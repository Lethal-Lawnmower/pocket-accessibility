-- Touch gestures (decision 66), scripted in any game: synthetic touches go
-- through the real love.touchpressed / touchmoved / touchreleased, so they
-- pass the layer's before-hooks exactly as an Android touch would.  Checks a
-- step on the map, two-finger navigation swipes, the start menu (three-
-- finger double tap, a swipe, two-finger double tap), that a two-finger
-- turn does nothing, AUTO's swipe walking to the point, and one hybrid leg.
-- Harness setup (reaching the map) presses buttons directly on the game's
-- input, never through gestures.
--
-- Silent and isolated, with a disposable identity:
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_ACCESS_TRACE=1 POKEPORT_ACCESS_TOUCH=1
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/touch_gestures.lua
--   POKEPORT_VERSION=crystal POKEPORT_GAME=crystal
--   POKEPORT_IDENTITY=pocket-access-touch-test  lovec.exe .
-- Read the RESULT lines; it asserts nothing about wording.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Speech = require("src.access.Speech")
  local Nav = require("src.access.nav")
  local AutoWalk = require("src.access.nav.AutoWalk")
  local Settings = require("src.access.Settings")

  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts)
    said[#said + 1] = ((opts and opts.interrupt) and "! " or "") .. tostring(text)
    return say(text, opts)
  end
  local function heard()
    local s = table.concat(said, " | ")
    said = {}
    return s
  end

  local function now() return love.timer.getTime() end
  local function waitSeconds(s)
    local start = now()
    for _ = 1, 100000 do
      if now() - start >= s then return end
      U.wait(1)
    end
  end
  local function frames(n) for _ = 1, n do U.wait(1) end end

  local function onMap()
    local nav, adapter, g = Nav.context()
    return nav ~= nil and adapter.onMap(g) == true
  end
  local function where()
    local nav = Nav.coordinator()
    local w = nav and nav:worldForCommand()
    local p = w and w.player
    if not p then return "?" end
    return tostring(p.cellX) .. "," .. tostring(p.cellY)
  end
  local function directTap(button)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    frames(2)
    game.input.state[button] = false
    frames(8)
  end

  -- harness: A through intros and text until the map has been free a while
  local function settle(limit)
    local run = 0
    for _ = 1, limit do
      if onMap() then
        run = run + 1
        if run >= 60 then return true end
        U.wait(1)
      else
        run = 0
        directTap("a")
      end
    end
    return onMap()
  end

  -- ---------------------------------------------------------- touches
  local w, h = love.graphics.getDimensions()
  -- Anywhere on the screen works the same (the owner, 2026-11-10), so the
  -- touches use two places to show it: high and low, or right and left when
  -- the window is wider than tall.
  local HIGH, LOW = "high", "low"
  local LANDSCAPE = w > h
  local function centre(place)
    if LANDSCAPE then return (place == HIGH and 0.75 or 0.25) * w, h / 2 end
    return w / 2, (place == HIGH and 0.25 or 0.75) * h
  end
  -- n fingers side by side around a place
  local function spread(place, n, from, step)
    local list = {}
    for i = 1, n do
      local f = from + step * i
      if LANDSCAPE then
        list[i] = { (place == HIGH and 0.5 or 0) * w + f * w / 2, h / 2 }
      else
        list[i] = { w * f, (place == HIGH and 0.25 or 0.75) * h }
      end
    end
    return list
  end
  local nextId = 100
  local consumedAll = true
  -- fingers: list of { x, y }; dx, dy move all of them; turn in degrees
  local function gesture(fingers, dx, dy, steps, turn)
    local ids = {}
    for i, f in ipairs(fingers) do
      nextId = nextId + 1
      ids[i] = nextId
      love.touchpressed(ids[i], f[1], f[2], 0, 0, 1)
    end
    steps = steps or 4
    local cx, cy = 0, 0
    for _, f in ipairs(fingers) do cx, cy = cx + f[1] / #fingers, cy + f[2] / #fingers end
    for s = 1, steps do
      U.wait(1)
      for i, f in ipairs(fingers) do
        local x, y = f[1] + (dx or 0) * s / steps, f[2] + (dy or 0) * s / steps
        if turn then
          local a = math.rad(turn * s / steps)
          local rx, ry = f[1] - cx, f[2] - cy
          x, y = cx + rx * math.cos(a) - ry * math.sin(a), cy + rx * math.sin(a) + ry * math.cos(a)
        end
        f.lx, f.ly = x, y
        love.touchmoved(ids[i], x, y, 0, 0, 1)
      end
    end
    for i, f in ipairs(fingers) do love.touchreleased(ids[i], f.lx or f[1], f.ly or f[2], 0, 0, 1) end
    -- upstream's on-screen buttons press with "touch:<button>" sources
    for _, sources in pairs(game.input.sources or {}) do
      for source in pairs(sources) do
        if tostring(source):match("^touch:") then consumedAll = false end
      end
    end
  end
  local SWIPE = math.min(w, h) * 0.2
  local MOVES = { up = { 0, -SWIPE }, down = { 0, SWIPE }, left = { -SWIPE, 0 }, right = { SWIPE, 0 } }
  local function swipe(dir, place)
    local x, y = centre(place)
    gesture({ { x, y } }, MOVES[dir][1], MOVES[dir][2], 4)
  end
  -- navigation: two fingers moving together
  local function swipe2(dir, place)
    gesture(spread(place, 2, 0.05, 0.3), MOVES[dir][1], MOVES[dir][2], 4)
  end
  local function spots(n, place)
    return spread(place, n, 0.0, 0.2)
  end
  local function doubleTap(n, place)
    gesture(spots(n, place or LOW), 0, 0, 1)
    frames(2)
    gesture(spots(n, place or LOW), 0, 0, 1)
  end
  local function turn(degrees)
    gesture(spread(LOW, 2, 0.05, 0.3), 0, 0, 8, degrees)
  end

  U.log("NOTE", "screen", w, h, "touch gestures", tostring(Settings.touchGestures(game)))
  if not settle(4000) then U.log("FAIL", "never reached the map") return end
  heard()

  -- a step on the map, high on the screen (once the halves' navigation side)
  local moved = false
  for _, dir in ipairs({ "down", "left", "right", "up" }) do
    local before = where()
    swipe(dir, HIGH)
    frames(40)
    local after = where()
    U.log("RESULT", "swipe " .. dir .. ": " .. before .. " -> " .. after, heard())
    if after ~= before then moved = true break end
  end
  U.log("RESULT", "a swipe took a step:", tostring(moved))

  -- two-finger swipes: navigation points and categories, high and low
  swipe2("right", LOW) frames(10)
  U.log("RESULT", "two-finger swipe right =>", heard())
  swipe2("right", HIGH) frames(10)
  U.log("RESULT", "two-finger swipe right =>", heard())
  swipe2("down", LOW) frames(10)
  U.log("RESULT", "two-finger swipe down =>", heard())
  swipe2("up", HIGH) frames(10)
  U.log("RESULT", "two-finger swipe up =>", heard())
  swipe2("right", LOW) frames(10)
  U.log("RESULT", "two-finger swipe right =>", heard())

  -- the start menu: START, a D-pad press, B
  doubleTap(3)
  frames(40)
  U.log("RESULT", "three-finger double tap (START) =>", heard(), "on map:", tostring(onMap()))
  swipe("down", HIGH)
  frames(20)
  U.log("RESULT", "swipe down in the menu =>", heard())
  swipe("up", LOW)
  frames(20)
  U.log("RESULT", "swipe up in the menu =>", heard())
  doubleTap(2)
  frames(40)
  U.log("RESULT", "two-finger double tap (B) =>", heard(), "on map:", tostring(onMap()))
  settle(600)
  heard()

  -- a two-finger turn does nothing now (walking modes live in the options)
  local beforeTurn = where()
  turn(90)
  frames(20)
  U.log("RESULT", "clockwise turn =>", heard(), "walking:", tostring(AutoWalk.walking()),
    "moved:", tostring(where() ~= beforeTurn))

  -- AUTO: a swipe any way walks to the selected point; another swipe stops it
  local function setWalking(label)
    for _, row in ipairs(Settings.rows()) do
      if row.id == "accessTouchWalk" then
        while row.value(game) ~= label do row.step(game, 1) end
      end
    end
  end
  setWalking("AUTO")
  swipe("down", LOW)
  frames(20)
  U.log("RESULT", "auto: swipe =>", heard(), "walking:", tostring(AutoWalk.walking()))
  swipe("left", HIGH)
  frames(10)
  U.log("RESULT", "auto: swipe while walking =>", heard(), "walking:", tostring(AutoWalk.walking()))
  settle(600)
  heard()

  -- hybrid: the next leg is said, and a swipe along it walks it
  setWalking("HYBRID")
  -- the first point with a leg to walk (one the player already stands at has none)
  local text, count, dir
  for _ = 1, 8 do
    swipe2("right", HIGH) frames(10)
    text = heard()
    U.log("RESULT", "hybrid: two-finger swipe right =>", text)
    count, dir = text:match("(%d+) (%a+)$")
    if dir then break end
  end
  if dir then
    local before = where()
    swipe(dir, LOW)
    for _ = 1, 900 do
      U.wait(1)
      if not AutoWalk.active() and #said > 0 then break end
    end
    frames(20)
    U.log("RESULT", "hybrid: swipe " .. dir .. " (" .. count .. ") " .. before .. " -> " .. where(), "=>", heard())
  else
    U.log("RESULT", "hybrid: no leg to walk")
  end
  U.log("RESULT", "no upstream on-screen button pressed:", tostring(consumedAll))
  U.log("DONE")
end
