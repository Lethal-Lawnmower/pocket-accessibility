-- FireRed navigation, the gaps closed after the first merge (decision 29):
--   A. cross-map journeys on the one-pass planner: Silph Co. 1F to the Card
--      Key, Rocket Hideout B2F to B4F, Silph Co. 4F to 5F, and the B4F item
--      only the elevator reaches (a real gate: "No route")
--   B. an item ball that blocks the only way: auto-walk picks it up and
--      walks on (the first such ball the scan finds on the cartridge)
--   C. renaming (Shift+K, Shift+M) through the game's naming screen
--   D. Icefall Cave ice and thin ice, E. Seafoam Islands currents,
--   F. a Pokemon Mansion secret switch, G. a waterfall climbed with
--      Waterfall
-- Harness setup (party, badges, story flags, teleports) uses the game's
-- own loader, party and flag store.  Silent and isolated:
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/gen3_nav_gaps.lua
-- GEN3_GAPS_ONLY=<letters> runs only those parts (for example "BD").
return function(game)
  local L = dofile("tests/access/drivers/gen3_nav_lib.lua").new(game)
  local U = L.U
  if not L.boot() then return end
  -- a Pokemon has four move slots (the first is the harness's attack)
  L.giveParty(6, 70, { "SURF", "STRENGTH", "CUT" },
    { "CUT", "SURF", "STRENGTH", "WATERFALL", "ROCK_SMASH" })
  L.setVar(0x4050, 3)
  local only = os.getenv("GEN3_GAPS_ONLY")
  local function part(letter) return not only or only == "" or only:find(letter, 1, true) ~= nil end
  local maps = game.data.maps
  local World = require("src.access.nav.gen3.World")
  local Pathfinder = require("src.access.nav.Pathfinder")
  local AutoWalk = require("src.access.nav.AutoWalk")

  -- Auto-walk to one cell (not an object-list entry): the coordinator's
  -- selection is answered with the cell for the length of the walk.
  local function walkToCell(x, y, label, opts)
    local nav = L.nav()
    nav.selectedRouteGoals = function(self)
      return { id = "cell:" .. x .. "," .. y, label = label, type = "cell" }, { { x = x, y = y } },
        nil, nil, self:worldForCommand()
    end
    local said = L.walkTo(nil, opts)
    nav.selectedRouteGoals = nil
    return said
  end

  local function kindsOf(steps)
    local seen = {}
    for _, step in ipairs(steps or {}) do if step.kind then seen[step.kind] = true end end
    local list = {}
    for kind in pairs(seen) do list[#list + 1] = kind end
    table.sort(list)
    return table.concat(list, ",")
  end

  -- Walk to each warp of the floor (up to `limitWarps`) from one start;
  -- the walk's planned steps (with their forced moves) are logged by
  -- L.walkTo.  Returns the arrivals and the warps tried.
  local function walkFloor(mapId, startX, startY, limitWarps)
    local arrived, tried = 0, 0
    L.teleport(mapId, startX, startY, "down")
    U.log("FLOOR", L.where())
    local warps = L.browse("warps")
    for i, warp in ipairs(warps) do
      if i > (limitWarps or 4) then break end
      if L.pos() ~= mapId then L.teleport(mapId, startX, startY, "down") end
      tried = tried + 1
      U.log("GUIDE", warp.label, "=>", L.guide(warp, "warps"))
      local said = L.walkTo(warp, { trace = true, answer = "a", limit = 12000, filter = "warps" })
      U.log("WALK", mapId, warp.label, "=>", said, "now", L.where())
      if said:find("Arrived at", 1, true) ~= nil or L.pos() ~= mapId then arrived = arrived + 1 end
      L.teleport(mapId, startX, startY, "down")
    end
    return arrived, tried
  end

  -- A walk on the floor that crosses the terrain under test, planned on
  -- the live floor: a move whose instruction matches `wantText` ("onto ice",
  -- "into the current") or a step onto a cell of behaviour `wantBehavior`
  -- (thin ice).  From each land start (a warp or a cell beside an object;
  -- on water the player would not be surfing), the movement graph is
  -- flooded and the first cell reached that way is the goal.  Returns
  -- whether the walk arrived and what was said, or nil when no such walk
  -- exists.
  local function forcedWalk(mapId, what, wantText, wantBehavior)
    local def = maps[mapId]
    local nav = L.nav()
    local view = World.plannedView(game, def)
    local starts = {}
    for _, w in ipairs(def.warps or {}) do
      if view:isWalkableCell(w.x, w.y) or not view:isWater(w.x, w.y) then starts[#starts + 1] = { x = w.x, y = w.y } end
    end
    for _, o in ipairs(def.objects or {}) do
      for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
        local x, y = o.x + d[1], o.y + d[2]
        if view:isWalkableCell(x, y) then starts[#starts + 1] = { x = x, y = y } end
      end
    end
    local function wanted(edge)
      return (wantText and tostring(edge.instruction):find(wantText) ~= nil)
        or (wantBehavior and view:behavior(edge.x, edge.y) == wantBehavior)
    end
    for i, s in ipairs(starts) do
      if i > 8 then break end
      L.teleport(mapId, s.x, s.y, "down")
      local live = nav:worldForCommand()
      local options = live and nav:routeOptionsFor(live, { { x = s.x, y = s.y } }, 2)
      local seen, queue, head = { [s.x .. "," .. s.y] = true }, { s }, 1
      local goal
      while options and not goal and head <= #queue and head < 3000 do
        local c = queue[head]
        head = head + 1
        for _, edge in ipairs(options.neighbors(c.x, c.y)) do
          local k = edge.x .. "," .. edge.y
          if not seen[k] and not view:warpAt(edge.x, edge.y) then
            seen[k] = true
            queue[#queue + 1] = { x = edge.x, y = edge.y }
            if wanted(edge) and not goal then
              local r = Pathfinder.find(nav:routeOptionsFor(live, { { x = edge.x, y = edge.y } }, 2))
              local crosses = false
              for _, step in ipairs(r and r.steps or {}) do if wanted(step) then crosses = true end end
              if crosses then goal = { x = edge.x, y = edge.y, route = r } end
            end
          end
        end
      end
      if goal then
        local said = {}
        for _, step in ipairs(goal.route.steps) do
          if step.instruction then said[#said + 1] = step.instruction end
        end
        U.log("FORCED", mapId, what, "from", s.x, s.y, "to", goal.x, goal.y, "special moves:", table.concat(said, "; "))
        local text = walkToCell(goal.x, goal.y, what .. " goal", { trace = true, answer = "a", limit = 12000 })
        U.log("WALK", text, "at", L.where())
        local id, x, y = L.pos()
        return id == mapId and x == goal.x and y == goal.y, text
      end
    end
    U.log("NOTE", mapId, "no walk from its warps or objects crosses", what)
    return nil
  end

  -- ---------------------------------------------------------------- A
  if part("A") then
    local function journey(mapId, x, y, pattern, limit)
      L.teleport(mapId, x, y, "down")
      local target = L.findLabel(pattern, "area")
      if not target then L.check(false, "Area lists " .. pattern .. " from " .. mapId) return nil end
      L.select(target, "area")
      local _, goals = L.nav():selectedRouteGoals()
      local t0 = os.clock()
      local leg, why = L.nav():regionalNextLeg({ targetMapId = target.mapId, targetGoals = goals })
      local seconds = os.clock() - t0
      U.log("LEG", mapId, target.label, leg and ("next " .. tostring(leg.nextMapId or "final")) or tostring(why),
        ("%.3fs"):format(seconds))
      if not leg then return nil, why, target end
      local said = L.walkTo(target, { trace = true, answer = "a", limit = limit or 40000, filter = "area" })
      U.log("JOURNEY", said, "at", L.where())
      return said, seconds, target
    end
    -- Protein on 5F is behind a card key door: without the key, say so
    local said, why = journey("FR_SILPH_CO_4F", 28, 3, "^Protein")
    U.log("GATE", tostring(said), tostring(why))
    L.check(said == nil and why == "Needs Card Key", "Silph Co. 4F to Protein without the key: " .. tostring(why))
    local seconds
    said, seconds = journey("FR_SILPH_CO_1F", 8, 18, "^Card Key")
    L.check(said and said:find("Arrived at Card Key", 1, true) ~= nil,
      "Silph Co. 1F to the Card Key on 5F walked by journey (planned in " .. tostring(seconds) .. "s)")
    if said and said:find("Arrived at Card Key", 1, true) then
      local face = said:match("Face (%a+) and interact")
      if face then L.tap(face, 12) end
      L.tap("a", 20)
      L.settle(600, true)
      U.log("SAID", L.heard())
    end
    L.check(L.nav():hasCardKey(), "the Card Key was picked up")
    said, seconds = journey("FR_SILPH_CO_4F", 28, 3, "^Protein")
    L.check(said and said:find("Arrived at", 1, true) ~= nil,
      "Silph Co. 4F to Protein on 5F through a card key door (planned in " .. tostring(seconds) .. "s)")
    said, seconds = journey("FR_ROCKET_HIDEOUT_B2F", 28, 3, "^TM 49")
    L.check(said and said:find("Arrived at", 1, true) ~= nil,
      "Rocket Hideout B2F to TM 49 on B4F walked by journey (planned in " .. tostring(seconds) .. "s)")
    -- B4F's elevator side: no walk reaches it; the answer says no route
    L.teleport("FR_ROCKET_HIDEOUT_B2F", 28, 3, "down")
    local calcium = L.find(function(item) return tostring(item.label):find("^Calcium, Rocket Hideout B4F") end, "area")
    if calcium then
      local text = L.walkTo(calcium, { answer = "a", limit = 200, filter = "area" })
      U.log("GATE", text)
      L.check(text:find("No route to Calcium", 1, true) ~= nil, "the elevator-only B4F item says no route: " .. text)
    end
  end

  -- ---------------------------------------------------------------- B
  if part("B") then
    -- the first item ball that stands in the only way between its two sides
    local found
    local ids = {}
    for id in pairs(maps) do if id:match("^FR_") then ids[#ids + 1] = id end end
    table.sort(ids)
    local nav = L.nav()
    local Scripts = require("src.access.nav.gen3.Scripts")
    for _, mapId in ipairs(ids) do
      if found then break end
      for _, object in ipairs(maps[mapId].objects or {}) do
        if found then break end
        if tonumber(object.graphicsId) == 92 and Scripts.itemBallItem(object.scriptKey)
           and nav.regionalObjectVisible(nav, object) then
          for _, pair in ipairs({ { 0, -1, 0, 1 }, { -1, 0, 1, 0 } }) do
            local ax, ay, bx, by = object.x + pair[1], object.y + pair[2], object.x + pair[3], object.y + pair[4]
            local world = nav:regionalStaticWorld(mapId, { x = ax, y = ay })
            if world and world.map:isWalkableCell(ax, ay) and world.map:isWalkableCell(bx, by)
               and not world.map:warpAt(ax, ay) then
              local walkOnly = Pathfinder.find(nav:routeOptionsFor(world, { { x = bx, y = by } }, 1))
              if not walkOnly then
                local through = Pathfinder.find(nav:routeOptionsFor(world, { { x = bx, y = by } }, 2))
                if through and kindsOf(through.steps):find("item_ball", 1, true) then
                  found = { mapId = mapId, ax = ax, ay = ay, bx = bx, by = by, object = object }
                  break
                end
              end
            end
          end
        end
      end
    end
    if not found then
      U.log("NOTE", "no item ball on the cartridge blocks the only way between its sides (unit test only)")
    else
      U.log("BALL", found.mapId, "ball at", found.object.x, found.object.y, "from", found.ax, found.ay, "to", found.bx, found.by)
      L.teleport(found.mapId, found.ax, found.ay, "down")
      local said = walkToCell(found.bx, found.by, "the far side", { trace = true, answer = "a", limit = 4000 })
      U.log("WALK", said, "at", L.where())
      local _, x, y = L.pos()
      L.check(x == found.bx and y == found.by, "walked through the item ball's cell after picking it up: " .. said)
    end
  end

  -- ---------------------------------------------------------------- C
  if part("C") then
    L.teleport("FR_PALLET_TOWN", 6, 8, "down")
    local Naming = require("src.ui.game3.naming")
    local sign = L.find(function(item) return item.type == "signpost" or item.type == "sign" end, "all")
      or L.browse("all")[1]
    L.select(sign, "all")
    L.command("rename_selected_item")
    L.wait(10)
    local st = Naming._state
    L.check(Naming.isOpen() and st ~= nil, "Shift+K opens FireRed's naming screen")
    if st then
      U.log("NAMING", "title", tostring(st.title), "name", tostring(st.name), "max", tostring(st.maxLen))
      L.check(st.title == "Object name?", "the naming screen's title says what is named")
      Naming.close("Gate")
      L.wait(10)
      U.log("SAID", L.heard())
      local renamed = L.find(function(item) return item.id == sign.id end, "all")
      L.check(renamed and renamed.label == "Gate", "the object list uses the new name: " .. tostring(renamed and renamed.label))
      local names = game.options.firered and game.options.firered.accessibilityNames
      L.check(names and names.objects and names.objects.FR_PALLET_TOWN
        and names.objects.FR_PALLET_TOWN[sign.id] == "Gate", "the name is kept in FireRed's options")
    end
    L.command("rename_map")
    L.wait(10)
    st = Naming._state
    if st then
      L.check(st.title == "Map name?", "Shift+M opens the naming screen for the map")
      Naming.close("Home")
      L.wait(10)
      local spoken = L.command("read_map_name")
      U.log("M", spoken)
      L.check(spoken:find("Home", 1, true) ~= nil, "M reads the new map name: " .. spoken)
      -- clear both again (an empty name)
      L.command("rename_map") L.wait(5) Naming.close("") L.wait(5)
      L.select(sign, "all") L.command("rename_selected_item") L.wait(5) Naming.close("") L.wait(5)
      L.check(L.command("read_map_name"):find("Pallet Town", 1, true) ~= nil, "an empty name restores the game's name")
    else
      L.check(false, "Shift+M opens the naming screen")
    end
  end

  -- ---------------------------------------------------------------- D
  if part("D") then
    -- 1F: from the entrance only the entrance side is reachable; the way on
    -- is falling through thin ice the player cracked, which routes do not
    -- plan (the game's design: one-way ledges and holes made on the spot)
    local w = maps.FR_FOUR_ISLAND_ICEFALL_CAVE_1F.warps[1]
    local arrived, total = walkFloor("FR_FOUR_ISLAND_ICEFALL_CAVE_1F", w.x, w.y, 6)
    U.log("NOTE", ("Icefall Cave 1F from the entrance: %d of %d warp walks arrived"):format(arrived, total))
    local ok, said = forcedWalk("FR_FOUR_ISLAND_ICEFALL_CAVE_B1F", "ice", "onto ice; slide [3-9]", nil)
    L.check(ok == true, "Icefall Cave B1F: auto-walk across the ice arrived: " .. tostring(said))
    ok, said = forcedWalk("FR_FOUR_ISLAND_ICEFALL_CAVE_1F", "thin ice", nil, 0x26)
    if ok ~= nil then
      L.check(ok == true, "Icefall Cave 1F: auto-walk over thin ice arrived: " .. tostring(said))
    end
  end

  -- ---------------------------------------------------------------- E
  if part("E") then
    -- the strong currents run while B3F's and B4F's boulders are still
    -- above (their HIDE flags set); in this harness's new game those flags
    -- are unset and the floors' load scripts calm the currents
    for flag = 70, 77 do L.setFlag(flag, true) end
    local any = false
    for _, mapId in ipairs({ "FR_SEAFOAM_ISLANDS_B3F", "FR_SEAFOAM_ISLANDS_B4F" }) do
      local ok, said = forcedWalk(mapId, "currents", "into the current", nil)
      if ok ~= nil then
        any = true
        L.check(ok == true, mapId .. ": auto-walk carried by the currents arrived: " .. tostring(said))
      end
    end
    L.check(any, "a Seafoam route crossing currents was found and walked")
    local w = maps.FR_SEAFOAM_ISLANDS_B3F.warps[1]
    local arrived, total = walkFloor("FR_SEAFOAM_ISLANDS_B3F", w.x, w.y, 4)
    U.log("NOTE", ("Seafoam B3F warp walks: %d of %d arrived"):format(arrived, total))
  end

  -- ---------------------------------------------------------------- F
  if part("F") then
    local w = maps.FR_POKEMON_MANSION_1F.warps[1]
    L.teleport("FR_POKEMON_MANSION_1F", w.x, w.y - 1, "up")
    L.logBrowse("all")
    local switch = L.findLabel("Secret Switch", "all")
    if not switch then
      L.check(false, "Pokemon Mansion 1F lists a Secret Switch")
    else
      local function coll()
        local view = World.liveView(game)
        local cells = {}
        for y = 0, view.heightCells - 1 do
          for x = 0, view.widthCells - 1 do cells[#cells + 1] = tostring(view:isWalkableCell(x, y)) end
        end
        return table.concat(cells, ",")
      end
      local before = coll()
      local said = L.walkTo(switch, { trace = true, answer = "a", limit = 8000 })
      U.log("WALK", said, "at", L.where())
      L.check(said:find("Arrived at", 1, true) ~= nil, "walked to the Secret Switch: " .. said)
      local face = said:match("Face (%a+) and interact")
      if face then L.tap(face, 12) end
      L.tap("a", 30)
      for _ = 1, 10 do if L.messageOpen() then L.tap("a", 20) end end
      L.settle(600, true)
      U.log("SAID", L.heard())
      L.check(coll() ~= before, "pressing the switch changed the floor's gates")
      -- every warp of the floor: which ones a route reaches now
      local reached = 0
      for _, warp in ipairs(L.browse("warps")) do
        local text = L.guide(warp, "warps")
        U.log("GUIDE", warp.label, "=>", text)
        if not text:find("No route", 1, true) and not text:find("No path", 1, true) then reached = reached + 1 end
      end
      L.check(reached > 0, "routes plan across the switched gates (" .. reached .. " warps)")
    end
  end

  -- ---------------------------------------------------------------- G
  if part("G") then
    -- the waterfall on Two Island's Cape Brink: the bottom of its column
    -- and the cell above the top
    local mapId = "FR_TWO_ISLAND_CAPE_BRINK"
    local view = World.plannedView(game, maps[mapId])
    local column
    for x = 0, view.widthCells - 1 do
      for y = 0, view.heightCells - 1 do
        if view:behavior(x, y) == 0x13 and not column then column = x end
      end
    end
    local top, bottom
    for y = 0, view.heightCells - 1 do
      if view:behavior(column, y) == 0x13 then top = top or y bottom = y end
    end
    U.log("WATERFALL", mapId, "column", column, "rows", top, bottom)
    -- a shore cell beside the water below it
    local startX, startY
    local seen, queue = { [column .. "," .. (bottom + 1)] = true }, { { column, bottom + 1 } }
    local head = 1
    while head <= #queue and not startX do
      local cx, cy = queue[head][1], queue[head][2]
      head = head + 1
      for _, d in ipairs({ { 0, 1 }, { -1, 0 }, { 1, 0 }, { 0, -1 } }) do
        local nx, ny = cx + d[1], cy + d[2]
        local k = nx .. "," .. ny
        if not seen[k] and view:inBounds(nx, ny) then
          seen[k] = true
          if view:isWater(nx, ny) and view:behavior(nx, ny) ~= 0x13 then queue[#queue + 1] = { nx, ny }
          elseif view:isWalkableCell(nx, ny) and not startX then startX, startY = nx, ny end
        end
      end
    end
    U.log("SHORE", startX, startY)
    -- four move slots: Waterfall must be among them for the game (and the
    -- route) to offer it
    L.giveParty(6, 70, { "SURF", "WATERFALL", "STRENGTH" }, { "SURF", "WATERFALL", "STRENGTH" })
    L.teleport(mapId, startX, startY, "down")
    local options = L.nav():worldRouteRequest({ { x = column, y = top - 1 } }, 2)
    local planned = options and Pathfinder.find(options)
    L.check(planned and kindsOf(planned.steps):find("waterfall", 1, true) ~= nil,
      "the route climbs the waterfall: " .. (planned and kindsOf(planned.steps) or "no route"))
    local said = walkToCell(column, top - 1, "the top of the waterfall", { trace = true, answer = "a", limit = 12000 })
    U.log("WALK", said, "at", L.where())
    local _, x, y = L.pos()
    L.check(x == column and y == top - 1, "climbed the waterfall by auto-walk (Surf, then Waterfall): " .. said)
  end

  L.finish("gen3_nav_gaps")
end
