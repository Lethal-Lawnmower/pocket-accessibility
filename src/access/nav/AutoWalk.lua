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
local MAX_REROUTES = 8
local PUSH_FRAMES = 60

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

-- Walking right now (not paused for a battle); real input cancels only then.
function AutoWalk.walking() return walk ~= nil and not walk.paused end

function AutoWalk.stop(reason)
  if not walk then return false end
  release(walk.input, walk.held)
  walk = nil
  if reason then Speech.say(reason, { interrupt = true }) end
  return true
end

-- Route from where the player stands to the goals.  Tries the old
-- coordinator's route policies in order: 1 walks only; 2 also uses the HMs
-- the party knows and card-key doors when the Card Key is held (the same
-- fallback guided navigation uses).
local function findRoute(nav, goals)
  local Pathfinder = require("src.access.nav.Pathfinder")
  local lastErr = "No route"
  for policy = 1, 2 do
    local options, err = nav:worldRouteRequest(goals, policy)
    if options then
      local result, findErr = Pathfinder.find(options)
      if result and type(result.steps) == "table" then return result end
      lastErr = findErr or lastErr
    else
      lastErr = err or lastErr
    end
  end
  return nil, lastErr
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
  -- an Area target is on another map: walk the cross-map journey leg by
  -- leg (Navigation:regionalNextLeg), re-planning on every new map
  local journey, final = nil, true
  if item.type == "area" then
    journey = { targetMapId = item.mapId, targetGoals = goals }
    local leg, legErr = nav:regionalNextLeg(journey)
    if not leg then
      Speech.say(tostring(legErr or "No route yet"), { interrupt = true })
      return false
    end
    goals, final = leg.goals, leg.final == true
  end
  local result, findErr = findRoute(nav, goals)
  if not result then
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
    -- the map a warp target leads to: reaching it is the arrival even when
    -- a fast game speed moved the player past the last step between two
    -- updates (several tiles per real frame at 200X)
    targetMapId = item.type == "warp" and item.destinationMapId or nil,
    interaction = interaction,
    nav = nav,
    goals = goals,
    journey = journey,
    final = final,
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

-- True when a battle screen is anywhere on the stack.
local function battleOnStack(stack)
  local BattleState = package.loaded["src.battle.BattleState"]
  if not (BattleState and stack and stack.states) then return false end
  for _, state in ipairs(stack.states) do
    if getmetatable(state) == BattleState then return true end
  end
  return false
end

-- Battles pause the walk and it resumes afterwards (owner request,
-- 2026-10-31).  Called from the world.trainer_engaged event, because a
-- trainer walks over on the open map before any screen opens.
function AutoWalk.pause(expectBattle)
  if not walk then return end
  release(walk.input, walk.held)
  walk.held = nil
  walk.paused = true
  walk.expectBattle = walk.expectBattle or expectBattle == true
end

-- Recomputes the route from where the player now stands to the same goals.
local function resume(quiet)
  local result = findRoute(walk.nav, walk.goals)
  if not result then
    return AutoWalk.stop("Cannot reach " .. tostring(walk.label) .. ", auto walk stopped")
  end
  local player = walk.overworld.player
  walk.steps, walk.goal = result.steps, result.goal or walk.goal
  walk.paused, walk.expectBattle, walk.battleSeen = nil, nil, nil
  walk.lastX, walk.lastY, walk.still = player.cellX, player.cellY, 0
  if #walk.steps == 0 then
    if walk.journey and not walk.final then
      -- standing on the warp this leg needs (a teleport pad lands you on a
      -- pad): pads fire on stepping onto them, so step off and back on
      local x, y = player.cellX, player.cellY
      local map = walk.overworld.map
      for _, d in ipairs({ { "up", 0, -1, "down" }, { "down", 0, 1, "up" },
                           { "left", -1, 0, "right" }, { "right", 1, 0, "left" } }) do
        local nx, ny = x + d[2], y + d[3]
        local ok, walkable = pcall(map.isWalkableCell, map, nx, ny)
        if ok and walkable then
          walk.steps = {
            { fromX = x, fromY = y, x = nx, y = ny, direction = d[1] },
            { fromX = nx, fromY = ny, x = x, y = y, direction = d[4] },
          }
          return
        end
      end
    end
    return AutoWalk.stop(arrivalText())
  end
  if not quiet then
    Speech.say("Resuming walk to " .. tostring(walk.label), { interrupt = false })
  end
