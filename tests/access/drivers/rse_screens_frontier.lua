-- Battle Frontier screens in Emerald, Trainer Hill records, and Ruby and Sapphire's
-- Battle Tower record board.  These open from scripts deep in the game: where a
-- section says "script" it runs the map's own script; otherwise it sets the session
-- state the challenge would have set and opens the module with the options its native
-- passes.  Asserts nothing; logs SCREEN, SAID, BAD.
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
  local ok, err = pcall(function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  if not ok then L.log("FAIL", "new game: " .. tostring(err)) love.event.quit() return end
  wait(120)
  L.talk(40)
  wait(60)

  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants")
  local Stack = require("src.ui.game3.stack")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Profile = require("src.core.game3.profile")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local session = L.session()
  local consts = C.active(session)
  local isRs = Profile.forSession(session).id ~= "emerald"

  session.party = {}
  Party.giveMon(session, consts:require("species", "SPECIES_MUDKIP"), 30)
  Party.giveMon(session, consts:require("species", "SPECIES_ZIGZAGOON"), 30, "ZIGGY")
  Party.giveMon(session, consts:require("species", "SPECIES_WINGULL"), 30)
  L.flag(session, "FLAG_SYS_POKEMON_GET")
  require("src.core.game3.encounters").onStep = function() return nil end

  local function goTo(mapId, x, y, facing)
    L.closeAll()
    L.log("GOTO", tostring(mapId))
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    local s = L.session()
    s.x, s.y, s.facing = x, y, facing
    Player.cellX, Player.cellY, Player.px, Player.py = x, y, x * 16, y * 16
    Player.targetX, Player.targetY, Player.facing = x, y, facing
    wait(40)
  end

  local function hold(key, frames)
    game.input.state[key] = true
    wait(frames)
    game.input.state[key] = false
    wait(6)
  end

  local function mashUntil(pred, budget)
    for _ = 1, budget or 40 do
      if pred() then return true end
      if Message.open and Message.isWaiting and Message.isWaiting() then tap("a", 12) else wait(6) end
    end
    return pred()
  end

  -- Script labels this bundle has, by parts of a name.
  local function labels(...)
    local out = {}
    local parts = { ... }
    for name in pairs(Space.bundle and Space.bundle.labels or {}) do
      local hit = true
      for _, part in ipairs(parts) do
        if not name:find(part, 1, true) then hit = false end
      end
      if hit then out[#out + 1] = name end
    end
    table.sort(out)
    return out
  end

  -- Only when named in RSE_ONLY: which scripts this game's bundle has.
  if only and only.labels then
    section("labels", function()
      for _, part in ipairs({ "Results", "Records", "RankingHall", "Tower" }) do
        L.log("LABELS " .. part, table.concat(labels(part), " "))
      end
    end)
  end

  -- ---------------------------------------------------------------- Ruby, Sapphire
  if isRs then
    section("rs_tower", function()
      local Board = require("src.ui.game3.rs.battle_tower_records")
      session.battleTower = session.battleTower or {}
      session.battleTower.currentWinStreaks = { 12, 3 }
      session.battleTower.recordWinStreaks = { 21, 7 }
      session.battleTower.var_4AE = { 2, 0 }
      Board.show(session)                 -- natives_rs_tower_records: ShowBattleTowerRecords
      wait(60)
      L.log("VISIBLE", tostring(Board.visible))
      Board.hide()
      wait(20)
    end)
    L.log("DONE", "rse_screens_frontier")
    love.event.quit()
    return
  end

  -- ------------------------------------------------------------------ Emerald
  local Util = require("src.core.game3.rse.frontier.util")
  local f = Util.frontier(session)
  f.battlePoints = 120
  f.lvlMode = 0
  L.flag(session, "FLAG_SYS_FRONTIER_PASS")
  L.flag(session, "FLAG_SYS_POKEDEX_GET")

  local StartMenu = require("src.ui.game3.start_menu")

  local function openStart(id)
    tap("start", 20)
    waitFor("start menu", function() return StartMenu.isOpen() end, 120)
    for _ = 1, 10 do
      local e = StartMenu.ENTRIES[StartMenu.cursor]
      if e and e.id == id then return true end
      tap("down", 12)
    end
    return false
  end

  section("pass", function()
    Util.giveSymbol(session, 0)         -- tower: silver
    Util.giveSymbol(session, 1)
    Util.giveSymbol(session, 1)         -- dome: gold
    goTo("EM_BATTLE_FRONTIER_OUTSIDE_WEST", 19, 19, "up")
    wait(30)
    L.log("OPEN", tostring(openStart("trainer")))
    tap("a", 30)
    local Pass = require("src.ui.game3.rse.frontier_pass")
    waitFor("pass", function() return Pass._st.phase == "input" end, 200)
    L.log("TOP", tostring(L.top()) .. " " .. tostring(Pass._st.cursorArea))
    hold("down", 40)                    -- over the card
    L.log("AREA", tostring(Pass._st.cursorArea))
    hold("left", 60)
    L.log("AREA", tostring(Pass._st.cursorArea))
    hold("left", 20)
    L.log("AREA", tostring(Pass._st.cursorArea))
    hold("up", 30)
    L.log("AREA", tostring(Pass._st.cursorArea))
    hold("up", 40)
    L.log("AREA", tostring(Pass._st.cursorArea))
    hold("right", 90)                   -- back over the map
    L.log("AREA", tostring(Pass._st.cursorArea))
    hold("down", 20)
    L.log("AREA", tostring(Pass._st.cursorArea))
    -- walk to the map's rectangle by what the screen says
    local function toArea(area)
      local Gfx = require("src.ui.game3.rse.pokeblock_gfx")
      local rect = Gfx.of("rse/frontier_pass"):manifest().areas[area]
      local st = Pass._st
      local tx, ty = math.floor((rect.xStart + rect.xEnd) / 2) + 5, math.floor((rect.yStart + rect.yEnd) / 2) - 5
      for _ = 1, 400 do
        local dx, dy = tx - st.cursorX, ty - st.cursorY
        if math.abs(dx) <= 2 and math.abs(dy) <= 2 then break end
        game.input.state.left, game.input.state.right = dx < -2, dx > 2
        game.input.state.up, game.input.state.down = dy < -2, dy > 2
        wait(1)
      end
      game.input.state.left, game.input.state.right, game.input.state.up, game.input.state.down = false, false, false, false
      wait(8)
      L.log("AREA", tostring(st.cursorArea) .. " want " .. tostring(area))
    end
    for _, area in ipairs({ Pass.AREA.POINTS, Pass.AREA.EARNED_SYMBOLS, Pass.AREA.SYMBOL_TOWER, Pass.AREA.SYMBOL_DOME,
      Pass.AREA.RECORD, Pass.AREA.CANCEL, Pass.AREA.MAP }) do
      toArea(area)
    end
    tap("a", 10)
    waitFor("map", function() return Pass.Map.active and Pass.Map.state == "input" end, 300)
    taps({ "down", "down", "up" }, 30)
    tap("up", 30)
    tap("up", 30)                        -- wraps
    tap("b", 10)
    waitFor("back", function() return Pass._st.phase == "input" end, 300)
    L.log("TOP", tostring(L.top()) .. " " .. tostring(Pass._st.phase))
    toArea(Pass.AREA.CARD)
    tap("a", 10)
    waitFor("card", function() return L.top() ~= Pass.ID end, 300)
    L.log("TOP", tostring(L.top()))
    wait(60)
    tap("b", 40)
    waitFor("back", function() return L.top() == Pass.ID and Pass._st.phase == "input" end, 400)
    L.log("TOP", tostring(L.top()) .. " " .. tostring(Pass._st.phase))
    toArea(Pass.AREA.CANCEL)
    tap("a", 60)
    wait(30)
    L.closeAll()
    L.log("TOP", tostring(L.top()))
  end)

  section("records", function()
    local D = require("src.core.game3.rse.frontier.trainers")
    local Records = require("src.ui.game3.rse.frontier_records")
    local F = D.FACILITY
    local function show(tag, fn)
      L.log("WINDOW", tag)
      fn()
      wait(40)
      Records.remove()
      wait(4)
    end
    show("tower singles", function() Records.showResults(session, F.TOWER, 0) end)
    show("tower link multi", function() Records.showResults(session, F.TOWER, 3) end)
    show("dome", function() Records.showResults(session, F.DOME, 0) end)
    show("palace", function() Records.showResults(session, F.PALACE, 1) end)
    show("pike", function() Records.showResults(session, F.PIKE, 0) end)
    show("arena", function() Records.showResults(session, F.ARENA, 0) end)
    show("factory", function() Records.showResults(session, F.FACTORY, 0) end)
    show("pyramid", function() Records.showResults(session, F.PYRAMID, 0) end)
    show("link contest", function() Records.showResults(session, Util.FACILITY_LINK_CONTEST, 0) end)
    -- natives_tower_rse: ShowLinkBattleRecords, the cable club's box
    session.gameStats = session.gameStats or {}
    session.linkBattleRecords = { { name = "MAY", wins = 3, losses = 1, draws = 0 } }
    show("link battle", function() Records.showLinkBattle(session) end)
    -- natives_frontier: the Ranking Hall's level pages replace one window
    L.log("WINDOW", "ranking hall")
    Records.showRankingHall(session, 0, 0)
    wait(40)
    Records.showRankingHall(session, 0, 1)
    wait(40)
    Records.remove()
    -- natives_frontier: ShowBattlePointsWindow, UpdateBattlePointsWindow
    L.log("WINDOW", "bp")
    Records.showBp(session)
    wait(20)
    f.battlePoints = 90
    Records.updateBp(session)
    wait(20)
    Records.hideBp()
    f.battlePoints = 120
    wait(10)
    -- The same windows by the game's own scripts.
    for _, label in ipairs({ "BattleFrontier_BattleTowerLobby_EventScript_ShowSinglesResults",
      "BattleFrontier_BattleFactoryLobby_EventScript_ShowSinglesResults",
      "BattleFrontier_RankingHall_EventScript_TowerSinglesRecords",
      "EventScript_CableBoxResults", "LilycoveCity_ContestLobby_EventScript_BerryBlenderSpeedRecords" }) do
      L.log("SCRIPT", label)
      goTo("EM_BATTLE_FRONTIER_OUTSIDE_WEST", 19, 19, "up")
      Space.startScript(label)
      wait(90)
      L.log("OPEN", tostring(Records.isOpen()))
      for _ = 1, 12 do
        if not Records.isOpen() and not Message.open and not Choice.isOpen() and not (Space.vm and Space.vm:isRunning()) then break end
        tap("a", 40)
      end
      wait(20)
      L.log("OPEN", tostring(Records.isOpen()) .. " " .. tostring(Space.vm and Space.vm:isRunning()))
    end
  end)

  local function runLabel(label)
    local found = Space.bundle.labels[label]
    L.log("SCRIPT", tostring(label) .. " " .. tostring(found ~= nil))
    if found then Space.startScript(label) end
    return found ~= nil
  end

  section("exchange", function()
    goTo("EM_BATTLE_FRONTIER_EXCHANGE_SERVICE_CORNER", 3, 4, "right")
    local ListMenu = require("src.core.game3.scripting.natives_listmenu")
    if runLabel("BattleFrontier_ExchangeServiceCorner_EventScript_DecorClerk1") then
      mashUntil(function() return ListMenu.Menu.open end, 300)
      L.log("LIST", tostring(ListMenu.Menu.open) .. " " .. tostring(ListMenu.Menu.kind))
      taps({ "down", "down", "up" }, 16)
      tap("b", 30)
      for _ = 1, 12 do
        if not Message.open and not Choice.isOpen() and not ListMenu.Menu.open then break end
        tap("b", 25)
      end
    end
    wait(30)
    for _, label in ipairs(labels("ExchangeServiceCorner_EventScript_", "Clerk")) do L.log("CLERK", label) end
    if runLabel("BattleFrontier_ExchangeServiceCorner_EventScript_VitaminClerk") then
      mashUntil(function() return ListMenu.Menu.open end, 300)
      taps({ "down", "up" }, 16)
      tap("b", 30)
      for _ = 1, 12 do
        if not Message.open and not Choice.isOpen() and not ListMenu.Menu.open then break end
        tap("b", 25)
      end
    end
    wait(30)
  end)

  section("tutor", function()
    goTo("EM_BATTLE_FRONTIER_LOUNGE7", 2, 6, "up")
    local ListMenu = require("src.core.game3.scripting.natives_listmenu")
    if runLabel("BattleFrontier_Lounge7_EventScript_LeftMoveTutor") then
      for _ = 1, 400 do
        if ListMenu.Menu.open then break end
        if Message.open then tap("a", 6) else wait(2) end
        if not (Space.vm and Space.vm:isRunning()) then break end
      end
      L.log("VM", tostring(Space.vm and Space.vm:isRunning()) .. " " .. tostring(L.top()))
      L.log("LIST", tostring(ListMenu.Menu.open) .. " " .. tostring(ListMenu.Menu.kind))
      taps({ "down", "down", "up" }, 16)
      tap("b", 30)
      for _ = 1, 12 do
        if not Message.open and not Choice.isOpen() and not ListMenu.Menu.open then break end
        tap("b", 25)
      end
    end
    wait(30)
  end)

  section("dome", function()
    -- natives_dome: CallBattleDomeFunction.  Challenge state as the lobby's scripts leave
    -- it: Dome.init, a chosen party, Dome.initTrainers.
    local Dome = require("src.core.game3.rse.frontier.dome")
    local UI = require("src.ui.game3.rse.dome_tourney")
    f.lvlMode = 0
    f.selectedPartyMons = { 1, 2, 3, 0 }
    Dome.init(session)
    Dome.initTrainers(session)
    goTo("EM_BATTLE_FRONTIER_BATTLE_DOME_PRE_BATTLE_ROOM", 5, 5, "up")
    local closed = false
    local function onClose() closed = true end
    local function waitInput() return waitFor("dome input", function() return UI._st.phase == "input" or UI._st.phase == "wait" end, 300) end
    -- The room's own script: its question, then its menu, then the native's screens.
    for _ = 1, 40 do
      if Choice.isOpen() and Choice.kind ~= "yesno" then break end
      if Message.open or Choice.isOpen() then tap("a", 14) else wait(10) end
    end
    L.log("MENU", tostring(Choice.isOpen()) .. " " .. tostring(Choice.kind))
    taps({ "down", "up" }, 16)
    tap("a", 10)                        -- OPPONENT
    local function pressUntilOpen()
      for _ = 1, 80 do
        if UI.isOpen() then return true end
        if Message.open and not Choice.isOpen() then tap("a", 10) else wait(4) end
      end
      return UI.isOpen()
    end
    pressUntilOpen()
    L.log("OPEN", "opponent card " .. tostring(UI.isOpen()))
    waitInput()
    wait(40)
    tap("a", 10)
    waitFor("closed", function() return not UI.isOpen() end, 200)
    wait(30)
    for _ = 1, 20 do
      if Choice.isOpen() and Choice.kind ~= "yesno" then break end
      if Message.open or Choice.isOpen() then tap("a", 14) else wait(10) end
    end
    tap("down", 16)
    tap("a", 10)                        -- TOURNEY TREE
    pressUntilOpen()
    L.log("OPEN", "tree " .. tostring(UI.isOpen()))
    waitInput()
    wait(20)
    taps({ "down", "down", "up" }, 16)
    taps({ "right" }, 16)               -- a match
    L.log("CURSOR", tostring(UI._st.cursor))
    taps({ "right" }, 16)
    L.log("CURSOR", tostring(UI._st.cursor))
    tap("a", 10)                        -- its card
    waitInput()
    wait(30)
    L.log("CARD", tostring(UI._st.card and UI._st.card.kind) .. " " .. tostring(UI._st.pos))
    tap("left", 10)
    waitFor("slide", function() return UI._st.slide == nil end, 120)
    wait(10)
    tap("up", 10)
    waitFor("slide", function() return UI._st.slide == nil end, 120)
    wait(10)
    tap("right", 10)
    waitFor("slide", function() return UI._st.slide == nil end, 120)
    wait(10)
    tap("b", 10)                        -- back to the tree
    waitInput()
    wait(20)
    -- To the close button by the tree's own movement table.
    do
      local M = require("src.ui.game3.rse.pokeblock_gfx").of("rse/frontier_f2"):manifest().dome
      local KEYS = { "up", "down", "left", "right" }
      local cur = tonumber(f.curChallengeBattleNum) or 0
      local from, seen = {}, { [UI._st.cursor] = true }
      local queue, head = { UI._st.cursor }, 1
      while queue[head] do
        local at = queue[head]
        head = head + 1
        local row = M.cursorMap[at + 1] and M.cursorMap[at + 1][cur + 1]
        for dir = 1, 4 do
          local to = row and row[dir]
          if to and to ~= 0xFF and not seen[to] then
            seen[to] = true
            from[to] = { at, KEYS[dir] }
            queue[#queue + 1] = to
          end
        end
      end
      local path, at = {}, UI.CLOSE_BUTTON
      while from[at] do
        table.insert(path, 1, from[at][2])
        at = from[at][1]
      end
      taps(path, 12)
    end
    L.log("CURSOR", tostring(UI._st.cursor))
    tap("a", 10)
    waitFor("closed", function() return not UI.isOpen() end, 200)
    wait(30)
    -- Leave the room's menu behind; the rest open as its natives open them.
    if Choice.reset then Choice.reset() elseif Choice.close then Choice.close() end
    if Message.close then Message.close() end
    wait(10)
    -- Between rounds: the first round decided (Dome.decideRoundWinners, as the challenge
    -- does), then the static tree; the player is kept.
    local ok1, err1 = pcall(function()
      f.curChallengeBattleNum = 1
      Dome.decideRoundWinners(session, 0)
      f.domeTrainers[1].isEliminated = false
    end)
    L.log("ROUND", tostring(ok1) .. " " .. tostring(err1))
    L.log("OPEN", "static tree")
    closed = false
    UI.showTree({ session = session, mode = "static", onClose = onClose })
    waitInput()
    wait(30)
    tap("a", 10)
    waitFor("closed", function() return closed end, 200)
    wait(20)
    L.log("OPEN", "tree round 2")
    closed = false
    UI.showTree({ session = session, mode = "interactive", onClose = onClose })
    waitInput()
    wait(20)
    taps({ "down", "right" }, 16)
    tap("b", 10)
    waitFor("closed", function() return closed end, 200)
    wait(20)
    -- SHOW_PREV_TOURNEY_TREE
    L.log("OPEN", "previous tree")
    f.lvlMode = f.domeLvlMode - 1
    f.curChallengeBattleNum = Dome.FINAL
    closed = false
    UI.showTree({ session = session, mode = "prev", onClose = onClose })
    waitInput()
    wait(20)
    tap("down", 16)
    tap("b", 10)
    waitFor("closed", function() return closed end, 200)
    wait(20)
    f.curChallengeBattleNum = 0
    L.log("TOP", tostring(L.top()))
  end)

  section("factory", function()
    -- Factory.selectScreen and swapScreen with their options; the challenge's state from
    -- Factory.init and generateInitialRentalMons.
    local Factory = require("src.core.game3.rse.frontier.factory")
    local Screens = require("src.ui.game3.screens")
    local Select = Screens.get("factory_select", session)
    local Swap = Screens.get("factory_swap", session)
    goTo("EM_BATTLE_FRONTIER_BATTLE_FACTORY_PRE_BATTLE_ROOM", 5, 5, "up")
    f.lvlMode = 0
    Factory.init(session)
    Factory.generateInitialRentalMons(session)
    local keep = session.party
    session.party = {}
    local selectable = Factory.selectableMons(session)
    local done = false
    local refuseOnce = true             -- the driver's: reach the refusal without two of a species
    Select.show({ session = session, mons = selectable,
      speciesValid = function(chosen, monId)
        if refuseOnce then
          refuseOnce = false
          return false
        end
        return Factory.speciesValid(session, selectable, chosen, monId)
      end,
      onDone = function(chosen)
        Factory.copyMonsToPlayerParty(session, selectable, chosen)
        done = true
      end })
    local st = Select._st
    local function phase(name) return waitFor("select " .. name, function() return st.phase == name end, 300) end
    phase("choose")
    wait(10)
    taps({ "right", "right", "left" }, 16)
    tap("a", 10)
    phase("menu")
    wait(6)
    taps({ "down", "up" }, 16)
    tap("a", 10)                        -- SUMMARY
    local SummaryMenu = require("src.ui.game3.summary_menu")
    waitFor("summary", function() return SummaryMenu.isOpen() end, 200)
    wait(60)
    tap("b", 30)
    waitFor("menu again", function() return st.phase == "menu" and not SummaryMenu.isOpen() end, 400)
    wait(10)
    tap("down", 16)
    tap("a", 10)                        -- RENT: refused
    phase("invalid")
    wait(10)
    tap("a", 10)
    phase("choose")
    wait(10)
    tap("a", 10)
    phase("menu")
    wait(6)
    tap("down", 16)
    tap("a", 10)                        -- RENT
    phase("choose")
    wait(10)
    tap("a", 10)                        -- the chosen one again: DESELECT row
    phase("menu")
    wait(6)
    tap("down", 16)
    tap("up", 16)
    tap("b", 10)
    phase("choose")
    wait(6)
    for target = 1, 6 do
      if st.selectingState > 3 then break end
      for _ = 1, 8 do
        if st.cursor == target then break end
        tap("right", 12)
      end
      if st.mons[target].selectedId == 0 then
        tap("a", 10)
        phase("menu")
        wait(4)
        tap("down", 16)
        tap("a", 10)
        waitFor("rented", function() return st.phase ~= "menu" end, 100)
        if st.phase == "invalid" then
          wait(10)
          tap("a", 10)
        end
        waitFor("next", function() return st.phase == "choose" or st.phase == "yesno" end, 300)
        wait(6)
      end
    end
    phase("yesno")
    wait(6)
    taps({ "down", "up" }, 16)
    tap("a", 10)
    waitFor("select done", function() return done end, 400)
    wait(30)
    L.log("PARTY", tostring(#session.party))

    -- The swap screen with the three the player rented and three opponents.
    local enemy = {}
    for i = 1, 3 do enemy[i] = selectable[((i + 2) % 6) + 1].mon end
    enemy[1] = session.party[1]          -- reaches "already in your party"
    session.frontierEnemyParty = enemy
    done = false
    local result
    local function openSwap()
      done = false
      Swap.show({ session = session, party = session.party, enemy = enemy,
        sameSpecies = function(enemyMonId, playerMonId) return Factory.alreadyHasSameSpecies(session, enemyMonId, playerMonId) end,
        onDone = function(r) result = r done = true end })
    end
    openSwap()
    local sw = Swap._st
    local function swPhase(name) return waitFor("swap " .. name, function() return sw.phase == name end, 400) end
    swPhase("choose")
    wait(10)
    taps({ "right", "down", "up" }, 16)  -- second mon, CANCEL, the first
    L.log("CURSOR", tostring(sw.cursor))
    tap("a", 10)
    swPhase("menu")
    wait(6)
    taps({ "down", "up" }, 16)
    tap("down", 16)
    tap("a", 10)                         -- SWAP: the other side
    waitFor("enemy", function() return sw.phase == "choose" and sw.inEnemyScreen end, 800)
    wait(10)
    taps({ "right", "down", "down", "up" }, 16)
    L.log("CURSOR", tostring(sw.cursor))
    for _ = 1, 6 do
      if sw.cursor == 0 then break end
      tap("right", 14)
    end
    tap("a", 10)
    waitFor("answer", function() return sw.phase == "yesno" or sw.phase == "same_species" end, 400)
    wait(10)
    L.log("PHASE", tostring(sw.phase))
    if sw.phase == "same_species" then
      tap("a", 10)
      swPhase("choose")
      wait(6)
      tap("right", 14)
      tap("a", 10)
      waitFor("answer", function() return sw.phase == "yesno" end, 400)
      wait(10)
    end
    taps({ "down", "up" }, 16)
    tap("down", 16)
    tap("a", 10)                         -- NO: back to choosing
    swPhase("choose")
    wait(10)
    tap("b", 10)                         -- quit?
    swPhase("yesno")
    wait(10)
    tap("a", 10)                         -- YES
    waitFor("swap done", function() return done end, 400)
    L.log("RESULT", tostring(result and result.swapped))
    wait(20)
    session.party = keep
  end)

  section("pyramid", function()
    -- The floor by its map, after Pyramid.init and seedFloor as the lobby's scripts do.
    local Py = require("src.core.game3.rse.frontier.pyramid")
    f.lvlMode = 0
    Py.init(session)
    Py.initBag(session, 0)
    Py.seedFloor(session)
    goTo(Py.FLOOR_MAP, 8, 8, "up")
    L.log("MAP", tostring(session.map))
    wait(30)
    L.talk(10)
    local Items = consts
    Py.bagAdd(session, Items:require("items", "ITEM_HYPER_POTION"), 4)
    Py.bagAdd(session, Items:require("items", "ITEM_CHERI_BERRY"), 1)
    L.log("OPEN", tostring(openStart("pyramid_bag")))
    tap("a", 30)
    local PBag = require("src.ui.game3.rse.pyramid_bag")
    waitFor("bag", function() return PBag.isOpen() end, 120)
    wait(30)
    taps({ "down", "down", "down", "up", "up" }, 16)
    tap("up", 16)                        -- first row
    tap("a", 16)                         -- the actions grid
    taps({ "right", "down", "left", "up" }, 16)
    tap("b", 16)
    tap("a", 16)
    taps({ "down", "right" }, 16)
    L.log("MENU", tostring(PBag._st.menuCursor))
    tap("up", 16)
    tap("right", 16)
    tap("down", 16)                      -- ends at CANCEL
    tap("left", 16)                      -- TOSS
    L.log("MENU", tostring(PBag._st.menuCursor))
    tap("a", 16)
    L.log("MODE", tostring(PBag._st.mode))
    taps({ "up", "up", "down" }, 14)
    tap("a", 16)
    L.log("MODE", tostring(PBag._st.mode))
    taps({ "down", "up" }, 14)
    tap("a", 16)
    L.log("MODE", tostring(PBag._st.mode))
    tap("a", 20)
    L.log("MODE", tostring(PBag._st.mode))
    tap("select", 16)                    -- move an item
    L.log("MODE", tostring(PBag._st.mode))
    tap("down", 16)
    tap("b", 16)
    tap("b", 40)
    waitFor("closed", function() return not PBag.isOpen() end, 120)
    wait(30)
    L.log("TOP", tostring(L.top()))
    -- REST: the game's save menu with the pyramid's line.
    for _ = 1, 10 do
      local e = StartMenu.ENTRIES[StartMenu.cursor]
      if e and e.id == "rest_frontier" then break end
      tap("down", 12)
    end
    tap("a", 40)
    L.log("TOP", tostring(L.top()))
    wait(40)
    tap("b", 40)
    wait(30)
    L.log("TOP", tostring(L.top()))
    L.closeAll()
    L.talk(5)
    wait(20)
    -- RETIRE: rse/pyramid_retire.lua
    L.log("OPEN", tostring(openStart("retire_frontier")))
    tap("a", 40)
    mashUntil(function() return Choice.isOpen() end, 40)
    wait(20)
    taps({ "up", "down" }, 16)
    tap("a", 30)                         -- NO
    wait(30)
    L.talk(5)
    L.log("TOP", tostring(L.top()))
    -- ChooseItemsToTossFromPyramidBag
    local closed = false
    PBag.show({ session = session, location = "choose_toss", onClose = function() closed = true end })
    waitFor("toss bag", function() return PBag._st.fade == 0 end, 60)
    wait(10)
    tap("a", 16)
    tap("down", 16)
    tap("b", 16)
    tap("b", 30)
    waitFor("closed", function() return closed end, 120)
    wait(20)
    -- The bag from a battle (battle/ui.lua opens it with location "battle"): its smaller menu.
    closed = false
    PBag.show({ session = session, location = "battle", onClose = function() closed = true end })
    waitFor("battle bag", function() return PBag._st.fade == 0 end, 60)
    wait(10)
    tap("a", 16)
    tap("down", 16)
    tap("b", 16)
    tap("b", 30)
    waitFor("closed", function() return closed end, 120)
    wait(20)
    -- The peak's window
    f.curChallengeBattleNum = 7
    goTo(Py.TOP_MAP, 8, 8, "up")
    wait(30)
    L.talk(10)
    tap("start", 30)
    tap("b", 30)
    f.curChallengeBattleNum = 0
  end)

  section("pike", function()
    goTo("EM_BATTLE_FRONTIER_BATTLE_PIKE_THREE_PATH_ROOM", 6, 6, "up")
    wait(20)
    L.talk(10)
    tap("start", 30)
    taps({ "down", "down" }, 14)
    tap("b", 30)
    L.closeAll()
  end)

  section("hill", function()
    goTo("EM_TRAINER_HILL_ENTRANCE", 8, 11, "up")
    session.trainerHillTimes = { 3600 + 120, 90000, 7200, 54321 }
    tap("a", 20)                         -- the time board, by its own script
    local Records = require("src.ui.game3.rse.trainer_hill_records")
    waitFor("board", function() return Records.isOpen() end, 200)
    L.log("TOP", tostring(L.top()))
    wait(60)
    tap("a", 30)
    waitFor("closed", function() return not Records.isOpen() end, 200)
    wait(30)
    L.talk(5)
  end)

  L.log("END", tostring(L.top()))
  L.log("DONE", "rse_screens_frontier")
  love.event.quit()
end
