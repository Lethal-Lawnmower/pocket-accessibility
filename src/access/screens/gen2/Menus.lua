-- Gen 2 presenters (decision 27): the boot sequence, the main menu, the
-- new-game screens (clock, gender, name), the start menu and its confirm,
-- the OPTION screen, SAVE, script multiple-choice menus, the elevator, the
-- Bank of Mom keypad, evolution and egg hatching.
--
-- Same contract as src/access/screens/Presenters.lua: matches(state) by
-- metatable, poll(state, memo, entering) -> text, interrupt.  Every value
-- is read from the screen's own fields, records or pure methods, mirroring
-- the draw code cited beside it; nothing here changes game state.  A field
-- that is missing or unreadable leaves the screen quiet rather than
-- guessed.
--
-- Deliberately silent (no presenter): OakSpeech (its only own text is the
-- last page of OakText7 re-drawn during the shrink, already spoken by the
-- TextBox before it; every other beat is a TextBox or one of the screens
-- below), MenuFade, BlankScreen (transient fades) and IntroFade (a helper,
-- not a state).

local Common = require("src.access.screens.gen2.Common")
local GameVersion = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local Strings = require("src.core.Strings")

local Menus = {}

local matcher, speakable, position = Common.matcher, Common.speakable, Common.position

-- ------------------------------------------------------------- helpers

local sentences = Common.sentences
Menus.sentences = sentences

local function trim(text)
  return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A screen's own read-only method, through pcall; nil when it fails.
local function call(state, name, ...)
  local fn = state[name]
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, state, ...)
  if ok then return value end
  return nil
end

-- YES / NO for the screens that draw their own two-row box from a 1/2
-- field (InitClock yesNo, StartMenu confirmChoice, SaveMenu choice): each
-- draws Strings("YES") on row 1 and Strings("NO") on row 2.
local function yesNo(choice)
  if choice == 1 then return Strings("YES") end
  if choice == 2 then return Strings("NO") end
  return nil
end

-- A word the cartridge split across lines ("crea-" / "tures"): letter,
-- hyphen, then a lower-case start.  Same rule as Presenters' dialogue box.
local function splitWord(line, nextLine)
  return tostring(line):find("%a%-$") ~= nil and tostring(nextLine or ""):find("^%l") ~= nil
end

