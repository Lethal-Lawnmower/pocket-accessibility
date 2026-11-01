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
    local Nav = require("src.access.nav")
    after("update", function()
      ScreenReader.update()
      Nav.update()
    end)
    -- Pokemon Access command keys (F7 command layer, F8 help) reach the
    -- router before the game; recognised commands are consumed.
    before("keypressed", function(key, scancode, isRepeat)
      return Nav.keypressed(key, scancode, isRepeat)
    end)
    after("keyreleased", function(_, key) Nav.keyreleased(key) end)
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
