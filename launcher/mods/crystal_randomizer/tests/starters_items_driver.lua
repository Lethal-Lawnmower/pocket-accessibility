-- A game run for the starters and items modules, on Crystal, with no core:
-- the driver builds the modules' ctx from tests/fake_ctx.lua (a fixed seed,
-- every question answered YES), hands them the live game and the engine's own
-- hook table, and then
--   0. logs the three starters, each ball's rival pair (three stages and the
--      type triangle are on) and the size of the live type chart;
--   1. runs Elm's CYNDAQUIL ball script in the VM, answers YES and declines a
--      nickname, and logs what Elm said and what species joined the party;
--   2. teleports beside an item ball whose contents the shuffle changed, logs
--      what the navigation's object list names it, picks it up with A, and
--      logs what entered the bag.
-- Run silently and isolated, with a disposable identity:
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_BACKGROUND=1 POKEPORT_VERSION=crystal
--   POKEPORT_GAME=crystal POKEPORT_IDENTITY=pocket-access-rand-starters-<x>
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=launcher/mods/crystal_randomizer/tests/starters_items_driver.lua
--   "C:\Program Files\LOVE\lovec.exe" .
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local Speech = require("src.access.Speech")
  local Runtime = require("src.mods.Runtime")
  local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
  local Starters = dofile("launcher/mods/crystal_randomizer/modules/starters.lua")
  local Items = dofile("launcher/mods/crystal_randomizer/modules/items.lua")

  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts)
    said[#said + 1] = tostring(text)
    return say(text, opts)
  end
  local function heard()
    local s = table.concat(said, " | ")
    said = {}
    return s
  end

  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") return end
  U.log("RESULT", "start", L.where())
  local data = game.data

  local seed = os.getenv("RAND_SEED") or "driver-seed"
  local ctx = Fake.new({ seed = seed,
    options = { starters = true, starters_stages = true, starters_triangle = true, gifts = true,
      gifts_legendary = true, items = true, items_hidden = true } })
  local mod = { game = game, hooks = {
    wrap = function(_, name, fn) return Runtime.hooks:wrap(name, fn, 0, "crystal_randomizer_driver") end,
  } }
  Starters.install(mod, ctx)
  Items.install(mod, ctx)
  -- the cart's own contents, before the shuffle, keyed by the itemball table
  local vanillaBall = {}
  for _, map in pairs(data.gen2Maps or {}) do
    for _, object in ipairs(type(map) == "table" and map.objects or {}) do
      if object.itemball then vanillaBall[object.itemball] = object.itemball.item end
    end
  end
  ctx.setActive(true)
  for _, line in ipairs(ctx.lines) do U.log("MODLOG", line) end
  local s = ctx.shared.starters
  if not s then U.log("FAIL", "no starters published") return end
  U.log("RESULT", "starters", "CHIKORITA>" .. s.CHIKORITA, "CYNDAQUIL>" .. s.CYNDAQUIL,
    "TOTODILE>" .. s.TOTODILE)
  -- the live game's type chart and evolutions: three stages, and each rival
  -- ball strong against the player's
  local pairs_ = ctx.shared.starterRivalPairs
  U.log("RESULT", "type chart rows", #((data.type_chart or {}).matchups or {}))
  for _, ball in ipairs(Starters.STARTERS) do
    local pair = pairs_ and pairs_[ball]
    if not pair then U.log("FAIL", "no rival pair for", ball) return end
    U.log("RESULT", "pair", "player " .. ball .. "=" .. pair.player, "rival " .. pair.rivalBall .. "=" .. pair.rival,
      "strong", tostring(pair.strong), "stages", Starters.lineLength(data.pokemon, pair.player),
      "types", tostring(Starters.typePhrase(data.pokemon[pair.player])))
  end

  -- ------------------------------------------------------------ the starter
  local species = Starters.species(data.pokemon)
  local key
  for k, list in pairs(data.gen2Scripts or {}) do
    local plan = type(list) == "table" and Starters.planFor(list, species.byIndex)
    if plan and plan[data.pokemon.CYNDAQUIL.index] == "starter" then key = k end
  end
  if not key then U.log("FAIL", "Elm's CYNDAQUIL ball script not found") return end
  U.log("RESULT", "ball script", key)
  local partyBefore = #(game.save.party or {})
  heard()
  game.world.vm:start(key)
  local got
  for i = 1, 900 do
    local party = game.save.party or {}
    if #party > partyBefore then got = party[#party] end
    if got and L.free() then break end
    -- A through Elm's question (YES is the default); after the gift, B
    -- declines the nickname and closes the rest
    if game.stack:top() ~= nil or not L.free() then L.tap(got and "b" or "a", 8) else U.wait(1) end
  end
  L.settle(300, false)
  local speech = heard()
  U.log("RESULT", "Elm speech =>", speech)
  local expected = data.pokemon[s.CYNDAQUIL]
  U.log("RESULT", "party got", got and got.species or "nothing", "expected", s.CYNDAQUIL,
    got and got.species == s.CYNDAQUIL and "MATCH" or "MISMATCH",
    "level", got and got.level or "?")
  U.log("RESULT", "Elm named it", speech:find(expected.name, 1, true) and "YES" or "NO",
    "type phrase", tostring(Starters.typePhrase(expected)),
    speech:find(tostring(Starters.typePhrase(expected)), 1, true) and "YES" or "NO")

  -- ------------------------------------------------------------ an item ball
  local byIndex = {}
  for id, def in pairs(data.items) do
    if type(def) == "table" and def.index then byIndex[def.index] = id end
  end
  local balls = Items.locations(data.gen2Maps, data.items, false)
  local target
  for _, mapId in ipairs({ "ROUTE_29", "ROUTE_30", "ROUTE_31", "ROUTE_46", "DARK_CAVE_VIOLET_ENTRANCE",
      "ROUTE_32", "SPROUT_TOWER_1F", "UNION_CAVE_1F" }) do
    local map = data.gen2Maps[mapId]
    for _, object in ipairs(map and map.objects or {}) do
      local ball = object.itemball
      local id = ball and byIndex[ball.item]
      local def = id and data.items[id]
      if def and (def.pocket == "ITEM" or def.pocket == "BALL") and not target
         and vanillaBall[ball] ~= ball.item then
        target = { map = mapId, object = object, item = id }
      end
    end
    if target then break end
  end
  if not target then U.log("FAIL", "no item ball found") return end
  U.log("RESULT", "ball", target.map, "#" .. tostring(target.object.index),
    "at", target.object.x, target.object.y, "now holds", target.item,
    "x" .. tostring(target.object.itemball.quantity),
    "vanilla", tostring(byIndex[vanillaBall[target.object.itemball]]), "(" .. #balls .. " movable balls)")

  game.save.repelSteps = 60000
  local bagBefore = {}
  for id, n in pairs(game.save.inventory or {}) do bagBefore[id] = n end
  local reached = false
  for _, side in ipairs({ { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" } }) do
    local x, y = target.object.x + side[1], target.object.y + side[2]
    L.teleport(target.map, x, y, side[3])
    local id, px, py = L.pos()
    if id == target.map and px == x and py == y then
      game.world.player.facing = side[3]
      L.wait(10)
      local seen = L.find(function(i)
        return tostring(i.description or ""):upper():find((target.item:gsub("_", " ")), 1, true) ~= nil
      end)
      U.log("RESULT", "navigation lists", seen and tostring(seen.description) or "nothing naming it")
      heard()
      L.tap("a", 20)
      L.settle(600, true)
      reached = true
      break
    end
  end
  if not reached then U.log("FAIL", "could not stand beside the ball") return end
  U.log("RESULT", "pickup speech =>", heard())
  local gained = {}
  for id, n in pairs(game.save.inventory or {}) do
    if n ~= (bagBefore[id] or 0) then gained[#gained + 1] = id .. " +" .. (n - (bagBefore[id] or 0)) end
  end
  U.log("RESULT", "bag gained", table.concat(gained, ", "),
    (game.save.inventory or {})[target.item] and "MATCH" or "MISMATCH")

  -- a vanilla save afterwards puts the ball back
  ctx.setActive(false)
  U.log("RESULT", "after a vanilla save the ball holds", tostring(byIndex[target.object.itemball.item]),
    "starters", tostring(ctx.shared.starters))
  U.log("DONE")
  love.event.quit()
end
