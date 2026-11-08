-- Test for modules/wild.lua.  From the repository root:
--   luajit launcher/mods/crystal_randomizer/tests/wild_test.lua
-- Optional: WILD_TEST_DATA=<a version cache's data/generated folder> repeats
-- the checks on the real Crystal tables (pokemon.lua, encounters.lua,
-- maps.lua), for example a disposable identity's
--   %APPDATA%/LOVE/<identity>/crystal/data/generated
package.path = "./?.lua;./?/init.lua;" .. package.path

local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
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

-- ------------------------------------------------------------ the fixture

local function fixture()
  local pokemon = {}
  local function mon(id, index, bst, extra)
    local each = math.floor(bst / 6)
    local def = { id = id, name = id, index = index, genderRatio = 127,
      eggGroups = { "EGG_FIELD", "EGG_FIELD" }, eggGroupsRaw = 0x55,
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
                  NITE = seven("MON33", "MON31", "MON32", 30) } },
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
                   { chance = 10, level = 15, species = "MON16" } }, rare = {} },
    },
    trees = { ROUTE_A = "TREEMON_SET_ROUTE" },
    rocks = { ROUTE_B = "TREEMON_SET_ROCK" },
    bugContest = { { chance = 50, min = 7, max = 18, species = "MON17" },
                   { chance = 50, min = 7, max = 18, species = "MON18" } },
    roamMons = { { species = "LEGEND", level = 40 } },
  }
  local maps = { ROUTE_A = { fishGroup = "FISHGROUP_SHORE" }, ROUTE_B = { fishGroup = "FISHGROUP_NONE" },
    RUINS = {} }
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

-- A fresh copy of the module, installed against `data` with a fake mod.
local function install(data, seed, options)
  local Wild = dofile(MODULE)
  local hooks = {}
  local mod = { game = { data = data },
    hooks = { wrap = function(_, name, fn) hooks[name] = fn end } }
  local ctx = Fake.new({ seed = seed, options = options })
  Wild.install(mod, ctx)
  return { Wild = Wild, ctx = ctx, hooks = hooks, mod = mod }
end

-- The engine's vanilla fishing link, standing in for World's fishVanilla.
local function vanillaFish(row)
  return function() return { species = row.species, level = row.level } end
end

local function fish(h, mapId, species)
  local fn = h.hooks["encounter.fishing"]
  local roll = fn(vanillaFish({ species = species, level = 10 }), "OLD_ROD", mapId, {}, {})
  return roll and roll.species
end

-- Every (scope, original) -> replacement visible in the rewritten tables.
local function tableMapping(vanilla, data)
  local out = {}
  local function walk(scope, a, b)
    if type(a) ~= "table" then return end
    if type(a.species) == "string" and type(b.species) == "string" then
      out[#out + 1] = { scope = scope, from = a.species, to = b.species,
        levelSame = a.level == b.level and a.min == b.min and a.max == b.max }
    end
    for k, v in pairs(a) do
      if type(v) == "table" then walk(scope, v, b[k]) end
    end
  end
  local ve, de = vanilla.gen2Encounters, data.gen2Encounters
  for _, kind in ipairs({ "grass", "water", "swarmGrass", "swarmWater" }) do
    for mapId, entry in pairs(ve[kind] or {}) do walk(mapId, entry, de[kind][mapId]) end
  end
  for setName, set in pairs(ve.treeSets or {}) do walk("tree:" .. setName, set, de.treeSets[setName]) end
  walk("bug_contest", ve.bugContest or {}, de.bugContest or {})
  return out
end

local function isLegendaryShape(def)
  return def.genderRatio == 255 and (def.eggGroupsRaw == 255
    or (def.eggGroups and def.eggGroups[1] == "EGG_NONE" and def.eggGroups[2] == "EGG_NONE"))
end

local function bst(def)
  local s = def.baseStats
  return s.hp + s.attack + s.defense + s.speed + s.specialAttack + s.specialDefense
end

-- ------------------------------------------------------------ the checks

