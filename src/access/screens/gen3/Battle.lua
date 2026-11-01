-- Gen 3 battle speech (FireRed, LeafGreen; decision 29).
--
-- The battle is a module singleton (src/core/game3/battle.lua returns
-- src/core/game3/battle/init.lua), never a stack layer.  gen3/Top.lua
-- reports it as { gen3 = "battle", key = Battle._st, mod = Battle, game }
-- while no stack layer is open, so the memo lives exactly as long as one
-- battle.  Party, bag, summary (forgetting a move), naming, Pokédex and the
-- evolution scene are stack layers above it and belong to their own
-- presenters.  The battle UI is src/core/game3/battle/ui.lua (`Ui._mode`:
-- "menu", "moves", "target", "selmsg", "bag", "party", "none").
--
-- What is spoken, all read without changing anything:
--   messages   every page Message.show puts in the battle box
--              (src/ui/game3/message.lua, frame "battle" or "voiceover"),
--              queued; a new `_pages` table per show, so a line shown twice
--              is said twice.  ALL AT ONCE (decision 26) says every page of
--              a box when it opens.
--   menu       "What will X do?" (drawn by the battle UI, not the box), the
--              selected command; when a turn's menu first opens, or on a
--              return from the party or bag, every side first (your HP
--              exactly, the enemy's level and HP percentage, status tags;
--              shiny, gender and the caught marker the first time each
--              Pokémon is summarised).  Queued; cursor moves interrupt.
--              Safari Zone: "BALL, N left".  The old man's catching demo and
--              the POKé DUDE drive their own menus: only the prompt is said.
--   moves      move, type, "PP n of m", position on opening.  The game
--              draws no disabled marker (selecting gives a message), so
--              none is said.  SELECT swap: the box's "SWITCH WHICH?" with
--              the second cursor's move, then "swapped, ..." or "swap
--              cancelled".
--   target     double battles: the battler under the target cursor.
--   YES / NO   src/ui/game3/choice.lua, after its question (a message).
--   level up   src/ui/game3/stat_growth.lua: page 1 the increases, page 2
--              the totals, six stats with max HP.
-- Gen3Battle.health(state, side) is the on-demand HP read for H and
-- Shift+H, in the Gen 2 words (gen2/Battle.lua).
--
-- Shown values, not resolved ones: the engine applies a move before its
-- lines play, so HP, level, status and who is on the field come from what
-- the healthbox draws (Anim._present[id].displayHp, displayMaxHp,
-- displayLevel, displayStatus, `shown`), read with rawget because
-- Anim.present and Anim.stage create entries.
--
-- Fast GAME SPEED: speech polls once per rendered frame, and at 200X a
-- self-advancing line ("X used Y!", "Go! X!") can be shown and replaced
-- between two polls.  Recorder below is a runtime wrapper on Message.show
-- and Message.close (listed in docs/access/architecture.md): it calls the
-- original unchanged with the same arguments, returns its results, and
-- only notes which page table was shown and how far it got, so the poll
-- can say lines it never saw on screen.  Without it (not installed yet)
-- the poll still reads the open box.

local Common = require("src.access.screens.gen3.Common")
local Gen2Common = require("src.access.screens.gen2.Common")
local Settings = require("src.access.Settings")

local Gen3Battle = {}

local function loaded(path)
  return package.loaded[path]
end

-- Calls a side-effect-free upstream function; nil when it fails.
local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

local function presenters()
  return package.loaded["src.access.screens.Presenters"] or require("src.access.screens.Presenters")
end

