-- Gen 2 information screens (decision 27): party list, summary, Pokédex,
-- Pokégear (strip, clock, map, phone, radio, fly map, town map), caller-ID
-- box, house radio and trainer card.  States are bare tables with the real
-- upstream metatables (src/ui/gen2/...) and a small fake game, polled
-- through the presenters directly so the interrupt flag can be checked.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness")
local check, eq = T.check, T.eq

local Presenters = require("src.access.screens.Presenters")
local Info = require("src.access.screens.gen2.Info")
local PartyMenu = require("src.ui.gen2.PartyMenu")
local SummaryMenu = require("src.ui.gen2.SummaryMenu")
local PokedexMenu = require("src.ui.gen2.PokedexMenu")
local Pokegear = require("src.ui.gen2.Pokegear")
local CallerBox = require("src.ui.gen2.CallerBox")
local MapRadio = require("src.ui.gen2.MapRadio")
local TrainerCard = require("src.ui.gen2.TrainerCard")

-- Polls `presenter` once; returns text and interrupt.
local function poller(presenter, state)
  local memo = {}
  return function(entering)
    return presenter.poll(state, memo, entering == true)
  end
end

local data = {
  pokemon = {
    PIKACHU = { name = "PIKACHU", dex = 25, types = { "ELECTRIC" }, tmhm = { "THUNDERBOLT" } },
    CHIKORITA = { name = "CHIKORITA", dex = 152, types = { "GRASS" }, tmhm = {} },
    TOGEPI = { name = "TOGEPI", dex = 175, types = { "NORMAL" } },
    UNOWN = { name = "UNOWN", dex = 201, types = { "PSYCHIC" } },
  },
  moves = {
    THUNDERSHOCK = { name = "THUNDERSHOCK", pp = 30, type = "ELECTRIC", power = 40,
      description = "An attack that may<NEXT>cause paralysis." },
    GROWL = { name = "GROWL", pp = 40, type = "NORMAL", power = 0,
      description = "Reduces the foe's<NEXT>ATTACK." },
  },
  items = { POTION = { name = "POTION" } },
}
local save = {
  player = { name = "GOLD", id = 12345, money = 3000, badges = { true, HIVE = true } },
  playTime = { hours = 1, minutes = 23 },
  pokedex = { seen = { PIKACHU = true, CHIKORITA = true }, caught = { PIKACHU = true } },
}
local game = { data = data, save = save }

local function newPika()
  return { species = "PIKACHU", nickname = "SPARKY", level = 5, hp = 19, maxHp = 20,
    experience = 135, gender = "male", item = "POTION",
    stats = { hp = 20, attack = 11, defense = 9, specialAttack = 10, specialDefense = 10, speed = 14 },
    moves = { { id = "THUNDERSHOCK", pp = 30 }, { id = "GROWL" } } }
end

