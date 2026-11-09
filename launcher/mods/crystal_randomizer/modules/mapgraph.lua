-- Crystal randomizer: the door graph (MAPS.md, "mapgraph").
--
-- Reads the vanilla warp tables in data.gen2Maps and describes them as doors
-- and complexes for the map randomizer's other modules.  Nothing here is
-- random and nothing changes the data: install only offers
-- ctx.lib.mapGraph.build(data), which returns a fresh table every call.
--
-- Terms (MAPS.md "What a door is"):
--   outdoor map   environment ROUTE or TOWN.
--   complex       non-outdoor maps joined by their own warps.
--   door          one outdoor warp leading into a complex, with the complex
--                 warps that lead back to it (`inside`).
--   dead end      a complex with exactly one entrance (see below).
--
-- How maps are joined into complexes.  A warp A -> B between two non-outdoor
-- maps joins them, with two exceptions that come from Gen 2's destination
-- warp -1 ($ff, World:resolveWarp / World:recordWarpBackup):
--
--   * A $ff warp whose destMap is ANOTHER map (the department store
--     elevators, whose doors say "CELADON_DEPT_STORE_1F, -1") is a hub: the
--     cart's elevator script picks the floor, so the elevator joins every map
--     that enters it and the map it names.  This is what puts Goldenrod's B1F
--     (reached from the Underground) in the same complex as the store.
--   * A $ff warp whose destMap is ITS OWN map (POKECENTER_2F, FAST_SHIP_1F)
--     names no destination at all: it returns to whatever warp led in.  An
--     arrival onto such a warp does not join the two maps by itself.  If the
--     map is entered from one complex only it joins that complex; if it is
--     entered from several (POKECENTER_2F is climbed into from every centre)
--     it is an ANNEX, shared by all of them and part of none.  An outdoor
--     warp arriving on one (the ports onto FAST_SHIP_1F) is an ordinary door
--     whose way back is the $ff warp (`inside` entry with backup = true).
--
-- Entrances.  Some doorways are two warp tiles wide on the outdoor side
-- (ILEX_FOREST_AZALEA_GATE from AZALEA_TOWN, ROUTE_23 into the Indigo
-- Plateau centre).  Each tile is a door, as MAPS.md says, but the tiles of one
-- doorway form one ENTRANCE: outdoor warps on the same map, into the same
-- complex, on orthogonally adjacent tiles.  `deadEnd` counts entrances, so a
-- house with a two-tile doorway is still a dead end, and a placer that moves
-- entrances together never splits one doorway between two destinations.
--
-- Determinism: every list is sorted (doors by map, then warp number; maps
-- and complex ids by name); nothing depends on pairs() order.

local OUTDOOR = { ROUTE = true, TOWN = true }
local BACKUP = 0xff
local ENV_TIE_ORDER = { CAVE = 1, DUNGEON = 2, INDOOR = 3, GATE = 4 }

local M = {}

-- "ROUTE_29:3" sorts before "ROUTE_29:10": map name, then warp number.
local function doorLess(a, b)
  local am, aw = a:match("^(.*):(%d+)$")
  local bm, bw = b:match("^(.*):(%d+)$")
  if am ~= bm then return am < bm end
  return tonumber(aw) < tonumber(bw)
end
M.doorLess = doorLess

local function doorId(map, warp) return map .. ":" .. warp end
M.doorId = doorId

