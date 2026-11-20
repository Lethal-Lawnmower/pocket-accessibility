-- The player's money while a shop is open (the owner, 2026-11-20: "L3 in
-- shops checks money").  The left stick click and, on touch, a one-finger
-- tap off the map ask for it (src/access/nav/init.lua, src/access/touch/
-- TouchInput.lua; decision 77).
--
-- A shop is open when, in each generation's own shop code:
--   Gen 1  a state on the game stack was built by src/ui/ShopMenu.lua (the
--          BUY / SELL / QUIT menu and its buy and sell lists); money is
--          game.save.money, as the shop's money box draws it.
--   Gen 2  a src/ui/gen2/MartMenu.lua state is on the stack; money is
--          save.player.money, as MartMenu reads it.
--   Gen 3  src/ui/game3/shop_menu.lua is open (all five games, selling
--          included); money is its session's, as its money box shows it.
-- Only shown values are read; nil means no shop is open.

local ShopMoney = {}

local function builtByGen1Shop(state)
  for _, fn in ipairs({ rawget(state, "draw"), rawget(state, "money") }) do
    if type(fn) == "function" then
      local info = debug.getinfo(fn, "S")
      if info and info.source and info.source:find("src[/%\\]ui[/%\\]ShopMenu%.lua$") then return true end
    end
  end
  return false
end

local function wholeAmount(value)
  local n = tonumber(value)
  if not n then return nil end
  return math.max(0, math.floor(n))
end

-- The money while a shop is open, else nil.
function ShopMoney.amount(game)
  local Shop3 = package.loaded["src.ui.game3.shop_menu"]
  if type(Shop3) == "table" and rawget(Shop3, "open") == true then
    local session = rawget(Shop3, "_session")
    return wholeAmount(type(session) == "table" and session.money)
  end
  local states = type(game) == "table" and game.stack and game.stack.states
  if type(states) ~= "table" then return nil end
  local Mart2 = package.loaded["src.ui.gen2.MartMenu"]
  for i = #states, 1, -1 do
    local state = states[i]
    if type(state) == "table" then
      if Mart2 and getmetatable(state) == Mart2 then
        local player = type(state.save) == "table" and state.save.player
        return wholeAmount(type(player) == "table" and player.money or 0)
      end
      if builtByGen1Shop(state) then
        return wholeAmount(type(game.save) == "table" and game.save.money or 0)
      end
    end
  end
  return nil
end

-- "Money ¥3000" while a shop is open, else nil.
function ShopMoney.text(game)
  local amount = ShopMoney.amount(game)
  return amount and ("Money ¥" .. tostring(amount)) or nil
end

return ShopMoney
