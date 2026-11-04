-- Which Gen 3 cartridge navigation is reading, and the constants that differ
-- between them (decision 29).  Upstream already holds every table:
-- the profile (map prefix, family, badges) and the per-game constants (object
-- graphics, specials, flags, map groups).  Nothing here is a second copy; a
-- lookup that finds no game (unit tests, early boot) answers for FireRed,
-- which is what the numbers in the older tests were written against.
--
-- Metatile behaviours do NOT differ at run time: the importer translates each
-- cartridge's raw byte to upstream's canonical ids (src/core/game3/mb.lua,
-- src/import/gba/mb_<game>.lua): FireRed's numbers, plus 0x100 + raw for names
-- only Ruby, Sapphire and Emerald have.  Read those by name through `mb(name)`.

local GameData = {}

local FALLBACK = "firered"

local function lazy(path)
  local module = package.loaded[path]
  if type(module) == "table" then return module end
  local ok, value = pcall(require, path)
  return ok and value or nil
end

-- The running cartridge's version id ("emerald", "ruby", ...).
function GameData.id()
  local Profile = lazy("src.core.game3.profile")
  if Profile and Profile.active then
    local ok, row = pcall(Profile.active)
    if ok and type(row) == "table" and type(row.id) == "string" then return row.id end
  end
  return FALLBACK
end

function GameData.profile()
  local Profile = lazy("src.core.game3.profile")
  if Profile and Profile.active then
    local ok, row = pcall(Profile.active)
    if ok and type(row) == "table" then return row end
  end
  return nil
end

function GameData.isHoenn()
  local row = GameData.profile()
  return type(row) == "table" and row.family == "rse"
end

function GameData.isEmerald() return GameData.id() == "emerald" end

-- The constants set of the running cartridge, or nil.
function GameData.constants()
  local Constants = lazy("src.core.game3.constants")
  if not (Constants and Constants.of) then return nil end
  local ok, set = pcall(Constants.of, GameData.id())
  return ok and set or nil
end

-- The prefix the running game's map ids carry ("EM_").
function GameData.mapPrefix()
  local row = GameData.profile()
  local map = type(row) == "table" and row.map or nil
  return type(map) == "table" and map.enginePrefix or "FR_"
end

local PREFIXES = { FR_ = true, LG_ = true, EM_ = true, RU_ = true, SA_ = true }

-- A map id without its game's prefix.
function GameData.bareMapId(mapId)
  if type(mapId) ~= "string" then return nil end
  local head = mapId:sub(1, 3)
  if PREFIXES[head] then return mapId:sub(4) end
  return mapId
end

-- Ruby and Sapphire number the seabeds; these are the routes their `emerge` links name.
GameData.RS_UNDERWATER = { UNDERWATER1 = "ROUTE124", UNDERWATER2 = "ROUTE126",
  UNDERWATER3 = "ROUTE127", UNDERWATER4 = "ROUTE128" }

-- A canonical metatile behaviour by name, or nil on names this build lacks.
function GameData.mb(name)
  local MB = lazy("src.core.game3.mb")
  return MB and MB.id and MB.id(name) or nil
end

-- A flag's or variable's number on this cartridge, by name, or nil.
function GameData.flag(name)
  local set = GameData.constants()
  local flags = set and set.flags
  return flags and flags.byName and flags.byName[name] or nil
end

function GameData.var(name)
  local set = GameData.constants()
  local vars = set and set.vars
  return vars and vars.byName and vars.byName[name] or nil
end

return GameData
