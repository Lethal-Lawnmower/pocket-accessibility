-- Scripted run: a wild battle interrupts auto-walk on Route 1; after
-- running away the walk should resume ("Resuming walk to ...").  Battle
-- input goes straight to the game's input, as button presses do not pass
-- the accessibility router that way, so they cannot cancel the walk.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  game.save.party = { Pokemon.new(game.data, "SQUIRTLE", 30) }
  U.teleport(game, "ROUTE_1", 9, 20, "up")
  U.wait(30)

  -- the navigation module's own controller handlers: isolated.lua turns
  -- the love callbacks into no-ops, so a walk started through them never ran
  local Nav = require("src.access.nav")
  Nav.gamepadaxis(nil, "triggerleft", 1.0) U.wait(5)
  for _ = 1, 2 do -- Warps, then Connections
    Nav.gamepadpressed(nil, "dpdown") U.wait(2) Nav.gamepadreleased(nil, "dpdown") U.wait(15)
  end
  Nav.gamepadaxis(nil, "triggerleft", 0.0) U.wait(5)
  Nav.gamepadpressed(nil, "leftstick") U.wait(2) Nav.gamepadreleased(nil, "leftstick")
  U.wait(50)

  local battle = BattleState.newWild(game, "PIDGEY", 2)
  game.overworld:pushBattle(battle)
  for _ = 1, 900 do if game.stack:top() == battle then break end U.wait(1) end
  for _ = 1, 120 do
    if battle.phase == "menu" then break end
    U.tap(game, "a") U.wait(6)
  end
  U.wait(20)
  U.tap(game, "down") U.wait(8)
  U.tap(game, "right") U.wait(8)
  U.tap(game, "a") U.wait(30)       -- RUN
  for _ = 1, 200 do
    if game.stack:top() == game.overworld then break end
    U.tap(game, "a") U.wait(6)
  end
  U.wait(120)
  U.log("DONE")
end
