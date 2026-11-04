-- Field screens a Hoenn player meets (Ruby, Sapphire, Emerald): secret base
-- decorating, mail, word entry, the casino, the move tutor, credits, diploma,
-- day-care menus, the glass workshop, link windows and the two scenes that have
-- no text.  FireRed's presenters keep what reads the same (Emerald's Easy Chat,
-- hall of fame, party, dialogue, multichoice).
--
-- Only fields and read-only functions are used.  Not called, because they
-- write: Decor.context and SecretBase.base (normalise the save's lists; the raw
-- session fields are read instead), UI:func in the casino (fills its cache;
-- `s.fn` is read instead).
--
-- Drawn as images, so said in our words: secret base in-use markers, the place
-- under the decorating cursor (a moving sprite), word editor footer and side
-- buttons, roulette board and wheel (colours, Pokémon, multiplier, balls), slot
-- symbols, bet lamps, credit and payout digits, Power meter, Reel Time display,
-- payout chart, stationery name and icon on a letter.

local Common = require("src.access.screens.gen3.Common")
local H = require("src.access.screens.gen3.HoennCommon")
local Top = require("src.access.screens.gen3.Top")

local Field = {}

local say, join, sentences, try, position, loaded = H.say, H.join, H.sentences, H.try, Common.position, H.loaded

local function yesNoRow(cursor)
  return join({ H.yesNo(cursor + 1), position(cursor + 1, 2) })
end

local function plural(n, word)
  if n == 1 then return "1 " .. word end
  return tostring(n) .. " " .. word .. "s"
end

-- The running task of a GBA scene (`self.fn[name]` is what UI:setFunc stored).
local function inTask(s, taskId, ...)
  local task = taskId and s.m and s.m.tasks and s.m.tasks.t and s.m.tasks.t[taskId]
  if not (task and s.fn) then return false end
  for _, name in ipairs({ ... }) do
    if s.fn[name] ~= nil and task.func == s.fn[name] then return true end
  end
  return false
end

-- ------------------------------------------------------------- decorating

-- src/ui/game3/rse/decoration.lua, one module for all three games; Ruby and
-- Sapphire pass their own text through `_opts.text` (rs/decoration.lua).
local DECOR_ACTIONS = { "gText_Decorate", "gText_PutAway", "gText_Toss2", "gText_Cancel" }
local DECOR_CATEGORIES = { [0] = "gText_Desk", "gText_Chair", "gText_Plant", "gText_Ornament", "gText_Mat",
  "gText_Poster", "gText_Doll", "gText_Cushion" }
local MENU_PLACE, MENU_TRADE = 0, 2
local DOLL, CUSHION = 6, 7

local function decorText(D, key)
  if D._opts and D._opts.text then return say(try(D._opts.text, key)) end
  return say(H.rom(key))
end

local function decorInventory() return loaded("src.core.game3.rse.decoration_inventory") end

local function categoryRow(D)
  local Inv = decorInventory()
  local cat = D.catCursor or 0
  local total = (loaded("src.core.game3.rse.decoration").CATEGORY_COUNT or 8) + 1
  local at = position(cat + 1, total)
  if cat == total - 1 then
    return join({ decorText(D, D.command == MENU_TRADE and "gText_Exit" or "gText_Cancel"), at })
  end
  -- rse/decoration.lua catDisabled: only dolls and cushions go in the bedroom.
  local disabled = D.isPlayerRoom and D.command == MENU_PLACE and cat ~= DOLL and cat ~= CUSHION
  return join({ decorText(D, DECOR_CATEGORIES[cat]),
    "owned " .. tostring(Inv.countInCategory(cat, D._session)) .. " of " .. tostring(Inv.SIZES[cat]),
    disabled and "not for this room" or nil, at })
end

local function itemRow(D)
  local Inv = decorInventory()
  local index = D.scroll + D.row + 1
  local count = Inv.countInCategory(D.category, D._session) + 1
  local at = position(index, count)
  if index >= count then
    return sentences({ join({ decorText(D, "gText_Cancel"), at }), decorText(D, "gText_GoBackPrevMenu") })
  end
  local list = Inv.inventories(D._session)[D.category]
  local info = Inv.info(list[index]) or {}
  -- the red and blue markers of rse/decoration.lua drawItems
  local mark = D.inBase and D.inBase[index] and "in use in your base"
    or D.inRoom and D.inRoom[index] and "in use in your room" or nil
  return sentences({ join({ say(info.name), mark, at }), say(info.description) })
end

