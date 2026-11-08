-- Test for modules/trainers.lua.  Run from the repository root:
--   luajit launcher/mods/crystal_randomizer/tests/trainers_test.lua
--
-- Uses a small synthetic dataset shaped like the extracted Crystal data
-- (data.pokemon, data.moves, data.type_chart, data.gen2Trainers.classes,
-- data.gen2Maps, data.gen2Scripts), so it needs no ROM, and the engine's own
-- Trainers.party / Mon.new to build the parties, which is the path the game
-- takes.  CRYSTAL_DATA_DIR=<an identity's crystal/data/generated folder>
-- additionally runs the checks on real extracted data (every trainer in the
-- game) and prints what each gym became for one seed.

package.path = "./?.lua;./?/init.lua;" .. package.path

local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Trainers = require("src.world.gen2.Trainers")
local Mon = require("src.battle.gen2.Mon")

local MODULE = "launcher/mods/crystal_randomizer/modules/trainers.lua"
local Module = dofile(MODULE)

local failures, checks = 0, 0
local function check(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print("FAIL " .. (select("#", ...) > 0 and fmt:format(...) or fmt))
  end
end

local function merge(a, b)
  local out = {}
  for k, v in pairs(a or {}) do out[k] = v end
  for k, v in pairs(b or {}) do out[k] = v end
  return out
end

---------------------------------------------------------------------------
-- Synthetic data
---------------------------------------------------------------------------

local MOVE_IDS = { "TACKLE", "GROWL", "EMBER", "WATER_GUN", "VINE_WHIP", "LICK",
  "BITE", "GUST", "PECK", "SLAM", "PSYCHIC_M", "HYPER_BEAM", "MUD_SLAP", "SPLASH" }

local TYPE_IDS = { "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST",
  "STEEL", "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC_TYPE", "ICE", "DRAGON", "DARK" }

-- attacker > defender rows, super effective (20), enough for these checks
local SUPER = {
  { "FIRE", "GRASS" }, { "FIRE", "BUG" }, { "FIRE", "STEEL" }, { "FIRE", "ICE" },
  { "WATER", "FIRE" }, { "WATER", "ROCK" }, { "WATER", "GROUND" },
  { "GRASS", "WATER" }, { "GRASS", "ROCK" }, { "GRASS", "GROUND" },
  { "ELECTRIC", "WATER" }, { "ELECTRIC", "FLYING" },
  { "FLYING", "GRASS" }, { "FLYING", "BUG" }, { "FLYING", "FIGHTING" },
  { "ROCK", "FIRE" }, { "ROCK", "FLYING" }, { "ROCK", "BUG" }, { "ROCK", "ICE" },
  { "GROUND", "FIRE" }, { "GROUND", "ELECTRIC" }, { "GROUND", "ROCK" }, { "GROUND", "POISON" },
  { "BUG", "GRASS" }, { "BUG", "PSYCHIC_TYPE" }, { "POISON", "GRASS" },
  { "ICE", "DRAGON" }, { "ICE", "FLYING" }, { "DRAGON", "DRAGON" }, { "GHOST", "GHOST" },
}
local RESIST = { { "GRASS", "FIRE" }, { "FIRE", "WATER" }, { "WATER", "GRASS" }, { "ELECTRIC", "GROUND" } }

local function syntheticData()
  local moves = {}
  for i, id in ipairs(MOVE_IDS) do moves[id] = { id = id, pp = 10 + i, index = i } end
  local pokemon = { growthRates = { GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1 } } }
  local nextIndex = 0
  local function sp(id, bst, types, evos, firstLevel)
    nextIndex = nextIndex + 1
    local per = bst / 6
    local mv = MOVE_IDS[(nextIndex % 10) + 3]
    local levelMoves
    if firstLevel then
      levelMoves = { { level = firstLevel, move = "SPLASH" } }
    else
      levelMoves = {
        { level = 1, move = "TACKLE" }, { level = 1, move = "GROWL" },
        { level = 8, move = mv }, { level = 15, move = "BITE" },
        { level = 25, move = "SLAM" }, { level = 40, move = "HYPER_BEAM" },
      }
    end
    local evolutions = {}
    for _, into in ipairs(evos or {}) do
      evolutions[#evolutions + 1] = { method = "EVOLVE_LEVEL", level = 16, into = into }
    end
    pokemon[id] = {
      id = id, name = id, index = nextIndex, growthRate = "GROWTH_MEDIUM_FAST",
      genderRatio = 31, types = { types[1], types[2] or types[1] },
      baseStats = { hp = per, attack = per, defense = per, speed = per,
        specialAttack = per, specialDefense = per },
      levelMoves = levelMoves, evolutions = evolutions,
    }
  end
  local G, F, W, N, FL = { "GRASS" }, { "FIRE" }, { "WATER" }, { "NORMAL" }, { "NORMAL", "FLYING" }
  sp("CHIKORITA", 318, G, { "BAYLEEF" }); sp("BAYLEEF", 405, G, { "MEGANIUM" }); sp("MEGANIUM", 525, G)
  sp("CYNDAQUIL", 309, F, { "QUILAVA" }); sp("QUILAVA", 405, F, { "TYPHLOSION" }); sp("TYPHLOSION", 534, F)
  sp("TOTODILE", 314, W, { "CROCONAW" }); sp("CROCONAW", 405, W, { "FERALIGATR" }); sp("FERALIGATR", 530, W)
  local GP = { "GHOST", "POISON" }
  sp("GASTLY", 310, GP, { "HAUNTER" }); sp("HAUNTER", 405, GP, { "GENGAR" }); sp("GENGAR", 500, GP)
  local PF = { "POISON", "FLYING" }
  sp("ZUBAT", 245, PF, { "GOLBAT" }); sp("GOLBAT", 455, PF, { "CROBAT" }); sp("CROBAT", 535, PF)
  sp("PIDGEY", 251, FL, { "PIDGEOTTO" }); sp("PIDGEOTTO", 349, FL, { "PIDGEOT" }); sp("PIDGEOT", 469, FL)
  local E = { "ELECTRIC" }
  sp("MAREEP", 280, E, { "FLAAFFY" }); sp("FLAAFFY", 365, E, { "AMPHAROS" }); sp("AMPHAROS", 510, E)
  sp("RATTATA", 253, N, { "RATICATE" }); sp("RATICATE", 413, N)
  sp("SENTRET", 215, N, { "FURRET" }); sp("FURRET", 415, N)
  sp("HOOTHOOT", 262, FL, { "NOCTOWL" }); sp("NOCTOWL", 442, FL)
  sp("SPEAROW", 262, FL, { "FEAROW" }); sp("FEAROW", 442, FL)
  sp("EEVEE", 325, N, { "VAPOREON", "JOLTEON", "FLAREON" })
  sp("VAPOREON", 525, W); sp("JOLTEON", 525, E); sp("FLAREON", 525, F)
  sp("TAUROS", 490, N); sp("DITTO", 288, N); sp("DUNSPARCE", 415, N)
  sp("GIRAFARIG", 455, { "NORMAL", "PSYCHIC_TYPE" })
  sp("SNORLAX", 540, N); sp("MEWTWO", 680, { "PSYCHIC_TYPE" })
  sp("SUNKERN", 180, G, { "SUNFLORA" }); sp("SUNFLORA", 425, G)
  sp("CATERPIE", 195, { "BUG" }, { "METAPOD" }); sp("METAPOD", 205, { "BUG" }, { "BUTTERFREE" })
  sp("BUTTERFREE", 385, { "BUG", "FLYING" })
  sp("SKARMORY", 465, { "STEEL", "FLYING" })
  sp("DRATINI", 300, { "DRAGON" }, { "DRAGONAIR" }); sp("DRAGONAIR", 420, { "DRAGON" }, { "DRAGONITE" })
  sp("DRAGONITE", 600, { "DRAGON", "FLYING" }); sp("KINGDRA", 540, { "WATER", "DRAGON" })
  local RG = { "ROCK", "GROUND" }
  sp("LARVITAR", 300, RG, { "PUPITAR" }); sp("PUPITAR", 410, RG, { "TYRANITAR" })
  sp("TYRANITAR", 600, { "ROCK", "DARK" })
  -- knows nothing before level 30: must never stand in below it
  sp("LATEMON", 320, N, nil, 30)

  local matchups = {}
  for _, r in ipairs(SUPER) do matchups[#matchups + 1] = { attacker = r[1], defender = r[2], multiplier = 20 } end
  for _, r in ipairs(RESIST) do matchups[#matchups + 1] = { attacker = r[1], defender = r[2], multiplier = 5 } end
  local types = {}
  for i, id in ipairs(TYPE_IDS) do types[id] = { id = id, index = i, name = id } end

  local function row(id, index, party, trainerType)
    return { id = id, index = index, name = "?", party = party,
      trainerType = trainerType or "TRAINERTYPE_NORMAL" }
  end
  local classes = {
    FALKNER = { id = "FALKNER", index = 1, name = "FALKNER", items = {}, trainers = {
      row("FALKNER1", 1, {
        { species = "PIDGEY", level = 7, moves = { "TACKLE", "MUD_SLAP" } },
        { species = "PIDGEOTTO", level = 9, moves = { "TACKLE", "MUD_SLAP", "GUST" } },
      }, "TRAINERTYPE_MOVES"),
    } },
    YOUNGSTER = { id = "YOUNGSTER", index = 3, name = "YOUNGSTER", items = {}, trainers = {
      row("JOEY1", 1, { { species = "RATTATA", level = 4 } }),
      row("MIKEY", 2, { { species = "PIDGEY", level = 2 }, { species = "RATTATA", level = 4 } }),
      row("ALBERT", 3, { { species = "RATTATA", level = 6 }, { species = "ZUBAT", level = 8 } }),
      -- level 1 and level 80: the level percentage clamps to 2..100
      row("EDGE", 4, { { species = "SENTRET", level = 1 }, { species = "TAUROS", level = 80 } }),
    } },
    BIRD_KEEPER = { id = "BIRD_KEEPER", index = 24, name = "BIRD KEEPER", items = {}, trainers = {
      row("ROD", 1, { { species = "PIDGEY", level = 7 }, { species = "PIDGEY", level = 7 } }),
      row("ABE", 2, { { species = "SPEAROW", level = 9 } }),
    } },
    CLAIR = { id = "CLAIR", index = 8, name = "CLAIR", items = {}, trainers = {
      row("CLAIR1", 1, { { species = "DRAGONAIR", level = 37 }, { species = "DRAGONAIR", level = 37 },
        { species = "KINGDRA", level = 40, item = "DRAGON_FANG" } }),
    } },
    COOLTRAINERM = { id = "COOLTRAINERM", index = 33, name = "COOLTRAINER", items = {}, trainers = {
      row("PAUL", 1, { { species = "DRATINI", level = 30 }, { species = "DRATINI", level = 30 } }),
      row("CODY", 2, { { species = "TAUROS", level = 34 } }),
    } },
    BLUE = { id = "BLUE", index = 64, name = "BLUE", items = {}, trainers = {
      row("BLUE1", 1, { { species = "PIDGEOT", level = 56 }, { species = "TAUROS", level = 58 } }),
    } },
    CHAMPION = { id = "CHAMPION", index = 16, name = "CHAMPION", items = {}, trainers = {
      row("LANCE", 1, {
        { species = "DRAGONITE", level = 47, item = "LEFTOVERS", moves = { "HYPER_BEAM" } },
        { species = "DRAGONITE", level = 50, item = "BERRY", moves = { "HYPER_BEAM", "SLAM" } },
      }, "TRAINERTYPE_ITEM_MOVES"),
    } },
    RIVAL1 = { id = "RIVAL1", index = 9, name = "RIVAL", items = {}, trainers = {
      row("RIVAL1_1_CHIKORITA", 1, { { species = "CHIKORITA", level = 5 } }),
      row("RIVAL1_1_CYNDAQUIL", 2, { { species = "CYNDAQUIL", level = 5 } }),
      row("RIVAL1_1_TOTODILE", 3, { { species = "TOTODILE", level = 5 } }),
      row("RIVAL1_2_CHIKORITA", 4, { { species = "GASTLY", level = 12 },
        { species = "ZUBAT", level = 14 }, { species = "BAYLEEF", level = 16 } }),
      row("RIVAL1_2_TOTODILE", 6, { { species = "GASTLY", level = 12 },
        { species = "ZUBAT", level = 14 }, { species = "CROCONAW", level = 16 } }),
    } },
    RIVAL2 = { id = "RIVAL2", index = 42, name = "RIVAL", items = {}, trainers = {
      row("RIVAL2_1_CHIKORITA", 1, { { species = "HAUNTER", level = 30 },
        { species = "CROBAT", level = 32 }, { species = "MEGANIUM", level = 36 } }),
      row("RIVAL2_1_CYNDAQUIL", 2, { { species = "HAUNTER", level = 30 },
        { species = "CROBAT", level = 32 }, { species = "TYPHLOSION", level = 36 } }),
      row("RIVAL2_1_TOTODILE", 3, { { species = "GENGAR", level = 30 },
        { species = "CROBAT", level = 32 }, { species = "FERALIGATR", level = 36 } }),
    } },
  }
  -- Maps the way the extractor writes them: objects with a `trainer` field,
  -- and a leader whose battle is a `loadtrainer` in the object's script.
  local scripts = {
    ["1a:0001"] = { { op = "checkevent", event = 1 }, { op = "iftrue", script = "1a:0002" },
      { op = "loadtrainer", class = 1, member = 1 }, { op = "startbattle" } },
    ["1a:0002"] = { { op = "writetext", text = "1a:9999" } },
    ["1b:0001"] = { { op = "loadtrainer", class = 8, member = 1 }, { op = "startbattle" } },
    ["1c:0001"] = { { op = "loadtrainer", class = 64, member = 1 } },
  }
  local function obj(trainerClass, member)
    return { sprite = "SPRITE_X", trainer = { class = trainerClass, member = member } }
  end
  local maps = {
    VIOLET_GYM = { id = "VIOLET_GYM", objects = { { sprite = "SPRITE_FALKNER", scriptKey = "1a:0001" },
      obj(24, 1), obj(24, 2) } },
    BLACKTHORN_GYM_1F = { id = "BLACKTHORN_GYM_1F", objects = {
      { sprite = "SPRITE_CLAIR", scriptKey = "1b:0001" }, obj(33, 1) } },
    BLACKTHORN_GYM_2F = { id = "BLACKTHORN_GYM_2F", objects = { obj(33, 2) } },
    VIRIDIAN_GYM = { id = "VIRIDIAN_GYM", objects = { { sprite = "SPRITE_BLUE", scriptKey = "1c:0001" } } },
    ROUTE_30 = { id = "ROUTE_30", objects = { obj(3, 1), obj(3, 2), obj(3, 3) } },
  }
  return { pokemon = pokemon, moves = moves, type_chart = { matchups = matchups, types = types },
    gen2Trainers = { classes = classes }, gen2Maps = maps, gen2Scripts = scripts }
end

---------------------------------------------------------------------------
-- Harness: the module installed on a fake mod, battles opened the way
-- Battle.new does (Trainers.lookup -> Trainers.party -> trainer.party hook).
---------------------------------------------------------------------------

local function harness(data, ctx)
  local module = dofile(MODULE) -- a fresh copy each time: no state shared
  local hook
  local mod = { game = { data = data }, hooks = {
    wrap = function(_, name, fn) if name == "trainer.party" then hook = fn end end } }
  module.install(mod, ctx)
  assert(hook, "the module did not wrap trainer.party")
  local h = { module = module, ctx = ctx }
  -- returns the party the battle would fight, and the vanilla one
  function h.battle(classId, member)
    local class = data.gen2Trainers.classes[classId]
    local record = Trainers.lookup(data.gen2Trainers, class.index, member)
    local vanilla = Trainers.party(data, record)
    local party = Trainers.party(data, record)
    local out = hook(function(_, _, p) return p end, record.classId, record.id, party)
    return out, vanilla, record
  end
  return h
end

local function speciesList(party)
  local out = {}
  for i, mon in ipairs(party) do out[i] = mon.species .. "@" .. mon.level end
  return table.concat(out, ",")
end

local function allTrainers(data)
  local list = {}
  local ids = {}
  for id in pairs(data.gen2Trainers.classes) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    for member in ipairs(data.gen2Trainers.classes[id].trainers or {}) do
      list[#list + 1] = { id, member }
    end
  end
  return list
end

local function teamsOf(h, trainers)
  local out = {}
  for _, t in ipairs(trainers) do
    out[t[1] .. "#" .. t[2]] = speciesList((h.battle(t[1], t[2])))
  end
  return out
end

-- the parent of a species in the current evolution data, sorted
local function parentOf(data, species)
  local ids = {}
  for id in pairs(data.pokemon) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local def = data.pokemon[id]
    for _, e in ipairs((type(def) == "table" and def.evolutions) or {}) do
      if e.into == species and id ~= species then return id end
    end
  end
  return nil
end

-- the first stage of a species' line, from the evolution data
local function rootOf(data, species)
  for _ = 1, 8 do
    local parent = parentOf(data, species)
    if not parent then return species end
    species = parent
  end
  return species
end

local function isFinal(data, species)
  return #(data.pokemon[species].evolutions or {}) == 0
end

local function hasType(data, species, t)
  local types = data.pokemon[species].types
  return types[1] == t or types[2] == t
end

local function bst(def)
  local s = def.baseStats
  return s.hp + s.attack + s.defense + s.speed + s.specialAttack + s.specialDefense
end

local function isRival(classId) return classId == "RIVAL1" or classId == "RIVAL2" end

-- Structural checks valid for any randomized battle.
local function checkParty(data, label, party, vanilla, record, pct)
  check(#party == #vanilla, "%s: party size %d, vanilla %d", label, #party, #vanilla)
  for i, mon in ipairs(party) do
    local want = vanilla[i]
    local rowMon = record.roster[i]
    local level = Module.scaleLevel(want.level, pct)
    check(mon.level == level, "%s slot %d: level %s, want %s", label, i, mon.level, level)
    check(mon.item == rowMon.item, "%s slot %d: item %s, vanilla %s", label, i,
      tostring(mon.item), tostring(rowMon.item))
    local def = data.pokemon[mon.species]
    check(def ~= nil, "%s slot %d: unknown species %s", label, i, tostring(mon.species))
    check(#(mon.moves or {}) >= 1, "%s slot %d: %s has no moves", label, i, tostring(mon.species))
    if not isRival(record.classId) then
      check(mon.species ~= want.species, "%s slot %d: kept the vanilla %s", label, i, want.species)
    end
    if def then
      -- the level-up moves at that level, exactly as the game builds them
      local expected = Mon.movesAtLevel(def, mon.level, data.moves)
      local got, exp = {}, {}
      for j, m in ipairs(mon.moves or {}) do
        got[j] = m.id
        check(data.moves[m.id] ~= nil, "%s slot %d: unknown move %s", label, i, tostring(m.id))
      end
      for j, m in ipairs(expected) do exp[j] = m.id end
      check(table.concat(got, ",") == table.concat(exp, ","),
        "%s slot %d: %s moves %s, level-up moves %s", label, i, mon.species,
        table.concat(got, ","), table.concat(exp, ","))
    end
  end
end

---------------------------------------------------------------------------
-- The general checks, run on one dataset with one set of options.
---------------------------------------------------------------------------

local function run(data, opts)
  local trainers = allTrainers(data)
  local name = opts.name
  local extra = opts.extra or {}

  -- Vanilla: no seed, and a seed with trainers off (other answers set).
  for _, setup in ipairs({
    { seed = nil, options = {} },
    { seed = "s1", options = merge(extra, { trainers = false }) },
  }) do
    local ctx = Fake.new(setup)
    local h = harness(data, ctx)
    for _, t in ipairs(trainers) do
      local party, vanilla = h.battle(t[1], t[2])
      check(speciesList(party) == speciesList(vanilla), "%s %s#%d: changed while inactive (%s)",
        name, t[1], t[2], speciesList(party))
    end
  end

  -- Randomized: structure, validity, real change.
  local options = merge(extra, { trainers = true, trainers_similar = false })
  local ctx = Fake.new({ seed = "alpha", options = options })
  local h = harness(data, ctx)
  local changed, slots = 0, 0
  for _, t in ipairs(trainers) do
    local party, vanilla, record = h.battle(t[1], t[2])
    checkParty(data, ("%s %s#%d"):format(name, t[1], t[2]), party, vanilla, record,
      options.trainers_level)
    if not isRival(t[1]) and not options.trainers_themes then
      -- with the whole pool open, no team repeats a species
      local seen = {}
      for i, mon in ipairs(party) do
        check(not seen[mon.species], "%s %s#%d: %s twice (slots %s and %d)", name, t[1], t[2],
          mon.species, tostring(seen[mon.species]), i)
        seen[mon.species] = i
      end
    end
    for i, mon in ipairs(party) do
      slots = slots + 1
      if mon.species ~= vanilla[i].species then changed = changed + 1 end
      local first = data.pokemon[mon.species] and data.pokemon[mon.species].levelMoves[1]
      check(first and first.level <= mon.level, "%s %s#%d slot %d: %s knows no move at %d",
        name, t[1], t[2], i, mon.species, mon.level)
    end
  end
  check(slots > 0 and changed >= slots * 0.8, "%s: only %d of %d slots changed", name, changed, slots)

  -- Determinism and call order: a second module copy, trainers in reverse.
  local first = teamsOf(h, trainers)
  local reversed = {}
  for i = #trainers, 1, -1 do reversed[#reversed + 1] = trainers[i] end
  local h2 = harness(data, Fake.new({ seed = "alpha", options = options }))
  local second = teamsOf(h2, reversed)
  local againSame = teamsOf(h, trainers)
  for key, team in pairs(first) do
    check(second[key] == team, "%s %s: order or copy changed the team (%s vs %s)", name, key,
      team, tostring(second[key]))
    check(againSame[key] == team, "%s %s: a second battle changed the team", name, key)
  end

  -- Another seed gives other teams.
  local other = teamsOf(harness(data, Fake.new({ seed = "beta", options = options })), trainers)
  local differ = 0
  for key, team in pairs(first) do if other[key] ~= team then differ = differ + 1 end end
  check(differ > 0, "%s: seeds alpha and beta gave identical teams", name)

  -- Switching saves in one process: alpha, vanilla, beta.  No residue.
  local live = Fake.new({ seed = "alpha", options = options })
  local hl = harness(data, live)
  teamsOf(hl, trainers)
  live.setActive(false)
  for _, t in ipairs(trainers) do
    local party, vanilla = hl.battle(t[1], t[2])
    check(speciesList(party) == speciesList(vanilla), "%s %s#%d: randomized after returning to vanilla",
      name, t[1], t[2])
  end
  live.setActive(true, "beta", options)
  local afterSwitch = teamsOf(hl, trainers)
  for key, team in pairs(other) do
    check(afterSwitch[key] == team, "%s %s: beta after alpha differs from a fresh beta", name, key)
  end

  -- "Keep them about as strong" (checked with the other options off, since
  -- themes and "fully evolved" narrow the pool on purpose).
  if not opts.skipBand then
    local similarOpts = { trainers = true, trainers_similar = true }
    local hs = harness(data, Fake.new({ seed = "alpha", options = similarOpts }))
    local worst, total, n = 0, 0, 0
    for _, t in ipairs(trainers) do
      local party, vanilla = hs.battle(t[1], t[2])
      for i, mon in ipairs(party) do
        local a, b = data.pokemon[vanilla[i].species], data.pokemon[mon.species]
        if a and b and not isRival(t[1]) then
          local d = math.abs(bst(b) - bst(a)) / bst(a)
          worst, total, n = math.max(worst, d), total + d, n + 1
        end
      end
    end
    check(n == 0 or total / n <= (opts.meanBand or 0.15),
      "%s: similar strength mean deviation %.2f", name, n > 0 and total / n or 0)
    check(worst <= (opts.worstBand or 0.40), "%s: similar strength worst deviation %.2f", name, worst)
  end

  return h, first
end

---------------------------------------------------------------------------
-- The new options
---------------------------------------------------------------------------

-- Every themed trainer's slots have the theme type, in the current data.
local function checkThemes(data, label, h, themedTrainers)
  local themed = 0
  for _, t in ipairs(themedTrainers) do
    local party, _, record = h.battle(t.class, t.member)
    for i, mon in ipairs(party) do
      themed = themed + 1
      check(hasType(data, mon.species, t.type), "%s %s %s slot %d: %s is not %s (types %s/%s)", label,
        t.class, record.id, i, mon.species, t.type, data.pokemon[mon.species].types[1],
        data.pokemon[mon.species].types[2])
    end
  end
  return themed
end

-- { class, member, type } for every themed leader and gym trainer.
local function themedList(data, ctx)
  local list = {}
  for _, t in ipairs(allTrainers(data)) do
    local row = data.gen2Trainers.classes[t[1]].trainers[t[2]]
    local theme = Module.themeFor(ctx, data, t[1], row.id)
    if theme then list[#list + 1] = { class = t[1], member = t[2], type = theme } end
  end
  return list
end

local function themeChecks(data, label, opts)
  opts = opts or {}
  local options = { trainers = true, trainers_themes = true, trainers_similar = opts.similar }
  local ctx = Fake.new({ seed = "theme", options = options })
  local h = harness(data, ctx)
  local list = themedList(data, ctx)
  check(#list >= (opts.minThemed or 1), "%s: only %d themed trainers", label, #list)
  checkThemes(data, label, h, list)
  -- a leader's gym trainers share the leader's theme
  for classId, rows in pairs(Module.gymMembers(data)) do
    for rowId, leader in pairs(rows) do
      if leader then
        check(Module.themeFor(ctx, data, classId, rowId) == Module.themeFor(ctx, data, leader,
          data.gen2Trainers.classes[leader].trainers[1].id),
          "%s: %s %s does not share %s's theme", label, classId, tostring(rowId), leader)
      end
    end
  end
  -- determinism: a second copy and reversed order give the same teams
  local keys = {}
  for _, t in ipairs(list) do keys[#keys + 1] = { t.class, t.member } end
  local a = teamsOf(h, keys)
  local rev = {}
  for i = #keys, 1, -1 do rev[#rev + 1] = keys[i] end
  local b = teamsOf(harness(data, Fake.new({ seed = "theme", options = options })), rev)
  for k, v in pairs(a) do check(b[k] == v, "%s: themed %s changed between copies", label, k) end

  -- themes read the current types: move FLYING off every species and onto
  -- others (as a type shuffle would), then FALKNER draws from the new FLYING
  local saved = {}
  for id, def in pairs(data.pokemon) do
    if type(def) == "table" and type(def.types) == "table" then
      saved[id] = def.types
      local t1, t2 = def.types[1], def.types[2]
      local function swap(t)
        if t == "FLYING" then return "BUG" elseif t == "BUG" then return "FLYING" end
        return t
      end
      def.types = { swap(t1), swap(t2) }
    end
  end
  local hs = harness(data, Fake.new({ seed = "theme", options = options }))
  local falkner = data.gen2Trainers.classes.FALKNER and { { class = "FALKNER", member = 1, type = "FLYING" } } or {}
  check(checkThemes(data, label .. " (shuffled types)", hs, falkner) > 0 or #falkner == 0,
    "%s: FALKNER not checked", label)
  for _, t in ipairs(falkner) do
    for _, mon in ipairs((hs.battle(t.class, t.member))) do
      check(saved[mon.species][1] == "BUG" or saved[mon.species][2] == "BUG",
        "%s: FALKNER's %s was not vanilla BUG, so the shuffled types were not read", label, mon.species)
    end
  end
  for id, types in pairs(saved) do data.pokemon[id].types = types end

  -- off: FALKNER's mons are not all FLYING across seeds
  local nonFlying = 0
  for i = 1, 30 do
    local hh = harness(data, Fake.new({ seed = "off" .. i, options = { trainers = true } }))
    for _, mon in ipairs((hh.battle("FALKNER", 1))) do
      if not hasType(data, mon.species, "FLYING") then nonFlying = nonFlying + 1 end
    end
  end
  check(nonFlying > 0, "%s: themes off, yet FALKNER was all FLYING over 30 seeds", label)
  return list
end

local function evolvedChecks(data, label, from)
  local options = { trainers = true, trainers_evolved = from }
  local trainers = allTrainers(data)
  local function scan(h, tag)
    local above, belowNonFinal = 0, 0
    for _, t in ipairs(trainers) do
      local party = h.battle(t[1], t[2])
      for i, mon in ipairs(party) do
        if mon.level >= from then
          above = above + 1
          check(isFinal(data, mon.species), "%s%s %s#%d slot %d: %s at %d is not a final stage",
            label, tag, t[1], t[2], i, mon.species, mon.level)
        elseif not isFinal(data, mon.species) then
          belowNonFinal = belowNonFinal + 1
        end
      end
    end
    return above, belowNonFinal
  end
  local above, below = scan(harness(data, Fake.new({ seed = "evo", options = options })), "")
  check(above > 0, "%s: no slot at or above %d", label, from)
  check(below > 0, "%s: no unevolved mon below %d (the rule applied too widely)", label, from)
  -- with themes too: still final, still the theme where a final of it exists
  local both = merge(options, { trainers_themes = true })
  scan(harness(data, Fake.new({ seed = "evo", options = both })), " (themes)")

  -- the current evolution data: TAUROS now evolves into SNORLAX, PIDGEOT is
  -- the last stage of nothing new, and a level-50 TAUROS slot can no longer
  -- be TAUROS
  local tauros = data.pokemon.TAUROS
  local savedEvos = tauros.evolutions
  tauros.evolutions = { { method = "EVOLVE_LEVEL", level = 30, into = "SNORLAX" } }
  local h = harness(data, Fake.new({ seed = "evo", options = options }))
  scan(h, " (shuffled evolutions)")
  local found = false
  for i = 1, 40 do
    local hh = harness(data, Fake.new({ seed = "evo" .. i, options = options }))
    for _, t in ipairs(trainers) do
      for _, mon in ipairs((hh.battle(t[1], t[2]))) do
        if mon.level >= from and mon.species == "TAUROS" then found = true end
      end
    end
  end
  check(not found, "%s: TAUROS chosen at or above %d after it gained an evolution", label, from)
  tauros.evolutions = savedEvos
end

local function levelChecks(data, label)
  for _, pct in ipairs({ 110, 150 }) do
    local options = { trainers = true, trainers_level = pct }
    local h = harness(data, Fake.new({ seed = "lvl", options = options }))
    for _, t in ipairs(allTrainers(data)) do
      local party, _, record = h.battle(t[1], t[2])
      for i, mon in ipairs(party) do
        local v = tonumber(record.roster[i].level)
        local want = math.max(2, math.min(100, math.floor(v * pct / 100 + 0.5)))
        check(mon.level == want, "%s %d%% %s#%d slot %d: level %d, want %d", label, pct,
          t[1], t[2], i, mon.level, want)
        check(mon.level >= 2 and mon.level <= 100, "%s: level %d out of range", label, mon.level)
      end
    end
  end
  check(Module.scaleLevel(80, 150) == 100, "80 at 150%% is %s, want 100", Module.scaleLevel(80, 150))
  check(Module.scaleLevel(1, 110) == 2, "1 at 110%% is %s, want 2", Module.scaleLevel(1, 110))
  check(Module.scaleLevel(1, 100) == 1, "100%% must keep the vanilla level")
  check(Module.scaleLevel(9, 130) == 12, "9 at 130%% is %s, want 12", Module.scaleLevel(9, 130))
end

---------------------------------------------------------------------------
-- The rival
---------------------------------------------------------------------------

local function evolvesTo(data, from, to, steps)
  if steps == 0 then return from == to end
  for _, e in ipairs(data.pokemon[from].evolutions or {}) do
    if evolvesTo(data, e.into, to, steps - 1) then return true end
  end
  -- a line too short stops at its last stage
  return #(data.pokemon[from].evolutions or {}) == 0 and from == to
end

local function rivalChecks(data)
  local options = { trainers = true }
  -- Without anything shared: his lines stay lines, and his starter is strong
  -- against the (vanilla) starter the player took.
  local ctx = Fake.new({ seed = "rival", options = options })
  local h = harness(data, ctx)
  local early = h.battle("RIVAL1", 4)   -- GASTLY 12, ZUBAT 14, BAYLEEF 16
  local late = h.battle("RIVAL2", 1)    -- HAUNTER 30, CROBAT 32, MEGANIUM 36
  local start = h.battle("RIVAL1", 1)   -- CHIKORITA 5
  check(evolvesTo(data, early[1].species, late[1].species, 1),
    "rival: GASTLY's stand-in %s does not lead to HAUNTER's %s", early[1].species, late[1].species)
  check(evolvesTo(data, early[2].species, late[2].species, 2),
    "rival: ZUBAT's stand-in %s does not lead to CROBAT's %s", early[2].species, late[2].species)
  check(evolvesTo(data, start[1].species, early[3].species, 1),
    "rival: starter %s does not lead to %s", start[1].species, early[3].species)
  check(evolvesTo(data, early[3].species, late[3].species, 1),
    "rival: %s does not lead to %s", early[3].species, late[3].species)
  for member, ball in ipairs({ "CHIKORITA", "CYNDAQUIL", "TOTODILE" }) do
    local player = Module.PLAYER_BALL_FOR_RIVAL[ball]
    local mine = h.battle("RIVAL1", member)[1].species
    check(Module.strongAgainst(data, mine, player),
      "rival %s ball, nothing shared: %s is not strong against the player's %s", ball, mine, player)
  end

  -- With ctx.shared.starters only: his starter line follows the ball he took.
  local starters = { CHIKORITA = "MAREEP", CYNDAQUIL = "TAUROS", TOTODILE = "EEVEE" }
  local sctx = Fake.new({ seed = "rival", options = options })
  sctx.shared.starters = starters
  local hs = harness(data, sctx)
  check(hs.battle("RIVAL1", 1)[1].species == "MAREEP", "rival CHIKORITA ball: got %s, want MAREEP",
    hs.battle("RIVAL1", 1)[1].species)
  check(hs.battle("RIVAL1", 2)[1].species == "TAUROS", "rival CYNDAQUIL ball: got %s, want TAUROS",
    hs.battle("RIVAL1", 2)[1].species)
  check(hs.battle("RIVAL1", 3)[1].species == "EEVEE", "rival TOTODILE ball: got %s, want EEVEE",
    hs.battle("RIVAL1", 3)[1].species)
  check(hs.battle("RIVAL1", 4)[3].species == "FLAAFFY", "rival BAYLEEF slot: got %s, want FLAAFFY",
    hs.battle("RIVAL1", 4)[3].species)
  check(hs.battle("RIVAL2", 1)[3].species == "AMPHAROS", "rival MEGANIUM slot: got %s, want AMPHAROS",
    hs.battle("RIVAL2", 1)[3].species)
  -- a line with no evolution stays put
  check(hs.battle("RIVAL2", 2)[3].species == "TAUROS", "rival TYPHLOSION slot: got %s, want TAUROS",
    hs.battle("RIVAL2", 2)[3].species)
  -- a branching line picks one branch for the save, the same in every battle
  local croconaw = hs.battle("RIVAL1", 5)[3].species
  local feraligatr = hs.battle("RIVAL2", 3)[3].species
  check(croconaw == "VAPOREON" or croconaw == "JOLTEON" or croconaw == "FLAREON",
    "rival CROCONAW slot: got %s, want an EEVEE evolution", croconaw)
  check(feraligatr == croconaw, "rival FERALIGATR slot %s differs from CROCONAW slot %s",
    feraligatr, croconaw)

  -- With ctx.shared.starterRivalPairs (a fake value): keyed by the ball the
  -- player takes, naming the rival's species, which wins over starters.  The
  -- player gets SUNKERN / MAREEP / CATERPIE; the pairs answer with a FIRE,
  -- a ROCK/GROUND and a FLYING line, each strong against the player's.
  local pctx = Fake.new({ seed = "rival", options = options })
  local playerGets = { CHIKORITA = "SUNKERN", CYNDAQUIL = "MAREEP", TOTODILE = "CATERPIE" }
  pctx.shared.starters = playerGets
  pctx.shared.starterRivalPairs = { CHIKORITA = "CYNDAQUIL", CYNDAQUIL = "LARVITAR", TOTODILE = "PIDGEY" }
  local hp = harness(data, pctx)
  local want = { [1] = "PIDGEY", [2] = "CYNDAQUIL", [3] = "LARVITAR" } -- RIVAL1_1_<his ball>
  for member, ball in ipairs({ "CHIKORITA", "CYNDAQUIL", "TOTODILE" }) do
    local got = hp.battle("RIVAL1", member)[1].species
    local player = playerGets[Module.PLAYER_BALL_FOR_RIVAL[ball]]
    check(got == want[member], "rival %s ball with pairs: got %s, want %s", ball, got, want[member])
    check(Module.strongAgainst(data, got, player), "rival %s ball: %s is not strong against the player's %s",
      ball, got, player)
  end
  -- his starter's line follows the pair's species
  check(hp.battle("RIVAL1", 4)[3].species == "PIDGEOTTO", "rival BAYLEEF slot with pairs: got %s, want PIDGEOTTO",
    hp.battle("RIVAL1", 4)[3].species)
  check(hp.battle("RIVAL2", 1)[3].species == "PIDGEOT", "rival MEGANIUM slot with pairs: got %s, want PIDGEOT",
    hp.battle("RIVAL2", 1)[3].species)
  check(hp.battle("RIVAL1", 5)[3].species == "PUPITAR", "rival CROCONAW slot with pairs: got %s, want PUPITAR",
    hp.battle("RIVAL1", 5)[3].species)
  check(hp.battle("RIVAL2", 3)[3].species == "TYRANITAR", "rival FERALIGATR slot with pairs: got %s, want TYRANITAR",
    hp.battle("RIVAL2", 3)[3].species)
  check(hp.battle("RIVAL2", 2)[3].species == "TYPHLOSION", "rival TYPHLOSION slot with pairs: got %s, want TYPHLOSION",
    hp.battle("RIVAL2", 2)[3].species)
  -- a table value naming the species is read too
  local tctx = Fake.new({ seed = "rival", options = options })
  tctx.shared.starterRivalPairs = { CHIKORITA = { rival = "SKARMORY" } }
  check(harness(data, tctx).battle("RIVAL1", 2)[1].species == "SKARMORY", "a table pair value was not read")
  -- fully evolved from 30 reaches his last stage, still on his line
  local ectx = Fake.new({ seed = "rival", options = { trainers = true, trainers_evolved = 30 } })
  ectx.shared.starterRivalPairs = pctx.shared.starterRivalPairs
  local he = harness(data, ectx)
  check(he.battle("RIVAL2", 1)[3].species == "PIDGEOT", "rival at 36, fully evolved: %s",
    he.battle("RIVAL2", 1)[3].species)
  check(isFinal(data, he.battle("RIVAL2", 1)[1].species),
    "rival HAUNTER slot at 30 with fully evolved: %s is not final", he.battle("RIVAL2", 1)[1].species)
  check(evolvesTo(data, he.battle("RIVAL1", 4)[1].species, he.battle("RIVAL2", 1)[1].species, 2),
    "rival GASTLY line broken under fully evolved")

  -- no two of his lines share a stand-in, and none takes a starter's line
  for _, h0 in ipairs({ h, hs, hp }) do
    for _, t in ipairs({ { "RIVAL1", 4 }, { "RIVAL1", 5 }, { "RIVAL2", 1 }, { "RIVAL2", 2 }, { "RIVAL2", 3 } }) do
      local party = h0.battle(t[1], t[2])
      local roots = {}
      for i, mon in ipairs(party) do
        local root = rootOf(data, mon.species)
        check(not roots[root], "rival %s#%d: slots %s and %d share the %s line", t[1], t[2],
          tostring(roots[root]), i, root)
        roots[root] = i
      end
    end
  end
  -- set after install, read at battle time: order does not matter
  local lctx = Fake.new({ seed = "rival", options = options })
  local hl = harness(data, lctx)
  lctx.shared.starters = starters
  check(hl.battle("RIVAL1", 1)[1].species == "MAREEP", "rival: starters set after install ignored")
  lctx.shared.starterRivalPairs = pctx.shared.starterRivalPairs
  check(hl.battle("RIVAL1", 1)[1].species == "PIDGEY", "rival: pairs set after install ignored")
end

---------------------------------------------------------------------------
-- Odd inputs and the questions
---------------------------------------------------------------------------

local function utf8len(s)
  local _, n = s:gsub("[^\128-\191]", "")
  return n
end

local function questionChecks(module)
  local q = module.questions
  check(module.id == "trainers", "id is %s", tostring(module.id))
  local byKey = {}
  for i, question in ipairs(q) do
    byKey[question.key] = question
    check(question.recommended ~= nil and question.everything ~= nil, "%s lacks setup values", question.key)
    if i > 1 then check(question.onlyIf == "trainers", "%s is not gated by trainers", question.key) end
    local lines = 0
    for line in (question.text .. "\n"):gmatch("(.-)\n") do
      lines = lines + 1
      check(utf8len(line) <= 18, "%s: line %q is %d characters", question.key, line, utf8len(line))
    end
    check(lines <= 2 and not question.text:find("[\v\f]"), "%s: more than one box", question.key)
    if question.kind == "choice" then
      local values = {}
      for _, option in ipairs(question.options) do
        check(#option.label <= 12 and option.label == option.label:upper(), "%s label %q", question.key,
          option.label)
        values[option.value] = true
      end
      check(values[question.recommended] and values[question.everything],
        "%s: setup value not among the options", question.key)
    else
      check(type(question.recommended) == "boolean" and type(question.everything) == "boolean",
        "%s: yes/no setup values must be booleans", question.key)
    end
  end
  check(q[1].key == "trainers" and q[1].kind == "yesno", "first question shape")
  for _, key in ipairs({ "trainers_similar", "trainers_themes", "trainers_evolved", "trainers_level" }) do
    check(byKey[key] ~= nil, "question %s missing", key)
  end
  check(byKey.trainers_level.options[1].value == 100, "first level option is not 100")
  check(byKey.trainers_evolved.options[1].value == 0, "first evolved option is not off")
end

local function edgeChecks(data)
  local ctx = Fake.new({ seed = "edge", options = { trainers = true } })
  local h = harness(data, ctx)
  -- a party another mod built is not the roster: left alone
  local module = h.module
  local foreign = { Mon.new(data, "SNORLAX", 20, {}) }
  local out = module.apply(ctx, data, "YOUNGSTER", "JOEY1", foreign)
  check(out[1].species == "SNORLAX", "a foreign party was rewritten to %s", out[1].species)
  -- an unknown class or member: untouched
  check(module.plan(ctx, data, "NOBODY", "X") == nil, "unknown class gave a plan")
  check(module.plan(ctx, data, "YOUNGSTER", "NOBODY") == nil, "unknown member gave a plan")
  -- numeric class constant and member number reach the same trainer
  local byName = module.plan(ctx, data, "YOUNGSTER", "MIKEY")
  local byNumber = module.plan(ctx, data, 3, "MIKEY")
  check(byName and byNumber and byName[1].species == byNumber[1].species,
    "numeric class id resolved differently")
  -- gym membership from the maps: floors join, routes do not
  local members = module.gymMembers(data)
  check(members.BIRD_KEEPER and members.BIRD_KEEPER.ROD == "FALKNER", "ROD is not in FALKNER's gym")
  check(members.COOLTRAINERM and members.COOLTRAINERM.CODY == "CLAIR", "2F's CODY is not in CLAIR's gym")
  check(not (members.YOUNGSTER and members.YOUNGSTER.JOEY1), "a route trainer was given a gym")
  -- BLUE's theme is one type per save
  local tctx = Fake.new({ seed = "edge", options = { trainers = true, trainers_themes = true } })
  local blue1 = module.themeFor(tctx, data, "BLUE", "BLUE1")
  check(blue1 ~= nil and blue1 == module.themeFor(tctx, data, "BLUE", "BLUE1"), "BLUE's theme is not stable")
  local blues = {}
  for i = 1, 20 do
    blues[module.themeFor(Fake.new({ seed = "b" .. i, options = {} }), data, "BLUE", "BLUE1") or "?"] = true
  end
  local n = 0
  for _ in pairs(blues) do n = n + 1 end
  check(n > 1, "BLUE's theme never changes between seeds")
  -- the theme table names the game's own type ids
  for leader, t in pairs(module.THEMES) do
    check(t == "random" or data.type_chart.types[t] ~= nil, "%s's theme %s is not a type id", leader, t)
  end
  -- a species missing from data keeps its slot
  data.gen2Trainers.classes.ODD = { id = "ODD", index = 99, items = {}, trainers = {
    { id = "ODD1", name = "?", party = { { species = "GYARADOS_MISSING", level = 44 },
      { species = "RATTATA", level = 10 } } } } }
  local plan = module.plan(ctx, data, "ODD", "ODD1")
  check(plan[1].species == "GYARADOS_MISSING", "a species not in data was replaced: %s", plan[1].species)
  data.gen2Trainers.classes.ODD = nil
  -- LATEMON never stands in below level 30, across many seeds and options
  for i = 1, 200 do
    local opts = { trainers = true, trainers_themes = i % 2 == 0, trainers_evolved = (i % 3) * 20,
      trainers_level = i % 4 == 0 and 150 or 100 }
    local c = Fake.new({ seed = "late" .. i, options = opts })
    for _, t in ipairs(allTrainers(data)) do
      local p = module.plan(c, data, t[1], data.gen2Trainers.classes[t[1]].trainers[t[2]].id)
      for _, row in ipairs(p or {}) do
        if row.species == "LATEMON" then
          check(row.level >= 30, "LATEMON at level %d (seed late%d)", row.level, i)
        end
      end
    end
  end
  questionChecks(module)
end

---------------------------------------------------------------------------

local data = syntheticData()
run(data, { name = "synthetic", meanBand = 0.15, worstBand = 0.45 })
run(data, { name = "synthetic all-options", skipBand = true,
  extra = { trainers_themes = true, trainers_evolved = 30, trainers_level = 120, trainers_similar = true } })
themeChecks(data, "synthetic", { minThemed = 6 })
evolvedChecks(data, "synthetic", 30)
levelChecks(data, "synthetic")
rivalChecks(data)
edgeChecks(data)

local dir = os.getenv("CRYSTAL_DATA_DIR")
if dir and dir ~= "" then
  local real = {
    pokemon = dofile(dir .. "/pokemon.lua"),
    moves = dofile(dir .. "/moves.lua"),
    type_chart = dofile(dir .. "/type_chart.lua"),
    gen2Trainers = dofile(dir .. "/trainers.lua"),
    gen2Maps = dofile(dir .. "/maps.lua"),
    gen2Scripts = dofile(dir .. "/scripts.lua"),
  }
  local _, teams = run(real, { name = "crystal", meanBand = 0.12, worstBand = 0.40 })
  run(real, { name = "crystal all-options", skipBand = true,
    extra = { trainers_themes = true, trainers_evolved = 40, trainers_level = 120, trainers_similar = true } })
  local themed = themeChecks(real, "crystal", { minThemed = 60, similar = true })
  evolvedChecks(real, "crystal", 40)
  levelChecks(real, "crystal")

  -- The theme table against the vanilla data: each leader's vanilla team is
  -- mostly of the theme type (the table is not read from the data, so check it).
  for leader, t in pairs(Module.THEMES) do
    local class = real.gen2Trainers.classes[leader]
    check(class ~= nil, "crystal has no class %s", leader)
    if class and t ~= "random" then
      local party, of = class.trainers[1].party, 0
      for _, mon in ipairs(party) do if hasType(real, mon.species, t) then of = of + 1 end end
      check(of * 2 >= #party, "crystal %s: only %d of %d vanilla mons are %s", leader, of, #party, t)
    end
  end
  -- every gym with trainers was found
  local gyms = {}
  for _, rows in pairs(Module.gymMembers(real)) do
    for _, leader in pairs(rows) do if leader then gyms[leader] = (gyms[leader] or 0) + 1 end end
  end
  for _, leader in ipairs({ "FALKNER", "BUGSY", "WHITNEY", "MORTY", "CHUCK", "PRYCE", "CLAIR", "BROCK",
      "MISTY", "LT_SURGE", "ERIKA", "JANINE", "SABRINA" }) do
    check((gyms[leader] or 0) > 0, "crystal: no gym trainers found for %s", leader)
  end

  -- the rival with real starters and a fake pairs value
  local ctx = Fake.new({ seed = "real", options = { trainers = true, trainers_similar = true } })
  ctx.shared.starters = { CHIKORITA = "MAREEP", CYNDAQUIL = "LARVITAR", TOTODILE = "EEVEE" }
  local h = harness(real, ctx)
  local function show(hh, classId, member)
    local party = hh.battle(classId, member)
    local row = real.gen2Trainers.classes[classId].trainers[member]
    print(("  %s %s: %s"):format(classId, row.id, speciesList(party)))
    return party
  end
  print("crystal sample (seed real, starters CHIKORITA=MAREEP CYNDAQUIL=LARVITAR TOTODILE=EEVEE):")
  local p = show(h, "RIVAL1", 1)
  check(p[1].species == "MAREEP", "real rival CHIKORITA ball: %s", p[1].species)
  for member, row in ipairs(real.gen2Trainers.classes.RIVAL2.trainers) do
    if row.id:find("CHIKORITA") then
      local party = show(h, "RIVAL2", member)
      local last = party[#party].species
      check(last == "FLAAFFY" or last == "AMPHAROS", "real RIVAL2 %s starter slot %s", row.id, last)
      local roots = {}
      for _, mon in ipairs(party) do
        local root = rootOf(real, mon.species)
        check(not roots[root], "real RIVAL2 %s: two slots share the %s line", row.id, root)
        roots[root] = true
      end
    end
  end
  -- pairs: player takes CHIKORITA, gets MAREEP (ELECTRIC); the rival answers
  -- with GEODUDE (ROCK/GROUND), which follows into GOLEM by the last battle
  local pctx = Fake.new({ seed = "real", options = { trainers = true } })
  pctx.shared.starters = ctx.shared.starters
  pctx.shared.starterRivalPairs = { CHIKORITA = "GEODUDE", CYNDAQUIL = "TOTODILE", TOTODILE = "CYNDAQUIL" }
  local hp = harness(real, pctx)
  for member, row in ipairs(real.gen2Trainers.classes.RIVAL1.trainers) do
    if row.id == "RIVAL1_1_CYNDAQUIL" then
      local got = hp.battle("RIVAL1", member)[1].species
      check(got == "GEODUDE", "real rival with pairs: %s, want GEODUDE", got)
      check(Module.strongAgainst(real, got, "MAREEP"), "real: GEODUDE not strong against MAREEP")
    end
  end
  for member, row in ipairs(real.gen2Trainers.classes.RIVAL2.trainers) do
    if row.id:find("CYNDAQUIL") then
      local party = hp.battle("RIVAL2", member)
      local last = party[#party].species
      check(last == "GRAVELER" or last == "GOLEM", "real RIVAL2 %s starter slot %s, want GEODUDE's line",
        row.id, last)
    end
  end

  -- What each gym became for one seed, with the recommended trainer answers.
  local rec = {}
  for _, q in ipairs(Module.questions) do rec[q.key] = q.recommended end
  local gctx = Fake.new({ seed = "123456", options = rec })
  local hg = harness(real, gctx)
  print("crystal gyms and Elite Four, seed 123456, recommended answers:")
  local order = { "FALKNER", "BUGSY", "WHITNEY", "MORTY", "CHUCK", "JASMINE", "PRYCE", "CLAIR",
    "WILL", "KOGA", "BRUNO", "KAREN", "CHAMPION", "BROCK", "MISTY", "LT_SURGE", "ERIKA", "JANINE",
    "SABRINA", "BLAINE", "BLUE" }
  local gymOf = {}
  for classId, rows in pairs(Module.gymMembers(real)) do
    for rowId, leader in pairs(rows) do
      if leader then
        gymOf[leader] = gymOf[leader] or {}
        gymOf[leader][#gymOf[leader] + 1] = { classId, rowId }
      end
    end
  end
  for _, leader in ipairs(order) do
    local theme = Module.themeFor(gctx, real, leader, real.gen2Trainers.classes[leader].trainers[1].id)
    io.write(("  %s (%s): "):format(leader, tostring(theme)))
    io.write(speciesList((hg.battle(leader, 1))))
    local members = gymOf[leader] or {}
    table.sort(members, function(a, b) return a[1] .. tostring(a[2]) < b[1] .. tostring(b[2]) end)
    for _, m in ipairs(members) do
      local class = real.gen2Trainers.classes[m[1]]
      for member, row in ipairs(class.trainers) do
        if row.id == m[2] then io.write((" | %s %s: %s"):format(m[1], tostring(m[2]),
          speciesList((hg.battle(m[1], member))))) end
      end
    end
    io.write("\n")
  end
  local count = 0
  for _ in pairs(teams) do count = count + 1 end
  print(("crystal: %d trainers checked, %d themed"):format(count, #themed))
end

print(("trainers_test: %d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
