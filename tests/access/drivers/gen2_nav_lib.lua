-- Shared helpers for the Gen 2 navigation drivers (gen2_nav*.lua): wait for
-- the free world, log speech, choose objects from the live object list and
-- auto-walk to them, answer the game's prompts.  Harness setup (teleports,
-- party, badges) goes through the game's own World:setMap and save tables,
-- never through accessibility code.
local L = {}

function L.new(game)
  local U = dofile("tests/drivers/util.lua")
  local Speech = require("src.access.Speech")
  local AutoWalk = require("src.access.nav.AutoWalk")
  local self = { game = game, U = U, AutoWalk = AutoWalk, said = {} }

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

  function self.nav() return package.loaded["src.access.nav"].coordinator() end
  function self.adapter() return (package.loaded["src.access.nav"].bound()) end

  function self.free()
    local world = game.world
    return game.phase == "play" and world and world.map and game.stack:top() == nil
      and world:acceptsMenuInput()
  end

  function self.wait(n) U.wait(n or 1) end

  function self.tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 6)
  end

  function self.hold(button, frames) U.hold(game, button, frames) end

  -- Wait until the world has been free for `calm` frames in a row (a map's
  -- scene script starts a few frames after the map settles); press A
  -- through any text or prompt meanwhile.
  function self.settle(limit, mash, calm)
    calm = calm or 45
    local run = 0
    for _ = 1, limit or 600 do
      if self.free() then
        run = run + 1
        if run >= calm then return true end
        U.wait(1)
      else
        run = 0
        if mash and game.stack:top() ~= nil then self.tap("a", 8) else U.wait(1) end
      end
    end
    return self.free()
  end

  -- GEN2_NAV_NO_RELATCH=1 turns off the steering re-latch (evidence runs for
  -- the one-tile steering lag the survey predicted on Gen 2)
  if os.getenv("GEN2_NAV_NO_RELATCH") == "1" then
    require("src.access.nav.WorldAdapter").gen2.afterSteer = function() end
    U.log("NOTE", "steering re-latch disabled")
  end

  function self.pos()
    local p = game.world and game.world.player
    return game.world and game.world.map and game.world.map.id or "?",
      p and p.cellX or -1, p and p.cellY or -1
  end

  function self.where()
    local id, x, y = self.pos()
    return id .. " (" .. x .. "," .. y .. ")"
  end

  function self.teleport(mapId, x, y, facing)
    while game.stack:top() do game.stack:pop() end
    local ok = game.world:setMap(mapId, x, y, facing or "down")
    U.wait(30)
    self.settle(300, true)
    U.wait(10)
    return ok
  end

  -- A party mon knowing `moves`, plus badges by name.
  function self.giveParty(species, level, moves, badges)
    local Mon = require("src.battle.gen2.Mon")
    local mon = Mon.new(game.data, species, level)
    if moves then
      local list = {}
      for i, id in ipairs(moves) do list[i] = { id = id, pp = 10 } end
      mon.moves = list
    end
    game.save.party = { mon }
    game.save.player = game.save.player or {}
    game.save.player.badges = game.save.player.badges or {}
    for _, badge in ipairs(badges or {}) do game.save.player.badges[badge] = true end
    return mon
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

  function self.select(item, filter)
    local nav = self.nav()
    nav.browseFilter, nav.browseSelectionId = filter or "all", item and item.id
  end

  function self.steps()
    local w = self.AutoWalk._state()
    local s = {}
    for _, st in ipairs(w and w.steps or {}) do
      s[#s + 1] = st.fromX .. "," .. st.fromY .. ">" .. st.direction .. (st.kind and ("(" .. st.kind .. ")") or "")
    end
    return table.concat(s, " ")
  end

  -- Auto-walk to `item`; answer prompts with `answer` ("a" = yes) when the
  -- walk pauses on a screen; stop after `limit` frames.  Returns the speech.
  function self.walkTo(item, opts)
    opts = opts or {}
    self.select(item, opts.filter)
    self.heard()
    local nav = self.nav()
    AutoWalk.start(nav, game, self.adapter())
    U.log("STEPS", self.steps())
    local positions, lastCell = {}, nil
    for _ = 1, opts.limit or 3000 do
      if not AutoWalk.active() then break end
      local cell = self.where()
      if cell ~= lastCell then positions[#positions + 1] = cell lastCell = cell end
      if opts.onFrame then opts.onFrame() end
      if not AutoWalk.walking() and game.stack:top() ~= nil and opts.answer then
        game.input.pressQueue[#game.input.pressQueue + 1] = opts.answer
        game.input.state[opts.answer] = true
        U.wait(2)
        game.input.state[opts.answer] = false
        for _ = 1, 10 do
          if opts.onFrame then opts.onFrame() end
          U.wait(1)
        end
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

  return self
end

return L
