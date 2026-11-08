-- Trainer teams for the Crystal randomizer: every trainer's POKéMON, gym
-- leaders, the Elite Four, RED and the rival included.
--
-- How it works.  Nothing in the game's data is changed.  The engine builds a
-- trainer's party from data.gen2Trainers (src/world/gen2/Trainers.lua) and
-- hands it to the `trainer.party` hook when the battle opens
-- (src/battle/gen2/Battle.lua).  This module wraps that hook and, when the
-- loaded save is randomized with "trainers" on, rebuilds the party with new
-- species.  Because the hook asks ctx every time, a vanilla save and a save
-- loaded after a randomized one get the untouched party with nothing to
-- restore.
--
-- Species facts are read from data.pokemon at battle time, never cached
-- across battles: types (the pokemon module may have shuffled them), base
-- stats and evolutions (the evolutions module may have shuffled those).
--
-- What is kept: the party size, every held item, and the fixed trainer DVs
-- (the rebuild goes through the engine's own Trainers.party).  Levels are kept
-- unless "trainer levels" is above 100 percent.  What changes: the species.
-- Moves: every new mon gets its own level-up moves at its level (the last
-- four learned at or below it, which is what the game does for a trainer
-- without a custom moveset).  A trainer whose vanilla party carried a custom
-- moveset gets the same: a custom list was written for the old species.
--
-- The options (CONTRACT.md, "Version 2 additions"):
--   trainers          on / off for the whole module.
--   trainers_similar  keep each new mon near the vanilla mon's base stat total.
--   trainers_themes   each gym leader and Elite Four member keeps one type for
--                     the save (M.THEMES), and so do the trainers in that
--                     leader's gym.  Their mons are drawn from species that
--                     have that type now.
--   trainers_evolved  0 (off) or a level: mons at or above it are the final
--                     stage of their line in the current evolution data.
--   trainers_level    a percentage applied to every level, clamped to 2..100.
-- In any slot, no ordinary trainer keeps the vanilla species, and a team
-- repeats a species only when its pool leaves nothing else.
--
-- Every choice comes from ctx.rng keyed by the trainer class, the trainer's
-- member id and the party slot, so the same trainer has the same team for the
-- whole save, in whatever order battles happen.
--
-- The rival (classes RIVAL1 and RIVAL2, one person across the game) keeps his
-- evolution lines: each vanilla line he uses (his starter's, GASTLY's,
-- ZUBAT's, ...) is mapped to one new line for the save, and each of his mons
-- takes the stage of the new line matching its vanilla stage, "where
-- possible" (a shorter line stops at its last stage).  His starter: his member
-- id names the vanilla ball he takes (RIVAL1_1_CHIKORITA), which tells which
-- ball the player took (M.PLAYER_BALL_FOR_RIVAL).  His starter is then, in
-- this order: ctx.shared.starterRivalPairs[the player's ball] (the starters
-- module's pick, chosen strong against the player's), ctx.shared.starters[his
-- ball] (what the starters module put in his ball), or, when neither is
-- published (starters left vanilla), a line whose current types are super
-- effective against the player's starter, as in the vanilla game.
--
-- A party the hook receives that does not match the trainer's roster in the
-- game's data (another mod's party, a Battle Tower draw) is left alone.

local RIVAL_CLASSES = { RIVAL1 = true, RIVAL2 = true }

-- species.lua index 253 is reserved for the EGG (docs/mod-api-gen2-compat.md,
-- "Mod script indices").
local EGG_INDEX = 253

-- "Keep them about as strong": candidates within this share of the vanilla
-- mon's base stat total, widened step by step until there is real choice.
local BAND_START, BAND_STEP, BAND_MAX = 0.10, 0.05, 1.00
local BAND_MIN_CHOICES = 4

local Trainers -- src.world.gen2.Trainers, required on first use

local M = {
  id = "trainers",
  questions = {
    { key = "trainers", kind = "yesno", text = "Shuffle trainers'\nPOKéMON?",
      recommended = true, everything = true },
    { key = "trainers_similar", kind = "yesno", onlyIf = "trainers",
      text = "Keep them about\nas strong?", recommended = true, everything = false },
    { key = "trainers_themes", kind = "yesno", onlyIf = "trainers",
      text = "Gyms and ELITE 4\nkeep one type?", recommended = true, everything = true },
    { key = "trainers_evolved", kind = "choice", onlyIf = "trainers",
      text = "Fully evolved\nfrom what level?",
      options = { { label = "OFF", value = 0 }, { label = "LEVEL 30", value = 30 },
        { label = "LEVEL 40", value = 40 }, { label = "LEVEL 50", value = 50 } },
      recommended = 40, everything = 30 },
    { key = "trainers_level", kind = "choice", onlyIf = "trainers",
      text = "Trainer levels:\n100 is normal.",
      options = { { label = "100 PERCENT", value = 100 }, { label = "110 PERCENT", value = 110 },
        { label = "120 PERCENT", value = 120 }, { label = "130 PERCENT", value = 130 },
        { label = "150 PERCENT", value = 150 } },
      recommended = 100, everything = 120 },
  },
}

-- The vanilla type theme of each gym leader and Elite Four member, by trainer
-- class id.  This is the one list here not read from the game's data: the
-- cart has no field naming a theme, and the vanilla types cannot be read back
-- at battle time once the pokemon module has shuffled them.  The ids are the
-- game's own type ids (data.type_chart.types); a theme whose type is missing
-- from the data is ignored.  "random" (BLUE, whose gym has no theme) is one
-- type per save.  CHAMPION is LANCE, themed DRAGON like his vanilla team.
M.THEMES = {
  FALKNER = "FLYING", BUGSY = "BUG", WHITNEY = "NORMAL", MORTY = "GHOST",
  CHUCK = "FIGHTING", JASMINE = "STEEL", PRYCE = "ICE", CLAIR = "DRAGON",
  BROCK = "ROCK", MISTY = "WATER", LT_SURGE = "ELECTRIC", ERIKA = "GRASS",
  JANINE = "POISON", SABRINA = "PSYCHIC_TYPE", BLAINE = "FIRE", BLUE = "random",
  WILL = "PSYCHIC_TYPE", KOGA = "POISON", BRUNO = "FIGHTING", KAREN = "DARK",
  CHAMPION = "DRAGON",
}

-- The rival takes the ball strong against the player's (CherrygroveCity's
-- script: player CHIKORITA -> RIVAL1_1_CYNDAQUIL, and so on).  His ball -> the
-- ball the player took.
M.PLAYER_BALL_FOR_RIVAL = { CYNDAQUIL = "CHIKORITA", TOTODILE = "CYNDAQUIL", CHIKORITA = "TOTODILE" }

