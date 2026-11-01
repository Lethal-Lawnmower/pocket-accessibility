-- Gen 2 menu screens, scripted: boot cards and title, main menu and OPTION
-- (our ACCESSIBILITY page and a built-in group page), a new game (gender in
-- Crystal, Oak's clock, name choice, naming keyboard), the start menu, SAVE
-- twice (new file, then overwrite), QUIT's confirm, Mom's day wheel, a
-- vending machine (script menu with the money box), an elevator, the Bank of
-- Mom (first visit, then a deposit on the keypad), the yes/no re-show
-- fallback, an evolution stopped with B and one that completes, and an egg
-- hatching with its nickname.
--
-- Logs every screen change and utterance ("SCREEN", "SAID"); with
-- POKEPORT_ACCESS_TRACE=1 every utterance is also printed as `say!:`
-- (interrupting) or `say:` (queued).  It asserts nothing about wording.
-- Run silently with a disposable identity:
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_BACKGROUND=1 POKEPORT_ACCESS_TRACE=1
--   POKEPORT_TOUCH=0 POKEPORT_IDENTITY=<id> POKEPORT_VERSION=<game>
--   POKEPORT_GAME=<game> POKEPORT_BOOT_CINEMA=1
--   POKEPORT_DRIVER=tests/access/drivers/gen2_menus.lua
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Speech = require("src.access.Speech")

  local function className(state)
    if state == nil then return "overworld" end
    local mt = getmetatable(state)
    for name, mod in pairs(package.loaded) do
      if mod == mt and type(name) == "string" then return (name:gsub("^src%.ui%.", "")) end
    end
    return tostring(mt)
  end

  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts)
    said[#said + 1] = ((opts and opts.interrupt) and "! " or "  ") .. tostring(text)
    return say(text, opts)
  end
  local lastTop
  local function watch()
    local name = className(game.stack:top())
    if name ~= lastTop then
      U.log("SCREEN", name)
      lastTop = name
    end
    for _, line in ipairs(said) do U.log("SAID", line) end
    said = {}
  end
  local function wait(n) for _ = 1, n do U.wait(1) watch() end end
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    wait(2)
    game.input.state[button] = false
    wait(frames or 8)
  end
  local function top() return game.stack:top() end
  local function topIs(name) return className(top()) == name end
  local function step(name) U.log("STEP", name) end
  local function waitFor(names, limit)
    for _ = 1, limit or 600 do
      local now = className(top())
      for _, name in ipairs(names) do if now == name then return top() end end
      wait(1)
    end
    return nil
  end
  -- wait until the screen's own typer has finished its page
  local function settle(state, limit)
    for _ = 1, limit or 300 do
      local typer = state and state.typer
      if not typer or typer:done() then break end
      wait(1)
    end
    wait(4)
  end
  local function inWorld()
    return game.phase == "play" and game.world and game.world.map and top() == nil
  end
  -- A through dialogue; B on yes/no boxes only when asked
  local function through(limit, onTop)
    for _ = 1, limit or 300 do
      if inWorld() then return true end
      if onTop and onTop(top()) then return true end
      tap("a", 10)
    end
    return inWorld()
  end
  local function moveListTo(list, value)
    for _ = 1, #(list.items or {}) + 1 do
      local item = list.items[list.index]
      if item and item.value == value then return true end
      tap("down", 10)
    end
    return false
  end

  -- ------------------------------------------------------------- boot
  step("boot: copyright, GAME FREAK, intro, title")
  waitFor({ "gen2.GoldSilverIntro", "gen2.CrystalIntro", "gen2.TitleState" }, 1200)
  wait(120)
  if not topIs("gen2.TitleState") then tap("start", 10) end
  waitFor({ "gen2.TitleState" }, 600)
  wait(120)
  tap("start", 40)
  if not waitFor({ "gen2.MainMenu" }, 300) then U.log("FAIL", "no main menu") return end
  wait(30)

  -- ------------------------------------------------------------- main menu, OPTION
  step("main menu and OPTION")
  tap("down", 15)
  tap("up", 15)
  local hasContinue = false
  for _, item in ipairs(top().list.items) do if item.value == "continue" then hasContinue = true end end
  if hasContinue then
    moveListTo(top().list, "continue")
    tap("a", 40) -- the save panel
    tap("b", 20) -- back to the menu
  end
  moveListTo(top().list, "option")
  tap("a", 40)
  if waitFor({ "gen2.OptionsMenu" }, 120) then
    tap("down", 12) tap("down", 12) tap("up", 12) tap("up", 12)
    tap("a", 30) -- ACCESSIBILITY page
    tap("down", 12)
    tap("right", 12) tap("left", 12) -- DIALOGUE SPEECH there and back
    tap("b", 30)
    tap("down", 12) -- SPEED
    tap("a", 30)
    tap("right", 12) tap("left", 12) -- TEXT SPEED there and back
    tap("b", 30)
    tap("b", 40)
  end
  if not waitFor({ "gen2.MainMenu" }, 300) then U.log("FAIL", "no main menu after OPTION") return end
  wait(20)
  moveListTo(top().list, "new")
  tap("a", 30)

  -- ------------------------------------------------------------- new game
  step("new game")
  local first = waitFor({ "gen2.GenderSelect", "gen2.InitClock" }, 600)
  if className(first) == "gen2.GenderSelect" then
    for _ = 1, 400 do if first:menuOpen() then break end wait(1) end
    wait(20)
    tap("down", 15) tap("up", 15)
    tap("a", 30)
  end
  local clock = waitFor({ "gen2.InitClock" }, 600)
  if not clock then U.log("FAIL", "no clock screen") return end
  for _ = 1, 300 do if not clock.blank and not clock.fade then break end wait(1) end
  wait(10)
  for _ = 1, 6 do
    if clock.phase ~= "intro" then break end
    settle(clock) tap("a", 10)
  end
  settle(clock)
  tap("up", 15) -- hour + 1
  tap("a", 10) settle(clock) -- confirm-hour
  tap("down", 15) tap("a", 10) settle(clock) -- NO: back to the hour
  tap("a", 10) settle(clock) tap("a", 10) settle(clock) -- confirm, YES: minutes
  tap("up", 15) tap("up", 15)
  tap("a", 10) settle(clock) tap("a", 10) settle(clock) -- confirm, YES: response
  tap("a", 30)

  step("Oak, name choice, naming keyboard")
  for _ = 1, 4000 do
    if topIs("gen2.NamePick") then break end
    -- dialogue boxes, and the clock's last (scrolled) response page
    if topIs("src.render.TextBox") or topIs("gen2.InitClock") then tap("a", 10) else wait(1) end
  end
  local pick = top()
  if className(pick) ~= "gen2.NamePick" then U.log("NOTE", "no name menu; top", className(pick)) end
  if className(pick) == "gen2.NamePick" then
    for _ = 1, 200 do if pick.slide == nil then break end wait(1) end
    wait(20)
    tap("down", 15) tap("down", 15) tap("up", 15) tap("up", 15)
    tap("a", 30)
  end
  local naming = waitFor({ "gen2.NamingScreen" }, 120)
  if naming then
    wait(20)
    tap("a", 12) -- A
    tap("right", 12) tap("a", 12) -- B
    tap("down", 12) tap("down", 12) tap("down", 12) -- symbol row
    tap("a", 12) -- a symbol
    tap("b", 12) -- delete it
    tap("up", 12) tap("up", 12) tap("up", 12)
    tap("select", 12) -- lower case
    tap("a", 12)
    tap("start", 12) -- cursor to END
    tap("a", 30)
  end
  if not through(800) then U.log("FAIL", "never reached the overworld; top", className(top())) return end
  U.log("MAP", game.world.map.id)
  wait(60)

  -- ------------------------------------------------------------- start menu, SAVE, QUIT
  step("start menu")
  local StartMenu = require("src.ui.gen2.StartMenu")
  StartMenu.lastIndex = 1
  -- the start menu, opened from the world (START until it is up)
  local function openStart()
    for _ = 1, 6 do
      if topIs("gen2.StartMenu") then return top() end
      if inWorld() then tap("start", 30) else tap("b", 20) end
    end
    return waitFor({ "gen2.StartMenu" }, 60)
  end
  -- SAVE from the start menu, answered YES to every question (save, then
  -- overwrite when a file exists), each page read before the next press
  local function saveGame(toggle)
    local start = openStart()
    if not start then U.log("NOTE", "no start menu for SAVE") return end
    moveListTo(start.list, "save")
    tap("a", 30)
    local saving = waitFor({ "gen2.SaveMenu" }, 120)
    if not saving then U.log("NOTE", "no save screen") return end
    for _ = 1, 600 do
      if not topIs("gen2.SaveMenu") then break end
      local typed = saving.typedPhase == saving.phase and saving.typer and saving.typer:done()
      if saving.phase == "saving" or saving.phase == "done" or not typed then
        wait(1)
      elseif saving:yesNoVisible() then
        wait(10)
        if toggle then tap("down", 15) tap("up", 15) toggle = false end
        tap("a", 10)
      else
        wait(10) tap("a", 10) -- next page of the question
      end
    end
    wait(30)
  end
  local start = openStart()
  if start then
    tap("down", 12) tap("down", 12) tap("up", 12)
    moveListTo(start.list, "option")
    tap("a", 60)
    if waitFor({ "gen2.OptionsMenu" }, 120) then tap("down", 12) tap("b", 60) end
    waitFor({ "gen2.StartMenu" }, 120)
    wait(20)
  end
  step("SAVE, first time in this run")
  saveGame(true)
  step("SAVE again, overwriting")
  saveGame(false)
  start = openStart()
  if start then
    step("QUIT, answered NO")
    moveListTo(start.list, "quit")
    tap("a", 10)
    settle(start)
    tap("down", 15) tap("up", 15)
    tap("a", 20)
    tap("b", 30)
  end
  for _ = 1, 6 do if inWorld() then break end tap("b", 20) end

  -- ------------------------------------------------------------- Mom and the day wheel
  step("Mom's day wheel")
  local world = game.world
  world:setMap("PLAYERS_HOUSE_1F", 7, 3, "down")
  wait(30)
  for _ = 1, 3 do tap("down", 10) end
  wait(30)
  local wheel
  for _ = 1, 300 do
    local t = top()
    if t and t.mode == "day" and className(t) == "gen2.InitClock" then wheel = t break end
    tap("a", 6)
  end
  if wheel then
    settle(wheel) wait(10)
    tap("up", 15) tap("up", 15)
    tap("a", 15) tap("a", 20) -- confirm, YES
  else
    U.log("NOTE", "no day wheel reached")
  end
  through(400)
  wait(30)

  -- ------------------------------------------------------------- vending machine
  local vm = game.world.vm
  -- A through dialogue until `name` is on top; nil if it never comes
  local function untilTop(name, limit)
    for _ = 1, limit or 400 do
      if topIs(name) then return top() end
      if top() ~= nil then tap("a", 10) else wait(1) end
    end
    return nil
  end
  -- the script has ended and the world is back
  local function idle(limit)
    for _ = 1, limit or 400 do
      if inWorld() and not vm.busy then return true end
      if top() ~= nil then tap("a", 10) else wait(1) end
    end
    U.log("NOTE", "script still running; top", className(top()))
    return false
  end
  local function findScript(pred)
    local keys = {}
    for key, ops in pairs(vm.scripts or {}) do
      if type(ops) == "table" and pred(ops) then keys[#keys + 1] = tostring(key) end
    end
    table.sort(keys)
    return keys[1]
  end
  step("vending machine (script menu with a money box)")
  local vend = findScript(function(ops)
    local special = false
    for _, op in ipairs(ops) do
      if op.op == "special" then special = true end
      if op.op == "loadmenu" and special and op.menu and op.menu.items and #op.menu.items == 4 then return true end
    end
    return false
  end)
  idle() -- Mom's scene can still be walking after its last box
  if not vend then
    U.log("NOTE", "no vending script found")
  elseif vm:start(vend) then
    -- the machine's menu comes back after every purchase; B (cancel) ends it
    if untilTop("gen2.ScriptMenu") then
      wait(10) tap("down", 15) tap("down", 15) tap("b", 20)
    end
    idle()
  else
    U.log("NOTE", "vending script did not start")
  end
  wait(20)

  -- ------------------------------------------------------------- elevator
  step("elevator")
  local elevatorKey, floors = nil, nil
  for key, ops in pairs(vm.scripts or {}) do
    if type(ops) == "table" then
      for _, op in ipairs(ops) do
        if op.op == "elevator" and type(op.floors) == "table" and not elevatorKey then
          elevatorKey, floors = key, op.floors
        end
      end
    end
  end
  if not floors then
    for key, ops in pairs(vm.scripts or {}) do
      if type(ops) == "table" then
        for _, op in ipairs(ops) do
          if op.op == "elevator" and not elevatorKey then
            elevatorKey = key
            for _, v in pairs(op) do if type(v) == "table" and v[1] and v[1].destMap then floors = v end end
          end
        end
      end
    end
  end
  if elevatorKey and floors and floors[2] then
    -- Elevator's .FindCurrentFloor needs the floor the player came from
    world.backupMapId = floors[2].destMap
    if vm:start(elevatorKey) then
      if untilTop("gen2.ElevatorMenu", 200) then
        wait(10) tap("down", 15) tap("down", 15) tap("up", 15) tap("b", 20)
      end
      idle()
    else
      U.log("NOTE", "elevator script did not start")
    end
  else
    U.log("NOTE", "no elevator script found")
  end
  wait(20)

  -- ------------------------------------------------------------- Bank of Mom
  step("Bank of Mom")
  local bankId
  local order = vm.specialOrder or (world.constants and world.constants.specialOrder) or {}
  for i, name in ipairs(order) do if name == "BankOfMom" then bankId = i - 1 end end
  local function bank()
    return vm:start({ { op = "opentext" }, { op = "special", id = bankId }, { op = "closetext" }, { op = "end" } })
  end
  if not bankId then
    U.log("NOTE", "no BankOfMom special")
  elseif not bank() then
    U.log("NOTE", "BankOfMom script did not start")
  else
    idle() -- first visit: Mom offers to save, A answers YES
    wait(20)
    if bank() then
      if untilTop("gen2.ScriptMenu") then
        wait(10)
        tap("down", 15) -- SAVE
        tap("a", 20)
        local pad = untilTop("gen2.BankOfMom", 100)
        if pad then
          wait(10)
          tap("up", 12) -- 1
          tap("left", 12) tap("left", 12) -- hundreds
          tap("up", 12) -- 101
          tap("a", 20)
        end
      end
      idle()
    end
  end
  wait(20)

  -- ------------------------------------------------------------- yes/no re-show
  step("yes/no fallback: showText, then askYesNo (the field-move prompt path)")
  world:showText("Would you like to\ntest the prompt?", function()
    world:askYesNo(function() end)
  end)
  wait(60)
  tap("a", 30) -- closes the question; the fallback re-shows it with YES/NO
  wait(30)
  if topIs("ChoiceBox") then tap("b", 30) end
  through(60)
  wait(20)

  -- ------------------------------------------------------------- evolution
  local Mon = require("src.battle.gen2.Mon")
  local Evolution = require("src.core.gen2.Evolution")
  local EvolutionAnim = require("src.ui.gen2.EvolutionAnim")
  local Palettes = require("src.world.gen2.Palettes")
  local function evolve(species, level, cancel)
    local mon = Mon.new(game.data, species, level)
    local entry = mon and Evolution.checkMon(game.data, mon, { timeOfDay = Palettes.clockDaytime() })
    if not entry then U.log("NOTE", "no evolution for", species) return end
    game.save.party = { mon }
    local finished
    local screen = EvolutionAnim.new(game, { mon = mon, entry = entry, index = 1,
      party = game.save.party, save = game.save, onDone = function(result) finished = result end })
    game.stack:push(screen)
    for _ = 1, 3000 do
      if finished and top() == nil then break end
      local now = className(top())
      if now == "gen2.EvolutionAnim" then
        if cancel and screen.phase == "flash" then tap("b", 10) else wait(1) end
      elseif now == "ChoiceBox" or now == "gen2.MoveDeleter" then
        tap("b", 10)
      elseif top() ~= nil then
        tap("a", 10)
      else
        wait(1)
      end
    end
  end
  step("evolution stopped with B")
  evolve("CHIKORITA", 16, true)
  wait(30)
  step("evolution completed")
  evolve("CYNDAQUIL", 16, false)
  wait(30)

  -- ------------------------------------------------------------- egg hatching
  step("egg hatching and nickname")
  if world:giveEgg(152, 5) then
    game.save.party[#game.save.party].eggSteps = 0
    world:hatchEggs()
    local quiet = 0
    for _ = 1, 900 do
      -- boxes chain through callbacks; done once the world stays clear
      if inWorld() then quiet = quiet + 1 else quiet = 0 end
      if quiet > 40 then break end
      local now = className(top())
      if now == "gen2.NamingScreen" then
        wait(20) tap("a", 12) tap("start", 12) tap("a", 30)
      elseif now == "gen2.EggHatchAnim" or now == "overworld" then
        wait(1)
      else
        tap("a", 10)
      end
    end
  else
    U.log("NOTE", "could not give an egg")
  end
  wait(60)
  Speech.say = say
  U.log("DONE")
end
