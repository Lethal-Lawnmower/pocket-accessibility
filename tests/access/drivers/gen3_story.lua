-- FireRed's story places by one auto-walk each, as a player reaches them from the
-- object list (and the Area list for other floors).  GEN3_STORY_PARTS limits the parts:
--   A  every multi-floor area: the Area list has its floors, and a journey is planned
--      from the first floor to each (no walking)
--   B  Rocket Hideout, Silph Co., Pokemon Tower, Mansion, Saffron and Viridian Gyms and
--      the other gym leaders
--   C  Seafoam and Victory Road through their puzzles, and on to Indigo Plateau
--   D  the Sevii Islands
-- Harness setup (party, badges, items, flags, teleports) goes through the game's own
-- loader, party and flag store; battles by the harness.  Silent; RESULT lines.
return function(game)
  local L = dofile("tests/access/drivers/gen3_nav_lib.lua").new(game)
  local U, AutoWalk = L.U, L.AutoWalk
  local BoulderWalk = require("src.access.nav.BoulderWalk")
  local SwitchWalk = require("src.access.nav.SwitchWalk")
  if not L.boot() then return end
  L.giveParty(9, 90, { "SURF", "STRENGTH", "CUT" }, { "SURF", "STRENGTH", "CUT", "WATERFALL", "ROCK_SMASH", "FLASH" })
  do
    -- the other field moves on a second Pokemon (four slots each)
    local s = L.session()
    local Party = require("src.core.game3.party")
    local FieldMoves = require("src.core.game3.field_moves")
    Party.giveMon(s, 6, 90)
    local mon = s.party[2]
    mon.moves = { FieldMoves.MOVES.ROCK_SMASH, FieldMoves.MOVES.WATERFALL, FieldMoves.MOVES.FLASH }
    mon.pp, mon.maxPp = { 30, 30, 30 }, { 30, 30, 30 }
  end
  game.options.firered = game.options.firered or {}
  game.options.firered.accessAutoWalkSpeed = 8
  local maps = game.data.maps
  local World = require("src.access.nav.gen3.World")
  local nav = L.nav()
  local areaKey = nav.areaKey
  local only = os.getenv("GEN3_STORY_PARTS")
  local function part(letter) return not only or only == "" or only:find(letter, 1, true) ~= nil end

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
    local x, y = entry(mapId, warpIndex)
    L.heal()
    L.teleport(mapId, x, y, "down")
    L.settle(120, true)
    return L.where()
  end

  -- Every puzzle or walk the one command started, to its end, with the harness in
  -- battles and through text the walk waits on.
  local function run(limit)
    for frame = 1, limit or 30000 do
      if not (AutoWalk.active() or BoulderWalk.active() or SwitchWalk.active()) then return true end
      if frame % 900 == 0 then L.heal() end
      local boulders, switches = BoulderWalk._state(), SwitchWalk._state()
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
    BoulderWalk.stop() SwitchWalk.stop() AutoWalk.stop()
    U.log("FAIL", "still going at the limit", L.where())
    return false
  end

  -- One auto-walk to the first item of `filter` whose label matches; `reachedMap`, when
  -- given, is what must be true after it.
  local function walk(name, filter, pattern, reachedMap)
    local item = L.findLabel(pattern, filter)
    if not item then
      local labels = {}
      for _, candidate in ipairs(L.browse(filter)) do labels[#labels + 1] = tostring(candidate.label) end
      U.log("FAIL", name, "not listed:", pattern, "in", filter, "at", L.where(), table.concat(labels, "; "):sub(1, 500))
      return false
    end
    L.select(item, filter)
    L.heard()
    AutoWalk.start(L.nav(), game, L.adapter())
    run()
    local said = L.heard()
    local mapId = L.pos()
    local ok = not reachedMap or mapId == reachedMap
    U.log(ok and "RESULT" or "FAIL", name, "->", L.where(), "|", said:sub(-120))
    return ok
  end

  if part("A") then
    -- areas of floors: maps sharing a key, cities and routes left out of the walk count
    local groups = {}
    for id in pairs(maps) do
      if id:match("^FR_") then
        local key = areaKey(id)
        if key then
          groups[key] = groups[key] or {}
          table.insert(groups[key], id)
        end
      end
    end
    local keys = {}
    for key, members in pairs(groups) do if #members > 1 then keys[#keys + 1] = key end end
    table.sort(keys)
    local planned, refused, floorsListed = 0, 0, 0
    for _, key in ipairs(keys) do
      table.sort(groups[key])
      local first
      for _, id in ipairs(groups[key]) do
        if maps[id].warps and maps[id].warps[1] then first = first or id end
      end
      if first then
        arrive(first)
        local listed = {}
        for _, item in ipairs(L.browse("area")) do
          if item.floorEntry then listed[item.mapId] = item end
        end
        for _, id in ipairs(groups[key]) do
          if id ~= first then
            if listed[id] then floorsListed = floorsListed + 1 else U.log("FAIL", "no Area entry", first, id) end
            local goals = { { x = 0, y = 0 } }
            goals.anywhere = true
            local leg, why = L.nav():regionalNextLeg({ targetMapId = id, targetGoals = goals })
            if leg then
              planned = planned + 1
            else
              refused = refused + 1
              U.log("REFUSED", first, "to", id, tostring(why))
            end
          end
        end
      end
      U.wait(1)
    end
    U.log("RESULT", "areas", #keys, "floor entries listed", floorsListed, "journeys planned", planned, "refused", refused)
  end

  if part("B") then
    L.setFlag(677, true) -- the Lift Key, as gen3_nav_gaps sets it
    -- Rocket Hideout, by Area and by warps
    arrive("FR_ROCKET_HIDEOUT_B1F")
    walk("Hideout B1F to B2F", "area", "B2F$", "FR_ROCKET_HIDEOUT_B2F")
    walk("Hideout B2F to B3F", "area", "B3F$", "FR_ROCKET_HIDEOUT_B3F")
    walk("Hideout B3F to B4F", "area", "B4F$", nil)
    U.log("RESULT", "Hideout labels", (function()
      local labels = {}
      for _, item in ipairs(L.browse("all")) do labels[#labels + 1] = tostring(item.label) end
      return table.concat(labels, "; "):sub(1, 400)
    end)())
    -- Silph Co.
    arrive("FR_SILPH_CO_1F")
    walk("Silph 1F to 5F", "area", "Silph Co%.? 5F$", nil)
    arrive("FR_SILPH_CO_3F")
    U.log("RESULT", "Silph 3F labels", (function()
      local labels = {}
      for _, item in ipairs(L.browse("all")) do labels[#labels + 1] = tostring(item.label) end
      return table.concat(labels, "; "):sub(1, 400)
    end)())
    walk("Silph 3F to 11F", "area", "Silph Co%.? 11F$", nil)
    -- Pokemon Tower
    arrive("FR_POKEMON_TOWER_1F")
    walk("Tower 1F to 7F", "area", "Tower 7F$", nil)
    -- Mansion
    arrive("FR_POKEMON_MANSION_1F")
    walk("Mansion 1F to B1F", "area", "Mansion B1F$", nil)
    -- Gyms
    for _, gym in ipairs({
      { "FR_SAFFRON_CITY_GYM", "Sabrina" }, { "FR_VIRIDIAN_CITY_GYM", "Giovanni" },
      { "FR_CINNABAR_ISLAND_GYM", "Blaine" }, { "FR_FUCHSIA_CITY_GYM", "Koga" },
      { "FR_CELADON_CITY_GYM", "Erika" }, { "FR_CERULEAN_CITY_GYM", "Misty" },
      { "FR_PEWTER_CITY_GYM", "Brock" },
    }) do
      arrive(gym[1])
      local names = {}
      for _, item in ipairs(L.browse("npcs")) do names[#names + 1] = tostring(item.label) end
      U.log("RESULT", gym[1], "people", #names, table.concat(names, "; "):sub(1, 240))
      walk(gym[1] .. " to " .. gym[2], "npcs", gym[2], gym[1])
    end
  end

  if part("C") then
    arrive("FR_SEAFOAM_ISLANDS_1F")
    walk("Seafoam 1F to B1F", "area", "Islands B1F$", nil)
    walk("Seafoam on to B2F", "area", "Islands B2F$", nil)
    walk("Seafoam on to B3F", "area", "Islands B3F$", nil)
    walk("Seafoam on to B4F", "area", "Islands B4F$", nil)
    arrive("FR_VICTORY_ROAD_1F")
    walk("Victory Road 1F to 2F", "area", "Road 2F$", "FR_VICTORY_ROAD_2F")
    walk("Victory Road 2F to 3F", "area", "Road 3F$", "FR_VICTORY_ROAD_3F")
    walk("Victory Road back to 2F", "area", "Road 2F$", nil)
    walk("Victory Road 2F exit", "warps", "Route 23", nil)
  end

  if part("D") then
    for _, spot in ipairs({
      { "FR_ONE_ISLAND_KINDLE_ROAD", "FR_MT_EMBER_EXTERIOR" },
      { "FR_MT_EMBER_EXTERIOR" }, { "FR_MT_EMBER_RUBY_PATH_1F" }, { "FR_FOUR_ISLAND_ICEFALL_CAVE_ENTRANCE" },
      { "FR_FIVE_ISLAND_ROCKET_WAREHOUSE" }, { "FR_FIVE_ISLAND_LOST_CAVE_ENTRANCE" },
      { "FR_SIX_ISLAND_DOTTED_HOLE_1F" }, { "FR_SIX_ISLAND_PATTERN_BUSH" }, { "FR_SIX_ISLAND_ALTERING_CAVE" },
      { "FR_SEVEN_ISLAND_SEVAULT_CANYON_TANOBY_KEY" }, { "FR_SEVEN_ISLAND_TRAINER_TOWER" },
      { "FR_THREE_ISLAND_BERRY_FOREST" },
    }) do
      if maps[spot[1]] and maps[spot[1]].warps and maps[spot[1]].warps[1] then
        arrive(spot[1])
        local labels = {}
        for _, item in ipairs(L.browse("all")) do labels[#labels + 1] = tostring(item.label) end
        local _, x, y = L.pos()
        U.log("RESULT", spot[1], "start", x .. "," .. y, "#", #labels, table.concat(labels, "; "):sub(1, 400))
        -- every target on the floor: route, or what auto-walk would do instead
        local refused = {}
        for _, item in ipairs(L.browse("all")) do
          L.select(item, "all")
          local ok, it, goals = pcall(L.nav().selectedRouteGoals, L.nav())
          if ok and type(goals) == "table" and #goals > 0 and not AutoWalk.routeExists(L.nav(), goals) then
            refused[#refused + 1] = tostring(item.label)
          end
        end
        U.log("RESULT", spot[1], "no route from the entrance:", #refused, table.concat(refused, "; "):sub(1, 400))
      else
        U.log("RESULT", spot[1], "no such map or warp")
      end
    end
  end
  U.log("DONE")
end
