-- Game-run check for modules/trainers.lua on Crystal.  Installs the module
-- with a fake ctx (the randomizer core is not part of this check), then opens
-- real trainer battles through World:trainerParty + World:startScriptedBattle,
-- the path a `loadtrainer` / `startbattle` script takes, and logs the party
-- each battle actually fights:
--   1. FALKNER, randomized (seed "drive", similar strength on);
--   2. the Cherrygrove rival (RIVAL1_1_CHIKORITA) with ctx.shared.starters set,
--      whose mon must be the CHIKORITA ball's replacement (MAREEP);
--   3. FALKNER again with the save switched to vanilla: the vanilla party.
-- The battles are fought with a level 100 MEWTWO pressing the first move.
--
-- Run silently and isolated, with a disposable identity:
--   POKEPORT_IDENTITY=pocket-access-rand-trainers-run POKEPORT_ACCESS_SILENT=1
--   POKEPORT_BACKGROUND=1 POKEPORT_VERSION=crystal POKEPORT_GAME=crystal
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=launcher/mods/crystal_randomizer/tests/trainers_driver.lua
--   lovec .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
  local module = dofile("launcher/mods/crystal_randomizer/modules/trainers.lua")
  local Runtime = require("src.mods.Runtime")
  local Hooks = require("src.mods.Hooks")
  local Mon = require("src.battle.gen2.Mon")
  local BattleState = require("src.ui.gen2.BattleState")

  local function top() return game.stack:top() end
  local function isBattle(s) return s ~= nil and getmetatable(s) == BattleState end
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 8)
  end

  U.wait(60)
  if not (game.world and game.world.map) then U.log("FAIL the world did not start") return end

  -- A live hook bus: the loader's when mods are on, a fresh one otherwise.
  local hooks = Runtime.hooks
  if type(hooks.wrap) ~= "function" then
    hooks = Hooks.new()
    Runtime.install(Runtime.events, hooks, Runtime.errors)
  end
  local ctx = Fake.new({ seed = "drive", options = { trainers = true, trainers_similar = true } })
  ctx.shared.starters = { CHIKORITA = "MAREEP", CYNDAQUIL = "LARVITAR", TOTODILE = "EEVEE" }
  module.install({ game = game, hooks = { wrap = function(_, name, fn)
    return hooks:wrap(name, fn, 0, "crystal_randomizer_test")
  end } }, ctx)

  local data = game.data
  game.save.party = { Mon.new(data, "MEWTWO", 100, {}) }

  local function describe(party)
    local out = {}
    for i, mon in ipairs(party or {}) do
      local moves = {}
      for j, m in ipairs(mon.moves or {}) do moves[j] = type(m) == "table" and m.id or tostring(m) end
      out[i] = ("%s L%d [%s]%s"):format(mon.species, mon.level, table.concat(moves, " "),
        mon.item and (" @" .. mon.item) or "")
    end
    return table.concat(out, "; ")
  end

  local function fight(label, classId, member)
    for _, mon in ipairs(game.save.party) do Mon.restoreAllPp(mon, data) mon.hp = mon.maxHp end
    local class = data.gen2Trainers.classes[classId]
    local record = game.world:trainerParty(class.index, member)
    if not record then U.log("FAIL", label, "no trainer record") return nil end
    U.log("ROSTER", label, record.id, describe(record.roster))
    local finished, outcome = false, nil
    game.world:startScriptedBattle(record, nil, function(result) finished, outcome = true, result end)
    local logged, seen = nil, nil
    for _ = 1, 30000 do
      if finished then break end
      local t = top()
      if isBattle(t) then
        seen = t
        if not logged and t.battle and t.battle.enemyParty then
          logged = describe(t.battle.enemyParty)
          U.log("FIGHTS", label, logged)
          U.log("TRAINER-PARTY", label, describe(t.battle.trainer and t.battle.trainer.party))
        end
        if (t.messageTimer or 0) > 0 then tap("a", 10)
        elseif t.phase == "menu" or t.phase == "moves" then tap("a", 12)
        else U.wait(1) end
      elseif seen and t ~= nil and t ~= game.overworld then
        tap("a", 12)
      else
        U.wait(1)
      end
    end
    U.log("RESULT", label, "finished", tostring(finished), "outcome", tostring(outcome))
    U.wait(60)
    return logged
  end

  local randomized = fight("falkner-randomized", "FALKNER", 1)
  local rival = fight("rival-cherrygrove", "RIVAL1", 1)
  ctx.setActive(false)
  local vanilla = fight("falkner-vanilla", "FALKNER", 1)

  local vanillaRoster = describe(game.world:trainerParty(data.gen2Trainers.classes.FALKNER.index, 1).roster)
  local ok = randomized ~= nil and vanilla ~= nil and randomized ~= vanilla
    and rival ~= nil and rival:find("^MAREEP ") ~= nil
    and vanilla:find("^PIDGEY ") ~= nil
  U.log(ok and "PASS" or "FAIL", "randomized", tostring(randomized), "| vanilla", tostring(vanilla),
    "| rival", tostring(rival), "| roster", vanillaRoster)
  love.event.quit()
end
