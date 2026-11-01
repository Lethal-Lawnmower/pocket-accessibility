-- Scripted run for screens the other drivers do not reach: mod manager,
-- cable club menu, slot machine, prize counter, League PC, Hall of Fame,
-- diploma, credits, the item move picker and evolution.  Each screen is
-- pushed directly, driven briefly and closed.  Read the "[access] say"
-- lines.  Same environment as menus_and_text.lua.  No network is opened:
-- the cable club only shows its HOST / JOIN menu.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")

  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  local pidgey = Pokemon.new(game.data, "PIDGEY", 16)
  game.save.party = { pidgey, Pokemon.new(game.data, "RATTATA", 8) }
  game.save.coins = 120
  game.save.hallOfFame = { { Pokemon.new(game.data, "PIDGEY", 50) } }
  game.save.inventory.COIN_CASE = 1

  local function press(btn, frames) U.tap(game, btn) U.wait(frames or 12) end
  local function clear()
    for _ = 1, 30 do
      if game.stack:top() == game.overworld then return end
      game.stack:pop()
    end
  end
  local function push(label, make)
    U.log("open", label)
    local ok, state = pcall(make)
    if not ok then U.log("FAIL", label .. ": " .. tostring(state)) return false end
    if state then game.stack:push(state) end
    U.wait(40)
    return true
  end

  if push("mod manager", function() return nil end) then
    pcall(Screens.push, game, "ManagerState")
    U.wait(40)
    press("down")
    press("right", 20)    -- PROFILES tab
    press("left", 20)
    clear()
  end

  if push("cable club", function() return require("src.link.LinkState").new(game) end) then
    press("down")
    press("up")
    clear()
  end

  if push("slot machine", function() return require("src.ui.SlotMachine").new(game) end) then
    for _ = 1, 6 do press("a", 30) end
    press("down")
    clear()
  end

  if push("prize counter", function()
    return require("src.ui.PrizeCounter").new(game, {
      { name = "ABRA", cost = 180 }, { name = "CLEFAIRY", cost = 500 } }, {})
  end) then
    press("down")
    press("down")
    clear()
  end

  if push("league PC", function() return require("src.ui.LeaguePC").new(game, function() end) end) then
    clear()
  end

  if push("hall of fame", function() return require("src.ui.HallOfFame").new(game, function() end) end) then
    U.wait(400)
    clear()
  end

  if push("diploma", function() return require("src.ui.Diploma").new(game, function() end) end) then
    clear()
  end

  if push("credits", function() return require("src.ui.Credits").new(game, function() end) end) then
    U.wait(900)
    clear()
  end

  if push("move picker", function()
    return require("src.ui.MoveSelectMenu").new(game, pidgey, "Raise PP of which technique?",
      function() end, function() end)
  end) then
    for _ = 1, 20 do press("a", 15) if game.stack:top().ready then break end end
    press("down")
    press("down")
    clear()
  end

  if push("evolution", function()
    return require("src.ui.EvolutionState").new(game, pidgey, "PIDGEOTTO", function() end)
  end) then
    for _ = 1, 40 do press("a", 15) if game.stack:top() == game.overworld then break end end
    clear()
  end
  U.log("DONE")
end
