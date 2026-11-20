-- Gen 2 game text for unit tests that build a fake game.  Since upstream
-- v0.4.x the Gen 2 screens read their wording only from the imported
-- cartridge's text: src/core/RomText.lua errors on a label missing from
-- `game.data.text`.  The fake games in our tests carry no text, so this
-- merges upstream's own test fixtures (tests/fixture_data/
-- gen2_rom_text_s7_*.lua, shipped by upstream) and, through `install`, lets
-- RomText fall back to them for a label the fake data lacks.  It also binds
-- upstream's engine flag table (src/core/gen2/EngineFlags.lua, normally bound
-- from the cartridge's constants) and the phone contacts to upstream's
-- fixtures.  Call `install()`
-- before requiring any game module.
local M = {}

local PARTS = { "a", "b", "c", "d", "e", "f1", "f2", "g" }

-- All fixture text in one table; `version` "crystal" applies Crystal's
-- differences, none adds Crystal-only lines; `extra` entries win.
function M.text(version, extra)
  local text = {}
  for _, part in ipairs(PARTS) do
    local fixture = require("tests.fixture_data.gen2_rom_text_s7_" .. part)
    for label, body in pairs(fixture.RAW or fixture) do
      if type(body) == "string" then text[label] = body end
    end
    local crystal = fixture.crystal or fixture.CRYSTAL or {}
    if version == "crystal" then
      for _, label in ipairs(fixture.crystalAbsent or {}) do text[label] = nil end
      for label, body in pairs(crystal) do text[label] = body end
    elseif version == nil then
      -- No version: Gold/Silver text, plus Crystal-only lines (the gender
      -- question) so one fake game covers screens from both.
      for label, body in pairs(crystal) do
        if text[label] == nil then text[label] = body end
      end
    end
  end
  for label, body in pairs(extra or {}) do text[label] = body end
  return text
end

function M.install(version)
  local fallback = M.text(version)
  local original = require("src.core.RomText")
  package.loaded["src.core.RomText"] = function(data, label, literal, ...)
    local own = data and data.text and data.text[label]
    if own == nil and fallback[label] ~= nil then
      data = { text = { [label] = fallback[label] } }
    end
    return original(data, label, literal, ...)
  end
  local flags = require("tests.fixture_data.gen2_engine_flags")
  require("src.core.gen2.EngineFlags").bind(flags.order(version or "crystal"))
  -- Phone contacts come from the cartridge's phone tables (upstream fixture).
  require("tests.fixtures.gen2_phone_events").install()
end

return M
