-- luajit launcher/mods/crystal_randomizer/tests/maprules_test.lua   (from the repository root)
--
-- 1. A hand-built graph of Johto's doors in the shape MAPS.md gives (real map
--    names and warp numbers, from the cart's maps): the vanilla placement is
--    winnable, obviously stranding placements are refused with a reason,
--    harmless ones are accepted, fixed complexes are listed with reasons and
--    may not move, and placement.entrances is read like per-door placements.
-- 2. The HM shuffle: with vanilla doors, canWin accepts exactly the HM
--    placements keyitems.lua accepts, on all 5040.
-- 3. With CRYSTAL_RANDOMIZER_CACHE set to an imported cache's data/generated
--    folder, the real graph from mapgraph.lua: vanilla is winnable, every
--    story step is located, the timing of one call, and random swaps of
--    dead-end entrances.
local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local R = dofile("launcher/mods/crystal_randomizer/modules/maprules.lua")
local K = dofile("launcher/mods/crystal_randomizer/modules/keyitems.lua")

local failures, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
  return cond
end
local function eq(a, b, msg) return ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

-- ------------------------------------------------------------ the hand graph
-- { complex id, environment, maps, outdoor doors }.  Door "MAP:n" is warp n
-- of that outdoor map (data.gen2Maps[MAP].warps[n]).
local SPEC = {
  { "ELMS_LAB", "INDOOR", { "ELMS_LAB" }, { "NEW_BARK_TOWN:1" } },
  { "PLAYERS_HOUSE_1F", "INDOOR", { "PLAYERS_HOUSE_1F", "PLAYERS_HOUSE_2F" }, { "NEW_BARK_TOWN:2" } },
  { "PLAYERS_NEIGHBORS_HOUSE", "INDOOR", { "PLAYERS_NEIGHBORS_HOUSE" }, { "NEW_BARK_TOWN:3" } },
  { "ELMS_HOUSE", "INDOOR", { "ELMS_HOUSE" }, { "NEW_BARK_TOWN:4" } },
  { "CHERRYGROVE_MART", "INDOOR", { "CHERRYGROVE_MART" }, { "CHERRYGROVE_CITY:1" } },
  { "CHERRYGROVE_POKECENTER_1F", "INDOOR", { "CHERRYGROVE_POKECENTER_1F" }, { "CHERRYGROVE_CITY:2" } },
  { "GUIDE_GENTS_HOUSE", "INDOOR", { "GUIDE_GENTS_HOUSE" }, { "CHERRYGROVE_CITY:4" } },
  { "ROUTE_29_ROUTE_46_GATE", "GATE", { "ROUTE_29_ROUTE_46_GATE" }, { "ROUTE_29:1", "ROUTE_46:1", "ROUTE_46:2" } },
  { "ROUTE_30_BERRY_HOUSE", "INDOOR", { "ROUTE_30_BERRY_HOUSE" }, { "ROUTE_30:1" } },
  { "MR_POKEMONS_HOUSE", "INDOOR", { "MR_POKEMONS_HOUSE" }, { "ROUTE_30:2" } },
  { "ROUTE_31_VIOLET_GATE", "GATE", { "ROUTE_31_VIOLET_GATE" },
    { "ROUTE_31:1", "ROUTE_31:2", "VIOLET_CITY:8", "VIOLET_CITY:9" } },
  { "DARK_CAVE_BLACKTHORN_ENTRANCE", "CAVE", { "DARK_CAVE_BLACKTHORN_ENTRANCE", "DARK_CAVE_VIOLET_ENTRANCE" },
    { "ROUTE_31:3", "ROUTE_45:1", "ROUTE_46:3" } },
  { "VIOLET_MART", "INDOOR", { "VIOLET_MART" }, { "VIOLET_CITY:1" } },
  { "VIOLET_GYM", "INDOOR", { "VIOLET_GYM" }, { "VIOLET_CITY:2" } },
  { "EARLS_POKEMON_ACADEMY", "INDOOR", { "EARLS_POKEMON_ACADEMY" }, { "VIOLET_CITY:3" } },
  { "VIOLET_POKECENTER_1F", "INDOOR", { "VIOLET_POKECENTER_1F" }, { "VIOLET_CITY:5" } },
  { "SPROUT_TOWER_1F", "DUNGEON", { "SPROUT_TOWER_1F", "SPROUT_TOWER_2F", "SPROUT_TOWER_3F" }, { "VIOLET_CITY:7" } },
  { "ROUTE_32_POKECENTER_1F", "INDOOR", { "ROUTE_32_POKECENTER_1F" }, { "ROUTE_32:1" } },
  { "ROUTE_32_RUINS_OF_ALPH_GATE", "GATE", { "ROUTE_32_RUINS_OF_ALPH_GATE" },
    { "ROUTE_32:2", "ROUTE_32:3", "RUINS_OF_ALPH_OUTSIDE:10", "RUINS_OF_ALPH_OUTSIDE:11" } },
  { "UNION_CAVE_1F", "CAVE", { "UNION_CAVE_1F", "UNION_CAVE_B1F", "UNION_CAVE_B2F" },
    { "ROUTE_32:4", "ROUTE_33:1", "RUINS_OF_ALPH_OUTSIDE:7", "RUINS_OF_ALPH_OUTSIDE:8" } },
  { "RUINS_OF_ALPH_AERODACTYL_CHAMBER", "DUNGEON", { "RUINS_OF_ALPH_AERODACTYL_CHAMBER",
      "RUINS_OF_ALPH_HO_OH_CHAMBER", "RUINS_OF_ALPH_INNER_CHAMBER", "RUINS_OF_ALPH_KABUTO_CHAMBER",
      "RUINS_OF_ALPH_OMANYTE_CHAMBER" },
    { "RUINS_OF_ALPH_OUTSIDE:1", "RUINS_OF_ALPH_OUTSIDE:2", "RUINS_OF_ALPH_OUTSIDE:3",
      "RUINS_OF_ALPH_OUTSIDE:4", "RUINS_OF_ALPH_OUTSIDE:5" } },
  { "RUINS_OF_ALPH_RESEARCH_CENTER", "INDOOR", { "RUINS_OF_ALPH_RESEARCH_CENTER" }, { "RUINS_OF_ALPH_OUTSIDE:6" } },
  { "ROUTE_36_RUINS_OF_ALPH_GATE", "GATE", { "ROUTE_36_RUINS_OF_ALPH_GATE" },
    { "ROUTE_36:3", "ROUTE_36:4", "RUINS_OF_ALPH_OUTSIDE:9" } },
  { "ROUTE_36_NATIONAL_PARK_GATE", "INDOOR", { "ROUTE_36_NATIONAL_PARK_GATE" },
    { "ROUTE_36:1", "ROUTE_36:2", "NATIONAL_PARK:1", "NATIONAL_PARK:2" } },
  { "ROUTE_35_NATIONAL_PARK_GATE", "INDOOR", { "ROUTE_35_NATIONAL_PARK_GATE" },
    { "ROUTE_35:3", "NATIONAL_PARK:3", "NATIONAL_PARK:4" } },
  { "ROUTE_35_GOLDENROD_GATE", "GATE", { "ROUTE_35_GOLDENROD_GATE" },
    { "GOLDENROD_CITY:12", "ROUTE_35:1", "ROUTE_35:2" } },
  { "AZALEA_POKECENTER_1F", "INDOOR", { "AZALEA_POKECENTER_1F" }, { "AZALEA_TOWN:1" } },
  { "CHARCOAL_KILN", "INDOOR", { "CHARCOAL_KILN" }, { "AZALEA_TOWN:2" } },
  { "AZALEA_MART", "INDOOR", { "AZALEA_MART" }, { "AZALEA_TOWN:3" } },
  { "KURTS_HOUSE", "INDOOR", { "KURTS_HOUSE" }, { "AZALEA_TOWN:4" } },
  { "AZALEA_GYM", "INDOOR", { "AZALEA_GYM" }, { "AZALEA_TOWN:5" } },
  { "SLOWPOKE_WELL_B1F", "CAVE", { "SLOWPOKE_WELL_B1F", "SLOWPOKE_WELL_B2F" }, { "AZALEA_TOWN:6" } },
  { "ILEX_FOREST_AZALEA_GATE", "CAVE", { "ILEX_FOREST", "ILEX_FOREST_AZALEA_GATE", "ROUTE_34_ILEX_FOREST_GATE" },
    { "AZALEA_TOWN:7", "AZALEA_TOWN:8", "ROUTE_34:1", "ROUTE_34:2" } },
  { "DAY_CARE", "INDOOR", { "DAY_CARE" }, { "ROUTE_34:3", "ROUTE_34:4", "ROUTE_34:5" } },
  { "GOLDENROD_GYM", "INDOOR", { "GOLDENROD_GYM" }, { "GOLDENROD_CITY:1" } },
  { "GOLDENROD_BIKE_SHOP", "INDOOR", { "GOLDENROD_BIKE_SHOP" }, { "GOLDENROD_CITY:2" } },
  { "BILLS_FAMILYS_HOUSE", "INDOOR", { "BILLS_FAMILYS_HOUSE" }, { "GOLDENROD_CITY:4" } },
  { "GOLDENROD_MAGNET_TRAIN_STATION", "INDOOR", { "GOLDENROD_MAGNET_TRAIN_STATION", "SAFFRON_MAGNET_TRAIN_STATION" },
    { "GOLDENROD_CITY:5" } },
  { "GOLDENROD_FLOWER_SHOP", "INDOOR", { "GOLDENROD_FLOWER_SHOP" }, { "GOLDENROD_CITY:6" } },
  { "GOLDENROD_DEPT_STORE_1F", "INDOOR", { "GOLDENROD_DEPT_STORE_1F", "GOLDENROD_DEPT_STORE_B1F",
      "GOLDENROD_UNDERGROUND", "GOLDENROD_UNDERGROUND_SWITCH_ROOM_ENTRANCES", "GOLDENROD_UNDERGROUND_WAREHOUSE" },
    { "GOLDENROD_CITY:9", "GOLDENROD_CITY:13", "GOLDENROD_CITY:14" } },
  { "GOLDENROD_GAME_CORNER", "INDOOR", { "GOLDENROD_GAME_CORNER" }, { "GOLDENROD_CITY:10" } },
  { "RADIO_TOWER_1F", "INDOOR", { "RADIO_TOWER_1F", "RADIO_TOWER_2F", "RADIO_TOWER_3F", "RADIO_TOWER_4F",
      "RADIO_TOWER_5F" }, { "GOLDENROD_CITY:11" } },
  { "GOLDENROD_POKECENTER_1F", "INDOOR", { "GOLDENROD_POKECENTER_1F" }, { "GOLDENROD_CITY:15" } },
  { "ROUTE_42_ECRUTEAK_GATE", "GATE", { "ROUTE_42_ECRUTEAK_GATE" },
    { "ECRUTEAK_CITY:1", "ECRUTEAK_CITY:2", "ROUTE_42:1", "ROUTE_42:2" } },
  { "ECRUTEAK_TIN_TOWER_ENTRANCE", "INDOOR", { "ECRUTEAK_TIN_TOWER_ENTRANCE", "WISE_TRIOS_ROOM" },
    { "ECRUTEAK_CITY:3", "ECRUTEAK_CITY:4", "ECRUTEAK_CITY:5" } },
  { "ECRUTEAK_POKECENTER_1F", "INDOOR", { "ECRUTEAK_POKECENTER_1F" }, { "ECRUTEAK_CITY:6" } },
  { "ECRUTEAK_LUGIA_SPEECH_HOUSE", "INDOOR", { "ECRUTEAK_LUGIA_SPEECH_HOUSE" }, { "ECRUTEAK_CITY:7" } },
  { "DANCE_THEATER", "INDOOR", { "DANCE_THEATER" }, { "ECRUTEAK_CITY:8" } },
  { "ECRUTEAK_MART", "INDOOR", { "ECRUTEAK_MART" }, { "ECRUTEAK_CITY:9" } },
  { "ECRUTEAK_GYM", "INDOOR", { "ECRUTEAK_GYM" }, { "ECRUTEAK_CITY:10" } },
  { "ECRUTEAK_ITEMFINDER_HOUSE", "INDOOR", { "ECRUTEAK_ITEMFINDER_HOUSE" }, { "ECRUTEAK_CITY:11" } },
  { "TIN_TOWER_1F", "DUNGEON", { "TIN_TOWER_1F", "TIN_TOWER_9F" }, { "ECRUTEAK_CITY:12", "TIN_TOWER_ROOF:1" } },
  { "BURNED_TOWER_1F", "DUNGEON", { "BURNED_TOWER_1F", "BURNED_TOWER_B1F" }, { "ECRUTEAK_CITY:13" } },
  { "ROUTE_38_ECRUTEAK_GATE", "GATE", { "ROUTE_38_ECRUTEAK_GATE" },
    { "ECRUTEAK_CITY:14", "ECRUTEAK_CITY:15", "ROUTE_38:1", "ROUTE_38:2" } },
  { "ROUTE_39_BARN", "INDOOR", { "ROUTE_39_BARN" }, { "ROUTE_39:1" } },
  { "ROUTE_39_FARMHOUSE", "INDOOR", { "ROUTE_39_FARMHOUSE" }, { "ROUTE_39:2" } },
  { "OLIVINE_POKECENTER_1F", "INDOOR", { "OLIVINE_POKECENTER_1F" }, { "OLIVINE_CITY:1" } },
  { "OLIVINE_GYM", "INDOOR", { "OLIVINE_GYM" }, { "OLIVINE_CITY:2" } },
  { "OLIVINE_GOOD_ROD_HOUSE", "INDOOR", { "OLIVINE_GOOD_ROD_HOUSE" }, { "OLIVINE_CITY:6" } },
  { "OLIVINE_CAFE", "INDOOR", { "OLIVINE_CAFE" }, { "OLIVINE_CITY:7" } },
  { "OLIVINE_MART", "INDOOR", { "OLIVINE_MART" }, { "OLIVINE_CITY:8" } },
  { "OLIVINE_LIGHTHOUSE_1F", "DUNGEON", { "OLIVINE_LIGHTHOUSE_1F", "OLIVINE_LIGHTHOUSE_6F" }, { "OLIVINE_CITY:9" } },
  { "OLIVINE_PORT_PASSAGE", "INDOOR", { "OLIVINE_PORT_PASSAGE" },
    { "OLIVINE_CITY:10", "OLIVINE_CITY:11", "OLIVINE_PORT:1" } },
  { "FAST_SHIP_1F", "INDOOR", { "FAST_SHIP_1F" }, { "OLIVINE_PORT:2" } },
  { "ROUTE_40_BATTLE_TOWER_GATE", "GATE", { "ROUTE_40_BATTLE_TOWER_GATE" },
    { "ROUTE_40:1", "BATTLE_TOWER_OUTSIDE:1", "BATTLE_TOWER_OUTSIDE:2" } },
  { "WHIRL_ISLAND_B1F", "CAVE", { "WHIRL_ISLAND_B1F", "WHIRL_ISLAND_NW", "WHIRL_ISLAND_NE", "WHIRL_ISLAND_SW",
      "WHIRL_ISLAND_SE" }, { "ROUTE_41:1", "ROUTE_41:2", "ROUTE_41:3", "ROUTE_41:4" } },
  { "MANIAS_HOUSE", "INDOOR", { "MANIAS_HOUSE" }, { "CIANWOOD_CITY:1" } },
  { "CIANWOOD_GYM", "INDOOR", { "CIANWOOD_GYM" }, { "CIANWOOD_CITY:2" } },
  { "CIANWOOD_POKECENTER_1F", "INDOOR", { "CIANWOOD_POKECENTER_1F" }, { "CIANWOOD_CITY:3" } },
  { "CIANWOOD_PHARMACY", "INDOOR", { "CIANWOOD_PHARMACY" }, { "CIANWOOD_CITY:4" } },
  { "CIANWOOD_PHOTO_STUDIO", "INDOOR", { "CIANWOOD_PHOTO_STUDIO" }, { "CIANWOOD_CITY:5" } },
  { "MOUNT_MORTAR_1F_INSIDE", "CAVE", { "MOUNT_MORTAR_1F_INSIDE", "MOUNT_MORTAR_1F_OUTSIDE" },
    { "ROUTE_42:3", "ROUTE_42:4", "ROUTE_42:5" } },
  { "MAHOGANY_MART_1F", "INDOOR", { "MAHOGANY_MART_1F", "TEAM_ROCKET_BASE_B1F", "TEAM_ROCKET_BASE_B2F",
      "TEAM_ROCKET_BASE_B3F" }, { "MAHOGANY_TOWN:1" } },
  { "MAHOGANY_RED_GYARADOS_SPEECH_HOUSE", "INDOOR", { "MAHOGANY_RED_GYARADOS_SPEECH_HOUSE" }, { "MAHOGANY_TOWN:2" } },
  { "MAHOGANY_GYM", "INDOOR", { "MAHOGANY_GYM" }, { "MAHOGANY_TOWN:3" } },
  { "MAHOGANY_POKECENTER_1F", "INDOOR", { "MAHOGANY_POKECENTER_1F" }, { "MAHOGANY_TOWN:4" } },
  { "ROUTE_43_MAHOGANY_GATE", "GATE", { "ROUTE_43_MAHOGANY_GATE" },
    { "MAHOGANY_TOWN:5", "ROUTE_43:1", "ROUTE_43:2" } },
  { "ROUTE_43_GATE", "GATE", { "ROUTE_43_GATE" }, { "ROUTE_43:3", "ROUTE_43:4", "ROUTE_43:5" } },
  { "LAKE_OF_RAGE_HIDDEN_POWER_HOUSE", "INDOOR", { "LAKE_OF_RAGE_HIDDEN_POWER_HOUSE" }, { "LAKE_OF_RAGE:1" } },
  { "LAKE_OF_RAGE_MAGIKARP_HOUSE", "INDOOR", { "LAKE_OF_RAGE_MAGIKARP_HOUSE" }, { "LAKE_OF_RAGE:2" } },
  { "ICE_PATH_1F", "CAVE", { "ICE_PATH_1F", "ICE_PATH_B1F" }, { "ROUTE_44:1", "BLACKTHORN_CITY:7" } },
  { "BLACKTHORN_GYM_1F", "INDOOR", { "BLACKTHORN_GYM_1F", "BLACKTHORN_GYM_2F" }, { "BLACKTHORN_CITY:1" } },
  { "BLACKTHORN_DRAGON_SPEECH_HOUSE", "INDOOR", { "BLACKTHORN_DRAGON_SPEECH_HOUSE" }, { "BLACKTHORN_CITY:2" } },
  { "BLACKTHORN_MART", "INDOOR", { "BLACKTHORN_MART" }, { "BLACKTHORN_CITY:4" } },
  { "BLACKTHORN_POKECENTER_1F", "INDOOR", { "BLACKTHORN_POKECENTER_1F" }, { "BLACKTHORN_CITY:5" } },
  { "DRAGONS_DEN_1F", "CAVE", { "DRAGONS_DEN_1F", "DRAGONS_DEN_B1F", "DRAGON_SHRINE" }, { "BLACKTHORN_CITY:8" } },
  { "ROUTE_27_SANDSTORM_HOUSE", "INDOOR", { "ROUTE_27_SANDSTORM_HOUSE" }, { "ROUTE_27:1" } },
  { "TOHJO_FALLS", "CAVE", { "TOHJO_FALLS" }, { "ROUTE_27:2", "ROUTE_27:3" } },
  { "VICTORY_ROAD", "CAVE", { "VICTORY_ROAD", "VICTORY_ROAD_GATE" },
    { "ROUTE_22:1", "ROUTE_23:3", "ROUTE_23:4", "ROUTE_26:1", "ROUTE_28:2" } },
  { "ROUTE_26_HEAL_HOUSE", "INDOOR", { "ROUTE_26_HEAL_HOUSE" }, { "ROUTE_26:2" } },
  { "INDIGO_PLATEAU_POKECENTER_1F", "INDOOR", { "INDIGO_PLATEAU_POKECENTER_1F", "WILLS_ROOM", "KOGAS_ROOM",
      "BRUNOS_ROOM", "KARENS_ROOM", "LANCES_ROOM", "HALL_OF_FAME" }, { "ROUTE_23:1", "ROUTE_23:2" } },
}

