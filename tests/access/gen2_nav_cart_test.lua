-- Gen 2 navigation against cartridge data (decision 27): real maps from an
-- extracted Gold, Silver or Crystal cache, so the checks rest on the game's
-- data rather than on a fixture written from reading code.  Solves both
-- stone-table floors (Ice Path B1F, Blackthorn Gym 2F) by following only the
-- puzzle help's next push under the game's own push rule, routes Route 29's
-- ledges, names connections and the return warp, labels signs, item balls,
-- waterfalls and whirlpools, and plans Sprout Tower's floors.
--
-- Gated: set GEN2_NAV_CACHE to a cache's data/generated folder, for example
--   GEN2_NAV_CACHE="$APPDATA/LOVE/pocket-access-nav-crystal/crystal/data/generated"
--   luajit tests/access/gen2_nav_cart_test.lua
-- Without it the suite makes NO CHECKS (never a pass).  No cartridge data is
-- read from or written to the repository.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local dir = os.getenv("GEN2_NAV_CACHE")
local function readable(path)
  local f = path and io.open(path, "rb")
  if f then f:close() return true end
  return false
end
if not (dir and readable(dir .. "/maps.lua") and readable(dir .. "/tilesets.lua")) then
  print("gen2 navigation (cartridge): NO CHECKS -- GEN2_NAV_CACHE does not name an extracted Gen 2 data/generated folder")
  os.exit(0)
end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Speech = require("src.access.Speech")
local fake = { name = "Fake" }
function fake:say() return true end
function fake:stop() return true end
function fake:close() end
Speech.shutdown()
Speech.start({ backend = fake })

local maps = dofile(dir .. "/maps.lua")
local tilesets = dofile(dir .. "/tilesets.lua")
local items = readable(dir .. "/items.lua") and dofile(dir .. "/items.lua") or {}
local scripts = readable(dir .. "/scripts.lua") and dofile(dir .. "/scripts.lua") or {}
local texts = readable(dir .. "/text.lua") and dofile(dir .. "/text.lua") or {}
local initial = readable(dir .. "/initial_events.lua") and dofile(dir .. "/initial_events.lua") or {}
local constants = readable(dir .. "/constants.lua") and dofile(dir .. "/constants.lua") or {}
local sprites = readable(dir .. "/sprites.lua") and dofile(dir .. "/sprites.lua") or {}
local pokemon = readable(dir .. "/pokemon.lua") and dofile(dir .. "/pokemon.lua") or {}
local itemById = {}
for id, item in pairs(items) do
  if type(item) == "table" and item.index then itemById[item.index] = id end
end

local Gen2Map = require("src.world.gen2.Map")
local Events = require("src.world.gen2.Events")
local CmdQueue = require("src.world.gen2.CmdQueue")
local FieldMoves = require("src.world.gen2.FieldMoves")
local Navigation2 = require("src.access.nav.gen2.Navigation")
local Puzzle2 = require("src.access.nav.gen2.PuzzleAssistance")
local RegionalPathfinder = require("src.access.nav.RegionalPathfinder")
local Pathfinder = require("src.access.nav.Pathfinder")

local BIG = { [0x15] = true, [0x20] = true, [0x21] = true }

-- The sheet the live world draws an object with (World:resolveSprite and
-- pooledNpc): a sheet name, or a variable-sprite slot filled by the new
-- game's InitializeEventsScript (initial_events.sprites, constants.spriteOrder).
-- No sheet, no object -- the game spawns nothing there either.
local variableSprites = {}
for _, row in ipairs(initial.sprites or {}) do variableSprites[row.slot] = row.sprite end
local function sheetFor(sprite)
  local function sheet(name)
    if next(sprites) == nil then return { id = name } end -- an older cache without sprites.lua
    return sprites[name]
  end
  if type(sprite) == "string" then return sheet(sprite) end
  if type(sprite) ~= "number" or sprite < 0xf0 then return nil end
  local byte = variableSprites[sprite - 0xf0]
  local name = byte and (constants.spriteOrder or {})[byte]
  return name and sheet(name) or nil
end

