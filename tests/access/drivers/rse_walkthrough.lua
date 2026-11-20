-- Ruby, Sapphire and Emerald played forward from the title screen, the way a blind
-- player has to: real button presses, the game's own menus and prompts, movement by
-- the object list and auto-walk through the bound commands (the controller's: hold the
-- left trigger, D-pad up and down for the category, left and right for the item, left
-- stick click to walk), battles through the battle menu.  No teleports, no flag or
-- variable writes, no gifted party, no healing by the harness: a weak party walks to a
-- Pokémon Center.  Every utterance is logged with the screen it came from.
--
-- Stages, each with a goal check read from the game's flags and variables: boot, truck,
-- house, rival_house, starter, rival_battle, pokedex, shoes, petalburg, catching_lesson,
-- woods, rustboro, roxanne, devon_goods, pokenav, dewford.  Written for Emerald; Ruby and
-- Sapphire name some of these variables differently.
--
--   FRESH=1                 start from clean game data (the runner's switch)
--   WALK_STOP=<stage>       stop after this stage
--   WALK_SPEED=<n>          AUTO-WALK SPEED (the game's own accessibility option); the
--                           default is the option's default
--   WALK_NAME=<letters>     the name typed on the naming screen (default ACE)
--   WALK_STARTER=<name>     TREECKO, TORCHIC or MUDKIP (default MUDKIP)
--   WALK_CONTINUE=1         CONTINUE from the save instead of NEW GAME; stages already
--                           done in it are skipped
--
-- Lines: SAID (speech, with the screen), SCREEN (what is on top), STAGE (a stage's
-- start and result), FINDING (something a blind player would trip on), CHEAT (the
-- harness did something a player cannot; none is expected).  Silent; nobody hears it.
return function(game)
  local L = dofile("tests/access/drivers/rse_nav_lib.lua").new(game)
  local U, AutoWalk = L.U, L.AutoWalk
  local Speech = require("src.access.Speech")
  local Top = require("src.access.screens.gen3.Top")
  local GameData = L.GameData
  local Nav = package.loaded["src.access.nav"] or require("src.access.nav")
  local BoulderWalk = require("src.access.nav.BoulderWalk")
  local SwitchWalk = require("src.access.nav.SwitchWalk")
  local IceWalk = require("src.access.nav.IceWalk")
  local Chase = require("src.access.nav.Chase")

  local frame = 0
  local findings, findingCount = {}, 0
  local function finding(kind, text)
    local key = kind .. "|" .. text
    findings[key] = (findings[key] or 0) + 1
    if findings[key] > 2 then return end
    findingCount = findingCount + 1
    U.log("FINDING", kind, text)
  end

  -- ------------------------------------------------------------ speech log
  local function topNow()
    local ok, top = pcall(Top.resolve, game)
    return ok and top or nil
  end
  local function battleOn()
    local Battle = package.loaded["src.core.game3.battle.init"] or package.loaded["src.core.game3.battle"]
    return Battle ~= nil and Battle._active == true
  end
  local function screenName(top)
    if top then return tostring(top.gen3) end
    if battleOn() then return "battle" end
    if game.phase ~= "field" then return tostring(game.phase) end
    if L.free() then return "field" end
    return "busy"
  end

  local inputEpoch = 0                               -- counts the driver's presses
  local tapRaw = L.tap
  L.tap = function(button, frames)
    inputEpoch = inputEpoch + 1
    return tapRaw(button, frames)
  end
  local spoken = {}                                  -- { text, frame, screen, epoch }
  local saidFor = setmetatable({}, { __mode = "k" }) -- screen key -> utterances while it was on top
  local RAW = {
    "{[%w_]+}", "%$", "\\[nlp]", "STR_VAR", "%f[%w]nil%f[%W]", "table: ", "function: ",
    "FC %x%x", "EXT_CTRL", "%[%u+_", "_%u%u",
  }
  local say = Speech.say
  Speech.say = function(text, opts)
    text = tostring(text)
    local top = topNow()
    local name = screenName(top)
    if top and top.key ~= nil then saidFor[top.key] = (saidFor[top.key] or 0) + 1 end
    local last = spoken[#spoken]
    -- the same words after another press of the driver's are an answer to that press
    if last and last.epoch ~= inputEpoch then last = nil end
    spoken[#spoken + 1] = { text = text, frame = frame, screen = name, epoch = inputEpoch }
    U.log("SAID", name, (opts and opts.interrupt) and "!" or "+", text)
    if text == "" or not text:match("%S") then finding("empty", "an empty utterance on " .. name) end
    for _, pattern in ipairs(RAW) do
      if text:find(pattern) then finding("raw", ("%s: %q in %q"):format(name, text:match(pattern), text:sub(1, 160))) break end
    end
    if last and last.text == text and frame - last.frame <= 90 and #text > 3 then
      finding("doubled", ("%s: said twice within %d frames: %q"):format(name, frame - last.frame, text:sub(1, 120)))
    end
    return say(text, opts)
  end
  local function mark() return #spoken end
  local function since(m, sep)
    local parts = {}
    for i = m + 1, #spoken do parts[#parts + 1] = spoken[i].text end
    return table.concat(parts, sep or " | ")
  end

  -- ------------------------------------------------------------ screen watch
  -- A screen, menu or prompt that was on top for a while and closed with nothing said.
  local SILENT_MIN = 40
  local current = { key = nil, kind = nil, since = 0 }
  local wasBattle = false
  local partyLineNow -- set below, once the party can be read
  local function watch()
    frame = frame + 1
    local fighting = battleOn()
    if wasBattle and not fighting then U.log("BATTLE", "ended at", L.where(), "party", partyLineNow and partyLineNow() or "") end
    wasBattle = fighting
    local top = topNow()
    local key = top and top.key
    if key ~= current.key then
      if current.key ~= nil and not saidFor[current.key] and frame - current.since >= SILENT_MIN then
        finding("silent", ("screen %s was up %d frames and nothing was spoken, at %s"):format(
          tostring(current.kind), frame - current.since, L.where()))
      end
      current = { key = key, kind = top and top.gen3, since = frame }
      U.log("SCREEN", screenName(top), L.where())
    end
  end
  local rawWait = U.wait
  U.wait = function(n) for _ = 1, n or 1 do rawWait(1) watch() end end
  local function wait(n) U.wait(n or 1) end
  local function kind()
    local top = topNow()
    return top and top.gen3 or nil, top
  end

  -- Press a button and return what was said because of it (waits up to `frames`
  -- for the first words, then a little for the rest).
  local function press(button, frames)
    local m = mark()
    L.tap(button, 2)
    for _ = 1, frames or 40 do
      if #spoken > m then break end
      wait(1)
    end
    wait(6)
    return since(m), m
  end

  -- ------------------------------------------------------------ game state (read only)
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local function flag(name)
    local id = GameData.flag(name)
    if not id then return nil end
    local ok, value = pcall(Flags.getFlag, Space.store, nil, id)
    return ok and value == true
  end
  local function var(name)
    local id = GameData.var(name)
    if not id then return nil end
    local ok, value = pcall(Flags.getVar, Space.store, nil, id)
    return ok and tonumber(value) or nil
  end
  local function party()
    local s = L.session()
    return s and s.party or {}
  end
  local function lead() return party()[1] end
  local function monMaxHp(mon) return tonumber(mon.maxHP or mon.maxHp or (mon.stats and mon.stats.hp)) or 1 end
  local function partyLine()
    local rows = {}
    for _, mon in ipairs(party()) do
      rows[#rows + 1] = ("%s L%s %s/%s"):format(tostring(mon.nickname or mon.species), tostring(mon.level), tostring(mon.hp), tostring(monMaxHp(mon)))
    end
    return #rows > 0 and table.concat(rows, ", ") or "no party"
  end
  partyLineNow = partyLine
  local function onMap(name) return (L.pos()) == L.id(name) end
  local function mapName() return GameData.bareMapId((L.pos())) or "?" end

  -- ------------------------------------------------------------ prompts
  -- A yes/no or list question: what a player would answer, from what was read out.
  -- `policy(question)` returns "a" (the option under the cursor), "b" (NO or cancel)
  -- or a function that makes the choice itself.
  local lastChoiceKey
  local function answerChoice(policy)
    local _, top = kind()
    local key = top and top.key
    if key ~= lastChoiceKey then
      lastChoiceKey = key
      -- give the layer a moment to read the options
      for _ = 1, 30 do
        if key and saidFor[key] then break end
        wait(1)
      end
      if key and not saidFor[key] then
        finding("choice", "a question opened and its options were not read, at " .. L.where()
          .. " after: " .. since(math.max(0, #spoken - 2)):sub(1, 160))
      end
    end
    local question = since(math.max(0, #spoken - 4))
    local how = policy and policy(question) or nil
    if type(how) == "function" then return how(question) end
    if not how then
      local q = question:lower()
      if q:find("delete a move", 1, true) or q:find("make room", 1, true) or q:find("forget", 1, true) then how = "b"
      elseif q:find("stop learning", 1, true) or q:find("stop trying", 1, true) then how = "a"
      elseif q:find("nickname", 1, true) then how = "b"
      elseif q:find("change pok", 1, true) or q:find("switch pok", 1, true) or q:find("will you switch", 1, true) then how = "b"
      else how = "a" end
    end
    U.log("ANSWER", how == "a" and "A" or "B", "to", question:sub(-200))
    L.tap(how, 10)
  end

  -- ------------------------------------------------------------ battle, by the menu
  local battles, battleKey = 0, nil
  local preferMoves = { "MUD SHOT", "WATER GUN", "EMBER", "ABSORB", "TACKLE", "PECK", "SCRATCH", "POUND", "MUD-SLAP" }
  local function battleUi()
    local Ui = package.loaded["src.core.game3.battle.ui"]
    return Ui and Ui._mode or nil
  end
  -- The move list: the cartridge's box is two by two; with a mod loaded upstream steps
  -- through it up and down instead.  Either way: listen to every move by moving the
  -- cursor (up, left, then down three times, right, up, left covers both), then make
  -- the same presses again as far as the best one heard.
  local TOUR = { "up", "left", "down", "down", "down", "right", "up", "left" }
  local function moveName(text) return (tostring(text):match("^[^,]+") or ""):upper() end
  local function pickMove()
    local now = since(math.max(0, #spoken - 1))
    if not now:find("PP %d+ of") then
      -- the list has just opened: its first words come a frame or two later
      for _ = 1, 20 do
        wait(1)
        now = since(math.max(0, #spoken - 1))
        if now:find("PP %d+ of") then break end
      end
    end
    local heardMoves, seen, best, bestRank = {}, {}, nil, nil
    local function consider(text)
      local name = moveName(text)
      if text == "" or seen[name] then return end
      seen[name] = true
      heardMoves[#heardMoves + 1] = text
      if text:upper():find("PP 0 OF", 1, true) then return end
      for rank, wanted in ipairs(preferMoves) do
        if name == wanted and (not bestRank or rank < bestRank) then best, bestRank = name, rank end
      end
    end
    consider(now)
    for _, button in ipairs(TOUR) do
      if battleUi() ~= "moves" then return end
      local said = press(button, 10)
      if said ~= "" then now = said consider(said) end
    end
    if #heardMoves == 0 then finding("battle", "the move list opened and no move was read") end
    if best and moveName(now) ~= best then
      for _, button in ipairs(TOUR) do
        local said = press(button, 10)
        if said ~= "" then now = said end
        if moveName(now) == best then break end
      end
    end
    U.log("MOVE", "chose", moveName(now), "wanted", tostring(best), "of", table.concat(heardMoves, " / "):sub(1, 300))
    L.tap("a", 12)
  end

  local warnedLayer
  local menuHeard, noRun = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
  local function battleAct(policy)
    local Battle = package.loaded["src.core.game3.battle.init"] or package.loaded["src.core.game3.battle"]
    if Battle and Battle._st ~= battleKey then
      battleKey = Battle._st
      battles = battles + 1
      U.log("BATTLE", "started at", L.where(), "party", partyLine())
    end
    local k = kind()
    if k == "choice" then return answerChoice(policy) end
    local mode = battleUi()
    if k and k ~= "battle" and k ~= "message" then
      -- a layer over the battle (level-up moves, nickname keyboard, Pokédex page, evolution)
      if warnedLayer ~= k then
        warnedLayer = k
        U.log("BATTLE", "layer over the battle:", k, "ui", tostring(mode), "phase", tostring(Battle and Battle._phase), "at", L.where())
      end
      -- the party or its summary is not wanted (one Pokémon): B backs out
      L.tap((k == "party" or k == "summary") and "b" or "a", 12)
      return
    end
    -- Wally's catching lesson: the game drives that menu itself; listen, do not press
    local st = Battle and Battle._st
    if st and st.kinds and st.kinds.tutorial == "wally" then
      if mode == "menu" or mode == "moves" then wait(1) return end
    end
    if mode == "menu" then
      -- the menu's words (both sides, then the command under the cursor) follow its opening
      local said = since(math.max(0, #spoken - 3))
      if not said:find("What will", 1, true) then
        for _ = 1, 40 do
          wait(1)
          said = since(math.max(0, #spoken - 3))
          if said:find("What will", 1, true) or battleUi() ~= "menu" then break end
        end
      end
      if battleUi() ~= "menu" then return end
      if not menuHeard[battleKey] then
        menuHeard[battleKey] = true
        U.log("BATTLE", "first menu heard:", said:sub(-300))
        if not said:upper():find("FIGHT", 1, true) then finding("battle", "the battle menu opened without FIGHT being read; heard: " .. said:sub(-200)) end
      end
      -- move round the menu until the wanted command is the last thing read
      local function command(wanted)
        local now = since(math.max(0, #spoken - 1))
        local read = { now }
        for _, button in ipairs(TOUR) do
          if now:upper():match(wanted .. "%s*$") then return true end
          local heardNow = press(button, 10)
          if heardNow ~= "" then now = heardNow read[#read + 1] = heardNow end
        end
        if now:upper():match(wanted .. "%s*$") then return true end
        finding("battle", wanted .. " was not read while moving round the battle menu; heard: " .. table.concat(read, " / "):sub(-200))
        return false
      end
      -- nearly out (by the HP the menu read): RUN, once a battle
      local hp, max = said:match("HP (%d+) of (%d+)")
      if hp and not noRun[battleKey] and tonumber(hp) / math.max(1, tonumber(max)) < 0.25 then
        noRun[battleKey] = true
        if command("RUN") then
          local m = mark()
          L.tap("a", 30)
          for _ = 1, 120 do
            if not battleOn() or since(m) ~= "" then break end
            wait(1)
          end
          U.log("BATTLE", "RUN at HP", hp, "of", max, "heard:", since(m):sub(1, 160))
        end
        return
      end
      if command("FIGHT") then L.tap("a", 12) end
    elseif mode == "moves" then
      pickMove()
    elseif mode == "party" then
      L.tap("a", 12)
    else
      L.tap("a", 8)
    end
  end

  -- ------------------------------------------------------------ play on until free
  local function anyWalk()
    return AutoWalk.active() or BoulderWalk.active() or SwitchWalk.active() or IceWalk.active() or Chase.active()
  end
  local unhandled = {}
  -- A stage's handler for a screen: by its kind, else `handlers.any` (given the kind).
  local function handlerFor(handlers, k)
    if not handlers then return nil end
    return handlers[k] or handlers.any
  end
  -- Advance text, questions and battles until the field has been free for `calm`
  -- frames, or `untilFn` holds.  `handlers[kind]` plays a screen of its own.
  local function advance(opts)
    opts = opts or {}
    local calm, run = opts.calm or 40, 0
    for _ = 1, opts.limit or 6000 do
      if opts.untilFn and opts.untilFn() then return true end
      local k, top = kind()
      if battleOn() then
        run = 0
        battleAct(opts.policy)
      elseif k == "choice" then
        run = 0
        answerChoice(opts.policy)
      elseif k == "message" then
        run = 0
        L.tap("a", 8)
      elseif k and handlerFor(opts.handlers, k) then
        run = 0
        handlerFor(opts.handlers, k)(top, k)
      elseif k then
        run = 0
        if not unhandled[k] then
          unhandled[k] = true
          U.log("NOTE", "a screen with no handler in the driver:", k, "at", L.where())
        end
        if opts.pressOnUnknown ~= false then L.tap("a", 10) else wait(1) end
      elseif L.free() then
        run = run + 1
        if run >= calm and not opts.untilFn then return true end
        wait(1)
      else
        run = 0
        wait(1)
      end
    end
    if opts.untilFn then return opts.untilFn() end
    return L.free()
  end

  -- ------------------------------------------------------------ the object list, by its commands
  local function command(button)
    local m = mark()
    inputEpoch = inputEpoch + 1
    Nav.gamepadaxis(nil, "triggerleft", 1)
    local used = Nav.gamepadpressed(nil, button)
    Nav.gamepadreleased(nil, button)
    Nav.gamepadaxis(nil, "triggerleft", 0)
    wait(3)
    return since(m), used
  end

  local CATEGORY = {
    all = "All", warps = "Warps", connections = "Connections", signs = "Sign", npcs = "NPC",
    objects = "Objects", misc = "Misc", area = "Area",
  }
  -- Cycle the category, then the items, listening for `pattern`.  Returns what was
  -- read for the chosen item, or nil and everything the category read out.
  local function choose(category, pattern)
    local matches = pattern
    if type(pattern) ~= "function" then matches = function(text) return text:find(pattern) ~= nil end end
    local word = CATEGORY[category] or category
    local said, used
    local found = false
    for _ = 1, 9 do
      said, used = command("dpdown")
      if not used then return nil, "the list command was not taken (not on the open map)" end
      if said:lower():find("^" .. word:lower()) then found = true break end
    end
    if not found then
      finding("list", "no category read as " .. word .. " at " .. L.where() .. "; last heard: " .. tostring(said))
      return nil, "no category " .. word
    end
    -- the category's first item is read after its name
    local heardItems, firstItem = {}, nil
    local item = said:gsub("^[^|]*|%s*", "")
    for index = 1, 80 do
      if index > 1 then item = command("dpright") end
      if item == "" then break end
      if firstItem and item == firstItem then break end
      firstItem = firstItem or item
      heardItems[#heardItems + 1] = item
      if matches(item) then return item, heardItems end
    end
    return nil, heardItems
  end
  -- Everything a category reads out, in order.
  local function listItems(category)
    local _, heardItems = choose(category, function() return false end)
    if type(heardItems) ~= "table" then return {} end
    if #heardItems == 1 and heardItems[1]:find("^Empty List") then return {} end
    return heardItems
  end

  local REFUSALS = { "No route", "Cannot reach", "No path", "Blocked by", "Needs ", "Could not plan", "Too dark", "Select an object" }
  local function refusal(text)
    for _, word in ipairs(REFUSALS) do
      if text:find(word, 1, true) then return word end
    end
    return nil
  end

  -- One auto-walk to the item `pattern` of `category`.  Returns "arrived", "refused",
  -- "missing" or "stopped", and what was said.
  --   opts.expect   false when a refusal is the right answer here
  --   opts.policy   answers to the game's questions on the way
  --   opts.untilFn  stop watching the walk once this holds (a scene took over)
  local function go(category, pattern, opts)
    opts = opts or {}
    if not L.free() then advance({ policy = opts.policy, handlers = opts.handlers }) end
    local item, heardItems
    if opts.best then
      -- several items fit: hear them all, then go back to the one `best` picks
      local fitting = {}
      heardItems = listItems(category)
      for _, text in ipairs(heardItems) do
        if type(pattern) == "function" and pattern(text) or type(pattern) == "string" and text:find(pattern) then fitting[#fitting + 1] = text end
      end
      local wanted = #fitting > 0 and opts.best(fitting) or nil
      if wanted then item = choose(category, function(text) return text == wanted end) end
    else
      item, heardItems = choose(category, pattern)
    end
    if not item then
      local read = type(heardItems) == "table" and table.concat(heardItems, "; ") or tostring(heardItems)
      if opts.optional then return "missing", read end
      finding("target", ("nothing matching %s in %s at %s; the list read: %s"):format(
        type(pattern) == "string" and ("%q"):format(pattern) or tostring(opts.what or "the wanted item"), category, L.where(), read))
      return "missing", read
    end
    local m = mark()
    local from = L.where()
    Nav.gamepadpressed(nil, "leftstick")
    Nav.gamepadreleased(nil, "leftstick")
    wait(2)
    local frames, textFor = 0, 0
    while anyWalk() and frames < (opts.limit or 20000) do
      frames = frames + 1
      if opts.untilFn and opts.untilFn() then break end
      local k, top = kind()
      textFor = k == "message" and textFor + 1 or 0
      if battleOn() then
        battleAct(opts.policy)
      elseif k == "choice" then
        answerChoice(opts.policy)
      elseif k == "message" and (not AutoWalk.walking() or textFor > 60) then
        L.tap("a", 8)
      elseif k and k ~= "message" and handlerFor(opts.handlers, k) then
        handlerFor(opts.handlers, k)(top, k)
      else
        wait(1)
      end
    end
    if anyWalk() and not (opts.untilFn and opts.untilFn()) then
      finding("walk", ("the walk to %q from %s was still going after %d frames, at %s"):format(item, from, frames, L.where()))
      Nav.stopWalks()
    end
    wait(4)
    local said = since(m)
    local why = refusal(said)
    local outcome
    if said:find("Arrived at", 1, true) or said:find(" is here", 1, true) then outcome = "arrived"
    elseif why then outcome = "refused"
    else outcome = "stopped" end
    U.log("WALK", outcome, category, item:sub(1, 80), "from", from, "to", L.where(), "|", said:sub(-220))
    -- A walk to a connection ends on the map's edge: the step across is the player's.
    if outcome == "arrived" and category == "connections" and L.free() then
      local button = ({ North = "up", South = "down", East = "right", West = "left" })[item:match("^(%a+) connection") or ""]
      local before = (L.pos())
      if button then
        for _ = 1, 2 do
          if (L.pos()) ~= before or not L.free() then break end
          inputEpoch = inputEpoch + 1
          L.hold(button, 24)
          wait(12)
        end
        U.log("CROSS", button, "from", before, "now", L.where(), L.free() and "free" or "a scene")
        if (L.pos()) == before and L.free() then
          finding("connection", ("held %s on the edge after %q and stayed on %s"):format(button, item:sub(1, 60), L.where()))
        end
      end
    end
    if outcome == "refused" and opts.expect ~= false then
      finding("refusal", ("%s: %q for %q from %s"):format(why, said:sub(-160), item:sub(1, 80), from))
    end
    return outcome, said
  end

  -- Press A at what the walk arrived at and play what follows.
  local function interact(opts)
    opts = opts or {}
    local m = mark()
    L.tap("a", 10)
    for _ = 1, 40 do
      if not L.free() then break end
      wait(1)
    end
    if L.free() and #spoken == m then
      if opts.expectText ~= false then finding("interact", "A did nothing at " .. L.where() .. " (" .. tostring(opts.what or "") .. ")") end
      return false, ""
    end
    advance(opts)
    return true, since(m)
  end

  local function talkTo(category, pattern, opts)
    opts = opts or {}
    local outcome, said = go(category, pattern, opts)
    if outcome ~= "arrived" then return false, said, outcome end
    if not L.free() then advance(opts) return true, said, outcome end -- the arrival itself started a scene
    opts.what = pattern
    -- "Arrived at Wall Clock. Face up and interact": do as told
    local facing = said:match("Face (%l+) and interact")
    if facing then L.tap(facing, 10) end
    local ok, text = interact(opts)
    return ok, text, outcome
  end

  -- The whole list as a player would hear it, category by category, for the log.
  local function readLists(tag)
    for _, category in ipairs({ "warps", "connections", "signs", "npcs", "objects", "area" }) do
      local _, heardItems = choose(category, "\1never")
      U.log("LIST", tag or mapName(), category, type(heardItems) == "table" and table.concat(heardItems, "; ") or tostring(heardItems))
    end
  end

  -- ------------------------------------------------------------ helpers for the stages
  local warnedNames = {}
  local function v(name)
    local value = var(name)
    if value == nil and not warnedNames[name] then
      warnedNames[name] = true
      U.log("NOTE", "no variable named", name, "on this cartridge")
    end
    return value or 0
  end
  local function isBoy()
    local s = L.session()
    return (tonumber(s and s.gender) or 0) == 0
  end
  local function playerName()
    local s = L.session()
    return tostring(s and (s.playerName or (s.player and s.player.name) or s.name) or "")
  end
  local function ownHouse() return "LITTLEROOT_TOWN_" .. (isBoy() and "BRENDANS" or "MAYS") .. "_HOUSE" end
  local function rivalHouse() return "LITTLEROOT_TOWN_" .. (isBoy() and "MAYS" or "BRENDANS") .. "_HOUSE" end
  local function rivalName() return isBoy() and "May" or "Brendan" end
  local function stateLine()
    return ("intro %d rival %d town %d route101 %d lab %d gym %d woods %d badge1 %s dex %s shoes %s"):format(
      v("VAR_LITTLEROOT_INTRO_STATE"), v("VAR_LITTLEROOT_RIVAL_STATE"), v("VAR_LITTLEROOT_TOWN_STATE"), v("VAR_ROUTE101_STATE"),
      v("VAR_BIRCH_LAB_STATE"), v("VAR_PETALBURG_GYM_STATE"), v("VAR_PETALBURG_WOODS_STATE"),
      tostring(flag("FLAG_BADGE01_GET")), tostring(flag("FLAG_SYS_POKEDEX_GET")), tostring(flag("FLAG_SYS_B_DASH")))
  end

  -- Which of YES and NO was read last.
  local function lastOption(text)
    local upper = " " .. tostring(text):upper() .. " "
    local yes, no = 0, 0
    for at in upper:gmatch("()%f[%a]YES%f[%A]") do yes = at end
    for at in upper:gmatch("()%f[%a]NO%f[%A]") do no = at end
    if yes == 0 and no == 0 then return nil end
    return yes > no and "YES" or "NO"
  end
  -- A yes or no drawn by a screen of its own: move to `want` by what is read, press A.
  local function pickYesNo(want, heard, what)
    local now = lastOption(heard)
    if not now then finding("choice", tostring(what) .. ": YES or NO was not read; heard: " .. tostring(heard)) end
    for _ = 1, 3 do
      if now == want then break end
      local said = press(want == "YES" and "up" or "down", 20)
      now = lastOption(said) or now
    end
    if now ~= want then finding("choice", tostring(what) .. ": could not hear the cursor reach " .. want) end
    return press("a", 40)
  end

  -- SAVE from the start menu, as a player saves.
  local function saveGame()
    if not L.free() then advance() end
    local said = press("start", 40)
    if kind() ~= "start" then
      finding("menu", "START did not open the start menu at " .. L.where() .. "; heard: " .. said)
      return false
    end
    if said == "" then finding("silent", "the start menu opened and nothing was read") end
    local row, rows = said, { said }
    for _ = 1, 10 do
      if row:upper():find("SAVE", 1, true) then break end
      row = press("down", 20)
      rows[#rows + 1] = row
    end
    U.log("MENU", "start menu rows heard:", table.concat(rows, " / "))
    if not row:upper():find("SAVE", 1, true) then
      finding("menu", "SAVE was not read in the start menu")
      L.tap("b", 20)
      return false
    end
    local m = mark()
    L.tap("a", 30)
    for _ = 1, 2500 do
      local k = kind()
      if not k and L.free() then break end
      if k == "choice" then
        answerChoice(function() return "a" end)
      elseif k == "message" then
        L.tap("a", 10)
      elseif k == "start" then
        L.tap("b", 15)
      elseif k then
        -- the save screen's own YES and NO
        if lastOption(since(m)) == "NO" then press("up", 15) end
        L.tap("a", 20)
      else
        wait(1)
      end
    end
    local text = since(m)
    U.log("SAVE", text:sub(1, 500))
    if not text:lower():find("saved", 1, true) then
      finding("save", "nothing said the game was saved; heard: " .. text:sub(-200))
      return false
    end
    return true
  end

  local visited = {}
  local function visit()
    local here = mapName()
    if visited[here] or os.getenv("WALK_LISTS") == "0" or not L.free() then return end
    visited[here] = true
    readLists(here)
  end

  -- ------------------------------------------------------------ the way between places
  local function conn(name)
    return { "connections", function(text) return text:find("connection to " .. name .. "%f[%W]") ~= nil and not text:find("connection to " .. name .. "%d") end }
  end
  local function warp(pattern) return { "warps", pattern } end
  local function exitTo(town) return { "warps", "^" .. town .. ":" } end
  local function northmost(items)
    local best, bestUp
    for _, text in ipairs(items) do
      local up = tonumber(text:match("(%d+) up")) or 0
      if text:find(" down") then up = -(tonumber(text:match("(%d+) down")) or 0) end
      if not bestUp or up > bestUp then best, bestUp = text, up end
    end
    return best
  end

  local CENTERS = { OLDALE_TOWN = true, PETALBURG_CITY = true, RUSTBORO_CITY = true, DEWFORD_TOWN = true, SLATEPORT_CITY = true }
  local TOWN_LABEL = { OLDALE_TOWN = "Oldale Town", PETALBURG_CITY = "Petalburg City", RUSTBORO_CITY = "Rustboro City",
    DEWFORD_TOWN = "Dewford Town", SLATEPORT_CITY = "Slateport City" }

  -- The neighbours of a map and the list item that leads to each.
  local function edges(map)
    local own, rival = ownHouse(), rivalHouse()
    if map == "LITTLEROOT_TOWN" then
      local name = playerName()
      return {
        ROUTE101 = conn("Route 101"),
        LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB = warp("Birch's Lab"),
        [own .. "_1F"] = { "warps", function(text) return text:find("House") ~= nil and text:find(name .. "'s", 1, true) ~= nil end },
        [rival .. "_1F"] = { "warps", function(text) return text:find("House") ~= nil and text:find(name .. "'s", 1, true) == nil end },
      }
    elseif map == own .. "_1F" then return { LITTLEROOT_TOWN = exitTo("Littleroot Town"), [own .. "_2F"] = warp("2F") }
    elseif map == own .. "_2F" then return { [own .. "_1F"] = warp("1F") }
    elseif map == rival .. "_1F" then return { LITTLEROOT_TOWN = exitTo("Littleroot Town"), [rival .. "_2F"] = warp("2F") }
    elseif map == rival .. "_2F" then return { [rival .. "_1F"] = warp("1F") }
    elseif map == "LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB" then return { LITTLEROOT_TOWN = exitTo("Littleroot Town") }
    elseif map == "ROUTE101" then return { LITTLEROOT_TOWN = conn("Littleroot Town"), OLDALE_TOWN = conn("Oldale Town") }
    elseif map == "OLDALE_TOWN" then
      return { ROUTE101 = conn("Route 101"), ROUTE103 = conn("Route 103"), ROUTE102 = conn("Route 102"),
        OLDALE_TOWN_POKEMON_CENTER_1F = warp("Center 1F") }
    elseif map == "ROUTE103" then return { OLDALE_TOWN = conn("Oldale Town") }
    elseif map == "ROUTE102" then return { OLDALE_TOWN = conn("Oldale Town"), PETALBURG_CITY = conn("Petalburg City") }
    elseif map == "PETALBURG_CITY" then
      return { ROUTE102 = conn("Route 102"), ROUTE104 = conn("Route 104"), PETALBURG_CITY_GYM = warp("Petalburg City Gym"),
        PETALBURG_CITY_POKEMON_CENTER_1F = warp("Center 1F") }
    elseif map == "PETALBURG_CITY_GYM" then return { PETALBURG_CITY = exitTo("Petalburg City") }
    elseif map == "ROUTE104" then
      -- the route is in two halves joined by the woods: the connection is chosen and
      -- the layer is left to find the way round
      return { PETALBURG_CITY = conn("Petalburg City"), RUSTBORO_CITY = conn("Rustboro City"),
        ROUTE104_MR_BRINEYS_HOUSE = warp("Mr. Briney's House") }
    elseif map == "ROUTE104_MR_BRINEYS_HOUSE" then return { ROUTE104 = exitTo("Route 104") }
    elseif map == "PETALBURG_WOODS" then
      -- three ways out, all read as Route 104: the one furthest north leads on
      return { RUSTBORO_CITY = { "warps", "Route 104", best = northmost } }
    elseif map == "RUSTBORO_CITY" then
      return { ROUTE104 = conn("Route 104"), ROUTE116 = conn("Route 116"), RUSTBORO_CITY_GYM = warp("Rustboro City Gym"),
        RUSTBORO_CITY_POKEMON_CENTER_1F = warp("Center 1F"), RUSTBORO_CITY_DEVON_CORP_1F = warp("Devon Corp 1F") }
    elseif map == "RUSTBORO_CITY_DEVON_CORP_1F" then
      return { RUSTBORO_CITY = exitTo("Rustboro City"), RUSTBORO_CITY_DEVON_CORP_2F = warp("2F") }
    elseif map == "RUSTBORO_CITY_DEVON_CORP_2F" then
      return { RUSTBORO_CITY_DEVON_CORP_1F = warp("1F"), RUSTBORO_CITY_DEVON_CORP_3F = warp("3F") }
    elseif map == "RUSTBORO_CITY_DEVON_CORP_3F" then return { RUSTBORO_CITY_DEVON_CORP_2F = warp("2F") }
    elseif map == "RUSTBORO_CITY_GYM" then return { RUSTBORO_CITY = exitTo("Rustboro City") }
    elseif map == "ROUTE116" then return { RUSTBORO_CITY = conn("Rustboro City"), RUSTURF_TUNNEL = warp("Rusturf Tunnel") }
    elseif map == "RUSTURF_TUNNEL" then return { ROUTE116 = warp("Route 116") }
    end
    local town = map:match("^(.+)_POKEMON_CENTER_1F$")
    if town and TOWN_LABEL[town] then return { [town] = exitTo(TOWN_LABEL[town]) } end
    return {}
  end

  -- The first leg from here towards `dest` (breadth first over `edges`).
  local function nextLeg(dest)
    local here = mapName()
    local from, queue, at = { [here] = false }, { here }, 1
    while queue[at] do
      local map = queue[at]
      at = at + 1
      if map == dest then
        local step = map
        while from[step] and from[step] ~= here do step = from[step] end
        return edges(here)[step], step
      end
      for neighbour in pairs(edges(map)) do
        if from[neighbour] == nil then
          from[neighbour] = map
          queue[#queue + 1] = neighbour
        end
      end
    end
    return nil, "the driver knows no way from " .. here .. " to " .. dest
  end

  local function weak(ratio)
    local mon = lead()
    return mon ~= nil and (tonumber(mon.hp) or 0) / monMaxHp(mon) < (ratio or 0.5)
  end

  -- Into the town's Pokémon Center, the nurse, and out again.
  local function healHere()
    local town = mapName()
    U.log("HEAL", "to the Pokémon Center of", town, "party", partyLine())
    if not TOWN_LABEL[town] and not town:find("POKEMON_CENTER_1F") then
      -- a scene carried the player indoors (Devon's employee): not a town with a Center
      U.log("HEAL", "not in a town with a Center:", L.where())
      return false
    end
    if not town:find("POKEMON_CENTER_1F") then
      go("warps", "Center 1F")
      if not mapName():find("POKEMON_CENTER_1F") then
        finding("heal", "could not get into the Pokémon Center from " .. L.where())
        return false
      end
    end
    visit()
    local ok, text = talkTo("npcs", "Nurse")
    U.log("HEAL", "the nurse:", tostring(ok), tostring(text):sub(1, 300), "party", partyLine())
    local mon = lead()
    if mon and (tonumber(mon.hp) or 0) < monMaxHp(mon) then
      finding("heal", "the party was not healed after talking to the nurse at " .. L.where() .. ": " .. partyLine())
    end
    local label = TOWN_LABEL[mapName():match("^(.+)_POKEMON_CENTER_1F$") or ""]
    if label then go("warps", "^" .. label .. ":") end
    return true
  end

  -- Walk on, one list item at a time, until the player is on `dest` (or `untilFn` holds).
  local function travel(dest, opts)
    opts = opts or {}
    local stuck = 0
    for _ = 1, opts.max or 40 do
      advance({ policy = opts.policy, handlers = opts.handlers })
      if opts.untilFn and opts.untilFn() then return true end
      local here = mapName()
      if here == dest then return true end
      visit()
      if CENTERS[here] and weak(opts.healBelow or 0.6) and not opts.noHeal then healHere() end
      local leg, why = nextLeg(dest)
      if not leg then return false, tostring(why) end
      local outcome, said = go(leg[1], leg[2], { policy = opts.policy, handlers = opts.handlers, untilFn = opts.untilFn, best = leg.best, what = why })
      advance({ policy = opts.policy, handlers = opts.handlers })
      if mapName() == here then
        stuck = stuck + 1
        if outcome == "missing" or outcome == "refused" or stuck >= 3 then
          return false, ("%s on the way from %s to %s: %s"):format(outcome, here, dest, tostring(said):sub(-160))
        end
      else
        stuck = 0
      end
    end
    return mapName() == dest, "at " .. L.where()
  end

  -- Wild battles for experience: back and forth between two places until the first
  -- Pokémon is at `level`.
  local function trainTo(level, placeA, placeB, rounds)
    for round = 1, rounds or 8 do
      local mon = lead()
      if not mon or (tonumber(mon.level) or 0) >= level then return true end
      U.log("TRAIN", "round", round, "towards level", level, "party", partyLine())
      local ok, why = travel(round % 2 == 1 and placeA or placeB)
      if not ok then return false, why end
    end
    local mon = lead()
    return mon ~= nil and (tonumber(mon.level) or 0) >= level
  end

  -- ------------------------------------------------------------ stages
  local stages = {}
  local function stage(name, done, fn) stages[#stages + 1] = { name = name, done = done, run = fn } end
  local results = {}
  local continued = false

  -- Title to the truck: the intro, the title, NEW GAME, Birch's speech, BOY, the name.
  -- With WALK_CONTINUE=1 and a save: CONTINUE.
  stage("boot", nil, function()
    for _ = 1, 1200 do
      if game.phase == "boot" and game.boot then break end
      wait(1)
    end
    if game.phase ~= "boot" then return false, "the game never reached its boot screens" end
    local wantName = (os.getenv("WALK_NAME") or "ACE"):upper()
    local wantContinue = os.getenv("WALK_CONTINUE") == "1"
    local typed, namingDone, started = false, false, frame
    local seen = {}
    local function note(k)
      if not seen[k] then seen[k] = true U.log("BOOT", "screen", k) end
    end
    local handlers = {}
    function handlers.hoenn_intro()
      note("intro")
      wait(30)
      if not since(0):find("Intro", 1, true) then finding("silent", "the intro opened and nothing was said in 30 frames") end
      L.tap("start", 20)
    end
    function handlers.hoenn_title()
      note("title")
      local m = mark()
      for _ = 1, 900 do
        if since(m) ~= "" or kind() ~= "hoenn_title" then break end
        wait(1)
      end
      if kind() ~= "hoenn_title" then return end
      if not since(math.max(0, m - 3)):find("Press start", 1, true) then
        finding("silent", "the title never said that START can be pressed")
      end
      L.tap("start", 30)
    end
    function handlers.hoenn_main_menu()
      note("main menu")
      local m = mark()
      for _ = 1, 120 do
        if since(m) ~= "" or kind() ~= "hoenn_main_menu" then break end
        wait(1)
      end
      local said = since(math.max(0, m - 1))
      U.log("BOOT", "main menu heard:", said)
      if wantContinue and said:find("CONTINUE", 1, true) then
        continued = true
        L.tap("a", 30)
        return
      end
      if not said:find("NEW GAME", 1, true) then
        for _ = 1, 4 do
          said = press("down", 30)
          if said:find("NEW GAME", 1, true) then break end
        end
      end
      if not said:find("NEW GAME", 1, true) then
        finding("menu", "NEW GAME was never read on the main menu; heard: " .. said)
        return
      end
      L.tap("a", 30)
    end
    function handlers.hoenn_birch(top)
      note("Birch's speech")
      local birch = top.key
      if birch.genderMenu then
        local said = since(math.max(0, #spoken - 2))
        if not said:find("BOY", 1, true) then finding("menu", "the BOY or GIRL menu opened without BOY being read; heard: " .. said) end
        U.log("BOOT", "gender menu heard:", said)
        -- look at the other row and come back, as a player checking the options would
        local other = press("down", 20)
        if not other:find("GIRL", 1, true) then finding("menu", "moving down in the BOY or GIRL menu did not read GIRL; heard: " .. other) end
        -- the picture slides for about a second after a move and the game takes no
        -- press meanwhile (the cartridge's own behaviour): press until BOY is read
        local back, tries = "", 0
        for attempt = 1, 8 do
          tries = attempt
          back = press("up", 25)
          if back:find("BOY", 1, true) then break end
        end
        U.log("BOOT", "gender rows:", other, "/", back, "presses of up needed:", tries)
        if not back:find("BOY", 1, true) then
          finding("menu", "could not get back to BOY in the gender menu by pressing up; heard: " .. back)
        elseif tries > 1 then
          U.log("NOTE", "the gender menu ignored " .. (tries - 1) .. " press(es) of up while the picture slid; nothing says to wait")
        end
        -- the same wait before A counts
        for _ = 1, 8 do
          if not top.key.genderMenu then break end
          L.tap("a", 25)
        end
      elseif birch.nameMenu then
        -- Ruby and Sapphire: NEW NAME is the first row
        local said = since(math.max(0, #spoken - 2))
        U.log("BOOT", "name menu heard:", said)
        L.tap("a", 20)
      elseif birch.yesNo then
        local said = since(math.max(0, #spoken - 3))
        U.log("BOOT", "yes/no heard:", said)
        if not said:find("YES", 1, true) then finding("menu", "Birch's yes or no opened without YES being read; heard: " .. said) end
        L.tap("a", 20)
      else
        L.tap("a", 10)
      end
    end
    function handlers.naming(top)
      note("naming")
      if namingDone then wait(1) return end
      local Naming = top.mod
      local st = Naming and Naming._state
      if not typed then
        local opening
        for _ = 1, 120 do
          opening = since(math.max(0, #spoken - 2))
          if saidFor[top.key] then break end
          wait(1)
        end
        U.log("NAMING", "on entry heard:", tostring(opening), "| name field:", tostring(st and st.name))
        if not saidFor[top.key] then finding("silent", "the naming screen opened and nothing was read") end
        -- type each letter by moving and listening for its cell
        for letter in wantName:gmatch(".") do
          local found = false
          local here = ""
          for _ = 1, 6 do          -- rows
            for _ = 1, 10 do       -- cells of a row
              here = press("right", 15)
              if here:upper():match("^%s*" .. letter .. "%f[%W]") then found = true break end
            end
            if found then break end
            here = press("down", 15)
            if here:upper():match("^%s*" .. letter .. "%f[%W]") then found = true break end
          end
          if not found then
            finding("naming", "could not find the letter " .. letter .. " by listening to the keyboard; last heard: " .. here)
            break
          end
          local after = press("a", 20)
          U.log("NAMING", "typed", letter, "heard:", after, "| name field:", tostring(st and st.name))
          if not after:find(letter, 1, true) then finding("naming", "typing " .. letter .. " was not confirmed in speech; heard: " .. after) end
        end
        typed = true
        -- B deletes: take one letter off and put it back, as a player correcting a slip
        local deleted = press("b", 20)
        U.log("NAMING", "B heard:", deleted, "| name field:", tostring(st and st.name))
        if not deleted:lower():find("delete", 1, true) then finding("naming", "B (delete a letter) was not confirmed in speech; heard: " .. deleted) end
        local again = press("a", 20)
        U.log("NAMING", "A again heard:", again, "| name field:", tostring(st and st.name))
        local toOk = press("start", 20)
        U.log("NAMING", "START heard:", toOk)
        if not toOk:lower():find("ok", 1, true) then finding("naming", "START (jump to OK) said nothing about OK; heard: " .. toOk) end
        local done = press("a", 30)
        U.log("NAMING", "A on OK heard:", done, "| name field:", tostring(st and st.name))
        namingDone = true
      end
    end
    for _ = 1, 20000 do
      if game.phase == "field" then break end
      local k, top = kind()
      if k and handlers[k] then handlers[k](top)
      elseif k == "choice" or k == "message" then L.tap("a", 10)
      else wait(1) end
    end
    if game.phase ~= "field" then return false, "still in the boot screens after " .. (frame - started) .. " frames, on " .. tostring(kind()) end
    advance({ calm = 30, limit = 1500 })
    U.log("BOOT", "in the field at", L.where(), "player name", playerName(), "boy", tostring(isBoy()), "continued", tostring(continued))
    if not continued then
      if playerName():upper() ~= wantName then finding("naming", "the name in the save is " .. playerName() .. ", typed " .. wantName) end
      if not isBoy() then finding("menu", "BOY was read when A was pressed and the player is a girl") end
    end
    return true, L.where()
  end)

  -- The truck: wait for it to stop, find the way out in the list, walk out; mother
  -- takes the player indoors.
  stage("truck", function() return not onMap("INSIDE_OF_TRUCK") and v("VAR_LITTLEROOT_INTRO_STATE") >= 3 end, function()
    advance({ calm = 60, limit = 3000 })
    if onMap("INSIDE_OF_TRUCK") then
      visit()
      go("warps", ".", { untilFn = function() return not onMap("INSIDE_OF_TRUCK") end })
    end
    advance({ calm = 90, limit = 6000 })
    return mapName() == ownHouse() .. "_1F", L.where()
  end)

  -- Upstairs, the wall clock set by ear, mother's visit, the television downstairs.
  stage("house", function() return flag("FLAG_SET_WALL_CLOCK") and v("VAR_LITTLEROOT_INTRO_STATE") >= 7 end, function()
    local own = ownHouse()
    local clockDone = false
    local handlers = {}
    function handlers.wall_clock(top)
      if clockDone then wait(1) return end
      for _ = 1, 180 do
        if saidFor[top.key] then break end
        wait(1)
      end
      local opening = since(math.max(0, #spoken - 1))
      U.log("CLOCK", "on entry heard:", opening)
      if not saidFor[top.key] then finding("silent", "the wall clock opened and nothing was read") end
      local steps = {}
      for _ = 1, 3 do steps[#steps + 1] = press("right", 30) end
      steps[#steps + 1] = press("left", 30)
      U.log("CLOCK", "right, right, right, left heard:", table.concat(steps, " / "))
      for index, text in ipairs(steps) do
        if text == "" then finding("clock", "press " .. index .. " of the hand said nothing") end
      end
      -- hold right for a second: the hand runs fast
      local m = mark()
      L.hold("right", 70)
      wait(30)
      U.log("CLOCK", "holding right heard:", since(m))
      if since(m) == "" then finding("clock", "holding the hand said nothing") end
      local question = press("a", 90)
      U.log("CLOCK", "A heard:", question)
      if not question:find("correct time", 1, true) then finding("clock", "A did not read the confirm question; heard: " .. question) end
      local after = pickYesNo("YES", question, "the wall clock's confirm")
      U.log("CLOCK", "YES heard:", after)
      clockDone = true
    end
    if mapName() == own .. "_1F" then
      visit()
      go("warps", "2F", { handlers = handlers })
      advance({ handlers = handlers })
    end
    if mapName() ~= own .. "_2F" then return false, "not upstairs: " .. L.where() end
    visit()
    if not flag("FLAG_SET_WALL_CLOCK") then
      local ok, text, outcome = talkTo("signs", "Clock", { handlers = handlers, calm = 90 })
      U.log("CLOCK", "talk:", tostring(ok), tostring(outcome), tostring(text):sub(-300))
    end
    advance({ handlers = handlers, calm = 90 })
    if not flag("FLAG_SET_WALL_CLOCK") then return false, "the clock is not set: " .. stateLine() end
    go("warps", "1F", { handlers = handlers })
    advance({ calm = 120 })
    return true, L.where() .. " " .. stateLine()
  end)

  -- Next door: the neighbour's mother, upstairs, the Poké Ball on the floor, the rival.
  stage("rival_house", function() return v("VAR_LITTLEROOT_RIVAL_STATE") >= 3 end, function()
    local ok, why = travel(rivalHouse() .. "_2F")
    if not ok then return false, tostring(why) end
    visit()
    local talked, text, outcome = talkTo("objects", "Ball", { calm = 90 })
    U.log("RIVAL", "the ball:", tostring(talked), tostring(outcome), tostring(text):sub(-300))
    advance({ calm = 90 })
    return true, L.where() .. " " .. stateLine()
  end)

  -- Route 101: Birch's shout, his bag, the starter chosen by ear, the first battle,
  -- the lab.
  stage("starter", function() return #party() >= 1 and v("VAR_BIRCH_LAB_STATE") >= 3 end, function()
    local want = (os.getenv("WALK_STARTER") or "MUDKIP"):upper()
    local chosen = false
    local handlers = {}
    function handlers.starter_choose(top)
      if chosen then L.tap("a", 20) return end
      for _ = 1, 240 do
        if saidFor[top.key] then break end
        wait(1)
      end
      wait(20)
      local opening = since(math.max(0, #spoken - 2))
      U.log("STARTER", "on entry heard:", opening)
      if not saidFor[top.key] then finding("silent", "the starter screen opened and nothing was read") end
      local here, heardAll = opening, { opening }
      for _ = 1, 3 do
        if here:upper():find(want, 1, true) then break end
        here = press("right", 40)
        heardAll[#heardAll + 1] = here
      end
      for _ = 1, 3 do
        if here:upper():find(want, 1, true) then break end
        here = press("left", 40)
        heardAll[#heardAll + 1] = here
      end
      U.log("STARTER", "moving heard:", table.concat(heardAll, " / "))
      if not here:upper():find(want, 1, true) then
        finding("starter", "could not hear " .. want .. " while moving over the three balls; heard: " .. table.concat(heardAll, " / "))
      end
      local question = press("a", 120)
      U.log("STARTER", "A heard:", question)
      if not question:lower():find("choose", 1, true) then finding("starter", "A on a ball did not read the question; heard: " .. question) end
      local after = pickYesNo("YES", question, "the starter's confirm")
      U.log("STARTER", "YES heard:", after)
      chosen = true
    end
    local ok, why = travel("LITTLEROOT_TOWN")
    if not ok then return false, tostring(why) end
    if v("VAR_ROUTE101_STATE") < 2 then
      go(conn("Route 101")[1], conn("Route 101")[2], { handlers = handlers, untilFn = function() return v("VAR_ROUTE101_STATE") >= 2 and L.free() end })
      advance({ handlers = handlers, calm = 60 })
    end
    if not onMap("ROUTE101") then return false, "Birch's scene did not start: " .. L.where() .. " " .. stateLine() end
    visit()
    local talked, text, outcome = talkTo("objects", "Bag", { handlers = handlers, calm = 120, limit = 30000 })
    U.log("STARTER", "the bag:", tostring(talked), tostring(outcome), tostring(text):sub(-200))
    advance({ handlers = handlers, calm = 120, limit = 30000 })
    return true, L.where() .. " " .. partyLine() .. " " .. stateLine()
  end)

  -- Through Oldale to Route 103 and the rival's battle.
  stage("rival_battle", function() return flag("FLAG_DEFEATED_RIVAL_ROUTE103") end, function()
    local detail = ""
    for attempt = 1, 3 do
      local trained, whyNot = trainTo(7, "OLDALE_TOWN", "LITTLEROOT_TOWN", 6)
      if not trained then U.log("TRAIN", "stopped:", tostring(whyNot), partyLine()) end
      local ok, why = travel("OLDALE_TOWN")
      if not ok then return false, tostring(why) end
      visit()
      if weak(0.95) then healHere() end
      ok, why = travel("ROUTE103")
      if not ok then return false, tostring(why) end
      visit()
      local name = rivalName()
      local talked, text, outcome = talkTo("npcs", name, { calm = 120, limit = 30000 })
      detail = ("attempt %d: %s %s"):format(attempt, tostring(outcome), tostring(text):sub(-120))
      U.log("RIVAL", "Route 103:", tostring(talked), detail)
      advance({ calm = 120 })
      if flag("FLAG_DEFEATED_RIVAL_ROUTE103") then break end
      if outcome == "missing" then return false, "the rival is not in the NPC list on Route 103" end
    end
    return true, L.where() .. " " .. partyLine() .. " " .. detail
  end)

  -- Back to the lab for the Pokédex.
  stage("pokedex", function() return flag("FLAG_SYS_POKEDEX_GET") end, function()
    local ok, why = travel("LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB")
    if not ok then return false, tostring(why) end
    advance({ calm = 120, limit = 20000 })
    visit()
    if not flag("FLAG_SYS_POKEDEX_GET") then
      local talked, text, outcome = talkTo("npcs", "Birch", { calm = 120 })
      U.log("LAB", "Birch:", tostring(talked), tostring(outcome), tostring(text):sub(-200))
    end
    return true, L.where() .. " " .. stateLine()
  end)

  -- Leaving town: mother and the Running Shoes.
  stage("shoes", function() return flag("FLAG_SYS_B_DASH") end, function()
    local ok, why = travel("ROUTE101", { untilFn = function() return flag("FLAG_SYS_B_DASH") and L.free() end })
    advance({ calm = 90 })
    return ok, tostring(why) .. " " .. L.where() .. " " .. stateLine()
  end)

  stage("petalburg", function() return flag("FLAG_VISITED_PETALBURG_CITY") end, function()
    local ok, why = travel("PETALBURG_CITY")
    return ok, tostring(why) .. " " .. L.where() .. " " .. partyLine()
  end)

  -- The gym: father, Wally, and the catching lesson (the game plays Wally's battle).
  stage("catching_lesson", function() return v("VAR_PETALBURG_GYM_STATE") >= 1 end, function()
    local ok, why = travel("PETALBURG_CITY")
    if not ok then return false, tostring(why) end
    visit()
    healHere()
    ok, why = travel("PETALBURG_CITY_GYM")
    if not ok then return false, tostring(why) end
    advance({ calm = 90 })
    visit()
    if v("VAR_PETALBURG_GYM_STATE") < 1 then
      local m = mark()
      local talked, text, outcome = talkTo("npcs", "Norman", { calm = 150, limit = 40000 })
      U.log("LESSON", "Norman:", tostring(talked), tostring(outcome))
      advance({ calm = 150, limit = 40000 })
      U.log("LESSON", "everything heard:", since(m):sub(1, 3000))
      local _ = text
    end
    return true, L.where() .. " " .. stateLine()
  end)

  -- Route 104 and Petalburg Woods: the Devon researcher and the Aqua grunt.
  stage("woods", function() return v("VAR_PETALBURG_WOODS_STATE") >= 1 end, function()
    local ok, why = travel("ROUTE104")
    if not ok then return false, tostring(why) end
    visit()
    ok, why = travel("RUSTBORO_CITY", { untilFn = function() return v("VAR_PETALBURG_WOODS_STATE") >= 1 and L.free() end })
    advance({ calm = 90 })
    return ok, tostring(why) .. " " .. L.where() .. " " .. partyLine() .. " " .. stateLine()
  end)

  stage("rustboro", function() return flag("FLAG_VISITED_RUSTBORO_CITY") end, function()
    local ok, why = travel("RUSTBORO_CITY")
    return ok, tostring(why) .. " " .. L.where() .. " " .. partyLine()
  end)

  -- The first gym.
  stage("roxanne", function() return flag("FLAG_BADGE01_GET") end, function()
    local detail = ""
    for attempt = 1, 3 do
      local ok, why = travel("RUSTBORO_CITY")
      if not ok then return false, tostring(why) end
      visit()
      local trained = trainTo(12, "ROUTE116", "RUSTBORO_CITY", 8)
      if not trained then U.log("TRAIN", "below level 12:", partyLine()) end
      ok, why = travel("RUSTBORO_CITY")
      if not ok then return false, tostring(why) end
      if weak(0.95) then healHere() end
      ok, why = travel("RUSTBORO_CITY_GYM")
      if not ok then return false, tostring(why) end
      visit()
      local talked, text, outcome = talkTo("npcs", "Roxanne", { calm = 150, limit = 60000 })
      detail = ("attempt %d: %s %s"):format(attempt, tostring(outcome), tostring(text):sub(-160))
      U.log("GYM", "Roxanne:", tostring(talked), detail)
      advance({ calm = 150, limit = 20000 })
      if flag("FLAG_BADGE01_GET") then break end
      if outcome == "missing" then return false, "Roxanne is not in the NPC list" end
    end
    return true, L.where() .. " " .. partyLine() .. " " .. detail
  end)

  -- The Devon Goods: the grunt's escape through Rustboro, Route 116, Mr. Briney and
  -- the grunt in Rusturf Tunnel.
  local function gruntLine()
    return ("rustboro %d route116 %d tunnel %d stolen %s recovered %s returned %s pokenav %s briney %d"):format(
      v("VAR_RUSTBORO_CITY_STATE"), v("VAR_ROUTE116_STATE"), v("VAR_RUSTURF_TUNNEL_STATE"),
      tostring(flag("FLAG_DEVON_GOODS_STOLEN")), tostring(flag("FLAG_RECOVERED_DEVON_GOODS")),
      tostring(flag("FLAG_RETURNED_DEVON_GOODS")), tostring(flag("FLAG_RECEIVED_POKENAV")), v("VAR_BRINEY_HOUSE_STATE"))
  end
  stage("devon_goods", function() return flag("FLAG_RECOVERED_DEVON_GOODS") end, function()
    local detail = ""
    local recovered = function() return flag("FLAG_RECOVERED_DEVON_GOODS") and L.free() end
    for attempt = 1, 3 do
      local ok, why = travel("RUSTBORO_CITY")
      if not ok then return false, tostring(why) end
      if weak(0.95) then healHere() end
      ok, why = travel("RUSTURF_TUNNEL", { untilFn = recovered })
      if recovered() then break end
      if not ok then return false, tostring(why) .. " " .. gruntLine() end
      visit()
      local talked, text, outcome = talkTo("npcs", "[Gg]runt", { calm = 150, limit = 40000 })
      detail = ("attempt %d: %s %s"):format(attempt, tostring(outcome), tostring(text):sub(-160))
      U.log("GOODS", "the grunt:", tostring(talked), detail, gruntLine())
      advance({ calm = 150, limit = 20000 })
      if flag("FLAG_RECOVERED_DEVON_GOODS") then break end
      if outcome == "missing" then return false, "no grunt in the NPC list in Rusturf Tunnel: " .. gruntLine() end
    end
    return true, L.where() .. " " .. partyLine() .. " " .. gruntLine() .. " " .. detail
  end)

  -- The goods back to Devon: the president on 3F, the PokéNav and the letter.
  stage("pokenav", function() return flag("FLAG_RECEIVED_POKENAV") end, function()
    local got = function() return flag("FLAG_RECEIVED_POKENAV") and L.free() end
    local ok, why = travel("RUSTBORO_CITY", { untilFn = got })
    if got() then return true, L.where() .. " " .. gruntLine() end
    if not ok then return false, tostring(why) .. " " .. gruntLine() end
    advance({ calm = 90 })
    ok, why = travel("RUSTBORO_CITY_DEVON_CORP_3F", { untilFn = got })
    if got() then return true, L.where() .. " " .. gruntLine() end
    if not ok then return false, tostring(why) .. " " .. gruntLine() end
    advance({ calm = 120 })
    visit()
    if not flag("FLAG_RECEIVED_POKENAV") then
      local talked, text, outcome = talkTo("npcs", "Stone", { calm = 150, limit = 30000 })
      U.log("DEVON", "the president:", tostring(talked), tostring(outcome), tostring(text):sub(-300), gruntLine())
      if outcome == "missing" then
        talked, text, outcome = talkTo("npcs", "President", { calm = 150, limit = 30000 })
        U.log("DEVON", "the president, second try:", tostring(talked), tostring(outcome), tostring(text):sub(-300))
      end
    end
    advance({ calm = 120 })
    return flag("FLAG_RECEIVED_POKENAV"), L.where() .. " " .. gruntLine()
  end)

  -- Emerald's Match Call lesson outside Devon: the game opens the start menu and waits
  -- for POKeNAV, MATCH CALL, MR. STONE, CALL.  Each choice is made by what was read.
  local function lastSaid() return spoken[#spoken] and spoken[#spoken].text or "", spoken[#spoken] and spoken[#spoken].frame or 0 end
  local function matchCallHandlers()
    local handlers, phase, tries = {}, "menu", 0
    local function moveOn(next)
      phase, tries = next, 0
      L.tap("a", 40)
    end
    -- one more press in this phase; past a dozen the lesson is given up and logged
    local function another(now)
      tries = tries + 1
      U.log("MATCHCALL", phase, "press", tries, "after:", tostring(now):sub(1, 160))
      -- what upstream's Pokénav shows (read only), to tell a silent screen from a lost press
      local Pokenav = package.loaded["src.ui.game3.rse.pokenav.init"]
      local okShell, shell = pcall(function() return Pokenav and Pokenav.active() end)
      local screen = okShell and type(shell) == "table" and shell.screen or nil
      U.log("MATCHCALL", "state:", "shell phase", tostring(okShell and type(shell) == "table" and shell.phase),
        "mode", tostring(okShell and type(shell) == "table" and shell.mode),
        "handler", tostring(screen and screen.handler), "visible", tostring(screen and screen.visible),
        "options", tostring(screen and screen.options and #screen.options), "cursor", tostring(screen and screen.optionCursor),
        "printer", tostring(screen and screen.printer ~= nil), "callBox", tostring(screen and screen.callBox),
        "checkPage", tostring(screen and screen.checkPage))
      if tries > 12 then
        finding("pokenav", "Match Call lesson: the " .. phase .. " step never read what was wanted; last heard: " .. tostring(now):sub(1, 160))
        phase = "gave up"
        return
      end
      press("down", 30)
    end
    function handlers.start()
      local now = lastSaid()
      local rows = { now }
      for _ = 1, 10 do
        if now:upper():find("NAV", 1, true) then break end
        now = press("down", 20)
        rows[#rows + 1] = now
      end
      U.log("MATCHCALL", "start menu heard:", table.concat(rows, " / "):sub(1, 400))
      if not now:upper():find("NAV", 1, true) then
        finding("menu", "POKeNAV was not read in the start menu; heard: " .. table.concat(rows, " / "):sub(-200))
        L.tap("b", 20)
        return
      end
      phase = "menu"
      L.tap("a", 40)
    end
    function handlers.any(_, k)
      if not tostring(k):find("pokenav") then L.tap("a", 10) return end
      local now, at = lastSaid()
      local upper = now:upper()
      if phase == "menu" then
        if upper:find("MATCH CALL, %d+ OF") then
          U.log("MATCHCALL", "menu:", now:sub(1, 200))
          moveOn("list")
        else
          another(now)
        end
      elseif phase == "list" then
        if upper:find("STONE", 1, true) then
          U.log("MATCHCALL", "list:", now:sub(1, 200))
          moveOn("options")
        else
          another(now)
        end
      elseif phase == "options" then
        if upper:find("^CALL") then
          U.log("MATCHCALL", "options:", now)
          moveOn("call")
        elseif upper:find("STONE", 1, true) then
          -- still the list's words: the A was taken before the list took input
          -- (r10, r11: upstream's handler stayed "list"); press A again, as a player would
          tries = tries + 1
          finding("pokenav", "Match Call list: A on MR. STONE did nothing the first time (the list was read before it took input)")
          U.log("MATCHCALL", "options: A again, try", tries)
          if tries > 12 then phase = "gave up" else L.tap("a", 10) wait(40) end
        else
          another(now)
        end
      elseif phase == "gave up" then
        -- the game will not let the lesson be left: end the stage here, with the log
        error("the Match Call lesson could not be finished by ear", 0)
      else
        -- the call, then out: B turns the call's pages and hangs up (A would hang up and
        -- then open MR. STONE's options again and call him a second time, r12), then
        -- leaves the list and the Pokénav
        tries = tries + 1
        if tries > 400 then
          finding("pokenav", "Match Call lesson: the Pokénav was not left after 400 presses of B; last heard: " .. now:sub(1, 160))
          phase = "gave up"
        elseif frame - at > 30 then
          U.log("MATCHCALL", "B; last heard:", now:sub(1, 160))
          L.tap("b", 30)
        else
          wait(1)
        end
      end
    end
    return handlers
  end

  -- Mr. Briney's cottage on Route 104 and the boat to Dewford.
  stage("dewford", function() return flag("FLAG_VISITED_DEWFORD_TOWN") end, function()
    local there = function() return onMap("DEWFORD_TOWN") and L.free() end
    local handlers = matchCallHandlers()
    local ok, why = travel("ROUTE104_MR_BRINEYS_HOUSE", { untilFn = there, handlers = handlers })
    if not ok and not there() then return false, tostring(why) .. " " .. gruntLine() end
    visit()
    if not there() then
      local m = mark()
      local talked, text, outcome = talkTo("npcs", "Briney", { calm = 150, limit = 40000, optional = true })
      if outcome == "missing" then
        -- r14: the list names him by his sheet, "Expert"; a player tries the one person
        finding("name", "Mr. Briney is listed as Expert in his cottage (" .. tostring(text):sub(1, 120) .. ")")
        -- he walks about the room: "Face right and interact" can be stale by the time it
        -- is acted on (r15: the step right moved the player instead), so try again
        for attempt = 1, 4 do
          talked, text, outcome = talkTo("npcs", "^Expert", { calm = 150, limit = 40000 })
          U.log("BRINEY", "try", attempt, tostring(talked), tostring(outcome))
          if talked or there() then break end
        end
        -- r16: four times the step said by the arrival moved the player instead (he had
        -- walked on).  Listen to the list again and act only when it says he is one step
        -- away, as a careful player would.
        for attempt = 1, 30 do
          if talked or there() then break end
          local item = choose("npcs", "^Expert")
          local way = tostring(item):match("^Expert: 1 (%a+);")
          if way == "up" or way == "down" or way == "left" or way == "right" then
            L.tap(way, 4)
            talked, text = interact({ calm = 150, limit = 40000, expectText = false })
            U.log("BRINEY", "adjacent try", attempt, way, tostring(talked))
          else
            wait(20)
            if attempt % 5 == 0 then go("npcs", "^Expert") end
          end
        end
      end
      U.log("BRINEY", "Mr. Briney:", tostring(talked), tostring(outcome), tostring(text):sub(-300))
      advance({ calm = 150, limit = 40000 })
      U.log("BRINEY", "everything heard:", since(m):sub(1, 2000))
    end
    advance({ calm = 90 })
    return onMap("DEWFORD_TOWN") or flag("FLAG_VISITED_DEWFORD_TOWN"), L.where() .. " " .. gruntLine()
  end)

  -- ------------------------------------------------------------ run
  local speed = tonumber(os.getenv("WALK_SPEED") or "")
  local stopAfter = os.getenv("WALK_STOP")
  local saveEach = os.getenv("WALK_SAVE") ~= "0"
  U.log("START", "rse_walkthrough", GameData.id(), "stop after", tostring(stopAfter), "walk speed", tostring(speed or "default"))
  for _, entry in ipairs(stages) do
    local inField = game.phase == "field"
    if continued and entry.done and entry.done() then
      U.log("STAGE", "skipped", entry.name, "(already done in this save)")
      results[#results + 1] = { name = entry.name, ok = true, detail = "done in the save continued from", frames = 0 }
    else
      U.log("STAGE", "begin", entry.name, "at", inField and L.where() or tostring(game.phase), "party", inField and partyLine() or "")
      if speed and inField then L.fastWalk(speed) end
      local began = frame
      local ok, okOrErr, detail = pcall(entry.run)
      if not ok then
        U.log("STAGE", "error", entry.name, tostring(okOrErr))
        results[#results + 1] = { name = entry.name, ok = false, detail = "driver error: " .. tostring(okOrErr), frames = frame - began }
        break
      end
      local reached = okOrErr == true
      if reached and entry.done and not entry.done() then
        reached = false
        detail = "its goal check does not hold: " .. tostring(detail)
      end
      results[#results + 1] = { name = entry.name, ok = reached, detail = tostring(detail), frames = frame - began }
      U.log("STAGE", reached and "reached" or "stopped", entry.name, tostring(detail), "frames", frame - began)
      if not reached then
        if game.phase == "field" and L.free() then
          U.log("STATE", stateLine(), "party", partyLine())
          readLists("where it stopped: " .. mapName())
        end
        break
      end
      if saveEach and entry.name ~= "boot" and entry.name ~= "truck" then
        local saved = saveGame()
        U.log("SAVE", "after", entry.name, saved and "saved" or "NOT saved")
      end
      if stopAfter == entry.name then break end
    end
  end
  local reachedCount = 0
  for _, row in ipairs(results) do
    if row.ok then reachedCount = reachedCount + 1 end
    U.log("TABLE", row.name, row.ok and "reached" or "stopped", row.detail, "frames", tostring(row.frames))
  end
  U.log("RESULT", "rse_walkthrough", GameData.id(), "stages reached", reachedCount, "of", #stages,
    "findings", findingCount, "battles", battles, "party", game.phase == "field" and partyLine() or "")
  Speech.say = say
  U.wait = rawWait
  U.log("DONE")
end
