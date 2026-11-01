-- Presenters for minor Gen 1 screens: title, League PC, prize counter, slot
-- machine, Hall of Fame, diploma, credits.  Bare tables with the real
-- upstream metatables.
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
local function as(path, fields) return setmetatable(fields, require(path)) end

local game = {
  data = { pokemon = { PIKACHU = { name = "PIKACHU" } },
    text = { DiplomaText = "Diploma", DiplomaPlayer = "Player",
      DiplomaCongrats = "Congrats! This\ndiploma certifies", DiplomaGameFreak = "GAME FREAK" } },
  save = { coins = 120, player = { name = "RED" },
    party = { { species = "PIKACHU", level = 50 } },
    hallOfFame = { { { species = "PIKACHU", level = 50, nickname = "SPARKY" } } } },
}

reset()
SR.update(as("src.ui.TitleState", { game = game }))
eq(last(), "Title screen. Press start.", "title screen")

reset()
local pc = as("src.ui.LeaguePC", { game = game, teams = game.save.hallOfFame, teamIndex = 1, monIndex = 1 })
SR.update(pc)
eq(last(), "Hall of Fame number 1, SPARKY, level 50", "league PC")

reset()
local prizes = as("src.ui.PrizeCounter", { game = game, index = 1,
  prizes = { { name = "ABRA", cost = 180 } } })
SR.update(prizes)
eq(last(), "Coins 120. ABRA, 180 coins", "prize counter entry")
prizes.index = 2
SR.update(prizes)
eq(last(), "NO THANKS", "prize counter last row")

reset()
local slots = as("src.ui.SlotMachine", { game = game, stage = "bet", betIndex = 0, yesno = 1 })
SR.update(slots)
eq(last(), "Bet 3 coins", "slot bet menu")
slots.betIndex = 2
SR.update(slots)
eq(last(), "Bet 1 coin", "slot bet change")
slots.stage = "spin"
SR.update(slots)
check(last():find("^Spinning") ~= nil, "slot spin announced")
slots.stage, slots.message = "message", "Yeah!\n7 lined up!"
SR.update(slots)
eq(last(), "Yeah! 7 lined up!", "slot message")
slots.stage = "onemore"
SR.update(slots)
eq(last(), "YES", "one more go")

reset()
local hof = as("src.ui.HallOfFame", { game = game, index = 0 })
SR.update(hof)
eq(#spoken, 0, "nothing before the first member")
hof.index = 1
SR.update(hof)
eq(last(), "Hall of Fame. PIKACHU, level 50", "hall of fame member")

reset()
SR.update(as("src.ui.Diploma", { game = game }))
eq(last(), "Diploma. Player RED. Congrats! This diploma certifies. GAME FREAK", "diploma")

reset()
local credits = as("src.ui.Credits", { game = game })
SR.update(credits)
credits.screen = { lines = { { text = "DIRECTOR" }, { text = "SATOSHI TAJIRI" } } }
SR.update(credits)
eq(last(), "DIRECTOR, SATOSHI TAJIRI", "credits screen")

reset()
game.data.pokemon.KABUTO = { name = "KABUTO" }
SR.update(as("src.ui.PicBox", { game = game, species = "KABUTO" }))
eq(last(), "Picture of KABUTO. Press A to continue.", "picture pop-up")
reset()
game.save.surfingHighScore = 1234
SR.update(as("src.ui.SurfHiScore", { game = game }))
eq(last(), "Pikachu's Beach high score: RED, 1234 points", "surfing high score")

Speech.shutdown()
T.finish()
