-- FireRed reachability over the whole cartridge, by the planner's own movement graph:
-- what the object list offers against what any route could ever reach.
--
-- One flood over cells of every FR_ map at route policy 3 (every field move, every
-- door), warps, connections, elevators and thin ice as edges.  People do not block
-- (they move, and story flags remove them): only terrain and field obstacles do.
--   MAPS      maps the flood from Pallet Town never enters
--   TARGETS   per map, labels with no goal cell any flood entered
--   BOULDER   floors with boulders: boulders, switches, holes
-- Each island group has no walking way from Kanto (the ferry is a cutscene), so every
-- map the first flood missed starts a further flood from its first warp.
-- Harness setup only; no game state changes beyond a new game.  Silent; RESULT lines.
return function(game)
  local L = dofile("tests/access/drivers/gen3_nav_lib.lua").new(game)
  local U = L.U
  if not L.boot() then return end
  L.giveParty(9, 90, { "SURF", "STRENGTH", "CUT" }, { "SURF", "STRENGTH", "CUT", "WATERFALL", "ROCK_SMASH", "FLASH" })
  local nav = L.nav()
  local maps = game.data.maps
  local World = require("src.access.nav.gen3.World")
  local Snapshot = require("src.access.nav.gen3.WorldSnapshot")
  local Puzzle = require("src.access.nav.gen3.PuzzleAssistance")
  local Terrain = require("src.access.nav.gen3.TerrainSemantics")

  local ids = {}
  for id in pairs(maps) do if id:match("^FR_") then ids[#ids + 1] = id end end
  table.sort(ids)

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
    local byCell, goals = {}, {}
    local function add(t)
      local key = t.x .. "," .. t.y
      if not byCell[key] then byCell[key] = {} goals[#goals + 1] = { x = t.x, y = t.y } end
      table.insert(byCell[key], t)
    end
    for _, t in ipairs(nav:regionalTransitions(mapId)) do add(t) end
    for _, t in ipairs(nav:elevatorTransitions(world, 3)) do add(t) end
    for _, t in ipairs(nav:fallTransitions(world)) do add(t) end
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
            -- neighbors() starts from any cell, so the player's position does not matter here
            for _, edge in ipairs(entry.neighbors(node[2], node[3])) do
              queue[#queue + 1] = { node[1], edge.x, edge.y, false }
            end
          end
        end
      end
      if head % 4096 == 0 then U.wait(1) end
    end
  end

  flood("FR_PALLET_TOWN", 5, 8)
  local missed = {}
  for _, id in ipairs(ids) do
    local entry = entryOf(id)
    if not (entry and next(entry.seen)) then missed[#missed + 1] = id end
  end
  U.log("RESULT", "MAPS not entered from Pallet Town", #missed, table.concat(missed, " "))
  for _, id in ipairs(missed) do
    local entry = entryOf(id)
    local warp = maps[id].warps and maps[id].warps[1]
    if entry and warp and not next(entry.seen) then flood(id, warp.x, warp.y) end
    if entry and not warp and not next(entry.seen) then U.log("RESULT", "no warps", id) end
  end

  local totals = { listed = 0, unreached = 0 }
  for _, id in ipairs(ids) do
    local entry = entryOf(id)
    if entry then
      local world = entry.world
      local warp = maps[id].warps and maps[id].warps[1]
      world.player.cellX, world.player.cellY = warp and warp.x or 0, warp and warp.y or 0
      local ok, snapshot = pcall(Snapshot.capture, world, { filter = "all", customNames = {}, playerName = "RED",
        rivalName = "BLUE", interactiveObjects = nav:interactiveBrowseObjects(world, { objects = {} }),
        maps = maps })
      if ok and snapshot then nav:dropUnservable(world, snapshot) end
      for _, item in ipairs(ok and snapshot and snapshot.browse or {}) do
        totals.listed = totals.listed + 1
        if tostring(item.label):match("^Signpost %d") then
          local event = maps[id].bgEvents and maps[id].bgEvents[tonumber(tostring(item.label):match("%d+"))]
          local reach = event and require("src.access.nav.gen3.Scripts").reach(event.scriptKey, 8)
          local ops, specials = {}, {}
          for op in pairs(reach and reach.ops or {}) do ops[#ops + 1] = op end
          for name in pairs(reach and reach.specials or {}) do specials[#specials + 1] = name end
          table.sort(ops)
          U.log("SIGNPOST", id, tostring(item.label), tostring(item.x) .. "," .. tostring(item.y),
            table.concat(specials, " "), "|", table.concat(ops, " "))
        end
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
    if _ % 40 == 0 then U.wait(1) end
  end
  U.log("RESULT", "listed", totals.listed, "with no goal cell any flood entered", totals.unreached)
  U.log("DONE")
end
