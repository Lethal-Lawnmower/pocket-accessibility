-- Test for modules/stats.lua (base stats and damaging moves' data).
--   luajit launcher/mods/crystal_randomizer/tests/stats_test.lua
-- With CRYSTAL_DATA_DIR pointing at a folder holding an imported Crystal's
-- data/generated pokemon.lua and moves.lua (never committed), the same
-- property checks also run on the real game data.
local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Module = dofile("launcher/mods/crystal_randomizer/modules/stats.lua")

local failures, checks = 0, 0
local function check(ok, fmt, ...)
  checks = checks + 1
  if not ok then
    failures = failures + 1
    print("FAIL " .. (select("#", ...) > 0 and fmt:format(...) or fmt))
  end
  return ok
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

local KEYS = { "hp", "attack", "defense", "speed", "specialAttack", "specialDefense" }
local MOVE_FIELDS = { power = true, accuracy = true, accuracyRaw = true, type = true }

-- ------------------------------------------------------- synthetic data

local function stats(hp, atk, def, spe, spa, spd)
  return { hp = hp, attack = atk, defense = def, speed = spe, specialAttack = spa, specialDefense = spd }
end

local function syntheticMoves()
  -- id, type, power, accuracy percent, raw byte, effect
  local list = {
    { "TACKLE", "NORMAL", 35, 95, 242, "EFFECT_NORMAL_HIT" },
    { "SCRATCH", "NORMAL", 40, 100, 255, "EFFECT_NORMAL_HIT" },
    { "HYPER_BEAM", "NORMAL", 150, 90, 229, "EFFECT_HYPER_BEAM" },
    { "GROWL", "NORMAL", 0, 100, 255, "EFFECT_ATTACK_DOWN" },
    { "EMBER", "FIRE", 40, 100, 255, "EFFECT_BURN_HIT" },
    { "FIRE_BLAST", "FIRE", 120, 85, 216, "EFFECT_BURN_HIT" },
    { "SUNNY_DAY", "FIRE", 0, 100, 255, "EFFECT_SUNNY_DAY" },
    { "WATER_GUN", "WATER", 40, 100, 255, "EFFECT_NORMAL_HIT" },
    { "SURF", "WATER", 95, 100, 255, "EFFECT_NORMAL_HIT" },
    { "CUT", "NORMAL", 50, 95, 242, "EFFECT_NORMAL_HIT" },
    { "DYNAMICPUNCH", "FIGHTING", 100, 50, 127, "EFFECT_CONFUSE_HIT" },
    { "FURY_SWIPES", "NORMAL", 18, 80, 204, "EFFECT_MULTI_HIT" },
    { "SWIFT", "NORMAL", 60, 100, 255, "EFFECT_ALWAYS_HIT" },
    { "SEISMIC_TOSS", "FIGHTING", 1, 100, 255, "EFFECT_LEVEL_DAMAGE" },
    { "DRAGON_RAGE", "DRAGON", 40, 100, 255, "EFFECT_STATIC_DAMAGE" },
    { "HIDDEN_POWER", "NORMAL", 1, 100, 255, "EFFECT_HIDDEN_POWER" },
    { "EXPLOSION", "NORMAL", 250, 100, 255, "EFFECT_SELFDESTRUCT" },
    { "HORN_DRILL", "NORMAL", 1, 30, 76, "EFFECT_OHKO" },
    { "CURSE", "CURSE_TYPE", 0, 100, 255, "EFFECT_CURSE" },
    { "STRUGGLE", "NORMAL", 50, 100, 255, "EFFECT_RECOIL_HIT" },
    { "LICK", "GHOST", 20, 100, 255, "EFFECT_PARALYZE_HIT" },
  }
  local moves = { generation = 2, source = "synthetic" }
  for i, m in ipairs(list) do
    moves[m[1]] = { id = m[1], name = m[1], index = i, type = m[2], power = m[3], accuracy = m[4],
      accuracyRaw = m[5], effect = m[6], pp = 10 + i, effectChance = 10, description = "row " .. i }
  end
  -- a move record written without the raw byte: restore must leave it absent
  moves.PECK = { id = "PECK", name = "PECK", index = 99, type = "FLYING", power = 35, accuracy = 100,
    effect = "EFFECT_NORMAL_HIT", pp = 35 }
  return moves
end

local function syntheticData(order)
  local defs = {
    CHIK1 = { baseStats = stats(45, 49, 65, 45, 49, 65),
      evolutions = { { method = "EVOLVE_LEVEL", level = 16, into = "CHIK2" } } },
    CHIK2 = { baseStats = stats(60, 62, 80, 60, 63, 80),
      evolutions = { { method = "EVOLVE_LEVEL", level = 32, into = "CHIK3" } } },
    CHIK3 = { baseStats = stats(80, 82, 100, 80, 83, 100), evolutions = {} },
    EEV = { baseStats = stats(55, 55, 50, 55, 45, 65),
      evolutions = { { method = "EVOLVE_ITEM", item = "WATER_STONE", into = "EEVW" },
        { method = "EVOLVE_ITEM", item = "FIRE_STONE", into = "EEVF" } } },
    EEVW = { baseStats = stats(130, 65, 60, 65, 110, 95), evolutions = {} },
    EEVF = { baseStats = stats(65, 130, 60, 65, 95, 110), evolutions = {} },
    BLISS = { baseStats = stats(250, 5, 5, 50, 35, 105), evolutions = {} },
    LUG = { baseStats = stats(106, 90, 130, 110, 90, 154), evolutions = {} },
    SUNK = { baseStats = stats(30, 30, 30, 30, 30, 30), evolutions = {} },
  }
  local data = {
    moves = syntheticMoves(),
    pokemon = { tutorMoves = { "SURF" }, tmhmMoves = { "CUT", "SURF" }, growthRates = {} },
  }
  local names = {}
  for name in pairs(defs) do names[#names + 1] = name end
  table.sort(names)
  if order == "reverse" then
    for i = 1, math.floor(#names / 2) do names[i], names[#names + 1 - i] = names[#names + 1 - i], names[i] end
  end
  for _, name in ipairs(names) do
    local def = defs[name]
    def.id, def.name = name, name
    def.types = { "NORMAL", "NORMAL" }
    def.levelMoves = { { level = 1, move = "TACKLE" } }
    data.pokemon[name] = def
  end
  return data
end

local function realData()
  local dir = os.getenv("CRYSTAL_DATA_DIR")
  if not dir or dir == "" then return nil end
  local okP, pokemon = pcall(dofile, dir .. "/pokemon.lua")
  local okM, moves = pcall(dofile, dir .. "/moves.lua")
  if not (okP and okM) then
    check(false, "CRYSTAL_DATA_DIR set but data did not load: %s", tostring(okP and moves or pokemon))
    return nil
  end
  return { pokemon = pokemon, moves = moves }
end

-- --------------------------------------------------------------- harness

local function isSpecies(def) return type(def) == "table" and type(def.baseStats) == "table" end

local function setup(data, seed, options)
  local ctx = Fake.new({ seed = seed, options = options })
  if not seed then ctx.setActive(false) end
  Module.install({ game = { data = data } }, ctx)
  return ctx
end

local function total(s)
  local t = 0
  for _, k in ipairs(KEYS) do t = t + s[k] end
  return t
end

-- What the module owns, as values, for comparing two builds.
local function owned(data)
  local out = { species = {}, moves = {} }
  for species, def in pairs(data.pokemon) do
    if isSpecies(def) then out.species[species] = deepCopy(def.baseStats) end
  end
  for id, move in pairs(data.moves) do
    if type(move) == "table" then
      out.moves[id] = { move.power, move.accuracy, move.accuracyRaw, move.type }
    end
  end
  return out
end

-- References a restore must put back, and the record tables that must stay.
local function originalTables(data)
  local out = { species = {}, moves = {} }
  for species, def in pairs(data.pokemon) do
    if isSpecies(def) then
      out.species[species] = { baseStats = def.baseStats, types = def.types,
        levelMoves = def.levelMoves, evolutions = def.evolutions }
    end
  end
  for id, move in pairs(data.moves) do out.moves[id] = move end
  return out
end

-- Families from the pristine evolutions, derived independently of the module.
local function familyOf(pristine)
  local parent = {}
  local function find(x) while parent[x] ~= x do x = parent[x] end return x end
  for s, def in pairs(pristine.pokemon) do if isSpecies(def) then parent[s] = s end end
  for s in pairs(parent) do
    for _, e in ipairs(pristine.pokemon[s].evolutions or {}) do
      if e.into and parent[e.into] then
        local a, b = find(s), find(e.into)
        if a ~= b then parent[b] = a end
      end
    end
  end
  local fam = {}
  for s in pairs(parent) do fam[s] = find(s) end
  return fam
end

-- All 720 orderings of six positions.
local PERMS = {}
do
  local function build(prefix, used)
    if #prefix == 6 then PERMS[#PERMS + 1] = { unpack(prefix) } return end
    for i = 1, 6 do
      if not used[i] then
        used[i] = true; prefix[#prefix + 1] = i
        build(prefix, used)
        prefix[#prefix] = nil; used[i] = false
      end
    end
  end
  build({}, {})
end

local function changeable(id, move)
  return Module.isChangeable(id, move)
end

local function checkUntouchedSpeciesFields(label, data, pristine, originals)
  for species, def in pairs(data.pokemon) do
    if isSpecies(def) then
      local o, p = originals.species[species], pristine.pokemon[species]
      check(def.types == o.types and deepEqual(def.types, p.types), "%s %s: types touched", label, species)
      check(def.levelMoves == o.levelMoves and deepEqual(def.levelMoves, p.levelMoves),
        "%s %s: levelMoves touched", label, species)
      check(def.evolutions == o.evolutions and deepEqual(def.evolutions, p.evolutions),
        "%s %s: evolutions touched", label, species)
      for key, value in pairs(p) do
        if key ~= "baseStats" then
          check(deepEqual(def[key], value), "%s %s: field %s touched", label, species, key)
        end
      end
    end
  end
  for key, value in pairs(pristine.pokemon) do
    if not isSpecies(value) then
      check(deepEqual(data.pokemon[key], value), "%s: top-level %s touched", label, key)
    end
  end
end

-- Every property a randomized build must hold.
local function checkRandomized(label, data, pristine, originals, options)
  checkUntouchedSpeciesFields(label, data, pristine, originals)
  local fam = familyOf(pristine)

  -- base stats
  local members = {}
  local changedSpecies = 0
  for species, def in pairs(data.pokemon) do
    if isSpecies(def) then
      local old, new = pristine.pokemon[species].baseStats, def.baseStats
      if not deepEqual(old, new) then changedSpecies = changedSpecies + 1 end
      if not options.stats_base then
        check(new == originals.species[species].baseStats, "%s %s: base stats changed while off", label, species)
      else
        check(total(new) == total(old), "%s %s: total %d, vanilla %d", label, species, total(new), total(old))
        local count = 0
        for _ in pairs(new) do count = count + 1 end
        check(count == 6, "%s %s: %d stat fields", label, species, count)
        for _, k in ipairs(KEYS) do
          check(math.floor(new[k]) == new[k] and new[k] >= 1 and new[k] <= 255,
            "%s %s: %s = %s", label, species, k, tostring(new[k]))
        end
        if options.stats_base_mode == "reroll" then
          for _, k in ipairs(KEYS) do
            check(new[k] >= math.min(Module.STAT_FLOOR, math.floor(total(old) / 6)),
              "%s %s: %s below the floor", label, species, k)
          end
        else
          local a, b = {}, {}
          for i, k in ipairs(KEYS) do a[i], b[i] = old[k], new[k] end
          table.sort(a) table.sort(b)
          check(deepEqual(a, b), "%s %s: reorder changed the values", label, species)
        end
        local f = fam[species]
        members[f] = members[f] or {}
        table.insert(members[f], species)
      end
    end
  end
  if options.stats_base then
    check(changedSpecies > 0, "%s: no species' base stats changed", label)
    for f, list in pairs(members) do
      if options.stats_base_mode == "reroll" then
        -- one set of weights per family: every member's shares agree to rounding
        local floorOf = function(s) return math.min(Module.STAT_FLOOR, math.floor(total(s) / 6)) end
        local function shares(s)
          local rest = total(s) - 6 * floorOf(s)
          local out = {}
          for i, k in ipairs(KEYS) do out[i] = (s[k] - floorOf(s)) / rest end
          return out, rest
        end
        local first = data.pokemon[list[1]].baseStats
        local sa, ra = shares(first)
        for j = 2, #list do
          local other = data.pokemon[list[j]].baseStats
          local sb, rb = shares(other)
          local capped = false
          for _, k in ipairs(KEYS) do if first[k] == 255 or other[k] == 255 then capped = true end end
          if not capped then
            for i = 1, 6 do
              check(math.abs(sa[i] - sb[i]) <= 1 / ra + 1 / rb + 1e-9,
                "%s family %s: %s and %s have different proportions", label, f, list[1], list[j])
            end
          end
        end
      else
        -- one order per family: some single permutation explains every member
        local found = false
        for _, perm in ipairs(PERMS) do
          local fits = true
          for _, species in ipairs(list) do
            local old, new = pristine.pokemon[species].baseStats, data.pokemon[species].baseStats
            for i, k in ipairs(KEYS) do
              if new[k] ~= old[KEYS[perm[i]]] then fits = false break end
            end
            if not fits then break end
          end
          if fits then found = true break end
        end
        check(found, "%s family %s: members do not share one order", label, f)
      end
    end
  end

  -- moves
  local types = {}
  for id, move in pairs(pristine.moves) do
    if changeable(id, move) then types[move.type] = true end
  end
  local changedPower, changedType, changedAccuracy = 0, 0, 0
  for id, move in pairs(data.moves) do
    if type(move) == "table" then
      local old = pristine.moves[id]
      check(move == originals.moves[id], "%s %s: move record replaced", label, id)
      for key, value in pairs(old) do
        if not MOVE_FIELDS[key] then
          check(deepEqual(move[key], value), "%s %s: move field %s touched", label, id, key)
        end
      end
      for key in pairs(move) do check(old[key] ~= nil, "%s %s: move field %s added", label, id, key) end
      if not (options.stats_moves and changeable(id, old)) then
        for key in pairs(MOVE_FIELDS) do
          check(move[key] == old[key], "%s %s: %s changed (%s)", label, id, key,
            options.stats_moves and "kept move" or "option off")
        end
      else
        if move.power ~= old.power then changedPower = changedPower + 1 end
        if move.type ~= old.type then changedType = changedType + 1 end
        if move.accuracy ~= old.accuracy then changedAccuracy = changedAccuracy + 1 end
        local lo = math.max(Module.POWER_MIN, math.floor(old.power * 0.5) - 3)
        local hi = math.min(Module.POWER_MAX, math.ceil(old.power * 1.5) + 3)
        check(move.power >= lo and move.power <= hi and math.floor(move.power) == move.power,
          "%s %s: power %s from %d", label, id, tostring(move.power), old.power)
        check(types[move.type], "%s %s: type %s not a damaging type", label, id, tostring(move.type))
        if old.effect == "EFFECT_ALWAYS_HIT" then
          check(move.accuracy == old.accuracy and move.accuracyRaw == old.accuracyRaw,
            "%s %s: never-miss accuracy changed", label, id)
        else
          check(move.accuracy >= math.min(Module.ACCURACY_FLOOR, old.accuracy) and move.accuracy <= 100
            and move.accuracy >= old.accuracy - 15 and move.accuracy <= old.accuracy + 10,
            "%s %s: accuracy %s from %d", label, id, tostring(move.accuracy), old.accuracy)
        end
        if old.accuracyRaw == nil then
          check(move.accuracyRaw == nil, "%s %s: raw accuracy added", label, id)
        elseif move.accuracy == old.accuracy then
          check(move.accuracyRaw == old.accuracyRaw, "%s %s: raw byte changed with the same accuracy", label, id)
        else
          check(Module.percentOf(move.accuracyRaw) == move.accuracy and move.accuracyRaw <= 255,
            "%s %s: raw %s does not read as %d%%", label, id, tostring(move.accuracyRaw), move.accuracy)
        end
      end
    else
      check(move == pristine.moves[id], "%s: moves.%s touched", label, id)
    end
  end
  check(deepEqual(data.moves.STRUGGLE, pristine.moves.STRUGGLE), "%s: STRUGGLE changed", label)
  if options.stats_moves then
    check(changedPower > 0 and changedType > 0 and changedAccuracy > 0,
      "%s: moves barely changed (power %d, type %d, accuracy %d)", label, changedPower, changedType, changedAccuracy)
  end
end

local function checkVanilla(label, data, pristine, originals)
  checkUntouchedSpeciesFields(label, data, pristine, originals)
  for species, def in pairs(data.pokemon) do
    if isSpecies(def) then
      check(def.baseStats == originals.species[species].baseStats,
        "%s %s: baseStats table not the vanilla one", label, species)
    end
  end
  for id, move in pairs(data.moves) do
    check(move == originals.moves[id], "%s %s: move record replaced", label, id)
  end
  check(deepEqual(data.pokemon, pristine.pokemon), "%s: data.pokemon differs from vanilla", label)
  check(deepEqual(data.moves, pristine.moves), "%s: data.moves differs from vanilla", label)
end

local ALL = { stats_base = true, stats_base_mode = "reorder", stats_moves = true }
local ALL_REROLL = { stats_base = true, stats_base_mode = "reroll", stats_moves = true }
local OPTION_SETS = {
  ALL, ALL_REROLL,
  { stats_base = true, stats_base_mode = "reorder" },
  { stats_base = true, stats_base_mode = "reroll" },
  { stats_moves = true },
}

local function runSuite(label, makeData)
  -- 1. A vanilla save, and an active save answering no, change nothing.
  do
    local data = makeData()
    local pristine, originals = deepCopy(data), originalTables(data)
    local ctx = setup(data, nil)
    checkVanilla(label .. " inactive", data, pristine, originals)
    ctx.setActive(true, "seed-no", { stats_base = false, stats_moves = false })
    checkVanilla(label .. " answered no", data, pristine, originals)
  end

  -- 2. Each option set.
  for _, options in ipairs(OPTION_SETS) do
    local data = makeData()
    local pristine, originals = deepCopy(data), originalTables(data)
    local ctx = setup(data, "alpha", options)
    ctx.setActive(true, "alpha", options)
    checkRandomized(("%s base=%s mode=%s moves=%s"):format(label, tostring(options.stats_base),
      tostring(options.stats_base_mode), tostring(options.stats_moves)), data, pristine, originals, options)
  end

  -- 3. Determinism: same seed, same result, whatever the data's insertion
  --    order; another seed, another result.
  for _, options in ipairs({ ALL, ALL_REROLL }) do
    local a, b = makeData(), makeData("reverse")
    local ca, cb = setup(a, "alpha", options), setup(b, "alpha", options)
    ca.setActive(true, "alpha", options)
    cb.setActive(true, "alpha", options)
    check(deepEqual(owned(a), owned(b)), "%s %s: same seed gave different results", label, options.stats_base_mode)
    cb.setActive(true, "beta", options)
    check(not deepEqual(owned(a).species, owned(b).species), "%s %s: other seed, same base stats", label,
      options.stats_base_mode)
    check(not deepEqual(owned(a).moves, owned(b).moves), "%s %s: other seed, same moves", label,
      options.stats_base_mode)
  end
  do -- reorder and reroll are different builds
    local a, b = makeData(), makeData()
    setup(a, "alpha", ALL).setActive(true, "alpha", ALL)
    setup(b, "alpha", ALL_REROLL).setActive(true, "alpha", ALL_REROLL)
    check(not deepEqual(owned(a).species, owned(b).species), "%s: reorder and reroll gave the same stats", label)
  end

  -- 4. Switching saves in one process: A, vanilla, B, A again, partial options.
  do
    local data = makeData()
    local pristine, originals = deepCopy(data), originalTables(data)
    local ctx = setup(data, "alpha", ALL)
    ctx.setActive(true, "alpha", ALL)
    local first = owned(data)
    ctx.setActive(false)
    checkVanilla(label .. " after leaving a randomized save", data, pristine, originals)
    ctx.setActive(true, "beta", ALL_REROLL)
    local beta = owned(data)
    local fresh = makeData()
    setup(fresh, "beta", ALL_REROLL).setActive(true, "beta", ALL_REROLL)
    check(deepEqual(beta, owned(fresh)), "%s: save B after save A differs from a fresh B", label)
    ctx.setActive(true, "alpha", ALL)
    check(deepEqual(first, owned(data)), "%s: returning to save A gave a different A", label)
    ctx.setActive(true, "alpha", { stats_base = true })
    for id, move in pairs(data.moves) do
      check(deepEqual(move, pristine.moves[id]), "%s %s: move not restored when only stats on", label, id)
    end
    ctx.setActive(true, "alpha", { stats_moves = true })
    for species, def in pairs(data.pokemon) do
      if isSpecies(def) then
        check(def.baseStats == originals.species[species].baseStats,
          "%s %s: stats not restored when only moves on", label, species)
      end
    end
    ctx.setActive(false)
    checkVanilla(label .. " final restore", data, pristine, originals)
  end

  -- 5. The family snapshot is vanilla even if a later module (evolutions)
  --    rewrites evolution rows between switches.
  do
    local data = makeData()
    local ctx = setup(data, "alpha", ALL)
    ctx.setActive(true, "alpha", ALL)
    local first = owned(data)
    local saved = {}
    for species, def in pairs(data.pokemon) do
      if isSpecies(def) then saved[species] = def.evolutions; def.evolutions = {} end
    end
    ctx.setActive(true, "alpha", ALL)
    check(deepEqual(first, owned(data)), "%s: changed evolutions changed the families", label)
    for species, evo in pairs(saved) do data.pokemon[species].evolutions = evo end
  end
end

runSuite("synthetic", syntheticData)

-- Specific synthetic expectations.
do
  local data = syntheticData()
  local ctx = setup(data, "alpha", ALL)
  ctx.setActive(true, "alpha", ALL)
  local M = data.moves
  for _, id in ipairs({ "SEISMIC_TOSS", "DRAGON_RAGE", "HIDDEN_POWER", "EXPLOSION", "HORN_DRILL",
      "STRUGGLE", "GROWL", "SUNNY_DAY", "CURSE" }) do
    check(not Module.isChangeable(id, M[id]), "synthetic: %s counted as changeable", id)
  end
  for _, id in ipairs({ "TACKLE", "SURF", "CUT", "FURY_SWIPES", "SWIFT", "HYPER_BEAM", "LICK" }) do
    check(Module.isChangeable(id, M[id]), "synthetic: %s not changeable", id)
  end
  -- many seeds, to exercise the ranges and the reroll spread
  for i = 1, 60 do
    for _, options in ipairs({ ALL, ALL_REROLL }) do
      local d = syntheticData()
      local pristine, originals = deepCopy(d), originalTables(d)
      local c = setup(d, "s" .. i, options)
      c.setActive(true, "s" .. i, options)
      checkRandomized(("synthetic seed s%d %s"):format(i, options.stats_base_mode), d, pristine, originals, options)
    end
  end
  -- the spread itself
  local spread = Module.spread(680, { 5, 0.25, 0.25, 0.25, 0.25, 0.25 })
  check(spread[1] == 255 and total({ hp = spread[1], attack = spread[2], defense = spread[3],
    speed = spread[4], specialAttack = spread[5], specialDefense = spread[6] }) == 680,
    "spread: a capped stat did not pass its share on (%s)", table.concat(spread, ","))
  local small = Module.spread(60, { 1, 1, 1, 1, 1, 1 })
  check(table.concat(small, ",") == "10,10,10,10,10,10", "spread: a tiny total gave %s", table.concat(small, ","))
  -- ranges at their edges
  local rng = dofile("launcher/mods/crystal_randomizer/rng.lua").stream("edges")
  for _ = 1, 2000 do
    local p = Module.newPower(rng, 150)
    check(p >= 75 and p <= 150 and p % 5 == 0, "newPower(150) gave %d", p)
    local q = Module.newPower(rng, 10)
    check(q >= 10 and q <= 15, "newPower(10) gave %d", q)
    local a = Module.newAccuracy(rng, 50)
    check(a >= 50 and a <= 60, "newAccuracy(50) gave %d", a)
    local b = Module.newAccuracy(rng, 100)
    check(b >= 85 and b <= 100, "newAccuracy(100) gave %d", b)
  end
  for percent = 0, 100 do
    check(Module.percentOf(Module.rawOf(percent)) == percent, "raw round trip fails at %d%%", percent)
  end
end

-- No game data: logs and changes nothing, never raises.
do
  local ctx = Fake.new({ seed = "x", options = ALL })
  Module.install({}, ctx)
  check(pcall(ctx.setActive, true, "x", ALL), "no-data onSave raised")
end

-- Contract shape.
check(Module.id == "stats", "module id")
local byKey = {}
for _, q in ipairs(Module.questions) do byKey[q.key] = q end
check(#Module.questions == 3 and byKey.stats_base and byKey.stats_base_mode and byKey.stats_moves, "questions")
check(byKey.stats_base_mode.onlyIf == "stats_base", "mode question depends on stats_base")
for _, q in ipairs(Module.questions) do
  check(q.recommended ~= nil and q.everything ~= nil, "question %s lacks a setup value", q.key)
  if q.kind == "choice" then
    local values = {}
    for _, option in ipairs(q.options) do
      values[option.value] = true
      check(#option.label <= 12 and option.label == option.label:upper(), "label %s", option.label)
    end
    check(values[q.recommended] and values[q.everything], "question %s setup value not an option", q.key)
  else
    check(q.kind == "yesno" and type(q.recommended) == "boolean" and type(q.everything) == "boolean",
      "question %s values", q.key)
  end
  for line in (q.text .. "\n"):gmatch("([^\n\v\f]*)[\n\v\f]") do
    -- é is two bytes in UTF-8 and one tile on screen
    local width = #line:gsub("\195\169", "e")
    check(width <= 18, "question %s line too wide: %q", q.key, line)
  end
end
check(byKey.stats_base.recommended == false and byKey.stats_base.everything == true, "stats_base setups")
check(byKey.stats_base_mode.recommended == "reorder" and byKey.stats_base_mode.everything == "reroll",
  "stats_base_mode setups")
check(byKey.stats_moves.recommended == false and byKey.stats_moves.everything == true, "stats_moves setups")

local real = realData()
if real then
  runSuite("crystal", function() return realData() end)
  local pristine = realData()
  local kept, changeableCount = {}, 0
  for id, move in pairs(pristine.moves) do
    if type(move) == "table" and (move.power or 0) > 0 then
      if Module.isChangeable(id, move) then changeableCount = changeableCount + 1 else kept[#kept + 1] = id end
    end
  end
  table.sort(kept)
  print(("crystal: %d damaging moves change, kept: %s"):format(changeableCount, table.concat(kept, " ")))
  for _, options in ipairs({ ALL, ALL_REROLL }) do
    local data = realData()
    setup(data, "report", options).setActive(true, "report", options)
    for _, species in ipairs({ "CHIKORITA", "BAYLEEF", "MEGANIUM", "CHANSEY", "BLISSEY", "LUGIA" }) do
      local old, new = pristine.pokemon[species].baseStats, data.pokemon[species].baseStats
      local a, b = {}, {}
      for i, k in ipairs(KEYS) do a[i], b[i] = old[k], new[k] end
      print(("crystal seed 'report' %s %s: %s -> %s (total %d)"):format(options.stats_base_mode, species,
        table.concat(a, "/"), table.concat(b, "/"), total(new)))
    end
    if options == ALL then
      for _, id in ipairs({ "TACKLE", "EMBER", "SURF", "CUT", "HYPER_BEAM", "THUNDER", "SWIFT", "STRUGGLE" }) do
        local o, n = pristine.moves[id], data.moves[id]
        print(("crystal seed 'report' %s: %s %d %d%% -> %s %d %d%%"):format(id, o.type, o.power, o.accuracy,
          n.type, n.power, n.accuracy))
      end
    end
  end
else
  print("note: CRYSTAL_DATA_DIR not set; real Crystal data not checked")
end

print(("%d checks, %d failures"):format(checks, failures))
if failures > 0 then os.exit(1) end
print("PASS stats_test")