-- Joins the parts with ", ", skipping nil and empty ones (holes allowed).
local function join(parts)
  local out = {}
  for i = 1, table.maxn(parts) do
    local part = parts[i]
    if part ~= nil and part ~= "" then out[#out + 1] = part end
  end
  return table.concat(out, ", ")
end

-- A list of cleaned lines as one sentence, split words rejoined.
local function say(lines)
  if #lines == 0 then return "" end
  return Gen2Common.speakable(presenters().joinLines(lines))
end

-- ------------------------------------------------------- message recorder

local KEEP = 64
local Recorder = {
  module = nil,   -- the Message module the wrappers sit on
  seq = 0,        -- number of the newest entry
  entries = {},   -- [seq] = { pages, st, covered, reached }
  -- page tables shown while a stack layer was open (another presenter's)
  covered = setmetatable({}, { __mode = "k" }),
}
local wrappers = setmetatable({}, { __mode = "k" })

local function liveBattle()
  local Battle = loaded("src.core.game3.battle")
  if type(Battle) == "table" and rawget(Battle, "_active") == true then return rawget(Battle, "_st") end
  return nil
end

local function layerOpen()
  local Stack = loaded("src.ui.game3.stack")
  local layers = type(Stack) == "table" and rawget(Stack, "_layers")
  return type(layers) == "table" and #layers > 0
end

-- How far the open table got, noted on its entry just before it is
-- replaced or closed.
local function stamp(Message)
  local entry = Recorder.entries[Recorder.seq]
  if entry and entry.pages == rawget(Message, "_pages") then
    local page = tonumber(rawget(Message, "_page")) or 1
    if page > entry.reached then entry.reached = page end
  end
end

local function note(Message)
  local pages = rawget(Message, "_pages")
  local st = liveBattle()
  if type(pages) ~= "table" or st == nil then return end
  local newest = Recorder.entries[Recorder.seq]
  if newest and newest.pages == pages then return end
  local covered = layerOpen()
  Recorder.seq = Recorder.seq + 1
  Recorder.entries[Recorder.seq] = { pages = pages, st = st, covered = covered,
    reached = tonumber(rawget(Message, "_page")) or 1 }
  Recorder.entries[Recorder.seq - KEEP] = nil
  if covered then Recorder.covered[pages] = true end
end

-- Wraps the loaded Message module once; true when the wrappers are in place.
function Recorder.install()
  local Message = loaded("src.ui.game3.message")
  if Message ~= nil and Recorder.module == Message then return true end
  if type(Message) ~= "table" or type(Message.show) ~= "function"
      or type(Message.close) ~= "function" then
    return false
  end
  Recorder.module = Message
  if not wrappers[Message.show] then
    local show = Message.show
    local function after(...)
      pcall(note, Message)
      return ...
    end
    local wrapper = function(...)
      pcall(stamp, Message)
      return after(show(...))
    end
    wrappers[wrapper] = true
    Message.show = wrapper
  end
  if not wrappers[Message.close] then
    local close = Message.close
    local wrapper = function(...)
      pcall(stamp, Message)
      return close(...)
    end
    wrappers[wrapper] = true
    Message.close = wrapper
  end
  return true
end
Gen3Battle._recorder = Recorder

-- Entries recorded for this battle since the last poll, oldest first.
local function newEntries(memo, st)
  local out = {}
  local from = math.max((memo.seq or 0) + 1, Recorder.seq - KEEP + 1)
  for i = from, Recorder.seq do
    local entry = Recorder.entries[i]
    if entry and entry.st == st and not entry.covered then out[#out + 1] = entry end
  end
  memo.seq = Recorder.seq
  return out
end

local function entryFor(pages)
  for i = Recorder.seq, math.max(1, Recorder.seq - KEEP + 1), -1 do
    local entry = Recorder.entries[i]
    if entry and entry.pages == pages then return entry end
  end
  return nil
end

-- ------------------------------------------------------- messages

-- Pages first..last of a table as one sentence.  A word the cartridge splits
-- across the page break after `last` is finished here and its line skipped
-- when that page comes (as gen3/Dialogue.lua does for field text).
local function pagesText(memo, pages, first, last)
  local lines = {}
  for i = first, last do
    local pageLines = Common.lines(pages[i])
    if memo.skipPages == pages and memo.skipPage == i then table.remove(pageLines, 1) end
    for _, line in ipairs(pageLines) do lines[#lines + 1] = line end
  end
  local nextLines = pages[last + 1] and Common.lines(pages[last + 1]) or nil
  if #lines > 0 and nextLines and nextLines[1] and presenters().splitWord(lines[#lines], nextLines[1]) then
    lines[#lines + 1] = nextLines[1]
    memo.skipPages, memo.skipPage = pages, last + 1
  end
  local text = say(lines)
  if text == "" then return nil end
  return text
end

local function messagePart(state, memo, st)
  local Message = loaded("src.ui.game3.message")
  if type(Message) ~= "table" then return nil end
  memo.spoken = memo.spoken or setmetatable({}, { __mode = "k" })
  local whole = Settings.dialogueWhole(state.game)
  local texts = {}
  local function add(text)
    if text then texts[#texts + 1] = text end
  end

  local current = rawget(Message, "open") == true and rawget(Message, "_pages") or nil
  if type(current) ~= "table" or rawget(Message, "_frame") == "braille" then current = nil end

  -- the table spoken last poll was replaced or closed: its pages the game
  -- reached after that poll (the recorder knows how far it got)
  local tracked = memo.pages
  if tracked and tracked ~= current then
    local entry = entryFor(tracked)
    local reached = math.min(entry and entry.reached or memo.page, #tracked)
    if reached > memo.page then add(pagesText(memo, tracked, memo.page + 1, reached)) end
    memo.pages, memo.page = nil, 0
  end

  -- tables shown and replaced between two polls (fast GAME SPEED)
  for _, entry in ipairs(newEntries(memo, st)) do
    local pages = entry.pages
    if pages ~= current and pages ~= tracked and not memo.spoken[pages] then
      memo.spoken[pages] = true
      local last = whole and #pages or math.min(entry.reached, #pages)
      if last >= 1 then add(pagesText(memo, pages, 1, last)) end
    end
  end

  -- the open box, page by page as the game shows it
  if current and not Recorder.covered[current] then
    if memo.pages ~= current then
      memo.pages, memo.page = current, 0
      memo.spoken[current] = true
    end
    local page = tonumber(rawget(Message, "_page")) or 1
    if whole then page = #current end
    page = math.min(page, #current)
    if page > memo.page then
      add(pagesText(memo, current, memo.page + 1, page))
      memo.page = page
    end
  end

  if #texts == 0 then return nil end
  return table.concat(texts, " ")
end

-- ------------------------------------------------------- the sides

local function battlerAt(st, id)
  if id == 0 then return st.player end
  if id == 1 then return st.enemy end
  return type(st.battlers) == "table" and st.battlers[id] or nil
end

local function absent(st, id)
  return type(st.absent) == "table" and st.absent[id] and true or false
end

local function animModule()
  return loaded("src.core.game3.battle.anim")
end

-- Anim._present[id] without Anim.present, which creates it.
local function present(id)
  local Anim = animModule()
  local list = type(Anim) == "table" and rawget(Anim, "_present")
  if type(list) ~= "table" then return nil end
  local p = rawget(list, id)
  if type(p) == "table" then return p end
  return nil
end

-- Who the healthbox shows in seat `id` (Anim.shownBattler).
local function shownBattler(st, id)
  local p = present(id)
  if p and p.shown then return p.shown end
  return battlerAt(st, id)
end

-- The healthbox's own visible flag (Anim._stage, read without Anim.stage).
local function healthboxUp(id)
  local Anim = animModule()
  local stage = type(Anim) == "table" and rawget(Anim, "_stage")
  local boxes = type(stage) == "table" and stage.healthbox
  local box = type(boxes) == "table" and rawget(boxes, id)
  return type(box) == "table" and box.visible ~= false
end

-- The mod seam battle.status_hud_visible (a query); shown by default.
local function hudVisible(ctx)
  local Ui = ctx.Ui
  if type(Ui) ~= "table" or type(Ui.statusHUDVisible) ~= "function" then return true end
  local ok, visible = pcall(Ui.statusHUDVisible)
  return not ok or visible ~= false
end

local function levelVisible(ctx, mon, side)
  local Runtime = loaded("src.mods.Runtime")
  if not (Runtime and call(Runtime.wantsHook, "pokemon.level_visible")) then return true end
  local LevelDisplay = loaded("src.ui.LevelDisplay")
  if not LevelDisplay then return true end
  local ok, visible = pcall(LevelDisplay.visible, mon, "battle." .. side, ctx.game)
  return not ok or visible ~= false
end

-- HP as the healthbox draws it (Anim.displayHpRatio without its write).
local function shownHp(id, mon)
  local p = present(id)
  local hp, maxHp
  if p and p.displayHp ~= nil then
    hp, maxHp = tonumber(p.displayHp), tonumber(p.displayMaxHp or mon.maxHp)
  else
    hp, maxHp = tonumber(mon.hp), tonumber(mon.maxHp)
  end
  if not hp then return nil end
  maxHp = math.max(1, maxHp or 1)
  return math.max(0, hp), maxHp
end

local function shownLevel(id, mon)
  local p = present(id)
  return tonumber(p and p.displayLevel or mon.level)
end

-- The status icon (Healthbox.shownAilment: 1 PSN, 2 PAR, 3 SLP, 4 FRZ, 5 BRN).
local STATUS_TAGS = { "PSN", "PAR", "SLP", "FRZ", "BRN" }
local STATUS_WORDS = { "poisoned", "paralyzed", "asleep", "frozen", "burned" }
local function ailment(id, battler)
  local Healthbox = loaded("src.core.game3.battle.healthbox")
  local code = Healthbox and call(Healthbox.shownAilment, present(id), battler)
  return tonumber(code) or 0
end

-- The name the healthbox prints; a Pokémon Tower ghost stays "GHOST" (and
-- shows no gender) until the SILPH SCOPE unveils it.
local function nameOf(st, id, battler)
  local State = loaded("src.core.game3.battle.state")
  local name = State and call(State.displayName, battler)
  if type(name) ~= "string" or name == "" then return nil, false end
  local hideGender = false
  if id == 1 and st.ghostBattle and not st.double then
    local RomText = loaded("src.core.game3.rom_text")
    local ghost = RomText and call(RomText.plain, "gText_Ghost")
    if ghost and name == ghost then
      local p = present(1)
      local Pokemon = loaded("src.core.game3.pokemon")
      if p and p.ghostUnveiled and Pokemon then
        name = call(Pokemon.name, battler.species) or name
      else
        hideGender = true
      end
    end
  end
  return Common.speakable(name), hideGender
end

-- The healthbox's gender symbol (mirrors its healthbox_gender: none for
-- genderless, none for NIDORAN♂/♀ still named after the species).
local function genderOf(mon)
  local g = mon.gender
  if g == "U" then return nil end
  local species = tonumber(mon.species or mon.speciesId)
  if g ~= "M" and g ~= "F" then
    local Pokemon = loaded("src.core.game3.pokemon")
    g = species and Pokemon and call(Pokemon.gender, species, mon.personality) or nil
  end
  if g ~= "M" and g ~= "F" then return nil end
  if species == 29 or species == 32 then
    local nick = tostring(mon.nickname or "")
    if nick == "" or nick == tostring(mon.name or "") then return nil end
  end
  return g == "M" and "male" or "female"
end

local function shiny(mon)
  local Pokemon = loaded("src.core.game3.pokemon")
  return Pokemon ~= nil and call(Pokemon.isShiny, mon) == true
end

-- The Poké Ball a wild enemy's healthbox shows for a species already
-- caught: the draw latches it in battler._caughtIcon (singles only, and
-- only while no status icon takes its place).
local function ownedMarker(st, id, battler, code)
  if st.double or id ~= 1 or code ~= 0 or battler.modStatus then return false end
  local latch = rawget(battler, "_caughtIcon")
  return type(latch) == "table" and latch.mon == battler.mon and latch.show == true
end

-- Shiny, gender and the caught marker are said the first time each Pokémon
-- is summarised in a battle, not every turn (as in Gen 2).
local function firstTime(memo, mon)
  memo.introduced = memo.introduced or setmetatable({}, { __mode = "k" })
  if memo.introduced[mon] then return false end
  memo.introduced[mon] = true
  return true
end

local function sideText(ctx, memo, id)
  local st = ctx.st
  if absent(st, id) or not healthboxUp(id) then return nil end
  local battler = shownBattler(st, id)
  local mon = type(battler) == "table" and battler.mon or nil
  if type(mon) ~= "table" then return nil end
  local name, hideGender = nameOf(st, id, battler)
  local hp, maxHp = shownHp(id, mon)
  if not (name and hp) then return nil end
  local first = firstTime(memo, mon)
  local code = ailment(id, battler)
  local status = STATUS_TAGS[code]
  local shinyWord = first and shiny(mon) and "shiny" or nil
  local gender = first and not hideGender and genderOf(mon) or nil
  if id % 2 == 0 then
    return join({ name, shinyWord, gender,
      string.format("HP %d of %d", math.floor(hp), math.floor(maxHp)), status })
  end
  local owned = first and ownedMarker(st, id, battler, code) and "owned" or nil
  local level = levelVisible(ctx, mon, "enemy") and shownLevel(id, mon) or nil
  return join({ "enemy " .. name, shinyWord, owned, level and ("level " .. math.floor(level)) or nil,
    gender, string.format("HP %d percent", math.ceil(100 * hp / maxHp)), status })
end

-- Every side the HUD shows: yours first, then the enemy's (both of each in
-- a double battle).  In the Safari Zone your box shows SAFARI BALLS, not a
-- Pokémon, so only the enemy is said.
local function sides(ctx, memo)
  if not hudVisible(ctx) then return nil end
  local st = ctx.st
  local ids = st.double and { 0, 2, 1, 3 } or { 0, 1 }
  local parts = {}
  for _, id in ipairs(ids) do
    if not (st.safari and id % 2 == 0) then
      local text = sideText(ctx, memo, id)
      if text then parts[#parts + 1] = text end
    end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ". ")
end

-- ------------------------------------------------------- menus

-- The battler choosing now (Ui.activeBattlerObject).
local function activeBattler(ctx)
  local st = ctx.st
  if not st.double then return st.player end
  local id = tonumber(rawget(ctx.Ui, "_active")) or 0
  if id == 0 then return st.player end
  return type(st.battlers) == "table" and st.battlers[id] or nil
end

-- "What will X do?", as action_prompt builds it.  The draw caches its text
-- per battle, mode and Pokémon; when that cache is for another Pokémon (the
-- draw runs after this poll) the same ROM string is built the same way.
local function promptText(ctx, battler)
  local st, Ui = ctx.st, ctx.Ui
  local mode = (st.safari and "safari") or (st.oldManTutorial and "oldman")
    or (type(st.kinds) == "table" and st.kinds.tutorial == "wally" and "wally") or "pkmn"
  local mon = battler and battler.mon
  local cached = rawget(Ui, "_promptFor")
  local text
  if type(cached) == "table" and cached.st == st and cached.mode == mode and cached.mon == mon then
    text = rawget(Ui, "_promptText")
  end
  local BattleText = loaded("src.core.game3.battle.battle_text")
  if type(text) ~= "string" and BattleText then
    if mode == "safari" then
      local Profile = loaded("src.core.game3.battle.profile")
      local profile = Profile and call(Profile.of, st)
      local key = type(profile) == "table" and type(profile.strings) == "table" and profile.strings.safariPrompt
      text = key and call(BattleText.get, key, { playerName = st.playerName }) or nil
    elseif mode == "oldman" then
      text = call(BattleText.get, "gText_WhatWillOldManDo")
    elseif mode == "wally" then
      text = call(BattleText.get, "gText_WhatWillWallyDo")
    elseif battler then
      text = call(BattleText.get, "gText_WhatWillPkmnDo", { active = battler, trainer = not st.wild })
    end
  end
  if type(text) ~= "string" then return nil end
  text = Common.speakable(text)
  if text == "" then return nil end
  return text
end

-- FIGHT / BAG on top, POKéMON / RUN below; Safari BALL / BAIT / ROCK / RUN.
-- The draw caches the ROM labels in Ui._menuLabels; until it has run, the
-- same words as constants (Commands.MENU, SAFARI_MENU).
local FALLBACK_LABELS = {
  gText_BattleMenu = { "FIGHT", "BAG", "{PKMN}", "RUN" },
  gText_SafariZoneMenu = { "BALL", "BAIT", "ROCK", "RUN" },
}
local function menuLabel(ctx, index)
  local st = ctx.st
  local key = st.safari and "gText_SafariZoneMenu" or "gText_BattleMenu"
  local cache = rawget(ctx.Ui, "_menuLabels")
  local labels = type(cache) == "table" and cache[key] or nil
  local label = type(labels) == "table" and labels[index] or nil
  if type(label) ~= "string" then label = FALLBACK_LABELS[key][index] end
  if not label then return nil end
  label = Common.speakable(label)
  if st.safari and index == 1 then
    -- the count is in your healthbox ("Left: N")
    local balls = tonumber(type(st.safariState) == "table" and st.safariState.balls)
    if balls then label = label .. ", " .. math.max(0, math.floor(balls)) .. " left" end
  end
  return label
end

local function menuPart(ctx, memo, entering)
  local st, Ui = ctx.st, ctx.Ui
  if rawget(Ui, "_mode") ~= "menu" or rawget(ctx.Battle, "_phase") ~= "command" then
    memo.menuBattler, memo.menuActive = nil, nil
    return nil
  end
  local battler = activeBattler(ctx)
  local active = tonumber(rawget(Ui, "_active")) or 0
  local index = tonumber(rawget(Ui, "_menuIndex")) or 1
  local opening = entering or memo.menuBattler ~= battler or memo.menuActive ~= active
  if not opening and memo.menuIndex == index then return nil end
  memo.menuBattler, memo.menuActive, memo.menuIndex = battler, active, index
  -- the old man's demo, the POKé DUDE and Wally choose by themselves: only
  -- the prompt, so their scripted cursor stays quiet (Gen 1 and 2 precedent)
  if st.oldManTutorial or st.pokedude or rawget(Ui, "_wally") then
    if not opening then return nil end
    return promptText(ctx, battler), false
  end
  local label = menuLabel(ctx, index)
  if not opening then return label, true end
  local parts = {}
  -- every side once per turn (a double battle's second menu, or a return
  -- after a refused choice, does not repeat it) and on a return from the
  -- party or bag
  if entering or memo.summaryTurn ~= st.turn then
    parts[#parts + 1] = sides(ctx, memo)
    memo.summaryTurn = st.turn
  end
  parts[#parts + 1] = promptText(ctx, battler)
  parts[#parts + 1] = label
  local text = Common.sentences(parts)
  if text == "" then return nil end
  -- queued, so the turn's last self-advancing line is not cut off
  return text, false
end

local function moveCount(mon)
  local n = 0
  for i = 1, 4 do
    local move = type(mon.moves) == "table" and mon.moves[i]
    if move and move ~= 0 and move ~= "" then n = n + 1 end
  end
  return math.max(1, n)
end

local function moveAt(mon, slot)
  local move = type(mon.moves) == "table" and mon.moves[slot] or nil
  if move == nil or move == 0 or move == "" then return nil end
  return move
end

local function moveName(move)
  local Moves = loaded("src.core.game3.battle.moves")
  local name = Moves and call(Moves.displayName, move)
  if type(name) ~= "string" then return nil end
  return Common.speakable(name)
end

local function typeText(ctx, mon, slot, def)
  local Types = loaded("src.core.game3.battle.types")
  if not (def and Types) then return nil end
  local id = call(ctx.Ui.moveTypeOf, mon, slot, def)
  local name = id ~= nil and call(Types.name, id) or nil
  if type(name) ~= "string" then return nil end
  name = Common.speakable(name)
  -- CURSE's type prints "???", which screen readers skip or spell
  if name:match("^%?+$") then return "question marks" end
  return name
end

-- The move box: name, then TYPE and PP as drawn.  PP the game does not
-- hold is left out (the box would print 0).
local function moveLine(ctx, mon, slot)
  local move = moveAt(mon, slot)
  if not move then return "empty" end
  local name = moveName(move)
  if not name then return nil end
  local Moves = loaded("src.core.game3.battle.moves")
  local def = Moves and call(Moves.get, move)
  local pp = type(mon.pp) == "table" and tonumber(mon.pp[slot]) or nil
  local ppText
  if pp then
    local maxPp = type(mon.maxPp) == "table" and tonumber(mon.maxPp[slot])
      or (type(def) == "table" and tonumber(def.pp)) or pp
    ppText = string.format("PP %d of %d", pp, maxPp)
  end
  return join({ name, typeText(ctx, mon, slot, def), ppText })
end

local function switchWhich()
  local RomText = loaded("src.core.game3.rom_text")
  local text = RomText and call(RomText.plain, "gText_BattleSwitchWhich")
  if type(text) ~= "string" then return nil end
  text = Common.speakable(text)
  return text ~= "" and text or nil
end

local function movesPart(ctx, memo)
  local Ui = ctx.Ui
  if rawget(Ui, "_mode") ~= "moves" then
    memo.movesBattler, memo.swapCursor = nil, nil
    return nil
  end
  local battler = activeBattler(ctx)
  local mon = type(battler) == "table" and battler.mon or nil
  if type(mon) ~= "table" then return nil end
  local index = tonumber(rawget(Ui, "_moveIndex")) or 1
  local swap = rawget(Ui, "_swap")
  local swapCursor = type(swap) == "table" and tonumber(swap.cursor) or nil
  local opening = memo.movesBattler ~= battler
  local moveHere = moveAt(mon, index)
  if not opening and memo.moveIndex == index and memo.swapCursor == swapCursor
      and memo.moveHere == moveHere then
    return nil
  end
  local wasSwapping, lastIndex = memo.swapCursor ~= nil, memo.moveIndex
  memo.movesBattler, memo.moveIndex, memo.swapCursor, memo.moveHere = battler, index, swapCursor, moveHere

  if swapCursor ~= nil and not opening then
    -- SELECT: the second cursor moves; the box shows "SWITCH WHICH?"
    local name = moveName(moveAt(mon, swapCursor + 1)) or "empty"
    if not wasSwapping then return Common.sentences({ switchWhich(), name }), true end
    return name, true
  end
  if wasSwapping and not opening then
    if index == lastIndex then return "swap cancelled", true end
    local line = moveLine(ctx, mon, index)
    return line and ("swapped, " .. line) or nil, true
  end
  local line = moveLine(ctx, mon, index)
  if not line then return nil end
  if opening then line = line .. ", " .. Common.position(index, moveCount(mon)) end
  return line, true
end

-- Double battles: the battler under the target cursor, with its HP.
local function targetText(ctx, id)
  local st = ctx.st
  local battler = id and shownBattler(st, id)
  local mon = type(battler) == "table" and battler.mon or nil
  if type(mon) ~= "table" then return nil end
  local name = nameOf(st, id, battler)
  if not name then return nil end
  local hp, maxHp = shownHp(id, mon)
  if id % 2 == 0 then
    return join({ name, hp and string.format("HP %d of %d", math.floor(hp), math.floor(maxHp)) or nil })
  end
  return join({ "enemy " .. name, hp and string.format("HP %d percent", math.ceil(100 * hp / maxHp)) or nil })
end

local function targetPart(ctx, memo)
  local Ui = ctx.Ui
  local target = rawget(Ui, "_target")
  if rawget(Ui, "_mode") ~= "target" or type(target) ~= "table" then
    memo.target, memo.targetCursor = nil, nil
    return nil
  end
  local cursor = tonumber(target.cursor)
  if memo.target == target and memo.targetCursor == cursor then return nil end
  memo.target, memo.targetCursor = target, cursor
  return targetText(ctx, cursor), true
end

-- YES / NO (and the multiple-choice fallback) over the battle box.  The
-- question is a message, spoken first; the selection queues behind it and
-- later moves interrupt.
local function choicePart(memo)
  local Choice = loaded("src.ui.game3.choice")
  if not (type(Choice) == "table" and Choice.active == true and Choice.done ~= nil) then
    memo.choice, memo.choiceCursor = nil, nil
    return nil
  end
  local key, cursor = Choice.done, tonumber(Choice.cursor) or 1
  local first = memo.choice ~= key
  if not first and memo.choiceCursor == cursor then return nil end
  memo.choice, memo.choiceCursor = key, cursor
  local options = type(Choice.options) == "table" and Choice.options or {}
  local option = options[cursor]
  if type(option) == "table" then option = option.label or option.text end
  if type(option) ~= "string" then return nil end
  local text = Common.speakable(option)
  if text == "" then return nil end
  if Choice.kind == "multi" and first then text = text .. ", " .. Common.position(cursor, #options) end
  return text, not first
end

-- The level-up window: page 1 the increases, page 2 the new totals, in the
-- window's order (MAX. HP, ATTACK, DEFENSE, SP. ATK, SP. DEF, SPEED).
local STAT_ROWS = {
  { "max HP", "maxHp" }, { "attack", "atk" }, { "defense", "def" },
  { "special attack", "spa" }, { "special defense", "spd" }, { "speed", "spe" },
}

local function growthText(StatGrowth, page)
  local mon = StatGrowth._mon
  local new, old = StatGrowth._newStats, StatGrowth._oldStats
  if type(mon) ~= "table" or type(new) ~= "table" then return nil end
  local name = mon.nickname
  if type(name) ~= "string" or name == "" then
    local Pokemon = loaded("src.core.game3.pokemon")
    name = Pokemon and call(Pokemon.name, mon.species) or nil
  end
  local values = {}
  for _, row in ipairs(STAT_ROWS) do
    local value = tonumber(new[row[2]])
    if page == 1 then
      local before = type(old) == "table" and tonumber(old[row[2]])
      if value and before then
        local diff = value - before
        values[#values + 1] = string.format("%s %s %d", row[1], diff < 0 and "minus" or "plus", math.abs(diff))
      end
    elseif value then
      values[#values + 1] = row[1] .. " " .. value
    end
  end
  if #values == 0 then return nil end
  local level = tonumber(mon.level)
  local head = join({ name and Common.speakable(name) or nil, level and ("level " .. level) or nil })
  local kind = page == 1 and "stat increases" or "stats"
  head = head ~= "" and (head .. " " .. kind) or kind
  return head .. ": " .. table.concat(values, ", ")
end

local function growthPart(ctx, memo)
  local StatGrowth = loaded("src.ui.game3.stat_growth")
  local open = type(StatGrowth) == "table" and StatGrowth._open == true
    and call(ctx.Battle.statWindowPhase) ~= false
  if not open then
    memo.growth, memo.growthPage = nil, nil
    return nil
  end
  local key, page = StatGrowth._newStats, tonumber(StatGrowth._page) or 1
  if memo.growth == key and memo.growthPage == page then return nil end
  local turned = memo.growth == key
  memo.growth, memo.growthPage = key, page
  -- page 1 queues behind "grew to LV. N!"; turning the page interrupts it
  return growthText(StatGrowth, page), turned
end

-- ------------------------------------------------------- presenter

local function battleModule()
  return loaded("src.core.game3.battle")
end

local function isBattle(state)
  if type(state) ~= "table" or state.gen3 ~= "battle" or type(state.key) ~= "table" then return false end
  local Battle = battleModule()
  return Battle ~= nil and state.mod == Battle
end
Gen3Battle.isBattle = isBattle

local function context(state)
  local Battle, st = state.mod, state.key
  if rawget(Battle, "_st") ~= st then return nil end
  local Ui = loaded("src.core.game3.battle.ui")
  if type(Ui) ~= "table" or rawget(Ui, "_headless") then return nil end
  return { Battle = Battle, st = st, Ui = Ui, game = state.game }
end

Gen3Battle.presenter = {
  matches = function(state)
    if not isBattle(state) then return false end
    Recorder.install()
    return true
  end,
  poll = function(state, memo, entering)
    Recorder.install()
    local ctx = context(state)
    if not ctx then return nil end
    local parts, interrupt = {}, nil
    local function add(text, wantsInterrupt)
      if not text then return end
      parts[#parts + 1] = text
      -- anything queued in this frame keeps the whole utterance queued
      if interrupt == nil then interrupt = wantsInterrupt else interrupt = interrupt and wantsInterrupt end
    end
    add(messagePart(state, memo, ctx.st), false)
    add(menuPart(ctx, memo, entering))
    add(movesPart(ctx, memo))
    add(targetPart(ctx, memo))
    add(choicePart(memo))
    add(growthPart(ctx, memo))
    if #parts == 0 then return nil end
    return table.concat(parts, " "), interrupt == true
  end,
}

-- ------------------------------------------------------- on-demand health

local function safariBalls(st)
  local balls = tonumber(type(st.safariState) == "table" and st.safariState.balls)
  if not balls then return nil end
  local RomText = loaded("src.core.game3.rom_text")
  local label = RomText and call(RomText.plain, "gText_SafariBalls")
  label = type(label) == "string" and Common.speakable(label) or ""
  if label == "" then label = "SAFARI BALLS" end
  return string.format("%s, %d left", label, math.max(0, math.floor(balls)))
end

local function healthOf(ctx, id, withName)
  local st = ctx.st
  if absent(st, id) or not healthboxUp(id) then return nil end
  local battler = shownBattler(st, id)
  local mon = type(battler) == "table" and battler.mon or nil
  if type(mon) ~= "table" then return nil end
  local hp, maxHp = shownHp(id, mon)
  if not hp then return nil end
  local name = nameOf(st, id, battler)
  if id % 2 == 1 then
    local percent = string.format("%.2f percent", hp * 100 / maxHp)
    if withName and name then return name .. " " .. percent end
    return percent
  end
  local text = string.format("%s, %d of %d HP", name or "Pokemon", math.floor(hp), math.floor(maxHp))
  local word = STATUS_WORDS[ailment(id, battler)]
  if word then text = text .. ", " .. word end
  return text
end

-- On-demand health for H (enemy) and Shift+H (player), in the words of
-- Gen2Battle.health and Navigation:readBattleHealth: "Enemy health: 52.17
-- percent", "Player CHARMANDER, 20 of 22 HP, poisoned".  A double battle
-- reads both Pokémon of that side, each named, as Pokémon Access did.
-- `state` is the battle proxy or nil (the live battle).  nil when no Gen 3
-- battle is running; "No bar found" while that side's healthbox is not on
-- screen.  In the Safari Zone your box shows the balls left instead.
function Gen3Battle.health(state, side)
  local Battle = battleModule()
  if not (type(Battle) == "table" and rawget(Battle, "_active") == true) then return nil end
  local st = rawget(Battle, "_st")
  if type(st) ~= "table" then return nil end
  if type(state) == "table" and state.gen3 == "battle" and state.key ~= st then return nil end
  local game = type(state) == "table" and state.game or nil
  if not game then
    local CurrentGame = loaded("src.access.CurrentGame")
    game = CurrentGame and CurrentGame.get() or nil
  end
  local ctx = { Battle = Battle, st = st, Ui = loaded("src.core.game3.battle.ui"), game = game }
  if not hudVisible(ctx) then return "No bar found" end
  local enemy = side == "enemy"
  if not enemy and st.safari then return safariBalls(st) or "No bar found" end
  local ids
  if st.double then ids = enemy and { 1, 3 } or { 0, 2 } else ids = { enemy and 1 or 0 } end
  local parts = {}
  for _, id in ipairs(ids) do
    local text = healthOf(ctx, id, st.double)
    if text then parts[#parts + 1] = text end
  end
  if #parts == 0 then return "No bar found" end
  if enemy then return "Enemy health: " .. table.concat(parts, "; ") end
  return "Player " .. table.concat(parts, "; ")
end

Gen3Battle.ordered = { Gen3Battle.presenter }

return Gen3Battle
