-- Does the game itself load a save the native editor wrote?  Continues from the
-- title screen and logs where the player stands, the money and the party.
-- Silent and isolated, on a disposable profile holding a save edited through
-- tests/access/save_backend.py:
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/edited_save.lua
return function(game)
  local version = os.getenv("POKEPORT_VERSION") or "red"
  local isGen3 = version == "firered"
  local isGen1 = version == "red" or version == "blue" or version == "yellow"
  local L = dofile(isGen3 and "tests/access/drivers/gen3_nav_lib.lua"
    or "tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local reached
  if isGen1 then
    U.wait(5)
    U.tap(game, "start")
    U.wait(10)
    for _ = 1, 1500 do
      U.tap(game, "a")
      U.wait(2)
      if game.overworld and game.stack:top() == game.overworld then reached = true break end
    end
  elseif isGen3 then
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then break end
      U.wait(1)
    end
    game:_handleBootAction({ action = "continue" })
    U.wait(60)
    reached = L.settle(3000, true)
  else
    -- the menu's CONTINUE calls this with the loaded save
    U.wait(300)
    game:continueGame(require("src.core.SaveData").load(version))
    reached = L.settle(2000, true)
  end
  U.log("RESULT", "reached the world", tostring(reached))
  U.wait(60)
  local nav = L.nav()
  local world = nav:worldForCommand()
  local saved = require("src.core.SaveData").load(version)
  U.log("RESULT", "game map", tostring(world and world.map and (world.map.id or (world.map.def and world.map.def.id))), "at",
    world and world.player and (tostring(world.player.cellX) .. "," .. tostring(world.player.cellY)))
  U.log("RESULT", "save party", saved and saved.party and #saved.party,
    "first", saved and saved.party and saved.party[1] and tostring(saved.party[1].species),
    "level", saved and saved.party and saved.party[1] and tostring(saved.party[1].level))
  love.event.quit()
end
