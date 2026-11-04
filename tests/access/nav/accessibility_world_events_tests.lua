local T = require("tests.harness")
local S = T.suite("accessibility settled world events")
local Accessibility = require("src.access.nav.Navigation")

local function eventBus()
  local bus = { listeners = {} }
  function bus:on(name, callback)
    self.listeners[name] = self.listeners[name] or {}
    local list = self.listeners[name]
    list[#list + 1] = callback
    return function()
      for i, candidate in ipairs(list) do
        if candidate == callback then table.remove(list, i) break end
      end
    end
  end
  function bus:emit(name, event)
    for _, callback in ipairs(self.listeners[name] or {}) do callback(event) end
  end
  return bus
end

local speechCalls = {}
local speech = {}
function speech:isAvailable() return true end
function speech:output(text, opts)
  speechCalls[#speechCalls + 1] = { text = text,
    interrupt = opts and opts.interrupt == true }
  return true
end
function speech:stop() return true end

local cueCalls = {}
local earcons = {}
function earcons:setEnabled() end
function earcons:play(id)
  cueCalls[#cueCalls + 1] = id
  return true
end
function earcons:stop() return true end

local cells = { ["2,3"] = "grass", ["4,5"] = "water" }
local map = {
  id = "TEST_TOWN", widthCells = 10, heightCells = 10,
  def = { id = "TEST_TOWN", displayName = "Test Town", tileset = "TEST" },
}
function map:inBounds(x, y) return x >= 0 and y >= 0 and x < 10 and y < 10 end
function map:cellTile(x, y)
  if x == 2 and y == 3 then return 30 end
  if x == 2 and y == 4 then return 31 end
  return 1
end
function map:warpAtCell() return nil end
function map:signAtCell() return nil end
function map:isWarpTileCell() return false end
function map:isCounterCell() return false end
function map:isGrassCell(x, y) return cells[x .. "," .. y] == "grass" end
function map:isWaterCell(x, y) return cells[x .. "," .. y] == "water" end
function map:isWalkableCell() return true end

local overworld = {
  isOverworld = true,
  map = map,
  player = { cellX = 2, cellY = 3, facing = "down" },
}
local transition = { screenId = "Transition" }
local dialogue = { screenId = "TextBox" }
local stack = { current = overworld }
function stack:top() return self.current end
local bus = eventBus()
local game = {
  stack = stack,
  overworld = overworld,
  data = { field = { ledges = {
    { tileset = "TEST", standingTile = 30, ledgeTile = 31,
      facing = "down", input = "down" },
  } } },
}
local access = Accessibility.new(game, {
  speech = speech, earcons = earcons, events = bus, enabled = true,
  defaultDelayFrames = 0,
})

S.eq(speechCalls[1].text,
  "Screen reader ready. Press F7 for accessibility command mode. Press F8 for help.",
  "production-ready announcement remains intact")
bus:emit("world.stepped", { mapId = "TEST_TOWN", x = 2, y = 3, tile = 1 })
access:update()
S.eq(cueCalls[1], "grass", "a settled native grass step emits its terrain cue")
S.eq(cueCalls[2], "ledge",
  "an adjacent jumpable ledge layers its navigation warning")
S.same({ access.sonarMapId, access.sonarX, access.sonarY },
  { "TEST_TOWN", 2, 3 }, "follow-mode sonar cursor settles on the player")

bus:emit("world.stepped", { mapId = "TEST_TOWN", x = 4, y = 5, tile = 2 })
access:update()
S.eq(#cueCalls, 2, "a stale coordinate cannot emit a cue")

overworld.player.cellX, overworld.player.cellY = 4, 5
bus:emit("world.stepped", { mapId = "TEST_TOWN", x = 4, y = 5, tile = 1 })
stack.current = dialogue
access:update()
S.same({ access.sonarX, access.sonarY }, { 4, 5 },
  "suppressed audio still keeps follow-mode navigation state current")
stack.current = overworld
access:update()
S.eq(#cueCalls, 2,
  "a step that opens dialogue is discarded rather than replayed afterward")

overworld.player.cellX, overworld.player.cellY = 2, 3
bus:emit("world.stepped", { mapId = "TEST_TOWN", x = 2, y = 3, tile = 1 })
bus:emit("map.entered", { mapId = "TEST_TOWN", via = "warp" })
stack.current = transition
access:update()
S.eq(#speechCalls, 1, "map speech waits beneath a transition")
S.eq(#cueCalls, 2, "map entry supersedes the source-map step cue")
stack.current = overworld
access:update()
S.same(speechCalls[2], { text = "Test Town", interrupt = true },
  "the settled live map name replaces stale connection feedback")

map.id, map.def.id, map.def.displayName = "OTHER_MAP", "OTHER_MAP", "Other Map"
bus:emit("map.entered", { mapId = "STALE_MAP", via = "reload" })
access:update()
S.eq(#speechCalls, 2, "a superseded map event cannot name the wrong live map")

access:setSonarFollow(false)
access.sonarMapId, access.sonarX, access.sonarY = "OTHER_MAP", 8, 8
overworld.player.cellX, overworld.player.cellY = 4, 5
bus:emit("world.stepped", { mapId = "OTHER_MAP", x = 4, y = 5, tile = 1 })
access:update()
S.eq(cueCalls[#cueCalls], "water",
  "follow-off footsteps classify terrain at the player rather than the sonar")
S.same({ access.sonarMapId, access.sonarX, access.sonarY },
  { "OTHER_MAP", 8, 8 },
  "follow-off footsteps preserve the independent sonar position")

cells["5,5"] = "water"
overworld.player.facing = "right"
function overworld:useSurfFieldMove() return "ok" end
local beforeSurfCue, beforeSurfSpeech = #cueCalls, #speechCalls
bus:emit("world.bumped", {
  mapId = "OTHER_MAP", x = 4, y = 5, targetX = 5, targetY = 5,
  direction = "right", reason = "terrain",
})
access:update()
S.eq(cueCalls[beforeSurfCue + 1], "water",
  "pressing toward shoreline immediately plays the Pokemon Access water cue")
S.eq(speechCalls[beforeSurfSpeech + 1].text,
  "Water ahead. Surf is available from the party menu.",
  "usable Surf is explained at the exact native field-action boundary")
S.check(speechCalls[beforeSurfSpeech + 1].interrupt,
  "shoreline guidance replaces stale spatial feedback")
bus:emit("world.bumped", {
  mapId = "OTHER_MAP", x = 4, y = 5, targetX = 5, targetY = 5,
  direction = "right", reason = "terrain",
})
access:update()
S.same({ #cueCalls, #speechCalls },
  { beforeSurfCue + 1, beforeSurfSpeech + 1 },
  "holding into one shoreline does not repeat its cue or instruction")

cells["3,5"] = "water"
overworld.player.facing = "left"
function overworld:useSurfFieldMove() return "no_badge" end
bus:emit("world.bumped", {
  mapId = "OTHER_MAP", x = 4, y = 5, targetX = 3, targetY = 5,
  direction = "left", reason = "terrain",
})
access:update()
S.eq(cueCalls[#cueCalls], "water",
  "shoreline is still identifiable when Surf is not yet usable")
S.eq(speechCalls[#speechCalls].text, "Water ahead.",
  "unusable Surf still identifies the shoreline without false advice")
S.check(speechCalls[#speechCalls].interrupt,
  "a rejected shoreline probe remains transient feedback")

local speechBeforeBumps = #speechCalls
overworld.player.facing = "up"
bus:emit("world.bumped", {
  mapId = "OTHER_MAP", x = 4, y = 5, targetX = 4, targetY = -1,
  direction = "up", reason = "bounds",
})
access:update()
S.eq(speechCalls[speechBeforeBumps + 1].text, "Map edge.",
  "a native bounds verdict is spoken without inspecting pixels")
S.check(speechCalls[speechBeforeBumps + 1].interrupt,
  "rapid map-edge probes cannot queue stale directions")

cells["5,5"] = nil
overworld.entities = {
  { cellX = 5, cellY = 5, def = { name = "OTHER_MAP_NURSE", index = 1 } },
}
overworld.player.facing = "right"
bus:emit("world.bumped", {
  mapId = "OTHER_MAP", x = 4, y = 5, targetX = 5, targetY = 5,
  direction = "right", reason = "entity",
})
access:update()
S.eq(speechCalls[speechBeforeBumps + 2].text, "Nurse ahead.",
  "an entity collision names the live blocking actor")
S.check(speechCalls[speechBeforeBumps + 2].interrupt,
  "rapid entity probes replace older spatial feedback")

overworld.entities = nil
overworld.player.facing = "down"
bus:emit("world.bumped", {
  mapId = "OTHER_MAP", x = 4, y = 5, targetX = 4, targetY = 6,
  direction = "down", reason = "tile",
})
access:update()
S.eq(speechCalls[speechBeforeBumps + 3].text, "Wall ahead.",
  "an otherwise generic tile collision has a stable fallback")
S.check(speechCalls[speechBeforeBumps + 3].interrupt,
  "rapid wall probes replace older spatial feedback")

game.save = { player = { name = "Alex" } }
map.id, map.def.id, map.def.displayName =
  "REDS_HOUSE_2F", "REDS_HOUSE_2F", nil
bus:emit("map.entered", { mapId = "REDS_HOUSE_2F", via = "reload" })
access:update()
S.eq(speechCalls[#speechCalls].text, "Alex's House 2F",
  "the settled live announcement uses the chosen player name")
S.check(speechCalls[#speechCalls].interrupt,
  "a new map location supersedes the map or connection just left")

-- Engine-driven movement emits no world.stepped: OverworldController calls
-- onStepComplete only for unscripted steps, so a spinner slide, a Seafoam
-- current, a cutscene escort and the forced-bike bounce all relocate the
-- player silently. Follow mode has to track the player, not the event.
access:setSonarFollow(true)
overworld.player.cellX, overworld.player.cellY = 4, 5
bus:emit("world.stepped", { mapId = "REDS_HOUSE_2F", x = 4, y = 5, tile = 1 })
access:update()
S.same({ access.sonarX, access.sonarY }, { 4, 5 },
  "an ordinary step still anchors the follow-mode sonar")
-- the slide: several cells, no event
overworld.player.cellX, overworld.player.cellY = 4, 9
access:update()
S.same({ access.sonarMapId, access.sonarX, access.sonarY },
  { "REDS_HOUSE_2F", 4, 9 },
  "scripted movement with no step event still carries the sonar along")

-- A deliberate displacement must survive: the player has not moved, so there
-- is nothing to follow.
access.sonarX, access.sonarY = 7, 9
access:update()
S.same({ access.sonarX, access.sonarY }, { 7, 9 },
  "a sonar moved with D, G, R or V is not snapped back to a stationary player")
overworld.player.cellX = 5
access:update()
S.same({ access.sonarX, access.sonarY }, { 5, 9 },
  "the next player movement re-anchors the displaced sonar")

access:setSonarFollow(false)
overworld.player.cellY = 8
access:update()
S.same({ access.sonarX, access.sonarY }, { 5, 9 },
  "follow-off keeps the independent sonar through scripted movement too")
access:setSonarFollow(true)
access:update()

local beforeShutdown = #(bus.listeners["world.stepped"] or {})
local cuesAtShutdown = #cueCalls
access:shutdown()
local afterShutdown = #(bus.listeners["world.stepped"] or {})
S.check(beforeShutdown == 1 and afterShutdown == 0,
  "shutdown removes first-party world subscriptions deterministically")
bus:emit("world.stepped", { mapId = "OTHER_MAP", x = 2, y = 3 })
S.eq(#cueCalls, cuesAtShutdown,
  "retired subscriptions cannot emit after shutdown")

local malformedAccess = Accessibility.new({ data = game.data }, {
  speech = speech, earcons = earcons, events = eventBus(), enabled = false,
})
S.check(not malformedAccess:hasAdjacentLedge({
  player = { cellX = 0, cellY = 0 },
  map = { cellTile = function() return 30 end },
}), "a malformed mod map without def or inBounds cannot crash ledge detection")
local boundsFailure = {
  def = { tileset = "TEST" },
  cellTile = function() return 30 end,
  inBounds = function() error("broken mod bounds callback") end,
}
S.check(not malformedAccess:hasAdjacentLedge({
  player = { cellX = 0, cellY = 0 }, map = boundsFailure,
}), "a mod bounds exception is contained at the accessibility boundary")
malformedAccess:shutdown()

S.finish()
