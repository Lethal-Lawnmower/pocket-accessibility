-- Gen 2 presenters for items and storage (decision 27): the PACK, marts, the
-- item PC, GIVE/TAKE, the Pokemon Center PC, Bill's PC and its boxes, the
-- move deleter (also the forget-a-move and PP-target lists) and Crystal's
-- move tutor.  Same matches/poll contract as src/access/screens/Presenters.lua.
--
-- Every screen here keeps several layers in its own fields (a list, a
-- submenu, a quantity box, a YES/NO, a message), and its update() serves the
-- first one that is set.  Each presenter mirrors that order in a `mode`
-- function, so speech always follows the layer that owns input:
--
--   * a mode change speaks the new layer's context (prompt, item, position);
--   * inside a mode, only the changed value is spoken (the cursor's new item,
--     a new quantity, YES or NO);
--   * `entering` (the screen came back to the top) repeats the context.
--
-- MartMenu and ItemPcMenu hold a PackMenu that is never on the stack (they
-- update and draw it themselves), and MoveTutor holds a PartyMenu the same
-- way; their presenters read the held instance.  Nothing here calls a method
-- that writes: Boxes.count/Boxes.box create box tables and PackMenu:pagesFor
-- fills a cache, so those are mirrored from fields instead.  Methods that are
-- called (PackMenu pocket/description/playerName, ItemPcMenu def/cantToss,
-- HeldItemMenu monName, BoxMenu submenuRows/title/prompt, PartyMenu
-- shownHpFor/tmhmAble/count/rowFor/heldMarkerRow, Mon.maxPpOf, MartMenu
-- buyPrice/sellPrice, Boxes.name, LevelDisplay.visible) only read, and go
-- through pcall.  Labels a screen keeps in a local table (the PACK submenu,
-- the mart's BUY/SELL/QUIT, two PC prompts) are found through the upvalues of
-- the method that draws them (screenLocal below), never copied.

local Common = require("src.access.screens.gen2.Common")
local Strings = require("src.core.Strings")

local Items = {}

-- ------------------------------------------------------------------ helpers

-- The catalog lookup the screens draw through (src/core/Strings.lua), so a
-- translation mod changes speech the same way it changes the screen.
local function S(source, ...)
  if source == nil then return nil end
  local ok, text = pcall(Strings.get, source, ...)
  return ok and text or source
end

local function call(state, method, ...)
  local fn = state and state[method]
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, state, ...)
  if not ok then return nil end
  return a, b
end

local function position(index, count)
  return Common.position(index, count)
end

local function nonEmpty(text)
  if text == nil or text == "" then return nil end
  return text
end

-- Joins spoken parts into sentences: ". " between them unless the previous
-- part already ends a sentence ("How may I help you? BUY, 1 of 3").
local function sentences(...)
  local out = ""
  for i = 1, select("#", ...) do
    local part = select(i, ...)
    if type(part) == "string" and part ~= "" then
      if out == "" then
        out = part
      elseif out:find("[%.!?…:]$") then
        out = out .. " " .. part
      else
        out = out .. ". " .. part
      end
    end
  end
  return nonEmpty(out)
end
Items.sentences = sentences

-- A local table a screen keeps out of reach (`local SUBMENU_LABEL = ...`),
-- found through the upvalues of the method that draws it.  This reads the
-- screen's own labels instead of a copy that could drift; if upstream renames
-- or removes it the lookup answers nil and the label stays silent.
local upvalueCache = setmetatable({}, { __mode = "k" })
local function screenLocal(fn, name)
  if type(fn) ~= "function" then return nil end
  local cached = upvalueCache[fn]
  if not cached then
    cached = {}
    upvalueCache[fn] = cached
  end
  local value = cached[name]
  if value == nil then
    value = false
    for i = 1, 255 do
      local upName, upValue = debug.getupvalue(fn, i)
      if upName == nil then break end
      if upName == name then value = upValue break end
    end
    cached[name] = value
  end
  return value or nil
end
Items.screenLocal = screenLocal

local function classOf(state)
  return getmetatable(state)
end

local function yesNo(choice)
  return Common.speakable(S(choice == 1 and "YES" or "NO"))
end

local function money(amount)
  return "money ¥" .. tostring(math.floor(tonumber(amount) or 0))
end

