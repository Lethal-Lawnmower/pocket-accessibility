-- A game run for the tms module, on Crystal, with no core: the driver builds
-- the module's ctx from tests/fake_ctx.lua (a fixed seed, every TM question
-- answered YES), hands it the live game and the engine's own hook table, then
--   1. opens the PACK on the TM pocket and logs what the row draws and what
--      the screen reader layer says for it, against the TM's new move;
--   2. teaches that TM from the PACK to a party mon that may learn it, and
--      logs the mon's moves and whether the TM is still in the bag;
--   3. runs Falkner's TM31 script and logs what was said;
--   4. switches to a vanilla save and logs that the TM tables came back.
-- Run silently and isolated, with a disposable identity:
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_BACKGROUND=1 POKEPORT_VERSION=crystal
--   POKEPORT_GAME=crystal POKEPORT_IDENTITY=pocket-access-rand2-tms-<x>
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=launcher/mods/crystal_randomizer/tests/tms_driver.lua
--   "C:\Program Files\LOVE\lovec.exe" .
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local Runtime = require("src.mods.Runtime")
  local Screens = require("src.ui.Screens")
  local Mon = require("src.battle.gen2.Mon")
  local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
  local Tms = dofile("launcher/mods/crystal_randomizer/modules/tms.lua")

  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") return end
  U.log("RESULT", "start", L.where())
  local data = game.data
  local vanillaTeaches = {}
  for id, def in pairs(data.items) do
    if type(def) == "table" and def.teaches then vanillaTeaches[id] = def.teaches end
  end

  local ctx = Fake.new({ seed = os.getenv("RAND_SEED") or "driver-seed",
    options = { tms = true, tms_compat = true, tms_reusable = true } })
  local mod = { game = game, hooks = {
    wrap = function(_, name, fn) return Runtime.hooks:wrap(name, fn, 0, "crystal_randomizer_driver") end,
  } }
  Tms.install(mod, ctx)
  ctx.setActive(true)
  for _, line in ipairs(ctx.lines) do U.log("MODLOG", line) end

  -- A level 5 CYNDAQUIL (fewer than four moves) and a TM it may now learn.
  local mon = Mon.new(data, "CYNDAQUIL", 5)
  game.save.party = { mon }
  local learnable = {}
  for _, m in ipairs(data.pokemon.CYNDAQUIL.tmhm) do learnable[m] = true end
  local tms = Tms.machines(data.items)
  local tm
  for _, entry in ipairs(tms) do
    if learnable[entry.def.teaches] and not tm then tm = entry end
  end
  if not tm then U.log("FAIL", "CYNDAQUIL learns no TM in this seed") return end
  local newMove = data.moves[tm.def.teaches]
  U.log("RESULT", "TM", tm.id, tm.def.tmLabel, "vanilla", vanillaTeaches[tm.id], "now", tm.def.teaches,
    "(" .. tostring(newMove.name) .. ")")
  local known = {}
  for _, m in ipairs(mon.moves or {}) do known[#known + 1] = m.id end
  U.log("RESULT", "CYNDAQUIL knows", table.concat(known, ","))
  game.save.inventory = game.save.inventory or {}
  game.save.inventory[tm.id] = 1

  -- 1. The PACK's TM pocket.
  L.heard()
  local pack = Screens.push(game, "Gen2PackMenu", { pocket = "TM_HM",
    onClose = function() game.stack:pop() end,
    onChoose = function(itemId) game:useFieldItem(itemId) end })
  L.wait(30)
  for _ = 1, 60 do
    local row = pack.rows[pack.index]
    if row and row.id == tm.id then break end
    L.tap("down", 10)
  end
  local row = pack.rows[pack.index]
  U.log("RESULT", "pack row", row and row.id or "none", "draws", tostring(row and row.tmhmLabel),
    tostring(row and row.teaches), "description", tostring(pack.description and pack:description()))
  local speech = L.heard()
  U.log("RESULT", "pack speech =>", speech)
  U.log("RESULT", "pack speech names the new move",
    speech:upper():find(tostring(newMove.name):upper(), 1, true) and "YES" or "NO",
    "names the vanilla move", speech:upper():find(
      tostring(data.moves[vanillaTeaches[tm.id]].name):upper(), 1, true) and "YES" or "NO")

  -- 2. Teach it: A on the row, then A on CYNDAQUIL, then through the text.
  L.tap("a", 20)
  for _ = 1, 30 do
    local top = game.stack:top()
    if top and top ~= pack and top.save then break end
    L.wait(1)
  end
  U.log("RESULT", "teach screen", tostring(game.stack:top() ~= pack))
  L.tap("a", 30)
  for _ = 1, 120 do
    if game.stack:top() == pack or game.stack:top() == nil then break end
    L.tap("a", 10)
  end
  local after = {}
  local learned = false
  for _, m in ipairs(mon.moves or {}) do
    after[#after + 1] = m.id
    if m.id == tm.def.teaches then learned = true end
  end
  U.log("RESULT", "after teaching, CYNDAQUIL knows", table.concat(after, ","), "learned",
    learned and "YES" or "NO", "TM left in bag", tostring(game.save.inventory[tm.id]))
  U.log("RESULT", "teach speech =>", L.heard())
  while game.stack:top() do game.stack:pop() end
  L.settle(200, true)

  -- 3. Falkner's TM31 script (the list that shows "TM31 contains ...").
  local falknerList
  for key, list in pairs(data.gen2Scripts or {}) do
    for _, cmd in ipairs(type(list) == "table" and list or {}) do
      if type(cmd) == "table" and cmd.text == "1a:4648" then falknerList = key end
    end
  end
  local tm31 = data.items.TM_MUD_SLAP
  if falknerList and tm31 then
    L.heard()
    game.world.vm:start(falknerList)
    for _ = 1, 600 do
      if L.free() then break end
      if game.stack:top() ~= nil or not L.free() then L.tap("a", 8) else U.wait(1) end
    end
    L.settle(300, true)
    local said = L.heard()
    U.log("RESULT", "Falkner list", falknerList, "TM31 now", tm31.teaches)
    U.log("RESULT", "Falkner speech =>", said)
    U.log("RESULT", "Falkner names the new move",
      said:find(data.moves[tm31.teaches].name, 1, true) and "YES" or "NO",
      "names MUD-SLAP", said:find("MUD-SLAP", 1, true) and "YES" or "NO")
  else
    U.log("RESULT", "Falkner list not found")
  end

  -- 4. A vanilla save.
  ctx.setActive(false)
  local same = true
  for id, move in pairs(vanillaTeaches) do
    if data.items[id].teaches ~= move then same = false end
  end
  U.log("RESULT", "vanilla save: TM contents restored", same and "YES" or "NO",
    "consumeItem instance field", tostring(rawget(game, "consumeItem")))
  U.log("RESULT", "done")
end
