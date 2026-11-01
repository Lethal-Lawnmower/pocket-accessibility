-- Watches the top of the game's state stack and speaks UI changes.
--
-- Called once per frame after upstream's love.update, so it sees the settled
-- result of that frame's input (docs/access/architecture.md).  Each presenter
-- compares a few fields against what it last said and builds speech only
-- when something changed, so an unchanged frame costs a table lookup and a
-- handful of comparisons.  Gen 1 keeps one shared stack in the StateStack
-- module itself (src/core/Game.lua: `self.stack = StateStack`), so reading
-- it needs no hook.

local Presenters = require("src.access.screens.Presenters")
local Speech = require("src.access.Speech")

local ScreenReader = {}

local lastState = nil      -- the state that was on top last frame
local lastPresenter = nil  -- its presenter, cached so matching runs once per screen
-- Per-screen memory of what was last said.  Weak keys, so closed screens are
-- collected normally; kept across returns so a presenter can stay quiet
-- (or repeat context) when a screen above it closes.
local memos = setmetatable({}, { __mode = "k" })

local stackModule = nil
local function topState()
  stackModule = stackModule or package.loaded["src.core.StateStack"]
  if not (stackModule and stackModule.states) then return nil end
  return stackModule.states[#stackModule.states]
end

local function poll(state, entering, presenter, queue)
  presenter = presenter or lastPresenter
  local memo = memos[state]
  if not memo then
    memo = {}
    memos[state] = memo
  end
  local text, interrupt = presenter.poll(state, memo, entering)
  if queue then interrupt = false end
  if text then Speech.say(text, { interrupt = interrupt, screen = true }) end
  return text ~= nil
end

-- A dialogue box can be covered in the same frame it opens: Yellow prints
-- the elevator's "Which floor do you want?" instantly and pushes the floor
-- list over it at once, so the box is never the top state.  When a new top
-- appears, speak any dialogue box under it that was pushed and never
-- polled, then queue the top behind it.  Only dialogue boxes, so other
-- covered screens (fades, transitions) stay quiet.
local function speakCovered(top)
  local stack = stackModule or package.loaded["src.core.StateStack"]
  local states = stack and stack.states
  if type(states) ~= "table" or states[#states] ~= top then return false end
  local spoke = false
  for i = 1, #states - 1 do
    local state = states[i]
    if not memos[state] and state ~= lastState and Presenters.textBox.matches(state) then
      spoke = poll(state, true, Presenters.textBox) or spoke
    end
  end
  return spoke
end

-- A screen can change and be covered in the same frame: Gen 2's box screen
-- sets "Release PKMN?" and pushes the Yes/No box at once.  A presenter may
-- provide covered(state, memo) -> text for that case; it is asked when the
-- screen it handles was on top last frame and now sits right under the new
-- top, and its text is said before the new top, which queues behind it.
local function speakChangedUnder(previous, previousPresenter, top)
  if not (previous and previousPresenter and previousPresenter.covered and memos[previous]) then return false end
  local stack = stackModule or package.loaded["src.core.StateStack"]
  local states = stack and stack.states
  if type(states) ~= "table" or states[#states] ~= top or states[#states - 1] ~= previous then return false end
  local text = previousPresenter.covered(previous, memos[previous])
  if not text then return false end
  Speech.say(text, { interrupt = true, screen = true })
  return true
end

-- `top` is injectable for tests; the game passes nothing.
function ScreenReader.update(top)
  local state = top or topState()
  if state ~= lastState then
    local previous, previousPresenter = lastState, lastPresenter
    lastPresenter = Presenters.find(state)
    local queued = lastPresenter and previous ~= nil and speakCovered(state)
    if lastPresenter and speakChangedUnder(previous, previousPresenter, state) then queued = true end
    if lastPresenter then poll(state, true, nil, queued) end
    lastState = state
    return
  end
  if lastPresenter then poll(state, false) end
end

function ScreenReader._resetForTests()
  lastState, lastPresenter, stackModule = nil, nil, nil
  Presenters.textBox.reset()
  memos = setmetatable({}, { __mode = "k" })
end

return ScreenReader
