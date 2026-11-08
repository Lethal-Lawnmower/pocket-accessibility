-- Test for modules/evolutions.lua (trade evolutions without trading, and
-- random evolutions).
--   luajit launcher/mods/crystal_randomizer/tests/evolutions_test.lua
-- With CRYSTAL_DATA_DIR pointing at a folder holding an imported Crystal's
-- data/generated pokemon.lua and items.lua (never committed), the same
-- property checks also run on the real game data, plus the exact trade table.
local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Module = dofile("launcher/mods/crystal_randomizer/modules/evolutions.lua")

local failures, checks = 0, 0
local function check(ok, fmt, ...)
  checks = checks + 1
  if not ok then
    failures = failures + 1
    print("FAIL " .. (select("#", ...) > 0 and fmt:format(...) or fmt))
  end
end

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = deepCopy(v) end
  return out
end
local function deepEqual(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- ------------------------------------------------------- synthetic data

local function stats(total)
  local each = math.floor(total / 6)
  return { hp = each, attack = each, defense = each, speed = each, specialAttack = each,
    specialDefense = total - 5 * each }
end

-- `order` lets a test build the same data with a different insertion order.
local function syntheticData(order)
  local specs = {
    -- id, types, bst, evolutions, legendary?
    { "BULB", { "GRASS", "POISON" }, 318, { { method = "EVOLVE_LEVEL", level = 16, into = "IVY" } } },
    { "IVY", { "GRASS", "POISON" }, 405, { { method = "EVOLVE_LEVEL", level = 32, into = "VENU" } } },
    { "VENU", { "GRASS", "POISON" }, 525, {} },
    { "ABRA", { "PSYCHIC_TYPE", "PSYCHIC_TYPE" }, 310, { { method = "EVOLVE_LEVEL", level = 16, into = "KAD" } } },
    { "KAD", { "PSYCHIC_TYPE", "PSYCHIC_TYPE" }, 400, { { method = "EVOLVE_TRADE", into = "ALA" } } },
    { "ALA", { "PSYCHIC_TYPE", "PSYCHIC_TYPE" }, 500, {} },
    { "ONX", { "ROCK", "GROUND" }, 385, { { method = "EVOLVE_TRADE", item = "METAL_COAT", into = "STX" } } },
    { "STX", { "STEEL", "GROUND" }, 510, {} },
    { "POLI", { "WATER", "WATER" }, 300, { { method = "EVOLVE_LEVEL", level = 25, into = "WHIRL" } } },
    { "WHIRL", { "WATER", "WATER" }, 385, { { method = "EVOLVE_ITEM", item = "WATER_STONE", into = "WRATH" },
      { method = "EVOLVE_TRADE", item = "KINGS_ROCK", into = "TOED" } } },
    { "WRATH", { "WATER", "FIGHTING" }, 500, {} },
    { "TOED", { "WATER", "WATER" }, 500, {} },
    { "EEV", { "NORMAL", "NORMAL" }, 325, { { method = "EVOLVE_ITEM", item = "WATER_STONE", into = "VAP" },
      { method = "EVOLVE_ITEM", item = "FIRE_STONE", into = "FLA" },
      { method = "EVOLVE_HAPPINESS", time = "MORNDAY", into = "ESP" },
      { method = "EVOLVE_HAPPINESS", time = "NITE", into = "UMB" } } },
    { "VAP", { "WATER", "WATER" }, 525, {} },
    { "FLA", { "FIRE", "FIRE" }, 525, {} },
    { "ESP", { "PSYCHIC_TYPE", "PSYCHIC_TYPE" }, 525, {} },
    { "UMB", { "DARK", "DARK" }, 525, {} },
    { "TYRO", { "FIGHTING", "FIGHTING" }, 210, {
      { method = "EVOLVE_STAT", level = 20, comparison = "ATK_GT_DEF", into = "LEE" },
      { method = "EVOLVE_STAT", level = 20, comparison = "ATK_LT_DEF", into = "CHAN" },
      { method = "EVOLVE_STAT", level = 20, comparison = "ATK_EQ_DEF", into = "TOP" } } },
    { "LEE", { "FIGHTING", "FIGHTING" }, 455, {} },
    { "CHAN", { "FIGHTING", "FIGHTING" }, 455, {} },
    { "TOP", { "FIGHTING", "FIGHTING" }, 455, {} },
    { "RATT", { "NORMAL", "NORMAL" }, 253, { { method = "EVOLVE_LEVEL", level = 20, into = "RATI" } } },
    { "RATI", { "NORMAL", "NORMAL" }, 413, {} },
    { "TAUR", { "NORMAL", "NORMAL" }, 490, {} },
    { "MILT", { "NORMAL", "NORMAL" }, 490, {} },
    { "CHARM", { "FIRE", "FIRE" }, 309, { { method = "EVOLVE_LEVEL", level = 16, into = "CHARL" } } },
    { "CHARL", { "FIRE", "FIRE" }, 405, { { method = "EVOLVE_LEVEL", level = 36, into = "CHARZ" } } },
    { "CHARZ", { "FIRE", "FLYING" }, 534, {} },
    { "MAGMAR", { "FIRE", "FIRE" }, 495, {} },
    { "STEELY", { "STEEL", "STEEL" }, 400, {} },
    { "HORSE", { "WATER", "WATER" }, 295, { { method = "EVOLVE_LEVEL", level = 32, into = "SEADRA" } } },
    { "SEADRA", { "WATER", "WATER" }, 440, { { method = "EVOLVE_TRADE", item = "DRAGON_SCALE", into = "KING" } } },
    { "KING", { "WATER", "DRAGON" }, 540, {} },
    { "MEW2", { "PSYCHIC_TYPE", "PSYCHIC_TYPE" }, 680, {}, true },
    { "LUGI", { "PSYCHIC_TYPE", "FLYING" }, 680, {}, true },
    { "UNOW", { "PSYCHIC_TYPE", "PSYCHIC_TYPE" }, 336, {}, true },
  }
  local data = {
    pokemon = { tutorMoves = { "X" }, tmhmMoves = { "Y" }, growthRates = {} },
    items = {
      METAL_COAT = { id = "METAL_COAT", fieldMenu = "ITEMMENU_NOUSE", battleMenu = "ITEMMENU_NOUSE" },
      KINGS_ROCK = { id = "KINGS_ROCK", fieldMenu = "ITEMMENU_NOUSE", battleMenu = "ITEMMENU_NOUSE" },
      DRAGON_SCALE = { id = "DRAGON_SCALE", fieldMenu = "ITEMMENU_NOUSE", battleMenu = "ITEMMENU_NOUSE" },
      WATER_STONE = { id = "WATER_STONE", fieldMenu = "ITEMMENU_PARTY", battleMenu = "ITEMMENU_NOUSE" },
      FIRE_STONE = { id = "FIRE_STONE", fieldMenu = "ITEMMENU_PARTY", battleMenu = "ITEMMENU_NOUSE" },
    },
  }
  local list = {}
  for i, s in ipairs(specs) do list[i] = s end
  if order == "reverse" then
    for i = 1, math.floor(#list / 2) do list[i], list[#list + 1 - i] = list[#list + 1 - i], list[i] end
  end
  local indexOf = {}
  for i, s in ipairs(specs) do indexOf[s[1]] = i end
  for _, s in ipairs(list) do
    data.pokemon[s[1]] = {
      id = s[1], name = s[1], index = indexOf[s[1]], types = s[2], baseStats = stats(s[3]),
      evolutions = s[4], genderRatio = s[5] and 255 or 31, eggGroupsRaw = s[5] and 255 or 17,
      levelMoves = { { level = 1, move = "TACKLE" } },
    }
  end
  return data
end

local function realData()
  local dir = os.getenv("CRYSTAL_DATA_DIR")
  if not dir or dir == "" then return nil end
  local okP, pokemon = pcall(dofile, dir .. "/pokemon.lua")
  local okI, items = pcall(dofile, dir .. "/items.lua")
  if not (okP and okI) then
    check(false, "CRYSTAL_DATA_DIR set but data did not load: %s", tostring(okP and items or pokemon))
    return nil
  end
  return { pokemon = pokemon, items = items }
end

-- --------------------------------------------------------------- harness

local function isSpecies(def)
  return type(def) == "table" and type(def.index) == "number" and type(def.baseStats) == "table"
end

local function bstOf(def)
  local s, t = def.baseStats, 0
  for _, k in ipairs({ "hp", "attack", "defense", "speed", "specialAttack", "specialDefense" }) do
    t = t + s[k]
  end
  return t
end

local function setup(data, seed, options)
  local ctx = Fake.new({ seed = seed, options = options })
  local mod = { game = { data = data } }
  Module.install(mod, ctx)
  return ctx, mod
end

local function evolutionsOf(data)
  local out = {}
  for id, def in pairs(data.pokemon) do
    if isSpecies(def) then out[id] = deepCopy(def.evolutions) end
  end
  return out
end

local function originalTables(data)
  local out = {}
  for id, def in pairs(data.pokemon) do
    if isSpecies(def) then out[id] = def.evolutions end
  end
  return out
end

local function legendary(def) return def.genderRatio == 255 and def.eggGroupsRaw == 255 end

-- Vanilla heights, derived independently.
local function vanillaHeights(pristine)
  local memo = {}
  local function h(id, depth)
    if memo[id] then return memo[id] end
    if depth > 10 then return 0 end
    local best = 0
    for _, e in ipairs(pristine.pokemon[id].evolutions or {}) do
      if pristine.pokemon[e.into] then best = math.max(best, 1 + h(e.into, depth + 1)) end
    end
    memo[id] = best
    return best
  end
  local out = {}
  for id, def in pairs(pristine.pokemon) do if isSpecies(def) then out[id] = h(id, 0) end end
  return out
end

local function checkVanilla(label, data, pristine, originals)
  for id, def in pairs(data.pokemon) do
    if isSpecies(def) then
      check(def.evolutions == originals[id], "%s %s: evolutions table not the vanilla one", label, id)
    end
  end
  check(deepEqual(data.pokemon, pristine.pokemon), "%s: data.pokemon differs from vanilla", label)
  check(deepEqual(data.items, pristine.items), "%s: data.items differs from vanilla", label)
  check(deepEqual(data.gen2ItemEffects, pristine.gen2ItemEffects),
    "%s: data.gen2ItemEffects differs from vanilla", label)
  if pristine.gen2ItemEffects == nil then
    check(data.gen2ItemEffects == nil, "%s: gen2ItemEffects left behind", label)
  end
end

-- The longest chain (in species) starting anywhere; nil if there is a cycle.
local function longestChain(data)
  local memo, onPath = {}, {}
  local cycle = false
  local function walk(id)
    if memo[id] then return memo[id] end
    if onPath[id] then cycle = true return 0 end
    onPath[id] = true
    local best = 1
    for _, e in ipairs(data.pokemon[id].evolutions or {}) do
      if data.pokemon[e.into] then best = math.max(best, 1 + walk(e.into)) end
    end
    onPath[id] = nil
    memo[id] = best
    return best
  end
  local longest = 0
  for id, def in pairs(data.pokemon) do
    if isSpecies(def) then longest = math.max(longest, walk(id)) end
  end
  if cycle then return nil end
  return longest
end

-- The row a trade row must become.
local function expectedConversion(row, items)
  if row.method ~= "EVOLVE_TRADE" then return row end
  if row.item and items[row.item] then return { method = "EVOLVE_ITEM", item = row.item, into = row.into } end
  return { method = "EVOLVE_LEVEL", level = 37, into = row.into }
end

-- Every property a build with `options` must hold.
local function checkBuild(label, data, pristine, options)
  local convert, shuffle = options.evolutions_trade == true, options.evolutions == true
  local heights = vanillaHeights(pristine)
  local maxVanilla = longestChain(pristine)
  local trades, changed = 0, 0
  for id, def in pairs(data.pokemon) do
    if isSpecies(def) then
      local old = pristine.pokemon[id].evolutions or {}
      local new = def.evolutions or {}
      check(#new == #old, "%s %s: %d rows, vanilla %d", label, id, #new, #old)
      local seen = {}
      for i, row in ipairs(new) do
        local want = old[i] and (convert and expectedConversion(old[i], data.items) or old[i])
        if want then
          -- method and condition kept (or converted), only `into` may change
          local a, b = deepCopy(row), deepCopy(want)
          a.into, b.into = nil, nil
          check(deepEqual(a, b), "%s %s row %d: method or condition changed", label, id, i)
          if old[i].method == "EVOLVE_TRADE" then trades = trades + 1 end
          if not shuffle then
            check(row.into == want.into, "%s %s row %d: target changed while off", label, id, i)
          else
            local target = data.pokemon[row.into]
            check(isSpecies(target), "%s %s row %d: invalid target %s", label, id, i, tostring(row.into))
            if isSpecies(target) then
              check(not legendary(target), "%s %s row %d: evolves into legendary %s", label, id, i, row.into)
              check(row.into ~= id, "%s %s row %d: evolves into itself", label, id, i)
              check(heights[row.into] == heights[old[i].into],
                "%s %s row %d: height %d, vanilla target height %d", label, id, i,
                heights[row.into], heights[old[i].into])
              check(not seen[row.into], "%s %s: two branches into %s", label, id, row.into)
              seen[row.into] = true
              if options.evolutions_types then
                local shares = false
                for _, x in ipairs(def.types) do
                  for _, y in ipairs(target.types) do if x == y then shares = true end end
                end
                -- required whenever a valid candidate sharing a type is left
                -- after this species' earlier branches took theirs
                local function sharesWith(cdef)
                  for _, x in ipairs(def.types) do
                    for _, y in ipairs(cdef.types) do if x == y then return true end end
                  end
                  return false
                end
                local available = 0
                for cid, cdef in pairs(data.pokemon) do
                  if isSpecies(cdef) and not legendary(cdef) and cid ~= id
                      and heights[cid] == heights[old[i].into] and sharesWith(cdef) then
                    local takenEarlier = false
                    for j = 1, i - 1 do if new[j].into == cid then takenEarlier = true end end
                    if not takenEarlier then available = available + 1 end
                  end
                end
                check(shares or available == 0, "%s %s row %d: %s shares no type", label, id, i, row.into)
              end
              if row.into ~= old[i].into then changed = changed + 1 end
            end
          end
        end
      end
      if convert then
        for _, row in ipairs(new) do
          check(row.method ~= "EVOLVE_TRADE", "%s %s: a trade row is left", label, id)
        end
      end
    end
  end
  local longest = longestChain(data)
  check(longest ~= nil, "%s: an evolution cycle", label)
  check(longest and longest <= 3 and longest <= maxVanilla, "%s: chain of %s species", label, tostring(longest))
  if convert then
    check(trades > 0, "%s: no trade rows seen", label)
    for itemId, def in pairs(pristine.items) do
      local used = false
      for _, pdef in pairs(data.pokemon) do
        if isSpecies(pdef) then
          for _, row in ipairs(pdef.evolutions or {}) do
            if row.method == "EVOLVE_ITEM" and row.item == itemId then used = true end
          end
        end
      end
      if used and type(def) == "table" and def.fieldMenu == "ITEMMENU_NOUSE" then
        check(data.items[itemId].fieldMenu == "ITEMMENU_PARTY", "%s: %s not usable", label, itemId)
        local rec = data.gen2ItemEffects and data.gen2ItemEffects[itemId]
        check(type(rec) == "table" and rec.action == "stone" and type(rec.use) == "function",
          "%s: %s has no stone record", label, itemId)
      elseif not used and type(def) == "table" then
        check(data.items[itemId].fieldMenu == def.fieldMenu, "%s: unused %s changed", label, itemId)
      end
    end
  else
    check(deepEqual(data.items, pristine.items), "%s: items changed without the trade option", label)
  end
  if shuffle then check(changed > 0, "%s: no target changed", label) end
end

local TRADE = { evolutions_trade = true }
local SHUFFLE = { evolutions = true }
local SHUFFLE_TYPED = { evolutions = true, evolutions_types = true }
local ALL = { evolutions_trade = true, evolutions = true, evolutions_types = true }

local function runSuite(label, makeData, seeds)
  -- 1. A vanilla save, and an active save with every answer "no", change nothing.
  do
    local data = makeData()
    local pristine, originals = deepCopy(data), originalTables(data)
    local ctx = setup(data, nil)
    ctx.setActive(false)
    checkVanilla(label .. " inactive", data, pristine, originals)
    ctx.setActive(true, "no", { evolutions_trade = false, evolutions = false, evolutions_types = true })
    checkVanilla(label .. " answered no", data, pristine, originals)
  end

  -- 2. Each option alone and together.
  for _, options in ipairs({ TRADE, SHUFFLE, SHUFFLE_TYPED, ALL }) do
    for i = 1, seeds do
      local data = makeData()
      local pristine = deepCopy(data)
      local seed = "s" .. i
      local ctx = setup(data, seed, options)
      ctx.setActive(true, seed, options)
      checkBuild(("%s seed %s trade=%s shuffle=%s types=%s"):format(label, seed,
        tostring(options.evolutions_trade), tostring(options.evolutions),
        tostring(options.evolutions_types)), data, pristine, options)
    end
  end

  -- 3. Determinism: same seed same result, whatever the insertion order;
  --    another seed, another result.
  do
    local a, b = makeData(), makeData("reverse")
    local ca, cb = setup(a, "alpha", ALL), setup(b, "alpha", ALL)
    ca.setActive(true, "alpha", ALL)
    cb.setActive(true, "alpha", ALL)
    check(deepEqual(evolutionsOf(a), evolutionsOf(b)), "%s: same seed gave different results", label)
    cb.setActive(true, "beta", ALL)
    check(not deepEqual(evolutionsOf(a), evolutionsOf(b)), "%s: different seeds gave the same result", label)
  end

  -- 4. Switching saves in one process: A, vanilla, B, A again, trade only,
  --    then vanilla; and the same with an item-effects table already there.
  for _, preexisting in ipairs({ false, true }) do
    local data = makeData()
    if preexisting then data.gen2ItemEffects = { SOME_MOD_ITEM = { action = "heal" } } end
    local tag = label .. (preexisting and " (existing item effects)" or "")
    local pristine, originals = deepCopy(data), originalTables(data)
    local effectsTable = data.gen2ItemEffects
    local ctx = setup(data, "alpha", ALL)
    ctx.setActive(true, "alpha", ALL)
    local first = evolutionsOf(data)
    ctx.setActive(false)
    checkVanilla(tag .. " after leaving a randomized save", data, pristine, originals)
    ctx.setActive(true, "beta", ALL)
    local beta = evolutionsOf(data)
    local fresh = makeData()
    local fctx = setup(fresh, "beta", ALL)
    fctx.setActive(true, "beta", ALL)
    check(deepEqual(beta, evolutionsOf(fresh)), "%s: save B after save A differs from a fresh B", tag)
    ctx.setActive(true, "alpha", ALL)
    check(deepEqual(first, evolutionsOf(data)), "%s: returning to save A gave a different A", tag)
    ctx.setActive(true, "alpha", TRADE)
    checkBuild(tag .. " trade after shuffle", data, pristine, TRADE)
    ctx.setActive(true, "alpha", SHUFFLE)
    checkBuild(tag .. " shuffle after trade", data, pristine, SHUFFLE)
    ctx.setActive(false)
    checkVanilla(tag .. " final restore", data, pristine, originals)
    if preexisting then
      check(data.gen2ItemEffects == effectsTable, "%s: item effects table replaced", tag)
    end
  end
end

runSuite("synthetic", syntheticData, 40)

-- Specific synthetic expectations.
do
  local data = syntheticData()
  local ctx = setup(data, "alpha", TRADE)
  ctx.setActive(true, "alpha", TRADE)
  local P = data.pokemon
  check(deepEqual(P.KAD.evolutions, { { method = "EVOLVE_LEVEL", level = 37, into = "ALA" } }),
    "synthetic: KAD not level 37")
  check(deepEqual(P.ONX.evolutions, { { method = "EVOLVE_ITEM", item = "METAL_COAT", into = "STX" } }),
    "synthetic: ONX not METAL_COAT use")
  check(P.WHIRL.evolutions[1].item == "WATER_STONE" and P.WHIRL.evolutions[2].method == "EVOLVE_ITEM"
    and P.WHIRL.evolutions[2].item == "KINGS_ROCK", "synthetic: WHIRL rows wrong")
  -- the stand-in stone record (no engine here) evolves the right mon only
  local rec = data.gen2ItemEffects.METAL_COAT
  local r1 = rec.use({ item = "METAL_COAT", mon = { species = "ONX" }, data = data })
  check(r1.used and r1.evolution and r1.evolution.into == "STX", "synthetic: METAL_COAT on ONX did not evolve")
  local r2 = rec.use({ item = "METAL_COAT", mon = { species = "KAD" }, data = data })
  check(not r2.used, "synthetic: METAL_COAT worked on KAD")
  local r3 = data.gen2ItemEffects.KINGS_ROCK.use({ item = "KINGS_ROCK", mon = { species = "WHIRL" }, data = data })
  check(r3.used and r3.evolution.into == "TOED", "synthetic: KINGS_ROCK on WHIRL did not give TOED")
  local r4 = rec.use({ item = "METAL_COAT", mon = { species = "ONX", item = "EVERSTONE" }, data = data })
  check(not r4.used, "synthetic: METAL_COAT worked through an Everstone")
  check(data.items.WATER_STONE.fieldMenu == "ITEMMENU_PARTY" and data.gen2ItemEffects.WATER_STONE == nil,
    "synthetic: a stone's own fields were touched")
end

-- No game data: logs and changes nothing, never raises.
do
  local ctx = Fake.new({ seed = "x", options = ALL })
  Module.install({}, ctx)
  local ok = pcall(ctx.setActive, true, "x", ALL)
  check(ok, "no-data onSave raised")
end

-- Real data, when an import is available.
local real = realData()
if real then
  local function makeReal()
    local d = realData()
    return d
  end
  runSuite("real", makeReal, 8)
  -- The trade table on the cart's data.
  local data = makeReal()
  local ctx = setup(data, "alpha", TRADE)
  ctx.setActive(true, "alpha", TRADE)
  local want = {
    KADABRA = { "ALAKAZAM", "EVOLVE_LEVEL", 37 }, MACHOKE = { "MACHAMP", "EVOLVE_LEVEL", 37 },
    GRAVELER = { "GOLEM", "EVOLVE_LEVEL", 37 }, HAUNTER = { "GENGAR", "EVOLVE_LEVEL", 37 },
    ONIX = { "STEELIX", "EVOLVE_ITEM", "METAL_COAT" }, SCYTHER = { "SCIZOR", "EVOLVE_ITEM", "METAL_COAT" },
    POLIWHIRL = { "POLITOED", "EVOLVE_ITEM", "KINGS_ROCK" }, SLOWPOKE = { "SLOWKING", "EVOLVE_ITEM", "KINGS_ROCK" },
    SEADRA = { "KINGDRA", "EVOLVE_ITEM", "DRAGON_SCALE" }, PORYGON = { "PORYGON2", "EVOLVE_ITEM", "UP_GRADE" },
  }
  local lines = {}
  for species, w in pairs(want) do
    local found = false
    for _, row in ipairs(data.pokemon[species].evolutions) do
      if row.into == w[1] then
        found = row.method == w[2] and (row.level == w[3] or row.item == w[3])
      end
    end
    check(found, "real: %s -> %s is not %s %s", species, w[1], w[2], tostring(w[3]))
  end
  for _, row in ipairs(data.pokemon.SLOWPOKE.evolutions) do lines[#lines + 1] = row.method .. ":" .. row.into end
  check(#data.pokemon.SLOWPOKE.evolutions == 2, "real: SLOWPOKE lost a row")
  for _, item in ipairs({ "METAL_COAT", "KINGS_ROCK", "DRAGON_SCALE", "UP_GRADE" }) do
    check(data.items[item].fieldMenu == "ITEMMENU_PARTY", "real: %s not usable", item)
  end
  -- The randomized cart: report a sample, to read.
  local d2 = makeReal()
  local c2 = setup(d2, "alpha", ALL)
  c2.setActive(true, "alpha", ALL)
  local sample = {}
  for _, id in ipairs({ "CHIKORITA", "BAYLEEF", "CYNDAQUIL", "EEVEE", "KADABRA", "ONIX", "TYROGUE", "PICHU" }) do
    local rows = {}
    for _, row in ipairs(d2.pokemon[id].evolutions) do
      rows[#rows + 1] = row.method:gsub("EVOLVE_", "") .. (row.level and (" " .. row.level) or "")
        .. (row.item and (" " .. row.item) or "") .. " -> " .. row.into
    end
    sample[#sample + 1] = id .. ": " .. table.concat(rows, "; ")
  end
  print("real seed alpha, all options:\n  " .. table.concat(sample, "\n  "))
end

-- Contract shape: id, every question with both setup values, Oak's box.
check(Module.id == "evolutions", "module id")
local keys = {}
for _, q in ipairs(Module.questions) do
  keys[q.key] = true
  check(q.recommended ~= nil and q.everything ~= nil, "question %s lacks recommended/everything", q.key)
  check(q.onlyIf == nil or keys[q.onlyIf], "question %s: onlyIf %s not earlier", q.key, tostring(q.onlyIf))
  local lines = 0
  for line in (q.text .. "\n"):gmatch("([^\n]*)\n") do
    lines = lines + 1
    local _, chars = line:gsub("[^\128-\191]", "")
    check(chars <= 18, "question %s: line %q has %d characters", q.key, line, chars)
    check(not line:find("[\v\f]"), "question %s: scroll or page break in a two-line text", q.key)
  end
  check(lines <= 2, "question %s: %d lines", q.key, lines)
end

print(("%d checks, %d failures%s"):format(checks, failures, real and " (real data included)" or ""))
os.exit(failures == 0 and 0 or 1)
