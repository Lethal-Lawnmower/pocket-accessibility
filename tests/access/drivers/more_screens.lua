-- Scripted run for screens not covered by the other drivers: bag with the
-- toss quantity box, Pokedex list and entry, town map, and a mart's buy list
-- with its priced quantity box.  Read the "[access] say" lines.  Same
-- environment as menus_and_text.lua.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")

  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  game.save.party = { Pokemon.new(game.data, "PIDGEY", 5) }
  game.save.inventory = game.save.inventory or {}
  game.save.inventory.POTION = 3
  game.save.money = 3000
  game.save.pokedex.owned.BULBASAUR = true
  game.save.pokedex.seen.BULBASAUR = true
  game.save.pokedex.owned.PIDGEY = true
  game.save.pokedex.seen.PIDGEY = true
  game.save.pokedex.seen.RATTATA = true

  local function press(btn, frames) U.tap(game, btn) U.wait(frames or 12) end
  local function backOut()
    for _ = 1, 8 do
      if game.stack:top() == game.overworld then return end
      press("b", 15)
    end
  end
  local function open(id, ...)
    local ok, err = pcall(Screens.push, game, id, ...)
    U.log(ok and "PASS" or "FAIL", "opened " .. id .. (ok and "" or (": " .. tostring(err))))
    U.wait(30)
    return ok
  end

  if open("BagMenu") then
    press("a", 20)        -- USE / TOSS
    press("down")         -- TOSS
    press("a", 20)        -- quantity box
    press("up")
    press("up")
    backOut()
  end

  if open("PokedexMenu") then
    press("down")
    press("up")
    press("a", 20)        -- side menu
    press("a", 90)        -- DATA: the entry page
    press("a", 30)        -- next page
    backOut()
  end

  if open("TownMap") then
    press("down")
    press("down")
    backOut()
  end

  U.teleport(game, "PEWTER_MART", 2, 5, "left")
  U.wait(20)
  for _ = 1, 20 do
    local top = game.stack:top()
    if top ~= game.overworld and type(top) == "table" and top.items then break end
    press("a", 15)
  end
  press("a", 30)          -- BUY
  press("a", 30)          -- past "Take your time."
  press("down")
  press("a", 30)          -- quantity with price
  press("up")
  press("a", 40)          -- price prompt
  press("a", 40)          -- scroll its last line; YES/NO appears
  press("b", 30)          -- NO
  backOut()
  U.log("DONE")
end
