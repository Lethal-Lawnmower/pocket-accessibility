-- Gen 2 chase: walks to the Ilex Forest Farfetch'd, talks to it once the way
-- the player does, then lets auto-walk keep after it (src/access/nav/Chase.lua).
-- Harness setup teleports, gives a party and clears the bird's hidden flag;
-- A in the game's text is the harness standing in for the player.  Silent;
-- read the RESULT lines.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local Chase = require("src.access.nav.Chase")
  local AutoWalk = L.AutoWalk
  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") return end
  L.giveParty("FERALIGATR", 60, { "SURF", "STRENGTH", "CUT", "WATERFALL" }, { "ZEPHYR", "HIVE" })
  -- a level 60 lead keeps a Repel going, so wild battles do not use up its moves
  game.save.repelSteps = 60000
  L.teleport("ILEX_FOREST", 5, 31, "up")
  local world = game.world
  -- arrive the way the player does, on the warp from Azalea's gate
  local startX, startY = 5, 31
  for _, warp in ipairs(world.map.def.warps or {}) do
    if warp.destMap == "ILEX_FOREST_AZALEA_GATE" then startX, startY = warp.x, warp.y end
  end
  local FlagNames = require("src.core.gen2.FlagNames")
  local flag = FlagNames.events and FlagNames.events.EVENT_ILEX_FOREST_FARFETCHD_1 or 1769
  pcall(function() world.events:set(flag, false) end)
  L.teleport("ILEX_FOREST", startX, startY - 1, "up")

  local function bird()
    for _, item in ipairs(L.logBrowse("all")) do
      if tostring(item.label):find("Farfetch", 1, true) then return item end
    end
  end
  local target = bird()
  if not target then U.log("FAIL", "no Farfetch'd in the object list") return end
  U.log("RESULT", "start", target.label, target.x, target.y, "at", L.where())
  U.log("RESULT", "walk =>", L.walkTo(target, { limit = 12000, answer = "a" }), "at", L.where())

  -- the player's own first talk
  L.select(target, "all")
  local world0 = game.world
  local dx, dy = target.x - world0.player.cellX, target.y - world0.player.cellY
  local dir = math.abs(dx) > math.abs(dy) and (dx > 0 and "right" or "left") or (dy > 0 and "down" or "up")
  L.tap(dir, 12)
  L.tap("a", 30)
  L.settle(600, true, 40)
  local moved = bird()
  U.log("RESULT", "after first talk", moved and moved.x, moved and moved.y, "=>", L.heard())

  local seen = AutoWalk._lastArrival()
  U.log("RESULT", "arrival note", seen and seen.id, seen and seen.x, seen and seen.y,
    seen and seen.targetX, seen and seen.targetY, "item", moved and moved.id, "at", L.where())
  -- the selection is left as the player would leave it, even if the id changed
  AutoWalk.start(L.nav(), game, L.adapter())
  U.log("RESULT", "chase started", Chase.active(), L.heard())
  local lastCell, presses = nil, 0
  for frame = 1, 40000 do
    if not Chase.active() and not AutoWalk.active() then break end
    if game.stack:top() ~= nil or not world.acceptsMenuInput or not world:acceptsMenuInput() then
      if frame % 20 == 0 then
        game.input.pressQueue[#game.input.pressQueue + 1] = "a"
        game.input.state.a = true
        U.wait(2)
        game.input.state.a = false
      end
    end
    local state = Chase._state()
    if state and state.presses ~= presses then
      presses = state.presses
      local now = bird()
      local cell = now and (now.x .. "," .. now.y) or "gone"
      U.log("RESULT", "press", presses, "bird", cell, "player", L.where(), "goal",
        state.goal and (state.goal.x .. "," .. state.goal.y))
      lastCell = cell
    end
    U.wait(1)
  end
  if Chase.active() then Chase.stop() U.log("FAIL", "chase still running at the limit") end
  local final = bird()
  U.log("RESULT", "ended =>", L.heard(), "bird", final and final.x, final and final.y, "last", lastCell)
  U.wait(60)
  L.settle(600, true, 40)
  U.log("RESULT", "after =>", L.heard(), "at", L.where())
  local herded = FlagNames.events and FlagNames.events.EVENT_HERDED_FARFETCHD or 41
  U.log("RESULT", "game says herded", world.events:get(herded))
  U.log("DONE")
end
