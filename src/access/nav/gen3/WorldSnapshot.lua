-- FireRed projected into the shared object-list vocabulary
-- (../WorldSnapshot.lua; decision 29).  Read-only: the projection copies
-- what it relabels and never changes a map def or a live object.
--
-- What the projection supplies that the shared module cannot read from a
-- Gen 3 map:
--   * map names: the id without its FR_ prefix, humanised as in Gen 1 and
--     Gen 2 ("Viridian City Pokemon Center 1F"), with the player's and
--     rival's houses named after them
--   * warps: only those the game fires (Collision's active set); the
--     destination resolved the way the game resolves it (dynamic warps
--     through the session; before the game has recorded one the warp is
--     "Exit"); holes marked so the list says "Drop to ..."
--   * connections re-keyed by direction (Gen 3 keeps an array)
--   * signs from bg events, named by what their script does (card key door,
--     secret switch, floor panel ...) or by the furniture they stand on, else
--     "Signpost N" by the event's ordinal; script keys are ROM addresses and
--     never spoken.  Hidden items are not listed (as in Gen 1 and Gen 2).
--     A card key door is listed while it is closed.
--   * objects named by their graphics (pret's OBJ_EVENT_GFX_* names), item
--     balls by the item their script gives, Blue by the rival's name;
--     invisible objects (script triggers) are not listed

local Shared = require("src.access.nav.WorldSnapshot")
local Scripts = require("src.access.nav.gen3.Scripts")
local Terrain = require("src.access.nav.gen3.TerrainSemantics")
local GameData = require("src.access.nav.gen3.GameData")

local Snapshot = {}
for key, value in pairs(Shared) do Snapshot[key] = value end

-- Gen 3 alone has a Misc stop: its flavor furniture (decision 36).
Snapshot.FILTER_ORDER = {
  "all", "warps", "connections", "signposts", "npcs", "objects", "misc", "area",
}

function Snapshot.nextFilter(filter, delta)
  return Shared.nextFilter(filter, delta, Snapshot.FILTER_ORDER)
end

local function nonempty(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

-- Words in FireRed map ids that the shared humaniser would misread.
local MAP_WORDS = {
  SSANNE = "S.S. Anne", OAKS = "Oak's", COPYCATS = "Copycat's",
  PSYCHICS = "Psychic's", LORELEIS = "Lorelei's", WARDENS = "Warden's",
  DIGLETTS = "Diglett's", BRUNOS = "Bruno's", AGATHAS = "Agatha's",
  LANCES = "Lance's", CHAMPIONS = "Champion's", POKEMON = "Pok\195\169mon",
  -- Ruby, Sapphire and Emerald
  BRENDANS = "Brendan's", MAYS = "May's", BIRCHS = "Birch's", CAPTAINS = "Captain's",
  COZMOS = "Cozmo's", DRAKES = "Drake's", GLACIAS = "Glacia's", PHOEBES = "Phoebe's",
  SIDNEYS = "Sidney's", STEVENS = "Steven's", WALLYS = "Wally's", SCOTTS = "Scott's",
  BRINEYS = "Briney's", LADYS = "Lady's", FAMILYS = "Family's", MANIACS = "Maniac's",
  LANETTES = "Lanette's", TUNNELERS = "Tunneler's", MASTERS = "Master's", HUNTERS = "Hunters'",
  CUTTERS = "Cutter's", RELEARNERS = "Relearner's", DELETERS = "Deleter's", RATERS = "Rater's",
  STERNS = "Stern's", AND = "and", OF = "of",
}

function Snapshot.mapIdName(mapId)
  if type(mapId) ~= "string" then return nil end
  local id = GameData.bareMapId(mapId):gsub("^SEVII_", "")
  id = GameData.RS_UNDERWATER[id] and ("UNDERWATER_" .. GameData.RS_UNDERWATER[id]) or id
  local words = {}
  for word in id:gmatch("[^_]+") do
    local fixed = MAP_WORDS[word]
    words[#words + 1] = fixed or Shared.humanize(word) or word
  end
  return table.concat(words, " ")
end

-- Location name for a FireRed map: a player rename, an authored label, the
-- player's and rival's houses, then the humanised id.
function Snapshot.locationName(mapOrDef, fallbackId, customName, playerName, rivalName)
  if nonempty(customName) then return customName end
  local record = type(mapOrDef) == "table" and mapOrDef or {}
  local def = type(record.def) == "table" and record.def or record
  local id = fallbackId or record.id or def.id
  if nonempty(def.accessibilityLabel) then return def.accessibilityLabel end
  if id == "FR_PLAYERS_HOUSE_1F" or id == "FR_PLAYERS_HOUSE_2F" then
    local floor = id:sub(-2)
    return (nonempty(playerName) and (playerName .. "'s House ") or "Your House ") .. floor
  end
  if id == "FR_RIVALS_HOUSE" then
    return (nonempty(rivalName) and (rivalName .. "'s House")) or "Rival's House"
  end
  return Snapshot.mapIdName(id) or "Unknown location"
end

-- ------------------------------------------------------------ objects

local GFX_NAME, GFX_NAME_GAME = nil, nil
local function gfxName(gfx)
  local game = GameData.id()
  if GFX_NAME == nil or (GFX_NAME_GAME ~= nil and GFX_NAME_GAME ~= game) then
    GFX_NAME, GFX_NAME_GAME = false, game
    local set = GameData.constants()
    local objects = set and set.event_objects
    local byId = objects and objects.byId
    if type(byId) == "table" then
      GFX_NAME = type(byId.OBJ_EVENT_GFX_) == "table" and byId.OBJ_EVENT_GFX_ or byId
    end
  end
  local name = GFX_NAME and GFX_NAME[tonumber(gfx)] or nil
  return type(name) == "string" and name or nil
end
function Snapshot.setGraphicsNames(names) GFX_NAME, GFX_NAME_GAME = names, nil end

local GFX_LABELS = {
  PROF_OAK = "Professor Oak", LT_SURGE = "Lt. Surge", MR_FUJI = "Mr. Fuji",
  GBA_KID = "Kid", MG_DELIVERYMAN = "Delivery Man", POKE_MANIAC = "Pok\195\169 Maniac",
  CABLE_CLUB_RECEPTIONIST = "Receptionist", UNION_ROOM_RECEPTIONIST = "Receptionist",
  UNUSED_MALE_RECEPTIONIST = "Receptionist", TRAINER_TOWER_DUDE = "Trainer Tower Guide",
  TEACHY_TV_HOST = "Teachy TV Host", OLD_MAN_LYING_DOWN = "Old Man",
  CUT_TREE = "Cuttable Tree", ROCK_SMASH_ROCK = "Smashable Rock",
  PUSHABLE_BOULDER = "Boulder", ITEM_BALL = "Pok\195\169 Ball",
  -- Ruby, Sapphire and Emerald (their sheets, in event_objects)
  CUTTABLE_TREE = "Cuttable Tree", BREAKABLE_ROCK = "Smashable Rock",
  PROF_BIRCH = "Professor Birch", BIRCHS_BAG = "Professor Birch's Bag",
  MR_BRINEYS_BOAT = "Mr. Briney's Boat", HOOH = "Ho-Oh", TEALA = "Attendant",
  LINK_RECEPTIONIST = "Receptionist", GAMEBOY_KID = "Kid", POKEFAN = "Pok\195\169 Fan",
  ROOFTOP_SALE_WOMAN = "Sale Clerk", HOT_SPRINGS_OLD_WOMAN = "Old Woman",
  TUBER_M_SWIMMING = "Tuber", CYCLING_TRIATHLETE = "Triathlete", RUNNING_TRIATHLETE = "Triathlete",
  AQUA_MEMBER = "Team Aqua Grunt", MAGMA_MEMBER = "Team Magma Grunt",
  GROUDON_ASLEEP = "Groudon", GROUDON_FRONT = "Groudon", GROUDON_SIDE = "Groudon",
  KYOGRE_ASLEEP = "Kyogre", KYOGRE_FRONT = "Kyogre", KYOGRE_SIDE = "Kyogre",
  RAYQUAZA_STILL = "Rayquaza", KECLEON_BRIDGE_SHADOW = "Kecleon",
  VIGOROTH_CARRYING_BOX = "Vigoroth", VIGOROTH_FACING_AWAY = "Vigoroth",
  TRICK_HOUSE_STATUE = "Statue", DEOXYS_TRIANGLE = "Triangle", SUBMARINE_SHADOW = "Submarine",
  SS_TIDAL = "S.S. Tidal", UNION_ROOM_NURSE = "Nurse", MYSTERY_GIFT_MAN = "Delivery Man",
  QUINTY_PLUMP = "Man", GIDDY = "Man", HIPSTER = "Man", MAN = "Man",
  NIDORAN_F = "Nidoran female", NIDORAN_M = "Nidoran male", HO_OH = "Ho-Oh",
  DEOXYS_D = "Deoxys", DEOXYS_A = "Deoxys", DEOXYS_N = "Deoxys", SS_ANNE = "S.S. Anne",
  OLD_AMBER = "Old Amber", POKEDEX = "Pok\195\169dex",
}

-- The graphics an object is drawn with.  A live object's variable sprite
-- (OBJ_EVENT_GFX_VAR_*, 240 and up) was resolved by the game when it
-- spawned; on a map that is not loaded the variable may not be set yet, so
-- such an object is only "Person" (nil here), never a guessed sheet.
local function resolvedGraphics(actor, def)
  local gfx = tonumber(actor.graphicsId or def.graphicsId or def.graphics)
  if gfx and gfx >= 240 then return nil end
  return gfx
end
-- The player's own sheets on someone else (link partners, the Trainer
-- Tower): not who stands there.
local PLAYER_SHEETS = { RED = true, GREEN = true, RS_BRENDAN = true, RS_MAY = true,
  BRENDAN = true, MAY = true, LINK = true }

local function personLabel(name)
  if GFX_LABELS[name] then return GFX_LABELS[name] end
  -- the rival's sheets: the rival's own name in Hoenn (the game gives it by gender)
  local rival = name:match("^RIVAL_(%u+)_")
  if rival then return Shared.humanize(rival) end
  local base = name:gsub("_WATER$", ""):gsub("_LAND$", ""):gsub("_%d+$", "")
  base = base:gsub("_[MF]$", "")
  if GFX_LABELS[base] then return GFX_LABELS[base] end
  return Shared.humanize(base)
end

-- Graphics that are things, not someone to talk to (decision 35): the object
-- list keeps them, and every other actor is listed under NPCs.
local THING_GRAPHICS = {
  CLIPBOARD = true, CUT_TREE = true, FOSSIL = true, GYM_SIGN = true, ITEM_BALL = true,
  LAPRAS_DOLL = true, METEORITE = true, OLD_AMBER = true, POKEDEX = true,
  PUSHABLE_BOULDER = true, ROCK_SMASH_ROCK = true, RUBY = true, SAPPHIRE = true,
  SEAGALLOP = true, SIGN = true, SS_ANNE = true, TOWN_MAP = true, TRAINER_TIPS = true,
  -- Ruby, Sapphire and Emerald
  BERRY_TREE = true, BERRY_TREE_EARLY_STAGES = true, BERRY_TREE_LATE_STAGES = true,
  BREAKABLE_ROCK = true, CUTTABLE_TREE = true, TRICK_HOUSE_STATUE = true, MOVING_BOX = true,
  TRUCK = true, CABLE_CAR = true, SS_TIDAL = true, MR_BRINEYS_BOAT = true, BIRCHS_BAG = true,
  SUBMARINE_SHADOW = true, DEOXYS_TRIANGLE = true,
}

function Snapshot.isThing(actor)
  local def = type(actor.def) == "table" and actor.def or {}
  local gfx = resolvedGraphics(actor, def)
  local name = gfx and gfxName(gfx)
  if not name then return false end
  name = name:gsub("^OBJ_EVENT_GFX_", "")
  return THING_GRAPHICS[name] == true or name:match("_DOLL$") ~= nil or name:match("_CUSHION$") ~= nil
end

-- The label for a FireRed object from its graphics, or nil.
function Snapshot.objectLabel(actor, opts)
  local def = type(actor.def) == "table" and actor.def or {}
  local gfx = resolvedGraphics(actor, def)
  if gfx == nil then return "Person" end
  if gfx == Terrain.GFX.ITEM_BALL then
    local item = Scripts.itemBallItem(def.scriptKey or actor.scriptKey)
    local label = item and Scripts.itemLabel(item)
    return label or GFX_LABELS.ITEM_BALL, item
  end
  local name = gfxName(gfx)
  if not name then return nil end
  name = name:gsub("^OBJ_EVENT_GFX_", "")
  -- a sheet with its own label first: LINK_RECEPTIONIST is no link partner
  if GFX_LABELS[name] then return GFX_LABELS[name] end
  local sheet = name:match("^(%u+)_") or name
  if PLAYER_SHEETS[name] or PLAYER_SHEETS[sheet] or name:match("^RED_") or name:match("^GREEN_") then
    return "Trainer"
  end
  if name == "BLUE" then
    local rival = opts and opts.rivalName
    return nonempty(rival) and rival or "Rival"
  end
  return personLabel(name)
end

local function projectActor(actor, opts)
  local def = type(actor.def) == "table" and actor.def or {}
  if def.owner or def.runtime == true or nonempty(def.accessibilityLabel) then return actor end
  local label, item = Snapshot.objectLabel(actor, opts)
  if not label then return actor end
  local defCopy = setmetatable({ accessibilityLabel = label, item = item and tostring(item) or nil,
    sprite = false, accessibilityKind = Snapshot.isThing(actor) and "thing" or nil }, { __index = def })
  return setmetatable({ def = defCopy }, { __index = actor })
end

-- ------------------------------------------------------------ warps

local function projectWarps(view, def, opts)
  local warps = {}
  local playerName, rivalName = opts and opts.playerName, opts and opts.rivalName
  for i, warp in ipairs(def.warps or {}) do
    local copy = {}
    for key, value in pairs(warp) do copy[key] = value end
    local active, activeIndex = view:warpAt(tonumber(warp.x), tonumber(warp.y))
    copy.accessibilityBrowsable = active ~= nil and activeIndex == i
    if copy.accessibilityBrowsable then
      local kind, press = view:warpKind(warp.x, warp.y)
      local destMap = view:warpDestination(warp)
      if destMap then
        copy.destMap = destMap
        copy.accessibilityLabel = warp.accessibilityLabel
          or Snapshot.locationName({ id = destMap }, destMap, nil, playerName, rivalName)
      else
        copy.destMap = "LAST_MAP"
        copy.accessibilityLabel = warp.accessibilityLabel or "Exit"
      end
      if kind == "hole" then
        copy.kind = "hole"
        copy.accessibilityLabel = "Drop to " .. tostring(copy.accessibilityLabel)
      end
      copy.warpKind, copy.pressDirection = kind, press
    end
    warps[i] = copy
  end
  return warps
end

local CONNECTION_DIRECTION = { north = "north", south = "south", east = "east", west = "west",
  up = "north", down = "south", left = "west", right = "east" }

local function projectConnections(def, opts)
  local keyed = {}
  local Connections = package.loaded["src.core.game3.connections"]
  local list = {}
  if Connections and type(Connections.each) == "function" then
    local ok, rows = pcall(Connections.each, def)
    if ok and type(rows) == "table" then list = rows end
  end
  if #list == 0 then
    for _, conn in ipairs(type(def.connections) == "table" and def.connections or {}) do
      list[#list + 1] = conn
    end
  end
  for _, conn in ipairs(list) do
    local direction = CONNECTION_DIRECTION[conn.dir or conn.direction]
    if direction and type(conn.map) == "string" and not keyed[direction] then
      keyed[direction] = {
        map = conn.map, offset = tonumber(conn.offset) or 0,
        accessibilityLabel = Shared.humanize(direction) .. " connection to "
          .. Snapshot.locationName({ id = conn.map }, conn.map, nil,
            opts and opts.playerName, opts and opts.rivalName),
      }
    end
  end
  return keyed
end

-- ------------------------------------------------------------ signs

local SIGN_FACING = { [1] = "up", [2] = "down", [3] = "right", [4] = "left" }

-- One object per group of neighbouring sign events that run one script the
-- same way (a two-cell door, a row of bookshelves); the first event names
-- it.  Returns the list the shared browse reads as def.signs.
function Snapshot.projectSigns(view, def, player)
  local listed = {}
  for index, event in ipairs(def.bgEvents or {}) do
    local kind = tonumber(event.kind) or 0
    if event.type == "sign" and (kind == 0 or SIGN_FACING[kind])
       and type(event.x) == "number" and type(event.y) == "number"
       and not (GameData.isHoenn() and view and not view:inBounds(event.x, event.y)) then
      listed[#listed + 1] = { index = index, event = event, kind = kind }
    end
  end
  local grouped, signs = {}, {}
  for i, first in ipairs(listed) do
    if not grouped[i] then
      grouped[i] = true
      local members, head = { first }, 1
      local key = first.event.scriptKey
      local firstRole = key and Scripts.signRole(key)
      while key ~= nil and head <= #members do
        local current = members[head]
        head = head + 1
        for j, other in ipairs(listed) do
          local near = math.abs(other.event.x - current.event.x)
            + math.abs(other.event.y - current.event.y) == 1
          local sameScript = other.event.scriptKey == key
          -- one elevator panel, wherever its signs stand (Celadon's car has a second,
          -- on a wall no one can stand below); the two cells of one quiz machine, each
          -- with its own script
          local together = (sameScript and (near or firstRole == "Floor Panel"))
            or (near and firstRole == "Quiz Machine" and Scripts.signRole(other.event.scriptKey) == firstRole)
          if not grouped[j] and together and other.kind == first.kind then
            grouped[j] = true
            members[#members + 1] = other
          end
        end
      end
      local cells, furniture = {}, nil
      for _, member in ipairs(members) do
        cells[#cells + 1] = { x = member.event.x, y = member.event.y }
        if not furniture and view then
          local row = Terrain.FURNITURE[view:behavior(member.event.x, member.event.y)]
          furniture = row and row.label or nil
        end
      end
      local role, roleKind = Scripts.signRole(key)
      local skip = false
      if roleKind == "card_key_door" and view then
        -- an opened door is floor: nothing left to find there
        skip = true
        for _, cell in ipairs(cells) do
          if not view:isWalkableCell(cell.x, cell.y) then skip = false break end
        end
      end
      if not skip then
        local nearest, best = cells[1], math.huge
        if type(player) == "table" and type(player.cellX) == "number" then
          for _, cell in ipairs(cells) do
            local distance = math.abs(cell.x - player.cellX) + math.abs(cell.y - player.cellY)
            if distance < best then nearest, best = cell, distance end
          end
        end
        local event = first.event
        local okWords, signWords = pcall(Scripts.signWords, key)
        signWords = okWords and signWords or nil
        signs[#signs + 1] = {
          x = nearest.x, y = nearest.y,
          accessibilityLabel = event.accessibilityLabel or role or furniture
            or (signWords and ("Sign: " .. signWords)) or ("Signpost " .. first.index),
          accessibilityId = event.accessibilityId
            or ("bg_event:" .. tostring(def.id) .. ":" .. first.index),
          requiredFacing = SIGN_FACING[first.kind],
          cells = cells, roleKind = roleKind,
          interactionCells = #cells > 1 and cells or nil,
        }
      end
    end
  end
  return signs
end

-- ------------------------------------------------------------ proxies

local function mapProxy(view, world, opts)
  local def = type(view.def) == "table" and view.def or {}
  local projected = { id = view.id, accessibilityLabel = def.accessibilityLabel }
  projected.warps = projectWarps(view, def, opts)
  projected.connections = projectConnections(def, opts)
  projected.signs = Snapshot.projectSigns(view, def, world.player)
  return setmetatable({ def = projected, id = view.id }, { __index = view })
end
Snapshot.mapProxy = mapProxy

local function worldProxy(world, opts)
  local projected = { map = mapProxy(world.map, world, opts) }
  local list = {}
  for _, actor in ipairs(world.npcs or {}) do
    -- a tree or a rock placed past the map's edge shows from the map next door: a
    -- thing to see there, nothing to walk to here
    if type(actor) == "table" and not actor.invisible
       and world.map:inBounds(actor.cellX, actor.cellY) then
      list[#list + 1] = projectActor(actor, opts)
    end
  end
  projected.npcs = list
  local entities = { world.player }
  for _, actor in ipairs(list) do entities[#entities + 1] = actor end
  projected.entities = entities
  return setmetatable(projected, { __index = world })
end
Snapshot.worldProxy = worldProxy

local function gen3Options(opts)
  local copy = {}
  for key, value in pairs(opts or {}) do copy[key] = value end
  copy.generation = 3
  return copy
end

-- The shared browse asks locationName with Gen 1's argument order; Gen 3
-- names come from here, so the shared calls are routed through the
-- projected labels (every warp and connection carries accessibilityLabel).
function Snapshot.browse(world, opts)
  return Shared.browse(worldProxy(world, opts), gen3Options(opts))
end

function Snapshot.capture(world, opts)
  local snapshot, err = Shared.capture(worldProxy(world, opts), gen3Options(opts))
  if snapshot then
    local names = type(opts.customNames) == "table" and opts.customNames or {}
    local mapNames = type(names.maps) == "table" and names.maps or {}
    snapshot.locationName = Snapshot.locationName(world.map, snapshot.mapId,
      mapNames[snapshot.mapId], opts.playerName, opts.rivalName)
  end
  return snapshot, err
end

return Snapshot
