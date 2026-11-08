-- A game run for the keyitems module, on Crystal, with no core: the driver
-- builds the module's ctx from tests/fake_ctx.lua with a seed whose placement
-- moves another HM into the Olivine Cafe and into the Ice Path ball, hands it
-- the live game and the engine's own hook table, and then
--   1. runs the Olivine Cafe sailor's script in the VM and logs what he said
--      and which HM entered the bag;
--   2. teleports beside the Ice Path HM ball, logs what the navigation's
--      object list names it, picks it up with A and logs what entered the bag;
--   3. switches to a vanilla save and logs that the ball holds HM07 again.
-- Run silently and isolated, with a disposable identity:
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_BACKGROUND=1 POKEPORT_VERSION=crystal
--   POKEPORT_GAME=crystal POKEPORT_IDENTITY=pocket-access-rand2-keys-<x>
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=launcher/mods/crystal_randomizer/tests/keyitems_driver.lua
--   "C:\Program Files\LOVE\lovec.exe" .
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local Runtime = require("src.mods.Runtime")
  local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
  local K = dofile("launcher/mods/crystal_randomizer/modules/keyitems.lua")

  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") return end
  U.log("RESULT", "start", L.where())
  local data = game.data

  -- a seed that moves both locations this run looks at
  local seed
  for n = 1, 500 do
    local probe = Fake.new({ seed = "keys-driver-" .. n, options = { keyitems = true } })
    local p = K.choose(probe)
    if p.OLIVINE_CAFE ~= "HM_STRENGTH" and p.ICE_PATH_1F ~= "HM_WATERFALL" then
      seed = "keys-driver-" .. n
      break
    end
  end
  if not seed then U.log("FAIL", "no seed moves both") return end
  local ctx = Fake.new({ seed = seed, options = { keyitems = true } })
  local mod = { game = game, hooks = {
    wrap = function(_, name, fn) return Runtime.hooks:wrap(name, fn, 0, "crystal_randomizer_driver") end,
  } }
  -- the locations, found while the data is still vanilla
  local found, why = K.discover(data)
  if not found then U.log("FAIL", "discover", tostring(why)) return end
  K.install(mod, ctx)
  ctx.setActive(true)
  for _, line in ipairs(ctx.lines) do U.log("MODLOG", line) end
  local placement = ctx.shared.keyitems
  if not placement then U.log("FAIL", "no placement published") return end
  U.log("RESULT", "seed", seed, "beatable", tostring(K.beatable(placement)))

  local vm = game.world.vm
  local function has(id) return vm.hasItemFn and vm.hasItemFn(data.items[id].index) end
  local pool = {}
  for _, site in ipairs(K.SITES) do pool[#pool + 1] = site.item end
  local function holding()
    local out = {}
    for _, id in ipairs(pool) do if has(id) then out[#out + 1] = id end end
    return table.concat(out, ",")
  end
  U.log("RESULT", "bag before", holding())

  -- ------------------------------------------------------------ the cafe sailor
  local cafeItem = placement.OLIVINE_CAFE
  local give = found.sites.OLIVINE_CAFE.give
  L.heard()
  vm:start(give.key)
  for _ = 1, 900 do
    if L.free() and has(cafeItem) then break end
    if game.stack:top() ~= nil or not L.free() then L.tap("a", 8) else U.wait(1) end
  end
  L.settle(300, true)
  local speech = L.heard()
  U.log("RESULT", "cafe speech =>", speech)
  local def = data.items[cafeItem]
  local move = K.FIELD_MOVES[cafeItem].move
  U.log("RESULT", "cafe placed", cafeItem, "bag has it", has(cafeItem) and "YES" or "NO",
    "said received " .. def.name, speech:find("received", 1, true) and speech:find(def.name, 1, true) and "YES" or "NO",
    "said " .. move, speech:find(move, 1, true) and "YES" or "NO",
    "said STRENGTH", speech:find("STRENGTH", 1, true) and "YES" or "NO",
    "bag", holding())

  -- ------------------------------------------------------------ the charcoal master
  -- (his gift is followed by an explanation line, which is generated)
  local ilexItem = placement.ILEX_FOREST
  local ilexGive = found.sites.ILEX_FOREST.give
  L.heard()
  vm:start(ilexGive.key)
  for _ = 1, 900 do
    if L.free() and has(ilexItem) then break end
    if game.stack:top() ~= nil or not L.free() then L.tap("a", 8) else U.wait(1) end
  end
  L.settle(300, true)
  local ilexSpeech = L.heard()
  U.log("RESULT", "Ilex speech =>", ilexSpeech)
  local field = K.FIELD_MOVES[ilexItem]
  U.log("RESULT", "Ilex placed", ilexItem, "bag has it", has(ilexItem) and "YES" or "NO",
    "said received " .. data.items[ilexItem].name,
    ilexSpeech:find("received", 1, true) and ilexSpeech:find(data.items[ilexItem].name, 1, true) and "YES" or "NO",
    "said " .. field.badgeName, ilexSpeech:find(field.badgeName, 1, true) and "YES" or "NO",
    "said CUT HM", ilexSpeech:find("CUT HM", 1, true) and "YES" or "NO")

  -- ------------------------------------------------------------ the Ice Path ball
  local ballItem = placement.ICE_PATH_1F
  local ball = found.sites.ICE_PATH_1F.ball
  local object
  for _, o in ipairs(data.gen2Maps.ICE_PATH_1F.objects) do if o.itemball == ball then object = o end end
  U.log("RESULT", "ball", "at", object.x, object.y, "holds", tostring(ball.item), "placed", ballItem,
    data.items[ballItem].index == ball.item and "MATCH" or "MISMATCH")
  game.save.repelSteps = 60000
  local reached = false
  for _, side in ipairs({ { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" } }) do
    local x, y = object.x + side[1], object.y + side[2]
    L.teleport("ICE_PATH_1F", x, y, side[3])
    local id, px, py = L.pos()
    if id == "ICE_PATH_1F" and px == x and py == y then
      game.world.player.facing = side[3]
      L.wait(10)
      local name = data.items[ballItem].name
      local seen = L.find(function(i) return tostring(i.description or ""):find(name, 1, true) ~= nil end)
      U.log("RESULT", "navigation lists", seen and tostring(seen.description) or "nothing naming " .. name)
      L.heard()
      L.tap("a", 20)
      L.settle(600, true)
      reached = true
      break
    end
  end
  if not reached then U.log("FAIL", "could not stand beside the ball") return end
  local pickup = L.heard()
  U.log("RESULT", "pickup speech =>", pickup)
  U.log("RESULT", "ball placed", ballItem, "bag has it", has(ballItem) and "YES" or "NO",
    "said " .. data.items[ballItem].name, pickup:find(data.items[ballItem].name, 1, true) and "YES" or "NO",
    "bag", holding())

  -- ------------------------------------------------------------ a vanilla save
  ctx.setActive(false)
  U.log("RESULT", "after a vanilla save the ball holds", tostring(ball.item),
    ball.item == data.items.HM_WATERFALL.index and "HM_WATERFALL" or "NOT VANILLA")
  U.log("DONE")
  love.event.quit()
end
