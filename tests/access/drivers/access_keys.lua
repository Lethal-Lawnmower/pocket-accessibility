-- The keyboard's navigation keys in any game, through the accessibility module's key
-- handler (isolated.lua keeps real keys out): F7, then L to pick something, K for spoken
-- directions and K to stop, Shift+K to auto-walk.  Keys now free must do nothing.
-- Silent; read the RESULT and FAIL lines.
return function(game)
  local version = os.getenv("POKEPORT_VERSION") or "red"
  local isGen3 = version == "firered" or version == "leafgreen" or version == "ruby"
    or version == "sapphire" or version == "emerald"
  local isGen1 = version == "red" or version == "blue" or version == "yellow"
  local L = dofile(isGen3 and "tests/access/drivers/gen3_nav_lib.lua"
    or "tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local started
  if isGen3 then started = L.boot()
  elseif isGen1 then started = U.newGame(game)
  else started = L.settle(2000, true) end
  if not started then U.log("FAIL", "never reached the free world") return end
  U.wait(30)
  local Nav = require("src.access.nav")
  local AutoWalk = require("src.access.nav.AutoWalk")
  local Speech = require("src.access.Speech")
  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts) said[#said + 1] = tostring(text) return say(text, opts) end
  local function heard() local s = table.concat(said, " | ") said = {} return s end

  local realIsDown = love.keyboard.isDown
  local function key(k, shift)
    love.keyboard.isDown = function(name) return shift == true and name == "lshift" end
    local consumed = Nav.keypressed(k, k, false)
    Nav.keyreleased(k, k)
    love.keyboard.isDown = realIsDown
    U.wait(15)
    return consumed
  end
  local function check(ok, text) U.log(ok and "RESULT" or "FAIL", text) end

  key("f8")
  local help = heard()
  check(help:find("Shift K auto-walks", 1, true) ~= nil and help:find("left trigger", 1, true) ~= nil
    and help:find("sonar", 1, true) == nil, "F8 says the keys that exist: " .. help:sub(1, 200))
  key("f7")
  heard()
  local picked
  for _ = 1, 40 do
    key("l")
    picked = heard()
    if picked ~= "" then break end
  end
  check(picked ~= "", "L picks something: " .. picked)
  said = {}
  check(key("k") == true, "K is a command")
  local guided = heard()
  check(guided ~= "" and not AutoWalk.walking(), "K gives directions and does not walk: " .. guided)
  key("k")
  U.log("RESULT", "K again =>", heard())
  check(key("k", true) == true, "Shift+K is a command")
  local frames = 0
  while AutoWalk.active() and frames < 900 do
    if L.messageOpen and L.messageOpen() then L.tap("a", 2) else U.wait(1) end
    frames = frames + 1
  end
  local walked = heard()
  check(walked:find("Walking to", 1, true) ~= nil or walked:find("is here", 1, true) ~= nil or walked:find("No route", 1, true) ~= nil,
    "Shift+K auto-walks: " .. walked:sub(1, 160))
  if AutoWalk.active() then AutoWalk.stop() end
  said = {}
  check(not key("m", true), "Shift+M is free")
  check(not key("0", true), "Shift+0 is free")
  check(not key("p"), "P is free")
  check(heard() == "", "the free keys say nothing")

  -- On a menu and in a battle the navigation keys belong to the game (decision 46); H still answers.
  local tap = isGen1 and function(button) U.tap(game, button) U.wait(10) end or function(button) L.tap(button, 10) end
  local function offMap() return Nav.coordinator():worldForCommand() == nil end
  local function keysOff(where)
    for _, chord in ipairs({ { "j" }, { "l" }, { "k" }, { "j", true }, { "l", true }, { "k", true } }) do
      local name = (chord[2] and "Shift+" or "") .. chord[1]
      check(not key(chord[1], chord[2]), name .. " passes through on " .. where)
    end
    check(not AutoWalk.active(), "no walk started on " .. where)
  end
  tap("start")
  U.wait(30)
  check(offMap(), "the start menu is open")
  keysOff("the start menu")
  tap("b")
  U.wait(30)
  for _ = 1, 60 do if not offMap() then break end tap("b") end

  local inBattle
  if isGen3 then
    L.giveParty(9, 50, { "SURF", "STRENGTH", "CUT" })
    local Runtime = require("src.core.game3.runtime")
    local Battle = require("src.core.game3.battle")
    require("src.core.game3.battle_bridge").startWild(Runtime._mod, game, { species = 19, level = 3 }, { fade = false })
    inBattle = function() return Battle.isActive() end
  elseif isGen1 then
    local BattleState = require("src.battle.BattleState")
    game.save.party = { require("src.pokemon.Pokemon").new(game.data, "SQUIRTLE", 12) }
    local battle = BattleState.newWild(game, "PIDGEY", 3)
    game.overworld:pushBattle(battle)
    inBattle = function() return game.stack:top() == battle end
  else
    local Mon = require("src.battle.gen2.Mon")
    game.save.party = { Mon.new(game.data, "CYNDAQUIL", 10) }
    game.world:startBattle({ wild = Mon.new(game.data, "SENTRET", 5) })
    local BattleState = require("src.ui.gen2.BattleState")
    inBattle = function() return getmetatable(game.stack:top()) == BattleState end
  end
  for _ = 1, 900 do if inBattle() then break end U.wait(1) end
  check(inBattle(), "a battle is on screen")
  -- through the opening lines to the battle's own menu, with both sides out
  said = {}
  for _ = 1, 80 do
    if table.concat(said, " "):find("FIGHT", 1, true) then break end
    U.wait(30)
    if not table.concat(said, " "):find("FIGHT", 1, true) then tap("a") end
  end
  check(table.concat(said, " "):find("FIGHT", 1, true) ~= nil, "the battle menu is up")
  U.wait(30)
  keysOff("a battle")
  said = {}
  check(key("h") == true, "H is a command in a battle")
  local enemy = heard()
  check(key("h", true) == true, "Shift+H is a command in a battle")
  local mine = heard()
  check(enemy:lower():find("health", 1, true) ~= nil or enemy:find("HP", 1, true) ~= nil, "H says enemy health: " .. enemy:sub(1, 120))
  check(mine:lower():find("health", 1, true) ~= nil or mine:find("HP", 1, true) ~= nil, "Shift+H says player health: " .. mine:sub(1, 120))
  U.log("DONE")
end
