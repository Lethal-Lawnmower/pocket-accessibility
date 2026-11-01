-- Watches the top of the game's state stack and speaks UI changes.
--
-- Called once per frame after upstream's love.update, so it sees the settled
-- result of that frame's input (docs/access/architecture.md).  The per-frame
-- cost is a table lookup and one or two number comparisons; speech text is
-- built only when the top screen or its marker (cursor index, page) changes.
-- Gen 1 keeps one shared stack in the StateStack module itself
-- (src/core/Game.lua: `self.stack = StateStack`), so reading it needs no hook.

local Presenters = require("src.access.screens.Presenters")
local Speech = require("src.access.Speech")

local ScreenReader = {}

local lastState = nil      -- the state that was on top last frame
local lastPresenter = nil  -- its presenter, cached so matching runs once per screen
local lastKey = nil
-- What was last said for each state, for presenters that must not repeat
-- themselves when a screen above them closes (a dialogue page under a
-- Yes/No box).  Weak keys, so closed screens are collected normally.
local spokenKey = setmetatable({}, { __mode = "k" })

local function announce(presenter, state, entering)
  local key = presenter.key(state)
  if entering and presenter.repeatOnReturn == false and spokenKey[state] == key then
    return key
  end
  local text, interrupt = presenter.speak(state, entering)
  if text then
    Speech.say(text, { interrupt = interrupt })
    spokenKey[state] = key
  end
  return key
end

local stackModule = nil
local function topState()
  stackModule = stackModule or package.loaded["src.core.StateStack"]
  if not (stackModule and stackModule.states) then return nil end
  return stackModule.states[#stackModule.states]
end

-- `top` is injectable for tests; the game passes nothing.
function ScreenReader.update(top)
  local state = top or topState()
  if state ~= lastState then
    lastState = state
    lastPresenter = Presenters.find(state)
    lastKey = lastPresenter and announce(lastPresenter, state, true) or nil
    return
  end
  if lastPresenter and lastPresenter.key(state) ~= lastKey then
    lastKey = announce(lastPresenter, state, false)
  end
end

function ScreenReader._resetForTests()
  lastState, lastPresenter, lastKey, stackModule = nil, nil, nil, nil
  spokenKey = setmetatable({}, { __mode = "k" })
end

return ScreenReader
