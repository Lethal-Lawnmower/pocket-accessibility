-- A game run for the shops module, on Crystal, with no core: the driver builds
-- the module's ctx from tests/fake_ctx.lua (a fixed seed, both shop answers
-- YES), hands it the live game, and then, for a few marts:
--   1. opens the mart through World:openMart (what the `pokemart` script
--      command calls), goes into BUY and checks the screen's own entries are
--      the shelf the module built, priced from the item data;
--   2. steps down the whole list and checks every row the screen reader says
--      names that entry and its price;
--   3. on the first mart, buys one of the first row and checks the bag.
-- Then a vanilla save puts the cart's shelf back, and the mart says so too.
-- Run silently and isolated, with a disposable identity:
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_BACKGROUND=1 POKEPORT_VERSION=crystal
--   POKEPORT_GAME=crystal POKEPORT_IDENTITY=pocket-access-rand2-shops-<x>
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=launcher/mods/crystal_randomizer/tests/shops_driver.lua
--   "C:\Program Files\LOVE\lovec.exe" .
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
  local Shops = dofile("launcher/mods/crystal_randomizer/modules/shops.lua")
  local failed = 0
  local function check(cond, ...)
    if not cond then failed = failed + 1 end
    U.log(cond and "RESULT" or "FAIL", ...)
  end

  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") return end
  U.log("RESULT", "start", L.where())
  local data = game.data
  local lists = Shops.shelves(data.gen2Marts)
  if not lists then U.log("FAIL", "no mart shelves in game data") return end
  check(game.world.marts == data.gen2Marts, "the world's marts are data.gen2Marts")

  local seed = os.getenv("RAND_SEED") or "driver-seed"
  local ctx = Fake.new({ seed = seed, options = { shops = true, shops_better = true } })
  Shops.install({ game = game }, ctx)
  local vanilla = {}
  for i, list in ipairs(lists) do vanilla[i] = table.concat(list, ",") end
  ctx.setActive(true)
  for _, line in ipairs(ctx.lines) do U.log("MODLOG", line) end

  -- letters only, so "POKé BALL" and its spoken form compare equal
  local function letters(s) return (tostring(s):upper():gsub("[^A-Z0-9]", "")) end

  local function openMart(martId)
    local closed = false
    L.heard()
    game.world:openMart(0, martId, function() closed = true end)
    L.wait(20)
    local mart = game.stack:top()
    return mart, function() return closed end
  end

  local function closeMart(isClosed)
    for _ = 1, 60 do
      if isClosed() and L.free() then return true end
      L.tap("b", 10)
    end
    return isClosed()
  end

  local function visit(martId, buy)
    local mart, isClosed = openMart(martId)
    if not (mart and mart.entries) then check(false, "mart", martId, "did not open") return end
    L.tap("a", 20) -- BUY
    check(mart.phase == "buy", "mart", martId, "in BUY", tostring(mart.phase))
    local shelf = lists[martId + 1]
    local ids, rows = {}, {}
    for i, entry in ipairs(mart.entries) do
      ids[i] = entry.id
      local def = data.items[entry.id]
      check(def and entry.price == def.price and def.price > 0, "mart", martId, "row", i, entry.id,
        "price", entry.price, "item data", def and def.price)
    end
    check(table.concat(ids, ",") == table.concat(shelf, ","), "mart", martId, "screen entries = shelf:",
      table.concat(ids, ","))
    local spoken = {}
    spoken[1] = L.heard()
    for i = 2, #mart.entries + 1 do
      L.tap("down", 12)
      spoken[i] = L.heard()
    end
    for i, entry in ipairs(mart.entries) do
      local said = spoken[i] or ""
      local okName = letters(said):find(letters(entry.name), 1, true) ~= nil
      local okPrice = said:find("¥" .. tostring(entry.price), 1, true) ~= nil
      check(okName and okPrice, "mart", martId, "row", i, "spoken:", said)
      rows[#rows + 1] = entry.name .. " " .. entry.price
    end
    check(letters(spoken[#mart.entries + 1] or ""):find("CANCEL", 1, true) ~= nil, "mart", martId,
      "last row spoken:", spoken[#mart.entries + 1])
    U.log("RESULT", "mart", martId, "sells", table.concat(rows, ", "))
    if buy then
      for _ = 1, #mart.entries do L.tap("up", 8) end
      local first = mart.entries[1]
      game.save.player.money = 50000
      local before = (game.save.inventory or {})[first.id]
      L.heard()
      L.tap("a", 20) -- the row: quantity selector
      L.tap("a", 40) -- one: the price question
      for _ = 1, 10 do
        if mart.confirm and mart:yesNoVisible() then break end
        L.tap("a", 20)
      end
      L.tap("a", 40) -- YES
      local after = (game.save.inventory or {})[first.id]
      check(game.save.player.money == 50000 - first.price and (after or 0) == (before or 0) + 1,
        "bought one", first.id, "money now", game.save.player.money, "bag", tostring(before), "->",
        tostring(after))
      U.log("RESULT", "purchase speech =>", L.heard())
    end
    check(closeMart(isClosed), "mart", martId, "closed")
  end

  visit(0, true)  -- Cherrygrove, before the POKeDEX
  visit(6, false) -- Goldenrod 2F, the BALL counter
  visit(8, false) -- Goldenrod 4F, vitamins and (better marts) stones

  ctx.setActive(false)
  local same = true
  for i, list in ipairs(lists) do if table.concat(list, ",") ~= vanilla[i] then same = false end end
  check(same, "a vanilla save puts every shelf back")
  local mart, isClosed = openMart(0)
  local ids = {}
  for i, entry in ipairs(mart and mart.entries or {}) do ids[i] = entry.id end
  check(table.concat(ids, ",") == vanilla[1], "vanilla Cherrygrove screen sells", table.concat(ids, ","))
  closeMart(isClosed)
  U.log(failed == 0 and "RESULT" or "FAIL", "shops driver failures", failed)
  U.log("DONE")
  love.event.quit()
end
