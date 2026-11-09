-- luajit launcher/mods/crystal_randomizer/tests/mapplacer_test.lua   (from the repository root)
--
-- The placer moves ENTRANCES (a doorway's warp tiles together), checked
-- against hand-made graphs and rules in the MAPS.md / mapgraph shapes:
--   1. houses: dead ends cannot strand, so every shuffle passes and the first
--      whole shuffle is used.
--   2. caves and full, where key items sit in caves: some random placements
--      fail canWin, the placer still always returns an accepted one.
--   3. rules under which nothing but the vanilla doors passes, or nothing at
--      all: nil and a report.
--   4. determinism (same rng, any table order), the one-to-one entrance map,
--      every tile of an entrance to one target, one- and two-tile entrances
--      swapped both ways, pools kept apart, fixed and story complexes left
--      alone, and a graph without entrances (one per door).
--   5. a large random world, timed.
--   6. with CRYSTAL_RANDOMIZER_CACHE set to an imported cache's
--      data/generated folder, the real Crystal door graph (mapgraph) at every
--      level, timed.  Its rules accept everything (maprules is separate), so
--      this checks the shape and the time, not winnability.
-- MAPPLACER_SEEDS sets how many seeds each check runs (default 200).
local Rng = dofile("launcher/mods/crystal_randomizer/rng.lua")
local P = dofile("launcher/mods/crystal_randomizer/modules/mapplacer.lua")

local failures, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
  return cond
end
local function eq(a, b, msg) return ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local SEEDS = tonumber(os.getenv("MAPPLACER_SEEDS") or "") or 200

-- ------------------------------------------------------------ a hand-made world
-- Regions R1..Rk in a line; walking from Ri to Ri+1 needs KEYi.  KEYi lies in
-- a complex whose vanilla entrance stands in Ri, so the vanilla game is
-- beatable.  Complexes: houses (INDOOR dead ends), centers, caves (CAVE or
-- DUNGEON, one or two entrances), gates (GATE, two entrances), one fixed gym
-- per region, one story house, one two-entrance INDOOR building.  Every third
-- house, every other cave entrance and the building's first entrance are two
-- tiles wide.
-- opts: regions, houses, caves, gates, keysIn ("houses" | "caves"), seed,
-- caveSpan, deadEndCaves, allDeadEnd, reverse (build the tables in reverse
-- order, to vary pairs order), noEntrances (leave graph.entrances out).
local function makeWorld(opts)
  local gen = Rng.stream("world", opts.seed or 1)
  local k = opts.regions or 4
  local list = {}   -- complexes in creation order: { id, env, kind, regions = { region, ... }, item }
  local function add(id, env, kind, regions, item, extra)
    local c = { id = id, env = env, kind = kind, regions = regions, item = item, wide = {} }
    for key, v in pairs(extra or {}) do c[key] = v end
    list[#list + 1] = c
    return c
  end
  for r = 1, k do add("GYM_" .. r, "INDOOR", "gym", { r }, nil, { fixed = "gym" }) end
  add("ELMS_LAB", "INDOOR", "building", { 1 }, nil, { story = true })
  add("BIG_BUILDING", "INDOOR", "building", { 1, 2 }, nil, { wide = { true } })
  for i = 1, opts.houses or 10 do
    add(("HOUSE_%03d"):format(i), "INDOOR", i % 5 == 0 and "center" or "house", { gen:int(1, k) }, nil,
      { wide = { i % 3 == 0 } })
  end
  for i = 1, opts.caves or 4 do
    local r = gen:int(1, k)
    local r2 = math.min(k, r + gen:int(0, opts.caveSpan or 1))
    -- deadEndCaves: three caves in four have one entrance, so a key inside one
    -- moved behind a locked region strands it (allDeadEnd: every cave)
    local regions = (opts.deadEndCaves and (i % 4 ~= 0 or opts.allDeadEnd)) and { r } or { r, r2 }
    add(("CAVE_%03d"):format(i), i % 3 == 0 and "DUNGEON" or "CAVE", "cave", regions, nil,
      { wide = { i % 2 == 0, i % 2 == 1 } })
  end
  for i = 1, opts.gates or 2 do
    local r = gen:int(1, k)
    add(("GATE_%03d"):format(i), "GATE", "gate", { r, r })
  end
  -- KEYi into a complex of the chosen kind whose first entrance is in Ri.
  if opts.keysIn then
    for i = 1, k - 1 do
      for _, c in ipairs(list) do
        local wanted = (opts.keysIn == "caves" and c.kind == "cave")
          or (opts.keysIn == "houses" and c.kind == "house")
        if wanted and not c.item and c.regions[1] == i then c.item = "KEY" .. i; break end
      end
    end
  end
  -- Keys that found no complex of that kind go to a fixed gym, still beatable.
  local placedKey = {}
  for _, c in ipairs(list) do if c.item then placedKey[c.item] = true end end
  for i = 1, k - 1 do
    if not placedKey["KEY" .. i] then
      for _, c in ipairs(list) do
        if c.id == "GYM_" .. i then c.item = (c.item and c.item .. "," or "") .. "KEY" .. i end
      end
    end
  end

  local graph = { doors = {}, complexes = {}, outdoor = {}, entrances = {} }
  local entranceRegion, fixed = {}, {}
  local order = {}
  for i = 1, #list do order[i] = opts.reverse and list[#list + 1 - i] or list[i] end
  for _, c in ipairs(order) do
    local complex = { id = c.id, maps = { c.id }, environment = c.env, doors = {}, entrances = {},
      deadEnd = #c.regions == 1, story = c.story or false, kind = c.kind, item = c.item }
    local warp = 0
    for n, r in ipairs(c.regions) do
      local tiles = {}
      for _ = 1, c.wide[n] and 2 or 1 do
        warp = warp + 1
        local doorId = ("R%d_%s:%d"):format(r, c.id, warp)
        tiles[#tiles + 1] = doorId
        complex.doors[#complex.doors + 1] = doorId
      end
      local eid = tiles[1]
      local insertOrder = {}
      for i = 1, #tiles do insertOrder[i] = opts.reverse and tiles[#tiles + 1 - i] or tiles[i] end
      for _, doorId in ipairs(insertOrder) do
        graph.doors[doorId] = { id = doorId, map = "R" .. r, warp = warp, complex = c.id, entrance = eid,
          inside = { { map = c.id, warp = n } } }
      end
      graph.entrances[eid] = { id = eid, map = "R" .. r, complex = c.id, doors = tiles,
        inside = { { map = c.id, warp = n } } }
      complex.entrances[#complex.entrances + 1] = eid
      entranceRegion[eid] = "R" .. r
    end
    graph.complexes[c.id] = complex
    if c.fixed then fixed[c.id] = c.fixed end
  end
  if opts.reverse then
    -- churn the hash parts so pairs order differs from the forward build
    for i = 1, 50 do graph.doors["junk" .. i] = true; graph.entrances["junk" .. i] = true end
    for i = 1, 50 do graph.doors["junk" .. i] = nil; graph.entrances["junk" .. i] = nil end
  end
  for r = 1, k do graph.outdoor["R" .. r] = true end
  local entrances = graph.entrances
  if opts.noEntrances then
    -- every door its own entrance, as the placer reads such a graph
    entrances = {}
    for did, door in pairs(graph.doors) do
      entrances[did] = { id = did, complex = door.complex, doors = { did } }
      entranceRegion[did] = door.map
    end
    for _, complex in pairs(graph.complexes) do
      complex.entrances = complex.doors
      complex.deadEnd = #complex.doors == 1
    end
    graph.entrances = nil
    for _, door in pairs(graph.doors) do door.entrance = nil end
  end

  -- canWin: from R1, walk regions (Ri -> Ri+1 needs KEYi), go in at
  -- entrances.  Entrance E leads into the complex of placement.entrances[E];
  -- leaving that complex by its entrance e comes out at the entrance that now
  -- leads to e.  Win: every key held, the last region reached and every
  -- complex entered.  Also rejects a placement whose tiles disagree with its
  -- entrance map, so a split doorway cannot pass.
  local rules = { fixed = fixed, entranceRegion = entranceRegion, entrances = entrances }
  function rules.canWin(placement)
    local map = placement.entrances
    if type(map) ~= "table" then return false, "no entrance map" end
    for eid, e in pairs(entrances) do
      local target = map[eid]
      if not entrances[target] then return false, eid .. " has no target" end
      for _, did in ipairs(e.doors) do
        if placement[did] ~= entrances[target].doors[1] then return false, did .. " split" end
      end
    end
    local inverse = {}
    for from, to in pairs(map) do inverse[to] = from end
    local regions, complexes, have = { R1 = true }, {}, {}
    local changed = true
    while changed do
      changed = false
      for r = 1, k - 1 do
        if regions["R" .. r] and have["KEY" .. r] and not regions["R" .. (r + 1)] then
          regions["R" .. (r + 1)] = true; changed = true
        end
      end
      for eid, e in pairs(entrances) do
        if regions[entranceRegion[eid]] then
          local inside = graph.complexes[entrances[map[eid]].complex]
          if not complexes[inside.id] then
            complexes[inside.id] = true
            changed = true
            for key in tostring(inside.item or ""):gmatch("[^,]+") do have[key] = true end
            for _, other in ipairs(inside.entrances) do
              regions[entranceRegion[inverse[other] or other]] = true
            end
          end
        end
      end
    end
    for r = 1, k - 1 do if not have["KEY" .. r] then return false, "KEY" .. r .. " unreachable" end end
    if not regions["R" .. k] then return false, "R" .. k .. " unreachable" end
    for id in pairs(graph.complexes) do
      if not complexes[id] then return false, id .. " unreachable" end
    end
    return true
  end
  return graph, rules
end

-- ------------------------------------------------------------ independent checks

local function sorted(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

-- The pool an entrance should be in, written apart from P.poolFor.
local function expectedPool(graph, rules, entrance, level)
  local c = graph.complexes[entrance.complex]
  if not c or rules.fixed[c.id] or c.story then return nil end
  if level == "full" then return "all" end
  if c.environment == "INDOOR" and c.deadEnd then return "houses" end
  if level == "caves" and (c.environment == "CAVE" or c.environment == "DUNGEON") then return "caves" end
  return nil
end

-- Counts of moves by tile width ("1>2" = a one-tile entrance now leads where
-- a two-tile one led), summed across calls.
local widthMoves = {}

-- entrances: the graph's entrance table as the placer should read it.
local function checkPlacement(graph, rules, level, placement, label, entrances, realRules)
  entrances = entrances or rules.entrances
  local good = true
  local function check(cond, msg) good = ok(cond, label .. ": " .. msg) and good end
  local map = placement.entrances
  check(type(map) == "table", "placement.entrances is a table")
  if type(map) ~= "table" then return false end
  local seen = {}
  for _, eid in ipairs(sorted(entrances)) do
    local e = entrances[eid]
    local target = map[eid]
    check(target ~= nil and entrances[target] ~= nil, eid .. " has a target entrance")
    if target and entrances[target] then
      check(not seen[target], target .. " is the target of one entrance only")
      seen[target] = true
      local rep = entrances[target].doors[1]
      for _, did in ipairs(e.doors) do
        if placement[did] ~= rep then check(false, did .. " leads to " .. tostring(placement[did])
          .. ", not " .. rep .. " (its entrance's target)") end
      end
      local pool = expectedPool(graph, rules, e, level)
      if pool == nil then
        if target ~= eid then check(false, "immovable " .. eid .. " stays") end
      elseif expectedPool(graph, rules, entrances[target], level) ~= pool then
        check(false, eid .. " swaps within " .. pool)
      end
      if target ~= eid then
        local key = #e.doors .. ">" .. #entrances[target].doors
        widthMoves[key] = (widthMoves[key] or 0) + 1
      end
    end
  end
  for key in pairs(placement) do
    if key ~= "entrances" and graph.doors[key] == nil then check(false, "no stray key " .. tostring(key)) end
  end
  for key in pairs(map) do
    if entrances[key] == nil then check(false, "no stray entrance " .. tostring(key)) end
  end
  for did in pairs(graph.doors) do
    if placement[did] == nil then check(false, did .. " has a target") end
  end
  check((realRules or rules).canWin(placement), "canWin accepts the result")
  return good
end

local function same(a, b)
  for k, v in pairs(a) do
    if type(v) == "table" then
      if type(b[k]) ~= "table" or not same(v, b[k]) then return false end
    elseif b[k] ~= v then return false end
  end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- A placement built here from an entrance map (independent of P's expand).
local function placementFrom(entrances, map)
  local p = { entrances = {} }
  for eid, e in pairs(entrances) do
    local target = map[eid] or eid
    p.entrances[eid] = target
    for _, did in ipairs(e.doors) do p[did] = entrances[target].doors[1] end
  end
  return p
end

local function shuffledPools(entrances, pools, names, gen)
  local map = {}
  for _, name in ipairs(names) do
    local t = gen:shuffled(pools[name])
    for i, eid in ipairs(pools[name]) do map[eid] = t[i] end
  end
  return placementFrom(entrances, map)
end

-- ------------------------------------------------------------ 1. houses never strand

do
  local graph, rules = makeWorld({ regions = 5, houses = 40, caves = 6, keysIn = "caves" })
  ok(rules.canWin(placementFrom(rules.entrances, {})), "houses world: vanilla is beatable")
  local pools, names = P.pools(graph, rules, "houses")
  local housePool = pools.houses
  ok(housePool and #housePool >= 30, "houses world: the house pool has the dead-end houses")
  -- direct: random permutations of the house pool always pass
  local gen = Rng.stream("houses-direct")
  local allPass = true
  for _ = 1, SEEDS do
    if not rules.canWin(shuffledPools(rules.entrances, pools, names, gen)) then allPass = false end
  end
  ok(allPass, "houses: every random house shuffle passes canWin")
  local good = true
  for s = 1, SEEDS do
    local placement, report = P.place(graph, rules, "houses", Rng.stream("seed", s, "maps"))
    good = ok(placement ~= nil, "houses seed " .. s .. " placed (" .. tostring(report.reason) .. ")") and good
    if placement then
      good = checkPlacement(graph, rules, "houses", placement, "houses seed " .. s) and good
      good = eq(report.phase, "shuffle", "houses seed " .. s .. ": phase") and good
      good = eq(report.shuffles, 1, "houses seed " .. s .. ": first whole shuffle accepted") and good
      good = eq(report.calls, 2, "houses seed " .. s .. ": vanilla check plus one") and good
      good = ok(report.moved > #housePool / 2, "houses seed " .. s .. ": most houses moved") and good
      good = eq(report.pools.caves, nil, "houses seed " .. s .. ": caves do not move") and good
    end
    if not good then break end
  end
end

-- ------------------------------------------------------------ 2. some placements fail

local strictSmall = { regions = 5, houses = 30, caves = 10, gates = 3, keysIn = "caves", seed = 7,
  caveSpan = 0, deadEndCaves = true }
for _, level in ipairs({ "caves", "full" }) do
  local graph, rules = makeWorld(strictSmall)
  local pools, names = P.pools(graph, rules, level)
  -- direct: some whole shuffles pass, some fail
  local gen = Rng.stream("direct", level)
  local pass, fail = 0, 0
  for _ = 1, SEEDS do
    if rules.canWin(shuffledPools(rules.entrances, pools, names, gen)) then pass = pass + 1 else fail = fail + 1 end
  end
  ok(fail > 0, level .. ": some whole shuffles fail canWin (" .. fail .. " of " .. SEEDS .. ")")
  print(("%s: %d of %d random whole shuffles pass canWin"):format(level, pass, SEEDS))
  local phases, good = {}, true
  local totalMoved, movable = 0, 0
  for s = 1, SEEDS do
    local placement, report = P.place(graph, rules, level, Rng.stream("seed", s, "maps"))
    good = ok(placement ~= nil, level .. " seed " .. s .. " placed (" .. tostring(report.reason) .. ")") and good
    if placement then
      good = checkPlacement(graph, rules, level, placement, level .. " seed " .. s) and good
      good = ok(report.calls <= P.LIMITS.calls, level .. " seed " .. s .. ": within the call bound") and good
      phases[report.phase] = (phases[report.phase] or 0) + 1
      totalMoved, movable = totalMoved + report.moved, report.movable
    end
    if not good then break end
  end
  print(("%s: phases shuffle=%d grow=%d, mean entrances moved %.1f of %d movable"):format(level,
    phases.shuffle or 0, phases.grow or 0, totalMoved / SEEDS, movable))
  if level == "caves" then
    ok(pools.houses and pools.caves, "caves: houses and caves are separate pools")
  else
    ok(pools.all and not pools.houses, "full: one pool")
  end
end

-- The grow phase on its own: no whole shuffle is allowed, so it must grow.
do
  local graph, rules = makeWorld(strictSmall)
  local saved = P.LIMITS.shuffles
  P.LIMITS.shuffles = 0
  local placement, report = P.place(graph, rules, "full", Rng.stream("grow-only"))
  P.LIMITS.shuffles = saved
  if ok(placement ~= nil, "grow only: placed (" .. tostring(report.reason) .. ")") then
    eq(report.phase, "grow", "grow only: phase")
    checkPlacement(graph, rules, "full", placement, "grow only")
    ok(report.moved > 10, "grow only: many entrances moved (" .. report.moved .. ")")
  end
end

-- Houses that hold a key can strand: the placer still only returns placements
-- canWin accepts (the "houses never strand" claim holds only while the rules
-- fix or model every house that holds something the story needs).
do
  local graph, rules = makeWorld({ regions = 5, houses = 20, caves = 2, keysIn = "houses", seed = 3 })
  local good = true
  for s = 1, math.min(SEEDS, 50) do
    local placement, report = P.place(graph, rules, "houses", Rng.stream("kh", s))
    good = ok(placement ~= nil, "key houses seed " .. s .. " placed (" .. tostring(report.reason) .. ")") and good
    if placement then good = checkPlacement(graph, rules, "houses", placement, "key houses " .. s) and good end
    if not good then break end
  end
end

-- ------------------------------------------------------------ 3. nothing passes

do
  local graph, rules = makeWorld({ regions = 3, houses = 10, caves = 3 })
  local function vanillaOnly(p)
    for k, v in pairs(p.entrances) do if k ~= v then return false, "an entrance moved" end end
    return true
  end
  local placement, report = P.place(graph, { fixed = rules.fixed, canWin = vanillaOnly }, "full", Rng.stream("none"))
  eq(placement, nil, "only vanilla passes: nothing placed")
  ok(type(report.reason) == "string" and report.reason:find("no shuffled placement", 1, true),
    "only vanilla passes: report says why (" .. tostring(report.reason) .. ")")
  ok(report.calls <= P.LIMITS.calls, "only vanilla passes: within the call bound (" .. report.calls .. ")")
  print(("only vanilla passes: %d canWin calls, %.3f s"):format(report.calls, report.seconds))

  local never = { fixed = rules.fixed, canWin = function() return false, "never" end }
  placement, report = P.place(graph, never, "houses", Rng.stream("none"))
  eq(placement, nil, "nothing passes: nothing placed")
  ok(report.reason and report.reason:find("vanilla doors fail", 1, true), "nothing passes: vanilla named")
  eq(report.calls, 1, "nothing passes: stops after the vanilla check")

  local calls = 0
  local capped = { fixed = rules.fixed, canWin = function(p) calls = calls + 1; return vanillaOnly(p) end }
  local saved = P.LIMITS.calls
  P.LIMITS.calls = 25
  placement, report = P.place(graph, capped, "full", Rng.stream("cap"))
  P.LIMITS.calls = saved
  eq(placement, nil, "call cap: nothing placed")
  ok(calls <= 25, "call cap: canWin called at most 25 times (" .. calls .. ")")

  placement = P.place(graph, rules, "off", Rng.stream("x"))
  eq(placement, nil, "level off: nothing placed")
  placement = P.place(graph, rules, "bogus", Rng.stream("x"))
  eq(placement, nil, "unknown level: nothing placed")
  placement = P.place(graph, { fixed = {} }, "full", Rng.stream("x"))
  eq(placement, nil, "no canWin: nothing placed")

  -- everything fixed: fewer than two movable entrances
  local allFixed = { fixed = {}, canWin = rules.canWin }
  for id in pairs(graph.complexes) do allFixed.fixed[id] = "test" end
  placement, report = P.place(graph, allFixed, "full", Rng.stream("x"))
  eq(placement, nil, "everything fixed: nothing placed")
  eq(report.movable, 0, "everything fixed: no movable entrance")
end

-- ------------------------------------------------------------ 4. determinism, entrances, fixed doors

do
  local opts = { regions = 5, houses = 30, caves = 10, gates = 3, keysIn = "caves", seed = 11 }
  local g1, r1 = makeWorld(opts)
  opts.reverse = true
  local g2, r2 = makeWorld(opts)
  local differ = 0
  for _, level in ipairs({ "houses", "caves", "full" }) do
    local prev
    for s = 1, 20 do
      local a = P.place(g1, r1, level, Rng.stream("det", s))
      local b = P.place(g1, r1, level, Rng.stream("det", s))
      local c = P.place(g2, r2, level, Rng.stream("det", s))
      ok(a and b and same(a, b), level .. " seed " .. s .. ": same rng, same placement")
      ok(a and c and same(a, c), level .. " seed " .. s .. ": other table order, same placement")
      if prev and a and not same(prev, a) then differ = differ + 1 end
      prev = a
    end
  end
  ok(differ > 50, "different seeds give different placements (" .. differ .. " of 57)")

  -- one- and two-tile entrances swap both ways (counted over every check so far)
  ok((widthMoves["1>2"] or 0) > 0, "a one-tile entrance leads where a two-tile one led (" .. tostring(widthMoves["1>2"]) .. ")")
  ok((widthMoves["2>1"] or 0) > 0, "a two-tile entrance leads where a one-tile one led (" .. tostring(widthMoves["2>1"]) .. ")")
  ok((widthMoves["2>2"] or 0) > 0, "two-tile entrances swap with each other (" .. tostring(widthMoves["2>2"]) .. ")")
  local placement = P.place(g1, r1, "full", Rng.stream("wide"))
  local wideMoved = 0
  for eid, e in pairs(r1.entrances) do
    if #e.doors == 2 and placement.entrances[eid] ~= eid then
      wideMoved = wideMoved + 1
      eq(placement[e.doors[1]], placement[e.doors[2]], "both tiles of " .. eid .. " lead to one place")
      ok(placement[e.doors[2]] ~= e.doors[2], "the second tile of " .. eid .. " moved with the first")
    end
  end
  ok(wideMoved > 5, "full: two-tile entrances moved (" .. wideMoved .. ")")

  -- fixed and story complexes
  for eid, e in pairs(r1.entrances) do
    local c = g1.complexes[e.complex]
    if r1.fixed[c.id] or c.story then
      eq(placement.entrances[eid], eid, "full: fixed entrance " .. eid .. " stays")
      for _, did in ipairs(e.doors) do eq(placement[did], did, "full: fixed door " .. did .. " stays") end
      for other, target in pairs(placement.entrances) do
        if target == eid then eq(other, eid, "full: nothing else leads into fixed " .. eid) end
      end
    end
  end
  -- the input graph is left alone
  local g3 = makeWorld({ regions = 5, houses = 30, caves = 10, gates = 3, keysIn = "caves", seed = 11 })
  ok(same(g1.entrances, g3.entrances) and same(g1.doors, g3.doors), "the graph is not changed")

  -- a graph without entrances: one entrance per door
  local g4, r4 = makeWorld({ regions = 5, houses = 30, caves = 10, gates = 3, keysIn = "caves", seed = 11,
    noEntrances = true })
  local p4, rep4 = P.place(g4, r4, "full", Rng.stream("noent"))
  if ok(p4 ~= nil, "no entrances: placed (" .. tostring(rep4.reason) .. ")") then
    checkPlacement(g4, r4, "full", p4, "no entrances")
    local doors = 0
    for _ in pairs(g4.doors) do doors = doors + 1 end
    local n = 0
    for _ in pairs(p4.entrances) do n = n + 1 end
    eq(n, doors, "no entrances: one entrance per door")
  end

  -- install
  local ctx = { lib = {}, shared = {} }
  P.install({}, ctx)
  ok(ctx.lib.mapPlacer and ctx.lib.mapPlacer.place == P.place, "install sets ctx.lib.mapPlacer.place")
  eq(#P.questions, 0, "no questions")
  local n = 0
  for _ in pairs(ctx.shared) do n = n + 1 end
  eq(n, 0, "install writes nothing to ctx.shared")
end

-- ------------------------------------------------------------ 5. a large random world, timed

-- "loose": two-entrance gates and caves link regions, so most whole shuffles
-- pass.  "strict": every cave a dead end and no gates, so a whole shuffle
-- almost never passes and the grow phase does the work (the slow case).
for _, world in ipairs({
  { name = "loose", opts = { regions = 12, houses = 450, caves = 60, gates = 40, keysIn = "caves", seed = 99,
    caveSpan = 0, deadEndCaves = true } },
  { name = "strict", opts = { regions = 12, houses = 450, caves = 60, gates = 0, keysIn = "caves", seed = 99,
    caveSpan = 0, deadEndCaves = true, allDeadEnd = true } },
}) do
  local graph, rules = makeWorld(world.opts)
  local doors, entranceCount = 0, 0
  for _ in pairs(graph.doors) do doors = doors + 1 end
  for _ in pairs(graph.entrances) do entranceCount = entranceCount + 1 end
  local probe = os.clock()
  local identity = placementFrom(rules.entrances, {})
  for _ = 1, 20 do rules.canWin(identity) end
  print(("large %s world: one canWin call takes %.4f s"):format(world.name, (os.clock() - probe) / 20))
  for _, level in ipairs({ "houses", "caves", "full" }) do
    local worst, total, grows, n = 0, 0, 0, 10
    local worstCalls, fewestMoved, movable = 0, math.huge, 0
    for s = 1, n do
      local placement, report = P.place(graph, rules, level, Rng.stream("big", s))
      ok(placement ~= nil, "large " .. level .. " seed " .. s .. " placed (" .. tostring(report.reason) .. ")")
      if placement then
        checkPlacement(graph, rules, level, placement, "large " .. level .. " " .. s)
        fewestMoved = math.min(fewestMoved, report.moved)
      end
      worst = math.max(worst, report.seconds)
      worstCalls = math.max(worstCalls, report.calls)
      total = total + report.seconds
      movable = report.movable
      if report.phase == "grow" then grows = grows + 1 end
    end
    print(("large %s world (%d doors, %d entrances), %s: mean %.3f s, worst %.3f s, worst %d canWin calls, "
      .. "%d of %d grew, fewest moved %d of %d"):format(world.name, doors, entranceCount, level, total / n, worst,
      worstCalls, grows, n, fewestMoved, movable))
    ok(worst < 5, "large " .. level .. ": worst under 5 s (" .. worst .. ")")
  end
end

-- ------------------------------------------------------------ 6. the real Crystal door graph

local cache = os.getenv("CRYSTAL_RANDOMIZER_CACHE")
if cache and cache ~= "" then
  local Graph = dofile("launcher/mods/crystal_randomizer/modules/mapgraph.lua")._M
  local graph = Graph.build({ gen2Maps = dofile(cache .. "/maps.lua") })
  local doors, entranceCount, wide = 0, 0, 0
  for _ in pairs(graph.doors) do doors = doors + 1 end
  for _, e in pairs(graph.entrances) do
    entranceCount = entranceCount + 1
    if #e.doors > 1 then wide = wide + 1 end
  end
  print(("real Crystal graph: %d doors, %d entrances, %d wider than one tile"):format(doors, entranceCount, wide))
  ok(wide > 0, "real: some entrances have more than one tile")
  for _, pair in ipairs({ { "AZALEA_TOWN:7", "AZALEA_TOWN:8" }, { "ROUTE_23:1", "ROUTE_23:2" },
      { "BATTLE_TOWER_OUTSIDE:3", "BATTLE_TOWER_OUTSIDE:4" } }) do
    local a, b = graph.doors[pair[1]], graph.doors[pair[2]]
    ok(a and b and a.entrance == b.entrance, "real: " .. pair[1] .. " and " .. pair[2] .. " are one entrance")
  end
  -- every door its entrance's tile, entrance ids in graph.entranceOrder
  local real = P.entrances(graph)
  for did, door in pairs(graph.doors) do
    ok(real[door.entrance] ~= nil, "real: " .. did .. " belongs to a listed entrance")
  end
  -- rules: no complex fixed (maprules owns that list) except a few to check
  -- they stay; canWin accepts everything, so only the shape is checked here.
  local fixed = { ELMS_LAB = "test", ILEX_FOREST_AZALEA_GATE = "test", INDIGO_PLATEAU_POKECENTER_1F = "test" }
  local calls = 0
  local rules = { fixed = fixed, canWin = function(p) calls = calls + 1; return type(p.entrances) == "table" end }
  local checker = { fixed = fixed, canWin = function() return true end }
  for _, level in ipairs({ "houses", "caves", "full" }) do
    local worst, n = 0, math.min(SEEDS, 20)
    local first
    for s = 1, n do
      local placement, report = P.place(graph, rules, level, Rng.stream("real", s))
      if ok(placement ~= nil, "real " .. level .. " seed " .. s .. " placed (" .. tostring(report.reason) .. ")") then
        checkPlacement(graph, checker, level, placement, "real " .. level .. " " .. s, real)
        for cid in pairs(fixed) do
          for _, eid in ipairs(graph.complexes[cid] and graph.complexes[cid].entrances or {}) do
            eq(placement.entrances[eid], eid, "real " .. level .. ": fixed " .. cid .. " stays")
          end
        end
        local again = P.place(graph, rules, level, Rng.stream("real", s))
        ok(again and same(placement, again), "real " .. level .. " seed " .. s .. ": deterministic")
        worst = math.max(worst, report.seconds)
        first = first or report
      end
    end
    if first then
      local poolText = {}
      for _, name in ipairs(sorted(first.pools)) do poolText[#poolText + 1] = name .. "=" .. first.pools[name] end
      print(("real %s: pools %s; seed 1 moved %d entrances (%d doors); worst placer time %.4f s "
        .. "(rules accept everything)"):format(level, table.concat(poolText, " "), first.moved, first.movedDoors, worst))
    end
  end
  print("real Crystal data checked: " .. cache)
else
  print("  (set CRYSTAL_RANDOMIZER_CACHE to an imported cache's data/generated folder to check real data)")
end

print(("mapplacer: %d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
