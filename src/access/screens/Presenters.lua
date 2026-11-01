-- Turns upstream UI screens into speech.
--
-- A presenter reads an upstream state table without changing it:
--   matches(state)                    is this state one of ours?
--   poll(state, memo, entering) -> text, interrupt
-- poll runs every frame the state is on top.  `memo` is this screen's own
-- scratch table (kept while the screen exists); a presenter stores the
-- fields it last spoke there and returns text only when they change.
-- `entering` is true on the first frame on top, including a return from a
-- screen above, so context (a title, a position) is said then and not on
-- every cursor move.  Keep poll cheap: compare numbers and existing strings,
-- build text only on a change.
--
-- Upstream classes are looked up in package.loaded, so a presenter never
-- forces a UI module to load before the game would.

local Settings = require("src.access.Settings")

local Presenters = {}

-- An instance can only exist once its class module has loaded, so look in
-- package.loaded instead of requiring: speech never loads UI code early.
local function class(path)
  return package.loaded[path]
end

local function matcher(path)
  return function(state)
    local mod = class(path)
    return mod ~= nil and getmetatable(state) == mod
  end
end

local function position(index, count)
  return string.format("%d of %d", index, count)
end

-- Game text uses line breaks and a few glyph tokens; make it one sentence.
local function speakable(text)
  text = tostring(text or "")
  text = text:gsub("<PK>", "PK"):gsub("<MN>", "MN")
  -- a line ending in a space plus the joining space would read as a pause
  return (text:gsub("%s*\n%s*", " "):gsub("  +", " "))
end
Presenters.speakable = speakable

-- Joins a page's lines into one sentence.  A line ending in a hyphen is a
-- word the original split across lines ("grand-" / "son"), so it is joined
-- without a space and reads as one word.
-- `first` and `last` select a range (default: every line).
local function joinLines(lines, first, last)
  first, last = first or 1, last or #lines
  local out = ""
  for i = first, last do
    local line = tostring(lines[i])
    if i == first then
      out = line
    elseif out:sub(-1) == "-" then
      out = out .. line
    else
      out = out .. " " .. line
    end
  end
  return out
end
Presenters.joinLines = joinLines

