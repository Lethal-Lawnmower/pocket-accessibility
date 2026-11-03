-- Red, Blue and Yellow: auto-walk to every warp, connection, sign and object on every
-- map, for real.  From a way onto the map that has a route, it walks there and checks the
-- outcome the walk claimed: a warp must change the map to where its label says, nothing
-- else may leave the map, a connection's edge must cross when pressed, and an accidental
-- warp or a stall is reported.  Battles are won by the harness.  Harness setup teleports
-- and gives a party with badges and Repel.  Silent; read the BAD lines and the RESULT line.
--   WALK_MAPS limits the maps, WALK_FROM and WALK_TO a slice of the sorted list.
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
  save.inventory.CARD_KEY = 1
  save.flashLit = true
  -- the story gates of an early save (they turn a walk back, as they should)
  for _, flag in ipairs({ "EVENT_FOLLOWED_OAK_INTO_LAB", "EVENT_GOT_POKEDEX", "EVENT_OAK_GOT_PARCEL", "EVENT_BEAT_BROCK",
      "EVENT_BEAT_MISTY", "EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE", "EVENT_BEAT_ROUTE22_RIVAL_2ND_BATTLE", "EVENT_GOT_STARTER",
      "EVENT_BATTLED_RIVAL_IN_OAKS_LAB" }) do
    save.flags[flag] = true
  end
  save.repelSteps = 99999
  save.options.accessAutoWalkBoulders = false -- plain walks here; gen1_puzzles.lua does the puzzles
  game.speedOverride = 4

  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts) said[#said + 1] = tostring(text) return say(text, opts) end
  local function heard() local s = table.concat(said, " | ") said = {} return s end
  local function nav() return Nav.coordinator() end
  local function here() return game.overworld.map.id end

  local function heal()
    mon.hp, mon.status = mon.stats.hp, nil
    for _, mv in ipairs(mon.moves) do mv.pp = 10 end
  end
  local function settle(frames)
    for _ = 1, frames or 200 do
      if game.stack:top() == game.overworld then return true end
      U.tap(game, "a") U.wait(3)
    end
    return game.stack:top() == game.overworld
  end
  local function calm()
    for _ = 1, 240 do if not game.overworld.transitioning then break end U.wait(1) end
  end
  local function teleport(mapId, x, y)
    calm()
    U.teleport(game, mapId, x, y, "down")
    calm()
    U.wait(4)
    settle()
    heal()
    save.flashLit = true
  end
  -- a route from any way onto the map, by moving the player there and asking
  local function entryWithRoute(mapId, coordinator, goals)
    local def = game.data.maps[mapId]
    local player = game.overworld.player
    local list = {}
    for _, warp in ipairs(def.warps or {}) do list[#list + 1] = { warp.x, warp.y } end
    local map = game.overworld.map
    for dir in pairs(def.connections or {}) do
      local w, h = map.widthCells, map.heightCells
      if dir == "north" or dir == "south" then
        local y = dir == "north" and 0 or h - 1
        for x = 0, w - 1 do if map:isWalkableCell(x, y) then list[#list + 1] = { x, y } end end
      else
        local x = dir == "west" and 0 or w - 1
        for y = 0, h - 1 do if map:isWalkableCell(x, y) then list[#list + 1] = { x, y } end end
      end
    end
    local Pathfinder = require("src.access.nav.Pathfinder")
    local homeX, homeY = player.cellX, player.cellY
    local found
    for _, cell in ipairs(list) do
      player.cellX, player.cellY = cell[1], cell[2]
      local options = coordinator:worldRouteRequest(goals, 2)
      local ok, result = false, nil
      if options then ok, result = pcall(Pathfinder.find, options) end
      if ok and result and #result.steps > 0 then found = cell break end
    end
    player.cellX, player.cellY = homeX, homeY
    return found
  end

  local ids = {}
  for id, def in pairs(game.data.maps) do
    if type(def) == "table" and type(def.warps) == "table" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  local only = os.getenv("WALK_MAPS")
  local from, to = tonumber(os.getenv("WALK_FROM")) or 1, tonumber(os.getenv("WALK_TO")) or #ids
  local totals = { walks = 0, ok = 0, bad = 0, noRoute = 0, skipped = 0 }
  local SKIP_MAPS = { COLOSSEUM = true, TRADE_CENTER = true, UNION_ROOM = true }

  local function bad(mapId, item, why)
    totals.bad = totals.bad + 1
    U.log("BAD", mapId, item.type, tostring(item.label), why)
  end

  for index, mapId in ipairs(ids) do
    if index >= from and index <= to and not SKIP_MAPS[mapId] and (not only or only:find(mapId, 1, true)) then
      local def = game.data.maps[mapId]
      local first = def.warps and def.warps[1]
      local entered = pcall(teleport, mapId, first and first.x or 0, first and first.y or 0)
      if not entered or game.stack:top() ~= game.overworld or here() ~= mapId then
        U.log("SKIP", mapId, "did not stay on the map, now", tostring(here()))
        totals.skipped = totals.skipped + 1
      else
        local coordinator = nav()
        local snapshot = coordinator:captureWorld("all")
        local items = {}
        for _, item in ipairs(snapshot and snapshot.browse or {}) do items[#items + 1] = item end
        U.log("MAP", mapId, #items)
        for _, item in ipairs(items) do
          local toMapId = item.destinationMapId
          coordinator = nav()
          -- back on the map and on a cell with a route
          if here() ~= mapId or game.stack:top() ~= game.overworld then teleport(mapId, first and first.x or 0, first and first.y or 0) end
          if here() == mapId and game.stack:top() == game.overworld then
            coordinator.browseFilter, coordinator.browseSelectionId = "all", item.id
            local _, goals = coordinator:selectedRouteGoals()
            local cell = type(goals) == "table" and #goals > 0 and entryWithRoute(mapId, coordinator, goals)
            if not cell then
              totals.noRoute = totals.noRoute + 1
            else
              teleport(mapId, cell[1], cell[2])
              if here() == mapId and game.stack:top() == game.overworld then
                coordinator = nav()
                coordinator.browseFilter, coordinator.browseSelectionId = "all", item.id
                -- a closed door an earlier walk opened, a person gone: no longer a target
                local present = false
                for _, now in ipairs(coordinator:captureWorld("all").browse or {}) do
                  if now.id == item.id then present = true break end
                end
                if not present then goto nextItem end
                heard()
                totals.walks = totals.walks + 1
                AutoWalk.start(coordinator, game)
                local frame = 0
                local trace = os.getenv("WALK_TRACE") and tostring(item.label):find(os.getenv("WALK_TRACE"), 1, true)
                if trace then U.log("TRACE", mapId, item.label, "start", cell[1], cell[2]) end
                local lastTrace
                while frame < 6000 and AutoWalk.active() do
                  frame = frame + 1
                  if trace then
                    local p, st = game.overworld.player, AutoWalk._state()
                    local line = p.cellX .. "," .. p.cellY .. " " .. tostring(p.facing) .. " held " .. tostring(st and st.held)
                      .. " push " .. tostring(st and st.pushDir) .. " top " .. tostring(game.stack:top() == game.overworld)
                    if line ~= lastTrace then U.log("TRACE", frame, line) lastTrace = line end
                  end
                  if frame % 300 == 0 then heal() end
                  if game.stack:top() ~= game.overworld then
                    U.tap(game, "a") U.wait(3)
                  else
                    U.wait(1)
                  end
                end
                local timedOut = AutoWalk.active()
                if timedOut then AutoWalk.stop() end
                -- a door's fade runs after the arrival is said: give the map time to change
                if item.type == "warp" and toMapId ~= mapId then
                  for _ = 1, 150 do
                    if here() ~= mapId then break end
                    U.wait(1)
                  end
                end
                calm()
                settle(100)
                local text = heard()
                local arrived = text:find("Arrived at", 1, true) ~= nil or text:find(" is here", 1, true) ~= nil
                if timedOut then
                  bad(mapId, item, "timed out at " .. game.overworld.player.cellX .. "," .. game.overworld.player.cellY .. " " .. text:sub(-120))
                elseif not arrived then
                  bad(mapId, item, "no arrival: " .. text:sub(-160) .. " | now " .. tostring(here()))
                elseif item.type == "warp" then
                  if toMapId == mapId then
                    totals.ok = totals.ok + 1
                  elseif here() == mapId and not tostring(item.label):find("^Drop") then
                    bad(mapId, item, "said arrived but still on the map at " .. game.overworld.player.cellX .. ","
                      .. game.overworld.player.cellY .. " want " .. tostring(toMapId))
                  elseif toMapId ~= "LAST_MAP" and toMapId and here() ~= toMapId and not tostring(item.label):find("^Drop")
                    and game.data.maps[mapId].warps[item.index].destMap ~= "LAST_MAP" then
                    bad(mapId, item, "arrived on " .. tostring(here()) .. " want " .. tostring(toMapId))
                  else
                    totals.ok = totals.ok + 1
                  end
                elseif here() ~= mapId then
                  bad(mapId, item, "left the map for " .. tostring(here()) .. " at arrival: " .. text:sub(-100))
                elseif item.type == "connection" then
                  -- one more press takes the player across, or the walk stopped at a wall
                  local dir = ({ north = "up", south = "down", east = "right", west = "left" })[item.direction]
                  for _ = 1, 30 do
                    if here() ~= mapId then break end
                    table.insert(game.input.pressQueue, dir)
                    game.input.state[dir] = true
                    U.wait(1)
                  end
                  game.input.state[dir] = false
                  calm()
                  if here() ~= item.destinationMapId then
                    bad(mapId, item, "would not cross at " .. game.overworld.player.cellX .. "," .. game.overworld.player.cellY)
                  else
                    totals.ok = totals.ok + 1
                  end
                else
                  totals.ok = totals.ok + 1
                end
                ::nextItem::
              end
            end
          end
        end
      end
    end
  end
  U.log("RESULT", "walks", totals.walks, "ok", totals.ok, "bad", totals.bad, "no route from any entry", totals.noRoute,
    "maps skipped", totals.skipped)
  Speech.say = say
  U.log("DONE")
end
