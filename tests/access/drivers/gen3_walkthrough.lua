-- Gen 3 walkthrough (FireRed, LeafGreen): boot to the title, start a new
-- game, open the start menu and the bag, then fight a wild battle, logging
-- every screen change and every utterance.  It asserts nothing, so it shows
-- what the layer says (or misses).  Gen 3 keeps its own menu stack
-- (src/ui/game3/stack.lua) and message box (src/ui/game3/message.lua), so a
-- "screen" here is the open message, else the top stack layer's id, else the
-- game phase.  Run silently and isolated:
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/gen3_walkthrough.lua
--   POKEPORT_VERSION=firered POKEPORT_GAME=firered POKEPORT_IDENTITY=<disposable>
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Speech = require("src.access.Speech")

  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts) said[#said + 1] = tostring(text) return say(text, opts) end

  local function screenName()
    local Message = package.loaded["src.ui.game3.message"]
    if Message and Message.isOpen and Message.isOpen() then return "message" end
    local Stack = package.loaded["src.ui.game3.stack"]
    local top = Stack and Stack.top and Stack.top()
    if top then return "layer:" .. tostring(top.id) end
    return "phase:" .. tostring(game.phase)
  end
  local last
  local function watch()
    local name = screenName()
    if name ~= last then U.log("SCREEN", name) last = name end
    for _, line in ipairs(said) do U.log("SAID", line) end
    said = {}
  end
  local function wait(n) for _ = 1, n do U.wait(1) watch() end end
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    wait(2)
    game.input.state[button] = false
    wait(frames or 8)
  end

  -- intro and title: wait, then press start a few times
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    wait(1)
  end
  wait(240)
  for _ = 1, 4 do tap("start", 60) end
  -- new game, as upstream's Gen 3 drivers start one
  local ok, err = pcall(function()
    game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  end)
  if not ok then U.log("FAIL", "new game: " .. tostring(err)) return end
  wait(120)
  -- talk through any opening text
  for _ = 1, 60 do
    local Message = package.loaded["src.ui.game3.message"]
    if not (Message and Message.isOpen and Message.isOpen()) then break end
    tap("a", 20)
  end
  U.log("MAP", tostring(require("src.core.game3.runtime").getSession().map))

  -- start menu, move, open the bag, back out
  tap("start", 30)
  for _ = 1, 3 do tap("down", 15) end
  tap("up", 15) tap("up", 15) tap("up", 15)
  tap("a", 60)
  tap("right", 30)
  tap("down", 15)
  for _ = 1, 4 do tap("b", 30) end

  -- a wild battle
  local Runtime = require("src.core.game3.runtime")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local started, why = pcall(BattleBridge.startWild, Runtime._mod, game, { species = 16, level = 3 }, { fade = false })
  if not started then U.log("FAIL", "battle: " .. tostring(why)) end
  for _ = 1, 300 do tap("a", 20) end
  wait(60)
  Speech.say = say
  U.log("DONE")
end
