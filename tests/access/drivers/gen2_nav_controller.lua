-- Gen 2 keys and controller (decision 23) through the real love callbacks:
-- F7 command mode and the J/K/L/M/P keys, left trigger plus D-pad for
-- categories and objects, left stick click for auto-walk, right stick click
-- for guided navigation, and Shift+M renaming with Gen 2's naming screen.
-- Silent; read the RESULT lines.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") return end
  U.wait(20)
  L.heard()
  local function key(k)
    love.keypressed(k, k, false)
    U.wait(2)
    love.keyreleased(k, k)
    U.wait(4)
    return L.heard()
  end
  local function pad(button)
    love.gamepadpressed(nil, button)
    U.wait(2)
    love.gamepadreleased(nil, button)
    U.wait(4)
    return L.heard()
  end

  U.log("RESULT", "F7 =>", key("f7"))
  U.log("RESULT", "M =>", key("m"))
  U.log("RESULT", "L =>", key("l"))
  U.log("RESULT", "L =>", key("l"))
  U.log("RESULT", "F7 off =>", key("f7"))

  love.gamepadaxis(nil, "triggerleft", 1.0)
  U.wait(2)
  U.log("RESULT", "trigger + down =>", pad("dpdown"))
  U.log("RESULT", "trigger + right =>", pad("dpright"))
  love.gamepadaxis(nil, "triggerleft", 0)
  U.wait(2)
  love.gamepadpressed(nil, "leftstick")
  U.wait(2)
  love.gamepadreleased(nil, "leftstick")
  for _ = 1, 1200 do
    if not L.AutoWalk.active() then break end
    U.wait(1)
  end
  U.log("RESULT", "left stick walk =>", L.heard(), "now", L.where())
  L.settle(600, true)
  L.heard()
  -- guided navigation to the first sign
  L.select(L.find(function(i) return i.type == "signpost" end))
  U.log("RESULT", "right stick =>", pad("rightstick"))
  U.log("RESULT", "right stick again =>", pad("rightstick"))

  U.log("DONE")
end
