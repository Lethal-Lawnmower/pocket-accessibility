-- luajit launcher/mods/crystal_randomizer/tests/keyitems_test.lua   (from the repository root)
--
-- 1. The logic model alone: the vanilla game is beatable under it, and an
--    independent checker written here agrees with the module on all 5040
--    placements of the seven HMs.
-- 2. A small synthetic dataset shaped like Crystal's: many seeds, each one's
--    placement beatable (by the independent checker), deterministic, every
--    giving row and rewritten line naming the HM actually placed, and the
--    data exactly restored for a vanilla save.
-- 3. With CRYSTAL_RANDOMIZER_CACHE set to an imported cache's data/generated
--    folder, the same checks on the real Crystal maps, scripts and text.
-- KEYITEMS_SEEDS sets how many seeds each dataset runs (default 2000).
local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local K = dofile("launcher/mods/crystal_randomizer/modules/keyitems.lua")

local failures, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
  return cond
end
local function eq(a, b, msg) return ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local SEEDS = tonumber(os.getenv("KEYITEMS_SEEDS") or "") or 2000

-- ------------------------------------------------------------ an independent checker
-- Written apart from M.sweep on purpose: one site or step at a time, in a
-- worklist, with the needs parsed differently.  It reads only the model's
-- tables, so a slip in the module's own sweep shows up as a disagreement.
local function independentBeatable(placement)
  local nodes = {}
  for _, ev in ipairs(K.EVENTS) do nodes[#nodes + 1] = { id = ev.id, needs = ev.needs } end
  for _, s in ipairs(K.SITES) do nodes[#nodes + 1] = { id = s.id, needs = s.needs, gives = placement[s.id] } end
  local reached, bag = {}, {}
  local progress = true
  while progress do
    progress = false
    for _, node in ipairs(nodes) do
      if not reached[node.id] then
        local open = true
        for _, need in ipairs(node.needs) do
          local colon = need:find(":", 1, true)
          if colon then
            local kind, item = need:sub(1, colon - 1), need:sub(colon + 1)
            if not bag[item] then open = false end
            if kind == "use" and not reached[K.FIELD_MOVES[item].badge] then open = false end
          elseif not reached[need] then
            open = false
          end
        end
        if open then
          reached[node.id] = true
          if node.gives then bag[node.gives] = true end
          progress = true
        end
      end
    end
  end
  for _, node in ipairs(nodes) do if not reached[node.id] then return false end end
  return true
end

local function placementString(p)
  local parts = {}
  for _, s in ipairs(K.SITES) do parts[#parts + 1] = s.id .. "=" .. tostring(p[s.id]) end
  return table.concat(parts, " ")
end

-- ------------------------------------------------------------ 1. the model
do
  local defined = {}
  for _, ev in ipairs(K.EVENTS) do
    ok(not defined[ev.id], "step defined once: " .. ev.id)
    defined[ev.id] = true
  end
  local pool = {}
  for _, s in ipairs(K.SITES) do
    ok(K.FIELD_MOVES[s.item] ~= nil, "pool item is a field-move HM: " .. s.item)
    ok(not pool[s.item], "pool item once: " .. s.item)
    pool[s.item] = true
  end
  for _, list in ipairs({ K.EVENTS, K.SITES }) do
    for _, node in ipairs(list) do
      for _, need in ipairs(node.needs) do
        local kind, item = need:match("^(%a+):(.+)$")
        if kind then
          ok((kind == "item" or kind == "use") and pool[item], node.id .. " needs a pool HM: " .. need)
        else
          ok(defined[need], node.id .. " needs a defined step: " .. need)
        end
      end
    end
  end
  for id, field in pairs(K.FIELD_MOVES) do ok(defined[field.badge], id .. "'s badge is a step") end
  ok(defined[K.GOAL], "the goal is a step")

  ok(K.beatable(K.vanillaPlacement()), "the vanilla game is beatable under the model")
  ok(independentBeatable(K.vanillaPlacement()), "independent checker: vanilla beatable")

  local total, agree, valid = 0, 0, 0
  local where = {}
  K.eachPlacement(function(p)
    total = total + 1
    local a, b = K.beatable(p), independentBeatable(p)
    if a == b then agree = agree + 1 else print("  disagree: " .. placementString(p)) end
    if a then
      valid = valid + 1
      for site, item in pairs(p) do
        where[item] = where[item] or {}
        where[item][site] = true
      end
    end
  end)
  eq(total, 5040, "every permutation of seven HMs is tried")
  eq(agree, total, "the module and the independent checker agree on every placement")
  eq(#K.validPlacements(), valid, "validPlacements lists exactly the beatable ones")
  ok(valid > 1, "more than one beatable placement")
  print(string.format("  model: %d of %d placements beatable", valid, total))
  for _, s in ipairs(K.SITES) do
    local spots = {}
    for site in pairs(where[s.item] or {}) do spots[#spots + 1] = site end
    table.sort(spots)
    print(string.format("  %-12s can be found at %d: %s", s.item, #spots, table.concat(spots, ", ")))
  end
  -- known strandings must be refused
  local p = K.vanillaPlacement()
  p.ICE_PATH_1F, p.ILEX_FOREST = "HM_CUT", "HM_WATERFALL"
  ok(not K.beatable(p), "CUT behind the Ice Path is refused")
  p = K.vanillaPlacement()
  p.CIANWOOD_CITY, p.DANCE_THEATER = "HM_SURF", "HM_FLY"
  ok(not K.beatable(p), "SURF in Cianwood (reached by SURF) is refused")
  p = K.vanillaPlacement()
  p.CIANWOOD_CITY, p.OLIVINE_CAFE = "HM_STRENGTH", "HM_FLY"
  ok(not K.beatable(p), "STRENGTH behind Chuck's boulders is refused")
  for _, vp in ipairs(K.validPlacements()) do
    local seen = {}
    for _, s in ipairs(K.SITES) do seen[vp[s.id]] = (seen[vp[s.id]] or 0) + 1 end
    for _, s in ipairs(K.SITES) do
      if seen[s.item] ~= 1 then ok(false, "a valid placement holds each HM once") break end
    end
  end
end

-- ------------------------------------------------------------ data helpers
local function serialize(v, out)
  local t = type(v)
  if t ~= "table" then out[#out + 1] = t .. ":" .. tostring(v) return end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  out[#out + 1] = "{"
  for _, k in ipairs(keys) do
    out[#out + 1] = tostring(k) .. "="
    serialize(v[k], out)
  end
  out[#out + 1] = "}"
end
local function fingerprint(data)
  local out = {}
  serialize(data.gen2Maps, out)
  serialize(data.gen2Scripts, out)
  local text = {}
  for k, v in pairs(data.gen2Text) do
    if not tostring(k):find("^crystal_randomizer:") then text[k] = v end
  end
  serialize(text, out)
  return table.concat(out, " ")
end

local function syntheticData()
  local items, moves = {}, {}
  local index = 243
  for _, id in ipairs({ "HM_CUT", "HM_FLY", "HM_SURF", "HM_STRENGTH", "HM_FLASH", "HM_WHIRLPOOL",
      "HM_WATERFALL" }) do
    local move = K.FIELD_MOVES[id].move
    items[id] = { index = index, pocket = "TM_HM", canToss = false, name = "HM0" .. (index - 242),
      teaches = move }
    moves[move] = { name = move }
    index = index + 1
  end
  items.POTION = { index = 18, pocket = "ITEM", canToss = true, name = "POTION" }
  local maps, scripts, text = {}, {}, {}
  for _, site in ipairs(K.SITES) do
    local list = { { op = "faceplayer" }, { op = "opentext" } }
    for n, spec in ipairs(site.texts) do
      local key = site.id .. ":t" .. n
      text[key] = "Some words.\n" .. spec.find .. " and more\vwords.{DONE}"
      list[#list + 1] = { op = n == 1 and "writetext" or "jumptext", text = key }
    end
    if site.kind == "script" then
      table.insert(list, 3, { op = "verbosegiveitem", item = items[site.item].index, quantity = 1 })
      local key = site.id .. ":script"
      scripts[key] = list
      maps[site.map] = { objects = { { index = 1, sprite = "SPRITE_SAGE", scriptKey = key } } }
    else
      maps[site.map] = { objects = { { index = 1, sprite = "SPRITE_POKE_BALL",
        itemball = { item = items[site.item].index, quantity = 1 } } } }
    end
  end
  -- a decoy: another map giving SURF, which must not be taken for the Dance Theater's
  scripts["DECOY:script"] = { { op = "verbosegiveitem", item = items.HM_SURF.index, quantity = 1 } }
  maps.ROUTE_29 = { objects = { { index = 1, scriptKey = "DECOY:script" },
    { index = 2, itemball = { item = 18, quantity = 1 } } } }
  return { items = items, moves = moves, gen2Maps = maps, gen2Scripts = scripts, gen2Text = text }
end

-- A module installed on `data` with a fake ctx and a captured hook.
local function setup(data, seed, options)
  local ctx = Fake.new({ seed = seed, options = options })
  local wrapped
  local mod = { game = { data = data }, hooks = { wrap = function(_, name, fn)
    if name == "script.command" then wrapped = fn end
  end } }
  K.install(mod, ctx)
  ctx.setActive(seed ~= nil, seed, options)
  return ctx, wrapped
end

-- Runs one row through the hook as the VM would; returns the row it ran.
local function run(wrapped, list, index, textTable)
  local cmd = list[index]
  local vm = { cmdList = list, cmdIndex = index, text = textTable }
  return wrapped(function(_, _, _, row) return row end, { vm = vm }, cmd.op, cmd.args or {}, cmd)
end

local function byIndexOf(items)
  local out = {}
  for id, def in pairs(items) do if type(def) == "table" and def.index then out[def.index] = id end end
  return out
end

-- What the placed site actually gives and says, through the hook.
local function observe(data, found, wrapped)
  local byIndex = byIndexOf(data.items)
  local out = {}
  for _, site in ipairs(K.SITES) do
    local entry = found.sites[site.id]
    local seen = { lines = {} }
    if entry.give then
      local row = run(wrapped, entry.give.list, entry.give.index, data.gen2Text)
      seen.item = byIndex[row.item]
      if row.args then seen.argsItem = byIndex[row.args[1]] end
      -- every text row in the giving list and wherever the site's lines are
      for _, key in ipairs(K.mapScriptKeys(data.gen2Scripts, data.gen2Maps[site.map])) do
        local list = data.gen2Scripts[key]
        for i, cmd in ipairs(list) do
          if cmd.text and entry.texts[cmd.text] then
            local r = run(wrapped, list, i, data.gen2Text)
            seen.lines[#seen.lines + 1] = { spec = entry.texts[cmd.text], body = data.gen2Text[r.text] }
          end
        end
      end
    else
      seen.item = byIndex[entry.ball.item]
    end
    out[site.id] = seen
  end
  return out
end

local function suite(label, makeData, seeds)
  local data = makeData()
  local before = fingerprint(data)
  local found, why = K.discover(data)
  if not ok(found ~= nil, label .. ": every site found (" .. tostring(why) .. ")") then return end

  -- vanilla save and answered NO: nothing changes, and the hook runs cart rows
  for _, case in ipairs({ { nil, {} }, { "s1", { keyitems = false } } }) do
    local _, wrapped = setup(data, case[1], case[2])
    eq(fingerprint(data), before, label .. ": vanilla / NO leaves the data alone")
    local seen = observe(data, found, wrapped)
    for _, site in ipairs(K.SITES) do
      eq(seen[site.id].item, site.item, label .. ": vanilla gift at " .. site.id)
      for _, line in ipairs(seen[site.id].lines) do
        ok(line.body:find(line.spec.find, 1, true), label .. ": vanilla line kept at " .. site.id)
      end
    end
  end

  local beatable, distinct, moved, textOk, widthOk = 0, {}, 0, true, true
  local widest = 0
  local ctx, wrapped = setup(data, "seed-1", { keyitems = true })
  for n = 1, seeds do
    local seed = "seed-" .. n
    ctx.setActive(true, seed, { keyitems = true })
    local placement = ctx.shared.keyitems
    if not ok(type(placement) == "table", label .. ": placement published for " .. seed) then break end
    if independentBeatable(placement) then beatable = beatable + 1
    else ok(false, label .. ": seed " .. seed .. " beatable: " .. placementString(placement)) end
    distinct[placementString(placement)] = true
    local seen = observe(data, found, wrapped)
    for _, site in ipairs(K.SITES) do
      local item = placement[site.id]
      if item ~= site.item then moved = moved + 1 end
      local s = seen[site.id]
      if s.item ~= item then ok(false, ("%s: %s gives %s, placed %s"):format(label, site.id, tostring(s.item), item)) end
      if s.argsItem and s.argsItem ~= item then ok(false, label .. ": args agree at " .. site.id) end
      local field = K.FIELD_MOVES[item]
      local vanillaMove = K.FIELD_MOVES[site.item].move
      for _, line in ipairs(s.lines) do
        local body = line.body
        if type(body) ~= "string" then textOk = false; ok(false, label .. ": a line has no text at " .. site.id)
        elseif item ~= site.item then
          if line.spec.replace == "explain" then
            if not (body:find(data.items[item].name, 1, true) and body:find(field.move, 1, true)
                and body:find(field.badgeName, 1, true)) then
              textOk = false
              ok(false, label .. ": explanation names the placed HM at " .. site.id .. ": " .. body)
            end
          end
          if line.spec.replace:find("%MOVE%", 1, true) and not body:find(field.move, 1, true) then
            textOk = false
            ok(false, label .. ": offer names the placed move at " .. site.id .. ": " .. body)
          end
          -- the vanilla HM's move is not named (word boundaries: SURF in SURFACE does not count)
          local bare = body:gsub("{DONE}", "")
          for word in bare:gmatch("[%u]+") do
            if word == vanillaMove then
              textOk = false
              ok(false, label .. ": " .. site.id .. " still names " .. vanillaMove .. ": " .. body)
            end
          end
          local w = K.widestLine(body)
          if w > widest then widest = w end
          if w > 18 then widthOk = false; ok(false, label .. ": line wider than 18 at " .. site.id .. ": " .. body) end
        else
          if not body:find(line.spec.find, 1, true) then
            textOk = false
            ok(false, label .. ": a site keeping its HM keeps its line: " .. site.id)
          end
        end
      end
    end
  end
  eq(beatable, seeds, label .. ": every seed beatable")
  ok(textOk, label .. ": every gift and line names the HM given")
  ok(widthOk, label .. ": rewritten lines fit 18 characters")
  local count = 0
  for _ in pairs(distinct) do count = count + 1 end
  ok(count > 50, label .. ": seeds reach many placements (" .. count .. ")")
  ok(moved > seeds, label .. ": HMs move")
  print(string.format("  %s: %d seeds, all beatable, %d distinct placements, widest rewritten line %d",
    label, seeds, count, widest))

  -- determinism: a fresh copy of the data and a fresh install agree
  for _, seed in ipairs({ "seed-3", "seed-77", "123456", "999999" }) do
    ctx.setActive(true, seed, { keyitems = true })
    local a = placementString(ctx.shared.keyitems)
    local d2 = makeData()
    local ctx2 = setup(d2, seed, { keyitems = true })
    eq(placementString(ctx2.shared.keyitems), a, label .. ": same seed, same placement (" .. seed .. ")")
    eq(fingerprint(d2), fingerprint(data), label .. ": same seed, same data (" .. seed .. ")")
  end

  -- exact restore: a vanilla save, and NO, after randomized ones
  ctx.setActive(false)
  eq(fingerprint(data), before, label .. ": a vanilla save after randomized ones is exactly vanilla")
  local seen = observe(data, found, wrapped)
  for _, site in ipairs(K.SITES) do eq(seen[site.id].item, site.item, label .. ": restored gift at " .. site.id) end
  ctx.setActive(true, "seed-5", { keyitems = false })
  eq(fingerprint(data), before, label .. ": answered NO after a randomized save is exactly vanilla")
  ctx.setActive(true, "seed-5", { keyitems = true })
  local first = fingerprint(data)
  ctx.setActive(true, "seed-5", { keyitems = true })
  eq(fingerprint(data), first, label .. ": the same save reported twice does not stack")
  ctx.setActive(true, "seed-6", { keyitems = true })
  ctx.setActive(true, "seed-5", { keyitems = true })
  eq(fingerprint(data), first, label .. ": back to a save gives its placement again")
  ctx.setActive(false)
  eq(fingerprint(data), before, label .. ": restored at the end")
end

-- ------------------------------------------------------------ 2. synthetic data
suite("synthetic", syntheticData, SEEDS)

-- a site the data does not match: nothing changes at all
do
  local data = syntheticData()
  data.gen2Text["DANCE_THEATER:t1"] = "Something else.{DONE}"
  local before = fingerprint(data)
  local ctx = setup(data, "seed-1", { keyitems = true })
  eq(fingerprint(data), before, "an unmatched line leaves everything vanilla")
  eq(ctx.shared.keyitems, nil, "and publishes no placement")
  local logged = table.concat(ctx.lines, " | ")
  ok(logged:find("not shuffled", 1, true), "and says so in the log: " .. logged)
end
do
  local data = syntheticData()
  data.items.HM_SURF.teaches = "TACKLE"
  local before = fingerprint(data)
  local ctx = setup(data, "seed-1", { keyitems = true })
  eq(fingerprint(data), before, "an HM teaching another move leaves everything vanilla")
  eq(ctx.shared.keyitems, nil, "and publishes no placement")
end

-- ------------------------------------------------------------ 3. real Crystal data
local cache = os.getenv("CRYSTAL_RANDOMIZER_CACHE")
if cache and cache ~= "" then
  local function realData()
    return { items = dofile(cache .. "/items.lua"), moves = dofile(cache .. "/moves.lua"),
      gen2Maps = dofile(cache .. "/maps.lua"), gen2Scripts = dofile(cache .. "/scripts.lua"),
      gen2Text = dofile(cache .. "/text.lua") }
  end
  local data = realData()
  local found, why = K.discover(data)
  if ok(found ~= nil, "real data: every site found (" .. tostring(why) .. ")") then
    for _, site in ipairs(K.SITES) do
      local e = found.sites[site.id]
      local keys = {}
      for k in pairs(e.texts) do keys[#keys + 1] = k end
      table.sort(keys)
      print(string.format("  real %-21s %-13s %s  lines %s", site.id, site.item,
        e.give and (e.give.key .. " row " .. e.give.index) or "item ball", table.concat(keys, ",")))
    end
  end
  suite("real data", realData, SEEDS)
  print("real Crystal data checked: " .. cache)
end

print(string.format("keyitems_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
