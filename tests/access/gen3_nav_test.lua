-- FireRed navigation (decision 29): script shapes, names, map views (warp
-- kinds, standing warps, cached cells), the movement graph (ledges, doors,
-- mats, spinners, ice, Surf, Cut trees, connections), the Strength floor
-- search, the world adapter's battle marker and options block, auto-walk's
-- battle-marker pause and the session binding.  Synthetic maps on the real
-- src/core/game3/collision.lua and src/world/gen2/Permissions.lua; no
-- cartridge data (that half is drivers/gen3_nav_sweep.lua, in the game).
-- Run: luajit tests/access/gen3_nav_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness")
local check, eq = T.check, T.eq

local Speech = require("src.access.Speech")
local fake = { name = "Fake" }
function fake:say() return true end
function fake:stop() return true end
function fake:close() end
Speech.shutdown()
Speech.start({ backend = fake })

local InteractionScripts = require("src.core.game3.scripting.interaction_scripts")
local World = require("src.access.nav.gen3.World")
local Scripts = require("src.access.nav.gen3.Scripts")
local Snapshot = require("src.access.nav.gen3.WorldSnapshot")
local Puzzle = require("src.access.nav.gen3.PuzzleAssistance")
local Navigation3 = require("src.access.nav.gen3.Navigation")
local WorldAdapter = require("src.access.nav.WorldAdapter")
local Pathfinder = require("src.access.nav.Pathfinder")
local AutoWalk = require("src.access.nav.AutoWalk")

-- ------------------------------------------------------------ fixtures
-- One character per cell: { coll, behaviour, elevation }.
local CELL = {
  ["."] = { 0x00, 0x00, 3 }, ["#"] = { 0x07, 0x00, 3 }, ["L"] = { 0xA3, 0x3B, 3 },
  ["W"] = { 0x71, 0x61, 3 }, ["D"] = { 0x71, 0x69, 3 }, ["M"] = { 0x71, 0x65, 3 },
  [">"] = { 0x00, 0x54, 3 }, ["^"] = { 0x00, 0x56, 3 }, ["x"] = { 0x00, 0x58, 3 },
  ["I"] = { 0x00, 0x23, 3 }, ["~"] = { 0x29, 0x10, 1 }, ["S"] = { 0x00, 0x20, 3 },
  ["H"] = { 0x71, 0x66, 3 }, ["c"] = { 0x00, 0x27, 3 },
}
InteractionScripts.behaviors.testpair = setmetatable({}, { __index = function(_, mid) return mid - 1000 end })

local function layout(rows)
  local height, width = #rows, #rows[1]
  local L = { width = width, height = height, pair = "testpair", _revision = 0, overrides = {} }
  local function cell(x, y)
    local ch = rows[y + 1] and rows[y + 1]:sub(x + 1, x + 1)
    return CELL[ch] or CELL["#"]
  end
  function L:midAt(x, y) return cell(x, y)[2] + 1000 end
  function L:collAt(x, y)
    if x < 0 or y < 0 or x >= width or y >= height then return 0xff end
    return cell(x, y)[1]
  end
  function L:elevAt(x, y) return cell(x, y)[3] end
  return L
end

local function mapDef(id, rows, warps, extra)
  local def = { id = id, pair = "testpair", warps = warps or {}, connections = {}, objects = {}, bgEvents = {} }
  for k, v in pairs(extra or {}) do def[k] = v end
  def.midLayout = layout(rows)
  return def
end

local doors = {}
package.loaded["src.core.game3.doors"] = {
  getDoorEntryAt = function(mapId, x, y) return doors[mapId .. ":" .. x .. "," .. y] end,
}

local maps = {}
local game = { data = { maps = maps }, input = { sources = {}, pressQueue = {}, state = {} },
  generation = 3, session = { party = {}, bag = { pockets = {} } }, options = { firered = {} } }

-- A coordinator over a planned view, with the field moves the test allows.
local allowed = {}
local function navFor()
  local nav = setmetatable({ game = game, enabled = false }, { __index = Navigation3 })
  nav.fieldMoveStatus = function(_, move)
    if allowed[move] then return true, false, nil end
    return false, true, nil
  end
  nav.hasCardKey = function() return false end
  return nav
end

local function worldOn(def, x, y, npcs, surfing)
  local view = World.plannedView(game, def)
  return { map = view, player = { cellX = x, cellY = y, surfing = surfing == true }, npcs = npcs or {},
    isOverworld = true }
