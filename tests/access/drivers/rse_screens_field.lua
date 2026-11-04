-- Field screens in Emerald, Ruby and Sapphire: decorating, mail, word entry, the
-- casino, the move tutor, scenes, day-care menus and link windows.  Screens open
-- by their own map scripts where a section says so, otherwise through the module
-- and options their native caller uses.  Asserts nothing; logs SCREEN, SAID, BAD.
-- RSE_ONLY (a comma list of section names) limits a run.
return function(game)
  local L = dofile("tests/access/drivers/rse_menus_lib.lua")(game)
  local tap, taps, wait, waitFor = L.tap, L.taps, L.wait, L.waitFor

  local only
  if os.getenv("RSE_ONLY") then
    only = {}
    for name in os.getenv("RSE_ONLY"):gmatch("[^,]+") do only[name] = true end
  end
  local function section(label, fn)
    if only and not only[label] then return end
    L.section(label, fn)
  end

  waitFor("boot", function() return game.phase == "boot" and game.boot end, 900)
  wait(60)
  if os.getenv("RSE_TITLE") then
    -- The title's own button combos, held as a player holds them (rse/title_rse.lua phase3).
    local Top = require("src.access.screens.gen3.Top")
    local function kind()
      local ok3, top = pcall(Top.resolve, game)
      return ok3 and top and top.gen3 or nil
    end
    tap("start", 30)
    waitFor("title", function() return kind() == "hoenn_title" and game.boot.custom.title.phase == "phase3" end, 1800)
    L.log("TITLE", tostring(kind()))
    local combo = os.getenv("RSE_TITLE")
    local keys = { clear = { "b", "select", "up" }, rtc = { "b", "select", "left" }, berry = { "b", "select" } }
    for _, key in ipairs(keys[combo]) do game.input.state[key] = true end
    wait(4)
    for _, key in ipairs(keys[combo]) do game.input.state[key] = false end
    wait(60)
    L.log("COMBO", tostring(kind()))
    if combo == "clear" then
      wait(60)
      taps({ "up", "down" }, 20)        -- ends on NO, the row it opens on
      tap("a", 60)                      -- NO: the save stays
      wait(120)
    elseif combo == "rtc" then
      wait(60)
      tap("a", 30)                      -- prompt: go on to set the time
      wait(30)
      taps({ "up", "up", "down", "right", "up", "left", "left", "up" }, 16)
      taps({ "right", "right", "right", "right" }, 16)
      tap("a", 90)                      -- CONFIRM (a disposable save)
      wait(60)
      tap("a", 90)
    else
      wait(30)
      tap("a", 30)
      tap("a", 30)
      tap("b", 60)
    end
    wait(60)
    L.log("END", tostring(kind()))
    L.log("DONE", "rse_screens_field")
    love.event.quit()
    return
  end
  local ok, err = pcall(function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  if not ok then L.log("FAIL", "new game: " .. tostring(err)) love.event.quit() return end
  wait(120)
  L.talk(40)
  wait(60)

  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local C = require("src.core.game3.constants")
  local Stack = require("src.ui.game3.stack")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local MapIds = require("src.core.game3.map_ids")
  local Profile = require("src.core.game3.profile")
  local Screens = require("src.ui.game3.screens")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local session = L.session()
  local consts = C.active(session)
  local isRs = Profile.forSession(session).id ~= "emerald"
  local function item(name) return consts:require("items", name) end

  session.party = {}
  Party.giveMon(session, consts:require("species", "SPECIES_MUDKIP"), 30)
  Party.giveMon(session, consts:require("species", "SPECIES_ZIGZAGOON"), 8, "ZIGGY")
  L.flag(session, "FLAG_SYS_POKEMON_GET")

  local function goTo(const, x, y, facing)
    L.closeAll()
    local mapId = MapIds.forConst(const)
    L.log("GOTO", tostring(const) .. " " .. tostring(mapId))
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    local s = L.session()
    s.x, s.y, s.facing = x, y, facing
    Player.cellX, Player.cellY, Player.px, Player.py = x, y, x * 16, y * 16
    Player.targetX, Player.targetY, Player.facing = x, y, facing
    wait(40)
  end

  -- A through dialogue until `pred`; returns whether it held.
  local function mashUntil(pred, budget)
    for _ = 1, budget or 40 do
      if pred() then return true end
      if Message.open and Message.isWaiting and Message.isWaiting() then tap("a", 12) else wait(6) end
    end
    return pred()
  end

  -- ------------------------------------------------------------ decorating

  local function decor(name) return consts:require("decorations", name) end
  local function giveDecor()
    local Inv = require("src.core.game3.rse.decoration_inventory")
    Inv.clear(session)
    for _, name in ipairs({ "DECOR_SMALL_DESK", "DECOR_PICHU_DOLL", "DECOR_PIKA_POSTER", "DECOR_PIKACHU_DOLL", "DECOR_RED_TENT" }) do
      local ok2, id = pcall(decor, name)
      if ok2 then Inv.add(id, session) else L.log("NODECOR", name) end
    end
  end

  local function decorUi() return require("src.ui.game3.rse.decoration") end
  local function walkMode(keys)
    for _, key in ipairs(keys) do tap(key, 22) end
  end

  -- The bedroom PC by its own script (decorating there takes dolls and cushions).
  local function bedroomDecorate()
    local UI = decorUi()
    local function until_(state, budget)
      return waitFor("decor " .. state, function() return UI.state == state end, budget or 300)
    end
    taps({ "down", "up" }, 16)
    tap("a", 20)                        -- DECORATE
    taps({ "down", "up" }, 16)
    tap("a", 20)                        -- DESK: not for this room
    tap("a", 20)                        -- SMALL DESK
    until_("wait_press")
    tap("a", 20)
    until_("items")
    tap("b", 20)                        -- categories
    for _ = 1, 6 do tap("down", 14) end
    tap("a", 20)                        -- DOLL
    taps({ "down", "up" }, 16)
    tap("a", 30)                        -- PICHU DOLL
    until_("place")
    L.log("TOP", tostring(UI.state))
    walkMode({ "left", "up", "right", "down" })
    tap("a", 30)
    waitFor("placed?", function() return UI.state == "yesno" or UI.state == "wait_press" end, 300)
    L.log("STATE", tostring(UI.state))
    if UI.state == "wait_press" then tap("a", 30) else tap("b", 30) end
    until_("place")
    tap("b", 30)                        -- stop decorating?
    until_("yesno")
    taps({ "down", "up" }, 16)
    tap("a", 40)
    until_("items")
    tap("b", 20)
    tap("b", 20)
    L.log("STATE", tostring(UI.state))
    tap("down", 16)                     -- PUT AWAY: nothing is out yet
    tap("a", 30)
    until_("wait_press")
    tap("a", 30)
    until_("actions")
    tap("down", 16)                     -- TOSS
    tap("a", 20)
    tap("a", 20)                        -- DESK
    tap("a", 30)                        -- toss the desk?
    until_("yesno")
    taps({ "down", "up", "down" }, 16)
    tap("a", 40)                        -- NO
    until_("items")
    tap("a", 30)                        -- again
    until_("yesno")
    tap("a", 40)                        -- YES
    until_("wait_press")
    tap("a", 30)
    tap("b", 20)
    tap("b", 20)
    tap("b", 40)                        -- out to the PC
  end

  section("decor_room", function()
    giveDecor()
    local house = isRs and "MAP_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F" or "MAP_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F"
    goTo(house, 0, 2, "up")
    tap("a", 30)
    local PcMenu = require("src.ui.game3.pc_menu")
    mashUntil(function() return PcMenu.isOpen() end, 60)
    L.log("PC", tostring(PcMenu.isOpen()) .. " " .. tostring(L.top()))
    for _ = 1, 3 do tap("down", 16) end
    L.log("MODE", tostring(PcMenu.mode))
    if not PcMenu.isOpen() then return end
    local order = require("src.ui.game3.rse.player_pc").topOrder(PcMenu)
    local want
    for i, id in ipairs(order) do if id == "decoration" then want = i end end
    for _ = 1, 6 do
      if PcMenu.cursor == want then break end
      tap("up", 14)
    end
    L.log("CURSOR", tostring(PcMenu.cursor) .. " want " .. tostring(want))
    tap("a", 40)
    L.log("TOP", tostring(L.top()))
    if L.top() == "rse_decoration" then bedroomDecorate() end
    L.closeAll()
    wait(40)
    L.talk(10)
  end)

  section("decor_base", function()
    -- rse/secret_base.lua's PC script calls ui.open({ isPlayerRoom = false }).
    giveDecor()
    goTo("MAP_SECRET_BASE_YELLOW_CAVE2", 5, 5, "up")
    local SB = require("src.core.game3.rse.secret_base")
    local mid = consts:require("metatile_labels", "METATILE_SecretBase_PC")
    local pcX, pcY = SB.findMetatile(SB.fieldGrid(), mid)
    L.log("PCCELL", tostring(pcX) .. "," .. tostring(pcY))
    local UI = decorUi()
    local mod = Screens.get("decoration", session) or UI
    mod.open({ isPlayerRoom = false, session = session })
    wait(30)
    L.log("TOP", tostring(L.top()))
    taps({ "down", "down", "down", "up", "up", "up" }, 16)
    tap("a", 20)                        -- DECORATE
    tap("a", 20)                        -- DESK
    tap("a", 30)                        -- SMALL DESK
    waitFor("place", function() return UI.state == "place" end, 120)
    walkMode({ "left", "left", "down", "up", "right" })
    tap("a", 30)
    wait(90)
    L.log("STATE", tostring(UI.state))
    if UI.state == "wait_press" then
      tap("a", 30)                      -- can't be placed; try elsewhere
      for _, key in ipairs({ "down", "down", "left", "left" }) do
        tap(key, 22)
        tap("a", 30)
        wait(90)
        if UI.state == "yesno" then break end
        if UI.state == "wait_press" then tap("a", 30) end
      end
    end
    L.log("STATE", tostring(UI.state))
    if UI.state == "yesno" then
      taps({ "down", "up" }, 16)
      tap("a", 90)                      -- YES: placed
    end
    waitFor("items", function() return UI.state == "items" end, 240)
    tap("b", 20)
    tap("b", 20)
    L.log("STATE", tostring(UI.state))
    tap("down", 16)                     -- PUT AWAY
    tap("a", 30)
    waitFor("putaway", function() return UI.state == "putaway" end, 240)
    local b = session.secretBases[1]
    local Decor = require("src.core.game3.rse.decoration")
    local px, py = Decor.decodePos(b.decorationPositions[1])
    L.log("PLACED", tostring(px) .. "," .. tostring(py) .. " at " .. tostring(UI.mode and UI.mode.x) .. "," .. tostring(UI.mode and UI.mode.y))
    local function toward(axis, key, back, target)
      for _ = 1, 16 do
        local m = UI.mode
        if not m or m[axis] == target then return end
        tap(m[axis] < target and back or key, 22)
      end
    end
    tap("up", 22)
    tap("left", 22)
    toward("x", "left", "right", px)
    toward("y", "up", "down", py)
    tap("a", 30)                        -- put it away?
    wait(90)
    taps({ "down", "up" }, 16)
    tap("a", 120)                       -- YES
    wait(120)
    tap("a", 30)
    tap("b", 30)
    wait(60)
    taps({ "down", "up" }, 16)
    tap("a", 120)                       -- stop putting away
    waitFor("actions", function() return UI.state == "actions" end, 300)
    L.log("STATE", tostring(UI.state))
    L.closeAll(3)
    wait(30)
    L.talk(10)
    L.closeAll()
  end)

  section("decor_shop", function()
    -- The pokemartdecoration script command: ShopMenu with martType "DECOR".
    local ShopMenu = require("src.ui.game3.shop_menu")
    session.money = 50000
    local ids = { decor("DECOR_SMALL_DESK"), decor("DECOR_PICHU_DOLL") }
    ShopMenu.show({ items = ids, martType = "DECOR", session = session, onClose = function() end })
    wait(60)
    L.log("TOP", tostring(L.top()))
    tap("a", 60)                        -- BUY
    taps({ "down", "up" }, 16)
    tap("a", 40)                        -- SMALL DESK
    wait(60)
    taps({ "down", "up" }, 16)
    tap("b", 40)
    wait(30)
    tap("b", 40)
    wait(30)
    tap("b", 40)
    L.closeAll()
  end)

  -- ------------------------------------------------------------------ mail

  local function mailItem() return item("ITEM_ORANGE_MAIL") end

  section("mail", function()
    local Mail = require("src.core.game3.mail")
    local pool = Mail.pool(session)
    local Easy = require("src.core.game3.easy_chat_text")
    local words = {}
    for i = 1, 9 do words[i] = Easy.encodeWord(1, (i % 5)) end
    for i = 0, 1 do
      local rec = pool[Mail.PARTY_SIZE + 1 + i]
      rec.itemId, rec.playerName = mailItem(), i == 0 and "BRENDA" or "ROXIE"
      rec.species = 258
      rec.words = {}
      for k = 1, 9 do rec.words[k] = words[k] end
    end
    local Mailbox = require("src.ui.game3.rse.mailbox")
    goTo("MAP_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", 0, 2, "up")
    tap("a", 30)
    local PcMenu = require("src.ui.game3.pc_menu")
    mashUntil(function() return PcMenu.isOpen() end, 60)
    if not PcMenu.isOpen() then return end
    local order = require("src.ui.game3.rse.player_pc").topOrder(PcMenu)
    local want
    for i, id in ipairs(order) do if id == "mailbox" then want = i end end
    for _ = 1, 6 do
      if PcMenu.cursor == want then break end
      tap("down", 14)
    end
    tap("a", 40)
    L.log("TOP", tostring(L.top()))
    taps({ "down", "down", "up", "up" }, 14)
    tap("a", 20)                        -- options
    taps({ "down", "up" }, 14)
    tap("a", 40)                        -- READ
    L.log("TOP", tostring(L.top()))
    wait(40)
    tap("a", 60)
    L.log("TOP", tostring(L.top()) .. " " .. tostring(Mailbox.state))
    tap("a", 20)                        -- options again
    tap("down", 14)
    tap("a", 30)                        -- MOVE TO BAG
    tap("a", 30)
    taps({ "down", "up", "down" }, 14)
    tap("a", 30)                        -- NO
    tap("a", 20)
    tap("down", 14)
    tap("a", 30)
    tap("a", 30)                        -- YES
    tap("up", 14)
    tap("a", 40)                        -- erased: back to the list
    L.log("STATE", tostring(Mailbox.state))
    tap("a", 20)
    taps({ "down", "down" }, 14)
    tap("a", 40)                        -- GIVE
    L.log("TOP", tostring(L.top()))
    tap("b", 40)
    L.log("STATE", tostring(Mailbox.state))
    L.closeAll()
    wait(20)
    L.talk(10)
  end)

  section("mailparty", function()
    -- A Pokémon holding mail: the party's READ, and giving mail from the bag.
    local Mail = require("src.core.game3.mail")
    local mon = session.party[1]
    mon.item, mon.heldItem = 0, 0
    local Easy = require("src.core.game3.easy_chat_text")
    local PartyMenu = require("src.ui.game3.party_menu")
    Mail.giveMailToMon(session, mon, mailItem())
    local rec = Mail.get(session, mon.mail)
    if rec then
      rec.playerName = "MAY"
      rec.words = {}
      for k = 1, 9 do rec.words[k] = Easy.encodeWord(2, k % 4) end
    end
    if isRs then
      L.log("READMAIL", tostring(require("src.ui.game3.rs.party_menu_data").readMail ~= nil))
    end
    if rec then
      local reader = isRs and require("src.ui.game3.rs.mail_reader") or require("src.ui.game3.rse.mail")
      local closed
      reader.read(rec, { session = session, onClose = function() closed = true end })
      wait(50)
      L.log("TOP", tostring(L.top()))
      tap("a", 60)
      waitFor("mail closed", function() return closed end, 90)
    end
    Mail.takeMailFromMon(session, mon)
    mon.item, mon.heldItem = 0, 0
    L.log("PARTY", tostring(PartyMenu ~= nil))
  end)

  -- ------------------------------------------------------------- word entry

  local function pressWords(mod, finish)
    -- phrase: down, up; A opens groups; right, down; A opens words; right; A chooses
    waitFor("input", function() return mod._state == "input" end, 120)
    wait(10)
    taps({ "right", "left" }, 16)
    tap("a", 30)
    waitFor("groups", function() return mod._view == "groups" and not mod._transition end, 120)
    wait(10)
    taps({ "right", "down", "up", "left" }, 18)
    tap("select", 10)                   -- by letter
    waitFor("alpha", function() return mod._view == "groups" and not mod._transition and mod._group.alpha end, 120)
    wait(10)
    taps({ "right", "down" }, 18)
    tap("select", 10)                   -- by group again
    waitFor("group", function() return mod._view == "groups" and not mod._transition and not mod._group.alpha end, 120)
    wait(10)
    tap("right", 18)
    tap("right", 18)                    -- the side buttons
    taps({ "down", "down" }, 18)
    tap("right", 18)
    tap("a", 30)                        -- first group's words
    waitFor("words", function() return mod._view == "words" and not mod._transition end, 120)
    wait(10)
    taps({ "right", "down" }, 18)
    tap("a", 30)
    waitFor("phrase", function() return mod._view == "phrase" and not mod._transition end, 120)
    wait(20)
    tap("start", 18)                    -- OK
    taps({ "left", "left" }, 18)        -- DEL. ALL
    tap("a", 30)
    taps({ "down", "up" }, 18)
    tap("b", 30)
    tap("right", 18)
    tap("a", 30)                        -- CANCEL's question
    taps({ "down" }, 18)
    tap("a", 30)                        -- NO
    tap("right", 18)
    tap("a", 30)                        -- OK: save question or a refusal
    wait(30)
    finish()
  end

  section("rs_words", function()
    if not isRs then return end
    local Contracts = require("src.core.game3.rs.easy_chat_contracts")
    local Editor = require("src.ui.game3.rs.easy_chat_editor")
    for _, kind in ipairs({ 0, 13, 6 }) do
      L.log("KIND", tostring(kind))
      local token = Contracts.prepare(session, kind, { slot = 0, person = 0, variant = 0 })
      local closed
      Editor.show({ type = kind, token = token, words = token.words, session = session, variant = token.variant,
        onDone = function() closed = true end })
      pressWords(Editor, function()
        for _ = 1, 3 do
          tap("b", 25)
        end
        if Editor._confirm then tap("down", 18) end
        tap("b", 25)
        tap("b", 25)
      end)
      for _ = 1, 6 do
        if closed then break end
        if Editor._confirm and Editor._confirm.kind ~= "save" then
          Editor._confirm.cursor = Editor._confirm.cursor -- key presses only below
          tap("up", 16)
          tap("a", 30)
        else
          tap("b", 30)
        end
      end
      waitFor("closed", function() return closed end, 90)
      L.log("CLOSED", tostring(closed) .. " " .. tostring(L.top()))
      L.closeAll()
    end
    local Trend = require("src.ui.game3.rs.trendy_phrase")
    local closed
    Trend.show({ session = session, words = { 65535, 65535 }, onDone = function() closed = true end })
    pressWords(Trend, function() end)
    for _ = 1, 6 do
      if closed then break end
      if Trend._confirm and Trend._confirm.kind == "cancel" then tap("up", 16) tap("a", 30) else tap("b", 30) end
    end
    waitFor("closed", function() return closed end, 90)
    L.log("CLOSED", tostring(closed))
    local Composer = require("src.ui.game3.rs.mail_composer")
    closed = nil
    local blank = {}
    for i = 1, 9 do blank[i] = 65535 end
    Composer.write({ words = blank }, { session = session, onClose = function() closed = true end })
    pressWords(Composer, function() end)
    for _ = 1, 6 do
      if closed then break end
      if Composer._confirm and Composer._confirm.kind == "cancel" then tap("up", 16) tap("a", 30) else tap("b", 30) end
    end
    waitFor("closed", function() return closed end, 90)
    L.log("CLOSED", tostring(closed))
    L.closeAll()
  end)

  section("em_words", function()
    if isRs then return end
    -- natives.lua's easy chat native opens this with the profile words.
    local EasyChat = require("src.ui.game3.easy_chat")
    local done
    EasyChat.open({ type = 0, words = { 65535, 65535, 65535, 65535 }, session = session,
      onDone = function() done = true end })
    wait(40)
    L.log("TOP", tostring(L.top()))
    taps({ "right", "down", "up" }, 16)
    tap("a", 30)
    taps({ "right", "down" }, 16)
    tap("a", 30)
    taps({ "down", "right" }, 16)
    tap("a", 30)
    wait(20)
    taps({ "down", "down", "down" }, 16)
    taps({ "right", "right" }, 16)
    tap("a", 30)
    wait(20)
    taps({ "down", "up" }, 16)
    for _ = 1, 8 do
      if done then break end
      tap("b", 30)
      if not done then tap("up", 16) tap("a", 30) end
    end
    L.log("DONE", tostring(done))
    L.closeAll()
  end)

  -- ----------------------------------------------------------------- casino

  local function giveCoins(n)
    Bag.add(session.bag, item("ITEM_COIN_CASE"), 1)
    Bag.Coins.set(session, n)
  end

  section("roulette", function()
    giveCoins(120)
    goTo("MAP_MAUVILLE_CITY_GAME_CORNER", 13, 7, "right")
    tap("a", 30)
    local Base = require("src.ui.game3.rse.roulette")
    mashUntil(function() return Base.Entry._entry and Base.Entry._entry.state == "yesNo" end, 80)
    local e = Base.Entry._entry
    L.log("ENTRY", tostring(e and e.state))
    if not e then return end
    taps({ "down", "up" }, 18)
    tap("a", 60)                        -- YES
    waitFor("roulette", function() return Base.active() ~= nil end, 300)
    local s = Base.active()
    L.log("TOP", tostring(L.top()))
    if not s then return end
    local bets, frames = 0, 0
    while Base.active() and frames < 60 * 240 do
      local task = s.st and s.st.playTaskId and s.m.tasks.t[s.st.playTaskId]
      if task and task.func == s.fn.taskHandleBetGridInput then
        bets = bets + 1
        L.log("BET", bets)
        wait(10)
        taps({ "right", "down", "left", "up" }, 18)
        if bets >= 2 then tap("up", 18) end
        tap("a", 12)
      elseif s.yesNo then
        L.log("YESNO", bets)
        wait(10)
        tap("down", 18)
        if bets < 9 then tap("up", 18) end
        tap("a", 20)
      elseif task and task.func == s.fn.taskWaitForNextTask then
        tap("a", 10)
      else
        wait(1)
      end
      frames = frames + 1
    end
    L.log("FINISHED", tostring(Base.active() == nil) .. " bets " .. bets .. " frames " .. frames)
    wait(60)
    L.talk(10)
    L.closeAll()
  end)

  section("slots", function()
    giveCoins(120)
    goTo("MAP_MAUVILLE_CITY_GAME_CORNER", 4, 7, "left")
    tap("a", 30)
    local Base = require("src.ui.game3.rse.slot_machine")
    mashUntil(function() return Base.active() ~= nil end, 80)
    L.log("TOP", tostring(L.top()))
    local s = Base.active()
    if not s then return end
    local ST = Base.STATE
    local spins, frames, shown, won = 0, 0, false, false
    while Base.active() and frames < 60 * 300 do
      local cs = s.core.state
      if cs == ST.BET_INPUT then
        if not shown then
          shown = true
          wait(20)
          tap("select", 60)
          waitFor("info", function() return s.infoWindow and s.infoWindow.text end, 120)
          wait(30)
          tap("b", 90)
          waitFor("bet", function() return s.core.state == ST.BET_INPUT end, 200)
          wait(10)
        end
        spins = spins + 1
        L.log("SPIN", spins)
        if s.core.coins < 100 or won or spins > 60 then
          tap("b", 30)
          taps({ "down", "up" }, 18)
          tap("a", 60)
        elseif spins >= 3 then
          tap("r", 30)
        else
          tap("down", 16)
          if spins == 2 then tap("down", 16) end
          tap("a", 20)
        end
      elseif cs == ST.WAIT_REEL_STOP then
        wait(20)
        tap("a", 10)
      elseif cs == ST.WAIT_PAYOUT then
        won = true
        wait(1)
      elseif s.message and not s.yesNo then
        tap("a", 20)
      else
        wait(1)
      end
      frames = frames + 1
    end
    L.log("FINISHED", tostring(Base.active() == nil) .. " spins " .. spins .. " frames " .. frames)
    wait(60)
    L.talk(10)
    L.closeAll()
  end)

  section("coins", function()
    -- The coins box beside a script's message (coins.c), and the money box.
    giveCoins(77)
    local CoinsBox = require("src.ui.game3.coins_box")
    CoinsBox.show(1, 1, 77)
    wait(30)
    CoinsBox.show(1, 1, 80)
    wait(30)
    CoinsBox.hide()
    wait(10)
    local MoneyBox = require("src.ui.game3.money_box")
    session.money = 1234
    MoneyBox.show(1, 1, 1234)
    wait(30)
    MoneyBox.hide()
    wait(10)
  end)

  -- ------------------------------------------------------------- move tutor

  section("tutor", function()
    local mon = session.party[1]
    local screens = isRs and require("src.ui.game3.rs.move_relearner") or require("src.ui.game3.rse.move_relearner")
    local finished
    screens.show(mon, { session = session, onDone = function(learned) finished = learned == true and "learned" or "no" end })
    wait(30)
    L.log("TOP", tostring(L.top()))
    taps({ "down", "down", "up" }, 18)
    tap("right", 20)                    -- contest moves
    tap("down", 20)
    tap("left", 20)
    tap("a", 25)                        -- teach?
    taps({ "down" }, 16)
    tap("a", 25)                        -- NO
    tap("b", 25)                        -- give up?
    tap("down", 16)
    tap("a", 25)                        -- NO
    tap("a", 25)                        -- teach?
    tap("a", 25)                        -- YES
    for _ = 1, 10 do
      if finished then break end
      if L.top() == "summary" then tap("b", 40) else tap("a", 25) end
    end
    L.log("FINISHED", tostring(finished))
    L.closeAll()
  end)

  -- ----------------------------------------------------------------- scenes

  section("cable_car", function()
    local Car = require("src.ui.game3.rse.cable_car")
    local finished
    Car.open({ goingDown = false, session = session, onDone = function() finished = true end })
    wait(60)
    L.log("TOP", tostring(L.top()))
    waitFor("ride", function() return finished end, 1800)
    L.log("FINISHED", tostring(finished))
    wait(20)
  end)

  section("rayquaza", function()
    if isRs then return end
    local Ray = require("src.ui.game3.rse.rayquaza_scene")
    local finished
    Ray.open({ animId = Ray.DUO_FIGHT_PRE, endEarly = true, onDone = function() finished = true end })
    wait(60)
    L.log("TOP", tostring(L.top()))
    waitFor("scene", function() return finished end, 1500)
    L.log("FINISHED", tostring(finished))
    wait(20)
  end)

  section("hof", function()
    local Hof = require("src.ui.game3.hall_of_fame")
    local finished
    Hof.start({ session = session, dontSave = true, warp = false, onDone = function() finished = true end })
    wait(30)
    L.log("TOP", tostring(L.top()))
    for _ = 1, 60 * 200 do
      if finished or not Hof.isOpen() then break end
      if Hof.phase() == "exitwait" then tap("a", 10) else wait(1) end
    end
    L.log("FINISHED", tostring(finished) .. " " .. tostring(L.top()))
    L.closeAll()
  end)

  section("hofpc", function()
    local Pc = require("src.ui.game3.hall_of_fame_pc")
    local ok2, why = pcall(function() Pc.show({ session = session, onClose = function() end }) end)
    L.log("SHOW", tostring(ok2) .. " " .. tostring(why))
    wait(60)
    L.log("TOP", tostring(L.top()))
    if ok2 then
      tap("a", 40)
      tap("a", 40)
      tap("b", 40)
    end
    L.closeAll()
  end)

  section("credits", function()
    local mod = isRs and require("src.ui.game3.rs.credits") or require("src.ui.game3.rse.credits")
    local finished
    mod.start({ session = session, onDone = function() finished = true end })
    wait(30)
    L.log("TOP", tostring(L.top()))
    local budget = tonumber(os.getenv("RSE_CREDIT_FRAMES")) or (60 * 60)
    for _ = 1, budget do
      if finished then break end
      wait(1)
    end
    L.log("FINISHED", tostring(finished))
    if not finished then require("src.ui.game3.rse.credits").reset() end
    wait(10)
  end)

  section("diploma", function()
    local D = isRs and require("src.ui.game3.rs.diploma") or require("src.ui.game3.diploma")
    local finished
    D.show({ session = session, onDone = function() finished = true end })
    wait(90)
    L.log("TOP", tostring(L.top()))
    tap("a", 60)
    waitFor("diploma", function() return finished end, 120)
    L.log("FINISHED", tostring(finished))
    wait(10)
  end)

  section("glass", function()
    if not isRs then return end
    local Glass = require("src.ui.game3.rs.glass_workshop")
    local value
    Glass.show(function(v) value = v end)
    wait(20)
    L.log("TOP", tostring(L.top()))
    taps({ "down", "down", "up" }, 16)
    tap("b", 30)
    L.log("VALUE", tostring(value))
  end)

  section("daycare", function()
    if not isRs then return end
    local Dc = require("src.ui.game3.rs.daycare_party")
    local value
    Dc.show(session, function(v) value = v end)
    wait(60)
    L.log("TOP", tostring(L.top()))
    tap("down", 25)
    tap("a", 30)
    L.log("TOP", tostring(L.top()))
    taps({ "down", "up" }, 16)
    tap("b", 30)
    tap("b", 30)
    L.log("VALUE", tostring(value))
    L.closeAll()
    local Daycare = require("src.core.game3.daycare")
    local dc = Daycare.stateOf(session)
    local Level = require("src.ui.game3.rs.daycare_level_menu")
    local probe, why = pcall(Level.rows, dc)
    L.log("ROWS", tostring(probe) .. " " .. tostring(why))
    if not probe then return end
    local choice
    Level.show(dc, function(v) choice = v end)
    wait(20)
    L.log("TOP", tostring(L.top()))
    taps({ "down", "down", "up" }, 16)
    tap("b", 30)
    L.log("VALUE", tostring(choice))
  end)

  section("linkrecords", function()
    if not isRs then return end
    local N = require("src.core.game3.scripting.natives_link_rs")
    session.linkBattleRecords = { { name = "ROXIE", wins = 3, losses = 1, draws = 0 } }
    session.gameStats = session.gameStats or {}
    session.gameStats[23], session.gameStats[24], session.gameStats[25] = 3, 1, 0
    N.BY_NAME.ShowLinkBattleRecords()
    wait(30)
    require("src.ui.game3.rs.link_records").eraseBox(0, 0, 29, 19)
    wait(10)
  end)

  section("lobby", function()
    if not isRs then return end
    -- Its caller, link/cable_entry.lua, needs a live link; the rows are the driver's.
    local Lobby = require("src.ui.game3.rs.cable_lobby")
    local cancelled
    Lobby.show({ title = function() return "Choose a group" end,
      rows = function() return { { label = "ROXIE" }, { label = "WALLY", disabled = true } } end,
      select = function() end, cancel = function() cancelled = true Lobby.close() end })
    wait(20)
    L.log("TOP", tostring(L.top()))
    taps({ "down", "up" }, 16)
    tap("b", 30)
    L.log("CANCELLED", tostring(cancelled))
  end)

  section("autoscroll", function()
    if not isRs then return end
    -- natives_rs_easy_chat_message.lua kind 0: the profile, as its special prints it.
    local Msg = require("src.core.game3.rs.easy_chat_message")
    local p = Msg.build(session, 0)
    L.log("TEXT", tostring(p.text ~= nil))
    local printed
    Message.showRsFieldAutoScroll(p, function() printed = true end)
    waitFor("printed", function() return printed end, 900)
    L.log("PRINTED", tostring(printed))
    wait(20)
    Message.close()
    require("src.ui.game3.rs.field_auto_scroll_message").reset()
    wait(10)
  end)

  section("multichoice", function()
    -- The prize clerk's real script: a multichoice, Hoenn's script list window.
    giveCoins(50)
    goTo("MAP_MAUVILLE_CITY_GAME_CORNER", 14, 3, "up")
    tap("a", 30)
    mashUntil(function() return Choice.isOpen() end, 60)
    L.log("OPEN", tostring(Choice.isOpen()) .. " " .. tostring(Choice.kind))
    taps({ "down", "down", "up" }, 16)
    tap("b", 30)
    for _ = 1, 10 do
      if not Message.open and not Choice.isOpen() then break end
      tap("b", 25)
    end
    wait(30)
    L.closeAll()
  end)

  section("listmenu", function()
    local LM = require("src.core.game3.scripting.natives_listmenu")
    local Menu = LM.Menu
    local picked
    local shown, why = pcall(function()
      Menu.showItems("driver", { "ONE", "TWO", "THREE" }, { left = 1, top = 1, width = 8, shown = 3, count = 3 }, 0, 0,
        function(i) picked = i end)
    end)
    L.log("SHOWN", tostring(shown) .. " " .. tostring(why))
    wait(20)
    L.log("TOP", tostring(L.top()))
    taps({ "down", "up" }, 16)
    tap("b", 30)
    L.log("PICKED", tostring(picked))
    L.closeAll()
  end)

  section("trickhouse", function()
    -- Script text only: the entrance's own script through the dialogue presenter.
    goTo("MAP_ROUTE110_TRICK_HOUSE_ENTRANCE", 6, 4, "up")
    L.log("MAP", tostring(L.session().map))
    wait(60)
    for _, x in ipairs({ 4, 5, 6, 7, 8 }) do
      if Message.open or Choice.isOpen() then break end
      Player.cellX, Player.px, Player.targetX = x, x * 16, x
      tap("a", 30)
    end
    for _ = 1, 8 do
      if not Message.open and not Choice.isOpen() then break end
      tap("a", 25)
    end
    L.closeAll()
    wait(20)
  end)

  section("mkrtcsave", function()
    -- Prepares this disposable profile's save for a RSE_TITLE=rtc run.
    L.flag(session, "FLAG_SYS_RESET_RTC_ENABLE")
    local Flags = require("src.core.game3.scripting.flags")
    Flags.setVar(Space.store, nil, consts:require("vars", "VAR_RESET_RTC_ENABLE"), 0x920)
    local save = require("src.core.game3.save_schema_firered").toSaveTable(session)
    local written = require("src.core.SaveData").save(save)
    L.log("SAVED", tostring(written))
  end)

  L.log("DONE", "rse_screens_field")
  love.event.quit()
end
