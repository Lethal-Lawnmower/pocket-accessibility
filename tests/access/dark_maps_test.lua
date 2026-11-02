-- Dark maps need Flash (decision 37): what each generation calls dark, what
-- stays in sight, and that auto-walk, guided navigation, the list and the
-- camera all keep to it.  Synthetic worlds; the game half is
-- drivers/dark_maps.lua.
-- Run: luajit tests/access/dark_maps_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness")
local check, eq = T.check, T.eq

local Speech = require("src.access.Speech")
local spoken = {}
local fake = { name = "Fake" }
function fake:say(text) spoken[#spoken + 1] = text return true end
function fake:stop() return true end
function fake:close() end
Speech.shutdown()
Speech.start({ backend = fake })

local Navigation1 = require("src.access.nav.Navigation")
local Navigation2 = require("src.access.nav.gen2.Navigation")
local Navigation3 = require("src.access.nav.gen3.Navigation")
local AutoWalk = require("src.access.nav.AutoWalk")

local TOO_DARK = "Too dark. Use Flash."

-- A coordinator of `class` standing at 10,10 with the given list.
local function navOn(class, game, world, items)
  world.player = { cellX = 10, cellY = 10 }
  local nav = setmetatable({ game = game, enabled = false, browseFilter = "all" }, { __index = class })
  nav.worldForCommand = function() return world end
  nav.captureWorld = function() return { browse = items } end
  nav.announced = {}
  nav.announceManual = function(self, parts)
    self.announced[#self.announced + 1] = table.concat(parts, " ")
    return true
  end
  return nav
end

local function labels(nav)
  local item, reason, snapshot = nav:selectedBrowseItem(0)
  if not item then return reason end
  local names = {}
  for _, entry in ipairs(snapshot.browse) do names[#names + 1] = entry.label end
  return table.concat(names, ",")
end

local function list()
  return {
    { label = "Near", type = "object", x = 11, y = 10 },
    { label = "Edge", type = "object", x = 15, y = 6 },
    { label = "Far", type = "object", x = 20, y = 10 },
    { label = "Exit", type = "warp", x = 13, y = 10 },
    { label = "Far Exit", type = "warp", x = 30, y = 30 },
    { label = "Connection", type = "connection" },
    { label = "Ball", type = "area", x = 11, y = 11, mapId = "OTHER" },
  }
end

-- ------------------------------------------------------------ Gen 1
do
  local game = { data = { field = { darkMaps = { maps = { "ROCK_TUNNEL_1F" } } } }, save = {} }
  local world = { map = { id = "ROCK_TUNNEL_1F" } }
  local nav = navOn(Navigation1, game, world, list())
  check(nav:isDark(world), "Gen 1: a dark map without Flash is dark")
  eq(nav:darkRefusal(), TOO_DARK, "Gen 1: navigation refuses")
  eq(labels(nav), "Near,Edge,Exit", "Gen 1: the list keeps the screen")

  nav:startWorldRoute({ { x = 11, y = 10 } }, nil, "selected")
  eq(nav.announced[#nav.announced], TOO_DARK, "Gen 1: guided navigation refuses")

  local allowed = AutoWalk.start(nav, { input = {} })
  eq(allowed, false, "Gen 1: auto-walk refuses")
  check(not AutoWalk.active(), "Gen 1: no walk started")

  local count = #nav.announced
  nav.sonarMapId, nav.sonarX, nav.sonarY = "ROCK_TUNNEL_1F", 6, 10
  nav:moveSonar("left", false)
  eq(nav.announced[count + 1], TOO_DARK, "Gen 1: the camera stops at the screen's edge")
  eq(nav.sonarX, 6, "Gen 1: the camera did not move")

  game.save.flashLit = true
  check(not nav:isDark(world), "Gen 1: Flash lights it")
  eq(nav:darkRefusal(), nil, "Gen 1: navigation works again")
  eq(labels(nav), "Near,Edge,Far,Exit,Far Exit,Connection,Ball", "Gen 1: the whole list is back")

  game.save.flashLit = nil
  world.map.id = "ROUTE_1"
  check(not nav:isDark(world), "Gen 1: other maps are not dark")
  eq(labels(nav), "Near,Edge,Far,Exit,Far Exit,Connection,Ball", "Gen 1: other maps list everything")
end

-- An empty dark list says why, not "Empty List."
do
  local game = { data = { field = { darkMaps = { maps = { "ROCK_TUNNEL_1F" } } } }, save = {} }
  local nav = navOn(Navigation1, game, { map = { id = "ROCK_TUNNEL_1F" } }, {
    { label = "Far", type = "object", x = 40, y = 40 },
  })
  eq(select(2, nav:selectedBrowseItem(0)), TOO_DARK, "nothing in sight says it is too dark")
  nav.game = {}
  eq(nav:darkRefusal(), nil, "a game without dark data is never dark")
end

-- ------------------------------------------------------------ Gen 2
do
  local native = { hour = function() return 12 end }
  local world = { native = native, map = { def = { id = "DARK_CAVE", palette = "PALETTE_DARK" } } }
  local nav = navOn(Navigation2, {}, world, list())
  check(nav:isDark(world), "Gen 2: a PALETTE_DARK map without Flash is dark")
  eq(labels(nav), "Exit", "Gen 2: only warps on screen are in sight")
  check(not nav:darkCellVisible(world, 11, 10), "Gen 2: the camera cannot move")

  native.flashUsed = true
  check(not nav:isDark(world), "Gen 2: Flash lights it")
  eq(labels(nav), "Near,Edge,Far,Exit,Far Exit,Connection,Ball", "Gen 2: the whole list is back")

  native.flashUsed = nil
  world.map.def.palette = "PALETTE_NITE"
  check(not nav:isDark(world), "Gen 2: a merely night-coloured cave is not dark")
end

-- ------------------------------------------------------------ Gen 3
do
  local view = { flashLevel = 4 }
  view.flashRadius = function() return ({ 72, 56, 40, 24 })[view.flashLevel] end
  package.loaded["src.core.game3.field_view"] = view
  local world = { map = { id = "FR_ROCK_TUNNEL_1F" } }
  local nav = navOn(Navigation3, {}, world, list())
  check(nav:isDark(world), "Gen 3: a flash level is dark")
  check(nav:darkCellVisible(world, 11, 11), "Gen 3: the corner cell is inside the smallest circle")
  check(not nav:darkCellVisible(world, 12, 10), "Gen 3: two cells away is outside it")
  eq(labels(nav), "Near", "Gen 3: the list keeps the circle of light")

  view.flashLevel = 1
  eq(labels(nav), "Near,Exit", "Gen 3: a wider circle keeps more")

  view.flashLevel = 0
  view.flashRadius = function() return nil end
  check(not nav:isDark(world), "Gen 3: Flash lights it")
  eq(labels(nav), "Near,Edge,Far,Exit,Far Exit,Connection,Ball", "Gen 3: the whole list is back")
  package.loaded["src.core.game3.field_view"] = nil
end

Speech.shutdown()
T.finish("dark maps")
