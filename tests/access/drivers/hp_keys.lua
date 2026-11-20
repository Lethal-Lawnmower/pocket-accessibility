-- Presses the in-battle health keys as a controller does (the owner,
-- 2026-11-20): hold the left trigger, D-pad up (your HP) then D-pad down (the
-- enemy's), through the access layer's love.gamepad* hooks.  Logs
-- "HPKEY up <said>" and "HPKEY down <said>"; "(nothing)" when nothing was said.
-- Used by battle.lua (Gen 1), gen2_battle.lua and gen3_battle.lua.
return function(U)
  local Nav = require("src.access.nav")
  local Speech = require("src.access.Speech")
  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts) said[#said + 1] = tostring(text) return say(text, opts) end
  local ok, err = pcall(function()
    Nav.gamepadaxis(nil, "triggerleft", 1)
    U.wait(3)
    for _, button in ipairs({ "dpup", "dpdown" }) do
      said = {}
      local consumed = Nav.gamepadpressed(nil, button)
      U.wait(3)
      Nav.gamepadreleased(nil, button)
      U.wait(3)
      U.log("HPKEY", button == "dpup" and "up" or "down", consumed and "consumed" or "NOT consumed",
        #said > 0 and table.concat(said, " / ") or "(nothing)")
    end
    Nav.gamepadaxis(nil, "triggerleft", 0)
    U.wait(3)
  end)
  Speech.say = say
  if not ok then U.log("FAIL", "hp keys: " .. tostring(err)) end
end