-- One row's spoken text: label first, then whichever detail the row draws
-- (src/ui/ListMenu.lua draws level, sub, price, count or right, in that order).
local function rowText(item)
  if type(item) ~= "table" then return nil end
  local parts = { speakable(item.label) }
  if item.level then
    parts[#parts + 1] = "level " .. tostring(item.level)
  elseif item.sub then
    parts[#parts + 1] = speakable(item.sub)
  elseif item.price then
    parts[#parts + 1] = tostring(item.price)
  elseif item.count then
    parts[#parts + 1] = "quantity " .. tostring(item.count)
  elseif item.right then
    parts[#parts + 1] = speakable(item.right)
  end
  return table.concat(parts, ", ")
end
Presenters.rowText = rowText

-- Dialogue box, paced like the game (owner request, 2026-10-31): a chunk is
-- spoken as soon as the game starts showing it, and a chunk ends where the
-- game waits for A before scrolling on (pages.contBefore[p][i] marks a line
-- that waits; TextBox moves lineIndex onto it only after the press).  Each
-- chunk is said whole, never letter by letter.  pages[p] holds the
-- already-substituted lines (TextBox.paginate).
--
-- memo.through is the last line already spoken on memo.page, so nothing is
-- said twice: a Yes/No box closing over the page stays quiet, and an
-- instant box (lineIndex already at the end) speaks its whole page at once.
Presenters.textBox = {
  matches = matcher("src.render.TextBox"),
  poll = function(state, memo)
    local pageIndex = state.pageIndex
    if memo.page ~= pageIndex then
      memo.page, memo.through = pageIndex, 0
    end
    -- DIALOGUE SPEECH set to ALL AT ONCE (decision 26): the whole box, every
    -- page, as soon as it opens; nothing more for this box afterwards.
    if Settings.dialogueWhole(state.game) and type(state.pages) == "table" then
      if memo.whole then return nil end
      memo.whole = true
      local parts = {}
      for _, page in ipairs(state.pages) do
        if type(page) == "table" and #page > 0 then parts[#parts + 1] = joinLines(page, 1, #page) end
      end
      if #parts == 0 then return nil end
      return speakable(table.concat(parts, " ")), true
    end
    local lines = state.pages and state.pages[pageIndex]
    if type(lines) ~= "table" or #lines == 0 then return nil end
    local current = math.min(state.lineIndex or 1, #lines)
    if current <= memo.through then return nil end
    local waits = state.pages.contBefore and state.pages.contBefore[pageIndex] or {}
    local last = current
    while last < #lines and not waits[last + 1] do last = last + 1 end
    local first = memo.through + 1
    memo.through = last
    return speakable(joinLines(lines, first, last)), true
  end,
}

-- Bordered menus (title menu, start menu, name choices, PC, shop root).
Presenters.menu = {
  matches = matcher("src.ui.Menu"),
  poll = function(state, memo, entering)
    if not entering and memo.index == state.index then return nil end
    memo.index = state.index
    local items = state.items or {}
    local text = rowText(items[state.index])
    if not text then return nil end
    if entering then
      text = text .. ", " .. position(state.index, #items)
      if state.title then text = speakable(state.title) .. ". " .. text end
    end
    return text, true
  end,
}

-- True for ListMenu itself and screens built on it (BindingsMenu sets a
-- metatable whose __index chain reaches ListMenu).
local function isListMenu(state)
  local ListMenu = class("src.ui.ListMenu")
  if not ListMenu then return false end
  local mt = getmetatable(state)
  for _ = 1, 8 do
    if mt == nil then return false end
    if mt == ListMenu then return true end
    local parent = getmetatable(mt)
    mt = parent and parent.__index
  end
  return false
end

-- Scrolling lists (bag, PC boxes, shop lists, controls, fly).
Presenters.listMenu = {
  matches = isListMenu,
  poll = function(state, memo, entering)
    if not entering and memo.index == state.index then return nil end
    memo.index = state.index
    local items = state.items or {}
    local title = (entering and state.title) and (speakable(state.title) .. ". ") or ""
    if #items == 0 then return title .. "Empty", true end
    local text = rowText(items[state.index])
    if not text then return nil end
    return title .. text .. ", " .. position(state.index, #items), true
  end,
}

-- Yes/No box over a dialogue page.  On entry it queues behind the question
-- that was just spoken instead of cutting it off; later moves interrupt.
Presenters.choiceBox = {
  matches = matcher("src.ui.ChoiceBox"),
  poll = function(state, memo, entering)
    if not entering and memo.index == state.index then return nil end
    memo.index = state.index
    local labels = state.labels or { "YES", "NO" }
    local label = labels[state.index]
    if not label then return nil end
    return speakable(label), not entering
  end,
}

-- "How many?" box (src/ui/QuantityBox.lua): quantity, and the running total
-- when buying or selling.
Presenters.quantityBox = {
  matches = matcher("src.ui.QuantityBox"),
  poll = function(state, memo, entering)
    if not entering and memo.qty == state.qty then return nil end
    memo.qty = state.qty
    local text = tostring(state.qty)
    if state.unitPrice then
      text = text .. ", ¥" .. tostring(state.qty * state.unitPrice)
    end
    if entering then text = "Quantity " .. text .. ", up to " .. tostring(state.max) end
    return text, true
  end,
}

-- Naming keyboard cells are glyphs; punctuation is spelled out because screen
-- readers often skip it.  Unlisted cells (letters) are read as they are.
local CELL_NAMES = {
  [" "] = "space", ["×"] = "times", ["("] = "left parenthesis",
  [")"] = "right parenthesis", [":"] = "colon", [";"] = "semicolon",
  ["["] = "left bracket", ["]"] = "right bracket", ["<PK>"] = "PK",
  ["<MN>"] = "MN", ["-"] = "dash", ["?"] = "question mark",
  ["!"] = "exclamation mark", ["♂"] = "male", ["♀"] = "female",
  ["/"] = "slash", ["<DOT>"] = "dot", [","] = "comma", ["ED"] = "end, confirm name",
}
local function cellName(cell)
  if cell == nil then return nil end
  return CELL_NAMES[cell] or speakable(cell)
end

local function typedName(glyphs)
  local out = {}
  for i, g in ipairs(glyphs or {}) do
    out[i] = (g == "<PK>" and "PK") or (g == "<MN>" and "MN") or g
  end
  return table.concat(out)
end

-- Naming screen (src/ui/NamingScreen.lua): the grid comes from its own
-- grid() method, so mod-replaced keyboards read correctly.
Presenters.namingScreen = {
  matches = matcher("src.ui.NamingScreen"),
  poll = function(state, memo, entering)
    local count = #(state.glyphs or {})
    if not entering and memo.row == state.row and memo.col == state.col
        and memo.lower == state.lower and memo.count == count then
      return nil
    end
    local okGrid, grid = pcall(state.grid, state)
    local row = okGrid and grid and grid[state.row]
    local cell = cellName(row and row[state.col])
    local text
    if entering then
      local name = typedName(state.glyphs)
      text = speakable(state.title) .. " " .. (name ~= "" and name or "empty")
        .. ". " .. tostring(cell)
    elseif count > (memo.count or 0) then
      local typed = state.glyphs[count]
      text = cellName(typed) .. ", " .. typedName(state.glyphs)
      if memo.row ~= state.row or memo.col ~= state.col then
        text = text .. ". " .. tostring(cell) -- the cursor jumped to end
      end
    elseif count < (memo.count or 0) then
      local name = typedName(state.glyphs)
      text = "deleted, " .. (name ~= "" and name or "empty")
    elseif memo.lower ~= state.lower then
      text = (state.lower and "lower case. " or "upper case. ") .. tostring(cell)
    else
      text = tostring(cell)
    end
    memo.row, memo.col, memo.lower, memo.count = state.row, state.col, state.lower, count
    return text, true
  end,
}

-- Party screen (src/ui/PartyMenu.lua).
local function partyOf(state)
  local game = state.game
  return state.party or (game and game.save and game.save.party) or {}
end

-- One party row as the screen draws it: name, level, then either HP and
-- status, or ABLE / NOT ABLE when teaching a TM or using an evolution stone.
-- The learnability scans mirror PartyMenu:draw (TM/HM list, ITEM evolutions).
local function partyRow(state, mon)
  if type(mon) ~= "table" then return nil end
  local data = state.game and state.game.data
  local def = data and data.pokemon and data.pokemon[mon.species] or {}
  local parts = { speakable(mon.nickname or def.name or mon.species), "level " .. tostring(mon.level) }
  if state.tmhm or state.evoStone then
    local can = false
    if state.tmhm then
      for _, m in ipairs(def.tmhm or {}) do
        if m == state.tmhm.move then can = true break end
      end
    else
      for _, evo in ipairs(def.evolutions or {}) do
        if evo.method == "ITEM" and evo.item == state.evoStone then can = true break end
      end
    end
    parts[#parts + 1] = can and "able" or "not able"
  else
    local maxHp = mon.stats and mon.stats.hp
    parts[#parts + 1] = string.format("HP %d of %s", mon.hp or 0, tostring(maxHp or "?"))
    if (mon.hp or 0) <= 0 then
      parts[#parts + 1] = "fainted"
    elseif mon.status then
      local okStatus, Status = pcall(require, "src.battle.Status")
      local label = okStatus and data and Status.hudLabelFor(data.statuses, mon.status)
      parts[#parts + 1] = speakable(label or mon.status)
    end
  end
  return table.concat(parts, ", ")
end
Presenters.partyRow = partyRow

local function bottomMessage(state)
  local ok, text = pcall(state.bottomMessage, state)
  return ok and type(text) == "string" and speakable(text) or nil
end

Presenters.partyMenu = {
  matches = matcher("src.ui.PartyMenu"),
  poll = function(state, memo, entering)
    local sub = state.submenu and state.subIndex or nil
    local message = state.message
    if not entering and memo.index == state.index and memo.sub == sub
        and memo.message == message and memo.swap == state.swapFrom then
      return nil
    end
    local party = partyOf(state)
    local text
    if entering then
      text = (bottomMessage(state) or "") .. " "
        .. (partyRow(state, party[state.index]) or "") .. ", " .. position(state.index, #party)
    elseif message ~= memo.message and message then
      text = speakable(message)
    elseif sub and sub ~= memo.sub then
      local entry = state.subItems and state.subItems[sub]
      text = entry and speakable(entry.label) or nil
      if memo.sub == nil and text then
        text = text .. ", " .. position(sub, #(state.subItems or {}))
      end
    elseif state.swapFrom ~= memo.swap and state.swapFrom then
      text = (bottomMessage(state) or "") .. " " .. (partyRow(state, party[state.index]) or "")
    else
      text = partyRow(state, party[state.index])
      if sub == nil and memo.sub ~= nil then
        text = text and (text .. ", " .. position(state.index, #party))
      end
    end
    memo.index, memo.sub, memo.message, memo.swap = state.index, sub, message, state.swapFrom
    return text, true
  end,
}

-- Any screen may describe itself, so a mod's custom screen can speak
-- without depending on this layer: give the state table a method
--   function state:accessibilityText() return "Jukebox. Track 3 of 10" end
-- It is called once per frame while the screen is on top and must be cheap.
-- The text is spoken (interrupting) whenever it differs from the last text.
-- Checked before every other presenter, so a screen's own description also
-- overrides ours.  Errors are logged once per screen and the screen goes
-- quiet instead of breaking the game.
Presenters.selfDescribing = {
  matches = function(state) return type(state.accessibilityText) == "function" end,
  poll = function(state, memo, entering)
    if memo.failed then return nil end
    local ok, text = pcall(state.accessibilityText, state)
    if not ok then
      memo.failed = true
      require("src.core.Logger").warn("[access] accessibilityText failed: %s", tostring(text))
      return nil
    end
    if type(text) ~= "string" or text == "" then return nil end
    if not entering and text == memo.text then return nil end
    memo.text = text
    return speakable(text), true
  end,
}

Presenters.ordered = {
  Presenters.selfDescribing,
  Presenters.textBox,
  Presenters.menu,
  Presenters.listMenu,
  Presenters.choiceBox,
  Presenters.quantityBox,
  Presenters.namingScreen,
  Presenters.partyMenu,
}
for _, presenter in ipairs(require("src.access.screens.InfoScreens").ordered) do
  Presenters.ordered[#Presenters.ordered + 1] = presenter
end
do
  local Battle = require("src.access.screens.Battle")
  Presenters.ordered[#Presenters.ordered + 1] = Battle.presenter
  Presenters.ordered[#Presenters.ordered + 1] = Battle.statBox
end
for _, presenter in ipairs(require("src.access.screens.MinorScreens").ordered) do
  Presenters.ordered[#Presenters.ordered + 1] = presenter
end
for _, presenter in ipairs(require("src.access.screens.ExtraScreens").ordered) do
  Presenters.ordered[#Presenters.ordered + 1] = presenter
end
for _, presenter in ipairs(require("src.access.screens.LinkScreens").ordered) do
  Presenters.ordered[#Presenters.ordered + 1] = presenter
end
Presenters.ordered[#Presenters.ordered + 1] = require("src.access.screens.Overworld").presenter

function Presenters.find(state)
  if type(state) ~= "table" then return nil end
  for _, presenter in ipairs(Presenters.ordered) do
    if presenter.matches(state) then return presenter end
  end
  return nil
end

return Presenters
