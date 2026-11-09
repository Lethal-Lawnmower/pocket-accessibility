-- Crystal randomizer: what the map shuffle must respect (MAPS.md "maprules").
--
-- No questions.  install() only offers ctx.lib.mapRules.model(data, graph),
-- which returns the rules the placer checks every placement against:
--
--   fixed        complexes that never move, each with its reason
--   regions      outdoor areas walkable with nothing more
--   needs        what crossing between two regions needs ("A|B", both ways)
--   doorRegion   which region each outdoor door stands in
--   complexNeeds what moving through each complex needs (exits, sides)
--   canWin       whether a placement keeps the whole game beatable
--
-- The logic follows keyitems.lua: needs are badges ("BADGE_FOG"), story steps
-- ("EVENT_..."), and HMs held ("SURF" means the HM that teaches SURF is in the
-- bag; a field move is always written with its badge next to it).  The model
-- is deliberately strict.  Where the true needs were not certain, it needs
-- more, or treats a passage as closed ("NEVER").  Over-requiring only removes
-- placements; it never lets one through that strands the player.  Every story
-- step's own needs repeat keyitems.lua's M.EVENTS (including its strict
-- "everything a vanilla player holds by then" lists), so with vanilla doors
-- this model accepts exactly the HM placements keyitems accepts; the test
-- checks that on all 5040.
--
-- How a placement is read (MAPS.md): placement[A] = P means outdoor door A
-- now leads where door P led, so walking into A puts the player on P's side
-- of P's complex, and leaving by P's side comes back out at A.  A door not in
-- the placement, or mapped to itself, is unmoved.
--
-- Inside a complex the model has a hub (the complex's middle) and sides (a
-- door, or doors standing together, such as the two tiles of a wide doorway).
-- Doors on the same side reach each other freely; reaching the hub from a
-- side, or a side from the hub, needs complexNeeds[c].exits[door].  A cave
-- the model does not know, whose doors stand in different regions, is
-- closed between them ("NEVER"): a door into it only leads back out.
--
-- Sources: pret/pokecrystal map scripts (maps/*.asm) as summarised in
-- keyitems.lua and checked against the cart's own decoded data (an import of
-- Crystal Rev 1 into a disposable identity): each map's warps, connections,
-- coord events and objects, and the scripts' warp commands.  The engine's
-- field-move badges are src/world/gen2/FieldMoves.lua FieldMoves.BADGE.
-- Each table entry says where it comes from or why it is strict.

local M = { id = "maprules", questions = {} }

-- ---------------------------------------------------------------- field moves

-- HM item -> the token holding it gives, and the badge its field use needs
-- (src/world/gen2/FieldMoves.lua FieldMoves.BADGE, which follows
-- engine/events/overworld.asm).
M.HMS = {
  HM_CUT = { move = "CUT", badge = "BADGE_HIVE" },
  HM_FLY = { move = "FLY", badge = "BADGE_STORM" },
  HM_SURF = { move = "SURF", badge = "BADGE_FOG" },
  HM_STRENGTH = { move = "STRENGTH", badge = "BADGE_PLAIN" },
  HM_FLASH = { move = "FLASH", badge = "BADGE_ZEPHYR" },
  HM_WHIRLPOOL = { move = "WHIRLPOOL", badge = "BADGE_GLACIER" },
  HM_WATERFALL = { move = "WATERFALL", badge = "BADGE_RISING" },
}
local MOVE_BADGE = {}
for _, hm in pairs(M.HMS) do MOVE_BADGE[hm.move] = hm.badge end

M.JOHTO_BADGES = { "BADGE_ZEPHYR", "BADGE_HIVE", "BADGE_PLAIN", "BADGE_FOG", "BADGE_STORM",
  "BADGE_MINERAL", "BADGE_GLACIER", "BADGE_RISING" }

-- Needs written compactly: "use:SURF" expands to SURF and BADGE_FOG.
local function needs(...)
  local out = {}
  for i = 1, select("#", ...) do
    local item = select(i, ...)
    local list = type(item) == "table" and item or { item }
    for _, need in ipairs(list) do
      local move = type(need) == "string" and need:match("^use:(.+)$")
      if move then
        out[#out + 1] = move
        out[#out + 1] = MOVE_BADGE[move] or ("NO_BADGE_FOR_" .. move)
      else
        out[#out + 1] = need
      end
    end
  end
  return out
end

local ALL_USES = needs("use:CUT", "use:FLY", "use:SURF", "use:STRENGTH", "use:FLASH",
  "use:WHIRLPOOL", "use:WATERFALL")
local SEVEN_BADGES = { "BADGE_ZEPHYR", "BADGE_HIVE", "BADGE_PLAIN", "BADGE_FOG", "BADGE_STORM",
  "BADGE_MINERAL", "BADGE_GLACIER" }
local NEVER = { "NEVER" }

-- ---------------------------------------------------------------- fixed complexes

-- A complex holding any of these maps never moves.  Matched by map, not by
-- complex id, so it holds however mapgraph names and groups complexes.
local FIXED = {}
local function fix(reason, list) for _, map in ipairs(list) do FIXED[map] = reason end end

fix("Elm's lab: the starter, the egg errand and Elm's later scenes are scripted there",
  { "ELMS_LAB" })
fix("the player's house: the game starts there, the League ending warps there, and it is the home heal point",
  { "PLAYERS_HOUSE_1F", "PLAYERS_HOUSE_2F" })
fix("a gym: its leader's script gives the badge", { "VIOLET_GYM", "AZALEA_GYM", "GOLDENROD_GYM",
  "ECRUTEAK_GYM", "CIANWOOD_GYM", "OLIVINE_GYM", "MAHOGANY_GYM", "BLACKTHORN_GYM_1F",
  "BLACKTHORN_GYM_2F", "PEWTER_GYM", "CERULEAN_GYM", "VERMILION_GYM", "CELADON_GYM", "FUCHSIA_GYM",
  "SAFFRON_GYM", "SEAFOAM_GYM", "VIRIDIAN_GYM" })
fix("the Radio Tower: the Rocket takeover", { "RADIO_TOWER_1F", "RADIO_TOWER_2F", "RADIO_TOWER_3F",
  "RADIO_TOWER_4F", "RADIO_TOWER_5F" })
fix("the Goldenrod Underground: the BASEMENT KEY and CARD KEY steps of the takeover",
  { "GOLDENROD_UNDERGROUND", "GOLDENROD_UNDERGROUND_SWITCH_ROOM_ENTRANCES",
    "GOLDENROD_UNDERGROUND_WAREHOUSE", "GOLDENROD_DEPT_STORE_B1F" })
fix("the Rocket hideout under the Mahogany mart: Lance, the Electrodes and HM06",
  { "MAHOGANY_MART_1F", "TEAM_ROCKET_BASE_B1F", "TEAM_ROCKET_BASE_B2F", "TEAM_ROCKET_BASE_B3F" })
fix("Ilex Forest: the shrine path, the FARFETCH'D, HM01 and the GS BALL scene",
  { "ILEX_FOREST", "ILEX_FOREST_AZALEA_GATE", "ROUTE_34_ILEX_FOREST_GATE" })
fix("the Ruins of Alph: puzzle chambers, the Unown and the research center",
  { "RUINS_OF_ALPH_HO_OH_CHAMBER", "RUINS_OF_ALPH_KABUTO_CHAMBER", "RUINS_OF_ALPH_OMANYTE_CHAMBER",
    "RUINS_OF_ALPH_AERODACTYL_CHAMBER", "RUINS_OF_ALPH_INNER_CHAMBER", "RUINS_OF_ALPH_RESEARCH_CENTER",
    "RUINS_OF_ALPH_HO_OH_ITEM_ROOM", "RUINS_OF_ALPH_KABUTO_ITEM_ROOM", "RUINS_OF_ALPH_OMANYTE_ITEM_ROOM",
    "RUINS_OF_ALPH_AERODACTYL_ITEM_ROOM", "RUINS_OF_ALPH_HO_OH_WORD_ROOM",
    "RUINS_OF_ALPH_KABUTO_WORD_ROOM", "RUINS_OF_ALPH_OMANYTE_WORD_ROOM",
    "RUINS_OF_ALPH_AERODACTYL_WORD_ROOM" })
fix("Tin Tower: the sages, the CLEAR BELL and Suicune", { "TIN_TOWER_1F", "TIN_TOWER_2F",
  "TIN_TOWER_3F", "TIN_TOWER_4F", "TIN_TOWER_5F", "TIN_TOWER_6F", "TIN_TOWER_7F", "TIN_TOWER_8F",
  "TIN_TOWER_9F", "ECRUTEAK_TIN_TOWER_ENTRANCE", "WISE_TRIOS_ROOM" })
fix("the Burned Tower: the beasts' scene that opens the Ecruteak gym", { "BURNED_TOWER_1F",
  "BURNED_TOWER_B1F" })
fix("Victory Road and its gate: the eight-badge check", { "VICTORY_ROAD", "VICTORY_ROAD_GATE" })
fix("the Pokemon League: the Elite Four, Lance and the Hall of Fame",
  { "INDIGO_PLATEAU_POKECENTER_1F", "WILLS_ROOM", "KOGAS_ROOM", "BRUNOS_ROOM", "KARENS_ROOM",
    "LANCES_ROOM", "HALL_OF_FAME" })
fix("the S.S. Aqua: its scripts warp between the ports and the ship",
  { "FAST_SHIP_1F", "FAST_SHIP_B1F", "FAST_SHIP_CABINS_NNW_NNE_NE",
    "FAST_SHIP_CABINS_SE_SSE_CAPTAINS_CABIN", "FAST_SHIP_CABINS_SW_SSW_NW", "OLIVINE_PORT_PASSAGE",
    "VERMILION_PORT_PASSAGE" })
fix("the Magnet Train: the PASS and the stations' ride scripts",
  { "GOLDENROD_MAGNET_TRAIN_STATION", "SAFFRON_MAGNET_TRAIN_STATION" })
fix("the Slowpoke Well: the Rockets; its script warps the player to Kurt's house",
  { "SLOWPOKE_WELL_B1F", "SLOWPOKE_WELL_B2F" })
fix("Kurt's house: the Slowpoke Well script warps here; Kurt's balls and the GS BALL",
  { "KURTS_HOUSE" })
fix("the Olivine Lighthouse: Jasmine and AMPHY, the MINERALBADGE story",
  { "OLIVINE_LIGHTHOUSE_1F", "OLIVINE_LIGHTHOUSE_2F", "OLIVINE_LIGHTHOUSE_3F",
    "OLIVINE_LIGHTHOUSE_4F", "OLIVINE_LIGHTHOUSE_5F", "OLIVINE_LIGHTHOUSE_6F" })
fix("the Cianwood pharmacy: the SECRETPOTION for AMPHY", { "CIANWOOD_PHARMACY" })
fix("the Goldenrod flower shop: the SQUIRTBOTTLE for SUDOWOODO, given only before SUDOWOODO is fought",
  { "GOLDENROD_FLOWER_SHOP" })
fix("Mr. Pokemon's house: the MYSTERY EGG and Oak's POKEDEX", { "MR_POKEMONS_HOUSE" })
fix("the Dragon's Den: Clair's test before the RISINGBADGE", { "DRAGONS_DEN_1F", "DRAGONS_DEN_B1F",
  "DRAGON_SHRINE" })
fix("a National Park gate: the Bug-Catching Contest scripts warp through it",
  { "ROUTE_35_NATIONAL_PARK_GATE", "ROUTE_36_NATIONAL_PARK_GATE" })
fix("the Battle Tower: its scripts warp the player between its rooms and back to the lobby",
  { "BATTLE_TOWER_1F", "BATTLE_TOWER_BATTLE_ROOM", "BATTLE_TOWER_ELEVATOR", "BATTLE_TOWER_HALLWAY" })
fix("Kanto story after the League: the MACHINE PART, the EXPN CARD, the PASS, Oak and Red",
  { "POWER_PLANT", "LAV_RADIO_TOWER_1F", "COPYCATS_HOUSE_1F", "COPYCATS_HOUSE_2F", "OAKS_LAB",
    "SILVER_CAVE_ROOM_1", "SILVER_CAVE_ROOM_2", "SILVER_CAVE_ROOM_3", "SILVER_CAVE_ITEM_ROOMS" })
M.FIXED_MAPS = FIXED

local SCRIPT_WARP_OPS = { warp = true, warpfacing = true }

-- Maps some script warps the player into (args group, map), from the cart's
-- scripts: a complex such a warp lands in must stay where the script expects.
function M.scriptWarpTargets(data)
  local out = {}
  local maps, scripts = data and data.gen2Maps, data and data.gen2Scripts
  if type(maps) ~= "table" or type(scripts) ~= "table" then return out end
  local byNumber = {}
  for id, m in pairs(maps) do
    if type(m) == "table" and m.group and m.map then byNumber[m.group .. ":" .. m.map] = id end
  end
  for _, list in pairs(scripts) do
    if type(list) == "table" then
      for _, cmd in ipairs(list) do
        if type(cmd) == "table" and SCRIPT_WARP_OPS[cmd.op] and type(cmd.args) == "table" then
          -- warp: map group, map number, x, y.  warpfacing: facing first.
          local a = cmd.args
          local group, number = a[1], a[2]
          if cmd.op == "warpfacing" then group, number = a[2], a[3] end
          local id = byNumber[tostring(group) .. ":" .. tostring(number)]
          if id then out[id] = true end
        end
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------- outdoor regions

-- Region -> the outdoor maps it holds.  Maps joined here are walked between
-- in both directions with nothing more.  Where two maps meet only through a
-- gate or cave (Route 31 and Violet, Azalea and Route 34, Route 32 and Route
-- 33, Ecruteak and Routes 38 and 42, Mahogany and Route 43, Route 29 and
-- Route 46), they are not joined: that way goes through a complex and moves
-- with it.  One-way ledges (Route 45 down to Route 46) are not modelled.  An
-- outdoor map not listed is a region of its own with no crossings (Kanto,
-- which the goal does not need).
M.REGIONS = {
  NEW_BARK = { "NEW_BARK_TOWN" },
  CHERRYGROVE = { "ROUTE_29", "CHERRYGROVE_CITY", "ROUTE_30", "ROUTE_31" },
  ROUTE_46 = { "ROUTE_46" },
  VIOLET = { "VIOLET_CITY", "ROUTE_32", "ROUTE_36" },
  RUINS_OF_ALPH = { "RUINS_OF_ALPH_OUTSIDE" },
  AZALEA = { "ROUTE_33", "AZALEA_TOWN" },
  GOLDENROD = { "GOLDENROD_CITY", "ROUTE_34" },
  ECRUTEAK = { "ROUTE_35", "NATIONAL_PARK", "ROUTE_37", "ECRUTEAK_CITY" },
  BUG_CONTEST = { "NATIONAL_PARK_BUG_CONTEST" },
  OLIVINE = { "ROUTE_38", "ROUTE_39", "OLIVINE_CITY", "ROUTE_40" },
  OLIVINE_PORT = { "OLIVINE_PORT" },
  BATTLE_TOWER = { "BATTLE_TOWER_OUTSIDE" },
  ROUTE_41 = { "ROUTE_41" },
  CIANWOOD = { "CIANWOOD_CITY" },
  ROUTE_42_WEST = { "ROUTE_42" },
  MAHOGANY = { "MAHOGANY_TOWN" },
  LAKE_OF_RAGE = { "ROUTE_43", "LAKE_OF_RAGE" },
  ROUTE_44 = { "ROUTE_44" },
  BLACKTHORN = { "BLACKTHORN_CITY", "ROUTE_45" },
  ROUTE_27_WEST = { "ROUTE_27" },
  ROUTE_26 = { "ROUTE_26" },
  INDIGO = { "ROUTE_23" },
  TIN_TOWER_ROOF = { "TIN_TOWER_ROOF" },
  -- Regions that hold only some doors of a map (M.DOOR_REGION).
  ECRUTEAK_ROUTE_36 = {},
  RUINS_WEST = {},
  WHIRL_ISLANDS = {},
  ROUTE_42_MIDDLE = {},
  LAKE_OF_RAGE_WEST = {},
  DRAGONS_DEN_POOL = {},
  ROUTE_27_EAST = {},
}

-- Doors (outdoor map:warp index, as in data.gen2Maps[map].warps) standing in
-- another region than their map's.
M.DOOR_REGION = {
  -- Route 36: SUDOWOODO (object at 35,9) stands between the National Park
  -- gate (warps 1-2 at x 18) and the Ruins gate (warps 3-4 at x 47) and Violet.
  ["ROUTE_36:1"] = "ECRUTEAK_ROUTE_36", ["ROUTE_36:2"] = "ECRUTEAK_ROUTE_36",
  -- Ruins of Alph: the Ho-Oh and Omanyte chambers and Union Cave's exits
  -- (west side, x 2-6) are taken apart from the main ruins.  Strict: no
  -- outdoor crossing is modelled to them.
  ["RUINS_OF_ALPH_OUTSIDE:1"] = "RUINS_WEST", ["RUINS_OF_ALPH_OUTSIDE:3"] = "RUINS_WEST",
  ["RUINS_OF_ALPH_OUTSIDE:7"] = "RUINS_WEST", ["RUINS_OF_ALPH_OUTSIDE:8"] = "RUINS_WEST",
  -- Route 41: the Whirl Islands entrances stand among whirlpools.
  ["ROUTE_41:1"] = "WHIRL_ISLANDS", ["ROUTE_41:2"] = "WHIRL_ISLANDS",
  ["ROUTE_41:3"] = "WHIRL_ISLANDS", ["ROUTE_41:4"] = "WHIRL_ISLANDS",
  -- Route 42: the middle Mt. Mortar entrance (28,9) stands past the water;
  -- the east one (46,7) is on the Mahogany side of it.
  ["ROUTE_42:4"] = "ROUTE_42_MIDDLE", ["ROUTE_42:5"] = "MAHOGANY",
  -- Lake of Rage: the house at (7,3), the far corner behind trees.
  ["LAKE_OF_RAGE:1"] = "LAKE_OF_RAGE_WEST",
  -- Blackthorn: the Dragon's Den (20,1) is across the pond.
  ["BLACKTHORN_CITY:8"] = "DRAGONS_DEN_POOL",
  -- Route 27: Tohjo Falls' west mouth (26,5) is reached from New Bark by
  -- water; its east mouth (36,5) and the house (33,7) are taken as the far side.
  ["ROUTE_27:1"] = "ROUTE_27_EAST", ["ROUTE_27:3"] = "ROUTE_27_EAST",
}

-- Crossings between regions, both ways.  Strict where unsure.
M.EDGES = {
  { "NEW_BARK", "CHERRYGROVE", needs("EVENT_STARTER"),
    why = "NewBarkTown coord events at (1,8)/(1,9): the teacher stops a player with no POKEMON" },
  { "NEW_BARK", "ROUTE_27_WEST", needs("use:SURF"), why = "Route 27 starts on the water east of New Bark" },
  { "ROUTE_27_EAST", "ROUTE_26", needs("use:SURF"),
    why = "walked in vanilla after Tohjo Falls; strict: SURF as the vanilla player holds it" },
  { "VIOLET", "ECRUTEAK_ROUTE_36", needs("EVENT_SQUIRTBOTTLE"),
    why = "Route36: SUDOWOODO (eventFlag object at 35,9) needs the SQUIRTBOTTLE" },
  { "ECRUTEAK_ROUTE_36", "ECRUTEAK", {}, why = "Route 36 west joins Routes 35 and 37 (connections)" },
  { "OLIVINE", "ROUTE_41", needs("use:SURF"), why = "Route 40 runs into the sea" },
  { "ROUTE_41", "CIANWOOD", needs("use:SURF"), why = "Route 41 is water" },
  { "ROUTE_41", "WHIRL_ISLANDS", needs("use:WHIRLPOOL"), why = "whirlpools ring the islands; strict" },
  { "ROUTE_42_WEST", "ROUTE_42_MIDDLE", needs("use:SURF"), why = "Route 42's water; strict" },
  { "ROUTE_42_WEST", "MAHOGANY", needs("use:SURF"),
    why = "Route 42's water (or Mt. Mortar, modelled as a complex)" },
  { "ROUTE_42_MIDDLE", "MAHOGANY", needs("use:SURF"), why = "Route 42's water; strict" },
  { "LAKE_OF_RAGE", "LAKE_OF_RAGE_WEST", needs("use:CUT", "use:SURF"),
    why = "trees around the far corner; strict: SURF as well" },
  { "MAHOGANY", "ROUTE_44", needs("EVENT_HIDEOUT", "EVENT_RADIO_TOWER"),
    why = "MahoganyTown coord events at (19,8)/(19,9): the RAGECANDYBAR man until the hideout "
      .. "is cleared; strict as keyitems ICE_PATH: the Radio Tower too" },
  { "BLACKTHORN", "DRAGONS_DEN_POOL", needs("use:SURF"), why = "the Dragon's Den is across the pond" },
}

-- ---------------------------------------------------------------- moving through complexes

-- Complexes the model knows door by door: door key -> its side and what
-- reaching the complex's hub from that side needs.  A door of a known
-- complex not listed here is closed.  Gates of Johto (environment GATE, all
-- doors in Johto regions) are open corridors without being listed.
local KNOWN = {}
local function known(side, need, doorKeys)
  for _, key in ipairs(doorKeys) do KNOWN[key] = { side = side, needs = need } end
end
-- Ilex Forest: the CUT tree stands between the Azalea half (the charcoal
-- master, HM01) and the Route 34 half (IlexForest.asm).
known("ilex:azalea", {}, { "AZALEA_TOWN:7", "AZALEA_TOWN:8" })
known("ilex:route34", needs("use:CUT"), { "ROUTE_34:1", "ROUTE_34:2" })
-- Union Cave: 1F joins Route 32 and Route 33 with no HM (the vanilla way to
-- Azalea).  The B1F exits to the Ruins: strict, STRENGTH and SURF.
known("union:route32", {}, { "ROUTE_32:4" })
known("union:route33", {}, { "ROUTE_33:1" })
known("union:ruins_north", needs("use:STRENGTH", "use:SURF"), { "RUINS_OF_ALPH_OUTSIDE:7" })
known("union:ruins_south", needs("use:STRENGTH", "use:SURF"), { "RUINS_OF_ALPH_OUTSIDE:8" })
-- Tohjo Falls: water inside, and the falls themselves.
known("tohjo:west", needs("use:SURF"), { "ROUTE_27:2" })
known("tohjo:east", needs("use:SURF", "use:WATERFALL"), { "ROUTE_27:3" })
-- Mt. Mortar: west and east mouths; the middle one leads up the waterfall.
-- Strict: SURF and STRENGTH across, WATERFALL from the middle.
known("mortar:west", needs("use:SURF", "use:STRENGTH"), { "ROUTE_42:3" })
known("mortar:east", needs("use:SURF", "use:STRENGTH"), { "ROUTE_42:5" })
known("mortar:middle", needs("use:SURF", "use:WATERFALL"), { "ROUTE_42:4" })
-- Ice Path: HM07's ball is on 1F by the Route 44 mouth; B1F's STRENGTH
-- boulders stand before the Blackthorn side (keyitems ICE_PATH).
known("icepath:route44", {}, { "ROUTE_44:1" })
known("icepath:blackthorn", needs("use:STRENGTH"), { "BLACKTHORN_CITY:7" })
-- Dark Cave: closed between its mouths (ROCK SMASH rocks and FLASH; ROCK
-- SMASH is a TM the model does not track).
known("darkcave:route31", NEVER, { "ROUTE_31:3" })
known("darkcave:route46", NEVER, { "ROUTE_46:3" })
known("darkcave:route45", NEVER, { "ROUTE_45:1" })
-- Whirl Islands: four separate caves as far as the model knows.
known("whirl:nw", NEVER, { "ROUTE_41:1" })
known("whirl:ne", NEVER, { "ROUTE_41:2" })
known("whirl:sw", NEVER, { "ROUTE_41:3" })
known("whirl:se", NEVER, { "ROUTE_41:4" })
-- Victory Road and its gate: the officer checks eight badges
-- (VictoryRoadGate.asm); strict: every field move usable as keyitems LEAGUE.
-- The Route 22 and Route 28 doors are closed (Kanto, after the League).
known("victory:route26", {}, { "ROUTE_26:1" })
known("victory:indigo", needs(M.JOHTO_BADGES, ALL_USES), { "ROUTE_23:3", "ROUTE_23:4" })
known("victory:route22", NEVER, { "ROUTE_22:1" })
known("victory:route28", NEVER, { "ROUTE_28:2" })
-- The League is entered from Indigo Plateau only.
known("league:indigo", {}, { "ROUTE_23:1", "ROUTE_23:2" })
-- Port passages are corridors; the ship itself needs the S.S.TICKET (closed).
known("port:olivine", {}, { "OLIVINE_CITY:10", "OLIVINE_CITY:11", "OLIVINE_PORT:1" })
known("port:vermilion", {}, { "VERMILION_CITY:8", "VERMILION_CITY:9", "VERMILION_PORT:1" })
known("ship:olivine", NEVER, { "OLIVINE_PORT:2" })
known("ship:vermilion", NEVER, { "VERMILION_PORT:2" })
-- Magnet Train: needs the PASS (closed).
known("train:goldenrod", NEVER, { "GOLDENROD_CITY:5" })
known("train:saffron", NEVER, { "SAFFRON_CITY:6" })
-- National Park gates: open to the park; the contest map only by script.
known("parkgate35:route", {}, { "ROUTE_35:3", "NATIONAL_PARK:3", "NATIONAL_PARK:4" })
known("parkgate35:contest", NEVER, { "NATIONAL_PARK_BUG_CONTEST:3", "NATIONAL_PARK_BUG_CONTEST:4" })
known("parkgate36:route", {}, { "ROUTE_36:1", "ROUTE_36:2", "NATIONAL_PARK:1", "NATIONAL_PARK:2" })
known("parkgate36:contest", NEVER, { "NATIONAL_PARK_BUG_CONTEST:1", "NATIONAL_PARK_BUG_CONTEST:2" })
-- Tin Tower's top opens onto its roof only after the story (closed).
known("tintower:ecruteak", {}, { "ECRUTEAK_CITY:12" })
known("tintower:roof", NEVER, { "TIN_TOWER_ROOF:1" })
M.KNOWN_DOORS = KNOWN

-- ---------------------------------------------------------------- story steps and HMs

-- Story steps.  `at` is where it happens: a map inside a complex ("IN:MAP",
-- reached when that complex's hub is) or a region ("AT:REGION").  `needs`
-- repeats keyitems.lua M.EVENTS where it has the same step.
M.EVENTS = {
  { id = "EVENT_STARTER", at = "IN:ELMS_LAB", needs = {}, why = "ElmsLab: the starter" },
  { id = "BADGE_ZEPHYR", at = "IN:VIOLET_GYM", needs = {}, why = "keyitems ZEPHYR" },
  { id = "EVENT_SLOWPOKE_WELL", at = "IN:SLOWPOKE_WELL_B1F", needs = { "BADGE_ZEPHYR" },
    why = "SlowpokeWellB1F: Proton; keyitems AZALEA needs ZEPHYR" },
  { id = "BADGE_HIVE", at = "IN:AZALEA_GYM", needs = { "EVENT_SLOWPOKE_WELL" }, why = "keyitems HIVE" },
  { id = "BADGE_PLAIN", at = "IN:GOLDENROD_GYM", needs = {}, why = "keyitems PLAIN" },
  { id = "EVENT_FLORIA", at = "AT:VIOLET", needs = { "BADGE_PLAIN" },
    why = "Route 36: FLORIA by SUDOWOODO on the Violet side; strict: after the PLAINBADGE" },
  { id = "EVENT_SQUIRTBOTTLE", at = "IN:GOLDENROD_FLOWER_SHOP", needs = { "BADGE_PLAIN", "EVENT_FLORIA" },
    why = "GoldenrodFlowerShop: after FLORIA and the PLAINBADGE (keyitems ECRUTEAK)" },
  { id = "EVENT_BURNED_TOWER", at = "IN:BURNED_TOWER_1F", needs = {},
    why = "BurnedTower1F/B1F: the beasts; no HM" },
  { id = "BADGE_FOG", at = "IN:ECRUTEAK_GYM", needs = { "EVENT_BURNED_TOWER" }, why = "keyitems FOG" },
  { id = "EVENT_LIGHTHOUSE", at = "IN:OLIVINE_LIGHTHOUSE_1F", needs = {},
    why = "OlivineLighthouse6F: Jasmine asks for medicine" },
  { id = "EVENT_SECRETPOTION", at = "IN:CIANWOOD_PHARMACY", needs = { "EVENT_LIGHTHOUSE" },
    why = "CianwoodPharmacy: the SECRETPOTION once Jasmine has asked" },
  { id = "BADGE_MINERAL", at = "IN:OLIVINE_GYM", needs = { "EVENT_SECRETPOTION" }, why = "keyitems MINERAL" },
  { id = "BADGE_STORM", at = "IN:CIANWOOD_GYM", needs = needs("use:STRENGTH"),
    why = "keyitems STORM: STRENGTH boulders in front of Chuck" },
  { id = "EVENT_RED_GYARADOS", at = "AT:LAKE_OF_RAGE", needs = needs("use:SURF"),
    why = "LakeOfRage: the red GYARADOS is on the water (keyitems HIDEOUT)" },
  { id = "EVENT_HIDEOUT", at = "IN:MAHOGANY_MART_1F",
    needs = needs("EVENT_RED_GYARADOS", "BADGE_STORM", "BADGE_MINERAL", "use:SURF", "use:STRENGTH",
      "use:CUT"),
    why = "TeamRocketBaseB1F-B3F with Lance; strict as keyitems MAHOGANY and HIDEOUT" },
  { id = "BADGE_GLACIER", at = "IN:MAHOGANY_GYM", needs = { "EVENT_HIDEOUT" }, why = "keyitems GLACIER" },
  { id = "EVENT_RADIO_TOWER", at = "IN:RADIO_TOWER_1F",
    needs = needs(SEVEN_BADGES, "IN:GOLDENROD_UNDERGROUND_WAREHOUSE"),
    why = "the takeover starts at seven badges (keyitems RADIO); the CARD KEY is in the "
      .. "Underground warehouse" },
  { id = "EVENT_CLAIR", at = "IN:BLACKTHORN_GYM_1F", needs = needs("EVENT_RADIO_TOWER", "use:STRENGTH"),
    why = "BlackthornCity: Clair is out until the Radio Tower is cleared; gym boulders" },
  { id = "EVENT_DRAGON_SHRINE", at = "IN:DRAGON_SHRINE", needs = needs("EVENT_CLAIR", "use:SURF", "use:WHIRLPOOL"),
    why = "DragonsDenB1F: water to the shrine; strict: WHIRLPOOL" },
  { id = "BADGE_RISING", at = "IN:BLACKTHORN_GYM_1F",
    needs = needs("EVENT_DRAGON_SHRINE", "EVENT_RADIO_TOWER", "use:CUT", "use:SURF", "use:STRENGTH",
      "use:WHIRLPOOL", "use:FLY", "use:FLASH", "WATERFALL"),
    why = "keyitems RISING: strict, every other HM" },
  { id = "EVENT_LEAGUE", at = "IN:INDIGO_PLATEAU_POKECENTER_1F", needs = needs(M.JOHTO_BADGES, ALL_USES),
    why = "keyitems LEAGUE: the goal" },
}
M.GOAL = "EVENT_LEAGUE"

-- HM locations, by keyitems.lua's site ids (hmPlacement and
-- ctx.shared.keyitems use them).  `item` is the vanilla HM.
M.SITES = {
  { id = "SPROUT_TOWER_3F", at = "IN:SPROUT_TOWER_3F", item = "HM_FLASH", needs = {} },
  { id = "ILEX_FOREST", at = "IN:ILEX_FOREST", item = "HM_CUT", needs = { "BADGE_HIVE" } },
  { id = "DANCE_THEATER", at = "IN:DANCE_THEATER", item = "HM_SURF", needs = {} },
  { id = "OLIVINE_CAFE", at = "IN:OLIVINE_CAFE", item = "HM_STRENGTH", needs = {} },
  { id = "CIANWOOD_CITY", at = "AT:CIANWOOD", item = "HM_FLY", needs = { "BADGE_STORM" } },
  { id = "TEAM_ROCKET_BASE_B2F", at = "IN:TEAM_ROCKET_BASE_B2F", item = "HM_WHIRLPOOL",
    needs = { "EVENT_HIDEOUT" } },
  { id = "ICE_PATH_1F", at = "IN:ICE_PATH_1F", item = "HM_WATERFALL", needs = {} },
}

function M.vanillaHms()
  local out = {}
  for _, site in ipairs(M.SITES) do out[site.id] = site.item end
  return out
end

M.START = "NEW_BARK"

-- ---------------------------------------------------------------- the model

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function doorKey(door) return tostring(door.map) .. ":" .. tostring(door.warp) end

local function edgeKey(a, b) if a < b then return a .. "|" .. b end return b .. "|" .. a end

function M.model(data, graph)
  assert(type(graph) == "table" and type(graph.doors) == "table" and type(graph.complexes) == "table",
    "maprules.model needs a graph from mapgraph")
  local mapsData = type(data) == "table" and type(data.gen2Maps) == "table" and data.gen2Maps or nil
  local rules = { fixed = {}, regions = {}, needs = {}, doorRegion = {}, complexNeeds = {},
    unlocated = {} }

  -- regions
  local regionOfMap, johtoMap = {}, {}
  for _, rid in ipairs(sortedKeys(M.REGIONS)) do
    rules.regions[rid] = { maps = {}, doors = {} }
    for _, map in ipairs(M.REGIONS[rid]) do
      regionOfMap[map] = rid
      johtoMap[map] = true
      rules.regions[rid].maps[#rules.regions[rid].maps + 1] = map
    end
  end
  local outdoor = graph.outdoor or {}
  for _, map in ipairs(sortedKeys(outdoor)) do
    if outdoor[map] and not regionOfMap[map] then
      regionOfMap[map] = map
      rules.regions[map] = rules.regions[map] or { maps = { map }, doors = {} }
    end
  end

  -- doors, in a fixed order
  local doorIds = sortedKeys(graph.doors)
  local doorByKey = {}
  for _, id in ipairs(doorIds) do
    local door = graph.doors[id]
    local key = doorKey(door)
    doorByKey[key] = id
    local rid = M.DOOR_REGION[key] or regionOfMap[door.map]
    if not rid then
      rid = door.map
      regionOfMap[door.map] = rid
      rules.regions[rid] = rules.regions[rid] or { maps = { door.map }, doors = {} }
    end
    rules.doorRegion[id] = rid
    local region = rules.regions[rid]
    region.doors[#region.doors + 1] = id
  end

  -- edges
  local edges = {}
  for _, e in ipairs(M.EDGES) do
    if rules.regions[e[1]] and rules.regions[e[2]] then
      rules.needs[edgeKey(e[1], e[2])] = e[3]
      edges[#edges + 1] = { a = e[1], b = e[2], needs = e[3] }
    end
  end

  -- fixed complexes
  local warpTargets = M.scriptWarpTargets(data)
  local complexIds = sortedKeys(graph.complexes)
  local complexOfMap = {}
  for _, cid in ipairs(complexIds) do
    local c = graph.complexes[cid]
    for _, map in ipairs(c.maps or {}) do
      complexOfMap[map] = cid
      if not rules.fixed[cid] then
        if FIXED[map] then
          rules.fixed[cid] = FIXED[map]
        elseif warpTargets[map] then
          rules.fixed[cid] = "a story script warps the player into " .. map
        end
      end
    end
  end

  -- moving through complexes
  local function environment(map)
    local m = mapsData and mapsData[map]
    return m and m.environment
  end
  for _, cid in ipairs(complexIds) do
    local c = graph.complexes[cid]
    local doors = {}
    for _, id in ipairs(c.doors or {}) do if graph.doors[id] then doors[#doors + 1] = id end end
    table.sort(doors)
    local exits, sides = {}, {}
    local isKnown = false
    for _, id in ipairs(doors) do if KNOWN[doorKey(graph.doors[id])] then isKnown = true end end
    if isKnown then
      for _, id in ipairs(doors) do
        local entry = KNOWN[doorKey(graph.doors[id])]
        sides[id] = entry and entry.side or ("closed:" .. id)
        exits[id] = entry and entry.needs or NEVER
      end
    else
      -- A Johto gate is an open corridor.
      local gate = #doors > 0
      for _, map in ipairs(c.maps or {}) do
        local env = environment(map) or c.environment
        if env ~= "GATE" then gate = false end
      end
      for _, id in ipairs(doors) do if not johtoMap[graph.doors[id].map] then gate = false end end
      local groups, count = {}, 0
      for _, id in ipairs(doors) do
        local rid = rules.doorRegion[id]
        if not groups[rid] then groups[rid] = true; count = count + 1 end
      end
      for _, id in ipairs(doors) do
        if gate or count <= 1 then
          sides[id], exits[id] = "open", {}
        else
          -- Doors in different regions of a complex the model does not know:
          -- closed between them, open beside each other.
          sides[id], exits[id] = rules.doorRegion[id], NEVER
        end
      end
    end
    rules.complexNeeds[cid] = { exits = exits, side = sides, known = isKnown }
  end

  -- where each story step and HM site is
  local function located(at)
    local kind, name = at:match("^(%u+):(.+)$")
    if kind == "IN" then return complexOfMap[name] ~= nil end
    return rules.regions[name] ~= nil
  end
  for _, list in ipairs({ M.EVENTS, M.SITES }) do
    for _, step in ipairs(list) do
      if not located(step.at) then rules.unlocated[#rules.unlocated + 1] = step.id .. " (" .. step.at .. ")" end
    end
  end
  for _, step in ipairs(M.EVENTS) do
    for _, need in ipairs(step.needs) do
      if need:match("^IN:") and not located(need) then
        rules.unlocated[#rules.unlocated + 1] = step.id .. " needs " .. need
      end
    end
  end

  -- ------------------------------------------------ compiled for canWin
  local nDoors = #doorIds
  local doorIndex = {}
  for i, id in ipairs(doorIds) do doorIndex[id] = i end
  local doorRegionList, doorComplex, doorExit, doorSide = {}, {}, {}, {}
  for i, id in ipairs(doorIds) do
    local door = graph.doors[id]
    doorRegionList[i] = rules.doorRegion[id]
    doorComplex[i] = door.complex
    local cn = rules.complexNeeds[door.complex]
    doorExit[i] = cn and cn.exits[id] or NEVER
    doorSide[i] = cn and cn.side[id] or ("closed:" .. id)
  end
  -- doors of each complex side, and each complex's doors and maps
  local sideDoors, complexDoors, complexMaps = {}, {}, {}
  for i = 1, nDoors do
    local cid = doorComplex[i]
    if cid then
      local k = cid .. "\0" .. doorSide[i]
      sideDoors[k] = sideDoors[k] or {}
      table.insert(sideDoors[k], i)
      complexDoors[cid] = complexDoors[cid] or {}
      table.insert(complexDoors[cid], i)
    end
  end
  for _, cid in ipairs(complexIds) do
    local list = {}
    for _, map in ipairs(graph.complexes[cid].maps or {}) do list[#list + 1] = "IN:" .. map end
    complexMaps[cid] = list
  end
  local graphEntrances = type(graph.entrances) == "table" and next(graph.entrances) ~= nil
    and graph.entrances or nil
  local fixedDoor = {}
  for i = 1, nDoors do if doorComplex[i] and rules.fixed[doorComplex[i]] then fixedDoor[i] = true end end

  local function reach(placement, hmPlacement)
    placement = placement or {}
    local hms = hmPlacement or M.vanillaHms()
    -- dest[i] = the door whose side door i now leads into
    local dest, exitTo = {}, {}
    for i = 1, nDoors do dest[i] = i end
    local function lead(from, to)
      local a, b = doorIndex[from], doorIndex[to]
      if not a then return "the placement names no door " .. tostring(from) end
      if not b then return "the placement leads to no door " .. tostring(to) end
      if a ~= b and (fixedDoor[a] or fixedDoor[b]) then
        return "the placement moves a fixed complex's door " .. (fixedDoor[a] and from or to)
      end
      dest[a] = b
    end
    -- placement.entrances (mapplacer): every tile of entrance E leads to the
    -- first tile of entrance T.  Otherwise placement[doorId] = doorId.
    local byEntrance = type(placement.entrances) == "table" and graphEntrances
    if byEntrance then
      for from, to in pairs(placement.entrances) do
        local e, t = graphEntrances[from], graphEntrances[to]
        if not e then return nil, "the placement names no entrance " .. tostring(from) end
        if not t or not t.doors[1] then return nil, "the placement leads to no entrance " .. tostring(to) end
        for _, tile in ipairs(e.doors) do
          local err = lead(tile, from == to and tile or t.doors[1])
          if err then return nil, err end
        end
      end
    else
      for from, to in pairs(placement) do
        if from ~= "entrances" then
          local err = lead(from, to)
          if err then return nil, err end
        end
      end
    end
    for i = 1, nDoors do
      local p = dest[i]
      exitTo[p] = exitTo[p] or {}
      table.insert(exitTo[p], i)
    end

    local have, regions, entered, sideIn, hubs = {}, { [M.START] = true }, {}, {}, {}
    local doneEvent, doneSite = {}, {}
    local function met(list)
      for j = 1, #list do if not have[list[j]] then return false end end
      return true
    end
    local function at(where)
      if where:sub(1, 3) == "AT:" then return regions[where:sub(4)] == true end
      return have[where] == true
    end
    local changed = true
    local function reachRegion(rid)
      if rid and not regions[rid] then regions[rid] = true; changed = true end
    end
    local function reachSide(i)
      if sideIn[i] then return end
      sideIn[i] = true
      changed = true
      local cid = doorComplex[i]
      if cid then
        for _, j in ipairs(sideDoors[cid .. "\0" .. doorSide[i]]) do
          if not sideIn[j] then sideIn[j] = true end
        end
      end
    end
    while changed do
      changed = false
      for _, e in ipairs(edges) do
        if (regions[e.a] or regions[e.b]) and not (regions[e.a] and regions[e.b]) and met(e.needs) then
          reachRegion(e.a); reachRegion(e.b)
        end
      end
      for i = 1, nDoors do
        if not entered[i] and regions[doorRegionList[i]] then
          entered[i] = true
          changed = true
          reachSide(dest[i])
        end
      end
      for i = 1, nDoors do
        if sideIn[i] then
          local cid = doorComplex[i]
          if cid and not hubs[cid] and met(doorExit[i]) then
            hubs[cid] = true
            changed = true
            for _, token in ipairs(complexMaps[cid]) do have[token] = true end
          end
          for _, a in ipairs(exitTo[i] or {}) do reachRegion(doorRegionList[a]) end
        end
      end
      for cid in pairs(hubs) do
        for _, j in ipairs(complexDoors[cid] or {}) do
          if not sideIn[j] and met(doorExit[j]) then reachSide(j) end
        end
      end
      for _, ev in ipairs(M.EVENTS) do
        if not doneEvent[ev.id] and at(ev.at) and met(ev.needs) then
          doneEvent[ev.id] = true
          have[ev.id] = true
          changed = true
        end
      end
      for _, site in ipairs(M.SITES) do
        if not doneSite[site.id] and at(site.at) and met(site.needs) then
          doneSite[site.id] = true
          changed = true
          local hm = M.HMS[hms[site.id] or ""]
          if hm then have[hm.move] = true; have[hms[site.id]] = true end
        end
      end
    end
    return { have = have, regions = regions, hubs = hubs, events = doneEvent, sites = doneSite }
  end
  rules.reach = reach

  function rules.canWin(placement, hmPlacement)
    local state, why = reach(placement, hmPlacement)
    if not state then return false, why end
    local missing = {}
    for _, badge in ipairs(M.JOHTO_BADGES) do
      if not state.have[badge] then missing[#missing + 1] = badge end
    end
    if not state.have[M.GOAL] then missing[#missing + 1] = M.GOAL end
    if #missing > 0 then return false, "not reachable: " .. table.concat(missing, ", ") end
    return true
  end

  return rules
end

function M.install(mod, ctx)
  ctx.lib = ctx.lib or {}
  ctx.lib.mapRules = { model = M.model }
end

return M
