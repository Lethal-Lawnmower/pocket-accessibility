-- Gen 3 menus, part 1 (FireRed): the intro and title, the main menu, the
-- whole new game scene (controls guide, Pikachu pages, Oak's speech, the
-- gender menu, the naming keyboard, the rival's name list, the yes/no
-- confirmations), then in the field the start menu, OPTION with the
-- ACCESSIBILITY page and a group page, CONTROLS, the trainer card, SAVE,
-- the help system and EXIT's confirmation.  Logs each step; the
-- `say!:` trace lines show what was spoken.  Run silently and isolated:
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/gen3_menus.lua
--   POKEPORT_VERSION=firered POKEPORT_GAME=firered POKEPORT_IDENTITY=<disposable>
return function(game)
  local L = dofile("tests/access/drivers/gen3_menus_lib.lua")
  local tap, step, wait, waitFor = L.tap, L.step, L.wait, L.waitFor

  waitFor("boot", function() return game.phase == "boot" and game.boot end, 900)
  local boot = game.boot

  step("intro")
  waitFor("intro scenes", function()
    return boot.introMovie and boot.introMovie.phase == "intro" and boot.introMovie.ptr
      and boot.introMovie.ptr.cb == "Scene1"
  end, 1500)
  wait(30)
  tap(game, "start", 20)

  step("title")
  local Title = L.loaded("src.ui.game3.title_screen")
  waitFor("title runs", function()
    return boot.title and Title and boot.title.scene == Title.SCENE.RUN
  end, 1500)
  wait(30)
  tap(game, "start", 20)

  step("main menu")
  waitFor("menu", function()
    return boot.phase == "menu" and not (boot.menuFade and boot.menuFade:fadeActive())
  end, 600)
  wait(20)
  tap(game, "down", 20)
  tap(game, "up", 20)
  -- NEW GAME is the first row without a save, the second with one
  local Boot = L.loaded("src.ui.game3.boot")
  for _ = 1, 4 do
    if Boot.menuItems(boot)[boot.menuIndex] == "NEW GAME" then break end
    tap(game, "down", 20)
  end
  tap(game, "a", 20)

  step("controls guide")
  waitFor("guide", function() return boot.newGame and boot.newGame.win.guide end, 900)
  wait(40)
  for _ = 1, 3 do
    tap(game, "a", 60)
    waitFor("guide fade", function() return not boot.newGame or not boot.newGame:fadeActive() end, 200)
    wait(20)
  end

  step("pikachu pages")
  waitFor("pikachu", function() return boot.newGame and boot.newGame.win.pika end, 900)
  wait(60)
  tap(game, "b", 40) -- page 1: B does nothing
  for _ = 1, 3 do tap(game, "a", 70) end

  step("oak's speech")
  local function scene() return boot.newGame end
  local function menuKind()
    local s = scene()
    return s and s.win and s.win.menu and s.win.menu.kind
  end
  -- presses A whenever Oak's printer waits, until `done` holds
  local function throughOak(label, done, budget)
    for _ = 1, budget or 3000 do
      if done() then return true end
      local s = scene()
      if s and s.printer and s.printer.state == "clear" then tap(game, "a", 10) else wait(1) end
    end
    step("WAIT-TIMEOUT " .. label)
    return false
  end
  throughOak("gender menu", function() return menuKind() == "gender" end)
  wait(20)
  step("gender menu")
  tap(game, "down", 20)
  tap(game, "up", 20)
  tap(game, "a", 20)

  step("player naming")
  throughOak("naming", function() return L.top() == "naming" end)
  local Naming = L.loaded("src.ui.game3.naming")
  waitFor("naming input", function()
    return boot.newGame and boot.newGame.naming and boot.newGame.naming.stage == "input"
  end, 300)
  wait(20)
  tap(game, "right", 20)
  tap(game, "a", 20) -- B
  tap(game, "left", 20)
  tap(game, "a", 20) -- A
  tap(game, "b", 20) -- delete
  tap(game, "down", 20)
  tap(game, "a", 20) -- G
  tap(game, "select", 60) -- lower case page
  tap(game, "right", 20)
  tap(game, "start", 20) -- to OK
  tap(game, "up", 20) -- BACK button
  tap(game, "up", 20) -- PAGE button
  tap(game, "down", 20)
  tap(game, "down", 20) -- OK
  tap(game, "a", 30)
  step("name: " .. tostring(boot.newGame and boot.newGame.playerName))

  step("confirm player name")
  throughOak("player yes/no", function() return menuKind() == "yesno" end)
  wait(10)
  tap(game, "down", 20)
  tap(game, "up", 20)
  tap(game, "a", 20)

  step("rival name list")
  throughOak("rival names", function() return menuKind() == "names" end)
  wait(10)
  tap(game, "down", 20)
  tap(game, "down", 20)
  tap(game, "a", 20)
  step("confirm rival name")
  throughOak("rival yes/no", function() return menuKind() == "yesno" end)
  wait(10)
  tap(game, "a", 20)

  step("to the field")
  throughOak("field", function() return game.phase == "field" end, 6000)
  wait(120)
  L.talk(game)
  wait(30)
  step("map " .. tostring((L.session() or {}).map))

  step("start menu")
  tap(game, "start", 30)
  tap(game, "down", 15)
  tap(game, "up", 15)

  step("option")
  L.startMenuTo(game, "option")
  tap(game, "a", 40)
  step("accessibility page")
  tap(game, "a", 30)
  tap(game, "down", 20)
  tap(game, "right", 20)
  tap(game, "left", 20)
  tap(game, "up", 20)
  tap(game, "right", 20)
  tap(game, "left", 20)
  tap(game, "b", 30)
  step("speed group")
  tap(game, "down", 20)
  tap(game, "a", 30)
  tap(game, "right", 20)
  tap(game, "left", 20)
  tap(game, "up", 20) -- CANCEL row
  tap(game, "b", 30)
  step("controls")
  tap(game, "down", 20)
  tap(game, "a", 40)
  tap(game, "down", 20)
  tap(game, "down", 20)
  tap(game, "b", 40)
  step("leave option")
  tap(game, "b", 40)

  step("trainer card")
  L.startMenuTo(game, "trainer")
  tap(game, "a", 60)
  tap(game, "a", 90) -- flip to the back
  tap(game, "b", 90) -- flip to the front
  tap(game, "b", 40) -- close

  step("save")
  L.startMenuTo(game, "save")
  tap(game, "a", 40)
  tap(game, "down", 20)
  tap(game, "up", 20)
  tap(game, "a", 40) -- overwrite question
  tap(game, "a", 60) -- save
  tap(game, "a", 40) -- close

  step("help system")
  wait(30)
  tap(game, "l", 40)
  tap(game, "a", 30)
  tap(game, "down", 20)
  tap(game, "a", 30)
  tap(game, "down", 20)
  tap(game, "a", 30)
  tap(game, "down", 20)
  tap(game, "b", 30)
  tap(game, "b", 30)
  tap(game, "l", 40)

  step("exit confirm")
  tap(game, "start", 30)
  L.startMenuTo(game, "exit")
  tap(game, "a", 90)
  tap(game, "up", 20)
  tap(game, "down", 20)
  tap(game, "a", 30)
  tap(game, "b", 30)

  step("done")
  wait(30)
end
