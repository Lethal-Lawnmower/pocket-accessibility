-- Gen 3 menu presenters (FireRed; decision 29): boot, the new game scene,
-- naming, start menu, OPTION and CONTROLS, SAVE, help, quest log, trainer
-- card, Fame Checker, Teachy TV, move relearner, evolution, egg hatching,
-- script list menus and the passive overlays.  The real upstream screen
-- modules are loaded and their fields set the way their own code sets
-- them; cart text comes from RomText overrides.  The screen is found the
-- way the game finds it: a fake Game3 through CurrentGame, gen3/Top.lua,
-- the real ScreenReader, a fake speech backend.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Speech = require("src.access.Speech")
local SR = require("src.access.screens.ScreenReader")
local GameVersion = require("src.core.GameVersion")
local CurrentGame = require("src.access.CurrentGame")
local RomText = require("src.core.game3.rom_text")
local TextIR = require("src.core.game3.scripting.text_ir")
local Stack = require("src.ui.game3.stack")
local Message = require("src.ui.game3.message")
local Choice = require("src.ui.game3.choice")
local Menus = require("src.access.screens.gen3.Menus")

GameVersion.set("firered")

local spoken = {}
local fake = { name = "Fake" }
function fake:say(text, interrupt) spoken[#spoken + 1] = { text = text, interrupt = interrupt } return true end
function fake:stop() return true end
function fake:close() end
Speech.shutdown()
Speech.start({ backend = fake })

local function text(key, value) RomText.overrides[key] = TextIR.fromAscii(value) end
local function last() return spoken[#spoken] and spoken[#spoken].text end
local function lastInterrupt() return spoken[#spoken] and spoken[#spoken].interrupt end
local function count() return #spoken end
local function said(i) return spoken[i] and spoken[i].text end

local game = { generation = 3, phase = "boot", options = { firered = {} }, session = {} }
CurrentGame.set(game)

local Help = require("src.ui.game3.help_system")
local function reset(phase)
  for i = #spoken, 1, -1 do spoken[i] = nil end
  SR._resetForTests()
  Stack._layers = {}
  Message.open, Message._pages, Message._page, Message._stay = false, nil, 1, false
  Choice.active, Choice.done, Choice.options = false, nil, nil
  Help.open = false
  game.phase = phase or "boot"
  game.boot = nil
  game.options.firered.accessDialogue = nil
end
local function update(n) for _ = 1, n or 1 do SR.update() end end

-- ---------------------------------------------------------------- boot
reset("boot")
local IntroMovie = require("src.ui.game3.intro_movie")
local movie = setmetatable({ phase = "copyright", isDone = false }, IntroMovie)
game.boot = { phase = "intro", introMovie = movie }
update()
eq(count(), 0, "copyright card is an image: nothing said")
movie.phase, movie.ptr = "intro", { cb = "Init" }
update()
eq(last(), "Intro. Press start to skip.", "intro hint once skipping works")
eq(lastInterrupt(), false, "boot lines queue")
movie.ptr.cb = "GF_RevealName"
update(2)
eq(last(), "GAME FREAK presents.", "GAME FREAK name revealed")
eq(count(), 2, "each intro line once")

local Title = require("src.ui.game3.title_screen")
require("src.ui.game3.boot")
reset("boot")
game.boot = { phase = "title", title = { scene = Title.SCENE.FADEIN } }
update()
eq(count(), 0, "title waits for the RUN scene")
game.boot.title.scene = Title.SCENE.RUN
update(2)
eq(last(), "POKéMON FireRed Version. Press start.", "title names the running game")
eq(count(), 1, "title said once")
GameVersion.set("leafgreen")
reset("boot")
game.boot = { phase = "title", title = { scene = Title.SCENE.RUN } }
update()
eq(last(), "POKéMON LeafGreen Version. Press start.", "LeafGreen title from the imported game")
GameVersion.set("firered")

text("gText_Continue", "CONTINUE") text("gText_NewGame", "NEW GAME")
text("gText_MysteryGift", "MYSTERY GIFT") text("gText_MenuExit", "EXIT")
text("gText_Player", "PLAYER") text("gText_Time", "TIME") text("gText_Pokedex", "POKEDEX")
text("gText_Badges", "BADGES")
reset("boot")
local fading = true
game.boot = { phase = "menu", menuIndex = 1, hasContinue = true,
  menuFade = { fadeActive = function() return fading end },
  continueInfo = { name = "RED", hours = 1, minutes = 5, hasDex = true, dexCount = 3, badges = 2 } }
update()
eq(count(), 0, "main menu quiet while it fades in")
fading = false
update()
eq(last(), "Main menu. CONTINUE, 1 of 4. PLAYER RED, TIME 1:05, POKEDEX 3, BADGES 2",
  "main menu entry with the CONTINUE panel once the fade ends")
game.boot.menuIndex = 2
update()
eq(last(), "NEW GAME", "a move says the row")
game.boot.continueInfo.hasDex = false
game.boot.menuIndex = 1
update()
eq(last(), "CONTINUE. PLAYER RED, TIME 1:05, BADGES 2", "no Pokédex line before the Pokédex")
game.boot.fadeThen = "continue"
game.boot.menuIndex = 2
update()
eq(last(), "CONTINUE. PLAYER RED, TIME 1:05, BADGES 2", "quiet while fading out")

reset("boot")
game.boot = { phase = "menu", saveError = { pages = { "The save file has\nbeen deleted…", "Page two." }, page = 1 } }
update()
eq(last(), "The save file has been deleted…", "save error first page")
game.boot.saveError.page = 2
update()
eq(last(), "Page two.", "save error next page")

-- ------------------------------------------------------ new game scene
local Scene = require("src.ui.game3.new_game_scene")
text("gText_Controls", "CONTROLS") text("gText_ABUTTONNext", "{A_BUTTON}NEXT")
text("gText_ABUTTONNext_BBUTTONBack", "{A_BUTTON}NEXT {B_BUTTON}BACK")
text("gControlsGuide_Text_Intro", "The various buttons will be\nexplained.")
text("sControlsGuide_Pages2And3_Strings[0]", "Moves the character.")
text("sControlsGuide_Pages2And3_Strings[1]", "Confirms.")
text("sControlsGuide_Pages2And3_Strings[2]", "Cancels.")
text("sControlsGuide_Pages2And3_Strings[3]", "Opens the MENU.")
text("sControlsGuide_Pages2And3_Strings[4]", "Uses an item.")
text("sControlsGuide_Pages2And3_Strings[5]", "Opens help.")
reset("boot")
local scene = setmetatable({ section = "controls", win = {} }, Scene)
game.boot = { phase = "controls", newGame = scene }
scene.win.topbar = { title = "gText_Controls", hint = "gText_ABUTTONNext" }
scene.win.guide = { page = 1 }
update()
eq(last(), "CONTROLS. The various buttons will be explained. A button NEXT", "guide page 1 with title and hint")
scene.win.guide = nil
update()
scene.win.topbar = { hint = "gText_ABUTTONNext_BBUTTONBack" }
scene.win.guide = { page = 2 }
update()
eq(last(), "Control Pad. Moves the character. A Button. Confirms. B Button. Cancels. A button NEXT B button BACK",
  "guide page 2 names each pictured button before its string")
scene.win.guide = nil
scene.win.guide = { page = 3 }
update()
eq(last(), "START Button. Opens the MENU. SELECT Button. Uses an item. L and R Buttons. Opens help. A button NEXT B button BACK",
  "guide page 3 names START, SELECT and L and R")
scene.win.guide = nil
scene.win.pika = { text = "In the world which you are\nabout to enter…" }
update()
eq(last(), "In the world which you are about to enter… A button NEXT B button BACK", "Pikachu page")

scene.section, scene.win.pika, scene.win.topbar = "oak", nil, nil
scene.printer = { pages = { "Hello, there!\nGlad to meet you!", "Welcome to the world of\nthe crea-", "tures called POKéMON!" }, page = 1 }
update()
eq(last(), "Hello, there! Glad to meet you!", "Oak's first page")
eq(lastInterrupt(), true, "Oak's pages interrupt like dialogue")
scene.printer.page = 2
update()
eq(last(), "Welcome to the world of the creatures called POKéMON!", "a word split across pages is finished")
local before = count()
scene.printer.page = 3
update()
eq(count(), before, "the carried line is not said again")

scene.win.menu = { kind = "gender", items = { { "BOY", 8, 1 }, { "GIRL", 8, 17 } }, cursor = 0 }
update()
eq(last(), "BOY, 1 of 2", "gender menu with position")
eq(lastInterrupt(), false, "first selection queues behind Oak's line")
scene.win.menu.cursor = 1
update()
eq(last(), "GIRL", "gender move")
eq(lastInterrupt(), true, "moves interrupt")
scene.win.menu = nil
-- RepeatNameQuestion: an instant line and the name list in one frame
scene.printer = { pages = { "Your name? What is it?" }, page = 1 }
scene.win.menu = { kind = "names", items = { { "NEW NAME" }, { "RED" }, { "FIRE" }, { "ASH" }, { "KENE" } }, cursor = 0 }
update()
eq(last(), "Your name? What is it? NEW NAME, 1 of 5", "line and list in one utterance")
scene.win.menu = { kind = "yesno", items = { { "YES" }, { "NO" } }, cursor = 0 }
update()
eq(last(), "YES", "yes/no without position")
game.options.firered.accessDialogue = "whole"
scene.win.menu = nil
scene.printer = { pages = { "That's right!", "His name is BLUE!" }, page = 1 }
update()
eq(last(), "That's right! His name is BLUE!", "ALL AT ONCE speaks every page of Oak's line")
before = count()
scene.printer.page = 2
update()
eq(count(), before, "and nothing after")
game.options.firered.accessDialogue = nil

-- --------------------------------------------------------------- naming
local Naming = require("src.ui.game3.naming")
reset("boot")
game.boot = { phase = "oak", newGame = scene }
local st = { title = "YOUR NAME?", name = "", page = 1, row = 1, col = 1, btn = 1, maxLen = 7 }
Naming._state = st
Stack.push("naming", Naming, { hideBelow = true })
update()
eq(last(), "YOUR NAME? empty. upper case. A", "naming entry: title, name, page, cell")
st.col = 2
update()
eq(last(), "B", "cell move")
st.name = "B"
update()
eq(last(), "B, B", "typed letter and name")
st.name = "BE"
update()
eq(last(), "E, BE", "second letter")
st.name = "B"
update()
eq(last(), "deleted, B", "delete")
st.page = 2
update()
eq(last(), "lower case. b", "page change")
st.col, st.btn = 9, 1
update()
eq(last(), "page, to others", "PAGE button names the next page")
st.btn = 2
update()
eq(last(), "back, delete a letter", "BACK button")
st.btn = 3
update()
eq(last(), "OK, confirm name", "OK button")
st.page, st.row, st.col = 3, 4, 1
update()
eq(last(), "others. ellipsis", "OTHERS page and its ellipsis")
st.col = 2
update()
eq(last(), "open quote", "quote cell spelled")
st.pcPages, st.pcPage = { "BE was transferred to\nthe PC.", "BOX 1 is full." }, 1
update()
eq(last(), "BE was transferred to the PC.", "sent-to-PC page")
st.pcPage = 2
update()
eq(last(), "BOX 1 is full.", "next PC page")

-- ----------------------------------------------------------- start menu
local StartMenu = require("src.ui.game3.start_menu")
text("gText_Yes", "YES") text("gText_No", "NO")
reset("field")
StartMenu.open, StartMenu.cursor, StartMenu._confirmExit, StartMenu._prompt = true, 1, false, nil
StartMenu.ENTRIES = { { id = "pokedex", label = "POKéDEX" }, { id = "bag", label = "BAG" },
  { id = "trainer", label = "RED" }, { id = "exit", label = "EXIT" } }
StartMenu._kind = "normal"
Stack.push("start", StartMenu, { hideBelow = true })
update()
eq(last(), "Start menu. POKéDEX, 1 of 4", "start menu entry")
StartMenu.cursor = 3
update()
eq(last(), "RED", "player row says the player's name")
StartMenu.cursor = 4
update()
StartMenu._confirmExit, StartMenu._confirmCursor = true, 2
StartMenu._prompt = { revealed = 0, total = 20 }
update()
eq(last(), "RETURN TO MAIN MENU?", "exit prompt as it starts typing")
StartMenu._prompt.revealed = 20
update()
eq(last(), "NO", "YES/NO once typed, NO first")
eq(lastInterrupt(), false, "queued behind the prompt")
StartMenu._confirmCursor = 1
update()
eq(last(), "YES", "confirm move")
StartMenu._confirmExit, StartMenu._prompt = false, nil
update()
eq(last(), "EXIT, 4 of 4", "back from the confirm repeats the row")

-- -------------------------------------------------------------- options
local OptionMenu = require("src.ui.game3.option_menu")
text("sOptionMenuItemsNames[6]", "CANCEL")
reset("field")
local speed = "MID"
local topPage = { title = "OPTION", index = 1, scroll = 0, rows = {
  { id = "group.speed", label = "SPEED", group = true, value = function() return "4 OPTIONS" end },
  { id = "buttonMode", label = "BUTTON MODE", value = function(ctx) return ctx.marker end },
} }
OptionMenu.open, OptionMenu._pages, OptionMenu._ctx = true, { topPage }, { game = game, marker = "HELP" }
Stack.push("option", OptionMenu, { hideBelow = true })
update()
eq(last(), "OPTION. SPEED, 4 OPTIONS, 1 of 3", "options entry: title, row, value, position with CANCEL")
topPage.index = 2
update()
eq(last(), "BUTTON MODE, HELP", "move: label and value")
OptionMenu._ctx.marker = "LR"
update()
eq(last(), "LR", "value change says the value only")
topPage.index = 3
update()
eq(last(), "CANCEL", "CANCEL row")
OptionMenu._pages[2] = { title = "SPEED", index = 1, scroll = 0,
  rows = { { id = "textSpeed", label = "TEXT SPEED", value = function() return speed end } } }
update()
eq(last(), "SPEED. TEXT SPEED, MID, 1 of 2", "a group page says its title")
speed = "FAST"
update()
eq(last(), "FAST", "group page value change")
OptionMenu._pages[2] = nil
update()
eq(last(), "OPTION. CANCEL, 3 of 3", "back on the top page")

-- ------------------------------------------------------------- controls
local Controls = require("src.ui.game3.controls_menu")
reset("field")
local bm = { index = 1, footer = "RESET ALL BINDINGS?",
  items = { { label = "UP", right = "UP/D-UP" }, { label = "A", right = "X/Z" } } }
Controls._bm, Controls._confirm = bm, nil
Stack.push("controls", Controls, { hideBelow = true })
update()
eq(last(), "CONTROLS. UP, UP/D-UP, 1 of 2", "controls entry")
bm.index = 2
update()
eq(last(), "A, X/Z", "controls move")
bm.items[2].right = "X/Z/ENTER"
update()
eq(last(), "X/Z/ENTER", "a new binding says the value")
bm.capture = bm.items[2]
update()
eq(last(), "PRESS A BUTTON. RELEASE TO SET. ESC/2ND CANCELS", "capture prompt")
bm.capture = nil
update()
eq(last(), "A, X/Z/ENTER, 2 of 2", "back from the capture")
Controls._confirm = { index = 2 }
update()
eq(last(), "RESET ALL BINDINGS? NO", "reset confirm question and choice")
Controls._confirm.index = 1
update()
eq(last(), "YES", "confirm move")
Controls._confirm = nil

-- ----------------------------------------------------------------- save
local SaveMenu = require("src.ui.game3.save_menu")
text("gSaveStatName_Player", "PLAYER") text("gSaveStatName_Badges", "BADGES")
text("gSaveStatName_Pokedex", "POKEDEX") text("gSaveStatName_Time", "TIME")
text("gText_WouldYouLikeToSaveTheGame", "Would you like to\nsave the game?")
text("gText_AlreadySaveFile_WouldLikeToOverwrite", "There is already a saved file.\nIs it okay to overwrite it?")
text("gText_PlayerSavedTheGame", "{PLAYER} saved\nthe game.")
reset("field")
SaveMenu.open, SaveMenu._phase, SaveMenu.cursor, SaveMenu._layout = true, "confirm", 1, "frlg"
SaveMenu._session = { name = "RED", mapName = "PALLET TOWN", playTime = { hours = 1, minutes = 5 }, flags = {} }
Stack.push("save", SaveMenu, { hideBelow = true })
update()
eq(last(), "Save. PALLET TOWN, PLAYER RED, BADGES 0, TIME 1:05. Would you like to save the game? YES",
  "save entry: panel, question, YES")
SaveMenu.cursor = 2
update()
eq(last(), "NO", "save choice")
SaveMenu._phase, SaveMenu.cursor = "overwrite", 1
update()
eq(last(), "There is already a saved file. Is it okay to overwrite it? YES", "overwrite question")
SaveMenu._phase = "saved"
update()
eq(last(), "RED saved the game.", "saved line with the player's name")

-- ----------------------------------------------------------------- help
text("gString_Help", "HELP") text("gText_HelpSystemControls_A_Next", "{A_BUTTON}NEXT")
reset("field")
Help.pack = {
  greetings = "Greetings, {PLAYER}!\nThis is the HELP System.",
  topics = { [1] = "About this game", [2] = "How do I do this?", [6] = "CANCEL" },
  descriptions = { [1] = "Detailed descriptions.", [2] = "Hints for {RIVAL}.", [6] = "Close." },
}
Help.session = { name = "RED", rivalName = "BLUE" }
Help.open, Help.level, Help.cursor = true, "welcome", 1
update()
eq(last(), "HELP. A button NEXT. Greetings, RED! This is the HELP System.", "help opens with the greeting")
Help.level = "main"
Help.rows = { { id = 1, label = "About this game" }, { id = 2, label = "How do I do this?" }, { label = "CANCEL" } }
update()
eq(last(), "About this game, 1 of 3. Detailed descriptions.", "main level row and its description")
Help.cursor = 2
update()
eq(last(), "How do I do this? Hints for BLUE.", "move: row and description, placeholders expanded")
Help.level, Help.topic, Help.cursor = "submenu", 2, 1
Help.rows = { { id = 7, label = "I can't leave a room!" }, { label = "CANCEL" } }
update()
eq(last(), "How do I do this? I can't leave a room!, 1 of 2", "submenu: topic, question, position")
Help.level = "article"
Help.article = { question = "I can't leave a room!", answer = "L1\nL2\nL3\nL4\nL5\nL6\nL7\nL8" }
Help.articleScroll = 0
update()
eq(last(), "I can't leave a room! L1 L2 L3 L4 L5 L6 L7 L8", "article: question and the whole answer")
Help.articleScroll = 1
update()
eq(last(), "L8", "scrolling down says the line that came into view")
Help.articleScroll = 0
update()
eq(last(), "L1", "scrolling up says the top line")

-- ------------------------------------------------------------ quest log
local QuestUI = require("src.ui.game3.quest_log")
reset("quest_log")
QuestUI.pack = { text = { PreviouslyOnYourQuest = "Previously on your quest…", Arrived = "Arrived in {S1}.",
  Saved = "{PLAYER} saved the game." } }
local events = { { key = "Arrived", args = { "PALLET TOWN" } }, { key = "Saved", args = {} } }
local playback = { index = 1, final = false, current = 1 }
function playback:isFinal() return self.final end
function playback:number() return 2 end
function playback:event() return events[self.current] end
game.session = { name = "RED" }
game.questPlayback = playback
update()
eq(last(), "A button NEXT B button SKIP. Previously on your quest… 2. Arrived in PALLET TOWN.",
  "quest log: controls, title with scene number, first event")
playback.current = 2
update()
eq(last(), "RED saved the game.", "next event")
eq(lastInterrupt(), false, "timed events queue")
playback.index, playback.final, playback.current = 2, true, 1
update()
eq(last(), "Previously on your quest… Arrived in PALLET TOWN.", "last scene: no number, no extra full stop")
game.questPlayback = nil

-- --------------------------------------------------------- trainer card
local TrainerCard = require("src.ui.game3.trainer_card")
text("gText_TrainerCardName", "NAME: ") text("gText_TrainerCardIDNo", "IDNo.")
text("gText_TrainerCardMoney", "MONEY") text("gText_PokedollarVar1", "{STR_VAR_1}Y")
text("gText_TrainerCardPokedex", "POKEDEX") text("gText_TrainerCardTime", "TIME") text("gText_Colon2", ":")
text("gText_HallOfFameDebut", "HALL OF FAME DEBUT")
reset("field")
TrainerCard.open, TrainerCard.side, TrainerCard._flip, TrainerCard._rse = true, "front", nil, false
TrainerCard._card = { playerName = "RED", trainerId = 1234, money = 3000, hasPokedex = true,
  caughtMonsCount = 5, playTimeHours = 1, playTimeMinutes = 5,
  badges = { true, true, false, false, false, false, false, false }, stars = 1,
  hasHofResult = true, hofDebutHours = 20, hofDebutMinutes = 3, hofDebutSeconds = 9,
  hasLinkResults = false, hasTrades = false, unionRoomNum = 0, berryCrushPoints = 0 }
Stack.push("trainer", TrainerCard, { hideBelow = true })
update()
eq(last(), "Trainer card. NAME: RED, IDNo.01234, MONEY 3000Y, POKEDEX 5, TIME 1:05. Badges, 2 of 8. 1 star",
  "card front: texts as printed, badges and stars counted")
TrainerCard.side, TrainerCard._flip = "back", { phase = "down" }
update()
before = count()
TrainerCard._flip = nil
update()
eq(last(), "RED, HALL OF FAME DEBUT 20:03:09", "card back once the flip ends")
check(count() == before + 1, "nothing during the flip")

-- --------------------------------------------------------- fame checker
local Fame = require("src.ui.game3.fame_checker")
reset("field")
Fame.open, Fame.mode, Fame.pickMode, Fame.cursor, Fame.scroll = true, "top", false, 1, 0
Fame.iconCursor, Fame.textPage, Fame._pages, Fame._rows, Fame._view = 0, 1, nil, nil, nil
Stack.push("fame_checker", Fame, { hideBelow = true })
update()
eq(count(), 0, "quiet until the screen's own draw builds its view")
eq(Fame._rows, nil, "reading never builds the rows")
local rows = { { person = 0, label = "OAK" }, { person = 3, label = "BROCK" }, { cancel = true, label = "CANCEL" } }
Fame._rows = rows
local function view(extra)
  local v = { rows = rows, cursor = Fame.cursor, scroll = Fame.scroll, mode = Fame.mode,
    pickMode = Fame.pickMode, iconCursor = Fame.iconCursor, textPage = Fame.textPage,
    pages = Fame._pages, row = rows[Fame.cursor], help = "{A_BUTTON}READ" }
  for k, value in pairs(extra or {}) do v[k] = value end
  Fame._view = v
end
view()
update()
eq(last(), "OAK, 1 of 3. A button READ", "Fame Checker entry: person, position, help line")
Fame.cursor = 3
update()
before = count()
view({ msg = "The FAME CHECKER will be closed." })
update()
eq(count(), before + 1, "waits for the fresh view")
eq(last(), "CANCEL. The FAME CHECKER will be closed.", "cancel row and its message")
Fame.cursor, Fame.mode, Fame.iconCursor = 1, "flavor", 1
view({ icons = { [0] = { unlocked = false }, [1] = { unlocked = true }, [2] = { unlocked = false },
  [3] = { unlocked = false }, [4] = { unlocked = false }, [5] = { unlocked = false } },
  loc = "RESEARCH LAB", obj = "PROF. OAK", msg = "Page one of the story." })
update()
eq(last(), "OAK. RESEARCH LAB. PROF. OAK. Page one of the story. panel 2 of 6", "a found panel")
local icons = Fame._view.icons
Fame.iconCursor = 2
view({ icons = icons })
update()
eq(last(), "unknown. panel 3 of 6", "a panel not yet found")

-- ------------------------------------------------------------ Teachy TV
local Tv = require("src.ui.game3.teachy_tv")
reset("field")
Tv.open, Tv.closing, Tv.state, Tv.cursor = true, false, "list", 1
Tv._rows = { { label = "Teach me how to battle." }, { label = "CANCEL" } }
Stack.push("teachy_tv", Tv, { hideBelow = true })
update()
eq(last(), "Teach me how to battle., 1 of 2", "Teachy TV list entry")
Tv.cursor = 2
update()
eq(last(), "CANCEL", "list move")
Tv.state, Tv._pages, Tv.page = "lesson", { "Hey, all you TRAINERS\nout there!", "HELLO, TRAINERS!" }, 1
update()
eq(last(), "Hey, all you TRAINERS out there!", "lesson page")
Tv.page = 2
update()
eq(last(), "HELLO, TRAINERS!", "next lesson page")
Tv.state, Tv.cursor = "list", 1
update()
eq(last(), "Teach me how to battle., 1 of 2", "back on the list")

-- ------------------------------------------------------- move relearner
local MR = require("src.ui.game3.move_relearner")
local realPokemon = package.loaded["src.core.game3.pokemon"]
local realSummary = package.loaded["src.core.game3.summary_data"]
package.loaded["src.core.game3.pokemon"] = {
  moveName = function(id) return ({ [33] = "TACKLE", [45] = "GROWL" })[id] end,
  battleMove = function(id) return ({ [33] = { type = "NORMAL", power = 35, accuracy = 95, pp = 35 },
    [45] = { type = 10, power = 0, accuracy = 100, pp = 40 } })[id] end,
  name = function(species) return species == 25 and "PIKACHU" or "?" end,
}
package.loaded["src.core.game3.summary_data"] = { moveDescription = function(_, name) return name .. " hits." end }
text("gFameCheckerText_Cancel", "CANCEL")
text("gTypeNames[10]", "FIRE")
require("src.core.game3.battle.types")
reset("field")
MR.open, MR.state, MR.cursor, MR._moves, MR._info = true, "list", 1, { 33, 45 }, nil
MR.prompt = "Teach which move to PIKACHU?"
Stack.push("move_relearner", MR, { hideBelow = true })
update()
eq(last(), "Teach which move to PIKACHU? TACKLE. TYPE NORMAL. POWER 35. ACCURACY 95. PP 35. EFFECT TACKLE hits., 1 of 3",
  "relearner entry: prompt, move details, position")
MR.cursor = 2
update()
eq(last(), "GROWL. TYPE FIRE. POWER ---. ACCURACY 100. PP 40. EFFECT GROWL hits.",
  "move with no power; a type id is named from the cart's type names")
eq(MR._info, nil, "the screen's move cache is untouched")
MR.cursor = 3
update()
eq(last(), "CANCEL", "CANCEL row")
MR.state, MR.prompt, MR.yesNoCursor = "yesno", "Give up trying to teach a new move to PIKACHU?", 1
update()
eq(last(), "Give up trying to teach a new move to PIKACHU? YES", "give-up question and YES")
MR.yesNoCursor = 2
update()
eq(last(), "NO", "yes/no move")
MR.state, MR.prompt = "list", "Teach which move to PIKACHU?"
update()
eq(last(), "CANCEL, 3 of 3", "back on the list")

-- ----------------------------------------------- evolution, egg hatching
local Evo = require("src.ui.game3.evolution_scene")
reset("field")
Evo.open, Evo._state, Evo._canStop = true, "intro_msg", true
Message.open, Message._pages, Message._page = true, { "What? CHARMANDER\nis evolving!" }, 1
Stack.push("evolution_scene", Evo, { hideBelow = true })
update()
eq(last(), "What? CHARMANDER is evolving!", "evolution message read under the scene's layer")
Evo._state = "cycle"
update()
eq(last(), "Press B to stop the evolution.", "B hint while it can be stopped")
eq(lastInterrupt(), false, "hint queues")
update()
Message._pages = { "Congratulations! Your\nCHARMANDER evolved into", "CHARMELEON!" }
Message._page = 1
update()
eq(last(), "Congratulations! Your CHARMANDER evolved into", "congratulations page")
Message._page = 2
update()
eq(last(), "CHARMELEON!", "second page")
Message._pages, Message._page, Message._stay = { "Stop learning EMBER?" }, 1, true
Choice.active, Choice.kind, Choice.options, Choice.cursor, Choice.done = true, "yesno", { "YES", "NO" }, 1, function() end
update()
eq(last(), "Stop learning EMBER? YES", "learning question and yes/no shown together")
Choice.cursor = 2
update()
eq(last(), "NO", "yes/no move")

local Egg = require("src.ui.game3.egg_hatch")
reset("field")
Stack.push("egg_hatch", Egg, { hideBelow = true })
update()
eq(last(), "Egg hatching.", "egg scene entry")
eq(lastInterrupt(), false, "queued")
Message.open, Message._pages, Message._page = true, { "PIKACHU hatched from the EGG!" }, 1
update()
eq(last(), "PIKACHU hatched from the EGG!", "hatched message")

-- ----------------------------------------------------- script list menu
local ListMenu = require("src.core.game3.scripting.natives_listmenu")
local Menu = ListMenu.Menu
reset("field")
Message.open, Message._pages, Message._page, Message._stay = true, { "Which floor do you want?" }, 1, true
update()
eq(last(), "Which floor do you want?", "the question first")
Menu.open, Menu.labels, Menu.scroll, Menu.row, Menu.count = true, { "5F", "4F", { text = "CANCEL" } }, 0, 1, 3
Stack.push("script_list_menu", Menu, { hideBelow = false })
update()
eq(last(), "5F, 1 of 3", "floor list over the question")
eq(lastInterrupt(), false, "queued behind the still-visible question")
Menu.row = 2
update()
eq(last(), "4F", "floor move")
Menu.row = 3
update()
eq(last(), "CANCEL", "a { text } label")
-- question and list opened in the same frame: the question is said first
reset("field")
Message.open, Message._pages, Message._page = true, { "Which floor?" }, 1
Menu.row = 1
Stack.push("script_list_menu", Menu, { hideBelow = false })
update()
eq(said(1), "Which floor?", "a never-spoken question under the list comes first")
eq(said(2), "5F, 1 of 3", "then the list")
-- a message or yes/no that opens after the list (a confirmation the list's
-- script shows) is the screen until it closes
reset("field")
Menu.row = 1
Stack.push("script_list_menu", Menu, { hideBelow = false })
update()
eq(last(), "5F, 1 of 3", "list alone")
Message.open, Message._pages, Message._page, Message._stay = true, { "You want 5F?" }, 1, true
update()
eq(last(), "You want 5F?", "a newer message wins over the list")
Choice.active, Choice.kind, Choice.options, Choice.cursor, Choice.done = true, "yesno", { "YES", "NO" }, 1, function() end
update()
eq(last(), "YES", "and its yes/no")
Choice.active, Choice.done = false, nil
Message.open, Message._pages = false, nil
update()
eq(last(), "5F, 1 of 3", "back on the list when they close")
-- a clerk's script can leave its greeting open under the shop: the shop
-- (driven by name in Hud's update_top_menu) is the screen, the greeting
-- is reported as covered
local Top = require("src.access.screens.gen3.Top")
local ShopMenu = require("src.ui.game3.shop_menu")
reset("field")
Message.open, Message._pages, Message._page = true, { "May I help you?" }, 1
Stack.push("shop", ShopMenu, { hideBelow = false })
local shopTop, under = Top.resolve(game)
eq(shopTop and shopTop.gen3, "shop", "the shop is the screen over the clerk's open message")
eq(under and under.gen3, "message", "the message is reported as covered")
check(Top.edge == Top._edge, "edge is public, _edge kept as an alias")
-- a layer that takes no input leaves the message in charge
reset("field")
Message.open, Message._pages, Message._page = true, { "Hello." }, 1
Stack.push("passive_window", {}, { hideBelow = false })
update()
eq(last(), "Hello.", "message stays the screen over a passive layer")

-- Teachy TV's Poké Dude demos push a layer that only drives the TM case or
-- bag under it: the screen is the layer under it, read by its presenter.
reset("field")
do
  local TmCase = require("src.ui.game3.tm_case")
  local TvUi = require("src.ui.game3.teachy_tv")
  Stack.push("tm_case", TmCase, { hideBelow = true })
  Stack.push("teachy_pokedude_tm_case", TvUi.tmDemo, { drawUnder = true, hideBelow = false })
  local demoTop = Top.resolve(game)
  eq(demoTop and demoTop.gen3, "tm_case", "the TM case under the Poké Dude demo is the screen")
  check(demoTop and demoTop.layer and demoTop.layer.mod == TmCase, "its layer is the TM case's own")
  local BagMenu = require("src.ui.game3.bag_menu")
  reset("field")
  Stack.push("bag", BagMenu, { hideBelow = true })
  Stack.push("teachy_pokedude_bag", {}, { drawUnder = true, hideBelow = false })
  local bagTop = Top.resolve(game)
  eq(bagTop and bagTop.gen3, "bag", "the bag under the Poké Dude bag demo is the screen")
end

-- A mod's screen pushed through src/ui/game3/mod_ui.lua (layer
-- "modui:<n>", an adapter holding a Gen 1 style state) speaks through the
-- Gen 1 presenters: its own accessibilityText.
reset("field")
do
  local jukebox = { track = 3 }
  function jukebox:accessibilityText() return "Jukebox. Track " .. self.track .. " of 10" end
  Stack.push("modui:1", { isMenu = true, state = jukebox, handleInput = function() end }, { hideBelow = false })
  update()
  eq(last(), "Jukebox. Track 3 of 10", "mod screen in Gen 3 speaks its accessibilityText")
  jukebox.track = 4
  update()
  eq(last(), "Jukebox. Track 4 of 10", "mod screen change")
  local n = count()
  Stack.push("modui:2", { isMenu = true, state = {}, handleInput = function() end }, { hideBelow = false })
  update(2)
  eq(count(), n, "a mod screen no presenter knows stays quiet")
end

-- ------------------------------------------------------------- overlays
local Popup = require("src.ui.game3.map_name_popup")
local Preview = require("src.ui.game3.map_preview_screen")
local Elevator = require("src.ui.game3.elevator_window")
local CoinsBox = require("src.ui.game3.coins_box")
reset("field")
Popup._state, Popup._name = Popup.STATE.SLIDE_IN, "PALLET TOWN"
update(2)
eq(last(), "PALLET TOWN", "map name popup")
eq(lastInterrupt(), false, "overlays queue")
eq(count(), 1, "said once")
Popup._state = Popup.STATE.IDLE
update()
Popup._state = Popup.STATE.SLIDE_IN
update()
eq(count(), 1, "the same name again is not repeated")
Popup._name = "ROUTE 1"
update()
eq(last(), "ROUTE 1", "a new name is said")
Popup._state = Popup.STATE.IDLE
Preview._active, Preview._name = true, "VIRIDIAN FOREST"
update()
eq(last(), "VIRIDIAN FOREST", "dungeon preview name")
Preview._active, Preview._name = false, nil

text("gText_NowOn", "Now on:")
Elevator.visible, Elevator._label, Elevator._owner = true, "1F", nil
update(2)
eq(last(), "Now on: 1F", "elevator window")
check(Elevator.visible == true, "reading never hides the window")
Elevator.visible = false
update()

text("gText_Coins", "{STR_VAR_1} COINS")
CoinsBox.visible, CoinsBox._amount = true, 120
update()
eq(last(), "120 COINS", "coins box")
CoinsBox.visible = false

package.loaded["src.core.game3.pokemon"] = realPokemon
package.loaded["src.core.game3.summary_data"] = realSummary

-- reading never creates the options block (it would skip the game's own
-- migration of old option keys)
local Settings = require("src.access.Settings")
local bare = { generation = 3, options = {} }
eq(Settings.dialogueWhole(bare), false, "no block: page by page")
eq(bare.options.firered, nil, "the block is not created by reading")

eq(Menus.speakable("{A_BUTTON}NEXT"), "A button NEXT", "button tags keep a space after them")
eq(Menus.speakable("{DPAD_ANY}MOVE {DPAD_UP}{DPAD_DOWN}{DPAD_LEFT}{DPAD_RIGHT}"), "the control pad MOVE up down left right",
  "every pad glyph TextIR decodes has words")

T.finish("gen3 menus")
