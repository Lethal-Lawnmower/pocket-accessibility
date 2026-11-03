-- Gen 2 cross-floor journeys: the Olivine Lighthouse, whose floors have sides
-- reached only through drops.  Area lists each other floor; auto-walk goes up
-- and down from any side.  Harness setup teleports and gives a party, and A
-- stands in for the player in battles and text.  Silent; read the RESULT lines.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U, AutoWalk = L.U, L.AutoWalk
  L.settle(2000, true)
  L.giveParty("FERALIGATR", 90, { "SURF", "STRENGTH", "CUT", "WATERFALL" }, { "ZEPHYR", "HIVE", "PLAIN", "FOG" })
  game.save.repelSteps = 60000
  local function journey(map, x, y, label)
    -- a fresh lead for each walk: trainers on the way use up its moves
    L.giveParty("FERALIGATR", 90, { "SURF", "STRENGTH", "CUT", "WATERFALL" }, { "ZEPHYR", "HIVE", "PLAIN", "FOG" })
    L.teleport(map, x, y, "up")
    while game.stack:top() do game.stack:pop() end
    U.wait(20)
    local target
    for _, item in ipairs(L.browse("area")) do
      if item.label == label then target = item end
    end
    if not target then U.log("FAIL", "not listed", label, "from", map) return end
    L.select(target, "area")
    L.heard()
    AutoWalk.start(L.nav(), game, L.adapter())
    for frame = 1, 30000 do
      if not AutoWalk.active() then break end
      if frame % 15 == 0 and (game.stack:top() ~= nil or not game.world:acceptsMenuInput()) then
        game.input.pressQueue[#game.input.pressQueue + 1] = "a"
        game.input.state.a = true
        U.wait(2)
        game.input.state.a = false
      end
      U.wait(1)
    end
    if AutoWalk.active() then AutoWalk.stop() U.log("FAIL", "still walking to", label) end
    local ended = L.where()
    local spoken = L.heard()
    U.log("RESULT", map, "to", label, "ended", ended, spoken:sub(-60))
    local floor = label:gsub("Olivine Lighthouse ", "OLIVINE_LIGHTHOUSE_")
    if not ended:find(floor, 1, true) then U.log("FAIL", "did not reach", label) end
  end
  journey("OLIVINE_LIGHTHOUSE_1F", 10, 15, "Olivine Lighthouse 6F")
  journey("OLIVINE_LIGHTHOUSE_5F", 3, 6, "Olivine Lighthouse 6F")
  journey("OLIVINE_LIGHTHOUSE_6F", 9, 14, "Olivine Lighthouse 1F")
  journey("OLIVINE_LIGHTHOUSE_3F", 13, 4, "Olivine Lighthouse 5F")
  U.log("DONE")
end
