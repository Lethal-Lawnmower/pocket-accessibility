-- Navigation sweep over the places most likely to trip navigation up when
-- finishing Red: Safari Zone (including the Gold Teeth), the Rocket Hideout
-- spinner floors, Silph Co. card-key floors (without and with the Card
-- Key), and the required story spots (gyms, Victory Road, Pokemon Tower).
-- For every warp and item ball (and, in gyms, every person) it teleports to
-- the map's first entrance, auto-walks to the target, wins any battle on the way, and
-- logs one RESULT line: arrived, stopped (with the spoken reason), or no
-- route.  Run with a fresh Red identity; see docs/access/navigation.md.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Speech = require("src.access.Speech")
  local AutoWalk = require("src.access.nav.AutoWalk")

  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  local mewtwo = Pokemon.new(game.data, "MEWTWO", 100)
  mewtwo.moves[1] = { id = "PSYCHIC_M", pp = 10 }
  if not game.data.moves.PSYCHIC_M then mewtwo.moves[1] = { id = "PSYCHIC", pp = 10 } end
  game.save.party = { mewtwo }
  game.speedOverride = 4
  -- SWEEP_SPEED=200 walks with that AUTO-WALK SPEED (decision 26)
  game.save.options.accessAutoWalkSpeed = tonumber(os.getenv("SWEEP_SPEED"))
  -- full HP and PP before every walk, so battles never stall
  local function heal()
    mewtwo.hp, mewtwo.status = mewtwo.stats.hp, nil
    for _, mv in ipairs(mewtwo.moves) do
      local def = game.data.moves[mv.id]
      mv.pp = def and def.pp or mv.pp
    end
  end

  local lastSaid = ""
  local say = Speech.say
  Speech.say = function(text, opts) lastSaid = tostring(text) return say(text, opts) end

  local function nav() return package.loaded["src.access.nav"].coordinator() end

  -- Clears any screen over the map the way a player would: A through text,
  -- YES on choices, FIGHT and the first move in battle.
  local function settle(frames)
    for _ = 1, frames or 600 do
      if game.stack:top() == game.overworld then return true end
      U.tap(game, "a") U.wait(4)
    end
    return game.stack:top() == game.overworld
  end
  local battleFrames = 0

