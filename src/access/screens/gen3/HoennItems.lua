-- Hoenn item, Pokémon and storage presenters (Ruby, Sapphire, Emerald): the
-- bag (one module with a skin per game), the summary (Emerald's skin over
-- FireRed's module, Ruby and Sapphire's own module) and the Pokédex (one
-- module for all three).  Anything the FireRed presenters read correctly here
-- (party, the sell flow) stays with them.
--
-- Bag and Emerald's summary share a module with FireRed, so these presenters
-- must run first and match only a Hoenn game (gen3/init.lua puts them first).
-- Every value comes from what the screen's draw code reads; labels the
-- screens draw as images are said in words and marked as such below.

local Common = require("src.access.screens.gen3.Common")
local H = require("src.access.screens.gen3.HoennCommon")
local Items3 = require("src.access.screens.gen3.Items")

local Items = {}

local say, rom, join, sentences, try, position = H.say, H.rom, H.join, H.sentences, H.try, Common.position
local lib = Items3.lib

local function hoennMatcher(kind, path)
  local plain = Common.matcher(kind, path)
  return function(state) return plain(state) and H.isHoenn() end
end

local function itemsData() return H.loaded("src.core.game3.items_data") end
local function pokemon() return H.loaded("src.core.game3.pokemon") end

-- -------------------------------------------------------------------- bag
-- src/ui/game3/bag_menu.lua driven by rse/bag_menu.lua (Emerald) or
-- rs/bag_menu.lua (Ruby, Sapphire).  Their pockets and action grids differ
-- from FireRed's: TMs and berries are pockets, each row shows a number and
-- the move or berry, the action grid has its own labels.

local function bagSkin()
  local Screens = H.loaded("src.ui.game3.screens")
  return Screens and try(Screens.skin, "bag") or nil
end

local function actionKey(B, action, row)
  local Skin = bagSkin()
  if Skin and Skin.ACTION_TEXT then
    if action == "SET" and row and B._session then
      local D = itemsData()
      if D and try(D.toNumericId, B._session.registeredItem) == try(D.toNumericId, row.id) then
        return Skin.ACTION_TEXT.DESELECT
      end
    end
    return Skin.ACTION_TEXT[action]
  end
  local Data = H.loaded("src.ui.game3.rs.bag_menu_data")
  if Data then
    local Player = H.loaded("src.core.game3.player")
    local D = itemsData()
    if action == "USE" and row and D then
      local kind = try(D.fieldUseKind, row.id)
      if kind == "bike" and Player and Player.biking then return Data.ACTION_TEXT.WALK end
    end
    return Data.ACTION_TEXT[action]
  end
  return nil
end

-- "TM06, TOXIC", "berry 1, CHERI BERRY": the row shows a number and the move.
local function bagName(pocket, row)
  local D, P = itemsData(), pokemon()
  local name = D and try(D.displayName, row.id)
  if pocket == "TM_CASE" and P then
    local move = try(P.moveFromTmItem, row.id)
    local moveName = move and try(P.moveName, move)
    if moveName then return join({ say(name), say(moveName) }) end
  end
  return say(name)
end

