-- Reused from the old Pocket Accessibility project
-- (src/accessibility/gen2/WorldSnapshot.lua at commit 71cdd419e, upstream
-- v0.3.32) under decision 20; adapted for v0.3.98.  Read-only.

-- Gold, Silver and Crystal projected into the shared object-list vocabulary
-- (../WorldSnapshot.lua).  The live map, NPCs and definitions are never
-- changed: the projection copies what it relabels.
--
-- What the projection supplies that the shared module cannot read from a
-- Gen 2 map:
--   * signs from `bgEvents`, named "Signpost N" by the event's own ordinal
--     (Pokemon Access's naming).  A sign's script key is a ROM address
--     ("1e:6c15") and is never spoken.  Facing-only signs carry their
--     facing; if-set and if-not-set signs are listed only while the game
--     would read them.  Hidden items are not listed, as in Gen 1, which lists
--     no hidden items either.
--   * pit warps marked as holes (COLL_PIT 0x60 / 0x68 under the warp).
--   * the "return where you came from" warp (destination warp 0xFF) resolved
--     through the world's backup warp, as World:resolveWarp does; before the
--     game has recorded one the warp is named "Exit" rather than given the
--     map it names, which is the room itself.
--   * item balls named by their item (Gen 1 names item balls by item too),
--     variable sprites by the sheet the game resolved, and Kanto's Red's Mom.

local Shared = require("src.access.nav.WorldSnapshot")

local Snapshot = {}
for key, value in pairs(Shared) do Snapshot[key] = value end

local function gen2Options(opts)
  local copy = {}
  for key, value in pairs(opts or {}) do copy[key] = value end
  copy.generation = 2
  return copy
end

function Snapshot.locationName(mapOrDef, fallbackId, customName, playerName)
  return Shared.locationName(mapOrDef, fallbackId, customName, playerName, 2)
end

local PIT = { [0x60] = true, [0x68] = true }
local SIGN_FACING = { [1] = "up", [2] = "down", [3] = "right", [4] = "left" }

-- What a sign is, from the standard script it runs: the `std` name the
-- extractor keeps on jumpstd and callstd (engine/events/std_scripts.asm), or
-- the `special` it calls (constants.specialOrder).  Only roles that name the
-- object itself; the rest stay "Signpost N".
local STD_SIGN_LABELS = {
  MagazineBookshelfScript = "Bookshelf", PictureBookshelfScript = "Bookshelf",
  DifficultBookshelfScript = "Bookshelf", TrashCanScript = "Trash Can",
  PokecenterSignScript = "Pok\195\169mon Center Sign", MartSignScript = "Mart Sign",
  GymStatue1Script = "Gym Statue", GymStatue2Script = "Gym Statue",
  ElevatorButtonScript = "Elevator Button", Radio1Script = "Radio", Radio2Script = "Radio",
  TeamRocketOathScript = "Team Rocket Oath",
}
local SPECIAL_SIGN_LABELS = {
  SlotMachine = "Slot Machine", CardFlip = "Card Flip", UnownPuzzle = "Unown Puzzle",
  DisplayUnownWords = "Unown Words", MapRadio = "Radio", PlayersHousePC = "PC",
  UnownPrinter = "Unown Printer",
}
-- Script commands whose `script` field is where the sign's script may go on.
local SCRIPT_BRANCHES = {
  iftrue = true, iffalse = true, ifequal = true, ifnotequal = true, ifgreater = true,
  ifless = true, sjump = true, scall = true, farsjump = true, farscall = true,
}

-- The role a sign's script names, read from the extracted scripts (never
-- run): the script itself and the branches it can take, two levels deep.  The
-- elevator car's panel (the `elevator` command) is the "Floor Panel" (Gen 1: "Floor panel").
local function signRole(world, key)
  local scripts = type(world) == "table" and world.scripts or nil
  if type(scripts) ~= "table" or type(key) ~= "string" then return nil end
  local constants = world.constants
  local specials = type(constants) == "table" and constants.specialOrder or nil
  local seen = {}
  local function walk(scriptKey, depth)
    if depth > 2 or type(scriptKey) ~= "string" or seen[scriptKey] then return nil end
    seen[scriptKey] = true
    local list = scripts[scriptKey]
    if type(list) ~= "table" then return nil end
    for _, cmd in ipairs(list) do
      if type(cmd) == "table" then
        if (cmd.op == "jumpstd" or cmd.op == "callstd") and STD_SIGN_LABELS[cmd.std] then
          return STD_SIGN_LABELS[cmd.std]
        elseif cmd.op == "special" and type(specials) == "table" and type(cmd.id) == "number"
            and SPECIAL_SIGN_LABELS[specials[cmd.id + 1]] then
          return SPECIAL_SIGN_LABELS[specials[cmd.id + 1]]
        elseif cmd.op == "elevator" then
          return "Floor Panel"
        elseif SCRIPT_BRANCHES[cmd.op] then
          local found = walk(cmd.script, depth + 1)
          if found then return found end
        end
      end
    end
    return nil
  end
  return walk(key, 0)
