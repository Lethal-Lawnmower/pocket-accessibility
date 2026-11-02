-- Gen 3 special screens walk (FireRed; decision 29): logs every utterance
-- and every change of what gen3/Top.lua reports as the screen, through the
-- Game Corner slots (by the machine's own script), the prize counter (the
-- clerk's script), the Ruin Valley braille wall (its script), and a set of
-- screens opened directly with their own show functions (records, PIN,
-- Easy Chat, Day-Care list, Hall of Fame PC, diploma, picture boxes, the
-- level-up window, the Itemfinder arrow, the whiteout screen, the mod
-- manager, the credits).  It asserts nothing.  Run silently and isolated:
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/gen3_special.lua
--   POKEPORT_VERSION=firered POKEPORT_GAME=firered POKEPORT_IDENTITY=<disposable>
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Speech = require("src.access.Speech")
  local Top = require("src.access.screens.gen3.Top")

  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts)
    said[#said + 1] = (opts and opts.interrupt == false and "(queued) " or "") .. tostring(text)
    return say(text, opts)
  end

  local lastKind
  local function watch()
    local ok, top = pcall(Top.resolve, game)
    local kind = ok and type(top) == "table" and tostring(top.gen3) or "none"
    if kind ~= lastKind then U.log("SCREEN", kind) lastKind = kind end
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
  local function step(label, fn)
    U.log("STEP", label)
    local ok, err = pcall(fn)
    if not ok then U.log("FAIL", label .. ": " .. tostring(err)) end
    wait(10)
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    wait(1)
  end
  wait(120)
  local ok, err = pcall(function()
    game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  end)
  if not ok then U.log("FAIL", "new game: " .. tostring(err)) return end
  wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Stack = require("src.ui.game3.stack")
  local Bag = require("src.core.game3.bag")
  local session = Runtime.getSession()
  if not session then U.log("FAIL", "no session") return end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    if game.session then game.session.x, game.session.y, game.session.facing = x, y, facing or "up" end
    wait(90)
  end
  local function busy()
    return Message.isOpen() or Choice.active or (Space.vm and Space.vm:isRunning())
  end
  local function settle(limit)
    for _ = 1, limit or 60 do
      if not busy() and not Stack.busy() then return end
      if Message.isOpen() or Choice.active then tap("b", 10) else wait(10) end
    end
  end

  -- pokefirered/include/constants/flags.h:604 FLAG_GOT_COIN_CASE
  Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, 0x243, true)
  Bag.Coins.set(session, 120)

  step("slot machine by its script", function()
    local SlotUi = require("src.ui.game3.slot_machine")
    goTo("FR_CELADON_CITY_GAME_CORNER", 1, 7, "left")
    tap("a", 20)
    for _ = 1, 80 do
      if SlotUi.isOpen() then break end
      if busy() then tap("a", 10) else wait(10) end
    end
    if not SlotUi.isOpen() then U.log("FAIL", "slot machine did not open") return end
    wait(60)
    tap("right", 40) -- payout chart
    tap("left", 40)
    tap("down", 20)
    tap("down", 20)
    tap("down", 30) -- third coin starts the spin
    for _ = 1, 3 do tap("a", 40) end
    for _ = 1, 600 do
      if SlotUi.task == "bet" then break end
      wait(1)
    end
    wait(30)
    tap("b", 20)
    tap("down", 15)
    tap("up", 15)
    tap("a", 60)
    for _ = 1, 120 do
      if not SlotUi.isOpen() then break end
      wait(1)
    end
    settle()
  end)

  local function prizeCounter()
    local Prize = require("src.ui.game3.prize_corner")
    Bag.Coins.set(session, 4000)
    goTo("FR_CELADON_CITY_GAME_CORNER_PRIZE_ROOM", 6, 4, "up")
    tap("a", 20)
    for _ = 1, 100 do
      if Prize.isOpen() then break end
      if busy() then tap("a", 10) else wait(10) end
    end
    U.log("NOTE", "prize open=" .. tostring(Prize.isOpen()) .. " message open under it=" .. tostring(Message.isOpen()))
    tap("down", 20)
    tap("down", 20)
    tap("b", 30)
    settle()
  end

  step("prize counter by the clerk's script", prizeCounter)

  step("braille wall by its script", function()
    goTo("FR_SIX_ISLAND_RUIN_VALLEY", 24, 25, "up")
    tap("a", 40)
    for _ = 1, 40 do
      if Choice.active then break end
      if Message.isWaiting and Message.isWaiting() then tap("a", 6) else wait(6) end
    end
    if Choice.active then Choice.cursor = 1 tap("a", 20) end
    for _ = 1, 80 do
      if Message.isOpen() and Message.frameKind() == "braille" then break end
      if Message.isWaiting and Message.isWaiting() then tap("a", 6) else wait(6) end
    end
    wait(60)
    settle()
  end)

  -- Screens opened with their own show functions from here on.
  step("coins box", function()
    local Coins = require("src.ui.game3.coins_box")
    Coins.show(1, 1)
    wait(30)
    Bag.Coins.set(session, 3990)
    Coins.update()
    wait(30)
    Coins.hide()
  end)

  step("trainer tower time board", function()
    local R = require("src.ui.game3.trainer_tower_records")
    R.show({ session = session, kind = "tower" })
    wait(90)
    tap("a", 90)
  end)

  step("link battle records", function()
    local R = require("src.ui.game3.trainer_tower_records")
    R.show({ session = session, kind = "link" })
    wait(90)
    tap("a", 90)
  end)

  step("minigame records", function()
    local R = require("src.ui.game3.minigame_records")
    R.show("pokemon_jump", session)
    wait(30)
    tap("a", 20)
    R.show("dodrio", session)
    wait(30)
    tap("a", 20)
  end)

  step("PIN pad", function()
    local Pin = require("src.ui.game3.pin_entry")
    Pin.show({ mode = "set" })
    wait(20)
    tap("up", 10)
    tap("up", 10)
    tap("right", 10)
    tap("down", 10)
    tap("b", 20)
  end)

  step("Easy Chat profile", function()
    local EC = require("src.ui.game3.easy_chat")
    EC.open({ session = session, type = 0 })
    wait(30)
    tap("right", 10)
    tap("a", 15) -- group list
    tap("right", 10)
    tap("down", 10)
    tap("a", 15) -- word list
    tap("down", 10)
    tap("b", 10)
    tap("b", 10)
    tap("down", 10)
    tap("down", 10) -- footer
    tap("b", 10)
    tap("b", 15) -- quit question
    tap("down", 10)
    tap("a", 30)
  end)

  step("Day-Care list", function()
    local D = require("src.ui.game3.daycare_menu")
    local Daycare = require("src.core.game3.daycare")
    local dc = Daycare.stateOf and Daycare.stateOf(session) or session.daycare
    if not dc then U.log("NOTE", "no day-care record accessor; skipped") return end
    D.show(dc, function() end)
    wait(20)
    tap("down", 10)
    tap("down", 10)
    D.close()
  end)

  step("Hall of Fame PC", function()
    local Pc = require("src.ui.game3.hall_of_fame_pc")
    local team = {}
    for i, mon in ipairs(session.party or {}) do team[i] = mon end
    if #team == 0 then team[1] = { species = 25, nickname = "PIKACHU", level = 50, personality = 0, trainerId = 1 } end
    session.hallOfFameTeams = { team }
    Pc.show({ session = session })
    wait(30)
    tap("down", 15)
    tap("b", 30)
  end)

  step("diploma", function()
    local Diploma = require("src.ui.game3.diploma")
    Diploma.show({})
    for _ = 1, 400 do
      if Diploma._phase == "wait" then break end
      wait(1)
    end
    tap("a", 60)
  end)

  step("Pokémon picture and fossil", function()
    local Pic = require("src.ui.game3.mon_pic")
    Pic.show(25, 10, 3, { noCry = true })
    wait(30)
    Pic.active = false
    wait(5)
  end)

  step("level-up window", function()
    local Growth = require("src.ui.game3.stat_growth")
    Growth.open({ species = 25 }, { maxHp = 20, atk = 10, def = 10, spa = 9, spd = 9, spe = 12 },
      { maxHp = 23, atk = 12, def = 11, spa = 10, spd = 9, spe = 14 })
    wait(20)
    Growth._page = 2
    wait(20)
    Growth.close({ silent = true })
  end)

  step("Itemfinder arrow", function()
    local Finder = require("src.core.game3.itemfinder")
    Finder._task = { result = { underfoot = false, itemX = 3, itemY = -1, dings = 2 } }
    wait(20)
    Finder._task = nil
  end)

  step("Viridian Forest title card by its warp", function()
    local Warp = require("src.core.game3.warp")
    local MapCatalog = require("src.import.gba.map_catalog")
    goTo(MapCatalog.pretToEngine("Route2_ViridianForest_SouthEntrance"), 7, 2, "up")
    Warp.request(nil, game, MapCatalog.pretToEngine("ViridianForest"), 29, 61, "up")
    wait(400)
    settle()
  end)

  step("Seagallop crossing", function()
    local Sea = require("src.ui.game3.seagallop")
    -- natives_seagallop.lua ids: 0 Vermilion City, 3 Three Island
    Sea.start(0, 3, function() end, function() end)
    wait(90)
    Sea.stop()
  end)

  step("mod manager", function()
    local MM = require("src.ui.game3.mod_manager")
    MM.show({ game = game })
    wait(30)
    tap("down", 15)
    tap("b", 20)
    if MM.isOpen() then MM.close() end
  end)

  step("whiteout screen", function()
    local Rush = require("src.ui.game3.whiteout_rush")
    Rush.start(game, session, {})
    for _ = 1, 300 do
      if Rush.phase() == "wait" then break end
      wait(1)
    end
    tap("a", 120)
    settle()
  end)

  step("credits (first screens)", function()
    local Credits = require("src.ui.game3.credits")
    if not Credits.start({}) then U.log("NOTE", "credits pack missing") return end
    wait(2400)
  end)

  Speech.say = say
  U.log("DONE")
  love.event.quit(0)
end
