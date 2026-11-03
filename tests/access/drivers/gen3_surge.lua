-- FireRed auto-walk through Vermilion Gym's trash cans (SwitchWalk.lua, hidden switches):
-- one auto-walk to Lt. Surge from the gym's door, with A in battles from the harness.
-- Harness setup teleports and gives a party.  Silent; read the RESULT lines.
return function(game)
  local L = dofile("tests/access/drivers/gen3_nav_lib.lua").new(game)
  local U, AutoWalk = L.U, L.AutoWalk
  local SwitchWalk = require("src.access.nav.SwitchWalk")
  if not L.boot() then return end
  L.giveParty(9, 90, { "SURF", "STRENGTH", "CUT" }, { "SURF", "STRENGTH", "CUT", "FLASH" })
  local floor = "FR_VERMILION_CITY_GYM"
  local warp = game.data.maps[floor].warps[1]
  L.heal()
  L.teleport(floor, warp.x, warp.y - 1, "up")
  L.settle(120, true)
  local target, filterUsed
  for _, filter in ipairs({ "npcs", "people", "objects" }) do
    local ok, items = pcall(L.browse, filter)
    for _, item in ipairs(ok and type(items) == "table" and items or {}) do
      if tostring(item.label):find("Surge") then target, filterUsed = item, filter end
    end
    if target then break end
  end
  if not target then U.log("FAIL", "Lt. Surge is not listed") return end
  L.select(target, filterUsed)
  local nav = L.nav()
  local _, _, goals = pcall(nav.selectedRouteGoals, nav)
  U.log("RESULT", "before", "route", tostring(AutoWalk.routeExists(nav, goals)), "cans", #nav:hiddenSwitchSigns(nav:worldForCommand()))
  L.heard()
  AutoWalk.start(nav, game, L.adapter())
  U.log("RESULT", "started", tostring(SwitchWalk.active()), L.heard():sub(1, 100))
  local started = os.time()
  local presses, lastFlips, nopes, frames = 0, 0, 0, 0
  for frame = 1, 90000 do
    frames = frame
    if not SwitchWalk.active() and not AutoWalk.active() then break end
    if frame % 900 == 0 then L.heal() end
    local state = SwitchWalk._state()
    if state and state.flips ~= lastFlips then
      lastFlips = state.flips
      local heard = L.heard()
      U.log("RESULT", "press", state.flips, tostring(state.sign and state.sign.label), "anchor",
        tostring(state.anchor and state.anchor.label), heard:sub(-90))
    end
    if not L.battleStep() and frame % 15 == 0 and not (state and state.phase == "flipping") and L.messageOpen() then
      L.tap("a", 6)
    end
    U.wait(1)
  end
  local running = SwitchWalk.active() or AutoWalk.active()
  if running then
    SwitchWalk.stop() AutoWalk.stop()
    U.log("FAIL", "still going at the limit")
  end
  local nav2 = L.nav()
  local ok, _, goals2 = pcall(nav2.selectedRouteGoals, nav2)
  U.log("RESULT", "end", "frames", frames, "seconds", os.time() - started, "searches", lastFlips, "now", L.where(),
    "route", tostring(ok and AutoWalk.routeExists(nav2, goals2)), L.heard():sub(-120))
  U.log("DONE")
end
