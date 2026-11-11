-- luajit launcher/mods/crystal_randomizer/tests/maps_test.lua   (from the repository root)
--
-- The maps module applies a placement; the graph, rules and placer come from
-- ctx.lib.  Here they are stubs written in this file, over a small synthetic
-- world shaped like Crystal's warp tables, with one- and two-tile doorways
-- (entrances, as the real mapgraph groups them):
--   TOWN_A (TOWN)  warps 1+4, two tiles -> HOUSE_1; both mat warps explicit back
--                                to TOWN_A:1 only (tile 4 is enter-only, like CELADON_CITY:3/4)
--                  warp 2     -> HOUSE_2 (mat warp 0xff)
--                  warp 3     -> MART_A (explicit back), a mart the stub rules fix
--   ROUTE_B (ROUTE) warps 1+4, two tiles -> HOUSE_3; mat warp 1 back to ROUTE_B:1,
--                                mat warp 2 back to ROUTE_B:4 (each tile has its own exit)
--                   warp 2    -> CAVE_1F (explicit back), floor 2 -> CAVE_B1F and up again
--                   warp 3    -> HOUSE_4 (two 0xff mat warps)
-- Checked:
--   1. the question's text, labels and values;
--   2. a vanilla save and every "off" answer change nothing;
--   3. a randomized save moves entrances: every tile of an entrance arrives
--      where the target's first tile led, and walking (a simulator of
--      World:resolveWarp / recordWarpBackup / takeWarp) in through each tile
--      and out through every way out of the complex reached comes back to the
--      first tile of the entrance used; two-tile and one-tile entrances are
--      swapped both ways on purpose;
--   4. a vanilla save afterwards restores every warp field exactly (same tables,
--      same values, no field added);
--   5. switching between two seeds and back gives the same doors each time;
--   6. the graph is built once, the placer gets the level, the "maps" rng and
--      ctx.shared.keyitems;
--   7. a missing library, a failing one, no placement, tiles of one entrance
--      sent to different places, or a placement that would give one exit two
--      entrances, change nothing and log why;
--   8. a graph without `entrances` is still applied, one entrance per door.
-- With MAPS_REAL_LIBS=1 and CRYSTAL_RANDOMIZER_CACHE set to an imported cache's
-- data/generated folder, the real mapgraph, maprules and mapplacer run on the
-- real Crystal maps too (MAPS_STUB_RULES=1 stands in a permissive rules stub
-- while maprules is missing; MAPS_LEVEL picks the level, default houses).
local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Rng = dofile("launcher/mods/crystal_randomizer/rng.lua")
-- run on either generator: CRYSTAL_RANDOMIZER_RNG_VERSION (1 when unset)
local RNG_VERSION = tonumber(os.getenv("CRYSTAL_RANDOMIZER_RNG_VERSION")) or 1
local Maps = dofile("launcher/mods/crystal_randomizer/modules/maps.lua")

local failures, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
  return cond
end
local function eq(a, b, msg) return ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local FF = 0xff

-- ------------------------------------------------------------ the synthetic world
local function newData()
  local function w(x, y, destMap, destWarp) return { x = x, y = y, destMap = destMap, destWarp = destWarp } end
  return { gen2Maps = {
    TOWN_A = { environment = "TOWN", warps = { w(3, 3, "HOUSE_1", 1), w(9, 3, "HOUSE_2", 1), w(15, 3, "MART_A", 1),
      w(4, 3, "HOUSE_1", 2) } },
    ROUTE_B = { environment = "ROUTE", warps = { w(4, 8, "HOUSE_3", 1), w(12, 2, "CAVE_1F", 1), w(20, 6, "HOUSE_4", 1),
      w(5, 8, "HOUSE_3", 2) } },
    HOUSE_1 = { environment = "INDOOR", warps = { w(2, 7, "TOWN_A", 1), w(3, 7, "TOWN_A", 1) } },
    HOUSE_2 = { environment = "INDOOR", warps = { w(2, 7, "TOWN_A", FF) } },
    MART_A = { environment = "INDOOR", warps = { w(2, 7, "TOWN_A", 3), w(3, 7, "TOWN_A", 3) } },
    HOUSE_3 = { environment = "INDOOR", warps = { w(4, 7, "ROUTE_B", 1), w(5, 7, "ROUTE_B", 4) } },
    HOUSE_4 = { environment = "INDOOR", warps = { w(4, 7, "ROUTE_B", FF), w(5, 7, "ROUTE_B", FF) } },
    CAVE_1F = { environment = "CAVE", warps = { w(5, 9, "ROUTE_B", 2), w(10, 2, "CAVE_B1F", 1) } },
    CAVE_B1F = { environment = "CAVE", warps = { w(6, 6, "CAVE_1F", 2) } },
  } }
