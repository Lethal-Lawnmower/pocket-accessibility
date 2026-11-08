-- Reused from the old Pocket Accessibility project (src/accessibility/Accessibility.lua
-- at commit 71cdd419) under decision 20; adapted for v0.3.98.  Only the
-- navigation half is used: menus, dialogue and battle speech are the new
-- presenters in src/access/screens, so describe() is not driven here.

-- Native accessibility coordinator.
--
-- States expose semantic snapshots through accessibilitySnapshot(context).
-- This coordinator observes the settled top of the state stack once per fixed
-- update and announces only meaningful changes.  It never scrapes pixels and
-- it owns the speech lifecycle, so gameplay remains independent of Prism.

local Logger = require("src.core.Logger")
-- v0.3.98 adaptation: speech is src/access/Speech (Prism), handed in as
-- opts.speech by src/access/nav/init.lua, so the old speech stack is gone.
local SpeechTrace = { write = function() end }
local Speech = nil
local BackendLoader = { create = function()
  return nil, "speech is provided by src/access/Speech"
end }
local Earcons = require("src.access.nav.Earcons")
local WorldSnapshot = require("src.access.nav.WorldSnapshot")
local TerrainSemantics = require("src.access.nav.TerrainSemantics")
local TraversalSemantics = require("src.access.nav.TraversalSemantics")
local Runtime = require("src.mods.Runtime")
local Collision = require("src.world.Collision")
local CutTrees = require("src.access.nav.CutTrees")
local FieldDefaults = require("src.world.FieldDefaults")
local Map = require("src.world.Map")
local Pathfinder = require("src.access.nav.Pathfinder")
local RegionalPathfinder = require("src.access.nav.RegionalPathfinder")
local PuzzleAssistance = require("src.access.nav.PuzzleAssistance")
local bit = require("bit")

local Accessibility = {}
Accessibility.__index = Accessibility

local WORLD_EVENT_OWNER = "__red_access_reimagined"

local CELL_CUES = {
  grass = "grass",
  water = "water",
  warp = "door",
  blocked = "wall",
  edge = "wall",
  walkable = "default",
  signpost = "default",
  counter = "default",
  unknown = "default",
}

-- Pokemon Access uses these terrain sounds as footsteps.  Doors, stairs,
-- holes, switches, and other points of interest are sonar-only: playing them
-- on every ordinary step would both diverge from the reference scripts and
-- duplicate transition/dialogue feedback.
local FOOTSTEP_TERRAIN = {
  grass = true,
  bush = true,
  water = true,
  directional_floor = true,
}

function Accessibility:usesTerrainFootstep(record)
  return type(record) == "table" and FOOTSTEP_TERRAIN[record.kind] == true
end

local CARDINAL_DELTA = {
  left = { -1, 0 }, right = { 1, 0 },
  up = { 0, -1 }, down = { 0, 1 },
}
local CARDINAL_ORDER = { "up", "right", "down", "left" }
local CARDINAL_ALIAS = {
  north = "up", south = "down", east = "right", west = "left",
}

