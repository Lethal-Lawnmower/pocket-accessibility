-- luajit launcher/mods/crystal_randomizer/tests/shops_test.lua   (from the repository root)
--
-- Runs on a small synthetic dataset shaped like Crystal's extracted marts,
-- items and evolutions.  With CRYSTAL_RANDOMIZER_CACHE set to an imported
-- cache's data/generated folder, it also runs against the real Crystal tables
-- and prints one seed's Cherrygrove and Goldenrod stock.
local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Shops = dofile("launcher/mods/crystal_randomizer/modules/shops.lua")

local failures, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg) ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local function item(index, pocket, price, battle, field, extra)
  local def = { index = index, pocket = pocket, price = price, canToss = true, battleMenu = battle,
    fieldMenu = field, heldEffect = "HELD_NONE", heldParameter = 0 }
  for k, v in pairs(extra or {}) do def[k] = v end
  def.name = def.name or "ITEM" .. index
  return def
end

local function syntheticData()
  local B, P, C, N, U = "ITEMMENU_CLOSE", "ITEMMENU_PARTY", "ITEMMENU_CURRENT", "ITEMMENU_NOUSE", nil
  local items = {
    MASTER_BALL = item(1, "BALL", 0, B, N),
    ULTRA_BALL = item(2, "BALL", 1200, B, N),
    GREAT_BALL = item(4, "BALL", 600, B, N),
    POKE_BALL = item(5, "BALL", 200, B, N),
    MOON_STONE = item(8, "ITEM", 0, N, P),
    ANTIDOTE = item(9, "ITEM", 100, P, P),
    HYPER_POTION = item(16, "ITEM", 1200, P, P, { heldParameter = 200 }),
    SUPER_POTION = item(17, "ITEM", 700, P, P, { heldParameter = 50 }),
    POTION = item(18, "ITEM", 300, P, P, { heldParameter = 20 }),
    REPEL = item(20, "ITEM", 350, N, C),
    FIRE_STONE = item(22, "ITEM", 2100, N, P),
    ITEM_19 = item(25, "ITEM", 0x9999, N, N, { name = "TERU-SAMA" }),
    PROTEIN = item(27, "ITEM", 9800, N, P),
    IRON = item(28, "ITEM", 9800, N, P),
    NUGGET = item(36, "ITEM", 10000, N, N),
    ETHER = item(63, "ITEM", 1200, P, P, { heldParameter = 10 }),
    X_ATTACK = item(49, "ITEM", 500, B, N),
    X_DEFEND = item(51, "ITEM", 550, B, N),
    BICYCLE = item(7, "KEY_ITEM", 0, N, B, { canToss = false }),
    FLOWER_MAIL = item(158, "ITEM", 50, N, N),
    TM_A = item(191, "TM_HM", 3000, N, P),
    TM_B = item(192, "TM_HM", 2000, N, P),
    TM_C = item(193, "TM_HM", 1000, N, P),
    HM_SURF = item(245, "TM_HM", 0, N, P, { canToss = false }),
  }
  local marts = {
    generation = 2,
    lists = {
      { "POTION", "ANTIDOTE" },                                                       -- 1 no BALL
      { "POKE_BALL", "POTION", "ANTIDOTE" },                                          -- 2
      { "POKE_BALL", "GREAT_BALL", "SUPER_POTION", "REPEL" },                         -- 3
      { "X_ATTACK", "X_DEFEND" },                                                     -- 4 specialty
      { "PROTEIN", "IRON" },                                                          -- 5 vitamins
      { "TM_A", "TM_B" },                                                             -- 6 TMs
      { "POKE_BALL", "GREAT_BALL", "ULTRA_BALL", "POTION", "SUPER_POTION", "HYPER_POTION" },
      { "GREAT_BALL", "ULTRA_BALL", "SUPER_POTION", "HYPER_POTION" },
      { "ULTRA_BALL", "HYPER_POTION", "FLOWER_MAIL" },                                -- 9 no POKE BALL
    },
    bargain = { { item = "NUGGET", price = 4500 } },
  }
  local pokemon = {
    GROWLITHE = { evolutions = { { method = "EVOLVE_ITEM", item = "FIRE_STONE", into = "ARCANINE" } } },
    NIDORINO = { evolutions = { { method = "EVOLVE_ITEM", item = "MOON_STONE", into = "NIDOKING" } } },
    SCYTHER = { evolutions = { { method = "EVOLVE_TRADE", item = "METAL_COAT", into = "SCIZOR" } } },
  }
  return { items = items, gen2Marts = marts, pokemon = pokemon }
