-- Gen 2 walkthrough: boot Gold, Silver or Crystal from the copyright screen,
-- start a new game, open the start menu and each of its pages, step outside,
-- and fight a wild battle, logging every screen change and every utterance.
-- It asserts nothing about order, so it shows what the layer says (or misses)
-- on each screen.  Run silently with POKEPORT_VERSION and POKEPORT_GAME set to
-- gold, silver or crystal and a disposable identity, plus
-- POKEPORT_BOOT_CINEMA=1 for the full intro.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Speech = require("src.access.Speech")

  -- class names: reverse lookup of the loaded Gen 2 screen modules
  local function className(state)
    if state == nil then return "overworld" end
    local mt = getmetatable(state)
    for name, mod in pairs(package.loaded) do
      if mod == mt and type(name) == "string" then return (name:gsub("^src%.ui%.", "")) end
    end
    return tostring(state.name or state.id or mt)
  end

  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts) said[#said + 1] = tostring(text) return say(text, opts) end
  local lastTop
  local function watch()
    local top = game.stack:top()
    local name = className(top)
    if name ~= lastTop then
      U.log("SCREEN", name)
      lastTop = name
    end
    if #said > 0 then
      for _, line in ipairs(said) do U.log("SAID", line) end
      said = {}
    end
  end
  local function wait(n) for _ = 1, n do U.wait(1) watch() end end
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    wait(2)
    game.input.state[button] = false
    wait(frames or 6)
  end
  local function topIs(name) return className(game.stack:top()) == name end
  local function inWorld() return game.phase == "play" and game.world and game.world.map and game.stack:top() == nil end

  -- boot to the main menu
  for _ = 1, 3000 do
    if topIs("gen2.MainMenu") then break end
    tap("start", 20)
  end
  wait(30)
  local menu = game.stack:top()
  if menu and menu.list then
    for i = 1, #menu.list.items do
      if menu.list.index == nil then break end
      if menu.list.items[menu.list.index].value == "new" then break end
      tap("down", 10)
    end
  end
  tap("a", 30)

  -- new game: gender (Crystal), clock, Oak, name pick, naming
  for _ = 1, 1500 do
    if inWorld() then break end
    local top = game.stack:top()
    local name = className(top)
    if name == "gen2.NamingScreen" and top.bottomRow then
      tap("a") tap("right") tap("a")
      top.row = top:bottomRow() top.col = 6
      tap("a", 20)
    elseif name == "gen2.NamePick" and top.slide ~= nil then
      wait(10)
    else
      tap("a", 8)
    end
  end
  if not inWorld() then U.log("FAIL", "never reached the overworld; top", className(game.stack:top())) return end
  U.log("MAP", game.world.map.id)
  wait(60)

  -- start menu: open each entry and back out
  tap("start", 30)
  local start = game.stack:top()
  local count = start and start.list and #start.list.items or (start and start.items and #start.items) or 6
  for i = 1, count do
    tap("a", 60)
    for _ = 1, 4 do tap("down", 15) end
    for _ = 1, 6 do
      if topIs("gen2.StartMenu") then break end
      tap("b", 30)
    end
    if not topIs("gen2.StartMenu") then break end
    tap("down", 15)
  end
  for _ = 1, 6 do if inWorld() then break end tap("b", 20) end

  -- downstairs and outside through the real doors
  wait(30)
  local Mon = require("src.battle.gen2.Mon")
  local player = Mon.new(game.data, "CYNDAQUIL", 12)
  game.save.party = { player }
  game.world:setMap("NEW_BARK_TOWN", 13, 6, "down")
  wait(120)
  U.log("MAP", game.world.map.id)
  for _ = 1, 4 do tap("left", 20) end

  local wild = Mon.new(game.data, "SENTRET", 3)
  game.world:startBattle({ wild = wild })
  for _ = 1, 400 do
    if inWorld() then break end
    tap("a", 20)
  end
  wait(60)
  Speech.say = say
  U.log("DONE")
end
