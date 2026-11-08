-- Test for modules/wild.lua.  From the repository root:
--   luajit launcher/mods/crystal_randomizer/tests/wild_test.lua
-- Optional: WILD_TEST_DATA=<a version cache's data/generated folder> repeats
-- the checks on the real Crystal tables (pokemon.lua, encounters.lua,
-- maps.lua), for example a disposable identity's
--   %APPDATA%/LOVE/<identity>/crystal/data/generated
-- and prints coverage and band figures for each setup.
package.path = "./?.lua;./?/init.lua;" .. package.path

local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Encounter = require("src.battle.gen2.Encounter")
local MODULE = "launcher/mods/crystal_randomizer/modules/wild.lua"

local failures, checks = 0, 0
local function check(ok, fmt, ...)
  checks = checks + 1
  if not ok then
    failures = failures + 1
    print("FAIL " .. (select("#", ...) > 0 and fmt:format(...) or fmt))
  end
end

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepCopy(x) end
  return out
end

local function deepEqual(a, b, path)
  path = path or "data"
  if type(a) ~= type(b) then return false, path end
  if type(a) ~= "table" then
    if a == b then return true end
    return false, path .. " (" .. tostring(a) .. " vs " .. tostring(b) .. ")"
  end
  for k, x in pairs(a) do
    local ok, where = deepEqual(x, b[k], path .. "." .. tostring(k))
    if not ok then return false, where end
  end
  for k in pairs(b) do
    if a[k] == nil then return false, path .. "." .. tostring(k) .. " added" end
  end
  return true
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

-- ------------------------------------------------------------ the fixture

local FIXTURE_TYPES = { "NORMAL", "BUG", "ROCK", "WATER", "FIRE" }

