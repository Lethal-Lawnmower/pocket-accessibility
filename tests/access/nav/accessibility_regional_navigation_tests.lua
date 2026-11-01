local T = require("tests.harness")
local S = T.suite("accessibility regional navigation")
local Accessibility = require("src.access.nav.Navigation")
local Collision = require("src.world.Collision")
local Map = require("src.world.Map")
local Pathfinder = require("src.access.nav.Pathfinder")

local data = {
  maps = require("data.generated.maps"),
  tilesets = require("data.generated.tilesets"),
  field = require("data.generated.field"),
}
Collision.load(data)

local speechCalls = {}
local speech = {}
function speech:isAvailable() return true end
function speech:stop()
  speechCalls[#speechCalls + 1] = { kind = "stop" }
  return true
end
function speech:output(text)
  speechCalls[#speechCalls + 1] = { kind = "output", text = text }
  return true
end

local events = { listeners = {} }
function events:on(name, callback)
  self.listeners[name] = self.listeners[name] or {}
  self.listeners[name][#self.listeners[name] + 1] = callback
  return function() end
end
function events:emit(name, event)
  for _, callback in ipairs(self.listeners[name] or {}) do callback(event) end
end

local game = {
  data = data,
  save = {
    options = {}, flags = {}, itemsTaken = {}, defeatedTrainers = {},
    objectToggles = {}, player = { name = "RED" },
  },
}

local function setWorld(mapId, x, y)
  local def = data.maps[mapId]
  local map = Map.new(def, data.tilesets[def.tileset])
  local player = { name = "RED", cellX = x, cellY = y,
                   facing = "down", surfing = false }
  local entities = { player }
  for _, object in ipairs(def.objects or {}) do
    entities[#entities + 1] = {
      cellX = object.x, cellY = object.y, def = object,
    }
  end
  local world = {
    isOverworld = true, map = map, player = player,
    entities = entities, npcs = entities,
  }
  local stack = { current = world }
  function stack:top() return self.current end
  game.overworld, game.stack = world, stack
end

local function setClosedSilphWorld(mapId, x, y)
  local source = data.maps[mapId]
  local def = {}
  for key, value in pairs(source) do def[key] = value end
  def.blocks = {}
  for index, block in ipairs(source.blocks) do def.blocks[index] = block end
  local map = Map.new(def, data.tilesets[def.tileset])
  for _, door in ipairs(data.field.cardKeyDoors.closedDoors[mapId] or {}) do
    map:setBlock(door.bx, door.by, door.block)
  end
  local player = { name = "RED", cellX = x, cellY = y,
                   facing = "down", surfing = false }
  local world = {
    isOverworld = true, map = map, player = player,
    entities = { player }, npcs = {},
  }
  local stack = { current = world }
  function stack:top() return self.current end
  game.overworld, game.stack = world, stack
  return world
end

local function arrivalFor(mapId, leg)
  local goal = leg.goals[1]
  for _, warp in ipairs(data.maps[mapId].warps or {}) do
    if warp.x == goal.x and warp.y == goal.y
       and warp.destMap == leg.nextMapId then
      local arrival = data.maps[warp.destMap].warps[warp.destWarp]
      return warp.destMap, arrival.x, arrival.y
    end
  end
end

setWorld("SAFARI_ZONE_WEST", 29, 22)
local access = Accessibility.new(game, {
  enabled = true, speech = speech, events = events, defaultDelayFrames = 0,
})

-- Route22Gate_Script rewrites LAST_MAP from the player's Y position. The
-- accessibility view must therefore keep its north and south doors separate
-- even when the player entered from Route 22.
setWorld("ROUTE_22_GATE", 4, 6)
game.overworld.lastOutdoor = { id = "ROUTE_22" }
local gateSnapshot = assert(access:captureWorld("warps"))
S.eq(#gateSnapshot.browse, 2,
  "Route 22 Gate exposes distinct north and south destinations")
local gateDestinations, gateCellCounts = {}, {}
for _, item in ipairs(gateSnapshot.browse) do
  gateDestinations[item.destinationMapId] = true
  gateCellCounts[item.destinationMapId] = #(item.navigationCells or {})
end
S.check(gateDestinations.ROUTE_22 and gateDestinations.ROUTE_23,
  "Route 22 Gate names Route 23 instead of merging every door into Route 22")
S.eq(gateCellCounts.ROUTE_22, 2,
  "both south door tiles share one Route 22 browse target")
S.eq(gateCellCounts.ROUTE_23, 2,
  "both north door tiles share one Route 23 browse target")

local gateTransitions = access:regionalTransitions("ROUTE_22_GATE")
local transitionCounts = { ROUTE_22 = 0, ROUTE_23 = 0 }
for _, transition in ipairs(gateTransitions) do
  if transitionCounts[transition.destMap] ~= nil then
    transitionCounts[transition.destMap] = transitionCounts[transition.destMap] + 1
  end
end
S.eq(transitionCounts.ROUTE_22, 2,
  "regional navigation retains both Route 22 return doors")
S.eq(transitionCounts.ROUTE_23, 2,
  "regional navigation can cross both Route 23 onward doors")

setWorld("ROUTE_23", 8, 138)
local route23Snapshot = assert(access:captureWorld("objects"))
S.eq(#route23Snapshot.browse, 7,
  "Route 23 exposes all seven remaining badge-check guards and swimmers")

setWorld("SAFARI_ZONE_WEST", 29, 22)
local target = {
  targetMapId = "SAFARI_ZONE_WEST",
  targetGoals = { { x = 3, y = 3 } },
}

local currentMap = "SAFARI_ZONE_WEST"
local visited, finalLeg, finalReason = {}, nil, nil
for index = 1, 8 do
  local leg, reason = access:regionalNextLeg(target)
  S.check(leg ~= nil, "Safari dry journey leg " .. index .. " exists: "
    .. tostring(reason))
  if not leg then break end
  if leg.final then
    finalLeg, finalReason = leg, reason
    break
  end
  S.check(leg.nextMapId ~= nil,
    "Safari dry journey leg " .. index .. " chooses a map transition")
  visited[#visited + 1] = leg.nextMapId
  local mapId, x, y = arrivalFor(currentMap, leg)
  S.check(mapId ~= nil, "Safari leg " .. index .. " resolves a real warp")
  if not mapId then break end
  setWorld(mapId, x, y)
  currentMap = mapId
end

S.check(finalLeg ~= nil, "upper West can finish the Secret House route: "
  .. tostring(finalReason))
S.check(finalLeg and finalLeg.final == true,
  "regional journey hands the reachable final leg back to local navigation")
S.same(finalLeg and finalLeg.goals, { { x = 3, y = 3 } },
  "the final leg retains the selected Secret House entrance")
S.same(visited, { "SAFARI_ZONE_NORTH", "SAFARI_ZONE_WEST" },
  "from lower West the shortest proven dry journey leaves through North and re-enters upper West")

setWorld("SAFARI_ZONE_WEST", 29, 22)
local teethLeg = access:regionalNextLeg({
  targetMapId = "SAFARI_ZONE_WEST",
  targetGoals = {
    { x = 19, y = 6 }, { x = 20, y = 7 },
    { x = 19, y = 8 }, { x = 18, y = 7 },
  },
})
S.eq(teethLeg and teethLeg.nextMapId, "SAFARI_ZONE_NORTH",
  "Gold Teeth use the same dry regional journey instead of requiring Surf")

local restLeg = access:regionalNextLeg({
  targetMapId = "SAFARI_ZONE_WEST",
  targetGoals = { { x = 11, y = 11 } },
})
S.check(restLeg ~= nil,
  "West Rest House produces either a proven local or regional dry leg")

local speechBeforeLiveRoute = #speechCalls
local started = access:startWorldRoute(target.targetGoals, nil, "selected", {
  mapId = target.targetMapId, goals = target.targetGoals,
})
S.check(started == true, "live selected-target command starts the Safari route")
for _ = 1, 128 do
  if not access.pendingRoute then break end
  access:updatePendingRoute()
end
S.check(access.activeNavigation and access.activeNavigation.journey == true,
  "local failure promotes the live navigation session to a regional journey")
S.eq(access.activeNavigation and access.activeNavigation.nextMapId,
  "SAFARI_ZONE_NORTH",
  "the live route directs lower West toward its proven dry North exit")
local sawSurfRequirement, sawDirection = false, false
for index = speechBeforeLiveRoute + 1, #speechCalls do
  local text = speechCalls[index].text or ""
  if text == "Needs Surf" then sawSurfRequirement = true end
  if text:match("^%d+ %a+$") then sawDirection = true end
end
S.check(not sawSurfRequirement,
  "the live Secret House route never invents a Surf prerequisite")
S.check(sawDirection,
  "the live Secret House journey starts with an actionable dry direction")

local function settleRoute()
  for _ = 1, 128 do
    if not access.pendingRoute then break end
    access:updatePendingRoute()
  end
end

local northMap, northX, northY = arrivalFor("SAFARI_ZONE_WEST", {
  goals = access.activeNavigation.goals,
  nextMapId = access.activeNavigation.nextMapId,
})
setWorld(northMap, northX, northY)
events:emit("map.entered", { mapId = northMap, via = "warp" })
access:processWorldEvents(game.overworld)
settleRoute()
S.eq(access.activeNavigation and access.activeNavigation.nextMapId,
  "SAFARI_ZONE_WEST",
  "the continuous journey survives North entry and chooses upper West")

local upperWestMap, upperWestX, upperWestY = arrivalFor(northMap, {
  goals = access.activeNavigation.goals,
  nextMapId = access.activeNavigation.nextMapId,
})
setWorld(upperWestMap, upperWestX, upperWestY)
events:emit("map.entered", { mapId = upperWestMap, via = "warp" })
access:processWorldEvents(game.overworld)
settleRoute()
S.check(access.activeNavigation
        and access.activeNavigation.currentLegFinal == true,
  "upper West entry automatically resumes the final Secret House leg")
S.eq(access.activeNavigation and access.activeNavigation.nextMapId, nil,
  "the final local leg no longer expects an intermediate map")

setWorld("CELADON_CITY", 39, 20)
local celadonMainRoute = access:regionalDryRoute(
  "CELADON_CITY", { x = 39, y = 20 },
  { { x = 8, y = 13 }, { x = 10, y = 13 } }, true)
S.check(celadonMainRoute ~= nil and celadonMainRoute.cost > 0,
  "Celadon Department Store main entrance has a proven dry walking route from the fifth-floor doorway")

access:stopNavigation(false)
setWorld("SAFFRON_CITY", 18, 23)
local saffronWorld = game.overworld
-- At this story stage Rocket3 occupies the Gym doorway's sole geometric
-- approach. Keep this fixture independent of event-script visibility details.
saffronWorld.entities = {
  saffronWorld.player,
  { cellX = 34, cellY = 4, def = { name = "Rocket3" } },
}
saffronWorld.npcs = saffronWorld.entities
local saffronTarget = {
  mapId = "SAFFRON_CITY", type = "warp",
  goals = { { x = 34, y = 3 } },
}
S.check(access:blockedWarpEntrance({
  targetMapId = saffronTarget.mapId,
  targetType = saffronTarget.type,
  targetGoals = saffronTarget.goals,
}), "Saffron Gym recognizes the live Rocket as a sealed entrance")
local speechBeforeSaffron = #speechCalls
S.check(access:startWorldRoute(
  saffronTarget.goals, nil, "selected", saffronTarget),
  "Saffron Gym route request completes normally")
settleRoute()
S.eq(speechCalls[#speechCalls] and speechCalls[#speechCalls].text,
  "Entrance is currently blocked",
  "story-blocked Saffron Gym stops before regional graph exploration")
S.check(#speechCalls > speechBeforeSaffron,
  "story-blocked entrance gives immediate useful speech")
S.eq(access.activeNavigation, nil,
  "blocked entrance does not leave stale continuous navigation active")

local silphDoorCount = 0
for _, mapId in ipairs(data.field.cardKeyDoors.maps) do
  local world = setClosedSilphWorld(mapId, 0, 0)
  local doors = {}
  for _, object in ipairs(access:interactiveBrowseObjects(world)) do
    if object.semanticKind == "card_key_door" then
      doors[#doors + 1] = object
    end
  end
  local expected = #(data.field.cardKeyDoors.closedDoors[mapId] or {})
  S.eq(#doors, expected, mapId .. " exposes every independently locked door")
  silphDoorCount = silphDoorCount + #doors
end
S.eq(silphDoorCount, 20,
  "the navigation list covers all twenty Silph card-key gates")

game.save.inventory = {}
local silph2F = setClosedSilphWorld("SILPH_CO_2F", 3, 4)
local lockedDoors = {}
for _, object in ipairs(access:interactiveBrowseObjects(silph2F)) do
  if object.semanticKind == "card_key_door" then
    lockedDoors[#lockedDoors + 1] = object
  end
end
S.eq(lockedDoors[1] and lockedDoors[1].label, "Closed Door 1",
  "multiple doors receive stable disambiguating numbers")
S.eq(lockedDoors[1] and lockedDoors[1].requirement, "Needs Card Key",
  "a closed-door entry explains the missing key")
local doorBrowse = access:captureWorld("objects")
local browsedDoor
for _, object in ipairs(doorBrowse and doorBrowse.browse or {}) do
  if object.semanticKind == "card_key_door" then browsedDoor = object break end
end
S.check(browsedDoor and browsedDoor.description:find(
  "Needs Card Key", 1, true) ~= nil,
  "cycling the object list speaks the missing Card Key requirement")
local noKeyOptions = access:worldRouteRequest({ { x = 6, y = 4 } }, 2)
S.check(not noKeyOptions.canTraverse(3, 4, 4, 4, "right"),
  "available-item routing cannot cross a locked door without the Card Key")
local hypotheticalOptions = access:worldRouteRequest({ { x = 6, y = 4 } }, 3)
S.check(hypotheticalOptions.canTraverse(3, 4, 4, 4, "right"),
  "hypothetical routing can diagnose a Card Key requirement")
local cardRequirements = access:routeRequirements(silph2F, {
  steps = { { fromX = 3, fromY = 4, x = 4, y = 4,
              direction = "right" } },
})
S.check(cardRequirements.CARD_KEY == true,
  "a hypothetical route through the door records Needs Card Key")

game.save.inventory.CARD_KEY = 1
S.check(access:hasCardKey(), "Card Key inventory detection sees the owned key")
local keyedDoors = access:interactiveBrowseObjects(silph2F)
local keyedDoor
for _, object in ipairs(keyedDoors) do
  if object.semanticKind == "card_key_door" then keyedDoor = object break end
end
S.eq(keyedDoor and keyedDoor.requirement, nil,
  "the requirement disappears when the player owns the Card Key")
local goals, instructions = access:interactionGoals(silph2F, {
  type = "object", x = keyedDoor.x, y = keyedDoor.y,
  interaction = keyedDoor.interaction,
  interactionCells = keyedDoor.interactionCells,
})
S.check(#goals > 0, "a closed door has at least one reachable interaction side")
local sawCardKeyInstruction = false
for _, instruction in pairs(instructions) do
  if instruction:find("use Card Key", 1, true) then
    sawCardKeyInstruction = true
  end
end
S.check(sawCardKeyInstruction,
  "door navigation tells the player to face it and use the Card Key")
local keyedOptions = access:worldRouteRequest({ { x = 6, y = 4 } }, 2)
S.check(keyedOptions.canTraverse(3, 4, 4, 4, "right"),
  "available-item routing crosses a locked tile when the key is owned")
-- Test north-to-south through the actual shutter. The cell immediately east
-- of this gate is an ordinary wall, so forcing an eastward route would test
-- the false-positive bug instead of Card Key traversal.
silph2F.player.cellX, silph2F.player.cellY = 4, 3
local keyedGoal = { { x = 4, y = 5 } }
local walkingOptions = access:worldRouteRequest(keyedGoal, 1)
keyedOptions = access:worldRouteRequest(keyedGoal, 2)
local walkingResult = Pathfinder.find(walkingOptions)
local keyedResult = Pathfinder.find(keyedOptions)
S.check(walkingResult == nil and keyedResult ~= nil,
  "the Silph corridor target specifically requires the owned Card Key")
local regionalCalls = 0
local realRegionalNextLeg = access.regionalNextLeg
access.regionalNextLeg = function(self, navigation)
  regionalCalls = regionalCalls + 1
  return realRegionalNextLeg(self, navigation)
end
access:stopNavigation(false)
S.check(access:startWorldRoute(keyedGoal, nil, "selected", {
  mapId = "SILPH_CO_2F", goals = keyedGoal, type = "object",
}), "live Silph target starts through the owned Card Key gate")
settleRoute()
S.eq(regionalCalls, 0,
  "owned Card Key routing completes before any regional teleport search")
access.regionalNextLeg = realRegionalNextLeg
local narration = access:routeNarration(silph2F, {
  cost = 2,
  steps = { { fromX = 3, fromY = 4, x = 4, y = 4,
              direction = "right" },
            { fromX = 4, fromY = 4, x = 5, y = 4,
              direction = "right" } },
}, 2)
S.same(narration, { "Use Card Key facing right", "2 right" },
  "a two-cell gate speaks one key action and preserves all movement")
local opened = data.field.cardKeyDoors.closedDoors.SILPH_CO_2F[1]
silph2F.map:setBlock(opened.bx, opened.by, opened.open)
local remainingDoors = 0
for _, object in ipairs(access:interactiveBrowseObjects(silph2F)) do
  if object.semanticKind == "card_key_door" then
    remainingDoors = remainingDoors + 1
  end
end
S.eq(remainingDoors, 1,
  "opening one gate removes only that door from the live navigation list")

access:shutdown()
-- Stepping off the route must be audible.
--
-- continuousDirectiveKey strips the step count so a leg announced as "three
-- up" does not count down at the player. That same key silences a *recomputed*
-- route whose leading directive points the same way, so deviating off a long
-- corridor left the player with no new directions at all -- reported from live
-- play as "it recalculates but only tells you whether a route exists".
local Access = require("src.access.nav.Navigation")
local deviationProbe = setmetatable({}, { __index = Access })

local function navAt(key, x, y)
  return { lastDirectiveKey = key, lastSeenCell = { x = x, y = y } }
end
local function worldAt(x, y)
  return { player = { cellX = x, cellY = y } }
end

-- Walking the announced direction is not a deviation: the key survives, so the
-- remaining steps of the leg stay quiet.
local walking = navAt("move:up", 5, 9)
S.check(Access.noteRouteDeviation(deviationProbe, walking, worldAt(5, 8)) == false,
  "walking the announced direction is not treated as leaving the route")
S.eq(walking.lastDirectiveKey, "move:up",
  "walking the announced direction keeps the leg coalesced")

-- Stepping sideways off that corridor is a deviation, even though a recomputed
-- route would still lead with "up" and would otherwise be suppressed.
local sidestep = navAt("move:up", 5, 9)
S.check(Access.noteRouteDeviation(deviationProbe, sidestep, worldAt(4, 9)) == true,
  "a step across the announced direction is a deviation")
S.eq(sidestep.lastDirectiveKey, nil,
  "deviating clears the suppression key so the new path is spoken")

-- Reversing back down the corridor is also a deviation.
local backtrack = navAt("move:up", 5, 9)
S.check(Access.noteRouteDeviation(deviationProbe, backtrack, worldAt(5, 10)) == true,
  "reversing along the announced axis is a deviation")

-- Standing still is not a deviation, so a stationary refresh cannot force the
-- directive to repeat.
local still = navAt("move:up", 5, 9)
S.check(Access.noteRouteDeviation(deviationProbe, still, worldAt(5, 9)) == false,
  "standing still never counts as leaving the route")
S.eq(still.lastDirectiveKey, "move:up",
  "standing still keeps the directive suppressed")

-- The first observation of a route has nothing to compare against.
local fresh = { lastDirectiveKey = "move:up" }
S.check(Access.noteRouteDeviation(deviationProbe, fresh, worldAt(3, 3)) == false,
  "the first observed cell cannot be a deviation")
S.same({ fresh.lastSeenCell.x, fresh.lastSeenCell.y }, { 3, 3 },
  "the first observation records the cell for the next comparison")

-- CORRECTED 2026-08-27.  This block used to assert that a Cut or Surf directive
-- "has no movement direction to compare" and must keep its key through any
-- movement.  That premise is wrong: `cut:up` names a direction, and the text it
-- comes from is "Use Cut facing up, THEN MOVE UP".  A player who walks left
-- after it has left the route, and off-route correction is exactly what should
-- fire.  Because only `^move:` was read, correction could not fire for ANY
-- directive except a plain move or "Exit water" -- every ledge, ice, Surf, Cut,
-- Whirlpool and Waterfall directive was uncorrectable.
local cut = navAt("cut:up", 5, 9)
S.check(Access.noteRouteDeviation(deviationProbe, cut, worldAt(4, 9)) == true,
  "walking left after a Cut directive that said up is a deviation")
S.eq(cut.lastDirectiveKey, nil,
  "and the stale directive is cleared so the route is re-announced")

-- Moving the way the directive said is NOT a deviation.
local cutRight = navAt("cut:up", 5, 9)
S.check(Access.noteRouteDeviation(deviationProbe, cutRight, worldAt(5, 8)) == false,
  "moving up after a Cut directive that said up is not")
S.eq(cutRight.lastDirectiveKey, "cut:up", "so the directive stands")

-- An instruction with no extractable direction still has to be left alone --
-- narrowing the guard must not become removing it.
local opaque = navAt("instruction:Arrived at the counter", 5, 9)
S.check(Access.noteRouteDeviation(deviationProbe, opaque, worldAt(4, 9)) == false,
  "a directive with genuinely no direction is still left alone")
S.eq(opaque.lastDirectiveKey, "instruction:Arrived at the counter",
  "and keeps its key")

-- A CURRENT is deliberately excluded.  "Move up into current" names the step,
-- but the current then carries the player along its own axis, so net
-- displacement can be perpendicular to the instruction.  Comparing them would
-- invent a deviation.
local carried = navAt("instruction:Move up into current; carried to x 9, y 4", 5, 9)
S.check(Access.noteRouteDeviation(deviationProbe, carried, worldAt(9, 4)) == false,
  "being carried sideways by a current is not a deviation")
S.eq(carried.lastDirectiveKey,
  "instruction:Move up into current; carried to x 9, y 4",
  "and the current directive keeps its key")

-- A word in the right position is not automatically a direction.  Without the
-- cardinal guard, a mod's instruction that happens to fit the pattern shape
-- would yield a "direction" that can never equal the observed one, so EVERY
-- movement after it would be reported as a deviation and the route would be
-- re-announced on every step.
local oddWording = navAt("instruction:Move sideways onto ice", 5, 9)
S.check(Access.noteRouteDeviation(deviationProbe, oddWording, worldAt(4, 9)) == false,
  "a non-cardinal word in the direction slot is not treated as a direction")
S.eq(oddWording.lastDirectiveKey, "instruction:Move sideways onto ice",
  "and the directive is left alone rather than cleared every step")

-- An ice slide DOES keep its direction, so it is compared.
local slid = navAt("instruction:Move up onto ice; slide 3 cells", 5, 9)
S.check(Access.noteRouteDeviation(deviationProbe, slid, worldAt(5, 6)) == false,
  "sliding up the way the ice directive said is not a deviation")
local slidWrong = navAt("instruction:Move up onto ice; slide 3 cells", 5, 9)
S.check(Access.noteRouteDeviation(deviationProbe, slidWrong, worldAt(2, 9)) == true,
  "but walking off sideways instead of taking the slide is")

S.finish()
