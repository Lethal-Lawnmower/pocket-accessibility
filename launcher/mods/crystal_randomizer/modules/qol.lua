-- Crystal randomizer: quality-of-life options.  Nothing here is random; each
-- option is the save's own answer, applied while that save is loaded and
-- undone exactly when another save (or a vanilla one) is.
--
-- 1. Experience multiplier (qol_exp: "1", "1.5", "2" or "3").  The engine
--    asks the `exp.gain` hook for every party member's share of a defeated
--    POKéMON's experience (src/battle/gen2/Battle.lua giveExperiencePass,
--    the one Gen 2 battle path that awards experience, EXP. SHARE pass
--    included).  The wrap multiplies the amount the vanilla formula gave
--    (after the trainer, traded and LUCKY EGG bonuses), with integer maths so
--    1.5 is exactly 3/2 rounded down.  The battle's "gained N EXP. Points!"
--    line prints the multiplied amount, because it is the amount the engine
--    pays.  Stat experience is not changed.
--
-- 2. Minimum catch rate (qol_catch).  The `catch.rate` hook receives the
--    options table the throw is computed from (src/battle/gen2/Catching.lua
--    attempt); a species whose catch rate is below CATCH_FLOOR is thrown at as
--    if its rate were CATCH_FLOOR.  The ball's own multiplier and the HP and
--    status terms then apply as usual, so a ball still matters.  The hook is
--    only wrapped while a save that asked for it is loaded: Catching.chance
--    returns nil whenever any catch.rate hook exists (a mod might replace the
--    roll), and an unwrapped hook keeps that preview for every other save.
--
-- 3. Blind trainers (qol_blind).  A map trainer is an object whose `trainer`
--    struct the extractor read (data.gen2Maps[map].objects[i].trainer), and
--    World:checkTrainerBattle engages one when Trainers.sees finds the player
--    within its `sight` cells.  Trainers.sees answers nil for a sight of 0, so
--    this module sets `sight` to 0 on every such object and puts the cart's
--    value back on a switch.  Talking to the trainer goes through
--    World:interact -> startTrainerScript(TALK_TO_TRAINER_SCRIPT), which never
--    reads `sight`, so every map trainer, Team Rocket's grunts and executives
--    included, still battles when spoken to, with the same seen text, battle
--    and after-battle script.  The rival, the gym leaders, the Elite Four and
--    Team Rocket's scripted battles are coord events and talk scripts
--    (`loadtrainer` / `startbattle`), not map trainers: nothing here touches
--    them.
--
--    Why data and not the trainer.before_battle hook: that hook cannot tell a
--    sighting from a talk (its ctx carries neither), and a sighting cancelled
--    through it still makes checkTrainerBattle answer true, which ends that
--    frame of World:update before the landed-step block runs (warps, coord
--    events, wild encounters on that step would be skipped).  A sight of 0 is
--    the cart's own "never looks" value, so nothing downstream sees a change.
--    Navigation names a trainer from its sprite and never from its sight
--    (src/access/nav/gen2/WorldSnapshot.lua), so the object list still lists
--    each one as a person to talk to.

local M = {
  id = "qol",
  questions = {
    { key = "qol_exp", kind = "choice", text = "How many EXP.\nPOINTS to earn?",
      options = {
        { label = "NORMAL", value = "1" },
        { label = "1.5 TIMES", value = "1.5" },
        { label = "2 TIMES", value = "2" },
        { label = "3 TIMES", value = "3" },
      },
      recommended = "1.5", everything = "2" },
    { key = "qol_catch", kind = "yesno", text = "Make rare POKéMON\neasier to catch?",
      recommended = true, everything = true },
    { key = "qol_blind", kind = "yesno", text = "Battle trainers\nonly if you talk?",
      recommended = false, everything = true },
  },
}

-- The catch rate every species is at least as easy to catch as.  100 is
-- PIDGEOTTO's band (cart rates run 3 for the legendaries, 25 for SNORLAX and
-- SCIZOR, 45 for the starters and most evolved forms, up to 255): with a
-- POKé BALL a full-HP target is about 13% and a red-HP one about 39%; an
-- ULTRA BALL roughly doubles both.
M.CATCH_FLOOR = 100

-- Answer -> numerator, denominator.  Strings, so a saved answer is exact.
M.EXP_RATES = { ["1"] = { 1, 1 }, ["1.5"] = { 3, 2 }, ["2"] = { 2, 1 }, ["3"] = { 3, 1 } }

