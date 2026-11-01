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
  self.battles = 0
  local inBattle = false
  -- A battle: press A through it (the harness party's first move wins).
  local function battleStep()
    local active = Gen3.battleActive()
    if active and not inBattle then self.battles = self.battles + 1 U.log("BATTLE", "started at", self.where()) end
    if not active and inBattle then U.log("BATTLE", "ended at", self.where()) end
    inBattle = active
    if active then
      self.heal()
      -- upstream's own auto-fight switch (the battle's autoFight option)
      -- chooses the moves; A pages the text and every third press is B,
      -- which backs out of "Will you change POKéMON?" and the party screen
      local Battle = package.loaded["src.core.game3.battle.init"] or package.loaded["src.core.game3.battle"]
      if Battle and Battle._active then Battle._auto = true end
      self.battleTaps = (self.battleTaps or 0) + 1
      self.tap(self.battleTaps % 3 == 0 and "b" or "a", 6)
      return true
    end
    return false
  end
  self.battleStep = battleStep

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
    mon.moves, mon.pp, mon.maxPp = ids, pp, pp
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

  function self.heal()
    for _, mon in ipairs(self.session().party or {}) do
      local max = tonumber(mon.maxHP or mon.maxHp or (mon.stats and mon.stats.hp))
      if max then mon.hp = max end
    end
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
