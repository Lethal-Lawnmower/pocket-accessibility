-- Gen 2 battle speech (decision 27): src/access/screens/gen2/Battle.lua.
--
-- Two halves.  The first builds bare tables with the real
-- src/ui/gen2/BattleState metatable and sets the fields by hand, so each
-- rule (carried rows, re-shown lines, shown HP, YES/NO, the forget list, the
-- stats box) is checked on its own.  The second runs the real screen around
-- a stub game, the way tests/gen2_battle_ui_test.lua does, and listens to a
-- whole wild battle and a trainer intro through the ScreenReader.
--
--   luajit tests/access/gen2_battle_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
GameVersion.set("crystal")

local Speech = require("src.access.Speech")
local SR = require("src.access.screens.ScreenReader")
local Presenters = require("src.access.screens.Presenters")
local Gen2Battle = require("src.access.screens.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")
local Input = require("src.core.Input")

local spoken = {}
local fake = { name = "Fake" }
local trace = os.getenv("POKEPORT_TEST_VERBOSE") == "1"
function fake:say(text, interrupt)
  spoken[#spoken + 1] = { text = text, interrupt = interrupt }
  if trace then print("said:", interrupt and "!" or " ", text) end
  return true
end
function fake:stop() return true end
function fake:close() end
Speech.shutdown()
Speech.start({ backend = fake })
SR._resetForTests()
local function last() return spoken[#spoken] or {} end
local function count() return #spoken end

-- ---------------------------------------------------------------- fixtures

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, accuracyRaw = 242, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  GROWL = { id = "GROWL", name = "GROWL", power = 0, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 40, effect = "EFFECT_ATTACK_DOWN" },
  CURSE = { id = "CURSE", name = "CURSE", power = 0, type = "CURSE_TYPE", pp = 10,
    effect = "EFFECT_CURSE" },
  CUT = { id = "CUT", name = "CUT", power = 50, type = "NORMAL", pp = 30,
    effect = "EFFECT_NORMAL_HIT" },
}
local GROWTH = {
  GROWTH_MEDIUM_SLOW = { numerator = 6, denominator = 5, squared = -15, linear = 100, constant = 140 },
}
local function species(id, index, base, types)
  return { id = id, index = index, name = id, baseStats = base, types = types,
    catchRate = 255, baseExp = 60, growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {} }
end
local DATA = {
  pokemon = {
    growthRates = GROWTH,
    CYNDAQUIL = species("CYNDAQUIL", 155, { hp = 39, attack = 52, defense = 43, speed = 65,
      specialAttack = 60, specialDefense = 50 }, { "FIRE", "FIRE" }),
    PIDGEY = species("PIDGEY", 16, { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 }, { "NORMAL", "FLYING" }),
    RATTATA = species("RATTATA", 19, { hp = 30, attack = 56, defense = 35, speed = 72,
      specialAttack = 25, specialDefense = 35 }, { "NORMAL", "NORMAL" }),
  },
  moves = MOVES,
  text = require("tests.gen2_battle_text_fixture")(),
  type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(),
    types = { NORMAL = { id = "NORMAL", name = "NORMAL", index = 0 },
      FIRE = { id = "FIRE", name = "FIRE", index = 20 },
      FLYING = { id = "FLYING", name = "FLYING", index = 2 } },
    matchups = {} },
  items = { POKE_BALL = { id = "POKE_BALL", pocket = "BALL", name = "POKé BALL", index = 5 } },
}
local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

-- A hand-built screen: the real metatable, the fields the presenter reads.
local function fakeScreen()
  local player = { species = "CYNDAQUIL", name = "CYNDAQUIL", level = 12, hp = 20, maxHp = 35,
    gender = "male", moves = { { id = "TACKLE", pp = 30, maxPp = 35 }, { id = "GROWL", pp = 40, maxPp = 40 } } }
  local enemy = { species = "PIDGEY", name = "PIDGEY", level = 4, hp = 6, maxHp = 18,
    gender = "female", shiny = true }
  return setmetatable({
    game = { data = DATA, options = {} },
    save = { party = { player } },
    battle = { player = player, enemy = enemy, party = { player }, wild = true },
    phase = "intro", menuIndex = 1, moveIndex = 1, messageTimer = 0,
    shownMon = { player = player, enemy = enemy },
    shownHp = { player = 20, enemy = 9 },
    shownStatus = { player = false, enemy = false },
    shownLevel = 12, showEnemyHud = true, showPlayerHud = true,
  }, BattleState), player, enemy
