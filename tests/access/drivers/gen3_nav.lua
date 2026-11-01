-- FireRed navigation, first scenarios (decision 29): from the bedroom of a
-- new game to outside Pallet Town by auto-walk, the object list, M, Y, Q,
-- E and F8, then Pallet Town to Route 1 and on to Viridian City (a ledge on
-- the way), guided navigation (P) and a cross-map journey.  Silent and
-- isolated:
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_BACKGROUND=1 POKEPORT_ACCESS_TRACE=1
--   POKEPORT_TOUCH=0 POKEPORT_IDENTITY=pocket-access-nav-firered
--   POKEPORT_VERSION=firered POKEPORT_GAME=firered
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/gen3_nav.lua
return function(game)
  local L = dofile("tests/access/drivers/gen3_nav_lib.lua").new(game)
  local U = L.U
  if not L.boot() then return end
  L.settle(600, true)
  L.check(L.nav() ~= nil, "navigation bound to the FireRed session")
  U.log("SAID", L.heard())

  -- the bedroom
  U.log("MAP", L.where())
  U.log("M", L.command("read_map_name"))
  U.log("Y", L.command("read_player_position"))
  U.log("Q", L.command("read_game_time"))
  U.log("E", L.command("read_collision_tiles"))
  local items = L.logBrowse("all")
  L.check(#items > 0, "bedroom object list has items")
  local stairs = L.findLabel("1F", "warps")
  L.check(stairs ~= nil, "stairs down listed as a warp")
  if stairs then
    local said = L.walkTo(stairs, { trace = true })
    U.log("WALK", said, "at", L.where())
    L.check(L.pos() == "FR_PLAYERS_HOUSE_1F", "auto-walk took the stairs to 1F")
  end
  L.settle(1200, true)
  U.log("SAID", L.heard())
  L.logBrowse("all")
  local door = L.findLabel("Pallet Town", "warps")
  L.check(door ~= nil, "front door to Pallet Town listed")
  if door then
    local said = L.walkTo(door, { trace = true, answer = "a" })
    U.log("WALK", said, "at", L.where())
    L.check(L.pos() == "FR_PALLET_TOWN", "auto-walk left the house into Pallet Town")
  end
  L.settle(1200, true)
  U.log("SAID", L.heard())
  U.log("M", L.command("read_map_name"))
  L.logBrowse("all")

  -- Pallet Town to Route 1.  Oak stops the player at the north exit in a
  -- new game (coord event on VAR 0x4050 == 0); the harness gives a party
  -- Pokemon and moves that story variable on, as playing would.
  L.giveParty(6, 40, {}, {})
  L.setVar(0x4050, 3)
  local function connection(direction)
    return L.find(function(item) return item.type == "connection" and item.direction == direction end)
  end
  local north = connection("north")
  L.check(north ~= nil, "north connection listed")
  if north then
    local guided = L.guide(north, "all")
    U.log("P", guided)
    L.check(guided ~= "", "guided navigation speaks a route to Route 1")
    local said = L.walkTo(north, { trace = true })
    U.log("WALK", said, "at", L.where())
    L.hold("up", 24)
    L.settle(600, true)
    U.log("SAID", L.heard())
    L.check(L.pos() == "FR_ROUTE_1", "crossed the connection onto Route 1")
  end
  L.logBrowse("all")
  north = connection("north")
  if north then
    local said = L.walkTo(north, { trace = true, answer = "b", limit = 6000 })
    U.log("WALK", said, "at", L.where())
    L.hold("up", 24)
    L.settle(600, true)
    U.log("SAID", L.heard())
    L.check(L.pos() == "FR_VIRIDIAN_CITY", "Route 1 walked north into Viridian City")
  end
  U.log("M", L.command("read_map_name"))
  L.logBrowse("all")

  -- Route 1 south at 200X AUTO-WALK SPEED: the ledges are jumped on the way
  game.options.accessAutoWalkSpeed = 200
  L.teleport("FR_ROUTE_1", 10, 4, "down")
  local south = connection("south")
  if south then
    L.select(south, "all")
    local options = L.nav():worldRouteRequest(
      L.nav():connectionGoals(L.nav():worldForCommand(), south), 1)
    local route = options and require("src.access.nav.Pathfinder").find(options)
    local ledges = 0
    for _, step in ipairs(route and route.steps or {}) do
      if step.kind == "ledge" then ledges = ledges + 1 end
    end
    U.log("ROUTE", table.concat(L.nav():routeNarration(L.nav():worldForCommand(), route or { steps = {} }), ", "))
    L.check(ledges > 0, "the route south over Route 1 jumps a ledge")
    local speeds = {}
    local said = L.walkTo(south, { trace = true, limit = 6000, onFrame = function()
      speeds[tostring(game:logicSpeed())] = true
    end })
    U.log("WALK", said, "at", L.where())
    local seen = {}
    for k in pairs(speeds) do seen[#seen + 1] = k end
    U.log("SPEEDS", table.concat(seen, ","))
    L.check(speeds["200"] == true, "auto-walk ran at 200X")
    L.check(said:find("Arrived at South connection", 1, true) ~= nil, "200X walk arrived at the south edge")
  end
  game.options.accessAutoWalkSpeed = nil
  L.check(game:logicSpeed() ~= 200, "game speed handed back after the walk")

  L.finish("gen3_nav")
end