end

local OUTDOOR = { TOWN = true, ROUTE = true }

local function sorted(t)
  local k = {}
  for key in pairs(t) do k[#k + 1] = key end
  table.sort(k)
  return k
end

-- ------------------------------------------------------------ stub libraries
local calls
local function resetCalls() calls = { build = 0, model = 0, place = 0, last = nil } end
resetCalls()

-- A small graph builder shaped like the real one: each outdoor warp into a
-- non-outdoor map is a door; its complex is every non-outdoor map reachable
-- from there; a door's `inside` is the complex warps that lead back to it
-- explicitly, or 0xff warps on the map it enters.  Adjacent door tiles on one
-- map into one complex form an entrance named after its first tile, whose
-- `inside` is all of its tiles' inside warps.  `noEntrances` leaves them out.
local function buildGraph(data, noEntrances)
  local maps = data.gen2Maps
  local graph = { doors = {}, complexes = {}, outdoor = {}, entrances = {} }
  for id, m in pairs(maps) do if OUTDOOR[m.environment] then graph.outdoor[id] = true end end
  for _, mapId in ipairs(sorted(maps)) do
    local m = maps[mapId]
    if graph.outdoor[mapId] then
      for i, warp in ipairs(m.warps) do
        if not graph.outdoor[warp.destMap] then
          local seen, queue = { [warp.destMap] = true }, { warp.destMap }
          local q = 1
          while queue[q] do
            for _, x in ipairs(maps[queue[q]].warps) do
              if not graph.outdoor[x.destMap] and not seen[x.destMap] then
                seen[x.destMap] = true; queue[#queue + 1] = x.destMap
              end
            end
            q = q + 1
          end
          table.sort(queue)
          local doorId = mapId .. ":" .. i
          local inside = {}
          for _, cm in ipairs(queue) do
            for j, x in ipairs(maps[cm].warps) do
              if (x.destMap == mapId and x.destWarp == i) or (x.destWarp == FF and cm == warp.destMap) then
                inside[#inside + 1] = { map = cm, warp = j }
              end
            end
          end
          local complexId = queue[1]
          local env = maps[complexId].environment
          graph.complexes[complexId] = graph.complexes[complexId] or { id = complexId, maps = queue,
            environment = env, doors = {}, deadEnd = true, story = false,
            kind = env == "CAVE" and "cave" or (complexId:find("MART") and "mart" or "house") }
          table.insert(graph.complexes[complexId].doors, doorId)
          graph.doors[doorId] = { id = doorId, map = mapId, warp = i, complex = complexId, inside = inside,
            x = warp.x, y = warp.y }
        end
      end
    end
  end
  -- entrances: adjacent tiles, same map, same complex (doors sorted by map, then warp number)
  local ids = sorted(graph.doors)
  table.sort(ids, function(a, b)
    local am, aw = a:match("^(.*):(%d+)$")
    local bm, bw = b:match("^(.*):(%d+)$")
    if am ~= bm then return am < bm end
    return tonumber(aw) < tonumber(bw)
  end)
  for _, did in ipairs(ids) do
    local d = graph.doors[did]
    for _, eid in ipairs(sorted(graph.entrances)) do
      local e = graph.entrances[eid]
      if not d.entrance and e.map == d.map and e.complex == d.complex then
        for _, other in ipairs(e.doors) do
          local o = graph.doors[other]
          if math.abs(o.x - d.x) + math.abs(o.y - d.y) == 1 then d.entrance = eid end
        end
      end
    end
    if not d.entrance then
      d.entrance = did
      graph.entrances[did] = { id = did, map = d.map, complex = d.complex, doors = {}, inside = {} }
    end
    local e = graph.entrances[d.entrance]
    e.doors[#e.doors + 1] = did
    for _, spot in ipairs(d.inside) do e.inside[#e.inside + 1] = spot end
  end
  if noEntrances then
    graph.entrances = nil
    for _, d in pairs(graph.doors) do d.entrance = nil end
  end
  return graph
end

local function stubBuild(data)
  calls.build = calls.build + 1
  return buildGraph(data)
end

local function stubModel(data, graph)
  calls.model = calls.model + 1
  return { fixed = { MART_A = "a mart in this test" }, regions = {}, needs = {}, doorRegion = {},
    complexNeeds = {}, canWin = function() return true end }
end

-- The placement the real placer gives for an entrance map: every tile of a
-- moved entrance names the target's first tile, every other door itself, and
-- placement.entrances says which entrance went where.
local function entrancePlacement(graph, byEntrance)
  local placement = { entrances = {} }
  for did in pairs(graph.doors) do placement[did] = did end
  for eid, tid in pairs(byEntrance) do
    placement.entrances[eid] = tid
    for _, did in ipairs(graph.entrances[eid].doors) do placement[did] = graph.entrances[tid].doors[1] end
  end
  return placement
end

local placeOverride
local function stubPlace(graph, rules, level, rng, hmPlacement)
  calls.place = calls.place + 1
  calls.last = { graph = graph, rules = rules, level = level, rng = rng, rngState = rng and rng.state,
    hm = hmPlacement }
  if placeOverride then return placeOverride(graph, rules, level, rng, hmPlacement) end
  local pool = {}
  for _, eid in ipairs(sorted(graph.entrances)) do
    local c = graph.complexes[graph.entrances[eid].complex]
    if not rules.fixed[c.id] and (level == "full" or c.kind == "house" or (level == "caves" and c.kind == "cave")) then
      pool[#pool + 1] = eid
    end
  end
  local shuffled = rng:shuffled(pool)
  local byEntrance = {}
  for i, eid in ipairs(pool) do if shuffled[i] ~= eid then byEntrance[eid] = shuffled[i] end end
  return entrancePlacement(graph, byEntrance), { level = level, moved = #pool }
end

local function libs()
  return { mapGraph = { build = stubBuild }, mapRules = { model = stubModel }, mapPlacer = { place = stubPlace } }
end

-- ------------------------------------------------------------ helpers
local function snapshot(data)
  local out = {}
  for _, id in ipairs(sorted(data.gen2Maps)) do
    for i, warp in ipairs(data.gen2Maps[id].warps) do
      local parts = {}
      for _, k in ipairs(sorted(warp)) do parts[#parts + 1] = k .. "=" .. tostring(warp[k]) end
      out[#out + 1] = id .. ":" .. i .. "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return table.concat(out, " ")
end

local function warpTables(data)
  local list = {}
  for id, m in pairs(data.gen2Maps) do
    for i, warp in ipairs(m.warps) do list[id .. ":" .. i] = warp end
  end
  return list
end

-- The world's warp rules, from src/world/gen2/World.lua (resolveWarp,
-- recordWarpBackup, takeWarp): returns the map and warp number arrived on.
local function newWalker(data)
  local walker = { backup = nil }
  function walker.take(mapId, index)
    local maps = data.gen2Maps
    local warp = maps[mapId].warps[index]
    local destMap, destWarp = warp.destMap, warp.destWarp
    if destWarp == FF then
      if walker.backup and maps[walker.backup.map] then
        destMap, destWarp = walker.backup.map, walker.backup.warp
      end
    end
    local arrival = maps[destMap] and maps[destMap].warps[destWarp]
    if not arrival then return nil end
    if arrival.destWarp == FF then
      walker.backup = { map = mapId, warp = index }
    elseif OUTDOOR[maps[mapId].environment] and not OUTDOOR[maps[destMap].environment] then
      walker.backup = { map = mapId, warp = index }
    end
    return destMap, destWarp
  end
  return walker
end

-- For each moved entrance A -> T (graph of the vanilla maps, vanilla warp
-- values in `vw`): every tile arrives where T's first tile led, and in
-- through every tile and out through every way out of T comes back to A's
-- first tile.  Returns how many entrances moved and how many walks returned.
local function checkEntrances(label, data, graph, vw, targets)
  local moved, walks, back = 0, 0, 0
  for _, eid in ipairs(sorted(targets)) do
    local tid = targets[eid]
    if tid ~= eid then
      moved = moved + 1
      local a, t = graph.entrances[eid], graph.entrances[tid]
      local rep = graph.doors[t.doors[1]]
      local repV = vw[rep.map .. ":" .. rep.warp]
      local first = graph.doors[a.doors[1]]
      for _, did in ipairs(a.doors) do
        local door = graph.doors[did]
        local outside = data.gen2Maps[door.map].warps[door.warp]
        ok(outside.destMap == repV.destMap and outside.destWarp == repV.destWarp,
          ("%s: tile %s of %s arrives where %s led (%s:%s, got %s:%s)"):format(label, did, eid, rep.id,
            tostring(repV.destMap), tostring(repV.destWarp), tostring(outside.destMap), tostring(outside.destWarp)))
        for _, spot in ipairs(t.inside) do
          walks = walks + 1
          local walker = newWalker(data)
          local inMap = walker.take(door.map, door.warp)
          local outMap, outWarp = walker.take(spot.map, spot.warp)
          -- an explicit exit leads to A's first tile; a 0xff one back to the tile stepped on
          local wantDoor = vw[spot.map .. ":" .. spot.warp].destWarp == FF and door or first
          if ok(inMap == repV.destMap and outMap == wantDoor.map and outWarp == wantDoor.warp,
              ("%s: in through %s, out through %s:%d comes back to %s (got %s:%s)"):format(label, did,
                spot.map, spot.warp, wantDoor.id, tostring(outMap), tostring(outWarp))) then
            back = back + 1
          end
        end
      end
    end
  end
  return moved, walks, back
end

local function vanillaValues(data)
  local vw = {}
  for id, t in pairs(warpTables(data)) do vw[id] = { destMap = t.destMap, destWarp = t.destWarp } end
  return vw
end

local function newCtx(seed, options)
  local ctx = Fake.new({ seed = seed, options = options })
  ctx.lib = libs()
  return ctx
end

-- A save switch the way the core does it: shared cleared, keyitems published
-- by an earlier module, then every onSave listener.
local function switch(ctx, active, seed, options, keyitems)
  for k in pairs(ctx.shared) do ctx.shared[k] = nil end
  if keyitems then ctx.shared.keyitems = keyitems end
  ctx.setActive(active, seed, options)
end

local function lastLog(ctx) return ctx.lines[#ctx.lines] or "" end

-- ------------------------------------------------------------ 0. the stub graph itself
do
  local g = buildGraph(newData())
  local e = g.entrances["TOWN_A:1"]
  ok(e and #e.doors == 2 and e.doors[2] == "TOWN_A:4", "stub graph: TOWN_A:1 and :4 are one entrance")
  eq(e and #e.inside, 2, "stub graph: HOUSE_1's two mats lead back to that entrance")
  local r = g.entrances["ROUTE_B:1"]
  ok(r and #r.doors == 2 and r.doors[2] == "ROUTE_B:4", "stub graph: ROUTE_B:1 and :4 are one entrance")
  eq(g.doors["TOWN_A:4"].entrance, "TOWN_A:1", "stub graph: door.entrance")
end

-- ------------------------------------------------------------ 1. the question
do
  local q = Maps.questions[1]
  eq(#Maps.questions, 1, "one question")
  eq(q.key, "maps", "key")
  eq(q.kind, "choice", "a choice")
  eq(q.recommended, "off", "recommended is off")
  eq(q.everything, "off", "everything is off")
  local lines = 0
  for line in (q.text .. "\n"):gmatch("([^\n]*)\n") do
    lines = lines + 1
    ok(#line <= 18, "question line within 18 characters: " .. line)
  end
  ok(not q.text:find("[\v\f]"), "question fits one box")
  eq(lines, 2, "two lines")
  local want = { { "OFF", "off" }, { "HOUSES", "houses" }, { "CAVES", "caves" }, { "EVERYTHING", "full" } }
  eq(#q.options, #want, "four options")
  for i, w in ipairs(want) do
    eq(q.options[i].label, w[1], "label " .. i)
    eq(q.options[i].value, w[2], "value " .. i)
    ok(#q.options[i].label <= 12 and q.options[i].label == q.options[i].label:upper(), "label short and uppercase")
  end
end

-- ------------------------------------------------------------ 2. vanilla and off
do
  for _, case in ipairs({ { false, nil }, { true, "off" }, { true, false }, { true, nil } }) do
    local data = newData()
    local vanilla = snapshot(data)
    resetCalls()
    local ctx = newCtx("vanilla-check", { maps = case[2] })
    Maps.install({ game = { data = data } }, ctx)
    switch(ctx, case[1], nil, { maps = case[2] })
    eq(snapshot(data), vanilla, "no change for active=" .. tostring(case[1]) .. " maps=" .. tostring(case[2]))
    eq(ctx.shared.maps, nil, "nothing published when not shuffled")
    eq(calls.build + calls.place, 0, "no library called when not shuffled")
  end
end

-- ------------------------------------------------------------ 3. two-tile and one-tile entrances, both ways
do
  local swaps = {
    { name = "two-tile TOWN_A:1 <-> one-tile TOWN_A:2 (0xff exit)",
      map = { ["TOWN_A:1"] = "TOWN_A:2", ["TOWN_A:2"] = "TOWN_A:1" } },
    { name = "two-tile ROUTE_B:1 <-> one-tile ROUTE_B:3 (two 0xff mats)",
      map = { ["ROUTE_B:1"] = "ROUTE_B:3", ["ROUTE_B:3"] = "ROUTE_B:1" } },
    { name = "two-tile TOWN_A:1 <-> two-tile ROUTE_B:1",
      map = { ["TOWN_A:1"] = "ROUTE_B:1", ["ROUTE_B:1"] = "TOWN_A:1" } },
    { name = "a cycle: TOWN_A:1 -> ROUTE_B:2 (cave) -> TOWN_A:2 -> TOWN_A:1",
      map = { ["TOWN_A:1"] = "ROUTE_B:2", ["ROUTE_B:2"] = "TOWN_A:2", ["TOWN_A:2"] = "TOWN_A:1" } },
  }
  for _, swap in ipairs(swaps) do
    local data = newData()
    local vanilla, vw = snapshot(data), vanillaValues(data)
    local graph = buildGraph(data)
    local ctx = newCtx("maps-test-swap", { maps = "full" })
    placeOverride = function(g) return entrancePlacement(g, swap.map), { fixed = true } end
    Maps.install({ game = { data = data } }, ctx)
    switch(ctx, true)
    placeOverride = nil
    ok(ctx.shared.maps ~= nil, swap.name .. ": applied (" .. lastLog(ctx) .. ")")
    local moved, walks, back = checkEntrances(swap.name, data, graph, vw, swap.map)
    eq(moved, 0 + #sorted(swap.map), swap.name .. ": entrances moved")
    eq(back, walks, swap.name .. ": every walk out returns to the first tile used")
    -- both tiles of a two-tile entrance arrive at the same warp
    for eid in pairs(swap.map) do
      local e = graph.entrances[eid]
      if #e.doors == 2 then
        local a = data.gen2Maps[e.map].warps[graph.doors[e.doors[1]].warp]
        local b = data.gen2Maps[e.map].warps[graph.doors[e.doors[2]].warp]
        ok(a.destMap == b.destMap and a.destWarp == b.destWarp, swap.name .. ": both tiles of " .. eid
          .. " arrive at the same place")
      end
    end
    switch(ctx, false)
    eq(snapshot(data), vanilla, swap.name .. ": restored exactly")
  end
  -- the second tile of TOWN_A:1 entering a one-tile entrance, and leaving
  -- comes out at TOWN_A:1, the first tile (TOWN_A:4 has no exit of its own)
  local data = newData()
  local ctx = newCtx("maps-test-swap", { maps = "full" })
  placeOverride = function(g) return entrancePlacement(g, { ["TOWN_A:1"] = "ROUTE_B:3", ["ROUTE_B:3"] = "TOWN_A:1" }), {} end
  Maps.install({ game = { data = data } }, ctx)
  switch(ctx, true)
  placeOverride = nil
  local walker = newWalker(data)
  local m = walker.take("TOWN_A", 4)
  eq(m, "HOUSE_4", "TOWN_A:4 now enters HOUSE_4")
  local om, ow = walker.take("HOUSE_4", 2)
  ok(om == "TOWN_A" and ow == 4, "out of HOUSE_4's 0xff mat returns to the tile stepped on, TOWN_A:4 (got "
    .. tostring(om) .. ":" .. tostring(ow) .. ")")
  walker = newWalker(data)
  walker.take("ROUTE_B", 3)
  om, ow = walker.take("HOUSE_1", 2)
  ok(om == "ROUTE_B" and ow == 3, "ROUTE_B:3 into HOUSE_1 and out its second mat returns to ROUTE_B:3")
end

-- ------------------------------------------------------------ 4-6. a randomized save
local function findSeed(level, prefix, notEqual)
  for n = 1, 500 do
    local data = newData()
    local ctx = newCtx(prefix .. n, { maps = level })
    Maps.install({ game = { data = data } }, ctx)
    local before = snapshot(data)
    switch(ctx, true, nil, nil)
    local after = snapshot(data)
    if after ~= before and (not notEqual or after ~= notEqual) then return prefix .. n, after end
  end
end

do
  for _, level in ipairs({ "houses", "caves", "full" }) do
    local seed, firstWorld = findSeed(level, "maps-test-" .. level .. "-")
    local seedB = seed and findSeed(level, "maps-test-b-" .. level .. "-", firstWorld)
    if ok(seed ~= nil and seedB ~= nil, level .. ": two seeds that move doors differently") then
      local data = newData()
      local vanilla, vw = snapshot(data), vanillaValues(data)
      local tables = warpTables(data)
      local graph = buildGraph(data)
      resetCalls()
      local ctx = newCtx(seed, { maps = level })
      Maps.install({ game = { data = data } }, ctx)
      local hm = { SPROUT_TOWER_3F = "HM_CUT" }
      switch(ctx, true, nil, nil, hm)
      local shared = ctx.shared.maps
      if ok(type(shared) == "table" and type(shared.placement) == "table", level .. ": placement published") then
        ok(shared.report ~= nil and shared.report.level == level, level .. ": report published")
        eq(calls.last.level, level, level .. ": placer got the level")
        eq(calls.last.hm, hm, level .. ": placer got ctx.shared.keyitems")
        eq(calls.last.rngState, Rng.streamFor(RNG_VERSION, seed, "maps").state, level .. ": placer got ctx.rng(\"maps\")")
        local placement = shared.placement
        eq(placement["TOWN_A:3"], "TOWN_A:3", level .. ": the mart stays")
        local targets = {}
        for eid in pairs(graph.entrances) do targets[eid] = placement.entrances[eid] or eid end
        local moved, walks, back = checkEntrances(level, data, graph, vw, targets)
        ok(moved > 0, level .. ": at least one entrance moved")
        eq(back, walks, level .. ": every walk out returns to the first tile used")
        -- a cave walk: down a floor and back up keeps the way out
        for eid, tid in pairs(targets) do
          if tid == "ROUTE_B:2" and eid ~= tid then
            local door = graph.doors[graph.entrances[eid].doors[1]]
            local walker = newWalker(data)
            walker.take(door.map, door.warp)
            local m, wn = walker.take("CAVE_1F", 2)
            walker.take(m, wn)
            local outMap, outWarp = walker.take("CAVE_1F", 1)
            ok(outMap == door.map and outWarp == door.warp,
              level .. ": through the cave's lower floor and out returns to " .. eid)
          end
        end
        if level == "houses" then
          eq(placement["ROUTE_B:2"], "ROUTE_B:2", "houses: the cave door stays")
          eq(data.gen2Maps.ROUTE_B.warps[2].destMap, "CAVE_1F", "houses: the cave door still leads to the cave")
        end
      end
      -- 4. an exact restore
      switch(ctx, false)
      eq(snapshot(data), vanilla, level .. ": a vanilla save restores every warp exactly")
      local same = true
      for id, t in pairs(warpTables(data)) do if tables[id] ~= t then same = false end end
      ok(same, level .. ": the same warp tables are kept (never replaced)")
      eq(ctx.shared.maps, nil, level .. ": nothing published for a vanilla save")
      -- 5. switching saves
      switch(ctx, true, seed, { maps = level })
      local first = snapshot(data)
      switch(ctx, true, seedB, { maps = level })
      local second = snapshot(data)
      switch(ctx, true, seed, { maps = level })
      eq(snapshot(data), first, level .. ": seed A again gives the same doors after seed B")
      switch(ctx, true, seedB, { maps = level })
      eq(snapshot(data), second, level .. ": seed B again gives the same doors")
      switch(ctx, true, seed, { maps = "off" })
      eq(snapshot(data), vanilla, level .. ": switching to an off save restores exactly")
      switch(ctx, false)
      eq(snapshot(data), vanilla, level .. ": and a vanilla save after all of that is exact")
      eq(calls.build, 1, level .. ": the graph was built once for all those switches")
    end
  end
end

-- ------------------------------------------------------------ 7. nothing changes on trouble
do
  local function expectUnchanged(name, mutate, logPattern)
    local data = newData()
    local vanilla = snapshot(data)
    resetCalls()
    local ctx = newCtx("maps-test-trouble", { maps = "full" })
    mutate(ctx)
    Maps.install({ game = { data = data } }, ctx)
    local okCall, err = pcall(switch, ctx, true)
    ok(okCall, name .. ": no error escapes (" .. tostring(err) .. ")")
    eq(snapshot(data), vanilla, name .. ": nothing changed")
    eq(ctx.shared.maps, nil, name .. ": nothing published")
    ok(lastLog(ctx):find(logPattern) ~= nil, name .. ": logged why (" .. lastLog(ctx) .. ")")
  end
  expectUnchanged("no mapGraph", function(ctx) ctx.lib.mapGraph = nil end, "no mapGraph")
  expectUnchanged("no mapRules", function(ctx) ctx.lib.mapRules = nil end, "no mapRules")
  expectUnchanged("no mapPlacer", function(ctx) ctx.lib.mapPlacer = nil end, "no mapPlacer")
  expectUnchanged("no ctx.lib at all", function(ctx) ctx.lib = nil end, "no mapGraph")
  expectUnchanged("build fails", function(ctx) ctx.lib.mapGraph = { build = function() error("boom") end } end,
    "mapGraph.build failed")
  expectUnchanged("model fails", function(ctx) ctx.lib.mapRules = { model = function() error("boom") end } end,
    "mapRules.model failed")
  placeOverride = function() return nil end
  expectUnchanged("placer gives nil", function() end, "no placement")
  placeOverride = function() error("boom") end
  expectUnchanged("placer fails", function() end, "mapPlacer.place failed")
  -- two entrances into HOUSE_1 while TOWN_A:1 stays: its explicit exits cannot lead to both
  placeOverride = function(g) return entrancePlacement(g, { ["TOWN_A:2"] = "TOWN_A:1" }), {} end
  expectUnchanged("two entrances share an exit", function() end, "two entrances")
  -- two entrances both sent to one target with explicit exits (HOUSE_3)
  placeOverride = function(g)
    return entrancePlacement(g, { ["TOWN_A:2"] = "ROUTE_B:1", ["TOWN_A:1"] = "ROUTE_B:1",
      ["ROUTE_B:1"] = "TOWN_A:2" }), {}
  end
  expectUnchanged("two entrances sent to one", function() end, "two entrances")
  -- the tiles of one entrance sent apart (no placement.entrances; tile 4 stays)
  placeOverride = function(g)
    local p = {}
    for did in pairs(g.doors) do p[did] = did end
    p["TOWN_A:1"], p["TOWN_A:2"] = "TOWN_A:2", "TOWN_A:1"
    return p, {}
  end
  expectUnchanged("tiles of one entrance sent apart", function() end, "different entrances")
  -- a tile disagreeing with placement.entrances
  placeOverride = function(g)
    local p = entrancePlacement(g, { ["TOWN_A:1"] = "TOWN_A:2", ["TOWN_A:2"] = "TOWN_A:1" })
    p["TOWN_A:4"] = "ROUTE_B:3"
    return p, {}
  end
  expectUnchanged("a tile disagreeing with placement.entrances", function() end, "different entrances")
  placeOverride = function() return { ["TOWN_A:2"] = "NOWHERE:1", ["NOWHERE:1"] = "TOWN_A:2" }, {} end
  expectUnchanged("a door the graph lacks", function() end, "no door")
  placeOverride = function() return { entrances = { ["TOWN_A:2"] = "NOWHERE:1" } }, {} end
  expectUnchanged("an entrance the graph lacks", function() end, "no entrance")
  placeOverride = nil
  -- an unknown level
  local data = newData()
  local vanilla = snapshot(data)
  local ctx = newCtx("maps-test-level", { maps = "sideways" })
  Maps.install({ game = { data = data } }, ctx)
  switch(ctx, true)
  eq(snapshot(data), vanilla, "an unknown level changes nothing")
  ok(lastLog(ctx):find("unknown level") ~= nil, "an unknown level is logged")
  -- no game data yet
  local ctx2 = newCtx("maps-test-nodata", { maps = "full" })
  Maps.install({ game = nil }, ctx2)
  switch(ctx2, true)
  ok(lastLog(ctx2):find("no map data") ~= nil, "no game data is logged")
  -- a working switch after a refused one still works and restores
  local data3 = newData()
  local vanilla3 = snapshot(data3)
  local ctx3 = newCtx(findSeed("full", "maps-test-full-"), { maps = "full" })
  Maps.install({ game = { data = data3 } }, ctx3)
  placeOverride = function(g) return entrancePlacement(g, { ["TOWN_A:2"] = "TOWN_A:1" }), {} end
  switch(ctx3, true)
  eq(snapshot(data3), vanilla3, "refused placement: vanilla")
  placeOverride = nil
  switch(ctx3, true)
  ok(snapshot(data3) ~= vanilla3, "the next save with a good placement is applied")
  switch(ctx3, false)
  eq(snapshot(data3), vanilla3, "and restored exactly")
end

-- ------------------------------------------------------------ 8. a graph without entrances
do
  local data = newData()
  local vanilla = snapshot(data)
  local ctx = newCtx("maps-test-old-graph", { maps = "full" })
  ctx.lib.mapGraph = { build = function(d) return buildGraph(d, true) end }
  placeOverride = function() return { ["TOWN_A:2"] = "ROUTE_B:3", ["ROUTE_B:3"] = "TOWN_A:2" }, {} end
  Maps.install({ game = { data = data } }, ctx)
  switch(ctx, true)
  placeOverride = nil
  eq(data.gen2Maps.TOWN_A.warps[2].destMap, "HOUSE_4", "no entrances: a door is its own entrance")
  local walker = newWalker(data)
  walker.take("ROUTE_B", 3)
  local om, ow = walker.take("HOUSE_2", 1)
  ok(om == "ROUTE_B" and ow == 3, "no entrances: leaving returns to the door used")
  switch(ctx, false)
  eq(snapshot(data), vanilla, "no entrances: restored exactly")
end

-- ------------------------------------------------------------ real libraries (optional)
local cache = os.getenv("CRYSTAL_RANDOMIZER_CACHE")
if os.getenv("MAPS_REAL_LIBS") == "1" then
  local names = { "mapgraph", "maprules", "mapplacer" }
  local data = cache and cache ~= "" and { gen2Maps = dofile(cache .. "/maps.lua") } or nil
  if not ok(data ~= nil, "real libraries need CRYSTAL_RANDOMIZER_CACHE") then data = { gen2Maps = {} } end
  local vanilla, vw = snapshot(data), vanillaValues(data)
  local level = os.getenv("MAPS_LEVEL") or "houses"
  local ctx = Fake.new({ seed = os.getenv("MAPS_SEED") or "maps-real-1", options = { maps = level } })
  local mod = { game = { data = data }, hooks = { wrap = function() end }, events = { on = function() end } }
  for _, name in ipairs(names) do
    local path = "launcher/mods/crystal_randomizer/modules/" .. name .. ".lua"
    local f = io.open(path, "r")
    if not f and name == "maprules" and os.getenv("MAPS_STUB_RULES") == "1" then
      print("NOTE: maprules missing, using a permissive stub (MAPS_STUB_RULES=1)")
      ctx.lib.mapRules = { model = function() return { fixed = {}, regions = {}, needs = {}, doorRegion = {},
        complexNeeds = {}, canWin = function() return true end } end }
    elseif ok(f ~= nil, path .. " exists") then
      f:close()
      local module = dofile(path)
      local installed, err = pcall(module.install, mod, ctx)
      ok(installed, name .. " installs (" .. tostring(err) .. ")")
    end
  end
  Maps.install(mod, ctx)
  -- the graph of the vanilla maps, built before anything moves
  local graph = ctx.lib.mapGraph and ctx.lib.mapGraph.build(data)
  switch(ctx, true)
  for _, line in ipairs(ctx.lines) do print("LOG: " .. line) end
  local shared = ctx.shared.maps
  if ok(shared ~= nil and graph ~= nil, "real libraries: a placement was applied") then
    ok(type(graph.entrances) == "table", "real libraries: the graph has entrances")
    print("real placer gives placement.entrances: " .. tostring(type(shared.placement.entrances) == "table"))
    local entrances, of = Maps.entrancesOf(graph)
    local targets = Maps.entranceTargets(graph, shared.placement, entrances, of)
    local wide, wideMoved = 0, 0
    for eid, e in pairs(entrances) do
      if #e.doors > 1 then
        wide = wide + 1
        if targets[eid] ~= eid then wideMoved = wideMoved + 1 end
      end
    end
    local savedFailures = failures
    local moved, walks, back = checkEntrances("real " .. level, data, graph, vw, targets)
    if failures - savedFailures > 20 then print("  (" .. (failures - savedFailures) .. " failures above)") end
    print(("real libraries, %s: %d entrances moved (%d of %d wide ones), %d of %d walks out return to the first tile used")
      :format(level, moved, wideMoved, wide, back, walks))
    ok(moved > 0, "real libraries: some entrance moved")
    eq(back, walks, "real libraries: every walk out returns to the first tile used")
  end
  switch(ctx, false)
  eq(snapshot(data), vanilla, "real libraries: a vanilla save restores exactly")
end

print(("maps_test: %d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
