-- Game-run check for modules/trainers.lua on Crystal.  Installs the module
-- with a fake ctx (the randomizer core is not part of this check), then opens
-- real trainer battles through World:trainerParty + World:startScriptedBattle,
-- the path a `loadtrainer` / `startbattle` script takes, and logs the party
-- each battle actually fights.  Options: similar strength, type themes, fully
-- evolved from level 40, trainer levels 120 percent.
--   1. FALKNER, randomized: every mon FLYING in the game's current data, at
--      120 percent of his vanilla levels;
--   2. a BIRD_KEEPER in his gym (Violet Gym's map data): FLYING too;
--   3. the Cherrygrove rival (RIVAL1_1_CHIKORITA, the player took TOTODILE)
--      with a fake ctx.shared.starterRivalPairs: his mon must be the pair's
--      GEODUDE, strong against the player's (fake) MAREEP;
--   4. FALKNER again with the save switched to vanilla: the vanilla party.
-- The battles are fought with a level 100 MEWTWO pressing the first move.
--
-- Run silently and isolated, with a disposable identity:
--   POKEPORT_IDENTITY=pocket-access-rand2-trainers-run POKEPORT_ACCESS_SILENT=1
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
  local ctx = Fake.new({ seed = "drive", options = { trainers = true, trainers_similar = true,
    trainers_themes = true, trainers_evolved = 40, trainers_level = 120 } })
  ctx.shared.starters = { CHIKORITA = "MAREEP", CYNDAQUIL = "LARVITAR", TOTODILE = "EEVEE" }
  ctx.shared.starterRivalPairs = { CHIKORITA = "LARVITAR", CYNDAQUIL = "EEVEE", TOTODILE = "GEODUDE" }
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

  local function memberOf(classId, rowId)
    for member, row in ipairs(data.gen2Trainers.classes[classId].trainers) do
      if row.id == rowId then return member end
    end
  end

  local function fight(label, classId, member)
    for _, mon in ipairs(game.save.party) do Mon.restoreAllPp(mon, data) mon.hp = mon.maxHp end
    local class = data.gen2Trainers.classes[classId]
    local record = game.world:trainerParty(class.index, member)
    if not record then U.log("FAIL", label, "no trainer record") return nil end
    U.log("ROSTER", label, record.id, describe(record.roster))
    local finished, outcome = false, nil
    local party
    game.world:startScriptedBattle(record, nil, function(result) finished, outcome = true, result end)
    local logged, seen = nil, nil
    for _ = 1, 30000 do
      if finished then break end
      local t = top()
      if isBattle(t) then
        seen = t
        if not logged and t.battle and t.battle.enemyParty then
          party = {}
          for i, mon in ipairs(t.battle.enemyParty) do party[i] = { species = mon.species, level = mon.level } end
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
    return logged, party, record
  end

  local function allOfType(party, typeId)
    if not party or #party == 0 then return false end
    for _, mon in ipairs(party) do
      local t = data.pokemon[mon.species].types
      if t[1] ~= typeId and t[2] ~= typeId then return false end
    end
    return true
  end
  local function levelsScaled(party, record)
    for i, mon in ipairs(party or {}) do
      if mon.level ~= module.scaleLevel(record.roster[i].level, 120) then return false end
    end
    return party ~= nil
  end

  local falkner, fParty, fRecord = fight("falkner-randomized", "FALKNER", 1)
  local keeperMember = memberOf("BIRD_KEEPER", "ROD")
  local keeper, kParty = fight("bird-keeper-rod", "BIRD_KEEPER", keeperMember or 1)
  local rival, rParty = fight("rival-cherrygrove", "RIVAL1", memberOf("RIVAL1", "RIVAL1_1_CHIKORITA") or 1)
  ctx.setActive(false)
  local vanilla = fight("falkner-vanilla", "FALKNER", 1)

  local checks = {
    { "falkner all FLYING", allOfType(fParty, "FLYING") },
    { "falkner levels 120 percent", levelsScaled(fParty, fRecord) },
    { "bird keeper all FLYING", keeperMember ~= nil and allOfType(kParty, "FLYING") },
    { "rival is the pair's GEODUDE", rParty ~= nil and rParty[1].species == "GEODUDE" },
    { "GEODUDE strong against MAREEP", module.strongAgainst(data, "GEODUDE", "MAREEP") },
    { "vanilla after switch", vanilla ~= nil and vanilla:find("^PIDGEY L7 ") ~= nil },
    { "randomized differs from vanilla", falkner ~= nil and falkner ~= vanilla },
  }
  local ok = true
  for _, c in ipairs(checks) do
    U.log(c[2] and "OK" or "FAIL", c[1])
    ok = ok and c[2]
  end
  U.log(ok and "PASS" or "FAIL", "falkner", tostring(falkner), "| keeper", tostring(keeper),
    "| rival", tostring(rival), "| vanilla", tostring(vanilla))
  love.event.quit()
end
