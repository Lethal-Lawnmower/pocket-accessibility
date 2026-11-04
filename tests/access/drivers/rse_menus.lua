-- Hoenn menus, part 1 (Emerald, Ruby, Sapphire): intro, title, main menu,
-- OPTION from the main menu with our ACCESSIBILITY page, Birch's speech,
-- gender, the name, then the truck.  In the field: the start menu with
-- every entry opened by key press.  Asserts nothing; logs SCREEN, SAID, BAD.
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/rse_menus.lua
--   POKEPORT_VERSION=emerald POKEPORT_GAME=emerald POKEPORT_IDENTITY=<disposable>
return function(game)
  local L = dofile("tests/access/drivers/rse_menus_lib.lua")(game)
  local tap, wait, waitFor, section = L.tap, L.wait, L.waitFor, L.section

  waitFor("boot", function() return game.phase == "boot" and game.boot end, 900)
  local boot = game.boot
  local c = boot.custom
  L.log("BOOT", c and "custom" or "plain")

  section("intro", function()
    wait(500)
    tap("start", 30)
  end)

  section("title", function()
    waitFor("title", function() return c.title end, 1500)
    wait(400)
    tap("start", 40)
  end)

  section("main menu", function()
    waitFor("menu", function() return c.menu and c.menu.state == "input" end, 900)
    wait(30)
    tap("down", 20)
    tap("up", 20)
  end)

  -- A profile with a save lists CONTINUE first, so rows are found by id.
  local function menuTo(id)
    for _ = 1, 6 do
      local menu = c.menu
      if menu and menu.items[menu.cursor] == id then return end
      tap(menu and menu.items[menu.cursor] and "down" or "up", 20)
    end
  end

  section("option from the main menu", function()
    menuTo("OPTION")
    tap("a", 90)
    L.taps({ "right", "down", "down", "up" }, 20)
    tap("up", 20)
    tap("a", 30)
    L.taps({ "down", "right", "left", "up" }, 20)
    tap("b", 30)
    tap("b", 90)
    waitFor("menu again", function() return c.menu and c.menu.state == "input" end, 400)
    for _ = 1, 4 do tap("up", 20) end
    menuTo("NEW_GAME")
  end)

  section("birch", function()
    tap("a", 60)
    waitFor("birch", function() return c.newGame end, 400)
    local function birch() return c.newGame end
    -- A whenever the printer waits, until `done`
    local function through(label, done, budget)
      for _ = 1, budget or 6000 do
        if done() then return true end
        local b = birch()
        local p = b and b.printer
        if p and (p.state == "clear" or p.state == "wait" or p.state == "scroll_start") then tap("a", 6) else wait(1) end
      end
      L.log("WAIT-TIMEOUT", label)
      return false
    end
    through("gender menu", function() return birch() and birch().genderMenu end)
    wait(20)
    tap("down", 40)
    tap("up", 40)
    tap("a", 30)
    through("name prompt", function()
      local b = birch()
      return b and (b.nameMenu or (b.main and b.main.func == "WaitPressBeforeNameChoice"))
    end)
    wait(20)
    if birch().nameMenu then
      tap("down", 20)
      tap("up", 20)
    end
    tap("a", 30)
    waitFor("naming", function() return birch().naming and birch().naming.stage == "input" end, 400)
    wait(20)
    L.taps({ "right", "down" }, 20)
    tap("a", 20)
    tap("b", 20)
    tap("start", 20)
    tap("a", 30)
    through("name yes no", function() return birch() and birch().yesNo end)
    wait(10)
    tap("down", 20)
    tap("up", 20)
    tap("a", 30)
    through("field", function() return game.phase == "field" end, 9000)
  end)

  section("truck", function()
    wait(300)
    L.log("MAP", tostring(L.session() and L.session().map))
  end)

  L.log("DONE", "rse_menus")
  love.event.quit()
end