end

local function route(nav, world, goals, policy)
  local options = nav:routeOptionsFor(world, goals, policy or 2)
  local result = Pathfinder.find(options)
  return result
end

local function kinds(result)
  local list = {}
  for _, step in ipairs(result and result.steps or {}) do list[#list + 1] = step.direction .. (step.kind and ("(" .. step.kind .. ")") or "") end
  return table.concat(list, " ")
end

-- ------------------------------------------------------------ scripts
do
  Scripts.setSpecialNames({ [347] = "SetVermilionTrashCans", [216] = "GetElevatorFloor", [142] = "DrawWholeMapView" })
  Scripts.setSource({
    ball = { { op = "setorcopyvar", 0x8000, 355 }, { op = "setorcopyvar", 0x8001, 1 }, { op = "callstd", std = 1 } },
    gift = { { op = "setorcopyvar", 0x8000, 13 }, { op = "callstd", std = 0 } },
    door = { { op = "checkflag", flag = 640 }, { op = "goto_if", target = "open" }, { op = "goto", target = "unlock" } },
    unlock = { { op = "playfanfare" }, { op = "setmetatile" }, { op = "special", id = 142 } },
    open = { { op = "callstd", std = 4 } },
    switch = { { op = "callstd", std = 5 }, { op = "checkflag", flag = 620 }, { op = "setflag", flag = 620 },
      { op = "call", target = "gates" } },
    gates = { { op = "setmetatile" } },
    quiz = { { op = "callstd", std = 5 }, { op = "trainerbattle" }, { op = "setmetatile" } },
    trash = { { op = "special", id = 347 } },
    panel = { { op = "special", id = 216 } },
    plain = { { op = "callstd", std = 3 } },
  })
  eq(Scripts.itemBallItem("ball"), 355, "item ball script names its item")
  eq(Scripts.itemBallItem("gift"), nil, "a gift script (callstd 0) is not an item ball")
  eq(Scripts.itemBallItem("missing"), nil, "an unknown script names nothing")
  eq(Scripts.signRole("door"), "Card Key Door", "flag check plus fanfare and setmetatile is a card key door")
  eq(Scripts.signRole("switch"), "Secret Switch", "yes/no toggling a flag and setting metatiles is a secret switch")
  eq(Scripts.signRole("quiz"), "Quiz Machine", "yes/no with a trainer battle is a quiz machine")
  eq(Scripts.signRole("trash"), "Trash Can", "SetVermilionTrashCans names a trash can")
  eq(Scripts.signRole("panel"), "Floor Panel", "GetElevatorFloor names the floor panel")
  eq(Scripts.signRole("plain"), nil, "a plain sign keeps Signpost N")
  eq(Scripts.titleCase("KING'S ROCK"), "King's Rock", "apostrophes kept in title case")
  eq(Scripts.titleCase("POK\195\169 BALL"), "Pok\195\169 Ball", "Poke Ball title case keeps the accent")
  eq(Scripts.titleCase("TM05"), "TM 05", "TM numbers spaced")
  eq(Scripts.titleCase("PP UP"), "PP Up", "PP kept in capitals")
end

-- ------------------------------------------------------------ names
do
  eq(Snapshot.mapIdName("FR_VIRIDIAN_CITY_POKEMON_CENTER_1F"), "Viridian City Pok\195\169mon Center 1F", "map id humanised without its prefix")
  eq(Snapshot.mapIdName("FR_SSANNE_1F_CORRIDOR"), "S.S. Anne 1F Corridor", "S.S. Anne spelled out")
  eq(Snapshot.mapIdName("FR_OAKS_LAB"), "Oak's Lab", "possessives restored")
  eq(Snapshot.locationName({ id = "FR_PLAYERS_HOUSE_2F" }, nil, nil, "RED"), "RED's House 2F", "player's house named after the player")
  eq(Snapshot.locationName({ id = "FR_RIVALS_HOUSE" }, nil, nil, "RED", "BLUE"), "BLUE's House", "rival's house named after the rival")
  eq(Snapshot.locationName({ id = "FR_ROUTE_1" }, nil, "Home Road"), "Home Road", "a rename wins")
  Snapshot.setGraphicsNames({ [72] = "OBJ_EVENT_GFX_BLUE", [23] = "OBJ_EVENT_GFX_WOMAN_1",
    [0] = "OBJ_EVENT_GFX_RED_NORMAL", [71] = "OBJ_EVENT_GFX_PROF_OAK", [97] = "OBJ_EVENT_GFX_PUSHABLE_BOULDER" })
  eq(Snapshot.objectLabel({ graphicsId = 72, def = {} }, { rivalName = "GARY" }), "GARY", "Blue's sheet named as the rival")
  eq(Snapshot.objectLabel({ graphicsId = 23, def = {} }, {}), "Woman", "people named by graphics, number dropped")
  eq(Snapshot.objectLabel({ graphicsId = 0, def = {} }, {}), "Trainer", "the player's sheet on someone else is a Trainer")
  eq(Snapshot.objectLabel({ graphicsId = 71, def = {} }, {}), "Professor Oak", "Professor Oak")
  eq(Snapshot.objectLabel({ graphicsId = 240, def = {} }, {}), "Person", "an unresolved variable sprite is only a Person")
  eq(Snapshot.objectLabel({ graphicsId = 92, def = { scriptKey = "nope" } }, {}), "Pok\195\169 Ball", "an item ball without a readable item")
end

-- ------------------------------------------------------------ views
local hub = mapDef("FR_TEST_HUB", {
  "#########",
  "#.......#",
  "#...L...#",
  "#.......#",
  "#..M.D..#",
  "#.......#",
  "#########",
}, {
  { x = 3, y = 4, destMap = "FR_TEST_OUT", destWarp = 1 },
  { x = 5, y = 4, destMap = "FR_TEST_OUT", destWarp = 2 },
})
local out = mapDef("FR_TEST_OUT", { "......", "......" }, {
  { x = 1, y = 0, destMap = "FR_TEST_HUB", destWarp = 1 },
  { x = 4, y = 0, destMap = "FR_TEST_HUB", destWarp = 2 },
})
maps.FR_TEST_HUB, maps.FR_TEST_OUT = hub, out
doors["FR_TEST_HUB:5,4"] = { kind = "door" }

do
  local view = World.plannedView(game, hub)
  eq(view.widthCells, 9, "view width from the layout")
  eq(view:behavior(3, 4), 0x65, "behaviour read through Collision.behaviorOn")
  eq(view:warpKind(3, 4), "arrow", "an arrow warp's kind")
  eq(view:standingWarp(3, 4), "down", "a south arrow warp is stood on and fires pressing down")
  eq(view:warpKind(5, 4), "door", "an animated door from the Doors manifest")
  eq(view:standingWarp(5, 4), nil, "a door is not stood on")
  check(view:isLedgeCell(4, 2), "ledge cell from the COLL byte")
  check(not view:isWalkableCell(4, 2), "a ledge is never stood on")
  check(view:dirBlocked(nil, nil, 4, 2, "up") == false, "no wall behaviour on plain cells")
  eq(view:warpDestination(hub.warps[1]), "FR_TEST_OUT", "destination resolved through the game's own rule")
  -- the cache follows the layout's revision
  local before = view:behavior(1, 1)
  hub.midLayout.midAt = function(_, x, y) if x == 1 and y == 1 then return 0x20 + 1000 end return 1000 end
  eq(view:behavior(1, 1), before, "behaviour cached until the layout changes")
  hub.midLayout._revision = 1
  eq(view:behavior(1, 1), 0x20, "a revision change clears the cache")
  hub.midLayout = layout({
    "#########", "#.......#", "#...L...#", "#.......#", "#..M.D..#", "#.......#", "#########" })
end

-- ------------------------------------------------------------ routing
do
  local nav = navFor()
  local world = worldOn(hub, 4, 1)
  local r = route(nav, world, { { x = 4, y = 3 } }, 1)
  check(r and kinds(r):find("down(ledge)", 1, true) ~= nil, "a ledge ahead facing the move is jumped: " .. kinds(r))
  eq(r and #r.steps, 1, "the hop is one move landing two cells on")
  r = route(nav, worldOn(hub, 4, 3), { { x = 4, y = 1 } }, 1)
  check(r and not kinds(r):find("ledge", 1, true), "a ledge is not climbed from below: " .. kinds(r))
  -- the door fires only moving up into it
  world = worldOn(hub, 7, 4)
  r = route(nav, world, { { x = 5, y = 4 } }, 1)
  eq(r and r.steps[#r.steps].direction, "up", "a door is entered moving up: " .. kinds(r))
  -- a mat may be crossed, never pressed in its own direction
  local options = nav:routeOptionsFor(worldOn(hub, 3, 4), { { x = 1, y = 1 } }, 1)
  for _, edge in ipairs(options.neighbors(3, 4)) do
    check(edge.direction ~= "down", "no move down off a south arrow warp")
  end
  r = route(nav, worldOn(hub, 2, 4), { { x = 4, y = 4 } }, 1)
  check(r ~= nil and #r.steps == 2, "an arrow warp is walked across: " .. kinds(r))
end

do
  local spin = mapDef("FR_TEST_SPIN", {
    "##########",
    "#..>...#.#",
    "#.....x..#",
    "#I.......#",
    "#I.......#",
    "#........#",
    "##########",
  })
  maps.FR_TEST_SPIN = spin
  local nav = navFor()
  local options = nav:routeOptionsFor(worldOn(spin, 2, 1), { { x = 6, y = 1 } }, 1)
  local found
  for _, edge in ipairs(options.neighbors(2, 1)) do
    if edge.direction == "right" then found = edge end
  end
  check(found and found.kind == "spinner" and found.x == 6 and found.y == 1,
    "a spinner carries the player on across floor to the wall: " .. tostring(found and (found.x .. "," .. found.y)))
  -- ice slides in the direction of travel
  options = nav:routeOptionsFor(worldOn(spin, 1, 5), { { x = 1, y = 1 } }, 1)
  found = nil
  for _, edge in ipairs(options.neighbors(1, 5)) do
    if edge.direction == "up" then found = edge end
  end
  check(found and found.kind == "ice" and found.y == 2, "ice slides until it stops: " .. tostring(found and found.y))
end

do
  local shore = mapDef("FR_TEST_SHORE", {
    "#######",
    "#.....#",
    "#~~~~~#",
    "#~~~~~#",
    "#.....#",
    "#######",
  })
  maps.FR_TEST_SHORE = shore
  local nav = navFor()
  local r = route(nav, worldOn(shore, 3, 1), { { x = 3, y = 4 } }, 2)
  check(r == nil, "no route over water without Surf")
  allowed.SURF = true
  r = route(nav, worldOn(shore, 3, 1), { { x = 3, y = 4 } }, 2)
  check(r and kinds(r):find("down(surf)", 1, true) ~= nil, "Surf from the shore: " .. kinds(r))
  check(r and kinds(r):find("exit_water", 1, true) ~= nil, "leaving the water is said: " .. kinds(r))
  eq(nav:stepInteraction(nil, { kind = "surf", direction = "down" }).move, "Surf", "Surf starts with an A press")
  allowed.SURF = nil
  -- a Cut tree is an object: use, then move
  local tree = { cellX = 3, cellY = 2, graphicsId = 95, def = { graphicsId = 95, index = 1 } }
  local lane = mapDef("FR_TEST_LANE", { "#######", "#.....#", "#.....#", "#.....#", "#######" })
  local blockedRow = { { cellX = 1, cellY = 2, def = {} }, { cellX = 2, cellY = 2, def = {} },
    tree, { cellX = 4, cellY = 2, def = {} }, { cellX = 5, cellY = 2, def = {} } }
  r = route(nav, worldOn(lane, 3, 1, blockedRow), { { x = 3, y = 3 } }, 2)
  check(r == nil, "a Cut tree blocks without Cut")
  allowed.CUT = true
  r = route(nav, worldOn(lane, 3, 1, blockedRow), { { x = 3, y = 3 } }, 2)
  check(r and kinds(r):find("down(cut)", 1, true) ~= nil, "Cut tree crossed with Cut: " .. kinds(r))
  allowed.CUT = nil
end

-- ------------------------------------------------------------ connections
do
  local north = mapDef("FR_TEST_N", { "......", "~~~..." }, {})
  local south = mapDef("FR_TEST_S", { "......", "......" }, {},
    { connections = { { direction = "up", dir = "north", map = "FR_TEST_N", offset = 0 } } })
  maps.FR_TEST_N, maps.FR_TEST_S = north, south
  package.loaded["src.core.game3.connections"] = package.loaded["src.core.game3.connections"]
    or require("src.core.game3.connections")
  local nav = navFor()
  local world = worldOn(south, 3, 1)
  local goals = nav:connectionGoals(world, { direction = "north" })
  local xs = {}
  for _, g in ipairs(goals) do xs[#xs + 1] = g.x end
  eq(table.concat(xs, ","), "3,4,5", "only edge cells landing on land are goals on foot")
end

-- ------------------------------------------------------------ Strength
do
  local floor = mapDef("FR_TEST_STRENGTH", {
    "#######",
    "#.....#",
    "#.....#",
    "#....S#",
    "#######",
  })
  local boulder = { cellX = 2, cellY = 2, graphicsId = 97, currentElevation = 3, localId = 1,
    def = { graphicsId = 97, index = 1 } }
  local world = worldOn(floor, 1, 2, { boulder })
  local targets, boulders = Puzzle.targetsFor(world)
  eq(targets and #targets, 1, "the switch is the floor's target")
  eq(targets and targets[1].label, "Pressure Switch 1", "switches numbered")
  local plan = Puzzle.planFloor(world, targets, boulders)
  check(plan ~= nil and plan.target == targets[1], "a plan puts the boulder on the switch")
  eq(plan and plan.boulder.number, 1, "Boulder 1 moves first")
  -- follow the plan's pushes to the end
  local pushes = 0
  while plan and pushes < 20 do
    local d = World.DELTA[plan.direction]
    world.player.cellX, world.player.cellY = plan.standX, plan.standY
    boulder.cellX, boulder.cellY = boulder.cellX + d[1], boulder.cellY + d[2]
    pushes = pushes + 1
    targets, boulders = Puzzle.targetsFor(world)
    plan = Puzzle.planFloor(world, targets, boulders)
  end
  check(targets[1].solved, "following the next push presses the switch (" .. pushes .. " pushes)")
  eq(targets[1].pressedBy, 1, "pressed by Boulder 1")
  check(Puzzle.elevationsMismatch(3, 4) and not Puzzle.elevationsMismatch(0, 4)
    and not Puzzle.elevationsMismatch(3, 15), "elevation rule: 0 and 15 match anything")
end

-- ------------------------------------------------------------ adapter
do
  local Gen3 = WorldAdapter.gen3
  eq(Gen3.identity({ session = "s1", save = "x" }), "s1", "FireRed binds to the session, not the save")
  local opts = { firered = { a = 1 } }
  eq(Gen3.options({ options = opts }), opts.firered, "FireRed options are its cartridge block")
  eq(Gen3.options({ options = {} }), nil, "no block, no options (never created)")
  package.loaded["src.core.game3.battle"] = { isActive = function() return true end }
  eq(Gen3.top({ phase = "field" }), WorldAdapter.GEN3_BATTLE, "a Gen 3 battle is the battle marker top")
  check(Gen3.isBattle(WorldAdapter.GEN3_BATTLE), "the marker is a battle")
  package.loaded["src.core.game3.battle"] = { isActive = function() return false end }
  eq(Gen3.top({ phase = "boot" }), WorldAdapter.BUSY, "outside the field the top is busy")
  package.loaded["src.core.game3.battle"] = nil
end

-- ------------------------------------------------------------ auto-walk
do
  -- a trainer pause with a battle that is not on any StateStack
  AutoWalk._resetForTests()
  local map = { id = "M" }
  local player = { cellX = 1, cellY = 1, moving = false, facing = "up" }
  local overworld = { map = map, player = player }
  local adapter = { generation = 3, isBattle = WorldAdapter.gen3.isBattle,
    transitioning = function() return false end, afterSteer = function() end }
  local input = { sources = {}, pressQueue = {}, state = {} }
  local nav = {
    selectedRouteGoals = function() return { id = "o", label = "Thing", type = "object" },
      { { x = 1, y = 3 } }, nil, nil, overworld end,
    worldRouteRequest = function(_, goals) return {
      start = { x = player.cellX, y = player.cellY }, goals = goals, bounds = { width = 5, height = 5 },
      canTraverse = function() return true end, maxSeconds = 1 } end,
  }
  check(AutoWalk.start(nav, { input = input }, adapter), "walk started")
  AutoWalk.pause(true)
  AutoWalk.update(overworld)
  check(AutoWalk.active() and not AutoWalk.walking(), "still waiting for the trainer's battle")
  AutoWalk.update(WorldAdapter.GEN3_BATTLE)
  AutoWalk.update(overworld)
  check(AutoWalk.walking(), "the battle marker counted as the battle; the walk resumed")
  AutoWalk.stop()
end

Speech.shutdown()
T.finish("gen3 navigation")
