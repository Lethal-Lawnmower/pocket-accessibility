-- Reused from the old Pocket Accessibility project (src/accessibility/Earcons.lua at
-- commit 71cdd419e) under decision 20; adapted for v0.3.98.

-- Procedural accessibility earcons.  These cues are generated at runtime so
-- the project does not redistribute the Pokémon Access WAV files whose
-- provenance/license is not stated in its repository.  Cue IDs preserve the
-- semantic contract; their sound design can be user-replaced later.

local Logger = require("src.core.Logger")

local Earcons = {}
Earcons.__index = Earcons

local PROFILES = {
  default = { 0.045, 440 },
  grass = { 0.075, 720, 520, 680 },
  bush = { 0.100, 520, 310 },
  water = { 0.120, 330, 440, 330 },
  ice = { 0.115, 1080, 820, 1180 },
  current = { 0.130, 300, 520, 760 },
  waterfall = { 0.150, 260, 420, 610, 830 },
  whirlpool = { 0.150, 520, 300, 520, 300 },
  wall = { 0.105, 145, 110 },
  pass = { 0.055, 760, 980 },
  boulder = { 0.120, 125, 165, 110 },
  door = { 0.095, 540, 760 },
  stair = { 0.115, 510, 620, 510 },
  stair_up = { 0.120, 360, 520, 720 },
  stair_down = { 0.120, 720, 520, 360 },
  hole = { 0.150, 420, 250, 120 },
  switch = { 0.080, 900, 450 },
  ledge = { 0.080, 250, 850 },
  move_up = { 0.090, 360, 520, 760 },
  move_down = { 0.090, 760, 520, 360 },
  move_left = { 0.085, 410, 310, 410 },
  move_right = { 0.085, 650, 820, 650 },
  menu = { 0.035, 880 },
}

-- File mapping for an explicitly configured external Pokemon Access sound
-- directory. These files are never copied into or redistributed with this
-- repository; their upstream provenance/license is not stated.
local SOUND_FILES = {
  default = "gb/s_default.wav",
  grass = "gb/s_grass.wav",
  bush = "gb/s_cut.wav",
  water = "common/s_water.wav",
  ice = "common/s_ice.wav",
  current = "common/s_water.wav",
  waterfall = "common/s_waterfall.wav",
  whirlpool = "gb/s_whirl.wav",
  wall = "common/s_wall.wav",
  pass = "common/pass.wav",
  boulder = "gb/s_boulder.wav",
  door = "gb/s_default.wav",
  stair = "common/s_stair.wav",
  stair_up = "common/s_stairup.wav",
  stair_down = "common/s_stairdown.wav",
  hole = "common/s_hole.wav",
  switch = "common/s_switch.wav",
  ledge = "common/s_mad.wav",
  move_up = "common/s_move_up.wav",
  move_down = "common/s_move_down.wav",
  move_left = "common/s_move.wav",
  move_right = "common/s_move.wav",
  menu = "gb/menusel.wav",
}

local function clamp(value, low, high)
  value = tonumber(value) or 0
  return math.max(low, math.min(high, value))
end

local function synth(profile, pan)
  if not (love and love.sound and love.audio) then
    return nil, "LÖVE audio is unavailable"
  end
  local rate = 22050
  local frames = math.max(1, math.floor(profile[1] * rate))
  local data = love.sound.newSoundData(frames, rate, 16, 2)
  local segments = #profile - 1
  local left = math.sqrt((1 - pan) / 2)
  local right = math.sqrt((1 + pan) / 2)
  local phase = 0
  for i = 0, frames - 1 do
    local progress = i / frames
    local segment = math.min(segments,
      math.floor(progress * segments) + 1)
    local frequency = profile[segment + 1]
    phase = phase + 2 * math.pi * frequency / rate
    local attack = math.min(1, i / math.max(1, rate * 0.004))
    local release = math.min(1, (frames - i - 1) / math.max(1, rate * 0.012))
    local sample = math.sin(phase) * math.min(attack, release) * 0.34
    data:setSample(i, 1, sample * left)
    data:setSample(i, 2, sample * right)
  end
  return love.audio.newSource(data, "static")
end

local function joinPath(root, relative)
  local separator = package.config and package.config:sub(1, 1) or "/"
  relative = relative:gsub("[/\\]", separator)
  return tostring(root):gsub("[/\\]+$", "") .. separator .. relative
end

