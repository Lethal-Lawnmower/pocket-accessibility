-- Hoenn special screens: the Battle Frontier (Emerald), the Trainer Hill time
-- board (Emerald), and Ruby and Sapphire's Battle Tower record board.  Every
-- value is what the named module's draw code reads.  Pictures said in words,
-- marked below: the Frontier Pass title and its MAP, CARD and CANCEL buttons,
-- the medals, the map title, the dome's CANCEL and EXIT buttons and its grey
-- "out" names, the factory's balls, the record windows' blank rows.
local Common = require("src.access.screens.gen3.Common")
local H = require("src.access.screens.gen3.HoennCommon")
local Menus = require("src.access.screens.gen3.Menus")
local Top = require("src.access.screens.gen3.Top")

local Special = {}

local say, rom, sentences, join, try, loaded = H.say, H.rom, H.sentences, H.join, H.try, H.loaded
local position = Common.position

local function plainIr(ir, session, vars)
  local TextIR = loaded("src.core.game3.scripting.text_ir")
  if not (TextIR and ir) then return nil end
  return say(try(TextIR.toPlain, ir, { playerName = session and session.name, stringVars = vars or {} }))
end

-- ---------------------------------------------------------- Frontier Pass
-- rse/frontier_pass.lua (layer "rse_frontier_pass"): `_st` { cursorX, cursorY,
-- cursorArea, desc, battlePoints, symbols, phase }, drawWindows, drawSprites,
-- Pass.areaAt.  The cursor moves freely and the pass draws no list, so where
-- no button lies under it the nearest one is named from the same rectangles
-- areaAt tests (our words; manifest `areas`).  The map is a phase of the same
-- layer (Pass.Map: pos, state, landmarks, head); Pass.MAP_ID is never pushed.

local function passManifest()
  local Gfx = loaded("src.ui.game3.rse.pokeblock_gfx")
  local g = Gfx and try(Gfx.of, "rse/frontier_pass")
  return g and try(g.manifest, g)
end

local LANDMARK_NAMES = { "gText_BattleTower3", "gText_BattleDome2", "gText_BattlePalace2", "gText_BattleArena2",
  "gText_BattleFactory2", "gText_BattlePike2", "gText_BattlePyramid2" }

-- A button's name.  MAP, CARD and CANCEL are pictures, so those are our words.
local function passAreaName(Pass, area)
  local A = Pass.AREA
  if area == A.MAP then return "MAP" end
  if area == A.CARD then return "TRAINER CARD" end
  if area == A.CANCEL then return "CANCEL" end
  if area == A.RECORD then return say(rom("gText_BattleRecord")) end
  if area == A.POINTS then return say(rom("gText_BattlePoints")) end
  if area == A.EARNED_SYMBOLS then return say(rom("gText_SymbolsEarned")) end
  local key = LANDMARK_NAMES[area - A.SYMBOL_TOWER + 1]
  return key and say(rom(key)) or nil
end

local function passAreaValue(Pass, st, area)
  local A = Pass.AREA
  if area == A.POINTS then return tostring(st.battlePoints or 0) end
  if area >= A.SYMBOL_TOWER then
    local count = st.symbols[area - A.SYMBOL_TOWER] or 0
    -- the medal's palette in drawSprites (our words)
    return count == 2 and "gold" or (count == 1 and "silver" or nil)
  end
  return nil
end

