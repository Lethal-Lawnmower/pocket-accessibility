-- Red, Blue and Yellow navigation against every map (whole-map evidence, not a
-- sample).  For each map the list a player standing there gets, checked for
-- generic or broken labels; every warp's and connection's use; every target
-- routed from every way onto the map, with the party's full field moves.
-- Nothing is walked here: see gen1_nav_walk.lua for that.  Harness setup
-- teleports and gives a party.  Silent; read the RESULT, LABEL and UNREACHED lines.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Pathfinder = require("src.access.nav.Pathfinder")
  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  local save = game.save
  local mon = Pokemon.new(game.data, "MEWTWO", 100)
  mon.moves = { { id = "CUT", pp = 30 }, { id = "SURF", pp = 15 }, { id = "STRENGTH", pp = 15 }, { id = "FLASH", pp = 20 } }
  save.party = { mon }
  for _, badge in ipairs({ "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE",
      "VOLCANOBADGE", "EARTHBADGE" }) do
    save.inventory[badge] = 1
  end
  save.inventory.CARD_KEY = 1
  save.flashLit = true
  save.repelSteps = 99999
  local function nav() return package.loaded["src.access.nav"].coordinator() end

  local ids = {}
  for id, def in pairs(game.data.maps) do
    if type(def) == "table" and type(def.warps) == "table" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  local only = os.getenv("SWEEP_MAPS")

  local totals = { maps = 0, skipped = 0, items = 0, signposts = 0, bad = 0, merged = 0, unreached = 0, nogoals = 0, deadConnections = 0 }
  local signText = {}
  local function bad(label)
    if type(label) ~= "string" or label == "" then return true end
    return label:find("Unknown", 1, true) or label:find("_", 1, true) or label:match("^Warp %d")
      or label:match("^Object %d") or label:find("Interactive object", 1, true) or label:find("LAST", 1, true)
      or label:find("nil", 1, true) or label == "Exit"
  end

  -- where a player can come onto this map: its warps' cells, and its edges
  local function entries(map, def)
    local list, seen = {}, {}
    local function add(x, y, why)
      local key = x .. "," .. y
      if not seen[key] and map:inBounds(x, y) then
        seen[key] = true
        list[#list + 1] = { x = x, y = y, why = why }
      end
    end
    for _, warp in ipairs(def.warps or {}) do add(warp.x, warp.y, "warp") end
    for dir in pairs(def.connections or {}) do
      local w, h = map.widthCells, map.heightCells
      local function edge(x, y)
        if map:isWalkableCell(x, y) then add(x, y, "edge " .. dir) end
      end
      if dir == "north" then for x = 0, w - 1 do edge(x, 0) end end
      if dir == "south" then for x = 0, w - 1 do edge(x, h - 1) end end
      if dir == "west" then for y = 0, h - 1 do edge(0, y) end end
      if dir == "east" then for y = 0, h - 1 do edge(w - 1, y) end end
    end
    return list
  end

  local function route(coordinator, goals, policy)
    local options = coordinator:worldRouteRequest(goals, policy)
    if not options then return nil end
    options.maxSeconds = 0.25
    local ok, result = pcall(Pathfinder.find, options)
    return ok and result or nil
  end

  for _, mapId in ipairs(ids) do
    if not only or only:find(mapId, 1, true) then
      local def = game.data.maps[mapId]
      local start = def.warps and def.warps[1]
      local ok = pcall(U.teleport, game, mapId, start and start.x or 0, start and start.y or 0, "down")
      for _ = 1, 120 do
        if not game.overworld.transitioning then break end
        U.wait(1)
      end
      -- scripts that run on entry (text, a walk): cleared as a player would
      for _ = 1, 60 do
        if game.stack:top() == game.overworld then break end
        U.tap(game, "a") U.wait(3)
      end
      if not ok or game.stack:top() ~= game.overworld or not nav() then
        totals.skipped = totals.skipped + 1
        U.log("SKIP", mapId, "not on the map")
      else
        totals.maps = totals.maps + 1
        local coordinator = nav()
        coordinator.browseFilter = "all"
        local snapshot = coordinator:captureWorld("all")
        local player = game.overworld.player
        local map = game.overworld.map
        local cells = entries(map, def)
        local homeX, homeY = player.cellX, player.cellY
        for _, item in ipairs(snapshot and snapshot.browse or {}) do
          totals.items = totals.items + 1
          if bad(item.label) then
            totals.bad = totals.bad + 1
            U.log("LABEL", mapId, item.type, tostring(item.label))
          end
          if tostring(item.label):match("^Signpost %d") then
            totals.signposts = totals.signposts + 1
            U.log("GENERIC", mapId, tostring(item.label), tostring(item.textId))
          end
          if item.type == "signpost" then U.log("SIGN", mapId, tostring(item.label)) end
          if item.type == "warp" and #(item.navigationCells or {}) > 1 then
            -- side by side only
            local nav2 = item.navigationCells
            for i = 2, #nav2 do
              local near = false
              for j = 1, #nav2 do
                if j ~= i and math.abs(nav2[i].x - nav2[j].x) + math.abs(nav2[i].y - nav2[j].y) == 1 then near = true end
              end
              if not near then
                totals.merged = totals.merged + 1
                U.log("MERGED", mapId, tostring(item.label), nav2[1].x .. "," .. nav2[1].y, nav2[i].x .. "," .. nav2[i].y)
                break
              end
            end
          end
          coordinator.browseSelectionId = item.id
          local _, goals = coordinator:selectedRouteGoals()
          if type(goals) ~= "table" or #goals == 0 then
            totals.nogoals = totals.nogoals + 1
            U.log("NOGOALS", mapId, item.type, tostring(item.label), item.x, item.y)
          else
            local reached, from1, from3 = false, nil, nil
            for _, cell in ipairs(cells) do
              player.cellX, player.cellY = cell.x, cell.y
              if route(coordinator, goals, 2) then reached = true from1 = cell break end
            end
            if not reached then
              for _, cell in ipairs(cells) do
                player.cellX, player.cellY = cell.x, cell.y
                if route(coordinator, goals, 3) then from3 = cell break end
              end
              totals.unreached = totals.unreached + 1
              U.log("UNREACHED", mapId, item.type, tostring(item.label), item.x, item.y, "entries", #cells,
                from3 and ("policy3 from " .. from3.x .. "," .. from3.y) or "never")
            end
            player.cellX, player.cellY = homeX, homeY
          end
          -- a connection's goal cells: does the game really cross there?
          if item.type == "connection" then
            local dir = ({ north = "up", south = "down", east = "right", west = "left" })[item.direction]
            local dead, live = 0, 0
            for _, goal in ipairs(type(goals) == "table" and goals or {}) do
              player.cellX, player.cellY = goal.x, goal.y
              local facing = player.facing
              player.facing = dir
              local okLanding, dest, ts, x, y = pcall(game.overworld.connectionLanding, game.overworld, dir)
              player.facing = facing
              local passable = false
              if okLanding and dest and ts then
                local Map = require("src.world.Map")
                local okPass, value = pcall(Map.defPassable, dest, ts, x, y, map:isWaterCell(goal.x, goal.y))
                passable = okPass and value == true
              end
              if passable then live = live + 1 else dead = dead + 1 end
            end
            player.cellX, player.cellY = homeX, homeY
            if dead > 0 then
              totals.deadConnections = totals.deadConnections + 1
              U.log("DEADEDGE", mapId, tostring(item.label), "dead", dead, "live", live)
            end
          end
        end
      end
    end
  end
  U.log("RESULT", "maps", totals.maps, "skipped", totals.skipped, "items", totals.items, "Signpost N", totals.signposts,
    "bad labels", totals.bad, "merged warps", totals.merged, "no goals", totals.nogoals, "unreached", totals.unreached,
    "connections with dead edge cells", totals.deadConnections)
  U.log("DONE")
end