-- The loaded save's experience multiplier as numerator, denominator; 1, 1 for
-- a vanilla save or an answer this version does not know.
function M.expRate(ctx)
  local rate = ctx.active() and M.EXP_RATES[tostring(ctx.option("qol_exp"))] or nil
  if not rate then return 1, 1 end
  return rate[1], rate[2]
end

-- `amount` scaled by num/den, rounded down, at least 1 (the cart's own floor
-- for a defeated POKéMON's experience).
function M.scaleExp(amount, num, den)
  if type(amount) ~= "number" or num == den then return amount end
  return math.max(1, math.floor(amount * num / den))
end

-- The loaded save's catch-rate floor, or nil.
function M.catchFloor(ctx)
  if ctx.active() and ctx.option("qol_catch") == true then return M.CATCH_FLOOR end
  return nil
end

-- A copy of a throw's options with the floor applied to catchRate, or the
-- same table when the rate already meets it.  Catching.rate reads a missing
-- catchRate as 45, so that is what the floor is compared with.
function M.flooredOptions(o, floor)
  if type(o) ~= "table" or not floor then return o end
  local rate = tonumber(o.catchRate) or 45
  if rate >= floor then return o end
  local copy = {}
  for k, v in pairs(o) do copy[k] = v end
  copy.catchRate = floor
  return copy
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

-- Every map trainer that can see: { mapId, object } in a fixed order.
function M.seeingTrainers(maps)
  local out = {}
  for _, mapId in ipairs(sortedKeys(maps)) do
    local map = maps[mapId]
    for _, object in ipairs(type(map) == "table" and map.objects or {}) do
      if type(object) == "table" and type(object.trainer) == "table"
         and type(object.sight) == "number" and object.sight > 0 then
        out[#out + 1] = { mapId = mapId, object = object }
      end
    end
  end
  return out
end

function M.install(mod, ctx)
  -- 1. Experience: one wrap for the session; it asks ctx on every award.
  mod.hooks:wrap("exp.gain", function(nextFn, ...)
    local amount = nextFn(...)
    local num, den = M.expRate(ctx)
    return M.scaleExp(amount, num, den)
  end)

  -- 2. Catch rate: wrapped only while a save that asked for it is loaded.
  -- `wrapped` is the remover the wrap returned, or true when the host's wrap
  -- returned none: that wrap stays, and it still asks ctx on every throw, so
  -- it does nothing for a save that did not ask for the floor.
  local wrapped
  local function catchHook(nextFn, ball, mon, def, o, ...)
    return nextFn(ball, mon, def, M.flooredOptions(o, M.catchFloor(ctx)), ...)
  end
  local function syncCatchHook()
    local want = M.catchFloor(ctx) ~= nil
    if want and not wrapped then
      local remove = mod.hooks:wrap("catch.rate", catchHook)
      wrapped = type(remove) == "function" and remove or true
    elseif not want and type(wrapped) == "function" then
      wrapped()
      wrapped = nil
    end
  end

  -- 3. Blind trainers: { object, vanilla sight } rows, put back by restore().
  local changed = {}
  local function restore()
    for i = #changed, 1, -1 do
      local row = changed[i]
      row.object.sight = row.vanilla
    end
    changed = {}
  end

  local function gameMaps()
    local ok, game = pcall(function() return mod.game end)
    local data = ok and type(game) == "table" and game.data or nil
    return type(data) == "table" and type(data.gen2Maps) == "table" and data.gen2Maps or nil
  end

  local function blind()
    local maps = gameMaps()
    if not maps then
      ctx.log("qol: no map data yet; trainers keep their sight")
      return
    end
    for _, row in ipairs(M.seeingTrainers(maps)) do
      changed[#changed + 1] = { object = row.object, vanilla = row.object.sight }
      row.object.sight = 0
    end
    ctx.log("qol: %d trainers battle only when spoken to", #changed)
  end

  ctx.onSave(function(active)
    restore()
    syncCatchHook()
    if active and ctx.option("qol_blind") == true then blind() end
    if active then
      local num, den = M.expRate(ctx)
      ctx.log("qol: experience x%s, catch floor %s, blind trainers %s",
        num == den and "1" or tostring(num / den), tostring(M.catchFloor(ctx) or "off"),
        tostring(ctx.option("qol_blind") == true))
    end
  end)
end

return M
