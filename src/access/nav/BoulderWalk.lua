-- Auto-walk's boulder pushing (owner request, 2026-11-03): when Strength
-- boulders are all that stands between the player and the selected object,
-- walk to each pushing cell, switch Strength on the way the player does (A at
-- a boulder, then YES) and push, planning again after every push.  The plan is
-- a search over the floor (Navigation:boulderOpening), with nothing about any
-- map written here.  AUTO-WALK BOULDERS in the Accessibility page turns it off.

local Speech = require("src.access.Speech")

local BoulderWalk = {}

local MAX_PUSHES = 40
local PUSH_FRAMES = 150
local PROMPT_FRAMES = 1500
local PROMPT_GAP = 30

local run = nil

function BoulderWalk.active() return run ~= nil end

local function autoWalk() return require("src.access.nav.AutoWalk") end

local function nativeWorld()
  return run.overworld.native or run.overworld
end

function BoulderWalk.stop(reason)
  if not run then return false end
  local input = run.game.input
  autoWalk().releaseDirection(input, run.held)
  input.state.a = false
  run = nil
  autoWalk().stop()
  if reason then Speech.say(reason, { interrupt = true }) end
  return true
end

-- Starts when boulders are the only thing in the way.  False leaves the caller's
-- "No route" to be said.
function BoulderWalk.tryStart(nav, game, adapter, item, goals, overworld)
  if type(nav.boulderOpening) ~= "function" or type(goals) ~= "table" then return false end
  if not require("src.access.Settings").autoWalkBoulders(game) then return false end
  local plan, _, needs = nav:boulderOpening(overworld, goals)
  if not plan then return false end
  -- "Use Strength from the party menu" is what this does itself
  if needs and needs ~= "" and not needs:find("party menu", 1, true) then
    Speech.say("Boulders block the way. " .. needs:gsub(";%s*$", ""), { interrupt = true })
    return true
  end
  run = { nav = nav, game = game, adapter = adapter, overworld = overworld, map = overworld.map,
    id = item.id, label = item.label, pushes = 0, phase = "choose" }
  Speech.say("Pushing boulders to reach " .. tostring(item.label), { interrupt = true })
  return true
end

local function press()
  table.insert(run.game.input.pressQueue, "a")
  run.game.input.state.a = true
  run.tapped = true
end

local function choose()
  local ok, item, goals = pcall(run.nav.selectedRouteGoals, run.nav)
  if not (ok and type(item) == "table" and item.id == run.id) then
    return BoulderWalk.stop(tostring(run.label) .. " is gone, auto walk stopped")
  end
  local plan, reason = run.nav:boulderOpening(run.overworld, goals)
  if not plan then
    local nav, game, adapter = run.nav, run.game, run.adapter
    run = nil
    if reason == "open" then return autoWalk().start(nav, game, adapter) end
    Speech.say("Could not find a way to push the boulders, auto walk stopped", { interrupt = true })
    return
  end
  if run.pushes >= MAX_PUSHES then
    return BoulderWalk.stop("Still pushing boulders after many tries, auto walk stopped")
  end
  run.plan = plan
  local player = run.overworld.player
  if player.cellX == plan.standX and player.cellY == plan.standY then
    run.phase = "face"
    return
  end
  run.phase = "walking"
  autoWalk().start(run.nav, run.game, run.adapter,
    { goals = { { x = plan.standX, y = plan.standY } }, quiet = true })
end

-- Per frame, after AutoWalk.update.
function BoulderWalk.update()
  if not run then return end
  local AutoWalk = autoWalk()
  if AutoWalk.active() then return end
  local input = run.game.input
  if run.tapped then
    input.state.a = false
    run.tapped = nil
  end
  local onMap = run.adapter.onMap(run.game)
  if run.phase == "strength" then
    -- the game's own question: A through its text, YES is the first answer
    run.waited = run.waited + 1
    if run.waited > PROMPT_FRAMES then
      return BoulderWalk.stop("Could not use Strength, auto walk stopped")
    end
    if nativeWorld().strengthActive and onMap then
      run.phase = "face"
    elseif onMap and run.waited > PROMPT_GAP * 2 then
      return BoulderWalk.stop("Could not use Strength, auto walk stopped")
    elseif run.waited % PROMPT_GAP == 0 then
      press()
    end
    return
  end
  if not onMap then return end
  if run.overworld.map ~= run.map then
    return BoulderWalk.stop("Left the map, auto walk stopped")
  end
  local player = run.overworld.player
  if run.phase == "choose" then return choose() end
  local plan = run.plan
  if run.phase == "walking" then
    if player.cellX == plan.standX and player.cellY == plan.standY then
      run.phase = "face"
    else
      return BoulderWalk.stop("Could not reach the boulder, auto walk stopped")
    end
    return
  end
  if run.phase == "face" then
    if player.moving then return end
    if player.facing ~= plan.direction then
      -- with Strength off this only turns; with it on, a turn into the boulder
      -- would push, which is the push planned here anyway
      if run.held ~= plan.direction then
        AutoWalk.releaseDirection(input, run.held)
        run.held = plan.direction
      end
      AutoWalk.holdDirection(input, plan.direction)
      return
    end
    AutoWalk.releaseDirection(input, run.held)
    run.held = nil
    if not nativeWorld().strengthActive then
      run.phase, run.waited = "strength", 0
      press()
      return
    end
    local boulder = plan.boulder.entity
    run.phase, run.frames = "pushing", 0
    run.fromX, run.fromY = boulder.cellX, boulder.cellY
    run.held = plan.direction
    AutoWalk.holdDirection(input, plan.direction)
    return
  end
  if run.phase == "pushing" then
    local boulder = plan.boulder.entity
    run.frames = run.frames + 1
    if boulder.cellX ~= run.fromX or boulder.cellY ~= run.fromY then
      AutoWalk.releaseDirection(input, run.held)
      run.held = nil
      run.pushes = run.pushes + 1
      run.phase, run.frames = "settling", 0
    elseif run.frames > PUSH_FRAMES then
      return BoulderWalk.stop("The boulder did not move, auto walk stopped")
    end
    return
  end
  if run.phase == "settling" then
    run.frames = run.frames + 1
    if run.frames > 30 and not plan.boulder.entity.moving and not player.moving then
      run.phase = "choose"
    end
  end
end

function BoulderWalk._state() return run end

return BoulderWalk
