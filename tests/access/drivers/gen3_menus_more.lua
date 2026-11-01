-- Gen 3 menus, part 2 (FireRed), run after gen3_menus.lua saved a game in
-- the same identity: the main menu's CONTINUE panel, the quest log, the map
-- name popup, the elevator (question, "Now on", floor list), the money
-- box, the Fame Checker, Teachy TV's list and a lesson, the move
-- relearner, an evolution and an egg hatching.  Some screens are opened
-- the way their scripts or items open them (the screen's own show/start),
-- with a party given through upstream's Party.giveMon.  Logs each step;
-- the `say!:` / `say:` trace lines show what was spoken.
return function(game)
  local L = dofile("tests/access/drivers/gen3_menus_lib.lua")
  local tap, step, wait, waitFor = L.tap, L.step, L.wait, L.waitFor

  waitFor("boot", function() return game.phase == "boot" and game.boot end, 900)
  local boot = game.boot
  waitFor("intro", function() return boot.introMovie and boot.introMovie.phase == "intro" end, 900)
  wait(10)
  tap(game, "start", 20)
  local Title = L.loaded("src.ui.game3.title_screen")
  waitFor("title runs", function() return boot.title and Title and boot.title.scene == Title.SCENE.RUN end, 1500)
  wait(20)
  tap(game, "start", 20)

  step("main menu with a save")
  waitFor("menu", function()
    return boot.phase == "menu" and not (boot.menuFade and boot.menuFade:fadeActive())
  end, 600)
  wait(20)
  tap(game, "down", 20)
  tap(game, "up", 20)
  tap(game, "a", 30)

  step("quest log")
  waitFor("quest log or field", function() return game.phase == "quest_log" or game.phase == "field" end, 600)
  step("phase " .. tostring(game.phase))
  if game.phase == "quest_log" then
    wait(240)
    tap(game, "a", 120)
    tap(game, "b", 60)
  end
  waitFor("field", function() return game.phase == "field" end, 1200)
  wait(60)
  L.talk(game)

  local F = require("tests.drivers.em_fa_util")
  step("map name popup")
  F.goTo(game, "FR_PALLET_TOWN", 6, 8, "down")
  wait(180)
  F.goTo(game, "FR_ROUTE_1", 12, 30, "up")
  wait(180)
  F.goTo(game, "FR_PALLET_TOWN", 12, 3, "down")
  wait(180)
  step("forest title card")
  F.goTo(game, "FR_VIRIDIAN_FOREST", 29, 60, "up")
  wait(240)
  F.goTo(game, "FR_PALLET_TOWN", 12, 3, "down")
  wait(120)

  step("elevator")
  F.goTo(game, "FR_CELADON_CITY_DEPARTMENT_STORE_ELEVATOR", 4, 2, "up")
  wait(60)
  tap(game, "a", 90)
  for _ = 1, 6 do
    if L.top() == "script_list_menu" then break end
    tap(game, "a", 60)
  end
  tap(game, "down", 20)
  tap(game, "down", 20)
  tap(game, "b", 60)
  L.talk(game)
  wait(30)

  step("money box")
  local MoneyBox = require("src.ui.game3.money_box")
  MoneyBox.show(19, 1)
  wait(30)
  local session = L.session()
  session.money = (session.money or 0) - 100
  MoneyBox.update()
  wait(30)
  MoneyBox.hide()
  wait(10)

  step("fame checker")
  local FameChecker = require("src.core.game3.fame_checker")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Natives = require("src.core.game3.scripting.natives")
  local function famechecker(person, index, special)
    local ctx = Space.vm and Space.vm.ctx
    Flags.setVar(Space.store, ctx, 0x8004, person)
    Flags.setVar(Space.store, ctx, 0x8005, index)
    pcall(Natives.special, ctx, special, nil)
  end
  local PERSON, PICK = FameChecker.PERSON, FameChecker.PICKSTATE
  famechecker(PERSON.BROCK, PICK.COLORED, 0x174)
  famechecker(PERSON.BROCK, 1, 0x173)
  famechecker(PERSON.OAK, 1, 0x173)
  local FameUi = require("src.ui.game3.fame_checker")
  FameUi.show(session)
  wait(60)
  tap(game, "down", 20)
  tap(game, "up", 20)
  tap(game, "a", 40)
  tap(game, "right", 30)
  tap(game, "right", 30)
  tap(game, "a", 30)
  tap(game, "b", 30)
  tap(game, "start", 30)
  tap(game, "start", 30)
  tap(game, "b", 60)

  step("teachy tv")
  local TvUi = require("src.ui.game3.teachy_tv")
  TvUi.show(session, session.bag)
  wait(90)
  tap(game, "down", 20)
  tap(game, "up", 20)
  tap(game, "a", 60)
  local pagesSeen = 0
  for _ = 1, 3000 do
    if TvUi.state ~= "lesson" or L.top() ~= "teachy_tv" or pagesSeen >= 6 then break end
    if TvUi.waitingForKey and TvUi.waitingForKey() then
      pagesSeen = pagesSeen + 1
      tap(game, "a", 20)
    else
      wait(1)
    end
  end
  step("teachy top " .. tostring(L.top()) .. " state " .. tostring(TvUi.state)
    .. " revealed " .. tostring(TvUi._revealed) .. "/" .. tostring(TvUi._total))
  tap(game, "b", 90) -- abort the lesson
  waitFor("teachy list", function() return TvUi.state == "list" end, 600)
  wait(60)
  tap(game, "b", 90)
  -- the close waits for a palette fade; finish it the screen's own way if
  -- the fade has not run, so later screens do not return to Teachy TV
  if TvUi.open then
    step("teachy still open; finishClose")
    TvUi.finishClose()
  end

  step("party")
  local Party = require("src.core.game3.party")
  session.party = session.party or {}
  Party.giveMon(session, 4, 30) -- CHARMANDER
  Party.giveMon(session, 25, 10) -- PIKACHU
  wait(10)

  step("move relearner")
  local MoveRelearner = require("src.ui.game3.move_relearner")
  MoveRelearner.show(session.party[1], { session = session, onDone = function() end })
  wait(60)
  tap(game, "down", 20)
  tap(game, "up", 20)
  tap(game, "a", 40)
  tap(game, "down", 20)
  tap(game, "a", 40) -- NO
  tap(game, "b", 40) -- give up?
  tap(game, "a", 60) -- YES
  wait(30)

  step("evolution")
  local EvolutionScene = require("src.ui.game3.evolution_scene")
  EvolutionScene.start(session.party[1], 5, { session = session, canStop = true, onDone = function() end })
  for _ = 1, 3000 do
    if not EvolutionScene.isOpen() then break end
    local Message = package.loaded["src.ui.game3.message"]
    if Message and Message.open and Message.isWaiting and Message.isWaiting() then tap(game, "a", 10) else wait(1) end
  end
  wait(30)

  step("egg hatch")
  local EggHatch = require("src.ui.game3.egg_hatch")
  local egg = session.party[2]
  egg.isEgg = true
  EggHatch.start(egg, { session = session, slot = 2, onDone = function() end })
  for _ = 1, 3000 do
    if not EggHatch.isOpen() then break end
    local Choice = package.loaded["src.ui.game3.choice"]
    if Choice and Choice.active then
      tap(game, "down", 20)
      tap(game, "a", 30)
    elseif L.top() == "naming" then
      tap(game, "start", 20)
      tap(game, "a", 40)
    else
      local Message = package.loaded["src.ui.game3.message"]
      if Message and Message.open and Message.isWaiting and Message.isWaiting() and not Message._stay then
        tap(game, "a", 10)
      else
        wait(1)
      end
    end
  end
  wait(30)

  step("done")
end
