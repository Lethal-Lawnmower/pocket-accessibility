-- Hoenn boot presenters (Ruby, Sapphire, Emerald): intro, title, main menu,
-- Birch's speech with its gender, name and yes/no menus, and the screens
-- title button combos open (clear save, reset clock, Berry fix).
--
-- These are objects in `boot.custom` (src/ui/game3/boot_modules.lua), kept
-- by gen3/Top.lua as one proxy per object.  Their text goes through a text
-- printer of src/ui/game3/rse/scene_kit.lua; HoennCommon.printerSay reads
-- the whole page from the printer's tokens so a page is spoken as it starts,
-- the pacing dialogue has.  Every field is read, never written.

local Common = require("src.access.screens.gen3.Common")
local H = require("src.access.screens.gen3.HoennCommon")
local Menus = require("src.access.screens.gen3.Menus")

local Boot = {}

local rom, say, sentences, position = H.rom, H.say, H.sentences, Common.position

-- src/ui/game3/rse/intro_emerald.lua, src/ui/game3/rs/intro.lua: any of A,
-- START, SELECT skips.  The copyright card and the scenes are images.
Boot.intro = {
  matches = Common.matcher("hoenn_intro"),
  poll = function(_, memo)
    if memo.said then return nil end
    memo.said = true
    return "Intro. Press start to skip.", false
  end,
}

-- src/ui/game3/rse/title_rse.lua, src/ui/game3/rs/title.lua: start counts
-- from "phase3" on (the logo and PRESS START are images).
Boot.title = {
  matches = Common.matcher("hoenn_title"),
  poll = function(state, memo)
    if memo.said or state.key.phase ~= "phase3" then return nil end
    memo.said = true
    return sentences({ Menus.editionName(), "Press start." }), false
  end,
}

-- The row labels the two main menus print, by item id.
local MENU_KEYS = {
  CONTINUE = { "gText_MainMenuContinue", "gMainMenuString_Continue" },
  NEW_GAME = { "gText_MainMenuNewGame", "gMainMenuString_NewGame" },
  OPTION = { "gText_MainMenuOption", "gMainMenuString_Option" },
  MYSTERY_GIFT = { "gText_MainMenuMysteryGift" },
  MYSTERY_GIFT2 = { "gText_MainMenuMysteryGift2" },
  MYSTERY_EVENTS = { "gText_MainMenuMysteryEvents", "gMainMenuString_MysteryEvents" },
  EXIT = { "gText_MenuExit", "SystemText_Exit" },
}

