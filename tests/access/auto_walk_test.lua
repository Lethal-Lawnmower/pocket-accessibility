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

game, overworld, nav = setup()
AutoWalk.start(nav, game)
AutoWalk.update({ someMenu = true })
eq(spoken[#spoken], "Auto walk stopped", "a screen opening stops the walk")

game, overworld, nav = setup()
AutoWalk.start(nav, game)
for _ = 1, 95 do AutoWalk.update(overworld) end
eq(spoken[#spoken], "Blocked, auto walk stopped", "no progress stops the walk")
eq(game.input.state.right, false, "blocked walk releases the direction")

game, overworld, nav = setup()
AutoWalk.start(nav, game)
overworld.player.cellX, overworld.player.cellY = 5, 5
AutoWalk.update(overworld)
eq(spoken[#spoken], "Off the route, auto walk stopped", "leaving the route stops the walk")

game, overworld, nav = setup()
AutoWalk.start(nav, game)
check(AutoWalk.stop("Auto walk stopped"), "manual stop")
check(not AutoWalk.active(), "inactive after stop")

Speech.shutdown()
T.finish()
