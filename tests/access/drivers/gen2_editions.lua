-- Things proven in Crystal, on each edition's own maps.  Every place is found from the
-- live data, never from Crystal's numbers:
--   Tohjo Falls: both exits listed apart; walking each; a journey from Route 27's west
--     side to Route 26, through the falls.
--   Team Rocket Base: B1F to B3F names; each floor's door by its role; a door refused
--     without the password; one auto-walk to it and A opens it; it leaves the list;
--     the room behind it is then routed.
--   Mt. Mortar, Dark Cave and Ice Path: floors reached as journeys from the far side.
--   Vermilion Gym: Lt. Surge reached by walking, cans named, no gates.
--   Kanto's gyms, Saffron's by its pads, each leader from the door.
-- GEN2_EDITION_ONLY=tohjo,rocket,journeys,surge,kanto limits it.
-- Harness setup teleports, sets story flags and gives a party.  Silent; read RESULT lines.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U, AutoWalk = L.U, L.AutoWalk
  L.settle(2000, true)
  L.strongParty()
  game.world.flashUsed = true
  game.speedOverride = 4
  local version = tostring(game.save.version)
  local maps = game.data.gen2Maps
  local only = os.getenv("GEN2_EDITION_ONLY")
  local function wanted(name) return not only or only:find(name, 1, true) end
  local fails = 0
  local function fail(...)
    fails = fails + 1
    U.log("FAIL", version, ...)
  end
  local function list(filter)
    local parts = {}
    for _, item in ipairs(L.browse(filter)) do parts[#parts + 1] = tostring(item.label) end
    return table.concat(parts, " ; ")
  end
  -- one auto-walk to the first item `match` accepts; returns its speech and final place
  local function walk(match, filter, limit)
    local target = L.find(match, filter)
    if not target then return nil, "not listed" end
    L.select(target, filter)
    L.heard()
    game.world.flashUsed = true
    AutoWalk.start(L.nav(), game, L.adapter())
    local finished = L.runWalk(tonumber(os.getenv("GEN2_EDITION_LIMIT")) or limit or 20000, nil, nil, function(frame)
      game.world.flashUsed = true -- what Flash leaves set; a new floor clears it here
      if os.getenv("GEN2_EDITION_TRACE") and frame % 300 == 0 then
        local world, state = game.world, AutoWalk._state()
        U.log("TRACE", L.where(), "coll", tostring(world.map:cellCollision(world.player.cellX, world.player.cellY)),
          "moving", tostring(world.player.moving), "setup", tostring(world.mapSetup ~= nil), "held",
          tostring(state and state.held), "push", tostring(state and state.pushDir), "paused", tostring(state and state.paused),
          "await", tostring(state and state.awaitingMap), "steps", tostring(state and #state.steps), "top", tostring(game.stack:top() ~= nil),
          "busy", tostring(require("src.access.nav.WorldAdapter").gen2.transitioning(world)), L.steps():sub(1, 80))
      end
    end)
    if not finished then AutoWalk.stop() U.log("WARN", "walk stopped at the limit", L.where()) end
    L.settle(600, true, 10)
    return L.heard(), L.where(), target
  end
  local function byLabel(text) return function(i) return tostring(i.label):find(text, 1, true) ~= nil end end
  local function arrivalOf(mapId, predicate)
    for _, warp in ipairs(maps[mapId].warps or {}) do
      if predicate(warp) then return warp end
    end
  end

  if wanted("tohjo") then
    local def = maps.TOHJO_FALLS
    local groups = {}
    for _, warp in ipairs(def.warps) do groups[#groups + 1] = warp.x .. "," .. warp.y .. ">" .. tostring(warp.destMap) end
    U.log("RESULT", version, "TOHJO warps in data", table.concat(groups, " "))
    local first = def.warps[1]
    L.teleport("TOHJO_FALLS", first.x, first.y - 1, "up")
    local labels = list("warps")
    U.log("RESULT", version, "TOHJO listed", labels)
    local count = #L.browse("warps")
    if count < 2 then fail("Tohjo Falls lists", count, "exit") end
    local items = L.browse("warps")
    for index = 1, #items do
      L.teleport("TOHJO_FALLS", first.x, first.y - 1, "up")
      local item = L.browse("warps")[index]
      local text, where = walk(function(i) return i.id == item.id end, "warps")
      U.log("RESULT", version, "TOHJO walk to", item.label, "=>", where, tostring(text):sub(-70))
      if not tostring(where):find("ROUTE_27", 1, true) then
        U.log("NOTE", version, "from entrance 1 this exit is reached only by water, ended", where)
      end
    end
    -- Route 27's west side to Route 26: through the falls
    local west = arrivalOf("ROUTE_27", function(w) return w.destMap == "TOHJO_FALLS" end)
    L.teleport("ROUTE_27", west.x, west.y + 1, "up")
    U.log("RESULT", version, "ROUTE_27 from", L.where(), "connections", list("connections"))
    local text, where = walk(byLabel("Route 26"), "connections", 30000)
    U.log("RESULT", version, "ROUTE_27 journey to Route 26 =>", where, tostring(text):sub(-100))
    if not (tostring(where):find("ROUTE_27", 1, true) or tostring(where):find("ROUTE_26", 1, true)) then
      fail("the journey to Route 26 ended at", where)
    end
  end

  if wanted("rocket") then
    local floors = { "TEAM_ROCKET_BASE_B1F", "TEAM_ROCKET_BASE_B2F", "TEAM_ROCKET_BASE_B3F" }
    for _, floor in ipairs(floors) do
      local w = maps[floor].warps[1]
      L.teleport(floor, w.x, w.y + 1, "down")
      U.log("RESULT", version, floor, "stood", L.where())
      U.log("RESULT", version, floor, "signs", list("signposts"))
      U.log("RESULT", version, floor, "warps", list("warps"))
    end
    for _, floor in ipairs({ "TEAM_ROCKET_BASE_B2F", "TEAM_ROCKET_BASE_B3F" }) do
      -- each door's arrival: every entrance is tried until the door routes
      local doorLabel = "Locked"
      local opened = false
      for _, warp in ipairs(maps[floor].warps) do
        L.teleport(floor, warp.x, warp.y, "down")
        L.settle(300, true, 10)
        if L.pos() == floor and L.nav():worldForCommand() and L.find(byLabel(doorLabel), "signposts") then
          local door = L.find(byLabel(doorLabel), "signposts")
          local text, where = walk(byLabel(doorLabel), "signposts", 30000)
          U.log("RESULT", version, floor, "from", warp.x .. "," .. warp.y, "walk to", door.label, "=>", where, tostring(text):sub(-80))
          if tostring(text):find("Arrived", 1, true) or tostring(text):find("is here", 1, true) then
            -- without the password the game refuses; A to read it
            local nav, world = L.nav(), game.world
            local dx, dy = door.x - world.player.cellX, door.y - world.player.cellY
            local dir = math.abs(dx) > math.abs(dy) and (dx > 0 and "right" or "left") or (dy > 0 and "down" or "up")
            L.tap(dir, 12)
            L.tap("a", 20)
            L.settle(300, true, 10)
            U.log("RESULT", version, floor, "A with no password, door listed", tostring(L.find(byLabel(doorLabel), "signposts") ~= nil), L.heard():sub(-80))
            -- the game's own passwords, by the flags the door's script checks
            local Scripts = game.world.scripts
            local bg
            for _, e in ipairs(maps[floor].bgEvents) do
              if e.x == door.x and e.y == door.y then bg = e end
            end
            for _, cmd in ipairs(bg and Scripts[bg.scriptKey] or {}) do
              if type(cmd) == "table" and cmd.op == "checkevent" then game.world.events:set(cmd.event, true) end
            end
            L.tap(dir, 12)
            L.tap("a", 20)
            L.settle(300, true, 10)
            local stillListed = L.find(byLabel(doorLabel), "signposts") ~= nil
            U.log("RESULT", version, floor, "A with the password, door listed", tostring(stillListed), L.heard():sub(-80))
            if stillListed then fail(floor, "door still listed after opening") end
            opened = not stillListed
            break
          end
        end
      end
      if not opened then fail(floor, "door not opened") end
      U.log("RESULT", version, floor, "after the door", list("all"))
    end
  end

  if wanted("journeys") then
    -- story state: Gold and Silver's sage stands on Tin Tower 1F's stairs until the
    -- story moves him (found by his cell, so Crystal, with none there, is untouched)
    for _, object in ipairs(maps.TIN_TOWER_1F.objects or {}) do
      for _, warp in ipairs(maps.TIN_TOWER_1F.warps) do
        if object.x == warp.x and object.y == warp.y and object.eventFlag then
          game.world.events:set(object.eventFlag, true)
          U.log("RESULT", version, "TIN_TOWER_1F object on the stairs moved by the harness", tostring(object.sprite))
        end
      end
    end
    for _, trip in ipairs({
      { from = "ICE_PATH_1F", to = "Ice Path B3F" }, { from = "ICE_PATH_B3F", to = "Ice Path 1F" },
      { from = "ICE_PATH_B2F_BLACKTHORN_SIDE", to = "Ice Path B1F" },
      { from = "MOUNT_MORTAR_1F_OUTSIDE", to = "Mount Mortar B1F" },
      { from = "DARK_CAVE_VIOLET_ENTRANCE", to = "Dark Cave Blackthorn Entrance" },
      { from = "WHIRL_ISLAND_NW", to = "Whirl Island B2F" },
      { from = "SILVER_CAVE_ROOM_1", to = "Silver Cave Room 3" },
      { from = "TIN_TOWER_1F", to = "Tin Tower Roof" },
      { from = "BURNED_TOWER_1F", to = "Burned Tower B1F" },
    }) do
      local w = maps[trip.from] and maps[trip.from].warps[1]
      if w then
        L.teleport(trip.from, w.x, w.y, "down")
        L.settle(300, true, 10)
        local text, where = walk(byLabel(trip.to), "area", 30000)
        U.log("RESULT", version, "JOURNEY", trip.from, "to", trip.to, "=>", where, tostring(text):sub(-90))
        local floor = trip.to:upper():gsub(" ", "_")
        if not tostring(where):find(floor, 1, true) then
          U.log("WARN", version, "journey", trip.from, "to", trip.to, "ended", where)
        end
      end
    end
  end

  if wanted("surge") then
    local w = maps.VERMILION_GYM.warps[1]
    L.teleport("VERMILION_GYM", w.x, w.y - 1, "up")
    U.log("RESULT", version, "VERMILION signs", list("signposts"))
    local text, where = walk(byLabel("Surge"), "npcs", 20000)
    U.log("RESULT", version, "VERMILION walk to Surge =>", where, tostring(text):sub(-80))
    if not (tostring(text):find("Arrived", 1, true) or tostring(text):find("is here", 1, true)) then
      fail("Lt. Surge not reached")
    end
  end
  if wanted("kanto") then
    -- gyms past the Elite Four, each from its door; Saffron's way is only by its pads
    for _, gym in ipairs({ { "SAFFRON_GYM", "Sabrina" }, { "VIRIDIAN_GYM", "Blue" }, { "SEAFOAM_GYM", "Blaine" },
        { "FUCHSIA_GYM", "Janine" }, { "CELADON_GYM", "Erika" }, { "CERULEAN_GYM", "Misty" }, { "PEWTER_GYM", "Brock" } }) do
      local w = maps[gym[1]].warps[1]
      -- a leader the new game's flags hide (Blue, until the story brings him)
      for _, object in ipairs(maps[gym[1]].objects or {}) do
        if object.eventFlag and object.eventFlag ~= 0xFFFF and object.movement == 6 then
          game.world.events:set(object.eventFlag, false)
        end
      end
      L.teleport(gym[1], w.x, w.y - 1, "up")
      L.settle(300, true, 10)
      U.log("RESULT", version, gym[1], "people", list("npcs"))
      local text, where = walk(function(i)
        local label = tostring(i.label)
        return label:find(gym[2], 1, true) ~= nil or label:find("Leader", 1, true) ~= nil
      end, "npcs", 40000)
      U.log("RESULT", version, gym[1], "walk to", gym[2], "=>", where, tostring(text):sub(-90))
      if not (tostring(text):find("Arrived", 1, true) or tostring(text):find("is here", 1, true)) then
        fail(gym[1], gym[2], "not reached:", tostring(text):sub(-90))
      end
    end
  end
  U.log("RESULT", version, "fails", fails)
  U.log("DONE")
end