end

local function show(list) return table.concat(list or {}, ",") end

-- shelf contents as strings, and the shelf tables themselves
local function snapshot(data)
  local out, refs = {}, {}
  for i, list in ipairs(data.gen2Marts.lists) do out[i], refs[i] = show(list), list end
  local rows = {}
  for _, row in ipairs(data.gen2Marts.bargain or {}) do rows[#rows + 1] = row.item .. ":" .. row.price end
  out.bargain = table.concat(rows, ",")
  return out, refs
end

local function same(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end

local function setup(data, seed, options)
  local ctx = Fake.new({ seed = seed, options = options })
  Shops.install({ game = { data = data } }, ctx)
  ctx.setActive(seed ~= nil, seed, options)
  return ctx
end

local function has(list, id)
  for _, v in ipairs(list or {}) do if v == id then return true end end
  return false
end

-- invariants every changed save must keep
local function invariants(data, vanillaLists, label)
  local survey = Shops.survey(vanillaLists, data.items)
  for i, list in ipairs(data.gen2Marts.lists) do
    local seen = {}
    for _, id in ipairs(list) do
      ok(not seen[id], label .. ": no item twice on shelf " .. i .. " (" .. id .. ")")
      seen[id] = true
      local def = data.items[id]
      ok(Shops.sellable(def), label .. ": shelf " .. i .. " sells only sellable items (" .. id .. ")")
      ok(def and def.pocket ~= "KEY_ITEM" and def.canToss ~= false,
        label .. ": no key item or HM on shelf " .. i .. " (" .. id .. ")")
      ok(def and (def.price or 0) > 0, label .. ": a price from the item data on shelf " .. i)
    end
    if survey.general[i] then
      ok(has(list, "POKE_BALL"), label .. ": general shelf " .. i .. " sells POKE BALLs")
      ok(has(list, "POTION"), label .. ": general shelf " .. i .. " sells POTIONs")
    end
  end
end

-- Oak's box: two lines of at most 18 characters, \v scrolls, \f starts a box.
local function fitsOak(text)
  for box in (text .. "\f"):gmatch("(.-)\f") do
    for line in (box:gsub("\v", "\n") .. "\n"):gmatch("(.-)\n") do
      if #line > 18 then return false, line end
    end
  end
  return true
end

-- ------------------------------------------------------------ questions
do
  local q = {}
  for _, question in ipairs(Shops.questions) do q[question.key] = question end
  ok(q.shops and q.shops_better, "both questions exist")
  eq(q.shops.recommended, false, "shuffle: off in RECOMMENDED")
  eq(q.shops.everything, true, "shuffle: on in EVERYTHING")
  eq(q.shops_better.recommended, true, "better marts: on in RECOMMENDED")
  eq(q.shops_better.everything, true, "better marts: on in EVERYTHING")
  eq(q.shops_better.onlyIf, nil, "better marts is asked on its own")
  for _, question in ipairs(Shops.questions) do
    local fits, line = fitsOak(question.text)
    ok(fits, "question " .. question.key .. " fits Oak's box (" .. tostring(line) .. ")")
    eq(question.kind, "yesno", "question " .. question.key .. " is yes/no")
  end
end

-- ------------------------------------------------------------ vanilla
do
  local data = syntheticData()
  local vanilla, refs = snapshot(data)
  setup(data, nil, {})
  ok(same(vanilla, snapshot(data)), "vanilla save leaves every shelf as it is")
  setup(data, "seed", { shops = false, shops_better = false })
  ok(same(vanilla, snapshot(data)), "both answered no leaves every shelf as it is")
  for i, list in ipairs(data.gen2Marts.lists) do ok(list == refs[i], "vanilla shelf table kept " .. i) end
end

-- ------------------------------------------------------------ better marts on the vanilla stock
do
  local data = syntheticData()
  local vanilla, refs = snapshot(data)
  local vanillaLists = {}
  for i, l in ipairs(refs) do vanillaLists[i] = l end
  local ctx = setup(data, "b", { shops = false, shops_better = true })
  local L = data.gen2Marts.lists
  eq(show(L[1]), "POKE_BALL,GREAT_BALL,POTION,SUPER_POTION,ANTIDOTE", "better: shelf without BALLs gets POKE BALL, then a rung up")
  eq(show(L[2]), "POKE_BALL,GREAT_BALL,POTION,SUPER_POTION,ANTIDOTE", "better: POKE BALL shop gets GREAT BALL and SUPER POTION")
  eq(show(L[3]), "POKE_BALL,GREAT_BALL,ULTRA_BALL,POTION,SUPER_POTION,HYPER_POTION,REPEL",
    "better: POTION after the BALLs, one rung above the best of each")
  eq(show(L[4]), vanilla[4], "better: X item shelf unchanged")
  eq(show(L[5]), "PROTEIN,IRON,FIRE_STONE", "better: vitamin shelf gets the sellable evolution stones (MOON STONE is priced 0)")
  eq(show(L[6]), vanilla[6], "better: TM shelf unchanged")
  eq(show(L[9]), "POKE_BALL,ULTRA_BALL,POTION,HYPER_POTION,FLOWER_MAIL", "better: top shelf gets the essentials only")
  ok(not has(L[1], "ETHER"), "better: a PP item is not on the potion ladder")
  for i, list in ipairs(vanillaLists) do
    for _, id in ipairs(list) do ok(has(L[i], id), "better keeps vanilla stock: shelf " .. i .. " " .. id) end
  end
  invariants(data, vanillaLists, "better")
  eq(snapshot(data).bargain, vanilla.bargain, "better: bargain shop untouched")
  ctx.setActive(false)
  ok(same(vanilla, snapshot(data)), "better: restored for a vanilla save")
  for i, list in ipairs(data.gen2Marts.lists) do ok(list == refs[i], "better: the cart's own shelf table is back " .. i) end
end

-- ------------------------------------------------------------ shuffle
do
  local data = syntheticData()
  local vanilla, refs = snapshot(data)
  local vanillaLists = {}
  for i, l in ipairs(refs) do vanillaLists[i] = l end
  local ctx = setup(data, "alpha", { shops = true, shops_better = false })
  local alpha = snapshot(data)
  invariants(data, vanillaLists, "shuffle")
  -- each vanilla slot's kind is kept (essentials may be put in front)
  for i, list in ipairs(vanillaLists) do
    local now = data.gen2Marts.lists[i]
    ok(#now >= #list and #now <= #list + #Shops.ESSENTIALS, "shuffle: shelf " .. i .. " keeps its length")
    local kinds = {}
    for _, id in ipairs(list) do local k = Shops.kind(data.items[id]); kinds[k] = (kinds[k] or 0) + 1 end
    local got = {}
    for _, id in ipairs(now) do local k = Shops.kind(data.items[id]); got[k] = (got[k] or 0) + 1 end
    for k, n in pairs(kinds) do
      ok((got[k] or 0) >= n, "shuffle: shelf " .. i .. " keeps " .. n .. " of kind " .. k)
    end
  end
  eq(snapshot(data).bargain, vanilla.bargain, "shuffle: bargain shop untouched")

  -- determinism
  local data2 = syntheticData()
  setup(data2, "alpha", { shops = true, shops_better = false })
  ok(same(alpha, snapshot(data2)), "shuffle: same seed, same shelves")

  local moved = false
  for n = 1, 10 do
    local d = syntheticData()
    setup(d, "s" .. n, { shops = true })
    local snap = snapshot(d)
    for i = 1, #d.gen2Marts.lists do if snap[i] ~= alpha[i] then moved = true end end
  end
  ok(moved, "shuffle: another seed gives other shelves")

  -- switching saves
  ctx.setActive(false)
  ok(same(vanilla, snapshot(data)), "shuffle: vanilla save after a randomized one restores")
  for i, list in ipairs(data.gen2Marts.lists) do ok(list == refs[i], "shuffle: the cart's own shelf table is back " .. i) end
  ctx.setActive(true, "beta", { shops = true })
  local d3 = syntheticData()
  setup(d3, "beta", { shops = true })
  ok(same(snapshot(d3), snapshot(data)), "shuffle: switching saves gives that save's shelves, not a stack")
  ctx.setActive(true, "alpha", { shops = true })
  ok(same(alpha, snapshot(data)), "shuffle: back to the first save gives its shelves again")
  ctx.setActive(true, "alpha", { shops = true })
  ok(same(alpha, snapshot(data)), "shuffle: the same save reported twice does not shuffle twice")
  ctx.setActive(false)
  for i = 1, #refs do eq(show(refs[i]), vanilla[i], "shuffle: vanilla shelf table never edited " .. i) end
end

-- ------------------------------------------------------------ both
do
  local data = syntheticData()
  local vanilla, refs = snapshot(data)
  local vanillaLists = {}
  for i, l in ipairs(refs) do vanillaLists[i] = l end
  local ctx = setup(data, "gamma", { shops = true, shops_better = true })
  invariants(data, vanillaLists, "both")
  ok(has(data.gen2Marts.lists[5], "FIRE_STONE"), "both: stones still added to the vitamin shelf")
  local d2 = syntheticData()
  setup(d2, "gamma", { shops = true, shops_better = true })
  ok(same(snapshot(d2), snapshot(data)), "both: same seed, same shelves")
  ctx.setActive(false)
  ok(same(vanilla, snapshot(data)), "both: restored")
end

-- ------------------------------------------------------------ real Crystal data
local cache = os.getenv("CRYSTAL_RANDOMIZER_CACHE")
if cache and cache ~= "" then
  local function load()
    return { items = dofile(cache .. "/items.lua"), gen2Marts = dofile(cache .. "/marts.lua"),
      pokemon = dofile(cache .. "/pokemon.lua") }
  end
  local data = load()
  local vanilla, refs = snapshot(data)
  local vanillaLists = {}
  for i, l in ipairs(refs) do vanillaLists[i] = l end
  eq(#data.gen2Marts.lists, 34, "real data: 34 shelves")
  local survey = Shops.survey(vanillaLists, data.items)
  local general = {}
  for i = 1, #vanillaLists do if survey.general[i] then general[#general + 1] = i - 1 end end
  print("  real data: general marts (mart ids) " .. table.concat(general, ","))
  local balls, potions = Shops.ladders(data.items, survey)
  eq(show(balls), "POKE_BALL,GREAT_BALL,ULTRA_BALL", "real data: BALL ladder")
  eq(show(potions), "POTION,SUPER_POTION,HYPER_POTION,MAX_POTION", "real data: potion ladder")
  print("  real data: evolution items sold " .. show(Shops.evolutionItems(data.items, data.pokemon)))
  ok(not survey.general[34], "real data: the herb shop is a specialty shelf")
  ok(survey.general[5], "real data: the Cianwood pharmacy is a general shelf")

  local function stock(d, label, ids)
    for _, mart in ipairs(ids) do
      local names = {}
      for _, id in ipairs(d.gen2Marts.lists[mart + 1]) do
        names[#names + 1] = id .. " " .. tostring(d.items[id].price)
      end
      print(string.format("  %s mart %d: %s", label, mart, table.concat(names, ", ")))
    end
  end

  for _, case in ipairs({
      { "better", { shops = false, shops_better = true } },
      { "shuffle", { shops = true, shops_better = false } },
      { "both", { shops = true, shops_better = true } } }) do
    local d = load()
    local _, dRefs = snapshot(d)
    local dBargain = d.gen2Marts.bargain
    local ctx = setup(d, "123456", case[2])
    invariants(d, vanillaLists, "real " .. case[1])
    if case[1] == "better" then
      eq(show(d.gen2Marts.lists[1]), "POKE_BALL,GREAT_BALL,POTION,SUPER_POTION,ANTIDOTE,PARLYZ_HEAL,AWAKENING",
        "real better: Cherrygrove before the POKeDEX")
      ok(has(d.gen2Marts.lists[9], "FIRE_STONE") and has(d.gen2Marts.lists[28], "SUN_STONE"),
        "real better: stones on Goldenrod 4F and Celadon 5F")
      ok(not has(d.gen2Marts.lists[9], "MOON_STONE"), "real better: MOON STONE (price 0) is not sold")
      for i, list in ipairs(vanillaLists) do
        for _, id in ipairs(list) do ok(has(d.gen2Marts.lists[i], id), "real better keeps vanilla " .. i .. " " .. id) end
      end
    end
    print("seed 123456, " .. case[1] .. ":")
    stock(d, "Cherrygrove", { 0, 1 })
    stock(d, "Goldenrod", { 5, 6, 7, 8, 9, 10, 11, 12 })
    local again = load()
    setup(again, "123456", case[2])
    ok(same(snapshot(again), snapshot(d)), "real " .. case[1] .. ": deterministic")
    ok(d.gen2Marts.bargain == dBargain, "real " .. case[1] .. ": bargain untouched")
    ctx.setActive(false)
    local after = snapshot(d)
    for i = 1, #dRefs do
      ok(d.gen2Marts.lists[i] == dRefs[i] and after[i] == vanilla[i], "real " .. case[1] .. ": shelf " .. i .. " restored")
    end
  end
  print("real Crystal data checked: " .. cache)
end

print(string.format("shops_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
