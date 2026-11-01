-- Entry point of the accessibility layer.
--
-- main.lua calls Access.install() once, early in love.load (the single boot
-- hook, listed in docs/access/architecture.md).  Everything else attaches
-- from here, so upstream files stay untouched apart from listed hooks.

local Speech = require("src.access.Speech")

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

function Access.install(opts)
  if installed then return false end
  installed = true
  opts = opts or {}

  if Speech.start(opts.speech) then
    Speech.say("Pocket Accessibility ready.", { interrupt = true })
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
