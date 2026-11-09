-- luajit launcher/mods/crystal_randomizer/tests/maps_test.lua   (from the repository root)
--
-- The maps module applies a placement; the graph, rules and placer come from
-- ctx.lib.  Here they are stubs written in this file, over a small synthetic
-- world shaped like Crystal's warp tables:
--   TOWN_A (TOWN)  warp 1 -> HOUSE_1 (two mat warps, both explicit back to TOWN_A:1)
--                  warp 2 -> HOUSE_2 (mat warp 0xff)
--                  warp 3 -> MART_A  (explicit back), a mart the stub rules fix
--   ROUTE_B (ROUTE) warp 1 -> HOUSE_3 (explicit back)
--                   warp 2 -> CAVE_1F (explicit back), floor 2 -> CAVE_B1F and up again
--                   warp 3 -> HOUSE_4 (0xff)
-- Checked:
--   1. the question's text, labels and values;
--   2. a vanilla save and every "off" answer change nothing;
--   3. a randomized save moves doors, and walking (a simulator of
--      World:resolveWarp / recordWarpBackup / takeWarp) through each door and
--      back out of every way out of the complex reached returns to the door used;
--   4. a vanilla save afterwards restores every warp field exactly (same tables,
--      same values, no field added);
--   5. switching between two seeds and back gives the same doors each time;
--   6. the graph is built once, the placer gets the level, the "maps" rng and
--      ctx.shared.keyitems;
--   7. a missing library, a failing one, no placement, or a placement that
--      would give one exit two doors, change nothing and log why.
-- With MAPS_REAL_LIBS=1 and the real mapgraph/maprules/mapplacer modules in
-- modules/, and CRYSTAL_RANDOMIZER_CACHE set to an imported cache's
-- data/generated folder, the real libraries run on the real Crystal maps too.
local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Rng = dofile("launcher/mods/crystal_randomizer/rng.lua")
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
    TOWN_A = { environment = "TOWN", warps = { w(3, 3, "HOUSE_1", 1), w(9, 3, "HOUSE_2", 1), w(15, 3, "MART_A", 1) } },
    ROUTE_B = { environment = "ROUTE", warps = { w(4, 8, "HOUSE_3", 1), w(12, 2, "CAVE_1F", 1), w(20, 6, "HOUSE_4", 1) } },
    HOUSE_1 = { environment = "INDOOR", warps = { w(2, 7, "TOWN_A", 1), w(3, 7, "TOWN_A", 1) } },
    HOUSE_2 = { environment = "INDOOR", warps = { w(2, 7, "TOWN_A", FF) } },
    MART_A = { environment = "INDOOR", warps = { w(2, 7, "TOWN_A", 3), w(3, 7, "TOWN_A", 3) } },
    HOUSE_3 = { environment = "INDOOR", warps = { w(4, 7, "ROUTE_B", 1) } },
    HOUSE_4 = { environment = "INDOOR", warps = { w(4, 7, "ROUTE_B", FF), w(5, 7, "ROUTE_B", FF) } },
    CAVE_1F = { environment = "CAVE", warps = { w(5, 9, "ROUTE_B", 2), w(10, 2, "CAVE_B1F", 1) } },
    CAVE_B1F = { environment = "CAVE", warps = { w(6, 6, "CAVE_1F", 2) } },
  } }
end

local OUTDOOR = { TOWN = true, ROUTE = true }

-- ------------------------------------------------------------ stub libraries
local calls
local function resetCalls() calls = { build = 0, model = 0, place = 0, last = nil } end
resetCalls()

-- A small graph builder: each outdoor warp into a non-outdoor map is a door;
-- its complex is every non-outdoor map reachable from there; `inside` is the
-- complex warps that lead back to it explicitly, or 0xff warps on the map it
-- enters.
local function stubBuild(data)
  calls.build = calls.build + 1
  local maps = data.gen2Maps
  local graph = { doors = {}, complexes = {}, outdoor = {} }
  for id, m in pairs(maps) do if OUTDOOR[m.environment] then graph.outdoor[id] = true end end
  for mapId, m in pairs(maps) do
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
          graph.complexes[complexId] = { id = complexId, maps = queue, environment = env, doors = { doorId },
            deadEnd = true, story = false, kind = env == "CAVE" and "cave" or (complexId:find("MART") and "mart" or "house") }
          graph.doors[doorId] = { id = doorId, map = mapId, warp = i, complex = complexId, inside = inside }
        end
      end
    end
  end
  return graph
