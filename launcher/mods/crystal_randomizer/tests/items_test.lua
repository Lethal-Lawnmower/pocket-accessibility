-- luajit launcher/mods/crystal_randomizer/tests/items_test.lua   (from the repository root)
--
-- Runs on a small synthetic dataset shaped like Crystal's extracted tables.
-- With CRYSTAL_RANDOMIZER_CACHE set to an imported cache's data/generated
-- folder, it also runs against the real Crystal maps and items.
local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Items = dofile("launcher/mods/crystal_randomizer/modules/items.lua")

local failures, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg) ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local function syntheticData()
  local items = {
    POTION = { index = 18, pocket = "ITEM", canToss = true },
    SUPER_POTION = { index = 21, pocket = "ITEM", canToss = true },
    POKE_BALL = { index = 5, pocket = "BALL", canToss = true },
    RARE_CANDY = { index = 32, pocket = "ITEM", canToss = true },
    TM_DIG = { index = 219, pocket = "TM_HM", canToss = true },
    HM_SURF = { index = 245, pocket = "TM_HM", canToss = false },
    MACHINE_PART = { index = 128, pocket = "KEY_ITEM", canToss = false },
    BICYCLE = { index = 7, pocket = "KEY_ITEM", canToss = false },
    ETHER = { index = 63, pocket = "ITEM", canToss = true },
  }
  local function ball(index, item, quantity)
    return { index = index, sprite = "SPRITE_POKE_BALL", itemball = { item = item, quantity = quantity or 1 } }
  end
  local maps = {
    ROUTE_29 = { objects = { { index = 1, sprite = "SPRITE_YOUNGSTER" }, ball(2, 18), ball(3, 5, 3) },
      bgEvents = { { kind = 7, hiddenItem = { item = 32, event = 300 } } } },
    ROUTE_30 = { objects = { ball(1, 219), ball(2, 21), ball(3, 245) },
      bgEvents = { { kind = 1, script = 1 }, { kind = 7, hiddenItem = { item = 63, event = 301 } } } },
    CERULEAN_GYM = { objects = { ball(1, 7), ball(2, 999) },
      bgEvents = { { kind = 7, hiddenItem = { item = 128, event = 250 } },
        { kind = 7, hiddenItem = { item = 18, event = 251 } } } },
    DARK_CAVE = { objects = { ball(1, 63), ball(2, 32), ball(3, 18, 2) } },
  }
  return { items = items, gen2Maps = maps }
end

local function snapshot(maps)
  local out = {}
  for mapId, map in pairs(maps) do
    for i, o in ipairs(map.objects or {}) do
      if o.itemball then out[mapId .. "#o" .. i] = o.itemball.item .. "x" .. tostring(o.itemball.quantity) end
    end
    for i, e in ipairs(map.bgEvents or {}) do
      if e.hiddenItem then out[mapId .. "#h" .. i] = tostring(e.hiddenItem.item) end
    end
  end
  return out
end

