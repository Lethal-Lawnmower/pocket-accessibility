-- Hoenn record windows (screens/gen3/HoennSpecial.lua frontierRecords): a window of
-- rse/frontier_records.lua is read from its `prints` { s, x, y } in reading order.
-- The Ranking Hall's link multi rows draw their two names a line above and a line
-- below the rank, which must not be read as lines of their own around it.
-- Run: luajit tests/access/hoenn_special_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness")
local eq = T.eq

local Special = require("src.access.screens.gen3.HoennSpecial")

local function read(prints)
  local text = Special.frontierRecords.poll({ window = { prints = prints } }, {})
  return text
end

-- buildRankingHall: the title row, then a rank every 40 pixels
eq(read({
  { s = "BATTLE TOWER SINGLE", x = 0, y = 1 }, { s = "LV. 50", x = 172, y = 1 },
  { s = "1.", x = 8, y = 33 }, { s = "ROXIE", x = 24, y = 33 }, { s = "Win streak: 42", x = 120, y = 33 },
  { s = "2.", x = 8, y = 73 }, { s = "3.", x = 8, y = 113 },
}), "BATTLE TOWER SINGLE LV. 50. 1. ROXIE Win streak: 42. 2. empty. 3. empty",
  "a hall row with a name; a rank with no record is an empty row")

eq(read({
  { s = "BATTLE TOWER LINK", x = 0, y = 1 }, { s = "LV. 50", x = 172, y = 1 },
  { s = "ROXIE", x = 24, y = 25 }, { s = "1.", x = 8, y = 33 }, { s = "Win streak: 17", x = 120, y = 33 },
  { s = "WALLY", x = 40, y = 41 },
  { s = "2.", x = 8, y = 73 }, { s = "3.", x = 8, y = 113 },
}), "BATTLE TOWER LINK LV. 50. 1. ROXIE and WALLY Win streak: 17. 2. empty. 3. empty",
  "link multi: the two names drawn above and below the rank are said after it")

-- lines 8 pixels apart that are not a rank with names stay lines of their own
eq(read({
  { s = "RESULTS", x = 0, y = 1 }, { s = "LV. 50", x = 8, y = 25 },
  { s = "PREV.", x = 8, y = 33 }, { s = "Win streak: 0", x = 80, y = 33 }, { s = "OPEN LV.", x = 8, y = 41 },
}), "RESULTS. LV. 50. PREV. Win streak: 0. OPEN LV.", "other windows keep their lines")

-- a row of dashes is a rule and is not said
eq(read({ { s = "RESULTS", x = 0, y = 1 }, { s = "------", x = 0, y = 9 }, { s = "120BP", x = 0, y = 17 } }),
  "RESULTS. 120 BP", "a rule is skipped; BP is set off from its number")

T.finish()
