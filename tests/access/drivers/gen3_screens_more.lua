-- Gen 3 screens the first FireRed runs did not reach: Mystery Gift from the
-- boot menu, then in the field the TM case and berry pouch opened from the
-- bag's own menu, TAKE, Softboiled, Teachy TV demos, the double-battle
-- party, a shop opened by a clerk's script, the Pokédex habitat pages,
-- registration after a catch, wallpaper and MOVE in storage, the party
-- level-up window, "can fly" on the Fly map and the prize corner list.
-- It asserts nothing: it logs every screen change (SCREEN) and every
-- utterance (SAID).
--
-- Harness setup (not reachable this early in a new game): the boot menu is
-- given its CONTINUE rows (`boot.hasContinue`) so MYSTERY GIFT is listed,
-- and the gift screen's wireless search goes to a stub client that answers
-- "offline", so the run never contacts upstream's gift server.  Party,
-- items, flags and Pokédex marks are given through upstream's own
-- functions, as in gen3_items.lua.  Run silently and isolated:
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/gen3_screens_more.lua
--   POKEPORT_VERSION=firered POKEPORT_GAME=firered POKEPORT_IDENTITY=pocket-access-finish-firered
--   POKEPORT_ACCESS_SILENT=1
-- GEN3_MORE_ONLY=<section name> runs just that field section (after setup).
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
  local function waitFor(label, fn, budget)
    for _ = 1, budget or 900 do
      local ok, value = pcall(fn)
      if ok and value then return true end
      wait(1)
    end
    U.log("WAIT-TIMEOUT", label)
    return false
  end
  local only = os.getenv("GEN3_MORE_ONLY")
  if only == "" then only = nil end
  local function section(label, fn)
    if only and only ~= label and label ~= "setup" then return end
    U.log("SECTION", label)
    local ok, err = pcall(fn)
    if not ok then U.log("FAIL", label .. ": " .. tostring(err)) end
    wait(20)
  end
  local function messageOpen()
    local Message = package.loaded["src.ui.game3.message"]
    local Choice = package.loaded["src.ui.game3.choice"]
    return (Message and Message.open) or (Choice and Choice.active)
  end
  local function settle(budget)
    for _ = 1, budget or 60 do
      if not messageOpen() then break end
      tap("a", 20)
    end
  end
  local function closeAll()
    local Stack = require("src.ui.game3.stack")
    for _ = 1, 12 do
      if not Stack.top() and not messageOpen() then return end
      tap("b", 25)
    end
  end

  -- ------------------------------------------------------------ boot
  waitFor("boot", function() return game.phase == "boot" and game.boot end, 900)
  local boot = game.boot
  if not only or only == "gift" then
    U.log("SECTION", "gift")
    local ok, err = pcall(function()
      waitFor("intro scenes", function()
        return boot.introMovie and boot.introMovie.phase == "intro" and boot.introMovie.ptr
          and boot.introMovie.ptr.cb == "Scene1"
      end, 1500)
      wait(30)
      tap("start", 20)
      local Title = package.loaded["src.ui.game3.title_screen"]
      waitFor("title", function() return boot.title and Title and boot.title.scene == Title.SCENE.RUN end, 1500)
      wait(30)
      -- harness: CONTINUE rows, so MYSTERY GIFT is listed (a save exists)
      boot.hasContinue = true
      tap("start", 20)
      waitFor("menu", function()
        return boot.phase == "menu" and not (boot.menuFade and boot.menuFade:fadeActive())
      end, 600)
      wait(20)
      local Boot = package.loaded["src.ui.game3.boot"]
      for _ = 1, 4 do
        if Boot.menuItems(boot)[boot.menuIndex] == "MYSTERY GIFT" then break end
        tap("down", 20)
      end
      tap("a", 20)
      waitFor("gift", function() return boot.phase == "mystery_gift" and boot.gift end, 300)
      -- harness: the wireless search answers "offline" without a network call
      boot.gift.fetchOpts = { client = { send = function() return nil end } }
      wait(40)
      U.log("GIFT ROWS", table.concat(boot.gift.rows or {}, " / "))
      tap("down", 20)
      tap("up", 20)                   -- WONDER NEWS (WONDER CARDS is listed once enabled)
      tap("a", 30)                    -- the news branch: "don't have any" message
      waitFor("gift message shown", function() return boot.gift.msg and boot.gift.msg.revealed >= boot.gift.msg.total end, 600)
      tap("a", 30)                    -- searching, then offline
      waitFor("offline message", function()
        return boot.gift.msg and boot.gift.state == "result_msg"
      end, 300)
      waitFor("offline shown", function() return boot.gift.msg and boot.gift.msg.revealed >= boot.gift.msg.total end, 600)
      tap("a", 30)                    -- back to the menu
      wait(30)
      tap("b", 40)                    -- exit to the boot menu
      waitFor("boot menu again", function() return boot.phase == "menu" end, 300)
      wait(40)
      boot.hasContinue = false
    end)
    if not ok then U.log("FAIL", "gift: " .. tostring(err)) end
  end
  if only == "gift" then Speech.say = say U.log("DONE") return end

  -- ------------------------------------------------------------ new game
  wait(60)
  local ok, err = pcall(function() game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 }) end)
  if not ok then U.log("FAIL", "new game: " .. tostring(err)) return end
  wait(120)
  settle(60)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local C = require("src.core.game3.constants")
  local Stack = require("src.ui.game3.stack")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local session = Runtime.getSession()
  if not session then U.log("FAIL", "no session") return end
  local consts = C.active(session)
  local function item(name) return consts:require("items", name) end
  local function top() local l = Stack.top() return l and l.id end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    if game.session then game.session.x, game.session.y, game.session.facing = x, y, facing or "up" end
    wait(90)
  end
  local function scriptBusy()
    return messageOpen() or (Space.vm and Space.vm:isRunning())
  end

  -- Moves a list cursor with up/down taps until `at()` holds.
  local function cursorTo(at, budget)
    for _ = 1, budget or 20 do
      if at() then return true end
      tap("down", 12)
    end
    return at()
  end
  local function indexOf(list, want)
    for i, v in ipairs(list or {}) do
      local label = type(v) == "table" and (v.action or v.label or v.name or v.id) or v
      if label == want then return i end
    end
  end

  section("setup", function()
    session.party = {}
    local _, _, chansey = Party.giveMon(session, 113, 40)          -- CHANSEY
    local _, _, pidgey = Party.giveMon(session, 16, 12, "BIRDY")    -- PIDGEY, nicknamed
    local _, _, bulba = Party.giveMon(session, 1, 10)               -- BULBASAUR
    Party.giveMon(session, 19, 6)                                    -- RATTATA, for the box
    if chansey and chansey.moves then
      local first = chansey.moves[1]
      chansey.moves[1] = type(first) == "table" and { id = 135, pp = 10 } or 135 -- SOFTBOILED
    end
    if pidgey then pidgey.item = item("ITEM_POTION") end
    if bulba then bulba.hp = 5 end
    Bag.add(session.bag, item("ITEM_TM_CASE"), 1)
    Bag.add(session.bag, item("ITEM_BERRY_POUCH"), 1)
    Bag.add(session.bag, item("ITEM_TM06"), 1)
    Bag.add(session.bag, item("ITEM_CHERI_BERRY"), 2)
    Bag.add(session.bag, item("ITEM_RARE_CANDY"), 2)
    Bag.add(session.bag, item("ITEM_MASTER_BALL"), 2)
    Bag.add(session.bag, item("ITEM_POTION"), 2)
    session.money = 5000
    -- RATTATA into BOX 1 for MOVE in storage
    local Storage = require("src.core.game3.storage")
    Storage.ensure(session)
    local okDep, why = pcall(Storage.deposit, session, 4, 1, 1)
    U.log("SETUP", "party " .. #session.party .. ", box deposit " .. tostring(okDep) .. " " .. tostring(why))
  end)

  section("bag cases", function()
    local BagMenu = require("src.ui.game3.bag_menu")
    BagMenu.show(session.bag, { session = session })
    wait(40)
    for _ = 1, 4 do
      if BagMenu.currentPocket() == "KEY_ITEMS" then break end
      tap("right", 30)
    end
    U.log("POCKET", tostring(BagMenu.currentPocket()))
    local function rowIs(id)
      return function()
        local row = (BagMenu.list() or {})[BagMenu.cursor]
        return row and (row.id == id or row.id == item("ITEM_" .. id))
      end
    end
    cursorTo(rowIs("TM_CASE"))
    tap("a", 20)                      -- action menu: USE first
    U.log("ACTIONS", table.concat(BagMenu.ACTIONS or {}, " / "))
    tap("a", 60)                      -- USE: the TM case opens over the bag
    U.log("TOP", tostring(top()))
    tap("down", 15)
    tap("up", 15)
    tap("b", 60)                      -- back to the bag
    U.log("TOP", tostring(top()))
    cursorTo(rowIs("BERRY_POUCH"))
    tap("a", 20)
    tap("a", 60)                      -- USE: the berry pouch
    U.log("TOP", tostring(top()))
    tap("down", 15)
    tap("b", 60)
    U.log("TOP", tostring(top()))
    closeAll()
  end)

  local function openParty(opts)
    local PartyMenu = require("src.ui.game3.party_menu")
    local o = { session = session, bag = session.bag }
    for k, v in pairs(opts or {}) do o[k] = v end
    PartyMenu.show(session.party, nil, o)
    wait(30)
    return PartyMenu
  end
  local function partyTo(PartyMenu, slot)
    for _ = 1, 8 do
      if PartyMenu.cursor == slot then return end
      tap(PartyMenu.cursor < slot and "down" or "up", 12)
    end
  end
  local function actionTo(PartyMenu, want)
    local idx = indexOf(PartyMenu.ACTIONS, want)
    U.log("ACTIONS", tostring(want) .. " at " .. tostring(idx))
    if not idx then return false end
    for _ = 1, 8 do
      if PartyMenu.actionCursor == idx then return true end
      tap("down", 12)
    end
    return PartyMenu.actionCursor == idx
  end

  section("take", function()
    local PartyMenu = openParty()
    partyTo(PartyMenu, 2)             -- BIRDY holds a POTION
    tap("a", 20)
    if actionTo(PartyMenu, "ITEM") then
      tap("a", 20)                    -- GIVE / TAKE / CANCEL
      tap("down", 15)
      tap("a", 40)                    -- TAKE: "Received the POTION from BIRDY."
      tap("a", 30)
    end
    closeAll()
  end)

  section("softboiled", function()
    local PartyMenu = openParty()
    partyTo(PartyMenu, 1)             -- CHANSEY
    tap("a", 20)
    if actionTo(PartyMenu, "SOFTBOILED") then
      tap("a", 30)                    -- target mode
      U.log("MODE", tostring(PartyMenu.mode))
      tap("down", 15)
      tap("down", 15)                 -- BULBASAUR
      tap("a", 60)                    -- HP moves over, message
      for _ = 1, 4 do
        if PartyMenu.mode ~= "message" then break end
        tap("a", 30)
      end
    end
    closeAll()
  end)

  section("level up", function()
    local PartyMenu = openParty({ item = item("ITEM_RARE_CANDY"), mode = "use" })
    partyTo(PartyMenu, 3)
    tap("a", 90)                      -- grew to level 11, then the window
    for _ = 1, 8 do
      if not PartyMenu.open then break end
      U.log("MODE", tostring(PartyMenu.mode))
      tap("a", 40)
    end
    closeAll()
  end)

  section("teachy demos", function()
    local TvUi = require("src.ui.game3.teachy_tv")
    local TmCase = require("src.ui.game3.tm_case")
    TvUi.show(session, session.bag)
    wait(90)
    local TeachyTv = require("src.core.game3.teachy_tv")
    for _ = 1, 6 do
      local row = TeachyTv.ORDER[TvUi.cursor or 1]
      if row == TeachyTv.SCRIPT.TMS then break end
      tap("down", 15)
    end
    U.log("LESSON", tostring(TvUi.cursor))
    tap("a", 60)
    local lastTop
    for _ = 1, 9000 do
      local t = top()
      if t ~= lastTop then U.log("TOP", tostring(t)) lastTop = t end
      if TvUi.state == "list" and t == "teachy_tv" then break end
      if TvUi.waitingForKey and t == "teachy_tv" and TvUi.waitingForKey() then
        tap("a", 20)
      elseif t == "teachy_pokedude_tm_case" and TmCase.mode == "message" then
        wait(40)
        tap("a", 20)
      else
        wait(1)
      end
    end
    U.log("TEACHY", tostring(TvUi.state), tostring(top()))
    tap("b", 90)
    if TvUi.open then TvUi.finishClose() end
    closeAll()
  end)

  section("pokedex habitat", function()
    local Dex = require("src.core.game3.dex")
    session.dex = session.dex or Dex.new()
    for _, sp in ipairs({ 1, 16, 19, 113, 10, 13 }) do pcall(Dex.setSeen, session.dex, sp, true) end
    for _, sp in ipairs({ 16, 113 }) do pcall(Dex.setCaught, session.dex, sp, true) end
    local Pokedex = require("src.ui.game3.pokedex")
    Pokedex.show(session.dex, { session = session })
    wait(40)
    cursorTo(function()
      local m = Pokedex.MODES and Pokedex.MODES[Pokedex.modeCursor]
      return m and m.type == "habitat" and m.unlocked
    end, 14)
    tap("a", 40)                      -- habitat page
    U.log("DEX", tostring(Pokedex.screen), tostring(Pokedex.currentCategory))
    tap("right", 20)
    tap("left", 20)
    tap("a", 40)                      -- the entry from the habitat page
    tap("b", 30)
    tap("b", 30)                      -- table of contents
    tap("down", 15)
    tap("a", 40)                      -- the next habitat (locked ones say so)
    tap("b", 30)
    tap("b", 40)
    closeAll()
  end)

  section("storage", function()
    local Box = require("src.ui.game3.box_storage_ui")
    Box.show({ session = session, subMode = "move" })
    wait(60)
    tap("a", 20)                      -- RATTATA in slot 1: action menu
    U.log("BOX", tostring(Box.mode), table.concat(Box._activeActions or {}, " / "))
    local idx = indexOf(Box._activeActions, "MOVE")
    if idx then
      for _ = 1, 6 do
        if Box.actionCursor == idx then break end
        tap("down", 12)
      end
      tap("a", 25)                    -- holding RATTATA
      tap("right", 15)
      tap("a", 25)                    -- placed in slot 2
    end
    tap("up", 15)                     -- box title
    tap("a", 20)                      -- SWITCH BOX / WALLPAPER / CANCEL
    tap("down", 15)
    tap("a", 25)                      -- wallpaper list
    U.log("BOX", tostring(Box.mode))
    tap("down", 15)
    tap("down", 15)
    tap("b", 25)
    tap("b", 25)
    tap("b", 40)
    closeAll()
  end)

  section("fly map", function()
    -- harness: Pallet Town and Viridian City visited
    Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, 0x890, true)
    Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, 0x891, true)
    local RegionMap = require("src.ui.game3.region_map")
    RegionMap.show({ session = session, mode = "fly" })
    wait(120)
    for _ = 1, 4 do tap("up", 15) end
    for _ = 1, 4 do tap("down", 15) end
    tap("b", 60)
    closeAll()
  end)

  section("clerk shop", function()
    local ShopMenu = require("src.ui.game3.shop_menu")
    goTo("FR_PEWTER_CITY_MART", 4, 6, "up")
    local Objects = require("src.core.game3.objects")
    local clerk
    for _, d in ipairs(Objects._defs or {}) do
      if d.sprite == "SPRITE_CLERK" then clerk = d end
    end
    if not clerk then U.log("FAIL", "no clerk on " .. tostring(Map.current)) return end
    goTo("FR_PEWTER_CITY_MART", clerk.x + 1, clerk.y, "left")
    tap("a", 20)
    for _ = 1, 80 do
      if ShopMenu.open then break end
      if scriptBusy() then tap("a", 15) else wait(5) end
    end
    U.log("SHOP", tostring(ShopMenu.open), tostring(top()))
    wait(30)
    tap("down", 15)
    tap("up", 15)
    tap("a", 60)                      -- BUY list
    tap("down", 15)
    tap("b", 60)
    tap("b", 40)                      -- QUIT
    for _ = 1, 30 do
      if not scriptBusy() and not Stack.top() then break end
      if messageOpen() then tap("a", 15) else wait(5) end
    end
    closeAll()
  end)

  section("prize corner", function()
    local Prize = require("src.ui.game3.prize_corner")
    Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, 0x243, true) -- FLAG_GOT_COIN_CASE
    Bag.Coins.set(session, 4000)
    goTo("FR_CELADON_CITY_GAME_CORNER_PRIZE_ROOM", 6, 4, "up")
    tap("a", 20)
    for _ = 1, 100 do
      if Prize.isOpen() then break end
      if scriptBusy() then tap("a", 10) else wait(10) end
    end
    U.log("PRIZE", tostring(Prize.isOpen()), tostring(top()))
    tap("down", 20)
    tap("down", 20)
    tap("up", 20)
    tap("a", 30)                      -- a prize: the confirmation
    for _ = 1, 4 do
      if not messageOpen() then break end
      tap("b", 30)                    -- NO
    end
    tap("b", 30)
    for _ = 1, 30 do
      if not scriptBusy() and not Stack.top() then break end
      if messageOpen() then tap("b", 15) else wait(5) end
    end
    closeAll()
  end)

  -- ------------------------------------------------------------ battles
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local BUi = require("src.core.game3.battle.ui")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local function inBattle() return Battle.isActive() end
  local function atMenu() return inBattle() and Battle._phase == "command" and BUi._mode == "menu" end
  local function menuTo(index)
    for _ = 1, 4 do
      local c = (BUi._menuIndex or 1) - 1
      local want = index - 1
      if c == want then break end
      if c % 2 ~= want % 2 then tap(c % 2 == 0 and "right" or "left", 12)
      else tap(c < 2 and "down" or "up", 12) end
    end
  end
  local function boxWaits()
    return Message.isOpen() and Message.isWaiting() and not Message.isHeld()
  end
  -- Runs the battle until `stop()`, pressing A on waiting boxes, NO on
  -- questions, B out of naming; a party or Pokédex layer is logged and left
  -- the way `onLayer(id)` says (default B).
  local function runBattle(stop, onLayer, budget)
    for _ = 1, budget or 6000 do
      if stop() then return true end
      local t = top()
      if Choice.active then
        wait(30)
        if Choice.cursor == 1 then tap("down", 15) end
        tap("a", 20)
      elseif t then
        if not (onLayer and onLayer(t)) then
          if t == "naming" then
            tap("start", 20)          -- to OK, then confirm the empty name
            tap("a", 40)
          else
            tap("b", 30)
          end
        end
      elseif boxWaits() then
        wait(20)
        tap("a", 6)
      elseif atMenu() then
        menuTo(1)
        tap("a", 20)
        tap("a", 20)                  -- first move
        if BUi._mode == "target" then tap("a", 20) end
      else
        wait(1)
      end
    end
    return stop()
  end

  section("catch registration", function()
    local started, why = pcall(BattleBridge.startWild, Runtime._mod, game, { species = 10, level = 3 }, { fade = false })
    if not started or why == false then U.log("FAIL", "wild battle: " .. tostring(why)) return end
    runBattle(function() return atMenu() end, nil, 3000)
    -- throw a MASTER BALL the way upstream's catch drivers do
    BUi._pendingCommand = { kind = "bag", itemId = item("ITEM_MASTER_BALL"), user = "player" }
    BUi._mode = "none"
    local seenDex = false
    runBattle(function() return not inBattle() and not Stack.top() and not messageOpen() end, function(t)
      if t == "pokedex" then
        if not seenDex then
          seenDex = true
          local Pokedex = require("src.ui.game3.pokedex")
          U.log("DEX", tostring(Pokedex.mode), tostring(Pokedex.screen))
          wait(90)
          tap("a", 40)                -- page 2
          wait(30)
        end
        tap("b", 40)
        return true
      end
      return false
    end, 6000)
    U.log("CATCH", "dex page seen " .. tostring(seenDex))
    closeAll()
  end)

  section("double party", function()
    local PartyMenu = require("src.ui.game3.party_menu")
    session.party = {}
    Party.giveMon(session, 6, 60)                                    -- CHARIZARD
    Party.giveMon(session, 9, 60)                                    -- BLASTOISE
    Party.giveMon(session, 3, 60)                                    -- VENUSAUR
    local okStart, why = pcall(BattleBridge.start, Runtime._mod, game,
      { trainerId = 484, party = { { species = 19, level = 8 }, { species = 16, level = 8 } } },
      { wild = false, trainerId = 484, double = true, fade = false })
    if not okStart or why == false then U.log("FAIL", "double battle: " .. tostring(why)) return end
    for _ = 1, 600 do if inBattle() then break end wait(1) end
    -- to the first command menu, pressing A only on the opening lines (the
    -- menu's own prompt box also waits, and A there would choose FIGHT)
    for _ = 1, 3000 do
      if atMenu() then break end
      if boxWaits() and BUi._mode ~= "menu" then wait(20) tap("a", 6) else wait(1) end
    end
    wait(60)                           -- the menu takes input once its prompt is up
    -- an A queued on the last opening line can land on the menu: back out
    if BUi._mode == "moves" then tap("b", 30) end
    menuTo(3)                          -- POKéMON
    U.log("MENU", tostring(BUi._menuIndex), tostring(BUi._mode))
    tap("a", 60)
    U.log("TOP", tostring(top()), tostring(PartyMenu.mode))
    tap("down", 15)
    tap("down", 15)
    tap("a", 25)                      -- VENUSAUR: SHIFT / SUMMARY / CANCEL
    tap("down", 15)
    tap("b", 25)
    tap("b", 40)                      -- back to the battle menu
    runBattle(function() return not inBattle() and not messageOpen() end, nil, 6000)
    closeAll()
  end)

  Speech.say = say
  U.log("DONE")
end
