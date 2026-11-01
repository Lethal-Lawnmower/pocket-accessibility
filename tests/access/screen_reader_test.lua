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
eq(Presenters.joinLines({ "This is my grand-", "son." }), "This is my grandson.",
  "split word rejoined")
eq(Presenters.joinLines({ "SUPER-", "POTION" }), "SUPER-POTION", "upper-case compound keeps its hyphen")
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

-- Chunk pacing: a line marked in contBefore waits for A, so speech stops
-- before it and speaks it only once the game moves lineIndex onto it.
reset()
local paced = setmetatable({ pageIndex = 1, lineIndex = 1,
  pages = { { "PIDGEY is trying", "to learn GUST!", "But PIDGEY can't", "learn more!" },
    contBefore = { { false, false, true, false } } } }, TextBox)
ScreenReader.update(paced)
eq(last().text, "PIDGEY is trying to learn GUST!", "first chunk stops at the A wait")
paced.lineIndex = 2
ScreenReader.update(paced)
eq(#spoken, 1, "typing the rest of a chunk says nothing new")
paced.lineIndex = 3
ScreenReader.update(paced)
eq(last().text, "But PIDGEY can't learn more!", "next chunk after the A press")
eq(last().interrupt, true, "a new chunk interrupts")
reset()
local instant = setmetatable({ pageIndex = 1, lineIndex = 4, pages = paced.pages }, TextBox)
ScreenReader.update(instant)
eq(last().text, "PIDGEY is trying to learn GUST! But PIDGEY can't learn more!",
  "an instant box speaks its whole page")

-- A word split across an A wait ("crea-" / wait / "tures") is finished in
-- the chunk before the wait; the next chunk starts after it.
reset()
local split = setmetatable({ pageIndex = 1, lineIndex = 1,
  pages = { { "This world is in-", "habited by crea-", "tures that we call", "POKéMON." },
    contBefore = { { false, false, true, true } } } }, TextBox)
ScreenReader.update(split)
eq(last().text, "This world is inhabited by creatures that we call", "split words finished across the wait")
split.lineIndex = 3
ScreenReader.update(split)
eq(#spoken, 1, "the line already spoken is not repeated after the A press")
split.lineIndex = 4
ScreenReader.update(split)
eq(last().text, "POKéMON.", "speech resumes with the next unspoken line")

-- Gen 2's yes/no fallback re-shows the question just spoken in a new
-- instant box with a choice: it stays quiet.  A new question on that path
-- (the egg's nickname prompt) is spoken.
reset()
local asked = setmetatable({ pageIndex = 1, lineIndex = 2,
  pages = { { "Would you like to", "test the prompt?" } } }, TextBox)
ScreenReader.update(asked)
eq(last().text, "Would you like to test the prompt?", "question spoken")
local count = #spoken
local reshown = setmetatable({ pageIndex = 1, lineIndex = 2, instant = true, choice = function() end,
  pages = { { "Would you like to", "test the prompt?" } } }, TextBox)
ScreenReader.update(reshown)
eq(#spoken, count, "re-shown question is not repeated")
local nickname = setmetatable({ pageIndex = 1, lineIndex = 2, instant = true, choice = function() end,
  pages = { { "Give a nickname to", "TOGEPI?" } } }, TextBox)
ScreenReader.update(nickname)
eq(last().text, "Give a nickname to TOGEPI?", "a new question on the same path is spoken")
eq(Presenters.speakable("a cute #MON"), "a cute POKéMON", "# is POKé")

-- A screen that changes and is covered in the same frame (Gen 2's box
-- screen: "Release PKMN?" plus the Yes/No box) says its change first through
-- its presenter's covered(), and the new top queues behind it.
reset()
do
  local Holder = {}
  Holder.__index = Holder
  local holderPresenter = {
    matches = function(s) return getmetatable(s) == Holder end,
    poll = function(s, memo) if memo.msg ~= s.message then memo.msg = s.message return s.message, true end end,
    covered = function(s, memo) if s.message ~= memo.msg then memo.msg = s.message return s.message end end,
  }
  table.insert(Presenters.ordered, 1, holderPresenter)
  local StateStack = package.loaded["src.core.StateStack"] or {}
  package.loaded["src.core.StateStack"] = StateStack
  local holder = setmetatable({ message = "BOX1" }, Holder)
  StateStack.states = { holder }
  ScreenReader.update()
  eq(last().text, "BOX1", "holder spoken")
  holder.message = "Release PKMN?"
  local yesNo = setmetatable({ index = 2, labels = { "YES", "NO" } }, ChoiceBox)
  StateStack.states = { holder, yesNo }
  ScreenReader.update()
  eq(spoken[#spoken - 1].text, "Release PKMN?", "covered screen's new message said first")
  eq(last().text, "NO", "the Yes/No selection follows")
  eq(last().interrupt, false, "and queues behind the question")
  table.remove(Presenters.ordered, 1)
  StateStack.states = nil
end

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
-- A dialogue box covered in the frame it opens (Yellow's instant elevator
-- prompt under the floor list) is spoken first, and the list queues behind.
reset()
local savedStack = package.loaded["src.core.StateStack"]
local map = { isOverworld = true }
local prompt = setmetatable({ pageIndex = 1, lineIndex = 2,
  pages = { { "Which floor do", "you want?" } } }, TextBox)
local floors = setmetatable({ index = 1, items = { { label = "1F" }, { label = "2F" } } }, ListMenu)
package.loaded["src.core.StateStack"] = { states = { map } }
ScreenReader.update(map)
package.loaded["src.core.StateStack"] = { states = { map, prompt, floors } }
ScreenReader.update(floors)
eq(spoken[1] and spoken[1].text, "Which floor do you want?", "covered prompt spoken")
eq(spoken[2] and spoken[2].text, "1F, 1 of 2", "list after it")
eq(spoken[2] and spoken[2].interrupt, false, "list queued behind the prompt")
package.loaded["src.core.StateStack"] = savedStack

reset()
ScreenReader.update(nil)
eq(#spoken, 0, "empty stack is silent")

Speech.shutdown()
T.finish()
