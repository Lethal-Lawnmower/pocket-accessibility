-- Shared helpers for the FireRed navigation drivers (gen3_nav*.lua): boot a
-- new game, wait for the free field, log speech, choose objects from the
-- live object list and auto-walk to them, answer the game's prompts.
-- Harness setup (teleports, party, badges, items) goes through the game's
-- own Map.load, session, bag and flag store, never through accessibility
-- code.  Run silently and isolated (AGENTS.md):
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua ISOLATED_DRIVER=<driver>
local L = {}

function L.new(game)
  local U = dofile("tests/drivers/util.lua")
  local Speech = require("src.access.Speech")
  local AutoWalk = require("src.access.nav.AutoWalk")
  local self = { game = game, U = U, AutoWalk = AutoWalk, said = {}, failures = 0, checks = 0 }

  local say = Speech.say
  Speech.say = function(text, opts)
    self.said[#self.said + 1] = tostring(text)
    return say(text, opts)
  end

  function self.heard()
    local s = table.concat(self.said, " | ")
    self.said = {}
    return s
  end

  function self.check(ok, label)
    self.checks = self.checks + 1
    if not ok then self.failures = self.failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  function self.nav() return package.loaded["src.access.nav"].coordinator() end
  function self.adapter() return (package.loaded["src.access.nav"].bound()) end
  local Gen3 = require("src.access.nav.WorldAdapter").gen3

  function self.free() return Gen3.onMap(game) and not Gen3.transitioning() end

  function self.wait(n) U.wait(n or 1) end

  function self.tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 6)
  end

  local function messageOpen()
    local Message = package.loaded["src.ui.game3.message"]
    local Choice = package.loaded["src.ui.game3.choice"]
    return (Message and Message.isOpen and Message.isOpen()) or (Choice and Choice.active)
  end
  self.messageOpen = messageOpen
  self.battles, self.battlesLost = 0, 0
  local inBattle, battleMap = false, nil
  local function battleModule()
    return package.loaded["src.core.game3.battle.init"] or package.loaded["src.core.game3.battle"]
  end
  local function loadedOpen(name)
    local module = package.loaded[name]
    return module and module.isOpen and module.isOpen() and module or nil
  end

  -- What a battle is waiting on that upstream's auto-fight does not answer: "stats"
  -- (the level-up window), "forget" (the list of moves to forget), "choice" (a YES/NO
  -- question) or nil.  While Battle._auto is on, upstream's battle passes no input to
  -- these (src/core/game3/battle/init.lua, "Choice input during award": the block is
  -- skipped under _auto), so with auto-fight left on a level-up never ended.
  local function battlePrompt(Battle)
    if not (Battle and Battle._active and Battle.statWindowPhase and Battle.statWindowPhase()) then return nil end
    if loadedOpen("src.ui.game3.stat_growth") then return "stats" end
    if loadedOpen("src.ui.game3.summary_menu") then return "forget" end
    local Choice = package.loaded["src.ui.game3.choice"]
    if Choice and Choice.active then return "choice" end
    return nil
  end

  -- The last thing the battle's text box was given (its own log), on one line.
  local function battleQuestion()
    local Ui = package.loaded["src.core.game3.battle.ui"]
    local log = Ui and Ui._log
    return (tostring(log and log[#log] or ""):gsub("%s+", " "))
  end

  -- Where a battle stands, for a log line when one will not end.
  function self.battleState()
    local Battle = battleModule()
    if not (Battle and Battle._active) then return "no battle" end
    local Ui = package.loaded["src.core.game3.battle.ui"]
    return "battle phase " .. tostring(Battle._phase) .. ", menu " .. tostring(Ui and Ui._mode)
      .. ", waiting on " .. tostring(battlePrompt(Battle)) .. ", auto " .. tostring(Battle._auto)
      .. ", last text: " .. battleQuestion():sub(-90)
  end

  -- One press as the player at the controls, with auto-fight off for as long as the
  -- prompt is up and on again the frame it goes (before the battle's next step, so the
  -- turns that follow are still chosen for us).
  local function answerPrompt(Battle, button)
    Battle._auto = false
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    for frame = 1, 8 do
      U.wait(1)
      if frame == 2 then game.input.state[button] = false end
      if not battlePrompt(Battle) then break end
    end
    game.input.state[button] = false
    if not battlePrompt(Battle) then Battle._auto = true end
  end

  -- A battle: press through it (the harness party's first move wins).
  local function battleStep()
    local active = Gen3.battleActive()
    if active and not inBattle then
      self.battles = self.battles + 1
      battleMap = self.pos()
      U.log("BATTLE", "started at", self.where())
    end
    if not active and inBattle then
      U.log("BATTLE", "ended at", self.where())
      if self.pos() ~= battleMap then
        -- The battle was lost: the game took the player to a Pokemon Center.  Its
        -- "whited out" screen is no message box, so nothing else here pages it and the
        -- field never came free again (every later test said "Not on a map"); upstream's
        -- own test helper pages it.
        self.battlesLost = self.battlesLost + 1
        local last = {}
        for i = math.max(1, #self.said - 14), #self.said do last[#last + 1] = self.said[i] end
        U.log("WARN", "battle lost, from", tostring(battleMap), "to", self.where(), "|", table.concat(last, " | "):sub(-700))
        local ok, err = pcall(U.clearWhiteoutRush, game)
        if not ok then U.log("WARN", "clearWhiteoutRush:", tostring(err)) end
      end
    end
    inBattle = active
    if active then
      self.heal()
      local Battle = battleModule()
      local prompt = battlePrompt(Battle)
      if prompt == "stats" then
        -- both pages of the level-up window
        answerPrompt(Battle, "a")
      elseif prompt == "forget" then
        -- never forget a move the walks need: back out, to "stop learning?"
        answerPrompt(Battle, "b")
      elseif prompt == "choice" then
        -- a new move is declined as a player would: NO to "delete a move?", YES to
        -- "stop learning?"; any other question (a nickname, changing Pokemon) is NO
        local LearnMove = package.loaded["src.core.game3.battle.learn_move"]
        local question = battleQuestion()
        local learning = LearnMove and LearnMove.waitingChoice and LearnMove.waitingChoice()
        local yes = learning and question:find("Stop learning", 1, true) ~= nil
        if learning then U.log("BATTLE", "answered", yes and "YES" or "NO", "to", question:sub(-80)) end
        answerPrompt(Battle, yes and "a" or "b")
      else
        -- upstream's own auto-fight switch (the battle's autoFight option)
        -- chooses the moves; A pages the text and every third press is B,
        -- which backs out of "Will you change POKéMON?" and the party screen
        if Battle and Battle._active then Battle._auto = true end
        self.battleTaps = (self.battleTaps or 0) + 1
        self.tap(self.battleTaps % 3 == 0 and "b" or "a", 6)
      end
      return true
    end
    return false
  end
  self.battleStep = battleStep

  -- A battle still up after a walk was stopped: play it to its end, so that the next
  -- test starts on the field and one stall cannot fail everything after it.  A battle
  -- that still will not end is left through the game's own Battle.abort, and logged.
  -- Returns true when the field is free.
  function self.endBattle(limit)
    if Gen3.battleActive() then
      for _ = 1, limit or 4000 do
        if not battleStep() then break end
      end
      if Gen3.battleActive() then
        U.log("WARN", "battle would not end, left by Battle.abort:", self.battleState())
        local Battle = battleModule()
        local ok, err = pcall(function() Battle.abort("run") end)
        if not ok then U.log("WARN", "Battle.abort:", tostring(err)) end
        U.wait(60)
      end
      battleStep() -- logs the end
    end
    return self.settle(900, true)
  end

  -- Wait until the field has been free for `calm` frames in a row; press A
  -- (or `mash`) through text meanwhile.
  function self.settle(limit, mash, calm)
    calm = calm or 30
    local run = 0
    for _ = 1, limit or 600 do
      if self.free() then
        run = run + 1
        if run >= calm then return true end
        U.wait(1)
      else
        run = 0
        if battleStep() then
          -- pressed A in the battle
        elseif mash and messageOpen() then
          self.tap(type(mash) == "string" and mash or "a", 8)
        else
          U.wait(1)
        end
      end
    end
    return self.free()
  end

  function self.session() return require("src.core.game3.runtime").getSession() end

  function self.pos()
    local Map = package.loaded["src.core.game3.map"]
    local P = package.loaded["src.core.game3.player"]
    return Map and Map.current or "?", P and P.cellX or -1, P and P.cellY or -1
  end

  function self.where()
    local id, x, y = self.pos()
    return id .. " (" .. x .. "," .. y .. ")"
  end

  -- Boot to the title and start a new game the way upstream's Gen 3 drivers
  -- do (tests/drivers/em_fa_util.lua F.boot), then talk through the opening.
  function self.boot()
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then break end
      U.wait(1)
    end
    local ok, err = pcall(function()
      game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
    end)
    if not ok then U.log("FAIL", "new game: " .. tostring(err)) return false end
    U.wait(60)
    self.settle(3000, true)
    U.log("MAP", self.where())
    return true
  end

  -- Teleport through the game's own map loader (as F.goTo does).
  function self.teleport(mapId, x, y, facing)
    AutoWalk.stop()
    if Gen3.battleActive() then self.endBattle() end -- never load a map under a battle
    self.settle(300, true, 5)
    local Map = require("src.core.game3.map")
    local Player = require("src.core.game3.player")
    local Runtime = require("src.core.game3.runtime")
    local ok, err = pcall(function() Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" }) end)
    if not ok then U.log("FAIL", "Map.load " .. mapId .. ": " .. tostring(err)) end
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing or "down" end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    Player.moveDir = facing or "down"
    Player.moving = false
    U.wait(40)
    self.settle(600, true)
    return ok and (package.loaded["src.core.game3.map"].current == mapId)
  end

  -- A party Pokemon (species, level) knowing `moves` (field move names plus
  -- a damaging move), and badges by field move, through the game's own
  -- Party.giveMon and flag store (as tests/drivers/game3_* do).
  function self.giveParty(species, level, moves, badges)
    local s = self.session()
    local Party = require("src.core.game3.party")
    local FieldMoves = require("src.core.game3.field_moves")
    local Space = require("src.core.game3.scripting.space")
    local Flags = require("src.core.game3.scripting.flags")
    Flags.setFlag(Space.store, nil, 0x828, true) -- FLAG_SYS_POKEMON_GET
    s.party = {}
    Party.giveMon(s, species or 6, level or 60)
    local mon = s.party[1]
    -- Hydro Pump first: auto-fight uses move 1 (Flamethrower met a Flash
    -- Fire Ponyta in Victory Road and the battle never ended)
    local ids, pp = { 56 }, { 30 }
    for _, name in ipairs(moves or {}) do
      ids[#ids + 1] = FieldMoves.MOVES[name] or name
      pp[#pp + 1] = 30
    end
    mon.moves, mon.pp, mon.maxPp = ids, pp, { unpack(pp) }
    for _, key in ipairs(badges or {}) do
      Flags.setFlag(Space.store, nil, FieldMoves.BADGE_FLAGS[key], true)
    end
    return mon
  end

  function self.setVar(var, value)
    local Space = require("src.core.game3.scripting.space")
    local Flags = require("src.core.game3.scripting.flags")
    Flags.setVar(Space.store, Space.vm and Space.vm.ctx or nil, var, value)
  end

  function self.setFlag(flag, on)
    local Space = require("src.core.game3.scripting.space")
    local Flags = require("src.core.game3.scripting.flags")
    Flags.setFlag(Space.store, Space.vm and Space.vm.ctx or nil, flag, on ~= false)
  end

  -- What a Pokemon Center does for the party: HP, status and PP (30 a move, as the
  -- harness gives them).  In a battle the Pokemon out is a copy that is written back
  -- over the party when the battle ends, so its HP is topped up too: with HP alone and
  -- the party alone, a status condition or the damage of several battles on one walk
  -- could lose a battle, and a FireRed story run whited out in Viridian Gym.
  function self.heal()
    for _, mon in ipairs(self.session().party or {}) do
      local max = tonumber(mon.maxHP or mon.maxHp or (mon.stats and mon.stats.hp))
      if max then mon.hp = max end
      mon.status, mon.sleep = nil, nil
      if type(mon.pp) == "table" then
        for i in ipairs(mon.moves or {}) do mon.pp[i] = math.max(tonumber(mon.pp[i]) or 0, 30) end
      end
    end
    local Battle = battleModule()
    local st = Battle and Battle._active and Battle._st
    local out = st and st.player and st.player.mon
    if out and (tonumber(out.hp) or 0) > 0 and tonumber(out.maxHp) then out.hp = tonumber(out.maxHp) end
  end

  -- Hold a direction for `frames` (a step across a connection or a push).
  function self.hold(dir, frames)
    for i = 1, frames or 20 do
      if i == 1 then game.input.pressQueue[#game.input.pressQueue + 1] = dir end
      game.input.state[dir] = true
      U.wait(1)
    end
    game.input.state[dir] = false
    U.wait(4)
  end

  -- Wait for guided navigation's first words (they come from a route task).
  function self.guide(item, filter)
    self.select(item, filter)
    self.heard()
    self.nav():handleCommand("describe_route_to_selected_item")
    for _ = 1, 120 do
      if #self.said > 0 then break end
      U.wait(1)
    end
    U.wait(5)
    local said = self.heard()
    self.nav():handleCommand("describe_route_to_selected_item") -- stop
    U.wait(2)
    self.heard()
    return said
  end

  function self.giveItem(item, qty)
    local s = self.session()
    require("src.core.game3.bag").add(s.bag, item, qty or 1)
  end

  function self.browse(filter)
    local nav = self.nav()
    if not nav then return {} end
    local snap, reason = nav:captureWorld(filter or "all")
    if not snap then U.log("BROWSE", "failed:", tostring(reason)) return {} end
    return snap.browse or {}, snap
  end

  function self.logBrowse(filter)
    local items = self.browse(filter)
    for _, item in ipairs(items) do U.log("ITEM", tostring(item.description)) end
    return items
  end

  function self.find(predicate, filter)
    for _, item in ipairs(self.browse(filter)) do
      if predicate(item) then return item end
    end
    return nil
  end

  function self.findLabel(pattern, filter)
    return self.find(function(item) return tostring(item.label):find(pattern) ~= nil end, filter)
  end

  function self.select(item, filter)
    local nav = self.nav()
    nav.browseFilter, nav.browseSelectionId = filter or "all", item and item.id
  end

  function self.steps()
    local w = AutoWalk._state()
    local s = {}
    for _, st in ipairs(w and w.steps or {}) do
      s[#s + 1] = st.fromX .. "," .. st.fromY .. ">" .. st.direction .. (st.kind and ("(" .. st.kind .. ")") or "")
    end
    return table.concat(s, " ")
  end

  -- Auto-walk to `item`; answer prompts with `answer` when the walk pauses
  -- on a message ("a" = yes); stop after `limit` frames.  Returns speech.
  function self.walkTo(item, opts)
    opts = opts or {}
    self.select(item, opts.filter)
    self.heard()
    AutoWalk.start(self.nav(), game, self.adapter())
    U.log("STEPS", self.steps())
    local positions, lastCell = {}, nil
    for _ = 1, opts.limit or 3000 do
      if not AutoWalk.active() then break end
      local cell = self.where()
      if cell ~= lastCell then positions[#positions + 1] = cell lastCell = cell end
      if opts.onFrame then opts.onFrame() end
      if battleStep() then
        -- pressed A in the battle
      elseif not AutoWalk.walking() and messageOpen() and opts.answer then
        self.tap(opts.answer, 10)
      else
        U.wait(1)
      end
    end
    if AutoWalk.active() then AutoWalk.stop() U.log("WARN", "walk still active at limit") end
    if opts.trace then U.log("PATH", table.concat(positions, " ")) end
    return self.heard()
  end

  function self.command(actionId)
    self.heard()
    self.nav():handleCommand(actionId)
    return self.heard()
  end

  function self.finish(name)
    U.log("RESULT", name, self.checks - self.failures .. "/" .. self.checks)
    U.log(self.failures == 0 and "PASS" or "FAIL", name .. " failures=" .. self.failures)
  end

  return self
end

return L
