local T = require("tests.harness")
local S = T.suite("accessibility generated-world journey")
local WorldSnapshot = require("src.access.nav.WorldSnapshot")
local Map = require("src.world.Map")
local maps = require("data.generated.maps")
local tilesets = require("data.generated.tilesets")

local function snapshot(mapId)
  local def = assert(maps[mapId], "missing generated map " .. mapId)
  local live = Map.new(def, assert(tilesets[def.tileset]))
  return assert(WorldSnapshot.capture({
    map = live,
    player = { cellX = 0, cellY = 0 },
    entities = {},
    maps = maps,
  }))
end

local function transition(mapId, destinationMapId, kind)
  local result = snapshot(mapId)
  for _, item in ipairs(result.browse) do
    if item.type == kind and item.destinationMapId == destinationMapId then
      return item, result
    end
  end
  return nil, result
end

-- This is an ordered semantic journey over the generated Red world, beyond
-- the live visual autopilot's Viridian endpoint.  It catches missing or raw-ID
-- navigation output at each transition a blind player needs on the way through
-- Viridian Forest and into the first Gym.
local itinerary = {
  { "PALLET_TOWN", "ROUTE_1", "connection", "North connection to Route 1" },
  { "ROUTE_1", "VIRIDIAN_CITY", "connection", "North connection to Viridian City" },
  { "VIRIDIAN_CITY", "ROUTE_2", "connection", "North connection to Route 2" },
  { "ROUTE_2", "VIRIDIAN_FOREST_SOUTH_GATE", "warp", "Viridian Forest South Gate" },
  { "VIRIDIAN_FOREST_SOUTH_GATE", "VIRIDIAN_FOREST", "warp", "Viridian Forest" },
  { "VIRIDIAN_FOREST", "VIRIDIAN_FOREST_NORTH_GATE", "warp", "Viridian Forest North Gate" },
  { "ROUTE_2", "PEWTER_CITY", "connection", "North connection to Pewter City" },
  { "PEWTER_CITY", "PEWTER_GYM", "warp", "Pewter Gym" },
}

local spoken = {}
for index, step in ipairs(itinerary) do
  local item = transition(step[1], step[2], step[3])
  S.check(item ~= nil, ("journey transition %d exists in generated Red data"):format(index))
  S.check(item and item.description:find(step[4], 1, true) ~= nil,
    ("journey transition %d has player-facing destination speech"):format(index))
  spoken[#spoken + 1] = item and item.description or "missing"
end

local first = table.concat(spoken, " | ")
local repeated = {}
for _, step in ipairs(itinerary) do
  local item = transition(step[1], step[2], step[3])
  repeated[#repeated + 1] = item and item.description or "missing"
end
S.eq(table.concat(repeated, " | "), first,
  "generated-world journey narration is deterministic across captures")
S.check(first:find("PALLET_TOWN", 1, true) == nil
    and first:find("PEWTER_GYM", 1, true) == nil,
  "journey narration does not leak internal map identifiers")

local celadonMain, celadon = transition(
  "CELADON_CITY", "CELADON_MART_1F", "warp")
local celadonFifth = transition(
  "CELADON_CITY", "CELADON_MART_5F", "warp")
S.eq(celadonMain and celadonMain.label,
  "Celadon Department Store main entrance",
  "Celadon exposes its ground-floor double door as the main store entrance")
S.eq(celadonMain and #celadonMain.navigationCells, 2,
  "the Department Store main entrance retains both physical doors")
-- The generated map includes a fifth-floor warp record at (39,19), but its
-- collision tile is not a door/warp tile and no vanilla carpet-facing check
-- activates it. Browsing must not advertise that dead exterior shortcut.
local hasFifthRecord = false
for _, warp in ipairs(maps.CELADON_CITY.warps) do
  if warp.destMap == "CELADON_MART_5F" then hasFifthRecord = true end
end
S.check(hasFifthRecord, "the generated Red map retains the raw fifth-floor record")
S.eq(celadonFifth, nil,
  "the inactive fifth-floor exterior warp is not a navigation destination")
S.check(celadon.browse[1] == celadonMain,
  "the active main entrance remains the first Celadon destination")
for _, floor in ipairs({
  { "CELADON_MART_1F", "CELADON_MART_2F" },
  { "CELADON_MART_2F", "CELADON_MART_3F" },
  { "CELADON_MART_3F", "CELADON_MART_4F" },
  { "CELADON_MART_4F", "CELADON_MART_5F" },
}) do
  S.check(transition(floor[1], floor[2], "warp") ~= nil,
    floor[1] .. " has an active interior route to " .. floor[2])
end

S.finish()
