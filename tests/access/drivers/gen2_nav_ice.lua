-- Ice slides in auto-walk: Ice Path 1F from the Route 44 entrance to each
-- item ball and to both ladders down, at the game's speed and at 200X.
-- The route plans each slide as one move ("Move right onto ice; slide N
-- cells"); auto-walk lets go while the game slides the player and steers
-- again where the slide ends.  Silent; read the RESULT and PATH lines.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") return end
  for _, speed in ipairs({ false, 200 }) do
    game.options.accessAutoWalkSpeed = speed or nil
    L.teleport("ICE_PATH_1F", 5, 20, "up")
    U.log("RESULT", "speed", tostring(speed or "game"), "at", L.where(), "=>", L.heard())
    local targets = {}
    for _, item in ipairs(L.browse("all")) do
      if item.type == "object" and item.label ~= "Boulder" then targets[#targets + 1] = item end
      if item.type == "warp" and tostring(item.label):find("B1F", 1, true) then targets[#targets + 1] = item end
    end
    for _, target in ipairs(targets) do
      L.teleport("ICE_PATH_1F", 5, 20, "up")
      L.heard()
      local text = L.walkTo(target, { trace = true, answer = "a", limit = 4000 })
      U.log("RESULT", "to", target.label, "=>", text, "now", L.where())
    end
  end
  game.options.accessAutoWalkSpeed = nil
  U.log("DONE")
end
