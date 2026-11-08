-- Crystal randomizer: wild POKéMON.
--
-- What changes, and where it is read:
--
--   grass (MORN, DAY and NITE lists), surfing, the Dunsparce and Yanma swarm
--   lists, headbutt trees, ROCK SMASH rocks and the Bug Catching Contest are
--   the game's own tables in data.gen2Encounters.  They are rewritten in place
--   when a randomized save becomes known and put back exactly when it does not
--   (ctx.onSave).  Rewriting the tables rather than hooking the roll is
--   deliberate: everything else that reads them -- the POKéDEX area page
--   (src/core/gen2/Nests.lua), the Pokégear, mod.world:effectiveEncounters and
--   so any route summary a screen reader speaks -- then tells the player the
--   truth about the randomized world, and the headbutt and ROCK SMASH paths,
--   which bypass the encounter hooks (docs/mod-api-gen2-compat.md, "partial
--   coverages"), are reached at all.
--
--   fishing (OLD, GOOD and SUPER ROD, both halves of the time-of-day rows and
--   the Qwilfish and Remoraid swarm groups) goes through the
--   encounter.fishing hook instead, because a fish group is shared by many
--   maps and the hook knows the map, so a rod on Route 30 and a rod on Route
--   31 can give different fish.
--
--   Not covered: the three roaming beasts (Roamers.checkEncounter has no hook
--   and its roster is copied into the save at the Burned Tower, so they stay
--   RAIKOU, ENTEI and SUICUNE), and single static encounters a script gives
--   (SUDOWOODO, the red GYARADOS, LAPRAS, the legendary birds and so on),
--   which are not wild tables.
--
-- The mapping.  Within one "scope" -- a map for grass, surfing, swarms and
-- fishing; a tree set for headbutt and ROCK SMASH, because the game shares one
-- tree list between many maps; the contest for the park -- each original
-- species becomes one replacement, the same at every time of day, in every
-- slot and with every rod.  So "on Route 29, PIDGEY became ZUBAT" stays true
-- all game, which is easier to learn and to talk about than a different
-- species in each slot.  Two different originals in one scope get different
-- replacements while the pool allows it.  Each choice comes from
-- ctx.rng("wild", scope, species), so it depends only on the seed, the scope
-- and the species, never on the order anything is asked.  Levels are left as
-- they are.
--
-- The pool is derived from the game's data, never typed in: every species
-- with a whole positive index, complete base stats and a name.  Left out of
-- the pool are the species the game marks genderless and unable to breed
-- (both egg groups EGG_NONE, gender ratio 255): in Crystal that is exactly
-- the eleven legendaries and UNOWN.  The legendaries stay special and the
-- roamers stay unique; UNOWN is also never replaced, because the Ruins of
-- Alph chambers give no encounter until a puzzle is solved, decided by the
-- species UNOWN itself (World:tryWildEncounter), and the UNOWN letters belong
-- to that puzzle.

local Encounter = require("src.battle.gen2.Encounter")

local WILD_KEY, SIMILAR_KEY = "wild", "wild_similar"

-- With "keep them about as strong", a replacement's base stat total is
-- within this fraction of the original's, widened step by step until at
-- least MIN_CANDIDATES species qualify.
local BAND_START, BAND_STEP, MIN_CANDIDATES = 0.10, 0.05, 8

local GENDER_UNKNOWN, NO_EGGS_RAW = 255, 255

local STAT_KEYS = { "hp", "attack", "defense", "speed", "specialAttack", "specialDefense" }

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function baseStatTotal(def)
  local stats = type(def) == "table" and def.baseStats
  if type(stats) ~= "table" then return nil end
  local total = 0
  for _, key in ipairs(STAT_KEYS) do
    local value = stats[key]
    if type(value) ~= "number" or value <= 0 then return nil end
    total = total + value
  end
  return total
end

-- The same test the cart's breeding code makes (Breeding.isNoEggs), plus the
-- genderless ratio, without requiring the breeding module.
local function isLegendaryShape(def)
  if def.genderRatio ~= GENDER_UNKNOWN then return false end
  if type(def.eggGroupsRaw) == "number" then return def.eggGroupsRaw == NO_EGGS_RAW end
  local groups = def.eggGroups
  return type(groups) == "table" and groups[1] == "EGG_NONE" and groups[2] == "EGG_NONE"
end

-- A species id the game can really build: a record with a whole positive
-- index, complete base stats and a name.
local function realSpecies(pokemon, id)
  local def = type(id) == "string" and pokemon[id]
  if type(def) ~= "table" then return nil end
  local index = def.index
  if type(index) ~= "number" or index < 1 or index % 1 ~= 0 then return nil end
  if not baseStatTotal(def) then return nil end
  if type(def.name) ~= "string" or def.name == "" then return nil end
  return def
end

-- Sorted by id, so the pool's order never depends on pairs().
local function buildPool(pokemon)
  local pool = {}
  for _, id in ipairs(sortedKeys(pokemon)) do
    local def = realSpecies(pokemon, id)
    if def and not isLegendaryShape(def) then
      pool[#pool + 1] = { id = id, bst = baseStatTotal(def) }
    end
  end
  return pool
end

-- An original that is kept as it is: not a real species, or one of the
-- genderless no-egg species (UNOWN in the wild tables).
local function keepAsIs(pokemon, id)
  local def = realSpecies(pokemon, id)
  return def == nil or isLegendaryShape(def)
end

local function candidatesFor(pool, original, originalBst, similar, taken)
  local function collect(tolerance, honourTaken)
    local out = {}
    for _, entry in ipairs(pool) do
      if entry.id ~= original and not (honourTaken and taken[entry.id])
          and (not tolerance or math.abs(entry.bst - originalBst) <= tolerance) then
        out[#out + 1] = entry.id
      end
    end
    return out
  end
  for _, honourTaken in ipairs({ true, false }) do
    if similar then
      local fraction = BAND_START
      while true do
        local list = collect(originalBst * fraction, honourTaken)
        if #list >= MIN_CANDIDATES or fraction >= 1 then
          if #list > 0 then return list end
          break
        end
        fraction = fraction + BAND_STEP
      end
    else
      local list = collect(nil, honourTaken)
      if #list > 0 then return list end
    end
  end
  return {}
end

-- The replacements for one scope's species, chosen in sorted order so the
-- distinctness rule is order-free.  `mapping` may already hold earlier picks
-- for this scope; their replacements count as taken.
local function assign(state, scope, species)
  local mapping = state.byScope[scope] or {}
  state.byScope[scope] = mapping
  local taken = {}
  for _, replacement in pairs(mapping) do taken[replacement] = true end
  local list = {}
  for id in pairs(species) do
    if mapping[id] == nil then list[#list + 1] = id end
  end
  table.sort(list)
  for _, id in ipairs(list) do
    if keepAsIs(state.pokemon, id) then
      mapping[id] = id
    else
      local candidates = candidatesFor(state.pool, id,
        baseStatTotal(state.pokemon[id]), state.similar, taken)
      local pick = state.ctx.rng("wild", scope, id):pick(candidates) or id
      mapping[id] = pick
      taken[pick] = true
    end
  end
  return mapping
end

-- ---------------------------------------------------------------- the tables

-- Every slot row the rewrite touches, as { scope, row } pairs, from the
-- current encounters table.
local function collectRows(encounters)
  local rows, seen = {}, {}
  local function add(scope, row)
    if type(row) == "table" and type(row.species) == "string" and not seen[row] then
      seen[row] = true
      rows[#rows + 1] = { scope = scope, row = row }
    end
  end
  for _, kind in ipairs({ "grass", "swarmGrass" }) do
    for _, mapId in ipairs(sortedKeys(encounters[kind] or {})) do
      local entry = encounters[kind][mapId]
      local slots = type(entry) == "table" and entry.slots
      if type(slots) == "table" then
        for _, tod in ipairs(sortedKeys(slots)) do
          for _, row in ipairs(slots[tod]) do add(mapId, row) end
        end
      end
    end
  end
  for _, kind in ipairs({ "water", "swarmWater" }) do
    for _, mapId in ipairs(sortedKeys(encounters[kind] or {})) do
      local entry = encounters[kind][mapId]
      if type(entry) == "table" and type(entry.slots) == "table" then
        for _, row in ipairs(entry.slots) do add(mapId, row) end
      end
    end
  end
  for _, setName in ipairs(sortedKeys(encounters.treeSets or {})) do
    local set = encounters.treeSets[setName]
    if type(set) == "table" then
      for _, half in ipairs({ "common", "rare" }) do
        for _, row in ipairs(set[half] or {}) do add("tree:" .. setName, row) end
      end
    end
  end
  for _, row in ipairs(encounters.bugContest or {}) do add("bug_contest", row) end
  return rows
end

-- The species a fish group can produce, rows, day/nite halves and the shared
-- time-of-day rows alike.
local function fishSpecies(encounters, groupName, into)
  local group = encounters.fishGroups and encounters.fishGroups[groupName]
  if type(group) ~= "table" then return end
  local function add(slot)
    if type(slot) == "table" and type(slot.species) == "string"
        and slot.species ~= "NO_ITEM" then
      into[slot.species] = true
    end
  end
  for _, rod in ipairs({ "old", "good", "super" }) do
    for _, row in ipairs(group[rod] or {}) do
      add(row)
      add(row.day)
      add(row.nite)
      local timed = row.timeGroup and encounters.timeFishGroups
        and encounters.timeFishGroups[row.timeGroup]
      if type(timed) == "table" then
        add(timed.day)
        add(timed.nite)
      end
    end
  end
end

-- Every fish group a map's rod can reach, the swarm swaps included
-- (Encounter.fishGroupFor is the engine's own GetFishGroupIndex).
local function mapFishSpecies(encounters, mapDef, into)
  local base = type(mapDef) == "table" and mapDef.fishGroup
  if type(base) ~= "string" or base == "FISHGROUP_NONE" then return end
  for _, swarm in ipairs({ Encounter.FISHSWARM_NONE, Encounter.FISHSWARM_QWILFISH,
      Encounter.FISHSWARM_REMORAID }) do
    fishSpecies(encounters, Encounter.fishGroupFor(encounters, base, swarm), into)
  end
end

-- ---------------------------------------------------------------- the module

local Wild = {
  id = "wild",
  questions = {
    { key = WILD_KEY, kind = "yesno", text = "Shuffle wild\nPOKéMON?" },
    { key = SIMILAR_KEY, kind = "yesno", onlyIf = WILD_KEY, text = "Keep them about\nas strong?" },
  },
}

-- Module state, one per installed copy.
local function newState() return { applied = nil, byScope = nil } end

-- Put every rewritten row back to the species it had.
local function restore(state)
  local applied = state.applied
  if applied then
    for i = #applied.rows, 1, -1 do
      local entry = applied.rows[i]
      entry.row.species = entry.original
    end
  end
  state.applied, state.byScope, state.pokemon, state.pool = nil, nil, nil, nil
  state.ctx.shared.wild = nil
end

local function apply(state, data)
  local encounters = data.gen2Encounters
  local pokemon = data.pokemon
  if type(encounters) ~= "table" or type(pokemon) ~= "table" then
    state.ctx.log("wild: no encounter or species data; wild POKéMON left as they are")
    return
  end
  state.pokemon, state.pool = pokemon, buildPool(pokemon)
  state.similar = state.ctx.option(SIMILAR_KEY) == true
  state.byScope = {}
  state.encounters = encounters

  local rows = collectRows(encounters)
  -- Gather each scope's species first (tables plus that map's fishing), so
  -- the distinctness rule sees the whole scope at once.
  local scopes = {}
  for _, entry in ipairs(rows) do
    scopes[entry.scope] = scopes[entry.scope] or {}
    scopes[entry.scope][entry.row.species] = true
  end
  local maps = data.gen2Maps
  if type(maps) == "table" then
    for _, mapId in ipairs(sortedKeys(maps)) do
      local fish = {}
      mapFishSpecies(encounters, maps[mapId], fish)
      if next(fish) then
        scopes[mapId] = scopes[mapId] or {}
        for id in pairs(fish) do scopes[mapId][id] = true end
      end
    end
  end
  for _, scope in ipairs(sortedKeys(scopes)) do assign(state, scope, scopes[scope]) end

  local applied = { rows = {} }
  local changed = 0
  for _, entry in ipairs(rows) do
    local original = entry.row.species
    applied.rows[#applied.rows + 1] = { row = entry.row, original = original }
    local replacement = state.byScope[entry.scope][original]
    if replacement and replacement ~= original then
      entry.row.species = replacement
      changed = changed + 1
    end
  end
  state.applied = applied
  state.ctx.shared.wild = state.byScope
  state.ctx.log("wild: %d of %d wild slots changed across %d scopes (%s)",
    changed, #rows, #sortedKeys(scopes), state.similar and "similar strength" or "any strength")
end

-- The replacement a rod gives on `mapId`.  A species the precomputed scope
-- did not know (a mod's fish group, a map with no header row) gets its own
-- pick, which depends only on the seed, the map and the species.
local function fishReplacement(state, mapId, species)
  if not (state.byScope and state.pokemon and mapId) then return nil end
  local mapping = state.byScope[mapId]
  if not (mapping and mapping[species]) then
    mapping = assign(state, mapId, { [species] = true })
  end
  return mapping[species]
end

function Wild.install(mod, ctx)
  local state = newState()
  state.ctx = ctx

  ctx.onSave(function(active)
    restore(state)
    if not (active and ctx.option(WILD_KEY) == true) then return end
    local game = mod.game
    local data = game and game.data
    if type(data) ~= "table" then
      ctx.log("wild: no game data yet; wild POKéMON left as they are")
      return
    end
    apply(state, data)
  end)

  if mod.hooks and mod.hooks.wrap then
    mod.hooks:wrap("encounter.fishing", function(nextFn, rod, mapId, candidates, hookCtx, ...)
      local roll = nextFn(rod, mapId, candidates, hookCtx, ...)
      if type(roll) ~= "table" or type(roll.species) ~= "string" then return roll end
      if not (state.applied and ctx.active() and ctx.option(WILD_KEY) == true) then
        return roll
      end
      local replacement = fishReplacement(state, mapId, roll.species)
      if not replacement or replacement == roll.species then return roll end
      local out = {}
      for k, v in pairs(roll) do out[k] = v end
      out.species = replacement
      return out
    end)
  end
end

return Wild
