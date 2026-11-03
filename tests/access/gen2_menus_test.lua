-- Gen 2 menu presenters (decision 27): boot cards, title, main menu, clock
-- setting, gender, name choice, naming keyboard, start menu, OPTION, SAVE,
-- script menus, elevator, Bank of Mom, evolution and egg hatching.
-- States are built with the real upstream classes (their constructors where
-- they are light, else bare tables with the real metatable), and driven by
-- setting fields or calling the screen's own methods the way its update
-- would.  Speech goes to a fake backend through the real ScreenReader.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Speech = require("src.access.Speech")
local SR = require("src.access.screens.ScreenReader")
local GameVersion = require("src.core.GameVersion")

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
local function gen2(name) return require("src.ui.gen2." .. name) end
local function as(name, fields) return setmetatable(fields, gen2(name)) end

local save = {
  version = "crystal",
  player = { name = "KRIS", money = 3000, coins = 120, badges = { ZEPHYR = true }, kantoBadges = {} },
  pokedex = { caught = { CYNDAQUIL = true, SENTRET = true } },
  playTime = { hours = 3, minutes = 7 },
  options = {},
}
local game = { data = {}, save = save, options = {} }

GameVersion.set("crystal")

-- ---------------------------------------------------------------- boot
reset()
local copyright = as("CopyrightSplash", { frames = 0 })
SR.update(copyright)
eq(last(), "Copyright Nintendo, Creatures inc., GAME FREAK inc.", "copyright card (image only)")
eq(lastInterrupt(), false, "boot lines queue")
SR.update(copyright)
eq(count(), 1, "copyright said once")
reset()
SR.update(as("CopyrightSplash", { lines = { "©1995 Nintendo", "©1995 GAME FREAK" } }))
eq(last(), "©1995 Nintendo ©1995 GAME FREAK", "copyright fallback lines are read when drawn")

reset()
SR.update(as("CrystalSplash", { scene = 0 }))
eq(last(), "GAME FREAK presents.", "Crystal splash")
reset()
SR.update(as("GameFreakPresents", { scene = 0 }))
eq(last(), "GAME FREAK presents.", "Gold and Silver splash")
reset()
SR.update(as("CrystalIntro", { scene = 1 }))
eq(last(), "Intro. Press start to skip.", "Crystal intro")
reset()
SR.update(as("GoldSilverIntro", { scene = 1 }))
eq(last(), "Intro. Press start to skip.", "Gold and Silver intro")

reset()
local title = as("TitleState", { entranceScx = 8 })
SR.update(title)
eq(count(), 0, "title waits for the entrance to land")
title.entranceScx = 0
SR.update(title)
eq(last(), "POKéMON Crystal Version. Copyright GAME FREAK inc. Press start.", "title names the running edition")
eq(lastInterrupt(), false, "title line queues behind the intro")
GameVersion.set("silver")
reset()
SR.update(as("TitleState", { entranceScx = 0 }))
eq(last(), "POKéMON Silver Version. Copyright GAME FREAK inc. Press start.", "Silver title")
GameVersion.set("crystal")
reset()
SR.update(as("TitleState", { entranceScx = 0, fadeStart = 10 }))
eq(count(), 0, "a title fading out on timeout says nothing")

-- ---------------------------------------------------------------- main menu
reset()
local MainMenu = gen2("MainMenu")
local main = MainMenu.new(game, { save = save, clock = { hour = 10, minute = 5, weekday = 1 } })
SR.update(main)
eq(last(), "Main menu. CONTINUE, 1 of 4. SUNDAY DAY 10:05", "main menu entry with the clock box")
main.list.index = 2
SR.update(main)
eq(last(), "NEW GAME", "main menu move")
main.list.index = 1
SR.update(main)
main.phase = "confirm"
SR.update(main)
eq(last(), "KRIS, badges 1, POKéDEX 2, time 3:07. A to continue, B to go back", "CONTINUE save panel")
main.phase = "menu"
SR.update(main)
eq(last(), "CONTINUE, 1 of 4", "back from the panel says the row and position")
reset()
SR.update(MainMenu.new(game, { save = nil, hasSave = false }))
eq(last(), "Main menu. NEW GAME, 1 of 3", "no save: no clock, no CONTINUE")

