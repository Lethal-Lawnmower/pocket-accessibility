-- Presses the left stick click as a controller does, through the access
-- layer's love.gamepad* hooks, and logs what was said: "SHOPKEY <label>
-- consumed|NOT consumed <said>" ("(nothing)" when nothing was said).  In a
-- shop it should say the money (decision 77).  Used by more_screens.lua
-- (Gen 1), gen2_items.lua, gen3_items.lua and rse_screens.lua.
return function(U, label)
  U = U or dofile("tests/drivers/util.lua")
  local Nav = require("src.access.nav")
  local Speech = require("src.access.Speech")
  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts) said[#said + 1] = tostring(text) return say(text, opts) end
  local ok, err = pcall(function()
    local consumed = Nav.gamepadpressed(nil, "leftstick")
    U.wait(3)
    Nav.gamepadreleased(nil, "leftstick")
    U.wait(3)
    U.log("SHOPKEY", label or "", consumed and "consumed" or "NOT consumed",
      #said > 0 and table.concat(said, " / ") or "(nothing)")
  end)
  Speech.say = say
  if not ok then U.log("FAIL", "shop key: " .. tostring(err)) end
end
