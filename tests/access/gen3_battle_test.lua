-- Gen 3 battle speech (decision 29): src/access/screens/gen3/Battle.lua.
--
-- Runs on the real upstream modules: the battle module and its UI
-- (src/core/game3/battle, battle/ui.lua), the message box, YES/NO, the
-- level-up window, Anim's shown values and the healthbox's status rule,
-- found through the real gen3/Top.lua and ScreenReader.  The battle state
-- and the UI fields are set by hand, so each rule is checked on its own.
-- Only the ROM-backed lookups (move rows, type and species names, battle
-- strings) are fakes, so the suite needs no imported cartridge.  The last
-- part drives the real Ui message queue many logic steps between two polls,
-- as GAME SPEED 200X does.
--
--   luajit tests/access/gen3_battle_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Speech = require("src.access.Speech")
local SR = require("src.access.screens.ScreenReader")
local Presenters = require("src.access.screens.Presenters")
local CurrentGame = require("src.access.CurrentGame")
local Top = require("src.access.screens.gen3.Top")
local Gen3Battle = require("src.access.screens.gen3.Battle")

local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")
local Anim = require("src.core.game3.battle.anim")
local Message = require("src.ui.game3.message")
local Choice = require("src.ui.game3.choice")
local StatGrowth = require("src.ui.game3.stat_growth")
local Stack = require("src.ui.game3.stack")
require("src.core.game3.battle.healthbox")
require("src.core.game3.battle.state")

-- ROM-backed lookups replaced for the presenter (it finds them in
-- package.loaded); upstream modules that captured the real ones keep them.
local MOVES = {
  [10] = { name = "SCRATCH", type = 0, pp = 35 },
  [45] = { name = "GROWL", type = 0, pp = 40 },
  [52] = { name = "EMBER", type = 10, pp = 25 },
  [174] = { name = "CURSE", type = 9, pp = 10 },
}
local TYPES = { [0] = "NORMAL", [9] = "???", [10] = "FIRE" }
package.loaded["src.core.game3.battle.moves"] = {
  displayName = function(id) return assert(MOVES[id], "move " .. tostring(id)).name end,
  get = function(id) return assert(MOVES[id], "move " .. tostring(id)) end,
}
package.loaded["src.core.game3.battle.types"] = { name = function(id) return assert(TYPES[id]) end }
local SPECIES = { [4] = "CHARMANDER", [16] = "PIDGEY", [19] = "RATTATA", [92] = "GASTLY" }
local realPokemon = require("src.core.game3.pokemon")
package.loaded["src.core.game3.pokemon"] = setmetatable({
  name = function(species) return assert(SPECIES[species], "species " .. tostring(species)) end,
  gender = function() return "M" end,
}, { __index = realPokemon })
local promptCalls = 0
package.loaded["src.core.game3.battle.battle_text"] = {
  get = function(key, fill)
    promptCalls = promptCalls + 1
    if key == "gText_WhatWillPkmnDo" then
      return "What will\n" .. (fill.active.mon.nickname or "?") .. " do?"
    elseif key == "gText_WhatWillOldManDo" then
      return "What will\nOLD MAN do?"
    end
    return "What will\n" .. tostring(fill and fill.playerName) .. " throw?"
  end,
}
package.loaded["src.core.game3.rom_text"] = setmetatable({
  plain = function(key)
    local fixed = { gText_BattleSwitchWhich = "SWITCH\nWHICH?", gText_Ghost = "GHOST",
      gText_SafariBalls = "SAFARI BALLS" }
    return assert(fixed[key], "rom text " .. tostring(key))
  end,
}, { __index = require("src.core.game3.rom_text") })

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
local function since(n)
  local out = {}
  for i = n + 1, #spoken do out[#out + 1] = spoken[i].text end
  return out
end

-- ---------------------------------------------------------------- fixtures

local game = { generation = 3, phase = "field", options = {} }
CurrentGame.set(game)

local function battler(side, mon, extra)
  if mon.isShiny == nil then mon.isShiny = false end
  local b = { side = side, mon = mon, species = mon.species, status = false }
  for k, v in pairs(extra or {}) do b[k] = v end
  return b
end

