-- Crystal randomizer: species base stats and damaging moves' power, accuracy
-- and type.
--
-- Like the pokemon module, this changes nothing at install.  On every
-- `ctx.onSave` it rebuilds its fields from a vanilla copy taken the first time
-- it ran, and when the save is not randomized (or an option is off) it puts the
-- vanilla values back exactly.  Loading another save in the same process
-- therefore never keeps the previous save's stats or moves.
--
-- What it owns, and nothing else:
--   def.baseStats            per species: replaced by a new table of the six
--                            stats; restored by putting the original table back
--   move.power, .accuracy,   per damaging move, changed in place on the
--   .accuracyRaw, .type      move's own record; restored field by field
-- def.types, def.levelMoves, evolutions, PP, effects and every other field are
-- never touched.
--
-- Choices (stated so they can be reviewed):
--   Families: species joined by the vanilla `evolutions` rows (read the first
--     time this runs, before the evolutions module, later in the order, has
--     changed anything), keyed by the alphabetically first member.
--   REORDER: each family gets one shuffle of the six stat positions, applied
--     to every member's vanilla stats.  So the six values and their total are
--     kept, and a line keeps its shape (if Chikorita's best stat moves to
--     SPEED, so do Bayleef's and Meganium's).
--   REROLL: each family gets six random weights; every member's own vanilla
--     total is spread over the six stats by those weights, each stat at least
--     STAT_FLOOR and at most 255.  The total is kept exactly, and a line keeps
--     the same proportions.
--   Moves: only a damaging move whose power the game uses as its power changes
--     (power 2 or more, and not one of the effects below, which compute damage
--     another way or would break: fixed damage, one-hit KO, Return, Hidden
--     Power and so on).  STRUGGLE, status moves and those effects keep their
--     vanilla data.  HM moves change in battle like any other attack; using
--     them in the field reads only the move id (src/world/gen2/FieldMoves.lua),
--     so CUT, SURF and the rest still work out of battle.
--       power:    vanilla power times a factor from 0.5 to 1.5, rounded to a
--                 multiple of 5 when 30 or more, kept within 10..150
--       accuracy: vanilla accuracy plus one of -15, -10, -5, 0, +5, +10 points,
--                 kept within min(70, vanilla)..100; a never-miss move
--                 (EFFECT_ALWAYS_HIT) keeps its accuracy.  The cart's raw byte
--                 is written beside the percentage, the same way the game's
--                 own content schema converts it (floor(percent * 255 / 100)).
--       type:     any type some vanilla damaging move has (which leaves out
--                 the cart's ??? type of CURSE), uniformly.
--
-- Stats a player already has: Gen 2 mons keep a stored copy of their stats,
-- but this engine recalculates it from the species' base stats (Mon.refreshStats)
-- at the start of every battle, whenever the party menu or a summary opens,
-- and at level-up, Rare Candy and evolution.  So a mon caught in a randomized
-- save shows and fights with that save's stats.  Move power and type are read
-- from the move table each time, never stored on the mon.

-- Effects whose damage does not come from the move's power, or whose power is
-- tied to how the effect works, so changing the move's data would break it.
local KEEP_EFFECTS = {
  EFFECT_STATIC_DAMAGE = true,  -- SONICBOOM, DRAGON RAGE: fixed damage
  EFFECT_LEVEL_DAMAGE = true,   -- SEISMIC TOSS, NIGHT SHADE
  EFFECT_PSYWAVE = true,
  EFFECT_SUPER_FANG = true,
  EFFECT_COUNTER = true,
  EFFECT_MIRROR_COAT = true,
  EFFECT_OHKO = true,           -- accuracy is computed from the levels
  EFFECT_RETURN = true,
  EFFECT_FRUSTRATION = true,
  EFFECT_MAGNITUDE = true,
  EFFECT_PRESENT = true,
  EFFECT_HIDDEN_POWER = true,   -- type and power come from the DVs
  EFFECT_REVERSAL = true,       -- FLAIL, REVERSAL
  EFFECT_SELFDESTRUCT = true,   -- the user faints; its power is the point
  EFFECT_BEAT_UP = true,        -- one hit per party member
  EFFECT_TRIPLE_KICK = true,    -- power grows each hit
}
-- The move the game falls back on when no other can be used
-- (src/battle/gen2/Battle.lua: Battle.STRUGGLE).
local STRUGGLE = "STRUGGLE"

-- The six base stats, in the cart's BaseData order.  These are field names
-- of the species record, not game ids.
local STAT_KEYS = { "hp", "attack", "defense", "speed", "specialAttack", "specialDefense" }
local STAT_FLOOR = 20
local STAT_CEILING = 255
local WEIGHT_MIN = 0.25

local POWER_FACTOR_MIN, POWER_FACTOR_SPAN = 0.5, 1.0
local POWER_MIN, POWER_MAX = 10, 150
local POWER_ROUND_FROM = 30
local ACCURACY_STEPS = { -15, -10, -5, 0, 5, 10 }
local ACCURACY_FLOOR = 70

local M = {
  id = "stats",
  questions = {
    { key = "stats_base", kind = "yesno", text = "Shuffle POKéMON's\nbase stats?",
      recommended = false, everything = true },
    { key = "stats_base_mode", kind = "choice", onlyIf = "stats_base",
      text = "Reorder the stats\nor reroll them?\vEach keeps its\vtotal either way.",
      options = { { label = "REORDER", value = "reorder" }, { label = "REROLL", value = "reroll" } },
      recommended = "reorder", everything = "reroll" },
    { key = "stats_moves", kind = "yesno", text = "Change attacks'\npower, accuracy\vand type?",
      recommended = false, everything = true },
  },
}
M.STAT_KEYS = STAT_KEYS
M.STAT_FLOOR, M.STAT_CEILING = STAT_FLOOR, STAT_CEILING
M.POWER_MIN, M.POWER_MAX = POWER_MIN, POWER_MAX
M.ACCURACY_FLOOR = ACCURACY_FLOOR

-- ------------------------------------------------------------------ data

local function sortedKeys(set)
  local list = {}
  for key in pairs(set) do list[#list + 1] = key end
  table.sort(list)
  return list
end

-- A species record with all six base stats, as opposed to the other tables
-- pokemon.lua carries at the top level (tutorMoves, tmhmMoves, growthRates).
local function isSpecies(def)
  if type(def) ~= "table" or type(def.baseStats) ~= "table" then return false end
  for _, key in ipairs(STAT_KEYS) do
    if type(def.baseStats[key]) ~= "number" then return false end
  end
  return true
end

-- The cart's percentage of a raw accuracy byte (src/import/RomExtractorGen2.lua).
local function percentOf(raw)
  return math.floor(raw * 100 / 255 + 0.5)
end
-- And back, as the content schema writes it (src/mods/Schemas.lua).
local function rawOf(percent)
  return math.floor(percent * 255 / 100)
end
M.percentOf, M.rawOf = percentOf, rawOf

-- Whether a move's power, accuracy and type may change (see the header).
function M.isChangeable(id, move)
  return type(move) == "table" and id ~= STRUGGLE
    and type(move.power) == "number" and move.power >= 2
    and not KEEP_EFFECTS[move.effect]
end

-- The vanilla copy.  Species: the original baseStats table (restored by
-- reference) and a value copy to build from.  Moves: the four owned fields'
-- values, restored by assignment (nil stays nil).
local function snapshot(data)
  local vanilla = { species = {}, moves = {}, evolutions = {} }
  for species, def in pairs(data.pokemon) do
    if isSpecies(def) then
      local values = {}
      for i, key in ipairs(STAT_KEYS) do values[i] = def.baseStats[key] end
      vanilla.species[species] = { table = def.baseStats, values = values }
      local into = {}
      for _, evo in ipairs(def.evolutions or {}) do
        local target = type(evo) == "table" and (evo.into or evo.species)
        if type(target) == "string" then into[#into + 1] = target end
      end
      vanilla.evolutions[species] = into
    end
  end
  for id, move in pairs(data.moves or {}) do
    if M.isChangeable(id, move) then
      vanilla.moves[id] = { power = move.power, accuracy = move.accuracy,
        accuracyRaw = move.accuracyRaw, type = move.type, effect = move.effect }
    end
  end
  return vanilla
end

-- Evolution families from the vanilla evolution rows.
local function familyKeys(vanilla)
  local parent = {}
  local function find(x)
    while parent[x] ~= x do
      parent[x] = parent[parent[x]]
      x = parent[x]
    end
    return x
  end
  for species in pairs(vanilla.species) do parent[species] = species end
  for _, species in ipairs(sortedKeys(vanilla.species)) do
    for _, into in ipairs(vanilla.evolutions[species]) do
      if parent[into] then
        local a, b = find(species), find(into)
        if a ~= b then
          if a < b then parent[b] = a else parent[a] = b end
        end
      end
    end
  end
  local keys = {}
  for species in pairs(vanilla.species) do keys[species] = find(species) end
  return keys
end

-- ---------------------------------------------------------- base stats

-- One permutation of the six positions per family.
local function familyOrder(ctx, family)
  return ctx.rng("stats_reorder", family):shuffled({ 1, 2, 3, 4, 5, 6 })
end

local function familyWeights(ctx, family)
  local rng = ctx.rng("stats_reroll", family)
  local weights = {}
  for i = 1, #STAT_KEYS do weights[i] = WEIGHT_MIN + rng:next() end
  return weights
end

-- Spread `total` over the six stats by `weights`, each within
-- [floor, STAT_CEILING], summing to exactly `total` (when that is possible).
-- Largest remainder rounding, ties to the earlier stat.
function M.spread(total, weights)
  local count = #weights
  local floor = math.min(STAT_FLOOR, math.floor(total / count))
  local ceiling = STAT_CEILING
  local values, capped = {}, {}
  for i = 1, count do values[i] = floor end
  for _ = 1, count + 1 do
    local fixed, weightSum = 0, 0
    for i = 1, count do
      if capped[i] then fixed = fixed + ceiling else weightSum = weightSum + weights[i] end
    end
    local free = 0
    for i = 1, count do if not capped[i] then free = free + 1 end end
    local remaining = total - fixed - free * floor
    if free == 0 or remaining < 0 then break end
    local fractions, given = {}, 0
    for i = 1, count do
      if not capped[i] then
        local exact = remaining * weights[i] / weightSum
        local whole = math.floor(exact)
        values[i] = floor + whole
        fractions[#fractions + 1] = { i = i, f = exact - whole }
        given = given + whole
      else
        values[i] = ceiling
      end
    end
    table.sort(fractions, function(a, b)
      if a.f ~= b.f then return a.f > b.f end
      return a.i < b.i
    end)
    for k = 1, remaining - given do
      local i = fractions[k].i
      values[i] = values[i] + 1
    end
    local over = false
    for i = 1, count do
      if not capped[i] and values[i] > ceiling then capped[i] = true; over = true end
    end
    if not over then break end
  end
  return values
end

local function newBaseStats(mode, order, weights, values)
  local out = {}
  if mode == "reroll" then
    local total = 0
    for _, v in ipairs(values) do total = total + v end
    local spread = M.spread(total, weights)
    for i, key in ipairs(STAT_KEYS) do out[key] = spread[i] end
  else
    for i, key in ipairs(STAT_KEYS) do out[key] = values[order[i]] end
  end
  return out
end

-- ---------------------------------------------------------------- moves

-- The types a changed move may take: those of the vanilla changeable moves.
local function movePools(vanilla)
  local set = {}
  for _, v in pairs(vanilla.moves) do
    if type(v.type) == "string" then set[v.type] = true end
  end
  return sortedKeys(set)
end

function M.newPower(rng, power)
  local value = power * (POWER_FACTOR_MIN + rng:next() * POWER_FACTOR_SPAN)
  if value >= POWER_ROUND_FROM then
    value = math.floor(value / 5 + 0.5) * 5
  else
    value = math.floor(value + 0.5)
  end
  return math.max(POWER_MIN, math.min(POWER_MAX, value))
end

function M.newAccuracy(rng, percent)
  local step = ACCURACY_STEPS[rng:int(1, #ACCURACY_STEPS)]
  local low = math.min(ACCURACY_FLOOR, percent)
  return math.max(low, math.min(100, percent + step))
end

local function newMove(ctx, id, v, types)
  local rng = ctx.rng("stats_moves", id)
  local out = { power = M.newPower(rng, v.power), accuracy = v.accuracy,
    accuracyRaw = v.accuracyRaw, type = v.type }
  if v.effect ~= "EFFECT_ALWAYS_HIT" and type(v.accuracy) == "number" then
    local percent = M.newAccuracy(rng, v.accuracy)
    if percent ~= v.accuracy then
      out.accuracy = percent
      if v.accuracyRaw ~= nil then out.accuracyRaw = rawOf(percent) end
    end
  end
  if #types > 0 then out.type = rng:pick(types) end
  return out
end

local function writeMove(move, values)
  move.power, move.accuracy, move.accuracyRaw, move.type =
    values.power, values.accuracy, values.accuracyRaw, values.type
end

-- ------------------------------------------------------------- the build

-- Rebuild (or restore) base stats and move data for the save that just
-- became known.  `state` holds the vanilla copy between calls.
function M.apply(data, ctx, state)
  if type(data) ~= "table" or type(data.pokemon) ~= "table" then return "no data.pokemon" end
  if not state.vanilla then
    state.vanilla = snapshot(data)
    state.families = familyKeys(state.vanilla)
    state.types = movePools(state.vanilla)
  end
  local vanilla, families = state.vanilla, state.families
  local active = ctx.active()
  local statsOn = active and ctx.option("stats_base") == true
  local mode = ctx.option("stats_base_mode") == "reroll" and "reroll" or "reorder"
  local movesOn = active and ctx.option("stats_moves") == true

  local changedSpecies = 0
  local orders, weights = {}, {}
  for _, species in ipairs(sortedKeys(vanilla.species)) do
    local v, def = vanilla.species[species], data.pokemon[species]
    if type(def) == "table" then
      if statsOn then
        local family = families[species]
        if mode == "reroll" then
          weights[family] = weights[family] or familyWeights(ctx, family)
        else
          orders[family] = orders[family] or familyOrder(ctx, family)
        end
        def.baseStats = newBaseStats(mode, orders[family], weights[family], v.values)
        changedSpecies = changedSpecies + 1
      else
        def.baseStats = v.table
      end
    end
  end

  local changedMoves = 0
  local moves = data.moves or {}
  for _, id in ipairs(sortedKeys(vanilla.moves)) do
    local move = moves[id]
    if type(move) == "table" then
      if movesOn then
        writeMove(move, newMove(ctx, id, vanilla.moves[id], state.types))
        changedMoves = changedMoves + 1
      else
        writeMove(move, vanilla.moves[id])
      end
    end
  end
  return ("base stats %s (%d), moves %s (%d)"):format(
    statsOn and mode or "vanilla", changedSpecies, movesOn and "changed" or "vanilla", changedMoves)
end

function M.install(mod, ctx)
  local state = {}
  ctx.onSave(function()
    local game = mod and mod.game
    local data = game and game.data
    if not data then
      ctx.log("stats: no game data yet; nothing changed")
      return
    end
    -- A different data table (a new boot of the dataset) needs a new copy.
    if state.data ~= data then state.data, state.vanilla = data, nil end
    ctx.log("stats: %s", M.apply(data, ctx, state))
  end)
end

return M
