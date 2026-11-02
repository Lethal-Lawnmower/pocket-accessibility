-- Works the save editor by keyboard on a scratch save and logs what it says:
-- adds a Pokémon and an item, changes money, sets a badge and a map position,
-- saves, reads the file back, then reads every page.  Silent and isolated, with
-- POKEPORT_VERSION naming the game:
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/editor_tour.lua
local U = require("tests.drivers.util")

return function()
  U.wait(10)
  package.path = package.path .. ";./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
  local version = os.getenv("POKEPORT_VERSION") or "red"
  local Speech = require("src.access.Speech")
  local spoken = {}
  local say = Speech.say
  Speech.say = function(text, opts)
    spoken[#spoken + 1] = tostring(text)
    return say(text, opts)
  end
  local function heard()
    local out = table.concat(spoken, " | ")
    spoken = {}
    return out
  end

  local App = require("App")
  local Gen = require("Gen")
  local SaveIO = require("SaveIO")
  local Serializer = require("src.core.SaveSerializer")
  local path = os.tmpname() .. "-editor-tour.lua"
  local file = assert(io.open(path, "wb"))
  file:write(Serializer.encode(Gen.newGame(version)))
  file:close()
  App.load(path, { version = version })
  local S = App.getState()

  -- the driver runs from update; the editor needs its own draws on a canvas
  local canvas = love.graphics.newCanvas(love.graphics.getDimensions())
  local function frames(n)
    for _ = 1, n or 1 do
      love.graphics.push("all")
      love.graphics.setCanvas(canvas)
      App.update(1 / 60)
      App.draw()
      love.graphics.setCanvas()
      love.graphics.pop()
      U.wait(1)
    end
  end
  local shift = false
  local isDown = love.keyboard.isDown
  love.keyboard.isDown = function(...)
    for _, name in ipairs({ ... }) do
      if shift and (name == "lshift" or name == "rshift") then return true end
    end
    return isDown(...)
  end
  local function key(name)
    App.keypressed(name)
    frames(3)
  end
  local function log(...) U.log("RESULT", ...) end

  -- Tab forward until the spoken text matches; true when found.
  local function focus(pattern)
    key("home")
    local first = heard()
    if first:find(pattern) then return true, first end
    for _ = 1, 150 do
      key("tab")
      local said = heard()
      if said:find(pattern) then return true, said end
      if said == "End of page" then break end
    end
    log("NOT FOUND", pattern)
    return false
  end
  local function press(pattern, settleFrames)
    local found = focus(pattern)
    if found then
      key("return")
      frames(settleFrames or 3)
    end
    local said = heard()
    log("press", pattern, "=>", said)
    return found, said
  end
  local function typeText(text)
    for ch in text:gmatch(".") do App.textinput(ch) end
    frames(3)
    heard()
  end
  local function openPage(pattern)
    local found = false
    for _ = 1, 20 do
      key("home")
      heard()
      key("tab")
      local said = heard()
      for _ = 1, 12 do
        if said:find("dropdown") then break end
        key("tab")
        said = heard()
      end
      break
    end
    key("return")
    frames(3)
    heard()
    key("home")
    heard()
    for _ = 1, 12 do
      key("down")
      if heard():find(pattern) then
        found = true
        break
      end
    end
    key("return")
    frames(30)
    log("page", pattern, found, "=>", heard())
  end
  local function readPage(name, limit)
    local lines = {}
    key("home")
    lines[#lines + 1] = heard()
    for _ = 1, limit or 60 do
      key("down")
      local said = heard()
      if said == "End of page" then break end
      lines[#lines + 1] = said
    end
    log("read", name, #lines, table.concat(lines, " / "))
  end

  frames(3)
  log("open =>", heard())
  log("active save would be", tostring(require("src.access.editor").activeSavePath(version)))

  -- optional: read a copy of a real save first, editing nothing
  local copy = os.getenv("EDITOR_TOUR_COPY")
  if copy then
    App.load(copy, { version = version })
    S = App.getState()
    frames(5)
    log("copy open =>", heard(), tostring(S.loadError), tostring(S.status))
    readPage("copy party", 50)
    openPage("Trainer")
    readPage("copy trainer", 30)
    App.load(path, { version = version })
    S = App.getState()
    frames(5)
    heard()
  end

  -- a Pokémon, by keyboard
  press("^Add, button")
  log("party", #(S.save.party or {}))
  readPage("party with a Pokémon", 40)
  press("^Change, button")
  typeText("PIKACHU")
  frames(400)
  log("species search =>", heard())
  key("return")
  frames(3)
  log("species picked =>", heard(), S.save.party[1] and S.save.party[1].species)
  if press("Level", 15) then
    typeText("50")
    key("return")
    frames(3)
    log("level typed =>", heard())
  end
  log("level now", S.save.party and S.save.party[1] and S.save.party[1].level)

  -- an item, by keyboard
  openPage("Items")
  press("^Add, button")
  typeText("POTION")
  frames(400)
  log("typed =>", heard())
  key("return")
  frames(3)
  log("item added =>", heard())
  key("escape")
  frames(3)
  log("picker closed =>", heard())
  readPage("items with one", 30)

  -- money
  openPage("Trainer")
  press("Money")
  log("money popup", tostring(S.editPopup and S.editPopup.mode))
  readPage("number popup", 15)
  key("escape")
  frames(3)
  heard()
  press("Money")
  key("return")
  frames(15)
  log("typing a value =>", heard())
  typeText("54321")
  key("return")
  frames(3)
  log("committed =>", heard())
  log("money now", S.save.money)

  -- a place on the map
  openPage("Map")
  local mapId = S.save.map or S.mapId
  press("search maps", 15)
  typeText("PALLET")
  log("searched =>", heard())
  key("tab")
  log("tab to result =>", heard())
  key("return")
  frames(3)
  log("chose map =>", heard(), S.mapId)
  shift = true
  key("right")
  log("cell =>", heard())
  key("down")
  log("cell =>", heard())
  shift = false
  press("^Player")
  log("player set", mapId, Gen.ofState and tostring(S.status))

  -- a badge: the section dropdown on the Items page, then a toggle
  openPage("Items")
  press("^Bag, dropdown")
  key("home")
  heard()
  for _ = 1, 8 do
    key("down")
    if heard():find("Badges") then break end
  end
  key("return")
  frames(30)
  log("badges page =>", heard())
  readPage("badges", 30)
  press("BOULDER", 5)
  log("badges now", S.save.badges and next(S.save.badges), "inventory", S.save.inventory and S.save.inventory.BOULDERBADGE)

  -- Close with unsaved edits asks first
  press("^Close, button")
  log("still open", tostring(App.getState() ~= nil))

  -- save and read the file back
  press("^Save, button")
  local saved = SaveIO.load(path)
  log("saved file: money", saved and saved.money, "party", saved and #(saved.party or {}),
    "status", tostring(S.status), "dirty", tostring(S.dirty))
  App.reload()
  S = App.getState()
  frames(5)
  heard()
  openPage("Trainer")
  log("after reload", select(2, focus("Money")))
  openPage("Party")
  local ok, map = require("MapBrowser").preview({ save = S.save, version = S.version, data = S.data, mapId = "PALLET_TOWN" })
  if ok and map.isWalkableCell then
    local open = 0
    for y = 0, map.heightCells - 1 do
      for x = 0, map.widthCells - 1 do
        if map:isWalkableCell(x, y) then open = open + 1 end
      end
    end
    log("Pallet walkable cells", open, "of", map.widthCells * map.heightCells)
  end
  -- a page left scrolled down is still readable from its top
  press("Lv ")
  for _ = 1, 30 do key("tab") end
  heard()
  local found = focus("Level")
  log("after scrolling, top of the Pokémon still reachable", tostring(found))

  for _, page in ipairs({ "Boxes", "Events", "Pok", "Checks" }) do
    openPage(page)
    readPage(page, 25)
  end
  os.remove(path)
  love.event.quit()
end
