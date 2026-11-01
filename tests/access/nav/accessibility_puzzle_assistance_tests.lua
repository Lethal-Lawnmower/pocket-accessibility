local T = require("tests.harness")
local S = T.suite("accessibility puzzle assistance")
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
Data:load()
local Collision = require("src.world.Collision")
local Map = require("src.world.Map")
local Puzzle = require("src.access.nav.PuzzleAssistance")
local WorldSnapshot = require("src.access.nav.WorldSnapshot")
local Accessibility = require("src.access.nav.Navigation")
Collision.load(Data)

local mapId = "VICTORY_ROAD_1F"
local map = Map.new(Data.maps[mapId], Data.tilesets.CAVERN)
local player = { cellX = 8, cellY = 16, facing = "up" }
local entities = { player }
for _, def in ipairs(Data.maps[mapId].objects) do
  entities[#entities + 1] = {
    id = mapId .. "_obj_" .. tostring(def.index),
    cellX = def.x, cellY = def.y, def = def,
  }
end
local world = { map = map, player = player, entities = entities,
                npcs = entities, strengthActive = false }
local game = { save = {
  options = { puzzleAssistance = true }, flags = {},
  inventory = { RAINBOWBADGE = 1 },
  party = { { moves = { "STRENGTH" } } },
} }

