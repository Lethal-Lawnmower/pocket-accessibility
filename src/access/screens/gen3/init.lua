-- Gen 3 presenters (FireRed, LeafGreen; Ruby, Sapphire, Emerald in the Hoenn
-- files, first because a few share a module with FireRed and match only a
-- Hoenn game; decision 29), collected in one list
-- that Presenters appends to its own.  They match only the proxies
-- gen3/Top.lua builds ({ gen3 = <kind>, ... }), so none can match a Gen 1
-- or Gen 2 screen.

local Gen3 = { ordered = {} }

for _, name in ipairs({ "HoennBoot", "HoennMenus", "HoennItems", "HoennSpecial", "HoennPokenav", "Dialogue", "Menus", "Items", "Special", "Battle" }) do
  local mod = require("src.access.screens.gen3." .. name)
  for _, presenter in ipairs(mod.ordered or {}) do
    Gen3.ordered[#Gen3.ordered + 1] = presenter
  end
end

return Gen3
