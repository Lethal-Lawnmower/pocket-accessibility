-- Gen 3 presenters for items, Pokémon and storage (FireRed; decision 29):
-- the bag (also in battle, at the item PC's DEPOSIT and the shop's SELL),
-- TM case, berry pouch, the sell flow they share, party (every mode the
-- screen has), summary (including the battle's forget-a-move mode),
-- Pokédex, the PC hub, box storage with its release sequence and box
-- picker, the item PC, the shop, the money box scripts show, and the
-- region map with Fly.
--
-- Each screen arrives from gen3/Top.lua as a proxy per opening
-- ({ gen3 = <layer id>, key = <layer record>, layer, mod, game }); the
-- screens themselves are module singletons, so everything remembered
-- lives in the per-opening memo, never on a module.
--
-- Every screen keeps several layers in one `mode` field (a list, an action
-- menu, a quantity, a YES/NO, a message) and its handleInput serves them
-- in a fixed order.  Each presenter mirrors that order, so speech follows
-- the layer that owns input:
--   * a mode change speaks the new layer's context (prompt, item, position);
--   * inside a mode only the changed value is spoken (the new row, the new
--     quantity, YES or NO), interrupting;
--   * `entering` (first frame, or back on top) repeats the context.
--
-- Text is the screens' own: rows, prompts and messages are built through
-- the same RomText keys the draw code uses (so a translation follows), or
-- read from the screens' own fields.  Labels a screen keeps in file-local
-- tables or functions (the bag's action labels, the TM case and berry
-- pouch actions, the item PC submenu, box storage menu texts and
-- wallpapers, the summary page titles, the Pokédex habitat titles) are
-- reached through the upvalues of the function that draws them and stay
-- silent if upstream renames them.  Icons with no text (status, held item,
-- caught ball, HM disc, storage buttons) are described in words.
--
-- Reading never changes game state.  Bag.listPocket and Bag.get run the
-- bag's ensure(), which rebuilds every pocket table, and Storage.ensure
-- creates storage (and adds a POTION to the item PC), so the pocket rows
-- are mirrored from `bag.pockets` and storage is read from
-- `session.storage`.  Methods that write a cache (PartyMenu._actionTextsFor,
-- PcMenu._rootEntries, Pokedex unitTexts) are not called: their inputs or
-- their cached result are read instead.  The read-only calls are listed in
-- docs/access/architecture.md and go through pcall.

local Common = require("src.access.screens.gen3.Common")
local Top = require("src.access.screens.gen3.Top")

local Items = {}

-- ------------------------------------------------------------------ helpers

local function loaded(path)
  return package.loaded[path]
end

-- A read-only call through pcall; nil when it is missing or fails, so an
-- unreadable value stays silent instead of being guessed.
local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c
end

local function nonEmpty(text)
  if text == nil or text == "" then return nil end
  return text
end

-- Spoken form of a game string (font tags, control bytes, line and page
-- breaks), nil when nothing is left.
local function say(text)
  if text == nil then return nil end
  return nonEmpty(Common.speakable(text))
end
Items.say = say

local function sentences(...)
  return nonEmpty(Common.sentences(...))
end

local function join(parts, sep)
  local out = {}
  for i = 1, table.maxn(parts) do
    local part = parts[i]
    if part ~= nil and part ~= "" then out[#out + 1] = tostring(part) end
  end
  return nonEmpty(table.concat(out, sep or ", "))
end

local position = Common.position

-- RomText as the screens call it.
local function romText() return loaded("src.core.game3.rom_text") end
local function rom(key, ctx)
  local R = romText()
  return R and try(R.plain, key, ctx) or nil
end
local function romBox(key, ctx)
  local R = romText()
  return R and try(R.box, key, ctx) or nil
end
local function romAt(name, i)
  local R = romText()
  return R and try(R.at, name, i) or nil
end
local function romHas(key)
  local R = romText()
  return R and try(R.has, key) == true
end

-- An engine string through src/core/Strings.lua (a callable table), as the
-- region map's names are drawn; the string itself when that fails.
local function translate(raw)
  local Strings = loaded("src.core.Strings")
  if Strings then
    local ok, out = pcall(Strings, raw)
    if ok and type(out) == "string" then return out end
  end
  return raw
end

local function yesNo(cursor)
  return say(rom(cursor == 1 and "gText_Yes" or "gText_No"))
end

local function quantity(qty, max)
  return string.format("Quantity %d, up to %d", tonumber(qty) or 1, tonumber(max) or 1)
end

local function cancelLabel()
  return say(rom("gFameCheckerText_Cancel"))
end

-- A local a screen keeps out of reach, found by name among the upvalues of
-- the function that uses it, searching nested local functions a few levels
-- deep (the summary's page titles live in a helper of its draw).  Read,
-- never copied; nil if upstream renames it.
local upvalueCache = setmetatable({}, { __mode = "k" })
local function screenLocal(fn, name, depth)
  if type(fn) ~= "function" then return nil end
  local cached = upvalueCache[fn]
  if not cached then
    cached = {}
    upvalueCache[fn] = cached
  end
  local value = cached[name]
  if value ~= nil then return value or nil end
  value = false
  local seen = {}
  local function search(f, level)
    if seen[f] then return nil end
    seen[f] = true
    local nested = {}
    for i = 1, 255 do
      local upName, upValue = debug.getupvalue(f, i)
      if upName == nil then break end
      if upName == name then return upValue end
      if type(upValue) == "function" then nested[#nested + 1] = upValue end
    end
    if level <= 0 then return nil end
    for _, inner in ipairs(nested) do
      local found = search(inner, level - 1)
      if found ~= nil then return found end
    end
    return nil
  end
  local found = search(fn, depth or 2)
  if found ~= nil then value = found end
  cached[name] = value
  return value or nil
end
Items.screenLocal = screenLocal

-- The mode bookkeeping every presenter shares: `fresh` when the layer
-- changed or the screen came back to the top; `from` the mode before.
local function modeChange(memo, mode, entering)
  local from = memo.mode
  local fresh = entering or mode ~= from
  memo.mode = mode
  return fresh, from
end

-- ------------------------------------------------------------------ items

local function itemsData() return loaded("src.core.game3.items_data") end

local function itemInfo(id)
  local D = itemsData()
  return D and try(D.info, id) or nil
end

local function itemName(id)
  local D = itemsData()
  return D and try(D.displayName, id) or nil
end

local function itemDescription(id)
  local D = itemsData()
  return D and try(D.description, id) or nil
end

local function numericId(id)
  local D = itemsData()
  return D and try(D.toNumericId, id) or tonumber(id)
end

-- The rows Bag.listPocket returns ({ id, qty } for every slot holding at
-- least one), read from the bag's own pocket without running its ensure().
-- A legacy bag without pockets is listed the way BagMenu.list lists it.
local function pocketRows(bag, pocket)
  local rows = {}
  if type(bag) ~= "table" then return rows end
  if type(bag.pockets) == "table" then
    for _, slot in ipairs(bag.pockets[pocket] or {}) do
      local qty = tonumber(slot.qty) or 0
      if slot.id ~= nil and qty > 0 then rows[#rows + 1] = { id = slot.id, qty = qty } end
    end
    return rows
  end
  local D = itemsData()
  if type(bag.stacks) ~= "table" or not D then return rows end
  for id, qty in pairs(bag.stacks) do
    if try(D.pocketOf, id) == pocket and (tonumber(qty) or 0) > 0 then
      rows[#rows + 1] = { id = id, qty = qty, name = itemName(id) }
    end
  end
  table.sort(rows, function(a, b) return tostring(a.name) < tostring(b.name) end)
  return rows
end
Items.pocketRows = pocketRows

-- How many of an item the bag holds (the shop's IN BAG count), summed from
-- the item's pocket like Bag.get does, without its ensure().
local function bagCount(bag, id)
  local D = itemsData()
  if type(bag) ~= "table" or type(bag.pockets) ~= "table" or not D then return nil end
  local pocket = try(D.pocketOf, id)
  local want = numericId(id)
  local total = 0
  for _, slot in ipairs(bag.pockets[pocket] or {}) do
    if slot.id ~= nil and (numericId(slot.id) == want or slot.id == id) then
      total = total + (tonumber(slot.qty) or 0)
    end
  end
  return total
end

-- The money window's text (src/money.c: MONEY and the ¥ amount).
local function moneyString(amount)
  local n = math.max(0, math.floor(tonumber(amount) or 0))
  return say(rom("gText_PokedollarVar1", { stringVars = { tostring(n) } })) or tostring(n)
end
local function moneyText(amount)
  return join({ say(rom("gText_TrainerCardMoney")), moneyString(amount) }, " ")
end
Items.moneyText = moneyText

-- --------------------------------------------------------------- Pokémon

local function pokemon() return loaded("src.core.game3.pokemon") end
local function summaryData() return loaded("src.core.game3.summary_data") end

local function monName(mon)
  local P = pokemon()
  return P and say(try(P.displayName, mon)) or nil
end

local function speciesName(mon)
  local P = pokemon()
  if not P then return nil end
  local species = try(P.speciesOf, mon)
  return species and say(try(P.name, species)) or nil
end

local function isEgg(mon)
  local P = pokemon()
  if P and P.isEgg then return try(P.isEgg, mon) == true end
  return type(mon) == "table" and mon.isEgg == true
end

local function typeName(id)
  local Types = loaded("src.core.game3.battle.types")
  if not Types then return nil end
  if type(id) == "string" then id = Types.ID and Types.ID[id:upper()] end
  if id == nil then return nil end
  return say(try(Types.name, id))
end

local function typesText(t1, t2)
  local first = typeName(t1)
  if not first then return nil end
  local second = (t2 ~= nil and t2 ~= t1 and t2 ~= "") and typeName(t2) or nil
  return "type " .. join({ first, second }, " and ")
end

local function genderWord(g)
  if g == "M" or g == "male" then return "male" end
  if g == "F" or g == "female" then return "female" end
  return nil
end

-- Words for the status icons (no text on the screen), keyed by the codes
-- SummaryData.statusAilment documents: 1 PSN, 2 PRZ, 3 SLP, 4 FRZ, 5 BRN,
-- 6 PKRS, 7 FNT.
local STATUS_WORDS = {
  [1] = "poisoned", [2] = "paralyzed", [3] = "asleep", [4] = "frozen",
  [5] = "burned", [6] = "POKéRUS", [7] = "fainted",
}

local function ailment(mon)
  local D = summaryData()
  return D and tonumber(try(D.statusAilment, mon)) or 0
end

local function levelVisible(mon, where, game)
  local LevelDisplay = loaded("src.ui.LevelDisplay")
  if not (LevelDisplay and LevelDisplay.visible) then return true end
  local ok, visible = pcall(LevelDisplay.visible, mon, where, game)
  return not ok or visible ~= false
end

local function levelText(mon)
  local level = type(mon) == "table" and tonumber(mon.level)
  if not level then return nil end
  return say((rom("gText_Lv") or "level ") .. tostring(level))
end

-- A move's name, type and PP.  A missing PP count means full (the screens
-- fill it from the maximum); PP is left out when the maximum is unknown.
local function moveFacts(moveId, pp, maxPp)
  local P = pokemon()
  if not P or moveId == nil then return nil end
  local def = try(P.battleMove, moveId) or {}
  local name = say(try(P.moveName, moveId)) or say(def.name)
  if not name then return nil end
  local max = tonumber(maxPp) or tonumber(def.pp)
  local parts = { name, typeName(def.type) }
  if max and max > 0 then
    parts[#parts + 1] = string.format("PP %d of %d", tonumber(pp) or max, max)
  end
  return join(parts), def
end

local function powerAccuracy(def)
  if type(def) ~= "table" then return nil end
  local power = tonumber(def.power)
  local accuracy = tonumber(def.accuracy)
  return join({ (power and power > 1) and ("power " .. power) or nil,
    (accuracy and accuracy > 0) and ("accuracy " .. accuracy) or nil })
end

local function moveDescription(moveId, name)
  local D = summaryData()
  local text = D and try(D.moveDescription, moveId, name)
  if text == nil or text == "---" then return nil end
  return say(text)
end

-- ------------------------------------------------------------- sell flow
-- src/ui/game3/sell_flow.lua, held by the bag, TM case and berry pouch
-- while their mode is "sell": state cant | qty | confirm | done, its own
-- message `text`, `qty` up to `owned`, total(), `yesNo`.

local function sellQuantity(flow, first)
  local total = try(flow.total, flow)
  local price = total and moneyString(total) or nil
  if first then return join({ quantity(flow.qty, flow.owned), price }) end
  return join({ tostring(flow.qty or 1), price })
end

local function readSell(flow, memo, fresh)
  if type(flow) ~= "table" then return nil end
  if memo.sellFlow ~= flow then
    memo.sellFlow, memo.sellState = flow, nil
    fresh = true
  end
  local st = flow.state
  if not st then return nil end
  local changed = fresh or st ~= memo.sellState
  memo.sellState = st
  local session = flow.session
  local text
  if st == "qty" then
    if changed then
      text = sentences(say(flow.text), sellQuantity(flow, true),
        session and moneyText(session.money) or nil)
    elseif flow.qty ~= memo.sellQty then
      text = sellQuantity(flow, false)
    end
  elseif st == "confirm" then
    if changed then
      text = sentences(say(flow.text), yesNo(flow.yesNo))
    elseif flow.yesNo ~= memo.sellYes then
      text = yesNo(flow.yesNo)
    end
  elseif changed then
    text = say(flow.text)
    if st == "done" and session then text = sentences(text, moneyText(session.money)) end
  end
  memo.sellQty, memo.sellYes = flow.qty, flow.yesNo
  return text
end
Items.readSell = readSell

-- -------------------------------------------------------------------- bag
-- src/ui/game3/bag_menu.lua.  handleInput serves the sell flow, the
-- Black/White Flute wait, deposit, deposit_done, toss, toss_confirm,
-- toss_done, message, action, move, then the list.

local Bag = {}
Items.Bag = Bag

function Bag.pocket(B)
  local D = itemsData()
  return D and D.BAG_POCKET_ORDER and D.BAG_POCKET_ORDER[B.pocketIdx] or "ITEMS"
end

-- The pocket title drawn at the top left (DEPOSIT ITEM at the item PC).
function Bag.title(B, pocket)
  if B._location == "itempc" then return say(rom("gText_DepositItem")) end
  local D = itemsData()
  local label = D and D.POCKET_LABEL and say(try(function() return D.POCKET_LABEL[pocket] end))
  return label and (label .. " pocket") or nil
end

-- One row as BagMenu.draw prints it: the name; the quantity except in the
-- KEY ITEMS and TM CASE pockets and for important items; the SELECT icon
-- of the registered key item; CANCEL after the last row.
function Bag.row(B, rows, i, pocket)
  local row = rows[i]
  if not row then
    if i == #rows + 1 then return cancelLabel() end
    return nil
  end
  local parts = { say(itemName(row.id)) }
  local info = itemInfo(row.id)
  local important = info and (tonumber(info.importance) or 0) ~= 0
  if pocket ~= "KEY_ITEMS" and pocket ~= "TM_CASE" and not important then
    parts[#parts + 1] = "quantity " .. tostring(row.qty)
  else
    local session = B._session
    local registered = session and session.registeredItem
    if registered ~= nil and numericId(registered) == numericId(row.id) then
      parts[#parts + 1] = "registered"
    end
  end
  return join(parts)
end

function Bag.description(rows, i)
  local row = rows[i]
  if not row then return say(rom("gText_CloseBag")) end
  return say(itemDescription(row.id))
end

-- An action label exactly as the bag's local action_label prints it.
function Bag.actionLabel(B, act, row)
  local label = screenLocal(B.draw, "action_label")
  return label and say(try(label, act, row)) or nil
end

function Bag.read(B, memo, entering)
  if not B.open or B._exit then return nil end
  local mode = (B.mode == "sell" and B._sell) and "sell" or (B.mode or "list")
  local fresh, from = modeChange(memo, mode, entering)
  if mode == "sell" then return readSell(B._sell, memo, fresh) end
  -- an unchanged frame costs these comparisons only
  if not fresh and memo.pocketIdx == B.pocketIdx and memo.cursor == B.cursor
      and memo.actionCursor == B.actionCursor and memo.qty == B.tossQty and memo.yesNo == B.yesNoCursor
      and memo.message == B.messageText and memo.msgPage == B._msgPage then
    return nil
  end
  local pocket = Bag.pocket(B)
  local rows = pocketRows(B._bag, pocket)
  local sel = rows[B.cursor]
  local name = sel and say(itemName(sel.id))
  local text
  if mode == "list" then
    local pocketChanged = memo.pocketIdx ~= nil and memo.pocketIdx ~= B.pocketIdx
    if fresh or pocketChanged then
      local context = (entering or pocketChanged or from == nil) and Bag.title(B, pocket) or nil
      local row = Bag.row(B, rows, B.cursor, pocket)
      text = sentences(context, row and join({ row, position(B.cursor, #rows + 1) }),
        Bag.description(rows, B.cursor))
    elseif B.cursor ~= memo.cursor then
      text = sentences(Bag.row(B, rows, B.cursor, pocket), Bag.description(rows, B.cursor))
    end
  elseif mode == "move" then
    if fresh then
      local moving = rows[B.moveFrom]
      local row = Bag.row(B, rows, B.cursor, pocket)
      text = sentences(moving and say(rom("gOtherText_WhereShouldTheStrVar1BePlaced",
        { stringVars = { itemName(moving.id) } })), row and join({ row, position(B.cursor, #rows + 1) }))
    elseif B.cursor ~= memo.cursor then
      text = Bag.row(B, rows, B.cursor, pocket)
    end
  elseif mode == "action" then
    local acts = type(B.ACTIONS) == "table" and B.ACTIONS or {}
    local cursor = B.actionCursor or 1
    local label = Bag.actionLabel(B, acts[cursor], sel)
    if fresh then
      text = sentences(name and say(romBox("gText_Var1IsSelected", { stringVars = { itemName(sel.id) } })),
        label and join({ label, position(cursor, #acts) }))
    elseif cursor ~= memo.actionCursor then
      text = label
    end
  elseif mode == "toss" or mode == "deposit" then
    local max = sel and sel.qty or 1
    if mode == "deposit" then max = math.min(999, max) end
    if fresh then
      local key = mode == "toss" and "gText_TossOutHowManyStrVar1s" or "gText_DepositHowManyStrVars1"
      text = sentences(sel and say(romBox(key, { stringVars = { itemName(sel.id) } })),
        quantity(B.tossQty, max))
    elseif B.tossQty ~= memo.qty then
      text = tostring(B.tossQty)
    end
  elseif mode == "toss_confirm" then
    if fresh then
      text = sentences(say(romBox("gText_ThrowAwayStrVar2OfThisItemQM",
        { stringVars = { [2] = tostring(B.tossQty) } })), yesNo(B.yesNoCursor))
    elseif B.yesNoCursor ~= memo.yesNo then
      text = yesNo(B.yesNoCursor)
    end
  elseif mode == "toss_done" then
    if fresh and sel then
      text = say(romBox("gText_ThrewAwayStrVar2StrVar1s",
        { stringVars = { itemName(sel.id), tostring(B.tossQty) } }))
    end
  elseif mode == "deposit_done" then
    if fresh then text = say(B._depositText) end
  elseif mode == "message" then
    if fresh or B.messageText ~= memo.message or B._msgPage ~= memo.msgPage then
      text = say(B.messageText)
    end
  end
  memo.pocketIdx, memo.cursor, memo.actionCursor = B.pocketIdx, B.cursor, B.actionCursor
  memo.qty, memo.yesNo = B.tossQty, B.yesNoCursor
  memo.message, memo.msgPage = B.messageText, B._msgPage
  return text
end

Items.bag = {
  matches = Common.matcher("bag", "src.ui.game3.bag_menu"),
  poll = function(state, memo, entering)
    local text = Bag.read(state.mod, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

-- ---------------------------------------------------------------- TM case
-- src/ui/game3/tm_case.lua: sell flow, message, action, list.

local Tm = {}
Items.Tm = Tm

-- The row label as drawTmLabel draws it: the text segments of the screen's
-- own TmCase.labelIr (number and move); an HM row also shows the HM icon.
function Tm.label(T, id)
  local segments = try(T.labelIr, id)
  local out = {}
  for _, seg in ipairs(type(segments) == "table" and segments or {}) do
    if seg.t == "text" and seg.s then out[#out + 1] = seg.s end
  end
  local label = say(table.concat(out))
  local D = itemsData()
  if label and D and try(D.isHm, id) then label = "HM " .. label end
  return label
end

function Tm.row(T, rows, i)
  local row = rows[i]
  if not row then
    if i == #rows + 1 then return say(rom("gText_Close")) end
    return nil
  end
  local D = itemsData()
  local parts = { Tm.label(T, row.id) }
  if not (D and try(D.isHm, row.id)) then parts[#parts + 1] = "quantity " .. tostring(row.qty) end
  return join(parts)
end

-- The left pane (TYPE, POWER, ACCURACY, PP; the labels are an image) and
-- the description, as TmCase.draw shows them for the selected row.
function Tm.details(rows, i)
  local row = rows[i]
  if not row then return say(rom("gText_TMCaseWillBePutAway")) end
  local P = pokemon()
  local moveId = P and try(P.moveFromTmItem, row.id)
  local def = (P and moveId and try(P.battleMove, moveId)) or {}
  local pp = tonumber(def.pp)
  local facts = join({ typeName(def.type) and ("type " .. typeName(def.type)) or nil, powerAccuracy(def),
    (pp and pp > 0) and ("PP " .. pp) or nil })
  local moveName = P and moveId and try(P.moveName, moveId)
  local desc = moveDescription(moveId, moveName) or say(itemDescription(row.id))
  return sentences(facts, desc)
end

function Tm.read(T, memo, entering)
  if not T.open then return nil end
  local mode = (T.mode == "sell" and T._sell) and "sell" or (T.mode or "list")
  local fresh, from = modeChange(memo, mode, entering)
  if mode == "sell" then return readSell(T._sell, memo, fresh) end
  if not fresh and memo.cursor == T.cursor and memo.actionCursor == T.actionCursor
      and memo.message == T.messageText then
    return nil
  end
  local rows = pocketRows(T._bag, "TM_CASE")
  local sel = rows[T.cursor]
  local text
  if mode == "list" then
    if fresh then
      local row = Tm.row(T, rows, T.cursor)
      text = sentences((entering or from == nil) and say(rom("gText_TMCase")) or nil,
        row and join({ row, position(T.cursor, #rows + 1) }), Tm.details(rows, T.cursor))
    elseif T.cursor ~= memo.cursor then
      text = sentences(Tm.row(T, rows, T.cursor), Tm.details(rows, T.cursor))
    end
  elseif mode == "action" then
    local acts = screenLocal(T.draw, "ACTIONS") or {}
    local cursor = T.actionCursor or 1
    local label = say(romAt("sMenuActions", cursor - 1))
    if fresh then
      text = sentences(sel and say(romBox("gText_Var1IsSelected", { stringVars = { Tm.label(T, sel.id) } })),
        label and join({ label, position(cursor, #acts) }))
    elseif cursor ~= memo.actionCursor then
      text = label
    end
  elseif mode == "message" then
    if fresh or T.messageText ~= memo.message then text = say(T.messageText) end
  end
  memo.cursor, memo.actionCursor, memo.message = T.cursor, T.actionCursor, T.messageText
  return text
end

Items.tmCase = {
  matches = Common.matcher("tm_case", "src.ui.game3.tm_case"),
  poll = function(state, memo, entering)
    local text = Tm.read(state.mod, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

-- ----------------------------------------------------------- berry pouch
-- src/ui/game3/berry_pouch.lua: sell flow, toss_select, toss_confirm,
-- message, action, list.

local Berry = {}
Items.Berry = Berry

function Berry.row(P, rows, i)
  local row = rows[i]
  if not row then
    if i == #rows + 1 and not P._fromBerryCrush then return say(rom("gText_Close")) end
    return nil
  end
  local D = itemsData()
  local number = D and try(D.berryNumber, row.id) or i
  return join({ say(string.format("№%02d", number)), say(itemName(row.id)), "quantity " .. tostring(row.qty) })
end

function Berry.description(P, rows, i)
  local row = rows[i]
  if not row then
    if P._fromBerryCrush then return nil end
    return say(rom("gText_TheBerryPouchWillBePutAway"))
  end
  return say(itemDescription(row.id))
end

function Berry.read(P, memo, entering)
  if not P.open then return nil end
  local mode = (P.mode == "sell" and P._sell) and "sell" or (P.mode or "list")
  local fresh, from = modeChange(memo, mode, entering)
  if mode == "sell" then return readSell(P._sell, memo, fresh) end
  if not fresh and memo.cursor == P.cursor and memo.actionCursor == P.actionCursor and memo.qty == P.tossQty
      and memo.yesNo == P.yesNoCursor and memo.message == P.messageText then
    return nil
  end
  local rows = pocketRows(P._bag, "BERRY_POUCH")
  local total = #rows + (P._fromBerryCrush and 0 or 1)
  local sel = rows[P.cursor]
  local text
  if mode == "list" then
    if fresh then
      local row = Berry.row(P, rows, P.cursor)
      text = sentences((entering or from == nil) and say(rom("gText_BerryPouch")) or nil,
        row and join({ row, position(P.cursor, math.max(total, 1)) }), Berry.description(P, rows, P.cursor))
    elseif P.cursor ~= memo.cursor then
      text = sentences(Berry.row(P, rows, P.cursor), Berry.description(P, rows, P.cursor))
    end
  elseif mode == "action" then
    local acts = screenLocal(P.draw, "ACTIONS") or {}
    local actionText = screenLocal(P.draw, "ACTION_TEXT") or {}
    local cursor = P.actionCursor or 1
    local index = actionText[acts[cursor]]
    local label = index and say(romAt("sContextMenuActions", index)) or nil
    if fresh then
      text = sentences(sel and say(romBox("gText_Var1IsSelected", { stringVars = { itemName(sel.id) } })),
        label and join({ label, position(cursor, #acts) }))
    elseif cursor ~= memo.actionCursor then
      text = label
    end
  elseif mode == "toss_select" then
    if fresh then
      text = sentences(sel and say(romBox("gText_TossOutHowManyStrVar1s", { stringVars = { itemName(sel.id) } })),
        quantity(P.tossQty, sel and sel.qty or 1))
    elseif P.tossQty ~= memo.qty then
      text = tostring(P.tossQty)
    end
  elseif mode == "toss_confirm" then
    if fresh then
      text = sentences(say(romBox("gText_ThrowAwayStrVar2OfThisItemQM",
        { stringVars = { [2] = tostring(P.tossQty) } })), yesNo(P.yesNoCursor))
    elseif P.yesNoCursor ~= memo.yesNo then
      text = yesNo(P.yesNoCursor)
    end
  elseif mode == "message" then
    if fresh or P.messageText ~= memo.message then text = say(P.messageText) end
  end
  memo.cursor, memo.actionCursor, memo.qty = P.cursor, P.actionCursor, P.tossQty
  memo.yesNo, memo.message = P.yesNoCursor, P.messageText
  return text
end

-- Berry Crush's berry choice (src/ui/game3/minigames/berry_crush/pouch.lua)
-- opens the berry pouch, then pushes its own layer under the same id, which
-- replaces the pouch's layer; the pouch module still holds the list.
local matchesPouch = Common.matcher("berry_pouch", "src.ui.game3.berry_pouch")
local matchesCrushPouch = Common.matcher("berry_pouch", "src.ui.game3.minigames.berry_crush.pouch")

Items.berryPouch = {
  matches = function(state) return matchesPouch(state) or matchesCrushPouch(state) end,
  poll = function(state, memo, entering)
    local P = package.loaded["src.ui.game3.berry_pouch"]
    if not P then return nil end
    local text = Berry.read(P, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

-- ------------------------------------------------------------------ party
-- src/ui/game3/party_menu.lua.  handleInput serves the Poké Dude demo, the
-- HP bar (input waits for it), message, oak (battle advice), yesno,
-- forget, summary, switch, item_action, stat_growth, action, then the
-- list-like modes (list, use, give, choose, choose_multi, move_tutor,
-- softboiled, battle_switch, battle_faint).

local Party = {}
Items.Party = Party

local SLOT_CANCEL = 7          -- PartyMenu's CANCEL button
local SLOT_CONFIRM_MULTI = 7   -- choose_multi: CONFIRM, then CANCEL
local SLOT_CANCEL_MULTI = 8

local function partySession(P)
  if P._session then return P._session end
  local Runtime = loaded("src.core.game3.runtime")
  return Runtime and try(Runtime.getSession) or nil
end

-- One slot as draw_filled_slot draws it: nickname; an egg shows its name
-- only; the level when the status icon is clear (or POKéRUS); the gender
-- mark except on Nidoran; the slot description (ABLE, NOT ABLE, LEARNED
-- ...) in place of HP; the status and held-item icons in words.
function Party.slot(P, i)
  local party = P._party or {}
  local mon = party[i]
  if type(mon) ~= "table" then return nil end
  local parts = { monName(mon) }
  local desc = say(try(P.slotDescription, i))
  if isEgg(mon) then
    parts[#parts + 1] = desc
    return join(parts)
  end
  -- the species after a nickname, as the Gen 2 party says it (the slot
  -- itself prints the nickname only)
  local species = speciesName(mon)
  if species and species ~= parts[1] then parts[#parts + 1] = species end
  local code = ailment(mon)
  if code == 0 or code == 6 then
    local session = partySession(P)
    local Runtime = loaded("src.core.game3.runtime")
    local game = (session and session.game) or (Runtime and Runtime._game)
    if levelVisible(mon, "party", game) then parts[#parts + 1] = levelText(mon) end
  end
  local speciesId = tonumber(mon.species)
  if speciesId ~= 29 and speciesId ~= 32 then
    local P3 = pokemon()
    local g = mon.gender or (P3 and try(P3.gender, mon.species, mon.personality))
    parts[#parts + 1] = genderWord(g)
  end
  if desc then
    parts[#parts + 1] = desc
  else
    local hp = tonumber(mon.hp) or 0
    local maxHp = tonumber(mon.maxHp) or tonumber(mon.maxhp)
    local anim = P._hpAnim
    if anim and anim.slot == i and anim.current then hp = math.floor(anim.current + 0.5) end
    if maxHp then parts[#parts + 1] = string.format("HP %d of %d", hp, maxHp) end
  end
  parts[#parts + 1] = STATUS_WORDS[code]
  local frame = try(P.heldItemFrame, mon)
  if frame == 1 then
    parts[#parts + 1] = "holding mail"
  elseif frame == 0 then
    parts[#parts + 1] = "holding an item"
  end
  return join(parts)
end

-- The row under the cursor with the CANCEL (and CONFIRM) buttons after the
-- slots, and its position among them.
function Party.row(P, cursor)
  local n = #(P._party or {})
  local multi = P.mode == "choose_multi"
  local count = n + (multi and 2 or 1)
  local text, index
  if multi and cursor == SLOT_CONFIRM_MULTI then
    text, index = say(rom("gMenuText_Confirm")), n + 1
  elseif multi and cursor == SLOT_CANCEL_MULTI then
    text, index = cancelLabel(), n + 2
  elseif not multi and cursor == SLOT_CANCEL then
    text, index = cancelLabel(), n + 1
  else
    text, index = Party.slot(P, cursor), cursor
  end
  return text, index, count
end

-- The prompt at the bottom, chosen the way PartyMenu.draw chooses it.
function Party.prompt(P)
  local key = "gText_ChoosePokemon"
  local D = itemsData()
  if P.mode == "switch" then
    key = "gText_MoveToWhere"
  elseif P.mode == "use" then
    key = (P._item and D and try(D.isTm, P._item)) and "gText_TeachWhichPokemon" or "gText_UseOnWhichPokemon"
  elseif P.mode == "give" then
    key = "gText_GiveToWhichPokemon"
  elseif P.mode == "move_tutor" then
    key = "gText_TeachWhichPokemon"
  end
  return say(rom(key))
end

local function actionLabel(P, act)
  if type(act) == "table" then return say(act.label) end
  return say(try(P._cursorOptionText, act))
end

local function menuText(P, list, cursor, prompt, fresh, memoCursor)
  list = type(list) == "table" and list or {}
  local label = actionLabel(P, list[cursor])
  if fresh then return sentences(prompt, label and join({ label, position(cursor, #list) })) end
  if cursor ~= memoCursor then return label end
  return nil
end

-- The level-up window: page 1 the gains, page 2 the new values; the stat
-- names are the cart's (sLevelUpWindowStatNames).
function Party.statGrowth(P)
  local R = romText()
  local names = R and try(R.list, "sLevelUpWindowStatNames") or {}
  local old, new = P._statGrowthOld or {}, P._statGrowthNew or {}
  local keys = { "maxHp", "atk", "def", "spa", "spd", "spe" }
  local parts = {}
  for i, key in ipairs(keys) do
    local label = say(names[i])
    if label then
      if P._statGrowthPage == 1 then
        local diff = (tonumber(new[key]) or 0) - (tonumber(old[key]) or 0)
        parts[#parts + 1] = string.format("%s %s%d", label, diff >= 0 and "plus " or "minus ", math.abs(diff))
      else
        parts[#parts + 1] = string.format("%s %d", label, tonumber(new[key]) or 0)
      end
    end
  end
  return join(parts)
end

local LIST_MODES = {
  list = true, use = true, give = true, choose = true, choose_multi = true, move_tutor = true,
  softboiled = true, battle_switch = true, battle_faint = true,
}

function Party.read(P, memo, entering)
  if not P.open then return nil end
  local mode = P.mode or "list"
  if P._hpAnim then return nil end -- the message follows once the bar stops
  local fresh, from = modeChange(memo, mode, entering)
  local orderCount = type(P._chooseOrder) == "table" and #P._chooseOrder or 0
  local oakPage = P._oakFx and P._oakFx.phase == "text" and P._oakWrapped or nil
  if not fresh and memo.cursor == P.cursor and memo.actionCursor == P.actionCursor
      and memo.itemCursor == P.itemActionCursor and memo.message == P._messageText
      and memo.dismiss == P._onMessageDismiss and memo.prompt == P._yesNoPrompt and memo.yesNo == P._yesNoCursor
      and memo.forget == P._forgetMoves and memo.forgetCursor == P._forgetCursor
      and memo.growthPage == P._statGrowthPage and memo.order == orderCount and memo.oak == oakPage then
    return nil
  end
  local text
  if mode == "message" then
    if fresh or P._messageText ~= memo.message or P._onMessageDismiss ~= memo.dismiss then
      text = say(P._messageText)
    end
  elseif mode == "oak" then
    if oakPage and (fresh or oakPage ~= memo.oak) then text = say(oakPage) end
  elseif mode == "yesno" then
    if fresh or P._yesNoPrompt ~= memo.prompt then
      text = sentences(say(P._yesNoPrompt), yesNo(P._yesNoCursor))
    elseif P._yesNoCursor ~= memo.yesNo then
      text = yesNo(P._yesNoCursor)
    end
  elseif mode == "forget" then
    local moves = type(P._forgetMoves) == "table" and P._forgetMoves or {}
    local cursor = P._forgetCursor or 1
    local move = say(moves[cursor])
    if fresh or P._forgetMoves ~= memo.forget then
      text = sentences(say(P._forgetPrompt), move and join({ move, position(cursor, #moves) }))
    elseif cursor ~= memo.forgetCursor then
      text = move
    end
  elseif mode == "action" then
    text = menuText(P, P.ACTIONS, P.actionCursor or 1, say(rom("gText_DoWhatWithPokemon")), fresh, memo.actionCursor)
  elseif mode == "item_action" then
    text = menuText(P, P.ITEM_ACTIONS, P.itemActionCursor or 1, say(rom("gText_DoWhatWithItem")), fresh,
      memo.itemCursor)
  elseif mode == "stat_growth" then
    if fresh or P._statGrowthPage ~= memo.growthPage then
      text = sentences(fresh and say(P._messageText) or nil, Party.statGrowth(P))
    end
  elseif mode == "switch" or LIST_MODES[mode] then
    local row, index, count = Party.row(P, P.cursor)
    local withPosition = row and join({ row, position(index, count) })
    if fresh then
      -- back on the list from one of its own layers (sub-menu, message,
      -- YES/NO, a switch made): the row under the cursor with its position
      -- (after a switch, the Pokémon now there).  Otherwise the prompt.
      local back = not entering and mode ~= "switch" and mode ~= "softboiled" and from ~= nil and from ~= "oak"
        and not LIST_MODES[from]
      if back then
        text = withPosition
      else
        text = sentences(Party.prompt(P), withPosition)
      end
    elseif P.cursor ~= memo.cursor then
      text = row
    elseif mode == "choose_multi" and memo.order ~= nil and orderCount ~= memo.order then
      text = row
    end
  end
  memo.message, memo.dismiss, memo.prompt = P._messageText, P._onMessageDismiss, P._yesNoPrompt
  memo.yesNo, memo.forget, memo.forgetCursor = P._yesNoCursor, P._forgetMoves, P._forgetCursor
  memo.actionCursor, memo.itemCursor, memo.growthPage = P.actionCursor, P.itemActionCursor, P._statGrowthPage
  memo.cursor, memo.order, memo.oak = P.cursor, orderCount, oakPage
  return text
end

Items.party = {
  matches = Common.matcher("party", "src.ui.game3.party_menu"),
  -- through the profile's text aliases, as the party screen itself runs:
  -- Ruby and Sapphire name its strings differently (no effect in FireRed)
  poll = function(state, memo, entering)
    local Screens = loaded("src.ui.game3.screens")
    if Screens and Screens.withTextAliases then
      return Screens.withTextAliases(nil, Items.partyPoll, state, memo, entering)
    end
    return Items.partyPoll(state, memo, entering)
  end,
}

function Items.partyPoll(state, memo, entering)
  return Items._partyPoll(state, memo, entering)
end

Items._partyPresenter = {
  poll = function(state, memo, entering)
    local text = Party.read(state.mod, memo, entering)
    if not text then return nil end
    return text, true
  end,
}
Items._partyPoll = Items._partyPresenter.poll

-- ---------------------------------------------------------------- summary
-- src/ui/game3/summary_menu.lua.  Pages INFO, SKILLS, KNOWN MOVES, the
-- move detail (cursor over 4 moves and a fifth row: CANCEL, or the move to
-- learn in the battle's select_move mode) and EGG.

local Summary = {}
Items.Summary = Summary

local PAGE_INFO, PAGE_SKILLS, PAGE_MOVES, PAGE_MOVES_INFO, PAGE_EGG = 0, 1, 2, 3, 4

local function summarySession(S)
  if S._playerState then return S._playerState end
  local Runtime = loaded("src.core.game3.runtime")
  return Runtime and try(Runtime.getSession) or nil
end

function Summary.mon(S)
  return type(S._party) == "table" and S._party[S._cursor] or nil
end

-- Nickname, level, gender and the shiny star (draw_header, left strip).
function Summary.header(S, mon)
  local D = summaryData()
  local session = summarySession(S)
  local Runtime = loaded("src.core.game3.runtime")
  local game = (session and session.game) or (Runtime and Runtime._game)
  local egg = isEgg(mon)
  return join({ monName(mon),
    (not egg and levelVisible(mon, "summary", game)) and levelText(mon) or nil,
    not egg and genderWord(D and try(D.gender, mon)) or nil,
    (not egg and D and try(D.isShiny, mon) == true) and "shiny" or nil })
end

-- The page title in the top bar (the screen's local PAGE_TITLES), with
-- the page's place among the three pages L and R flip through.
function Summary.pageTitle(S, page)
  local titles = screenLocal(S.draw, "PAGE_TITLES", 3)
  local title = titles and say(try(function() return titles[page] end))
  if page <= PAGE_MOVES then return join({ title, string.format("page %d of 3", page + 1) }) end
  return title
end

local function memoLines(S, mon)
  local D = summaryData()
  local lines = D and try(D.formatTrainerMemo, mon, S._playerState,
    { enemyParty = S._enemyParty, owner = S._owner })
  if type(lines) ~= "table" then return nil end
  return say(table.concat(lines, "\n"))
end

local function monTypes(mon)
  local P = pokemon()
  local species = P and try(P.speciesOf, mon)
  local types = (P and species and try(P.types, species)) or {}
  return mon.type1 or types[1], mon.type2 or types[2]
end

function Summary.info(S, mon)
  local session = summarySession(S)
  local dexNo = try(S.dexNoText, mon, S._playerState)
  local otName = mon.otName or mon.ot or mon.originalTrainer or (session and (session.name or session.playerName))
  local otId = tonumber(mon.otId or mon.ot_id or mon.trainerId
    or (session and (session.trainerId or session.id or session.playerId)))
  return sentences(join({ dexNo and ("number " .. say(dexNo)) or nil, speciesName(mon), typesText(monTypes(mon)),
    otName and ("OT " .. say(otName)) or nil,
    otId and ("ID " .. string.format("%05d", otId % 65536)) or nil,
    "item " .. (say(try(S.heldItemText, mon)) or "") }), memoLines(S, mon))
end

function Summary.skills(S, mon)
  local P = pokemon()
  local D = summaryData()
  local hp, maxHp = tonumber(mon.hp or mon.currentHp) or 0, tonumber(mon.maxHp or mon.maxhp)
  local function stat(label, ...)
    for _, key in ipairs({ ... }) do
      if mon[key] ~= nil then return label .. " " .. tostring(mon[key]) end
    end
    return nil
  end
  local prog = D and try(D.expProgress, mon) or {}
  local abilityId = tonumber(mon.abilityId) or tonumber(mon.ability)
  local ability = mon.abilityName
  if type(mon.ability) == "string" and mon.ability ~= "" and not tonumber(mon.ability) then ability = mon.ability end
  if (not ability or ability == "") and abilityId and abilityId > 0 and P then ability = try(P.abilityName, abilityId) end
  if (not ability or ability == "") and P and P.abilityId then
    local aid = try(P.abilityId, try(P.speciesOf, mon), mon.personality or 0)
    if aid and aid > 0 then
      abilityId, ability = aid, try(P.abilityName, aid)
    end
  end
  local abilityDesc = D and ability and try(D.abilityDescription, abilityId, tostring(ability))
  return sentences(join({ maxHp and string.format("HP %d of %d", hp, maxHp) or nil,
      stat("attack", "attack", "atk"), stat("defense", "defense", "def"),
      stat("special attack", "spAtk", "spatk"), stat("special defense", "spDef", "spdef"),
      stat("speed", "speed", "spe") }),
    join({ prog.totalExp and join({ say(rom("gText_PokeSum_ExpPoints")), tostring(prog.totalExp) }, " ") or nil,
      prog.expNeeded and join({ say(rom("gText_PokeSum_NextLv")), tostring(prog.expNeeded) }, " ") or nil }),
    ability and join({ "ability " .. say(ability), say(abilityDesc) }) or nil)
end

-- The four moves (and the fifth row in select_move) as moves_for_mon
-- reads them: the maximum PP from mon.maxPp or the move's own PP.
function Summary.move(S, mon, slot)
  if slot == 5 then
    if S._mode == "select_move" and not S._forgetMove and S._moveToLearn ~= nil then
      local P = pokemon()
      local id = tonumber(S._moveToLearn) or (P and P.battleMoveId and try(P.battleMoveId, S._moveToLearn))
      if id then return moveFacts(id, nil, nil) end
      return nil
    end
    return cancelLabel()
  end
  local entry = type(mon.moves) == "table" and mon.moves[slot] or nil
  local moveId, pp
  if type(entry) == "table" then
    moveId = entry.id or entry.move or entry.moveId or entry.num or entry.name or entry[1]
    pp = entry.pp
  else
    moveId = entry
    pp = type(mon.pp) == "table" and mon.pp[slot] or nil
  end
  if moveId == nil or moveId == 0 or moveId == "" then return nil end
  local maxPp = type(mon.maxPp) == "table" and mon.maxPp[slot] or nil
  return moveFacts(moveId, pp, maxPp)
end

function Summary.moveId(S, mon, slot)
  if slot == 5 then return tonumber(S._moveToLearn) end
  local entry = type(mon.moves) == "table" and mon.moves[slot] or nil
  if type(entry) == "table" then return entry.id or entry.move or entry.moveId or entry.num end
  return entry
end

function Summary.moves(S, mon)
  local rows = {}
  for slot = 1, 4 do
    local row = Summary.move(S, mon, slot)
    if row then rows[#rows + 1] = row end
  end
  if #rows == 0 then return nil end
  return "moves: " .. table.concat(rows, "; ")
end

-- The move detail row under the cursor: name, type, PP, then power,
-- accuracy and description, or the HM notice when it is shown.
function Summary.detail(S, mon, withPosition)
  local cursor = S._moveCursor or 1
  local row, def = Summary.move(S, mon, cursor)
  if not row then row = say(rom("gText_PokeSum_OneHyphen")) end
  local parts = { withPosition and join({ row, position(cursor, 5) }) or row }
  if def then
    local P = pokemon()
    local id = Summary.moveId(S, mon, cursor)
    parts[#parts + 1] = powerAccuracy(def)
    parts[#parts + 1] = moveDescription(id, P and try(P.moveName, id))
  end
  return sentences(parts)
end

function Summary.egg(S, mon)
  local D = summaryData()
  return sentences(say(rom("gText_EggNickname")), D and say(try(D.eggHatchText, mon)) or nil, memoLines(S, mon))
end

function Summary.page(S, mon, page)
  if page == PAGE_INFO then return Summary.info(S, mon) end
  if page == PAGE_SKILLS then return Summary.skills(S, mon) end
  if page == PAGE_MOVES then return Summary.moves(S, mon) end
  if page == PAGE_MOVES_INFO then return Summary.detail(S, mon, true) end
  if page == PAGE_EGG then return Summary.egg(S, mon) end
  return nil
end

function Summary.read(S, memo, entering)
  if S._nativeDelegate or not S.open then return nil end
  local mon = Summary.mon(S)
  if type(mon) ~= "table" then return nil end
  local page = S._page
  local text
  local newMon = memo.monIndex ~= S._cursor or memo.mon ~= mon
  if entering or newMon then
    text = sentences(Summary.header(S, mon), Summary.pageTitle(S, page), Summary.page(S, mon, page))
  elseif page ~= memo.page then
    if page == PAGE_MOVES_INFO or memo.page == PAGE_MOVES_INFO then
      text = Summary.page(S, mon, page)
    else
      text = sentences(Summary.pageTitle(S, page), Summary.page(S, mon, page))
    end
  elseif page == PAGE_MOVES_INFO then
    if S._hmNotice and not memo.hmNotice then
      text = say(rom("gText_PokeSum_HmMovesCantBeForgotten"))
    elseif S._swapSlot ~= memo.swap then
      if S._swapSlot then
        local row = Summary.move(S, mon, S._swapSlot)
        text = row and ("moving " .. row)
      else
        text = Summary.detail(S, mon, false)
      end
    elseif S._moveCursor ~= memo.moveCursor then
      text = Summary.detail(S, mon, false)
    end
  end
  memo.monIndex, memo.mon, memo.page = S._cursor, mon, page
  memo.hmNotice, memo.swap, memo.moveCursor = S._hmNotice, S._swapSlot, S._moveCursor
  return text
end

Items.summary = {
  matches = Common.matcher("summary", "src.ui.game3.summary_menu"),
  poll = function(state, memo, entering)
    local text = Summary.read(state.mod, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

-- --------------------------------------------------------------- Pokédex
-- src/ui/game3/pokedex.lua: screen mode_select (table of contents with
-- section headers), category_grid (habitat pages), ordered_list, data (two
-- pages) and registration (the entry shown after a catch).

local Dex = {}
Items.Dex = Dex

local function dexModule() return loaded("src.core.game3.dex") end
local function dexData() return loaded("src.core.game3.pokedex_data") end

local function seen(D, sp)
  local Mod = dexModule()
  return Mod and try(Mod.isSeen, D._dex, sp) == true
end
local function caught(D, sp)
  local Mod = dexModule()
  return Mod and try(Mod.isCaught, D._dex, sp) == true
end

function Dex.counts(D)
  local Mod, Data = dexModule(), dexData()
  if not (Mod and Data) then return nil end
  local dex = D._dex
  local national = try(Data.isNationalUnlocked, D._session, dex) == true
  local seenLabel, ownedLabel = say(rom("gText_Seen")), say(rom("gText_Owned"))
  if national then
    local kanto, nat = say(rom("gText_Kanto")), say(rom("gText_National"))
    return join({ join({ seenLabel, kanto, try(Mod.countSeen, dex, "kanto"), nat, try(Mod.countSeen, dex, "national") }, " "),
      join({ ownedLabel, kanto, try(Mod.countCaught, dex, "kanto"), nat, try(Mod.countCaught, dex, "national") }, " ") })
  end
  return join({ join({ seenLabel, try(Mod.countSeen, dex, "kanto") }, " "),
    join({ ownedLabel, try(Mod.countCaught, dex, "kanto") }, " ") })
end

-- The table of contents row: its label (greyed habitats say so), its
-- place among the rows the cursor stops on, and the section header above
-- it when the cursor has moved into another section.
function Dex.modeRow(D)
  local modes = type(D.MODES) == "table" and D.MODES or {}
  local index, count, header = 0, 0, nil
  for i, m in ipairs(modes) do
    if m.isHeader then
      if i < (D.modeCursor or 1) then header = i end
    else
      count = count + 1
      if i == D.modeCursor then index = count end
    end
  end
  local m = modes[D.modeCursor]
  if type(m) ~= "table" then return nil end
  local label = join({ say(m.label), m.unlocked == false and "unavailable" or nil })
  return label and join({ label, position(index, count) }), header
end

function Dex.number(D, sp, national)
  local P = pokemon()
  local nat = P and try(P.national, sp) or 0
  local num = national and nat or ((D.currentOrder == "numerical_kanto") and sp or nat)
  return say(string.format("№%03d", tonumber(num) or 0))
end

function Dex.listRow(D, list, i)
  local sp = list[i]
  if sp == nil then return nil end
  local P = pokemon()
  local isSeen = seen(D, sp)
  local isCaught = caught(D, sp)
  local types = isCaught and P and try(P.types, sp) or nil
  return join({ Dex.number(D, sp), isSeen and say(try(P and P.name, sp)) or say(rom("gText_5Dashes")),
    isCaught and "caught" or (isSeen and "seen" or nil),
    types and typesText(types[1], types[2]) or nil })
end

function Dex.categoryTitle(D)
  local title = screenLocal(D.draw, "category_title", 2)
  return title and say(try(title, D.currentCategory)) or nil
end

-- A habitat page: its mini cards show the national number and the name
-- once seen.
function Dex.categorySlot(D)
  local Data = dexData()
  local pages = Data and try(Data.getUnlockedCategoryPages, D.currentCategory, D._dex) or {}
  local page = pages[D.categoryPage or 1]
  local mons = page and page.mons or {}
  local sp = mons[D.categorySlot or 1]
  local pageText = string.format("page %d of %d", D.categoryPage or 1, math.max(1, #pages))
  if sp == nil then return nil, pageText end
  local P = pokemon()
  local row = join({ Dex.number(D, sp, true), seen(D, sp) and say(try(P and P.name, sp)) or nil,
    caught(D, sp) and "caught" or nil })
  return row and join({ row, position(D.categorySlot or 1, #mons) }), pageText
end

local function feetAndInches(text)
  text = tostring(text or "")
  return (text:gsub("(%d+)'(%d+)\"", "%1 feet %2 inches"))
end

-- Entry page 1: number, name, category, height and weight once caught
-- (question marks before), and the description.
function Dex.entryPage1(D, sp)
  local P = pokemon()
  local Chrome = loaded("src.ui.game3.pokedex_chrome")
  local entry = Chrome and try(Chrome.getEntry, sp) or {}
  local isCaught = caught(D, sp)
  local parts = { Dex.number(D, sp), say(try(P and P.name, sp)) }
  if isCaught then
    local Units = loaded("src.core.game3.pokedex_units")
    local metric = Units and try(Units.metric, sp)
    local height = (metric and try(Units.height, metric)) or entry.heightFormatted
    local weight = (metric and try(Units.weight, metric)) or entry.weightFormatted
    parts[#parts + 1] = say(entry.categoryName)
    parts[#parts + 1] = height and ("height " .. say(feetAndInches(height))) or nil
    parts[#parts + 1] = weight and ("weight " .. say(weight)) or nil
    return sentences(join(parts), say(entry.description))
  end
  parts[#parts + 1] = "seen"
  return join(parts)
end

-- The names of the places the AREA map marks (Kanto markers), from the
-- region map's own section names, or AREA UNKNOWN as drawn.
function Dex.areaNames(sp)
  local Data = dexData()
  if not Data then return nil end
  local areas = try(Data.getWildAreasForSpecies, sp) or {}
  local kanto = {}
  for _, key in ipairs(areas) do
    if try(Data.getAreaMapKey, key) == "kanto" and try(Data.getAreaMarker, key) then kanto[#kanto + 1] = key end
  end
  if #kanto == 0 then return say(rom("gText_AreaUnknown")), true end
  local Region = loaded("src.import.gba.region_map_extract")
  local byArea = {}
  local secs = Data._areaData and Data._areaData.mapsecToArea or {}
  for secId, area in pairs(secs) do
    if byArea[area] == nil or tostring(secId) < tostring(byArea[area]) then byArea[area] = secId end
  end
  if Region then try(Region.ensureGenerated) end
  local names, said = {}, {}
  for _, key in ipairs(kanto) do
    local secId = byArea[key]
    local raw = Region and secId and Region.SECTION_NAMES and Region.SECTION_NAMES[secId]
    local name = raw and say(translate(raw))
    if name and not said[name] then
      said[name] = true
      names[#names + 1] = name
    end
  end
  if #names == 0 then return nil end
  return table.concat(names, ", ")
end

function Dex.entryPage2(D, sp)
  local P = pokemon()
  local types = caught(D, sp) and P and try(P.types, sp) or nil
  -- AREA UNKNOWN replaces the map, so it is said alone; marked places
  -- follow the AREA title
  local areas, unknown = Dex.areaNames(sp)
  return sentences(join({ Dex.number(D, sp), say(try(P and P.name, sp)), types and typesText(types[1], types[2]) or nil }),
    unknown and areas or join({ say(rom("gText_Area")), areas }, ": "))
end

function Dex.read(D, memo, entering)
  if not D.open then return nil end
  local screen = D.screen
  local fresh, from = modeChange(memo, screen, entering)
  local species = D._regSpecies or D.selectedSpecies
  if not fresh and memo.modeCursor == D.modeCursor and memo.order == D.currentOrder
      and memo.listCursor == D.listCursor and memo.categoryPage == D.categoryPage
      and memo.categorySlot == D.categorySlot and memo.dataPage == D.dataPage and memo.species == species then
    return nil
  end
  local Data = dexData()
  local text
  if screen == "mode_select" then
    local row, header = Dex.modeRow(D)
    if fresh then
      text = sentences((entering or from == nil) and say(rom("gText_PokedexTableOfContents")) or nil,
        (entering or from == nil) and Dex.counts(D) or nil, row)
    elseif D.modeCursor ~= memo.modeCursor then
      local headerLabel = header ~= memo.header and header and D.MODES[header] and say(D.MODES[header].label)
      text = sentences(headerLabel or nil, row)
    end
    memo.header = header
  elseif screen == "ordered_list" then
    local list = Data and try(Data.getOrderList, D.currentOrder, D._dex) or {}
    if fresh or D.currentOrder ~= memo.order then
      local row = Dex.listRow(D, list, D.listCursor or 1)
      text = sentences(say(rom("gText_PokemonListNoColor")), row and join({ row, position(D.listCursor or 1, #list) }))
    elseif D.listCursor ~= memo.listCursor then
      text = Dex.listRow(D, list, D.listCursor or 1)
    end
  elseif screen == "category_grid" then
    local row, pageText = Dex.categorySlot(D)
    if fresh then
      text = sentences(Dex.categoryTitle(D), pageText, row)
    elseif D.categoryPage ~= memo.categoryPage then
      text = sentences(pageText, row)
    elseif D.categorySlot ~= memo.categorySlot then
      text = row
    end
  elseif screen == "data" or screen == "registration" then
    if fresh or species ~= memo.species or D.dataPage ~= memo.dataPage then
      text = (D.dataPage == 2) and Dex.entryPage2(D, species) or Dex.entryPage1(D, species)
    end
  end
  memo.species = species
  memo.modeCursor, memo.order, memo.listCursor = D.modeCursor, D.currentOrder, D.listCursor
  memo.categoryPage, memo.categorySlot, memo.dataPage = D.categoryPage, D.categorySlot, D.dataPage
  return text
end

Items.pokedex = {
  matches = Common.matcher("pokedex", "src.ui.game3.pokedex"),
  poll = function(state, memo, entering)
    local text = Dex.read(state.mod, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

-- ---------------------------------------------------------------- PC menu
-- src/ui/game3/pc_menu.lua (hideBelow false, but it hides the field
-- message).  Modes root, storage_menu, player_pc, item_storage, msg; while
-- item_pc is set a child screen (box storage, item PC, bag) is on top.

local Pc = {}
Items.Pc = Pc

-- The rows of the mode's menu and the cursor's place.  Root rows are the
-- screen's own cached _rootRows, which its draw and input rebuild every
-- frame (_rootEntries itself is not called: it writes that cache).
function Pc.rows(P)
  local mode = P.mode
  if mode == "root" then
    if P._rootKey == nil then return nil end
    return P._rootRows
  elseif mode == "storage_menu" then
    return try(P._storageOptions)
  elseif mode == "player_pc" then
    return P.TOP_ACTIONS
  elseif mode == "item_storage" then
    return P.ITEM_STORAGE_ACTIONS
  end
  return nil
end

local function pcLabel(row)
  if type(row) ~= "table" then return nil end
  return say(try(function() return row.label end))
end

function Pc.read(P, memo, entering)
  if not P.open then return nil end
  local mode = P.mode
  if mode == "item_pc" then
    memo.mode = mode
    return nil
  end
  if not (entering or memo.pending) and mode == memo.mode and P.cursor == memo.cursor and P._status == memo.status then
    return nil
  end
  local rows = Pc.rows(P)
  if mode ~= "msg" and type(rows) ~= "table" then return nil end -- not drawn yet; retry next frame
  local fresh = modeChange(memo, mode, entering or memo.pending)
  memo.pending = nil
  local text
  if mode == "msg" then
    if fresh or P._status ~= memo.status then text = say(P._status) end
  else
    local cursor = P.cursor or 1
    local label = pcLabel(rows[cursor])
    -- storage and item storage rows have a description that follows the
    -- cursor in the status window; the other menus keep their question
    local describes = mode == "storage_menu" or mode == "item_storage"
    if fresh then
      if describes then
        text = sentences(label and join({ label, position(cursor, #rows) }), say(P._status))
      else
        text = sentences(say(P._status), label and join({ label, position(cursor, #rows) }))
      end
    elseif cursor ~= memo.cursor then
      text = describes and sentences(label, say(P._status)) or label
    elseif P._status ~= memo.status and not describes then
      text = say(P._status)
    end
  end
  memo.cursor, memo.status = P.cursor, P._status
  return text
end

Items.pcMenu = {
  matches = Common.matcher("pc_menu", "src.ui.game3.pc_menu"),
  poll = function(state, memo, entering)
    if entering and state.mod and state.mod._rootKey == nil and state.mod.mode == "root" then memo.pending = true end
    local text = Items.Pc.read(state.mod, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

-- ---------------------------------------------------------------- item PC
-- src/ui/game3/item_pc.lua.  Items from session.storage.items (never
-- Storage.ensure).  Modes list, move, submenu, qty, result, msg; party
-- opens the party screen on top.

local ItemPc = {}
Items.ItemPc = ItemPc

local function pcItems(I)
  local session = I._session
  local storage = type(session) == "table" and session.storage or nil
  return type(storage) == "table" and type(storage.items) == "table" and storage.items or nil
end

function ItemPc.row(list, i)
  local entry = list[i]
  if not entry then
    if i == #list + 1 then return cancelLabel() end
    return nil
  end
  return join({ say(itemName(entry.id)), "quantity " .. tostring(entry.qty) })
end

function ItemPc.description(list, i)
  local entry = list[i]
  if not entry then return say(rom("gText_ReturnToPC")) end
  local D = itemsData()
  if D and try(D.pocketOf, entry.id) == "TM_CASE" then
    local P = pokemon()
    return P and say(try(P.moveName, try(P.moveFromTmItem, entry.id))) or nil
  end
  return say(itemDescription(entry.id))
end

function ItemPc.read(I, memo, entering)
  if not I.open then return nil end
  local list = pcItems(I)
  if not list then return nil end
  local mode = I.mode or "list"
  local fresh, from = modeChange(memo, mode, entering)
  local cursor = (I.scroll or 0) + (I.row or 0) + 1
  if not fresh and memo.cursor == cursor and memo.sub == I.subCursor and memo.qty == I.qty
      and memo.result == I.resultText and memo.msg == I.msgText then
    return nil
  end
  local entry = list[cursor]
  local text
  if mode == "list" then
    if fresh then
      local row = ItemPc.row(list, cursor)
      text = sentences((entering or from == nil) and say(rom("gText_WithdrawItem")) or nil,
        row and join({ row, position(cursor, #list + 1) }), ItemPc.description(list, cursor))
    elseif cursor ~= memo.cursor then
      text = sentences(ItemPc.row(list, cursor), ItemPc.description(list, cursor))
    end
  elseif mode == "move" then
    local moving = list[(I.moveOrig or 0) + 1]
    if fresh then
      local row = ItemPc.row(list, cursor)
      text = sentences(moving and say(rom("gOtherText_WhereShouldTheStrVar1BePlaced",
        { stringVars = { itemName(moving.id) } })), row and join({ row, position(cursor, #list + 1) }))
    elseif cursor ~= memo.cursor then
      text = ItemPc.row(list, cursor)
    end
  elseif mode == "submenu" then
    local submenu = screenLocal(I.draw, "SUBMENU") or {}
    local sub = I.subCursor or 1
    local label = submenu[sub] and say(rom(submenu[sub].key)) or nil
    if fresh then
      text = sentences(entry and say(romBox("gText_Var1IsSelected", { stringVars = { itemName(entry.id) } })),
        label and join({ label, position(sub, #submenu) }))
    elseif sub ~= memo.sub then
      text = label
    end
  elseif mode == "qty" then
    if fresh then
      text = sentences(entry and say(romBox("gText_WithdrawHowMany", { stringVars = { itemName(entry.id) } })),
        quantity(I.qty, entry and entry.qty or 1))
    elseif I.qty ~= memo.qty then
      text = tostring(I.qty)
    end
  elseif mode == "result" then
    if fresh or I.resultText ~= memo.result then text = say(I.resultText) end
  elseif mode == "msg" then
    if fresh or I.msgText ~= memo.msg then text = say(I.msgText) end
  end
  memo.cursor, memo.sub, memo.qty, memo.result, memo.msg = cursor, I.subCursor, I.qty, I.resultText, I.msgText
  return text
end

Items.itemPc = {
  matches = Common.matcher("item_pc", "src.ui.game3.item_pc"),
  poll = function(state, memo, entering)
    local text = ItemPc.read(state.mod, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

-- ------------------------------------------------------------ box storage
-- src/ui/game3/box_storage_ui.lua with src/ui/game3/release_seq.lua and
-- the box picker (storage_choose_box.lua).  handleInput serves
-- deposit_box_full, the release sequence, message, party_drawer,
-- action_menu, box_menu, pick_wallpaper, pick_box, then browse.  The grid
-- cursor is cursorSlot: 1..30 the box (6 columns, 5 rows), 0 the box
-- title, -10 PARTY POKéMON, -20 CLOSE BOX; partyCursor 1..6 the drawer, 7
-- its CANCEL.  Live fields are read, never the animated presentation.

local Box = {}
Items.Box = Box

local function storageOf(B)
  local session = B._session
  local storage = type(session) == "table" and session.storage or nil
  return type(storage) == "table" and storage or nil
end

local function storageModule() return loaded("src.core.game3.storage") end

local function boxCount(box)
  local n = 0
  for i = 1, 30 do if box and box.mons and box.mons[i] then n = n + 1 end end
  return n
end

-- The left data panel for a Pokémon (PcChrome.drawLeftDataPanel):
-- nickname, species when it differs, gender, level and held item; an egg
-- shows its egg name only.
function Box.mon(mon)
  if type(mon) ~= "table" then return nil end
  if isEgg(mon) then return say(rom("gText_EggNickname")) end
  local name = monName(mon)
  local species = speciesName(mon)
  local held = tonumber(mon.heldItem or mon.item)
  local heldName = held and held > 0 and say(itemName(held)) or nil
  if heldName == "NONE" then heldName = nil end
  return join({ name, species ~= name and species or nil, genderWord(mon.gender), levelText(mon),
    heldName and ("holding " .. heldName) or nil })
end

function Box.boxName(storage, index)
  local box = storage and storage.boxes and storage.boxes[index]
  return box and say(box.name) or nil
end

local function totalBoxes()
  local Storage = storageModule()
  return Storage and tonumber(Storage.TOTAL_BOXES_COUNT) or 14
end

function Box.partyButton() return "PARTY POKéMON button" end
function Box.closeButton() return "CLOSE BOX button" end

-- What the grid cursor is on.
function Box.cursorText(B, storage)
  local slot = B.cursorSlot
  local current = storage.currentBox or 1
  if slot == -10 then return Box.partyButton() end
  if slot == -20 then return Box.closeButton() end
  if slot == 0 then return join({ Box.boxName(storage, current), position(current, totalBoxes()) }) end
  if type(slot) ~= "number" or slot < 1 or slot > 30 then return nil end
  local box = storage.boxes and storage.boxes[current]
  local mon = box and box.mons and box.mons[slot]
  local col, row = (slot - 1) % 6 + 1, math.floor((slot - 1) / 6) + 1
  return join({ Box.mon(mon) or "empty", string.format("row %d, column %d", row, col) })
end

function Box.drawerText(B)
  local slot = B.partyCursor or 1
  local party = (B._session and B._session.party) or {}
  if slot == 7 then
    local label = romHas("gPCText_Cancel") and say(rom("gPCText_Cancel")) or cancelLabel()
    return label and join({ label, position(7, 7) })
  end
  local mon = party[slot]
  local holding = B.holdingSource
  if mon and holding and holding.loc == "party" and holding.slot == slot and B.holdingMon == mon then mon = nil end
  return join({ Box.mon(mon) or "empty", position(slot, 7) })
end

function Box.menuText(B, act)
  local fn = screenLocal(B.draw, "menu_text")
  return fn and say(try(fn, act)) or nil
end

function Box.wallpaper(B)
  local forest = screenLocal(B.draw, "menu_text_forest")
  local countFn = screenLocal(B.draw, "wallpaper_count")
  local Chrome = loaded("src.ui.game3.pc_chrome")
  local names = Chrome and try(Chrome.wallpaperNames) or {}
  local count = countFn and try(countFn, B._session) or #names
  local id = B.wallpaperCursor or 1
  local base = forest and try(forest, B._session)
  if not base then return nil end
  local textId = id > #names and base - 1 or base + id - 1
  local label = say(romAt("sMenuTexts", textId))
  return label and join({ label, position(id, count) })
end

function Box.pickBox(B, storage)
  local index = B._pickBox or 1
  local box = storage.boxes and storage.boxes[index]
  return join({ Box.boxName(storage, index), string.format("%d of 30", boxCount(box)) })
end

local function releaseText(R)
  local P = pokemon()
  local dynamic = { [0] = P and try(P.displayName, R.mon) or nil }
  if R.state == "confirm" then
    return sentences(say(rom("gText_ReleaseThisPokemon")), yesNo(R.yesNoCursor))
  elseif R.state == "released" then
    return say(rom("gText_PkmnWasReleased", { dynamic = dynamic }))
  elseif R.state == "bye" then
    return say(rom("gText_ByeByePkmn", { dynamic = dynamic }))
  end
  return nil
end

function Box.read(B, memo, entering)
  if not B.open then return nil end
  local storage = storageOf(B)
  if not storage then return nil end
  local Release = loaded("src.ui.game3.release_seq")
  local releasing = Release and try(Release.isActive) == true
  local mode = releasing and ("release:" .. tostring(Release.state)) or (B.mode or "browse")
  local fresh, from = modeChange(memo, mode, entering)
  local current = storage.currentBox or 1
  if not fresh and memo.box == current and memo.cursorSlot == B.cursorSlot and memo.partyCursor == B.partyCursor
      and memo.holding == B.holdingMon and memo.actionCursor == B.actionCursor
      and memo.boxMenuCursor == B.boxMenuCursor and memo.wallpaper == B.wallpaperCursor
      and memo.pickBox == B._pickBox and memo.status == B._status
      and (not releasing or memo.release == Release.yesNoCursor) then
    return nil
  end
  local text
  if releasing then
    if Release.state == "confirm" and not fresh and Release.yesNoCursor ~= memo.release then
      text = yesNo(Release.yesNoCursor)
    elseif fresh then
      text = releaseText(Release)
    end
    memo.release = Release.yesNoCursor
  elseif mode == "browse" then
    local boxChanged = memo.box ~= nil and memo.box ~= current
    local holding = B.holdingMon
    if fresh then
      local context = (entering or from == nil) and join({ Box.boxName(storage, current),
        string.format("%d of 30", boxCount(storage.boxes and storage.boxes[current])) }) or nil
      text = sentences(context, holding and ("holding " .. (monName(holding) or "")) or nil, Box.cursorText(B, storage))
    elseif holding ~= memo.holding then
      text = sentences(holding and ("holding " .. (monName(holding) or "")) or nil, Box.cursorText(B, storage))
    elseif boxChanged then
      local name = Box.boxName(storage, current)
      text = sentences(join({ name, string.format("%d of 30", boxCount(storage.boxes and storage.boxes[current])) }),
        B.cursorSlot ~= 0 and Box.cursorText(B, storage) or nil)
    elseif B.cursorSlot ~= memo.cursorSlot then
      text = Box.cursorText(B, storage)
    end
  elseif mode == "party_drawer" then
    if fresh or B.holdingMon ~= memo.holding then
      local party = (B._session and B._session.party) or {}
      text = sentences(fresh and string.format("Party, %d POKéMON", #party) or nil,
        B.holdingMon and ("holding " .. (monName(B.holdingMon) or "")) or nil, Box.drawerText(B))
    elseif B.partyCursor ~= memo.partyCursor then
      text = Box.drawerText(B)
    end
  elseif mode == "action_menu" then
    local acts = type(B._activeActions) == "table" and B._activeActions or {}
    local cursor = B.actionCursor or 1
    local label = Box.menuText(B, acts[cursor])
    if fresh then
      local target = B._actionTarget
      text = sentences(target and monName(target.mon) or nil, label and join({ label, position(cursor, #acts) }))
    elseif cursor ~= memo.actionCursor then
      text = label
    end
  elseif mode == "box_menu" then
    local acts = try(screenLocal(B.draw, "box_actions")) or {}
    local cursor = B.boxMenuCursor or 1
    local label = Box.menuText(B, acts[cursor])
    if fresh then
      text = sentences(Box.boxName(storage, current), label and join({ label, position(cursor, #acts) }))
    elseif cursor ~= memo.boxMenuCursor then
      text = label
    end
  elseif mode == "pick_wallpaper" then
    if fresh then
      text = sentences(say(rom("gText_PickTheWallpaper")), Box.wallpaper(B))
    elseif B.wallpaperCursor ~= memo.wallpaper then
      text = Box.wallpaper(B)
    end
  elseif mode == "pick_box" or mode == "deposit_box_full" then
    if fresh then
      local key = mode == "deposit_box_full" and "gText_BoxIsFull2"
        or (B._pendingDeposit and "gText_DepositInWhichBox" or "gText_JumpToWhichBox")
      text = sentences(say(rom(key)), mode == "pick_box" and Box.pickBox(B, storage) or nil)
    elseif B._pickBox ~= memo.pickBox then
      text = Box.pickBox(B, storage)
    end
  elseif mode == "message" then
    if fresh or B._status ~= memo.status then text = say(B._status) end
  end
  memo.box, memo.cursorSlot, memo.partyCursor, memo.holding = current, B.cursorSlot, B.partyCursor, B.holdingMon
  memo.actionCursor, memo.boxMenuCursor, memo.wallpaper = B.actionCursor, B.boxMenuCursor, B.wallpaperCursor
  memo.pickBox, memo.status = B._pickBox, B._status
  return text
end

Items.boxStorage = {
  matches = Common.matcher("box_storage", "src.ui.game3.box_storage_ui"),
  poll = function(state, memo, entering)
    local text = Box.read(state.mod, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

-- ------------------------------------------------------------------- shop
-- src/ui/game3/shop_menu.lua (FireRed and LeafGreen; Ruby and Sapphire
-- shops are other code and stay quiet here).  Modes root, buy, buy_qty,
-- buy_confirm, buy_msg; sell opens the bag on top.

local Shop = {}
Items.Shop = Shop

local function shopMoney(S)
  local session = S._session
  return math.max(0, math.floor(tonumber(session and session.money) or 0))
end

local function shopPrice(id)
  local info = itemInfo(id)
  return math.max(0, math.floor(tonumber(info and info.price) or 0))
end

function Shop.row(S, i)
  local items = type(S._items) == "table" and S._items or {}
  local id = items[i]
  if id == nil then
    if i == #items + 1 then return cancelLabel() end
    return nil
  end
  return join({ say(itemName(id)), moneyString(shopPrice(id)) })
end

function Shop.description(S, i)
  local items = type(S._items) == "table" and S._items or {}
  local id = items[i]
  if id == nil then return say(rom("gText_QuitShopping")) end
  return say(itemDescription(id))
end

function Shop.quantity(S, first)
  local pending = S._pending or {}
  local unit = tonumber(pending.price) or 0
  local total = moneyString(unit * (S.qty or 1))
  if not first then return join({ tostring(S.qty or 1), total }) end
  local max = math.max(1, math.min(99, math.floor(shopMoney(S) / math.max(1, unit))))
  local inBag = pending.id ~= nil and bagCount(S._session and S._session.bag, pending.id) or nil
  local inBagText = inBag and say(rom("gText_InBagVar1", { stringVars = { tostring(inBag) } })) or nil
  return join({ quantity(S.qty, max), total, inBagText })
end

function Shop.read(S, memo, entering)
  if not S.open or S._rse then return nil end
  local mode = S.mode or "root"
  if S._fading then return nil end
  local fresh, from = modeChange(memo, mode, entering)
  local money = shopMoney(S)
  if not fresh and memo.cursor == S.cursor and memo.status == S._status and memo.qty == S.qty
      and memo.yesNo == S.yesNoCursor and memo.money == money then
    return nil
  end
  local items = type(S._items) == "table" and S._items or {}
  local text
  if mode == "root" then
    local label = say(romAt("sShopMenuActions_BuySellQuit", (S.cursor or 1) - 1))
    local count = type(S.ROOT) == "table" and #S.ROOT or 3
    if fresh then
      text = sentences(say(S._status), label and join({ label, position(S.cursor or 1, count) }))
    elseif S.cursor ~= memo.cursor then
      text = label
    elseif S._status ~= memo.status then
      text = say(S._status)
    end
  elseif mode == "buy" then
    if fresh then
      local row = Shop.row(S, S.cursor or 1)
      text = sentences((from == "root" or entering) and moneyText(money) or nil,
        row and join({ row, position(S.cursor or 1, #items + 1) }), Shop.description(S, S.cursor or 1))
    elseif S.cursor ~= memo.cursor then
      text = sentences(Shop.row(S, S.cursor), Shop.description(S, S.cursor))
    end
  elseif mode == "buy_qty" then
    if fresh then
      text = sentences(say(S._status), Shop.quantity(S, true))
    elseif S.qty ~= memo.qty then
      text = Shop.quantity(S, false)
    end
  elseif mode == "buy_confirm" then
    if fresh then
      text = sentences(say(S._status), yesNo(S.yesNoCursor))
    elseif S.yesNoCursor ~= memo.yesNo then
      text = yesNo(S.yesNoCursor)
    end
  elseif mode == "buy_msg" then
    if fresh or S._status ~= memo.status then text = say(S._status) end
  end
  -- the money window changes in the frame a purchase completes
  if memo.money ~= nil and money ~= memo.money and mode ~= "root" and mode ~= "sell" then
    text = sentences(text, moneyText(money))
  end
  memo.cursor, memo.status, memo.qty, memo.yesNo, memo.money = S.cursor, S._status, S.qty, S.yesNoCursor, money
  return text
end

Items.shop = {
  matches = Common.matcher("shop", "src.ui.game3.shop_menu"),
  poll = function(state, memo, entering)
    local text = Shop.read(state.mod, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

-- -------------------------------------------------------------- money box
-- src/ui/game3/money_box.lua: the money window scripts show (vending
-- machines, paid services) beside their messages.  Passive, so it is an
-- ambient overlay (gen3/Top.lua): said once when it appears and again when
-- the amount changes, queued behind the dialogue.

local function moneyBoxSource(game, proxy)
  local MoneyBox = loaded("src.ui.game3.money_box")
  local token = Top._edge and Top._edge("money_box", MoneyBox ~= nil and MoneyBox.visible == true)
  if not token then return nil end
  return proxy(token, "money_box", { mod = MoneyBox, game = game })
end
Top.addAmbient(moneyBoxSource)

Items.moneyBox = {
  matches = Common.matcher("money_box"),
  poll = function(state, memo)
    local MoneyBox = state.mod
    if not (MoneyBox and MoneyBox.visible) then return nil end
    local amount = MoneyBox._amount
    if memo.amount == amount then return nil end
    memo.amount = amount
    return moneyText(amount), false
  end,
}

-- ------------------------------------------------------------- region map
-- src/ui/game3/region_map.lua: the town map from the bag, the wall maps
-- and the Fly map.  A free cursor over a 22 by 15 picture; agent default
-- until the owner decides (as Gen 1 and 2's town maps): the place under
-- the cursor as the map's own name box shows it (S.text.map and, for a
-- dungeon, S.text.dungeon), "you are here" on the player's cell, and on
-- the Fly map whether the place can be flown to.  The dungeon preview's
-- name and description are read when they appear.

local Region = {}
Items.Region = Region

function Region.place(R, S)
  local text = S.text or {}
  local here = S.player and S.player.exists and R.cursorX == R.playerX and R.cursorY == R.playerY
    and S.selectedRegion == S.playersRegion
  local fly = R.mode == "fly" and text.map ~= nil and try(R.canFlyToCursor) == true
  return join({ say(text.map), say(text.dungeon), fly and "can fly" or nil, here and "you are here" or nil })
end

function Region.read(R, memo, entering)
  if not R.open then return nil end
  local S = try(R.state)
  if type(S) ~= "table" then return nil end
  local ready = try(R.inputReady) == true
  local preview = S.preview and S.preview.text or nil
  local text
  if preview then
    if preview ~= memo.preview then text = sentences(say(preview.name), say(preview.desc)) end
  elseif ready then
    local name = S.text and S.text.map
    if entering or not memo.ready then
      text = sentences(R.mode == "fly" and "Fly" or "Town map", Region.place(R, S))
    elseif R.cursorX ~= memo.x or R.cursorY ~= memo.y or S.selectedRegion ~= memo.region or name ~= memo.name then
      text = Region.place(R, S)
    end
    memo.x, memo.y, memo.region, memo.name = R.cursorX, R.cursorY, S.selectedRegion, name
  end
  memo.ready = ready
  memo.preview = preview
  return text
end

Items.regionMap = {
  matches = Common.matcher("region_map", "src.ui.game3.region_map"),
  poll = function(state, memo, entering)
    local text = Region.read(state.mod, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

Items.ordered = {
  Items.bag, Items.tmCase, Items.berryPouch, Items.party, Items.summary, Items.pokedex,
  Items.pcMenu, Items.itemPc, Items.boxStorage, Items.shop, Items.moneyBox, Items.regionMap,
}

-- Reading helpers the Hoenn presenters share (gen3/HoennItems.lua).
Items.lib = {
  say = say, try = try, pocketRows = pocketRows, readSell = readSell, quantity = quantity,
  speciesName = speciesName, typesText = typesText, typeName = typeName, powerAccuracy = powerAccuracy,
  moneyText = moneyText, moneyString = moneyString, bagCount = bagCount,
  Summary = function() return Items.Summary end,
  SummaryMenu = function() return loaded("src.ui.game3.summary_menu") end,
  moveLine = function(moveId)
    local P = pokemon()
    local def = P and try(P.battleMove, moveId) or {}
    local pp = tonumber(def.pp)
    return join({ typeName(def.type) and ("type " .. typeName(def.type)) or nil, powerAccuracy(def),
      (pp and pp > 0) and ("PP " .. pp) or nil })
  end,
}

return Items
