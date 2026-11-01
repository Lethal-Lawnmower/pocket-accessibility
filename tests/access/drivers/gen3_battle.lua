-- Gen 3 battle speech, scripted (FireRed; decision 29).  Plays real battles
-- on the imported cartridge data and logs every screen change, battle phase
-- and UI mode, every page the message box shows (SHOWN, checked once per
-- logic step) and every utterance (SAID), so the trace shows what the Gen 3
-- battle presenter says and whether any shown line went unsaid:
--
--   wild     a wild PIDGEY: the menu cursor round the grid, the move list
--            with a SELECT swap cancelled, GROWL, then POKé BALLs until it
--            is caught, the Pokédex page, the nickname question (NO);
--   level    a four-move CHARMANDER one point short of level 13 knocks out
--            a RATTATA: EXP, the two-page level-up window, METAL CLAW with
--            "delete a move?" NO and "stop learning?" YES;
--   trainer  a trainer with two Pokémon, battle style SHIFT: the shift
--            offer (NO), the second send-out, the win and prize money;
--   run      a wild battle run from;
--   safari   a Safari Zone battle: ROCK, BAIT, then RUN;
--   oldman   the old man's catching demo in Viridian City;
--   doubles  TWINS ELI & ANNE: four sides, both battlers' menus, targets;
--   fast     (only when asked for) a wild battle at POKEPORT_BATTLE_FAST
--            logic steps per frame (default 200), BATTLE SCENE off,
--            pressing no faster than a person could.
--
-- POKEPORT_BATTLE_SCENES=wild,level,... picks scenes (default: all but
-- fast).  POKEPORT_BATTLE_WHOLE=1 sets DIALOGUE SPEECH to ALL AT ONCE.
-- Each scene ends with "TALLY <scene> shown=N missed=M": a page the box
-- showed during the battle (no menu layer open) that does not appear, in
-- order, in what was said.  Run silently, isolated, with a disposable
-- identity:
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_BACKGROUND=1 POKEPORT_ACCESS_TRACE=1
--   POKEPORT_TOUCH=0 POKEPORT_IDENTITY=pocket-access-battle-firered
--   POKEPORT_VERSION=firered POKEPORT_GAME=firered
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/gen3_battle.lua
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Speech = require("src.access.Speech")
  local ScreenReader = require("src.access.screens.ScreenReader")
  local Top = require("src.access.screens.gen3.Top")
  local G3Common = require("src.access.screens.gen3.Common")
  local Gen2Common = require("src.access.screens.gen2.Common")
  local Presenters = require("src.access.screens.Presenters")

  local scenesEnv = os.getenv("POKEPORT_BATTLE_SCENES")
  local wanted = {}
  for name in (scenesEnv or "wild,level,trainer,run,safari,oldman,doubles"):gmatch("[^,]+") do
    wanted[name] = true
  end

  -- ------------------------------------------------------------ the trace

  local saidStream = {}
  local say = Speech.say
  Speech.say = function(text, opts)
    local line = tostring(text)
    saidStream[#saidStream + 1] = line
    U.log("SAID", (opts and opts.interrupt) and "!" or "-", line)
    return say(text, opts)
  end

  local polls, srUpdate = 0, ScreenReader.update
  ScreenReader.update = function(...) polls = polls + 1 return srUpdate(...) end

  local function clean(page)
    local lines = G3Common.lines(page)
    if #lines == 0 then return "" end
    -- as the presenter says "LV. 13"
    return (Gen2Common.speakable(Presenters.joinLines(lines)):gsub("%f[%w]LV%. ?(%d)", "level %1"))
  end

  local shownList = {}
  local lastPages, lastPage, lastPhase, lastMode, lastTop
  local function watch()
    local Battle = package.loaded["src.core.game3.battle"]
    local Ui = package.loaded["src.core.game3.battle.ui"]
    local Message = package.loaded["src.ui.game3.message"]
    local Stack = package.loaded["src.ui.game3.stack"]
    local active = Battle and Battle.isActive and Battle.isActive()
    if Message and Message.open and type(Message._pages) == "table" then
      if Message._pages ~= lastPages or Message._page ~= lastPage then
        lastPages, lastPage = Message._pages, Message._page
        local text = clean(Message._pages[Message._page] or "")
        U.log("SHOWN", text)
        local covered = Stack and Stack.top and Stack.top() ~= nil
        if active and not covered and text ~= "" then shownList[#shownList + 1] = text end
      end
    else
      lastPages = nil
    end
    local phase = active and Battle._phase or nil
    local mode = active and Ui and Ui._mode or nil
    if phase ~= lastPhase or mode ~= lastMode then
      if phase then U.log("PHASE", phase, mode) end
      lastPhase, lastMode = phase, mode
    end
    local top = Top.resolve(game)
    local name = top and (top.gen3 .. (top.layer and (":" .. tostring(top.layer.id)) or "")) or "none"
    if name ~= lastTop then U.log("TOP", name) lastTop = name end
  end
  local function wait(n) for _ = 1, n or 1 do U.wait(1) watch() end end

  -- A person cannot press twice within one rendered frame: under
  -- fast-forward, wait for two screen-reader polls before each press.
  local function humanPace()
    if not game.driverSpeed or game.driverSpeed <= 1 then return end
    local start = polls
    for _ = 1, 4000 do
      if polls >= start + 2 then return end
      wait(1)
    end
  end
  local function tap(button, frames)
    humanPace()
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    wait(2)
    game.input.state[button] = false
    wait(frames or 10)
  end

  local function tally(scene, from, saidFrom)
    local said = table.concat(saidStream, " ", saidFrom)
    local pos, missed = 1, 0
    for i = from, #shownList do
      local at = said:find(shownList[i], pos, true)
      if at then
        pos = at + #shownList[i]
      else
        missed = missed + 1
        U.log("MISSED", shownList[i])
      end
    end
    U.log("TALLY", scene, "shown=" .. (#shownList - from + 1), "missed=" .. missed)
  end

  -- ------------------------------------------------------------ the game

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    wait(1)
  end
  local ok, err = pcall(function() game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 }) end)
  if not ok then U.log("FAIL", "new game: " .. tostring(err)) return end
  wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Options = require("src.core.game3.options")
  local Experience = require("src.core.game3.battle.experience")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Stack = require("src.ui.game3.stack")
  local StatGrowth = require("src.ui.game3.stat_growth")
  local session = Runtime.getSession()
  if not session then U.log("FAIL", "no session") return end
  if os.getenv("POKEPORT_BATTLE_WHOLE") == "1" then game.options.accessDialogue = "whole" end
  -- POKEPORT_BATTLE_NORECORDER=1 measures the presenter without its
  -- Message.show recorder (only before the first battle installs it)
  if os.getenv("POKEPORT_BATTLE_NORECORDER") == "1" then
    local Gen3Battle = require("src.access.screens.gen3.Battle")
    if Gen3Battle._recorder.module == nil then
      Gen3Battle._recorder.install = function() return false end
      U.log("RECORDER", "off")
    end
  end

  -- talk through anything the new game opened
  for _ = 1, 60 do
    if not Message.isOpen() then break end
    tap("a", 20)
  end

  local function inBattle() return Battle.isActive() end
  local function atMenu() return inBattle() and Battle._phase == "command" and Ui._mode == "menu" end
  local function boxWaits()
    if not (Message.isOpen() and Message.isWaiting()) or Message.isHeld() then return false end
    return not Message._stay or (Message._page or 1) < #(Message._pages or {})
  end
  local function interrupted()
    return atMenu() or not inBattle() or Choice.active or Stack.top() ~= nil or StatGrowth.isOpen()
  end
  -- Presses A on boxes that wait for it, after a moment's reading.
  local function advance(stop, limit)
    local waited = 0
    for _ = 1, limit or 6000 do
      if stop() then return true end
      if boxWaits() then waited = waited + 1 else waited = 0 end
      if waited >= 24 then
        tap("a", 4)
        waited = 0
      else
        wait(1)
      end
    end
    return stop()
  end

  local function party(list)
    session.party = {}
    for _, row in ipairs(list) do Party.giveMon(session, row[1], row[2]) end
    return session.party
  end

  local function startWild(encounter, opts)
    opts = opts or {}
    opts.fade = false
    local started, why = BattleBridge.startWild(Runtime._mod, game, encounter, opts)
    if not started then U.log("FAIL", "wild battle: " .. tostring(why)) return false end
    for _ = 1, 600 do
      if inBattle() then return true end
      wait(1)
    end
    return inBattle()
  end

  local function menuTo(index)
    for _ = 1, 4 do
      local c = (Ui._menuIndex or 1) - 1
      local want = index - 1
      if c == want then break end
      if c % 2 ~= want % 2 then tap(c % 2 == 0 and "right" or "left", 12)
      else tap(c < 2 and "down" or "up", 12) end
    end
  end
  local function command(index)
    menuTo(index)
    tap("a", 20)
  end
  local function moveTo(index)
    for _ = 1, 4 do
      local c = (Ui._moveIndex or 1) - 1
      local want = index - 1
      if c == want then break end
      if c % 2 ~= want % 2 then tap(c % 2 == 0 and "right" or "left", 12)
      else tap(c < 2 and "down" or "up", 12) end
    end
  end
  -- The first move with power, else slot 1.
  local function attackSlot()
    local Moves = require("src.core.game3.battle.moves")
    local b = Ui.activeBattlerObject and Ui.activeBattlerObject() or nil
    local mon = b and b.mon
    for i = 1, 4 do
      local mv = mon and mon.moves and mon.moves[i]
      if mv and mv ~= 0 then
        local okM, def = pcall(Moves.get, mv)
        if okM and def and (tonumber(def.power) or 0) > 0 then return i end
      end
    end
    return 1
  end
  local function fight(slot)
    command(1)
    if Ui._mode ~= "moves" then return end
    moveTo(slot or attackSlot())
    tap("a", 20)
    -- a double battle may ask for a target: move the cursor once, then A
    if Ui._mode == "target" then
      tap("right", 16)
      tap("a", 20)
    end
  end
  local function health()
    local Gen3Battle = require("src.access.screens.gen3.Battle")
    U.log("HEALTH", tostring(Gen3Battle.health(nil, "enemy")), "|", tostring(Gen3Battle.health(nil, "player")))
  end
  local function answer(yes)
    wait(30)
    if (Choice.cursor == 1) ~= yes then tap("down", 16) end
    tap("a", 20)
  end
  local function throwBall()
    -- the bag is a menu layer read by its own presenter; throw as the
    -- upstream catch drivers do
    Ui._pendingCommand = { kind = "bag", itemId = 4, user = "player" }
    Ui._mode = "none"
    wait(2)
  end

  -- Runs the battle on until the menu or its end, handling what comes up.
  -- `onChoice(n)` answers the n-th question (YES/NO), default NO.
  local function settle(opts)
    opts = opts or {}
    local questions = 0
    for _ = 1, 60 do
      advance(interrupted, opts.limit)
      if atMenu() or not inBattle() then return end
      if StatGrowth.isOpen() then
        wait(40) tap("a", 40) tap("a", 30)
      elseif Choice.active then
        questions = questions + 1
        local yes = opts.onChoice and opts.onChoice(questions, Message.isOpen() and Message.currentPage() or "")
        answer(yes == true)
      elseif Stack.top() then
        local id = Stack.top().id
        U.log("LAYER", id)
        if id == "party" then
          local PM = package.loaded["src.ui.game3.party_menu"]
          wait(30)
          if PM then PM.cursor = 2 end
          tap("a", 20) tap("a", 30)
        else
          for _ = 1, 30 do
            if Stack.top() == nil or Stack.top().id ~= id then break end
            tap(id == "naming" and "b" or "a", 20)
          end
          if Stack.top() and Stack.top().id == id then tap("b", 20) end
        end
      end
    end
  end

  local function finish(scene, shownFrom, saidFrom)
    for _ = 1, 30 do
      if not inBattle() then break end
      settle()
      if atMenu() then fight() end
    end
    wait(60)
    tally(scene, shownFrom, saidFrom)
    -- the field may talk after a battle (whiteout, trainer text)
    for _ = 1, 30 do
      if not Message.isOpen() then break end
      tap("a", 20)
    end
    wait(30)
  end

  local function scene(name, fn)
    if not wanted[name] then return end
    U.log("SCENE", name)
    local shownFrom, saidFrom = #shownList + 1, #saidStream + 1
    local okScene, errScene = pcall(fn)
    if not okScene then U.log("FAIL", name .. ": " .. tostring(errScene)) end
    finish(name, shownFrom, saidFrom)
  end

  -- ------------------------------------------------------------ scenes

  scene("wild", function()
    party({ { 4, 12 } })
    Bag.add(session.bag, 4, 20)
    if not startWild({ species = 16, level = 3 }) then return end
    settle()
    health()
    -- round the grid, then FIGHT
    tap("right", 16) tap("down", 16) tap("left", 16) tap("up", 16)
    tap("a", 20)
    -- the move list, a SELECT swap begun and cancelled, back, then GROWL
    tap("right", 16) tap("down", 16)
    tap("select", 16) tap("up", 16) tap("b", 16)
    tap("b", 20)
    fight(2)
    settle()
    for _ = 1, 12 do
      if not atMenu() then break end
      throwBall()
      settle({ onChoice = function() return false end })
    end
  end)

  scene("level", function()
    local mons = party({ { 4, 12 } })
    local mon = mons[1]
    mon.moves = { 10, 45, 52, 43 }
    mon.pp = { 35, 40, 25, 30 }
    mon.maxPp = { 35, 40, 25, 30 }
    mon.exp = Experience.expForLevel(mon, 13) - 1
    if not startWild({ species = 19, level = 2 }) then return end
    settle()
    fight(1)
    -- "delete a move?" NO, then "stop learning?" YES
    settle({ onChoice = function(n, question)
      U.log("QUESTION", n, question)
      return n >= 2
    end })
  end)

  scene("trainer", function()
    party({ { 4, 25 }, { 7, 20 } })
    Options.ensure(session).battleStyle = 0
    local started, why = BattleBridge.start(Runtime._mod, game,
      { trainerId = 326, party = { { species = 16, level = 5 }, { species = 19, level = 5 } } },
      { wild = false, trainerId = 326, fade = false })
    if not started then U.log("FAIL", "trainer battle: " .. tostring(why)) return end
    for _ = 1, 600 do if inBattle() then break end wait(1) end
    settle()
    for _ = 1, 10 do
      if not inBattle() then break end
      if atMenu() then fight() end
      settle({ onChoice = function() return false end })
    end
  end)

  scene("run", function()
    party({ { 4, 25 } })
    if not startWild({ species = 19, level = 2 }) then return end
    settle()
    for _ = 1, 6 do
      if not atMenu() then break end
      command(4)
      settle()
    end
  end)

  scene("safari", function()
    party({ { 4, 25 } })
    local Rules = require("src.core.game3.battle.rules")
    session.safari = { active = true, balls = Rules.safari.BALLS, steps = Rules.safari.STEPS }
    if not startWild({ species = 111, level = 25 }, { safari = true }) then return end
    settle()
    health()
    command(3) -- ROCK
    settle()
    if atMenu() then command(2) settle() end -- BAIT
    for _ = 1, 6 do
      if not atMenu() then break end
      command(4) -- RUN
      settle()
    end
    session.safari = nil
  end)

  scene("oldman", function()
    party({ { 4, 12 } })
    if not startWild({ species = 13, level = 5, gender = "M", oldManTutorial = true },
        { oldManTutorial = true }) then return end
    -- the demo drives its own menu and bag; only the boxes need A
    for _ = 1, 40 do
      if not inBattle() then break end
      advance(function() return not inBattle() or Choice.active or Stack.top() ~= nil end, 3000)
      if Choice.active then answer(false) end
      if Stack.top() then wait(60) end
    end
  end)

  scene("doubles", function()
    party({ { 2, 30 }, { 8, 30 } })
    local started, why = BattleBridge.start(Runtime._mod, game,
      { trainerId = 484, party = { { species = 19, level = 8 }, { species = 16, level = 8 } } },
      { wild = false, trainerId = 484, double = true, fade = false })
    if not started then U.log("FAIL", "double battle: " .. tostring(why)) return end
    for _ = 1, 600 do if inBattle() then break end wait(1) end
    settle()
    health()
    -- the first battler chooses, the partner backs out to it with B
    wait(40)
    fight()
    for _ = 1, 200 do if atMenu() and Ui._active ~= 0 then break end wait(1) end
    U.log("PARTNER", tostring(Ui._active), tostring(Ui._mode))
    if atMenu() and Ui._active ~= 0 then
      tap("b", 30)
      U.log("PARTNER", "after B", tostring(Ui._active), tostring(Ui._mode))
    end
    for _ = 1, 30 do
      if not inBattle() then break end
      if atMenu() then fight() end
      settle({ onChoice = function() return false end })
    end
  end)

  -- A trainer with two Pokémon fought with SCRATCH, so the trace has many
  -- self-advancing lines (moves, damage, send-outs, faints).
  scene("fast", function()
    party({ { 4, 16 } })
    Options.ensure(session).battleScene = 1
    Options.ensure(session).battleStyle = 0
    local speed = tonumber(os.getenv("POKEPORT_BATTLE_FAST")) or 200
    game.driverSpeed = speed
    U.log("SPEED", speed)
    local started, why = BattleBridge.start(Runtime._mod, game,
      { trainerId = 326, party = { { species = 16, level = 11 }, { species = 19, level = 11 } } },
      { wild = false, trainerId = 326, fade = false })
    if not started then U.log("FAIL", "fast battle: " .. tostring(why)) return end
    for _ = 1, 600 do if inBattle() then break end wait(1) end
    settle()
    health()
    for _ = 1, 20 do
      if not inBattle() then break end
      if atMenu() then fight(1) end
      settle({ onChoice = function() return false end })
    end
  end)
  game.driverSpeed = nil

  wait(30)
  Speech.say = say
  ScreenReader.update = srUpdate
  U.log("DONE")
  love.event.quit()
end
