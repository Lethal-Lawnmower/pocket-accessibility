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
local REROUTE_FRAMES = 45
local MAX_REROUTES = 8
local MAX_BLOCKED_TRIES = 3
local PUSH_FRAMES = 60
-- Resuming from the same cell this many times means the game keeps turning
-- the player back there (Ecruteak's Tin Tower sages stop every walk north
-- and step the player back; auto-walk resumed into them for ever).
local MAX_RESUMES_AT_CELL = 3
local MAX_RESUMES_IN_A_WALK = 8
local RESUME_RETRIES = 8
local RESUME_RETRY_FRAMES = 20
local MAX_JOURNEY_LEGS = 32

local walk = nil -- active walk, or nil
-- Where the last walk to an object ended, for Chase: the player's cell and
-- where the object stood.
local lastArrival = nil

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

-- A leg whose warp lands on the same map (Saffron Gym's pads): the map never changes,
-- so the walk has to notice the jump itself.
local function landsOnSameMap(nav, overworld, leg)
  return leg ~= nil and leg.nextMapId ~= nil and type(nav.currentMapIdOf) == "function"
    and nav:currentMapIdOf(overworld) == leg.nextMapId
end

-- For Chase, which faces an object the way a walk faces an obstacle.
AutoWalk.holdDirection = hold
AutoWalk.releaseDirection = release

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
  -- a floor whose route depends on more than cells (Fortree's spinning gates)
  if type(nav.plannedRoute) == "function" then
    local handled, planned, planError = nav:plannedRoute(goals)
    if handled then return planned, planError end
  end
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

-- The planners give their reasons for code ("no path", "regional search
-- timed out"); those were spoken as they were.  The player hears what they
-- mean; any other reason ("Not on a map") is already a sentence.
local PLANNER_REASONS = {
  ["no path"] = "none", ["no regional path"] = "none", ["no regional transition"] = "none",
  ["regional search timed out"] = "slow", ["time limit exceeded"] = "slow",
  ["node limit exceeded"] = "slow",
}
local function spokenReason(reason, label)
  local kind = PLANNER_REASONS[reason]
  if kind == "none" then return "No route to " .. tostring(label) .. " from here" end
  if kind == "slow" then return "Could not plan a route to " .. tostring(label) .. " in time" end
  return tostring(reason)
end
AutoWalk.spokenReason = spokenReason

-- The goal of this leg only works by leaving it and stepping back on (a
-- teleport pad the player stands on; thin ice, which cracks under the first
-- step and gives way under the next).  Sets the two steps; false when there
-- is no cell to step to.  A plain floor cell is preferred over more ice.
local function stepOffAndBack()
  local player, map = walk.overworld.player, walk.overworld.map
  local x, y = player.cellX, player.cellY
  local function tileAt(cx, cy)
    if type(map.cellTile) ~= "function" then return nil end
    local ok, tile = pcall(map.cellTile, map, cx, cy)
    return ok and tile or nil
  end
  local here = tileAt(x, y)
  local best
  for _, d in ipairs({ { "up", 0, -1, "down" }, { "down", 0, 1, "up" },
                       { "left", -1, 0, "right" }, { "right", 1, 0, "left" } }) do
    local nx, ny = x + d[2], y + d[3]
    local ok, walkable = pcall(map.isWalkableCell, map, nx, ny)
    -- stepping off onto another warp would leave the map on the wrong one
    local okWarp, warp = pcall(map.warpAt, map, nx, ny)
    if ok and walkable and not (okWarp and warp) then
      local plain = here == nil or tileAt(nx, ny) ~= here
      if not best or (walk.danceAtGoal and plain and not best.plain) then
        best = { nx = nx, ny = ny, off = d[1], back = d[4], plain = plain }
      end
    end
  end
  if not best then return false end
  walk.steps = {
    { fromX = x, fromY = y, x = best.nx, y = best.ny, direction = best.off },
    { fromX = best.nx, fromY = best.ny, x = x, y = y, direction = best.back },
  }
  walk.dancing = walk.danceAtGoal == true
  walk.steppingOff = true
  walk.lastX, walk.lastY, walk.still = x, y, 0
  if walk.danceText then Speech.say(walk.danceText, { interrupt = false }) end
  walk.danceAtGoal, walk.danceText = nil, nil
  return true
end

-- Off the cell, on the way back: the step off is done with.  Left in the list it sent
-- the player off again from the same cell for ever, on a warp that needs its direction
-- held to fire (Tohjo Falls' mats).
local function leftTheCell(x, y)
  local second = walk.steps[2]
  if walk.steppingOff and second and second.fromX == x and second.fromY == y then
    walk.steppingOff = nil
    table.remove(walk.steps, 1)
  end
end

-- Starts walking to the coordinator's selected object.  Returns true when
-- walking began; otherwise speaks why not.  `adapter` defaults to the running
-- game's (WorldAdapter.current), Gen 1 when none is known.
local function noteArrival()
  if walk.quiet or walk.targetType ~= "object" or type(walk.targetX) ~= "number" then return end
  local player = walk.overworld.player
  lastArrival = { id = walk.targetId, label = walk.label, map = walk.overworld.map,
    x = player.cellX, y = player.cellY,
    targetX = walk.targetX, targetY = walk.targetY }
end

-- opts (for Chase): goals replaces the selected object's cells; quiet says
-- neither the start nor the arrival.
function AutoWalk.start(nav, game, adapter, opts)
  opts = opts or {}
  local Chase = require("src.access.nav.Chase")
  if not opts.quiet and Chase.active() then return Chase.stop("Auto walk stopped") end
  local Boulders = require("src.access.nav.BoulderWalk")
  if not opts.quiet and Boulders.active() then return Boulders.stop("Auto walk stopped") end
  local Switches = require("src.access.nav.SwitchWalk")
  if not opts.quiet and Switches.active() then return Switches.stop("Auto walk stopped") end
  local Ice = require("src.access.nav.IceWalk")
  if not opts.quiet and Ice.active() then return Ice.stop("Auto walk stopped") end
  if walk then return AutoWalk.stop("Auto walk stopped") end
  adapter = adapter or WorldAdapter.current() or WorldAdapter.gen1
  local tooDark = type(nav.darkRefusal) == "function" and nav:darkRefusal()
  if tooDark then
    Speech.say(tooDark, { interrupt = true })
    return false
  end
  local followed = lastArrival and not opts.quiet
    and Chase.relink(nav, lastArrival.id, lastArrival.label) or nil
  local item, goals, interaction, _, overworld = nav:selectedRouteGoals()
  -- a walk to given cells does not need the selection: a hole just filled has left it
  if not item and opts.goals then
    item, overworld = { id = "cells", label = opts.label or "", type = "cells" }, nav:worldForCommand()
  end
  if not item then
    Speech.say(goals or "Select an object from the list", { interrupt = true })
    return false
  end
  if not opts.quiet and require("src.access.nav.BoulderWalk").tryStone(nav, game, adapter, item, overworld) then
    return true
  end
  -- it ran off while the player stood beside it: keep after it
  local seen = lastArrival
  -- (the same object, or the one that took over its name when its id left the
  -- list: another object that merely shares a name, like a second Rocket, is not)
  if not opts.quiet and seen and item.id == followed and seen.map == overworld.map
     and seen.x == overworld.player.cellX and seen.y == overworld.player.cellY
     and type(item.x) == "number" and type(item.y) == "number"
     and math.abs(item.x - seen.targetX) + math.abs(item.y - seen.targetY) >= 2 then
    lastArrival = nil
    return Chase.start(nav, game, adapter, item, overworld)
  end
  lastArrival = nil
  if opts.goals then goals = opts.goals end
  -- a walk to given cells on another floor (SwitchWalk's way to a switch up there)
  local presetJourney = opts.journeyTo
  if type(goals) ~= "table" or #goals == 0 then
    Speech.say("No route to " .. tostring(item.label), { interrupt = true })
    return false
  end
  -- an Area target is on another map: walk the cross-map journey leg by
  -- leg (Navigation:regionalNextLeg), re-planning on every new map
  local journey, final, stopText, danceLeg = nil, true, nil, nil
  if presetJourney then
    local leg = nav:regionalNextLeg(presetJourney)
    if not leg then return false end
    journey, goals = presetJourney, leg.goals
    final = leg.final == true or leg.stopAtGoal == true
    stopText = leg.stopAtGoal and leg.stopText or nil
    danceLeg = leg
  end
  if item.type == "area" and not opts.goals then
    journey = { targetMapId = item.mapId, targetGoals = goals }
    local leg, legErr = nav:regionalNextLeg(journey)
    if not leg then
      -- this floor's own puzzle may be what closes the way
      if not opts.quiet then
        local Boulders = require("src.access.nav.BoulderWalk")
        if Boulders.tryJourney(nav, game, adapter, item, overworld) then return true end
        if Boulders.tryArea(nav, game, adapter, item, overworld) then return true end
        if require("src.access.nav.SwitchWalk").tryStart(nav, game, adapter, item, overworld) then return true end
      end
      Speech.say(spokenReason(legErr or "no regional path", item.label), { interrupt = true })
      return false
    end
    goals, final = leg.goals, leg.final == true or leg.stopAtGoal == true
    stopText = leg.stopAtGoal and leg.stopText or nil
    danceLeg = leg
  end
  local result, findErr = findRoute(nav, goals)
  -- Thin ice comes before any way round through a fall (Sootopolis Gym)
  if not result and not journey and not opts.goals and not opts.quiet
     and require("src.access.nav.IceWalk").tryStart(nav, game, adapter, item, goals, overworld) then
    return true
  end
  -- A target on this map with no way here may have one through other maps
  -- (Seafoam's floors): the coordinator that says so (FireRed) walks it as
  -- a journey, the same answer guided navigation gives.
  if not result and not journey and not opts.goals and nav.autoWalkJourneys and type(nav.currentMapIdOf) == "function" then
    local attempt = { targetMapId = nav:currentMapIdOf(overworld), targetGoals = goals }
    local leg, legErr = nav:regionalNextLeg(attempt)
    if leg and not leg.final then
      journey, goals = attempt, leg.goals
      final = leg.stopAtGoal == true
      stopText = leg.stopAtGoal and leg.stopText or nil
      danceLeg = leg
      result, findErr = findRoute(nav, goals)
    elseif not leg and legErr and not PLANNER_REASONS[legErr] then
      findErr = legErr -- "Needs Surf": what guided navigation would name
    end
  end
  if not result then
    if not opts.quiet then
      local BoulderWalk = require("src.access.nav.BoulderWalk")
      -- a journey planned with the boulders aside can have no way off this floor yet
      -- (FireRed's Victory Road 2F): the floor comes first, as when no leg was found
      if not journey and BoulderWalk.tryStart(nav, game, adapter, item, goals, overworld) then return true end
      if BoulderWalk.tryJourney(nav, game, adapter, item, overworld) then return true end
      if journey and BoulderWalk.tryArea(nav, game, adapter, item, overworld) then return true end
      if require("src.access.nav.SwitchWalk").tryStart(nav, game, adapter, item, overworld) then
        return true
      end
    end
    if not opts.quiet then
      -- a coordinator may name what is missing ("Needs Surf")
      local needs = type(nav.routeNeeds) == "function" and nav:routeNeeds(goals) or nil
      Speech.say(needs and (tostring(item.label) .. ": " .. needs)
        or spokenReason(findErr or "no path", item.label), { interrupt = true })
    end
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
    -- an object target is looked up again after a pause (refreshTarget)
    targetId = item.id, targetType = item.type,
    targetX = item.x, targetY = item.y,
    quiet = opts.quiet,
    -- the map a warp target leads to: reaching it is the arrival even when
    -- a fast game speed moved the player past the last step between two
    -- updates (several tiles per real frame at 200X)
    -- (a walk that ends at a panel is not going through that warp)
    targetMapId = not stopText and (opts.targetMapId
      or (not opts.goals and item.type == "warp" and item.destinationMapId)) or nil,
    interaction = interaction,
    nav = nav,
    goals = goals,
    journey = journey,
    final = final,
    stopText = stopText,
    danceAtGoal = danceLeg and danceLeg.danceAtGoal or nil,
    danceText = danceLeg and danceLeg.danceText or nil,
    -- the way off the map on a leg that ends at a connection (Gen 2)
    edgeDir = danceLeg and danceLeg.edgeDirection or nil,
    sameMapLeg = landsOnSameMap(nav, overworld, danceLeg),
    legs = 0,
    lastX = player.cellX, lastY = player.cellY,
    still = 0,
  }
  if #result.steps == 0 and journey and not final then
    -- standing on the way onto the next map: take it, not "is here"
    Speech.say("Walking to " .. tostring(item.label), { interrupt = true })
    if walk.edgeDir then
      walk.pushDir, walk.pushFrames = walk.edgeDir, 0
      return true
    end
    if stepOffAndBack() then return true end
    AutoWalk.stop("No route to " .. tostring(item.label))
    return false
  end
  if #result.steps == 0 then
    -- already in place: still say which way to face (Yellow's Pikachu is
    -- usually right behind the player), as an arrival would
    if stopText then
      AutoWalk.stop(stopText)
      return true
    end
    if walk.danceAtGoal then
      Speech.say("Walking to " .. tostring(item.label), { interrupt = true })
      if stepOffAndBack() then return true end
    end
    -- the journey's way on is the stairs or mat underfoot (just came through them): a mat
    -- wants its press, stairs a step off and back on; this is not "here" yet
    if journey and not final and not opts.quiet then
      local press = type(nav.warpPressDirection) == "function"
        and select(2, pcall(nav.warpPressDirection, nav, overworld, player.cellX, player.cellY)) or nil
      if type(press) == "string" then
        walk.pushDir, walk.pushFrames = press, 0
      elseif not stepOffAndBack() then
        AutoWalk.stop("Could not go through, auto walk stopped")
        return false
      end
      Speech.say("Walking to " .. tostring(item.label), { interrupt = true })
      return true
    end
    -- standing on an exit mat that fires when pressed (just came in, and want out again)
    if walk.targetMapId and type(nav.warpPressDirection) == "function" then
      local okPress, press = pcall(nav.warpPressDirection, nav, overworld, player.cellX, player.cellY)
      if okPress and press then
        walk.pushDir, walk.pushFrames = press, 0
        if not opts.quiet then Speech.say("Walking to " .. tostring(item.label), { interrupt = true }) end
        return true
      end
    end
    -- standing on a door or stair the player just came out of: it fires on stepping back on
    if walk.targetMapId and (nav.stepBackOntoWarps or nav.stepOffWarpTargets) and stepOffAndBack() then
      walk.steppedBack = true
      if not opts.quiet then Speech.say("Walking to " .. tostring(item.label), { interrupt = true }) end
      return true
    end
    local text = tostring(item.label) .. " is here"
    local hint = interaction and result.goal
      and interaction[tostring(result.goal.x) .. "," .. tostring(result.goal.y)]
    if hint then text = text .. ". " .. tostring(hint) end
    noteArrival()
    AutoWalk.stop(not opts.quiet and text or nil)
    return true
  end
  if not opts.quiet then Speech.say("Walking to " .. tostring(item.label), { interrupt = true }) end
  return true
end

-- Whether a route to these cells exists right now (SwitchWalk).
function AutoWalk.routeExists(nav, goals)
  return (findRoute(nav, goals)) ~= nil
end

local function arrivalText()
  noteArrival()
  if walk.quiet then return nil end
  -- a leg that ends where the player must act: an elevator's panel, thin
  -- ice to crack (Navigation:regionalNextLeg's stopAtGoal)
  if walk.stopText then return walk.stopText end
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

-- The top itself is a battle.  FireRed's battle is a module, not a stack
-- state: its adapter reports a battle marker as the top instead, and a
-- trainer pause that only looked at the stack waited for ever after the
-- battle (WorldAdapter.gen3.top).
local function battleTop(top)
  local adapter = walk and walk.adapter or WorldAdapter.gen1
  return adapter.isBattle ~= nil and adapter.isBattle(top) == true
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

-- A person or other object can move while the walk is paused (a scene walks
-- them over: Radio Tower 5F's imposter director comes to the player, battles
-- and stays beside them, and the old goals beyond him were unreachable,
-- "Cannot reach Gentleman").  Takes the target's cells again from where it
-- is now.  False when it is no longer on the map.
local function refreshTarget()
  if walk.quiet then return true end -- Chase and BoulderWalk chose these cells
  if walk.journey or walk.targetType ~= "object" or not walk.targetId then return true end
  local nav = walk.nav
  if type(nav.captureWorld) ~= "function" then return true end
  local ok, snapshot = pcall(nav.captureWorld, nav, nav.browseFilter)
  if not (ok and type(snapshot) == "table") then return true end -- cannot tell: keep the goals
  local present = false
  for _, item in ipairs(snapshot.browse or {}) do
    if item.id == walk.targetId then present = true break end
  end
  if not present then return false end
  local okGoals, item, goals, interaction = pcall(nav.selectedRouteGoals, nav)
  if okGoals and type(item) == "table" and item.id == walk.targetId
     and type(goals) == "table" and #goals > 0 then
    walk.goals, walk.interaction = goals, interaction
  end
  return true
end

-- The walk ends and this floor's puzzle takes over, when it has one that helps.
local function journeyPuzzle()
  local nav, game, adapter, overworld = walk.nav, walk.game, walk.adapter, walk.overworld
  local item = nav:selectedRouteGoals()
  if type(item) ~= "table" then return false end
  local saved = walk
  release(walk.input, walk.held)
  walk = nil
  local Boulders = require("src.access.nav.BoulderWalk")
  if Boulders.tryJourney(nav, game, adapter, item, overworld)
     or Boulders.tryArea(nav, game, adapter, item, overworld)
     or require("src.access.nav.SwitchWalk").tryStart(nav, game, adapter, item, overworld) then
    return true
  end
  walk = saved
  return false
end

-- Recomputes the route from where the player now stands to the target.
local function resume(quiet)
  if not refreshTarget() then
    return AutoWalk.stop(tostring(walk.label) .. " is gone, auto walk stopped")
  end
  local result = findRoute(walk.nav, walk.goals)
  if not result then
    -- after a scene someone can still be walking off through the only way (the Cerulean
    -- rival, Silph Co.'s): give it a moment before giving up
    if walk.paused and (walk.resumeRetries or 0) < RESUME_RETRIES then
      walk.resumeRetries = (walk.resumeRetries or 0) + 1
      walk.retryIn = RESUME_RETRY_FRAMES
      return
    end
    -- a floor of a journey closed by boulders or switches: its puzzle comes first
    if (walk.journey or walk.nav.puzzlesOnResume) and not walk.quiet and journeyPuzzle() then return end
    return AutoWalk.stop("Cannot reach " .. tostring(walk.label) .. ", auto walk stopped")
  end
  walk.retryIn = nil
  local player = walk.overworld.player
  walk.steps, walk.goal = result.steps, result.goal or walk.goal
  walk.paused, walk.expectBattle, walk.battleSeen = nil, nil, nil
  walk.lastX, walk.lastY, walk.still = player.cellX, player.cellY, 0
  if #walk.steps == 0 then
    if walk.journey and not walk.final then
      if walk.edgeDir then
        walk.pushDir, walk.pushFrames = walk.edgeDir, 0
        return
      end
      -- standing on the warp this leg needs (a teleport pad lands you on a
      -- pad): pads fire on stepping onto them, so step off and back on
      if stepOffAndBack() then return end
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
  -- a plan that keeps changing its mind between maps (one floor's load
  -- state read wrong) must not walk for ever
  walk.legs = (walk.legs or 0) + 1
  if walk.legs > MAX_JOURNEY_LEGS then
    return AutoWalk.stop("No route from here to " .. tostring(walk.label) .. ", auto walk stopped")
  end
  -- a floor still dark for lack of Flash ends the walk (decision 37)
  local tooDark = type(walk.nav.darkRefusal) == "function" and walk.nav:darkRefusal()
  if tooDark then return AutoWalk.stop(tooDark) end
  local leg, err = walk.nav:regionalNextLeg(walk.journey)
  if not leg then
    if not walk.quiet and journeyPuzzle() then return end
    if err and not PLANNER_REASONS[err] then return AutoWalk.stop(tostring(err) .. ", auto walk stopped") end
    return AutoWalk.stop("No route from here to " .. tostring(walk.label) .. ", auto walk stopped")
  end
  -- a floor as the target: being on it is the arrival (a step across a connection can still
  -- be finishing, and the cell it started from is not one to walk back to)
  if leg.arrived then return AutoWalk.stop(arrivalText()) end
  walk.map, walk.goals, walk.final = walk.overworld.map, leg.goals, leg.final == true or leg.stopAtGoal == true
  walk.stopText = leg.stopAtGoal and leg.stopText or nil
  if walk.stopText then walk.targetMapId = nil end
  walk.danceAtGoal, walk.danceText = leg.danceAtGoal or nil, leg.danceText or nil
  walk.dancing = nil
  walk.edgeDir = leg.edgeDirection
  walk.sameMapLeg = landsOnSameMap(walk.nav, walk.overworld, leg)
  walk.awaitingMap, walk.reroutes, walk.doorTries = nil, nil, nil
  walk.pushDir, walk.pushFrames = nil, nil
  return resume(true)
end

local function nav_stepsBack(state)
  return state.nav.stepBackOntoWarps == true and not state.steppedBack
end

-- A walk to a pad on this same map (Saffron Gym, Silph Co.) has arrived when the player
-- jumps: the map never changes, and it used to re-plan from the far side of the wall.
local function landedOnThisMap(x, y)
  local map = walk.overworld.map
  local mapId = map.id or (map.def and map.def.id)
  if not walk.targetMapId or walk.targetMapId ~= mapId or walk.journey then return false end
  return math.abs(x - walk.lastX) + math.abs(y - walk.lastY) > 1
end

local function nav_replans(nav) return nav.replanJourneyOffRoute == true end

-- Per frame, after upstream's update.  `top` is the top screen.
function AutoWalk.update(top)
  if not walk then return end
  local overworld = walk.overworld
  local player = overworld.player
  if walk.awaitingMap then
    if not onMap(top) or transitioning() then return end
    if overworld.map == walk.map and not walk.sameMapLeg then return end
    return nextLeg()
  end
  if walk.teleported and onMap(top) and not transitioning() then return AutoWalk.stop(arrivalText()) end
  if walk.paused then
    local stack = package.loaded["src.core.StateStack"]
    if battleOnStack(stack) or battleTop(top) then walk.battleSeen = true end
    if not onMap(top) then return end
    if transitioning() then return end
    if overworld.map ~= walk.map then
      -- on a journey a new map is the next leg (FireRed's thin ice drops the
      -- player while the walk waits on the game's own script)
      if walk.journey then return nextLeg() end
      return AutoWalk.stop("Auto walk stopped")
    end
    if walk.expectBattle and not walk.battleSeen then return end -- trainer still walking over
    if walk.retryIn then
      walk.retryIn = walk.retryIn - 1
      if walk.retryIn > 0 then return end
      return resume()
    end
    -- a wild battle on the way to the water: being asked again there is no refusal
    if walk.battleSeen then walk.fieldMoveAt = nil end
    -- the walk's own Surf or Cut: not the game turning the player back, and "got on" has
    -- said it (Route 12's walkway takes Surf many times, which used to end the walk)
    if walk.ownFieldMove then
      walk.ownFieldMove = nil
      return resume(true)
    end
    -- battles, card-key door messages and other game-caused screens: carry
    -- on, unless the game keeps sending the player back to the same cell
    local key = tostring(player.cellX) .. "," .. tostring(player.cellY)
    walk.resumesAt = walk.resumesAt or {}
    walk.resumesAt[key] = (walk.resumesAt[key] or 0) + 1
    -- (a guard can also turn the player back to a different cell each time, Route 18's gate)
    walk.resumesTotal = (walk.resumesTotal or 0) + 1
    if walk.resumesAt[key] >= MAX_RESUMES_AT_CELL or (not walk.journey and not walk.battleSeen
        and walk.resumesTotal >= MAX_RESUMES_IN_A_WALK) then
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
    -- ...unless it is the game's text, which can turn the player back (Route 16's gate
    -- guard on a player with no Bicycle): that pauses, as anywhere else
    local TextBox = package.loaded["src.render.TextBox"]
    local isText = TextBox and type(top) == "table" and getmetatable(top) == TextBox
    if last and player.cellX == last.x and player.cellY == last.y and not (isText and walk.targetMapId) then
      if walk.journey and not walk.final then
        release(walk.input, walk.held)
        walk.held, walk.awaitingMap = nil, true
        return
      end
      return AutoWalk.stop(arrivalText())
    end
    -- anything else pauses; the walk resumes when the map returns
    AutoWalk.pause(false)
    if battleOnStack(package.loaded["src.core.StateStack"]) or battleTop(top) then
      walk.battleSeen = true
    end
    return
  end
  -- spinner slides, door or stair transitions (Gen 2 also ice slides,
  -- currents and the step off an arrival door) move the player on their
  -- own: let go of the direction and wait
  if transitioning() then
    release(walk.input, walk.held)
    walk.held = nil
    if not walk.teleported then
      -- a pad's jump shows up here first, seen from where the walk last stood
      walk.teleported = landedOnThisMap(player.cellX, player.cellY)
    end
    walk.lastX, walk.lastY, walk.still = player.cellX, player.cellY, 0
    return
  end
  if walk.teleported then return AutoWalk.stop(arrivalText()) end
  if walk.tapA then
    -- release the one-frame A press used on a card-key door or field move
    walk.input.state.a = false
    walk.tapA = nil
  end
  local x, y = player.cellX, player.cellY
  if landedOnThisMap(x, y) then return AutoWalk.stop(arrivalText()) end
  leftTheCell(x, y)
  if x ~= walk.lastX or y ~= walk.lastY then
    walk.lastX, walk.lastY, walk.still = x, y, 0
  elseif not player.moving then
    walk.still = walk.still + 1
    -- someone wandered into the way: plan around them if there is a way round
    if walk.still == REROUTE_FRAMES and walk.pushDir == nil and not walk.tapA then
      local around = findRoute(walk.nav, walk.goals)
      if around and #around.steps > 0 then
        walk.steps, walk.goal = around.steps, around.goal or walk.goal
        release(walk.input, walk.held)
        walk.held = nil
      end
    end
    if walk.still > STUCK_FRAMES then
      -- they stayed: try again from here, a few times per walk
      walk.reroutes = (walk.reroutes or 0) + 1
      if walk.reroutes > MAX_BLOCKED_TRIES then return AutoWalk.stop("Blocked, auto walk stopped") end
      return resume(true)
    end
  end
  -- A walk that must end exactly on its goal lets go as soon as the last step is under
  -- way: the step finishes by itself, and the game starts the next one in the tick it
  -- lands, while the direction is held (past the pushing cell on Blackthorn 2F, for ever).
  local lastStep = walk.steps[#walk.steps]
  if walk.quiet and player.moving and lastStep and walk.held
     and ((x == lastStep.fromX and y == lastStep.fromY) or (x == lastStep.x and y == lastStep.y)) then
    release(walk.input, walk.held)
    walk.held = nil
  end
  if player.moving then return end -- keep the held direction mid-step
  if walk.pushDir and walk.sameMapLeg then
    local last = walk.steps[#walk.steps]
    if not (last and last.x == x and last.y == y) then
      walk.pushDir = nil
      return nextLeg()
    end
  end
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
        if walk.danceAtGoal and stepOffAndBack() then return end
        if walk.dancing then
          -- back on the thin ice: it gives way; wait for the game's fall
          release(walk.input, walk.held)
          walk.held = nil
          return
        end
        walk.pushDir, walk.pushFrames = walk.edgeDir or press or last.direction, 0
        return
      end
      if press and walk.targetMapId then
        walk.pushDir, walk.pushFrames = press, 0
        return
      end
      -- a step from one warp tile onto another does not fire it (Gen 1's standing-on-warp bit)
      if walk.targetMapId and nav_stepsBack(walk) and stepOffAndBack() then
        walk.steppedBack = true
        return
      end
      return AutoWalk.stop(arrivalText())
    end
    if walk.journey and nav_replans(walk.nav) then return nextLeg() end
    -- the pad took the player across the map: on to the next leg
    if walk.sameMapLeg then return nextLeg() end
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
  -- A walk that must end exactly on its goal (BoulderWalk's pushing cell, Chase's
  -- side) takes its last steps at 1X: at a fast speed one held direction carried
  -- the player two cells, past the goal and back for ever (Blackthorn 2F).
  walk.turning = nil
  if walk.quiet and (step == walk.steps[#walk.steps] or step == walk.steps[#walk.steps - 1]) then
    walk.turning = true
  end
  -- A ledge hop at 1X too: at a fast speed the direction still held on landing hops the
  -- next ledge in the same frame (Route 4's steps, past the turn, with no way back up).
  if step.kind == "ledge" then walk.turning = true end
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
    walk.ownFieldMove = true
    walk.still = 0
    -- Gen 1 has no A press for field moves: the coordinator calls what the party menu calls
    if action.use then
      if not action.use() then
        return AutoWalk.stop(tostring(action.failText) .. ". " .. tostring(action.hint))
      end
      return
    end
    table.insert(walk.input.pressQueue, "a")
    walk.input.state.a = true
    walk.tapA = true
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
  leftTheCell(x, y)
  for _, s in ipairs(walk.steps) do
    if s.fromX == x and s.fromY == y then
      -- a field move on this step starts with an A press: stop here and let
      -- the update face the obstacle and press.  A ledge's hop is left to the update as
      -- well, which takes it at 1X.
      if s.kind == "ledge" or (type(walk.nav.stepInteraction) == "function"
         and walk.nav:stepInteraction(walk.overworld, s)) then
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
  if (walk.targetMapId or (walk.journey and not walk.final)) and not walk.dancing and not walk.danceAtGoal
     and last and last.x == x and last.y == y then
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

-- Called from upstream's map.entered event, inside the game's step.  At a fast speed a
-- whole door transition fits between two updates, and a direction still held on landing
-- takes the stairs straight back (Celadon Mart, Silph Co.; the walk then said "Arrived"
-- on the floor it started from).  A pad on one floor counts as arrival here too.
function AutoWalk.mapEntered(mapId)
  if not walk then return end
  release(walk.input, walk.held)
  walk.held = nil
  if walk.targetMapId and walk.targetMapId == mapId and not walk.journey then walk.teleported = true end
end

-- For scripted debugging: the active walk's plan (read-only use).
function AutoWalk._state() return walk end

function AutoWalk._lastArrival() return lastArrival end

function AutoWalk._resetForTests() walk, lastArrival = nil, nil end

return AutoWalk
