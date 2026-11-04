-- Hoenn menu presenters (Ruby, Sapphire, Emerald).
local Common = require("src.access.screens.gen3.Common")
local H = require("src.access.screens.gen3.HoennCommon")

local Hoenn = {}

local say, rom, sentences, position = H.say, H.rom, H.sentences, Common.position

-- ------------------------------------------------------------- OPTION
-- src/ui/game3/rse/option_menu.lua (Emerald: `_st.pages`, cart rows
-- { cart = { label, key, choices, frame } }) and rs/option_menu.lua (Ruby,
-- Sapphire: `_pages`, rows { native = i }, `_data.rows[i]`, `_pending`).
-- Both keep the engine's rows and our ACCESSIBILITY page as { label, value },
-- and CANCEL as the row after the last.

local function emeraldRow(OptionMenu, page, index)
  local row = page.rows[index]
  if not row then return say(rom("gText_OptionMenuCancel")), nil end
  local cart = row.cart
  if not cart then
    local value = row.value and H.try(row.value, OptionMenu._st.ctx)
    return say(row.label), value and say(tostring(value)) or nil
  end
  local Options = H.loaded("src.core.game3.options")
  local block = Options and H.try(Options.block, OptionMenu._st.ctx.options)
  local current = block and tonumber(block[cart.key]) or nil
  local value
  if current then
    if cart.frame then
      value = H.join({ say(rom("gText_FrameType")), tostring(current + 1) }, " ")
    else
      value = say(rom(cart.choices[current + 1]))
    end
  end
  return say(rom(cart.label)), value
end

local RUBY_KEYS = { "textSpeed", "battleScene", "battleStyle", "sound", "buttonMode", "frameType" }