end

-- World:bgEventAt's flag test for kinds 5 (if set) and 6 (if not set), read
-- without running anything.  An event with no flag is not guessed at.
local function conditionalActive(event, world)
  local events = type(world) == "table" and world.events or nil
  if not (event.event and events and type(events.get) == "function") then return false end
  local ok, set = pcall(events.get, events, event.event)
  if not ok then return false end
  return (event.kind == 5) == (set and true or false)
end

-- A bg event standing on a bookshelf, TV or other standard tile is that
-- object (the A press runs the event instead of the tile's own script), so it
-- takes the tile's name; one whose script runs a standard script that names
-- it (a trash can, a gym statue, a slot machine) takes that name; any other
-- is "Signpost N".
--
-- Neighbouring events that run the same script the same way are one object,
-- as neighbouring cells of one standard tile are: a two-cell bookshelf, a row
-- of slot machines, the twenty cells of the Rocket base's transmitter.  The
-- first event names it ("Signpost N" keeps N) and every cell can be faced.
local function projectSigns(def, world, map)
  local Terrain = require("src.access.nav.gen2.TerrainSemantics")
  local listedEvents = {}
  for index, event in ipairs(def.bgEvents or {}) do
    local kind = event.kind or 0
    local listed = kind == 0 or SIGN_FACING[kind] ~= nil
      or ((kind == 5 or kind == 6) and conditionalActive(event, world))
    if listed and type(event.x) == "number" and type(event.y) == "number" then
      listedEvents[#listedEvents + 1] = { index = index, event = event, kind = kind }
    end
  end
  local grouped, signs = {}, {}
  local player = type(world) == "table" and world.player or nil
  for i, first in ipairs(listedEvents) do
    if not grouped[i] then
      grouped[i] = true
      local members, head = { first }, 1
      local key = first.event.scriptKey
      while key ~= nil and head <= #members do
        local current = members[head]
        head = head + 1
        for j, other in ipairs(listedEvents) do
          if not grouped[j] and other.event.scriptKey == key and other.kind == first.kind
             and math.abs(other.event.x - current.event.x)
               + math.abs(other.event.y - current.event.y) == 1 then
            grouped[j] = true
            members[#members + 1] = other
          end
        end
      end
      local cells, tile = {}, nil
      for _, member in ipairs(members) do
        cells[#cells + 1] = { x = member.event.x, y = member.event.y }
        if not tile and type(map) == "table" and type(map.cellCollision) == "function" then
          local ok, coll = pcall(map.cellCollision, map, member.event.x, member.event.y)
          tile = ok and Terrain.STD_TILES[coll] or nil
        end
      end
      local nearest, best = cells[1], math.huge
      if type(player) == "table" and type(player.cellX) == "number" and type(player.cellY) == "number" then
        for _, cell in ipairs(cells) do
          local distance = math.abs(cell.x - player.cellX) + math.abs(cell.y - player.cellY)
          if distance < best then nearest, best = cell, distance end
        end
      end
      local event = first.event
      signs[#signs + 1] = {
        x = nearest.x, y = nearest.y,
        name = event.accessibilityLabel or tile or signRole(world, key)
          or ("Signpost " .. first.index),
        accessibilityId = event.accessibilityId
          or ("bg_event:" .. tostring(def.id) .. ":" .. first.index),
        requiredFacing = SIGN_FACING[first.kind],
        cells = cells,
        interactionCells = #cells > 1 and cells or nil,
      }
    end
  end
  return signs
end

-- The warp's real destination when it is the 0xFF "go back" warp, or nil
-- when the game has not recorded where back is yet.
local function returnWarpDestination(world, warp)
  local backup = type(world) == "table" and world.backupWarp or nil
  local maps = type(world) == "table" and world.maps or nil
  if type(backup) == "table" and type(backup.map) == "string"
     and type(maps) == "table" and maps[backup.map] then
    return backup.map, backup.warp
  end
  return nil
end

local function projectWarps(map, def, world, holes)
  local warps = {}
  for i, warp in ipairs(def.warps or {}) do
    local marked
    local function copy()
      if marked then return marked end
      marked = {}
      for key, value in pairs(warp) do marked[key] = value end
      return marked
    end
    local ok, coll = pcall(map.cellCollision, map, warp.x, warp.y)
    if ok and PIT[coll] and warp.kind == nil then copy().kind = "hole" end
    -- a stone-table hole is its own object, named by its table row, with the
    -- puzzle's state (gen2/PuzzleAssistance.lua)
    local hole = type(holes) == "table"
      and holes[tostring(warp.x) .. "," .. tostring(warp.y)] or nil
    if hole and ok and PIT[coll] then
      copy().accessibilityTargetId = "stone_hole:" .. tostring(def.id) .. ":" .. i
      marked.accessibilityLabel = warp.accessibilityLabel or hole.label
      marked.accessibilityStateText = hole.state
    end
    if warp.destWarp == 0xff then
      local destMap, destWarp = returnWarpDestination(world, warp)
      if destMap then
        copy()
        marked.destMap, marked.destWarp = destMap, destWarp
      else
        copy().accessibilityLabel = warp.accessibilityLabel or "Exit"
        marked.unresolvedReturn = true
      end
    end
    warps[i] = marked or warp
  end
  return warps
end

local function mapProxy(map, world, opts)
  local def = type(map.def) == "table" and map.def or {}
  local projected = {}
  for key, value in pairs(def) do projected[key] = value end
  if type(map.cellCollision) == "function" then
    projected.warps = projectWarps(map, def, world, opts and opts.holeTargets)
  end
  projected.signs = projectSigns(def, world, map)
  return setmetatable({
    def = projected,
    -- a deliberate native projection: the COLL byte, never a Gen 1 tile id
    cellTile = function(_, x, y) return map:cellCollision(x, y) end,
  }, { __index = map })
end

local function nonempty(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

local function hasAuthoredLabel(record)
  if type(record) ~= "table" then return false end
  local a11y = record.accessibility
  return nonempty(record.accessibilityLabel) or nonempty(record.displayName)
    or nonempty(record.label) or (type(a11y) == "table"
      and (nonempty(a11y.label) or nonempty(a11y.role)))
end

-- The item an item ball holds: Gen 2 stores the item's index, so it is looked
-- up the way the game does (World:itemIdByIndex), never spoken as a number.
local function itemBallItem(world, def)
  local ball = type(def.itemball) == "table" and def.itemball or nil
  if not ball or ball.item == nil then return nil end
  if type(ball.item) == "string" then return ball.item end
  local native = type(world) == "table" and (world.native or world) or nil
  if native and type(native.itemIdByIndex) == "function" then
    local ok, id = pcall(native.itemIdByIndex, native, ball.item)
    if ok and type(id) == "string" then return id end
  end
  return nil
end

-- Person sheets whose name is not who stands there: the player's own sheet
-- (reused for link partners and the Trainer House trainer; "Chris" is not a
-- character in Gold and Silver at all), and pose or size variants.
local SHEET_LABELS = {
  SPRITE_CHRIS = "Trainer", SPRITE_STANDING_YOUNGSTER = "Youngster",
  SPRITE_KURT_OUTSIDE = "Kurt", SPRITE_BIG_SNORLAX = "Snorlax",
  SPRITE_BIG_LAPRAS = "Lapras", SPRITE_BIG_ONIX = "Onix",
  SPRITE_SURF = "Pok\195\169mon",
}
-- Pokemon drawn with a shape sheet that names no species.
local SHAPE_SHEETS = {
  SPRITE_MONSTER = true, SPRITE_FAIRY = true, SPRITE_BIRD = true,
  SPRITE_DRAGON = true, SPRITE_SURF = true,
}

-- "FARFETCH'D" as "Farfetch'd", "MR.MIME" as "Mr. Mime", "HO-OH" as "Ho-Oh".
local function speciesLabel(name)
  local text = tostring(name):lower()
  text = text:gsub("^%l", string.upper):gsub("([%s%-%.])(%l)", function(gap, letter)
    return gap .. letter:upper()
  end)
  return (text:gsub("%.(%a)", ". %1"))
end

-- The species an object's own script cries (`cry` with a species index),
-- read from the extracted scripts and never run; the script and the
-- branches it can take, two levels deep.
local function criedSpecies(world, def, opts)
  local scripts = type(world) == "table" and world.scripts or nil
  local constants = type(world) == "table" and world.constants or nil
  local order = type(constants) == "table" and constants.speciesOrder or nil
  if type(scripts) ~= "table" or type(order) ~= "table" or type(def.scriptKey) ~= "string" then
    return nil
  end
  local seen = {}
  local function walk(key, depth)
    if depth > 2 or type(key) ~= "string" or seen[key] then return nil end
    seen[key] = true
    for _, cmd in ipairs(type(scripts[key]) == "table" and scripts[key] or {}) do
      if type(cmd) == "table" then
        if cmd.op == "cry" and type(cmd.id) == "number" and order[cmd.id] then
          return order[cmd.id]
        elseif SCRIPT_BRANCHES[cmd.op] then
          local found = walk(cmd.script, depth + 1)
          if found then return found end
        end
      end
    end
    return nil
  end
  local id = walk(def.scriptKey, 0)
  if not id then return nil end
  local pokemon = type(opts) == "table" and opts.pokemon or nil
  local record = type(pokemon) == "table" and pokemon[id] or nil
  if type(record) == "table" and nonempty(record.name) then return speciesLabel(record.name) end
  return Shared.humanize(id)
end

-- The label for an object drawn with a Pokemon sheet.  The cartridge reuses
-- its 35 species sheets (ROM SpriteMons) for other species -- GROWLITHE's for
-- a MEOWTH, MOLTRES's for a FARFETCH'D, TAUROS's for every MILTANK -- and a
-- few shape sheets (MONSTER, BIRD) name no species at all, so the sheet's
-- name is a wrong but plausible label.  The species the object's script
-- cries is the one the game means; with no cry, a species sheet says only
-- "Pokemon", and a shape sheet keeps its shape.
local function pokemonLabel(world, actor, def, opts)
  local sheet = type(actor.spriteDef) == "table" and actor.spriteDef or nil
  local sheetId = sheet and sheet.id or def.sprite
  local speciesSheet = sheet and type(sheet.source) == "string"
    and sheet.source:find("SpriteMons", 1, true) ~= nil
  if not (speciesSheet or SHAPE_SHEETS[sheetId]) then return nil end
  local species = criedSpecies(world, def, opts)
  if species then return species end
  if speciesSheet then return "Pok\195\169mon" end
  return nil
end

local function projectActor(world, actor, opts)
  local def = actor.def
  if type(def) ~= "table" or def.owner or def.runtime == true
     or hasAuthoredLabel(actor) or hasAuthoredLabel(def) then
    return actor
  end
  local relabel = {}
  local item = def.item == nil and itemBallItem(world, def) or nil
  if item then relabel.item = item end
  -- A sprite slot number (variable sprites, decorations) names the sheet the
  -- game resolved for it.
  if type(def.sprite) ~= "string" then
    local sheet = type(actor.spriteDef) == "table" and actor.spriteDef.id or nil
    if type(sheet) == "string" then relabel.sprite = sheet end
  end
  local sheetId = relabel.sprite or def.sprite
  -- The bedroom's decorations are variable sprites on a doll or console sheet
  -- that can also be a real Pokemon elsewhere (decision 35).
  local mapId = type(world) == "table" and type(world.map) == "table" and world.map.id
  if type(def.sprite) ~= "string" and type(mapId) == "string" and mapId:find("PLAYERS_HOUSE_2F", 1, true) then
    relabel.accessibilityKind = "thing"
  end
  -- The Kanto character Pokemon Access calls "[red]'s Mom"; the player's own
  -- SPRITE_MOM follows the saved Mom name in the shared module instead.
  if sheetId == "SPRITE_REDS_MOM" then
    relabel.accessibilityLabel = "Red's Mom"
  elseif not item then
    relabel.accessibilityLabel = pokemonLabel(world, actor, def, opts) or SHEET_LABELS[sheetId]
  end
  if next(relabel) == nil then return actor end
  local defCopy = setmetatable(relabel, { __index = def })
  return setmetatable({ def = defCopy }, { __index = actor })
end

local function worldProxy(world, opts)
  local projected = { map = mapProxy(world.map, world, opts) }
  local actors = {}
  local function project(actor)
    if actor == world.player or type(actor) ~= "table" then return actor end
    if not actors[actor] then actors[actor] = projectActor(world, actor, opts) end
    return actors[actor]
  end
  for _, field in ipairs({ "npcs", "entities" }) do
    if type(world[field]) == "table" then
      local list = {}
      for i, actor in ipairs(world[field]) do list[i] = project(actor) end
      projected[field] = list
    end
  end
  return setmetatable(projected, { __index = world })
end

function Snapshot.browse(world, opts)
  return Shared.browse(worldProxy(world, opts), gen2Options(opts))
end

function Snapshot.capture(world, opts)
  return Shared.capture(worldProxy(world, opts), gen2Options(opts))
end

-- Exposed for the coordinator (cross-map labels) and tests.
Snapshot.projectWarps = projectWarps
Snapshot.projectSigns = projectSigns
Snapshot.returnWarpDestination = returnWarpDestination

return Snapshot
