-- In-game check for modules/stats.lua on Crystal: installs the module with a
-- fake ctx (the randomizer core is not needed), gives the party a CHIKORITA
-- built while the save is still vanilla (a mon the player already has), makes
-- the save randomized, then opens the party menu and the summary (move screen
-- and stats page) and checks what the mon now carries; then makes the save
-- vanilla again and repeats.  Logs `[driver]` lines; with
-- POKEPORT_ACCESS_TRACE=1 the layer's speech shows as `say!:` lines.
-- Run only through the isolated wrapper, silently, in a disposable identity:
--   POKEPORT_IDENTITY=pocket-access-rand2-stats-<x> POKEPORT_ACCESS_SILENT=1
--   POKEPORT_BACKGROUND=1 POKEPORT_ACCESS_TRACE=1 POKEPORT_TOUCH=0
--   POKEPORT_VERSION=crystal POKEPORT_GAME=crystal
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=launcher/mods/crystal_randomizer/tests/stats_driver.lua
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
  local Module = dofile("launcher/mods/crystal_randomizer/modules/stats.lua")
  local Mon = require("src.battle.gen2.Mon")
  local KEYS = Module.STAT_KEYS

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

  local function statLine(stats)
    local parts = {}
    for _, key in ipairs(KEYS) do parts[#parts + 1] = key .. "=" .. tostring(stats and stats[key]) end
    return table.concat(parts, " ")
  end
  local function expected(mon)
    return Mon.stats(data.pokemon[mon.species].baseStats, mon.dvs, mon.level, mon.statExp)
  end
  local function same(a, b)
    for _, key in ipairs(KEYS) do if a[key] ~= b[key] then return false end end
    return true
  end
  local function moveLine(id)
    local m = data.moves[id]
    return ("%s %s power %s accuracy %s raw %s"):format(id, tostring(m.type), tostring(m.power),
      tostring(m.accuracy), tostring(m.accuracyRaw))
  end

  -- Party menu and summary: what refreshStats leaves on the mon, and what the
  -- screens' own move lookup returns.  Speech is in the say!: lines between.
  local function look(label, mon)
    save.party = { mon }
    U.log(label, "stored stats before any screen", statLine(mon.stats))
    game:openStartMenuItem("pokemon")
    if not waitFor("gen2.PartyMenu") then return end
    wait(20)
    U.log(label, "after party menu", statLine(mon.stats), "maxHp", tostring(mon.maxHp), "hp", tostring(mon.hp))
    U.log(label, same(mon.stats, expected(mon)) and "PASS" or "FAIL",
      "party menu stats match this save's base stats")
    tap("a")       -- submenu
    local sub = top().submenu
    for _ = 1, 8 do
      local item = sub and sub.items[sub.index]
      if not item or item.id == "STATS" then break end
      tap("down")
    end
    tap("a", 40)   -- STATS
    if waitFor("gen2.SummaryMenu") then
      wait(30)
      local menu = top()
      U.log(label, "SECTION moves page and move screen")
      tap("right", 30)    -- the moves page
      tap("select", 40)   -- the move screen: name, type, power of the first move
      for i, move in ipairs(mon.moves or {}) do
        local def = menu:moveDef(move.id) or {}
        U.log(label, "summary moveDef", i, move.id, "type", tostring(def.type), "power", tostring(def.power))
      end
      tap("down", 30)     -- the second move, spoken
      tap("b", 30)        -- back to the moves page
      U.log(label, "SECTION stats page")
      tap("right", 40)    -- the stats page
      U.log(label, "summary page", tostring(menu.page), "mon.stats", statLine(menu.mon.stats))
    end
    backToWorld()
  end

  local caught = assert(Mon.new(data, "CHIKORITA", 20))
  local vanillaBase = statLine(data.pokemon.CHIKORITA.baseStats)
  U.log("VANILLA", "base", vanillaBase)
  local moveIds = {}
  for _, move in ipairs(caught.moves) do moveIds[#moveIds + 1] = move.id end
  for _, id in ipairs(moveIds) do U.log("VANILLA", "move", moveLine(id)) end
  look("VANILLA", caught)

  local options = { stats_base = true, stats_base_mode = "reorder", stats_moves = true }
  local ctx = Fake.new({ seed = "driver-seed", options = options })
  Module.install({ game = game }, ctx)
  ctx.setActive(true, "driver-seed", options)
  for _, line in ipairs(ctx.lines) do U.log("MODLOG", line) end
  U.log("RANDOM", "base", statLine(data.pokemon.CHIKORITA.baseStats))
  for _, id in ipairs(moveIds) do U.log("RANDOM", "move", moveLine(id)) end
  look("RANDOM", caught)

  -- A battle recalculates both sides at its start (Battle.lua): the same call.
  local copy = {}
  for k, v in pairs(caught) do copy[k] = v end
  copy.stats = nil
  Mon.refreshStats(copy, data)
  U.log("RANDOM", same(copy.stats, expected(caught)) and "PASS" or "FAIL", "refreshStats matches")

  ctx.setActive(false)
  for _, line in ipairs(ctx.lines) do U.log("MODLOG", line) end
  U.log("RESTORED", "base", statLine(data.pokemon.CHIKORITA.baseStats),
    statLine(data.pokemon.CHIKORITA.baseStats) == vanillaBase and "PASS" or "FAIL")
  for _, id in ipairs(moveIds) do U.log("RESTORED", "move", moveLine(id)) end
  look("RESTORED", caught)
  U.log("DONE")
  love.event.quit()
end
