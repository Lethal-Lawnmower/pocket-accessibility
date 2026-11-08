-- What one seed did: the early routes' wild POKéMON, the starters, the first
-- trainers and the gym leaders, vanilla beside randomized.  Runs on a disposable
-- profile with the mod installed; the seed and answers come from the environment,
-- so no real save is opened.  Silent; read the REPORT lines.
--   RANDOMIZER_SEED=876506  (every answer YES unless RANDOMIZER_NO=key,key)
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  if not L.settle(3000, true) then U.log("FAIL", "never reached the free world") return end
  local data = game.data
  local Runtime = require("src.mods.Runtime")
  local Trainers = require("src.world.gen2.Trainers")

  local ROUTES = { "ROUTE_29", "ROUTE_30", "ROUTE_31", "ROUTE_46", "ROUTE_32", "ROUTE_33",
    "DARK_CAVE_VIOLET_ENTRANCE", "SPROUT_TOWER_2F", "UNION_CAVE_1F", "ILEX_FOREST", "ROUTE_34" }
  local TRAINERS = { { "RIVAL1", 1 }, { "RIVAL1", 2 }, { "RIVAL1", 3 }, { "YOUNGSTER", 1 }, { "BUG_CATCHER", 1 },
    { "FALKNER", 1 }, { "BUGSY", 1 }, { "WHITNEY", 1 }, { "MORTY", 1 }, { "CHUCK", 1 },
    { "JASMINE", 1 }, { "PRYCE", 1 }, { "CLAIR", 1 } }

  local function grassLine(mapId)
    local grass = data.gen2Encounters and data.gen2Encounters.grass and data.gen2Encounters.grass[mapId]
    if not grass then return nil end
    local seen, order = {}, {}
    for _, time in ipairs({ "MORN", "DAY", "NITE" }) do
      local rows = grass[time] or (grass.slots and grass.slots[time]) or {}
      for _, row in ipairs(type(rows) == "table" and rows or {}) do
        local species = type(row) == "table" and (row.species or row[2]) or nil
        if species and not seen[species] then seen[species] = true; order[#order + 1] = tostring(species) end
      end
    end
    return table.concat(order, ", ")
  end

  local function trainerLine(classId, member)
    local class = data.gen2Trainers and data.gen2Trainers.classes and data.gen2Trainers.classes[classId]
    if not class then return nil end
    local record = game.world:trainerParty(class.index, member)
    if not record or not record.roster then return nil end
    local party = Trainers.party(data, record)
    local memberId = record.memberId or record.id or member
    local fought = Runtime.call("trainer.party", function(_, _, p) return p end, classId, memberId, party) or party
    local parts = {}
    for _, mon in ipairs(fought) do parts[#parts + 1] = tostring(mon.species) .. " " .. tostring(mon.level) end
    return table.concat(parts, ", "), tostring(memberId)
  end

  local vanilla = { routes = {}, trainers = {} }
  for _, mapId in ipairs(ROUTES) do vanilla.routes[mapId] = grassLine(mapId) end
  for _, t in ipairs(TRAINERS) do vanilla.trainers[t[1] .. t[2]] = trainerLine(t[1], t[2]) end

  local options = {}
  for _, key in ipairs({ "wild", "wild_similar", "trainers", "trainers_similar", "starters", "gifts",
      "items", "items_hidden", "pokemon_types", "pokemon_moves" }) do options[key] = true end
  for key in (os.getenv("RANDOMIZER_NO") or ""):gmatch("[^,]+") do options[key] = false end
  local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
  end
  local save = copy(game.save)
  save.modData = save.modData or {}
  save.modData.crystal_randomizer = { seed = os.getenv("RANDOMIZER_SEED") or "876506", options = options, version = 1 }
  game:continueGame(save)
  L.settle(600, true)

  for _, mapId in ipairs(ROUTES) do
    U.log("REPORT", "wild", mapId, "was: " .. tostring(vanilla.routes[mapId]), "now: " .. tostring(grassLine(mapId)))
  end
  for _, t in ipairs(TRAINERS) do
    local now, memberId = trainerLine(t[1], t[2])
    U.log("REPORT", "trainer", t[1] .. " " .. tostring(memberId), "was: " .. tostring(vanilla.trainers[t[1] .. t[2]]),
      "now: " .. tostring(now))
  end
  local chik = data.pokemon.CHIKORITA
  U.log("REPORT", "types", "SNORLAX", table.concat(data.pokemon.SNORLAX.types or {}, "/"))
  U.log("DONE")
end
