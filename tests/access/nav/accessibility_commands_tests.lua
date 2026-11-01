local T = require("tests.harness")
local S = T.suite("accessibility native command handlers")
local Accessibility = require("src.access.nav.Navigation")
local Events = require("src.mods.Events")

local semanticEvents = {}
local events = Events.new()
events:on("accessibility.event", function(event)
  semanticEvents[#semanticEvents + 1] = event
end, 0, "test")

local function lastSemantic(kind)
  for i = #semanticEvents, 1, -1 do
    if semanticEvents[i].kind == kind then return semanticEvents[i] end
  end
end

local speechCalls = {}
local speech = {}
function speech:isAvailable() return true end
function speech:stop()
  speechCalls[#speechCalls + 1] = { kind = "stop" }
  return true
end
function speech:output(text, opts)
  speechCalls[#speechCalls + 1] = {
    kind = "output", text = text, interrupt = opts and opts.interrupt == true,
  }
  return true
end

local cues = {}
local earcons = {}
function earcons:setEnabled() end
function earcons:stop() return true end
function earcons:play(id, opts)
  cues[#cues + 1] = { id = id, pan = opts and opts.pan }
  return true
end

local function lastOutput()
  for i = #speechCalls, 1, -1 do
    if speechCalls[i].kind == "output" then return speechCalls[i] end
  end
end

local blocked = { ["1,2"] = true }
local grass = { ["2,2"] = true }
local water = { ["4,2"] = true }
local map = {
  id = "MOD_ROUTE",
  widthCells = 6,
  heightCells = 6,
  def = {
    id = "MOD_ROUTE", displayName = "Mod Route", width = 3, height = 3,
    tileset = "OVERWORLD", blocks = {}, borderBlock = 0,
    warps = { { x = 5, y = 5, destMap = "MOD_HOUSE", destWarp = 1 } },
    connections = { north = { map = "ROUTE_1", offset = 0 } },
    signs = { { x = 2, y = 1, text = "TEXT_MOD_ROUTE_SIGN" } },
    accessibilityTerrain = { cells = {
      ["2,3"] = {
        kind = "directional_floor", direction = "down",
        label = "Mod conveyor toward down",
      },
    } },
  },
}
function map:inBounds(x, y) return x >= 0 and y >= 0 and x < 6 and y < 6 end
function map:cellTile(x, y) return y * 10 + x end
function map:warpAtCell(x, y)
  for index, warp in ipairs(self.def.warps or {}) do
    if warp.x == x and warp.y == y then
      return { index = index, def = warp }
    end
  end
end
function map:signAtCell(x, y)
  if x == 2 and y == 1 then return self.def.signs[1] end
end
function map:isWarpTileCell(x, y) return self:warpAtCell(x, y) ~= nil end
function map:isCounterCell() return false end
function map:isGrassCell(x, y) return grass[x .. "," .. y] == true end
function map:isWaterCell(x, y) return water[x .. "," .. y] == true end
function map:isWalkableCell(x, y)
  return self:inBounds(x, y) and not blocked[x .. "," .. y]
end

local player = { name = "RED", cellX = 2, cellY = 2, facing = "up" }
local boulder = {
  id = "MOD_ROUTE_obj_1", cellX = 3, cellY = 2, facing = "down",
  def = { index = 1, name = "MOD_ROUTE_BOULDER", sprite = "SPRITE_BOULDER" },
}
local overworld = {
  isOverworld = true, map = map, player = player,
  npcs = { boulder }, entities = { player, boulder },
}
local stack = { states = { overworld }, current = overworld }
function stack:top() return self.current end
function stack:push(state)
  self.states[#self.states + 1] = state
  self.current = state
  if state.enter then state:enter() end
end
function stack:pop()
  local state = table.remove(self.states)
  self.current = self.states[#self.states]
  return state
end

local game = {
  stack = stack,
  overworld = overworld,
  data = { maps = {
    MOD_ROUTE = map.def,
    MOD_HOUSE = { id = "MOD_HOUSE", displayName = "Mod House" },
    ROUTE_1 = { id = "ROUTE_1", displayName = "Route 1" },
  } },
  save = { options = {
    accessibilityNames = {
      maps = { MOD_ROUTE = "My Route" },
      objects = { MOD_ROUTE = { ["MOD_ROUTE_obj_1"] = "Round Rock" } },
    },
  } },
  writes = 0,
}
function game:writeOptions() self.writes = self.writes + 1 end

local access = Accessibility.new(game, {
  speech = speech, earcons = earcons, events = events,
  enabled = true, defaultDelayFrames = 0,
})
S.eq(lastOutput().text,
  "Screen reader ready. Press F6 to repeat. Press F7 for accessibility command mode. Press F8 for help.",
  "coordinator is ready and exposes bootstrap controls")

local callsBeforeHelp = #speechCalls
access:handleCommand("read_command_help")
S.eq(speechCalls[callsBeforeHelp + 1].kind, "stop",
  "F8 help stops old speech once")
S.eq(#speechCalls, callsBeforeHelp + 7,
  "F8 help queues six deterministic sections after one stop")
S.check(lastOutput().text:find("Shift M renames the map", 1, true) ~= nil,
  "F8 help reaches the final rename command without one giant utterance")

access:handleCommand("describe_route_to_selected_item")
S.eq(lastOutput().text, "Select an object from the list",
  "P requires an explicit browse selection after map entry")

access:handleCommand("read_player_position")
S.eq(lastOutput().text, "x 2, y 2", "Y reads native player coordinates")
S.check(lastOutput().interrupt == false, "manual coordinate output queues")
access:handleCommand("read_map_name")
S.eq(lastOutput().text, "My Route", "M honors the persisted custom map label")

access:handleCommand("current_map_item")
S.eq(lastOutput().text, "Mod House: 3 down 3 right",
  "K reads the first item in Pokemon Access browse order")
S.eq(lastSemantic("browse.selected").label, "Mod House",
  "browse selection emits the same semantic label presented to speech")
S.eq(lastSemantic("browse.selected").id, "warp:MOD_ROUTE:1",
  "browse selection event retains the stable accessibility target id")
local callsBeforeRoute = #speechCalls
access:handleCommand("describe_route_to_selected_item")
S.eq(speechCalls[callsBeforeRoute + 1].kind, "stop",
  "route narration stops old speech once")
S.eq(speechCalls[callsBeforeRoute + 2].text, "1 down",
  "P starts continuous navigation with only the next direction")
S.check(access.activeNavigation ~= nil,
  "selected-item navigation remains active after its first instruction")
S.eq(lastSemantic("navigation.started").targetLabel, "Mod House",
  "continuous navigation emits its selected semantic target")
S.same({ lastSemantic("navigation.directive").action,
         lastSemantic("navigation.directive").direction,
         lastSemantic("navigation.directive").distance },
       { "move", "down", 1 },
  "navigation event mirrors the first spoken movement without hidden cells")
local routeBattle = {
  isBattle = true, accessibilityRole = "battle",
  accessibilitySnapshot = function()
    return { key = "battle:test", text = "Battle in progress", immediate = true }
  end,
}
stack.states, stack.current = { overworld, routeBattle }, routeBattle
access:update()
local beforeBattleReturn = #speechCalls
stack.states, stack.current = { overworld }, overworld
access:update()
S.eq(speechCalls[beforeBattleReturn + 2].text, "1 down",
  "returning from battle repeats the current navigation instruction once")
S.check(access.activeNavigation ~= nil,
  "battle return preserves the selected navigation target")
local beforeFirstTurn = #speechCalls
player.cellY = 1
access.pendingStepEvent = { mapId = map.id, x = player.cellX, y = player.cellY }
access:processWorldEvents(overworld)
S.eq(speechCalls[beforeFirstTurn + 2].text, "3 right",
  "a settled off-route step automatically announces a corrected direction")
local beforeStraightStep = #speechCalls
player.cellX = 3
access.pendingStepEvent = { mapId = map.id, x = player.cellX, y = player.cellY }
access:processWorldEvents(overworld)
S.eq(#speechCalls, beforeStraightStep,
  "walking along the current segment does not repeat shrinking directions")
player.cellX = 5
access.pendingStepEvent = { mapId = map.id, x = player.cellX, y = player.cellY }
access:processWorldEvents(overworld)
S.eq(lastOutput().text, "4 down",
  "settled movement automatically announces the following turn")
access:handleCommand("describe_route_to_selected_item")
S.eq(lastOutput().text, "Navigation stopped",
  "pressing P again stops continuous navigation")
player.cellX, player.cellY = 2, 2
access.sonarMapId, access.sonarX, access.sonarY = nil, nil, nil
access:handleCommand("previous_map_item")
S.eq(lastOutput().text, "Round Rock: 1 right; facing down",
  "J wraps backward and applies a stable custom object label")
local callsBeforeObjectRoute = #speechCalls
access:handleCommand("describe_route_to_selected_item")
S.eq(speechCalls[callsBeforeObjectRoute + 2].text,
       "Face right and interact",
  "object routes stop on a reachable adjacent cell and finish with interaction")
access:handleCommand("next_map_item")
S.eq(lastOutput().text, "Mod House: 3 down 3 right",
  "L wraps forward to the first item")

-- Keyboard letters, bumpers, and triggers all enter through handleCommand.
-- Rapid browse edges must cancel the prior utterance instead of building a
-- slow speech queue that continues after the player has moved on.
local callsBeforeRapidBrowse = #speechCalls
access:handleCommand("next_map_item")
access:handleCommand("previous_map_item")
S.same({ speechCalls[callsBeforeRapidBrowse + 1].kind,
         speechCalls[callsBeforeRapidBrowse + 2].interrupt,
         speechCalls[callsBeforeRapidBrowse + 3].kind,
         speechCalls[callsBeforeRapidBrowse + 4].interrupt },
       { "stop", false, "stop", false },
  "rapid keyboard or controller browsing interrupts each stale utterance")
S.eq(lastOutput().text, "Mod House: 3 down 3 right",
  "rapid cycling finishes on only the current entity")

local originalCounter = map.isCounterCell
local originalBoulderX, originalBoulderY = boulder.cellX, boulder.cellY
map.isCounterCell = function(_, x, y) return x == 2 and y == 1 end
boulder.cellX, boulder.cellY = 2, 0
access.browseFilter, access.browseIndex, access.browseSelectionId =
  "objects", 1, nil
access:handleCommand("current_map_item")
local callsBeforeCounterRoute = #speechCalls
access:handleCommand("describe_route_to_selected_item")
S.eq(speechCalls[callsBeforeCounterRoute + 2].text,
       "Face up and interact",
  "object routes model the native talk-across-counter interaction distance")
map.isCounterCell = originalCounter
boulder.cellX, boulder.cellY = originalBoulderX, originalBoulderY
access.browseFilter, access.browseIndex, access.browseSelectionId =
  "signposts", 1, nil
access:handleCommand("current_map_item")
local callsBeforeSignRoute = #speechCalls
access:handleCommand("describe_route_to_selected_item")
S.eq(speechCalls[callsBeforeSignRoute + 2].text,
       "Face up and interact",
  "signpost routes also retain a reachable interaction position")
access.browseFilter, access.browseIndex, access.browseSelectionId =
  "all", 1, "warp:MOD_ROUTE:1"

local callsBeforeFilter = #speechCalls
access:handleCommand("next_item_filter")
S.eq(speechCalls[callsBeforeFilter + 1].kind, "stop",
  "filter change stops speech exactly once")
S.eq(speechCalls[callsBeforeFilter + 2].text, "Warps",
  "filter name is the first queued response")
S.eq(speechCalls[callsBeforeFilter + 3].text, "Mod House: 3 down 3 right",
  "filter selection follows in the same manual queue")

access:handleCommand("read_collision_tiles")
S.eq(lastOutput().text,
  "Now on 22, Up 12, Down 32, Left 21, Right 23",
  "E derives current and adjacent collision tiles from the live map")

access:handleCommand("read_camera_position")
S.eq(lastOutput().text, "x 2, y 2", "Shift+Y starts sonar at the player")
local callsBeforeTerrain = #speechCalls
access:handleCommand("read_terrain")
S.eq(speechCalls[callsBeforeTerrain + 2].text,
  "Sonar x 2, y 2. tall grass",
  "Shift+E speaks semantic terrain at sonar instead of a native tile ID")
S.eq(lastOutput().text, "Passable",
  "semantic terrain query includes known passability")
local cueCount = #cues
access:handleCommand("move_camera_left")
S.eq(#cues, cueCount + 1, "blocked camera movement emits one wall cue")
S.eq(cues[#cues].id, "wall", "normal sonar stops at a wall")
access:handleCommand("read_camera_position")
S.eq(lastOutput().text, "x 2, y 2", "normal wall collision retains camera position")
access:handleCommand("move_camera_left_through_walls")
access:handleCommand("read_camera_position")
S.eq(lastOutput().text, "x 1, y 2", "Shift sonar retains an in-bounds wall cell")
access:handleCommand("read_terrain")
S.eq(lastOutput().text, "Blocked",
  "semantic terrain query includes the collision verdict")
S.check(cues[#cues - 1].id == "wall" and cues[#cues].id == "wall",
  "through-wall move reports collision and the blocked target terrain")

access:handleCommand("reset_camera_to_player")
S.eq(cues[#cues].id, "grass", "F resets and identifies the player's terrain")
access:handleCommand("describe_route_to_camera")
S.eq(lastOutput().text, "Already there",
  "Shift+F handles a camera already on the player")
access:handleCommand("move_camera_right")
S.check(cues[#cues - 1].id == "boulder" and cues[#cues].id == "wall",
  "a pushable object is identified before its blocking wall cue")

local beforeBoulderThrough = #cues
access:handleCommand("move_camera_right_through_walls")
S.same({ cues[beforeBoulderThrough + 1].id,
         cues[beforeBoulderThrough + 2].id,
         cues[beforeBoulderThrough + 3].id },
       { "boulder", "wall", "default" },
  "through-wall boulder sonar layers entity, collision, and underlying floor once")
access:handleCommand("reset_camera_to_player")
local beforeDirectional = #cues
access:handleCommand("move_camera_down")
S.same({ cues[beforeDirectional + 1].id, cues[beforeDirectional + 2].id },
       { "pass", "move_down" },
  "sonar honors declarative mod terrain and native collision as separate layers")

access:handleCommand("toggle_camera_follow")
S.eq(lastOutput().text, "Camera does not follow the player",
  "C reports disabled follow mode")
S.eq(game.save.options.accessibilitySonarFollow, false,
  "C persists disabled follow mode in installation options")
access:handleCommand("toggle_camera_follow")
S.eq(lastOutput().text, "Camera follows the player",
  "C reports enabled follow mode")
S.eq(game.save.options.accessibilitySonarFollow, true,
  "C persists re-enabled follow mode")
S.eq(game.writes, 2, "each command-layer follow toggle flushes options once")

local originalCuttable = access.isCuttableCell
access.isCuttableCell = function(_, _, x, y) return x == 2 and y == 0 end
local routeWater = { ["2,1"] = true, ["3,1"] = true }
local routeMap = {}
function routeMap:isWaterCell(x, y) return routeWater[x .. "," .. y] == true end
local narrated = access:routeNarration({ map = routeMap }, {
  cost = 5,
  steps = {
    { fromX = 0, fromY = 0, x = 1, y = 0, direction = "right" },
    { fromX = 1, fromY = 0, x = 2, y = 0, direction = "right" },
    { fromX = 2, fromY = 0, x = 2, y = 1, direction = "down" },
    { fromX = 2, fromY = 1, x = 3, y = 1, direction = "right" },
    { fromX = 3, fromY = 1, x = 3, y = 2, direction = "down" },
  },
}, 2)
S.same(narrated, {
  "1 right", "Use Cut facing right", "1 right",
  "Use Surf facing down", "1 down", "1 right", "Exit water down",
}, "route narration inserts actionable Cut and Surf transitions without dropping movement")
access.isCuttableCell = function(_, _, x, y)
  return (x == 2 or x == 3) and y == 0
end
local oneBlockNarration = access:routeNarration({ map = routeMap }, {
  cost = 2,
  steps = {
    { fromX = 1, fromY = 0, x = 2, y = 0, direction = "right" },
    { fromX = 2, fromY = 0, x = 3, y = 0, direction = "right" },
  },
}, 2)
S.same(oneBlockNarration, { "Use Cut facing right", "2 right" },
  "one 2x2 Cut block produces one action even when two cells are crossed")
access.isCuttableCell = originalCuttable

local obstacleParts, obstacleError, obstacleResult =
  access:findWorldRoute({ { x = 4, y = 2 } })
S.eq(obstacleError, nil, "route around a live person succeeds")
S.same(obstacleParts, { "1 up", "2 right", "1 down" },
  "route instructions detour around a live person")
local crossedPerson = false
for _, cell in ipairs(obstacleResult.cells) do
  if cell.x == boulder.cellX and cell.y == boulder.cellY then
    crossedPerson = true
  end
end
S.check(not crossedPerson, "route cells never cross the occupied actor cell")

local blockedGoalParts, blockedGoalError =
  access:findWorldRoute({ { x = boulder.cellX, y = boulder.cellY } })
S.eq(blockedGoalParts, nil, "an occupied route goal is not force-enabled")
S.eq(blockedGoalError, "No path",
  "an occupied route goal reports no path instead of entering the actor")

-- A merged semantic destination routes to the cheapest reachable physical
-- entrance instead of exposing each doorway as another list item.
local savedWarps = map.def.warps
map.def.warps = {
  { x = 1, y = 2, destMap = "MOD_HOUSE", destWarp = 1 },
  { x = 5, y = 5, destMap = "MOD_HOUSE", destWarp = 2 },
}
local mergedSnapshot = assert(access:captureWorld("warps"))
S.eq(#mergedSnapshot.browse, 1,
  "two entrances to Mod House produce one navigation destination")
S.eq(#mergedSnapshot.browse[1].navigationCells, 2,
  "the destination carries both route candidates")
local mergedParts, mergedError, mergedResult = access:findWorldRoute(
  mergedSnapshot.browse[1].navigationCells)
S.eq(mergedError, nil, "master destination route finds a usable entrance")
S.same(mergedResult.goal, { x = 5, y = 5 },
  "master route rejects the blocked entrance and selects the reachable one")
S.check(#mergedParts > 0, "master destination returns normal directions")
map.def.warps = savedWarps

-- Failed selected-item routes get a proven HM requirement. The diagnostic
-- retry may use all HMs, but only capabilities crossed by its complete route
-- are spoken; an ordinary hard wall remains an honest unknown.
local savedWalkable = map.isWalkableCell
local savedWater = map.isWaterCell
local savedCuttableForRequirements = access.isCuttableCell
local savedRouteEntities, savedRouteNpcs = overworld.entities, overworld.npcs
overworld.entities, overworld.npcs = { player }, {}
player.cellX, player.cellY = 1, 2
local corridorWater, corridorCut = {}, {}
map.isWalkableCell = function(self, x, y)
  return self:inBounds(x, y) and y == 2
    and not corridorWater[x .. "," .. y]
    and not corridorCut[x .. "," .. y]
end
map.isWaterCell = function(_, x, y)
  return corridorWater[x .. "," .. y] == true
end
access.isCuttableCell = function(_, _, x, y)
  return corridorCut[x .. "," .. y] == true
end

corridorCut["2,2"] = true
S.eq(access:routeRequirement({ { x = 4, y = 2 } }), "Needs Cut",
  "a complete hypothetical Cut route reports its exact requirement")
corridorCut["2,2"] = nil
corridorWater["2,2"] = true
S.eq(access:routeRequirement({ { x = 4, y = 2 } }), "Needs Surf",
  "a complete hypothetical water route reports Surf")
corridorCut["2,2"], corridorWater["3,2"] = true, true
S.eq(access:routeRequirement({ { x = 4, y = 2 } }), "Needs Cut and Surf",
  "a route can report more than one proven HM requirement")

-- P has no route-mode setting. It first avoids HMs, then uses capabilities the
-- current party has, and finally returns the complete hypothetical route with
-- an honest requirement instead of replacing the directions with that phrase.
corridorWater, corridorCut = {}, { ["2,2"] = true }
local automaticParts, automaticError, automaticResult =
  access:findWorldRoute({ { x = 4, y = 2 } })
S.eq(automaticError, nil, "automatic routing finds the all-HM fallback")
S.eq(automaticResult.policy, 3, "missing Cut selects the hypothetical tier")
S.same(automaticParts, { "Needs Cut", "Use Cut facing right", "3 right" },
  "missing Cut is announced alongside the complete route")
function overworld:partyKnows(moveId)
  if moveId == "CUT" then return { species = "BULBASAUR" } end
end
automaticParts, automaticError, automaticResult =
  access:findWorldRoute({ { x = 4, y = 2 } })
S.eq(automaticError, nil, "automatic routing uses a party HM without a setting")
S.eq(automaticResult.policy, 2, "known Cut selects the available-HM tier")
S.same(automaticParts, { "Use Cut facing right", "3 right" },
  "known Cut gets actionable directions without a false Needs Cut warning")
overworld.partyKnows = nil

corridorCut, corridorWater = {}, {}
map.isWalkableCell = function(self, x, y)
  return self:inBounds(x, y) and y == 2 and x < 2
end
S.eq(access:routeRequirement({ { x = 4, y = 2 } }), "Cannot reach yet",
  "a route with no proven HM solution does not guess at its blocker")
local noParts, selectedReason = access:finishWorldRoute(
  overworld, nil, "no path", { { x = 4, y = 2 } }, true)
S.eq(noParts, nil, "failed selected route still returns no directions")
S.eq(selectedReason, "Cannot reach yet",
  "selected-item failure uses the accessible availability wording")

map.isWalkableCell, map.isWaterCell = savedWalkable, savedWater
access.isCuttableCell = savedCuttableForRequirements
overworld.entities, overworld.npcs = savedRouteEntities, savedRouteNpcs
player.cellX, player.cellY = 2, 2
local guard = { cellX = 2, cellY = 2, def = { name = "LAB_PEDESTAL_GUARD" } }
local savedPlayerXForApproach, savedPlayerYForApproach = player.cellX, player.cellY
local savedNpcsForApproach, savedEntitiesForApproach = overworld.npcs, overworld.entities
player.cellX, player.cellY = 0, 2
overworld.npcs = { boulder, guard }
overworld.entities = { player, boulder, guard }
local approachGoals = access:interactionGoals(overworld, {
  type = "object", x = boulder.cellX, y = boulder.cellY,
})
local _, approachError, approachResult = access:findWorldRoute(approachGoals)
S.eq(approachError, nil,
  "pedestal-style target selects another reachable interaction side")
S.check(not (approachResult.goal.x == guard.cellX
             and approachResult.goal.y == guard.cellY),
  "occupied pedestal approach is rejected as a final standing cell")

player.cellX, player.cellY = 2, 3
local footprintGoals = access:interactionGoals(overworld, {
  type = "object", x = 1, y = 2,
  interactionCells = { { x = 1, y = 2 }, { x = 1, y = 3 } },
})
local hasCurrentCell = false
for _, goal in ipairs(footprintGoals) do
  if goal.x == player.cellX and goal.y == player.cellY then
    hasCurrentCell = true
  end
end
S.check(hasCurrentCell,
  "multi-cell interaction footprint accepts the player's nearest valid side")
player.cellX, player.cellY = savedPlayerXForApproach, savedPlayerYForApproach
overworld.npcs, overworld.entities = savedNpcsForApproach, savedEntitiesForApproach

game.data.field = { ledges = {
  { tileset = "OVERWORLD", standingTile = 22, ledgeTile = 32,
    facing = "down", input = "down" },
} }
local ledgeParts, ledgeError, ledgeResult = access:findWorldRoute({ { x = 2, y = 5 } })
S.eq(ledgeError, nil, "native ledge route succeeds")
S.same(ledgeParts, { "Jump ledge down", "1 down" },
  "ledge route narration represents one input and skips the intermediate tile")
S.same(ledgeResult.cells,
  { { x = 2, y = 2 }, { x = 2, y = 4 }, { x = 2, y = 5 } },
  "ledge route graph lands two cells away like the native controller")
local NativeMap = require("src.world.Map")
local generatedMaps = require("data.generated.maps")
local generatedTilesets = require("data.generated.tilesets")
game.data.field = require("data.generated.field")
local cerulean = NativeMap.new(generatedMaps.CERULEAN_CITY,
  generatedTilesets[generatedMaps.CERULEAN_CITY.tileset])
local ceruleanWorld = {
  map = cerulean, player = { cellX = 18, cellY = 30, facing = "up" },
  entities = {}, npcs = {},
}
local ceruleanObjects = access:interactiveBrowseObjects(ceruleanWorld)
local ceruleanCut
for _, object in ipairs(ceruleanObjects) do
  if object.semanticKind == "cut_tree" then ceruleanCut = object break end
end
S.check(ceruleanCut and #ceruleanCut.interactionCells > 1,
  "real Cerulean Cut block retains every native blocked quadrant")
local ceruleanGoals, ceruleanInstructions = access:interactionGoals(ceruleanWorld, {
  type = "object", x = ceruleanCut.x, y = ceruleanCut.y,
  interaction = "cut", interactionCells = ceruleanCut.interactionCells,
})
local ceruleanAlreadyThere = false
for _, goal in ipairs(ceruleanGoals) do
  if goal.x == 18 and goal.y == 30 then ceruleanAlreadyThere = true end
end
S.check(ceruleanAlreadyThere,
  "Cerulean entrance route recognizes the live south-side Cut position")
S.eq(ceruleanInstructions["18,30"],
  "Face up and use Cut from the party menu",
  "Cerulean entrance route names the native Cut action")
local nativeLedgeX, nativeLedgeY = access:ledgeDestination({
  map = cerulean,
  player = { cellX = 24, cellY = 2 },
  entities = {},
}, 24, 2, "down")
S.same({ nativeLedgeX, nativeLedgeY }, { 24, 4 },
  "real Cerulean ledge fixture resolves to the native two-cell landing")

game.data.field = { spinners = { MOD_ROUTE = {
  { x = 3, y = 2, moves = { { dir = "right", count = 2 } } },
} } }
local savedEntitiesForSpinner, savedNpcsForSpinner =
  overworld.entities, overworld.npcs
overworld.entities, overworld.npcs = { player }, {}
local spinnerParts, spinnerError, spinnerResult =
  access:findWorldRoute({ { x = 5, y = 2 } })
S.eq(spinnerError, nil, "native spinner route succeeds")
S.same(spinnerParts,
  { "Move right onto spinner, then forced 2 right" },
  "spinner narration separates the controllable entry from forced movement")
S.same(spinnerResult.cells, { { x = 2, y = 2 }, { x = 5, y = 2 } },
  "spinner route graph skips cells the player cannot control")
overworld.entities, overworld.npcs = savedEntitiesForSpinner, savedNpcsForSpinner

game.data.field = require("data.generated.field")
local rocket = NativeMap.new(generatedMaps.ROCKET_HIDEOUT_B2F,
  generatedTilesets[generatedMaps.ROCKET_HIDEOUT_B2F.tileset])
local spinnerX, spinnerY, spinnerInstruction, spinnerMatched =
  access:spinnerDestination({ map = rocket }, 4, 9, "down")
S.same({ spinnerX, spinnerY, spinnerMatched }, { 2, 9, true },
  "real Rocket Hideout spinner resolves its extracted landing")
S.eq(spinnerInstruction, "Move down onto spinner, then forced 2 left",
  "real Rocket Hideout spinner retains its forced direction and distance")

game.data.field = { spinners = { MOD_ROUTE = {
  { x = 3, y = 2, moves = { { dir = "right", count = 1 } } },
  { x = 4, y = 2, moves = { { dir = "left", count = 1 } } },
} } }
local cycleX, cycleY, _, cycleMatched =
  access:spinnerDestination(overworld, 3, 2, "right")
S.check(cycleX == nil and cycleY == nil and cycleMatched == true,
  "cyclic mod spinner data is detected and fails closed")

game.data.field = { seafoam = { MOD_ROUTE = {
  currentsDisabledByEvents = { "EVENT_NEVER_SET" },
  currents = {
    { x = 4, y = 2, moves = { { dir = "right", count = 1 } } },
  },
} } }
overworld.entities, overworld.npcs = { player }, {}
player.surfing = true
local currentParts, currentError, currentResult =
  access:findWorldRoute({ { x = 5, y = 2 } })
S.eq(currentError, nil, "active Seafoam-style current route succeeds")
S.same(currentParts,
  { "1 right", "Move right into current, then current 1 right" },
  "current narration separates controlled entry from forced water movement")
S.same(currentResult.cells,
  { { x = 2, y = 2 }, { x = 3, y = 2 }, { x = 5, y = 2 } },
  "current route graph omits the uncontrollable intermediate water cell")
player.surfing = nil
overworld.entities, overworld.npcs = savedEntitiesForSpinner, savedNpcsForSpinner

game.data.field = require("data.generated.field")
local seafoamB3 = NativeMap.new(generatedMaps.SEAFOAM_ISLANDS_B3F,
  generatedTilesets[generatedMaps.SEAFOAM_ISLANDS_B3F.tileset])
local currentX, currentY, currentInstruction, currentMatched, currentKind =
  access:forcedDestination({
    map = seafoamB3, player = { surfing = true }, entities = {},
  }, 18, 7, "down")
S.same({ currentX, currentY, currentMatched, currentKind },
  { 20, 17, true, "current" },
  "real Seafoam B3F current resolves its extracted forced landing")
S.eq(currentInstruction,
  "Move down into current, then current 4 down, then current 2 right, then current 6 down",
  "real Seafoam B3F current retains its complete forced movement sequence")
S.eq(game.data.field.seafoam.SEAFOAM_ISLANDS_B3F.currents[1].kind, nil,
  "current resolution never annotates or mutates generated field records")

local savedFlags = game.save.flags
game.save.flags = {}
local seafoamB4 = NativeMap.new(generatedMaps.SEAFOAM_ISLANDS_B4F,
  generatedTilesets[generatedMaps.SEAFOAM_ISLANDS_B4F.tileset])
local exitX, exitY, exitInstruction, exitMatched = access:forcedDestination({
  map = seafoamB4, player = { surfing = true }, entities = {},
}, 20, 17, "down")
S.same({ exitX, exitY, exitMatched }, { 20, 15, true },
  "active Seafoam B4F current mouth forces the native two-cell retreat")
S.eq(exitInstruction, "Move down into current, then current 2 up",
  "Seafoam forced-exit narration reports the state-dependent retreat")
game.save.flags = {
  EVENT_SEAFOAM3_BOULDER1_DOWN_HOLE = true,
  EVENT_SEAFOAM3_BOULDER2_DOWN_HOLE = true,
}
local _, _, _, disabledExit = access:forcedDestination({
  map = seafoamB4, player = { surfing = true }, entities = {},
}, 20, 17, "down")
S.eq(disabledExit, false,
  "plugging both upstream boulders disables the Seafoam forced exit")
game.save.flags = savedFlags
game.data.field = nil

require("data.scripts.init")
local mansionScripts = require("data.scripts.story6")
local TraversalSemantics = require("src.access.nav.TraversalSemantics")
local mansionTraversal = assert(TraversalSemantics.forMap("POKEMON_MANSION_3F"))
S.eq(#mansionTraversal.specialWarps, 3,
  "accessibility semantics expose all three native Mansion 3F drop holes")
S.same({ mansionTraversal.specialWarps[1].x,
         mansionTraversal.specialWarps[1].y,
         mansionTraversal.specialWarps[1].destinationMap },
       { 16, 14, "POKEMON_MANSION_1F" },
  "Mansion hole metadata shares the gameplay script's real destination")

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = deepCopy(child) end
  return result
end
local function mansionMapWithSwitch(on, mapId)
  mapId = mapId or "POKEMON_MANSION_1F"
  local def = deepCopy(generatedMaps[mapId])
  local live = NativeMap.new(def, generatedTilesets[def.tileset])
  local fakeGame = { save = { flags = {
    EVENT_MANSION_SWITCH_ON = on and true or nil,
  } } }
  local fakeWorld = { map = live }
  function fakeWorld:replaceBlock(bx, by, block) live:setBlock(bx, by, block) end
  mansionScripts[mapId].onEnter(fakeGame, fakeWorld)
  return live
end
local mansionOff, mansionOn = mansionMapWithSwitch(false), mansionMapWithSwitch(true)
S.check(not mansionOff:isWalkableCell(16, 7)
        and mansionOn:isWalkableCell(16, 7),
  "real Mansion switch state opens the first live collision passage")
S.check(mansionOff:isWalkableCell(24, 13)
        and not mansionOn:isWalkableCell(24, 13),
  "real Mansion switch state closes the complementary live passage")

local mansionFloors = {
  "POKEMON_MANSION_1F", "POKEMON_MANSION_2F",
  "POKEMON_MANSION_3F", "POKEMON_MANSION_B1F",
}
local totalProjectedAcrossStates = 0
for _, mapId in ipairs(mansionFloors) do
  local traversal = assert(TraversalSemantics.forMap(mapId))
  for _, on in ipairs({ false, true }) do
    local live = mansionMapWithSwitch(on, mapId)
    local player = { cellX = 0, cellY = 0, facing = "down" }
    local world = { map = live, player = player, entities = { player }, npcs = {} }
    local projected, seenCells, seenIds = {}, {}, {}
    for _, object in ipairs(access:interactiveBrowseObjects(world)) do
      if object.semanticKind == "mansion_gate" then
        projected[#projected + 1] = object
        S.check(not seenIds[object.id],
          mapId .. " does not duplicate a closed gate object")
        seenIds[object.id] = true
        S.check(#(object.interactionCells or {}) > 0,
          mapId .. " closed gate retains a native collision footprint")
        for _, cell in ipairs(object.interactionCells or {}) do
          local key = tostring(cell.x) .. "," .. tostring(cell.y)
          S.check(not seenCells[key],
            mapId .. " does not expose one closed gate cell twice")
          seenCells[key] = true
        end
      end
    end
    local expected = 0
    for index, gate in ipairs(traversal.alternatingGates) do
      local block = on and gate.onBlock or gate.offBlock
      if block ~= gate.openBlock then
        expected = expected + 1
        S.check(seenIds[gate.id],
          mapId .. " projects closed gate " .. tostring(index)
            .. " in the correct switch state")
      else
        S.check(not seenIds[gate.id],
          mapId .. " removes open gate " .. tostring(index)
            .. " in the correct switch state")
      end
    end
    S.eq(#projected, expected,
      mapId .. " exposes exactly one object per live closed gate")
    totalProjectedAcrossStates = totalProjectedAcrossStates + #projected
  end
end
S.eq(totalProjectedAcrossStates, 13,
  "both switch states account for every native Mansion alternating gate once")

local gymTraversal = assert(TraversalSemantics.forMap("CINNABAR_GYM"))
S.eq(#gymTraversal.switches, 6,
  "accessibility semantics expose all six native quiz-machine gates")
S.same({ gymTraversal.switches[1].x, gymTraversal.switches[1].y,
         gymTraversal.switches[1].stateFlag },
       { 15, 7, "EVENT_CINNABAR_GYM_GATE0_UNLOCKED" },
  "quiz traversal metadata retains the native machine and gate flag")
local function cinnabarMapWithGate(open)
  local def = deepCopy(generatedMaps.CINNABAR_GYM)
  local live = NativeMap.new(def, generatedTilesets[def.tileset])
  local flags = {}
  if open then flags.EVENT_CINNABAR_GYM_GATE0_UNLOCKED = true end
  local fakeGame = { save = { flags = flags, defeatedTrainers = {} } }
  local fakeWorld = { map = live }
  function fakeWorld:replaceBlock(bx, by, block) live:setBlock(bx, by, block) end
  mansionScripts.CINNABAR_GYM.onEnter(fakeGame, fakeWorld)
  return live
end
local gymClosed, gymOpen = cinnabarMapWithGate(false), cinnabarMapWithGate(true)
S.check(not gymClosed:isWalkableCell(18, 6)
        and gymOpen:isWalkableCell(18, 6),
  "real Cinnabar gate flag changes the live route collision surface")

local savedGameData, savedOverworld = game.data, game.overworld
local savedStackStates, savedStackCurrent = stack.states, stack.current
local savedBrowseFilter, savedBrowseIndex, savedBrowseSelection =
  access.browseFilter, access.browseIndex, access.browseSelectionId
game.data = { maps = generatedMaps, field = require("data.generated.field") }
local mansionPlayer = { name = "RED", cellX = 2, cellY = 6, facing = "up" }
local mansionWorld = {
  isOverworld = true, map = mansionOff, player = mansionPlayer,
  npcs = {}, entities = { mansionPlayer },
}
game.overworld = mansionWorld
stack.states, stack.current = { mansionWorld }, mansionWorld
access.browseFilter, access.browseIndex, access.browseSelectionId =
  "objects", 1, "mansion_switch:POKEMON_MANSION_1F:1"
access:handleCommand("current_map_item")
S.eq(lastOutput().text, "Secret switch: 1 up",
  "real Mansion switch is discoverable through native map browsing")
local beforeMansionSwitchRoute = #speechCalls
access:handleCommand("describe_route_to_selected_item")
S.eq(speechCalls[beforeMansionSwitchRoute + 2].text,
       "Face up and interact",
  "Mansion switch route honors its gameplay facing requirement")

local selectedGate
for _, object in ipairs(access:interactiveBrowseObjects(mansionWorld)) do
  if object.semanticKind == "mansion_gate" then selectedGate = object break end
end
S.check(selectedGate ~= nil,
  "real Mansion closed gate is discoverable as one live object")
local gateGoals, gateInstructions = access:interactionGoals(
  mansionWorld, selectedGate)
S.check(#gateGoals > 0,
  "Mansion closed gate has at least one legal neighboring route endpoint")
local gateCells = {}
for _, cell in ipairs(selectedGate.interactionCells or {}) do
  gateCells[tostring(cell.x) .. "," .. tostring(cell.y)] = true
end
for _, goal in ipairs(gateGoals) do
  local key = tostring(goal.x) .. "," .. tostring(goal.y)
  S.check(not gateCells[key],
    "Mansion gate route never asks the player to stand inside the closed gate")
  S.eq(gateInstructions[key], "Closed passage; use a Secret switch",
    "Mansion gate route explains the puzzle instead of claiming it is usable")
end

local mansion3Def = deepCopy(generatedMaps.POKEMON_MANSION_3F)
local mansion3 = NativeMap.new(mansion3Def,
  generatedTilesets[mansion3Def.tileset])
mansionPlayer.cellX, mansionPlayer.cellY = 15, 14
mansionWorld.map = mansion3
access.browseFilter, access.browseIndex, access.browseSelectionId =
  "warps", 1, "mansion_hole:POKEMON_MANSION_3F:1"
access:handleCommand("current_map_item")
S.check(lastOutput().text:find("Drop to Pokémon Mansion", 1, true) == 1,
  "real Mansion hole is discoverable and names its destination")
local beforeMansionHoleRoute = #speechCalls
access:handleCommand("describe_route_to_selected_item")
S.check(speechCalls[beforeMansionHoleRoute + 2].text:find(
  "Drop to ", 1, true) == 1
  and speechCalls[beforeMansionHoleRoute + 2].text:find(
    "Mansion 1F", 1, true) ~= nil,
  "Mansion hole navigation identifies its landing before movement")
S.eq(speechCalls[beforeMansionHoleRoute + 3].text, "1 right",
  "Mansion hole route reaches the exact special-warp cell")
S.eq(#speechCalls, beforeMansionHoleRoute + 3,
  "Mansion hole destination is a one-time navigation preamble")
access:handleCommand("describe_route_to_selected_item")
S.eq(lastOutput().text, "Navigation stopped",
  "a second P stops the Mansion route")

-- Starting on the drop should use the arrival instruction itself, not repeat
-- the same destination as both a preamble and an arrival warning.
mansionPlayer.cellX, mansionPlayer.cellY = 16, 14
local beforeMansionHoleArrival = #speechCalls
access:handleCommand("describe_route_to_selected_item")
S.check(speechCalls[beforeMansionHoleArrival + 2].text:find(
  "Drop to ", 1, true) == 1
  and speechCalls[beforeMansionHoleArrival + 2].text:find(
    "Mansion 1F", 1, true) ~= nil,
  "arrival at a Mansion hole repeats its landing warning")
S.eq(#speechCalls, beforeMansionHoleArrival + 2,
  "arrival speaks the hole destination exactly once")

game.data, game.overworld = savedGameData, savedOverworld
stack.states, stack.current = savedStackStates, savedStackCurrent
access.browseFilter, access.browseIndex, access.browseSelectionId =
  savedBrowseFilter, savedBrowseIndex, savedBrowseSelection

access.browseFilter, access.browseIndex, access.browseSelectionId =
  "connections", 1, "connection:MOD_ROUTE:north"
access:handleCommand("current_map_item")
local beforeConnectionRoute = #speechCalls
access:handleCommand("describe_route_to_selected_item")
S.eq(speechCalls[beforeConnectionRoute + 2].text, "2 up",
  "connection route reaches a valid cell on the selected boundary")
S.eq(#speechCalls, beforeConnectionRoute + 2,
  "connection continuation is deferred until the boundary is reached")
player.cellY = 0
access.pendingStepEvent = { mapId = map.id, x = player.cellX, y = player.cellY }
access:processWorldEvents(overworld)
S.eq(lastOutput().text, "Continue north to Route 1",
  "connection arrival retains natural compass wording")
S.same({ lastSemantic("navigation.arrived").action,
         lastSemantic("navigation.arrived").direction },
       { "continue", "up" },
  "connection arrival exposes a canonical Game Boy direction")
player.cellY = 2

local battle = {
  isBattle = true,
  enemy = { name = "RATTATA", mon = { hp = 1, stats = { hp = 4 } } },
  player = { name = "PIKACHU", mon = {
    hp = 12, stats = { hp = 35 }, status = "PAR",
  } },
}
stack.states = { overworld, battle }
stack.current = battle
access:handleCommand("read_enemy_health")
S.eq(lastOutput().text, "Enemy health: 25.00 percent",
  "H reads enemy HP as the reference percentage")
access:handleCommand("read_player_health")
S.eq(lastOutput().text, "Player PIKACHU, 12 of 35 HP, paralyzed",
  "Shift+H reads player HP and status")

battle.accessibilitySnapshot = function()
  return { enterText = "Battle", text = "Fight, 1 of 4" }
end
-- v0.3.98 adaptation: screens are spoken by src/access/screens, and T
-- repeats their most recent speech (src/access/Speech.lastScreenText).
access:handleCommand("read_screen_text")
S.eq(lastOutput().text, require("src.access.Speech").lastScreenText() or "No accessible screen text",
  "T repeats the most recent screen speech")

stack.states, stack.current = { overworld }, overworld
access.browseFilter, access.browseSelectionId = "objects", nil
access:handleCommand("rename_selected_item")
local naming = stack:top()
S.eq(naming.accessibilityTitle, "Rename selected item",
  "Shift+K opens the already-accessible naming UI")
S.eq(table.concat(naming.glyphs), "Round Rock",
  "rename UI is initialized from the current custom label")
naming.onDone("Stone")
S.eq(game.save.options.accessibilityNames.objects.MOD_ROUTE.MOD_ROUTE_obj_1,
  "Stone", "renamed object is persisted by stable native id")
S.eq(game.writes, 3, "object rename flushes data-only options")
S.eq(lastOutput().text, "Names saved", "rename completion is confirmed")

stack.states, stack.current = { overworld }, overworld
access:handleCommand("rename_map")
naming = stack:top()
naming.onDone("")
S.check(game.save.options.accessibilityNames.maps.MOD_ROUTE == nil,
  "an empty map rename clears the override instead of writing executable Lua")
S.eq(game.writes, 4, "map rename also flushes options")

stack.states, stack.current = { overworld }, overworld
access:handleCommand("configure_rom_hack")
S.check(lastOutput().text:find("native port", 1, true) ~= nil,
  "Shift+0 explains the native mod replacement for ROM profiles")

local savedNpcs, savedEntities = overworld.npcs, overworld.entities
overworld.npcs, overworld.entities = {}, { player }
access.browseFilter, access.browseIndex, access.browseSelectionId =
  "objects", 1, nil
access:handleCommand("current_map_item")
S.eq(lastOutput().text, "Empty List.",
  "an empty browse category is announced without an exception")
local stateBeforeEmptyRename = stack:top()
access:handleCommand("rename_selected_item")
S.eq(lastOutput().text, "Empty List.",
  "rename selected item reports an empty category")
S.eq(stack:top(), stateBeforeEmptyRename,
  "rename selected item cannot open naming UI without a stable target")
overworld.npcs, overworld.entities = savedNpcs, savedEntities

stack.states, stack.current = {}, { screenId = "TitleState" }
access:handleCommand("read_map_name")
S.eq(lastOutput().text, "Not on a map", "map commands fail accessibly off-map")
access:handleCommand("read_enemy_health")
S.eq(lastOutput().text, "Not in battle", "health commands fail accessibly off-battle")

access:handleCommandStatus("command_layer_enabled")
S.check(lastOutput().text:find("command mode on", 1, true) ~= nil,
  "F7 enable status explains the safe movement fallback")
access:handleCommandStatus("command_layer_disabled")
S.eq(lastOutput().text, "Accessibility command mode off",
  "F7 disable status is explicit")

-- A deliberately long, open mod map proves that production commands use the
-- cooperative task API instead of monopolizing a LÖVE frame.  The ordinary
-- fixture routes above remain synchronous because they finish within one
-- 128-node slice.
stack.states, stack.current = { overworld }, overworld
local savedWidth, savedHeight = map.widthCells, map.heightCells
local savedWarps, savedInBounds = map.def.warps, map.inBounds
local savedPlayerX, savedPlayerY = player.cellX, player.cellY
local savedNpcs2, savedEntities2 = overworld.npcs, overworld.entities
map.widthCells, map.heightCells = 1000, 1
map.def.warps = {}
function map:inBounds(x, y) return x >= 0 and x < 1000 and y == 0 end
player.cellX, player.cellY = 0, 0
overworld.npcs, overworld.entities = {}, { player }
access.sonarMapId, access.sonarX, access.sonarY = map.id, 999, 0
local callsBeforeSilentRoute = #speechCalls
access:handleCommand("describe_route_to_camera")
S.check(access.pendingRoute ~= nil,
  "a long native route yields through a live accessibility task")
S.eq(#speechCalls, callsBeforeSilentRoute,
  "a yielded route calculates silently until it has a result")
access:handleCommand("describe_route_to_camera")
S.eq(lastOutput().text, "Route cancelled",
  "pressing the route command again cancels live calculation")
S.eq(access.pendingRoute, nil, "route cancellation releases the live task")

access:handleCommand("describe_route_to_camera")
access:setEnabled(false, { silent = true })
S.eq(access.pendingRoute, nil,
  "disabling accessibility invalidates an in-flight route")
access:setEnabled(true, { silent = true })
access:handleCommand("describe_route_to_camera")
for _ = 1, 16 do
  if not access.pendingRoute then break end
  access:updatePendingRoute()
end
S.eq(access.pendingRoute, nil, "a cooperative route completes across bounded slices")
S.eq(lastOutput().text, "999 right",
  "cooperative completion preserves deterministic grouped narration")

local savedLongWalkable = map.isWalkableCell
local savedLongCuttable = access.isCuttableCell
function map:isWalkableCell(x, y)
  return self:inBounds(x, y) and x ~= 500
end
access.isCuttableCell = function(_, _, x, y) return x == 500 and y == 0 end
access.sonarX, access.sonarY = 999, 0
local speechBeforeAutomaticTask = #speechCalls
access:handleCommand("describe_route_to_camera")
for _ = 1, 40 do
  if not access.pendingRoute then break end
  access:updatePendingRoute()
end
S.eq(access.pendingRoute, nil,
  "cooperative routing automatically advances through all HM tiers")
local automaticTaskText = {}
local sawAutomaticNeedsCut, sawAutomaticUseCut = false, false
for i = speechBeforeAutomaticTask + 1, #speechCalls do
  if speechCalls[i].kind == "output" then
    automaticTaskText[#automaticTaskText + 1] = speechCalls[i].text
    if speechCalls[i].text == "Needs Cut" then sawAutomaticNeedsCut = true end
    if speechCalls[i].text == "Use Cut facing right" then
      sawAutomaticUseCut = true
    end
  end
end
S.check(sawAutomaticNeedsCut,
  "the live P command announces a missing Cut requirement")
S.check(sawAutomaticUseCut,
  "the live P command keeps the exact Cut action in its complete route")
S.eq(automaticTaskText[#automaticTaskText], "500 right",
  "the live P command narrates the route beyond the missing HM obstacle")
map.isWalkableCell = savedLongWalkable
access.isCuttableCell = savedLongCuttable

map.widthCells, map.heightCells = savedWidth, savedHeight
map.def.warps, map.inBounds = savedWarps, savedInBounds
player.cellX, player.cellY = savedPlayerX, savedPlayerY
overworld.npcs, overworld.entities = savedNpcs2, savedEntities2
access.sonarMapId, access.sonarX, access.sonarY = nil, nil, nil

S.finish()
