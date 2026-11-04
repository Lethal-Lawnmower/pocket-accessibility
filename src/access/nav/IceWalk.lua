-- Auto-walk's thin ice puzzle (Sootopolis Gym, Ruby, Sapphire and Emerald).  Every thin ice
-- cell of a room must be stepped on exactly once: a second step on one drops the player to
-- the floor below (src/core/game3/step_callbacks_rse.lua sootopolisIce), and the room's way
-- on opens only when the count of cells is reached (the map's frame scripts).  When a target
-- has no route and the floor has thin ice, this finds one path that covers a whole room and
-- walks it, one cell at a time, then asks again.  What it reads is only the floor: which
-- cells are thin, which have cracked, which side is walled.  Any key stops it, like any walk.
-- AUTO-WALK PUZZLES in the Accessibility page turns it off.

local Speech = require("src.access.Speech")

local IceWalk = {}

local run = nil
local SEARCH_LIMIT = 400000

function IceWalk.active() return run ~= nil end

local function autoWalk() return require("src.access.nav.AutoWalk") end

function IceWalk.stop(reason)
  if not run then return false end
  run = nil
  autoWalk().stop()
  if reason then Speech.say(reason, { interrupt = true }) end
  return true
end

local DIRS = { { "up", 0, -1 }, { "right", 1, 0 }, { "down", 0, 1 }, { "left", -1, 0 } }

-- One room's thin cells (a connected group) and the floor cells beside them.
local function rooms(map, isThin)
  local seen, found = {}, {}
  for y = 0, map.heightCells - 1 do
    for x = 0, map.widthCells - 1 do
      local key = y * 1024 + x
      if isThin(map:behavior(x, y)) and not seen[key] then
        local cells, queue, head = {}, { { x, y } }, 1
        seen[key] = true
        while queue[head] do
          local cx, cy = queue[head][1], queue[head][2]
          head = head + 1
          cells[#cells + 1] = { x = cx, y = cy }
          for _, d in ipairs(DIRS) do
            local nx, ny = cx + d[2], cy + d[3]
            local nk = ny * 1024 + nx
            if map:inBounds(nx, ny) and not seen[nk] and isThin(map:behavior(nx, ny))
               and not map:dirBlocked(cx, cy, nx, ny, d[1]) then
              seen[nk] = true
              queue[#queue + 1] = { nx, ny }
            end
          end
        end
        found[#found + 1] = cells
      end
    end
  end
  return found
end

-- A path over every cell of `cells`, each once, from a neighbouring floor cell `start`,
-- ending beside a way out that is not `start` (a cracked cell cannot be walked back over).
-- Fewest onward choices first, so dead ends show early.  Returns the cells to step to, or nil.
local function coverRoom(map, cells, start, beside)
  local inRoom, count = {}, 0
  for _, cell in ipairs(cells) do
    inRoom[cell.y * 1024 + cell.x] = true
    count = count + 1
  end
  local nexts = {}
  for _, cell in ipairs(cells) do
    local list = {}
    for _, d in ipairs(DIRS) do
      local nx, ny = cell.x + d[2], cell.y + d[3]
      if inRoom[ny * 1024 + nx] and not map:dirBlocked(cell.x, cell.y, nx, ny, d[1]) then
        list[#list + 1] = ny * 1024 + nx
      end
    end
    nexts[cell.y * 1024 + cell.x] = list
  end
  local exits = {}
  for _, cell in ipairs(beside or {}) do
    if not (cell.x == start.x and cell.y == start.y) then exits[#exits + 1] = cell end
  end
  local function endsAtExit(key)
    if #exits == 0 then return true end
    local x, y = key % 1024, math.floor(key / 1024)
    for _, exit in ipairs(exits) do
      if math.abs(exit.x - x) + math.abs(exit.y - y) == 1 then return true end
    end
    return false
  end
  local used, path, steps = {}, {}, 0
  local function dive(key, left)
    steps = steps + 1
    if steps > SEARCH_LIMIT then return false end
    used[key] = true
    path[#path + 1] = key
    if left == 1 then
      if endsAtExit(key) then return true end
      used[key] = nil
      path[#path] = nil
      return false
    end
    -- prune: what is left must hang together from here, with at most one cell that can
    -- only be the last
    local reach, queue, head, ends = { [key] = true }, { key }, 1, 0
    while queue[head] do
      local here = queue[head]
      head = head + 1
      local free = 0
      for _, m in ipairs(nexts[here]) do
        if not used[m] or m == key then free = free + 1 end
        if not used[m] and not reach[m] then
          reach[m] = true
          queue[#queue + 1] = m
        end
      end
      if here ~= key and free <= 1 then ends = ends + 1 end
    end
    if #queue ~= left or ends > 1 then
      used[key] = nil
      path[#path] = nil
      return false
    end
    local order = {}
    for _, n in ipairs(nexts[key]) do
      if not used[n] then
        local free = 0
        for _, m in ipairs(nexts[n]) do if not used[m] then free = free + 1 end end
        order[#order + 1] = { n, free }
      end
    end
    table.sort(order, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
    for _, row in ipairs(order) do
      if dive(row[1], left - 1) then return true end
    end
    used[key] = nil
    path[#path] = nil
    return false
  end
  for _, d in ipairs(DIRS) do
    local nx, ny = start.x + d[2], start.y + d[3]
    if inRoom[ny * 1024 + nx] and not map:dirBlocked(start.x, start.y, nx, ny, d[1]) then
      if dive(ny * 1024 + nx, count) then
        local list = {}
        for i, key in ipairs(path) do list[i] = { x = key % 1024, y = math.floor(key / 1024) } end
        return list
      end
    end
  end
  return nil
end

-- The walk to the next room with thin ice left that a route reaches: its floor cell beside
-- the ice, and the path to cover it.  Nil, and why, when there is none.
local function nextRoom(nav, map, isThin, player)
  local AutoWalk = autoWalk()
  local refused = false
  for _, cells in ipairs(rooms(map, isThin)) do
    local beside, seen = {}, {}
    for _, cell in ipairs(cells) do
      for _, d in ipairs(DIRS) do
        local nx, ny = cell.x + d[2], cell.y + d[3]
        local key = ny * 1024 + nx
        if map:inBounds(nx, ny) and not seen[key] and not isThin(map:behavior(nx, ny)) and map:isWalkableCell(nx, ny)
           and not map:warpAt(nx, ny) and map:behavior(nx, ny) ~= nav.crackedIceBehavior then
          seen[key] = true
          beside[#beside + 1] = { x = nx, y = ny }
        end
      end
    end
    -- nearest way in first
    table.sort(beside, function(a, b)
      return math.abs(a.x - player.cellX) + math.abs(a.y - player.cellY)
        < math.abs(b.x - player.cellX) + math.abs(b.y - player.cellY)
    end)
    for _, cell in ipairs(beside) do
      local here = cell.x == player.cellX and cell.y == player.cellY
      if here or AutoWalk.routeExists(nav, { cell }) then
        local path = coverRoom(map, cells, cell, beside)
        if path then return { entry = cell, path = path } end
        refused = true
      end
    end
  end
  return nil, refused and "cracked" or nil
end

-- Starts when this floor has thin ice a route reaches and no route to the target exists.
-- False leaves the caller's "No route" to be said.
function IceWalk.tryStart(nav, game, adapter, item, goals, overworld)
  if type(nav.thinIceBehavior) ~= "function" or not nav:thinIceBehavior() then return false end
  if not require("src.access.Settings").autoWalkBoulders(game) then return false end
  local thin = nav:thinIceBehavior()
  local function isThin(beh) return beh == thin end
  local map = overworld.map
  local plan = nextRoom(nav, map, isThin, overworld.player)
  if not plan then return false end
  run = { nav = nav, game = game, adapter = adapter, overworld = overworld, map = map, isThin = isThin,
    id = item.id, label = item.label, plan = plan, phase = "entry", index = 0, selection = nav.browseSelectionId,
    filter = nav.browseFilter }
  Speech.say("Stepping once on every thin ice cell to reach " .. tostring(item.label), { interrupt = true })
  return true
end

local function step(goal)
  autoWalk().start(run.nav, run.game, run.adapter, { goals = { goal }, quiet = true })
end

-- Per frame, after AutoWalk.update.
function IceWalk.update()
  if not run then return end
  local AutoWalk = autoWalk()
  if AutoWalk.active() then return end
  if not run.adapter.onMap(run.game) then return end
  if run.overworld.map ~= run.map then
    -- the floor gave way, or a door took the player: the journey is theirs to ask for again
    return IceWalk.stop("Left the floor, auto walk stopped")
  end
  local player = run.overworld.player
  if player.moving then return end
  if run.phase == "entry" then
    if player.cellX == run.plan.entry.x and player.cellY == run.plan.entry.y then
      run.phase, run.index = "cover", 0
    else
      run.tries = (run.tries or 0) + 1
      if run.tries > 3 then return IceWalk.stop("Could not reach the ice, auto walk stopped") end
      return step(run.plan.entry)
    end
  end
  if run.phase == "cover" then
    local target = run.plan.path[run.index + 1]
    if not target then
      run.phase, run.calm = "after", 0
    elseif player.cellX == target.x and player.cellY == target.y then
      run.index = run.index + 1
      run.tries = 0
      return
    else
      run.tries = (run.tries or 0) + 1
      if run.tries > 3 then return IceWalk.stop("Could not walk the ice, auto walk stopped") end
      return step(target)
    end
  end
  if run.phase == "after" then
    run.calm = run.calm + 1
    if run.calm < 30 then return end
    local nav, game, adapter = run.nav, run.game, run.adapter
    nav.browseFilter, nav.browseSelectionId = run.filter, run.selection
    local ok, item, goals = pcall(nav.selectedRouteGoals, nav)
    if ok and type(item) == "table" and item.id == run.id and type(goals) == "table" and #goals > 0
       and AutoWalk.routeExists(nav, goals) then
      run = nil
      return AutoWalk.start(nav, game, adapter)
    end
    local plan, why = nextRoom(nav, run.map, run.isThin, player)
    if not plan then
      return IceWalk.stop(why == "cracked" and "The ice left cannot be crossed in one go, auto walk stopped"
        or ("No route to " .. tostring(run.label) .. " after the ice, auto walk stopped"))
    end
    run.plan, run.phase, run.tries = plan, "entry", 0
  end
end

function IceWalk._state() return run end

return IceWalk
