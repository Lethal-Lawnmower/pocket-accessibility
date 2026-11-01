-- Reused from the old Pocket Accessibility project (src/accessibility/TraversalSemantics.lua at
-- commit 71cdd419e) under decision 20; adapted for v0.3.98.

-- Read-only traversal annotations for native map mechanics which are not
-- represented by ordinary map warps.  These records never mutate gameplay;
-- the canonical behavior remains owned by data/scripts/story*.lua.
--
-- A mod may replace a built-in record by authoring either
-- `map.accessibilityTraversal` or `map.accessibility.traversal`.

local TraversalSemantics = {}

local MANSION_BLOCKS = {
  POKEMON_MANSION_1F = {
    { 12,  6, 0x0e, 0x2d },
    {  8,  3, 0x2d, 0x0e },
    { 10,  8, 0x2d, 0x0e },
    { 13, 13, 0x2d, 0x0e },
  },
  POKEMON_MANSION_2F = {
    { 4, 2, 0x0e, 0x5f },
    { 9, 4, 0x54, 0x0e },
    { 3, 11, 0x5f, 0x0e },
  },
  POKEMON_MANSION_3F = {
    { 7, 2, 0x0e, 0x5f },
    { 7, 5, 0x5f, 0x0e },
  },
  POKEMON_MANSION_B1F = {
    { 13, 8, 0x0e, 0x2d },
    { 6, 11, 0x0e, 0x5f },
    { 4, 3, 0x5f, 0x0e },
    { 8, 8, 0x54, 0x0e },
  },
}

local MANSION_SWITCHES = {
  POKEMON_MANSION_1F = { { 2, 5 } },
  POKEMON_MANSION_2F = { { 2, 11 } },
  POKEMON_MANSION_3F = { { 10, 5 } },
  POKEMON_MANSION_B1F = { { 20, 3 }, { 18, 25 } },
}

local function mansionTraversal(mapId)
  local switches = {}
  for index, cell in ipairs(MANSION_SWITCHES[mapId] or {}) do
    switches[index] = {
      id = "mansion_switch:" .. mapId .. ":" .. tostring(index),
      x = cell[1], y = cell[2], kind = "switch", label = "Secret switch",
      requiredFacing = "up",
    }
  end
  local gates = {}
  for index, row in ipairs(MANSION_BLOCKS[mapId] or {}) do
    gates[index] = {
      id = "mansion_gate:" .. mapId .. ":" .. tostring(index),
      bx = row[1], by = row[2], offBlock = row[3], onBlock = row[4],
      openBlock = 0x0e,
    }
  end
  return {
    switches = switches,
    alternatingGates = gates,
    stateFlag = "EVENT_MANSION_SWITCH_ON",
  }
end

local builtIn = {}
for mapId in pairs(MANSION_BLOCKS) do
  builtIn[mapId] = mansionTraversal(mapId)
end

builtIn.POKEMON_MANSION_3F.specialWarps = {
  { id = "mansion_hole:POKEMON_MANSION_3F:1", x = 16, y = 14,
    kind = "hole", destinationMap = "POKEMON_MANSION_1F",
    destinationX = 16, destinationY = 14 },
  { id = "mansion_hole:POKEMON_MANSION_3F:2", x = 17, y = 14,
    kind = "hole", destinationMap = "POKEMON_MANSION_1F",
    destinationX = 16, destinationY = 14 },
  { id = "mansion_hole:POKEMON_MANSION_3F:3", x = 19, y = 14,
    kind = "hole", destinationMap = "POKEMON_MANSION_2F",
    destinationX = 18, destinationY = 14 },
}

local GYM_MACHINES = {
  { x = 15, y = 7,  gate = { 9, 3, 0x54 } },
  { x = 10, y = 1,  gate = { 6, 3, 0x54 } },
  { x = 9,  y = 7,  gate = { 6, 6, 0x54 } },
  { x = 9,  y = 13, gate = { 3, 8, 0x5f } },
  { x = 1,  y = 13, gate = { 2, 6, 0x54 } },
  { x = 1,  y = 7,  gate = { 2, 3, 0x54 } },
}

local gymSwitches = {}
for index, machine in ipairs(GYM_MACHINES) do
  gymSwitches[index] = {
    id = "cinnabar_quiz:" .. tostring(index),
    x = machine.x, y = machine.y, kind = "switch",
    label = "Quiz machine " .. tostring(index), requiredFacing = "up",
    stateFlag = "EVENT_CINNABAR_GYM_GATE" .. tostring(index - 1)
      .. "_UNLOCKED",
    gate = {
      bx = machine.gate[1], by = machine.gate[2],
      closedBlock = machine.gate[3], openBlock = 0x0e,
    },
  }
end
builtIn.CINNABAR_GYM = { switches = gymSwitches }

builtIn.VICTORY_ROAD_3F = {
  specialWarps = {
    { id = "victory_road_hole:VICTORY_ROAD_3F:1", x = 23, y = 15,
      kind = "hole", destinationMap = "VICTORY_ROAD_2F",
      destinationX = 22, destinationY = 16 },
  },
}

function TraversalSemantics.forMap(mapId, map)
  local def = type(map) == "table" and (map.def or map) or nil
  if type(def) == "table" then
    if type(def.accessibilityTraversal) == "table" then
      return def.accessibilityTraversal
    end
    local accessibility = def.accessibility
    if type(accessibility) == "table"
       and type(accessibility.traversal) == "table" then
      return accessibility.traversal
    end
  end
  return builtIn[mapId]
end

return TraversalSemantics
