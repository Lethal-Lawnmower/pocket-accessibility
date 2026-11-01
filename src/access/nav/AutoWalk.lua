-- Auto-walk: walks the player to the selected object along the same route
-- guided navigation would describe (owner request, 2026-10-31; decision 23).
--
-- The route comes from the reused coordinator (Navigation:selectedRouteGoals
-- and worldRouteRequest) and Pathfinder.find.  Walking is done the way a
-- player does it: the next step's direction is held on upstream's Input as
-- its own source ("access_autowalk"), released when the player reaches the
-- next cell.  Nothing about movement itself is changed.
--
-- It stops, releasing the direction, when the player arrives, the map
-- changes (a door or connection was taken), any screen opens over the map,
-- the player presses any key or button, or no progress is made for a while.

local Speech = require("src.access.Speech")

local AutoWalk = {}

local SOURCE = "access_autowalk"
local STUCK_FRAMES = 90

local walk = nil -- active walk, or nil

local function hold(input, dir)
  input.sources = input.sources or {}
  local sources = input.sources[dir]
  if not sources then
    sources = {}
    input.sources[dir] = sources
  end
  if not sources[SOURCE] then
    sources[SOURCE] = true
    table.insert(input.pressQueue, dir)
  end
  input.state[dir] = true
end

local function release(input, dir)
  if not (input and dir) then return end
  local sources = input.sources and input.sources[dir]
  if sources then
    sources[SOURCE] = nil
    if next(sources) == nil then input.state[dir] = false end
  else
    input.state[dir] = false
  end
end

function AutoWalk.active() return walk ~= nil end

function AutoWalk.stop(reason)
  if not walk then return false end
  release(walk.input, walk.held)
  walk = nil
  if reason then Speech.say(reason, { interrupt = true }) end
  return true
end

-- Starts walking to the coordinator's selected object.  Returns true when
-- walking began; otherwise speaks why not.
function AutoWalk.start(nav, game)
  if walk then return AutoWalk.stop("Auto walk stopped") end
  local item, goals, interaction, _, overworld = nav:selectedRouteGoals()
  if not item then
    Speech.say(goals or "Select an object from the list", { interrupt = true })
    return false
  end
  if type(goals) ~= "table" or #goals == 0 then
    Speech.say("No route to " .. tostring(item.label), { interrupt = true })
    return false
  end
  local options, err = nav:worldRouteRequest(goals, 1)
  if not options then
    Speech.say(tostring(err or "No route"), { interrupt = true })
    return false
  end
  local Pathfinder = require("src.access.nav.Pathfinder")
  local result, findErr = Pathfinder.find(options)
  if not result or type(result.steps) ~= "table" then
    Speech.say(tostring(findErr or "Cannot reach yet"), { interrupt = true })
    return false
  end
  local player = overworld.player
  walk = {
    input = game.input,
    overworld = overworld,
    map = overworld.map,
    steps = result.steps,
    goal = result.goal,
    label = item.label,
    interaction = interaction,
    lastX = player.cellX, lastY = player.cellY,
    still = 0,
  }
  if #result.steps == 0 then
    AutoWalk.stop(tostring(item.label) .. " is here")
    return true
  end
  Speech.say("Walking to " .. tostring(item.label), { interrupt = true })
  return true
end

local function arrivalText()
  local text = "Arrived at " .. tostring(walk.label)
  local goal = walk.goal
  if walk.interaction and goal then
    local hint = walk.interaction[tostring(goal.x) .. "," .. tostring(goal.y)]
    if hint then text = text .. ". " .. tostring(hint) end
  end
  return text
end

-- Per frame, after upstream's update.  `top` is the top screen.
function AutoWalk.update(top)
  if not walk then return end
  local overworld = walk.overworld
  if overworld.map ~= walk.map then return AutoWalk.stop(arrivalText()) end
  local player = overworld.player
  if top ~= overworld then
    -- a door or staircase shows its transition before the map changes, so a
    -- screen opening on the destination cell is the arrival
    local last = walk.steps[#walk.steps]
    if last and player.cellX == last.x and player.cellY == last.y then
      return AutoWalk.stop(arrivalText())
    end
    return AutoWalk.stop("Auto walk stopped")
  end
  local x, y = player.cellX, player.cellY
  if x ~= walk.lastX or y ~= walk.lastY then
    walk.lastX, walk.lastY, walk.still = x, y, 0
  elseif not player.moving then
    walk.still = walk.still + 1
    if walk.still > STUCK_FRAMES then return AutoWalk.stop("Blocked, auto walk stopped") end
  end
  if player.moving then return end -- keep the held direction mid-step
  local step = nil
  for _, s in ipairs(walk.steps) do
    if s.fromX == x and s.fromY == y then step = s break end
  end
  if not step then
    local last = walk.steps[#walk.steps]
    if last and last.x == x and last.y == y then return AutoWalk.stop(arrivalText()) end
    return AutoWalk.stop("Off the route, auto walk stopped")
  end
  if walk.held ~= step.direction then
    release(walk.input, walk.held)
    walk.held = step.direction
  end
  hold(walk.input, step.direction)
end

function AutoWalk._resetForTests() walk = nil end

return AutoWalk
