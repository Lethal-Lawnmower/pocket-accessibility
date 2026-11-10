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
-- Gen 3 has a third OPTION screen (src/ui/game3/option_menu.lua) that keeps
-- its pages inside one module; the page is added to it by wrapping
-- OptionMenu.show (Settings.installGen3).
--
-- Values live in the options table the game persists, which keeps unknown
-- keys: Gen 1's save.options (SaveData.mergeOptions), Gen 2's game.options
-- (stored under options.lua's `gold` block by src/core/gen2/Save.lua) and
-- Gen 3's cartridge options block (`firered`, inside game.options), so each
-- generation keeps its own choice:
--   accessAutoWalkSpeed  nil = the game's own speed, else a GameSpeed level
--   accessDialogue       nil = page by page (chunk as shown), "whole" = all
--                        of a dialogue box at once
--   accessTouchGestures  nil = the platform default (on for Android and iOS), else
--                        true / false (decision 66, src/access/touch/)
--   accessTouchWalk      nil = manual, "hybrid" or "auto" (touch walking mode)
--   accessHaptics        nil = on, false = off (decision 68, src/access/Haptics.lua)

local GameSpeed = require("src.core.GameSpeed")

local Settings = {}

local GameVersion = require("src.core.GameVersion")

-- Gen 3's game.options is the root of the shared options.lua, the same
-- table Gen 1 reads as save.options, so its keys would be shared with Red
-- and Blue.  FireRed keeps its cartridge options in a block of that table
-- named by the profile (`firered`; LeafGreen shares it,
-- src/core/game3/options.lua), and ours go there too.  Read as a plain
-- field: Options.block would create the block and skip the game's own
-- migration of old root keys.  The block exists once a game session has
-- bound its options, which is before the OPTION screen can open; until
-- then nothing is stored and the defaults apply.
local function gen3Options(game)
  local root = type(game.options) == "table" and game.options or nil
  if not root then return nil end
  local id = "firered"
  local Profile = package.loaded["src.core.game3.profile"]
  if Profile and type(Profile.active) == "function" then
    local ok, row = pcall(Profile.active)
    if ok and type(row) == "table" and type(row.optionsBlock) == "string" then id = row.optionsBlock end
  end
  local block = root[id]
  return type(block) == "table" and block or nil
end

local function options(game)
  if not game then return {} end
  local generation = GameVersion.generation()
  -- Gen 2's OPTION screen edits game.options in place (Game2:showOptions)
  if generation == 2 and type(game.options) == "table" then return game.options end
  if generation == 3 then return gen3Options(game) or {} end
  return game.save and game.save.options or {}
end

-- The auto-walk multiplier the player chose, or nil for "use the game's own
-- speed".  Clamped to the levels the current cart allows.
function Settings.autoWalkSpeed(game)
  local value = tonumber(options(game).accessAutoWalkSpeed)
  if not value then return nil end
  return GameSpeed.clamp(value)
end

-- Auto-walk pushes boulders and tries switches when a target has no route (Gen 2 and 3).
function Settings.autoWalkBoulders(game)
  return options(game).accessAutoWalkBoulders ~= false
end

function Settings.dialogueWhole(game)
  return options(game).accessDialogue == "whole"
end

-- Touch gestures (decision 66): on by default on Android, where our touch
-- service passes the game screen's touches through TalkBack, and on iOS, where
-- VoiceOver's direct touch does (docs/access/ios.md); off elsewhere, so a computer
-- keeps upstream's mouse and on-screen buttons.  POKEPORT_ACCESS_TOUCH=1
-- makes them the default on a computer too (scripted tests).
function Settings.touchDefault()
  if os.getenv("POKEPORT_ACCESS_TOUCH") == "1" then return true end
  local system = love and love.system
  if not (system and system.getOS) then return false end
  local ok, os_ = pcall(system.getOS)
  return ok and (os_ == "Android" or os_ == "iOS")
end

-- The touch rows are shown only where touch gestures can be used.
Settings.touchAvailable = Settings.touchDefault

function Settings.touchGestures(game)
  local value = options(game).accessTouchGestures
  if value == nil then return Settings.touchDefault() end
  return value == true
end

local TOUCH_WALK = { "manual", "hybrid", "auto" }
local TOUCH_WALK_LABELS = { manual = "MANUAL", hybrid = "HYBRID", auto = "AUTO" }

-- "manual" (each swipe one step), "hybrid" (one swipe walks the route's
-- next straight leg) or "auto" (a swipe walks to the selected point).
function Settings.touchWalking(game)
  local value = options(game).accessTouchWalk
  if value == "hybrid" or value == "auto" then return value end
  return "manual"
end

-- HAPTICS (decision 68): on unless the player turned it off.  The row is shown
-- only on a device that can play them (Haptics.available).
function Settings.haptics(game)
  return options(game).accessHaptics ~= false
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
  local rows = {
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
  rows[#rows + 1] = { id = "accessAutoWalkBoulders", label = "AUTO-WALK PUZZLES",
    value = function(g) return Settings.autoWalkBoulders(g) and "ON" or "OFF" end,
    step = function(g)
      local o = options(g)
      o.accessAutoWalkBoulders = o.accessAutoWalkBoulders == false and true or false
      return true
    end }
  if Settings.touchAvailable() then
    rows[#rows + 1] = { id = "accessTouchGestures", label = "TOUCH GESTURES",
      value = function(g) return Settings.touchGestures(g) and "ON" or "OFF" end,
      step = function(g)
        options(g).accessTouchGestures = not Settings.touchGestures(g)
        return true
      end }
    rows[#rows + 1] = { id = "accessTouchWalk", label = "TOUCH WALKING",
      value = function(g) return TOUCH_WALK_LABELS[Settings.touchWalking(g)] end,
      step = function(g, dir)
        local current = Settings.touchWalking(g)
        local index = 1
        for i, mode in ipairs(TOUCH_WALK) do if mode == current then index = i end end
        index = (index - 1 + (dir or 1)) % #TOUCH_WALK + 1
        options(g).accessTouchWalk = TOUCH_WALK[index] ~= "manual" and TOUCH_WALK[index] or nil
        return true
      end }
  end
  if require("src.access.Haptics").available() then
    rows[#rows + 1] = { id = "accessHaptics", label = "HAPTICS",
      value = function(g) return Settings.haptics(g) and "ON" or "OFF" end,
      step = function(g)
        -- nil (the default) is on; only "off" is stored
        if Settings.haptics(g) then options(g).accessHaptics = false
        else options(g).accessHaptics = nil end
        return true
      end }
  end
  return rows
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

-- Gen 3 (FireRed, LeafGreen): src/ui/game3/option_menu.lua is a singleton
-- that keeps its pages inside itself (`_pages`, each { title, rows, index,
-- scroll }; rows get the screen's ctx { session, game, options }).  Each
-- OptionMenu.show builds a fresh top page; right after it, our group row
-- goes first on that page and opens a page shaped like the screen's own
-- pushPage.  The rows take the game from ctx (the screen persists them
-- with game:writeOptions after a step).  Wrapped only once the module has
-- loaded (the Gen 3 HUD loads it), so other games never load Gen 3 code;
-- returns true once wrapped.
local function gen3Game(ctx)
  if type(ctx) == "table" and type(ctx.game) == "table" then return ctx.game end
  local CurrentGame = package.loaded["src.access.CurrentGame"]
  return CurrentGame and CurrentGame.get() or nil
end

function Settings.gen3Rows()
  local rows = {}
  for i, row in ipairs(Settings.rows()) do
    rows[i] = {
      id = row.id, label = row.label,
      value = function(ctx) return row.value(gen3Game(ctx)) end,
      step = function(ctx, dir) return row.step(gen3Game(ctx), dir) end,
    }
  end
  return rows
end

local GEN3_OPTIONS = "src.ui.game3.option_menu"

-- Each game's OPTION screen keeps its pages in its own field: FireRed, Ruby
-- and Sapphire in `_pages`, Emerald in `_st.pages`
-- (src/ui/game3/rse/option_menu.lua).
local function gen3Pages(OptionMenu)
  if OptionMenu.open == false then return nil end
  local pages = OptionMenu._pages
  if pages == nil and type(OptionMenu._st) == "table" then pages = OptionMenu._st.pages end
  return type(pages) == "table" and pages or nil
end

local function addGen3Page(OptionMenu)
  local pages = gen3Pages(OptionMenu)
  if not (pages and #pages == 1) then return end
  local rows = type(pages[1]) == "table" and pages[1].rows
  if type(rows) ~= "table" or (rows[1] and rows[1].id == "group.accessibility") then return end
  local pageRows = Settings.gen3Rows()
  table.insert(rows, 1, {
    id = "group.accessibility", label = "ACCESSIBILITY", group = true,
    value = function() return #pageRows .. " OPTIONS" end,
    activate = function()
      local open = gen3Pages(OptionMenu)
      if not open then return end
      open[#open + 1] = { title = "ACCESSIBILITY", rows = pageRows, index = 1, scroll = 0 }
    end,
  })
end

local function wrapGen3(path)
  if installed[path] then return true end
  local OptionMenu = package.loaded[path]
  if type(OptionMenu) ~= "table" or type(OptionMenu.show) ~= "function" then return false end
  installed[path] = true
  local originalShow = OptionMenu.show
  OptionMenu.show = function(...)
    local result = originalShow(...)
    addGen3Page(OptionMenu)
    return result
  end
  return true
end

-- The running game's own OPTION module, when its profile names one (the
-- Hoenn games).  Loaded here, because the game loads it only as it opens
-- the screen and calls show in that same frame, too late to wrap.
local function profileOptionsPath()
  local Profile = package.loaded["src.core.game3.profile"]
  if not (Profile and type(Profile.active) == "function") then return nil end
  local ok, row = pcall(Profile.active)
  local screens = ok and type(row) == "table" and type(row.ui) == "table" and row.ui.screens
  return type(screens) == "table" and screens.option or nil
end

function Settings.installGen3()
  local frlg = wrapGen3(GEN3_OPTIONS)
  local path = profileOptionsPath()
  if not path then return frlg end
  if not package.loaded[path] then pcall(require, path) end
  return wrapGen3(path) and frlg
end

function Settings.install()
  Settings.installGen3()
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
