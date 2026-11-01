-- Shared reading helpers for the Gen 3 presenters (FireRed, LeafGreen;
-- decision 29).  Gen 3 screens arrive as proxies from gen3/Top.lua
-- ({ gen3 = <kind>, layer, mod, game, ... }); presenters match on the kind
-- and check the layer's module is the builtin one, so a mod that replaces a
-- screen stays quiet instead of being misread (mods can use
-- accessibilityText instead).

local Gen2Common = require("src.access.screens.gen2.Common")

local Common = {}

local function presenters()
  return package.loaded["src.access.screens.Presenters"] or require("src.access.screens.Presenters")
end

Common.position = Gen2Common.position
Common.tr = Gen2Common.tr
Common.sentences = Gen2Common.sentences

-- matches(proxy) for a kind; `modulePath`, when given, must be the module
-- the layer holds.
function Common.matcher(kind, modulePath)
  return function(state)
    if type(state) ~= "table" or state.gen3 ~= kind then return false end
    if modulePath and state.layer then
      local mod = package.loaded[modulePath]
      return mod ~= nil and state.layer.mod == mod
    end
    return true
  end
end

-- Gen 3 text keeps font tags and control bytes for the renderer
-- (src/ui/game3/frlg_font.lua, src/core/game3/scripting/text_ir.lua).
-- Extension control byte 0xFC takes a fixed number of argument bytes.
local EXT_ARGS = {
  [0x01] = 1, [0x02] = 1, [0x03] = 1, [0x04] = 3, [0x05] = 1, [0x06] = 1, [0x08] = 1,
  [0x0B] = 2, [0x0C] = 1, [0x0D] = 1, [0x0E] = 1, [0x10] = 2, [0x11] = 1, [0x12] = 1,
  [0x13] = 1, [0x14] = 1,
}

local function stripControls(text)
  if not text:find("\252", 1, true) then return text end
  local out, i, n = {}, 1, #text
  while i <= n do
    local byte = text:byte(i)
    if byte == 0xFC then
      i = i + 2 + (EXT_ARGS[text:byte(i + 1) or 0] or 0)
    else
      out[#out + 1] = string.char(byte)
      i = i + 1
    end
  end
  return table.concat(out)
end

-- Glyph and button tags said in words; colour, shadow and font tags are
-- presentation only and dropped, as is any other tag left over.
local TAG_WORDS = {
  PKMN = "POKéMON", PK = "PK", MN = "MN", LV = "level ", LV_2 = "level ", PP = "PP ",
  ID = "ID ", NO = "number ", PLUS = "plus", TIMES = "times",
  -- button, pad and arrow glyphs stand right before a word on screen
  -- ("{A_BUTTON}NEXT"), so their words end in a space; doubled spaces are
  -- collapsed later
  A_BUTTON = "A button ", B_BUTTON = "B button ", START_BUTTON = "START ",
  SELECT_BUTTON = "SELECT ", L_BUTTON = "L button ", R_BUTTON = "R button ",
  DPAD_UPDOWN = "up and down ", DPAD_LEFTRIGHT = "left and right ", DPAD_NONE = "the control pad ",
  UP_ARROW = "up ", DOWN_ARROW = "down ", LEFT_ARROW = "left ", RIGHT_ARROW = "right ",
}

function Common.speakable(text)
  text = stripControls(tostring(text or ""))
  text = text:gsub("{PK}{MN}", "{PKMN}")
  text = text:gsub("{([%u%d_]+)[^}]*}", function(tag) return TAG_WORDS[tag] or "" end)
  text = text:gsub("\f", "\n")
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then lines[#lines + 1] = line end
  end
  return Gen2Common.speakable(presenters().joinLines(lines))
end

-- A page string's lines, cleaned, as a list (split words handled by the caller).
function Common.lines(text)
  text = stripControls(tostring(text or ""))
  text = text:gsub("{PK}{MN}", "{PKMN}")
  text = text:gsub("{([%u%d_]+)[^}]*}", function(tag) return TAG_WORDS[tag] or "" end)
  local lines = {}
  for line in (text:gsub("\f", "\n") .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then lines[#lines + 1] = line end
  end
  return lines
end

return Common
