-- Auto-walk's boulder pushing (owner request, 2026-11-03): when Strength
-- boulders are all that stands between the player and the selected object,
-- walk to each pushing cell, switch Strength on the way the player does (A at
-- a boulder, then YES) and push, planning again after every push.  The plan is
-- a search over the floor (Navigation:boulderOpening), with nothing about any
-- map written here.  AUTO-WALK PUZZLES in the Accessibility page turns it off.

local Speech = require("src.access.Speech")

local BoulderWalk = {}

local MAX_PUSHES = 120
local PUSH_FRAMES = 150
local PROMPT_FRAMES = 1500
local PROMPT_GAP = 30
local SEARCH_FRAMES = 1800

local run = nil

function BoulderWalk.active() return run ~= nil end

-- Facing and pushing run at 1X (WalkSpeed): at a fast speed the held direction lasts
-- many game ticks, and after the boulder moves the player would step after it, on a
-- floor of holes right into one.
function BoulderWalk.pushing()
  return run ~= nil and (run.phase == "face" or run.phase == "pushing")
end

local function autoWalk() return require("src.access.nav.AutoWalk") end

local function strengthOn()
  if type(run.nav.strengthActive) == "function" then return run.nav:strengthActive() end
  return (run.overworld.native or run.overworld).strengthActive
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

local function begin(nav, game, adapter, item, overworld, plan, needs, stone)
  -- switching Strength on is what this does itself
  if needs and needs ~= "" and not needs:find("party menu", 1, true)
     and not needs:find("Use Strength", 1, true) then
    Speech.say("Boulders block the way. " .. needs:gsub(";%s*$", ""), { interrupt = true })
    return true
  end
  run = { nav = nav, game = game, adapter = adapter, overworld = overworld, map = overworld.map,
    id = item.id, label = item.label, pushes = 0, phase = "choose", stone = stone }
  Speech.say(stone and "Pushing boulders into place"
    or ("Pushing boulders to reach " .. tostring(item.label)), { interrupt = true })
  return true
end

-- Starts when boulders are the only thing in the way.  False leaves the caller's
-- "No route" to be said.
function BoulderWalk.tryStart(nav, game, adapter, item, goals, overworld)
  if type(nav.boulderOpening) ~= "function" or type(goals) ~= "table" then return false end
  if not require("src.access.Settings").autoWalkBoulders(game) then return false end
  local plan, _, needs, stone = nav:boulderOpening(overworld, goals)
  if not plan then return false end
  return begin(nav, game, adapter, item, overworld, plan, needs, stone)
end

-- An Area target with no way there yet: the floor's puzzle may open one (Seafoam's
-- currents, Victory Road's barriers), so do the floor, then try the journey again.
function BoulderWalk.tryArea(nav, game, adapter, item, overworld)
  if type(nav.boulderOpening) ~= "function" then return false end
  if not require("src.access.Settings").autoWalkBoulders(game) then return false end
  local plan, reason, needs, stone = nav:boulderOpening(overworld, {})
  if not (stone and (plan or reason == "searching")) then return false end
  begin(nav, game, adapter, item, overworld, plan, needs, true)
  if run then run.thenWalk = true end
  return true
end

-- A journey blocked by boulders on this floor: open the way to the warp it needs (Mt.
-- Ember, the Ruby Path), then the journey is planned again.
function BoulderWalk.tryJourney(nav, game, adapter, item, overworld)
  if type(nav.journeyOpeningGoals) ~= "function" then return false end
  if not require("src.access.Settings").autoWalkBoulders(game) then return false end
  local goals = nav:journeyOpeningGoals(item, overworld)
  if not goals then return false end
  local plan, _, needs = nav:boulderOpening(overworld, goals)
  if not plan then return false end
  begin(nav, game, adapter, item, overworld, plan, needs, false)
  -- (the floor's plan may change which warp the journey wants, so it is planned again)
  if run then run.fixedGoals, run.thenWalk = goals, true end
  return true
end

-- Auto-walk to a boulder or a hole on a floor of holes still to fill does the whole
-- floor.  With AUTO-WALK PUZZLES off it stays a walk to the hint's pushing cell.
function BoulderWalk.tryStone(nav, game, adapter, item, overworld)
  if type(nav.boulderOpening) ~= "function" then return false end
  local label = tostring(item.label)
  if not (label:find("^Boulder %d") or label:find("^Hole %d")
      or label:find("^Pressure Switch") or label:find("^Boulder Drop Hole")) then return false end
  if not require("src.access.Settings").autoWalkBoulders(game) then return false end
  local plan, reason, needs, stone = nav:boulderOpening(overworld, {})
  if not (stone and (plan or reason == "searching")) then return false end
  return begin(nav, game, adapter, item, overworld, plan, needs, true)
end

local function press()
  table.insert(run.game.input.pressQueue, "a")
  run.game.input.state.a = true
  run.tapped = true
end

local function choose()
  local ok, item, goals = pcall(run.nav.selectedRouteGoals, run.nav)
  local present = ok and type(item) == "table" and item.id == run.id
  -- a boulder chosen as the target leaves the list when it falls
  if not present and not run.stone then
    return BoulderWalk.stop(tostring(run.label) .. " is gone, auto walk stopped")
  end
  local plan, reason = run.nav:boulderOpening(run.overworld, run.fixedGoals or (present and goals) or {}, run.stone)
  if reason == "searching" then
    run.searching = (run.searching or 0) + 1
    if run.searching > SEARCH_FRAMES then
      return BoulderWalk.stop("Could not plan the boulders in time, auto walk stopped")
    end
    return
  end
  run.searching = nil
  if not plan then
    local nav, game, adapter, stone, pushes = run.nav, run.game, run.adapter, run.stone, run.pushes
    local thenWalk = run.thenWalk
    run = nil
    if thenWalk and reason ~= "searching" then return autoWalk().start(nav, game, adapter) end
    if stone and (reason == "open" or (reason == "finished" and pushes > 0)) then
      Speech.say("The boulders are all in place", { interrupt = true })
      return
    end
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
    if strengthOn() and onMap then
      run.phase = "face"
    elseif onMap and run.waited > PROMPT_GAP * 2 then
      return BoulderWalk.stop("Could not use Strength, auto walk stopped")
    elseif run.waited % PROMPT_GAP == 0 then
      press()
    end
    return
  end
  if not onMap then
    -- "The boulder fell through" waits for A; a battle stays the player's
    if run.phase == "settling" then
      run.frames = run.frames + 1
      local top = run.adapter.top and run.adapter.top(run.game)
      if run.frames % PROMPT_GAP == 0 and not (type(top) == "table" and top.isBattle) then
        press()
      end
    end
    return
  end
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
    if not strengthOn() then
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
