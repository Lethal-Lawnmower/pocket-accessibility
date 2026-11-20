-- ShopMoney: which shop is open in each generation, and the money said
-- (decision 77).  Run: luajit tests/access/shop_money_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local eq = T.eq

local ShopMoney = require("src.access.ShopMoney")

local function clear()
  package.loaded["src.ui.game3.shop_menu"] = nil
  package.loaded["src.ui.gen2.MartMenu"] = nil
end

-- nothing open
clear()
eq(ShopMoney.text({ stack = { states = { {} } }, save = { money = 5 } }), nil, "no shop: nil")
eq(ShopMoney.text(nil), nil, "no game: nil")

-- Gen 3: the shop module is open, its session's money
package.loaded["src.ui.game3.shop_menu"] = { open = true, _session = { money = 3000.7 } }
eq(ShopMoney.text({}), "Money ¥3000", "Gen 3 open shop: the session's money")
package.loaded["src.ui.game3.shop_menu"] = { open = false, _session = { money = 3000 } }
eq(ShopMoney.text({ stack = { states = {} } }), nil, "Gen 3 shop closed: nil")

-- Gen 2: a MartMenu state on the stack, under other screens too
clear()
local Mart = {}
package.loaded["src.ui.gen2.MartMenu"] = Mart
local mart = setmetatable({ save = { player = { money = 1234 } } }, Mart)
eq(ShopMoney.text({ stack = { states = { {}, mart, {} } } }), "Money ¥1234", "Gen 2 mart under a text box")
eq(ShopMoney.text({ stack = { states = { {}, setmetatable({}, {}) } } }), nil, "Gen 2 without a mart: nil")

-- Gen 1: a state whose draw was built by src/ui/ShopMenu.lua
clear()
local ok, ShopMenu1 = pcall(require, "src.ui.ShopMenu")
if ok and type(ShopMenu1) == "table" then
  -- a function defined in that file stands in for the menu's draw closure
  local fromShopFile
  for _, v in pairs(ShopMenu1) do if type(v) == "function" then fromShopFile = v break end end
  eq(ShopMoney.text({ save = { money = 77 }, stack = { states = { { draw = fromShopFile } } } }),
    "Money ¥77", "Gen 1 shop menu on the stack: save money")
end
eq(ShopMoney.text({ save = { money = 77 }, stack = { states = { { draw = function() end } } } }),
  nil, "Gen 1 other menu: nil")

T.finish("shop money")