end

-- Shows a line the way showPages does: the string, then typedText nil until
-- the typer picks it up on the next draw or update (polled again then, as
-- every frame is).
local function show(screen, text, page, carried)
  screen.message, screen.typedText = text, nil
  screen.messagePage = page or 1
  if carried ~= nil then screen.messageCarried = carried end
  SR.update(screen)
  screen.typedText = text
  SR.update(screen)
end

-- ---------------------------------------------------------------- matching

do
  local screen = fakeScreen()
  check(Gen2Battle.presenter.matches(screen), "the real Gen 2 metatable matches")
  check(not Gen2Battle.presenter.matches({ phase = "menu" }), "a plain table does not")
  eq(Presenters.find(screen), Gen2Battle.presenter, "Presenters finds the Gen 2 battle presenter")
  local gen1 = require("src.access.screens.Battle")
  check(not gen1.presenter.matches(screen), "the Gen 1 presenter does not claim it")
end

-- ---------------------------------------------------------------- messages

do
  SR._resetForTests()
  local screen = fakeScreen()
  local before = count()
  show(screen, "Wild PIDGEY\nappeared!")
  eq(last().text, "Wild PIDGEY appeared!", "a line is spoken whole, rows joined")
  eq(last().interrupt, false, "battle lines queue")
  SR.update(screen)
  eq(count(), before + 1, "an unchanged line is not repeated")

  -- trainer send-out: page 2 opens on page 1's last row
  local pages = { "YOUNGSTER JOEY\nsent out", "sent out\nRATTATA!" }
  screen.messagePages = pages
  show(screen, pages[1], 1, { [2] = true })
  eq(last().text, "YOUNGSTER JOEY sent out", "first page")
  screen.messagePages = nil -- the last page clears it, as nextPage does
  show(screen, pages[2], 2)
  eq(last().text, "RATTATA!", "the carried row of a scroll page is not said twice")

  -- the carried flag outlives the pages; a direct write must not lose its row
  show(screen, "Go! CYNDAQUIL!", 2)
  eq(last().text, "Go! CYNDAQUIL!", "a stale carried flag drops nothing from a new line")

  -- the same string shown twice in a row (two critical hits)
  show(screen, "A critical hit!", 1, {})
  local n = count()
  screen.typedText = nil -- showPages again with the same text
  SR.update(screen)
  eq(count(), n + 1, "the same line shown again is spoken again")
  screen.typedText = "A critical hit!"
  SR.update(screen)
  eq(count(), n + 1, "but only once per showing")

  -- a gap (text-pause, the menu) then the same line is a new showing
  screen.message, screen.typedText = nil, nil
  SR.update(screen)
  show(screen, "A critical hit!")
  eq(count(), n + 2, "a line after a gap is spoken even if it repeats")

  show(screen, "It's super-\neffective!")
  eq(last().text, "It's supereffective!", "a line-end hyphen is a split word, rejoined (project rule)")
  show(screen, "PIDGEY's data was newly added to the #DEX.")
  eq(last().text, "PIDGEY's data was newly added to the POKéDEX.", "# is POKé")
end

-- DIALOGUE SPEECH: ALL AT ONCE says every page when the box opens.
do
  SR._resetForTests()
  local screen = fakeScreen()
  screen.game.options.accessDialogue = "whole"
  local pages = { "YOUNGSTER JOEY\nis about to use", "is about to use\nRATTATA.",
    "Will GOLD\nchange POKéMON?" }
  screen.messagePages, screen.phase = pages, "shift-intro"
  show(screen, pages[1], 1, { [2] = true })
  eq(last().text, "YOUNGSTER JOEY is about to use RATTATA. Will GOLD change POKéMON?",
    "all pages at once, carried row dropped")
  local n = count()
  show(screen, pages[2], 2)
  screen.messagePages = nil
  show(screen, pages[3], 3)
  eq(count(), n, "later pages of the same box stay quiet")
  show(screen, "Got away safely!", 3)
  eq(last().text, "Got away safely!", "the next line is spoken")
