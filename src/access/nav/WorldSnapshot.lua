-- Reused from the old Pocket Accessibility project (src/accessibility/WorldSnapshot.lua at
-- commit 71cdd419e) under decision 20; adapted for v0.3.98.

-- Read-only semantic view of the native overworld.
--
-- This module deliberately knows nothing about rendering, emulators, speech,
-- input, or the Game singleton.  It consumes the live OverworldState shape
-- (map, player, and npcs) and returns detached values suitable for narration.
-- Map-cell meaning is obtained from the live Map predicates, so block changes
-- and registry patches are reflected without maintaining a second map model.

local WorldSnapshot = {}
local ChaosCut = require("src.access.nav.ChaosCut")

WorldSnapshot.FILTER_ORDER = {
  "all", "warps", "connections", "signposts", "objects", "area",
}

WorldSnapshot.CONNECTION_ORDER = {
  "north", "south", "east", "west",
}

local FILTER_ALIASES = {
  all = "all",
  warp = "warps", warps = "warps",
  connection = "connections", connections = "connections",
  sign = "signposts", signs = "signposts",
  signpost = "signposts", signposts = "signposts",
  object = "objects", objects = "objects",
  entity = "objects", entities = "objects",
  -- v0.3.98 addition: off-map item balls of the current area
  -- (Navigation:areaBrowse fills this category)
  area = "area",
}

local FILTER_TYPES = {
  warps = "warp",
  area = "area",
  connections = "connection",
  signposts = "signpost",
  objects = "object",
}

local DELTA = {
  up = { 0, -1 }, down = { 0, 1 },
  left = { -1, 0 }, right = { 1, 0 },
  north = { 0, -1 }, south = { 0, 1 },
  west = { -1, 0 }, east = { 1, 0 },
}

local DISPLAY_WORDS = {
  ss = "S.S.", mt = "Mt.", mr = "Mr.",
  pokemon = "Pok\195\169mon", pkmn = "Pok\195\169mon",
  pc = "PC", hm = "HM", tm = "TM", tv = "TV",
  silph = "Silph", co = "Co.",
}

-- Canonical exterior doors whose raw destination floor is technically
-- correct but misleading as a city landmark. These labels describe the
-- physical entrance without changing the underlying warp or indoor map name.
local EXTERIOR_WARP_LABELS = {
  CELADON_CITY = {
    CELADON_MART_1F = "Celadon Department Store main entrance",
    CELADON_MART_5F = "Celadon Department Store fifth-floor entrance",
  },
}

