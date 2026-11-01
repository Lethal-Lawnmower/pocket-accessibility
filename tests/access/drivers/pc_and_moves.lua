-- Scripted run for Bill's PC, the player's PC and the "forget a move"
-- picker.  Read the "[access] say" lines.  Same environment as
-- menus_and_text.lua.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")

  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  local pidgey = Pokemon.new(game.data, "PIDGEY", 20)
  game.save.party = { pidgey, Pokemon.new(game.data, "RATTATA", 6) }
  game.save.pcItems = { POTION = 2 }

  local function press(btn, frames) U.tap(game, btn) U.wait(frames or 12) end
  local function backOut()
    for _ = 1, 10 do
      if game.stack:top() == game.overworld then return end
      press("b", 15)
    end
  end

  -- Bill's PC: root menu, then DEPOSIT's party list
  game.stack:push(require("src.ui.BoxMenu").new(game))
  U.wait(30)
  press("down")           -- DEPOSIT
  press("a", 40)
  press("down")
  backOut()

  -- Player's PC: root menu, then WITHDRAW ITEM's list
  game.stack:push(require("src.ui.PlayerPC").new(game))
  U.wait(30)
  press("a", 40)          -- WITHDRAW ITEM
  press("down")
  backOut()

  -- Forget-a-move picker: fill four moves, then learn a fifth
  pidgey.moves = { { id = "GUST", pp = 35 }, { id = "SAND_ATTACK", pp = 15 },
    { id = "QUICK_ATTACK", pp = 30 }, { id = "WHIRLWIND", pp = 20 } }
  local learn = require("src.ui.MoveLearnMenu").new(game, pidgey, "WING_ATTACK", function() end)
  game.stack:push(learn)
  -- the prompt scrolls line by line; A on the YES/NO answers YES
  for _ = 1, 80 do
    if learn.selecting and game.stack:top() == learn then break end
    press("a", 20)
  end
  U.log(learn.selecting and "PASS" or "FAIL", "forget list reached")
  press("down")
  press("down")
  backOut()
  U.log("DONE")
end
