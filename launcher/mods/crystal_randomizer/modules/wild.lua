-- Crystal randomizer: wild POKéMON.
--
-- What changes, and where it is read:
--
--   grass (MORN, DAY and NITE lists), surfing, the Dunsparce and Yanma swarm
--   lists, headbutt trees, ROCK SMASH rocks and the Bug Catching Contest are
--   the game's own tables in data.gen2Encounters.  They are rewritten in place
--   (species, and levels when a level percentage is chosen) when a randomized
--   save becomes known and put back exactly when it does not (ctx.onSave).
--   Rewriting the tables rather than hooking the roll is deliberate:
--   everything else that reads them -- the POKéDEX area page
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
--   RAIKOU, ENTEI and SUICUNE, at their own levels), and single static
--   encounters a script gives (SUDOWOODO, the red GYARADOS, LAPRAS, the
--   legendary birds and so on), which are not wild tables.
--
-- Places.  A "scope" is a map for grass, surfing, swarms and fishing; a tree
-- set for headbutt and ROCK SMASH, because the game shares one tree list
-- between many maps; the contest for the park.  Each scope has a land half
-- (grass, swarms, trees, rocks, contest) and a water half (surfing, fishing).
--
-- Modes (the "wild_mode" answer):
--
--   route  Within one scope each original species becomes one replacement,
--          the same at every time of day, in every slot and with every rod,
--          so "on Route 29, PIDGEY became ZUBAT" stays true all game.  Two
--          originals in one scope get different replacements while the pool
--          allows it.
--   game   One replacement per original for the whole game, and each
--          replacement is used for one original only (global one-to-one).
--   slot   Every table slot, and every rod row (rod, species, level) on a
--          map, is chosen on its own.
--
-- Rules every mode keeps:
--
--   - Never the original itself, and never a species the vanilla game
--     already has in that scope: its grass, surfing, swarms and fishing, plus
--     the map's headbutt and ROCK SMASH sets; for a tree set, every map that
--     uses it; for the contest, the National Park's own grass.  In "game"
--     mode the replacement avoids the vanilla species of every scope the
--     original appears in.  Seed 876506 showed why: with "about as strong",
--     early routes swapped common early species for each other.  This rule
--     is never relaxed.
--   - "Keep them about as strong" (wild_similar): a replacement's base stat
--     total is within 10% of the original's, widened in steps of 5% until
--     at least MIN_CANDIDATES species qualify (MIN_THEMED when a type theme
--     applies; or all that are left, if fewer).  How often a band had to widen is logged and kept in
--     ctx.shared.wild.report.
--   - "Keep route types" (wild_theme): on water (surfing and fishing) the
--     replacement must be WATER-typed, as long as the game has that type.  On
--     land, a place's theme is every type carried by at least a third of its
--     distinct vanilla species (both types of a dual-typed species count); if
--     no type reaches a third, the most common types.  On land the
--     original's own types also count, so a FIRE species on a NORMAL route
--     may become another FIRE species.  A replacement must fit the theme
--     of every place it fills; if none can (an
--     original spread over differently themed places in "game" mode), the
--     place where it has the most slots decides; if still none, the theme is
--     dropped for that pick.  Types are read from the current data at switch
--     time, so with shuffled types (the pokemon module runs first) the theme
--     follows the types the player actually meets.
--   - "Catch 'em all" (wild_catch_all): after the picks, every pool species
--     no slot uses is moved into a place whose current replacement is also
--     used elsewhere, so nothing is lost.  The no-reuse rule, the type theme
--     and one-to-one are kept; the strength band widens step by step for the
--     species being placed when it must.  In "game" mode every replacement is
--     already used once, so coverage is the number of originals.
--   - Levels (wild_level, a percentage): 100 leaves them alone; other values
--     scale every table level and every fishing roll, rounded, clamped to 2
--     to 100.  Asked whether or not wild POKéMON are shuffled.
--
-- Every pick comes from ctx.rng("wild", ...) with fixed keys and is made in
-- a fixed, seed-shuffled order, never in the order anything is asked.
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
--
-- A save made before version 2 (wild = YES but no wild_mode answer) keeps the
-- round-one picks exactly (legacyAssign), so a run in progress does not
-- change under the player.

local Encounter = require("src.battle.gen2.Encounter")

