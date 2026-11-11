-- luajit launcher/mods/crystal_randomizer/tests/rng_test.lua   (from the repository root)
--
-- The generator (rng.lua): version 1 must never change, because saves made with
-- it keep their world; version 2 must give streams with nearby keys answers that
-- are not related.  Also checks version 2's starter triangle (modules/starters.lua
-- fairTriangle) on a small type chart, and, with CRYSTAL_RANDOMIZER_CACHE set to
-- an imported Crystal cache's data/generated folder, how evenly it spreads the
-- real three-stage starters.
local Rng = dofile("launcher/mods/crystal_randomizer/rng.lua")
local Starters = dofile("launcher/mods/crystal_randomizer/modules/starters.lua")

local failures, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

-- ------------------------------------------------------------ version 1 is frozen
-- Values from the generator as it was before version 2 existed (commit before 2026-11-10's fix).
ok(Rng.stream("123456", "starters").state == 1676822778, "version 1 stream state unchanged")
ok(Rng.streamFor(nil, "123456", "starters").state == 1676822778, "a save with no version uses version 1")
ok(Rng.streamFor(1, "123456", "starters").state == 1676822778, "version 1 by number")

-- ------------------------------------------------------------ the mixer
ok(Rng.mix(1) == 0x514E28B7, "Rng.mix is MurmurHash3's fmix32 (fmix32(1) = 514E28B7)")
ok(Rng.mix(0) == 0, "fmix32(0) = 0")
ok(Rng.streamFor(2, "123456", "starters").state == Rng.mixedStream("123456", "starters").state,
  "version 2 is the mixed stream")

-- ------------------------------------------------------------ nearby keys
local pool = {}
for i = 1, 100 do pool[i] = i end
local function adjacentEqual(make)
  local same, n = 0, 0
  for s = 1, 4000 do
    local seed = ("%06d"):format((s * 7919) % 1000000)
    local prev
    for slot = 1, 10 do
      local p = make(seed, slot):pick(pool)
      if prev then n = n + 1; if p == prev then same = same + 1 end end
      prev = p
    end
  end
  return same / n
end
local v1 = adjacentEqual(function(seed, slot) return Rng.stream(seed, "wild", "ROUTE_29", slot) end)
local v2 = adjacentEqual(function(seed, slot) return Rng.mixedStream(seed, "wild", "ROUTE_29", slot) end)
print(("  neighbouring slots picking the same of 100: version 1 %.2f%%, version 2 %.2f%% (chance 1%%)")
  :format(100 * v1, 100 * v2))
ok(v2 > 0.007 and v2 < 0.013, "version 2: neighbouring slots agree about as often as chance")

-- ------------------------------------------------------------ fair triangle, small chart
local function mon(id, index, t1, t2) return { id = id, index = index, types = { t1, t2 or t1 } } end
local P = {
  LEAF = mon("LEAF", 1, "GRASS"), FLAME = mon("FLAME", 2, "FIRE"), WAVE = mon("WAVE", 3, "WATER"),
  SPROUT = mon("SPROUT", 4, "GRASS"), EMBER = mon("EMBER", 5, "FIRE"), DROP = mon("DROP", 6, "WATER"),
  PLAIN = mon("PLAIN", 7, "NORMAL"),
}
local chart = Starters.typeTable({ matchups = {
  { attacker = "FIRE", defender = "GRASS", multiplier = 20 }, { attacker = "WATER", defender = "FIRE", multiplier = 20 },
  { attacker = "GRASS", defender = "WATER", multiplier = 20 }, { attacker = "GRASS", defender = "FIRE", multiplier = 5 },
  { attacker = "FIRE", defender = "WATER", multiplier = 5 }, { attacker = "WATER", defender = "GRASS", multiplier = 5 },
} })
local small = { "LEAF", "FLAME", "WAVE", "SPROUT", "EMBER", "DROP", "PLAIN" }
ok(#Starters.triangles(small, P, chart) == 8, "every grass-fire-water triangle listed once (2x2x2)")
local seen = {}
for s = 1, 300 do
  local got = Starters.fairTriangle(Rng.mixedStream(tostring(s), "starters"), small, P, chart)
  ok(got ~= nil, "a triangle found")
  if got then
    for ball, rival in pairs(Starters.RIVAL_BALL) do
      ok(Starters.strongAgainst(chart, P[got[rival]], P[got[ball]]),
        "seed " .. s .. ": the rival's ball beats the player's " .. ball)
    end
    for _, id in pairs(got) do seen[id] = (seen[id] or 0) + 1 end
  end
end
ok(seen.PLAIN == nil, "a species in no triangle is never chosen")
for _, id in ipairs({ "LEAF", "FLAME", "WAVE", "SPROUT", "EMBER", "DROP" }) do
  ok((seen[id] or 0) > 110 and (seen[id] or 0) < 190, id .. " comes up about half the time: " .. tostring(seen[id]))
end
ok(Starters.fairTriangle(Rng.mixedStream("x"), { "PLAIN", "LEAF" }, P, chart) == nil, "no triangle: nil")

-- ------------------------------------------------------------ real Crystal data
local cache = os.getenv("CRYSTAL_RANDOMIZER_CACHE")
if cache and cache ~= "" then
  local pokemon = dofile(cache .. "/pokemon.lua")
  local real = Starters.typeTable(dofile(cache .. "/type_chart.lua"))
  local species = Starters.species(pokemon)
  local function spread(fair)
    local counts, n = {}, 3000
    for s = 1, n do
      local seed = ("%06d"):format((s * 7919) % 1000000)
      local ctx = { rng = function(...) return Rng.streamFor(fair and 2 or 1, seed, ...) end }
      local got = Starters.chooseStarters(ctx, pokemon, { stages = true, triangle = true, fair = fair }, real, species)
      for _, id in pairs(got) do counts[id] = (counts[id] or 0) + 1 end
    end
    local most = 0
    for _, c in pairs(counts) do most = math.max(most, c / n) end
    return most
  end
  local before, after = spread(false), spread(true)
  print(("  three-stage starters with a triangle: the most common species is in %.0f%% of seeds before, %.0f%% after")
    :format(100 * before, 100 * after))
  ok(after < before - 0.05, "version 2 spreads the real starters more evenly")
end

print(("rng_test: %d checks, %d failures"):format(checks, failures))
if failures > 0 then os.exit(1) end
