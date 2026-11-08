-- A game run for the quality-of-life module, on Crystal, with no core: the
-- driver installs modules/qol.lua with a fake ctx (experience x2, catch floor
-- on, blind trainers on), hands it the live game and the engine's own hook
-- table, and then
--   1. stands in Route 30's BUG CATCHER's line of sight and waits: he must not
--      come over; logs what the navigation's object list says about him; talks
--      to him and fights, logging the vanilla and paid experience per award;
--   2. stands in YOUNGSTER MIKEY's line (sight 1): nothing; switches the save
--      to vanilla and stands there again: he must engage, and pay x1;
--   3. switches back and talks to FALKNER: his scripted battle;
--   4. runs the Cherrygrove rival's scripted battle (the coord-event script);
--   5. opens a wild SUICUNE battle and asks the live battle's catch options
--      for the rate, randomized and vanilla.
-- Run silently and isolated, with a disposable identity:
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_BACKGROUND=1 POKEPORT_VERSION=crystal
--   POKEPORT_GAME=crystal POKEPORT_IDENTITY=pocket-access-rand2-qol-<x>
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=launcher/mods/crystal_randomizer/tests/qol_driver.lua
--   "C:\Program Files\LOVE\lovec.exe" .
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local Runtime = require("src.mods.Runtime")
  local Hooks = require("src.mods.Hooks")
  local Mon = require("src.battle.gen2.Mon")
  local Catching = require("src.battle.gen2.Catching")
  local BattleState = require("src.ui.gen2.BattleState")
  local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
  local Qol = dofile("launcher/mods/crystal_randomizer/modules/qol.lua")
  local passed, failed = 0, 0
  local function check(cond, ...)
    if cond then passed = passed + 1 else failed = failed + 1 end
    U.log(cond and "PASS" or "FAIL", ...)
  end

  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") love.event.quit() return end
  U.log("RESULT", "start", L.where())
  local data = game.data
  local seeingAtStart = #Qol.seeingTrainers(data.gen2Maps)

  local hooks = Runtime.hooks
  if type(hooks.wrap) ~= "function" then
    hooks = Hooks.new()
    Runtime.install(Runtime.events, hooks, Runtime.errors)
  end
  local options = { qol_exp = "2", qol_catch = true, qol_blind = true }
  local ctx = Fake.new({ seed = "qol-drive", options = options })
  Qol.install({ game = game, hooks = { wrap = function(_, name, fn)
    return hooks:wrap(name, fn, 0, "crystal_randomizer_driver")
  end } }, ctx)
  -- experience observers: the innermost link sees the vanilla amount, the
  -- outermost the amount the battle pays
  local awards, pending = {}, nil
  hooks:wrap("exp.gain", function(nextFn, ...)
    local amount = nextFn(...)
    pending = amount
    return amount
  end, -100, "qol_driver_observer")
  hooks:wrap("exp.gain", function(nextFn, ...)
    local amount = nextFn(...)
    awards[#awards + 1] = { vanilla = pending, paid = amount }
    return amount
  end, 100, "qol_driver_observer")
  ctx.setActive(true)
  for _, line in ipairs(ctx.lines) do U.log("MODLOG", line) end

  local function inBattle()
    for _, state in ipairs(game.stack.states or {}) do
      if type(state) == "table" and state.isBattle then return state end
    end
    return nil
  end
  local function party()
    local feraligatr = L.giveParty("FERALIGATR", 50, { "SURF", "ICE_BEAM", "BITE", "SLASH" })
    game.save.repelSteps = 60000
    game.options.battleStyle, game.options.battleScene, game.options.textSpeed = "SET", false, "FAST"
    return feraligatr
  end
  local function fightOut(limit)
    for _ = 1, limit or 20000 do
      if not inBattle() and L.free() then break end
      if not L.battleStep() then
        if game.stack:top() ~= nil or not L.free() then L.tap("a", 8) else U.wait(1) end
      end
    end
    L.settle(400, true)
  end
  local function reportAwards(label, num, den)
    local good = #awards > 0
    for _, a in ipairs(awards) do
      local want = math.max(1, math.floor(a.vanilla * num / den))
      U.log("RESULT", label, "award vanilla", a.vanilla, "paid", a.paid, "want", want)
      if a.paid ~= want then good = false end
    end
    check(good, label, "experience paid x" .. (num / den), "over", #awards, "awards")
    awards = {}
  end
  local function liveNpc(object)
    for _, npc in ipairs(game.world.npcs or {}) do
      if npc.def == object then return npc end
    end
  end
  local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
  -- Stands `d` cells in front of the trainer, facing him.  Returns the npc.
  local function standInLine(mapId, object, d)
    L.teleport(mapId, object.x, object.y + 3, "up")
    local npc = liveNpc(object)
    if not npc then return nil, "no live npc" end
    local delta = DELTA[npc.facing]
    if not delta then return nil, "no facing" end
    local x, y = npc.cellX + delta[1] * d, npc.cellY + delta[2] * d
    L.teleport(mapId, x, y, OPPOSITE[npc.facing])
    local id, px, py = L.pos()
    if id ~= mapId or px ~= x or py ~= y then return nil, "could not stand at " .. x .. "," .. y end
    return liveNpc(object)
  end
  -- Every trainer script the world starts, and whether its eyesight started it
  -- (driver instrumentation on this run's world object only).
  local engagements = {}
  local startTrainerScript = game.world.startTrainerScript
  game.world.startTrainerScript = function(world, who, script, sight, preparation)
    if not preparation then
      engagements[#engagements + 1] = { npc = who, sight = sight }
      U.log("RESULT", "trainer script started for", who and who.def and who.def.sprite,
        sight and ("by sight, " .. tostring(sight.distance) .. " cells") or "by talking")
    end
    return startTrainerScript(world, who, script, sight, preparation)
  end
  -- by the map object, since a teleport may pool a fresh npc for it
  local function sighted(npc)
    for _, e in ipairs(engagements) do
      if e.npc and npc and e.npc.def == npc.def and e.sight then return true end
    end
    return false
  end
  -- Waits `frames` on the open map; true when the trainer's eyesight engaged.
  local function engagedWithin(npc, frames)
    for _ = 1, frames do
      if sighted(npc) then return true end
      U.wait(1)
    end
    return sighted(npc)
  end
  local route30 = data.gen2Maps.ROUTE_30
  local function trainerAt(sprite, x, y)
    for _, o in ipairs(route30.objects) do
      if o.sprite == sprite and o.x == x and o.y == y and o.trainer then return o end
    end
  end

  -- ------------------------------------------------------------ 1. BUG CATCHER DON
  party()
  local don = trainerAt("SPRITE_BUG_CATCHER", 1, 7)
  check(don and don.sight == 0, "Route 30 BUG CATCHER's sight is", don and don.sight, "(vanilla 3)")
  local npc, why = standInLine("ROUTE_30", don, 2)
  if not npc then check(false, "stand in his line:", why) else
    U.log("RESULT", "standing at", L.where(), "trainer at", npc.cellX, npc.cellY, "facing", npc.facing)
    check(not engagedWithin(npc, 240), "blind: he did not come over in 4 seconds")
    local items = L.browse("all")
    local listed
    for _, item in ipairs(items) do
      U.log("ITEM", tostring(item.description))
      if tostring(item.description):find("Bug Catcher", 1, true) then listed = item end
    end
    check(listed ~= nil, "navigation lists him:", listed and listed.description or "nothing")
    -- talk: step next to him, facing him
    standInLine("ROUTE_30", don, 1)
    check(not engagedWithin(npc, 60), "blind: one cell away, still nothing until A")
    L.heard()
    L.tap("a", 10)
    local battle
    for _ = 1, 900 do
      battle = inBattle()
      if battle then break end
      L.tap("a", 8)
    end
    check(battle ~= nil, "talking to him starts his battle")
    U.log("RESULT", "his speech =>", L.heard())
    fightOut()
    reportAwards("bug catcher (talked, blind save)", 2, 1)
  end

  -- ------------------------------------------------------------ 2. MIKEY, blind then vanilla
  party()
  local mikey = trainerAt("SPRITE_YOUNGSTER", 5, 23)
  npc, why = standInLine("ROUTE_30", mikey, 1)
  if not npc then check(false, "stand in Mikey's line:", why) else
    check(not engagedWithin(npc, 180), "blind: MIKEY (sight 1) does not engage from the next cell")
    ctx.setActive(false)
    check(mikey.sight == 1, "vanilla save: MIKEY's sight is back to", mikey.sight)
    standInLine("ROUTE_30", mikey, 3)
    standInLine("ROUTE_30", mikey, 1)
    -- the teleport's own settle presses A through whatever follows, so the
    -- battle may already be over; the engagement record says how it began
    local engaged = engagedWithin(npc, 300)
    fightOut()
    check(engaged, "vanilla save: MIKEY's eyesight engages the player")
    reportAwards("mikey (sighted, vanilla save)", 1, 1)
    ctx.setActive(true)
  end

  -- ------------------------------------------------------------ 3. FALKNER
  party()
  L.teleport("VIOLET_GYM", 5, 2, "up")
  L.tap("a", 10)
  local falkner
  for _ = 1, 1500 do
    falkner = inBattle()
    if falkner then break end
    L.tap("a", 8)
  end
  local trainer = falkner and falkner.battle and falkner.battle.trainer
  check(falkner ~= nil, "blind save: FALKNER's battle starts when talked to (class",
    trainer and tostring(trainer.classId or trainer.class), ")")
  fightOut()
  reportAwards("falkner", 2, 1)

  -- ------------------------------------------------------------ 4. the Cherrygrove rival
  party()
  local cherry = data.gen2Maps.CHERRYGROVE_CITY
  local coord = cherry and cherry.coordEvents and cherry.coordEvents[1]
  if not coord then check(false, "no Cherrygrove coord event") else
    L.teleport("CHERRYGROVE_CITY", coord.x, coord.y, "right")
    game.world.vm:start(coord.scriptKey)
    local rival
    for _ = 1, 3000 do
      rival = inBattle()
      if rival then break end
      if game.stack:top() ~= nil or not L.free() then L.tap("a", 8) else U.wait(1) end
    end
    local t = rival and rival.battle and rival.battle.trainer
    check(rival ~= nil, "blind save: the rival's scripted battle starts (class",
      t and tostring(t.classId or t.class), ")")
    fightOut()
    reportAwards("rival", 2, 1)
  end

  -- ------------------------------------------------------------ 5. catching SUICUNE
  party()
  L.teleport("ROUTE_30", 5, 30, "down")
  local suicune = Mon.new(data, "SUICUNE", 40)
  game.world:startBattle({ wild = suicune }, function() end)
  local state
  for _ = 1, 1200 do
    local top = game.stack:top()
    if top and getmetatable(top) == BattleState and top.battle and top.battle.enemy then state = top break end
    U.wait(1)
  end
  if not state then check(false, "the SUICUNE battle did not open") else
    local function rateNow(ball)
      local opts = state:catchOptions(ball)
      opts.random = function() return 255 end -- never succeeds, so nothing is caught
      local _, rate = Catching.attempt(opts)
      return rate, opts.catchRate, state:catchChance(ball)
    end
    local rate, base, chance = rateNow("POKE_BALL")
    local want = Catching.rate({ catchRate = Qol.CATCH_FLOOR, maxHp = suicune.maxHp, hp = suicune.hp,
      ball = "POKE_BALL" })
    U.log("RESULT", "blind save: SUICUNE base", base, "thrown at rate", rate, "preview", tostring(chance))
    check(base == 3 and rate == want, "floor save: SUICUNE (3) is thrown at as", Qol.CATCH_FLOOR, "rate", rate)
    ctx.setActive(false)
    local vRate, _, vChance = rateNow("POKE_BALL")
    local vWant = Catching.rate({ catchRate = 3, maxHp = suicune.maxHp, hp = suicune.hp, ball = "POKE_BALL" })
    U.log("RESULT", "vanilla save: SUICUNE thrown at rate", vRate, "preview", tostring(vChance))
    check(vRate == vWant and type(vChance) == "number", "vanilla save: vanilla rate and the preview is back")
    ctx.setActive(true)
    fightOut()
    reportAwards("suicune (wild)", 2, 1)
  end

  ctx.setActive(false)
  local seeing = #Qol.seeingTrainers(data.gen2Maps)
  check(seeing == seeingAtStart and don.sight == 3, "vanilla at the end: every trainer sees again (",
    seeing, "of", seeingAtStart, ")")
  hooks:removeOwner("qol_driver_observer")
  U.log("SUMMARY", passed, "passed", failed, "failed")
  love.event.quit()
end