local function sortedKeys(t, less)
  local list = {}
  for k in pairs(t) do list[#list + 1] = k end
  table.sort(list, less)
  return list
end

local function warpLess(a, b)
  if a.map ~= b.map then return a.map < b.map end
  return a.warp < b.warp
end

-- ------------------------------------------------------------ union-find
local function newSets()
  local parent = {}
  local sets = {}
  function sets.add(x) if parent[x] == nil then parent[x] = x end end
  function sets.find(x)
    local root = x
    while parent[root] ~= root do root = parent[root] end
    while parent[x] ~= root do parent[x], x = root, parent[x] end
    return root
  end
  -- The smaller name becomes the root, so roots never depend on visit order.
  function sets.union(a, b)
    local ra, rb = sets.find(a), sets.find(b)
    if ra == rb then return false end
    if rb < ra then ra, rb = rb, ra end
    parent[rb] = ra
    return true
  end
  return sets
end

-- ------------------------------------------------------------ kinds
local function nameKind(mapIds)
  local center, gym, mart = false, false, false
  for _, id in ipairs(mapIds) do
    if id:find("POKECENTER_1F$") then center = true end
    -- "_GYM_1F" yes, "CERULEAN_GYM_BADGE_SPEECH_HOUSE" no
    if id:find("_GYM$") or id:find("_GYM_B?%d+F$") then gym = true end
    if id:find("_MART$") then mart = true end
  end
  if center then return "center" end
  if gym then return "gym" end
  if mart then return "mart" end
  return nil
end

local function complexKind(complex)
  local env = complex.environment
  if env == "GATE" then return "gate" end
  if env == "CAVE" then return "cave" end
  if env == "DUNGEON" then return "dungeon" end
  local named = nameKind(complex.maps)
  if named then return named end
  if complex.deadEnd and #complex.maps <= 2 then return "house" end
  return "building"
end

-- ------------------------------------------------------------ build
function M.build(data)
  local maps = (data and data.gen2Maps) or {}
  local mapIds = {}
  for id, def in pairs(maps) do
    if type(id) == "string" and type(def) == "table" then mapIds[#mapIds + 1] = id end
  end
  table.sort(mapIds)

  local special = {
    badWarps = {},          -- { map, warp, destMap, destWarp, why }
    outdoorToOutdoor = {},  -- { map, warp, destMap, destWarp }
    outdoorBackupWarps = {},-- outdoor warps that are themselves $ff
    elevators = {},         -- maps whose $ff warp names another map (hubs)
    backupMaps = {},        -- maps whose $ff warp names themselves
    backupDoors = {},       -- doors whose way back is a $ff warp
    oneWayDoors = {},       -- doors whose whole entrance has nothing inside leading back
    enterOnlyTiles = {},    -- door tiles nothing leads back to, though a neighbour tile is
    unpairedExits = {},     -- complex warps onto an outdoor warp that does not lead back in
    multiOutdoor = {},      -- complexes with doors on more than one outdoor map
    mixedEnvironment = {},  -- complexes whose maps differ in environment
    doorsIntoAnnex = {},    -- outdoor warps straight into an annex (none expected)
    unknownEnvironment = {},-- maps with no environment (treated as non-outdoor)
  }

  local outdoor = {}
  for _, id in ipairs(mapIds) do
    local env = maps[id].environment
    if OUTDOOR[env] then outdoor[id] = true end
    if env == nil then special.unknownEnvironment[#special.unknownEnvironment + 1] = id end
  end

  local function warpsOf(id) return (maps[id] and maps[id].warps) or {} end
  local function selfBackup(id, index)
    local w = warpsOf(id)[index]
    return w and w.destWarp == BACKUP and w.destMap == id
  end

  -- 1. Join non-outdoor maps.  Arrivals on a self-named $ff warp are held back.
  local sets = newSets()
  for _, id in ipairs(mapIds) do if not outdoor[id] then sets.add(id) end end
  local deferred = {}   -- [arrivalMap] = { sourceMap = true }
  local elevatorSeen, backupSeen = {}, {}
  for _, id in ipairs(mapIds) do
    for index, w in ipairs(warpsOf(id)) do
      local dest = w.destMap
      local destDef = dest and maps[dest]
      if not destDef then
        special.badWarps[#special.badWarps + 1] = { map = id, warp = index, destMap = dest,
          destWarp = w.destWarp, why = "destination map is not in the data" }
      elseif w.destWarp == BACKUP then
        if dest == id then
          backupSeen[id] = true
        elseif not outdoor[id] and not outdoor[dest] then
          elevatorSeen[id] = true
          sets.union(id, dest)
        end
        if outdoor[id] then
          special.outdoorBackupWarps[#special.outdoorBackupWarps + 1] = { map = id, warp = index,
            destMap = dest }
        end
      elseif not (destDef.warps or {})[w.destWarp] then
        special.badWarps[#special.badWarps + 1] = { map = id, warp = index, destMap = dest,
          destWarp = w.destWarp, why = "destination warp does not exist" }
      elseif outdoor[id] and outdoor[dest] then
        special.outdoorToOutdoor[#special.outdoorToOutdoor + 1] = { map = id, warp = index,
          destMap = dest, destWarp = w.destWarp }
      elseif not outdoor[id] and not outdoor[dest] then
        if dest ~= id and selfBackup(dest, w.destWarp) then
          deferred[dest] = deferred[dest] or {}
          deferred[dest][id] = true
        else
          sets.union(id, dest)
        end
      end
    end
  end
  special.elevators = sortedKeys(elevatorSeen)
  special.backupMaps = sortedKeys(backupSeen)

  -- 2. A backup map entered from one complex joins it; from several, it is an
  -- annex.  Repeat, because one join can turn several sources into one.
  local annexArrival = {}
  local changed = true
  while changed do
    changed = false
    for _, dest in ipairs(sortedKeys(deferred)) do
      local target = sets.find(dest)
      local sources = {}
      for _, source in ipairs(sortedKeys(deferred[dest])) do
        local root = sets.find(source)
        if root ~= target then sources[root] = true end
      end
      local list = sortedKeys(sources)
      if #list == 1 then
        sets.union(list[1], dest)
        changed = true
      end
    end
  end
  for _, dest in ipairs(sortedKeys(deferred)) do
    local target = sets.find(dest)
    for source in pairs(deferred[dest]) do
      if sets.find(source) ~= target then annexArrival[dest] = true end
    end
  end

  -- Components: [root] = sorted list of maps.
  local members = {}
  for _, id in ipairs(mapIds) do
    if not outdoor[id] then
      local root = sets.find(id)
      members[root] = members[root] or {}
      members[root][#members[root] + 1] = id
    end
  end
  local annexRoot = {}
  for dest in pairs(annexArrival) do annexRoot[sets.find(dest)] = true end

  -- 3. Doors: every outdoor warp into a non-outdoor map.
  local doors, doorsByRoot, arrivalOf = {}, {}, {}
  for _, id in ipairs(mapIds) do
    if outdoor[id] then
      for index, w in ipairs(warpsOf(id)) do
        local dest = w.destMap
        local destDef = dest and maps[dest]
        if destDef and not outdoor[dest] and w.destWarp ~= BACKUP and (destDef.warps or {})[w.destWarp] then
          local root = sets.find(dest)
          local did = doorId(id, index)
          if annexRoot[root] then
            special.doorsIntoAnnex[#special.doorsIntoAnnex + 1] = did
          end
          doors[did] = { id = did, map = id, warp = index, x = w.x, y = w.y, root = root,
            inside = {}, arrival = { map = dest, warp = w.destWarp } }
          arrivalOf[did] = { map = dest, warp = w.destWarp }
          doorsByRoot[root] = doorsByRoot[root] or {}
          doorsByRoot[root][#doorsByRoot[root] + 1] = did
        end
      end
    end
  end

  -- inside: the complex's warps that lead back to the door, and the arrival
  -- warp itself when it is a self-named $ff warp (it returns through the backup).
  for root, list in pairs(members) do
    for _, id in ipairs(list) do
      for index, w in ipairs(warpsOf(id)) do
        if w.destMap and outdoor[w.destMap] and w.destWarp ~= BACKUP then
          local did = doorId(w.destMap, w.destWarp)
          local door = doors[did]
          if door and door.root == root then
            door.inside[#door.inside + 1] = { map = id, warp = index }
          else
            special.unpairedExits[#special.unpairedExits + 1] = { map = id, warp = index,
              destMap = w.destMap, destWarp = w.destWarp,
              why = door and ("that outdoor warp leads into " .. door.root) or "that outdoor warp is not a door" }
          end
        end
      end
    end
  end
  for _, did in ipairs(sortedKeys(doors, doorLess)) do
    local door = doors[did]
    local arrival = door.arrival
    if selfBackup(arrival.map, arrival.warp) then
      door.inside[#door.inside + 1] = { map = arrival.map, warp = arrival.warp, backup = true }
      door.backup = true
      special.backupDoors[#special.backupDoors + 1] = did
    end
    table.sort(door.inside, warpLess)
  end

  -- 4. Complex ids: the alphabetically first map a door enters, so the id
  -- names the front door's map rather than an arbitrary back room.
  local complexIdOf = {}
  for _, root in ipairs(sortedKeys(members)) do
    local best
    for _, did in ipairs(doorsByRoot[root] or {}) do
      local entered = doors[did].arrival.map
      if not best or entered < best then best = entered end
    end
    complexIdOf[root] = best or members[root][1]
  end

  -- 5. Entrances: adjacent door tiles on one map into one complex.
  local entranceSets = newSets()
  local byMapRoot = {}
  for _, did in ipairs(sortedKeys(doors, doorLess)) do
    local door = doors[did]
    entranceSets.add(did)
    local key = door.map .. "|" .. door.root
    byMapRoot[key] = byMapRoot[key] or {}
    local group = byMapRoot[key]
    for _, other in ipairs(group) do
      local o = doors[other]
      if door.x and o.x and math.abs(door.x - o.x) + math.abs(door.y - o.y) == 1 then
        entranceSets.union(other, did)
      end
    end
    group[#group + 1] = did
  end

  local graph = {
    doors = {}, complexes = {}, outdoor = outdoor, annexes = {}, entrances = {}, isolated = {},
    special = special,
  }
  graph.outdoorOrder = sortedKeys(outdoor)

  for _, did in ipairs(sortedKeys(doors, doorLess)) do
    local door = doors[did]
    local cid = complexIdOf[door.root]
    -- entrance ids are the first door of the doorway (union roots are the
    -- smallest string; recompute with doorLess for a natural first).
    graph.doors[did] = { id = did, map = door.map, warp = door.warp, complex = cid,
      inside = door.inside, arrival = door.arrival, backup = door.backup or false,
      x = door.x, y = door.y }
  end
  local entranceMembers = {}
  for _, did in ipairs(sortedKeys(doors, doorLess)) do
    local root = entranceSets.find(did)
    entranceMembers[root] = entranceMembers[root] or {}
    local list = entranceMembers[root]
    list[#list + 1] = did
  end
  for _, root in ipairs(sortedKeys(entranceMembers)) do
    local list = entranceMembers[root]
    table.sort(list, doorLess)
    local eid = list[1]
    local first = graph.doors[eid]
    -- inside: every complex warp leading back to any tile of the doorway.
    -- Usually both inside tiles lead to ONE outdoor tile (CELADON_CITY:3),
    -- leaving its neighbour (CELADON_CITY:4) enter-only.
    local inside = {}
    for _, did in ipairs(list) do
      graph.doors[did].entrance = eid
      for _, w in ipairs(graph.doors[did].inside) do inside[#inside + 1] = w end
    end
    table.sort(inside, warpLess)
    graph.entrances[eid] = { id = eid, map = first.map, complex = first.complex, doors = list,
      inside = inside }
    for _, did in ipairs(list) do
      if #graph.doors[did].inside == 0 then
        local key = #inside == 0 and "oneWayDoors" or "enterOnlyTiles"
        special[key][#special[key] + 1] = did
      end
    end
  end

  -- 6. Complexes, annexes and door-less components.
  local annexOfRoot = {}
  for _, root in ipairs(sortedKeys(members)) do
    if annexRoot[root] then
      local landing
      for dest in pairs(annexArrival) do
        if sets.find(dest) == root and (not landing or dest < landing) then landing = dest end
      end
      annexOfRoot[root] = landing
      graph.annexes[landing] = { id = landing, maps = members[root], entries = {}, complexes = {} }
    end
  end
  for _, dest in ipairs(sortedKeys(annexArrival)) do
    local annex = graph.annexes[annexOfRoot[sets.find(dest)]]
    local seen = {}
    for _, c in ipairs(annex.complexes) do seen[c] = true end
    for _, source in ipairs(sortedKeys(deferred[dest])) do
      local sourceRoot = sets.find(source)
      if sourceRoot ~= sets.find(dest) then
        for index, w in ipairs(warpsOf(source)) do
          if w.destMap == dest and w.destWarp ~= BACKUP and selfBackup(dest, w.destWarp) then
            annex.entries[#annex.entries + 1] = { map = source, warp = index,
              complex = complexIdOf[sourceRoot], arrival = { map = dest, warp = w.destWarp } }
          end
        end
        local cid = complexIdOf[sourceRoot]
        if not seen[cid] then seen[cid] = true; annex.complexes[#annex.complexes + 1] = cid end
      end
    end
  end
  for _, annex in pairs(graph.annexes) do
    table.sort(annex.entries, warpLess)
    table.sort(annex.complexes)
  end

  for _, root in ipairs(sortedKeys(members)) do
    local cid = complexIdOf[root]
    local doorList = doorsByRoot[root]
    if annexRoot[root] then
      -- listed in graph.annexes
    elseif not doorList then
      graph.isolated[cid] = { id = cid, maps = members[root] }
    else
      table.sort(doorList, doorLess)
      -- environment: the one most of the complex's maps have; a tie goes to
      -- the more place-like (ENV_TIE_ORDER), so VICTORY_ROAD (one cave map,
      -- one gate map) is CAVE.
      local envCount, envList, entrySeen = {}, {}, {}
      for _, id in ipairs(members[root]) do
        local env = maps[id].environment or "?"
        if not envCount[env] then envList[#envList + 1] = env end
        envCount[env] = (envCount[env] or 0) + 1
      end
      for _, did in ipairs(doorList) do entrySeen[doors[did].arrival.map] = true end
      table.sort(envList)
      local env = envList[1]
      for _, e in ipairs(envList) do
        if envCount[e] > envCount[env]
            or (envCount[e] == envCount[env] and (ENV_TIE_ORDER[e] or 99) < (ENV_TIE_ORDER[env] or 99)) then
          env = e
        end
      end
      local entranceList, entranceSeen, outdoorSeen = {}, {}, {}
      for _, did in ipairs(doorList) do
        local eid = graph.doors[did].entrance
        if not entranceSeen[eid] then entranceSeen[eid] = true; entranceList[#entranceList + 1] = eid end
        outdoorSeen[graph.doors[did].map] = true
      end
      table.sort(entranceList, doorLess)
      local complex = { id = cid, maps = members[root], environment = env, environments = envList,
        doors = doorList, entrances = entranceList, deadEnd = #entranceList == 1, story = false,
        outdoorMaps = sortedKeys(outdoorSeen), entryMaps = sortedKeys(entrySeen), annexes = {} }
      complex.kind = complexKind(complex)
      graph.complexes[cid] = complex
      if #envList > 1 then special.mixedEnvironment[#special.mixedEnvironment + 1] = cid end
      if #complex.outdoorMaps > 1 then special.multiOutdoor[#special.multiOutdoor + 1] = cid end
    end
  end
  for _, aid in ipairs(sortedKeys(graph.annexes)) do
    for _, cid in ipairs(graph.annexes[aid].complexes) do
      local complex = graph.complexes[cid]
      if complex then complex.annexes[#complex.annexes + 1] = aid end
    end
  end

  graph.doorOrder = sortedKeys(graph.doors, doorLess)
  graph.complexOrder = sortedKeys(graph.complexes)
  graph.entranceOrder = sortedKeys(graph.entrances, doorLess)
  graph.annexOrder = sortedKeys(graph.annexes)
  graph.isolatedOrder = sortedKeys(graph.isolated)
  -- complexOf: every non-outdoor map's complex (or annex / isolated id).
  graph.complexOf = {}
  for root, list in pairs(members) do
    local cid = annexOfRoot[root] or complexIdOf[root]
    for _, id in ipairs(list) do graph.complexOf[id] = cid end
  end

  for _, key in ipairs({ "backupDoors", "oneWayDoors", "enterOnlyTiles", "doorsIntoAnnex" }) do
    table.sort(special[key], doorLess)
  end
  table.sort(special.multiOutdoor)
  table.sort(special.mixedEnvironment)
  table.sort(special.unknownEnvironment)
  for _, key in ipairs({ "badWarps", "outdoorToOutdoor", "outdoorBackupWarps", "unpairedExits" }) do
    table.sort(special[key], warpLess)
  end

  -- Counts, for reports and tests.
  local counts = { kinds = {}, deadEnds = 0, complexes = 0, doors = #graph.doorOrder,
    entrances = #graph.entranceOrder, annexes = #graph.annexOrder, isolated = #graph.isolatedOrder,
    outdoor = #graph.outdoorOrder }
  for _, cid in ipairs(graph.complexOrder) do
    local c = graph.complexes[cid]
    counts.complexes = counts.complexes + 1
    counts.kinds[c.kind] = (counts.kinds[c.kind] or 0) + 1
    if c.deadEnd then counts.deadEnds = counts.deadEnds + 1 end
  end
  graph.counts = counts
  return graph
end

return {
  id = "mapgraph",
  questions = {},
  install = function(mod, ctx)
    ctx.lib.mapGraph = { build = M.build, doorLess = M.doorLess, doorId = M.doorId }
  end,
  -- for tests (luajit): the same functions without a ctx
  _M = M,
}
