-- Shared steps for the Gen 3 menu drivers (tests/access/drivers/gen3_menus*.lua).
-- They press buttons through game.input the way upstream's drivers do and
-- log each step, so the `say!:` trace lines (POKEPORT_ACCESS_TRACE=1) can be
-- read against what was pressed.  Nothing here asserts; a step that waits
-- for a screen logs WAIT-TIMEOUT when the screen never came.

local U = require("tests.drivers.util")

local L = {}

function L.step(label)
  print("[step] " .. label)
end

function L.wait(n)
  U.wait(n or 1)
end

function L.waitFor(label, fn, budget)
  for _ = 1, budget or 900 do
    local ok, value = pcall(fn)
    if ok and value then return true end
    U.wait(1)
  end
  print("[step] WAIT-TIMEOUT " .. label)
  return false
end

-- Holds a button for two frames, releases it, then waits.
function L.tap(game, button, frames)
  game.input.pressQueue[#game.input.pressQueue + 1] = button
  game.input.state[button] = true
  U.wait(2)
  game.input.state[button] = false
  U.wait(frames or 20)
end

function L.loaded(path)
  return package.loaded[path]
end

function L.top()
  local Stack = package.loaded["src.ui.game3.stack"]
  local top = Stack and Stack.top and Stack.top()
  return top and top.id or nil
end

-- Talks through field messages and yes/no boxes (A each time), until none
-- is open or the budget runs out.
function L.talk(game, budget)
  for _ = 1, budget or 40 do
    local Message = package.loaded["src.ui.game3.message"]
    local Choice = package.loaded["src.ui.game3.choice"]
    local open = (Message and Message.open) or (Choice and Choice.active)
    if not open then return end
    L.tap(game, "a", 25)
  end
end

-- Moves the start menu cursor to the entry with this id.
function L.startMenuTo(game, id)
  local StartMenu = package.loaded["src.ui.game3.start_menu"]
  if not StartMenu then return false end
  for _ = 1, 12 do
    local entry = StartMenu.ENTRIES[StartMenu.cursor]
    if entry and entry.id == id then return true end
    L.tap(game, "down", 12)
  end
  return false
end

function L.session()
  local Runtime = package.loaded["src.core.game3.runtime"]
  return Runtime and Runtime.getSession and Runtime.getSession() or nil
end

return L
