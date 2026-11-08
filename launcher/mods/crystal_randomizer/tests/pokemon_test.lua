-- Test for modules/pokemon.lua (types and level-up learnsets).
--   luajit launcher/mods/crystal_randomizer/tests/pokemon_test.lua
-- With CRYSTAL_DATA_DIR pointing at a folder holding an imported Crystal's
-- data/generated pokemon.lua and moves.lua (never committed), the same
-- property checks also run on the real game data.
local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Module = dofile("launcher/mods/crystal_randomizer/modules/pokemon.lua")

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

local function syntheticMoves()
  local list = {
    { "TACKLE", "NORMAL", 35, "EFFECT_NORMAL_HIT" },
    { "SCRATCH", "NORMAL", 40, "EFFECT_NORMAL_HIT" },
    { "HYPER_BEAM", "NORMAL", 150, "EFFECT_HYPER_BEAM" },
    { "GROWL", "NORMAL", 0, "EFFECT_ATTACK_DOWN" },
    { "SPLASH", "NORMAL", 0, "EFFECT_SPLASH" },
    { "EMBER", "FIRE", 40, "EFFECT_BURN_HIT" },
    { "FLAMETHROWER", "FIRE", 95, "EFFECT_BURN_HIT" },
    { "SUNNY_DAY", "FIRE", 0, "EFFECT_SUNNY_DAY" },
    { "WATER_GUN", "WATER", 40, "EFFECT_NORMAL_HIT" },
    { "RAIN_DANCE", "WATER", 0, "EFFECT_RAIN_DANCE" },
    { "GUST", "FLYING", 40, "EFFECT_GUST" },
    { "AGILITY", "PSYCHIC_TYPE", 0, "EFFECT_SPEED_UP_2" },
    { "CONFUSION", "PSYCHIC_TYPE", 50, "EFFECT_CONFUSE_HIT" },
    { "DREAM_EATER", "PSYCHIC_TYPE", 100, "EFFECT_DREAM_EATER" },
    { "COUNTER", "FIGHTING", 1, "EFFECT_COUNTER" },
    { "MIRROR_COAT", "PSYCHIC_TYPE", 1, "EFFECT_MIRROR_COAT" },
    { "SAFEGUARD", "NORMAL", 0, "EFFECT_SAFEGUARD" },
    { "DESTINY_BOND", "GHOST", 0, "EFFECT_DESTINY_BOND" },
    { "SELFDESTRUCT", "NORMAL", 200, "EFFECT_SELFDESTRUCT" },
    { "CUT", "NORMAL", 50, "EFFECT_NORMAL_HIT" },
    { "SURF", "WATER", 95, "EFFECT_NORMAL_HIT" },
    -- in the move table but learnable by nothing: must never be dealt out
    { "STRUGGLE", "NORMAL", 50, "EFFECT_RECOIL_HIT" },
  }
  local moves = { generation = 2, source = "synthetic" }
  for i, m in ipairs(list) do
    moves[m[1]] = { id = m[1], index = i, type = m[2], power = m[3], effect = m[4] }
  end
  return moves
end

local function rows(spec)
  local out = {}
  for i = 1, #spec, 2 do out[#out + 1] = { level = spec[i], move = spec[i + 1] } end
  return out
end

