-- Chase (src/access/nav/Chase.lua): an object that runs off when talked to,
-- followed from what is seen alone.  A fake world moves it by a table the
-- module never reads, including a wrong side that sends it back.
--
--   luajit tests/access/chase_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local passed, failed = 0, 0
local function check(ok, name)
  if ok then passed = passed + 1 else failed = failed + 1 print("FAIL " .. name) end
end

local said = {}
package.loaded["src.access.Speech"] = { say = function(text) said[#said + 1] = text end }
local walking = false
local world = { map = {}, player = { cellX = 0, cellY = 0, facing = "up" } }
local fakeWalk = {
  active = function() return walking end,
  stop = function() walking = false end,
  holdDirection = function(_, dir) world.player.facing = dir end,
  releaseDirection = function() end,
  start = function(_, _, _, opts)
    local goal = opts.goals[1]
    if goal.x == 99 then return false end -- a side no route reaches
    world.player.cellX, world.player.cellY = goal.x, goal.y
    return true
  end,
}
package.loaded["src.access.nav.AutoWalk"] = fakeWalk
local Chase = require("src.access.nav.Chase")

-- from each cell, the side (player's offset) that moves it, and where to
local MOVES = {
  ["10,10"] = { ["10,11"] = "20,10", ["9,10"] = "10,10" },
  ["20,10"] = { ["20,11"] = "10,10", ["21,10"] = "30,10" },
}
local bird = { id = "bird", label = "Bird", x = 10, y = 10, type = "object" }
local nav = {}
function nav.selectedRouteGoals()
  if not bird then return nil, "gone" end
  return bird, {
    { x = bird.x, y = bird.y + 1 }, { x = bird.x - 1, y = bird.y },
    { x = bird.x + 1, y = bird.y }, { x = bird.x, y = bird.y - 1 },
  }, nil, nil, world
end
local input = { state = {}, pressQueue = {} }
local game = { input = input }
local free = true
local adapter = { onMap = function() return free end }

local function run(frames)
  for _ = 1, frames do
    Chase.update()
    if input.state.a and #input.pressQueue > 0 then
      input.pressQueue = {}
      local key = world.player.cellX .. "," .. world.player.cellY
      local to = MOVES[bird.x .. "," .. bird.y]
      to = to and to[key]
      if to then
        local x, y = to:match("(%d+),(%d+)")
        bird.x, bird.y = tonumber(x), tonumber(y)
      end
    end
    if not Chase.active() then return true end
  end
  return false
end

Chase.start(nav, game, adapter, bird, world)
check(Chase.active(), "a chase starts")
check(run(20000), "a chase ends by itself")
check(bird.x == 30 and bird.y == 10, "it finds the way forward past a side that sends the object back")
check(said[#said]:find("stopped running", 1, true) ~= nil, "it says when the object has stopped running")

-- text the game opens is the player's: no frames count while it is up
bird.x, bird.y = 10, 10
Chase.start(nav, game, adapter, bird, world)
free = false
run(500)
check(Chase.active() and #input.pressQueue == 0, "nothing is pressed while a screen is open")
free = true
Chase.stop("Auto walk stopped")
check(not Chase.active(), "any key stops it")
check(said[#said] == "Auto walk stopped", "stopping says so")

-- the object disappears
bird.x, bird.y = 10, 10
Chase.start(nav, game, adapter, bird, world)
local kept = bird
bird = nil
check(run(100) and not Chase.active(), "an object that is gone ends the chase")
check(said[#said]:find("is gone", 1, true) ~= nil, "it says the object is gone")
bird = kept

print(("%d/%d checks passed  (chase)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
