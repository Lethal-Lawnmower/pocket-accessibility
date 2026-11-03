-- Red, Blue and Yellow: Crystal's auto-walk puzzles on the games' own puzzle maps
-- (decision 41's request for Gen 1).  One auto-walk per case, A in text and battles
-- from the harness, with only what the walk itself does.  Harness setup teleports,
-- gives a party, badges and flags.  Silent; read the RESULT lines.
--   PUZZLE_CASES limits the cases ("seafoam vr1 vr2 vr3 wardens mansion surge cut surf").
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Speech = require("src.access.Speech")
  local AutoWalk = require("src.access.nav.AutoWalk")
  local BoulderWalk = require("src.access.nav.BoulderWalk")
  local SwitchWalk = require("src.access.nav.SwitchWalk")
  local Nav = require("src.access.nav")
  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  local save = game.save
  local mon = Pokemon.new(game.data, "MEWTWO", 100)
  mon.moves = { { id = "PSYCHIC_M", pp = 10 }, { id = "CUT", pp = 30 }, { id = "SURF", pp = 15 }, { id = "STRENGTH", pp = 15 } }
  if not game.data.moves.PSYCHIC_M then mon.moves[1].id = "PSYCHIC" end
  save.party = { mon }
  for _, badge in ipairs({ "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE",
      "VOLCANOBADGE", "EARTHBADGE" }) do
    save.inventory[badge] = 1
  end
  save.repelSteps = 99999
  game.speedOverride = 4

  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts) said[#said + 1] = tostring(text) return say(text, opts) end
  local function heard() local s = table.concat(said, " | ") said = {} return s end
  local function nav() return Nav.coordinator() end
  local function where()
    local p = game.overworld.player
    return tostring(game.overworld.map.id) .. " " .. p.cellX .. "," .. p.cellY
  end

  local function heal()
    mon.hp, mon.status = mon.stats.hp, nil
    for _, mv in ipairs(mon.moves) do mv.pp = 10 end
  end

  local function settle(frames)
    for _ = 1, frames or 300 do
      if game.stack:top() == game.overworld then return true end
      U.tap(game, "a") U.wait(4)
    end
    return game.stack:top() == game.overworld
  end

  local function teleport(mapId, x, y)
    for _ = 1, 240 do if not game.overworld.transitioning then break end U.wait(1) end
    U.teleport(game, mapId, x, y, "down")
    for _ = 1, 240 do if not game.overworld.transitioning then break end U.wait(1) end
    U.wait(10)
    settle()
    heal()
  end

  local function find(filter, text)
    local snap = nav():captureWorld(filter)
    for _, item in ipairs(snap and snap.browse or {}) do
      if tostring(item.label):find(text, 1, true) then return item end
    end
  end

  local function list(filter)
    local names = {}
    local snap = nav():captureWorld(filter)
    for _, item in ipairs(snap and snap.browse or {}) do names[#names + 1] = item.description or item.label end
    return table.concat(names, " ; ")
  end

  -- Starts auto-walk to the item and follows it, pressing A through text and battles
  -- as a player would, without touching any walk's own presses.
  local function walk(item, limit)
    local coordinator = nav()
    coordinator.browseFilter, coordinator.browseSelectionId = "all", item.id
    heard()
    AutoWalk.start(coordinator, game)
    for frame = 1, limit or 40000 do
      if not (AutoWalk.active() or BoulderWalk.active() or SwitchWalk.active()) then break end
      local top = game.stack:top()
      if frame % 900 == 0 then heal() end
      local helper = BoulderWalk.active() and BoulderWalk._state().phase or SwitchWalk.active() and SwitchWalk._state().phase
      if top ~= game.overworld and frame % 8 == 0 and helper ~= "strength" and helper ~= "flipping" and helper ~= "settling" then
        U.tap(game, "a")
      end
      U.wait(1)
    end
    local running = AutoWalk.active() or BoulderWalk.active() or SwitchWalk.active()
    if running then
      BoulderWalk.stop() SwitchWalk.stop() AutoWalk.stop()
      return "TIMED OUT " .. heard():sub(-200)
    end
    for _ = 1, 120 do if not game.overworld.transitioning then break end U.wait(1) end
    return heard():sub(-300)
  end

  local function boulderPlaces()
    local cells = {}
    for _, entity in ipairs(game.overworld.entities or {}) do
      if type(entity.def) == "table" and require("src.world.Map").isPushable(entity.def) then
        cells[#cells + 1] = entity.cellX .. "," .. entity.cellY
      end
    end
    return table.concat(cells, " ")
  end

  local only = os.getenv("PUZZLE_CASES")
  local function case(name, fn)
    if only and not only:find(name, 1, true) then return end
    local ok, err = pcall(fn)
    if not ok then U.log("FAIL", name, tostring(err)) end
  end

  local function floorCase(name, mapId, startX, startY, label)
    case(name, function()
      teleport(mapId, startX, startY)
      U.log("RESULT", name, "list", list("objects"):sub(1, 500))
      U.log("RESULT", name, "boulders", boulderPlaces())
      local item = find("objects", label)
      if not item then U.log("FAIL", name, "no " .. label) return end
      local outcome = walk(item)
      U.log("RESULT", name, "=>", outcome, "| at", where(), "| boulders", boulderPlaces())
      U.log("RESULT", name, "after", list("objects"):sub(1, 500))
    end)
  end

  -- Seafoam, from the top: each floor's holes filled
  for _, floor in ipairs({
    { "seafoam1", "SEAFOAM_ISLANDS_1F", "Hole 1" }, { "seafoamb1", "SEAFOAM_ISLANDS_B1F", "Hole 1" },
    { "seafoamb2", "SEAFOAM_ISLANDS_B2F", "Hole 1" }, { "seafoamb3", "SEAFOAM_ISLANDS_B3F", "Hole 1" },
  }) do
    case(floor[1], function()
      for index, warp in ipairs(game.data.maps[floor[2]].warps) do
        teleport(floor[2], warp.x, warp.y)
        local item = find("objects", floor[3])
        U.log("RESULT", floor[1], "from warp", index, "boulders", boulderPlaces(), "list", list("objects"):sub(1, 300))
        if item then
          local outcome = walk(item)
          U.log("RESULT", floor[1], "from warp", index, "=>", outcome, "| at", where(), "| boulders", boulderPlaces())
          if outcome:find("all in place", 1, true) then break end
        end
      end
    end)
  end

  -- Victory Road: each floor's switches
  local function vr(name, mapId, label)
    case(name, function()
      for index, warp in ipairs(game.data.maps[mapId].warps) do
        teleport(mapId, warp.x, warp.y)
        local item = find("objects", label)
        U.log("RESULT", name, "from warp", index, "boulders", boulderPlaces())
        if not item then U.log("FAIL", name, "no " .. label) return end
        local outcome = walk(item)
        U.log("RESULT", name, "from warp", index, "=>", outcome, "| at", where(), "| boulders", boulderPlaces(),
          "flags", tostring(save.flags.EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH),
          tostring(save.flags.EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1), tostring(save.flags.EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH2),
          tostring(save.flags.EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH1), tostring(save.flags.EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH2))
        if outcome:find("all in place", 1, true) then break end
      end
    end)
  end
  vr("vr1", "VICTORY_ROAD_1F", "Pressure Switch")
  vr("vr3", "VICTORY_ROAD_3F", "Pressure Switch")
  vr("vr2", "VICTORY_ROAD_2F", "Pressure Switch")

  -- targets only boulders block
  case("vrtarget", function()
    save.flags.EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH = nil
    local warp = game.data.maps.VICTORY_ROAD_1F.warps[1]
    teleport("VICTORY_ROAD_1F", warp.x, warp.y)
    local item = find("objects", "Rare Candy")
    if not item then U.log("FAIL", "vrtarget", "no Rare Candy", list("objects")) return end
    U.log("RESULT", "vrtarget", "=>", walk(item), "| at", where())
  end)
  floorCase("wardens", "WARDENS_HOUSE", game.data.maps.WARDENS_HOUSE.warps[1].x, game.data.maps.WARDENS_HOUSE.warps[1].y, "Rare Candy")

  -- Mansion: targets behind gates, tried by flipping
  for _, target in ipairs({
    { "mansion2", "POKEMON_MANSION_2F", "Diary 2" }, { "mansionb1", "POKEMON_MANSION_B1F", "Secret Key" },
    { "mansionb1s", "POKEMON_MANSION_B1F", "Solarbeam" },
  }) do
    case(target[1], function()
      save.flags.EVENT_MANSION_SWITCH_ON = nil
      local warp = game.data.maps[target[2]].warps[1]
      teleport(target[2], warp.x, warp.y)
      local item = find("all", target[3])
      if not item then U.log("FAIL", target[1], "no " .. target[3], list("all")) return end
      U.log("RESULT", target[1], "=>", walk(item), "| at", where(), "| switch", tostring(save.flags.EVENT_MANSION_SWITCH_ON))
    end)
  end

  -- Lt. Surge: one auto-walk from the door
  case("surge", function()
    save.flags.EVENT_1ST_LOCK_OPENED, save.flags.EVENT_2ND_LOCK_OPENED = nil, nil
    save.trashPuzzle = nil
    local warp = game.data.maps.VERMILION_GYM.warps[1]
    teleport("VERMILION_GYM", warp.x, warp.y - 1)
    local item = find("npcs", "Surge")
    if not item then U.log("FAIL", "surge", "no Surge", list("all")) return end
    local outcome = walk(item, 400000)
    U.log("RESULT", "surge", "=>", outcome, "| at", where(), "| locks", tostring(save.flags.EVENT_1ST_LOCK_OPENED),
      tostring(save.flags.EVENT_2ND_LOCK_OPENED))
  end)

  -- Cut and Surf on a walk
  case("cut", function()
    -- Vermilion Gym's door is behind a Cut tree
    local warp = game.data.maps.VERMILION_CITY.warps[1]
    teleport("VERMILION_CITY", warp.x, warp.y + 1)
    local item = find("warps", "Vermilion Gym")
    if not item then U.log("FAIL", "cut", "no gym door", list("warps")) return end
    U.log("RESULT", "cut", "=>", walk(item), "| at", where())
  end)
  case("surf", function()
    teleport("PALLET_TOWN", 5, 16)
    local item = find("connections", "South")
    if not item then U.log("FAIL", "surf", "no south connection", list("all")) return end
    U.log("RESULT", "surf", "=>", walk(item), "| at", where(), "| surfing", tostring(game.overworld.player.surfing))
  end)

  Speech.say = say
  U.log("DONE")
end