-- The CONTINUE window (MainMenu:_drawContinue, Menu:_drawContinue).
local function continuePanel(menu)
  local info = menu.info
  if type(info) ~= "table" then return nil end
  local function stat(keys, value)
    local label = H.first(keys)
    return label and (label .. " " .. tostring(value)) or nil
  end
  local parts = {
    stat({ "gText_ContinueMenuPlayer", "gMainMenuString_Player" }, say(info.name or "") or ""),
    stat({ "gText_ContinueMenuTime", "gMainMenuString_Time" },
      string.format("%d:%02d", info.hours or 0, info.minutes or 0)),
  }
  -- Emerald draws the POKéDEX count only once it has a Pokédex; Ruby and
  -- Sapphire draw it always.
  if info.hasDex or not H.romHas("gText_ContinueMenuPokedex") then
    parts[#parts + 1] = stat({ "gText_ContinueMenuPokedex", "gMainMenuString_Pokedex" }, info.dexCount or 0)
  end
  parts[#parts + 1] = stat({ "gText_ContinueMenuBadges", "gMainMenuString_Badges" }, info.badges or 0)
  return H.join(parts)
end

-- main_menu_rse.lua, rs/main_menu.lua: `items`, 1-based `cursor`, `state`.
-- Error pages are printers (`errorPrinter` in Emerald, `printer` in Ruby).
Boot.mainMenu = {
  matches = Common.matcher("hoenn_main_menu"),
  poll = function(state, memo, entering)
    local menu = state.key
    if entering then memo.fresh = true end
    local printer = menu.errorPrinter or menu.printer
    if printer then
      local text = H.printerSay(printer, memo, state.game)
      if text then return text, true end
      return nil
    end
    if menu.state ~= "input" then return nil end
    local cursor = menu.cursor or 1
    if not memo.fresh and memo.cursor == cursor then return nil end
    local items = menu.items or {}
    local id = items[cursor]
    local label = id and MENU_KEYS[id] and H.first(MENU_KEYS[id])
    if not label then return nil end
    local text = label
    if memo.fresh then text = "Main menu. " .. text .. ", " .. position(cursor, #items) end
    if id == "CONTINUE" then text = sentences({ text, continuePanel(menu) }) end
    memo.cursor, memo.fresh = cursor, nil
    return text, true
  end,
}

-- rse/birch_speech.lua and rs/birch_speech.lua: one object for the whole
-- scene.  `printer` (new per line), `genderMenu`, in Ruby and Sapphire
-- `nameMenu` (five rows: NEW NAME and four preset names), and `yesNo`, read
-- as they are drawn.  The naming keyboard is its own layer.
local GENDER_KEYS = { [0] = { "gText_BirchBoy", "gBirchText_Boy" }, [1] = { "gText_BirchGirl", "gBirchText_Girl" } }

local function nameRow(birch, cursor)
  local names = H.try(birch.presetNames, birch)
  return type(names) == "table" and say(names[cursor + 1]) or nil
end

Boot.birch = {
  matches = Common.matcher("hoenn_birch"),
  poll = function(state, memo)
    local birch = state.key
    local parts, interrupt = {}, true
    if birch.printer then
      local text = H.printerSay(birch.printer, memo, state.game)
      if text then parts[#parts + 1] = text end
    end
    local function menu(open, name, label, count)
      if not open then
        memo[name] = nil
        return
      end
      local cursor = open.cursor or 0
      if memo[name] == cursor then return end
      local opening = memo[name] == nil
      memo[name] = cursor
      local text = label(cursor)
      if not text then return end
      if opening and count then text = text .. ", " .. position(cursor + 1, count) end
      if opening and #parts == 0 then interrupt = false end
      parts[#parts + 1] = text
    end
    menu(birch.genderMenu, "gender", function(cursor) return H.first(GENDER_KEYS[cursor]) end, 2)
    menu(birch.nameMenu, "name", function(cursor) return nameRow(birch, cursor) end, 5)
    menu(birch.yesNo, "yesNo", function(cursor) return H.yesNo(cursor + 1) end)
    local text = sentences(parts)
    if not text then return nil end
    return text, interrupt
  end,
}

-- Title combos.  rse/clear_save_screen.lua (printer, yesNo) and
-- rs/clear_save_screen.lua (draws its own strings, `cursor`, `clearing`);
-- reset_rtc_screen in both (`msg`, `prompt`, `input`, `selection`);
-- rse/berry_fix_screen.lua (SCENE_TEXT by `state`).
local RTC_FIELDS = { "days", "hours", "minutes", "seconds" }
local function rtcInput(combo)
  local input = combo.input
  if type(input) ~= "table" then return nil end
  local parts = {}
  for _, name in ipairs(RTC_FIELDS) do
    if input[name] ~= nil then parts[#parts + 1] = tostring(input[name]) .. " " .. name end
  end
  return H.join(parts)
end

Boot.combo = {
  matches = Common.matcher("hoenn_combo"),
  poll = function(state, memo)
    local combo = state.key
    local parts = {}
    local printer = combo.printer or combo.msg
    if printer then
      local text = H.printerSay(printer, memo, state.game)
      if text then parts[#parts + 1] = text end
    end
    local meta = getmetatable(combo)
    local scenes = type(meta) == "table" and meta.SCENE_TEXT
    if scenes and scenes[combo.state] and memo.scene ~= combo.state then
      memo.scene = combo.state
      parts[#parts + 1] = say(rom(scenes[combo.state]))
    end
    -- Ruby's clear save draws its own strings once the menu is shown
    if combo.clear and combo.menuShown then
      local key = combo.clearing and "gSystemText_ClearingData" or "gSystemText_ClearAllSaveDataPrompt"
      if memo.question ~= key then
        memo.question = key
        parts[#parts + 1] = say(rom(key))
      end
      if memo.cursor ~= combo.cursor and not combo.clearing then
        memo.cursor = combo.cursor
        parts[#parts + 1] = H.yesNo((combo.cursor or 0) + 1)
      end
    end
    if combo.yesNo and memo.yn ~= combo.yesNo.cursor then
      memo.yn = combo.yesNo.cursor
      parts[#parts + 1] = H.yesNo((combo.yesNo.cursor or 0) + 1)
    end
    local time = rtcInput(combo)
    if time and (memo.time ~= time or memo.selection ~= combo.selection) then
      memo.time, memo.selection = time, combo.selection
      parts[#parts + 1] = time
    end
    local text = sentences(parts)
    if not text then return nil end
    return text, true
  end,
}

Boot.ordered = { Boot.intro, Boot.title, Boot.mainMenu, Boot.birch, Boot.combo }

return Boot
