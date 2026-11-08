-- Test for modules/trainers.lua.  Run from the repository root:
--   luajit launcher/mods/crystal_randomizer/tests/trainers_test.lua
--
-- Uses a small synthetic dataset shaped like the extracted Crystal data
-- (data.pokemon, data.moves, data.gen2Trainers.classes), so it needs no ROM,
-- and the engine's own Trainers.party / Mon.new to build the parties, which is
-- the path the game takes.  CRYSTAL_DATA_DIR=<an identity's
-- crystal/data/generated folder> additionally runs the checks on real
-- extracted data (every trainer in the game).

package.path = "./?.lua;./?/init.lua;" .. package.path

local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Trainers = require("src.world.gen2.Trainers")
local Mon = require("src.battle.gen2.Mon")

local MODULE = "launcher/mods/crystal_randomizer/modules/trainers.lua"

local failures, checks = 0, 0
local function check(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print("FAIL " .. (select("#", ...) > 0 and fmt:format(...) or fmt))
  end
end

---------------------------------------------------------------------------
-- Synthetic data
---------------------------------------------------------------------------

local MOVE_IDS = { "TACKLE", "GROWL", "EMBER", "WATER_GUN", "VINE_WHIP", "LICK",
  "BITE", "GUST", "PECK", "SLAM", "PSYCHIC_M", "HYPER_BEAM", "MUD_SLAP", "SPLASH" }

local function syntheticData()
  local moves = {}
  for i, id in ipairs(MOVE_IDS) do moves[id] = { id = id, pp = 10 + i, index = i } end
  local pokemon = { growthRates = { GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1 } } }
  local nextIndex = 0
  local function sp(id, bst, evos, firstLevel)
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
      genderRatio = 31, types = { "NORMAL", "NORMAL" },
      baseStats = { hp = per, attack = per, defense = per, speed = per,
        specialAttack = per, specialDefense = per },
      levelMoves = levelMoves, evolutions = evolutions,
    }
  end
  sp("CHIKORITA", 318, { "BAYLEEF" }); sp("BAYLEEF", 405, { "MEGANIUM" }); sp("MEGANIUM", 525)
  sp("CYNDAQUIL", 309, { "QUILAVA" }); sp("QUILAVA", 405, { "TYPHLOSION" }); sp("TYPHLOSION", 534)
  sp("TOTODILE", 314, { "CROCONAW" }); sp("CROCONAW", 405, { "FERALIGATR" }); sp("FERALIGATR", 530)
  sp("GASTLY", 310, { "HAUNTER" }); sp("HAUNTER", 405, { "GENGAR" }); sp("GENGAR", 500)
  sp("ZUBAT", 245, { "GOLBAT" }); sp("GOLBAT", 455, { "CROBAT" }); sp("CROBAT", 535)
  sp("PIDGEY", 251, { "PIDGEOTTO" }); sp("PIDGEOTTO", 349, { "PIDGEOT" }); sp("PIDGEOT", 469)
  sp("MAREEP", 280, { "FLAAFFY" }); sp("FLAAFFY", 365, { "AMPHAROS" }); sp("AMPHAROS", 510)
  sp("RATTATA", 253, { "RATICATE" }); sp("RATICATE", 413)
  sp("SENTRET", 215, { "FURRET" }); sp("FURRET", 415)
  sp("HOOTHOOT", 262, { "NOCTOWL" }); sp("NOCTOWL", 442)
  sp("EEVEE", 325, { "VAPOREON", "JOLTEON", "FLAREON" })
  sp("VAPOREON", 525); sp("JOLTEON", 525); sp("FLAREON", 525)
  sp("TAUROS", 490); sp("DITTO", 288); sp("DUNSPARCE", 415); sp("GIRAFARIG", 455)
  sp("SNORLAX", 540); sp("MEWTWO", 680); sp("SUNKERN", 180, { "SUNFLORA" }); sp("SUNFLORA", 425)
  sp("CATERPIE", 195, { "METAPOD" }); sp("METAPOD", 205, { "BUTTERFREE" }); sp("BUTTERFREE", 385)
  sp("DRATINI", 300, { "DRAGONAIR" }); sp("DRAGONAIR", 420, { "DRAGONITE" }); sp("DRAGONITE", 600)
  sp("LARVITAR", 300, { "PUPITAR" }); sp("PUPITAR", 410, { "TYRANITAR" }); sp("TYRANITAR", 600)
  -- knows nothing before level 30: must never stand in below it
  sp("LATEMON", 320, nil, 30)

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
  return { pokemon = pokemon, moves = moves, gen2Trainers = { classes = classes } }
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
  local h = { module = module }
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