-- ---------------------------------------------------------------- clock setting
reset()
local InitClock = gen2("InitClock")
local clock = InitClock.new(game, { mode = "clock" })
SR.update(clock)
eq(last(), "Zzz... Hm? Wha...? You woke me up!", "Oak's first page")
clock:accept() -- second page of the same question
SR.update(clock)
eq(last(), "Will you check the clock for me?", "second page only")
clock:accept() -- the hour picker
SR.update(clock)
eq(last(), "What time is it? DAY 10 o'clock", "question and picker value (10 is DAY on the cart's ladder)")
clock:step(1)
SR.update(clock)
eq(last(), "DAY 11 o'clock", "value change says the value")
eq(lastInterrupt(), true, "value change interrupts")
clock:accept() -- confirm the hour
SR.update(clock)
eq(last(), "What? DAY 11 o'clock? YES", "confirmation with YES/NO")
clock.yesNo = 2
SR.update(clock)
eq(last(), "NO", "YES/NO toggle")
clock:decline()
clock.yesNo = 1
SR.update(clock)
eq(last(), "What time is it? DAY 11 o'clock", "NO goes back and repeats the question")
clock:accept() clock:accept() -- confirm-hour, then YES: minutes
SR.update(clock)
eq(last(), "How many minutes? 0 min.", "minute picker")
clock.hour = 13
clock:accept() clock:accept() -- confirm-minute, YES: response
SR.update(clock)
eq(last(), "DAY 1:00! Yikes! I overslept!", "word split across the scroll is finished in one chunk")
local before = count()
clock:accept() -- a second page would only repeat lines already spoken
SR.update(clock)
eq(count(), before, "scrolled page with nothing new stays quiet")

reset()
local wheel = InitClock.new(game, { mode = "day" })
SR.update(wheel)
eq(last(), "What day is it? SUNDAY", "Mom's day wheel")
wheel:step(1)
SR.update(wheel)
eq(last(), "MONDAY", "day change")
wheel:accept()
SR.update(wheel)
eq(last(), "MONDAY, is that right? YES", "day confirmation")

reset()
local fading = InitClock.new(game, { mode = "clock" })
fading.blank = true
SR.update(fading)
eq(count(), 0, "nothing while the screen is blank")

-- ---------------------------------------------------------------- gender
reset()
local gender = gen2("GenderSelect").new(game, {})
SR.update(gender)
eq(last(), "Are you a boy? Or are you a girl?", "gender question")
gender.typer.shown = gender.typer.total
gender.menuWait = 0
SR.update(gender)
eq(last(), "Boy, 1 of 2", "menu opens on Boy")
eq(lastInterrupt(), false, "menu queues behind the question")
gender.cursor = 2
SR.update(gender)
eq(last(), "Girl", "gender move")
gender.chosen = "female"
gender.cursor = 1
before = count()
SR.update(gender)
eq(count(), before, "quiet once chosen")

-- ---------------------------------------------------------------- name choice
reset()
local pick = gen2("NamePick").new(game, { presets = { "KRIS", "AMANDA", "JUANA", "JODI" } })
SR.update(pick)
eq(count(), 0, "name menu waits for the picture to slide in")
pick.slide = nil
SR.update(pick)
eq(last(), "Name. NEW NAME, 1 of 5", "name menu entry")
pick.cursor = 3
SR.update(pick)
eq(last(), "AMANDA", "preset name")

