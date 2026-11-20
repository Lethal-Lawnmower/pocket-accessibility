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
  ["H"] = { 0x71, 0x66, 3 }, ["c"] = { 0x00, 0x27, 3 }, ["t"] = { 0x00, 0x26, 3 },
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
    -- load scripts
    load_gates = { { op = "checkflag", flag = 620 }, { op = "call_if", cond = 1, target = "gates_set" }, { op = "end" } },
    gates_set = { { op = "setmetatile", 3, 2, 1007, 1 }, { op = "setmetatile", 1, 1, 1000, 0 }, { op = "return" } },
    load_count = { { op = "setvar", var = 0x4002, value = 0 }, { op = "checkflag", flag = 70 },
      { op = "call_if", cond = 0, target = "count_one" }, { op = "checkflag", flag = 71 },
      { op = "call_if", cond = 0, target = "count_one" }, { op = "compare_var_to_value", var = 0x4002, value = 2 },
      { op = "call_if", cond = 1, target = "swap" }, { op = "end" } },
    count_one = { { op = "addvar", 0x4002, 1 }, { op = "return" } },
    swap = { { op = "setmaplayoutindex", 278 }, { op = "return" } },
    load_special = { { op = "special", id = 142 }, { op = "end" } },
    -- elevators: floors by map group and number
    panel_free = { { op = "lockall" }, { op = "special", id = 216 }, { op = "goto", target = "panel_floors" } },
    panel_floors = { { op = "setdynamicwarp", 1, 1, 255, 1, 1 }, { op = "setdynamicwarp", 1, 2, 255, 1, 1 }, { op = "end" } },
    panel_gated = { { op = "checkflag", flag = 677 }, { op = "goto_if", cond = 0, target = "no_key" },
      { op = "special", id = 216 }, { op = "goto", target = "panel_floors" } },
    no_key = { { op = "callstd", std = 4 }, { op = "end" } },
    lift_key = { { op = "setflag", flag = 677 }, { op = "setorcopyvar", 0x8000, 356 }, { op = "callstd", std = 0 } },
    -- the floor that gives way
    ice_resume = { { op = "setstepcallback", 4 }, { op = "end" } },
    ice_frame = { { op = "warphole", 1, 3 }, { op = "end" } },
  })
  Scripts.setMapGroups({ MAP_TEST_SHAFT_A = { group = 1, num = 1 }, MAP_TEST_SHAFT_B = { group = 1, num = 2 },
    MAP_TEST_CAVE_B1 = { group = 1, num = 3 } })
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
    [0] = "OBJ_EVENT_GFX_RED_NORMAL", [71] = "OBJ_EVENT_GFX_PROF_OAK", [97] = "OBJ_EVENT_GFX_PUSHABLE_BOULDER",
    [28] = "OBJ_EVENT_GFX_LINK_RECEPTIONIST" })
  eq(Snapshot.objectLabel({ graphicsId = 72, def = {} }, { rivalName = "GARY" }), "GARY", "Blue's sheet named as the rival")
  eq(Snapshot.objectLabel({ graphicsId = 23, def = {} }, {}), "Woman", "people named by graphics, number dropped")
  eq(Snapshot.objectLabel({ graphicsId = 0, def = {} }, {}), "Trainer", "the player's sheet on someone else is a Trainer")
  eq(Snapshot.objectLabel({ graphicsId = 71, def = {} }, {}), "Professor Oak", "Professor Oak")
  eq(Snapshot.objectLabel({ graphicsId = 240, def = {} }, {}), "Person", "an unresolved variable sprite is only a Person")
  eq(Snapshot.objectLabel({ graphicsId = 28, def = {} }, {}), "Receptionist",
    "the link receptionist is no link partner (its sheet starts with LINK)")
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
  -- ice against a wall is a plain step, not "slide 0 cells"
  options = nav:routeOptionsFor(worldOn(spin, 2, 3), { { x = 8, y = 5 } }, 1)
  found = nil
  for _, edge in ipairs(options.neighbors(2, 3)) do
    if edge.direction == "left" then found = edge end
  end
  check(found and found.x == 1 and found.kind == nil and found.instruction == nil,
    "a step onto ice that cannot slide is a plain step: " .. tostring(found and found.instruction))
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

-- ------------------------------------------------------------ opening a way
-- A boulder in the only corridor, no switch or hole on the floor (the Warden's House,
-- Mt. Ember): the first push that opens the way, and none when nothing could.
do
  local nav = navFor()
  local floor = mapDef("FR_TEST_OPENING", {
    "#########",
    "#.......#",
    "###.#.###",
    "#.......#",
    "#########",
  })
  local function boulderAt(x, y, id)
    return { cellX = x, cellY = y, graphicsId = 97, currentElevation = 3, localId = id,
      def = { graphicsId = 97, index = id } }
  end
  local world = worldOn(floor, 1, 1, { boulderAt(3, 1, 1) })
  local plan, why = Puzzle.planOpening(world, { { x = 7, y = 1 } }, nav:routeOptionsFor(nav:withoutBoulders(world),
    { { x = 7, y = 1 } }, 2).neighbors)
  check(plan ~= nil and plan.direction == "right" and plan.standX == 2,
    "a boulder pushed along the corridor clears the side way round it: " .. tostring(why))
  local side = worldOn(floor, 2, 1, { boulderAt(3, 2, 1) })
  local free, freeWhy = Puzzle.planOpening(side, { { x = 7, y = 1 } }, nav:routeOptionsFor(nav:withoutBoulders(side),
    { { x = 7, y = 1 } }, 2).neighbors)
  eq(freeWhy, "open", "nothing to push when the way is free")
  check(free == nil, "and no plan")
  local room = mapDef("FR_TEST_OPENING2", {
    "#######",
    "#.....#",
    "#.....#",
    "###.###",
    "#.....#",
    "#######",
  })
  local blocked = worldOn(room, 1, 1, { boulderAt(3, 3, 1), boulderAt(3, 2, 2) })
  local goals = { { x = 1, y = 4 } }
  local first = Puzzle.planOpening(blocked, goals, nav:routeOptionsFor(nav:withoutBoulders(blocked), goals, 2).neighbors)
  check(first == nil, "a boulder pushed into the only gap cannot be got past: no plan")
  local aside = worldOn(room, 1, 2, { boulderAt(3, 2, 1) })
  local g = { { x = 3, y = 3 } }
  local opened = Puzzle.planOpening(aside, g, nav:routeOptionsFor(nav:withoutBoulders(aside), g, 2).neighbors)
  check(opened ~= nil and opened.standY == 2 and (opened.direction == "left" or opened.direction == "right"),
    "pushing the boulder along the row opens the gap")
  -- with goals, boulderOpening says "open" once a route exists, not "all in place"
  local plain = worldOn(room, 1, 1, {})
  local _, reason, _, stone = nav:boulderOpening(plain, { { x = 3, y = 3 } })
  eq(reason, "open", "with a free way the walk goes on")
  check(stone == false, "aiming at a target is not a floor to finish")
  -- a walk asked for the floor itself ignores what the selection's cells are
  local _, wholeReason, _, wholeStone = nav:boulderOpening(plain, { { x = 3, y = 3 } }, true)
  eq(wholeReason, "finished", "no boulders left on a floor being finished")
  check(wholeStone == true, "that walk stays a floor walk")
end

-- The Area list has the floors themselves; being on one is the arrival.
do
  local nav = navFor()
  maps.FR_TEST_TOWER_1F = mapDef("FR_TEST_TOWER_1F", { "###", "#.#", "###" })
  maps.FR_TEST_TOWER_2F = mapDef("FR_TEST_TOWER_2F", { "###", "#.#", "###" })
  local world = worldOn(maps.FR_TEST_TOWER_1F, 1, 1)
  nav.currentMapIdOf = function() return "FR_TEST_TOWER_1F" end
  local items = nav:areaBrowse(world)
  local entry
  for _, item in ipairs(items) do if item.mapId == "FR_TEST_TOWER_2F" then entry = item end end
  check(entry ~= nil and entry.floorEntry == true, "the other floor is an Area target")
  maps.FR_TEST_TOWER_1F, maps.FR_TEST_TOWER_2F = nil, nil
end