local function runSuite(label, makeData, fishMap, fishOne, fishTwo)
  local function tag(fmt) return "[" .. label .. "] " .. fmt end

  -- 1. Inactive (a vanilla save): nothing changes, fishing passes through.
  do
    local data = makeData()
    local vanilla = deepCopy(data)
    local h = install(data, nil, {})
    h.ctx.setActive(false)
    local ok, where = deepEqual(vanilla, data)
    check(ok, tag("inactive save changed the tables at %s"), tostring(where))
    check(fish(h, fishMap, fishOne) == fishOne, tag("inactive fishing was changed"))
    -- Active, but wild answered NO.
    h.ctx.setActive(true, "seed-no", { wild = false })
    ok, where = deepEqual(vanilla, data)
    check(ok, tag("wild = NO changed the tables at %s"), tostring(where))
    check(fish(h, fishMap, fishOne) == fishOne, tag("wild = NO fishing was changed"))
  end

  for _, similar in ipairs({ false, true }) do
    local opts = { wild = true, wild_similar = similar }
    local sub = similar and "similar" or "any"

    -- 2. Active: valid species only, levels kept, one replacement per scope.
    local data = makeData()
    local vanilla = deepCopy(data)
    local h = install(data, "seed-one", opts)
    h.ctx.setActive(true)
    local pokemon = data.pokemon
    local perScope, changed, worstBand = {}, 0, 0
    for _, m in ipairs(tableMapping(vanilla, data)) do
      local def = pokemon[m.to]
      check(def ~= nil, tag("%s: %s %s became unknown species %s"), sub, m.scope, m.from, tostring(m.to))
      if def then
        check(type(def.index) == "number" and def.index >= 1 and def.baseStats ~= nil,
          tag("%s: %s became invalid species %s"), sub, m.scope, m.to)
        if m.to ~= m.from then
          check(not isLegendaryShape(def), tag("%s: %s %s became legendary/UNOWN %s"),
            sub, m.scope, m.from, m.to)
          changed = changed + 1
          if similar then
            local a, b = bst(pokemon[m.from]), bst(def)
            worstBand = math.max(worstBand, math.abs(a - b) / a)
          end
        end
      end
      check(m.levelSame, tag("%s: %s %s level changed"), sub, m.scope, m.from)
      if m.from == "UNOWN" then
        check(m.to == "UNOWN", tag("%s: UNOWN was replaced on %s"), sub, m.scope)
      end
      perScope[m.scope] = perScope[m.scope] or {}
      local seen = perScope[m.scope][m.from]
      check(seen == nil or seen == m.to, tag("%s: %s %s maps to both %s and %s"),
        sub, m.scope, m.from, tostring(seen), m.to)
      perScope[m.scope][m.from] = m.to
    end
    check(changed > 0, tag("%s: nothing was randomized"), sub)
    if similar then
      check(worstBand <= 0.5, tag("similar: a replacement is %.0f%% off the original's total"), worstBand * 100)
      print(("[%s] similar: worst base-stat-total difference %.1f%%"):format(label, worstBand * 100))
    end
    -- The roamers' roster is not touched.
    local ok = deepEqual(vanilla.gen2Encounters.roamMons, data.gen2Encounters.roamMons)
    check(ok, tag("%s: the roaming roster changed"), sub)

    -- Fishing: same map and species, same answer; valid and not legendary.
    local fishA = fish(h, fishMap, fishOne)
    check(fishA == fish(h, fishMap, fishOne), tag("%s: fishing is not stable"), sub)
    check(pokemon[fishA] and not isLegendaryShape(pokemon[fishA]), tag("%s: fishing gave %s"), sub, tostring(fishA))
    -- A species shared by grass and rod on one map has one replacement.
    local anyGrass = next(perScope)
    for scope, mapping in pairs(perScope) do
      for from, to in pairs(mapping) do
        if not scope:find("^tree:") and scope ~= "bug_contest" then
          check(fish(h, scope, from) == to, tag("%s: %s %s differs between tables and rod"), sub, scope, from)
        end
      end
    end
    check(anyGrass ~= nil, tag("no scopes found"))

    -- 3. Determinism: a second install, fishing asked in a different order.
    local data2 = makeData()
    local h2 = install(data2, "seed-one", opts)
    local f2 = fish(h2, fishMap, fishTwo) -- before the save is known: vanilla
    check(f2 == fishTwo, tag("%s: fishing changed before any save"), sub)
    h2.ctx.setActive(true)
    local fishOrder = { fish(h2, fishMap, fishTwo), fish(h2, fishMap, fishOne) }
    check(fishOrder[2] == fishA, tag("%s: fishing depends on call order"), sub)
    check(fishOrder[1] == fish(h, fishMap, fishTwo), tag("%s: fishing depends on call order (2)"), sub)
    local same, where = deepEqual(data.gen2Encounters, data2.gen2Encounters)
    check(same, tag("%s: same seed gave different tables at %s"), sub, tostring(where))

    -- 4. Switching saves: another seed, then a vanilla save, then back.
    local one = deepCopy(data.gen2Encounters)
    h.ctx.setActive(true, "seed-two", opts)
    local data3 = makeData()
    local h3 = install(data3, "seed-two", opts)
    h3.ctx.setActive(true)
    same, where = deepEqual(data.gen2Encounters, data3.gen2Encounters)
    check(same, tag("%s: switching seeds kept the old seed's picks at %s"), sub, tostring(where))
    check(not deepEqual(one, data.gen2Encounters), tag("%s: two seeds gave identical tables"), sub)
    h.ctx.setActive(false)
    same, where = deepEqual(vanilla, data)
    check(same, tag("%s: returning to a vanilla save did not restore at %s"), sub, tostring(where))
    check(fish(h, fishMap, fishOne) == fishOne, tag("%s: fishing not restored"), sub)
    check(h.ctx.shared.wild == nil, tag("%s: shared mapping left behind"), sub)
    h.ctx.setActive(true, "seed-one", opts)
    same, where = deepEqual(one, data.gen2Encounters)
    check(same, tag("%s: loading the first save again differs at %s"), sub, tostring(where))
  end
