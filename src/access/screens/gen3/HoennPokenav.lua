-- The Pokénav (Ruby, Sapphire, Emerald).
--
-- Emerald: src/ui/game3/rse/pokenav/* (layer "rse_pokenav").  `Pokenav.active()`
-- is a shell whose `screen` is one object per sub-screen, chosen by `menuId`.
-- The incoming call is its own layer, "rse_match_call_window".
-- Ruby and Sapphire: src/ui/game3/rs/pokenav/* (layer "rs_pokenav").  The state
-- has `menu`, `cursor`, `rows`, and `feature` for everything but the three menus.
--
-- Only fields and read-only functions are used.  Not called, because they write:
-- Rematch.get (Rematch.state fills in session fields), Ribbons.giftRibbons,
-- the Ruby ribbon screen's description() (keeps a field on the screen).
--
-- The screens draw these as images, so they are said in our words: every menu
-- row, the headers on the left of the screen, the condition graph's five axes
-- and its sparkles, the marking symbols, the male and female signs, and the
-- rematch marker.  Ruby and Sapphire's help bars are images too; the words for
-- the ones we say were read off those images.

local Common = require("src.access.screens.gen3.Common")
local H = require("src.access.screens.gen3.HoennCommon")

local Nav = {}

local say, rom, join, sentences, try, position = H.say, H.rom, H.join, H.sentences, H.try, Common.position

local CONDITION_WORDS = {
  { key = "cool", word = "COOL" }, { key = "beauty", word = "BEAUTY" }, { key = "cute", word = "CUTE" },
  { key = "smart", word = "SMART" }, { key = "tough", word = "TOUGH" },
}
local SEARCH_WORDS = { [0] = "COOL", "BEAUTY", "CUTE", "SMART", "TOUGH" }
local MARK_WORDS = { [0] = "circle", "square", "triangle", "heart" }
local MARK_OK, MARK_CANCEL = 4, 5
local REMATCH_WORDS = "wants a rematch"
-- The blue light that blinks on the device's left (main_menu.lua draw).
local NEARBY_WORDS = "A rematch is nearby"

local function genderWord(gender)
  if gender == "M" then return "male" end
  if gender == "F" then return "female" end
  return nil
end

-- One memory per sub-screen object, so returning to a screen says its context.
local function subMemo(memo, key)
  if memo.subKey ~= key then
    memo.subKey, memo.sub = key, {}
  end
  return memo.sub
end

-- A printer page made only of dots says nothing a screen reader can use.
local function noDots(text)
  if text and text:find("[%w]") then return text end
  return nil
end

local function statNumber(mon, key)
  local contest = type(mon) == "table" and type(mon.contest) == "table" and mon.contest or {}
  return math.floor(tonumber(contest[key]) or 0)
end

-- The five axes of the graph and the sheen behind its sparkles, as numbers.
local function conditionNumbers(mon)
  local parts = {}
  for _, row in ipairs(CONDITION_WORDS) do
    parts[#parts + 1] = row.word .. " " .. statNumber(mon, row.key)
  end
  parts[#parts + 1] = "sheen " .. statNumber(mon, "sheen")
  return table.concat(parts, ", ")
end

local function monLine(name, gender, level)
  return join({ say(name), genderWord(gender), level and ("level " .. tostring(level)) or nil })
end

local function markedWords(marks)
  marks = math.floor(tonumber(marks) or 0)
  local names = {}
  for i = 0, 3 do
    if marks % 2 ^ (i + 1) >= 2 ^ i then names[#names + 1] = MARK_WORDS[i] end
  end
  if #names == 0 then return nil end
  return "marked " .. table.concat(names, ", ")
end

-- The marking box: `isOn(i)` for the four symbols, OK and CANCEL after them
-- (src/ui/game3/rse/pokenav/condition.lua drawMarkingsMenu, rs/storage_markings.lua).
local function markingRow(cursor, isOn)
  local label
  if cursor == MARK_OK then label = "OK"
  elseif cursor == MARK_CANCEL then label = H.first({ "gText_Cancel2", "gOtherText_CancelNoTerminator" }) or "CANCEL"
  else label = join({ MARK_WORDS[cursor], isOn(cursor) and "marked" or "not marked" }) end
  return join({ label, position(cursor + 1, MARK_CANCEL + 1) })
end

-- ----------------------------------------------------------------- Emerald

local function pathOf(name) return "src.ui.game3.rse.pokenav." .. name end
local function moduleOf(name) return H.loaded(pathOf(name)) end

-- Names of the rows by ITEM id (rse/pokenav/main_menu.lua).
local EMERALD_ITEM_WORDS = { [0] = "HOENN MAP", "CONDITION", "MATCH CALL", "RIBBONS", "SWITCH OFF",
  "PARTY", "SEARCH", "CANCEL", "COOL", "BEAUTY", "CUTE", "SMART", "TOUGH", "CANCEL" }

local function emeraldMenu(screen, sub)
  local Main = moduleOf("main_menu")
  if not (Main and screen.visible) or screen.pendingReturnFn then return nil end
  local list = Main.ITEMS[screen.menuType]
  if type(list) ~= "table" then return nil end
  local context
  if screen.menuType ~= sub.menuType then
    if screen.menuType == Main.TYPE.CONDITION then context = "CONDITION"
    elseif screen.menuType == Main.TYPE.CONDITION_SEARCH then context = "CONDITION search"
    else context = "POKéNAV" end
  end
  local denied = screen.handler == "cant_ribbons"
  local text
  if denied and not sub.denied then
    text = say(rom(screen.description))
  elseif context or screen.cursorPos ~= sub.cursor or sub.denied ~= denied then
    local label = EMERALD_ITEM_WORDS[screen.currMenuItem]
    local description = say(rom(try(screen.descriptionKey, screen)))
    if context or screen.cursorPos ~= sub.cursor then
      local light = context == "POKéNAV" and screen.nearbyRematch and NEARBY_WORDS or nil
      text = sentences({ context, light, label and join({ label, position(screen.cursorPos + 1, #list) }), description })
    else
      text = description
    end
  end
  sub.menuType, sub.cursor, sub.denied = screen.menuType, screen.cursorPos, denied
  return text
end

local function emeraldPlace(nav)
  local RegionMap = H.loaded("src.ui.game3.rse.region_map")
  local rm = nav.rm
  if not (RegionMap and type(rm) == "table" and RegionMap.TYPE) then return nil end
  local TYPE = RegionMap.TYPE
  if rm.mapSecType == TYPE.NONE then return "no place" end
  local parts = { say(rm.mapSecName) }
  if rm.mapSecType == TYPE.ROUTE or rm.mapSecType == TYPE.BATTLE_FRONTIER then
    for _, name in ipairs(try(nav.landmarkNames, rm.mapSecId, rm.posWithinMapSec) or {}) do
      parts[#parts + 1] = say(name)
    end
  end
  return join(parts)
end

local function emeraldMap(shell, nav, sub)
  if not nav.visible or not nav.info then return nil end
  if nav.inputFn ~= "full" and nav.inputFn ~= "zoomed" then return nil end
  local rm = nav.rm
  local x, y = rm.cursorX, rm.cursorY
  if nav.zoomed then x, y = nav.zoomedX, nav.zoomedY end
  local here = x == rm.playerIconX and y == rm.playerIconY
  local place = emeraldPlace(nav)
  local line = join({ place, here and "you are here" or nil })
  local zoomWord = not nav.zoomDisabled and (nav.zoomed and "zoomed in" or "zoomed out") or nil
  local text
  if not sub.opened then
    sub.opened = true
    -- On an event island the bar still says ZOOM, but only B does anything.
    text = sentences({ "HOENN MAP", zoomWord, line, not nav.zoomDisabled and say(rom(shell.helpBar)) or nil })
  elseif nav.zoomed ~= sub.zoomed then
    text = sentences({ zoomWord, line })
  elseif line ~= sub.line then
    text = line
  end
  sub.line, sub.zoomed = line, nav.zoomed
  return text
end

local function emeraldGraph(shell, screen, sub)
  if not (screen.window and screen.showText) then return nil end
  local Info = moduleOf("mon_info")
  if not Info then return nil end
  local list = screen.list
  local index = list.currIndex
  local marks = screen.marksMenu
  if marks then
    if sub.marksOpen and marks.cursorPos == sub.markCursor and marks.array[marks.cursorPos] == sub.markOn then return nil end
    local fresh = not sub.marksOpen
    sub.marksOpen, sub.markCursor, sub.markOn = true, marks.cursorPos, marks.array[marks.cursorPos]
    local row = markingRow(marks.cursorPos, function(i) return marks.array[i] end)
    if fresh then return sentences({ "Markings", row, say(rom(shell.helpBar)) }) end
    return row
  end
  local slot = screen.slots and screen.slots[screen.loadId]
  local function rowText()
    if screen:onCancel() then
      return join({ H.first({ "gText_Cancel2" }) or "CANCEL", position(index + 1, list.listCount) })
    end
    local mon = screen:mon(index)
    if type(mon) ~= "table" then return nil end
    local gender = try(Info.conditionGender, mon)
    local rank
    if screen.searchMode then
      local item = screen:item(index)
      rank = item and join({ say(rom("gText_Number2")), tostring(item.data) }, " ")
    end
    return sentences({
      join({ monLine(try(Info.nickname, mon), gender, try(Info.level, mon)),
        screen.searchMode and slot and say(slot.location) or nil, rank, position(index + 1, list.listCount) }),
      conditionNumbers(mon),
      screen.searchMode and markedWords(slot and slot.marks) or nil,
    })
  end
  local text
  if not sub.opened then
    sub.opened = true
    local context = screen.searchMode and join({ "CONDITION", SEARCH_WORDS[shell.conditionSearchId or 0] })
      or join({ "CONDITION", "PARTY" })
    text = sentences({ context, rowText(), screen.searchMode and say(rom(shell.helpBar)) or nil })
  elseif index ~= sub.index then
    text = rowText()
  elseif sub.marksOpen then
    text = markedWords(slot and slot.marks) or "no marks"
  end
  sub.index, sub.marksOpen = index, nil
  return text
end

local function emeraldMonRow(screen, item, tail)
  local Info = moduleOf("mon_info")
  local mon = Info and try(Info.mon, screen.session, item)
  if type(mon) ~= "table" then return nil end
  return join({ monLine(try(Info.nickname, mon), try(Info.gender, mon), try(Info.level, mon)), tail })
end

local function emeraldSearchList(shell, screen, sub)
  local list = screen.list
  if not list or shell:busy(shell.screenTask) then return nil end
  local index = try(list.selectedIndex, list)
  local function rowText()
    local item = list.entries[index + 1]
    if not item then return nil end
    local rank = join({ say(rom("gText_Number2")), tostring(item.data) }, " ")
    return emeraldMonRow(screen, item, join({ rank, position(index + 1, #list.entries) }))
  end
  local text
  if not sub.opened then
    sub.opened = true
    text = sentences({ join({ "CONDITION", SEARCH_WORDS[shell.conditionSearchId or 0] }), rowText(), say(rom(shell.helpBar)) })
  elseif index ~= sub.index then
    text = rowText()
  end
  sub.index = index
  return text
end

local function emeraldRibbonList(shell, screen, sub)
  local list = screen.list
  if not list or shell:busy(shell.screenTask) then return nil end
  local index = try(list.selectedIndex, list)
  local function rowText()
    local item = list.entries[index + 1]
    if not item then return nil end
    return emeraldMonRow(screen, item, join({ "ribbons " .. tostring(item.data), position(index + 1, #list.entries) }))
  end
  local text
  if not sub.opened then
    sub.opened = true
    text = sentences({ "RIBBONS", rowText(), say(rom(shell.helpBar)) })
  elseif index ~= sub.index then
    text = rowText()
  end
  sub.index = index
  return text
end

local function emeraldRibbonSummary(shell, screen, sub)
  if not screen.visible or shell:busy(shell.screenTask) or shell:busy(shell.loopTask) then return nil end
  local list = screen.monList
  local mode = screen.handler
  local text
  if mode == "input" then
    if not sub.opened or list.currIndex ~= sub.index then
      local info = screen.info
      local mon = info and monLine(info.name, info.gender, info.level)
      text = sentences({ not sub.opened and "RIBBONS" or nil,
        join({ mon, position(list.currIndex + 1, list.listCount) }), say(screen.countText),
        not sub.opened and say(rom(shell.helpBar)) or nil })
    elseif sub.mode == "expanded" then
      text = say(screen.countText)
    end
    sub.opened, sub.index = true, list.currIndex
  elseif mode == "expanded" and screen.textMode == "desc" then
    if sub.mode ~= "expanded" or screen.selectedPos ~= sub.pos then
      local pos = screen.selectedPos
      local at
      if pos < screen.FIRST_GIFT_RIBBON then at = pos + 1
      else at = #(screen.normalIds or {}) + pos - screen.GIFT_RIBBON_START_POS + 1 end
      local lines = {}
      for _, key in ipairs(screen.desc or {}) do lines[#lines + 1] = say(rom(key)) end
      text = sentences({ join(lines, " "), position(at, #(screen.normalIds or {}) + #(screen.giftIds or {})) })
    end
    sub.pos = screen.selectedPos
  else
    return nil
  end
  sub.mode = mode
  return text
end

local function emeraldEntryRow(screen, e)
  local MatchCall = H.loaded("src.core.game3.rse.match_call")
  local Rematch = H.loaded("src.core.game3.rse.rematch")
  if not (MatchCall and e) then return nil end
  local desc, name = try(screen.entryText, screen, e)
  local place
  if e.mapSec and e.mapSec ~= try(MatchCall.mapsecNone) then place = say(try(MatchCall.mapName, e.mapSec))
  else place = H.first({ "gText_Unknown" }) end
  local rematch
  local idx = try(MatchCall.entryRematchIdx, e)
  local rows = screen.session and screen.session.trainerRematches
  if idx and Rematch and idx ~= try(Rematch.count) and type(rows) == "table" and (tonumber(rows[idx]) or 0) ~= 0 then
    rematch = REMATCH_WORDS
  end
  return join({ say(desc), say(name), place, rematch })
end

-- The Check page (rse/pokenav/match_call.lua drawCheckPage): three headings,
-- with the fourth text the second line of the self-introduction.
local function emeraldCheckPage(screen, e)
  local MatchCall = H.loaded("src.core.game3.rse.match_call")
  if not MatchCall then return nil end
  local function flavor(i)
    local key = try(MatchCall.entryFlavorText, screen.session, e, i)
    return key and say(rom(key)) or nil
  end
  return sentences({ emeraldEntryRow(screen, e),
    join({ say(rom("gText_PokenavMatchCall_Strategy")), flavor(1) }, ": "),
    join({ say(rom("gText_PokenavMatchCall_TrainerPokemon")), flavor(2) }, ": "),
    join({ say(rom("gText_PokenavMatchCall_SelfIntroduction")), join({ flavor(3), flavor(4) }, " ") }, ": ") })
end

local function emeraldMatchCall(shell, screen, sub, state)
  if not screen.visible then return nil end
  local mode = screen.handler
  if mode == "call" then
    sub.mode = mode
    if not screen.printer then return nil end
    return noDots(H.printerSay(screen.printer, sub, state.game))
  end
  local Gfx = moduleOf("gfx")
  local index = screen:selectedIndex()
  local text
  if mode == "list" then
    if screen.checkPage or screen.callBox then return nil end
    if not sub.opened then
      sub.opened = true
      local count = join({ say(rom("gText_NumberRegistered")), tostring(#screen.entries) }, " ")
      local stats = screen.session and screen.session.gameStats
      local battles = join({ say(rom("gText_NumberOfBattles")),
        tostring(math.min(99999, math.floor(tonumber(stats and stats[9]) or 0))) }, " ")
      local row = emeraldEntryRow(screen, screen:entry(index))
      text = sentences({ "MATCH CALL", count, battles, row and join({ row, position(index + 1, #screen.entries) }),
        say(rom(shell.helpBar)) })
    elseif index ~= sub.index or sub.mode ~= "list" then
      local row = emeraldEntryRow(screen, screen:entry(index))
      text = row and join({ row, position(index + 1, #screen.entries) })
    end
    sub.index = index
  elseif mode == "options" then
    if not screen.options or not Gfx then return nil end
    if sub.mode ~= "options" or screen.optionCursor ~= sub.option then
      local man = Gfx.manifest()
      local option = screen.options[screen.optionCursor + 1]
      text = join({ say(rom(man.optionTexts[option])), position(screen.optionCursor + 1, #screen.options) })
    end
    sub.option = screen.optionCursor
  elseif mode == "check" then
    if not screen.checkPage then return nil end
    if sub.mode ~= "check" or screen.top ~= sub.top then
      text = emeraldCheckPage(screen, screen:entry(screen.top))
    end
    sub.top = screen.top
  end
  sub.mode = mode
  return text
end

local function emeraldRead(shell, memo, state)
  if shell.phase ~= "menu" or not shell.screen then return nil end
  local screen = shell.screen
  local sub = subMemo(memo, screen)
  local Main = moduleOf("main_menu")
  if Main and getmetatable(screen) == Main then return emeraldMenu(screen, sub) end
  local mt = getmetatable(screen)
  if mt == moduleOf("region_map") then return emeraldMap(shell, screen, sub) end
  if mt == moduleOf("match_call") then return emeraldMatchCall(shell, screen, sub, state) end
  if mt == moduleOf("condition") then return emeraldGraph(shell, screen, sub) end
  if mt == moduleOf("condition_search") then return emeraldSearchList(shell, screen, sub) end
  if mt == moduleOf("ribbons_summary") then
    return emeraldRibbonSummary(shell, screen, sub)
  end
  if mt == moduleOf("ribbons") then return emeraldRibbonList(shell, screen, sub) end
  return nil
end

Nav.emerald = {
  matches = Common.matcher("rse_pokenav"),
  poll = function(state, memo)
    local Pokenav = moduleOf("init")
    local shell = Pokenav and try(Pokenav.active)
    if type(shell) ~= "table" then return nil end
    local text = emeraldRead(shell, memo, state)
    if not text then return nil end
    return text, true
  end,
}

-- The incoming call (rse/pokenav/call_window.lua): the window shows the
-- Pokénav's icon and the printer's text; the icon is said in our words.
Nav.callWindow = {
  matches = Common.matcher("rse_match_call_window"),
  poll = function(state, memo)
    local Window = moduleOf("call_window")
    local s = Window and try(Window.active)
    if type(s) ~= "table" then return nil end
    local head
    if not memo.opened then
      memo.opened = true
      head = "POKéNAV call"
    end
    local text = s.printer and noDots(H.printerSay(s.printer, memo, state.game)) or nil
    text = sentences({ head, text })
    if not text then return nil end
    return text, true
  end,
}

-- ------------------------------------------------------- Ruby and Sapphire

local function rsPath(name) return "src.ui.game3.rs.pokenav." .. name end
local function rsModule(name) return H.loaded(rsPath(name)) end

local RS_MENU_WORDS = {
  main = { "HOENN MAP", "CONDITION", "TRAINER'S EYES", "RIBBONS", "SWITCH OFF" },
  condition = { "PARTY", "SEARCH", "CANCEL" },
  search = { "COOL", "BEAUTY", "CUTE", "SMART", "TOUGH", "CANCEL" },
}
local RS_MENU_CONTEXT = { main = "POKéNAV", condition = "CONDITION", search = "CONDITION search" }

-- Help bars, read off the images in the Ruby build.
local RS_HELP_MAP_OUT = "A button ZOOM B button CANCEL"
local RS_HELP_MAP_IN = "A button FULL B button CANCEL"
local RS_HELP_EYES = "A button CHECK B button CANCEL"
local RS_HELP_GRAPH = "A button MARKINGS B button CANCEL"
local RS_HELP_MARKS = "A button SELECT MARK B button CANCEL"

local function rsMenu(s, sub)
  local words = RS_MENU_WORDS[s.menu]
  local menu = s.nav and s.nav.menus and s.nav.menus[s.menu]
  if not (words and menu and type(s.rows) == "table") then return nil end
  local count, at = 0, nil
  for i = 1, menu.count do
    if s.rows[i] then
      count = count + 1
      if i - 1 == s.cursor then at = count end
    end
  end
  local help = say(menu.help[s.cursor + 1])
  local override = s.helpOverride
  local text
  if override and override ~= sub.override then
    text = say(menu.help[override])
  elseif not sub.opened or s.cursor ~= sub.cursor then
    local label = words[s.cursor + 1]
    text = sentences({ not sub.opened and RS_MENU_CONTEXT[s.menu] or nil,
      not sub.opened and s.menu == "main" and s.nearbyRematch and NEARBY_WORDS or nil,
      label and at and join({ label, position(at, count) }), help })
  elseif sub.override and not override then
    text = help
  end
  sub.opened, sub.cursor, sub.override = true, s.cursor, override
  return text
end

local function rsMap(map, sub, shellManifest, session)
  local Data = rsModule("data")
  if not Data or map.zoomFrame or map.moveFrames ~= 0 then return nil end
  local place
  if map.kind == 0 then
    place = "no place"
  else
    local parts = { say(map.name) }
    if map.kind == 1 or map.kind == 4 then
      local names = try(Data.landmarks, shellManifest, session, map.section, map.pos, map.man.mapsecs.NONE)
      for _, name in ipairs(names or {}) do parts[#parts + 1] = say(name) end
    end
    place = join(parts)
  end
  local here = map.x == map.playerX and map.y == map.playerY
  local line = join({ place, here and "you are here" or nil })
  local zoomWord = map.zoomed and "zoomed in" or "zoomed out"
  local help = map.zoomed and RS_HELP_MAP_IN or RS_HELP_MAP_OUT
  local text
  if not sub.opened then
    sub.opened = true
    text = sentences({ "HOENN MAP", zoomWord, line, help })
  elseif map.zoomed ~= sub.zoomed then
    text = sentences({ zoomWord, line })
  elseif line ~= sub.line then
    text = line
  end
  sub.line, sub.zoomed = line, map.zoomed
  return text
end

local function rsEyesRow(eyes, row)
  local Data = rsModule("data")
  local Trainers = H.loaded("src.core.game3.scripting.trainers")
  if not (Data and Trainers and row) then return nil end
  local info = try(Trainers.get, row.opponentId)
  return join({ info and say(info.className), info and say(info.name),
    say(try(Data.sectionName, eyes.region, row.regionMapSectionId)),
    row.rematchNo ~= 0 and REMATCH_WORDS or nil })
end

local function rsEyes(eyes, sub, session)
  local row = eyes.entries[eyes.index]
  local strings = eyes.man.strings
  local text
  if eyes.detail then
    if sub.mode ~= "detail" or eyes.index ~= sub.index then
      local lines = eyes.man.descriptions[row.descriptionId] or {}
      text = sentences({ rsEyesRow(eyes, row),
        join({ say(strings.Strategy), say(lines[1]) }, ": "),
        join({ say(strings.TrainersPokemon), say(lines[2]) }, ": "),
        join({ say(strings.SelfIntroduction), join({ say(lines[3]), say(lines[4]) }, " ") }, ": ") })
    end
    sub.mode = "detail"
  else
    if not sub.opened then
      sub.opened = true
      local stats = session and session.gameStats
      local rowText = rsEyesRow(eyes, row)
      text = sentences({ "TRAINER'S EYES",
        join({ say(strings.NumberRegistered), tostring(#eyes.entries) }, " "),
        join({ say(strings.NumberBattles), tostring(math.min(99999, tonumber(stats and stats[9]) or 0)) }, " "),
        rowText and join({ rowText, position(eyes.index, #eyes.entries) }), RS_HELP_EYES })
    elseif eyes.index ~= sub.index or sub.mode ~= "list" then
      local rowText = rsEyesRow(eyes, row)
      text = rowText and join({ rowText, position(eyes.index, #eyes.entries) })
    end
    sub.mode = "list"
  end
  sub.index = eyes.index
  return text
end

local function rsMonLine(session, row, mon)
  local Data = rsModule("data")
  local Cond = rsModule("condition_data")
  local Pokemon = H.loaded("src.core.game3.pokemon")
  if not (Data and Cond and Pokemon and type(mon) == "table") then return nil end
  return monLine(try(Pokemon.displayName, mon), try(Cond.gender, mon), try(Cond.level, mon, row.box ~= 14))
end

local function rsGraph(g, sub, s)
  local Cond = rsModule("condition_data")
  if not Cond then return nil end
  local marks = g.markings
  if marks then
    local function isOn(i) return marks.value % 2 ^ (i + 1) >= 2 ^ i end
    local on = marks.cursor < MARK_OK and isOn(marks.cursor) or nil
    if sub.marksOpen and marks.cursor == sub.markCursor and on == sub.markOn then return nil end
    local fresh = not sub.marksOpen
    sub.marksOpen, sub.markCursor, sub.markOn = true, marks.cursor, on
    local row = markingRow(marks.cursor, isOn)
    if fresh then return sentences({ "Markings", row, RS_HELP_MARKS }) end
    return row
  end
  local function rowText()
    local row = g.rows[g.index]
    if not row then return nil end
    if row.cancel then return join({ H.first({ "gOtherText_CancelNoTerminator", "gText_Cancel2" }) or "CANCEL",
      position(g.index, #g.rows) }) end
    local mon = try(Cond.mon, g.session, row)
    if type(mon) ~= "table" then return nil end
    local strings = g.man.strings
    return sentences({
      join({ rsMonLine(g.session, row, mon),
        g.searchMode and say(try(Cond.location, g.session, row, g.man)) or nil,
        g.searchMode and join({ say(strings.Number), tostring(row.rank) }, " ") or nil,
        position(g.index, #g.rows) }),
      conditionNumbers(mon),
      g.searchMode and markedWords(mon.markings) or nil,
    })
  end
  local text
  if not sub.opened then
    sub.opened = true
    local context = g.searchMode and join({ "CONDITION", SEARCH_WORDS[s.conditionSearchId or 0] })
      or join({ "CONDITION", "PARTY" })
    text = sentences({ context, rowText(), g.searchMode and RS_HELP_GRAPH or nil })
  elseif g.index ~= sub.index then
    text = rowText()
  elseif sub.marksOpen then
    local mon = try(Cond.mon, g.session, g.rows[g.index])
    text = markedWords(mon and mon.markings) or "no marks"
  end
  sub.index, sub.marksOpen = g.index, nil
  return text
end

local function rsSearchList(list, sub, s)
  local Cond = rsModule("condition_data")
  if not Cond then return nil end
  local function rowText()
    local row = list.rows[list.index]
    local mon = row and try(Cond.mon, list.session, row)
    if type(mon) ~= "table" then return nil end
    local tail = list.ribbons and ("ribbons " .. tostring(row.value))
      or join({ say(list.man.strings.Number), tostring(row.rank) }, " ")
    return join({ rsMonLine(list.session, row, mon), tail, position(list.index, #list.rows) })
  end
  local text
  if not sub.opened then
    sub.opened = true
    local context = list.ribbons and "RIBBONS" or join({ "CONDITION", SEARCH_WORDS[s.conditionSearchId or 0] })
    text = sentences({ context, rowText() })
  elseif list.index ~= sub.index then
    text = rowText()
  end
  sub.index = list.index
  return text
end

local function rsRibbonText(r, session)
  local id = r.row == 3 and r.gift[r.column + 1] or r.normal[r.row * 9 + r.column + 1]
  if id == nil then return nil end
  local lines
  if id < 25 then
    lines = r.man.descriptions[id]
  else
    local Native = H.loaded("src.core.game3.profiles.rs.pokenav")
    local index = Native and try(Native.giftDescriptionIndex, session, id)
    lines = index and r.man.giftDescriptions and r.man.giftDescriptions[index]
  end
  local parts = {}
  for _, line in ipairs(lines or {}) do parts[#parts + 1] = say(line) end
  return join(parts, " ")
end

local function rsRibbons(r, sub)
  if r.busy > 0 then return nil end
  local row = r.rows[r.index]
  local text
  if r.selecting then
    if sub.mode ~= "selecting" or r.row ~= sub.row or r.column ~= sub.column then
      local at = r.row == 3 and (#r.normal + r.column + 1) or (r.row * 9 + r.column + 1)
      text = sentences({ rsRibbonText(r, r.session), position(at, #r.normal + #r.gift) })
    end
    sub.mode, sub.row, sub.column = "selecting", r.row, r.column
    return text
  end
  local count = join({ say(r.man.strings.Ribbons), tostring(row and row.value) }, " ")
  if not sub.opened or r.index ~= sub.index then
    text = sentences({ not sub.opened and "RIBBONS" or nil,
      join({ rsMonLine(r.session, row, r.mon), position(r.index, #r.rows) }), count })
  elseif sub.mode == "selecting" then
    text = count
  end
  sub.opened, sub.index, sub.mode = true, r.index, "list"
  return text
end

local function rsRead(s, memo)
  if s.phase ~= "in" and s.phase ~= "active" then return nil end
  local feature = s.feature
  local sub = subMemo(memo, feature or s.menu)
  if not feature then return rsMenu(s, sub) end
  local mt = getmetatable(feature)
  if mt == rsModule("map") then return rsMap(feature, sub, s.shell, s.session) end
  if mt == rsModule("eyes") then return rsEyes(feature, sub, s.session) end
  if mt == rsModule("condition") then return rsGraph(feature, sub, s) end
  if mt == rsModule("condition_search") then return rsSearchList(feature, sub, s) end
  if mt == rsModule("ribbons") then return rsRibbons(feature, sub) end
  return nil
end

Nav.rubySapphire = {
  matches = Common.matcher("rs_pokenav"),
  poll = function(state, memo)
    local Pokenav = rsModule("init")
    local s = Pokenav and try(Pokenav.active)
    if type(s) ~= "table" then return nil end
    local text = rsRead(s, memo)
    if not text then return nil end
    return text, true
  end,
}

Nav.ordered = { Nav.emerald, Nav.callWindow, Nav.rubySapphire }

return Nav