-- ---------------------------------------------------------------- naming keyboard
reset()
local naming = gen2("NamingScreen").new(game, { type = "player" })
SR.update(naming)
eq(last(), "YOUR NAME? empty. A", "naming entry, 0-based cursor")
naming.col = 1
SR.update(naming)
eq(last(), "B", "cell")
naming.text = "B"
SR.update(naming)
eq(last(), "B, B", "typed letter and name")
naming.row, naming.col = 3, 0
SR.update(naming)
eq(last(), "dash", "symbol spelled out")
naming.row, naming.col = 2, 8
SR.update(naming)
eq(last(), "space", "a blank cell types a space")
naming.row, naming.col = 4, 0
SR.update(naming)
eq(last(), "lower case", "case target names the board it switches to")
naming.lower = true
SR.update(naming)
eq(last(), "lower case. UPPER CASE", "case switch")
naming.col = 3
SR.update(naming)
eq(last(), "delete", "delete target")
naming.col = 6
SR.update(naming)
eq(last(), "end, confirm name", "end target")
naming.row, naming.col = 3, 7
SR.update(naming)
eq(last(), "PK", "PK glyph")
naming.text = "B<PK>"
SR.update(naming)
eq(last(), "PK, BPK", "typed glyph")
naming.text = "B"
SR.update(naming)
eq(last(), "deleted, B", "delete announced")
naming.text = "B\xc3\xa9"
SR.update(naming)
eq(last(), "e acute, Bé", "typed é")
naming.text = "B\xc3" -- the screen deletes one byte, leaving half of é
SR.update(naming)
eq(last(), "deleted, B", "a broken character is left out of speech")
reset()
SR.update(gen2("NamingScreen").new(game, { type = "nickname", monName = "TOTODILE" }))
eq(last(), "TOTODILE, NICKNAME? empty. A", "nickname prompt names the POKéMON")

-- ---------------------------------------------------------------- start menu
reset()
local StartMenu = gen2("StartMenu")
StartMenu.lastIndex = 1
save.options.menuAccount = true
local start = StartMenu.new(game, { save = save,
  unlocked = { pokedex = true, party = true, pack = true, pokegear = true } })
SR.update(start)
eq(last(), "Start menu. POKéDEX, 1 of 8. POKéMON database", "start menu entry with description")
start.list.index = 4
SR.update(start)
eq(last(), "POKéGEAR. Trainer's key device", "ligature row and description")
start.list.index = 5
SR.update(start)
eq(last(), "KRIS. Your own status", "player name row")
local quitIndex
for i, item in ipairs(start.list.items) do if item.value == "quit" then quitIndex = i end end
start.list.index = quitIndex
start:choose("quit", quitIndex)
SR.update(start)
eq(last(), "Return to the title screen?", "QUIT prompt as soon as it types")
start.typer.shown = start.typer.total
SR.update(start)
eq(last(), "NO", "YES/NO appears with NO selected")
eq(lastInterrupt(), false, "first YES/NO queues behind the prompt")
start.confirmChoice = 1
SR.update(start)
eq(last(), "YES", "confirm toggle")
start.phase = nil
SR.update(start)
eq(last(), "QUIT, 8 of 8. Return to the title", "back to the list")
SR.update(start, nil)
reset()
SR.update(start)
check(last():find("^Start menu%. QUIT, 8 of 8") ~= nil, "returning to the start menu repeats context")
save.options.menuAccount = false
reset()
StartMenu.lastIndex = 1
SR.update(StartMenu.new(game, { save = save, unlocked = { party = true, pack = true } }))
eq(last(), "Start menu. POKéMON, 1 of 6", "MENU ACCOUNT off: no description")
save.options.menuAccount = nil
-- the Bug-Catching Contest status box
reset()
save.bugContest = { active = true, balls = 18, caught = { species = "CATERPIE", name = "CATERPIE", level = 7 } }
StartMenu.lastIndex = 1
SR.update(StartMenu.new(game, { save = save, unlocked = { party = true, pack = true } }))
check(last():find("^Start menu%. Caught CATERPIE, level 7, balls 18%. POKéMON, 1 of") ~= nil,
  "contest status on entry: " .. tostring(last()))
