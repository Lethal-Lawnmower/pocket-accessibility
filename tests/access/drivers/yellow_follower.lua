-- Yellow's following Pikachu and navigation: with the starter Pikachu in the
-- party it follows the player.  Auto-walk out to a target and straight back
-- (the route back starts through the cell Pikachu stands on), list Pikachu
-- in the objects, auto-walk to it and talk to it.  Run silently with
-- POKEPORT_VERSION=yellow and a disposable Yellow identity.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Speech = require("src.access.Speech")
  local AutoWalk = require("src.access.nav.AutoWalk")
  local PikachuFollower = require("src.world.PikachuFollower")
  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  local save = game.save
  save.flags.EVENT_GOT_STARTER = true
  save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  save.pikachuInBall = false
  local pikachu = Pokemon.new(game.data, "PIKACHU", 50)
  pikachu.otId, pikachu.ot = save.player.id, save.player.name
  local mewtwo = Pokemon.new(game.data, "MEWTWO", 100)
  mewtwo.moves[1] = { id = "PSYCHIC_M", pp = 10 }
  -- Mewtwo leads so battles end quickly; the starter only has to be in the party
  save.party = { mewtwo, pikachu }
  game.speedOverride = 4

  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts) said[#said + 1] = tostring(text) return say(text, opts) end
  local function heard() local s = table.concat(said, " | ") said = {} return s end
  local function nav() return package.loaded["src.access.nav"].coordinator() end
  local function waitTransition()
    for _ = 1, 240 do if not game.overworld.transitioning then break end U.wait(1) end
  end
  local function settle()
    for _ = 1, 200 do
      if game.stack:top() == game.overworld then return end
      U.tap(game, "a") U.wait(4)
    end
  end
  local function find(text)
    for _, item in ipairs(nav():captureWorld("all").browse or {}) do
      if tostring(item.label):find(text, 1, true) then return item end
    end
  end
  local function follower()
    local npc = PikachuFollower.current(game.overworld)
    return npc and (npc.cellX .. "," .. npc.cellY) or "none"
  end
  local function walkTo(item)
    for _, mon in ipairs({ mewtwo, pikachu }) do
      mon.hp = mon.stats.hp
      for _, mv in ipairs(mon.moves) do mv.pp = (game.data.moves[mv.id] or {}).pp or mv.pp end
    end
    nav().browseFilter, nav().browseSelectionId = "all", item.id
    heard()
    AutoWalk.start(nav(), game)
    for _ = 1, 4000 do
      if not AutoWalk.active() then break end
      if game.stack:top() ~= game.overworld and not AutoWalk.walking() then settle() end
      U.wait(1)
    end
    if AutoWalk.active() then AutoWalk.stop() return "timed out" end
    waitTransition()
    U.wait(10)
    return heard()
  end

  -- Start on a map's first door, walk to a sign on the same map, then walk
  -- back to that door: the route back starts through Pikachu's cell.
  local function trip(mapId)
    waitTransition()
    local w = game.data.maps[mapId].warps[1]
    U.teleport(game, mapId, w.x, w.y, "down")
    waitTransition()
    U.wait(30)
    settle()
    -- step off the door so Pikachu ends up behind the player
    U.tap(game, "down") U.wait(30)
    local p = game.overworld.player
    local snap = nav():captureWorld("all")
    local sign, door
    for _, item in ipairs(snap.browse or {}) do
      if item.type == "signpost" and not sign then sign = item end
      if item.type == "warp" and item.x == w.x and item.y == w.y then door = item end
    end
    U.log("MAP", mapId, "player", p.cellX .. "," .. p.cellY, "pikachu", follower())
    U.log("RESULT", mapId, "out to", tostring(sign and sign.label), "=>", sign and walkTo(sign) or "no sign",
      "player", p.cellX .. "," .. p.cellY, "pikachu", follower())
    U.log("RESULT", mapId, "back to", tostring(door and door.label), "=>", door and walkTo(door) or "no door",
      "map now", tostring(game.overworld.map.def.id))
  end

  -- trainer-free maps, so no battle interrupts the out-and-back
  save.repelSteps = 9999
  trip("PALLET_TOWN")
  trip("VIRIDIAN_CITY")
  trip("CERULEAN_CITY")

  -- Pikachu in the object list: once it is behind the player, auto-walk to
  -- it (already next to it) and talk to it
  waitTransition()
  local w = game.data.maps.PALLET_TOWN.warps[1]
  U.teleport(game, "PALLET_TOWN", w.x, w.y, "down")
  waitTransition()
  U.wait(30)
  U.tap(game, "down") U.wait(30)
  U.tap(game, "down") U.wait(30)
  local p = game.overworld.player
  local pika = find("Pikachu")
  U.log("RESULT", "Pikachu listed as", tostring(pika and pika.label), "at", pika and (pika.x .. "," .. pika.y) or "-",
    "player", p.cellX .. "," .. p.cellY)
  if pika then
    local arrival = walkTo(pika)
    U.log("RESULT", "walk to Pikachu =>", arrival)
    local face = arrival:match("Face (%a+) and interact")
    if face then U.tap(game, face) U.wait(10) end
    heard()
    U.tap(game, "a") U.wait(120)
    U.log("RESULT", "talk to Pikachu =>", heard())
    settle()
  end
  Speech.say = say
  U.log("DONE")
end
