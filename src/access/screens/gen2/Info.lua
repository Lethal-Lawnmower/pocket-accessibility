-- Gen 2 presenters (decision 27): party list, summary, Pokédex, Pokégear
-- (card strip, clock, map, phone, radio, fly map, town map), the caller-ID
-- box of an incoming call, house radios and the trainer card.
--
-- Same matches/poll contract as src/access/screens/Presenters.lua.  Every
-- presenter reads fields of the upstream screen under src/ui/gen2/ and calls
-- only read-only methods, always through pcall (`call` below).  Methods that
-- would change game state are never called: the radio is read from the
-- screen's own `radio` record, never through Pokegear:ensureTuned or
-- tuneRadio, and the Unown list is read from the save field rather than
-- through Unown.dex (which creates it).  The fields read are listed in
-- docs/access/architecture.md's hook list.
--
-- Labels the screens draw from local tables are reached through their own
-- public records (PartyMenu.PROMPTS, Pokegear.PHONE_SUBMENUS,
-- PokedexMenu.OPTION_MODES, TrainerCard.JOHTO_BADGES ...) and translated
-- through src/core/Strings.lua the way the draw code does.  A handful of
-- draw-only strings (CANCEL, AM/PM, "Where?", the dex action bar) are looked
-- up by the same English source string the draw code passes to Strings.

local Common = require("src.access.screens.gen2.Common")

local Info = {}

local speakable, position = Common.speakable, Common.position

local function class(name)
  return package.loaded["src.ui.gen2." .. name]
end

