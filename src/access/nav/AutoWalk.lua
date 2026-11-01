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

-- Generation differences come through the world adapter (WorldAdapter.lua):
-- what counts as "on the map", the game's own transitions, and how a
-- direction chosen inside the game's step takes effect.  Gen 2 adds two
-- coordinator hooks: field moves started with an A press facing the obstacle
-- (Navigation:stepInteraction) and carpet warps that need their direction
-- held (Navigation:warpPressDirection).

local Speech = require("src.access.Speech")
local WorldAdapter = require("src.access.nav.WorldAdapter")

local AutoWalk = {}

local SOURCE = "access_autowalk"
local STUCK_FRAMES = 90
local MAX_REROUTES = 8
local PUSH_FRAMES = 60
-- Resuming from the same cell this many times means the game keeps turning
-- the player back there (Ecruteak's Tin Tower sages stop every walk north
-- and step the player back; auto-walk resumed into them for ever).
local MAX_RESUMES_AT_CELL = 3

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

-- Turning on the spot to face a field-move obstacle (see AutoWalk.update).
function AutoWalk.turning() return walk ~= nil and not walk.paused and walk.turning == true end

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
-- walking began; otherwise speaks why not.  `adapter` defaults to the running
-- game's (WorldAdapter.current), Gen 1 when none is known.
function AutoWalk.start(nav, game, adapter)
  if walk then return AutoWalk.stop("Auto walk stopped") end
  adapter = adapter or WorldAdapter.current() or WorldAdapter.gen1
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
    game = game,
    adapter = adapter,
    overworld = overworld,
    -- Gen 2's coordinator hands out a facade over the live World; the
    -- adapter's top is the World itself when the player is free to walk
    native = overworld.native,
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
    -- already in place: still say which way to face (Yellow's Pikachu is
    -- usually right behind the player), as an arrival would
    local text = tostring(item.label) .. " is here"
    local hint = interaction and result.goal
      and interaction[tostring(result.goal.x) .. "," .. tostring(result.goal.y)]
    if hint then text = text .. ". " .. tostring(hint) end
    AutoWalk.stop(text)
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

-- True when a battle screen is anywhere on the stack.  Both generations'
-- battle screens carry `isBattle = true` (src/battle/BattleState.lua,
-- src/ui/gen2/BattleState.lua); Gen 1's class is still recognised directly.
-- Matching only Gen 1's class left a Gen 2 trainer pause waiting forever.
local function battleOnStack(stack)
  if not (stack and stack.states) then return false end
  local BattleState = package.loaded["src.battle.BattleState"]
  for _, state in ipairs(stack.states) do
    if type(state) == "table" and (state.isBattle == true
        or (BattleState and getmetatable(state) == BattleState)) then
      return true
    end
  end
  return false
end

-- The player is on the map with nothing over it: Gen 1's overworld is its
-- own top state; Gen 2's adapter reports the live World there.
local function onMap(top)
  return top ~= nil and (top == walk.overworld or (walk.native ~= nil and top == walk.native))
end

local function transitioning()
  local adapter = walk.adapter or WorldAdapter.gen1
  return adapter.transitioning(walk.overworld)
end

-- The direction a carpet warp on (x, y) needs held, or nil (Gen 1, or not a
-- carpet).
local function pressDirection(x, y)
  local nav = walk.nav
  if type(nav.warpPressDirection) ~= "function" then return nil end
  local ok, dir = pcall(nav.warpPressDirection, nav, walk.overworld, x, y)
  return ok and dir or nil
end