-- `order` lets a test build the same data with a different insertion order.
local function syntheticData(order)
  local defs = {
    CHAR1 = { types = { "FIRE", "FIRE" }, levelMoves = rows{ 1, "SCRATCH", 1, "GROWL", 7, "EMBER" },
      evolutions = { { method = "EVOLVE_LEVEL", level = 16, into = "CHAR2" } }, tmhm = { "CUT" } },
    CHAR2 = { types = { "FIRE", "FIRE" }, levelMoves = rows{ 1, "SCRATCH", 1, "GROWL", 7, "EMBER", 30, "FLAMETHROWER" },
      evolutions = { { method = "EVOLVE_LEVEL", level = 36, into = "CHAR3" } }, tmhm = { "CUT" } },
    CHAR3 = { types = { "FIRE", "FLYING" }, levelMoves = rows{ 1, "SCRATCH", 1, "GROWL", 7, "EMBER", 30, "FLAMETHROWER", 50, "HYPER_BEAM" },
      evolutions = {}, tmhm = { "CUT" } },
    EEV = { types = { "NORMAL", "NORMAL" }, levelMoves = rows{ 1, "TACKLE", 1, "GROWL" },
      evolutions = { { method = "EVOLVE_ITEM", item = "WATER_STONE", into = "EEVW" },
        { method = "EVOLVE_ITEM", item = "FIRE_STONE", into = "EEVF" } }, tmhm = { "SURF" } },
    EEVW = { types = { "WATER", "WATER" }, levelMoves = rows{ 1, "TACKLE", 1, "WATER_GUN", 40, "RAIN_DANCE" },
      evolutions = {}, tmhm = { "SURF" } },
    EEVF = { types = { "FIRE", "FIRE" }, levelMoves = rows{ 1, "TACKLE", 1, "EMBER", 40, "SUNNY_DAY" },
      evolutions = {}, tmhm = {} },
    WOBB = { types = { "PSYCHIC_TYPE", "PSYCHIC_TYPE" },
      levelMoves = rows{ 1, "COUNTER", 1, "MIRROR_COAT", 1, "SAFEGUARD", 1, "DESTINY_BOND", 1, "AGILITY" },
      evolutions = {}, tmhm = {}, eggMoves = { "DREAM_EATER" } },
    KARP = { types = { "WATER", "WATER" }, levelMoves = rows{ 1, "SPLASH", 15, "TACKLE", 30, "GUST" },
      evolutions = {}, tmhm = {}, tutorMoves = { "CONFUSION" } },
    BOMB = { types = { "NORMAL", "FLYING" }, levelMoves = rows{ 3, "SELFDESTRUCT", 9, "GROWL", 20, "SAFEGUARD", 25, "AGILITY", 31, "SPLASH" },
      evolutions = {}, tmhm = { "CUT" } },
  }
  local data = {
    moves = syntheticMoves(),
    pokemon = { tutorMoves = { "CONFUSION" }, tmhmMoves = { "CUT", "SURF" }, growthRates = {} },
    type_chart = { types = { NORMAL = {}, FIRE = {}, WATER = {}, FLYING = {}, PSYCHIC_TYPE = {},
      FIGHTING = {}, GHOST = {}, BIRD = {}, CURSE_TYPE = {} } },
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

local function isSpecies(def)
  return type(def) == "table" and type(def.types) == "table" and type(def.levelMoves) == "table"
end

local function setup(data, seed, options)
  local ctx = Fake.new({ seed = seed, options = options })
  if not seed then ctx.setActive(false) end
  local mod = { game = { data = data } }
  Module.install(mod, ctx)
  return ctx, mod
end

-- The four moves a mon of `level` arrives with (src/battle/gen2/Mon.lua:movesAtLevel).
local function movesAtLevel(levelMoves, level)
  local known = {}
  for _, row in ipairs(levelMoves) do
    if row.level <= level then
      local dup = false
      for _, m in ipairs(known) do if m == row.move then dup = true end end
      if not dup then
        known[#known + 1] = row.move
        if #known > 4 then table.remove(known, 1) end
      end
    end
  end
  return known
end

local function snapshotFields(data)
  local out = {}
  for species, def in pairs(data.pokemon) do
    if isSpecies(def) then
      out[species] = { types = deepCopy(def.types), levelMoves = deepCopy(def.levelMoves) }
    end
  end
  return out
end

-- Pools a correct build may draw from, derived independently of the module.
local function expectedPools(pristine)
  local types, learnable = {}, {}
  for _, def in pairs(pristine.pokemon) do
    if isSpecies(def) then
      types[def.types[1]] = true
      types[def.types[2] or def.types[1]] = true
      for _, r in ipairs(def.levelMoves) do learnable[r.move] = true end
      for _, list in ipairs({ def.tmhm or {}, def.tutorMoves or {}, def.eggMoves or {} }) do
        for _, m in ipairs(list) do learnable[m] = true end
      end
    end
  end
  return types, learnable
end

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

-- Every property a randomized build must hold.
local function checkRandomized(label, data, pristine, options)
  local types, learnable = expectedPools(pristine)
  local fam = familyOf(pristine)
  local familyMap = {}
  local changedTypes, changedMoves = 0, 0
  for species, def in pairs(data.pokemon) do
    if isSpecies(def) then
      local old = pristine.pokemon[species]
      -- TM/HM, tutor, egg moves and evolutions untouched
      check(deepEqual(def.tmhm, old.tmhm), "%s %s: tmhm changed", label, species)
      check(deepEqual(def.tutorMoves, old.tutorMoves), "%s %s: tutor moves changed", label, species)
      check(deepEqual(def.eggMoves, old.eggMoves), "%s %s: egg moves changed", label, species)
      check(deepEqual(def.evolutions, old.evolutions), "%s %s: evolutions changed", label, species)
      -- types
      local t1, t2 = def.types[1], def.types[2]
      local o1, o2 = old.types[1], old.types[2] or old.types[1]
      check(#def.types == 2, "%s %s: %d types", label, species, #def.types)
      check(types[t1] and types[t2], "%s %s: invalid type %s/%s", label, species, tostring(t1), tostring(t2))
      check((t1 == t2) == (o1 == o2), "%s %s: single/dual changed", label, species)
      if options.pokemon_types then
        if t1 ~= o1 or t2 ~= o2 then changedTypes = changedTypes + 1 end
        -- one old->new mapping per family
        local map = familyMap[fam[species]] or {}
        familyMap[fam[species]] = map
        for _, pair in ipairs({ { o1, t1 }, { o2, t2 } }) do
          if map[pair[1]] then
            check(map[pair[1]] == pair[2], "%s %s: family maps %s inconsistently", label, species, pair[1])
          end
          map[pair[1]] = pair[2]
        end
      else
        check(def.types == old.types or deepEqual(def.types, old.types), "%s %s: types changed while off", label, species)
      end
      -- learnsets
      check(#def.levelMoves == #old.levelMoves, "%s %s: learnset length changed", label, species)
      local lowest = math.huge
      for i, row in ipairs(def.levelMoves) do
        check(row.level == old.levelMoves[i].level, "%s %s: row %d level changed", label, species, i)
        check(type(data.moves[row.move]) == "table" and learnable[row.move],
          "%s %s: row %d invalid move %s", label, species, i, tostring(row.move))
        if row.move ~= old.levelMoves[i].move then changedMoves = changedMoves + 1 end
        if row.level < lowest then lowest = row.level end
      end
      if options.pokemon_moves and #def.levelMoves > 0 then
        local levels = {}
        for _, row in ipairs(def.levelMoves) do levels[row.level] = true end
        for level in pairs(levels) do
          local attack, starting = false, false
          for _, id in ipairs(movesAtLevel(def.levelMoves, level)) do
            local mv = data.moves[id]
            if Module.isDependableAttack(mv) then
              attack = true
              if mv.power <= 60 then starting = true end
            end
          end
          check(attack, "%s %s: no dependable attack at level %d", label, species, level)
          if level == lowest then
            check(starting, "%s %s: no starting attack (power <= 60) at lowest level %d", label, species, level)
          end
        end
      elseif not options.pokemon_moves then
        check(def.levelMoves == old.levelMoves or deepEqual(def.levelMoves, old.levelMoves),
          "%s %s: learnset changed while off", label, species)
      end
    end
  end
  if options.pokemon_types then check(changedTypes > 0, "%s: no species changed type", label) end
  if options.pokemon_moves then check(changedMoves > 0, "%s: no move changed", label) end
end

local function checkVanilla(label, data, pristine, originals)
  for species, def in pairs(data.pokemon) do
    if isSpecies(def) then
      check(def.types == originals[species].types, "%s %s: types table not the vanilla one", label, species)
      check(def.levelMoves == originals[species].levelMoves, "%s %s: levelMoves table not the vanilla one", label, species)
    end
  end
  check(deepEqual(data.pokemon, pristine.pokemon), "%s: data.pokemon differs from vanilla", label)
  check(deepEqual(data.moves, pristine.moves), "%s: data.moves changed", label)
end

local function originalTables(data)
  local out = {}
  for species, def in pairs(data.pokemon) do
    if isSpecies(def) then out[species] = { types = def.types, levelMoves = def.levelMoves } end
  end
  return out
end

local BOTH = { pokemon_types = true, pokemon_moves = true }

local function runSuite(label, makeData)
  -- 1. A vanilla save changes nothing.
  do
    local data = makeData()
    local pristine, originals = deepCopy(data), originalTables(data)
    local ctx = setup(data, nil)
    ctx.setActive(false)
    checkVanilla(label .. " inactive", data, pristine, originals)
    -- an active save with both answers "no" is vanilla too
    ctx.setActive(true, "seed-no", { pokemon_types = false, pokemon_moves = false })
    checkVanilla(label .. " answered no", data, pristine, originals)
  end

  -- 2. Randomized with both options, then each option alone.
  for _, options in ipairs({ BOTH, { pokemon_types = true }, { pokemon_moves = true } }) do
    local data = makeData()
    local pristine = deepCopy(data)
    local ctx = setup(data, "alpha", options)
    ctx.setActive(true, "alpha", options)
    checkRandomized(("%s types=%s moves=%s"):format(label, tostring(options.pokemon_types),
      tostring(options.pokemon_moves)), data, pristine, options)
  end

  -- 3. Determinism: same seed, same result; another seed, another result;
  --    insertion order of the data does not matter.
  do
    local a, b = makeData(), makeData("reverse")
    local ca, cb = setup(a, "alpha", BOTH), setup(b, "alpha", BOTH)
    ca.setActive(true, "alpha", BOTH)
    cb.setActive(true, "alpha", BOTH)
    check(deepEqual(snapshotFields(a), snapshotFields(b)), "%s: same seed gave different results", label)
    cb.setActive(true, "beta", BOTH)
    check(not deepEqual(snapshotFields(a), snapshotFields(b)), "%s: different seeds gave the same result", label)
  end

  -- 4. Switching saves in one process: A, vanilla, B, A again.
  do
    local data = makeData()
    local pristine, originals = deepCopy(data), originalTables(data)
    local ctx = setup(data, "alpha", BOTH)
    ctx.setActive(true, "alpha", BOTH)
    local first = snapshotFields(data)
    ctx.setActive(false)
    checkVanilla(label .. " after leaving a randomized save", data, pristine, originals)
    ctx.setActive(true, "beta", BOTH)
    local beta = snapshotFields(data)
    local fresh = makeData()
    local fctx = setup(fresh, "beta", BOTH)
    fctx.setActive(true, "beta", BOTH)
    check(deepEqual(beta, snapshotFields(fresh)), "%s: save B after save A differs from a fresh B", label)
    ctx.setActive(true, "alpha", BOTH)
    check(deepEqual(first, snapshotFields(data)), "%s: returning to save A gave a different A", label)
    ctx.setActive(true, "alpha", { pokemon_types = true })
    for species, def in pairs(data.pokemon) do
      if isSpecies(def) then
        check(def.levelMoves == originals[species].levelMoves, "%s %s: moves not restored when only types on", label, species)
      end
    end
    ctx.setActive(false)
    checkVanilla(label .. " final restore", data, pristine, originals)
  end
end

runSuite("synthetic", syntheticData)

-- Specific synthetic expectations.
do
  local data = syntheticData()
  local ctx = setup(data, "alpha", BOTH)
  ctx.setActive(true, "alpha", BOTH)
  local P = data.pokemon
  check(P.CHAR1.types[1] == P.CHAR2.types[1] and P.CHAR2.types[1] == P.CHAR3.types[1],
    "synthetic: the CHAR line does not share its first type")
  check(P.CHAR3.types[1] ~= P.CHAR3.types[2], "synthetic: CHAR3 is no longer dual-typed")
  -- Eevee's branches keep their relationship: both gained a type Eevee lacks.
  check(P.EEVW.types[1] ~= P.EEV.types[1] and P.EEVF.types[1] ~= P.EEV.types[1]
    and P.EEVW.types[1] ~= P.EEVF.types[1], "synthetic: the EEV branches lost their relationship")
  for species, def in pairs(P) do
    if isSpecies(def) then
      for _, t in ipairs(def.types) do
        check(t ~= "BIRD" and t ~= "CURSE_TYPE", "synthetic %s: placeholder type %s", species, t)
      end
      for _, row in ipairs(def.levelMoves) do
        check(row.move ~= "STRUGGLE", "synthetic %s: STRUGGLE dealt out", species)
      end
    end
  end
  -- Several seeds, to exercise the never-stuck repair on more draws.
  for i = 1, 40 do
    local d = syntheticData()
    local pristine = deepCopy(d)
    local c = setup(d, "s" .. i, BOTH)
    c.setActive(true, "s" .. i, BOTH)
    checkRandomized("synthetic seed s" .. i, d, pristine, BOTH)
  end
end

-- No game data: logs and changes nothing, never raises.
do
  local ctx = Fake.new({ seed = "x", options = BOTH })
  Module.install({}, ctx)
  local ok = pcall(ctx.setActive, true, "x", BOTH)
  check(ok, "no-data onSave raised")
end

-- Contract shape.
check(Module.id == "pokemon", "module id")
check(#Module.questions == 2 and Module.questions[1].key == "pokemon_types"
  and Module.questions[2].key == "pokemon_moves", "questions")
for _, q in ipairs(Module.questions) do
  check(q.kind == "yesno", "question %s kind", q.key)
  for line in (q.text .. "\n"):gmatch("([^\n]*)\n") do
    -- é is two bytes in UTF-8 and one tile on screen
    local width = #line:gsub("\195\169", "e")
    check(width <= 18, "question %s line too wide: %q", q.key, line)
  end
end

local real = realData()
if real then
  runSuite("crystal", function() return realData() end)
  -- A report of one species, for the record.
  local ctx = setup(real, "report", BOTH)
  ctx.setActive(true, "report", BOTH)
  for _, species in ipairs({ "CHIKORITA", "BAYLEEF", "MEGANIUM", "MAGIKARP", "WOBBUFFET", "EEVEE", "VAPOREON" }) do
    local def = real.pokemon[species]
    if def then
      local parts = {}
      for _, row in ipairs(def.levelMoves) do parts[#parts + 1] = row.level .. ":" .. row.move end
      print(("crystal seed 'report' %s %s/%s %s"):format(species, def.types[1], def.types[2], table.concat(parts, " ")))
    end
  end
else
  print("note: CRYSTAL_DATA_DIR not set; real Crystal data not checked")
end

print(("%d checks, %d failures"):format(checks, failures))
if failures > 0 then os.exit(1) end
print("PASS pokemon_test")
