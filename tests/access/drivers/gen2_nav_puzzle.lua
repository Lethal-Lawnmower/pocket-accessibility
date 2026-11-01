-- Strength puzzle help on Gen 2's two stone-table floors, Ice Path B1F and
-- Blackthorn Gym 2F: teleport there with a Strength user and the Plain Badge,
-- read the object list (boulders, holes, their state and next push), then
-- solve each floor only by following the hints the way a player would --
-- select the boulder, auto-walk to the pushing position it names, switch
-- Strength on by talking to a boulder, push once in the hinted direction,
-- and repeat until every hole is filled (gen2_nav_lib's solveStoneFloor).
-- Silent; read the RESULT lines.
-- GEN2_PUZZLE_MAPS=ICE_PATH_B1F (or BLACKTHORN_GYM_2F) limits the floors.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") return end
  L.giveParty("FERALIGATR", 60, { "STRENGTH", "SURF", "CUT", "WATERFALL" },
    { "ZEPHYR", "HIVE", "PLAIN", "FOG", "STORM", "MINERAL", "GLACIER", "RISING" })

  local floors = {
    { id = "ICE_PATH_B1F", x = 3, y = 14 },
    { id = "BLACKTHORN_GYM_2F", x = 2, y = 7 },
  }
  local only = os.getenv("GEN2_PUZZLE_MAPS")
  for _, floor in ipairs(floors) do
    if not only or only:find(floor.id, 1, true) then L.solveStoneFloor(floor) end
  end
  U.log("DONE")
end