-- Teleports only once any door or staircase transition has finished: a
-- teleport during one leaves the overworld's transitioning flag set and the
-- player frozen, which no real player can cause.
  local function teleport(mapId, x, y)
    for _ = 1, 240 do
      if not game.overworld.transitioning then break end
      U.wait(1)
    end
    U.teleport(game, mapId, x, y, "down")
    for _ = 1, 240 do
      if not game.overworld.transitioning then break end
      U.wait(1)
    end
    if game.overworld.transitioning then U.log("WARN", "transition still running after teleport") end
  end

  local function entrance(mapId, index)
    local def = game.data.maps[mapId]
    local warp = def and def.warps and def.warps[index or 1]
    if not warp then return nil end
    return warp.x, warp.y
  end

  local function targetsOn(mapId, withPeople)
    local x, y = entrance(mapId)
    if not x then return {} end
    teleport(mapId, x, y)
    U.wait(20)
    settle(200)
    local snap = nav() and nav():captureWorld("all")
    local list = {}
    for _, item in ipairs(snap and snap.browse or {}) do
      local isItemBall = item.type == "object" and item.item ~= nil
      local isPerson = withPeople and item.type == "object" and item.item == nil
      if item.type == "warp" or isItemBall or isPerson or tostring(item.label):find("Teeth", 1, true) then
        list[#list + 1] = { id = item.id, label = item.label }
      end
    end
    return list
  end

  local function walkTo(mapId, target, entranceIndex)
    heal()
    local x, y = entrance(mapId, entranceIndex)
    if not x then return "no such entrance" end
    teleport(mapId, x, y)
    U.wait(15)
    settle(200)
    local coordinator = nav()
    if not coordinator then return "no navigation" end
    coordinator.browseFilter, coordinator.browseSelectionId = "all", target.id
    battleFrames = 0
    lastSaid = ""
    AutoWalk.start(coordinator, game)
    if not AutoWalk.active() then return "not started: " .. lastSaid end
    local trace = os.getenv("SWEEP_TRACE") and tostring(target.label):find(os.getenv("SWEEP_TRACE"), 1, true)
    local p = game.overworld.player
    for f = 1, 4000 do
      if not AutoWalk.active() then break end
      if trace and f % 6 == 0 then
        if f == 30 then
          local flags = {}
          for k, v in pairs(game.overworld) do
            if v == true or (type(v) == "table" and k:lower():find("script")) or (type(v) == "number" and k:lower():find("lock|freeze|wait|delay")) then flags[#flags + 1] = k .. "=" .. tostring(v) end
          end
          for k, v in pairs(p) do if v == true then flags[#flags + 1] = "player." .. k end end
          U.log("flags", table.concat(flags, " "))
        end
        U.log("trace", f, p.cellX, p.cellY, tostring(p.moving), tostring(game.input.state.up),
          tostring(game.input.state.down), tostring(game.input.state.left), tostring(game.input.state.right),
          game.stack:top() == game.overworld and "map" or "other")
      end
      if game.stack:top() ~= game.overworld and not AutoWalk.walking() then
        battleFrames = battleFrames + 30
        if battleFrames > 6000 then AutoWalk.stop() return "battle never ended (sweep gave up)" end
        settle(30)
      end
      U.wait(1)
    end
    if AutoWalk.active() then AutoWalk.stop() return "timed out" end
    return lastSaid
  end

  local only = os.getenv("SWEEP_MAPS")
  local plan = {
    { map = "SAFARI_ZONE_WEST" }, { map = "SAFARI_ZONE_CENTER" },
    { map = "ROCKET_HIDEOUT_B2F" }, { map = "ROCKET_HIDEOUT_B3F" },
    { map = "SILPH_CO_5F" }, { map = "SILPH_CO_7F" },
    { map = "SILPH_CO_5F", cardKey = true }, { map = "SILPH_CO_7F", cardKey = true },
    -- required story spots (gyms target their trainers, leader included)
    { map = "VIRIDIAN_GYM", people = true }, { map = "VERMILION_GYM", people = true },
    { map = "SAFFRON_GYM", people = true }, { map = "CINNABAR_GYM", people = true },
    { map = "VICTORY_ROAD_1F" }, { map = "VICTORY_ROAD_2F" }, { map = "VICTORY_ROAD_3F" },
    { map = "POKEMON_TOWER_5F" }, { map = "POKEMON_TOWER_7F", people = true },
  }
  local arrived, total = 0, 0
  for _, step in ipairs(plan) do
    if only and not only:find(step.map, 1, true) then goto continue end
    game.save.inventory.CARD_KEY = step.cardKey and 1 or nil
    local targets = targetsOn(step.map, step.people)
    U.log("MAP", step.map, step.cardKey and "(with Card Key)" or "", #targets .. " targets")
    for _, target in ipairs(targets) do
      local outcome = walkTo(step.map, target)
      if outcome:find("no path", 1, true) or outcome:find("No route to", 1, true) then
        -- unreachable from the first entrance: try the map's other doors
        local warps = game.data.maps[step.map].warps or {}
        for e = 2, #warps do
          local other = walkTo(step.map, target, e)
          if not (other:find("no path", 1, true) or other:find("No route to", 1, true)) then
            outcome = other .. " (from entrance " .. e .. ")"
            break
          end
        end
      end
      total = total + 1
      if outcome:find("^Arrived") or outcome:find(" is here$") then arrived = arrived + 1 end
      U.log("RESULT", step.map, target.label, "=>", outcome)
      if outcome:find("no path", 1, true) or outcome:find("No route to", 1, true)
         or outcome:find("Blocked", 1, true) then
        -- what guided navigation (P) would say from the first entrance
        local x, y = entrance(step.map)
        teleport(step.map, x, y)
        settle(200)
        local coordinator = nav()
        coordinator.browseFilter, coordinator.browseSelectionId = "all", target.id
        lastSaid = ""
        coordinator:handleCommand("describe_route_to_selected_item")
        for _ = 1, 120 do U.wait(1) end
        U.log("GUIDED", step.map, target.label, "=>", lastSaid)
        if coordinator.activeNavigation then coordinator:handleCommand("describe_route_to_selected_item") end
      end
    end
    ::continue::
  end
  U.log("SUMMARY", arrived .. " of " .. total .. " targets reached")
  Speech.say = say
  U.log("DONE")
end
