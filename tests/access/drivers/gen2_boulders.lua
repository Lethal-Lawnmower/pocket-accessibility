-- Gen 2 auto-walk through boulders (src/access/nav/BoulderWalk.lua): from Cianwood
-- Gym's door, one auto-walk to Chuck, with nothing else asked of the player but A
-- in battles.  Then the same with no Strength in the party and with the setting
-- off.  Harness setup teleports and gives a party.  Silent; read the RESULT lines.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U, AutoWalk = L.U, L.AutoWalk
  local BoulderWalk = require("src.access.nav.BoulderWalk")
  L.settle(2000, true)
  local badges = { "ZEPHYR", "HIVE", "PLAIN", "FOG", "MINERAL" }
  game.save.repelSteps = 60000
  local function chuck()
    for _, item in ipairs(L.browse("npcs")) do
      if tostring(item.label):find("Chuck", 1, true) then return item end
    end
  end
  local function refused(tag)
    L.teleport("CIANWOOD_GYM", 4, 16, "up")
    L.select(chuck(), "npcs")
    L.heard()
    AutoWalk.start(L.nav(), game, L.adapter())
    U.log("RESULT", tag, L.heard(), "pushing", tostring(BoulderWalk.active()))
    BoulderWalk.stop()
    AutoWalk.stop()
  end
  L.giveParty("RATTATA", 90, { "TACKLE" }, badges)
  refused("no Strength =>")
  L.giveParty("FERALIGATR", 90, { "STRENGTH", "SURF", "CUT", "WATERFALL" }, badges)
  game.options.accessAutoWalkBoulders = false
  refused("setting off =>")
  game.options.accessAutoWalkBoulders = nil

  L.teleport("CIANWOOD_GYM", 4, 16, "up")
  game.speedOverride = 4
  L.select(chuck(), "npcs")
  L.heard()
  AutoWalk.start(L.nav(), game, L.adapter())
  U.log("RESULT", "start", L.heard(), "pushing", tostring(BoulderWalk.active()))
  local pushes = 0
  for frame = 1, 30000 do
    if not BoulderWalk.active() and not AutoWalk.active() then break end
    local state = BoulderWalk._state()
    if state and state.pushes ~= pushes then
      pushes = state.pushes
      U.log("RESULT", "push", pushes, "player", L.where(), "phase", state.phase)
    end
    if frame % 15 == 0 and not (state and state.phase == "strength")
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
    U.log("FAIL", "still walking at the limit")
  end
  local spoken = L.heard()
  U.log("RESULT", "ended", L.where(), "pushes", pushes, spoken:sub(-120))
  if not spoken:find("Arrived at Chuck", 1, true) then U.log("FAIL", "did not reach Chuck") end
  U.log("DONE")
end