local function sortedKeys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

---------------------------------------------------------------------------
-- The species pool, read from data.pokemon as it is now.
---------------------------------------------------------------------------

local function baseStatTotal(def)
  local s = def.baseStats
  local total = 0
  for _, key in ipairs({ "hp", "attack", "defense", "speed", "specialAttack", "specialDefense" }) do
    total = total + (tonumber(s[key]) or 0)
  end
  if total == 0 then total = tonumber(s.special) or 0 end
  return total
end

local function isSpecies(def)
  return type(def) == "table" and type(def.baseStats) == "table"
    and type(def.levelMoves) == "table" and #def.levelMoves > 0
    and type(def.index) == "number" and def.index > 0 and def.index ~= EGG_INDEX
end

-- Everything this module needs to know about the species in `data`, now:
--   list    species ids, sorted by index then id (never pairs order)
--   bst     id -> base stat total
--   types   id -> { type, type } (current, maybe shuffled)
--   pre     id -> the species it evolves from (nil for a first stage)
--   evos    id -> sorted list of species it can evolve into
-- Built on every call (a few hundred species, once per battle), because the
-- pokemon, stats and evolutions modules change these fields when a save loads.
local function poolFor(data)
  local pokemon = data and data.pokemon
  if type(pokemon) ~= "table" then return nil end
  local list, bst, types = {}, {}, {}
  for id, def in pairs(pokemon) do
    if type(id) == "string" and isSpecies(def) then
      list[#list + 1] = id
      bst[id] = baseStatTotal(def)
      local t = type(def.types) == "table" and def.types or {}
      types[id] = { t[1], t[2] or t[1] }
    end
  end
  local function byIndex(a, b)
    local ia, ib = pokemon[a].index, pokemon[b].index
    if ia ~= ib then return ia < ib end
    return a < b
  end
  table.sort(list, byIndex)
  local pre, evos = {}, {}
  for _, id in ipairs(list) do
    local seen, out = {}, {}
    for _, evo in ipairs(pokemon[id].evolutions or {}) do
      local into = type(evo) == "table" and (evo.into or evo.species) or nil
      if into and bst[into] and into ~= id and not seen[into] then
        seen[into] = true
        out[#out + 1] = into
      end
    end
    table.sort(out, byIndex)
    evos[id] = out
  end
  -- pre in sorted order, so a species two others evolve into always names
  -- the same parent
  for _, id in ipairs(list) do
    for _, into in ipairs(evos[id]) do
      if pre[into] == nil then pre[into] = id end
    end
  end
  return { list = list, bst = bst, types = types, pre = pre, evos = evos, pokemon = pokemon }
end

-- The first stage of a species' line and the species' stage in it (1, 2, 3).
-- The guard also stops a loop a shuffled evolution table might contain.
local function lineOf(pool, species)
  local base, stage = species, 1
  while pool.pre[base] and stage < 8 do
    base, stage = pool.pre[base], stage + 1
  end
  return base, stage
end

-- How many stages a line has from `species` on (the longest branch).
local function depthOf(pool, species, guard)
  guard = guard or 0
  if guard > 8 then return 1 end
  local best = 1
  for _, into in ipairs(pool.evos[species] or {}) do
    local d = 1 + depthOf(pool, into, guard + 1)
    if d > best then best = d end
  end
  return best
end

local function isFinal(pool, species)
  return #(pool.evos[species] or {}) == 0
end

-- The strongest final stage reachable from `species` (its own total if final).
local function finalBst(pool, species, guard)
  guard = guard or 0
  local evos = pool.evos[species] or {}
  if #evos == 0 or guard > 8 then return pool.bst[species] or 0 end
  local best = 0
  for _, into in ipairs(evos) do best = math.max(best, finalBst(pool, into, guard + 1)) end
  return best
end

local function hasType(pool, species, typeId)
  local t = pool.types[species]
  return t ~= nil and (t[1] == typeId or t[2] == typeId)
end

-- A species can stand in a battle at `level` only if it knows a move there.
local function hasMovesAt(pool, species, level)
  for _, entry in ipairs(pool.pokemon[species].levelMoves or {}) do
    if (tonumber(entry.level) or 1) <= level then return true end
  end
  return false
end

-- Narrow `candidates` to a base stat band around `target`, widening until at
-- least BAND_MIN_CHOICES remain (or the band covers everything).
local function inBand(pool, candidates, target)
  local pct = BAND_START
  while true do
    local lo, hi = target * (1 - pct), target * (1 + pct)
    local out = {}
    for _, id in ipairs(candidates) do
      local v = pool.bst[id]
      if v >= lo and v <= hi then out[#out + 1] = id end
    end
    if #out >= BAND_MIN_CHOICES or pct >= BAND_MAX then
      if #out > 0 then return out end
      return candidates
    end
    pct = pct + BAND_STEP
  end
end

-- Gen 2's x10 type multiplier of an attacking type against a defender's
-- types, the rule of src/battle/gen2/Damage.lua typeMultiplier (each matchup
-- row applied in turn, floored), from the game's own type chart.
local function typeMultiplier(attackType, defenderTypes, matchups)
  local multiplier = 10
  for _, row in ipairs(matchups or {}) do
    if row.attacker == attackType then
      for _, defenderType in ipairs(defenderTypes or {}) do
        if row.defender == defenderType then
          multiplier = math.floor(multiplier * row.multiplier / 10)
          break
        end
      end
    end
  end
  return multiplier
end

-- True when one of `attacker`'s current types is super effective against
-- `defender`'s current types.
function M.strongAgainst(data, attacker, defender)
  local pokemon = data and data.pokemon or {}
  local a, d = pokemon[attacker], pokemon[defender]
  local matchups = data and data.type_chart and data.type_chart.matchups
  if not (a and d and type(a.types) == "table" and type(d.types) == "table" and matchups) then
    return false
  end
  local defending = { d.types[1], d.types[2] ~= d.types[1] and d.types[2] or nil }
  for _, t in ipairs({ a.types[1], a.types[2] }) do
    if typeMultiplier(t, defending, matchups) > 10 then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- This save's settings.
---------------------------------------------------------------------------

local function settingsOf(ctx)
  local evolvedFrom = tonumber(ctx.option("trainers_evolved")) or 0
  if evolvedFrom <= 0 then evolvedFrom = nil end
  local pct = tonumber(ctx.option("trainers_level")) or 100
  if pct <= 0 then pct = 100 end
  return {
    similar = ctx.option("trainers_similar") == true,
    themes = ctx.option("trainers_themes") == true,
    evolvedFrom = evolvedFrom,
    levelPct = pct,
  }
end

-- A level after the percentage, clamped to 2..100.  At 100 percent the
-- vanilla level is kept exactly.
function M.scaleLevel(level, pct)
  level = tonumber(level) or 5
  if not pct or pct == 100 then return level end
  local scaled = math.floor(level * pct / 100 + 0.5)
  return math.max(2, math.min(100, scaled))
end

local function forcedAt(settings, level)
  return settings.evolvedFrom ~= nil and level >= settings.evolvedFrom
end

---------------------------------------------------------------------------
-- Gyms: which trainers stand in which leader's gym, from the map data.
---------------------------------------------------------------------------

local gymCache = setmetatable({}, { __mode = "k" })

-- The class id for a numeric class constant, sorted so a duplicate index (a
-- mod's mistake) resolves the same way each time.
local function classIdByIndex(classes)
  local out = {}
  for _, id in ipairs(sortedKeys(classes)) do
    local class = classes[id]
    if type(class) == "table" and type(class.index) == "number" and out[class.index] == nil then
      out[class.index] = id
    end
  end
  return out
end

-- { [class id] = { [row id] = leader class id } } for every trainer met in a
-- themed leader's gym.  A gym is the maps sharing a name once a floor suffix
-- is dropped (BLACKTHORN_GYM_1F, BLACKTHORN_GYM_2F); the trainers in it are
-- those its objects name (`trainer` on an object event) or whose battle its
-- scripts load (`loadtrainer`, the leader himself and JANINE's disguised
-- trainers).  A trainer found in two themed gyms is left unthemed.
local function gymMembers(data)
  local maps, scripts = data.gen2Maps, data.gen2Scripts or {}
  local classes = data.gen2Trainers and data.gen2Trainers.classes
  if type(maps) ~= "table" or type(classes) ~= "table" then return {} end
  local cached = gymCache[maps]
  if cached and cached.classes == classes then return cached.members end
  local byIndex = classIdByIndex(classes)

  local function refsOf(map)
    local refs, seen = {}, {}
    local function add(classIndex, member)
      local classId = byIndex[classIndex]
      local class = classId and classes[classId]
      local row = class and class.trainers and class.trainers[member]
      if type(row) == "table" and row.id ~= nil then refs[#refs + 1] = { classId, row.id } end
    end
    local function scan(key, depth)
      if type(key) ~= "string" or seen[key] or depth > 6 or type(scripts[key]) ~= "table" then return end
      seen[key] = true
      for _, cmd in ipairs(scripts[key]) do
        if type(cmd) == "table" then
          if cmd.op == "loadtrainer" then add(cmd.class, cmd.member) end
          for _, field in ipairs(sortedKeys(cmd)) do
            local value = cmd[field]
            if type(value) == "string" and field ~= "text" then scan(value, depth + 1) end
          end
        end
      end
    end
    for _, object in ipairs(map.objects or {}) do
      if type(object) == "table" then
        if type(object.trainer) == "table" then add(object.trainer.class, object.trainer.member) end
        scan(object.scriptKey, 0)
      end
    end
    for _, list in ipairs({ "coordEvents", "bgEvents", "sceneScripts", "callbacks" }) do
      for _, event in ipairs(type(map[list]) == "table" and map[list] or {}) do
        if type(event) == "table" then
          for _, field in ipairs(sortedKeys(event)) do scan(event[field], 0) end
        end
      end
    end
    return refs
  end

  local groups, groupIds = {}, {}
  for _, mapId in ipairs(sortedKeys(maps)) do
    local map = maps[mapId]
    if type(map) == "table" then
      local name = tostring(map.id or mapId):gsub("_B?%d+F$", "")
      if not groups[name] then groups[name] = {} groupIds[#groupIds + 1] = name end
      for _, ref in ipairs(refsOf(map)) do groups[name][#groups[name] + 1] = ref end
    end
  end
  local members = {}
  for _, name in ipairs(groupIds) do
    local refs, leader, leaders = groups[name], nil, 0
    local seenLeader = {}
    for _, ref in ipairs(refs) do
      if M.THEMES[ref[1]] and not seenLeader[ref[1]] then
        seenLeader[ref[1]], leader, leaders = true, ref[1], leaders + 1
      end
    end
    if leaders == 1 then
      for _, ref in ipairs(refs) do
        local classId, rowId = ref[1], ref[2]
        if not M.THEMES[classId] and not RIVAL_CLASSES[classId] then
          members[classId] = members[classId] or {}
          local was = members[classId][rowId]
          if was == nil then members[classId][rowId] = leader
          elseif was ~= leader then members[classId][rowId] = false end
        end
      end
    end
  end
  gymCache[maps] = { classes = classes, members = members }
  return members
end

M.gymMembers = gymMembers

-- The type a trainer's team is drawn from, or nil.
local function themeFor(ctx, data, pool, classKey, rowKey)
  local leader = M.THEMES[classKey] and classKey or nil
  if not leader then
    local byClass = gymMembers(data)[classKey]
    leader = byClass and byClass[rowKey] or nil
  end
  if not leader then return nil end
  local typeId = M.THEMES[leader]
  -- the types some species has now, sorted
  local present, list = {}, {}
  for _, id in ipairs(pool.list) do
    for _, t in ipairs(pool.types[id]) do
      if type(t) == "string" and not present[t] then present[t] = true list[#list + 1] = t end
    end
  end
  table.sort(list)
  if typeId == "random" then
    return ctx.rng("trainers", "theme", leader):pick(list), leader
  end
  local known = data.type_chart and data.type_chart.types
  if type(known) == "table" and next(known) ~= nil and known[typeId] == nil then return nil end
  if not present[typeId] then return nil end
  return typeId, leader
end

M.themeFor = function(ctx, data, classKey, rowKey)
  local pool = poolFor(data)
  return pool and themeFor(ctx, data, pool, classKey, rowKey)
end

---------------------------------------------------------------------------
-- Choosing species.
---------------------------------------------------------------------------

-- An ordinary slot: any species other than the vanilla one that knows a move
-- at this level; of the theme's type when there is one; a final stage when
-- "fully evolved" applies at this level; within the band when "keep them
-- about as strong" is on.  A filter that leaves nothing is dropped rather
-- than keep the vanilla species: a themed slot with no final stage of its
-- type left takes an earlier stage of that type, and a type no candidate has
-- is dropped last.
local function pickSlot(ctx, pool, settings, classId, memberId, slot, vanilla, level, theme, used)
  local forced = forcedAt(settings, level)
  local base = {}
  for _, id in ipairs(pool.list) do
    if id ~= vanilla and hasMovesAt(pool, id, level) then base[#base + 1] = id end
  end
  if #base == 0 then return vanilla end
  local function filter(list, keep)
    local out = {}
    for _, id in ipairs(list) do if keep(id) then out[#out + 1] = id end end
    return out
  end
  local candidates = base
  if forced then
    local finals = filter(base, function(id) return isFinal(pool, id) end)
    if #finals > 0 then candidates = finals end
  end
  if theme then
    local themed = filter(candidates, function(id) return hasType(pool, id, theme) end)
    if #themed == 0 and candidates ~= base then
      themed = filter(base, function(id) return hasType(pool, id, theme) end)
    end
    if #themed > 0 then candidates = themed end
  end
  -- a species already in this team only when nothing else is left (a small
  -- themed pool, LANCE's DRAGON at "fully evolved")
  if used then
    local fresh = filter(candidates, function(id) return not used[id] end)
    if #fresh > 0 then candidates = fresh end
  end
  if settings.similar and pool.bst[vanilla] then
    local target = forced and finalBst(pool, vanilla) or pool.bst[vanilla]
    candidates = inBand(pool, candidates, target)
  end
  return ctx.rng("trainers", "slot", classId, memberId, slot):pick(candidates) or vanilla
end

-- Walk `steps` evolutions up from `species`.  A branching line (EEVEE,
-- POLIWHIRL, ...) takes one branch per save, keyed by where it branches.
local function evolve(ctx, pool, species, steps)
  local current = species
  for _ = 1, steps do
    local options = pool.evos[current]
    if not options or #options == 0 then break end
    if #options == 1 then
      current = options[1]
    else
      current = ctx.rng("trainers", "branch", current):pick(options)
    end
  end
  return current
end

-- A species named in a shared table, if it is one.  starterRivalPairs values
-- may be a species id or a table naming it (`rival` or `species`).
local function sharedSpecies(pool, value)
  if type(value) == "table" then value = value.rival or value.species end
  if type(value) == "string" and pool.bst[value] then return value end
  return nil
end

-- The new first stage standing in for each of the rival's vanilla lines,
-- as { [vanilla first stage] = new first stage }.  Every line the rival uses
-- anywhere in the game's data is assigned at once, in sorted order, so two of
-- his lines never share a stand-in (no team of two BELLOSSOM) and the answer
-- does not depend on which battle comes first.  His starter lines are placed
-- before the rest, so no other line takes them.
local function rivalLines(ctx, pool, data, settings)
  local trainerData = data.gen2Trainers
  local bases, seen = {}, {}
  for _, classId in ipairs(sortedKeys(RIVAL_CLASSES)) do
    local class = trainerData.classes[classId]
    for _, row in ipairs((type(class) == "table" and class.trainers) or {}) do
      for _, mon in ipairs((type(row) == "table" and row.party) or {}) do
        if pool.bst[mon.species] then
          local base = lineOf(pool, mon.species)
          if not seen[base] then seen[base] = true bases[#bases + 1] = base end
        end
      end
    end
  end
  table.sort(bases)
  local lines, taken = {}, {}
  local function take(base, species)
    lines[base] = species
    taken[species], taken[(lineOf(pool, species))] = true, true
  end
  local shared = ctx.shared or {}
  local pairs_ = type(shared.starterRivalPairs) == "table" and shared.starterRivalPairs or nil
  local starters = type(shared.starters) == "table" and shared.starters or nil
  -- the starters module's choices first
  for _, ball in ipairs(sortedKeys(M.PLAYER_BALL_FOR_RIVAL)) do
    if seen[ball] then
      local given = pairs_ and sharedSpecies(pool, pairs_[M.PLAYER_BALL_FOR_RIVAL[ball]])
      given = given or (starters and sharedSpecies(pool, starters[ball]))
      if given then take(ball, given) end
    end
  end

  local function firstStages(wanted)
    local full, any = {}, {}
    for _, id in ipairs(pool.list) do
      if pool.pre[id] == nil and not taken[id] then
        any[#any + 1] = id
        if depthOf(pool, id) >= wanted then full[#full + 1] = id end
      end
    end
    return #full > 0 and full or any
  end

  -- with nothing published, a starter line strong against the player's
  -- starter, which is then the vanilla one
  if not pairs_ and not starters then
    for _, ball in ipairs(sortedKeys(M.PLAYER_BALL_FOR_RIVAL)) do
      if seen[ball] and not lines[ball] then
        local player = M.PLAYER_BALL_FOR_RIVAL[ball]
        local candidates, strong = firstStages(depthOf(pool, ball)), {}
        for _, id in ipairs(candidates) do
          if id ~= ball and id ~= player and M.strongAgainst(data, id, player) then
            strong[#strong + 1] = id
          end
        end
        if #strong > 0 then candidates = strong end
        if settings.similar and #candidates > 0 and pool.bst[ball] then
          candidates = inBand(pool, candidates, pool.bst[ball])
        end
        local pick = ctx.rng("trainers", "rival_line", ball):pick(candidates)
        if pick then take(ball, pick) end
      end
    end
  end

  for _, base in ipairs(bases) do
    if not lines[base] then
      local candidates = {}
      for _, id in ipairs(firstStages(depthOf(pool, base))) do
        if id ~= base then candidates[#candidates + 1] = id end
      end
      if settings.similar and #candidates > 0 and pool.bst[base] then
        candidates = inBand(pool, candidates, pool.bst[base])
      end
      local pick = ctx.rng("trainers", "rival_line", base):pick(candidates) or base
      take(base, pick)
    end
  end
  return lines
end

local function pickRival(ctx, pool, settings, lines, classId, memberId, slot, vanilla, level)
  local vanillaBase, stage = lineOf(pool, vanilla)
  local base = lines[vanillaBase] or vanillaBase
  local steps = forcedAt(settings, level) and 8 or stage - 1
  local species = evolve(ctx, pool, base, steps)
  -- An evolved stand-in still has to know a move at this level; fall back to
  -- earlier stages, then to an ordinary pick, rather than an empty moveset.
  while not hasMovesAt(pool, species, level) and pool.pre[species] and species ~= base do
    species = pool.pre[species]
  end
  if not hasMovesAt(pool, species, level) then
    return pickSlot(ctx, pool, settings, classId, memberId, slot, vanilla, level, nil)
  end
  return species
end

---------------------------------------------------------------------------
-- Rosters.
---------------------------------------------------------------------------

local function findClass(trainerData, classId)
  local classes = trainerData and trainerData.classes
  if type(classes) ~= "table" then return nil end
  if type(classId) == "string" and type(classes[classId]) == "table" then
    return classId, classes[classId]
  end
  if type(classId) == "number" then
    local id = classIdByIndex(classes)[classId]
    if id then return id, classes[id] end
  end
  return nil
end

local function findRow(class, memberId)
  local rows = class.trainers
  if type(rows) ~= "table" then return nil end
  for _, row in ipairs(rows) do
    if type(row) == "table" and row.id ~= nil and row.id == memberId then return row, row.id end
  end
  if type(memberId) == "number" and type(rows[memberId]) == "table" then
    local row = rows[memberId]
    return row, row.id or memberId
  end
  return nil
end

local function active(ctx)
  return ctx.active() and ctx.option("trainers") == true
end

-- The randomized roster for one trainer: a list of { species, level, item }
-- rows, or nil when this save leaves trainers vanilla or the trainer is not
-- in the game's data.  Pure: same data, seed and keys, same answer.
function M.plan(ctx, data, classId, memberId)
  if not active(ctx) then return nil end
  local pool = poolFor(data)
  local classKey, class = findClass(data and data.gen2Trainers, classId)
  if not (pool and class) then return nil end
  local row, rowKey = findRow(class, memberId)
  if not (row and type(row.party) == "table") then return nil end
  local settings = settingsOf(ctx)
  local rival = RIVAL_CLASSES[classKey] == true
  local lines = rival and rivalLines(ctx, pool, data, settings) or nil
  local theme = (not rival and settings.themes) and themeFor(ctx, data, pool, classKey, rowKey) or nil
  local out, used = {}, {}
  for slot, mon in ipairs(row.party) do
    local vanilla = mon.species
    local level = M.scaleLevel(mon.level, settings.levelPct)
    local species = vanilla
    if pool.bst[vanilla] then
      if rival then
        species = pickRival(ctx, pool, settings, lines, classKey, rowKey, slot, vanilla, level)
      else
        species = pickSlot(ctx, pool, settings, classKey, rowKey, slot, vanilla, level, theme, used)
        used[species] = true
      end
    end
    out[slot] = { species = species, level = level, item = mon.item }
  end
  return out, row
end

-- The party the hook was handed is the one the engine built from `row`.
local function matchesRoster(party, row)
  if type(party) ~= "table" or #party ~= #row.party then return false end
  for i, mon in ipairs(party) do
    local want = row.party[i]
    if type(mon) ~= "table" or mon.species ~= want.species
      or tonumber(mon.level) ~= tonumber(want.level) then
      return false
    end
  end
  return true
end

-- Rebuild `party` in place (it is the trainer record's own party table, so
-- the battle's enemyParty and trainer.party stay one list).
function M.apply(ctx, data, classId, memberId, party)
  local plan, row = M.plan(ctx, data, classId, memberId)
  if not plan or not matchesRoster(party, row) then return party end
  Trainers = Trainers or require("src.world.gen2.Trainers")
  for i, newRow in ipairs(plan) do
    -- one row at a time, so a species the engine refuses keeps its slot
    local built = Trainers.party(data, { roster = { newRow } })[1]
    if built then party[i] = built end
  end
  return party
end

function M.install(mod, ctx)
  mod.hooks:wrap("trainer.party", function(nextFn, classId, memberId, party, ...)
    local result = nextFn(classId, memberId, party, ...)
    if not active(ctx) then return result end
    local game = mod.game
    local data = game and game.data
    if not (data and data.gen2Trainers) then return result end
    return M.apply(ctx, data, classId, memberId, result)
  end)
  ctx.onSave(function(isActive)
    -- nothing to restore: the hook reads ctx on every battle
    if isActive and ctx.option("trainers") then
      local s = settingsOf(ctx)
      ctx.log("trainers: randomized (similar %s, themes %s, fully evolved from %s, levels %s percent)",
        tostring(s.similar), tostring(s.themes), tostring(s.evolvedFrom or "off"), tostring(s.levelPct))
    end
  end)
end

return M
