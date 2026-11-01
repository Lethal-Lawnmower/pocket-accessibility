-- FireRed navigation, harder places (decision 29): a trainer battle that
-- pauses and resumes a walk (Viridian Forest), Surf through the game's own
-- prompt (Pallet Town to Route 21), the Rocket Hideout's spinner floors by
-- a cross-map journey, and Silph Co.: a journey through warp pads to the
-- Card Key, then card key doors opened on the way.  Harness setup (party,
-- badges, story flags, teleports) uses the game's own loader, party and
-- flag store.  Silent and isolated:
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/gen3_nav_more.lua
return function(game)
  local L = dofile("tests/access/drivers/gen3_nav_lib.lua").new(game)
  local U = L.U
  if not L.boot() then return end
  L.giveParty(6, 70, { "SURF", "STRENGTH", "CUT" }, { "CUT", "SURF", "STRENGTH" })
  L.setVar(0x4050, 3)
  local engaged = 0
  local Runtime = package.loaded["src.mods.Runtime"]
  Runtime.events:on("world.trainer_engaged", function() engaged = engaged + 1 U.log("TRAINER", "engaged at", L.where()) end)
  local function only(pattern, filter)
    return L.find(function(item) return tostring(item.label):find(pattern) ~= nil end, filter)
  end

  -- A. Nugget Bridge (Route 24): trainers stand along the bridge and the
  -- Rocket at its end starts a scene; walk to the item ball past them all
  L.teleport("FR_ROUTE_24", 11, 33, "up")
  U.log("MAP", L.where())
  L.logBrowse("objects")
  local ball = L.find(function(item) return item.type == "object" and item.x == 11 and item.y == 4 end, "objects")
  L.check(ball ~= nil, "Route 24 item ball listed by its item (" .. tostring(ball and ball.label) .. ")")
  if ball then
    local battles = L.battles
    local said = L.walkTo(ball, { trace = true, answer = "a", limit = 40000 })
    U.log("WALK", said, "at", L.where())
    L.check(said:find("Arrived at", 1, true) ~= nil, "Nugget Bridge walk arrived")
    U.log("NOTE", "trainers engaged", engaged, "battles", L.battles - battles)
    L.check(engaged > 0, "trainers engaged the walking player")
    L.check(said:find("Resuming walk", 1, true) ~= nil, "walk resumed after the trainer battles")
  end

  -- B. Surf: Pallet Town south to Route 21
  L.teleport("FR_PALLET_TOWN", 6, 14, "down")
  local south = L.find(function(item) return item.type == "connection" and item.direction == "south" end)
  if south then
    L.select(south, "all")
    U.log("P", L.guide(south, "all"))
    local said = L.walkTo(south, { trace = true, answer = "a", limit = 6000 })
    U.log("WALK", said, "at", L.where())
    L.check(said:find("Arrived at South connection", 1, true) ~= nil, "Surf walk reached the south edge")
    L.check(require("src.core.game3.player").surfing == true, "the player is surfing after the walk")
    L.hold("down", 24)
    L.settle(600, true)
    L.check(L.pos() == "FR_ROUTE_21_NORTH", "crossed onto Route 21 North by Surf")
  end

  -- C. Rocket Hideout: a journey from B1F across the spinner floor
  L.teleport("FR_ROCKET_HIDEOUT_B2F", 28, 3, "down")
  U.log("MAP", L.where())
  L.logBrowse("all")
  local target = L.find(function(item) return item.type == "object" and item.x == 15 and item.y == 3 end, "objects")
  if target then
    local said = L.walkTo(target, { trace = true, answer = "a", limit = 20000 })
    U.log("WALK", said, "at", L.where())
    L.check(said:find("Arrived at", 1, true) ~= nil, "Rocket Hideout B2F: walked across the spinners")
  else
    L.check(false, "Rocket Hideout B2F item ball at (15,3) listed")
  end
  local area = L.logBrowse("area")
  local deep = L.find(function(item) return item.type == "area" and tostring(item.label):find("B4F") end, "area")
    or area[1]
  if deep then
    local said = L.walkTo(deep, { trace = true, answer = "a", limit = 30000, filter = "area" })
    U.log("JOURNEY", said, "at", L.where())
    L.check(said:find("Arrived at", 1, true) ~= nil, "Rocket Hideout journey arrived (" .. tostring(deep.label) .. ")")
  end

  -- D. Silph Co.: journey to the Card Key, then through card key doors
  L.teleport("FR_SILPH_CO_1F", 8, 18, "up")
  U.log("MAP", L.where())
  local key = only("^Card Key", "area")
  L.check(key ~= nil, "Area lists the Card Key on another Silph Co. floor")
  if key then
    local said = L.walkTo(key, { trace = true, answer = "a", limit = 40000, filter = "area" })
    U.log("JOURNEY", said, "at", L.where())
    L.check(said:find("Arrived at Card Key", 1, true) ~= nil, "journey through the warp pads to the Card Key")
    L.tap("a", 20)
    L.settle(600, true)
    U.log("SAID", L.heard())
  end
  L.check(L.nav():hasCardKey(), "the Card Key is in the bag")
  if L.pos() ~= "FR_SILPH_CO_5F" then L.teleport("FR_SILPH_CO_5F", 28, 3, "down") end
  L.logBrowse("all")
  local behind = L.find(function(item) return item.type == "object" and item.x == 4 and item.y == 9 end, "objects")
  if behind then
    local said = L.walkTo(behind, { trace = true, answer = "a", limit = 20000 })
    U.log("WALK", said, "at", L.where())
    L.check(said:find("Arrived at", 1, true) ~= nil, "walked through a card key door to " .. tostring(behind.label))
  else
    L.check(false, "Silph Co. 5F item ball at (4,9) listed")
  end

  L.finish("gen3_nav_more")
end
