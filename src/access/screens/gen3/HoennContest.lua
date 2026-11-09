-- Contests, Pokéblock, the Berry Blender and the berry tag (Ruby, Sapphire,
-- Emerald).
--
-- Contest stage: src/ui/game3/rse/contest.lua, wrapped by rs/contest.lua; both
-- open through rse/contest.lua's Host, so `UI.active()` serves all three games.
-- The announcer is a printer.  Everything the stage shows beside it (hearts,
-- stars, the crowd meter, the next-turn labels, symbols) is drawn as images
-- from the event list of src/core/game3/rse/contest.lua, so those are said in
-- our words from the same events, as the stage starts each one.
--
-- Only fields and read-only functions are used.  Not called, because they
-- write: UI:func (fills its cache; `s.fn` is read instead), g:sortScores,
-- Pokeblock.contest and Pokeblock.conditions (normalise mon.contest),
-- Pokeblock.get (Pokeblock.slots fills empty rows; session.pokeblocks is read).
--
-- Drawn as images, so said in our words: contest category and rank, hearts,
-- condition stars, status and judge symbols, excitement meter, next-turn
-- labels, final place numbers, the combo and repeat colours of a move, Use
-- Pokéblock's CONDITION title and axes, sheen sparkles, BEST, GOOD and MISS
-- icons in the blender's ranking, and Ruby's and Sapphire's BERRY TAG title
-- and flavour names on the tag.

local Common = require("src.access.screens.gen3.Common")
local H = require("src.access.screens.gen3.HoennCommon")

local Contest = {}

local say, join, sentences, try, position = H.say, H.join, H.sentences, H.try, Common.position

local CONTEST_COUNT = 4
local NUM_APPEALS = 5
local APPLAUSE_SIZE = 5
local MAX_MOVE_HEARTS = 8        -- pokeemerald/include/constants/contest.h:7
local WIN_MOVE0, WIN_MOVE_DESCRIPTION = 5, 10

local CATEGORY_WORDS = { [0] = "COOL", "BEAUTY", "CUTE", "SMART", "TOUGH" }
local RANK_WORDS = { [0] = "NORMAL RANK", "SUPER RANK", "HYPER RANK", "MASTER RANK", "LINK" }
local PLACE_WORDS = { [0] = "1st", "2nd", "3rd", "4th" }

local function stageModule() return H.loaded("src.ui.game3.rse.contest") end
local function coreContest() return H.loaded("src.core.game3.rse.contest") end

-- The running task of a GBA scene.  UI:setFunc stores self.fn[name], so a task
-- is in a phase when its function is that entry.  Never calls UI:func.
local function inTask(s, taskId, ...)
  local task = taskId and s.m and s.m.tasks and s.m.tasks.t and s.m.tasks.t[taskId]
  if not (task and s.fn) then return false end
  for _, name in ipairs({ ... }) do
    if s.fn[name] ~= nil and task.func == s.fn[name] then return true end
  end
  return false
end

local function plural(n, word)
  local count = n < 0 and ("minus " .. tostring(-n)) or tostring(n)
  if n == 1 or n == -1 then return count .. " " .. word end
  return count .. " " .. word .. "s"
end

local function monWord(s, i)
  return say(try(s.monName, s, i))
end

-- pokeemerald/src/contest.c:3699 heartsFromAppeal
local function appealHearts(appeal)
  appeal = tonumber(appeal) or 0
  local q = appeal / 10
  local hearts = q >= 0 and math.floor(q) or -math.floor(-q)
  return math.max(-16, math.min(16, hearts))
end

-- pokeemerald/src/contest.c:3856 updateHeartSlider: the slider sits at the
-- round total over ten, never below zero, two pixels a heart up to 56.
local function sliderHearts(total)
  local q = (tonumber(total) or 0) / 10
  local hearts = q >= 0 and math.floor(q) or -math.floor(-q)
  return math.max(0, math.min(28, hearts))
end

-- pokeemerald/src/contest.c:3343 drawStatusSymbol
local function statusWord(st)
  if st.resistant ~= 0 or st.immune ~= 0 or st.jamSafetyCount ~= 0 or st.jamReduction ~= 0 then return "protected" end
  if st.nervous ~= 0 then return "nervous" end
  if st.numTurnsSkipped ~= 0 or st.noMoreTurns ~= 0 then return "cannot appeal" end
  return nil
