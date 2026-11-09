-- End-to-end game run for the map (door) randomizer (MAPS.md), in a real
-- Crystal run with the whole mod installed in a disposable profile's mods
-- folder.  One run is one seed at one level:
--   1. a copy of the boot save gets modData.crystal_randomizer with the seed and
--      `maps` at that level, and is loaded with Continue;
--   2. every outdoor door on New Bark Town, Cherrygrove, Violet and Goldenrod is
--      listed with where the placement says it leads, where the warp data now
--      leads, and what the navigation's object list names it;
--   3. a sample of those doors is walked into from a neighbouring cell: the
--      arrival must be the destination the placement says, and walking straight
--      back out must return to the same door;
--   4. at `caves` and `full`, an Escape Rope is used inside a shuffled cave and
--      the landing is reported against the door used to enter;
--   5. the placement's own canWin result is reported.
-- While a piece is not installed, the run says which one (MISSING lines) and
-- checks what it still can.  Silent; read the PASS, FAIL, MISSING, SKIP,
-- RESULT and SUMMARY lines.  Normally run by tests/maps_e2e.py, which sets:
--   POKEPORT_IDENTITY=pocket-access-maps-e2e POKEPORT_ACCESS_SILENT=1
--   POKEPORT_BACKGROUND=1 POKEPORT_VERSION=crystal POKEPORT_GAME=crystal
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=launcher/mods/crystal_randomizer/tests/maps_e2e_driver.lua
--   MAPS_E2E_LEVEL=houses|caves|full  MAPS_E2E_SEED=<seed>
--   MAPS_E2E_SAMPLE=<doors walked per map, default 3>
--   MAPS_E2E_FRAMES=<frame budget for the whole run, default 60000>
--   "C:\Program Files\LOVE\lovec.exe" .

local TOWNS = { "NEW_BARK_TOWN", "CHERRYGROVE_CITY", "VIOLET_CITY", "GOLDENROD_CITY" }
local PIECES = { "mapgraph", "maprules", "mapplacer", "maps", "mapmoves" }
local MOD_ID = "crystal_randomizer"

