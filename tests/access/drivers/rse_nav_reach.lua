-- Ruby, Sapphire and Emerald reachability over the whole cartridge, by the planner's
-- own movement graph (gen3_reach_sweep.lua on FireRed): what the object list offers
-- against what any route could ever reach.
--
-- One flood over the cells of every map at route policy 3 (every field move, the bikes
-- named), warps, connections, elevators, Dive and cracked floors as edges.  People do not
-- block (they move, and story flags remove them): only terrain and field obstacles do.
--   MAPS      maps the flood from Littleroot Town never enters
--   TARGETS   per map, labels with no goal cell any flood entered
--   BOULDER   floors with boulders: boulders, switches, holes
-- Every map the first flood missed starts a further flood from its first warp (ferries and
-- other scripted rides leave no walking edge).  Silent; RESULT lines.
return function(game)
  local L = dofile("tests/access/drivers/rse_nav_lib.lua").new(game)
  local U = L.U
  if not L.boot() then return end
  L.giveParty()
  local nav = L.nav()
  local maps = game.data.maps
  local Snapshot = require("src.access.nav.gen3.WorldSnapshot")
  local Puzzle = require("src.access.nav.gen3.PuzzleAssistance")
  local Terrain = require("src.access.nav.gen3.TerrainSemantics")

  local ids = L.mapIds()
  local entries = {}
  local function entryOf(mapId)
    if entries[mapId] ~= nil then return entries[mapId] or nil end
    local world = nav:regionalStaticWorld(mapId, { x = 0, y = 0 })
    if not world then entries[mapId] = false return nil end
    -- people do not count; boulders, trees and rocks do, and balls can be picked up
    local kept = {}
    for _, actor in ipairs(world.npcs) do
      local gfx = tonumber(actor.graphicsId)
      if gfx == Terrain.GFX.CUT_TREE or gfx == Terrain.GFX.ROCK or gfx == Terrain.GFX.BOULDER
         or gfx == Terrain.GFX.ITEM_BALL then
        kept[#kept + 1] = actor
      end
    end
    world.npcs = kept
    -- the floor as drawn: a new game's load scripts also put up what the story clears
    -- (the Wailmer between Lilycove and Route 124), and no walk from here runs that story
    world.map = require("src.access.nav.gen3.World").plannedView(game, maps[mapId])
    local byCell, goals = {}, {}
    local function add(t)
      local key = t.x .. "," .. t.y
      if not byCell[key] then byCell[key] = {} goals[#goals + 1] = { x = t.x, y = t.y } end
      table.insert(byCell[key], t)
    end
    for _, t in ipairs(nav:regionalTransitions(mapId)) do add(t) end
    for _, t in ipairs(nav:elevatorTransitions(world, 3)) do add(t) end
    for _, t in ipairs(nav:fallTransitions(world)) do add(t) end
    for _, t in ipairs(nav:diveTransitions(world, 3)) do add(t) end
    if #goals == 0 then goals[1] = { x = 0, y = 0 } end
    local options = nav:routeOptionsFor(world, goals, 3)
    if not options then entries[mapId] = false return nil end
    local entry = { world = world, map = world.map, neighbors = options.neighbors, byCell = byCell, seen = {} }
    entries[mapId] = entry
    return entry
  end

  local function flood(startMap, startX, startY)
    local queue, head = { { startMap, startX, startY, true } }, 1
    while queue[head] do
      local node = queue[head]
      head = head + 1
      local entry = entryOf(node[1])
      if entry then
        local key = node[2] .. "," .. node[3]
        local stateKey = key .. (node[4] and "a" or "w")
        if not entry.seen[stateKey] then
          entry.seen[stateKey] = true
          entry.seen[key] = true
          local map = entry.map
          local fires = not node[4] and map:warpAt(node[2], node[3]) ~= nil and not map:standingWarp(node[2], node[3])
          for _, t in ipairs(entry.byCell[key] or {}) do
            if t.kind ~= "warp" or fires or map:standingWarp(node[2], node[3]) ~= nil then
              queue[#queue + 1] = { t.destMap, t.destX, t.destY, true }
            end
          end
          if not fires then
            for _, edge in ipairs(entry.neighbors(node[2], node[3])) do
              queue[#queue + 1] = { node[1], edge.x, edge.y, false }
            end
          end
        end
      end
      if head % 4096 == 0 then U.wait(1) end
    end
  end

  flood(L.id("LITTLEROOT_TOWN"), 10, 10)
  local missed = {}
  for _, id in ipairs(ids) do
    local entry = entryOf(id)
    if not (entry and next(entry.seen)) then missed[#missed + 1] = id end
  end
  U.log("RESULT", "MAPS not entered from Littleroot Town", #missed, table.concat(missed, " "))
  for _, id in ipairs(missed) do
    local entry = entryOf(id)
    local warp = maps[id].warps and maps[id].warps[1]
    if entry and warp and not next(entry.seen) then flood(id, warp.x, warp.y) end
    if entry and not warp and not next(entry.seen) then U.log("RESULT", "no warps", id) end
  end

  -- RSE_REACH_SHOW=MAP,MAP: those maps as rows of cells: # wall, . land, ~ water, o reached land, w reached water
  for name in tostring(os.getenv("RSE_REACH_SHOW") or ""):gmatch("[^,]+") do
    local entry = entryOf(L.prefix .. name)
    if entry then
      local map = entry.map
      for y = 0, map.heightCells - 1 do
        local row = {}
        for x = 0, map.widthCells - 1 do
          local seen = entry.seen[x .. "," .. y]
          local water = map:isWater(x, y)
          local land = map:walkableColl(x, y)
          row[#row + 1] = seen and (water and "w" or "o") or (water and "~") or (land and ".") or "#"
        end
        U.log("SHOW", name, string.format("%3d", y), table.concat(row))
      end
    end
  end

  local totals = { listed = 0, unreached = 0 }
  for index, id in ipairs(ids) do
    local entry = entryOf(id)
    if entry then
      local world = entry.world
      local warp = maps[id].warps and maps[id].warps[1]
      world.player.cellX, world.player.cellY = warp and warp.x or 0, warp and warp.y or 0
      local ok, snapshot = pcall(Snapshot.capture, world, { filter = "all", customNames = {}, playerName = "RED",
        rivalName = "MAY", interactiveObjects = nav:interactiveBrowseObjects(world, { objects = {} }),
        maps = maps })
      if ok and snapshot then nav:dropUnservable(world, snapshot) end
      for _, item in ipairs(ok and snapshot and snapshot.browse or {}) do
        totals.listed = totals.listed + 1
        local okGoals, goals = pcall(nav.interactionGoals, nav, world, item)
        if item.type == "warp" and type(item.navigationCells) == "table" then goals = item.navigationCells end
        if item.type == "connection" then goals = nav:connectionGoals(world, item) end
        local reached = false
        for _, goal in ipairs(okGoals and type(goals) == "table" and goals or {}) do
          if entry.seen[goal.x .. "," .. goal.y] then reached = true break end
        end
        if not reached then
          totals.unreached = totals.unreached + 1
          U.log("TARGET", id, item.type, tostring(item.label), tostring(item.x) .. "," .. tostring(item.y))
        end
      end
      local okT, targets, boulders = pcall(Puzzle.targetsFor, world)
      local count = 0
      for _, actor in ipairs(world.npcs) do if Terrain.isBoulder(actor) then count = count + 1 end end
      if count > 0 then
        local switches, holes = 0, 0
        for _, t in ipairs(okT and targets or {}) do
          if t.kind == "switch" then switches = switches + 1 else holes = holes + 1 end
        end
        U.log("BOULDER", id, "boulders", count, "switches", switches, "holes", holes)
      end
    end
    if index % 40 == 0 then U.wait(1) end
  end
  U.log("RESULT", "listed", totals.listed, "with no goal cell any flood entered", totals.unreached)
  U.log("DONE")
end