end

local function starsWord(condition)
  return plural(math.floor((tonumber(condition) or 0) / 10), "star")
end

-- Contestants in appeal order, the order of the boxes on the stage.
local function inAppealOrder(c)
  local list = {}
  for i = 0, CONTEST_COUNT - 1 do list[#list + 1] = i end
  table.sort(list, function(a, b) return (c.turnOrder[a] or 0) < (c.turnOrder[b] or 0) end)
  return list
end

local function roundOrder(s, c)
  local rows = {}
  for at, i in ipairs(inAppealOrder(c)) do
    local st = c.status[i]
    rows[#rows + 1] = join({ tostring(at), monWord(s, i), say(try(s.trainerName, s, i)),
      i == c.playerIndex and "you" or nil, plural(sliderHearts(st.pointTotal), "heart"),
      starsWord(st.condition), statusWord(st), st.hasJudgesAttention ~= 0 and "judge's attention" or nil }, ", ")
  end
  return "Appeal order: " .. table.concat(rows, "; ")
end

local function excitementWord(level)
  level = tonumber(level) or 0
  return join({ "Excitement", tostring(math.max(0, math.min(APPLAUSE_SIZE, level))), "of", tostring(APPLAUSE_SIZE) }, " ")
end

local function moveLine(s, c)
  local choice = c.contest.playerMoveChoice
  local me = c.playerIndex
  local move = c.mons[me].moves[choice] or 0
  local count = 0
  for i = 0, 3 do if (c.mons[me].moves[i] or 0) ~= 0 then count = count + 1 end end
  -- pokeemerald/src/contest.c:3194 printContestMoveDescription
  local cm = c.data.moves[move] or {}
  local eff = c.data.effects[cm.effect or 0] or {}
  local function hearts(value)
    value = tonumber(value) or 0
    if value == 0xFF then return 0 end
    return math.min(MAX_MOVE_HEARTS, math.floor(value / 10))
  end
  local win = s.win[WIN_MOVE0 + choice]
  local mark
  -- pokeemerald/src/contest.c:1517: the move's name is coloured for these.
  if win and win.colorKey == "combo" then mark = "combo"
  elseif win and win.colorKey == "repeat" then mark = "repeated" end
  local description = s.win[WIN_MOVE_DESCRIPTION]
  return sentences({
    join({ say(win and win.text), CATEGORY_WORDS[cm.category or 0], mark, position(choice + 1, count) }),
    join({ "appeal " .. plural(hearts(eff.appeal), "heart"), "jam " .. plural(hearts(eff.jam), "heart") }),
    description and say(description.text) or nil,
  })
end

