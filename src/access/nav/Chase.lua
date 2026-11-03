-- Chase: keeps after an object that runs off when talked to (owner request,
-- 2026-11-03, for the Ilex Forest Farfetch'd), with no knowledge of any map,
-- object or script.  Everything comes from watching the live object list:
-- walk beside it, face it, press A, see where it went.  Each side tried from
-- each cell is remembered, so a side that sends it the wrong way is not tried
-- again; when no untried side is left anywhere it can be reached, it has
-- stopped running.
--
-- AutoWalk starts a chase: the player walked to an object, stayed put, and on
-- the next auto-walk it is at least two cells from where it stood.  Text the
-- game opens stays the player's to read and advance.

local Speech = require("src.access.Speech")

local Chase = {}

local CALM_FRAMES = 30 -- free and unchanged this long: the object's move is over
local MAX_PRESSES = 64

local chase = nil

local function cellKey(x, y) return tostring(x) .. "," .. tostring(y) end

function Chase.active() return chase ~= nil end

function Chase.stop(reason)
  if not chase then return false end
  local AutoWalk = require("src.access.nav.AutoWalk")
  AutoWalk.releaseDirection(chase.game.input, chase.held)
  chase.game.input.state.a = false
  chase = nil
  AutoWalk.stop()
  if reason then Speech.say(reason, { interrupt = true }) end
  return true
end

function Chase.start(nav, game, adapter, item, overworld)
  chase = {
    nav = nav, game = game, adapter = adapter, overworld = overworld,
    map = overworld.map, id = item.id, label = item.label,
    tried = {}, complete = {}, presses = 0, phase = "choose",
  }
  Speech.say("Following " .. tostring(item.label), { interrupt = true })
  return true
end

-- Gold and Silver's bird is one object per place, each shown in turn, so it
-- leaves the list under one id and returns under another.  When the selected
-- id has gone and exactly one object has the same name, that is the same
-- thing: select it.  Returns the id now selected, or nil.
function Chase.relink(nav, id, label)
  if type(nav.captureWorld) ~= "function" then return nil end
  local ok, snapshot = pcall(nav.captureWorld, nav, nav.browseFilter)
  if not (ok and type(snapshot) == "table") then return nil end
  local match, count = nil, 0
  for _, item in ipairs(snapshot.browse or {}) do
    if item.id == id then return id end
    if item.label == label then match, count = item.id, count + 1 end
  end
  if count ~= 1 then return nil end
  if nav.browseSelectionId == id then nav.browseSelectionId = match end
  return match
end

-- The selected object now, following it if it changed id.
local function currentItem()
  local nav = chase.nav
  local newId = Chase.relink(nav, chase.id, chase.label)
  if newId then chase.id = newId end
  local ok, item, goals = pcall(nav.selectedRouteGoals, nav)
  if ok and type(item) == "table" and item.id == chase.id then return item, goals end
  return nil
end

-- The first step toward a cell with sides left to try, through moves already
-- seen: { goal key } from `from`, or nil when every known cell is exhausted.
local function knownWayOut(from)
  local queue, seen, head = { { cell = from } }, { [from] = true }, 1
  while queue[head] do
    local node = queue[head]
    head = head + 1
    for goal, to in pairs(chase.tried[node.cell] or {}) do
      if to ~= "blocked" and not seen[to] then
        seen[to] = true
        local first = node.first or goal
        if not chase.complete[to] then return first end
        queue[#queue + 1] = { cell = to, first = first }
      end
    end
  end
  return nil
end

local function chooseSide()
  local nav = chase.nav
  local item, goals = currentItem()
  if not item then
    return Chase.stop(tostring(chase.label) .. " is gone, stopped following")
  end
  if chase.presses >= MAX_PRESSES then
    return Chase.stop("Still chasing " .. tostring(chase.label) .. " after many tries, stopped following")
  end
  local here = cellKey(item.x, item.y)
  local tried = chase.tried[here] or {}
  chase.tried[here] = tried
  local byKey, pick = {}, nil
  for _, goal in ipairs(type(goals) == "table" and goals or {}) do
    local key = cellKey(goal.x, goal.y)
    byKey[key] = goal
    if tried[key] == nil and not pick then pick = goal end
  end
  if not pick then
    chase.complete[here] = true
    local key = knownWayOut(here)
    pick = key and byKey[key]
    if not pick then
      return Chase.stop(tostring(chase.label) .. " has stopped running, stopped following")
    end
  end
  chase.goal, chase.from, chase.targetX, chase.targetY = pick, here, item.x, item.y
  local player = chase.overworld.player
  if player.cellX == pick.x and player.cellY == pick.y then
    chase.phase = "face"
    return
  end
  chase.phase = "walking"
  local AutoWalk = require("src.access.nav.AutoWalk")
  AutoWalk.start(nav, chase.game, chase.adapter, { goals = { pick }, quiet = true })
end

-- Per frame, after AutoWalk.update.
function Chase.update()
  if not chase then return end
  local AutoWalk = require("src.access.nav.AutoWalk")
  if AutoWalk.active() then return end
  local input = chase.game.input
  if chase.phase == "pressed" then
    input.state.a = false
    chase.phase, chase.calm = "settling", 0
  end
  if not chase.adapter.onMap(chase.game) then
    if chase.phase == "settling" then chase.calm = 0 end
    return
  end
  if chase.overworld.map ~= chase.map then
    return Chase.stop("Left the map, stopped following " .. tostring(chase.label))
  end
  local player = chase.overworld.player
  if chase.phase == "choose" then return chooseSide() end
  local goalKey = cellKey(chase.goal.x, chase.goal.y)
  if chase.phase == "walking" then
    if player.cellX == chase.goal.x and player.cellY == chase.goal.y then
      chase.phase = "face"
    else
      chase.tried[chase.from][goalKey] = "blocked"
      chase.phase = "choose"
    end
    return
  end
  if chase.phase == "face" then
    if player.moving then return end
    local dx, dy = chase.targetX - player.cellX, chase.targetY - player.cellY
    local dir
    if math.abs(dx) > math.abs(dy) then dir = dx > 0 and "right" or "left"
    else dir = dy > 0 and "down" or "up" end
    if player.facing ~= dir then
      if chase.held ~= dir then
        AutoWalk.releaseDirection(input, chase.held)
        chase.held = dir
      end
      AutoWalk.holdDirection(input, dir)
      return
    end
    AutoWalk.releaseDirection(input, chase.held)
    chase.held = nil
    chase.presses = chase.presses + 1
    table.insert(input.pressQueue, "a")
    input.state.a = true
    chase.phase = "pressed"
    return
  end
  if chase.phase == "settling" then
    chase.calm = chase.calm + 1
    if chase.calm < CALM_FRAMES then return end
    local item = currentItem()
    if not item then
      return Chase.stop(tostring(chase.label) .. " is gone, stopped following")
    end
    local now = cellKey(item.x, item.y)
    chase.tried[chase.from][goalKey] = now
    if now ~= chase.from then Speech.say(tostring(chase.label) .. " moved", { interrupt = false }) end
    chase.phase = "choose"
  end
end

function Chase._state() return chase end

return Chase
