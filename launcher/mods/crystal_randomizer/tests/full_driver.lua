-- The whole randomizer in a real Crystal run: the mod installed in a disposable
-- profile's mods folder, a New Game through Oak's real speech answering YES to
-- everything, then Continue from a copy of that save, then a copy without the
-- randomizer's data.  Silent; read the PASS, FAIL and RESULT lines.
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=launcher/mods/crystal_randomizer/tests/full_driver.lua
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  if not L.settle(3000, true) then U.log("FAIL", "never reached the free world") return end

  local data = game.data
  local function serialize(value, depth)
    depth = depth or 0
    if type(value) ~= "table" or depth > 6 then return tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. "=" .. serialize(value[key], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  local function snapshot()
    local route = data.gen2Encounters and data.gen2Encounters.grass and data.gen2Encounters.grass.ROUTE_29
    local chik = data.pokemon and data.pokemon.CHIKORITA
    local balls = {}
    local map = data.gen2Maps and data.gen2Maps.ROUTE_29
    for i, object in ipairs(map and map.objects or {}) do
      if object.itemball then balls[#balls + 1] = i .. ":" .. tostring(object.itemball.item) end
    end
    return {
      wild = serialize(route),
      types = chik and serialize(chik.types) or "?",
      moves = chik and serialize(chik.levelMoves) or "?",
      balls = table.concat(balls, " "),
    }
  end
  local function same(a, b) return a.wild == b.wild and a.types == b.types and a.moves == b.moves and a.balls == b.balls end

  local vanilla = snapshot()
  U.log("RESULT", "vanilla", vanilla.types, vanilla.balls)

  -- New Game through Oak: A answers YES to every question and picks the first name.
  L.said = {}
  game:newGame()
  local spoken = {}
  local finished = false
  -- RAND_DOWNS: how many times to press down on Oak's setup choice (0 RECOMMENDED,
  -- 1 EVERYTHING, 2 CHOOSE EACH)
  local downs = tonumber(os.getenv("RAND_DOWNS") or "0") or 0
  local setupHandled = false
  for _ = 1, 400 do
    local top = game.stack:top()
    if L.free() then finished = true break end
    local asked = false
    for _, line in ipairs(L.said) do
      spoken[#spoken + 1] = line
      if line:find("How shuffled", 1, true) then asked = true end
    end
    L.said = {}
    if asked and not setupHandled then
      setupHandled = true
      for _ = 1, 30 do L.tap("a", 4) if (game.stack:top() or {}).header then break end end
      for _ = 1, downs do L.tap("down", 6) end
      L.tap("a", 8)
    elseif top and top.kind == "keyboard" then L.tap("start", 8) else L.tap("a", 8) end
  end
  if not finished then finished = L.settle(3000, true) end
  U.log(finished and "PASS" or "FAIL", "New Game through Oak reached the world")
  local seedLine
  for _, line in ipairs(spoken) do
    if line:find("shuffled", 1, true) or line:find("Shuffle", 1, true) or line:find("seed", 1, true) then
      U.log("RESULT", "Oak said", line)
      if line:find("seed is", 1, true) then seedLine = line end
    end
  end

  local bucket = game.save and game.save.modData and game.save.modData.crystal_randomizer
  local seed = bucket and bucket.seed
  U.log(seed and "PASS" or "FAIL", "the save holds a seed", tostring(seed))
  U.log(seedLine and seedLine:find(tostring(seed), 1, true) and "PASS" or "FAIL", "Oak said that seed", tostring(seedLine))
  local answers = {}
  for key, value in pairs(bucket and bucket.options or {}) do answers[#answers + 1] = key .. "=" .. tostring(value) end
  table.sort(answers)
  U.log("RESULT", "answers", table.concat(answers, " "))

  local first = snapshot()
  U.log(first.wild ~= vanilla.wild and "PASS" or "FAIL", "Route 29 grass changed")
  local wantTypes = bucket and bucket.options and bucket.options.pokemon_types == true
  U.log((first.types ~= vanilla.types) == wantTypes and "PASS" or "FAIL",
    "Chikorita's types " .. (wantTypes and "changed" or "kept"), first.types)
  U.log("RESULT", "setup", tostring(bucket and bucket.options and bucket.options.setup))
  U.log(first.balls ~= vanilla.balls and "PASS" or "FAIL", "Route 29's item ball changed", first.balls)

  -- Continue from a copy of that save: the same world comes back.
  local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, v in pairs(value) do out[key] = copy(v) end
    return out
  end
  local saved = copy(game.save)
  game:continueGame(copy(saved))
  L.settle(600, true)
  U.log(same(snapshot(), first) and "PASS" or "FAIL", "Continue gives the same randomized world")

  -- A save without the randomizer's data plays as vanilla.
  local plain = copy(saved)
  plain.modData.crystal_randomizer = nil
  game:continueGame(plain)
  L.settle(600, true)
  U.log(same(snapshot(), vanilla) and "PASS" or "FAIL", "a plain save is vanilla again")

  -- And back to the randomized save.
  game:continueGame(copy(saved))
  L.settle(600, true)
  U.log(same(snapshot(), first) and "PASS" or "FAIL", "the randomized save comes back the same")
  U.log("DONE")
end
