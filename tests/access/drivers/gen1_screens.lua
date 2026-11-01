-- Scripted run for Gen 1 screen speech: naming keyboard during a new game,
-- then party, Pokemon summary, options and trainer card from the start menu.
-- Read the "[access] say" lines it logs.  Same environment as
-- menus_and_text.lua (disposable POKEPORT_IDENTITY, POKEPORT_ACCESS_TRACE=1).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")

  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  game.save.party = { Pokemon.new(game.data, "PIDGEY", 5), Pokemon.new(game.data, "RATTATA", 3) }

  -- Opens the start menu and moves its cursor to the first row whose label
  -- contains `text`; returns false when no row matches.
  local function startMenuTo(text)
    U.tap(game, "start")
    U.wait(20)
    local menu = game.stack:top()
    for _ = 1, #(menu.items or {}) do
      local item = menu.items[menu.index]
      if item and tostring(item.label):find(text, 1, true) then return true end
      U.tap(game, "down")
      U.wait(6)
    end
    U.log("FAIL", "start menu has no row containing " .. text)
    U.tap(game, "b")
    U.wait(20)
    return false
  end

  local function press(btn, frames) U.tap(game, btn) U.wait(frames or 12) end

  if startMenuTo("MON") then
    press("a", 30)          -- party
    press("down")           -- second Pokemon
    press("up")
    press("a", 20)          -- submenu: STATS first
    press("down")
    press("up")
    press("a", 60)          -- summary page 1
    press("a", 30)          -- page 2
    press("b", 30)          -- back to party
    press("b", 30)          -- back to start menu
    press("b", 20)
  end

  if startMenuTo("OPTION") then
    press("a", 30)
    press("right")          -- change text speed
    press("down")
    press("b", 30)
    press("b", 20)
  end

  local name = game.save.player and game.save.player.name or "RED"
  if startMenuTo(name) then
    press("a", 40)          -- trainer card
    press("b", 30)
    press("b", 20)
  end
  U.log("DONE")
end