local function textLines(text)
  local out = {}
  for line in (tostring(text or "") .. "\n"):gmatch("(.-)[\n\f\v]") do
    if line ~= "" then out[#out + 1] = line end
  end
  return out
end

-- The new part of a typed page.  `all` is the whole message as lines and
-- `page` the lines the screen shows now; a scrolled page repeats the line
-- above it, so only lines past memo.through are spoken.  A word split at
-- the end of the page is finished from the next line, so it is never cut
-- in half across an A press.  A page not found in `all` is spoken whole.
local function newLines(all, page, memo)
  local n = #page
  if n == 0 then return nil end
  local start, stop
  for a = 1, #all - n + 1 do
    local match = true
    for i = 1, n do
      if all[a + i - 1] ~= page[i] then match = false break end
    end
    if match then
      start, stop = a, a + n - 1
      if stop > (memo.through or 0) then break end
    end
  end
  if not stop then return Common.lines(page) end
  if stop <= (memo.through or 0) then return nil end
  while stop < #all and splitWord(all[stop], all[stop + 1]) do stop = stop + 1 end
  local first = math.max((memo.through or 0) + 1, start)
  memo.through = stop
  local chunk = {}
  for i = first, stop do chunk[#chunk + 1] = all[i] end
  return Common.lines(chunk)
end

-- The save panel the CONTINUE confirm and SAVE both draw from
-- Save.summary (src/ui/gen2/MainMenu.lua drawSavePanel,
-- src/ui/gen2/SaveMenu.lua drawPanel): name, badges, Pokédex, play time.
local function panelText(saveTable)
  local Save = package.loaded["src.core.gen2.Save"]
  local ok, summary = pcall(Save and Save.summary, saveTable)
  if not ok or type(summary) ~= "table" then return nil end
  return string.format("%s, badges %d, POKéDEX %d, time %d:%02d",
    speakable(summary.name), summary.badges or 0, summary.caught or 0,
    summary.hours or 0, summary.minutes or 0)
end

-- ----------------------------------------------------- script menus

-- src/ui/gen2/ScriptMenu.lua: `items` are the drawn labels, the cursor is
-- `row`/`col` and the chosen item is ScriptMenu.choiceIndex(row, col, cols).
-- The balance box (drawBalance) shows money and/or coins from the save.
local function balanceText(state)
  local kind = state.balance
  if not kind then return nil end
  local player = state.save and state.save.player or {}
  local money = "Money ¥" .. tostring(player.money or 0)
  local coins = "Coins " .. tostring(player.coins or 0)
  if kind == "coins" then return coins end
  if kind == "moneycoins" then return money .. ", " .. coins end
  return money
end

Menus.scriptMenu = {
  matches = matcher("ScriptMenu"),
  poll = function(state, memo, entering)
    if state.done then return nil end
    local cols = state.cols or 1
    local index = ((state.row or 1) - 1) * cols + (state.col or 1)
    if not entering and memo.index == index then return nil end
    memo.index = index
    local items = state.items or {}
    local item = items[index]
    if type(item) == "table" then item = item.label end
    if item == nil then return nil end
    local text = speakable(item)
    if entering then
      text = text .. ", " .. position(index, #items)
      -- a 2D menu: left and right move along a row
      if cols > 1 then text = text .. ", " .. cols .. " columns" end
      text = sentences({ text, balanceText(state) })
    end
    return text, true
  end,
}

-- ----------------------------------------------------- boot sequence

-- Boot lines queue behind each other (interrupt false), so the copyright,
-- GAME FREAK and title lines are all heard even when the cards are short or
-- skipped; the main menu interrupts them.  Each card is a new instance on
-- every attract loop, so the lines repeat when the title times out.
local function once(text)
  return function(state, memo)
    if memo.said then return nil end
    memo.said = true
    local value = text(state)
    if not value or value == "" then return nil end
    return value, false
  end
end

-- src/ui/gen2/CopyrightSplash.lua draws the cart's copyright card from an
-- image (CopyrightGFX: the Nintendo, Creatures and GAME FREAK lines), so
-- there is no text to read; its `lines` fallback is read when present.  The
-- years exist only in the image and are not spoken.
Menus.copyrightSplash = {
  matches = matcher("CopyrightSplash"),
  poll = once(function(state)
    if type(state.lines) == "table" and #state.lines > 0 then
      return Common.lines(state.lines)
    end
    return "Copyright Nintendo, Creatures inc., GAME FREAK inc."
  end),
}

-- GAME FREAK splash: Gold/Silver's star and logo, Crystal's Ditto.  Both
-- place the words "GAME FREAK" and "presents" as tiles; any button skips
-- straight to the title.
local function gameFreak() return "GAME FREAK presents." end
Menus.gameFreakPresents = { matches = matcher("GameFreakPresents"), poll = once(gameFreak) }
Menus.crystalSplash = { matches = matcher("CrystalSplash"), poll = once(gameFreak) }

-- The intro movies have no text; A, B, START or SELECT skip them.
local function intro() return "Intro. Press start to skip." end
Menus.goldSilverIntro = { matches = matcher("GoldSilverIntro"), poll = once(intro) }
Menus.crystalIntro = { matches = matcher("CrystalIntro"), poll = once(intro) }

-- The edition the running game was imported as (src/core/GameVersion.lua,
-- picked from the ROM by the importer), never a fixed "Gold".
local function editionName()
  local ok, info = pcall(GameVersion.info)
  if not ok or type(info) ~= "table" or info.generation ~= 2 or not info.label then return nil end
  return "POKéMON " .. info.label .. " Version"
end
Menus.editionName = editionName

-- src/ui/gen2/TitleState.lua: the logo, wordmark and the bottom
-- "© GAME FREAK inc." line are images.  Buttons are ignored while the
-- entrance slides in (entranceScx > 0), so the line waits for it; a
-- timed-out title fading back to the copyright card says nothing.
Menus.titleState = {
  matches = matcher("TitleState"),
  poll = function(state, memo)
    if memo.said or (state.entranceScx or 0) > 0 or state.fadeStart then return nil end
    memo.said = true
    return sentences({ editionName(), "Copyright GAME FREAK inc.", "Press start." }), false
  end,
}

-- ----------------------------------------------------- main menu

-- The clock box (MainMenu:drawClockBox): weekday and InitClock.timeString.
-- Mirrors MainMenu:clockParts, except that Clock.weekday also raises the
-- mod event clock.day_changed when a mod listens, so the weekday is left
-- out then rather than read through a call that can emit an event.
local function mainMenuClock(state)
  local InitClock = package.loaded["src.ui.gen2.InitClock"]
  local Clock = package.loaded["src.core.gen2.Clock"]
  if not (InitClock and Clock) then return nil end
  local hour, minute, weekday
  if type(state.clock) == "table" then
    hour, minute, weekday = state.clock.hour or 0, state.clock.minute or 0, state.clock.weekday or 1
  else
    local okH, h = pcall(Clock.hour, state.save)
    local okM, m = pcall(Clock.minute, state.save)
    if not (okH and okM) then return nil end
    hour, minute = h, m
    if not Runtime.wants("clock.day_changed") then
      local okD, d = pcall(Clock.weekday, state.save)
      if okD and d then weekday = d + 1 end
    end
  end
  local okT, time = pcall(InitClock.timeString, hour, minute)
  local day = weekday and Clock.weekdayName(weekday)
  return trim(((day and speakable(day) .. " ") or "") .. (okT and speakable(time) or ""))
end

Menus.mainMenu = {
  matches = matcher("MainMenu"),
  poll = function(state, memo, entering)
    if state.phase == "confirm" then
      if memo.phase == "confirm" and not entering then return nil end
      memo.phase = "confirm"
      -- CONTINUE's save panel; A continues, B goes back (MainMenu:update).
      return sentences({ panelText(state.save) or "NO SAVE FILE", "A to continue, B to go back" }), true
    end
    local list = state.list
    local index = list and list.index
    local back = memo.phase == "confirm"
    if not entering and not back and memo.index == index then return nil end
    memo.phase, memo.index = "menu", index
    local label = Common.listRow(list)
    if not label then return nil end
    if not (entering or back) then return label, true end
    local text = label .. ", " .. position(index, #list.items)
    if entering then
      text = "Main menu. " .. text
      if state.hasSave then text = sentences({ text, mainMenuClock(state) }) end
    end
    return text, true
  end,
}

-- ----------------------------------------------------- clock setting

-- src/ui/gen2/InitClock.lua, both modes (Oak's hour and minutes, Mom's day
-- wheel).  The question is the typer's current page (typer.page, a new
-- table per page) read against question() so scrolled pages are not
-- repeated; the picker value is display(); confirming() phases draw a
-- YES/NO from `yesNo`.  Raw fields are compared each frame and text is only
-- built when one changes.  Nothing is said while the screen is blank
-- (fading in).
Menus.initClock = {
  matches = matcher("InitClock"),
  poll = function(state, memo, entering)
    if state.blank then return nil end
    if entering then
      memo.page, memo.phase, memo.value, memo.choice, memo.question, memo.through = nil, nil, nil, nil, nil, 0
    end
    local typer = state.typer
    local page = typer and typer.page
    local phase = state.phase
    local value = phase == "hour" and state.hour or phase == "minute" and state.minute
      or phase == "day" and state.day or nil
    local confirming = call(state, "confirming") and true or false
    local choice = confirming and state.yesNo or nil
    if page == memo.page and phase == memo.phase and value == memo.value and choice == memo.choice then
      return nil
    end
    local parts = {}
    if type(page) == "table" and page ~= memo.page then
      local question = call(state, "question") or ""
      -- a new question, or the same one asked again in a new phase (NO on a
      -- confirmation goes back to the picker and re-types its question)
      if question ~= memo.question or phase ~= memo.phase then
        memo.question, memo.through = question, 0
      end
      parts[#parts + 1] = newLines(textLines(question), page, memo)
    end
    if value ~= nil and (value ~= memo.value or phase ~= memo.phase) then
      local shown = call(state, "display")
      if shown then parts[#parts + 1] = speakable(shown) end
    end
    if choice and (choice ~= memo.choice or phase ~= memo.phase) then
      parts[#parts + 1] = yesNo(choice)
    end
    memo.page, memo.phase, memo.value, memo.choice = page, phase, value, choice
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
}

-- ----------------------------------------------------- gender (Crystal)

-- src/ui/gen2/GenderSelect.lua: the typed question (typer.page), then the
-- Boy/Girl menu once menuOpen(); labels are the screen's own OPTIONS
-- records, drawn through Strings.  Quiet once a choice is made.
Menus.genderSelect = {
  matches = matcher("GenderSelect"),
  poll = function(state, memo, entering)
    if state.chosen then return nil end
    local parts, interrupt = {}, true
    local question = Common.typerText(state, memo)
    if question then parts[#parts + 1] = question end
    local open = call(state, "menuOpen") and true or false
    local cursor = open and state.cursor or nil
    if cursor and (cursor ~= memo.cursor or entering) then
      local options = getmetatable(state).OPTIONS or {}
      local option = options[cursor]
      if option and option.label then
        local label = speakable(Strings(option.label))
        if memo.cursor == nil or entering then
          label = label .. ", " .. position(cursor, #options)
          -- the menu opens after the question: queue behind it
          if not question then interrupt = false end
        end
        parts[#parts + 1] = label
      end
    end
    memo.cursor = cursor
    local text = sentences(parts)
    if text == "" then return nil end
    return text, interrupt
  end,
}

-- ----------------------------------------------------- name choice

-- src/ui/gen2/NamePick.lua: NEW NAME plus the edition's preset names.  The
-- menu is drawn only once the picture has slid in (`slide` nil); the draw
-- translates row 1 (the NEW NAME source string) and prints the presets as
-- they are, which is mirrored here.
Menus.namePick = {
  matches = matcher("NamePick"),
  poll = function(state, memo, entering)
    if state.slide ~= nil then return nil end
    local first = entering or not memo.shown
    if not first and memo.cursor == state.cursor then return nil end
    memo.shown, memo.cursor = true, state.cursor
    local items = state.items or {}
    local label = items[state.cursor]
    if label == nil then return nil end
    if state.cursor == 1 then label = Strings(label) end
    local text = speakable(label)
    if first then text = "Name. " .. text .. ", " .. position(state.cursor, #items) end
    return text, true
  end,
}

-- ----------------------------------------------------- naming keyboard

-- Cells a screen reader would skip or misread, spelled out.  Letters and
-- digits are read as they are.
local CELL_WORDS = {
  [" "] = "space", ["×"] = "times", ["("] = "left parenthesis",
  [")"] = "right parenthesis", [":"] = "colon", [";"] = "semicolon",
  ["["] = "left bracket", ["]"] = "right bracket", ["<PK>"] = "PK",
  ["<MN>"] = "MN", ["-"] = "dash", ["?"] = "question mark",
  ["!"] = "exclamation mark", ["/"] = "slash", ["."] = "dot", [","] = "comma",
  ["♂"] = "male", ["♀"] = "female", ["&"] = "and", ["é"] = "e acute",
}
local function cellWord(cell)
  if cell == nil or cell == "" then return nil end
  if CELL_WORDS[cell] then return CELL_WORDS[cell] end
  local rest = cell:match("^'(%a+)$")
  if rest then return "apostrophe " .. rest end
  return speakable(cell)
end
Menus.cellWord = cellWord

-- The name as typed.  The screen deletes one byte at a time, which can
-- leave half of a two-byte letter behind (é, ×, ♂); bytes that do not form
-- a whole UTF-8 character are left out of speech.
local function wholeCharacters(text)
  local out, i, n = {}, 1, #text
  while i <= n do
    local b = text:byte(i)
    local len = b < 0x80 and 1 or (b >= 0xF0 and 4) or (b >= 0xE0 and 3) or (b >= 0xC2 and 2) or 0
    local ok = len > 0 and i + len - 1 <= n
    for k = i + 1, i + len - 1 do
      local c = ok and text:byte(k)
      if not c or c < 0x80 or c > 0xBF then ok = false break end
    end
    if ok then
      out[#out + 1] = text:sub(i, i + len - 1)
      i = i + len
    else
      i = i + 1
    end
  end
  return table.concat(out)
end

local function typedName(text)
  local name = speakable(wholeCharacters(tostring(text or "")))
  return name ~= "" and name or "empty"
end

-- The cell under the cursor.  Letter rows come from characterAt (the
-- screen's own board, ui.naming.grid included).  The bottom row holds three
-- targets, told apart by bottomTarget() exactly as update() dispatches them:
-- 1 switches case (the label names the board it switches to), 2 deletes,
-- 3 ends entry.
local function namingCell(state)
  local bottom = call(state, "bottomRow")
  if bottom and state.row == bottom then
    local target = call(state, "bottomTarget")
    if target == 1 then return state.lower and "UPPER CASE" or "lower case" end
    if target == 2 then return "delete" end
    if target == 3 then return "end, confirm name" end
    return nil
  end
  return cellWord(call(state, "characterAt", state.col, state.row))
end

-- src/ui/gen2/NamingScreen.lua: `prompt` (a source string the draw
-- translates), `monName` for nicknames, `text` (a string), 0-based
-- `row`/`col`, `lower`.
Menus.namingScreen = {
  matches = matcher("NamingScreen"),
  poll = function(state, memo, entering)
    local text = tostring(state.text or "")
    if not entering and memo.row == state.row and memo.col == state.col
        and memo.lower == state.lower and memo.text == text then
      return nil
    end
    local before = memo.text or ""
    local moved = memo.row ~= state.row or memo.col ~= state.col
    local cell = namingCell(state)
    local out
    if entering or memo.text == nil then
      local prompt = state.prompt and speakable(Strings(state.prompt)) or ""
      if state.monName then prompt = speakable(state.monName) .. ", " .. prompt end
      out = sentences({ trim(prompt .. " " .. typedName(text)), cell })
    elseif #text > #before and text:sub(1, #before) == before then
      out = (cellWord(text:sub(#before + 1)) or speakable(text:sub(#before + 1))) .. ", " .. typedName(text)
      if moved then out = sentences({ out, cell }) end -- the cursor jumped to END
    elseif #text < #before then
      out = "deleted, " .. typedName(text)
    elseif text ~= before then
      out = typedName(text)
    elseif memo.lower ~= state.lower and not moved then
      out = sentences({ state.lower and "lower case" or "upper case", cell })
    else
      out = cell
    end
    memo.row, memo.col, memo.lower, memo.text = state.row, state.col, state.lower, text
    if not out or out == "" then return nil end
    return out, true
  end,
}

-- ----------------------------------------------------- start menu

-- The Bug-Catching Contest box StartMenu:drawContestStatus shows: the
-- caught mon and its level, and balls left.  Read straight from
-- save.bugContest (BugContest.state would create the table).
local function contestText(state)
  if not state.contest then return nil end
  local contest = state.save and state.save.bugContest
  if type(contest) ~= "table" then return nil end
  local mon = contest.caught
  local caught = "Caught nothing"
  if type(mon) == "table" then
    caught = "Caught " .. speakable(mon.nickname or mon.name or mon.species) .. ", level " .. tostring(mon.level or 1)
  end
  return caught .. ", balls " .. tostring(contest.balls or 0)
end

local function startRow(state)
  local list = state.list
  local item = list and list.items and list.items[list.index]
  if type(item) ~= "table" then return nil end
  local label = speakable(item.label)
  -- MENU ACCOUNT: the row's two-line description (StartMenu:draw)
  local desc = state.showDescription and item.desc and Common.lines(item.desc) or nil
  return label, desc ~= "" and desc or nil
end

-- src/ui/gen2/StartMenu.lua: a Chrome.List (`list.items[i].label`,
-- `list.index`); QUIT's confirm (`phase` "confirm" or "confirmContest") types
-- its prompt with the typer and draws YES/NO from `confirmChoice` once
-- promptTyping() is false.  Every submenu opens and closes through a
-- MenuFade over this screen, so returning repeats the context.
Menus.startMenu = {
  matches = matcher("StartMenu"),
  poll = function(state, memo, entering)
    local phase = state.phase
    if phase == "confirm" or phase == "confirmContest" then
      local parts, interrupt = {}, true
      if entering then memo.promptPage, memo.choice = nil, nil end
      local prompt = state.typedPhase == phase and Common.typerText(state, memo, "promptPage") or nil
      if prompt then parts[#parts + 1] = prompt end
      local typing = call(state, "promptTyping")
      local choice = (typing == false) and state.confirmChoice or nil
      if choice and choice ~= memo.choice then
        parts[#parts + 1] = yesNo(choice)
        if memo.choice == nil and not prompt then interrupt = false end
      end
      memo.choice, memo.confirm = choice, phase
      local text = sentences(parts)
      if text == "" then return nil end
      return text, interrupt
    end
    local index = state.list and state.list.index
    local back = memo.confirm ~= nil
    if not entering and not back and memo.index == index then return nil end
    memo.index, memo.confirm, memo.choice, memo.promptPage = index, nil, nil, nil
    local label, desc = startRow(state)
    if not label then return nil end
    local text = label
    if entering or back then
      text = text .. ", " .. position(index, #state.list.items)
      if entering then
        text = sentences({ "Start menu", contestText(state), text })
      end
    end
    return sentences({ text, desc }), true
  end,
}

-- ----------------------------------------------------- options

-- One OPTION row's value as OptionsMenu:drawPanel prints it, in the same
-- order of precedence: FRAME's ":TYPE" plus the number, a `text(options)`
-- reader, a `values` row through its `display` strings, or a Gen 1 style
-- `value(game)` reader (mod rows and the ACCESSIBILITY rows).
local function optionValue(state, row)
  local options = state.options or {}
  if row.frame then
    return trim(Strings(":TYPE"):gsub("^:", "")) .. " " .. tostring(options.frame or 1)
  elseif type(row.text) == "function" then
    local ok, value = pcall(row.text, options)
    return ok and value ~= nil and trim(speakable(value)) or nil
  elseif row.values then
    local value = options[row.key]
    local shown = row.display and row.display[value]
    if shown ~= nil then return trim(speakable(Strings(shown))) end
    return value ~= nil and trim(speakable(tostring(value))) or nil
  elseif type(row.value) == "function" then
    local ok, value = pcall(row.value, state.game)
    return ok and value ~= nil and trim(speakable(value)) or nil
  end
  return nil
end

-- The raw setting a row shows, compared each frame so the value text is
-- only built when it changes.  Rows whose value comes from a function are
-- read through it (the draw calls the same function every frame).
local function optionKey(state, row)
  local options = state.options or {}
  if row.frame then return options.frame end
  local ok, value = true, nil
  if type(row.text) == "function" then
    ok, value = pcall(row.text, options)
  elseif row.values then
    value = options[row.key]
  elseif type(row.value) == "function" then
    ok, value = pcall(row.value, state.game)
  end
  if not ok or value == nil then return "nil" end
  return value
end

-- A group page (SPEED, AUDIO, ACCESSIBILITY ...) is the same class pushed
-- over the top level with `sub` set; it is named after the row selected on
-- the OptionsMenu directly below it, as in Gen 1.
local function optionsPageName(state)
  if not state.sub then return nil end
  local stack = package.loaded["src.core.StateStack"]
  local states = type(stack) == "table" and stack.states or {}
  for i = #states, 2, -1 do
    if states[i] == state then
      local parent = states[i - 1]
      if getmetatable(parent) ~= getmetatable(state) then return nil end
      local rows = parent.view or parent.rows or {}
      local row = rows[parent.index]
      return row and row.label and speakable(Strings(row.label)) or nil
    end
  end
  return nil
end

-- src/ui/gen2/OptionsMenu.lua: `view` (rows as shown, BACK included) and
-- `index`.  Entry: page name, label, value, position.  A value change on
-- the same row says the value only.
Menus.options = {
  matches = matcher("OptionsMenu"),
  poll = function(state, memo, entering)
    local rows = state.view or state.rows or {}
    local row = rows[state.index]
    local key = row and optionKey(state, row)
    if not entering and memo.index == state.index and memo.key == key then return nil end
    local moved = memo.index ~= state.index
    memo.index, memo.key = state.index, key
    if not row then return nil end
    local value = optionValue(state, row)
    local text
    if moved or entering then
      text = speakable(Strings(row.label))
      if value and value ~= "" then text = text .. ", " .. value end
      text = text .. ", " .. position(state.index, #rows)
    else
      text = value
    end
    if not text or text == "" then return nil end
    if entering then text = (optionsPageName(state) or "Options") .. ". " .. text end
    return text, true
  end,
}

-- ----------------------------------------------------- save

-- src/ui/gen2/SaveMenu.lua: the panel (Save.summary), then each prompt page
-- (`pages`, `page`; a `scrolled` page repeats the line above it), YES/NO
-- from `choice` once yesNoVisible().  The typer starts on the screen's first
-- update (typedPhase), so nothing is read before that.  The SAVING and
-- saved lines are timed, not prompts, so they queue rather than cut each
-- other off.
Menus.saveMenu = {
  matches = matcher("SaveMenu"),
  poll = function(state, memo, entering)
    if state.typedPhase ~= state.phase or type(state.pages) ~= "table" then return nil end
    local parts, interrupt = {}, true
    if entering then memo.pages, memo.page, memo.choice = nil, nil, nil end
    if not memo.started then
      memo.started = true
      parts[#parts + 1] = sentences({ "Save", panelText(state.save) })
    end
    if state.pages ~= memo.pages then memo.pages, memo.page = state.pages, nil end
    if state.page ~= memo.page then
      local page = state.pages[state.page]
      if type(page) == "table" then
        local first = (page.scrolled and memo.page == (state.page or 1) - 1) and 2 or 1
        local chunk = {}
        for i = first, #page do chunk[#chunk + 1] = page[i] end
        parts[#parts + 1] = Common.lines(chunk)
      end
      memo.page = state.page
      if state.phase == "saving" or state.phase == "done" then interrupt = false end
    end
    local visible = call(state, "yesNoVisible")
    local choice = visible and state.choice or nil
    if choice and choice ~= memo.choice then
      parts[#parts + 1] = yesNo(choice)
      if memo.choice == nil and #parts == 1 then interrupt = false end
    end
    memo.choice = choice
    local text = sentences(parts)
    if text == "" then return nil end
    return text, interrupt
  end,
}

-- ----------------------------------------------------- elevator

-- src/ui/gen2/ElevatorMenu.lua: "Now on:" and the floor the player got in
-- on (`origin`), then the floor list (`floors[i].floorId` named by the
-- class's own floorName).  Choosing the current floor just closes the menu.
local function floorText(state, row)
  local floorName = getmetatable(state).floorName
  if type(floorName) ~= "function" or type(row) ~= "table" then return nil end
  local ok, name = pcall(floorName, state.floorNames, row.floorId)
  if not ok or name == nil or name == "?" then return nil end
  return speakable(name)
end

Menus.elevator = {
  matches = matcher("ElevatorMenu"),
  poll = function(state, memo, entering)
    if state.done then return nil end
    if not entering and memo.index == state.index then return nil end
    memo.index = state.index
    local floors = state.floors or {}
    local text = floorText(state, floors[state.index])
    if not text then return nil end
    if state.index == state.origin then text = text .. ", current floor" end
    if entering then
      text = text .. ", " .. position(state.index, #floors)
      local here = state.origin and floorText(state, floors[state.origin])
      text = sentences({ "Elevator", here and ("Now on " .. here), text })
    end
    return text, true
  end,
}

-- ----------------------------------------------------- Bank of Mom

-- src/ui/gen2/BankOfMom.lua: `saved` and `held` money, the typed `amount`
-- and the digit under the cursor, `position` 0 (hundred-thousands) to
-- 5 (ones); up and down add or take that place value.
local DIGITS = { "hundred thousands", "ten thousands", "thousands", "hundreds", "tens", "ones" }

local function digitText(state)
  local positionIndex = tonumber(state.position)
  local name = positionIndex and DIGITS[positionIndex + 1]
  if not name then return nil end
  local place = 10 ^ (5 - positionIndex)
  return name .. ", " .. tostring(math.floor((state.amount or 0) / place) % 10)
end

Menus.bankOfMom = {
  matches = matcher("BankOfMom"),
  poll = function(state, memo, entering)
    if state.done then return nil end
    if not entering and memo.amount == state.amount and memo.position == state.position then
      return nil
    end
    local text
    local amount = "¥" .. tostring(state.amount or 0)
    if entering then
      local kind = state.kind == "withdraw" and "Withdraw" or "Deposit"
      text = sentences({ "Saved ¥" .. tostring(state.saved or 0) .. ", held ¥" .. tostring(state.held or 0),
        kind .. " " .. amount .. ", " .. (digitText(state) or "") })
    elseif memo.amount ~= state.amount then
      text = amount
    else
      text = digitText(state)
    end
    memo.amount, memo.position = state.amount, state.position
    if not text then return nil end
    return text, true
  end,
}

-- ----------------------------------------------------- evolution, eggs

-- src/ui/gen2/EvolutionAnim.lua: `lines` (the message box, a new table per
-- message).  The messages are timed (they advance by themselves), so they
-- queue instead of cutting each other off.  When the flashing starts and
-- the evolution can still be stopped (`force` unset), the B hint is added.
Menus.evolution = {
  matches = matcher("EvolutionAnim"),
  poll = function(state, memo)
    local parts = {}
    local lines = state.lines
    if lines ~= memo.lines then
      memo.lines = lines
      if type(lines) == "table" and #lines > 0 then parts[#parts + 1] = Common.lines(lines) end
    end
    if state.phase == "flash" and not state.force and not state.canceled and not memo.hinted then
      memo.hinted = true
      parts[#parts + 1] = "Press B to stop the evolution."
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, false
  end,
}

-- src/ui/gen2/EggHatchAnim.lua has no text and reads no input: "Huh?"
-- before it and the hatchling's line after it are dialogue boxes.  The
-- species is not named here, before the game names it.
Menus.eggHatch = {
  matches = matcher("EggHatchAnim"),
  poll = once(function() return "Egg hatching." end),
}

Menus.ordered = {
  Menus.scriptMenu,
  Menus.copyrightSplash,
  Menus.gameFreakPresents,
  Menus.crystalSplash,
  Menus.goldSilverIntro,
  Menus.crystalIntro,
  Menus.titleState,
  Menus.mainMenu,
  Menus.initClock,
  Menus.genderSelect,
  Menus.namePick,
  Menus.namingScreen,
  Menus.startMenu,
  Menus.options,
  Menus.saveMenu,
  Menus.elevator,
  Menus.bankOfMom,
  Menus.evolution,
  Menus.eggHatch,
}

return Menus
