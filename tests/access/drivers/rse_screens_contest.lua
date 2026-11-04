-- Contests, Pokéblock, the Berry Blender and the berry tag in Emerald, Ruby and
-- Sapphire.  Screens open through the modules and options their own callers use
-- (natives_contest.lua, natives_blender.lua, item_use.lua, bag_menu.lua, the
-- Safari battle's chooseForBattle); a contest is played through its five rounds
-- by key press.  Asserts nothing; logs SCREEN, SAID, BAD.  RSE_ONLY (a comma
-- list of section names) limits a run.
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
  local ok, err = pcall(function() game:_handleBootAction({ action = "new_game", name = "MAY", gender = 1 }) end)
  if not ok then L.log("FAIL", "new game: " .. tostring(err)) love.event.quit() return end
  wait(120)
  L.talk(40)
  wait(60)

  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local C = require("src.core.game3.constants")
  local Stack = require("src.ui.game3.stack")
  local Pokeblock = require("src.core.game3.rse.pokeblock")
  local Profile = require("src.core.game3.profile")
  local Screens = require("src.ui.game3.screens")
  local session = L.session()
  local consts = C.active(session)
  local function item(name) return consts:require("items", name) end

  session.party = {}
  Party.giveMon(session, consts:require("species", "SPECIES_MUDKIP"), 12)
  Party.giveMon(session, consts:require("species", "SPECIES_ZIGZAGOON"), 5, "ZIGGY")
  session.party[1].contest = { cool = 40, beauty = 12, cute = 3, smart = 0, tough = 25, sheen = 60 }
  L.flag(session, "FLAG_SYS_POKEMON_GET")
  Bag.add(session.bag, item("ITEM_CHERI_BERRY"), 3)
  Bag.add(session.bag, item("ITEM_ORAN_BERRY"), 2)

  local function blocks()
    Pokeblock.clearAll(session)
    Pokeblock.add(session, Pokeblock.new({ color = 1, spicy = 20, dry = 0, sweet = 5, bitter = 0, sour = 0, feel = 21 }))
    Pokeblock.add(session, Pokeblock.new({ color = 3, spicy = 0, dry = 0, sweet = 15, bitter = 0, sour = 0, feel = 30 }))
  end

  local function contestUi(key, path)
    local ui = Profile.forSession(session).ui
    local native = ui and ui.contest and ui.contest[key]
    return require(native or path)
  end

  local function current()
    local Rs = require("src.core.game3.rs.contest_util")
    if Rs.is(session) then return Rs end
    return require("src.core.game3.rse.contest_util")
  end

  -- natives_contest.lua TryEnterContestMon, then its screen(): the profile's module.
  local function enter(category, rank)
    local U = current()
    local e = U.tryEnterContestMon(session, 0, category, rank)
    L.log("ENTER", tostring(e))
    local Shared = require("src.core.game3.rse.contest_util")
    local c = Shared.current()
    local m = c and c.mons[c.playerIndex]
    if m and (m.nickname == nil or m.nickname == "") then
      local Pokemon = require("src.core.game3.pokemon")
      m.nickname = Pokemon.displayName and Pokemon.displayName(session.party[1]) or Pokemon.name(m.species)
    end
    return c
  end

  section("party", function()
    if require("src.core.game3.rs.contest_util").is(session) then
      local done
      require("src.ui.game3.rse.contest_party").show(session, 0, 0, function(slot) done = slot end)
      wait(60)
      L.log("TOP", tostring(L.top()))
      taps({ "down", "down", "up" }, 20)
      tap("a", 60)
      waitFor("party done", function() return done ~= nil end, 200)
      L.log("PICKED", tostring(done))
      wait(40)
    else
      -- Emerald's choosecontestmon: Natives.choosePartyMon's PartyMenu.show.
      local PartyMenu = require("src.ui.game3.party_menu")
      PartyMenu.show(session.party, nil, { mode = "choose", session = session, onSelect = function() end, onClose = function() end })
      wait(60)
      L.log("TOP", tostring(L.top()))
      taps({ "down", "up" }, 20)
      tap("b", 40)
      L.closeAll()
    end
  end)

  section("contest", function()
    local c = enter(0, 0)
    if not c then L.log("FAIL", "no contest") return end
    local finished
    contestUi("stage", "src.ui.game3.rse.contest").open({ contest = c, session = session,
      onDone = function() finished = true end })
    local Stage = require("src.ui.game3.rse.contest")
    wait(30)
    L.log("TOP", tostring(L.top()))
    local rounds = 0
    local Budget = 60 * 60 * 20
    local frames = 0
    local inMenu = false
    while not finished and frames < Budget do
      local s = Stage.active()
      if not s then break end
      local task = s.m.tasks.t[s.mainTaskId]
      if task and s.fn.taskHandleMoveSelectInput == task.func then
        if not inMenu then
          inMenu = true
          rounds = rounds + 1
          L.log("ROUND", rounds)
          taps({ "down", "down", "up" }, 20)
          if rounds == 1 then
            tap("b", 30)                -- back to the appeal text, as a player can
            tap("a", 30)
          end
          if rounds % 2 == 0 then tap("down", 20) end
          tap("a", 10)
        end
      else
        inMenu = false
        if task and (s.fn.taskTryShowMoveSelectScreen == task.func or s.fn.taskPrintRoundResultText == task.func
            or s.fn.taskWaitForOutOfTimeMsg == task.func) then
          tap("a", 8)
        else
          wait(1)
        end
      end
      frames = frames + 1
    end
    L.log("FINISHED", tostring(finished) .. " rounds " .. rounds .. " frames " .. frames)
    wait(40)
  end)

  section("results", function()
    local Shared = require("src.core.game3.rse.contest_util")
    local c = Shared.current()
    if not c then enter(0, 0) c = Shared.current() end
    local finished
    contestUi("results", "src.ui.game3.rse.contest_results").open({ contest = c, session = session,
      onDone = function() finished = true end })
    wait(30)
    L.log("TOP", tostring(L.top()))
    local frames = 0
    while not finished and frames < 60 * 90 do
      local R = require("src.ui.game3.rse.contest_results").active()
      local task = R and R.m.tasks.t[R.d.showResultsTaskId]
      if task and R.fn.taskSetSeenWinnerMon == task.func then tap("a", 20) else wait(1) end
      frames = frames + 1
    end
    L.log("FINISHED", tostring(finished) .. " frames " .. frames)
    wait(40)
  end)

  section("painting", function()
    local NC = require("src.core.game3.scripting.natives_contest")
    local Shared = require("src.core.game3.rse.contest_util")
    if type(session.contestWinners) ~= "table" then NC.ensureWinners(session) end
    local c = Shared.current()
    local winner = NC.curWinner
    local rows = session.contestWinners or {}
    for _, row in pairs(rows) do
      if type(row) == "table" and (tonumber(row.species) or 0) ~= 0 then winner = winner or row end
    end
    if not winner then L.log("NOWINNER", "no winner") return end
    -- a hall caption (not the artist's copy)
    local hall
    for _, row in pairs(rows) do
      if type(row) == "table" and (tonumber(row.species) or 0) ~= 0 then hall = row break end
    end
    local finished
    contestUi("painting", "src.ui.game3.rse.contest_painting").open({ winner = hall or winner, saveIdx = 0,
      isForArtist = false, session = session, onDone = function() finished = true end })
    wait(90)
    L.log("TOP", tostring(L.top()))
    tap("a", 90)
    waitFor("painting done", function() return finished end, 200)
    finished = nil
    contestUi("painting", "src.ui.game3.rse.contest_painting").open({ winner = winner, saveIdx = 0,
      isForArtist = true, session = session, onDone = function() finished = true end })
    wait(90)
    tap("a", 90)
    waitFor("painting done", function() return finished end, 200)
    L.log("C", tostring(c ~= nil))
    wait(30)
  end)

  section("case", function()
    blocks()
    Pokeblock.openCase(session, {})
    wait(40)
    L.log("TOP", tostring(L.top()))
    taps({ "down", "down", "up", "up" }, 20)
    tap("select", 20)                   -- moving a row
    tap("down", 20)
    tap("b", 20)
    tap("a", 20)                        -- actions
    taps({ "down", "down", "up" }, 20)
    tap("a", 90)                        -- TOSS
    wait(60)
    taps({ "down", "up" }, 20)
    tap("down", 20)
    tap("a", 40)                        -- NO
    tap("up", 20)
    L.log("STEP", "toss yes")
    tap("a", 20)
    tap("down", 20)
    tap("a", 90)
    wait(60)
    tap("up", 20)
    tap("a", 60)
    wait(40)
    tap("a", 40)
    L.log("STEP", "use")
    tap("a", 20)                        -- USE on the remaining block
    tap("a", 80)
    waitFor("use", function() return L.top() == "rse_use_pokeblock" end, 120)
    wait(90)
    taps({ "down" }, 60)
    tap("down", 60)
    tap("up", 60)
    tap("up", 60)
    tap("a", 30)                        -- feed the lead
    taps({ "down", "up" }, 20)
    L.log("STEP", "feed yes")
    tap("a", 30)
    waitFor("feed", function() return L.top() == "rse_pokeblock_feed" end, 120)
    L.log("TOP", tostring(L.top()))
    waitFor("back", function() return L.top() == "rse_use_pokeblock" end, 900)
    L.log("TOP", tostring(L.top()))
    wait(90)
    tap("a", 90)                        -- results_wait
    wait(90)
    for _ = 1, 8 do
      if L.top() ~= "rse_use_pokeblock" then break end
      tap("a", 40)
    end
    wait(90)
    L.log("TOP", tostring(L.top()))
    tap("b", 60)
    L.closeAll()
    wait(30)
  end)

  section("safari", function()
    -- The Safari battle's POKéBLOCK command opens the case this way.
    blocks()
    local got
    Pokeblock.chooseForBattle(session, function(r) got = r or false end)
    wait(40)
    L.log("TOP", tostring(L.top()))
    tap("down", 20)
    tap("a", 20)
    taps({ "down", "up" }, 20)
    tap("a", 60)
    waitFor("safari", function() return got ~= nil end, 120)
    L.log("SAFARI", got and tostring(got.name) or "cancelled")
    wait(30)
  end)

  section("safaribattle", function()
    -- A real Safari battle: its POKeBLOCK command (rse_battle.lua's way in).
    blocks()
    local Battle = require("src.core.game3.battle")
    local Ui = require("src.core.game3.battle.ui")
    local Runtime = require("src.core.game3.runtime")
    local BattleBridge = require("src.core.game3.battle_bridge")
    local Rules = require("src.core.game3.battle.rules")
    session.safari = { active = true, balls = Rules.safari.BALLS, steps = Rules.safari.STEPS }
    local started, why = BattleBridge.startWild(Runtime._mod, game, { species = 111, level = 25 }, { safari = true, fade = false })
    if not started then L.log("FAIL", "safari: " .. tostring(why)) return end
    local function atMenu() return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" end
    for _ = 1, 3000 do
      if atMenu() then break end
      local Message = require("src.ui.game3.message")
      if Message.isOpen() and Message.isWaiting() then tap("a", 20) else wait(1) end
    end
    L.log("ATMENU", tostring(atMenu()))
    for _ = 1, 4 do
      local c = (Ui._menuIndex or 1) - 1
      if c == 1 then break end
      if c % 2 == 0 then tap("right", 12) else tap("left", 12) end
    end
    tap("a", 80)                        -- POKeBLOCK
    L.log("TOP", tostring(L.top()) .. " " .. tostring(Battle._phase))
    tap("down", 20)
    tap("a", 20)                        -- actions
    taps({ "down", "up" }, 20)
    tap("a", 90)                        -- USE
    for _ = 1, 1500 do
      if atMenu() then break end
      local Message = require("src.ui.game3.message")
      if Message.isOpen() and Message.isWaiting() then tap("a", 20) else wait(1) end
    end
    L.log("ATMENU", tostring(atMenu()))
    for _ = 1, 8 do
      if not atMenu() then break end
      for _ = 1, 4 do                   -- RUN, the fourth command (rse_battle.lua menuTo)
        local c = (Ui._menuIndex or 1) - 1
        if c == 3 then break end
        if c % 2 ~= 1 then tap("right", 12) else tap("down", 12) end
      end
      tap("a", 60)
      for _ = 1, 400 do
        if atMenu() or not Battle.isActive() then break end
        local Message = require("src.ui.game3.message")
        if Message.isOpen() and Message.isWaiting() then tap("a", 20) else wait(1) end
      end
    end
    session.safari = nil
    wait(60)
    L.log("INBATTLE", tostring(Battle.isActive()))
  end)

  section("tag", function()
    local Tag = Screens.get("berry_tag", session)
    local list = { item("ITEM_CHERI_BERRY"), item("ITEM_ORAN_BERRY") }
    Tag.show({ session = session, list = list, pos = 0, onClose = function() end })
    wait(40)
    L.log("TOP", tostring(L.top()))
    tap("down", 40)
    tap("up", 40)
    tap("b", 60)
    L.closeAll()
    wait(20)
  end)

  section("blender", function()
    blocks()
    Pokeblock.tryClear(session, 0)
    local NB = require("src.core.game3.scripting.natives_blender")
    local Mod = Screens.get("berry_blender", session) or require("src.ui.game3.rse.berry_blender")
    local finished
    local RsPolicy = require("src.core.game3.rs.berry_blender_policy")
    local screen = Mod.open({ session = session, opponents = 1, blendMaster = false,
      version = Profile.forSession(session).id, playerName = "MAY",
      onDone = function() finished = true end })
    L.log("NB", tostring(NB ~= nil and RsPolicy ~= nil))
    wait(30)
    L.log("TOP", tostring(L.top()))
    local played = false
    local tagSeen = false
    local frames = 0
    local answered = 0
    local cool = 0
    local B = require("src.core.game3.rse.berry_blender")
    while not finished and frames < 60 * 180 do
      local top = L.top()
      if top == "rse_berry_tag" or top == "rs_berry_tag" then
        wait(40)
        tap("b", 60)
      elseif top == "bag_menu" or top == "bag" then
        L.log("STEP", "berry in the bag " .. tostring(top))
        wait(60)
        taps({ "down", "up" }, 20)
        tap("a", 30)
        -- the bag's own CHECK TAG once, then CONFIRM (the rows' order differs by game)
        local want = tagSeen and "CONFIRM" or "CHECK_TAG"
        tagSeen = true
        local BagMenu = require("src.ui.game3.bag_menu")
        for _, key in ipairs({ "down", "up", "left", "right", "down", "up" }) do
          if BagMenu.ACTIONS and BagMenu.ACTIONS[BagMenu.actionCursor] == want then break end
          tap(key, 15)
        end
        L.log("STEP", "action " .. tostring(BagMenu.ACTIONS and BagMenu.ACTIONS[BagMenu.actionCursor]))
        tap("a", 60)
      elseif screen.cb == "play" then
        played = true
        -- a press as the arrow reaches this player's marker (as tests/drivers/em_berry_blender.lua)
        local g = screen.game
        local nxt = (g.arrowPos + 3 * g.speed) % 65536
        if cool == 0 and g:arrowProximity(nxt, 0) == B.PROXIMITY.BEST then
          tap("a", 0)
          cool = 12
        else
          wait(1)
        end
        cool = math.max(0, cool - 1)
      elseif screen.yesNo then
        L.log("STEP", "another?")
        tap("down", 20)
        tap("up", 20)
        tap("down", 20)
        tap("a", 20)
        answered = answered + 1
      elseif screen.printer or (screen.cb == "end") then
        tap("a", 12)
      else
        wait(1)
      end
      frames = frames + 1
    end
    L.log("FINISHED", tostring(finished) .. " played " .. tostring(played) .. " frames " .. frames .. " answered " .. answered)
    wait(40)
  end)

  L.log("DONE", "rse_screens_contest")
  love.event.quit()
end
