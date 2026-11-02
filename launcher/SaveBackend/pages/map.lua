-- The Map page: how the owner teleports.  The list chooses a map, X and Y choose a
-- cell, and the actions are upstream's panels/MapBrowser.lua pointActions, run with
-- S.mapId and S.mapClickCell set exactly as a click on the map would set them.
--
-- MapBrowser.preview is not used for the cell: with no love.graphics it falls back
-- to a bare grid that cannot say what a cell is.  The game's own map objects need no
-- renderer, so they answer instead: Map (Gen 1), gen2.Map, and for Gen 3 navigation's
-- read-only view of the layout's collision bytes (src/access/nav/gen3/World.lua).
local Ops = require("Ops")
local Gen = require("Gen")
local MapBrowser = require("MapBrowser")

local Page = {}

-- ------------------------------------------------------------------ names

local function playerName(save)
  return (save.player and save.player.name) or save.name or save.playerName
end

-- The names navigation speaks in the game, so a map is called the same thing in both.
local function computeName(S, id, def)
  local generation = Gen.ofState(S)
  local name
  if generation == 3 then
    name = require("src.access.nav.gen3.WorldSnapshot").locationName(
      def, id, nil, playerName(S.save), S.save.rivalName)
  else
    name = require("src.access.nav.WorldSnapshot").locationName(
      def, id, nil, playerName(S.save), generation, S.version)
  end
  return name or tostring(id)
end