-- ------------------------------------------------------------ item balls
do
  local hall = mapDef("FR_TEST_HALL", { "#######", "#.....#", "###.###", "#.....#", "#######" })
  maps.FR_TEST_HALL = hall
  local nav = navFor()
  local function ball(scriptKey)
    return { cellX = 3, cellY = 2, graphicsId = 92, def = { graphicsId = 92, scriptKey = scriptKey, index = 1 } }
  end
  local r = route(nav, worldOn(hall, 1, 1, { ball("ball") }), { { x = 5, y = 3 } }, 1)
  check(r == nil, "an item ball in the only way blocks a walk-only route")
  local world = worldOn(hall, 1, 1, { ball("ball") })
  r = route(nav, world, { { x = 5, y = 3 } }, 2)
  check(r and kinds(r):find("down(item_ball)", 1, true) ~= nil, "policy 2 picks the ball up and walks on: " .. kinds(r))
  local said = r and table.concat(nav:routeNarration(world, r, 2), ", ") or ""
  check(said:find("Pick up [^,]+ facing down, then move down") ~= nil, "the pickup is said: " .. said)
  local step
  for _, s in ipairs(r and r.steps or {}) do if s.kind == "item_ball" then step = s end end
  local action = step and nav:stepInteraction(world, step)
  eq(action and action.move, "item", "auto-walk presses A facing the ball")
  r = route(nav, worldOn(hall, 1, 1, { ball("gift") }), { { x = 5, y = 3 } }, 2)
  check(r == nil, "a gift Poke Ball (no item ball script) is never walked through")
  -- with a way round, walking (policy 1, tried first) goes round
  local loop = mapDef("FR_TEST_LOOP", { "#######", "#.....#", "#.#.#.#", "#.....#", "#######" })
  maps.FR_TEST_LOOP = loop
  r = route(nav, worldOn(loop, 3, 1, { ball("ball") }), { { x = 3, y = 3 } }, 1)
  check(r and #r.steps == 6 and not kinds(r):find("item_ball", 1, true), "a detour is walked round the ball: " .. kinds(r))
end

-- ------------------------------------------------------------ card key doors
do
  -- a planned floor draws its doors open (the load script closes those
  -- whose own flag is unset): the door's flag decides there
  local floor = mapDef("FR_TEST_DOORS", { "#######", "#.....#", "###.###", "#.....#", "#######" }, {},
    { bgEvents = { { type = "sign", x = 3, y = 2, scriptKey = "door" } } })
  maps.FR_TEST_DOORS = floor
  eq(Scripts.cardKeyDoorOpenFlag("door"), 640, "a door's own flag is the first its script checks")
  local nav = navFor()
  local world = worldOn(floor, 3, 1)
  check(nav:isClosedCardKeyDoorCell(world, 3, 2), "an unopened door on a planned floor is closed")
  check(route(nav, world, { { x = 3, y = 3 } }, 2) == nil, "a closed door blocks without the Card Key")
  local r = route(nav, world, { { x = 3, y = 3 } }, 3)
  local said = r and table.concat(nav:routeNarration(world, r, 3), ", ") or ""
  check(said:find("Use Card Key facing down", 1, true) ~= nil, "with the key the door is opened on the way: " .. said)
  maps.FR_TEST_DOORS = nil
end

-- ------------------------------------------------------------ journeys
do
  -- A ladder on A leads to B; on B the way to the target runs down a
  -- one-cell corridor at (5,2).
  local A = mapDef("FR_TJ_ROOM_A", { "#####", "#...#", "#..W#", "#####" },
    { { x = 3, y = 2, destMap = "FR_TJ_ROOM_B", destWarp = 1 } })
  local function bMap(corridor)
    return mapDef("FR_TJ_ROOM_B", { "#######", "#W....#", "#####" .. corridor .. "#", "#.....#", "#######" },
      { { x = 1, y = 1, destMap = "FR_TJ_ROOM_A", destWarp = 1 } })
  end
  maps.FR_TJ_ROOM_A, maps.FR_TJ_ROOM_B = A, bMap(".")
  local nav = navFor()
  local start = { mapId = "FR_TJ_ROOM_A", x = 1, y = 1 }
  local target = { mapId = "FR_TJ_ROOM_B", goals = { { x = 1, y = 3 } } }
  local result, why = nav:journeySearch(start, target, 1, nil)
  check(result ~= nil, "a journey through a ladder is planned: " .. tostring(why))
  local first = result and result.firstTransition
  check(first and first.destMap == "FR_TJ_ROOM_B" and first.x == 3 and first.y == 2,
    "the first leg ends on A's ladder")
  check(result and not result.final, "the target is on another map: not the final leg")
  -- arriving on B's ladder, the player walks off it (it does not send them
  -- back): 3 steps on A, the ladder, 10 steps on B
  eq(result and result.cost, 14, "the journey walks off the ladder it arrived on")
  result = nav:journeySearch({ mapId = "FR_TJ_ROOM_B", x = 2, y = 1 }, target, 1, nil)
  check(result and result.final, "on the target's map the leg is final")
  -- an item ball in B's corridor: policy 1 no path, policy 2 through it
  maps.FR_TJ_ROOM_B = bMap(".")
  maps.FR_TJ_ROOM_B.objects = { { x = 5, y = 2, graphicsId = 92, scriptKey = "ball", index = 1, localId = 1 } }
  result, why = nav:journeySearch(start, target, 1, nil)
  eq(why, "no regional path", "a ball in the only corridor blocks a walking journey")
  result = nav:journeySearch(start, target, 2, nil)
  check(result ~= nil, "policy 2 journeys pick the ball up")
  -- water in the corridor: only Surf opens it, and the reason says so
  maps.FR_TJ_ROOM_B = bMap("~")
  result = nav:journeySearch(start, target, 2, nil)
  check(result == nil, "no journey over water without Surf")
  result = nav:journeySearch(start, target, 3, nil)
  eq(result and nav:journeyRequirement(result), "Needs Surf", "the journey's missing capability is named")
  -- the maps a journey may cross: the target's area plus the player's map
  local allowed = nav:journeyMaps("FR_TJ_ROOM_A", "FR_TJ_ROOM_B")
  check(allowed and allowed.FR_TJ_ROOM_A and allowed.FR_TJ_ROOM_B and not allowed.FR_TEST_HUB,
    "a journey stays inside its area")
  check(nav:journeyMaps("FR_TEST_HUB", "FR_TJ_ROOM_B") == nil, "a target outside the area may cross any map")
  -- outside the allowed maps there is no way
  result, why = nav:journeySearch(start, target, 1, { FR_TJ_ROOM_A = true })
  eq(why, "no regional path", "maps outside the allowed set are not entered")
  maps.FR_TJ_ROOM_A, maps.FR_TJ_ROOM_B = nil, nil
end