end

-- ---------------------------------------------------------------- menu

do
  SR._resetForTests()
  local screen, player, enemy = fakeScreen()
  screen.phase = "menu"
  SR.update(screen)
  eq(last().text, "CYNDAQUIL, male, HP 20 of 35. enemy PIDGEY, shiny, level 4, female, HP 50 percent. FIGHT",
    "menu opens with both sides from the shown HP, gender and shiny the first time")
  eq(last().interrupt, false, "the turn summary queues behind the last line")
  screen.menuIndex = 2
  SR.update(screen)
  eq(last().text, "POKéMON", "PKMN label")
  eq(last().interrupt, true, "cursor moves interrupt")
  screen.menuIndex = 3
  SR.update(screen)
  eq(last().text, "PACK", "PACK label")

  -- next turn: statuses, no first-time extras
  screen.phase = "resolving"
  SR.update(screen)
  screen.shownStatus.player, screen.shownStatus.enemy = "poison", "sleep"
  player.status, enemy.status = "burn", "sleep" -- live values run ahead; the HUD lags
  screen.phase, screen.menuIndex = "menu", 1
  SR.update(screen)
  eq(last().text, "CYNDAQUIL, HP 20 of 35, PSN. enemy PIDGEY, level 4, HP 50 percent, SLP. FIGHT",
    "status tags as the HUD shows them, extras not repeated")

  -- a return from the party menu is an entry
  SR.update(screen) -- nothing new
  local n = count()
  SR.update(setmetatable({}, { __index = {} })) -- something else on top
  SR.update(screen)
  eq(count(), n + 1, "returning to the menu repeats both sides")
  check(last().text:find("^CYNDAQUIL, HP 20 of 35") ~= nil, "with the summary: " .. tostring(last().text))

  -- a new mon on the enemy side brings its gender again
  local rattata = { species = "RATTATA", name = "RATTATA", level = 3, hp = 12, maxHp = 12, gender = "male" }
  screen.shownMon.enemy, screen.shownHp.enemy, screen.shownStatus.enemy = rattata, 12, false
  screen.phase = "resolving"
  SR.update(screen)
  screen.phase = "menu"
  SR.update(screen)
  check(last().text:find("enemy RATTATA, level 3, male, HP 100 percent%. FIGHT$") ~= nil,
    "a new enemy is introduced with its gender: " .. tostring(last().text))
  -- the first one comes back: already introduced in this battle
  screen.shownMon.enemy, screen.shownHp.enemy = enemy, 9
  screen.phase = "resolving"
  SR.update(screen)
  screen.phase = "menu"
  SR.update(screen)
  check(last().text:find("enemy PIDGEY, level 4, HP 50 percent") ~= nil,
    "a returning Pokémon is not introduced again: " .. tostring(last().text))

  -- contest third label, read without creating the contest table
  screen.contest, screen.menuIndex = true, 3
  SR.update(screen)
  eq(last().text, "PARK BALL, 0 left", "contest label")
  eq(screen.save.bugContest, nil, "reading the ball count creates nothing")
  screen.save.bugContest = { balls = 18 }
  screen.menuIndex = 1
  SR.update(screen)
  screen.menuIndex = 3
  SR.update(screen)
  eq(last().text, "PARK BALL, 18 left", "contest balls left")

  -- the DUDE's demonstration drives its own menu
  local tutorial = fakeScreen()
  tutorial.tutorial, tutorial.phase = true, "menu"
  n = count()
  SR.update(tutorial)
  eq(count(), n, "the catching tutorial menu is not spoken")
end

-- ---------------------------------------------------------------- moves

