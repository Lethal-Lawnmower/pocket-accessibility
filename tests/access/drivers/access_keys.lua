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
  key("f7")
  U.log("DONE")
end