local function same(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end

local function multiset(snap, kind)
  local out = {}
  for k, v in pairs(snap) do
    if k:find("#" .. kind, 1, true) then out[#out + 1] = v end
  end
  table.sort(out)
  return table.concat(out, ",")
end

local function setup(data, seed, options)
  local ctx = Fake.new({ seed = seed, options = options })
  Items.install({ game = { data = data } }, ctx)
  ctx.setActive(seed ~= nil, seed, options)
  return ctx
end

local function protectedSpots(data)
  -- every location holding a key item, an HM or an unknown index
  local out = {}
  local byIndex = {}
  for id, def in pairs(data.items) do
    if type(def) == "table" and def.index then byIndex[def.index] = id end
  end
  for mapId, map in pairs(data.gen2Maps) do
    for i, o in ipairs(map.objects or {}) do
      local def = o.itemball and data.items[byIndex[o.itemball.item]]
      if o.itemball and not Items.movable(def) then out[#out + 1] = { o.itemball, o.itemball.item } end
    end
    for i, e in ipairs(map.bgEvents or {}) do
      local def = e.hiddenItem and data.items[byIndex[e.hiddenItem.item]]
      if e.hiddenItem and not Items.movable(def) then out[#out + 1] = { e.hiddenItem, e.hiddenItem.item } end
    end
  end
  return out
end

-- ------------------------------------------------------------ questions
do
  -- Oak's box: two lines of at most 18 characters, \v scrolls, \f starts a box.
  local function fitsOak(text)
    for box in (text .. "\f"):gmatch("(.-)\f") do
      for line in (box:gsub("\v", "\n") .. "\n"):gmatch("(.-)\n") do
        if #line > 18 then return false, line end
      end
    end
    return true
  end
  local keys = {}
  for _, q in ipairs(Items.questions) do
    keys[#keys + 1] = q.key
    eq(q.recommended, true, "question " .. q.key .. " is on in RECOMMENDED")
    eq(q.everything, true, "question " .. q.key .. " is on in EVERYTHING")
    local fits, line = fitsOak(q.text)
    ok(fits, "question " .. q.key .. " fits Oak's box (" .. tostring(line) .. ")")
  end
  eq(table.concat(keys, ","), "items,items_hidden", "the items questions")
end

-- ------------------------------------------------------------ vanilla
do
  local data = syntheticData()
  local vanilla = snapshot(data.gen2Maps)
  setup(data, nil, {})
  ok(same(vanilla, snapshot(data.gen2Maps)), "vanilla save leaves every item where it is")
  setup(data, "seed", { items = false })
  ok(same(vanilla, snapshot(data.gen2Maps)), "answered no leaves every item where it is")
end

-- ------------------------------------------------------------ shuffle
do
  local data = syntheticData()
  local vanilla = snapshot(data.gen2Maps)
  local guarded = protectedSpots(data)
  local ctx = setup(data, "alpha", { items = true })
  local alpha = snapshot(data.gen2Maps)
  eq(multiset(alpha, "o"), multiset(vanilla, "o"), "balls hold the same items as before")
  for k, v in pairs(vanilla) do
    if k:find("#h", 1, true) then eq(alpha[k], v, "hidden items untouched without the second answer: " .. k) end
  end
  for _, g in ipairs(guarded) do eq(g[1].item, g[2], "key item / HM / unknown stays put") end

  -- determinism
  local data2 = syntheticData()
  setup(data2, "alpha", { items = true })
  ok(same(alpha, snapshot(data2.gen2Maps)), "same seed, same shuffle")

  -- some seed actually moves something
  local moved = false
  for n = 1, 10 do
    local d = syntheticData()
    setup(d, "s" .. n, { items = true })
    if not same(vanilla, snapshot(d.gen2Maps)) then moved = true end
  end
  ok(moved, "shuffling moves items")

  -- switching saves: vanilla restores, another seed rebuilds from vanilla
  ctx.setActive(false)
  ok(same(vanilla, snapshot(data.gen2Maps)), "vanilla save after a randomized one restores")
  ctx.setActive(true, "beta", { items = true })
  local d3 = syntheticData()
  setup(d3, "beta", { items = true })
  ok(same(snapshot(d3.gen2Maps), snapshot(data.gen2Maps)), "switching saves gives that save's shuffle, not a stack")
  ctx.setActive(true, "alpha", { items = true })
  ok(same(alpha, snapshot(data.gen2Maps)), "back to the first save gives its shuffle again")
  ctx.setActive(true, "alpha", { items = true })
  ok(same(alpha, snapshot(data.gen2Maps)), "the same save reported twice does not shuffle twice")
end

-- ------------------------------------------------------------ hidden items
do
  local data = syntheticData()
  local vanilla = snapshot(data.gen2Maps)
  local guarded = protectedSpots(data)
  local moved = false
  local ctx
  for n = 1, 10 do
    data = syntheticData()
    ctx = setup(data, "h" .. n, { items = true, items_hidden = true })
    local snap = snapshot(data.gen2Maps)
    eq(multiset(snap, "h"), multiset(vanilla, "h"), "hidden items hold the same items")
    eq(multiset(snap, "o"), multiset(vanilla, "o"), "balls hold the same items")
    for k, v in pairs(vanilla) do if k:find("#h", 1, true) and snap[k] ~= v then moved = true end end
    eq(data.gen2Maps.CERULEAN_GYM.bgEvents[1].hiddenItem.item, 128, "MACHINE PART stays in Cerulean Gym")
    eq(data.gen2Maps.ROUTE_30.objects[3].itemball.item, 245, "HM ball stays")
    eq(data.gen2Maps.CERULEAN_GYM.objects[1].itemball.item, 7, "key item ball stays")
  end
  ok(moved, "hidden items move")
  ctx.setActive(false)
  ok(same(vanilla, snapshot(data.gen2Maps)), "hidden items restored for a vanilla save")
end

-- ------------------------------------------------------------ real Crystal data
local cache = os.getenv("CRYSTAL_RANDOMIZER_CACHE")
if cache and cache ~= "" then
  local data = { items = dofile(cache .. "/items.lua"), gen2Maps = dofile(cache .. "/maps.lua") }
  local vanilla = snapshot(data.gen2Maps)
  local guarded = protectedSpots(data)
  local balls, hidden = Items.locations(data.gen2Maps, data.items, true)
  print(string.format("  real data: %d movable balls, %d movable hidden, %d protected spots",
    #balls, #hidden, #guarded))
  ok(#balls > 100 and #hidden > 50, "real data: locations found")
  local ctx = setup(data, "real", { items = true, items_hidden = true })
  local snap = snapshot(data.gen2Maps)
  eq(multiset(snap, "o"), multiset(vanilla, "o"), "real data: same ball items")
  eq(multiset(snap, "h"), multiset(vanilla, "h"), "real data: same hidden items")
  for _, g in ipairs(guarded) do eq(g[1].item, g[2], "real data: protected item stays") end
  local changed = 0
  for k, v in pairs(vanilla) do if snap[k] ~= v then changed = changed + 1 end end
  ok(changed > 100, "real data: many locations changed (" .. changed .. ")")
  ctx.setActive(false)
  ok(same(vanilla, snapshot(data.gen2Maps)), "real data: restored")
  print("real Crystal data checked: " .. cache)
end

print(string.format("items_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