do
  SR._resetForTests()
  local screen, player = fakeScreen()
  screen.phase = "moves"
  SR.update(screen)
  eq(last().text, "TACKLE, NORMAL, PP 30 of 35, 1 of 2", "move list opens with type, PP and position")
  eq(last().interrupt, true, "move list interrupts")
  screen.moveIndex = 2
  SR.update(screen)
  eq(last().text, "GROWL, NORMAL, PP 40 of 40", "next move")
  eq(rawget(player, "volatile"), nil, "reading a move creates no volatile table")

  player.volatile = { disabled = "GROWL" }
  screen.moveIndex = 1
  SR.update(screen)
  screen.moveIndex = 2
  SR.update(screen)
  eq(last().text, "GROWL, disabled", "disabled move")
  player.volatile = nil

  player.moves[2] = { id = "CURSE", maxPp = 10 }
  screen.moveIndex = 1
  SR.update(screen)
  screen.moveIndex = 2
  SR.update(screen)
  eq(last().text, "CURSE, question marks", "missing PP is left out, never 0; ??? type said")
  player.moves[2].pp = 0
  screen.moveIndex = 1
  SR.update(screen)
  screen.moveIndex = 2
  SR.update(screen)
  eq(last().text, "CURSE, question marks, PP 0 of 10", "an explicit 0 is said")

  -- SELECT reordering
  screen.moveSwapIndex = 2
  SR.update(screen)
  eq(last().text, "marked for swap", "SELECT marks the move")
  screen.moveIndex = 1
  SR.update(screen)
  eq(last().text, "TACKLE, NORMAL, PP 30 of 35", "moving off the marked row")
  player.moves[1], player.moves[2] = player.moves[2], player.moves[1]
  screen.moveSwapIndex = nil
  SR.update(screen)
  eq(last().text, "swapped, CURSE, question marks, PP 0 of 10", "SELECT again swaps")
  screen.moveSwapIndex = 1
  SR.update(screen)
  screen.moveSwapIndex = nil
  SR.update(screen)
  eq(last().text, "swap cancelled", "SELECT twice on one row swaps nothing")

  -- refusal line, then back to the list with its position
  screen.phase = "refuse-move"
  show(screen, "There's no PP left for this move!")
  eq(last().text, "There's no PP left for this move!", "refusal line")
  screen.message, screen.phase = nil, "moves"
  SR.update(screen)
  check(last().text:find(", 1 of 2$") ~= nil, "the list again with position: " .. tostring(last().text))
end

-- ---------------------------------------------------------------- YES / NO

do
  SR._resetForTests()
  local screen = fakeScreen()
  screen.phase, screen.nicknameIndex, screen.messageTimer = "ask-nickname", 1, 48
  show(screen, "Give a nickname to PIDGEY?")
  eq(last().text, "Give a nickname to PIDGEY?", "the question is the message")
  local n = count()
  SR.update(screen)
  eq(count(), n, "no YES/NO before the question is acknowledged")
  screen.messageTimer = 0
  SR.update(screen)
  eq(last().text, "YES", "YES/NO box opens on YES")
  eq(last().interrupt, false, "queued behind the question")
  screen.nicknameIndex = 2
  SR.update(screen)
  eq(last().text, "NO", "cursor to NO")
  eq(last().interrupt, true, "cursor moves interrupt")

  -- ask-next-mon opens with its box already up: one utterance
  local wild = fakeScreen()
  wild.phase, wild.nextMonIndex, wild.messageTimer = "ask-next-mon", 1, 0
  show(wild, "Use next POKéMON?")
  eq(last().text, "Use next POKéMON? YES", "question and box together")

  -- forget flow: ask-forget, NO, stop-learning asks again
  local learn = fakeScreen()
  learn.phase, learn.forgetChoice, learn.messageTimer = "ask-forget", 1, 0
  show(learn, "for EMBER?")
  check(last().text:find("YES$") ~= nil, "ask-forget box: " .. tostring(last().text))
  learn.phase, learn.messageTimer = "stop-learning", 48
  show(learn, "Stop learning\nEMBER?")
  eq(last().text, "Stop learning EMBER?", "stop-learning question")
  learn.messageTimer = 0
  SR.update(learn)
  eq(last().text, "YES", "a new question opens its box again")
