-- A Crystal game run for the maps module (door shuffle).  Silent; read the
-- PASS, FAIL, RESULT and NOTE lines.
--
-- Part A, the whole mod as installed in the profile's mods folder: a copy of
-- the start save gets modData.crystal_randomizer = { seed, options = { maps =
-- MAPS_LEVEL or "houses" } } and goes through game:continueGame.  If the map
-- libraries (mapgraph, maprules, mapplacer) are installed and placed doors,
-- the driver walks through the first moved door it can reach and back out,
-- logging each map arrived at, then loads a plain copy and checks every warp
-- is vanilla again.
--
-- Part B, the module on the real data and the real world: maps.lua installed
-- with tests/fake_ctx.lua, the real mapgraph's graph, a permissive rules stub
-- and a fixed entrance placement: the one-tile CHERRYGROVE_CITY:3 (gym speech
-- house) swaps with the two-tile ROUTE_23:1/:2 doorway (Indigo Plateau
-- centre), and CHERRYGROVE_CITY:4 and :5 swap.  All their exits are explicit
-- warps, the case the module rewrites.  For each tile the player is put on the
-- ground below it, walks up through the door, logs where they arrived, walks
-- down out over the mat, and logs where they came out (for ROUTE_23:2, the
-- entrance's first tile ROUTE_23:1).  Then a vanilla save, and the warps are
-- checked against the start.
--
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_BACKGROUND=1 POKEPORT_VERSION=crystal
--   POKEPORT_IDENTITY=pocket-access-maps-apply
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=launcher/mods/crystal_randomizer/tests/maps_driver.lua
--   "C:\Program Files\LOVE\lovec.exe" .
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  if not L.settle(3000, true) then U.log("FAIL", "never reached the free world") return end
  local data = game.data
  local maps = data.gen2Maps
  local FF = 0xff
  local OUTDOOR = { ROUTE = true, TOWN = true }

  local function snapshot()
    local ids = {}
    for id in pairs(maps) do ids[#ids + 1] = id end
    table.sort(ids)
    local out = {}
    for _, id in ipairs(ids) do
      for i, w in ipairs(maps[id].warps or {}) do
        out[#out + 1] = id .. ":" .. i .. "=" .. tostring(w.destMap) .. ":" .. tostring(w.destWarp)
      end
    end
    return out
  end
  local function differences(a, b)
    local n, first = 0, {}
    for i = 1, math.max(#a, #b) do
      if a[i] ~= b[i] then
        n = n + 1
        if #first < 6 then first[#first + 1] = tostring(a[i]) .. " now " .. tostring(b[i]) end
      end
    end
    return n, table.concat(first, "; ")
  end
  local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
  end

  local vanilla = snapshot()
  local start = copy(game.save)
  U.log("RESULT", "start", L.where(), "warps", #vanilla)

  -- Walk through outdoor warp `index` of `mapId` from the tile below it, then
  -- out over the mat.  Returns where the player arrived inside and outside.
  local function walkThrough(mapId, index, label)
    local w = maps[mapId].warps[index]
    game.save.repelSteps = 60000
    L.teleport(mapId, w.x, w.y + 1, "up")
    local here = L.where()
    U.log("RESULT", label, "standing below door", mapId .. ":" .. index, "at", here,
      "door says", tostring(w.destMap) .. ":" .. tostring(w.destWarp))
    L.hold("up", 24)
    L.settle(400, true)
    local inMap = L.pos()
    U.log("RESULT", label, "walked up through the door, arrived in", L.where())
    L.hold("down", 24)
    L.settle(400, true)
    local outMap, ox, oy = L.pos()
    U.log("RESULT", label, "walked down out of", inMap, "came out at", L.where())
    return inMap, outMap, ox, oy, w
  end

  -- `returnIndex`: the outdoor warp leaving should come out at (the first tile
  -- of the entrance used; default the door itself).  The player comes out on
  -- that tile or the one below it.
  local function checkWalk(label, mapId, index, wantInside, returnIndex)
    local inMap, outMap, ox, oy = walkThrough(mapId, index, label)
    U.log(inMap == wantInside and "PASS" or "FAIL", label, "door", mapId .. ":" .. index, "leads into",
      tostring(inMap), "want", tostring(wantInside))
    local r = maps[mapId].warps[returnIndex or index]
    local back = outMap == mapId and ox == r.x and (oy == r.y or oy == r.y + 1)
    U.log(back and "PASS" or "FAIL", label, "leaving", tostring(inMap), "comes out at",
      mapId .. ":" .. (returnIndex or index), "(" .. r.x .. "," .. r.y .. ")",
      "(got " .. outMap .. " " .. ox .. "," .. oy .. ")")
  end

  -- ------------------------------------------------------------ part A: the whole mod
  local level = os.getenv("MAPS_LEVEL") or "houses"
  local seed = os.getenv("RANDOMIZER_SEED") or "424242"
  local save = copy(start)
  save.modData = save.modData or {}
  save.modData.crystal_randomizer = { seed = seed, options = { maps = level }, version = 1 }
  game:continueGame(save)
  L.settle(600, true)
  local shuffled = snapshot()
  local changed, sample = differences(vanilla, shuffled)
  U.log("RESULT", "A: whole mod, seed", seed, "maps =", level, "warp fields changed:", changed, sample)
  if changed == 0 then
    U.log("NOTE", "A: the whole mod moved no door (are mapgraph, maprules and mapplacer installed? "
      .. "the mod log says why)")
  else
    -- the first outdoor door whose destination moved, in sorted order
    local tried = 0
    for i, entry in ipairs(shuffled) do
      if entry ~= vanilla[i] and tried < 2 then
        local mapId, index = entry:match("^([%w_]+):(%d+)=")
        index = tonumber(index)
        if maps[mapId] and OUTDOOR[maps[mapId].environment] then
          tried = tried + 1
          checkWalk("A" .. tried, mapId, index, maps[mapId].warps[index].destMap)
        end
      end
    end
    if tried == 0 then U.log("NOTE", "A: no moved outdoor door found to walk") end
  end
  local plain = copy(start)
  if plain.modData then plain.modData.crystal_randomizer = nil end
  game:continueGame(plain)
  L.settle(600, true)
  local n = differences(vanilla, snapshot())
  U.log(n == 0 and "PASS" or "FAIL", "A: a plain save after the shuffled one has vanilla warps", n)

  -- ------------------------------------------------------------ part B: the module alone
  -- The real mapgraph builds the graph; the placement is fixed by entrance:
  -- the one-tile Cherrygrove gym speech house door (CHERRYGROVE_CITY:3) swaps
  -- with the two-tile Indigo Plateau centre doorway (ROUTE_23:1 and :2), and
  -- the guide gent and evolution speech houses (:4, :5) swap with each other.
  local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
  local Maps = dofile("launcher/mods/crystal_randomizer/modules/maps.lua")
  local ctx = Fake.new({ seed = "maps-driver", options = { maps = "full" } })
  local graphModule = dofile("launcher/mods/crystal_randomizer/modules/mapgraph.lua")
  graphModule.install({ game = game }, ctx)
  if not (ctx.lib.mapGraph and ctx.lib.mapGraph.build) then U.log("FAIL", "B: mapgraph offers no build") return end
  local graph = ctx.lib.mapGraph.build(data)
  local SWAP = { ["CHERRYGROVE_CITY:3"] = "ROUTE_23:1", ["ROUTE_23:1"] = "CHERRYGROVE_CITY:3",
    ["CHERRYGROVE_CITY:4"] = "CHERRYGROVE_CITY:5", ["CHERRYGROVE_CITY:5"] = "CHERRYGROVE_CITY:4" }
  for eid in pairs(SWAP) do
    if not (graph.entrances and graph.entrances[eid]) then U.log("FAIL", "B: no entrance", eid) return end
  end
  U.log("RESULT", "B: ROUTE_23:1 entrance tiles", table.concat(graph.entrances["ROUTE_23:1"].doors, " "))
  local placement = { entrances = {} }
  for did in pairs(graph.doors) do placement[did] = did end
  for eid in pairs(graph.entrances) do placement.entrances[eid] = eid end
  for eid, tid in pairs(SWAP) do
    placement.entrances[eid] = tid
    for _, did in ipairs(graph.entrances[eid].doors) do placement[did] = graph.entrances[tid].doors[1] end
  end
  ctx.lib.mapRules = { model = function() return { fixed = {}, canWin = function() return true end } end }
  ctx.lib.mapPlacer = { place = function() return placement, { note = "fixed driver swaps" } end }
  local inside = {}
  for eid in pairs(SWAP) do
    local d = graph.doors[graph.entrances[eid].doors[1]]
    inside[eid] = maps[d.map].warps[d.warp].destMap
  end
  Maps.install({ game = game }, ctx)
  ctx.setActive(true)
  for _, line in ipairs(ctx.lines) do U.log("MODLOG", line) end
  U.log(ctx.shared.maps and "PASS" or "FAIL", "B: placement published")
  local walks = {
    { "CHERRYGROVE_CITY", 3, "ROUTE_23:1", 3 },
    { "ROUTE_23", 1, "CHERRYGROVE_CITY:3", 1 },
    { "ROUTE_23", 2, "CHERRYGROVE_CITY:3", 1 },  -- second tile: comes out at the first
    { "CHERRYGROVE_CITY", 4, "CHERRYGROVE_CITY:5", 4 },
    { "CHERRYGROVE_CITY", 5, "CHERRYGROVE_CITY:4", 5 },
  }
  for _, w in ipairs(walks) do
    checkWalk("B " .. w[1] .. ":" .. w[2], w[1], w[2], inside[w[3]], w[4])
  end
  ctx.setActive(false)
  local m = differences(vanilla, snapshot())
  U.log(m == 0 and "PASS" or "FAIL", "B: a vanilla save restores every warp", m)
  -- and the vanilla doors walk as vanilla
  checkWalk("B vanilla", "CHERRYGROVE_CITY", 3, inside["CHERRYGROVE_CITY:3"])
  checkWalk("B vanilla", "ROUTE_23", 2, inside["ROUTE_23:1"], 2)
  U.log("DONE")
  love.event.quit()
end