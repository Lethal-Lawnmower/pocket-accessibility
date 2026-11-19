-- The harness's own battle presses, checked on FireRed or LeafGreen: an auto-walk to a
-- gym leader through one of the gym's trainers, with the lead Pokemon one experience
-- point short of a level.  GEN3_LEVELUP_SCENES picks the scenes (default: both):
--   level  Pewter Gym, level 90 to 91: the two-page level-up window, no new move
--   learn  Cerulean Gym, a level at which the species learns a move while it knows
--          four: "delete a move?" is answered NO and "stop learning?" YES, so its
--          moves stay as given
-- Each scene passes when the battle ends, the level went up, the four moves are the
-- ones given and the walk arrives beside the leader.  This tests gen3_nav_lib.lua's
-- battleStep and endBattle (the long story drivers stalled at a level-up), not speech.
-- Silent; PASS, FAIL and RESULT lines.
return function(game)
  local L = dofile("tests/access/drivers/gen3_nav_lib.lua").new(game)
  local U, AutoWalk = L.U, L.AutoWalk
  local Experience = require("src.core.game3.battle.experience")
  local LearnMove = require("src.core.game3.battle.learn_move")
  if not L.boot() then return end
  game.options.firered = game.options.firered or {}
  game.options.firered.accessAutoWalkSpeed = 8
  local wanted = os.getenv("GEN3_LEVELUP_SCENES")
  local function scene(name) return not wanted or wanted == "" or wanted:find(name, 1, true) ~= nil end
  local fieldMoves = { "SURF", "STRENGTH", "CUT" }

  local function moveList(mon)
    local ids = {}
    for i = 1, 4 do ids[i] = tostring(mon.moves and mon.moves[i] or "-") end
    return table.concat(ids, ",")
  end

  -- One auto-walk from the gym's door to its leader, with `level`'s Pokemon a point
  -- short of the next level.
  local function toLeader(name, gym, x, y, leader, level, limit)
    limit = limit or 9000
    local mon = L.giveParty(9, level, fieldMoves, fieldMoves)
    mon.exp = Experience.expForLevel(mon, level + 1) - 1
    local before = moveList(mon)
    L.setVar(0x4020, 60000) -- a long Repel
    L.teleport(gym, x, y, "up")
    L.settle(120, true)
    local target = L.findLabel(leader, "npcs")
    if not target then
      L.check(false, name .. ": " .. leader .. " is listed at " .. L.where())
      return
    end
    local battlesBefore = L.battles
    L.select(target, "npcs")
    L.heard()
    AutoWalk.start(L.nav(), game, L.adapter())
    local frames, stalled = 0, false
    while AutoWalk.active() do
      frames = frames + 1
      if frames > limit then stalled = true break end
      if not L.battleStep() then
        if frames % 15 == 0 and L.messageOpen() and not L.free() then L.tap("a", 2) else U.wait(1) end
      end
    end
    local said = L.heard()
    U.log("NOTE", name, "loop turns", frames, "battles", L.battles - battlesBefore, "level", tostring(mon.level),
      "moves", moveList(mon), "at", L.where(), "|", said:sub(-200))
    L.check(L.battles > battlesBefore, name .. ": a trainer fought")
    L.check(not stalled, name .. ": the walk and its battle ended inside " .. limit .. " turns of the loop")
    if stalled then
      U.log("NOTE", name, "stalled:", L.battleState and L.battleState() or "")
      AutoWalk.stop()
      local clean = L.endBattle and L.endBattle() or false
      L.check(clean, name .. ": the field is free again after the stall, at " .. L.where())
    end
    L.check(mon.level == level + 1, name .. ": level " .. level .. " became " .. tostring(mon.level))
    L.check(moveList(mon) == before, name .. ": moves kept (" .. before .. " then " .. moveList(mon) .. ")")
    local _, px, py = L.pos()
    L.check(math.abs(px - target.x) + math.abs(py - target.y) == 1,
      name .. ": beside " .. leader .. " (" .. target.x .. "," .. target.y .. "), at " .. L.where())
  end

  if scene("level") then toLeader("level", "FR_PEWTER_CITY_GYM", 5, 13, "Brock", 90) end
  if scene("learn") then
    -- the highest level below 89 at which a Blastoise knowing these moves learns another
    local probe = L.giveParty(9, 30, fieldMoves, fieldMoves)
    local level
    for candidate = 88, 30, -1 do
      local learned = LearnMove.movesForLevels(probe, { candidate + 1 })
      if learned and #learned > 0 then level = candidate break end
    end
    if level then
      U.log("NOTE", "learn: a new move comes at level", level + 1)
      toLeader("learn", "FR_CERULEAN_CITY_GYM", 7, 17, "Misty", level)
    else
      L.check(false, "learn: a level with a new move was found")
    end
  end
  L.finish("gen3_levelup_walk")
  U.log("DONE")
end