-- Joins the non-empty parts with `sep` (default ", ").  Parts may be nil,
-- so walk to table.maxn instead of stopping at the first hole.
local function join(parts, sep)
  local out = {}
  for i = 1, table.maxn(parts) do
    local part = parts[i]
    if part ~= nil and part ~= "" then out[#out + 1] = tostring(part) end
  end
  return table.concat(out, sep or ", ")
end

-- Joins sentences with ". ", without doubling the stop when a part already
-- ends in one ("...cheeks." then "PAGE").
local function sentences(parts)
  local out = ""
  for i = 1, table.maxn(parts) do
    local part = parts[i]
    if part ~= nil and part ~= "" then
      part = tostring(part)
      if out == "" then
        out = part
      elseif out:find("[%.!?]$") then
        out = out .. " " .. part
      else
        out = out .. ". " .. part
      end
    end
  end
  return out
end

-- Text whose lines are joined with <NEXT> (dex entries, move descriptions),
-- read as one sentence with words split across lines rejoined
-- ("electric-" / "ity"), as Common.lines does for dialogue.
local function nextLines(text)
  local lines = {}
  for line in (tostring(text or "") .. "<NEXT>"):gmatch("(.-)<NEXT>") do
    if line ~= "" then lines[#lines + 1] = line end
  end
  return Common.lines(lines)
end

local function count(n, singular, plural)
  return string.format("%d %s", n, n == 1 and singular or plural)
end

-- An engine string translated the way the screen translates it
-- (src/core/Strings.lua is an identity function until a translation loads).
local function tr(source, ...)
  if source == nil then return nil end
  local Strings = package.loaded["src.core.Strings"]
  if Strings == nil then return source end
  local ok, text = pcall(Strings, source, ...)
  if ok and type(text) == "string" then return text end
  return source
end

-- A read-only method of the screen, through pcall.  Nil when it is missing
-- or fails, so an unreadable value stays silent instead of being guessed.
local function call(state, method, ...)
  local fn = state and state[method]
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, state, ...)
  if not ok then return nil end
  return a, b, c
end

local function gameData(state)
  return (state.game and state.game.data) or {}
end

-- src/ui/LevelDisplay.lua: a mod may hide levels on a surface.  Default true.
local function levelVisible(mon, where, game)
  local LevelDisplay = package.loaded["src.ui.LevelDisplay"]
  if not LevelDisplay then return true end
  local ok, visible = pcall(LevelDisplay.visible, mon, where, game)
  return not ok or visible ~= false
end

-- Landmark names carry a line break ("NEW BARK\nTOWN"); the Pokegear's own
-- flatName turns it into a space for the radio, and so does speech.
local function flatName(name)
  if name == nil then return nil end
  return speakable((tostring(name):gsub("\n", " ")))
end

-- --------------------------------------------------------------- party

local function speciesName(state, mon)
  local defs = state.pokemon or gameData(state).pokemon
  local def = defs and defs[mon.species]
  return def and def.name
end

-- One row as PartyMenu:drawPanel writes it, from the screen's own
-- PartyMenu.rowFor (name, status, level) and tmhmAble (ABLE / NOT ABLE).
-- The species is added when it differs from the nickname, and the held-item
-- marker on the icon (PartyMenu.heldMarkerRow: 0 mail, 1 item) as words.
-- The list draws no gender.  An EGG row is the word EGG alone, as drawn.
local function partyRow(state, index)
  local party = state.party or {}
  if index > #party then
    -- drawPanel prints actionLabel("CANCEL") one row past the last mon
    return speakable(tr("CANCEL"))
  end
  local mon = party[index]
  local PartyMenu = class("PartyMenu")
  if type(mon) ~= "table" or not PartyMenu then return nil end
  local hp = call(state, "shownHpFor", index, mon)
  if hp == nil then hp = mon.hp end
  local ok, row = pcall(PartyMenu.rowFor, mon, hp, gameData(state).gen2Statuses)
  if not ok or type(row) ~= "table" then return nil end
  local name = speakable(row.name)
  if mon.isEgg then return name end
  local parts = { name }
  local species = speciesName(state, mon)
  if species and speakable(species) ~= name then parts[#parts + 1] = speakable(species) end
  if row.level and levelVisible(mon, "party", state.game) then
    parts[#parts + 1] = speakable(row.level)
  end
  if state.tmhm then
    local able = call(state, "tmhmAble", mon)
    if able then parts[#parts + 1] = speakable(able):lower() end
  else
    local maxHp = mon.maxHp or (mon.stats and mon.stats.hp)
    if hp and maxHp then parts[#parts + 1] = string.format("HP %d of %d", hp, maxHp) end
  end
  if (hp or 0) <= 0 then
    parts[#parts + 1] = "fainted"
  elseif row.status then
    parts[#parts + 1] = speakable(row.status)
  end
  local okMarker, marker = pcall(PartyMenu.heldMarkerRow, mon)
  if okMarker and marker == 0 then
    parts[#parts + 1] = "holding mail"
  elseif okMarker and marker == 1 then
    parts[#parts + 1] = "holding an item"
  end
  return join(parts)
end
Info.partyRow = partyRow

-- The bottom prompt, chosen the way drawPanel chooses it.
local function partyPrompt(state)
  local PartyMenu = class("PartyMenu")
  local prompts = (PartyMenu and PartyMenu.PROMPTS) or {}
  local text
  if #(state.party or {}) == 0 then
    text = tr(prompts.none)
  elseif state.switchFrom then
    text = tr(prompts.moveTo)
  elseif state.softboiledFrom then
    text = tr(prompts.useItem)
  elseif state.promptIsBuiltin then
    text = tr(state.prompt)
  else
    text = state.prompt
  end
  return text and speakable(text) or nil
end

local function submenuText(menu, first)
  local item = menu.items and menu.items[menu.index]
  if type(item) ~= "table" then return nil end
  local text = speakable(item.label or item.id)
  if first then text = join({ text, position(menu.index, #menu.items) }) end
  return text
end

-- PartyMenu (src/ui/gen2/PartyMenu.lua): rows, the action submenu, the
-- SWITCH and SOFTBOILED picks, and itemResult messages (shown once the HP
-- climb has finished, as drawPanel does).
Info.partyMenu = {
  matches = Common.matcher("PartyMenu"),
  poll = function(state, memo, entering)
    local sub = state.submenu
    local subIndex = sub and sub.index
    local result = state.itemResult
    if result and (not result.text or call(state, "itemResultClimbing")) then result = nil end
    if not entering and memo.index == state.index and memo.sub == sub
        and memo.subIndex == subIndex and memo.switch == state.switchFrom
        and memo.soft == state.softboiledFrom and memo.result == result then
      return nil
    end
    local total = call(state, "count") or (#(state.party or {}) + 1)
    local function rowWithPosition()
      local row = partyRow(state, state.index)
      return row and join({ row, position(state.index, total) }) or nil
    end
    local text
    if entering then
      text = join({ result and speakable(result.text) or partyPrompt(state), rowWithPosition() }, " ")
      if sub then text = join({ text, submenuText(sub, true) }, ". ") end
    elseif result and result ~= memo.result then
      text = speakable(result.text)
    elseif sub and sub ~= memo.sub then
      text = submenuText(sub, true)
    elseif sub and subIndex ~= memo.subIndex then
      text = submenuText(sub)
    elseif state.switchFrom and state.switchFrom ~= memo.switch
        or state.softboiledFrom and state.softboiledFrom ~= memo.soft then
      text = join({ partyPrompt(state), rowWithPosition() }, " ")
    elseif (memo.switch and not state.switchFrom) or (memo.soft and not state.softboiledFrom)
        or (memo.sub and not sub) then
      -- back on the plain list (a switch made, a pick cancelled): the row
      -- under the cursor now, with its position
      text = rowWithPosition()
    else
      text = partyRow(state, state.index)
    end
    memo.index, memo.sub, memo.subIndex = state.index, sub, subIndex
    memo.switch, memo.soft, memo.result = state.switchFrom, state.softboiledFrom, result
    if not text or text == "" then return nil end
    return text, true
  end,
}

-- ------------------------------------------------------------- summary

local function typeText(state)
  local first, second = call(state, "typeNames")
  if not first then return nil end
  return "type " .. join({ speakable(first), second and speakable(second) or nil }, " and ")
end

-- One move: name, type, PP.  A missing PP count means full (Mon.repairMoves
-- fills it from the maximum); only an explicit 0 is "used up".  When the
-- maximum is unknown too, PP is left out rather than read as 0.
local function moveRowText(state, entry, withType)
  if type(entry) ~= "table" then return nil end
  local name = call(state, "moveName", entry) or entry.id
  local def = call(state, "moveDef", entry.id) or {}
  local data = gameData(state)
  local parts = { speakable(name) }
  if withType and def.type then
    local TypeChart = package.loaded["src.battle.TypeChart"]
    local ok, typeName = pcall(TypeChart.displayName, def.type, data)
    parts[#parts + 1] = speakable(ok and typeName or def.type)
  end
  local Mon = package.loaded["src.battle.gen2.Mon"]
  local okMax, maxPp = false, nil
  if Mon then okMax, maxPp = pcall(Mon.maxPpOf, entry, data) end
  if okMax and type(maxPp) == "number" and maxPp > 0 then
    local pp = tonumber(entry.pp) or maxPp
    parts[#parts + 1] = string.format("PP %d of %d", pp, maxPp)
  end
  return join(parts)
end

-- The upper half: nickname, species, dex number, level, gender, shiny mark
-- (StatsScreen_InitUpperHalf, SummaryMenu:upperPlacements, drawUpperHalf).
local function summaryHeader(state)
  local mon = state.mon
  local def = call(state, "speciesDef") or {}
  local name = speakable(mon.nickname or mon.name or mon.species)
  local species = def.name and speakable(def.name) or nil
  return join({ name, species ~= name and species or nil,
    def.dex and ("number " .. tostring(def.dex)) or nil,
    levelVisible(mon, "summary", state.game) and ("level " .. tostring(mon.level or 1)) or nil,
    (mon.gender == "male" or mon.gender == "female") and mon.gender or nil,
    mon.shiny and "shiny" or nil })
end

-- Pink page: HP, status (or POKéRUS) and type, experience and the gap to the
-- next level.  Status comes from the page's own placements
-- (SummaryMenu:pinkPlacements writes POKéRUS at (1,13), otherwise the
-- status or OK at (6,13)), so it is the string the page shows.
local function pinkText(state)
  local mon = state.mon
  local SummaryMenu = class("SummaryMenu")
  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp)
  local parts = { maxHp and string.format("HP %d of %d", mon.hp or 0, maxHp) or nil }
  local placements = call(state, "pinkPlacements")
  if placements and SummaryMenu and SummaryMenu.at then
    local pokerus = SummaryMenu.at(placements, 1, 13)
    local status = SummaryMenu.at(placements, 6, 13)
    if (mon.hp or 0) <= 0 then
      parts[#parts + 1] = "fainted"
    elseif pokerus or status then
      parts[#parts + 1] = "status " .. speakable(pokerus or status)
    end
  end
  parts[#parts + 1] = typeText(state)
  parts[#parts + 1] = "experience " .. tostring(mon.experience or 0)
  local level = mon.level or 1
  if level < 100 and levelVisible(mon, "summary", state.game) then
    local toNext = call(state, "expToNext")
    if toNext then parts[#parts + 1] = string.format("%d to level %d", toNext, level + 1) end
  end
  return join(parts)
end

-- Green page: held item and the moves with type and PP.
local function greenText(state)
  local item = call(state, "itemName")
  local moves = call(state, "moveList") or {}
  local rows = {}
  for slot = 1, 4 do
    local row = moveRowText(state, moves[slot], true)
    if row then rows[#rows + 1] = row end
  end
  return join({ "item " .. (item and speakable(item) or "none"),
    #rows > 0 and ("moves: " .. table.concat(rows, "; ")) or "no moves" })
end

-- Blue page: ID and OT, then the five stats (PrintTempMonStats' order).
local function blueText(state)
  local mon = state.mon
  local stats = mon.stats or {}
  local function stat(label, key)
    return stats[key] ~= nil and (label .. " " .. tostring(stats[key])) or nil
  end
  local id = call(state, "otId")
  local ot = call(state, "otName")
  return join({ id and ("ID " .. tostring(id)) or nil, ot and ("OT " .. speakable(ot)) or nil,
    stat("attack", "attack"), stat("defense", "defense"),
    stat("special attack", "specialAttack"), stat("special defense", "specialDefense"),
    stat("speed", "speed") })
end

local function summaryPage(state)
  local SummaryMenu = class("SummaryMenu") or {}
  local page = state.page
  local text
  if page == SummaryMenu.GREEN_PAGE then
    text = greenText(state)
  elseif page == SummaryMenu.BLUE_PAGE then
    text = blueText(state)
  else
    text = pinkText(state)
  end
  return join({ text, "page " .. position(page or 1, SummaryMenu.NUM_STAT_PAGES or 3) })
end

-- The egg page (EggStatsScreen): EGG and the hatch flavour text.  The ID
-- and OT read ?????, which says nothing, so they are left out.  The flavour
-- lines are the placements from row 9 down (SummaryMenu:eggPlacements
-- starts them at ty = 9).
local function eggText(state)
  local placements = call(state, "eggPlacements") or {}
  local lines = {}
  for _, entry in ipairs(placements) do
    if (entry.y or 0) >= 9 then lines[#lines + 1] = entry.text end
  end
  return join({ speakable(tr("EGG")), Common.lines(lines) }, ". ")
end

-- The move screen (MoveScreenLoop / moveDetailPlacements): the move under
-- the cursor with its type, power and description.  While a move is held
-- the data half reads "Where?", so only name and PP are said then.
local function detailRow(state, withPosition)
  local moves = call(state, "moveList") or {}
  local entry = moves[state.moveIndex]
  if type(entry) ~= "table" then return nil end
  local parts = { moveRowText(state, entry, false) }
  local description
  if not state.swapFrom then
    local def = call(state, "moveDef", entry.id) or {}
    if def.type then
      local TypeChart = package.loaded["src.battle.TypeChart"]
      local ok, typeName = pcall(TypeChart.displayName, def.type, gameData(state))
      parts[#parts + 1] = "type " .. speakable(ok and typeName or def.type)
    end
    -- a power of 0 or 1 prints "---" (no power): left out
    if (def.power or 0) >= 2 then parts[#parts + 1] = "power " .. tostring(def.power) end
    if def.description then description = nextLines(def.description) end
  end
  if withPosition then parts[#parts + 1] = position(state.moveIndex, math.max(1, #moves)) end
  return join({ join(parts), description }, ". ")
end

local function detailHeader(state)
  local mon = state.mon
  local name = speakable(mon.nickname or mon.name or mon.species)
  if levelVisible(mon, "summary", state.game) then
    return name .. ", level " .. tostring(mon.level or 1)
  end
  return name
end

-- SummaryMenu (src/ui/gen2/SummaryMenu.lua): three pages, the egg page,
-- the move screen with its reorder ("Where?").
Info.summaryMenu = {
  matches = Common.matcher("SummaryMenu"),
  poll = function(state, memo, entering)
    local mon = state.mon
    if type(mon) ~= "table" then return nil end
    local detail = state.moveDetail and true or false
    local moves = mon.moves
    local moveAt = moves and moves[state.moveIndex]
    if not entering and memo.mon == mon and memo.page == state.page and memo.detail == detail
        and memo.moveIndex == state.moveIndex and memo.swap == state.swapFrom
        and memo.moveAt == moveAt then
      return nil
    end
    local text
    if mon.isEgg then
      if entering or memo.mon ~= mon then text = eggText(state) end
    elseif entering or memo.mon ~= mon then
      if detail then
        text = join({ detailHeader(state), detailRow(state, true) }, ". ")
      else
        text = join({ summaryHeader(state), summaryPage(state) }, ". ")
      end
    elseif detail ~= memo.detail then
      text = detail and detailRow(state, true) or summaryPage(state)
    elseif not detail and memo.page ~= state.page then
      text = summaryPage(state)
    elseif state.swapFrom and state.swapFrom ~= memo.swap then
      local held = moves and moves[state.swapFrom]
      text = join({ held and speakable(call(state, "moveName", held) or held.id) or nil,
        speakable(tr("Where?")) }, ". ")
    elseif memo.swap and not state.swapFrom then
      text = detailRow(state, true)
    elseif detail then
      text = detailRow(state, false)
    end
    memo.mon, memo.page, memo.detail = mon, state.page, detail
    memo.moveIndex, memo.swap, memo.moveAt = state.moveIndex, state.swapFrom, moveAt
    if not text or text == "" then return nil end
    return text, true
  end,
}

-- ------------------------------------------------------------- Pokédex

local function dexModeLabel(state)
  local PokedexMenu = class("PokedexMenu")
  local mode = call(state, "mode")
  for _, row in ipairs((PokedexMenu and PokedexMenu.OPTION_MODES) or {}) do
    if row.mode == mode then return speakable(tr(row.label)) end
  end
  return nil
end

-- A listing row as Pokedex_PrintListing draws it: the number only in OLD
-- mode, the name once seen (else "-----"), and the caught mark.
local function dexRow(state, row)
  if type(row) ~= "table" then return nil end
  local parts = {}
  if call(state, "mode") == "OLD" then parts[1] = tostring(row.dex or 0) end
  if row.seen then
    parts[#parts + 1] = speakable(call(state, "monName", row.species) or row.species)
    parts[#parts + 1] = row.caught and "owned" or "seen"
  else
    parts[#parts + 1] = "unknown"
  end
  return join(parts)
end

local function dexListRow(state)
  local rows = state.rows or {}
  local row = dexRow(state, rows[state.index])
  if not row then return "Empty" end
  return join({ row, position(state.index, #rows) })
end

local function dexListContext(state)
  local seen, caught = call(state, "totals")
  return join({ "Pokédex", dexModeLabel(state),
    (state.searchResults and state.rows == state.searchResults) and "search results" or nil,
    seen and string.format("seen %d, owned %d", seen, caught or 0) or nil })
end

local function dexEntry(state, row)
  return row and state.dex and state.dex.entries and state.dex.entries[row.species] or nil
end

-- The entry's description page.  drawEntryBody returns before the page
-- marker and the text when the mon is not caught, so nothing is said then.
local function dexPageText(state, row)
  local entry = dexEntry(state, row)
  if not (entry and row.caught) then return nil end
  local text = state.page == 2 and entry.text2 or entry.text
  if not text or text == "" then return nil end
  return nextLines(text)
end

-- Height and weight, only once caught (the page prints ?'?? and ???lb
-- before that).  `height` is feet and inches as one number (204 = 2'04")
-- and `weight` tenths of a pound, as drawEntryBody prints them.
local function dexSize(entry, row)
  if not (entry and row.caught) then return nil end
  if entry.heightM then
    return string.format("height %.1f meters, weight %.1f kilograms",
      entry.heightM, entry.weightKg or 0)
  end
  if entry.height then
    local feet, inches = math.floor(entry.height / 100), entry.height % 100
    return string.format("height %d feet %d inches, weight %.1f pounds",
      feet, inches, (entry.weight or 0) / 10)
  end
  return nil
end

-- The entry screen's action bar: the drawn words of ENTRY_ACTION_LABEL
-- (" PAGE AREA CRY PRNT"), and the one under the arrow (entryAction).
local function dexAction(state, withPosition)
  if state.newEntry then return nil end
  local words = {}
  for word in tr(" PAGE AREA CRY PRNT"):gmatch("%S+") do words[#words + 1] = word end
  local word = words[state.entryAction or 1]
  if not word then return nil end
  if withPosition then return join({ speakable(word), position(state.entryAction or 1, #words) }) end
  return speakable(word)
end

local function dexEntryIntro(state)
  local row = call(state, "current")
  if not row then return nil end
  local entry = dexEntry(state, row) or {}
  local header = join({ speakable(call(state, "monName", row.species) or row.species),
    entry.kind and speakable(entry.kind) or nil,
    entry.dex and ("number " .. tostring(entry.dex)) or nil, dexSize(entry, row) })
  -- The description goes last: a page often ends mid-sentence (the entry
  -- runs on to page 2), so nothing may follow it as if it had ended.
  return sentences({ header, dexAction(state, true), dexPageText(state, row) })
end

-- AREA: the title, the region shown, and every nest landmark in the
-- game's landmark order (Nests.find, the list drawArea marks).
local function dexAreaText(state)
  local row = call(state, "current")
  if not row then return nil end
  local name = call(state, "monName", row.species) or row.species
  local region = call(state, "areaRegionName") or "johto"
  local names = {}
  local Nests = package.loaded["src.core.gen2.Nests"]
  if Nests then
    local data = state.data or gameData(state)
    local ok, list = pcall(Nests.find, data, row.species, region, state.game and state.game.save)
    for _, index in ipairs(ok and list or {}) do
      local okMark, mark = pcall(Nests.landmark, data, index)
      if okMark and mark and mark.name then names[#names + 1] = flatName(mark.name) end
    end
  end
  return join({ speakable(tr("%s'S NEST", name)),
    region:sub(1, 1):upper() .. region:sub(2),
    #names > 0 and table.concat(names, ", ") or "none" }, ". ")
end

local function dexOptionRow(state, withPosition)
  local rows = call(state, "optionRows") or {}
  local row = rows[state.optionIndex]
  if not row then return nil end
  local lines = {}
  for i, line in ipairs(row.lines or {}) do lines[i] = tr(line) end
  local text = speakable(tr(row.label))
  if withPosition then text = join({ text, position(state.optionIndex, #rows) }) end
  -- the two-line description Pokedex_DisplayModeDescription prints under it
  return join({ text, Common.lines(lines) }, ". ")
end

-- The SEARCH screen's four rows, as drawSearch lays them out: TYPE1 and
-- TYPE2 with their wheel value, BEGIN SEARCH!! and CANCEL.
local function dexSearchValue(state, slot)
  local name = call(state, "searchTypeName", slot)
  if not name or name:match("^%-+$") then return "none" end
  return speakable(name)
end

local function dexSearchRow(state, withPosition)
  local index = state.searchIndex or 1
  local text
  if index == 1 then
    text = join({ speakable(tr("TYPE1")), dexSearchValue(state, 1) })
  elseif index == 2 then
    text = join({ speakable(tr("TYPE2")), dexSearchValue(state, 2) })
  elseif index == 3 then
    text = speakable(tr("BEGIN SEARCH!!"))
  else
    text = speakable(tr("CANCEL"))
  end
  if withPosition then text = join({ text, position(index, 4) }) end
  return text
end

-- UNOWN MODE: the form under the ring cursor and its word.  The list is the
-- save's unownDex field (Unown.dex would create it).
local function dexUnownRow(state, withPosition)
  local list = (state.save and state.save.unownDex) or {}
  local slot = (state.unownIndex or 0) + 1
  local letter = list[slot]
  if letter == nil then return nil end
  local Unown = package.loaded["src.core.gen2.Unown"]
  local name, word
  if Unown then
    local okName, n = pcall(Unown.name, letter)
    local okWord, w = pcall(Unown.word, letter)
    name, word = okName and n or nil, okWord and w or nil
  end
  local text = join({ name, word and speakable(word) or nil })
  if withPosition then text = join({ text, position(slot, #list) }) end
  return text
end

local function dexUnownTitle()
  local PokedexMenu = class("PokedexMenu")
  for _, row in ipairs((PokedexMenu and PokedexMenu.OPTION_MODES) or {}) do
    if row.unown then return speakable(tr(row.label)) end
  end
  return nil
end

-- PokedexMenu (src/ui/gen2/PokedexMenu.lua): listing, entry pages and
-- action bar, AREA, OPTION, SEARCH and UNOWN MODE, plus the two-page
-- new-entry view after a catch.
Info.pokedexMenu = {
  matches = Common.matcher("PokedexMenu"),
  poll = function(state, memo, entering)
    local view = state.view
    local types = state.searchType or {}
    if not entering and memo.view == view and memo.index == state.index
        and memo.page == state.page and memo.action == state.entryAction
        and memo.option == state.optionIndex and memo.search == state.searchIndex
        and memo.type1 == types[1] and memo.type2 == types[2]
        and memo.message == state.searchMessage and memo.unown == state.unownIndex
        and memo.region == state.areaRegion and memo.rows == state.rows then
      return nil
    end
    local first = not memo.seen
    local newView = memo.view ~= view
    local text
    if entering and not first and not newView then
      -- back from a screen above (PRNT's message box): the focus only
      if view == "list" then text = dexListRow(state)
      elseif view == "entry" then text = dexAction(state, true)
      elseif view == "area" then text = dexAreaText(state)
      elseif view == "option" then text = dexOptionRow(state, true)
      elseif view == "search" then text = dexSearchRow(state, true)
      elseif view == "unown" then text = dexUnownRow(state, true)
      end
    elseif view == "list" then
      if first or memo.rows ~= state.rows then
        text = join({ dexListContext(state), dexListRow(state) }, ". ")
      else
        text = dexListRow(state)
      end
    elseif view == "entry" then
      local row = call(state, "current")
      if first or (newView and memo.view ~= "area") then
        text = dexEntryIntro(state)
      elseif newView then
        text = dexAction(state, true)
      elseif memo.page ~= state.page then
        -- the page marker (P1 / P2) first, then that page's text
        text = sentences({ "page " .. position(state.page, 2), dexPageText(state, row) })
      elseif memo.action ~= state.entryAction then
        text = dexAction(state, true)
      end
    elseif view == "area" then
      if newView or memo.region ~= state.areaRegion then text = dexAreaText(state) end
    elseif view == "option" then
      if newView then
        text = join({ speakable(tr(" OPTION ")), dexOptionRow(state, true) }, ". ")
      elseif memo.option ~= state.optionIndex then
        text = dexOptionRow(state)
      end
    elseif view == "search" then
      if newView then
        text = join({ speakable(tr(" SEARCH ")), dexSearchRow(state, true) }, ". ")
      elseif state.searchMessage and state.searchMessage ~= memo.message then
        text = speakable(tr(state.searchMessage))
      elseif memo.search ~= state.searchIndex then
        text = dexSearchRow(state)
      elseif memo.type1 ~= types[1] then
        text = dexSearchValue(state, 1)
      elseif memo.type2 ~= types[2] then
        text = dexSearchValue(state, 2)
      end
    elseif view == "unown" then
      if newView then
        text = join({ dexUnownTitle(), dexUnownRow(state, true) }, ". ")
      elseif memo.unown ~= state.unownIndex then
        text = dexUnownRow(state)
      end
    end
    memo.seen, memo.view, memo.index, memo.page = true, view, state.index, state.page
    memo.action, memo.option, memo.search = state.entryAction, state.optionIndex, state.searchIndex
    memo.type1, memo.type2, memo.message = types[1], types[2], state.searchMessage
    memo.unown, memo.region, memo.rows = state.unownIndex, state.areaRegion, state.rows
    if not text or text == "" then return nil end
    return text, true
  end,
}

-- ----------------------------------------------------- radio (shared)

-- New radio lines since the last poll.  `radio.log` holds every line the
-- show has printed (src/ui/gen2/Pokegear.lua Radio:printLine); a retune
-- makes a new table.  The Pokemon Channel jingle rewrites the top line by
-- appending to it ("POKéMON" then "POKéMON  POKéMON"), so a line that
-- extends the previous one is said as its new part only.
local function newRadioLines(radio, memo)
  local log = type(radio) == "table" and radio.log or nil
  if type(log) ~= "table" then
    memo.radioLog, memo.radioCount, memo.radioLast = nil, 0, nil
    return nil
  end
  if log ~= memo.radioLog then
    memo.radioLog, memo.radioCount, memo.radioLast = log, 0, nil
  end
  local total = #log
  if total <= memo.radioCount then return nil end
  local out = {}
  for i = memo.radioCount + 1, total do
    local line = tostring(log[i] or "")
    local previous = memo.radioLast
    local said = line
    if previous and #line > #previous and line:sub(1, #previous) == previous then
      said = line:sub(#previous + 1)
    end
    memo.radioLast = line
    said = speakable(said)
    if said ~= "" then out[#out + 1] = said end
  end
  memo.radioCount = total
  if #out == 0 then return nil end
  return table.concat(out, " ")
end
Info.newRadioLines = newRadioLines

-- ------------------------------------------------------------ Pokégear

-- CLOCK card: weekday and time as Pokegear:drawClock prints them (12-hour,
-- AM/PM).  Read on entry only, so minute ticks are not announced.
local function clockText(state)
  local hour, minute, weekday = call(state, "clockParts")
  if type(hour) ~= "number" or type(minute) ~= "number" then return nil end
  local Clock = package.loaded["src.core.gen2.Clock"]
  local day
  if Clock and Clock.weekdayName then
    local ok, name = pcall(Clock.weekdayName, weekday)
    day = ok and name or nil
  end
  local display = hour % 12
  if display == 0 then display = 12 end
  return join({ day and speakable(day) or nil,
    string.format("%d:%02d %s", display, minute, speakable(tr(hour < 12 and "AM" or "PM"))) })
end

local function playerLandmarkIndex(state)
  local player = call(state, "playerLandmark")
  return type(player) == "table" and player.index or nil
end

-- MAP card and the town map: the landmark under the cursor, and "you are
-- here" when it is the player's own (the walking icon's landmark).
local function mapText(state)
  local landmark = call(state, "mapLandmark")
  if type(landmark) ~= "table" or not landmark.name then return nil end
  local here = landmark.index ~= nil and landmark.index == playerLandmarkIndex(state)
  return join({ flatName(landmark.name), here and "you are here" or nil })
end

-- Fly map: the flypoint row under the cursor (drawFlyBubble prints its
-- name), "you are here" where drawMap draws the player icon on it.
local function flyText(state, withPosition)
  local rows = state.fly or {}
  local row = call(state, "flyRow")
  if type(row) ~= "table" then return nil end
  local sameRegion = not state.flyRegion or state.flyRegion == call(state, "region")
  local here = sameRegion and row.index ~= nil and row.index == playerLandmarkIndex(state)
  local text = join({ flatName(row.name), here and "you are here" or nil })
  if withPosition then text = join({ text, position(state.flyIndex or 1, #rows) }) end
  return text
end

-- RADIO card: frequency and the station drawRadio names (the show's own
-- stationName, else the dial row's name).  Dead air has no name.
local function radioText(state)
  local row = call(state, "currentStation")
  if type(row) ~= "table" then return nil end
  local frequency = row.frequency and tonumber(row.frequency)
  local name = (state.radio and state.radio.stationName) or row.name
  return join({ frequency and string.format("%.1f", frequency) or row.frequency,
    (name and name ~= "") and speakable(name) or nil })
end

-- The phone list.  Phone.contacts normalises save.phone (creating it on a
-- fresh save); the card's own draw does that every frame, so the list is
-- read only once save.phone exists and the call repeats what the draw did.
local function phoneList(state)
  local save = state.save
  if type(save) ~= "table" or type(save.phone) ~= "table" then return nil end
  return call(state, "phoneList")
end

-- A contact row: "NAME:" and the trainer class under it (contactRow), or an
-- empty slot ("----------"), with its slot of the ten.
local function phoneRow(state)
  local list = phoneList(state)
  if not list then return nil end
  local slot = (state.phoneScroll or 0) + (state.phoneCursor or 0) + 1
  local id = list[slot] or 0
  local text
  if id == 0 then
    text = "empty"
  else
    local label, className = call(state, "contactRow", id)
    label = label and tostring(label):gsub("%s*:%s*$", "") or nil
    text = join({ label and speakable(label) or nil, className and speakable(className) or nil })
  end
  return join({ text, position(slot, #list) })
end

local function phoneSubmenuText(state, withPosition)
  local Pokegear = class("Pokegear")
  local menus = Pokegear and Pokegear.PHONE_SUBMENUS
  local menu = menus and menus[state.phoneSubmenu]
  if type(menu) ~= "table" then return nil end
  local cursor = (state.phoneSubmenuCursor or 0) + 1
  local entry = menu.entries and menu.entries[cursor]
  if not entry then return nil end
  local text = speakable(tr(entry))
  if withPosition then text = join({ text, position(cursor, menu.rows or #menu.entries) }) end
  return text
end

local function callText(state)
  local text = state.call and state.call.text
  if not text or text == "" then text = call(state, "phoneText", "GearEllipse") end
  return text and speakable(text) or nil
end

-- What the phone card is showing: a call, the contact submenu, or the
-- "Whom do you want to call?" prompt over the list.
local function phoneFocus(state, withPrompt)
  if state.call then return callText(state) end
  if state.phoneSubmenu then return phoneSubmenuText(state, true) end
  local prompt = withPrompt and call(state, "phoneText", "AskWhoCall") or nil
  return join({ prompt and speakable(prompt) or nil, phoneRow(state) }, " ")
end

local function cardDetails(state, id)
  if id == "clock" then return clockText(state) end
  if id == "map" then return mapText(state) end
  if id == "radio" then return radioText(state) end
  if id == "phone" then return phoneFocus(state, true) end
  return nil
end

-- A card arriving: its label, what it shows and, on the card strip, its
-- place among the cards owned.  The strip shows each card's face (clock,
-- map, radio) even before A is pressed, so the details are said there too.
local function cardIntro(state, card)
  local label = speakable(call(state, "cardLabel", card) or "")
  local id = card and card.id
  local text = join({ label, cardDetails(state, id) }, ". ")
  if state.mode == "strip" then
    text = join({ text, position(state.cardIndex or 1, #(state.cards or {})) })
  end
  return text
end

local function gearPoll(state, memo, entering)
  local card = call(state, "card")
  local id = card and card.id
  local first = not memo.seen
  local cardChanged = memo.cardIndex ~= state.cardIndex or memo.mode ~= state.mode
  local phoneReady = id == "phone" and type(state.save) == "table" and type(state.save.phone) == "table"
  local cursorSlot = (state.phoneScroll or 0) + (state.phoneCursor or 0)
  local text
  if first or (cardChanged and not entering) then
    text = cardIntro(state, card)
  elseif entering then
    -- back from a screen above (a call's text pages): only the focus, and
    -- nothing while the call that was just heard is still up
    if id == "phone" and not state.call then text = phoneFocus(state, false) end
  elseif id == "map" and memo.mapCursor ~= state.mapCursor then
    text = mapText(state)
  elseif id == "radio" and memo.knob ~= state.tuningKnob then
    text = radioText(state)
  elseif id == "phone" then
    if state.call ~= memo.call then
      text = state.call and callText(state) or phoneFocus(state, true)
    elseif state.phoneSubmenu ~= memo.submenu then
      text = state.phoneSubmenu and phoneSubmenuText(state, true) or phoneRow(state)
    elseif state.phoneSubmenu and memo.submenuCursor ~= state.phoneSubmenuCursor then
      text = phoneSubmenuText(state, false)
    elseif memo.slot ~= cursorSlot or (phoneReady and not memo.phoneReady) then
      text = phoneRow(state)
    end
  end
  -- radio show lines queue behind whatever else is said, like dialogue;
  -- off the radio card the memo forgets the show
  local lines = newRadioLines(id == "radio" and state.radio or nil, memo)
  memo.seen, memo.cardIndex, memo.mode = true, state.cardIndex, state.mode
  memo.mapCursor, memo.knob, memo.call = state.mapCursor, state.tuningKnob, state.call
  memo.submenu, memo.submenuCursor, memo.slot = state.phoneSubmenu, state.phoneSubmenuCursor, cursorSlot
  memo.phoneReady = phoneReady
  if text == "" then text = nil end
  if text and lines then return text .. ". " .. lines, true end
  if text then return text, true end
  if lines then return lines, false end
  return nil
end

local function flyPoll(state, memo, entering)
  if not entering and memo.flyIndex == state.flyIndex then return nil end
  local first = not memo.seen
  memo.seen, memo.flyIndex = true, state.flyIndex
  local text
  if first then
    -- the card label (FLY), then the bubble: "Where?" over the row name
    text = join({ speakable(call(state, "cardLabel") or ""),
      join({ speakable(tr("Where?")), flyText(state, true) }, " ") }, ". ")
  else
    text = flyText(state, entering)
  end
  if not text or text == "" then return nil end
  return text, true
end

local function townMapPoll(state, memo, entering)
  if not entering and memo.mapCursor == state.mapCursor then return nil end
  local first = not memo.seen
  memo.seen, memo.mapCursor = true, state.mapCursor
  local text = mapText(state)
  if first then text = join({ speakable(call(state, "cardLabel") or ""), text }, ". ") end
  if not text or text == "" then return nil end
  return text, true
end

-- Pokegear (src/ui/gen2/Pokegear.lua) in its three uses: the gear itself,
-- the fly map (`fly`) and the town map (`townMap`).
Info.pokegear = {
  matches = Common.matcher("Pokegear"),
  poll = function(state, memo, entering)
    if state.fly then return flyPoll(state, memo, entering) end
    if state.townMap then return townMapPoll(state, memo, entering) end
    return gearPoll(state, memo, entering)
  end,
}

-- CallerBox (src/ui/gen2/CallerBox.lua): the caller-ID strip of an incoming
-- call, pushed under the call's text pages.  It is the top state while the
-- phone rings, so the caller is named once, before the RING! page.
Info.callerBox = {
  matches = Common.matcher("CallerBox"),
  poll = function(state, memo)
    if memo.said then return nil end
    memo.said = true
    local name = state.name and state.name ~= "" and speakable(state.name) or nil
    local className = state.className and state.className ~= "" and speakable(state.className) or nil
    return join({ "Phone call", name, className }), true
  end,
}

-- MapRadio (src/ui/gen2/MapRadio.lua): a house radio.  It holds its own
-- Radio off the stack; the station name (quoted in the box until the first
-- line) on entry, then each show line as it prints, queued.
Info.mapRadio = {
  matches = Common.matcher("MapRadio"),
  poll = function(state, memo)
    local text
    if not memo.said then
      memo.said = true
      local name = call(state, "name")
      text = join({ "Radio", name and name ~= "" and speakable(name) or nil })
    end
    local lines = newRadioLines(state.radio, memo)
    if text and lines then return text .. ". " .. lines, true end
    if text then return text, true end
    if lines then return lines, false end
    return nil
  end,
}

-- --------------------------------------------------------- trainer card

-- Badge pages: page 2 draws the Johto badges from player.badges (keyed by
-- index or by name).  Page 3 is labelled KANTO BADGES (drawPlain), but
-- upstream reads the same player.badges flags there (TrainerCard.lua says
-- the cart's page 3 reuses the Johto table); speech mirrors that page.
local function badgeText(state, names, label)
  local player = (state.save and state.save.player) or {}
  local held = player.badges or {}
  local owned = {}
  for i, name in ipairs(names or {}) do
    if held[i] or held[name] then owned[#owned + 1] = speakable(tr(name)) end
  end
  return join({ speakable(tr(label)),
    #owned == 0 and "no badges" or (count(#owned, "badge", "badges") .. ": " .. table.concat(owned, ", ")) }, ". ")
end

local function trainerCardPage(state)
  local TrainerCard = class("TrainerCard") or {}
  local pages = call(state, "pages") or 2
  local text
  if state.page == 1 then
    local save = state.save or {}
    local player = save.player or {}
    local time = save.playTime or {}
    local caught = call(state, "caughtCount")
    text = join({ "Trainer card", player.name and speakable(player.name) or nil,
      "ID " .. tostring(player.id or 0), "money ¥" .. tostring(player.money or 0),
      caught and ("Pokédex " .. tostring(caught)) or nil,
      "time " .. count(time.hours or 0, "hour", "hours") .. " "
        .. count(time.minutes or 0, "minute", "minutes") })
  elseif state.page == 2 then
    text = badgeText(state, TrainerCard.JOHTO_BADGES, "JOHTO BADGES")
  else
    text = badgeText(state, TrainerCard.KANTO_BADGES, "KANTO BADGES")
  end
  return join({ text, "page " .. position(state.page or 1, pages) })
end

-- TrainerCard (src/ui/gen2/TrainerCard.lua): name, ID, money, Pokédex
-- count and play time, then the badge pages.  Time is read on entry and on
-- a page turn, not on every minute tick.
Info.trainerCard = {
  matches = Common.matcher("TrainerCard"),
  poll = function(state, memo, entering)
    if not entering and memo.page == state.page then return nil end
    memo.page = state.page
    return trainerCardPage(state), true
  end,
}

Info.ordered = {
  Info.partyMenu,
  Info.summaryMenu,
  Info.pokedexMenu,
  Info.pokegear,
  Info.callerBox,
  Info.mapRadio,
  Info.trainerCard,
}

return Info
