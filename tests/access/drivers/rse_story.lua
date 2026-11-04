-- Ruby, Sapphire and Emerald's story places by one auto-walk each, as a player reaches
-- them from the object list (and the Area list for other floors).  RSE_STORY_PARTS limits
-- the parts:
--   A  every multi-floor area: the Area list has its floors, and a journey is planned
--      from the first floor to each (no walking)
--   G  every gym, from its door to its leader
--   F  field walks: first route, ledges, Surf, Waterfall, Dive and back, currents
--   H  hideouts, Seafloor Cavern, Victory Road and the other late places
-- Harness setup (party, badges, flags, teleports) goes through the game's own loader,
-- party and flag store; battles by the harness.  Silent; RESULT and FAIL lines.  Nobody
-- hears these runs.
return function(game)
  local L = dofile("tests/access/drivers/rse_nav_lib.lua").new(game)
  local U, AutoWalk = L.U, L.AutoWalk
  local BoulderWalk = require("src.access.nav.BoulderWalk")
  local SwitchWalk = require("src.access.nav.SwitchWalk")
  if not L.boot() then return end
  L.giveParty()
  L.repel()
  L.fastWalk(8)
  local maps = game.data.maps
  local World = require("src.access.nav.gen3.World")
  local nav = L.nav()
  local areaKey = nav.areaKey
  local id = L.id
  local only = os.getenv("RSE_STORY_PARTS")
  local isEmerald = L.GameData.isEmerald()
  local function part(letter) return not only or only == "" or only:find(letter, 1, true) ~= nil end
  local summary = { arrived = 0, failed = 0 }

  -- A cell beside the map's warp (the first by default) that is floor and no warp.
  local function entry(mapId, warpIndex)
    local def = maps[mapId]
    local view = World.loadedView(game, def)
    local warp = def.warps[warpIndex or 1]
    for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
      local x, y = warp.x + d[1], warp.y + d[2]
      if view:isWalkableCell(x, y) and not view:warpAt(x, y) then return x, y end
    end
    return warp.x, warp.y
  end

  local function arrive(mapId, warpIndex)
    if not maps[mapId] then U.log("SKIP", mapId, "not on this cartridge") return false end
    local x, y = entry(mapId, warpIndex)
    L.heal()
    L.teleport(mapId, x, y, "up")
    L.settle(120, true)
    return L.where()
  end

  local function arriveAt(mapId, x, y, facing)
    if not maps[mapId] then U.log("SKIP", mapId, "not on this cartridge") return false end
    L.heal()
    L.teleport(mapId, x, y, facing or "down")
    L.settle(120, true)
    return L.where()
  end

  -- Every puzzle or walk the one command started, to its end, with the harness in
  -- battles and through text the walk waits on.
  local function run(limit)
    local Extra = package.loaded["src.access.nav.IceWalk"]
    for frame = 1, limit or 30000 do
      local extraActive = Extra and Extra.active()
      if not (AutoWalk.active() or BoulderWalk.active() or SwitchWalk.active() or extraActive) then return true end
      if frame % 900 == 0 then L.heal() end
      local boulders, switches = BoulderWalk._state(), SwitchWalk._state()
      local walkNow = AutoWalk._state()
      if walkNow and walkNow.paused and os.getenv("RSE_STORY_TRACE") == "1" then
        local Space = package.loaded["src.core.game3.scripting.space"]
        local vm = Space and Space.vm
        local Field = package.loaded["src.core.game3.field"]
        local Fade = package.loaded["src.ui.game3.fade"]
        local mark = table.concat({ "held", tostring(L.adapter().held(game)), "vm", tostring(vm and vm:isRunning()),
          "script", tostring(vm and (vm.currentKey or vm.key or vm.script)), "locked", tostring(Field and Field.isLocked and Field.isLocked()),
          "hold", tostring(Field and rawget(Field, "_holdInput")), "fade", tostring(Fade and Fade.lockInput),
          "pending", tostring(Space and Space._pendingOnFrame), "at", L.where() }, " ")
        if mark ~= L.lastPause then
          L.lastPause = mark
          U.log("PAUSE", mark)
        end
      end
      if switches and os.getenv("RSE_STORY_TRACE") == "1" then
        local mark = tostring(switches.phase) .. " " .. tostring(switches.sign and switches.sign.label) .. " flips " .. tostring(switches.flips)
        if mark ~= L.lastMark then
          L.lastMark = mark
          local walkState = AutoWalk._state()
          local goals = {}
          for _, goal in ipairs(walkState and walkState.goals or {}) do goals[#goals + 1] = goal.x .. "," .. goal.y end
          U.log("SWITCH", mark, "at", L.where(), "walk goals", table.concat(goals, " "), "steps", L.steps():sub(1, 160))
          if switches.phase == "choose" and os.getenv("RSE_STORY_SHOW") == "1" then L.showFloor(mark) end
        end
      end
      local own = (boulders and (boulders.phase == "strength" or boulders.phase == "settling"))
        or (switches and switches.phase == "flipping")
      if not L.battleStep() then
        if frame % 15 == 0 and not own and L.messageOpen() and not L.free() then
          L.tap("a", 2)
        else
          U.wait(1)
        end
      end
    end
    local stuck = AutoWalk._state()
    U.log("FAIL", "still going at the limit", L.where(), "paused", tostring(stuck and stuck.paused), "still", tostring(stuck and stuck.still), "retry", tostring(stuck and stuck.retryIn), "await", tostring(stuck and stuck.awaitingMap), "held game", tostring(L.adapter().held(game)), "trans", tostring(L.adapter().transitioning()), "goals", tostring(stuck and stuck.goals and stuck.goals[1] and (stuck.goals[1].x .. "," .. stuck.goals[1].y)), "held", tostring(stuck and stuck.held), "steps", L.steps():sub(1, 200),
      "free", tostring(L.free()), "message", tostring(L.messageOpen()),
      "walk", tostring(AutoWalk.active()), "boulders", tostring(BoulderWalk.active()), "switches", tostring(SwitchWalk.active()),
      "boulder phase", tostring(BoulderWalk._state() and BoulderWalk._state().phase), "switch phase", tostring(SwitchWalk._state() and SwitchWalk._state().phase))
    if os.getenv("RSE_STORY_SHOW") == "1" then L.showFloor("limit") end
    BoulderWalk.stop() SwitchWalk.stop() AutoWalk.stop()
    return false
  end

  local function labels(filter)
    local list = {}
    for _, candidate in ipairs(L.browse(filter)) do list[#list + 1] = tostring(candidate.label) end
    return table.concat(list, "; "):sub(1, 700)
  end

  -- One auto-walk to the first item of `filter` whose label matches; `reachedMap`, when
  -- given, is what must be true after it.
  local function walk(name, filter, pattern, reachedMap, limit)
    local item = L.findLabel(pattern, filter)
    if not item then
      summary.failed = summary.failed + 1
      U.log("FAIL", name, "not listed:", pattern, "in", filter, "at", L.where(), labels(filter))
      return false
    end
    L.select(item, filter)
    L.heard()
    AutoWalk.start(L.nav(), game, L.adapter())
    run(limit)
    local said = L.heard()
    local mapId = L.pos()
    local ok = not reachedMap or mapId == reachedMap
    if ok and not reachedMap then ok = said:find("Arrived", 1, true) ~= nil or said:find(" is here", 1, true) ~= nil end
    summary[ok and "arrived" or "failed"] = summary[ok and "arrived" or "failed"] + 1
    U.log(ok and "RESULT" or "FAIL", name, "->", L.where(), "|", said:sub(-160))
    if not ok and os.getenv("RSE_STORY_SHOW") == "1" then
      L.showFloor(name)
      local world = nav:worldState()
      local selected = nav:selectedRouteGoals()
      if type(selected) == "table" then
        local goals = nav:journeyOpeningGoals(selected, world)
        local cells = {}
        for _, goal in ipairs(goals or {}) do cells[#cells + 1] = goal.x .. "," .. goal.y end
        local ok, plan, why = pcall(nav.boulderOpening, nav, world, goals or {})
        U.log("OPENING", tostring(selected.label), "goals", table.concat(cells, " "), tostring(ok), tostring(plan and plan.direction), tostring(why))
      end
      local rows = {}
      for _, actor in ipairs(world.npcs) do rows[#rows + 1] = tostring(actor.graphicsId) .. "@" .. actor.cellX .. "," .. actor.cellY end
      U.log("ACTORS", table.concat(rows, " "))
      for _, sign in ipairs(nav:switchSigns(world)) do
        local options = nav:routeOptionsFor(world, sign.goals, 2)
        local found = options and require("src.access.nav.Pathfinder").find(options)
        local leg, why = nav:regionalNextLeg({ targetMapId = L.pos(), targetGoals = sign.goals })
        U.log("SIGN", sign.label, "route", tostring(found ~= nil), "leg", tostring(leg ~= nil), tostring(why))
      end
    end
    return ok
  end

  if part("A") then
    local groups = {}
    for _, mapId in ipairs(L.mapIds()) do
      local key = areaKey(mapId)
      if key then
        groups[key] = groups[key] or {}
        table.insert(groups[key], mapId)
      end
    end
    local keys = {}
    for key, members in pairs(groups) do if #members > 1 then keys[#keys + 1] = key end end
    table.sort(keys)
    local planned, refused, floorsListed = 0, 0, 0
    for _, key in ipairs(keys) do
      table.sort(groups[key])
      local first
      for _, mapId in ipairs(groups[key]) do
        if maps[mapId].warps and maps[mapId].warps[1] then first = first or mapId end
      end
      if first and not key:match("^BATTLE_") then -- (their load scripts need a challenge under way)
        arrive(first)
        local listed = {}
        for _, item in ipairs(L.browse("area")) do
          if item.floorEntry then listed[item.mapId] = item end
        end
        for _, mapId in ipairs(groups[key]) do
          if mapId ~= first then
            if listed[mapId] then floorsListed = floorsListed + 1 else U.log("FAIL", "no Area entry", first, mapId) end
            local goals = { { x = 0, y = 0 } }
            goals.anywhere = true
            local leg, why = L.nav():regionalNextLeg({ targetMapId = mapId, targetGoals = goals })
            if leg then
              planned = planned + 1
            else
              refused = refused + 1
              U.log("REFUSED", first, "to", mapId, tostring(why))
            end
          end
        end
      end
      U.wait(1)
    end
    U.log("RESULT", "areas", #keys, "floor entries listed", floorsListed, "journeys planned", planned, "refused", refused)
  end

  if part("G") then
    local gyms = {
      { "RUSTBORO_CITY_GYM", "Roxanne" }, { "DEWFORD_TOWN_GYM", "Brawly" }, { "MAUVILLE_CITY_GYM", "Wattson" },
      { "LAVARIDGE_TOWN_GYM_1F", "Flannery" }, { "PETALBURG_CITY_GYM", "Norman" }, { "FORTREE_CITY_GYM", "Winona" },
      { "MOSSDEEP_CITY_GYM", isEmerald and "Tate" or "Liza" }, { "SOOTOPOLIS_CITY_GYM_1F", isEmerald and "Juan" or "Wallace" },
    }
    local onlyGyms = os.getenv("RSE_STORY_GYMS")
    for _, row in ipairs(gyms) do
      local mapId = id(row[1])
      -- a leader the story has not brought back yet (Ruby and Sapphire's Wallace)
      for _, object in ipairs(maps[mapId] and maps[mapId].objects or {}) do
        local flag = tonumber(object.flag) or 0
        local name = require("src.access.nav.gen3.WorldSnapshot").objectLabel({ def = object, graphicsId = object.graphicsId }, {})
        if flag > 0 and name == row[2] then L.setFlag(flag, false) end
      end
      if (not onlyGyms or onlyGyms:find(row[2], 1, true)) and arrive(mapId) then
        U.log("GYM", mapId, "listed:", labels("npcs"))
        if os.getenv("RSE_STORY_TRACE") == "1" then
          local world = nav:worldState()
          local target = L.findLabel(row[2], "npcs")
          L.select(target, "npcs")
          local _, goals = nav:selectedRouteGoals()
          local started = os.clock()
          local ok, plan, why = pcall(nav.rotatingSwitchPlan, nav, world, goals)
          U.log("PLAN", tostring(ok), tostring(plan), tostring(why), os.clock() - started)
        end
        walk("gym " .. row[1] .. " to " .. row[2], "npcs", row[2], nil, tonumber(os.getenv("RSE_STORY_LIMIT")) or 40000)
      end
    end
  end

  if part("F") then
    arriveAt(id("ROUTE101"), 10, 15)
    if walk("Route 101 to Oldale's edge", "connections", "Oldale", nil) then
      L.hold("up", 30)
      L.settle(200, true)
      local Collision = require("src.core.game3.collision")
      local Player = require("src.core.game3.player")
      U.log("NOTE", "after hold", L.where(), "facing", Player.facing, "moving", tostring(Player.moving), "free", tostring(L.free()),
        "conn", tostring(pcall(Collision.tryConnection, game, Player.cellX, Player.cellY, "up", false)))
      L.settle(100, true)
    end
    U.log(L.pos() ~= id("ROUTE101") and "RESULT" or "FAIL", "crossed to", L.where())
    arriveAt(id("OLDALE_TOWN"), 11, 18)
    walk("Oldale to its Center", "warps", "Pok..?mon Center", id("OLDALE_TOWN_POKEMON_CENTER_1F"))
    arriveAt(id("ROUTE124"), 70, 49)
    walk("Route 124 to its seabed", "area", "Underwater Route 124", nil)
    U.log("RESULT", "stopped at", L.where())
    -- the game's own question, as a player answers it
    L.tap("a", 20)
    L.settle(1500, "a")
    U.log(L.pos() ~= id("ROUTE124") and "RESULT" or "FAIL", "dived", L.where(), L.heard():sub(-160))
    walk("Back to the surface", "area", "Route 124$", nil)
    L.tap("b", 20)
    L.settle(1500, "a")
    U.log(L.pos() == id("ROUTE124") and "RESULT" or "FAIL", "surfaced", L.where(), L.heard():sub(-160))
    -- Surf over a current and up a waterfall
    -- Surf from the shore, across a route to its far edge
    arriveAt(id("ROUTE124"), 70, 49)
    walk("Route 124 surf to Route 126's edge", "connections", "Route 126", nil)
  end

  if part("H") then
    -- Harness flags that open what the story opens: read from this cartridge's names.
    local function setFlagByName(name)
      local flag = L.GameData.flag(name)
      if flag then L.setFlag(flag, true) else U.log("NOTE", "no flag", name) end
    end
    setFlagByName("FLAG_LANDMARK_SEAFLOOR_CAVERN")
    setFlagByName("FLAG_SYS_USE_FLASH")
    local function area(title, start, pattern, reached, warpIndex)
      if not maps[id(start)] then return end
      local onlyPlaces = os.getenv("RSE_STORY_PLACES")
      if onlyPlaces and not onlyPlaces:find(start, 1, true) then return end
      if arrive(id(start), warpIndex) then
        -- a warp in the water is reached surfing
        local Player = require("src.core.game3.player")
        local view = nav:worldState().map
        if view:isWater(Player.cellX, Player.cellY) then Player.surfing = true end
        -- every map load clears Flash, as it does for a player
        setFlagByName("FLAG_SYS_USE_FLASH")
        walk(title, "area", pattern, reached and id(reached) or nil, 60000)
      end
    end
    area("Granite Cave 1F to B1F", "GRANITE_CAVE_1F", "B1F$", "GRANITE_CAVE_B1F")
    area("Mt. Pyre 1F to 2F", "MT_PYRE_1F", "Mt%. Pyre 2F$", "MT_PYRE_2F")
    area("Mt. Pyre 2F to 3F", "MT_PYRE_2F", "Mt%. Pyre 3F$", "MT_PYRE_3F")
    area("Mt. Pyre 5F to 6F", "MT_PYRE_5F", "Mt%. Pyre 6F$", "MT_PYRE_6F")
    if isEmerald then
      area("Magma Hideout 1F to 4F", "MAGMA_HIDEOUT_1F", "Magma Hideout 4F$", "MAGMA_HIDEOUT_4F")
    else
      area("Magma Hideout 1F to B2F", "MAGMA_HIDEOUT_1F", "Magma Hideout B2F$", "MAGMA_HIDEOUT_B2F")
    end
    area("Aqua Hideout 1F to B2F", "AQUA_HIDEOUT_1F", "Aqua Hideout B2F$", "AQUA_HIDEOUT_B2F")
    area("Seafloor Cavern entrance to Room 1", "SEAFLOOR_CAVERN_ENTRANCE", "Room 1$", "SEAFLOOR_CAVERN_ROOM1")
    area("Seafloor Cavern Room 1 to Room 9", "SEAFLOOR_CAVERN_ROOM1", "Room 9$", "SEAFLOOR_CAVERN_ROOM9")
    area("Victory Road 1F to B1F", "VICTORY_ROAD_1F", "B1F$", "VICTORY_ROAD_B1F")
    area("Victory Road B1F to B2F", "VICTORY_ROAD_B1F", "B2F$", "VICTORY_ROAD_B2F")
    area("Meteor Falls 1F to B1F", "METEOR_FALLS_1F_1R", "B1F 1[Rr]$", "METEOR_FALLS_B1F_1R")
    area("New Mauville entrance to inside", "NEW_MAUVILLE_ENTRANCE", "Inside$", "NEW_MAUVILLE_INSIDE")
    area("Abandoned Ship deck to corridors", "ABANDONED_SHIP_DECK", "Corridors 1F$", "ABANDONED_SHIP_CORRIDORS_1F")
    area("Weather Institute 1F to 2F", "ROUTE119_WEATHER_INSTITUTE_1F", "2F$", "ROUTE119_WEATHER_INSTITUTE_2F")
    area("Space Center 1F to 2F", "MOSSDEEP_CITY_SPACE_CENTER_1F", "Space Center 2F$", "MOSSDEEP_CITY_SPACE_CENTER_2F")
    area("Safari Zone South to Southwest", "SAFARI_ZONE_SOUTH", "Southwest$", "SAFARI_ZONE_SOUTHWEST")
    area("Shoal Cave entrance to Ice Room", "SHOAL_CAVE_LOW_TIDE_ENTRANCE_ROOM", "Ice Room$", "SHOAL_CAVE_LOW_TIDE_ICE_ROOM")
    -- the Trick House's rooms, each to its scroll
    -- (5 is the Mechadolls' quiz, a script that holds the player: not a walk)
    for _, number in ipairs({ 1, 2, 3, 4, 6, 7, 8 }) do
      local name = "ROUTE110_TRICK_HOUSE_PUZZLE" .. number
      local onlyList = os.getenv("RSE_STORY_PLACES")
      if maps[id(name)] and (not onlyList or onlyList:find(name, 1, true)) and arrive(id(name)) then
        walk("Trick House " .. number .. " to the scroll", "signposts", "Secret Scroll", nil, 40000)
      end
    end
    -- Sky Pillar: on foot the cracked floors refuse; on the Mach Bike they are ridden.  The
    -- floors crack in the story (VAR_SKY_PILLAR_STATE); its value is set here
    local onlyPlaces = os.getenv("RSE_STORY_PLACES")
    if maps[id("SKY_PILLAR_2F")] and not onlyPlaces then
      local stateVar = L.GameData.var("VAR_SKY_PILLAR_STATE")
      if stateVar then L.setVar(stateVar, 2) end
      arrive(id("SKY_PILLAR_2F"))
      L.showFloor("Sky Pillar 2F")
      walk("Sky Pillar 2F to 3F on foot", "area", "Sky Pillar 3F$", nil)
      arrive(id("SKY_PILLAR_2F"))
      local Bike = require("src.core.game3.bike")
      local rse = Bike.rse()
      local okMount, mountErr = pcall(function() rse.getOnOff("mach") end)
      U.log("NOTE", "mounted", tostring(okMount), tostring(mountErr), tostring(require("src.core.game3.player").bikeType))
      do
        local world = nav:worldState()
        local goals = {}
        for _, warp in ipairs(maps[id("SKY_PILLAR_2F")].warps) do
          if warp.destMap == id("SKY_PILLAR_3F") then goals[#goals + 1] = { x = warp.x, y = warp.y } end
        end
        local result, why = nav:machRoute(world, goals)
        U.log("NOTE", "mach route", tostring(result and #result.steps), tostring(why), "on bike", tostring(nav:onMachBike()), "facing", tostring(world.player.facing))
        local anywhere = { { x = 0, y = 0 } }
        anywhere.anywhere = true
        local leg, legWhy = nav:regionalNextLeg({ targetMapId = id("SKY_PILLAR_3F"), targetGoals = anywhere })
        U.log("NOTE", "leg", tostring(leg and leg.final), tostring(legWhy), "area", tostring(nav.areaKey(id("SKY_PILLAR_3F"))), tostring(nav.areaKey(id("SKY_PILLAR_2F"))))
      end
      walk("Sky Pillar 2F to 3F on the Mach Bike", "area", "Sky Pillar 3F$", id("SKY_PILLAR_3F"))
      pcall(function() rse.getOnOff("mach") end)
    end
    -- Sootopolis's crater by Dive, from Route 126
    arriveAt(maps[id("UNDERWATER_ROUTE126")] and id("UNDERWATER_ROUTE126") or id("UNDERWATER2"), 45, 67, "up")
    walk("Underwater Route 126 into the crater", "warps", "Sootopolis", id("UNDERWATER_SOOTOPOLIS_CITY"))
    -- the clock
    L.heard()
    nav:handleCommand("read_game_time")
    U.log("RESULT", "Q says", L.heard())
  end

  if part("L") then
    -- People whose sprite a variable decides: what the live list says on those maps
    for _, name in ipairs({ "LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", "LITTLEROOT_TOWN_MAYS_HOUSE_2F", "CONTEST_HALL",
        "LILYCOVE_CITY_POKEMON_CENTER_1F", "MAUVILLE_CITY_POKEMON_CENTER_1F", "SECRET_BASE_RED_CAVE1",
        "SLATEPORT_CITY_BATTLE_TENT_BATTLE_ROOM", "LILYCOVE_CITY" }) do
      if maps[id(name)] and maps[id(name)].warps and maps[id(name)].warps[1] and arrive(id(name)) then
        local persons, total = 0, 0
        for _, item in ipairs(L.browse("all")) do
          if item.type == "object" then
            total = total + 1
            if item.label == "Person" then persons = persons + 1 end
          end
        end
        U.log("RESULT", "live list", name, "objects", total, "Person", persons)
      end
    end
  end

  U.log("RESULT", "walks arrived", summary.arrived, "failed", summary.failed)
  U.log("DONE")
end
