-- Gen 2 navigation, first leg (Crystal first, then Gold and Silver): from the
-- bedroom of a fresh driver save, the object list and commands, auto-walk
-- downstairs and outside, across New Bark Town to Route 29 and to a sign.
-- Silent (POKEPORT_ACCESS_SILENT=1); read the RESULT lines and the trace.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") return end
  U.wait(30)
  if not L.nav() then U.log("FAIL", "no navigation coordinator on", L.where()) return end
  U.log("RESULT", "start", L.where(), "generation", tostring(L.nav().generation))
  U.log("RESULT", "startup =>", L.heard())
  U.log("RESULT", "M =>", L.command("read_map_name"))
  U.log("RESULT", "Y =>", L.command("read_player_position"))
  U.log("RESULT", "Q =>", L.command("read_game_time"))
  U.log("RESULT", "E =>", L.command("read_collision_tiles"))
  U.log("RESULT", "next filter =>", L.command("next_item_filter"))
  U.log("RESULT", "next item =>", L.command("next_map_item"))
  L.logBrowse("all")

  -- the stairs
  local stairs = L.find(function(i) return i.type == "warp" end)
  U.log("RESULT", "walk to stairs =>", L.walkTo(stairs, { trace = true, answer = "a" }), "now", L.where())
  L.settle(600, true)
  U.log("RESULT", "downstairs =>", L.heard(), "now", L.where())
  L.logBrowse("all")
  -- Mom stops the player on the way out (her scene): the walk pauses while
  -- she talks (the driver answers her) and resumes afterwards
  local function exitWarp()
    return L.find(function(i) return i.type == "warp" and tostring(i.label):find("New Bark", 1, true) end)
  end
  for attempt = 1, 3 do
    if L.pos() ~= "PLAYERS_HOUSE_1F" then break end
    U.log("RESULT", "walk outside, attempt " .. attempt .. " =>",
      L.walkTo(exitWarp(), { trace = true, answer = "a" }), "now", L.where())
    L.settle(900, true)
  end
  U.wait(30)
  U.log("RESULT", "outside =>", L.heard(), "now", L.where())
  L.logBrowse("all")

  -- the teacher stops a player leaving New Bark Town before Elm's errand
  -- (scene 0); the driver moves the town past it, as the story would
  game.world.mapScenes = game.world.mapScenes or {}
  game.world.mapScenes.NEW_BARK_TOWN = 1
  local sign = L.find(function(i) return i.type == "signpost" end)
  U.log("RESULT", "walk to sign =>", L.walkTo(sign, { trace = true, answer = "a" }), "now", L.where(),
    "facing", tostring(game.world.player.facing))
  L.settle(300, true)
  local west = L.find(function(i) return i.type == "connection" and i.direction == "west" end)
  U.log("RESULT", "walk to west connection =>", L.walkTo(west, { trace = true, answer = "a" }), "now", L.where())
  -- auto-walk stops on the edge cell, as in Gen 1; the player steps over
  L.hold("left", 20)
  L.settle(600, true)
  U.wait(30)
  U.log("RESULT", "on route =>", L.heard(), "now", L.where())
  U.log("RESULT", "M =>", L.command("read_map_name"))
  L.logBrowse("all")

  -- AUTO-WALK SPEED 200X across Route 29 (its ledges hop south) to the
  -- Cherrygrove connection
  game.options.accessAutoWalkSpeed = 200
  local speeds = {}
  local cherry = L.find(function(i) return i.type == "connection" and i.direction == "west" end)
  local text = L.walkTo(cherry, { trace = true, answer = "a", onFrame = function()
    if L.AutoWalk.walking() then speeds[game:logicSpeed()] = true end
  end })
  local list = {}
  for s in pairs(speeds) do list[#list + 1] = s end
  table.sort(list)
  U.log("RESULT", "200X walk =>", text, "now", L.where(), "speeds", table.concat(list, ","),
    "after", game:logicSpeed())
  game.options.accessAutoWalkSpeed = nil

  -- a ledge on purpose: from above the first ledge row, to a cell below it
  local id, px, py = L.pos()
  U.log("RESULT", "M =>", L.command("read_map_name"), "at", id, px, py)
  U.log("DONE")
end