-- --------------------------------------------------------------- party
do
  local pika = newPika()
  local egg = { species = "TOGEPI", isEgg = true, level = 5, hp = 10, maxHp = 10 }
  local fainted = { species = "CHIKORITA", level = 7, hp = 0, maxHp = 24, status = "psn",
    item = "FLOWER_MAIL" }
  local party = { pika, egg, fainted }
  local menu = setmetatable({ game = game, save = save, party = party, index = 1,
    prompt = PartyMenu.PROMPTS.choose, promptIsBuiltin = true,
    pokemon = data.pokemon, moves = data.moves }, PartyMenu)
  check(Presenters.find(menu) == Info.partyMenu, "party presenter is registered")
  local poll = poller(Info.partyMenu, menu)
  local text, interrupt = poll(true)
  eq(text, "Choose a POKéMON. SPARKY, PIKACHU, level 5, HP 19 of 20, holding an item, 1 of 4",
    "party entry: prompt, row with species and held marker, position")
  check(interrupt == true, "party speech interrupts")
  eq(poll(), nil, "unchanged frame is silent")
  menu.index = 2
  eq(poll(), "EGG", "an egg row is the word EGG alone, as drawn")
  menu.index = 3
  eq(poll(), "CHIKORITA, level 7, HP 0 of 24, fainted, holding mail", "fainted row and mail marker")
  fainted.hp = 5
  menu.index = 1
  poll()
  menu.index = 3
  eq(poll(), "CHIKORITA, level 7, HP 5 of 24, PSN, holding mail", "status from the screen's own row")
  menu.index = 4
  eq(poll(), "CANCEL", "the row past the last mon is CANCEL")

  menu.index = 1
  poll()
  menu:openSubmenu()
  eq(poll(), "STATS, 1 of 5", "submenu opens with label and position")
  menu.submenu.index = 2
  eq(poll(), "SWITCH", "submenu move says the label")
  menu:closeSubmenu()
  menu:beginSwitch(1)
  eq(poll(), "Move to where? SPARKY, PIKACHU, level 5, HP 19 of 20, holding an item, 1 of 3",
    "switch: the drawn prompt, the row, position without CANCEL")
  menu.index = 3
  eq(poll(), "CHIKORITA, level 7, HP 5 of 24, PSN, holding mail", "switch target row")
  -- finishSwitch also plays a sound; swap by hand the way it does
  party[1], party[3] = party[3], party[1]
  menu.switchFrom = nil
  eq(poll(), "SPARKY, PIKACHU, level 5, HP 19 of 20, holding an item, 3 of 4",
    "after the switch: the mon now under the cursor, with position")
  party[1], party[3] = party[3], party[1]

  menu.index = 1
  menu:showItemResult(1, { fromHp = 10, toHp = 19, text = "SPARKY\nrecovered 9HP!" })
  eq(poll(), "SPARKY, PIKACHU, level 5, HP 10 of 20, holding an item", "row shows the HP the bar is at")
  eq(poll(), nil, "climbing HP is not announced every step")
  menu.itemResult.shown = 19
  eq(poll(), "SPARKY recovered 9HP!", "the item message once the climb is over")
  menu.itemResult = nil
  eq(poll(), "SPARKY, PIKACHU, level 5, HP 19 of 20, holding an item", "back on the row after the message")

  local teach = setmetatable({ game = game, save = save, party = party, index = 1,
    prompt = PartyMenu.PROMPTS.teach, promptIsBuiltin = true, tmhm = { move = "THUNDERBOLT" },
    pokemon = data.pokemon }, PartyMenu)
  local pollTeach = poller(Info.partyMenu, teach)
  eq(pollTeach(true), "Teach which PKMN? SPARKY, PIKACHU, level 5, able, holding an item, 1 of 4",
    "TM teaching: the screen's own ABLE check instead of HP")
  teach.index = 3
  eq(pollTeach(), "CHIKORITA, level 7, not able, PSN, holding mail", "NOT ABLE")

  local empty = setmetatable({ game = game, party = {}, index = 1,
    prompt = PartyMenu.PROMPTS.choose, promptIsBuiltin = true }, PartyMenu)
  eq(Info.partyMenu.poll(empty, {}, true), "You have no PKMN! CANCEL, 1 of 1", "empty party")
end

