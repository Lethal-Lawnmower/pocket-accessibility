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
-- What is kept: the party size, every level, every held item, and the fixed
-- trainer DVs (the rebuild goes through the engine's own Trainers.party).
-- What changes: the species.  Moves: every new mon gets its own level-up
-- moves at that level (the last four learned at or below it, which is what
-- the game does for a trainer without a custom moveset).  A trainer whose
-- vanilla party carried a custom moveset gets the same: a custom list was
-- written for the old species and would make no sense on the new one.
--
-- Every choice comes from ctx.rng keyed by the trainer class, the trainer's
-- member id and the party slot, so the same trainer has the same team for the
-- whole save, in whatever order battles happen.
--
-- The rival (classes RIVAL1 and RIVAL2, one person across the game) keeps his
-- evolution lines: each vanilla line he uses (his starter's, GASTLY's,
-- ZUBAT's, ...) is mapped to one new line for the save, and each of his mons
-- takes the stage of the new line matching its vanilla stage, "where
-- possible" (a shorter line stops at its last stage).  His starter line
-- follows ctx.shared.starters when the starters module set it: the vanilla
-- starter he takes (named in his member id, RIVAL1_1_CHIKORITA) becomes the
-- species the starters module put in that ball, and his later stages evolve
-- from it.
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
    { key = "trainers", kind = "yesno", text = "Shuffle trainers'\nPOKéMON?" },
    { key = "trainers_similar", kind = "yesno", onlyIf = "trainers",
      text = "Keep them about\nas strong?" },
  },
}

---------------------------------------------------------------------------
-- The species pool, derived from data.pokemon.  Cached per data table.
---------------------------------------------------------------------------

local poolCache = setmetatable({}, { __mode = "k" })

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

-- Everything this module needs to know about the species in `data`:
--   list    species ids, sorted by index then id (never pairs order)
--   bst     id -> base stat total
--   pre     id -> the species it evolves from (nil for a first stage)
--   evos    id -> sorted list of species it can evolve into
local function poolFor(data)
  local pokemon = data and data.pokemon
  if type(pokemon) ~= "table" then return nil end
  local cached = poolCache[pokemon]
  if cached then return cached end
  local list, bst = {}, {}
  for id, def in pairs(pokemon) do
    if type(id) == "string" and isSpecies(def) then
      list[#list + 1] = id
      bst[id] = baseStatTotal(def)
    end
  end
  table.sort(list, function(a, b)
    local ia, ib = pokemon[a].index, pokemon[b].index
    if ia ~= ib then return ia < ib end
    return a < b
  end)
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
    table.sort(out, function(a, b)
      local ia, ib = pokemon[a].index, pokemon[b].index
      if ia ~= ib then return ia < ib end
      return a < b
    end)
    evos[id] = out
    for _, into in ipairs(out) do
      if pre[into] == nil then pre[into] = id end
    end
  end
  cached = { list = list, bst = bst, pre = pre, evos = evos, pokemon = pokemon }
  poolCache[pokemon] = cached
  return cached
end

-- The first stage of a species' line and the species' stage in it (1, 2, 3).
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

---------------------------------------------------------------------------
-- Choosing species.
---------------------------------------------------------------------------

-- An ordinary slot: any species that knows a move at this level, other than
-- the vanilla one; within the band when "keep them about as strong" is on.
local function pickSlot(ctx, pool, similar, classId, memberId, slot, vanilla, level)
  local candidates = {}
  for _, id in ipairs(pool.list) do
    if id ~= vanilla and hasMovesAt(pool, id, level) then candidates[#candidates + 1] = id end
  end
  if #candidates == 0 then return vanilla end
  if similar and pool.bst[vanilla] then candidates = inBand(pool, candidates, pool.bst[vanilla]) end
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

-- The new first stage standing in for each of the rival's vanilla lines,
-- as { [vanilla first stage] = new first stage }.  Every line the rival uses
-- anywhere in the game's data is assigned at once, in sorted order, so two of
-- his lines never share a stand-in (no team of two BELLOSSOM) and the answer
-- does not depend on which battle comes first.  The starter lines given by
-- ctx.shared.starters are placed before the rest, so no other line takes them.
local function rivalLines(ctx, pool, similar, trainerData)
  local bases, seen = {}, {}
  local classIds = {}
  for id in pairs(RIVAL_CLASSES) do classIds[#classIds + 1] = id end
  table.sort(classIds)
  for _, classId in ipairs(classIds) do
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
  local starters = ctx.shared and ctx.shared.starters
  if type(starters) == "table" then
    for _, base in ipairs(bases) do
      local given = starters[base]
      if type(given) == "string" and pool.bst[given] then
        lines[base] = given
        taken[given], taken[(lineOf(pool, given))] = true, true
      end
    end
  end
  for _, base in ipairs(bases) do
    if not lines[base] then
      local wanted = depthOf(pool, base)
      local full, any = {}, {}
      for _, id in ipairs(pool.list) do
        if pool.pre[id] == nil and id ~= base and not taken[id] then
          any[#any + 1] = id
          if depthOf(pool, id) >= wanted then full[#full + 1] = id end
        end
      end
      local candidates = #full > 0 and full or any
      if similar and #candidates > 0 and pool.bst[base] then
        candidates = inBand(pool, candidates, pool.bst[base])
      end
      local pick = ctx.rng("trainers", "rival_line", base):pick(candidates) or base
      lines[base], taken[pick] = pick, true
    end
  end
  return lines
end

local function pickRival(ctx, pool, similar, lines, classId, memberId, slot, vanilla, level)
  local vanillaBase, stage = lineOf(pool, vanilla)
  local base = lines[vanillaBase] or vanillaBase
  local species = evolve(ctx, pool, base, stage - 1)
  -- An evolved stand-in still has to know a move at this level; fall back to
  -- earlier stages, then to an ordinary pick, rather than an empty moveset.
  while not hasMovesAt(pool, species, level) and pool.pre[species] and species ~= base do
    species = pool.pre[species]
  end
  if not hasMovesAt(pool, species, level) then
    return pickSlot(ctx, pool, similar, classId, memberId, slot, vanilla, level)
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
    -- the numeric class constant: same id space as Trainers.lookup, sorted
    -- so a duplicate index (a mod's mistake) resolves the same way each time
    local ids = {}
    for id, class in pairs(classes) do
      if type(class) == "table" and class.index == classId then ids[#ids + 1] = tostring(id) end
    end
    table.sort(ids)
    if ids[1] then return ids[1], classes[ids[1]] end
  end
  return nil
end

local function findRow(class, memberId)
  local rows = class.trainers
  if type(rows) ~= "table" then return nil end
  for i, row in ipairs(rows) do
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
  local similar = ctx.option("trainers_similar") == true
  local rival = RIVAL_CLASSES[classKey] == true
  local lines = rival and rivalLines(ctx, pool, similar, data.gen2Trainers) or nil
  local out = {}
  for slot, mon in ipairs(row.party) do
    local vanilla, level = mon.species, tonumber(mon.level) or 5
    local species = vanilla
    if pool.bst[vanilla] then
      if rival then
        species = pickRival(ctx, pool, similar, lines, classKey, rowKey, slot, vanilla, level)
      else
        species = pickSlot(ctx, pool, similar, classKey, rowKey, slot, vanilla, level)
      end
    end
    out[slot] = { species = species, level = mon.level, item = mon.item }
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
      ctx.log("trainers: randomized (similar strength %s)",
        tostring(ctx.option("trainers_similar") == true))
    end
  end)
end

return M
