-- Test for modules/tms.lua (TM contents, TM compatibility, reusable TMs).
--   luajit launcher/mods/crystal_randomizer/tests/tms_test.lua
-- With CRYSTAL_DATA_DIR pointing at an imported Crystal's data/generated
-- folder (pokemon.lua, moves.lua, items.lua, scripts.lua, text.lua; never
-- committed), the same checks also run on the real game data.
local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Module = dofile("launcher/mods/crystal_randomizer/modules/tms.lua")

local failures, checks = 0, 0
local function check(ok, fmt, ...)
  checks = checks + 1
  if not ok then
    failures = failures + 1
    print("FAIL " .. (select("#", ...) > 0 and fmt:format(...) or fmt))
  end
  return ok
end

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = deepCopy(v) end
  return out
end
local function deepEqual(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- ------------------------------------------------------------ questions

for _, q in ipairs(Module.questions) do
  check(q.recommended ~= nil and q.everything ~= nil, "%s carries recommended and everything", q.key)
  local lines = {}
  for line in (q.text .. "\n"):gmatch("(.-)[\n\v\f]") do lines[#lines + 1] = line end
  check(#lines <= 2, "%s fits two lines", q.key)
  for _, line in ipairs(lines) do check(#line <= 18, "%s line '%s' is at most 18", q.key, line) end
end

-- ------------------------------------------------------- synthetic data

local function syntheticData(order)
  local moveList = {
    { "TACKLE", "NORMAL", 35 }, { "HEADBUTT", "NORMAL", 70 }, { "ROCK_SMASH", "FIGHTING", 20 },
    { "MUD_SLAP", "GROUND", 20 }, { "TOXIC", "POISON", 0 }, { "PROTECT", "NORMAL", 0 },
    { "EMBER", "FIRE", 40 }, { "FLAMETHROWER", "FIRE", 95 }, { "WATER_GUN", "WATER", 40 },
    { "BUBBLEBEAM", "WATER", 65 }, { "GROWL", "NORMAL", 0 }, { "SUNNY_DAY", "FIRE", 0 },
    { "RAIN_DANCE", "WATER", 0 }, { "THUNDERSHOCK", "ELECTRIC", 40 }, { "AGILITY", "PSYCHIC_TYPE", 0 },
    { "CONFUSION", "PSYCHIC_TYPE", 50 }, { "CUT", "NORMAL", 50 }, { "SURF", "WATER", 95 },
    { "STRUGGLE", "NORMAL", 50 }, { "SPLASH", "NORMAL", 0 }, { "SCREECH", "NORMAL", 0 },
    { "PECK", "FLYING", 35 },
  }
  local moves = { generation = 2, source = "synthetic" }
  for i, m in ipairs(moveList) do
    moves[m[1]] = { id = m[1], index = i, type = m[2], power = m[3], name = (m[1]:gsub("_", "-")) }
  end
  moves.MUD_SLAP.name = "MUD-SLAP"
  moves.ROCK_SMASH.name = "ROCK SMASH"
  local items = {
    POTION = { id = "POTION", index = 18, pocket = "ITEM", name = "POTION" },
  }
  local machines = { { "TM_HEADBUTT", "HEADBUTT" }, { "TM_ROCK_SMASH", "ROCK_SMASH" },
    { "TM_MUD_SLAP", "MUD_SLAP" }, { "TM_TOXIC", "TOXIC" }, { "TM_PROTECT", "PROTECT" },
    { "TM_FLAMETHROWER", "FLAMETHROWER" } }
  for i, m in ipairs(machines) do
    local label = ("TM%02d"):format(i)
    items[m[1]] = { id = m[1], index = 190 + i, pocket = "TM_HM", teaches = m[2], tmNumber = i,
      tmLabel = label, name = label }
  end
  items.HM_CUT = { id = "HM_CUT", index = 243, pocket = "TM_HM", teaches = "CUT", tmNumber = 7,
    tmLabel = "HM01", name = "HM01", canToss = false }
  items.HM_SURF = { id = "HM_SURF", index = 245, pocket = "TM_HM", teaches = "SURF", tmNumber = 8,
    tmLabel = "HM02", name = "HM02", canToss = false }
  local defs = {
    CHAR = { types = { "FIRE", "FIRE" }, tmhm = { "HEADBUTT", "TOXIC", "PROTECT", "FLAMETHROWER", "CUT" } },
    SQUIRT = { types = { "WATER", "WATER" }, tmhm = { "HEADBUTT", "ROCK_SMASH", "TOXIC", "SURF" } },
    PIKA = { types = { "ELECTRIC", "ELECTRIC" }, tmhm = { "HEADBUTT", "MUD_SLAP", "TOXIC", "PROTECT" } },
    KARP = { types = { "WATER", "WATER" }, tmhm = {} },
    BIRD = { types = { "NORMAL", "FLYING" }, tmhm = { "TOXIC", "PROTECT", "CUT" } },
    ONIX = { types = { "ROCK", "GROUND" }, tmhm = { "HEADBUTT", "ROCK_SMASH", "MUD_SLAP", "TOXIC", "CUT" } },
  }
  local pokemon = { tmhmMoves = { "HEADBUTT", "ROCK_SMASH", "MUD_SLAP", "TOXIC", "PROTECT",
    "FLAMETHROWER", "CUT", "SURF", "BUBBLEBEAM" }, tutorMoves = { "BUBBLEBEAM" }, growthRates = {} }
  local names = {}
  for name in pairs(defs) do names[#names + 1] = name end
  table.sort(names)
  if order == "reverse" then
    for i = 1, math.floor(#names / 2) do names[i], names[#names + 1 - i] = names[#names + 1 - i], names[i] end
  end
  for i, name in ipairs(names) do
    local def = defs[name]
    def.id, def.name, def.index = name, name, i
    def.levelMoves = { { level = 1, move = "TACKLE" } }
    pokemon[name] = def
  end
  local text = {
    ["01:0001"] = "That's TM03.\nIt's MUD-SLAP!{DONE}",
    ["01:0002"] = "It's FLAMETHROWER.\nHot!{DONE}",
    ["01:0003"] = "FLAMETHROWER is a\nmove.{DONE}",
    ["01:0004"] = "A MUD-SLAPPER and\nPROTECTOR.{DONE}",
  }
  local scripts = {
    ["01:1000"] = { { op = "writetext", text = "01:0002" }, { op = "verbosegiveitem", item = 196, quantity = 1 },
      { op = "end" } },
    ["01:2000"] = { { op = "jumptext", text = "01:0003" } },
    ["01:3000"] = { { op = "writetext", text = "01:0004" }, { op = "giveitem", item = 18 } },
  }
  return { moves = moves, items = items, pokemon = pokemon, gen2Text = text, gen2Scripts = scripts }
end

local function realData()
  local dir = os.getenv("CRYSTAL_DATA_DIR")
  if not dir or dir == "" then return nil end
  local data = {}
  for field, file in pairs({ pokemon = "pokemon.lua", moves = "moves.lua", items = "items.lua",
      gen2Scripts = "scripts.lua", gen2Text = "text.lua" }) do
    local ok, value = pcall(dofile, dir .. "/" .. file)
    if not check(ok and type(value) == "table", "real %s loads: %s", file, tostring(value)) then return nil end
    data[field] = value
  end
  return data
end

-- ---------------------------------------------------------- the checks

local OWNED = { "items", "tmhm", "tmhmMoves" }
local function ownedView(data)
  local view = { teaches = {}, tmhm = {}, tmhmMoves = deepCopy(data.pokemon.tmhmMoves) }
  for id, def in pairs(data.items) do if type(def) == "table" and def.teaches then view.teaches[id] = def.teaches end end
  for id, def in pairs(data.pokemon) do
    if type(def) == "table" and type(def.tmhm) == "table" and def.types then view.tmhm[id] = deepCopy(def.tmhm) end
  end
  return view
end
local function hmSet(data)
  local set = {}
  for id, def in pairs(data.items) do
    if type(def) == "table" and def.teaches and id:sub(1, 3) == "HM_" then set[def.teaches] = true end
  end
  return set
end

local function runSuite(label, makeData)
  local data = makeData()
  local moves = data.moves
  local vanilla = ownedView(data)
  local refs = { tmhmMoves = data.pokemon.tmhmMoves, tmhm = {}, types = {}, levelMoves = {} }
  for id, def in pairs(data.pokemon) do
    if type(def) == "table" and def.tmhm and def.types then
      refs.tmhm[id], refs.types[id], refs.levelMoves[id] = def.tmhm, def.types, def.levelMoves
    end
  end
  local vanillaText = deepCopy(data.gen2Text)
  local hms = hmSet(data)
  local tms = Module.machines(data.items)
  local tmCount = #tms

  local all = { tms = true, tms_compat = true, tms_reusable = true }
  local ctx = Fake.new({ seed = "1234", options = all })
  local state = {}

  -- A vanilla save changes nothing.
  ctx.setActive(false)
  Module.apply(data, ctx, state)
  check(deepEqual(ownedView(data), vanilla), "%s: a vanilla save keeps vanilla TMs", label)
  check(data.pokemon.tmhmMoves == refs.tmhmMoves, "%s: vanilla tmhmMoves is the same table", label)

  -- Everything on.
  ctx.setActive(true, "1234", all)
  Module.apply(data, ctx, state)
  local first = ownedView(data)
  local seen, changed = {}, 0
  for _, tm in ipairs(tms) do
    local move = tm.def.teaches
    check(moves[move] ~= nil, "%s: %s teaches a real move", label, tm.id)
    check(not seen[move], "%s: %s's move %s is not on another TM", label, tm.id, tostring(move))
    check(not hms[move], "%s: %s does not teach an HM move", label, tm.id)
    check(move ~= "STRUGGLE", "%s: %s does not teach STRUGGLE", label, tm.id)
    local vanillaMove = vanilla.teaches[tm.id]
    check(Module.isDamaging(moves[move]) == Module.isDamaging(moves[vanillaMove]),
      "%s: %s keeps its kind (%s -> %s)", label, tm.id, vanillaMove, tostring(move))
    if move ~= vanillaMove then changed = changed + 1 end
    seen[move] = true
  end
  check(changed >= math.floor(tmCount / 2), "%s: most TMs changed (%d of %d)", label, changed, tmCount)
  for _, keep in ipairs({ "HEADBUTT", "ROCK_SMASH" }) do
    local wasTm = false
    for _, tm in ipairs(tms) do if vanilla.teaches[tm.id] == keep then wasTm = true end end
    if wasTm then check(seen[keep], "%s: %s is still taught by some TM", label, keep) end
  end
  for id, def in pairs(data.items) do
    if type(def) == "table" and def.teaches and id:sub(1, 3) == "HM_" then
      check(def.teaches == vanilla.teaches[id], "%s: %s still teaches %s", label, id, vanilla.teaches[id])
    end
  end
  for i = tmCount + 1, #vanilla.tmhmMoves do
    check(data.pokemon.tmhmMoves[i] == vanilla.tmhmMoves[i], "%s: tmhmMoves[%d] (HM/tutor) unchanged", label, i)
  end
  for _, tm in ipairs(tms) do
    check(data.pokemon.tmhmMoves[tm.number] == tm.def.teaches, "%s: tmhmMoves[%d] follows the TM", label, tm.number)
  end

  -- Compatibility: counts kept, HMs kept, every move taught by a TM or HM.
  local users = {}
  local taught = {}
  for _, tm in ipairs(tms) do taught[tm.def.teaches] = tm.number end
  local sameType, total = 0, 0
  for id, def in pairs(data.pokemon) do
    if refs.tmhm[id] then
      local vTm, vHm, nTm, nHm = 0, {}, 0, {}
      for _, m in ipairs(vanilla.tmhm[id]) do if hms[m] then vHm[#vHm + 1] = m else vTm = vTm + 1 end end
      for _, m in ipairs(def.tmhm) do
        if hms[m] then nHm[#nHm + 1] = m
        else
          nTm = nTm + 1
          check(taught[m] ~= nil, "%s: %s's %s is taught by a TM", label, id, m)
          if taught[m] then users[taught[m]] = (users[taught[m]] or 0) + 1 end
          total = total + 1
          local mt = moves[m] and moves[m].type
          if mt == def.types[1] or mt == def.types[2] then sameType = sameType + 1 end
        end
      end
      check(nTm == vTm, "%s: %s keeps %d TMs (has %d)", label, id, vTm, nTm)
      check(deepEqual(nHm, vHm), "%s: %s keeps its HM compatibility", label, id)
      check(def.types == refs.types[id] and def.levelMoves == refs.levelMoves[id],
        "%s: %s types and levelMoves untouched", label, id)
    end
  end
  for _, tm in ipairs(tms) do check((users[tm.number] or 0) >= 1, "%s: %s has a learner", label, tm.id) end

  -- Determinism: the same seed again, from a fresh state, and in another order.
  local again = makeData("reverse")
  local stateB = {}
  local ctxB = Fake.new({ seed = "1234", options = all })
  ctxB.setActive(true)
  Module.apply(again, ctxB, stateB)
  check(deepEqual(ownedView(again), first), "%s: same seed, same TMs (fresh data, other order)", label)
  ctx.setActive(true, "9999", all)
  Module.apply(data, ctx, state)
  check(not deepEqual(ownedView(data), first), "%s: another seed gives other TMs", label)
  ctx.setActive(true, "1234", all)
  Module.apply(data, ctx, state)
  check(deepEqual(ownedView(data), first), "%s: switching back gives the same TMs", label)

  -- Contents only: compatibility follows the TM number.
  ctx.setActive(true, "1234", { tms = true })
  Module.apply(data, ctx, state)
  local numberOf = {}
  for _, tm in ipairs(tms) do numberOf[vanilla.teaches[tm.id]] = tm.number end
  for id, def in pairs(data.pokemon) do
    if refs.tmhm[id] then
      local want = {}
      for _, m in ipairs(vanilla.tmhm[id]) do
        if not hms[m] then want[#want + 1] = data.pokemon.tmhmMoves[numberOf[m]] end
      end
      for _, m in ipairs(vanilla.tmhm[id]) do if hms[m] then want[#want + 1] = m end end
      check(deepEqual(def.tmhm, want), "%s: contents only, %s learns the same TM numbers", label, id)
    end
  end

  -- Compatibility only: the TMs teach the cart's moves.
  ctx.setActive(true, "1234", { tms_compat = true })
  Module.apply(data, ctx, state)
  local compatOnly = ownedView(data)
  check(deepEqual(compatOnly.teaches, vanilla.teaches), "%s: compatibility only keeps contents", label)
  check(not deepEqual(compatOnly.tmhm, vanilla.tmhm), "%s: compatibility only changes learners", label)

  -- Text: rewritten when it names a given TM's move or a TM label.
  ctx.setActive(true, "1234", all)
  Module.apply(data, ctx, state)
  local rewrites = state.rewrites or {}
  local byLabel, byMove = {}, {}
  for _, tm in ipairs(tms) do byLabel[tm.def.tmLabel] = tm end
  local textCount = 0
  for key, r in pairs(rewrites) do
    textCount = textCount + 1
    check(vanillaText[key] ~= nil and r.body ~= vanillaText[key], "%s: text %s rewritten", label, key)
    check(data.gen2Text[key] == vanillaText[key], "%s: vanilla text %s untouched", label, key)
  end
  if label == "synthetic" then
    local tm3, tm6 = data.items.TM_MUD_SLAP.teaches, data.items.TM_FLAMETHROWER.teaches
    local r1, r2 = rewrites["01:0001"], rewrites["01:0002"]
    check(r1 and r1.body:find(moves[tm3].name, 1, true) and not r1.body:find("MUD-SLAP", 1, true),
      "synthetic: 'TM03 ... MUD-SLAP' names %s: %s", tm3, r1 and r1.body or "nil")
    check(r2 and r2.body:find(moves[tm6].name, 1, true) and not r2.body:find("FLAMETHROWER", 1, true),
      "synthetic: the giving script's text names %s: %s", tm6, r2 and r2.body or "nil")
    check(rewrites["01:0003"] == nil, "synthetic: a text outside any TM context is left alone")
    check(rewrites["01:0004"] == nil, "synthetic: a script giving a POTION is left alone")
    check(Module.replaceNames("A MUD-SLAPPER, MUD-SLAP!", { ["MUD-SLAP"] = "X" }) == "A MUD-SLAPPER, X!",
      "synthetic: whole words only")
    check(Module.replaceNames("A B", { A = "B", B = "A" }) == "B A", "synthetic: one-pass swaps")
    -- the hook path
    local vmText = deepCopy(vanillaText)
    local added = {}
    local cmd = { op = "writetext", text = "01:0002" }
    local row = Module.rewriteRow(cmd, rewrites, vmText, added)
    check(row and row ~= cmd and vmText[row.text] == r2.body and cmd.text == "01:0002",
      "synthetic: the hook runs a copy of the row with the new text")
    check(Module.rewriteRow({ op = "writetext", text = "01:0003" }, rewrites, vmText, added) == nil,
      "synthetic: the hook leaves other rows alone")
    state.addedText = { { data.gen2Text, "x:added" } }
    data.gen2Text["x:added"] = "x"
  end
  if label == "crystal" then
    print(("crystal: %d texts renamed, %d TM moves changed, same-type share %d/%d"):format(
      textCount, changed, sameType, total))
    for _, key in ipairs({ "1a:4648", "15:4302", "63:6efa" }) do
      if rewrites[key] then print("  " .. key .. ": " .. (rewrites[key].body:gsub("%c", " / "))) end
    end
    check(textCount >= 20, "crystal: at least 20 TM texts renamed (%d)", textCount)
    local sample = {}
    for _, tm in ipairs(tms) do
      if tm.number <= 6 then sample[#sample + 1] = tm.def.tmLabel .. " " .. vanilla.teaches[tm.id] .. ">" .. tm.def.teaches end
    end
    print("  seed 1234: " .. table.concat(sample, ", "))
  end

  -- Restore: exact, by reference, and added text removed.
  ctx.setActive(false)
  Module.apply(data, ctx, state)
  check(deepEqual(ownedView(data), vanilla), "%s: restore gives vanilla values", label)
  check(data.pokemon.tmhmMoves == refs.tmhmMoves, "%s: restore puts back the tmhmMoves table", label)
  for id, t in pairs(refs.tmhm) do
    check(data.pokemon[id].tmhm == t, "%s: restore puts back %s's tmhm table", label, id)
  end
  check(deepEqual(data.gen2Text, vanillaText), "%s: restore leaves the text table as the cart's", label)
end

-- ----------------------------------------------------------- reusable

local function reusableSuite()
  local data = syntheticData()
  local consumed = {}
  local Class = { consumeItem = function(self, id) consumed[#consumed + 1] = id end }
  Class.__index = Class
  local game = setmetatable({ data = data }, Class)
  local ctx = Fake.new({ seed = "1", options = { tms_reusable = true } })
  local state = {}
  ctx.setActive(true)
  check(Module.installReusable(game, ctx, state), "reusable: installs on an active save")
  game:consumeItem("TM_TOXIC")
  game:consumeItem("HM_CUT")
  game:consumeItem("POTION")
  check(deepEqual(consumed, { "HM_CUT", "POTION" }), "reusable: a TM is kept, other items pass (%s)",
    table.concat(consumed, ","))
  ctx.setActive(true, "1", { tms_reusable = false })
  Module.installReusable(game, ctx, state)
  check(rawget(game, "consumeItem") == nil, "reusable: off puts the class method back")
  consumed = {}
  game:consumeItem("TM_TOXIC")
  check(deepEqual(consumed, { "TM_TOXIC" }), "reusable: off, a TM is used up")
  ctx.setActive(true, "1", { tms_reusable = true })
  Module.installReusable(game, ctx, state)
  ctx.setActive(false)
  Module.installReusable(game, ctx, state)
  check(rawget(game, "consumeItem") == nil, "reusable: a vanilla save puts the class method back")
end

-- ---------------------------------------------------------- install path

local function installSuite()
  local data = syntheticData()
  local hooks = {}
  local Class = { consumeItem = function() end }
  Class.__index = Class
  local mod = { game = setmetatable({ data = data }, Class),
    hooks = { wrap = function(_, name, fn) hooks[name] = fn end } }
  local ctx = Fake.new({ seed = "abc", options = { tms = true, tms_compat = true, tms_reusable = true } })
  Module.install(mod, ctx)
  check(type(hooks["script.command"]) == "function", "install: wraps script.command")
  ctx.setActive(true)
  check(data.items.TM_FLAMETHROWER.teaches ~= nil and rawget(mod.game, "consumeItem") ~= nil,
    "install: onSave applies the save")
  local vmText = deepCopy(data.gen2Text)
  local ran
  hooks["script.command"](function(_, _, _, row) ran = row end, { vm = { text = vmText } }, "writetext", {},
    { op = "writetext", text = "01:0002" })
  check(ran and ran.text ~= "01:0002" and vmText[ran.text] ~= nil, "install: the hook renames the TM text")
  ctx.setActive(false)
  check(vmText[ran.text] == nil, "install: switching away removes the added text")
  hooks["script.command"](function(_, _, _, row) ran = row end, { vm = { text = vmText } }, "writetext", {},
    { op = "writetext", text = "01:0002" })
  check(ran.text == "01:0002", "install: a vanilla save runs the cart's row")
end

runSuite("synthetic", syntheticData)
reusableSuite()
installSuite()
if realData() then
  runSuite("crystal", realData)
else
  print("note: CRYSTAL_DATA_DIR not set; real Crystal data not checked")
end

print(("tms_test: %d checks, %d failures"):format(checks, failures))
if failures > 0 then os.exit(1) end
