-- Required story spots for Gold, Silver and Crystal (the Gen 2 counterpart of
-- hard_places_sweep.lua): every gym and its trainers, the dungeons and
-- buildings a blind player must get through to finish the game, Kanto, Mt.
-- Silver and Crystal's Battle Tower.  For every warp and item ball on each
-- map (and, where `people` is set, every person; `extra` adds named signs or
-- objects) it teleports to the map's first entrance, auto-walks to the
-- target, wins any battle on the way and logs one RESULT line.  A target not
-- reached from the first entrance is tried from the map's other entrances.
--
-- Outcomes: REACHED ("Arrived" or "is here"); GATED, with what gates it: a
-- person, boulder or rock on every route (named, found by re-planning with
-- the map's objects removed), or the map's own collision (a closed door,
-- shutter or wall the story or a puzzle opens); BLOCKED for anything else
-- (the walk began and failed), which is a layer problem until shown
-- otherwise.  The party knows every field move and every Johto badge is
-- owned, so field moves never gate.
--
-- Harness setup (teleports, party, badges, healing, a repel so wild battles
-- do not stall every walk) goes through the game's World:setMap and save
-- tables, never through accessibility code.  Silent; identities
-- `pocket-access-audit-<game>`.  SPOTS_MAPS=VIOLET_GYM,... limits the maps;
-- SPOTS_SPEED sets AUTO-WALK SPEED; SPOTS_DRIVER_SPEED sets the frames the
-- harness runs per rendered frame (default 8).
return function(game)
  -- POKEPORT_BACKGROUND only mutes the game on Windows; its window can still
  -- take keyboard focus, and any real key or button stops auto-walk.  One
  -- run had walks stop at once with "Auto walk stopped" (the suspected
  -- cause; runs since are clean).  Minimise the window and ignore real
  -- input: the harness drives game.input directly.
  pcall(function() love.window.minimize() end)
  for _, callback in ipairs({ "keypressed", "keyreleased", "textinput", "gamepadpressed",
      "gamepadreleased", "gamepadaxis", "joystickpressed", "joystickreleased",
      "joystickaxis", "joystickhat", "mousepressed", "mousereleased" }) do
    love[callback] = function() end
  end
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local Pathfinder = require("src.access.nav.Pathfinder")
  local Mon = require("src.battle.gen2.Mon")
  if not L.settle(3000, true) then U.log("FAIL", "never reached the free world") return end
  game.driverSpeed = tonumber(os.getenv("SPOTS_DRIVER_SPEED")) or 8
  game.options.accessAutoWalkSpeed = tonumber(os.getenv("SPOTS_SPEED"))
  -- SET: no "change POKéMON?" offer between a trainer's Pokémon (an A there
  -- opens the party, where A only says the lead is already out); no battle
  -- animations; fast text
  game.options.battleStyle, game.options.battleScene, game.options.textSpeed = "SET", false, "FAST"
  local version = tostring(game.save and game.save.version or os.getenv("POKEPORT_VERSION"))
  local maps = game.data.gen2Maps

  local function newMon(species, moves)
    local mon = Mon.new(game.data, species, 100)
    local list = {}
    for i, id in ipairs(moves) do list[i] = { id = id, pp = 10 } end
    mon.moves = list
    return mon
  end
  local party = {
    -- ICE_BEAM first: no type is immune to Ice (with PSYCHIC first the
    -- rival's SNEASEL at Mt. Moon could never be hurt and the battle never
    -- ended)
    newMon("MEWTWO", { "ICE_BEAM", "SURF", "STRENGTH", "FLASH" }),
    newMon("FERALIGATR", { "CUT", "WHIRLPOOL", "WATERFALL", "ROCK_SMASH" }),
    newMon("SNORLAX", { "HEADBUTT", "EARTHQUAKE", "FLY", "STRENGTH" }),
  }
  game.save.party = party
  game.save.player.badges = game.save.player.badges or {}
  for _, badge in ipairs({ "ZEPHYR", "HIVE", "PLAIN", "FOG", "STORM", "MINERAL", "GLACIER", "RISING" }) do
    game.save.player.badges[badge] = true
  end
  -- PP inside a battle: the battle may clamp the party's PP to its maximum
  -- (Gold showed "PP 9 of 10" where Crystal kept 60), and Vermilion Gym's
  -- three trainers in one walk emptied it; with no PP an A press only says
  -- "no PP left" and the battle never ends.  Refill the battle's own moves.
  local function refillBattlePp()
    local stack = package.loaded["src.core.StateStack"]
    for _, state in ipairs(stack and stack.states or {}) do
      local battle = type(state) == "table" and state.isBattle and state.battle
      if type(battle) == "table" then
        for _, mon in ipairs({ battle.player, (battle.party or {})[1] }) do
          for _, move in ipairs(type(mon) == "table" and mon.moves or {}) do
            if type(move) == "table" and (move.pp or 0) < 5 then move.pp = move.maxPp or 10 end
          end
        end
      end
    end
  end
  local function heal()
    refillBattlePp()
    for _, mon in ipairs(party) do
      if mon.maxHp then mon.hp = mon.maxHp end
      mon.status = nil
      pcall(Mon.restoreAllPp, mon, game.data)
      -- a walk can meet several trainers before the next heal, so the lead
      -- carries plenty: two gym trainers back to back once emptied 10 PP
      if mon.moves and mon.moves[1] then mon.moves[1].pp = 60 end
    end
    game.save.repelSteps = 9999
    -- what using Flash leaves set: dark floors are gated by it on purpose (decision 37)
    if game.world then game.world.flashUsed = true end
  end

  -- Scenes that hold the world in a loop an A press never leaves: Crystal's
  -- Dragon Shrine quiz repeats its first question for ever when pressed
  -- through.  Walking into the shrine is still a target; its scene is set to
  -- the one the story leaves it in, so the walk's arrival does not start it.
  local function lastScene(mapId)
    local scenes = maps[mapId] and maps[mapId].sceneScripts or {}
    local last = 0
    for id in pairs(scenes) do if type(id) == "number" and id > last then last = id end end
    return last
  end
  for _, mapId in ipairs({ "DRAGON_SHRINE" }) do
    if maps[mapId] then game.world.mapScenes[mapId] = lastScene(mapId) end
  end

  local function entrance(mapId, index)
    local def = maps[mapId]
    local warp = def and def.warps and def.warps[index or 1]
    if not warp then return nil end
    return warp.x, warp.y
  end

  -- the cell to stand on for entrance `index`: the warp cell itself, or a
  -- start cell given by the plan
  local function goTo(step, index)
    heal()
    local x, y
    if step.start and (index or 1) == 1 then
      x, y = step.start[1], step.start[2]
    else
      x, y = entrance(step.map, index)
    end
    if not x then return false end
    -- never teleport out of a battle or script: popping a battle leaves the
    -- world marked busy for good, which no player can cause
    local held = require("src.access.nav.WorldAdapter").gen2.scriptHeld
    for _ = 1, 12 do
      if not held(game.world) then break end
      heal()
      L.settle(150, true, 5)
    end
    if held(game.world) then U.log("WARN", "a script still holds the world at", L.where(), "; teleporting anyway") end
    -- a map whose entry scene sent the player away (a fresh save is before
    -- the story reaches it) is retried with its last scene, the state the
    -- story leaves it in
    if step.lastScene then game.world.mapScenes[step.map] = lastScene(step.map) end
    L.teleport(step.map, x, y, step.facing or "down")
    L.settle(600, true)
    -- a teleport onto a warp the game fires at once (Ruins of Alph's chamber doors)
    -- leaves the map: stand beside the entrance
    if L.pos() ~= step.map then L.teleport(step.map, x, y + 1, step.facing or "down") L.settle(600, true) end
    -- a teleport onto a staircase or door skips the game's step off it, so
    -- the world counts as mid-transition until the player moves (Radio
    -- Tower 2F's stairs sit at 0,0): stand beside the entrance instead
    local nav = L.nav()
    if L.pos() == step.map and nav and not nav:worldForCommand() then
      local Permissions = require("src.world.gen2.Permissions")
      local map = game.world.map
      for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
        local nx, ny = x + d[1], y + d[2]
        local ok, coll = pcall(map.cellCollision, map, nx, ny)
        if ok and map:inBounds(nx, ny) and Permissions.isWalkable(coll)
           and not Permissions.isWarpCollision(coll) then
          L.teleport(step.map, nx, ny, step.facing or "down")
          L.settle(600, true)
          break
        end
      end
    end
    return L.pos() == step.map
  end

  local function isPerson(item)
    return item.type == "object" and item.item == nil and not item.synthetic
      and item.semanticKind == nil and not tostring(item.label):match("^Boulder")
      and item.label ~= "Smashable Rock"
  end

  local function targetsOn(step)
    if not goTo(step) then return nil end
    local list = {}
    local items = L.browse("all")
    if #items == 0 then U.log("WARN", step.map, "empty object list at", L.where(), "top", tostring(game.stack:top())) end
    for _, item in ipairs(items) do
      local want = item.type == "warp"
        or (item.type == "object" and item.item ~= nil)
        or (step.people and isPerson(item))
        or (step.extra and step.extra(item))
      if want and step.skip and step.skip(item) then want = false end
      if want then list[#list + 1] = { id = item.id, label = item.label, description = item.description } end
    end
    return list
  end

  local function reached(text)
    return text:find("Arrived at", 1, true) ~= nil or text:find(" is here", 1, true) ~= nil
  end

  local function noRoute(text)
    return text:find("No route", 1, true) or text:find("No path", 1, true)
      or text:find("Cannot reach", 1, true) or text:find("no path", 1, true)
      or text:find("Could not plan a route", 1, true)
  end

  local function selectedItem(id)
    for _, item in ipairs(L.browse("all")) do
      if item.id == id then return item end
    end
    return nil
  end

  -- What stands in the way when no route exists: re-plan on the live map
  -- with every object removed.  If that finds a route, name the objects on
  -- its cells (and beside them, for a person who blocks by standing in a
  -- corridor); otherwise the map's own collision gates it.
  local function gateFor(id)
    local nav = L.nav()
    local item = selectedItem(id)
    if not (nav and item) then return "target not in the list here" end
    L.select(item)
    local _, goals = nav:selectedRouteGoals()
    if type(goals) ~= "table" or #goals == 0 then return "no approach cell" end
    local world = nav:worldForCommand()
    if not world then return "not on the map" end
    local bare = { map = world.map, player = world.player, native = { npcAt = function() return nil end },
      npcs = {}, entities = { world.player } }
    local options = nav:routeOptionsFor(bare, goals, 2)
    local result = options and Pathfinder.find(options)
    if not result then return "map collision (closed passage, wall or puzzle)" end
    local blockers, seen = {}, {}
    for _, stepCell in ipairs(result.steps or {}) do
      local x, y = stepCell.x, stepCell.y
      local ok, npc = pcall(world.native.npcAt, world.native, x, y)
      if ok and npc and not seen[npc] then
        seen[npc] = true
        local label = "object"
        for _, entry in ipairs(L.browse("objects")) do
          if entry.id == npc.id then label = entry.label break end
        end
        blockers[#blockers + 1] = label .. " at " .. x .. "," .. y
      end
    end
    if #blockers == 0 then return "no route though nothing stands on the bare route (check by hand)" end
    return "object: " .. table.concat(blockers, "; ")
  end

  local function walkTo(step, target, index)
    if not goTo(step, index) then return "could not teleport to entrance " .. tostring(index or 1) end
    local item = selectedItem(target.id)
    if not item then return "target not listed from entrance " .. tostring(index or 1) end
    -- full HP and PP through every battle (the Rocket base cameras can call
    -- several grunts in one walk)
    -- The harness's own frame multiplier (driverSpeed) bypasses the game's
    -- speed field, so it does here what WalkSpeed does in play: one tick
    -- per frame while auto-walk turns to face a field move.
    local frames, base = 0, game.driverSpeed
    local text = L.walkTo(item, { answer = "a", limit = step.limit or 6000, onFrame = function()
      frames = frames + 1
      if frames % 30 == 0 then heal() end
      game.driverSpeed = L.AutoWalk.turning() and 1 or base
    end })
    game.driverSpeed = base
    L.settle(900, true)
    return text
  end

  local only = os.getenv("SPOTS_MAPS")
  local P = true
  local plan = {
    -- Johto gyms: every trainer and the leader
    { map = "VIOLET_GYM", people = P }, { map = "AZALEA_GYM", people = P },
    { map = "GOLDENROD_GYM", people = P }, { map = "ECRUTEAK_GYM", people = P },
    { map = "OLIVINE_GYM", people = P }, { map = "CIANWOOD_GYM", people = P },
    { map = "MAHOGANY_GYM", people = P }, { map = "BLACKTHORN_GYM_1F", people = P },
    { map = "BLACKTHORN_GYM_2F", people = P },
    -- Johto story dungeons
    { map = "SPROUT_TOWER_1F" }, { map = "SPROUT_TOWER_2F" }, { map = "SPROUT_TOWER_3F", people = P },
    { map = "RUINS_OF_ALPH_OUTSIDE" }, { map = "RUINS_OF_ALPH_HO_OH_CHAMBER", extra = function(i) return i.type == "signpost" end },
    { map = "RUINS_OF_ALPH_KABUTO_CHAMBER", extra = function(i) return i.type == "signpost" end },
    { map = "RUINS_OF_ALPH_OMANYTE_CHAMBER", extra = function(i) return i.type == "signpost" end },
    { map = "RUINS_OF_ALPH_AERODACTYL_CHAMBER", extra = function(i) return i.type == "signpost" end },
    { map = "RUINS_OF_ALPH_INNER_CHAMBER" },
    { map = "RUINS_OF_ALPH_HO_OH_ITEM_ROOM" }, { map = "RUINS_OF_ALPH_KABUTO_ITEM_ROOM" },
    { map = "RUINS_OF_ALPH_OMANYTE_ITEM_ROOM" }, { map = "RUINS_OF_ALPH_AERODACTYL_ITEM_ROOM" },
    { map = "RUINS_OF_ALPH_HO_OH_WORD_ROOM" }, { map = "RUINS_OF_ALPH_KABUTO_WORD_ROOM" },
    { map = "RUINS_OF_ALPH_OMANYTE_WORD_ROOM" }, { map = "RUINS_OF_ALPH_AERODACTYL_WORD_ROOM" },
    { map = "UNION_CAVE_1F" }, { map = "UNION_CAVE_B1F" }, { map = "UNION_CAVE_B2F" },
    { map = "SLOWPOKE_WELL_B1F", people = P }, { map = "SLOWPOKE_WELL_B2F", people = P },
    { map = "ILEX_FOREST", people = P }, { map = "NATIONAL_PARK" },
    { map = "BURNED_TOWER_1F" }, { map = "BURNED_TOWER_B1F", people = P },
    { map = "OLIVINE_LIGHTHOUSE_1F" }, { map = "OLIVINE_LIGHTHOUSE_2F" }, { map = "OLIVINE_LIGHTHOUSE_3F" },
    { map = "OLIVINE_LIGHTHOUSE_4F" }, { map = "OLIVINE_LIGHTHOUSE_5F" }, { map = "OLIVINE_LIGHTHOUSE_6F", people = P },
    { map = "TEAM_ROCKET_BASE_B1F", people = P }, { map = "TEAM_ROCKET_BASE_B2F", people = P },
    { map = "TEAM_ROCKET_BASE_B3F", people = P },
    { map = "GOLDENROD_UNDERGROUND", extra = function(i) return i.type == "signpost" end },
    { map = "GOLDENROD_UNDERGROUND_SWITCH_ROOM_ENTRANCES", extra = function(i) return i.type == "signpost" end },
    { map = "GOLDENROD_UNDERGROUND_WAREHOUSE", people = P },
    { map = "RADIO_TOWER_1F" }, { map = "RADIO_TOWER_2F" }, { map = "RADIO_TOWER_3F" },
    { map = "RADIO_TOWER_4F" }, { map = "RADIO_TOWER_5F", people = P },
    { map = "ICE_PATH_1F" }, { map = "ICE_PATH_B1F" }, { map = "ICE_PATH_B2F_MAHOGANY_SIDE" },
    { map = "ICE_PATH_B2F_BLACKTHORN_SIDE" }, { map = "ICE_PATH_B3F" },
    { map = "DRAGONS_DEN_1F" }, { map = "DRAGONS_DEN_B1F" }, { map = "DRAGON_SHRINE", people = P },
    { map = "WHIRL_ISLAND_NW" }, { map = "WHIRL_ISLAND_NE" }, { map = "WHIRL_ISLAND_SW" },
    { map = "WHIRL_ISLAND_SE" }, { map = "WHIRL_ISLAND_CAVE" }, { map = "WHIRL_ISLAND_B1F" },
    { map = "WHIRL_ISLAND_B2F" }, { map = "WHIRL_ISLAND_LUGIA_CHAMBER", people = P },
    { map = "ECRUTEAK_TIN_TOWER_ENTRANCE", people = P }, { map = "WISE_TRIOS_ROOM", people = P },
    { map = "ECRUTEAK_TIN_TOWER_BACK_ENTRANCE", people = P },
    { map = "TIN_TOWER_1F", people = P }, { map = "TIN_TOWER_2F" }, { map = "TIN_TOWER_3F" },
    { map = "TIN_TOWER_4F" }, { map = "TIN_TOWER_5F" }, { map = "TIN_TOWER_6F" },
    { map = "TIN_TOWER_7F" }, { map = "TIN_TOWER_8F" }, { map = "TIN_TOWER_9F" },
    { map = "TIN_TOWER_ROOF", people = P },
    { map = "MOUNT_MORTAR_1F_OUTSIDE" }, { map = "MOUNT_MORTAR_1F_INSIDE" },
    { map = "MOUNT_MORTAR_2F_INSIDE" }, { map = "MOUNT_MORTAR_B1F" },
    { map = "FAST_SHIP_1F" }, { map = "FAST_SHIP_B1F" },
    { map = "FAST_SHIP_CABINS_NNW_NNE_NE", people = P }, { map = "FAST_SHIP_CABINS_SW_SSW_NW", people = P },
    { map = "FAST_SHIP_CABINS_SE_SSE_CAPTAINS_CABIN", people = P },
    -- the League
    { map = "VICTORY_ROAD_GATE" }, { map = "VICTORY_ROAD" }, { map = "INDIGO_PLATEAU_POKECENTER_1F" },
    { map = "WILLS_ROOM", people = P }, { map = "KOGAS_ROOM", people = P }, { map = "BRUNOS_ROOM", people = P },
    { map = "KARENS_ROOM", people = P }, { map = "LANCES_ROOM", people = P },
    -- Kanto gyms
    { map = "PEWTER_GYM", people = P }, { map = "CERULEAN_GYM", people = P },
    { map = "VERMILION_GYM", people = P }, { map = "CELADON_GYM", people = P },
    { map = "FUCHSIA_GYM", people = P }, { map = "SAFFRON_GYM", people = P },
    { map = "SEAFOAM_GYM", people = P }, { map = "VIRIDIAN_GYM", people = P },
    -- Kanto places
    { map = "VERMILION_PORT" },
    { map = "VERMILION_CITY", extra = function(i) return i.label == "Snorlax" end },
    { map = "ROCK_TUNNEL_1F" }, { map = "ROCK_TUNNEL_B1F" },
    { map = "DARK_CAVE_VIOLET_ENTRANCE" }, { map = "DARK_CAVE_BLACKTHORN_ENTRANCE" },
    { map = "DIGLETTS_CAVE" }, { map = "MOUNT_MOON" }, { map = "CERULEAN_CITY" },
    { map = "POWER_PLANT", people = P },
    -- Mt. Silver
    { map = "SILVER_CAVE_OUTSIDE" }, { map = "SILVER_CAVE_ROOM_1" }, { map = "SILVER_CAVE_ROOM_2" },
    { map = "SILVER_CAVE_ROOM_3", people = P }, { map = "SILVER_CAVE_ITEM_ROOMS" },
    -- Crystal's Battle Tower
    { map = "ROUTE_40_BATTLE_TOWER_GATE" }, { map = "BATTLE_TOWER_OUTSIDE" },
    -- the elevator starts a challenge whose scripts the harness cannot
    -- leave; walking into it was checked once (arrived) and is skipped
    { map = "BATTLE_TOWER_1F", people = P, skip = function(i) return i.label == "Battle Tower Elevator" end },
  }

  local counts = { REACHED = 0, GATED = 0, BLOCKED = 0 }
  for _, step in ipairs(plan) do
    if not maps[step.map] then
      if not only or only:find(step.map, 1, true) then U.log("SKIP", version, step.map, "not in this edition") end
    elseif not only or only:find(step.map, 1, true) then
      local targets = targetsOn(step)
      if not targets and maps[step.map].sceneScripts then
        U.log("NOTE", version, step.map, "entry scene sent the player to", L.where(), "; retrying with the map's last scene")
        step.lastScene = true
        targets = targetsOn(step)
      end
      if not targets then
        U.log("MAP", version, step.map, "could not stand at the entrance", L.where())
      else
        U.log("MAP", version, step.map, #targets .. " targets")
        for _, target in ipairs(targets) do
          local text = walkTo(step, target)
          local from = ""
          if not reached(text) and (noRoute(text) or text:find("not listed", 1, true)) then
            local warps = maps[step.map].warps or {}
            for e = 2, #warps do
              local other = walkTo(step, target, e)
              if reached(other) then text, from = other, " (from entrance " .. e .. ")" break end
            end
          end
          local verdict, gate = "REACHED", ""
          if not reached(text) then
            if noRoute(text) or text:find("not listed", 1, true) then
              goTo(step)
              verdict, gate = "GATED", gateFor(target.id)
              if gate:find("check by hand", 1, true) or gate:find("no approach", 1, true) then verdict = "BLOCKED" end
            else
              verdict = "BLOCKED"
            end
          end
          counts[verdict] = counts[verdict] + 1
          local last = text:match("([^|]*)$") or text
          U.log("RESULT", version, verdict, step.map, target.label .. from, "=>", (last:gsub("^%s+", "")),
            gate ~= "" and ("[gate: " .. gate .. "]") or "")
          if verdict == "BLOCKED" then U.log("TEXT", text) end
        end
      end
    end
  end
  U.log("SUMMARY", version, "reached " .. counts.REACHED, "gated " .. counts.GATED, "blocked " .. counts.BLOCKED)
  game.options.accessAutoWalkSpeed = nil
  U.log("DONE")
end
