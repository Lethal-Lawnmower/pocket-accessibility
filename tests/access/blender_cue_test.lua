-- The Berry Blender's "press now" tone (screens/gen3/HoennContest.lua blenderCue):
-- once per lap, a fixed number of frames before the arrow reaches the middle of the
-- player's BEST range, read from the game's own arrow and hit ranges.
-- Run: luajit tests/access/blender_cue_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness")
local eq = T.eq

local Contest = require("src.access.screens.gen3.HoennContest")
local cues = 0
package.loaded["src.access.nav"] = { coordinator = function()
  return { cue = function(_, id) if id == "blender" then cues = cues + 1 end return true end }
end }

-- player 0 on arrow 1, whose range starts at 100: BEST's middle is arrowPos 100 * 256
local g = { gameEndState = 0, speed = 256, arrowPos = 0, localPlayerId = 0,
  playerIdToArrowId = { [0] = 0 }, T = { arrowHitRangeStart = { 100, 50, 150, 200 } } }
local memo = {}
local lead = Contest.BLENDER_LEAD_FRAMES
local middle = 100 * 256

local firstAt
for frame = 1, 2 * 256 + 10 do
  Contest.blenderCue(g, memo)
  if cues == 1 and not firstAt then firstAt = g.arrowPos end
  g.arrowPos = (g.arrowPos + g.speed) % 0x10000
end
eq(cues, 2, "one tone a lap (two laps)")
eq((middle - firstAt) / g.speed, lead, "the tone comes the lead's frames before the middle of BEST")

-- nothing once play has ended, or before the arrow moves
cues = 0
g.gameEndState = 1
Contest.blenderCue(g, {})
g.gameEndState, g.speed, g.arrowPos = 0, 0, middle - 256
Contest.blenderCue(g, {})
eq(cues, 0, "no tone when play has ended or the arrow is still")

T.finish()
