-- Touch gestures (decision 66): the recogniser (Gestures.lua) and the
-- mapping to game buttons, navigation and walking (TouchInput.lua).  Fake
-- clock, screen, game, navigation and auto-walk; no upstream screens.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness")
local check, eq = T.check, T.eq

local Gestures = require("src.access.touch.Gestures")

-- ------------------------------------------------------------ recogniser
local W, H = 1600, 2560 -- a tablet held upright
local function size() return W, H end

-- Runs a scripted stroke list and collects every gesture.
-- fingers: { { x, y, dx, dy } ... } moved by (dx, dy) over `duration`.
local function stroke(r, t, fingers, duration, steps, out, rotateDegrees)
  out = out or {}
  local function add(list) for _, g in ipairs(list) do out[#out + 1] = g end end
  for i, f in ipairs(fingers) do add(r:pressed(i, f[1], f[2], t)) end
  steps = steps or 4
  for s = 1, steps do
    local k = s / steps
    for i, f in ipairs(fingers) do
      local x, y = f[1] + (f[3] or 0) * k, f[2] + (f[4] or 0) * k
      if rotateDegrees then
        -- turn each finger about the fingers' middle
        local cx = (fingers[1][1] + fingers[2][1]) / 2
        local cy = (fingers[1][2] + fingers[2][2]) / 2
        local a = math.rad(rotateDegrees * k)
        local rx, ry = f[1] - cx, f[2] - cy
        x = cx + rx * math.cos(a) - ry * math.sin(a)
        y = cy + rx * math.sin(a) + ry * math.cos(a)
      end
      f.lx, f.ly = x, y
      add(r:moved(i, x, y, t + duration * k))
    end
  end
  for i, f in ipairs(fingers) do add(r:released(i, f.lx or f[1], f.ly or f[2], t + duration)) end
  return out
end

local function only(out, label)
  eq(#out, 1, label .. ": one gesture")
  return out[1] or {}
end

-- swipes in all four directions, bottom half, portrait
local r = Gestures.new({ size = size })
for _, case in ipairs({ { "up", 0, -300 }, { "down", 0, 300 }, { "left", -300, 0 }, { "right", 300, 0 } }) do
  local g = only(stroke(r, 10, { { 800, 2000, case[2], case[3] } }, 0.15), "swipe " .. case[1])
  eq(g.kind, "swipe", "swipe " .. case[1] .. " kind")
  eq(g.direction, case[1], "swipe " .. case[1] .. " direction")
  eq(g.half, "bottom", "swipe " .. case[1] .. " starts in the bottom half")
  eq(g.fingers, 1, "one finger")
end

-- top half in portrait and in landscape
r = Gestures.new({ size = size })
eq(only(stroke(r, 20, { { 800, 600, 300, 0 } }, 0.15), "portrait top").half, "top", "portrait: y 600 of 2560 is top")
eq(only(stroke(r, 21, { { 800, 1400, 300, 0 } }, 0.15), "portrait bottom").half, "bottom", "portrait: y 1400 of 2560 is bottom")
W, H = 2560, 1600 -- turned on its side
-- landscape is cut down the middle: left moves ("bottom"), right navigates ("top")
eq(only(stroke(r, 22, { { 1400, 300, 0, 300 } }, 0.15), "landscape right").half, "top", "landscape: x 1400 of 2560 navigates")
eq(only(stroke(r, 23, { { 1100, 300, 0, 300 } }, 0.15), "landscape left").half, "bottom", "landscape: x 1100 of 2560 moves")
eq(only(stroke(r, 24, { { 600, 1400, 0, -300 } }, 0.15), "landscape low left").half, "bottom", "landscape: height does not matter")
-- the threshold follows the shorter side: 6% of 1600 = 96
eq(#stroke(r, 24, { { 800, 1200, 90, 0 } }, 0.15), 0, "90 px is neither tap nor swipe on a 1600 px side")
eq(only(stroke(r, 25, { { 800, 1200, 100, 0 } }, 0.15), "100 px").kind, "swipe", "100 px is a swipe")
eq(#stroke(r, 26, { { 800, 1200, 400, 0 } }, 1.5), 0, "a slow drag is no swipe")
eq(#stroke(r, 27, { { 800, 1200 } }, 0.8), 0, "a long press is no gesture (holding is not decided)")
W, H = 1600, 2560

-- double tap; a single tap is reported only after the window
r = Gestures.new({ size = size })
local out = stroke(r, 30, { { 800, 2000 } }, 0.08)
eq(#out, 0, "first tap waits for a possible second")
out = stroke(r, 30.2, { { 805, 2003 } }, 0.08)
local g = only(out, "double tap")
eq(g.kind .. g.fingers .. ":" .. g.taps, "tap1:2", "one-finger double tap")
eq(#r:update(31), 0, "nothing left waiting")

out = stroke(r, 40, { { 800, 2000 } }, 0.08)
eq(#r:update(40.2), 0, "still inside the window")
g = only(r:update(40.5), "late single")
eq(g.taps, 1, "one-finger single tap after the window")
-- a second tap too late is two single taps, not a double
r = Gestures.new({ size = size })
stroke(r, 50, { { 800, 2000 } }, 0.08)
out = stroke(r, 50.6, { { 800, 2000 } }, 0.08)
eq(#out, 1, "late second tap flushes the first")
eq(out[1].taps, 1, "the first was single")

-- two-finger double tap
r = Gestures.new({ size = size })
stroke(r, 60, { { 700, 2000 }, { 900, 2000 } }, 0.1)
g = only(stroke(r, 60.25, { { 700, 2000 }, { 900, 2000 } }, 0.1), "two-finger double")
eq(g.fingers .. ":" .. g.taps, "2:2", "two-finger double tap")

-- three-finger single versus double
r = Gestures.new({ size = size })
local three = function() return { { 600, 2000 }, { 800, 2000 }, { 1000, 2000 } } end
stroke(r, 70, three(), 0.1)
g = only(stroke(r, 70.2, three(), 0.1), "three-finger double")
eq(g.fingers .. ":" .. g.taps, "3:2", "three-finger double tap")
stroke(r, 75, three(), 0.45)
g = only(stroke(r, 75.95, three(), 0.45), "slow three-finger double")
eq(g.fingers .. ":" .. g.taps, "3:2", "a slower three-finger double tap still counts (owner, 2026-11-09)")
stroke(r, 80, three(), 0.1)
eq(#r:update(80.3), 0, "three-finger single waits")
eq(#r:update(80.6), 0, "three fingers get the longer wait (0.55 s)")
g = only(r:update(80.7), "three-finger single")
eq(g.fingers .. ":" .. g.taps, "3:1", "three-finger single tap after the window")
-- a one-finger tap right after a three-finger one is not their double
stroke(r, 90, three(), 0.1)
out = stroke(r, 90.2, { { 800, 2000 } }, 0.08)
eq(#out, 1, "different finger counts do not pair")
eq(out[1].fingers .. ":" .. out[1].taps, "3:1", "the three-finger tap was single")

-- rotation versus two-finger swipe and tap
r = Gestures.new({ size = size })
g = only(stroke(r, 100, { { 600, 2000 }, { 1000, 2000 } }, 0.4, 8, nil, 90), "clockwise")
eq(g.kind, "rotate", "a 90 degree two-finger turn is a rotation")
eq(g.direction, "clockwise", "growing angle with y down is clockwise on screen")
g = only(stroke(r, 101, { { 600, 2000 }, { 1000, 2000 } }, 0.4, 8, nil, -60), "counterclockwise")
eq(g.direction, "counterclockwise", "the other way is counterclockwise")
out = stroke(r, 102, { { 600, 2000 }, { 1000, 2000 } }, 0.4, 8, nil, 30)
check(#out == 0 or out[1].kind ~= "rotate", "30 degrees is not a rotation")
g = only(stroke(r, 103, { { 600, 2000, 0, -300 }, { 1000, 2000, 0, -300 } }, 0.2), "two-finger swipe")
eq(g.kind .. ":" .. g.fingers, "swipe:2", "two fingers moving together are a two-finger swipe, not a turn")
-- a turn past the 180 degree line keeps adding up
g = only(stroke(r, 104, { { 600, 2000 }, { 1000, 2000 } }, 0.6, 12, nil, 200), "big turn")
eq(g.direction, "clockwise", "200 degrees clockwise stays clockwise")

-- a stroke whose releases were lost does not swallow the next one
r = Gestures.new({ size = size })
r:pressed(1, 800, 2000, 200)
g = only(stroke(r, 210, { { 800, 2000, 0, 300 } }, 0.15), "after a lost stroke")
eq(g.direction, "down", "stale stroke dropped after STALE_SECONDS")

-- ------------------------------------------------------------ mapping
local TouchInput = require("src.access.touch.TouchInput")

local spoken = {}
local speech = { say = function(text, opts)
  spoken[#spoken + 1] = ((opts and opts.interrupt) and "! " or "  ") .. tostring(text)
  return true
end }
local function lastSaid() return spoken[#spoken] end

local now = 0
local options = {}
local game, overworld, adapter, coordinator, commands, autoCalls, walkingNow, stopped
local settings = {
  touchGestures = function() return options.gestures ~= false end,
  touchWalking = function() return options.walk or "manual" end,
}
local planResult, planReason
local autoWalk
autoWalk = {
  activeNow = false,
  plan = function() return planResult, planReason end,
  start = function(_, _, _, opts)
    autoCalls[#autoCalls + 1] = opts or "selected"
    autoWalk.activeNow = true
    return true
  end,
  active = function() return autoWalk.activeNow end,
}
local nav = {
  context = function() return coordinator, adapter, game end,
  walking = function() return walkingNow end,
  stopWalks = function()
    if walkingNow then walkingNow = false stopped = stopped + 1 return true end
    return false
  end,
}

local function setup(onMap)
  TouchInput._resetForTests()
  spoken, commands, autoCalls, stopped = {}, {}, {}, 0
  walkingNow, autoWalk.activeNow = false, false
  planResult, planReason = nil, nil
  options = {}
  game = { input = { sources = {}, pressQueue = {}, state = {} } }
  overworld = { map = {}, player = { cellX = 5, cellY = 5, moving = false, facing = "down" } }
  coordinator = {
    handleCommand = function(_, id) commands[#commands + 1] = id return true end,
    worldForCommand = function() return overworld end,
  }
  adapter = {
    onMap = function() return onMap end,
    transitioning = function() return false end,
  }
  TouchInput.configure({
    speech = speech, settings = settings, autoWalk = autoWalk, nav = nav,
    currentGame = { live = function() return game end },
    clock = function() return now end,
    size = function() return W, H end,
  })
end

-- gesture helpers through the love callbacks
local nextId = 0
local function touch(fingers, dx, dy, duration, rotate)
  local ids, consumed = {}, true
  for i, f in ipairs(fingers) do
    nextId = nextId + 1
    ids[i] = nextId
    consumed = TouchInput.touchpressed(nextId, f[1], f[2]) and consumed
  end
  local steps = 4
  for s = 1, steps do
    now = now + (duration or 0.1) / steps
    for i, f in ipairs(fingers) do
      local x, y = f[1] + (dx or 0) * s / steps, f[2] + (dy or 0) * s / steps
      if rotate then
        local cx, cy = (fingers[1][1] + fingers[2][1]) / 2, (fingers[1][2] + fingers[2][2]) / 2
        local a = math.rad(rotate * s / steps)
        local rx, ry = f[1] - cx, f[2] - cy
        x, y = cx + rx * math.cos(a) - ry * math.sin(a), cy + rx * math.sin(a) + ry * math.cos(a)
      end
      f.lx, f.ly = x, y
      consumed = TouchInput.touchmoved(ids[i], x, y) and consumed
    end
  end
  for i, f in ipairs(fingers) do
    consumed = TouchInput.touchreleased(ids[i], f.lx or f[1], f.ly or f[2]) and consumed
  end
  return consumed
end
local BOTTOM, TOP = 2000, 500
local function swipe(dir, y)
  local d = { up = { 0, -300 }, down = { 0, 300 }, left = { -300, 0 }, right = { 300, 0 } }
  return touch({ { 800, y or BOTTOM } }, d[dir][1], d[dir][2], 0.15)
end
local function frame()
  now = now + 1 / 60
  TouchInput.update()
end
local function frames(n) for _ = 1, n do frame() end end
local function doubleTap(fingers, y)
  local function spots()
    local list = {}
    for i = 1, fingers do list[i] = { 400 + i * 200, y or BOTTOM } end
    return list
  end
  touch(spots(), 0, 0, 0.08)
  now = now + 0.1
  return touch(spots(), 0, 0, 0.08)
end
local function pressedButtons()
  local list = {}
  for _, b in ipairs(game.input.pressQueue) do list[#list + 1] = b end
  return table.concat(list, ",")
end

-- consumption, and handing touches back when off
setup(false)
check(swipe("down"), "a touch is consumed while gestures are on")
eq(pressedButtons(), "down", "off the map a swipe is one D-pad press")
eq(game.input.state.down, true, "held for the first update")
frame()
eq(game.input.state.down, true, "still held after one update")
frame()
eq(game.input.state.down, false, "released on the second update")
eq(game.input.sources.down[TouchInput.SOURCE], nil, "its own source is gone")

setup(false)
options.gestures = false
check(not TouchInput.touchpressed(1, 800, 2000), "gestures off: upstream gets the touch")
check(not TouchInput.touchreleased(1, 800, 2000), "and its release")
setup(false)
TouchInput.configure({ currentGame = { live = function() return nil end } })
check(not TouchInput.touchpressed(1, 800, 2000), "no running game (launcher): upstream gets the touch")
check(not TouchInput.ownsTouches(), "no running game: upstream's buttons stay drawn")
setup(false)
check(TouchInput.ownsTouches(), "gestures on with a game: upstream's buttons are hidden")
setup(false)
options.gestures = false
check(not TouchInput.ownsTouches(), "gestures off: upstream's buttons come back")

-- buttons, off the map: the whole screen counts, top half too
setup(false)
doubleTap(1, TOP)
eq(pressedButtons(), "a", "double tap is A (top half off the map)")
setup(false)
doubleTap(2)
eq(pressedButtons(), "b", "two-finger double tap is B")
setup(false)
doubleTap(3)
eq(pressedButtons(), "start", "three-finger double tap is START")
setup(false)
touch({ { 600, BOTTOM }, { 800, BOTTOM }, { 1000, BOTTOM } }, 0, 0, 0.08)
eq(pressedButtons(), "", "three-finger single tap waits for the window")
frames(25)
eq(pressedButtons(), "", "still waiting at the old 0.3 s window")
frames(20)
eq(pressedButtons(), "select", "then it is SELECT")
setup(false)
swipe("up", TOP)
eq(pressedButtons(), "up", "off the map the top half swipes the D-pad too")
eq(#commands, 0, "no navigation command off the map")
setup(false)
touch({ { 600, BOTTOM }, { 1000, BOTTOM } }, 0, 0, 0.4, 90)
eq(#autoCalls, 0, "a turn off the map does not start auto-walk")

-- on the map: the top half navigates
setup(true)
swipe("right", TOP) swipe("left", TOP) swipe("up", TOP) swipe("down", TOP)
eq(table.concat(commands, ","), "next_map_item,previous_map_item,previous_item_filter,next_item_filter",
  "top half: left/right through points, up/down through categories")
eq(pressedButtons(), "", "and no D-pad press")
doubleTap(1, TOP)
eq(pressedButtons(), "", "a double tap in the top half on the map does nothing")

-- on the map: a bottom swipe is one step, held until the step is under way
setup(true)
swipe("left")
local st = TouchInput._state()
check(st.step ~= nil, "a step started")
eq(game.input.state.left, true, "left held")
frame()
eq(game.input.state.left, true, "held while the player has not moved")
overworld.player.facing, overworld.player.moving = "left", true
frame()
eq(game.input.state.left, false, "let go once the step is under way")
overworld.player.cellX, overworld.player.moving = 4, false
frame()
check(TouchInput._state().step == nil, "step finished")
-- world.stepped lets go inside the game's step
setup(true)
swipe("up")
TouchInput.stepped(5, 4)
eq(game.input.state.up, false, "released on world.stepped")
-- blocked: let go after STEP_MAX_FRAMES
setup(true)
swipe("right")
frames(TouchInput.STEP_MAX_FRAMES)
eq(game.input.state.right, false, "a blocked step lets go")
check(TouchInput._state().step == nil, "and ends")
-- turning on the spot is not the step
setup(true)
swipe("down")
overworld.player.facing, overworld.player.moving = "up", true
frame()
eq(game.input.state.down, true, "still held while turning from another direction")
-- quick swipes queue
setup(true)
swipe("up") swipe("up") swipe("left")
eq(#TouchInput._state().queue, 2, "two more steps wait")
overworld.player.cellY, overworld.player.moving = 4, false
frame() -- moved: let go
frame() -- standing: finished
frame() -- next one starts
eq(TouchInput._state().step and TouchInput._state().step.direction, "up", "the queued step runs")

-- double tap on the map is A, and walks are stopped by gestures
setup(true)
doubleTap(1)
eq(pressedButtons(), "a", "double tap on the map is A")
setup(true)
walkingNow = true
swipe("left")
eq(stopped, 1, "a swipe while walking stops the walk")
eq(pressedButtons(), "", "and does nothing else")

-- rotation: clockwise starts auto-walk, counterclockwise stops it
setup(true)
touch({ { 600, BOTTOM }, { 1000, BOTTOM } }, 0, 0, 0.4, 90)
eq(#autoCalls, 1, "clockwise turn starts auto-walk")
eq(autoCalls[1], "selected", "to the selected point (as the left stick click)")
walkingNow = true
touch({ { 600, BOTTOM }, { 1000, BOTTOM } }, 0, 0, 0.4, 90)
eq(#autoCalls, 1, "clockwise while walking keeps walking")
eq(stopped, 0, "and does not stop")
touch({ { 600, BOTTOM }, { 1000, BOTTOM } }, 0, 0, 0.4, -90)
eq(stopped, 1, "counterclockwise stops the walk")
touch({ { 600, BOTTOM }, { 1000, BOTTOM } }, 0, 0, 0.4, -90)
eq(lastSaid(), "! Not walking", "counterclockwise with nothing walking says so")

-- walking modes
local function route(...)
  local steps, x, y = {}, 5, 5
  for _, d in ipairs({ ... }) do
    local nx, ny = x, y
    if d == "up" then ny = y - 1 elseif d == "down" then ny = y + 1
    elseif d == "left" then nx = x - 1 else nx = x + 1 end
    steps[#steps + 1] = { fromX = x, fromY = y, x = nx, y = ny, direction = d }
    x, y = nx, ny
  end
  return { item = { label = "PC" }, steps = steps, goal = { x = x, y = y },
           interaction = { [x .. "," .. y] = "Face up and interact" } }
end
local leg = TouchInput.firstLeg(route("up", "up", "up", "left").steps)
eq(leg.direction .. leg.count .. ":" .. leg.x .. "," .. leg.y, "up3:5,2", "first leg: 3 up to 5,2")
eq(TouchInput.legText(route("up", "up", "left")), "2 up", "leg text")
eq(TouchInput.legText(route()), "PC is here. Face up and interact", "arrival text with the hint")
eq(TouchInput.legText(nil, "Select an object from the list"), "Select an object from the list", "why not")

-- AUTO: swipes still step one at a time
setup(true)
options.walk = "auto"
planResult = route("up", "up")
swipe("up")
eq(#autoCalls, 0, "auto mode: a swipe does not walk the leg")
check(TouchInput._state().step ~= nil, "it steps")

-- HYBRID: selection change says the leg; the right way walks it
setup(true)
options.walk = "hybrid"
planResult = route("up", "up", "up", "left")
swipe("right", TOP)
eq(lastSaid(), "  3 up", "a new point is followed by its first leg, queued")
swipe("up")
eq(#autoCalls, 1, "a swipe along the leg starts a walk")
eq(autoCalls[1].quiet, true, "a quiet walk")
eq(autoCalls[1].goals[1].x .. "," .. autoCalls[1].goals[1].y, "5,2", "to the leg's end")
check(TouchInput._state().step == nil, "no single step")
-- the walk ends at the leg's end: the next leg is said
autoWalk.activeNow = false
overworld.player.cellY = 2
planResult = route("left")
frame()
eq(lastSaid(), "  1 left", "next leg said after the walk, queued behind any stop reason")
-- arrival
planResult = route("left")
swipe("left")
autoWalk.activeNow = false
planResult = route()
frame()
eq(lastSaid(), "  PC is here. Face up and interact", "arrival said at the end")

-- HYBRID: the wrong way takes one step and plans again
setup(true)
options.walk = "hybrid"
planResult = route("up", "up", "up")
swipe("right")
eq(#autoCalls, 0, "a wrong-way swipe does not walk the leg")
eq(game.input.state.right, true, "it steps right")
overworld.player.facing, overworld.player.moving = "right", true
frame()
overworld.player.cellX, overworld.player.moving = 6, false
planResult = route("left", "up", "up", "up")
frame()
frame()
eq(lastSaid(), "! 1 left", "then the new route's first leg")
-- no route: the swipe steps and the reason is said
setup(true)
options.walk = "hybrid"
planResult, planReason = nil, "Select an object from the list"
swipe("down")
eq(game.input.state.down, true, "with nothing selected a swipe steps")
overworld.player.facing, overworld.player.moving = "down", true
frame()
overworld.player.cellY, overworld.player.moving = 6, false
frame() frame()
eq(lastSaid(), "! Select an object from the list", "and says why there is no leg")

-- ------------------------------------------------------------ settings rows
local Settings = require("src.access.Settings")
local before = #Settings.rows()
local getenv = os.getenv
os.getenv = function(name)
  if name == "POKEPORT_ACCESS_TOUCH" then return "1" end
  return getenv(name)
end
local rows = Settings.rows()
eq(#rows, before + 2, "touch rows appear where touch is available")
local sgame = { save = { options = {} } }
local gestureRow, walkRow = rows[#rows - 1], rows[#rows]
eq(gestureRow.label .. "=" .. gestureRow.value(sgame), "TOUCH GESTURES=ON", "on by default where available")
gestureRow.step(sgame, 1)
eq(gestureRow.value(sgame), "OFF", "turned off")
eq(sgame.save.options.accessTouchGestures, false, "stored")
eq(Settings.touchGestures(sgame), false, "and read back")
eq(walkRow.label .. "=" .. walkRow.value(sgame), "TOUCH WALKING=MANUAL", "manual by default")
walkRow.step(sgame, 1)
eq(walkRow.value(sgame), "HYBRID", "then hybrid")
walkRow.step(sgame, 1)
eq(walkRow.value(sgame), "AUTO", "then auto")
walkRow.step(sgame, 1)
eq(walkRow.value(sgame), "MANUAL", "and round")
eq(sgame.save.options.accessTouchWalk, nil, "manual clears the key")
os.getenv = getenv
eq(#Settings.rows(), before, "no touch rows on a computer without the variable")
eq(Settings.touchGestures({ save = { options = {} } }), false, "and gestures default off there")

-- ------------------------------------------------------------ AutoWalk.plan
package.loaded["src.access.nav.Pathfinder"] = {
  find = function() return route("up", "up", "right") end,
}
package.loaded["src.access.nav.AutoWalk"] = nil
local RealAutoWalk = require("src.access.nav.AutoWalk")
local planned = RealAutoWalk.plan({
  selectedRouteGoals = function() return { label = "PC" }, { { x = 6, y = 3 } }, nil, nil, overworld end,
  worldRouteRequest = function() return {} end,
})
eq(planned and #planned.steps, 3, "AutoWalk.plan returns the route without walking")
check(not RealAutoWalk.active(), "nothing walks")
local none, why = RealAutoWalk.plan({ selectedRouteGoals = function() return nil, "Select an object from the list" end })
check(none == nil and why == "Select an object from the list", "no selection: the reason")

T.finish("touch gestures")
