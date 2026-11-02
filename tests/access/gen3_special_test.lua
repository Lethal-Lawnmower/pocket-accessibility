-- Gen 3 special screens and minigames (FireRed; decision 29).  The screens
-- are the real upstream singleton modules, with their fields set the way
-- their own functions set them; proxies are built the way gen3/Top.lua
-- builds them.  ROM text is not available headless, so RomText.plain is
-- replaced by a small table of stand-in strings (test data only), and
-- species names by a stand-in name table.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Speech = require("src.access.Speech")
local SR = require("src.access.screens.ScreenReader")
local Top = require("src.access.screens.gen3.Top")
local CurrentGame = require("src.access.CurrentGame")

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

-- ------------------------------------------------------------ stand-ins
local RomText = require("src.core.game3.rom_text")
local ROM = {
  gText_Yes = "YES", gText_No = "NO",
  gText_TimeBoard = "TIME BOARD",
  gText_ReleaseThisPokemon = "Release this\nPOKéMON?",
  gText_PkmnWasReleased = function(ctx) return ctx.dynamic[0] .. " was released." end,
  gText_ByeByePkmn = function(ctx) return "Bye-bye, " .. ctx.dynamic[0] .. "!" end,
  gOtherText_Powder = "POWDER",
  gText_Var1Players = function(ctx) return ctx.stringVars[1] .. " PLAYERS" end,
  gText_NumPlayerLink = function(ctx) return ctx.stringVars[1] .. " players in link" end,
  gText_HOFNumber = function(ctx) return "HALL OF FAME No. " .. ctx.stringVars[1] end,
  gText_HOFCorrupted = "The HALL OF FAME data is corrupted.",
  gText_WelcomeToHOF = "Welcome to the HALL OF FAME!",
  gText_LeagueChamp = "LEAGUE CHAMPION!\nCONGRATULATIONS!",
  gText_SavingDontTurnOffThePower2 = "SAVING… DON'T TURN OFF THE POWER.",
  gText_QuitEditing = "Quit editing?",
  gText_TradeAction_Summary = "SUMMARY", gText_TradeAction_Trade = "TRADE",
  gText_IsThisTradeOkay = "Is this trade okay?",
  ["sActionTexts[0]"] = "CANCEL", ["sActionTexts[1]"] = "Choose a POKéMON.", ["sActionTexts[4]"] = "Cancel trade?",
  ["sLevelUpWindowStatNames[0]"] = "MAX. HP", ["sLevelUpWindowStatNames[1]"] = "ATTACK",
  ["sLevelUpWindowStatNames[2]"] = "DEFENSE", ["sLevelUpWindowStatNames[3]"] = "SP. ATK",
  ["sLevelUpWindowStatNames[4]"] = "SP. DEF", ["sLevelUpWindowStatNames[5]"] = "SPEED",
  ["sSeagallopDestStrings[3]"] = "THREE ISLAND",
  ["sKeyboardSwapTexts[0]"] = "UPPER", ["sKeyboardSwapTexts[1]"] = "lower",
  ["sKeyboardSwapTexts[2]"] = "SYMBOLS", ["sKeyboardSwapTexts[3]"] = "REGISTER", ["sKeyboardSwapTexts[4]"] = "EXIT",
  ["sListMenuItems_TypeNames[1]"] = "FIRE",
  gText_CommunicationStandby4 = "Communication standby…",
  gText_SomeoneDroppedOut = "Someone dropped out.",
  gText_WantToPlayAgain2 = "Want to play again?",
}
RomText.plain = function(key, ctx)
  local text = ROM[key]
  if text == nil then error("no stand-in for " .. tostring(key)) end
  if type(text) == "function" then return text(ctx or {}) end
  return text
end
local Family = require("src.core.game3.link.family")
Family.textKey = function(key) return key end

local Pokemon = require("src.core.game3.pokemon")
Pokemon._names = { [6] = "CHARIZARD", [25] = "PIKACHU", [141] = "KABUTOPS", [142] = "AERODACTYL", [3] = "VENUSAUR" }
Pokemon.gender = function(_, personality)
  if personality == 1 then return "M" end
  if personality == 2 then return "F" end
  return "U"
end
Pokemon.isEgg = function(mon) return mon and mon.egg == true end
Pokemon.displayName = function(mon) return mon.nickname or Pokemon._names[mon.species] end
Pokemon.speciesOf = function(mon) return mon.species end
Pokemon.national = function(sp) return sp end

local game = { generation = 3, phase = "field" }

-- A layer proxy as Top.resolve builds it.
local function layerProxy(id, mod)
  local layer = { id = id, mod = mod }
  return Top._proxy(layer, id, { layer = layer, mod = mod, game = game })
end

-- Polls the overlays only (gen3 game current, an inert top).
local inert = {}
local function overlays()
  CurrentGame.set(game)
  SR.update(inert)
end

