-- Screen speech: presenters for TextBox, Menu, ListMenu and ChoiceBox, and
-- ScreenReader's change detection.  States are bare tables carrying the real
-- upstream metatables, shaped like the fields those classes keep.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Speech = require("src.access.Speech")
local ScreenReader = require("src.access.screens.ScreenReader")
local Presenters = require("src.access.screens.Presenters")
local TextBox = require("src.render.TextBox")
local Menu = require("src.ui.Menu")
local ListMenu = require("src.ui.ListMenu")
local ChoiceBox = require("src.ui.ChoiceBox")

local spoken = {}
local fake = { name = "Fake" }
function fake:say(text, interrupt) spoken[#spoken + 1] = { text = text, interrupt = interrupt } return true end
function fake:stop() return true end
function fake:close() end
Speech.shutdown()
Speech.start({ backend = fake })

local function reset()
  for i = #spoken, 1, -1 do spoken[i] = nil end
  ScreenReader._resetForTests()
end
local function last() return spoken[#spoken] end

-- Row text: label plus the one detail the list draws.
eq(Presenters.rowText({ label = "POTION", count = 3 }), "POTION, quantity 3", "count row")
eq(Presenters.rowText({ label = "PIDGEY", level = 5 }), "PIDGEY, level 5", "level row")
eq(Presenters.rowText({ label = "POKé BALL", price = "¥200" }), "POKé BALL, ¥200", "price row")
eq(Presenters.rowText({ label = "CANCEL", cancel = true }), "CANCEL", "plain row")

-- Lines join with spaces, except a word split by a line-end hyphen.
eq(Presenters.joinLines({ "This is my grand-", "son." }), "This is my grand-son.",
  "split word rejoined")
eq(Presenters.joinLines({ "Hello", "there" }), "Hello there", "lines joined by a space")

-- Text box: whole page on entry and on each new page, interrupting.
reset()
local box = setmetatable({ pages = { { "Hello there!", "Welcome to the" }, { "world of POKéMON!" } },
  pageIndex = 1 }, TextBox)
ScreenReader.update(box)
eq(last().text, "Hello there! Welcome to the", "first page joined into one utterance")
eq(last().interrupt, true, "page interrupts")
ScreenReader.update(box)
eq(#spoken, 1, "same page is not repeated on later frames")
box.pageIndex = 2
ScreenReader.update(box)
eq(last().text, "world of POKéMON!", "second page spoken when it begins")

-- A Yes/No box over the page queues behind it, and closing it does not
-- make the question repeat.
local choice = setmetatable({ index = 1, labels = { "YES", "NO" } }, ChoiceBox)
ScreenReader.update(choice)
eq(last().text, "YES", "choice entry speaks the selection")
eq(last().interrupt, false, "choice entry queues after the question")
choice.index = 2
ScreenReader.update(choice)
eq(last().text, "NO", "choice move speaks the new selection")
eq(last().interrupt, true, "choice move interrupts")
local before = #spoken
ScreenReader.update(box)
eq(#spoken, before, "returning to the same page stays quiet")

-- Menu: position on entry and on return, label only while moving.
reset()
local menu = setmetatable({ index = 1, items = { { label = "POKéDEX" }, { label = "POKéMON" },
  { label = "ITEM" } } }, Menu)
ScreenReader.update(menu)
eq(last().text, "POKéDEX, 1 of 3", "menu entry includes position")
menu.index = 2
ScreenReader.update(menu)
eq(last().text, "POKéMON", "menu move says the label")
ScreenReader.update(box)
ScreenReader.update(menu)
eq(last().text, "POKéMON, 2 of 3", "returning to a menu repeats context")

-- List: title on entry, position always; empty lists say so.
reset()
local list = setmetatable({ title = "ITEM", index = 1,
  items = { { label = "POTION", count = 2 }, { label = "CANCEL", cancel = true } } }, ListMenu)
ScreenReader.update(list)
eq(last().text, "ITEM. POTION, quantity 2, 1 of 2", "list entry")
list.index = 2
ScreenReader.update(list)
eq(last().text, "CANCEL, 2 of 2", "list move")
reset()
ScreenReader.update(setmetatable({ title = "ITEM", index = 1, items = {} }, ListMenu))
eq(last().text, "ITEM. Empty", "empty list")

-- Unknown screens stay silent and cost nothing further.
reset()
ScreenReader.update({ someOtherScreen = true })
ScreenReader.update({ someOtherScreen = true })
eq(#spoken, 0, "unknown screens are silent")
ScreenReader.update(nil)
eq(#spoken, 0, "empty stack is silent")

Speech.shutdown()
T.finish()
