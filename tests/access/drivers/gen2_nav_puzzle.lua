-- Strength puzzle help on Gen 2's two stone-table floors, Ice Path B1F and
-- Blackthorn Gym 2F: teleport there with a Strength user and the Plain Badge,
-- read the object list (boulders, holes, their state and next push), then
-- solve each floor only by following the hints the way a player would --
-- select the boulder, auto-walk to the pushing position it names, switch
-- Strength on by talking to a boulder, push once in the hinted direction,
-- and repeat until every hole is filled.  Silent; read the RESULT lines.
-- GEN2_PUZZLE_MAPS=ICE_PATH_B1F (or BLACKTHORN_GYM_2F) limits the floors.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") return end
  L.giveParty("FERALIGATR", 60, { "STRENGTH", "SURF", "CUT", "WATERFALL" },
    { "ZEPHYR", "HIVE", "PLAIN", "FOG", "STORM", "MINERAL", "GLACIER", "RISING" })

  local floors = {
    { id = "ICE_PATH_B1F", x = 3, y = 14 },
    { id = "BLACKTHORN_GYM_2F", x = 2, y = 7 },
  }
  local only = os.getenv("GEN2_PUZZLE_MAPS")

  local function boulderAt(id)
    for _, npc in ipairs(game.world.npcs or {}) do
      if npc.id == id then return npc end
    end
    return nil
  end

  -- holes not yet filled; nil when the object list cannot be read (a battle
  -- or text still up), which must never count as solved
  local function holesLeft()
    L.settle(3000, true)
    local items = L.browse("all")
    if #items == 0 then return nil end
    local n = 0
    for _, item in ipairs(items) do
      if tostring(item.label):match("^Hole %d") and not tostring(item.stateText):match("^filled") then
        n = n + 1
      end
    end
    return n
  end

  -- one push: hold the direction until the boulder leaves its cell
  local function push(npc, dir)
    local fromX, fromY = npc.cellX, npc.cellY
    for _ = 1, 90 do
      game.input.pressQueue[#game.input.pressQueue + 1] = dir
      game.input.state[dir] = true
      U.wait(1)
      if npc.cellX ~= fromX or npc.cellY ~= fromY or npc.moving then break end
    end
    game.input.state[dir] = false
    for _ = 1, 60 do if not npc.moving then break end U.wait(1) end
    U.wait(4)
    return npc.cellX ~= fromX or npc.cellY ~= fromY
  end

  for _, floor in ipairs(floors) do
    if not only or only:find(floor.id, 1, true) then
      L.teleport(floor.id, floor.x, floor.y, "up")
      L.settle(300, true)
      U.log("RESULT", floor.id, "arrived", L.where(), "=>", L.heard())
      local items = L.logBrowse("all")
      local pushes, strengthOn = 0, false
      for round = 1, 60 do
        if holesLeft() == 0 then break end
        -- the first boulder with a planned push, as its object entry says
        local target
        for _, item in ipairs(L.browse("objects")) do
          if tostring(item.label):match("^Boulder") and tostring(item.stateText):find("next push", 1, true) then
            target = item
            break
          end
        end
        if not target then
          U.log("RESULT", floor.id, "no planned push left; holes left", holesLeft())
          L.logBrowse("objects")
          break
        end
        local id = target.id
        local walk = L.walkTo(target, { filter = "objects", answer = "a", limit = 12000 })
        local npc = boulderAt(id)
        local dir = target.requiredFacing
        U.log("RESULT", floor.id, "round " .. round, target.description, "=>", walk, "at", L.where())
        if not npc or not dir then U.log("FAIL", "boulder or push direction missing") break end
        if not strengthOn and not game.world.strengthActive then
          -- the game's own offer: talk to the boulder, answer YES
          L.tap("a", 20)
          for _ = 1, 20 do
            if L.free() then break end
            L.tap("a", 15)
          end
          L.settle(300, true)
          strengthOn = game.world.strengthActive == true
          U.log("RESULT", floor.id, "Strength on =>", L.heard(), tostring(strengthOn))
        end
        local moved = push(npc, dir)
        pushes = pushes + 1
        L.settle(400, true)
        U.log("RESULT", floor.id, "pushed " .. dir, moved and "moved" or "did not move",
          "boulder now", npc.cellX .. "," .. npc.cellY, "visible", tostring(boulderAt(id) ~= nil),
          "=>", L.heard())
      end
      U.log("RESULT", floor.id, "pushes", pushes, "holes left", holesLeft())
      L.logBrowse("all")
    end
  end
  U.log("DONE")
end
