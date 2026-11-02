-- Gen 2 navigation (decision 27): the world adapter, the Gen 2 coordinator's
-- object list, terrain, routing (side walls, ledges, ice, whirlpool,
-- waterfall, Surf, Cut, big objects), return warps, connections, signs,
-- field-move requirements, the floor-wide Strength puzzle search, auto-walk's
-- Gen 2 hooks and the shared-module fixes.  Synthetic maps built on the real
-- src/world/gen2/Map and Permissions; no cartridge data (that half is
-- gen2_nav_cart_test.lua).  Run: luajit tests/access/gen2_nav_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness")
local check, eq = T.check, T.eq

local Speech = require("src.access.Speech")
local spoken = {}
local fake = { name = "Fake" }
function fake:say(text) spoken[#spoken + 1] = text return true end
function fake:stop() return true end
function fake:close() end
Speech.shutdown()
Speech.start({ backend = fake })

local Gen2Map = require("src.world.gen2.Map")
local Events = require("src.world.gen2.Events")
local CmdQueue = require("src.world.gen2.CmdQueue")
local FieldMoves = require("src.world.gen2.FieldMoves")
local WorldAdapter = require("src.access.nav.WorldAdapter")
local Navigation2 = require("src.access.nav.gen2.Navigation")
local Snapshot2 = require("src.access.nav.gen2.WorldSnapshot")
local Terrain2 = require("src.access.nav.gen2.TerrainSemantics")
local Puzzle2 = require("src.access.nav.gen2.PuzzleAssistance")
local Pathfinder = require("src.access.nav.Pathfinder")

-- ------------------------------------------------------------ fixtures

local CODES = {
  ["."] = 0x00, ["#"] = 0x07, W = 0x29, I = 0x23, T = 0x12, P = 0x24,
  F = 0x33, v = 0xa3, U = 0xb2, D = 0x71, C = 0x70, O = 0x60, H = 0x15,
  B = 0x91, S = 0x7a, L = 0x72, G = 0x18,
}

-- A Gen 2 map from rows of collision letters; every Map method runs, only
-- the collision lookup is per cell instead of per block quad.
local function gridMap(id, rows, extra)
  extra = extra or {}
  local height, width = #rows, #rows[1]
  local grid = {}
  for y, row in ipairs(rows) do
    for x = 1, #row do grid[(y - 1) * width + (x - 1)] = CODES[row:sub(x, x)] end
  end
  local def = {
    id = id, width = width / 2, height = height / 2, warps = extra.warps or {},
    bgEvents = extra.bgEvents or {}, connections = extra.connections or {},
    objects = extra.objects or {}, landmark = extra.landmark, environment = "ROUTE",
  }
  local map = setmetatable({
    id = id, def = def, widthCells = width, heightCells = height,
    width = width / 2, height = height / 2, warps = def.warps,
    connections = def.connections, _warpAt = {},
  }, { __index = Gen2Map })
  for i, w in ipairs(def.warps) do map._warpAt[w.y * 1024 + w.x] = { index = i, def = w } end
  map.cellCollision = function(_, x, y)
    if x < 0 or y < 0 or x >= width or y >= height then return 0xff end
    return grid[y * width + x] or 0x07
  end
  return map
end

local function npc(id, x, y, def)
  def = def or {}
  def.index = def.index or 1
  return { id = id, cellX = x, cellY = y, def = def, facing = "down",
    bigObject = def.big == true }
end

local function newWorld(map, px, py, opts)
  opts = opts or {}
  local world = {
    map = map, player = { cellX = px, cellY = py, facing = opts.facing or "down", moving = false },
    npcs = opts.npcs or {}, events = Events.new(), maps = opts.maps or { [map.id] = map.def },
    cmdQueue = opts.cmdQueue or CmdQueue.new(), scripts = opts.scripts or {},
    playerState = opts.surfing and FieldMoves.PLAYER_SURF or FieldMoves.PLAYER_NORMAL,
    party = opts.party or {}, backupWarp = opts.backupWarp,
  }
  function world:scriptRunning() return self.running == true end
  function world:acceptsMenuInput() return true end
  function world:npcAt(x, y)
    for _, n in ipairs(self.npcs) do
      if n.bigObject then
        local dx, dy = x - n.cellX, y - n.cellY
        if dx >= 0 and dx < 2 and dy >= 0 and dy < 2 then return n end
      elseif n.cellX == x and n.cellY == y then return n end
    end
  end
  function world:partyMoveUser(move)
    for _, m in ipairs(self.party) do if m == move then return { moves = { move } } end end
    return nil
  end
  function world:itemIdByIndex(index) return ({ [28] = "IRON", [9] = "ANTIDOTE" })[index] end
  function world:objectTimeVisible() return true end
  function world:hour() return opts.hour or 14 end
  function world:minute() return opts.minute or 5 end
  function world:weekday() return 2 end
  function world:pollInput(input)
    self.polled = (self.polled or 0) + 1
    self.heldDir = nil
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      if input.state[d] then self.heldDir = d break end
    end
  end
  function world:cellCollisionAcross(m, x, y) return m:cellCollision(x, y) end
  return world
end

local events = { handlers = {} }
function events:on(name, fn) self.handlers[name] = fn return function() end end
function events:emit(name, payload) if self.handlers[name] then self.handlers[name](payload) end end

local function newGame(world, badges, stackTop)
  local stack = { states = {} }
  function stack:top() return stackTop end
  return {
    world = world, phase = "play", stack = stack,
    input = { sources = {}, pressQueue = {}, state = {} },
    save = { player = { name = "GOLD", badges = badges or {} }, rival = { name = "SILVER" },
             mom = { name = "MOM" }, options = {}, party = {} },
    data = { gen2Maps = world.maps, gen2Tilesets = {} },
  }
end

local speechAdapter = {
  isAvailable = function() return true end,
  output = function(_, text) spoken[#spoken + 1] = text return true end,
  stop = function() return true end,
}

local function newNav(game)
  events.handlers = {}
  return Navigation2.new(game, { speech = speechAdapter, events = events, enabled = true })
end

local function route(nav, goals, policy)
  local options = nav:worldRouteRequest(goals, policy or 1)
  if not options then return nil end
  return Pathfinder.find(options)
end

local function stepText(result)
  local parts = {}
  for _, s in ipairs(result and result.steps or {}) do
    parts[#parts + 1] = s.fromX .. "," .. s.fromY .. ">" .. s.direction .. (s.kind and ("/" .. s.kind) or "")
  end
  return table.concat(parts, " ")
end

-- ------------------------------------------------------------ adapter

do
  local map = gridMap("TEST_MAP", { "....", "..I.", "...." })
  local world = newWorld(map, 1, 1)
  local game = newGame(world)
  local A = WorldAdapter.gen2
  check(not A.scriptHeld(world), "adapter: a free world holds nobody")
  eq(A.top(game), world, "adapter: an empty stack with the world free is the map")
  check(A.onMap(game), "adapter: on the map")
  world.textbox = {}
  eq(A.top(game), WorldAdapter.BUSY, "adapter: a text box over the world is busy, not the map")
  world.textbox = nil
  world.moveState = {}
  eq(A.top(game), WorldAdapter.BUSY, "adapter: scripted movement is busy")
  world.moveState = nil
  world.mapSetup = {}
  check(A.transitioning(world), "adapter: a door fade is a transition")
  eq(A.top(game), world, "adapter: a door fade is not a screen")
  world.mapSetup = nil
  world.player.cellX, world.turningDirection = 2, "right"
  check(A.transitioning(world), "adapter: the latched direction on ice is a slide")
  world.turningDirection = nil
  check(not A.transitioning(world), "adapter: standing on ice without the latch is not")
  game.input.state.left = true
  A.afterSteer(game)
  eq(world.heldDir, "left", "adapter: afterSteer re-reads the held direction into the world")
  local battle = { isBattle = true }
  check(A.isBattle(battle), "adapter: Gen 2 battle screens carry isBattle")
end

-- ------------------------------------------------------------ facade, names, time

do
  local map = gridMap("PLAYERS_HOUSE_2F", { "....", "...." })
  local world = newWorld(map, 1, 1, { surfing = true, hour = 0, minute = 7 })
  local game = newGame(world)
  local nav = newNav(game)
  local facade = nav:worldState()
  eq(facade, nav:worldState(), "facade: one identity per live world")
  eq(facade.player.surfing, true, "facade: surfing from the world's player state")
  world.player = { cellX = 3, cellY = 0 }
  eq(facade.player.cellX, 3, "facade: reads the live player after a reload")
  eq(facade.entities[1], facade.player, "facade: entities start with the wrapped player")
  spoken = {}
  nav:handleCommand("read_map_name")
  eq(spoken[#spoken], "GOLD's House 2F", "map name: humanised id with the player's house")
  spoken = {}
  nav:handleCommand("read_game_time")
  eq(spoken[#spoken], "Tuesday, 12:07 AM, night", "Q: weekday, 12-hour clock with AM, daytime")
  check(Navigation2.normalize("OAK: Hello") == "OAK, Hello", "speaker labels still get a comma")
end

-- ------------------------------------------------------------ terrain

do
  local map = gridMap("SPROUT_TOWER_1F", { ".IvFP", "TH#BO", "WSLD." },
    { warps = { { x = 1, y = 2, destMap = "SPROUT_TOWER_2F", destWarp = 1 },
                { x = 2, y = 2, destMap = "SPROUT_TOWER_B1F", destWarp = 1 },
                { x = 4, y = 1, destMap = "SPROUT_TOWER_B1F", destWarp = 2 } } })
  local function kind(x, y) return Terrain2.classify(map, x, y, {}).kind end
  eq(kind(1, 0), "ice", "terrain: ice from COLL_ICE")
  eq(Terrain2.classify(map, 2, 0, {}).description, "Jump down", "terrain: ledge with its hop")
  eq(kind(3, 0), "waterfall", "terrain: waterfall")
  eq(kind(4, 0), "whirlpool", "terrain: whirlpool")
  eq(kind(0, 1), "cut_tree", "terrain: cuttable tree")
  eq(kind(1, 1), "headbutt_tree", "terrain: headbutt tree")
  eq(kind(4, 1), "hole", "terrain: pit under a warp is a hole")
  eq(kind(1, 2), "stairs_up", "terrain: staircase to a higher floor")
  eq(kind(2, 2), "ladder", "terrain: COLL_LADDER is a ladder")
  eq(kind(3, 2), "door", "terrain: door")
  eq(kind(0, 2), "water", "terrain: water")
  eq(Terrain2.classify(map, 9, 9, {}).label, "map edge", "terrain: outside is the map edge")
  local boulder = npc("b", 0, 0, { movement = 0x19 })
  eq(Terrain2.classify({ map = map, npcs = { boulder } }, 0, 0, {}).kind, "boulder",
    "terrain: a Strength boulder by its movement byte")
  check(not Terrain2.isBoulder(npc("d", 0, 0, { movement = 0x01, sprite = "SPRITE_BOULDER" })),
    "terrain: a boulder sprite that is not a Strength boulder is not one")
end

-- ------------------------------------------------------------ routing

local function routeWorld(rows, px, py, opts)
  local map = gridMap("ROUTE_TEST", rows, opts and opts.extra)
  local world = newWorld(map, px, py, opts)
  local game = newGame(world, opts and opts.badges)
  return newNav(game), world, game
end

do -- side walls: an UP_WALL refuses the step up off it and the step down onto it
  local nav = routeWorld({ "...", ".U.", "..." }, 1, 0)
  local r = route(nav, { { x = 1, y = 2 } })
  check(r and not stepText(r):find("1,0>down", 1, true), "side wall: no step down onto an up wall")
  nav = routeWorld({ "...", ".U.", "..." }, 1, 2)
  r = route(nav, { { x = 1, y = 0 } })
  check(r and stepText(r):find("1,2>up", 1, true) and not stepText(r):find("1,1>up", 1, true),
    "side wall: onto it from below, never up off it")
end

do -- ledges hop two cells off the ledge cell, one way only
  local nav = routeWorld({ "...", "vvv", "###", "..." }, 1, 0)
  local r = route(nav, { { x = 1, y = 3 } })
  eq(stepText(r), "1,0>down 1,1>down/ledge", "ledge: walk onto it, then hop")
  eq(nav:routeNarration(nil, r)[2], "Jump ledge down", "ledge: narrated as a jump")
  nav = routeWorld({ "...", "vvv", "###", "..." }, 1, 3)
  check(route(nav, { { x = 1, y = 0 } }) == nil, "ledge: never back up")
end

do -- ice slides as one edge, ending on the first cell off the ice or at a bump
  local nav = routeWorld({ ".III." }, 0, 0)
  local r = route(nav, { { x = 4, y = 0 } })
  eq(stepText(r), "0,0>right/ice", "ice: one edge over the strip")
  eq(nav:routeNarration(nil, r)[1], "Move right onto ice; slide 4 cells", "ice: narrated")
  check(route(nav, { { x = 2, y = 0 } }) == nil, "ice: a cell mid-slide is not a rest position")
  nav = routeWorld({ ".II#" }, 0, 0)
  r = route(nav, { { x = 2, y = 0 } })
  eq(stepText(r), "0,0>right/ice", "ice: a bump ends the slide on the last ice cell")
end

do -- a slide runs onto a warp and the warp fires (Ice Path B2F, audit): never a rest before it
  local extra = { warps = { { x = 0, y = 0, destMap = "ICE_PATH_B1F", destWarp = 1 } } }
  local rows = { "S...", "I...", "I...", "...." }
  local nav = routeWorld(rows, 0, 3, { extra = extra })
  local r = route(nav, { { x = 2, y = 0 } })
  check(r ~= nil and not stepText(r):find("0,3>up/ice", 1, true),
    "slide toward a warp: not planned as stopping short of it: " .. stepText(r))
  r = route(nav, { { x = 0, y = 0 } })
  eq(stepText(r), "0,3>up/ice", "slide onto the warp that is the goal: one move")
  local currentRows = { "S..", "P..", "..." }
  nav = routeWorld(currentRows, 0, 2, { extra = extra, surfing = true })
  r = route(nav, { { x = 2, y = 0 } })
  check(r == nil or not stepText(r):find("0,2>up", 1, true),
    "a current that carries onto a warp is not a way past it")
end

do -- Surf: entering water from land is a Surf use; the badge and a user are both needed
  local nav = routeWorld({ "..WW" }, 0, 0)
  check(route(nav, { { x = 3, y = 0 } }, 2) == nil, "surf: no route without Surf")
  nav = routeWorld({ "..WW" }, 0, 0, { party = { "SURF" } })
  check(route(nav, { { x = 3, y = 0 } }, 2) == nil, "surf: no route without the Fog Badge")
  nav = routeWorld({ "..WW" }, 0, 0, { party = { "SURF" }, badges = { FOG = true } })
  local r = route(nav, { { x = 3, y = 0 } }, 2)
  eq(stepText(r), "0,0>right 1,0>right/surf 2,0>right", "surf: used at the shore")
  eq(nav:routeNarration(nil, r)[2], "Use Surf facing right", "surf: narrated")
  nav = routeWorld({ "WW.WW" }, 0, 0, { surfing = true, party = { "SURF" }, badges = { FOG = true } })
  r = route(nav, { { x = 4, y = 0 } }, 1)
  check(r and stepText(r):find("2,0>right/surf", 1, true), "surf: back onto water after an island")
end

do -- Cut: "use, then move"; a missing badge is named as the badge
  local nav, _, game = routeWorld({ ".T." }, 0, 0, { party = { "CUT" } })
  check(route(nav, { { x = 2, y = 0 } }, 2) == nil, "cut: no route without the Hive Badge")
  eq(nav:routeRequirement({ { x = 2, y = 0 } }), "Needs Hive Badge", "cut: requirement names the badge")
  game.save.player.badges.HIVE = true
  local r = route(nav, { { x = 2, y = 0 } }, 2)
  eq(nav:routeNarration(nil, r)[1], "Use Cut facing right, then move right", "cut: narrated")
  eq(nav:stepInteraction(nil, r.steps[1]).move, "Cut", "cut: auto-walk presses A for it")
end

do -- whirlpool: Whirlpool and Surf, used from the water
  local nav = routeWorld({ "WPW" }, 0, 0, { surfing = true, party = { "SURF" }, badges = { FOG = true } })
  check(route(nav, { { x = 2, y = 0 } }, 2) == nil, "whirlpool: impassable without the move")
  nav = routeWorld({ "WPW" }, 0, 0, { surfing = true, party = { "SURF", "WHIRLPOOL" },
    badges = { FOG = true, GLACIER = true } })
  local r = route(nav, { { x = 2, y = 0 } }, 2)
  eq(stepText(r), "0,0>right/whirlpool 1,0>right", "whirlpool: lands on the cleared cell")
  eq(nav:routeNarration(nil, r)[1], "Use Whirlpool facing right, then move right", "whirlpool: narrated")
end

do -- waterfall: climbed whole from the water below, only with the move
  local rows = { "#.#", "#.#", "#F#", "#F#", "#W#" }
  local nav = routeWorld(rows, 1, 4, { surfing = true, party = { "SURF" }, badges = { FOG = true } })
  check(route(nav, { { x = 1, y = 1 } }, 2) == nil, "waterfall: no climb without Waterfall")
  nav = routeWorld(rows, 1, 4, { surfing = true, party = { "SURF", "WATERFALL" },
    badges = { FOG = true, RISING = true } })
  local r = route(nav, { { x = 1, y = 1 } }, 2)
  eq(stepText(r), "1,4>up/waterfall", "waterfall: one climb edge")
  eq(r.steps[1].y, 1, "waterfall: lands on the first cell above it, never itself")
  eq(nav:routeNarration(nil, r)[1], "Use Waterfall facing up, then climb 2 cells", "waterfall: narrated")
end

do -- a big object fills its 2x2
  local nav, world = routeWorld({ "....", "....", "....", "...." }, 0, 3)
  world.npcs = { npc("snorlax", 1, 1, { big = true }) }
  local r = route(nav, { { x = 3, y = 0 } })
  local text = stepText(r)
  check(r and not text:find("2,2", 1, true) and not text:find("1,2", 1, true),
    "big object: no route through any of its four cells")
end

do -- warps are walls unless they are the goal
  local nav = routeWorld({ "...", ".D.", "..." }, 1, 0,
    { extra = { warps = { { x = 1, y = 1, destMap = "X", destWarp = 1 } } } })
  local r = route(nav, { { x = 1, y = 2 } })
  check(r and not stepText(r):find("1,0>down", 1, true), "warp: walked around when not the goal")
  r = route(nav, { { x = 1, y = 1 } })
  eq(stepText(r), "1,0>down", "warp: entered when it is the goal")
end

-- ------------------------------------------------------------ object list

do
  local extra = {
    warps = {
      { x = 0, y = 0, destMap = "POKECENTER_2F", destWarp = 0xff },
      { x = 3, y = 0, destMap = "ROUTE_29", destWarp = 1 },
      { x = 4, y = 3, destMap = "ICE_PATH_B2F", destWarp = 1 },
    },
    connections = { west = { map = 26, mapId = "ROUTE_29", offset = 0 } },
    bgEvents = {
      { x = 1, y = 1, kind = 0, scriptKey = "1e:6c15" },
      { x = 2, y = 1, kind = 1, scriptKey = "1e:6c16" },
      { x = 3, y = 3, kind = 7, hiddenItem = { item = 15, event = 3 } },
      { x = 1, y = 3, kind = 8 },
      { x = 0, y = 2, kind = 5, event = 40, scriptKey = "1e:aaaa" },
      { x = 5, y = 1, kind = 0, scriptKey = "1e:bbbb" },
    },
    objects = {},
  }
  local rows = { "D..D..", "...#.B", "......", "...TO.", "HH...." }
  local map = gridMap("NEW_BARK_TOWN", rows, extra)
  local world = newWorld(map, 2, 2, { maps = {
    NEW_BARK_TOWN = map.def, ROUTE_29 = { id = "ROUTE_29" }, POKECENTER_2F = { id = "POKECENTER_2F" },
  } })
  world.npcs = {
    npc("NEW_BARK_TOWN_obj_1", 5, 4, { index = 1, sprite = "SPRITE_POKE_BALL", itemball = { item = 28 } }),
    npc("NEW_BARK_TOWN_obj_2", 0, 3, { index = 2, sprite = 240 }),
    npc("NEW_BARK_TOWN_obj_3", 5, 2, { index = 3, sprite = "SPRITE_ROCK", movement = 0x18 }),
  }
  world.npcs[2].spriteDef = { id = "SPRITE_CONSOLE" }
  local game = newGame(world)
  local nav = newNav(game)
  local snap = nav:captureWorld("all")
  local labels, byLabel = {}, {}
  for _, item in ipairs(snap.browse) do labels[#labels + 1] = item.label byLabel[item.label] = item end
  local all = table.concat(labels, " | ")
  check(byLabel["Exit"] ~= nil, "0xFF warp unresolved: named Exit, not the room itself: " .. all)
  check(not all:find("Pokecenter", 1, true), "0xFF warp never spoken as the map it names")
  check(byLabel["West connection to Route 29"] ~= nil, "connection named from mapId, not the number")
  check(byLabel["Signpost 1"] ~= nil, "bg event 1 is Signpost 1")
  eq(byLabel["Signpost 2"] and byLabel["Signpost 2"].requiredFacing, "up",
    "a facing-only sign keeps its facing")
  check(not all:find("1e:", 1, true), "a sign's script address is never spoken")
  check(byLabel["Signpost 3"] == nil and byLabel["Signpost 4"] == nil,
    "hidden items and copy events are not listed (as in Gen 1)")
  check(byLabel["Signpost 5"] == nil, "an if-set sign is listed only while its flag is set")
  world.events:set(40, true)
  snap = nav:captureWorld("all")
  local found5 = false
  for _, item in ipairs(snap.browse) do if item.label == "Signpost 5" then found5 = true end end
  check(found5, "the if-set sign appears once its flag is set")
  check(byLabel["Bookshelf"] ~= nil, "a sign on a bookshelf tile is the Bookshelf")
  local shelves = 0
  for _, l in ipairs(labels) do if l == "Bookshelf" then shelves = shelves + 1 end end
  eq(shelves, 1, "the bookshelf is listed once")
  eq(byLabel["Cuttable Tree"] and byLabel["Cuttable Tree"].requirement, "Needs Cut and Hive Badge",
    "cut tree: the real missing pieces")
  eq(byLabel["Headbutt Tree"] and byLabel["Headbutt Tree"].requirement, "Needs Headbutt",
    "headbutt tree: needs a party member, no badge")
  eq(#byLabel["Headbutt Tree"].interactionCells, 2, "two headbutt cells side by side are one object")
  check(byLabel["Iron"] ~= nil, "item ball named by its item, looked up by index")
  check(byLabel["Console"] ~= nil, "a variable sprite named by the resolved sheet")
  eq(byLabel["Smashable Rock"] and byLabel["Smashable Rock"].requirement, "Needs Rock Smash",
    "smashable rock with its requirement")
  local hole
  for _, item in ipairs(snap.browse) do if item.label:find("^Drop to") then hole = item end end
  check(hole and hole.category == "objects", "a pit warp is listed as a drop under objects")

  world.party = { "CUT", "HEADBUTT", "ROCK_SMASH" }
  game.save.player.badges.HIVE = true
  snap = nav:captureWorld("all")
  for _, item in ipairs(snap.browse) do byLabel[item.label] = item end
  eq(byLabel["Cuttable Tree"].requirement, nil, "cut tree: no requirement once usable (the old 'and nil or' bug)")
  eq(byLabel["Headbutt Tree"].requirement, nil, "headbutt tree: no requirement once usable")

  world.backupWarp = { map = "ROUTE_29", warp = 1 }
  snap = nav:captureWorld("all")
  local resolved
  for _, item in ipairs(snap.browse) do
    for _, cell in ipairs(item.navigationCells or {}) do
      if item.type == "warp" and cell.x == 0 and cell.y == 0 then resolved = item end
    end
  end
  eq(resolved and resolved.label, "Route 29", "0xFF warp resolved through the backup warp")
  local dest, warpNumber = nav:regionalResolveWarp(extra.warps[1])
  eq(dest, "ROUTE_29", "cross-map planner resolves the 0xFF warp the same way")
  eq(warpNumber, 1, "and its arrival warp")
end

do -- standard tiles without signs, and a waterfall object faced from below
  local nav = select(1, routeWorld({ "B..F", "B..F", "...W" }, 1, 1))
  local snap = nav:captureWorld("all")
  local wf
  for _, item in ipairs(snap.browse) do if item.label == "Waterfall" then wf = item end end
  check(wf and wf.requiredFacing == "up" and #wf.interactionCells == 1 and wf.interactionCells[1].y == 1,
    "waterfall object: climbed from below its bottom cell")
end

-- ------------------------------------------------------------ labels from the game's data (audit)
-- Signs named by the standard script they run, neighbouring signs with one
-- script as one object, Pokemon named by the species their script cries
-- (the cartridge reuses its species sheets: GROWLITHE's for a MEOWTH), and
-- sheet names that are not who stands there.

do
  local extra = {
    bgEvents = {
      { x = 0, y = 0, kind = 0, scriptKey = "trash" },                 -- 1: Trash Can
      { x = 2, y = 0, kind = 0, scriptKey = "statue" },                -- 2: Gym Statue (via a branch)
      { x = 4, y = 0, kind = 0, scriptKey = "slots" },                 -- 3: Slot Machine row,
      { x = 5, y = 0, kind = 0, scriptKey = "slots" },                 --    one object
      { x = 7, y = 0, kind = 0, scriptKey = "panel" },                 -- 5: Floor Panel
      { x = 0, y = 2, kind = 0, scriptKey = "plain" },                 -- 6: Signpost 6, three cells
      { x = 1, y = 2, kind = 0, scriptKey = "plain" },
      { x = 1, y = 3, kind = 0, scriptKey = "plain" },
      { x = 3, y = 2, kind = 0, scriptKey = "plain" },                 -- 9: not touching: its own
      { x = 4, y = 2, kind = 1, scriptKey = "plain" },                 -- 10: other kind: its own
    },
  }
  local rows = { "........", "........", "........", "........", "........", "........" }
  local map = gridMap("GAME_CORNER", rows, extra)
  local world = newWorld(map, 6, 5, { scripts = {
    trash = { { op = "jumpstd", std = "TrashCanScript" } },
    statue = { { op = "checkflag", flag = 3 }, { op = "iftrue", script = "statue2" },
               { op = "jumptext", text = "x" } },
    statue2 = { { op = "jumpstd", std = "GymStatue2Script" } },
    slots = { { op = "random", value = 6 }, { op = "special", id = 1 } },
    panel = { { op = "opentext" }, { op = "elevator", floors = {} } },
    plain = { { op = "jumptext", text = "1b:5da7" } },
    meowth = { { op = "faceplayer" }, { op = "opentext" }, { op = "cry", id = 52 } },
  } })
  world.constants = { specialOrder = { "PlaceMoneyTopRight", "SlotMachine" },
    speciesOrder = { [52] = "MEOWTH", [83] = "FARFETCH_D" } }
  world.npcs = {
    npc("GAME_CORNER_obj_1", 7, 3, { index = 1, sprite = "SPRITE_GROWLITHE", scriptKey = "meowth" }),
    npc("GAME_CORNER_obj_2", 7, 4, { index = 2, sprite = "SPRITE_GROWLITHE", scriptKey = "plain" }),
    npc("GAME_CORNER_obj_3", 6, 3, { index = 3, sprite = "SPRITE_MONSTER", scriptKey = "plain" }),
    npc("GAME_CORNER_obj_4", 5, 4, { index = 4, sprite = "SPRITE_CHRIS" }),
    npc("GAME_CORNER_obj_5", 4, 4, { index = 5, sprite = "SPRITE_STANDING_YOUNGSTER" }),
    npc("GAME_CORNER_obj_6", 3, 4, { index = 6, sprite = "SPRITE_POKE_BALL", itemball = { item = 28 } }),
  }
  world.npcs[1].spriteDef = { id = "SPRITE_GROWLITHE", source = "ROM:SpriteMons[2]" }
  world.npcs[2].spriteDef = { id = "SPRITE_GROWLITHE", source = "ROM:SpriteMons[2]" }
  world.npcs[3].spriteDef = { id = "SPRITE_MONSTER", source = "ROM:OverworldSprites[75]" }
  local game = newGame(world)
  game.data.pokemon = { MEOWTH = { name = "MEOWTH" }, FARFETCH_D = { name = "FARFETCH'D" } }
  local nav = newNav(game)
  local snap = nav:captureWorld("all")
  local byLabel, counts, labels = {}, {}, {}
  for _, item in ipairs(snap.browse) do
    byLabel[item.label] = byLabel[item.label] or item
    counts[item.label] = (counts[item.label] or 0) + 1
    labels[#labels + 1] = item.label
  end
  local all = table.concat(labels, " | ")
  check(byLabel["Trash Can"] ~= nil, "a sign running TrashCanScript is the Trash Can: " .. all)
  check(byLabel["Gym Statue"] ~= nil, "a std script reached through a branch names the sign")
  eq(counts["Slot Machine"], 1, "two neighbouring slot machines with one script are one object")
  eq(byLabel["Slot Machine"] and #byLabel["Slot Machine"].interactionCells, 2,
    "and both machines can be faced")
  check(byLabel["Floor Panel"] ~= nil, "the elevator command names the car's panel")
  eq(byLabel["Signpost 6"] and #byLabel["Signpost 6"].interactionCells, 3,
    "three touching signs with one script are one Signpost, keeping the first ordinal")
  check(byLabel["Signpost 7"] == nil and byLabel["Signpost 8"] == nil, "the grouped signs are not listed again")
  check(byLabel["Signpost 9"] ~= nil, "a sign with the same script but not touching is its own object")
  check(byLabel["Signpost 10"] ~= nil and byLabel["Signpost 10"].requiredFacing == "up",
    "a facing-only sign is not merged into a read-from-anywhere one")
  local goals = nav:interactionGoals(nav:worldState(), byLabel["Signpost 6"])
  local fromBelow = false
  for _, goal in ipairs(goals) do if goal.x == 1 and goal.y == 4 then fromBelow = true end end
  check(fromBelow, "a grouped sign is approached from any of its cells (below the third)")

  check(byLabel["Meowth"] ~= nil, "a GROWLITHE sheet whose script cries MEOWTH is the Meowth")
  check(byLabel["Growlithe"] == nil, "the reused sheet's name is never spoken")
  eq(counts["Pok\195\169mon"], 1, "a species sheet with no cry says only Pokemon")
  check(byLabel["Monster"] ~= nil, "a shape sheet with no cry keeps its shape")
  check(byLabel["Trainer"] ~= nil and byLabel["Chris"] == nil, "the player's sheet on someone else is a Trainer")
  check(byLabel["Youngster"] ~= nil, "a pose variant names the person")
  check(byLabel["Iron"] ~= nil, "item balls keep their item")

  world.npcs[2].def.scriptKey = "bird"
  world.scripts.bird = { { op = "cry", id = 83 } }
  snap = nav:captureWorld("all")
  local bird
  for _, item in ipairs(snap.browse) do if item.label == "Farfetch'd" then bird = item end end
  check(bird ~= nil, "species names are said as the game prints them, title case (Farfetch'd)")
end

do -- the rival before he is named: "???" may be said as nothing at all
  local map = gridMap("SPROUT_TOWER_3F", { "....", "...." })
  local world = newWorld(map, 0, 0)
  world.npcs = { npc("SPROUT_TOWER_3F_obj_1", 3, 1, { index = 1, sprite = "SPRITE_RIVAL" }) }
  local game = newGame(world)
  game.save.rival.name = "???"
  local nav = newNav(game)
  local function rivalLabel()
    for _, item in ipairs(nav:captureWorld("all").browse) do
      if item.id == "SPROUT_TOWER_3F_obj_1" then return item.label end
    end
  end
  eq(rivalLabel(), "Rival", "an unnamed rival (a new game's ???) is Rival")
  game.save.rival.name = "SILVER"
  eq(rivalLabel(), "SILVER", "once named, the rival is his name")
end

do -- spoken forms of abbreviations in generated ids (shared humanize)
  local Shared = require("src.access.nav.WorldSnapshot")
  eq(Shared.humanize("PP_UP"), "PP Up", "PP stays PP")
  eq(Shared.humanize("HP_UP"), "HP Up", "HP stays HP")
  eq(Shared.humanize("WHIRL_ISLAND_NE"), "Whirl Island NE", "compass points stay capitals")
  eq(Shared.humanize("FAST_SHIP_CABINS_SW_SSW_NW"), "Fast Ship Cabins SW SSW NW", "three-letter points too")
  eq(Shared.humanize("LAV_RADIO_TOWER_1F"), "Lavender Radio Tower 1F", "Lav is Lavender")
end

-- ------------------------------------------------------------ cues and terrain query

do
  local map = gridMap("ICE_PATH_1F", { ".I.v", "...." })
  local world = newWorld(map, 1, 0)
  local game = newGame(world)
  local nav = newNav(game)
  local cues = {}
  nav.earcons = { play = function(_, id) cues[#cues + 1] = id return true end,
    setEnabled = function() end, stop = function() end }
  events:emit("world.stepped", { mapId = "ICE_PATH_1F", x = 1, y = 0 })
  nav:processWorldEvents(nil)
  eq(cues[#cues], "ice", "footstep: a step onto ice cues ice (transient or not)")
  world.player.cellX = 3
  events:emit("world.stepped", { mapId = "ICE_PATH_1F", x = 3, y = 0 })
  nav:processWorldEvents(nil)
  eq(cues[#cues], "ledge", "footstep: a ledge cell cues the ledge once")
  eq(#cues, 2, "footstep: no second adjacent-ledge cue on Gen 2")
  world.textbox = {}
  world.player.cellX = 1
  events:emit("world.stepped", { mapId = "ICE_PATH_1F", x = 1, y = 0 })
  nav:processWorldEvents(nil)
  eq(#cues, 2, "footstep: nothing cued under a text box")
  world.textbox = nil
  spoken = {}
  nav.sonarMapId, nav.sonarX, nav.sonarY = "ICE_PATH_1F", 1, 0
  nav:handleCommand("read_terrain")
  eq(spoken[#spoken - 1] or spoken[#spoken], "Sonar x 1, y 0. ice", "Shift+E: the cell's terrain")
end

-- ------------------------------------------------------------ landmark sign

do
  local map = gridMap("BLACKTHORN_GYM_2F", { "...." })
  local world = newWorld(map, 1, 0)
  local game = newGame(world)
  local nav = newNav(game)
  spoken = {}
  world.mapSign = { name = "BLACKTHORN CITY" }
  nav:processWorldEvents(nil)
  eq(spoken[#spoken], "Blackthorn City", "Crystal's entry sign is spoken")
  local count = #spoken
  nav:processWorldEvents(nil)
  eq(#spoken, count, "the same sign is spoken once")
  world.mapSign = { name = "BLACKTHORN GYM" }
  nav:processWorldEvents(nil)
  eq(#spoken, count, "a sign repeating the map name is not spoken again")
end

-- ------------------------------------------------------------ puzzle

local function puzzleWorld(rows, px, py, boulders, rowsTable, scripts)
  local map = gridMap("PUZZLE_TEST", rows, { warps = rowsTable.warps })
  local world = newWorld(map, px, py, { scripts = scripts })
  world.npcs = boulders
  world.strengthActive = true
  CmdQueue.write(world.cmdQueue, { kind = CmdQueue.STONETABLE, rows = rowsTable.rows, mapId = "PUZZLE_TEST" })
  local game = newGame(world, { PLAIN = true })
  world.party = { "STRENGTH" }
  return world, game
end

do -- one boulder, one hole: the next push and the pushing position
  local rows = { ".....", ".....", ".....", "..O..", "....." }
  local warps = { { x = 2, y = 3, destMap = "BELOW", destWarp = 1 } }
  local boulder = npc("PUZZLE_TEST_obj_1", 2, 1, { index = 1, movement = 0x19 })
  local script = { { op = "disappear", object = 2 } }
  local world, game = puzzleWorld(rows, 0, 0, { boulder },
    { warps = warps, rows = { { warp = 1, object = 2, script = script } } })
  local nav = newNav(game)
  local result = Puzzle2.describe(game, nav:worldState())
  local action = result.nextAction
  check(action ~= nil, "puzzle: a next push is planned")
  eq(action and action.direction, "down", "puzzle: push the boulder down toward the hole")
  eq(action and (action.standX .. "," .. action.standY), "2,0", "puzzle: standing above it")
  eq(action and action.instruction, "push down toward Hole 1", "puzzle: Strength already on, no prefix")
  eq(result.targetStates[1].state, "empty; Boulder 1 can reach it; next push down", "puzzle: hole state")
  world.strengthActive = false
  result = Puzzle2.describe(game, nav:worldState())
  eq(result.nextAction.instruction, "Use Strength from the party menu; push down toward Hole 1",
    "puzzle: says to switch Strength on first")
  world.party = {}
  result = Puzzle2.describe(game, nav:worldState())
  check(result.nextAction.instruction:find("^Needs a party Pok"), "puzzle: names a missing Strength user")
  -- the hole is filled once its boulder is gone
  world.party, world.strengthActive, world.npcs = { "STRENGTH" }, true, {}
  result = Puzzle2.describe(game, nav:worldState())
  eq(result.targetStates[1].state, "filled", "puzzle: a hole whose boulder fell is filled")
  eq(result.nextAction, nil, "puzzle: nothing left to push")
  -- the stone row must really drop that boulder
  world.npcs = { boulder }
  world.cmdQueue = CmdQueue.new()
  CmdQueue.write(world.cmdQueue, { kind = CmdQueue.STONETABLE, mapId = "PUZZLE_TEST",
    rows = { { warp = 1, object = 2, script = { { op = "disappear", object = 9 } } } } })
  result = Puzzle2.describe(game, nav:worldState())
  eq(result.nextAction, nil, "puzzle: a row whose script drops another object promises nothing")
end

do -- a boulder in no row blocks the way: push it aside first
  -- the player starts at (2,2); Boulder 2 (no row) at (1,2) closes the only
  -- way up; Boulder 1 at (3,0) goes right into the hole at (5,0)
  local rows = {
    "#....O#",
    "#.#####",
    "...####",
  }
  local warps = { { x = 5, y = 0, destMap = "BELOW", destWarp = 1 } }
  local target = npc("P_obj_1", 3, 0, { index = 1, movement = 0x19 })
  local blocker = npc("P_obj_2", 1, 2, { index = 2, movement = 0x19 })
  local world, game = puzzleWorld(rows, 2, 2, { target, blocker },
    { warps = warps, rows = { { warp = 1, object = 2, script = { { op = "disappear", object = 2 } } } } })
  local nav = newNav(game)
  local result = Puzzle2.describe(game, nav:worldState())
  local over = result.objectOverrides
  check(result.nextAction ~= nil, "floor search: a plan through the blocking boulder")
  eq(result.nextAction and result.nextAction.boulderLabel, "Boulder 2", "floor search: the blocker moves first")
  eq(over.P_obj_2 and over.P_obj_2.stateText, "next push left, to clear the way for Boulder 1",
    "floor search: says why")
  eq(over.P_obj_1 and over.P_obj_1.stateText, "goes in Hole 1", "floor search: the target boulder waits")
  check(result.targetStates[1].state:find("first push Boulder 2 left", 1, true),
    "floor search: the hole names the first push")
end

-- ------------------------------------------------------------ auto-walk hooks

do
  package.loaded["src.access.nav.Pathfinder"] = nil
  local AutoWalk = require("src.access.nav.AutoWalk")
  local relatched = 0
  local adapter = setmetatable({ afterSteer = function() relatched = relatched + 1 end },
    { __index = WorldAdapter.gen2 })
  local map = gridMap("HOUSE", { "...", "...", "..C" },
    { warps = { { x = 2, y = 2, destMap = "TOWN", destWarp = 1 } } })
  local world = newWorld(map, 0, 2)
  local game = newGame(world)
  local nav = newNav(game)
  local facade = nav:worldState()
  local fakeNav = setmetatable({
    selectedRouteGoals = function()
      return { label = "Town", type = "warp", destinationMapId = "TOWN" }, { { x = 2, y = 2 } }, nil, nil, facade
    end,
    worldRouteRequest = function() return {} end,
  }, { __index = nav })
  package.loaded["src.access.nav.Pathfinder"] = {
    find = function() return { steps = {
      { fromX = 0, fromY = 2, x = 1, y = 2, direction = "right" },
      { fromX = 1, fromY = 2, x = 2, y = 2, direction = "right" } }, goal = { x = 2, y = 2 } } end,
  }
  AutoWalk._resetForTests()
  check(AutoWalk.start(fakeNav, game, adapter), "auto-walk (Gen 2): starts")
  AutoWalk.update(WorldAdapter.BUSY)
  check(AutoWalk.active() and not AutoWalk.walking(), "auto-walk (Gen 2): a busy world pauses the walk")
  AutoWalk.update(world)
  check(AutoWalk.walking(), "auto-walk (Gen 2): the free World resumes it")
  AutoWalk.update(world)
  eq(game.input.state.right, true, "auto-walk (Gen 2): the World as top is the map")
  world.player.cellX = 1
  AutoWalk.stepped(1, 2)
  world.player.cellX = 2
  AutoWalk.stepped(2, 2)
  eq(game.input.state.down, true, "auto-walk (Gen 2): a carpet warp gets its own direction held")
  check(relatched > 0, "auto-walk (Gen 2): the change is re-latched inside the step")
  AutoWalk.update(world)
  check(AutoWalk.active(), "auto-walk (Gen 2): keeps pressing on the carpet instead of announcing arrival")
  local stack = package.loaded["src.core.StateStack"]
  package.loaded["src.core.StateStack"] = { states = { { isBattle = true } } }
  AutoWalk.pause(true)
  AutoWalk.update({ isBattle = true })
  package.loaded["src.core.StateStack"] = { states = {} }
  AutoWalk.update(world)
  check(AutoWalk.walking() or not AutoWalk.active(), "auto-walk (Gen 2): a Gen 2 battle counts as the expected battle")
  package.loaded["src.core.StateStack"] = stack
  AutoWalk._resetForTests()
  package.loaded["src.access.nav.Pathfinder"] = nil
end

-- ------------------------------------------------------------ shared fixes

do
  local map = gridMap("X_MAP", { "..." })
  local world = newWorld(map, 0, 0)
  local game = newGame(world)
  local nav = newNav(game)
  events:emit("battle.damage_dealt", { damage = 5, battle = {}, target = {} })
  eq(nav.pendingBattleDamage, nil, "battle damage is not queued for a coordinator that never drains it")
  nav.pendingBattleDamage = { { battle = {}, damage = 3 } }
  local ok = pcall(nav.processBattleEvents, nav, nil)
  check(ok, "processBattleEvents on Gen 2 no longer calls a missing method")
  eq(#nav.pendingBattleDamage, 0, "and drops the fact")
  local Shared = require("src.access.nav.Navigation")
  eq(Shared.normalize("Sunday, 10:00 AM"), "Sunday, 10:00 AM", "a clock time is not a speaker label")
end

do -- the shared journey's last leg keeps only target cells inside the map
  local Shared = require("src.access.nav.Navigation")
  local map = { id = "SMALL", inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 4 and y < 4 end }
  local nav = setmetatable({
    worldForCommand = function() return { map = map, player = { cellX = 1, cellY = 1 } } end,
    regionalDryRoute = function() return { cost = 1 } end,
    regionalTransitions = function() return {} end,
  }, { __index = Shared })
  local leg = nav:regionalNextLeg({ targetMapId = "SMALL",
    targetGoals = { { x = 2, y = 3 }, { x = 2, y = 4 } } })
  check(leg and leg.final, "a target on this map is the final leg")
  eq(leg and #leg.goals, 1, "a goal cell outside this map (worked out on a bigger one) is dropped")
end

Speech.shutdown()
T.finish("gen2 navigation")
