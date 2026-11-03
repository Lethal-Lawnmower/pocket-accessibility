-- Gen 2 navigation against every map of the edition, in the game: the whole-map
-- evidence for labels, reachability and journeys that gen2_story_spots.lua gives
-- for a chosen list of maps by walking.  Nothing here walks; it reads the object
-- list a player would get and asks the same planners auto-walk uses.
--
-- For every map, standing just inside it with every field move and badge:
--   LABEL   every generic name ("Signpost N"), raw or empty label, and a count
--   MERGED  warps to one map that stand apart but share one list entry
--   UNREACH a listed target no arrival on the map can walk to, with what gates it
--           (object: a person or boulder; collision: a door, wall or puzzle)
--   JOURNEY each other floor of the map's Area group, planned as a journey from the
--           map's first arrival: slow plans ("timed out") and refusals are logged
--   LEG     (with SWEEP_ITEMS=1) the same for every Area item
-- Then WORLD: the maps the whole game can reach from the start by warps and
-- connections alone, and those it cannot (scripted rides).
--
-- SWEEP_MAPS=A,B limits the maps; SWEEP_FROM=name starts at a map in sorted order.
-- Harness setup teleports and gives a party.  Silent; read the SWEEP lines.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local Pathfinder = require("src.access.nav.Pathfinder")
  local Permissions = require("src.world.gen2.Permissions")
  local Mon = require("src.battle.gen2.Mon")
  if not L.settle(3000, true) then U.log("FAIL", "never reached the free world") return end
  game.driverSpeed = 8
  game.options.battleStyle, game.options.battleScene, game.options.textSpeed = "SET", false, "FAST"
  local version = tostring(game.save and game.save.version or os.getenv("POKEPORT_VERSION"))
  local maps = game.data.gen2Maps
  local function newMon(species, moves)
    local mon = Mon.new(game.data, species, 100)
    local list = {}
    for i, id in ipairs(moves) do list[i] = { id = id, pp = 60 } end
    mon.moves = list
    return mon
  end
  game.save.party = {
    newMon("MEWTWO", { "ICE_BEAM", "SURF", "STRENGTH", "FLASH" }),
    newMon("FERALIGATR", { "CUT", "WHIRLPOOL", "WATERFALL", "ROCK_SMASH" }),
    newMon("SNORLAX", { "HEADBUTT", "EARTHQUAKE", "FLY", "STRENGTH" }),
  }
  game.save.player.badges = game.save.player.badges or {}
  for _, badge in ipairs({ "ZEPHYR", "HIVE", "PLAIN", "FOG", "STORM", "MINERAL", "GLACIER", "RISING" }) do
    game.save.player.badges[badge] = true
  end
  game.save.repelSteps = 60000
  game.world.flashUsed = true

  local only = os.getenv("SWEEP_MAPS")
  local from = os.getenv("SWEEP_FROM")
  local allItems = os.getenv("SWEEP_ITEMS") == "1"
  local ids = {}
  for id in pairs(maps) do
    if type(id) == "string" and (not only or ("," .. only .. ","):find("," .. id .. ",", 1, true))
       and (not from or id >= from) then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)

  local nav = L.nav()
  -- the shared planner, for before-and-after numbers
  if os.getenv("SWEEP_OLD_PLANNER") == "1" then
    nav.regionalNextLeg = require("src.access.nav.Navigation").regionalNextLeg
  end
  local totals = { maps = 0, labels = 0, generic = 0, bad = 0, unreachObject = 0, unreachCollision = 0, merged = 0,
    journeys = 0, journeyOk = 0, timedOut = 0, refused = 0, slowest = 0, notStood = 0 }
  local arrivalsOf = {} -- map id -> list of arrival cells from other maps
  local function arrival(map, x, y)
    arrivalsOf[map] = arrivalsOf[map] or {}
    arrivalsOf[map][x .. "," .. y] = { x = x, y = y }
  end
  local edges = {}
  for id in pairs(maps) do
    edges[id] = nav:regionalTransitions(id)
    for _, t in ipairs(edges[id]) do arrival(t.destMap, t.destX, t.destY) end
  end

  -- every cell reachable from `start`, by the same graph a route uses; warps are
  -- reached but not walked through
  local function flood(world, start, goals)
    local options = nav:routeOptionsFor(world, goals, 2)
    local seen, queue, head = { [start.x .. "," .. start.y] = true }, { start }, 1
    while queue[head] do
      local cell = queue[head]
      head = head + 1
      local warp = world.map:warpAt(cell.x, cell.y)
      if head == 2 or not warp or not Permissions.isWarpCollision(world.map:cellCollision(cell.x, cell.y)) then
        for _, edge in ipairs(options.neighbors(cell.x, cell.y)) do
          local key = edge.x .. "," .. edge.y
          if not seen[key] then
            seen[key] = true
            queue[#queue + 1] = { x = edge.x, y = edge.y }
          end
        end
      end
    end
    return seen
  end

  local function badLabel(label)
    if type(label) ~= "string" or label == "" then return true end
    return label:find("nil", 1, true) or label:find("Unknown", 1, true) or label:find("_", 1, true)
      or label:match("%x%x:%x%x%x%x") ~= nil or label:match("^Warp %d") or label:match("^Object %d")
  end

  local held = require("src.access.nav.WorldAdapter").gen2.scriptHeld
  local function standOn(mapId)
    -- a scene or battle a teleport started: finish it (a strong lead wins)
    for _ = 1, 6000 do
      if not held(game.world) and game.stack:top() == nil then break end
      if not L.battleStep() then L.tap("a", 4) end
    end
    -- beside the first arrival: a teleport onto a door skips the game's step off it
    local cells = {}
    for _, cell in pairs(arrivalsOf[mapId] or {}) do cells[#cells + 1] = cell end
    table.sort(cells, function(a, b) return a.y * 1000 + a.x < b.y * 1000 + b.x end)
    for _, warp in ipairs(maps[mapId].warps or {}) do cells[#cells + 1] = { x = warp.x, y = warp.y } end
    if #cells == 0 then cells[1] = { x = 2, y = 2 } end
    local first = cells[1]
    -- no scene plays on arrival: past the map's last one, so a rival's walk or a
    -- quiz neither sends the player away nor holds the sweep
    game.world.mapScenes = game.world.mapScenes or {}
    local lastScene = 0
    for id in pairs(maps[mapId].sceneScripts or {}) do
      if type(id) == "number" and id > lastScene then lastScene = id end
    end
    game.world.mapScenes[mapId] = lastScene + 1
    L.teleport(mapId, first.x, first.y, "down")
    L.settle(200, true, 10)
    game.world.flashUsed = true
    local function ready() return L.pos() == mapId and nav:worldForCommand() ~= nil end
    if ready() then return first end
    if L.pos() ~= mapId then return nil end
    local map = game.world.map
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      local nx, ny = first.x + d[1], first.y + d[2]
      local ok, coll = pcall(map.cellCollision, map, nx, ny)
      if ok and map:inBounds(nx, ny) and Permissions.isWalkable(coll) and not Permissions.isWarpCollision(coll) then
        L.teleport(mapId, nx, ny, "down")
        L.settle(200, true, 10)
        if ready() then return first end
      end
    end
    return nil
  end

  for _, mapId in ipairs(ids) do
    local stood = standOn(mapId)
    local world = stood and nav:worldForCommand()
    if not world then
      totals.notStood = totals.notStood + 1
      local native = game.world
      U.log("NOSTAND", version, mapId, "at", L.where(), "script", tostring(native:scriptRunning()), "box", tostring(native.textbox ~= nil),
        "move", tostring(native.moveState ~= nil), "setup", tostring(native.mapSetup ~= nil), "top", tostring(game.stack:top() ~= nil),
        "phase", tostring(game.phase), "forced", tostring(require("src.access.nav.WorldAdapter").gen2.transitioning(native)))
    else
      totals.maps = totals.maps + 1
      local items = L.browse("all")
      local live = { map = world.map, native = world.native, player = { cellX = 0, cellY = 0, surfing = false },
        npcs = world.npcs, entities = world.entities }
      -- every cell any arrival reaches
      local allGoals = {}
      local warpGoals = {}
      for _, warp in ipairs(world.map.def.warps or {}) do warpGoals[#warpGoals + 1] = { x = warp.x, y = warp.y } end
      local goalsOf = {}
      for _, item in ipairs(items) do
        totals.labels = totals.labels + 1
        L.select(item, "all")
        local ok, picked, goals = pcall(nav.selectedRouteGoals, nav)
        if ok and type(goals) == "table" and type(picked) == "table" and picked.id == item.id then
          goalsOf[item.id] = goals
          for _, goal in ipairs(goals) do allGoals[#allGoals + 1] = goal end
        end
        if tostring(item.label):match("^Signpost") then
          totals.generic = totals.generic + 1
          U.log("LABEL", version, mapId, item.label, item.x, item.y)
        elseif tostring(item.label):match("^Sign: ") then
          U.log("SIGN", version, mapId, item.label)
        end
        if badLabel(item.label) then
          totals.bad = totals.bad + 1
          U.log("BADLABEL", version, mapId, item.type, tostring(item.label))
        end
      end
      for _, goal in ipairs(warpGoals) do allGoals[#allGoals + 1] = goal end
      if #allGoals == 0 then allGoals[1] = { x = 0, y = 0 } end
      local reachable = {}
      local starts = {}
      for _, cell in pairs(arrivalsOf[mapId] or {}) do starts[#starts + 1] = cell end
      if #starts == 0 then starts[1] = { x = world.player.cellX, y = world.player.cellY } end
      for _, start in ipairs(starts) do
        for key in pairs(flood(live, start, allGoals)) do reachable[key] = true end
      end
      local bare = { map = world.map, native = { npcAt = function() return nil end },
        player = { cellX = 0, cellY = 0, surfing = false }, npcs = {}, entities = {} }
      for _, item in ipairs(items) do
        local goals = goalsOf[item.id]
        if item.type ~= "area" then
          local found = false
          for _, goal in ipairs(goals or {}) do
            if reachable[goal.x .. "," .. goal.y] then found = true break end
          end
          if not found and item.requirement == nil then
            -- with objects removed?
            local bareReach = {}
            for _, start in ipairs(starts) do
              for key in pairs(flood(bare, start, allGoals)) do bareReach[key] = true end
            end
            local objectGate = false
            for _, goal in ipairs(goals or {}) do
              if bareReach[goal.x .. "," .. goal.y] then objectGate = true break end
            end
            if objectGate then totals.unreachObject = totals.unreachObject + 1
            else totals.unreachCollision = totals.unreachCollision + 1 end
            U.log("UNREACH", version, mapId, item.type, item.label, "at", item.x, item.y,
              goals and "" or "no goals", objectGate and "object" or "collision")
          end
        end
      end
      -- warps standing apart, one list entry
      local warpItems = {}
      for _, item in ipairs(items) do if item.type == "warp" then warpItems[#warpItems + 1] = item end end
      local groups = {}
      local defWarps = world.map.def.warps or {}
      for i, warp in ipairs(defWarps) do
        if Permissions.isWarpCollision(world.map:cellCollision(warp.x, warp.y)) then
          local placed
          for _, group in ipairs(groups) do
            for _, other in ipairs(group) do
              if math.abs(other.x - warp.x) + math.abs(other.y - warp.y) <= 1 then placed = group break end
            end
            if placed then break end
          end
          if placed then placed[#placed + 1] = warp else groups[#groups + 1] = { warp } end
        end
      end
      if #warpItems < #groups then
        totals.merged = totals.merged + 1
        U.log("MERGED", version, mapId, "warp groups", #groups, "listed", #warpItems)
      end
      -- journeys to the other maps of its Area group
      if nav:worldForCommand() then
        local areaItems = L.browse("area")
        for _, item in ipairs(areaItems) do
          if allItems or item.id == "area:" .. tostring(item.mapId) then
            L.select(item, "area")
            local ok, picked, goals = pcall(nav.selectedRouteGoals, nav)
            if ok and type(goals) == "table" and #goals > 0 and type(picked) == "table" then
              totals.journeys = totals.journeys + 1
              local clock = os.clock()
              local okLeg, leg, reason = pcall(nav.regionalNextLeg, nav, { targetMapId = item.mapId, targetGoals = goals })
              local seconds = os.clock() - clock
              if seconds > totals.slowest then totals.slowest = seconds end
              if okLeg and leg then
                totals.journeyOk = totals.journeyOk + 1
              elseif okLeg and tostring(reason):find("timed out", 1, true) then
                totals.timedOut = totals.timedOut + 1
                U.log("JOURNEY", version, mapId, "to", item.label, "timed out", ("%.2f"):format(seconds))
              else
                totals.refused = totals.refused + 1
                U.log("JOURNEY", version, mapId, "to", item.label, "refused", tostring(reason))
              end
            else
              U.log("JOURNEY", version, mapId, "to", item.label, "no goals", tostring(goals))
            end
          end
        end
      end
    end
  end
  -- the whole game's map graph, from the player's start
  local startId = maps.PLAYERS_HOUSE_2F and "PLAYERS_HOUSE_2F" or ids[1]
  local seen, queue, head = { [startId] = true }, { startId }, 1
  while queue[head] do
    local id = queue[head]
    head = head + 1
    for _, t in ipairs(edges[id] or {}) do
      if not seen[t.destMap] then seen[t.destMap] = true queue[#queue + 1] = t.destMap end
    end
  end
  local lonely = {}
  for id in pairs(maps) do if not seen[id] then lonely[#lonely + 1] = id end end
  table.sort(lonely)
  U.log("WORLD", version, "maps from the start", #queue, "not by warp or connection:", table.concat(lonely, " "))
  local parts = {}
  for key, value in pairs(totals) do parts[#parts + 1] = key .. "=" .. tostring(value) end
  table.sort(parts)
  U.log("SWEEP", version, table.concat(parts, " "))
  U.log("DONE")
end
