-- Gen 2 item and storage presenters (decision 27): PACK with its submenu,
-- toss quantity, YES/NO and messages; mart top menu, buy list, quantity,
-- typed confirm and money, sell through the held PACK; item PC; GIVE/TAKE;
-- the Pokemon Center PC; Bill's PC with CHANGE BOX and its save prompt; the
-- box list, submenu, release question, messages and MOVE's insert cursor;
-- the move deleter layouts; the move tutor's held party.  States carry the
-- real upstream metatables and only the fields the screens set.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Speech = require("src.access.Speech")
local SR = require("src.access.screens.ScreenReader")
local Items = require("src.access.screens.gen2.Items")
local Typer = require("src.ui.gen2.Typer")

local spoken = {}
local fake = { name = "Fake" }
function fake:say(text, interrupt) spoken[#spoken + 1] = { text = text, interrupt = interrupt } return true end
function fake:stop() return true end
function fake:close() end
Speech.shutdown()
Speech.start({ backend = fake })

local function reset() for i = #spoken, 1, -1 do spoken[i] = nil end SR._resetForTests() end
local function last() return spoken[#spoken] and spoken[#spoken].text end
local function lastInterrupt() return spoken[#spoken] and spoken[#spoken].interrupt end
local function count() return #spoken end
local function as(name, fields) return setmetatable(fields, require("src.ui.gen2." .. name)) end

local items = {
  POTION = { name = "POTION", pocket = "ITEM", price = 300, description = "Restores HP<NEXT>by 20." },
  ANTIDOTE = { name = "ANTIDOTE", pocket = "ITEM", price = 100, description = "Cures poison." },
  SUPER_POTION = { name = "SUPER POTION", pocket = "ITEM", price = 700, description = "Restores HP<NEXT>by 50." },
  TM_DYNAMICPUNCH = { name = "TM01", pocket = "TM_HM", teaches = "DYNAMICPUNCH", tmNumber = 1 },
  BICYCLE = { name = "BICYCLE", pocket = "KEY_ITEM", canToss = false, description = "A collapsible bike." },
}
local game = {
  data = {
    items = items,
    moves = {
      DYNAMICPUNCH = { name = "DYNAMICPUNCH", pp = 5, description = "Always confuses<NEXT>the foe." },
      TACKLE = { name = "TACKLE", pp = 35 }, GROWL = { name = "GROWL", pp = 40 },
      LEER = { name = "LEER", pp = 30 },
    },
  },
  save = { player = { name = "KRIS", money = 3000 }, options = {} },
}

local function packRows()
  return {
    { id = "POTION", name = "POTION", count = 3, showCount = true },
    { id = "ANTIDOTE", name = "ANTIDOTE", count = 1, showCount = true },
  }
end
local function newPack(fields)
  local pack = { game = game, items = items, save = game.save, rows = packRows(),
    index = 1, pocketIndex = 1, scroll = 0 }
  for k, v in pairs(fields or {}) do pack[k] = v end
  return as("PackMenu", pack)
end

-- ------------------------------------------------------------------ PACK
reset()
local pack = newPack()
SR.update(pack)
eq(last(), "ITEMS pocket. POTION, quantity 3, 1 of 3. Restores HP by 20.", "pack entry: pocket, row, position, description")
pack.index = 2
SR.update(pack)
eq(last(), "ANTIDOTE, quantity 1. Cures poison.", "cursor move: the row and its description, no position")
check(lastInterrupt(), "cursor moves interrupt")
pack.index = 3
SR.update(pack)
eq(last(), "CANCEL", "CANCEL row has no description")
local before = count()
SR.update(pack)
eq(count(), before, "an unchanged frame says nothing")

pack.pocketIndex, pack.index = 4, 1
pack.rows = { { id = "TM_DYNAMICPUNCH", name = "TM01", count = 1, showCount = true,
  teaches = "DYNAMICPUNCH", tmhmLabel = "01" } }
SR.update(pack)
eq(last(), "TM/HM pocket. TM01, DYNAMICPUNCH, quantity 1, 1 of 2. Always confuses the foe.",
  "pocket change: pocket name, TM row with its move, the move's description")
pack.pocketIndex, pack.index = 3, 1
pack.rows = { { id = "BICYCLE", name = "BICYCLE", count = 1, showCount = false } }
SR.update(pack)
eq(last(), "KEY ITEMS pocket. BICYCLE, 1 of 2. A collapsible bike.", "a key item draws no quantity")

reset()
pack = newPack()
SR.update(pack)
pack.submenu = { row = pack.rows[1], rows = { "use", "give", "toss", "quit" }, index = 1 }
SR.update(pack)
eq(last(), "USE, 1 of 4", "submenu opens on its first row with position")
pack.submenu.index = 3
SR.update(pack)
eq(last(), "TOSS", "submenu move: the label")
-- TOSS: the submenu closes, "Throw away how many?" and the quantity box open
pack.submenu = nil
pack:showMessage("Throw away how\nmany?")
pack.qtyState = { row = pack.rows[1], qty = 1, max = 3 }
SR.update(pack)
eq(last(), "Throw away how many? Quantity 1, up to 3", "toss quantity: prompt, amount, maximum")
pack.qtyState.qty = 2
SR.update(pack)
eq(last(), "2", "quantity change says the amount")
pack.qtyState, pack.message, pack.messagePage = nil, nil, nil
pack.confirm = { prompt = { "Throw away 2", "POTION(S)?" }, choice = 1 }
SR.update(pack)
eq(last(), "Throw away 2 POTION(S)? YES", "toss YES/NO: question and selection")
pack.confirm.choice = 2
SR.update(pack)
eq(last(), "NO", "YES/NO move")
pack.confirm = nil
pack.rows[1].count = 1
pack.message, pack.messagePage = { "Threw away", "POTION(S)." }, 1
SR.update(pack)
eq(last(), "Threw away POTION(S).", "message without a split cache is read through the mirror")
pack.message = nil
SR.update(pack)
eq(last(), "POTION, quantity 1, 1 of 3. Restores HP by 20.", "back on the list: row and position again")

-- a two-page message whose second page scrolls one line: only the new line
reset()
pack = newPack()
SR.update(pack)
pack.message = { "OAK: {PLAYER}!", "This isn't the", "\v", "time to use that!" }
pack.messagePage = 1
SR.update(pack)
eq(last(), "OAK: KRIS! This isn't the", "first page, player name filled in")
pack.messagePage = 2
SR.update(pack)
eq(last(), "time to use that!", "scrolled page says only its new line")
pack.message = nil
SR.update(pack)
SR.update({}) -- something else on top
SR.update(pack)
eq(last(), "ITEMS pocket. POTION, quantity 3, 1 of 3. Restores HP by 20.", "returning repeats the pocket")

-- SELECT's item move
reset()
pack = newPack()
SR.update(pack)
pack.switching = 1
pack:showMessage("Where should this\nbe moved to?")
SR.update(pack)
eq(last(), "Where should this be moved to? POTION, quantity 3, 1 of 3", "item move: question and the held row")
pack.index = 2
SR.update(pack)
eq(last(), "ANTIDOTE, quantity 1", "item move cursor: the row")

-- ------------------------------------------------------------------- MART
local MartMenu = require("src.ui.gen2.MartMenu")
local function newMart()
  return as("MartMenu", { game = game, save = { player = { money = 3000 } }, items = items,
    martType = "STANDARD", phase = "top", topIndex = 1, index = 1, scroll = 0,
    topLines = { "Welcome! How may I", "help you?" },
    text = { howMany = { "How many?" } }, sellText = { howMany = { "How many?" } },
    entries = {
      { id = "POTION", name = "POTION", price = 300 },
      { id = "SUPER_POTION", name = "SUPER POTION", price = 700 },
    } })
end
reset()
local mart = newMart()
SR.update(mart)
eq(last(), "Welcome! How may I help you? BUY, 1 of 3", "mart top: clerk line, BUY, position")
mart.topIndex = 2
SR.update(mart)
eq(last(), "SELL", "top menu move")
mart.topIndex, mart.phase = 1, "buy"
SR.update(mart)
eq(last(), "money ¥3000. POTION, ¥300, 1 of 3. Restores HP by 20.", "buy list: money, row with price, description")
mart.index = 2
SR.update(mart)
eq(last(), "SUPER POTION, ¥700. Restores HP by 50.", "buy list move")
mart.index = 1
SR.update(mart)
mart.phase, mart.qtyItem, mart.qty, mart.qtyMax = "buyQuantity", mart.entries[1], 1, 99
SR.update(mart)
eq(last(), "How many? Quantity 1, ¥300, up to 99", "buy quantity: prompt, amount, total, maximum")
mart.qty = 3
SR.update(mart)
eq(last(), "3, ¥900", "quantity change: amount and total")
mart:ask({ { "3 POTION(S)", "will be ¥900." } })
SR.update(mart)
eq(last(), "3 POTION(S) will be ¥900.", "typed confirm question is spoken as it starts")
check(lastInterrupt(), "the question interrupts")
before = count()
SR.update(mart)
eq(count(), before, "no YES while the question is still typing")
mart.typer.shown = mart.typer.total
SR.update(mart)
eq(last(), "YES", "YES once the box is drawn")
check(not lastInterrupt(), "YES queues behind the question")
mart.confirm.choice = 2
SR.update(mart)
eq(last(), "NO", "confirm move")
check(lastInterrupt(), "a YES/NO move interrupts")
mart.confirm = nil
mart.save.player.money = 2100
mart.phase = "buy"
Typer.say(mart, { { "Here you are.", "Thank you!" } })
SR.update(mart)
eq(last(), "Here you are. Thank you! money ¥2100", "purchase message with the new money")
mart.message = nil
SR.update(mart)
eq(last(), "POTION, ¥300, 1 of 3. Restores HP by 20.", "back on the buy list")

-- selling goes through the PACK the mart holds off the stack
mart.phase, mart.topIndex = "top", 2
mart.topLines = { "Can I do anything", "else for you?" }
SR.update(mart)
eq(last(), "Can I do anything else for you? SELL, 2 of 3", "top again after buying")
mart.phase = "sell"
mart.pack = newPack()
SR.update(mart)
eq(last(), "SELL. ITEMS pocket. POTION, quantity 3, 1 of 3. Restores HP by 20.", "sell: the held PACK with context")
mart.pack.index = 2
SR.update(mart)
eq(last(), "ANTIDOTE, quantity 1. Cures poison.", "held PACK cursor")
mart.pack.index = 1
SR.update(mart)
mart.phase, mart.qtyItem, mart.qty, mart.qtyMax = "sellQuantity", { id = "POTION", name = "POTION", price = 300 }, 1, 3
SR.update(mart)
eq(last(), "How many? Quantity 1, ¥150, up to 3. money ¥2100", "sell quantity: half price, money box")
mart.qty = 2
SR.update(mart)
eq(last(), "2, ¥300", "sell quantity change")
mart:ask({ { "I can pay you", "¥300." }, { "Is that OK?" } })
mart.typer.shown = mart.typer.total
SR.update(mart)
eq(last(), "I can pay you ¥300.", "first confirm page; no YES before the last page")
Typer.turn(mart, mart.confirm)
SR.update(mart)
eq(last(), "Is that OK?", "second page")
mart.typer.shown = mart.typer.total
SR.update(mart)
eq(last(), "YES", "YES after the last page")
check(MartMenu.sellPrice(300, 2) == 300, "sell price helper agrees with the spoken total")

-- -------------------------------------------------------------- ITEM PC
local ItemPcMenu = require("src.ui.gen2.ItemPcMenu")
local entries = {}
for i, entry in ipairs(ItemPcMenu.ENTRIES) do entries[i] = entry end
entries[#entries + 1] = { id = "logoff", label = "LOG OFF", builtin = true }
reset()
local pc = as("ItemPcMenu", { game = game, save = game.save, items = items, data = game.data,
  entries = entries, index = 1, phase = "menu", rows = {}, listIndex = 1, scroll = 0 })
SR.update(pc)
eq(last(), "What do you want to do? WITHDRAW ITEM, 1 of 5", "item PC menu: prompt, row, position")
pc.index = 2
SR.update(pc)
eq(last(), "DEPOSIT ITEM", "menu move")
pc.index, pc.phase = 1, "withdraw"
pc.rows = { { id = "POTION", name = "POTION", count = 5, slot = 1 }, { id = "BICYCLE", name = "BICYCLE", count = 1, slot = 2 } }
SR.update(pc)
eq(last(), "WITHDRAW ITEM. POTION, quantity 5, 1 of 3. Restores HP by 20.", "withdraw list with context")
pc.listIndex = 2
SR.update(pc)
eq(last(), "BICYCLE. A collapsible bike.", "an untossable item draws no quantity")
pc.listIndex = 1
SR.update(pc)
pc.qtyState = { qty = 1, max = 5, prompt = { "How many do you", "want to withdraw?" } }
SR.update(pc)
eq(last(), "How many do you want to withdraw? Quantity 1, up to 5", "withdraw quantity")
pc.qtyState.qty = 5
SR.update(pc)
eq(last(), "5", "quantity change")
pc.qtyState = nil
Typer.say(pc, { { "Withdrew 5", "POTION(S)." } })
SR.update(pc)
eq(last(), "Withdrew 5 POTION(S).", "typed message")
pc.message = nil
SR.update(pc)
eq(last(), "POTION, quantity 5, 1 of 3. Restores HP by 20.", "back on the list without the menu label")
pc.switching = 1
SR.update(pc)
eq(last(), "moving POTION", "SELECT's move says which item")
pc.listIndex = 2
SR.update(pc)
eq(last(), "BICYCLE", "move cursor")
pc.switching, pc.listIndex = nil, 1
SR.update(pc)
pc.confirm = { prompt = { "Throw away 1", "POTION(S)?" }, choice = 1 }
SR.update(pc)
eq(last(), "Throw away 1 POTION(S)? YES", "instant YES/NO with its question")
pc.confirm.choice = 2
SR.update(pc)
eq(last(), "NO", "YES/NO move")
pc.confirm, pc.phase, pc.index = nil, "menu", 2
SR.update(pc)
eq(last(), "What do you want to do? DEPOSIT ITEM, 2 of 5", "back on the menu")
pc.phase, pc.pack = "deposit", newPack()
SR.update(pc)
eq(last(), "DEPOSIT ITEM. ITEMS pocket. POTION, quantity 3, 1 of 3. Restores HP by 20.", "deposit: the held PACK")

-- ------------------------------------------------------------ GIVE / TAKE
reset()
local held = as("HeldItemMenu", { game = game, items = items, index = 1, busy = false, slot = 1,
  save = { party = { { species = "PIKACHU", name = "PIKACHU", nickname = "SPARKY" } } } })
SR.update(held)
eq(last(), "SPARKY. GIVE, 1 of 2", "GIVE/TAKE entry names the Pokémon")
held.index = 2
SR.update(held)
eq(last(), "TAKE", "menu move")
held:say({ { "SPARKY is", "already holding" }, { "POTION.", "Switch items?" } })
held.message = nil -- the same pages as a confirm instead
held:ask({ { "SPARKY is", "already holding" }, { "POTION.", "Switch items?" } })
SR.update(held)
eq(last(), "SPARKY is already holding", "swap question, first page")
held.typer.shown = held.typer.total
Typer.turn(held, held.confirm)
SR.update(held)
eq(last(), "POTION. Switch items?", "second page")
held.typer.shown = held.typer.total
SR.update(held)
eq(last(), "YES", "YES after the last page is typed")

-- ------------------------------------------------------ POKéMON CENTER PC
reset()
local CenterPcMenu = require("src.ui.gen2.CenterPcMenu")
local center = CenterPcMenu.new(game, { save = { player = { name = "KRIS" }, party = {} } })
SR.update(center)
eq(last(), "Bzzzzt! You must have a POKéMON to", "no party: refusal first page")
center.typer.shown = center.typer.total
Typer.turn(center, center.message)
SR.update(center)
eq(last(), "use this!", "the scrolled page says only its new line")
reset()
center = CenterPcMenu.new(game, { save = { player = { name = "KRIS" }, party = { {} } } })
SR.update(center)
eq(last(), "KRIS turned on the PC.", "turn-on message with the player's name")
center.message, center.booted = nil, true
SR.update(center)
eq(last(), "Access whose PC? BILL's PC, 1 of 3", "whose-PC menu with its prompt")
center.index = 2
SR.update(center)
eq(last(), "KRIS's PC", "menu move")
center.confirm = { prompt = { "Want to get your", "#DEX rated?" }, choice = 1 }
SR.update(center)
eq(last(), "Want to get your POKéDEX rated? YES", "OAK's PC question")

-- -------------------------------------------------------------- BILL'S PC
local PcMenu = require("src.ui.gen2.PcMenu")
reset()
local bills = PcMenu.new(game, { save = { player = { name = "KRIS" }, party = { { hp = 10 } },
  boxes = { [1] = { {}, {}, {} } }, currentBox = 1 }, bills = true, saveExists = false })
SR.update(bills)
eq(last(), "What? WITHDRAW PKMN, 1 of 5", "Bill's PC menu with its prompt")
bills.index = 3
SR.update(bills)
eq(last(), "CHANGE BOX", "menu move")
bills.picking, bills.pickIndex = true, 1
SR.update(bills)
eq(last(), "Which BOX? BOX1, 3 of 20 POKéMON, 1 of 14", "box picker: name, fill, position")
bills.pickIndex = 2
SR.update(bills)
eq(last(), "BOX2, 0 of 20 POKéMON", "box picker move")
check(bills.save.boxes[2] == nil, "reading a box's fill does not create the box")
bills:beginChangeBox(2)
SR.update(bills)
eq(last(), "When you change a POKéMON BOX, data", "change-box save prompt, first page")
bills.typer.shown = bills.typer.total
bills.savePage = 2
bills.typer:start(bills:savePages()[2])
SR.update(bills)
eq(last(), "will be saved. OK?", "scrolled second page")
bills.typer.shown = bills.typer.total
SR.update(bills)
eq(last(), "YES", "save YES/NO once the prompt is typed")
check(not lastInterrupt(), "YES queues")
bills.saveChoice = 2
SR.update(bills)
eq(last(), "NO", "save choice move")
bills:refuseChangeBox()
SR.update(bills)
eq(last(), "Which BOX? BOX2, 0 of 20 POKéMON, 2 of 14", "refusing goes back to the picker")
bills.picking = false
bills:notice({ "There is a POKéMON\nholding MAIL.", "Please remove the\nMAIL." })
SR.update(bills)
eq(last(), "There is a POKéMON holding MAIL.", "notice page")
bills.messagePage, bills.message = 2, bills.messagePages[2]
SR.update(bills)
eq(last(), "Please remove the MAIL.", "next notice page")

-- ------------------------------------------------------------------ BOXES
reset()
local sprout = { species = "BELLSPROUT", name = "BELLSPROUT", nickname = "SPROUTY", level = 7,
  gender = "female", item = "BERRY" }
local cynda = { species = "CYNDAQUIL", name = "CYNDAQUIL", level = 14, gender = "male", hp = 40 }
local egg = { species = "TOGEPI", name = "TOGEPI", nickname = "EGG", isEgg = true, level = 5 }
local boxSave = { party = { cynda, egg }, boxes = { [1] = { sprout } }, currentBox = 1 }
local box = as("BoxMenu", { game = game, save = boxSave, mode = "withdraw", boxIndex = 1,
  index = 1, scroll = 0, submenuIndex = 1 })
SR.update(box)
eq(last(), "BOX1. Choose a PKMN. SPROUTY, level 7, female, BELLSPROUT, holding an item, 1 of 2",
  "box entry: box name, prompt, mon with its panel details, position")
box.index = 2
SR.update(box)
eq(last(), "CANCEL", "list move to CANCEL")
box.index, box.phase = 1, "submenu"
SR.update(box)
eq(last(), "What's up? WITHDRAW, 1 of 4", "submenu with its prompt")
box.submenuIndex = 3
SR.update(box)
eq(last(), "RELEASE", "submenu move")
-- RELEASE: the question is set and the ChoiceBox covers the screen at once
local boxMemo = {}
Items.boxMenu.poll(box, boxMemo, true)
box.message = "Release <PK><MN>?"
eq(Items.boxMenu.covered(box, boxMemo), "Release PKMN?", "covered hook returns the release question")
eq(Items.boxMenu.covered(box, boxMemo), nil, "and only once")
box.message, box.phase = "Released <PK><MN>.\fBye,\nSPROUTY!", nil
box.messagePage = 1
SR.update(box)
eq(last(), "Released PKMN.", "release message first page")
box.messagePage = 2
SR.update(box)
eq(last(), "Bye, SPROUTY!", "second page")
box.message, box.messagePage = nil, nil
boxSave.boxes[1] = {}
SR.update(box)
eq(last(), "CANCEL, 1 of 1", "empty box after the release")

reset()
local deposit = as("BoxMenu", { game = game, save = boxSave, mode = "deposit", boxIndex = 1,
  index = 2, scroll = 0, submenuIndex = 1 })
SR.update(deposit)
eq(last(), "PARTY PKMN. Choose a PKMN. EGG, 2 of 3", "deposit lists the party; an egg is its name only")

reset()
local move = as("BoxMenu", { game = game, save = boxSave, mode = "move", boxIndex = 0,
  index = 1, scroll = 0, submenuIndex = 1 })
SR.update(move)
eq(last(), "PARTY PKMN. Choose a PKMN. CYNDAQUIL, level 14, male, 1 of 3", "move screen starts on the party")
move.boxIndex = 1
SR.update(move)
eq(last(), "BOX1. CANCEL, 1 of 1", "left/right: the next box")
move.boxIndex, move.phase, move.moveFrom = 0, "insert", { box = 0, slot = 1 }
SR.update(move)
eq(last(), "Move to where? PARTY PKMN. before CYNDAQUIL, level 14, male, 1 of 2", "insert cursor entry")
move.index = 2
SR.update(move)
eq(last(), "before EGG", "insert cursor move")
move.boxIndex, move.index = 3, 1
SR.update(move)
eq(last(), "BOX3. empty, 1 of 1", "insert into an empty box")
check(boxSave.boxes[3] == nil, "reading the box list does not create it")

-- ------------------------------------------------------------ MOVE LISTS
reset()
local deleter = as("MoveDeleter", { game = game, moves = game.data.moves, row = 1,
  list = { { id = "TACKLE", pp = 30 }, { id = "GROWL" }, { id = "LEER", pp = 0 } } })
SR.update(deleter)
eq(last(), "TACKLE, PP 30 of 35, 1 of 3", "deleter entry: move, PP, position")
deleter.row = 2
SR.update(deleter)
eq(last(), "GROWL, maximum PP 40", "missing PP is never spoken as zero")
deleter.row = 3
SR.update(deleter)
eq(last(), "LEER, PP 0 of 30", "an explicit 0 is used up")
reset()
local forget = as("MoveDeleter", { game = game, moves = game.data.moves, row = 1, forget = true,
  list = { { id = "TACKLE", pp = 30 }, { id = "GROWL", pp = 40 } } })
SR.update(forget)
eq(last(), "TACKLE, 1 of 2", "forget list: names only, as drawn")

-- ------------------------------------------------------------- MOVE TUTOR
reset()
local PartyMenu = require("src.ui.gen2.PartyMenu")
local list = as("PartyMenu", { game = game, index = 1, prompt = PartyMenu.PROMPTS.teach,
  promptIsBuiltin = true, tmhm = { move = "FLAMETHROWER" },
  pokemon = { CYNDAQUIL = { tmhm = { "FLAMETHROWER" } }, PIDGEY = { tmhm = {} } },
  party = { { species = "CYNDAQUIL", name = "CYNDAQUIL", level = 14, hp = 40, maxHp = 40 },
    { species = "PIDGEY", name = "PIDGEY", level = 5, hp = 0, maxHp = 20 } } })
local tutor = as("MoveTutor", { game = game, move = "FLAMETHROWER", list = list })
SR.update(tutor)
eq(last(), "Teach which PKMN? CYNDAQUIL, level 14, ABLE, 1 of 3", "tutor: prompt and the held party row")
list.index = 2
SR.update(tutor)
eq(last(), "PIDGEY, level 5, NOT ABLE, fainted", "next row")
list.index = 3
SR.update(tutor)
eq(last(), "CANCEL", "CANCEL row")
SR.update({})
SR.update(tutor)
eq(last(), "Teach which PKMN? CANCEL, 3 of 3", "returning from a refusal repeats the prompt")

-- ------------------------------------------------------------------ misc
eq(Items.sentences("How many?", "Quantity 1"), "How many? Quantity 1", "sentence join keeps punctuation")
eq(Items.sentences("BOX1", nil, "CANCEL"), "BOX1. CANCEL", "missing parts are skipped")
-- Crystal's POKé BALL text, seen in the first game run as "catch- ing"
eq(Items.description("An item for catch-<NEXT>ing #MON."), "An item for catching POKéMON.",
  "a word split across a description's two lines is said whole")
local pages = Items.tokenPages({ "a", "b", "\v", "c", "\f", "d" })
check(#pages == 3 and pages[2][1] == "b" and pages[2][2] == "c" and pages[3][1] == "d",
  "token pages mirror the cart's para and cont")

T.finish("gen2 items")
