-- Gen 3 presenters for the special screens and minigames (FireRed;
-- decision 29): the Game Corner (slot machine, prize corner),
-- Trainer Tower and link battle records, minigame records, the wireless
-- status screen, Direct Corner, Union Room windows and chat, the link trade
-- menu, the trade animation, the PIN pad, Mystery Gift, Easy Chat, the
-- Day-Care level menu, the Hall of Fame and its PC, the diploma, the
-- credits, the whiteout screen, the mod manager, the wireless minigames'
-- shell (lobby, standby, countdown, messages and results), and these
-- overlays, which are not stack layers and come through Top.addAmbient:
-- the Berry Powder box, braille, the Seagallop crossing, Pokémon and fossil
-- pictures, the Itemfinder arrow, the VS Seeker result and the online
-- arena's message.  (The coins box, the forest title card, the release
-- sequence and the level-up window are read by the Menus, Items and Battle
-- presenters.)  Same matches/poll contract as
-- Presenters.lua; proxies come from gen3/Top.lua.
--
-- Every presenter reads the screen's own module fields and pure functions
-- and builds speech only when a compared field changes.  Nothing here calls
-- a function that changes game state.  Avoided on purpose:
-- MuseumPic.isActive (clears the picture when its binding check fails),
-- BerryPowderBox.isVisible (hides the box when the script changed), the
-- slot model's calcPayout and bet functions, MysteryGift.ensure (creates the
-- save record), Pokemon.install (loads the name cache) and every records
-- update.  Speech memory lives in the per-opening memo; the only state kept
-- in this file is the edge tokens that give an overlay one proxy per
-- showing.
--
-- Agent defaults until the owner decides (listed in the report):
-- braille says "Braille:" and the decoded text; the slot symbols are named
-- by the model's own icon names (7 for SEVEN); PIN digits other than the
-- one under the cursor stay hidden, as on screen; the Itemfinder says only
-- the direction its arrow shows; the VS Seeker says how many trainers want
-- a rematch; real-time minigame play (vine, falling berries, crushing) is
-- silent: menus, countdown, messages and results only.

local Common = require("src.access.screens.gen3.Common")
local Top = require("src.access.screens.gen3.Top")

local Special = {}

local say = Common.speakable
local position = Common.position

local ELLIPSIS = "\xe2\x80\xa6"

-- Non-empty parts as sentences: ". " between them, or a space when the part
-- before already ends a sentence ("?", "!", ".", ":" or "…").  Holes and
-- empty parts are skipped.
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

local function loaded(path)
  return package.loaded[path]
end

-- A read-only function through pcall; nil when missing or it raises.
local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok then return nil end
  return a, b
end

local function nonEmpty(text)
  if type(text) ~= "string" or text == "" then return nil end
  return text
end

-- ROM text the screens print, looked up the same way they do.
local function romModule()
  return loaded("src.core.game3.rom_text")
end

local function rom(key, ctx)
  local R = romModule()
  return R and nonEmpty(try(R.plain, key, ctx)) or nil
end

local function romAt(name, i, ctx)
  local R = romModule()
  return R and nonEmpty(try(R.at, name, i, nil, ctx)) or nil
end

-- Link screens print through the link family's RomText.
local function linkRom()
  local Family = loaded("src.core.game3.link.family")
  return (Family and try(Family.romText)) or romModule()
end

local function linkText(key, ctx)
  local R = linkRom()
  return R and nonEmpty(try(R.plain, key, ctx)) or nil
end

-- An engine string as drawn (src/core/Strings.lua is callable).
local function tr(source, ...)
  local Strings = loaded("src.core.Strings")
  if Strings then
    local ok, text = pcall(Strings, source, ...)
    if ok and type(text) == "string" then return text end
  end
  return source
end

local function yesNo(isYes)
  return say(rom(isYes and "gText_Yes" or "gText_No") or (isYes and "YES" or "NO"))
end

local GENDER_WORDS = { ["♂"] = "male", ["♀"] = "female" }

local function genderWord(symbol)
  return GENDER_WORDS[symbol]
end

-- "Lv12" as drawn, said as "level 12".
local function levelWords(text)
  text = tostring(text or "")
  local n = text:match("^%s*Lv%.?%s*(%d+)%s*$")
  if n then return "level " .. n end
  return say(text)
end

local function pokemonModule()
  return loaded("src.core.game3.pokemon")
end

-- A species name from the game's own name table, never loading it.
local function speciesName(species)
  local P = pokemonModule()
  species = tonumber(species)
  if not (P and species and species > 0) or rawget(P, "_names") == nil then return nil end
  return nonEmpty(try(P.name, species))
end

local function monName(mon)
  if type(mon) ~= "table" then return nil end
  local P = pokemonModule()
  if P and rawget(P, "_names") ~= nil then
    local name = nonEmpty(try(P.displayName, mon))
    if name then return name end
  end
  return nonEmpty(mon.nickname)
end

local function monGender(mon)
  local P = pokemonModule()
  if not (P and type(mon) == "table") then return nil end
  local species = try(P.speciesOf, mon) or tonumber(mon.species)
  local g = try(P.gender, species, mon.personality)
  if g == "M" then return "male" end
  if g == "F" then return "female" end
  return nil
end

-- Overlay edge tokens: a new table each time an overlay turns on, so each
-- showing has its own proxy and memo.
local tokens = {}
local function edge(kind, on)
  if not on then
    tokens[kind] = nil
    return nil
  end
  tokens[kind] = tokens[kind] or {}
  return tokens[kind]
end

local function layer(kind, path)
  return Common.matcher(kind, path)
end

local function kindOnly(kind)
  return function(state)
    return type(state) == "table" and state.gen3 == kind
  end
end

local ordered = {}
local function add(presenter)
  ordered[#ordered + 1] = presenter
  return presenter
end

local function ambient(source)
  Top.addAmbient(source)
end

-- The selected row of a src/ui/game3/list_menu.lua list.
local function listSelected(list)
  if type(list) ~= "table" then return nil, nil end
  local item, index = try(list.selected, list)
  return item, index, #(list.items or {})
end

-- ================================================================ slots

-- src/core/game3/slot_machine.lua: reels, lines and payouts.
local function slotModel()
  return loaded("src.core.game3.slot_machine")
end

local function iconName(Model, icon)
  for name, id in pairs(Model.ICON or {}) do
    if id == icon then
      if name == "SEVEN" then return "7" end
      return name
    end
  end
  return nil
end

local ROW_NAMES = { [0] = "top", [1] = "middle", [2] = "bottom" }

-- A pay line by where it runs, from the model's row attributes (cells are
-- reel * 3 + row).
local function lineName(Model, line)
  local attr = Model.ROW_ATTRIBUTES and Model.ROW_ATTRIBUTES[line]
  local A = Model.ROWATTR
  if not (attr and A) then return nil end
  local first, last = attr[A.COL1POS] % 3, attr[A.COL3POS] % 3
  if first == last then return ROW_NAMES[first] .. " row" end
  if first < last then return "diagonal from top left" end
  return "diagonal from bottom left"
end

