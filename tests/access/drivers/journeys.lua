-- Scripted run for cross-map journeys to Area targets: auto-walk to the Gold
-- Teeth from Safari Zone Center and to the Card Key from Silph Co. 1F, and
-- start guided navigation to an Area target.  Battles are won, dialogue is
-- confirmed with A, as a player would.  Run silently
-- (POKEPORT_ACCESS_SILENT=1); read the RESULT lines and the speech trace.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Speech = require("src.access.Speech")
  local AutoWalk = require("src.access.nav.AutoWalk")
  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  local mewtwo = Pokemon.new(game.data, "MEWTWO", 100)
  mewtwo.moves[1] = { id = "PSYCHIC_M", pp = 10 }
  game.save.party = { mewtwo }
  game.speedOverride = 4

  local lastSaid = ""
  local say = Speech.say
  Speech.say = function(text, opts) lastSaid = tostring(text) return say(text, opts) end
  local function nav() return package.loaded["src.access.nav"].coordinator() end
  local function heal()
    mewtwo.hp = mewtwo.stats.hp
    for _, mv in ipairs(mewtwo.moves) do mv.pp = (game.data.moves[mv.id] or {}).pp or mv.pp end
  end

  local function teleport(mapId)
    for _ = 1, 240 do if not game.overworld.transitioning then break end U.wait(1) end
    local w = game.data.maps[mapId].warps[1]
    U.teleport(game, mapId, w.x, w.y, "down")
    for _ = 1, 240 do if not game.overworld.transitioning then break end U.wait(1) end
    U.wait(20)
  end

  -- Selects the Area entry whose label contains `text`; returns its label.
  local function selectArea(text)
    local coordinator = nav()
    coordinator.browseFilter = "area"
    local snap = coordinator:captureWorld("area")
    for _, item in ipairs(snap and snap.browse or {}) do
      if tostring(item.label):find(text, 1, true) then
        coordinator.browseSelectionId = item.id
        return item.label, #snap.browse
      end
    end
    return nil, snap and #snap.browse or 0
  end

  local function journey(mapId, text)
    heal()
    teleport(mapId)
    local label, count = selectArea(text)
    U.log("AREA", mapId, count .. " area entries", label or ("no entry matching " .. text))
    if not label then return "not in the Area list" end
    lastSaid = ""
    AutoWalk.start(nav(), game)
    if not AutoWalk.active() then return "not started: " .. lastSaid end
    do
      local w = AutoWalk._state()
      local s1 = w.steps[1]
      U.log("PLAN", "final", tostring(w.final), "steps", #w.steps, "goal", w.goals[1] and (w.goals[1].x .. "," .. w.goals[1].y) or "-",
        "first", s1 and (s1.fromX .. "," .. s1.fromY .. ">" .. s1.direction) or "-", "player", game.overworld.player.cellX .. "," .. game.overworld.player.cellY)
    end
    for f = 1, 12000 do
      if not AutoWalk.active() then break end
      if os.getenv("JOURNEY_ONLY") and f <= 400 and f % 4 == 0 then
        local w = AutoWalk._state()
        U.log("F", f, game.overworld.player.cellX .. "," .. game.overworld.player.cellY,
          "moving", tostring(game.overworld.player.moving), "top", game.stack:top() == game.overworld and "map" or "other",
          "mapSame", tostring(game.overworld.map == w.map), "paused", tostring(w.paused), "await", tostring(w.awaitingMap),
          "steps", #w.steps, "reroutes", tostring(w.reroutes), "trans", tostring(game.overworld.transitioning))
      end
      if game.stack:top() ~= game.overworld and not AutoWalk.walking() then
        U.tap(game, "a") U.wait(4)
      end
      U.wait(1)
    end
    if AutoWalk.active() then AutoWalk.stop() return "timed out on " .. tostring(game.overworld.map.def and game.overworld.map.def.id) end
    return lastSaid .. " (ended on " .. tostring(game.overworld.map.def and game.overworld.map.def.id or "?") .. ")"
  end

  if os.getenv("JOURNEY_ONLY") ~= "silph" then
  U.log("RESULT", "Gold Teeth from Safari Zone Center =>", journey("SAFARI_ZONE_CENTER", "Gold Teeth"))
  end
  U.log("RESULT", "Card Key from Silph Co. 1F =>", journey("SILPH_CO_1F", "Card Key"))

  -- guided navigation (right stick / P) to an Area target starts a journey
  heal()
  teleport("SAFARI_ZONE_CENTER")
  local label = selectArea("Gold Teeth")
  lastSaid = ""
  nav():handleCommand("describe_route_to_selected_item")
  U.wait(60)
  U.log("RESULT", "guided navigation to", tostring(label), "=>", lastSaid,
    nav().activeNavigation and "(navigation active)" or "(not active)")
  nav():handleCommand("describe_route_to_selected_item")
  Speech.say = say
  U.log("DONE")
end
