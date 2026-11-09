-- luajit launcher/mods/crystal_randomizer/tests/mapgraph_test.lua   (from the repository root)
--
-- 1. A small fixture shaped like Crystal's special cases: a house with a
--    two-tile doorway, a gate between two routes, two Pokemon Centers sharing
--    one $ff upstairs with a trade room, a store whose $ff elevator joins a
--    basement reached from the town's underground, a ship entered from two
--    ports onto a self-named $ff warp, a cave with an outdoor courtyard
--    holding a shop, a passage with doors on two outdoor maps, and a one-way
--    door.  Exact results are checked.
-- 2. With CRYSTAL_RANDOMIZER_CACHE set to an imported cache's data/generated
--    folder, the real Crystal maps: every outdoor warp into a non-outdoor map
--    is a door of exactly one complex, every complex and annex is reachable
--    from New Bark Town (ignoring what crossing needs), the build is
--    deterministic and leaves the data untouched, and the counts are printed.
local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Module = dofile("launcher/mods/crystal_randomizer/modules/mapgraph.lua")

local failures, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
  return cond
end
local function eq(a, b, msg) return ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
local function list(t) return table.concat(t or {}, ",") end

-- A stable text form of any table: keys sorted, so two equal graphs print alike.
local function serialize(v, out)
  out = out or {}
  local t = type(v)
  if t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      if type(a) == type(b) then return a < b end
      return type(a) < type(b)
    end)
    out[#out + 1] = "{"
    for _, k in ipairs(keys) do
      out[#out + 1] = tostring(k) .. "="
      serialize(v[k], out)
      out[#out + 1] = ","
    end
    out[#out + 1] = "}"
  elseif t ~= "function" then
    out[#out + 1] = tostring(v)
  end
  return out
end
local function text(v) return table.concat(serialize(v)) end

-- The same maps inserted in the reverse order, so pairs() walks differently.
local function reinserted(maps)
  local ids = {}
  for id in pairs(maps) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b) return a > b end)
  local copy = {}
  for _, id in ipairs(ids) do copy[id] = maps[id] end
  return copy
end

-- ------------------------------------------------------------ independent checks
-- Written apart from the module: reads only the raw warps and the graph.
local OUTDOOR = { ROUTE = true, TOWN = true }

local function checkDoors(data, graph, label)
  local maps = data.gen2Maps
  local owners = {}
  for _, cid in ipairs(graph.complexOrder) do
    for _, did in ipairs(graph.complexes[cid].doors) do
      owners[did] = (owners[did] or 0) + 1
      eq(graph.doors[did] and graph.doors[did].complex, cid, label .. ": door " .. did .. " names its complex")
    end
  end
  local warpsIn = 0
  for id, def in pairs(maps) do
    if OUTDOOR[def.environment] then
      for index, w in ipairs(def.warps or {}) do
        local dest = maps[w.destMap]
        if dest and not OUTDOOR[dest.environment] and w.destWarp ~= 0xff and (dest.warps or {})[w.destWarp] then
          warpsIn = warpsIn + 1
          local did = id .. ":" .. index
          eq(owners[did], 1, label .. ": outdoor warp " .. did .. " is a door of exactly one complex")
          local door = graph.doors[did]
          if ok(door, label .. ": " .. did .. " is in graph.doors") then
            eq(door.map, id, label .. ": " .. did .. ".map")
            eq(door.warp, index, label .. ": " .. did .. ".warp")
            local complex = graph.complexes[door.complex]
            local holds = false
            for _, m in ipairs(complex and complex.maps or {}) do if m == w.destMap then holds = true end end
            ok(holds, label .. ": " .. did .. " leads into a map of its complex")
            for _, back in ipairs(door.inside) do
              local bw = maps[back.map].warps[back.warp]
              if back.backup then
                ok(bw.destWarp == 0xff and bw.destMap == back.map, label .. ": backup inside of " .. did)
              else
                ok(bw.destMap == id and bw.destWarp == index, label .. ": inside warp of " .. did .. " leads back to it")
              end
            end
          end
        end
      end
    end
  end
  eq(#graph.doorOrder, warpsIn, label .. ": doors are exactly the outdoor warps into complexes")
  local listed = 0
  for _ in pairs(graph.doors) do listed = listed + 1 end
  eq(listed, warpsIn, label .. ": graph.doors holds nothing else")
  for id, def in pairs(maps) do
    eq(graph.outdoor[id] == true, OUTDOOR[def.environment] == true, label .. ": outdoor flag of " .. id)
  end
  -- every non-outdoor map is in exactly one complex, annex or isolated set
  local seen = {}
  local function mark(group, kind)
    for _, m in ipairs(group.maps) do
      ok(not seen[m], label .. ": " .. m .. " in one group only (" .. kind .. " " .. group.id .. ")")
      seen[m] = true
    end
  end
  for _, cid in ipairs(graph.complexOrder) do mark(graph.complexes[cid], "complex") end
  for _, aid in ipairs(graph.annexOrder) do mark(graph.annexes[aid], "annex") end
  for _, iid in ipairs(graph.isolatedOrder) do mark(graph.isolated[iid], "isolated") end
  for id, def in pairs(maps) do
    if not OUTDOOR[def.environment] then ok(seen[id], label .. ": " .. id .. " is grouped") end
  end
  -- dead ends and kinds
  local KINDS = { house = true, center = true, mart = true, gym = true, gate = true, cave = true,
    dungeon = true, building = true }
  for _, cid in ipairs(graph.complexOrder) do
    local c = graph.complexes[cid]
    ok(KINDS[c.kind], label .. ": " .. cid .. " has a known kind (" .. tostring(c.kind) .. ")")
    eq(c.deadEnd, #c.entrances == 1, label .. ": " .. cid .. " deadEnd means one entrance")
    eq(c.story, false, label .. ": " .. cid .. " story is left to maprules")
    ok(#c.doors >= 1, label .. ": " .. cid .. " has a door")
  end
end

-- Breadth-first over outdoor connections and doors, from one outdoor map.
local function checkReach(data, graph, start, label)
  local maps = data.gen2Maps
  local outdoorSeen, complexSeen = { [start] = true }, {}
  local doorsOn = {}
  for _, did in ipairs(graph.doorOrder) do
    local d = graph.doors[did]
    doorsOn[d.map] = doorsOn[d.map] or {}
    table.insert(doorsOn[d.map], d)
  end
  local neighbours = {}
  for id, def in pairs(maps) do
    if OUTDOOR[def.environment] then
      for _, c in pairs(def.connections or {}) do
        local other = type(c) == "table" and c.mapId
        if other and maps[other] then
          neighbours[id] = neighbours[id] or {}; table.insert(neighbours[id], other)
          neighbours[other] = neighbours[other] or {}; table.insert(neighbours[other], id)
        end
      end
    end
  end
  local queue = { { "o", start } }
  local head = 1
  while queue[head] do
    local kind, id = queue[head][1], queue[head][2]
    head = head + 1
    if kind == "o" then
      for _, other in ipairs(neighbours[id] or {}) do
        if not outdoorSeen[other] then outdoorSeen[other] = true; queue[#queue + 1] = { "o", other } end
      end
      for _, d in ipairs(doorsOn[id] or {}) do
        if not complexSeen[d.complex] then complexSeen[d.complex] = true; queue[#queue + 1] = { "c", d.complex } end
      end
    else
      for _, did in ipairs(graph.complexes[id].doors) do
        local m = graph.doors[did].map
        if not outdoorSeen[m] then outdoorSeen[m] = true; queue[#queue + 1] = { "o", m } end
      end
    end
  end
  for _, cid in ipairs(graph.complexOrder) do ok(complexSeen[cid], label .. ": complex " .. cid .. " is reachable") end
  for _, aid in ipairs(graph.annexOrder) do
    local any = false
    for _, cid in ipairs(graph.annexes[aid].complexes) do if complexSeen[cid] then any = true end end
    ok(any, label .. ": annex " .. aid .. " is reachable through a complex")
  end
  for _, id in ipairs(graph.outdoorOrder) do ok(outdoorSeen[id], label .. ": outdoor map " .. id .. " is reachable") end
  eq(#graph.isolatedOrder, 0, label .. ": no non-outdoor group without a door (" .. list(graph.isolatedOrder) .. ")")
end

local function checkStable(data, build, label)
  local before = text(data.gen2Maps)
  local a = build(data)
  local b = build({ gen2Maps = reinserted(data.gen2Maps) })
  eq(text(a), text(b), label .. ": same graph whatever the table order")
  eq(text(data.gen2Maps), before, label .. ": the data is left untouched")
  for _, key in ipairs({ "doorOrder", "entranceOrder" }) do
    for i = 2, #a[key] do ok(Module._M.doorLess(a[key][i - 1], a[key][i]), label .. ": " .. key .. " sorted") end
  end
  for _, key in ipairs({ "complexOrder", "outdoorOrder", "annexOrder" }) do
    for i = 2, #a[key] do ok(a[key][i - 1] < a[key][i], label .. ": " .. key .. " sorted") end
  end
  for _, cid in ipairs(a.complexOrder) do
    local c = a.complexes[cid]
    for i = 2, #c.maps do ok(c.maps[i - 1] < c.maps[i], label .. ": " .. cid .. " maps sorted") end
    for i = 2, #c.doors do ok(Module._M.doorLess(c.doors[i - 1], c.doors[i]), label .. ": " .. cid .. " doors sorted") end
  end
  return a
end

local function report(graph, label)
  local c = graph.counts
  local kinds = {}
  for k, n in pairs(c.kinds) do kinds[#kinds + 1] = k .. "=" .. n end
  table.sort(kinds)
  print(string.format("  %s: %d complexes (%s), %d dead ends, %d doors in %d entrances, %d annexes, %d outdoor maps",
    label, c.complexes, table.concat(kinds, " "), c.deadEnds, c.doors, c.entrances, c.annexes, c.outdoor))
  local keys = {}
  for k in pairs(graph.special) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local items = {}
    for _, v in ipairs(graph.special[k]) do
      items[#items + 1] = type(v) == "table" and (v.map .. ":" .. v.warp .. (v.destMap and (">" .. tostring(v.destMap)
        .. ":" .. tostring(v.destWarp)) or "")) or v
    end
    if #items > 0 then print(string.format("    %s (%d): %s", k, #items, table.concat(items, " "))) end
  end
end

-- ------------------------------------------------------------ module shape
do
  eq(Module.id, "mapgraph", "module id")
  eq(#Module.questions, 0, "mapgraph asks nothing")
  local ctx = Fake.new({ seed = "test", options = {} })
  Module.install({}, ctx)
  ok(type(ctx.lib.mapGraph) == "table" and type(ctx.lib.mapGraph.build) == "function", "install sets ctx.lib.mapGraph.build")
  local shared = 0
  for _ in pairs(ctx.shared) do shared = shared + 1 end
  eq(shared, 0, "install writes nothing to ctx.shared")
  ok(Module._M.doorLess("ROUTE_29:3", "ROUTE_29:10"), "door ids sort by warp number")
end

-- ------------------------------------------------------------ 1. the fixture
local function w(x, y, destMap, destWarp) return { x = x, y = y, destMap = destMap, destWarp = destWarp } end
local function map(env, warps, connections) return { environment = env, warps = warps, connections = connections or {} } end

local FIXTURE = {
  -- TOWN_A: 1 house (2-tile doorway, tiles 1 and 2), 3 center A, 4 store, 5/6 underground, 7 passage
  TOWN_A = map("TOWN", {
    w(4, 5, "HOUSE_1F", 1), w(5, 5, "HOUSE_1F", 2), w(10, 5, "A_POKECENTER_1F", 1), w(14, 5, "STORE_1F", 1),
    w(20, 5, "UNDERGROUND", 1), w(30, 5, "UNDERGROUND", 2), w(8, 12, "PASSAGE", 1),
  }, { east = { mapId = "ROUTE_A" } }),
  HOUSE_1F = map("INDOOR", { w(4, 7, "TOWN_A", 1), w(5, 7, "TOWN_A", 1), w(7, 0, "HOUSE_2F", 1) }),
  HOUSE_2F = map("INDOOR", { w(7, 0, "HOUSE_1F", 3) }),
  A_POKECENTER_1F = map("INDOOR", { w(3, 7, "TOWN_A", 3), w(4, 7, "TOWN_A", 3), w(0, 7, "POKECENTER_2F", 1) }),
  B_POKECENTER_1F = map("INDOOR", { w(3, 7, "ROUTE_B", 2), w(4, 7, "ROUTE_B", 2), w(0, 7, "POKECENTER_2F", 1) }),
  POKECENTER_2F = map("INDOOR", { w(0, 7, "POKECENTER_2F", 0xff), w(5, 0, "TRADE_ROOM", 1) }),
  TRADE_ROOM = map("INDOOR", { w(4, 7, "POKECENTER_2F", 2) }),
  STORE_1F = map("INDOOR", { w(7, 7, "TOWN_A", 4), w(8, 7, "TOWN_A", 4), w(1, 0, "STORE_ELEVATOR", 1) }),
  STORE_ELEVATOR = map("INDOOR", { w(1, 3, "STORE_1F", 0xff) }),
  STORE_B1F = map("DUNGEON", { w(1, 0, "STORE_ELEVATOR", 1), w(9, 9, "UNDERGROUND", 3) }),
  UNDERGROUND = map("DUNGEON", { w(0, 0, "TOWN_A", 5), w(9, 0, "TOWN_A", 6), w(5, 5, "STORE_B1F", 2) }),
  PASSAGE = map("INDOOR", { w(0, 0, "TOWN_A", 7), w(9, 9, "PORT_A", 1) }),
  -- ROUTE_A: gate to ROUTE_B (2-tile on this side), the cave
  ROUTE_A = map("ROUTE", { w(2, 0, "GATE_AB", 1), w(3, 0, "GATE_AB", 2), w(9, 9, "CAVE_1F", 1) },
    { west = { mapId = "TOWN_A" } }),
  GATE_AB = map("GATE", { w(4, 7, "ROUTE_A", 1), w(5, 7, "ROUTE_A", 2), w(4, 0, "ROUTE_B", 1) }),
  ROUTE_B = map("ROUTE", { w(4, 9, "GATE_AB", 3), w(8, 3, "B_POKECENTER_1F", 1), w(1, 1, "LOST_HOUSE", 1) }),
  LOST_HOUSE = map("INDOOR", { w(1, 1, "ROUTE_A", 3) }),  -- leads to the cave's door tile: an unpaired exit
  -- the cave with its outdoor courtyard and the courtyard's shop
  CAVE_1F = map("CAVE", { w(1, 1, "ROUTE_A", 3), w(5, 5, "COURTYARD", 1), w(6, 6, "CAVE_B1F", 1) }),
  CAVE_B1F = map("CAVE", { w(6, 6, "CAVE_1F", 3) }),
  COURTYARD = map("ROUTE", { w(5, 5, "CAVE_1F", 2), w(9, 2, "COURTYARD_SHOP", 1) }),
  COURTYARD_SHOP = map("INDOOR", { w(2, 7, "COURTYARD", 2), w(3, 7, "COURTYARD", 2) }),
  -- two ports onto a ship whose way out is $ff to itself; port B also has a one-way hole
  PORT_A = map("ROUTE", { w(9, 9, "PASSAGE", 2), w(4, 4, "SHIP_1F", 1) }),
  PORT_B = map("ROUTE", { w(4, 4, "SHIP_1F", 1), w(7, 7, "PIT", 1) }, { north = { mapId = "ROUTE_B" } }),
  SHIP_1F = map("INDOOR", { w(4, 4, "SHIP_1F", 0xff), w(8, 0, "SHIP_CABIN", 1) }),
  SHIP_CABIN = map("INDOOR", { w(0, 0, "SHIP_1F", 2) }),
  PIT = map("CAVE", { w(3, 3, "PIT", 1) }),  -- lands on its own warp, never leads out
}

do
  local data = { gen2Maps = FIXTURE }
  local graph = checkStable(data, Module._M.build, "fixture")
  checkDoors(data, graph, "fixture")
  checkReach(data, graph, "TOWN_A", "fixture")
  report(graph, "fixture")
  local C, D = graph.complexes, graph.doors

  eq(list(graph.complexOrder), "A_POKECENTER_1F,B_POKECENTER_1F,CAVE_1F,COURTYARD_SHOP,GATE_AB,HOUSE_1F,LOST_HOUSE,"
    .. "PASSAGE,PIT,SHIP_1F,STORE_1F", "fixture: complexes")
  -- house: two-tile doorway is one entrance, still a dead end; upstairs joined
  eq(list(C.HOUSE_1F.maps), "HOUSE_1F,HOUSE_2F", "house holds its upstairs")
  eq(list(C.HOUSE_1F.doors), "TOWN_A:1,TOWN_A:2", "house: both tiles are doors")
  eq(list(C.HOUSE_1F.entrances), "TOWN_A:1", "house: one entrance")
  eq(D["TOWN_A:2"].entrance, "TOWN_A:1", "house: tile 2 belongs to entrance TOWN_A:1")
  eq(C.HOUSE_1F.deadEnd, true, "house is a dead end")
  eq(C.HOUSE_1F.kind, "house", "house kind")
  eq(#D["TOWN_A:1"].inside, 2, "house: both inside tiles lead back to TOWN_A:1")
  eq(#D["TOWN_A:2"].inside, 0, "house: tile 2 has nothing leading back")
  eq(#graph.entrances["TOWN_A:1"].inside, 2, "house: the entrance gathers both inside tiles")
  -- centers: the shared upstairs is an annex, not part of either
  eq(C.A_POKECENTER_1F.kind, "center", "center kind")
  eq(list(C.A_POKECENTER_1F.maps), "A_POKECENTER_1F", "center A without the upstairs")
  eq(list(C.A_POKECENTER_1F.annexes), "POKECENTER_2F", "center A reaches the annex")
  eq(list(graph.annexOrder), "POKECENTER_2F", "one annex")
  eq(list(graph.annexes.POKECENTER_2F.maps), "POKECENTER_2F,TRADE_ROOM", "the annex holds the trade room")
  eq(list(graph.annexes.POKECENTER_2F.complexes), "A_POKECENTER_1F,B_POKECENTER_1F", "annex shared by both centers")
  eq(#graph.annexes.POKECENTER_2F.entries, 2, "annex: one stair per center")
  eq(graph.complexOf.TRADE_ROOM, "POKECENTER_2F", "complexOf names the annex")
  -- store: the $ff elevator joins the basement and the underground into it
  eq(list(C.STORE_1F.maps), "STORE_1F,STORE_B1F,STORE_ELEVATOR,UNDERGROUND", "store joined through its elevator")
  eq(list(C.STORE_1F.doors), "TOWN_A:4,TOWN_A:5,TOWN_A:6", "store doors include the underground's")
  eq(C.STORE_1F.deadEnd, false, "store with underground is not a dead end")
  eq(C.STORE_1F.environment, "DUNGEON", "store: two dungeon maps of four, tie to DUNGEON")
  eq(list(C.STORE_1F.environments), "DUNGEON,INDOOR", "store environments")
  eq(list(graph.special.elevators), "STORE_ELEVATOR", "elevator reported")
  -- gate: two outdoor maps, two-tile on one side
  eq(C.GATE_AB.kind, "gate", "gate kind")
  eq(list(C.GATE_AB.entrances), "ROUTE_A:1,ROUTE_B:1", "gate: one entrance per side")
  eq(list(C.GATE_AB.outdoorMaps), "ROUTE_A,ROUTE_B", "gate: both outdoor maps")
  -- ship: two ports, the way out is the $ff warp
  eq(list(C.SHIP_1F.doors), "PORT_A:2,PORT_B:1", "ship doors on two ports")
  eq(D["PORT_A:2"].backup, true, "ship door returns by backup")
  eq(D["PORT_A:2"].inside[1].map .. ":" .. D["PORT_A:2"].inside[1].warp, "SHIP_1F:1", "ship inside is the $ff warp")
  eq(D["PORT_A:2"].inside[1].backup, true, "ship inside marked backup")
  eq(list(graph.special.backupDoors), "PORT_A:2,PORT_B:1", "backup doors reported")
  eq(list(graph.special.backupMaps), "POKECENTER_2F,SHIP_1F", "backup maps reported")
  -- passage with doors on two outdoor maps
  eq(list(C.PASSAGE.outdoorMaps), "PORT_A,TOWN_A", "passage spans two outdoor maps")
  ok(list(graph.special.multiOutdoor):find("PASSAGE", 1, true), "passage reported as multi-outdoor")
  -- cave: courtyard doors belong to the cave; the courtyard shop is its own dead end
  eq(list(C.CAVE_1F.maps), "CAVE_1F,CAVE_B1F", "cave floors")
  eq(list(C.CAVE_1F.doors), "COURTYARD:1,ROUTE_A:3", "cave doors include the courtyard's")
  eq(C.CAVE_1F.kind, "cave", "cave kind")
  eq(C.COURTYARD_SHOP.deadEnd, true, "courtyard shop is a dead end")
  eq(graph.outdoor.COURTYARD, true, "courtyard is outdoor")
  -- odd warps
  eq(list(graph.special.oneWayDoors), "PORT_B:2,ROUTE_B:3", "the pit and the lost house are one-way doors")
  eq(#graph.special.unpairedExits, 1, "one unpaired exit")
  eq(graph.special.unpairedExits[1].map, "LOST_HOUSE", "the unpaired exit is LOST_HOUSE's")
  eq(list(graph.special.enterOnlyTiles), "TOWN_A:2", "enter-only tiles")
  eq(graph.counts.complexes, 11, "fixture complex count")
  eq(graph.counts.deadEnds, 6, "fixture dead ends")
end

-- ------------------------------------------------------------ 2. real Crystal data
local cache = os.getenv("CRYSTAL_RANDOMIZER_CACHE")
if cache and cache ~= "" then
  local data = { gen2Maps = dofile(cache .. "/maps.lua") }
  local graph = checkStable(data, Module._M.build, "crystal")
  checkDoors(data, graph, "crystal")
  checkReach(data, graph, "NEW_BARK_TOWN", "crystal")
  report(graph, "crystal")
  local C = graph.complexes
  local A = graph.annexes.POKECENTER_2F
  if ok(A, "crystal: POKECENTER_2F is an annex") then
    eq(#A.complexes, graph.counts.kinds.center, "crystal: every center shares the upstairs")
    for _, cid in ipairs(graph.complexOrder) do
      if C[cid].kind == "center" then eq(list(C[cid].annexes), "POKECENTER_2F", "crystal: " .. cid .. " has the upstairs") end
    end
  end
  local function holds(cid, m)
    for _, x in ipairs(C[cid] and C[cid].maps or {}) do if x == m then return true end end
    return false
  end
  ok(holds("GOLDENROD_DEPT_STORE_1F", "GOLDENROD_DEPT_STORE_ELEVATOR"), "crystal: Goldenrod elevator in the store")
  ok(holds("GOLDENROD_DEPT_STORE_1F", "GOLDENROD_DEPT_STORE_B1F"), "crystal: the basement joined through the elevator")
  ok(holds("GOLDENROD_DEPT_STORE_1F", "GOLDENROD_UNDERGROUND"), "crystal: the underground joined to the store")
  ok(holds("CELADON_DEPT_STORE_1F", "CELADON_DEPT_STORE_ELEVATOR"), "crystal: Celadon elevator in the store")
  eq(list(C.FAST_SHIP_1F and C.FAST_SHIP_1F.doors), "OLIVINE_PORT:2,VERMILION_PORT:2", "crystal: ship doors")
  eq(graph.doors["OLIVINE_PORT:2"].backup, true, "crystal: the ship returns by backup")
  eq(list(C.OLIVINE_PORT_PASSAGE.outdoorMaps), "OLIVINE_CITY,OLIVINE_PORT", "crystal: port passage spans two maps")
  eq(C.ILEX_FOREST_AZALEA_GATE.deadEnd, false, "crystal: Ilex Forest is a way through")
  eq(C.AZALEA_POKECENTER_1F.deadEnd, true, "crystal: a center is a dead end")
  eq(C.INDIGO_PLATEAU_POKECENTER_1F.deadEnd, true, "crystal: Indigo's two-tile doorway is one entrance")
  eq(graph.doors["MOUNT_MOON_SQUARE:3"].complex, "MOUNT_MOON_GIFT_SHOP", "crystal: the gift shop opens off the square")
  eq(#graph.special.unpairedExits, 0, "crystal: every complex warp outdoors pairs with a door")
  eq(#graph.special.badWarps, 0, "crystal: no warp to a missing map or warp")
  print("real Crystal data checked: " .. cache)
else
  print("  (set CRYSTAL_RANDOMIZER_CACHE to an imported cache's data/generated folder to check real data)")
end

print(string.format("mapgraph: %d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