-- An item or move description: two lines joined by the '<NEXT>' the
-- extractor keeps (PackMenu:drawDescription splits on it, or on "\n").
-- Read as lines so a word the cartridge splits across them ("catch-" /
-- "ing") is said whole.
local function description(text)
  if type(text) ~= "string" or text == "" then return nil end
  local lines = {}
  for line in (text:gsub("<NEXT>", "\n") .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  return nonEmpty(Common.lines(lines))
end
Items.description = description

-- Lines of one text-box page as one sentence.  A `cont` page
-- (home/text.asm _ContText) repeats the previous page's bottom line on its
-- top row, because the box scrolled; that line was already spoken, so only
-- the new line is said.  memo.lastLine is the bottom line last spoken.
local function pageText(lines, memo, player)
  if type(lines) == "string" then lines = { lines } end
  if type(lines) ~= "table" or #lines == 0 then return nil end
  local first = 1
  if memo.lastLine ~= nil and #lines > 1 and lines[1] == memo.lastLine then first = 2 end
  memo.lastLine = lines[#lines]
  local out = {}
  for i = first, #lines do
    local line = tostring(lines[i])
    if player then line = line:gsub("{PLAYER}", player) end
    out[#out + 1] = line
  end
  return nonEmpty(Common.lines(out))
end
Items.pageText = pageText

-- src/ui/gen2/Typer.lua: `typer.page` is the current page's lines after
-- substitution, a new table each page.  Returns the page's text once per
-- page table (memo.typerPage), with the scroll line dropped as above.
local function typerPage(state, memo)
  local typer = state.typer
  local page = typer and typer.page
  if type(page) ~= "table" or page == memo.typerPage then return nil end
  memo.typerPage = page
  return pageText(page, memo)
end

local function typing(state)
  local typer = state.typer
  return typer ~= nil and (tonumber(typer.shown) or 0) < (tonumber(typer.total) or 0)
end

-- A Typer message or confirm record ({ pages, page, choice }), as MartMenu,
-- HeldItemMenu, ItemPcMenu and CenterPcMenu keep them.  New pages are spoken
-- as they appear; on a confirm, YES or NO is said once its box is drawn
-- (last page typed out: MartMenu:yesNoVisible, HeldItemMenu:drawPanel) and
-- again when the choice flips.  Returns text and whether it interrupts.
local function typerRecord(state, memo, record, fresh)
  if fresh or memo.record ~= record then
    memo.record, memo.lastLine, memo.yesShown, memo.choice = record, nil, nil, nil
    if fresh then memo.typerPage = nil end
  end
  local text = typerPage(state, memo)
  local interrupt = text ~= nil
  local pages = record.pages
  if record.choice ~= nil and type(pages) == "table" then
    local visible = (record.page or 1) >= #pages and not typing(state)
    if visible and not memo.yesShown then
      memo.yesShown, memo.choice = true, record.choice
      text = sentences(text, yesNo(record.choice))
    elseif visible and record.choice ~= memo.choice then
      memo.choice = record.choice
      return yesNo(record.choice), true
    end
  end
  if not text then return nil end
  return text, interrupt or fresh
end

-- An instant YES/NO record ({ prompt, choice }), drawn with its prompt at
-- once (ItemPcMenu and CenterPcMenu draw `confirm.prompt` and the box
-- together in drawPanel, which fills {PLAYER} with the screen's playerName).
local function instantConfirm(state, record, memo, fresh)
  if fresh or memo.record ~= record then
    memo.record, memo.choice = record, record.choice
    local lines = record.prompt
    local prompt
    if type(lines) == "table" then
      local player = call(state, "playerName")
      local copy = {}
      for i, line in ipairs(lines) do copy[i] = player and tostring(line):gsub("{PLAYER}", player) or line end
      prompt = Common.lines(copy)
    end
    return sentences(prompt, yesNo(record.choice)), true
  end
  if record.choice ~= memo.choice then
    memo.choice = record.choice
    return yesNo(record.choice), true
  end
  return nil
end

-- The mode bookkeeping every presenter shares.  `fresh` is true when the
-- layer changed or the screen came back to the top; `from` is the mode that
-- was speaking before (nil on the very first frame).
local function modeChange(memo, mode, entering)
  local from = memo.mode
  local fresh = entering or mode ~= from
  memo.mode = mode
  return fresh, from
end

-- ------------------------------------------------------------------- PACK
-- src/ui/gen2/PackMenu.lua.  update() serves qtyState, switching, message,
-- confirm, submenu, then the list, in that order.

local Pack = {}
Items.Pack = Pack

local function packMode(pack)
  if pack.qtyState then return "qty" end
  if pack.switching then return "switch" end
  if pack.message then return "message" end
  if pack.confirm then return "confirm" end
  if pack.submenu then return "submenu" end
  return "list"
end

-- The pocket's title (POCKETS[i].label, drawn through Strings).
function Pack.pocket(pack)
  local pocket = call(pack, "pocket")
  if type(pocket) ~= "table" or pocket.label == nil then return nil end
  return Common.speakable(S(pocket.label)) .. " pocket"
end

-- One row as PackMenu:drawList draws it: the name (a TM/HM row draws its
-- number and the move it teaches; the record's own name is "TM01"), the
-- quantity when showCount says the cart prints one, CANCEL after the last.
function Pack.row(pack, i)
  local rows = type(pack.rows) == "table" and pack.rows or {}
  local row = rows[i]
  if type(row) ~= "table" then
    if i == #rows + 1 then return Common.speakable(S("CANCEL")) end
    return nil
  end
  local parts = { Common.speakable(row.name or row.id) }
  if row.tmhmLabel and row.teaches then parts[#parts + 1] = Common.speakable(row.teaches) end
  if row.showCount and row.count then parts[#parts + 1] = "quantity " .. tostring(row.count) end
  return table.concat(parts, ", ")
end

function Pack.description(pack)
  local text = call(pack, "description")
  if type(text) ~= "string" then return nil end
  return description(text)
end

local function packPosition(pack)
  local rows = type(pack.rows) == "table" and pack.rows or {}
  return position(pack.index or 1, #rows + 1)
end

-- Message pages, split the way PackMenu's local messagePages does
-- (home/text.asm:397): "\f" starts a page, "\v" scrolls one line.  The
-- screen's own split is used when it has one for these exact lines.
local function tokenPages(lines)
  if type(lines) == "string" then
    local CommonText = require("src.core.gen2.CommonText")
    return CommonText.pages(lines) or {}
  end
  local pages, rows = {}, {}
  local function flush(scroll)
    if #rows > 0 then pages[#pages + 1] = rows end
    rows = scroll and { rows[#rows] or "" } or {}
  end
  for _, line in ipairs(type(lines) == "table" and lines or {}) do
    if line == "\f" then
      flush(false)
    elseif line == "\v" then
      flush(true)
    else
      rows[#rows + 1] = line
    end
  end
  flush(false)
  return pages
end
Items.tokenPages = tokenPages

local function packPages(pack, lines)
  if pack.pagesSource == lines and type(pack.pages) == "table" then return pack.pages end
  return tokenPages(lines)
end

local function packMessage(pack, memo)
  local pages = packPages(pack, pack.message)
  return pageText(pages[pack.messagePage or 1], memo, call(pack, "playerName"))
end

local function submenuLabel(pack, menu)
  local id = menu.rows and menu.rows[menu.index]
  if id == nil then return nil end
  -- PackMenu:drawSubmenu prints Strings(SUBMENU_LABEL[id] or id).
  local labels = screenLocal(classOf(pack).drawSubmenu, "SUBMENU_LABEL")
  return Common.speakable(S((labels and labels[id]) or id))
end

-- how: "enter" (the screen or its holder's phase just opened: pocket name
-- first), "return" (back from one of its own layers), or nil (changes only).
function Pack.read(pack, memo, how)
  local mode = packMode(pack)
  local fresh = modeChange(memo, mode, how ~= nil)
  local text
  if mode == "list" then
    if fresh or pack.pocketIndex ~= memo.pocket then
      local context = (how == "enter" or (memo.pocket ~= nil and pack.pocketIndex ~= memo.pocket))
        and Pack.pocket(pack) or nil
      local row = Pack.row(pack, pack.index or 1)
      text = sentences(context, row and (row .. ", " .. packPosition(pack)), Pack.description(pack))
    elseif pack.index ~= memo.index then
      text = sentences(Pack.row(pack, pack.index), Pack.description(pack))
    end
  elseif mode == "message" then
    if fresh or pack.message ~= memo.message then
      memo.lastLine = nil
      text = packMessage(pack, memo)
    elseif pack.messagePage ~= memo.messagePage then
      text = packMessage(pack, memo)
    end
  elseif mode == "qty" then
    local qty = pack.qtyState
    if fresh or qty ~= memo.qtyState then
      memo.lastLine = nil
      local prompt = pack.message and packMessage(pack, memo) or nil
      text = sentences(prompt, string.format("Quantity %d, up to %d", qty.qty or 1, qty.max or 1))
    elseif qty.qty ~= memo.qty then
      text = tostring(qty.qty)
    end
    memo.qtyState, memo.qty = qty, qty.qty
  elseif mode == "confirm" then
    local confirm = pack.confirm
    if fresh or confirm ~= memo.confirm then
      memo.lastLine = nil
      local parts = {}
      for _, page in ipairs(packPages(pack, confirm.prompt)) do
        parts[#parts + 1] = pageText(page, memo, call(pack, "playerName"))
      end
      text = sentences(table.concat(parts, " "), yesNo(confirm.choice))
    elseif confirm.choice ~= memo.choice then
      text = yesNo(confirm.choice)
    end
    memo.confirm, memo.choice = confirm, confirm.choice
  elseif mode == "switch" then
    if fresh then
      memo.lastLine = nil
      local row = Pack.row(pack, pack.index or 1)
      text = sentences(pack.message and packMessage(pack, memo) or nil,
        row and (row .. ", " .. packPosition(pack)))
    elseif pack.index ~= memo.index then
      text = Pack.row(pack, pack.index)
    end
  elseif mode == "submenu" then
    local menu = pack.submenu
    if fresh or menu ~= memo.submenu then
      local label = submenuLabel(pack, menu)
      text = label and (label .. ", " .. position(menu.index or 1, #(menu.rows or {})))
    elseif menu.index ~= memo.subIndex then
      text = submenuLabel(pack, menu)
    end
    memo.submenu, memo.subIndex = menu, menu.index
  end
  memo.index, memo.pocket = pack.index, pack.pocketIndex
  memo.message, memo.messagePage = pack.message, pack.messagePage
  if not text then return nil end
  return text, true
end

Items.packMenu = {
  matches = Common.matcher("PackMenu"),
  poll = function(state, memo, entering)
    return Pack.read(state, memo, entering and "enter" or nil)
  end,
}

-- A PackMenu held off the stack by a holder (MartMenu sell, ItemPcMenu
-- deposit).  Its memo lives in the holder's memo and starts over for each
-- new held instance.
local function heldPack(memo, pack, how)
  if memo.pack ~= pack then
    memo.pack, memo.packMemo = pack, {}
    how = how or "enter"
  end
  return Pack.read(pack, memo.packMemo, how)
end

-- ------------------------------------------------------------------- MART
-- src/ui/gen2/MartMenu.lua.  update() serves message, confirm, then phase:
-- top, intro, buy, buyQuantity, sell (the held PACK), sellQuantity, outro.

local function martMode(mart)
  if mart.message then return "message" end
  if mart.confirm then return "confirm" end
  return mart.phase
end

-- BUY / SELL / QUIT: MartMenu:drawTopMenu prints Strings(TOP_ITEMS[i]).
local function martTopLabel(mart, index)
  local labels = screenLocal(classOf(mart).drawTopMenu, "TOP_ITEMS")
  local label = labels and labels[index]
  return label and Common.speakable(S(label)) or nil, labels and #labels or 0
end

local function martMoney(mart)
  local player = mart.save and mart.save.player
  return (player and player.money) or 0
end

-- MartMenu:drawBuyList: name and price, CANCEL after the last entry.
local function martRow(mart, i)
  local entries = type(mart.entries) == "table" and mart.entries or {}
  local entry = entries[i]
  if type(entry) ~= "table" then
    if i == #entries + 1 then return Common.speakable(S("CANCEL")) end
    return nil
  end
  return Common.speakable(entry.name or entry.id) .. ", ¥" .. tostring(entry.price or 0)
end

local function martDescription(mart)
  local entries = type(mart.entries) == "table" and mart.entries or {}
  if (mart.index or 1) > #entries then return nil end
  local text = call(mart, "description")
  return description(text)
end

local function martPrice(mart, kind)
  local fn = classOf(mart)[kind]
  local item = mart.qtyItem or {}
  if type(fn) ~= "function" then return nil end
  local ok, total = pcall(fn, item.price, mart.qty)
  return ok and total or nil
end

local function martQuantity(mart, kind, entry)
  local total = martPrice(mart, kind)
  local text = tostring(mart.qty or 1) .. (total and (", ¥" .. tostring(total)) or "")
  if entry then text = "Quantity " .. text .. ", up to " .. tostring(mart.qtyMax or 1) end
  return text
end

Items.martMenu = {
  matches = Common.matcher("MartMenu"),
  poll = function(state, memo, entering)
    local mode = martMode(state)
    local fresh, from = modeChange(memo, mode, entering)
    local cash = martMoney(state)
    local text, interrupt = nil, true
    if mode == "message" then
      text, interrupt = typerRecord(state, memo, state.message, fresh)
    elseif mode == "confirm" then
      text, interrupt = typerRecord(state, memo, state.confirm, fresh)
    elseif mode == "top" then
      if fresh then
        local label, count = martTopLabel(state, state.topIndex or 1)
        text = sentences(Common.lines(state.topLines or {}),
          label and (label .. ", " .. position(state.topIndex or 1, count)))
      elseif state.topIndex ~= memo.topIndex then
        text = martTopLabel(state, state.topIndex)
      end
    elseif mode == "buy" then
      if fresh then
        local row = martRow(state, state.index or 1)
        local entries = type(state.entries) == "table" and state.entries or {}
        text = sentences((from == "top" or entering) and money(cash) or nil,
          row and (row .. ", " .. position(state.index or 1, #entries + 1)), martDescription(state))
      elseif state.index ~= memo.index then
        text = sentences(martRow(state, state.index), martDescription(state))
      end
    elseif mode == "buyQuantity" then
      if fresh then
        text = sentences(Common.lines(state.text and state.text.howMany or {}),
          martQuantity(state, "buyPrice", true))
      elseif state.qty ~= memo.qty then
        text = martQuantity(state, "buyPrice", false)
      end
    elseif mode == "sellQuantity" then
      if fresh then
        text = sentences(Common.lines(state.sellText and state.sellText.howMany or {}),
          martQuantity(state, "sellPrice", true), money(cash))
      elseif state.qty ~= memo.qty then
        text = martQuantity(state, "sellPrice", false)
      end
    elseif mode == "sell" and state.pack then
      if fresh then
        local enter = entering or from == "top" or memo.pack ~= state.pack
        local packText = heldPack(memo, state.pack, enter and "enter" or "return")
        text = sentences(enter and martTopLabel(state, state.topIndex or 2) or nil, packText)
      else
        text = heldPack(memo, state.pack, nil)
      end
    end
    -- The money box changes in the frame a sale or purchase completes; say
    -- the new amount after whatever else this frame speaks.
    if memo.cash ~= nil and cash ~= memo.cash and mode ~= "top" then
      text = sentences(text, money(cash))
    end
    memo.cash, memo.index, memo.topIndex, memo.qty = cash, state.index, state.topIndex, state.qty
    if not text then return nil end
    return text, interrupt ~= false
  end,
}

-- ---------------------------------------------------------------- ITEM PC
-- src/ui/gen2/ItemPcMenu.lua.  update() serves message, qtyState, confirm,
-- then phase: deposit (the held PACK), withdraw/toss (the PC list, with
-- SELECT's switching), menu.

local function itemPcMode(pc)
  if pc.message then return "message" end
  if pc.qtyState then return "qty" end
  if pc.confirm then return "confirm" end
  if pc.phase == "deposit" then return "deposit" end
  if pc.phase == "withdraw" or pc.phase == "toss" then
    return pc.switching and "switch" or "list"
  end
  return "menu"
end

-- ItemPcMenu:drawPanel prints `entry.builtin and Strings(entry.label) or entry.label`.
local function entryLabel(entry)
  if type(entry) ~= "table" then return nil end
  return Common.speakable(entry.builtin and S(entry.label) or entry.label)
end

-- ItemPcMenu:drawList: name, ×count unless the item cannot be tossed, CANCEL.
local function itemPcRow(pc, i)
  local rows = type(pc.rows) == "table" and pc.rows or {}
  local row = rows[i]
  if type(row) ~= "table" then
    if i == #rows + 1 then return Common.speakable(S("CANCEL")) end
    return nil
  end
  local text = Common.speakable(row.name or row.id)
  if not call(pc, "cantToss", row.id) and row.count then
    text = text .. ", quantity " .. tostring(row.count)
  end
  return text
end

local function itemPcDescription(pc)
  local row = type(pc.rows) == "table" and pc.rows[pc.listIndex or 1]
  local def = row and call(pc, "def", row.id)
  local text = type(def) == "table" and def.description
  return description(text)
end

local function itemPcRowPosition(pc)
  local row = itemPcRow(pc, pc.listIndex or 1)
  local rows = type(pc.rows) == "table" and pc.rows or {}
  return row and (row .. ", " .. position(pc.listIndex or 1, #rows + 1))
end

-- "What do you want to do?" (TEXT.whatDo, drawn under the menu by drawPanel).
local function itemPcPrompt(pc)
  local text = screenLocal(classOf(pc).drawPanel, "TEXT")
  return text and text.whatDo and Common.speakable(S(text.whatDo)) or nil
end

Items.itemPcMenu = {
  matches = Common.matcher("ItemPcMenu"),
  poll = function(state, memo, entering)
    local mode = itemPcMode(state)
    local fresh, from = modeChange(memo, mode, entering)
    local text, interrupt = nil, true
    if mode == "message" then
      text, interrupt = typerRecord(state, memo, state.message, fresh)
    elseif mode == "qty" then
      local qty = state.qtyState
      if fresh or qty ~= memo.qtyState then
        text = sentences(Common.lines(qty.prompt or {}),
          string.format("Quantity %d, up to %d", qty.qty or 1, qty.max or 1))
      elseif qty.qty ~= memo.qty then
        text = tostring(qty.qty)
      end
      memo.qtyState, memo.qty = qty, qty.qty
    elseif mode == "confirm" then
      text = instantConfirm(state, state.confirm, memo, fresh)
    elseif mode == "menu" then
      local entries = type(state.entries) == "table" and state.entries or {}
      if fresh then
        local label = entryLabel(entries[state.index or 1])
        text = sentences(itemPcPrompt(state),
          label and (label .. ", " .. position(state.index or 1, #entries)))
      elseif state.index ~= memo.index then
        text = entryLabel(entries[state.index])
      end
    elseif mode == "list" then
      if fresh then
        local context = (entering or from == "menu" or from == nil)
          and entryLabel(state.entries and state.entries[state.index or 1]) or nil
        text = sentences(context, itemPcRowPosition(state), itemPcDescription(state))
      elseif state.listIndex ~= memo.listIndex then
        text = sentences(itemPcRow(state, state.listIndex), itemPcDescription(state))
      end
    elseif mode == "switch" then
      -- SELECT marks the row with a hollow cursor and prints nothing; say
      -- which item is being moved, then follow the cursor.
      if fresh then
        local held = type(state.rows) == "table" and state.rows[state.switching]
        text = held and ("moving " .. Common.speakable(held.name or held.id)) or nil
      elseif state.listIndex ~= memo.listIndex then
        text = itemPcRow(state, state.listIndex)
      end
    elseif mode == "deposit" and state.pack then
      if fresh then
        local enter = entering or from == "menu" or memo.pack ~= state.pack
        local packText = heldPack(memo, state.pack, enter and "enter" or "return")
        text = sentences(enter and entryLabel(state.entries and state.entries[state.index or 1]) or nil,
          packText)
      else
        text = heldPack(memo, state.pack, nil)
      end
    end
    memo.index, memo.listIndex = state.index, state.listIndex
    if not text then return nil end
    return text, interrupt ~= false
  end,
}

-- ------------------------------------------------------------- GIVE / TAKE
-- src/ui/gen2/HeldItemMenu.lua, over the party list.  While `busy` a PACK or
-- the mail keyboard is on top of it, so this presenter is not polled.

Items.heldItemMenu = {
  matches = Common.matcher("HeldItemMenu"),
  poll = function(state, memo, entering)
    local mode = state.message and "message" or (state.confirm and "confirm") or "menu"
    local fresh = modeChange(memo, mode, entering)
    local text, interrupt = nil, true
    if mode == "message" then
      text, interrupt = typerRecord(state, memo, state.message, fresh)
    elseif mode == "confirm" then
      text, interrupt = typerRecord(state, memo, state.confirm, fresh)
    else
      local entries = classOf(state).ENTRIES or {}
      local entry = entries[state.index or 1]
      local label = entry and Common.speakable(S(entry.label)) or nil
      if fresh then
        local name = call(state, "monName")
        text = sentences(name and Common.speakable(name) or nil,
          label and (label .. ", " .. position(state.index or 1, #entries)))
      elseif state.index ~= memo.index then
        text = label
      end
    end
    memo.index = state.index
    if not text then return nil end
    return text, interrupt ~= false
  end,
}

-- ------------------------------------------------------- POKéMON CENTER PC
-- src/ui/gen2/CenterPcMenu.lua: the turn-on message, then (booted) the
-- whose-PC menu under "Access whose PC?"; OAK's PC asks a YES/NO.

local function centerPrompt(pc)
  local text = screenLocal(classOf(pc).drawPanel, "TEXT")
  return text and text.accessWhose and Common.speakable(S(text.accessWhose)) or nil
end

Items.centerPcMenu = {
  matches = Common.matcher("CenterPcMenu"),
  poll = function(state, memo, entering)
    local mode = (state.message and "message") or (state.confirm and "confirm")
      or (state.booted and "menu") or nil
    local fresh = modeChange(memo, mode, entering)
    local text, interrupt = nil, true
    if mode == "message" then
      text, interrupt = typerRecord(state, memo, state.message, fresh)
    elseif mode == "confirm" then
      text = instantConfirm(state, state.confirm, memo, fresh)
    elseif mode == "menu" then
      local entries = type(state.entries) == "table" and state.entries or {}
      local entry = entries[state.index or 1]
      local label = entry and Common.speakable(entry.label) or nil
      if fresh then
        text = sentences(centerPrompt(state),
          label and (label .. ", " .. position(state.index or 1, #entries)))
      elseif state.index ~= memo.index then
        text = label
      end
    end
    memo.index = state.index
    if not text then return nil end
    return text, interrupt ~= false
  end,
}

-- --------------------------------------------------------------- BILL'S PC
-- src/ui/gen2/PcMenu.lua.  update() serves message, savePhase (CHANGE BOX's
-- save prompt), picking (the box list), then the menu.

local function pcMode(pc)
  if pc.message then return "message" end
  if pc.savePhase then return "save" end
  if pc.picking then return "pick" end
  return "menu"
end

-- One CHANGE BOX row as PcMenu:drawPanel shows it: the name and "n/20".
-- The count is read from save.boxes directly: Boxes.count would create the
-- box table it is asked about.
local function boxPickRow(pc, i)
  local Boxes = package.loaded["src.core.gen2.Boxes"]
  local save = pc.save or {}
  local name = Boxes and Boxes.name and Boxes.name(save, i) or nil
  if not name then return nil end
  local box = type(save.boxes) == "table" and save.boxes[i]
  local count = type(box) == "table" and #box or 0
  local cap = Boxes.MONS_PER_BOX
  return Common.speakable(name) .. ", " .. tostring(count)
    .. (cap and (" of " .. tostring(cap)) or "") .. " POKéMON"
end

-- CHANGE BOX's save prompt: typed pages (PcMenu:setSavePhase starts the
-- typer on savePages(), whose cache savePagesCache holds), then YES/NO once
-- the last confirm or overwrite page has typed out (saveYesNoVisible).
local function pcSave(pc, memo, fresh)
  if fresh then memo.typerPage, memo.lastLine, memo.saveShown = nil, nil, nil end
  if pc.savePhase ~= memo.savePhase then
    memo.savePhase, memo.lastLine, memo.saveShown = pc.savePhase, nil, nil
  end
  local text = typerPage(pc, memo)
  local asking = pc.savePhase == "confirm" or pc.savePhase == "overwrite"
  local pages = type(pc.savePagesCache) == "table" and pc.savePagesCache or {}
  local visible = asking and not typing(pc) and (pc.savePage or 1) >= #pages
  if visible and not memo.saveShown then
    memo.saveShown, memo.saveChoice = true, pc.saveChoice
    return sentences(text, yesNo(pc.saveChoice)), text ~= nil or fresh
  elseif visible and pc.saveChoice ~= memo.saveChoice then
    memo.saveChoice = pc.saveChoice
    return yesNo(pc.saveChoice), true
  end
  return text, true
end

Items.pcMenu = {
  matches = Common.matcher("PcMenu"),
  poll = function(state, memo, entering)
    local mode = pcMode(state)
    local fresh = modeChange(memo, mode, entering)
    local text, interrupt = nil, true
    if mode == "message" then
      if fresh or state.message ~= memo.message then
        text = Common.lines(tostring(state.message))
      end
    elseif mode == "save" then
      text, interrupt = pcSave(state, memo, fresh)
    elseif mode == "pick" then
      local Boxes = package.loaded["src.core.gen2.Boxes"]
      local total = Boxes and Boxes.NUM_BOXES or 0
      if fresh then
        local row = boxPickRow(state, state.pickIndex or 1)
        -- PcMenu:drawPanel prints Strings("Which BOX?") under the list.
        text = sentences(Common.speakable(S("Which BOX?")),
          row and (row .. ", " .. position(state.pickIndex or 1, total)))
      elseif state.pickIndex ~= memo.pickIndex then
        text = boxPickRow(state, state.pickIndex)
      end
    else
      local entries = type(state.entries) == "table" and state.entries or {}
      local label = entryLabel(entries[state.index or 1])
      if fresh then
        -- PcMenu:drawPanel prints Strings("What?") in the box under the menu.
        text = sentences(Common.speakable(S("What?")),
          label and (label .. ", " .. position(state.index or 1, #entries)))
      elseif state.index ~= memo.index then
        text = label
      end
    end
    memo.index, memo.pickIndex, memo.message = state.index, state.pickIndex, state.message
    if not text then return nil end
    return text, interrupt ~= false
  end,
}

-- ------------------------------------------------------------------ BOXES
-- src/ui/gen2/BoxMenu.lua.  update() serves cryWait (a Crystal cry before
-- the message), the held or pressed message, the submenu, the insert cursor
-- (MOVE), then the list.

local PARTY_BOX = 0 -- wBillsPC_LoadedBox: the party on the MOVE screen

local function boxMode(box)
  if box.cryWait then return "wait" end
  if box.message then return "message" end
  if box.phase == "submenu" then return "submenu" end
  if box.phase == "insert" then return "insert" end
  return "list"
end

-- The mon list loaded box `index` stands for (BoxMenu:listAt), read without
-- Boxes.box, which would create the table.
local function boxListAt(box, index)
  local save = box.save or {}
  if box.mode == "move" and index == PARTY_BOX then return save.party or {} end
  local boxes = save.boxes
  local list = type(boxes) == "table" and boxes[index]
  return type(list) == "table" and list or {}
end

-- The list the cursor browses (BoxMenu:list): the party on DEPOSIT.
local function boxBrowsed(box)
  if box.mode == "deposit" then return (box.save and box.save.party) or {} end
  return boxListAt(box, box.boxIndex)
end

-- One mon as the screen shows it: the nickname from the list
-- (.PlaceNickname), then the left panel PCMonInfo draws for it -- level,
-- gender, species name and the held-item or mail icon.  An egg shows only
-- its name and picture.
local function monText(mon)
  if type(mon) ~= "table" then return nil end
  local name = mon.nickname or mon.name or mon.species or "?"
  if mon.isEgg then return Common.speakable(name) end
  local parts = { Common.speakable(name), "level " .. tostring(mon.level or 1) }
  if mon.gender == "male" or mon.gender == "female" then parts[#parts + 1] = mon.gender end
  local species = mon.name or mon.species
  if species and species ~= name then parts[#parts + 1] = Common.speakable(species) end
  local PartyMenu = package.loaded["src.ui.gen2.PartyMenu"]
  local marker
  if PartyMenu and PartyMenu.heldMarkerRow then
    local ok, row = pcall(PartyMenu.heldMarkerRow, mon)
    marker = ok and row or nil
  end
  if marker == 0 then
    parts[#parts + 1] = "holding mail"
  elseif marker ~= nil then
    parts[#parts + 1] = "holding an item"
  end
  return table.concat(parts, ", ")
end
Items.monText = monText

local function boxRow(box, i)
  local list = boxBrowsed(box)
  if list[i] then return monText(list[i]) end
  if i == #list + 1 then return Common.speakable(S("CANCEL")) end
  return nil
end

local function boxRowPosition(box)
  local row = boxRow(box, box.index or 1)
  return row and (row .. ", " .. position(box.index or 1, #boxBrowsed(box) + 1))
end

-- The insert cursor is a rule above the mon the moved one will go in front
-- of (BoxMenu:drawInsertCursor); an empty destination has only the cursor.
local function insertRow(box, i)
  local list = boxListAt(box, box.boxIndex)
  local mon = list[i]
  if not mon then return "empty" end
  return "before " .. monText(mon)
end

local function insertPosition(box)
  local count = math.max(1, #boxListAt(box, box.boxIndex))
  return insertRow(box, box.index or 1) .. ", " .. position(box.index or 1, count)
end

local function boxText(box, method)
  local text = call(box, method)
  return type(text) == "string" and nonEmpty(Common.speakable(text)) or nil
end

local function submenuText(box, index, withPosition)
  local rows = call(box, "submenuRows")
  local label = type(rows) == "table" and rows[index]
  if not label then return nil end
  local text = Common.speakable(S(label))
  if withPosition then text = text .. ", " .. position(index, #rows) end
  return text
end

local function boxMessage(box, memo)
  local CommonText = require("src.core.gen2.CommonText")
  local pages = CommonText.pages(box.message) or {}
  return pageText(pages[box.messagePage or 1], memo)
end

Items.boxMenu = {
  matches = Common.matcher("BoxMenu"),
  poll = function(state, memo, entering)
    local mode = boxMode(state)
    local fresh = modeChange(memo, mode, entering)
    local text
    if mode == "message" then
      if fresh or state.message ~= memo.message then
        memo.lastLine = nil
        text = boxMessage(state, memo)
      elseif state.messagePage ~= memo.messagePage then
        text = boxMessage(state, memo)
      end
    elseif mode == "submenu" then
      if fresh then
        text = sentences(boxText(state, "prompt"), submenuText(state, state.submenuIndex or 1, true))
      elseif state.submenuIndex ~= memo.submenuIndex then
        text = submenuText(state, state.submenuIndex, false)
      end
    elseif mode == "insert" then
      if fresh then
        text = sentences(boxText(state, "prompt"), boxText(state, "title"), insertPosition(state))
      elseif state.boxIndex ~= memo.boxIndex then
        text = sentences(boxText(state, "title"), insertPosition(state))
      elseif state.index ~= memo.index then
        text = insertRow(state, state.index or 1)
      end
    elseif mode == "list" then
      if fresh and (entering or memo.seen == nil) then
        text = sentences(boxText(state, "title"), boxText(state, "prompt"), boxRowPosition(state))
      elseif fresh or state.boxIndex ~= memo.boxIndex then
        text = sentences(state.boxIndex ~= memo.boxIndex and boxText(state, "title") or nil,
          boxRowPosition(state))
      elseif state.index ~= memo.index then
        text = boxRow(state, state.index)
      end
    end
    memo.seen = true
    memo.index, memo.boxIndex, memo.submenuIndex = state.index, state.boxIndex, state.submenuIndex
    memo.message, memo.messagePage = state.message, state.messagePage
    if not text then return nil end
    return text, true
  end,
  -- RELEASE sets `message` to "Release PKMN?" and pushes the Gen 1 ChoiceBox
  -- in the same frame, so this screen is covered before it is polled again
  -- and the question would never be said.  ScreenReader can call this for
  -- the screen a new top just covered (proposed hook; see the module's
  -- report): it returns the message when it is one not yet spoken.
  covered = function(state, memo)
    if not state.message or state.message == memo.message then return nil end
    memo.lastLine = nil
    local text = boxMessage(state, memo)
    memo.message, memo.messagePage = state.message, state.messagePage
    return text
  end,
}

-- ------------------------------------------------------------ MOVE LISTS
-- src/ui/gen2/MoveDeleter.lua: the Blackthorn deleter and the PP-restore
-- pick draw name and "PP x/y"; layout "forget" (learning a fifth move,
-- drawn by ForgetMoveList) draws names only.

local function moveRow(state, entry)
  if type(entry) ~= "table" then return nil end
  local def = state.moves and state.moves[entry.id]
  local name = Common.speakable((def and def.name) or entry.id)
  if state.forget then return name end
  local Mon = package.loaded["src.battle.gen2.Mon"]
  local maxPp = 0
  if Mon and Mon.maxPpOf then
    local ok, value = pcall(Mon.maxPpOf, entry, state.game and state.game.data)
    maxPp = ok and tonumber(value) or 0
  end
  -- A missing pp is unknown (or full), never zero: only an explicit 0 is
  -- used up.
  local pp = tonumber(entry.pp)
  if pp and maxPp > 0 then return string.format("%s, PP %d of %d", name, pp, maxPp) end
  if pp then return string.format("%s, PP %d", name, pp) end
  if maxPp > 0 then return string.format("%s, maximum PP %d", name, maxPp) end
  return name
end
Items.moveRow = moveRow

Items.moveDeleter = {
  matches = Common.matcher("MoveDeleter"),
  poll = function(state, memo, entering)
    if not entering and memo.row == state.row then return nil end
    local list = type(state.list) == "table" and state.list or {}
    local first = entering or memo.row == nil
    memo.row = state.row
    local text = moveRow(state, list[state.row or 1])
    if not text then return nil end
    if first then text = text .. ", " .. position(state.row or 1, #list) end
    return text, true
  end,
}

-- ------------------------------------------------------------- MOVE TUTOR
-- src/ui/gen2/MoveTutor.lua holds a PartyMenu in teach mode (`list`), off
-- the stack; this reads that held instance the way PartyMenu:drawPanel
-- draws it.  The on-stack party screen has its own presenter (Info.lua).

local function partyPrompt(list)
  local PartyMenu = classOf(list)
  local prompts = PartyMenu and PartyMenu.PROMPTS or {}
  local party = type(list.party) == "table" and list.party or {}
  local text
  if #party == 0 then
    text = S(prompts.none)
  elseif list.switchFrom then
    text = S(prompts.moveTo)
  elseif list.softboiledFrom then
    text = S(prompts.useItem)
  elseif list.promptIsBuiltin then
    text = S(list.prompt)
  else
    text = list.prompt
  end
  return type(text) == "string" and Common.speakable(text) or nil
end

-- One party row: name, level, then ABLE / NOT ABLE in teach mode (or HP),
-- and the status, as PartyMenu.rowFor and tmhmAble give them.
local function partyRow(list, i)
  local party = type(list.party) == "table" and list.party or {}
  local mon = party[i]
  if type(mon) ~= "table" then
    if i == #party + 1 then return Common.speakable(S("CANCEL")) end
    return nil
  end
  local PartyMenu = classOf(list)
  local game = list.game
  local hp = call(list, "shownHpFor", i, mon)
  local ok, row = pcall(PartyMenu.rowFor, mon, hp, game and game.data and game.data.gen2Statuses)
  if not ok or type(row) ~= "table" then return nil end
  local parts = { Common.speakable(row.name) }
  if not mon.isEgg then
    local LevelDisplay = package.loaded["src.ui.LevelDisplay"]
    local shown = true
    if LevelDisplay and LevelDisplay.visible then
      local okLevel, visible = pcall(LevelDisplay.visible, mon, "party", game)
      shown = not okLevel or visible ~= false
    end
    if shown then parts[#parts + 1] = "level " .. tostring(mon.level or 1) end
    if list.tmhm then
      local able = call(list, "tmhmAble", mon)
      if able then parts[#parts + 1] = Common.speakable(able) end
    elseif row.hp then
      local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 0
      parts[#parts + 1] = string.format("HP %d of %d", math.floor(tonumber(hp) or 0), maxHp)
    end
    if (tonumber(hp) or 0) <= 0 then
      parts[#parts + 1] = "fainted"
    elseif row.status then
      parts[#parts + 1] = Common.speakable(row.status)
    end
  end
  return table.concat(parts, ", ")
end
Items.partyRow = partyRow

local function heldParty(list, memo, enter)
  if enter or memo.index == nil then
    memo.index = list.index
    local party = type(list.party) == "table" and list.party or {}
    local row = partyRow(list, list.index or 1)
    local count = call(list, "count") or (#party + 1)
    return sentences(partyPrompt(list), row and (row .. ", " .. position(list.index or 1, count)))
  end
  if list.index ~= memo.index then
    memo.index = list.index
    return partyRow(list, list.index)
  end
  return nil
end

Items.moveTutor = {
  matches = Common.matcher("MoveTutor"),
  poll = function(state, memo, entering)
    local list = state.list
    if type(list) ~= "table" or state.done then return nil end
    if memo.list ~= list then memo.list, memo.party = list, {} end
    local text = heldParty(list, memo.party, entering)
    if not text then return nil end
    return text, true
  end,
}

Items.ordered = {
  Items.packMenu,
  Items.martMenu,
  Items.itemPcMenu,
  Items.heldItemMenu,
  Items.centerPcMenu,
  Items.pcMenu,
  Items.boxMenu,
  Items.moveDeleter,
  Items.moveTutor,
}

return Items