-- ------------------------------------------------------------ load scripts
do
  local flagsOn = {}
  local function flag(id) return flagsOn[id] == true end
  local state = Scripts.loadState({ mapScripts = { onLoad = "load_gates" } }, flag)
  check(state and next(state.cells) == nil, "a flag unset: its setmetatile calls are not on the path")
  flagsOn[620] = true
  state = Scripts.loadState({ mapScripts = { onLoad = "load_gates" } }, flag)
  check(state and state.cells[2 * 1024 + 3] and state.cells[2 * 1024 + 3].impassable, "flag set: the gate closes")
  eq(state and state.cells[1 * 1024 + 1].impassable, false, "and another opens")
  flagsOn[620] = nil
  state = Scripts.loadState({ mapScripts = { onTransition = "load_count" } }, flag)
  eq(state and state.layoutIndex, 278, "both flags unset, counted in a temporary variable: the layout is swapped")
  flagsOn[70] = true
  state = Scripts.loadState({ mapScripts = { onTransition = "load_count" } }, flag)
  eq(state and state.layoutIndex, nil, "one flag set: the layout stays")
  flagsOn[70] = nil
  local none, why = Scripts.loadState({ mapScripts = { onLoad = "load_special" } }, flag)
  check(none == nil and tostring(why):find("^special") ~= nil, "a special cannot be read: " .. tostring(why))

  -- the view: gates on a planned floor, and a swapped layout
  local floor = mapDef("FR_TEST_LOADED", { "#######", "#.....#", "###.###", "#.....#", "#######" }, {},
    { mapScripts = { onLoad = "load_gates" } })
  maps.FR_TEST_LOADED = floor
  local Flags = { getFlag = function(_, _, id) return flagsOn[id] == true end, getVar = function() return 0 end }
  package.loaded["src.core.game3.scripting.space"] = { store = {} }
  package.loaded["src.core.game3.scripting.flags"] = Flags
  local nav = navFor()
  local world = nav:regionalStaticWorld("FR_TEST_LOADED", { x = 3, y = 1 })
  check(route(nav, world, { { x = 3, y = 3 } }, 1) ~= nil, "the planned floor as the layout has it")
  flagsOn[620] = true
  world = nav:regionalStaticWorld("FR_TEST_LOADED", { x = 3, y = 1 })
  check(route(nav, world, { { x = 3, y = 3 } }, 1) == nil, "the load script's closed gate blocks the planned route")
  flagsOn[620] = nil
  world = nav:regionalStaticWorld("FR_TEST_LOADED", { x = 3, y = 1 })
  check(route(nav, world, { { x = 3, y = 3 } }, 1) ~= nil, "gates follow the flag each time")
  -- a whole-layout swap: water in the corridor in the base, floor in the alternate
  local base = mapDef("FR_TEST_SWAP", { "#######", "#.....#", "###~###", "#.....#", "#######" }, {},
    { mapScripts = { onTransition = "load_count" } })
  maps.FR_TEST_SWAP = base
  World.alternateReader = function(id)
    eq(id, 278, "the alternate layout asked for by number")
    local cells = {}
    for i = 1, 35 do cells[i] = { mid = 1000, coll = 0x00, elev = 3 } end
    return { width = 7, height = 5, cells = cells }
  end
  world = nav:regionalStaticWorld("FR_TEST_SWAP", { x = 3, y = 1 })
  eq(world.map:isWater(3, 2), false, "the planned floor reads the swapped layout")
  flagsOn[70] = true
  world = nav:regionalStaticWorld("FR_TEST_SWAP", { x = 3, y = 1 })
  eq(world.map:isWater(3, 2), true, "with the flag set the base layout stands")
  World.alternateReader = nil
  flagsOn[70] = nil
  maps.FR_TEST_LOADED, maps.FR_TEST_SWAP = nil, nil

  -- ---------------------------------------------------------- elevators
  local function shaftMaps(panelKey)
    maps.FR_TEST_SHAFT_CAR = mapDef("FR_TEST_SHAFT_CAR", { "#####", "#...#", "#...#", "#####" }, {},
      { bgEvents = { { type = "sign", x = 2, y = 0, kind = 0, scriptKey = panelKey } } })
    maps.FR_TEST_SHAFT_A = mapDef("FR_TEST_SHAFT_A", { "#####", "#...#", "#####" }, {})
    maps.FR_TEST_SHAFT_B = mapDef("FR_TEST_SHAFT_B", { "#####", "#...#", "#####" }, {})
  end
  local labelled = Scripts.itemLabel
  Scripts.itemLabel = function(id) if id == 356 then return "Lift Key" end return labelled(id) end
  shaftMaps("panel_free")
  local panel = Scripts.elevatorPanel("panel_free")
  eq(panel and #panel.floors, 2, "the panel's floors, from its setdynamicwarp commands")
  eq(panel and panel.floors[2].mapId, "FR_TEST_SHAFT_B", "floors named from their group and number")
  eq(panel and panel.gateFlag, nil, "no gate on a free panel")
  local gated = Scripts.elevatorPanel("panel_gated")
  eq(gated and gated.gateFlag, 677, "the flag checked before the floors is the gate")
  eq(Scripts.itemSettingFlag(677), 356, "the item whose receipt sets that flag")
  nav = navFor()
  local function liveOn(mapId, x, y)
    local w = nav:regionalStaticWorld(mapId, { x = x, y = y })
    nav.worldForCommand = function() return w end
    return w
  end
  liveOn("FR_TEST_SHAFT_CAR", 1, 2)
  local leg, reason = nav:regionalNextLeg({ targetMapId = "FR_TEST_SHAFT_B", targetGoals = { { x = 3, y = 1 } } })
  check(leg and leg.stopAtGoal, "an elevator leg ends at the panel: " .. tostring(reason))
  eq(leg and leg.goals[1].x .. "," .. leg.goals[1].y, "2,1", "the cell the panel is used from")
  eq(leg and leg.stopText, "Arrived at the floor panel. Face up and take the elevator to B",
    "the instruction names the floor without the car's own words")
  local parts = {}
  if leg then leg.appendInstructions(parts) end
  check(parts[1] and parts[1]:find("take the elevator to B", 1, true) ~= nil, "guided navigation says it too")
  -- a way that can be walked is preferred to the menu
  maps.FR_TEST_SHAFT_CAR = mapDef("FR_TEST_SHAFT_CAR", { "#####", "#...#", "#..W#", "#####" },
    { { x = 3, y = 2, destMap = "FR_TEST_SHAFT_B", destWarp = 1 } },
    { bgEvents = { { type = "sign", x = 2, y = 0, kind = 0, scriptKey = "panel_free" } } })
  maps.FR_TEST_SHAFT_B = mapDef("FR_TEST_SHAFT_B", { "#####", "#W..#", "#####" },
    { { x = 1, y = 1, destMap = "FR_TEST_SHAFT_CAR", destWarp = 1 } })
  liveOn("FR_TEST_SHAFT_CAR", 1, 1)
  leg = nav:regionalNextLeg({ targetMapId = "FR_TEST_SHAFT_B", targetGoals = { { x = 3, y = 1 } } })
  check(leg and not leg.stopAtGoal and leg.goals[1].x == 3, "the ladder is taken, not the elevator")
  -- the gate
  shaftMaps("panel_gated")
  liveOn("FR_TEST_SHAFT_CAR", 1, 2)
  leg, reason = nav:regionalNextLeg({ targetMapId = "FR_TEST_SHAFT_B", targetGoals = { { x = 3, y = 1 } } })
  check(leg == nil and reason == "Needs Lift Key", "a gated panel without its key: " .. tostring(reason))
  flagsOn[677] = true
  leg, reason = nav:regionalNextLeg({ targetMapId = "FR_TEST_SHAFT_B", targetGoals = { { x = 3, y = 1 } } })
  check(leg and leg.stopAtGoal, "with the flag set the elevator is a leg: " .. tostring(reason))
  flagsOn[677] = nil
  Scripts.itemLabel = labelled
  maps.FR_TEST_SHAFT_CAR, maps.FR_TEST_SHAFT_A, maps.FR_TEST_SHAFT_B = nil, nil, nil

  -- ---------------------------------------------------------- thin ice
  maps.FR_TEST_CAVE_1F = mapDef("FR_TEST_CAVE_1F", { "#######", "#..t.##", "#######" }, {},
    { mapScripts = { onResume = "ice_resume", onFrame = { { script = "ice_frame", var = 16385, value = 1 } } } })
  maps.FR_TEST_CAVE_B1 = mapDef("FR_TEST_CAVE_B1", { "#######", "#.....#", "#######" }, {})
  eq(Scripts.crackedIceDrop(maps.FR_TEST_CAVE_1F), "FR_TEST_CAVE_B1", "the frame script's hole, on a floor that cracks")
  eq(Scripts.crackedIceDrop(maps.FR_TEST_CAVE_B1), nil, "a floor that does not crack")
  liveOn("FR_TEST_CAVE_1F", 1, 1)
  leg, reason = nav:regionalNextLeg({ targetMapId = "FR_TEST_CAVE_B1", targetGoals = { { x = 5, y = 1 } } })
  check(leg and leg.danceAtGoal and not leg.stopAtGoal, "falling through thin ice is a leg auto-walk takes itself: " .. tostring(reason))
  eq(leg and leg.goals[1].x, 3, "it ends on the thin ice")
  parts = {}
  if leg then leg.appendInstructions(parts) end
  check(parts[1] and parts[1]:find("Step off the thin ice and back onto it", 1, true) ~= nil, "guided navigation says how: " .. tostring(parts[1]))
  maps.FR_TEST_CAVE_1F = mapDef("FR_TEST_CAVE_1F", { "#######", "#..c.##", "#######" }, {},
    { mapScripts = { onResume = "ice_resume", onFrame = { { script = "ice_frame", var = 16385, value = 1 } } } })
  liveOn("FR_TEST_CAVE_1F", 1, 1)
  leg = nav:regionalNextLeg({ targetMapId = "FR_TEST_CAVE_B1", targetGoals = { { x = 5, y = 1 } } })
  check(leg and not leg.stopAtGoal and not leg.danceAtGoal, "cracked ice is simply walked onto")
  maps.FR_TEST_CAVE_1F, maps.FR_TEST_CAVE_B1 = nil, nil
  package.loaded["src.core.game3.scripting.space"] = nil
  package.loaded["src.core.game3.scripting.flags"] = nil
end

-- ------------------------------------------------------------ Strength plans
do
  -- The Tanoby Key room's floor (seven boulders, seven switches; read from
  -- FireRed's SEVEN_ISLAND_SEVAULT_CANYON_TANOBY_KEY in a game run): the
  -- whole plan takes more than one request's time, so it is searched on
  -- across calls, kept, and followed push by push to the end.
  local rows = {
    "################", "################", "#######S########", "######...#######",
    "####S.....S#####", "#####.#.#.######", "#####S...S######", "######...#######",
    "#####S...S######", "#####.....######", "#####.....######", "#####.###.######",
    "#####.....######", "#####.....######", "################", "################" }
  local room = mapDef("FR_TEST_TANOBY", rows)
  maps.FR_TEST_TANOBY = room
  local npcs = {}
  for i, p in ipairs({ { 6, 6 }, { 7, 6 }, { 8, 6 }, { 6, 9 }, { 8, 9 }, { 6, 10 }, { 8, 10 } }) do
    npcs[i] = { cellX = p[1], cellY = p[2], graphicsId = 97, currentElevation = 3, localId = i,
      def = { graphicsId = 97, index = i } }
  end
  local world = worldOn(room, 7, 12, npcs)
  local targets, boulders = Puzzle.targetsFor(world)
  eq(#targets .. "/" .. #boulders, "7/7", "seven switches and seven boulders")
  local task = Puzzle.newPlanTask(world, targets, boulders)
  local plan, why = task.run(0.01)
  eq(why, "budget", "a short slice leaves the search running, with no push given")
  local slices = 1
  while not plan and why == "budget" and slices < 2000 do
    plan, why = task.run(0.05)
    slices = slices + 1
  end
  check(plan ~= nil, "the search carried on across slices to a whole plan (" .. slices .. " slices)")
  check(plan and #plan.steps == plan.pushes and #plan.states == plan.pushes, "the plan keeps every push")
  local pushes, push = 0, plan
  while push and pushes < 100 do
    local d = World.DELTA[push.direction]
    world.player.cellX, world.player.cellY = push.standX, push.standY
    local b = push.boulder.entity
    b.cellX, b.cellY = b.cellX + d[1], b.cellY + d[2]
    pushes = pushes + 1
    targets, boulders = Puzzle.targetsFor(world)
    push = Puzzle.followPlan(plan, world, boulders)
  end
  local open = 0
  for _, t in ipairs(targets) do if not t.solved then open = open + 1 end end
  eq(open, 0, "following the kept plan presses all seven switches (" .. pushes .. " pushes)")
  -- describe: while the search runs the help says so and names no push
  Puzzle._resetPlansForTests()
  for i, p in ipairs({ { 6, 6 }, { 7, 6 }, { 8, 6 }, { 6, 9 }, { 8, 9 }, { 6, 10 }, { 8, 10 } }) do
    npcs[i].cellX, npcs[i].cellY = p[1], p[2]
  end
  world.player.cellX, world.player.cellY = 7, 12
  local saved = Puzzle.DESCRIBE_SECONDS
  Puzzle.DESCRIBE_SECONDS = 0.01
  local nav = navFor()
  nav.strengthActive = function() return true end
  allowed.STRENGTH = true
  local described = Puzzle.describe(game, world, nav)
  check(described.searching and described.nextAction == nil, "while searching there is no next push")
  local state = described.targetStates[1] and described.targetStates[1].state or ""
  check(state:find("still working out", 1, true) ~= nil, "the switch says the plan is still being worked out: " .. state)
  local frames = 0
  while Puzzle.continueSearch(world, 0.05) and frames < 2000 do frames = frames + 1 end
  described = Puzzle.describe(game, world, nav)
  check(described.nextAction ~= nil, "after the frames' slices the next push is known (" .. frames .. " frames)")
  Puzzle.DESCRIBE_SECONDS = saved
  allowed.STRENGTH = nil
  maps.FR_TEST_TANOBY = nil
end

-- ------------------------------------------------------------ renaming
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
-- Flavor furniture (windows, bookshelves, kitchens, paintings) goes under Misc;
-- furniture that does something stays in Objects (decisions 34 and 36).
do
  local behaviors = { [0] = 0x9C, [1] = 0x81, [2] = 0x8A, [3] = 0x94, [4] = 0x85, [5] = 0x83 }
  local world = {
    player = { cellX = 0, cellY = 1 },
    map = { id = "FR_TEST", widthCells = 6, heightCells = 1, def = { id = "FR_TEST" },
      behavior = function(_, x) return behaviors[x] end },
  }
  local Shared = require("src.access.nav.WorldSnapshot")
  local Gen3Snapshot = require("src.access.nav.gen3.WorldSnapshot")
  local objects = navFor():interactiveBrowseObjects(world, { objects = {} })
  local function listed(filter)
    local labels = {}
    for _, item in ipairs(Shared.browse({ player = world.player, map = world.map, npcs = {} },
        { filter = filter, interactiveObjects = objects })) do
      labels[#labels + 1] = item.label
    end
    table.sort(labels)
    return table.concat(labels, ",")
  end
  eq(listed("objects"), "PC,Town Map", "the PC and wall map stay in Objects")
  eq(listed("all"), "PC,Town Map", "All leaves scenery out")
  eq(listed("misc"), "Bookshelf,Kitchen,Painting,Window", "flavor furniture is listed under Misc")
  eq(Gen3Snapshot.nextFilter("objects", 1), "misc", "Misc follows Objects in Gen 3")
  eq(Gen3Snapshot.nextFilter("misc", 1), "area", "Area follows Misc")
  eq(Gen3Snapshot.nextFilter("all", -1), "area", "cycling back from All still reaches Area")
  eq(Shared.nextFilter("objects", 1), "area", "Gen 1 and 2 have no Misc stop")
  eq(Gen3Snapshot.humanize("misc"), "Misc", "the category is spoken as Misc")
end

-- People and Pokemon have their own category; things stay under Objects, and
-- all of them stay type "object" for routing (decision 35).
do
  local Shared = require("src.access.nav.WorldSnapshot")
  eq(Shared.nextFilter("signposts", 1), "npcs", "NPCs follows Signposts")
  eq(Shared.nextFilter("npcs", 1), "objects", "Objects follows NPCs")
  eq(Shared.humanize("npcs"), "NPCs", "the category is spoken as NPCs")
  local function actor(x, def) return { cellX = x, cellY = 0, facing = "down", def = def } end
  local world = {
    player = { cellX = 0, cellY = 0, facing = "down" },
    map = { id = "TEST", widthCells = 8, heightCells = 1, def = { id = "TEST", label = "Test" } },
    npcs = {
      actor(1, { index = 1, sprite = "SPRITE_NURSE", accessibilityLabel = "Nurse" }),
      actor(2, { index = 2, sprite = "SPRITE_SNORLAX", accessibilityLabel = "Snorlax" }),
      actor(3, { index = 3, sprite = "SPRITE_POKE_BALL", item = "POTION" }),
      actor(4, { index = 4, sprite = "SPRITE_BOULDER", accessibilityLabel = "Boulder" }),
      actor(5, { index = 5, sprite = "SPRITE_POKE_BALL", accessibilityLabel = "Gift Ball" }),
      actor(6, { index = 6, accessibilityKind = "thing", accessibilityLabel = "Tree" }),
    },
  }
  local function labels(filter)
    local items, out = Shared.browse(world, { filter = filter }), {}
    for _, item in ipairs(items) do out[#out + 1] = item.label end
    table.sort(out)
    return table.concat(out, ",")
  end
  eq(labels("npcs"), "Nurse,Snorlax", "people and Pokemon are NPCs")
  eq(labels("objects"), "Boulder,Gift Ball,Potion,Tree", "items and things are Objects")
  local nurse = Shared.browse(world, { filter = "npcs" })[1]
  eq(nurse.type, "object", "an NPC still routes as an object")
  eq(nurse.category, "npcs", "an NPC's category is npcs")
end

do
  -- a sign's words on one line (Ruby, Sapphire and Emerald's texts, from the cartridge)
  local Scripts = require("src.access.nav.gen3.Scripts")
  local line = Scripts.signLine
  local open, close, dots = "\226\128\156", "\226\128\157", "\226\128\166"
  eq(line("ROUTE 1O4\n{RIGHT_ARROW} PETALBURG CITY"), "ROUTE 104, east: PETALBURG CITY",
    "a route sign: its arrow says which way, and 1O4 is a number")
  eq(line("{RIGHT_ARROW} TRAINER HILL ENTRANCE\n\n" .. open .. "Scale the heights, you hot-blooded\nTRAINERS!" .. close),
    "east: TRAINER HILL ENTRANCE", "an arrow first; the first page is long enough")
  eq(line("TRAINER TIPS\n\nIn the HOENN region there are pairs\nof TRAINERS who challenge others\n\nfor 2-on-2"),
    "TRAINER TIPS In the HOENN region there are pairs of TRAINERS who", "a short first page takes the next, cut at a word")
  eq(line("Wanted itemTrade item\nRED SHARD{LEFT_ARROW}{RIGHT_ARROW}FIRE STONE\n\nWanted item"),
    "Wanted item, Trade item RED SHARD for FIRE STONE", "a table's columns and its two-way arrow")
  eq(line("IDENTIFYING GOOD\n" .. open .. "{STR_VAR_1}" .. close .. " &\n\nBAD " .. open .. "{STR_VAR_2}" .. close .. dots),
    "IDENTIFYING GOOD & BAD" .. dots, "quotes a filled-in word leaves empty are dropped")
  eq(line("The Battle Tournament rules\nare listed."), "The Battle Tournament rules are listed.", "lines are joined")
  eq(line(open .. "Our family's hearts beat as one!" .. close .. "\nTHE WINSTRATE'S HOUSE"),
    open .. "Our family's hearts beat as one!" .. close .. " THE WINSTRATE'S HOUSE", "quotes with words stay")
  eq(line("MT. CHIMNEY CABLE CAR\n" .. open .. "A short walk {UP_ARROW} way!" .. close),
    "MT. CHIMNEY CABLE CAR " .. open .. "A short walk up way!" .. close, "an arrow inside a sentence is a word")
  eq(line("It's a Nintendo GameCube."), "It's a Nintendo GameCube.", "a word with a capital inside stays whole")
  eq(line("Hi, there! Did you want to blend some {STR_VAR_1}S with us?"),
    "Hi, there! Did you want to blend some with us?", "a filled-in word goes with its S")
  eq(line("\n\n"), nil, "nothing to say")
end

do
  -- Littleroot's houses: the one that matches the player's gender is the player's own
  local Snapshot = require("src.access.nav.gen3.WorldSnapshot")
  local GameData = require("src.access.nav.gen3.GameData")
  local isHoenn, bare, gender = GameData.isHoenn, GameData.bareMapId, Snapshot.playerGender
  GameData.isHoenn = function() return true end
  GameData.bareMapId = function(id) return (id:gsub("^EM_", "")) end
  Snapshot.playerGender = function() return 0 end
  eq(Snapshot.locationName({ id = "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F" }, nil, nil, "Alex", nil),
    "Alex's House 1F", "a boy's own house is his")
  eq(Snapshot.locationName({ id = "EM_LITTLEROOT_TOWN_MAYS_HOUSE_2F" }, nil, nil, "Alex", nil),
    "Littleroot Town May's House 2F", "the other house stays the rival's")
  Snapshot.playerGender = function() return 1 end
  eq(Snapshot.locationName({ id = "EM_LITTLEROOT_TOWN_MAYS_HOUSE_2F" }, nil, nil, nil, nil),
    "Your House 2F", "a girl's own house, before she has a name")
  eq(Snapshot.mapIdName("EM_METEOR_FALLS_B1F_2R"), "Meteor Falls B1F Room 2", "a room number is spelt out")
  Snapshot.playerGender = function() return nil end
  eq(Snapshot.locationName({ id = "EM_LITTLEROOT_TOWN_MAYS_HOUSE_1F" }, nil, nil, "Alex", nil),
    "Littleroot Town May's House 1F", "no session: the map's own name")
  GameData.isHoenn, GameData.bareMapId, Snapshot.playerGender = isHoenn, bare, gender
end

do
  -- a trainer drawn with a plain sheet is named by the class the battle shows
  local Snapshot = require("src.access.nav.gen3.WorldSnapshot")
  local Scripts = require("src.access.nav.gen3.Scripts")
  eq(Snapshot.classLabel("BIRD KEEPER"), "Bird Keeper", "a class in the ROM's capitals")
  eq(Snapshot.classLabel("PKMN RANGER"), "Pok\195\169mon Ranger", "PKMN spelt out")
  eq(Snapshot.classLabel("SWIMMER\226\153\130"), "Swimmer", "the gender sign goes")
  eq(Snapshot.classLabel("SR. AND JR."), "Sr. and Jr.", "a pair's class")
  eq(Snapshot.classLabel("POK\195\169FAN"), "Pok\195\169 Fan", "as the sheet's own label spells it")
  local trainersModule = package.loaded["src.core.game3.scripting.trainers"]
  package.loaded["src.core.game3.scripting.trainers"] = { info = function(id)
    return ({ [7] = { className = "BIRD KEEPER" }, [8] = { className = "PKMN TRAINER" } })[id]
  end }
  Scripts.setSource({
    keeper = { { op = "trainerbattle", trainer = 7 }, { op = "end" } },
    wally = { { op = "trainerbattle", trainer = 8 } },
    talker = { { op = "msgbox" } },
  })
  Snapshot.setGraphicsNames({ [23] = "OBJ_EVENT_GFX_MAN_5", [40] = "OBJ_EVENT_GFX_HIKER" })
  eq(Snapshot.objectLabel({ graphicsId = 23, def = { scriptKey = "keeper" } }, {}), "Bird Keeper", "a plain sheet takes the class")
  eq(Snapshot.objectLabel({ graphicsId = 23, def = { scriptKey = "wally" } }, {}), "Man", "a title is no better than the sheet")
  eq(Snapshot.objectLabel({ graphicsId = 23, def = { scriptKey = "talker" } }, {}), "Man", "no battle, no class")
  eq(Snapshot.objectLabel({ graphicsId = 40, def = { scriptKey = "keeper" } }, {}), "Hiker", "a sheet that names a class keeps it")
  Scripts.setSource(nil)
  Snapshot.setGraphicsNames(nil)
  package.loaded["src.core.game3.scripting.trainers"] = trainersModule
end

do
  -- places the story or the tide keeps shut say so, where nothing else explains a refusal
  local Navigation3 = require("src.access.nav.gen3.Navigation")
  local nav = setmetatable({}, { __index = Navigation3 })
  local function world(id, water, blocked)
    return { map = { id = id, widthCells = 10, heightCells = 10,
      isWater = function(_, x, y) return water and water[x .. "," .. y] == true end,
      overrideBlocked = function(_, x, y) return blocked and blocked[x .. "," .. y] == true end } }
  end
  eq(nav:closedForNow(world("EM_DESERT_RUINS"), { { x = 1, y = 1 } }),
    "Sealed: the braille on the far wall says how to open it", "a sealed chamber")
  nav.shoalHighTide = function() return false end
  eq(nav:closedForNow(world("EM_SHOAL_CAVE_LOW_TIDE_INNER_ROOM"), { { x = 1, y = 1 } }),
    "Not at low tide: this part is reached at high tide", "Shoal Cave at low tide")
  nav.shoalHighTide = function() return true end
  eq(nav:closedForNow(world("EM_SHOAL_CAVE_LOW_TIDE_INNER_ROOM"), { { x = 1, y = 1 } }),
    "Not at high tide: this part is reached at low tide", "the same room at high tide: the flag, not the map's name")
  eq(nav:closedForNow(world("EM_LILYCOVE_CITY", { ["5,5"] = true }, { ["7,5"] = true }), { { x = 5, y = 5 } }),
    "Blocked by a group of Wailmer", "Lilycove's water while the Wailmer are drawn")
  eq(nav:closedForNow(world("EM_LILYCOVE_CITY", { ["5,5"] = true }, {}), { { x = 5, y = 5 } }), nil,
    "no Wailmer, no such reason")
  eq(nav:closedForNow(world("EM_LILYCOVE_CITY", { ["5,5"] = true }, { ["7,5"] = true }), { { x = 2, y = 2 } }), nil,
    "a door in town is not the Wailmer's")
  eq(nav:closedForNow(world("EM_ROUTE110"), { { x = 1, y = 1 } }), nil, "anywhere else says nothing")
end

do
  -- Things down a current (Navigation:farMaps, farTargets): the Area list has the item
  -- balls of maps entered the way their currents run, and their journey takes the lane
  local Navigation3 = require("src.access.nav.gen3.Navigation")
  CELL["<"] = { 0x29, 0x51, 1 }
  local function sea(id, rows, connections, objects)
    return mapDef(id, rows, {}, { connections = connections, objects = objects or {} })
  end
  maps.FR_FAR_TOWN = sea("FR_FAR_TOWN", { "~~~~", "~~~~", "~~~~" },
    { { dir = "west", map = "FR_FAR_SEA_A", offset = 0 } })
  -- two lanes, joined only at the east end
  maps.FR_FAR_SEA_A = sea("FR_FAR_SEA_A", { "<<<<<~", "#####~", "<<<<<~" },
    { { dir = "east", map = "FR_FAR_TOWN", offset = 0 }, { dir = "west", map = "FR_FAR_SEA_B", offset = 0 } })
  -- the ball's sandbar is at the end of the north lane only
  local ball = { x = 0, y = 0, graphicsId = 92, scriptKey = "far_ball", index = 1, localId = 1 }
  maps.FR_FAR_SEA_B = sea("FR_FAR_SEA_B", { "..~<<<<<", "########", "~~~<<<<<" },
    { { dir = "east", map = "FR_FAR_SEA_A", offset = 0 }, { dir = "west", map = "FR_FAR_END", offset = 0 } }, { ball })
  maps.FR_FAR_END = sea("FR_FAR_END", { "~~~~", "####", "~~~~" },
    { { dir = "east", map = "FR_FAR_SEA_B", offset = 0 } })
  Scripts.setSource({ far_ball = { { op = "setorcopyvar", 0x8000, 355 }, { op = "callstd", std = 1 } } })
  local labelled = Scripts.itemLabel
  Scripts.itemLabel = function() return "Rare Candy" end
  local taken = false
  package.loaded["src.core.game3.scripting.space"] = { objectVisible = function(object) return not (taken and object == ball) end }
  package.loaded["src.core.game3.connections"] = package.loaded["src.core.game3.connections"]
    or require("src.core.game3.connections")
  allowed.SURF = true
  local nav = navFor()
  local function standOn(mapId, x, y)
    local w = worldOn(maps[mapId], x, y, {}, true)
    nav.worldForCommand = function() return w end
    nav.worldState = function() return w end
    return w
  end
  local flow, cells = nav:currentFlow(maps.FR_FAR_SEA_A)
  eq(flow, "west", "a map's currents run one way")
  eq(cells, 10, "its cells of current are counted")
  eq(select(2, nav:currentFlow(maps.FR_FAR_TOWN)), 0, "calm water has none")
  local town = standOn("FR_FAR_TOWN", 1, 2)
  local far = nav:farMaps(town)
  check(far.downstream.FR_FAR_SEA_A and far.downstream.FR_FAR_SEA_B and not far.downstream.FR_FAR_END,
    "from upstream, the maps with currents entered the way they run are downstream")
  local function listed(world)
    local labels = {}
    for _, item in ipairs(nav:areaBrowse(world)) do labels[#labels + 1] = item.label end
    return table.concat(labels, "; ")
  end
  eq(listed(town), "Rare Candy, Far Sea B", "the ball down the current is in the Area list")
  local item = nav:areaBrowse(town)[1]
  nav.browseSelectionId = item.id
  nav.selectedBrowseItem = function() return item end
  local _, goals, hints = nav:selectedRouteGoals()
  check(goals.journeyAllowed == far.within, "its journey may cross the maps between")
  eq(hints["1,0"], "Face left and interact", "the arrival says which way the ball is")
  -- from the south lane's side of the town the journey still takes the north lane
  local result, why = nav:journeySearch({ mapId = "FR_FAR_TOWN", x = 1, y = 2 },
    { mapId = "FR_FAR_SEA_B", goals = goals }, 2, goals.journeyAllowed, nil, true)
  check(result ~= nil, "a journey down the currents is planned: " .. tostring(why))
  local first = result and result.firstTransition
  eq(first and (first.destMap .. " row " .. first.y), "FR_FAR_SEA_A row 0", "it leaves the town in the lane that reaches the ball")
  -- already in the wrong lane: no way, and nothing pretends otherwise
  standOn("FR_FAR_SEA_A", 0, 2)
  result, why = nav:journeySearch({ mapId = "FR_FAR_SEA_A", x = 0, y = 2 },
    { mapId = "FR_FAR_SEA_B", goals = goals }, 2, goals.journeyAllowed, nil, true)
  eq(why, "no regional path", "the south lane does not reach it")
  -- from the far end, against the current, nothing is listed
  local farEnd = standOn("FR_FAR_END", 1, 0)
  check(next(nav:farMaps(farEnd).downstream) == nil, "from the far end no map is downstream")
  eq(listed(farEnd), "", "and the Area list does not fill with what cannot be reached")
  -- the ball taken: gone from the list the next time it opens
  taken = true
  eq(listed(town), "", "a ball that was picked up is no longer listed")
  taken = false
  Scripts.itemLabel = labelled
  Scripts.setSource(nil)
  allowed.SURF = nil
  package.loaded["src.core.game3.scripting.space"] = nil
  maps.FR_FAR_TOWN, maps.FR_FAR_SEA_A, maps.FR_FAR_SEA_B, maps.FR_FAR_END = nil, nil, nil, nil
end

do
  -- A current that carries the player onto land leaves them surfing there (upstream): from
  -- that sand neither Surf nor a step into the water is possible (probed on Route 134), so
  -- no route is planned through such a carry.
  CELL["<"] = { 0x29, 0x51, 1 }
  maps.FR_SANDBAR = mapDef("FR_SANDBAR", { "..<<~", "~~###", "~~~~~" })
  allowed.SURF = true
  local nav = navFor()
  local result = route(nav, worldOn(maps.FR_SANDBAR, 4, 0, {}, true), { { x = 0, y = 0 } })
  eq(result and kinds(result) or "none", "none", "the sandbar a current ends on is not a way in")
  result = route(nav, worldOn(maps.FR_SANDBAR, 4, 2, {}, true), { { x = 0, y = 2 } })
  eq(kinds(result), "left left left left", "calm water beside it is crossed as ever")
  allowed.SURF = nil
end

do
  -- a dive spot's label follows its item balls (it was worked out once a session), and a
  -- far dive spot's arrival says the game's button
  local Navigation3 = require("src.access.nav.gen3.Navigation")
  CELL["d"] = { 0x29, 0x12, 1 }
  local diveModule = package.loaded["src.core.game3.dive"]
  package.loaded["src.core.game3.dive"] = {
    isDiveable = function(beh) return beh == 0x12 end, isUnableToEmerge = function() return false end }
  local shard = { x = 5, y = 1, graphicsId = 92, scriptKey = "pool_ball", index = 1, localId = 1 }
  maps.FR_DIVE_TOP = mapDef("FR_DIVE_TOP", { "#######", "~d~#d.#", "#######" }, {},
    { dive = "FR_DIVE_SEABED", objects = { shard } })
  maps.FR_DIVE_SEABED = mapDef("FR_DIVE_SEABED", { "#######", "......#", "#######" }, {},
    { mapType = 5, emerge = "FR_DIVE_TOP" })
  Scripts.setSource({ pool_ball = { { op = "setorcopyvar", 0x8000, 48 }, { op = "callstd", std = 1 } } })
  local labelled = Scripts.itemLabel
  Scripts.itemLabel = function() return "Red Shard" end
  local taken = false
  package.loaded["src.core.game3.scripting.space"] = { objectVisible = function(object) return not (taken and object == shard) end }
  local nav = navFor()
  local world = worldOn(maps.FR_DIVE_TOP, 0, 1, {}, true)
  local function labels()
    local list = {}
    for _, spot in ipairs(nav:diveSpots(world)) do list[#list + 1] = spot.label end
    table.sort(list)
    return table.concat(list, "; ")
  end
  eq(labels(), "Dive Spot to a pool with Red Shard; Dive Spot to the open water", "a dive spot names the ball in the pool it leads to")
  local before = nav:diveSpots(world)
  check(nav:diveSpots(world) == before, "asked again with nothing changed, the same list is handed back")
  taken = true
  eq(labels(), "Dive Spot to an enclosed pool; Dive Spot to the open water", "with the ball taken the label no longer names it")
  check(nav:diveSpots(world) ~= before, "the list was worked out again")
  taken = false
  -- the final leg of a guided journey to a far dive spot says the button
  local rim = { { x = 1, y = 1 } }
  rim.arrivalHint = "Press A and answer yes to dive"
  nav.worldForCommand = function() return world end
  nav.worldState = function() return world end
  local leg, reason = nav:regionalNextLeg({ targetMapId = "FR_DIVE_TOP", targetGoals = rim })
  check(leg and leg.final, "on the spot's own map the leg is final: " .. tostring(reason))
  local parts = {}
  if leg and leg.appendInstructions then leg.appendInstructions(parts) end
  eq(parts[1], "Press A and answer yes to dive", "and it ends with the button")
  -- auto-walk's arrival reads the same hint from the selection
  local farItem = { id = "area:dive", type = "area", category = "area", label = "Dive Spot, Far", mapId = "FR_DIVE_TOP",
    x = 1, y = 1, farDiveRim = rim }
  nav.browseSelectionId = farItem.id
  nav.selectedBrowseItem = function() return farItem end
  local _, goals, hints = nav:selectedRouteGoals()
  check(goals == rim, "a far dive spot's goals are its rim")
  eq(hints and hints["1,1"], "Press A and answer yes to dive", "whichever cell the walk ends on, the arrival says the button")
  Scripts.itemLabel = labelled
  Scripts.setSource(nil)
  package.loaded["src.core.game3.dive"] = diveModule
  package.loaded["src.core.game3.scripting.space"] = nil
  maps.FR_DIVE_TOP, maps.FR_DIVE_SEABED = nil, nil
end

do
  -- a part of the map reached only from another way in (Navigation:otherWayIn): one-way
  -- ledges between the player and the target
  package.loaded["src.core.game3.connections"] = package.loaded["src.core.game3.connections"]
    or require("src.core.game3.connections")
  local function shelf(connections)
    return mapDef("FR_OW_ROUTE", { ".......", ".......", "LLLLLLL", ".......", "......." }, {}, { connections = connections })
  end
  maps.FR_OW_NORTH = mapDef("FR_OW_NORTH", { ".......", "......." }, {},
    { connections = { { dir = "south", map = "FR_OW_ROUTE", offset = 0 } } })
  maps.FR_OW_WEST = mapDef("FR_OW_WEST", { "..", "..", "##", "..", ".." }, {},
    { connections = { { dir = "east", map = "FR_OW_ROUTE", offset = 0 } } })
  maps.FR_OW_ROUTE = shelf({ { dir = "north", map = "FR_OW_NORTH", offset = 0 } })
  local nav = navFor()
  local function standOn(x, y)
    local w = worldOn(maps.FR_OW_ROUTE, x, y)
    nav.worldForCommand = function() return w end
    nav.worldState = function() return w end
    return w
  end
  local below = standOn(3, 4)
  local goals = nav:connectionGoals(below, { direction = "north" })
  check(#goals > 0 and route(nav, below, goals, 2) == nil, "the shelf above the ledges cannot be reached from below")
  eq(nav:otherWayIn(below, goals), "Not from here: this part is reached from Ow North",
    "with no other way in, the target's own far side is where to come from")
  eq(nav:closedReason(goals), "Not from here: this part is reached from Ow North", "it is one of the last reasons")
  -- another edge reaches the shelf: that is the way round, and the one named
  maps.FR_OW_ROUTE = shelf({ { dir = "north", map = "FR_OW_NORTH", offset = 0 }, { dir = "west", map = "FR_OW_WEST", offset = 0 } })
  below = standOn(3, 4)
  eq(nav:otherWayIn(below, goals), "Not from here: this part is reached from Ow West", "another way in is named before the target's own")
  -- from the shelf itself there is a way: no such reason
  local above = standOn(3, 0)
  eq(nav:otherWayIn(above, goals), nil, "where a way exists this says nothing")
  -- a cell nothing reaches at all
  maps.FR_OW_ROUTE = mapDef("FR_OW_ROUTE", { "...#.", "...##", "....." }, {}, {})
  below = standOn(0, 0)
  eq(nav:otherWayIn(below, { { x = 4, y = 0 } }), nil, "a walled-in cell has no way in to name")
  maps.FR_OW_ROUTE, maps.FR_OW_NORTH, maps.FR_OW_WEST = nil, nil, nil
end

do
  -- a way round through the map next door (Navigation:wayRoundNextDoor): two strips of a
  -- route that join only along the next town's edge
  package.loaded["src.core.game3.connections"] = package.loaded["src.core.game3.connections"]
    or require("src.core.game3.connections")
  maps.FR_NR_ROUTE = mapDef("FR_NR_ROUTE", { "..#..", "..#..", "..#.." }, {},
    { connections = { { dir = "north", map = "FR_NR_TOWN", offset = 0 } } })
  maps.FR_NR_TOWN = mapDef("FR_NR_TOWN", { ".....", "....." }, {},
    { connections = { { dir = "south", map = "FR_NR_ROUTE", offset = 0 } } })
  local nav = navFor()
  local w = worldOn(maps.FR_NR_ROUTE, 4, 2)
  nav.worldForCommand = function() return w end
  nav.worldState = function() return w end
  local goals = { { x = 0, y = 2 } }
  check(route(nav, w, goals, 2) == nil, "the two strips do not join on the route itself")
  local leg, reason = nav:regionalNextLeg({ targetMapId = "FR_NR_ROUTE", targetGoals = goals })
  check(leg and not leg.final and leg.nextMapId == "FR_NR_TOWN", "the way round goes over the edge into the next town: " .. tostring(reason))
  eq(leg and leg.goals[1].y, 0, "the leg ends on this strip's top edge")
  eq(leg and leg.edgeDirection, "up", "and says which way to step off")
  -- with the town's row walled between the strips there is no way round
  maps.FR_NR_TOWN = mapDef("FR_NR_TOWN", { "..#..", "..#.." }, {},
    { connections = { { dir = "south", map = "FR_NR_ROUTE", offset = 0 } } })
  leg, reason = nav:regionalNextLeg({ targetMapId = "FR_NR_ROUTE", targetGoals = goals })
  check(leg == nil, "no way round where the next map does not join them")
  maps.FR_NR_ROUTE, maps.FR_NR_TOWN = nil, nil
end

do
  -- a door its key opens (Scripts.keyDoor; the Abandoned Ship's rooms): its sign is a
  -- locked door, and a journey it closes names the key
  local World = require("src.access.nav.gen3.World")
  Scripts.setSource({
    room_door = { { op = "lockall" }, { op = "checkflag", flag = 241 }, { op = "goto_if", target = "door_open" },
      { op = "checkitem", 282, 1 }, { op = "goto_if", target = "door_locked" }, { op = "removeitem", 282, 1 },
      { op = "setflag", flag = 241 }, { op = "call", target = "door_draw" }, { op = "special", id = 142 }, { op = "end" } },
    door_open = { { op = "callstd", std = 4 } },
    door_locked = { { op = "callstd", std = 4 } },
    door_draw = { { op = "setmetatile", 6, 8, 555, 1 }, { op = "return" } },
    poster = { { op = "checkflag", flag = 300 }, { op = "setflag", flag = 300 }, { op = "setmetatile", 1, 1, 5, 0 } },
  })
  local door = Scripts.keyDoor("room_door")
  eq(door and door.flag, 241, "the door's own flag is the first its script checks")
  eq(door and door.item, 282, "the key is the item it checks for and takes")
  eq(Scripts.signRole("room_door"), "Locked Door", "such a sign is a locked door, not a hidden switch")
  eq(Scripts.keyDoor("poster"), nil, "a switch that takes no item is no key door")
  eq(Scripts.signRole("poster"), "Hidden Switch", "and keeps its name")
  maps.FR_KD_HALL = mapDef("FR_KD_HALL", { "###", "#.#", "###" }, {},
    { bgEvents = { { type = "sign", x = 1, y = 0, kind = 0, scriptKey = "room_door" } } })
  local flagsOn = {}
  package.loaded["src.core.game3.scripting.space"] = { store = {} }
  package.loaded["src.core.game3.scripting.flags"] = { getFlag = function(_, _, id) return flagsOn[id] == true end }
  local labelled = Scripts.itemLabel
  Scripts.itemLabel = function(id) return id == 282 and "Rm. 2 Key" or nil end
  local nav = navFor()
  -- the journey exists only with the door's flag supposed set
  local supposing
  nav.journeySearch = function(self)
    supposing = self.journeySupposing
    return World.supposedFlags and World.supposedFlags[241] and { cost = 1 } or nil
  end
  local start, target = { mapId = "FR_KD_HALL", x = 1, y = 1 }, { mapId = "FR_KD_HALL", goals = { { x = 1, y = 1 } } }
  nav.session = function() return { bag = { pockets = {} } } end
  eq(nav:lockedDoor(start, target, nil), "A door on the way is locked: needs the Rm. 2 Key", "without the key the refusal names it")
  check(supposing == true and World.supposedFlags == nil and nav.journeySupposing == nil, "the supposition is put back after the search")
  nav.session = function() return { bag = { pockets = { keys = { { id = 282, qty = 1 } } } } } end
  eq(nav:lockedDoor(start, target, nil), "A door on the way is locked: face it and press A, the Rm. 2 Key opens it",
    "with the key in the bag it says how the door opens")
  flagsOn[241] = true
  eq(nav:lockedDoor(start, target, nil), nil, "a door already opened is not blamed")
  Scripts.itemLabel = labelled
  Scripts.setSource(nil)
  package.loaded["src.core.game3.scripting.space"] = nil
  package.loaded["src.core.game3.scripting.flags"] = nil
  maps.FR_KD_HALL = nil
end

do
  -- Ruby, Sapphire, FireRed and LeafGreen name things Emerald's sheets name differently
  local Snapshot = require("src.access.nav.gen3.WorldSnapshot")
  local Scripts = require("src.access.nav.gen3.Scripts")
  local trainersModule = package.loaded["src.core.game3.scripting.trainers"]
  package.loaded["src.core.game3.scripting.trainers"] = { info = function(id)
    return ({ [7] = { className = "TWINS" }, [8] = { className = "POK\195\169MON TRAINER" },
      [9] = { className = "YOUNG COUPLE" } })[id]
  end }
  Scripts.setSource({
    twin = { { op = "trainerbattle", trainer = 7 } },
    titled = { { op = "trainerbattle", trainer = 8 } },
    couple = { { op = "trainerbattle", trainer = 9 } },
  })
  Snapshot.setGraphicsNames({ [95] = "OBJ_EVENT_GFX_MACHOKE_CARRYING_BOX", [96] = "OBJ_EVENT_GFX_MACHOKE_FACING_AWAY",
    [20] = "OBJ_EVENT_GFX_LITTLE_GIRL_1", [23] = "OBJ_EVENT_GFX_MAN_5" })
  eq(Snapshot.objectLabel({ graphicsId = 95, def = {} }, {}), "Machoke", "Ruby and Sapphire's mover, as Emerald's Vigoroth")
  eq(Snapshot.objectLabel({ graphicsId = 96, def = {} }, {}), "Machoke", "the mover facing away")
  eq(Snapshot.objectLabel({ graphicsId = 20, def = { scriptKey = "twin" } }, {}), "Twin", "one of the twins, as Emerald's sheet says it")
  eq(Snapshot.objectLabel({ graphicsId = 23, def = { scriptKey = "titled" } }, {}), "Man",
    "the title as the class table spells it is no better than the sheet")
  eq(Snapshot.objectLabel({ graphicsId = 23, def = { scriptKey = "couple" } }, {}), "Young Couple", "a couple's class stays")
  Scripts.setSource(nil)
  Snapshot.setGraphicsNames(nil)
  package.loaded["src.core.game3.scripting.trainers"] = trainersModule
end

do
  -- a buried trainer met through the journey planner is named as one met on this floor is
  -- (Ruby and Sapphire's Lavaridge Gym reaches four of its 1F holes through B1F)
  local Navigation3 = require("src.access.nav.gen3.Navigation")
  local nav = setmetatable({}, { __index = Navigation3 })
  local function journey(trainerType)
    local buried = { cellX = 3, cellY = 4, invisible = true, graphicsId = 66, def = { trainerType = trainerType } }
    return { legs = { { mapId = "RU_LAVARIDGE_TOWN_GYM_B1F", steps = { { x = 3, y = 3 }, { x = 3, y = 4 } } } },
      maps = { RU_LAVARIDGE_TOWN_GYM_B1F = { world = { npcs = { buried } } } } }
  end
  eq((nav:journeyBlocker(journey(3), "RU_LAVARIDGE_TOWN_GYM_B1F")), "a hidden trainer", "a buried trainer on the way")
  eq((nav:journeyBlocker(journey(0), "RU_LAVARIDGE_TOWN_GYM_B1F")), "something hidden", "anything else unseen keeps its words")
end

do
  -- One Island's maps carry SEVII_ where the rest of FireRed and LeafGreen carry FR_
  local GameData = require("src.access.nav.gen3.GameData")
  local Snapshot = require("src.access.nav.gen3.WorldSnapshot")
  local Navigation3 = require("src.access.nav.gen3.Navigation")
  eq(GameData.bareMapId("SEVII_ONE_ISLAND_KINDLE_ROAD"), "ONE_ISLAND_KINDLE_ROAD", "SEVII_ comes off as FR_ does")
  eq(GameData.bareMapId("FR_ONE_ISLAND_KINDLE_ROAD_EMBER_SPA"), "ONE_ISLAND_KINDLE_ROAD_EMBER_SPA", "FR_ as before")
  eq(Navigation3.areaKey("SEVII_ONE_ISLAND_KINDLE_ROAD"), Navigation3.areaKey("FR_ONE_ISLAND_KINDLE_ROAD_EMBER_SPA"),
    "Kindle Road and its Ember Spa are one area")
  eq(Navigation3.areaKey("SEVII_ONE_ISLAND_POKECENTER"), Navigation3.areaKey("SEVII_ONE_ISLAND_POKECENTER_2F"),
    "the Center's two floors are one area")
  check(Navigation3.areaKey("SEVII_ONE_ISLAND_POKECENTER") ~= Navigation3.areaKey("SEVII_ONE_ISLAND_KINDLE_ROAD"),
    "and not the whole island's")
  eq(Snapshot.mapIdName("SEVII_ONE_ISLAND_POKECENTER"), "One Island Pok\195\169mon Center 1F", "named as every other Center")
  eq(Snapshot.mapIdName("SEVII_ONE_ISLAND_POKECENTER_2F"), "One Island Pok\195\169mon Center 2F", "and its upper floor")
  local profile = GameData.profile
  GameData.profile = function() return { map = { enginePrefix = "FR_", prefixes = { "FR_", "SEVII_" } } } end
  check(GameData.ownsMap("SEVII_ONE_ISLAND"), "a SEVII_ map is the cartridge's own")
  check(GameData.ownsMap("FR_PALLET_TOWN"), "an FR_ map is")
  check(not GameData.ownsMap("EM_ROUTE101"), "another game's map is not")
  GameData.profile = profile

  -- Ruby and Sapphire's sheets read by the names Emerald gives the same pictures
  local id = GameData.id
  Snapshot.setGraphicsNames({ [116] = "OBJ_EVENT_GFX_MAN_7", [28] = "OBJ_EVENT_GFX_WOMAN_6", [21] = "OBJ_EVENT_GFX_OLD_MAN_1",
    [18] = "OBJ_EVENT_GFX_WOMAN_2", [6] = "OBJ_EVENT_GFX_LITTLE_GIRL_1", [20] = "OBJ_EVENT_GFX_WOMAN_3" })
  GameData.id = function() return "ruby" end
  eq(Snapshot.objectLabel({ graphicsId = 116, def = {} }, {}), "Devon Employee", "Ruby's MAN_7 is Emerald's Devon Employee")
  eq(Snapshot.objectLabel({ graphicsId = 28, def = {} }, {}), "Receptionist", "WOMAN_6 the link receptionist")
  eq(Snapshot.objectLabel({ graphicsId = 21, def = {} }, {}), "Expert", "OLD_MAN_1 the Expert")
  eq(Snapshot.objectLabel({ graphicsId = 18, def = {} }, {}), "Pok\195\169 Fan", "WOMAN_2 the fan")
  eq(Snapshot.objectLabel({ graphicsId = 6, def = {} }, {}), "Twin", "LITTLE_GIRL_1 a twin")
  eq(Snapshot.objectLabel({ graphicsId = 20, def = {} }, {}), "Woman", "a sheet with no other name keeps its own")
  GameData.id = function() return "firered" end
  eq(Snapshot.objectLabel({ graphicsId = 18, def = {} }, {}), "Woman", "FireRed's WOMAN_2 is its own sheet")
  GameData.id = id
  Snapshot.setGraphicsNames(nil)
end

do
  -- FireRed and LeafGreen's sheet MAN (no number) has an entry of its own in the label table
  -- ("Man"), which answered before the trainer class was asked: Fuchsia Gym's Tamers and
  -- the man of each Young Couple stayed "Man"
  local Snapshot = require("src.access.nav.gen3.WorldSnapshot")
  local Scripts = require("src.access.nav.gen3.Scripts")
  local trainersModule = package.loaded["src.core.game3.scripting.trainers"]
  package.loaded["src.core.game3.scripting.trainers"] = { info = function(id)
    return ({ [7] = { className = "TAMER" } })[id]
  end }
  Scripts.setSource({ tamer = { { op = "trainerbattle", trainer = 7 } }, talker = { { op = "msgbox" } } })
  Snapshot.setGraphicsNames({ [30] = "OBJ_EVENT_GFX_MAN", [31] = "OBJ_EVENT_GFX_HOT_SPRINGS_OLD_WOMAN" })
  eq(Snapshot.objectLabel({ graphicsId = 30, def = { scriptKey = "tamer" } }, {}), "Tamer", "the sheet MAN takes the class")
  eq(Snapshot.objectLabel({ graphicsId = 30, def = { scriptKey = "talker" } }, {}), "Man", "and is Man with no battle")
  eq(Snapshot.objectLabel({ graphicsId = 31, def = { scriptKey = "talker" } }, {}), "Old Woman", "a sheet's own plain label stays")
  Scripts.setSource(nil)
  Snapshot.setGraphicsNames(nil)
  package.loaded["src.core.game3.scripting.trainers"] = trainersModule
end

do
  -- Sootopolis's size records: the second sentence is only what the game fills in
  local Scripts = require("src.access.nav.gen3.Scripts")
  eq(Scripts.signLine("The biggest SHROOMISH in history!\n{STR_VAR_2}'s {STR_VAR_3}-inch giant!"),
    "The biggest SHROOMISH in history!", "a sentence of placeholders is left out")
end

do
  -- routeNeeds names whoever stands on the goal before the first person on the way there
  -- (Emerald's Lavaridge Gym: the guide by the door was named for a buried trainer's hole)
  maps.FR_TEST_HOLES = mapDef("FR_TEST_HOLES", { ".....", "....." })
  local guide = { cellX = 1, cellY = 0, graphicsId = 23, currentElevation = 3, localId = 1,
    def = { graphicsId = 23, index = 1, trainerType = 0 } }
  local buried = { cellX = 4, cellY = 0, graphicsId = 66, currentElevation = 3, localId = 2, invisible = true,
    def = { graphicsId = 66, index = 2, trainerType = 3 } }
  local nav = navFor()
  local w = worldOn(maps.FR_TEST_HOLES, 0, 0, { guide, buried })
  nav.worldForCommand = function() return w end
  eq(nav:routeNeeds({ { x = 4, y = 0 } }), "Blocked by a hidden trainer", "the one in the hole, not the guide on the way")
  maps.FR_TEST_HOLES = nil
end

T.finish("gen3 navigation")
