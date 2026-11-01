-- Follow-up to the required-spots sweep.  Victory Road 1F: solve the boulder
-- switch the way a navigation user would -- select the boulder, read its push
-- hint, auto-walk to it, push the hinted direction, repeat -- then auto-walk to
-- the 2F ladder.  Pokemon Tower 5F and 7F: rerun the walks with the Silph
-- Scope, which the story requires there.  Run silently with a disposable Red
-- identity; read the RESULT lines.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Speech = require("src.access.Speech")
  local AutoWalk = require("src.access.nav.AutoWalk")
  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  local mewtwo = Pokemon.new(game.data, "MEWTWO", 100)
  mewtwo.moves[1] = { id = "PSYCHIC_M", pp = 10 }
  mewtwo.moves[2] = { id = "STRENGTH", pp = 15 }
  game.save.party = { mewtwo }
  game.save.inventory.RAINBOWBADGE = 1
  game.save.inventory.SILPH_SCOPE = 1
  game.speedOverride = 4
  local function heal()
    mewtwo.hp, mewtwo.status = mewtwo.stats.hp, nil
    for _, mv in ipairs(mewtwo.moves) do mv.pp = (game.data.moves[mv.id] or {}).pp or mv.pp end
  end

  local lastSaid = ""
  local say = Speech.say
  Speech.say = function(text, opts) lastSaid = tostring(text) return say(text, opts) end
  local function nav() return package.loaded["src.access.nav"].coordinator() end
  local ow = game.overworld
  local function waitTransition()
    for _ = 1, 240 do if not game.overworld.transitioning then break end U.wait(1) end
  end
  local function settle(frames)
    for _ = 1, frames or 600 do
      if game.stack:top() == game.overworld then return true end
      U.tap(game, "a") U.wait(4)
    end
  end
  local function teleport(mapId)
    waitTransition()
    local w = game.data.maps[mapId].warps[1]
    U.teleport(game, mapId, w.x, w.y, "down")
    waitTransition()
    U.wait(20)
    settle(200)
  end
  local function find(text)
    local snap = nav():captureWorld("all")
    for _, item in ipairs(snap and snap.browse or {}) do
      if tostring(item.label):find(text, 1, true) then return item end
    end
  end
  local function walkTo(item)
    heal()
    local coordinator = nav()
    coordinator.browseFilter, coordinator.browseSelectionId = "all", item.id
    lastSaid = ""
    AutoWalk.start(coordinator, game)
    if not AutoWalk.active() then return "not started: " .. lastSaid end
    local battle = 0
    for _ = 1, 4000 do
      if not AutoWalk.active() then break end
      if game.stack:top() ~= game.overworld and not AutoWalk.walking() then
        battle = battle + 30
        if battle > 6000 then AutoWalk.stop() return "battle never ended (sweep gave up)" end
        settle(30)
      end
      U.wait(1)
    end
    if AutoWalk.active() then AutoWalk.stop() return "timed out" end
    return lastSaid
  end

  -- Victory Road 1F
  teleport("VICTORY_ROAD_1F")
  game.overworld.strengthActive = true
  local switch = find("Pressure Switch")
  U.log("SWITCH", switch and (switch.label .. ": " .. tostring(switch.stateText)) or "not listed")
  for push = 1, 40 do
    -- the boulder whose hint names a switch, as a player would pick it
    local boulder
    for _, item in ipairs(nav():captureWorld("all").browse or {}) do
      if tostring(item.label):find("^Boulder") and tostring(item.stateText):find("^target") then boulder = item break end
    end
    if not boulder then U.log("RESULT", "no boulder listed") break end
    local sw = find("Pressure Switch")
    if sw and tostring(sw.stateText):find("^pressed") then
      U.log("RESULT", "switch pressed after", push - 1, "pushes")
      break
    end
    local hint = tostring(boulder.routeInstruction)
    local dir = hint:match("push (%a+)")
    if not dir then U.log("RESULT", "no push hint:", hint) break end
    local walked = walkTo(boulder)
    if not (walked:find("^Arrived") or walked:find(" is here$")) then U.log("RESULT", "push", push, "could not reach boulder:", walked) break end
    game.overworld.strengthActive = true
    U.log("PUSH", push, boulder.label, "hint", hint, "walk", walked)
    U.tap(game, dir) U.wait(8)
    for _ = 1, 60 do
      if not game.overworld.player.moving then break end
      U.wait(1)
    end
    U.wait(30)
    settle(200)
  end
  local ladder = find("Victory Road 2F")
  U.log("RESULT", "VICTORY_ROAD_1F ladder =>", ladder and walkTo(ladder) or "not listed")
  for _, name in ipairs({ "TM Sky Attack", "Rare Candy" }) do
    local item = find(name)
    U.log("RESULT", "VICTORY_ROAD_1F", name, "=>", item and walkTo(item) or "not listed")
  end

  -- Pokemon Tower with the Silph Scope
  for _, step in ipairs(os.getenv("VRT_TOWER") and { { "POKEMON_TOWER_5F", "Nugget" }, { "POKEMON_TOWER_7F", "Mr. Fuji" } } or {}) do
    teleport(step[1])
    local item = find(step[2])
    U.log("RESULT", step[1], step[2], "=>", item and walkTo(item) or "not listed")
  end
  Speech.say = say
  U.log("DONE")
end