local function loadWaveFromDisk(root, relative, pan)
  if not (love and love.filesystem and love.audio) then
    return nil, "LÖVE file/audio services are unavailable"
  end
  local path = joinPath(root, relative)
  local file, openError = io.open(path, "rb")
  if not file then return nil, openError or "sound file unavailable" end
  -- External packs are user-selected; a preflighted ZIP is not the only way
  -- this older cue loader can receive a path. Bound the actual read so a
  -- swapped or oversized WAV cannot allocate an unbounded string first.
  local maxBytes = 4 * 1024 * 1024
  local bytes = file:read(maxBytes + 1)
  file:close()
  if type(bytes) ~= "string" or #bytes < 44 or #bytes > maxBytes
     or bytes:sub(1, 4) ~= "RIFF" or bytes:sub(9, 12) ~= "WAVE" then
    return nil, "invalid or oversized WAV file"
  end
  local data = love.filesystem.newFileData(bytes, relative)
  local source = love.audio.newSource(data, "static")
  if source.setRelative then source:setRelative(true) end
  if source.setRolloff then source:setRolloff(0) end
  if source.setPosition then source:setPosition(pan, 0, 0) end
  return source
end

-- The pack the launcher's Tools menu imported into the save folder, if any.
local function importedPack()
  if not (love and love.filesystem and love.filesystem.getInfo and love.filesystem.getSaveDirectory) then return nil end
  if not love.filesystem.getInfo("pocket-access-sounds/common", "directory") then return nil end
  return love.filesystem.getSaveDirectory() .. "/pocket-access-sounds"
end

function Earcons.new(opts)
  opts = opts or {}
  return setmetatable({
    sink = opts.sink,
    soundPackPath = opts.soundPackPath or os.getenv("POKEPORT_ACCESS_SOUND_DIR") or importedPack(),
    assetLoader = opts.assetLoader,
    cache = {},
    history = {},
    enabled = opts.enabled ~= false,
    volumeLevel = math.floor(clamp(
      opts.volumeLevel == nil and 7 or opts.volumeLevel, 0, 7) + 0.5),
  }, Earcons)
end

function Earcons:setEnabled(enabled)
  self.enabled = enabled == true
end

function Earcons:setVolumeLevel(level)
  self.volumeLevel = math.floor(clamp(level == nil and 7 or level, 0, 7) + 0.5)
  return self.volumeLevel
end

function Earcons:play(id, opts)
  opts = opts or {}
  if not self.enabled then return false, "earcons disabled" end
  local profile = PROFILES[id]
  if not profile then return false, "unknown earcon: " .. tostring(id) end
  local pan = clamp(opts.pan, -1, 1)
  local requestedVolume = clamp(opts.volume == nil and 1 or opts.volume, 0, 1)
  local volume = requestedVolume * (self.volumeLevel or 7) / 7
  local record = { id = id, pan = pan, volume = volume }
  self.history[#self.history + 1] = record
  if #self.history > 200 then table.remove(self.history, 1) end

  if self.sink then
    local ok, result, reason = pcall(self.sink, record)
    if not ok then return false, tostring(result) end
    if result == false or result == nil then return false, reason or "earcon sink failed" end
    return true
  end

  -- Quantized pan keeps the cache bounded while retaining useful spatial
  -- resolution across the stereo field.
  local panStep = math.floor((pan + 1) * 10 + 0.5)
  local cacheKey = id .. ":" .. tostring(panStep)
  local source = self.cache[cacheKey]
  if source == false then return false, "earcon synthesis previously failed" end
  if not source then
    local made, reason
    if self.soundPackPath and SOUND_FILES[id] then
      local loader = self.assetLoader or loadWaveFromDisk
      local loaded
      loaded, made, reason = pcall(loader, self.soundPackPath, SOUND_FILES[id],
                                   panStep / 10 - 1)
      if not loaded then reason, made = made, nil end
      if not made and not self.packWarning then
        self.packWarning = true
        Logger.warn("Pokemon Access sound pack unavailable; using procedural cues: %s",
                    tostring(reason))
      end
    end
    local ok = true
    if not made then
      ok, made, reason = pcall(synth, profile, panStep / 10 - 1)
    end
    if not ok or not made then
      self.cache[cacheKey] = false
      local message = not ok and made or reason or "earcon synthesis failed"
      Logger.warn("accessibility earcon %s unavailable: %s", id, tostring(message))
      return false, message
    end
    source = made
    self.cache[cacheKey] = source
  end
  local ok, reason = pcall(function()
    source:stop()
    source:setVolume(volume)
    source:play()
  end)
  if not ok then return false, tostring(reason) end
  return true
end

function Earcons:stop()
  for _, source in pairs(self.cache) do
    if source and source ~= false then pcall(source.stop, source) end
  end
  return true
end

Earcons.PROFILES = PROFILES
Earcons.SOUND_FILES = SOUND_FILES

return Earcons