end

local function stubModel(data, graph)
  calls.model = calls.model + 1
  return { fixed = { MART_A = "a mart in this test" }, regions = {}, needs = {}, doorRegion = {},
    complexNeeds = {}, canWin = function() return true end }
end

local placeOverride
local function stubPlace(graph, rules, level, rng, hmPlacement)
  calls.place = calls.place + 1
  calls.last = { graph = graph, rules = rules, level = level, rng = rng, rngState = rng and rng.state,
    hm = hmPlacement }
  if placeOverride then return placeOverride(graph, rules, level, rng, hmPlacement) end
  local pool = {}
  for _, id in ipairs((function() local k = {} for d in pairs(graph.doors) do k[#k + 1] = d end table.sort(k) return k end)()) do
    local c = graph.complexes[graph.doors[id].complex]
    if not rules.fixed[c.id] and (level == "full" or c.kind == "house" or (level == "caves" and c.kind == "cave")) then
      pool[#pool + 1] = id
    end
  end
  local shuffled = rng:shuffled(pool)
  -- like the real placer: every door listed, a door that stays maps to itself
  local placement = {}
  for id in pairs(graph.doors) do placement[id] = id end
  for i, id in ipairs(pool) do placement[id] = shuffled[i] end
  return placement, { level = level, moved = #pool }
end

local function libs()
  return { mapGraph = { build = stubBuild }, mapRules = { model = stubModel }, mapPlacer = { place = stubPlace } }
end

-- ------------------------------------------------------------ helpers
local function snapshot(data)
  local out = {}
  local ids = {}
  for id in pairs(data.gen2Maps) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    for i, warp in ipairs(data.gen2Maps[id].warps) do
      local keys = {}
      for k in pairs(warp) do keys[#keys + 1] = k end
      table.sort(keys)
      local parts = {}
      for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(warp[k]) end
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

-- ------------------------------------------------------------ 3-6. a randomized save
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
      local vanilla = snapshot(data)
      local tables = warpTables(data)
      local graph = stubBuild(data)
      local vanillaWarps = {}
      for id, t in pairs(tables) do vanillaWarps[id] = { destMap = t.destMap, destWarp = t.destWarp } end
      resetCalls()
      local ctx = newCtx(seed, { maps = level })
      Maps.install({ game = { data = data } }, ctx)
      local hm = { SPROUT_TOWER_3F = "HM_CUT" }
      switch(ctx, true, nil, nil, hm)
      local shared = ctx.shared.maps
      if ok(type(shared) == "table" and type(shared.placement) == "table", level .. ": placement published") then
        ok(shared.report ~= nil and shared.report.level == level, level .. ": report published")
        -- 6. what the placer was given
        eq(calls.last.level, level, level .. ": placer got the level")
        eq(calls.last.hm, hm, level .. ": placer got ctx.shared.keyitems")
        eq(calls.last.rngState, Rng.stream(seed, "maps").state, level .. ": placer got ctx.rng(\"maps\")")
        local placement = shared.placement
        -- the fixed mart never moves (a stub-placer property, kept as a sanity check)
        eq(placement["TOWN_A:3"], "TOWN_A:3", level .. ": the mart stays")
        -- 3. each outdoor door leads where its target led, and back out to itself
        local moved = 0
        for doorId, targetId in pairs(placement) do
          local door, target = graph.doors[doorId], graph.doors[targetId]
          local outside = data.gen2Maps[door.map].warps[door.warp]
          local tv = vanillaWarps[target.map .. ":" .. target.warp]
          eq(outside.destMap, tv.destMap, level .. ": " .. doorId .. " leads to " .. targetId .. "'s map")
          eq(outside.destWarp, tv.destWarp, level .. ": " .. doorId .. " leads to " .. targetId .. "'s warp")
          if doorId ~= targetId then moved = moved + 1 end
          -- walk in, then out through every way out of that complex
          for _, spot in ipairs(target.inside) do
            local walker = newWalker(data)
            local inMap, inWarp = walker.take(door.map, door.warp)
            eq(inMap, tv.destMap, level .. ": walking into " .. doorId .. " arrives in " .. tostring(tv.destMap))
            local outMap, outWarp = walker.take(spot.map, spot.warp)
            ok(outMap == door.map and outWarp == door.warp,
              ("%s: in through %s, out through %s:%d comes back to %s (got %s:%s)"):format(level, doorId,
                spot.map, spot.warp, doorId, tostring(outMap), tostring(outWarp)))
          end
        end
        ok(moved > 0, level .. ": at least one door moved")
        -- a cave walk: down a floor and back up keeps the way out
        for doorId, targetId in pairs(placement) do
          if targetId == "ROUTE_B:2" then
            local door = graph.doors[doorId]
            local walker = newWalker(data)
            walker.take(door.map, door.warp)
            local m, wn = walker.take("CAVE_1F", 2)
            m, wn = walker.take(m, wn == 1 and 1 or wn)
            local outMap, outWarp = walker.take("CAVE_1F", 1)
            ok(outMap == door.map and outWarp == door.warp,
              level .. ": through the cave's lower floor and out returns to " .. doorId)
          end
        end
        -- level pools: houses never moves the cave
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
  -- two doors into HOUSE_1: its explicit exit cannot lead to both
  placeOverride = function() return { ["TOWN_A:2"] = "TOWN_A:1" }, {} end
  expectUnchanged("two doors share an exit", function() end, "two doors")
  placeOverride = function() return { ["TOWN_A:2"] = "NOWHERE:1", ["NOWHERE:1"] = "TOWN_A:2" }, {} end
  expectUnchanged("a door the graph lacks", function() end, "no door")
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
  placeOverride = function() return { ["TOWN_A:2"] = "TOWN_A:1" }, {} end
  switch(ctx3, true)
  eq(snapshot(data3), vanilla3, "refused placement: vanilla")
  placeOverride = nil
  switch(ctx3, true)
  ok(snapshot(data3) ~= vanilla3, "the next save with a good placement is applied")
  switch(ctx3, false)
  eq(snapshot(data3), vanilla3, "and restored exactly")
end

-- ------------------------------------------------------------ real libraries (optional)
local cache = os.getenv("CRYSTAL_RANDOMIZER_CACHE")
if os.getenv("MAPS_REAL_LIBS") == "1" then
  local names = { "mapgraph", "maprules", "mapplacer" }
  local data = cache and cache ~= "" and { gen2Maps = dofile(cache .. "/maps.lua") } or nil
  if not ok(data ~= nil, "real libraries need CRYSTAL_RANDOMIZER_CACHE") then data = { gen2Maps = {} } end
  local vanilla = snapshot(data)
  local ctx = Fake.new({ seed = "maps-real-1", options = { maps = os.getenv("MAPS_LEVEL") or "houses" } })
  local mod = { game = { data = data }, hooks = { wrap = function() end }, events = { on = function() end } }
  for _, name in ipairs(names) do
    local path = "launcher/mods/crystal_randomizer/modules/" .. name .. ".lua"
    local f = io.open(path, "r")
    if not f and name == "maprules" and os.getenv("MAPS_STUB_RULES") == "1" then
      -- while maprules is unwritten: nothing fixed, everything winnable
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
    local moved, back, total = 0, 0, 0
    for doorId, targetId in pairs(shared.placement) do
      if doorId ~= targetId then
        moved = moved + 1
        local door, target = graph.doors[doorId], graph.doors[targetId]
        for _, spot in ipairs(target.inside or {}) do
          total = total + 1
          local walker = newWalker(data)
          walker.take(door.map, door.warp)
          local m, w = walker.take(spot.map, spot.warp)
          if m == door.map and w == door.warp then back = back + 1
          else print(("  out of %s:%d after entering %s went to %s:%s"):format(spot.map, spot.warp, doorId,
            tostring(m), tostring(w))) end
        end
      end
    end
    print(("real libraries: %d doors moved, %d of %d ways out return to the door used"):format(moved, back, total))
    eq(back, total, "real libraries: every way out returns to the door used")
  end
  switch(ctx, false)
  eq(snapshot(data), vanilla, "real libraries: a vanilla save restores exactly")
end

print(("maps_test: %d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
