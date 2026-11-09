-- luajit launcher/mods/crystal_randomizer/tests/mapplacer_test.lua   (from the repository root)
--
-- The placer against hand-made graphs and rules in the MAPS.md shapes (the
-- real mapgraph and maprules are written separately):
--   1. houses: dead ends cannot strand, so every shuffle passes and the first
--      whole shuffle is used.
--   2. caves and full, where key items sit in caves: some random placements
--      fail canWin, the placer still always returns an accepted one.
--   3. rules under which nothing but the vanilla doors passes, or nothing at
--      all: nil and a report.
--   4. determinism (same rng, any table order), the one-to-one swap, pools
--      kept apart, fixed and story complexes left alone.
--   5. a large random world, timed.
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
-- a complex whose vanilla door stands in Ri, so the vanilla game is beatable.
-- Complexes: houses (INDOOR dead ends), centers, caves (CAVE, two doors, in
-- the same or neighbouring regions, or dead-end caves), gates (GATE, two doors), one fixed gym
-- per region, one story house, one two-door INDOOR building.
-- opts: regions, houses, caves, gates, keysIn ("houses" | "caves"), seed,
-- reverse (insert into the tables in reverse order, to vary pairs order).
local function makeWorld(opts)
  local gen = Rng.stream("world", opts.seed or 1)
  local k = opts.regions or 4
  local list = {}   -- complexes in creation order: { id, env, kind, doors = { region, ... }, item }
  local function add(id, env, kind, regions, item, extra)
    local c = { id = id, env = env, kind = kind, regions = regions, item = item }
    for key, v in pairs(extra or {}) do c[key] = v end
    list[#list + 1] = c
    return c
  end
  for r = 1, k do add("GYM_" .. r, "INDOOR", "gym", { r }, nil, { fixed = "gym" }) end
  add("ELMS_LAB", "INDOOR", "building", { 1 }, nil, { story = true })
  add("BIG_BUILDING", "INDOOR", "building", { 1, 2 })
  for i = 1, opts.houses or 10 do
    add(("HOUSE_%03d"):format(i), "INDOOR", i % 5 == 0 and "center" or "house", { gen:int(1, k) })
  end
  local caves = {}
  for i = 1, opts.caves or 4 do
    local r = gen:int(1, k)
    local r2 = math.min(k, r + gen:int(0, opts.caveSpan or 1))
    -- deadEndCaves: three caves in four have one door, so a key inside one
    -- moved behind a locked region strands it (allDeadEnd: every cave)
    local regions = (opts.deadEndCaves and (i % 4 ~= 0 or opts.allDeadEnd)) and { r } or { r, r2 }
    caves[#caves + 1] = add(("CAVE_%03d"):format(i), i % 3 == 0 and "DUNGEON" or "CAVE", "cave", regions)
  end
  for i = 1, opts.gates or 2 do
    local r = gen:int(1, k)
    add(("GATE_%03d"):format(i), "GATE", "gate", { r, r })
  end
  -- KEYi into a complex of the chosen kind whose first door is in Ri.
  for i = 1, k - 1 do
    for _, c in ipairs(list) do
      local wanted = (opts.keysIn == "caves" and c.kind == "cave")
        or (opts.keysIn == "houses" and c.kind == "house")
      if wanted and not c.item and c.regions[1] == i then c.item = "KEY" .. i; break end
    end
    if not opts.keysIn then break end
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

  local graph = { doors = {}, complexes = {}, outdoor = {} }
  local doorRegion, fixed = {}, {}
  local order = {}
  for i = 1, #list do order[i] = opts.reverse and list[#list + 1 - i] or list[i] end
  for _, c in ipairs(order) do
    local complex = { id = c.id, maps = { c.id }, environment = c.env, doors = {},
      deadEnd = #c.regions == 1, story = c.story or false, kind = c.kind, item = c.item }
    for n, r in ipairs(c.regions) do
      local doorId = ("R%d_%s:%d"):format(r, c.id, n)
      graph.doors[doorId] = { id = doorId, map = "R" .. r, warp = n, complex = c.id,
        inside = { { map = c.id, warp = n } } }
      complex.doors[#complex.doors + 1] = doorId
      doorRegion[doorId] = "R" .. r
    end
    graph.complexes[c.id] = complex
    if c.fixed then fixed[c.id] = c.fixed end
  end
  if opts.reverse then
    -- churn the hash part so pairs order differs from the forward build
    for i = 1, 50 do graph.doors["junk" .. i] = true end
    for i = 1, 50 do graph.doors["junk" .. i] = nil end
  end
  for r = 1, k do graph.outdoor["R" .. r] = true end

  -- canWin: from R1, walk regions (Ri -> Ri+1 needs KEYi), enter doors.  Door
  -- A leads into the complex of placement[A]; leaving that complex by its
  -- door d comes out at the door that now leads to d.  Win: every key held,
  -- the last region reached and every complex entered.
  local rules = { fixed = fixed, doorRegion = doorRegion }
  function rules.canWin(placement)
    local inverse = {}
    for door, target in pairs(placement) do inverse[target] = door end
    local regions, complexes, have = { R1 = true }, {}, {}
    local changed = true
    while changed do
      changed = false
      for r = 1, k - 1 do
        if regions["R" .. r] and have["KEY" .. r] and not regions["R" .. (r + 1)] then
          regions["R" .. (r + 1)] = true; changed = true
        end
      end
      for doorId, door in pairs(graph.doors) do
        if regions[doorRegion[doorId]] then
          local inside = graph.complexes[graph.doors[placement[doorId] or doorId].complex]
          if not complexes[inside.id] then
            complexes[inside.id] = true
            changed = true
            for key in tostring(inside.item or ""):gmatch("[^,]+") do have[key] = true end
            for _, d in ipairs(inside.doors) do
              local out = doorRegion[inverse[d] or d]
              if not regions[out] then regions[out] = true end
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

-- The pool a door should be in, written apart from P.poolFor.
local function expectedPool(graph, rules, doorId, level)
  local c = graph.complexes[graph.doors[doorId].complex]
  if rules.fixed[c.id] or c.story then return nil end
  if level == "full" then return "all" end
  if c.environment == "INDOOR" and #c.doors == 1 then return "houses" end
  if level == "caves" and (c.environment == "CAVE" or c.environment == "DUNGEON") then return "caves" end
  return nil
end

local function checkPlacement(graph, rules, level, placement, label)
  local seen, good = {}, true
  for doorId in pairs(graph.doors) do
    local target = placement[doorId]
    good = ok(target ~= nil and graph.doors[target] ~= nil, label .. ": " .. doorId .. " has a target") and good
    if target then
      good = ok(not seen[target], label .. ": " .. target .. " is the target of one door only") and good
      seen[target] = true
      local pool = expectedPool(graph, rules, doorId, level)
      if pool == nil then
        good = eq(target, doorId, label .. ": immovable " .. doorId .. " stays") and good
      else
        good = eq(expectedPool(graph, rules, target, level), pool,
          label .. ": " .. doorId .. " swaps within " .. pool) and good
      end
    end
  end
  for k in pairs(placement) do
    good = ok(graph.doors[k] ~= nil, label .. ": no stray key " .. tostring(k)) and good
  end
  good = ok(rules.canWin(placement), label .. ": canWin accepts the result") and good
  return good
end

local function same(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end

local function moved(p) local n = 0 for k, v in pairs(p) do if k ~= v then n = n + 1 end end return n end

-- ------------------------------------------------------------ 1. houses never strand

do
  local graph, rules = makeWorld({ regions = 5, houses = 40, caves = 6, keysIn = "caves" })
  ok(rules.canWin((function() local v = {} for id in pairs(graph.doors) do v[id] = id end return v end)()),
    "houses world: vanilla is beatable")
  local pools = P.pools(graph, rules, "houses")
  local housePool = pools.houses
  ok(housePool and #housePool >= 30, "houses world: the house pool has the dead-end houses")
  -- direct: random permutations of the house pool always pass
  local gen = Rng.stream("houses-direct")
  local allPass = true
  for _ = 1, SEEDS do
    local p = {}
    for id in pairs(graph.doors) do p[id] = id end
    local t = gen:shuffled(housePool)
    for i, d in ipairs(housePool) do p[d] = t[i] end
    if not rules.canWin(p) then allPass = false end
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

for _, level in ipairs({ "caves", "full" }) do
  local graph, rules = makeWorld({ regions = 5, houses = 30, caves = 10, gates = 3, keysIn = "caves", seed = 7, caveSpan = 0, deadEndCaves = true })
  local pools, names = P.pools(graph, rules, level)
  -- direct: some whole shuffles pass, some fail
  local gen = Rng.stream("direct", level)
  local pass, fail = 0, 0
  for _ = 1, SEEDS do
    local p = {}
    for id in pairs(graph.doors) do p[id] = id end
    for _, name in ipairs(names) do
      local t = gen:shuffled(pools[name])
      for i, d in ipairs(pools[name]) do p[d] = t[i] end
    end
    if rules.canWin(p) then pass = pass + 1 else fail = fail + 1 end
  end
  ok(fail > 0, level .. ": some whole shuffles fail canWin (" .. fail .. " of " .. SEEDS .. ")")
  print(("%s: %d of %d random whole shuffles pass canWin"):format(level, pass, SEEDS))
  local phases, good = {}, true
  local totalMoved = 0
  for s = 1, SEEDS do
    local placement, report = P.place(graph, rules, level, Rng.stream("seed", s, "maps"))
    good = ok(placement ~= nil, level .. " seed " .. s .. " placed (" .. tostring(report.reason) .. ")") and good
    if placement then
      good = checkPlacement(graph, rules, level, placement, level .. " seed " .. s) and good
      good = ok(report.calls <= P.LIMITS.calls, level .. " seed " .. s .. ": within the call bound") and good
      phases[report.phase] = (phases[report.phase] or 0) + 1
      totalMoved = totalMoved + report.moved
    end
    if not good then break end
  end
  print(("%s: phases shuffle=%d grow=%d, mean doors moved %.1f of %d movable"):format(level,
    phases.shuffle or 0, phases.grow or 0, totalMoved / SEEDS, P.pools and (function()
      local n = 0 for _, l in pairs(pools) do n = n + #l end return n end)()))
  if level == "caves" then
    ok(pools.houses and pools.caves, "caves: houses and caves are separate pools")
  else
    ok(pools.all and not pools.houses, "full: one pool")
  end
end

-- The grow phase on its own: no whole shuffle is allowed, so it must grow.
do
  local graph, rules = makeWorld({ regions = 5, houses = 30, caves = 10, gates = 3, keysIn = "caves", seed = 7, caveSpan = 0, deadEndCaves = true })
  local saved = P.LIMITS.shuffles
  P.LIMITS.shuffles = 0
  local placement, report = P.place(graph, rules, "full", Rng.stream("grow-only"))
  P.LIMITS.shuffles = saved
  if ok(placement ~= nil, "grow only: placed (" .. tostring(report.reason) .. ")") then
    eq(report.phase, "grow", "grow only: phase")
    checkPlacement(graph, rules, "full", placement, "grow only")
    ok(report.moved > 10, "grow only: many doors moved (" .. report.moved .. ")")
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
  local onlyVanilla = { fixed = rules.fixed, canWin = function(p)
    for k, v in pairs(p) do if k ~= v then return false, "a door moved" end end
    return true
  end }
  local placement, report = P.place(graph, onlyVanilla, "full", Rng.stream("none"))
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
  local capped = { fixed = rules.fixed, canWin = function(p)
    calls = calls + 1
    for k, v in pairs(p) do if k ~= v then return false end end
    return true
  end }
  local saved = P.LIMITS.calls
  P.LIMITS.calls = 25
  placement, report = P.place(graph, capped, "full", Rng.stream("cap"))
  P.LIMITS.calls = saved
  eq(placement, nil, "call cap: nothing placed")
  ok(calls <= 25, "call cap: canWin called at most 25 times (" .. calls .. ")")

  placement, report = P.place(graph, rules, "off", Rng.stream("x"))
  eq(placement, nil, "level off: nothing placed")
  placement, report = P.place(graph, rules, "bogus", Rng.stream("x"))
  eq(placement, nil, "unknown level: nothing placed")
  placement, report = P.place(graph, { fixed = {} }, "full", Rng.stream("x"))
  eq(placement, nil, "no canWin: nothing placed")

  -- everything fixed: fewer than two movable doors
  local allFixed = { fixed = {}, canWin = rules.canWin }
  for id in pairs(graph.complexes) do allFixed.fixed[id] = "test" end
  placement, report = P.place(graph, allFixed, "full", Rng.stream("x"))
  eq(placement, nil, "everything fixed: nothing placed")
  eq(report.movable, 0, "everything fixed: no movable door")
end

-- ------------------------------------------------------------ 4. determinism, fixed doors

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

  -- fixed and story complexes
  local placement = P.place(g1, r1, "full", Rng.stream("fixed"))
  for id, door in pairs(g1.doors) do
    local c = g1.complexes[door.complex]
    if r1.fixed[c.id] or c.story then
      eq(placement[id], id, "full: fixed door " .. id .. " stays")
      for other, target in pairs(placement) do
        if target == id then eq(other, id, "full: nothing else leads into fixed " .. id) end
      end
    end
  end
  -- the input graph is left alone
  local count = 0
  for _ in pairs(g1.doors) do count = count + 1 end
  local g3 = makeWorld({ regions = 5, houses = 30, caves = 10, gates = 3, keysIn = "caves", seed = 11 })
  local count3 = 0
  for _ in pairs(g3.doors) do count3 = count3 + 1 end
  eq(count, count3, "the graph is not changed")

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

-- "loose": two-door gates and caves link regions, so most whole shuffles pass.
-- "strict": every cave a dead end and no gates, so a whole shuffle almost
-- never passes and the grow phase does the work (the slow case).
for _, world in ipairs({
  { name = "loose", opts = { regions = 12, houses = 450, caves = 60, gates = 40, keysIn = "caves", seed = 99,
    caveSpan = 0, deadEndCaves = true } },
  { name = "strict", opts = { regions = 12, houses = 450, caves = 60, gates = 0, keysIn = "caves", seed = 99,
    caveSpan = 0, deadEndCaves = true, allDeadEnd = true } },
}) do
  local graph, rules = makeWorld(world.opts)
  local doors = 0
  for _ in pairs(graph.doors) do doors = doors + 1 end
  local probe = os.clock()
  local identity = {}
  for id in pairs(graph.doors) do identity[id] = id end
  for _ = 1, 20 do rules.canWin(identity) end
  print(("large %s world: one canWin call takes %.4f s"):format(world.name, (os.clock() - probe) / 20))
  for _, level in ipairs({ "houses", "caves", "full" }) do
    local worst, total, grows, n = 0, 0, 0, 10
    local worstCalls, fewestMoved = 0, math.huge
    for s = 1, n do
      local placement, report = P.place(graph, rules, level, Rng.stream("big", s))
      ok(placement ~= nil, "large " .. level .. " seed " .. s .. " placed (" .. tostring(report.reason) .. ")")
      if placement then checkPlacement(graph, rules, level, placement, "large " .. level .. " " .. s) end
      worst = math.max(worst, report.seconds)
      worstCalls = math.max(worstCalls, report.calls)
      if placement then fewestMoved = math.min(fewestMoved, report.moved) end
      total = total + report.seconds
      if report.phase == "grow" then grows = grows + 1 end
    end
    print(("large " .. world.name .. " world (%d doors), %s: mean %.3f s, worst %.3f s, worst %d canWin calls, %d of %d grew, fewest moved %d of %d")
      :format(doors, level, total / n, worst, worstCalls, grows, n, fewestMoved, P.place(graph, rules, level, Rng.stream("big", 1)) and select(2, P.place(graph, rules, level, Rng.stream("big", 1))).movable or 0))
    ok(worst < 5, "large " .. level .. ": worst under 5 s (" .. worst .. ")")
  end
end

print(("mapplacer: %d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