-- A headless world on a real map: the objects a new game shows (initial
-- event flags applied), the command queue the map's callback writes, and the
-- few World methods navigation reads.
local function world(mapId, px, py, opts)
  opts = opts or {}
  local def = assert(maps[mapId], "no map " .. mapId)
  local map = Gen2Map.new(def, tilesets[def.tileset])
  local events = Events.new()
  for _, flag in ipairs(initial.flags or {}) do events:set(flag, true) end
  local w = {
    map = map, maps = maps, tilesets = tilesets, scripts = scripts, text = texts, events = events,
    constants = constants,
    player = { cellX = px, cellY = py, facing = "down", moving = false },
    npcs = {}, cmdQueue = CmdQueue.new(), party = opts.party or {},
    playerState = opts.surfing and FieldMoves.PLAYER_SURF or FieldMoves.PLAYER_NORMAL,
    strengthActive = opts.strength, backupWarp = opts.backupWarp,
  }
  for _, obj in ipairs(def.objects or {}) do
    local sheet = sheetFor(obj.sprite)
    if sheet and events:objectVisible(obj.eventFlag) then
      w.npcs[#w.npcs + 1] = { id = mapId .. "_obj_" .. obj.index, cellX = obj.x, cellY = obj.y,
        def = obj, spriteDef = sheet, bigObject = BIG[obj.movement] == true, facing = "down" }
    end
  end
  for _, cb in ipairs(def.callbacks or {}) do
    if cb.callback == "MAPCALLBACK_CMDQUEUE" then
      for _, cmd in ipairs(scripts[cb.scriptKey] or {}) do
        local entry = cmd.op == "writecmdqueue" and CmdQueue.fromExtracted(cmd.queue, mapId)
        if entry then CmdQueue.write(w.cmdQueue, entry) end
      end
    end
  end
  function w:scriptRunning() return false end
  function w:acceptsMenuInput() return true end
  function w:npcAt(x, y)
    for _, n in ipairs(self.npcs) do
      if n.bigObject then
        local dx, dy = x - n.cellX, y - n.cellY
        if dx >= 0 and dx < 2 and dy >= 0 and dy < 2 then return n end
      elseif n.cellX == x and n.cellY == y then return n end
    end
  end
  function w:partyMoveUser(move)
    for _, m in ipairs(self.party) do if m == move then return { moves = { move } } end end
  end
  function w:itemIdByIndex(index) return itemById[index] end
  function w:objectTimeVisible() return true end
  function w:cellCollisionAcross(m, x, y) return m:cellCollision(x, y) end
  function w:resolveWarp(warp)
    if warp.destWarp ~= 0xff then return warp.destMap, warp.destWarp end
    local b = self.backupWarp
    if b and self.maps[b.map] then return b.map, b.warp end
    return warp.destMap, warp.destWarp
  end
  return w
end

local function game(w, badges)
  local stack = { states = {} }
  function stack:top() return nil end
  return { world = w, phase = "play", stack = stack, input = { sources = {}, pressQueue = {}, state = {} },
    save = { player = { name = "GOLD", badges = badges or {} }, rival = { name = "SILVER" },
             mom = { name = "MOM" }, options = {}, party = {} },
    data = { gen2Maps = maps, gen2Tilesets = tilesets, pokemon = pokemon } }
end

local quiet = { isAvailable = function() return true end, output = function() return true end,
  stop = function() return true end }
local nullEvents = { on = function() return function() end end, emit = function() end }

local function nav(g) return Navigation2.new(g, { speech = quiet, events = nullEvents, enabled = true }) end