local function bagRow(B, rows, i, pocket)
  local row = rows[i]
  if not row then
    if i == #rows + 1 and B._location ~= "blender" then return H.first({ "gText_CloseBag", "gOtherText_CloseBag" }) end
    return nil
  end
  local parts = { bagName(pocket, row) }
  local D = itemsData()
  if pocket == "KEY_ITEMS" then
    local session = B._session
    if session and D and try(D.toNumericId, session.registeredItem) == try(D.toNumericId, row.id) then
      parts[#parts + 1] = "registered"
    end
  elseif not (pocket == "TM_CASE" and D and try(D.isHm, row.id)) then
    parts[#parts + 1] = "quantity " .. tostring(row.qty)
  end
  return join(parts)
end

-- The left pane in the TM pocket; otherwise the description.
local function bagDescription(B, rows, i, pocket)
  local row = rows[i]
  local D, P = itemsData(), pokemon()
  if not row then
    local Skin = bagSkin()
    local Data = H.loaded("src.ui.game3.rs.bag_menu_data")
    local where = B._battle and "battle" or B._location
    if Skin and Skin.LOCATION then
      local place = H.romAt("gBagMenu_ReturnToStrings", Skin.LOCATION[where or ""] or 0)
      return say(rom("gText_ReturnToVar1", { stringVars = { place } }))
    end
    if Data then
      local key = Data.RETURN_TEXT[where or "field"] or Data.RETURN_TEXT.field
      return H.join({ say(rom("gOtherText_ReturnTo")), say(rom(key)) }, " ")
    end
    return nil
  end
  local description = D and say(try(D.description, row.id))
  if pocket == "TM_CASE" and P then
    local move = try(P.moveFromTmItem, row.id)
    local def = move and try(P.battleMove, move)
    if def then return sentences({ lib.moveLine(move), description }) end
  end
  return description
end

local POCKET_WORDS = { ITEMS = "ITEMS", POKE_BALLS = "POKé BALLS", TM_CASE = "TMs & HMs",
  BERRY_POUCH = "BERRIES", KEY_ITEMS = "KEY ITEMS" }

local function bagTitle(B, pocket)
  if B._location == "itempc" then
    local key = H.first({ "gText_DepositItem", "gPCText_DepositItem" })
    if key then return key end
  end
  local D = itemsData()
  local label = D and D.POCKET_LABEL and say(D.POCKET_LABEL[pocket])
  -- Ruby and Sapphire draw the pocket's name as an image
  label = label or POCKET_WORDS[pocket]
  return label and (label .. " pocket") or nil
end

local function bagQuestion(key, keys, vars)
  for _, k in ipairs(keys) do
    if H.romHas(k) then return say(rom(k, { stringVars = vars })) end
  end
  return key
end

local function bagRead(B, memo, entering)
  if not B.open or B._exit or B._switch then return nil end
  local mode = (B.mode == "sell" and B._sell) and "sell" or (B.mode or "list")
  local from = memo.mode
  local fresh = entering or mode ~= from
  memo.mode = mode
  if mode == "sell" then return lib.readSell(B._sell, memo, fresh) end
  local pocket = B.currentPocket and try(B.currentPocket) or nil
  if not pocket then return nil end
  if not fresh and memo.pocketIdx == B.pocketIdx and memo.cursor == B.cursor
      and memo.actionCursor == B.actionCursor and memo.qty == B.tossQty and memo.yesNo == B.yesNoCursor
      and memo.message == B.messageText and memo.msgPage == B._msgPage then
    return nil
  end
  local rows = lib.pocketRows(B._bag, pocket)
  local sel = rows[B.cursor]
  local D = itemsData()
  local name = sel and D and try(D.displayName, sel.id)
  local count = #rows + (B._location == "blender" and 0 or 1)
  local text
  if mode == "list" then
    local pocketChanged = memo.pocketIdx ~= nil and memo.pocketIdx ~= B.pocketIdx
    if fresh or pocketChanged then
      local context = (entering or pocketChanged or from == nil) and bagTitle(B, pocket) or nil
      local row = bagRow(B, rows, B.cursor, pocket)
      text = sentences({ context, row and join({ row, position(B.cursor, count) }),
        bagDescription(B, rows, B.cursor, pocket) })
    elseif B.cursor ~= memo.cursor then
      text = sentences({ bagRow(B, rows, B.cursor, pocket), bagDescription(B, rows, B.cursor, pocket) })
    end
  elseif mode == "move" then
    local row = bagRow(B, rows, B.cursor, pocket)
    if fresh then
      local moving = rows[B.moveFrom]
      text = sentences({ moving and bagQuestion(nil, { "gText_MoveVar1Where", "gOtherText_SwitchWhichItem" },
        { D and try(D.displayName, moving.id) }), row and join({ row, position(B.cursor, count) }) })
    elseif B.cursor ~= memo.cursor then
      text = row
    end
  elseif mode == "action" then
    local acts = type(B.ACTIONS) == "table" and B.ACTIONS or {}
    local cursor = B.actionCursor or 1
    local key = actionKey(B, acts[cursor], sel)
    local label = say(key and rom(key))
    if fresh then
      text = sentences({ bagQuestion(nil, { "gText_Var1IsSelected", "gOtherText_WhatWillYouDo2" }, { name }),
        label and join({ label, position(cursor, #acts) }) })
    elseif cursor ~= memo.actionCursor then
      text = label
    end
  elseif mode == "toss" or mode == "deposit" then
    if fresh then
      local keys = mode == "toss" and { "gText_TossHowManyVar1s", "gOtherText_HowManyToToss" }
        or { "gText_DepositHowManyVar1", "gOtherText_HowManyToDeposit" }
      text = sentences({ bagQuestion(nil, keys, { name }), lib.quantity(B.tossQty, sel and sel.qty or 1) })
    elseif B.tossQty ~= memo.qty then
      text = tostring(B.tossQty)
    end
  elseif mode == "toss_confirm" then
    if fresh then
      text = sentences({ bagQuestion(nil, { "gText_ConfirmTossItems", "gOtherText_OkayToThrowAwayPrompt" },
        { name, tostring(B.tossQty) }), H.yesNo(B.yesNoCursor) })
    elseif B.yesNoCursor ~= memo.yesNo then
      text = H.yesNo(B.yesNoCursor)
    end
  elseif mode == "toss_done" then
    if fresh then
      text = bagQuestion(nil, { "gText_ThrewAwayVar2Var1s", "gOtherText_ThrewAwayItem" }, { name, tostring(B.tossQty) })
    end
  elseif mode == "deposit_done" then
    if fresh then text = say(B._depositText) end
  elseif mode == "message" then
    if fresh or B.messageText ~= memo.message or B._msgPage ~= memo.msgPage then text = say(B.messageText) end
  end
  memo.pocketIdx, memo.cursor, memo.actionCursor = B.pocketIdx, B.cursor, B.actionCursor
  memo.qty, memo.yesNo = B.tossQty, B.yesNoCursor
  memo.message, memo.msgPage = B.messageText, B._msgPage
  return text
end

Items.bag = {
  matches = hoennMatcher("bag", "src.ui.game3.bag_menu"),
  poll = function(state, memo, entering)
    local text = bagRead(state.mod, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

-- --------------------------------------------------------------- summary
-- Emerald: FireRed's module with rse/summary_menu.lua as its skin, four
-- pages (RseSummary.page: 0 info, 1 skills, 2 battle moves, 3 contest
-- moves); the moves pages have a detail mode.  Ruby and Sapphire:
-- rs/summary_menu.lua, its own `_page` 0-3, `_state`, `_selected`, `_switch`.

local NATURE_KEY = "gNatureNamePointers"

local function textOf(segments)
  local out = {}
  for _, seg in ipairs(segments or {}) do
    if seg.s then out[#out + 1] = seg.s
    elseif seg.nl then out[#out + 1] = " " end
  end
  return table.concat(out)
end

-- Emerald's memo line, built with the screen's own text key and dynamic
-- values (RseSummary drawInfo).
local function emeraldMemo(S, mon)
  local PalText = H.loaded("src.ui.game3.rse.pal_text")
  local RomText = H.loaded("src.core.game3.rom_text")
  local D = H.loaded("src.core.game3.summary_data")
  if not (PalText and RomText and D) then return nil end
  local session = S._playerState or {}
  local natureId = try(D.nature, mon)
  local Mapsec = H.loaded("src.ui.game3.rse.mapsec") or require("src.ui.game3.rse.mapsec")
  local sec = tonumber(mon.metLocation)
  local secName = sec and H.nonEmpty(try(Mapsec.name, sec)) or nil
  local metLevel = tonumber(mon.metLevel) or 0
  local otName = tostring(mon.otName or mon.ot or "")
  local own = otName == tostring(session.name or session.playerName or "")
    and ((tonumber(mon.otId) or 0) % 65536) == ((tonumber(session.trainerId) or 0) % 65536)
  local key
  if own then
    if metLevel == 0 then key = secName and "gText_XNatureHatchedAtYZ" or "gText_XNatureHatchedSomewhereAt"
    else key = secName and "gText_XNatureMetAtYZ" or "gText_XNatureMetSomewhereAt" end
  else
    key = secName and "gText_XNatureProbablyMetAt" or "gText_XNatureObtainedInTrade"
  end
  local segments = try(PalText.segments, key, { dynamic = {
    [2] = natureId and H.romAt(NATURE_KEY, natureId) or nil,
    [3] = tostring(metLevel == 0 and 5 or metLevel), [4] = secName or "",
  } })
  return say(textOf(segments))
end

local function rubyMemo(S, mon)
  local Policy = H.loaded("src.ui.game3.rs.summary_policy")
  if not Policy then return nil end
  local owner = (type(S._opts) == "table" and S._opts.owner) or S._playerState
  local place = try(S.locationName, tonumber(mon.metLocation) or 0)
  local runs = try(Policy.memo, mon, owner, place)
  if type(runs) ~= "table" then return nil end
  local out = {}
  for _, run in ipairs(runs) do out[#out + 1] = run.text end
  return say(table.concat(out))
end

local function abilityText(mon)
  local P = pokemon()
  local D = H.loaded("src.core.game3.summary_data")
  if not (P and D) then return nil end
  local species = try(P.speciesOf, mon)
  local abilities = species and try(P.abilities, species)
  local flag = tonumber(mon.abilityNum or mon.altAbility)
  local id = (flag and type(abilities) == "table" and abilities[flag % 2 + 1])
    or tonumber(mon.ability or mon.abilityId) or (species and try(P.abilityId, species, mon.personality))
  if not id or id == 0 then return nil end
  local name = try(P.abilityName, id)
  if not name or name == "" then return nil end
  return join({ "ability " .. tostring(say(name)), say(try(D.abilityDescription, id, name)) })
end

local function eggSpeech(S, mon, ruby)
  local D = H.loaded("src.core.game3.summary_data")
  if ruby then
    local Policy = H.loaded("src.ui.game3.rs.summary_policy")
    local key = Policy and try(Policy.eggHatchKey, mon)
    return sentences({ lib.say("EGG"), key and say(rom(key)) })
  end
  local f = tonumber(mon.friendship or mon.eggCycles) or 40
  local key = mon.isBadEgg and "gText_EggWillTakeALongTime" or f <= 5 and "gText_EggAboutToHatch"
    or f <= 10 and "gText_EggWillHatchSoon" or f <= 40 and "gText_EggWillTakeSomeTime" or "gText_EggWillTakeALongTime"
  return sentences({ D and "EGG", say(rom(key)) })
end

local function infoPage(S, mon, memoText)
  local P = pokemon()
  local species = P and try(P.speciesOf, mon)
  local types = species and P and try(P.types, species) or {}
  local dex = try(lib.SummaryMenu().dexNoText, mon, S._playerState)
  local otId = tonumber(mon.otId)
  local otName = mon.otName or mon.ot or mon.originalTrainer
  return sentences({ join({ dex and ("number " .. tostring(say(dex))) or nil, lib.speciesName(mon),
      lib.typesText(types[1], types[2]), otName and ("OT " .. tostring(say(otName))) or nil,
      otId and ("ID " .. string.format("%05d", otId % 65536)) or nil }),
    abilityText(mon), memoText })
end

local function skillsPage(S, mon)
  local D = H.loaded("src.core.game3.summary_data")
  local P = pokemon()
  local stats = type(mon.stats) == "table" and mon.stats or {}
  local function stat(label, ...)
    for _, key in ipairs({ ... }) do
      local value = mon[key] or stats[key]
      if value ~= nil then return label .. " " .. tostring(value) end
    end
    return nil
  end
  local hp, maxHp = tonumber(mon.hp) or 0, tonumber(mon.maxHp or stats.hp)
  local itemId = tonumber(mon.item or mon.heldItem) or 0
  local Items_ = itemsData()
  local item = itemId == 0 and H.first({ "gText_None", "gOtherText_None" })
    or (Items_ and say(try(Items_.displayName, itemId)))
  local Ribbons = H.loaded("src.core.game3.rse.ribbons")
    or select(2, pcall(require, "src.core.game3.rse.ribbons"))
  local ribbons = type(Ribbons) == "table" and try(Ribbons.count, mon) or nil
  local species = P and try(P.speciesOf, mon)
  local growth = P and species and try(P.growthRate, species)
  local prog = D and (try(D.expProgress, mon, growth) or try(D.expProgress, mon)) or {}
  return sentences({
    join({ item and ("item " .. item) or nil, ribbons and (ribbons == 0 and "ribbons none" or ("ribbons " .. ribbons)) or nil }),
    join({ maxHp and string.format("HP %d of %d", hp, maxHp) or nil,
      stat("attack", "attack", "atk"), stat("defense", "defense", "def"),
      stat("special attack", "spAtk", "spa"), stat("special defense", "spDef", "spd"),
      stat("speed", "speed", "spe") }),
    join({ prog.totalExp and join({ H.first({ "gText_ExpPoints", "gOtherText_ExpPoints" }), tostring(prog.totalExp) }, " ") or nil,
      prog.expNeeded and join({ H.first({ "gText_NextLv", "gOtherText_NextLv" }),
        tostring((prog.level or 0) < 100 and prog.expNeeded or 0) }, " ") or nil }),
  })
end

-- Contest move data as the screens read it (Kit.loadLua is cached upstream).
local function contestInfo(id)
  local Kit = H.loaded("src.ui.game3.rse.scene_kit")
  local pack = Kit and try(Kit.loadLua, "data/generated/gba/pokemon/contest_moves.lua")
  local move = type(pack) == "table" and pack.moves and pack.moves[id]
  if not move then return nil end
  return move, pack.effects and pack.effects[move.effect]
end

-- The category icons are images; COOL, BEAUTY, CUTE, SMART, TOUGH are the
-- words the contest rank screens print for them.
local CONTEST_CATEGORY = { [0] = "COOL", "BEAUTY", "CUTE", "SMART", "TOUGH" }

local function moveId(mon, slot)
  local entry = type(mon.moves) == "table" and mon.moves[slot] or nil
  local id = type(entry) == "table" and (entry.id or entry.move or entry.moveId) or entry
  if tonumber(id) then id = tonumber(id) end
  if id == 0 or id == "" then return nil end
  return id
end

local function moveNumeric(S, id)
  if type(id) == "number" then return id end
  local P = pokemon()
  return P and id and try(P.battleMoveId, id) or nil
end

-- One row: name, type or contest category, PP.
local function moveRow(S, mon, slot, contest, learnId)
  local P = pokemon()
  local id = slot == 5 and learnId or moveId(mon, slot)
  id = moveNumeric(S, id)
  if not (id and P) then return nil end
  local def = try(P.battleMove, id) or {}
  local name = say(try(P.moveName, id))
  if not name then return nil end
  local kind
  if contest then
    local move = contestInfo(id)
    kind = move and CONTEST_CATEGORY[move.category] or nil
  else
    kind = lib.typeName(def.type)
  end
  local entry = type(mon.moves) == "table" and mon.moves[slot] or nil
  local pp = type(entry) == "table" and entry.pp or (type(mon.pp) == "table" and mon.pp[slot]) or nil
  local max = (type(mon.maxPp) == "table" and tonumber(mon.maxPp[slot])) or tonumber(def.pp)
  if slot == 5 then pp, max = def.pp, def.pp end
  return join({ name, kind, max and max > 0 and string.format("PP %d of %d", tonumber(pp) or max, max) or nil }), id, def
end

local function movesPage(S, mon, contest)
  local rows = {}
  for slot = 1, 4 do rows[#rows + 1] = moveRow(S, mon, slot, contest) end
  if #rows == 0 then return nil end
  return "moves: " .. table.concat(rows, "; ")
end

-- While a move is being learned the screen has five rows, the fifth the new
-- move (choosing it gives up learning), so every row says its position and the
-- fifth says it is the new one (our words: the screen shows it below a line).
local function moveDetail(S, mon, slot, contest, learnId, withPosition)
  local row, id, def = moveRow(S, mon, slot, contest, learnId)
  local where = (withPosition or learnId ~= nil) and position(slot, 5) or nil
  if not row then
    return join({ H.first({ "gText_Cancel2", "gOtherText_CancelNoTerminator" }), where })
  end
  if learnId ~= nil and slot == 5 then row = join({ "new move", row }) end
  row = join({ row, where })
  local D = H.loaded("src.core.game3.summary_data")
  if contest then
    local _, effect = contestInfo(id)
    if not effect then return row end
    local appeal = effect.appeal ~= 0xFF and math.floor(effect.appeal / 10) or 0
    local jam = effect.jam ~= 0xFF and math.floor(effect.jam / 10) or 0
    return sentences({ row, string.format("appeal %d, jam %d", appeal, jam),
      D and say(try(D.contestEffectDescription, effect)) })
  end
  local P = pokemon()
  return sentences({ row, lib.powerAccuracy(def), D and say(try(D.moveDescription, id, try(P.moveName, id))) })
end

local PAGE_TITLES = {
  emerald = { [0] = "gText_PkmnInfo", "gText_PkmnSkills", "gText_BattleMoves", "gText_ContestMoves" },
}
-- Ruby and Sapphire draw the page titles as images, so these are our words
-- for the same four pages.
local RUBY_TITLES = { [0] = "POKéMON INFO", "POKéMON SKILLS", "BATTLE MOVES", "CONTEST MOVES" }

-- Reads through an adapter: { mon, egg, page, detail, cursor (1-5), swap,
-- learnId, first, last, memoText, notice }.
local function summaryRead(S, view, memo, entering)
  local mon = view.mon
  if type(mon) ~= "table" then return nil end
  local page = view.page
  local title = view.title(page)
  local pageText
  if view.egg then pageText = eggSpeech(S, mon, view.ruby)
  elseif page == 0 then pageText = infoPage(S, mon, view.memoText(S, mon))
  elseif page == 1 then pageText = skillsPage(S, mon)
  else pageText = movesPage(S, mon, page == 3) end
  local function headed()
    return join({ title, not view.egg and string.format("page %d of %d", page - view.first + 1, view.last - view.first + 1) or nil })
  end
  local newMon = memo.mon ~= mon or memo.cursorMon ~= view.monIndex
  local text
  if entering or newMon then
    local detailText = view.detail and moveDetail(S, mon, view.cursor, page == 3, view.learnId) or nil
    text = sentences({ lib.Summary().header(S, mon), headed(), detailText or pageText })
  elseif page ~= memo.page then
    text = sentences({ headed(), view.detail and moveDetail(S, mon, view.cursor, page == 3, view.learnId) or pageText })
  elseif view.detail then
    if view.notice and not memo.notice then
      text = H.first({ "gText_CantForgetHMs", "gOtherText_CantForgetHMs" })
    elseif view.swap ~= memo.swap then
      if view.swap then
        local row = moveRow(S, mon, view.swap, page == 3)
        text = row and ("moving " .. row) or nil
      else
        text = moveDetail(S, mon, view.cursor, page == 3, view.learnId)
      end
    elseif view.cursor ~= memo.moveCursor or not memo.detail then
      text = moveDetail(S, mon, view.cursor, page == 3, view.learnId, not memo.detail)
    end
  elseif memo.detail then
    text = pageText
  end
  memo.mon, memo.cursorMon, memo.page = mon, view.monIndex, page
  memo.detail, memo.swap, memo.moveCursor, memo.notice = view.detail, view.swap, view.cursor, view.notice
  return text
end

Items.summaryEmerald = {
  matches = hoennMatcher("summary", "src.ui.game3.summary_menu"),
  poll = function(state, memo, entering)
    local S = state.mod
    local Skin = H.loaded("src.ui.game3.rse.summary_menu")
    if not (S.open and Skin) or S._nativeDelegate then return nil end
    if S._slide and S._slide.active then return nil end
    local page, egg = Skin.page(S)
    local selecting = S._mode == "select_move"
    local learn = selecting and not S._forgetMove and S._moveToLearn or nil
    local first = (selecting or S._context == "moves") and 2 or 0
    local text = summaryRead(S, {
      mon = lib.Summary().mon(S), monIndex = S._cursor, egg = egg, page = page, ruby = false,
      detail = Skin.detail(S), cursor = S._moveCursor or 1, swap = S._swapSlot, learnId = learn,
      first = first, last = 3, memoText = emeraldMemo, notice = S._hmNotice,
      -- the cart's own string spells CONTEST with a zero
      title = function(p)
        local title = say(rom(PAGE_TITLES.emerald[p]))
        return title and (title:gsub("C0NTEST", "CONTEST")) or nil
      end,
    }, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

Items.summaryRuby = {
  matches = Common.matcher("summary", "src.ui.game3.rs.summary_menu"),
  poll = function(state, memo, entering)
    local S = state.mod
    if not S.open or S._fade == "in" or S._pageTask or S._reload then return nil end
    local mon = S._loaded or (S._party and S._party[S._cursor])
    local P = pokemon()
    local text = summaryRead(S, {
      mon = mon, monIndex = S._cursor, egg = P and try(P.isEgg, mon) == true, page = S._page, ruby = true,
      detail = S._state ~= "normal" and (S._page or 0) >= 2,
      cursor = (S._state == "swap" and S._switch or S._selected or 0) + 1,
      swap = S._state == "swap" and (S._selected + 1) or nil,
      learnId = (S._moveToLearn or 0) ~= 0 and S._moveToLearn or nil,
      first = S._firstPage or 0, last = S._lastPage or 3, memoText = rubyMemo, notice = S._state == "notice",
      title = function(p) return RUBY_TITLES[p] end,
    }, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

-- --------------------------------------------------------------- Pokédex
-- src/ui/game3/rse/pokedex.lua (layer "rse_pokedex"; rs/pokedex.lua returns
-- the same module): `Pokedex.active()` holds the view, `fn` its task, `page`
-- its screen.  Everything is read from the view; no list or area is rebuilt.
-- These labels are images on the screen, so they are said in words:
-- the info bar (AREA, CRY, SIZE, CANCEL; Ruby and Sapphire add PAGE first)
-- and the list's START menu.

local function dexModule() return H.loaded("src.ui.game3.rse.pokedex") end

local function dexNative()
  local Gfx = H.loaded("src.ui.game3.rse.pokedex_gfx")
  local man = Gfx and try(Gfx.manifest)
  return type(man) == "table" and man.assetLayout == "rs"
end

local function dexRow(view, i)
  local Dex, P = dexModule(), pokemon()
  local list = view.list
  local it = type(list) == "table" and type(list.items) == "table" and list.items[i]
  if not (it and Dex and P) then return nil end
  local num = it.dexNum
  if view.dexMode == 0 then num = try(Dex.hoennNumber, num) or num end
  -- an unseen row draws dashes, which a screen reader skips
  local name = it.seen and say(try(P.name, try(Dex.speciesOf, it.dexNum))) or "not seen"
  return join({ string.format("number %03d", tonumber(num) or 0), name,
    it.owned and it.seen and "owned" or (it.seen and "seen" or nil) })
end

local function dexMenuLabels(view)
  if view.page == 3 then return { "select", "list top", "list bottom", "return to POKéDEX", "close POKéDEX" } end
  return { "select", "list top", "list bottom", "close POKéDEX" }
end

-- `1'04"` as the screen shows it, in words; labels and values on one line
-- (same y) are read together.
local function dexInfoText(list)
  if type(list) ~= "table" then return nil end
  local lines, order = {}, {}
  for _, row in ipairs(list) do
    local text = say(row.text)
    if text then
      text = text:gsub("(%d+)'(%d+)\"", function(feet, inches)
        return string.format("%d feet %d inches", tonumber(feet), tonumber(inches))
      end)
      local y = row.y or #order
      if not lines[y] then
        lines[y] = {}
        order[#order + 1] = y
      end
      table.insert(lines[y], text)
    end
  end
  table.sort(order)
  local parts = {}
  for _, y in ipairs(order) do parts[#parts + 1] = table.concat(lines[y], " ") end
  return sentences(parts)
end

local function dexBarLabel(index)
  local labels = dexNative() and { [0] = "PAGE", "AREA", "CRY", "SIZE", "CANCEL" }
    or { [0] = "AREA", "CRY", "SIZE", "CANCEL" }
  return labels[index]
end

local function dexAreaText(view)
  local area = view.area
  if type(area) ~= "table" or type(area.found) ~= "table" then return nil end
  local Mapsec = H.loaded("src.ui.game3.rse.mapsec")
  if not Mapsec then return nil end
  local seen, names = {}, {}
  local function add(sec)
    local name = say(try(Mapsec.name, sec))
    if name and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  for _, row in ipairs(area.found.overworld or {}) do add(row.sec) end
  for _, sec in ipairs(area.found.special or {}) do add(sec) end
  if #names == 0 then return "AREA UNKNOWN" end
  return table.concat(names, ", ")
end

local function dexSearchRow(view, q, which)
  local Dex = dexModule()
  local texts = Dex and try(Dex.searchOptionTexts, which)
  if type(texts) ~= "table" then return nil end
  local c = (q.cursor[which] or 0) + (q.scroll[which] or 0)
  local row = texts[c + 1]
  return row and say(row.title) or nil, #texts, c + 1
end

-- The rows of the search page, by their SEARCH ids: the titles are images.
local SEARCH_LABEL = { [0] = "NAME", "COLOR", "TYPE", "TYPE, second", "ORDER", "MODE", "OK" }
local TOPBAR_LABEL = { [0] = "SEARCH", "SHIFT", "CANCEL" }

local function dexSearch(view, memo)
  local q = view.searchState
  if type(q) ~= "table" then return nil end
  local parts = {}
  if memo.q ~= q then
    memo.q, memo.topBar, memo.phase, memo.item, memo.sel, memo.message = q, nil, nil, nil, nil, nil
    parts[#parts + 1] = "POKéDEX search"
  end
  local phase = q.phase
  if phase == "topbar" then
    if memo.topBar ~= q.topBar or memo.phase ~= phase then
      memo.topBar = q.topBar
      parts[#parts + 1] = join({ TOPBAR_LABEL[q.topBar], position((q.topBar or 0) + 1, 3) })
    end
  elseif phase == "menu" then
    if memo.item ~= q.menuItem or memo.phase ~= phase then
      memo.item = q.menuItem
      local value = q.menuItem ~= 6 and dexSearchRow(view, q, q.menuItem) or nil
      parts[#parts + 1] = join({ SEARCH_LABEL[q.menuItem], value })
    end
  elseif phase == "param" then
    local c = (q.cursor[q.menuItem] or 0) + (q.scroll[q.menuItem] or 0)
    if memo.sel ~= c or memo.phase ~= phase then
      memo.sel = c
      local title, count, at = dexSearchRow(view, q, q.menuItem)
      parts[#parts + 1] = title and join({ title, position(at, count) }) or nil
    end
  end
  memo.phase = phase
  if q.message ~= memo.message then
    memo.message = q.message
    parts[#parts + 1] = say(q.message)
  end
  return sentences(parts)
end

local DEX_LIST_TASKS = { mainInput = true, waitScroll = true }

local function dexRead(view, memo, entering)
  local Dex = dexModule()
  if not (Dex and type(Dex.PAGE) == "table") then return nil end
  local PAGE = Dex.PAGE
  local page, fn = view.page, view.fn
  if not view.shown then return nil end
  if page ~= memo.page then
    memo.page, memo.selected, memo.screen, memo.menuOpen, memo.saidArea = page, nil, nil, nil, nil
    memo.info, memo.descPage = nil, nil
    memo.fresh = true
  end
  if entering then memo.fresh = true end
  if page == PAGE.MAIN or page == PAGE.SEARCH_RESULTS then
    if view.menuIsOpen then
      local labels = dexMenuLabels(view)
      if not memo.menuOpen or memo.menuCursor ~= view.menuCursorPos then
        local first = not memo.menuOpen
        memo.menuOpen, memo.menuCursor = true, view.menuCursorPos
        local label = labels[(view.menuCursorPos or 0) + 1]
        if first then return join({ label, position((view.menuCursorPos or 0) + 1, #labels) }) end
        return label
      end
      return nil
    end
    if not DEX_LIST_TASKS[fn] then return nil end
    local selected = view.selected or 0
    if memo.selected == selected and not memo.fresh and not memo.menuOpen then return nil end
    local row = dexRow(view, selected)
    if not row then return nil end
    local text = row
    if memo.fresh then
      local seenLabel = H.first({ "gText_Seen" }) or "seen"
      local head = page == PAGE.MAIN
        and string.format("POKéDEX. %s %d, owned %d", seenLabel, view.seenCount or 0, view.ownCount or 0)
        or "Search results"
      text = sentences({ head, join({ row, position(selected + 1, view.list.count or 0) }) })
    end
    memo.selected, memo.fresh, memo.menuOpen = selected, nil, nil
    return text
  end
  if page == PAGE.INFO then
    local info = view.info
    if type(info) ~= "table" or type(info.text) ~= "table" then return nil end
    local parts = {}
    if info.text ~= memo.info or memo.fresh then
      memo.info = info.text
      parts[#parts + 1] = dexInfoText(info.text)
      if memo.fresh then memo.screen = nil end
    end
    if memo.screen ~= view.selectedScreen then
      memo.screen = view.selectedScreen
      parts[#parts + 1] = dexBarLabel(view.selectedScreen)
    end
    memo.fresh = nil
    return sentences(parts)
  end
  if page == PAGE.AREA then
    if memo.saidArea or not view.area or fn ~= "areaInput" then return nil end
    memo.saidArea, memo.fresh = true, nil
    return sentences({ "AREA", dexAreaText(view) })
  end
  if page == PAGE.CRY then
    if not memo.fresh then return nil end
    memo.fresh = nil
    return sentences({ "CRY", "Press A to play the cry" })
  end
  if page == PAGE.SIZE then
    if not memo.fresh or type(view.sizeText) ~= "table" then return nil end
    memo.fresh = nil
    return sentences({ "SIZE", say(view.sizeText.text) })
  end
  if page == PAGE.SEARCH then return dexSearch(view, memo) end
  if page == PAGE.CAUGHT then
    local c = view.caught
    if type(c) ~= "table" or type(c.text) ~= "table" or c.text == memo.info then return nil end
    memo.info = c.text
    return dexInfoText(c.text)
  end
  return nil
end

Items.pokedex = {
  matches = Common.matcher("rse_pokedex"),
  poll = function(state, memo, entering)
    local Dex = dexModule()
    local view = Dex and try(Dex.active)
    if type(view) ~= "table" then return nil end
    local text = dexRead(view, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

-- ------------------------------------------------------------------ shop
-- src/ui/game3/shop_menu.lua with rse/shop_menu.lua (Emerald) or rs/shop_menu
-- (Ruby, Sapphire; `_nativeShopPolicy`): `state` root, list, msg, qty,
-- confirm, sell (the bag on top), `_status`, `cursor`, `scroll`+`row`, `qty`,
-- `_totalCost`, `yesCursor`, decoration shops by `_martType`.

local function shopPlain(S, key, ctx)
  local policy = S._nativeShopPolicy
  if policy and policy.plain then
    local text = try(policy.plain, key, ctx)
    if text then return say(text) end
  end
  return say(rom(key, ctx))
end

local function shopDecor(S) return S._martType ~= nil and S._martType ~= "NORMAL" end

local function shopRows(S)
  if shopDecor(S) then return { "gText_ShopBuy", "gText_ShopQuit" } end
  return { "gText_ShopBuy", "gText_ShopSell", "gText_ShopQuit" }
end

local function shopInfo(id)
  local Inventory = H.loaded("src.core.game3.rse.decoration_inventory")
  return Inventory and try(Inventory.info, id) or nil
end

local function shopPrice(S, id)
  local Base = H.loaded("src.ui.game3.rse.shop_menu")
  local unit = Base and Items3.screenLocal(Base.handleInput, "unit_price", 3)
  return unit and try(unit, S, id) or nil
end

local function shopRow(S, id)
  if id == nil then return shopPlain(S, "gText_Cancel2") end
  local name
  if shopDecor(S) then
    local info = shopInfo(id)
    name = info and say(info.name)
  else
    local D = itemsData()
    name = D and say(try(D.displayName, id))
  end
  local price = shopPrice(S, id)
  return join({ name, price and lib.moneyString(price) or nil })
end

local function shopDescription(S, id)
  if id == nil then return shopPlain(S, "gText_QuitShopping") end
  if shopDecor(S) then
    local info = shopInfo(id)
    return info and say(info.description) or nil
  end
  local D = itemsData()
  return D and say(try(D.description, id)) or nil
end

local function shopRead(S, memo, entering)
  if not S.open or S._fading then return nil end
  local st = S.state
  local fresh = entering or st ~= memo.state
  local from = memo.state
  memo.state = st
  if st == "sell" then return nil end
  local items = type(S._items) == "table" and S._items or {}
  local at = (S.scroll or 0) + (S.row or 0) + 1
  local money = tonumber(S._session and S._session.money)
  local text
  if st == "root" then
    local rows = shopRows(S)
    local label = shopPlain(S, rows[S.cursor or 1])
    if fresh or S._status ~= memo.status then
      text = sentences({ say(S._status), label and join({ label, position(S.cursor or 1, #rows) }) })
    elseif S.cursor ~= memo.cursor then
      text = label
    end
  elseif st == "list" then
    if fresh or at ~= memo.at then
      local id = items[at]
      local row = shopRow(S, id)
      if fresh then
        text = sentences({ (from == "root" or entering) and lib.moneyText(money) or nil,
          row and join({ row, position(at, #items + 1) }), shopDescription(S, id) })
      else
        text = sentences({ row, shopDescription(S, id) })
      end
    end
  elseif st == "qty" then
    if fresh then
      local id = S._itemId
      local inBag = id and lib.bagCount(S._session and S._session.bag, id)
      text = sentences({ say(S._status), join({ lib.quantity(S.qty, S._maxQty or 1),
        S._totalCost and lib.moneyString(S._totalCost) or nil,
        inBag and shopPlain(S, "gText_InBagVar1", { stringVars = { tostring(inBag) } }) or nil }) })
    elseif S.qty ~= memo.qty then
      text = join({ tostring(S.qty), S._totalCost and lib.moneyString(S._totalCost) or nil })
    end
  elseif st == "confirm" then
    if fresh then
      text = sentences({ say(S._status), H.yesNo(S.yesCursor or 1) })
    elseif S.yesCursor ~= memo.yes then
      text = H.yesNo(S.yesCursor or 1)
    end
  elseif st == "msg" then
    if fresh or S._status ~= memo.status then text = say(S._status) end
  end
  if memo.money ~= nil and money ~= memo.money then text = sentences({ text, lib.moneyText(money) }) end
  memo.at, memo.cursor, memo.status, memo.qty, memo.yes, memo.money = at, S.cursor, S._status, S.qty, S.yesCursor, money
  return text
end

Items.shop = {
  matches = function(state)
    if type(state) ~= "table" or state.gen3 ~= "shop" or not state.layer then return false end
    local mod = package.loaded["src.ui.game3.shop_menu"]
    return mod ~= nil and state.layer.mod == mod and H.isHoenn()
  end,
  poll = function(state, memo, entering)
    local text = shopRead(state.mod, memo, entering)
    if not text then return nil end
    return text, true
  end,
}

-- -------------------------------------------------------------------- PC
-- src/ui/game3/pc_menu.lua: the FireRed presenter reads its root and storage
-- menus; rse/player_pc.lua adds modes player_pc, item_storage, rse_msg and
-- rse_child (a screen of its own on top), with these labels.

local PC_TOP = { item_storage = "gText_ItemStorage", mailbox = "gText_Mailbox",
  decoration = "gText_Decoration", turn_off = "gText_TurnOff" }
local PC_STORAGE = { "gText_WithdrawItem", "gText_DepositItem", "gText_TossItem" }

local function pcLabels(P)
  if P.mode == "player_pc" then
    local PlayerPc = H.loaded("src.ui.game3.rse.player_pc")
    local order = PlayerPc and try(PlayerPc.topOrder, P)
    if type(order) ~= "table" then return nil end
    local out = {}
    for i, id in ipairs(order) do out[i] = say(rom(PC_TOP[id])) end
    return out
  end
  local out = {}
  for i, key in ipairs(PC_STORAGE) do out[i] = say(rom(key)) end
  out[4] = H.first({ "gOtherText_Exit", "gText_Cancel" })
  return out
end

local PC_OWN = { player_pc = true, item_storage = true, rse_msg = true, rse_child = true }

Items.pcMenu = {
  matches = function(state)
    if type(state) ~= "table" or state.gen3 ~= "pc_menu" or not state.layer then return false end
    local mod = package.loaded["src.ui.game3.pc_menu"]
    return mod ~= nil and state.layer.mod == mod and H.isHoenn()
  end,
  poll = function(state, memo, entering)
    local P = state.mod
    if not P.open then return nil end
    local mode = P.mode
    if not PC_OWN[mode] then
      if P._rootRows == nil and type(P._rseRootRows) == "table" and mode == "root" then
        -- Emerald's root rows, named in the same words
        local fresh = entering or memo.ownMode ~= mode
        memo.ownMode = mode
        if not fresh and memo.cursor == P.cursor then return nil end
        memo.cursor = P.cursor
        local row = P._rseRootRows[P.cursor or 1]
        local label = row and say(row.label)
        if fresh then
          return sentences({ say(P._status), label and join({ label, position(P.cursor or 1, #P._rseRootRows) }) }), true
        end
        return label, true
      end
      memo.ownMode = mode
      if entering and mode == "root" and P._rootKey == nil then memo.pending = true end
      local text = Items3.Pc.read(P, memo, entering)
      if not text then return nil end
      return text, true
    end
    local fresh = entering or memo.ownMode ~= mode
    memo.ownMode = mode
    if mode == "rse_child" then return nil end
    if mode == "rse_msg" then
      if not fresh and memo.status == P._status then return nil end
      memo.status = P._status
      local text = say(P._status)
      if not text then return nil end
      return text, true
    end
    if not fresh and memo.cursor == P.cursor and memo.status == P._status then return nil end
    local labels = pcLabels(P)
    if type(labels) ~= "table" then return nil end
    local cursor = P.cursor or 1
    local label = labels[cursor]
    local text
    if mode == "item_storage" then
      if fresh then text = sentences({ label and join({ label, position(cursor, #labels) }), say(P._status) })
      else text = sentences({ label, say(P._status) }) end
    elseif fresh then
      text = sentences({ say(P._status), label and join({ label, position(cursor, #labels) }) })
    else
      text = label
    end
    memo.cursor, memo.status = cursor, P._status
    if not text then return nil end
    return text, true
  end,
}

-- rse/item_storage.lua (layer "rse_item_storage", also in Ruby and Sapphire):
-- rows from session.storage.items, never Storage.ensure (it writes).
Items.itemStorage = {
  matches = Common.matcher("rse_item_storage", "src.ui.game3.rse.item_storage"),
  poll = function(state, memo, entering)
    local S = state.mod
    if not S.open then return nil end
    local session = S._session
    local storage = session and session.storage
    local rows = type(storage) == "table" and type(storage.items) == "table" and storage.items or {}
    local st = S.state
    local fresh = entering or st ~= memo.state
    memo.state = st
    local at = (S.scroll or 0) + (S.row or 0) + 1
    local D = itemsData()
    local function rowText(i)
      local e = rows[i]
      if not e then return say(rom("gText_Cancel2")) end
      return join({ D and say(try(D.displayName, e.id)), "quantity " .. tostring(e.qty) })
    end
    local text
    if st == "list" or st == "swap" then
      if fresh or at ~= memo.at then
        if fresh then
          text = sentences({ memo.opened == nil and say(rom(S._toss and "gText_TossItem" or "gText_WithdrawItem")) or nil,
            st == "swap" and say(S._message) or nil, join({ rowText(at), position(at, #rows + 1) }),
            st == "list" and say(S._message) or nil })
        elseif st == "list" then
          text = sentences({ rowText(at), say(S._message) })
        else
          text = rowText(at)
        end
      end
    elseif st == "quantity" then
      if fresh then
        local e = rows[at]
        text = sentences({ say(S._message), lib.quantity(S.quantity, e and tonumber(e.qty) or 1) })
      elseif S.quantity ~= memo.qty then
        text = tostring(S.quantity)
      end
    elseif st == "yesno" then
      if fresh then text = sentences({ say(S._message), H.yesNo(S.yesCursor or 1) })
      elseif S.yesCursor ~= memo.yes then text = H.yesNo(S.yesCursor or 1) end
    elseif fresh or S._message ~= memo.message then
      text = say(S._message)
    end
    memo.opened, memo.at, memo.qty, memo.yes, memo.message = true, at, S.quantity, S.yesCursor, S._message
    if not text then return nil end
    return text, true
  end,
}

-- ------------------------------------------------------------- region map
-- rse/region_map.lua (layer "rse_region_map"; the wall map and Fly):
-- `RegionMap.active()`: `mode` wall or fly, `state`, `mapSecName`, `nameShown`
-- (wall), `flyText` (fly), `mapSecType`.  Spoken once the cursor stops moving.
Items.regionMap = {
  matches = Common.matcher("rse_region_map"),
  poll = function(state, memo)
    local Map = H.loaded("src.ui.game3.rse.region_map")
    local s = Map and try(Map.active)
    if type(s) ~= "table" then return nil end
    local ready = s.mode == "fly" and s.state == 12 or s.mode == "wall" and s.state == 4
    if not ready then return nil end
    local name
    if s.mode == "fly" then
      local t = s.flyText
      name = type(t) == "table" and join({ say(t.name), say(t.sub) }) or nil
      local canFly = Map.TYPE and (s.mapSecType == Map.TYPE.CITY_CANFLY or s.mapSecType == Map.TYPE.BATTLE_FRONTIER)
      if name and canFly then name = name .. ", can fly" end
    else
      name = s.nameShown and say(s.mapSecName) or nil
    end
    if not memo.opened then
      memo.opened, memo.name = true, name
      local head = s.mode == "fly" and say(rom("gText_FlyToWhere")) or "Town map"
      return sentences({ head, name, name and "you are here" or nil }), true
    end
    if name == memo.name then return nil end
    memo.name = name
    if not name then return nil end
    return name, true
  end,
}

Items.ordered = { Items.bag, Items.summaryEmerald, Items.summaryRuby, Items.pokedex, Items.shop,
  Items.pcMenu, Items.itemStorage, Items.regionMap }

return Items
