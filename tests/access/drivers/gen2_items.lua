-- Gen 2 item and storage screens in a real game (decision 27): the PACK
-- (pockets, submenu, toss quantity, YES/NO, messages, item move), a mart
-- (buy, quantity, typed confirm, money, sell through the held PACK), the
-- Pokemon Center PC, Bill's PC (CHANGE BOX save prompt, refused), the boxes
-- (withdraw list, submenu, release question answered NO, withdraw, deposit,
-- MOVE's insert cursor), the item PC (withdraw, toss, deposit through the
-- held PACK), GIVE/TAKE, the move deleter, the forget-a-move list, the
-- PP-target list and, in Crystal, the move tutor.  It logs every screen
-- change and every utterance ("!" marks an interrupting one) and asserts
-- nothing about wording, so the log shows what the layer says on each screen.
-- Steps choose rows by reading the screen's fields, so a different bag or
-- menu order still lands on the intended row.
--
-- Run silently with a disposable identity, for example:
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_BACKGROUND=1 POKEPORT_ACCESS_TRACE=1
--   POKEPORT_TOUCH=0 POKEPORT_IDENTITY=pocket-access-items-crystal
--   POKEPORT_VERSION=crystal POKEPORT_GAME=crystal
--   POKEPORT_DRIVER=tests/access/drivers/gen2_items.lua lovec .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Speech = require("src.access.Speech")
  local Screens = require("src.ui.Screens")
  local Mon = require("src.battle.gen2.Mon")
  local GameVersion = require("src.core.GameVersion")

  local function className(state)
    if state == nil then return "overworld" end
    local mt = getmetatable(state)
    for name, mod in pairs(package.loaded) do
      if mod == mt and type(name) == "string" then return (name:gsub("^src%.ui%.", "")) end
    end
    return tostring(state.screenId or mt)
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
  -- Typed message boxes ignore presses until the page has typed out.
  local function settle(state)
    for _ = 1, 400 do
      local t = state or top()
      local typer = t and t.typer
      if not (typer and (typer.shown or 0) < (typer.total or 0)) then break end
      wait(1)
    end
    wait(4)
  end
  local function press(button, frames) settle() tap(button, frames) settle() end
  local function step(label) U.log("STEP", label) end
  -- Taps `button` until test() holds (at most `limit` taps); logs a miss.
  local function until_(test, button, label, limit)
    for _ = 1, limit or 12 do
      if test() then return true end
      settle()
      if test() then return true end
      tap(button or "down", 12)
    end
    if test() then return true end
    U.log("MISS", label or "?", className(top()))
    return false
  end
  local function waitFor(test, limit)
    for _ = 1, limit or 300 do
      if test() then return true end
      wait(1)
    end
    return test()
  end
  local function clearStack()
    game.stack:clear()
    wait(10)
  end

  wait(60)
  local world, save, data = game.world, game.save, game.data
  if not (world and world.map and save) then U.log("FAIL", "the world did not boot") return end
  U.log("MAP", world.map.id or "?")

  -- The save the screens read: a party, bag, money, a box and PC items.
  save.player = save.player or {}
  save.player.money = 3000
  local cynda = Mon.new(data, "CYNDAQUIL", 14)
  local pidgey = Mon.new(data, "PIDGEY", 5)
  local sprout = Mon.new(data, "BELLSPROUT", 7)
  sprout.nickname = "SPROUTY"
  save.party = { cynda, pidgey, sprout }
  save.inventory = save.inventory or {}
  save.inventory.POTION = 3
  save.inventory.ANTIDOTE = 1
  save.inventory.POKE_BALL = 5
  save.inventory.ETHER = 1
  save.inventory.BICYCLE = 1
  local tmId, tmNumber
  for id, def in pairs(data.items or {}) do
    local n = type(def) == "table" and tonumber(def.tmNumber)
    if n and def.pocket == "TM_HM" and def.teaches and (not tmNumber or n < tmNumber) then
      tmId, tmNumber = id, n
    end
  end
  if tmId then save.inventory[tmId] = 1 end
  save.boxes = save.boxes or {}
  save.boxes[1] = { Mon.new(data, "SENTRET", 4), Mon.new(data, "HOOTHOOT", 3) }
  save.currentBox = 1
  save.pcItems = { POTION = 5, BICYCLE = nil }
  U.log("TM", tostring(tmId))

  -- ---------------------------------------------------------------- PACK
  step("pack")
  game.packCursor = nil
  local pack = Screens.push(game, "Gen2PackMenu", { onClose = function() game.stack:pop() end })
  wait(20)
  tap("down") tap("up")
  tap("right", 12) tap("right", 12) tap("right", 12)
  tap("left", 12) tap("left", 12) tap("left", 12)
  until_(function() local r = pack.rows[pack.index] return r and r.id == "POTION" end, "down", "POTION row")
  tap("a", 12)            -- the submenu
  until_(function() local m = pack.submenu return m and m.rows[m.index] == "toss" end, "down", "TOSS")
  tap("a", 12)            -- "Throw away how many?"
  tap("up")               -- 2
  tap("a", 12)            -- the YES/NO
  tap("down") tap("up")
  tap("a", 12)            -- YES: "Threw away"
  tap("a", 12)            -- clears the message
  tap("select", 12)       -- item move
  tap("down") tap("b", 12)
  tap("b", 20)
  save.inventory.POTION = 3

  -- ---------------------------------------------------------------- MART
  step("mart")
  world:setMap("CHERRYGROVE_MART", 2, 3, "left")
  wait(40)
  local mart
  for _ = 1, 60 do
    if topIs("gen2.MartMenu") then mart = top() break end
    tap("a", 10)
  end
  if mart then
    wait(10)
    tap("down") tap("up")
    tap("a", 20)            -- BUY
    tap("down") tap("up")
    tap("a", 12)            -- quantity
    tap("up") tap("up")     -- 3
    tap("a", 6)             -- "3 POTION(S) will be"
    press("a")              -- YES: "Here you are"
    press("a", 12)          -- clears
    tap("b", 20)            -- back to the top menu
    tap("down")             -- SELL
    tap("a", 20)            -- the held PACK
    until_(function() local p = mart.pack local r = p and p.rows[p.index] return r and r.id == "POTION" end,
      "down", "POTION to sell")
    tap("a", 12)            -- sell quantity
    tap("up")
    tap("a", 6)             -- "I can pay you"
    press("a")              -- "Is that OK?"
    press("a")              -- YES: "Got"
    press("a", 12)          -- clears
    tap("b", 20)            -- closes the PACK
    tap("down") tap("down") -- QUIT
    tap("a", 6)
    press("a", 20)
    until_(function() return topIs("overworld") end, "a", "out of the mart", 10)
  else
    U.log("FAIL", "the mart never opened; top " .. className(top()))
  end

  -- ------------------------------------------------------ POKéMON CENTER PC
  step("center pc")
  world:setMap("CHERRYGROVE_POKECENTER_1F", 4, 4, "up")
  wait(10)
  local pcX, pcY
  for cy = 0, world.map.heightCells - 1 do
    for cx = 0, world.map.widthCells - 1 do
      if world.map:cellCollision(cx, cy) == 0x93 then pcX, pcY = cx, cy end
    end
  end
  local center
  if pcX then
    world:setMap("CHERRYGROVE_POKECENTER_1F", pcX, pcY + 1, "up")
    wait(20)
    tap("a", 10)
    center = top()
  end
  if center and topIs("gen2.CenterPcMenu") then
    press("a", 10)          -- "<PLAYER> turned on the PC."
    tap("down") tap("up")
    until_(function() return center.entries[center.index].id == "bills" end, "down", "BILL's PC")
    tap("a", 10)
    until_(function() return topIs("gen2.PcMenu") end, "a", "Bill's PC opens", 6)
    local bills = top()
    local function billsRow(id)
      return until_(function() local e = bills.entries[bills.index] return e and e.id == id end,
        "down", id)
    end

    step("change box")
    billsRow("changebox")
    tap("a", 10)
    tap("down")
    tap("a", 10)            -- the save prompt
    press("a", 10)          -- its second page
    settle()
    tap("down") tap("b", 10) -- NO
    tap("b", 10)            -- leave the picker

    step("box withdraw")
    billsRow("withdraw")
    tap("a", 20)
    local box = top()
    tap("down") tap("up")
    tap("a", 10)            -- submenu
    until_(function() return box.submenuRows and box:submenuRows()[box.submenuIndex] == "RELEASE" end,
      "down", "RELEASE")
    tap("a", 10)            -- "Release PKMN?" and the ChoiceBox (NO first)
    tap("a", 10)            -- NO
    until_(function() return box.submenuRows and box:submenuRows()[box.submenuIndex] == "WITHDRAW" end,
      "up", "WITHDRAW")
    tap("a", 10)            -- "Got SENTRET!"
    waitFor(function() return box.message == nil and box.cryWait == nil end, 400)
    wait(10)
    tap("b", 20)            -- close the box

    step("box deposit")
    billsRow("deposit")
    tap("a", 20)
    box = top()
    until_(function() local m = box.save.party[box.index] return m and m.nickname == "SPROUTY" end,
      "down", "SPROUTY")
    tap("a", 10)
    tap("a", 10)            -- DEPOSIT: "Stored SPROUTY!"
    waitFor(function() return box.message == nil and box.cryWait == nil end, 400)
    wait(10)
    tap("b", 20)

    step("box move")
    billsRow("move")
    tap("a", 20)            -- MOVE screen, on the party
    box = top()
    tap("right", 12) tap("left", 12)
    tap("a", 10)            -- MOVE / STATS / CANCEL
    tap("a", 10)            -- MOVE: the insert cursor
    tap("right", 12)
    tap("down")
    tap("a", 10)            -- "Saving… Leave ON!"
    tap("a", 10)
    tap("b", 20)
    billsRow("seeya")
    tap("a", 20)            -- SEE YA!

    step("item pc")
    until_(function() return topIs("gen2.CenterPcMenu") end, "b", "back at the whose-PC menu", 4)
    until_(function() return center.entries[center.index].id == "players" end, "down", "own PC")
    tap("a", 10)
    until_(function() return topIs("gen2.ItemPcMenu") end, "a", "item PC opens", 6)
    local itemPc = top()
    local function itemRow(id)
      return until_(function() local e = itemPc.entries[itemPc.index] return e and e.id == id end,
        "down", id)
    end
    itemRow("withdraw")
    tap("a", 12)            -- the PC list
    tap("a", 10)            -- quantity
    tap("up")
    tap("a", 6)             -- "Withdrew"
    press("a", 10)
    tap("b", 10)
    itemRow("toss")
    tap("a", 12)
    tap("a", 10)            -- "Toss out how many"
    tap("a", 10)            -- the YES/NO
    tap("down")
    tap("a", 10)            -- NO
    tap("b", 10)
    itemRow("deposit")
    tap("a", 12)            -- the held PACK
    tap("down") tap("up")
    tap("a", 10)            -- quantity
    tap("a", 6)             -- "Deposited"
    press("a", 10)
    tap("b", 12)            -- close the PACK
    tap("b", 10)            -- log off
    tap("b", 20)            -- shut down
    until_(function() return topIs("overworld") end, "b", "PC closed", 6)
  else
    U.log("FAIL", "the Pokemon Center PC did not open")
  end

  -- Away from the PC, so later A presses on the map do not turn it on.
  clearStack()
  world:setMap("CHERRYGROVE_CITY", 10, 10, "down")
  wait(30)

  -- ------------------------------------------------------------ GIVE / TAKE
  step("give")
  save.party = { cynda, pidgey }
  save.inventory.POTION = 3
  game.packCursor = nil
  local held = Screens.push(game, "Gen2HeldItemMenu", { save = save, slot = 1,
    onClose = function() game.stack:pop() end })
  wait(10)
  tap("down") tap("up")
  tap("a", 20)              -- GIVE: the PACK on top
  local givePack = top()
  if topIs("gen2.PackMenu") then
    until_(function() local r = givePack.rows[givePack.index] return r and r.id == "POTION" end,
      "down", "POTION to give")
    tap("a", 12)
    press("a", 10)          -- "Made CYNDAQUIL hold POTION."
  end
  step("take")
  held = Screens.push(game, "Gen2HeldItemMenu", { save = save, slot = 1,
    onClose = function() game.stack:pop() end })
  wait(10)
  tap("down")
  tap("a", 6)               -- "Took POTION from CYNDAQUIL."
  press("a", 10)
  if held and topIs("gen2.HeldItemMenu") then clearStack() end

  -- ------------------------------------------------------------ MOVE LISTS
  step("move deleter")
  Screens.push(game, "Gen2MoveDeleter", { mon = cynda, moves = data.moves,
    onChoose = function() game.stack:pop() end, onCancel = function() game.stack:pop() end })
  wait(10)
  tap("down") tap("up")
  tap("b", 10)

  step("forget a move")
  local full = Mon.new(data, "CYNDAQUIL", 30)
  save.party = { full, pidgey }
  game:learnMoveOn(full, "FLAMETHROWER", function() end)
  until_(function() return topIs("gen2.MoveDeleter") end, "a", "forget list", 40)
  if topIs("gen2.MoveDeleter") then
    tap("down") tap("down")
    tap("b", 12)            -- "Stop learning FLAMETHROWER?"
    until_(function() return topIs("overworld") end, "a", "learning ends", 20)
  end

  step("pp target")
  clearStack()
  full.moves[1].pp = 3
  save.inventory.ETHER = 1
  game:usePartyItem("ETHER")
  wait(20)
  tap("a", 20)              -- the first Pokemon
  if topIs("gen2.MoveDeleter") then
    tap("down") tap("up")
    tap("a", 20)
  end
  until_(function() return topIs("overworld") end, "a", "ether done", 20)

  -- ------------------------------------------------------------ MOVE TUTOR
  if GameVersion.engine(GameVersion.get()) == "crystal" then
    step("move tutor")
    clearStack()
    save.party = { cynda, pidgey }
    Screens.push(game, "Gen2MoveTutor", { move = "FLAMETHROWER", moveName = "FLAMETHROWER",
      onDone = function() end })
    wait(20)
    tap("down")
    tap("a", 20)            -- PIDGEY: not compatible
    until_(function() return topIs("gen2.MoveTutor") end, "a", "back on the tutor list", 10)
    tap("down")
    tap("b", 20)
  end

  wait(30)
  Speech.say = say
  U.log("DONE")
end
