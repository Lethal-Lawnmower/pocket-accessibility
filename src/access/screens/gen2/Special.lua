-- Gen 2 presenters for the minigames and special screens (decision 27):
-- Card Flip, slots, the Unown puzzle and stamp viewer, the Bug-Catching
-- Contest switch, the Battle Tower level picker, Buena's password and prizes,
-- the Day-Care, decorations, mail, the photo card, the Magnet Train, NPC
-- trades and their animation, the Hall of Fame, diploma, credits, the Ruins
-- of Alph wall words, the Union Room list and prep screens, and the online
-- arena's launcher.  Same matches/poll contract as Presenters.lua.
--
-- Every presenter reads the screen's own fields and pure functions (cited per
-- presenter) and builds speech only when a compared field changes.  Nothing
-- here calls a method that can change game state: Mail.lines and
-- Mail.mailbox are avoided on purpose (one fires the mail.read mod event, the
-- other re-arms it), and Decorations.state is never called (it creates the
-- save's decoration record).
--
-- Agent recommendations used as defaults until the owner decides
-- (docs/access/decisions.md 27): Card Flip says only what a sighted player
-- sees (squares, payouts, the cards already played, never odds); the Unown
-- puzzle names pieces by number and never says whether a placement is right;
-- the wall words are said as the word and then spelled.

local Common = require("src.access.screens.gen2.Common")

local Special = {}

local say = Common.speakable
local position = Common.position
local gen2 = Common.matcher

-- Matches a class outside src/ui/gen2/ (the Unown wall, the Union Room prep).
local function classAt(path)
  return function(state)
    local mod = package.loaded[path]
    return mod ~= nil and getmetatable(state) == mod
  end
end

local tr = Common.tr

-- The YES / NO box every Gen 2 screen draws as Strings("YES") / Strings("NO").
local function yesNo(yes)
  return say(tr(yes and "YES" or "NO"))
end

-- A read-only method through pcall; nil when it is missing or raises.
local function call(state, method, ...)
  local fn = state and state[method]
  if type(fn) ~= "function" then return nil end
  local ok, result = pcall(fn, state, ...)
  if not ok then return nil end
  return result
end

local function speciesName(game, id)
  local data = game and game.data
  local def = id and data and data.pokemon and data.pokemon[id]
  return def and def.name or nil
end

local function core(path)
  local mod = package.loaded[path]
  if mod then return mod end
  local ok, loaded = pcall(require, path)
  return ok and loaded or nil
end

-- Non-empty parts joined as sentences.  A part that already ends a sentence
-- ("Switch POKéMON?", "Darn…") is followed by a plain space, not ". ".
local function join(parts, sep)
  sep = sep or ". "
  local out = ""
  for i = 1, table.maxn(parts) do
    local part = parts[i] ~= nil and tostring(parts[i]) or ""
    if part ~= "" then
      if out == "" then
        out = part
      elseif sep == ". " and (out:find("[%.!%?]$") or out:find("\xe2\x80\xa6$")) then
        out = out .. " " .. part
      else
        out = out .. sep .. part
      end
    end
  end
  return out
end

-- A few screens keep the labels they draw in file-local tables (the
-- decoration side picker's SIDES, the diploma's CERTIFICATION lines, the slot
-- bet rows).  Copying those tables here is how the old project came to name
-- the wrong decoration side, so they are read out of the screen's own
-- functions with debug.getupvalue instead: read-only, looked up once per
-- class, and nil (so the label stays silent) if upstream renames them.
local upvalueCache = setmetatable({}, { __mode = "k" })
local function screenLocal(class, name)
  if type(class) ~= "table" then return nil end
  local byClass = upvalueCache[class]
  if not byClass then
    byClass = {}
    upvalueCache[class] = byClass
  end
  local hit = byClass[name]
  if hit ~= nil then return hit or nil end
  local found = false
  if debug and debug.getupvalue then
    for _, fn in pairs(class) do
      if type(fn) == "function" then
        for i = 1, 255 do
          local upName, value = debug.getupvalue(fn, i)
          if upName == nil then break end
          if upName == name then
            found = value
            break
          end
        end
      end
      if found then break end
    end
  end
  byClass[name] = found
  return found or nil
end

-- ------------------------------------------------- message box conversations

-- A page's lines as one sentence.  A `cont` in cart text shows as a new page
-- whose first line repeats the previous page's last line
-- (src/core/gen2/CommonText.lua, TradeMenu.paginate's `scrolled`); inside one
-- message that line is dropped so it is not said twice.
local function pageText(lines, memo, record)
  if type(lines) ~= "table" then lines = { lines } end
  local first = 1
  if record ~= nil and record == memo.pageRecord and #lines > 1
      and lines[1] == memo.lastLine then
    first = 2
  end
  memo.pageRecord = record
  memo.lastLine = lines[#lines]
  local rest = {}
  for i = first, #lines do rest[#rest + 1] = lines[i] end
  local text = Common.lines(rest)
  if text == "" then return nil end
  return text
end

-- The typed page (src/ui/gen2/Typer.lua): typer.page is the page after
-- substitution, a new table for each page.  Spoken whole once typing has
-- begun, not before: the Day-Care holds its last page untyped through the
-- two-second egg jingle.
local function typerPage(state, memo, record)
  local typer = state.typer
  local page = typer and typer.page
  if type(page) ~= "table" or page == memo.typerPage then return nil end
  if (tonumber(typer.shown) or 0) <= 0 and (tonumber(typer.total) or 0) > 0 then
    return nil
  end
  memo.typerPage = page
  return pageText(page, memo, record)
end

local function typedOut(state)
  local typer = state.typer
  if not typer then return true end
  return (tonumber(typer.shown) or 0) >= (tonumber(typer.total) or 0)
end

-- The speech box records several screens keep for themselves (DayCareMenu,
-- TradeMenu, MailMenu, MailboxMenu): `message` or `confirm`, each
-- { pages, page[, choice] }, drawn message first.  With a typer the page
-- comes from it; without one the record's own page is drawn as it stands.
-- YES/NO shows on a confirm's last page once it is typed out (DayCareMenu
-- :yesNoVisible); its first appearance queues behind the question, like the
-- Gen 1 ChoiceBox.  Returns text, interrupt or nil.
local function conversation(state, memo)
  local record = state.message or state.confirm
  if type(record) ~= "table" then
    memo.choiceRecord = nil
    return nil
  end
  local text
  if state.typer then
    text = typerPage(state, memo, record)
  elseif record ~= memo.plainRecord or record.page ~= memo.plainPage then
    memo.plainRecord, memo.plainPage = record, record.page
    local lines = record.pages and record.pages[record.page or 1]
    if lines then text = pageText(lines, memo, record) end
  end
  local confirm = (record == state.confirm) and record or nil
  local pages = confirm and confirm.pages
  if confirm and type(pages) == "table" and (confirm.page or 1) >= #pages
      and typedOut(state) then
    local first = memo.choiceRecord ~= confirm
    if first or memo.choice ~= confirm.choice then
      memo.choiceRecord, memo.choice = confirm, confirm.choice
      local label = yesNo(confirm.choice == 1)
      if text then return text .. " " .. label, true end
      return label, not first
    end
  end
  if text then return text, true end
  return nil
end

-- -------------------------------------------------------------- Card Flip

-- CardFlip's private localizedLines (src/ui/gen2/CardFlip.lua): the
-- translated `source` split at line breaks, else the English lines.
local function cardFlipText(lines)
  if type(lines) ~= "table" then return nil end
  if lines.source then
    local translated = tr(lines.source)
    if translated ~= lines.source then return say(translated) end
  end
  local text = Common.lines(lines)
  return text ~= "" and text or nil
end

-- A card as the face-up card shows it: the Pokemon's picture and the level
-- digit, which the board numbers 1-6 (CardFlip:drawBoard prints y - 1 for
-- level rows 2-7, so level index 0 is "1").
local function cardName(CF, card)
  if type(card) ~= "number" or not CF.MONS then return nil end
  local mon = CF.MONS[CF.mon(card)]
  if not mon then return nil end
  return say(mon) .. " level " .. tostring(CF.level(card) + 1)
end

-- A board square in words, from the screen's own payout rule: the cards
-- CardFlip.payout pays on for this square, grouped the way the board labels
-- them (a Pokemon column, a level row, one card).  "played" marks a card cell
-- the board has blanked (CardFlip:drawBoard's discard covers); nothing is
-- said about odds.
local function squareText(CF, state)
  local x, y = state.cursorX, state.cursorY
  if not (CF.cell and CF.payout and CF.cell(x, y)) then return nil end
  local cards, mons, levels = {}, {}, {}
  local monCount, levelCount = 0, 0
  for card = 0, (CF.DECK_SIZE or 24) - 1 do
    if CF.payout(x, y, card) > 0 then
      cards[#cards + 1] = card
      local m, l = CF.mon(card), CF.level(card)
      if not mons[m] then mons[m] = true monCount = monCount + 1 end
      if not levels[l] then levels[l] = true levelCount = levelCount + 1 end
    end
  end
  if #cards == 0 then return "Corner, pays nothing" end
  local text
  local played = #cards == 1 and state.discarded and state.discarded[cards[1]]
  if #cards == 1 then
    text = cardName(CF, cards[1])
  elseif levelCount == (CF.NUM_LEVELS or 6) then
    local names = {}
    for m = 0, (CF.NUM_MONS or 4) - 1 do
      if mons[m] then names[#names + 1] = say(CF.MONS[m]) end
    end
    text = table.concat(names, " or ")
  elseif monCount == (CF.NUM_MONS or 4) then
    local numbers = {}
    for l = 0, (CF.NUM_LEVELS or 6) - 1 do
      if levels[l] then numbers[#numbers + 1] = tostring(l + 1) end
    end
    text = "level " .. table.concat(numbers, " or ")
  else
    local names = {}
    for _, card in ipairs(cards) do names[#names + 1] = cardName(CF, card) end
    text = table.concat(names, " or ")
  end
  text = text .. ", pays " .. tostring(CF.payout(x, y, cards[1]))
  if played then text = text .. ", played" end
  return text
end

-- The cards this deck has already turned over, which the board blanks out.
local function playedText(CF, state)
  local names = {}
  for card = 0, (CF.DECK_SIZE or 24) - 1 do
    if state.discarded and state.discarded[card] then names[#names + 1] = cardName(CF, card) end
  end
  if #names == 0 then return nil end
  return "Played: " .. table.concat(names, ", ")
end

local function coinsText(state)
  local coins = call(state, "coins")
  return coins and ("Coins " .. tostring(coins)) or nil
end

-- Card Flip (src/ui/gen2/CardFlip.lua).  Fields: phase, lines (CardFlip.TEXTS),
-- choice, played (hand light 0-11), cursorX/cursorY, faceUp, discarded;
-- pure CardFlip.cell, payout, mon, level, MONS; read-only coins().
-- The two face-down cards alternate by themselves; both are unknown, so the
-- lit one (`which`) is not spoken.
Special.cardFlip = {
  matches = gen2("CardFlip"),
  poll = function(state, memo, entering)
    local CF = getmetatable(state)
    local phase = state.phase
    -- one message can follow another without a phase change ("The cards
    -- shuffled." then "Not enough coins."), so the message table counts too
    local newMessage = phase == "message" and state.lines ~= memo.lines
    if entering or phase ~= memo.phase or newMessage then
      local previous = memo.phase
      memo.phase, memo.choice, memo.lines = phase, state.choice, state.lines
      memo.cx, memo.cy = state.cursorX, state.cursorY
      local message = cardFlipText(state.lines)
      local text
      if phase == "ask" then
        text = join({ coinsText(state), message }) .. " " .. yesNo(state.choice == 1)
      elseif phase == "again" then
        text = (message or "") .. " " .. yesNo(state.choice == 1)
      elseif phase == "message" then
        text = message
      elseif phase == "choose" then
        local hand = string.format("Hand %d of %d", (state.played or 0) + 1,
          CF.HANDS_PER_DECK or 12)
        text = join({ coinsText(state), hand, message })
      elseif phase == "bet" then
        text = join({ message, playedText(CF, state), squareText(CF, state) })
      elseif phase == "payout" then
        text = join({ cardName(CF, state.faceUp), message })
      elseif phase == "result" then
        if previous == "payout" then
          text = coinsText(state)
        else
          text = join({ cardName(CF, state.faceUp), message })
        end
      end
      if text == nil or text == "" then return nil end
      if entering and previous == nil then text = "Card flip. " .. text end
      return text, true
    end
    if (phase == "ask" or phase == "again") and state.choice ~= memo.choice then
      memo.choice = state.choice
      return yesNo(state.choice == 1), true
    end
    if phase == "bet" and (state.cursorX ~= memo.cx or state.cursorY ~= memo.cy) then
      memo.cx, memo.cy = state.cursorX, state.cursorY
      return squareText(CF, state), true
    end
    return nil
  end,
}

-- --------------------------------------------------------------- slot machine

-- The slot messages are { source, english[, args] } (SlotMachine.TEXTS,
-- linedUpLines), translated the way its private localizedLines does.
local function slotMessage(SM, state, message)
  if type(message) ~= "table" then return nil end
  local text
  if message.source then
    if message.args then
      text = tr(message.source, unpack(message.args))
    else
      text = tr(message.source)
    end
  else
    text = table.concat(message, "\n")
  end
  -- "    lined up!": the matched symbol is drawn as a picture over the
  -- leading spaces (SlotMachine:drawMessage, PAYOUT_SYMBOL_X), so its name
  -- is said there.
  local matched = state.matched
  if state.phase == "payoutText" and matched ~= nil and matched ~= SM.NO_MATCH
      and SM.NAMES and SM.NAMES[matched] and text:find("^%s") then
    text = SM.NAMES[matched] .. " " .. text:gsub("^%s+", "")
  end
  text = say(text)
  return text ~= "" and text or nil
end

-- What a bet buys: SlotMachine.LINES[bet] lists { reel1, reel2, reel3 }
-- window indexes, 1 = bottom, 2 = middle, 3 = top (SlotMachine.window's
-- order).  The lights showing this are pictures only.
local ROW_WORDS = { "bottom row", "middle row", "top row" }
local function betLines(SM, bet)
  local lines = SM.LINES and SM.LINES[bet]
  if type(lines) ~= "table" or #lines == 0 then return nil end
  local rows, diagonals, rowName = 0, 0, nil
  for _, line in ipairs(lines) do
    if line[1] == line[2] and line[2] == line[3] then
      rows = rows + 1
      rowName = ROW_WORDS[line[1]]
    else
      diagonals = diagonals + 1
    end
  end
  if rows == 1 and diagonals == 0 then return rowName end
  local parts = {}
  if rows > 0 then parts[#parts + 1] = string.format("%d %s", rows, rows == 1 and "row" or "rows") end
  if diagonals > 0 then
    parts[#parts + 1] = string.format("%d %s", diagonals, diagonals == 1 and "diagonal" or "diagonals")
  end
  return table.concat(parts, " and ")
end

-- The bet row under the cursor: the screen's own BET_ROWS label (" 3"),
-- which is the coins bet (SlotMachine:updateBet's `bet = 4 - betIndex`).
local function betText(SM, state)
  local rows = screenLocal(SM, "BET_ROWS")
  local label = rows and rows[state.betIndex]
  local bet = label and tonumber((tostring(label):gsub("%s", "")))
  if not bet then return nil end
  return join({ string.format("%d %s", bet, bet == 1 and "coin" or "coins"), betLines(SM, bet) }, ", ")
end

local function reelText(SM, index, window)
  if type(window) ~= "table" or not SM.NAMES then return nil end
  local function name(symbol) return say(SM.NAMES[symbol] or "?") end
  -- window is bottom, middle, top; read top to bottom as it is seen
  return string.format("Reel %d: top %s, middle %s, bottom %s", index,
    name(window[3]), name(window[2]), name(window[1]))
end

-- The reel 3 near-miss shows and the reel 2 pause: pictures and sound
-- effects only on the cart.
local function slotTells(SM, state, memo)
  local parts = {}
  local paused = state.reel2Pause ~= nil
  if paused and not memo.paused then parts[#parts + 1] = "Reel 2 pauses" end
  memo.paused = paused
  local slow = state.reel3Action == (SM.REEL3_SLOW or "slowAdvance")
  if slow and not memo.slow then parts[#parts + 1] = "Reel 3 slows down" end
  memo.slow = slow
  -- SlotMachine:pressStop builds golemAnim (count) and chanseyAnim; update
  -- walks their `state` fields.  The species names come from the game data.
  local golem = state.golemAnim
  local golemName = say(speciesName(state.game, "GOLEM") or "GOLEM")
  if golem ~= memo.golem then
    memo.golem, memo.golemCount = golem, golem and golem.count
    if golem then parts[#parts + 1] = golemName .. " drops onto reel 3" end
  elseif golem and golem.count ~= memo.golemCount then
    memo.golemCount = golem.count
    if golem.state == "falling" then parts[#parts + 1] = "Another " .. golemName .. " drops" end
  end
  local chansey = state.chanseyAnim
  local chanseyName = say(speciesName(state.game, "CHANSEY") or "CHANSEY")
  if chansey ~= memo.chansey then
    memo.chansey, memo.egg = chansey, false
    if chansey then parts[#parts + 1] = chanseyName .. " walks up to reel 3" end
  end
  if chansey and chansey.state == "egg_drop" and not memo.egg then
    memo.egg = true
    parts[#parts + 1] = chanseyName .. " drops an egg"
  end
  return parts
end

-- Slot machine (src/ui/gen2/SlotMachine.lua).  Fields: phase, betIndex,
-- message, stopped[i] (bottom, middle, top), matched, againChoice,
-- reel2Pause, reel3Action, golemAnim, chanseyAnim; SlotMachine.NAMES, LINES,
-- TEXTS, NO_MATCH; the local BET_ROWS; read-only coins().  The spinning
-- positions pass about 15 symbols a second and are never spoken; each reel
-- is read once it has stopped.
Special.slotMachine = {
  matches = gen2("SlotMachine"),
  poll = function(state, memo, entering)
    local SM = getmetatable(state)
    local phase = state.phase
    if phase == "quit" then return nil end
    local newPhase = entering or phase ~= memo.phase
    local first = memo.phase == nil
    memo.phase = phase

    if phase == "bet" then
      if newPhase then
        memo.bet, memo.message = state.betIndex, state.message
        local prompt = slotMessage(SM, state, SM.TEXTS and SM.TEXTS.betHowMany)
        local row = betText(SM, state)
        local rows = screenLocal(SM, "BET_ROWS") or {}
        local text = join({ coinsText(state), prompt,
          row and (row .. ", " .. position(state.betIndex, #rows)) })
        if first then text = "Slot machine. " .. text end
        return text, true
      end
      if state.message ~= memo.message then
        memo.message = state.message
        if state.message then return slotMessage(SM, state, state.message), true end
        return betText(SM, state), true
      end
      if state.betIndex ~= memo.bet then
        memo.bet = state.betIndex
        return betText(SM, state), true
      end
      return nil
    end

    if phase == "again" then
      if newPhase then
        memo.again, memo.message = state.againChoice, state.message
        local prompt = slotMessage(SM, state, SM.TEXTS and SM.TEXTS.playAgain)
        return join({ coinsText(state), prompt }) .. " " .. yesNo(state.againChoice == 1), false
      end
      if state.againChoice ~= memo.again then
        memo.again = state.againChoice
        return yesNo(state.againChoice == 1), true
      end
      return nil
    end

    -- spinning, flash, payoutText, ranOut: the start message, each reel as it
    -- stops, the tells, then the result.  Queued, so a quick A on the next
    -- reel does not cut off the one before; "Start!" interrupts the bet menu.
    local parts, interrupt = {}, false
    local message = state.message
    local newMessage = message ~= memo.message
    memo.message = message
    local start = SM.TEXTS and SM.TEXTS.start
    if newMessage and message ~= nil and message == start then
      interrupt = true
      parts[#parts + 1] = slotMessage(SM, state, message)
    end
    local stopped = state.stopped
    if stopped ~= memo.stoppedTable then memo.stoppedTable, memo.stoppedCount = stopped, 0 end
    if type(stopped) == "table" then
      for i = (memo.stoppedCount or 0) + 1, 3 do
        if not stopped[i] then break end
        parts[#parts + 1] = reelText(SM, i, stopped[i])
        memo.stoppedCount = i
      end
    end
    for _, tell in ipairs(slotTells(SM, state, memo)) do parts[#parts + 1] = tell end
    if newMessage and message ~= nil and message ~= start then
      parts[#parts + 1] = slotMessage(SM, state, message)
    end
    if #parts == 0 then return nil end
    return join(parts), interrupt
  end,
}

-- ------------------------------------------------------------- Unown puzzle

-- The picture's name: UnownPuzzle's `puzzle` id indexes Unown.PUZZLES
-- (src/core/gen2/Unown.lua), whose ids are species; the species' own name is
-- said.  No name is said when the data cannot answer.
local function puzzlePicture(state)
  local Unown = core("src.core.gen2.Unown")
  local row = Unown and Unown.PUZZLES and Unown.PUZZLES[state.puzzle or 0]
  return row and speciesName(state.game, row.id) or nil
end

-- One cell as the board shows it: its piece (pieces carry their number, and
-- the art-less board draws it, UnownPuzzle drawing fallback) or empty, then
-- the row and column of the 6 by 6 board.  Nothing says where a piece
-- belongs.
local function puzzleCell(UP, state)
  local cursor = state.cursor or 0
  local columns = UP.COLUMNS or 6
  local piece = state.pieces and state.pieces[cursor + 1] or 0
  local content = piece ~= 0 and ("piece " .. tostring(piece)) or "empty"
  return string.format("%s, row %d, column %d", content,
    math.floor(cursor / columns) + 1, cursor % columns + 1)
end

-- Unown puzzle (src/ui/gen2/UnownPuzzle.lua).  Fields: pieces (36 cells,
-- 0 empty or a piece 1-16), cursor 0-35, holding, held, solved, waiting,
-- closed, puzzle; UnownPuzzle.COLUMNS.  A refused move or press changes no
-- field and stays silent (the game plays its own wrong-move sound for A).
Special.unownPuzzle = {
  matches = gen2("UnownPuzzle"),
  poll = function(state, memo, entering)
    local UP = getmetatable(state)
    if state.closed then return nil end
    if state.solved then
      if memo.solved then return nil end
      memo.solved = true
      return "Puzzle complete. Press A.", true
    end
    local occupant = state.pieces and state.pieces[(state.cursor or 0) + 1]
    if not entering and state.cursor == memo.cursor and state.holding == memo.holding
        and occupant == memo.occupant then
      return nil
    end
    local text
    if entering then
      local picture = puzzlePicture(state)
      text = "Unown puzzle" .. (picture and (", " .. say(picture)) or "")
        .. ". A picks up or puts down a piece, START quits. " .. puzzleCell(UP, state)
      if state.holding then text = text .. ". Holding piece " .. tostring(state.held) end
    elseif state.holding ~= memo.holding then
      text = state.holding and ("Took piece " .. tostring(state.held))
        or ("Placed piece " .. tostring(memo.held or occupant))
    else
      text = puzzleCell(UP, state)
    end
    memo.cursor, memo.holding, memo.held, memo.occupant = state.cursor, state.holding, state.held, occupant
    return text, true
  end,
}

-- --------------------------------------------------------- Alph Ruins stamp

-- The ALPH RUINS STAMP viewer (src/ui/gen2/UnownPrinter.lua).  Fields:
-- index; read-only letter() and slots(); the local TEXT (title, VACANT).
-- The letter is shown only as an Unown picture.  The on-screen legend says
-- L and R, but the screen reads the d-pad's left and right, and A has no
-- printer to print on.
local function stampText(state)
  local letter = call(state, "letter")
  if letter == nil then
    local text = screenLocal(getmetatable(state), "TEXT")
    return text and text.vacant and say(tr(text.vacant)) or nil
  end
  local Unown = core("src.core.gen2.Unown")
  local char = Unown and Unown.name and Unown.name(letter)
  if not char then return nil end
  return say(speciesName(state.game, Unown.SPECIES) or "UNOWN") .. " " .. char
end

Special.unownPrinter = {
  matches = gen2("UnownPrinter"),
  poll = function(state, memo, entering)
    if state.done then return nil end
    if not entering and memo.index == state.index then return nil end
    memo.index = state.index
    local row = stampText(state)
    if not row then return nil end
    local count = call(state, "slots") or 0
    if entering then
      local text = screenLocal(getmetatable(state), "TEXT")
      local title = text and text.title and say(tr(text.title))
      return join({ title, row .. ", " .. position((state.index or 0) + 1, count),
        "Left and right to browse, B to leave" }), true
    end
    return row, true
  end,
}

-- ------------------------------------------------- Bug-Catching Contest switch

-- ContestMenu (src/ui/gen2/ContestMenu.lua).  Fields: stock, caught, choice;
-- labels() and TEXT.health / askSwitch, all as drawPanel prints them
-- (name is nickname, name or species; HEALTH is the maximum HP).
local function contestBox(label, mon, health)
  if type(mon) ~= "table" then return nil end
  local name = mon.nickname or mon.name or mon.species or "?"
  local hp = mon.maxHp or (mon.stats and mon.stats.hp) or 0
  return string.format("%s: %s, level %s, %s %s", say(tr(label)), say(name),
    tostring(mon.level or 1), say(tr(health)), tostring(hp))
end

Special.contestMenu = {
  matches = gen2("ContestMenu"),
  poll = function(state, memo, entering)
    local CM = getmetatable(state)
    if not entering and memo.choice == state.choice then return nil end
    memo.choice = state.choice
    if not entering then return yesNo(state.choice == 1), true end
    local ok, stockLabel, thisLabel = pcall(CM.labels)
    if not ok then return nil end
    local text = CM.TEXT or {}
    return join({ say(tr(text.askSwitch)), contestBox(stockLabel, state.stock, text.health),
      contestBox(thisLabel, state.caught, text.health) }) .. ". " .. yesNo(state.choice == 1), true
  end,
}

-- ------------------------------------------------------ Battle Tower levels

-- BattleTowerMenu (src/ui/gen2/BattleTowerMenu.lua, Crystal).  Fields:
-- phase pick / message / quit, message (a string), cursor, rows[i].group,
-- yes; levelLabel(group) and rowCount().  UP raises the level, which is said
-- once because a list usually moves forward with DOWN.  A refusal clears
-- itself after 128 frames, so the picker that follows it is queued.
local function towerRow(BT, state)
  local row = state.rows and state.rows[state.cursor]
  if not row then return say(tr("CANCEL")) end
  local ok, label = pcall(BT.levelLabel, row.group)
  if not ok then return nil end
  return say((tostring(label):gsub("L:%s*(%d+)", "level %1")))
end

Special.battleTowerMenu = {
  matches = gen2("BattleTowerMenu"),
  poll = function(state, memo, entering)
    local BT = getmetatable(state)
    if state.done then return nil end
    local phase = state.phase
    local newPhase = entering or phase ~= memo.phase
    local previous = memo.phase
    memo.phase = phase
    if phase == "message" then
      if newPhase or state.message ~= memo.message then
        memo.message = state.message
        return say(state.message), true
      end
      return nil
    end
    if phase == "quit" then
      if newPhase then
        memo.yes = state.yes
        return say(state.message) .. " " .. yesNo(state.yes), true
      end
      if state.yes ~= memo.yes then
        memo.yes = state.yes
        return yesNo(state.yes), true
      end
      return nil
    end
    if not newPhase and state.cursor == memo.cursor then return nil end
    memo.cursor = state.cursor
    local row = towerRow(BT, state)
    if not row then return nil end
    if not newPhase then return row, true end
    local text = join({ say(state.message), row .. ", "
      .. position(state.cursor or 1, call(state, "rowCount") or 1) })
    if not memo.hinted then
      memo.hinted = true
      text = text .. ". Up raises the level"
    end
    return text, previous ~= "message"
  end,
}

-- ------------------------------------------------------ Buena (Crystal)

-- BuenaPassword (src/ui/gen2/BuenaPassword.lua): two modes.  Fields: mode,
-- words, prizes[i] { name, cost }, balance, index; count().  A prize row
-- shows its cost as one digit (drawPrizePanel's `cost % 10`); the Points box
-- shows the Blue Card balance.
local function buenaRow(state)
  if state.mode == "prize" then
    local prize = state.prizes and state.prizes[state.index]
    if not prize then return nil end
    local cost = (tonumber(prize.cost) or 0) % 10
    return string.format("%s, %d %s", say(prize.name), cost, cost == 1 and "point" or "points")
  end
  local word = state.words and state.words[state.index]
  return word and say(word) or nil
end

Special.buenaPassword = {
  matches = gen2("BuenaPassword"),
  poll = function(state, memo, entering)
    if state.done then return nil end
    if not entering and memo.index == state.index then return nil end
    memo.index = state.index
    local row = buenaRow(state)
    if not row then return nil end
    if not entering then return row, true end
    local text = row .. ", " .. position(state.index or 1, call(state, "count") or 0)
    if state.mode == "prize" then
      local label = screenLocal(getmetatable(state), "POINTS_LABEL") or "Points"
      text = say(tr(label)) .. " " .. tostring(state.balance or 0) .. ". " .. text
    end
    return text, true
  end,
}

-- ------------------------------------------------------ Day-Care, NPC trade

-- DayCareMenu (src/ui/gen2/DayCareMenu.lua) and TradeMenu
-- (src/ui/gen2/TradeMenu.lua) are speech boxes with YES/NO and a party list
-- pushed on top (`picking`, `animating`), so they are the conversation alone.
local function conversationPresenter(name)
  return {
    matches = gen2(name),
    poll = function(state, memo)
      return conversation(state, memo)
    end,
  }
end

Special.dayCareMenu = conversationPresenter("DayCareMenu")
Special.tradeMenu = conversationPresenter("TradeMenu")

-- ------------------------------------------------------------ decorations

local function decorations() return package.loaded["src.core.gen2.Decorations"] end

-- What is set up in the room, which shows only on the map after the PC
-- reloads it.  Read from the screen's own copy of the placed slots
-- (DecorationMenu.state; Decorations.SLOTS order); an ornament slot is named
-- by the side picker's own label, matched the way Decorations.apply maps a
-- side to its slot.
local function roomText(state)
  local D = decorations()
  local placed = state.state
  if not (D and D.SLOTS and type(placed) == "table") then return nil end
  local sides = screenLocal(getmetatable(state), "SIDES")
  local names = {}
  for _, slot in ipairs(D.SLOTS) do
    local id = placed[slot]
    if id and id ~= 0 then
      local name = say(D.name(id))
      local side = tostring(slot):match("^(%l+)Ornament$")
      for _, entry in ipairs(sides or {}) do
        if side and entry.id == side then name = name .. ", " .. say(tr(entry.label)) end
      end
      if name ~= "" then names[#names + 1] = name end
    end
  end
  if #names == 0 then return "Nothing set up" end
  return "Set up: " .. table.concat(names, "; ")
end

-- The row under the cursor in the current mode, the list's length, and the
-- context said when the mode changes (DecorationMenu:drawPanel's labels).
local function decorationRow(state)
  local mode = state.mode
  if mode == "side" then
    local sides = screenLocal(getmetatable(state), "SIDES")
    local entry = sides and sides[state.sideIndex]
    if not entry then return nil end
    return say(tr(entry.label)), #sides, say(call(state, "rowName", state.pendingDeco) or "")
  elseif mode == "items" then
    local rows = state.rows or {}
    local id = rows[state.index]
    if id == nil then return nil end
    return say(call(state, "rowName", id) or ""), #rows,
      state.category and say(state.category.label) or nil
  end
  local categories = state.categories or {}
  local category = categories[state.index]
  local label
  if category then
    label = say(category.label)
  else
    local exit = screenLocal(getmetatable(state), "EXIT")
    label = exit and say(tr(exit)) or nil
  end
  if not label then return nil end
  return label, #categories + 1, "Decoration"
end

-- DecorationMenu (src/ui/gen2/DecorationMenu.lua).  Fields: mode,
-- index, sideIndex, categories[i].label, rows (decoration ids), category,
-- pendingDeco, pages/typer (messages over the list), state (placed slots);
-- read-only rowName(id); the locals SIDES and EXIT.
Special.decorationMenu = {
  matches = gen2("DecorationMenu"),
  poll = function(state, memo, entering)
    if state.done then return nil end
    if state.pages then
      memo.inMessage = true
      local text = typerPage(state, memo, state.pages)
      if text then return text, true end
      return nil
    end
    local back = memo.inMessage
    memo.inMessage = false
    local mode = state.mode
    local index = mode == "side" and state.sideIndex or state.index
    local changed = entering or back or mode ~= memo.mode
    if not changed and index == memo.index then return nil end
    local firstEntry = memo.mode == nil
    memo.mode, memo.index = mode, index
    local row, count, context = decorationRow(state)
    if not row then return nil end
    if not changed then return row, true end
    local text = row .. ", " .. position(index or 1, count or 1)
    if mode ~= memo.lastContextMode or firstEntry or entering then
      local room = (firstEntry and mode == "category") and roomText(state) or nil
      text = join({ context, room, text })
    end
    memo.lastContextMode = mode
    return text, true
  end,
}

-- --------------------------------------------------------------------- mail

-- Mail glyphs a screen reader would skip or misread, spelled out.  Letters
-- and digits are read as they are.  (The naming keyboard's cells: the
-- MailCompose grids, MAIL_INPUT_UPPER / LOWER.)
local GLYPHS = {
  [" "] = "space", [","] = "comma", ["?"] = "question mark", ["!"] = "exclamation mark",
  ["."] = "period", ["-"] = "dash", ["/"] = "slash", ["&"] = "and sign",
  ["("] = "left parenthesis", [")"] = "right parenthesis", ["["] = "left bracket",
  ["]"] = "right bracket", ["'"] = "apostrophe", [":"] = "colon", [";"] = "semicolon",
  ["\xe2\x80\x9c"] = "open quote", ["\xe2\x80\x9d"] = "close quote",
  ["<PK>"] = "PK", ["<MN>"] = "MN", ["<PO>"] = "PO", ["<KE>"] = "KE",
  ["\xc3\xa9"] = "accented e", ["\xe2\x99\x82"] = "male", ["\xe2\x99\x80"] = "female",
  ["\xc2\xa5"] = "yen", ["\xe2\x80\xa6"] = "ellipsis", ["\xc3\x97"] = "times",
  ["DEL"] = "DEL, delete",
}
local function glyphName(glyph)
  if glyph == nil then return "blank" end
  local named = GLYPHS[glyph]
  if named then return named end
  local letter = tostring(glyph):match("^'(%l)$")
  if letter then return "apostrophe " .. letter end
  return say(glyph)
end

-- Typed mail text: the POKé glyph pair and lone PO / KE made readable, then
-- the shared Gen 2 cleanup (PK, MN, line breaks).
local function mailText(text)
  text = tostring(text or "")
  text = text:gsub("<PO><KE>", "POKé"):gsub("<PO>", "PO"):gsub("<KE>", "KE")
  return say(text)
end

-- The cell under the MailCompose cursor: a grid glyph, or on the bottom
-- strip the label drawPanel prints there (the case switch shows the case it
-- switches TO).  Grid and strip come from the screen's own rows(),
-- characterAt(), onBottomRow(), bottomTarget() and its local label tables.
local function composeCell(state)
  local MC = getmetatable(state)
  if call(state, "onBottomRow") then
    local target = call(state, "bottomTarget")
    local labels = screenLocal(MC, state.lower and "BOTTOM_UPPER_LABELS" or "BOTTOM_LABELS")
    local label = labels and target and labels[target]
    if label then return glyphName(say(tr(label))) end
    return say(call(state, "cursorCharacter") or "")
  end
  return glyphName(call(state, "characterAt", state.col, state.row))
end

-- MailCompose (src/ui/gen2/MailCompose.lua): the naming-style keyboard for a
-- letter.  Fields: row, col, lower, text; read-only length() (what the
-- screen counts to place the second line); Mail.MAIL_LINE_LENGTH.  Like the
-- Gen 1 naming presenter: the cell on a move, the typed glyph and the text
-- on a keypress, "deleted" on B or DEL, the case on SELECT.  The typed glyph
-- is what was appended to `text` (a key adds one whole grid cell, such as
-- "<PK>"); Mail.characters splits "<PK>" into four bytes, so it is not used
-- to find it.
Special.mailCompose = {
  matches = gen2("MailCompose"),
  poll = function(state, memo, entering)
    local text = tostring(state.text or "")
    if not entering and memo.row == state.row and memo.col == state.col
        and memo.lower == state.lower and memo.text == text then
      return nil
    end
    local previous = memo.text or ""
    local count = call(state, "length") or 0
    local typed = mailText(text)
    local out
    if entering then
      out = "Write mail. " .. (typed ~= "" and typed or "empty") .. ". " .. composeCell(state)
    elseif #text > #previous and text:sub(1, #previous) == previous then
      out = glyphName(text:sub(#previous + 1))
      local Mail = package.loaded["src.core.gen2.Mail"]
      local lineLength = Mail and Mail.MAIL_LINE_LENGTH or 16
      if (memo.count or 0) <= lineLength and count > lineLength then out = out .. ", line 2" end
      out = out .. ", " .. typed
    elseif #text < #previous then
      out = "deleted, " .. (typed ~= "" and typed or "empty")
    elseif text ~= previous then
      out = typed ~= "" and typed or "empty"
    elseif memo.lower ~= state.lower then
      out = (state.lower and "lower case. " or "upper case. ") .. composeCell(state)
    else
      out = composeCell(state)
    end
    memo.row, memo.col, memo.lower, memo.text, memo.count = state.row, state.col, state.lower, text, count
    return out, true
  end,
}

-- The stationery's name: entry.type is the mail item, which the port does
-- not draw at all (MailRead header), so the item's own name is said.
local function stationery(game, itemId)
  local items = game and game.data and game.data.items
  local def = itemId and items and items[itemId]
  return def and def.name or nil
end

-- MailRead (src/ui/gen2/MailRead.lua): entry { type, message, author }.
-- The message is read from the entry itself, never through Mail.lines,
-- which fires the mail.read mod event.  A blank author is not drawn.
Special.mailRead = {
  matches = gen2("MailRead"),
  poll = function(state, memo)
    if memo.said then return nil end
    memo.said = true
    local entry = state.entry
    if type(entry) ~= "table" then return nil end
    local author = tostring(entry.author or "")
    local name = stationery(state.game, entry.type)
    local message = mailText(entry.message)
    return join({ name and say(name), message ~= "" and message or "No message",
      author ~= "" and ("From " .. mailText(author)) or nil }), true
  end,
}

-- MailMenu (src/ui/gen2/MailMenu.lua): READ / TAKE / QUIT over the party
-- list (MailMenu.ENTRIES), then its own questions (message / confirm, no
-- typer).  The menu row is repeated when a question closes over it.
Special.mailMenu = {
  matches = gen2("MailMenu"),
  poll = function(state, memo, entering)
    local text, interrupt = conversation(state, memo)
    if text then
      memo.talked = true
      return text, interrupt
    end
    if state.message or state.confirm or state.reading then return nil end
    local back = memo.talked
    memo.talked = false
    if not entering and not back and memo.index == state.index then return nil end
    memo.index = state.index
    local entries = getmetatable(state).ENTRIES or {}
    local entry = entries[state.index]
    if not entry then return nil end
    local label = say(tr(entry.label))
    if entering or back then
      return "Mail. " .. label .. ", " .. position(state.index, #entries), true
    end
    return label, true
  end,
}

-- MailboxMenu (src/ui/gen2/MailboxMenu.lua): the PC's letters, each row the
-- author only (drawList), then the READ / PACK / ATTACH / CANCEL submenu
-- (MailboxMenu.SUB_ENTRIES) and the questions.  The letters are read from
-- save.mail.box directly: MailboxMenu:box() goes through Mail.mailbox, which
-- re-arms the mail.read event.
local function mailbox(state)
  local mail = state.save and state.save.mail
  return type(mail) == "table" and type(mail.box) == "table" and mail.box or {}
end

local function mailboxRow(state)
  local entry = mailbox(state)[state.index]
  if type(entry) ~= "table" then return nil end
  local author = tostring(entry.author or "")
  return author ~= "" and mailText(author) or "blank"
end

Special.mailboxMenu = {
  matches = gen2("MailboxMenu"),
  poll = function(state, memo, entering)
    local text, interrupt = conversation(state, memo)
    if text then
      memo.talked = true
      return text, interrupt
    end
    if state.message or state.confirm or state.picking then return nil end
    local back = memo.talked or entering
    memo.talked = false
    local submenu = state.submenu
    if submenu then
      local opened = memo.sub == nil
      if not back and not opened and submenu.index == memo.sub then return nil end
      memo.sub = submenu.index
      local entries = getmetatable(state).SUB_ENTRIES or {}
      local entry = entries[submenu.index]
      if not entry then return nil end
      local label = say(tr(entry.label))
      if back or opened then label = label .. ", " .. position(submenu.index, #entries) end
      return label, true
    end
    local closed = memo.sub ~= nil
    memo.sub = nil
    if not back and not closed and memo.index == state.index then return nil end
    memo.index = state.index
    local row = mailboxRow(state)
    if not row then return nil end
    local text = row
    if back or closed then text = row .. ", " .. position(state.index or 1, #mailbox(state)) end
    if entering then text = "Mailbox. " .. text end
    return text, true
  end,
}

-- --------------------------------------------------------------- photo card

-- PhotoStudio (src/ui/gen2/PhotoStudio.lua): the portrait card, read once in
-- drawPanel's order: number, level, HP (the maximum), gender, shiny,
-- nickname, species, OT, ID, first move.
Special.photoStudio = {
  matches = gen2("PhotoStudio"),
  poll = function(state, memo)
    if memo.said then return nil end
    memo.said = true
    local mon = state.mon
    if type(mon) ~= "table" then return nil end
    local def = call(state, "speciesDef") or {}
    local nickname = mon.nickname or mon.name or mon.species
    local species = def.name or mon.species
    local move = call(state, "moveName")
    return join({
      "Photo",
      join({ "Number " .. tostring(def.dex or 0), "level " .. tostring(mon.level or 1),
        "HP " .. tostring(mon.maxHp or mon.hp or 0),
        mon.gender == "male" and "male" or mon.gender == "female" and "female" or nil,
        mon.shiny and "shiny" or nil }, ", "),
      join({ say(nickname), species ~= nickname and say(species) or nil }, ", "),
      "OT " .. say(mon.ot or state.playerName or ""),
      string.format("ID %05d", tonumber(mon.otId) or 0),
      (move and move ~= "-") and ("Move " .. say(move)) or nil,
      "Press A",
    }), true
  end,
}

-- ------------------------------------------------------------ Magnet Train

-- MagnetTrainRide (src/ui/gen2/MagnetTrainRide.lua): a cutscene with no
-- text.  ride.toGoldenrod is the officer's wScriptVar: Saffron's officer
-- sets TRUE and Goldenrod's FALSE (src/core/gen2/MagnetTrain.lua, above
-- MagnetTrain.new), so the ride goes to the other city.
Special.magnetTrainRide = {
  matches = gen2("MagnetTrainRide"),
  poll = function(state, memo)
    if memo.said then return nil end
    memo.said = true
    local ride = state.ride
    if type(ride) ~= "table" then return nil end
    return ride.toGoldenrod and "Magnet Train to Goldenrod City" or "Magnet Train to Saffron City", true
  end,
}

-- --------------------------------------------------------- trade animation

-- The stats panel (TradeAnimView:drawStats): number, species, OT, ID.
local function tradePanel(record)
  if type(record) ~= "table" then return nil end
  return join({ "Number " .. tostring(record.dex or 0), say(record.name or "?"),
    "OT " .. say(record.otName or ""), string.format("ID %05d", tonumber(record.id) or 0) }, ", ")
end

-- TradeAnim (src/ui/gen2/TradeAnim.lua).  Fields: beat.id, give, get;
-- read-only lines(id) for the text beats (TradeAnim.TEXT in
-- src/core/gen2/TradeAnim.lua).  The animation runs by itself, so its lines
-- are queued; B or START skips to the end (a port addition).
Special.tradeAnim = {
  matches = gen2("TradeAnim"),
  poll = function(state, memo, entering)
    if state.done then return nil end
    local beat = state.beat
    local id = beat and beat.id
    if not entering and id == memo.beat then return nil end
    memo.beat = id
    local text
    if id == "givemon_scroll" then
      text = tradePanel(state.give)
    elseif id == "getmon_poof" then
      text = tradePanel(state.get)
    elseif id then
      local lines = call(state, "lines", id)
      if type(lines) == "table" then text = Common.lines(lines) end
    end
    if entering and memo.entered == nil then
      memo.entered = true
      return join({ "Trade. B skips", text }), true
    end
    if text == nil or text == "" then return nil end
    return text, false
  end,
}

-- ------------------------------------------------------------- Hall of Fame

-- One Hall of Famer as HallOfFame.monPlacements lays it out: number,
-- species, gender, nickname (said once when it is the species name), level,
-- ID.  An egg shows only its ID there.
local function famerText(state, mon)
  if type(mon) ~= "table" then return nil end
  local id = string.format("ID %05d", tonumber(mon.otId) or 0)
  if mon.species == "EGG" then return id end
  local pokemon = state.pokemon or (state.game and state.game.data and state.game.data.pokemon) or {}
  local def = pokemon[mon.species] or {}
  local species = def.name or mon.species
  local nickname = mon.nickname or mon.name or mon.species
  return join({ "Number " .. tostring(def.dex or 0), say(species),
    mon.gender == "male" and "male" or mon.gender == "female" and "female" or nil,
    nickname ~= species and say(nickname) or nil,
    "level " .. tostring(mon.level or 1), id }, ", ")
end

-- The glyphs of a placement string: a <TOKEN> or one UTF-8 character each.
local function glyphs(text)
  local out, i = {}, 1
  text = tostring(text or "")
  while i <= #text do
    local token = text:match("^<[%u_]+>", i)
    if token then
      out[#out + 1] = token
      i = i + #token
    else
      local b = text:byte(i)
      local width = b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
      out[#out + 1] = text:sub(i, i + width - 1)
      i = i + width
    end
  end
  return out
end

-- One screen row of a placement list, later writes over earlier ones, the
-- way the header's count is printed over the leading spaces of
-- "    -Time Famer" (HallOfFame.headerPlacements).
local function placedRow(placements, y)
  local cells, last = {}, 0
  for _, entry in ipairs(placements or {}) do
    if entry.y == y and entry.text then
      for k, glyph in ipairs(glyphs(entry.text)) do
        local x = entry.x + k - 1
        cells[x] = glyph
        if x > last then last = x end
      end
    end
  end
  local out = {}
  for x = 0, last do out[#out + 1] = cells[x] or " " end
  return say(table.concat(out))
end

local function hofHeader(HOF, state)
  local entry = state.entry
  local ok, placements = pcall(HOF.headerPlacements, state.mode,
    entry and entry.winCount, state.textData)
  if not ok or type(placements) ~= "table" or not placements[1] then return nil end
  return placedRow(placements, placements[1].y)
end

-- The player's card (HallOfFame.playerPlacements): name, ID, play time.
local function hofPlayer(state)
  local save = state.save or {}
  local player = save.player or {}
  local time = save.playTime or {}
  return join({ say(player.name or ""), string.format("ID %05d", tonumber(player.id) or 0),
    string.format("play time %d:%02d", tonumber(time.hours) or 0, tonumber(time.minutes) or 0) })
end

-- HallOfFame (src/ui/gen2/HallOfFame.lua).  Fields: mode induct / view,
-- phase, entry { winCount, mons }, index, team, done; pure
-- headerPlacements; read-only currentMon().  The induction is a cutscene:
-- each member is said when its panel is up (phase display), then the player
-- card, queued.  The PC viewer speaks each member on A, a new team on START.
Special.hallOfFame = {
  matches = gen2("HallOfFame"),
  poll = function(state, memo, entering)
    local HOF = getmetatable(state)
    if state.done then return nil end
    if state.mode == "view" then
      if state.phase ~= "display" then return nil end
      if not entering and memo.team == state.team and memo.index == state.index then return nil end
      local newTeam = entering or memo.team ~= state.team
      memo.team, memo.index = state.team, state.index
      local mons = state.entry and state.entry.mons or {}
      local text = join({ newTeam and hofHeader(HOF, state) or nil,
        famerText(state, call(state, "currentMon")) }) .. ". " .. position(state.index or 1, #mons)
      if entering and not memo.hinted then
        memo.hinted = true
        text = "Hall of Fame. " .. text .. ". A next, START next team, B leave"
      end
      return text, true
    end
    local phase = state.phase
    if phase == "display" and (memo.index ~= state.index or memo.phase ~= phase) then
      memo.phase, memo.index = phase, state.index
      local header = not memo.header and hofHeader(HOF, state) or nil
      memo.header = true
      return join({ header, famerText(state, call(state, "currentMon")) }), false
    end
    if phase == "player" and memo.phase ~= phase then
      memo.phase = phase
      return hofPlayer(state), false
    end
    if phase ~= "display" then memo.phase = phase end
    return nil
  end,
}

-- ------------------------------------------------------------------ diploma

-- Diploma (src/ui/gen2/Diploma.lua): "PLAYER", the player's name and the
-- local CERTIFICATION lines, as drawPanel prints them.
Special.diploma = {
  matches = gen2("Diploma"),
  poll = function(state, memo)
    if memo.said then return nil end
    memo.said = true
    local lines = {}
    for i, line in ipairs(screenLocal(getmetatable(state), "CERTIFICATION") or {}) do
      lines[i] = tr(line)
    end
    return join({ "Diploma", say(tr("PLAYER")) .. " " .. say(state.playerName or ""),
      #lines > 0 and Common.lines(lines) or nil, "Press A" }), true
  end,
}

-- ------------------------------------------------------------------ credits

-- Credits (src/ui/gen2/Credits.lua): `shown` is the text on screen, a list
-- of { text, x, y } or { theEnd }, replaced whole at each wait; `exiting`
-- once the roll is over and A leaves.  Queued: the roll runs by itself.
Special.credits = {
  matches = gen2("Credits"),
  poll = function(state, memo)
    if state.done then return nil end
    if state.exiting and not memo.exiting then
      memo.exiting = true
      return "Press A", false
    end
    local shown = state.shown
    if shown == memo.shown then return nil end
    memo.shown = shown
    local entries = {}
    for i, entry in ipairs(shown or {}) do entries[i] = entry end
    table.sort(entries, function(a, b)
      if (a.y or 0) ~= (b.y or 0) then return (a.y or 0) < (b.y or 0) end
      return (a.x or 0) < (b.x or 0)
    end)
    local parts = {}
    for _, entry in ipairs(entries) do
      if entry.theEnd then
        parts[#parts + 1] = "THE END"
      elseif entry.text then
        local text = say(entry.text)
        if text ~= "" then parts[#parts + 1] = text end
      end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", "), false
  end,
}

-- ------------------------------------------------- Ruins of Alph wall words

-- UnownWords (src/world/gen2/UnownWords.lua, Crystal): wall.word is the
-- decoded word the extractor stores beside the glyphs the screen draws
-- (RomExtractorGen2, unownWalls).  Said as the word, then spelled (agent
-- recommendation).  An undecodable glyph is extracted as "?".
local function spelled(word)
  local letters = {}
  for char in tostring(word):gmatch(".") do
    if char == "?" then
      letters[#letters + 1] = "unknown"
    elseif char == "-" then
      letters[#letters + 1] = "dash"
    elseif char ~= " " then
      letters[#letters + 1] = char
    end
  end
  return table.concat(letters, ", ")
end

Special.unownWords = {
  matches = classAt("src.world.gen2.UnownWords"),
  poll = function(state, memo)
    if memo.said or state.done then return nil end
    memo.said = true
    local word = state.wall and state.wall.word
    if type(word) ~= "string" or word == "" then return nil end
    return "Unown letters on the wall: " .. word .. ". " .. spelled(word) .. ". Press A.", true
  end,
}

-- -------------------------------------------------------------- Union Room

-- The Union Room list (src/ui/gen2/union/List.lua, the TRADING BOARD):
-- title, items[i] { label, right }, index.
local function unionRow(item)
  if type(item) ~= "table" then return nil end
  return join({ say(item.label), item.right and say(item.right) or nil }, ", ")
end

Special.unionList = {
  matches = gen2("union.List"),
  poll = function(state, memo, entering)
    if state.done then return nil end
    if not entering and memo.index == state.index then return nil end
    memo.index = state.index
    local items = state.items or {}
    local title = state.title and say(tr(state.title)) or nil
    if #items == 0 then return entering and join({ title, "Empty" }) or nil, true end
    local row = unionRow(items[state.index])
    if not row then return nil end
    if not entering then return row, true end
    return join({ title, row .. ", " .. position(state.index, #items) }), true
  end,
}

-- The Gen 2 battle and trade prep screens keep the same `model` / `ctl`
-- page objects as Gen 1's (src/ui/union/prep/Gen2BattlePrep.lua,
-- Gen2TradePrep.lua), so the Gen 1 presenter's reading applies unchanged.
local LinkScreens = require("src.access.screens.LinkScreens")
Special.unionBattlePrep = {
  matches = classAt("src.ui.union.prep.Gen2BattlePrep"),
  poll = LinkScreens.unionBattlePrep.poll,
}
Special.unionTradePrep = {
  matches = classAt("src.ui.union.prep.Gen2TradePrep"),
  poll = LinkScreens.unionTradePrep.poll,
}

-- The online arena's launcher (src/ui/gen2/ArenaState.lua): stage and, when
-- the battle could not start, message until A, B, START or 300 frames.
Special.arenaState = {
  matches = gen2("ArenaState"),
  poll = function(state, memo)
    if state.message == memo.message then return nil end
    memo.message = state.message
    if not state.message then return nil end
    return say(state.message), true
  end,
}

Special.ordered = {
  Special.cardFlip,
  Special.slotMachine,
  Special.unownPuzzle,
  Special.unownPrinter,
  Special.contestMenu,
  Special.battleTowerMenu,
  Special.buenaPassword,
  Special.dayCareMenu,
  Special.tradeMenu,
  Special.decorationMenu,
  Special.mailCompose,
  Special.mailRead,
  Special.mailMenu,
  Special.mailboxMenu,
  Special.photoStudio,
  Special.magnetTrainRide,
  Special.tradeAnim,
  Special.hallOfFame,
  Special.diploma,
  Special.credits,
  Special.unownWords,
  Special.unionList,
  Special.unionBattlePrep,
  Special.unionTradePrep,
  Special.arenaState,
}

-- Exposed for tests.
Special._conversation = conversation

return Special
