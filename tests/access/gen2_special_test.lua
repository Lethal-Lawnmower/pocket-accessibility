-- Gen 2 minigames and special screens (decision 27): Card Flip, slots, the
-- Unown puzzle and stamp, contest, Battle Tower, Buena, Day-Care, NPC trade,
-- decorations, mail, photo card, Magnet Train, trade animation, Hall of Fame,
-- diploma, credits, wall words, Union Room and the arena launcher.  Screens
-- are the real upstream classes, built with their own constructors where
-- that needs no game data, otherwise bare tables with the real metatables.
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
local function lastInterrupts() return spoken[#spoken] and spoken[#spoken].interrupt end
local function as(path, fields) return setmetatable(fields, require(path)) end
local function gen2(name, fields) return as("src.ui.gen2." .. name, fields) end

-- one roll per call, cycling a fixed list, for the screens' `random(n)`
local function rolls(list)
  local i = 0
  return function(n)
    i = i % #list + 1
    return list[i] % n
  end
end

local data = {
  pokemon = {
    KABUTO = { name = "KABUTO" }, UNOWN = { name = "UNOWN" }, GOLEM = { name = "GOLEM" },
    CHANSEY = { name = "CHANSEY" }, CHIKORITA = { name = "CHIKORITA", dex = 152 },
    TYPHLOSION = { name = "TYPHLOSION", dex = 157 },
  },
  items = { FLOWER_MAIL = { name = "FLOWER MAIL" } },
  moves = { TACKLE = { name = "TACKLE" } },
}
local game = { data = data, save = { player = { name = "KRIS", id = 1234, coins = 10 } } }

-- ------------------------------------------------------------ Card Flip
do
  reset()
  local CardFlip = require("src.ui.gen2.CardFlip")
  local flip = CardFlip.new(game, { random = rolls({ 5, 9, 2, 17, 30, 11, 3 }) })
  SR.update(flip)
  eq(last(), "Card flip. Coins 10. Play with 3 coins? YES", "card flip entry")
  flip.choice = 2
  SR.update(flip)
  eq(last(), "NO", "card flip yes/no moves")
  flip.choice = 1
  SR.update(flip)
  flip:deduct()
  SR.update(flip)
  eq(last(), "Coins 7. Hand 1 of 12. Choose a card.", "hand starts with coins and hand number")
  local before = #spoken
  for _ = 1, 9 do flip.which = flip.which == 0 and 1 or 0 SR.update(flip) end
  eq(#spoken, before, "the lit face-down card is not spoken")
  flip:enterBet()
  SR.update(flip)
  eq(last(), "Place your bet. PIKACHU level 1, pays 72", "bet entry names the square under the cursor")
  local function square(x, y)
    flip.cursorX, flip.cursorY = x, y
    SR.update(flip)
    return last()
  end
  eq(square(3, 0), "PIKACHU or JIGGLYPUFF, pays 6", "Pokemon pair square")
  eq(square(4, 0), "POLIWAG or ODDISH, pays 6", "second Pokemon pair")
  eq(square(3, 1), "JIGGLYPUFF, pays 12", "single Pokemon square")
  eq(square(0, 2), "level 1 or 2, pays 9", "level pair square")
  eq(square(1, 4), "level 3, pays 18", "single level square")
  eq(square(5, 7), "ODDISH level 6, pays 72", "bottom right is Oddish level 6, not reversed")
  eq(square(2, 7), "PIKACHU level 6, pays 72", "bottom left card")
  eq(square(0, 0), "Corner, pays nothing", "the always-losing corner")
  -- deal a known card: the first hand's lit card is deck[1]
  flip.deck[1], flip.which = CardFlip.card(2, 1), 0
  flip.cursorX, flip.cursorY = 3, 1
  SR.update(flip)
  flip:flip()
  SR.update(flip)
  for _ = 1, 12 do flip:updateFlipping() end
  SR.update(flip)
  eq(last(), "JIGGLYPUFF level 3. Yeah!", "the turned card and the cart's line")
  while flip.phase == "payout" do flip:updatePayout() end
  SR.update(flip)
  eq(last(), "Coins 19", "coin total after the count-up")
  flip:enterAgain()
  SR.update(flip)
  eq(last(), "Play again? YES", "play again")
  flip:continue()
  SR.update(flip)
  flip:enterBet()
  flip.cursorX, flip.cursorY = 2, 2
  SR.update(flip)
  eq(last(), "Place your bet. Played: JIGGLYPUFF level 3. PIKACHU level 1, pays 72",
    "the board's blanked cards are listed")
  eq(square(3, 4), "JIGGLYPUFF level 3, pays 72, played", "a blanked card cell says played")
  flip.deck[3], flip.which = CardFlip.card(0, 3), 0
  flip:flip()
  for _ = 1, 12 do flip:updateFlipping() end
  SR.update(flip)
  eq(last(), "ODDISH level 1. Darn…", "a losing card")
  flip.played = CardFlip.HANDS_PER_DECK - 1
  flip:continue()
  SR.update(flip)
  eq(last(), "The cards shuffled.", "the twelfth hand reshuffles")
  game.save.player.coins = 1
  flip.after()
  SR.update(flip)
  eq(last(), "Not enough coins.", "too few coins for a hand")
end

-- ------------------------------------------------------------ slots
do
  reset()
  game.save.player.coins = 10
  local SM = require("src.ui.gen2.SlotMachine")
  local slots = SM.new(game, { random = rolls({ 200, 7, 90, 3 }) })
  SR.update(slots)
  eq(last(), "Slot machine. Coins 10. Bet how many coins? 3 coins, 3 rows and 2 diagonals, 1 of 3",
    "slot entry: coins, prompt, bet and what it buys")
  slots.betIndex = 2
  SR.update(slots)
  eq(last(), "2 coins, 3 rows", "two coins")
  slots.betIndex = 3
  SR.update(slots)
  eq(last(), "1 coin, middle row", "one coin")
  check(lastInterrupts(), "bet moves interrupt")
  slots.message = SM.TEXTS.notEnough
  SR.update(slots)
  eq(last(), "Not enough coins.", "a refused bet")
  slots.message = nil
  SR.update(slots)
  eq(last(), "1 coin, middle row", "the bet row again once the message closes")
  slots.bet = 3
  slots:startSpin()
  SR.update(slots)
  eq(last(), "Start!", "spin starts")
  slots.message = nil
  slots.stopped = { { SM.CHERRY, SM.SEVEN, SM.STARYU } }
  SR.update(slots)
  eq(last(), "Reel 1: top STARYU, middle SEVEN, bottom CHERRY", "first reel read top to bottom")
  check(not lastInterrupts(), "a stopped reel queues")
  slots.reel2Pause = 32
  SR.update(slots)
  eq(last(), "Reel 2 pauses", "reel 2 tell")
  slots.reel2Pause = nil
  slots.stopped[2] = { SM.SEVEN, SM.SEVEN, SM.SEVEN }
  SR.update(slots)
  eq(last(), "Reel 2: top SEVEN, middle SEVEN, bottom SEVEN", "second reel")
  slots.golemAnim = { count = 2, state = "falling" }
  SR.update(slots)
  eq(last(), "GOLEM drops onto reel 3", "golem tell")
  slots.golemAnim.state, slots.golemAnim.count = "falling", 1
  SR.update(slots)
  eq(last(), "Another GOLEM drops", "second golem")
  slots.golemAnim = nil
  slots.stopped[3] = { SM.CHERRY, SM.PIKACHU, SM.CHERRY }
  slots.phase, slots.matched, slots.message = "payoutText", SM.NO_MATCH, SM.TEXTS.darn
  SR.update(slots)
  eq(last(), "Reel 3: top CHERRY, middle PIKACHU, bottom CHERRY. Darn!", "last reel and the loss together")
  slots.matched = SM.SEVEN
  slots:beginPayout()
  SR.update(slots)
  eq(last(), "SEVEN lined up! Won 300 coins!", "the matched symbol is said where its picture is")
  slots.payoutLeft = 0
  slots:enterAgain()
  SR.update(slots)
  eq(last(), "Coins 10. Play again? YES", "play again, queued")
  check(not lastInterrupts(), "play again queues behind the win")
  slots.againChoice = 2
  SR.update(slots)
  eq(last(), "NO", "again choice")
  game.save.player.coins = 0
  slots:enterAgain()
  SR.update(slots)
  eq(last(), "Darn… Ran out of coins…", "ran out")
  check(not lastInterrupts(), "ran out queues")
  game.save.player.coins = 10
end

-- ------------------------------------------------------------ Unown puzzle
do
  reset()
  local UP = require("src.ui.gen2.UnownPuzzle")
  local puzzle = UP.new(game, { puzzle = 0, random = rolls({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }) })
  local first = puzzle.pieces[1]
  SR.update(puzzle)
  eq(last(), "Unown puzzle, KABUTO. A picks up or puts down a piece, START quits. piece "
    .. first .. ", row 1, column 1", "puzzle entry")
  puzzle.cursor = 7
  SR.update(puzzle)
  eq(last(), "empty, row 2, column 2", "an empty middle cell")
  puzzle.cursor = 0
  SR.update(puzzle)
  puzzle.held, puzzle.holding, puzzle.pieces[1] = first, true, 0
  SR.update(puzzle)
  eq(last(), "Took piece " .. first, "picking up")
  puzzle.cursor = 7
  SR.update(puzzle)
  eq(last(), "empty, row 2, column 2", "moving while holding names the cell")
  puzzle.pieces[8], puzzle.held, puzzle.holding = first, 0, false
  SR.update(puzzle)
  eq(last(), "Placed piece " .. first, "putting down")
  check(not last():find("correct") and not last():find("belongs"), "no hint about the right place")
  puzzle.solved, puzzle.waiting = true, true
  SR.update(puzzle)
  eq(last(), "Puzzle complete. Press A.", "solved")
end

-- ------------------------------------------------------------ stamp viewer
do
  reset()
  local printer = require("src.ui.gen2.UnownPrinter").new(game, {})
  SR.update(printer)
  eq(last(), "ALPH RUINS STAMP. UNOWN A, 1 of 27. Left and right to browse, B to leave", "stamp entry")
  printer.index = 1
  SR.update(printer)
  eq(last(), "UNOWN B", "next letter")
  printer.index = 26
  SR.update(printer)
  eq(last(), "VACANT", "the vacant slot")
end

-- ------------------------------------------------------------ contest switch
do
  reset()
  local menu = gen2("ContestMenu", { game = game, choice = 1,
    stock = { nickname = "CATERPIE", level = 7, maxHp = 25 },
    caught = { species = "SCYTHER", level = 13, stats = { hp = 40 } } })
  SR.update(menu)
  eq(last(), "Switch POKéMON? STOCK PKMN: CATERPIE, level 7, HEALTH 25. THIS PKMN: SCYTHER, level 13, HEALTH 40. YES",
    "contest switch entry")
  menu.choice = 2
  SR.update(menu)
  eq(last(), "NO", "contest switch choice")
end

-- ------------------------------------------------------------ Battle Tower
do
  reset()
  local BT = require("src.ui.gen2.BattleTowerMenu")
  local menu = BT.new(game, { rows = { { group = 1 }, { group = 2 } }, party = {} })
  SR.update(menu)
  eq(last(), "What level do you want to challenge? level 10, 1 of 3. Up raises the level", "tower entry")
  menu.cursor = 2
  SR.update(menu)
  eq(last(), "level 20", "level up")
  menu.cursor = 3
  SR.update(menu)
  eq(last(), "CANCEL", "cancel row")
  menu:refuse("A party POKéMON\ntops this level.")
  SR.update(menu)
  eq(last(), "A party POKéMON tops this level.", "refusal")
  menu.phase, menu.cursor, menu.message = "pick", 1, "What level do you\nwant to challenge?"
  SR.update(menu)
  eq(last(), "What level do you want to challenge? level 10, 1 of 3", "picker after a refusal, hint not repeated")
  check(not lastInterrupts(), "picker after a refusal queues")
  menu.phase, menu.message, menu.yes = "quit", "Cancel your BATTLE\nROOM challenge?", true
  SR.update(menu)
  eq(last(), "Cancel your BATTLE ROOM challenge? YES", "quit question")
  menu.yes = false
  SR.update(menu)
  eq(last(), "NO", "quit choice")
end

-- ------------------------------------------------------------ Buena
do
  reset()
  local BP = require("src.ui.gen2.BuenaPassword")
  local pass = BP.new(game, { mode = "password", words = { "CYNDAQUIL", "TOTODILE", "CHIKORITA" } })
  SR.update(pass)
  eq(last(), "CYNDAQUIL, 1 of 3", "password entry")
  pass.index = 2
  SR.update(pass)
  eq(last(), "TOTODILE", "password move")
  reset()
  local prize = BP.new(game, { mode = "prize", balance = 5,
    prizes = { { name = "ULTRA BALL", cost = 2 }, { name = "NUGGET", cost = 3 } } })
  SR.update(prize)
  eq(last(), "Points 5. ULTRA BALL, 2 points, 1 of 2", "prize entry with the Points box")
  prize.index = 2
  SR.update(prize)
  eq(last(), "NUGGET, 3 points", "prize move")
end

-- ------------------------------------------------------------ conversations
do
  reset()
  local pageOne = { "I'm the DAY-CARE", "MAN. Want me to" }
  local pageTwo = { "MAN. Want me to", "raise a #MON?" }
  local confirm = { pages = { pageOne, pageTwo }, page = 1, choice = 1 }
  local daycare = gen2("DayCareMenu", { game = game, confirm = confirm,
    typer = { page = { pageOne[1], pageOne[2] }, shown = 0, total = 30 } })
  SR.update(daycare)
  eq(#spoken, 0, "a page is held until typing begins")
  daycare.typer.shown = 1
  SR.update(daycare)
  eq(last(), "I'm the DAY-CARE MAN. Want me to", "first page")
  confirm.page = 2
  daycare.typer = { page = { pageTwo[1], pageTwo[2] }, shown = 15, total = 30 }
  SR.update(daycare)
  eq(last(), "raise a POKéMON?", "a cont page drops the repeated line")
  daycare.typer.shown = 30
  SR.update(daycare)
  eq(last(), "YES", "YES once typed out")
  check(not lastInterrupts(), "first YES queues behind the question")
  confirm.choice = 2
  SR.update(daycare)
  eq(last(), "NO", "choice moves")
  check(lastInterrupts(), "choice moves interrupt")
  daycare.confirm, daycare.picking = nil, true
  SR.update(daycare)
  daycare.picking = false
  daycare.message = { pages = { { "Oh, fine then." } }, page = 1 }
  daycare.typer = { page = { "Oh, fine then." }, shown = 1, total = 14 }
  SR.update(daycare)
  eq(last(), "Oh, fine then.", "next message")

  reset()
  local trade = gen2("TradeMenu", { game = game,
    message = { pages = { { "KRIS traded", "ABRA for" } }, page = 1 },
    typer = { page = { "KRIS traded", "ABRA for" }, shown = 2, total = 20 } })
  SR.update(trade)
  eq(last(), "KRIS traded ABRA for", "trade conversation")
end

-- ------------------------------------------------------------ decorations
do
  reset()
  local DM = require("src.ui.gen2.DecorationMenu")
  local save = {}
  local deco = gen2("DecorationMenu", { game = game, save = save, mode = "category", index = 1,
    categories = { { label = "BED" }, { label = "ORNAMENT" } },
    state = { bed = 2, poster = 16, rightOrnament = 30 } })
  SR.update(deco)
  eq(last(), "Decoration. Set up: FEATHERY BED; TOWN MAP; PIKACHU DOLL, RIGHT SIDE. BED, 1 of 3",
    "decoration entry with what the room holds")
  check(save.decorations == nil, "reading never creates the save's decoration record")
  deco.index = 3
  SR.update(deco)
  eq(last(), "EXIT", "exit row from the screen's own label")
  deco.mode, deco.index, deco.rows, deco.category = "items", 1, { 3, 1, 0 }, { label = "BED" }
  SR.update(deco)
  eq(last(), "BED. PINK BED, 1 of 3", "category opened")
  deco.index = 3
  SR.update(deco)
  eq(last(), "CANCEL", "item cancel row")
  -- the side picker's labels come from the screen's own SIDES, in its order
  local sides
  for i = 1, 60 do
    local name, value = debug.getupvalue(DM.update, i)
    if name == nil then break end
    if name == "SIDES" then sides = value end
  end
  deco.mode, deco.sideIndex, deco.pendingDeco = "side", 1, 30
  SR.update(deco)
  eq(last(), "PIKACHU DOLL. " .. sides[1].label .. ", 1 of 3", "side picker entry")
  eq(sides[1].id, "right", "the first side row applies to the right side")
  check(last():find("RIGHT SIDE", 1, true) ~= nil, "first side row is spoken as the right side")
  deco.sideIndex = 2
  SR.update(deco)
  eq(last(), "LEFT SIDE", "second side row")
  deco.mode, deco.index = "items", 1
  SR.update(deco)
  eq(last(), "BED. PINK BED, 1 of 3", "back from the side picker to the list")
  deco.pages = { "Set up the\nPINK BED." }
  deco.typer = { page = { "Set up the", "PINK BED." }, shown = 1, total = 18 }
  SR.update(deco)
  eq(last(), "Set up the PINK BED.", "message over the list")
  deco.pages, deco.typer, deco.index = nil, nil, 1
  SR.update(deco)
  eq(last(), "PINK BED, 1 of 3", "row repeated when the message closes")
end

-- ------------------------------------------------------------ mail
do
  reset()
  local MC = require("src.ui.gen2.MailCompose")
  local compose = MC.new(game, {})
  SR.update(compose)
  eq(last(), "Write mail. empty. A", "compose entry")
  compose.col = 1
  SR.update(compose)
  eq(last(), "B", "cell move")
  compose:addCharacter("B")
  SR.update(compose)
  eq(last(), "B, B", "typed letter and text")
  compose:toggleCase()
  SR.update(compose)
  eq(last(), "lower case. b", "case change")
  compose.row, compose.col = 5, 0
  SR.update(compose)
  eq(last(), "UPPER", "the case key shows the case it switches to")
  compose.col = 3
  SR.update(compose)
  eq(last(), "DEL, delete", "delete key")
  compose.lower, compose.row, compose.col = false, 4, 0
  SR.update(compose)
  SR.update(compose)
  compose.row, compose.col = 4, 9
  SR.update(compose)
  eq(last(), "times", "symbol named")
  compose.row, compose.col = 2, 6
  SR.update(compose)
  eq(last(), "blank", "a blank cell")
  compose:addCharacter("<PO>")
  SR.update(compose)
  eq(last(), "PO, BPO", "a glyph token typed")
  compose:addCharacter("<KE>")
  SR.update(compose)
  eq(last(), "KE, BPOKé", "the POKé pair reads as POKé")
  compose.text = "ABCDEFGHIJKLMNOP"
  SR.update(compose)
  compose:addCharacter("Q")
  SR.update(compose)
  eq(last(), "Q, line 2, ABCDEFGHIJKLMNOPQ", "the 17th character starts line 2")
  compose:deleteCharacter()
  SR.update(compose)
  eq(last(), "deleted, ABCDEFGHIJKLMNOP", "deleting")

  -- reading must never fire the mail.read event (Mail.lines) or re-arm it
  local Mail = require("src.core.gen2.Mail")
  local linesCalls, mailboxCalls = 0, 0
  local realLines, realMailbox = Mail.lines, Mail.mailbox
  Mail.lines = function(...) linesCalls = linesCalls + 1 return realLines(...) end
  Mail.mailbox = function(...) mailboxCalls = mailboxCalls + 1 return realMailbox(...) end

  reset()
  SR.update(gen2("MailRead", { game = game,
    entry = { type = "FLOWER_MAIL", message = "HELLO\nTHERE <PK><MN>", author = "KRIS" } }))
  eq(last(), "FLOWER MAIL. HELLO THERE PKMN. From KRIS", "mail read")
  reset()
  SR.update(gen2("MailRead", { game = game, entry = { type = "SURF_MAIL", message = "HI", author = "" } }))
  eq(last(), "HI", "unknown stationery and blank author stay silent")

  reset()
  local menu = gen2("MailMenu", { game = game, index = 1 })
  SR.update(menu)
  eq(last(), "Mail. READ, 1 of 3", "mail menu entry")
  menu.index = 2
  SR.update(menu)
  eq(last(), "TAKE", "mail menu move")
  menu.confirm = { pages = { { "Send the removed", "MAIL to your PC?" } }, page = 1, choice = 1 }
  SR.update(menu)
  eq(last(), "Send the removed MAIL to your PC? YES", "question with its YES/NO at once")
  menu.confirm = nil
  SR.update(menu)
  eq(last(), "Mail. TAKE, 2 of 3", "menu row repeated after the question")

  reset()
  local box = gen2("MailboxMenu", { game = game, index = 1,
    save = { mail = { box = { { author = "KRIS", message = "HI" }, { author = "", message = "YO" } } } } })
  SR.update(box)
  eq(last(), "Mailbox. KRIS, 1 of 2", "mailbox entry")
  box.index = 2
  SR.update(box)
  eq(last(), "blank", "blank author")
  box.submenu = { index = 1 }
  SR.update(box)
  eq(last(), "READ MAIL, 1 of 4", "submenu opens")
  box.submenu.index = 2
  SR.update(box)
  eq(last(), "PUT IN PACK", "submenu move")
  box.submenu = nil
  SR.update(box)
  eq(last(), "blank, 2 of 2", "back on the letter")

  eq(linesCalls, 0, "Mail.lines never called by speech")
  eq(mailboxCalls, 0, "Mail.mailbox never called by speech")
  Mail.lines, Mail.mailbox = realLines, realMailbox
end

-- ------------------------------------------------------------ one-shot cards
do
  reset()
  SR.update(gen2("PhotoStudio", { game = game, playerName = "KRIS", pokemon = data.pokemon, moves = data.moves,
    mon = { species = "CHIKORITA", nickname = "LEAFY", level = 12, maxHp = 35, gender = "female",
      shiny = true, ot = "KRIS", otId = 1234, moves = { { id = "TACKLE" } } } }))
  eq(last(), "Photo. Number 152, level 12, HP 35, female, shiny. LEAFY, CHIKORITA. OT KRIS. ID 01234. Move TACKLE. Press A",
    "photo card")

  reset()
  SR.update(gen2("MagnetTrainRide", { game = game, ride = { toGoldenrod = true } }))
  eq(last(), "Magnet Train to Goldenrod City", "magnet train to Goldenrod")
  reset()
  SR.update(gen2("MagnetTrainRide", { game = game, ride = { toGoldenrod = false } }))
  eq(last(), "Magnet Train to Saffron City", "magnet train to Saffron")

  reset()
  SR.update(gen2("Diploma", { game = game, playerName = "KRIS" }))
  eq(last(), "Diploma. PLAYER KRIS. This certifies that you have completed the new POKéDEX. Congratulations! Press A",
    "diploma")

  reset()
  SR.update(as("src.world.gen2.UnownWords", { game = game, wall = { word = "ESCAPE" } }))
  eq(last(), "Unown letters on the wall: ESCAPE. E, S, C, A, P, E. Press A.", "wall word said then spelled")
end

-- ------------------------------------------------------------ trade animation
do
  reset()
  local anim = gen2("TradeAnim", { game = game, eventTables = {}, beat = { id = "givemon_scroll" },
    give = { dex = 63, name = "ABRA", otName = "KRIS", id = 1234, senderName = "KRIS" },
    get = { dex = 66, name = "MACHOP", otName = "MIKE", id = 37460, senderName = "MIKE" } })
  SR.update(anim)
  eq(last(), "Trade. B skips. Number 63, ABRA, OT KRIS, ID 01234", "trade entry and the given mon's panel")
  anim.beat = { id = "sent_blank" }
  SR.update(anim)
  anim.beat = { id = "sent_text" }
  SR.update(anim)
  eq(last(), "ABRA was sent to MIKE.", "text beat")
  check(not lastInterrupts(), "animation lines queue")
  anim.beat = { id = "getmon_poof" }
  SR.update(anim)
  eq(last(), "Number 66, MACHOP, OT MIKE, ID 37460", "received mon's panel")
end

-- ------------------------------------------------------------ Hall of Fame
do
  reset()
  local mon = { species = "TYPHLOSION", nickname = "BLAZE", level = 50, gender = "male", otId = 1234 }
  local hof = gen2("HallOfFame", { game = game, mode = "induct", phase = "backpic", index = 1,
    pokemon = data.pokemon, entry = { mons = { mon } },
    save = { player = { name = "KRIS", id = 1234 }, playTime = { hours = 25, minutes = 3 } } })
  SR.update(hof)
  eq(#spoken, 0, "nothing while the pictures slide in")
  hof.phase = "display"
  SR.update(hof)
  eq(last(), "New Hall of Famer! Number 157, TYPHLOSION, male, BLAZE, level 50, ID 01234", "inducted member")
  check(not lastInterrupts(), "induction queues")
  hof.phase = "playerBack"
  SR.update(hof)
  hof.phase = "player"
  SR.update(hof)
  eq(last(), "KRIS. ID 01234. play time 25:03", "player card")

  reset()
  local view = gen2("HallOfFame", { game = game, mode = "view", phase = "display", team = 1, index = 1,
    pokemon = data.pokemon, entry = { winCount = 3, mons = { mon, { species = "CHIKORITA", level = 9, otId = 5 } } } })
  SR.update(view)
  eq(last(), "Hall of Fame. 3-Time Famer. Number 157, TYPHLOSION, male, BLAZE, level 50, ID 01234. 1 of 2. A next, START next team, B leave",
    "viewer entry")
  view.index = 2
  SR.update(view)
  eq(last(), "Number 152, CHIKORITA, level 9, ID 00005. 2 of 2", "viewer next member")
end

-- ------------------------------------------------------------ credits
do
  reset()
  local credits = gen2("Credits", { game = game, shown = {} })
  SR.update(credits)
  credits.shown = { { text = "STAFF", x = 0, y = 8 }, { text = "#MON", x = 0, y = 6 } }
  SR.update(credits)
  eq(last(), "POKéMON, STAFF", "credits screen in reading order")
  check(not lastInterrupts(), "credits queue")
  credits.shown = { { theEnd = true, x = 6, y = 8 } }
  SR.update(credits)
  eq(last(), "THE END", "the end")
  credits.exiting = true
  SR.update(credits)
  eq(last(), "Press A", "credits wait for A")
end

-- ------------------------------------------------------------ Union Room, arena
do
  reset()
  local List = require("src.ui.gen2.union.List")
  local list = List.new(game, "TRADING BOARD", { { label = "PIKACHU", right = "Lv25" }, { label = "ONIX" } })
  SR.update(list)
  eq(last(), "TRADING BOARD. PIKACHU, Lv25, 1 of 2", "union list entry")
  list.index = 2
  SR.update(list)
  eq(last(), "ONIX", "union list move")

  reset()
  local model = {}
  function model:page() return { title = "BATTLE", lines = { "Rules" }, items = { { label = "READY" } }, cursor = 1 } end
  function model:label(v) return v end
  function model:formatLines(list) return list or {} end
  SR.update(as("src.ui.union.prep.Gen2BattlePrep", { game = game, model = model }))
  eq(last(), "BATTLE. Rules. READY, 1 of 1", "Gen 2 battle prep reads like Gen 1's")

  reset()
  local arena = gen2("ArenaState", { game = game, stage = "boot" })
  SR.update(arena)
  eq(#spoken, 0, "arena boot is quiet")
  arena.stage, arena.message = "failed", "The battle could not start."
  SR.update(arena)
  eq(last(), "The battle could not start.", "arena failure")
end

T.finish("gen2 special")