-- ------------------------------------------------------------- summary
do
  local pika = newPika()
  local chiko = { species = "CHIKORITA", nickname = "CHIKORITA", level = 7, hp = 0, maxHp = 24,
    experience = 400, stats = { hp = 24 }, moves = { { id = "GROWL", pp = 0 } } }
  local summary = setmetatable({ game = game, save = save, party = { pika, chiko }, index = 1,
    mon = pika, page = SummaryMenu.PINK_PAGE, moveIndex = 1, moveDetail = false,
    pokemon = data.pokemon, moves = data.moves, items = data.items }, SummaryMenu)
  check(Presenters.find(summary) == Info.summaryMenu, "summary presenter is registered")
  local poll = poller(Info.summaryMenu, summary)
  eq(poll(true), "SPARKY, PIKACHU, number 25, level 5, male. HP 19 of 20, status OK, "
    .. "type ELECTRIC, experience 135, 81 to level 6, page 1 of 3", "summary entry: upper half and pink page")
  eq(poll(), nil, "summary unchanged")
  summary:turnPage(1)
  eq(poll(), "item POTION, moves: THUNDERSHOCK, ELECTRIC, PP 30 of 30; GROWL, NORMAL, PP 40 of 40, page 2 of 3",
    "green page: item, moves with type and PP; missing PP means full")
  summary:turnPage(1)
  eq(poll(), "ID 12345, OT GOLD, attack 11, defense 9, special attack 10, special defense 10, speed 14, page 3 of 3",
    "blue page: ID, OT and stats")
  summary:turnPage(1)
  poll()
  summary.index, summary.mon = 2, chiko
  eq(poll(), "CHIKORITA, number 152, level 7. HP 0 of 24, fainted, type GRASS, experience 400, 112 to level 8, page 1 of 3",
    "switching mon: header and the same page; species not repeated")
  summary:turnPage(1)
  eq(poll(), "item none, moves: GROWL, NORMAL, PP 0 of 40, page 2 of 3", "an explicit 0 PP is said as 0")

  summary.index, summary.mon, summary.page = 1, pika, SummaryMenu.GREEN_PAGE
  poll()
  summary.moveDetail, summary.moveIndex = true, 1
  eq(poll(), "THUNDERSHOCK, PP 30 of 30, type ELECTRIC, power 40, 1 of 2. An attack that may cause paralysis.",
    "move screen: move, PP, type, power, position, description")
  summary.moveIndex = 2
  eq(poll(), "GROWL, PP 40 of 40, type NORMAL. Reduces the foe's ATTACK.", "no power is left out")
  summary.swapFrom = 2
  eq(poll(), "GROWL. Where?", "picking a move up")
  summary.moveIndex = 1
  eq(poll(), "THUNDERSHOCK, PP 30 of 30", "while holding, only name and PP")
  summary:swapMoves(2, 1)
  summary.swapFrom = nil
  eq(poll(), "GROWL, PP 40 of 40, type NORMAL, 1 of 2. Reduces the foe's ATTACK.", "dropped: the moved move")
  summary:swapMoves(2, 1)
  summary.moveDetail = false
  eq(poll(), "item POTION, moves: THUNDERSHOCK, ELECTRIC, PP 30 of 30; GROWL, NORMAL, PP 40 of 40, page 2 of 3",
    "leaving the move screen returns to the page")

  local infected = newPika()
  infected.pokerus = 0x12
  local sick = setmetatable({ game = game, save = save, party = { infected }, index = 1, mon = infected,
    page = 1, moveIndex = 1, pokemon = data.pokemon, moves = data.moves }, SummaryMenu)
  check(Info.summaryMenu.poll(sick, {}, true):find("status POKéRUS", 1, true) ~= nil, "POKéRUS replaces the status")

  local egg = { species = "TOGEPI", isEgg = true, eggSteps = 40 }
  local eggScreen = setmetatable({ game = game, save = save, party = { egg }, index = 1, mon = egg,
    page = 1, moveIndex = 1, pokemon = data.pokemon }, SummaryMenu)
  eq(Info.summaryMenu.poll(eggScreen, {}, true), "EGG. Wonder what's inside? It needs more time, though.",
    "egg page: EGG and the flavour line")

  local tutor = setmetatable({ game = game, save = save, party = { pika }, index = 1, mon = pika,
    page = 1, moveIndex = 1, moveDetail = true, moveScreen = true, pokemon = data.pokemon,
    moves = data.moves }, SummaryMenu)
  eq(Info.summaryMenu.poll(tutor, {}, true),
    "SPARKY, level 5. THUNDERSHOCK, PP 30 of 30, type ELECTRIC, power 40, 1 of 2. An attack that may cause paralysis.",
    "the party's MOVE row opens straight on the move screen")
end

