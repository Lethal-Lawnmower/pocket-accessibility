-- Shared steps for the Hoenn drivers (rse_menus, rse_screens, rse_battle).
-- Presses buttons through game.input and logs every screen change (SCREEN)
-- and every utterance (SAID), plus BAD for a spoken line that is empty or
-- holds a raw id, table address or tag.  It asserts nothing else: the log
-- is read against what was pressed.

local U = dofile("tests/drivers/util.lua")

return function(game)
  local Speech = require("src.access.Speech")
  local Top = require("src.access.screens.gen3.Top")

  local L = { U = U, game = game }

  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts)
    said[#said + 1] = { text = tostring(text), queued = opts and opts.interrupt == false }
    return say(text, opts)
  end

  local function isBad(text)
    if text:find("^%s*$") then return "empty" end
    if text:find("table: ", 1, true) or text:find("function: ", 1, true) then return "address" end
    if text:find("[{}]") then return "tag" end
    if text:find("%f[%w]g[A-Z]%l+[A-Z_]") or text:find("%f[%w]s[A-Z]%l+[A-Z_]") then return "text key" end
    if text:find("ITEM_", 1, true) or text:find("SPECIES_", 1, true) or text:find("MOVE_", 1, true)
        or text:find("MAPSEC_", 1, true) or text:find("TYPE_", 1, true) then return "constant" end
    if text:find("%f[%w]nil%f[%W]") then return "nil" end
    if text:find("[%z\1-\8\11-\31]") or text:find("\252", 1, true) then return "control byte" end
    return nil
  end

  L.silentScreens = {}
  local last, lastSaidAt, frames = nil, 0, 0

  local function name()
    local ok, top = pcall(Top.resolve, game)
    if ok and top then return tostring(top.gen3) end
    return "phase:" .. tostring(game.phase)
  end

  function L.watch()
    frames = frames + 1
    local now = name()
    if now ~= last then U.log("SCREEN", now) last = now end
    for _, line in ipairs(said) do
      U.log("SAID", line.text .. (line.queued and "  [queued]" or ""))
      local why = isBad(line.text)
      if why then U.log("BAD", why .. ": " .. line.text) end
      lastSaidAt = frames
    end
    said = {}
  end

  function L.wait(n) for _ = 1, n or 1 do U.wait(1) L.watch() end end

  function L.tap(button, frames_)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    L.wait(2)
    game.input.state[button] = false
    L.wait(frames_ or 14)
  end

  function L.taps(list, frames_) for _, b in ipairs(list) do L.tap(b, frames_) end end

  function L.waitFor(label, fn, budget)
    for _ = 1, budget or 900 do
      local ok, value = pcall(fn)
      if ok and value then return true end
      L.wait(1)
    end
    U.log("WAIT-TIMEOUT", label)
    return false
  end

  function L.section(label, fn)
    U.log("SECTION", label)
    local ok, err = pcall(fn)
    if not ok then U.log("FAIL", label .. ": " .. tostring(err)) end
    L.wait(20)
    return ok
  end

  function L.log(tag, value) U.log(tag, value) end

  function L.top()
    local Stack = package.loaded["src.ui.game3.stack"]
    local top = Stack and Stack.top and Stack.top()
    return top and top.id or nil
  end

  -- A through field messages and yes/no boxes until none is open.
  function L.talk(budget)
    for _ = 1, budget or 60 do
      local Message = package.loaded["src.ui.game3.message"]
      local Choice = package.loaded["src.ui.game3.choice"]
      local open = (Message and Message.open) or (Choice and Choice.active)
      if not open then return end
      L.tap("a", 22)
    end
  end

  -- B until no layer is open.
  function L.closeAll(budget)
    local Stack = require("src.ui.game3.stack")
    for _ = 1, budget or 12 do
      if not Stack.top() then return end
      L.tap("b", 25)
    end
  end

  function L.session()
    return require("src.core.game3.runtime").getSession()
  end

  function L.flag(session, name, on)
    local Flags = require("src.core.game3.scripting.flags")
    local C = require("src.core.game3.constants").active(session)
    local ok, id = pcall(function() return C:require("flags", name) end)
    if not ok then U.log("NOFLAG", name) return end
    local Space = require("src.core.game3.scripting.space")
    Flags.setFlag(Space.store, nil, id, on ~= false)
  end

  return L
end