end

-- Journey: the map changed on a leg that was not the last one.  Once the new
-- map is settled, plan its leg and keep walking.
local function nextLeg()
  local leg, err = walk.nav:regionalNextLeg(walk.journey)
  if not leg then
    return AutoWalk.stop("No route from here to " .. tostring(walk.label) .. ", auto walk stopped")
  end
  walk.map, walk.goals, walk.final = walk.overworld.map, leg.goals, leg.final == true
  walk.awaitingMap, walk.reroutes, walk.doorTries = nil, nil, nil
  walk.pushDir, walk.pushFrames = nil, nil
  return resume(true)
end

-- Per frame, after upstream's update.  `top` is the top screen.
function AutoWalk.update(top)
  if not walk then return end
  local overworld = walk.overworld
  local player = overworld.player
  if walk.awaitingMap then
    if top ~= overworld or overworld.transitioning or overworld.map == walk.map then return end
    return nextLeg()
  end
  if walk.paused then
    local stack = package.loaded["src.core.StateStack"]
    if battleOnStack(stack) then walk.battleSeen = true end
    if top ~= overworld then return end
    if overworld.map ~= walk.map then return AutoWalk.stop("Auto walk stopped") end
    if walk.expectBattle and not walk.battleSeen then return end -- trainer still walking over
    -- battles, card-key door messages and other game-caused screens: carry on
    return resume()
  end
  if overworld.map ~= walk.map then
    -- it is an arrival only when the player was finishing the route; a warp
    -- crossed earlier (a teleport pad) is not
    local last = walk.steps[#walk.steps]
    local finishing = last and ((walk.lastX == last.x and walk.lastY == last.y)
      or (walk.lastX == last.fromX and walk.lastY == last.fromY))
    local newMapId = overworld.map.def and overworld.map.def.id or overworld.map.id
    if walk.targetMapId and walk.targetMapId == newMapId then finishing = true end
    if walk.journey and (not walk.final or not finishing) then
      release(walk.input, walk.held)
      walk.held, walk.awaitingMap = nil, true
      walk.pushDir = nil
      return
    end
    if not finishing then return AutoWalk.stop("Left the map, auto walk stopped") end
    return AutoWalk.stop(arrivalText())
  end
  if top ~= overworld then
    -- a door or staircase shows its transition before the map changes, so a
    -- screen opening on the destination cell is the arrival (or, mid-journey,
    -- the way onto the next map)
    local last = walk.steps[#walk.steps]
    if last and player.cellX == last.x and player.cellY == last.y then
      if walk.journey and not walk.final then
        release(walk.input, walk.held)
        walk.held, walk.awaitingMap = nil, true
        return
      end
      return AutoWalk.stop(arrivalText())
    end
    -- anything else pauses; the walk resumes when the map returns
    AutoWalk.pause(false)
    if battleOnStack(package.loaded["src.core.StateStack"]) then walk.battleSeen = true end
    return
  end
  -- spinner slides and door or stair transitions move the player on their
  -- own: let go of the direction and wait (OverworldState spinnerSliding,
  -- player.spinning, transitioning)
  if overworld.spinnerSliding or player.spinning or overworld.transitioning then
    release(walk.input, walk.held)
    walk.held = nil
    walk.lastX, walk.lastY, walk.still = player.cellX, player.cellY, 0
    return
  end
  if walk.tapA then
    -- release the one-frame A press used on a card-key door
    walk.input.state.a = false
    walk.tapA = nil
  end
  local x, y = player.cellX, player.cellY
  if x ~= walk.lastX or y ~= walk.lastY then
    walk.lastX, walk.lastY, walk.still = x, y, 0
  elseif not player.moving then
    walk.still = walk.still + 1
    if walk.still > STUCK_FRAMES then return AutoWalk.stop("Blocked, auto walk stopped") end
  end
  if player.moving then return end -- keep the held direction mid-step
  if walk.pushDir then
    -- mid-journey on the way onto the next map: some warps (doors, some
    -- stairs) fire only while the player keeps pressing into them
    walk.pushFrames = walk.pushFrames + 1
    if walk.pushFrames > PUSH_FRAMES then
      return AutoWalk.stop("Could not go through, auto walk stopped")
    end
    if walk.held ~= walk.pushDir then release(walk.input, walk.held) walk.held = walk.pushDir end
    hold(walk.input, walk.pushDir)
    walk.still = 0
    return
  end
  local step = nil
  for _, s in ipairs(walk.steps) do
    if s.fromX == x and s.fromY == y then step = s break end
  end
  if not step then
    local last = walk.steps[#walk.steps]
    if last and last.x == x and last.y == y then
      if walk.journey and not walk.final then
        walk.pushDir, walk.pushFrames = last.direction, 0
        return
      end
      return AutoWalk.stop(arrivalText())
    end
    -- pushed off the route (a spinner, a current, a scripted step): plan again
    -- from here, quietly, a few times per walk
    walk.reroutes = (walk.reroutes or 0) + 1
    if walk.reroutes > MAX_REROUTES then
      return AutoWalk.stop("Off the route, auto walk stopped")
    end
    return resume(true)
  end
  -- a closed card-key door opens when faced and A is pressed (Gen 1 Silph
  -- Co.); with the key, turn to it, press A once, and the door's message
  -- pauses the walk until it opens
  local nav = walk.nav
  if type(nav.isClosedCardKeyDoorCell) == "function" and type(nav.hasCardKey) == "function"
      and nav:isClosedCardKeyDoorCell(overworld, step.x, step.y) and nav:hasCardKey() then
    if player.facing ~= step.direction then
      if walk.held ~= step.direction then release(walk.input, walk.held) walk.held = step.direction end
      hold(walk.input, step.direction)
      return
    end
    release(walk.input, walk.held)
    walk.held = nil
    walk.doorTries = (walk.doorTries or 0) + 1
    if walk.doorTries > 3 then return AutoWalk.stop("Door will not open, auto walk stopped") end
    table.insert(walk.input.pressQueue, "a")
    walk.input.state.a = true
    walk.tapA = true
    walk.still = 0
    return
  end
  if walk.held ~= step.direction then
    release(walk.input, walk.held)
    walk.held = step.direction
  end
  hold(walk.input, step.direction)
end

-- Called from upstream's world.stepped event, which fires inside the game's
-- own step each time the player finishes a tile, before the next step reads
-- input.  Steering here keeps the walk on its route at any game speed: at
-- 30X or 200X one real frame covers several tiles, and the per-frame update
-- alone ran the player past every turn.  The update still handles arrival,
-- reroutes, card-key doors, warps and pauses.
function AutoWalk.stepped(x, y)
  if not walk or walk.paused or walk.awaitingMap or walk.pushDir or walk.tapA then return end
  if walk.overworld.map ~= walk.map then return end
  for _, s in ipairs(walk.steps) do
    if s.fromX == x and s.fromY == y then
      if walk.held ~= s.direction then
        release(walk.input, walk.held)
        walk.held = s.direction
        hold(walk.input, s.direction)
      end
      return
    end
  end
  -- the route's last cell, or off the route: stop pressing here and let the
  -- update announce the arrival or plan again
  release(walk.input, walk.held)
  walk.held = nil
end

-- For scripted debugging: the active walk's plan (read-only use).
function AutoWalk._state() return walk end

function AutoWalk._resetForTests() walk = nil end

return AutoWalk
