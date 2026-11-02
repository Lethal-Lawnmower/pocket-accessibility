-- FireRed navigation against the whole cartridge (decision 29): the label
-- sweep and puzzle check the Gen 2 audit did with gen2_nav_cart_test.lua,
-- run inside the game because Gen 3 map data is only readable through the
-- game's own loader (Dataset, LayoutNative, the script bundle).
--
-- For every FR_ map, from a new game's flags: the object list a player
-- standing on the map's first warp would get (planned view, the objects
-- the game would show), checked for empty, nil, raw-id, ROM-address and
-- placeholder labels; every active warp and connection must resolve.
-- Every floor with Strength boulders and a switch or hole is solved by
-- following only the puzzle help's next push under the game's push rule
-- (the plan's own model, applied to a copy of the floor).
--
-- Silent and isolated; needs the imported FireRed identity (no ROM data is
-- read from or written to the repository).  Prints NO CHECKS if FireRed
-- data is missing.
return function(game)
  local L = dofile("tests/access/drivers/gen3_nav_lib.lua").new(game)
  local U = L.U
  if not L.boot() then
    U.log("RESULT", "gen3_nav_sweep", "NO CHECKS -- no FireRed game")
    return
  end
  local maps = game.data and game.data.maps
  if type(maps) ~= "table" or not maps.FR_PALLET_TOWN then
    U.log("RESULT", "gen3_nav_sweep", "NO CHECKS -- no FireRed map data")
    return
  end
  local nav = L.nav()
  local Snapshot = require("src.access.nav.gen3.WorldSnapshot")
  local Puzzle = require("src.access.nav.gen3.PuzzleAssistance")
  local World = require("src.access.nav.gen3.World")

  local ids = {}
  for id in pairs(maps) do if id:match("^FR_") then ids[#ids + 1] = id end end
  table.sort(ids)
  local stats = { maps = 0, labels = 0, signposts = 0, bad = 0, warps = 0, unresolved = 0,
    connections = 0, roles = {}, objects = {} }
  local function bad(label)
    if type(label) ~= "string" or label == "" then return true end
    return label:find("g3:", 1, true) or label:find("nil", 1, true)
      or label:find("Unknown", 1, true) or label:find("FR_", 1, true)
      or label:match("^Warp %d") or label:match("^Object %d") or label:find("Interactive object", 1, true)
      or label:find("_", 1, true) or label:match("%x%x%x%x%x%x") ~= nil
  end
  local puzzleFloors = {}
  for _, mapId in ipairs(ids) do
    local def = maps[mapId]
    local view = World.plannedView(game, def)
    if view then
      stats.maps = stats.maps + 1
      local start = { x = 0, y = 0 }
      local firstWarp = def.warps and def.warps[1]
      if firstWarp then start = { x = firstWarp.x, y = firstWarp.y } end
      local world = nav:regionalStaticWorld(mapId, start)
      local okCapture, snapshot = pcall(Snapshot.capture, world, {
        filter = "all", customNames = {}, playerName = "RED", rivalName = "BLUE",
        interactiveObjects = nav:interactiveBrowseObjects(world, { objects = {} }),
      })
      if not okCapture or not snapshot then
        stats.bad = stats.bad + 1
        U.log("BAD", mapId, "capture failed", tostring(snapshot))
      else
        for _, item in ipairs(snapshot.browse or {}) do
          stats.labels = stats.labels + 1
          if bad(item.label) then
            stats.bad = stats.bad + 1
            U.log("BAD", mapId, item.type, tostring(item.label))
          end
          if tostring(item.label):match("^Signpost %d") then stats.signposts = stats.signposts + 1 end
          if item.type == "signpost" and not tostring(item.label):match("^Signpost") then
            stats.roles[item.label] = (stats.roles[item.label] or 0) + 1
          end
          if item.type == "object" then
            stats.objects[item.label] = (stats.objects[item.label] or 0) + 1
          end
          if item.type == "connection" then stats.connections = stats.connections + 1 end
        end
      end
      for index, warp in ipairs(def.warps or {}) do
        local active, activeIndex = view:warpAt(warp.x, warp.y)
        if active and activeIndex == index then
          stats.warps = stats.warps + 1
          local dest = view:warpDestination(warp)
          if not dest then
            stats.unresolved = stats.unresolved + 1
            U.log("UNRESOLVED", mapId, index, tostring(warp.destMap), "mapNum", tostring(warp.mapNum))
          end
        end
      end
      local okTargets, targets, boulders = pcall(Puzzle.targetsFor, world)
      if okTargets and targets then puzzleFloors[#puzzleFloors + 1] = { id = mapId, world = world } end
    end
  end
  U.log("SWEEP", "maps", stats.maps, "labels", stats.labels, "bad", stats.bad,
    "signposts", stats.signposts, "active warps", stats.warps, "unresolved", stats.unresolved,
    "connections", stats.connections)
  local roleList = {}
  for label, n in pairs(stats.roles) do roleList[#roleList + 1] = label .. "=" .. n end
  table.sort(roleList)
  U.log("ROLES", table.concat(roleList, ", "))
  local objectList = {}
  for label, n in pairs(stats.objects) do objectList[#objectList + 1] = label .. "=" .. n end
  table.sort(objectList)
  U.log("OBJECTS", table.concat(objectList, ", "))
  L.check(stats.maps >= 400, "every FireRed map has a view (" .. stats.maps .. ")")
  L.check(stats.bad == 0, "no bad labels (" .. stats.bad .. ")")

  -- Strength floors: follow only the next push, on a copy of the floor.
  -- The plan is searched as the game does it (a task run in slices until
  -- it is found, then kept and followed push by push).
  local kept
  local function nextPush(world, targets, boulders)
    local push = kept and Puzzle.followPlan(kept, world, boulders)
    if push then return push end
    local task = Puzzle.newPlanTask(world, targets, boulders)
    local plan, why
    for _ = 1, 200 do
      plan, why = task.run(0.1)
      if why ~= "budget" then break end
    end
    kept = plan
    return plan, why
  end
  for _, floor in ipairs(puzzleFloors) do
    kept = nil
    local world = floor.world
    local targets, boulders = Puzzle.targetsFor(world)
    local holes, switches, total = 0, 0, #boulders
    for _, t in ipairs(targets) do if t.kind == "hole" then holes = holes + 1 else switches = switches + 1 end end
    U.log("PUZZLE", floor.id, "boulders", #boulders, "switches", switches, "holes", holes)
    -- the player starts on each walkable cell next to a boulder in turn
    -- until a plan exists (the floor's entrance may be far from them)
    local pushes, done = 0, false
    local startCells = {}
    for _, b in ipairs(boulders) do
      for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
        local x, y = b.cellX + d[1], b.cellY + d[2]
        if world.map:isWalkableCell(x, y) then startCells[#startCells + 1] = { x, y } end
      end
    end
    local placed = false
    for _, cell in ipairs(startCells) do
      world.player.cellX, world.player.cellY = cell[1], cell[2]
      kept = nil
      local plan = nextPush(world, targets, boulders)
      if plan then placed = true break end
    end
    local dropped = 0
    if not placed then
      U.log("PUZZLE", floor.id, "no plan from any cell beside a boulder")
    else
      for round = 1, 200 do
        targets, boulders = Puzzle.targetsFor(world)
        local openSwitches = 0
        for _, t in ipairs(targets or {}) do
          if t.kind == "switch" and not t.solved then openSwitches = openSwitches + 1 end
        end
        if switches > 0 and openSwitches == 0 then done = true break end
        if not targets then done = switches == 0 and dropped > 0 break end
        local plan = nextPush(world, targets, boulders)
        if not plan then
          done = switches == 0 and dropped > 0
          U.log("PUZZLE", floor.id, "round", round, "no further push; open switches", openSwitches,
            "dropped", dropped)
          break
        end
        -- apply the push: the player stands where told, the boulder moves
        local b = plan.boulder.entity
        local d = World.DELTA[plan.direction]
        world.player.cellX, world.player.cellY = plan.standX, plan.standY
        b.cellX, b.cellY = b.cellX + d[1], b.cellY + d[2]
        pushes = pushes + 1
        if world.map:behavior(b.cellX, b.cellY) == 0x66 then
          b.invisible = true -- fell through: gone from the floor
          b.passable = true
          dropped = dropped + 1
        end
      end
    end
    U.log("PUZZLE", floor.id, "pushes", pushes, "dropped", dropped, done and "solved" or "unsolved")
    if floor.id:match("VICTORY_ROAD") then
      L.check(done, floor.id .. " switches all pressed by following the hints (" .. pushes .. " pushes)")
    elseif floor.id:match("TANOBY_KEY") then
      -- the seven-switch plan takes about a second: searched in slices,
      -- kept, and followed to the end
      L.check(done, floor.id .. " switches all pressed by following the hints (" .. pushes .. " pushes)")
    elseif floor.id == "FR_SEAFOAM_ISLANDS_1F" then
      L.check(dropped == total, floor.id .. " every boulder dropped by following the hints ("
        .. pushes .. " pushes)")
    end
  end
  L.finish("gen3_nav_sweep")
end