-- The cursor from where the player stood, as cells on the map.
local function offsetWords(m)
  local dx, dy = m.x - m.initialX, m.y - m.initialY
  local parts = {}
  if dx ~= 0 then parts[#parts + 1] = tostring(math.abs(dx)) .. (dx > 0 and " right" or " left") end
  if dy ~= 0 then parts[#parts + 1] = tostring(math.abs(dy)) .. (dy > 0 and " down" or " up") end
  if #parts == 0 then return "where you stood" end
  return table.concat(parts, ", ")
end

local function secretBase() return loaded("src.core.game3.rse.secret_base") end

local function placeWords(m)
  local Decor = loaded("src.core.game3.rse.decoration")
  local grid = try(secretBase().fieldGrid)
  local ok = grid and try(Decor.canPlace, grid, { x = m.x, y = m.y, initialX = m.initialX, initialY = m.initialY }, m.decor)
  if ok == nil then return nil end
  return ok and "can be placed" or "cannot be placed"
end

-- What A would pick up here (rse/decoration.lua attemptPutAway), from the
-- session's raw lists: Decor.context writes them back.
local function putAwayWords(D, m)
  local Decor = loaded("src.core.game3.rse.decoration")
  local Inv = decorInventory()
  local sess = D._session
  local ctx
  if D.isPlayerRoom then
    ctx = { items = sess.playerRoomDecorations, pos = sess.playerRoomDecorationPositions, size = Decor.MAX_PLAYERS_HOUSE }
  else
    local base = type(sess.secretBases) == "table" and sess.secretBases[1]
    ctx = base and { items = base.decorations, pos = base.decorationPositions, size = Decor.MAX_SECRET_BASE }
  end
  local grid = try(secretBase().fieldGrid)
  if not (ctx and ctx.items and ctx.pos and grid) then return nil end
  local marked = try(Decor.markForRemoval, grid, ctx, m.x, m.y)
  local first = type(marked) == "table" and marked[1]
  if first then
    local info = Inv.info(ctx.items[first.idx])
    return info and say(info.name) or nil
  end
  local beh = try(grid.behavior, m.x, m.y)
  if beh and (try(Decor.isBeh, beh, "SECRET_BASE_PC") or try(Decor.isBeh, beh, "PLAYER_ROOM_PC_ON")) then return "PC" end
  return "nothing here"
end

Field.decoration = {
  matches = Common.matcher("rse_decoration"),
  poll = function(state, memo)
    local D = H.loaded("src.ui.game3.rse.decoration")
    if not (D and D.open_) then return nil end
    local s = D.state
    local parts, queued = {}, false
    -- the description in the action menu is said with its row
    if D.msg ~= memo.msg then
      memo.msg = D.msg
      if D.msg and D.view ~= "actions" then parts[#parts + 1] = say(D.msg.text) end
    end
    local changed = s ~= memo.state
    if s == "actions" then
      if changed or D.actionCursor ~= memo.action then
        memo.action = D.actionCursor
        parts[#parts + 1] = sentences({ join({ decorText(D, DECOR_ACTIONS[D.actionCursor + 1]),
          position(D.actionCursor + 1, #DECOR_ACTIONS) }), D.msg and say(D.msg.text) or nil })
      end
    elseif s == "categories" then
      if changed or D.catCursor ~= memo.cat then
        memo.cat = D.catCursor
        parts[#parts + 1] = categoryRow(D)
      end
    elseif s == "items" then
      local key = D.category .. ":" .. (D.scroll + D.row)
      if changed or key ~= memo.item then
        memo.item = key
        if memo.itemsOf ~= D.category then
          memo.itemsOf = D.category
          parts[#parts + 1] = decorText(D, DECOR_CATEGORIES[D.category])
        end
        parts[#parts + 1] = itemRow(D)
      end
    elseif s == "place" or s == "putaway" then
      local m = D.mode
      local key = m and (m.x .. ":" .. m.y)
      if m and (changed or key ~= memo.cell) then
        memo.cell = key
        if memo.modeOf ~= m then
          memo.modeOf = m
          if s == "place" then
            local info = decorInventory().info(m.decor) or {}
            parts[#parts + 1] = join({ say(info.name), tostring(m.w) .. " wide", tostring(m.h) .. " tall" })
            parts[#parts + 1] = "Arrows move it, A places it, B cancels"
          else
            parts[#parts + 1] = decorText(D, "gText_PutAway")
            parts[#parts + 1] = "Arrows move the cursor, A puts away, B stops"
          end
        end
        parts[#parts + 1] = join({ offsetWords(m), s == "place" and placeWords(m) or putAwayWords(D, m) })
      end
    elseif s == "yesno" then
      if changed or D.yesCursor ~= memo.yes then
        queued = changed and #parts == 0
        memo.yes = D.yesCursor
        parts[#parts + 1] = yesNoRow(D.yesCursor - 1)
      end
    elseif s == "registry" then
      local index = D.regScroll + D.regRow + 1
      if changed or index ~= memo.reg then
        memo.reg = index
        local rows = try(secretBase().registryEntries, D._session) or {}
        local row = rows[index]
        parts[#parts + 1] = join({ row and say(row.name) or decorText(D, "gText_Cancel"), position(index, #rows + 1) })
      end
    elseif s == "registry_actions" then
      if changed or D.regAction ~= memo.regAction then
        memo.regAction = D.regAction
        parts[#parts + 1] = join({ decorText(D, D.regAction == 0 and "gText_DelRegist" or "gText_Cancel"),
          position(D.regAction + 1, 2) })
      end
    end
    memo.state = s
    local text = sentences(parts)
    if not text then return nil end
    return text, not queued
  end,
}

-- ------------------------------------------------------------------- mail

local function itemName(id)
  local Items = loaded("src.core.game3.items_data")
  return Items and say(try(Items.displayName, id)) or nil
end

-- rse/mail.lua: `_lines`, signature gText_FromSpace and the sender.
Field.mail = {
  matches = Common.matcher("rse_mail"),
  poll = function(_, memo)
    local M = loaded("src.ui.game3.rse.mail")
    if not (M and M.open) or memo.said then return nil end
    memo.said = true
    local mail = M._mail or {}
    local parts = { itemName(mail.itemId) }
    if M._hasText then
      for _, line in ipairs(M._lines or {}) do parts[#parts + 1] = say(line) end
      parts[#parts + 1] = say((H.rom("gText_FromSpace") or "") .. tostring(mail.playerName or ""))
    end
    parts[#parts + 1] = "Press A"
    return sentences(parts), true
  end,
}

-- rs/mail_reader.lua: `_content` is what the draw code prints.
Field.rsMail = {
  matches = Common.matcher("rs_mail"),
  poll = function(_, memo)
    local M = loaded("src.ui.game3.rs.mail_reader")
    if not (M and M.open) or memo.said then return nil end
    memo.said = true
    local content = M._content or {}
    local parts = { itemName(M._mail and M._mail.itemId) }
    for _, row in ipairs(content.rows or {}) do parts[#parts + 1] = say(row.text) end
    if content.signature then parts[#parts + 1] = say(content.signature.text) end
    -- the sender's Pokémon, drawn as an icon on the stationery
    local Pokemon = loaded("src.core.game3.pokemon")
    if content.icon and Pokemon then parts[#parts + 1] = say(try(Pokemon.name, content.icon.species)) end
    parts[#parts + 1] = "Press A"
    return sentences(parts), true
  end,
}

-- rse/mailbox.lua (all three games): `state`, `scroll`, `row`, `optCursor`,
-- `yesCursor`, `_status`.
local MAIL_OPTION_KEYS_RS = { "OtherText_Read", "gOtherText_MoveToBag", "OtherText_Give", "gOtherText_CancelNoTerminator" }

local function mailOption(i)
  local Policy = loaded("src.ui.game3.rs.player_pc_policy")
  local M = loaded("src.ui.game3.rse.mailbox")
  if Policy and try(Policy.matches, M._session) then return say(H.rom(MAIL_OPTION_KEYS_RS[i])) end
  return say(H.romAt("gMailboxMailOptions", i - 1))
end

Field.mailbox = {
  matches = Common.matcher("rse_mailbox"),
  poll = function(_, memo)
    local M = loaded("src.ui.game3.rse.mailbox")
    if not (M and M.open) then return nil end
    local st = M.state
    local changed = st ~= memo.state
    local parts, queued = {}, false
    if st == "list" then
      local count = try(M.count) or 0
      local index = M.scroll + M.row + 1
      if changed or index ~= memo.index then
        memo.index = index
        if not memo.opened then
          memo.opened = true
          parts[#parts + 1] = say(H.rom("gText_Mailbox"))
        end
        local mail = index <= count and try(M.selectedMail) or nil
        local label = mail and say(tostring(mail.playerName or "")) or H.first({ "gText_Cancel2", "gOtherText_CancelNoTerminator" })
        parts[#parts + 1] = join({ label, position(index, count + 1) })
      end
    elseif st == "options" then
      if changed then parts[#parts + 1] = say(M._status) end
      if changed or M.optCursor ~= memo.opt then
        memo.opt = M.optCursor
        parts[#parts + 1] = join({ mailOption(M.optCursor), position(M.optCursor, 4) })
      end
    elseif st == "confirm_msg" or st == "message" then
      if changed then parts[#parts + 1] = say(M._status) end
    elseif st == "confirm" then
      if changed or M.yesCursor ~= memo.yes then
        queued = changed
        memo.yes = M.yesCursor
        parts[#parts + 1] = yesNoRow(M.yesCursor - 1)
      end
    end
    memo.state = st
    local text = sentences(parts)
    if not text then return nil end
    return text, not queued
  end,
}

-- ------------------------------------------------------------- word entry

-- rs/mail_composer.lua, rs/easy_chat_editor.lua and rs/trendy_phrase.lua keep
-- one shape: `_view` phrase, groups, words or none; `_confirm` over the phrase.
-- Footer and side buttons are drawn from tiles, so they are our words.
local EDITOR_FOOTER = { "DEL. ALL", "CANCEL", "OK" }
local EDITOR_SIDE = { "MODE", "DEL.", "CANCEL" }
local EMPTY_WORD = 65535

local function easyWord(id)
  local Easy = loaded("src.core.game3.easy_chat_text")
  if not Easy or id == nil or id == EMPTY_WORD then return nil end
  return say(try(Easy.word, id))
end

local function editorShape(C)
  local man = C._man or {}
  local count = man.wordCount or #(C.words or {})
  local columns = man.columns or 2
  local rows = man.rows or math.ceil(count / columns)
  return count, columns, rows
end

local function editorPhrase(C)
  local count = editorShape(C)
  local words = {}
  for i = 1, count do
    local word = easyWord(C.words[i])
    if word then words[#words + 1] = word end
  end
  if #words == 0 then return "empty" end
  return table.concat(words, " ")
end

local function editorSlot(C)
  local count, columns, rows = editorShape(C)
  if C.row >= rows then
    return join({ EDITOR_FOOTER[C.col + 1], position(C.col + 1, #EDITOR_FOOTER) })
  end
  local index = C.row * columns + C.col + 1
  return join({ "word " .. index .. " of " .. count, easyWord(C.words[index]) or "empty" })
end

-- The lines of a confirmation box, as each editor's prompt() picks them.
local function editorConfirmLines(C, kind)
  local labels = C._man.texts
  local lines
  if kind == "save" then lines = labels.confirm
  elseif kind == "cancel" then lines = { labels.cancel }
  elseif kind == "discard" then lines = { labels.discard1, labels.discard2 }
  elseif kind == "bardRestore" then lines = { labels.bardRestore1, labels.bardRestore2 }
  elseif kind == "delete" then lines = { labels.delete1, labels.delete2 }
  else lines = { labels[kind] } end
  local out = {}
  for _, line in ipairs(type(lines) == "table" and lines or { lines }) do out[#out + 1] = say(line) end
  return join(out, " ")
end

local YESNO_CONFIRM = { save = true, cancel = true, discard = true, delete = true }

local function editorGroups(C)
  local Easy = loaded("src.core.game3.easy_chat_text")
  local g = C._group
  if g.sidebar then
    return join({ EDITOR_SIDE[g.row], position(g.row, #EDITOR_SIDE) })
  end
  if g.alpha then
    local ch = (C._man.alphabet[g.row + 1] or ""):sub(g.col + 1, g.col + 1)
    if ch == " " or ch == "" then return "OTHERS" end
    return ch
  end
  local index = g.row * 2 + g.col + 1
  local group = C.groups[index]
  return group and join({ say(try(Easy.groupName, group)), position(index, #C.groups) }) or nil
end

local function editorPoll(path)
  return function(_, memo)
    local C = loaded(path)
    if not (C and C.open and C._man) or C._state == "setup" then return nil end
    local parts, queued = {}, false
    local view, confirm = C._view, C._confirm
    if confirm then
      if memo.confirm ~= confirm then
        memo.confirm = confirm
        memo.cursor = confirm.cursor
        parts[#parts + 1] = editorConfirmLines(C, confirm.kind)
        if confirm.kind == "save" then parts[#parts + 1] = editorPhrase(C) end
        if YESNO_CONFIRM[confirm.kind] then parts[#parts + 1] = yesNoRow(confirm.cursor) end
      elseif confirm.cursor ~= memo.cursor then
        memo.cursor = confirm.cursor
        parts[#parts + 1] = yesNoRow(confirm.cursor)
      end
    elseif view == "phrase" then
      local key = C.row .. ":" .. C.col .. ":" .. tostring(C.words[C.row * (C._man.columns or 2) + C.col + 1])
      local fresh = memo.view ~= "phrase" or memo.confirm ~= nil
      if fresh or key ~= memo.slot then
        memo.slot = key
        if not memo.opened then
          memo.opened = true
          local lines = C._man.texts.edit
          for _, line in ipairs(type(lines) == "table" and lines or { lines }) do parts[#parts + 1] = say(line) end
        end
        if fresh then parts[#parts + 1] = editorPhrase(C) end
        parts[#parts + 1] = editorSlot(C)
      end
      memo.confirm = nil
    elseif view == "groups" then
      local g = C._group
      local key = table.concat({ tostring(g.alpha), g.row, g.col, tostring(g.sidebar) }, ":")
      if memo.view ~= "groups" or key ~= memo.group then
        memo.group = key
        if memo.view ~= "groups" or memo.alpha ~= g.alpha then
          memo.alpha = g.alpha
          parts[#parts + 1] = g.alpha and "Words by letter" or "Words by group"
        end
        parts[#parts + 1] = editorGroups(C)
      end
    elseif view == "words" and C._word and C._list then
      local index = C._word.row * 2 + C._word.col + 1
      if memo.view ~= "words" or index ~= memo.word then
        memo.word = index
        local row = C._list[index]
        parts[#parts + 1] = join({ row and easyWord(row.id), position(index, #C._list) })
      end
    end
    memo.view = confirm and "phrase" or view
    local text = sentences(parts)
    if not text then return nil end
    return text, not queued
  end
end

Field.composer = { matches = Common.matcher("rs_mail_composer"), poll = editorPoll("src.ui.game3.rs.mail_composer") }
Field.easyChatEditor = { matches = Common.matcher("rs_easy_chat_editor"), poll = editorPoll("src.ui.game3.rs.easy_chat_editor") }
Field.trendyPhrase = { matches = Common.matcher("rs_trendy_phrase"), poll = editorPoll("src.ui.game3.rs.trendy_phrase") }

-- --------------------------------------------------------------- roulette

-- rse/roulette.lua; rs/roulette.lua opens through the same Host and Entry.
local ROW_WORDS = { "ORANGE", "GREEN", "PURPLE" }
local COL_WORDS = { "WYNAUT", "AZURILL", "SKITTY", "MAKUHITA" }

-- pokeemerald/src/roulette.c:49 the grid selection numbers.
local function squareWords(sel)
  if not sel or sel <= 0 or sel > 19 then return nil end
  if sel <= 4 then return "all " .. COL_WORDS[sel] end
  local row, col = math.floor(sel / 5), sel % 5
  if col == 0 then return "all " .. ROW_WORDS[row] end
  return ROW_WORDS[row] .. " " .. COL_WORDS[col]
end

local function rouletteHits(s, count)
  local names = {}
  for i = 0, count - 1 do
    local name = squareWords(s.st.hitSquares[i])
    if name then names[#names + 1] = name end
  end
  if #names == 0 then return nil end
  return "Hit so far: " .. table.concat(names, ", ")
end

local function rouletteSquare(s, sel)
  local R = loaded("src.core.game3.rse.roulette")
  local name = squareWords(sel)
  if not name then return nil end
  local multiplier = try(R.getMultiplier, s.T, s.st, sel)
  local row = s.T.grid[sel]
  local hit = row and math.floor((s.st.hitFlags or 0) / (row.flag or 1)) % 2 == 1 and (row.flag or 0) > 0
  local mark = multiplier and multiplier > 0 and ("pays " .. multiplier .. " times") or "already hit"
  if hit and not (sel <= 4 or sel % 5 == 0) then mark = "already hit" end
  return join({ name, mark })
end

Field.roulette = {
  matches = Common.matcher("rse_roulette"),
  poll = function(state, memo)
    local Base = loaded("src.ui.game3.rse.roulette")
    local s = Base and try(Base.active)
    if type(s) ~= "table" or not s.st or not s.st.playTaskId then return nil end
    local task = s.m.tasks.t[s.st.playTaskId]
    local d = task and task.data
    if not d then return nil end
    local parts, queued = {}, false
    if not memo.opened then
      memo.opened = true
      parts[#parts + 1] = sentences({ "Roulette", "Coins " .. tostring(d[13] or 0), "Bet " .. tostring(s.st.minBet) .. " a ball" })
    end
    if s.text ~= memo.textObj then
      memo.textObj = s.text
      if s.text then parts[#parts + 1] = say(s.text.text) end
    end
    local id = s.st.playTaskId
    if inTask(s, id, "taskHandleBetGridInput") then
      local sel = d[4]
      if not memo.betting then
        memo.betting = true
        memo.placed = nil
        memo.landed = nil
        parts[#parts + 1] = sentences({ "Coins " .. tostring(d[13] or 0), plural(6 - (d[6] or 0), "ball") .. " left",
          rouletteHits(s, d[6] or 0), "Arrows choose, A bets" })
        memo.sel = sel
        parts[#parts + 1] = rouletteSquare(s, sel)
      elseif sel ~= memo.sel then
        memo.sel = sel
        parts[#parts + 1] = rouletteSquare(s, sel)
      end
    else
      memo.betting = nil
    end
    if not memo.placed and inTask(s, id, "taskStartSpin", "taskSlideGridOffscreen", "taskInitBallRoll", "taskRollBall") then
      memo.placed = true
      local chosen = s.st.betSelection[s.st.curBallNum]
      parts[#parts + 1] = sentences({ "Bet on " .. tostring(squareWords(chosen)), "Coins " .. tostring(d[13] or 0) })
    end
    -- taskRecordBallHit: the ball has stopped in `hitSlot`; the roll itself has no text.
    if not memo.landed and inTask(s, id, "taskRecordBallHit") and (d[1] or 0) > 0 then
      memo.landed = true
      local slot = s.T.slots and s.T.slots[s.st.hitSlot]
      if slot then parts[#parts + 1] = "Ball on " .. tostring(squareWords(slot.gridSquare)) end
    end
    if s.yesNo then
      local cursor = s.yesNo.cursor or 0
      if cursor ~= memo.cursor then
        queued = memo.cursor == nil and #parts == 0
        memo.cursor = cursor
        parts[#parts + 1] = yesNoRow(cursor)
      end
    else
      memo.cursor = nil
    end
    local text = sentences(parts)
    if not text then return nil end
    return text, not queued
  end,
}

Field.rouletteEntry = {
  matches = Common.matcher("rse_roulette_entry"),
  poll = function(_, memo)
    local Base = loaded("src.ui.game3.rse.roulette")
    local e = Base and Base.Entry and Base.Entry._entry
    if type(e) ~= "table" then return nil end
    local parts = {}
    if e.text ~= memo.text then
      memo.text = e.text
      parts[#parts + 1] = say(e.text)
    end
    local cursor = e.yesNo and e.yesNo.cursor
    local queued = false
    if cursor and cursor ~= memo.cursor then
      queued = memo.cursor == nil and #parts == 0
      parts[#parts + 1] = yesNoRow(cursor)
    end
    memo.cursor = cursor
    local text = sentences(parts)
    if not text then return nil end
    return text, not queued
  end,
}

-- ------------------------------------------------------------------ slots

-- rse/slot_machine.lua and its Ruby and Sapphire class; the symbols are images.
local SYMBOL_WORDS = { [0] = "red 7", "blue 7", "AZURILL", "LOTAD", "CHERRY", "POWER", "REPLAY" }

local function reelWords(core, reel)
  local names = {}
  for row = 1, 3 do
    names[#names + 1] = SYMBOL_WORDS[try(core.getSymbolAtRest, core, reel, row)] or "unknown"
  end
  return "Reel " .. (reel + 1) .. ": " .. table.concat(names, ", ")
end

-- The lines a bet plays and flashes (rse/slot_machine core checkMatch).
local SLOT_LINES = {
  { "middle row", 2, 2, 2, 1 }, { "top row", 1, 1, 1, 2 }, { "bottom row", 3, 3, 3, 2 },
  { "diagonal from top left", 1, 2, 3, 3 }, { "diagonal from bottom left", 3, 2, 1, 3 },
}
local BET_WORDS = { "middle row", "all three rows", "all rows and diagonals" }

local function slotWin(core, payout)
  local Slots = loaded("src.core.game3.rse.slot_machine")
  local parts = { "Win. Payout " .. tostring(payout) }
  for _, line in ipairs(SLOT_LINES) do
    if core.bet >= line[5] then
      local a, b, c = core:getSymbolAtRest(0, line[2]), core:getSymbolAtRest(1, line[3]), core:getSymbolAtRest(2, line[4])
      if core:getMatchFromSymbols(a, b, c) ~= Slots.MATCH.NONE then
        parts[#parts + 1] = line[1] .. ": " .. table.concat({ SYMBOL_WORDS[a], SYMBOL_WORDS[b], SYMBOL_WORDS[c] }, ", ")
      end
    end
  end
  return sentences(parts)
end

-- The payout chart is a picture; its rows come from the table `T.payouts`.
local function slotChart(s)
  local Slots = loaded("src.core.game3.rse.slot_machine")
  local M, pay = Slots.MATCH, s.T.payouts
  if not pay then return nil end
  local rows = {
    "red 7 or blue 7, three of a kind: " .. tostring(pay[M.RED_7]),
    "mixed 7s: " .. tostring(pay[M.MIXED_7]),
    "AZURILL: " .. tostring(pay[M.AZURILL]),
    "LOTAD: " .. tostring(pay[M.LOTAD]),
    "POWER: " .. tostring(pay[M.POWER]),
    "CHERRY on the first reel: " .. tostring(pay[M.CHERRY]),
    "REPLAY: spin again",
  }
  return "Payouts. " .. table.concat(rows, ", ")
end

Field.slots = {
  matches = Common.matcher("rse_slot_machine"),
  poll = function(state, memo)
    local Base = loaded("src.ui.game3.rse.slot_machine")
    local s = Base and try(Base.active)
    if type(s) ~= "table" or not s.core then return nil end
    local c, ST = s.core, Base.STATE
    local cs = c.state
    local parts, queue = {}, false
    if cs == ST.UNFADE or cs == ST.WAIT_FADE then return nil end
    if not memo.opened then
      memo.opened = true
      parts[#parts + 1] = "Slot machine"
      parts[#parts + 1] = "Down bets 1 coin, R bets 3, A spins and stops each reel, Select shows the payouts, B quits. Each reel reads top to bottom"
    end
    if c.reelTimeSpinsLeft ~= memo.reelTime then
      if (c.reelTimeSpinsLeft or 0) > (memo.reelTime or 0) then
        parts[#parts + 1] = "Reel Time, " .. plural(c.reelTimeSpinsLeft, "spin")
      end
      memo.reelTime = c.reelTimeSpinsLeft
    end
    if cs == ST.BET_INPUT then
      if not memo.betting then
        memo.betting = true
        parts[#parts + 1] = "Coins " .. tostring(c.coins)
      end
    else
      memo.betting = nil
    end
    if c.bet ~= memo.bet then
      memo.bet = c.bet
      if (c.bet or 0) > 0 then
        parts[#parts + 1] = sentences({ "Bet " .. c.bet .. ": " .. BET_WORDS[c.bet], "Coins " .. tostring(c.coins) })
      end
    end
    if cs == ST.WAIT_REEL_STOP and memo.spinningOf ~= 0 and c.currentReel == 0 then
      memo.spinningOf, memo.reel, memo.won = 0, 0, nil
      parts[#parts + 1] = "Spinning"
    end
    if (c.currentReel or 0) > (memo.reel or 0) then
      for reel = memo.reel or 0, math.min(c.currentReel, 3) - 1 do
        parts[#parts + 1] = reelWords(c, reel)
        queue = true
      end
      memo.reel = c.currentReel
    end
    if cs == ST.WAIT_PAYOUT or cs == ST.END_PAYOUT then
      if not memo.won then
        memo.won = true
        memo.spinningOf = nil
        parts[#parts + 1] = slotWin(c, c.payout)
        queue = true
      end
    elseif cs == ST.NO_MATCHES then
      if not memo.won then
        memo.won = true
        memo.spinningOf = nil
        parts[#parts + 1] = "No win"
        queue = true
      end
    end
    if c.pikaPowerBolts ~= memo.bolts then
      if memo.bolts ~= nil and (c.pikaPowerBolts or 0) > memo.bolts then
        parts[#parts + 1] = "Power " .. tostring(c.pikaPowerBolts) .. " of 16"
        queue = true
      end
      memo.bolts = c.pikaPowerBolts
    end
    if s.message ~= memo.message then
      memo.message = s.message
      if s.message then parts[#parts + 1] = say(s.message.text); queue = false end
    end
    local cursor = s.yesNo and s.yesNo.cursor
    if cursor and cursor ~= memo.cursor then
      parts[#parts + 1] = yesNoRow(cursor)
    end
    memo.cursor = cursor
    local info = s.infoWindow and s.infoWindow.text == true
    if info ~= memo.info then
      memo.info = info
      if info then
        parts[#parts + 1] = slotChart(s)
        parts[#parts + 1] = say(H.first({ "gText_ReelTimeHelp", "gOtherText_ReelTime" }))
      end
    end
    local text = sentences(parts)
    if not text then return nil end
    return text, not queue
  end,
}

-- ------------------------------------------------------------- move tutor

-- rse/move_relearner.lua (layer "move_relearner", shared id with FireRed's
-- module, so it matches on the module): the window draw_battle or draw_contest
-- shows.  Ruby and Sapphire pass their own text through `_opts.text`.
local function relearnerText(M, key, ctx)
  if M._opts and M._opts.text then return say(try(M._opts.text, key, ctx)) end
  return say(H.rom(key, ctx))
end

local function relearnerBattle(M, id)
  local Pokemon = loaded("src.core.game3.pokemon")
  local Types = loaded("src.core.game3.battle.types")
  local Summary = loaded("src.core.game3.summary_data")
  local row = try(Pokemon.battleMove, id) or {}
  local power, accuracy = tonumber(row.power) or 0, tonumber(row.accuracy) or 0
  local name = try(Pokemon.moveName, id)
  return sentences({
    join({ "TYPE " .. tostring(say(Types and try(Types.name, tonumber(row.type) or 0)) or ""),
      "POWER " .. (power < 2 and "---" or tostring(power)),
      "ACCURACY " .. (accuracy == 0 and "---" or tostring(accuracy)),
      "PP " .. tostring(tonumber(row.pp) or 0) }),
    Summary and say(try(Summary.moveDescription, id, name)) or nil,
  })
end

local function relearnerContest(id)
  local Kit = loaded("src.ui.game3.rse.scene_kit")
  local Summary = loaded("src.core.game3.summary_data")
  local data = Kit and try(Kit.loadLua, "data/generated/gba/pokemon/contest_moves.lua")
  local move = data and data.moves and data.moves[id]
  local eff = move and data.effects and data.effects[move.effect]
  if not eff then return nil end
  local function hearts(value)
    value = tonumber(value) or 0
    if value == 0xFF then return 0 end
    return math.floor(value / 10)
  end
  return sentences({
    join({ say(try(Summary.contestCategoryName, data.categories and data.categories[move.category])),
      "APPEAL " .. plural(hearts(eff.appeal), "heart"), "JAM " .. plural(hearts(eff.jam), "heart") }),
    say(try(Summary.contestEffectDescription, eff)),
  })
end

local function relearnerRow(M)
  local moves = try(M.moves) or {}
  local id = moves[M.cursor]
  local total = #moves + 1
  if not id then
    return join({ relearnerText(M, "gText_Cancel") or H.first({ "gOtherText_Exit", "gOtherText_CancelNoTerminator" }),
      position(M.cursor, total) })
  end
  local Pokemon = loaded("src.core.game3.pokemon")
  return sentences({ join({ say(try(Pokemon.moveName, id)), position(M.cursor, total) }),
    M.contest and relearnerContest(id) or relearnerBattle(M, id) })
end

Field.moveRelearner = {
  matches = Common.matcher("move_relearner", "src.ui.game3.rse.move_relearner"),
  poll = function(_, memo)
    local M = loaded("src.ui.game3.rse.move_relearner")
    if not (M and M.open) then return nil end
    local st = M.state
    local changed = st ~= memo.state
    local parts, queued = {}, false
    if st == "list" then
      if changed or M.cursor ~= memo.cursor or M.contest ~= memo.contest then
        if changed or memo.state == nil then parts[#parts + 1] = say(M.prompt) end
        if M.contest ~= memo.contest and memo.contest ~= nil then
          parts[#parts + 1] = M.contest and "CONTEST MOVES" or "BATTLE MOVES"
        end
        memo.cursor, memo.contest = M.cursor, M.contest
        parts[#parts + 1] = relearnerRow(M)
      end
    elseif st == "message" then
      if changed or M.prompt ~= memo.prompt then parts[#parts + 1] = say(M.prompt) end
    elseif st == "yesno" then
      if changed or M.prompt ~= memo.prompt then
        parts[#parts + 1] = say(M.prompt)
        parts[#parts + 1] = yesNoRow(M.yesNoCursor - 1)
        memo.yes = M.yesNoCursor
      elseif M.yesNoCursor ~= memo.yes then
        memo.yes = M.yesNoCursor
        parts[#parts + 1] = yesNoRow(M.yesNoCursor - 1)
      end
    end
    memo.state, memo.prompt = st, M.prompt
    local text = sentences(parts)
    if not text then return nil end
    return text, not queued
  end,
}

-- ---------------------------------------------------------------- credits

-- rse/credits.lua: `state.text` is a page of rows, `showMons` a slide of
-- Pokémon by national number, `theEnd` the closing picture.
Field.credits = {
  matches = Common.matcher("rse_credits"),
  poll = function(_, memo)
    local C = loaded("src.ui.game3.rse.credits")
    local st = C and C.state
    if not (C and C.open and type(st) == "table") then return nil end
    local parts = {}
    if st.text ~= memo.text then
      memo.text = st.text
      if type(st.text) == "table" then
        local rows = {}
        for _, row in ipairs(st.text) do
          local line = say(row.text)
          if line then rows[#rows + 1] = line end
        end
        if #rows > 0 then parts[#parts + 1] = table.concat(rows, ", ") end
      end
    end
    memo.mons = memo.mons or {}
    local Pokemon = loaded("src.core.game3.pokemon")
    if st.showMons and Pokemon then
      for _, sprite in ipairs(st.mons or {}) do
        if sprite.nat and not sprite.invisible and not memo.mons[sprite] then
          memo.mons[sprite] = true
          local species = try(Pokemon.speciesFromNational, sprite.nat)
          parts[#parts + 1] = species and say(try(Pokemon.name, species)) or nil
        end
      end
    end
    if st.theEnd and not memo.theEnd then
      memo.theEnd = true
      parts[#parts + 1] = "THE END"
    end
    local text = sentences(parts)
    if not text then return nil end
    return text, false
  end,
}

-- ---------------------------------------------------------- small screens

-- rs/diploma.lua: `_content` is every piece of text the draw code prints.
Field.rsDiploma = {
  matches = Common.matcher("rs_diploma"),
  poll = function(_, memo)
    local D = loaded("src.ui.game3.rs.diploma")
    if not (D and D.open and D._content) or memo.said then return nil end
    memo.said = true
    local lines, order = {}, {}
    for _, row in ipairs(D._content) do
      if not lines[row.y] then lines[row.y] = {}; order[#order + 1] = row.y end
      table.insert(lines[row.y], (tostring(row.text)))
    end
    table.sort(order)
    local parts = {}
    for _, y in ipairs(order) do parts[#parts + 1] = say(table.concat(lines[y])) end
    return sentences(parts), true
  end,
}

-- rs/glass_workshop.lua keeps its rows in a closure.
local function upvalue(fn, wanted)
  if type(fn) ~= "function" then return nil end
  for i = 1, 16 do
    local name, value = debug.getupvalue(fn, i)
    if not name then return nil end
    if name == wanted then return value end
  end
  return nil
end

Field.glassWorkshop = {
  matches = Common.matcher("rs_glass_workshop"),
  poll = function(_, memo)
    local M = loaded("src.ui.game3.rs.glass_workshop")
    local st = M and upvalue(M.draw, "state")
    if type(st) ~= "table" or st.cursor == memo.cursor then return nil end
    local first = memo.cursor == nil
    memo.cursor = st.cursor
    return join({ say(st.labels[st.cursor + 1]), position(st.cursor + 1, #st.labels) }), not first
  end,
}

-- rs/daycare_party.lua: the rows over the party screen, under its prompt.
local DAYCARE_ACTIONS = { store = "OtherText_Store", summary = "OtherText_Summary", exit = "gOtherText_Exit" }

Field.rsDaycareParty = {
  matches = Common.matcher("rs_daycare_party"),
  poll = function(_, memo)
    local M = loaded("src.ui.game3.rs.daycare_party")
    if not (M and M.open and M.actions) or M.cursor == memo.cursor then return nil end
    local first = memo.cursor == nil
    memo.cursor = M.cursor
    local row = join({ say(H.rom(DAYCARE_ACTIONS[M.actions[M.cursor]])), position(M.cursor, #M.actions) })
    if not first then return row, true end
    local Kit = loaded("src.ui.game3.rse.scene_kit")
    local man = Kit and try(Kit.manifest, "rse/party")
    return sentences({ man and man.prompts and say(man.prompts[6]) or nil, row }), true
  end,
}

-- rs/daycare_level_menu.lua: name with gender sign, level, CANCEL.
Field.rsDaycareLevel = {
  matches = Common.matcher("rs_daycare_level"),
  poll = function(_, memo)
    local M = loaded("src.ui.game3.rs.daycare_level_menu")
    if not (M and M.open and M.rowList) or M.cursor == memo.cursor then return nil end
    local first = memo.cursor == nil
    memo.cursor = M.cursor
    local row = M.rowList[M.cursor + 1]
    if type(row) ~= "table" then return nil end
    local label = say(row.text)
    if label then label = label:gsub("%s*/%s*", " "):gsub("♂", " male"):gsub("♀", " female") end
    return join({ label, row.level and ("level " .. tostring(row.level)) or nil,
      position(M.cursor + 1, #M.rowList) }), not first
  end,
}

-- rs/cable_lobby.lua
Field.rsCableLobby = {
  matches = Common.matcher("rs_cable_lobby"),
  poll = function(_, memo)
    local M = loaded("src.ui.game3.rs.cable_lobby")
    if not (M and M.open and M.opts) then return nil end
    local rows = try(M.rows) or {}
    local title = say(try(M.opts.title)) or nil
    local parts = {}
    if not memo.opened then
      memo.opened = true
      for _, key in ipairs(M.HEADERS) do
        if H.romHas(key) then parts[#parts + 1] = say(H.rom(key)); break end
      end
    end
    if title ~= memo.title then
      memo.title = title
      parts[#parts + 1] = title
    end
    local key = tostring(M.cursor) .. ":" .. #rows
    if key ~= memo.key then
      memo.key = key
      local row = rows[M.cursor]
      if row then
        parts[#parts + 1] = join({ say(row.label), row.disabled and "not available" or nil, position(M.cursor, #rows) })
      end
    end
    local text = sentences(parts)
    if not text then return nil end
    return text, true
  end,
}

-- Two scenes with no text on screen and nothing to press: rse/cable_car.lua,
-- rse/rayquaza_scene.lua.  Their name is our words.
local function sceneOnce(label)
  return function(_, memo)
    if memo.said then return nil end
    memo.said = true
    return label, false
  end
end

Field.cableCar = { matches = Common.matcher("cable_car"), poll = sceneOnce("Cable car ride") }
Field.rayquazaScene = { matches = Common.matcher("rayquaza_scene"), poll = sceneOnce("Rayquaza scene") }

-- -------------------------------------------------------- passive windows

-- rs/link_records.lua draws over the field with no input of its own.
local function linkRecordsText(M)
  local stats = M.session and M.session.gameStats or {}
  local parts = { say(H.rom("gOtherText_BattleResults")) }
  local function num(v) return string.format("%4d", math.min(9999, math.max(0, tonumber(v) or 0))) end
  parts[#parts + 1] = say(H.rom("gOtherText_WinRecord", { stringVars = { num(stats[23]), num(stats[24]), num(stats[25]) } }))
  local slots = {}
  for i, row in pairs(M.session and M.session.linkBattleRecords or {}) do
    slots[(tonumber(row.nativeSlot) or i - 1) + 1] = row
  end
  for i = 1, 5 do
    local row = slots[i] or {}
    if (tonumber(row.wins) or 0) + (tonumber(row.losses) or 0) + (tonumber(row.draws) or 0) > 0 then
      parts[#parts + 1] = join({ say(row.name), "WIN " .. tostring(row.wins or 0), "LOSE " .. tostring(row.losses or 0),
        "DRAW " .. tostring(row.draws or 0) })
    end
  end
  return sentences(parts)
end

Top.addAmbient(function(game, proxy)
  local M = loaded("src.ui.game3.rs.link_records")
  local token = Top._edge("rs_link_records", M ~= nil and M.visible == true)
  return token and proxy(token, "rs_link_records", { mod = M, game = game }) or nil
end)

Field.rsLinkRecords = {
  matches = Common.matcher("rs_link_records"),
  poll = function(state, memo)
    if memo.said or not state.mod.session then return nil end
    memo.said = true
    return linkRecordsText(state.mod), false
  end,
}

-- rs/field_auto_scroll_message.lua: a page that scrolls by itself, with no
-- pages for Message to hold, so gen3/Top.lua sees no dialogue.
Top.addAmbient(function(game, proxy)
  local M = loaded("src.ui.game3.rs.field_auto_scroll_message")
  local on = M ~= nil and try(M.ownsFrame) == true
  local token = Top._edge("rs_auto_scroll", on)
  return token and proxy(token, "rs_auto_scroll", { mod = M, game = game }) or nil
end)

Field.rsAutoScroll = {
  matches = Common.matcher("rs_auto_scroll"),
  poll = function(state, memo)
    local value = try(state.mod.text)
    if value == memo.text then return nil end
    memo.text = value
    return say(value), false
  end,
}

Field.ordered = {
  Field.decoration, Field.mail, Field.rsMail, Field.mailbox,
  Field.composer, Field.easyChatEditor, Field.trendyPhrase,
  Field.roulette, Field.rouletteEntry, Field.slots, Field.moveRelearner, Field.credits,
  Field.rsDiploma, Field.glassWorkshop, Field.rsDaycareParty, Field.rsDaycareLevel, Field.rsCableLobby,
  Field.cableCar, Field.rayquazaScene, Field.rsLinkRecords, Field.rsAutoScroll,
}

return Field
