-- Accessibility page in the game's own OPTIONS menu (decision 26).
--
-- OptionsMenu.new is wrapped at install time, the same runtime-wrapping
-- approach the layer uses for love callbacks, so no upstream file changes.
-- The page is one more group row ("ACCESSIBILITY", first on the top level)
-- that opens a submenu of ordinary option rows; OptionsMenu drives them and
-- saves them like its own, and the options presenter speaks them.
--
-- Gen 2 has its own OPTION screen (src/ui/gen2/OptionsMenu.lua) with the
-- same row vocabulary (`value`, `step`, group rows with `activate`), so the
-- same page is added there too (decision 27).
--
-- Values live in the options table the game persists, which keeps unknown
-- keys: Gen 1's save.options (SaveData.mergeOptions) and Gen 2's
-- game.options (stored under options.lua's `gold` block by
-- src/core/gen2/Save.lua), so each generation keeps its own choice:
--   accessAutoWalkSpeed  nil = the game's own speed, else a GameSpeed level
--   accessDialogue       nil = page by page (chunk as shown), "whole" = all
--                        of a dialogue box at once

local GameSpeed = require("src.core.GameSpeed")

local Settings = {}

local GameVersion = require("src.core.GameVersion")

local function options(game)
  if not game then return {} end
  -- Gen 2's OPTION screen edits game.options in place (Game2:showOptions)
  if GameVersion.generation() == 2 and type(game.options) == "table" then return game.options end
  return game.save and game.save.options or {}
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

local installed = {}

-- The ACCESSIBILITY group row, first on a top-level OPTION screen.
local function groupRow(openPage)
  local rows = Settings.rows()
  return {
    id = "group.accessibility", label = "ACCESSIBILITY", group = true,
    value = function() return #rows .. " OPTIONS" end,
    activate = function(g) openPage(g, rows) end,
  }
end

-- Wraps one OPTION screen class's constructor.  `isPage` says whether a
-- constructed menu is a group page (left alone); `openPage` pushes our page.
local function wrap(path, isPage, openPage)
  if installed[path] then return end
  local ok, OptionsMenu = pcall(require, path)
  if not ok or type(OptionsMenu) ~= "table" or type(OptionsMenu.new) ~= "function" then return end
  installed[path] = true
  local originalNew = OptionsMenu.new
  OptionsMenu.new = function(game, opts)
    local menu = originalNew(game, opts)
    if type(menu) ~= "table" or type(menu.view) ~= "table" or isPage(menu, opts) then
      return menu
    end
    table.insert(menu.view, 1, groupRow(function(g, rows) openPage(OptionsMenu, originalNew, menu, g, rows) end))
    return menu
  end
end

function Settings.install()
  -- Gen 1: a group page is OptionsMenu.new(game, { rows = ... })
  wrap("src.ui.OptionsMenu",
    function(_, opts) return opts and opts.rows ~= nil end,
    function(OptionsMenu, _, _, g, rows) g.stack:push(OptionsMenu.new(g, { rows = rows })) end)
  -- Gen 2: group pages are built in place by the screen's local pushGroup
  -- (sub = true, the rows plus a BACK row, the parent's options table),
  -- never through new(), so our page is built the same way.
  wrap("src.ui.gen2.OptionsMenu",
    function(menu) return menu.sub == true end,
    function(OptionsMenu, _, parent, g, rows)
      local page = setmetatable({}, OptionsMenu)
      page.game, page.rows, page.options = g, rows, parent.options
      page.index, page.scroll, page.sub = 1, 0, true
      page.view = {}
      for i, row in ipairs(rows) do page.view[i] = row end
      page.view[#page.view + 1] = { label = "BACK", cancel = true, id = "cancel" }
      g.stack:push(page)
    end)
end

return Settings
