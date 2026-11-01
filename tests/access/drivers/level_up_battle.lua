-- Scripted run for level-up and status speech in battle: a poisoned
-- SQUIRTLE one experience point short of level 6 beats a wild RATTATA,
-- so the trace should show PSN in the turn summary, "grew to level 6!",
-- the level-up stats box, and any new-move text.  Same environment as
-- menus_and_text.lua.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Growth = require("src.pokemon.Growth")
  local BattleState = require("src.battle.BattleState")

  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  local squirtle = Pokemon.new(game.data, "SQUIRTLE", 5)
  local def = game.data.pokemon.SQUIRTLE
  squirtle.exp = Growth.expForLevel(def.growthRate, 6, game.data.growth_rates) - 1
  squirtle.status = "PSN"
  game.save.party = { squirtle }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(20)

  local battle = BattleState.newWild(game, "RATTATA", 2)
  game.overworld:pushBattle(battle)
  for _ = 1, 900 do
    if game.stack:top() == battle then break end
    U.wait(1)
  end

  local function press(btn, frames) U.tap(game, btn) U.wait(frames or 10) end
  for _ = 1, 8 do
    for _ = 1, 120 do
      if game.stack:top() == battle and battle.phase == "menu" then break end
      if not game.stack.states[1] or not battle.player then break end
      press("a", 8)
      if battle.phase ~= "menu" and game.stack:top() == game.overworld then break end
    end
    if game.stack:top() ~= battle or battle.phase ~= "menu" then break end
    press("a", 20)        -- FIGHT
    press("a", 30)        -- first move
  end
  for _ = 1, 200 do
    if game.stack:top() == game.overworld then break end
    press("a", 8)
  end
  U.log(squirtle.level == 6 and "PASS" or "FAIL", "SQUIRTLE reached level " .. tostring(squirtle.level))
  U.log("DONE")
end
