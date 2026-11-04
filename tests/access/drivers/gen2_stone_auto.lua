-- Gen 2 auto-walk filling stone-table floors (BoulderWalk.tryStone): on Ice Path B1F
-- and Blackthorn Gym 2F, one auto-walk to a hole fills the floor, with A in battles
-- from the harness.  Harness setup teleports and gives a party.  Silent; read the
-- RESULT lines.  GEN2_PUZZLE_MAPS limits the floors.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U, AutoWalk = L.U, L.AutoWalk
  local BoulderWalk = require("src.access.nav.BoulderWalk")
  L.settle(2000, true)
  L.strongParty()
  game.options.accessAutoWalkSpeed = 8
  local only = os.getenv("GEN2_PUZZLE_MAPS")
  for _, floor in ipairs({ { id = "ICE_PATH_B1F", x = 3, y = 14 }, { id = "BLACKTHORN_GYM_2F", x = 2, y = 7 } }) do
    if not only or only:find(floor.id, 1, true) then
      L.teleport(floor.id, floor.x, floor.y, "down")
      local hole
      for _, item in ipairs(L.browse("all")) do
        if tostring(item.label):find("^Hole %d") or tostring(item.label):find("^Drop") then
          hole = hole or item
        end
      end
      if not hole then
        U.log("FAIL", floor.id, "no hole listed")
      else
        L.select(hole, "all")
        L.heard()
        AutoWalk.start(L.nav(), game, L.adapter())
        U.log("RESULT", floor.id, "target", hole.label, "start", L.heard(), "pushing", tostring(BoulderWalk.active()))
        local pushes = 0
        for frame = 1, 60000 do
          if not BoulderWalk.active() and not AutoWalk.active() then break end
          local state = BoulderWalk._state()
          if state then pushes = state.pushes end
          if frame % 15 == 0 and not (state and (state.phase == "strength" or state.phase == "settling"))
             and (game.stack:top() ~= nil or not game.world:acceptsMenuInput()) then
            game.input.pressQueue[#game.input.pressQueue + 1] = "a"
            game.input.state.a = true
            U.wait(2)
            game.input.state.a = false
          end
          U.wait(1)
        end
        if BoulderWalk.active() or AutoWalk.active() then
          BoulderWalk.stop() AutoWalk.stop()
          U.log("FAIL", floor.id, "still pushing at the limit")
        end
        local spoken = L.heard()
        U.log("RESULT", floor.id, "ended", L.where(), "pushes", pushes, spoken:sub(-70))
        if not spoken:find("The boulders are all in place", 1, true) then
          U.log("FAIL", floor.id, "floor not filled")
        end
        -- the way on: Ice Path's lower floors open only once the holes are filled
        if floor.id == "ICE_PATH_B1F" then
          local next = L.find(function(i) return i.label == "Ice Path B3F" end, "area")
          if next then
            L.select(next, "area")
            L.heard()
            AutoWalk.start(L.nav(), game, L.adapter())
            L.runWalk(30000)
            local trip = L.heard()
            U.log("RESULT", floor.id, "journey to Ice Path B3F ended", L.where(), trip:sub(-70))
            if not L.where():find("ICE_PATH_B3F", 1, true) then U.log("FAIL", "did not reach Ice Path B3F") end
          end
        end
      end
    end
  end
  U.log("DONE")
end