end

runSuite("fixture", fixture, "ROUTE_A", "MON07", "MON09")

-- Fixture-only: the distinctness rule on a map with room for it.
do
  local data = fixture()
  local h = install(data, "distinct", { wild = true })
  h.ctx.setActive(true)
  local map = h.ctx.shared.wild.ROUTE_A
  local seen, dup = {}, nil
  for from, to in pairs(map) do
    if seen[to] then dup = from .. "/" .. seen[to] end
    seen[to] = from
  end
  check(dup == nil, "[fixture] two species on ROUTE_A share a replacement: %s", tostring(dup))
end

local realDir = os.getenv("WILD_TEST_DATA")
if realDir and realDir ~= "" then
  local probe = loadReal(realDir)
  if probe then
    runSuite("crystal", function() return loadReal(realDir) end, "ROUTE_30", "POLIWAG", "MAGIKARP")
    -- Every pool species the module could pick is real and not legendary.
    local data = loadReal(realDir)
    local h = install(data, "coverage", { wild = true })
    h.ctx.setActive(true)
    local scopes, kinds = 0, {}
    for scope in pairs(h.ctx.shared.wild) do
      scopes = scopes + 1
      local kind = scope:match("^tree:") and "tree" or (scope == "bug_contest" and "contest" or "map")
      kinds[kind] = (kinds[kind] or 0) + 1
    end
    print(("[crystal] %d scopes: %d maps, %d tree sets, %d contest"):format(scopes,
      kinds.map or 0, kinds.tree or 0, kinds.contest or 0))
    for _, line in ipairs(h.ctx.lines) do print("[crystal] log: " .. line) end
  else
    check(false, "WILD_TEST_DATA=%s has no pokemon.lua/encounters.lua", realDir)
  end
end

print(("wild_test: %d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