save.bugContest = nil

-- ---------------------------------------------------------------- options
reset()
local OptionsMenu = gen2("OptionsMenu")
local pageRows = {
  { label = "TEXT SPEED", key = "textSpeed", values = { "FAST", "MID", "SLOW" },
    display = { FAST = "FAST", MID = "MID ", SLOW = "SLOW" } },
  { label = "FRAME", key = "frame", frame = true },
  { label = "MUSIC VOL", key = "musicVol", cycle = function() end,
    text = function(options) return options.musicVol == 0 and "OFF" or tostring(options.musicVol) end },
  { label = "AUTO-WALK SPEED", value = function() return "GAME SPEED" end },
  { label = "BACK", cancel = true },
}
local opts = { textSpeed = "MID", frame = 3, musicVol = 7 }
local top = as("OptionsMenu", { game = game, options = opts, index = 1, view = {
  { id = "group.accessibility", label = "ACCESSIBILITY", group = true, value = function() return "2 OPTIONS" end },
  { id = "group.speed", label = "SPEED", group = true },
  { label = "BACK", cancel = true } } })
SR.update(top)
eq(last(), "Options. ACCESSIBILITY, 2 OPTIONS, 1 of 3", "options entry")
top.index = 2
SR.update(top)
eq(last(), "SPEED, 2 of 3", "group row has no value")
local page = as("OptionsMenu", { game = game, options = opts, index = 1, sub = true, view = pageRows })
local savedStack = package.loaded["src.core.StateStack"]
package.loaded["src.core.StateStack"] = { states = { top, page } }
SR.update(page)
eq(last(), "SPEED. TEXT SPEED, MID, 1 of 5", "group page named after its row; display trimmed")
opts.textSpeed = "SLOW"
SR.update(page)
eq(last(), "SLOW", "values row change")
page.index = 2
SR.update(page)
eq(last(), "FRAME, TYPE 3, 2 of 5", "frame row")
opts.frame = 4
SR.update(page)
eq(last(), "TYPE 4", "frame change")
page.index = 3
SR.update(page)
eq(last(), "MUSIC VOL, 7, 3 of 5", "text row")
opts.musicVol = 0
SR.update(page)
eq(last(), "OFF", "text row change")
page.index = 4
SR.update(page)
eq(last(), "AUTO-WALK SPEED, GAME SPEED, 4 of 5", "Gen 1 style value row")
page.index = 5
SR.update(page)
eq(last(), "BACK, 5 of 5", "BACK is inside the view")
-- the real OPTION screen, with our ACCESSIBILITY page installed
reset()
require("src.access.Settings").install()
local stackStates = {}
package.loaded["src.core.StateStack"] = { states = stackStates }
local game2 = { data = {}, save = {}, options = {},
  stack = { push = function(_, s) stackStates[#stackStates + 1] = s end } }
local real = OptionsMenu.new(game2, { options = game2.options })
stackStates[1] = real
SR.update(real)
eq(last(), "Options. ACCESSIBILITY, 2 OPTIONS, 1 of " .. #real.view, "real OPTION screen entry")
real.view[1].activate(game2)
local access = stackStates[2]
SR.update(access)
eq(last(), "ACCESSIBILITY. AUTO-WALK SPEED, GAME SPEED, 1 of 4", "ACCESSIBILITY page")
access.index = 2
SR.update(access)
eq(last(), "DIALOGUE SPEECH, PAGE BY PAGE, 2 of 4", "DIALOGUE SPEECH row")
access:cycle(access.view[2], 1)
SR.update(access)
eq(last(), "ALL AT ONCE", "value change through the screen's own cycle")
stackStates[2] = nil
real.index = 2
SR.update(real)
real.view[2].activate(game2)
SR.update(stackStates[2])
check(last():find("^SPEED%. TEXT SPEED, %u+, 1 of %d+$") ~= nil, "built-in group page: " .. tostring(last()))
stackStates[2] = nil
for i, row in ipairs(real.view) do if row.id == "menuAccount" then real.index = i end end
SR.update(real)
-- back from the group page, so the context is repeated
check(last():find("^Options%. MENU ACCOUNT, O[NF]F?, %d+ of %d+$") ~= nil, "cart values row on the top level: " .. tostring(last()))
package.loaded["src.core.StateStack"] = savedStack

-- ---------------------------------------------------------------- save
reset()
local SaveMenu = gen2("SaveMenu")
local saving = SaveMenu.new(game, { save = save, existed = true, writer = function() return true end })
SR.update(saving)
eq(count(), 0, "nothing before the first update types the prompt")
saving:enterPhase("confirm")
SR.update(saving)
eq(last(), "Save. KRIS, badges 1, POKéDEX 2, time 3:07. Would you like to save the game?", "save entry")
saving.typer.shown = saving.typer.total
SR.update(saving)
eq(last(), "YES", "YES/NO once typed")
eq(lastInterrupt(), false, "YES queues behind the question")
saving.choice = 2
SR.update(saving)
eq(last(), "NO", "toggle")
saving.choice = 1
SR.update(saving)
saving:accept() -- a file exists: overwrite question, two pages
SR.update(saving)
eq(last(), "There is already a save file. Is it", "overwrite page 1")
saving.typer.shown = saving.typer.total
saving.page = 2
saving.typer:start(saving.pages[2])
SR.update(saving)
eq(last(), "OK to overwrite?", "scrolled page says only its new line")
saving.typer.shown = saving.typer.total
SR.update(saving)
eq(last(), "YES", "overwrite YES/NO")
saving:accept()
SR.update(saving)
eq(last(), "SAVING… DON'T TURN OFF THE POWER.", "saving line")
eq(lastInterrupt(), false, "saving line queues")
saving.saved = true
saving:enterPhase("done")
SR.update(saving)
eq(last(), "KRIS saved the game.", "saved line")

-- ---------------------------------------------------------------- script menus
reset()
local ScriptMenu = gen2("ScriptMenu")
local vend = ScriptMenu.new(game, { save = save, balance = "money",
  header = { items = { "FRESH WATER  ¥200", "SODA POP     ¥300", "CANCEL" }, cursor = 1 } })
SR.update(vend)
eq(last(), "FRESH WATER ¥200, 1 of 3. Money ¥3000", "script menu entry with the balance box")
vend.row = 2
SR.update(vend)
eq(last(), "SODA POP ¥300", "script menu move")
reset()
SR.update(ScriptMenu.new(game, { save = save, balance = "moneycoins",
  header = { items = { "50 COINS", "CANCEL" }, cursor = 1 } }))
eq(last(), "50 COINS, 1 of 2. Money ¥3000, Coins 120", "money and coins")
reset()
local grid = ScriptMenu.new(game, { save = save, style = "2d",
  header = { grid = { rows = 2, cols = 2, spacing = 6 }, gridItems = { "RED", "BLU", "YLW", "GRN" }, cursor = 1 } })
SR.update(grid)
eq(last(), "RED, 1 of 4, 2 columns", "2D menu entry")
grid.row, grid.col = 2, 1
SR.update(grid)
eq(last(), "YLW", "2D index is (row - 1) * cols + col")

-- ---------------------------------------------------------------- elevator
reset()
local elevator = gen2("ElevatorMenu").new(game, {
  -- floorId is 0-based into floorNames (ElevatorMenu.floorName)
  floors = { { floorId = 3, destMap = "B1F" }, { floorId = 4, destMap = "1F" }, { floorId = 5, destMap = "2F" } },
  currentMap = "1F", floorNames = { "B4F", "B3F", "B2F", "B1F", "1F", "2F", "3F" } })
SR.update(elevator)
eq(last(), "Elevator. Now on 1F. B1F, 1 of 3", "elevator entry")
elevator.index = 2
SR.update(elevator)
eq(last(), "1F, current floor", "current floor marked")

-- ---------------------------------------------------------------- Bank of Mom
reset()
local bank = gen2("BankOfMom").new(game, { kind = "deposit", saved = 3000, held = 500 })
SR.update(bank)
eq(last(), "Saved ¥3000, held ¥500. Deposit ¥0, ones, 0", "bank entry")
bank.position = 3
SR.update(bank)
eq(last(), "hundreds, 0", "digit move")
bank.amount = 100
SR.update(bank)
eq(last(), "¥100", "amount change")
bank.position = 3
bank.amount = 100
SR.update(bank)
reset()
SR.update(gen2("BankOfMom").new(game, { kind = "withdraw", saved = 3000, held = 500 }))
check(last():find("Withdraw ¥0") ~= nil, "withdraw kind")

-- ---------------------------------------------------------------- evolution, eggs
reset()
local evo = as("EvolutionAnim", { phase = "evolving", force = false, lines = { "What? CYNDAQUIL", "is evolving!" } })
SR.update(evo)
eq(last(), "What? CYNDAQUIL is evolving!", "evolution message")
eq(lastInterrupt(), false, "timed messages queue")
evo.phase = "flash"
SR.update(evo)
eq(last(), "Press B to stop the evolution.", "B hint when it can be stopped")
evo.lines = { "Congratulations!", "Your CYNDAQUIL" }
evo.phase = "congrats"
SR.update(evo)
eq(last(), "Congratulations! Your CYNDAQUIL", "next message")
evo.lines = nil
SR.update(evo)
evo.lines = { "evolved into", "QUILAVA!" }
SR.update(evo)
eq(last(), "evolved into QUILAVA!", "message after the paragraph gap")
reset()
local stone = as("EvolutionAnim", { phase = "flash", force = true, lines = { "What? EEVEE", "is evolving!" } })
SR.update(stone)
eq(last(), "What? EEVEE is evolving!", "a stone evolution gets no B hint")
reset()
SR.update(as("EggHatchAnim", {}))
eq(last(), "Egg hatching.", "egg hatch")

-- ---------------------------------------------------------------- silent screens
reset()
SR.update(as("OakSpeech", { step = 2 }))
SR.update(as("MenuFade", {}))
SR.update(as("BlankScreen", {}))
eq(count(), 0, "OakSpeech, MenuFade and BlankScreen stay silent")

-- ---------------------------------------------------------------- reading changes nothing
local Presenters = require("src.access.screens.Presenters")
local function snapshot(t, seen)
  seen = seen or {}
  if seen[t] then return "<seen>" end
  seen[t] = true
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    local v = t[k]
    if v == nil then
      for key, value in pairs(t) do if tostring(key) == k then v = value end end
    end
    out[#out + 1] = k .. "=" .. (type(v) == "table" and snapshot(v, seen) or tostring(v))
  end
  return "{" .. table.concat(out, ",") .. "}"
end
local probes = {
  StartMenu.new(game, { save = save, unlocked = { party = true } }),
  InitClock.new(game, { mode = "day" }),
  SaveMenu.new(game, { save = save, existed = false }),
  gen2("NamingScreen").new(game, { type = "rival" }),
}
probes[3]:enterPhase("confirm")
local saveBefore = snapshot(save)
for _, state in ipairs(probes) do
  local beforeState = snapshot(state)
  local presenter = Presenters.find(state)
  check(presenter ~= nil, "presenter found for probe")
  if presenter then
    presenter.poll(state, {}, true)
    presenter.poll(state, {}, false)
  end
  eq(snapshot(state), beforeState, "polling leaves the screen unchanged")
end
eq(snapshot(save), saveBefore, "polling leaves the save unchanged")

GameVersion.set("red")
T.finish("gen2 menus")