-- the first stage of a species' line, from the evolution data
local function rootOf(data, species)
  for _ = 1, 8 do
    local parent
    local ids = {}
    for id in pairs(data.pokemon) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local def = data.pokemon[id]
      for _, e in ipairs((type(def) == "table" and def.evolutions) or {}) do
        if e.into == species and id ~= species then parent = id break end
      end
      if parent then break end
    end
    if not parent then return species end
    species = parent
  end
  return species
end

local function bst(def)
  local s = def.baseStats
  return s.hp + s.attack + s.defense + s.speed + s.specialAttack + s.specialDefense
end

-- Structural checks valid for any randomized battle.
local function checkParty(data, label, party, vanilla, record)
  check(#party == #vanilla, "%s: party size %d, vanilla %d", label, #party, #vanilla)
  for i, mon in ipairs(party) do
    local want = vanilla[i]
    local rowMon = record.roster[i]
    check(mon.level == want.level, "%s slot %d: level %s, vanilla %s", label, i, mon.level, want.level)
    check(mon.item == rowMon.item, "%s slot %d: item %s, vanilla %s", label, i,
      tostring(mon.item), tostring(rowMon.item))
    local def = data.pokemon[mon.species]
    check(def ~= nil, "%s slot %d: unknown species %s", label, i, tostring(mon.species))
    check(#(mon.moves or {}) >= 1, "%s slot %d: %s has no moves", label, i, tostring(mon.species))
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
-- The checks, run on one dataset.
---------------------------------------------------------------------------

local function run(data, opts)
  local trainers = allTrainers(data)
  local name = opts.name

  -- Vanilla: no seed, and a seed with trainers off.
  for _, setup in ipairs({
    { seed = nil, options = {} },
    { seed = "s1", options = { trainers = false } },
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
  local options = { trainers = true, trainers_similar = false }
  local ctx = Fake.new({ seed = "alpha", options = options })
  local h = harness(data, ctx)
  local changed, slots = 0, 0
  for _, t in ipairs(trainers) do
    local party, vanilla, record = h.battle(t[1], t[2])
    checkParty(data, ("%s %s#%d"):format(name, t[1], t[2]), party, vanilla, record)
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

  -- "Keep them about as strong": the base stat total stays near the vanilla
  -- mon's.  The band widens only where fewer than four species fit, so allow
  -- a generous margin on the small synthetic set.
  local similarOpts = { trainers = true, trainers_similar = true }
  local hs = harness(data, Fake.new({ seed = "alpha", options = similarOpts }))
  local worst, total, n = 0, 0, 0
  for _, t in ipairs(trainers) do
    local party, vanilla = hs.battle(t[1], t[2])
    local classId = t[1]
    for i, mon in ipairs(party) do
      local a, b = data.pokemon[vanilla[i].species], data.pokemon[mon.species]
      if a and b and classId ~= "RIVAL1" and classId ~= "RIVAL2" then
        local d = math.abs(bst(b) - bst(a)) / bst(a)
        worst, total, n = math.max(worst, d), total + d, n + 1
      end
    end
  end
  check(n == 0 or total / n <= (opts.meanBand or 0.15),
    "%s: similar strength mean deviation %.2f", name, n > 0 and total / n or 0)
  check(worst <= (opts.worstBand or 0.40), "%s: similar strength worst deviation %.2f", name, worst)

  return h, first
end

---------------------------------------------------------------------------
-- The rival
---------------------------------------------------------------------------

local function rivalChecks(data)
  local options = { trainers = true }
  -- Without ctx.shared.starters: his lines stay lines.
  local ctx = Fake.new({ seed = "rival", options = options })
  local h = harness(data, ctx)
  local pool = {}
  local function evolvesTo(from, to, steps)
    if steps == 0 then return from == to end
    for _, e in ipairs(data.pokemon[from].evolutions or {}) do
      if evolvesTo(e.into, to, steps - 1) then return true end
    end
    -- a line too short stops at its last stage
    return #(data.pokemon[from].evolutions or {}) == 0 and from == to
  end
  local early = h.battle("RIVAL1", 4)   -- GASTLY 12, ZUBAT 14, BAYLEEF 16
  local late = h.battle("RIVAL2", 1)    -- HAUNTER 30, CROBAT 32, MEGANIUM 36
  local start = h.battle("RIVAL1", 1)   -- CHIKORITA 5
  check(evolvesTo(early[1].species, late[1].species, 1),
    "rival: GASTLY's stand-in %s does not lead to HAUNTER's %s", early[1].species, late[1].species)
  check(evolvesTo(early[2].species, late[2].species, 2),
    "rival: ZUBAT's stand-in %s does not lead to CROBAT's %s", early[2].species, late[2].species)
  check(evolvesTo(start[1].species, early[3].species, 1),
    "rival: starter %s does not lead to %s", start[1].species, early[3].species)
  check(evolvesTo(early[3].species, late[3].species, 1),
    "rival: %s does not lead to %s", early[3].species, late[3].species)

  -- With ctx.shared.starters: his starter line follows the ball he took.
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
  -- no two of his lines share a stand-in, and none takes a starter's line
  for _, h0 in ipairs({ h, hs }) do
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
end

---------------------------------------------------------------------------
-- Odd inputs
---------------------------------------------------------------------------

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
  -- a species missing from data keeps its slot
  data.gen2Trainers.classes.ODD = { id = "ODD", index = 99, items = {}, trainers = {
    { id = "ODD1", name = "?", party = { { species = "GYARADOS_MISSING", level = 44 },
      { species = "RATTATA", level = 10 } } } } }
  local plan = module.plan(ctx, data, "ODD", "ODD1")
  check(plan[1].species == "GYARADOS_MISSING", "a species not in data was replaced: %s", plan[1].species)
  -- LATEMON never stands in below level 30, across many seeds
  for i = 1, 200 do
    local c = Fake.new({ seed = "late" .. i, options = { trainers = true } })
    for _, t in ipairs(allTrainers(data)) do
      local p = module.plan(c, data, t[1], data.gen2Trainers.classes[t[1]].trainers[t[2]].id)
      for _, row in ipairs(p or {}) do
        if row.species == "LATEMON" then
          check(row.level >= 30, "LATEMON at level %d (seed late%d)", row.level, i)
        end
      end
    end
  end
  -- the questions follow the contract
  local q = module.questions
  check(module.id == "trainers", "id is %s", tostring(module.id))
  check(q[1].key == "trainers" and q[1].kind == "yesno", "first question shape")
  check(q[2].key == "trainers_similar" and q[2].onlyIf == "trainers", "second question shape")
end

---------------------------------------------------------------------------

local data = syntheticData()
run(data, { name = "synthetic", meanBand = 0.15, worstBand = 0.45 })
rivalChecks(data)
edgeChecks(data)

local dir = os.getenv("CRYSTAL_DATA_DIR")
if dir and dir ~= "" then
  local real = {
    pokemon = dofile(dir .. "/pokemon.lua"),
    moves = dofile(dir .. "/moves.lua"),
    gen2Trainers = dofile(dir .. "/trainers.lua"),
  }
  local _, teams = run(real, { name = "crystal", meanBand = 0.12, worstBand = 0.40 })
  -- the rival with real starters
  local ctx = Fake.new({ seed = "real", options = { trainers = true, trainers_similar = true } })
  ctx.shared.starters = { CHIKORITA = "MAREEP", CYNDAQUIL = "LARVITAR", TOTODILE = "EEVEE" }
  local h = harness(real, ctx)
  local function show(classId, member)
    local party = h.battle(classId, member)
    local row = real.gen2Trainers.classes[classId].trainers[member]
    print(("  %s %s: %s"):format(classId, row.id, speciesList(party)))
    return party
  end
  print("crystal sample (seed real, starters CHIKORITA=MAREEP CYNDAQUIL=LARVITAR TOTODILE=EEVEE):")
  local p = show("RIVAL1", 1)
  check(p[1].species == "MAREEP", "real rival CHIKORITA ball: %s", p[1].species)
  for member, row in ipairs(real.gen2Trainers.classes.RIVAL2.trainers) do
    if row.id:find("CHIKORITA") then
      local party = show("RIVAL2", member)
      local last = party[#party].species
      check(last == "FLAAFFY" or last == "AMPHAROS", "real RIVAL2 %s starter slot %s", row.id, last)
      local roots = {}
      for i, mon in ipairs(party) do
        local root = rootOf(real, mon.species)
        check(not roots[root], "real RIVAL2 %s: two slots share the %s line", row.id, root)
        roots[root] = true
      end
    end
  end
  for _, c in ipairs({ "FALKNER", "WHITNEY", "CLAIR", "WILL", "CHAMPION", "RED" }) do
    if real.gen2Trainers.classes[c] then show(c, 1) end
  end
  local count = 0
  for _ in pairs(teams) do count = count + 1 end
  print(("crystal: %d trainers checked"):format(count))
end

print(("trainers_test: %d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