local WILD_KEY, SIMILAR_KEY = "wild", "wild_similar"
local MODE_KEY, CATCH_KEY, THEME_KEY, LEVEL_KEY = "wild_mode", "wild_catch_all", "wild_theme", "wild_level"

-- With a type theme the pool is far smaller, so fewer candidates are
-- enough before the band stops widening.
local BAND_START, BAND_STEP, MIN_CANDIDATES, MIN_THEMED = 0.10, 0.05, 8, 3
local LEVEL_MIN, LEVEL_MAX = 2, 100
local WATER_TYPE = "WATER"
-- The contest scope also avoids this map's vanilla grass species.
local CONTEST_MAP = "NATIONAL_PARK"

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

local function typesOf(def)
  local out = {}
  if type(def) == "table" and type(def.types) == "table" then
    for _, t in ipairs(def.types) do
      if type(t) == "string" then out[t] = true end
    end
  end
  return out
end

-- Sorted by id, so the pool's order never depends on pairs().
local function buildPool(pokemon)
  local pool = {}
  for _, id in ipairs(sortedKeys(pokemon)) do
    local def = realSpecies(pokemon, id)
    if def and not isLegendaryShape(def) then
      pool[#pool + 1] = { id = id, bst = baseStatTotal(def), types = typesOf(def) }
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

local function scaleLevel(level, percent)
  if type(level) ~= "number" or percent == 100 then return level end
  local scaled = math.floor(level * percent / 100 + 0.5)
  return math.max(LEVEL_MIN, math.min(LEVEL_MAX, scaled))
end

-- ------------------------------------------------- round one (legacy saves)

local function legacyCandidates(pool, original, originalBst, similar, taken)
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

-- Round one's per-scope picks, unchanged, for saves made before version 2.
local function legacyAssign(state, scope, species)
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
      local candidates = legacyCandidates(state.pool, id,
        baseStatTotal(state.pokemon[id]), state.similar, taken)
      local pick = state.ctx.rng("wild", scope, id):pick(candidates) or id
      mapping[id] = pick
      taken[pick] = true
    end
  end
  return mapping
end

-- ---------------------------------------------------------------- the tables

-- Every slot row the rewrite touches, from the current encounters table:
-- { scope, row, habitat, slot } where slot names the row for "slot" mode.
local function collectRows(encounters)
  local rows, seen = {}, {}
  local function add(scope, row, habitat, slot)
    if type(row) == "table" and type(row.species) == "string" and not seen[row] then
      seen[row] = true
      rows[#rows + 1] = { scope = scope, row = row, habitat = habitat, slot = slot }
    end
  end
  for _, kind in ipairs({ "grass", "swarmGrass" }) do
    for _, mapId in ipairs(sortedKeys(encounters[kind] or {})) do
      local entry = encounters[kind][mapId]
      local slots = type(entry) == "table" and entry.slots
      if type(slots) == "table" then
        for _, tod in ipairs(sortedKeys(slots)) do
          for i, row in ipairs(slots[tod]) do
            add(mapId, row, "land", table.concat({ mapId, kind, tod, i }, "|"))
          end
        end
      end
    end
  end
  for _, kind in ipairs({ "water", "swarmWater" }) do
    for _, mapId in ipairs(sortedKeys(encounters[kind] or {})) do
      local entry = encounters[kind][mapId]
      if type(entry) == "table" and type(entry.slots) == "table" then
        for i, row in ipairs(entry.slots) do
          add(mapId, row, "water", table.concat({ mapId, kind, i }, "|"))
        end
      end
    end
  end
  for _, setName in ipairs(sortedKeys(encounters.treeSets or {})) do
    local set = encounters.treeSets[setName]
    if type(set) == "table" then
      for _, half in ipairs({ "common", "rare" }) do
        for i, row in ipairs(set[half] or {}) do
          add("tree:" .. setName, row, "land", table.concat({ "tree:" .. setName, half, i }, "|"))
        end
      end
    end
  end
  for i, row in ipairs(encounters.bugContest or {}) do
    add("bug_contest", row, "land", "bug_contest|" .. i)
  end
  return rows
end

local ROD_KEYS = { "old", "good", "super" }
local ROD_KEY = { OLD_ROD = "old", GOOD_ROD = "good", SUPER_ROD = "super" }

local function fishSlotKey(mapId, rod, species, level)
  return table.concat({ mapId, "fish", rod, species, tostring(level) }, "|")
end

-- The (rod, species, level) rows a fish group can produce, rows, day/nite
-- halves and the shared time-of-day rows alike.
local function fishRows(encounters, groupName, into)
  local group = encounters.fishGroups and encounters.fishGroups[groupName]
  if type(group) ~= "table" then return end
  for _, rod in ipairs(ROD_KEYS) do
    local function add(slot)
      if type(slot) == "table" and type(slot.species) == "string"
          and slot.species ~= "NO_ITEM" then
        into[#into + 1] = { rod = rod, species = slot.species, level = slot.level }
      end
    end
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

-- Every fish row a map's rod can reach, the swarm swaps included
-- (Encounter.fishGroupFor is the engine's own GetFishGroupIndex).
local function mapFishRows(encounters, mapDef, into)
  local base = type(mapDef) == "table" and mapDef.fishGroup
  if type(base) ~= "string" or base == "FISHGROUP_NONE" then return end
  local seenGroup = {}
  for _, swarm in ipairs({ Encounter.FISHSWARM_NONE, Encounter.FISHSWARM_QWILFISH,
      Encounter.FISHSWARM_REMORAID }) do
    local group = Encounter.fishGroupFor(encounters, base, swarm)
    if group and not seenGroup[group] then
      seenGroup[group] = true
      fishRows(encounters, group, into)
    end
  end
end

-- ------------------------------------------------------------ the places

-- Everything the picks need to know about the vanilla world, gathered once
-- per switch from the current (vanilla) tables.
--   scopes[scope] = { species = set, habitats = { land/water = { [id] = slots } } }
--   exclude[scope] = set of species never used as a replacement there
--   fish[mapId] = list of { rod, species, level }
local function survey(encounters, maps, rows)
  local scopes = {}
  local function note(scope, habitat, species)
    local s = scopes[scope]
    if not s then
      s = { species = {}, habitats = { land = {}, water = {} } }
      scopes[scope] = s
    end
    s.species[species] = true
    s.habitats[habitat][species] = (s.habitats[habitat][species] or 0) + 1
  end
  for _, entry in ipairs(rows) do note(entry.scope, entry.habitat, entry.row.species) end
  local fish = {}
  if type(maps) == "table" then
    for _, mapId in ipairs(sortedKeys(maps)) do
      local list = {}
      mapFishRows(encounters, maps[mapId], list)
      if #list > 0 then
        fish[mapId] = list
        for _, f in ipairs(list) do note(mapId, "water", f.species) end
      end
    end
  end

  local exclude = {}
  local function union(into, set) for id in pairs(set or {}) do into[id] = true end end
  local setMaps = {}
  for _, kind in ipairs({ "trees", "rocks" }) do
    for _, mapId in ipairs(sortedKeys(encounters[kind] or {})) do
      local setName = encounters[kind][mapId]
      if type(setName) == "string" then
        local scope = "tree:" .. setName
        setMaps[scope] = setMaps[scope] or {}
        setMaps[scope][mapId] = true
      end
    end
  end
  for scope, s in pairs(scopes) do
    local ex = {}
    union(ex, s.species)
    exclude[scope] = ex
  end
  for _, kind in ipairs({ "trees", "rocks" }) do
    for mapId, setName in pairs(encounters[kind] or {}) do
      local tree = scopes["tree:" .. tostring(setName)]
      if exclude[mapId] and tree then union(exclude[mapId], tree.species) end
    end
  end
  for scope, mapSet in pairs(setMaps) do
    if exclude[scope] then
      for mapId in pairs(mapSet) do
        if scopes[mapId] then union(exclude[scope], scopes[mapId].species) end
      end
    end
  end
  if exclude.bug_contest and scopes[CONTEST_MAP] then
    union(exclude.bug_contest, scopes[CONTEST_MAP].species)
  end
  return scopes, exclude, fish
end

-- A place's type theme (see the header).  `hasWater` is whether the game's
-- data has a WATER type at all.
local function placeTheme(pokemon, habitatSpecies, habitat, hasWater)
  if habitat == "water" and hasWater then return { [WATER_TYPE] = true } end
  local counts, n = {}, 0
  for id in pairs(habitatSpecies) do
    local def = realSpecies(pokemon, id)
    if def then
      n = n + 1
      for t in pairs(typesOf(def)) do counts[t] = (counts[t] or 0) + 1 end
    end
  end
  local theme, best = {}, 0
  for t, c in pairs(counts) do
    if c * 3 >= n then theme[t] = true end
    best = math.max(best, c)
  end
  if next(theme) == nil then
    for t, c in pairs(counts) do
      if c == best then theme[t] = true end
    end
  end
  return theme
end

local function sharesType(types, theme)
  for t in pairs(types) do
    if theme[t] then return true end
  end
  return false
end

-- --------------------------------------------------------- the positions

-- A position is one thing to pick a replacement for:
--   { key, original, bst, group, exclude = set, places = { { theme, weight } } }
-- `group` positions must differ from each other while the pool allows.
local function placeList(state, scope, habitats)
  local list = {}
  for _, habitat in ipairs({ "land", "water" }) do
    local weight = habitats[habitat]
    if weight and weight > 0 then
      list[#list + 1] = { scope = scope, habitat = habitat, weight = weight,
        theme = state.themes[scope] and state.themes[scope][habitat] or {} }
    end
  end
  return list
end

local function newPosition(state, key, original, group, exclude, places)
  local ex = { [original] = true }
  for id in pairs(exclude or {}) do ex[id] = true end
  return { key = key, original = original, bst = baseStatTotal(state.pokemon[original]),
    types = typesOf(state.pokemon[original]), group = group, exclude = ex, places = places }
end

local function buildPositions(state, rows)
  local positions = {}
  local scopes = state.scopes
  if state.mode == "route" then
    for _, scope in ipairs(sortedKeys(scopes)) do
      local s = scopes[scope]
      for _, id in ipairs(sortedKeys(s.species)) do
        if not keepAsIs(state.pokemon, id) then
          positions[#positions + 1] = newPosition(state, scope .. "|" .. id, id, scope,
            state.exclude[scope], placeList(state, scope,
              { land = s.habitats.land[id], water = s.habitats.water[id] }))
        end
      end
    end
  elseif state.mode == "game" then
    local byOriginal = {}
    for _, scope in ipairs(sortedKeys(scopes)) do
      local s = scopes[scope]
      for id in pairs(s.species) do
        if not keepAsIs(state.pokemon, id) then
          local o = byOriginal[id] or { exclude = {}, places = {} }
          byOriginal[id] = o
          for ex in pairs(state.exclude[scope]) do o.exclude[ex] = true end
          for _, place in ipairs(placeList(state, scope,
              { land = s.habitats.land[id], water = s.habitats.water[id] })) do
            o.places[#o.places + 1] = place
          end
        end
      end
    end
    for _, id in ipairs(sortedKeys(byOriginal)) do
      local o = byOriginal[id]
      positions[#positions + 1] = newPosition(state, "game|" .. id, id, "game", o.exclude, o.places)
    end
  else -- slot
    for _, entry in ipairs(rows) do
      local id = entry.row.species
      if not keepAsIs(state.pokemon, id) then
        positions[#positions + 1] = newPosition(state, entry.slot, id, nil,
          state.exclude[entry.scope], placeList(state, entry.scope, { [entry.habitat] = 1 }))
      end
    end
    for _, mapId in ipairs(sortedKeys(state.fish)) do
      local seen = {}
      for _, f in ipairs(state.fish[mapId]) do
        local key = fishSlotKey(mapId, f.rod, f.species, f.level)
        if not seen[key] and not keepAsIs(state.pokemon, f.species) then
          seen[key] = true
          positions[#positions + 1] = newPosition(state, key, f.species, nil,
            state.exclude[mapId], placeList(state, mapId, { water = 1 }))
        end
      end
    end
  end
  return positions
end

-- The place with the most slots (ties: the first in scope/habitat order).
local function mainPlace(pos)
  local best
  for _, place in ipairs(pos.places) do
    if not best or place.weight > best.weight then best = place end
  end
  return best
end

-- Whether `entry` satisfies the theme at `level`: "all" places, the "main"
-- one, or "none".
-- On land the original's own types count as part of the theme, so a FIRE
-- species on a NORMAL route can still become another FIRE species; on water
-- only the water theme counts.
local function fitsPlace(entry, pos, place)
  if sharesType(entry.types, place.theme) then return true end
  return place.habitat ~= "water" and sharesType(entry.types, pos.types)
end

local function themeOk(entry, pos, level)
  if level == "none" then return true end
  if level == "main" then
    local place = mainPlace(pos)
    return place == nil or fitsPlace(entry, pos, place)
  end
  for _, place in ipairs(pos.places) do
    if not fitsPlace(entry, pos, place) then return false end
  end
  return true
end

local function bandDiff(entry, pos)
  return math.abs(entry.bst - pos.bst) / pos.bst
end

-- The candidates for a position, and how much was relaxed to find them:
-- { list, fraction (band used, or nil), themeLevel, sharedTaken }.
local function candidatesFor(state, pos, taken)
  local themeLevels = state.theme and { "all", "main", "none" } or { "none" }
  for _, honourTaken in ipairs({ true, false }) do
    for _, level in ipairs(themeLevels) do
      local base = {}
      for _, entry in ipairs(state.pool) do
        if not pos.exclude[entry.id] and not (honourTaken and taken and taken[entry.id])
            and themeOk(entry, pos, level) then
          base[#base + 1] = entry
        end
      end
      if #base > 0 then
        local result = { themeLevel = level, sharedTaken = not honourTaken }
        if state.similar then
          local need = math.min(level == "none" and MIN_CANDIDATES or MIN_THEMED, #base)
          local fraction = BAND_START
          while true do
            local list = {}
            for _, entry in ipairs(base) do
              if bandDiff(entry, pos) <= fraction + 1e-9 then list[#list + 1] = entry.id end
            end
            if #list >= need then
              result.list, result.fraction = list, fraction
              return result
            end
            fraction = fraction + BAND_STEP
          end
        end
        local list = {}
        for i, entry in ipairs(base) do list[i] = entry.id end
        result.list = list
        return result
      end
    end
  end
  return { list = {}, themeLevel = "none", sharedTaken = true }
end

local function newReport(state)
  return { mode = state.mode, positions = 0, widened = 0, worstBand = 0, over25 = 0, over50 = 0,
    themeMain = 0, themeDropped = 0, sharedTaken = 0, kept = 0,
    catchMoved = 0, catchWidened = 0, catchUnplaced = {}, poolSize = #state.pool,
    covered = 0, coveredBefore = 0, missing = {} }
end

local function noteRelaxation(report, result)
  if result.fraction then
    if result.fraction > BAND_START + 1e-9 then report.widened = report.widened + 1 end
    if result.fraction > 0.25 + 1e-9 then report.over25 = report.over25 + 1 end
    if result.fraction > 0.50 + 1e-9 then report.over50 = report.over50 + 1 end
    report.worstBand = math.max(report.worstBand, result.fraction)
  end
  if result.themeLevel == "main" then report.themeMain = report.themeMain + 1 end
  if result.themeLevel == "none" and result.relaxedTheme then
    report.themeDropped = report.themeDropped + 1
  end
  if result.sharedTaken then report.sharedTaken = report.sharedTaken + 1 end
end

local function assignAll(state, positions)
  local report = state.report
  local takenByGroup = {}
  -- A fixed order, shuffled by the seed so no species is always picked last.
  local order = state.ctx.rng("wild", "order", state.mode):shuffled(positions)
  for _, pos in ipairs(order) do
    local taken = pos.group and takenByGroup[pos.group]
    if pos.group and not taken then
      taken = {}
      takenByGroup[pos.group] = taken
    end
    local result = candidatesFor(state, pos, taken)
    result.relaxedTheme = state.theme
    pos.pick = state.ctx.rng("wild", pos.key):pick(result.list)
    if not pos.pick then
      pos.pick = pos.original
      report.kept = report.kept + 1
    else
      pos.fraction, pos.themeLevel = result.fraction, result.themeLevel
      noteRelaxation(report, result)
    end
    if taken then taken[pos.pick] = true end
    report.positions = report.positions + 1
  end
  state.takenByGroup = takenByGroup
end

local function usageOf(positions)
  local usage = {}
  for _, pos in ipairs(positions) do usage[pos.pick] = (usage[pos.pick] or 0) + 1 end
  return usage
end

local function countCovered(state, usage)
  local covered, missing = 0, {}
  for _, entry in ipairs(state.pool) do
    if usage[entry.id] then covered = covered + 1 else missing[#missing + 1] = entry.id end
  end
  return covered, missing
end

-- Catch 'em all: place every unused pool species (see the header).
local function catchAll(state, positions)
  local report = state.report
  local usage = usageOf(positions)
  local _, missing = countCovered(state, usage)
  local byId = {}
  for _, entry in ipairs(state.pool) do byId[entry.id] = entry end
  local sorted = {}
  for i, pos in ipairs(positions) do sorted[i] = pos end
  table.sort(sorted, function(a, b) return a.key < b.key end)
  for _, id in ipairs(state.ctx.rng("wild", "catch", state.mode):shuffled(missing)) do
    local entry = byId[id]
    local eligible = {}
    for _, pos in ipairs(sorted) do
      local taken = pos.group and state.takenByGroup[pos.group]
      if pos.pick ~= pos.original and (usage[pos.pick] or 0) >= 2 and not pos.exclude[id]
          and not (taken and taken[id]) and themeOk(entry, pos, pos.themeLevel or "none") then
        eligible[#eligible + 1] = pos
      end
    end
    local list = eligible
    if state.similar and #eligible > 0 then
      local fraction, widened = nil, false
      while true do
        list = {}
        for _, pos in ipairs(eligible) do
          local band = fraction or pos.fraction or BAND_START
          if bandDiff(entry, pos) <= band + 1e-9 then list[#list + 1] = pos end
        end
        if #list > 0 then break end
        -- widen for this species alone, from the starting band
        fraction = (fraction or BAND_START) + BAND_STEP
        widened = true
      end
      if widened then report.catchWidened = report.catchWidened + 1 end
    end
    local pos = state.ctx.rng("wild", "catch", state.mode, id):pick(list)
    if pos then
      local taken = pos.group and state.takenByGroup[pos.group]
      usage[pos.pick] = usage[pos.pick] - 1
      if taken then
        -- the old pick stays taken only if another position in the group has it
        local still = false
        for _, other in ipairs(sorted) do
          if other ~= pos and other.group == pos.group and other.pick == pos.pick then still = true end
        end
        if not still then taken[pos.pick] = nil end
        taken[id] = true
      end
      pos.pick = id
      usage[id] = 1
      report.catchMoved = report.catchMoved + 1
    else
      report.catchUnplaced[#report.catchUnplaced + 1] = id
    end
  end
end

-- ---------------------------------------------------------------- the module

local LEVEL_OPTIONS = {}
for i, percent in ipairs({ 100, 125, 150, 200 }) do
  LEVEL_OPTIONS[i] = { label = percent .. " PERCENT", value = percent }
end

local Wild = {
  id = "wild",
  -- Oak's box: two lines of at most 18 characters; labels at most 12.
  questions = {
    { key = WILD_KEY, kind = "yesno", text = "Shuffle wild\nPOKéMON?",
      recommended = true, everything = true },
    { key = MODE_KEY, kind = "choice", onlyIf = WILD_KEY, text = "One swap per\nroute or game?",
      options = { { label = "PER ROUTE", value = "route" }, { label = "WHOLE GAME", value = "game" },
                  { label = "ANY SLOT", value = "slot" } },
      recommended = "route", everything = "game" },
    { key = SIMILAR_KEY, kind = "yesno", onlyIf = WILD_KEY, text = "Keep them about\nas strong?",
      recommended = true, everything = false },
    { key = THEME_KEY, kind = "yesno", onlyIf = WILD_KEY, text = "Keep each route's\ntype theme?",
      -- off in RECOMMENDED: no Johto place has a FIRE, ELECTRIC or DRAGON
      -- theme, so with it on a few of those species have nowhere to go
      recommended = false, everything = false },
    { key = CATCH_KEY, kind = "yesno", onlyIf = WILD_KEY, text = "Put every POKéMON\nin the wild?",
      recommended = true, everything = true },
    { key = LEVEL_KEY, kind = "choice", text = "Wild POKéMON\nlevel percent?",
      options = LEVEL_OPTIONS, recommended = 100, everything = 100 },
  },
}

-- Module state, one per installed copy.
local function newState() return { applied = nil, byScope = nil } end

-- Put every rewritten row back to the species and levels it had.
local function restore(state)
  local applied = state.applied
  if applied then
    for i = #applied.rows, 1, -1 do
      local entry = applied.rows[i]
      entry.row.species, entry.row.level = entry.species, entry.level
      entry.row.min, entry.row.max = entry.min, entry.max
    end
  end
  state.applied, state.byScope, state.bySlot, state.pokemon, state.pool = nil, nil, nil, nil, nil
  state.report, state.levelPercent, state.shuffle = nil, nil, nil
  state.ctx.shared.wild = nil
end

local function readOptions(state)
  local ctx = state.ctx
  state.shuffle = ctx.option(WILD_KEY) == true
  local mode = ctx.option(MODE_KEY)
  state.legacy = state.shuffle and mode == nil
  state.mode = (mode == "game" or mode == "slot") and mode or "route"
  state.similar = ctx.option(SIMILAR_KEY) == true
  state.theme = ctx.option(THEME_KEY) == true
  state.catchAll = ctx.option(CATCH_KEY) == true
  local percent = ctx.option(LEVEL_KEY)
  state.levelPercent = (type(percent) == "number" and percent > 0) and percent or 100
end

local function apply(state, data)
  local encounters = data.gen2Encounters
  local pokemon = data.pokemon
  if type(encounters) ~= "table" or type(pokemon) ~= "table" then
    state.ctx.log("wild: no encounter or species data; wild POKéMON left as they are")
    return
  end
  state.pokemon, state.pool = pokemon, buildPool(pokemon)
  state.byScope, state.bySlot = {}, {}
  state.encounters = encounters

  local rows = collectRows(encounters)
  local scopes, exclude, fish = survey(encounters, data.gen2Maps, rows)
  state.scopes, state.exclude, state.fish = scopes, exclude, fish
  state.report = newReport(state)

  if state.shuffle and state.legacy then
    local species = {}
    for scope, s in pairs(scopes) do species[scope] = s.species end
    for _, scope in ipairs(sortedKeys(species)) do legacyAssign(state, scope, species[scope]) end
    state.report.mode = "route (before version 2)"
  elseif state.shuffle then
    local hasWater = false
    for _, entry in ipairs(state.pool) do
      if entry.types[WATER_TYPE] then hasWater = true end
    end
    state.themes = {}
    for scope, s in pairs(scopes) do
      state.themes[scope] = {
        land = placeTheme(pokemon, s.habitats.land, "land", hasWater),
        water = placeTheme(pokemon, s.habitats.water, "water", hasWater),
      }
    end
    local positions = buildPositions(state, rows)
    assignAll(state, positions)
    state.report.coveredBefore = countCovered(state, usageOf(positions))
    if state.catchAll then catchAll(state, positions) end
    state.report.covered, state.report.missing = countCovered(state, usageOf(positions))
    state.positions = positions
    -- The lookups the rewrite and the rod use.
    for _, pos in ipairs(positions) do
      if state.mode == "slot" then
        state.bySlot[pos.key] = pos.pick
      elseif state.mode == "game" then
        for scope, s in pairs(scopes) do
          if s.species[pos.original] then
            state.byScope[scope] = state.byScope[scope] or {}
            state.byScope[scope][pos.original] = pos.pick
          end
        end
      else
        local scope = pos.key:sub(1, #pos.key - #pos.original - 1)
        state.byScope[scope] = state.byScope[scope] or {}
        state.byScope[scope][pos.original] = pos.pick
      end
    end
  end

  local applied = { rows = {} }
  local changed, levelled = 0, 0
  local percent = state.levelPercent
  for _, entry in ipairs(rows) do
    local row = entry.row
    local original = row.species
    applied.rows[#applied.rows + 1] = { row = row, species = original, level = row.level,
      min = row.min, max = row.max }
    if state.shuffle then
      local replacement
      if state.mode == "slot" and not state.legacy then
        replacement = state.bySlot[entry.slot]
      else
        replacement = state.byScope[entry.scope] and state.byScope[entry.scope][original]
      end
      if replacement and replacement ~= original then
        row.species = replacement
        changed = changed + 1
      end
    end
    if percent ~= 100 then
      row.level, row.min, row.max = scaleLevel(row.level, percent), scaleLevel(row.min, percent),
        scaleLevel(row.max, percent)
      levelled = levelled + 1
    end
  end
  state.applied = applied
  state.ctx.shared.wild = { mode = state.report.mode, byScope = state.byScope, bySlot = state.bySlot,
    report = state.report, levelPercent = percent }
  local r = state.report
  if state.shuffle then
    state.ctx.log("wild: %s mode, %d of %d wild slots changed across %d scopes (%s%s)",
      r.mode, changed, #rows, #sortedKeys(scopes), state.similar and "similar strength" or "any strength",
      state.theme and ", type themes" or "")
    if not state.legacy then
      state.ctx.log("wild: %d picks; band widened past 10%% for %d (past 25%%: %d, past 50%%: %d, widest %d%%);"
        .. " theme from the main place %d, theme dropped %d; shared a replacement %d",
        r.positions, r.widened, r.over25, r.over50, math.floor(r.worstBand * 100 + 0.5),
        r.themeMain, r.themeDropped, r.sharedTaken)
      state.ctx.log("wild: %d of %d species in the wild (%d before catch 'em all, %d moved, %d widened, %d unplaced)",
        r.covered, r.poolSize, r.coveredBefore, r.catchMoved, r.catchWidened, #r.catchUnplaced)
    end
  end
  if percent ~= 100 then
    state.ctx.log("wild: levels at %d%% on %d slots, clamped to %d-%d", percent, levelled, LEVEL_MIN, LEVEL_MAX)
  end
end

-- A replacement for a rod row the precomputed survey did not know (a mod's
-- fish group, a map with no header row).  It depends only on the seed, the
-- key and the precomputed picks, never on which unknown row came first.
local function lateFishPick(state, key, mapId, species, group)
  local places = { { scope = mapId, habitat = "water", weight = 1,
    theme = state.themes and state.themes[mapId] and state.themes[mapId].water or { [WATER_TYPE] = true } } }
  local pos = newPosition(state, key, species, nil, state.exclude[mapId], places)
  local taken = {}
  for _, other in ipairs(state.positions or {}) do
    if group == "game" or (group and other.group == group) then taken[other.pick] = true end
  end
  return state.ctx.rng("wild", "late", key):pick(candidatesFor(state, pos, taken).list) or species
end

local function fishReplacement(state, mapId, rod, species, level)
  if not (state.byScope and state.pokemon and mapId) then return nil end
  if keepAsIs(state.pokemon, species) then return species end
  if state.legacy then
    local mapping = state.byScope[mapId]
    if not (mapping and mapping[species]) then
      mapping = legacyAssign(state, mapId, { [species] = true })
    end
    return mapping[species]
  end
  if state.mode == "slot" then
    local key = fishSlotKey(mapId, ROD_KEY[rod] or tostring(rod), species, level)
    state.bySlot[key] = state.bySlot[key] or lateFishPick(state, key, mapId, species, nil)
    return state.bySlot[key]
  end
  local mapping = state.byScope[mapId] or {}
  state.byScope[mapId] = mapping
  if not mapping[species] then
    if state.mode == "game" then
      -- an original seen elsewhere keeps its one replacement
      for _, pos in ipairs(state.positions or {}) do
        if pos.original == species then mapping[species] = pos.pick end
      end
    end
    mapping[species] = mapping[species]
      or lateFishPick(state, mapId .. "|" .. species, mapId, species, state.mode == "game" and "game" or mapId)
  end
  return mapping[species]
end

function Wild.install(mod, ctx)
  local state = newState()
  state.ctx = ctx

  ctx.onSave(function(active)
    restore(state)
    if not active then return end
    readOptions(state)
    if not state.shuffle and state.levelPercent == 100 then return end
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
      if not (state.applied and ctx.active()) then return roll end
      local out
      if state.shuffle then
        local replacement = fishReplacement(state, mapId, rod, roll.species, roll.level)
        if replacement and replacement ~= roll.species then
          out = {}
          for k, v in pairs(roll) do out[k] = v end
          out.species = replacement
        end
      end
      if state.levelPercent ~= 100 and type(roll.level) == "number" then
        if not out then
          out = {}
          for k, v in pairs(roll) do out[k] = v end
        end
        out.level = scaleLevel(roll.level, state.levelPercent)
      end
      return out or roll
    end)
  end
end

-- For tests: the pure helpers.
Wild._scaleLevel = scaleLevel
Wild._placeTheme = placeTheme

return Wild
