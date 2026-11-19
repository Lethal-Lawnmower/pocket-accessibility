-- Ruby, Sapphire and Emerald played forward from the title screen, the way a blind
-- player has to: real button presses, the game's own menus and prompts, movement by
-- the object list and auto-walk through the bound commands (the controller's: hold the
-- left trigger, D-pad up and down for the category, left and right for the item, left
-- stick click to walk), battles through the battle menu.  No teleports, no flag or
-- variable writes, no gifted party, no healing by the harness: a weak party walks to a
-- Pokémon Center.  Every utterance is logged with the screen it came from.
--
--   FRESH=1                 start from clean game data (the runner's switch)
--   WALK_STOP=<stage>       stop after this stage
--   WALK_SPEED=<n>          AUTO-WALK SPEED (the game's own accessibility option); the
--                           default is the option's default
--   WALK_NAME=<letters>     the name typed on the naming screen (default ACE)
--   WALK_STARTER=<name>     TREECKO, TORCHIC or MUDKIP (default MUDKIP)
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
  local function watch()
    frame = frame + 1
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
  local preferMoves = { "MUD SHOT", "WATER GUN", "MUD-SLAP", "EMBER", "PECK", "ABSORB", "TACKLE", "SCRATCH", "POUND" }
  local function battleUi()
    local Ui = package.loaded["src.core.game3.battle.ui"]
    return Ui and Ui._mode or nil
  end
  -- The moves box is two by two: read each cell by moving the cursor round it, as a
  -- player does, then go on round to the best one heard.
  local function pickMove()
    local heardMoves = {}
    local here = since(math.max(0, #spoken - 1))
    local round = { "right", "down", "left", "up" }
    local best, bestRank, bestAt
    for index = 0, 3 do
      if index > 0 then here = press(round[index], 20) end
      if battleUi() ~= "moves" then return end
      if here ~= "" then
        heardMoves[#heardMoves + 1] = here
        local upper = here:upper()
        local empty = upper:find("PP 0 OF", 1, true) ~= nil
        for rank, name in ipairs(preferMoves) do
          if not empty and upper:find(name, 1, true) and (not bestRank or rank < bestRank) then
            best, bestRank, bestAt = here, rank, index
          end
        end
      end
    end
    if #heardMoves == 0 then finding("battle", "the move list opened and no move was read") end
    -- the cursor has gone right, down, left (three cells on); "up" closes the round
    if bestAt and bestAt ~= 3 then
      press("up", 20)
      for index = 1, bestAt do press(round[index], 20) end
    end
    U.log("MOVE", best or "(none preferred: the cell under the cursor)", "of", table.concat(heardMoves, " / "):sub(1, 300))
    L.tap("a", 12)
  end

  local warnedLayer
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
      if warnedLayer ~= k then warnedLayer = k U.log("BATTLE", "layer over the battle:", k) end
      L.tap("a", 12)
      return
    end
    if mode == "menu" then
      local said = since(math.max(0, #spoken - 3))
      if not said:upper():find("FIGHT", 1, true) then
        -- the cursor remembers; go to FIGHT (top left)
        press("up", 10) press("left", 10)
      end
      L.tap("a", 12)
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
      elseif k and opts.handlers and opts.handlers[k] then
        run = 0
        opts.handlers[k](top)
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
      if item:find(pattern) then return item, heardItems end
    end
    return nil, heardItems
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
    local item, heardItems = choose(category, pattern)
    if not item then
      local read = type(heardItems) == "table" and table.concat(heardItems, "; ") or tostring(heardItems)
      if opts.optional then return "missing", read end
      finding("target", ("nothing matching %q in %s at %s; the list read: %s"):format(pattern, category, L.where(), read))
      return "missing", ""
    end
    local m = mark()
    local from = L.where()
    Nav.gamepadpressed(nil, "leftstick")
    Nav.gamepadreleased(nil, "leftstick")
    wait(2)
    local frames = 0
    while anyWalk() and frames < (opts.limit or 20000) do
      frames = frames + 1
      if opts.untilFn and opts.untilFn() then break end
      local k, top = kind()
      if battleOn() then
        battleAct(opts.policy)
      elseif k == "choice" then
        answerChoice(opts.policy)
      elseif k == "message" and not AutoWalk.walking() then
        L.tap("a", 8)
      elseif k and k ~= "message" and opts.handlers and opts.handlers[k] then
        opts.handlers[k](top)
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

  -- ------------------------------------------------------------ stages
  local stages = {}
  local function stage(name, fn) stages[#stages + 1] = { name = name, run = fn } end
  local results = {}

  -- Title to the truck: the intro, the title, NEW GAME, Birch's speech, BOY, the name.
  stage("boot", function()
    for _ = 1, 1200 do
      if game.phase == "boot" and game.boot then break end
      wait(1)
    end
    if game.phase ~= "boot" then return false, "the game never reached its boot screens" end
    local wantName = (os.getenv("WALK_NAME") or "ACE"):upper()
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
        L.tap("a", 20)
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
    local s = L.session()
    local name = s and (s.playerName or (s.player and s.player.name) or s.name)
    U.log("BOOT", "in the field at", L.where(), "player name", tostring(name), "wanted", wantName)
    if name and tostring(name):upper() ~= wantName then finding("naming", "the name in the save is " .. tostring(name) .. ", typed " .. wantName) end
    return true, L.where()
  end)

  -- The truck: wait for it to stop, find the way out in the list, walk out; mother
  -- takes the player indoors.
  stage("truck", function()
    advance({ calm = 60, limit = 3000 })
    if not onMap("INSIDE_OF_TRUCK") then return onMap("LITTLEROOT_TOWN") or mapName():find("HOUSE") ~= nil, L.where() end
    readLists("truck")
    local outcome, said = go("warps", ".", { untilFn = function() return not onMap("INSIDE_OF_TRUCK") end })
    advance({ calm = 90, limit = 6000 })
    local ok = mapName():find("LITTLEROOT_TOWN_.*HOUSE_1F") ~= nil
    return ok, L.where() .. " after " .. outcome .. ": " .. said:sub(-120)
  end)

  -- ------------------------------------------------------------ run
  local speed = tonumber(os.getenv("WALK_SPEED") or "")
  local stopAfter = os.getenv("WALK_STOP")
  U.log("START", "rse_walkthrough", GameData.id(), "stop after", tostring(stopAfter), "walk speed", tostring(speed or "default"))
  for _, entry in ipairs(stages) do
    local inField = game.phase == "field"
    U.log("STAGE", "begin", entry.name, "at", inField and L.where() or tostring(game.phase), "party", inField and partyLine() or "")
    if speed and inField then L.fastWalk(speed) end
    local began = frame
    local ok, okOrErr, detail = pcall(entry.run)
    if not ok then
      U.log("STAGE", "error", entry.name, tostring(okOrErr))
      results[#results + 1] = { name = entry.name, ok = false, detail = "driver error: " .. tostring(okOrErr), frames = frame - began }
      break
    end
    results[#results + 1] = { name = entry.name, ok = okOrErr == true, detail = tostring(detail), frames = frame - began }
    U.log("STAGE", okOrErr == true and "reached" or "stopped", entry.name, tostring(detail), "frames", frame - began)
    if okOrErr ~= true then break end
    if stopAfter == entry.name then break end
  end
  local reached = 0
  for _, row in ipairs(results) do
    if row.ok then reached = reached + 1 end
    U.log("TABLE", row.name, row.ok and "reached" or "stopped", row.detail, "frames", tostring(row.frames))
  end
  U.log("RESULT", "rse_walkthrough", GameData.id(), "stages reached", reached, "of", #stages,
    "findings", findingCount, "battles", battles, "party", game.phase == "field" and partyLine() or "")
  Speech.say = say
  U.wait = rawWait
  U.log("DONE")
  -- keep the unused helpers referenced until their stages exist
  local _ = { flag, var, lead, talkTo, interact }
end