-- A battle as Battle.start leaves it, plus the shown copies the healthbox
-- draws.  Returns the state.
local function startBattle(opts)
  opts = opts or {}
  Stack.clear()
  Message.reset()
  Choice.reset()
  StatGrowth.close({ silent = true })
  Ui.reset()
  Anim.reset({ headless = false, double = opts.double })
  local player = opts.player or { species = 4, nickname = "CHARMANDER", level = 12, hp = 20, maxHp = 35,
    gender = "M", personality = 0x1234, otId = 0x99990000,
    moves = { 10, 45, 52, 0 }, pp = { 30, 40, 25, 0 }, maxPp = { 35, 40, 25, 0 } }
  local enemy = opts.enemy or { species = 16, nickname = "PIDGEY", level = 4, hp = 9, maxHp = 18,
    gender = "F", personality = 0, otId = 0 }
  local st = {
    wild = opts.wild ~= false, double = opts.double or nil, turn = 1,
    player = battler("player", player), enemy = battler("enemy", enemy),
    safari = opts.safari, safariState = opts.safari and { balls = 30 } or nil,
    oldManTutorial = opts.oldManTutorial, ghostBattle = opts.ghostBattle,
    absent = {},
  }
  st.battlers = { [0] = st.player, [1] = st.enemy }
  for id, mon in pairs(opts.extra or {}) do
    st.battlers[id] = battler(id % 2 == 0 and "player" or "enemy", mon)
  end
  Ui.bindState(st)
  for id = 0, (opts.double and 3 or 1) do
    local b = st.battlers[id]
    local p = rawget(Anim._present, id) or {}
    rawset(Anim._present, id, p)
    p.displayHp, p.displayMaxHp = b.mon.hp, b.mon.maxHp
    p.displayLevel, p.displayStatus = b.mon.level, false
    Anim._stage.healthbox[id].visible = true
  end
  Battle._st, Battle._active, Battle._phase = st, true, "intro"
  return st
end

local function endBattle()
  Battle._active, Battle._st = false, nil
  Message.reset()
  Choice.reset()
  SR.update()
end

-- Shows a battle line the way show_next does.
local function show(text, stay)
  Message.show(text, { frame = "battle", battle = true, stay = stay })
end

local function openMenu(index)
  Message.reset()
  Battle._phase = "command"
  Ui._mode = "menu"
  Ui._menuIndex = index or 1
end

-- ---------------------------------------------------------------- matching

do
  local st = startBattle()
  local top = Top.resolve(game)
  check(top and top.gen3 == "battle" and top.key == st, "Top reports the battle")
  check(Presenters.find(top) == Gen3Battle.presenter, "the battle presenter matches it")
  check(Gen3Battle._recorder.module == Message, "matching installs the Message.show recorder")
  check(not Gen3Battle.presenter.matches({ gen3 = "message", key = {} }), "a field message is not the battle")
  check(not Gen3Battle.presenter.matches({ gen3 = "battle", key = st, mod = {} }),
    "a battle proxy for another module is not matched")
  endBattle()
end

-- ---------------------------------------------------------------- messages