-- ------------------------------------------------------------ slot machine
do
  reset()
  local Model = require("src.core.game3.slot_machine")
  local Slots = require("src.ui.game3.slot_machine")
  local session = { coins = 120 }
  Slots.open = true
  Slots._session = session
  Slots.state = Model.newState(0)
  Slots.task = "bet"
  Slots.helpPhase = nil
  local st = Slots.state
  local p = layerProxy("slot_machine", Slots)
  SR.update(p)
  eq(last(), "Slot machine. CREDIT 120. Down bets 1 coin, R bets 3, A spins and stops each reel, Right shows the payout chart",
    "slot entry: title, credit and controls")
  Model.betOne(st, session)
  SR.update(p)
  eq(last(), "Bet 1: middle row. CREDIT 119", "bet 1 lights the middle row")
  Model.betOne(st, session)
  SR.update(p)
  eq(last(), "Bet 2: top, middle and bottom rows. CREDIT 118", "bet 2 adds top and bottom")
  Model.betOne(st, session)
  SR.update(p)
  eq(last(), "Bet 3: 3 rows and 2 diagonals. CREDIT 117", "bet 3 adds both diagonals")
  -- the update's begin_spin
  Slots.task = "stopping"
  Model.startReels(st)
  SR.update(p)
  eq(last(), "Spinning", "spin start")
  local before = #spoken
  for _ = 1, 5 do st.reelPositions[0] = (st.reelPositions[0] + 1) % 21 SR.update(p) end
  eq(#spoken, before, "spinning reels are silent")
  -- reel 1 lands at position 0: rows show strip cells 1, 2, 3
  st.reelPositions[0] = 0
  st.reelIsSpinning[0] = false
  SR.update(p)
  local function name(icon)
    for k, v in pairs(Model.ICON) do if v == icon then return k == "SEVEN" and "7" or k end end
  end
  eq(last(), "Reel 1: " .. name(Model.iconAt(0, 1)) .. ", " .. name(Model.iconAt(0, 2)) .. ", " .. name(Model.iconAt(0, 3)),
    "a stopped reel says its three symbols top to bottom")
  eq(lastInterrupts(), false, "reel results queue")
  -- reels 2 and 3, then the result, in one frame for the last reel
  st.reelPositions[1], st.reelIsSpinning[1] = 0, false
  SR.update(p)
  check(last():find("^Reel 2: ") ~= nil, "second reel")
  st.reelPositions[2], st.reelIsSpinning[2] = 0, false
  Model.calcPayout(st)
  st.bet = 0
  Slots.task = st.slotRewardClass == Model.PAYOUT.NONE and "lose" or "win"
  SR.update(p)
  if Slots.task == "lose" then
    check(last():find("^Reel 3: .*%. No win$") ~= nil, "last reel then the loss: " .. tostring(last()))
  else
    check(last():find("^Reel 3: .*%. Win%. PAYOUT %d+") ~= nil, "last reel then the win: " .. tostring(last()))
  end
  -- a forced win: middle row of three 7s
  reset()
  Slots.task = "bet"
  SR.update(p)
  for line = 0, 4 do st.winFlags[line] = false end
  st.payout, st.winFlags[2] = 300, true
  local orig = Model.visibleIcons
  Model.visibleIcons = function() local t = {} for i = 0, 8 do t[i] = Model.ICON.CHERRIES end
    t[1], t[4], t[7] = Model.ICON.SEVEN, Model.ICON.SEVEN, Model.ICON.SEVEN return t end
  Slots.task = "win"
  SR.update(p)
  eq(last(), "Win. PAYOUT 300. middle row: 7, 7, 7", "win names the line and its symbols")
  Model.visibleIcons = orig
  session.coins = 417
  Slots.task = "bet"
  SR.update(p)
  eq(last(), "CREDIT 417", "credit after the payout")
  -- payout chart
  Slots.task, Slots.helpPhase = "help", "in"
  SR.update(p)
  Slots.helpPhase = "shown"
  SR.update(p)
  eq(last(), "Payout chart. 3 7, 300. 3 ROCKET, 100. 3 PIKACHU or PSYDUCK, 15. 3 MAGNEMITE or SHELLDER, 8. "
    .. "CHERRIES on reels 1 and 2, 6. CHERRIES on reel 1, 2", "payout chart from the model")
  -- quit question
  Slots.helpPhase, Slots.task = nil, "quit"
  Slots._message, Slots._yesNo = "Quit playing?", 1
  SR.update(p)
  eq(last(), "Quit playing? YES", "quit question and YES")
  Slots._yesNo = 2
  SR.update(p)
  eq(last(), "NO", "quit moves to NO")
  eq(lastInterrupts(), true, "yes/no moves interrupt")
  Slots.open, Slots.state = false, nil
end

-- ------------------------------------------------------------ prize corner, coins box
do
  reset()
  local Prize = require("src.ui.game3.prize_corner")
  Prize.open = true
  Prize.rows = Prize.buildRows(Prize.LIST_POKEMON_PRIZES, { "ABRA 180 COINS", "CLEFAIRY 500 COINS", "CANCEL" })
  Prize.cursor = 1
  local p = layerProxy("prize_corner", Prize)
  SR.update(p)
  eq(last(), "ABRA, 180 COINS, 1 of 3", "prize entry: name, amount, position")
  Prize.cursor = 2
  SR.update(p)
  eq(last(), "CLEFAIRY, 500 COINS", "prize move")
  Prize.cursor = 3
  SR.update(p)
  eq(last(), "CANCEL", "row without an amount")

  -- the coins box beside the clerk belongs to the Menus presenters
  reset()
  local Coins = require("src.ui.game3.coins_box")
  Coins.show(1, 1, 50)
  overlays()
  eq(#spoken, 0, "the coins box is not read here")
  Coins.hide()

  reset()
  local Powder = require("src.ui.game3.berry_powder_box")
  package.loaded["src.core.game3.scripting.space"] = package.loaded["src.core.game3.scripting.space"] or {}
  local Space = package.loaded["src.core.game3.scripting.space"]
  Space.vm = { id = "vm" }
  Powder.show(1200)
  overlays()
  eq(last(), "POWDER 1200", "berry powder shown")
  Space.vm = { id = "other" }
  local n = #spoken
  Powder._amount = 1300
  overlays()
  eq(#spoken, n, "a box left by its script is not read (and not hidden by reading)")
  eq(Powder.visible, true, "reading never hides the box")
  Powder.hide()
  Space.vm = nil
end

-- ------------------------------------------------------------ records
do
  reset()
  local R = require("src.ui.game3.trainer_tower_records")
  R.open, R._kind, R._phase = true, "tower", "in"
  R._rows = { { label = "SINGLES", time = "3 min. 12.45 sec." }, { label = "DOUBLES", time = "10 min. 0.00 sec." } }
  local p = layerProxy("trainer_tower_records", R)
  SR.update(p)
  eq(#spoken, 0, "records stay quiet while fading in")
  R._phase = "wait"
  SR.update(p)
  eq(last(), "TIME BOARD. SINGLES, 3 min. 12.45 sec. DOUBLES, 10 min. 0.00 sec.", "time board rows")
  reset()
  R._kind, R._title, R._total = "link", "RED's battle results", "TOTAL RECORD W: 3 L: 1 D: 0"
  R.columnHeaders = function() return { "WIN", "LOSE", "DRAW" } end
  R._rows = { { name = "BLUE", wins = "   3", losses = "   1", draws = "   0" },
    { name = "-------", wins = "----", losses = "----", draws = "----" } }
  local p2 = layerProxy("trainer_tower_records", R)
  SR.update(p2)
  eq(last(), "RED's battle results. TOTAL RECORD W: 3 L: 1 D: 0. BLUE, WIN 3, LOSE 1, DRAW 0. No record",
    "link records with headers; dash rows are empty")
  R.open = false

  reset()
  local M = require("src.ui.game3.minigame_records")
  M.open, M._kind = true, "pokemon_jump"
  M._lines = { { text = "POKéMON JUMP RECORDS", x = 0 }, { text = "JUMPS IN A ROW:", x = 0 }, { text = "12", x = 200 },
    { text = "BEST SCORE:", x = 0 }, { text = "340", x = 190 } }
  SR.update(layerProxy("minigame_records", M))
  eq(last(), "POKéMON JUMP RECORDS. JUMPS IN A ROW: 12. BEST SCORE: 340", "records pair labels with values")
  M.open = false
end

-- ------------------------------------------------------------ wireless, Direct Corner, Union Room
do
  reset()
  local LinkMenu = require("src.ui.game3.link_menu")
  local Status = require("src.core.game3.link.status")
  rawset(Status, "HEADER", { [0] = "Wireless Communication Status" })
  LinkMenu.open = true
  LinkMenu.rows = { { label = "People trading:", count = 0 }, { label = "People battling:", count = 2 } }
  local p = layerProxy("wireless_status", LinkMenu)
  SR.update(p)
  eq(last(), "Wireless Communication Status. People trading: 0. People battling: 2", "status title and counts")
  LinkMenu.rows = { { label = "People trading:", count = 1 }, { label = "People battling:", count = 2 } }
  SR.update(p)
  eq(last(), "People trading: 1", "only a changed count")
  LinkMenu.open = false

  reset()
  local Direct = LinkMenu.Direct
  local ListMenu = require("src.ui.game3.list_menu")
  Direct.open, Direct.view = true, "modes"
  Direct.modes = ListMenu.new({ items = { { label = "AUTO" }, { label = "CHOOSE" }, { label = "EXIT" } }, maxShowed = 3 })
  Direct.count = 0
  local dp = layerProxy("direct_corner", LinkMenu)
  SR.update(dp)
  eq(last(), "AUTO, 1 of 3", "direct corner modes")
  Direct.modes:setSelected(2)
  SR.update(dp)
  eq(last(), "CHOOSE", "mode move")
  Direct.view = "choose"
  Direct.rows = { k1 = { key = "k1", name = "BLUE", trainerId = 12345 } }
  Direct.fresh = { k1 = 64 }
  Direct.list = ListMenu.new({ items = { { row = Direct.rows.k1 }, { row = nil, disabled = true } }, maxShowed = 5 })
  SR.update(dp)
  eq(last(), "BLUE, ID 12345, new, 1 of 2", "player row with ID and the new mark")
  Direct.rows.k2 = { key = "k2", name = "GREEN", trainerId = 1 }
  Direct.list:setSelected(2)
  SR.update(dp)
  eq(last(), "GREEN joined. empty", "an arrival, then the empty slot")
  Direct.count = 2
  SR.update(dp)
  eq(last(), "2 players in link", "player count box")
  Direct.open = false

  reset()
  local U = require("src.ui.game3.union_room")
  U.open, U.mode, U.list = true, "group", nil
  U.players, U.cursor = {}, 1
  local up = layerProxy("union_room", U)
  SR.update(up)
  eq(last(), "1 PLAYERS. Searching...", "union room search")
  U.players = { { name = "BLUE", activity = 0 } }
  SR.update(up)
  eq(last(), "2 PLAYERS. BLUE, 1 of 1", "a player appears")
  -- trade board
  reset()
  U.mode = "board"
  U.list = ListMenu.new({ items = { { label = "", disabled = true, entry = { name = "RED", species = 25, level = 14, wantType = 10 } },
    { label = "EXIT" } }, maxShowed = 5 })
  U.fontText = function() return "NAME WANTED OFFER LV." end
  SR.update(up)
  eq(last(), "NAME WANTED OFFER LV. RED, wants FIRE, offers PIKACHU, level 14, 1 of 2", "board row names the type badge")
  U.open, U.list = false, nil
end

-- ------------------------------------------------------------ union chat
do
  reset()
  local Chat = require("src.core.game3.link.chat")
  local UnionChat = require("src.ui.game3.union_chat")
  Chat.lines = { { text = "BLUE:hi", seat = 1 } }
  Chat.buffer, Chat.page, Chat.row, Chat.col = {}, 0, 0, 0
  Chat.msg, Chat.yesNo, Chat.swap = nil, nil, nil
  Chat._rows = { gText_UnionRoomChatKeyboard_ABCDE = { "A", "B", "C", "D", "E" } }
  local p = layerProxy("union_chat", UnionChat)
  SR.update(p)
  eq(last(), "UPPER. A", "chat entry: page and key (history not re-read)")
  Chat.col = 2
  SR.update(p)
  eq(last(), "C", "key move")
  Chat.buffer = { "C" }
  SR.update(p)
  eq(last(), "C, C", "typed letter and the line so far")
  Chat.buffer = {}
  SR.update(p)
  eq(last(), "deleted, empty", "deleted")
  Chat.lines[#Chat.lines + 1] = { text = "BLUE\252\19\42:hey {EMOJI_HEART}", seat = 1 }
  SR.update(p)
  eq(last(), "BLUE:hey heart emoji", "a new log line, emoji named")
  Chat.swap = { cursor = 3 }
  SR.update(p)
  eq(last(), "REGISTER, 4 of 5", "swap menu row with position")
  Chat.swap = nil
  Chat.msg = { text = "Quit chatting?" }
  Chat.yesNo = { cursor = 1 }
  SR.update(p)
  eq(last(), "Quit chatting? NO", "message and the yes/no (cursor 1 is NO)")
  Chat.msg, Chat.yesNo = nil, nil
end

-- ------------------------------------------------------------ link trade, trade scene, PIN
do
  reset()
  local Trade = require("src.ui.game3.link_trade_menu")
  local Link = require("src.core.game3.link")
  local LT = require("src.core.game3.link.trade")
  local mine = { { nickname = "SPARKY", species = 25, level = 14, personality = 1, item = 0 } }
  local origSession = Link.session
  Link.session = function() return { party = mine } end
  LT.peerParty = { { species = 3, level = 30, personality = 2 } }
  Trade.open, Trade.cb, Trade.pos, Trade.message, Trade.bottom = true, "main", 0, nil, "choose"
  local p = layerProxy("link_trade", Trade)
  SR.update(p)
  eq(last(), "Choose a POKéMON. Your party, SPARKY, level 14, male, 1 of 1", "trade menu entry")
  Trade.pos = 6
  SR.update(p)
  eq(last(), "Partner's party, VENUSAUR, level 30, female, 1 of 1", "partner side")
  Trade.pos = 12
  SR.update(p)
  eq(last(), "CANCEL", "cancel button")
  Trade.pos, Trade.cb, Trade.subCursor = 0, "selected", 1
  SR.update(p)
  eq(last(), "SUMMARY, 1 of 2", "submenu")
  Trade.subCursor = 2
  SR.update(p)
  eq(last(), "TRADE", "submenu move")
  Trade.cb, Trade.message = "idle", "Communication standby…"
  SR.update(p)
  eq(last(), "Communication standby…", "trade message")
  Link.session = origSession
  Trade.open = false

  reset()
  local Scene = require("src.ui.game3.trade_scene")
  local s = { text = "" }
  Scene._core = { state = function() return s end }
  local sp = layerProxy("trade_scene", Scene)
  SR.update(sp)
  s.text = "SPARKY will be sent to BLUE."
  SR.update(sp)
  eq(last(), "SPARKY will be sent to BLUE.", "trade caption")
  eq(lastInterrupts(), false, "captions queue")
  Scene._core = nil

  reset()
  local Pin = require("src.ui.game3.pin_entry")
  Pin.show({ mode = "enter" })
  local pp = layerProxy("pin_entry", Pin)
  SR.update(pp)
  eq(last(), "Enter the 4-digit PIN. digit 1 of 4, 0", "PIN entry")
  Pin.digits[1] = 7
  SR.update(pp)
  eq(last(), "7", "scrubbed digit")
  Pin.cursor = 2
  SR.update(pp)
  eq(last(), "digit 2 of 4, 0", "next digit; the first stays hidden")
  Pin.error = "Wrong PIN."
  SR.update(pp)
  eq(last(), "Wrong PIN. digit 2 of 4, 0", "error replaces the title")
  Pin.close()
end

-- ------------------------------------------------------------ Mystery Gift (boot)
do
  reset()
  local st = { state = "main_menu", rows = { "WONDER CARDS", "WONDER NEWS", "EXIT" }, cursor = 1, session = {} }
  ROM.gText_MysteryGift = "MYSTERY GIFT"
  local p = Top._proxy(st, "mystery_gift", { game = game })
  SR.update(p)
  eq(last(), "MYSTERY GIFT. WONDER CARDS, 1 of 3", "gift menu entry")
  st.cursor = 2
  SR.update(p)
  eq(last(), "WONDER NEWS", "gift menu move")
  st.msg = { text = "You don't have any WONDER NEWS." }
  SR.update(p)
  eq(last(), "You don't have any WONDER NEWS.", "gift message")
  st.msg = nil
  st.state, st.isNews = "saved_view", false
  st.viewCard = { titleText = "BERRY CARD", subtitleText = "EVENT", idNumber = 3, bodyText = { "Get a BERRY", "", "", "" },
    footerLine1Text = "Thanks", type = 0, iconSpecies = 25 }
  SR.update(p)
  eq(last(), "BERRY CARD. EVENT. number 3. Get a BERRY. Thanks. Picture: PIKACHU", "card read whole, icon named")
  st.yesno = { text = "Throw away the card?", cursor = 1 }
  SR.update(p)
  eq(last(), "Throw away the card? YES", "card question")
  st.yesno.cursor = 2
  SR.update(p)
  eq(last(), "NO", "question move")
  check(st.session.mysteryGift == nil and st.session.modData == nil, "reading created no save record")
end

-- ------------------------------------------------------------ Easy Chat
do
  reset()
  local EC = require("src.ui.game3.easy_chat")
  local E = require("src.core.game3.easy_chat_text")
  local origWord, origGroup, origInGroup = E.word, E.groupName, E.wordInGroup
  E.word = function(id) return ({ [1] = "HELLO", [2] = "FRIEND" })[id] end
  E.groupName = function(g) return g.name end
  E.wordInGroup = function(entry) return entry.text end
  EC.footerLabels = function() return { "DEL. ALL", "CANCEL", "OK" } end
  EC.openFlag = true
  EC._state = { title = "PROFILE", instr1 = "Combine four words", instr2 = "and make your profile.",
    confirm1 = "Your profile", confirm2 = "Is it as shown?", words = { 1, E.EC_WORD_UNDEFINED, 2, E.EC_WORD_UNDEFINED },
    count = 4, cols = 2, mode = "SLOT", selectedSlot = 1, footerIdx = 3,
    groups = { { name = "POKéMON", words = {} }, { name = "GREETINGS", words = { { id = 1, text = "HELLO" }, { id = 9, text = "BYE" } } } },
    groupCursor = 1, wordCursor = 1, wordPage = 0, confirmChoice = 1 }
  local st = EC._state
  local p = layerProxy("easy_chat", EC)
  SR.update(p)
  eq(last(), "PROFILE. Combine four words and make your profile. HELLO FRIEND. word 1 of 4, HELLO", "easy chat entry")
  st.selectedSlot = 2
  SR.update(p)
  eq(last(), "word 2 of 4, empty", "empty slot")
  st.mode = "GROUP"
  SR.update(p)
  eq(last(), "POKéMON, 1 of 2", "group list")
  st.groupCursor = 2
  SR.update(p)
  eq(last(), "GREETINGS, 2 of 2", "group move")
  st.mode = "WORD"
  SR.update(p)
  eq(last(), "HELLO, 1 of 2", "word list")
  st.wordCursor = 2
  SR.update(p)
  eq(last(), "BYE", "word move")
  st.mode, st.words[2], st.selectedSlot = "SLOT", 9, 3
  E.word = function(id) return ({ [1] = "HELLO", [2] = "FRIEND", [9] = "BYE" })[id] end
  SR.update(p)
  eq(last(), "HELLO BYE FRIEND. word 3 of 4, FRIEND", "back on the slots: the phrase, then the slot")
  st.mode, st.footerIdx = "FOOTER", 3
  SR.update(p)
  eq(last(), "OK, 3 of 3", "footer")
  st.mode, st.confirmChoice = "CONFIRM", 1
  SR.update(p)
  eq(last(), "Your profile HELLO BYE FRIEND. Is it as shown? YES", "confirm with the phrase")
  st.mode, st.confirmChoice = "CANCEL_CONFIRM", 2
  SR.update(p)
  eq(last(), "Quit editing? NO", "cancel question")
  E.word, E.groupName, E.wordInGroup = origWord, origGroup, origInGroup
  EC.openFlag, EC._state = false, nil
end

-- ------------------------------------------------------------ Day-Care
do
  reset()
  local D = require("src.ui.game3.daycare_menu")
  D.open, D.cursor = true, 1
  D.rowList = { { text = "PIKACHU", symbol = "♂", level = "Lv12" }, { text = "NIDORAN♀", symbol = "", level = "Lv5" },
    { text = "EXIT", symbol = "", level = "" } }
  local p = layerProxy("daycare_level_menu", D)
  SR.update(p)
  eq(last(), "PIKACHU, male, level 12, 1 of 3", "day-care row")
  D.cursor = 2
  SR.update(p)
  eq(last(), "NIDORAN♀, level 5", "name with its own sign")
  D.cursor = 3
  SR.update(p)
  eq(last(), "EXIT", "exit row")
  D.rowList[2] = { text = "", symbol = "", level = "" }
  D.cursor = 2
  SR.update(p)
  eq(last(), "empty", "a slot with no Pokémon")
  D.open = false
end

-- ------------------------------------------------------------ Hall of Fame, PC, diploma, credits, whiteout
do
  reset()
  local H = require("src.ui.game3.hall_of_fame")
  H.open, H._session, H._national = true, { name = "RED", trainerId = 54321, playTimeHours = 12, playTimeMinutes = 5 }, true
  H._saving, H._info, H._welcome, H._playerInfo = true, nil, false, false
  local p = layerProxy("hall_of_fame", H)
  SR.update(p)
  eq(last(), "SAVING… DON'T TURN OFF THE POWER.", "saving line")
  H._saving = false
  H._info = { species = 6, nickname = "CHARIZARD", level = 50, personality = 1, otId = 54321 }
  SR.update(p)
  eq(last(), "CHARIZARD, male, level 50, number 006, ID 54321", "member card, species not repeated")
  eq(lastInterrupts(), false, "members queue")
  H._info = { species = 25, nickname = "SPARKY", level = 40, personality = 2, otId = 7 }
  SR.update(p)
  eq(last(), "SPARKY, PIKACHU, female, level 40, number 025, ID 00007", "nicknamed member")
  H._info, H._welcome = nil, true
  SR.update(p)
  eq(last(), "Welcome to the HALL OF FAME!", "welcome")
  H._welcome, H._playerInfo = false, true
  SR.update(p)
  eq(last(), "RED. ID 54321. time 12:05. LEAGUE CHAMPION! CONGRATULATIONS!", "player card")
  H.open = false

  reset()
  local Pc = require("src.ui.game3.hall_of_fame_pc")
  Pc.open, Pc._corrupted, Pc._national, Pc._number, Pc._team, Pc._mon = true, false, false, 2, 1, 1
  Pc._teams = { { { species = 6, nickname = "CHARIZARD", level = 51, personality = 1, trainerId = 1 },
    { species = 252, nickname = "TREECKO", level = 5, personality = 0, trainerId = 1 } } }
  Pokemon._names[252] = "TREECKO"
  local pp = layerProxy("hall_of_fame_pc", Pc)
  SR.update(pp)
  eq(last(), "HALL OF FAME No. 2. CHARIZARD, male, level 51, number 006, ID 00001, 1 of 2", "PC header and member")
  Pc._mon = 2
  SR.update(pp)
  eq(last(), "TREECKO, level 5, number ???, ID 00001, 2 of 2", "beyond Kanto shows ??? without the national dex")
  Pc.open = false

  reset()
  local Diploma = require("src.ui.game3.diploma")
  Diploma.open, Diploma._player, Diploma._body, Diploma._gameFreak = true, "PLAYER: RED", "This document certifies…", "GAME FREAK"
  SR.update(layerProxy("diploma", Diploma))
  eq(last(), "PLAYER: RED. This document certifies… GAME FREAK", "diploma lines")
  Diploma.open = false

  reset()
  local Credits = require("src.ui.game3.credits")
  local cs = { text = nil, mon = nil, closing = nil, whichMon = 0 }
  local origState = Credits.state
  Credits.state = function() return cs end
  local cp = layerProxy("credits", Credits)
  cs.text = { title = "Director" }
  SR.update(cp)
  eq(#spoken, 0, "a title waits for its names")
  cs.text.names = "Junichi Masuda"
  SR.update(cp)
  eq(last(), "Director. Junichi Masuda", "credit block")
  cs.text = { title = "Art Director\nBattle Director", names = "Ken Sugimori\nShigeki Morimoto" }
  SR.update(cp)
  eq(last(), "Art Director, Battle Director. Ken Sugimori, Shigeki Morimoto", "one role or name per line")
  cs.mon = { def = { species = 25 } }
  SR.update(cp)
  eq(last(), "PIKACHU", "starter scene")
  cs.closing, cs.whichMon = { shown = true }, 1
  SR.update(cp)
  eq(last(), "THE END", "the end picture")
  Credits.state = origState

  reset()
  local Rush = require("src.ui.game3.whiteout_rush")
  Rush._state = { phase = "hold", text = "RED scurried to a POKéMON CENTER…" }
  local rp = layerProxy("whiteout_rush", Rush)
  SR.update(rp)
  eq(#spoken, 0, "quiet during the hold")
  Rush._state.phase = "print"
  SR.update(rp)
  eq(last(), "RED scurried to a POKéMON CENTER…", "whiteout text")
  Rush._state = nil
end

-- ------------------------------------------------------------ mod manager
do
  reset()
  local MM = require("src.ui.game3.mod_manager")
  local ManagerState = require("src.mods.ManagerState")
  local mgr = setmetatable({ screen = "list", tab = 1, cursor = 1 }, ManagerState)
  mgr.rowsForScreen = function() return { { label = "Jukebox", mod = { enabled = true } } } end
  mgr.isStaged = function() return false end
  mgr.runsHere = function() return true end
  MM._mgr, MM._prompt = mgr, nil
  local p = layerProxy("mod_manager", MM)
  SR.update(p)
  eq(last(), "Mod manager, Mods tab. Jukebox, enabled, 1 of 1", "the Gen 1 manager presenter reads the Gen 3 screen")
  MM._prompt = { kind = "qty", title = "HOW MANY?", value = 3, max = 99 }
  SR.update(p)
  eq(last(), "HOW MANY? 3, up to 99", "quantity prompt")
  MM._prompt.value = 4
  SR.update(p)
  eq(last(), "4", "quantity change")
  MM._prompt = nil
  SR.update(p)
  eq(last(), "Mod manager, Mods tab. Jukebox, enabled, 1 of 1", "back from the prompt: context again")
  MM._mgr = nil
end

-- ------------------------------------------------------------ minigames
do
  reset()
  local MG = require("src.core.game3.minigames.common")
  local cd = { state = 1, digit = { alive = true, frame = 0 } }
  function cd:digitShown() if not self.digit.alive then return nil end return 3 - self.digit.frame end
  MG._run = { stage = "active", match = { phase = "ready" } }
  local p = layerProxy("minigame", MG)
  SR.update(p)
  eq(last(), "Communication standby…", "standby")
  MG._run.match.phase, MG._run.match.countdown = "countdown", cd
  SR.update(p)
  eq(last(), "3", "countdown 3")
  cd.digit.frame = 1
  SR.update(p)
  eq(last(), "2", "countdown 2")
  cd.digit.alive, cd.state = false, 2
  SR.update(p)
  eq(last(), "Start", "start")
  MG._run.match.phase = "play"
  MG._run.match.sim = { game = { gfx = { msgWindow = { key = "gText_WantToPlayAgain2", shown = true }, yesno = { cursor = 0 } } } }
  SR.update(p)
  eq(last(), "Want to play again? YES", "Pokémon Jump play again")
  MG._run.match.sim.game.gfx.yesno.cursor = 1
  SR.update(p)
  eq(last(), "NO", "jump yes/no move")
  MG._run.stage, MG._run.text = "message", "gText_SomeoneDroppedOut"
  SR.update(p)
  eq(last(), "Someone dropped out.", "drop message")
  MG._run = nil

  reset()
  local Lobby = require("src.ui.game3.minigames.common_lobby")
  Lobby.open, Lobby.mode, Lobby.players, Lobby.me = true, "leader", {}, { name = "RED" }
  Lobby.message = function() return "Awaiting communication." end
  Lobby.modeText = function() return "2-5 players" end
  local lp = layerProxy("minigame_lobby", Lobby)
  SR.update(lp)
  eq(last(), "Awaiting communication. 2-5 players. RED", "leader lobby")
  Lobby.players = { { name = "BLUE", trainerId = 1 } }
  SR.update(lp)
  eq(last(), "BLUE joined. 2-5 players", "a member joins")
  Lobby.open = false
end

-- ------------------------------------------------------------ overlays
do
  -- braille: the decoded text, labelled, once per message
  reset()
  local Message = require("src.ui.game3.message")
  local Braille = require("src.ui.game3.braille")
  Braille._text = "CUT"
  Message.open, Message._frame, Message._pages, Message._page = true, "braille", { "CUT" }, 1
  overlays()
  eq(last(), "Braille: CUT", "braille labelled and decoded")
  overlays()
  eq(#spoken, 1, "braille said once")
  Message.open, Message._frame, Message._pages = false, "dialogue", nil

  -- Seagallop crossing
  reset()
  local Sea = require("src.ui.game3.seagallop")
  Sea._active, Sea._run = true, { dest = 3 }
  overlays()
  eq(last(), "SEAGALLOP to THREE ISLAND", "ferry destination")
  Sea._active, Sea._run = false, nil

  -- pictures
  reset()
  local Pic = require("src.ui.game3.mon_pic")
  Pic.active, Pic.species = true, 25
  overlays()
  eq(last(), "Picture: PIKACHU", "mon picture")
  overlays()
  eq(#spoken, 1, "picture said once")
  Pic.active = false
  overlays()
  local Space = package.loaded["src.core.game3.scripting.space"]
  local fossil = { species = 141 }
  Space.vm = { ctx = { museumFossilPic = fossil } }
  local MuseumPic = require("src.ui.game3.museum_fossil_pic")
  local origActive = MuseumPic.isActive
  local called = false
  MuseumPic.isActive = function() called = true return false end
  overlays()
  eq(last(), "Picture of a KABUTOPS fossil", "fossil picture")
  check(not called, "MuseumPic.isActive is never called")
  MuseumPic.isActive = origActive
  Space.vm = nil

  -- the forest card, the release sequence and the level-up window are
  -- read by the Menus, Items and Battle presenters, not here
  reset()
  local Preview = require("src.ui.game3.map_preview_screen")
  local Release = require("src.ui.game3.release_seq")
  local Growth = require("src.ui.game3.stat_growth")
  Preview._active, Preview._entry, Preview._name = true, {}, "VIRIDIAN FOREST"
  Release.active, Release.state, Release.yesNoCursor, Release.mon = true, "confirm", 2, { nickname = "SPARKY", species = 25 }
  Growth.open({}, { maxHp = 20 }, { maxHp = 23 })
  overlays()
  -- the forest title card belongs to the menus presenter (gen3/Menus.lua),
  -- which says it; the release sequence and level-up window stay quiet here
  local others = {}
  for _, entry in ipairs(spoken) do
    if entry.text ~= "VIRIDIAN FOREST" then others[#others + 1] = entry.text end
  end
  eq(#others, 0, "overlays owned by other presenters stay quiet here: " .. table.concat(others, " | "))
  Preview._active, Preview._entry = false, nil
  Release.active, Release.state = false, "idle"
  Growth.close({ silent = true })

  -- Itemfinder arrow
  reset()
  local Finder = require("src.core.game3.itemfinder")
  Finder._task = { result = { underfoot = false, itemX = -2, itemY = 5, dings = 2 } }
  overlays()
  eq(last(), "Itemfinder points down", "arrow along the larger offset")
  Finder._task = nil

  -- VS Seeker
  reset()
  local Events = require("src.core.game3.step_events")
  local V = require("src.core.game3.vs_seeker")
  local seq = { t = 0 }
  local ev = { type = "vs_seeker", tick = function() return seq end }
  Events._activeEvent = ev
  overlays()
  eq(#spoken, 0, "nothing before the result")
  seq.response, seq.responders = V.RESPONSE_FOUND_REMATCHES, { {}, {} }
  overlays()
  eq(last(), "VS Seeker: 2 trainers want a rematch", "rematch count")
  Events._activeEvent = nil

  -- arena
  reset()
  local arena = { stage = "linking", message = "Please wait." }
  game.phase, game.arena = "arena", arena
  overlays()
  eq(last(), "Please wait.", "arena standby")
  arena.stage, arena.message = "failed", "The battle could not start."
  overlays()
  eq(last(), "The battle could not start.", "arena failure")
  game.phase, game.arena = "field", nil

  CurrentGame.set(nil)
end

-- Lines and chart wording are derived from the model's own tables.
do
  local Special = require("src.access.screens.gen3.Special")
  local Model = require("src.core.game3.slot_machine")
  eq(Special._lineName(Model, 0), "diagonal from top left", "line 0")
  eq(Special._lineName(Model, 4), "diagonal from bottom left", "line 4")
  eq(Special._lineName(Model, 1), "top row", "line 1")
end

-- ------------------------------------------------------------ Union Room prep (cross-generation)
do
  reset()
  local model = { cursorAt = 1 }
  function model:page()
    return { title = "BATTLE RULES", lines = { "Level 50", "Singles" }, info = {},
      items = { { label = "READY" }, { label = "CANCEL" } }, cursor = self.cursorAt }
  end
  function model:label(text) return text end
  function model:formatLines(lines) return lines end
  local layerRec = { id = "union_battle_prep", mod = { model = model } }
  local p = Top._proxy(layerRec, "union_battle_prep", { layer = layerRec, mod = layerRec.mod, game = game })
  SR.update(p)
  eq(last(), "BATTLE RULES. Level 50 Singles. READY, 1 of 2", "Gen 3 Union battle prep read through the Gen 1 page model")
  model.cursorAt = 2
  SR.update(p)
  eq(last(), "CANCEL, 2 of 2", "prep cursor")
  local tradeRec = { id = "union_trade_prep", mod = { ctl = model } }
  model.cursorAt = 1
  local q = Top._proxy(tradeRec, "union_trade_prep", { layer = tradeRec, mod = tradeRec.mod, game = game })
  SR.update(q)
  eq(last(), "BATTLE RULES. Level 50 Singles. READY, 1 of 2", "Gen 3 Union trade prep (ctl)")
end

-- The cross-generation Union battle layer only paints Message and Choice:
-- its text is the screen, read as dialogue.
do
  reset()
  local Stack = require("src.ui.game3.stack")
  local Message = require("src.ui.game3.message")
  local saved = Stack._layers
  Stack._layers = {}
  Stack.push("g3u_battle", { handleInput = function() end }, { hideBelow = true })
  local pages = { "Waiting for the other player..." }
  Message.open, Message._pages, Message._page, Message._frame = true, pages, 1, "battle"
  local top = Top.resolve(game)
  eq(top and top.gen3, "message", "the Union battle's message is the screen, not its layer")
  Message.open, Message._pages, Message._frame = false, nil, nil
  Stack._layers = saved
end

T.finish("gen3 special")