local function fixture()
  local pokemon = {}
  local function mon(id, index, bst, extra)
    local each = math.floor(bst / 6)
    local def = { id = id, name = id, index = index, genderRatio = 127,
      eggGroups = { "EGG_FIELD", "EGG_FIELD" }, eggGroupsRaw = 0x55,
      types = { FIXTURE_TYPES[index % 5 + 1], FIXTURE_TYPES[(index * 3) % 5 + 1] },
      baseStats = { hp = bst - each * 5, attack = each, defense = each, speed = each,
        specialAttack = each, specialDefense = each } }
    for k, v in pairs(extra or {}) do def[k] = v end
    pokemon[id] = def
  end
  for i = 1, 40 do mon(("MON%02d"):format(i), i, 200 + i * 10) end
  mon("UNOWN", 201, 336, { genderRatio = 255, eggGroups = { "EGG_NONE", "EGG_NONE" }, eggGroupsRaw = 255 })
  mon("LEGEND", 150, 680, { genderRatio = 255, eggGroups = { "EGG_NONE", "EGG_NONE" }, eggGroupsRaw = 255 })
  pokemon.GLITCH = { id = "GLITCH", name = "GLITCH", index = 0, baseStats = { hp = 1 } }
  pokemon.NOSTATS = { id = "NOSTATS", name = "NOSTATS", index = 99 }
  local function slot(species, level) return { species = species, level = level } end
  local function seven(a, b, c, level)
    return { slot(a, level), slot(b, level), slot(a, level + 1), slot(c, level),
      slot(b, level), slot(a, level + 2), slot(c, level + 2) }
  end
  local encounters = {
    grass = {
      ROUTE_A = { map = "ROUTE_A", rates = { MORN = 10, DAY = 10, NITE = 10 },
        slots = { MORN = seven("MON01", "MON02", "MON03", 2),
                  DAY = seven("MON01", "MON02", "MON04", 3),
                  NITE = seven("MON05", "MON02", "MON03", 4) } },
      RUINS = { map = "RUINS", rates = { MORN = 10, DAY = 10, NITE = 10 },
        slots = { MORN = seven("UNOWN", "UNOWN", "UNOWN", 5),
                  DAY = seven("UNOWN", "UNOWN", "UNOWN", 5),
                  NITE = seven("UNOWN", "UNOWN", "UNOWN", 5) } },
      ROUTE_B = { map = "ROUTE_B", rates = { MORN = 10, DAY = 10, NITE = 10 },
        slots = { MORN = seven("MON30", "MON31", "MON32", 30),
                  DAY = seven("MON30", "MON31", "MON32", 30),
                  NITE = seven("MON33", "MON31", "MON32", 90) } },
      NATIONAL_PARK = { map = "NATIONAL_PARK", rates = { MORN = 10, DAY = 10, NITE = 10 },
        slots = { MORN = seven("MON19", "MON20", "MON21", 12),
                  DAY = seven("MON19", "MON20", "MON21", 12),
                  NITE = seven("MON19", "MON20", "MON21", 12) } },
    },
    water = {
      ROUTE_A = { map = "ROUTE_A", rate = 10,
        slots = { slot("MON06", 10), slot("MON01", 10), slot("MON06", 12) } },
    },
    swarmGrass = {
      ROUTE_B = { map = "ROUTE_B", rates = { MORN = 10, DAY = 10, NITE = 10 },
        slots = { MORN = seven("MON34", "MON31", "MON32", 30),
                  DAY = seven("MON34", "MON31", "MON32", 30),
                  NITE = seven("MON34", "MON31", "MON32", 30) } },
    },
    swarmWater = {},
    fishGroups = {
      FISHGROUP_SHORE = { chance = 128,
        old = { { chance = 179, level = 10, species = "MON07" },
                { chance = 255, level = 10, species = "MON01" } },
        good = { { chance = 179, level = 20, species = "MON07" },
                 { chance = 255, timeGroup = 0 } },
        super = { { chance = 255, level = 40, day = slot("MON08", 40), nite = slot("MON09", 40) } } },
    },
    timeFishGroups = { [0] = { day = slot("MON10", 20), nite = slot("MON11", 20) } },
    treeSets = {
      TREEMON_SET_ROUTE = {
        common = { { chance = 50, level = 10, species = "MON12" },
                   { chance = 50, level = 10, species = "MON13" } },
        rare = { { chance = 100, level = 10, species = "MON14" } } },
      TREEMON_SET_ROCK = {
        common = { { chance = 90, level = 15, species = "MON15" },
                   { chance = 10, level = 1, species = "MON16" } }, rare = {} },
    },
    trees = { ROUTE_A = "TREEMON_SET_ROUTE" },
    rocks = { ROUTE_B = "TREEMON_SET_ROCK" },
    bugContest = { { chance = 50, min = 7, max = 18, species = "MON17" },
                   { chance = 50, min = 7, max = 60, species = "MON18" } },
    roamMons = { { species = "LEGEND", level = 40 } },
  }
  local maps = { ROUTE_A = { fishGroup = "FISHGROUP_SHORE" }, ROUTE_B = { fishGroup = "FISHGROUP_NONE" },
    RUINS = {}, NATIONAL_PARK = {} }
  return { pokemon = pokemon, gen2Encounters = encounters, gen2Maps = maps }
end