return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local Runtime = require("src.mods.Runtime")
  local Permissions = require("src.world.gen2.Permissions")

  local level = os.getenv("MAPS_E2E_LEVEL") or "houses"
  local seed = os.getenv("MAPS_E2E_SEED") or "424242"
  local sample = tonumber(os.getenv("MAPS_E2E_SAMPLE") or "3") or 3
  local budget = tonumber(os.getenv("MAPS_E2E_FRAMES") or "60000") or 60000

  local counts = { PASS = 0, FAIL = 0, MISSING = 0, SKIP = 0 }
  local function log(kind, ...)
    if counts[kind] then counts[kind] = counts[kind] + 1 end
    U.log(kind, ...)
  end
  local function summary()
    U.log("SUMMARY", "level=" .. level, "seed=" .. seed, "pass=" .. counts.PASS, "fail=" .. counts.FAIL,
      "missing=" .. counts.MISSING, "skip=" .. counts.SKIP, "frames=" .. U.frame())
    U.log("DONE")
  end
  -- The whole run stops cleanly once the frame budget is spent; the runner's
  -- own timeout is the second bound.
  local function overBudget() return U.frame() > budget end

  if not L.settle(3000, true) then log("FAIL", "never reached the free world") summary() return end
  local data = game.data
  local world = function() return game.world end

  ------------------------------------------------------------------------------
  -- The mod's ctx.  The core keeps it local; the only way in from a driver is
  -- through the closures it registered (save.loading -> setState -> ctx).  This
  -- is test-only introspection and reads nothing but what MAPS.md publishes
  -- (ctx.lib and ctx.shared).
  ------------------------------------------------------------------------------
  local function findCtx()
    local listeners = Runtime.events and Runtime.events.listeners
    if type(listeners) ~= "table" then return nil, "no mod events are registered (mods not loaded?)" end
    local seen = {}
    local function isCtx(t)
      return type(t) == "table" and type(t.shared) == "table" and type(t.lib) == "table"
        and type(t.onSave) == "function" and type(t.active) == "function"
    end
    local function search(fn, depth)
      if depth > 4 or seen[fn] then return nil end
      seen[fn] = true
      for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if isCtx(value) then return value end
        if type(value) == "function" then
          local found = search(value, depth + 1)
          if found then return found end
        end
      end
      return nil
    end
    for _, event in ipairs({ "save.loading", "save.created" }) do
      for _, entry in ipairs(listeners[event] or {}) do
        if entry.owner == MOD_ID then
          local found = search(entry.callback, 0)
          if found then return found end
        end
      end
    end
    return nil, "the crystal_randomizer mod is not loaded (no save.loading listener of its own)"
  end

  local ctx, ctxWhy = findCtx()
  if not ctx then
    log("FAIL", "randomizer core not found:", ctxWhy)
    summary()
    return
  end
  log("PASS", "randomizer core found")
  if ctx.active() then log("FAIL", "the boot save is already randomized; the vanilla snapshot is not vanilla") end

  -- Which pieces are installed: the module file in the profile's mods folder,
  -- and the interface MAPS.md says it offers.
  local saveDir = love.filesystem.getSaveDirectory()
  local function installed(name)
    local f = io.open(saveDir .. "/mods/" .. MOD_ID .. "/modules/" .. name .. ".lua", "rb")
    if f then f:close() return true end
    return false
  end
  local libOf = { mapgraph = "mapGraph", maprules = "mapRules", mapplacer = "mapPlacer" }
  local present = {}
  local states = {}
  for _, name in ipairs(PIECES) do
    local file = installed(name)
    local lib = libOf[name]
    local ok = file and (lib == nil or type(ctx.lib[lib]) == "table")
    present[name] = ok
    if not file then
      log("MISSING", name, "modules/" .. name .. ".lua is not installed")
    elseif lib and type(ctx.lib[lib]) ~= "table" then
      log("MISSING", name, "installed but ctx.lib." .. lib .. " is not set (did it fail to install? see the mod log)")
    end
    states[#states + 1] = name .. "=" .. (ok and "present" or "missing")
  end
  U.log("RESULT", "pieces", table.concat(states, " "))

  ------------------------------------------------------------------------------
  -- Vanilla, before the seeded save loads.
  ------------------------------------------------------------------------------
  local vanillaWarps = {}
  for mapId, def in pairs(data.gen2Maps or {}) do
    local rows = {}
    for i, w in ipairs(def.warps or {}) do
      rows[i] = { x = w.x, y = w.y, destMap = w.destMap, destWarp = w.destWarp }
    end
    vanillaWarps[mapId] = rows
  end
  for _, town in ipairs(TOWNS) do
    if not vanillaWarps[town] then log("FAIL", "map " .. town .. " is not in the imported data") end
  end

  local graph, rules
  if present.mapgraph then
    local ok, result = pcall(ctx.lib.mapGraph.build, data)
    if ok and type(result) == "table" and type(result.doors) == "table" then
      graph = result
      local n, c = 0, 0
      for _ in pairs(graph.doors) do n = n + 1 end
      for _ in pairs(graph.complexes or {}) do c = c + 1 end
      log("PASS", "mapgraph built", n .. " doors", c .. " complexes")
    else
      log("FAIL", "mapgraph build failed:", tostring(result))
    end
  end
  if graph and present.maprules then
    local ok, result = pcall(ctx.lib.mapRules.model, data, graph)
    if ok and type(result) == "table" and type(result.canWin) == "function" then
      rules = result
      log("PASS", "maprules modelled")
    else
      log("FAIL", "maprules model failed:", tostring(result))
    end
  end

  ------------------------------------------------------------------------------
  -- Load the seeded save.
  ------------------------------------------------------------------------------
  local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, v in pairs(value) do out[key] = copy(v) end
    return out
  end
  local save = copy(game.save)
  save.modData = save.modData or {}
  save.modData[MOD_ID] = { seed = seed, options = { maps = level, setup = "custom" }, version = 1 }
  local loadStarted = os.clock()
  game:continueGame(save)
  local loadSeconds = os.clock() - loadStarted
  L.settle(600, true)
  L.strongParty()
  U.log("RESULT", "load", ("Continue with the seeded save took %.3f s (the onSave switch, placer included)"):format(loadSeconds))
  log(ctx.active() and ctx.seed() == seed and "PASS" or "FAIL", "the seeded save is active", tostring(ctx.seed()))

  local published = ctx.shared.maps
  local placement, report
  -- A door with no entry in the placement keeps its own destination.
  local function targetOf(doorId)
    if not placement then return doorId end
    return placement[doorId] or doorId
  end
  -- A door is moved when its entrance now leads to another entrance.  The
  -- placer names every tile's target by that entrance's first tile, so the
  -- second tile of a wide doorway that stays points at the first one: not a move.
  local function entranceOf(doorId)
    local door = graph and graph.doors[doorId]
    return door and door.entrance or doorId
  end
  local function isMoved(doorId)
    if not placement then return false end
    local to = placement[doorId]
    if to == nil or to == doorId then return false end
    return entranceOf(to) ~= entranceOf(doorId)
  end
  if type(published) == "table" and type(published.placement) == "table" then
    placement, report = published.placement, published.report
    local moved, total = 0, 0
    for from in pairs(placement) do
      if from ~= "entrances" then
        total = total + 1
        if isMoved(from) then moved = moved + 1 end
      end
    end
    local movedE, totalE = 0, 0
    for from, to in pairs(type(placement.entrances) == "table" and placement.entrances or {}) do
      totalE = totalE + 1
      if from ~= to then movedE = movedE + 1 end
    end
    log((level == "off" or moved > 0) and "PASS" or "FAIL", "maps published a placement",
      moved .. " of " .. total .. " door tiles moved", movedE .. " of " .. totalE .. " entrances moved")
  elseif present.maps then
    local needs = {}
    for _, name in ipairs({ "mapgraph", "maprules", "mapplacer" }) do
      if not present[name] then needs[#needs + 1] = name end
    end
    if #needs > 0 then
      log("MISSING", "maps", "no placement published; it needs " .. table.concat(needs, ", ") .. ", not installed")
    else
      log("FAIL", "maps is installed but ctx.shared.maps.placement is not set after loading the seeded save"
        .. " (no placement passed canWin, or maps failed; see the mod log)")
    end
  else
    log("MISSING", "maps", "no placement published (ctx.shared.maps is nil)")
  end
  if type(report) == "table" then
    local parts = {}
    for key, value in pairs(report) do
      if type(value) ~= "table" and type(value) ~= "function" then parts[#parts + 1] = key .. "=" .. tostring(value) end
    end
    table.sort(parts)
    U.log("RESULT", "placement report", table.concat(parts, " "))
  end

  local function doorAt(mapId, warpIndex)
    if not graph then return nil end
    for id, door in pairs(graph.doors) do
      if door.map == mapId and door.warp == warpIndex then return id, door end
    end
    return nil
  end
  -- Where door `doorId` should lead now: where its target door led in vanilla.
  local function expectedDest(doorId)
    local target = graph and graph.doors[isMoved(doorId) and targetOf(doorId) or doorId]
    local row = target and vanillaWarps[target.map] and vanillaWarps[target.map][target.warp]
    if not row then return nil end
    return row.destMap, row.destWarp
  end
  local function complexOf(doorId)
    local door = graph and graph.doors[doorId]
    return door and graph.complexes and graph.complexes[door.complex]
  end

  ------------------------------------------------------------------------------
  -- Pools: a moved door only swaps with doors the level allows.
  ------------------------------------------------------------------------------
  if placement and graph then
    local function house(c)
      return c and c.deadEnd and c.environment == "INDOOR"
    end
    local function cave(c)
      return c and (c.environment == "CAVE" or c.environment == "DUNGEON")
    end
    local bad, checked = {}, 0
    for from, to in pairs(placement) do
      if from ~= "entrances" and isMoved(from) then
        checked = checked + 1
        local a, b = complexOf(from), complexOf(to)
        local ok
        if level == "houses" then ok = house(a) and house(b)
        elseif level == "caves" then ok = (house(a) and house(b)) or (cave(a) and cave(b))
        else ok = a ~= nil and b ~= nil end
        if ok and rules and rules.fixed and (rules.fixed[a.id] or rules.fixed[b.id]) then ok = false end
        if not ok then bad[#bad + 1] = tostring(from) .. "->" .. tostring(to) end
      end
    end
    log(#bad == 0 and "PASS" or "FAIL", "moved doors stay in the level's pools and off fixed complexes",
      checked .. " moved", #bad > 0 and ("bad: " .. table.concat(bad, " ", 1, math.min(#bad, 10))) or "")
  end

  ------------------------------------------------------------------------------
  -- Warps taken, from the engine's own event; the map and cell are the fallback.
  ------------------------------------------------------------------------------
  local warps = {}
  local unsubscribe
  if Runtime.events and Runtime.events.on then
    unsubscribe = Runtime.events:on("player.warped", function(ev)
      warps[#warps + 1] = { from = ev.fromMap, to = ev.toMap, toWarp = ev.toWarp, x = ev.x, y = ev.y }
    end, 0, "maps_e2e_driver")
  end

  local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

  -- Hold `dir` until a warp is taken, the map changes, or `frames` pass.
  local function holdUntilWarp(dir, frames)
    local before = #warps
    local startMap = world().map and world().map.id
    for _ = 1, frames do
      game.input.pressQueue[#game.input.pressQueue + 1] = dir
      game.input.state[dir] = true
      U.wait(1)
      if #warps > before or (world().map and world().map.id) ~= startMap then break end
    end
    game.input.state[dir] = false
    if #warps > before then return warps[#warps] end
    local id, x, y = L.pos()
    if id ~= startMap then
      -- no event: name the warp under (or next to) the player
      local map = world().map
      for dy = -1, 1 do
        for dx = -1, 1 do
          local entry = map and map.warpAt and map:warpAt(x + dx, y + dy)
          if entry then return { to = id, toWarp = world():warpIndexOf(entry.def), x = x, y = y, guessed = true } end
        end
      end
      return { to = id, x = x, y = y, guessed = true }
    end
    return nil
  end

  -- Hold `dir` until the player's cell changes (one step), or `frames` pass.
  local function stepOnce(dir, frames)
    local _, x0, y0 = L.pos()
    for _ = 1, frames do
      game.input.pressQueue[#game.input.pressQueue + 1] = dir
      game.input.state[dir] = true
      U.wait(1)
      local _, x, y = L.pos()
      if x ~= x0 or y ~= y0 then break end
    end
    game.input.state[dir] = false
    for _ = 1, 30 do
      local p = world().player
      if not (p and p.moving) then break end
      U.wait(1)
    end
    local _, x, y = L.pos()
    return x ~= x0 or y ~= y0
  end

  -- Stand beside the door's warp cell and walk onto it.  Returns the warp
  -- record, or nil and why.
  local function enterDoor(door)
    local row = vanillaWarps[door.map][door.warp]
    local tried = {}
    for _, dir in ipairs({ "up", "left", "right", "down" }) do
      local d = DELTA[dir]
      local sx, sy = row.x - d[1], row.y - d[2]
      L.teleport(door.map, sx, sy, dir)
      local map = world().map
      local id, x, y = L.pos()
      tried[#tried + 1] = dir .. "@" .. sx .. "," .. sy .. (id ~= door.map and (" on " .. id) or "")
        .. ((x ~= sx or y ~= sy) and (" moved to " .. x .. "," .. y) or "")
        .. (map and not map:isWalkable(sx, sy) and " blocked" or "")
        .. (not L.free() and " busy" or "")
      if id == door.map and x == sx and y == sy and map:isWalkable(sx, sy) and not map:warpAt(sx, sy) then
        local taken = holdUntilWarp(dir, 90)
        if not taken then
          -- on the warp cell already: a carpet needs a press its own way
          local _, px, py = L.pos()
          local carpet = Permissions.carpetDirection(map:cellCollision(px, py))
          if px == row.x and py == row.y and carpet then taken = holdUntilWarp(carpet, 60) end
        end
        if taken then
          L.settle(900, true)
          return taken
        end
      end
    end
    -- say what stands on the warp cell, so a blocked doorway is told apart from a harness miss
    local map = world().map
    local coll = map and world().map.id == door.map and map:cellCollision(row.x, row.y)
    local blocker = "nothing"
    for _, npc in ipairs(world().npcs or {}) do
      if npc.cellX == row.x and npc.cellY == row.y then blocker = "object " .. tostring(npc.id) end
    end
    return nil, ("no neighbouring cell walked onto the warp at %d,%d (vanilla %s:%s, collision %s, %s on it; %s)")
      :format(row.x, row.y, tostring(row.destMap), tostring(row.destWarp),
        coll and ("0x%02x"):format(coll) or "?", blocker, table.concat(tried, "; "))
  end

  -- Each walk starts from a fresh Continue of the seeded save, so a story
  -- scene one door starts (Elm's Lab walks the player up to Elm) cannot leave
  -- a script running into the next.
  local seededSave = copy(game.save)
  local function freshStart()
    game:continueGame(copy(seededSave))
    L.settle(600, true)
    L.strongParty()
    warps = {}
  end

  -- From the arrival cell inside, walk straight back out.
  local function leave(arrivalCell)
    local note
    if arrivalCell then
      local id, px, py = L.pos()
      if px ~= arrivalCell.x or py ~= arrivalCell.y then
        -- an entry scene (Elm's Lab) walked the player off the mat: back onto it
        note = "a scene moved the player to " .. px .. "," .. py .. "; put back on the mat"
        L.teleport(id, arrivalCell.x, arrivalCell.y, "down")
      end
    end
    local map = world().map
    local _, x, y = L.pos()
    local carpet = map and Permissions.carpetDirection(map:cellCollision(x, y))
    if carpet then
      local taken = holdUntilWarp(carpet, 90)
      if taken then L.settle(900, true) taken.note = note return taken end
    end
    -- a stair or cave mouth: step off, then back on
    for _, dir in ipairs({ "down", "up", "left", "right" }) do
      local d = DELTA[dir]
      if map:isWalkable(x + d[1], y + d[2]) and not map:warpAt(x + d[1], y + d[2]) then
        if stepOnce(dir, 40) then
          local taken = holdUntilWarp(OPPOSITE[dir], 90)
          if taken then L.settle(900, true) taken.note = note return taken end
          -- the step may itself have left the map
        end
        L.teleport(world().map.id, x, y, OPPOSITE[dir])
        map = world().map
      end
    end
    return nil, "could not walk back out from " .. L.where()
  end

  ------------------------------------------------------------------------------
  -- 2. Every outdoor door on the four towns, with its navigation name.
  ------------------------------------------------------------------------------
  local function navItems(mapId)
    local rows = vanillaWarps[mapId] or {}
    -- stand somewhere walkable on the map: beside its first warp
    local first = rows[1]
    if not first then return {} end
    L.teleport(mapId, first.x, first.y + 1, "up")
    local ok, items = pcall(L.browse, "all")
    if not ok then return {}, tostring(items) end
    local out = {}
    for _, item in ipairs(items or {}) do
      if item.type == "warp" then out[#out + 1] = item end
    end
    return out
  end
  local function navFor(items, row)
    for _, item in ipairs(items) do
      if item.x == row.x and item.y == row.y then return item end
    end
    for _, item in ipairs(items) do
      for _, cell in ipairs(item.navigationCells or {}) do
        if cell.x == row.x and cell.y == row.y then return item end
      end
    end
    for _, item in ipairs(items) do
      if math.abs((item.x or -99) - row.x) + math.abs((item.y or -99) - row.y) == 1 then return item end
    end
    return nil
  end

  local candidates = {} -- per town: door ids, moved ones first
  local navChecked, navWrong, navMoved = 0, 0, 0
  for _, town in ipairs(TOWNS) do
    if overBudget() then break end
    local rows = vanillaWarps[town] or {}
    local items, navWhy = navItems(town)
    if navWhy then log("FAIL", town, "navigation object list failed:", navWhy) end
    local list = {}
    for i, row in ipairs(rows) do
      local live = data.gen2Maps[town].warps[i]
      local doorId, door = doorAt(town, i)
      local expMap, expWarp
      if door then expMap, expWarp = expectedDest(doorId) end
      local item = navFor(items, row)
      local navName = item and (item.description or item.label) or "(not listed)"
      U.log("DOOR", town .. ":" .. i, "at " .. row.x .. "," .. row.y,
        "vanilla " .. tostring(row.destMap) .. ":" .. tostring(row.destWarp),
        "door " .. tostring(doorId or "(not a door in the graph)"),
        "placement " .. (door and (tostring(targetOf(doorId)) .. " -> " .. tostring(expMap) .. ":" .. tostring(expWarp)) or "-"),
        "data now " .. tostring(live.destMap) .. ":" .. tostring(live.destWarp),
        "nav \"" .. tostring(navName) .. "\" -> " .. tostring(item and item.destinationMapId))
      if door and placement then
        log((live.destMap == expMap and live.destWarp == expWarp) and "PASS" or "FAIL",
          town .. ":" .. i, "warp data leads where the placement says")
        if item then
          navChecked = navChecked + 1
          if item.destinationMapId ~= expMap then navWrong = navWrong + 1 end
          if isMoved(doorId) then
            navMoved = navMoved + 1
            log(item.destinationMapId == expMap and "PASS" or "FAIL", town .. ":" .. i, "shuffled door named",
              "\"" .. tostring(item.description or item.label) .. "\"", "leads to " .. tostring(expMap))
          end
        end
      end
      if door then list[#list + 1] = doorId end
    end
    -- moved doors first, then ordinary dead ends (houses, centers, marts),
    -- which have no story scene on entry, then the rest
    local function rank(id)
      if isMoved(id) then return 0 end
      local c = complexOf(id)
      local fixed = rules and rules.fixed and c and rules.fixed[c.id]
      if c and c.deadEnd and not fixed and not c.story then return 1 end
      return 2
    end
    table.sort(list, function(a, b)
      local ra, rb = rank(a), rank(b)
      if ra ~= rb then return ra < rb end
      return tostring(a) < tostring(b)
    end)
    candidates[town] = list
  end
  if placement then
    log(navChecked > 0 and navWrong == 0 and "PASS" or "FAIL",
      "navigation names each door by where it leads now", (navChecked - navWrong) .. " of " .. navChecked,
      navMoved .. " of them shuffled")
  else
    log("SKIP", "navigation names: no placement to compare against")
  end

  ------------------------------------------------------------------------------
  -- 3. Walk in and back out of a sample of doors.
  ------------------------------------------------------------------------------
  -- With no placement the walks still run against vanilla doors (every door
  -- its own target), which proves the walking harness before the shuffle lands.
  if not graph then
    log("SKIP", "door walks: no door graph")
  else
    if not placement then U.log("NOTE", "no placement: walking vanilla doors to check the harness itself") end
    for _, town in ipairs(TOWNS) do
      for n, doorId in ipairs(candidates[town] or {}) do
        if n > sample then break end
        if overBudget() then log("SKIP", "frame budget spent before " .. doorId) break end
        local door = graph.doors[doorId]
        local expMap, expWarp = expectedDest(doorId)
        local moved = isMoved(doorId) and "moved" or "kept"
        freshStart()
        local arrived, why = enterDoor(door)
        if not arrived then
          log("FAIL", doorId, "walk in:", why)
        else
          local okIn = arrived.to == expMap and (arrived.toWarp == nil or arrived.toWarp == expWarp)
          log(okIn and "PASS" or "FAIL", doorId, moved, "walked in to " .. tostring(arrived.to) .. ":" .. tostring(arrived.toWarp),
            "expected " .. tostring(expMap) .. ":" .. tostring(expWarp), arrived.guessed and "(warp guessed from cell)" or "")
          if okIn then
            local back, whyBack = leave(vanillaWarps[expMap] and vanillaWarps[expMap][expWarp])
            if not back then
              log("FAIL", doorId, "walk out:", whyBack)
            else
              -- the explicit exits of a moved entrance point at its first
              -- tile (maps.lua), so any tile of the doorway used counts
              local tiles, tileSet = {}, {}
              local entrance = graph.entrances and door.entrance and graph.entrances[door.entrance]
              for _, did in ipairs(entrance and entrance.doors or { doorId }) do
                local d = graph.doors[did]
                if d then tiles[#tiles + 1] = d.warp tileSet[d.warp] = true end
              end
              local okOut = back.to == door.map and (back.toWarp == nil or tileSet[back.toWarp] == true)
              log(okOut and "PASS" or "FAIL", doorId, "walked out to " .. tostring(back.to) .. ":" .. tostring(back.toWarp),
                "expected " .. door.map .. ":" .. table.concat(tiles, "/"), back.guessed and "(warp guessed from cell)" or "",
                back.note or "")
            end
          end
        end
      end
    end
  end

  ------------------------------------------------------------------------------
  -- 4. Escape Rope inside a shuffled cave.
  ------------------------------------------------------------------------------
  if level == "caves" or level == "full" then
    local choices = {}
    if graph then
      local ids = {}
      for id in pairs(graph.doors) do ids[#ids + 1] = id end
      table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
      for _, id in ipairs(ids) do
        local target = targetOf(id)
        local into = complexOf(target)
        -- with no placement (harness check) any door into a cave will do
        -- MOUNT_MOON_SQUARE and TIN_TOWER_ROOF are outdoor maps inside indoor
        -- ones, which the engine never banks as an Escape Rope door
        -- (World:recordWarpBackup DIG_WARP_EXCLUDED); a teleport straight onto
        -- them skips the way in that banks one, so they make no rope test
        local onMap = graph.doors[id].map
        if (isMoved(id) or not placement) and into and (into.environment == "CAVE" or into.environment == "DUNGEON")
            and onMap ~= "MOUNT_MOON_SQUARE" and onMap ~= "TIN_TOWER_ROOF" then
          choices[#choices + 1] = id
        end
      end
    end
    -- the first shuffled cave door that can be walked onto; one that cannot is
    -- itself a finding (a cave placed behind a walled-off doorway)
    local choice, door
    for n, id in ipairs(choices) do
      if n > 4 or overBudget() then break end
      freshStart()
      local arrivedTry, whyTry = enterDoor(graph.doors[id])
      if arrivedTry then
        choice, door = id, graph.doors[id]
        break
      end
      local into = complexOf(targetOf(id))
      log("FAIL", "shuffled cave door cannot be walked onto", id, "now leads into " ..
        tostring(into and into.maps and into.maps[1] or targetOf(id)), whyTry)
    end
    if not choice then
      log("SKIP", "escape rope: " .. (#choices > 0 and "no shuffled cave door could be entered"
        or (graph and placement) and "no door leads into a cave or dungeon by shuffle" or "no graph"))
    else
      do
        local caveMap = world().map and world().map.id
        game.save.inventory = game.save.inventory or {}
        game.save.inventory.ESCAPE_ROPE = (game.save.inventory.ESCAPE_ROPE or 0) + 1
        local outcome = world():useFieldItem("ESCAPE_ROPE")
        L.settle(1500, true)
        local id, x, y = L.pos()
        local row = vanillaWarps[door.map][door.warp]
        local distance = id == door.map and (math.abs(x - row.x) + math.abs(y - row.y)) or nil
        local vanillaDoor = graph.doors[targetOf(choice)]
        U.log("RESULT", "escape rope", "entered by " .. choice .. " into " .. tostring(caveMap),
          "outcome " .. tostring(outcome), "landed " .. L.where(),
          "the vanilla door of that cave is " .. tostring(vanillaDoor and (vanillaDoor.map .. ":" .. vanillaDoor.warp)))
        log(distance and distance <= 2 and "PASS" or "FAIL", "escape rope lands at the door used",
          choice .. " at " .. door.map .. " (" .. row.x .. "," .. row.y .. ")", "landed " .. L.where())
        if not present.mapmoves then log("MISSING", "mapmoves", "escape rope result above is the engine's own") end
      end
    end
  end

  ------------------------------------------------------------------------------
  -- 5. The placement's own canWin.
  ------------------------------------------------------------------------------
  if rules and placement then
    local ok, win, why = pcall(rules.canWin, placement, ctx.shared.keyitems)
    if not ok then
      log("FAIL", "canWin raised:", tostring(win))
    else
      U.log("RESULT", "canWin", tostring(win), tostring(why or ""))
      log(win and "PASS" or "FAIL", "the placement is beatable by its own rules")
    end
  else
    log("SKIP", "canWin: " .. (rules and "no placement" or "no rules"))
  end

  if unsubscribe then pcall(unsubscribe) end
  summary()
end