end

-- ---------------------------------------------------------------- forget list

do
  SR._resetForTests()
  local screen, player = fakeScreen()
  player.moves = { { id = "TACKLE", pp = 30, maxPp = 35 }, { id = "GROWL", pp = 40, maxPp = 40 },
    { id = "CUT", pp = 30, maxPp = 30 }, { id = "CURSE", maxPp = 10 } }
  screen.pendingLearn = { index = 1, move = "EMBER", moveName = "EMBER" }
  screen.phase, screen.forgetIndex, screen.messageTimer = "choose-forget", 1, 0
  show(screen, "Which move should\nbe forgotten?")
  eq(last().text, "Which move should be forgotten? TACKLE, PP 30 of 35, 1 of 4",
    "question and the first move with position")
  screen.forgetIndex = 4
  SR.update(screen)
  eq(last().text, "CURSE", "a move without PP data is named only")
  screen.forgetIndex = 3
  SR.update(screen)
  eq(last().text, "CUT, PP 30 of 30", "next move")
  -- HM refusal hides the list, then it comes back on its first row
  screen.messageTimer, screen.forgetIndex = 48, 1
  show(screen, "HM moves can't be\nforgotten now.")
  eq(last().text, "HM moves can't be forgotten now.", "HM refusal")
  screen.messageTimer = 0
  show(screen, "Which move should\nbe forgotten?")
  eq(last().text, "Which move should be forgotten? TACKLE, PP 30 of 35, 1 of 4", "list again")
end

-- ---------------------------------------------------------------- stats box

do
  SR._resetForTests()
  local screen = fakeScreen()
  local mon = Mon.new(DATA, "CYNDAQUIL", 13, { dvs = perfect })
  mon.stats = { attack = 1, defense = 1, specialAttack = 1, specialDefense = 1, speed = 1 } -- stale
  local expected = Mon.stats(DATA.pokemon.CYNDAQUIL.baseStats, mon.dvs, 13, mon.statExp)
  screen.phase, screen.statsBoxMon = "stats-box", mon
  SR.update(screen)
  eq(last().text, string.format(
    "CYNDAQUIL, level 13 stats: attack %d, defense %d, special attack %d, special defense %d, speed %d",
    expected.attack, expected.defense, expected.specialAttack, expected.specialDefense, expected.speed),
    "stats box recomputed as drawStatsBox does, in the box's order")
  eq(last().interrupt, false, "queued behind the level-up line")
  local n = count()
  SR.update(screen)
  eq(count(), n, "said once")
end

-- ---------------------------------------------------------------- health

do
  local screen, player = fakeScreen()
  eq(Gen2Battle.health(screen, "enemy"), "Enemy health: 50.00 percent", "enemy health from the shown bar")
  eq(Gen2Battle.health(screen, "player"), "Player CYNDAQUIL, 20 of 35 HP", "player health from the shown HP")
  screen.shownStatus.player = "paralyze"
  player.status = nil
  eq(Gen2Battle.health(screen, "player"), "Player CYNDAQUIL, 20 of 35 HP, paralyzed", "shown status word")
  screen.showEnemyHud = false
  eq(Gen2Battle.health(screen, "enemy"), "No bar found", "no bar while the enemy HUD is down")
  eq(Gen2Battle.health({}, "enemy"), nil, "not a Gen 2 battle")
end

-- ---------------------------------------------------------------- real screen