do
  startBattle()
  SR.update()
  local n = count()
  show("Wild PIDGEY appeared!\\p")
  SR.update()
  eq(last().text, "Wild PIDGEY appeared!", "the intro line")
  eq(last().interrupt, false, "battle lines queue")
  SR.update()
  eq(count(), n + 1, "an unchanged box says nothing")
  show("Go! CHARMANDER!", true)
  SR.update()
  eq(last().text, "Go! CHARMANDER!", "the send-out")
  show("A critical hit!", true)
  SR.update()
  show("A critical hit!", true)
  SR.update()
  eq(spoken[#spoken - 1].text, "A critical hit!", "the first critical hit")
  eq(last().text, "A critical hit!", "the same line shown again is said again")

  -- a two-page line is said page by page as the game shows it
  n = count()
  show("CHARMANDER is trying to\nlearn EMBER.\\pBut CHARMANDER can't learn\nmore than four moves.\\p")
  SR.update()
  eq(last().text, "CHARMANDER is trying to learn EMBER.", "page 1 of a long line")
  SR.update()
  eq(count(), n + 1, "page 2 waits for the game")
  Message.skipReveal()
  Message.advance()
  SR.update()
  eq(last().text, "But CHARMANDER can't learn more than four moves.", "page 2 once shown")

  -- a word split across two pages is finished on the first
  show("Many wild\ncrea-\\ptures hide in grass.\\p")
  SR.update()
  eq(last().text, "Many wild creatures hide in grass.", "a split word joined across the page break")
  n = count()
  Message.skipReveal()
  Message.advance()
  SR.update()
  eq(count(), n, "the continued line is not said twice")

  -- ALL AT ONCE says the whole box when it opens
  -- Gen 3 keeps the setting in the game's own options block (Settings.lua)
  game.options.firered = { accessDialogue = "whole" }
  show("Page one.\\pPage two.\\p")
  SR.update()
  eq(last().text, "Page one. Page two.", "ALL AT ONCE: every page at once")
  n = count()
  Message.skipReveal()
  Message.advance()
  SR.update()
  eq(count(), n, "ALL AT ONCE: page 2 not repeated")
  game.options.firered = nil

  -- the voiceover frame (Oak's advice) is battle text too
  Message.show("Inflicting damage on the foe\nis the key to any battle.\\p", { frame = "voiceover", hold = true })
  SR.update()
  eq(last().text, "Inflicting damage on the foe is the key to any battle.", "Oak's voiceover")
  endBattle()
end

-- ---------------------------------------------------------------- the menu

do
  local st = startBattle()
  SR.update()
  Ui._promptFor = { st = st, mode = "pkmn", mon = st.player.mon }
  Ui._promptText = "What will\nCHARMANDER do?"
  show("Enemy PIDGEY used\nTACKLE!", true)
  SR.update()
  local n = count()
  openMenu(1)
  SR.update()
  eq(last().text, "CHARMANDER, male, HP 20 of 35. enemy PIDGEY, level 4, female, HP 50 percent. "
    .. "What will CHARMANDER do? FIGHT", "menu opening: both sides, the prompt, the command")
  eq(last().interrupt, false, "the menu summary queues behind the last line")
  eq(count(), n + 1, "one utterance")
  Ui._menuIndex = 2
  SR.update()
  eq(last().text, "BAG", "BAG to the right")
  eq(last().interrupt, true, "cursor moves interrupt")
  Ui._menuIndex = 3
  SR.update()
  eq(last().text, "POKéMON", "the POKéMON ligature")
  Ui._menuIndex = 4
  SR.update()
  eq(last().text, "RUN", "RUN")

  -- the next turn: shown values, status, no repeated gender
  Ui._mode = "none"
  Battle._phase = "actions"
  SR.update()
  st.turn = 2
  rawget(Anim._present, 0).displayHp = 12.6
  rawget(Anim._present, 0).displayStatus = "PSN"
  rawget(Anim._present, 1).displayHp = 1
  rawget(Anim._present, 1).displayStatus = 0x40
  st.player.mon.hp = 3 -- logical HP ahead of the healthbox: not read
  openMenu(1)
  SR.update()
  eq(last().text, "CHARMANDER, HP 12 of 35, PSN. enemy PIDGEY, level 4, HP 6 percent, PAR. "
    .. "What will CHARMANDER do? FIGHT", "turn 2: shown HP and status tags, gender said once")

  -- a refused choice returns to the menu in the same turn: no summary again
  Ui._mode = "selmsg"
  show("No! There's no running\nfrom a TRAINER battle!\\p")
  SR.update()
  Ui._mode = "menu"
  Ui._menuIndex = 4
  SR.update()
  eq(last().text, "What will CHARMANDER do? RUN", "same turn: the prompt and command only")
  eq(last().interrupt, true, "a menu reopened by a press interrupts")

  -- a return from the bag (a stack layer) repeats every side
  local bagMod = {}
  Stack.push("bag", bagMod, { hideBelow = true })
  Ui._mode = "bag"
  SR.update()
  Stack.pop("bag")
  Ui._mode = "menu"
  Ui._menuIndex = 2
  SR.update()
  check(last().text:find("^CHARMANDER, HP 12 of 35, PSN%. enemy PIDGEY") ~= nil
    and last().text:find("BAG$") ~= nil, "a return from the bag repeats the sides")

  -- unreadable prompt: silent, never invented
  Ui._promptFor = nil
  local saved = package.loaded["src.core.game3.battle.battle_text"]
  package.loaded["src.core.game3.battle.battle_text"] = nil
  Ui._mode = "none"
  SR.update()
  st.turn = 3
  openMenu(1)
  SR.update()
  check(last().text:find("What will") == nil and last().text:find("FIGHT$") ~= nil,
    "no prompt when the ROM string cannot be read")
  package.loaded["src.core.game3.battle.battle_text"] = saved

  -- the prompt for another Pokémon is built from the same ROM string
  Ui._mode = "none"
  SR.update()
  st.turn = 4
  local before = promptCalls
  openMenu(1)
  SR.update()
  check(promptCalls > before and last().text:find("What will CHARMANDER do%? FIGHT$") ~= nil,
    "the prompt is built when the draw has not cached it yet")
  endBattle()
end

-- ---------------------------------------------------------------- moves

do
  local st = startBattle()
  SR.update()
  openMenu(1)
  SR.update()
  Ui._mode = "moves"
  Ui._moveIndex = 1
  SR.update()
  eq(last().text, "SCRATCH, NORMAL, PP 30 of 35, 1 of 3", "move menu opening: name, type, PP, position")
  eq(last().interrupt, true, "the move list interrupts")
  Ui._moveIndex = 3
  SR.update()
  eq(last().text, "EMBER, FIRE, PP 25 of 25", "EMBER")
  -- PP the game does not hold is unknown, never 0; max PP falls back to the move's
  st.player.mon.pp = nil
  st.player.mon.maxPp = nil
  Ui._moveIndex = 2
  SR.update()
  eq(last().text, "GROWL, NORMAL", "missing PP left out")
  st.player.mon.pp = { 30, 40, 25, 0 }
  Ui._moveIndex = 1
  SR.update()
  eq(last().text, "SCRATCH, NORMAL, PP 30 of 35", "max PP from the move row when the mon has none")
  -- CURSE's ??? type
  st.player.mon.moves[4], st.player.mon.pp[4] = 174, 10
  Ui._moveIndex = 4
  SR.update()
  eq(last().text, "CURSE, question marks, PP 10 of 10", "the ??? type")

  -- SELECT swap: SWITCH WHICH?, the second cursor, then swapped / cancelled
  Ui._moveIndex = 1
  SR.update()
  Ui._swap = { cursor = 0 }
  SR.update()
  eq(last().text, "SWITCH WHICH? SCRATCH", "swap starts on the box's prompt")
  Ui._swap.cursor = 1
  SR.update()
  eq(last().text, "GROWL", "the second cursor says its move")
  local mon = st.player.mon
  mon.moves[1], mon.moves[2] = mon.moves[2], mon.moves[1]
  mon.pp[1], mon.pp[2] = mon.pp[2], mon.pp[1]
  Ui._swap, Ui._moveIndex = nil, 2
  SR.update()
  eq(last().text, "swapped, SCRATCH, NORMAL, PP 30 of 35", "swapped")
  Ui._swap = { cursor = 1 }
  SR.update()
  Ui._swap = nil
  SR.update()
  eq(last().text, "swap cancelled", "B cancels the swap")

  -- a refused move ("No PP left!") returns to the list with its position
  Ui._mode = "selmsg"
  show("There's no PP left for\nthis move!\\p")
  SR.update()
  Ui._mode = "moves"
  SR.update()
  eq(last().text, "SCRATCH, NORMAL, PP 30 of 35, 2 of 4", "back in the list after a refusal")
  endBattle()
end

-- ---------------------------------------------------------------- YES / NO

do
  startBattle()
  SR.update()
  Battle._phase = "catch_nickname_prompt"
  show("Give a nickname to the\ncaptured PIDGEY?", true)
  Choice.active, Choice.kind, Choice.options, Choice.cursor = true, "yesno", { "YES", "NO" }, 1
  Choice.done, Choice.style = function() end, "battle"
  local n = count()
  SR.update()
  eq(since(n)[1], "Give a nickname to the captured PIDGEY? YES", "the question, then YES")
  eq(last().interrupt, false, "the first selection queues")
  Choice.cursor = 2
  SR.update()
  eq(last().text, "NO", "NO")
  eq(last().interrupt, true, "moving interrupts")
  Choice.reset()
  -- the shift offer: the question was a message closed by A, then YES/NO alone
  Battle._phase = "shift_prompt"
  show("BUG CATCHER is about to use\nWEEDLE.\\pWill RED change\nPOKéMON?\\p")
  SR.update()
  Message.close()
  Choice.active, Choice.kind, Choice.options, Choice.cursor = true, "yesno", { "YES", "NO" }, 1
  Choice.done = function() end
  SR.update()
  eq(last().text, "YES", "the shift offer's YES")
  Choice.reset()
  endBattle()
end

-- ---------------------------------------------------------------- level up

do
  startBattle()
  SR.update()
  Battle._phase = "awarding"
  show("CHARMANDER grew to\nLV. 13!\\p")
  local mon = { species = 4, nickname = "CHARMANDER", level = 13 }
  StatGrowth.open(mon, { maxHp = 35, atk = 20, def = 18, spa = 22, spd = 19, spe = 23 },
    { maxHp = 38, atk = 22, def = 19, spa = 24, spd = 20, spe = 25 })
  local n = count()
  SR.update()
  eq(since(n)[1], "CHARMANDER grew to level 13! CHARMANDER, level 13 stat increases: max HP plus 3, "
    .. "attack plus 2, defense plus 1, special attack plus 2, special defense plus 1, speed plus 2",
    "level-up window page 1 behind its line")
  eq(last().interrupt, false, "page 1 queues")
  StatGrowth._page = 2
  SR.update()
  eq(last().text, "CHARMANDER, level 13 stats: max HP 38, attack 22, defense 19, special attack 24, "
    .. "special defense 20, speed 25", "page 2: the totals")
  eq(last().interrupt, true, "turning the page interrupts page 1")
  n = count()
  Battle._phase = "command" -- the window only shows while it can be dismissed
  StatGrowth._page = 1
  SR.update()
  eq(count(), n, "no window outside its phases")
  StatGrowth.close({ silent = true })
  endBattle()
end

-- ---------------------------------------------------------------- variants

do -- Safari Zone: the enemy only, BALL with the count, the throw prompt
  local st = startBattle({ safari = true })
  SR.update()
  Ui._promptFor = { st = st, mode = "safari", mon = st.player.mon }
  Ui._promptText = "What will\nRED throw?"
  openMenu(1)
  SR.update()
  eq(last().text, "enemy PIDGEY, level 4, female, HP 50 percent. What will RED throw? BALL, 30 left",
    "Safari menu")
  Ui._menuIndex = 3
  SR.update()
  eq(last().text, "ROCK", "Safari ROCK")
  eq(Gen3Battle.health(nil, "player"), "SAFARI BALLS, 30 left", "Shift+H in the Safari Zone")
  endBattle()
end

do -- the old man's demo: only the prompt, his scripted cursor stays quiet
  local st = startBattle({ oldManTutorial = true })
  SR.update()
  Ui._promptFor = { st = st, mode = "oldman", mon = st.player.mon }
  Ui._promptText = "What will\nOLD MAN do?"
  openMenu(1)
  SR.update()
  eq(last().text, "What will OLD MAN do?", "old man: the prompt")
  local n = count()
  Ui._menuIndex = 2
  SR.update()
  eq(count(), n, "old man: his cursor move to BAG is not said")
  endBattle()
end

do -- a Pokémon Tower ghost: GHOST, no gender, until unveiled
  startBattle({ ghostBattle = true,
    enemy = { species = 92, nickname = "GHOST", level = 18, hp = 30, maxHp = 30, gender = "F" } })
  SR.update()
  openMenu(1)
  SR.update()
  check(last().text:find("enemy GHOST, level 18, HP 100 percent", 1, true) ~= nil, "the ghost is GHOST, no gender")
  endBattle()
end

do -- shiny and the caught marker, said the first time only
  local st = startBattle({
    enemy = { species = 19, nickname = "RATTATA", level = 3, hp = 12, maxHp = 12, gender = "M",
      isShiny = true } })
  st.enemy._caughtIcon = { mon = st.enemy.mon, show = true }
  SR.update()
  openMenu(1)
  SR.update()
  check(last().text:find("enemy RATTATA, shiny, owned, level 3, male, HP 100 percent", 1, true) ~= nil,
    "shiny and owned on first summary")
  Ui._mode = "none"
  SR.update()
  st.turn = 2
  openMenu(1)
  SR.update()
  check(last().text:find("enemy RATTATA, level 3, HP 100 percent", 1, true) ~= nil, "not repeated next turn")
  endBattle()
end

do -- a hidden healthbox is not read; the status HUD seam hides all
  startBattle()
  Anim._stage.healthbox[1].visible = false
  SR.update()
  openMenu(1)
  SR.update()
  check(last().text:find("enemy") == nil and last().text:find("^CHARMANDER") ~= nil,
    "a healthbox off screen is left out")
  eq(Gen3Battle.health(nil, "enemy"), "No bar found", "H with the enemy box hidden")
  endBattle()
end

-- ---------------------------------------------------------------- doubles

do
  local st = startBattle({ double = true, wild = false, extra = {
    [2] = { species = 7, nickname = "SQUIRTLE", level = 11, hp = 30, maxHp = 31, gender = "F",
      moves = { 33, 0, 0, 0 }, pp = { 35 } },
    [3] = { species = 19, nickname = "RATTATA", level = 10, hp = 10, maxHp = 25, gender = "M" } } })
  MOVES[33] = { name = "TACKLE", type = 0, pp = 35 }
  SR.update()
  Ui._promptFor = nil
  openMenu(1)
  Ui._active = 0
  SR.update()
  eq(last().text, "CHARMANDER, male, HP 20 of 35. SQUIRTLE, female, HP 30 of 31. "
    .. "enemy PIDGEY, level 4, female, HP 50 percent. enemy RATTATA, level 10, male, HP 40 percent. "
    .. "What will CHARMANDER do? FIGHT", "doubles: four sides, then the first battler's prompt")
  -- the second battler's menu in the same turn: its prompt only
  Ui._mode = "none"
  SR.update()
  openMenu(1)
  Ui._active = 2
  SR.update()
  eq(last().text, "What will SQUIRTLE do? FIGHT", "doubles: the partner's prompt")
  -- B on the partner's menu goes back to the first battler
  Ui._active = 0
  SR.update()
  eq(last().text, "What will CHARMANDER do? FIGHT", "doubles: B back to the first battler")
  eq(last().interrupt, true, "the reopened menu interrupts")
  Ui._active = 2
  SR.update()
  -- its moves, then the target cursor
  Ui._mode = "moves"
  Ui._moveIndex = 1
  SR.update()
  eq(last().text, "TACKLE, NORMAL, PP 35 of 35, 1 of 1", "doubles: the partner's moves")
  Ui._mode = "target"
  Ui._target = { battler = 2, slot = 1, cursor = 1 }
  SR.update()
  eq(last().text, "enemy PIDGEY, HP 50 percent", "target: the enemy under the cursor")
  Ui._target.cursor = 3
  SR.update()
  eq(last().text, "enemy RATTATA, HP 40 percent", "target moves")
  Ui._target.cursor = 0
  SR.update()
  eq(last().text, "CHARMANDER, HP 20 of 35", "target: your own side")
  eq(Gen3Battle.health(nil, "enemy"), "Enemy health: PIDGEY 50.00 percent; RATTATA 40.00 percent",
    "H in a double battle names both")
  eq(Gen3Battle.health(nil, "player"), "Player CHARMANDER, 20 of 35 HP; SQUIRTLE, 30 of 31 HP",
    "Shift+H in a double battle names both")
  endBattle()
end

-- ---------------------------------------------------------------- health

do
  check(Gen3Battle.health(nil, "enemy") == nil, "no battle: nil, so the caller says not in battle")
  local st = startBattle()
  eq(Gen3Battle.health(nil, "enemy"), "Enemy health: 50.00 percent", "H: the Gen 2 words")
  eq(Gen3Battle.health(nil, "player"), "Player CHARMANDER, 20 of 35 HP", "Shift+H: the Gen 2 words")
  rawget(Anim._present, 0).displayHp = 7
  rawget(Anim._present, 0).displayStatus = 0x03
  eq(Gen3Battle.health(nil, "player"), "Player CHARMANDER, 7 of 35 HP, asleep", "shown HP and status word")
  rawget(Anim._present, 1).shown = battler("enemy", { species = 19, nickname = "RATTATA", hp = 5, maxHp = 20 })
  rawget(Anim._present, 1).displayHp, rawget(Anim._present, 1).displayMaxHp = 5, 20
  eq(Gen3Battle.health(nil, "enemy"), "Enemy health: 25.00 percent", "the Pokémon the healthbox shows")
  local proxy = Top.resolve(game)
  eq(Gen3Battle.health(proxy, "enemy"), "Enemy health: 25.00 percent", "with the battle proxy")
  check(Gen3Battle.health({ gen3 = "battle", key = {}, mod = Battle }, "enemy") == nil, "a stale proxy")
  check(rawget(Anim._present, 2) == nil, "reading never creates Anim entries")
  local _ = st
  endBattle()
end

-- ---------------------------------------------------------------- fast speed

do
  -- Lines shown and replaced between two polls (several logic steps per
  -- frame) are said from the recorder, in order, each once.
  startBattle()
  SR.update()
  local n = count()
  show("Go! CHARMANDER!", true)
  show("CHARMANDER used\nSCRATCH!", true)
  show("Enemy PIDGEY used\nTACKLE!", true)
  SR.update()
  local said = since(n)
  eq(said[1], "Go! CHARMANDER! CHARMANDER used SCRATCH! Enemy PIDGEY used TACKLE!",
    "three lines between two polls, in order")
  eq(#said, 1, "one utterance")
  SR.update()
  eq(count(), n + 1, "none repeated")

  -- the page a replaced line reached, not more
  n = count()
  show("One.\\pTwo.\\pThree.\\p")
  SR.update()
  Message.skipReveal()
  Message.advance()
  show("Next line.", true)
  SR.update()
  eq(since(n)[1], "One.", "page 1 seen")
  eq(since(n)[2], "Two. Next line.", "the page it reached, then the next line; page 3 never shown")

  -- a line shown while a stack layer is open belongs to that layer
  n = count()
  Stack.push("party", {}, { hideBelow = true })
  show("Do what with this POKéMON?", true)
  Stack.pop("party")
  Message.close()
  SR.update()
  eq(count(), n, "a covered line is not said by the battle")
  endBattle()
end

do
  -- The real Ui queue at 200X: self-advancing lines (pushTimed 0 and 64)
  -- run many logic steps between two polls.
  local st = startBattle()
  SR.update()
  Ui.bindState(st)
  local lines = { "Go! CHARMANDER!", "CHARMANDER used\nSCRATCH!", "It's super effective!",
    "Enemy PIDGEY used\nGUST!", "PIDGEY's attack missed!" }
  Ui.pushTimed(lines[1], 0)
  Ui.pushTimed(lines[2], 0)
  Ui.pushTimed(lines[3], 64)
  Ui.pushTimed(lines[4], 0)
  Ui.pushTimed(lines[5], 64)
  local n = count()
  local polls = 0
  for step = 1, 3000 do
    Ui.pump()
    Message.tick()
    if step % 200 == 0 then
      SR.update()
      polls = polls + 1
    end
    if #Ui._queue == 0 and not Ui._timed then break end
  end
  SR.update()
  local all = table.concat(since(n), " ")
  check(polls <= 3, "the lines ran in at most a few polls (" .. polls .. ")")
  eq(all, "Go! CHARMANDER! CHARMANDER used SCRATCH! It's super effective! Enemy PIDGEY used GUST! "
    .. "PIDGEY's attack missed!", "200X: every self-advancing line said once, in order")

  -- the recorder calls the original unchanged
  local result = Message.show("Plain.", { frame = "battle" })
  check(result == Message, "Message.show still returns the module")
  check(Message.open == true and Message.currentPage() == "Plain.", "the box shows the line")
  Message.close()
  check(Message.open == false and Message._pages == nil, "Message.close still closes")
  endBattle()
end

Speech.shutdown()
T.finish("gen3 battle")