-- One event of the running turn in words, or nil for an event the printer or
-- nothing says.  `s.turn.events` is the list playTurn walks.
local function eventWords(s, c, ev, memo)
  local kind = ev.kind
  if kind == "hearts" then
    local before, after = appealHearts(ev.from), appealHearts((tonumber(ev.from) or 0) + (tonumber(ev.delta) or 0))
    local own = s.turn and ev.contestant == s.turn.contestant
    if after == before and not (own and (ev.from or 0) == 0) then return nil end
    return join({ monWord(s, ev.contestant), plural(after, "heart") })
  elseif kind == "stars" then
    return join({ monWord(s, ev.contestant), starsWord(ev.condition) })
  elseif kind == "crowd" then
    if (ev.level or 0) >= APPLAUSE_SIZE then return excitementWord(APPLAUSE_SIZE) .. ", maximum" end
    return excitementWord(ev.level)
  elseif kind == "applause" then
    return "Excitement reset to 0"
  elseif kind == "status" then
    local st = c.status[ev.contestant]
    local word = st and statusWord(st)
    memo.statusWords = memo.statusWords or {}
    if word == memo.statusWords[ev.contestant] then return nil end
    memo.statusWords[ev.contestant] = word
    return word and join({ monWord(s, ev.contestant), word }) or nil
  elseif kind == "nextTurnGfx" then
    -- pokeemerald/src/contest.c:5012 showHideNextTurnGfx
    local rows = {}
    memo.nextTurn = memo.nextTurn or {}
    for i = 0, CONTEST_COUNT - 1 do
      local st = c.status[i]
      local value
      if st.turnOrderMod ~= 0 then value = st.turnOrderMod == 1 and PLACE_WORDS[st.nextTurnOrder] or "at random" end
      if value and memo.nextTurn[i] ~= value then
        rows[#rows + 1] = join({ monWord(s, i), value })
      end
      memo.nextTurn[i] = value
    end
    if #rows == 0 then return nil end
    return "Next turn: " .. table.concat(rows, "; ")
  end
  return nil
end

local function roundTotals(s, c)
  local rows = {}
  for _, i in ipairs(inAppealOrder(c)) do
    rows[#rows + 1] = join({ monWord(s, i), plural(sliderHearts(c.status[i].pointTotal), "heart") })
  end
  return "Totals: " .. table.concat(rows, "; ")
end

local function pushPrinter(parts, s, memo, game)
  local text = s.printer and H.printerSay(s.printer, memo, game) or nil
  if text then parts[#parts + 1] = text end
end

-- Announcer lines and events never interrupt each other, or a turn would be
-- cut short; the move list does interrupt whatever is left of them.
Contest.stage = {
  matches = Common.matcher("rse_contest"),
  poll = function(state, memo)
    local Stage = stageModule()
    local s = Stage and try(Stage.active)
    if type(s) ~= "table" or type(s.c) ~= "table" then return nil end
    local c = s.c
    if not s.mainTaskId then return nil end
    local game = state.game
    local parts = {}
    if not memo.opened then
      memo.opened = true
      parts[#parts + 1] = join({ RANK_WORDS[c.rank], CATEGORY_WORDS[c.category], "CONTEST" }, " ")
    end
    if inTask(s, s.mainTaskId, "taskHandleMoveSelectInput") and s.win[WIN_MOVE0] then
      local fresh = not memo.moves
      local choice = c.contest.playerMoveChoice
      if fresh or choice ~= memo.choice then
        memo.moves, memo.choice = true, choice
        local line = moveLine(s, c)
        return sentences({ fresh and "Moves" or nil, line }), true
      end
      return nil
    end
    memo.moves = nil
    local t = s.turn
    if t and type(t.events) == "table" then
      if memo.turn ~= t then memo.turn, memo.seen = t, 0 end
      local upto = (t.i or 1) - 1
      for k = memo.seen + 1, upto do
        local ev = t.events[k]
        if ev and (ev.kind == "text" or ev.kind == "result") then
          pushPrinter(parts, s, memo, game)
        elseif ev then
          local words = eventWords(s, c, ev, memo)
          if words then parts[#parts + 1] = words end
        end
      end
      memo.seen = math.max(memo.seen, upto)
    end
    pushPrinter(parts, s, memo, game)
    if not t then
      local appeal = c.contest.appealNumber
      if appeal < NUM_APPEALS and appeal ~= memo.round
          and inTask(s, s.mainTaskId, "taskDisplayAppealNumberText", "taskTryShowMoveSelectScreen") then
        memo.round = appeal
        parts[#parts + 1] = "Round " .. (appeal + 1) .. " of " .. NUM_APPEALS
        parts[#parts + 1] = roundOrder(s, c)
      elseif memo.totals ~= appeal
          and inTask(s, s.mainTaskId, "taskReUpdateHeartSliders") then
        memo.totals = appeal
        parts[#parts + 1] = roundTotals(s, c)
      end
    end
    local text = sentences(parts)
    if not text then return nil end
    return text, false
  end,
}

-- ------------------------------------------------------------------ results

local function resultsRows(s, field)
  local Util = H.loaded("src.core.game3.rse.contest_util")
  local rows = {}
  for i = 0, CONTEST_COUNT - 1 do
    local r = s.results and s.results[i]
    local names = s.names and s.names[i]
    local who = names and say(names.nick)
    if r then rows[#rows + 1] = join({ who, field(r, i) }) end
  end
  return table.concat(rows, "; "), Util
end

Contest.results = {
  matches = Common.matcher("rse_contest_results"),
  poll = function(state, memo)
    local Results = H.loaded("src.ui.game3.rse.contest_results")
    local s = Results and try(Results.active)
    if type(s) ~= "table" or type(s.c) ~= "table" then return nil end
    local c = s.c
    local d = s.d
    local parts = {}
    if not memo.opened then
      memo.opened = true
      parts[#parts + 1] = join({ RANK_WORDS[c.rank], CATEGORY_WORDS[c.category], "CONTEST" }, " ")
    end
    for _, id in ipairs({ d.slidingTextBoxSpriteId, d.linkTextBoxSpriteId }) do
      local box = id and s.boxTexts and s.boxTexts[id]
      if box and box.text ~= memo[id] then
        memo[id] = box.text
        parts[#parts + 1] = say(box.text)
      end
    end
    local task = d.showResultsTaskId
    if not memo.prelim and inTask(s, task, "taskShowPreliminaryResults") then
      memo.prelim = true
      -- pokeemerald/src/contest_util.c:1770: stars, then a bar; the bar follows them.
      parts[#parts + 1] = (resultsRows(s, function(r) return plural(r.numStars, "star") end))
    end
    if not memo.round2 and inTask(s, task, "taskShowRound2Results") then
      memo.round2 = true
      parts[#parts + 1] = (resultsRows(s, function(r)
        return plural(r.lostPoints and -r.numHearts or r.numHearts, "heart")
      end))
    end
    if not memo.places and (d.numStandingsPrinted or 0) >= CONTEST_COUNT then
      memo.places = true
      local rows = {}
      for place = 0, CONTEST_COUNT - 1 do
        for i = 0, CONTEST_COUNT - 1 do
          if c.standings[i] == place then
            rows[#rows + 1] = join({ PLACE_WORDS[place], say(s.names[i].nick) })
          end
        end
      end
      parts[#parts + 1] = table.concat(rows, "; ")
    end
    -- pokeemerald/src/contest_util.c:978: nothing on screen says the scene waits.
    if not memo.waiting and inTask(s, task, "taskSetSeenWinnerMon") then
      memo.waiting = true
      parts[#parts + 1] = "Press A"
    end
    local text = sentences(parts)
    if not text then return nil end
    return text, false
  end,
}

-- ----------------------------------------------------------------- painting

Contest.painting = {
  matches = Common.matcher("rse_contest_painting"),
  poll = function(_, memo)
    local Painting = H.loaded("src.ui.game3.rse.contest_painting")
    local st = Painting and Painting._st and try(Painting._st)
    if type(st) ~= "table" or memo.said then return nil end
    memo.said = true
    -- The artist's copy has no caption (contest_painting.c:281): only the name.
    local winner = st.winner
    local Util = H.loaded("src.core.game3.rse.contest_util")
    local name = winner and Util and say(try(Util.decode, winner.monName)) or nil
    if winner and type(winner.monName) == "string" then name = say(winner.monName) end
    local text = sentences({ "Painting", say(st.caption) or name })
    if not text then return nil end
    return text, true
  end,
}

-- ------------------------------------------------------------- contest party

-- Ruby and Sapphire choose through FireRed's party screen under this host
-- (rse/contest_party.lua), which leaves ABLE and NOT ABLE on each row.
Contest.party = {
  matches = Common.matcher("rs_contest_party"),
  poll = function(state, memo, entering)
    local Items = H.loaded("src.access.screens.gen3.Items")
    local Party = H.loaded("src.ui.game3.party_menu")
    local Screens = H.loaded("src.ui.game3.screens")
    if not (Items and Party and Party.open and Screens) then return nil end
    local inner = { mod = Party, game = state.game, gen3 = "party" }
    return Screens.withTextAliases(nil, Items.partyPoll, inner, memo, entering)
  end,
}

-- ---------------------------------------------------------------- Pokéblock

local FLAVOR_KEYS = {
  { "gText_Spicy", "gContestStatsText_Spicy" }, { "gText_Dry", "gContestStatsText_Dry" },
  { "gText_Sweet", "gContestStatsText_Sweet" }, { "gText_Bitter", "gContestStatsText_Bitter" },
  { "gText_Sour", "gContestStatsText_Sour" },
}
local FLAVOR_FIELDS = { "spicy", "dry", "sweet", "bitter", "sour" }

local function yesNoRow(yn)
  if type(yn) ~= "table" then return nil end
  return join({ H.yesNo((yn.cursor or 0) + 1), position((yn.cursor or 0) + 1, 2) })
end

local function caseRow(st, Case, Pokeblock)
  local id = Case.saved.scroll + Case.saved.row
  local at = position(id + 1, st.itemsNo)
  if id >= st.itemsNo - 1 then
    local stow = H.first({ "gText_StowCase", "gContestStatsText_StowCase" })
    return join({ stow and (stow:gsub("%.%s*$", "")) or nil, at })
  end
  local block = st.session and st.session.pokeblocks and st.session.pokeblocks[id + 1]
  if type(block) ~= "table" then return nil end
  -- pokeemerald/src/pokeblock.c:762 drawInfo: a circle for each flavour above 0.
  local flavors = {}
  for i, field in ipairs(FLAVOR_FIELDS) do
    if (tonumber(block[field]) or 0) > 0 then flavors[#flavors + 1] = H.first(FLAVOR_KEYS[i]) or field end
  end
  return sentences({
    join({ say(Pokeblock.name(block)), "level " .. tostring(Pokeblock.highestFlavorLevel(block)), at }),
    #flavors > 0 and table.concat(flavors, ", ") or nil,
    "feel " .. tostring(Pokeblock.feel(block)),
  })
end

Contest.pokeblockCase = {
  matches = Common.matcher("rse_pokeblock_case"),
  poll = function(state, memo)
    local Case = H.loaded("src.ui.game3.rse.pokeblock_case")
    local Pokeblock = H.loaded("src.core.game3.rse.pokeblock")
    local st = Case and Case._st
    if not (st and Pokeblock and Case.open) then return nil end
    local phase = st.phase
    local text
    if phase == "list" or phase == "swap" then
      local id = Case.saved.scroll + Case.saved.row
      if not memo.opened or id ~= memo.id or memo.phase ~= phase then
        local title = not memo.opened and "POKéBLOCK CASE" or nil
        local swapping = phase == "swap" and memo.phase ~= "swap" and "Moving" or nil
        text = sentences({ title, swapping, caseRow(st, Case, Pokeblock) })
      end
      memo.opened, memo.id = true, id
    elseif phase == "actions" then
      local list = (st.opts and st.opts.actions) or Case.ACTIONS
      list = list[st.caseId] or list[Pokeblock.CASE.FIELD]
      local row = list and list[(st.actionCursor or 0) + 1]
      if row and (memo.phase ~= phase or memo.action ~= st.actionCursor) then
        text = join({ say(H.rom(row.text)), position(st.actionCursor + 1, #list) })
      end
      memo.action = st.actionCursor
    elseif phase == "toss" or phase == "tossed" then
      text = H.printerSay(st.printer, memo, state.game)
    elseif phase == "toss_yesno" then
      local cursor = st.yesNo and st.yesNo.cursor
      if cursor and cursor ~= memo.tossCursor then
        text = yesNoRow(st.yesNo)
        -- the first row must not cut off the question just printed
        if memo.tossCursor == nil then
          memo.tossCursor = cursor
          memo.phase = phase
          return text, false
        end
      end
      memo.tossCursor = cursor
    end
    if phase ~= "toss_yesno" then memo.tossCursor = nil end
    memo.phase = phase
    if not text then return nil end
    return text, true
  end,
}

-- The axes of the condition graph, as `Pokeblock.CONDITIONS` keys.
local CONDITION_ROWS = { { "cool", "COOL" }, { "beauty", "BEAUTY" }, { "cute", "CUTE" }, { "smart", "SMART" }, { "tough", "TOUGH" } }

local function conditionNumbers(mon)
  local stats = type(mon) == "table" and type(mon.contest) == "table" and mon.contest or {}
  local rows = {}
  for _, row in ipairs(CONDITION_ROWS) do
    rows[#rows + 1] = row[2] .. " " .. math.floor(tonumber(stats[row[1]]) or 0)
  end
  rows[#rows + 1] = "sheen " .. math.floor(tonumber(stats.sheen) or 0)
  return table.concat(rows, ", ")
end

local function useMon(st)
  local index = st.party and st.party[st.sel + 1]
  return index and st.session.party[index] or nil
end

local function useRow(st)
  local count = st.numSelections or 0
  local at = position(st.sel + 1, count)
  if st.sel == count - 1 then
    return join({ H.first({ "gText_Cancel2", "gOtherText_CancelNoTerminator" }) or "CANCEL", at })
  end
  local info = st.nameInfo or {}
  local gender = info.gender == "M" and "male" or info.gender == "F" and "female" or nil
  -- use_pokeblock.lua nameLine: gText_LvVar1 or Ruby's "{LV}<n>".
  local nature = say(st.natureText)
  return sentences({ join({ say(info.name), gender, say(info.level), at }), nature and (nature:gsub("%s*/%s*", " ")) or nil,
    conditionNumbers(useMon(st)) })
end

Contest.usePokeblock = {
  matches = Common.matcher("rse_use_pokeblock"),
  poll = function(_, memo)
    local Use = H.loaded("src.ui.game3.rse.use_pokeblock")
    local st = Use and Use._st
    if not (st and Use.open) then return nil end
    local state = st.state
    local text
    if state == "input" then
      if memo.state ~= "input" or st.sel ~= memo.sel then
        text = sentences({ not memo.opened and "CONDITION" or nil, useRow(st) })
        memo.opened = true
      end
      memo.sel = st.sel
    elseif state == "confirm" then
      local cursor = st.yesNo and st.yesNo.cursor
      if memo.state ~= "confirm" then
        text = sentences({ say(st.message), yesNoRow(st.yesNo) })
      elseif cursor ~= memo.cursor then
        text = yesNoRow(st.yesNo)
      end
      memo.cursor = cursor
    elseif state == "wont_eat" then
      if memo.state ~= state then text = say(st.message) end
    elseif state == "results_wait" then
      if memo.state ~= state then
        text = sentences({ not memo.opened and "CONDITION" or nil, useRow(st), "Press A" })
        memo.opened = true
      end
    elseif state == "results_text" then
      if st.message ~= memo.message then
        local first = memo.message == nil
        text = sentences({ say(st.message), first and conditionNumbers(useMon(st)) or nil })
        memo.message = st.message
      end
    end
    memo.state = state
    if not text then return nil end
    return text, true
  end,
}

Contest.pokeblockFeed = {
  matches = Common.matcher("rse_pokeblock_feed"),
  poll = function(state, memo)
    local Feed = H.loaded("src.ui.game3.rse.pokeblock_feed")
    local st = Feed and Feed._st
    if not (st and Feed.open and st.printer) then return nil end
    local text = H.printerSay(st.printer, memo, state.game)
    if not text then return nil end
    return text, true
  end,
}

-- ------------------------------------------------------------ Berry Blender

-- A window's prints as rows on the screen: by height, then left to right.
local function windowRows(win)
  local byRow, order = {}, {}
  for _, p in ipairs(win.prints or {}) do
    local key = tonumber(p.y) or 0
    if not byRow[key] then byRow[key] = {}; order[#order + 1] = key end
    table.insert(byRow[key], p)
  end
  table.sort(order)
  local rows = {}
  for _, key in ipairs(order) do
    local row = byRow[key]
    table.sort(row, function(a, b) return (a.x or 0) < (b.x or 0) end)
    local cells = {}
    for i, p in ipairs(row) do
      -- Ruby's place reads "1 . NAME".
      cells[i] = (tostring(p.text):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^(%d+) %. ", "%1. "))
    end
    rows[#rows + 1] = cells
  end
  return rows
end

local function joinedCell(cells, from)
  local out = {}
  for i = from, #cells do out[#out + 1] = cells[i] end
  return table.concat(out, " ")
end

-- pokeemerald/src/berry_blender.c:3665 printRanking: name, then the counts
-- under the BEST, GOOD and MISS icons.
local function rankingText(win)
  local parts = {}
  for _, cells in ipairs(windowRows(win)) do
    if #cells >= 4 then
      parts[#parts + 1] = join({ say(cells[1]), "BEST " .. say(cells[2]), "GOOD " .. say(cells[3]), "MISS " .. say(cells[4]) })
    else
      parts[#parts + 1] = say(joinedCell(cells, 1))
    end
  end
  return sentences(parts)
end

-- pokeemerald/src/berry_blender.c:3455 printResults: place and berry, then
-- maximum speed and time.  Ruby prints the speed's dot and the time's parts
-- as separate strings; they are joined back as they read.
local function resultsText(win)
  local parts = {}
  for _, cells in ipairs(windowRows(win)) do
    -- "Time:" keeps no colon before its value.
    local label = cells[1] and (cells[1]:gsub(":%s*$", "")) or nil
    if #cells <= 1 then
      parts[#parts + 1] = say(label)
    elseif #cells == 2 then
      parts[#parts + 1] = join({ say(label), say(cells[2]) })
    else
      -- Ruby: "92", ".", "88RPM" and "00MIN.", "30SEC."
      local value = joinedCell(cells, 2):gsub("%s+%.%s+", "."):gsub("(%d)(%a)", "%1 %2")
      parts[#parts + 1] = join({ say(label), say(value) })
    end
  end
  return sentences(parts)
end

local function blenderScreen(state)
  local path = state.gen3 == "rs_berry_blender" and "src.ui.game3.rs.berry_blender" or "src.ui.game3.rse.berry_blender"
  local mod = H.loaded(path)
  return mod and try(mod.active)
end

local function blenderPlayers(s)
  local g = s.game
  if not (g and g.numPlayers and g.blendedBerries) then return nil end
  local rows = {}
  for pid = 0, g.numPlayers - 1 do
    local berry = g.blendedBerries[pid]
    rows[#rows + 1] = join({ say(g.playerNames[pid]), berry and say(berry.name) and (say(berry.name) .. " BERRY") or nil })
  end
  return table.concat(rows, "; ")
end

-- Ruby's yes/no keeps its cursor in a closure (rs/berry_blender.lua nativeYesNo).
local function blenderYesNoCursor(yn)
  if type(yn) ~= "table" then return nil end
  if yn.cursor then return yn.cursor end
  local draw = rawget(yn, "draw")
  if type(draw) ~= "function" then return nil end
  for i = 1, 16 do
    local name, value = debug.getupvalue(draw, i)
    if not name then return nil end
    if name == "select" then return value end
  end
  return nil
end

-- The timing game has no text: its arrow, BEST, GOOD and MISS sprites and
-- changing speed digits are real time, and a cue spoken for them would arrive
-- after the moment.  Instead a short tone (earcon "blender") plays a fixed time
-- before the arrow reaches the middle of the player's BEST range, so a press on
-- the tone lands there (owner request, 2026-11-09).  The range and the arrow are
-- the game's own (core/game3/rse/berry_blender.lua arrowProximity: BEST while
-- arrowPos / 256 is within 4 of the player's arrowHitRangeStart, so its middle
-- is arrowPos = start * 256).  What the game shows is said when play has ended.
-- Measured in Emerald, playing by ear only (drivers/rse_screens_contest.lua
-- BLENDER_BY_TONE, 2026-11-09): a press as many frames after the tone as its lead
-- lands mostly GOOD with some BEST and no MISS; four frames either way starts to miss.
-- 14 frames (about a quarter second) is near a player's reaction to an expected
-- sound, and a player can learn the beat from there.  Not tried by a person yet.
Contest.BLENDER_LEAD_FRAMES = 14

local function blenderCue(g, memo)
  local speed = g and tonumber(g.speed) or 0
  local playing = g and g.gameEndState == 0 and speed > 0 and type(g.playerIdToArrowId) == "table"
    and type(g.T) == "table" and type(g.T.arrowHitRangeStart) == "table"
  if not playing then memo.blenderCued = nil return end
  local arrowId = g.playerIdToArrowId[g.localPlayerId or 0]
  local start = arrowId and tonumber(g.T.arrowHitRangeStart[arrowId + 1])
  if not start then return end
  local ahead = (start * 256 - (tonumber(g.arrowPos) or 0)) % 0x10000
  local frames = ahead / speed
  if frames <= Contest.BLENDER_LEAD_FRAMES then
    if not memo.blenderCued then
      memo.blenderCued = true
      local Nav = package.loaded["src.access.nav"]
      local nav = Nav and Nav.coordinator and Nav.coordinator()
      if nav and nav.cue then pcall(nav.cue, nav, "blender") end
    end
  elseif ahead > 0x8000 then
    -- the arrow has passed the range: the next lap gets its own tone
    memo.blenderCued = nil
  end
end
Contest.blenderCue = blenderCue

Contest.blender = {
  matches = function(state)
    return type(state) == "table" and (state.gen3 == "rse_berry_blender" or state.gen3 == "rs_berry_blender")
  end,
  poll = function(state, memo)
    local s = blenderScreen(state)
    if type(s) ~= "table" or s.hidden or s.done then return nil end
    local parts = {}
    local g = s.game
    if s.cb == "play" then blenderCue(g, memo) end
    if s.printer then
      local text = H.printerSay(s.printer, memo, state.game)
      if text then parts[#parts + 1] = text end
    end
    if g and s.cb == "startLocal" and (s.state or 0) >= 11 and memo.players ~= g then
      memo.players = g
      parts[#parts + 1] = blenderPlayers(s)
    end
    local win = s.wins and s.wins[5]
    if g and win and win.shown and s.cb == "end" then
      if g.gameEndState == 5 and (s.rankState or 0) >= 4 and memo.ranking ~= g then
        memo.ranking = g
        parts[#parts + 1] = rankingText(win)
      elseif g.gameEndState == 6 and (s.resState or 0) >= 4 and memo.results ~= g then
        memo.results = g
        parts[#parts + 1] = resultsText(win)
      end
    end
    local cursor = blenderYesNoCursor(s.yesNo)
    -- the first row must not cut off the question just printed
    local queued = false
    if cursor and cursor ~= memo.cursor then
      queued = memo.cursor == nil
      parts[#parts + 1] = join({ H.yesNo(cursor + 1), position(cursor + 1, 2) })
    end
    memo.cursor = cursor
    local text = sentences(parts)
    if not text then return nil end
    return text, not queued
  end,
}

-- ----------------------------------------------------------------- berry tag

local function flavorWords(circles)
  local names = {}
  for i = 1, 5 do
    if circles and circles[i] then names[#names + 1] = H.first(FLAVOR_KEYS[i]) or FLAVOR_FIELDS[i] end
  end
  if #names == 0 then return nil end
  return table.concat(names, ", ")
end

local function tagAt(st)
  if type(st.list) ~= "table" then return nil end
  return position(st.pos + 1, #st.list)
end

-- "SIZE /" and "FIRM /" with their value; the size's inch mark in a word.
local function tagField(label, value)
  label = label and (label:gsub("%s*/%s*$", "")) or nil
  value = value and (value:gsub("\226\128\157", " inches"):gsub('"', " inches")) or nil
  return join({ label, value }, " ")
end

local function tagLines(st, opened)
  local text = st.text or {}
  local isRuby = st.man ~= nil
  local title = opened and (isRuby and "BERRY TAG" or say(H.rom("gText_BerryTag")) or "BERRY TAG") or nil
  local name
  if isRuby then name = join({ text.number, say(text.name) }, " ") else name = say(text.name) end
  local sizeLabel = isRuby and say(st.man.strings.size) or say(H.rom("gText_SizeSlash"))
  local firmLabel = isRuby and say(st.man.strings.firm) or say(H.rom("gText_FirmSlash"))
  local one = isRuby and say(text.description1) or say(text.desc1)
  local two = isRuby and say(text.description2) or say(text.desc2)
  local circles = isRuby and st.sprite and st.sprite.circles or st.circles
  return sentences({ title, join({ name, tagAt(st) }),
    tagField(sizeLabel, say(text.size)), tagField(firmLabel, say(text.firm)),
    flavorWords(circles), join({ one, two }, " ") })
end

local function tagPoll(path)
  return function(_, memo)
    local Tag = H.loaded(path)
    local st = Tag and Tag._st
    if not (st and Tag.open and st.phase == "input") then return nil end
    if memo.berry == st.berryId then return nil end
    local opened = memo.berry == nil
    memo.berry = st.berryId
    local text = tagLines(st, opened)
    if not text then return nil end
    return text, true
  end
end

Contest.berryTag = { matches = Common.matcher("rse_berry_tag"), poll = tagPoll("src.ui.game3.rse.berry_tag") }
Contest.rsBerryTag = { matches = Common.matcher("rs_berry_tag"), poll = tagPoll("src.ui.game3.rs.berry_tag") }

Contest.ordered = {
  Contest.stage, Contest.results, Contest.painting, Contest.party,
  Contest.pokeblockCase, Contest.usePokeblock, Contest.pokeblockFeed,
  Contest.blender, Contest.berryTag, Contest.rsBerryTag,
}

return Contest