-- After the held direction changed inside the game's step.
local function steered()
  local adapter = walk.adapter
  if adapter and adapter.afterSteer then adapter.afterSteer(walk.game) end
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
    if not onMap(top) or transitioning() or overworld.map == walk.map then return end
    return nextLeg()
  end
  if walk.paused then
    local stack = package.loaded["src.core.StateStack"]
    if battleOnStack(stack) then walk.battleSeen = true end
    if not onMap(top) then return end
    if transitioning() then return end
    if overworld.map ~= walk.map then return AutoWalk.stop("Auto walk stopped") end
    if walk.expectBattle and not walk.battleSeen then return end -- trainer still walking over
    -- battles, card-key door messages and other game-caused screens: carry
    -- on, unless the game keeps sending the player back to the same cell
    local key = tostring(player.cellX) .. "," .. tostring(player.cellY)
    walk.resumesAt = walk.resumesAt or {}
    walk.resumesAt[key] = (walk.resumesAt[key] or 0) + 1
    if walk.resumesAt[key] >= MAX_RESUMES_AT_CELL then
      return AutoWalk.stop("Turned back again, auto walk stopped")
    end
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
  if not onMap(top) then
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
  -- spinner slides, door or stair transitions (Gen 2 also ice slides,
  -- currents and the step off an arrival door) move the player on their
  -- own: let go of the direction and wait
  if transitioning() then
    release(walk.input, walk.held)
    walk.held = nil
    walk.lastX, walk.lastY, walk.still = player.cellX, player.cellY, 0
    return
  end
  if walk.tapA then
    -- release the one-frame A press used on a card-key door or field move
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
      -- Gen 2 carpet warps (doormats, gate mats) fire only while their own
      -- direction is held, which need not be the step that reached them
      local press = pressDirection(x, y)
      if walk.journey and not walk.final then
        walk.pushDir, walk.pushFrames = press or last.direction, 0
        return
      end
      if press and walk.targetMapId then
        walk.pushDir, walk.pushFrames = press, 0
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
  -- Gen 2 field moves on the route (Cut, Whirlpool, Surf, Waterfall) start
  -- with an A press facing the obstacle; the game asks first, which pauses
  -- the walk until the player answers, and the walk resumes from wherever
  -- the move leaves them.  Asked again at the same place means the player
  -- declined or the move could not be used: stop with the instruction.
  local nav = walk.nav
  local action = type(nav.stepInteraction) == "function"
    and nav:stepInteraction(overworld, step) or nil
  walk.turning = nil
  if action then
    if player.facing ~= step.direction then
      -- Turn to face the obstacle.  The held direction lasts a whole frame
      -- of game ticks, so at a fast speed the turn becomes a step: into a
      -- waterfall's bottom cell, where the current carries the player
      -- back, every frame (Silver Cave at 200X: "Blocked").  While
      -- turning, WalkSpeed runs the game at 1X (AutoWalk.turning).
      if walk.held ~= step.direction then release(walk.input, walk.held) walk.held = step.direction end
      hold(walk.input, step.direction)
      walk.turning = true
      return
    end
    release(walk.input, walk.held)
    walk.held = nil
    local key = tostring(x) .. "," .. tostring(y) .. "," .. tostring(step.direction)
    if walk.fieldMoveAt == key then
      return AutoWalk.stop(tostring(action.failText) .. ". " .. tostring(action.hint))
    end
    walk.fieldMoveAt = key
    table.insert(walk.input.pressQueue, "a")
    walk.input.state.a = true
    walk.tapA = true
    walk.still = 0
    return
  end
  -- a closed card-key door opens when faced and A is pressed (Gen 1 Silph
  -- Co.); with the key, turn to it, press A once, and the door's message
  -- pauses the walk until it opens
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
--
-- Gen 2 latches the held direction before the world steps and starts the
-- next step in the same tick as the landing, so after any change here the
-- adapter re-reads the input (steered); without it every turn came one tile
-- late and every walk overshot its last cell by one.
function AutoWalk.stepped(x, y)
  if not walk or walk.paused or walk.awaitingMap or walk.pushDir or walk.tapA then return end
  if walk.overworld.map ~= walk.map then return end
  for _, s in ipairs(walk.steps) do
    if s.fromX == x and s.fromY == y then
      -- a field move on this step starts with an A press: stop here and let
      -- the update face the obstacle and press
      if type(walk.nav.stepInteraction) == "function"
         and walk.nav:stepInteraction(walk.overworld, s) then
        release(walk.input, walk.held)
        walk.held = nil
        steered()
        return
      end
      if walk.held ~= s.direction then
        release(walk.input, walk.held)
        walk.held = s.direction
        hold(walk.input, s.direction)
        steered()
      end
      return
    end
  end
  -- the route's last cell of a walk to a warp: keep pressing.  Some warps
  -- (the Rocket Hideout elevator door, house exit mats) fire only while the
  -- player keeps pressing into them after stepping on; letting go here
  -- stranded the player on the door.  A Gen 2 carpet wants its own direction.
  local last = walk.steps[#walk.steps]
  if walk.targetMapId and last and last.x == x and last.y == y then
    local press = pressDirection(x, y)
    if press and walk.held ~= press then
      release(walk.input, walk.held)
      walk.held = press
      hold(walk.input, press)
      steered()
    end
    return
  end
  -- the last cell of any other walk, or off the route: stop pressing here
  -- and let the update announce the arrival or plan again
  release(walk.input, walk.held)
  walk.held = nil
  steered()
end

-- For scripted debugging: the active walk's plan (read-only use).
function AutoWalk._state() return walk end

function AutoWalk._resetForTests() walk = nil end

return AutoWalk
