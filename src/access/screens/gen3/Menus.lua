-- Gen 3 menu presenters (FireRed; LeafGreen shares the code, decision 29):
-- the boot sequence (intro, title, main menu, save errors), the new game
-- scene (controls guide, Pikachu pages, Oak's own text printer and his
-- menus), the naming keyboard, the start menu, OPTION and CONTROLS, SAVE,
-- the help system, the quest log, the trainer card, the Fame Checker,
-- Teachy TV's list and lesson pages, the move relearner, evolution and egg
-- hatching, script list menus (the elevator floors) and the passive
-- overlays: map name and the forest title card, elevator "Now on", coins
-- box.  (Pokémon pictures are gen3/Special.lua's, the money box
-- gen3/Items.lua's.)
--
-- Screens arrive as proxies from gen3/Top.lua ({ gen3 = <kind>, key,
-- layer, mod, game, boot, ... }, one per opening).  Every value is read
-- from the screen's own fields and from the same cart text keys and read-
-- only helpers its draw code uses (cited beside each presenter); memory is
-- kept in the per-opening memo, never on the upstream module.  A field
-- that is missing or unreadable leaves the screen quiet.
--
-- Never called, because they write: Options.block (creates the options
-- block), ElevatorWindow.isVisible (hides a stale window), FameCheckerUi
-- rows/icons/messageText (fill caches), MoveRelearner's move_info cache,
-- Naming's refreshGrids.  The Fame Checker is read from the view its own
-- draw builds.  HelpWindow (the script op loadhelp) is never drawn
-- upstream, so it is not spoken.

local Common = require("src.access.screens.gen3.Common")
local Gen2Common = require("src.access.screens.gen2.Common")
local Dialogue = require("src.access.screens.gen3.Dialogue")
local Top = require("src.access.screens.gen3.Top")
local Settings = require("src.access.Settings")

local Menus = {}

local position = Common.position

-- Common.sentences, also treating a closing ellipsis ("Previously on your
-- quest…") as the end of a sentence, so no full stop is added after it.
local ELLIPSIS = "\226\128\166"
local function sentences(parts)
  local out = ""
  for i = 1, table.maxn(parts) do
    local part = parts[i]
    if part ~= nil and part ~= "" then
      part = tostring(part)
      if out == "" then
        out = part
      elseif out:find("[%.!%?:]$") or out:sub(-#ELLIPSIS) == ELLIPSIS then
        out = out .. " " .. part
      else
        out = out .. ". " .. part
      end
    end
  end
  return out
end
Menus.sentences = sentences

-- Common.speakable says button and pad tags in words but runs them into
-- the next word ("{A_BUTTON}NEXT" would read "A buttonNEXT"), so a space
-- is put after those tags first.
local function speakable(text)
  text = tostring(text or "")
  if text:find("{", 1, true) then
    text = text:gsub("(%{[%u_]*BUTTON[%u_]*%})", "%1 "):gsub("(%{DPAD_[%u_]*%})", "%1 ")
      :gsub("(%{[%u_]*ARROW%})", "%1 ")
  end
  return Common.speakable(text)
end
Menus.speakable = speakable

-- ------------------------------------------------------------- helpers

local function loaded(path)
  return package.loaded[path]
end

local function presenters()
  return package.loaded["src.access.screens.Presenters"] or require("src.access.screens.Presenters")
end

-- A read-only upstream function through pcall; nil when it fails.
local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

-- Cart text by key, through src/core/game3/rom_text.lua as the draw code
-- reads it (translations and profile aliases included).
local function rom(key, ctx)
  local RomText = loaded("src.core.game3.rom_text")
  if not (RomText and key) then return nil end
  local ok, text = pcall(RomText.plain, key, ctx)
  if ok and type(text) == "string" then return text end
  return nil
end

local function romAt(name, index, ctx)
  local RomText = loaded("src.core.game3.rom_text")
  if not (RomText and name) then return nil end
  local ok, text = pcall(RomText.at, name, index, nil, ctx)
  if ok and type(text) == "string" then return text end
  return nil
end

-- An engine string as the screen draws it (src/core/Strings.lua).
local tr = Common.tr

-- A file-local value of an upstream module, read from one of its
-- functions by name.  Nil (so the screen stays quiet) if upstream renames it.
-- Only used for locals that never change after load (functions, constant
-- tables), so a found value is remembered per function.
local upvalueCache = setmetatable({}, { __mode = "k" })
local function upvalue(fn, name)
  if type(fn) ~= "function" then return nil end
  local cached = upvalueCache[fn]
  if cached and cached[name] ~= nil then return cached[name] end
  for i = 1, 255 do
    local n, value = debug.getupvalue(fn, i)
    if n == nil then return nil end
    if n == name then
      cached = cached or {}
      cached[name] = value
      upvalueCache[fn] = cached
      return value
    end
  end
  return nil
end
Menus._upvalue = upvalue

local function nonEmpty(text)
  if text == nil or text == "" then return nil end
  return text
end

local function trim(text)
  return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Lines as one sentence (split words rejoined), as Dialogue speaks them.
local function say(lines)
  return Gen2Common.speakable(presenters().joinLines(lines))
end

-- One page of a printed text: a list of page strings whose lines are
-- separated by "\n".  A word the cartridge split across the page break
-- ("crea-" / "tures") is finished on the earlier page, as in dialogue.
local function pageText(pages, index, memo)
  local lines = Common.lines(pages[index])
  if memo.carried == index then table.remove(lines, 1) end
  local nextLines = pages[index + 1] and Common.lines(pages[index + 1]) or nil
  if #lines > 0 and nextLines and nextLines[1] and presenters().splitWord(lines[#lines], nextLines[1]) then
    lines[#lines + 1] = nextLines[1]
    memo.carried = index + 1
  end
  return nonEmpty(say(lines))
end

-- A text printer's pages spoken like dialogue: each page as the game starts
-- showing it, or every page at once when DIALOGUE SPEECH is ALL AT ONCE
-- (decision 26).  `memo` is this printer's own table: a new pages table
-- starts over.
local function printerSpeech(pages, page, memo, game)
  if type(pages) ~= "table" then return nil end
  if memo.pages ~= pages then
    memo.pages, memo.page, memo.carried, memo.whole = pages, nil, nil, nil
  end
  if Settings.dialogueWhole(game) then
    if memo.whole then return nil end
    memo.whole = true
    local all = {}
    for _, text in ipairs(pages) do
      for _, line in ipairs(Common.lines(text)) do all[#all + 1] = line end
    end
    return nonEmpty(say(all))
  end
  page = page or 1
  if memo.page == page or pages[page] == nil then return nil end
  memo.page = page
  return pageText(pages, page, memo)
end
Menus.printerSpeech = printerSpeech

-- YES / NO as the FRLG windows print them (gText_Yes, gText_No).
local function yesNo(cursor)
  if cursor == 1 then return speakable(rom("gText_Yes") or "YES") end
  if cursor == 2 then return speakable(rom("gText_No") or "NO") end
  return nil
end

-- "Fresh" context: ScreenReader says `entering` only on the first frame a
-- screen is on top, but several screens are not readable yet then (a fade,
-- a draw that has not run); the flag waits in the memo until they are.
local function fresh(memo, entering)
  if entering then memo.fresh = true end
  return memo.fresh == true
end

-- ----------------------------------------------------------- boot: intro

-- src/ui/game3/intro_movie.lua: the copyright card, the GAME FREAK star,
-- name and logo, then the fight scenes, all images.  A, START or SELECT
-- skip it only once `phase` is "intro" (IntroMovie:update), so the hint is
-- said then; "GAME FREAK presents" when the name is revealed (callback
-- GF_RevealName).  The copyright card is an image with no text to read.
Menus.intro = {
  matches = Common.matcher("intro"),
  poll = function(state, memo)
    local movie = state.key
    if type(movie) ~= "table" or movie.isDone then return nil end
    local parts = {}
    if movie.phase == "intro" and not memo.skippable then
      memo.skippable = true
      parts[#parts + 1] = "Intro. Press start to skip."
    end
    local cb = type(movie.ptr) == "table" and movie.ptr.cb or nil
    if (cb == "GF_RevealName" or cb == "GF_RevealLogo") and not memo.gameFreak then
      memo.gameFreak = true
      parts[#parts + 1] = "GAME FREAK presents."
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, false
  end,
}

-- ----------------------------------------------------------- boot: title

-- The edition the running game was imported as (src/core/GameVersion.lua),
-- never a fixed "FireRed": the title logo is an image.
local function editionName()
  local GameVersion = loaded("src.core.GameVersion")
  local info = GameVersion and call(GameVersion.info)
  if type(info) ~= "table" or info.generation ~= 3 or not info.label then return nil end
  return "POKéMON " .. info.label .. " Version"
end
Menus.editionName = editionName

-- src/ui/game3/title_screen.lua: buttons count only in the RUN scene
-- (sceneRun), so the line waits for it.  Logo, PRESS START and the
-- copyright line are images.  Each title entry is a new object, so the
-- line repeats on every attract loop, as in Gen 2.
Menus.title = {
  matches = Common.matcher("title"),
  poll = function(state, memo)
    if memo.said then return nil end
    local Title = loaded("src.ui.game3.title_screen")
    local run = Title and type(Title.SCENE) == "table" and Title.SCENE.RUN
    local T = state.key
    if not run or type(T) ~= "table" or T.scene ~= run then return nil end
    memo.said = true
    return sentences({ editionName(), "Press start." }), false
  end,
}

-- ------------------------------------------------------ boot: main menu

-- Labels the main menu prints for each Boot.menuItems id
-- (src/ui/game3/boot.lua drawMainMenu).
local MAIN_MENU_KEYS = {
  ["CONTINUE"] = "gText_Continue", ["NEW GAME"] = "gText_NewGame",
  ["MYSTERY GIFT"] = "gText_MysteryGift", ["EXIT"] = "gText_MenuExit",
}

-- The CONTINUE window's panel (drawMainMenu): player, time, Pokédex once
-- owned, badges, from boot.continueInfo.
local function continuePanel(boot)
  local info = boot.continueInfo
  if type(info) ~= "table" then return nil end
  local parts = {
    trim(speakable(rom("gText_Player") or "")) .. " " .. speakable(info.name or ""),
    trim(speakable(rom("gText_Time") or "")) .. " " .. string.format("%d:%02d", info.hours or 0, info.minutes or 0),
  }
  if info.hasDex then
    parts[#parts + 1] = trim(speakable(rom("gText_Pokedex") or "")) .. " " .. tostring(info.dexCount or 0)
  end
  parts[#parts + 1] = trim(speakable(rom("gText_Badges") or "")) .. " " .. tostring(info.badges or 0)
  return table.concat(parts, ", ")
end

Menus.mainMenu = {
  matches = Common.matcher("main_menu"),
  poll = function(state, memo, entering)
    local boot = state.boot
    if type(boot) ~= "table" or boot.saveError then return nil end
    local isFresh = fresh(memo, entering)
    -- nothing is selectable while the menu fades in or out
    local index = boot.menuIndex or 1
    if not isFresh and memo.index == index then return nil end
    local fade = boot.menuFade
    if (fade and call(fade.fadeActive, fade)) or boot.fadeThen then return nil end
    local Boot = loaded("src.ui.game3.boot")
    local items = Boot and call(Boot.menuItems, boot)
    if type(items) ~= "table" then return nil end
    memo.index, memo.fresh = index, nil
    local id = items[index]
    local label = id and nonEmpty(speakable(rom(MAIN_MENU_KEYS[id]) or ""))
    if not label then return nil end
    local text = label
    if isFresh then text = "Main menu. " .. text .. ", " .. position(index, #items) end
    if id == "CONTINUE" then text = sentences({ text, continuePanel(boot) }) end
    return text, true
  end,
}

-- ----------------------------------------------------- boot: save error

-- boot.saveError (beginSaveError): the cart's deleted or corrupted save
-- pages, each waiting for A.
Menus.saveError = {
  matches = Common.matcher("save_error"),
  poll = function(state, memo)
    local e = state.key
    if type(e) ~= "table" then return nil end
    memo.printer = memo.printer or {}
    local text = printerSpeech(e.pages, e.page, memo.printer, state.game)
    if not text then return nil end
    return text, true
  end,
}

-- ---------------------------------------------------- boot: new game

-- The controls guide's pages 2 and 3 print three strings each from a cart
-- table whose name and window list the scene keeps in file-locals
-- (Scene.drawBg0Text: CONTROLS_PAGES, CONTROLS_WINDOWS).  The button each
-- string describes is a picture in the page's background, not text, so its
-- name is said first, in the cart's order (pokefirered/src/oak_speech.c,
-- sControlsGuide_Pages2And3_Strings): Control Pad, A, B, then START,
-- SELECT, L and R.
local GUIDE_BUTTONS = {
  [2] = { "Control Pad", "A Button", "B Button" },
  [3] = { "START Button", "SELECT Button", "L and R Buttons" },
}
Menus.GUIDE_BUTTONS = GUIDE_BUTTONS

local function guideText(scene, page)
  if page == 1 then return rom("gControlsGuide_Text_Intro") end
  local draw = scene.drawBg0Text
  local name = upvalue(draw, "CONTROLS_PAGES")
  local windows = upvalue(draw, "CONTROLS_WINDOWS")
  local list = type(windows) == "table" and windows[page]
  if type(name) ~= "string" or type(list) ~= "table" then return nil end
  local base = (page - 2) * 3
  local lines = {}
  local buttons = GUIDE_BUTTONS[page] or {}
  for i = 1, #list do
    local text = romAt(name, base + i - 1)
    -- a sentence break after the name; the text's own line breaks are joined later
    if text and buttons[i] then text = buttons[i] .. ".\n" .. text end
    lines[#lines + 1] = text
  end
  return table.concat(lines, "\n")
end

local function topbarText(scene)
  local bar = scene.win and scene.win.topbar
  if type(bar) ~= "table" then return nil, nil end
  local title = bar.title and nonEmpty(speakable(rom(bar.title) or ""))
  local hint = bar.hint and nonEmpty(speakable(rom(bar.hint) or ""))
  return title, hint
end

-- src/ui/game3/new_game_scene.lua (boot.newGame), one object for the whole
-- scene: the controls guide (`win.guide`, a new table per page), the
-- Pikachu pages (`win.pika.text`), Oak's own text printer (`printer`, new
-- per line; `pages`, `page`), and its menus (`win.menu`: gender, names,
-- yes/no; items { label, x, y }, 0-based `cursor`).  The menu opens once
-- the printer above it has finished, so its first selection queues behind
-- the line.  The naming keyboard it opens is its own screen.
Menus.newGame = {
  matches = Common.matcher("new_game"),
  poll = function(state, memo)
    local scene = state.key
    if type(scene) ~= "table" or type(scene.win) ~= "table" then return nil end
    local win = scene.win
    local parts, interrupt = {}, true

    local guide = win.guide
    if type(guide) == "table" and guide ~= memo.guide then
      memo.guide = guide
      local title, hint = topbarText(scene)
      local text = guide.page and guideText(scene, guide.page)
      parts[#parts + 1] = sentences({ title, text and speakable(text), hint })
    end
    local pika = win.pika
    if type(pika) == "table" and pika ~= memo.pika then
      memo.pika = pika
      local _, hint = topbarText(scene)
      parts[#parts + 1] = sentences({ speakable(pika.text or ""), hint })
    end

    local printer = scene.printer
    if type(printer) == "table" then
      if printer ~= memo.printerObject then
        memo.printerObject, memo.printer = printer, {}
      end
      local text = printerSpeech(printer.pages, printer.page, memo.printer, state.game)
      if text then parts[#parts + 1] = text end
    end

    local menu = win.menu
    if type(menu) == "table" and type(menu.items) == "table" then
      local cursor = (menu.cursor or 0) + 1
      if menu ~= memo.menu or cursor ~= memo.cursor then
        local opening = menu ~= memo.menu
        memo.menu, memo.cursor = menu, cursor
        local item = menu.items[cursor]
        local label = type(item) == "table" and nonEmpty(speakable(item[1] or "")) or nil
        if label then
          if opening and menu.kind ~= "yesno" then label = label .. ", " .. position(cursor, #menu.items) end
          if opening and #parts == 0 then interrupt = false end
          parts[#parts + 1] = label
        end
      end
    else
      memo.menu, memo.cursor = nil, nil
    end

    local text = sentences(parts)
    if text == "" then return nil end
    return text, interrupt
  end,
}

-- -------------------------------------------------------------- naming

-- Keyboard cells a screen reader would skip or misread.  Gen 2's words
-- cover most; these are the FRLG OTHERS page's quotes and ellipsis.
local EXTRA_CELL_WORDS = {
  ["…"] = "ellipsis", ["“"] = "open quote", ["”"] = "close quote",
  ["‘"] = "open single quote", ["’"] = "close single quote", ["'"] = "apostrophe",
}
local function cellWord(cell)
  if cell == nil or cell == "" then return nil end
  if EXTRA_CELL_WORDS[cell] then return EXTRA_CELL_WORDS[cell] end
  local Gen2Menus = loaded("src.access.screens.gen2.Menus") or require("src.access.screens.gen2.Menus")
  return Gen2Menus.cellWord(cell)
end
Menus.cellWord = cellWord

-- The page labels the PAGE button shows (images page_swap_upper, _lower,
-- _others), by page id.
local PAGE_NAMES = { UPPER = "upper case", LOWER = "lower case", OTHERS = "others" }

local function namingPages(st)
  local Naming = loaded("src.ui.game3.naming")
  local pagesOf = Naming and upvalue(Naming.draw, "pagesOf")
  local pages = (type(pagesOf) == "function" and call(pagesOf, st)) or st.pages
  return type(pages) == "table" and pages or nil
end

local function pageName(pages, index)
  local page = pages and pages[index]
  return page and (PAGE_NAMES[page.id] or (page.id and tostring(page.id):lower())) or nil
end

-- The cell under the cursor, as Naming.handleInput reads it: a column past
-- the row's last cell is the button column (st.btn 1 PAGE, 2 BACK, 3 OK);
-- a cart keyboard can also hold page and OK cells (cellRole).
local function namingCell(st, pages)
  local page = pages[st.page]
  local row = page and page.rows and page.rows[st.row]
  if type(row) ~= "table" then return nil end
  if (st.col or 1) > #row then
    if st.btn == 1 then
      local nextName = pageName(pages, st.page % #pages + 1)
      return "page" .. (nextName and (", to " .. nextName) or "")
    elseif st.btn == 2 then return "back, delete a letter"
    elseif st.btn == 3 then return "OK, confirm name" end
    return nil
  end
  local cell = row[st.col]
  if cell == "ED" then return "OK, confirm name" end
  if cell == "lower case" or cell == "UPPER CASE" or cell == "lower" or cell == "UPPER" then
    local nextName = pageName(pages, st.page % #pages + 1)
    return "page" .. (nextName and (", to " .. nextName) or "")
  end
  return cellWord(cell)
end

local function typedName(name)
  local text = speakable(name or "")
  return text ~= "" and text or "empty"
end

-- src/ui/game3/naming.lua: Naming._state (a new table per open): `title`,
-- `name`, `page`, `row`, `col`, `btn`, `pages`; after a caught Pokémon's
-- nickname, `pcPages`/`pcPage` (sent to the PC).  Same speech as the Gen 1
-- and Gen 2 keyboards: entry says the title, the name so far, the page and
-- the cell; then the cell on each move, the typed letter with the name,
-- "deleted", the new page.
Menus.naming = {
  matches = Common.matcher("naming", "src.ui.game3.naming"),
  poll = function(state, memo, entering)
    local Naming = state.mod
    local st = Naming and Naming._state
    if type(st) ~= "table" or st.finished then return nil end
    if st ~= memo.st then memo.st, memo.name, memo.pc = st, nil, nil end
    if type(st.pcPages) == "table" then
      memo.pc = memo.pc or {}
      local text = printerSpeech(st.pcPages, st.pcPage, memo.pc, state.game)
      if not text then return nil end
      return text, true
    end
    local pages = namingPages(st)
    if not pages then return nil end
    local name = tostring(st.name or "")
    if not entering and memo.name == name and memo.page == st.page and memo.row == st.row
        and memo.col == st.col and memo.btn == st.btn then
      return nil
    end
    local before = memo.name
    local moved = memo.row ~= st.row or memo.col ~= st.col or memo.btn ~= st.btn
    local cell = namingCell(st, pages)
    local out
    if entering or before == nil then
      out = sentences({ trim(speakable(st.title or "")) .. " " .. typedName(name), pageName(pages, st.page), cell })
    elseif #name > #before and name:sub(1, #before) == before then
      out = (cellWord(name:sub(#before + 1)) or speakable(name:sub(#before + 1))) .. ", " .. typedName(name)
      if moved then out = sentences({ out, cell }) end -- a full name jumps to OK
    elseif #name < #before then
      out = "deleted, " .. typedName(name)
    elseif name ~= before then
      out = typedName(name)
    elseif memo.page ~= st.page then
      out = sentences({ pageName(pages, st.page), cell })
    else
      out = cell
    end
    memo.name, memo.page, memo.row, memo.col, memo.btn = name, st.page, st.row, st.col, st.btn
    if not out or out == "" then return nil end
    return out, true
  end,
}

-- ---------------------------------------------------------- start menu

-- The Safari Zone window (StartMenu.draw: the menu data's extraWindow, a
-- cart string with the steps and balls), and Emerald's Battle Pyramid floor
-- window from the same call (kind "pyramid" exists only in rse/start_menu_data).
local function safariText(StartMenu)
  if StartMenu._kind ~= "safari" and StartMenu._kind ~= "pyramid" then return nil end
  local data, ctx = StartMenu._data, StartMenu._ctx
  local window = data and ctx and call(data.extraWindow, StartMenu._kind, ctx)
  if type(window) ~= "table" or not window.key then return nil end
  return nonEmpty(speakable(rom(window.key, { stringVars = window.vars }) or ""))
end

-- src/ui/game3/start_menu.lua (layer "start"): ENTRIES (labels as drawn,
-- the player's name included), `cursor`; EXIT's confirm (`_confirmExit`)
-- types its prompt (`_prompt`, promptTyping()) and draws YES/NO from
-- `_confirmCursor` once typing ends.  Upstream draws no descriptions, so
-- none are spoken.
Menus.startMenu = {
  matches = Common.matcher("start", "src.ui.game3.start_menu"),
  poll = function(state, memo, entering)
    local StartMenu = state.mod
    if StartMenu._confirmExit then
      local parts, interrupt = {}, true
      if not memo.confirm then
        memo.confirm, memo.choice = true, nil
        parts[#parts + 1] = speakable(tr("RETURN TO MAIN\nMENU?"))
      end
      local typing = call(StartMenu.promptTyping)
      local choice = (typing == false) and StartMenu._confirmCursor or nil
      if choice and choice ~= memo.choice then
        if memo.choice == nil and #parts == 0 then interrupt = false end
        parts[#parts + 1] = yesNo(choice)
      end
      memo.choice = choice
      local text = sentences(parts)
      if text == "" then return nil end
      return text, interrupt
    end
    local back = memo.confirm
    local cursor = StartMenu.cursor
    if not entering and not back and memo.cursor == cursor then return nil end
    memo.cursor, memo.confirm, memo.choice = cursor, nil, nil
    local entries = StartMenu.ENTRIES or {}
    local entry = entries[cursor]
    local label = type(entry) == "table" and nonEmpty(speakable(entry.label or "")) or nil
    if not label then return nil end
    local text = label
    if entering or back then text = text .. ", " .. position(cursor, #entries) end
    if entering then text = sentences({ "Start menu", safariText(StartMenu), text }) end
    return text, true
  end,
}

-- -------------------------------------------------------------- options

-- The value an OPTION row prints (value(ctx), as OptionMenu.draw calls it
-- every frame), raw, so an unchanged frame only compares strings.
local function optionRaw(OptionMenu, page, index)
  local row = (page.rows or {})[index]
  if type(row) ~= "table" or type(row.value) ~= "function" then return nil end
  local ok, v = pcall(row.value, OptionMenu._ctx)
  if ok and v ~= nil then return tostring(v) end
  return nil
end

-- One OPTION row's label; the row after the last is CANCEL
-- (sOptionMenuItemsNames[6]).
local function optionLabel(page, index)
  local rows = page.rows or {}
  if index > #rows then return speakable(romAt("sOptionMenuItemsNames", 6) or "CANCEL") end
  local row = rows[index]
  if type(row) ~= "table" then return nil end
  return speakable(row.label or "")
end

-- src/ui/game3/option_menu.lua (layer "option"): the pages live inside the
-- screen (`_pages`, each { title, rows, index, scroll }; group rows and our
-- ACCESSIBILITY page push onto it).  Entry or a new page: title, label,
-- value, position (CANCEL counts).  A move says label and value, a value
-- change on the same row the value only (as Gen 1).
Menus.options = {
  matches = Common.matcher("option", "src.ui.game3.option_menu"),
  poll = function(state, memo, entering)
    local OptionMenu = state.mod
    local ShaderFX = loaded("src.ui.game3.shaderfx_menu")
    if ShaderFX and call(ShaderFX.isOpen) then return nil end
    local pages = OptionMenu._pages
    local page = type(pages) == "table" and pages[#pages] or nil
    if type(page) ~= "table" then return nil end
    local index = page.index or 1
    local raw = optionRaw(OptionMenu, page, index)
    local newPage = page ~= memo.page
    if not entering and not newPage and memo.index == index and memo.raw == raw then return nil end
    local label = optionLabel(page, index)
    if not label then return nil end
    local value = raw and nonEmpty(trim(speakable(raw))) or nil
    local moved = memo.index ~= index
    memo.page, memo.index, memo.raw = page, index, raw
    local text
    if entering or newPage or moved then
      text = label
      if value and value ~= "" then text = text .. ", " .. value end
      if entering or newPage then
        text = sentences({ speakable(page.title or ""), text .. ", " .. position(index, #(page.rows or {}) + 1) })
      end
    else
      text = value
    end
    if not text or text == "" then return nil end
    return text, true
  end,
}

-- src/ui/game3/controls_menu.lua (layer "controls"): a Gen 1 BindingsMenu
-- (`Controls._bm`: `items` { label, right }, `index`, `capture`, `footer`)
-- drawn in the OPTION frame; Controls._confirm replaces its yes/no box.
Menus.controls = {
  matches = Common.matcher("controls", "src.ui.game3.controls_menu"),
  poll = function(state, memo, entering)
    local Controls = state.mod
    local bm = Controls._bm
    if type(bm) ~= "table" then return nil end
    local confirm = Controls._confirm
    if type(confirm) == "table" then
      if memo.confirm ~= confirm or memo.choice ~= confirm.index then
        local opening = memo.confirm ~= confirm
        memo.confirm, memo.choice = confirm, confirm.index
        local choice = confirm.index == 1 and tr("YES") or tr("NO")
        if opening then return sentences({ speakable(bm.footer or ""), choice }), true end
        return speakable(choice), true
      end
      return nil
    end
    if bm.capture then
      if memo.capture == bm.capture then return nil end
      memo.capture = bm.capture
      return sentences({ tr("PRESS A BUTTON"), tr("RELEASE TO SET"), tr("ESC/2ND CANCELS") }), true
    end
    local item = bm.items and bm.items[bm.index]
    if type(item) ~= "table" then return nil end
    local back = memo.confirm ~= nil or memo.capture ~= nil
    if not entering and not back and memo.index == bm.index and memo.right == item.right then return nil end
    local moved = memo.index ~= bm.index
    memo.index, memo.right, memo.confirm, memo.choice, memo.capture = bm.index, item.right, nil, nil, nil
    local right = trim(speakable(item.right or ""))
    if not (entering or moved or back) then return nonEmpty(right), true end
    local text = speakable(item.label or "")
    if right ~= "" then text = text .. ", " .. right end
    if entering or back then text = text .. ", " .. position(bm.index, #bm.items) end
    if entering then text = sentences({ speakable(tr("CONTROLS")), text }) end
    return text, true
  end,
}

-- ----------------------------------------------------------------- save

-- The FRLG save panel (SaveMenu.draw): location, player, badges, Pokédex
-- once owned, time, through the screen's own read helpers.
local function savePanel(SaveMenu)
  local session = SaveMenu._session or {}
  local parts = {}
  local location = call(SaveMenu.locationName, session)
  if location then parts[#parts + 1] = speakable(tr(location)) end
  local function stat(key, value)
    local label = trim(speakable(rom(key) or ""))
    if value ~= nil then parts[#parts + 1] = trim(label .. " " .. tostring(value)) end
  end
  stat("gSaveStatName_Player", speakable(tostring(session.name or session.playerName or "")))
  stat("gSaveStatName_Badges", call(SaveMenu.countBadges, session))
  if call(SaveMenu.hasDex, session) then stat("gSaveStatName_Pokedex", call(SaveMenu.countDex, session)) end
  local pt = session.playtime or session.playTime or {}
  local hours = tonumber(pt.hours or session.playTimeHours or session.hours) or 0
  local minutes = tonumber(pt.minutes or session.playTimeMinutes or session.minutes) or 0
  stat("gSaveStatName_Time", string.format("%d:%02d", hours, minutes))
  return table.concat(parts, ", ")
end

-- The dialogue line each phase draws (SaveMenu.draw).
local SAVE_MESSAGES = {
  confirm = "gText_WouldYouLikeToSaveTheGame",
  overwrite = "gText_AlreadySaveFile_WouldLikeToOverwrite",
  saving = "gText_SavingDontTurnOffThePower",
  saved = "gText_PlayerSavedTheGame",
}

local function saveMessage(SaveMenu)
  local phase = SaveMenu._phase
  if phase == "save_failed" then return speakable(tr("The game could not be saved.")) end
  local key = SAVE_MESSAGES[phase]
  if not key then return nil end
  local session = SaveMenu._session or {}
  local ctx = phase == "saved" and { playerName = tostring(session.name or session.playerName or "") } or nil
  return nonEmpty(speakable(rom(key, ctx) or ""))
end

-- src/ui/game3/save_menu.lua (layer "save", FRLG layout): the panel and the
-- question on entry, then YES/NO (`cursor`) queued behind it; each phase's
-- line (`_phase`) as it changes.  The save itself runs within one frame,
-- so "saving" is rarely seen; the saved line is.
Menus.saveMenu = {
  matches = Common.matcher("save", "src.ui.game3.save_menu"),
  poll = function(state, memo, entering)
    local SaveMenu = state.mod
    if SaveMenu._layout and SaveMenu._layout ~= "frlg" then return nil end
    local phase = SaveMenu._phase
    local parts, interrupt = {}, true
    if entering then
      -- the panel once; a return (from the help system) repeats the line
      if not memo.started then
        memo.started = true
        parts[#parts + 1] = sentences({ "Save", savePanel(SaveMenu) })
      end
      memo.phase = nil
    end
    if phase ~= memo.phase then
      memo.phase, memo.cursor = phase, nil
      parts[#parts + 1] = saveMessage(SaveMenu)
    end
    local cursor = (phase == "confirm" or phase == "overwrite") and SaveMenu.cursor or nil
    if cursor and (cursor ~= memo.cursor or entering) then
      if memo.cursor == nil and #parts == 0 then interrupt = false end
      parts[#parts + 1] = yesNo(cursor)
    end
    memo.cursor = cursor
    local text = sentences(parts)
    if text == "" then return nil end
    return text, interrupt
  end,
}

-- ----------------------------------------------------------------- help

-- Help text carries {PLAYER}, {RIVAL}, {PC_OWNER} and \n \l \p; the screen
-- expands and splits it with its file-local help_lines (Help.draw).
local function helpLines(Help, text)
  local helpLinesFn = upvalue(Help.draw, "help_lines")
  local lines = type(helpLinesFn) == "function" and call(helpLinesFn, text)
  if type(lines) ~= "table" then return nil end
  return lines
end

local function helpText(Help, text)
  local lines = helpLines(Help, text)
  if not lines then return nil end
  local clean = {}
  for _, line in ipairs(lines) do
    for _, part in ipairs(Common.lines(line)) do clean[#clean + 1] = part end
  end
  return nonEmpty(say(clean))
end

local HELP_CONTROLS = {
  welcome = "gText_HelpSystemControls_A_Next", article = "gText_HelpSystemControls_AorBtoCancel",
  main = "gText_HelpSystemControls_PickOkEnd", submenu = "gText_HelpSystemControls_PickOkCancel",
}

-- src/ui/game3/help_system.lua (Help.open, over every screen): `level`
-- welcome (the greeting), main (topics, with the description box for the
-- row), submenu (a topic's questions), article (question and answer, the
-- answer scrolling by line).  The whole answer is said when it opens; a
-- scroll says the line that came into view.
Menus.help = {
  matches = Common.matcher("help"),
  poll = function(state, memo, entering)
    local Help = state.mod
    if not (Help and Help.open and type(Help.pack) == "table") then return nil end
    local level, pack = Help.level, Help.pack
    local parts = {}
    if entering then
      parts[#parts + 1] = speakable(rom("gString_Help") or "")
      parts[#parts + 1] = nonEmpty(speakable(rom(HELP_CONTROLS[level]) or ""))
    end
    local newLevel = level ~= memo.level or (level == "submenu" and Help.topic ~= memo.topic)
    if level == "welcome" then
      if newLevel then parts[#parts + 1] = helpText(Help, pack.greetings) end
    elseif level == "article" then
      local article = Help.article
      if type(article) ~= "table" then return nil end
      if newLevel or article ~= memo.article then
        memo.scroll = Help.articleScroll or 0
        parts[#parts + 1] = helpText(Help, article.question)
        parts[#parts + 1] = helpText(Help, article.answer)
      elseif (Help.articleScroll or 0) ~= memo.scroll then
        local lines = helpLines(Help, article.answer) or {}
        local scroll = Help.articleScroll or 0
        local line = scroll > memo.scroll and lines[scroll + 7] or lines[scroll + 1]
        memo.scroll = scroll
        parts[#parts + 1] = line and nonEmpty(speakable(line)) or nil
      end
      memo.article = article
    else
      local rows = Help.rows or {}
      local cursor = Help.cursor or 1
      if newLevel or entering or cursor ~= memo.cursor then
        local row = rows[cursor]
        local label = type(row) == "table" and helpText(Help, row.label) or nil
        if label then
          if newLevel or entering then
            label = label .. ", " .. position(cursor, #rows)
            if level == "submenu" then
              parts[#parts + 1] = helpText(Help, pack.topics and pack.topics[Help.topic])
            end
          end
          parts[#parts + 1] = label
          -- the main level's description box follows the cursor
          if level == "main" and type(pack.descriptions) == "table" then
            parts[#parts + 1] = helpText(Help, pack.descriptions[row.id or 6])
          end
        end
      end
      memo.cursor = cursor
    end
    memo.level, memo.topic = level, Help.topic
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
}

-- ------------------------------------------------------------ quest log

-- src/ui/game3/quest_log.lua over game.questPlayback: the title
-- (PreviouslyOnYourQuest and the scene number until the last scene) when a
-- scene starts, then each event line as the playback reaches it (the
-- events are timed, so they queue).  The controls line once.
Menus.questLog = {
  matches = Common.matcher("quest_log"),
  poll = function(state, memo, entering)
    local playback = state.playback
    local UI = loaded("src.ui.game3.quest_log")
    if type(playback) ~= "table" or not UI or playback.done then return nil end
    local session = state.game and state.game.session or {}
    local parts, interrupt = {}, false
    if entering then
      parts[#parts + 1] = nonEmpty(speakable(tr("{A_BUTTON}NEXT   {B_BUTTON}SKIP")))
    end
    if playback.index ~= memo.index then
      memo.index, memo.event = playback.index, nil
      local title = call(UI.text, "PreviouslyOnYourQuest", {}, session)
      if title and not call(playback.isFinal, playback) then
        title = title .. " " .. tostring(call(playback.number, playback) or "")
      end
      parts[#parts + 1] = title and nonEmpty(speakable(title)) or nil
      interrupt = true
    end
    local event = call(playback.event, playback)
    if type(event) == "table" and event ~= memo.event then
      memo.event = event
      local text = call(UI.text, event.key, event.args, session)
      parts[#parts + 1] = text and nonEmpty(speakable(text)) or nil
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, interrupt
  end,
}

-- --------------------------------------------------------- trainer card

-- Joins a card side's text list (TrainerCard.frontTexts / backTexts, each
-- { id, text }) the way it reads on the card: a label and the values
-- after it are one part ("TIME 1:05"), other entries stand alone.
local function cardText(list)
  local parts, current = {}, nil
  for _, entry in ipairs(list or {}) do
    local id, text = tostring(entry.id or ""), trim(speakable(entry.text or ""))
    if text ~= "" then
      if id:find("_label$") then
        current = #parts + 1
        parts[current] = text
      elseif current and (id == "colon" or id == "minutes" or id:find("^link_")) then
        local glue = (id == "colon" or id == "minutes") and "" or " "
        parts[current] = parts[current] .. glue .. text
      elseif current and not id:find("^name") and not id:find("^id$") then
        parts[current] = parts[current] .. " " .. text
      else
        current = nil
        parts[#parts + 1] = text
      end
    end
  end
  return table.concat(parts, ", ")
end

local function cardFront(TrainerCard, card)
  local list = call(TrainerCard.frontTexts, card, false)
  local parts = { cardText(list) }
  if type(card.badges) == "table" then
    local earned = 0
    for i = 1, #card.badges do if card.badges[i] then earned = earned + 1 end end
    parts[#parts + 1] = "Badges, " .. position(earned, #card.badges)
  end
  local stars = tonumber(card.stars) or 0
  if stars > 0 then parts[#parts + 1] = stars == 1 and "1 star" or (stars .. " stars") end
  return sentences(parts)
end

-- src/ui/game3/trainer_card.lua (layer "trainer", FRLG card): the front on
-- entry, the back once the flip animation (`_flip`) ends on `side`
-- "back", the front again when flipped back.  Badges and stars are
-- pictures, so they are counted.
Menus.trainerCard = {
  matches = Common.matcher("trainer", "src.ui.game3.trainer_card"),
  poll = function(state, memo, entering)
    local TrainerCard = state.mod
    local card = TrainerCard._card
    if type(card) ~= "table" or TrainerCard._rse or TrainerCard._flip then return nil end
    local side = TrainerCard.side
    if not entering and memo.side == side then return nil end
    memo.side = side
    local text
    if side == "back" then
      text = cardText(call(TrainerCard.backTexts, card))
    else
      text = cardFront(TrainerCard, card)
      if entering then text = sentences({ "Trainer card", text }) end
    end
    if not text or text == "" then return nil end
    return text, true
  end,
}

-- --------------------------------------------------------- fame checker

-- The view FameCheckerUi's own draw builds (`_view`: rows, row, person,
-- msg, loc, obj, icons, help) is read once it matches the screen's fields;
-- the screen's helpers that build it fill caches, so speech never calls
-- them and waits one frame for the draw instead.
local function fameView(Fame)
  local v = Fame._view
  if type(v) ~= "table" or v.rows ~= Fame._rows or v.cursor ~= Fame.cursor or v.mode ~= Fame.mode
      or v.pickMode ~= Fame.pickMode or v.iconCursor ~= Fame.iconCursor
      or v.textPage ~= Fame.textPage or v.pages ~= Fame._pages then
    return nil
  end
  return v
end

-- src/ui/game3/fame_checker.lua (layer "fame_checker"): the list of people
-- (CANCEL last) with the message box for the row; START picks a person
-- (pickMode: their quote); A opens their six panels (mode "flavor":
-- iconCursor 0-5, a found panel's place and source, its text pages).
Menus.fameChecker = {
  matches = Common.matcher("fame_checker", "src.ui.game3.fame_checker"),
  poll = function(state, memo, entering)
    local Fame = state.mod
    local isFresh = fresh(memo, entering)
    local v = fameView(Fame)
    if not v then return nil end
    local parts = {}
    if Fame.mode == "flavor" then
      local slot = Fame.iconCursor or 0
      if memo.mode ~= "flavor" or slot ~= memo.slot or isFresh then
        local icons = v.icons or {}
        local icon = icons[slot]
        local count = 0
        for i = 0, 5 do if icons[i] ~= nil then count = count + 1 end end
        if memo.mode ~= "flavor" and type(v.row) == "table" then
          parts[#parts + 1] = speakable(v.row.label or "")
        end
        if type(icon) == "table" and icon.unlocked then
          parts[#parts + 1] = sentences({ v.loc and speakable(v.loc), v.obj and speakable(v.obj) })
          parts[#parts + 1] = v.msg and speakable(v.msg) or nil
        else
          parts[#parts + 1] = "unknown"
        end
        parts[#parts + 1] = "panel " .. position(slot + 1, math.max(count, slot + 1))
      elseif Fame.textPage ~= memo.textPage then
        parts[#parts + 1] = v.msg and speakable(v.msg) or nil
      end
      memo.slot = slot
    else
      local rows = v.rows or {}
      local moved = Fame.cursor ~= memo.cursor
      if isFresh or moved or memo.mode == "flavor" then
        local row = v.row
        local label = type(row) == "table" and nonEmpty(speakable(row.label or "")) or nil
        if label then
          if isFresh or memo.mode == "flavor" then label = label .. ", " .. position(Fame.cursor, #rows) end
          parts[#parts + 1] = label
          parts[#parts + 1] = v.msg and speakable(v.msg) or nil
          if isFresh then parts[#parts + 1] = v.help and nonEmpty(speakable(v.help)) or nil end
        end
      elseif Fame.pickMode ~= memo.pickMode then
        parts[#parts + 1] = v.msg and speakable(v.msg) or nil
      end
      memo.cursor = Fame.cursor
    end
    memo.mode, memo.pickMode, memo.textPage, memo.fresh = Fame.mode, Fame.pickMode, Fame.textPage, nil
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
}

-- ----------------------------------------------------------- Teachy TV

-- src/ui/game3/teachy_tv.lua (layer "teachy_tv"): the lesson list (`_rows`
-- labels, `cursor`, CANCEL last), then a lesson's text pages (`_pages`, a
-- new table per printer; `page`), spoken like dialogue.  The Poké Dude's
-- demonstration screens (bag, TM case, party, battle) are their own
-- screens on top.
Menus.teachyTv = {
  matches = Common.matcher("teachy_tv", "src.ui.game3.teachy_tv"),
  poll = function(state, memo, entering)
    local Ui = state.mod
    if Ui.closing then return nil end
    if Ui.state == "lesson" then
      memo.listCursor = nil
      if type(Ui._pages) ~= "table" then return nil end
      memo.printer = memo.printer or {}
      local text = printerSpeech(Ui._pages, Ui.page, memo.printer, state.game)
      if not text then return nil end
      return text, true
    end
    local rows = Ui._rows or {}
    local cursor = Ui.cursor or 1
    if not entering and memo.listCursor == cursor then return nil end
    local first = entering or memo.listCursor == nil
    memo.listCursor, memo.printer = cursor, nil
    local row = rows[cursor]
    local label = type(row) == "table" and nonEmpty(speakable(row.label or "")) or nil
    if not label then return nil end
    if first then label = label .. ", " .. position(cursor, #rows) end
    return label, true
  end,
}

-- ------------------------------------------------------- move relearner

-- The move window MoveRelearner.draw shows for the selected move (labels
-- Strings TYPE, POWER, ACCURACY, PP, EFFECT; values as PrintMoveInfo
-- formats them).  Read straight from the move data, not through the
-- screen's move_info, which caches.
local function moveInfo(moveId)
  local Pokemon = loaded("src.core.game3.pokemon")
  if not Pokemon then return nil end
  local name = call(Pokemon.moveName, moveId)
  if not name then return nil end
  local row = call(Pokemon.battleMove, moveId) or {}
  local power = tonumber(row.power) or 0
  local accuracy = tonumber(row.accuracy) or 0
  -- the move data holds a type id; its name is the cart's gTypeNames entry
  -- (src/core/game3/battle/types.lua Types.name).  The screen passes the
  -- id as a string to its badge drawer, which only knows names, so upstream
  -- draws every badge as NORMAL; speech says the move's real type.
  local typeName
  local Types = loaded("src.core.game3.battle.types")
  if tonumber(row.type) and Types then typeName = call(Types.name, tonumber(row.type)) end
  typeName = speakable(typeName or tostring(row.type or "NORMAL"):upper():gsub("^TYPE_", ""):gsub("_", " "))
  local SummaryData = loaded("src.core.game3.summary_data")
  local desc = SummaryData and call(SummaryData.moveDescription, moveId, name)
  return sentences({
    speakable(name),
    speakable(tr("TYPE")) .. " " .. typeName,
    speakable(tr("POWER")) .. " " .. (power >= 2 and tostring(power) or "---"),
    speakable(tr("ACCURACY")) .. " " .. (accuracy > 0 and tostring(accuracy) or "---"),
    speakable(tr("PP")) .. " " .. tostring(tonumber(row.pp) or 0),
    desc and desc ~= "" and (speakable(tr("EFFECT")) .. " " .. speakable(desc)) or nil,
  })
end

local function relearnerRow(MoveRelearner, cursor)
  local moves = MoveRelearner._moves or {}
  if moves[cursor] then return moveInfo(moves[cursor]) end
  if cursor == #moves + 1 then return speakable(rom("gFameCheckerText_Cancel") or "CANCEL") end
  return nil
end

-- src/ui/game3/move_relearner.lua (layer "move_relearner"): `state` list
-- (the moves, CANCEL last, under the prompt "Teach which move to ...?"),
-- message or yesno (`prompt`, YES/NO from `yesNoCursor`).  Forgetting a
-- move opens the summary screen, which speaks for itself.
Menus.moveRelearner = {
  matches = Common.matcher("move_relearner", "src.ui.game3.move_relearner"),
  poll = function(state, memo, entering)
    local MR = state.mod
    if not MR.open then return nil end
    local parts, interrupt = {}, true
    local prompt = MR.prompt
    local promptChanged = prompt ~= memo.prompt or MR.state ~= memo.state
    if MR.state == "list" then
      local cursor = MR.cursor or 1
      if entering or promptChanged or cursor ~= memo.cursor then
        local row = relearnerRow(MR, cursor)
        if row then
          if entering or promptChanged then
            if entering then parts[#parts + 1] = prompt and speakable(prompt) or nil end
            row = row .. ", " .. position(cursor, #(MR._moves or {}) + 1)
          end
          parts[#parts + 1] = row
        end
      end
      memo.cursor, memo.choice = cursor, nil
    else
      if promptChanged then
        memo.choice = nil
        parts[#parts + 1] = prompt and nonEmpty(speakable(prompt)) or nil
      end
      if MR.state == "yesno" then
        local choice = MR.yesNoCursor
        if choice ~= memo.choice then
          if memo.choice == nil and #parts == 0 then interrupt = false end
          parts[#parts + 1] = yesNo(choice)
        end
        memo.choice = choice
      end
    end
    memo.prompt, memo.state = prompt, MR.state
    local text = sentences(parts)
    if text == "" then return nil end
    return text, interrupt
  end,
}

-- ------------------------------------------------- evolution, egg hatching

-- Both scenes print through the global message box and yes/no
-- (src/ui/game3/message.lua, choice.lua) and draw them themselves, under
-- their own layer, so the dialogue presenters are run here on the scene's
-- behalf, with their own memos.
local function sceneDialogue(state, memo, parts)
  local Message = loaded("src.ui.game3.message")
  local spoke = false
  if Message and Message.open and type(Message._pages) == "table" then
    local pages = Message._pages
    if memo.pages ~= pages then memo.pages, memo.message = pages, {} end
    local inner = Top._proxy(pages, "message", { mod = Message, game = state.game })
    local text = Dialogue.message.poll(inner, memo.message, false)
    if text then
      parts[#parts + 1] = text
      spoke = true
    end
  end
  local Choice = loaded("src.ui.game3.choice")
  if Choice and Choice.active and Choice.done then
    local key = Choice.done
    if memo.choiceKey ~= key then memo.choiceKey, memo.choice = key, {} end
    local inner = Top._proxy(key, "choice", { mod = Choice, game = state.game })
    local text, interrupt = Dialogue.choice.poll(inner, memo.choice, false)
    if text then
      parts[#parts + 1] = text
      if not spoke then return interrupt end
    end
  end
  return true
end

-- src/ui/game3/evolution_scene.lua (layer "evolution_scene", also over a
-- battle): its messages and move-learning yes/no; while the Pokémon
-- flashes (`_state` "cycle") and `_canStop`, the B hint once, queued.
Menus.evolution = {
  matches = Common.matcher("evolution_scene", "src.ui.game3.evolution_scene"),
  poll = function(state, memo)
    local Evo = state.mod
    local parts = {}
    local interrupt = sceneDialogue(state, memo, parts)
    if Evo._state == "cycle" and Evo._canStop and not memo.hinted then
      memo.hinted = true
      if #parts == 0 then interrupt = false end
      parts[#parts + 1] = "Press B to stop the evolution."
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, interrupt
  end,
}

-- src/ui/game3/egg_hatch.lua (layer "egg_hatch"): "Egg hatching." on
-- entry (the egg cracks without text), then its messages and the nickname
-- yes/no; the naming keyboard is its own screen.
Menus.eggHatch = {
  matches = Common.matcher("egg_hatch", "src.ui.game3.egg_hatch"),
  poll = function(state, memo)
    local parts = {}
    local opened = not memo.said
    if opened then
      memo.said = true
      parts[1] = "Egg hatching."
    end
    local interrupt = sceneDialogue(state, memo, parts)
    local text = sentences(parts)
    if text == "" then return nil end
    if opened and #parts == 1 then interrupt = false end
    return text, interrupt
  end,
}

-- ---------------------------------------------------- script list menus

-- src/core/game3/scripting/natives_listmenu.lua (layer "script_list_menu",
-- module field Menu): the elevator floors, badge list, wireless lectures,
-- Berry Powder exchange.  `labels` are strings or { text, tail }; the
-- cursor is `scroll + row`, out of `count`.  The question above the list
-- stays visible, so on entry the list queues behind it.
local function listLabel(label)
  if type(label) == "table" then
    return sentences({ speakable(label.text or ""), nonEmpty(trim(speakable(label.tail or ""))) })
  end
  return speakable(label or "")
end

Menus.scriptListMenu = {
  matches = function(state)
    if type(state) ~= "table" or state.gen3 ~= "script_list_menu" or not state.layer then return false end
    local ListMenu = loaded("src.core.game3.scripting.natives_listmenu")
    return ListMenu ~= nil and state.layer.mod == ListMenu.Menu
  end,
  poll = function(state, memo, entering)
    local Menu = state.mod
    if not Menu.open or type(Menu.labels) ~= "table" then return nil end
    local index = (Menu.scroll or 0) + (Menu.row or 1)
    if not entering and memo.index == index then return nil end
    memo.index = index
    local label = nonEmpty(listLabel(Menu.labels[index]))
    if not label then return nil end
    local interrupt = true
    if entering then
      label = label .. ", " .. position(index, Menu.count or #Menu.labels)
      local Message = loaded("src.ui.game3.message")
      if Message and Message.open then interrupt = false end
    end
    return label, interrupt
  end,
}

-- ------------------------------------------------------ passive overlays

-- Overlays that take no input are registered with Top.addAmbient and
-- polled every frame beside the top screen; their speech queues.  Each
-- source returns a proxy keyed so that one showing gets one memo.

local ambientKeys = setmetatable({}, { __mode = "k" })
local function gameKey(game, kind)
  local keys = ambientKeys[game]
  if not keys then
    keys = {}
    ambientKeys[game] = keys
  end
  keys[kind] = keys[kind] or {}
  return keys[kind]
end

-- Map names: src/ui/game3/map_name_popup.lua (`_name`, already with the
-- floor; active while sliding in, holding or out) and the dungeon entry
-- preview (src/ui/game3/map_preview_screen.lua `_active`, `_name`).  One
-- proxy per game, so a name is said once per new name: walking back and
-- forth inside one town says nothing, a new place says its name.
Menus.mapName = {
  matches = Common.matcher("map_name"),
  poll = function(state, memo)
    local name
    local Preview = loaded("src.ui.game3.map_preview_screen")
    if Preview and Preview._active and type(Preview._name) == "string" then name = Preview._name end
    local Popup = loaded("src.ui.game3.map_name_popup")
    if not name and Popup and Popup._state and Popup.STATE and Popup._state ~= Popup.STATE.IDLE then
      name = Popup._name
    end
    -- Hoenn's popups keep the name in their own window (Popup.Rse, Popup.Rs)
    for _, Native in ipairs(Popup and { Popup.Rse, Popup.Rs } or {}) do
      if not name and type(Native) == "table" and Native.task and type(Native.window) == "table" then
        name = Native.window.name
      end
    end
    if type(name) ~= "string" or name == "" or name == memo.name then return nil end
    memo.name = name
    return nonEmpty(speakable(tr(name))), false
  end,
}

-- src/ui/game3/elevator_window.lua: "Now on" and the floor while the
-- elevator script runs.  `visible` is read with the owner check
-- ElevatorWindow.isVisible makes (which would hide a stale window).
Menus.elevatorWindow = {
  matches = Common.matcher("elevator_window"),
  poll = function(state, memo)
    if memo.said then return nil end
    local Window = state.mod
    local label = Window and Window._label
    if not label then return nil end
    memo.said = true
    return sentences({ speakable(rom("gText_NowOn") or ""), speakable(label) }), false
  end,
}

-- src/ui/game3/coins_box.lua: the Game Corner coins when the box appears
-- and whenever the amount changes.  (The money box is gen3/Items.lua's.)
Menus.coinsBox = {
  matches = Common.matcher("coins_box"),
  poll = function(state, memo)
    local Box = state.mod
    local amount = Box and Box._amount
    if amount == nil or amount == memo.amount then return nil end
    memo.amount = amount
    local text = call(Box.countText, amount)
    return nonEmpty(trim(speakable(text or ""))), false
  end,
}

local function fieldPhase(game)
  return type(game) == "table" and game.phase == "field"
end

Top.addAmbient(function(game, proxy)
  if not fieldPhase(game) then return nil end
  return proxy(gameKey(game, "map_name"), "map_name", { game = game })
end)

Top.addAmbient(function(game, proxy)
  local Window = loaded("src.ui.game3.elevator_window")
  if not (fieldPhase(game) and Window) then return nil end
  local Space = loaded("src.core.game3.scripting.space")
  local on = Window.visible == true and Window._owner == (Space and Space.vm or nil)
  local token = Top._edge("elevator_window", on)
  return token and proxy(token, "elevator_window", { mod = Window, game = game }) or nil
end)

Top.addAmbient(function(game, proxy)
  local Box = loaded("src.ui.game3.coins_box")
  if not (fieldPhase(game) and Box) then return nil end
  local token = Top._edge("coins_box", Box.visible == true)
  return token and proxy(token, "coins_box", { mod = Box, game = game }) or nil
end)

Menus.ordered = {
  Menus.intro,
  Menus.title,
  Menus.mainMenu,
  Menus.saveError,
  Menus.newGame,
  Menus.naming,
  Menus.startMenu,
  Menus.options,
  Menus.controls,
  Menus.saveMenu,
  Menus.help,
  Menus.questLog,
  Menus.trainerCard,
  Menus.fameChecker,
  Menus.teachyTv,
  Menus.moveRelearner,
  Menus.evolution,
  Menus.eggHatch,
  Menus.scriptListMenu,
  Menus.mapName,
  Menus.elevatorWindow,
  Menus.coinsBox,
}

return Menus
