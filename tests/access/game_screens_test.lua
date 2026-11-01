-- Presenters for Gen 1 screens beyond plain menus: naming keyboard,
-- quantity, party, summary, move pickers, trainer card, Pokedex, options,
-- town map.  States are bare tables with the real upstream metatables and a
-- minimal fake game.
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
  data = {
    pokemon = {
      PIKACHU = { id = "PIKACHU", name = "PIKACHU", dex = 25, types = { "ELECTRIC" },
        tmhm = { "THUNDERBOLT" }, evolutions = { { method = "ITEM", item = "THUNDER_STONE" } },
        dexEntry = { kind = "MOUSE", heightFt = 1, heightIn = 4, weight = 132, text = "DEX_PIKA" } },
    },
    moves = { THUNDERSHOCK = { name = "THUNDERSHOCK", pp = 30 }, GROWL = { name = "GROWL", pp = 40 } },
    text = { DEX_PIKA = "When several of\nthese gather,\fits electricity\ncan build.{DONE}" },
    statuses = {},
  },
  save = { player = { name = "RED", id = 12345 }, money = 3000, playTime = 3725,
    inventory = {}, pokedex = { owned = { PIKACHU = true }, seen = { PIKACHU = true } } },
}
local pika = { species = "PIKACHU", nickname = "SPARKY", level = 5, hp = 19, exp = 135,
  stats = { hp = 20, attack = 11, defense = 9, speed = 14, special = 10 },
  moves = { { id = "THUNDERSHOCK", pp = 30 }, { id = "GROWL", pp = 12 } } }
game.save.party = { pika }

-- Quantity box.
reset()
local qty = as("src.ui.QuantityBox", { game = game, qty = 1, max = 10, unitPrice = 200 })
SR.update(qty)
eq(last(), "Quantity 1, ¥200, up to 10", "quantity entry with total")
qty.qty = 3
SR.update(qty)
eq(last(), "3, ¥600", "quantity change with total")

-- Naming keyboard: grid comes from the screen's own grid() method.
reset()
local naming = as("src.ui.NamingScreen", { game = game, title = "YOUR NAME?", glyphs = {},
  row = 1, col = 1, lower = false, maxLen = 7 })
SR.update(naming)
eq(last(), "YOUR NAME? empty. A", "naming entry")
naming.col = 2
SR.update(naming)
eq(last(), "B", "cursor move says the cell")
naming.glyphs[1] = "B"
SR.update(naming)
eq(last(), "B, B", "typing says the letter and the name so far")
naming.row, naming.col = 4, 8
SR.update(naming)
eq(last(), "PK", "glyph cells are spelled out")
naming.glyphs[1] = nil
SR.update(naming)
eq(last(), "deleted, empty", "erasing is announced")
naming.row, naming.col = 6, 1
SR.update(naming)
eq(last(), "lower case", "case switch cell")
naming.lower = true
SR.update(naming)
eq(last(), "lower case. UPPER CASE", "switching case announces the new page")

-- Party.
reset()
local party = as("src.ui.PartyMenu", { game = game, index = 1, subIndex = 1 })
SR.update(party)
eq(last(), "Choose a POKéMON. SPARKY, level 5, HP 19 of 20, 1 of 1", "party entry")
party.submenu = true
party.subItems = { { label = "STATS" }, { label = "SWITCH" }, { label = "CANCEL" } }
SR.update(party)
eq(last(), "STATS, 1 of 3", "submenu opening gives position")
party.subIndex = 2
SR.update(party)
eq(last(), "SWITCH", "submenu move")
party.submenu = nil
SR.update(party)
eq(last(), "SPARKY, level 5, HP 19 of 20, 1 of 1", "closing submenu returns to the row")
reset()
local tm = as("src.ui.PartyMenu", { game = game, index = 1, subIndex = 1,
  tmhm = { move = "THUNDERBOLT" } })
SR.update(tm)
check(last():find("able, 1 of 1", 1, true) ~= nil, "TM teaching says able")

