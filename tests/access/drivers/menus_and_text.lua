-- Scripted run for screen speech: new game through Oak's speech and naming,
-- then the start menu and bag.  Read the "[access] say" lines it logs.
--   POKEPORT_IDENTITY=pocket-access-test POKEPORT_VERSION=red
--   POKEPORT_ACCESS_TRACE=1 POKEPORT_BACKGROUND=1
--   POKEPORT_DRIVER=tests/access/drivers/menus_and_text.lua love .
-- Needs Red imported into that identity first (POKEPORT_IMPORT_ROM with
-- POKEPORT_IMPORT_ONLY=1).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local reached = U.newGame(game)
  U.log(reached and "PASS" or "FAIL", "reached the overworld")
  if not reached then return end

  U.tap(game, "start")
  U.wait(20)
  U.tap(game, "down")
  U.wait(10)
  U.tap(game, "down")
  U.wait(10)
  U.tap(game, "a") -- ITEM opens the bag list
  U.wait(30)
  U.tap(game, "down")
  U.wait(10)
  U.tap(game, "b")
  U.wait(20)
  U.tap(game, "b")
  U.wait(20)
  U.log("DONE")
end