local function rubyRow(Menu, page, index)
  local row = page.rows[index]
  local data = Menu._data
  if not (type(data) == "table" and type(data.rows) == "table") then return nil end
  if not row then
    local cancel = data.rows[#RUBY_KEYS + 1]
    return cancel and say(cancel.text), nil
  end
  if not row.native then
    local ctx = { session = Menu._session, game = Menu._game, options = Menu._engine }
    local value = row.value and H.try(row.value, ctx)
    return say(row.label), value and say(tostring(value)) or nil
  end
  local native = data.rows[row.native]
  if type(native) ~= "table" then return nil end
  local key = RUBY_KEYS[row.native]
  local current = type(Menu._pending) == "table" and tonumber(Menu._pending[key]) or nil
  local value
  if current then
    if key == "frameType" then
      value = H.join({ say(data.frameLabel), tostring(current + 1) }, " ")
    else
      local choice = (native.choices or {})[current + 1]
      value = choice and say(choice.text)
    end
  end
  return say(native.text), value
end

local function optionPoll(state, memo, entering, readRow, pagesOf, title)
  local ShaderFX = H.loaded("src.ui.game3.shaderfx_menu")
  if ShaderFX and H.try(ShaderFX.isOpen) then return nil end
  local Menu = state.mod
  local pages = pagesOf(Menu)
  local page = type(pages) == "table" and pages[#pages] or nil
  if type(page) ~= "table" then return nil end
  local index = page.index or 1
  local label, value = readRow(Menu, page, index)
  local newPage = page ~= memo.page
  if not entering and not newPage and memo.index == index and memo.value == value then return nil end
  if not label then return nil end
  local moved = memo.index ~= index
  memo.page, memo.index, memo.value = page, index, value
  local text
  if entering or newPage or moved then
    text = H.join({ label, value })
    if entering or newPage then
      text = sentences({ say(title(Menu, page)), H.join({ text, position(index, #page.rows + 1) }) })
    end
  else
    text = value
  end
  if not text then return nil end
  return text, true
end

Hoenn.optionEmerald = {
  matches = Common.matcher("option", "src.ui.game3.rse.option_menu"),
  poll = function(state, memo, entering)
    return optionPoll(state, memo, entering, emeraldRow,
      function(Menu) return Menu._st and Menu._st.pages end,
      function(_, page) return page.title end)
  end,
}

Hoenn.optionRuby = {
  matches = Common.matcher("option", "src.ui.game3.rs.option_menu"),
  poll = function(state, memo, entering)
    return optionPoll(state, memo, entering, rubyRow,
      function(Menu) return Menu._pages end,
      function(Menu, page) return page.top and Menu._data and Menu._data.title or page.title end)
  end,
}

-- --------------------------------------------------------------- save
-- src/ui/game3/save_menu.lua with `_layout` "rse" or "rs" (drawRse, drawRs,
-- drawDialog): the panel, the phase's line, YES/NO (`cursor`) while it asks.
local SAVE_LINES = {
  confirm = "gText_ConfirmSave", overwrite = "gText_AlreadySavedFile", saving_msg = "gText_SavingDontTurnOff",
  saving = "gText_SavingDontTurnOff", saved = "gText_PlayerSavedGame", save_failed = "gText_SaveError",
}

local function savePanel(SaveMenu)
  local session = SaveMenu._session or {}
  local function stat(key, value)
    local label = say(rom(key))
    return label and H.join({ label, tostring(value) }, " ") or nil
  end
  local Strings = H.loaded("src.core.Strings")
  local location = H.try(SaveMenu.locationName, session)
  local place = location and Strings and say(H.try(Strings, location)) or say(location)
  local pt = session.playtime or session.playTime or {}
  return H.join({ place, stat("gText_SavingPlayer", say(tostring(session.name or session.playerName or "")) or ""),
    stat("gText_SavingBadges", H.try(SaveMenu.countBadges, session) or 0),
    H.try(SaveMenu.hasDex, session) and stat("gText_SavingPokedex", H.try(SaveMenu.countDex, session) or 0) or nil,
    stat("gText_SavingTime", string.format("%d:%02d", tonumber(pt.hours or session.hours) or 0,
      tonumber(pt.minutes or session.minutes) or 0)) })
end

local function saveLine(SaveMenu)
  local session = SaveMenu._session or {}
  local phase = SaveMenu._phase
  local pyramid
  if phase == "confirm" then
    local Rse = H.loaded("src.core.game3.rse.init")
    pyramid = Rse and H.try(Rse.system, "pyramid")
    if pyramid and H.try(pyramid.inPyramid, session) then
      local TextIr = H.loaded("src.core.game3.scripting.text_ir")
      local man = H.try(pyramid.manifest)
      local line = TextIr and man and H.try(TextIr.toPlain, man.confirmRest.ir)
      if line then return say(line) end
    end
  end
  local key = SAVE_LINES[phase]
  if not key then return nil end
  return say(rom(key, { playerName = tostring(session.name or session.playerName or "") }))
end

Hoenn.saveMenu = {
  matches = function(state)
    if type(state) ~= "table" or state.gen3 ~= "save" or not state.layer then return false end
    local mod = package.loaded["src.ui.game3.save_menu"]
    return mod ~= nil and state.layer.mod == mod and mod._layout ~= nil and mod._layout ~= "frlg"
  end,
  poll = function(state, memo, entering)
    local SaveMenu = state.mod
    local phase = SaveMenu._phase
    local parts, interrupt = {}, true
    if entering and not memo.started then
      memo.started = true
      parts[#parts + 1] = sentences({ "Save", savePanel(SaveMenu) })
    end
    if phase ~= memo.phase and not (phase == "saving" and memo.phase == "saving_msg") then
      memo.cursor = nil
      parts[#parts + 1] = saveLine(SaveMenu)
    end
    memo.phase = phase
    local cursor = (phase == "confirm" or phase == "overwrite") and SaveMenu.cursor or nil
    if cursor and cursor ~= memo.cursor then
      if memo.cursor == nil and #parts == 0 then interrupt = false end
      parts[#parts + 1] = H.yesNo(cursor)
    end
    memo.cursor = cursor
    local text = sentences(parts)
    if not text then return nil end
    return text, interrupt
  end,
}

-- --------------------------------------------------------- trainer card
-- Emerald: src/ui/game3/trainer_card.lua with `_rse` (frontTextsRse,
-- backTextsRse: entries { text, x, y }).  Ruby and Sapphire:
-- rs/trainer_card.lua (T.texts(card, side, colon): { id, text }, labels are
-- images on the card).  Rows on one line are read together; badges and stars
-- are pictures, so they are counted.

local function byLine(list)
  local rows, order = {}, {}
  for _, entry in ipairs(list or {}) do
    local y = entry.y
    if not rows[y] then
      rows[y] = {}
      order[#order + 1] = y
    end
    local text = say(entry.text)
    if text then table.insert(rows[y], text) end
  end
  table.sort(order)
  local out = {}
  for _, y in ipairs(order) do
    local line = table.concat(rows[y], " "):gsub(" : ", ":"):gsub(" :", ":"):gsub("%s+", " ")
    if line ~= "" then out[#out + 1] = line end
  end
  return out
end

local function badgesAndStars(card)
  local parts = {}
  if type(card.badges) == "table" then
    local earned = 0
    for i = 1, 8 do if card.badges[i] then earned = earned + 1 end end
    parts[#parts + 1] = "Badges, " .. position(earned, 8)
  end
  local stars = tonumber(card.stars) or 0
  if stars > 0 then parts[#parts + 1] = stars == 1 and "1 star" or (stars .. " stars") end
  return parts
end

Hoenn.trainerEmerald = {
  matches = function(state)
    if type(state) ~= "table" or state.gen3 ~= "trainer" or not state.layer then return false end
    local mod = package.loaded["src.ui.game3.trainer_card"]
    return mod ~= nil and state.layer.mod == mod and mod._rse == true
  end,
  poll = function(state, memo, entering)
    local T = state.mod
    local card = T._card
    if type(card) ~= "table" or T._flip then return nil end
    local side = T.side
    if not entering and memo.side == side then return nil end
    memo.side = side
    local parts
    if side == "back" then
      parts = byLine(H.try(T.backTextsRse, card))
    else
      parts = byLine(H.try(T.frontTextsRse, card, false))
      for _, part in ipairs(badgesAndStars(card)) do parts[#parts + 1] = part end
      if entering then table.insert(parts, 1, "Trainer card") end
    end
    local text = sentences(parts)
    if not text then return nil end
    return text, true
  end,
}

-- The fields rs/trainer_card.lua draws from images, in our words.
local RUBY_LABELS = {
  name = "name", id = "ID", money = "money", seen = "POKéDEX", time = "time",
  hof = "Hall of Fame debut", wins = "link battle wins", losses = "losses", trade = "POKéMON trades",
  blender = "POKéBLOCKS with friends", contest = "contests won with friends",
  towerWins = "Battle Tower wins", towerBest = "best streak",
}

Hoenn.trainerRuby = {
  matches = Common.matcher("trainer", "src.ui.game3.rs.trainer_card"),
  poll = function(state, memo, entering)
    local T = state.mod
    local card = T._card
    if type(card) ~= "table" or T._flip or T._phase == "setup" or T._phase == "in" then return nil end
    local side = T.side
    if not entering and memo.side == side then return nil end
    local list = H.try(T.texts, card, side, true)
    if type(list) ~= "table" then return nil end
    memo.side = side
    local parts = {}
    for _, row in ipairs(list) do
      local id = tostring(row.id)
      if not id:find("Label$") then
        local value = say(row.text)
        if id == "time" and value then value = value:gsub("%s*:%s*", ":") end
        if value then
          if id == "name" and side == "back" then parts[#parts + 1] = value
          elseif RUBY_LABELS[id] then parts[#parts + 1] = RUBY_LABELS[id] .. " " .. value
          else parts[#parts + 1] = value end
        end
      end
    end
    if side ~= "back" then
      for _, part in ipairs(badgesAndStars(card)) do parts[#parts + 1] = part end
      if entering then table.insert(parts, 1, "Trainer card") end
    end
    local text = sentences(parts)
    if not text then return nil end
    return text, true
  end,
}

-- ------------------------------------------------- Birch's bag: the starter
-- rse/starter_choose.lua (layer "starter_choose"; `active()`): `selection`
-- 0-2, `label` { category, name }, `message` key, `state`, `confirm` (yes/no),
-- `mon` { species } once chosen.
Hoenn.starter = {
  matches = Common.matcher("starter_choose"),
  poll = function(state, memo)
    local Choose = H.loaded("src.ui.game3.rse.starter_choose")
    local screen = Choose and H.try(Choose.active)
    if type(screen) ~= "table" then return nil end
    local parts = {}
    if screen.message and screen.message ~= memo.message then
      memo.message = screen.message
      parts[#parts + 1] = say(rom(screen.message))
    end
    local label = screen.label
    if type(label) == "table" and (memo.selection ~= label.selection) then
      local first = memo.selection == nil
      memo.selection = label.selection
      local text = H.join({ say(label.name), say(label.category) })
      if text and first then text = H.join({ text, position(label.selection + 1, 3) }) end
      parts[#parts + 1] = text
    elseif type(label) ~= "table" and screen.state ~= "input" then
      memo.selection = nil
    end
    local confirm = screen.confirm
    if type(confirm) == "table" then
      if memo.yes ~= confirm.cursor then
        memo.yes = confirm.cursor
        parts[#parts + 1] = H.yesNo((confirm.cursor or 0) + 1)
      end
    else
      memo.yes = nil
    end
    local text = sentences(parts)
    if not text then return nil end
    return text, true
  end,
}

-- ------------------------------------------------------------ wall clock
-- rse/wall_clock.lua (layer "wall_clock"; `active()`): `mode` set or view,
-- `state`, `t` { hours, minutes, period, moveDir }, `confirm`.  The clock is a
-- picture, so the time is said in words: on each change while setting (every
-- five minutes while a hand is moving fast), and whole when it stops.
local function clockTime(t)
  local hours = (tonumber(t.hours) or 0) % 12
  if hours == 0 then hours = 12 end
  return string.format("%d:%02d %s", hours, tonumber(t.minutes) or 0, t.period == 1 and "PM" or "AM")
end

Hoenn.wallClock = {
  matches = Common.matcher("wall_clock"),
  poll = function(state, memo)
    local Clock = H.loaded("src.ui.game3.rse.wall_clock")
    local clock = Clock and H.try(Clock.active)
    if type(clock) ~= "table" or type(clock.t) ~= "table" then return nil end
    local st = clock.state
    if st == "wait_fade_in" then return nil end
    local parts = {}
    local time = clockTime(clock.t)
    if not memo.opened then
      memo.opened, memo.time = true, time
      if clock.mode == "view" then
        parts[#parts + 1] = "Wall clock, " .. time
      else
        parts[#parts + 1] = "Set the clock. Left and right turn the hands, A confirms. " .. time
      end
    elseif st == "set_input" and memo.time ~= time then
      local moving = (clock.t.moveDir or 0) ~= 0 and (tonumber(clock.t.moveSpeed) or 0) > 10
      if not moving or (tonumber(clock.t.minutes) or 0) % 5 == 0 then
        memo.time = time
        parts[#parts + 1] = time
      end
    end
    if (st == "ask_confirm" or st == "confirm_input") and not memo.asked then
      memo.asked = true
      parts[#parts + 1] = H.first({ "gText_IsThisTheCorrectTime", "gOtherText_CorrectTimePrompt" })
      memo.time = time
      parts[#parts + 1] = time
    elseif st == "set_input" then
      memo.asked = nil
    end
    local confirm = clock.confirm
    if type(confirm) == "table" then
      if memo.yes ~= confirm.cursor then
        memo.yes = confirm.cursor
        parts[#parts + 1] = H.yesNo((confirm.cursor or 0) + 1)
      end
    else
      memo.yes = nil
    end
    local text = sentences(parts)
    if not text then return nil end
    return text, true
  end,
}

Hoenn.ordered = { Hoenn.optionEmerald, Hoenn.optionRuby, Hoenn.saveMenu, Hoenn.trainerEmerald, Hoenn.trainerRuby,
  Hoenn.starter, Hoenn.wallClock }

return Hoenn