local function stubGame(save)
  local pushed = {}
  return {
    data = DATA, save = save, input = Input, options = {},
    stack = {
      push = function(_, screen) pushed[#pushed + 1] = screen end,
      pop = function() table.remove(pushed) end,
      top = function() return pushed[#pushed] end,
    },
  }
end

local function detRandom(n)
  if (n or 1) <= 1 then return 0 end
  if n == 256 then return 128 end
  return 1
end

-- One frame: update, then the screen reader, as main.lua runs them.
local function frame(screen, press)
  if press then Input:overlayPressed(press) end
  Input:step()
  screen:update(1 / 60)
  if press then Input:overlayReleased(press) end
  SR.update(screen)
end

-- Runs frames, pressing A whenever a line holds for it, until `stop`.
local function drain(screen, stop, limit)
  for _ = 1, limit or 3000 do
    if stop(screen) then return true end
    local waiting = (screen.messageTimer or 0) > 0 or screen.phase == "stats-box"
    frame(screen, waiting and "a" or nil)
    if waiting then frame(screen) end
  end
  return stop(screen)
end

local function texts(from)
  local out = {}
  for i = from + 1, #spoken do out[#out + 1] = spoken[i].text end
  return out
end

do
  SR._resetForTests()
  Input:init()
  local player = Mon.new(DATA, "CYNDAQUIL", 30, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 }, { id = "GROWL", pp = 40, maxPp = 40 } }
  local wild = Mon.new(DATA, "PIDGEY", 2, { dvs = perfect })
  wild.moves = { { id = "GROWL", pp = 40, maxPp = 40 } }
  local save = { party = { player }, inventory = {}, player = { name = "GOLD" } }
  local game = stubGame(save)
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild, random = detRandom })
  local screen = BattleState.new(game, { battle = battle, save = save })
  local from = #spoken
  check(drain(screen, function(s) return s.phase == "menu" end), "the intro reaches the menu")
  local said = texts(from)
  eq(said[1], "Wild PIDGEY appeared!", "real screen: the wild intro line")
  eq(said[2], "Go! CYNDAQUIL!", "real screen: the send-out")
  check(said[3] and said[3]:find("^CYNDAQUIL, [mf]?[ae]?l?e?,? ?HP %d+ of %d+%. enemy PIDGEY") ~= nil,
    "real screen: the summary: " .. tostring(said[3]))
  check(said[3] and said[3]:find("HP 100 percent%. FIGHT$") ~= nil, "enemy at full HP before the first hit")

  -- FIGHT, then TACKLE: the turn's lines, each once
  from = #spoken
  frame(screen, "a")
  eq(screen.phase, "moves", "FIGHT opens the move list")
  eq(last().text, "TACKLE, NORMAL, PP 35 of 35, 1 of 2", "real screen: move list")
  frame(screen, "a")
  drain(screen, function(s) return s.phase == "menu" or (s.battle.over and s.phase ~= "resolving") end)
  said = texts(from)
  local joined = table.concat(said, " | ")
  check(joined:find("CYNDAQUIL used TACKLE!", 1, true) ~= nil, "real screen: the player's move: " .. joined)
  check(joined:find("Enemy PIDGEY fainted!", 1, true) ~= nil, "real screen: the faint line: " .. joined)
  check(joined:find("gained", 1, true) ~= nil, "real screen: the experience line: " .. joined)
  for i = 2, #said do
    check(said[i] ~= said[i - 1], "real screen: no line spoken twice in a row: " .. said[i])
  end
end

do
  SR._resetForTests()
  Input:init()
  local player = Mon.new(DATA, "CYNDAQUIL", 30, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local foe = Mon.new(DATA, "RATTATA", 3, { dvs = perfect })
  foe.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local save = { party = { player }, inventory = {}, player = { name = "GOLD" } }
  local game = stubGame(save)
  local battle = Battle.new({ data = DATA, party = { player }, random = detRandom,
    trainer = { class = "YOUNGSTER", name = "YOUNGSTER JOEY", party = { foe } } })
  local screen = BattleState.new(game, { battle = battle, save = save })
  local from = #spoken
  check(drain(screen, function(s) return s.phase == "menu" end), "the trainer intro reaches the menu")
  local said = texts(from)
  eq(said[1], "YOUNGSTER JOEY wants to battle!", "real screen: trainer intro")
  eq(said[2], "YOUNGSTER JOEY sent out", "real screen: send-out first page")
  eq(said[3], "RATTATA!", "real screen: the carried row is dropped on the scroll page")
  eq(said[4], "Go! CYNDAQUIL!", "real screen: the player's send-out")
end

Speech.shutdown()
T.finish("gen2 battle")
