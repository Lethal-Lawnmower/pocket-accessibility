-- In-game check for modules/evolutions.lua on Crystal: installs the module
-- with a fake ctx (the randomizer core is not needed), makes the save
-- randomized with "trade evolutions without trading" on, then
--   1. gives a level 36 KADABRA a RARE CANDY through the field PACK path and
--      lets the evolution screen run (expected: ALAKAZAM at level 37);
--   2. opens the PACK, logs its submenu for METAL COAT, chooses it on an ONIX
--      the way USE does, and lets the evolution screen run (expected: STEELIX,
--      METAL COAT spent);
-- then makes the save vanilla again and repeats both (expected: no
-- evolution, METAL COAT unusable again).  Logs `[driver]` lines.
-- Run only through the isolated wrapper, silently, in a disposable identity:
--   POKEPORT_IDENTITY=pocket-access-rand2-evo-<x> POKEPORT_ACCESS_SILENT=1
--   POKEPORT_BACKGROUND=1 POKEPORT_VERSION=crystal POKEPORT_GAME=crystal
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=launcher/mods/crystal_randomizer/tests/evolutions_driver.lua
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
  local Module = dofile("launcher/mods/crystal_randomizer/modules/evolutions.lua")
  local Mon = require("src.battle.gen2.Mon")
  local ItemEffects = require("src.core.gen2.ItemEffects")

  local function className(state)
    if state == nil then return "overworld" end
    local mt = getmetatable(state)
    for name, mod in pairs(package.loaded) do
      if mod == mt and type(name) == "string" then return (name:gsub("^src%.ui%.", "")) end
    end
    return tostring(mt)
  end
  local function top() return game.stack:top() end
  local function waitFor(name, limit)
    for _ = 1, limit or 300 do
      if className(top()) == name then return true end
      U.wait(1)
    end
    U.log("FAIL", "never reached", name, "top", className(top()))
    return false
  end
  -- A through every text box and the evolution screen until the world is free.
  local function finish(limit)
    local seen = {}
    for _ = 1, limit or 3000 do
      if top() == nil then break end
      local name = className(top())
      if not seen[name] then seen[name] = true U.log("SCREEN", name) end
      L.tap("a", 10)
    end
    return top() == nil
  end

  if not L.settle(4000, true) then U.log("FAIL", "never reached the free world") love.event.quit() return end
  local data, save = game.data, game.save
  U.log("MAP", L.where())
  U.log("BEFORE", "gen2ItemEffects", type(data.gen2ItemEffects),
    "METAL_COAT fieldMenu", tostring(data.items.METAL_COAT.fieldMenu),
    "partyAction", tostring(ItemEffects.partyAction("METAL_COAT", data)))

  local function rows(species)
    local out = {}
    for _, row in ipairs(data.pokemon[species].evolutions or {}) do
      out[#out + 1] = row.method .. "/" .. tostring(row.level or row.item or "") .. "/" .. row.into
    end
    return table.concat(out, " ")
  end

  local function candyOn(label, species, level)
    local mon = assert(Mon.new(data, species, level))
    save.party = { mon }
    save.inventory = save.inventory or {}
    save.inventory.RARE_CANDY = 1
    L.heard()
    game:useFieldItem("RARE_CANDY")
    if not waitFor("gen2.PartyMenu") then return end
    U.wait(20)
    L.tap("a", 20)
    finish()
    local now = save.party[1]
    U.log(label, "RARE CANDY on", species, level, "->", now.species, "level", now.level)
    U.log(label, "heard", L.heard())
  end

  local function coatOn(label, species, level)
    local mon = assert(Mon.new(data, species, level))
    save.party = { mon }
    save.inventory = save.inventory or {}
    save.inventory.METAL_COAT = 1
    game:openStartMenuItem("pack")
    if not waitFor("gen2.PackMenu") then return end
    U.wait(20)
    local pack = top()
    local found
    for _ = 1, 4 do
      for i, row in ipairs(pack.rows or {}) do
        if row.id == "METAL_COAT" then found = i end
      end
      if found then break end
      pack:switchPocket(1)
      U.wait(5)
    end
    if not found then U.log("FAIL", "METAL_COAT not in the pack") finish() return end
    pack.index = found
    U.log(label, "pack submenu for METAL_COAT", table.concat(pack:submenuRows("METAL_COAT"), ","))
    L.heard()
    pack:useSelected()   -- what choosing USE does
    U.wait(20)
    U.log(label, "after USE top", className(top()), "heard", L.heard())
    if className(top()) == "gen2.PartyMenu" then
      L.tap("a", 20)
    end
    finish()
    local now = save.party[1]
    U.log(label, "METAL COAT on", species, "->", now.species, "level", now.level,
      "METAL_COAT left", tostring(save.inventory.METAL_COAT))
    U.log(label, "heard", L.heard())
  end

  local options = { evolutions_trade = true }
  local ctx = Fake.new({ seed = "driver-seed", options = options })
  Module.install({ game = game }, ctx)
  ctx.setActive(true, "driver-seed", options)
  for _, line in ipairs(ctx.lines) do U.log("MODLOG", line) end
  U.log("RANDOM", "KADABRA", rows("KADABRA"), "ONIX", rows("ONIX"), "SLOWPOKE", rows("SLOWPOKE"))
  U.log("RANDOM", "METAL_COAT fieldMenu", data.items.METAL_COAT.fieldMenu,
    "partyAction", tostring(ItemEffects.partyAction("METAL_COAT", data)))
  candyOn("RANDOM", "KADABRA", 36)
  coatOn("RANDOM", "ONIX", 20)

  ctx.setActive(false)
  for _, line in ipairs(ctx.lines) do U.log("MODLOG", line) end
  U.log("RESTORED", "KADABRA", rows("KADABRA"), "ONIX", rows("ONIX"),
    "gen2ItemEffects", type(data.gen2ItemEffects),
    "METAL_COAT fieldMenu", data.items.METAL_COAT.fieldMenu,
    "partyAction", tostring(ItemEffects.partyAction("METAL_COAT", data)))
  candyOn("RESTORED", "KADABRA", 36)
  coatOn("RESTORED", "ONIX", 20)
  U.log("DONE")
  love.event.quit()
end