local function browse(n)
  local snap = assert(n:captureWorld("all"))
  local byLabel, labels = {}, {}
  for _, item in ipairs(snap.browse) do
    byLabel[item.label] = byLabel[item.label] or item
    labels[#labels + 1] = item.label
  end
  return byLabel, table.concat(labels, " | "), snap
end

-- ------------------------------------------------------------ the puzzles
-- Follow only the help's next push; apply it by the game's push rule
-- (World:tryPushBoulder: Map:objectStepPermitted, nothing on the landing;
-- a boulder on its own hole drops, CmdQueue.stoneFall).

local function solve(mapId, px, py)
  local w = world(mapId, px, py, { party = { "STRENGTH" }, strength = true })
  local g = game(w, { PLAIN = true })
  local n = nav(g)
  local pushes, label = 0, nil
  for _ = 1, 300 do
    local result = Puzzle2.describe(g, n:worldState())
    local action = result.nextAction
    local left = 0
    for _, t in ipairs(result.targetStates) do if t.state ~= "filled" then left = left + 1 end end
    if left == 0 then return pushes, 0 end
    if not action then return pushes, left, "no next push" end
    local boulder
    for _, b in ipairs(w.npcs) do if b.id == action.boulderId then boulder = b end end
    -- the player walks to the pushing position (the route must exist)
    local options = n:worldRouteRequest({ { x = action.standX, y = action.standY } }, 1)
    local walked = options and Pathfinder.find(options)
    if not walked then return pushes, left, "pushing position unreachable" end
    w.player.cellX, w.player.cellY = action.standX, action.standY
    local d = Gen2Map.DELTA[action.direction]
    local tx, ty = boulder.cellX + d[1], boulder.cellY + d[2]
    if not w.map:objectStepPermitted(boulder.cellX, boulder.cellY, action.direction) then
      return pushes, left, "push refused by the game rule"
    end
    for _, e in ipairs(w.npcs) do
      if e ~= boulder and e.cellX == tx and e.cellY == ty then return pushes, left, "landing taken" end
    end
    boulder.cellX, boulder.cellY = tx, ty
    pushes = pushes + 1
    label = label or action.instruction
    local warpNumber = CmdQueue.warpNumberAt(w.map.def.warps, tx, ty)
    local row = warpNumber and CmdQueue.stoneRow(w.cmdQueue[1].rows, warpNumber, boulder.def.index + 1)
    if row then
      for i, e in ipairs(w.npcs) do if e == boulder then table.remove(w.npcs, i) break end end
    end
  end
  return pushes, -1, "too many pushes"
end

do
  local pushes, left, why = solve("ICE_PATH_B1F", 3, 14)
  eq(left, 0, "Ice Path B1F: every hole filled by following the help (" .. tostring(why) .. ")")
  check(pushes > 4, "Ice Path B1F: solved in " .. pushes .. " pushes")
  pushes, left, why = solve("BLACKTHORN_GYM_2F", 2, 7)
  eq(left, 0, "Blackthorn Gym 2F: every hole filled, moving the blocking boulders too (" .. tostring(why) .. ")")
  check(pushes > 3, "Blackthorn Gym 2F: solved in " .. pushes .. " pushes")
  local w = world("BLACKTHORN_GYM_2F", 2, 7, { party = { "STRENGTH" } })
  local g = game(w, { PLAIN = true })
  local byLabel, _, snap0 = browse(nav(g))
  check(byLabel["Hole 1"] and byLabel["Hole 2"] and byLabel["Hole 3"], "Blackthorn: three holes listed by row")
  local noRow, nextPush = 0, 0
  for _, item in ipairs(snap0.browse) do
    if item.stateText == "goes in no hole" then noRow = noRow + 1 end
    if tostring(item.stateText):find("next push", 1, true) then nextPush = nextPush + 1 end
  end
  check(noRow >= 2, "Blackthorn: boulders in no row say so (" .. noRow .. ")")
  eq(nextPush, 1, "Blackthorn: exactly one boulder carries the next push")
  local w2 = world("ICE_PATH_B2F_MAHOGANY_SIDE", 1, 1)
  local snap = nav(game(w2)):captureWorld("all")
  local boulders = 0
  for _, item in ipairs(snap.browse) do if item.label == "Boulder" then boulders = boulders + 1 end end
  eq(Puzzle2.describe(game(w2), w2).nextAction, nil, "Ice Path B2F has no stone table: no push guidance")
end

-- ------------------------------------------------------------ routes

do
  local w = world("ROUTE_29", 58, 9)
  local n = nav(game(w))
  local byLabel = browse(n)
  local west = byLabel["West connection to Cherrygrove City"]
  check(west ~= nil, "Route 29: west connection named from mapId")
  local goals = n:connectionGoals(n:worldState(), west)
  local r = Pathfinder.find(n:worldRouteRequest(goals, 1))
  local ledges = 0
  for _, s in ipairs(r and r.steps or {}) do if s.kind == "ledge" then ledges = ledges + 1 end end
  check(r ~= nil, "Route 29: route to Cherrygrove")
  check(ledges >= 1, "Route 29: the route hops a ledge (" .. ledges .. ")")
  check(byLabel["Potion"] ~= nil, "Route 29: the item ball is named by its item")
end

do -- every planned ice slide ends where the game's slide ends, on every map with ice
  -- (the audit found Ice Path B2F's slide up the bottom column planned as
  -- stopping below the B1F ladder; the game slides onto it and the player
  -- climbs to B1F).  Routes from each warp to every other warp and item
  -- ball; each slide replayed by the game's rule, written out here: keep
  -- going while on ice; a warp ahead is entered; a wall, side wall or
  -- object stops it.
  local P = require("src.world.gen2.Permissions")
  local ids = {}
  for id in pairs(maps) do ids[#ids + 1] = id end
  table.sort(ids)
  local slides, wrong, icy, icyNames = 0, {}, 0, {}
  for _, mapId in ipairs(ids) do
    local def = maps[mapId]
    local map = tilesets[def.tileset] and Gen2Map.new(def, tilesets[def.tileset])
    local hasIce = false
    for y = 0, map and map.heightCells - 1 or -1 do
      for x = 0, map.widthCells - 1 do
        if P.isIce(map:cellCollision(x, y)) then hasIce = true end
      end
    end
    if hasIce then
      icy = icy + 1
      icyNames[#icyNames + 1] = mapId
      local targets = {}
      for _, warp in ipairs(def.warps or {}) do targets[#targets + 1] = { { x = warp.x, y = warp.y } } end
      for _, obj in ipairs(def.objects or {}) do
        if obj.itemball then
          targets[#targets + 1] = { { x = obj.x, y = obj.y - 1 }, { x = obj.x, y = obj.y + 1 },
            { x = obj.x - 1, y = obj.y }, { x = obj.x + 1, y = obj.y } }
        end
      end
      for _, start in ipairs(def.warps or {}) do
        local w = world(mapId, start.x, start.y)
        local n = nav(game(w))
        local function gameSlide(x, y, dir)
          local d = Gen2Map.DELTA[dir]
          x, y = x + d[1], y + d[2]
          while P.isIce(w.map:cellCollision(x, y)) and not w.map:warpAt(x, y) do
            if not w.map:stepPermitted(x, y, dir) then break end
            local nx, ny = x + d[1], y + d[2]
            local c = w.map:cellCollision(nx, ny)
            if w:npcAt(nx, ny) then break end
            if w.map:warpAt(nx, ny) and P.isWarpCollision(c) then return nx, ny end
            if not P.isWalkable(c) then break end
            x, y = nx, ny
          end
          return x, y
        end
        for _, goals in ipairs(targets) do
          local options = n:worldRouteRequest(goals, 1)
          local r = options and Pathfinder.find(options)
          for _, s in ipairs(r and r.steps or {}) do
            if s.kind == "ice" then
              slides = slides + 1
              local gx, gy = gameSlide(s.fromX, s.fromY, s.direction)
              if gx ~= s.x or gy ~= s.y then
                wrong[#wrong + 1] = mapId .. " " .. s.fromX .. "," .. s.fromY .. " " .. s.direction
                  .. " planned " .. s.x .. "," .. s.y .. ", game " .. gx .. "," .. gy
              end
            end
          end
        end
      end
    end
  end
  check(icy >= 5 and slides > 20, "ice maps checked: " .. table.concat(icyNames, ", ") .. "; planned slides: " .. slides)
  eq(#wrong, 0, "every planned slide ends where the game's slide ends: " .. table.concat(wrong, "; "))
end

do -- the 0xFF return warp
  local w = world("POKECENTER_2F", 0, 7)
  local byLabel, all = browse(nav(game(w)))
  check(byLabel["Exit"] ~= nil, "Pokemon Center 2F: unresolved return warp is Exit: " .. all)
  w = world("POKECENTER_2F", 0, 7, { backupWarp = { map = "CHERRYGROVE_POKECENTER_1F", warp = 3 } })
  byLabel, all = browse(nav(game(w)))
  check(all:find("Cherrygrove Pokecenter 1F", 1, true) ~= nil, "Pokemon Center 2F: resolved through the backup warp: " .. all)
end

do -- connections across water, signs, standard tiles
  local w = world("NEW_BARK_TOWN", 13, 6)
  local n = nav(game(w))
  local byLabel, all = browse(n)
  check(byLabel["East connection to Route 27"] and byLabel["West connection to Route 29"],
    "New Bark Town: both connections named")
  check(not all:find("Unknown location", 1, true), "New Bark Town: no unknown locations")
  check(not all:find("%d+:%x+"), "New Bark Town: no script addresses spoken")
  local toRoute27 = 0
  for _, t in ipairs(n:regionalTransitions("NEW_BARK_TOWN")) do
    if t.kind == "connection" and t.destMap == "ROUTE_27" then toRoute27 = toRoute27 + 1 end
  end
  check(toRoute27 > 0, "New Bark Town: the water crossing to Route 27 is a transition")
  local house = world("PLAYERS_HOUSE_2F", 3, 3)
  local hb, hall = browse(nav(game(house)))
  local shelves = 0
  for label in hall:gmatch("[^|]+") do if label:find("Bookshelf", 1, true) then shelves = shelves + 1 end end
  eq(shelves, 1, "player's room: the bookshelf listed once: " .. hall)
end

-- The first plain water cell of a map, to stand a surfing player on.
local Permissions = require("src.world.gen2.Permissions")
local function waterCell(mapId)
  local def = maps[mapId]
  local map = Gen2Map.new(def, tilesets[def.tileset])
  for y = 0, map.heightCells - 1 do
    for x = 0, map.widthCells - 1 do
      local c = map:cellCollision(x, y)
      if c == 0x29 then return x, y end
    end
  end
end

do -- field obstacles from collision
  local x, y = waterCell("ROUTE_41")
  local w = world("ROUTE_41", x, y, { surfing = true })
  local byLabel = browse(nav(game(w)))
  eq(byLabel["Whirlpool"] and byLabel["Whirlpool"].requirement, "Needs Whirlpool and Glacier Badge",
    "Route 41: whirlpools need the move and the badge")
  x, y = waterCell("TOHJO_FALLS")
  w = world("TOHJO_FALLS", x, y, { surfing = true })
  byLabel = browse(nav(game(w, { RISING = true })))
  local fall = byLabel["Waterfall"]
  check(fall and fall.requiredFacing == "up", "Tohjo Falls: the waterfall is climbed facing up")
  eq(fall and fall.requirement, "Needs Waterfall", "Tohjo Falls: badge owned, move missing")
end

do -- Sprout Tower: the floors' transitions plan a journey
  local w = world("SPROUT_TOWER_1F", 9, 13)
  local n = nav(game(w))
  local target = maps.SPROUT_TOWER_3F.objects[5]
  local result = RegionalPathfinder.find({
    start = { mapId = "SPROUT_TOWER_1F", x = 9, y = 13 },
    target = { mapId = "SPROUT_TOWER_3F", goals = { { x = target.x, y = target.y - 1 },
      { x = target.x + 1, y = target.y }, { x = target.x - 1, y = target.y } } },
    route = function(mapId, start, goals, initial, budget)
      return n:regionalDryRoute(mapId, start, goals, initial, budget)
    end,
    transitions = function(mapId) return n:regionalTransitions(mapId) end,
    maxStates = 96, maxTransitions = 16, maxSeconds = 2, maxRouteSeconds = 0.2,
  })
  check(result ~= nil and result.firstTransition ~= nil, "Sprout Tower: a journey from 1F to 3F is planned")
  eq(result and result.firstTransition and result.firstTransition.destMap, "SPROUT_TOWER_2F",
    "Sprout Tower: the first leg climbs to 2F")
end

-- ------------------------------------------------------------ whole-game label sweep
-- Every map of the cache, from a new game's flags: the object list the layer
-- shows, every label checked for the wrong-but-plausible kinds the old
-- project shipped (Unknown, nil, raw ids, ROM addresses, "Object N", empty),
-- every warp and connection leading somewhere real, every return warp
-- having a way in.  Failures name the map and the label.

local startCellOf = function(def, map)
  local anchor = (def.warps or {})[1]
  local ax, ay = anchor and anchor.x or 0, anchor and anchor.y or 0
  local best, bx, by = math.huge, 0, 0
  for y = 0, map.heightCells - 1 do
    for x = 0, map.widthCells - 1 do
      local c = map:cellCollision(x, y)
      if Permissions.isWalkable(c) and not Permissions.isWarpCollision(c) and not Permissions.isIce(c)
         and not Permissions.currentDirection(c) and not Permissions.doorForcedDirection(c) then
        local d = math.abs(x - ax) + math.abs(y - ay)
        if d < best then best, bx, by = d, x, y end
      end
    end
  end
  return bx, by
end

do
  local ids = {}
  for id in pairs(maps) do ids[#ids + 1] = id end
  table.sort(ids)
  -- the first map (by id) leading into each map, as the backup warp a return
  -- warp resolves through
  local enteredFrom = {}
  for _, id in ipairs(ids) do
    for i, warp in ipairs(maps[id].warps or {}) do
      if warp.destWarp ~= 0xff and maps[warp.destMap] then
        enteredFrom[warp.destMap] = enteredFrom[warp.destMap] or { map = id, warp = i }
      end
    end
  end
  local mapsChecked, labelsChecked, bad, badData = 0, 0, {}, {}
  local function suspicious(label)
    if type(label) ~= "string" or not label:match("%S") then return "empty" end
    if label:find("Unknown", 1, true) or label:find("nil", 1, true) then return "unknown or nil" end
    if label:match("%x%x?:%x%x%x%x") then return "ROM address" end
    if label:find("_", 1, true) or label:find("SPRITE", 1, true) or label:find("EVENT", 1, true) then
      return "raw id"
    end
    if label:match("^Object %d") or label:match("^Warp %d") or label:match("^Interactive object") then
      return "generic placeholder"
    end
    return nil
  end
  for _, mapId in ipairs(ids) do
    local def = maps[mapId]
    if tilesets[def.tileset] then
      mapsChecked = mapsChecked + 1
      for i, warp in ipairs(def.warps or {}) do
        if warp.destWarp == 0xff then
          if not enteredFrom[mapId] then badData[#badData + 1] = mapId .. " return warp " .. i .. " has no way in" end
        elseif not (maps[warp.destMap] and (maps[warp.destMap].warps or {})[warp.destWarp]) then
          badData[#badData + 1] = mapId .. " warp " .. i .. " to " .. tostring(warp.destMap) .. "#" .. tostring(warp.destWarp)
        end
      end
      for direction, conn in pairs(def.connections or {}) do
        if type(conn) == "table" and not maps[conn.mapId or ""] then
          badData[#badData + 1] = mapId .. " " .. direction .. " connection to " .. tostring(conn.mapId)
        end
      end
      local map = Gen2Map.new(def, tilesets[def.tileset])
      local px, py = startCellOf(def, map)
      local w = world(mapId, px, py, { backupWarp = enteredFrom[mapId] })
      local snap = nav(game(w)):captureWorld("all")
      if not snap then
        bad[#bad + 1] = mapId .. ": no object list"
      else
        if suspicious(snap.locationName) then bad[#bad + 1] = mapId .. " map name: " .. tostring(snap.locationName) end
        for _, item in ipairs(snap.browse) do
          labelsChecked = labelsChecked + 1
          local why = suspicious(item.label)
          if why then bad[#bad + 1] = mapId .. " " .. why .. ": " .. tostring(item.label) end
          if item.label == "Exit" then bad[#bad + 1] = mapId .. " return warp unresolved with a way in" end
        end
      end
    end
  end
  check(mapsChecked > 300, "label sweep: every map of the cache (" .. mapsChecked .. ")")
  eq(#bad, 0, "label sweep: " .. labelsChecked .. " labels, none suspicious: " .. table.concat(bad, "; "))
  eq(#badData, 0, "label sweep: every warp, return warp and connection resolves: " .. table.concat(badData, "; "))
end

do -- named from the game's own data rather than the sheet or "Signpost N"
  local function labelsOn(mapId)
    local def = maps[mapId]
    if not def then return nil end
    local map = Gen2Map.new(def, tilesets[def.tileset])
    local px, py = startCellOf(def, map)
    local byLabel, all = browse(nav(game(world(mapId, px, py))))
    local counts = {}
    for label in (all .. " | "):gmatch("(.-) | ") do counts[label] = (counts[label] or 0) + 1 end
    return byLabel, counts, all
  end
  local byLabel, _, all = labelsOn("CHARCOAL_KILN")
  check(byLabel and byLabel["Farfetch'd"] and not byLabel["Moltres"],
    "Charcoal Kiln: the Farfetch'd drawn with MOLTRES's sheet is the Farfetch'd: " .. tostring(all))
  byLabel, _, all = labelsOn("CELADON_MANSION_1F")
  check(byLabel and byLabel["Meowth"] and not byLabel["Growlithe"],
    "Celadon Mansion 1F: the Meowth drawn with GROWLITHE's sheet: " .. tostring(all))
  -- signs named from their own words: every one on every map, printed for review
  local named = {}
  for mapId in pairs(maps) do
    local okLabels, labels = pcall(labelsOn, mapId)
    if okLabels and type(labels) == "table" then
      for label in pairs(labels) do
        if label == "Locked Door" or label:find("^Switch ") or label:find(" Slot$") then
          named[#named + 1] = mapId .. " = " .. label
        end
      end
    end
  end
  table.sort(named)
  print("signs named from their words: " .. table.concat(named, "; "))
  -- boulders: the search opens the way to Chuck from his gym's door, and asks for
  -- nothing where the way is already open
  do
    local Puzzle = require("src.access.nav.gen2.PuzzleAssistance")
    local gym = world("CIANWOOD_GYM", 4, 16)
    local plan = Puzzle.planOpening(gym, { { x = 4, y = 2 } }, { maxSeconds = 5 })
    check(plan and plan.pushes and plan.pushes > 0, "Cianwood Gym: pushes open the way to Chuck")
    local _, reason = Puzzle.planOpening(gym, { { x = 4, y = 15 } }, { maxSeconds = 5 })
    eq(reason, "open", "Cianwood Gym: no push where the way is open")
  end
  byLabel = labelsOn("TEAM_ROCKET_BASE_B3F")
  check(byLabel and byLabel["Locked Door"], "Team Rocket Base B3F: the password door is a Locked Door")
  byLabel = labelsOn("GOLDENROD_UNDERGROUND_SWITCH_ROOM_ENTRANCES")
  check(byLabel and byLabel["Switch 1"], "Goldenrod Underground: switches say their label")
  byLabel, _, all = labelsOn("VIRIDIAN_GYM")
  check(byLabel and byLabel["Gym Statue"], "Viridian Gym: the statues are Gym Statue: " .. tostring(all))
  byLabel, _, all = labelsOn("GOLDENROD_GAME_CORNER")
  check(byLabel and byLabel["Slot Machine"] and byLabel["Card Flip"],
    "Goldenrod Game Corner: slot machines and Card Flip named by their special: " .. tostring(all))
  local _, counts
  byLabel, counts, all = labelsOn("TEAM_ROCKET_BASE_B2F")
  local transmitter = 0
  for label, n in pairs(counts or {}) do if label:match("^Signpost") then transmitter = transmitter + n end end
  check(byLabel and transmitter <= 2,
    "Rocket base B2F: the transmitter's twenty bg events are one object: " .. tostring(all))
  byLabel, _, all = labelsOn("RUINS_OF_ALPH_KABUTO_CHAMBER")
  check(byLabel and byLabel["Unown Puzzle"], "Ruins of Alph: the puzzle panel is named: " .. tostring(all))
end

Speech.shutdown()
T.finish("gen2 navigation (cartridge)")
