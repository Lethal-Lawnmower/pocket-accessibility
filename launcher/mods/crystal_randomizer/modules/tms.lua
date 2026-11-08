-- Crystal randomizer: what each TM teaches, who can learn it, and reusable TMs.
--
-- How Gen 2 reads a TM (checked in this port, 2026-11-08):
--   * The move a TM or HM teaches is the item record's `teaches` field
--     (data.items[TM_x].teaches, written by src/import/RomExtractorGen2.lua
--     from TMHMMoves).  Every reader takes it from there at the moment it is
--     needed: the PACK's TM pocket rows and description (src/ui/gen2/PackMenu.lua
--     rebuild / moveLabel / moveOf), the mart's description
--     (src/ui/gen2/MartMenu.lua description), the teach flow
--     (PackMenu:openTeachParty, Game2:useFieldItem) and, through the PACK's
--     rows, the speech (src/access/screens/gen2/Items.lua Pack.row speaks
--     `row.teaches`).  The item's own name is its label ("TM02"), which never
--     names a move, and the item id (TM_HEADBUTT) is a save key and is never
--     changed.
--   * Compatibility is `def.tmhm` on the species: a list of MOVE ids, not of
--     TM numbers.  The teach flow, the party's ABLE / NOT ABLE
--     (src/access/screens/Presenters.lua), breeding's TM inheritance
--     (src/core/gen2/Breeding.lua) and src/inventory/ItemEffects.lua all ask
--     "is this move in def.tmhm".  So when a TM's move changes, every
--     species' list is rebuilt from TM numbers.
--   * A TM is used up by Game2:consumeItem, called after a successful teach
--     from both teach paths (an HM never is).  There is no hook there, so the
--     reusable option wraps that one method on the live game instance (see
--     installReusable).
--
-- What it owns, and restores exactly (the vanilla tables by reference):
--   data.items[TM_x / HM_x].teaches  (only TMs ever change; HMs are restored
--                                     too, but are never given another value)
--   def.tmhm for every species        (replaced by a new list)
--   data.pokemon.tmhmMoves            (replaced by a new list)
--   game.consumeItem on the instance  (the instance's own field put back)
--   text entries it adds to the script text table, removed on every switch
-- It never touches def.types or def.levelMoves (the pokemon module's), and it
-- reads def.types as the pokemon module left them for this save.
--
-- Choices (stated so they can be reviewed):
--   Contents: every TM gets a different move.  A TM whose vanilla move deals
--     damage gets a damaging move, and a status TM a status move, so a run
--     keeps about the cart's mix.  Never an HM's move (that would hand out HM
--     compatibility under another name) and never STRUGGLE.  HEADBUTT and
--     ROCK SMASH, the TM moves the overworld checks for (trees and rocks), are
--     always still taught by some TM, placed at random.
--   Compatibility: each species keeps the number of TMs it could learn (a
--     species that learned none still learns none), and draws which ones;
--     half the draws prefer a TM whose move shares one of the species'
--     current types.  Any TM nobody drew is given to one species that learns
--     TMs at all.  HM compatibility is the vanilla one, always.
--   Compatibility without the shuffle: it stays with the TM's number, so a
--     species that learned TM24 still learns TM24, whatever TM24 now teaches.
--   Text: a script text that names a TM's move is rewritten to name the new
--     move when the text belongs to a script that gives that TM, or names the
--     TM by number ("TM31 contains MUD-SLAP").  The rest of such a text (what
--     the old move does) is the cart's.

local M = {
  id = "tms",
  questions = {
    { key = "tms", kind = "yesno", text = "Shuffle what TMs\nteach?",
      recommended = true, everything = true },
    { key = "tms_compat", kind = "yesno", text = "Shuffle who can\nlearn each TM?",
      recommended = true, everything = true },
    { key = "tms_reusable", kind = "yesno", text = "Let TMs be used\nmore than once?",
      recommended = true, everything = true },
  },
}

-- The move the battle falls back on when nothing else is left; no species
-- learns it (on Crystal it is the only move none does).
local NEVER_TAUGHT = { STRUGGLE = true }
-- TM moves the overworld needs a party member to know (src/world/gen2/World.lua
-- CheckPartyMove for headbutt trees and smashable rocks).
local OVERWORLD_MOVES = { "HEADBUTT", "ROCK_SMASH" }
-- Chance that a compatibility draw prefers a TM of the species' own type.
local SAME_TYPE_CHANCE = 0.5
local TEXT_KEY_PREFIX = "crystal_randomizer:tms:"
local TEXT_OPS = { writetext = true, farwritetext = true, jumptext = true,
  farjumptext = true, jumptextfaceplayer = true }

-- ------------------------------------------------------------------ data

local function sortedKeys(set)
  local list = {}
  for key in pairs(set) do list[#list + 1] = key end
  table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
  return list
end

local function isHmId(id) return tostring(id):sub(1, 3) == "HM_" end

-- TM and HM items, as { id, number, def } sorted by TM/HM number.
function M.machines(items)
  local tms, hms = {}, {}
  for id, def in pairs(items or {}) do
    if type(def) == "table" and type(def.teaches) == "string" and tonumber(def.tmNumber) then
      local entry = { id = id, number = tonumber(def.tmNumber), def = def }
      if isHmId(id) then hms[#hms + 1] = entry else tms[#tms + 1] = entry end
    end
  end
  local byNumber = function(a, b) return a.number < b.number end
  table.sort(tms, byNumber)
  table.sort(hms, byNumber)
  return tms, hms
end

local function isSpecies(def)
  return type(def) == "table" and type(def.types) == "table" and type(def.tmhm) == "table"
end

function M.isDamaging(move)
  return type(move) == "table" and (tonumber(move.power) or 0) > 0
end

-- The vanilla copy, taken the first time this data is seen.  Only fields this
-- module owns, which no earlier module changes, so the first sight is vanilla.
local function snapshot(data)
  local tms, hms = M.machines(data.items)
  local v = { tms = {}, hms = {}, hmMoves = {}, tmNumberOfMove = {}, species = {} }
  for i, tm in ipairs(tms) do
    v.tms[i] = { id = tm.id, number = tm.number, def = tm.def, teaches = tm.def.teaches,
      label = tm.def.tmLabel or tm.def.name }
    v.tmNumberOfMove[tm.def.teaches] = tm.number
  end
  for i, hm in ipairs(hms) do
    v.hms[i] = { id = hm.id, number = hm.number, def = hm.def, teaches = hm.def.teaches }
    v.hmMoves[hm.def.teaches] = true
  end
  for species, def in pairs(data.pokemon or {}) do
    if isSpecies(def) then
      local numbers, hmList = {}, {}
      for _, move in ipairs(def.tmhm) do
        if v.hmMoves[move] then
          hmList[#hmList + 1] = move
        elseif v.tmNumberOfMove[move] then
          numbers[#numbers + 1] = v.tmNumberOfMove[move]
        end
      end
      table.sort(numbers)
      v.species[species] = { table = def.tmhm, numbers = numbers, hms = hmList }
    end
  end
  local list = data.pokemon and data.pokemon.tmhmMoves
  if type(list) == "table" then
    local copy = {}
    for i, move in ipairs(list) do copy[i] = move end
    v.tmhmMovesTable, v.tmhmMoves = list, copy
  end
  return v
end

-- ------------------------------------------------------------- contents

-- { [TM number] = move id } for this seed.  Reads the move table as it is for
-- this save (another module may have changed a move's power or type).
function M.newContents(ctx, vanilla, moves)
  local damaging, status = {}, {}
  for _, id in ipairs(sortedKeys(moves)) do
    local move = moves[id]
    if type(move) == "table" and tonumber(move.index) and move.index > 0
        and not NEVER_TAUGHT[id] and not vanilla.hmMoves[id] then
      if M.isDamaging(move) then damaging[#damaging + 1] = id else status[#status + 1] = id end
    end
  end
  local rng = ctx.rng("tms_contents")
  local out, used = {}, {}
  local function kindOf(moveId) return M.isDamaging(moves[moveId]) and "damaging" or "status" end

  -- The overworld moves first, each on a TM of its own kind.
  for _, keep in ipairs(OVERWORLD_MOVES) do
    if vanilla.tmNumberOfMove[keep] and moves[keep] and not used[keep] then
      local candidates = {}
      for _, tm in ipairs(vanilla.tms) do
        if not out[tm.number] and kindOf(tm.teaches) == kindOf(keep) then
          candidates[#candidates + 1] = tm.number
        end
      end
      if #candidates == 0 then
        for _, tm in ipairs(vanilla.tms) do
          if not out[tm.number] then candidates[#candidates + 1] = tm.number end
        end
      end
      local number = rng:pick(candidates)
      if number then out[number], used[keep] = keep, true end
    end
  end

  local decks = { damaging = rng:shuffled(damaging), status = rng:shuffled(status) }
  local next = { damaging = 1, status = 1 }
  local function draw(kind)
    local deck = decks[kind]
    while next[kind] <= #deck do
      local id = deck[next[kind]]
      next[kind] = next[kind] + 1
      if not used[id] then return id end
    end
  end
  for _, tm in ipairs(vanilla.tms) do
    if not out[tm.number] then
      local kind = kindOf(tm.teaches)
      local id = draw(kind) or draw(kind == "damaging" and "status" or "damaging") or tm.teaches
      out[tm.number], used[id] = id, true
    end
  end
  return out
end

-- -------------------------------------------------------- compatibility

-- { [species] = sorted TM numbers } for this seed.  `teaches` maps a TM number
-- to the move it teaches in this save; `pokemon` gives the current types.
function M.newCompatibility(ctx, vanilla, pokemon, moves, teaches)
  local numbers = {}
  for _, tm in ipairs(vanilla.tms) do numbers[#numbers + 1] = tm.number end
  local out, users = {}, {}
  local learners = {}
  for _, species in ipairs(sortedKeys(vanilla.species)) do
    local count = #vanilla.species[species].numbers
    local def = pokemon[species]
    local typeSet = {}
    for _, t in ipairs(def and def.types or {}) do typeSet[t] = true end
    local rng = ctx.rng("tms_compat", species)
    local remaining, typed = {}, {}
    for _, n in ipairs(numbers) do
      remaining[#remaining + 1] = n
      local move = moves[teaches[n]]
      if move and typeSet[move.type] then typed[#typed + 1] = n end
    end
    local chosen, taken = {}, {}
    local function take(list)
      while #list > 0 do
        local i = rng:int(1, #list)
        local n = table.remove(list, i)
        if not taken[n] then return n end
      end
    end
    for _ = 1, math.min(count, #numbers) do
      local n
      if #typed > 0 and rng:next() < SAME_TYPE_CHANCE then n = take(typed) end
      n = n or take(remaining)
      if not n then break end
      taken[n] = true
      chosen[#chosen + 1] = n
    end
    table.sort(chosen)
    out[species] = chosen
    if count > 0 then learners[#learners + 1] = species end
    for _, n in ipairs(chosen) do users[n] = (users[n] or 0) + 1 end
  end
  -- A TM nobody drew still has a learner.
  for _, n in ipairs(numbers) do
    if not users[n] and #learners > 0 then
      local species = ctx.rng("tms_compat_floor", n):pick(learners)
      local list = out[species]
      list[#list + 1] = n
      table.sort(list)
      users[n] = 1
    end
  end
  return out
end

-- ------------------------------------------------------------------ text

-- Every whole-word occurrence of each `from` in `body` becomes its `to`, in
-- one pass, so a new name that equals another TM's old name is not replaced
-- again.  A word touching a capital letter, a digit or a hyphen is not whole.
function M.replaceNames(body, swaps)
  local out, pos = {}, 1
  while pos <= #body do
    local bestS, bestE, bestTo
    for from, to in pairs(swaps) do
      local search = pos
      while true do
        local s, e = body:find(from, search, true)
        if not s then break end
        local before = s > 1 and body:sub(s - 1, s - 1) or ""
        local after = body:sub(e + 1, e + 1)
        if not before:match("[%u%d%-]") and not after:match("[%u%d%-]") then
          if not bestS or s < bestS or (s == bestS and e > bestE) then
            bestS, bestE, bestTo = s, e, to
          end
          break
        end
        search = s + 1
      end
    end
    if not bestS then break end
    out[#out + 1] = body:sub(pos, bestS - 1) .. bestTo
    pos = bestE + 1
  end
  out[#out + 1] = body:sub(pos)
  return table.concat(out)
end

-- Which TMs each script text speaks about: { [text key] = { TM number, ... } }.
-- A text is about a TM when a script that gives (or names) that TM shows it,
-- or when it names the TM by its label ("TM31").
function M.textPlan(scripts, text, vanilla, items)
  local tmByIndex, tmByLabel = {}, {}
  for _, tm in ipairs(vanilla.tms) do
    if tonumber(tm.def.index) then tmByIndex[tm.def.index] = tm.number end
    if tm.label then tmByLabel[tm.label] = tm.number end
  end
  local plan = {}
  local function add(key, number)
    plan[key] = plan[key] or {}
    for _, n in ipairs(plan[key]) do if n == number then return end end
    local list = plan[key]
    list[#list + 1] = number
  end
  for _, listKey in ipairs(sortedKeys(scripts or {})) do
    local list = scripts[listKey]
    if type(list) == "table" then
      local given = {}
      for _, cmd in ipairs(list) do
        local item = type(cmd) == "table" and cmd.item
        if type(item) == "number" and tmByIndex[item] then given[#given + 1] = tmByIndex[item] end
      end
      if #given > 0 then
        for _, cmd in ipairs(list) do
          if type(cmd) == "table" and TEXT_OPS[cmd.op] and type(cmd.text) == "string" then
            for _, n in ipairs(given) do add(cmd.text, n) end
          end
        end
      end
    end
  end
  for _, key in ipairs(sortedKeys(text or {})) do
    local body = text[key]
    if type(body) == "string" then
      for label in body:gmatch("TM%d%d") do
        if tmByLabel[label] then add(key, tmByLabel[label]) end
      end
    end
  end
  for _, list in pairs(plan) do table.sort(list) end
  return plan
end

-- { [text key] = { key = new key, body = new body } } for the texts whose
-- TM moves changed in this save.
function M.textRewrites(plan, text, vanilla, moves, teaches)
  local out = {}
  local byNumber = {}
  for _, tm in ipairs(vanilla.tms) do byNumber[tm.number] = tm end
  for _, key in ipairs(sortedKeys(plan)) do
    local body = text[key]
    if type(body) == "string" then
      local swaps, tag = {}, {}
      for _, n in ipairs(plan[key]) do
        local tm = byNumber[n]
        local old, new = tm and moves[tm.teaches], moves[teaches[n]]
        if old and new and tm.teaches ~= teaches[n] then
          swaps[old.name or tm.teaches] = new.name or teaches[n]
          tag[#tag + 1] = n .. ">" .. teaches[n]
        end
      end
      if #tag > 0 then
        local rewritten = M.replaceNames(body, swaps)
        if rewritten ~= body then
          out[key] = { key = TEXT_KEY_PREFIX .. key .. ":" .. table.concat(tag, ","), body = rewritten }
        end
      end
    end
  end
  return out
end

-- The row to run instead of `cmd`, or nil to run the cart's own.  Makes sure
-- `textTable` (the VM's) carries the new text; `added` records what it adds.
function M.rewriteRow(cmd, rewrites, textTable, added)
  if type(cmd) ~= "table" or not TEXT_OPS[cmd.op] or type(cmd.text) ~= "string" then return nil end
  local rewrite = rewrites and rewrites[cmd.text]
  if not rewrite then return nil end
  if type(textTable) == "table" and textTable[rewrite.key] ~= rewrite.body then
    textTable[rewrite.key] = rewrite.body
    if added then added[#added + 1] = { textTable, rewrite.key } end
  end
  local row = {}
  for k, v in pairs(cmd) do row[k] = v end
  row.text = rewrite.key
  return row
end

-- ------------------------------------------------------------- the build

-- Put back everything an earlier apply changed.
function M.restore(data, state)
  local v = state.vanilla
  for i = #(state.addedText or {}), 1, -1 do
    local entry = state.addedText[i]
    entry[1][entry[2]] = nil
  end
  state.addedText, state.rewrites = {}, nil
  if not v then return end
  for _, tm in ipairs(v.tms) do tm.def.teaches = tm.teaches end
  for _, hm in ipairs(v.hms) do hm.def.teaches = hm.teaches end
  local pokemon = data and data.pokemon
  if type(pokemon) == "table" then
    for species, s in pairs(v.species) do
      if pokemon[species] then pokemon[species].tmhm = s.table end
    end
    if v.tmhmMovesTable then pokemon.tmhmMoves = v.tmhmMovesTable end
  end
end

-- Rebuild (or restore) the TM tables for the save that just became known.
function M.apply(data, ctx, state)
  if type(data) ~= "table" or type(data.items) ~= "table" or type(data.pokemon) ~= "table" then
    return "no game data"
  end
  if state.data ~= data then state.data, state.vanilla, state.plan = data, nil, nil end
  if not state.vanilla then state.vanilla = snapshot(data) end
  M.restore(data, state)
  local v = state.vanilla
  local active = ctx.active()
  local shuffleContents = active and ctx.option("tms") == true
  local shuffleCompat = active and ctx.option("tms_compat") == true
  if not (shuffleContents or shuffleCompat) or #v.tms == 0 then
    return "vanilla"
  end
  local moves = data.moves or {}
  local teaches = {}
  if shuffleContents then
    teaches = M.newContents(ctx, v, moves)
  else
    for _, tm in ipairs(v.tms) do teaches[tm.number] = tm.teaches end
  end
  for _, tm in ipairs(v.tms) do tm.def.teaches = teaches[tm.number] end

  local compat
  if shuffleCompat then
    compat = M.newCompatibility(ctx, v, data.pokemon, moves, teaches)
  else
    compat = {}
    for species, s in pairs(v.species) do compat[species] = s.numbers end
  end
  for species, s in pairs(v.species) do
    local def = data.pokemon[species]
    if def then
      local list = {}
      for _, n in ipairs(compat[species] or {}) do list[#list + 1] = teaches[n] end
      for _, move in ipairs(s.hms) do list[#list + 1] = move end
      def.tmhm = list
    end
  end
  if v.tmhmMovesTable then
    local list = {}
    for i, move in ipairs(v.tmhmMoves) do list[i] = teaches[i] or move end
    data.pokemon.tmhmMoves = list
  end

  if shuffleContents then
    state.plan = state.plan or M.textPlan(data.gen2Scripts, data.gen2Text, v, data.items)
    state.rewrites = M.textRewrites(state.plan, data.gen2Text or {}, v, moves, teaches)
  end
  local rewritten = 0
  for _ in pairs(state.rewrites or {}) do rewritten = rewritten + 1 end
  return ("contents %s, compatibility %s, %d texts renamed"):format(
    shuffleContents and "shuffled" or "vanilla", shuffleCompat and "shuffled" or "vanilla", rewritten)
end

-- ------------------------------------------------------------ reusable TMs

-- Wrap game.consumeItem on the instance so a TM is not used up while the
-- loaded save asked for reusable TMs.  An HM is never consumed by the engine
-- anyway.  Without the option the instance's own field is put back exactly.
function M.installReusable(game, ctx, state)
  if type(game) ~= "table" then return false end
  if state.reusableGame and state.reusableGame ~= game then
    rawset(state.reusableGame, "consumeItem", state.reusableOriginal)
    state.reusableGame, state.reusableOriginal = nil, nil
  end
  local want = ctx.active() and ctx.option("tms_reusable") == true
  if not want then
    if state.reusableGame then
      rawset(game, "consumeItem", state.reusableOriginal)
      state.reusableGame, state.reusableOriginal = nil, nil
    end
    return false
  end
  if state.reusableGame == game then return true end
  if type(game.consumeItem) ~= "function" then return false end
  local own = rawget(game, "consumeItem")
  local original = game.consumeItem
  state.reusableGame, state.reusableOriginal = game, own
  rawset(game, "consumeItem", function(self, itemId, ...)
    local items = self and self.data and self.data.items
    local def = items and items[itemId]
    if ctx.active() and ctx.option("tms_reusable") == true and type(def) == "table"
        and def.teaches and not isHmId(itemId) then
      return
    end
    return original(self, itemId, ...)
  end)
  return true
end

function M.install(mod, ctx)
  local state = {}
  local function liveGame()
    local ok, game = pcall(function() return mod.game end)
    return ok and type(game) == "table" and game or nil
  end
  ctx.onSave(function()
    local game = liveGame()
    local data = game and game.data
    if not data then
      ctx.log("tms: no game data yet; nothing changed")
      return
    end
    ctx.log("tms: %s", M.apply(data, ctx, state))
    if M.installReusable(game, ctx, state) then ctx.log("tms: TMs are reusable") end
  end)

  local function hook(nextFn, sctx, name, args, cmd)
    local rewrites = state.rewrites
    if rewrites and ctx.active() and type(cmd) == "table" then
      local vm = type(sctx) == "table" and sctx.vm or nil
      state.addedText = state.addedText or {}
      local row = M.rewriteRow(cmd, rewrites, vm and vm.text, state.addedText)
      if row then return nextFn(sctx, name, args, row) end
    end
    return nextFn(sctx, name, args, cmd)
  end
  if mod and mod.hooks and mod.hooks.wrap then
    mod.hooks:wrap("script.command", hook)
  else
    ctx.log("tms: no mod.hooks; TM texts keep the cart's move names")
  end
end

return M
