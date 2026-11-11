-- Deterministic random numbers for the randomizer.
--
-- Every choice comes from a stream named after what it decides (the run's seed,
-- then a name such as "wild", then any keys such as a map and a slot).  The same
-- seed and the same names always give the same answers, on every device and in
-- every order the game asks them, which is what keeps one save's randomized world
-- the same for the whole playthrough without storing every answer.
--
-- Pure Lua arithmetic only (no os.time, no math.random), so it is the same on
-- LuaJIT everywhere.

local Rng = {}
Rng.__index = Rng

local MOD32 = 4294967296

-- FNV-1a over the bytes of a string, as a 32-bit number.
local function hash(text, start)
  local h = start or 2166136261
  for i = 1, #text do
    h = (h - h % 1) -- keep it whole
    local byte = text:byte(i)
    -- xor without the bit library: same result, portable
    local a, b, x, bitValue = h % 256, byte, 0, 1
    for _ = 1, 8 do
      local abit, bbit = a % 2, b % 2
      if abit ~= bbit then x = x + bitValue end
      a, b, bitValue = (a - abit) / 2, (b - bbit) / 2, bitValue * 2
    end
    h = (h - h % 256) + x
    -- h * 16777619 mod 2^32, split so no product passes 2^53 (16777619 = 2^24 + 403)
    h = ((h % 256) * 16777216 + h * 403) % MOD32
  end
  return h
end
Rng.hash = hash

-- a xor b for whole numbers below 2^32, without the bit library
local function xor32(a, b)
  local x, bitValue = 0, 1
  for _ = 1, 32 do
    local abit, bbit = a % 2, b % 2
    if abit ~= bbit then x = x + bitValue end
    a, b, bitValue = (a - abit) / 2, (b - bbit) / 2, bitValue * 2
  end
  return x
end

-- a * c mod 2^32, split so no product passes 2^53
local function mul32(a, c)
  local lo, hi = c % 65536, (c - c % 65536) / 65536
  return (a * lo + ((a * hi) % 65536) * 65536) % MOD32
end

-- MurmurHash3's 32-bit finalizer.  FNV-1a followed by a linear step is close to
-- linear in the last bytes of the key, so streams whose keys differ only at the
-- end (slot 1, slot 2, ...) started from states a fixed distance apart and gave
-- related answers.  This scrambles every bit of the state into every other.
function Rng.mix(h)
  h = xor32(h, (h - h % 65536) / 65536)
  h = mul32(h, 0x85EBCA6B)
  h = xor32(h, (h - h % 8192) / 8192)
  h = mul32(h, 0xC2B2AE35)
  h = xor32(h, (h - h % 65536) / 65536)
  return h
end

-- A stream for `seed` and any number of keys (strings or numbers): the first
-- generator, kept unchanged for saves started before 2026-11-10 (version 1),
-- whose randomized world must stay as it was.  New saves use Rng.mixedStream.
function Rng.stream(seed, ...)
  local h = hash(tostring(seed))
  for i = 1, select("#", ...) do
    h = hash("|" .. tostring(select(i, ...)), h)
  end
  -- never zero, which would stall the generator
  return setmetatable({ state = h == 0 and 1 or h }, Rng)
end

-- Version 2: the same key hash, then Rng.mix, so streams with nearby keys are
-- independent.
function Rng.mixedStream(seed, ...)
  local stream = Rng.stream(seed, ...)
  local h = Rng.mix(stream.state)
  stream.state = h == 0 and 1 or h
  return stream
end

-- A stream for a save made with generator `version` (1 when it has none).
function Rng.streamFor(version, seed, ...)
  if (tonumber(version) or 1) >= 2 then return Rng.mixedStream(seed, ...) end
  return Rng.stream(seed, ...)
end

-- The next number in [0, 1).  A 32-bit linear congruential step (Numerical
-- Recipes' constants), which is exact in doubles.
function Rng:next()
  self.state = (self.state * 1664525 + 1013904223) % MOD32
  return self.state / MOD32
end

-- A whole number from lo to hi, both included.
function Rng:int(lo, hi)
  return lo + math.floor(self:next() * (hi - lo + 1))
end

function Rng:pick(list)
  if #list == 0 then return nil end
  return list[self:int(1, #list)]
end

-- A shuffled copy; the list itself is left alone.
function Rng:shuffled(list)
  local copy = {}
  for i = 1, #list do copy[i] = list[i] end
  for i = #copy, 2, -1 do
    local j = self:int(1, i)
    copy[i], copy[j] = copy[j], copy[i]
  end
  return copy
end

return Rng
