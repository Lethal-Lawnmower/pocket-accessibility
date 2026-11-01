-- Scripted run for battle speech: a wild battle on Route 1, moving through
-- the main menu and move list, attacking until the battle ends.  Read the
-- "[access] say" lines.  Same environment as menus_and_text.lua.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  game.save.party = { Pokemon.new(game.data, "SQUIRTLE", 12) }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(20)

  local battle = BattleState.newWild(game, "PIDGEY", 3)
  game.overworld:pushBattle(battle)
  -- the wipe transition owns the screen first
  local reached = false
  for _ = 1, 900 do
    if game.stack:top() == battle then reached = true break end
    U.wait(1)
  end
  U.log(reached and "PASS" or "FAIL", "battle screen reached")
  if not reached then return end

  local function press(btn, frames) U.tap(game, btn) U.wait(frames or 10) end
  local function untilMenu(max)
    for _ = 1, max or 120 do
      if game.stack:top() ~= battle then return false end
      if battle.phase == "menu" then return true end
      press("a", 6)
    end
    return false
  end

  for turn = 1, 6 do
    if not untilMenu() then break end
    U.wait(20)
    if turn == 1 then
      press("right")      -- POKéMON
      press("down")       -- RUN
      press("left")       -- ITEM
      press("up")         -- FIGHT
    end
    press("a", 20)        -- open the move list
    if turn == 1 then
      press("down")
      press("up")
    end
    press("a", 30)        -- use the first move
  end
  for _ = 1, 200 do
    if game.stack:top() ~= battle then break end
    press("a", 6)
  end
  U.log(game.stack:top() ~= battle and "PASS" or "FAIL", "battle ended")
  U.log("DONE")
end