-- Two-tile doorways become one entrance, like mapgraph (adjacent warp numbers
-- of one outdoor map into one complex; good enough for these doors).
local function buildGraph(withEntrances)
  local graph = { doors = {}, complexes = {}, outdoor = {}, entrances = {} }
  local data = { gen2Maps = {} }
  for _, row in ipairs(SPEC) do
    local cid, env, maps, doors = row[1], row[2], row[3], row[4]
    local c = { id = cid, maps = maps, environment = env, doors = {}, entrances = {}, story = false }
    for _, m in ipairs(maps) do data.gen2Maps[m] = { environment = env } end
    local last
    for _, key in ipairs(doors) do
      local map, warp = key:match("^(.*):(%d+)$")
      warp = tonumber(warp)
      graph.outdoor[map] = true
      local door = { id = key, map = map, warp = warp, complex = cid, inside = { { map = maps[1], warp = 1 } } }
      graph.doors[key] = door
      c.doors[#c.doors + 1] = key
      if withEntrances then
        local prev = last and graph.doors[last]
        if prev and prev.map == map and prev.warp == warp - 1 and not (map == "ROUTE_43" and warp == 4) then
          door.entrance = prev.entrance
          table.insert(graph.entrances[prev.entrance].doors, key)
        else
          door.entrance = key
          graph.entrances[key] = { id = key, map = map, complex = cid, doors = { key } }
          c.entrances[#c.entrances + 1] = key
        end
      end
      last = key
    end
    c.deadEnd = #doors == 1
    graph.complexes[cid] = c
  end
  for _, rid in pairs(R.REGIONS) do for _, m in ipairs(rid) do graph.outdoor[m] = true end end
  for m in pairs(graph.outdoor) do data.gen2Maps[m] = { environment = "ROUTE" } end
  if not withEntrances then graph.entrances = nil end
  return graph, data
end

local graph, data = buildGraph(false)
local rules = R.model(data, graph)

-- the documented shape
for _, field in ipairs({ "fixed", "regions", "needs", "doorRegion", "complexNeeds" }) do
  ok(type(rules[field]) == "table", "rules." .. field .. " is a table")
end
ok(type(rules.canWin) == "function", "rules.canWin is a function")
eq(#rules.unlocated, 0, "every story step and HM site is in the hand graph: " .. table.concat(rules.unlocated, "; "))
for id in pairs(graph.doors) do ok(rules.doorRegion[id] ~= nil, "door " .. id .. " has a region") end

-- vanilla
local won, why = rules.canWin({}, nil)
ok(won, "the vanilla placement is winnable (" .. tostring(why) .. ")")
local identity = {}
for id in pairs(graph.doors) do identity[id] = id end
ok(rules.canWin(identity, nil), "every door mapped to itself is the vanilla placement")
ok(rules.canWin({}, R.vanillaHms()), "vanilla doors with vanilla HMs given explicitly")

-- fixed complexes and reasons
local mustBeFixed = { "ELMS_LAB", "PLAYERS_HOUSE_1F", "VIOLET_GYM", "AZALEA_GYM", "GOLDENROD_GYM", "ECRUTEAK_GYM",
  "CIANWOOD_GYM", "OLIVINE_GYM", "MAHOGANY_GYM", "BLACKTHORN_GYM_1F", "RADIO_TOWER_1F", "MAHOGANY_MART_1F",
  "GOLDENROD_DEPT_STORE_1F", "ILEX_FOREST_AZALEA_GATE", "RUINS_OF_ALPH_AERODACTYL_CHAMBER", "TIN_TOWER_1F",
  "BURNED_TOWER_1F", "VICTORY_ROAD", "INDIGO_PLATEAU_POKECENTER_1F", "FAST_SHIP_1F", "OLIVINE_PORT_PASSAGE",
  "GOLDENROD_MAGNET_TRAIN_STATION", "KURTS_HOUSE", "SLOWPOKE_WELL_B1F", "OLIVINE_LIGHTHOUSE_1F",
  "CIANWOOD_PHARMACY", "GOLDENROD_FLOWER_SHOP", "MR_POKEMONS_HOUSE", "DRAGONS_DEN_1F",
  "ROUTE_35_NATIONAL_PARK_GATE", "ROUTE_36_NATIONAL_PARK_GATE", "ECRUTEAK_TIN_TOWER_ENTRANCE" }
for _, cid in ipairs(mustBeFixed) do
  ok(type(rules.fixed[cid]) == "string" and #rules.fixed[cid] > 10, cid .. " is fixed with a reason")
end
for _, cid in ipairs({ "DANCE_THEATER", "OLIVINE_CAFE", "SPROUT_TOWER_1F", "UNION_CAVE_1F", "ICE_PATH_1F",
    "ECRUTEAK_MART", "TOHJO_FALLS", "ROUTE_31_VIOLET_GATE" }) do
  eq(rules.fixed[cid], nil, cid .. " may move")
end
local fixedCount = 0
for _ in pairs(rules.fixed) do fixedCount = fixedCount + 1 end
print(("  hand graph: %d complexes fixed"):format(fixedCount))

-- swapping two entrances' destinations (per-door, both tiles of a doorway)
local function swap(a, b)
  local p = {}
  for i = 1, #a do p[a[i]] = b[1]; end
  for i = 1, #b do p[b[i]] = a[1]; end
  return p
end
local function refused(p, msg, hms)
  local w, reason = rules.canWin(p, hms)
  ok(not w, msg .. " is refused")
  ok(type(reason) == "string" and #reason > 0, msg .. " says why (" .. tostring(reason) .. ")")
  return reason
end
local function accepted(p, msg, hms)
  local w, reason = rules.canWin(p, hms)
  ok(w, msg .. " is accepted (" .. tostring(reason) .. ")")
end

-- The only way to SURF's location behind water: the Dance Theater (HM03)
-- behind Route 27's door, which needs SURF to reach.
local r = refused(swap({ "ECRUTEAK_CITY:8" }, { "ROUTE_27:1" }), "SURF's Dance Theater behind Route 27's water")
ok(r:find("BADGE_STORM", 1, true) ~= nil, "and Cianwood's STORMBADGE, across the sea, is among what cannot be reached")
-- HM03 behind Cianwood, which needs SURF to reach.
refused(swap({ "ECRUTEAK_CITY:8" }, { "CIANWOOD_CITY:5" }), "SURF's Dance Theater on Cianwood")
-- STRENGTH's cafe behind the Dragon's Den pool: Blackthorn is reached through
-- the Ice Path, whose Blackthorn side and the hideout before it need STRENGTH.
refused(swap({ "OLIVINE_CITY:7" }, { "BLACKTHORN_CITY:8" }), "STRENGTH's cafe across Blackthorn's pond")
-- Union Cave's Route 33 mouth swapped with a Whirl Islands mouth: Azalea is
-- then reached only from the sea, after SURF, which needs the HIVEBADGE first.
refused(swap({ "ROUTE_33:1" }, { "ROUTE_41:1" }), "Union Cave's way to Azalea swapped onto the Whirl Islands")
-- Moving a fixed complex.
r = refused(swap({ "GOLDENROD_CITY:6" }, { "GOLDENROD_CITY:2" }), "moving the flower shop")
ok(r:find("fixed", 1, true) ~= nil, "and says a fixed complex moved")
refused(swap({ "VIOLET_CITY:2" }, { "VIOLET_CITY:1" }), "moving Violet gym")
refused({ ["NO_SUCH_MAP:1"] = "VIOLET_CITY:1" }, "a placement naming an unknown door")

-- Harmless placements.
accepted(swap({ "ECRUTEAK_CITY:8" }, { "ECRUTEAK_CITY:9" }), "the Dance Theater and Ecruteak mart swapped")
accepted(swap({ "OLIVINE_CITY:7" }, { "CIANWOOD_CITY:5" }), "STRENGTH's cafe on Cianwood (reached by SURF first)")
accepted(swap({ "VIOLET_CITY:1" }, { "CHERRYGROVE_CITY:1" }), "two marts swapped")
accepted(swap({ "ROUTE_32:1" }, { "ROUTE_26:2" }), "a center and a far house swapped")

-- FLASH is needed only for the RISINGBADGE and the League, so Sprout Tower
-- may stand behind Lake of Rage's corner (CUT and SURF, both earlier).
accepted(swap({ "VIOLET_CITY:7" }, { "LAKE_OF_RAGE:1" }), "Sprout Tower behind Lake of Rage's corner")

-- Same answer whether given by doors or by entrances.
do
  local g2, d2 = buildGraph(true)
  local r2 = R.model(d2, g2)
  ok(r2.canWin({ entrances = {} }, nil), "entrances: vanilla is winnable")
  local p = { entrances = { ["ECRUTEAK_CITY:8"] = "ROUTE_27:1", ["ROUTE_27:1"] = "ECRUTEAK_CITY:8" } }
  ok(not r2.canWin(p, nil), "entrances: SURF behind water is refused")
  p = { entrances = { ["AZALEA_TOWN:7"] = "AZALEA_TOWN:1", ["AZALEA_TOWN:1"] = "AZALEA_TOWN:7" } }
  local w, reason = r2.canWin(p, nil)
  ok(not w and reason:find("fixed", 1, true), "entrances: moving Ilex Forest's doorway is refused")
  p = { entrances = { ["ECRUTEAK_CITY:8"] = "ECRUTEAK_CITY:9", ["ECRUTEAK_CITY:9"] = "ECRUTEAK_CITY:8" },
        ["ECRUTEAK_CITY:8"] = "ECRUTEAK_CITY:9", ["ECRUTEAK_CITY:9"] = "ECRUTEAK_CITY:8" }
  ok(r2.canWin(p, nil), "entrances with the per-door copy alongside")
end

-- Deterministic and quick.
do
  local p = swap({ "ECRUTEAK_CITY:8" }, { "ROUTE_27:1" })
  local a1, b1 = rules.canWin(p, nil)
  local a2, b2 = rules.canWin(p, nil)
  ok(a1 == a2 and b1 == b2, "the same placement gets the same answer")
  local t = os.clock()
  for _ = 1, 500 do rules.canWin({}, nil) end
  print(("  hand graph: canWin %.3f ms per call"):format((os.clock() - t) / 500 * 1000))
end

-- ------------------------------------------------------------ 2. the HM shuffle
do
  local agree, total, keyitemsOnly, rulesOnly = 0, 0, 0, 0
  K.eachPlacement(function(p)
    total = total + 1
    local a, b = K.beatable(p), rules.canWin({}, p)
    if a == b then agree = agree + 1 elseif a then keyitemsOnly = keyitemsOnly + 1 else rulesOnly = rulesOnly + 1 end
  end)
  eq(total, 5040, "every HM placement checked")
  eq(rulesOnly, 0, "no HM placement maprules accepts that keyitems refuses")
  eq(keyitemsOnly, 0, "no HM placement keyitems accepts that maprules refuses")
  print(("  HM shuffle: %d of %d agree with keyitems"):format(agree, total))
  -- An HM shuffle that keyitems refuses: SURF and CUT swapped (CUT behind Sudowoodo... ).
  local p = R.vanillaHms()
  p.DANCE_THEATER, p.ILEX_FOREST = "HM_CUT", "HM_SURF"
  ok(not rules.canWin({}, p), "CUT at the Dance Theater (behind Ilex's CUT tree) is refused")
end

-- ------------------------------------------------------------ install
do
  local ctx = Fake.new({})
  R.install(nil, ctx)
  ok(type(ctx.lib.mapRules) == "table" and ctx.lib.mapRules.model == R.model, "install offers ctx.lib.mapRules.model")
  eq(#R.questions, 0, "no questions")
end

-- ------------------------------------------------------------ 3. real Crystal data
local cache = os.getenv("CRYSTAL_RANDOMIZER_CACHE")
if cache and cache ~= "" then
  local G = dofile("launcher/mods/crystal_randomizer/modules/mapgraph.lua")._M
  local real = { gen2Maps = dofile(cache .. "/maps.lua"), gen2Scripts = dofile(cache .. "/scripts.lua") }
  local g = G.build(real)
  local rr = R.model(real, g)
  eq(#rr.unlocated, 0, "real data: every story step located (" .. table.concat(rr.unlocated, "; ") .. ")")
  local w, reason = rr.canWin({}, nil)
  ok(w, "real data: vanilla is winnable (" .. tostring(reason) .. ")")
  local count = 0
  for cid, why in pairs(rr.fixed) do count = count + 1 end
  print(("  real data: %d complexes fixed"):format(count))
  for _, map in ipairs({ "ELMS_LAB", "VIOLET_GYM", "RADIO_TOWER_1F", "TIN_TOWER_1F", "BATTLE_TOWER_1F",
      "KURTS_HOUSE", "FAST_SHIP_1F", "HALL_OF_FAME", "ROUTE_36_NATIONAL_PARK_GATE" }) do
    local cid = g.complexOf and g.complexOf[map]
    ok(cid and rr.fixed[cid], "real data: " .. map .. "'s complex is fixed")
  end
  local t = os.clock()
  for _ = 1, 200 do rr.canWin({}, nil) end
  local ms = (os.clock() - t) / 200 * 1000
  print(("  real data: canWin %.3f ms per call"):format(ms))
  ok(ms < 5, "real data: one call under 5 ms")
  -- Random swaps of two dead-end entrances among the movable ones.
  local movable = {}
  for _, eid in ipairs(g.entranceOrder or {}) do
    local e = g.entrances[eid]
    local c = g.complexes[e.complex]
    if c and c.deadEnd and not rr.fixed[e.complex] then movable[#movable + 1] = eid end
  end
  local Rng = dofile("launcher/mods/crystal_randomizer/rng.lua")
  local rng = Rng.streamFor(tonumber(os.getenv("CRYSTAL_RANDOMIZER_RNG_VERSION")) or 1, "maprules-test", "swaps")
  local yes, no = 0, 0
  for _ = 1, 300 do
    local a, b = movable[rng:int(1, #movable)], movable[rng:int(1, #movable)]
    if a ~= b then
      local p = { entrances = { [a] = b, [b] = a } }
      if rr.canWin(p, nil) then yes = yes + 1 else no = no + 1 end
    end
  end
  print(("  real data: %d movable dead-end entrances; of random swaps %d accepted, %d refused"):format(
    #movable, yes, no))
  ok(yes > 0 and no > 0, "real data: some swaps pass and some strand")
  print("real Crystal data checked: " .. cache)
end

print(string.format("maprules_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
