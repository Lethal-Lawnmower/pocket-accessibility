-- Gen 2 special screens: opens each minigame and special screen on the real
-- stack and plays it with button presses, logging every screen change.  Run
-- with POKEPORT_ACCESS_TRACE=1 so each utterance prints as a `say:` line
-- (`say!:` when it interrupts); it asserts nothing, so the trace shows what
-- the layer says on each screen.
--
-- Silent, disposable identity, one game at a time:
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_BACKGROUND=1 POKEPORT_ACCESS_TRACE=1
--   POKEPORT_TOUCH=0 POKEPORT_IDENTITY=pocket-access-special-<game>
--   POKEPORT_VERSION=<game> POKEPORT_GAME=<game>
--   POKEPORT_DRIVER=tests/access/drivers/gen2_special.lua lovec .
-- With a driver set, Game2 starts the world directly (no boot cinema).  The
-- Battle Tower picker, Buena's screens and the Unown wall words run only in
-- Crystal.  The run ends with a real Hall of Fame induction (which saves
-- into the disposable identity) and the credits.  Some setup is forced by
-- the driver and logged as FORCED: the party, coins, decorations, mail, a
-- Hall of Fame team for the PC viewer, and the first slot spin's reels 1 and
-- 2 placed on SEVEN so the reel 3 near-miss shows (and maybe a win) appear.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local version = require("src.core.GameVersion").get()
  local crystal = version == "crystal"

  local function className(state)
    if state == nil then return "overworld" end
    local mt = getmetatable(state)
    for name, mod in pairs(package.loaded) do
      if mod == mt and type(name) == "string" then return (name:gsub("^src%.ui%.", "")) end
    end
    return tostring(mt)
  end
  local lastTop
  local function watch()
    local name = className(game.stack:top())
    if name ~= lastTop then
      U.log("SCREEN", name)
      lastTop = name
    end
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
  local function section(name) U.log("SECTION", name) end
  local function gone(state, frames)
    for _ = 1, frames or 600 do
      if top() ~= state then return true end
      wait(1)
    end
    U.log("STUCK", className(top()))
    while top() do game.stack:pop() end
    wait(10)
    return false
  end
  local function push(id, opts)
    local Screens = require("src.ui.Screens")
    Screens.push(game, id, opts)
    wait(10)
    return top()
  end
  local function pop() game.stack:pop() end
  -- run `step` until it returns false or `frames` frames have passed
  local function during(frames, step)
    local deadline = U.frame() + frames
    while U.frame() < deadline do
      if step() == false then return end
    end
    U.log("TIMEOUT", className(top()))
  end

  for _ = 1, 900 do
    if game.world and game.world.map and not top() then break end
    wait(1)
  end
  if not (game.world and game.world.map) then U.log("FAIL", "no world") return end
  local world, save, data = game.world, game.save, game.data
  U.log("GAME", version, world.map.id)

  local Mon = require("src.battle.gen2.Mon")
  save.party = { Mon.new(data, "CYNDAQUIL", 30), Mon.new(data, "PIKACHU", 25) }
  save.player.coins = 60
  U.log("FORCED", "party CYNDAQUIL 30, PIKACHU 25; 60 coins")
  wait(30)

  -- ------------------------------------------------------------ Card Flip
  section("Card Flip")
  world:gameCornerGame("cardflip")
  wait(10)
  local flip = top()
  local hands, moves = 0, { "right", "up", "up", "down", "left", "left", "down", "down", "right", "up" }
  during(3000, function()
    if top() ~= flip then return false end
    local phase = flip.phase
    if phase == "ask" or phase == "choose" or phase == "message" or phase == "result" then
      tap("a", 12)
    elseif phase == "bet" then
      if hands == 0 then for _, d in ipairs(moves) do tap(d, 10) end end
      hands = hands + 1
      tap("a", 12)
    elseif phase == "again" then
      if hands >= 2 then tap("down", 10) end
      tap("a", 12)
    else
      wait(1)
    end
  end)
  gone(flip)
  wait(30)

  -- ------------------------------------------------------------ slots
  section("Slot machine")
  save.player.coins = 60
  world:gameCornerGame("slots")
  wait(10)
  local slots = top()
  local SM = getmetatable(slots)
  local spins = 0
  during(6000, function()
    if top() ~= slots then return false end
    local phase = slots.phase
    if phase == "bet" then
      if spins == 0 then
        tap("down", 10) tap("up", 10)
      else
        tap("down", 10) tap("down", 10)
      end
      tap("a", 4)
      spins = spins + 1
    elseif phase == "spinning" then
      local busy = (slots.delay or 0) > 0 or slots.reel2Pause or slots.golemAnim or slots.chanseyAnim
        or slots.stops[slots.reel]
      if busy then
        wait(1)
      else
        -- First spin: reels 1 and 2 placed on a middle SEVEN with no bias
        -- just before A, so they stop there and reel 3 runs its near-miss.
        if spins == 1 and slots.reel <= 2 then
          for p = 0, SM.REEL_SIZE - 1 do
            local _, middle = SM.window(SM.REELS[slots.reel], p)
            if middle == SM.SEVEN then
              slots.bias, slots.positions[slots.reel], slots.distance[slots.reel] = SM.NO_BIAS, p, 0
              U.log("FORCED", "reel " .. slots.reel .. " placed on SEVEN before A")
              break
            end
          end
        end
        tap("a", 24)
      end
    elseif phase == "payoutText" and slots.matched == SM.NO_MATCH then
      tap("a", 12)
    elseif phase == "again" then
      if spins >= 2 then tap("down", 10) end
      tap("a", 12)
    else
      wait(1)
    end
  end)
  gone(slots)
  wait(30)

  -- ------------------------------------------------------------ Unown puzzle
  section("Unown puzzle")
  world:unownPuzzle(0, function(solved) U.log("PUZZLE", "solved", tostring(solved)) end)
  wait(10)
  local puzzle = top()
  tap("right", 10) tap("down", 10) tap("left", 10)
  tap("a", 10) tap("right", 10) tap("a", 10)
  tap("left", 10) tap("left", 10)
  local UP = getmetatable(puzzle)
  local board = {}
  for i, v in ipairs(UP.SOLVED) do board[i] = v end
  board[29], board[36] = 0, 16
  puzzle.pieces, puzzle.holding, puzzle.held, puzzle.cursor = board, false, 0, 29
  U.log("FORCED", "board set to solved except piece 16 at row 6 column 6; cursor row 5 column 6")
  wait(4)
  tap("down", 10) tap("a", 10) tap("up", 10) tap("left", 10) tap("a", 30)
  tap("a", 10)
  gone(puzzle)
  wait(20)

  -- ------------------------------------------------------------ stamp viewer
  section("Alph Ruins stamp")
  world:showUnownPrinter(function() end)
  wait(10)
  local stamp = top()
  tap("right", 10) tap("right", 10) tap("left", 10) tap("left", 10) tap("left", 10)
  tap("b", 10)
  gone(stamp)

  -- ------------------------------------------------------------ cards
  section("Diploma")
  world:showDiploma(function() end)
  wait(30)
  local diploma = top()
  tap("a", 10)
  gone(diploma)

  section("Photo studio")
  world:showPhotoStudio(save.party[2], function() end)
  wait(30)
  local photo = top()
  tap("a", 10)
  gone(photo)

  section("Magnet Train")
  world:magnetTrain(false, function() end)
  wait(10)
  gone(top(), 4000)
  wait(20)

  -- ------------------------------------------------------------ contest switch
  section("Contest switch")
  local contest = push("Gen2ContestMenu", { save = save,
    stock = Mon.new(data, "CATERPIE", 7), caught = Mon.new(data, "SCYTHER", 13),
    onClose = function() pop() end })
  tap("down", 10) tap("up", 10) tap("b", 10)
  gone(contest)

  -- ------------------------------------------------------------ Day-Care
  -- press A through a conversation screen and any party list it opens
  local function converse(screen)
    during(4000, function()
      local t = top()
      if t == nil then return false end
      if t ~= screen and className(t) ~= "gen2.PartyMenu" then return false end
      tap("a", 16)
    end)
  end
  section("Day-Care deposit")
  world:dayCare("man", function() end)
  wait(10)
  converse(top())
  wait(20)
  section("Day-Care withdraw")
  world:dayCare("man", function() end)
  wait(10)
  converse(top())
  wait(20)
  section("Day-Care outside")
  world:dayCare("outside", function() end)
  wait(10)
  converse(top())
  wait(20)

  -- ------------------------------------------------------------ NPC trade
  section("NPC trade")
  local NpcTrade = require("src.core.gen2.NpcTrade")
  local row = NpcTrade.row(world.eventTables, 0)
  if row then
    local mon = Mon.new(data, row.give, 10)
    if row.gender == NpcTrade.TRADE_GENDER_MALE then mon.gender = "male"
    elseif row.gender == NpcTrade.TRADE_GENDER_FEMALE then mon.gender = "female" end
    table.insert(save.party, 1, mon)
    U.log("FORCED", "party leads with " .. tostring(row.give) .. " for trade 0")
    world:openNpcTrade(0, function() end)
    wait(10)
    local trade = top()
    during(8000, function()
      if top() == nil then return false end
      local name = className(top())
      if name == "gen2.TradeAnim" then wait(1)
      elseif top() == trade or name == "gen2.PartyMenu" then tap("a", 16)
      else return false end
    end)
  else
    U.log("SKIP", "no NPC trade row")
  end
  wait(20)

  -- ------------------------------------------------------------ decorations
  section("Decorations")
  local Decorations = require("src.core.gen2.Decorations")
  Decorations.give(world.events, 3)
  Decorations.give(world.events, 30)
  U.log("FORCED", "own PINK BED and PIKACHU DOLL")
  local deco = push("Gen2DecorationMenu", { save = save, events = world.events,
    onDone = function() pop() end })
  local function drain()
    during(1200, function()
      if not deco.pages then return false end
      tap("a", 16)
    end)
  end
  tap("down", 10) tap("up", 10)
  tap("a", 10)                 -- open the first category
  tap("down", 10) tap("a", 16) -- set something up
  drain()
  tap("b", 10)                 -- back to the categories
  for _ = 1, 8 do
    local category = deco.categories and deco.categories[deco.index]
    if category and category.label == "ORNAMENT" then break end
    tap("down", 10)
  end
  tap("a", 10) tap("a", 10)    -- ORNAMENT, first doll
  tap("down", 10) tap("up", 10)
  tap("a", 16)                 -- first side
  drain()
  tap("b", 10) tap("b", 10)
  gone(deco)

  -- ------------------------------------------------------------ mail
  section("Mail compose")
  local compose = push("Gen2MailCompose", { onDone = function(message)
    U.log("MAIL", message) pop() end })
  for _ = 1, 7 do tap("right", 6) end
  tap("a", 10) tap("right", 6) tap("a", 10)
  tap("select", 10) tap("a", 10)
  tap("down", 6) tap("down", 6) tap("down", 6)
  tap("a", 10)
  tap("down", 6) tap("right", 6)
  tap("b", 10)
  tap("start", 10) tap("a", 10)
  gone(compose)

  local Mail = require("src.core.gen2.Mail")
  section("Mail read")
  local read = push("Gen2MailRead", { entry = Mail.entry("FLOWER_MAIL", "HELLO THERE\nMY FRIEND", "KRIS", 1, "PIKACHU"),
    onClose = function() pop() end })
  tap("a", 10)
  gone(read)

  section("Mail menu")
  save.party[1].item = "SURF_MAIL"
  Mail.set(save, 1, Mail.entry("SURF_MAIL", "SEE YOU SOON", "MOM", 2, "PIKACHU"))
  U.log("FORCED", "party lead holds SURF MAIL")
  local mailMenu = push("Gen2MailMenu", { save = save, slot = 1, onClose = function() pop() end })
  tap("down", 10) tap("up", 10) tap("a", 20)
  tap("a", 20)
  gone(mailMenu)

  section("Mailbox")
  local mailState = Mail.state(save)
  mailState.box = { Mail.entry("EON_MAIL", "THANKS", "ELM", 3, "TOGEPI"), Mail.entry("LOVELY_MAIL", "HI", "", 0, "PIKACHU") }
  U.log("FORCED", "two letters in the PC mailbox")
  local box = push("Gen2MailboxMenu", { save = save, onClose = function() pop() end })
  tap("down", 10) tap("a", 10) tap("down", 10) tap("up", 10) tap("b", 10)
  tap("b", 10)
  gone(box)

  -- ------------------------------------------------------------ Crystal only
  if crystal then
    section("Battle Tower levels")
    local BattleTower = require("src.core.gen2.BattleTower")
    local tower = push("Gen2BattleTowerMenu", { save = save, party = save.party,
      rows = BattleTower.levelGroupRows(save), onDone = function(group) U.log("TOWER", tostring(group)) end })
    tap("up", 10) tap("up", 10) tap("down", 10) tap("down", 10)
    tap("a", 10)
    wait(160)
    tap("b", 10) tap("down", 10) tap("up", 10) tap("a", 10)
    gone(tower)

    section("Buena password")
    local pass = push("Gen2BuenaPassword", { mode = "password", words = { "CYNDAQUIL", "TOTODILE", "CHIKORITA" },
      width = 9, onDone = function(i) U.log("BUENA", tostring(i)) end })
    tap("down", 10) tap("down", 10) tap("a", 10)
    gone(pass)

    section("Buena prizes")
    local prizes = push("Gen2BuenaPassword", { mode = "prize", balance = 4,
      prizes = { { name = "ULTRA BALL", cost = 2 }, { name = "NUGGET", cost = 3 }, { name = "PROTEIN", cost = 5 } },
      onDone = function(i) U.log("BUENA", tostring(i)) end })
    tap("down", 10) tap("down", 10) tap("b", 10)
    gone(prizes)

    section("Unown wall words")
    local UnownWords = require("src.world.gen2.UnownWords")
    local wall = UnownWords.wallFor(data, 0)
    if wall then
      game.stack:push(UnownWords.new(game, { wall = wall, world = world, onClose = function() end }))
      wait(20)
      local words = top()
      tap("a", 10)
      gone(words)
    else
      U.log("SKIP", "no wall data")
    end
  end

  -- ------------------------------------------------------------ Union Room list
  section("Union Room list")
  local List = require("src.ui.gen2.union.List")
  game.stack:push(List.new(game, "TRADING BOARD", { { label = "PIKACHU", right = "Lv25" },
    { label = "ONIX", right = "Lv14" } }, function() end))
  wait(10)
  local list = top()
  tap("down", 10) tap("b", 10)
  gone(list)

  -- ------------------------------------------------------------ Hall of Fame
  section("Hall of Fame viewer")
  local HOFCore = require("src.core.gen2.HallOfFame")
  HOFCore.induct(save, save.party, {})
  U.log("FORCED", "one Hall of Fame team recorded for the viewer")
  local viewer = push("Gen2HallOfFame", { save = save, mode = "view", text = world.text,
    onDone = function() pop() end })
  -- the viewer reads no buttons while a picture animates
  local function settled()
    during(900, function()
      if top() ~= viewer or not viewer.picAnim then return false end
      wait(1)
    end)
  end
  settled() tap("a", 10)
  settled() tap("a", 10)
  settled() tap("b", 20)
  gone(viewer)

  section("Hall of Fame induction and credits")
  world:hallOfFame(function() U.log("CREDITS", "done") end)
  during(30000, function()
    local state = top()
    local name = className(state)
    if name == "gen2.Credits" and state.exiting then
      wait(30)
      tap("a", 30)
      return false
    end
    if name ~= "gen2.HallOfFame" and name ~= "gen2.Credits" then return false end
    wait(1)
  end)
  wait(60)
  U.log("DONE")
  love.event.quit(0)
end