-- The nearest button to the cursor and the way to it (our words).
local function passNearest(Pass, st)
  local man = passManifest()
  if not (man and type(man.areas) == "table") then return nil end
  local A = Pass.AREA
  local x, y = st.cursorX - 5, st.cursorY + 5
  local best, bestArea, bestDx, bestDy
  for i, rect in ipairs(man.areas) do
    local area = i
    local open = area < A.SYMBOL_TOWER or (st.symbols[area - A.SYMBOL_TOWER] or 0) ~= 0
    if open and (area ~= A.RECORD or st.hasRecord) then
      local dx = x < rect.xStart and rect.xStart - x or (x > rect.xEnd and rect.xEnd - x or 0)
      local dy = y < rect.yStart and rect.yStart - y or (y > rect.yEnd and rect.yEnd - y or 0)
      local dist = dx * dx + dy * dy
      if not best or dist < best then best, bestArea, bestDx, bestDy = dist, area, dx, dy end
    end
  end
  if not bestArea then return nil end
  local name = passAreaName(Pass, bestArea)
  local way = join({ bestDy < 0 and "up" or (bestDy > 0 and "down" or nil),
    bestDx < 0 and "left" or (bestDx > 0 and "right" or nil) }, " ")
  return join({ name, way })
end

local function passFocus(Pass, st, wasNothing)
  local area = st.cursorArea
  if area == Pass.AREA.NOTHING then
    -- Past the first step in empty space, only the way to the nearest button.
    local nearest = passNearest(Pass, st)
    if nearest and wasNothing then return nearest, nearest end
    return nearest and ("Nothing here. Nearest, " .. nearest) or "Nothing here", nearest or "nothing"
  end
  local parts = {}
  local name = passAreaName(Pass, area)
  local desc = say(st.desc)
  -- A description naming its button already says it (the record's refusal does not).
  if name and not (desc and desc:upper():find(name:upper(), 1, true)) then parts[#parts + 1] = name end
  parts[#parts + 1] = desc
  parts[#parts + 1] = passAreaValue(Pass, st, area)
  return sentences(parts), area
end

-- The map: where the head picture stands (Map.headPosition), by the landmark
-- it stands on or nearest to (our words).
local function mapWhere(man, Map)
  local head = Map.head
  if not (head and man and type(man.landmarks) == "table") then return nil end
  local best, bestI
  for i, mark in ipairs(man.landmarks) do
    local dx, dy = (mark.x or 0) - head.x, (mark.y or 0) - head.y
    local dist = dx * dx + dy * dy
    if not best or dist < best then best, bestI = dist, i end
  end
  local mark = bestI and Map.landmarks[bestI - 1]
  local name = mark and say(mark.name)
  if not name then return nil end
  return (best == 0 and "You are at " or "You are near ") .. name
end

local function mapPoll(Map, memo)
  if Map.state ~= "input" and Map.state ~= "fadein" then return nil end
  if memo.mapPos == Map.pos then return nil end
  local first = memo.mapPos == nil
  memo.mapPos = Map.pos
  local mark = Map.landmarks and Map.landmarks[Map.pos]
  if not mark then return nil end
  local row = join({ say(mark.name), position(Map.pos + 1, 7) })
  if first then
    return sentences({ "Frontier map", mapWhere(passManifest(), Map), row, say(mark.description) }), true
  end
  return sentences({ row, say(mark.description) }), true
end

Special.frontierPass = {
  matches = Common.matcher("rse_frontier_pass", "src.ui.game3.rse.frontier_pass"),
  poll = function(state, memo, entering)
    local Pass = state.mod
    local st = Pass._st
    if type(st) ~= "table" or not Pass.open then return nil end
    if st.phase == "map" and Pass.Map.active then return mapPoll(Pass.Map, memo) end
    if st.phase == "record" or st.phase == "card" or st.phase == "fadeout" or st.zoom and not st.zoom.out then return nil end
    memo.mapPos = nil
    local text, key = passFocus(Pass, st, memo.nothing)
    if not entering and memo.focus == key then return nil end
    memo.focus = key
    memo.nothing = st.cursorArea == Pass.AREA.NOTHING
    if entering then
      local earned, medals = 0, 0
      for i = 0, 6 do
        local n = st.symbols[i] or 0
        if n > 0 then earned = earned + 1 end
        medals = medals + n
      end
      text = sentences({ "Frontier pass. The control pad moves a cursor",
        join({ say(rom("gText_BattlePoints")), tostring(st.battlePoints or 0) }, " "),
        join({ say(rom("gText_SymbolsEarned")), tostring(medals) }, " "), text })
    end
    if not text then return nil end
    return text, true
  end,
}

-- --------------------------------------------- record and BP windows
-- rse/frontier_records.lua: `_window` and `_bp`, windows that draw over the
-- field with no input and hold `prints` { s, x, y }; the facility results,
-- ranking hall, link battle and link contest records, and natives_blender's
-- record window.  A new window object is a new showing (the ranking hall's
-- level page replaces the object), so it speaks by itself; a full row of dashes
-- is a rule or an empty record, and a rank with no name is a blank row (our word).
local function windowLines(win)
  local rows, order = {}, {}
  for _, p in ipairs(win.prints or {}) do
    if not rows[p.y] then
      rows[p.y] = {}
      order[#order + 1] = p.y
    end
    table.insert(rows[p.y], p)
  end
  table.sort(order)
  local lines = {}
  for _, y in ipairs(order) do
    table.sort(rows[y], function(a, b) return a.x < b.x end)
    local cells = {}
    for _, p in ipairs(rows[y]) do cells[#cells + 1] = say(p.s) end
    local line = join(cells, " ")
    if line then line = line:gsub("(%d)BP", "%1 BP") end
    if line and not line:find("^[%-%s]+$") then
      if line:find("^%d+%.?$") then line = line .. " empty" end
      lines[#lines + 1] = line
    end
  end
  return lines
end

Top.addAmbient(function(game, proxy)
  local Records = loaded("src.ui.game3.rse.frontier_records")
  local win = Records and Records._window
  if not win then return nil end
  return proxy(win, "frontier_records", { mod = Records, window = win, game = game })
end)

Special.frontierRecords = {
  matches = Common.matcher("frontier_records"),
  poll = function(state, memo)
    if memo.said then return nil end
    memo.said = true
    return sentences(windowLines(state.window)), false
  end,
}

Top.addAmbient(function(game, proxy)
  local Records = loaded("src.ui.game3.rse.frontier_records")
  local win = Records and Records._bp
  if not win then return nil end
  return proxy(win, "frontier_bp", { mod = Records, window = win, game = game })
end)

Special.frontierBp = {
  matches = Common.matcher("frontier_bp"),
  poll = function(state, memo)
    local text = sentences(windowLines(state.window))
    if text == memo.text then return nil end
    memo.text = text
    return text, false
  end,
}

-- ------------------------------------------------ Frontier list descriptions
-- rse/frontier_preview.lua draws a description beside the exchange corner's and
-- the tutors' script lists.  The list's own presenter says the row; this adds
-- the description M.draw prints.  The last row draws EXIT, the row's own word.
local PREVIEW_FILES = { [3] = "decor1", [4] = "decor2", [5] = "vitamins", [6] = "holdItems" }

local function previewDescription(Preview, menu)
  local index = menu.selection() + 1
  if Preview.exchangeOpen then
    local file = PREVIEW_FILES[tonumber(menu.kind)]
    local id = file and Preview.ids(file)[index]
    if not id then return nil end
    local info
    if file == "decor1" or file == "decor2" then
      local Inv = loaded("src.core.game3.rse.decoration_inventory")
      info = Inv and Inv.info(id)
    else
      local Items = loaded("src.core.game3.items_data")
      info = Items and Items.info(id)
    end
    return info and say(info.description)
  end
  local id = Preview.ids(menu.kind == 9 and "tutor1" or "tutor2")[index]
  if not id then return nil end
  local Pokemon, Summary = loaded("src.core.game3.pokemon"), loaded("src.core.game3.summary_data")
  if not (Pokemon and Summary) then return nil end
  return say(Summary.moveDescription(id, Pokemon.moveName(id)))
end

Special.frontierList = {
  matches = function(state)
    if not Menus.scriptListMenu.matches(state) then return false end
    local Preview = loaded("src.ui.game3.rse.frontier_preview")
    if not Preview then return false end
    local kind = state.mod.kind
    return Preview.exchangeOpen == true or (Preview.tutorOpen == true and (kind == 9 or kind == 10))
  end,
  poll = function(state, memo, entering)
    local label, interrupt = Menus.scriptListMenu.poll(state, memo, entering)
    if not label then return nil end
    -- The price is drawn in its own column, so it arrives glued to the name.
    label = label:gsub("(%D)(%d+)BP", "%1, %2 BP")
    local Preview = loaded("src.ui.game3.rse.frontier_preview")
    return sentences({ label, try(previewDescription, Preview, state.mod) }), interrupt
  end,
}

-- ------------------------------------------------------------- Battle Dome
-- rse/dome_tourney.lua (layer "rse_dome_tourney"): `_st` { screen, mode, cursor,
-- names, phase, card { kind, data }, cardMode, pos, returnTree }.  Cursor 0-15 are
-- the trainers (names by M.treeTrainerIds), 16-30 the matches, UI.CLOSE_BUTTON
-- the sprite button.  Trees show names and lines; a grey name or lost line is
-- said as "out" with the round text (our word).

local function domeData()
  local Gfx = loaded("src.ui.game3.rse.pokeblock_gfx")
  local g = Gfx and try(Gfx.of, "rse/frontier_f2")
  local man = g and try(g.manifest, g)
  return man and man.dome
end

local function domeSession(st)
  if st.session then return st.session end
  local Runtime = loaded("src.core.game3.runtime")
  return Runtime and Runtime.getSession()
end

local function domeSpecies(list)
  local Pokemon = loaded("src.core.game3.pokemon")
  local names = {}
  for i = 1, 3 do names[#names + 1] = Pokemon and say(try(Pokemon.name, list[i])) or nil end
  return join(names)
end

-- A match: its number, who meets whom and the result line (drawMatchCard).
local function domeMatchText(session, matchNo)
  local Dome = loaded("src.core.game3.rse.frontier.dome")
  local M = domeData()
  if not (Dome and M) then return nil end
  local f = Dome.frontier(session)
  local ws = Dome.winString(session, matchNo)
  local names = {}
  for i = 1, 2 do
    local tid = ws.tournamentIds[i]
    local trainer = tid and f.domeTrainers[tid + 1]
    names[i] = trainer and say(Dome.trainerName(session, trainer.trainerId)) or nil
  end
  local versus = (names[1] and names[2]) and (names[1] .. " against " .. names[2]) or (names[1] or names[2])
  return plainIr(Dome.tableText(M.text.matchNumbers, "sBattleDomeMatchNumberTexts", matchNo + 1), session), versus,
    plainIr(Dome.tableText(M.text.wins, "sBattleDomeWinTexts", ws.id + 1), session, { ws.var1, ws.var2 })
end

local function domeTreeFocus(UI, st)
  local session = domeSession(st)
  local Dome = loaded("src.core.game3.rse.frontier.dome")
  local M = domeData()
  if not (Dome and M and session) then return nil end
  local cursor = st.cursor
  if cursor == UI.CLOSE_BUTTON then return st.mode == "prev" and "EXIT" or "CANCEL" end
  if cursor < 16 then
    local tid = M.treeTrainerIds[cursor + 1]
    local trainer = Dome.frontier(session).domeTrainers[tid + 1]
    local name = st.names[tid] and say(st.names[tid].text)
    local out
    if trainer.isEliminated then
      local round = plainIr(Dome.tableText(M.text.rounds, "gRoundsStringTable", trainer.eliminatedAt + 1), session)
      out = join({ "out", round })
    end
    return sentences({ join({ name, out }), position(cursor + 1, 16) })
  end
  local number, versus, result = domeMatchText(session, cursor - 16)
  return sentences({ number, versus, result })
end

-- The arrows drawArrows shows on a card from the tree (updateArrows).
local function domeArrows(st, session)
  local Dome = loaded("src.core.game3.rse.frontier.dome")
  local M = domeData()
  if st.cardMode == "next" or not (Dome and M) then return nil end
  local f = Dome.frontier(session)
  local cur = tonumber(f.curChallengeBattleNum) or 0
  local up, left, right
  if st.cardMode == "trainer" then
    local trainer = f.domeTrainers[M.treeTrainerIds[st.cursor + 1] + 1]
    up, left = st.pos == 0, st.pos ~= 0
    right = (trainer.isEliminated and st.pos - 1 < trainer.eliminatedAt)
      or ((not trainer.isEliminated) and st.pos - 1 < cur)
  else
    up, left, right = st.pos == 1, st.pos ~= 0, st.pos <= 1
  end
  local ways = join({ up and "up and down" or nil, left and "left" or nil, right and "right" or nil })
  return ways and ("More with " .. ways) or nil
end

local function domeCardText(st, session)
  local card = st.card
  local d = card.data
  if card.kind == "trainer" then
    return sentences({ say(d.title), domeSpecies(d.species), plainIr(d.potential, session), plainIr(d.styleText, session),
      plainIr(d.statText, session), domeArrows(st, session) })
  end
  local parts = { plainIr(d.matchNoIr, session) }
  for _, side in ipairs(d.sides or {}) do
    parts[#parts + 1] = join({ say(side.name), side.lost and "out" or nil, domeSpecies(side.species) })
  end
  parts[#parts + 1] = plainIr(d.winIr, session, { d.win.var1, d.win.var2 })
  parts[#parts + 1] = domeArrows(st, session)
  return sentences(parts)
end

-- The static tree between rounds: who is still in, as its lines and names show.
local function domeRemaining(st, session)
  local Dome = loaded("src.core.game3.rse.frontier.dome")
  if not Dome then return nil end
  local f = Dome.frontier(session)
  local names = {}
  for i = 0, 15 do
    local trainer = f.domeTrainers[i + 1]
    if not trainer.isEliminated and st.names[i] then names[#names + 1] = say(st.names[i].text) end
  end
  local list = join(names)
  return list and ("Still in: " .. list) or nil
end

Special.domeTourney = {
  matches = Common.matcher("rse_dome_tourney", "src.ui.game3.rse.dome_tourney"),
  poll = function(state, memo)
    local UI = state.mod
    local st = UI._st
    if type(st) ~= "table" or not UI.open or st.phase == "fadeout" then return nil end
    local session = domeSession(st)
    if st.screen == "tree" then
      local newTree = memo.view ~= "tree"
      memo.view, memo.card = "tree", nil
      if st.mode == "static" then
        local parts = {}
        if newTree then parts[#parts + 1] = say(st.treeTitle) end
        if st.phase == "wait" and not memo.waited then
          memo.waited = true
          parts[#parts + 1] = domeRemaining(st, session)
          parts[#parts + 1] = "Press A"
        end
        local text = sentences(parts)
        if not text then return nil end
        return text, true
      end
      if not newTree and memo.cursor == st.cursor then return nil end
      memo.cursor = st.cursor
      local focus = try(domeTreeFocus, UI, st)
      local text = newTree and sentences({ say(st.treeTitle), focus }) or focus
      if not text then return nil end
      return text, true
    end
    memo.view, memo.cursor = "card", nil
    if not st.card or memo.card == st.card then return nil end
    memo.card = st.card
    local text = try(domeCardText, st, session)
    if not text then return nil end
    return text, true
  end,
}

-- --------------------------------------------------------- Battle Factory
-- rse/factory_select.lua (layer "rse_factory_select", `_st`: mons, cursor,
-- menuCursor, yesNoCursor, info, phase) and rse/factory_swap.lua (layer
-- "rse_factory_swap", `_st`: party, enemy, inEnemyScreen, actions, cursor,
-- menuCursor, yesNoCursor, info, phase).  Species and category as Select.draw
-- prints them, Common.categoryText and speciesName; the balls are pictures, so a
-- chosen ball is said as "chosen" with its order (our word).

local function factoryMon(Shared, mon)
  if not mon then return nil end
  return join({ say(try(Shared.speciesName, mon.species)), say(try(Shared.categoryText, mon.species)) })
end

local function menuRow(keys, cursor)
  return join({ say(rom(keys[cursor + 1])), position(cursor + 1, #keys) })
end

local SELECT_ORDER = { "first", "second", "third" }

Special.factorySelect = {
  matches = Common.matcher("rse_factory_select", "src.ui.game3.rse.factory_select"),
  poll = function(state, memo, entering)
    local Select = state.mod
    local st = Select._st
    if type(st) ~= "table" or not Select.open or st.phase == "exit" or st.phase == "exit_wait" then return nil end
    local parts = {}
    if entering then parts[#parts + 1] = say(rom("gText_RentalPkmn2")) end
    local info = say(st.info)
    if info ~= memo.info then
      memo.info = info
      parts[#parts + 1] = info
    end
    local phase, key, row = st.phase, nil, nil
    if phase == "fadein" or phase == "choose" then
      local m = st.mons[st.cursor]
      key = "mon" .. st.cursor .. ":" .. m.selectedId
      local order = SELECT_ORDER[m.selectedId]
      row = join({ factoryMon(Select.Common, m.monData), order and ("chosen " .. order) or nil,
        position(st.cursor, #st.mons) })
    elseif st.menuShown and (phase == "menu" or phase == "menu_reinit") then
      key = "menu" .. st.menuCursor
      local rent = st.mons[st.cursor].selectedId ~= 0 and "gText_Deselect" or "gText_Rent"
      row = menuRow({ "gText_Summary", rent, "gText_Others2" }, st.menuCursor)
    elseif st.yesNoShown then
      key = "yesno" .. st.yesNoCursor
      local parted = memo.key and memo.key:find("^yesno")
      local names = {}
      if not parted then
        for order, index in pairs(try(Select.chosenIndices) or {}) do
          names[order] = say(try(Select.Common.speciesName, st.mons[index].monData.species))
        end
        parts[#parts + 1] = join({ names[1], names[2], names[3] })
      end
      row = say(rom(st.yesNoCursor == 0 and "gText_Yes2" or "gText_No2"))
    end
    if key ~= memo.key then
      memo.key = key
      parts[#parts + 1] = row
    end
    local text = sentences(parts)
    if not text then return nil end
    return text, true
  end,
}

Special.factorySwap = {
  matches = Common.matcher("rse_factory_swap", "src.ui.game3.rse.factory_swap"),
  poll = function(state, memo, entering)
    local Swap = state.mod
    local st = Swap._st
    if type(st) ~= "table" or not Swap.open or st.phase == "exit" then return nil end
    local Shared = package.loaded["src.ui.game3.rse.factory_select"].Common
    local parts = {}
    if entering then parts[#parts + 1] = say(rom("gText_PkmnSwap")) end
    local info = say(st.info)
    if info ~= memo.info then
      memo.info = info
      parts[#parts + 1] = info
    end
    local party = st.inEnemyScreen and st.enemy or st.party
    local mon = st.cursor < 3 and party[st.cursor + 1] or nil
    local phase, key, row = st.phase, nil, nil
    if phase == "fadein" or phase == "choose" then
      key = (st.inEnemyScreen and "enemy" or "party") .. st.cursor
      if mon then
        row = factoryMon(Shared, mon)
      else
        local act = st.actions[st.cursor + 1]
        row = say(rom(act == Swap.ACTION.PKMN_FOR_SWAP and "gText_PkmnForSwap" or "gText_Cancel3"))
      end
      row = join({ row, position(st.cursor + 1, #st.actions) })
    elseif st.menuShown and (phase == "menu" or phase == "menu_reinit") then
      key = "menu" .. st.menuCursor
      row = menuRow({ "gText_Summary2", "gText_Swap", "gText_Rechoose" }, st.menuCursor)
    elseif phase == "yesno" then
      key = "yesno" .. st.yesNoCursor
      local first = not (memo.key and memo.key:find("^yesno"))
      row = say(rom(st.yesNoCursor == 0 and "gText_Yes3" or "gText_No3"))
      if first and mon and st.monSwapped then row = join({ factoryMon(Shared, mon), row }) end
    end
    if key ~= memo.key then
      memo.key = key
      parts[#parts + 1] = row
    end
    local text = sentences(parts)
    if not text then return nil end
    return text, true
  end,
}

-- ------------------------------------------------------------ Pyramid bag
-- rse/pyramid_bag.lua (layer "rse_pyramid_bag"): `_st` { mode, count, location,
-- menuCursor, tossNum, yesNo, message }, PBag.description() (the info window),
-- Py.bagCursor, Py.bagLists, gText_CloseBag for the last row.  itemName as in
-- the draw: a berry through gText_NumberItem_TMBerry.
local function pyramidItemName(id)
  local Items = loaded("src.core.game3.items_data")
  if Items.pocketOf(id) == "BERRY_POUCH" then
    -- The number and the name are drawn in columns, so they arrive glued.
    local text = say(rom("gText_NumberItem_TMBerry", { stringVars = { string.format("%02d", Items.berryNumber(id) or 0),
      Items.displayName(id) } }))
    return text and (text:gsub("(%d)(%a)", "%1, %2")) or nil
  end
  return say(Items.displayName(id))
end

local function pyramidRow(PBag, st, Py)
  local cur = Py.bagCursor
  local index = cur.scroll + cur.cursor
  local item, qty = PBag.selectedItem()
  local label
  if item then
    label = join({ pyramidItemName(item), "times " .. tostring(qty) })
  else
    label = say(rom("gText_CloseBag"))
  end
  return join({ label, position(index + 1, st.count) })
end

-- actionsFor in the module.
local function pyramidActions(PBag, st)
  if st.location == "battle" then
    local item = PBag.selectedItem()
    local Items = loaded("src.core.game3.items_data")
    local info = item and Items.info(item)
    if info and (tonumber(info.battleUsage) or 0) ~= 0 then return PBag.ACTIONS.battle end
    return PBag.ACTIONS.battle_cannot
  end
  return PBag.ACTIONS[st.location] or PBag.ACTIONS.field
end

Special.pyramidBag = {
  matches = Common.matcher("rse_pyramid_bag", "src.ui.game3.rse.pyramid_bag"),
  poll = function(state, memo, entering)
    local PBag = state.mod
    local st = PBag._st
    if type(st) ~= "table" or not PBag.open or st.mode == "closing" then return nil end
    local Py = loaded("src.core.game3.rse.frontier.pyramid")
    if not (Py and Py.bagCursor) then return nil end
    local mode = st.mode
    local cur = Py.bagCursor
    local index = cur.scroll + cur.cursor
    local desc = say(try(PBag.description))
    local parts = {}
    if entering then parts[#parts + 1] = "Pyramid bag" end
    if mode == "list" or mode == "swap" then
      local key = mode .. index
      if not entering and memo.key == key then return nil end
      memo.key = key
      parts[#parts + 1] = pyramidRow(PBag, st, Py)
      -- In swap mode the info window keeps the question; said when it starts.
      if mode == "list" or memo.mode ~= "swap" then parts[#parts + 1] = desc end
    elseif mode == "action" then
      local key = "action" .. st.menuCursor
      if memo.key == key then return nil end
      local first = memo.mode ~= "action"
      memo.key = key
      if first then parts[#parts + 1] = desc end
      local acts = pyramidActions(PBag, st)
      parts[#parts + 1] = join({ say(rom(PBag.ACTION_TEXT[acts[st.menuCursor]])), position(st.menuCursor, #acts) })
    elseif mode == "toss" then
      local key = "toss" .. st.tossNum
      if memo.key == key then return nil end
      local first = memo.mode ~= "toss"
      memo.key = key
      if first then parts[#parts + 1] = desc end
      parts[#parts + 1] = "times " .. tostring(st.tossNum)
    elseif mode == "toss_confirm" then
      local key = "confirm" .. st.yesNo
      if memo.key == key then return nil end
      local first = memo.mode ~= "toss_confirm"
      memo.key = key
      if first then parts[#parts + 1] = desc end
      parts[#parts + 1] = H.yesNo(st.yesNo)
    elseif mode == "toss_done" then
      if memo.key == "done" then return nil end
      memo.key = "done"
      parts[#parts + 1] = desc
    elseif mode == "message" then
      if memo.key == st.message then return nil end
      memo.key = st.message
      parts[#parts + 1] = say(st.message)
    else
      return nil
    end
    memo.mode = mode
    local text = sentences(parts)
    if not text then return nil end
    return text, true
  end,
}

-- ---------------------------------------------------- Trainer Hill time board
-- rse/trainer_hill_records.lua (layer "rse_trainer_hill_records"): `_st.lines`,
-- each { text, x, y }, as the draw prints them.
Special.trainerHillRecords = {
  matches = Common.matcher("rse_trainer_hill_records", "src.ui.game3.rse.trainer_hill_records"),
  poll = function(state, memo)
    local st = state.mod._st
    if memo.said or type(st) ~= "table" or type(st.lines) ~= "table" then return nil end
    memo.said = true
    local parts = {}
    for _, line in ipairs(st.lines) do parts[#parts + 1] = say(line.text) end
    return sentences(parts), true
  end,
}

-- --------------------------------------- Ruby and Sapphire's tower record board
-- rs/battle_tower_records.lua draws over the field with no input: Board.model()
-- { title, rows { level, label, streak, recordLabel, record } } and the
-- manifest's streak string.  Board.isVisible can hide the board, so `visible`
-- is read instead.
Top.addAmbient(function(game, proxy)
  local Board = loaded("src.ui.game3.rs.battle_tower_records")
  local model = Board and Board.visible == true and Board.model()
  if not model then return nil end
  return proxy(model, "rs_tower_records", { model = model, game = game })
end)

Special.rsTowerRecords = {
  matches = Common.matcher("rs_tower_records"),
  poll = function(state, memo)
    if memo.said then return nil end
    memo.said = true
    local Kit = loaded("src.ui.game3.rse.scene_kit")
    local man = Kit and try(Kit.manifest, "rse/battle_tower_records")
    local format = man and man.strings and man.strings.streak
    if not format then return nil end
    local function streak(value)
      -- "12W STREAK" as drawn; a space so the number is not read as a word.
      local text = format:gsub("{STR_VAR_1}", function() return tostring(value) end)
      return say((text:gsub("(%d)W%f[%A]", "%1 W")))
    end
    local parts = { say(state.model.title) }
    for _, row in ipairs(state.model.rows) do
      parts[#parts + 1] = join({ say(row.level), say(row.label), streak(row.streak) }, " ")
      parts[#parts + 1] = join({ say(row.recordLabel), streak(row.record) }, " ")
    end
    return sentences(parts), false
  end,
}

Special.ordered = {
  Special.frontierPass, Special.frontierRecords, Special.frontierBp, Special.frontierList, Special.domeTourney,
  Special.factorySelect, Special.factorySwap, Special.pyramidBag, Special.trainerHillRecords, Special.rsTowerRecords,
}

return Special
