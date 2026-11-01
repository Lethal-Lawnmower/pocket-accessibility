-- Gen 2 navigation, second leg: a cross-map journey to an Area target
-- (Sprout Tower), a trainer battle interrupting auto-walk (Route 30), Surf
-- started by auto-walk through the game's own prompt (New Bark Town to Route
-- 27), and guided navigation (P).  Harness setup teleports and gives a party
-- and badges; everything else is the layer's own object list and auto-walk.
-- Silent; read the RESULT lines.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") return end
  L.giveParty("FERALIGATR", 60, { "SURF", "STRENGTH", "CUT", "WATERFALL" },
    { "ZEPHYR", "HIVE", "PLAIN", "FOG" })
  local StateStack = package.loaded["src.core.StateStack"]
  local function battleUp()
    for _, state in ipairs(StateStack.states or {}) do
      if state.isBattle == true then return true end
    end
    return false
  end

  -- 1. cross-map journey: Sprout Tower 1F to an item ball on 3F
  L.teleport("SPROUT_TOWER_1F", 9, 13, "up")
  U.log("RESULT", "sprout =>", L.heard(), "at", L.where())
  local area = L.logBrowse("area")
  local target
  for _, item in ipairs(area) do
    if tostring(item.label):find("3F", 1, true) then target = item break end
  end
  target = target or area[1]
  local battles = 0
  local text = L.walkTo(target, { filter = "area", answer = "a", trace = true, limit = 6000,
    onFrame = function() if battleUp() then battles = battles + 1 end end })
  U.log("RESULT", "journey =>", text, "now", L.where(), "battle frames", battles)

  -- 2. trainer battle: Youngster Mikey (2,28) faces right with sight 3; from
  -- (4,26) every way south to the Cherrygrove exit crosses his line of sight
  L.teleport("ROUTE_30", 4, 26, "down")
  U.log("RESULT", "route 30 =>", L.heard(), "at", L.where())
  L.logBrowse("all")
  local north = L.find(function(i) return i.type == "connection" and i.direction == "south" end)
  battles = 0
  local sawBattle = false
  text = L.walkTo(north, { answer = "a", trace = true, limit = 9000, onFrame = function()
    if battleUp() then
      battles = battles + 1
      if not sawBattle then
        sawBattle = true
        U.log("RESULT", "battle on screen; walk paused =", tostring(not L.AutoWalk.walking()))
      end
    end
  end })
  U.log("RESULT", "trainer walk =>", text, "now", L.where(), "battle frames", battles)

  -- 3. Surf: New Bark Town's east shore to the Route 27 connection
  L.teleport("NEW_BARK_TOWN", 13, 6, "down")
  L.heard()
  local east = L.find(function(i) return i.type == "connection" and i.direction == "east" end)
  U.log("RESULT", "east item =>", east and east.description or "none")
  text = L.walkTo(east, { answer = "a", trace = true, limit = 4000 })
  U.log("RESULT", "surf walk =>", text, "now", L.where(),
    "surfing", tostring(require("src.world.gen2.FieldMoves").isSurfing(game.world.playerState)))

  -- 4. guided navigation (P) to a sign, then a step along it
  L.teleport("NEW_BARK_TOWN", 13, 6, "down")
  L.heard()
  local sign = L.find(function(i) return i.type == "signpost" end)
  L.select(sign)
  U.log("RESULT", "P =>", L.command("describe_route_to_selected_item"))
  for _ = 1, 30 do U.wait(1) end
  L.hold("down", 18)
  for _ = 1, 30 do U.wait(1) end
  U.log("RESULT", "after a step =>", L.heard(), "at", L.where())
  U.log("RESULT", "P again =>", L.command("describe_route_to_selected_item"))
  U.log("DONE")
end
