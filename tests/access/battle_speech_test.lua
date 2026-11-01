-- Battle speech: messages, the main menu with both sides' HP, move select
-- and mimic.  The state is a bare table with BattleState's real metatable,
-- shaped like the fields drawTextArea reads.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Speech = require("src.access.Speech")
local SR = require("src.access.screens.ScreenReader")
local Battle = require("src.access.screens.Battle")
local BattleState = require("src.battle.BattleState")

local spoken = {}
local fake = { name = "Fake" }
function fake:say(text, interrupt) spoken[#spoken + 1] = { text = text, interrupt = interrupt } return true end
function fake:stop() return true end
function fake:close() end
Speech.shutdown()
Speech.start({ backend = fake })
SR._resetForTests()
local function last() return spoken[#spoken] end

local data = {
  pokemon = { SQUIRTLE = { name = "SQUIRTLE" }, PIDGEY = { name = "PIDGEY" } },
  moves = { TACKLE = { name = "TACKLE", type = "NORMAL", pp = 35 },
    TAIL_WHIP = { name = "TAIL WHIP", type = "NORMAL", pp = 30 } },
}
local battle = setmetatable({
  data = data, phase = "messages", menuIndex = 1, moveIndex = 1,
  player = { mon = { species = "SQUIRTLE", level = 5, hp = 18, stats = { hp = 20 } },
    curMoves = { { id = "TACKLE", pp = 34 }, { id = "TAIL_WHIP", pp = 30 } } },
  enemy = { mon = { species = "PIDGEY", level = 3, hp = 7, stats = { hp = 14 } } },
}, BattleState)

eq(Battle.speakable("Enemy PIDGEY\nused GUST!"), "Enemy PIDGEY used GUST!", "lines join")
eq(Battle.speakable("super-\neffective"), "super-effective", "hyphenated word rejoined")

-- Messages: each new message once, queued.
battle.current = { text = "Wild PIDGEY\nappeared!" }
SR.update(battle)
eq(last().text, "Wild PIDGEY appeared!", "first message")
eq(last().interrupt, false, "battle messages queue")
SR.update(battle)
eq(#spoken, 1, "same message not repeated")
battle.current = { text = "Go! SQUIRTLE!" }
SR.update(battle)
eq(last().text, "Go! SQUIRTLE!", "next message")

-- Menu: opens with both sides, then labels.
battle.phase, battle.current = "menu", nil
SR.update(battle)
eq(last().text, "SQUIRTLE, HP 18 of 20. enemy PIDGEY, level 3, HP 50 percent. FIGHT",
  "menu opens with both sides")
eq(last().interrupt, true, "menu interrupts")
battle.menuIndex = 2
SR.update(battle)
eq(last().text, "POKéMON", "menu move")

-- Move select.
battle.phase = "moveSelect"
SR.update(battle)
eq(last().text, "TACKLE, NORMAL, PP 34 of 35, 1 of 2", "move list opens with position")
battle.moveIndex = 2
SR.update(battle)
eq(last().text, "TAIL WHIP, NORMAL, PP 30 of 30", "move list move")
battle.player.disabledSlot = 2
battle.moveIndex = 1
SR.update(battle)
battle.moveIndex = 2
SR.update(battle)
eq(last().text, "TAIL WHIP, disabled", "disabled move")

-- Safari menu labels.
battle.phase, battle.safari = "messages", { balls = 30 }
SR.update(battle)
battle.phase, battle.menuIndex = "menu", 1
SR.update(battle)
check(last().text:find("BALL, 30 left$") ~= nil, "safari menu: " .. last().text)

-- Mimic.
battle.phase, battle.mimicIndex, battle.mimicMoves = "mimicSelect", 1, { "TACKLE" }
SR.update(battle)
eq(last().text, "Mimic which move? TACKLE", "mimic select")

-- Status conditions join the turn summary.
battle.phase, battle.safari, battle.menuIndex = "messages", nil, 1
SR.update(battle)
battle.player.mon.status = "PSN"
battle.phase = "menu"
SR.update(battle)
check(last().text:find("SQUIRTLE, HP 18 of 20, PSN%.") ~= nil, "status in summary: " .. last().text)

-- Level-up stats box: recognised by its draw function living in BattleState.lua.
local statBoxClass = {}
statBoxClass.__index = statBoxClass
statBoxClass.draw = load("return function() end", "@src/battle/BattleState.lua")()
SR.update(setmetatable({ game = { data = data }, mon = { species = "SQUIRTLE", level = 6,
  stats = { attack = 12, defense = 14, speed = 11, special = 11 } } }, statBoxClass))
eq(last().text, "SQUIRTLE, level 6 stats: attack 12, defense 14, speed 11, special 11",
  "level-up stats box")

Speech.shutdown()
T.finish()