local function betLines(Model, bet)
  local lines = try(Model.linesForBet, bet) or {}
  local rows, diagonals = {}, 0
  for _, line in ipairs(lines) do
    local attr = Model.ROW_ATTRIBUTES[line]
    local A = Model.ROWATTR
    if attr[A.COL1POS] % 3 == attr[A.COL3POS] % 3 then
      rows[#rows + 1] = ROW_NAMES[attr[A.COL1POS] % 3]
    else
      diagonals = diagonals + 1
    end
  end
  if #rows == 0 then return nil end
  if diagonals > 0 then
    return string.format("%d rows and %d diagonals", #rows, diagonals)
  end
  if #rows == 1 then return rows[1] .. " row" end
  return table.concat(rows, ", ", 1, #rows - 1) .. " and " .. rows[#rows] .. " rows"
end

local function reelText(Model, st, reel)
  local icons = try(Model.visibleIcons, st)
  if not icons then return nil end
  local names = {}
  for row = 0, 2 do names[#names + 1] = iconName(Model, icons[reel * 3 + row]) or "?" end
  return string.format("Reel %d: %s", reel + 1, table.concat(names, ", "))
end

-- The won lines, each with the three symbols on it (the screen flashes
-- them; there is no text for a win or a loss).
local function winText(Model, st)
  local icons = try(Model.visibleIcons, st)
  local A = Model.ROWATTR
  local parts = { string.format("Win. PAYOUT %d", tonumber(st.payout) or 0) }
  for line = 0, (Model.NUM_MATCH_LINES or 5) - 1 do
    if st.winFlags and st.winFlags[line] and icons then
      local attr = Model.ROW_ATTRIBUTES[line]
      local names = {}
      for _, col in ipairs({ A.COL1POS, A.COL2POS, A.COL3POS }) do
        names[#names + 1] = iconName(Model, icons[attr[col]]) or "?"
      end
      parts[#parts + 1] = (lineName(Model, line) or "line") .. ": " .. table.concat(names, ", ")
    end
  end
  return sentences(parts)
end

-- The payout chart (a picture), rebuilt from the model calls the screen's
-- chart rows come from: testIconAttribute and payoutFor per reward rank.
local function chartText(Model)
  local P = Model.PAYOUT
  if not P then return nil end
  local parts = { "Payout chart" }
  for rank = (Model.NUM_PAYOUT_TYPES or 7) - 1, P.CHERRIES2, -1 do
    local names = {}
    for icon = 0, 6 do
      if try(Model.testIconAttribute, rank, icon) then names[#names + 1] = iconName(Model, icon) end
    end
    local what
    if rank == P.CHERRIES2 then
      what = (names[1] or "?") .. " on reel 1"
    elseif rank == P.CHERRIES3 then
      what = (names[1] or "?") .. " on reels 1 and 2"
    else
      what = "3 " .. table.concat(names, " or ")
    end
    parts[#parts + 1] = what .. ", " .. tostring(try(Model.payoutFor, rank) or 0)
  end
  return sentences(parts)
end

Special.slotMachine = add({
  matches = layer("slot_machine", "src.ui.game3.slot_machine"),
  poll = function(state, memo, entering)
    local M = state.mod
    local st = M and M.state
    local Model = slotModel()
    if not (st and Model) then return nil end
    local parts, queue = {}, false
    local coins = try(Model.coins, M._session)
    local credit = coins and (say(tr("CREDIT")) .. " " .. tostring(coins)) or nil
    if entering then
      if not memo.entered then
        memo.entered = true
        parts[#parts + 1] = "Slot machine"
        parts[#parts + 1] = credit
        parts[#parts + 1] = "Down bets 1 coin, R bets 3, A spins and stops each reel, Right shows the payout chart"
      else
        parts[#parts + 1] = credit
      end
    end
    -- reels as they come to rest (one keeps moving after A until it lands)
    if memo.spinning then
      for reel = 0, 2 do
        if memo.spinning[reel] and not st.reelIsSpinning[reel] then
          memo.spinning[reel] = false
          parts[#parts + 1] = reelText(Model, st, reel)
          queue = true
        end
      end
    end
    local task = M.task
    if task ~= memo.task then
      local before = memo.task
      memo.task = task
      if task == "stopping" then
        memo.spinning = {}
        for reel = 0, 2 do memo.spinning[reel] = st.reelIsSpinning[reel] and true or false end
        parts[#parts + 1] = "Spinning"
      elseif task == "win" then
        memo.spinning = nil
        parts[#parts + 1] = winText(Model, st)
        queue = true
      elseif task == "lose" then
        memo.spinning = nil
        parts[#parts + 1] = "No win"
        queue = true
      elseif task == "quit" then
        memo.yesNo = M._yesNo
        parts[#parts + 1] = say(M._message)
        parts[#parts + 1] = yesNo(M._yesNo == 1)
      elseif task == "nocoins" then
        parts[#parts + 1] = say(M._message)
      elseif task == "bet" and before ~= nil and before ~= "lose" and not entering then
        parts[#parts + 1] = credit
      end
    elseif task == "quit" and M._yesNo ~= memo.yesNo then
      memo.yesNo = M._yesNo
      parts[#parts + 1] = yesNo(M._yesNo == 1)
    end
    local bet = tonumber(st.bet) or 0
    if bet ~= memo.bet then
      memo.bet = bet
      if bet > 0 then
        parts[#parts + 1] = sentences({ "Bet " .. bet .. ": " .. (betLines(Model, bet) or ""), credit })
      end
    end
    local help = M.helpPhase == "shown"
    if help ~= memo.help then
      memo.help = help
      if help then parts[#parts + 1] = chartText(Model) end
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, not queue
  end,
})

-- ================================================================ prize corner, coins

Special.prizeCorner = add({
  matches = layer("prize_corner", "src.ui.game3.prize_corner"),
  poll = function(state, memo, entering)
    local P = state.mod
    local rows = P.rows
    if type(rows) ~= "table" then return nil end
    local cursor = P.cursor or 1
    if not entering and memo.cursor == cursor then return nil end
    memo.cursor = cursor
    local row = rows[cursor]
    if type(row) ~= "table" then return nil end
    local text = say(row.name or row.label)
    if row.amount and row.amount ~= "" then text = text .. ", " .. say(row.amount) end
    if entering then text = text .. ", " .. position(cursor, #rows) end
    return text, true
  end,
})

-- The COINS window (src/ui/game3/coins_box.lua) is read by the Menus
-- presenters with the money box (same overlay pattern), so it is not here.

-- The Berry Powder window: read `visible` and the owner check that
-- isVisible would make, without its hide().
Special.berryPowderBox = add({
  matches = kindOnly("berry_powder_box"),
  poll = function(state, memo)
    local Box = state.mod
    local amount = Box._amount
    if memo.amount == amount then return nil end
    memo.amount = amount
    local title = rom("gOtherText_Powder") or "POWDER"
    return say(title) .. " " .. tostring(amount), false
  end,
})

ambient(function(_, proxy)
  local Box = loaded("src.ui.game3.berry_powder_box")
  local Space = loaded("src.core.game3.scripting.space")
  local on = Box ~= nil and Box.visible == true and Box._owner == (Space and Space.vm or nil)
  local key = edge("berry_powder_box", on)
  if not key then return nil end
  return proxy(key, "berry_powder_box", { mod = Box })
end)

-- ================================================================ records

local function dashesOnly(text)
  text = tostring(text or "")
  return text ~= "" and text:gsub("[%-%s]", "") == ""
end

Special.towerRecords = add({
  matches = layer("trainer_tower_records", "src.ui.game3.trainer_tower_records"),
  poll = function(state, memo, entering)
    local R = state.mod
    if R._phase == "in" or not R.open then return nil end
    if memo.said and not entering then return nil end
    memo.said = true
    local parts = {}
    if R._kind == "link" then
      parts[#parts + 1] = say(R._title)
      parts[#parts + 1] = say(R._total)
      local headers = R.columnHeaders and try(R.columnHeaders) or {}
      for _, row in ipairs(R._rows or {}) do
        if dashesOnly(row.name) then
          parts[#parts + 1] = "No record"
        else
          local cells = { say(row.name) }
          for i, field in ipairs({ "wins", "losses", "draws" }) do
            local value = tostring(row[field] or ""):gsub("^%s+", "")
            cells[#cells + 1] = (headers[i] and (say(headers[i]) .. " ") or "") .. value
          end
          parts[#parts + 1] = table.concat(cells, ", ")
        end
      end
    else
      parts[#parts + 1] = say(rom("gText_TimeBoard"))
      for _, row in ipairs(R._rows or {}) do
        local label = say(row.label)
        local time = say(row.time)
        parts[#parts + 1] = label ~= "" and (label .. ", " .. time) or time
      end
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
})

-- Minigame records (src/ui/game3/minigame_records.lua): title lines, then
-- label and value pairs; a value is the line drawn to the right of the one
-- before it.
Special.minigameRecords = add({
  matches = layer("minigame_records", "src.ui.game3.minigame_records"),
  poll = function(state, memo, entering)
    local R = state.mod
    if not R.open or type(R._lines) ~= "table" then return nil end
    if memo.said and not entering then return nil end
    memo.said = true
    local parts, lines, i = {}, R._lines, 1
    while i <= #lines do
      local line, nextLine = lines[i], lines[i + 1]
      if nextLine and (tonumber(nextLine.x) or 0) > (tonumber(line.x) or 0) then
        local label = say(line.text)
        parts[#parts + 1] = label .. (label:find(":$") and " " or ", ") .. say(nextLine.text)
        i = i + 2
      else
        parts[#parts + 1] = say(line.text)
        i = i + 1
      end
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
})

-- ================================================================ wireless and link

-- Wireless status screen (src/ui/game3/link_menu.lua): the title and each
-- group's count; afterwards only counts that change.
Special.wirelessStatus = add({
  matches = layer("wireless_status", "src.ui.game3.link_menu"),
  poll = function(state, memo, entering)
    local L = state.mod
    local rows = L.rows
    if type(rows) ~= "table" then return nil end
    memo.counts = memo.counts or {}
    local parts = {}
    if entering then
      local Status = loaded("src.core.game3.link.status")
      parts[#parts + 1] = say(Status and Status.HEADER and Status.HEADER[0])
    end
    for i, row in ipairs(rows) do
      if entering or memo.counts[i] ~= row.count then
        parts[#parts + 1] = say(row.label) .. " " .. tostring(row.count or 0)
      end
      memo.counts[i] = row.count
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, entering
  end,
})

local function idText(trainerId)
  if trainerId == nil then return nil end
  return string.format("ID %05d", math.floor(tonumber(trainerId) or 0) % 65536)
end

-- A Direct Corner or lobby player row as drawn: name, ID; "locked" for the
-- lock icon, "new" while the arrival is drawn green.
local function directRow(Direct, item)
  if type(item) ~= "table" then return nil end
  local row = item.row
  if type(row) ~= "table" then return "empty" end
  local parts = { say(row.name) }
  parts[#parts + 1] = idText(row.trainerId)
  if row.locked then parts[#parts + 1] = "locked" end
  if (Direct.fresh and (Direct.fresh[row.key] or 0) > 0) then parts[#parts + 1] = "new" end
  return table.concat(parts, ", ")
end

Special.directCorner = add({
  matches = layer("direct_corner", "src.ui.game3.link_menu"),
  poll = function(state, memo, entering)
    local L = state.mod
    local Direct = L and L.Direct
    if not Direct then return nil end
    local view = Direct.view
    local list = (view == "modes" and Direct.modes) or (view == "choose" and Direct.list) or nil
    local item, index, count = listSelected(list)
    local changedView = entering or view ~= memo.view or list ~= memo.list
    local parts = {}
    if changedView then
      memo.view, memo.list = view, list
      memo.index = nil
      memo.names = nil
    end
    if view == "choose" then
      -- arrivals: names in the slots that were not there before
      local names = {}
      for _, row in pairs(Direct.rows or {}) do
        if type(row) == "table" and row.key ~= nil then names[row.key] = row.name end
      end
      if memo.names then
        for key, name in pairs(names) do
          if memo.names[key] == nil then parts[#parts + 1] = say(name) .. " joined" end
        end
        for key, name in pairs(memo.names) do
          if names[key] == nil then parts[#parts + 1] = say(name) .. " left" end
        end
      end
      memo.names = names
    end
    if list and (changedView or index ~= memo.index) then
      memo.index = index
      local text
      if view == "modes" then
        text = item and say(item.label) or nil
      else
        text = directRow(Direct, item)
      end
      if text then
        if changedView and index and count then text = text .. ", " .. position(index, count) end
        parts[#parts + 1] = text
      end
    end
    local players = (Direct.count or 0) >= 2 and Direct.count or nil
    if players ~= memo.players then
      memo.players = players
      if players then
        parts[#parts + 1] = say(linkText("gText_NumPlayerLink", { stringVars = { tostring(players) } }))
      end
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
})

-- Union Room trade board row: name, the wanted type (a badge picture, named
-- from the type list's own labels), the offered Pokémon and level.
local function boardRow(U, entry)
  if type(entry) ~= "table" then return nil end
  local parts = { say(entry.name) }
  local species = tonumber(entry.species) or 0
  if species == 412 then
    parts[#parts + 1] = say(linkText("gText_UR_EggTrade"))
    return table.concat(parts, ", ")
  end
  local R = linkRom()
  local typeName
  for i, id in ipairs(U.TYPE_IDS or {}) do
    if id == tonumber(entry.wantType) and R then
      typeName = nonEmpty(try(R.plain, try(R.key, "sListMenuItems_TypeNames", i - 1)))
      break
    end
  end
  if typeName then parts[#parts + 1] = "wants " .. say(typeName) end
  local offer = speciesName(species)
  if offer then parts[#parts + 1] = "offers " .. say(offer) end
  if entry.level then parts[#parts + 1] = "level " .. tostring(math.floor(tonumber(entry.level) or 0)) end
  return table.concat(parts, ", ")
end

Special.unionRoom = add({
  matches = layer("union_room", "src.ui.game3.union_room"),
  poll = function(state, memo, entering)
    local U = state.mod
    local mode, list = U.mode, U.list
    local fresh = entering or mode ~= memo.mode or list ~= memo.list
    if fresh then
      memo.mode, memo.list, memo.index, memo.player, memo.count = mode, list, nil, nil, nil
    end
    local parts = {}
    if list then
      local item, index, count = listSelected(list)
      if fresh and mode == "board" then
        local R = linkRom()
        parts[#parts + 1] = say(R and try(U.fontText, "gText_UR_NameWantedOfferLv") or nil)
      end
      if fresh or index ~= memo.index then
        memo.index = index
        local text
        if type(item) == "table" then
          if item.entry then
            text = boardRow(U, item.entry)
          elseif item.label and item.label ~= "" then
            text = say(item.label)
          else
            text = "empty"
          end
        end
        if text then
          if fresh and index and count then text = text .. ", " .. position(index, count) end
          parts[#parts + 1] = text
        end
      end
    else
      local players = U.players or {}
      local count = #players
      if fresh or count ~= memo.count then
        memo.count = count
        parts[#parts + 1] = say(linkText("gText_Var1Players", { stringVars = { tostring(count + 1) } }))
        if count == 0 then parts[#parts + 1] = say(tr("Searching...")) end
      end
      local row = players[U.cursor or 1]
      local key = row and (tostring(row.name) .. "|" .. tostring(row.activity)) or nil
      if row and (fresh or key ~= memo.player or U.cursor ~= memo.cursor) then
        memo.player, memo.cursor = key, U.cursor
        local text = say(row.name)
        local activity = try(U.activityLabel, row.activity)
        if nonEmpty(activity) then text = text .. ", " .. say(activity) end
        parts[#parts + 1] = text .. ", " .. position(U.cursor or 1, count)
      end
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
})

-- Union Room chat (src/core/game3/link/chat.lua).  Emoji are glyph tags
-- ({EMOJI_HEART}); they are said by their tag's words ("heart emoji").
local function chatSpeakable(text)
  text = tostring(text or ""):gsub("{EMOJI_([%u_]+)}", function(name)
    return " " .. name:lower():gsub("_", " ") .. " emoji "
  end)
  return say(text)
end

local CHAT_KEYS = { [" "] = "space" }

local function chatToken(token)
  if token == nil then return nil end
  if CHAT_KEYS[token] then return CHAT_KEYS[token] end
  local text = chatSpeakable(token)
  if text == "" then return say(token) end
  return text
end

local function chatPageName(Chat, page)
  local R = linkRom()
  local key = R and try(R.key, "sKeyboardSwapTexts", page)
  return key and say(try(R.plain, key)) or nil
end

local function chatKey(Chat)
  if Chat.page == (Chat.PAGE and Chat.PAGE.REGISTER) then
    local phrase = Chat.registered and Chat.registered[(Chat.row or 0) + 1]
    return nonEmpty(phrase) and chatSpeakable(phrase) or "empty"
  end
  local row = try(Chat.keyboardRow, Chat.page, Chat.row or 0) or {}
  return chatToken(row[(Chat.col or 0) + 1]) or "empty"
end

local function chatBuffer(Chat)
  local text = table.concat(Chat.buffer or {})
  text = chatSpeakable(text)
  return text ~= "" and text or "empty"
end

Special.unionChat = add({
  matches = layer("union_chat", "src.ui.game3.union_chat"),
  poll = function(state, memo, entering)
    local Chat = loaded("src.core.game3.link.chat")
    if not Chat then return nil end
    local parts = {}
    -- new log lines, in order
    local lines = Chat.lines or {}
    local last = lines[#lines]
    if memo.lastLine ~= last then
      local from = 1
      for i = #lines, 1, -1 do
        if lines[i] == memo.lastLine then from = i + 1 break end
      end
      if memo.lastLine == nil and entering then from = #lines + 1 end
      for i = from, #lines do parts[#parts + 1] = chatSpeakable(lines[i].text) end
      memo.lastLine = last
    end
    local msg = Chat.msg
    if msg ~= memo.msg then
      memo.msg = msg
      if msg then parts[#parts + 1] = say(msg.text) end
    end
    local yn = Chat.yesNo
    local ynCursor = yn and yn.cursor
    if yn ~= memo.yn or ynCursor ~= memo.ynCursor then
      memo.yn, memo.ynCursor = yn, ynCursor
      if yn then parts[#parts + 1] = yesNo(ynCursor == 0) end
    end
    local swap = Chat.swap
    local swapCursor = swap and swap.cursor
    if swap ~= memo.swap or swapCursor ~= memo.swapCursor then
      local opened = memo.swap == nil
      memo.swap, memo.swapCursor = swap, swapCursor
      if swap then
        local text = chatPageName(Chat, swapCursor or 0)
        if text and opened then text = text .. ", " .. position((swapCursor or 0) + 1, (Chat.SWAP_EXIT or 4) + 1) end
        parts[#parts + 1] = text
      end
    end
    if not (msg or yn or swap) then
      local buffer = #(Chat.buffer or {})
      local pageChanged = Chat.page ~= memo.page
      if entering or pageChanged then
        parts[#parts + 1] = chatPageName(Chat, Chat.page or 0)
      end
      if memo.buffer and buffer > memo.buffer then
        parts[#parts + 1] = chatToken(Chat.buffer[buffer]) .. ", " .. chatBuffer(Chat)
      elseif memo.buffer and buffer < memo.buffer then
        parts[#parts + 1] = "deleted, " .. chatBuffer(Chat)
      elseif entering or pageChanged or Chat.row ~= memo.row or Chat.col ~= memo.col then
        parts[#parts + 1] = chatKey(Chat)
      end
      memo.buffer, memo.page, memo.row, memo.col = buffer, Chat.page, Chat.row, Chat.col
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
})

-- ---------------------------------------------------------------- link trade

local function tradeParty(side)
  if side == 0 then
    local Link = loaded("src.core.game3.link")
    local s = Link and try(Link.session)
    return (s and s.party) or {}
  end
  local Trade = loaded("src.core.game3.link.trade")
  return (Trade and Trade.peerParty) or {}
end

local function heldWords(mon)
  local Party = loaded("src.ui.game3.party_menu")
  local frame = Party and try(Party.heldItemFrame, mon)
  if frame == 1 then return "holding mail" end
  if frame == 0 then return "holding an item" end
  return nil
end

local function tradeMonRow(mon)
  if type(mon) ~= "table" then return nil end
  local P = pokemonModule()
  local parts = { say(monName(mon) or "?") }
  if P and try(P.isEgg, mon) then return parts[1] end
  parts[#parts + 1] = "level " .. tostring(math.floor(tonumber(mon.level) or 0))
  parts[#parts + 1] = monGender(mon)
  parts[#parts + 1] = heldWords(mon)
  local out = {}
  for i = 1, table.maxn(parts) do if parts[i] then out[#out + 1] = parts[i] end end
  return table.concat(out, ", ")
end

local function tradeMoves(T, mon)
  local lines = try(T.movesLines, mon) or {}
  local out = {}
  for _, line in ipairs(lines) do
    if nonEmpty(line) then out[#out + 1] = say(line) end
  end
  return table.concat(out, ", ")
end

local function tradePosText(T, pos)
  local size = 6
  if pos >= 2 * size then return say(romAt("sActionTexts", 0) or "CANCEL") end
  local side = pos >= size and 1 or 0
  local party = tradeParty(side)
  local index = pos - side * size + 1
  local row = tradeMonRow(party[index])
  if not row then return nil end
  return row, side, index, math.min(size, #party)
end

local function tradeBottom(T)
  if T.bottom == "okay" then return say(rom("gText_IsThisTradeOkay")) end
  if T.bottom == "cancel" then return say(romAt("sActionTexts", 4)) end
  return say(romAt("sActionTexts", 1))
end

Special.linkTrade = add({
  matches = layer("link_trade", "src.ui.game3.link_trade_menu"),
  poll = function(state, memo, entering)
    local T = state.mod
    local parts = {}
    local cb = T.cb
    if T.message ~= memo.message then
      memo.message = T.message
      if T.message then parts[#parts + 1] = say(T.message) end
    end
    local cbChanged = entering or cb ~= memo.cb
    memo.cb = cb
    if cb == "main" then
      if cbChanged or T.pos ~= memo.pos then
        local text, side, index, count = tradePosText(T, T.pos or 0)
        if cbChanged then parts[#parts + 1] = tradeBottom(T) end
        if text then
          if side ~= memo.side or cbChanged then
            text = (side == 1 and "Partner's party" or (side == 0 and "Your party" or "")) .. ", " .. text
            text = text:gsub("^, ", "")
          end
          if index and (cbChanged or side ~= memo.side) then text = text .. ", " .. position(index, count) end
          parts[#parts + 1] = text
        end
        memo.pos, memo.side = T.pos, side
      end
    elseif cb == "selected" then
      if cbChanged or T.subCursor ~= memo.subCursor then
        memo.subCursor = T.subCursor
        local label = rom(T.subCursor == 2 and "gText_TradeAction_Trade" or "gText_TradeAction_Summary")
        local text = say(label)
        if cbChanged then text = text .. ", " .. position(T.subCursor or 1, 2) end
        parts[#parts + 1] = text
      end
    elseif cb == "cancel_prompt" or cb == "confirm_prompt" then
      if cbChanged then
        memo.yesNoCursor = T.yesNoCursor
        if cb == "confirm_prompt" then
          for side = 0, 1 do
            local sel = T.selected and T.selected[side]
            local mon = sel and sel.idx and tradeParty(side)[sel.idx + 1]
            if mon then
              parts[#parts + 1] = (side == 0 and "Yours: " or "Partner's: ") .. (tradeMonRow(mon) or "")
                .. ". " .. tradeMoves(T, mon)
            end
          end
        end
        parts[#parts + 1] = tradeBottom(T)
        parts[#parts + 1] = yesNo(T.yesNoCursor == 1)
      elseif T.yesNoCursor ~= memo.yesNoCursor then
        memo.yesNoCursor = T.yesNoCursor
        parts[#parts + 1] = yesNo(T.yesNoCursor == 1)
      end
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
})

-- Trade animation: each new caption, queued so a quick sequence is heard
-- whole.
Special.tradeScene = add({
  matches = layer("trade_scene", "src.ui.game3.trade_scene"),
  poll = function(state, memo)
    local core = state.mod._core
    local s = core and try(core.state)
    if type(s) ~= "table" then return nil end
    local caption = s.text
    if caption == memo.text then return nil end
    memo.text = caption
    local text = say(caption)
    if text == "" then return nil end
    return text, false
  end,
})

-- PIN pad (a port addition): the title or error, then the digit under the
-- cursor; the others are drawn masked and stay unspoken.
Special.pinEntry = add({
  matches = layer("pin_entry", "src.ui.game3.pin_entry"),
  poll = function(state, memo, entering)
    local P = state.mod
    if not P.open then return nil end
    local cursor = P.cursor or 1
    local digit = (P.digits or {})[cursor] or 0
    local heading = P.error or P.title
    local parts = {}
    if entering or heading ~= memo.heading then
      memo.heading = heading
      parts[#parts + 1] = say(heading)
    end
    if entering or cursor ~= memo.cursor or #parts > 0 then
      parts[#parts + 1] = string.format("digit %d of %d, %d", cursor, P.LENGTH or 4, digit)
    elseif digit ~= memo.digit then
      parts[#parts + 1] = tostring(digit)
    end
    memo.cursor, memo.digit = cursor, digit
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
})

-- ================================================================ Mystery Gift

-- The saved card and news, read where MysteryGift.ensure would find them
-- (without creating anything).
local function giftRecord(st)
  local session = st.session
  if type(session) ~= "table" then return nil end
  if type(session.mysteryGift) == "table" then return session.mysteryGift end
  local MG = loaded("src.core.game3.mystery_gift")
  local data = type(session.modData) == "table" and MG and session.modData[MG.SAVE_KEY]
  return type(data) == "table" and data or nil
end

local function giftCard(st)
  if st.viewCard then return st.viewCard, { iconSpecies = st.viewCard.iconSpecies } end
  local rec = giftRecord(st)
  return rec and rec.card, rec and rec.cardMetadata
end

local function giftNews(st)
  if st.viewNews then return st.viewNews end
  local rec = giftRecord(st)
  return rec and rec.news
end

local function cardText(st)
  local card, meta = giftCard(st)
  if type(card) ~= "table" then return nil end
  local MG = loaded("src.core.game3.mystery_gift") or {}
  local parts = { say(card.titleText), say(card.subtitleText) }
  if (tonumber(card.idNumber) or 0) ~= 0 then parts[#parts + 1] = "number " .. tostring(card.idNumber) end
  for i = 1, 4 do parts[#parts + 1] = say((card.bodyText or {})[i]) end
  parts[#parts + 1] = say(card.footerLine1Text)
  local kind = tonumber(card.type) or 0
  if kind == MG.CARD_TYPE_GIFT then
    parts[#parts + 1] = say(card.footerLine2Text)
  elseif kind == MG.CARD_TYPE_LINK_STAT and type(meta) == "table" then
    parts[#parts + 1] = string.format("wins %d, losses %d, trades %d",
      tonumber(meta.battlesWon) or 0, tonumber(meta.battlesLost) or 0, tonumber(meta.numTrades) or 0)
  end
  local icon = type(meta) == "table" and speciesName(meta.iconSpecies)
  if icon then parts[#parts + 1] = "Picture: " .. say(icon) end
  if kind == MG.CARD_TYPE_STAMP and type(meta) == "table" and type(meta.stampData) == "table" then
    local stamps = {}
    for i = 1, math.min(tonumber(card.maxStamps) or 0, MG.MAX_STAMP_CARD_STAMPS or 7) do
      local name = speciesName((meta.stampData.species or {})[i])
      if name then stamps[#stamps + 1] = say(name) end
    end
    if #stamps > 0 then parts[#parts + 1] = "Stamps: " .. table.concat(stamps, ", ") end
  end
  return sentences(parts)
end

local NEWS_LINES = 8

local function newsText(st, from)
  local news = giftNews(st)
  if type(news) ~= "table" then return nil end
  local parts = {}
  if not from then parts[#parts + 1] = say(news.titleText) end
  local scroll = st.newsScroll or 0
  local first = from or 1
  for i = first, NEWS_LINES do
    parts[#parts + 1] = say((news.bodyText or {})[i + scroll])
  end
  return sentences(parts)
end

local CARD_STATES = { gift_input = true, news_view = true, saved_view = true, gift_menu = true, ask_toss = true }

Special.mysteryGift = add({
  matches = kindOnly("mystery_gift"),
  poll = function(state, memo, entering)
    local st = state.key
    if type(st) ~= "table" then return nil end
    local parts = {}
    local stateChanged = entering or st.state ~= memo.state
    if stateChanged then
      local before = memo.state
      memo.state = st.state
      memo.cursor, memo.listIndex, memo.scroll = nil, nil, st.newsScroll
      if CARD_STATES[st.state] and not (before and CARD_STATES[before]) then
        parts[#parts + 1] = st.isNews and newsText(st) or cardText(st)
      end
      if entering and st.state == "main_menu" then parts[#parts + 1] = say(rom("gText_MysteryGift")) end
    end
    if st.isNews and CARD_STATES[st.state] and (st.newsScroll or 0) ~= (memo.scroll or 0) then
      local down = (st.newsScroll or 0) > (memo.scroll or 0)
      memo.scroll = st.newsScroll
      local news = giftNews(st)
      local line = news and (news.bodyText or {})[(st.newsScroll or 0) + (down and NEWS_LINES or 1)]
      parts[#parts + 1] = say(line)
    end
    local msg = st.msg
    if msg ~= memo.msg then
      memo.msg = msg
      if msg then parts[#parts + 1] = say(msg.text) end
    end
    local yn = st.yesno
    if yn ~= memo.yn then
      memo.yn = yn
      memo.ynCursor = yn and yn.cursor
      if yn then
        parts[#parts + 1] = say(yn.text)
        parts[#parts + 1] = yesNo(yn.cursor == 1)
      end
    elseif yn and yn.cursor ~= memo.ynCursor then
      memo.ynCursor = yn.cursor
      parts[#parts + 1] = yesNo(yn.cursor == 1)
    end
    if not (msg or yn) then
      if st.prompt ~= memo.prompt then
        memo.prompt = st.prompt
        if st.prompt then parts[#parts + 1] = say(st.prompt) end
      end
      if (st.state == "main_menu" or st.state == "gift_menu") and type(st.rows) == "table" then
        if stateChanged or st.cursor ~= memo.cursor or memo.wasBusy then
          memo.cursor = st.cursor
          local text = say(st.rows[st.cursor or 1])
          if stateChanged or memo.wasBusy then text = text .. ", " .. position(st.cursor or 1, #st.rows) end
          parts[#parts + 1] = text
        end
      elseif st.state == "offer_list" and st.list then
        local item, index, count = listSelected(st.list)
        if stateChanged or index ~= memo.listIndex or memo.wasBusy then
          memo.listIndex = index
          if item then
            local text = say(item.label)
            if stateChanged or memo.wasBusy then text = text .. ", " .. position(index, count) end
            parts[#parts + 1] = text
          end
        end
      end
    end
    memo.wasBusy = (msg or yn) and true or false
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
})

-- ================================================================ Easy Chat

local function easyChatText()
  return loaded("src.core.game3.easy_chat_text")
end

local function easyWord(id)
  local E = easyChatText()
  if not E or id == nil or id == E.EC_WORD_UNDEFINED then return nil end
  return nonEmpty(try(E.word, id))
end

local function easyPhrase(st)
  local words = {}
  for i = 1, st.count or 0 do
    local w = easyWord((st.words or {})[i])
    if w then words[#words + 1] = say(w) end
  end
  if #words == 0 then return "empty" end
  return table.concat(words, " ")
end

local function easySlot(st)
  local slot = st.selectedSlot or 1
  local w = easyWord((st.words or {})[slot])
  return string.format("word %d of %d, %s", slot, st.count or 0, w and say(w) or "empty")
end

local EASY_CONFIRM = { CONFIRM = true, CANCEL_CONFIRM = true, DEL_ALL_CONFIRM = true }

Special.easyChat = add({
  matches = layer("easy_chat", "src.ui.game3.easy_chat"),
  poll = function(state, memo, entering)
    local E = state.mod
    local st = E._state
    if type(st) ~= "table" then return nil end
    local mode = st.mode
    local modeChanged = entering or mode ~= memo.mode
    local parts = {}
    if mode == "SLOT" then
      if entering and not memo.entered then
        memo.entered = true
        parts[#parts + 1] = say(st.title)
        parts[#parts + 1] = say(st.instr1) .. " " .. say(st.instr2)
        parts[#parts + 1] = easyPhrase(st)
      end
      local key = tostring(st.selectedSlot) .. ":" .. tostring((st.words or {})[st.selectedSlot or 1])
      if modeChanged or key ~= memo.slotKey then
        if memo.mode == "WORD" and not entering then parts[#parts + 1] = easyPhrase(st) end
        memo.slotKey = key
        parts[#parts + 1] = easySlot(st)
      end
    elseif mode == "FOOTER" then
      if modeChanged or st.footerIdx ~= memo.footer then
        memo.footer = st.footerIdx
        local labels = try(E.footerLabels) or {}
        local text = say(labels[st.footerIdx or 1])
        parts[#parts + 1] = text .. ", " .. position(st.footerIdx or 1, #labels > 0 and #labels or 3)
      end
    elseif mode == "GROUP" then
      if modeChanged or st.groupCursor ~= memo.group then
        memo.group = st.groupCursor
        local T = easyChatText()
        local name = T and try(T.groupName, (st.groups or {})[st.groupCursor or 1])
        parts[#parts + 1] = say(name) .. ", " .. position(st.groupCursor or 1, #(st.groups or {}))
      end
    elseif mode == "WORD" then
      local group = (st.groups or {})[st.groupCursor or 1]
      local words = group and group.words or {}
      local index = (st.wordPage or 0) * 8 + (st.wordCursor or 1)
      if modeChanged or index ~= memo.word then
        memo.word = index
        local T = easyChatText()
        local word = T and try(T.wordInGroup, words[index], group)
        local text = say(word)
        if modeChanged or (st.wordPage ~= memo.page) then
          text = text .. ", " .. position(index, #words)
        end
        memo.page = st.wordPage
        parts[#parts + 1] = text
      end
    elseif EASY_CONFIRM[mode] then
      if modeChanged then
        memo.choice = st.confirmChoice
        if mode == "CONFIRM" then
          parts[#parts + 1] = say(st.confirm1) .. " " .. easyPhrase(st) .. ". " .. say(st.confirm2)
        elseif mode == "CANCEL_CONFIRM" then
          parts[#parts + 1] = say(rom("gText_QuitEditing"))
        else
          parts[#parts + 1] = say(rom("gText_AllTextBeingEditedWill")) .. " " .. say(rom("gText_BeDeletedThatOkay"))
        end
        parts[#parts + 1] = yesNo(st.confirmChoice == 1)
      elseif st.confirmChoice ~= memo.choice then
        memo.choice = st.confirmChoice
        parts[#parts + 1] = yesNo(st.confirmChoice == 1)
      end
    end
    memo.mode = mode
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
})

-- ================================================================ Day-Care

Special.daycareMenu = add({
  matches = layer("daycare_level_menu", "src.ui.game3.daycare_menu"),
  poll = function(state, memo, entering)
    local D = state.mod
    local rows = D.rowList
    if type(rows) ~= "table" then return nil end
    local cursor = D.cursor or 1
    if not entering and memo.cursor == cursor then return nil end
    memo.cursor = cursor
    local row = rows[cursor]
    if type(row) ~= "table" then return nil end
    local parts = { say(row.text) }
    parts[#parts + 1] = genderWord(row.symbol)
    if nonEmpty(row.level) then parts[#parts + 1] = levelWords(row.level) end
    local out = {}
    for i = 1, table.maxn(parts) do if parts[i] and parts[i] ~= "" then out[#out + 1] = parts[i] end end
    -- a slot with no Pokémon draws nothing
    local text = #out > 0 and table.concat(out, ", ") or "empty"
    if entering then text = text .. ", " .. position(cursor, #rows) end
    return text, true
  end,
})

-- ================================================================ Hall of Fame

local SPECIES_NIDORAN_F, SPECIES_NIDORAN_M, SPECIES_EGG = 29, 32, 412

-- A member card as the screens print it: nickname, species and gender
-- sign, level, Pokédex number, ID.  `number` is the card's own number text.
local function memberCard(mon, nickname, number, trainerId)
  local sp = tonumber(mon.species) or 0
  local parts = { say(nickname or "") }
  if sp == SPECIES_EGG then return parts[1] end
  local species = speciesName(sp)
  local P = pokemonModule()
  local gender
  if sp ~= SPECIES_NIDORAN_M and sp ~= SPECIES_NIDORAN_F and P then
    local g = try(P.gender, sp, tonumber(mon.personality) or 0)
    gender = (g == "M" and "male") or (g == "F" and "female") or nil
  end
  if species and say(species) ~= parts[1] then parts[#parts + 1] = say(species) end
  if gender then parts[#parts + 1] = gender end
  parts[#parts + 1] = "level " .. tostring(tonumber(mon.level) or 0)
  if number then parts[#parts + 1] = "number " .. number end
  parts[#parts + 1] = string.format("ID %05d", (tonumber(trainerId) or 0) % 65536)
  return table.concat(parts, ", ")
end

local function hofNumber(mon, national, session)
  local sp = tonumber(mon.species) or 0
  local P = pokemonModule()
  local dex = (P and try(P.national, sp)) or sp
  if not national then
    local Dex = loaded("src.core.game3.dex")
    local Profile = loaded("src.core.game3.profile")
    local row = Profile and try(Profile.forSession, session)
    dex = Dex and row and try(Dex.regionalNumber, sp, row.id) or nil
  end
  return dex and string.format("%03d", dex) or "???"
end

Special.hallOfFame = add({
  matches = layer("hall_of_fame", "src.ui.game3.hall_of_fame"),
  poll = function(state, memo)
    local H = state.mod
    local parts = {}
    local saving = H._saving and true or false
    if saving ~= memo.saving then
      memo.saving = saving
      if saving then parts[#parts + 1] = say(rom("gText_SavingDontTurnOffThePower2")) end
    end
    local info = H._info
    if info ~= memo.info then
      memo.info = info
      if type(info) == "table" then
        local session = H._session or {}
        local P = pokemonModule()
        local nickname = (P and try(P.isEgg, info)) and rom("gText_EggNickname") or monName(info)
        parts[#parts + 1] = memberCard(info, nickname, hofNumber(info, H._national, session),
          info.otId or info.tid or session.trainerId)
      end
    end
    local welcome = H._welcome and true or false
    if welcome ~= memo.welcome then
      memo.welcome = welcome
      if welcome then parts[#parts + 1] = say(rom("gText_WelcomeToHOF")) end
    end
    local player = H._playerInfo and true or false
    if player ~= memo.player then
      memo.player = player
      if player then
        local session = H._session or {}
        local pt = session.playtime or session.playTime or {}
        local h = tonumber(session.playTimeHours or session.hours or pt.hours) or 0
        local m = tonumber(session.playTimeMinutes or session.minutes or pt.minutes) or 0
        parts[#parts + 1] = say(tostring(session.name or session.playerName or ""))
        parts[#parts + 1] = string.format("ID %05d", (tonumber(session.trainerId or session.playerTrainerId) or 0) % 65536)
        parts[#parts + 1] = string.format("time %d:%02d", h % 1000, m % 100)
        parts[#parts + 1] = say(rom("gText_LeagueChamp"))
      end
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, false
  end,
})

local function hofPcMembers(team)
  local list = {}
  for i = 1, 6 do
    local mon = team and team[i]
    if type(mon) == "table" and (tonumber(mon.species) or 0) ~= 0 then list[#list + 1] = mon end
  end
  return list
end

Special.hallOfFamePc = add({
  matches = layer("hall_of_fame_pc", "src.ui.game3.hall_of_fame_pc"),
  poll = function(state, memo, entering)
    local H = state.mod
    if H._corrupted then
      if memo.said and not entering then return nil end
      memo.said = true
      return say(rom("gText_HOFCorrupted")), true
    end
    local team = H._teams and H._teams[H._team]
    local members = hofPcMembers(team)
    local teamChanged = entering or H._team ~= memo.team
    if not teamChanged and H._mon == memo.mon then return nil end
    memo.team, memo.mon = H._team, H._mon
    local parts = {}
    if teamChanged then
      parts[#parts + 1] = say(rom("gText_HOFNumber", { stringVars = { tostring(H._number) } }))
    end
    local mon = members[H._mon or 1]
    if mon then
      local sp = tonumber(mon.species) or 0
      local P = pokemonModule()
      local dex = (P and try(P.national, sp)) or sp
      local number = (not H._national and dex > 151) and "???" or string.format("%03d", dex)
      parts[#parts + 1] = memberCard(mon, mon.nickname, number, mon.trainerId)
        .. ", " .. position(H._mon or 1, #members)
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
})

Special.diploma = add({
  matches = layer("diploma", "src.ui.game3.diploma"),
  poll = function(state, memo, entering)
    local D = state.mod
    if memo.said and not entering then return nil end
    if not D.open then return nil end
    memo.said = true
    local text = sentences({ say(D._player), say(D._body), say(D._gameFreak) })
    if text == "" then return nil end
    return text, true
  end,
})

-- Credits (src/ui/game3/credits.lua, Credits.state()): each title and name
-- block once its names arrive, the starter Pokémon scenes, and the closing
-- pictures (copyright, THE END) as words.
Special.credits = add({
  matches = layer("credits", "src.ui.game3.credits"),
  poll = function(state, memo)
    local C = state.mod
    local s = try(C.state)
    if type(s) ~= "table" then return nil end
    local parts = {}
    local t = s.text
    if type(t) == "table" and (t.names or t.staff) and t ~= memo.text then
      memo.text = t
      -- one role or name per drawn line, so lines are kept apart by commas
      parts[#parts + 1] = say(table.concat(Common.lines(t.title), ", "))
      if t.names then parts[#parts + 1] = say(table.concat(Common.lines(t.names), ", ")) end
    end
    local mon = s.mon
    if mon ~= memo.mon then
      memo.mon = mon
      local species = type(mon) == "table" and mon.def and mon.def.species
      local name = speciesName(species)
      if name then parts[#parts + 1] = say(name) end
    end
    local closing = type(s.closing) == "table" and s.closing.shown and s.closing or nil
    if closing ~= memo.closing then
      memo.closing = closing
      if closing then parts[#parts + 1] = (s.whichMon == 0) and "Copyright" or "THE END" end
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, false
  end,
})

-- Whiteout ("scurried to a POKéMON CENTER"): once the text starts printing.
Special.whiteoutRush = add({
  matches = layer("whiteout_rush", "src.ui.game3.whiteout_rush"),
  poll = function(state, memo)
    local Rush = state.mod
    local st = Rush._state
    if type(st) ~= "table" or st.phase == "hold" or memo.said then return nil end
    memo.said = true
    return say(st.text), true
  end,
})

-- ================================================================ mod manager

-- The Gen 3 mod manager wraps the shared ManagerState (ModManager._mgr), so
-- the Gen 1 presenter's poll reads it; the quantity prompt is Gen 3's own.
Special.modManager = add({
  matches = layer("mod_manager", "src.ui.game3.mod_manager"),
  poll = function(state, memo, entering)
    local M = state.mod
    local prompt = M._prompt
    if prompt then
      if prompt ~= memo.prompt or prompt.value ~= memo.value then
        local opened = prompt ~= memo.prompt
        memo.prompt, memo.value = prompt, prompt.value
        local text = tostring(prompt.value)
        if opened then text = say(prompt.title) .. " " .. text .. ", up to " .. tostring(prompt.max) end
        return text, true
      end
      return nil
    end
    local returning = memo.prompt ~= nil
    memo.prompt = nil
    local mgr = M._mgr
    if not mgr then return nil end
    local Extra = loaded("src.access.screens.ExtraScreens")
    if not (Extra and Extra.modManager) then return nil end
    if memo.mgr ~= mgr then memo.mgr, memo.inner = mgr, {} end
    return Extra.modManager.poll(mgr, memo.inner, entering or returning)
  end,
})

-- ================================================================ wireless minigames

local function minigameText(key, ctx)
  return say(rom(key, ctx))
end

-- Lobby (src/ui/game3/minigames/common_lobby.lua): the leader's member list
-- with the mode text, or the joiner's group list.
Special.minigameLobby = add({
  matches = layer("minigame_lobby", "src.ui.game3.minigames.common_lobby"),
  poll = function(state, memo, entering)
    local L = state.mod
    local parts = {}
    local message = try(L.message)
    if entering or message ~= memo.message then
      memo.message = message
      parts[#parts + 1] = say(message)
    end
    local players = L.players or {}
    if L.mode == "leader" then
      local count = #players
      if entering or count ~= memo.count then
        local names = {}
        for _, p in ipairs(players) do names[#names + 1] = say(p.name) end
        if memo.count and count > memo.count then parts[#parts + 1] = names[#names] .. " joined" end
        memo.count = count
        parts[#parts + 1] = say(try(L.modeText))
        if entering then
          local me = L.me or {}
          local list = { say(me.name) }
          for _, n in ipairs(names) do list[#list + 1] = n end
          parts[#parts + 1] = table.concat(list, ", ")
        end
      end
    else
      local cursor = L.cursor or 1
      local row = players[cursor]
      if entering or cursor ~= memo.cursor or #players ~= memo.count then
        memo.cursor, memo.count = cursor, #players
        if row then
          local text = say(row.name)
          if row.trainerId ~= nil then text = text .. ", " .. idText(row.trainerId) end
          parts[#parts + 1] = text .. ", " .. position(cursor, #players)
        else
          parts[#parts + 1] = "empty"
        end
      end
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
})

-- Pokémon Jump's message window and yes/no (core gfx).
local function jumpMessage(sim, memo, parts)
  local g = sim.game
  local gfx = g and g.gfx
  if not gfx then return end
  local w = gfx.msgWindow
  local shown = w and w.shown and w or nil
  if shown ~= memo.jumpMsg then
    memo.jumpMsg = shown
    if shown then
      if shown.itemId then
        local Items = loaded("src.core.game3.items")
        local item = Items and try(Items.displayName, shown.itemId)
        parts[#parts + 1] = say(item) .. (shown.quantity and (" times " .. tostring(shown.quantity)) or "")
      else
        parts[#parts + 1] = minigameText(shown.key)
      end
    end
  end
  local yn = gfx.yesno
  local cursor = yn and yn.cursor
  if yn ~= memo.jumpYn or cursor ~= memo.jumpYnCursor then
    memo.jumpYn, memo.jumpYnCursor = yn, cursor
    if yn then parts[#parts + 1] = yesNo(cursor == 0) end
  end
end

-- Dodrio Berry Picking's results pages (core sim.rs).
local function dodrioResults(sim, memo, parts)
  local rs = sim.rs
  if type(rs) ~= "table" then
    memo.dodrioShow = nil
    return
  end
  local show = rs.show
  if show ~= memo.dodrioShow then
    memo.dodrioShow = show
    local R = loaded("src.core.game3.minigames.dodrio_berry_picking.rules")
    local Draw = loaded("src.ui.game3.minigames.dodrio_berry_picking.draw")
    if show == "results" and R then
      parts[#parts + 1] = minigameText("gText_BerryPickingResults")
      local header = {}
      for word in tostring(rom("gText_10P30P50P50P") or ""):gmatch("%S+") do header[#header + 1] = word end
      for p = 0, (sim.n or 0) - 1 do
        local cells = { say((sim.names or {})[p] or "") }
        for j = 0, 3 do
          local label = (j == R.BERRY_MISSED) and "missed" or header[j + 1] or ""
          local value = math.min(((rs.res or {})[p] or {})[j] or 0, R.MAX_BERRIES or 9999)
          cells[#cells + 1] = (label ~= "" and (label .. " ") or "") .. tostring(value)
        end
        parts[#parts + 1] = table.concat(cells, ", ")
      end
    elseif show == "rankings" then
      parts[#parts + 1] = minigameText("gText_AnnouncingRankings")
      for _, row in ipairs(rs.rows or {}) do
        local rank = Draw and Draw.RANK_TEXTS and (Draw.RANK_TEXTS[(row.ranking or 0) + 1] or Draw.RANK_TEXTS[5])
        parts[#parts + 1] = sentences({ minigameText(rank), say((sim.names or {})[row.player] or "") })
          .. ", " .. tostring(row.score or 0) .. " " .. minigameText("gText_SpacePoints")
      end
    elseif show == "prize" and R then
      local Items = loaded("src.core.game3.items")
      local item = try(R.prizeItem, rs.prize)
      local name = Items and try(Items.displayName, item) or ""
      parts[#parts + 1] = minigameText("gText_AnnouncingPrizes")
      parts[#parts + 1] = minigameText("gText_FirstPlacePrize", { dynamic = { [0] = name } })
      if rs.prizeState == R.PRIZE_NO_ROOM then
        parts[#parts + 1] = minigameText("gText_CantHoldAnyMore", { dynamic = { [0] = name } })
      elseif rs.prizeState == R.PRIZE_FILLED_BAG then
        parts[#parts + 1] = minigameText("gText_FilledStorageSpace", { dynamic = { [0] = name } })
      end
    elseif show == "standby" then
      parts[#parts + 1] = minigameText("gText_CommunicationStandby3")
    elseif show == "saving" then
      parts[#parts + 1] = minigameText("gText_SavingDontTurnOffThePower2")
    elseif show == "ask" then
      memo.dodrioCursor = rs.cursor
      parts[#parts + 1] = minigameText("gText_WantToPlayAgain")
      parts[#parts + 1] = yesNo(rs.cursor ~= 2)
    elseif show == "dropped" then
      parts[#parts + 1] = minigameText("gText_SomeoneDroppedOut")
    end
  elseif show == "ask" and rs.cursor ~= memo.dodrioCursor then
    memo.dodrioCursor = rs.cursor
    parts[#parts + 1] = yesNo(rs.cursor ~= 2)
  end
end

-- Berry Crush's printer pages, results pages and yes/no (core sim).
local function crushPages(sim, memo, parts)
  local printer = sim.printer
  if type(printer) == "table" then
    local page = try(printer.text, printer)
    if printer ~= memo.printer or page ~= memo.printerPage then
      memo.printer, memo.printerPage = printer, page
      parts[#parts + 1] = say(page)
    end
  else
    memo.printer, memo.printerPage = nil, nil
  end
  if sim.stage == "results" and type(sim.res) == "table" then
    local page = sim.res.page
    if page ~= memo.crushPage then
      memo.crushPage = page
      local View = loaded("src.ui.game3.minigames.berry_crush.view")
      local lines = View and try(View.buildPage, sim, page)
      if type(lines) == "table" then
        local out, i = {}, 1
        while i <= #lines do
          local line, nextLine = lines[i], lines[i + 1]
          if nextLine and nextLine.y == line.y then
            out[#out + 1] = say(line.text) .. ", " .. say(nextLine.text)
            i = i + 2
          else
            out[#out + 1] = say(line.text)
            i = i + 1
          end
        end
        parts[#parts + 1] = sentences(out)
      end
    end
  else
    memo.crushPage = nil
  end
  local yn = sim.yesNo
  if yn ~= memo.crushYn then
    memo.crushYn = yn
    if yn ~= nil then parts[#parts + 1] = yesNo(yn == 0) end
  end
end

Special.minigame = add({
  matches = layer("minigame", "src.core.game3.minigames.common"),
  poll = function(state, memo)
    local MG = state.mod
    local run = MG._run
    if type(run) ~= "table" then return nil end
    local parts = {}
    local m = run.match
    local message = run.stage == "message" and (run.text or MG.ERROR_TEXT) or nil
    if message ~= memo.message then
      memo.message = message
      if message then parts[#parts + 1] = minigameText(message) end
    end
    local phase = m and m.phase
    if phase ~= memo.phase then
      memo.phase = phase
      if phase == "ready" then parts[#parts + 1] = minigameText(MG.STANDBY_TEXT) end
    end
    local cd = m and phase == "countdown" and m.countdown
    if type(cd) == "table" then
      local digit = try(cd.digitShown, cd)
      local mark = digit or (cd.state == 2 and "start") or nil
      if mark ~= memo.countdown then
        memo.countdown = mark
        if digit then parts[#parts + 1] = tostring(digit)
        elseif mark == "start" then parts[#parts + 1] = "Start" end
      end
    else
      memo.countdown = nil
    end
    local sim = m and m.sim
    if type(sim) == "table" then
      if sim.game and sim.game.gfx then jumpMessage(sim, memo, parts) end
      if sim.rs ~= nil or memo.dodrioShow ~= nil then dodrioResults(sim, memo, parts) end
      if sim.printer ~= nil or sim.res ~= nil or sim.yesNo ~= nil or memo.printer then crushPages(sim, memo, parts) end
    end
    local text = sentences(parts)
    if text == "" then return nil end
    return text, true
  end,
})

-- ================================================================ overlays

-- Braille (src/ui/game3/braille.lua): the dialogue box shows dot cells; the
-- script's plain text is Braille._text.  Said once per message as
-- "Braille:" and the text (agent default; the original Pokémon Access spelt
-- each cell's dot numbers instead).  The dialogue presenter leaves braille
-- pages to this one.
local brailleKeys = setmetatable({}, { __mode = "k" })

Special.braille = add({
  matches = kindOnly("braille"),
  poll = function(state, memo)
    if memo.said then return nil end
    memo.said = true
    local Braille = state.mod
    local body = Braille and Braille._text
    if not nonEmpty(body) then
      local Message = loaded("src.ui.game3.message")
      body = Message and type(Message._pages) == "table" and table.concat(Message._pages, "\n") or nil
    end
    local text = say(body)
    if text == "" then return nil end
    return "Braille: " .. text, false
  end,
})

ambient(function(_, proxy)
  local Message = loaded("src.ui.game3.message")
  if not (Message and Message.open and Message._frame == "braille" and type(Message._pages) == "table") then
    return nil
  end
  local key = brailleKeys[Message._pages]
  if not key then
    key = {}
    brailleKeys[Message._pages] = key
  end
  return proxy(key, "braille", { mod = loaded("src.ui.game3.braille") })
end)

-- Seagallop crossing: a wordless cutscene; its destination once.
Special.seagallop = add({
  matches = kindOnly("seagallop"),
  poll = function(state, memo)
    if memo.said then return nil end
    memo.said = true
    local run = state.key
    local dest = romAt("sSeagallopDestStrings", run.dest)
    return "SEAGALLOP to " .. say(dest or "?"), false
  end,
})

ambient(function(_, proxy)
  local Sea = loaded("src.ui.game3.seagallop")
  local run = Sea and Sea._active and Sea._run
  if type(run) ~= "table" then return nil end
  return proxy(run, "seagallop", { mod = Sea })
end)

-- Pokémon picture box (showmonpic) and the Pewter Museum fossil pictures.
Special.picture = add({
  matches = kindOnly("picture"),
  poll = function(state, memo)
    if memo.said then return nil end
    memo.said = true
    local name = speciesName(state.species)
    if not name then return nil end
    if state.fossil then return "Picture of a " .. say(name) .. " fossil", false end
    return "Picture: " .. say(name), false
  end,
})

ambient(function(_, proxy)
  local Pic = loaded("src.ui.game3.mon_pic")
  if not (Pic and Pic.active == true) then
    tokens.mon_pic = nil
    return nil
  end
  -- a new token per showing, and when a new picture replaces the old one
  local key = tokens.mon_pic
  if not key or key.species ~= Pic.species then
    key = { species = Pic.species }
    tokens.mon_pic = key
  end
  return proxy(key, "picture", { species = Pic.species })
end)

ambient(function(_, proxy)
  local Space = loaded("src.core.game3.scripting.space")
  local ctx = Space and Space.vm and Space.vm.ctx
  local pic = type(ctx) == "table" and ctx.museumFossilPic or nil
  if type(pic) ~= "table" then return nil end
  return proxy(pic, "picture", { species = pic.species, fossil = true })
end)

-- Covered by the other Gen 3 presenters, so not repeated here: the forest
-- title card (Menus, with the map name popup, said once per new name),
-- the release sequence (Items, inside box storage) and the level-up
-- window (Battle in battle, Items in the party menu).

-- Itemfinder: the arrow points along the larger offset to the nearest
-- hidden item (the screen shows nothing more exact).
Special.itemfinder = add({
  matches = kindOnly("itemfinder"),
  poll = function(state, memo)
    if memo.said then return nil end
    memo.said = true
    local result = state.key.result
    if type(result) ~= "table" or result.underfoot then return nil end
    local x, y = tonumber(result.itemX) or 0, tonumber(result.itemY) or 0
    if x == 0 and y == 0 then return nil end
    local dir
    if math.abs(x) > math.abs(y) then dir = x < 0 and "left" or "right"
    else dir = y < 0 and "up" or "down" end
    return "Itemfinder points " .. dir, false
  end,
})

ambient(function(_, proxy)
  local F = loaded("src.core.game3.itemfinder")
  local task = F and F._task
  if type(task) ~= "table" then return nil end
  return proxy(task, "itemfinder", {})
end)

-- VS Seeker: the trainers' emotes are the only result when some respond.
-- The use sequence keeps its result in the queued event's `seq` (read by
-- name from the event's tick function).
local function upvalue(fn, name)
  if type(fn) ~= "function" or not (debug and debug.getupvalue) then return nil end
  for i = 1, 255 do
    local upName, value = debug.getupvalue(fn, i)
    if upName == nil then return nil end
    if upName == name then return value end
  end
  return nil
end

Special.vsSeeker = add({
  matches = kindOnly("vs_seeker"),
  poll = function(state, memo)
    if memo.said then return nil end
    local seq = upvalue(state.key.tick, "seq")
    if type(seq) ~= "table" or seq.response == nil then return nil end
    memo.said = true
    local V = loaded("src.core.game3.vs_seeker") or {}
    if seq.response == V.RESPONSE_FOUND_REMATCHES then
      local n = #(seq.responders or {})
      return string.format(n == 1 and "VS Seeker: %d trainer wants a rematch" or
        "VS Seeker: %d trainers want a rematch", n), false
    elseif seq.response == V.RESPONSE_UNFOUGHT_TRAINERS then
      return "VS Seeker: no rematches; trainers here have not battled you yet", false
    end
    return nil
  end,
})

ambient(function(_, proxy)
  local Events = loaded("src.core.game3.step_events")
  local ev = Events and Events._activeEvent
  if type(ev) ~= "table" or ev.type ~= "vs_seeker" then return nil end
  return proxy(ev, "vs_seeker", {})
end)

-- Online arena (a port addition, game.phase "arena"): its standby or
-- failure message, which gen3/Top.lua does not report as a screen.
Special.arena = add({
  matches = kindOnly("arena"),
  poll = function(state, memo)
    local arena = state.key
    local message = (arena.stage ~= "leaving" and arena.stage ~= "battle") and arena.message or nil
    if message == memo.message then return nil end
    memo.message = message
    if not message then return nil end
    return say(message), false
  end,
})

ambient(function(game, proxy)
  if type(game) ~= "table" or game.phase ~= "arena" or type(game.arena) ~= "table" then return nil end
  return proxy(game.arena, "arena", { game = game })
end)

Special.ordered = ordered

-- Test hooks: the pure line and chart wording.
Special._lineName = lineName
Special._betLines = betLines
Special._chartText = chartText

return Special
