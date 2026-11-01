-- Presenters for PC-port additions: the in-game mod manager and the save
-- load report.  Bare tables with the real upstream metatables and stubbed
-- row methods.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Speech = require("src.access.Speech")
local SR = require("src.access.screens.ScreenReader")

local spoken = {}
local fake = { name = "Fake" }
function fake:say(text, interrupt) spoken[#spoken + 1] = { text = text, interrupt = interrupt } return true end
function fake:stop() return true end
function fake:close() end
Speech.shutdown()
Speech.start({ backend = fake })
local function reset() for i = #spoken, 1, -1 do spoken[i] = nil end SR._resetForTests() end
local function last() return spoken[#spoken] and spoken[#spoken].text end

local ManagerState = require("src.mods.ManagerState")
local jukebox = { id = "jukebox", name = "JUKEBOX", version = "1.2", enabled = true,
  description = "Plays music anywhere." }
local broken = { id = "broken", name = "BROKEN MOD", enabled = true, error = "bad file" }
local rows = {
  { header = true, label = "AUDIO" },
  { mod = jukebox, label = "JUKEBOX" },
  { mod = broken, label = "BROKEN MOD" },
}
local mgr = setmetatable({ screen = "list", tab = 1, cursor = 2 }, ManagerState)
mgr.rowsForScreen = function() return rows end
mgr.isStaged = function() return false end
mgr.runsHere = function() return true end

reset()
SR.update(mgr)
eq(last(), "Mod manager, Mods tab. JUKEBOX, enabled, 1 of 2", "manager entry")
mgr.cursor = 3
SR.update(mgr)
eq(last(), "BROKEN MOD, error, 2 of 2", "row with an error")
mgr.tab = 2
SR.update(mgr)
check(last():find("^Mod manager, Profiles tab") ~= nil, "tab change announced")

mgr.tab, mgr.screen, mgr.currentMod, mgr.cursor = 1, "detail", jukebox, 1
rows = { { label = "DISABLE" }, { label = "OPTIONS.." } }
SR.update(mgr)
eq(last(), "JUKEBOX 1.2. enabled. Plays music anywhere. DISABLE, 1 of 2", "detail page")

mgr.overlay = { kind = "confirm", lines = { "Disable", "JUKEBOX?" }, index = 1 }
SR.update(mgr)
eq(last(), "Disable JUKEBOX?. YES", "confirm overlay")
mgr.overlay.index = 2
SR.update(mgr)
eq(last(), "NO", "confirm overlay move")
mgr.overlay = nil
SR.update(mgr)
check(last():find("^JUKEBOX 1.2") ~= nil, "closing the overlay repeats context")

mgr.notice = "Restart to apply"
SR.update(mgr)
eq(last(), "Restart to apply", "notice spoken")

local volume = "LOUD"
mgr.screen, mgr.cursor, mgr.notice = "options", 1, mgr.notice
mgr.optionRows = { { label = "VOLUME", value = function() return volume end } }
SR.update(mgr)
eq(last(), "Options for JUKEBOX. VOLUME, LOUD, 1 of 1", "options page")
volume = "QUIET"
SR.update(mgr)
eq(last(), "QUIET", "option value change")

reset()
SR.update(setmetatable({ lines = { "1 BOX MON MOVED", "TO QUARANTINE" } }, require("src.ui.QuarantineReport")))
eq(last(), "Save load report. 1 BOX MON MOVED. TO QUARANTINE", "load report")

-- Cable club (LinkState): stages, address entry, trade cursor and choices.
local LinkState = require("src.link.LinkState")
package.loaded["src.link.CodeEntry"] = { text = function(addr) return addr.value end }
local game = { data = { text = { CancelTextString = "CANCEL", WaitingText = "Waiting...!",
  ["TradeCenter_SelectMon.statsTrade"] = "STATS     TRADE",
  ["TwoOptionMenuStrings.TradeCancelMenu"] = "TRADE\nCANCEL" } },
  save = { party = { { species = "PIDGEY" }, { species = "RATTATA" } } } }
reset()
local link = setmetatable({ game = game, stage = "menu", index = 1 }, LinkState)
package.loaded["src.link.Net"] = { defaultPort = function() return 7777 end }
SR.update(link)
eq(last(), "Link cable. HOST A GAME. UDP port 7777", "link menu")
link.index = 2
SR.update(link)
eq(last(), "Link cable. JOIN A GAME. UDP port 7777", "link menu move")
link.stage, link.addr, link.status = "addrEntry", { value = "192.168.1.5  " }, ""
SR.update(link)
eq(last(), "Enter host address: 192.168.1.5", "address entry")
link.stage, link.side, link.index = "trade", "mine", 1
link.trade = { theirParty = { { species = "PIDGEY" } }, canPick = function() return true end }
link.listLabel = function(_, mon) return mon and mon.species or "" end
SR.update(link)
eq(last(), "yours, PIDGEY, 1 of 2", "trade cursor on your party")
link.pickChoice = 2
SR.update(link)
eq(last(), "TRADE", "trade pick choice")
link.pickChoice, link.willText = nil, { lines = { "Trade PIDGEY", "for PIDGEY?" }, done = true }
SR.update(link)
eq(last(), "Trade PIDGEY for PIDGEY?", "trade message window")
link.trade.stage, link.confirmChoice = "confirming", 2
SR.update(link)
eq(last(), "CANCEL", "trade confirm choice")

-- Union Room prep: page title, body and focused item from the page model.
local Prep = require("src.ui.union.prep.Gen1BattlePrep")
local page = { title = "BATTLE RULES", lines = { "Level 50" }, info = { "3 vs 3" },
  items = { { label = "READY" }, { label = "CHANGE", disabled = true } }, cursor = 1 }
local model = { page = function() return page end, label = function(_, t) return t end,
  formatLines = function(_, l) return l or {} end }
reset()
local prep = setmetatable({ game = game, model = model }, Prep)
SR.update(prep)
eq(last(), "BATTLE RULES. Level 50 3 vs 3. READY, 1 of 2", "union prep page")
page.cursor = 2
SR.update(prep)
eq(last(), "CHANGE, unavailable, 2 of 2", "union prep move")

-- Pikachu reactions: the emote image is traced to its emotion number.
local Overworld = require("src.access.screens.Overworld")
local OverworldState = { isOverworld = true }
package.loaded["src.world.OverworldController"] = OverworldState
package.loaded["src.core.Game"] = { data = { field = { pikachu = {
  pics = { [4] = { image = "pikapic_happy.png" } },
  emotions = { [4] = { { op = "pikapic", script = 4 } } } } } } }
reset()
SR.update(OverworldState)
eq(#spoken, 0, "overworld without a reaction is silent")
OverworldState.emote = { pikaPic = "pikapic_happy.png" }
SR.update(OverworldState)
eq(last(), "Pikachu is happy", "Pikachu reaction named")
OverworldState.emote = { pikaPic = "pikapic_happy.png" }
SR.update(OverworldState)
eq(#spoken, 1, "same picture after the cry is not repeated")
eq(Overworld.EMOTION_WORDS[11], "is asleep", "emotion 11 is sleep, as upstream uses it")

Speech.shutdown()
T.finish()