-- ------------------------------------------------------------- Pokédex
do
  local dexData = {
    pokemon = data.pokemon,
    gen2Encounters = { grass = { ROUTE_29 = { slots = { day = { { species = "PIKACHU" } } } } } },
    gen2Maps = { ROUTE_29 = { landmark = 2 } },
    gen2Landmarks = { landmarks = {
      LANDMARK_NEW_BARK_TOWN = { index = 1, name = "NEW BARK\nTOWN" },
      LANDMARK_ROUTE_29 = { index = 2, name = "ROUTE 29" },
      LANDMARK_PALLET_TOWN = { index = 46, name = "PALLET\nTOWN" },
      LANDMARK_FAST_SHIP = { index = 94, name = "FAST SHIP" },
    } },
  }
  local dexGame = { data = dexData, save = save }
  local dex = {
    entries = {
      PIKACHU = { dex = 25, kind = "MOUSE", height = 104, weight = 132,
        text = "It stores electric-<NEXT>ity in its cheeks.", text2 = "Page two text." },
      CHIKORITA = { dex = 152, kind = "LEAF", height = 211, weight = 141, text = "Leaf text." },
      TOGEPI = { dex = 175, kind = "SPIKE BALL", height = 100, weight = 33, text = "Egg text." },
    },
    newOrder = { "PIKACHU", "CHIKORITA", "TOGEPI" },
  }
  local menu = setmetatable({ game = dexGame, save = save, data = dexData, dex = dex,
    pokemon = data.pokemon, modeIndex = 1, index = 1, scroll = 0, view = "list", page = 1,
    entryAction = 1, optionIndex = 1, searchIndex = 1, unownIndex = 0, searchType = { 1, 0 } },
    PokedexMenu)
  menu:rebuild()
  check(Presenters.find(menu) == Info.pokedexMenu, "Pokédex presenter is registered")
  local poll = poller(Info.pokedexMenu, menu)
  eq(poll(true), "Pokédex, NEW POKéDEX MODE, seen 2, owned 1. PIKACHU, owned, 1 of 3",
    "Pokédex entry: mode, counts, row and position")
  menu.index = 2
  eq(poll(), "CHIKORITA, seen, 2 of 3", "seen row")
  menu.index = 3
  eq(poll(), "unknown, 3 of 3", "an unseen row reads unknown (the screen shows dashes)")
  menu.index = 1
  poll()
  menu.view = "entry"
  eq(poll(), "PIKACHU, MOUSE, number 25, height 1 feet 4 inches, weight 13.2 pounds. "
    .. "It stores electricity in its cheeks. PAGE, 1 of 4", "entry: header, size, page text, action")
  menu.page = 2
  eq(poll(), "page 2 of 2. Page two text.", "page flip: the marker, then the text")
  menu.entryAction = 2
  eq(poll(), "AREA, 2 of 4", "action bar move")
  menu.view, menu.areaRegion = "area", nil
  eq(poll(), "PIKACHU'S NEST. Johto. ROUTE 29", "AREA: title, region and nest landmarks")
  menu.view = "entry"
  eq(poll(), "AREA, 2 of 4", "back from AREA: the action")
  eq(Info.pokedexMenu.poll(menu, {}, false) ~= nil, true, "fresh memo speaks")
  menu.view = "list"
  eq(poll(), "PIKACHU, owned, 1 of 3", "back on the list: the row")
  eq(poll(true), "PIKACHU, owned, 1 of 3", "return from a screen above: the focus only")

  menu.index = 2
  poll()
  menu.view, menu.page, menu.entryAction = "entry", 1, 1
  eq(poll(), "CHIKORITA, LEAF, number 152. PAGE, 1 of 4", "seen but not caught: no size and no text")

  menu.view, menu.optionIndex = "option", 1
  eq(poll(), "OPTION. NEW POKéDEX MODE, 1 of 3. PKMN are listed by evolution type.",
    "OPTION: title, mode, position, description")
  menu.optionIndex = 2
  eq(poll(), "OLD POKéDEX MODE. PKMN are listed by official type.", "option move")
  menu.view, menu.modeIndex, menu.index = "list", 2, 1
  menu:rebuild()
  eq(poll(), "Pokédex, OLD POKéDEX MODE, seen 2, owned 1. 25, PIKACHU, owned, 1 of 3",
    "OLD mode prints numbers; the new order is announced with its context")

  menu.view, menu.searchIndex = "search", 1
  eq(poll(), "SEARCH. TYPE1, NORMAL, 1 of 4", "SEARCH entry")
  menu.searchType[1] = 2
  eq(poll(), "FIGHTING", "type wheel change says the value")
  menu.searchIndex = 2
  eq(poll(), "TYPE2, none", "a blank wheel reads none")
  menu.searchIndex = 3
  eq(poll(), "BEGIN SEARCH!!", "search row")
  menu.searchMessage = "No <PK><MN> found!"
  eq(poll(), "No PKMN found!", "no results message")

  save.unownDex = { 1, 3 }
  menu.view, menu.unownIndex = "unown", 0
  eq(poll(), "UNOWN MODE. A, ANGRY, 1 of 2", "UNOWN MODE")
  menu.unownIndex = 1
  eq(poll(), "C, CHASE", "next form")
  save.unownDex = nil

  local fresh = setmetatable({ game = dexGame, save = {}, data = dexData, dex = dex, pokemon = data.pokemon,
    modeIndex = 1, index = 1, scroll = 0, view = "unown", unownIndex = 0 }, PokedexMenu)
  Info.pokedexMenu.poll(fresh, {}, true)
  eq(fresh.save.unownDex, nil, "reading UNOWN MODE never creates the save's list")

  local newEntry = setmetatable({ game = dexGame, save = save, data = dexData, dex = dex,
    pokemon = data.pokemon, modeIndex = 1, index = 1, scroll = 0, view = "entry", page = 1,
    entryAction = 1, newEntry = true }, PokedexMenu)
  newEntry:rebuild()
  local pollNew = poller(Info.pokedexMenu, newEntry)
  eq(pollNew(true), "PIKACHU, MOUSE, number 25, height 1 feet 4 inches, weight 13.2 pounds. "
    .. "It stores electricity in its cheeks.", "new entry after a catch: no action bar")
  newEntry.page = 2
  eq(pollNew(), "page 2 of 2. Page two text.", "new entry second page")
