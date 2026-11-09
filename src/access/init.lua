-- Entry point of the accessibility layer.
--
-- main.lua calls Access.install() once, early in love.load (the single boot
-- hook, listed in docs/access/architecture.md).  Everything else attaches
-- from here, so upstream files stay untouched apart from listed hooks.

local Speech = require("src.access.Speech")
local ScreenReader = require("src.access.screens.ScreenReader")

local Access = {}

local installed = false

-- Wraps a love callback so the layer runs after upstream's own handler.
-- Upstream's return value is passed through unchanged; love.quit relies on
-- it (returning true cancels the quit).
local function after(name, fn)
  local original = love[name]
  love[name] = function(...)
    local result
    if original then result = original(...) end
    fn(result, ...)
    return result
  end
end

-- Wraps a love callback so the layer runs first and may consume the event:
-- when fn returns true, upstream's handler never sees it.
local function before(name, fn)
  local original = love[name]
  love[name] = function(...)
    if fn(...) then return end
    if original then return original(...) end
  end
end

function Access.install(opts)
  if installed then return false end
  -- POKEPORT_ACCESS=0 runs plain upstream, for telling our bugs from theirs.
  if os.getenv("POKEPORT_ACCESS") == "0" then return false end
  installed = true
  opts = opts or {}

  if Speech.start(opts.speech) then
    Speech.say("Pocket Accessibility ready.", { interrupt = true })
  end

  -- Screen speech reads the frame's settled state, after upstream's update.
  -- Only when speech works: with no output there is nothing to report.
  if Speech.available() then
    -- the live game for every generation (Gen 3 screens need it)
    require("src.access.CurrentGame").install()
    local Nav = require("src.access.nav")
    -- the ACCESSIBILITY page in OPTIONS (decision 26)
    require("src.access.Settings").install()
    local TouchInput = require("src.access.touch.TouchInput")
    after("update", function()
      ScreenReader.update()
      Nav.update()
      TouchInput.update()
    end)
    -- Pokemon Access command keys (F7 command layer, F8 help) reach the
    -- router before the game; recognised commands are consumed.
    before("keypressed", function(key, scancode, isRepeat)
      return Nav.keypressed(key, scancode, isRepeat)
    end)
    after("keyreleased", function(_, key) Nav.keyreleased(key) end)
    -- Controller navigation (decision 23): left trigger modifier, D-pad
    -- categories and items, stick clicks for auto-walk and guidance.
    before("gamepadaxis", function(joystick, axis, value)
      return Nav.gamepadaxis(joystick, axis, value)
    end)
    before("gamepadpressed", function(joystick, button)
      return Nav.gamepadpressed(joystick, button)
    end)
    before("gamepadreleased", function(joystick, button)
      return Nav.gamepadreleased(joystick, button)
    end)
    -- Touch gestures (decision 66): with TOUCH GESTURES on and a game
    -- running, every touch is a gesture and upstream's on-screen buttons
    -- never see it.  A mouse never comes this way (Game3 routes its
    -- POKEPORT_TOUCH stand-in finger to the game directly).
    before("touchpressed", function(id, x, y)
      return TouchInput.touchpressed(id, x, y)
    end)
    before("touchmoved", function(id, x, y)
      return TouchInput.touchmoved(id, x, y)
    end)
    before("touchreleased", function(id, x, y)
      return TouchInput.touchreleased(id, x, y)
    end)
    -- Runtime wrapper (architecture.md hook list): while gestures own the
    -- touches, upstream's on-screen D-pad and buttons are not drawn.  Its
    -- layout editor's preview still shows them.
    local okControls, TouchControls = pcall(require, "src.core.TouchControls")
    if okControls and type(TouchControls) == "table" and type(TouchControls.visible) == "function" then
      local upstreamVisible = TouchControls.visible
      TouchControls.visible = function(self, ...)
        if not self.preview and TouchInput.ownsTouches() then return false end
        return upstreamVisible(self, ...)
      end
    end
  end

  -- A cancelled quit (true) keeps the game running, so speech stays open.
  after("quit", function(cancelled)
    if not cancelled then Speech.shutdown() end
  end)
  return true
end

function Access._resetForTests()
  installed = false
  Speech.shutdown()
end

return Access
