-- Crystal randomizer: starters, gift Pokemon and static encounters.
--
-- Nothing in the game's tables is changed.  Every species is swapped as the
-- script VM runs a command, through the `script.command` hook
-- (src/script/gen2/Vm.lua runList), which hands a hook the decoded cart row and
-- runs whatever row the hook passes down instead.  So a vanilla save, or a save
-- with these questions answered NO, runs every row exactly as the cart wrote it,
-- and loading another save needs nothing restored.
--
-- What is swapped, and where:
--   * A script list (one decoded cart script) that gives or fights a Pokemon:
--     `givepoke` (not the trainer-owned gift, KENYA the SPEAROW, whose mail and
--     nickname are the errand), `giveegg` and `loadwildmon`.  Lists that sell
--     a Pokemon for coins (`checkcoins` / `takecoins`, the Game Corner prize
--     counters) are left alone, because their menu names the prize before the
--     purchase; and the catching tutorial (`catchtutorial`) is left alone,
--     because it is a demonstration, not an encounter.
--   * In such a list, every row naming that species follows it: `pokepic`,
--     `cry`, `getmonname`, `checkpoke`, and every `writetext` whose text names
--     the species or its type ("CYNDAQUIL, the fire POKéMON?" in Elm's lab),
--     so what the player hears is what they get.
--
-- Elm's three balls are the givepoke rows for CHIKORITA, CYNDAQUIL and TOTODILE;
-- those three become three different species and are published as
-- ctx.shared.starters for the trainers module's rival.  Every other gift and
-- static encounter keeps its level and gets a species chosen from a stream
-- keyed by its vanilla species alone, so one gift reached by two scripts (the
-- Karate King's Tyrogue) is the same on both paths.
--
-- Not reached by this module (there is no script row to rewrite):
--   * SHUCKIE (`special GiveShuckle`, src/script/gen2/Specials.lua), and the
--     Odd Egg (`special GiveOddEgg`, src/script/gen2/specials/crystal_story.lua).
--   * Raikou and Entei: they roam (src/core/gen2 Roamers), they are never a
--     `loadwildmon`.
--   * Overworld sprites keep their vanilla look, so a sprite the navigation
--     names by its sheet (SPRITE_BIG_SNORLAX reads "Snorlax") still says so.

local M = {
  id = "starters",
  questions = {
    { key = "starters", kind = "yesno", text = "Shuffle the\nstarter POKéMON?" },
    { key = "gifts", kind = "yesno", text = "Shuffle gift and\nstatic POKéMON?" },
  },
}

-- The three balls in Elm's lab, in the order ctx.shared.starters lists them.
M.STARTERS = { "CHIKORITA", "CYNDAQUIL", "TOTODILE" }
local IS_STARTER = {}
for _, id in ipairs(M.STARTERS) do IS_STARTER[id] = true end

-- Ops that mean "this list is not a gift or an encounter" (see above).
local SKIP_LIST_OPS = { checkcoins = true, takecoins = true, catchtutorial = true }

-- ---------------------------------------------------------------- species data

-- Per data.pokemon table: index -> id, and the two pools, sorted by index so the
-- same seed picks the same species whatever order `pairs` walks the table in.
local speciesCache = setmetatable({}, { __mode = "k" })

-- A species with no egg group, no evolution and no pre-evolution is a
-- legendary or UNOWN in the cart's data; neither is a fair Lv. 5 start.
local function isLoner(def, evolvedInto)
  local groups = def.eggGroups or {}
  return groups[1] == "EGG_NONE" and #(def.evolutions or {}) == 0
    and not evolvedInto[def.id]
end

function M.species(pokemon)
  local cached = speciesCache[pokemon]
  if cached then return cached end
  local byIndex, all = {}, {}
  local evolvedInto = {}
  for id, def in pairs(pokemon or {}) do
    if type(def) == "table" and type(def.index) == "number" and def.baseStats then
      byIndex[def.index] = id
      all[#all + 1] = id
      for _, evo in ipairs(def.evolutions or {}) do
        if evo.into then evolvedInto[evo.into] = true end
      end
    end
  end
  table.sort(all, function(a, b) return pokemon[a].index < pokemon[b].index end)
  -- First stages: nothing evolves into them.  Starters and eggs come from here.
  local basic = {}
  for _, id in ipairs(all) do
    local def = pokemon[id]
    if not evolvedInto[id] and not isLoner(def, evolvedInto) then
      basic[#basic + 1] = id
    end
  end
  cached = { byIndex = byIndex, all = all, basic = basic }
  speciesCache[pokemon] = cached
  return cached
end

-- ---------------------------------------------------------------- the choices

-- { CHIKORITA = x, CYNDAQUIL = y, TOTODILE = z }, three different species.
function M.chooseStarters(ctx, pokemon)
  local pool = M.species(pokemon).basic
  if #pool < 3 then return nil end
  local order = ctx.rng("starters"):shuffled(pool)
  local out = {}
  for i, vanilla in ipairs(M.STARTERS) do out[vanilla] = order[i] end
  return out
end

-- The species given instead of `vanilla` by a gift (`kind` "gift") or an egg
-- (`kind` "egg", from the first-stage pool, since an egg hatches one).
function M.chooseGift(ctx, pokemon, vanilla, kind)
  local species = M.species(pokemon)
  local pool = kind == "egg" and species.basic or species.all
  return ctx.rng("gifts", kind, vanilla):pick(pool)
end

-- ---------------------------------------------------------------- text

-- The word the cart's prose uses for a type: "fire", "psychic".
local function typeWord(typeId)
  return (tostring(typeId):gsub("_TYPE$", "")):lower()
end

function M.typePhrase(def)
  local types = def and def.types or {}
  local first, second = types[1], types[2]
  if not first then return nil end
  if second and second ~= first then
    return typeWord(first) .. "/" .. typeWord(second)
  end
  return typeWord(first)
end

-- Every whole-word `from` in `body` (no capital letter touching either end, so
-- a name inside a longer name is not hit) becomes `to`.
local function replaceWord(body, from, to)
  if from == "" or from == to then return body end
  local out, pos = {}, 1
  while true do
    local s, e = body:find(from, pos, true)
    if not s then break end
    local before = s > 1 and body:sub(s - 1, s - 1) or ""
    local after = body:sub(e + 1, e + 1)
    if before:match("%u") or after:match("%u") then
      out[#out + 1] = body:sub(pos, e)
    else
      out[#out + 1] = body:sub(pos, s - 1) .. to
    end
    pos = e + 1
  end
  out[#out + 1] = body:sub(pos)
  return table.concat(out)
end

local function replacePlain(body, from, to)
  if from == to then return body end
  local out, pos = {}, 1
  while true do
    local s, e = body:find(from, pos, true)
    if not s then break end
    out[#out + 1] = body:sub(pos, s - 1) .. to
    pos = e + 1
  end
  out[#out + 1] = body:sub(pos)
  return table.concat(out)
end

-- `body` with the vanilla species' name and type ("the fire POKéMON",
-- "a fighting-type") replaced by the new one's.  The text box soft-wraps a
-- line that grows past the box (src/render/TextBox.lua paginate).
function M.rewriteText(body, fromDef, toDef)
  if type(body) ~= "string" or not fromDef or not toDef then return body end
  body = replaceWord(body, fromDef.name or fromDef.id, toDef.name or toDef.id)
  local fromType, toType = M.typePhrase(fromDef), M.typePhrase(toDef)
  if fromType and toType and fromType ~= toType then
    body = replacePlain(body, fromType .. " POKéMON", toType .. " POKéMON")
    body = replacePlain(body, fromType .. "-type", toType .. "-type")
  end
  return body
end

-- ---------------------------------------------------------------- the rows

local function speciesOf(cmd)
  local args = cmd.args
  return cmd.species or (args and args[1])
end

-- Which species a list gives or fights, and how: { [index] = "starter" |
-- "gift" | "egg" }, or false for a list with none.  Cached per list table.
local planCache = setmetatable({}, { __mode = "k" })

function M.planFor(list, byIndex)
  local cached = planCache[list]
  if cached ~= nil then return cached end
  local plan = false
  if type(list) == "table" then
    for _, cmd in ipairs(list) do
      if type(cmd) == "table" and SKIP_LIST_OPS[cmd.op] then
        planCache[list] = false
        return false
      end
    end
    for _, cmd in ipairs(list) do
      local op = type(cmd) == "table" and cmd.op
      local index, kind
      if op == "givepoke" then
        local trainer = cmd.trainer or (cmd.args and cmd.args[4]) or 0
        if trainer == 0 then index = speciesOf(cmd) end
      elseif op == "giveegg" then
        index, kind = speciesOf(cmd), "egg"
      elseif op == "loadwildmon" then
        index = speciesOf(cmd)
      end
      local id = index and byIndex[index]
      if id then
        plan = plan or {}
        plan[index] = kind or (IS_STARTER[id] and "starter") or "gift"
      end
    end
  end
  planCache[list] = plan
  return plan
end

local SPECIES_FIELD = {
  givepoke = "species", giveegg = "species", loadwildmon = "species",
  pokepic = "species", getmonname = "species", checkpoke = "species",
  cry = "id",
}

local function copyRow(cmd)
  local row = {}
  for k, v in pairs(cmd) do row[k] = v end
  return row
end

-- The row to run instead of `cmd`, or nil to run the cart's own.
-- `swap` maps a vanilla species index to the index given instead.
function M.rewriteRow(cmd, swap, pokemon, byIndex, text, textKeyPrefix)
  local op = cmd.op
  local field = SPECIES_FIELD[op]
  if field then
    local current = cmd[field]
    if current == nil and field == "species" then current = speciesOf(cmd) end
    local new = current and swap[current]
    if not new then return nil end
    local row = copyRow(cmd)
    row[field] = new
    if op == "giveegg" or op == "pokepic" or op == "checkpoke" then
      -- these read args[1] when the decoded field is missing; keep both agreeing
      if type(cmd.args) == "table" then
        local args = copyRow(cmd.args)
        args[1] = new
        row.args = args
      end
    end
    return row
  end
  if (op == "writetext" or op == "farwritetext") and cmd.text and text then
    local body = text[cmd.text]
    if type(body) ~= "string" then return nil end
    local rewritten, tag = body, {}
    for from, to in pairs(swap) do
      rewritten = M.rewriteText(rewritten,
        pokemon[byIndex[from]], pokemon[byIndex[to]])
      tag[#tag + 1] = from .. ">" .. to
    end
    if rewritten == body then return nil end
    table.sort(tag)
    -- A key of our own, named by the cart's key and the swap, so the text is
    -- the same whichever save asks and the vanilla entry is never touched.
    local key = textKeyPrefix .. cmd.text .. ":" .. table.concat(tag, ",")
    text[key] = rewritten
    local row = copyRow(cmd)
    row.text = key
    return row
  end
  return nil
end

-- ---------------------------------------------------------------- install

function M.install(mod, ctx)
  local state = { starters = nil, gifts = {} }

  local function gameData()
    local ok, game = pcall(function() return mod.game end)
    local data = ok and type(game) == "table" and game.data or nil
    if type(data) == "table" and type(data.pokemon) == "table" then return data end
    return nil
  end

  local function refreshStarters()
    state.starters, ctx.shared.starters = nil, nil
    if not (ctx.active() and ctx.option("starters")) then return end
    local data = gameData()
    if not data then return end
    state.starters = M.chooseStarters(ctx, data.pokemon)
    if state.starters then
      local copy = {}
      for k, v in pairs(state.starters) do copy[k] = v end
      ctx.shared.starters = copy
      ctx.log("starters: CHIKORITA>%s CYNDAQUIL>%s TOTODILE>%s",
        copy.CHIKORITA, copy.CYNDAQUIL, copy.TOTODILE)
    end
  end

  ctx.onSave(function()
    state.gifts = {}
    refreshStarters()
  end)

  -- The species id given instead of vanilla `id`, or nil to keep it.
  local function replacementFor(id, kind, pokemon)
    if kind == "starter" then
      if not ctx.option("starters") then return nil end
      if not state.starters then refreshStarters() end
      return state.starters and state.starters[id]
    end
    if not ctx.option("gifts") then return nil end
    local key = kind .. ":" .. id
    local chosen = state.gifts[key]
    if chosen == nil then
      chosen = M.chooseGift(ctx, pokemon, id, kind) or false
      state.gifts[key] = chosen
    end
    return chosen or nil
  end

  local function hook(nextFn, sctx, name, args, cmd)
    if not ctx.active() or type(cmd) ~= "table" then
      return nextFn(sctx, name, args, cmd)
    end
    local vm = type(sctx) == "table" and sctx.vm or nil
    local data = gameData()
    if not (vm and data) then return nextFn(sctx, name, args, cmd) end
    local species = M.species(data.pokemon)
    local plan = M.planFor(vm.cmdList, species.byIndex)
    if not plan then return nextFn(sctx, name, args, cmd) end
    local swap, any = {}, false
    for index, kind in pairs(plan) do
      local id = species.byIndex[index]
      local new = replacementFor(id, kind, data.pokemon)
      local def = new and data.pokemon[new]
      if def and def.index ~= index then
        swap[index] = def.index
        any = true
      end
    end
    if not any then return nextFn(sctx, name, args, cmd) end
    local row = M.rewriteRow(cmd, swap, data.pokemon, species.byIndex,
      vm.text, "crystal_randomizer:")
    return nextFn(sctx, name, args, row or cmd)
  end

  if mod and mod.hooks and mod.hooks.wrap then
    mod.hooks:wrap("script.command", hook)
  else
    ctx.log("starters: no mod.hooks; nothing will be randomized")
  end
end

return M
