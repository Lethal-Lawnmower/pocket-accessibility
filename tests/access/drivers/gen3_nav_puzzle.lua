-- FireRed Strength puzzles solved in the game by following only the
-- puzzle help (decision 29): select the boulder whose entry carries the
-- next push, auto-walk to the pushing position it names, switch Strength on
-- through the game's own offer at a boulder, push once the hinted way, and
-- repeat.  Victory Road 1F (the switch opens the way on) and Seafoam
-- Islands 1F (both boulders into the holes).  Silent and isolated:
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/gen3_nav_puzzle.lua
return function(game)
  local L = dofile("tests/access/drivers/gen3_nav_lib.lua").new(game)
  local U = L.U
  if not L.boot() then return end
  L.giveParty(6, 70, { "STRENGTH", "SURF" }, { "STRENGTH", "SURF" })
  local Player = require("src.core.game3.player")

  local function boulderEntity(id)
    for _, eo in ipairs(require("src.access.nav.gen3.World").actors()) do
      if require("src.access.nav.gen3.PuzzleAssistance").objectId(L.pos(), eo) == id then return eo end
    end
    return nil
  end

  local function push(eo, dir)
    local fromX, fromY = eo.cellX, eo.cellY
    for _ = 1, 90 do
      game.input.pressQueue[#game.input.pressQueue + 1] = dir
      game.input.state[dir] = true
      U.wait(1)
      if eo.cellX ~= fromX or eo.cellY ~= fromY or eo.moving then break end
    end
    game.input.state[dir] = false
    for _ = 1, 60 do if not eo.moving and not Player.boulderPush then break end U.wait(1) end
    U.wait(6)
    L.settle(300, true, 10)
    return eo.cellX ~= fromX or eo.cellY ~= fromY or eo.hidden or not eo.visible
  end

  -- `done()` says when the floor is finished.
  local function solve(name, done)
    local pushes = 0
    for round = 1, 60 do
      if done() then break end
      L.settle(600, true)
      local target
      for _, item in ipairs(L.browse("objects")) do
        if tostring(item.label):match("^Boulder") and tostring(item.stateText):find("next push", 1, true) then
          target = item
          break
        end
      end
      if not target then
        U.log("RESULT", name, "no planned push; round", round)
        L.logBrowse("objects")
        break
      end
      local said = L.walkTo(target, { filter = "objects", answer = "a", limit = 8000 })
      U.log("ROUND", round, target.description, "=>", said, "at", L.where())
      local eo, dir = boulderEntity(target.id), target.requiredFacing
      if not (eo and dir) then L.check(false, name .. ": boulder or push direction missing") break end
      if not L.nav():strengthActive() then
        -- the game's own offer at the boulder: A, then YES
        L.tap("a", 20)
        for _ = 1, 20 do
          if L.nav():strengthActive() and not L.messageOpen() then break end
          L.tap("a", 15)
        end
        L.settle(300, true)
      end
      if not push(eo, dir) then
        U.log("RESULT", name, "push did not move the boulder at", L.where(), "facing", dir)
        break
      end
      pushes = pushes + 1
    end
    return pushes
  end

  -- Victory Road 1F
  L.teleport("FR_VICTORY_ROAD_1F", 11, 19, "up")
  L.logBrowse("objects")
  local function switchPressed()
    local item = L.findLabel("^Pressure Switch 1", "objects")
    return item ~= nil and tostring(item.stateText):find("pressed by", 1, true) ~= nil
  end
  local pushes = solve("FR_VICTORY_ROAD_1F", switchPressed)
  L.check(switchPressed(), "Victory Road 1F switch pressed by following the hints (" .. pushes .. " pushes)")
  local ladder = L.findLabel("Victory Road 2F", "warps")
  if ladder then
    local said = L.walkTo(ladder, { answer = "a", limit = 8000 })
    U.log("WALK", said, "at", L.where())
    L.check(L.pos() == "FR_VICTORY_ROAD_2F", "auto-walk reached the 2F ladder past the opened barrier")
  end

  -- Seafoam Islands 1F
  L.teleport("FR_SEAFOAM_ISLANDS_1F", 6, 20, "up")
  L.logBrowse("all")
  local function noBoulders()
    for _, item in ipairs(L.browse("objects")) do
      if tostring(item.label):match("^Boulder") then return false end
    end
    return true
  end
  pushes = solve("FR_SEAFOAM_ISLANDS_1F", noBoulders)
  L.check(noBoulders(), "Seafoam Islands 1F boulders dropped into the holes (" .. pushes .. " pushes)")
  L.finish("gen3_nav_puzzle")
end
