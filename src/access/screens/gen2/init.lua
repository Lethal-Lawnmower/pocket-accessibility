-- Gen 2 presenters (Gold, Silver, Crystal; decision 27), collected in one
-- list that Presenters appends to its own.  Each module returns
-- `{ ordered = { presenter, ... } }` with the same matches/poll contract as
-- src/access/screens/Presenters.lua.  Gen 2 classes live at their own paths
-- (src/ui/gen2/...), so none of these can match a Gen 1 screen.

local Gen2 = { ordered = {} }

for _, name in ipairs({ "Menus", "Items", "Info", "Special", "Battle" }) do
  local mod = require("src.access.screens.gen2." .. name)
  for _, presenter in ipairs(mod.ordered or {}) do
    Gen2.ordered[#Gen2.ordered + 1] = presenter
  end
end

return Gen2
