-- Story spots that need more than one walk (follow-ups to
-- gen2_story_spots.lua): the targets that sweep found gated by a puzzle or
-- by the dungeon's layout, checked once the gate is opened the way a player
-- opens it.  Silent; read the RESULT lines.
--
-- 1. Blackthorn Gym 2F solved by following the Strength hints
--    (gen2_nav_lib solveStoneFloor, with this driver's party), then 1F: Clair
--    and the trainer the dropped boulders open the way to.
-- 2. Cianwood Gym: Chuck stands behind three Strength boulders, which have
--    no push hints (they are not on a stone table).  The harness pushes
--    them the way the gym is solved (right one up, left one up, step up,
--    middle one right) and auto-walk then has to reach Chuck.
-- 3. Olivine Lighthouse 3F's Ether, reachable only from 4F's ladders: an
--    Area journey from 1F.
return function(game)
  pcall(function() love.window.minimize() end)
  for _, callback in ipairs({ "keypressed", "keyreleased", "textinput", "gamepadpressed",
      "gamepadreleased", "gamepadaxis", "joystickpressed", "joystickreleased",
      "joystickaxis", "joystickhat", "mousepressed", "mousereleased" }) do
    love[callback] = function() end
  end
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local Mon = require("src.battle.gen2.Mon")
  if not L.settle(3000, true) then U.log("FAIL", "never reached the free world") return end
  game.driverSpeed = 8
  game.options.battleStyle, game.options.battleScene, game.options.textSpeed = "SET", false, "FAST"
  local version = tostring(game.save and game.save.version or os.getenv("POKEPORT_VERSION"))

  local function party()
    local function newMon(species, moves)
      local mon = Mon.new(game.data, species, 100)
      local list = {}
      for i, id in ipairs(moves) do list[i] = { id = id, pp = 10 } end
      mon.moves = list
      return mon
    end
    game.save.party = {
      newMon("MEWTWO", { "ICE_BEAM", "SURF", "STRENGTH", "FLASH" }),
      newMon("FERALIGATR", { "CUT", "WHIRLPOOL", "WATERFALL", "ROCK_SMASH" }),
    }
    for _, badge in ipairs({ "ZEPHYR", "HIVE", "PLAIN", "FOG", "STORM", "MINERAL", "GLACIER", "RISING" }) do
      game.save.player.badges[badge] = true
    end
  end
  local function heal()
    -- the battle's own moves too (gen2_story_spots.lua refillBattlePp)
    local stack = package.loaded["src.core.StateStack"]
    for _, state in ipairs(stack and stack.states or {}) do
      local battle = type(state) == "table" and state.isBattle and state.battle
      if type(battle) == "table" then
        for _, mon in ipairs({ battle.player, (battle.party or {})[1] }) do
          for _, move in ipairs(type(mon) == "table" and mon.moves or {}) do
            if type(move) == "table" and (move.pp or 0) < 5 then move.pp = move.maxPp or 10 end
          end
        end
      end
    end
    for _, mon in ipairs(game.save.party or {}) do
      if mon.maxHp then mon.hp = mon.maxHp end
      mon.status = nil
      pcall(Mon.restoreAllPp, mon, game.data)
      -- a walk can meet several trainers before the next heal, so the lead
      -- carries plenty: two gym trainers back to back once emptied 10 PP
      if mon.moves and mon.moves[1] then mon.moves[1].pp = 60 end
    end
    game.save.repelSteps = 9999
  end
  local function walk(item, filter)
    -- one tick per frame while auto-walk turns (as WalkSpeed does in play;
    -- the harness's driverSpeed bypasses the game's speed field)
    local frames, base = 0, game.driverSpeed
    local text = L.walkTo(item, { filter = filter, answer = "a", limit = 8000, onFrame = function()
      frames = frames + 1
      if frames % 30 == 0 then heal() end
      game.driverSpeed = L.AutoWalk.turning() and 1 or base
    end })
    game.driverSpeed = base
    L.settle(900, true)
    return text
  end
  local function find(predicate, filter)
    for _, item in ipairs(L.browse(filter or "all")) do if predicate(item) then return item end end
  end
  local function result(spot, text)
    local verdict = (text:find("Arrived at", 1, true) or text:find(" is here", 1, true)) and "REACHED" or "NOT REACHED"
    U.log("RESULT", version, verdict, spot, "=>", (text:match("([^|]*)$") or text):gsub("^%s+", ""))
  end
  local function npc(id)
    for _, n in ipairs(game.world.npcs or {}) do if n.id == id then return n end end
  end
  -- Face the boulder (the arrival hint says which way), talk to it so the
  -- game offers Strength and answer YES, then one push: hold the direction
  -- until the boulder leaves its cell.  Facing first: an A press facing
  -- away talks to nothing and Strength never comes on.
  local function push(boulder, dir)
    if game.world.player.facing ~= dir then L.tap(dir, 10) end
    L.tap("a", 20)
    for _ = 1, 20 do
      if L.free() then break end
      L.tap("a", 15)
    end
    L.settle(300, true)
    U.log("RESULT", version, "Strength =>", L.heard(), "active", tostring(game.world.strengthActive))
    local fromX, fromY = boulder.cellX, boulder.cellY
    for _ = 1, 90 do
      game.input.pressQueue[#game.input.pressQueue + 1] = dir
      game.input.state[dir] = true
      U.wait(1)
      if boulder.cellX ~= fromX or boulder.cellY ~= fromY or boulder.moving then break end
    end
    game.input.state[dir] = false
    for _ = 1, 60 do if not boulder.moving then break end U.wait(1) end
    L.settle(200, true)
    return boulder.cellX ~= fromX or boulder.cellY ~= fromY
  end

  -- FOLLOWUPS_PARTS=blackthorn,cianwood,lighthouse limits the parts
  local parts = os.getenv("FOLLOWUPS_PARTS")
  local function part(name) return not parts or parts:find(name, 1, true) ~= nil end

  -- 1. Blackthorn Gym 2F by the hints, then 1F (Ice Path B1F:
  -- FOLLOWUPS_ICE_PATH=1 solves it first)
  if part("blackthorn") and game.data.gen2Maps.BLACKTHORN_GYM_2F then
    party()
    heal()
    local frames = 0
    local function healing()
      frames = frames + 1
      if frames % 30 == 0 then heal() end
    end
    if os.getenv("FOLLOWUPS_ICE_PATH") == "1" then
      L.solveStoneFloor({ id = "ICE_PATH_B1F", x = 3, y = 14 }, healing)
    end
    L.solveStoneFloor({ id = "BLACKTHORN_GYM_2F", x = 2, y = 7 }, healing)
    heal()
    L.teleport("BLACKTHORN_GYM_1F", 4, 16, "up")
    L.settle(600, true)
    -- from the door, then from each 1F arrival of a 2F ladder (the part of
    -- 1F behind the lava is reached through 2F, across the filled holes)
    local warps = game.data.gen2Maps.BLACKTHORN_GYM_1F.warps or {}
    for _, label in ipairs({ "Clair", "Cooltrainer F" }) do
      local text, from = "not in the object list", "the door"
      for index = 0, #warps do
        local x, y = 4, 16
        if index > 0 then x, y = warps[index].x, warps[index].y end
        L.teleport("BLACKTHORN_GYM_1F", x, y, "up")
        L.settle(600, true)
        -- a teleport onto a ladder skips the game's step off it: stand beside
        local nav = L.nav()
        if nav and not nav:worldForCommand() then
          local P = require("src.world.gen2.Permissions")
          local map = game.world.map
          for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
            local nx, ny = x + d[1], y + d[2]
            if map:inBounds(nx, ny) and P.isWalkable(map:cellCollision(nx, ny))
               and not P.isWarpCollision(map:cellCollision(nx, ny)) then
              L.teleport("BLACKTHORN_GYM_1F", nx, ny, "up")
              L.settle(600, true)
              break
            end
          end
        end
        local target = find(function(i) return i.label == label end)
        if target then
          text = walk(target)
          from = index == 0 and "the door" or ("1F warp " .. index)
          if text:find("Arrived at", 1, true) or text:find(" is here", 1, true) then break end
        end
      end
      result("BLACKTHORN_GYM_1F " .. label .. " after the 2F puzzle, from " .. from, text)
    end
  end

  -- 2. Cianwood Gym
  if part("cianwood") then
  party()
  heal()
  L.teleport("CIANWOOD_GYM", 4, 16, "up")
  L.settle(600, true)
  local chuck = find(function(i) return i.label == "Chuck" end)
  U.log("RESULT", version, "CIANWOOD_GYM before pushing: Chuck =>", chuck and chuck.description or "not listed")
  local plan = { { id = "CIANWOOD_GYM_obj_9", dir = "up" }, { id = "CIANWOOD_GYM_obj_7", dir = "up" },
                 { id = "CIANWOOD_GYM_obj_8", dir = "right", stepFirst = "up" } }
  for _, step in ipairs(plan) do
    local boulder = npc(step.id)
    local entry = find(function(i) return i.id == step.id end)
    if not (boulder and entry) then
      U.log("RESULT", version, "CIANWOOD_GYM boulder", step.id, "not found") break
    end
    if step.stepFirst then
      -- a push leaves the player where they stood: step into the cell the
      -- left boulder left, beside the middle one, and push from there
      L.hold(step.stepFirst, 18)
      L.settle(60, true)
    else
      U.log("RESULT", version, "CIANWOOD_GYM walk to", entry.description, "=>", walk(entry))
    end
    U.log("RESULT", version, "CIANWOOD_GYM push", step.id, step.dir, "=>",
      push(boulder, step.dir) and "moved" or "did not move", "now", boulder.cellX .. "," .. boulder.cellY,
      "player", L.where())
  end
  chuck = find(function(i) return i.label == "Chuck" end)
  result("CIANWOOD_GYM Chuck after three pushes", chuck and walk(chuck) or "not in the object list")
  end

  -- 3. Olivine Lighthouse 3F's Ether, as an Area journey from 1F
  if not part("lighthouse") then U.log("DONE") return end
  party()
  heal()
  L.teleport("OLIVINE_LIGHTHOUSE_1F", 10, 15, "up")
  L.settle(600, true)
  local ether = find(function(i) return tostring(i.label):find("Ether, Olivine Lighthouse 3F", 1, true) end, "area")
  U.log("RESULT", version, "OLIVINE_LIGHTHOUSE area target =>", ether and ether.description or "not listed")
  if ether then result("OLIVINE_LIGHTHOUSE_3F Ether by journey from 1F", walk(ether, "area")) end
  U.log("DONE")
end
