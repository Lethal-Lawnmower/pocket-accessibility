-- In-game check for modules/pokemon.lua on Crystal: installs the module with
-- a fake ctx (the randomizer core is not needed), makes the save randomized,
-- builds a CHIKORITA the way wild and gift mons are built, opens its summary,
-- then makes the save vanilla again and repeats.  Logs `[driver]` lines; with
-- POKEPORT_ACCESS_TRACE=1 the summary's speech shows as `say!:` lines.
-- Run only through the isolated wrapper, silently, in a disposable identity:
--   POKEPORT_IDENTITY=pocket-access-rand-pokemon-<x> POKEPORT_ACCESS_SILENT=1
--   POKEPORT_BACKGROUND=1 POKEPORT_ACCESS_TRACE=1 POKEPORT_TOUCH=0
--   POKEPORT_VERSION=crystal POKEPORT_GAME=crystal
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=launcher/mods/crystal_randomizer/tests/pokemon_driver.lua
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
  local Module = dofile("launcher/mods/crystal_randomizer/modules/pokemon.lua")
  local Mon = require("src.battle.gen2.Mon")

  local function className(state)
    if state == nil then return "overworld" end
    local mt = getmetatable(state)
    for name, mod in pairs(package.loaded) do
      if mod == mt and type(name) == "string" then return (name:gsub("^src%.ui%.", "")) end
    end
    return tostring(mt)
  end
  local function top() return game.stack:top() end
  local function wait(n) U.wait(n) end
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    wait(2)
    game.input.state[button] = false
    wait(frames or 8)
  end
  local function waitFor(name, limit)
    for _ = 1, limit or 300 do
      if className(top()) == name then return true end
      wait(1)
    end
    U.log("FAIL", "never reached", name, "top", className(top()))
    return false
  end
  local function inWorld() return game.world and game.world.map and top() == nil end
  local function backToWorld()
    for _ = 1, 15 do
      if inWorld() then return true end
      tap("b", 24)
    end
    U.log("FAIL", "could not back out; top", className(top()))
    return false
  end

  for _ = 1, 900 do
    if game.world and game.world.map and game.phase == "play" and inWorld() then break end
    wait(1)
  end
  if not inWorld() then U.log("FAIL", "no world") love.event.quit() return end
  local data, save = game.data, game.save
  U.log("MAP", game.world.map.id, save.version)

  local function describe(label, species)
    local def = data.pokemon[species]
    local rows = {}
    for _, row in ipairs(def.levelMoves) do rows[#rows + 1] = row.level .. ":" .. row.move end
    U.log(label, species, "types", def.types[1] .. "/" .. def.types[2], "learnset", table.concat(rows, " "))
    local mon = assert(Mon.new(data, species, 5))
    local moves = {}
    for _, m in ipairs(mon.moves or {}) do moves[#moves + 1] = type(m) == "table" and m.id or tostring(m) end
    U.log(label, "Mon.new level 5", species, "moves", table.concat(moves, ","),
      "mon.types", (mon.types[1] or "?") .. "/" .. (mon.types[2] or "?"))
    return mon
  end

  local function summary(label, mon)
    save.party = { mon }
    game:openStartMenuItem("pokemon")
    if not waitFor("gen2.PartyMenu") then return end
    wait(20)
    tap("a")       -- submenu
    -- a randomized mon may know field moves, which the submenu lists first
    local sub = top().submenu
    for _ = 1, 8 do
      local item = sub and sub.items[sub.index]
      if not item or item.id == "STATS" then break end
      tap("down")
    end
    tap("a", 40)   -- STATS
    -- a text box first (logged, then dismissed) does not stop the check
    for _ = 1, 6 do
      local name = className(top())
      if name == "gen2.SummaryMenu" then break end
      if name == "src.render.TextBox" then
        local box = top()
        U.log(label, "text box before summary", tostring(box.text or box.message or (box.pages and box.pages[1])))
        tap("a", 30)
      else
        wait(20)
      end
    end
    if waitFor("gen2.SummaryMenu") then
      wait(30)
      local first, second = top():typeNames()
      U.log(label, "summary typeNames", tostring(first), tostring(second))
    end
    backToWorld()
  end

  local vanilla = describe("VANILLA", "CHIKORITA")

  local options = { pokemon_types = true, pokemon_moves = true }
  local ctx = Fake.new({ seed = "driver-seed", options = options })
  Module.install({ game = game }, ctx)
  ctx.setActive(true, "driver-seed", options)
  for _, line in ipairs(ctx.lines) do U.log("MODLOG", line) end
  local randomized = describe("RANDOM", "CHIKORITA")
  summary("RANDOM", randomized)

  ctx.setActive(false)
  for _, line in ipairs(ctx.lines) do U.log("MODLOG", line) end
  describe("RESTORED", "CHIKORITA")
  -- the randomized mon's summary after the save went vanilla: refreshStats
  -- re-reads the species, so it now shows the vanilla types
  summary("RESTORED-old-mon", randomized)
  summary("RESTORED", vanilla)
  U.log("DONE")
  love.event.quit()
end
