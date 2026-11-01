-- Gen 2 battle speech (Gold, Silver, Crystal; decision 27).
--
-- The battle screen is src/ui/gen2/BattleState.lua, matched by its metatable
-- (link battles are pushed onto the stack without Screens.push, so they have
-- no screenId).  The engine (src/battle/gen2/Battle.lua) resolves a whole
-- turn before the first line plays, so everything about the two sides is read
-- from the copies the HUD draws: activeMon(side), hudHp(mon, side),
-- hudStatus / statusTag(mon, side).  Only fields and pure methods are read;
-- Battle:moveDisabled, Battle:partyMoves and BugContest.state create tables
-- when they are called, so their fields are read directly instead.
--
-- What is spoken, phase by phase (state.phase):
--   any phase   the message box (state.message): each new line once, queued,
--               paced like the box.  A scroll page repeats the previous
--               page's last row (messageCarried); that row is dropped so
--               nothing is said twice.  DIALOGUE SPEECH set to ALL AT ONCE
--               (decision 26) says every page of a box when it opens.
--   menu        on opening, both sides as the Gen 1 presenter words them
--               (your HP exactly, the enemy's level and HP as a percentage,
--               since its HUD is a bar), then the command; then each command.
--               The summary queues (an auto-advancing last line such as the
--               enemy's move is not cut off); shiny and gender are added the
--               first time each Pokémon is summarised in a battle.
--   moves       move, type, PP (or "disabled"), position on opening.
--   ask-*       the question is the message; YES / NO once the box is drawn.
--   choose-forget  the four-move list (name and PP), position on opening.
--   stats-box   the level-up stats window, five stats as the box lists them.
-- Party, pack, naming, Pokédex and evolution screens are pushed on top and
-- belong to their own presenters.  Gen2Battle.health(state, side) is the
-- on-demand HP read (the counterpart of H / Shift+H) for the command layer.
--
-- Polling is once per rendered frame; at a GAME SPEED above 1 several logic
-- steps run between polls, so a line that is shown and replaced within one
-- frame is not spoken.  Only self-advancing lines can be (a move line,
-- "Go! X!"): a scripted Crystal run with BATTLE SCENE off lost 2 of 14 lines
-- at 200X and none at 8X or 64X (tests/access/drivers/gen2_battle.lua, fast).

local Common = require("src.access.screens.gen2.Common")
local Settings = require("src.access.Settings")

local Gen2Battle = {}

local function battleClass()
  return package.loaded["src.ui.gen2.BattleState"]
end

local function isBattle(state)
  local class = battleClass()
  return class ~= nil and type(state) == "table" and getmetatable(state) == class
end
Gen2Battle.isBattle = isBattle

local function gameData(state)
  local game = state.game
  return (game and game.data) or (state.battle and state.battle.data) or {}
end

local function module(path)
  return package.loaded[path]
end

local function position(index, count)
  return Common.position(index, count)
end

-- Joins the first `count` entries with ", ", skipping nil and empty ones
-- (table.concat stops at the first nil).
local function join(list, count)
  local out = {}
  for i = 1, count do
    if list[i] ~= nil and list[i] ~= "" then out[#out + 1] = list[i] end
  end
  return table.concat(out, ", ")
end

-- ---------------------------------------------------------------- the sides

-- The name the HUD prints (BattleState:name), or nil when there is none.
local function monName(mon)
  if type(mon) ~= "table" then return nil end
  local name = mon.nickname or mon.name or mon.species
  if name == nil then return nil end
  return Common.speakable(name)
end

local function activeMon(state, side)
  local mon = state.activeMon and state:activeMon(side)
  if type(mon) == "table" then return mon end
  return nil
end

local function maxHpOf(mon)
  return tonumber(mon.maxHp or (type(mon.stats) == "table" and mon.stats.hp))
end

local function shownHp(state, mon, side)
  if state.hudHp then return tonumber(state:hudHp(mon, side)) end
  return tonumber(mon.hp)
end

-- The status tag the HUD prints (PSN, PAR...), as the Gen 1 presenter says it.
local function statusTag(state, mon, side)
  if not state.statusTag then return nil end
  local ok, tag = pcall(state.statusTag, state, mon, side)
  if ok and type(tag) == "string" and tag ~= "" then return Common.speakable(tag) end
  return nil
end

-- Mod seams the HUD consults before drawing (battle.status_hud_visible, RFC
-- 0019's pokemon.level_visible).  Both default to shown and are queries only.
local function hudVisible(state)
  if not state.statusHUDVisible then return true end
  local ok, visible = pcall(state.statusHUDVisible, state)
  return not ok or visible ~= false
end

local function levelVisible(state, mon, where)
  local LevelDisplay = module("src.ui.LevelDisplay")
  if not LevelDisplay then return true end
  local ok, visible = pcall(LevelDisplay.visible, mon, where, state.game)
  return not ok or visible ~= false
end

local GENDER_WORDS = { male = "male", female = "female" }

-- Shiny and gender are drawn on the field (the shiny palette and sparkle,
-- the HUD's gender symbol); they are said the first time each Pokémon is
-- summarised in a battle, not on every turn or every switch-in.
local function extras(memo, mon)
  memo.introduced = memo.introduced or setmetatable({}, { __mode = "k" })
  if memo.introduced[mon] then return nil, nil end
  memo.introduced[mon] = true
  return mon.shiny and "shiny" or nil, GENDER_WORDS[mon.gender]
end

-- Both sides as the HUD shows them, in the Gen 1 presenter's words.
local function sides(state, memo)
  if not hudVisible(state) then return nil end
  local parts = {}
  local player = activeMon(state, "player")
  local playerName = player and monName(player)
  local hp, maxHp = player and shownHp(state, player, "player"), player and maxHpOf(player)
  if playerName and hp and maxHp then
    local shiny, gender = extras(memo, player)
    parts[#parts + 1] = join({ playerName, shiny, gender,
      string.format("HP %d of %d", hp, maxHp), statusTag(state, player, "player") }, 5)
  end
  local enemy = activeMon(state, "enemy")
  local enemyName = enemy and monName(enemy)
  hp, maxHp = enemy and shownHp(state, enemy, "enemy"), enemy and maxHpOf(enemy)
  if enemyName and hp and maxHp and maxHp > 0 then
    local shiny, gender = extras(memo, enemy)
    local level = levelVisible(state, enemy, "battle.enemy") and tonumber(enemy.level)
    parts[#parts + 1] = join({ "enemy " .. enemyName, shiny,
      level and ("level " .. level) or nil, gender,
      string.format("HP %d percent", math.ceil(100 * math.max(0, hp) / maxHp)),
      statusTag(state, enemy, "enemy") }, 6)
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ". ")
end

-- Status words for the on-demand read, as Navigation's STATUS_WORDS give
-- them for Gen 1 (the HUD tag PSN covers toxic too).
local STATUS_WORDS = {
  poison = "poisoned", toxic = "poisoned", burn = "burned", freeze = "frozen",
  paralyze = "paralyzed", sleep = "asleep",
}

-- On-demand health, the Gen 2 counterpart of the navigation layer's H and
-- Shift+H (Navigation:readBattleHealth), in the same words.  Shown values,
-- and "No bar found" while that side's HUD is not on screen.
function Gen2Battle.health(state, side)
  if not isBattle(state) then return nil end
  local mon = activeMon(state, side)
  local hudUp
  if side == "enemy" then hudUp = state.showEnemyHud else hudUp = state.showPlayerHud end
  local hp = mon and shownHp(state, mon, side)
  local maxHp = mon and maxHpOf(mon)
  if not (hudUp and hudVisible(state) and hp and maxHp and maxHp > 0) then
    return "No bar found"
  end
  if side == "enemy" then
    return string.format("Enemy health: %.2f percent", hp * 100 / maxHp)
  end
  local text = string.format("Player %s, %d of %d HP", monName(mon) or "Pokemon", hp, maxHp)
  local status = state.hudStatus and state:hudStatus(mon, side)
  if status then
    text = text .. ", " .. (STATUS_WORDS[status] or statusTag(state, mon, side) or tostring(status))
  end
  return text
end

-- ---------------------------------------------------------------- menus

-- FIGHT / PKMN on top, PACK / RUN below (BattleState's MENU, 2x2).  The
-- <PK><MN> ligature is said "POKéMON", as the Gen 1 presenter says Gen 1's.
-- Inside the Bug-Catching Contest the third slot is the PARK BALL throw.
local function menuLabel(state, index)
  if index == 3 and state.contest then
    local contest = state.save and state.save.bugContest
    return string.format("PARK BALL, %d left", tonumber(contest and contest.balls) or 0)
  end
  return ({ "FIGHT", "POKéMON", "PACK", "RUN" })[index]
end

local function typeName(data, typeId)
  if typeId == nil then return nil end
  local TypeChart = module("src.battle.TypeChart")
  local name = TypeChart and TypeChart.displayName(typeId, data) or typeId
  name = Common.speakable(name)
  -- CURSE's type prints as "???", which screen readers skip or spell
  if name:match("^%?+$") then return "question marks" end
  return name
end

local function maxPpOf(data, move)
  local stored = tonumber(move.maxPp)
  if stored then return stored end
  local Mon = module("src.battle.gen2.Mon")
  local max = Mon and Mon.maxPpOf(move, data)
  if max and max > 0 then return max end
  return nil
end

-- "PP 12 of 35".  Missing PP is unknown, never 0: it is left out.
local function ppText(data, move)
  local pp = tonumber(move.pp)
  if not pp then return nil end
  local max = maxPpOf(data, move)
  if max then return string.format("PP %d of %d", pp, max) end
  return string.format("PP %d", pp)
end

local function moveName(data, move)
  local def = data.moves and data.moves[move.id]
  return Common.speakable(def and def.name or move.id), def
end

local function playerMoves(state)
  local player = state.battle and state.battle.player
  return (player and player.moves) or {}
end

-- MoveInfoBox: "Disabled!" in place of the type and PP when the move is
-- disabled; read from the volatile table without creating it.
local function moveLine(state, move)
  if type(move) ~= "table" then return nil end
  local data = gameData(state)
  local name, def = moveName(data, move)
  local player = state.battle and state.battle.player
  local volatile = player and rawget(player, "volatile")
  if type(volatile) == "table" and volatile.disabled ~= nil and volatile.disabled == move.id then
    return name .. ", disabled"
  end
  return join({ name, typeName(data, def and def.type), ppText(data, move) }, 3)
end

-- The moves ForgetMoveList draws: Battle:partyMoves' answer, read without its
-- write (it creates preTransform.moves when missing).
local function forgetMoves(state)
  local learn = state.pendingLearn
  local party = state.battle and state.battle.party
  local mon = learn and party and party[learn.index]
  if type(mon) ~= "table" then return playerMoves(state) end
  local volatile = rawget(mon, "volatile")
  if type(volatile) == "table" then
    if volatile.mimicMoves then return volatile.mimicMoves end
    local pre = volatile.preTransform
    if type(pre) == "table" then return pre.moves or {} end
  end
  return mon.moves or playerMoves(state)
end

local function forgetRow(state, move)
  if type(move) ~= "table" then return "empty" end
  local data = gameData(state)
  return join({ (moveName(data, move)), ppText(data, move) }, 2)
end

-- The level-up stats window: drawStatsBox recomputes the stats from the
-- species' base stats (pokecrystal core.asm:7208-7213), so this does too.
local STATS_ROWS = {
  { "attack", "attack" }, { "defense", "defense" },
  { "special attack", "specialAttack" }, { "special defense", "specialDefense" },
  { "speed", "speed" },
}
local function statsText(state, mon)
  local data = gameData(state)
  local stats = mon.stats
  local Mon = module("src.battle.gen2.Mon")
  local def = Mon and data.pokemon and data.pokemon[Mon.partySpecies(mon)]
  if def and def.baseStats then
    stats = Mon.stats(def.baseStats, mon.dvs, mon.level, mon.statExp)
  end
  local name = monName(mon)
  if type(stats) ~= "table" or not name then return nil end
  local values = {}
  for _, row in ipairs(STATS_ROWS) do
    local value = tonumber(stats[row[2]])
    if value then values[#values + 1] = row[1] .. " " .. value end
  end
  if #values == 0 then return nil end
  local level = tonumber(mon.level)
  return string.format("%s, %sstats: %s", name, level and ("level " .. level .. " ") or "",
    table.concat(values, ", "))
end

-- YES / NO boxes and the field holding each one's cursor (1 = YES).  The box
-- is drawn only once the question has been acknowledged (messageTimer 0).
local CHOICE_FIELD = {
  ["ask-nickname"] = "nicknameIndex", ["ask-shift"] = "shiftIndex",
  ["ask-next-mon"] = "nextMonIndex", ["ask-forget"] = "forgetChoice",
  ["stop-learning"] = "forgetChoice",
}
local CHOICES = { "YES", "NO" }

-- ---------------------------------------------------------------- messages

local function rows(text)
  local out = {}
  for row in (tostring(text) .. "\n"):gmatch("([^\n\v\f]*)[\n\v\f]") do out[#out + 1] = row end
  return out
end

local function without(list, first)
  local out = {}
  for i = first, #list do out[#out + 1] = list[i] end
  return out
end

-- A scroll page opens on the previous page's last row (paginate / foldPages
-- mark it in messageCarried).  The flag survives later direct writes, so the
-- row is dropped only when it really is the last row just spoken.
local function carriedFrom(state, index, pageRows, previousRows)
  local carried = type(state.messageCarried) == "table" and state.messageCarried[index]
  return carried and previousRows ~= nil and #previousRows > 0
    and pageRows[1] == previousRows[#previousRows]
end

-- Every page of a multi-page box as one sentence (ALL AT ONCE).
local function wholeBox(state, pages)
  local all, previous = {}, nil
  for i, page in ipairs(pages) do
    local pageRows = rows(page)
    local keep = pageRows
    if i > 1 and carriedFrom(state, i, pageRows, previous) then keep = without(pageRows, 2) end
    for _, row in ipairs(keep) do all[#all + 1] = row end
    previous = pageRows
  end
  return Common.lines(all), previous
end

-- A new line in the message box, or nil.  A line is new when the string
-- changes, or when the same string is shown again: showPages leaves
-- typedText nil until the typer picks the line up on the next update or
-- draw, so "message set, typedText nil" after it was typed marks a re-show
-- (two "A critical hit!" lines in a row).
local function messageLine(state, memo)
  local message = state.message
  if type(message) ~= "string" or message == "" then
    memo.message, memo.typed = nil, false
    return nil
  end
  local fresh = message ~= memo.message or (state.typedText == nil and memo.typed)
  if not fresh then
    if state.typedText == message then memo.typed = true end
    return nil
  end
  memo.message, memo.typed = message, state.typedText == message
  local pageRows = rows(message)
  local previous = memo.rows
  memo.rows = pageRows

  if Settings.dialogueWhole(state.game) then
    local pages = state.messagePages
    if type(pages) == "table" and state.messagePage == 1 and pages[1] == message then
      memo.wholePages = pages
      local text, last = wholeBox(state, pages)
      memo.rows = last
      return text ~= "" and text or nil
    end
    if memo.wholePages and memo.wholePages[state.messagePage or 0] == message then
      return nil -- a later page of a box already said whole
    end
  end
  memo.wholePages = nil

  local keep = pageRows
  if carriedFrom(state, state.messagePage, pageRows, previous) then keep = without(pageRows, 2) end
  local text = Common.lines(keep)
  if text == "" then return nil end
  return text
end

-- ---------------------------------------------------------------- presenter

local function menuPart(state, memo, newPhase)
  if state.tutorial then return nil end -- the DUDE's demonstration drives it
  if not newPhase and memo.menu == state.menuIndex then return nil end
  memo.menu = state.menuIndex
  local label = menuLabel(state, state.menuIndex)
  if not label then return nil end
  if newPhase then
    local summary = sides(state, memo)
    -- queued, so an auto-advancing last line ("Enemy X used TACKLE!") is
    -- not cut off by the turn summary
    return summary and (summary .. ". " .. label) or label, false
  end
  return label, true
end

local function movesPart(state, memo, newPhase)
  local moves = playerMoves(state)
  local index = state.moveIndex
  local move = moves[index]
  local swap = state.moveSwapIndex
  local sameRow = not newPhase and memo.move == index
  if sameRow and memo.moveRecord == move and memo.swap == swap then return nil end
  local marked, swapped = swap ~= nil and memo.swap == nil, swap == nil and memo.swap ~= nil
  memo.move, memo.moveRecord, memo.swap = index, move, swap
  local line = moveLine(state, move) or "empty"
  if sameRow and marked then return "marked for swap", true end
  if sameRow and swapped then
    if memo.lastRecord == move then return "swap cancelled", true end
    line = "swapped, " .. line
  end
  memo.lastRecord = move
  if swap ~= nil and swap == index and not sameRow then line = line .. ", marked for swap" end
  if newPhase then line = line .. ", " .. position(index or 0, #moves) end
  return line, true
end

local function choicePart(state, memo, phase)
  local visible = CHOICE_FIELD[phase] and (state.messageTimer or 0) <= 0
  if not visible then
    memo.choice, memo.choicePhase = nil, nil
    return nil
  end
  local index = state[CHOICE_FIELD[phase]]
  local first = memo.choicePhase ~= phase
  if not first and memo.choice == index then return nil end
  memo.choice, memo.choicePhase = index, phase
  local label = CHOICES[index]
  if not label then return nil end
  return label, not first
end

local function forgetPart(state, memo, phase)
  local visible = phase == "choose-forget" and (state.messageTimer or 0) <= 0
  if not visible then
    memo.forget = nil
    return nil
  end
  local index = state.forgetIndex
  if memo.forget ~= nil and memo.forget == index then return nil end
  local first = memo.forget == nil
  memo.forget = index
  local moves = forgetMoves(state)
  local text = forgetRow(state, moves[index])
  if first then text = text .. ", " .. position(index or 0, #moves) end
  return text, not first
end

local function statsPart(state, memo, phase, newPhase)
  if phase ~= "stats-box" or type(state.statsBoxMon) ~= "table" then
    memo.statsMon = nil
    return nil
  end
  if not newPhase and memo.statsMon == state.statsBoxMon then return nil end
  memo.statsMon = state.statsBoxMon
  local text = statsText(state, state.statsBoxMon)
  if not text then return nil end
  return text, false
end

Gen2Battle.presenter = {
  matches = isBattle,
  poll = function(state, memo, entering)
    local phase = state.phase
    -- a return from a screen pushed on top (party, pack) counts as opening
    -- the phase again, so the menu repeats both sides as in Gen 1
    local newPhase = entering or phase ~= memo.phase
    memo.phase = phase

    local parts, interrupt = {}, nil
    local function add(text, wantsInterrupt)
      if not text then return end
      parts[#parts + 1] = text
      -- anything queued in this frame keeps the whole utterance queued
      if interrupt == nil then interrupt = wantsInterrupt else interrupt = interrupt and wantsInterrupt end
    end

    add(messageLine(state, memo), false)
    if phase == "menu" then
      add(menuPart(state, memo, newPhase))
    elseif phase == "moves" then
      add(movesPart(state, memo, newPhase))
    end
    add(choicePart(state, memo, phase))
    add(forgetPart(state, memo, phase))
    add(statsPart(state, memo, phase, newPhase))

    if #parts == 0 then return nil end
    return table.concat(parts, " "), interrupt == true
  end,
}

Gen2Battle.ordered = { Gen2Battle.presenter }

return Gen2Battle
