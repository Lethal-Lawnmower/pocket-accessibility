-- Auto-walk's switch trying (owner request, 2026-11-03): when a target has no
-- route and the floor has signs that ask to be turned on or off, flip them and
-- watch the map.  What each switch does is not read or assumed: a state is the
-- floor's collision grid, each switch tried from each state is remembered, and
-- the walk ends as soon as a route to the target opens.  Nothing here names a
-- map.  AUTO-WALK PUZZLES in the Accessibility page turns it off.
--
-- Hidden switches (Vermilion Gym's trash cans) are the same walk with one change: a
-- press can do nothing visible, and the answer can be re-rolled, so nothing tried stays
-- ruled out.  The floor's tiles say when a press did something.  From there the nearest
-- switches go first, because the game hides the second next to the first.  This learns
-- by trying and does not read which ones hold the answer.

local Speech = require("src.access.Speech")

local SwitchWalk = {}

local MAX_FLIPS = 48
local MAX_SEARCHES = 200
local PROMPT_FRAMES = 1500
local PROMPT_GAP = 30
local CALM_FRAMES = 20

local run = nil

function SwitchWalk.active() return run ~= nil end

local function autoWalk() return require("src.access.nav.AutoWalk") end

function SwitchWalk.stop(reason)
  if not run then return false end
  local input = run.game.input
  autoWalk().releaseDirection(input, run.held)
  input.state.a = false
  run = nil
  autoWalk().stop()
  if reason then Speech.say(reason, { interrupt = true }) end
  return true
end

local function floorState(map)
  local parts = {}
  for y = 0, map.heightCells - 1 do
    for x = 0, map.widthCells - 1 do
      local read = map.cellCollision or map.coll or map.cellTile
      parts[#parts + 1] = tostring(read(map, x, y))
    end
  end
  return table.concat(parts, ",")
end

-- Starts when the floor has switches.  False leaves the caller's "No route" to be said.
function SwitchWalk.tryStart(nav, game, adapter, item, overworld)
  if type(nav.switchSigns) ~= "function" then return false end
  if not require("src.access.Settings").autoWalkBoulders(game) then return false end
  local signs = nav:switchSigns(overworld)
  local hidden = false
  if #signs == 0 and type(nav.hiddenSwitchSigns) == "function" then
    signs, hidden = nav:hiddenSwitchSigns(overworld), true
  end
  if #signs == 0 then return false end
  run = { nav = nav, game = game, adapter = adapter, overworld = overworld, map = overworld.map,
    id = item.id, label = item.label, flips = 0, phase = "choose", tried = {}, complete = {}, hidden = hidden }
  Speech.say((hidden and "Searching for switches to reach " or "Trying switches to reach ") .. tostring(item.label),
    { interrupt = true })
  return true
end

local function press()
  table.insert(run.game.input.pressQueue, "a")
  run.game.input.state.a = true
  run.tapped = true
end

-- A press while the switch's script runs with no text up would land after it ends and
-- start the switch again (Pokemon Mansion), so A only goes to text the game shows.
local function promptUp()
  local nav = run.nav
  if type(nav.promptWaiting) ~= "function" then return true end
  return nav:promptWaiting()
end

-- The first switch toward a state with switches left to try, through flips
-- already seen, from `from`; nil when every known state is exhausted.
local function knownWayOn(from)
  local queue, seen, head = { { state = from } }, { [from] = true }, 1
  while queue[head] do
    local node = queue[head]
    head = head + 1
    for switch, to in pairs(run.tried[node.state] or {}) do
      if to ~= "blocked" and not seen[to] then
        seen[to] = true
        local first = node.first or switch
        if not run.complete[to] then return first end
        queue[#queue + 1] = { state = to, first = first }
      end
    end
  end
  return nil
end

local function walkToSign(pick, from)
  run.sign, run.from, run.lastLabel = pick, from, pick.label
  run.phase = "walking"
  local player = run.overworld.player
  for _, goal in ipairs(pick.goals) do
    if goal.x == player.cellX and goal.y == player.cellY then
      run.phase = "face"
      return
    end
  end
  autoWalk().start(run.nav, run.game, run.adapter, { goals = pick.goals, quiet = true })
end

-- The nearest switch not tried since the floor last changed, measured from the switch
-- that changed it, or from the player before any has.
local function nearestUntried()
  local AutoWalk = autoWalk()
  local player = run.overworld.player
  local fromX = run.anchor and run.anchor.x or player.cellX
  local fromY = run.anchor and run.anchor.y or player.cellY
  local best, bestDistance = nil, math.huge
  for _, sign in ipairs(run.nav:hiddenSwitchSigns(run.overworld)) do
    local distance = math.abs(sign.x - fromX) + math.abs(sign.y - fromY)
    if not run.tried[sign.label] and distance < bestDistance and AutoWalk.routeExists(run.nav, sign.goals) then
      best, bestDistance = sign, distance
    end
  end
  return best
end

local function chooseHidden()
  if run.flips >= MAX_SEARCHES then
    return SwitchWalk.stop("Still searching after many tries, auto walk stopped")
  end
  local pick = nearestUntried()
  if not pick then
    run.tried = {}
    pick = nearestUntried()
  end
  if not pick then
    return SwitchWalk.stop("No switch opens a way to " .. tostring(run.label) .. ", auto walk stopped")
  end
  walkToSign(pick, run.nav:floorMarks(run.overworld))
end

local function finishHiddenPress()
  run.flips = run.flips + 1
  local marks = run.nav:floorMarks(run.overworld)
  if marks ~= run.from then
    run.tried, run.anchor = {}, run.sign
  end
  run.tried[run.sign.label] = true
  run.phase = "choose"
end

local function choose()
  local AutoWalk = autoWalk()
  local ok, item, goals = pcall(run.nav.selectedRouteGoals, run.nav)
  if not (ok and type(item) == "table" and item.id == run.id) then
    return SwitchWalk.stop(tostring(run.label) .. " is gone, auto walk stopped")
  end
  if AutoWalk.routeExists(run.nav, goals) then
    local nav, game, adapter = run.nav, run.game, run.adapter
    run = nil
    return AutoWalk.start(nav, game, adapter)
  end
  if run.hidden then return chooseHidden() end
  if run.flips >= MAX_FLIPS then
    return SwitchWalk.stop("Still trying switches after many flips, auto walk stopped")
  end
  local state = floorState(run.map)
  run.tried[state] = run.tried[state] or {}
  local signs = run.nav:switchSigns(run.overworld)
  local pick, byLabel, again = nil, {}, nil
  for _, sign in ipairs(signs) do
    byLabel[sign.label] = sign
    if not pick and run.tried[state][sign.label] == nil then
      if not AutoWalk.routeExists(run.nav, sign.goals) then
        run.tried[state][sign.label] = "blocked"
      elseif sign.label == run.lastLabel then
        again = sign -- flipping it straight back is the last thing to try here
      else
        pick = sign
      end
    end
  end
  pick = pick or again
  if not pick then
    run.complete[state] = true
    local label = knownWayOn(state)
    pick = label and byLabel[label]
    if not pick then
      return SwitchWalk.stop("No switch opens a way to " .. tostring(run.label) .. ", auto walk stopped")
    end
  end
  walkToSign(pick, state)
end

-- Per frame, after AutoWalk.update.
function SwitchWalk.update()
  if not run then return end
  local AutoWalk = autoWalk()
  if AutoWalk.active() then return end
  local input = run.game.input
  if run.tapped then
    input.state.a = false
    run.tapped = nil
  end
  local onMap = run.adapter.onMap(run.game)
  if run.phase == "flipping" then
    -- the game's own question: A through its text, YES is the first answer
    run.waited = run.waited + 1
    if run.waited > PROMPT_FRAMES then
      return SwitchWalk.stop("The switch did not finish, auto walk stopped")
    end
    if onMap then
      run.calm = run.calm + 1
      if run.calm >= CALM_FRAMES then
        if run.hidden then return finishHiddenPress() end
        run.flips = run.flips + 1
        run.tried[run.from][run.sign.label] = floorState(run.map)
        run.phase = "choose"
      end
    else
      run.calm = 0
      if run.waited % PROMPT_GAP == 0 and promptUp() then press() end
    end
    return
  end
  if not onMap then return end
  if run.overworld.map ~= run.map then
    return SwitchWalk.stop("Left the map, auto walk stopped")
  end
  if run.phase == "choose" then return choose() end
  local player = run.overworld.player
  local sign = run.sign
  if run.phase == "walking" then
    run.phase = "face"
    for _, goal in ipairs(sign.goals) do
      if goal.x == player.cellX and goal.y == player.cellY then return end
    end
    if run.hidden then run.tried[sign.label] = true
    else run.tried[run.from][sign.label] = "blocked" end
    run.phase = "choose"
    return
  end
  if run.phase == "face" then
    if player.moving then return end
    local dx, dy = sign.x - player.cellX, sign.y - player.cellY
    local dir
    if math.abs(dx) > math.abs(dy) then dir = dx > 0 and "right" or "left"
    else dir = dy > 0 and "down" or "up" end
    if player.facing ~= dir then
      if run.held ~= dir then
        AutoWalk.releaseDirection(input, run.held)
        run.held = dir
      end
      AutoWalk.holdDirection(input, dir)
      return
    end
    AutoWalk.releaseDirection(input, run.held)
    run.held = nil
    run.phase, run.waited, run.calm = "flipping", 0, 0
    press()
  end
end

function SwitchWalk._state() return run end

return SwitchWalk
