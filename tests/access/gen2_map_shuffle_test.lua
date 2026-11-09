-- Gen 2 navigation under a map (door) randomizer (launcher/mods/crystal_randomizer,
-- MAPS.md): the mod rewrites `destMap` / `destWarp` in `data.gen2Maps[mapId].warps`
-- per save and restores them for a vanilla save.  A door must be named by where
-- it leads now, the object list must follow a rewrite without a refresh, journeys
-- must plan over the current warps (through a shuffled door, never through one
-- that no longer goes there), and a return warp (destWarp 0xFF) is named by where
-- it leads back to.  Synthetic maps on the real src/world/gen2/Map (blocks and a
-- tileset's collision quads), so the coordinator's own planned maps are built the
-- way they are in the game.  No cartridge data.
-- Run: luajit tests/access/gen2_map_shuffle_test.lua
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

local Gen2Map = require("src.world.gen2.Map")
local Events = require("src.world.gen2.Events")
local CmdQueue = require("src.world.gen2.CmdQueue")
local FieldMoves = require("src.world.gen2.FieldMoves")
local Navigation2 = require("src.access.nav.gen2.Navigation")

-- ------------------------------------------------------------ fixtures

-- Block 1: floor.  Block 2: a door (COLL_DOOR 0x71) in its top-left cell.
-- Block 3: a down carpet (COLL_WARP_CARPET_DOWN 0x70) in its bottom-right cell.
local TILESET = { collision = {
  [2] = { 0x00, 0x00, 0x00, 0x00 },
  [3] = { 0x71, 0x00, 0x00, 0x00 },
  [4] = { 0x00, 0x00, 0x00, 0x70 },
} }

-- A town 8x4 cells with three doors, at (0,0), (4,0) and (6,0).
local function townDef()
  return {
    id = "NEW_BARK_TOWN", environment = "TOWN", tileset = "T", width = 4, height = 2,
    blocks = { 2, 1, 2, 2, 1, 1, 1, 1 },
    warps = {
      { x = 0, y = 0, destMap = "ELMS_HOUSE", destWarp = 1 },
      { x = 4, y = 0, destMap = "PLAYERS_NEIGHBORS_HOUSE", destWarp = 1 },
      { x = 6, y = 0, destMap = "POKECENTER_2F", destWarp = 1 },
    },
    bgEvents = {}, objects = {}, connections = {},
  }
end

-- A house 4x4 cells whose exit carpet is (3,3).
local function houseDef(id, exitMap, exitWarp)
  return {
    id = id, environment = "INDOOR", tileset = "T", width = 2, height = 2,
    blocks = { 1, 1, 1, 3 },
    warps = { { x = 3, y = 3, destMap = exitMap, destWarp = exitWarp } },
    bgEvents = {}, objects = {}, connections = {},
  }
end

local function newWorld(maps, mapId, px, py)
  local world = {
    map = Gen2Map.new(maps[mapId], TILESET),
    player = { cellX = px, cellY = py, facing = "down", moving = false },
    npcs = {}, events = Events.new(), maps = maps, cmdQueue = CmdQueue.new(), scripts = {},
    playerState = FieldMoves.PLAYER_NORMAL, party = {},
  }
  function world:scriptRunning() return false end
  function world:acceptsMenuInput() return true end
  function world:npcAt() return nil end
  function world:partyMoveUser() return nil end
  function world:objectTimeVisible() return true end
  function world:cellCollisionAcross(m, x, y) return m:cellCollision(x, y) end
  -- the game's own rule (World:resolveWarp)
  function world:resolveWarp(warp)
    if warp.destWarp ~= 0xff then return warp.destMap, warp.destWarp end
    local backup = self.backupWarp
    if not (backup and backup.map and self.maps[backup.map]) then return warp.destMap, warp.destWarp end
    return backup.map, backup.warp
  end
  return world
end

-- The player moved to another map, as World:setMap leaves it.
local function moveTo(world, mapId, x, y)
  world.map = Gen2Map.new(world.maps[mapId], TILESET)
  world.player.cellX, world.player.cellY = x, y
end

local events = { handlers = {} }
function events:on(name, fn) self.handlers[name] = fn return function() end end
function events:emit() end

local function newNav(world)
  local stack = { states = {} }
  function stack:top() return nil end
  local game = {
    world = world, phase = "play", stack = stack,
    input = { sources = {}, pressQueue = {}, state = {} },
    save = { player = { name = "GOLD", badges = {} }, rival = { name = "SILVER" },
             mom = { name = "MOM" }, options = {}, party = {} },
    data = { gen2Maps = world.maps, gen2Tilesets = { T = TILESET } },
  }
  local speech = { isAvailable = function() return true end,
    output = function() return true end, stop = function() return true end }
  return Navigation2.new(game, { speech = speech, events = events, enabled = true })
end

-- The warp items of the live list, by cell.
local function doorsByCell(nav)
  local snap = nav:captureWorld("all")
  local doors = {}
  for _, item in ipairs(snap and snap.browse or {}) do
    if item.type == "warp" then doors[item.x .. "," .. item.y] = item end
  end
  return doors
end

local function warpEdges(nav, mapId)
  local edges = {}
  for _, t in ipairs(nav:regionalTransitions(mapId)) do
    if t.kind == "warp" then edges[t.x .. "," .. t.y] = t.destMap end
  end
  return edges
end

-- What the randomizer does for one pair of dead-end houses (MAPS.md): door A
-- now leads where door B led and the other way round, and each house's
-- explicit way out returns to the door used.  In place, as `maps` writes it.
local function swapDoors(maps, a, b)
  local town = maps.NEW_BARK_TOWN.warps
  local wa, wb = town[a], town[b]
  local insideA, insideB = maps[wa.destMap].warps[1], maps[wb.destMap].warps[1]
  wa.destMap, wb.destMap = wb.destMap, wa.destMap
  wa.destWarp, wb.destWarp = wb.destWarp, wa.destWarp
  insideA.destWarp, insideB.destWarp = insideB.destWarp, insideA.destWarp
end

local function fixtureMaps()
  local maps = {
    NEW_BARK_TOWN = townDef(),
    ELMS_HOUSE = houseDef("ELMS_HOUSE", "NEW_BARK_TOWN", 1),
    PLAYERS_NEIGHBORS_HOUSE = houseDef("PLAYERS_NEIGHBORS_HOUSE", "NEW_BARK_TOWN", 2),
    -- a room whose way out is "back where you came from"
    POKECENTER_2F = houseDef("POKECENTER_2F", "POKECENTER_2F", 0xff),
  }
  return maps
end

-- ------------------------------------------------------------ names follow the door

local maps = fixtureMaps()
local world = newWorld(maps, "NEW_BARK_TOWN", 2, 3)
local nav = newNav(world)
local elms = nav:regionalDestinationName("ELMS_HOUSE")
local neighbors = nav:regionalDestinationName("PLAYERS_NEIGHBORS_HOUSE")
check(elms ~= neighbors and elms ~= "ELMS_HOUSE", "fixture: the two houses have distinct spoken names: "
  .. tostring(elms) .. " / " .. tostring(neighbors))

do
  local doors = doorsByCell(nav)
  eq(doors["0,0"] and doors["0,0"].label, elms, "vanilla: the first door is named by Elm's house")
  eq(doors["4,0"] and doors["4,0"].label, neighbors, "vanilla: the second door by the neighbours' house")
  -- planned before the shuffle, so the coordinator's planned maps are cached
  eq(warpEdges(nav, "NEW_BARK_TOWN")["0,0"], "ELMS_HOUSE", "vanilla: the planner's first door")
end

swapDoors(maps, 1, 2)

do
  local doors = doorsByCell(nav)
  eq(doors["0,0"] and doors["0,0"].label, neighbors, "shuffled: the first door is named by where it leads now")
  eq(doors["0,0"] and doors["0,0"].destinationMapId, "PLAYERS_NEIGHBORS_HOUSE",
    "shuffled: and auto-walk's arrival map is the new one")
  eq(doors["4,0"] and doors["4,0"].label, elms, "shuffled: the second door too")
  local edges = warpEdges(nav, "NEW_BARK_TOWN")
  eq(edges["0,0"], "PLAYERS_NEIGHBORS_HOUSE", "shuffled: the planner's first door leads where it leads now")
  eq(edges["4,0"], "ELMS_HOUSE", "shuffled: and its second")
end

-- ------------------------------------------------------------ journeys over the current warps

do
  local leg, why = nav:regionalNextLeg({ targetMapId = "ELMS_HOUSE", targetGoals = { { x = 1, y = 1 } } })
  check(leg ~= nil, "journey into Elm's house planned: " .. tostring(why))
  eq(leg and leg.goals[1].x .. "," .. leg.goals[1].y, "4,0",
    "journey: through the door that leads there now, not the vanilla one")
  eq(leg and leg.nextMapId, "ELMS_HOUSE", "journey: the next map is the house")
end

do -- from inside one house to the other: out by the shuffled exit, in by the other door
  moveTo(world, "ELMS_HOUSE", 3, 3)
  local doors = doorsByCell(nav)
  local town = nav:regionalDestinationName("NEW_BARK_TOWN")
  eq(doors["3,3"] and doors["3,3"].label, town, "inside: the way out is named by the town")
  local Journey = require("src.access.nav.gen2.Journey")
  local result = Journey.search(nav, { mapId = "ELMS_HOUSE", x = 3, y = 3 },
    { mapId = "PLAYERS_NEIGHBORS_HOUSE", goals = { { x = 1, y = 1 } } }, 1, nil, os.clock() + 5)
  check(result ~= nil, "journey from house to house planned")
  local townLeg
  for _, leg in ipairs(result and result.legs or {}) do
    if leg.mapId == "NEW_BARK_TOWN" then townLeg = leg end
  end
  local first = townLeg and townLeg.steps[1]
  eq(first and (first.fromX .. "," .. first.fromY), "4,0",
    "journey: arrives in town at the door Elm's house now opens onto")
  local last = townLeg and townLeg.steps[#townLeg.steps]
  eq(last and (last.x .. "," .. last.y), "0,0", "journey: and enters by the door that leads there now")
  moveTo(world, "NEW_BARK_TOWN", 2, 3)
end

-- ------------------------------------------------------------ restored for a vanilla save

swapDoors(maps, 1, 2)
do
  local doors = doorsByCell(nav)
  eq(doors["0,0"] and doors["0,0"].label, elms, "restored: the first door is Elm's house again")
  eq(warpEdges(nav, "NEW_BARK_TOWN")["0,0"], "ELMS_HOUSE", "restored: and the planner's")
end

-- ------------------------------------------------------------ warps replaced, not rewritten

do -- a warp record or list replaced outright reaches the planned maps too
  local def = maps.NEW_BARK_TOWN
  local planned = nav:regionalMap(def)
  local old = def.warps[1]
  def.warps[1] = { x = old.x, y = old.y, destMap = "PLAYERS_NEIGHBORS_HOUSE", destWarp = 1 }
  local rebuilt = nav:regionalMap(def)
  check(rebuilt ~= planned, "a replaced warp record rebuilds the planned map")
  eq(rebuilt:warpAt(0, 0).def, def.warps[1], "the planned map indexes the new record")
  eq(warpEdges(nav, "NEW_BARK_TOWN")["0,0"], "PLAYERS_NEIGHBORS_HOUSE", "and plans over it")
  eq(nav:regionalMap(def), rebuilt, "an unchanged map is not rebuilt again")
  local list = {}
  for i, w in ipairs(def.warps) do list[i] = w end
  def.warps = list
  check(nav:regionalMap(def) ~= rebuilt, "a replaced warp list rebuilds it too")
  def.warps[1] = old
end

-- ------------------------------------------------------------ return warps

do
  local town = nav:regionalDestinationName("NEW_BARK_TOWN")
  -- the door into the room shuffled onto the first door; the game recorded it on the way in
  local doorWarps = maps.NEW_BARK_TOWN.warps
  doorWarps[1].destMap, doorWarps[3].destMap = "POKECENTER_2F", "ELMS_HOUSE"
  moveTo(world, "POKECENTER_2F", 3, 3)
  world.backupWarp = { map = "NEW_BARK_TOWN", warp = 1 }
  local doors = doorsByCell(nav)
  eq(doors["3,3"] and doors["3,3"].label, town, "return warp: named by where it leads back to")
  eq(doors["3,3"] and doors["3,3"].destinationMapId, "NEW_BARK_TOWN", "return warp: and leads there")
  local back
  for _, t in ipairs(nav:regionalTransitions("POKECENTER_2F")) do
    if t.kind == "warp" then back = t end
  end
  eq(back and (back.destX .. "," .. back.destY), "0,0",
    "return warp: the planner lands on the door the player came in by")

  -- on a map a plan only passes through, the backup warp says nothing about it
  moveTo(world, "NEW_BARK_TOWN", 2, 3)
  eq(next(warpEdges(nav, "POKECENTER_2F")), nil,
    "return warp: no edge from a map the player is not on (it would be the last door used)")
  local dest = nav:regionalResolveWarp(maps.POKECENTER_2F.warps[1])
  eq(dest, "NEW_BARK_TOWN", "return warp: still resolved when no map is named")
  doorWarps[1].destMap, doorWarps[3].destMap = "ELMS_HOUSE", "POKECENTER_2F"
end

Speech.shutdown()
T.finish("gen2 map shuffle")