local beforePositions = {}
for _, entity in ipairs(entities) do
  beforePositions[#beforePositions + 1] = { entity.cellX, entity.cellY }
end
local result = Puzzle.describe(game, world)
S.eq(#result.objects, 1,
  "Victory Road 1F exposes its pressure switch while assistance is on")
S.eq(result.objects[1].label, "Pressure Switch 1",
  "pressure switch has a stable puzzle label")
S.check(result.objects[1].stateText:find(
  "Boulder 1 can reach it; next push down", 1, true) ~= nil,
  "live planner identifies the useful boulder and first push")
S.eq(result.nextAction.boulderId, "VICTORY_ROAD_1F_obj_5",
  "planner exposes the exact boulder required for blocked navigation")
S.eq(result.nextAction.boulderLabel, "Boulder 1",
  "navigation action uses the stable spoken boulder number")
S.same({ result.nextAction.standX, result.nextAction.standY }, { 5, 14 },
  "navigation action exposes the exact safe pushing position")
S.eq(result.nextAction.direction, "down",
  "navigation action exposes the required push direction")
S.eq(result.nextAction.instruction,
  "Use Strength from the party menu; push down toward Pressure Switch 1",
  "navigation action includes Strength state and the push target")
local boulder = result.objectOverrides.VICTORY_ROAD_1F_obj_5
S.eq(boulder.requiredFacing, "down",
  "boulder route approaches from the side required for the planned push")
S.eq(boulder.routeInstruction,
  "Use Strength from the party menu; push down toward Pressure Switch 1",
  "inactive Strength produces an exact advisory instruction")
S.same(game.save.flags, {}, "planning never mutates native puzzle flags")
for i, entity in ipairs(entities) do
  S.same({ entity.cellX, entity.cellY }, beforePositions[i],
    "planning never moves live entity " .. tostring(i))
end

local snapshot = assert(WorldSnapshot.capture(world, {
  maps = Data.maps, filter = "objects", interactiveObjects = result.objects,
  objectOverrides = result.objectOverrides,
}))
local switchItem, boulderItem
for _, item in ipairs(snapshot.browse) do
  if item.id == "victory_road_switch:VICTORY_ROAD_1F:1" then switchItem = item end
  if item.id == "VICTORY_ROAD_1F_obj_5" then boulderItem = item end
end
S.check(switchItem and switchItem.description:find(
  "Boulder 1 can reach it", 1, true) ~= nil,
  "switch planning state reaches normal browse speech")
S.check(boulderItem and boulderItem.description:find(
  "target Pressure Switch 1; next push down", 1, true) ~= nil,
  "boulder plan reaches normal browse speech")
local access = setmetatable({ game = game }, Accessibility)
local goals, instructions = access:interactionGoals(world, boulderItem)
S.eq(#goals, 1, "planned boulder exposes only its correct pushing side")
S.same(goals[1], { x = 5, y = 14 },
  "planned first push routes above the live boulder")
S.eq(instructions["5,14"],
  "Use Strength from the party menu; push down toward Pressure Switch 1",
  "boulder arrival speaks the advisory push without sending input")

local originalGoals = { { x = 15, y = 2 } }
local originalInstructions = function(parts)
  parts[#parts + 1] = "original destination"
end
local navigation = {
  goals = originalGoals,
  appendInstructions = originalInstructions,
  announcedRequirements = {},
}
S.check(access:updatePuzzleDetour(navigation, world, true),
  "an unreachable destination can begin a puzzle detour")
S.same(navigation.goals, { { x = 5, y = 14 } },
  "puzzle detour routes to the exact side of the required boulder")
S.eq(navigation.pendingPuzzleIntro,
  "Boulder 1 to Pressure Switch 1. Walk to the pushing position.",
  "puzzle detour explains which boulder unlocks which switch")
local detourParts = {}
navigation.appendInstructions(detourParts)
S.eq(detourParts[1],
  "Use Strength from the party menu; push down toward Pressure Switch 1",
  "arrival at the pushing position announces where to move the boulder")

local liveBoulder
for _, entity in ipairs(entities) do
  if entity.id == "VICTORY_ROAD_1F_obj_5" then liveBoulder = entity break end
end
local firstActionSignature = navigation.puzzle.actionSignature
navigation.pendingPuzzleIntro = nil
player.cellX, player.cellY = liveBoulder.cellX, liveBoulder.cellY
liveBoulder.cellY = liveBoulder.cellY + 1
S.check(access:updatePuzzleDetour(navigation, world, false),
  "moving the boulder recalculates the next push without another key press")
S.check(navigation.puzzle.actionSignature ~= firstActionSignature,
  "the live boulder position changes the planned standing cell or direction")
S.check(navigation.pendingPuzzleIntro == nil,
  "subsequent pushes do not repeat the full puzzle introduction")

-- Simulate completing the switch without asking the accessibility layer to
-- move anything. The original destination must be restored automatically.
game.save.flags.EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH = true
S.check(not access:updatePuzzleDetour(navigation, world, false),
  "solving the blocking switch ends the temporary puzzle detour")
S.check(navigation.puzzle == nil,
  "completed detour discards its temporary navigation state")
S.check(navigation.goals == originalGoals,
  "completed detour resumes the exact original destination goals")
S.check(navigation.appendInstructions == originalInstructions,
  "completed detour resumes the original arrival instructions")
game.save.flags.EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH = nil
player.cellX, player.cellY = 8, 16
liveBoulder.cellX, liveBoulder.cellY = 5, 15

local toggleGoals = { { x = 11, y = 3 } }
local toggleNavigation = { goals = toggleGoals, announcedRequirements = {} }
S.check(access:updatePuzzleDetour(toggleNavigation, world, true),
  "enabled assistance can create a live puzzle detour")
game.save.options.puzzleAssistance = false
S.check(not access:updatePuzzleDetour(toggleNavigation, world, false),
  "turning assistance off cancels an existing puzzle detour")
S.check(toggleNavigation.puzzle == nil and toggleNavigation.goals == toggleGoals,
  "turning assistance off restores the player's original destination")
game.save.options.puzzleAssistance = true

world.strengthActive = true
result = Puzzle.describe(game, world)
S.eq(result.objectOverrides.VICTORY_ROAD_1F_obj_5.routeInstruction,
  "push down toward Pressure Switch 1",
  "active Strength removes the redundant party-menu instruction")

-- Victory Road 3F is a two-stage dependency. Boulder 1 opens the lower
-- section; only then can Boulder 4 be pushed into the hole to 2F.
local vr3Id = "VICTORY_ROAD_3F"
local vr3Map = Map.new(Data.maps[vr3Id], Data.tilesets.CAVERN)
local vr3Player = { cellX = 23, cellY = 7, facing = "up" }
local vr3Entities = { vr3Player }
local vr3Boulders = {}
for _, def in ipairs(Data.maps[vr3Id].objects) do
  local entity = {
    id = vr3Id .. "_obj_" .. tostring(def.index),
    cellX = def.x, cellY = def.y, def = def,
  }
  vr3Entities[#vr3Entities + 1] = entity
  local number = def.name and tonumber(def.name:match("BOULDER(%d+)$"))
  if number then vr3Boulders[number] = entity end
end
local vr3World = {
  map = vr3Map, player = vr3Player, entities = vr3Entities,
  npcs = vr3Entities, strengthActive = false,
}
local vr3Game = { save = {
  options = { puzzleAssistance = true }, flags = {},
  inventory = { RAINBOWBADGE = 1 },
  party = { { moves = { "STRENGTH" } } },
} }
local vr3Result = Puzzle.describe(vr3Game, vr3World)
S.eq(vr3Result.nextAction.boulderId, "VICTORY_ROAD_3F_obj_7",
  "3F begins with Boulder 1 rather than the unreachable Boulder 2")
S.eq(vr3Result.nextAction.targetLabel, "Pressure Switch 1",
  "3F first-stage guidance names the gate-opening pressure switch")
S.same({ vr3Result.nextAction.standX, vr3Result.nextAction.standY },
  { 22, 4 }, "3F routes below Boulder 1 for its first upward push")
S.eq(vr3Result.nextAction.direction, "up",
  "3F announces Boulder 1's first push direction")

vr3Boulders[1].cellX, vr3Boulders[1].cellY = 3, 5
vr3Player.cellX, vr3Player.cellY = 3, 4
vr3Game.save.flags.EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH1 = true
vr3Map:setBlock(3, 5, 0x1D)
vr3World.strengthActive = true
vr3Result = Puzzle.describe(vr3Game, vr3World)
S.eq(vr3Result.nextAction.boulderId, "VICTORY_ROAD_3F_obj_10",
  "after the switch opens, 3F advances to Boulder 4")
S.eq(vr3Result.nextAction.targetLabel, "Boulder Drop Hole",
  "the second 3F stage identifies the 2F boulder drop")
S.same({ vr3Result.nextAction.standX, vr3Result.nextAction.standY },
  { 21, 15 }, "Boulder 4 guidance routes to its left pushing side")
S.eq(vr3Result.nextAction.direction, "right",
  "Boulder 4 is pushed right into the 2F hole")

game.save.options.puzzleAssistance = false
result = Puzzle.describe(game, world)
S.eq(#result.objects, 0,
  "disabling assistance removes enhanced pressure-switch objects")
S.check(next(result.objectOverrides) == nil,
  "disabling assistance restores unmodified boulder labels and routing")

game.save.options = {} -- old options files inherit the default-on behavior
S.check(Puzzle.enabled(game), "missing option defaults puzzle assistance on")

S.finish()
