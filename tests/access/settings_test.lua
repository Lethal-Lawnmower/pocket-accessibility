-- Accessibility settings page (decision 26): the rows cycle and persist in
-- save.options, auto-walk speed is applied only while walking and handed
-- back afterwards, and DIALOGUE SPEECH switches a dialogue box between
-- chunk-by-chunk and all at once.  Fake game; no upstream screens.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness")
local check, eq = T.check, T.eq

local Settings = require("src.access.Settings")
local WalkSpeed = require("src.access.nav.WalkSpeed")
local GameSpeed = require("src.core.GameSpeed")

local game = { save = { options = {} } }
local rows = Settings.rows()
local speedRow, dialogueRow = rows[1], rows[2]

-- auto-walk speed row
eq(speedRow.label, "AUTO-WALK SPEED", "speed row label")
eq(speedRow.value(game), "GAME SPEED", "default is the game's own speed")
eq(Settings.autoWalkSpeed(game), nil, "no override by default")
speedRow.step(game, 1)
eq(speedRow.value(game), "NORMAL", "first step is NORMAL")
eq(game.save.options.accessAutoWalkSpeed, 1, "stored as a speed level")
speedRow.step(game, 1)
eq(speedRow.value(game), "2X", "then the game's ladder")
speedRow.step(game, -1) speedRow.step(game, -1)
eq(speedRow.value(game), "GAME SPEED", "back to GAME SPEED")
eq(game.save.options.accessAutoWalkSpeed, nil, "GAME SPEED clears the key")
speedRow.step(game, -1)
local top = GameSpeed.LEVELS[#GameSpeed.LEVELS]
eq(speedRow.value(game), GameSpeed.levelLabel(top), "wraps to the fastest level")

-- walk speed hand-off
WalkSpeed._resetForTests()
game.speedOverride = nil
WalkSpeed.update(game, true)
eq(game.speedOverride, top, "applied while walking")
WalkSpeed.update(game, false)
eq(game.speedOverride, nil, "restored when the walk pauses or ends")
game.speedOverride = 4
WalkSpeed.update(game, true)
eq(game.speedOverride, top, "overrides a run speed while walking")
WalkSpeed.update(game, false)
eq(game.speedOverride, 4, "and gives the previous value back")
WalkSpeed.update(game, true)
game.speedOverride = 30 -- skin fast-forward took the field mid-walk
WalkSpeed.update(game, true)
WalkSpeed.update(game, false)
eq(game.speedOverride, 30, "a value someone else set is left alone")
game.save.options.accessAutoWalkSpeed = nil
game.speedOverride = nil
WalkSpeed.update(game, true)
eq(game.speedOverride, nil, "GAME SPEED never touches the field")

-- dialogue row and presenter
eq(dialogueRow.value(game), "PAGE BY PAGE", "dialogue default")
dialogueRow.step(game, 1)
eq(dialogueRow.value(game), "ALL AT ONCE", "dialogue toggles")
eq(game.save.options.accessDialogue, "whole", "stored")

local TextBox = {}
TextBox.__index = TextBox
package.loaded["src.render.TextBox"] = TextBox
local Presenters = require("src.access.screens.Presenters")
local box = setmetatable({ game = game, pageIndex = 1, lineIndex = 1,
  pages = { { "Hello there!", "Welcome to the" }, { "world of POKEMON!" },
            contBefore = { { [2] = true } } } }, TextBox)
local memo = {}
local text = Presenters.textBox.poll(box, memo, true)
check(text and text:find("Hello there!", 1, true) and text:find("world of POKEMON!", 1, true),
  "all at once speaks every page: " .. tostring(text))
box.pageIndex, box.lineIndex = 2, 1
eq(Presenters.textBox.poll(box, memo, false), nil, "nothing more for that box")

dialogueRow.step(game, 1)
eq(game.save.options.accessDialogue, nil, "back to page by page")
memo = {}
box.pageIndex, box.lineIndex = 1, 1
eq(Presenters.textBox.poll(box, memo, true), "Hello there!", "page by page speaks the first chunk")

T.finish("accessibility settings")
