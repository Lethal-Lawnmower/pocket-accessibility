-- FireRed auto-walk through boulder puzzles (BoulderWalk.lua, decision 41): on each
-- floor with pressure switches or boulder holes, one auto-walk to a boulder, with A
-- in battles from the harness.  Harness setup teleports and gives a party.  Silent;
-- read the RESULT lines.  GEN3_BOULDER_MAPS limits the floors.
return function(game)
  local L = dofile("tests/access/drivers/gen3_nav_lib.lua").new(game)
  local U, AutoWalk = L.U, L.AutoWalk
  local BoulderWalk = require("src.access.nav.BoulderWalk")
  if not L.boot() then return end
  L.giveParty(9, 90, { "SURF", "STRENGTH", "CUT", "HYDRO_PUMP" },
    { "SURF", "STRENGTH", "CUT", "WATERFALL", "FLASH" })
  game.options.firered = game.options.firered or {}
  game.options.firered.accessAutoWalkSpeed = 8
  local Puzzle = require("src.access.nav.gen3.PuzzleAssistance")
  local World = require("src.access.nav.gen3.World")
  local nav = L.nav()
  local floors = {}
  for id, def in pairs(game.data.maps) do
    if id:match("^FR_") and (not os.getenv("GEN3_BOULDER_MAPS") or os.getenv("GEN3_BOULDER_MAPS"):find(id, 1, true)) then
      local view = World.plannedView(game, def)
      local first = def.warps and def.warps[1]
      if view and first then
        local world = nav:regionalStaticWorld(id, { x = first.x, y = first.y })
        local ok, targets = pcall(Puzzle.targetsFor, world)
        if ok and targets then floors[#floors + 1] = { id = id, x = first.x, y = first.y } end
      end
    end
  end
  table.sort(floors, function(a, b) return a.id < b.id end)
  U.log("RESULT", "floors", #floors)
  for _, floor in ipairs(floors) do
    L.heal()
    -- a cell with the floor's boulders in reach, from gen3_nav_puzzle
    local starts = { FR_VICTORY_ROAD_1F = { 11, 19 }, FR_VICTORY_ROAD_2F = { 2, 12 }, FR_VICTORY_ROAD_3F = { 7, 4 } }
    local start = starts[floor.id]
    if start then
      L.teleport(floor.id, start[1], start[2], "up")
    else
      L.teleport(floor.id, floor.x, floor.y, "down")
      L.hold("down", 2)
    end
    L.settle(120, true)
    local target
    for _, item in ipairs(L.browse("all")) do
      if tostring(item.label):find("^Boulder %d") then target = target or item end
    end
    if not target then
      U.log("RESULT", floor.id, "no boulder listed at", L.where())
    else
      L.select(target, "all")
      L.heard()
      AutoWalk.start(L.nav(), game, L.adapter())
      local started = tostring(BoulderWalk.active())
      local pushes = 0
      for frame = 1, 25000 do
        if not BoulderWalk.active() and not AutoWalk.active() then break end
        if frame % 900 == 0 then L.heal() end
        local state = BoulderWalk._state()
        if state then pushes = state.pushes end
        if not L.battleStep() and frame % 15 == 0 and not (state and (state.phase == "strength" or state.phase == "settling")) and L.messageOpen() then
          L.tap("a", 6)
        end
        U.wait(1)
      end
      if BoulderWalk.active() or AutoWalk.active() then
        BoulderWalk.stop() AutoWalk.stop()
        U.log("FAIL", floor.id, "still pushing at the limit")
      end
      local spoken = L.heard()
      U.log("RESULT", floor.id, "started", started, "pushes", pushes, "now", L.where(), spoken:sub(-70))
      if not spoken:find("all in place", 1, true) then U.log("FAIL", floor.id, "floor not finished") end
    end
  end
  U.log("DONE")
end
