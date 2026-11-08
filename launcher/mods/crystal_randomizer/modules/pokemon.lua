-- Crystal randomizer: Pokémon types and level-up learnsets.
--
-- Species data (`data.pokemon`) is loaded at boot, but a save's seed is known
-- only once that save loads.  So this module changes nothing at install: on
-- every `ctx.onSave` it rebuilds the two fields it owns from a vanilla copy it
-- took the first time it ran, and when the save is not randomized it puts the
-- vanilla tables themselves back.  Loading another save in the same process
-- therefore never keeps the previous save's types or moves.
--
-- What it owns, per species, and nothing else:
--   def.types       replaced by a new two-entry table (a single-typed species
--                   has the same type twice, as on the cart)
--   def.levelMoves  replaced by a new list of { level, move } rows
-- TM/HM and tutor compatibility (def.tmhm, def.tutorMoves), egg moves and
-- evolutions are never touched, so every field move the story needs still
-- has its users.
--
-- Choices (stated so they can be reviewed):
--   Types: each evolution family (species joined by vanilla `evolutions`) gets
--     one shuffle of the type list, applied to every member's vanilla types.
--     So a line that shares a type keeps sharing it (Charmander, Charmeleon and
--     Charizard all get the same new type in place of FIRE), a type an
--     evolution gains stays a gained type (Charizard's FLYING becomes another
--     new type), a single type stays single and a dual type stays dual.
--     Branching families (Eevee) stay related the same way.
--   Learnsets: every row keeps its level; only the move changes.  Half the
--     picks prefer a move of one of the species' (new) types when one exists,
--     the other half are drawn from every move.  A species does not learn the
--     same move twice if that can be avoided.
--   Never stuck: the last move learned at the species' lowest level is a
--     dependable damaging move of power 60 or less (so a level 2 wild mon is
--     not carrying HYPER BEAM as its only guaranteed attack), and at every
--     level where the moves a mon arrives with change, at least one of those
--     four is a dependable damaging move.
--
-- Every list is derived from the game's data: the types are those some
-- vanilla species has (which leaves out the cart's BIRD and ??? placeholders),
-- the moves are those some vanilla species can learn by level, TM/HM, tutor or
-- egg (which leaves out STRUGGLE and the empty slot).  The only names written
-- here are move *effects* that cannot be relied on to deal damage.

-- Effects of moves with power that still cannot be relied on to hurt the foe:
-- the user faints, the move needs the target asleep, or it only reflects a hit
-- the user took, or it is a one-hit KO that usually misses.
local UNDEPENDABLE_EFFECTS = {
  EFFECT_SELFDESTRUCT = true,
  EFFECT_DREAM_EATER = true,
  EFFECT_SNORE = true,
  EFFECT_COUNTER = true,
  EFFECT_MIRROR_COAT = true,
  EFFECT_OHKO = true,
}
-- The ceiling on the guaranteed first attack (see "Never stuck" above).
local STARTING_ATTACK_MAX_POWER = 60
-- Chance that a learnset pick prefers a move of the species' own type.
local SAME_TYPE_CHANCE = 0.5

local M = {
  id = "pokemon",
  questions = {
    -- A first run keeps types and learnsets familiar; EVERYTHING shuffles both.
    { key = "pokemon_types", kind = "yesno", text = "Shuffle POKéMON\ntypes?",
      recommended = false, everything = true },
    { key = "pokemon_moves", kind = "yesno", text = "Shuffle moves\nlearned by level?",
      recommended = false, everything = true },
  },
}

-- ------------------------------------------------------------------ data

local function sortedKeys(set)
  local list = {}
  for key in pairs(set) do list[#list + 1] = key end
  table.sort(list)
  return list
end

-- A species record, as opposed to the other tables pokemon.lua carries at the
-- top level (tutorMoves, tmhmMoves, growthRates).
local function isSpecies(def)
  return type(def) == "table" and type(def.types) == "table"
    and type(def.levelMoves) == "table"
end

-- The vanilla copy: the original tables themselves (restored by reference, so
-- a restore is exact) plus a value copy to build from, so nothing a later
-- write does to a live table can leak into the next build.
local function snapshot(pokemon)
  local vanilla = {}
  for species, def in pairs(pokemon) do
    if isSpecies(def) then
      local rows = {}
      for i, row in ipairs(def.levelMoves) do
        rows[i] = { level = row.level, move = row.move }
      end
      vanilla[species] = {
        typesTable = def.types,
        levelMovesTable = def.levelMoves,
        types = { def.types[1], def.types[2] or def.types[1] },
        rows = rows,
      }
    end
  end
  return vanilla
end

-- Pools derived from the vanilla copy and the move table.
local function buildPools(pokemon, vanilla, moves)
  local typeSet, learnable = {}, {}
  local function addMove(id)
    if type(id) == "string" and type(moves[id]) == "table" then learnable[id] = true end
  end
  for species, v in pairs(vanilla) do
    typeSet[v.types[1]] = true
    typeSet[v.types[2]] = true
    for _, row in ipairs(v.rows) do addMove(row.move) end
    local def = pokemon[species]
    for _, id in ipairs(def.tmhm or {}) do addMove(id) end
    for _, id in ipairs(def.tutorMoves or {}) do addMove(id) end
    for _, id in ipairs(def.eggMoves or {}) do addMove(id) end
  end
  local pools = {
    types = sortedKeys(typeSet),
    all = sortedKeys(learnable),
    damaging = {}, starting = {},
    byType = {}, damagingByType = {}, startingByType = {},
  }
  local function add(listName, byTypeName, id, moveType)
    local list = pools[listName]
    list[#list + 1] = id
    if moveType then
      local byType = pools[byTypeName]
      byType[moveType] = byType[moveType] or {}
      local typed = byType[moveType]
      typed[#typed + 1] = id
    end
  end
  for _, id in ipairs(pools.all) do
    local move = moves[id]
    local moveType = move.type
    if moveType then
      pools.byType[moveType] = pools.byType[moveType] or {}
      local typed = pools.byType[moveType]
      typed[#typed + 1] = id
    end
    if M.isDependableAttack(move) then
      add("damaging", "damagingByType", id, moveType)
      if (move.power or 0) <= STARTING_ATTACK_MAX_POWER then
        add("starting", "startingByType", id, moveType)
      end
    end
  end
  return pools
end

-- A move that will hurt the foe whenever it hits.
function M.isDependableAttack(move)
  return type(move) == "table" and (tonumber(move.power) or 0) > 0
    and not UNDEPENDABLE_EFFECTS[move.effect]
end

-- Evolution families: species joined by any vanilla evolution row, keyed by
-- the alphabetically first member so the key does not depend on table order.
local function familyKeys(pokemon, vanilla)
  local parent = {}
  local function find(x)
    while parent[x] ~= x do
      parent[x] = parent[parent[x]]
      x = parent[x]
    end
    return x
  end
  for species in pairs(vanilla) do parent[species] = species end
  for species in pairs(vanilla) do
    for _, evo in ipairs(pokemon[species].evolutions or {}) do
      local into = evo.into or evo.species
      if into and parent[into] then
        local a, b = find(species), find(into)
        if a ~= b then
          if a < b then parent[b] = a else parent[a] = b end
        end
      end
    end
  end
  local keys = {}
  for species in pairs(vanilla) do keys[species] = find(species) end
  return keys
end

-- ----------------------------------------------------------------- types

local function newTypes(ctx, pools, family, vanillaTypes)
  -- One shuffle per family, so the mapping old type -> new type is the same
  -- for every member.
  local shuffled = ctx.rng("pokemon_types", family):shuffled(pools.types)
  local map = {}
  for i, old in ipairs(pools.types) do map[old] = shuffled[i] end
  local first = map[vanillaTypes[1]] or vanillaTypes[1]
  local second = map[vanillaTypes[2]] or vanillaTypes[2]
  return { first, second }
end

-- ------------------------------------------------------------- learnsets

-- The moves a mon arrives with at `level`: the last four distinct level-up
-- moves at or below it.  Mirrors src/battle/gen2/Mon.lua:movesAtLevel, which
-- is what wild, trainer (without set moves) and gift mons are built with.
local function movesAtLevel(rows, level)
  local known = {}
  for _, row in ipairs(rows) do
    if row.level <= level then
      local duplicate = false
      for _, existing in ipairs(known) do
        if existing == row.move then duplicate = true break end
      end
      if not duplicate then
        known[#known + 1] = row.move
        if #known > 4 then table.remove(known, 1) end
      end
    end
  end
  return known
end

-- Draw from `pool` (or, by chance, its same-type part), avoiding moves the
-- species already has where it can.
local function pickMove(rng, pool, byType, types, used)
  local typed = {}
  local seen = {}
  for _, t in ipairs(types) do
    if not seen[t] then
      seen[t] = true
      for _, id in ipairs(byType[t] or {}) do typed[#typed + 1] = id end
    end
  end
  table.sort(typed)
  local source = pool
  if #typed > 0 and rng:next() < SAME_TYPE_CHANCE then source = typed end
  if #source == 0 then return nil end
  local choice
  for _ = 1, 24 do
    choice = rng:pick(source)
    if not used[choice] then break end
  end
  return choice
end

local function newLevelMoves(ctx, pools, moves, species, vanillaRows, types)
  local rng = ctx.rng("pokemon_moves", species)
  local rows, used = {}, {}
  for i, row in ipairs(vanillaRows) do
    local move = pickMove(rng, pools.all, pools.byType, types, used) or row.move
    used[move] = true
    rows[i] = { level = row.level, move = move }
  end
  if #rows == 0 then return rows end

  local levels, lowest = {}, math.huge
  for _, row in ipairs(rows) do
    if not levels[row.level] then levels[row.level] = true end
    if row.level < lowest then lowest = row.level end
  end
  local function lastRowAt(level)
    for i = #rows, 1, -1 do
      if rows[i].level == level then return i end
    end
  end
  local function replace(index, pool, byType)
    used[rows[index].move] = nil
    local move = pickMove(rng, pool, byType, types, used)
    if move then rows[index].move = move end
    used[rows[index].move] = true
  end

  -- The guaranteed first attack: the last row at the lowest level, which is
  -- always among the four a mon of that level knows.
  replace(lastRowAt(lowest), pools.starting, pools.startingByType)

  -- Every later level where the arriving moveset changes keeps an attack.
  for _, level in ipairs(sortedKeys(levels)) do
    local hasAttack = false
    for _, id in ipairs(movesAtLevel(rows, level)) do
      if M.isDependableAttack(moves[id]) then hasAttack = true break end
    end
    if not hasAttack then replace(lastRowAt(level), pools.damaging, pools.damagingByType) end
  end
  return rows
end

-- ------------------------------------------------------------- the build

-- Rebuild (or restore) `data.pokemon` for the save that just became known.
-- `state` holds the vanilla copy between calls.  Returns a short summary.
function M.apply(data, ctx, state)
  local pokemon = data and data.pokemon
  if type(pokemon) ~= "table" then return "no data.pokemon" end
  if not state.vanilla then
    state.vanilla = snapshot(pokemon)
    state.pools = buildPools(pokemon, state.vanilla, data.moves or {})
    state.families = familyKeys(pokemon, state.vanilla)
  end
  local vanilla, pools, families = state.vanilla, state.pools, state.families
  local active = ctx.active()
  local shuffleTypes = active and ctx.option("pokemon_types") == true
  local shuffleMoves = active and ctx.option("pokemon_moves") == true
    and #pools.starting > 0

  local typed, learned = 0, 0
  for _, species in ipairs(sortedKeys(vanilla)) do
    local v, def = vanilla[species], pokemon[species]
    if def then
      local types = v.types
      if shuffleTypes then
        types = newTypes(ctx, pools, families[species], v.types)
        def.types = types
        typed = typed + 1
      else
        def.types = v.typesTable
      end
      if shuffleMoves then
        def.levelMoves = newLevelMoves(ctx, pools, data.moves, species, v.rows, types)
        learned = learned + 1
      else
        def.levelMoves = v.levelMovesTable
      end
    end
  end
  return ("types %s (%d), level moves %s (%d)"):format(
    shuffleTypes and "shuffled" or "vanilla", typed,
    shuffleMoves and "shuffled" or "vanilla", learned)
end

function M.install(mod, ctx)
  local state = {}
  ctx.onSave(function()
    local game = mod and mod.game
    local data = game and game.data
    if not data then
      ctx.log("pokemon: no game data yet; nothing changed")
      return
    end
    -- A different data table (a new boot of the dataset) needs a new copy.
    if state.data ~= data then state.data, state.vanilla = data, nil end
    ctx.log("pokemon: %s", M.apply(data, ctx, state))
  end)
end

return M