local function loadReal(dir)
  local function load(name)
    local f = io.open(dir .. "/" .. name, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    local chunk = assert(loadstring(text, name))
    setfenv(chunk, {})
    return chunk()
  end
  local pokemon, encounters, maps = load("pokemon.lua"), load("encounters.lua"), load("maps.lua")
  if not (pokemon and encounters) then return nil end
  return { pokemon = pokemon, gen2Encounters = encounters, gen2Maps = maps }
end

-- ------------------------------------------------------------ harness

local function install(data, seed, options)
  local Wild = dofile(MODULE)
  local hooks = {}
  local mod = { game = { data = data },
    hooks = { wrap = function(_, name, fn) hooks[name] = fn end } }
  local ctx = Fake.new({ seed = seed, options = options })
  Wild.install(mod, ctx)
  return { Wild = Wild, ctx = ctx, hooks = hooks, mod = mod }
end

local ROD_NAME = { old = "OLD_ROD", good = "GOOD_ROD", super = "SUPER_ROD" }

-- One rod roll through the hook, the engine's vanilla link giving `species`.
local function fish(h, mapId, species, level, rod)
  local fn = h.hooks["encounter.fishing"]
  local roll = fn(function() return { species = species, level = level or 10 } end,
    rod or "OLD_ROD", mapId, {}, {})
  return roll and roll.species, roll and roll.level
end

local function isLegendaryShape(def)
  return def.genderRatio == 255 and (def.eggGroupsRaw == 255
    or (def.eggGroups and def.eggGroups[1] == "EGG_NONE" and def.eggGroups[2] == "EGG_NONE"))
end

local function isReal(def)
  if type(def) ~= "table" or type(def.index) ~= "number" or def.index < 1 then return false end
  local s = def.baseStats
  return type(s) == "table" and type(s.hp) == "number" and type(s.attack) == "number"
    and type(s.defense) == "number" and type(s.speed) == "number"
    and type(s.specialAttack) == "number" and type(s.specialDefense) == "number"
end

local function bst(def)
  local s = def.baseStats
  return s.hp + s.attack + s.defense + s.speed + s.specialAttack + s.specialDefense
end

local function poolOf(pokemon)
  local pool = {}
  for id, def in pairs(pokemon) do
    if isReal(def) and type(def.name) == "string" and not isLegendaryShape(def) then pool[id] = true end
  end
  return pool
end

-- The vanilla world, worked out here independently of the module:
-- every slot { scope, habitat, path, species, level } in table order, fish
-- rows per map, each scope's species and the no-reuse sets.
local function vanillaWorld(data)
  local e, slots = data.gen2Encounters, {}
  local function add(scope, habitat, row, path)
    if type(row) == "table" and type(row.species) == "string" then
      slots[#slots + 1] = { scope = scope, habitat = habitat, row = row, path = path,
        species = row.species, level = row.level, min = row.min, max = row.max }
    end
  end
  for _, kind in ipairs({ "grass", "swarmGrass" }) do
    for mapId, entry in pairs(e[kind] or {}) do
      for tod, list in pairs(entry.slots or {}) do
        for i, row in ipairs(list) do add(mapId, "land", row, { kind, mapId, "slots", tod, i }) end
      end
    end
  end
  for _, kind in ipairs({ "water", "swarmWater" }) do
    for mapId, entry in pairs(e[kind] or {}) do
      for i, row in ipairs(entry.slots or {}) do add(mapId, "water", row, { kind, mapId, "slots", i }) end
    end
  end
  for setName, set in pairs(e.treeSets or {}) do
    for _, half in ipairs({ "common", "rare" }) do
      for i, row in ipairs(set[half] or {}) do add("tree:" .. setName, "land", row, { "treeSets", setName, half, i }) end
    end
  end
  for i, row in ipairs(e.bugContest or {}) do add("bug_contest", "land", row, { "bugContest", i }) end

  local fishRows = {}
  for mapId, def in pairs(data.gen2Maps or {}) do
    local base = def.fishGroup
    if type(base) == "string" and base ~= "FISHGROUP_NONE" then
      local list, seen = {}, {}
      for _, swarm in ipairs({ Encounter.FISHSWARM_NONE, Encounter.FISHSWARM_QWILFISH,
          Encounter.FISHSWARM_REMORAID }) do
        local group = e.fishGroups[Encounter.fishGroupFor(e, base, swarm)]
        for rod, rows in pairs(group or {}) do
          if type(rows) == "table" and ROD_NAME[rod] then
            for _, row in ipairs(rows) do
              local timed = row.timeGroup and e.timeFishGroups and e.timeFishGroups[row.timeGroup] or {}
              for _, s in ipairs({ row, row.day or false, row.nite or false, timed.day or false, timed.nite or false }) do
                if s and type(s.species) == "string" and s.species ~= "NO_ITEM" then
                  local key = rod .. s.species .. tostring(s.level)
                  if not seen[key] then
                    seen[key] = true
                    list[#list + 1] = { rod = rod, species = s.species, level = s.level }
                  end
                end
              end
            end
          end
        end
      end
      if #list > 0 then fishRows[mapId] = list end
    end
  end

  local scopeSpecies = {}
  local function note(scope, species)
    scopeSpecies[scope] = scopeSpecies[scope] or {}
    scopeSpecies[scope][species] = true
  end
  for _, s in ipairs(slots) do note(s.scope, s.species) end
  for mapId, list in pairs(fishRows) do for _, f in ipairs(list) do note(mapId, f.species) end end
  local banned = {}
  for scope, set in pairs(scopeSpecies) do banned[scope] = deepCopy(set) end
  for _, kind in ipairs({ "trees", "rocks" }) do
    for mapId, setName in pairs(e[kind] or {}) do
      local tree = scopeSpecies["tree:" .. setName]
      if banned[mapId] and tree then for id in pairs(tree) do banned[mapId][id] = true end end
      if banned["tree:" .. setName] and scopeSpecies[mapId] then
        for id in pairs(scopeSpecies[mapId]) do banned["tree:" .. setName][id] = true end
      end
    end
  end
  if banned.bug_contest and scopeSpecies.NATIONAL_PARK then
    for id in pairs(scopeSpecies.NATIONAL_PARK) do banned.bug_contest[id] = true end
  end
  -- habitat species per scope, for the theme check
  local habitat = {}
  for _, s in ipairs(slots) do
    habitat[s.scope] = habitat[s.scope] or { land = {}, water = {} }
    habitat[s.scope][s.habitat][s.species] = true
  end
  for mapId, list in pairs(fishRows) do
    habitat[mapId] = habitat[mapId] or { land = {}, water = {} }
    for _, f in ipairs(list) do habitat[mapId].water[f.species] = true end
  end
  return { slots = slots, fish = fishRows, species = scopeSpecies, banned = banned, habitat = habitat }
end

local function rowAt(data, path)
  local t = data.gen2Encounters
  for _, k in ipairs(path) do t = t[k] end
  return t
end

-- Every (scope, habitat, original, replacement, level before/after) in the
-- randomized world: table slots plus one rod roll per vanilla fish row.
local function observed(h, data, world)
  local out = {}
  for _, s in ipairs(world.slots) do
    local row = rowAt(data, s.path)
    out[#out + 1] = { scope = s.scope, habitat = s.habitat, from = s.species, to = row.species,
      slot = table.concat(s.path, "|"), level = s.level, newLevel = row.level,
      min = s.min, max = s.max, newMin = row.min, newMax = row.max }
  end
  for _, mapId in ipairs(sortedKeys(world.fish)) do
    for _, f in ipairs(world.fish[mapId]) do
      local to, level = fish(h, mapId, f.species, f.level, ROD_NAME[f.rod])
      out[#out + 1] = { scope = mapId, habitat = "water", from = f.species, to = to,
        slot = mapId .. "|fish|" .. f.rod .. "|" .. f.species .. "|" .. tostring(f.level),
        level = f.level, newLevel = level, fish = true }
    end
  end
  return out
end

-- The theme a place must keep (the module header's definition, rewritten).
local function themeFits(pokemon, world, scope, habitat, original, to)
  local types = {}
  for _, t in ipairs(pokemon[to].types or {}) do types[t] = true end
  if habitat == "water" then return types.WATER == true end
  local counts, n, best = {}, 0, 0
  for id in pairs(world.habitat[scope].land) do
    local def = pokemon[id]
    if isReal(def) then
      n = n + 1
      local seen = {}
      for _, t in ipairs(def.types or {}) do
        if not seen[t] then seen[t] = true; counts[t] = (counts[t] or 0) + 1 end
      end
    end
  end
  local theme = {}
  for t, c in pairs(counts) do
    if c * 3 >= n then theme[t] = true end
    best = math.max(best, c)
  end
  if next(theme) == nil then for t, c in pairs(counts) do if c == best then theme[t] = true end end end
  for _, t in ipairs(pokemon[original].types or {}) do theme[t] = true end
  for t in pairs(types) do if theme[t] then return true end end
  return false
end

-- ------------------------------------------------------------ the questions

do
  local Wild = dofile(MODULE)
  local keys = {}
  local function glyphs(s) return #(s:gsub("é", "e")) end
  for _, q in ipairs(Wild.questions) do
    keys[q.key] = q
    local lines = {}
    for line in (q.text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    check(#lines <= 2, "question %s has %d lines", q.key, #lines)
    for _, line in ipairs(lines) do
      check(glyphs(line) <= 18, "question %s line %q is %d characters", q.key, line, glyphs(line))
    end
    check(q.recommended ~= nil and q.everything ~= nil, "question %s lacks recommended/everything", q.key)
    if q.kind == "choice" then
      local values = {}
      for _, o in ipairs(q.options) do
        check(#o.label <= 12 and o.label == o.label:upper(), "label %q of %s", o.label, q.key)
        values[o.value] = true
      end
      check(values[q.recommended] and values[q.everything], "question %s presets are not options", q.key)
    else
      check(type(q.recommended) == "boolean" and type(q.everything) == "boolean",
        "question %s presets are not booleans", q.key)
    end
    if q.onlyIf then check(keys[q.onlyIf] ~= nil, "question %s gates on a later key", q.key) end
  end
  for _, key in ipairs({ "wild", "wild_mode", "wild_similar", "wild_theme", "wild_catch_all", "wild_level" }) do
    check(keys[key] ~= nil, "question %s missing", key)
  end
end

local SETUPS = {}
do
  local Wild = dofile(MODULE)
  for _, preset in ipairs({ "recommended", "everything" }) do
    local opts = {}
    for _, q in ipairs(Wild.questions) do opts[q.key] = q[preset] end
    SETUPS[preset] = opts
  end
end

-- ------------------------------------------------------------ the checks

local function checkWorld(tag, h, data, vanilla, world, opts)
  local pokemon = data.pokemon
  local pool = poolOf(pokemon)
  local obs = observed(h, data, world)
  local mode = opts.wild_mode
  local perScope, global, globalFrom, used = {}, {}, {}, {}
  local changed, worst = 0, 0
  for _, m in ipairs(obs) do
    local def = pokemon[m.to]
    check(def ~= nil and isReal(def), "%s %s %s became invalid %s", tag, m.slot, m.from, tostring(m.to))
    if def then
      used[m.to] = true
      local keep = not pool[m.from]
      if keep then
        check(m.to == m.from, "%s %s: kept species %s was replaced", tag, m.slot, m.from)
      else
        check(m.to ~= m.from, "%s %s: %s replaced by itself", tag, m.slot, m.from)
        check(not world.banned[m.scope][m.to], "%s %s: %s became %s, already on that route",
          tag, m.slot, m.from, m.to)
        if mode == "game" then
          for scope, set in pairs(world.species) do
            if set[m.from] then
              check(not world.banned[scope][m.to], "%s game: %s became %s, vanilla on %s",
                tag, m.from, m.to, scope)
            end
          end
        end
        check(not isLegendaryShape(def), "%s %s: became legendary/UNOWN %s", tag, m.slot, m.to)
        changed = changed + 1
        if opts.wild_similar then
          local a = bst(pokemon[m.from])
          worst = math.max(worst, math.abs(bst(def) - a) / a)
        end
        if opts.wild_theme and mode ~= "game" then
          check(themeFits(pokemon, world, m.scope, m.habitat, m.from, m.to),
            "%s %s: %s became %s, off the %s theme", tag, m.slot, m.from, m.to, m.habitat)
        end
        if opts.wild_theme and m.habitat == "water" and mode ~= "game" then
          local water = false
          for _, t in ipairs(def.types or {}) do if t == "WATER" then water = true end end
          check(water, "%s %s: water slot got non-water %s", tag, m.slot, m.to)
        end
      end
      if mode == "route" or mode == "game" then
        perScope[m.scope] = perScope[m.scope] or {}
        local seen = perScope[m.scope][m.from]
        check(seen == nil or seen == m.to, "%s %s %s maps to both %s and %s", tag, m.scope, m.from,
          tostring(seen), m.to)
        perScope[m.scope][m.from] = m.to
      end
      if mode == "game" and not keep then
        check(global[m.from] == nil or global[m.from] == m.to, "%s game: %s maps to %s and %s",
          tag, m.from, tostring(global[m.from]), m.to)
        global[m.from] = m.to
        check(globalFrom[m.to] == nil or globalFrom[m.to] == m.from,
          "%s game: %s replaces both %s and %s", tag, m.to, tostring(globalFrom[m.to]), m.from)
        globalFrom[m.to] = m.from
      end
    end
    -- levels
    local pct = opts.wild_level or 100
    local function scaled(v)
      if v == nil or pct == 100 then return v end
      return math.max(2, math.min(100, math.floor(v * pct / 100 + 0.5)))
    end
    check(m.newLevel == scaled(m.level), "%s %s level %s became %s at %d%%", tag, m.slot,
      tostring(m.level), tostring(m.newLevel), pct)
    check(m.newMin == scaled(m.min) and m.newMax == scaled(m.max), "%s %s contest range wrong", tag, m.slot)
  end
  check(changed > 0, "%s nothing was randomized", tag)
  -- route mode: originals in one scope differ while the pool allows it
  if mode == "route" then
    for scope, map in pairs(perScope) do
      local back = {}
      for from, to in pairs(map) do
        if from ~= to then
          check(back[to] == nil or h.ctx.shared.wild.report.sharedTaken > 0,
            "%s %s: %s and %s share %s", tag, scope, from, tostring(back[to]), to)
          back[to] = from
        end
      end
    end
  end
  -- coverage as the player meets it equals the module's report
  local covered = 0
  for id in pairs(pool) do if used[id] then covered = covered + 1 end end
  local r = h.ctx.shared.wild.report
  check(r.covered == covered, "%s coverage report %d, counted %d", tag, r.covered, covered)
  if mode == "game" then
    local originals = 0
    for _ in pairs(global) do originals = originals + 1 end
    check(covered == originals, "%s game: %d species for %d originals", tag, covered, originals)
  end
  -- the roamers' roster is untouched
  check(deepEqual(vanilla.gen2Encounters.roamMons, data.gen2Encounters.roamMons), "%s roamers changed", tag)
  return { covered = covered, pool = r.poolSize, worst = worst, report = r }
end

local function snapshot(h, data, world)
  local out = {}
  for _, m in ipairs(observed(h, data, world)) do out[#out + 1] = m.slot .. "=" .. tostring(m.to) .. ":" .. tostring(m.newLevel) end
  return table.concat(out, ",")
end

local function runSuite(label, makeData, fishMap, fishOne)
  local summary = {}
  local function tag(fmt) return "[" .. label .. "] " .. fmt end

  -- 1. Inactive, wild = NO, and level-only saves.
  do
    local data = makeData()
    local vanilla = deepCopy(data)
    local h = install(data, nil, {})
    h.ctx.setActive(false)
    local ok, where = deepEqual(vanilla, data)
    check(ok, tag("inactive save changed the tables at %s"), tostring(where))
    check(fish(h, fishMap, fishOne) == fishOne, tag("inactive fishing was changed"))
    h.ctx.setActive(true, "seed-no", { wild = false, wild_level = 100 })
    ok, where = deepEqual(vanilla, data)
    check(ok, tag("wild = NO changed the tables at %s"), tostring(where))
    check(fish(h, fishMap, fishOne) == fishOne, tag("wild = NO fishing was changed"))
    -- levels without shuffling
    h.ctx.setActive(true, "seed-no", { wild = false, wild_level = 150 })
    local world = vanillaWorld(vanilla)
    for _, s in ipairs(world.slots) do
      local row = rowAt(data, s.path)
      check(row.species == s.species, tag("level-only save changed species at %s"), table.concat(s.path, "|"))
      if s.level then
        check(row.level == math.max(2, math.min(100, math.floor(s.level * 1.5 + 0.5))),
          tag("level-only save: level %d became %s"), s.level, tostring(row.level))
      end
    end
    local sp, lv = fish(h, fishMap, fishOne, 10)
    check(sp == fishOne and lv == 15, tag("level-only fishing gave %s L%s"), tostring(sp), tostring(lv))
    h.ctx.setActive(false)
    ok, where = deepEqual(vanilla, data)
    check(ok, tag("level-only save did not restore at %s"), tostring(where))
  end

  local cases = {}
  for _, mode in ipairs({ "route", "game", "slot" }) do
    for _, flags in ipairs({ { false, false, false }, { true, false, true }, { true, true, true },
        { false, true, false } }) do
      cases[#cases + 1] = { name = mode .. (flags[1] and "+similar" or "") .. (flags[2] and "+theme" or "")
          .. (flags[3] and "+catch" or ""),
        opts = { wild = true, wild_mode = mode, wild_similar = flags[1], wild_theme = flags[2],
          wild_catch_all = flags[3], wild_level = 100 } }
    end
  end
  cases[#cases + 1] = { name = "recommended", opts = SETUPS.recommended }
  cases[#cases + 1] = { name = "everything", opts = SETUPS.everything }
  cases[#cases + 1] = { name = "route+125%", opts = { wild = true, wild_mode = "route", wild_similar = true,
    wild_level = 125 } }
  cases[#cases + 1] = { name = "slot+200%", opts = { wild = true, wild_mode = "slot", wild_level = 200 } }

  for _, case in ipairs(cases) do
    local opts = case.opts
    local sub = "[" .. label .. " " .. case.name .. "]"
    local data = makeData()
    local vanilla = deepCopy(data)
    local world = vanillaWorld(vanilla)
    local h = install(data, "seed-one", opts)
    h.ctx.setActive(true)
    local result = checkWorld(sub, h, data, vanilla, world, opts)
    summary[#summary + 1] = { name = case.name, result = result }

    -- Determinism: a second install, fishing asked in reverse order first.
    local data2 = makeData()
    local h2 = install(data2, "seed-one", opts)
    check(fish(h2, fishMap, fishOne) == fishOne, "%s fishing changed before any save", sub)
    h2.ctx.setActive(true)
    local rev = {}
    for _, mapId in ipairs(sortedKeys(world.fish)) do
      for i = #world.fish[mapId], 1, -1 do
        local f = world.fish[mapId][i]
        rev[#rev + 1] = fish(h2, mapId, f.species, f.level, ROD_NAME[f.rod])
      end
    end
    check(snapshot(h, data, world) == snapshot(h2, data2, world), "%s same seed, different world", sub)
    local same, where = deepEqual(data.gen2Encounters, data2.gen2Encounters)
    check(same, "%s same seed gave different tables at %s", sub, tostring(where))

    -- Switching: another seed, then vanilla, then back.
    local one = snapshot(h, data, world)
    h.ctx.setActive(true, "seed-two", opts)
    local data3 = makeData()
    local h3 = install(data3, "seed-two", opts)
    h3.ctx.setActive(true)
    check(snapshot(h, data, world) == snapshot(h3, data3, world), "%s switching seeds kept old picks", sub)
    check(snapshot(h, data, world) ~= one, "%s two seeds gave the same world", sub)
    h.ctx.setActive(false)
    same, where = deepEqual(vanilla, data)
    check(same, "%s returning to a vanilla save did not restore at %s", sub, tostring(where))
    check(fish(h, fishMap, fishOne) == fishOne, "%s fishing not restored", sub)
    check(h.ctx.shared.wild == nil, "%s shared state left behind", sub)
    h.ctx.setActive(true, "seed-one", opts)
    check(snapshot(h, data, world) == one, "%s loading the first save again differs", sub)
    h.ctx.setActive(false)
  end

  -- A save from before version 2 (no wild_mode): round one's rules, stable,
  -- restored, and it may reuse a vanilla species (which v2 never does).
  do
    local opts = { wild = true, wild_similar = true }
    local data = makeData()
    local vanilla = deepCopy(data)
    local world = vanillaWorld(vanilla)
    local h = install(data, "seed-one", opts)
    h.ctx.setActive(true)
    check(h.ctx.shared.wild.mode == "route (before version 2)", tag("legacy save not recognised"))
    local data2 = makeData()
    local h2 = install(data2, "seed-one", opts)
    h2.ctx.setActive(true)
    check(snapshot(h, data, world) == snapshot(h2, data2, world), tag("legacy save not deterministic"))
    h.ctx.setActive(false)
    check(deepEqual(vanilla, data), tag("legacy save did not restore"))
  end
  return summary
end

local function printSummary(label, summary)
  for _, s in ipairs(summary) do
    local r = s.result.report
    print(("[%s] %-22s coverage %3d/%d (%d before catch 'em all); picks %d, band past 10%% %d,"
      .. " past 25%% %d, past 50%% %d, widest band %d%%, worst slot %.0f%%; catch moves %d, widened %d;"
      .. " theme main-place %d"):format(label, s.name, s.result.covered, s.result.pool, r.coveredBefore,
      r.positions, r.widened, r.over25, r.over50, math.floor(r.worstBand * 100 + 0.5), s.result.worst * 100,
      r.catchMoved, r.catchWidened, r.themeMain))
  end
end

local fixtureSummary = runSuite("fixture", fixture, "ROUTE_A", "MON07")
printSummary("fixture", fixtureSummary)
-- On the fixture, slot mode has more slots than species: full coverage.
for _, s in ipairs(fixtureSummary) do
  if s.name == "slot+catch" or s.name == "slot+similar+catch" then
    check(s.result.covered == s.result.pool, "[fixture] %s covered %d of %d", s.name, s.result.covered, s.result.pool)
  end
end

local realDir = os.getenv("WILD_TEST_DATA")
if realDir and realDir ~= "" then
  local probe = loadReal(realDir)
  if probe then
    local summary = runSuite("crystal", function() return loadReal(realDir) end, "ROUTE_30", "POLIWAG")
    printSummary("crystal", summary)
    for _, s in ipairs(summary) do
      if s.name == "route+similar+catch" or s.name == "recommended" or s.name == "slot+similar+catch" then
        check(s.result.covered == s.result.pool, "[crystal] %s covered %d of %d", s.name,
          s.result.covered, s.result.pool)
      end
    end
    -- Seed 876506 with the recommended setup: early routes, then and now.
    local data = loadReal(realDir)
    local vanilla = deepCopy(data)
    local h = install(data, "876506", SETUPS.recommended)
    h.ctx.setActive(true)
    for _, mapId in ipairs({ "ROUTE_29", "ROUTE_30", "ROUTE_31", "ROUTE_32", "ROUTE_33" }) do
      local function line(d)
        local seen, out = {}, {}
        for _, row in ipairs(d.gen2Encounters.grass[mapId].slots.DAY) do
          if not seen[row.species] then seen[row.species] = true; out[#out + 1] = row.species end
        end
        return table.concat(out, " ")
      end
      print(("[crystal] seed 876506 recommended %s DAY: was %s; now %s"):format(mapId, line(vanilla), line(data)))
    end
    for _, l in ipairs(h.ctx.lines) do print("[crystal] log: " .. l) end
  else
    check(false, "WILD_TEST_DATA=%s has no pokemon.lua/encounters.lua", realDir)
  end
end

print(("wild_test: %d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
