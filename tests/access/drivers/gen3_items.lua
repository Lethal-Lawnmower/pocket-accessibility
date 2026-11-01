-- Gen 3 items and storage screens (FireRed): bag pockets, actions and
-- toss, TM case, berry pouch, party with its action menu, switch and TM
-- use, summary pages and move detail, Pokédex, PC hub, box storage with a
-- deposit and a release, item PC withdraw and deposit, shop buy and sell,
-- the money box, the town map and Fly map, and the bag in a wild battle.
-- It asserts nothing: it logs every screen change (SCREEN) and every
-- utterance (SAID) so the trace shows what the layer says.
--
-- The screens are opened the way the game's own callers open them
-- (BagMenu.show, PartyMenu.show, Hud.openPc ...) with a party and items
-- given through upstream's own Party.giveMon and Bag.add, then driven by
-- key presses.  Run silently and isolated, in a disposable identity:
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/gen3_items.lua
--   POKEPORT_VERSION=firered POKEPORT_GAME=firered POKEPORT_IDENTITY=pocket-access-items-firered
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Speech = require("src.access.Speech")
  local Top = require("src.access.screens.gen3.Top")

  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts)
    said[#said + 1] = tostring(text) .. ((opts and opts.interrupt == false) and "  [queued]" or "")
    return say(text, opts)
  end

  local last
  local function watch()
    local ok, top = pcall(Top.resolve, game)
    local name = ok and top and tostring(top.gen3) or ("phase:" .. tostring(game.phase))
    if name ~= last then U.log("SCREEN", name) last = name end
    for _, line in ipairs(said) do U.log("SAID", line) end
    said = {}
  end
  local function wait(n) for _ = 1, n do U.wait(1) watch() end end
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    wait(2)
    game.input.state[button] = false
    wait(frames or 12)
  end
  local function taps(list, frames) for _, b in ipairs(list) do tap(b, frames) end end
  local function section(label, fn)
    U.log("SECTION", label)
    local ok, err = pcall(fn)
    if not ok then U.log("FAIL", label .. ": " .. tostring(err)) end
    wait(20)
  end
  local function settle(frames)
    local Message = package.loaded["src.ui.game3.message"]
    for _ = 1, frames or 120 do
      if not (Message and Message.isOpen and Message.isOpen()) then break end
      tap("a", 20)
    end
  end
  local function closeAll()
    local Stack = require("src.ui.game3.stack")
    for _ = 1, 12 do
      if not Stack.top() then return end
      tap("b", 25)
    end
  end

  -- boot and a new game
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    wait(1)
  end
  wait(120)
  local ok, err = pcall(function() game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 }) end)
  if not ok then U.log("FAIL", "new game: " .. tostring(err)) return end
  wait(120)
  settle(60)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local C = require("src.core.game3.constants")
  local session = Runtime.getSession()
  if not session then U.log("FAIL", "no session") return end
  local consts = C.active(session)
  local function item(name) return consts:require("items", name) end

  section("setup", function()
    session.party = {}
    local _, _, lead = Party.giveMon(session, 4, 12)            -- CHARMANDER
    Party.giveMon(session, 16, 5, "BIRDY")                       -- PIDGEY, nicknamed
    local _, _, third = Party.giveMon(session, 1, 7)             -- BULBASAUR
    if third then third.item = item("ITEM_POTION") end
    if lead and lead.moves then lead.moves = { lead.moves[1], lead.moves[2] } end
    Bag.add(session.bag, item("ITEM_POTION"), 3)
    Bag.add(session.bag, item("ITEM_ANTIDOTE"), 1)
    Bag.add(session.bag, item("ITEM_POKE_BALL"), 5)
    Bag.add(session.bag, item("ITEM_TM06"), 1)
    Bag.add(session.bag, item("ITEM_HM01"), 1)
    Bag.add(session.bag, item("ITEM_CHERI_BERRY"), 2)
    Bag.add(session.bag, item("ITEM_TOWN_MAP"), 1)
    session.money = 5000
    U.log("PARTY", #session.party)
  end)

  section("bag", function()
    require("src.ui.game3.bag_menu").show(session.bag, { session = session })
    wait(40)
    taps({ "down", "down", "up" }, 15)
    tap("a", 20)                    -- POTION: action menu
    taps({ "down", "down" }, 15)    -- GIVE, TOSS
    tap("a", 20)                    -- toss quantity
    tap("up", 15)
    tap("a", 20)                    -- confirm
    tap("down", 15)                 -- NO
    tap("a", 25)                    -- back to the list
    tap("right", 30)                -- KEY ITEMS
    taps({ "down", "down" }, 15)
    tap("right", 30)                -- POKé BALLS
    tap("left", 30)
    tap("left", 30)                 -- ITEMS
  end)

  section("tm case", function()
    local BagMenu = require("src.ui.game3.bag_menu")
    BagMenu.close()
    wait(10)
    require("src.ui.game3.tm_case").show(session, session.bag, { session = session, bag = session.bag })
    wait(30)
    tap("down", 15)
    tap("a", 20)                    -- action menu
    tap("down", 15)
    tap("b", 20)
    tap("down", 15)                 -- CLOSE
    tap("b", 25)
  end)

  section("berry pouch", function()
    require("src.ui.game3.berry_pouch").show(session, session.bag, { session = session, bag = session.bag })
    wait(30)
    tap("a", 20)
    taps({ "down", "down" }, 15)    -- TOSS
    tap("a", 20)
    tap("up", 15)
    tap("b", 20)
    tap("b", 25)
  end)

  section("party", function()
    local PartyMenu = require("src.ui.game3.party_menu")
    PartyMenu.show(session.party, nil, { session = session, bag = session.bag })
    wait(30)
    taps({ "down", "down", "down" }, 15)
    tap("up", 15)
    tap("up", 15)
    tap("a", 20)                    -- action menu on slot 2
    tap("down", 15)                 -- SWITCH
    tap("a", 20)
    tap("down", 15)
    tap("a", 25)                    -- switched
    tap("a", 20)                    -- action menu
    tap("a", 40)                    -- SUMMARY
    tap("right", 30)
    tap("right", 30)
    tap("a", 40)                    -- move detail
    tap("down", 15)
    tap("down", 15)
    tap("b", 40)
    tap("down", 30)                 -- next Pokémon
    tap("b", 40)                    -- close summary
    tap("b", 25)                    -- close party
    closeAll()
  end)

  section("party TM", function()
    local PartyMenu = require("src.ui.game3.party_menu")
    PartyMenu.show(session.party, nil, { session = session, bag = session.bag, item = item("ITEM_TM06"), mode = "use" })
    wait(30)
    taps({ "down", "down" }, 15)
    tap("b", 25)
    closeAll()
  end)

  section("TM with four moves: forget-a-move summary", function()
    local lead = session.party[1]
    local first = lead and lead.moves and lead.moves[1]
    local ids = { 10, 45, 52, 108 } -- SCRATCH, GROWL, EMBER, SMOKESCREEN
    lead.moves = {}
    for i, id in ipairs(ids) do
      lead.moves[i] = type(first) == "table" and { id = id } or id
    end
    local PartyMenu = require("src.ui.game3.party_menu")
    PartyMenu.show(session.party, nil, { session = session, bag = session.bag, item = item("ITEM_TM06"), mode = "use" })
    wait(30)
    tap("a", 60)                    -- teach CHARMANDER
    for _ = 1, 6 do                 -- through the messages and YES to forget a move
      local SummaryMenu = package.loaded["src.ui.game3.summary_menu"]
      if SummaryMenu and SummaryMenu.open then break end
      tap("a", 40)
    end
    wait(30)
    taps({ "down", "down", "down", "down" }, 20)
    tap("b", 40)                    -- give up forgetting
    tap("a", 40)                    -- "Stop trying to teach?" YES
    tap("a", 40)                    -- "did not learn" message
    tap("b", 40)                    -- close the party
    U.log("PARTY OPEN", tostring(PartyMenu.open), tostring(PartyMenu.mode))
    closeAll()
  end)

  section("pokedex", function()
    local Dex = require("src.core.game3.dex")
    session.dex = session.dex or Dex.new()
    for _, sp in ipairs({ 1, 4, 16, 19 }) do pcall(Dex.setSeen, session.dex, sp, true) end
    for _, sp in ipairs({ 4, 16 }) do pcall(Dex.setCaught, session.dex, sp, true) end
    require("src.ui.game3.pokedex").show(session.dex, { session = session })
    wait(30)
    tap("down", 15)
    tap("up", 15)
    tap("a", 25)                    -- numerical list
    taps({ "down", "down", "down" }, 15)
    tap("a", 30)                    -- entry
    tap("a", 25)                    -- page 2
    tap("b", 25)                    -- page 1
    tap("b", 25)                    -- list
    tap("b", 25)                    -- contents
    tap("b", 30)
    closeAll()
  end)

  section("pc and box storage", function()
    local Hud = require("src.ui.game3.hud")
    if Hud.openPc then Hud.openPc(game, session) else require("src.ui.game3.pc_menu").show({ session = session }) end
    wait(30)
    settle(10)
    tap("down", 15)
    tap("up", 15)
    tap("a", 25)                    -- storage menu
    tap("down", 15)                 -- DEPOSIT
    tap("a", 60)                    -- box storage (drawer)
    tap("down", 15)
    tap("down", 15)                 -- slot 3
    tap("a", 20)                    -- action menu
    tap("a", 30)                    -- STORE: box picker
    tap("right", 15)
    tap("left", 15)
    tap("a", 40)                    -- deposited in BOX 1
    tap("b", 60)                    -- close
    wait(40)
    tap("up", 15)                   -- WITHDRAW
    tap("a", 60)                    -- box storage
    tap("right", 15)
    tap("left", 15)
    tap("a", 20)                    -- action menu on slot 1
    taps({ "down", "down" }, 15)    -- RELEASE
    tap("a", 25)                    -- release question (NO)
    tap("up", 15)                   -- YES
    tap("a", 120)                   -- released
    tap("a", 30)
    tap("a", 30)
    tap("up", 15)                   -- box title
    tap("a", 20)                    -- box menu
    tap("b", 20)
    tap("up", 15)                   -- PARTY POKéMON button
    tap("right", 15)                -- CLOSE BOX button
    tap("a", 60)
    wait(30)
  end)

  section("item pc", function()
    local PcMenu = require("src.ui.game3.pc_menu")
    if not PcMenu.open then
      PcMenu.show({ session = session })
      wait(30)
    end
    for _ = 1, 4 do
      if PcMenu.mode == "root" then break end
      tap("b", 25)
    end
    tap("down", 15)                 -- player's PC
    tap("a", 25)
    tap("a", 25)                    -- ITEM STORAGE
    tap("a", 60)                    -- WITHDRAW: item PC
    tap("a", 20)                    -- submenu
    tap("a", 25)                    -- WITHDRAW (one POTION)
    tap("a", 30)
    tap("b", 60)                    -- leave item PC
    wait(30)
    tap("down", 15)                 -- DEPOSIT
    tap("a", 60)                    -- bag at the item PC
    tap("a", 25)
    tap("b", 25)
    tap("b", 60)
    closeAll()
  end)

  section("shop", function()
    require("src.ui.game3.shop_menu").show({ session = session,
      items = { item("ITEM_POTION"), item("ITEM_ANTIDOTE"), item("ITEM_POKE_BALL") } })
    wait(20)
    tap("down", 15)
    tap("up", 15)
    tap("a", 60)                    -- BUY
    tap("down", 15)
    tap("up", 15)
    tap("a", 25)                    -- quantity
    tap("up", 15)
    tap("a", 25)                    -- confirm
    tap("a", 40)                    -- YES
    tap("a", 30)
    tap("b", 60)                    -- back to the root
    tap("down", 15)                 -- SELL
    tap("a", 80)
    taps({ "up", "up", "up" }, 15)  -- POTION (the bag keeps its last row)
    tap("a", 30)                    -- sell POTION: quantity
    tap("up", 15)
    tap("a", 25)                    -- confirm
    tap("a", 40)                    -- YES
    tap("a", 30)
    tap("b", 60)                    -- close the bag
    tap("b", 30)                    -- leave the shop
    closeAll()
  end)

  section("money box", function()
    local MoneyBox = require("src.ui.game3.money_box")
    MoneyBox.show(19, 1)
    wait(30)
    session.money = (session.money or 0) - 100
    MoneyBox.update()
    wait(30)
    MoneyBox.hide()
  end)

  section("town map", function()
    local RegionMap = require("src.ui.game3.region_map")
    RegionMap.show({ session = session, mode = "normal" })
    wait(120)
    taps({ "up", "up", "up", "right", "right" }, 15)
    tap("b", 60)
    closeAll()
    RegionMap.show({ session = session, mode = "fly" })
    wait(120)
    taps({ "up", "up", "up", "up" }, 15)
    tap("b", 60)
    closeAll()
  end)

  section("battle bag", function()
    local BattleBridge = require("src.core.game3.battle_bridge")
    local started, why = pcall(BattleBridge.startWild, Runtime._mod, game, { species = 16, level = 3 }, { fade = false })
    if not started then U.log("FAIL", "battle: " .. tostring(why)) return end
    -- wait for the action menu (FIGHT, BAG, POKéMON, RUN), pressing A
    -- only through the opening messages
    local function inMenu()
      local Ui = package.loaded["src.core.game3.battle.ui"]
      return Ui and Ui._mode == "menu"
    end
    local function toMenu()
      for _ = 1, 600 do
        if inMenu() then break end
        local Message = package.loaded["src.ui.game3.message"]
        if Message and Message.isOpen and Message.isOpen() and Message._waiting then tap("a", 10) else wait(1) end
      end
      U.log("BATTLE MENU", tostring(inMenu()))
    end
    toMenu()
    tap("right", 20)
    tap("a", 60)                    -- BAG
    taps({ "down", "up" }, 15)
    tap("right", 30)                -- KEY ITEMS
    tap("b", 60)
    wait(30)
    -- party from the battle menu (POKéMON, under FIGHT; the cursor is
    -- still on BAG)
    toMenu()
    if inMenu() then
      tap("left", 20)
      tap("down", 20)
      tap("a", 60)
      tap("down", 15)
      tap("a", 30)                  -- action menu on the second slot
      tap("down", 15)
      tap("b", 30)
      tap("b", 60)
    end
    wait(30)
  end)

  Speech.say = say
  U.log("DONE")
end