-- `speakerNames` is an optional set of exact names that may open a line as a
-- speaker label. It carries the saved player and rival names, which Gen 1 lets
-- the player enter in mixed case; the uppercase heuristic below cannot
-- recognize those. Omitting it retains the original single-argument behavior.
local function normalize(text, speakerNames)
  if type(text) ~= "string" then return nil end
  -- The game font renders the Unicode gender glyphs, but some Prism-selected
  -- screen-reader backends omit or reject an utterance containing them. Keep
  -- the visual text exact and expand only at the speech boundary.
  text = text:gsub("♂", " male")
  text = text:gsub("♀", " female")
  -- Respect punctuation already authored at a visual line boundary. The old
  -- unconditional period produced constructions such as "Well,. then" and
  -- gave speech engines poor prosody. An unpunctuated boundary still becomes
  -- a sentence pause rather than running two visual lines together.
  text = text:gsub("([,;:%.!%?])[\n\v\f]+", "%1 ")
  text = text:gsub("[\n\v\f]+", ". ")
  text = text:gsub("%s+", " ")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  text = text:gsub("%. ([,%.!%?])", "%1")
  -- Gen 1 dialogue commonly prefixes a line with BILL:, OAK:, RED:, a
  -- player-chosen name, or a role such as LEADER:. A comma gives plain-text
  -- Prism backends a reliable short vocative pause without speaking SSML or
  -- changing the visual text. Keep the bound conservative so an arbitrary
  -- prose colon is not rewritten.
  local clockTime = text:match("^[^:]*%d:%d") ~= nil
  text = text:gsub("^([^:]+):%s*", function(prefix)
    -- v0.3.98: a clock time ("10:00 AM", Gen 2's Q) is not a speaker label
    if clockTime then return nil end
    -- Canonical speaker tags are uppercase. Requiring that form protects
    -- semantic labels such as "Mod House:" and "Enemy health:", whose colon
    -- conveys useful navigation structure.
    if #prefix <= 32 and prefix:match("^[A-Z][A-Z%.%' %-]*$") then
      return prefix .. ", "
    end
    -- The naming screen also accepts mixed case, and both <PLAYER>: and
    -- <RIVAL>: open canonical lines (Copycat's House, Oak's Lab, Cerulean,
    -- Champion's Room and others). Match those two names exactly rather than
    -- widening the pattern, so an arbitrary mixed-case label is still safe.
    if type(speakerNames) == "table" and speakerNames[prefix] == true then
      return prefix .. ", "
    end
    return prefix .. ": "
  end)
  return text ~= "" and text or nil
end

local function descriptorText(descriptor, entering)
  if type(descriptor) == "string" then return descriptor end
  if type(descriptor) ~= "table" then return nil end
  local text = descriptor.text
  if entering and descriptor.enterText then
    local introduction = descriptor.enterText
    local separator = introduction:match("[%.!%?]%s*$") and " " or ". "
    text = text and (introduction .. separator .. text) or introduction
  end
  return text
end

function Accessibility.new(game, opts)
  opts = opts or {}
  local savedOptions = game and game.save and game.save.options or {}
  local follows = opts.sonarFollowsPlayer
  if follows == nil then follows = savedOptions.accessibilitySonarFollow ~= false end
  local cueVolume = opts.cueVolumeLevel
  if cueVolume == nil then cueVolume = savedOptions.accessibilityCueVol end
  local self = setmetatable({
    game = game,
    enabled = false,
    speech = opts.speech,
    -- The optional Pokemon Access cue pack the player supplied through the
    -- first-run wizard.  Read from saved options here rather than left to
    -- Earcons' environment-variable default, which only a developer ever sets:
    -- without this the pack could be installed and never heard.
    earcons = opts.earcons
      or Earcons.new({ soundPackPath = savedOptions.accessSoundPack }),
    backendFactory = opts.backendFactory or BackendLoader.create,
    backendOptions = opts.backendOptions,
    worldSnapshot = opts.worldSnapshot or WorldSnapshot,
    terrainSemantics = opts.terrainSemantics or TerrainSemantics,
    -- Injected the same way, because a generation's puzzles differ in all
    -- three of the things this module needs: where the boulders must go, what
    -- counts as one, and whether a step is legal.
    puzzleAssistance = opts.puzzleAssistance or PuzzleAssistance,
    events = opts.events or Runtime.events,
    eventOwner = opts.eventOwner or WORLD_EVENT_OWNER,
    browseFilter = "all",
    browseIndex = 1,
    sonarFollowsPlayer = follows == true,
    ownsSpeech = opts.speech == nil,
    observedState = nil,
    observedKey = nil,
    observedContext = nil,
    pendingKey = nil,
    pendingFrames = 0,
    pendingEntering = false,
    stateUnannounced = false,
    -- Native snapshots change only when semantic state changes, unlike the
    -- emulator-era text polling that needed a long stability window. Two fixed
    -- updates retain coalescing without adding a perceptible control lag.
    defaultDelayFrames = math.max(0, tonumber(opts.defaultDelayFrames) or 2),
    snapshotErrors = setmetatable({}, { __mode = "k" }),
    terrainCueWarnings = {},
    semanticSequence = 0,
    status = { enabled = false, available = opts.speech ~= nil },
  }, Accessibility)
  -- decision 22: camera keys and help are off unless the player opts in;
  -- nil (old tests) keeps the old behaviour
  self.cameraEnabled = opts.cameraEnabled
  self.battleEvents = opts.battleEvents == true
  self:setCueVolume(cueVolume)
  self:setEnabled(opts.enabled ~= false, { silent = true })
  self:subscribeWorldEvents()
  if self.enabled and self.speech and self.speech:isAvailable() then
    -- Android has no keyboard commands: it is played with a controller (decision 52)
    local android = love and love.system and love.system.getOS and love.system.getOS() == "Android"
    self:announce(android
      and "Screen reader ready. Hold the left trigger and use the D-pad to choose where to go."
      or "Screen reader ready. Press F7 for accessibility command mode. Press F8 for help.",
      { remember = true })
  end
  return self
end

-- Generation adapters override this single ownership seam.  Gen I calls the
-- live object `overworld`; Gold calls it `world`.  Keeping the spelling out of
-- the semantic coordinator prevents an adapter from aliasing/mutating Game
-- merely to receive events and semantic telemetry.
function Accessibility:worldState()
  return self.game and self.game.overworld or nil
end

-- Structured mirror of the information offered to the player. Test drivers
-- consume this event instead of scraping Prism audio or reaching into route
-- internals. `spoken` on announcement events records whether the backend
-- accepted that particular utterance; semantic observation remains available
-- when a test intentionally outruns audio. Payloads contain labels and
-- directives, never a privileged movement path.
function Accessibility:emitSemantic(kind, payload)
  if type(kind) ~= "string" or kind == "" then return nil end
  self.semanticSequence = (self.semanticSequence or 0) + 1
  local event = {}
  for key, value in pairs(type(payload) == "table" and payload or {}) do
    event[key] = value
  end
  -- `kind` and `sequence` are this surface's identity and ordering, so they are
  -- stamped after the payload is copied and a payload can never rewrite them.
  -- Consumers dispatch on `kind` and dedupe/order on `sequence`; a payload that
  -- reused either key would silently misroute events or make the sequence
  -- non-monotonic. Stamping last enforces that structurally, which matters
  -- because `announce` forwards a caller-supplied `semantic` table here.
  event.kind = kind
  event.sequence = self.semanticSequence
  local overworld = self:worldState()
  local map = type(overworld) == "table" and overworld.map or nil
  if event.mapId == nil and type(map) == "table" then
    event.mapId = map.id or (type(map.def) == "table" and map.def.id)
  end
  local events = self.events
  if type(events) == "table" and type(events.emit) == "function" then
    events:emit("accessibility.event", event)
  end
  return event
end

function Accessibility:setCueVolume(level)
  level = math.floor(math.max(0, math.min(7, tonumber(level) or 7)) + 0.5)
  self.cueVolumeLevel = level
  local setter = self.earcons and self.earcons.setVolumeLevel
  if type(setter) ~= "function" then return true end
  local ok, reason = pcall(setter, self.earcons, level)
  if not ok then
    Logger.warn("accessibility cue volume could not be applied: %s", tostring(reason))
    return false, tostring(reason)
  end
  return true
end

function Accessibility:setSonarFollow(enabled, opts)
  opts = opts or {}
  self.sonarFollowsPlayer = enabled ~= false
  local game = self.game
  local options = game and game.save and game.save.options
  if type(options) == "table" then
    options.accessibilitySonarFollow = self.sonarFollowsPlayer
  end
  if opts.persist and game and type(game.writeOptions) == "function" then
    local ok, reason = pcall(game.writeOptions, game)
    if not ok then
      Logger.warn("accessibility sonar-follow preference could not be saved: %s",
                  tostring(reason))
      return false, tostring(reason)
    end
  end
  return true
end

function Accessibility:applyOptions(options)
  options = type(options) == "table" and options or {}
  self:setCueVolume(options.accessibilityCueVol)
  self:setSonarFollow(options.accessibilitySonarFollow ~= false)
  return true
end

-- Classify from live gameplay data, never pixels.  The classifier contains
-- its own protected mod-metadata boundary; this outer pcall also makes an
-- injected/replaced classifier unable to crash gameplay.  WorldSnapshot is a
-- deliberately smaller fallback so accessibility remains usable if the rich
-- terrain layer itself is unavailable.
function Accessibility:terrainAt(overworld, x, y, opts)
  opts = opts or {}
  local game = self.game
  local data = game and game.data
  local save = game and game.save
  local player = type(overworld) == "table" and overworld.player or nil
  local entities = opts.entities
  if entities == nil and type(overworld) == "table" then
    entities = overworld.entities or overworld.npcs
  end
  local classifyOpts = {
    game = game,
    data = data,
    field = data and data.field,
    player = player,
    entities = entities,
    onBike = (save and save.onBike == true)
      or (type(player) == "table" and player.onBike == true),
    passable = opts.passable,
    metadata = opts.metadata,
    providers = opts.providers,
  }
  local classifier = self.terrainSemantics
  local classify = type(classifier) == "table" and classifier.classify or nil
  local ok, record
  if type(classify) == "function" then
    ok, record = pcall(classify, overworld, x, y, classifyOpts)
  else
    ok, record = false, "terrain classifier is unavailable"
  end
  if ok and type(record) == "table" then return record end

  if not self.warnedTerrainClassifier then
    self.warnedTerrainClassifier = true
    Logger.warn("accessibility terrain classifier failed: %s", tostring(record))
  end
  local map = type(overworld) == "table" and overworld.map or nil
  local fallback = type(self.worldSnapshot) == "table"
    and self.worldSnapshot.classifyCell or nil
  local fallbackOK, cell = false, nil
  if type(fallback) == "function" then
    fallbackOK, cell = pcall(fallback, map, x, y)
  end
  local kind = fallbackOK and type(cell) == "table" and cell.kind or "unknown"
  return {
    schema = 0,
    x = x, y = y,
    kind = kind,
    label = "unknown terrain",
    cue = CELL_CUES[kind] or "default",
    confidence = "fallback",
    source = "WorldSnapshot",
    diagnostics = { { code = "classifier_failed" } },
    features = {},
  }
end

-- Authored mods may name a cue that this installation does not provide.  Try
-- it first so an injected/custom earcon sink can honor it, then fall back to a
-- safe default instead of turning missing presentation audio into a failure.
function Accessibility:cueTerrain(record, opts, override)
  local cue = override or (type(record) == "table" and record.cue) or "default"
  local ok, reason = self:cue(cue, opts)
  if ok or cue == "default" then return ok, reason end
  if not self.terrainCueWarnings[cue] then
    self.terrainCueWarnings[cue] = true
    Logger.warn("accessibility terrain cue %s unavailable; using default: %s",
                tostring(cue), tostring(reason))
  end
  return self:cue("default", opts)
end

-- The native world emits a step before it resolves warps, scripts, poison,
-- encounters, and other consequences.  Queue the fact here and arbitrate only
-- after StateStack:update has settled.  This prevents a grass cue from leaking
-- into a battle/dialogue/warp that the same step immediately opened.
function Accessibility:subscribeWorldEvents()
  local events = self.events
  if type(events) ~= "table" or type(events.on) ~= "function" then return end
  self.worldSubscriptions = {
    events:on("map.entered", function(event)
      if not self.enabled or type(event) ~= "table" then return end
      local navigation = self.activeNavigation
      if navigation and navigation.journey and navigation.nextMapId == event.mapId then
        self:cancelPendingRoute(false)
        navigation.mapId = event.mapId
        navigation.awaitingMap = true
        navigation.lastDirectiveKey = nil
      else
        self:stopNavigation(false)
        self:cancelPendingRoute(false)
      end
      self.pendingMapEvent = { mapId = event.mapId, via = event.via }
      self.pendingStepEvent = nil
      self.pendingBumpEvent, self.lastBumpKey = nil, nil
      self.browseFilter, self.browseIndex = "all", 1
      self.browseSelectionId = nil
      self.sonarMapId, self.sonarX, self.sonarY = nil, nil, nil
    end, -1000, self.eventOwner),
    events:on("world.stepped", function(event)
      if not self.enabled or type(event) ~= "table" then return end
      self.pendingStepEvent = {
        mapId = event.mapId, x = event.x, y = event.y, tile = event.tile,
      }
      self.pendingBumpEvent, self.lastBumpKey = nil, nil
    end, -1000, self.eventOwner),
    events:on("world.bumped", function(event)
      if not self.enabled or type(event) ~= "table" then return end
      self.pendingBumpEvent = {
        mapId = event.mapId, x = event.x, y = event.y,
        targetX = event.targetX, targetY = event.targetY,
        direction = event.direction, reason = event.reason,
      }
    end, -1000, self.eventOwner),
  }
  -- v0.3.98 adaptation: the old coordinator also queued battle.damage_dealt
  -- and battle.ball_shakes_complete for processBattleEvents to speak.  Battle
  -- speech is the new presenters (src/access/screens), updateNavigation never
  -- drives processBattleEvents, and so both queues grew for the whole session
  -- holding battle references.  They are subscribed only when a caller asks
  -- for the old battle narration (opts.battleEvents; nothing does today).
  if self.battleEvents ~= true then return end
  local subscriptions = self.worldSubscriptions
  subscriptions[#subscriptions + 1] = events:on("battle.damage_dealt", function(event)
    if not self.enabled or type(event) ~= "table" then return end
    local damage = math.floor(tonumber(event.damage) or 0)
    if damage <= 0 then return end
    self.pendingBattleDamage = self.pendingBattleDamage or {}
    self.pendingBattleDamage[#self.pendingBattleDamage + 1] = {
      battle = event.battle, target = event.target, damage = damage,
      remainingHP = tonumber(event.remainingHP), maxHP = tonumber(event.maxHP),
      hitSubstitute = event.hitSubstitute == true, side = event.side,
    }
  end, -1000, self.eventOwner)
  subscriptions[#subscriptions + 1] = events:on("battle.ball_shakes_complete", function(event)
    if not self.enabled or type(event) ~= "table" then return end
    self.pendingBallShakes = self.pendingBallShakes or {}
    self.pendingBallShakes[#self.pendingBallShakes + 1] = {
      battle = event.battle, shakes = math.max(0,
        math.floor(tonumber(event.shakes) or 0)),
    }
  end, -1000, self.eventOwner)
end

function Accessibility:unsubscribeWorldEvents()
  for _, unsubscribe in ipairs(self.worldSubscriptions or {}) do
    pcall(unsubscribe)
  end
  self.worldSubscriptions = nil
end

local function currentMapId(overworld)
  local map = type(overworld) == "table" and overworld.map or nil
  if type(map) ~= "table" then return nil end
  return map.id or (type(map.def) == "table" and map.def.id) or nil
end

local function sentenceCase(text)
  text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if text == "" then return nil end
  return text:sub(1, 1):upper() .. text:sub(2)
end

-- Convert the engine's collision verdict into the smallest useful spoken
-- fact. Native movement has already proved the cell is blocked; this only
-- identifies what was rejected and never changes or predicts gameplay.
-- Callers that build a bare table and call these methods directly (several
-- suites do, deliberately, to test one method in isolation) never run new(),
-- so the injected module has to degrade to the shared one rather than nil-index.
local function puzzleModule(self)
  return (type(self) == "table" and self.puzzleAssistance) or PuzzleAssistance
end

function Accessibility:bumpText(overworld, bump)
  if bump.reason == "bounds" then return "Map edge." end

  if bump.reason == "entity" then
    local entities = overworld.entities or overworld.npcs or {}
    for index, entity in ipairs(entities) do
      if type(entity) == "table"
         and ((entity.cellX == bump.targetX and entity.cellY == bump.targetY)
           or (entity.targetX == bump.targetX and entity.targetY == bump.targetY)) then
        local map = overworld.map
        local def = type(map) == "table" and type(map.def) == "table" and map.def or {}
        local describe = type(self.worldSnapshot) == "table"
          and self.worldSnapshot.describeEntity or nil
        if type(describe) == "function" then
          local ok, item = pcall(describe, entity, {
            mapId = currentMapId(overworld), mapLabel = def.label, ordinal = index,
          })
          local label = ok and type(item) == "table" and sentenceCase(item.label) or nil
          if label then return label .. " ahead." end
        end
        break
      end
    end
    return "Person or object ahead."
  end

  local terrain = self:terrainAt(overworld, bump.targetX, bump.targetY, {
    passable = false,
  })
  local kind = type(terrain) == "table" and terrain.kind or nil
  local label = type(terrain) == "table" and sentenceCase(terrain.label) or nil
  if label and kind ~= "default" and kind ~= "unknown" then
    return label .. " ahead."
  end
  return "Wall ahead."
end

function Accessibility:hasAdjacentLedge(overworld)
  local player, map = overworld.player, overworld.map
  local field = self.game and self.game.data and self.game.data.field
  if not (type(player) == "table" and type(map) == "table"
          and type(map.cellTile) == "function"
          and type(map.inBounds) == "function") then return false end
  local mapDef = type(map.def) == "table" and map.def or {}
  local ok, standing = pcall(map.cellTile, map, player.cellX, player.cellY)
  if not ok then return false end
  for _, ledge in ipairs((field and field.ledges) or {}) do
    local delta = CARDINAL_DELTA[ledge.input or ledge.facing]
    if delta and (ledge.tileset or "OVERWORLD") == mapDef.tileset
       and ledge.standingTile == standing then
      local tx, ty = player.cellX + delta[1], player.cellY + delta[2]
      local boundsOK, inBounds = pcall(map.inBounds, map, tx, ty)
      if boundsOK and inBounds then
        local tileOK, tile = pcall(map.cellTile, map, tx, ty)
        if tileOK and tile == ledge.ledgeTile then return true end
      end
    end
  end
  return false
end

-- Re-anchor the follow-mode sonar whenever the player's cell changes, however
-- it changed. Records the cell it observed either way, so the very first
-- observation of a map does not read as movement.
function Accessibility:followPlayerCell(overworld)
  local player = type(overworld) == "table" and overworld.player or nil
  if type(player) ~= "table" then return end
  local mapId = currentMapId(overworld)
  local x, y = player.cellX, player.cellY
  if type(x) ~= "number" or type(y) ~= "number" then return end
  local seen = self.observedPlayerCell
  local moved = seen ~= nil
    and (seen.mapId ~= mapId or seen.x ~= x or seen.y ~= y)
  self.observedPlayerCell = { mapId = mapId, x = x, y = y }
  if moved and self.sonarFollowsPlayer ~= false then
    self.sonarMapId, self.sonarX, self.sonarY = mapId, x, y
  end
end

function Accessibility:processWorldEvents(state)
  local overworld = self:worldState()
  local isSettledWorld = state ~= nil and state.isOverworld == true

  -- Map entry can occur under the transition state.  Retain only the newest
  -- event until that exact live map is again the actionable top state.
  local mapEvent = self.pendingMapEvent
  if mapEvent and isSettledWorld then
    self.pendingMapEvent = nil
    self.pendingStepEvent = nil
    if currentMapId(overworld) == mapEvent.mapId then
      local location = self.worldSnapshot.locationName(
        overworld.map, mapEvent.mapId, nil,
        self.game.save and self.game.save.player and self.game.save.player.name,
        nil, self.game.save and self.game.save.version,
        self.game.save and self.game.save.player and self.game.save.player.rival)
      local navigation = self.activeNavigation
      if location and navigation and navigation.awaitingMap then
        navigation.pendingLocation = location
      elseif location then
        -- A map/route connection is orientation feedback, not authored
        -- narration.  Holding across a seam can emit north/south map names in
        -- rapid succession; retaining them all makes the player hear where
        -- they were several steps ago.  Keep only the newest location.
        self:announce(location, { interrupt = true })
      end
      if navigation and navigation.awaitingMap then
        self:resumeRegionalNavigation()
      end
    end
    return
  end

  -- Following is a property of where the player is, not of who moved them.
  -- OverworldController runs onStepComplete -- and so emits world.stepped --
  -- only for unscripted steps (`if stepped and not scripted`), so a spinner
  -- slide, a Seafoam current, a cutscene escort or a forced-bike bounce moves
  -- the player with no step event at all. Anchoring on the event alone left
  -- the sonar behind on the tile the slide started from, which is exactly the
  -- kind of maze where it matters. Re-anchor on any observed cell change; a
  -- deliberate D/G/R/V displacement survives because the player has not moved.
  self:followPlayerCell(overworld)

  local stepEvent = self.pendingStepEvent
  if not stepEvent then
    local bump = self.pendingBumpEvent
    self.pendingBumpEvent = nil
    if not (bump and isSettledWorld and currentMapId(overworld) == bump.mapId) then
      return
    end
    local player, map = overworld and overworld.player, overworld and overworld.map
    if type(player) ~= "table" or type(map) ~= "table"
       or player.cellX ~= bump.x or player.cellY ~= bump.y
       or player.facing ~= bump.direction then return end
    local key = table.concat({ tostring(bump.mapId), tostring(bump.x),
      tostring(bump.y), tostring(bump.direction) }, ":")
    if key == self.lastBumpKey then return end
    self.lastBumpKey = key

    local boundsOK, inBounds = pcall(map.inBounds, map,
                                      bump.targetX, bump.targetY)
    local waterOK, water = pcall(map.isWaterCell, map,
                                  bump.targetX, bump.targetY)
    if boundsOK and inBounds and waterOK and water then
      -- Pokémon Access identifies shorelines with s_water.wav.  At this
      -- native boundary we can additionally report the real field-action
      -- result, without guessing from inventory/badge state.
      self:cue("water", { pan = self:sonarPan(overworld, bump.targetX) })
      local usableOK, status = pcall(
        overworld.useSurfFieldMove, overworld)
      if usableOK and status == "ok" then
        self:announce("Water ahead. Surf is available from the party menu.",
          { interrupt = true })
      else
        self:announce("Water ahead.", { interrupt = true })
      end
    else
      -- Signs, walls, actors and bounds are live spatial feedback.  They must
      -- replace an earlier bump rather than form an audio history when a
      -- player rapidly probes or tabs through nearby interactables.
      self:announce(self:bumpText(overworld, bump), { interrupt = true })
    end
    self:refreshActiveNavigation()
    return
  end
  self.pendingStepEvent = nil
  if currentMapId(overworld) ~= stepEvent.mapId then return end
  local player = overworld and overworld.player
  if type(player) ~= "table"
     or player.cellX ~= stepEvent.x or player.cellY ~= stepEvent.y then return end

  -- Following is logical navigation state, not audio.  Keep it synchronized
  -- even when the landing immediately opens dialogue/battle and the cue itself
  -- is intentionally suppressed.
  if self.sonarFollowsPlayer ~= false then
    self.sonarMapId = stepEvent.mapId
    self.sonarX, self.sonarY = stepEvent.x, stepEvent.y
  end
  if not isSettledWorld then return end

  local terrain = self:terrainAt(overworld, stepEvent.x, stepEvent.y, {
    -- A settled step is proof that native movement accepted this cell.
    passable = true,
  })
  local cue = self:usesTerrainFootstep(terrain) and terrain.cue or "default"
  if terrain.kind == "directional_floor" and terrain.active == false then
    cue = "default"
  end
  self:cueTerrain(terrain, nil, cue)
  if self:hasAdjacentLedge(overworld) then self:cue("ledge") end
  -- A TRANSIENT settled world is one the player is standing in but cannot
  -- choose to remain in -- mid-current, mid-waterfall.  The terrain cue is
  -- exactly what they need there, so it fires above; a route directive is
  -- exactly what they do not, because the bearing would be measured from a cell
  -- they are already leaving.  Generations that never set the flag are
  -- unaffected.
  if state ~= nil and state.transient == true then return end
  self:refreshActiveNavigation()
end

function Accessibility:initializeSpeech()
  if self.speech and self.speech:isAvailable() then return true end
  local backend, reason, path = self.backendFactory(self.backendOptions)
  if not backend then
    self.status.available = false
    self.status.reason = reason or "no speech backend available"
    if not self.warnedUnavailable then
      self.warnedUnavailable = true
      Logger.warn("accessibility enabled but speech is unavailable: %s",
                  tostring(self.status.reason))
    end
    return false, self.status.reason
  end
  self.speech = Speech.new(backend)
  self.ownsSpeech = true
  self.status.available = true
  self.status.reason = nil
  self.status.backend = backend.name
  self.status.path = path
  self.warnedUnavailable = false
  return true
end

function Accessibility:setEnabled(enabled, opts)
  opts = opts or {}
  enabled = enabled == true
  if enabled == self.enabled then
    self.status.enabled = enabled
    return enabled and self:initializeSpeech() or true
  end

  if not enabled then
    self.pendingMapEvent, self.pendingStepEvent, self.pendingBumpEvent = nil, nil, nil
    self.pendingBattleDamage, self.pendingBallShakes = nil, nil
    self.lastBumpKey = nil
    self:stopNavigation(false)
    self:cancelPendingRoute(false)
    if self.earcons then
      self.earcons:setEnabled(false)
      self.earcons:stop()
    end
    if self.speech then
      self.speech:stop()
      -- Keep an initialized backend for a later toggle.  Destroying it here
      -- would either cancel the audible OFF confirmation or force a second
      -- screen-reader discovery every time the option is changed.
      if not opts.silent and self.speech:isAvailable() then
        self.speech:output("Screen reader off", { interrupt = false })
      end
    end
    self.enabled = false
    self.status.enabled = false
    self.status.available = self.speech and self.speech:isAvailable() or false
    return true
  end

  self.enabled = true
  self.status.enabled = true
  if self.earcons then self.earcons:setEnabled(true) end
  self.observedState, self.observedKey, self.observedContext = nil, nil, nil
  self.pendingKey, self.pendingFrames, self.pendingEntering = nil, 0, false
  self.stateUnannounced = false
  local ok, reason = self:initializeSpeech()
  if ok and not opts.silent then
    self:announce("Screen reader on", { interrupt = true, remember = false })
  end
  return ok, reason
end

function Accessibility:isAvailable()
  return self.enabled and self.speech ~= nil and self.speech:isAvailable()
end

function Accessibility:announce(text, opts)
  opts = opts or {}
  text = normalize(text, self:speakerNames())
  if not text then return false, "announcement text is empty" end
  if not self.enabled then return false, "accessibility disabled" end
  if not self.speech and not self:initializeSpeech() then
    return false, self.status.reason
  end
  -- Cursor-driven descriptors opt into interruption; sequential dialogue,
  -- battle narration, and other automatic events stay ordered. Making every
  -- event interrupt caused automatically advancing wrapped dialogue to cut
  -- itself off before Prism finished the preceding visual line.
  SpeechTrace.write("semantic", text, opts.interrupt == true)
  local ok, reason = self.speech:output(
    text, { interrupt = opts.interrupt == true })
  local semantic = type(opts.semantic) == "table" and opts.semantic or {}
  local payload = {
    text = text,
    interrupt = opts.interrupt == true,
    channel = semantic.channel or "automatic",
    spoken = ok == true,
  }
  for key, value in pairs(semantic) do
    if key ~= "kind" then payload[key] = value end
  end
  self:emitSemantic(semantic.kind or "announcement", payload)
  return ok, reason
end

-- Owner-stamped entry point for the public mod facade.  It deliberately
-- returns nil,error (rather than throwing) so an unavailable screen reader
-- can never turn a presentation request into a mod or gameplay failure.
function Accessibility:announceFrom(owner, text, opts)
  if type(owner) ~= "string" or owner == "" then
    return nil, "announcement owner is required"
  end
  opts = opts or {}
  local normalized = normalize(text, self:speakerNames())
  if not normalized then return nil, "announcement text is empty" end
  self.lastSource = owner
  local ok, reason = self:announce(normalized, {
    interrupt = opts.interrupt == true,
    remember = opts.remember ~= false,
  })
  if not ok then return nil, reason end
  self.lastAnnouncement = {
    owner = owner,
    text = normalized,
    interrupt = opts.interrupt == true,
    remember = opts.remember ~= false,
  }
  return true
end

function Accessibility:cue(id, opts)
  if not self.enabled then return false, "accessibility disabled" end
  if not self.earcons then return false, "earcons unavailable" end
  return self.earcons:play(id, opts)
end

-- Pokémon Access manual commands cancel old speech exactly once and then
-- queue each response part noninterruptingly.  Route narration and other
-- multipart queries must use this method rather than repeated interrupting
-- announcements.
function Accessibility:announceManual(parts, opts)
  opts = opts or {}
  if type(parts) == "string" then parts = { parts } end
  if type(parts) ~= "table" or #parts == 0 then
    return false, "manual announcement needs one or more parts"
  end
  if not self.enabled then return false, "accessibility disabled" end
  if not self.speech and not self:initializeSpeech() then
    return false, self.status.reason
  end
  local stopped, stopReason = self.speech:stop()
  if not stopped then return false, stopReason end
  local speakerNames = self:speakerNames()
  for i, part in ipairs(parts) do
    local text = normalize(part, speakerNames)
    if not text then return false, "manual announcement part " .. i .. " is empty" end
    -- Trace the manual channel at the semantic stage too.  Without this every
    -- command answer -- browse results, route narration, arrival lines, the
    -- help text -- reached the native call with no semantic-stage counterpart
    -- to compare against, which is the exact comparison that identified the
    -- Gen II PP defect.  Same stage name as announce so the stages diff
    -- uniformly; the manual channel is recorded on the semantic event below.
    SpeechTrace.write("semantic", text, false)
    local ok, reason = self.speech:output(text, { interrupt = false })
    if not ok then return false, reason end
    self:emitSemantic("announcement", {
      text = text, interrupt = false, channel = "manual",
      part = i, parts = #parts,
    })
  end
  return true
end

-- Exact saved names that may legitimately open a spoken line as a speaker
-- label. Read live so a new game is reflected without restarting.
function Accessibility:speakerNames()
  local save = self.game and self.game.save
  local player = type(save) == "table" and save.player or nil
  if type(player) ~= "table" then return nil end
  local names, found = {}, false
  for _, value in ipairs({ player.name, player.rival }) do
    if type(value) == "string" and value ~= "" then
      names[value] = true
      found = true
    end
  end
  return found and names or nil
end

function Accessibility:worldForCommand()
  local stack = self.game and self.game.stack
  local state = stack and stack:top() or nil
  local overworld = self:worldState()
  if not (state and state.isOverworld == true
          and type(overworld) == "table" and type(overworld.map) == "table"
          and type(overworld.player) == "table") then
    return nil, "Not on a map"
  end
  return overworld
end

function Accessibility:captureWorld(filter)
  local overworld, reason = self:worldForCommand()
  if not overworld then return nil, reason end
  local data = self.game and self.game.data
  local mapId = currentMapId(overworld)
  local traversal = mapId and TraversalSemantics.forMap(mapId, overworld.map)
  local puzzle = puzzleModule(self).describe(self.game, overworld)
  local snapshot, snapshotError = self.worldSnapshot.capture(overworld, {
    maps = data and data.maps,
    field = data and data.field,
    lastMapRewrites = FieldDefaults.field(data, "lastMapRewrites"),
    filter = filter or self.browseFilter,
    playerName = self.game.save and self.game.save.player
                 and self.game.save.player.name,
    rivalName = self.game.save and self.game.save.player
                and self.game.save.player.rival,
    edition = self.game.save and self.game.save.version,
    separateWarps = self.separateWarps,
    specialTraversal = traversal,
    interactiveObjects = self:interactiveBrowseObjects(overworld, puzzle),
    objectOverrides = puzzle.objectOverrides,
    chaosCut = self.game.save and self.game.save.options
               and self.game.save.options.chaosCut == true,
  })
  -- v0.3.98 addition: the Area category lists item balls on the other maps
  -- of the building or zone the player is in (see areaBrowse)
  if snapshot and (filter or self.browseFilter) == "area" then
    snapshot.browse = self:areaBrowse(overworld)
  end
  return snapshot, snapshotError
end


-- Project native non-actor interactables into the same semantic object list
-- used for NPCs and item balls.  Nothing is cached: every browse capture is
-- derived from current map blocks and live field data, so completed Cut
-- actions disappear immediately.  Mods can contribute coordinate objects via
-- map accessibilityObjects/accessibility.interactiveObjects metadata.
function Accessibility:interactiveBrowseObjects(overworld, puzzle)
  if type(overworld) ~= "table" or type(overworld.map) ~= "table" then
    return {}
  end
  local map = overworld.map
  local def = type(map.def) == "table" and map.def or map
  local mapId = map.id or def.id or "unknown"
  local data = self.game and self.game.data
  local field = data and data.field
  local extras = field and field.hiddenExtras
  local traversal = TraversalSemantics.forMap(mapId, map)
  local result, ids = {}, {}
  local function add(record)
    if type(record) ~= "table" or type(record.x) ~= "number"
       or type(record.y) ~= "number" then return end
    local id = record.id
    if type(id) ~= "string" or id == "" or ids[id] then return end
    ids[id] = true
    result[#result + 1] = record
  end

  -- Pokémon Access synthesizes these from Gym tile coordinates; the native
  -- port stores the exact interaction coordinates in hidden field data.
  local trashAt = {}
  if mapId == "VERMILION_GYM" then
    local trash = extras and extras.trashCans
    local assistance = puzzleModule(self).enabled(self.game)
    local save = self.game and self.game.save or {}
    local flags = type(save.flags) == "table" and save.flags or {}
    local state = type(save.trashPuzzle) == "table" and save.trashPuzzle or {}
    local checked = type(state.checked) == "table" and state.checked or {}
    local firstOpen = flags.EVENT_1ST_LOCK_OPENED == true
    local secondOpen = flags.EVENT_2ND_LOCK_OPENED == true
    local firstCan, secondCan = state.activatedFirst, state.activatedSecond
    local possibleSecond = {}
    if assistance and firstOpen and type(firstCan) == "number" then
      local adjacent = (((trash and trash.adjacent) or {})[firstCan]) or {}
      local mask = #adjacent
      for candidateIndex = 1, mask do
        if bit.band(candidateIndex, mask) == candidateIndex then
          possibleSecond[adjacent[candidateIndex]] = true
        end
      end
      possibleSecond[0] = true -- preserve the original underflow candidate
    end
    for i, can in ipairs((trash and trash.cans) or {}) do
      local canIndex = can.can or (i - 1)
      trashAt[tostring(can.x) .. "," .. tostring(can.y)] = true
      local stateText
      if assistance then
        if secondOpen then
          if canIndex == firstCan and canIndex == secondCan then
            stateText = "first and second hidden switches toggled"
          elseif canIndex == firstCan then
            stateText = "first hidden switch toggled"
          elseif canIndex == secondCan then
            stateText = "second hidden switch toggled"
          else
            stateText = "no switch toggled"
          end
        elseif firstOpen then
          if type(firstCan) ~= "number" then
            stateText = "first switch toggled; candidate state unavailable"
          elseif canIndex == firstCan then
            stateText = "first hidden switch toggled"
            if possibleSecond[canIndex] then
              stateText = stateText .. "; possible second hidden switch"
            end
          elseif possibleSecond[canIndex] then
            stateText = "possible second hidden switch, not toggled"
          else
            stateText = "not a second-switch candidate"
          end
        elseif checked[canIndex + 1] then
          stateText = "checked, no switch"
        else
          stateText = "not checked"
        end
      end
      add({
        id = "trash_can:" .. mapId .. ":" .. tostring(canIndex),
        label = assistance and ("Trash Can " .. tostring(canIndex + 1))
                or "Trash Can",
        stateText = stateText, x = can.x, y = can.y,
        index = canIndex, interaction = "inspect",
        semanticKind = "trash_can",
      })
    end
  end
  -- Access also finds ordinary trash-can tiles in the SS Anne kitchen.
  -- The native field data already supplies their exact A-interaction cells;
  -- project those cells as browse objects without assigning Gym switch state.
  -- A mod may add the same metadata elsewhere, so keep this map-driven.
  for i, can in ipairs((extras and extras.printTrash
                        and extras.printTrash[mapId]) or {}) do
    local key = tostring(can.x) .. "," .. tostring(can.y)
    if not trashAt[key] then
      trashAt[key] = true
      add({
        id = "print_trash:" .. tostring(mapId) .. ":" .. tostring(i),
        label = "Trash Can", x = can.x, y = can.y,
        interaction = "inspect", semanticKind = "trash_can",
      })
    end
  end

  -- A Cut obstacle is encoded as one replaceable 2x2 map block.  Several
  -- cells in that block may be impassable, so expose one stable object per
  -- block rather than making the user browse duplicate quadrants. Retain the
  -- complete blocked footprint: any of those cells can be faced for native
  -- Cut, and reducing it to one arbitrary quadrant can route around the tree.
  if type(map.widthCells) == "number" and type(map.heightCells) == "number" then
    local cutBlocks, cutOrder = {}, {}
    for y = 0, map.heightCells - 1 do
      for x = 0, map.widthCells - 1 do
        if self:isCuttableCell(overworld, x, y) then
          local bx, by = math.floor(x / 2), math.floor(y / 2)
          local blockKey = tostring(bx) .. "," .. tostring(by)
          if not cutBlocks[blockKey] then
            cutBlocks[blockKey] = { key = blockKey, cells = {} }
            cutOrder[#cutOrder + 1] = cutBlocks[blockKey]
          end
          local cells = cutBlocks[blockKey].cells
          cells[#cells + 1] = { x = x, y = y }
        end
      end
    end
    local player = overworld.player
    for _, block in ipairs(cutOrder) do
      local nearest, nearestDistance = block.cells[1], math.huge
      for _, cell in ipairs(block.cells) do
        local distance = 0
        if type(player) == "table" and type(player.cellX) == "number"
           and type(player.cellY) == "number" then
          distance = math.abs(cell.x - player.cellX)
                   + math.abs(cell.y - player.cellY)
        end
        if distance < nearestDistance then
          nearest, nearestDistance = cell, distance
        end
      end
      local terrain = self:terrainAt(overworld, nearest.x, nearest.y)
      add({
        id = "cut_tree:" .. tostring(mapId) .. ":" .. block.key,
        label = (terrain and terrain.label) or "Cuttable Tree",
        x = nearest.x, y = nearest.y, interaction = "cut",
        interactionCells = block.cells,
        semanticKind = "cut_tree",
      })
    end
  end

  -- Pokémon Access exposes Silph's locked tiles as Closed Door objects. The
  -- native data describes one replaceable 2x2 block per independently opened
  -- gate, so group its one/two visible door cells into one stable browse item.
  -- Inspect live terrain rather than flags alone: this stays correct during
  -- the frame in which the Card Key swaps the block and for modded layouts.
  local card = field and field.cardKeyDoors
  local floorDoors = card and card.closedDoors and card.closedDoors[mapId]
  for index, door in ipairs(floorDoors or {}) do
    if type(door.bx) == "number" and type(door.by) == "number" then
      local cells = {}
      for y = door.by * 2, door.by * 2 + 1 do
        for x = door.bx * 2, door.bx * 2 + 1 do
          if self:isClosedCardKeyDoorCell(overworld, x, y) then
            cells[#cells + 1] = { x = x, y = y }
          end
        end
      end
      if #cells > 0 then
        local nearest, nearestDistance = cells[1], math.huge
        for _, cell in ipairs(cells) do
          local distance = math.abs(cell.x - overworld.player.cellX)
                         + math.abs(cell.y - overworld.player.cellY)
          if distance < nearestDistance then
            nearest, nearestDistance = cell, distance
          end
        end
        local label = #floorDoors > 1
          and ("Closed Door " .. tostring(index)) or "Closed Door"
        local requirement
        if not self:hasCardKey() then requirement = "Needs Card Key" end
        add({
          id = "card_key_door:" .. tostring(mapId) .. ":"
               .. tostring(door.event or (door.bx .. "," .. door.by)),
          label = label, x = nearest.x, y = nearest.y,
          interaction = "card_key", interactionCells = cells,
          semanticKind = "card_key_door",
          requirement = requirement,
        })
      end
    end
  end

  -- Mansion gates alternate when any Secret switch is pressed. Expose only
  -- the live closed half of that puzzle, one object per native 2x2 block.
  -- Reading the live block keeps the projection correct immediately after a
  -- switch and permits mods to rearrange the authored state safely.
  local mansionGates = traversal and traversal.alternatingGates
  for index, gate in ipairs(mansionGates or {}) do
    if type(gate.bx) == "number" and type(gate.by) == "number"
       and type(map.blockAt) == "function"
       and map:blockAt(gate.bx, gate.by) ~= gate.openBlock then
      local cells = {}
      for y = gate.by * 2, gate.by * 2 + 1 do
        for x = gate.bx * 2, gate.bx * 2 + 1 do
          local terrain = self:terrainAt(overworld, x, y)
          if terrain and terrain.kind == "door" and terrain.passable == false then
            cells[#cells + 1] = { x = x, y = y }
          end
        end
      end
      if #cells > 0 then
        local nearest, nearestDistance = cells[1], math.huge
        local player = overworld.player
        for _, cell in ipairs(cells) do
          local distance = type(player) == "table"
            and math.abs(cell.x - player.cellX) + math.abs(cell.y - player.cellY)
            or 0
          if distance < nearestDistance then
            nearest, nearestDistance = cell, distance
          end
        end
        local label = #mansionGates > 1
          and ("Closed Door " .. tostring(index)) or "Closed Door"
        add({
          id = gate.id, label = label, x = nearest.x, y = nearest.y,
          interaction = "closed_gate", interactionCells = cells,
          semanticKind = "mansion_gate",
        })
      end
    end
  end

  for i, pc in ipairs((extras and extras.pcTiles and extras.pcTiles[mapId]) or {}) do
    add({
      id = "pc:" .. tostring(mapId) .. ":" .. i,
      label = pc.playerOnly and "Player's PC" or "PC",
      x = pc.x, y = pc.y, interaction = "inspect", semanticKind = "pc",
    })
  end
  -- Access includes Gym statue tiles in object browse. The native field
  -- metadata already holds their interaction cells and required facing.
  for i, statue in ipairs((extras and extras.gymStatues
                           and extras.gymStatues[mapId]) or {}) do
    add({
      id = "gym_statue:" .. tostring(mapId) .. ":" .. i,
      label = "Statue", x = statue.x, y = statue.y,
      requiredFacing = statue.facing,
      interaction = "inspect", semanticKind = "gym_statue",
    })
  end
  for i, object in ipairs((extras and extras.interactables
                            and extras.interactables[mapId]) or {}) do
    add({
      id = "hidden_interactable:" .. tostring(mapId) .. ":" .. i,
      label = object.label or "Interactable object",
      x = object.x, y = object.y, interaction = "inspect",
      semanticKind = "hidden_interactable",
    })
  end

  local authored = def.accessibilityObjects
  local accessibility = type(def.accessibility) == "table" and def.accessibility
  if type(authored) ~= "table" and accessibility then
    authored = accessibility.interactiveObjects
  end
  for i, object in ipairs(type(authored) == "table" and authored or {}) do
    local copy = {}
    for key, value in pairs(object) do copy[key] = value end
    copy.id = copy.id or ("interactive:" .. tostring(mapId) .. ":" .. i)
    add(copy)
  end
  puzzle = puzzle or puzzleModule(self).describe(self.game, overworld)
  for _, object in ipairs(puzzle.objects or {}) do add(object) end
  return result
end

-- ------------------------------------------------------------ dark maps
-- Decision 37: on a map still dark for lack of Flash, navigation knows only
-- what a sighted player can see there.  Auto-walk, guided navigation and the
-- camera's route refuse, the object list keeps what is in sight, and the
-- camera stays inside it.  Walking by hand and the tiles around the player
-- still work.  Each generation answers the two questions below for itself.
Accessibility.TOO_DARK = "Too dark. Use Flash."

-- Gen 1: field.darkMaps (home/overworld.asm's check), lit by save.flashLit,
-- which lasts between the tunnel's floors.
function Accessibility:isDark(overworld)
  local game = self.game
  local field = game and game.data and game.data.field
  local dark = type(field) == "table" and field.darkMaps
  if type(dark) ~= "table" or (game.save and game.save.flashLit) then return false end
  local mapId = overworld and currentMapId(overworld)
  for _, candidate in ipairs(dark.maps or {}) do
    if candidate == mapId then return true end
  end
  return false
end

-- The screen shows 4 cells left, 5 right, 4 up and 4 down of the player.
function Accessibility:darkOnScreen(overworld, x, y)
  local dx, dy = x - overworld.player.cellX, y - overworld.player.cellY
  return dx >= -4 and dx <= 5 and dy >= -4 and dy <= 4
end

-- Gen 1 darkens the whole screen, with no window of light (PaletteFX): floors
-- go dark grey and everything else black silhouettes, all of it still in view.
function Accessibility:darkCellVisible(overworld, x, y)
  return self:darkOnScreen(overworld, x, y)
end

function Accessibility:darkItemVisible(overworld, item)
  return type(item.x) == "number" and type(item.y) == "number" and item.type ~= "area"
    and self:darkCellVisible(overworld, item.x, item.y)
end

-- The refusal to speak, or nil when the player's map is not dark.
function Accessibility:darkRefusal()
  local overworld = self:worldForCommand()
  if overworld and self:isDark(overworld) then return self.TOO_DARK end
  return nil
end

function Accessibility:selectedBrowseItem(delta)
  local snapshot, reason = self:captureWorld(self.browseFilter)
  if not snapshot then return nil, reason end
  local items = snapshot.browse or {}
  local overworld = self:worldForCommand()
  if overworld and self:isDark(overworld) then
    local visible = {}
    for _, item in ipairs(items) do
      if self:darkItemVisible(overworld, item) then visible[#visible + 1] = item end
    end
    items, snapshot.browse = visible, visible
    if #items == 0 then return nil, self.TOO_DARK end
  end
  if #items == 0 then return nil, "Empty List." end

  local index
  if self.browseSelectionId then
    for i, item in ipairs(items) do
      if item.id == self.browseSelectionId then index = i break end
    end
  end
  index = index or math.max(1, math.min(#items, self.browseIndex or 1))
  if delta and delta ~= 0 then index = ((index - 1 + delta) % #items) + 1 end
  self.browseIndex = index
  self.browseSelectionId = items[index].id
  return items[index], nil, snapshot
end

function Accessibility:announceBrowse(delta)
  local item, reason, snapshot = self:selectedBrowseItem(delta)
  if item then
    self:emitSemantic("browse.selected", {
      id = item.id, label = item.label, description = item.description,
      category = item.category, itemType = item.type,
      filter = self.browseFilter,
      locationName = snapshot and snapshot.locationName,
    })
  else
    self:emitSemantic("browse.failed", {
      reason = reason, filter = self.browseFilter,
    })
  end
  return self:announceManual({ item and item.description or reason })
end

function Accessibility:cycleBrowseFilter(delta)
  local filter, reason = self.worldSnapshot.nextFilter(self.browseFilter, delta)
  if not filter then return self:announceManual({ reason }) end
  self.browseFilter, self.browseIndex, self.browseSelectionId = filter, 1, nil
  local item, itemReason = self:selectedBrowseItem(0)
  self:emitSemantic("browse.filter", {
    filter = filter,
    label = self.worldSnapshot.humanize(filter) or filter,
    selectedId = item and item.id,
    selectedLabel = item and item.label,
    reason = itemReason,
  })
  local parts = { self.worldSnapshot.humanize(filter) or filter }
  parts[#parts + 1] = item and item.description or itemReason
  return self:announceManual(parts)
end

local function tileNumber(map, x, y)
  local ok, value = pcall(map.cellTile, map, x, y)
  return ok and value ~= nil and tostring(value) or "unknown"
end

function Accessibility:readCollisionTiles()
  local overworld, reason = self:worldForCommand()
  if not overworld then return self:announceManual({ reason }) end
  local map, player = overworld.map, overworld.player
  local x, y = player.cellX, player.cellY
  return self:announceManual({
    ("Now on %s, Up %s, Down %s, Left %s, Right %s"):format(
      tileNumber(map, x, y), tileNumber(map, x, y - 1),
      tileNumber(map, x, y + 1), tileNumber(map, x - 1, y),
      tileNumber(map, x + 1, y)),
  })
end

local function battleTargetLabel(battle, target)
  local mon = type(target) == "table" and target.mon or nil
  local name = type(target) == "table" and target.name or nil
  name = name or (type(mon) == "table" and (mon.nickname or mon.species))
  name = tostring(name or "Pok\195\169mon"):gsub("_", " ")
  return (target and (target.isPlayer or (battle and target == battle.player)))
         and ("Your " .. name)
         or ("Enemy " .. name)
end

-- Damage events are emitted when the battle model changes, before the native
-- HP-bar drain catches up. Hold each fact until the corresponding displayed
-- HP stop has completed. Multi-hit attacks therefore speak one result per
-- visible drain in order instead of revealing the final HP early.
function Accessibility:processBattleEvents(state)
  local damageQueue = self.pendingBattleDamage
  local damage = type(damageQueue) == "table" and damageQueue[1] or nil
  if damage then
    -- v0.3.98 adaptation: the old Gen 2 subclass's processGen2BattleDamage
    -- is battle speech and was not carried over (decision 20 covers the
    -- navigation half only); calling it raised an error.  Drop the fact.
    if self.generation == 2 then
      table.remove(damageQueue, 1)
    elseif state ~= damage.battle then
      if not (state and state.isBattle) then
        table.remove(damageQueue, 1)
      end
    else
      local shown = damage.target and tonumber(damage.target.shownHP)
      local ready = damage.hitSubstitute
        or (damage.remainingHP ~= nil and shown ~= nil
            and shown <= damage.remainingHP and not damage.battle.draining)
        or (damage.remainingHP == nil and not damage.battle.draining)
      if ready then
        table.remove(damageQueue, 1)
        local subject = battleTargetLabel(damage.battle, damage.target)
        local text
        if damage.hitSubstitute then
          text = ("%s's substitute took %d damage."):format(subject, damage.damage)
        elseif damage.remainingHP and damage.maxHP then
          text = ("%s lost %d HP. %d of %d HP remaining."):format(
            subject, damage.damage, math.max(0, math.floor(damage.remainingHP)),
            math.max(0, math.floor(damage.maxHP)))
        else
          text = ("%s lost %d HP."):format(subject, damage.damage)
        end
        self:announce(text, { interrupt = false, semantic = {
          kind = "battle.damage", damage = damage.damage,
          remainingHP = damage.remainingHP, maxHP = damage.maxHP,
        } })
      end
    end
  end

  local shakeQueue = self.pendingBallShakes
  local result = type(shakeQueue) == "table" and shakeQueue[1] or nil
  if result then
    table.remove(shakeQueue, 1)
    if state == result.battle then
      local words = { "No shakes.", "One shake.", "Two shakes.", "Three shakes." }
      self:announce(words[math.min(3, result.shakes) + 1], {
        interrupt = false,
        semantic = { kind = "battle.ball_shakes", shakes = result.shakes },
      })
    end
  end
end

function Accessibility:readSonarTerrain()
  local overworld, reason = self:worldForCommand()
  if not overworld then return self:announceManual({ reason }) end
  local x, y = self:ensureSonar(overworld)
  local terrain = self:terrainAt(overworld, x, y)
  local label = terrain and terrain.label or "unknown terrain"
  local parts = { ("Sonar x %d, y %d. %s"):format(x, y, label) }
  if terrain and terrain.direction then
    parts[#parts + 1] = "Moves " .. tostring(terrain.direction)
  end
  if terrain and terrain.description then
    parts[#parts + 1] = terrain.description
  end
  if terrain and terrain.passable == true then
    parts[#parts + 1] = "Passable"
  elseif terrain and terrain.passable == false then
    parts[#parts + 1] = "Blocked"
  end
  return self:announceManual(parts)
end

local function routeCellKey(x, y)
  return tostring(x) .. "," .. tostring(y)
end

function Accessibility:hmAllowed(overworld, moveId, policy)
  policy = policy or 2
  if policy == 3 then return true end
  if policy ~= 2 or type(overworld.partyKnows) ~= "function" then
    return false
  end
  local ok, mon = pcall(overworld.partyKnows, overworld, moveId)
  return ok and mon ~= nil
end

function Accessibility:isCuttableCell(overworld, x, y)
  local map = overworld.map
  if not (map.inBounds and map:inBounds(x, y)
          and type(map.blockAt) == "function") then return false end
  local field = self.game and self.game.data and self.game.data.field
  local ok, swap = pcall(CutTrees.swapAt, map, field, x, y)
  if not ok or not swap then return false end
  local walkOK, walkable = pcall(map.isWalkableCell, map, x, y)
  return not (walkOK and walkable)
end

function Accessibility:hasCardKey()
  local inventory = self.game and self.game.save and self.game.save.inventory
  if type(inventory) ~= "table" then return false end
  local value = inventory.CARD_KEY
  return value == true or (tonumber(value) or 0) > 0
end

function Accessibility:isClosedCardKeyDoorCell(overworld, x, y)
  local terrain = self:terrainAt(overworld, x, y)
  return terrain and terrain.kind == "door"
         and terrain.source == "field.cardKeyDoors"
         and terrain.passable == false
end

function Accessibility:connectionGoals(overworld, item)
  local map = overworld.map
  local goals = {}
  local width, height = map.widthCells, map.heightCells
  if type(width) ~= "number" or type(height) ~= "number" then return goals end
  local function add(x, y)
    local ok, walkable = pcall(map.isWalkableCell, map, x, y)
    local waterOK, water = pcall(map.isWaterCell, map, x, y)
    if (ok and walkable) or (waterOK and water and self:hmAllowed(overworld, "SURF")) then
      goals[#goals + 1] = { x = x, y = y }
    end
  end
  if item.direction == "north" then
    for x = 0, width - 1 do add(x, 0) end
  elseif item.direction == "south" then
    for x = 0, width - 1 do add(x, height - 1) end
  elseif item.direction == "west" then
    for y = 0, height - 1 do add(0, y) end
  elseif item.direction == "east" then
    for y = 0, height - 1 do add(width - 1, y) end
  end
  return goals
end

-- NPCs, signs, and object balls are activated from a neighboring cell; routing
-- onto their own blocked cell produces an instruction the native player cannot
-- execute. Mart clerks and nurses add the engine's counter rule: stand one cell
-- before the counter and interact across it toward the actor two cells away.
function Accessibility:interactionGoals(overworld, item)
  local map = overworld and overworld.map
  if type(map) ~= "table" or type(item) ~= "table" then
    return {}, {}
  end

  local targets = {}
  for _, cell in ipairs(item.interactionCells or {}) do
    if type(cell) == "table" and type(cell.x) == "number"
       and type(cell.y) == "number" then
      targets[#targets + 1] = cell
    end
  end
  if #targets == 0 then
    if type(item.x) ~= "number" or type(item.y) ~= "number" then return {}, {} end
    targets[1] = item
  end

  local goals, instructions, seen = {}, {}, {}
  local interactionInstruction = item.interaction == "cut"
    and "use Cut from the party menu"
    or item.interaction == "card_key" and self:hasCardKey()
    and "use Card Key" or "interact"
  local function usable(x, y)
    local boundsOK, inBounds = pcall(map.inBounds, map, x, y)
    if not boundsOK or not inBounds then return false end
    local walkOK, walkable = pcall(map.isWalkableCell, map, x, y)
    if walkOK and walkable then return true end
    local waterOK, water = pcall(map.isWaterCell, map, x, y)
    return waterOK and water and self:hmAllowed(overworld, "SURF")
  end
  -- Standing on one of the map's own warps to interact would leave the map
  -- (the Rocket Hideout elevator panel is next to the car's exit tile), so a
  -- warp cell is only an approach cell when no other cell will do.
  local warpCells = {}
  for _, warp in ipairs(map.def and map.def.warps or {}) do
    warpCells[routeCellKey(warp.x, warp.y)] = true
  end
  local onWarps = {}
  local function add(x, y, facing, allowWarp)
    local key = routeCellKey(x, y)
    if not allowWarp and warpCells[key] then
      onWarps[#onWarps + 1] = { x, y, facing }
      return
    end
    if not seen[key] and usable(x, y) then
      seen[key] = true
      goals[#goals + 1] = { x = x, y = y }
      if item.routeInstruction then
        instructions[key] = item.routeInstruction
      elseif item.interaction == "closed_gate" then
        instructions[key] = "Closed passage; use a Secret switch"
      else
        instructions[key] = "Face " .. facing .. " and " .. interactionInstruction
      end
    end
  end

  local directions = CARDINAL_ORDER
  if item.requiredFacing and CARDINAL_DELTA[item.requiredFacing] then
    directions = { item.requiredFacing }
  end
  for _, target in ipairs(targets) do
    for _, facing in ipairs(directions) do
      local delta = CARDINAL_DELTA[facing]
      local frontX, frontY = target.x - delta[1], target.y - delta[2]
      local acrossCounter = false
      if item.type == "object" and type(map.isCounterCell) == "function" then
        local counterOK, counter = pcall(map.isCounterCell, map, frontX, frontY)
        acrossCounter = counterOK and counter == true
      end
      if acrossCounter then
        add(target.x - delta[1] * 2, target.y - delta[2] * 2, facing)
      else
        add(frontX, frontY, facing)
      end
    end
  end
  if #goals == 0 then
    for _, cell in ipairs(onWarps) do add(cell[1], cell[2], cell[3], true) end
  end
  return goals, instructions
end

-- Mirror OverworldController:checkLedgeHop without mutating player state. A
-- matching standing/front tile pair consumes one input and lands two cells
-- away, so the route graph must not expose the intermediate ledge tile as a
-- separate player-controlled step.
function Accessibility:ledgeDestination(overworld, x, y, direction)
  local map = overworld and overworld.map
  local delta = CARDINAL_DELTA[direction]
  if type(map) ~= "table" or not delta or type(map.cellTile) ~= "function" then
    return nil
  end
  local frontX, frontY = x + delta[1], y + delta[2]
  local boundsOK, frontInBounds = pcall(map.inBounds, map, frontX, frontY)
  if not boundsOK or not frontInBounds then return nil end
  local standingOK, standing = pcall(map.cellTile, map, x, y)
  local frontOK, front = pcall(map.cellTile, map, frontX, frontY)
  if not standingOK or not frontOK then return nil end
  local field = self.game and self.game.data and self.game.data.field
  local tileset = map.def and map.def.tileset
  for _, ledge in ipairs((field and field.ledges) or {}) do
    if (ledge.tileset or "OVERWORLD") == tileset
       and ledge.facing == direction and ledge.input == direction
       and ledge.standingTile == standing and ledge.ledgeTile == front then
      local landingX, landingY = frontX + delta[1], frontY + delta[2]
      local landingBoundsOK, landingInBounds = pcall(
        map.inBounds, map, landingX, landingY)
      local walkOK, walkable = pcall(
        map.isWalkableCell, map, landingX, landingY)
      local occupiedOK, occupied = pcall(Collision.occupied,
        overworld.entities or overworld.npcs or {}, landingX, landingY,
        overworld.player)
      if landingBoundsOK and landingInBounds and walkOK and walkable
         and occupiedOK and occupied == nil then
        return landingX, landingY
      end
      return nil
    end
  end
  return nil
end

local function spinnerAt(field, mapId, x, y)
  local byMap = field and field.spinners and field.spinners[mapId]
  for _, spinner in ipairs(byMap or {}) do
    if spinner.x == x and spinner.y == y then return spinner end
  end
  return nil
end

local function allFlagsSet(flags, names)
  for _, name in ipairs(names or {}) do
    if not flags[name] then return false end
  end
  return true
end

function Accessibility:seafoamCurrentAt(overworld, x, y, policy)
  local map = overworld and overworld.map
  local field = self.game and self.game.data and self.game.data.field
  local mapId = map and (map.id or (map.def and map.def.id))
  local seafoam = field and field.seafoam and field.seafoam[mapId]
  if not seafoam then return nil end
  local surfing = overworld.player and overworld.player.surfing == true
  if not surfing and not self:hmAllowed(overworld, "SURF", policy) then return nil end
  local flags = self.game and self.game.save and self.game.save.flags or {}

  local forcedExit = seafoam.forcedExit
  if forcedExit and not allFlagsSet(flags, forcedExit.activeUntilEvents) then
    for _, cell in ipairs(forcedExit.coords or {}) do
      if cell.x == x and cell.y == y then
        return { x = x, y = y, kind = "current", moves = {
          { dir = "up", count = y == 17 and 2 or 1 },
        } }
      end
    end
  end
  if not allFlagsSet(flags, seafoam.currentsDisabledByEvents) then
    for _, current in ipairs(seafoam.currents or {}) do
      if current.x == x and current.y == y then
        return { x = current.x, y = current.y, kind = "current",
                 moves = current.moves }
      end
    end
  end
  local entry = seafoam.entryCurrent
  if entry then
    local plugged = true
    local holes = seafoam.pluggedByHolesOn
                 and seafoam.pluggedByHolesOn.holes or {}
    for _, hole in ipairs(holes) do
      if not flags[hole.boulderEvent] then plugged = false end
    end
    if not plugged and entry.x == x and entry.y == y then
      return { x = entry.x, y = entry.y, kind = "current",
               moves = entry.moves }
    end
  end
  return nil
end

local function forcedRecordAt(self, overworld, field, mapId, x, y, policy)
  local spinner = spinnerAt(field, mapId, x, y)
  if spinner then return spinner, "spinner" end
  local current = self:seafoamCurrentAt(overworld, x, y, policy)
  if current then return current, "current" end
  return nil
end

-- Resolve the same post-step priority as the native controller: spinner first,
-- then Seafoam current while surfing. Chained forced records are folded into
-- one uncontrollable action; malformed/cyclic mod data fails closed.
function Accessibility:forcedDestination(overworld, x, y, enteringDirection,
                                          requiredKind, policy)
  local map = overworld and overworld.map
  local field = self.game and self.game.data and self.game.data.field
  local mapId = map and (map.id or (map.def and map.def.id))
  local record, kind = forcedRecordAt(self, overworld, field, mapId, x, y, policy)
  if not record or (requiredKind and kind ~= requiredKind) then
    return nil, nil, nil, false
  end

  local parts = { kind == "spinner"
    and ("Move " .. enteringDirection .. " onto spinner")
    or ("Move " .. enteringDirection .. " into current") }
  local firstKind = kind
  local seen = {}
  while record do
    local key = kind .. ":" .. routeCellKey(record.x, record.y)
    if seen[key] then return nil, nil, nil, true end
    seen[key] = true
    for _, move in ipairs(record.moves or {}) do
      local delta = CARDINAL_DELTA[move.dir]
      local count = tonumber(move.count)
      if not delta or not count or count < 1 or count % 1 ~= 0 then
        return nil, nil, nil, true
      end
      for _ = 1, count do
        x, y = x + delta[1], y + delta[2]
        local boundsOK, inBounds = pcall(map.inBounds, map, x, y)
        if not boundsOK or not inBounds then return nil, nil, nil, true end
      end
      parts[#parts + 1] = (kind == "current" and "current " or "forced ")
        .. tostring(count) .. " " .. move.dir
    end
    record, kind = forcedRecordAt(self, overworld, field, mapId, x, y, policy)
  end
  return x, y, table.concat(parts, ", then "), true, firstKind
end

function Accessibility:spinnerDestination(overworld, x, y, enteringDirection)
  return self:forcedDestination(overworld, x, y, enteringDirection, "spinner")
end

function Accessibility:routeNeighbors(overworld, x, y, policy)
  local edges = {}
  for _, direction in ipairs(CARDINAL_ORDER) do
    local delta = CARDINAL_DELTA[direction]
    local landingX, landingY = self:ledgeDestination(
      overworld, x, y, direction)
    if landingX ~= nil then
      edges[#edges + 1] = {
        x = landingX, y = landingY, direction = direction,
        kind = "ledge", instruction = "Jump ledge " .. direction,
      }
    else
      local stepX, stepY = x + delta[1], y + delta[2]
      local forcedX, forcedY, instruction, forced, forcedKind =
        self:forcedDestination(overworld, stepX, stepY, direction, nil, policy)
      if forced then
        if forcedX ~= nil then
          edges[#edges + 1] = {
            x = forcedX, y = forcedY, direction = direction,
            kind = forcedKind, instruction = instruction,
          }
        end
      else
        edges[#edges + 1] = {
          x = stepX, y = stepY, direction = direction,
        }
      end
    end
  end
  return edges
end

function Accessibility:routeNarration(overworld, result, routePolicy)
  if result.cost == 0 then return { "Already there" } end
  routePolicy = routePolicy or result.policy or 1
  local map = overworld.map
  local tokens = {}
  local seenCardDoors, seenCutBlocks = {}, {}
  local function addToken(command, countable)
    local previous = tokens[#tokens]
    if countable and previous and previous.countable
       and previous.command == command then
      previous.count = previous.count + 1
    else
      tokens[#tokens + 1] = { command = command, count = 1,
                              countable = countable }
    end
  end
  for _, step in ipairs(result.steps) do
    local command = step.direction
    local countable = true
    local fromWaterOK, fromWater = pcall(
      map.isWaterCell, map, step.fromX, step.fromY)
    local toWaterOK, toWater = pcall(map.isWaterCell, map, step.x, step.y)
    fromWater = fromWaterOK and fromWater or false
    toWater = toWaterOK and toWater or false
    if step.kind == "ledge" or step.kind == "spinner"
       or step.kind == "current" then
      command = step.instruction or ("Jump ledge " .. step.direction)
      countable = false
    elseif routePolicy > 1
       and self:isClosedCardKeyDoorCell(overworld, step.x, step.y) then
      local doorKey = tostring(math.floor(step.x / 2)) .. ","
                    .. tostring(math.floor(step.y / 2))
      if not seenCardDoors[doorKey] then
        seenCardDoors[doorKey] = true
        addToken("Use Card Key facing " .. step.direction, false)
      end
    elseif routePolicy > 1
       and self:isCuttableCell(overworld, step.x, step.y) then
      -- A native Cut target is a 2x2 map block. One Cut action swaps the
      -- whole block, even when the planned path crosses two of its cells.
      local cutKey = tostring(math.floor(step.x / 2)) .. ","
                   .. tostring(math.floor(step.y / 2))
      if not seenCutBlocks[cutKey] then
        seenCutBlocks[cutKey] = true
        addToken("Use Cut facing " .. step.direction, false)
      end
    elseif routePolicy > 1 and toWater and not fromWater then
      addToken("Use Surf facing " .. step.direction, false)
    elseif routePolicy > 1 and fromWater and not toWater then
      addToken("Exit water " .. step.direction, false)
      command = nil
    end
    if command then addToken(command, countable) end
  end
  local parts = {}
  for _, token in ipairs(tokens) do
    parts[#parts + 1] = token.countable
      and (tostring(token.count) .. " " .. token.command) or token.command
  end
  return parts
end

function Accessibility:worldRouteRequest(goals, policyOverride)
  local overworld, reason = self:worldForCommand()
  if not overworld then return nil, reason end
  if type(goals) ~= "table" or #goals == 0 then return nil, "No path" end
  local map, player = overworld.map, overworld.player
  local routePolicy = policyOverride or 1
  local goalSet = {}
  for _, goal in ipairs(goals) do goalSet[routeCellKey(goal.x, goal.y)] = true end

  local blocked, routeEntities = {}, {}
  for _, entity in ipairs(overworld.entities or overworld.npcs or {}) do
    if entity ~= player then
      -- v0.3.98 addition: an entity the game itself lets the player walk
      -- through (`passable`, Yellow's following Pikachu) is no wall either.
      -- It stands right behind the player, so blocking it made every route
      -- that starts by turning back detour or fail in a corridor.
      local ignorable = entity.passable == true
                        or (type(entity.def) == "table"
                            and entity.def.ignorable == true)
      blocked[#blocked + 1] = {
        cellX = entity.cellX, cellY = entity.cellY,
        targetX = entity.targetX, targetY = entity.targetY,
        ignorable = ignorable,
      }
      -- Match Pathfinder's blockIgnorable=false contract when asking native
      -- collision and mod hooks. Decorative/explicitly ignorable entities do
      -- not become route walls; every other current or reserved cell does.
      if not ignorable then routeEntities[#routeEntities + 1] = entity end
    end
  end
  for i, warp in ipairs((map.def and map.def.warps) or {}) do
    if not goalSet[routeCellKey(warp.x, warp.y)] then
      blocked[#blocked + 1] = { x = warp.x, y = warp.y,
                                id = "warp:" .. tostring(i) }
    end
  end

  local function canTraverse(fromX, fromY, toX, toY, direction, _, edge)
    if edge and edge.kind == "ledge" then
      local landingX, landingY = self:ledgeDestination(
        overworld, fromX, fromY, direction)
      return landingX == toX and landingY == toY
    end
    local probe = setmetatable({
      cellX = fromX, cellY = fromY,
      surfing = player.surfing == true
        or (map:isWaterCell(fromX, fromY) and routePolicy > 1),
    }, { __index = player })
    local allowed = Collision.canMove(
      map, routeEntities, probe, direction)
    if edge and (edge.kind == "spinner" or edge.kind == "current") then
      if not allowed then
        local delta = CARDINAL_DELTA[direction]
        local waterOK, water = pcall(
          map.isWaterCell, map, fromX + delta[1], fromY + delta[2])
        allowed = waterOK and water and self:hmAllowed(overworld, "SURF")
      end
      if not allowed then return false end
      local delta = CARDINAL_DELTA[direction]
      local landingX, landingY, _, forced, kind = self:forcedDestination(
        overworld, fromX + delta[1], fromY + delta[2], direction, nil,
        routePolicy)
      return forced and kind == edge.kind and landingX == toX and landingY == toY
    end
    if allowed then return true end
    if routePolicy == 1 then return false end
    if self:isClosedCardKeyDoorCell(overworld, toX, toY)
       and (self:hasCardKey() or routePolicy >= 3) then return true end
    if map:isWaterCell(toX, toY)
       and self:hmAllowed(overworld, "SURF", routePolicy) then
      return true
    end
    if self:isCuttableCell(overworld, toX, toY)
       and self:hmAllowed(overworld, "CUT", routePolicy) then return true end
    return false
  end

  return {
    start = { x = player.cellX, y = player.cellY },
    goals = goals,
    bounds = { width = map.widthCells, height = map.heightCells },
    blockedCells = blocked,
    -- Interaction targets are converted to reachable standing cells before
    -- search. A selected wall/person is never a license to enter its cell.
    allowBlockedGoal = false,
    policy = routePolicy,
    canTraverse = canTraverse,
    neighbors = function(x, y)
      return self:routeNeighbors(overworld, x, y, routePolicy)
    end,
    -- This is a guardrail for pathological mod maps or traversal callbacks,
    -- not a normal-map limit.  os.clock measures CPU time, so time spent
    -- yielded between LÖVE frames does not consume this budget.
    maxSeconds = 0.25,
  }, overworld
end

local function regionalObjectVisible(save, mapId, object)
  local toggles = save.objectToggles and save.objectToggles[mapId] or {}
  local visible = not object.hidden
  if object.name and toggles[object.name] ~= nil then
    visible = toggles[object.name]
  end
  if object.item and save.itemsTaken
     and save.itemsTaken[mapId .. "_obj_" .. tostring(object.index)] then
    visible = false
  end
  if object.pokemon and save.defeatedTrainers
     and save.defeatedTrainers[mapId .. "_obj_" .. tostring(object.index)] then
    visible = false
  end
  return visible
end

-- Maps that form one building or zone share the first two words of their id
-- (SAFARI_ZONE_WEST, SAFARI_ZONE_GATE; SILPH_CO_5F, SILPH_CO_ELEVATOR).  Only
-- groups of two or more maps count, so a single town is not an area.
local function areaKey(mapId)
  return type(mapId) == "string" and mapId:match("^([A-Z0-9]+_[A-Z0-9]+)") or nil
end

-- The Area category: every item ball still in place on the other maps of the
-- current area, named with its map, nearest first by map name.  Built from
-- map data and the save (regionalObjectVisible skips collected items), so
-- nothing is hand-listed.  Selecting one starts a cross-map journey.
function Accessibility:areaBrowse(overworld)
  local data = self.game and self.game.data
  local maps = data and data.maps or {}
  local here = currentMapId(overworld)
  local key = areaKey(here)
  local items = {}
  if not key then return items end
  local members = {}
  for mapId in pairs(maps) do
    if areaKey(mapId) == key then members[#members + 1] = mapId end
  end
  if #members < 2 then return items end
  table.sort(members)
  local save = self.game.save or {}
  for _, mapId in ipairs(members) do
    if mapId ~= here then
      local mapName = self:regionalDestinationName(mapId)
      for _, object in ipairs(maps[mapId].objects or {}) do
        if object.item and regionalObjectVisible(save, mapId, object) then
          local machine = self.worldSnapshot.machineLabel
            and self.worldSnapshot.machineLabel({ game = self.game }, object.item)
          local label = tostring(machine or self.worldSnapshot.humanize(object.item) or object.item)
            .. ", " .. tostring(mapName)
          items[#items + 1] = {
            id = "area:" .. mapId .. ":" .. tostring(object.index),
            type = "area", category = "area", label = label, description = label,
            mapId = mapId, x = object.x, y = object.y,
          }
        end
      end
    end
  end
  return items
end

function Accessibility:regionalStaticWorld(mapId, start)
  local data = self.game and self.game.data
  local def = data and data.maps and data.maps[mapId]
  local tileset = def and data.tilesets and data.tilesets[def.tileset]
  if not (def and tileset) then return nil end
  local ok, map = pcall(Map.new, def, tileset)
  if not ok or type(map) ~= "table" then return nil end
  local player = {
    cellX = start.x, cellY = start.y, facing = "down", surfing = false,
  }
  local save = self.game.save or {}
  local entities = { player }
  for _, object in ipairs(def.objects or {}) do
    -- an item ball on a floor not yet reached can be picked up on the way
    if object.ignorable ~= true and object.sprite ~= "SPRITE_POKE_BALL"
       and regionalObjectVisible(save, mapId, object) then
      entities[#entities + 1] = {
        cellX = object.x, cellY = object.y, def = object,
      }
    end
  end
  return { isOverworld = true, map = map, player = player,
           entities = entities, npcs = entities }
end

function Accessibility:regionalDryRoute(mapId, start, goals, useLive,
                                         maxSeconds)
  local overworld
  if useLive then
    local live = self:worldForCommand()
    if live and currentMapId(live) == mapId
       and live.player.cellX == start.x and live.player.cellY == start.y then
      local options = self:worldRouteRequest(goals, 1)
      if not options then return nil end
      options.maxSeconds = maxSeconds or options.maxSeconds
      return Pathfinder.find(options)
    end
  end
  overworld = self:regionalStaticWorld(mapId, start)
  if not overworld then return nil end
  local map, player = overworld.map, overworld.player
  local goalSet, blocked, routeEntities = {}, {}, {}
  for _, goal in ipairs(goals or {}) do
    goalSet[routeCellKey(goal.x, goal.y)] = true
  end
  for _, entity in ipairs(overworld.entities or {}) do
    if entity ~= player then
      blocked[#blocked + 1] = entity
      routeEntities[#routeEntities + 1] = entity
    end
  end
  for i, warp in ipairs((map.def and map.def.warps) or {}) do
    if not goalSet[routeCellKey(warp.x, warp.y)] then
      blocked[#blocked + 1] = {
        x = warp.x, y = warp.y, id = "warp:" .. tostring(i),
      }
    end
  end
  local function canTraverse(fromX, fromY, _, _, direction)
    local probe = setmetatable({
      cellX = fromX, cellY = fromY, surfing = false,
    }, { __index = player })
    return Collision.canMove(map, routeEntities, probe, direction)
  end
  return Pathfinder.find({
    start = start, goals = goals,
    bounds = { width = map.widthCells, height = map.heightCells },
    blockedCells = blocked, allowBlockedGoal = false, policy = 1,
    canTraverse = canTraverse,
    neighbors = function(x, y) return self:routeNeighbors(overworld, x, y, 1) end,
    maxSeconds = maxSeconds or 0.25,
  })
end

local OPPOSITE_DIRECTION = {
  north = "south", south = "north", east = "west", west = "east",
}

-- v0.3.98 adaptation: a warp listed in map data that the game never fires
-- (Silph Co. 1F has one to 3F off any warp tile) would send journeys to a
-- dead end, so only warps the object list would show are transitions.
local function activeWarp(self, def, mapId, warp, index)
  local data = self.game.data
  local tileset = data.tilesets and data.tilesets[def.tileset]
  local check = self.worldSnapshot.browsableWarp
  if not (tileset and check) then return true end
  self.regionalMaps = self.regionalMaps or setmetatable({}, { __mode = "k" })
  local map = self.regionalMaps[def]
  if map == nil then
    local ok, built = pcall(Map.new, def, tileset)
    map = ok and built or false
    self.regionalMaps[def] = map
  end
  if not map then return true end
  local ok, active = pcall(check, map, warp, index, { generation = 1, field = data.field })
  return not ok or active
end

function Accessibility:regionalTransitions(mapId)
  local data = self.game and self.game.data
  local def = data and data.maps and data.maps[mapId]
  if not def then return {} end
  local result = {}
  for index, warp in ipairs(def.warps or {}) do
    if not activeWarp(self, def, mapId, warp, index) then goto nextWarp end
    local destinationId = self.worldSnapshot.destinationId(
      self.game and self.game.overworld or {}, mapId, warp,
      FieldDefaults.field(data, "lastMapRewrites"))
    local destination = destinationId and data.maps[destinationId]
    local arrival = destination and destination.warps
                    and destination.warps[warp.destWarp]
    if destination and arrival then
      result[#result + 1] = {
        kind = "warp", index = index,
        x = warp.x, y = warp.y,
        destMap = destinationId, destX = arrival.x, destY = arrival.y,
      }
    end
    ::nextWarp::
  end

  local sourceTileset = data.tilesets and data.tilesets[def.tileset]
  for _, direction in ipairs({ "north", "east", "south", "west" }) do
    local connection = (def.connections or {})[direction]
    local destination = connection and connection.map
                        and data.maps[connection.map]
    local destinationTileset = destination and data.tilesets
                               and data.tilesets[destination.tileset]
    if connection and sourceTileset and destination and destinationTileset
       and OPPOSITE_DIRECTION[direction] then
      local width, height = def.width * 2, def.height * 2
      local count = (direction == "north" or direction == "south")
                    and width or height
      for coordinate = 0, count - 1 do
        local x = (direction == "west") and 0
               or (direction == "east") and (width - 1) or coordinate
        local y = (direction == "north") and 0
               or (direction == "south") and (height - 1) or coordinate
        local destWidth, destHeight = destination.width * 2, destination.height * 2
        local destX, destY
        if direction == "north" then
          destX, destY = x - connection.offset * 2, destHeight - 1
        elseif direction == "south" then
          destX, destY = x - connection.offset * 2, 0
        elseif direction == "west" then
          destX, destY = destWidth - 1, y - connection.offset * 2
        else
          destX, destY = 0, y - connection.offset * 2
        end
        destX = math.max(0, math.min(destWidth - 1, destX))
        destY = math.max(0, math.min(destHeight - 1, destY))
        if Map.defIsWalkableCell(def, sourceTileset, x, y)
           and Map.defPassable(destination, destinationTileset,
                               destX, destY, false) then
          result[#result + 1] = {
            kind = "connection", direction = direction,
            x = x, y = y, destMap = connection.map,
            destX = destX, destY = destY,
          }
        end
      end
    end
  end
  return result
end

function Accessibility:regionalDestinationName(mapId)
  local data = self.game and self.game.data
  local def = data and data.maps and data.maps[mapId]
  return self.worldSnapshot.locationName(
    def or { id = mapId }, mapId, nil,
    self.game.save and self.game.save.player and self.game.save.player.name,
    nil, self.game.save and self.game.save.version,
    self.game.save and self.game.save.player and self.game.save.player.rival)
end

function Accessibility:regionalNextLeg(navigation)
  local overworld = self:worldForCommand()
  if not overworld then return nil, "Not on a map" end
  local mapId = currentMapId(overworld)
  -- The search sees the boulders where they are only on this floor, so a floor they close
  -- looks open when reached by going out and back in, and the journey bounced between two
  -- floors for ever (Seafoam B1F's first stairs).  It takes no way twice.
  local taken = navigation.takenTransitions or {}
  navigation.takenTransitions = taken
  local crossing = navigation.lastTransition
  if crossing and crossing.destMap == mapId then
    taken[crossing.mapId .. ":" .. crossing.x .. "," .. crossing.y] = true
    navigation.lastTransition = nil
  end
  local function search(useLive)
    return RegionalPathfinder.find({
    start = {
      mapId = mapId, x = overworld.player.cellX, y = overworld.player.cellY,
    },
    target = {
      mapId = navigation.targetMapId, goals = navigation.targetGoals,
    },
    route = function(routeMapId, start, goals, initial, budget)
      return self:regionalDryRoute(
        routeMapId, start, goals, useLive and initial, budget)
    end,
    transitions = function(routeMapId)
      local open = {}
      for _, transition in ipairs(self:regionalTransitions(routeMapId)) do
        if not taken[routeMapId .. ":" .. transition.x .. "," .. transition.y] then
          open[#open + 1] = transition
        end
      end
      return open
    end,
    maxStates = 400, maxTransitions = 16, -- (Pokémon Tower 2F spent 96 on Lavender Town's houses)
    -- Olivine Lighthouse, with sides reached only through drops, takes 0.7 to
    -- 0.9 seconds from its first floor (measured 2026-11-03).
    maxSeconds = 1.5, maxRouteSeconds = 0.05,
    })
  end
  local result, reason = search(true)
  if not result then
    -- Someone or something in the only way on (Pokemon Tower 6F's Rare Candy): say so.
    local around = type(self.routeNeeds) == "function" and search(false) or nil
    local way = around and around.firstTransition
    local needs = way and self:routeNeeds({ { x = way.x, y = way.y } })
    if type(needs) == "string" and needs:find("^Blocked by") then return nil, needs end
    return nil, reason
  end
  if result.final then
    -- v0.3.98: an Area target's cells are worked out on the map the
    -- journey began on; a cell outside this (smaller) map makes the
    -- Pathfinder refuse the whole last leg ("goal is outside bounds")
    local goals = {}
    for _, goal in ipairs(navigation.targetGoals or {}) do
      local okBounds, inside = pcall(overworld.map.inBounds, overworld.map, goal.x, goal.y)
      if not okBounds or inside then goals[#goals + 1] = goal end
    end
    return {
      final = true, goals = #goals > 0 and goals or navigation.targetGoals,
      appendInstructions = navigation.targetAppendInstructions,
    }
  end
  local transition = result.firstTransition
  if not transition then return nil, "no regional transition" end
  navigation.lastTransition = {
    mapId = mapId, x = transition.x, y = transition.y, destMap = transition.destMap,
  }
  local destinationName = self:regionalDestinationName(transition.destMap)
  local instruction = transition.kind == "connection"
    and ("Continue " .. transition.direction .. " to " .. destinationName)
    or ("Continue to " .. destinationName)
  return {
    final = false,
    goals = { { x = transition.x, y = transition.y } },
    nextMapId = transition.destMap,
    appendInstructions = function(parts)
      parts[#parts + 1] = instruction
    end,
  }
end

-- A door can be physically valid yet unavailable because a live story actor
-- occupies every cell from which it can be entered. Leaving the map cannot
-- solve that condition, so do not launch a Kanto-wide journey search. This
-- deliberately describes the live obstruction without guessing which story
-- flag will eventually remove it.
function Accessibility:blockedWarpEntrance(navigation)
  if not navigation or navigation.targetType ~= "warp" then return false end
  local overworld = self:worldForCommand()
  if not overworld or navigation.targetMapId ~= currentMapId(overworld) then
    return false
  end
  local map, player = overworld.map, overworld.player
  local entities = {}
  for _, entity in ipairs(overworld.entities or overworld.npcs or {}) do
    local ignorable = type(entity.def) == "table"
                      and entity.def.ignorable == true
    if entity ~= player and not ignorable then entities[#entities + 1] = entity end
  end
  local viableApproach = false
  for _, goal in ipairs(navigation.targetGoals or {}) do
    for _, direction in ipairs(CARDINAL_ORDER) do
      local delta = CARDINAL_DELTA[direction]
      local fromX, fromY = goal.x - delta[1], goal.y - delta[2]
      local inBounds = map:inBounds(fromX, fromY)
      local walkable = inBounds and map:isWalkableCell(fromX, fromY)
      if walkable then
        local probe = setmetatable({
          cellX = fromX, cellY = fromY, surfing = false,
        }, { __index = player })
        if Collision.canMove(map, {}, probe, direction) then
          viableApproach = true
          if not Collision.occupied(entities, fromX, fromY) then
            return false
          end
        end
      end
    end
  end
  return viableApproach
end

local function requirementPhrase(requirements)
  local ordered = {}
  local labels = {
    CARD_KEY = "Card Key", CUT = "Cut", SURF = "Surf", STRENGTH = "Strength",
    WHIRLPOOL = "Whirlpool", WATERFALL = "Waterfall",
  }
  local known = {}
  for _, move in ipairs({
    "CARD_KEY", "CUT", "SURF", "STRENGTH", "WHIRLPOOL", "WATERFALL",
  }) do
    known[move] = true
    if requirements[move] then
      ordered[#ordered + 1] = labels[move]
    end
  end
  -- v0.3.98: Gen 2 also names a missing badge (HIVE_BADGE -> "Hive Badge")
  local extra = {}
  for key, needed in pairs(requirements) do
    if needed and not known[key] and type(key) == "string" then extra[#extra + 1] = key end
  end
  table.sort(extra)
  for _, key in ipairs(extra) do
    ordered[#ordered + 1] = (key:lower():gsub("_", " "):gsub("(%a)(%a*)", function(a, b)
      return a:upper() .. b
    end))
  end
  if #ordered == 0 then return "Cannot reach yet" end
  if #ordered == 1 then return "Needs " .. ordered[1] end
  return "Needs " .. table.concat(ordered, ", ", 1, #ordered - 1)
    .. " and " .. ordered[#ordered]
end
-- v0.3.98: FireRed's journey planner names what a journey still needs
-- with the same words (nav/gen3/Navigation.lua journeyRequirement).
Accessibility.requirementPhrase = requirementPhrase

-- Describe only capabilities the player cannot currently use. A route may
-- still cross and narrate those cells; the requirement is context, never a
-- substitute for the full directions.
function Accessibility:routeRequirements(overworld, result)
  local map = overworld.map
  local requirements = {}
  for _, step in ipairs(result.steps or {}) do
    if self:isClosedCardKeyDoorCell(overworld, step.x, step.y)
       and not self:hasCardKey() then
      requirements.CARD_KEY = true
    end
    if self:isCuttableCell(overworld, step.x, step.y)
       and not self:hmAllowed(overworld, "CUT", 2) then
      requirements.CUT = true
    end
    local fromOK, fromWater = pcall(
      map.isWaterCell, map, step.fromX, step.fromY)
    local toOK, toWater = pcall(map.isWaterCell, map, step.x, step.y)
    if toOK and toWater and not (fromOK and fromWater)
       and not self:hmAllowed(overworld, "SURF", 2) then
      requirements.SURF = true
    end
  end
  return requirements
end

-- Compatibility helper retained for mods/tests that ask only for the short
-- availability phrase. Normal navigation uses the complete automatic route.
function Accessibility:routeRequirement(goals)
  local options, overworldOrReason = self:worldRouteRequest(goals, 3)
  if not options then return "Cannot reach yet" end
  local result = Pathfinder.find(options)
  if not result then return "Cannot reach yet" end
  return requirementPhrase(self:routeRequirements(overworldOrReason, result))
end

function Accessibility:finishWorldRoute(overworld, result, routeError,
                                         goals, diagnoseRequirements,
                                         routePolicy)
  if not result then
    if routeError == "no path" then
      routeError = diagnoseRequirements and self:routeRequirement(goals)
                   or "No path"
    end
    return nil, routeError
  end
  routePolicy = routePolicy or result.policy or 1
  result.policy = routePolicy
  local parts = self:routeNarration(overworld, result, routePolicy)
  if routePolicy == 3 then
    local phrase = requirementPhrase(self:routeRequirements(overworld, result))
    if phrase ~= "Cannot reach yet" then table.insert(parts, 1, phrase) end
  end
  return parts, nil, result
end

function Accessibility:findWorldRoute(goals)
  local overworld
  for routePolicy = 1, 3 do
    local options, overworldOrReason = self:worldRouteRequest(goals, routePolicy)
    if not options then return nil, overworldOrReason end
    overworld = overworldOrReason
    local result, routeError = Pathfinder.find(options)
    if result then
      return self:finishWorldRoute(overworld, result, nil, goals, false,
                                   routePolicy)
    end
    if routeError ~= "no path" then return nil, routeError end
  end
  return nil, "No path"
end

function Accessibility:cancelPendingRoute(announce)
  local pending = self.pendingRoute
  if not pending then return false end
  pending.task:cancel()
  self.pendingRoute = nil
  if announce then self:announceManual({ "Route cancelled" }) end
  return true
end

function Accessibility:stopNavigation(announce)
  local hadNavigation = self.activeNavigation ~= nil
  local pending = self.pendingRoute
  if pending and pending.continuous then
    pending.task:cancel()
    self.pendingRoute = nil
    hadNavigation = true
  end
  self.activeNavigation = nil
  if hadNavigation then
    self:emitSemantic("navigation.stopped", {
      announced = announce == true,
    })
  end
  if announce and hadNavigation then
    self:announceManual({ "Navigation stopped" })
  end
  return hadNavigation
end

local function continuousDirectiveKey(text)
  local direction = text:match("^%d+ (%a+)$")
  if direction and not CARDINAL_DELTA[direction] then direction = nil end
  if direction then return "move:" .. direction end
  local move
  move, direction = text:match("^Use (%a+) facing (%a+), then move %a+$")
  if direction and not CARDINAL_DELTA[direction] then direction = nil end
  if move and direction then return move:lower() .. ":" .. direction end
  move, direction = text:match("^Use (%a+) facing (%a+)$")
  if direction and not CARDINAL_DELTA[direction] then direction = nil end
  if move and direction then return move:lower() .. ":" .. direction end
  direction = text:match("^Exit water (%a+)$")
  if direction and not CARDINAL_DELTA[direction] then direction = nil end
  if direction then return "move:" .. direction end
  return "instruction:" .. text
end

local function navigationDirectivePayload(text, key, result, navigation)
  local payload = {
    text = text,
    directiveKey = key,
    routeCost = result and result.cost,
    targetId = navigation and navigation.targetId,
    targetLabel = navigation and navigation.targetLabel,
  }
  local count, direction = text:match("^(%d+) (%a+)$")
  if count and CARDINAL_DELTA[direction] then
    payload.action = "move"
    payload.direction = direction
    payload.distance = tonumber(count)
    return payload
  end
  direction = text:match("^Jump ledge (%a+)$")
  if direction and CARDINAL_DELTA[direction] then
    payload.action = "move"
    payload.direction = direction
    payload.distance = 1
    payload.movementKind = "ledge"
    return payload
  end
  direction = text:match("^Face (%a+) and interact$")
  if direction and CARDINAL_DELTA[direction] then
    payload.action = "interact"
    payload.direction = direction
    return payload
  end
  direction = text:match("^Continue (%a+)")
  direction = CARDINAL_ALIAS[direction] or direction
  if direction and CARDINAL_DELTA[direction] then
    payload.action = "continue"
    payload.direction = direction
    return payload
  end
  local after
  move, direction, after = text:match(
    "^Use (%a+) facing (%a+), then move (%a+)$")
  if move and direction and after and CARDINAL_DELTA[direction]
     and CARDINAL_DELTA[after] then
    payload.action = "field_move"
    payload.move = move:upper()
    payload.direction = direction
    payload.followDirection = after
    return payload
  end
  move, direction = text:match("^Use (%a+) facing (%a+)$")
  if move and direction and CARDINAL_DELTA[direction] then
    payload.action = "field_move"
    payload.move = move:upper()
    payload.direction = direction
    return payload
  end
  direction = text:match("^Exit water (%a+)$")
  if direction and CARDINAL_DELTA[direction] then
    payload.action = "move"
    payload.direction = direction
    payload.distance = 1
    return payload
  end
  local landingDistance
  direction, landingDistance = text:match(
    "^Move (%a+) onto ice; slide (%d+) cells$")
  if direction and CARDINAL_DELTA[direction] then
    payload.action = "move"
    payload.direction = direction
    payload.distance = 1
    payload.movementKind = "ice"
    payload.landingDistance = tonumber(landingDistance)
    return payload
  end
  local landingX, landingY
  direction, landingX, landingY = text:match(
    "^Move (%a+) into current; carried to x (%d+), y (%d+)$")
  if direction and CARDINAL_DELTA[direction] then
    payload.action = "move"
    payload.direction = direction
    payload.distance = 1
    payload.movementKind = "current"
    payload.landingX = tonumber(landingX)
    payload.landingY = tonumber(landingY)
    return payload
  end
  direction = text:match("push (%a+)")
  if direction and CARDINAL_DELTA[direction] then
    payload.action = "push"
    payload.direction = direction
    return payload
  end
  payload.action = "instruction"
  return payload
end

function Accessibility:completeContinuousRoute(pending, result, routeError)
  local navigation = pending.navigation
  if navigation ~= self.activeNavigation then return false end
  local parts, normalizedError, finalResult = self:finishWorldRoute(
    pending.overworld, result, routeError, pending.goals, true,
    pending.routePolicy)
  if not parts then
    self.activeNavigation = nil
    self:emitSemantic("navigation.failed", {
      reason = normalizedError or "Cannot reach yet",
      targetId = navigation.targetId,
      targetLabel = navigation.targetLabel,
    })
    return self:announceManual({ normalizedError or "Cannot reach yet" })
  end
  if pending.appendInstructions then
    pending.appendInstructions(parts, finalResult)
  end

  local output, directive, directiveKey = {}, nil, nil
  if navigation.pendingLocation then
    output[#output + 1] = navigation.pendingLocation
    navigation.pendingLocation = nil
  end
  if navigation.pendingPuzzleIntro then
    output[#output + 1] = navigation.pendingPuzzleIntro
    navigation.pendingPuzzleIntro = nil
  end
  if navigation.pendingPreamble then
    -- If the route starts on its target, the arrival instruction below already
    -- names the transition. Otherwise speak irreversible-transition context
    -- once, alongside the first live direction, and never on step refreshes.
    if not finalResult or finalResult.cost > 0 then
      output[#output + 1] = navigation.pendingPreamble
    end
    navigation.pendingPreamble = nil
  end
  for _, part in ipairs(parts) do
    if part:match("^Needs ") then
      if not navigation.announcedRequirements[part] then
        navigation.announcedRequirements[part] = true
        output[#output + 1] = part
      end
    elseif part ~= "Already there" and not directive then
      directive = part
      directiveKey = continuousDirectiveKey(part)
    end
  end

  local navigationEvent
  if finalResult and finalResult.cost == 0 then
    if navigation.puzzle then
      if directive and directiveKey ~= navigation.lastDirectiveKey then
        navigation.lastDirectiveKey = directiveKey
        output[#output + 1] = directive
        navigationEvent = navigationDirectivePayload(
          directive, directiveKey, finalResult, navigation)
      end
    elseif navigation.journey and not navigation.currentLegFinal then
      if directive and directiveKey ~= navigation.lastDirectiveKey then
        navigation.lastDirectiveKey = directiveKey
        output[#output + 1] = directive
        navigationEvent = navigationDirectivePayload(
          directive, directiveKey, finalResult, navigation)
      end
    else
      self.activeNavigation = nil
      local arrival = directive or "Arrived at destination"
      local parsed = directive and navigationDirectivePayload(
        directive, directiveKey, finalResult, navigation)
      output[#output + 1] = arrival
      navigationEvent = {
        text = arrival,
        targetId = navigation.targetId,
        targetLabel = navigation.targetLabel,
        action = parsed and parsed.action or "arrived",
        direction = parsed and parsed.direction,
      }
    end
  elseif directive and directiveKey ~= navigation.lastDirectiveKey then
    navigation.lastDirectiveKey = directiveKey
    output[#output + 1] = directive
    navigationEvent = navigationDirectivePayload(
      directive, directiveKey, finalResult, navigation)
  end
  if navigationEvent then
    self:emitSemantic(finalResult and finalResult.cost == 0
      and not navigation.puzzle
      and not (navigation.journey and not navigation.currentLegFinal)
      and "navigation.arrived" or "navigation.directive", navigationEvent)
  end
  if #output > 0 then return self:announceManual(output) end
  return true
end

-- Replace an unreachable Victory Road destination with one live boulder push
-- at a time. The original selected destination remains parked on the
-- navigation session and is restored as soon as the required switch changes
-- state. This is guidance only: no movement or puzzle mutation occurs here.
function Accessibility:updatePuzzleDetour(navigation, overworld, allowStart)
  local function restoreOriginal()
    if not navigation.puzzle then return end
    navigation.goals = navigation.puzzle.originalGoals
    navigation.appendInstructions = navigation.puzzle.originalAppendInstructions
    navigation.puzzle = nil
    navigation.pendingPuzzleIntro = nil
    navigation.lastDirectiveKey = nil
  end
  if not puzzleModule(self).enabled(self.game) then
    restoreOriginal()
    return false
  end
  local puzzle = puzzleModule(self).describe(self.game, overworld)
  local action = puzzle.nextAction
  -- A floor can have more than one independent switch. As soon as the switch
  -- we were working on is solved, retry the player's real destination first.
  -- Only choose another switch if that retry is still unreachable.
  if navigation.puzzle and (not action
     or action.targetLabel ~= navigation.puzzle.targetLabel) then
    restoreOriginal()
    return false
  end
  if not action then return false end
  if not navigation.puzzle then
    if not allowStart then return false end
    navigation.puzzle = {
      originalGoals = navigation.goals,
      originalAppendInstructions = navigation.appendInstructions,
      targetLabel = action.targetLabel,
    }
    navigation.pendingPuzzleIntro = action.boulderLabel .. " to "
      .. action.targetLabel .. ". Walk to the pushing position."
  end
  local signature = table.concat({ action.boulderId or "boulder",
    action.targetLabel, action.standX, action.standY, action.direction }, ":")
  if navigation.puzzle.actionSignature ~= signature then
    navigation.puzzle.actionSignature = signature
    navigation.lastDirectiveKey = nil
  end
  navigation.goals = { { x = action.standX, y = action.standY } }
  navigation.appendInstructions = function(parts)
    parts[#parts + 1] = action.instruction
  end
  return true
end

function Accessibility:completePendingRoute(pending, result, routeError)
  if pending.continuous then
    return self:completeContinuousRoute(pending, result, routeError)
  end
  local parts, normalizedError, finalResult = self:finishWorldRoute(
    pending.overworld, result, routeError, pending.goals,
    pending.commandId == "selected", pending.routePolicy)
  if parts and pending.appendInstructions then
    pending.appendInstructions(parts, finalResult)
  end
  return self:announceManual(parts or { normalizedError or "No path" })
end

function Accessibility:advancePendingRoute(pending, result, routeError)
  if not result and routeError == "no path" and pending.routePolicy == 1
     and pending.continuous and pending.navigation
     and pending.navigation.targetMapId and not pending.isRegionalLeg then
    if self:blockedWarpEntrance(pending.navigation) then
      self.activeNavigation = nil
      return self:announceManual({ "Entrance is currently blocked" })
    end
  end
  while not result and routeError == "no path" and pending.routePolicy < 3 do
    -- Prefer traversal the player can perform on this map before searching
    -- every regional transition. This is critical inside Silph Co.: an owned
    -- Card Key is the direct solution, while a premature graph search wanders
    -- through teleport pads and creates a long synchronous pause. Regional
    -- dry journeys still precede the hypothetical all-requirements policy, so
    -- Safari's walk-around route wins over an invented Surf prerequisite.
    if pending.routePolicy == 2 and pending.continuous and pending.navigation
       and pending.navigation.targetMapId and not pending.isRegionalLeg then
      local leg = self:regionalNextLeg(pending.navigation)
      if leg and not leg.final then
        return self:startRegionalLeg(pending.navigation, leg)
      end
    end
    pending.routePolicy = pending.routePolicy + 1
    local options, overworldOrReason = self:worldRouteRequest(
      pending.goals, pending.routePolicy)
    if not options then
      return self:completePendingRoute(pending, nil, overworldOrReason)
    end
    pending.overworld = overworldOrReason
    local task, taskError = Pathfinder.start(options, { yieldEvery = 128 })
    if not task then
      return self:completePendingRoute(pending, nil, taskError or "No path")
    end
    pending.task = task
    local done
    done, result, routeError = task:step()
    if not done then
      self.pendingRoute = pending
      return true
    end
  end
  if not result and routeError == "no path" and pending.continuous
     and pending.navigation and not pending.navigation.puzzle
     and self:updatePuzzleDetour(pending.navigation, pending.overworld, true) then
    return self:refreshActiveNavigation()
  end
  if not result and routeError == "no path" then
    routeError = pending.navigation and pending.navigation.puzzle
      and "Cannot reach the next safe boulder pushing position"
      or "Cannot reach yet"
  end
  return self:completePendingRoute(pending, result, routeError)
end

function Accessibility:startWorldRoute(goals, appendInstructions, commandId,
                                       journeyTarget)
  local continuous = commandId == "selected"
  if continuous and self.activeNavigation then
    return self:stopNavigation(true)
  end
  if self.pendingRoute then
    return self:cancelPendingRoute(true)
  end
  local tooDark = self:darkRefusal()
  if tooDark then return self:announceManual({ tooDark }) end
  local options, overworldOrReason = self:worldRouteRequest(goals, 1)
  if not options then return self:announceManual({ overworldOrReason }) end
  local task, taskError = Pathfinder.start(options, { yieldEvery = 128 })
  if not task then return self:announceManual({ taskError or "No path" }) end
  local pending = {
    task = task,
    overworld = overworldOrReason,
    mapId = currentMapId(overworldOrReason),
    startX = overworldOrReason.player.cellX,
    startY = overworldOrReason.player.cellY,
    appendInstructions = appendInstructions,
    commandId = commandId,
    goals = goals,
    routePolicy = 1,
    continuous = continuous,
  }
  if continuous then
    pending.navigation = {
      mapId = pending.mapId,
      goals = goals,
      appendInstructions = appendInstructions,
      announcedRequirements = {},
      targetMapId = journeyTarget and journeyTarget.mapId,
      targetGoals = journeyTarget and journeyTarget.goals,
      targetAppendInstructions = journeyTarget
        and journeyTarget.appendInstructions,
      targetType = journeyTarget and journeyTarget.type,
      targetId = journeyTarget and journeyTarget.id,
      targetLabel = journeyTarget and journeyTarget.label,
      targetCategory = journeyTarget and journeyTarget.category,
      pendingPreamble = journeyTarget and journeyTarget.preamble,
    }
    self.activeNavigation = pending.navigation
    self:emitSemantic("navigation.started", {
      targetId = pending.navigation.targetId,
      targetLabel = pending.navigation.targetLabel,
      targetCategory = pending.navigation.targetCategory,
      targetType = pending.navigation.targetType,
    })
  end
  local done, result, routeError = task:step()
  if done then return self:advancePendingRoute(pending, result, routeError) end
  self.pendingRoute = pending
  return true
end

-- Leaving the route must be audible.
--
-- `continuousDirectiveKey` deliberately strips the step count, so a leg
-- announced as "three up" stays quiet for its remaining two steps instead of
-- counting down at the player. The cost is that a *recomputed* route whose
-- leading directive points the same way is suppressed by the same key: step
-- sideways off a long corridor and the new path still begins "up", the key
-- still reads `move:up`, and the player hears nothing — no new directions,
-- just silence, while the route quietly re-plans underneath them. The owner
-- reported exactly this: the route recalculates, but only reachability is
-- spoken, never the new path.
--
-- A step in any direction other than the one just announced means the player
-- left the route, so the suppression key is dropped and the recomputed leading
-- directive speaks. Walking the announced direction still coalesces as before,
-- which is the behaviour the key exists to provide.
--
-- Returns true when a deviation was detected, so callers and tests can tell
-- "walked the leg" from "left the route".
-- The direction a directive told the player to go, from its key.
--
-- Off-route correction used to read only `^move:(%a+)$`, and
-- continuousDirectiveKey produces that for exactly two texts -- "N <dir>" and
-- "Exit water <dir>".  Every ledge hop, ice slide, current, Surf, Cut,
-- Whirlpool and Waterfall directive keys as `<verb>:<dir>` or
-- `instruction:<text>` instead, so `announced` came back nil and the guard
-- could not fire at all: a player who walked the wrong way after any of them
-- was never corrected.
--
-- The KEYS are deliberately left alone.  Folding an instruction into a
-- `<verb>:<dir>` key would make two different texts collide -- "slide 3 cells"
-- and "slide 5 cells" would share `ice:up` -- and the second would then be
-- suppressed as a repeat.  The direction is extracted here instead, where it is
-- the only thing wanted.
-- A current is deliberately absent.  "Move <dir> into current" names the
-- direction the player STEPS, but the current then carries them along its own
-- axis, so the net displacement can be perpendicular to the instruction and
-- comparing the two would report a deviation that did not happen.  Ice keeps
-- its direction through the slide, and a ledge hop is two cells the way it was
-- announced, so both are safe to compare.
local DIRECTIVE_TEXT_DIRECTION = {
  "^Jump ledge (%a+)$",
  "^Move (%a+) onto ice",
}

local function directiveDirection(key)
  if type(key) ~= "string" then return nil end
  -- `<verb>:<direction>` covers move, surf, cut, whirlpool and waterfall.  The
  -- trailing anchor keeps `instruction:<sentence>` out, since a sentence has
  -- spaces.
  local direction = key:match("^%a+:(%a+)$")
  if direction and CARDINAL_DELTA[direction] then return direction end
  local text = key:match("^instruction:(.+)$")
  if not text then return nil end
  for _, pattern in ipairs(DIRECTIVE_TEXT_DIRECTION) do
    direction = text:match(pattern)
    if direction and CARDINAL_DELTA[direction] then return direction end
  end
  return nil
end

function Accessibility:noteRouteDeviation(navigation, overworld)
  if type(navigation) ~= "table" or type(overworld) ~= "table" then return false end
  local player = overworld.player
  if type(player) ~= "table" then return false end
  local px, py = player.cellX, player.cellY
  if type(px) ~= "number" or type(py) ~= "number" then return false end

  local deviated = false
  local seen = navigation.lastSeenCell
  if seen and (seen.x ~= px or seen.y ~= py) then
    local dx, dy = px - seen.x, py - seen.y
    local moved = (dx > 0 and "right") or (dx < 0 and "left")
      or (dy > 0 and "down") or (dy < 0 and "up") or nil
    local announced = directiveDirection(navigation.lastDirectiveKey)
    if moved and announced and moved ~= announced then
      navigation.lastDirectiveKey = nil
      deviated = true
    end
  end
  navigation.lastSeenCell = { x = px, y = py }
  return deviated
end

function Accessibility:refreshActiveNavigation()
  local navigation = self.activeNavigation
  if not navigation or self.pendingRoute then return false end
  local overworld = self:worldForCommand()
  if not overworld or currentMapId(overworld) ~= navigation.mapId then
    self.activeNavigation = nil
    return false
  end
  if navigation.puzzle then
    self:updatePuzzleDetour(navigation, overworld, false)
  end

  self:noteRouteDeviation(navigation, overworld)

  local options, reason = self:worldRouteRequest(navigation.goals, 1)
  if not options then
    self.activeNavigation = nil
    return self:announceManual({ reason or "Cannot reach yet" })
  end
  local task, taskError = Pathfinder.start(options, { yieldEvery = 128 })
  if not task then
    self.activeNavigation = nil
    return self:announceManual({ taskError or "Cannot reach yet" })
  end
  local pending = {
    task = task, overworld = overworld, mapId = navigation.mapId,
    startX = overworld.player.cellX, startY = overworld.player.cellY,
    appendInstructions = navigation.appendInstructions,
    commandId = "selected", goals = navigation.goals, routePolicy = 1,
    continuous = true, navigation = navigation,
    isRegionalLeg = navigation.journey == true,
  }
  local done, result, routeError = task:step()
  if done then return self:advancePendingRoute(pending, result, routeError) end
  self.pendingRoute = pending
  return true
end

function Accessibility:startRegionalLeg(navigation, leg)
  local overworld, reason = self:worldForCommand()
  if not overworld then return false, reason end
  local options, routeReason = self:worldRouteRequest(leg.goals, 1)
  if not options then return false, routeReason end
  local task, taskError = Pathfinder.start(options, { yieldEvery = 128 })
  if not task then return false, taskError end

  navigation.journey = true
  navigation.awaitingMap = false
  navigation.mapId = currentMapId(overworld)
  navigation.goals = leg.goals
  navigation.appendInstructions = leg.appendInstructions
  navigation.nextMapId = leg.nextMapId
  navigation.currentLegFinal = leg.final == true
  navigation.lastDirectiveKey = nil
  local pending = {
    task = task, overworld = overworld, mapId = navigation.mapId,
    startX = overworld.player.cellX, startY = overworld.player.cellY,
    appendInstructions = navigation.appendInstructions,
    commandId = "selected", goals = navigation.goals, routePolicy = 1,
    continuous = true, navigation = navigation, isRegionalLeg = true,
  }
  local done, result, routeError = task:step()
  if done then return self:advancePendingRoute(pending, result, routeError) end
  self.pendingRoute = pending
  return true
end

function Accessibility:resumeRegionalNavigation()
  local navigation = self.activeNavigation
  if not (navigation and navigation.journey) then return false end
  navigation.awaitingMap = false
  local tooDark = self:darkRefusal()
  if tooDark then
    self.activeNavigation = nil
    return self:announceManual({ tooDark })
  end
  local leg = self:regionalNextLeg(navigation)
  if not leg then
    self.activeNavigation = nil
    local output = {}
    if navigation.pendingLocation then
      output[#output + 1] = navigation.pendingLocation
    end
    output[#output + 1] = "Cannot calculate a complete route yet"
    return self:announceManual(output)
  end
  return self:startRegionalLeg(navigation, leg)
end

function Accessibility:updateNavigationInterruption(state)
  local navigation = self.activeNavigation
  if not navigation then
    self.navigationInterruptedByBattle = false
    return false
  end
  if type(state) == "table"
     and (state.isBattle == true or state.accessibilityRole == "battle") then
    self.navigationInterruptedByBattle = true
    return false
  end
  if self.navigationInterruptedByBattle
     and type(state) == "table" and state.isOverworld == true then
    self.navigationInterruptedByBattle = false
    -- Battle speech displaced the bearing even though the route is unchanged.
    -- Forget only its speech key, then repeat the live instruction once.
    navigation.lastDirectiveKey = nil
    return self:refreshActiveNavigation()
  end
  return false
end

function Accessibility:updatePendingRoute()
  local pending = self.pendingRoute
  if not pending then return end
  local overworld = self:worldForCommand()
  if not overworld and pending.continuous
     and pending.navigation == self.activeNavigation then
    -- A battle, menu, dialogue, or transition may temporarily cover the
    -- overworld. Keep continuous work paused until play becomes actionable.
    return
  end
  if overworld ~= pending.overworld
     or currentMapId(overworld) ~= pending.mapId
     or overworld.player.cellX ~= pending.startX
     or overworld.player.cellY ~= pending.startY then
    pending.task:cancel()
    self.pendingRoute = nil
    if pending.continuous and pending.navigation == self.activeNavigation then
      return self:refreshActiveNavigation()
    end
    return self:announceManual({ "Route cancelled" })
  end
  local done, result, routeError = pending.task:step()
  if not done then return end
  self.pendingRoute = nil
  return self:advancePendingRoute(pending, result, routeError)
end

-- v0.3.98 adaptation: the goal cells for the selected object, shared by
-- guided navigation (describeRouteToSelected) and auto-walk (AutoWalk.lua).
-- Returns item, goals, interactionInstructions, connectionInstruction,
-- overworld; or nil and a reason.
function Accessibility:selectedRouteGoals()
  if not self.browseSelectionId then return nil, "Select an object from the list" end
  local item, reason = self:selectedBrowseItem(0)
  if not item then return nil, reason end
  local overworld = self:worldForCommand()
  local goals, interactionInstructions, connectionInstruction
  if item.type == "area" then
    -- the cells around the item on its own map; the journey search checks them
    goals = {
      { x = item.x, y = item.y - 1 }, { x = item.x, y = item.y + 1 },
      { x = item.x - 1, y = item.y }, { x = item.x + 1, y = item.y },
    }
    return item, goals, nil, nil, overworld
  end
  if item.type == "connection" then
    goals = self:connectionGoals(overworld, item)
    -- v0.3.98: named by regionalDestinationName (the same Gen 1 call as
    -- before), so a generation's own map registry and names apply
    local destinationName = self:regionalDestinationName(item.destinationMapId)
    connectionInstruction = "Continue " .. tostring(item.direction)
      .. " to " .. destinationName
  elseif item.type == "warp" and type(item.navigationCells) == "table" then
    goals = {}
    for _, cell in ipairs(item.navigationCells) do
      if type(cell.x) == "number" and type(cell.y) == "number" then
        goals[#goals + 1] = { x = cell.x, y = cell.y }
      end
    end
  elseif item.type == "object" or item.type == "signpost" then
    goals, interactionInstructions = self:interactionGoals(overworld, item)
  elseif type(item.x) == "number" and type(item.y) == "number" then
    goals = { { x = item.x, y = item.y } }
  else
    goals = {}
  end
  return item, goals, interactionInstructions, connectionInstruction, overworld
end

-- v0.3.98 addition: guided navigation to an Area target on another map.
-- Starts the old cross-map journey (regionalNextLeg / startRegionalLeg)
-- directly; map.entered then carries it from leg to leg as before.
function Accessibility:startAreaJourney(item, goals)
  if self.activeNavigation then return self:stopNavigation(true) end
  if self.pendingRoute then return self:cancelPendingRoute(true) end
  local overworld, reason = self:worldForCommand()
  if not overworld then return self:announceManual({ reason }) end
  local tooDark = self:darkRefusal()
  if tooDark then return self:announceManual({ tooDark }) end
  local navigation = {
    mapId = currentMapId(overworld), goals = {}, announcedRequirements = {},
    targetMapId = item.mapId, targetGoals = goals, targetType = "area",
    targetId = item.id, targetLabel = item.label, targetCategory = "area",
  }
  local leg, legReason = self:regionalNextLeg(navigation)
  if not leg then
    -- v0.3.98 (Gen 2 audit): the planner's own reason ("regional search
    -- timed out") was spoken as it was; say what it means
    return self:announceManual({ require("src.access.nav.AutoWalk").spokenReason(
      legReason or "no regional path", item.label) })
  end
  self.activeNavigation = navigation
  self:emitSemantic("navigation.started", {
    targetId = item.id, targetLabel = item.label, targetCategory = "area",
    targetType = "area",
  })
  if leg.final then
    self.activeNavigation = nil
    return self:startWorldRoute(goals, nil, "selected", {
      mapId = item.mapId, goals = goals, type = "area", id = item.id,
      label = item.label, category = "area",
    })
  end
  local ok, startReason = self:startRegionalLeg(navigation, leg)
  if ok == false then
    self.activeNavigation = nil
    return self:announceManual({ startReason or "No route yet" })
  end
  return ok
end

function Accessibility:describeRouteToSelected()
  local item, goals, interactionInstructions, connectionInstruction, overworld =
    self:selectedRouteGoals()
  if not item then return self:announceManual({ goals }) end
  if item.type == "area" then return self:startAreaJourney(item, goals) end
  local appendInstructions = function(parts, result)
    if item.requirement then table.insert(parts, 1, item.requirement) end
    if interactionInstructions and result and result.goal then
      local instruction = interactionInstructions[
        routeCellKey(result.goal.x, result.goal.y)]
      if instruction then parts[#parts + 1] = instruction end
    end
    local transitionInstruction = item.transitionInstruction
    if result and result.goal and type(item.navigationCells) == "table" then
      for _, cell in ipairs(item.navigationCells) do
        if cell.x == result.goal.x and cell.y == result.goal.y then
          transitionInstruction = cell.transitionInstruction
            or transitionInstruction
          break
        end
      end
    end
    if transitionInstruction then
      parts[#parts + 1] = transitionInstruction
    end
    if connectionInstruction then parts[#parts + 1] = connectionInstruction end
  end
  return self:startWorldRoute(goals, appendInstructions, "selected", {
    mapId = currentMapId(overworld), goals = goals,
    appendInstructions = appendInstructions, type = item.type,
    id = item.id, label = item.label, category = item.category,
    preamble = item.routePreamble,
  })
end

function Accessibility:describeRouteToSonar()
  local overworld, reason = self:worldForCommand()
  if not overworld then return self:announceManual({ reason }) end
  local x, y = self:ensureSonar(overworld)
  return self:startWorldRoute({ { x = x, y = y } }, nil, "sonar")
end

function Accessibility:ensureSonar(overworld)
  local mapId = currentMapId(overworld)
  if self.sonarMapId ~= mapId
     or type(self.sonarX) ~= "number" or type(self.sonarY) ~= "number" then
    self.sonarMapId = mapId
    self.sonarX, self.sonarY = overworld.player.cellX, overworld.player.cellY
  end
  return self.sonarX, self.sonarY
end

local function sonarEntityAt(overworld, x, y)
  for _, entity in ipairs(overworld.entities or overworld.npcs or {}) do
    if entity ~= overworld.player
       and ((entity.cellX == x and entity.cellY == y)
         or (entity.targetX == x and entity.targetY == y)) then
      return entity
    end
  end
end

function Accessibility:sonarPan(overworld, x)
  local px = overworld.player and overworld.player.cellX
  if type(px) ~= "number" or type(x) ~= "number" or px == x then return 0 end
  return x < px and -0.75 or 0.75
end

function Accessibility:playSonarCell(overworld, x, y, opts)
  opts = opts or {}
  local pan = self:sonarPan(overworld, x)
  local terrain = self:terrainAt(overworld, x, y, {
    passable = opts.passable,
    entities = opts.entities,
  })
  local isBoulder = terrain.kind == "boulder"
    or (type(terrain.features) == "table" and terrain.features.boulder == true)
  if isBoulder and not opts.boulderAlready then
    self:cue("boulder", { pan = pan })
  end

  -- A native boulder describes the entity, not the floor beneath it.  Sonar
  -- already layers the boulder cue, so classify once more without entities to
  -- preserve the underlying grass/water/special cue and avoid saying boulder
  -- twice.  Explicit entity semantics remain authoritative and are retained.
  if terrain.kind == "boulder" then
    terrain = self:terrainAt(overworld, x, y, {
      passable = opts.passable,
      entities = {},
    })
  end
  return self:cueTerrain(terrain, { pan = pan })
end

-- The sonar's pass/wall question, isolated so a generation can answer it with
-- the same movement rules its ROUTER uses.
--
-- This is Gen I's answer and stays Gen I's: Collision.canMove reads the tile
-- vocabulary Gen I movement reads.  Generation II overrides it, because its
-- directional COLL_* side walls are a concept Collision.canMove has no notion
-- of -- and a sonar that disagrees with routing is worse than one that says
-- nothing, since the player sweeps ahead precisely to decide where to walk.
-- Whether this entity is a boulder the player could push.
--
-- Isolated for the same reason the sonar's pass/wall question is: the two
-- generations answer it from different fields.  Gen I reads the sprite name;
-- Gen II reads SPRITEMOVEDATA_STRENGTH_BOULDER, because a Gold boulder is not
-- reliably SPRITE_BOULDER -- Blackthorn Gym 2F carries six of them and only
-- three are in its stone table, while all six have the movedata
-- (src/world/gen2/CmdQueue.lua:37-40).  Asking the Gen I question about a Gold
-- boulder therefore misses it silently, and the sonar stops cueing the one
-- object on the map the player most needs to find.
function Accessibility:isPushableEntity(entity)
  if type(entity) ~= "table" or type(entity.def) ~= "table" then return false end
  return Map.isPushable(entity.def) == true
end

function Accessibility:sonarCanMove(overworld, probe, direction, entities)
  local ok, allowed = pcall(Collision.canMove,
    overworld.map, entities, probe, direction)
  if not ok then
    Logger.warn("accessibility sonar collision probe failed: %s", tostring(allowed))
    return false
  end
  return allowed == true
end

function Accessibility:moveSonar(direction, throughWalls)
  local overworld, reason = self:worldForCommand()
  if not overworld then return self:announceManual({ reason }) end
  local delta = CARDINAL_DELTA[direction]
  if not delta then return false, "unknown sonar direction" end
  local x, y = self:ensureSonar(overworld)
  local tx, ty = x + delta[1], y + delta[2]
  if self:isDark(overworld) and not self:darkCellVisible(overworld, tx, ty) then
    return self:announceManual({ self.TOO_DARK })
  end
  local pan = self:sonarPan(overworld, tx)
  local boundsOK, inBounds = pcall(overworld.map.inBounds, overworld.map, tx, ty)
  if not boundsOK or not inBounds then
    self:cue("wall", { pan = pan })
    return true
  end

  local entity = sonarEntityAt(overworld, tx, ty)
  if self:isPushableEntity(entity) then
    self:cue("boulder", { pan = pan })
  end
  local collisionEntities = {}
  for _, candidate in ipairs(overworld.entities or overworld.npcs or {}) do
    if candidate ~= overworld.player then
      collisionEntities[#collisionEntities + 1] = candidate
    end
  end
  local probe = { cellX = x, cellY = y,
                  surfing = overworld.player.surfing == true }
  local allowed = self:sonarCanMove(overworld, probe, direction, collisionEntities)
  if not allowed then
    self:cue("wall", { pan = pan })
    if not throughWalls then return true end
  else
    self:cue("pass", { pan = pan })
  end
  self.sonarX, self.sonarY = tx, ty
  return self:playSonarCell(overworld, tx, ty, {
    passable = allowed,
    boulderAlready = self:isPushableEntity(entity),
  })
end

function Accessibility:resetSonar()
  local overworld, reason = self:worldForCommand()
  if not overworld then return self:announceManual({ reason }) end
  self.sonarMapId = currentMapId(overworld)
  self.sonarX, self.sonarY = overworld.player.cellX, overworld.player.cellY
  return self:playSonarCell(overworld, self.sonarX, self.sonarY)
end

function Accessibility:battleForCommand()
  local stack = self.game and self.game.stack
  for i = #(stack and stack.states or {}), 1, -1 do
    local state = stack.states[i]
    -- Gen I and Gen II publish compatible battle markers for commands.
    if state and (state.isBattle == true
                  or state.accessibilityRole == "battle") then
      return state
    end
  end
  return nil
end

local STATUS_WORDS = {
  SLP = "asleep", FRZ = "frozen", PSN = "poisoned",
  BRN = "burned", PAR = "paralyzed",
}

function Accessibility:readBattleHealth(side)
  local battle = self:battleForCommand()
  if not battle then return self:announceManual({ "Not in battle" }) end
  -- Gen 2's battle screen answers from the values its HUD shows
  -- (src/access/screens/gen2/Battle.lua); nil for any other battle screen.
  local gen2Text = require("src.access.screens.gen2.Battle").health(battle, side)
  if gen2Text then return self:announceManual({ gen2Text }) end
  local battler = side == "enemy" and battle.enemy or battle.player
  local mon = type(battler) == "table" and battler.mon or nil
  local hp = mon and tonumber(mon.hp)
  local maxHP = mon and type(mon.stats) == "table" and tonumber(mon.stats.hp)
  if not (hp and maxHP and maxHP > 0) then
    return self:announceManual({ "No bar found" })
  end
  if side == "enemy" then
    return self:announceManual({
      ("Enemy health: %.2f percent"):format(hp * 100 / maxHP),
    })
  end
  local name = battler.name or mon.nickname or mon.species or "Pokemon"
  local text = ("Player %s, %d of %d HP"):format(name, hp, maxHP)
  if mon.status then text = text .. ", " .. (STATUS_WORDS[mon.status] or mon.status) end
  return self:announceManual({ text })
end

function Accessibility:readScreenText()
  -- v0.3.98 adaptation: screens are spoken by src/access/screens, so "read
  -- screen text" repeats the most recent screen speech from src/access/Speech.
  local text = require("src.access.Speech").lastScreenText()
  return self:announceManual({
    normalize(text, self:speakerNames()) or "No accessible screen text" })
end

function Accessibility:handleCommandStatus(actionId)
  if actionId == "command_layer_enabled" then
    return self:announceManual({
      "Accessibility command mode on. Arrow keys remain available for movement. Press F8 for command help.",
    })
  elseif actionId == "command_layer_disabled" then
    return self:announceManual({ "Accessibility command mode off" })
  end
  return false, "unknown command status"
end

function Accessibility:handleCommand(actionId)
  if actionId == "read_command_help" then
    local helpLines = {
      "Accessibility help. F7 toggles command mode. F8 reads this help.",
      "While command mode is on, J and L browse map items. Shift J and Shift L change the item filter. K gives spoken directions to the selected item as you move: press K again to stop. Shift K auto-walks to it, and any key stops the walk. These keys only work on the map. H reads enemy health and Shift H reads player health.",
      "On a controller, hold the left trigger: D-pad up and down change the item filter, left and right browse map items. Click the right stick for spoken directions and the left stick to auto-walk.",
    }
    -- drop the camera line when it is off (announceManual stops at a nil)
    local parts = {}
    for i = 1, table.maxn(helpLines) do
      if helpLines[i] then parts[#parts + 1] = helpLines[i] end
    end
    return self:announceManual(parts)
  end
  if actionId == "read_player_position" then
    local snapshot, reason = self:captureWorld()
    return self:announceManual({ snapshot
      and ("x %d, y %d"):format(snapshot.player.x, snapshot.player.y) or reason })
  elseif actionId == "read_camera_position" then
    local overworld, reason = self:worldForCommand()
    if not overworld then return self:announceManual({ reason }) end
    local x, y = self:ensureSonar(overworld)
    return self:announceManual({ ("x %d, y %d"):format(x, y) })
  elseif actionId == "previous_map_item" then
    return self:announceBrowse(-1)
  elseif actionId == "current_map_item" then
    return self:announceBrowse(0)
  elseif actionId == "next_map_item" then
    return self:announceBrowse(1)
  elseif actionId == "previous_item_filter" then
    return self:cycleBrowseFilter(-1)
  elseif actionId == "next_item_filter" then
    return self:cycleBrowseFilter(1)
  elseif actionId == "read_screen_text" then
    return self:readScreenText()
  elseif actionId == "read_map_name" then
    local snapshot, reason = self:captureWorld()
    return self:announceManual({ snapshot and snapshot.locationName or reason })
  elseif actionId == "read_game_time" then
    return self:readGameTime()
  elseif actionId == "read_collision_tiles" then
    return self:readCollisionTiles()
  elseif actionId == "read_terrain" then
    return self:readSonarTerrain()
  elseif actionId == "move_camera_left" then
    return self:moveSonar("left", false)
  elseif actionId == "move_camera_right" then
    return self:moveSonar("right", false)
  elseif actionId == "move_camera_up" then
    return self:moveSonar("up", false)
  elseif actionId == "move_camera_down" then
    return self:moveSonar("down", false)
  elseif actionId == "move_camera_left_through_walls" then
    return self:moveSonar("left", true)
  elseif actionId == "move_camera_right_through_walls" then
    return self:moveSonar("right", true)
  elseif actionId == "move_camera_up_through_walls" then
    return self:moveSonar("up", true)
  elseif actionId == "move_camera_down_through_walls" then
    return self:moveSonar("down", true)
  elseif actionId == "reset_camera_to_player" then
    return self:resetSonar()
  elseif actionId == "toggle_camera_follow" then
    self:setSonarFollow(not self.sonarFollowsPlayer, { persist = true })
    return self:announceManual({ self.sonarFollowsPlayer
      and "Camera follows the player" or "Camera does not follow the player" })
  elseif actionId == "read_enemy_health" then
    return self:readBattleHealth("enemy")
  elseif actionId == "read_player_health" then
    return self:readBattleHealth("player")
  elseif actionId == "describe_route_to_selected_item" then
    return self:describeRouteToSelected()
  elseif actionId == "describe_route_to_camera" then
    return self:describeRouteToSonar()
  end
  return false, "unknown accessibility command: " .. tostring(actionId)
end

function Accessibility:readGameTime()
  return self:announceManual({ "This game does not have an in-game clock" })
end

function Accessibility:describe(state, entering)
  if not state or type(state.accessibilitySnapshot) ~= "function" then
    return nil
  end
  local ok, descriptor = pcall(state.accessibilitySnapshot, state, {
    entering = entering,
    game = self.game,
  })
  if not ok then
    if not self.snapshotErrors[state] then
      self.snapshotErrors[state] = true
      Logger.error("accessibility snapshot failed for %s: %s",
                   tostring(state.screenId or state), tostring(descriptor))
    end
    return nil
  end
  return descriptor
end

function Accessibility:update()
  if not self.enabled then return end
  local stack = self.game and self.game.stack
  local state = stack and stack:top() or nil
  self:updateNavigationInterruption(state)
  self:updatePendingRoute()
  self:processWorldEvents(state)
  self:processBattleEvents(state)
  local entering = state ~= self.observedState
  if entering then
    self.observedState = state
    self.observedKey = nil
    self.observedContext = nil
    self.pendingKey = nil
    self.pendingFrames = 0
    self.pendingEntering = false
    self.stateUnannounced = state ~= nil
  end

  local descriptor = self:describe(state, entering)
  if descriptor == nil then return end
  local contextKey = type(descriptor) == "table" and descriptor.contextKey or nil
  if contextKey ~= self.observedContext then
    -- Internal semantic-region transition (battle messages -> command menu,
    -- naming grid -> preset list, and similar).  This lets enterText run once
    -- without mutating the state or repeating on every selection.
    if contextKey ~= nil or self.observedContext ~= nil then
      self.observedKey = nil
      self.pendingKey = nil
      self.pendingFrames = 0
      self.stateUnannounced = true
    end
    self.observedContext = contextKey
  end
  local key = type(descriptor) == "table" and descriptor.key or descriptor
  if key == nil and type(descriptor) == "table" then key = descriptor.text end
  key = tostring(key or "")
  if key == self.observedKey then return end

  if key ~= self.pendingKey then
    self.pendingKey = key
    self.pendingFrames = 0
    self.pendingEntering = self.stateUnannounced
  else
    self.pendingFrames = self.pendingFrames + 1
  end
  local delay = type(descriptor) == "table" and descriptor.delayFrames or nil
  if type(descriptor) == "table" and descriptor.immediate then delay = 0 end
  delay = math.max(0, tonumber(delay) or self.defaultDelayFrames)
  if self.pendingFrames < delay then return end
  self.observedKey = key
  self.stateUnannounced = false

  local text = descriptorText(descriptor, self.pendingEntering)
  if type(descriptor) == "table" and descriptor.cue then
    self:cue(descriptor.cue, {
      pan = tonumber(descriptor.cuePan) or 0,
      volume = tonumber(descriptor.cueVolume) or 0.3,
    })
  end
  local interrupt = type(descriptor) == "table"
                    and descriptor.interrupt == true or false
  self:announce(text, {
    interrupt = interrupt,
    semantic = {
      kind = "screen.focus",
      screenId = state and state.screenId,
      stateRole = state and state.accessibilityRole,
      key = key,
      contextKey = contextKey,
      entering = self.pendingEntering == true,
    },
  })
end

-- v0.3.98 adaptation: the per-frame work this layer still owns.  Screen
-- speech is src/access/screens; this keeps routes, step and map events and
-- terrain cues moving.
function Accessibility:updateNavigation()
  if not self.enabled then return end
  local stack = self.game and self.game.stack
  local state = stack and stack:top() or nil
  self:updateNavigationInterruption(state)
  self:updatePendingRoute()
  self:processWorldEvents(state)
end

function Accessibility:shutdown()
  self:unsubscribeWorldEvents()
  self:stopNavigation(false)
  self:cancelPendingRoute(false)
  self.pendingMapEvent, self.pendingStepEvent, self.pendingBumpEvent = nil, nil, nil
  self.pendingBattleDamage, self.pendingBallShakes = nil, nil
  self.lastBumpKey = nil
  if self.earcons then self.earcons:stop() end
  if not self.speech then return true end
  if self.ownsSpeech then
    local ok = self.speech:stop()
    local closed = self.speech:shutdown()
    self.speech = nil
    self.status.available = false
    return ok and closed
  end
  if type(self.speech.releaseMode) == "function" then
    return self.speech:releaseMode()
  end
  return self.speech:stop()
end

Accessibility.normalize = normalize

return Accessibility