local function nonempty(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

local function metadataLabel(record)
  if type(record) ~= "table" then return nil end
  if nonempty(record.accessibilityLabel) then return record.accessibilityLabel end
  local a11y = record.accessibility
  if type(a11y) == "table" and nonempty(a11y.label) then return a11y.label end
  if nonempty(record.displayName) then return record.displayName end
  if nonempty(record.label) then return record.label end
  return nil
end

-- Convert generated ids and mod fallback ids into useful spoken text.  An
-- explicit accessibilityLabel always wins before this function is needed.
function WorldSnapshot.humanize(value)
  if not nonempty(value) then return nil end
  local text = value
  text = text:gsub("([a-z])([A-Z])", "%1 %2")
  text = text:gsub("([A-Z])([A-Z][a-z])", "%1 %2")
  text = text:gsub("([a-z])(%d)", "%1 %2")
  text = text:gsub("[_%-]+", " ")
  text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

  local words = {}
  for word in text:gmatch("%S+") do
    local lower = word:lower()
    if DISPLAY_WORDS[lower] then
      words[#words + 1] = DISPLAY_WORDS[lower]
    elseif word:match("^%d+[Ff]$") or word:match("^[Bb]%d+[Ff]$") then
      words[#words + 1] = word:upper()
    elseif word:match("^[A-Z]+%d+$") then
      local letters, number = word:match("^([A-Z]+)(%d+)$")
      words[#words + 1] = letters:sub(1, 1) .. letters:sub(2):lower()
      words[#words + 1] = number
    elseif word:match("^[A-Z%d]+$") then
      words[#words + 1] = word:sub(1, 1) .. word:sub(2):lower()
    else
      words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2)
    end
  end
  return #words > 0 and table.concat(words, " ") or nil
end

local function mapDefAndId(mapOrDef, fallbackId)
  local record = type(mapOrDef) == "table" and mapOrDef or {}
  local def = type(record.def) == "table" and record.def or record
  local id = fallbackId or record.id or def.id
  return def, id
end

-- Deterministic location fallback: authored accessible/display names first,
-- then the registry id (which is more readable than an assembler label),
-- then the label, and finally a fixed nonempty phrase.
function WorldSnapshot.locationName(mapOrDef, fallbackId, customName, playerName,
                                    generation, edition, rivalName)
  if nonempty(customName) then return customName end
  local def, id = mapDefAndId(mapOrDef, fallbackId)
  local explicit = nonempty(def.accessibilityLabel) and def.accessibilityLabel
  local a11y = def.accessibility
  if not explicit and type(a11y) == "table" and nonempty(a11y.label) then
    explicit = a11y.label
  end
  if generation == 2 then
    -- Gen II has both Red's Kanto house and the current player's New Bark
    -- home. A mod's explicit accessibility label may override either one.
    if explicit then return explicit end
    local floor = id == "REDS_HOUSE_1F" and "1F"
      or (id == "REDS_HOUSE_2F" and "2F")
    if floor then return "Red's House " .. floor end
    floor = id == "PLAYERS_HOUSE_1F" and "1F"
      or (id == "PLAYERS_HOUSE_2F" and "2F")
    if floor and nonempty(playerName) then
      return playerName .. "'s House " .. floor
    end
  end
  if nonempty(playerName) then
    if id == "REDS_HOUSE_1F" then return playerName .. "'s House 1F" end
    if id == "REDS_HOUSE_2F" then return playerName .. "'s House 2F" end
  end
  if not explicit and nonempty(def.displayName) then explicit = def.displayName end
  -- Generated map records can repeat the registry id in `name`; that is not
  -- an authored display label and should not mask the spoken fallback.
  if not explicit and nonempty(def.name) and def.name ~= id then
    explicit = def.name
  end
  if explicit then return explicit end
  if id == "BLUES_HOUSE" then
    if generation == 2 then return "Blue's House" end
    return (nonempty(rivalName) and rivalName or "Blue") .. "'s House"
  end
  -- Access's Yellow map table names these two locations differently from
  -- their native symbolic ids. This is only a speech fallback: authored map
  -- labels, including those supplied by mods, have already taken priority.
  if generation ~= 2 and edition == "yellow" then
    if id == "CERULEAN_MELANIES_HOUSE" then return "Bulbasaur House" end
    if id == "SUMMER_BEACH_HOUSE" then return "Beach House" end
  end
  return WorldSnapshot.humanize(id)
      or WorldSnapshot.humanize(def.label)
      or "Unknown location"
end

local function invoke(map, method, ...)
  local fn = type(map) == "table" and map[method] or nil
  if type(fn) ~= "function" then return nil, "missing " .. method end
  local ok, result = pcall(fn, map, ...)
  if not ok then return nil, tostring(result) end
  return result
end

local CELL_LABELS = {
  edge = "map edge",
  warp = "warp",
  signpost = "signpost",
  counter = "counter",
  grass = "tall grass",
  water = "water",
  walkable = "path",
  blocked = "blocked",
  unknown = "unknown terrain",
}

-- Classify a cell exclusively through the live Map query surface.  Predicate
-- failures are contained and reported in `errors`; accessibility must never
-- turn malformed mod metadata into a gameplay crash.
function WorldSnapshot.classifyCell(map, x, y)
  local cell = { x = x, y = y, errors = {} }
  if type(x) ~= "number" or type(y) ~= "number" then
    cell.kind, cell.label = "unknown", CELL_LABELS.unknown
    cell.errors[1] = "cell coordinates must be numbers"
    return cell
  end

  local inBounds, boundsErr = invoke(map, "inBounds", x, y)
  if inBounds == nil then
    cell.errors[#cell.errors + 1] = "inBounds: " .. tostring(boundsErr)
    local width = type(map) == "table" and map.widthCells or nil
    local height = type(map) == "table" and map.heightCells or nil
    if type(width) == "number" and type(height) == "number" then
      inBounds = x >= 0 and y >= 0 and x < width and y < height
    end
  end
  cell.inBounds = inBounds == true
  if inBounds == false then
    cell.kind, cell.label = "edge", CELL_LABELS.edge
    return cell
  elseif inBounds ~= true then
    cell.kind, cell.label = "unknown", CELL_LABELS.unknown
    return cell
  end

  local function query(method)
    local value, err = invoke(map, method, x, y)
    if err then
      cell.errors[#cell.errors + 1] = method .. ": " .. tostring(err)
      return nil
    end
    return value
  end

  cell.tile = query("cellTile")
  local warp = query("warpAtCell")
  local signpost = query("signAtCell")
  cell.warp = warp ~= nil and warp ~= false
  cell.warpIndex = type(warp) == "table" and warp.index or nil
  cell.signpost = signpost ~= nil and signpost ~= false
  cell.warpTile = query("isWarpTileCell") == true
  cell.counter = query("isCounterCell") == true
  cell.grass = query("isGrassCell") == true
  cell.water = query("isWaterCell") == true
  cell.walkable = query("isWalkableCell") == true

  if cell.warp or cell.warpTile then
    cell.kind = "warp"
  elseif cell.signpost then
    cell.kind = "signpost"
  elseif cell.counter then
    cell.kind = "counter"
  elseif cell.grass then
    cell.kind = "grass"
  elseif cell.water then
    cell.kind = "water"
  elseif cell.walkable then
    cell.kind = "walkable"
  elseif #cell.errors > 0 then
    cell.kind = "unknown"
  else
    cell.kind = "blocked"
  end
  cell.label = CELL_LABELS[cell.kind]
  return cell
end

function WorldSnapshot.relative(fromX, fromY, toX, toY)
  if type(fromX) ~= "number" or type(fromY) ~= "number"
     or type(toX) ~= "number" or type(toY) ~= "number" then
    return nil, "relative coordinates must be numbers"
  end
  local dx, dy = toX - fromX, toY - fromY
  return {
    dx = dx,
    dy = dy,
    horizontal = dx < 0 and "left" or (dx > 0 and "right" or nil),
    horizontalDistance = math.abs(dx),
    vertical = dy < 0 and "up" or (dy > 0 and "down" or nil),
    verticalDistance = math.abs(dy),
    distance = math.abs(dx) + math.abs(dy),
    here = dx == 0 and dy == 0,
  }
end

-- Pok\195\169mon Access speaks vertical displacement first, followed by
-- horizontal displacement.  Preserve that order for behavioral parity.
function WorldSnapshot.formatRelative(fromX, fromY, toX, toY)
  local relative, err = WorldSnapshot.relative(fromX, fromY, toX, toY)
  if not relative then return nil, err end
  if relative.here then return "here" end
  local parts = {}
  if relative.vertical then
    parts[#parts + 1] = relative.verticalDistance .. " " .. relative.vertical
  end
  if relative.horizontal then
    parts[#parts + 1] = relative.horizontalDistance .. " " .. relative.horizontal
  end
  return table.concat(parts, " ")
end

local function stripOwnerPrefix(identifier, mapId, mapLabel)
  if not nonempty(identifier) then return identifier end
  local upper = identifier:upper()
  local prefixes = {}
  if nonempty(mapId) then
    prefixes[#prefixes + 1] = mapId:upper()
    prefixes[#prefixes + 1] = mapId:gsub("[^%w]", ""):upper()
  end
  if nonempty(mapLabel) then
    prefixes[#prefixes + 1] = mapLabel:gsub("[^%w]", ""):upper()
  end
  for _, prefix in ipairs(prefixes) do
    if upper:sub(1, #prefix + 1) == prefix .. "_" then
      return identifier:sub(#prefix + 2)
    end
  end
  return identifier
end

local function personName(role, opts)
  if opts.generation ~= 2 then return nil end
  if role == "rival" then return nonempty(opts.rivalName) and opts.rivalName end
  if role == "mom" then return nonempty(opts.momName) and opts.momName end
  if role == "player" then return nonempty(opts.playerName) and opts.playerName end
  if role == "red" then return "Red" end
  return nil
end

local function namedLabel(label, opts)
  if opts.generation ~= 2 then return label end
  return (label:gsub("%[([%a]+)%]", function(role)
    return personName(role, opts) or ("[" .. role .. "]")
  end))
end

local function entityLabel(entity, mapId, mapLabel, ordinal, isPlayer, opts)
  local def = type(entity.def) == "table" and entity.def or {}
  local explicit = metadataLabel(entity) or metadataLabel(def)
  if explicit then return namedLabel(explicit, opts) end
  if isPlayer then
    return WorldSnapshot.humanize(entity.name) or "Player"
  end
  if nonempty(def.item) then return WorldSnapshot.humanize(def.item) end
  -- Access's Red/Blue and Yellow sprite tables call their native Blue actor
  -- [rival], then substitute the current saved rival name during object browse.
  -- Match the symbolic extracted sprite, never its edition-specific ROM byte;
  -- authored labels above and mod-owned/runtime actors keep their own names.
  if (opts.generation == nil or opts.generation == 1)
     and not def.owner and def.runtime ~= true
     and def.sprite == "SPRITE_BLUE" and nonempty(opts.rivalName) then
    return opts.rivalName
  end
  if opts.generation == 2 then
    local a11y = type(def.accessibility) == "table" and def.accessibility
    local role = a11y and a11y.role
    local name = personName(role, opts)
    if name then return name end
    -- Access's GSC sprite table gives the rival and Mom saved-name labels.
    -- Use only native symbolic sprite keys on unowned cartridge objects;
    -- mod actors should supply explicit accessibility metadata instead.
    if not def.owner and def.runtime ~= true then
      if def.sprite == "SPRITE_RIVAL" then
        name = personName("rival", opts)
      elseif def.sprite == "SPRITE_MOM" then
        name = personName("mom", opts)
      end
      if name then return name end
    end
  end
  if nonempty(def.name) then
    return WorldSnapshot.humanize(stripOwnerPrefix(def.name, mapId, mapLabel))
  end
  if nonempty(def.sprite) then
    return WorldSnapshot.humanize(def.sprite:gsub("^SPRITE_", ""))
  end
  return "Object " .. tostring(def.index or ordinal or "unknown")
end

-- Copy the semantic properties of a live Player or NPC.  In-progress actors
-- report their current logical cell; no sprite/pixel/render state leaks out.
function WorldSnapshot.describeEntity(entity, opts)
  opts = opts or {}
  if type(entity) ~= "table" then return nil, "entity must be a table" end
  local def = type(entity.def) == "table" and entity.def or {}
  local mapId = opts.mapId or def.mapId or "unknown"
  local isPlayer = opts.isPlayer == true
  local ordinal = opts.ordinal
  local id = entity.accessibilityId or def.accessibilityId or entity.id
  if not nonempty(id) then
    if isPlayer then
      id = "player:" .. tostring(mapId)
    else
      id = "object:" .. tostring(mapId) .. ":"
           .. tostring(def.index or ordinal or "unknown")
    end
  end
  return {
    id = id,
    type = isPlayer and "player" or "object",
    category = isPlayer and "player" or "objects",
    label = entityLabel(entity, mapId, opts.mapLabel, ordinal, isPlayer, opts),
    x = entity.cellX,
    y = entity.cellY,
    facing = DELTA[entity.facing] and entity.facing or nil,
    moving = entity.moving == true,
    runtime = def.runtime == true,
    owner = def.owner,
    item = def.item,
    trainerClass = def.trainerClass,
    index = def.index or ordinal,
  }
end

function WorldSnapshot.normalizeFilter(filter)
  if filter == nil then return "all" end
  if type(filter) == "number" then
    return WorldSnapshot.FILTER_ORDER[filter]
  end
  if type(filter) ~= "string" then return nil end
  return FILTER_ALIASES[filter:lower()]
end

function WorldSnapshot.nextFilter(filter, delta)
  local normalized = WorldSnapshot.normalizeFilter(filter)
  if not normalized then return nil, "unknown browse filter: " .. tostring(filter) end
  local index = 1
  for i, name in ipairs(WorldSnapshot.FILTER_ORDER) do
    if name == normalized then index = i break end
  end
  local count = #WorldSnapshot.FILTER_ORDER
  local step = tonumber(delta) or 1
  index = ((index - 1 + step) % count) + 1
  return WorldSnapshot.FILTER_ORDER[index]
end

function WorldSnapshot.filter(items, filter)
  if type(items) ~= "table" then return nil, "browse items must be a table" end
  local normalized = WorldSnapshot.normalizeFilter(filter)
  if not normalized then return nil, "unknown browse filter: " .. tostring(filter) end
  local wanted = FILTER_TYPES[normalized]
  local result = {}
  for _, item in ipairs(items) do
    -- A browse category can differ from the route-goal type. Gen II pit
    -- holes belong to Access's Objects list, but still need warp-cell routing
    -- so guidance never asks the player to face and interact with the pit.
    if wanted == nil or (item.browseType or item.type) == wanted then
      result[#result + 1] = item
    end
  end
  return result
end

local function registryDef(maps, mapId)
  if type(maps) ~= "table" then return nil end
  local record = maps[mapId]
  if type(record) == "table" and type(record.def) == "table" then
    return record.def
  end
  return record
end

local function explicitOr(record, fallback)
  local explicit = metadataLabel(record)
  if explicit then return explicit end
  if type(record) == "table" and nonempty(record.name) then
    return WorldSnapshot.humanize(record.name)
  end
  return fallback
end

local function addPosition(item, player)
  -- A semantic destination may have several physical entrances. Use the
  -- nearest one only for the short browse-list bearing; navigation retains
  -- the full candidate set and chooses by actual path cost later.
  if type(item.navigationCells) == "table" and type(player) == "table"
     and type(player.cellX) == "number" and type(player.cellY) == "number" then
    local nearest, distance
    for _, cell in ipairs(item.navigationCells) do
      if type(cell) == "table" and type(cell.x) == "number"
         and type(cell.y) == "number" then
        local candidateDistance = math.abs(cell.x - player.cellX)
                                + math.abs(cell.y - player.cellY)
        if distance == nil or candidateDistance < distance then
          nearest, distance = cell, candidateDistance
        end
      end
    end
    if nearest then item.x, item.y = nearest.x, nearest.y end
  end
  if type(item.x) == "number" and type(item.y) == "number"
     and type(player) == "table"
     and type(player.cellX) == "number" and type(player.cellY) == "number" then
    item.relative = WorldSnapshot.relative(player.cellX, player.cellY,
                                           item.x, item.y)
    item.relativeText = WorldSnapshot.formatRelative(player.cellX, player.cellY,
                                                     item.x, item.y)
  end
  local description = item.label
  if nonempty(item.requirement) then
    description = description .. "; " .. item.requirement
  end
  if item.relativeText then description = description .. ": " .. item.relativeText end
  if item.facing then description = description .. "; facing " .. item.facing end
  if nonempty(item.stateText) then description = description .. "; " .. item.stateText end
  item.description = description
end

local function applyCustomLabel(item, names)
  local custom = type(names) == "table" and names[item.id] or nil
  if nonempty(custom) then item.label = custom end
end

local function applyObjectOverride(item, object, overrides)
  if type(overrides) ~= "table" then return end
  local def = type(object) == "table" and object.def or nil
  local override = overrides[item.id] or (def and overrides[def.name])
  if type(override) ~= "table" then return end
  for _, key in ipairs({ "label", "stateText", "interaction", "semanticKind",
                         "requiredFacing", "routeInstruction" }) do
    if override[key] ~= nil then item[key] = override[key] end
  end
end

local function applyChaosCutLabel(item, entity, opts)
  if opts and opts.chaosCut and ChaosCut.eligible(entity) then
    item.label = ChaosCut.label(item.label)
    item.interaction = "cut"
    item.semanticKind = "chaos_cut_actor"
  end
end

-- Resolve LAST_MAP exactly as the native map script will when the player
-- reaches this warp. Some connector maps rewrite wLastMap from position; in
-- Route 22 Gate this is what makes the north doors lead to Route 23 while the
-- south doors return to Route 22. Falling back to the remembered exterior is
-- correct only when the current map has no authored rewrite.
function WorldSnapshot.destinationId(overworld, mapId, warp, rewrites)
  -- Generation II spells the same "go back where you came from" contract as a
  -- destination warp of -1 ($ff), with destMap naming the map ITSELF -- so the
  -- shared Pokemon Center 2F staircase, and every elevator floor, declares
  -- POKECENTER_2F as its own destination.  Taken literally that labels the
  -- staircase with the room the player is standing in.
  --
  -- The world resolves this itself, through the backup warp triple the cart
  -- keeps for exactly this purpose, so ask it rather than reimplementing the
  -- rule here.  Gen I worlds have no `resolveWarp`, so this is inert for them
  -- and the LAST_MAP path below stays their only special case.
  if warp.destWarp == 0xff and type(overworld) == "table"
     and type(overworld.resolveWarp) == "function" then
    local ok, resolved = pcall(overworld.resolveWarp, overworld, warp)
    if ok and type(resolved) == "string" and resolved ~= "" then
      return resolved
    end
  end
  if warp.destMap ~= "LAST_MAP" then return warp.destMap end
  local rewrite = rewrites and rewrites[mapId]
  if type(rewrite) == "table" then
    local value = rewrite.axis == "x" and warp.x or warp.y
    for _, rule in ipairs(rewrite.rules or {}) do
      if (rule.below == nil or value < rule.below)
         and (rule.atLeast == nil or value >= rule.atLeast) then
        return rule.map
      end
    end
  end
  local last = type(overworld) == "table" and overworld.lastOutdoor
  return type(last) == "table" and last.id or "LAST_MAP"
end

local function liveNpcs(overworld)
  if type(overworld.npcs) == "table" then return overworld.npcs end
  local result = {}
  for _, entity in ipairs(overworld.entities or {}) do
    if entity ~= overworld.player then result[#result + 1] = entity end
  end
  return result
end

-- Browsing is about every live map object, not only actors that happen to be
-- registered in the NPC convenience list.  Strength boulders and mod-owned
-- interactive actors can live only in entities.  Prefer that authoritative
-- list when present, while retaining compatibility with small/test worlds
-- that expose only npcs.
local function liveObjects(overworld)
  local source = type(overworld.entities) == "table"
                 and overworld.entities or overworld.npcs or {}
  local result, seen = {}, {}
  for _, entity in ipairs(source) do
    if type(entity) == "table" and entity ~= overworld.player
       and not seen[entity] then
      seen[entity] = true
      result[#result + 1] = entity
    end
  end
  return result
end

-- Floors and named regions inside one dungeon are not interchangeable merely
-- because their warps share a destination map. Mt. Moon's three 1F ladders
-- land in disconnected B1F pockets; Safari Zone North/West likewise has two
-- physically separate passages. Keep contiguous trigger tiles together while
-- retaining distinct internal entrances. Explicit target ids can still merge
-- authored noncontiguous entrances when a map or mod knows they are equivalent.
local function transitionFamily(mapId)
  if type(mapId) ~= "string" then return nil end
  local floorBase = mapId:gsub("_B?%d+F$", "")
  if floorBase ~= mapId then return floorBase end
  if mapId:match("^SAFARI_ZONE_") then return "SAFARI_ZONE" end
  return nil
end

local function distinctInternalTransitions(mapId, destId)
  if mapId == destId then return true end
  local fromFamily, toFamily = transitionFamily(mapId), transitionFamily(destId)
  return fromFamily ~= nil and fromFamily == toFamily
end

local function adjacentToNavigationCell(item, x, y)
  for _, cell in ipairs(item.navigationCells or {}) do
    if math.abs(cell.x - x) + math.abs(cell.y - y) == 1 then return true end
  end
  return false
end

-- A defined warp is not necessarily an active transition. The native world
-- only takes a Gen I warp on a warp tile or a qualifying edge/carpet input;
-- Gen II requires warp collision. Keep unknown/mod-provided map surfaces
-- visible rather than guessing, but use native queries when they exist.
local function browsableWarp(map, warp, index, opts)
  if warp.accessibilityBrowsable == false then return false end
  if warp.accessibilityBrowsable == true then return true end
  if type(map.warpAtCell) ~= "function"
      or type(map.isWarpTileCell) ~= "function" then return true end
  local active, activeError = invoke(map, "warpAtCell", warp.x, warp.y)
  if activeError then return true end
  if type(active) ~= "table" then return false end
  if active.index ~= nil and active.index ~= index then return false end
  local tile, tileError = invoke(map, "isWarpTileCell", warp.x, warp.y)
  if tileError then return true end
  if tile == true then return true end
  if opts.generation == 2 then return false end
  local def = type(map.def) == "table" and map.def or {}
  local width = map.widthCells or ((tonumber(def.width) or 0) * 2)
  local height = map.heightCells or ((tonumber(def.height) or 0) * 2)
  if width > 0 and height > 0 and (warp.x == 0 or warp.y == 0
      or warp.x == width - 1 or warp.y == height - 1) then return true end
  local carpets = type(opts.field) == "table" and opts.field.warpCarpets
  if type(carpets) ~= "table" then return false end
  local Warp = require("src.world.Warp")
  for _, dir in ipairs({ "up", "down", "left", "right" }) do
    local ok, fires = pcall(Warp.extraCheck, map, carpets,
      warp.x, warp.y, dir)
    if ok and fires then return true end
  end
  return false
end
-- v0.3.98 addition: shared with Navigation:regionalTransitions so the
-- cross-map planner ignores the same inactive data warps the list hides.
WorldSnapshot.browsableWarp = browsableWarp

-- Build the browse list in Pok\195\169mon Access order: active warps, then
-- north/south/east/west connections, then signposts, then live objects.
-- opts.maps is the merged map registry and is used only to improve destination
-- labels.  opts.filter accepts singular/plural names or the original 1..5
-- filter positions.
function WorldSnapshot.browse(overworld, opts)
  opts = opts or {}
  if type(overworld) ~= "table" or type(overworld.map) ~= "table" then
    return nil, "no overworld"
  end
  local map = overworld.map
  local def, mapId = mapDefAndId(map)
  mapId = mapId or "unknown"
  local items = {}

  -- Several physical warp tiles can represent one semantic destination: a
  -- double-width door or two entrances to one building. Group by destination
  -- plus the authoritative label (or an explicit accessibilityTargetId), never
  -- by a label alone. Internal dungeon/area transitions are an exception:
  -- only contiguous trigger tiles merge, because separate ladders/passages can
  -- lead to disconnected pockets of the same destination map. The first legacy
  -- warp id remains the browse selection id so custom names and focus stay stable.
  local warpTargets, warpTargetOrder = {}, {}
  local internalTargets = {}
  local browseableWarps = {}
  for i, warp in ipairs(def.warps or {}) do
    if browsableWarp(map, warp, i, opts) then
      browseableWarps[#browseableWarps + 1] = { index = i, warp = warp }
    end
  end
  for _, entry in ipairs(browseableWarps) do
    local i, warp = entry.index, entry.warp
    local destId = WorldSnapshot.destinationId(
      overworld, mapId, warp, opts.lastMapRewrites)
    local destDef = registryDef(opts.maps, destId)
    local fallback
    if destId == "LAST_MAP" then
      fallback = "Exit"
    else
      fallback = WorldSnapshot.locationName(
        destDef or { id = destId }, destId, nil, opts.playerName,
        opts.generation, opts.edition, opts.rivalName)
    end
    local exteriorLabels = EXTERIOR_WARP_LABELS[mapId]
    if exteriorLabels and exteriorLabels[destId] then
      fallback = exteriorLabels[destId]
    end
    -- A hole is not a door.  Stepping onto one is irreversible and lands the
    -- player somewhere they did not choose, so it is named as a drop and
    -- identified BEFORE the first step as well as on arrival -- the same
    -- treatment the special-traversal branch gives an authored hole.  Gen I
    -- reaches that branch through authored map scripts; Gen II has no authored
    -- equivalent and marks the warp itself, so this reads `kind` on the warp
    -- and is inert for a generation that does not set it.
    local isHole = warp.kind == "hole"
    local browseAsObject = isHole and opts.generation == 2
    if isHole then fallback = "Drop to " .. tostring(fallback or "destination") end
    local item = {
      id = warp.accessibilityId or ("warp:" .. tostring(mapId) .. ":" .. i),
      type = "warp", category = browseAsObject and "objects" or "warps",
      browseType = browseAsObject and "object" or nil, index = i,
      label = explicitOr(warp, fallback or ("Warp " .. i)),
      x = warp.x, y = warp.y,
      destinationMapId = destId,
      destinationWarp = warp.destWarp,
      navigationCells = {
        { x = warp.x, y = warp.y, destinationWarp = warp.destWarp },
      },
      routePreamble = isHole and fallback or nil,
    }
    -- Edge carpets (house exits, gates and similar) require one final input
    -- out of the map after reaching the warp cell. A route that merely says
    -- "Arrived" strands the player on the carpet. Interior stairs/pads fire
    -- when entered and intentionally have no extra instruction.
    local width = map.widthCells or ((tonumber(def.width) or 0) * 2)
    local height = map.heightCells or ((tonumber(def.height) or 0) * 2)
    local outward = warp.x == 0 and "left"
      or (width > 0 and warp.x == width - 1 and "right")
      or warp.y == 0 and "up"
      or (height > 0 and warp.y == height - 1 and "down")
    if outward then
      item.transitionInstruction = "Continue " .. outward .. " to "
        .. tostring(fallback or "destination")
      item.navigationCells[1].transitionInstruction = item.transitionInstruction
    end
    local targetId = warp.accessibilityTargetId
    if not targetId then
      local baseTarget = "destination:" .. tostring(destId)
        .. ":" .. tostring(item.label)
      if distinctInternalTransitions(mapId, destId) then
        local clusters = internalTargets[baseTarget] or {}
        internalTargets[baseTarget] = clusters
        for _, candidate in ipairs(clusters) do
          if adjacentToNavigationCell(candidate, warp.x, warp.y) then
            targetId = candidate._targetId
            break
          end
        end
        if not targetId then
          targetId = baseTarget .. ":entrance:" .. tostring(i)
          item._targetId = targetId
          item._internalLabelKey = baseTarget
          clusters[#clusters + 1] = item
        end
      else
        targetId = baseTarget
      end
    end
    local group = warpTargets[targetId]
    if group then
      group.navigationCells[#group.navigationCells + 1] = {
        x = warp.x, y = warp.y, destinationWarp = warp.destWarp,
        transitionInstruction = item.transitionInstruction,
      }
      group.transitionInstruction = group.transitionInstruction
        or item.transitionInstruction
    else
      warpTargets[targetId] = item
      warpTargetOrder[#warpTargetOrder + 1] = item
    end
  end
  local internalCounts, internalPositions = {}, {}
  for _, item in ipairs(warpTargetOrder) do
    local key = item._internalLabelKey
    if key then internalCounts[key] = (internalCounts[key] or 0) + 1 end
  end
  for _, item in ipairs(warpTargetOrder) do
    local key = item._internalLabelKey
    if key and internalCounts[key] > 1 then
      internalPositions[key] = (internalPositions[key] or 0) + 1
      item.label = item.label .. ", entrance " .. internalPositions[key]
        .. " of " .. internalCounts[key]
    end
    item._targetId, item._internalLabelKey = nil, nil
    applyCustomLabel(item, opts.names)
    addPosition(item, overworld.player)
    items[#items + 1] = item
  end

  local traversal = type(opts.specialTraversal) == "table"
                    and opts.specialTraversal or {}
  for i, warp in ipairs(traversal.specialWarps or {}) do
    local destId = warp.destinationMap
    local destDef = registryDef(opts.maps, destId)
    local destName = WorldSnapshot.locationName(
      destDef or { id = destId }, destId, nil, opts.playerName,
      opts.generation, opts.edition, opts.rivalName)
    local fallback = warp.kind == "hole"
      and ("Drop to " .. destName) or ("Special exit to " .. destName)
    local item = {
      id = warp.id or ("special_warp:" .. tostring(mapId) .. ":" .. i),
      type = "warp", category = "warps", index = i,
      label = explicitOr(warp, fallback),
      x = warp.x, y = warp.y,
      destinationMapId = destId,
      destinationX = warp.destinationX,
      destinationY = warp.destinationY,
      transitionInstruction = fallback,
      -- Continuous guidance normally speaks only its next movement. Holes are
      -- irreversible, so identify their landing before the first step as well
      -- as at arrival. The navigation session consumes this preamble once.
      routePreamble = warp.kind == "hole" and fallback or nil,
      specialTraversal = true,
    }
    applyCustomLabel(item, opts.names)
    addPosition(item, overworld.player)
    items[#items + 1] = item
  end

  local connections = def.connections or {}
  for _, direction in ipairs(WorldSnapshot.CONNECTION_ORDER) do
    local connection = connections[direction]
    if type(connection) == "table" then
      -- Gen I writes the destination NAME into `map` and nothing into `mapId`.
      -- Gen II writes the raw numeric map byte into `map` and the name into
      -- `mapId`, so reading `map` alone looked a number up in a name-keyed
      -- registry, missed, and ran the whole locationName fallback chain to its
      -- last resort: every route and town connection in Gold, Silver and
      -- Crystal browsed as "Unknown location", four per outdoor map, each one
      -- correctly positioned and completely unidentified.  The live engine
      -- reads both (src/world/gen2/World.lua:476); so does this now.
      local destId = connection.mapId or connection.map
      local destDef = registryDef(opts.maps, destId)
      local destName = WorldSnapshot.locationName(
        destDef or { id = destId }, destId, nil, opts.playerName,
        opts.generation, opts.edition, opts.rivalName)
      local fallback = WorldSnapshot.humanize(direction)
                       .. " connection to " .. destName
      local item = {
        id = connection.accessibilityId
             or ("connection:" .. tostring(mapId) .. ":" .. direction),
        type = "connection", category = "connections",
        direction = direction,
        label = explicitOr(connection, fallback),
        destinationMapId = destId,
        offset = connection.offset,
      }
      applyCustomLabel(item, opts.names)
      addPosition(item, overworld.player)
      items[#items + 1] = item
    end
  end

  for i, sign in ipairs(def.signs or {}) do
    -- The cartridge's `text` field is a script identifier, not a public
    -- description. Distinct Gen I signs can resolve to the same tail (for
    -- example TEXT_ROUTE_1_SIGN -> "Sign"), making browse selection ambiguous.
    -- Access uses each sign's one-based event ordinal. An authored `name`,
    -- accessibility label, or user rename still wins in explicitOr below.
    local fallback = "Signpost " .. i
    -- v0.3.98 addition: the elevator cars' only sign is the floor panel
    -- (TEXT_CELADONMARTELEVATOR and friends), which is worth naming.
    if mapId:find("ELEVATOR", 1, true) and tostring(sign.text):find("ELEVATOR", 1, true) then
      fallback = "Floor panel"
    end
    if opts.generation == 2 then
      local raw = nonempty(sign.name) and sign.name or sign.text
      if nonempty(raw) then raw = raw:gsub("^TEXT_", "") end
      fallback = WorldSnapshot.humanize(
        stripOwnerPrefix(raw, mapId, def.label)) or fallback
    end
    local item = {
      id = sign.accessibilityId
           or ("signpost:" .. tostring(mapId) .. ":" .. i),
      type = "signpost", category = "signposts", index = i,
      label = explicitOr(sign, fallback),
      x = sign.x, y = sign.y,
      textId = sign.text,
    }
    applyCustomLabel(item, opts.names)
    addPosition(item, overworld.player)
    items[#items + 1] = item
  end


  for i, target in ipairs(traversal.switches or {}) do
    local item = {
      id = target.id or ("switch:" .. tostring(mapId) .. ":" .. i),
      -- Pokemon Access presents special switches and quiz machines alongside
      -- other map objects, not ordinary signs.
      type = "object", category = "objects", index = i,
      label = explicitOr(target, "Switch " .. tostring(i)),
      x = target.x, y = target.y,
      requiredFacing = target.requiredFacing,
      specialTraversal = true,
    }
    applyCustomLabel(item, opts.names)
    addPosition(item, overworld.player)
    items[#items + 1] = item
  end

  -- Tile/block-backed features (for example Cut trees and Vermilion Gym
  -- trash cans) have no actor in the native entity array.  Accessibility may
  -- supply live semantic projections without manufacturing gameplay actors.
  for i, target in ipairs(opts.interactiveObjects or {}) do
    local interactionCells = {}
    for _, cell in ipairs(target.interactionCells or {}) do
      if type(cell) == "table" and type(cell.x) == "number"
         and type(cell.y) == "number" then
        interactionCells[#interactionCells + 1] = { x = cell.x, y = cell.y }
      end
    end
    local item = {
      id = target.id or ("interactive:" .. tostring(mapId) .. ":" .. i),
      type = "object", category = "objects", index = target.index or i,
      label = explicitOr(target, "Interactive object " .. tostring(i)),
      x = target.x, y = target.y,
      requiredFacing = target.requiredFacing,
      interaction = target.interaction,
      interactionCells = interactionCells,
      semanticKind = target.semanticKind,
      requirement = target.requirement,
      stateText = target.stateText,
      routeInstruction = target.routeInstruction,
      synthetic = true,
    }
    applyCustomLabel(item, opts.names)
    addPosition(item, overworld.player)
    items[#items + 1] = item
  end

  for i, object in ipairs(liveObjects(overworld)) do
    local item = WorldSnapshot.describeEntity(object, {
      mapId = mapId, mapLabel = def.label, ordinal = i,
      generation = opts.generation, playerName = opts.playerName,
      rivalName = opts.rivalName, momName = opts.momName,
    })
    applyObjectOverride(item, object, opts.objectOverrides)
    applyCustomLabel(item, opts.names)
    applyChaosCutLabel(item, object, opts)
    addPosition(item, overworld.player)
    items[#items + 1] = item
  end

  return WorldSnapshot.filter(items, opts.filter)
end

-- Capture the active world's complete semantic snapshot.  Every returned
-- table is newly allocated; callers cannot mutate the live map or actors by
-- editing this result.
function WorldSnapshot.capture(overworld, opts)
  opts = opts or {}
  if type(overworld) ~= "table" or type(overworld.map) ~= "table" then
    return nil, "no overworld"
  end
  if type(overworld.player) ~= "table" then return nil, "no player" end
  local map = overworld.map
  local def, mapId = mapDefAndId(map)
  mapId = mapId or "unknown"
  local customNames = type(opts.customNames) == "table" and opts.customNames or {}
  local mapNames = type(customNames.maps) == "table" and customNames.maps or {}
  local objectNames = type(customNames.objects) == "table"
                      and customNames.objects[mapId] or nil
  local browseOpts = {}
  for key, value in pairs(opts) do browseOpts[key] = value end
  browseOpts.names = objectNames
  local player = WorldSnapshot.describeEntity(overworld.player, {
    mapId = mapId, mapLabel = def.label, isPlayer = true,
    generation = opts.generation, playerName = opts.playerName,
    rivalName = opts.rivalName, momName = opts.momName,
  })
  local npcs, entities = {}, { player }
  for i, npc in ipairs(liveNpcs(overworld)) do
    local description = WorldSnapshot.describeEntity(npc, {
      mapId = mapId, mapLabel = def.label, ordinal = i,
      generation = opts.generation, playerName = opts.playerName,
      rivalName = opts.rivalName, momName = opts.momName,
    })
    applyChaosCutLabel(description, npc, opts)
    npcs[#npcs + 1] = description
  end
  for i, object in ipairs(liveObjects(overworld)) do
    local description = WorldSnapshot.describeEntity(object, {
      mapId = mapId, mapLabel = def.label, ordinal = i,
      generation = opts.generation, playerName = opts.playerName,
      rivalName = opts.rivalName, momName = opts.momName,
    })
    applyChaosCutLabel(description, object, opts)
    entities[#entities + 1] = description
  end

  local facingCell, facingError
  local delta = DELTA[overworld.player.facing]
  local px, py = overworld.player.cellX, overworld.player.cellY
  if type(px) ~= "number" or type(py) ~= "number" then
    facingError = "player coordinates must be numbers"
  elseif delta then
    facingCell = WorldSnapshot.classifyCell(
      map, px + delta[1], py + delta[2])
  else
    facingError = "unknown facing: " .. tostring(overworld.player.facing)
  end
  local browse, browseErr = WorldSnapshot.browse(overworld, browseOpts)
  if not browse then return nil, browseErr end
  return {
    mapId = mapId,
    locationName = WorldSnapshot.locationName(
      map, mapId, mapNames[mapId], opts.playerName, opts.generation,
      opts.edition, opts.rivalName),
    width = map.widthCells,
    height = map.heightCells,
    player = player,
    currentCell = WorldSnapshot.classifyCell(map, px, py),
    facingCell = facingCell,
    facingError = facingError,
    npcs = npcs,
    entities = entities,
    browseFilter = WorldSnapshot.normalizeFilter(opts.filter),
    browse = browse,
  }
end

return WorldSnapshot