-- Summary pages.
reset()
local summary = as("src.ui.SummaryMenu", { game = game, mon = pika, page = 1 })
SR.update(summary)
check(last():find("SPARKY, number 25, level 5, HP 19 of 20, status OK", 1, true) == 1,
  "summary page 1 starts with identity: " .. tostring(last()))
check(last():find("trainer RED", 1, true) ~= nil, "summary page 1 names the trainer")
summary.page = 2
SR.update(summary)
check(last():find("THUNDERSHOCK, PP 30 of 30; GROWL, PP 12 of 40; empty; empty", 1, true) ~= nil,
  "summary page 2 lists moves with PP: " .. tostring(last()))

-- Move learn list appears only once selecting starts.
reset()
local learn = as("src.ui.MoveLearnMenu", { game = game, mon = pika, index = 1, selecting = false })
SR.update(learn)
eq(#spoken, 0, "nothing before the forget list opens")
learn.selecting = true
SR.update(learn)
eq(last(), "THUNDERSHOCK, PP 30 of 30, 1 of 2", "forget list opens with position")
learn.index = 2
SR.update(learn)
eq(last(), "GROWL, PP 12 of 40", "forget list move")

-- Trainer card.
reset()
SR.update(as("src.ui.TrainerCard", { game = game }))
eq(last(), "Trainer card, RED, money ¥3000, time 1 hour 2 minutes, no badges", "trainer card")

-- Pokedex list and entry.
reset()
local dex = as("src.ui.PokedexMenu", { game = game, index = 1, seenCount = 1, ownedCount = 1,
  items = { { num = "025", name = "PIKACHU", value = "PIKACHU", ball = true } } })
SR.update(dex)
eq(last(), "Pokédex, seen 1, owned 1, 025, PIKACHU, owned, 1 of 1", "pokedex entry")
reset()
local entry = as("src.ui.DexEntryMenu", { game = game, def = game.data.pokemon.PIKACHU, page = 1 })
SR.update(entry)
eq(last(), "PIKACHU, MOUSE, number 25, height 1 feet 4 inches, weight 13.2 pounds, When several of these gather,",
  "dex entry first page")
entry.page = 2
SR.update(entry)
eq(last(), "its electricity can build.", "dex entry second page")

-- Options.
reset()
local speed = "FAST"
local options = as("src.ui.OptionsMenu", { game = game, index = 1,
  rows = { { label = "TEXT SPEED", value = function() return speed end } } })
SR.update(options)
eq(last(), "Options. TEXT SPEED, FAST, 1 of 2", "options entry")
speed = "SLOW"
SR.update(options)
eq(last(), "SLOW", "changing a value says only the value")
options.index = 2
SR.update(options)
eq(last(), "BACK, 2 of 2", "back row")

-- Town map.
reset()
local home = { name = "PALLET TOWN" }
local map = as("src.ui.TownMap", { game = game, sel = 1, locs = { home, { name = "ROUTE 1" } },
  playerLoc = home })
SR.update(map)
eq(last(), "Town map. PALLET TOWN, you are here", "town map entry")
map.sel = 2
SR.update(map)
eq(last(), "ROUTE 1", "town map move")

-- Self-describing screens (the mod contract).
reset()
local track = 1
local jukebox = { accessibilityText = function() return "Jukebox. Track " .. track end }
SR.update(jukebox)
eq(last(), "Jukebox. Track 1", "self-description spoken on entry")
SR.update(jukebox)
eq(#spoken, 1, "unchanged self-description is not repeated")
track = 2
SR.update(jukebox)
eq(last(), "Jukebox. Track 2", "changed self-description spoken")
reset()
local overridden = as("src.ui.Menu", { index = 1, items = { { label = "X" } },
  accessibilityText = function() return "Custom menu" end })
SR.update(overridden)
eq(last(), "Custom menu", "a screen's own description overrides the built-in presenter")
reset()
local broken = { accessibilityText = function() error("mod bug") end }
SR.update(broken)
SR.update(broken)
eq(#spoken, 0, "a failing description stays quiet instead of raising")

Speech.shutdown()
T.finish()
