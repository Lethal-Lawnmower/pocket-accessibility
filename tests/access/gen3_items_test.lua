-- Gen 3 item, Pokémon and storage presenters (FireRed; decision 29): bag
-- with its pockets, action menu, toss, messages, sell flow and deposit
-- title; TM case; berry pouch; party in its list, TM, switch, action,
-- message, YES/NO, forget, level-up and choose-several modes; summary
-- pages, move detail, swap, HM notice, the battle's forget-a-move mode and
-- the egg page; Pokédex contents, list, habitat page and entry pages; PC
-- hub; item PC; box storage with drawer, menus, box picker, wallpaper and
-- the release sequence; shop; the money box overlay; the region map.
--
-- The screens are the real upstream modules (src/ui/game3/*), with the
-- fields their show() and input set.  What needs the imported cartridge
-- (RomText's script bundle, item and Pokémon data) is replaced by small
-- tables, so the rows and prompts are built through the same keys the
-- screens use.  Bag.listPocket, Bag.get and Storage.ensure are trapped:
-- reading must never call them.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

-- ------------------------------------------------------------ cartridge
local TEXT = {
  gText_Yes = "YES", gText_No = "NO", gFameCheckerText_Cancel = "CANCEL", gText_Close = "CLOSE",
  gText_CloseBag = "CLOSE BAG", gText_DepositItem = "DEPOSIT\nITEM",
  ["sItemMenuContextActions[0]"] = "USE", ["sItemMenuContextActions[1]"] = "TOSS",
  ["sItemMenuContextActions[2]"] = "REGISTER", ["sItemMenuContextActions[3]"] = "GIVE",
  ["sItemMenuContextActions[4]"] = "CANCEL", ["sItemMenuContextActions[7]"] = "OPEN",
  ["sItemMenuContextActions[10]"] = "DESELECT",
  gText_Var1IsSelected = "{STR_VAR_1} is\nselected.",
  gText_TossOutHowManyStrVar1s = "Toss out how many\n{STR_VAR_1}(s)?",
  gText_ThrowAwayStrVar2OfThisItemQM = "Throw away {STR_VAR_2} of\nthis item?",
  gText_ThrewAwayStrVar2StrVar1s = "Threw away {STR_VAR_2}\n{STR_VAR_1}(s).",
  gText_DepositHowManyStrVars1 = "Deposit how many\n{STR_VAR_1}(s)?",
  gOtherText_WhereShouldTheStrVar1BePlaced = "Where should the {STR_VAR_1}\nbe placed?",
  gText_PokedollarVar1 = "¥{STR_VAR_1}", gText_TrainerCardMoney = "MONEY",
  gText_HowManyWouldYouLikeToSell = "{STR_VAR_1}? How many would\nyou like to sell?",
  gText_ICanPayThisMuch_WouldThatBeOkay = "I can pay ¥{STR_VAR_3}.\nWould that be okay?",
  gText_TurnedOverItemsWorthYen = "Turned over the {STR_VAR_1}\nand received ¥{STR_VAR_3}.",
  gText_TMCase = "TM CASE", gText_TMCaseWillBePutAway = "The TM CASE will be\nput away.",
  gText_FontSmall = "", sText_ClearTo18 = "", gText_NumberClear01 = "No.", sText_SingleSpace = " ",
  gText_FontNormal = "",
  ["sMenuActions[0]"] = "USE", ["sMenuActions[1]"] = "GIVE", ["sMenuActions[2]"] = "EXIT",
  gText_BerryPouch = "BERRY POUCH", gText_TheBerryPouchWillBePutAway = "The BERRY POUCH will be\nput away.",
  ["sContextMenuActions[0]"] = "USE", ["sContextMenuActions[1]"] = "TOSS",
  ["sContextMenuActions[2]"] = "GIVE", ["sContextMenuActions[3]"] = "EXIT",
  gText_ChoosePokemon = "Choose a POKéMON.", gText_MoveToWhere = "Move to where?",
  gText_TeachWhichPokemon = "Teach which POKéMON?", gText_UseOnWhichPokemon = "Use on which POKéMON?",
  gText_GiveToWhichPokemon = "Give to which POKéMON?", gText_DoWhatWithPokemon = "Do what with this {PKMN}?",
  gText_DoWhatWithItem = "Do what with an item?", gText_Lv = "{LV}", gMenuText_Confirm = "CONFIRM",
  ["sCursorOptions[0]"] = "SUMMARY", ["sCursorOptions[1]"] = "SWITCH", ["sCursorOptions[2]"] = "CANCEL",
  ["sCursorOptions[3]"] = "ITEM", ["sCursorOptions[4]"] = "GIVE", ["sCursorOptions[5]"] = "TAKE",
  ["sCursorOptions[19]"] = "CUT",
  ["sDescriptionStringTable[5]"] = "ABLE", ["sDescriptionStringTable[6]"] = "NOT ABLE",
  ["sDescriptionStringTable[7]"] = "ABLE!", ["sDescriptionStringTable[8]"] = "NOT ABLE!",
  ["sDescriptionStringTable[9]"] = "LEARNED",
  ["sLevelUpWindowStatNames[0]"] = "MAX. HP", ["sLevelUpWindowStatNames[1]"] = "ATTACK",
  ["sLevelUpWindowStatNames[2]"] = "DEFENSE", ["sLevelUpWindowStatNames[3]"] = "SP. ATK",
  ["sLevelUpWindowStatNames[4]"] = "SP. DEF", ["sLevelUpWindowStatNames[5]"] = "SPEED",
  gText_PokeSum_PageName_PokemonInfo = "POKéMON INFO", gText_PokeSum_PageName_PokemonSkills = "POKéMON SKILLS",
  gText_PokeSum_PageName_KnownMoves = "KNOWN MOVES", gText_PokeSum_Item_None = "NONE",
  gText_PokeSum_ExpPoints = "EXP. POINTS", gText_PokeSum_NextLv = "NEXT LV.", gText_PokeSum_OneHyphen = "-",
  gText_PokeSum_HmMovesCantBeForgotten = "HM moves can't be\nforgotten now.", gText_EggNickname = "EGG",
  gText_PokeSum_DexNoUnknown = "???",
  ["gTypeNames[0]"] = "NORMAL", ["gTypeNames[2]"] = "FLYING", ["gTypeNames[3]"] = "POISON",
  ["gTypeNames[10]"] = "FIRE", ["gTypeNames[12]"] = "GRASS", ["gTypeNames[1]"] = "FIGHTING",
  gText_PokedexTableOfContents = "TABLE OF CONTENTS", gText_Seen = "SEEN", gText_Owned = "OWNED",
  gText_Kanto = "KANTO", gText_National = "NATIONAL", gText_PokemonListNoColor = "POKéMON LIST",
  gText_5Dashes = "-----", gText_Area = "AREA", gText_AreaUnknown = "AREA UNKNOWN",
  ["sListMenuItems_KantoDexModeSelect[0]"] = "POKéMON LIST",
  ["sListMenuItems_KantoDexModeSelect[1]"] = "NUMERICAL MODE",
  ["sListMenuItems_KantoDexModeSelect[2]"] = "POKéMON HABITATS",
  ["sListMenuItems_KantoDexModeSelect[3]"] = "GRASSLAND", ["sListMenuItems_KantoDexModeSelect[4]"] = "FOREST",
  ["sDexCategoryNamePtrs[0]"] = "GRASSLAND", ["sDexCategoryNamePtrs[1]"] = "FOREST",
  gText_SomeoneSPc = "SOMEONE'S PC", Text_AccessWhichPC = "Which PC should be accessed?",
  gText_WithdrawPokemon = "WITHDRAW POKéMON", gText_WithdrawMonDescription = "Move POKéMON stored in\nBOXES to your party.",
  gText_DepositPokemon = "DEPOSIT POKéMON", gText_DepositMonDescription = "Store POKéMON in your\nparty in BOXES.",
  gText_MovePokemon = "MOVE POKéMON", gText_MoveMonDescription = "Organize the POKéMON in\nBOXES and your party.",
  gText_MoveItems = "MOVE ITEMS", gText_MoveItemsDescription = "Move items held by\nPOKéMON.",
  gText_SeeYa = "SEE YA!", gText_SeeYaDescription = "Return to the previous\nmenu.",
  gText_JustOnePkmn = "That's your last\nPOKéMON!",
  gText_WithdrawItem = "WITHDRAW\nITEM", gText_ReturnToPC = "Go back to the\nprevious menu.",
  gText_Withdraw = "WITHDRAW", gOtherText_Give = "GIVE", gText_WithdrawHowMany = "Withdraw how many\n{STR_VAR_1}(s)?",
  ["sMenuTexts[0]"] = "CANCEL", ["sMenuTexts[2]"] = "WITHDRAW", ["sMenuTexts[3]"] = "MOVE",
  ["sMenuTexts[6]"] = "SUMMARY", ["sMenuTexts[7]"] = "RELEASE", ["sMenuTexts[9]"] = "SWITCH BOX",
  ["sMenuTexts[10]"] = "WALLPAPER", ["sMenuTexts[22]"] = "FOREST", ["sMenuTexts[23]"] = "CITY",
  gText_JumpToWhichBox = "Jump to which BOX?", gText_DepositInWhichBox = "Deposit in which BOX?",
  gText_PickTheWallpaper = "Pick the wallpaper.", gText_ReleaseThisPokemon = "Release this POKéMON?",
  gText_PkmnWasReleased = "{DYN0} was released.", gText_ByeByePkmn = "Bye-bye, {DYN0}!",
  ["sShopMenuActions_BuySellQuit[0]"] = "BUY", ["sShopMenuActions_BuySellQuit[1]"] = "SELL",
  ["sShopMenuActions_BuySellQuit[2]"] = "SEE YA!", gText_QuitShopping = "Quit shopping.",
  gText_InBagVar1 = "IN BAG: {STR_VAR_1}",
}

local Rom = require("src.core.game3.rom_text")
local function expand(key, ctx)
  local text = TEXT[key]
  if text == nil then error("no text " .. tostring(key)) end
  ctx = ctx or {}
  local vars = ctx.stringVars or {}
  text = text:gsub("{STR_VAR_(%d)}", function(n) return tostring(vars[tonumber(n)] or "") end)
  text = text:gsub("{DYN0}", function() return tostring(ctx.dynamic and ctx.dynamic[0] or "") end)
  return text
end
Rom.plain = expand
Rom.box = expand
Rom.has = function(key) return TEXT[key] ~= nil end
Rom.at = function(name, i) return expand(Rom.key(name, i)) end
Rom.list = function(name)
  local out = {}
  for i = 0, 5 do out[i + 1] = TEXT[Rom.key(name, i)] end
  return out
end
Rom.ir = function(key) return { { t = "text", s = expand(key) } } end

local Profile = require("src.core.game3.profile")
Profile.forSession = function() return { id = "firered", family = "frlg", ui = {} } end
Profile.family = function() return "frlg" end
Profile.sessionVersion = function() return "firered" end

-- Item data: 13 POTION, 14 ANTIDOTE, 259 TOWN MAP (registrable key item),
-- 364 BERRY POUCH, 289 TM01, 339 HM01, 133 CHERI BERRY, 4 POKé BALL.
local ITEMS = {
  [13] = { name = "POTION", pocket = "ITEMS", price = 300, description = "Restores the HP of a\nPOKéMON by 20 points." },
  [14] = { name = "ANTIDOTE", pocket = "ITEMS", price = 100, description = "Heals a poisoned\nPOKéMON." },
  [259] = { name = "TOWN MAP", pocket = "KEY_ITEMS", importance = 1, registrability = 1,
    description = "Can be viewed anytime." },
  [4] = { name = "POKé BALL", pocket = "POKE_BALLS", price = 200, description = "A tool for catching." },
  [289] = { name = "TM01", pocket = "TM_CASE", description = "TM item" },
  [339] = { name = "HM01", pocket = "TM_CASE", description = "HM item" },
  [133] = { name = "CHERI BERRY", pocket = "BERRY_POUCH", price = 20, description = "Heals paralysis." },
  [1] = { name = "MASTER BALL", pocket = "POKE_BALLS" },
}
local ItemsData = require("src.core.game3.items_data")
ItemsData.info = function(id) return ITEMS[tonumber(id)] end
ItemsData.displayName = function(id) return ITEMS[tonumber(id)] and ITEMS[tonumber(id)].name or tostring(id) end
ItemsData.description = function(id) return ITEMS[tonumber(id)] and ITEMS[tonumber(id)].description or "" end
ItemsData.toNumericId = function(id) return tonumber(id) end
ItemsData.pocketOf = function(id) return ITEMS[tonumber(id)] and ITEMS[tonumber(id)].pocket or "ITEMS" end
ItemsData.isHm = function(id) return tonumber(id) == 339 end
ItemsData.isTm = function(id) return tonumber(id) == 289 or tonumber(id) == 339 end
ItemsData.tmNumber = function(id) return tonumber(id) == 339 and 1 or 1 end
ItemsData.berryNumber = function(id) return tonumber(id) == 133 and 1 or nil end
ItemsData.fieldUseKind = function() return "none" end
for k in pairs(ItemsData.BAG_POCKET_ORDER) do ItemsData.BAG_POCKET_ORDER[k] = nil end
ItemsData.BAG_POCKET_ORDER[1], ItemsData.BAG_POCKET_ORDER[2], ItemsData.BAG_POCKET_ORDER[3] = "ITEMS", "KEY_ITEMS", "POKE_BALLS"
ItemsData.POCKET_LABEL = { ITEMS = "ITEMS", KEY_ITEMS = "KEY ITEMS", POKE_BALLS = "POKé BALLS" }

-- Pokémon data: 1 BULBASAUR, 16 PIDGEY, 4 CHARMANDER; moves 1 POUND,
-- 15 CUT, 33 TACKLE, 45 GROWL, 52 EMBER, 5 MEGA PUNCH (TM01).
local SPECIES = { [1] = "BULBASAUR", [16] = "PIDGEY", [4] = "CHARMANDER", [29] = "NIDORAN♀" }
local MOVES = {
  [1] = { name = "POUND", type = 0, power = 40, accuracy = 100, pp = 35 },
  [15] = { name = "CUT", type = 0, power = 50, accuracy = 95, pp = 30 },
  [33] = { name = "TACKLE", type = 0, power = 35, accuracy = 95, pp = 35 },
  [45] = { name = "GROWL", type = 0, power = 0, accuracy = 100, pp = 40 },
  [52] = { name = "EMBER", type = 10, power = 40, accuracy = 100, pp = 25 },
  [5] = { name = "MEGA PUNCH", type = 1, power = 80, accuracy = 85, pp = 20 },
}
local P3 = require("src.core.game3.pokemon")
P3.name = function(sp) return SPECIES[tonumber(sp)] end
P3.speciesOf = function(mon) return tonumber(mon.species) end
P3.displayName = function(mon)
  if mon.isEgg then return "EGG" end
  return (mon.nickname and mon.nickname ~= "") and mon.nickname or SPECIES[tonumber(mon.species)]
end
P3.isEgg = function(mon) return mon and mon.isEgg == true end
P3.moveName = function(id) return MOVES[tonumber(id)] and MOVES[tonumber(id)].name end
P3.battleMove = function(id) return MOVES[tonumber(id)] end
P3.types = function(sp) if tonumber(sp) == 4 then return { 10, 10 } end return { 12, 3 } end
P3.gender = function() return nil end
P3.moveFromTmItem = function(id) if tonumber(id) == 289 then return 5 end if tonumber(id) == 339 then return 15 end end
P3.canLearnTmItem = function(species, item) return tonumber(species) ~= 16 end
P3.knowsMove = function(mon, move) for _, m in ipairs(mon.moves or {}) do if (type(m) == "table" and m.id or m) == move then return true end end return false end
P3.national = function(sp) return tonumber(sp) end
P3.abilityName = function(id) return id == 65 and "OVERGROW" or nil end
P3.abilityId = function() return 65 end
P3.isHmMove = function(id) return tonumber(id) == 15 end
require("src.core.game3.battle.types")

local SD = require("src.core.game3.summary_data")
SD.formatTrainerMemo = function(mon) return { "BOLD nature.", "Met at Lv. 5." } end
SD.expProgress = function(mon) return { totalExp = 135, expNeeded = 44 } end
SD.moveDescription = function(id) return MOVES[tonumber(id)] and ("Description of " .. MOVES[tonumber(id)].name) or "---" end
SD.abilityDescription = function() return "Ups GRASS moves in a pinch." end
SD.eggHatchText = function() return "It appears to move\noccasionally." end
package.loaded["src.core.game3.mail"] = { isMailItem = function(i) return i >= 121 and i <= 132 end }

-- Traps: reading must never call these.
local Bag = require("src.core.game3.bag")
local Storage = require("src.core.game3.storage")
local trapped = 0
Bag.listPocket = function() trapped = trapped + 1 return {} end
Bag.get = function() trapped = trapped + 1 return 0 end
Storage.ensure = function() trapped = trapped + 1 return nil end

-- ------------------------------------------------------------- harness
local Speech = require("src.access.Speech")
local SR = require("src.access.screens.ScreenReader")
local Top = require("src.access.screens.gen3.Top")
local Items = require("src.access.screens.gen3.Items")

local spoken = {}
local fake = { name = "Fake" }
function fake:say(text, interrupt) spoken[#spoken + 1] = { text = text, interrupt = interrupt } return true end
function fake:stop() return true end
function fake:close() end
Speech.shutdown()
Speech.start({ backend = fake })

local function reset() for i = #spoken, 1, -1 do spoken[i] = nil end SR._resetForTests() end
local function last() return spoken[#spoken] and spoken[#spoken].text end
local function count() return #spoken end

local function screen(id, mod)
  local layer = { id = id, mod = mod }
  return Top._proxy(layer, id, { layer = layer, mod = mod, game = {} })
end
local function poll(p) SR.update(p) end

-- ------------------------------------------------------------------ bag
local BagMenu = require("src.ui.game3.bag_menu")
local session = { party = {}, money = 3000, registeredItem = nil, name = "RED" }
local bag = { pockets = {
  ITEMS = { { id = 13, qty = 2 }, { id = 14, qty = 1 }, { id = 99, qty = 0 } },
  KEY_ITEMS = { { id = 259, qty = 1 } },
  POKE_BALLS = { { id = 4, qty = 5 } },
  TM_CASE = { { id = 289, qty = 1 }, { id = 339, qty = 1 } },
  BERRY_POUCH = { { id = 133, qty = 3 } },
} }
session.bag = bag
local function openBag(fields)
  BagMenu.open, BagMenu._exit, BagMenu._open, BagMenu._switch = true, nil, nil, nil
  BagMenu._bag, BagMenu._session, BagMenu._battle, BagMenu._location = bag, session, false, nil
  BagMenu.pocketIdx, BagMenu.cursor, BagMenu.scroll, BagMenu.mode = 1, 1, 0, "list"
  BagMenu.actionCursor, BagMenu.tossQty, BagMenu.yesNoCursor = 1, 1, 1
  BagMenu.messageText, BagMenu._msgPage, BagMenu._sell = nil, 1, nil
  for k, v in pairs(fields or {}) do BagMenu[k] = v end
  return screen("bag", BagMenu)
end

reset()
local bagScreen = openBag()
poll(bagScreen)
eq(last(), "ITEMS pocket. POTION, quantity 2, 1 of 3. Restores the HP of a POKéMON by 20 points.", "bag entry: pocket, row, position, description")
BagMenu.cursor = 2
poll(bagScreen)
eq(last(), "ANTIDOTE, quantity 1. Heals a poisoned POKéMON.", "bag move: row and description")
BagMenu.cursor = 3
poll(bagScreen)
eq(last(), "CANCEL. CLOSE BAG", "bag cancel row: CANCEL and the close-bag text")
local n = count()
poll(bagScreen)
eq(count(), n, "unchanged bag frame is silent")
BagMenu.pocketIdx, BagMenu.cursor = 2, 1
poll(bagScreen)
eq(last(), "KEY ITEMS pocket. TOWN MAP, 1 of 2. Can be viewed anytime.", "pocket change: title, row (no quantity in KEY ITEMS), position")
session.registeredItem = 259
BagMenu.mode = "action"
BagMenu.ACTIONS = { "USE", "SET", "CANCEL" }
poll(bagScreen)
eq(last(), "TOWN MAP is selected. USE, 1 of 3", "action menu: selected prompt, label, position")
BagMenu.actionCursor = 2
poll(bagScreen)
eq(last(), "DESELECT", "action label read through the bag's own action_label (registered: DESELECT)")
BagMenu.mode = "list"
poll(bagScreen)
eq(last(), "TOWN MAP, registered, 1 of 2. Can be viewed anytime.", "back on the list: row with SELECT icon, position")
session.registeredItem = nil
BagMenu.pocketIdx, BagMenu.cursor, BagMenu.mode = 1, 1, "toss"
poll(bagScreen)
eq(last(), "Toss out how many POTION(s)? Quantity 1, up to 2", "toss: prompt and quantity range")
BagMenu.tossQty = 2
poll(bagScreen)
eq(last(), "2", "toss: new quantity only")
BagMenu.mode, BagMenu.yesNoCursor = "toss_confirm", 1
poll(bagScreen)
eq(last(), "Throw away 2 of this item? YES", "toss confirm: question and YES")
BagMenu.yesNoCursor = 2
poll(bagScreen)
eq(last(), "NO", "toss confirm: NO")
BagMenu.mode = "toss_done"
poll(bagScreen)
eq(last(), "Threw away 2 POTION(s).", "toss done message")
BagMenu.mode, BagMenu.messageText, BagMenu._msgPage = "message", "There is no POKéMON.", 1
poll(bagScreen)
eq(last(), "There is no POKéMON.", "bag message")
BagMenu.mode, BagMenu.moveFrom, BagMenu.cursor = "move", 1, 2
poll(bagScreen)
eq(last(), "Where should the POTION be placed? ANTIDOTE, quantity 1, 2 of 3", "move: where-placed prompt and the row")
BagMenu.cursor = 3
poll(bagScreen)
eq(last(), "CANCEL", "move: the row under the cursor")

-- sell through the real SellFlow
local SellFlow = require("src.ui.game3.sell_flow")
local flow = setmetatable({ itemId = 13, name = "POTION", session = session, bag = bag, qty = 1, owned = 2,
  unit = 150, yesNo = 1, state = "qty", text = expand("gText_HowManyWouldYouLikeToSell", { stringVars = { "POTION" } }) }, SellFlow)
BagMenu.mode, BagMenu._sell, BagMenu.cursor = "sell", flow, 1
poll(bagScreen)
eq(last(), "POTION? How many would you like to sell? Quantity 1, up to 2, ¥150. MONEY ¥3000", "sell: question, quantity, offer, money")
flow.qty = 2
poll(bagScreen)
eq(last(), "2, ¥300", "sell: quantity and offer")
flow.state, flow.text = "confirm", expand("gText_ICanPayThisMuch_WouldThatBeOkay", { stringVars = { [3] = "300" } })
poll(bagScreen)
eq(last(), "I can pay ¥300. Would that be okay? YES", "sell confirm: offer and YES")
flow.yesNo = 2
poll(bagScreen)
eq(last(), "NO", "sell confirm: NO")
flow.state, flow.text, session.money = "done", expand("gText_TurnedOverItemsWorthYen", { stringVars = { "POTION", [3] = "300" } }), 3300
poll(bagScreen)
eq(last(), "Turned over the POTION and received ¥300. MONEY ¥3300", "sell done: message and new money")

reset()
bagScreen = openBag({ _location = "itempc" })
poll(bagScreen)
eq(last(), "DEPOSIT ITEM. POTION, quantity 2, 1 of 3. Restores the HP of a POKéMON by 20 points.", "item PC deposit: DEPOSIT ITEM title")
BagMenu.mode, BagMenu.tossQty = "deposit", 1
poll(bagScreen)
eq(last(), "Deposit how many POTION(s)? Quantity 1, up to 2", "deposit quantity")
BagMenu._exit = { k = 1 }
n = count()
poll(bagScreen)
eq(count(), n, "a closing bag stays quiet")
BagMenu._exit = nil

-- ------------------------------------------------------------- TM case
local TmCase = require("src.ui.game3.tm_case")
reset()
TmCase.open, TmCase._bag, TmCase._session, TmCase.cursor, TmCase.mode = true, bag, session, 1, "list"
local tmScreen = screen("tm_case", TmCase)
poll(tmScreen)
eq(last(), "TM CASE. No.01 MEGA PUNCH, quantity 1, 1 of 3. type FIGHTING, power 80, accuracy 85, PP 20. Description of MEGA PUNCH",
  "TM case entry: number and move, quantity, position, move facts, description")
TmCase.cursor = 2
poll(tmScreen)
eq(last(), "HM No.1 CUT. type NORMAL, power 50, accuracy 95, PP 30. Description of CUT", "HM row: icon in words, no quantity")
TmCase.cursor = 3
poll(tmScreen)
eq(last(), "CLOSE. The TM CASE will be put away.", "TM case close row")
TmCase.cursor, TmCase.mode, TmCase.actionCursor = 1, "action", 1
poll(tmScreen)
eq(last(), "No.01 MEGA PUNCH is selected. USE, 1 of 3", "TM case actions from its own table")
TmCase.actionCursor = 3
poll(tmScreen)
eq(last(), "EXIT", "TM case action change")

-- ---------------------------------------------------------- berry pouch
local BerryPouch = require("src.ui.game3.berry_pouch")
reset()
BerryPouch.open, BerryPouch._bag, BerryPouch.cursor, BerryPouch.mode = true, bag, 1, "list"
BerryPouch._fromBerryCrush = false
local berryScreen = screen("berry_pouch", BerryPouch)
poll(berryScreen)
eq(last(), "BERRY POUCH. number 01, CHERI BERRY, quantity 3, 1 of 2. Heals paralysis.", "berry pouch entry")
BerryPouch.mode, BerryPouch.actionCursor = "action", 3
poll(berryScreen)
eq(last(), "CHERI BERRY is selected. TOSS, 3 of 4", "berry pouch actions through ACTION_TEXT")
BerryPouch.mode, BerryPouch.tossQty = "toss_select", 1
poll(berryScreen)
eq(last(), "Toss out how many CHERI BERRY(s)? Quantity 1, up to 3", "berry toss quantity")
BerryPouch.cursor = 2
BerryPouch.mode = "list"
poll(berryScreen)
eq(last(), "CLOSE, 2 of 2. The BERRY POUCH will be put away.", "berry close row after a sub-mode: row with position")

-- Berry Crush's berry choice replaces the pouch's layer with its own under
-- the same id; the pouch module still holds the list (no CLOSE row).
do
  reset()
  local CrushPouch = require("src.ui.game3.minigames.berry_crush.pouch")
  BerryPouch.open, BerryPouch.cursor, BerryPouch.mode = true, 1, "list"
  BerryPouch._fromBerryCrush = true
  local crushScreen = screen("berry_pouch", CrushPouch)
  poll(crushScreen)
  eq(last(), "BERRY POUCH. number 01, CHERI BERRY, quantity 3, 1 of 1. Heals paralysis.",
    "Berry Crush berry choice read from the pouch module")
  BerryPouch._fromBerryCrush = false
  check(Items.berryPouch.matches(screen("berry_pouch", {})) == false, "a mod's berry_pouch layer stays quiet")
end

-- ---------------------------------------------------------------- party
local PartyMenu = require("src.ui.game3.party_menu")
local bulba = { species = 1, nickname = "BULBA", level = 7, hp = 20, maxHp = 22, gender = "M", item = 13,
  moves = { { id = 33, pp = 30 }, { id = 45 } }, maxPp = {}, personality = 0 }
local pidgey = { species = 16, level = 4, hp = 10, maxHp = 16, gender = "F", status = "PSN", moves = { { id = 33 } },
  otId = 12345, personality = 987654321 }
local egg = { species = 4, isEgg = true, level = 5, hp = 10, maxHp = 10 }
local nido = { species = 29, level = 3, hp = 0, maxHp = 12, gender = "F" }
local function openParty(party, mode, fields)
  PartyMenu.open, PartyMenu._party, PartyMenu._session, PartyMenu.mode = true, party, session, mode or "list"
  PartyMenu.cursor, PartyMenu._item, PartyMenu._battle, PartyMenu._hpAnim = 1, nil, false, nil
  PartyMenu._chooseOrder, PartyMenu._tutor, PartyMenu._minigameEligible, PartyMenu._pokedude = nil, nil, nil, nil
  PartyMenu.switchFrom, PartyMenu._messageText = nil, nil
  for k, v in pairs(fields or {}) do PartyMenu[k] = v end
  return screen("party", PartyMenu)
end
reset()
local partyScreen = openParty({ bulba, pidgey, egg, nido })
poll(partyScreen)
eq(last(), "Choose a POKéMON. BULBA, BULBASAUR, level 7, male, HP 20 of 22, holding an item, 1 of 5", "party entry: prompt, row, position")
PartyMenu.cursor = 2
poll(partyScreen)
eq(last(), "PIDGEY, female, HP 10 of 16, poisoned", "status icon replaces the level")
PartyMenu.cursor = 3
poll(partyScreen)
eq(last(), "EGG", "an egg row is its name alone")
PartyMenu.cursor = 4
poll(partyScreen)
eq(last(), "NIDORAN♀, HP 0 of 12, fainted", "Nidoran shows no gender mark; fainted")
PartyMenu.cursor = 7
poll(partyScreen)
eq(last(), "CANCEL", "CANCEL button")
PartyMenu.cursor, PartyMenu.mode, PartyMenu.actionCursor = 1, "action", 1
PartyMenu.ACTIONS = { "SUMMARY", "SWITCH", "ITEM", "CANCEL" }
poll(partyScreen)
eq(last(), "Do what with this POKéMON? SUMMARY, 1 of 4", "action menu prompt and label")
PartyMenu.actionCursor = 2
poll(partyScreen)
eq(last(), "SWITCH", "action label")
PartyMenu.mode, PartyMenu.switchFrom = "switch", 1
poll(partyScreen)
eq(last(), "Move to where? BULBA, BULBASAUR, level 7, male, HP 20 of 22, holding an item, 1 of 5", "switch: prompt and row")
PartyMenu.cursor = 2
poll(partyScreen)
eq(last(), "PIDGEY, female, HP 10 of 16, poisoned", "switch: destination row")
PartyMenu._party[1], PartyMenu._party[2] = pidgey, bulba
PartyMenu.mode, PartyMenu.switchFrom = "list", nil
poll(partyScreen)
eq(last(), "BULBA, BULBASAUR, level 7, male, HP 20 of 22, holding an item, 2 of 5", "after the switch: the Pokémon now under the cursor, position")
PartyMenu.mode, PartyMenu.itemActionCursor = "item_action", 1
PartyMenu.ITEM_ACTIONS = { "GIVE", "TAKE", "CANCEL" }
poll(partyScreen)
eq(last(), "Do what with an item? GIVE, 1 of 3", "item sub-menu")
PartyMenu._hpAnim = { slot = 2, current = 10, target = 20 }
PartyMenu.mode = "message"
n = count()
poll(partyScreen)
eq(count(), n, "silent while the HP bar runs")
PartyMenu._hpAnim, PartyMenu._messageText = nil, "BULBA's HP was restored\nby 2 point(s)."
poll(partyScreen)
eq(last(), "BULBA's HP was restored by 2 point(s).", "message once the bar stops")
PartyMenu.mode, PartyMenu._yesNoPrompt, PartyMenu._yesNoCursor = "yesno", "Cancel the battle?", 1
poll(partyScreen)
eq(last(), "Cancel the battle? YES", "party YES/NO")
PartyMenu._yesNoCursor = 2
poll(partyScreen)
eq(last(), "NO", "party YES/NO change")
PartyMenu.mode, PartyMenu._forgetPrompt, PartyMenu._forgetMoves, PartyMenu._forgetCursor =
  "forget", "Restore which move?", { "TACKLE", "GROWL" }, 1
poll(partyScreen)
eq(last(), "Restore which move? TACKLE, 1 of 2", "move picker")
PartyMenu._forgetCursor = 2
poll(partyScreen)
eq(last(), "GROWL", "move picker change")
PartyMenu.mode, PartyMenu._statGrowthPage, PartyMenu._messageText = "stat_growth", 1, "BULBA grew to\nLv. 8!"
PartyMenu._statGrowthOld = { maxHp = 22, atk = 11, def = 11, spa = 13, spd = 13, spe = 10 }
PartyMenu._statGrowthNew = { maxHp = 24, atk = 12, def = 12, spa = 14, spd = 14, spe = 11 }
poll(partyScreen)
eq(last(), "BULBA grew to Lv. 8! MAX. HP plus 2, ATTACK plus 1, DEFENSE plus 1, SP. ATK plus 1, SP. DEF plus 1, SPEED plus 1",
  "level-up window page 1: the gains")
PartyMenu._statGrowthPage = 2
poll(partyScreen)
eq(last(), "MAX. HP 24, ATTACK 12, DEFENSE 12, SP. ATK 14, SP. DEF 14, SPEED 11", "level-up page 2: the values")

-- Softboiled / Milk Drink: from the action menu to the target choice, a new
-- question (the screen's prompt), not a return to the list
reset()
partyScreen = openParty({ bulba, pidgey }, "action", { actionCursor = 1 })
PartyMenu.ACTIONS = { "SUMMARY", "SOFTBOILED", "CANCEL" }
poll(partyScreen)
PartyMenu.mode = "softboiled"
poll(partyScreen)
eq(last(), "Choose a POKéMON. BULBA, BULBASAUR, level 7, male, HP 20 of 22, holding an item, 1 of 3",
  "Softboiled target: prompt, donor row, position")
PartyMenu.cursor = 2
poll(partyScreen)
eq(last(), "PIDGEY, female, HP 10 of 16, poisoned", "Softboiled target row")

reset()
partyScreen = openParty({ bulba, pidgey }, "use", { _item = 289 })
poll(partyScreen)
eq(last(), "Teach which POKéMON? BULBA, BULBASAUR, level 7, male, ABLE!, holding an item, 1 of 3", "TM: teach prompt and the screen's own ABLE")
PartyMenu.cursor = 2
poll(partyScreen)
eq(last(), "PIDGEY, female, NOT ABLE!, poisoned", "TM: NOT ABLE")
reset()
partyScreen = openParty({ bulba, pidgey }, "choose_multi", { _chooseOrder = {} })
PartyMenu.cursor = 7
poll(partyScreen)
eq(last(), "Choose a POKéMON. CONFIRM, 3 of 4", "choose several: CONFIRM after the slots")
PartyMenu.cursor = 8
poll(partyScreen)
eq(last(), "CANCEL", "choose several: CANCEL last")

-- -------------------------------------------------------------- summary
local SummaryMenu = require("src.ui.game3.summary_menu")
local function openSummary(party, fields)
  SummaryMenu.open, SummaryMenu._nativeDelegate, SummaryMenu._party, SummaryMenu._cursor = true, nil, party, 1
  SummaryMenu._page, SummaryMenu._moveCursor, SummaryMenu._swapSlot, SummaryMenu._mode = 0, 1, nil, nil
  SummaryMenu._moveToLearn, SummaryMenu._forgetMove, SummaryMenu._hmNotice = nil, false, false
  SummaryMenu._playerState = session
  for k, v in pairs(fields or {}) do SummaryMenu[k] = v end
  return screen("summary", SummaryMenu)
end
reset()
bulba.otName, bulba.otId = "RED", 12345
local summaryScreen = openSummary({ bulba, pidgey, egg })
poll(summaryScreen)
eq(last(), "BULBA, level 7, male. POKéMON INFO, page 1 of 3. number 001, BULBASAUR, type GRASS and POISON, OT RED, ID 12345, item POTION. BOLD nature. Met at Lv. 5.",
  "summary entry: header, page, info")
SummaryMenu._page = 1
bulba.attack, bulba.defense, bulba.spAtk, bulba.spDef, bulba.speed, bulba.ability = 12, 11, 14, 14, 10, 65
poll(summaryScreen)
eq(last(), "POKéMON SKILLS, page 2 of 3. HP 20 of 22, attack 12, defense 11, special attack 14, special defense 14, speed 10. EXP. POINTS 135, NEXT LV. 44. ability OVERGROW, Ups GRASS moves in a pinch.",
  "skills page")
SummaryMenu._page = 2
poll(summaryScreen)
eq(last(), "KNOWN MOVES, page 3 of 3. moves: TACKLE, NORMAL, PP 30 of 35; GROWL, NORMAL, PP 40 of 40",
  "moves page: a missing PP count is full")
SummaryMenu._page = 3
poll(summaryScreen)
eq(last(), "TACKLE, NORMAL, PP 30 of 35, 1 of 5. power 35, accuracy 95. Description of TACKLE", "move detail with position")
SummaryMenu._moveCursor = 5
poll(summaryScreen)
eq(last(), "CANCEL", "move detail fifth row: CANCEL")
SummaryMenu._moveCursor, SummaryMenu._swapSlot = 1, 1
poll(summaryScreen)
eq(last(), "moving TACKLE, NORMAL, PP 30 of 35", "swap started")
SummaryMenu._cursor = 2
poll(summaryScreen)
check(last():find("^PIDGEY, level 4, female%. KNOWN MOVES") ~= nil, "Pokémon change: header again (" .. tostring(last()) .. ")")
reset()
summaryScreen = openSummary({ bulba }, { _mode = "select_move", _page = 3, _moveToLearn = 15 })
poll(summaryScreen)
eq(last(), "BULBA, level 7, male. KNOWN MOVES. TACKLE, NORMAL, PP 30 of 35, 1 of 5. power 35, accuracy 95. Description of TACKLE",
  "forget-a-move mode entry")
SummaryMenu._moveCursor = 5
poll(summaryScreen)
eq(last(), "new move, CUT, NORMAL, PP 30 of 30, 5 of 5. power 50, accuracy 95. Description of CUT",
  "the move to learn as the fifth row, marked new, with its position")
SummaryMenu._moveCursor = 1
poll(summaryScreen)
eq(last(), "TACKLE, NORMAL, PP 30 of 35, 1 of 5. power 35, accuracy 95. Description of TACKLE",
  "a known move keeps its position while a move is being learned")
SummaryMenu._hmNotice = true
poll(summaryScreen)
eq(last(), "HM moves can't be forgotten now.", "HM notice")
reset()
summaryScreen = openSummary({ egg }, { _page = 4 })
poll(summaryScreen)
eq(last(), "EGG. POKéMON INFO. EGG. It appears to move occasionally. BOLD nature. Met at Lv. 5.", "egg page")

-- -------------------------------------------------------------- Pokédex
local Pokedex = require("src.ui.game3.pokedex")
local DexMod = require("src.core.game3.dex")
local PData = require("src.core.game3.pokedex_data")
local seenSet, caughtSet = { [1] = true, [4] = true, [16] = true }, { [1] = true }
DexMod.isSeen = function(_, sp) return seenSet[tonumber(sp)] == true end
DexMod.isCaught = function(_, sp) return caughtSet[tonumber(sp)] == true end
DexMod.countSeen = function() return 3 end
DexMod.countCaught = function() return 1 end
PData.isNationalUnlocked = function() return false end
PData.getOrderList = function() return { 1, 2, 3, 4 } end
PData.getUnlockedCategoryPages = function() return { { mons = { 1, 16 } }, { mons = { 4 } } } end
PData.getWildAreasForSpecies = function(sp) if sp == 16 then return { "DEX_AREA_ROUTE_1", "DEX_AREA_ROUTE_2" } end return {} end
PData.getAreaMapKey = function() return "kanto" end
PData.getAreaMarker = function() return { x = 1, y = 1 } end
PData._areaData = { mapsecToArea = { MAPSEC_ROUTE_1 = "DEX_AREA_ROUTE_1", MAPSEC_ROUTE_2 = "DEX_AREA_ROUTE_2" } }
package.loaded["src.import.gba.region_map_extract"] = { SECTION_NAMES = { MAPSEC_ROUTE_1 = "ROUTE 1", MAPSEC_ROUTE_2 = "ROUTE 2" } }
package.loaded["src.ui.game3.pokedex_chrome"] = { getEntry = function(sp)
  return { categoryName = "SEED POKéMON", heightFormatted = " 2'04\"", weightFormatted = "  15.2 lbs.",
    description = "A strange seed was\nplanted on its back." } end }
package.loaded["src.core.game3.pokedex_units"] = nil
reset()
Pokedex.open, Pokedex._dex, Pokedex._session, Pokedex.screen = true, {}, session, "mode_select"
Pokedex.MODES = {
  { isHeader = true, label = "POKéMON LIST" }, { id = "numerical_kanto", type = "order", label = "NUMERICAL MODE", unlocked = true },
  { isHeader = true, label = "POKéMON HABITATS" }, { id = "grassland", type = "habitat", label = "GRASSLAND", unlocked = true },
  { id = "forest", type = "habitat", label = "FOREST", unlocked = false },
}
Pokedex.modeCursor, Pokedex.currentOrder, Pokedex.listCursor = 2, "numerical_kanto", 1
local dexScreen = screen("pokedex", Pokedex)
poll(dexScreen)
eq(last(), "TABLE OF CONTENTS. SEEN 3, OWNED 1. NUMERICAL MODE, 1 of 3", "Pokédex contents: counts and row")
Pokedex.modeCursor = 4
poll(dexScreen)
eq(last(), "POKéMON HABITATS. GRASSLAND, 2 of 3", "a new section says its header")
Pokedex.modeCursor = 5
poll(dexScreen)
eq(last(), "FOREST, unavailable, 3 of 3", "a greyed habitat")
Pokedex.screen = "ordered_list"
poll(dexScreen)
eq(last(), "POKéMON LIST. number 001, BULBASAUR, caught, type GRASS and POISON, 1 of 4", "list row: caught with types")
Pokedex.listCursor = 2
poll(dexScreen)
eq(last(), "number 002, -----", "unseen row as drawn")
Pokedex.listCursor = 4
poll(dexScreen)
eq(last(), "number 004, CHARMANDER, seen", "seen row")
Pokedex.screen, Pokedex.selectedSpecies, Pokedex.dataPage, Pokedex.listCursor = "data", 1, 1, 1
poll(dexScreen)
eq(last(), "number 001, BULBASAUR, SEED POKéMON, height 2 feet 04 inches, weight 15.2 lbs. A strange seed was planted on its back.",
  "entry page 1 once caught")
Pokedex.selectedSpecies = 16
poll(dexScreen)
eq(last(), "number 016, PIDGEY, seen", "entry page 1 for a seen Pokémon")
Pokedex.dataPage = 2
poll(dexScreen)
eq(last(), "number 016, PIDGEY. AREA: ROUTE 1, ROUTE 2", "entry page 2: the marked places by name")
Pokedex.selectedSpecies = 4
poll(dexScreen)
eq(last(), "number 004, CHARMANDER. AREA UNKNOWN", "area unknown as drawn, alone")
Pokedex.screen, Pokedex.currentCategory, Pokedex.categoryPage, Pokedex.categorySlot = "category_grid", "grassland", 1, 1
poll(dexScreen)
eq(last(), "GRASSLAND. page 1 of 2. number 001, BULBASAUR, caught, 1 of 2", "habitat page through its own category_title")
Pokedex.categorySlot = 2
poll(dexScreen)
eq(last(), "number 016, PIDGEY, 2 of 2", "habitat slot")

-- ---------------------------------------------------------------- PC hub
local PcMenu = require("src.ui.game3.pc_menu")
reset()
PcMenu.open, PcMenu._session, PcMenu.mode, PcMenu.cursor = true, session, "root", 1
PcMenu._status = expand("Text_AccessWhichPC")
PcMenu._rootKey, PcMenu._rootRows = nil, nil
local pcScreen = screen("pc_menu", PcMenu)
poll(pcScreen)
n = count()
eq(n, 0, "PC root waits until its rows are drawn")
PcMenu._rootKey = "k"
PcMenu._rootRows = { { id = "storage", label = "SOMEONE'S PC" }, { id = "player", label = "RED's PC" }, { id = "quit", label = "LOG OFF" } }
poll(pcScreen)
eq(last(), "Which PC should be accessed? SOMEONE'S PC, 1 of 3", "PC root: question, row, position")
PcMenu.mode, PcMenu.cursor = "storage_menu", 1
PcMenu._status = expand("gText_WithdrawMonDescription")
poll(pcScreen)
eq(last(), "WITHDRAW POKéMON, 1 of 5. Move POKéMON stored in BOXES to your party.", "storage menu: row, position, description")
PcMenu.cursor, PcMenu._status = 2, expand("gText_DepositMonDescription")
poll(pcScreen)
eq(last(), "DEPOSIT POKéMON. Store POKéMON in your party in BOXES.", "storage menu move: row and description")
PcMenu.mode, PcMenu._status = "msg", expand("gText_JustOnePkmn")
poll(pcScreen)
eq(last(), "That's your last POKéMON!", "PC message")

-- --------------------------------------------------------------- item PC
local ItemPc = require("src.ui.game3.item_pc")
reset()
session.storage = { items = { { id = 13, qty = 1 }, { id = 289, qty = 1 } }, currentBox = 1, boxes = {} }
ItemPc.open, ItemPc._session, ItemPc.mode, ItemPc.scroll, ItemPc.row = true, session, "list", 0, 0
local itemPcScreen = screen("item_pc", ItemPc)
poll(itemPcScreen)
eq(last(), "WITHDRAW ITEM. POTION, quantity 1, 1 of 3. Restores the HP of a POKéMON by 20 points.", "item PC entry")
ItemPc.row = 1
poll(itemPcScreen)
eq(last(), "TM01, quantity 1. MEGA PUNCH", "item PC TM row describes its move")
ItemPc.row = 0
ItemPc.mode, ItemPc.subCursor = "submenu", 1
poll(itemPcScreen)
eq(last(), "POTION is selected. WITHDRAW, 1 of 3", "item PC submenu from its own table")
ItemPc.mode, ItemPc.qty = "qty", 1
poll(itemPcScreen)
eq(last(), "Withdraw how many POTION(s)? Quantity 1, up to 1", "item PC quantity")

-- ----------------------------------------------------------- box storage
local BoxStorageUI = require("src.ui.game3.box_storage_ui")
local ReleaseSeq = require("src.ui.game3.release_seq")
local boxes = {}
for b = 1, 14 do boxes[b] = { name = "BOX " .. b, wallpaper = 1, mons = {} } end
boxes[1].mons[1] = { species = 16, nickname = "", level = 3, gender = "F" }
boxes[1].mons[8] = { species = 4, nickname = "CHAR", level = 5, gender = "M", heldItem = 13 }
session.storage = { items = {}, currentBox = 1, boxes = boxes }
session.party = { bulba, pidgey }
local function openBox(fields)
  BoxStorageUI.open, BoxStorageUI._session, BoxStorageUI.mode, BoxStorageUI.subMode = true, session, "browse", "move"
  BoxStorageUI.cursorSlot, BoxStorageUI.partyCursor, BoxStorageUI.holdingMon, BoxStorageUI.drawerOpen = 1, 1, nil, false
  BoxStorageUI._actionTarget, BoxStorageUI._status, BoxStorageUI._pendingDeposit = nil, nil, nil
  ReleaseSeq.active = false
  for k, v in pairs(fields or {}) do BoxStorageUI[k] = v end
  return screen("box_storage", BoxStorageUI)
end
reset()
local boxScreen = openBox()
poll(boxScreen)
eq(last(), "BOX 1, 2 of 30. PIDGEY, female, level 3, row 1, column 1", "box entry: box, count, slot")
BoxStorageUI.cursorSlot = 2
poll(boxScreen)
eq(last(), "empty, row 1, column 2", "empty slot")
BoxStorageUI.cursorSlot = 8
poll(boxScreen)
eq(last(), "CHAR, CHARMANDER, male, level 5, holding POTION, row 2, column 2", "nicknamed Pokémon with species and item")
BoxStorageUI.cursorSlot = 0
poll(boxScreen)
eq(last(), "BOX 1, 1 of 14", "box title")
BoxStorageUI.cursorSlot = -10
poll(boxScreen)
eq(last(), "PARTY POKéMON button", "party button")
session.storage.currentBox, BoxStorageUI.cursorSlot = 2, 1
poll(boxScreen)
eq(last(), "BOX 2, 0 of 30. empty, row 1, column 1", "box change: name, count, slot")
session.storage.currentBox = 1
poll(boxScreen)
BoxStorageUI.holdingMon = boxes[1].mons[1]
poll(boxScreen)
eq(last(), "holding PIDGEY. PIDGEY, female, level 3, row 1, column 1", "picked up")
BoxStorageUI.holdingMon = nil
BoxStorageUI.mode, BoxStorageUI._actionTarget, BoxStorageUI.actionCursor = "action_menu", { mon = boxes[1].mons[8] }, 1
BoxStorageUI._activeActions = { "MOVE", "SUMMARY", "WITHDRAW", "RELEASE", "CANCEL" }
poll(boxScreen)
eq(last(), "CHAR. MOVE, 1 of 5", "action menu through the screen's own menu_text")
BoxStorageUI.actionCursor = 4
poll(boxScreen)
eq(last(), "RELEASE", "action change")
BoxStorageUI.mode, BoxStorageUI.boxMenuCursor = "box_menu", 1
poll(boxScreen)
eq(last(), "BOX 1. SWITCH BOX, 1 of 3", "box menu")
BoxStorageUI.mode, BoxStorageUI._pickBox = "pick_box", 1
poll(boxScreen)
eq(last(), "Jump to which BOX? BOX 1, 2 of 30", "box picker")
BoxStorageUI._pickBox = 2
poll(boxScreen)
eq(last(), "BOX 2, 0 of 30", "box picker change")
BoxStorageUI.mode, BoxStorageUI.wallpaperCursor = "pick_wallpaper", 1
poll(boxScreen)
check(last() and last():find("^Pick the wallpaper%. FOREST, 1 of ") ~= nil, "wallpaper picker: " .. tostring(last()))
BoxStorageUI.mode, BoxStorageUI.partyCursor, BoxStorageUI.drawerOpen = "party_drawer", 1, true
poll(boxScreen)
eq(last(), "Party, 2 POKéMON. BULBA, BULBASAUR, male, level 7, holding POTION, 1 of 7", "party drawer")
BoxStorageUI.partyCursor = 7
poll(boxScreen)
eq(last(), "CANCEL, 7 of 7", "drawer cancel")
BoxStorageUI.mode, BoxStorageUI.drawerOpen = "browse", false
BoxStorageUI.cursorSlot = 8
ReleaseSeq.active, ReleaseSeq.state, ReleaseSeq.mon, ReleaseSeq.yesNoCursor = true, "confirm", boxes[1].mons[8], 2
poll(boxScreen)
eq(last(), "Release this POKéMON? NO", "release question, NO by default")
ReleaseSeq.yesNoCursor = 1
poll(boxScreen)
eq(last(), "YES", "release YES")
ReleaseSeq.state = "anim"
n = count()
poll(boxScreen)
eq(count(), n, "release animation is silent")
ReleaseSeq.state = "released"
poll(boxScreen)
eq(last(), "CHAR was released.", "released")
ReleaseSeq.state = "bye"
poll(boxScreen)
eq(last(), "Bye-bye, CHAR!", "bye-bye")
ReleaseSeq.active = false
BoxStorageUI.mode, BoxStorageUI._status = "message", "That's your last\nPOKéMON!"
poll(boxScreen)
eq(last(), "That's your last POKéMON!", "storage message")

-- ------------------------------------------------------------------ shop
local ShopMenu = require("src.ui.game3.shop_menu")
reset()
session.money = 3000
session.bag = bag
ShopMenu.open, ShopMenu._session, ShopMenu.mode, ShopMenu.cursor, ShopMenu._rse = true, session, "root", 1, nil
ShopMenu._items, ShopMenu._status, ShopMenu._fading = { 13, 14 }, "Hi, there!\nMay I help you?", false
local shopScreen = screen("shop", ShopMenu)
poll(shopScreen)
eq(last(), "Hi, there! May I help you? BUY, 1 of 3", "shop: clerk and BUY")
ShopMenu.cursor = 2
poll(shopScreen)
eq(last(), "SELL", "shop root change")
ShopMenu.mode, ShopMenu.cursor = "buy", 1
poll(shopScreen)
eq(last(), "MONEY ¥3000. POTION, ¥300, 1 of 3. Restores the HP of a POKéMON by 20 points.", "buy list: money, row, price, description")
ShopMenu.cursor = 3
poll(shopScreen)
eq(last(), "CANCEL. Quit shopping.", "buy list cancel")
ShopMenu.cursor = 1
poll(shopScreen)
ShopMenu.mode, ShopMenu.qty, ShopMenu._pending = "buy_qty", 1, { id = 13, name = "POTION", price = 300 }
ShopMenu._status = "POTION? Certainly.\nHow many would you like?"
poll(shopScreen)
eq(last(), "POTION? Certainly. How many would you like? Quantity 1, up to 10, ¥300, IN BAG: 2", "buy quantity with total and IN BAG")
ShopMenu.qty = 3
poll(shopScreen)
eq(last(), "3, ¥900", "buy quantity change")
ShopMenu.mode, ShopMenu.yesNoCursor, ShopMenu._status = "buy_confirm", 1, "POTION, and you want 3.\nThat will be ¥900. Okay?"
poll(shopScreen)
eq(last(), "POTION, and you want 3. That will be ¥900. Okay? YES", "buy confirm")
ShopMenu.mode, ShopMenu._status, session.money = "buy_msg", "Here you are!\nThank you!", 2100
poll(shopScreen)
eq(last(), "Here you are! Thank you! MONEY ¥2100", "purchase message and new money")

-- ------------------------------------------------------------- money box
local MoneyBox = require("src.ui.game3.money_box")
reset()
MoneyBox.visible, MoneyBox._amount = true, 2100
local game3 = { generation = 3, phase = "field" }
local overlays = Top.ambient(game3)
local box
for _, o in ipairs(overlays) do if o.gen3 == "money_box" then box = o end end
check(box ~= nil, "money box listed as an ambient overlay while shown")
local memo = {}
local text, interrupt = Items.moneyBox.poll(box, memo, true)
eq(text, "MONEY ¥2100", "money box amount")
check(interrupt == false, "money box queues")
MoneyBox._amount = 1900
eq((Items.moneyBox.poll(box, memo)), "MONEY ¥1900", "money box change")
MoneyBox.visible = false
overlays = Top.ambient(game3)
local still = false
for _, o in ipairs(overlays) do if o.gen3 == "money_box" then still = true end end
check(not still, "money box gone once hidden")

-- ------------------------------------------------------------ region map
local RegionMap = require("src.ui.game3.region_map")
local mapState = { text = { map = "PALLET TOWN" }, player = { exists = true }, selectedRegion = 0, playersRegion = 0 }
local ready = false
local saved = { RegionMap.state, RegionMap.inputReady, RegionMap.canFlyToCursor }
RegionMap.state = function() return mapState end
RegionMap.inputReady = function() return ready end
RegionMap.canFlyToCursor = function() return true end
reset()
RegionMap.open, RegionMap.mode, RegionMap.cursorX, RegionMap.cursorY, RegionMap.playerX, RegionMap.playerY = true, "normal", 4, 11, 4, 11
local mapScreen = screen("region_map", RegionMap)
poll(mapScreen)
eq(count(), 0, "region map waits for its opening animation")
ready = true
poll(mapScreen)
eq(last(), "Town map. PALLET TOWN, you are here", "town map: place and you are here")
RegionMap.cursorY, mapState.text = 10, { map = "ROUTE 1" }
poll(mapScreen)
eq(last(), "ROUTE 1", "cursor move: the place")
mapState.text = {}
RegionMap.cursorX = 10
n = count()
poll(mapScreen)
eq(count(), n, "an empty cell says nothing")
RegionMap.mode, RegionMap.cursorX, mapState.text = "fly", 4, { map = "VIRIDIAN CITY" }
poll(mapScreen)
eq(last(), "VIRIDIAN CITY, can fly", "Fly map: can fly")
mapState.preview = { text = { name = "VIRIDIAN FOREST", desc = "A deep and sprawling\nforest." } }
poll(mapScreen)
eq(last(), "VIRIDIAN FOREST. A deep and sprawling forest.", "dungeon preview text")
RegionMap.state, RegionMap.inputReady, RegionMap.canFlyToCursor = saved[1], saved[2], saved[3]

eq(trapped, 0, "Bag.listPocket, Bag.get and Storage.ensure were never called")

-- Cost of an unchanged frame (informational; LuaJIT, fake backend): the
-- bag, party and box storage presenters compare fields and return.
do
  local function cost(presenter, p, label)
    local m = {}
    presenter.poll(p, m, true)
    local frames = 100000
    local start = os.clock()
    for _ = 1, frames do presenter.poll(p, m, false) end
    local us = (os.clock() - start) / frames * 1e6
    print(string.format("[cost] %s unchanged frame: %.3f microseconds", label, us))
    check(us < 50, label .. " unchanged frame stays cheap")
  end
  local bp = openBag()
  cost(Items.bag, bp, "bag")
  local pp = openParty({ bulba, pidgey })
  cost(Items.party, pp, "party")
  cost(Items.boxStorage, openBox(), "box storage")
  cost(Items.pokedex, dexScreen, "Pokédex")
end

T.finish("gen3 items")