-- Sorted rows of { id, name }, rebuilt only when a name could have changed.
local function mapIndex(S, state)
  local owner = tostring(playerName(S.save)) .. "/" .. tostring(S.save.rivalName)
  if state.index and state.indexOwner == owner then return state.index end
  local index, names, used = {}, {}, {}
  for id, def in pairs(Gen.maps(S.data)) do
    if type(def) == "table" then
      local name = computeName(S, id, def)
      names[id] = name
      index[#index + 1] = { id = id, name = name, key = name:lower() }
      used[name] = (used[name] or 0) + 1
    end
  end
  -- two maps tidied to one name stay apart by their ids
  for _, entry in ipairs(index) do
    if used[entry.name] > 1 then
      entry.name = entry.name .. " (" .. entry.id .. ")"
      names[entry.id] = entry.name
    end
  end
  table.sort(index, function(a, b)
    if a.key ~= b.key then return a.key < b.key end
    return a.id < b.id
  end)
  state.index, state.indexOwner, state.names = index, owner, names
  return index
end

local function nameOf(S, state, id)
  mapIndex(S, state)
  return state.names[id] or tostring(id)
end

-- ------------------------------------------------------------- map objects

local function gridOnly(id, def, generation)
  local factor = generation == 3 and 1 or 2
  local grid = { id = id, def = def, widthCells = def.width * factor, heightCells = def.height * factor }
  function grid:inBounds(x, y) return x >= 0 and y >= 0 and x < self.widthCells and y < self.heightCells end
  return grid
end

-- The map object for `id`, or nil and a reason.  One with no isWalkableCell has no
-- real collision data, and the page says so rather than guess.
local function buildMap(S, id, def)
  if type(def) ~= "table" then return nil, "unknown map" end
  if type(def.width) ~= "number" or type(def.height) ~= "number" then
    return nil, "incomplete map record, missing its size"
  end
  local generation = Gen.ofState(S)
  local built
  if generation == 3 then
    local ok, view = pcall(function()
      return require("src.access.nav.gen3.World").plannedView({ data = S.data }, def)
    end)
    built = ok and view or nil
  elseif type(def.blocks) == "table" then
    local tileset = Gen.tilesets(S.data)[def.tileset]
    if generation == 2 and tileset and tileset.collision then
      local ok, map = pcall(require("src.world.gen2.Map").new, def, tileset)
      built = ok and map or nil
    elseif generation == 1 and tileset and tileset.walkable then
      local ok, map = pcall(require("src.world.Map").new, def, tileset)
      built = ok and map or nil
    end
  end
  return built or gridOnly(id, def, generation)
end

local function mapObject(S, state, id)
  state.objects = state.objects or {}
  local cached = state.objects[id]
  if cached then return cached.map, cached.reason end
  local map, reason = buildMap(S, id, Gen.maps(S.data)[id])
  state.objects[id] = { map = map, reason = reason }
  return map, reason
end

-- ------------------------------------------------------------------- warps

-- The warp on a cell.  `active` is false for a warp in the map's data that the game
-- ignores (Gen 3 keeps some on real walls), which the game's warpAtCell leaves out.
local function warpAtCell(map, x, y)
  local found = map.warpAtCell and map:warpAtCell(x, y)
  if found then return found.def, found.index, true end
  for index, warp in ipairs(map.def.warps or {}) do
    if warp.x == x and warp.y == y then return warp, index, map.warpAtCell == nil end
  end
  return nil
end

-- Where a warp leads: map, landing x and y, or nil and why it cannot be known here.
local function warpDestination(S, map, warp)
  local generation = Gen.ofState(S)
  if generation == 3 then
    local destination, x, y
    if map.warpDestination then destination, x, y = map:warpDestination(warp) end
    if not destination then
      destination = warp.destMap or warp.map
      if type(destination) ~= "string" or destination == "" then
        return nil, "This warp's destination cannot be read from the map data; elevators and link rooms decide it during play"
      end
    end
    return destination, x, y
  end
  if generation == 2 then
    local destination = warp.destMap or warp.map
    if not destination then return nil, "Warp has no destination map" end
    local def = Gen.maps(S.data)[destination]
    local landing = def and def.warps and def.warps[warp.destWarp]
    return destination, landing and landing.x, landing and landing.y
  end
  if warp.destMap == "LAST_MAP" and not S.save.lastOutdoor then
    return nil, "Can't follow warp: no remembered outdoor map"
  end
  local ok, destination, x, y = pcall(require("src.world.Warp").destination, S.data, warp, S.save.lastOutdoor)
  if not ok then return nil, "Warp failed: " .. tostring(destination) end
  return destination, x, y
end

local function destinationLabel(S, state, map, warp)
  local destination, x, y = warpDestination(S, map, warp)
  if not destination then
    if warp.destMap == "LAST_MAP" then return "the last outdoor map, none remembered" end
    return "a destination that cannot be read from the map data"
  end
  local words = nameOf(S, state, destination)
  if x and y then words = ("%s, cell %d, %d"):format(words, x, y) end
  if warp.destMap == "LAST_MAP" then words = "last outdoor map, " .. words end
  if warp.destWarp == 0xff then words = words .. ", or back where you came from" end
  return words
end

-- ------------------------------------------------------------------- cells

local function walkable(map, x, y)
  return map.isWalkableCell ~= nil and map:isWalkableCell(x, y) == true
end

-- A cell the player can reach, near the middle: flood from the warps over walkable
-- cells, because the walkable cell nearest the middle is often walled in.  With no
-- warp to start from, the nearest walkable cell; with no collision data, a warp's
-- cell or the middle.
local function sensibleCell(map)
  local width, height = map.widthCells, map.heightCells
  local midX, midY = math.floor(width / 2), math.floor(height / 2)
  local warps = map.def.warps or {}
  if not map.isWalkableCell then
    local first = warps[1]
    if first and map:inBounds(first.x, first.y) then return first.x, first.y end
    return midX, midY
  end
  local bestX, bestY, bestDistance
  local function consider(x, y)
    local distance = (x - midX) ^ 2 + (y - midY) ^ 2
    if not bestDistance or distance < bestDistance then bestX, bestY, bestDistance = x, y, distance end
  end
  local isWarp, seen, queue = {}, {}, {}
  for _, warp in ipairs(warps) do
    if map:inBounds(warp.x, warp.y) then
      local key = warp.y * width + warp.x
      isWarp[key], seen[key] = true, true
      queue[#queue + 1] = key
    end
  end
  local head = 1
  while head <= #queue do
    local key = queue[head]
    head = head + 1
    local x, y = key % width, math.floor(key / width)
    if not isWarp[key] then consider(x, y) end
    for _, step in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
      local nextX, nextY = x + step[1], y + step[2]
      local nextKey = nextY * width + nextX
      if map:inBounds(nextX, nextY) and not seen[nextKey] then
        seen[nextKey] = true
        if walkable(map, nextX, nextY) then queue[#queue + 1] = nextKey end
      end
    end
  end
  if bestX then return bestX, bestY end
  for radius = 0, math.max(width, height) do
    for y = midY - radius, midY + radius do
      for x = midX - radius, midX + radius do
        if (math.abs(x - midX) == radius or math.abs(y - midY) == radius)
          and map:inBounds(x, y) and walkable(map, x, y) then
          return x, y
        end
      end
    end
  end
  if warps[1] and map:inBounds(warps[1].x, warps[1].y) then return warps[1].x, warps[1].y end
  return midX, midY
end

-- Where the save puts the player.  A Gen 2 save with no position yet names a spawn
-- point, not a map, so it is resolved through the game's own table.
local function playerLocation(S)
  local map, x, y = Gen.playerMap(S.save)
  if not Gen.maps(S.data)[map] and Gen.ofState(S) == 2 then
    local spawns = S.data.gen2Landmarks and S.data.gen2Landmarks.spawns
    local spawn = spawns and spawns[map]
    if spawn and spawn.map then return spawn.map, spawn.x or 0, spawn.y or 0 end
  end
  return map, x or 0, y or 0
end

local function setDefaultCell(S, state)
  local map = mapObject(S, state, S.mapId)
  if not map then
    S.mapClickCell = nil
    return
  end
  local playerMap, x, y = playerLocation(S)
  if playerMap ~= S.mapId or not map:inBounds(x, y) then x, y = sensibleCell(map) end
  S.mapClickCell = { cx = x, cy = y }
end

-- Keeps S.mapId and S.mapClickCell usable: first use, after Reload (which empties
-- `state` and points S.mapId at the save again), and on a Gen 2 stub whose "map"
-- is really a spawn point.
local function ensureSelection(S, state)
  local maps = Gen.maps(S.data)
  if not state.ready or not maps[S.mapId] then
    local playerMap = playerLocation(S)
    if maps[playerMap] then
      S.mapId = playerMap
    elseif not maps[S.mapId] then
      local first = mapIndex(S, state)[1]
      S.mapId = first and first.id or S.mapId
    end
    state.ready = true
    setDefaultCell(S, state)
    return
  end
  local map = mapObject(S, state, S.mapId)
  local cell = S.mapClickCell
  if map and not (cell and map:inBounds(cell.cx, cell.cy)) then setDefaultCell(S, state) end
end

-- What a cell is, and a warning when the game would not let the player stand there.
-- Terrain only: people and boulders move during play and are not in the map data.
local function describeCell(S, state, map, x, y)
  local parts, warning = {}, nil
  local warp, _, active = warpAtCell(map, x, y)
  if warp then
    local where = destinationLabel(S, state, map, warp)
    if active then
      parts[#parts + 1] = "Warp to " .. where .. "."
    else
      parts[#parts + 1] = "A warp in the map data the game ignores, to " .. where .. "."
    end
  end
  if not map.isWalkableCell then
    parts[#parts + 1] = "Walkable or blocked is unknown: this map has no collision data here."
  elseif walkable(map, x, y) then
    parts[#parts + 1] = "Walkable."
  elseif warp and active then
    parts[#parts + 1] = "Arrivals land here."
  elseif map.isWaterCell and map:isWaterCell(x, y) then
    parts[#parts + 1] = "Water."
    warning = ("Cell %d, %d is water. Upstream allows placing the player there, but they may be stuck without Surf."):format(x, y)
  else
    parts[#parts + 1] = "Blocked."
    warning = ("Cell %d, %d is blocked. Upstream allows placing the player there, but they may be stuck."):format(x, y)
  end
  return table.concat(parts, " "), warning
end

-- ----------------------------------------------------------------- summary

local function located(S, state, id, x, y)
  if not id then return "unset" end
  return ("%s, cell %d, %d"):format(nameOf(S, state, id), x or 0, y or 0)
end

local function summaryLines(S, state, map, reason, warning)
  local save, generation = S.save, Gen.ofState(S)
  local lines = { "Player: " .. located(S, state, playerLocation(S)) .. "." }
  if generation == 3 then
    lines[#lines + 1] = "Last heal: " .. located(S, state, save.healMap, save.healX, save.healY) .. "."
  elseif generation == 2 then
    local value = save.spawn or "SPAWN_HOME"
    local spawns = S.data.gen2Landmarks and S.data.gen2Landmarks.spawns
    local spawn = type(value) == "string" and spawns and spawns[value]
    if spawn and spawn.map then
      lines[#lines + 1] = ("Spawn: %s, %s."):format(value, located(S, state, spawn.map, spawn.x, spawn.y))
    elseif type(value) == "string" then
      lines[#lines + 1] = ("Spawn: map %s. The game's whiteout looks up named spawn points, and this is not one."):format(
        nameOf(S, state, value))
    else
      lines[#lines + 1] = "Spawn: " .. located(S, state, value.map, value.x, value.y) .. "."
    end
  else
    local heal, outdoor = save.lastHeal, save.lastOutdoor
    lines[#lines + 1] = "Last heal: " .. (heal and located(S, state, heal.map, heal.x, heal.y) or "unset") .. "."
    lines[#lines + 1] = "Last outdoor: " .. (outdoor and located(S, state, outdoor.id, outdoor.x, outdoor.y) or "unset") .. "."
  end
  if map then
    lines[#lines + 1] = ("Viewing %s: %d by %d cells, %s."):format(nameOf(S, state, S.mapId),
      map.widthCells, map.heightCells, Ops.isOutdoor(S, map) and "outdoor" or "indoor")
  else
    lines[#lines + 1] = ("Failed to load %s: %s."):format(nameOf(S, state, S.mapId), tostring(reason))
  end
  if warning then lines[#lines + 1] = "Warning: " .. warning end
  return table.concat(lines, "\n")
end

-- ------------------------------------------------------------------- model

local function actionFor(S, entry)
  local action = { id = entry.id, enabled = true }
  if entry.id == "player" then
    action.label = "Put player here"
  elseif entry.id == "spawn" then
    action.label = "Set spawn here"
    -- Source read, World:healPoint: it looks save.spawn up in the spawn point table.
    -- Upstream's Ops writes a map id, which is not a key of that table.
    action.confirm = "Upstream stores this map's id as the spawn. The game's whiteout looks up named "
      .. "spawn points, so a whiteout may not bring you back here. Set it anyway?"
  elseif entry.id == "heal" then
    action.label = "Set last heal here"
  elseif entry.id == "outdoor" then
    action.label = "Set last outdoor here"
  else
    action.label = entry.label
  end
  return action
end

local function warpOptions(S, state, map)
  local options = { { value = 0, label = "Not on a warp" } }
  for index, warp in ipairs(map.def.warps or {}) do
    options[#options + 1] = { value = index, label = ("Cell %d, %d to %s"):format(
      warp.x, warp.y, tostring(destinationLabel(S, state, map, warp))) }
  end
  return options
end

function Page.model(S, state)
  ensureSelection(S, state)
  local index = mapIndex(S, state)
  local playerMap = playerLocation(S)
  local rows = {}
  for i, entry in ipairs(index) do
    rows[i] = { id = entry.id, text = entry.id == playerMap and entry.name .. ", player here" or entry.name }
  end
  local map, reason = mapObject(S, state, S.mapId)
  local fields, actions, warning = {}, {}, nil
  if map then
    local cell = S.mapClickCell
    local description
    description, warning = describeCell(S, state, map, cell.cx, cell.cy)
    local warp, warpIndex = warpAtCell(map, cell.cx, cell.cy)
    local issue = warning and "this cell is not walkable" or nil
    fields = {
      { id = "x", label = "X", kind = "number", value = cell.cx, lo = 0, hi = map.widthCells - 1, issue = issue,
        help = "Cells across, from the left edge." },
      { id = "y", label = "Y", kind = "number", value = cell.cy, lo = 0, hi = map.heightCells - 1, issue = issue,
        help = "Cells down, from the top edge." },
      { id = "cell", label = "Cell", kind = "info", value = description,
        help = "Terrain only. People and boulders move during play and are not in the map data." },
      { id = "warp", label = "Warps", kind = "choice", value = warp and warpIndex or 0,
        options = warpOptions(S, state, map), help = "Choosing a warp moves the cell onto it." },
    }
    for _, entry in ipairs(MapBrowser.pointActions(S, map)) do
      actions[#actions + 1] = actionFor(S, entry)
    end
    actions[#actions + 1] = { id = "follow", label = "Follow warp", enabled = warp ~= nil }
  end
  actions[#actions + 1] = { id = "goto", label = "Go to player's location" }
  return {
    summary = summaryLines(S, state, map, reason, warning),
    list = { label = "Maps", rows = rows, selected = S.mapId, filter = true },
    fields = fields,
    actions = actions,
  }
end

-- ---------------------------------------------------------------- commands

function Page.select(S, state, request)
  ensureSelection(S, state)
  local id = request.row
  if id == S.mapId or not Gen.maps(S.data)[id] then return end
  MapBrowser.select(S, id)
  setDefaultCell(S, state)
end

function Page.set(S, state, request)
  ensureSelection(S, state)
  local map = mapObject(S, state, S.mapId)
  if not map then return end
  local cell = S.mapClickCell
  if request.field == "warp" then
    local warp = (map.def.warps or {})[tonumber(request.value) or 0]
    if not warp then return end
    if not map:inBounds(warp.x, warp.y) then
      Ops.say(S, ("That warp's cell %d, %d is outside the map."):format(warp.x, warp.y))
      return
    end
    S.mapClickCell = { cx = warp.x, cy = warp.y }
    Ops.say(S, ("Cell %d, %d: warp to %s"):format(warp.x, warp.y, tostring(destinationLabel(S, state, map, warp))), "info")
    return
  end
  local value = math.floor(tonumber(request.value) or -1)
  local x = request.field == "x" and value or cell.cx
  local y = request.field == "y" and value or cell.cy
  if not map:inBounds(x, y) then
    Ops.say(S, ("%s must be from 0 to %d on this map."):format(request.field:upper(),
      (request.field == "x" and map.widthCells or map.heightCells) - 1))
    return
  end
  S.mapClickCell = { cx = x, cy = y }
end

local function followWarp(S, state, map)
  local cell = S.mapClickCell
  local warp = warpAtCell(map, cell.cx, cell.cy)
  if not warp then
    Ops.say(S, "This cell is not a warp.")
    return
  end
  local destination, x, y = warpDestination(S, map, warp)
  if not destination then
    Ops.say(S, tostring(x))
    return
  end
  if not Gen.maps(S.data)[destination] then
    Ops.say(S, "Warp leads to an unknown map: " .. tostring(destination))
    return
  end
  -- Unlike upstream's goToWarp this leaves save.lastOutdoor alone: looking around
  -- must not change the save without marking it changed.
  MapBrowser.select(S, destination)
  if x and y then S.mapClickCell = { cx = x, cy = y } else setDefaultCell(S, state) end
  ensureSelection(S, state)
  Ops.say(S, ("Followed warp to %s, cell %d, %d"):format(nameOf(S, state, destination),
    S.mapClickCell.cx, S.mapClickCell.cy), "info")
end

local function goToPlayer(S, state)
  local playerMap = playerLocation(S)
  if not Gen.maps(S.data)[playerMap] then
    Ops.say(S, "No player location on this save")
    return
  end
  MapBrowser.select(S, playerMap)
  setDefaultCell(S, state)
  local cell = S.mapClickCell
  Ops.say(S, ("Jumped to %s, cell %d, %d"):format(nameOf(S, state, playerMap), cell and cell.cx or 0, cell and cell.cy or 0), "info")
end

function Page.action(S, state, request)
  ensureSelection(S, state)
  if request.action == "goto" then return goToPlayer(S, state) end
  local map = mapObject(S, state, S.mapId)
  if not map then return end
  if request.action == "follow" then return followWarp(S, state, map) end
  for _, entry in ipairs(MapBrowser.pointActions(S, map)) do
    if entry.id == request.action then
      -- enabled or not, as a press on a disabled upstream button does: the run is
      -- what says why it is refused
      entry.run(S)
      return
    end
  end
end

return Page
