-- FireRed auto-walk through Secret Switches (SwitchWalk.lua, decision 41): on each
-- Pokemon Mansion floor, one auto-walk to every target that has no route, with A in
-- battles from the harness.  Harness setup teleports and gives a party.  Silent;
-- read the RESULT lines.
return function(game)
  local L = dofile("tests/access/drivers/gen3_nav_lib.lua").new(game)
  local U, AutoWalk = L.U, L.AutoWalk
  local SwitchWalk = require("src.access.nav.SwitchWalk")
  if not L.boot() then return end
  L.giveParty(9, 90, { "SURF", "STRENGTH", "CUT" }, { "SURF", "STRENGTH", "CUT", "FLASH" })
  L.setVar(0x4020, 60000) -- a long Repel: the switches, not wild battles, are under test
  for _, floor in ipairs({ "FR_POKEMON_MANSION_1F", "FR_POKEMON_MANSION_2F", "FR_POKEMON_MANSION_3F", "FR_POKEMON_MANSION_B1F" }) do
    local warp = game.data.maps[floor].warps[1]
    L.heal()
    L.teleport(floor, warp.x, warp.y - 1, "up")
    L.settle(120, true)
    U.log("RESULT", "== floor", L.where(), "switches", #L.nav():switchSigns(L.nav():worldForCommand()))
    for _, filter in ipairs({ "objects", "warps" }) do
      for _, item in ipairs(L.browse(filter)) do
        L.select(item, filter)
        local nav = L.nav()
        local ok, it, goals = pcall(nav.selectedRouteGoals, nav)
        if ok and type(goals) == "table" and #goals > 0 and not AutoWalk.routeExists(nav, goals) then
          L.heard()
          AutoWalk.start(nav, game, L.adapter())
          local started = tostring(SwitchWalk.active())
          local flips = 0
          for frame = 1, 16000 do
            if not SwitchWalk.active() and not AutoWalk.active() then break end
            if frame % 900 == 0 then L.heal() end
            local state = SwitchWalk._state()
            if state then flips = state.flips end
            if not L.battleStep() and frame % 15 == 0 and not (state and state.phase == "flipping") and L.messageOpen() then
              L.tap("a", 6)
            end
            U.wait(1)
          end
          if SwitchWalk.active() or AutoWalk.active() then
            SwitchWalk.stop() AutoWalk.stop()
            U.log("FAIL", item.label, "still going at the limit")
          end
          U.log("RESULT", filter, tostring(item.description):sub(1, 40), "trying", started, "flips", flips, "now", L.where(), L.heard():sub(-60))
          L.teleport(floor, warp.x, warp.y - 1, "up")
          L.settle(120, true)
        end
      end
    end
  end
  U.log("DONE")
end
