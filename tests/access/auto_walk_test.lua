-- Auto-walk (decision 23): holds each route step's direction on the game's
-- input as its own source, announces arrival, and stops when blocked, off
-- the route, or when a screen opens.  Fake game, coordinator and pathfinder.
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

package.loaded["src.access.nav.Pathfinder"] = {
  find = function() return {
    steps = { { fromX = 0, fromY = 0, x = 1, y = 0, direction = "right" },
              { fromX = 1, fromY = 0, x = 1, y = 1, direction = "down" } },
    goal = { x = 1, y = 1 } } end,
}
local AutoWalk = require("src.access.nav.AutoWalk")

local function setup()
  AutoWalk._resetForTests()
  for i = #spoken, 1, -1 do spoken[i] = nil end
  local map = {}
  local overworld = { map = map, player = { cellX = 0, cellY = 0, moving = false } }
  local game = { input = { sources = {}, pressQueue = {}, state = {} } }
  local nav = {
    selectedRouteGoals = function() return { label = "PC" }, { { x = 1, y = 1 } },
      { ["1,1"] = "Face up and interact" }, nil, overworld end,
    worldRouteRequest = function() return {} end,
  }
  return game, overworld, nav
end

local game, overworld, nav = setup()
check(AutoWalk.start(nav, game), "auto-walk starts")
eq(spoken[#spoken], "Walking to PC", "start is announced")
AutoWalk.update(overworld)
eq(game.input.state.right, true, "first step holds right")
eq(game.input.sources.right.access_autowalk, true, "held as its own input source")
overworld.player.cellX = 1
AutoWalk.update(overworld)
eq(game.input.state.right, false, "right released after the step")
eq(game.input.state.down, true, "next step holds down")
overworld.player.cellY = 1
AutoWalk.update(overworld)
eq(spoken[#spoken], "Arrived at PC. Face up and interact", "arrival with the interaction hint")
check(not AutoWalk.active(), "walk ends on arrival")
eq(game.input.state.down, false, "direction released on arrival")

-- A non-battle screen (a card-key door message, a script) pauses the walk;
-- it resumes when the map returns.
local fakeStack = { states = {} }
package.loaded["src.core.StateStack"] = fakeStack
local BattleState = {}
package.loaded["src.battle.BattleState"] = BattleState
game, overworld, nav = setup()
AutoWalk.start(nav, game)
AutoWalk.update(overworld)
local sign = { sign = true }
AutoWalk.update(sign)
check(AutoWalk.active() and not AutoWalk.walking(), "a screen opening pauses the walk")
eq(game.input.state.right, false, "pausing releases the direction")
AutoWalk.update(overworld)
eq(spoken[#spoken], "Resuming walk to PC", "back on the map after any interruption: resumes")

-- A battle pauses the walk and it resumes afterwards.
game, overworld, nav = setup()
AutoWalk.start(nav, game)
AutoWalk.update(overworld)
local battle = setmetatable({}, BattleState)
fakeStack.states = { overworld, battle }
AutoWalk.update(battle)
check(not AutoWalk.walking(), "battle pauses the walk")
fakeStack.states = { overworld }
AutoWalk.update(overworld)
eq(spoken[#spoken], "Resuming walk to PC", "walk resumes after the battle")
check(AutoWalk.walking(), "walking again")
AutoWalk.update(overworld)
eq(game.input.state.right, true, "resumed walk holds the next direction")

-- A trainer engagement pauses before any screen opens and waits for the battle.
game, overworld, nav = setup()
AutoWalk.start(nav, game)
AutoWalk.pause(true)
fakeStack.states = { overworld }
for _ = 1, 120 do AutoWalk.update(overworld) end
check(AutoWalk.active() and not AutoWalk.walking(), "still paused while the trainer walks over")
fakeStack.states = { overworld, battle }
AutoWalk.update(battle)
fakeStack.states = { overworld }
AutoWalk.update(overworld)
eq(spoken[#spoken], "Resuming walk to PC", "resumes after the trainer battle")
fakeStack.states = {}

-- A scene that turns the player back to the same cell every time (Ecruteak's
-- Tin Tower sages): resume twice, then stop instead of walking into it for ever.
game, overworld, nav = setup()
AutoWalk.start(nav, game)
local scene = { scene = true }
for round = 1, 3 do
  AutoWalk.update(overworld)
  AutoWalk.update(scene)
  overworld.player.cellX, overworld.player.cellY = 0, 0 -- stepped back by the scene
  AutoWalk.update(overworld)
  if round < 3 then eq(spoken[#spoken], "Resuming walk to PC", "turned back " .. round .. ": resumes") end
end
eq(spoken[#spoken], "Turned back again, auto walk stopped", "turned back a third time at the same cell: stops")
check(not AutoWalk.active(), "and the walk is over")
game, overworld, nav = setup()
AutoWalk.start(nav, game)
for round = 1, 3 do
  AutoWalk.update(overworld)
  AutoWalk.update(scene)
  overworld.player.cellX = round -- each interruption somewhere new (trainers along the way)
  AutoWalk.update(overworld)
end
check(AutoWalk.active(), "interruptions at different cells never stop the walk")
AutoWalk.stop()

-- A field move on the route (Gen 2): turn to face it, flagged as turning so
-- the game runs that frame at 1X (a fast frame's worth of a held direction
-- stepped onto a waterfall's bottom cell instead of turning), then press A.
game, overworld, nav = setup()
nav.stepInteraction = function(_, _, step)
  if step.direction == "down" then
    return { move = "Waterfall", failText = "Could not use Waterfall", hint = "Use Waterfall facing down" }
  end
end
overworld.player.facing = "right"
AutoWalk.start(nav, game)
AutoWalk.update(overworld)
check(not AutoWalk.turning(), "an ordinary step is not a turn")
overworld.player.cellX = 1
AutoWalk.update(overworld)
check(AutoWalk.turning(), "facing the wrong way at a field move: turning")
eq(game.input.state.down, true, "holding the direction to turn")
overworld.player.facing = "down"
AutoWalk.update(overworld)
check(not AutoWalk.turning(), "facing it: no longer turning")
eq(game.input.state.a, true, "and A is pressed for the move")
AutoWalk.stop()

game, overworld, nav = setup()
AutoWalk.start(nav, game)
for _ = 1, 95 do AutoWalk.update(overworld) end
eq(spoken[#spoken], "Blocked, auto walk stopped", "no progress stops the walk")
eq(game.input.state.right, false, "blocked walk releases the direction")

game, overworld, nav = setup()
AutoWalk.start(nav, game)
overworld.player.cellX, overworld.player.cellY = 5, 5
for _ = 1, 10 do AutoWalk.update(overworld) end
eq(spoken[#spoken], "Off the route, auto walk stopped", "re-plans a few times, then stops when still off the route")

game, overworld, nav = setup()
AutoWalk.start(nav, game)
check(AutoWalk.stop("Auto walk stopped"), "manual stop")
check(not AutoWalk.active(), "inactive after stop")

-- Journey to an Area target on another map: walk a leg, take the door,
-- plan the next map's leg, arrive.
game, overworld, nav = setup()
local legs = 0
nav.selectedRouteGoals = function()
  return { label = "Gold Teeth, Safari Zone West", type = "area", mapId = "WEST" },
    { { x = 1, y = 1 } }, nil, nil, overworld
end
nav.regionalNextLeg = function(_, journey)
  legs = legs + 1
  eq(journey.targetMapId, "WEST", "journey targets the item's map")
  return { goals = { { x = 1, y = 1 } }, final = legs >= 2 }
end
check(AutoWalk.start(nav, game), "journey starts")
eq(spoken[#spoken], "Walking to Gold Teeth, Safari Zone West", "journey start announced")
AutoWalk.update(overworld)
overworld.map = { west = true }
overworld.player.cellX, overworld.player.cellY = 0, 0
AutoWalk.update(overworld)
check(AutoWalk.active(), "a new map mid-journey does not end the walk")
AutoWalk.update(overworld)
eq(legs, 2, "the next leg is planned on the new map")
overworld.player.cellX = 1
AutoWalk.update(overworld)
overworld.player.cellY = 1
AutoWalk.update(overworld)
eq(spoken[#spoken], "Arrived at Gold Teeth, Safari Zone West", "journey arrives on the final map")

Speech.shutdown()
T.finish()