end

-- ------------------------------------------------------------ Pokégear
do
  local landmarks = { landmarks = {
    LANDMARK_NEW_BARK_TOWN = { index = 1, name = "NEW BARK\nTOWN" },
    LANDMARK_ROUTE_29 = { index = 2, name = "ROUTE 29" },
    LANDMARK_SILVER_CAVE = { index = 45, name = "SILVER CAVE" },
    LANDMARK_PALLET_TOWN = { index = 46, name = "PALLET\nTOWN" },
    LANDMARK_FAST_SHIP = { index = 94, name = "FAST SHIP" },
  } }
  local gearSave = { player = save.player, engineFlags = { [0] = true, [1] = true, [2] = true },
    phone = { list = { 1, 4, 0, 0, 0, 0, 0, 0, 0, 0 } } }
  local gearGame = { data = {}, save = gearSave }
  local gear = setmetatable({ game = gearGame, save = gearSave, landmarks = landmarks,
    currentLandmark = "LANDMARK_NEW_BARK_TOWN", clock = { hour = 10, minute = 5, weekday = 7 },
    cardIndex = 1, mode = "strip", tuningKnob = 0, phoneCursor = 0, phoneScroll = 0,
    phoneSubmenuCursor = 0 }, Pokegear)
  gear.cards = gear:visibleCards()
  check(#gear.cards == 4, "fixture owns all four cards")
  check(Presenters.find(gear) == Info.pokegear, "Pokégear presenter is registered")
  local poll = poller(Info.pokegear, gear)
  eq(poll(true), "CLOCK. SATURDAY, 10:05 AM, 1 of 4", "strip entry: card, its face, position")
  gear.clock.minute = 6
  eq(poll(), nil, "a minute tick is not announced")
  gear.cardIndex = 2
  eq(poll(), "MAP. NEW BARK TOWN, you are here, 2 of 4", "strip: map card")
  gear.mode = "card"
  eq(poll(), "MAP. NEW BARK TOWN, you are here", "into the map card")
  gear:stepMapCursor(1)
  eq(poll(), "ROUTE 29", "map cursor: the landmark")
  gear.cardIndex = 3
  eq(poll(), "PHONE. Whom do you want to call? MOM, 1 of 10", "phone card: prompt and contact")
  gear.phoneCursor = 1
  eq(poll(), "PROF.ELM, 2 of 10", "phone cursor")
  gear.phoneCursor = 2
  eq(poll(), "empty, 3 of 10", "an empty slot")
  gear.phoneCursor = 1
  poll()
  gear:openPhoneSubmenu()
  eq(poll(), "CALL, 1 of 2", "contact submenu (no DELETE for PROF.ELM)")
  gear.phoneSubmenuCursor = 1
  eq(poll(), "CANCEL", "submenu move")
  gear.phoneSubmenu = nil
  gear.call = { kind = "call", text = "PROF.ELM: ……" }
  eq(poll(), "PROF.ELM: ……", "a placed call says what the card shows")
  eq(poll(true), nil, "back from the call's text pages with the call still up: quiet")
  gear.call = nil
  eq(poll(), "Whom do you want to call? PROF.ELM, 2 of 10", "hung up: the prompt and the row")

  gear.cardIndex = 4
  local text = poll()
  eq(text, "RADIO. 0.5", "radio card on dead air: the frequency only")
  gear.tuningKnob = 16
  eq(poll(), "4.5, OAK's PKMN Talk", "tuned: frequency and station")
  gear.radio = { log = {} }
  eq(poll(), nil, "a new show with no line yet")
  gear.radio.log[1] = "OAK's <PK><MN> Talk!"
  local line, interrupt = poll()
  eq(line, "OAK's PKMN Talk!", "a show line as it prints")
  check(interrupt == false, "show lines queue rather than cut each other off")
  gear.radio.log[2] = "POKéMON"
  gear.radio.log[3] = "POKéMON        POKéMON"
  eq(poll(), "POKéMON POKéMON", "the jingle's rewritten line says only its new part")
  gear.tuningKnob = 18
  gear.radio = nil
  eq(poll(), "5.0", "retuned to dead air interrupts with the new frequency")

  local before = gearSave.phone
  local blank = setmetatable({ game = { data = {}, save = { engineFlags = { [2] = true } } },
    landmarks = landmarks, cardIndex = 2, mode = "card", phoneCursor = 0, phoneScroll = 0,
    phoneSubmenuCursor = 0, clock = { hour = 1, minute = 0, weekday = 1 } }, Pokegear)
  blank.save = blank.game.save
  blank.cards = blank:visibleCards()
  local pollBlank = poller(Info.pokegear, blank)
  eq(pollBlank(true), "PHONE. Whom do you want to call?", "no phone record yet: the prompt only")
  eq(blank.save.phone, nil, "reading the phone card never creates the phone record")
  blank:phoneList() -- what the card's draw does every frame
  eq(pollBlank(), "empty, 1 of 10", "the row once the card has made its record")
  check(gearSave.phone == before, "fixture untouched")

  local fly = setmetatable({ game = gearGame, save = gearSave, landmarks = landmarks,
    currentLandmark = "LANDMARK_NEW_BARK_TOWN",
    fly = { { spawn = "SPAWN_NEW_BARK", index = 1, name = "NEW BARK\nTOWN" },
      { spawn = "SPAWN_CHERRYGROVE", index = 3, name = "CHERRYGROVE\nCITY" } },
    flyIndex = 1, flyRegion = "johto", cardIndex = 1, mode = "card" }, Pokegear)
  fly.cards = { { id = "map", label = "FLY" } }
  local pollFly = poller(Info.pokegear, fly)
  eq(pollFly(true), "FLY. Where? NEW BARK TOWN, you are here, 1 of 2", "fly map entry")
  fly.flyIndex = 2
  eq(pollFly(), "CHERRYGROVE CITY", "fly cursor")

  local town = setmetatable({ game = gearGame, save = gearSave, landmarks = landmarks,
    currentLandmark = "LANDMARK_NEW_BARK_TOWN", townMap = true, cardIndex = 1, mode = "card" }, Pokegear)
  town.cards = { { id = "map", label = "MAP" } }
  local pollTown = poller(Info.pokegear, town)
  eq(pollTown(true), "MAP. NEW BARK TOWN, you are here", "town map entry")
  town:stepMapCursor(1)
  eq(pollTown(), "ROUTE 29", "town map cursor")
end

-- ------------------------------------------ caller box, radio, card
do
  local box = CallerBox.new("JOEY", "YOUNGSTER")
  check(Presenters.find(box) == Info.callerBox, "caller box presenter is registered")
  local poll = poller(Info.callerBox, box)
  eq(poll(true), "Phone call, JOEY, YOUNGSTER", "incoming call: who is calling")
  eq(poll(true), nil, "said once, not again on return")
  eq(Info.callerBox.poll(CallerBox.new("MOM", nil), {}, true), "Phone call, MOM", "non-trainer caller")

  local radio = setmetatable({ game = { data = {} }, station = "POKEMON_MUSIC",
    gear = setmetatable({ game = { data = {} } }, Pokegear),
    radio = { log = {}, top = "", bottom = "" }, hold = 100 }, MapRadio)
  check(Presenters.find(radio) == Info.mapRadio, "house radio presenter is registered")
  local pollRadio = poller(Info.mapRadio, radio)
  eq(pollRadio(true), "Radio, POKéMON Music", "house radio: the station named in the box")
  radio.radio.log[1] = "Hello there!"
  local line, interrupt = pollRadio()
  eq(line, "Hello there!", "house radio line")
  check(interrupt == false, "house radio lines queue")

  local card = setmetatable({ game = game, save = save, page = 1 }, TrainerCard)
  check(Presenters.find(card) == Info.trainerCard, "trainer card presenter is registered")
  local pollCard = poller(Info.trainerCard, card)
  eq(pollCard(true), "Trainer card, GOLD, ID 12345, money ¥3000, Pokédex 1, time 1 hour 23 minutes, page 1 of 2",
    "trainer card page 1")
  card.page = 2
  eq(pollCard(), "JOHTO BADGES. 2 badges: ZEPHYR, HIVE, page 2 of 2", "Johto badge page (index or name keys)")
  save.player.kantoBadges = { BOULDER = true }
  card.page = 3
  eq(pollCard(), "KANTO BADGES. 1 badge: BOULDER, page 3 of 3",
    "page 3 mirrors drawPlain: Kanto names over the Johto flags (index keys only)")
  save.player.kantoBadges = nil
end

T.finish("gen2 info")
