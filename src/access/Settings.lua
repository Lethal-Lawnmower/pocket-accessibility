-- Accessibility page in the game's own OPTIONS menu (decision 26).
--
-- OptionsMenu.new is wrapped at install time, the same runtime-wrapping
-- approach the layer uses for love callbacks, so no upstream file changes.
-- The page is one more group row ("ACCESSIBILITY", first on the top level)
-- that opens a submenu of ordinary option rows; OptionsMenu drives them and
-- saves them like its own, and the options presenter speaks them.
--
-- Values live in save.options, which keeps unknown keys
-- (SaveData.mergeOptions), so they persist in the normal options file:
--   accessAutoWalkSpeed  nil = the game's own speed, else a GameSpeed level
--   accessDialogue       nil = page by page (chunk as shown), "whole" = all
--                        of a dialogue box at once

local GameSpeed = require("src.core.GameSpeed")

local Settings = {}

local function options(game)
  return game and game.save and game.save.options or {}
end

-- The auto-walk multiplier the player chose, or nil for "use the game's own
-- speed".  Clamped to the levels the current cart allows.
function Settings.autoWalkSpeed(game)
  local value = tonumber(options(game).accessAutoWalkSpeed)
  if not value then return nil end
  return GameSpeed.clamp(value)
end

function Settings.dialogueWhole(game)
  return options(game).accessDialogue == "whole"
end

-- GAME SPEED, then the game's own speed ladder (NORMAL, 2X ... 200X).
local function stepAutoWalkSpeed(game, dir)
  local choices = { false }
  for _, level in ipairs(GameSpeed.allowed()) do choices[#choices + 1] = level end
  local current = Settings.autoWalkSpeed(game) or false
  local index = 1
  for i, choice in ipairs(choices) do
    if choice == current then index = i break end
  end
  index = (index - 1 + (dir or 1)) % #choices + 1
  options(game).accessAutoWalkSpeed = choices[index] or nil
  return true
end

function Settings.rows()
  return {
    { id = "accessAutoWalkSpeed", label = "AUTO-WALK SPEED",
      value = function(g)
        local speed = Settings.autoWalkSpeed(g)
        return speed and GameSpeed.levelLabel(speed) or "GAME SPEED"
      end,
      step = stepAutoWalkSpeed },
    { id = "accessDialogue", label = "DIALOGUE SPEECH",
      value = function(g)
        return Settings.dialogueWhole(g) and "ALL AT ONCE" or "PAGE BY PAGE"
      end,
      step = function(g)
        local o = options(g)
        o.accessDialogue = o.accessDialogue ~= "whole" and "whole" or nil
        return true
      end },
  }
end

local installed = false

function Settings.install()
  if installed then return end
  local ok, OptionsMenu = pcall(require, "src.ui.OptionsMenu")
  if not ok or type(OptionsMenu) ~= "table" or type(OptionsMenu.new) ~= "function" then return end
  installed = true
  local originalNew = OptionsMenu.new
  OptionsMenu.new = function(game, opts)
    local menu = originalNew(game, opts)
    -- only the top level; group pages (opts.rows) are left as they are
    if (opts and opts.rows) or type(menu) ~= "table" or type(menu.view) ~= "table" then
      return menu
    end
    local rows = Settings.rows()
    table.insert(menu.view, 1, {
      id = "group.accessibility", label = "ACCESSIBILITY", group = true,
      value = function() return #rows .. " OPTIONS" end,
      activate = function(g)
        g.stack:push(OptionsMenu.new(g, { rows = rows }))
      end,
    })
    return menu
  end
end

return Settings
