-- Reused from the old Pocket Accessibility project (src/world/ChaosCut.lua at
-- commit 71cdd419e) under decision 20; read-only use by navigation.

-- Deliberately silly, opt-in accessibility easter egg.  This recreates the
-- memorable effect of an old terrain-classification bug without restoring
-- the unsafe raw-block mutation that caused crashes in indoor maps.

local Map = require("src.world.Map")

local ChaosCut = {}

function ChaosCut.enabled(game)
  return game and game.save and game.save.options
     and game.save.options.chaosCut == true
end

-- Keep inventory balls, static Pokemon encounters, and Strength boulders on
-- their real gameplay paths.  Ordinary actors -- including trainers and gym
-- leaders -- are fair game while the explicit chaos option is enabled.
function ChaosCut.eligible(entity)
  if type(entity) ~= "table" then return false end
  local def = type(entity.def) == "table" and entity.def or {}
  return def.item == nil and def.pokemon == nil and not Map.isPushable(def)
end

function ChaosCut.label(label)
  return "Cuttable Bush (" .. tostring(label or "Person") .. ")"
end

return ChaosCut
