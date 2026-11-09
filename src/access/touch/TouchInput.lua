-- Touch gestures to game input and navigation (decision 66).
--
-- On Android an accessibility service passes the game screen's touches to
-- the game while TalkBack stays on, so the game receives ordinary
-- love.touchpressed / touchmoved / touchreleased.  src/access/init.lua hands
-- them here before upstream; while TOUCH GESTURES is on and a game is
-- running, every touch is consumed, so upstream's on-screen buttons
-- (src/core/TouchControls.lua) never also fire.  Turned off, upstream gets
-- its touches back.  The launcher and other screens main.lua shows without
-- a game keep their touches either way.
--
-- Gestures (Gestures.lua recognises them):
--   (Halves: portrait top / bottom; landscape right navigates, left moves.)
--   On the map, top half (the navigation half):
--     swipe left / right   previous / next navigation point in the category
--     swipe up / down      previous / next category
--     (decision 23's controller modifier plus D-pad; other gestures there do nothing)
--   On the map, bottom half, and the whole screen everywhere else
--   (menus, battles, dialogue):
--     swipe                D-pad: one step on the map (see walking modes), one
--                          press in menus
--     double tap           A
--     two-finger double tap B
--     three-finger double tap START
--     three-finger tap     SELECT
--     two-finger turn      clockwise starts auto-walk to the selected point
--                          (as the left stick click), counterclockwise stops it
--   While any walk runs, any other gesture stops it, as any controller button does.
--
-- TOUCH WALKING (src/access/Settings.lua):
--   MANUAL  each swipe is one step.
--   HYBRID  the game says the route's next straight leg ("18 up"); a swipe
--           that way walks the whole leg (auto-walk, quietly, to the leg's
--           end), then the next leg is said.  A swipe any other way takes
--           one step that way and plans again from there.
--   AUTO    swipes still step one at a time; the two-finger turn is the main
--           way to move.  (It behaves as MANUAL; the turn works in every mode.)
-- Holding a direction is not decided and not implemented.
--
-- Buttons go in the way scripted drivers press them: on upstream's Input
-- (one module shared by all three engines, with the same button names) as
-- this layer's own source ("access_touch"), held for TAP_FRAMES updates and
-- released by TouchInput.update, which runs after the game's update.

local Gestures = require("src.access.touch.Gestures")

local TouchInput = {}

local SOURCE = "access_touch"
-- a menu press is held for this many game updates, as the drivers' tap
local TAP_FRAMES = 2
-- a step that has not started by now was blocked (or only turned the player)
local STEP_MAX_FRAMES = 24
-- quick swipes queue up to this many steps
local STEP_QUEUE_MAX = 4

local NAV_SWIPES = {
  up = "previous_item_filter", down = "next_item_filter",
  left = "previous_map_item", right = "next_map_item",
}

-- fingers .. ":" .. taps -> button
local TAP_BUTTONS = {
  ["1:2"] = "a", ["2:2"] = "b", ["3:2"] = "start", ["3:1"] = "select",
}

-- ------------------------------------------------------------ dependencies
-- Real modules by default; tests replace them with TouchInput.configure.
local deps = {}
local DEFAULTS = {
  speech = function() return require("src.access.Speech") end,
  settings = function() return require("src.access.Settings") end,
  currentGame = function() return require("src.access.CurrentGame") end,
  nav = function() return require("src.access.nav") end,
  autoWalk = function() return require("src.access.nav.AutoWalk") end,
  clock = function()
    return function() return love.timer.getTime() end
  end,
  size = function()
    return function() return love.graphics.getDimensions() end
  end,
}

local function dep(name)
  if deps[name] == nil then deps[name] = DEFAULTS[name]() end
  return deps[name]
end

-- ------------------------------------------------------------ state
local recogniser = nil
local owned = {}      -- touch ids whose press was consumed here
local taps = {}       -- buttons being held: { input, button, frames }
local step = nil      -- the single step under way
local stepQueue = {}  -- swiped directions waiting for it
local hybrid = { legWalk = false, announce = nil }

local function rec()
  if not recogniser then
    recogniser = Gestures.new({ size = function() return dep("size")() end })
  end
  return recogniser
end

-- ------------------------------------------------------------ input
local function hold(input, button)
  input.sources = input.sources or {}
  local sources = input.sources[button]
  if not sources then
    sources = {}
    input.sources[button] = sources
  end
  if not sources[SOURCE] then
    sources[SOURCE] = true
    input.pressQueue = input.pressQueue or {}
    table.insert(input.pressQueue, button)
  end
  input.state = input.state or {}
  input.state[button] = true
end

local function release(input, button)
  if not (input and button) then return end
  local sources = input.sources and input.sources[button]
  if sources then
    sources[SOURCE] = nil
    if next(sources) == nil then input.state[button] = false end
  elseif input.state then
    input.state[button] = false
  end
end

-- Presses a button for TAP_FRAMES game updates.
local function tap(input, button)
  if not input then return end
  hold(input, button)
  taps[#taps + 1] = { input = input, button = button, frames = TAP_FRAMES }
end

-- ------------------------------------------------------------ context
local function say(text, interrupt)
  if text then dep("speech").say(text, { interrupt = interrupt ~= false }) end
end

-- The running game while gestures are on, or nil.
local function liveGame()
  local game = dep("currentGame").live()
  if not game then return nil end
  local ok, on = pcall(dep("settings").touchGestures, game)
  if not (ok and on) then return nil end
  return game
end

-- True while gestures own every touch (TOUCH GESTURES on and a game running).
-- Upstream's on-screen buttons are hidden then (src/access/init.lua): the owner
-- asked for them gone, since they no longer take any touch.
function TouchInput.ownsTouches()
  return liveGame() ~= nil
end

-- coordinator, adapter, game and whether the player is free on the map
local function navContext()
  local ok, nav, adapter, game = pcall(dep("nav").context)
  if not (ok and nav and adapter and game) then return nil end
  local okMap, onMap = pcall(adapter.onMap, game)
  return nav, adapter, game, okMap and onMap == true
end

local function world(nav)
  local ok, overworld = pcall(nav.worldForCommand, nav)
  if ok and type(overworld) == "table" and type(overworld.player) == "table" then return overworld end
  return nil
end

local function walkingMode(game)
  local ok, mode = pcall(dep("settings").touchWalking, game)
  return ok and mode or "manual"
end

-- ------------------------------------------------------------ hybrid legs
-- The route's first straight run of steps: { direction, count, x, y }.
function TouchInput.firstLeg(steps)
  if type(steps) ~= "table" or not steps[1] then return nil end
  local leg = { direction = steps[1].direction, count = 0 }
  for _, s in ipairs(steps) do
    if s.direction ~= leg.direction then break end
    leg.count, leg.x, leg.y = leg.count + 1, s.x, s.y
  end
  return leg
end

-- What hybrid walking says next: "18 up", the arrival, or why there is no route.
function TouchInput.legText(plan, reason)
  if not plan then return reason end
  local leg = TouchInput.firstLeg(plan.steps)
  if leg then return tostring(leg.count) .. " " .. tostring(leg.direction) end
  local text = tostring(plan.item and plan.item.label or "Target") .. " is here"
  local goal = plan.goal
  local hint = plan.interaction and goal
    and plan.interaction[tostring(goal.x) .. "," .. tostring(goal.y)]
  if hint then text = text .. ". " .. tostring(hint) end
  if plan.connection then text = text .. ". " .. tostring(plan.connection) end
  return text
end

local function plan(nav)
  local ok, result, reason = pcall(dep("autoWalk").plan, nav)
  if not ok then return nil, nil end
  return result, reason
end

local function announceLeg(nav, interrupt)
  local result, reason = plan(nav)
  say(TouchInput.legText(result, reason), interrupt)
end

-- ------------------------------------------------------------ steps
local function finishStep()
  local done = step
  step = nil
  if done and done.held then release(done.input, done.held) end
  if done and done.announce then hybrid.announce = hybrid.announce or { interrupt = true } end
end

local function startStep(entry)
  local nav, _, game, onMap = navContext()
  local overworld = nav and onMap and world(nav)
  if not overworld then return false end
  local player = overworld.player
  step = {
    input = game.input, direction = entry.direction, held = entry.direction,
    announce = entry.announce, frames = 0,
    startX = player.cellX, startY = player.cellY, map = overworld.map,
  }
  hold(game.input, entry.direction)
  return true
end

local function queueStep(direction, announce)
  if #stepQueue >= STEP_QUEUE_MAX then return end
  stepQueue[#stepQueue + 1] = { direction = direction, announce = announce }
  if not step then
    local entry = table.remove(stepQueue, 1)
    startStep(entry)
  end
end

local function updateStep()
  if not step then
    if stepQueue[1] then startStep(table.remove(stepQueue, 1)) end
    return
  end
  step.frames = step.frames + 1
  local nav, _, _, onMap = navContext()
  local overworld = nav and onMap and world(nav)
  if not overworld then
    -- a screen opened (a sign, a trainer, a battle): the step is over
    stepQueue = {}
    return finishStep()
  end
  local player = overworld.player
  local moved = player.cellX ~= step.startX or player.cellY ~= step.startY
    or overworld.map ~= step.map
  if step.held then
    -- under way: the step finishes by itself.  Turning on the spot (Gen 2
    -- and 3 turn first when the player faced elsewhere) is not the step.
    local walking = player.moving and (player.facing == nil or player.facing == step.direction)
    if moved or walking then
      release(step.input, step.held)
      step.held = nil
    elseif step.frames >= STEP_MAX_FRAMES then
      return finishStep() -- blocked: the game's own bump sound said so
    end
    return
  end
  if not player.moving then finishStep() end
end

-- From upstream's world.stepped event, inside the game's step as the player
-- lands on a cell and before the next step reads input: letting go here keeps
-- one swipe to one cell at any game speed.
function TouchInput.stepped()
  if not (step and step.held) then return end
  release(step.input, step.held)
  step.held = nil
  local _, adapter, game = navContext()
  if adapter and adapter.afterSteer then pcall(adapter.afterSteer, game) end
end

-- ------------------------------------------------------------ gestures
local function hybridSwipe(direction, nav, adapter, game)
  if step or stepQueue[1] then return queueStep(direction, true) end
  local result = plan(nav)
  local leg = result and TouchInput.firstLeg(result.steps)
  if leg and leg.direction == direction then
    local autoWalk = dep("autoWalk")
    local ok, started = pcall(autoWalk.start, nav, game, adapter, {
      goals = { { x = leg.x, y = leg.y } }, quiet = true,
      label = result.item and result.item.label,
    })
    if ok and started and autoWalk.active() then
      hybrid.legWalk = true
      return
    end
  end
  -- the wrong way (owner's choice): one step, then plan again from there
  queueStep(direction, true)
end

function TouchInput.perform(gesture)
  local game = dep("currentGame").live()
  if not game then return end
  local nav, adapter, navGame, onMap = navContext()
  if not nav then onMap = false end
  local zone = (onMap and gesture.half == "top") and "top" or "bottom"
  local clockwise = gesture.kind == "rotate" and gesture.direction == "clockwise"

  -- a running walk stops on any gesture but the one that starts walks
  if onMap and dep("nav").walking() then
    if not clockwise then
      dep("nav").stopWalks()
      hybrid.legWalk = false
    end
    return
  end

  if zone == "top" then
    if gesture.kind == "swipe" and gesture.fingers == 1 then
      pcall(nav.handleCommand, nav, NAV_SWIPES[gesture.direction])
      -- after the point's own announcement, its first leg
      if walkingMode(game) == "hybrid" then announceLeg(nav, false) end
    end
    return
  end

  if gesture.kind == "swipe" then
    if gesture.fingers ~= 1 then return end
    if not onMap then return tap(game.input, gesture.direction) end
    if walkingMode(game) == "hybrid" then
      return hybridSwipe(gesture.direction, nav, adapter, navGame)
    end
    return queueStep(gesture.direction, false)
  end

  if gesture.kind == "tap" then
    local button = TAP_BUTTONS[tostring(gesture.fingers) .. ":" .. tostring(gesture.taps)]
    if button then
      stepQueue = {}
      tap(game.input, button)
    end
    return
  end

  if gesture.kind == "rotate" and onMap then
    if clockwise then
      stepQueue = {}
      pcall(dep("autoWalk").start, nav, navGame, adapter)
    elseif not dep("nav").stopWalks() then
      say("Not walking", true)
    end
  end
end

local function performAll(gestures)
  for _, gesture in ipairs(gestures) do TouchInput.perform(gesture) end
end

-- ------------------------------------------------------------ love callbacks
-- Each returns true when the touch is consumed.
function TouchInput.touchpressed(id, x, y)
  if not liveGame() then return false end
  owned[id] = true
  performAll(rec():pressed(id, x, y, dep("clock")()))
  return true
end

function TouchInput.touchmoved(id, x, y)
  if not owned[id] then return false end
  performAll(rec():moved(id, x, y, dep("clock")()))
  return true
end

function TouchInput.touchreleased(id, x, y)
  if not owned[id] then return false end
  owned[id] = nil
  performAll(rec():released(id, x, y, dep("clock")()))
  return true
end

-- Every frame, after the game's update: releases taps, runs steps, reports
-- waiting single taps, and says hybrid's next leg once the player stands still.
function TouchInput.update()
  for i = #taps, 1, -1 do
    local held = taps[i]
    held.frames = held.frames - 1
    if held.frames <= 0 then
      release(held.input, held.button)
      table.remove(taps, i)
    end
  end
  if recogniser then performAll(recogniser:update(dep("clock")())) end
  updateStep()

  local autoWalk = dep("autoWalk")
  if hybrid.legWalk and not autoWalk.active() then
    hybrid.legWalk = false
    -- after any reason the walk gave for stopping
    hybrid.announce = { interrupt = false }
  end
  if not hybrid.announce or step or stepQueue[1] or autoWalk.active() then return end
  local nav, adapter, game, onMap = navContext()
  if not (nav and onMap) then
    if not nav then hybrid.announce = nil end
    return
  end
  if walkingMode(game) ~= "hybrid" then hybrid.announce = nil return end
  local overworld = world(nav)
  if not overworld or overworld.player.moving then return end
  local okBusy, busy = pcall(adapter.transitioning, overworld)
  if okBusy and busy then return end
  local interrupt = hybrid.announce.interrupt
  hybrid.announce = nil
  announceLeg(nav, interrupt)
end

-- ------------------------------------------------------------ tests
function TouchInput.configure(overrides)
  for key, value in pairs(overrides or {}) do deps[key] = value end
  recogniser = nil
end

function TouchInput._resetForTests()
  for _, held in ipairs(taps) do release(held.input, held.button) end
  if step and step.held then release(step.input, step.held) end
  deps, recogniser, owned, taps, step, stepQueue = {}, nil, {}, {}, nil, {}
  hybrid = { legWalk = false, announce = nil }
end

function TouchInput._state()
  return { step = step, queue = stepQueue, taps = taps, hybrid = hybrid }
end

TouchInput.SOURCE = SOURCE
TouchInput.TAP_FRAMES = TAP_FRAMES
TouchInput.STEP_MAX_FRAMES = STEP_MAX_FRAMES

return TouchInput
