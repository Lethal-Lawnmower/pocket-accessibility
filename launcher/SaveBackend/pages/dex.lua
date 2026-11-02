-- The Pokédex page: every species with its seen and owned state, and upstream's bulk
-- tools.  Same rules as panels/Dex.lua; all edits are upstream's Ops, which keep
-- "owning implies seen, un-seeing clears owned".
local Ops = require("Ops")
local Gen = require("Gen")

local Page = {}

local function displayName(def, id)
  local name = tostring(def and def.name or id)
  -- some caches hold names in capitals, which a screen reader may spell out
  if name == name:upper() and name:lower() ~= name then
    return (name:lower():gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
  end
  return name
end

-- Upstream's panel reads a species by its record key and its number, since Gen 3
-- saves can hold either.
local function stateOf(S, dex, ownedKey, id)
  local def = S.data.pokemon[id]
  local number = def and (def.speciesId or def.dex)
  local seen = dex.seen[id] == true or (number and dex.seen[number] == true)
  local owned = (dex[ownedKey] and (dex[ownedKey][id] == true or (number and dex[ownedKey][number] == true)))
    or (dex.caught and (dex.caught[id] == true or (number and dex.caught[number] == true)))
  return seen == true, owned == true
end

-- The sorted species, recomputed only when the sort changes.
local function speciesList(S, state)
  local sort = S.dexSort == "name" and "name" or "dex"
  if state.list and state.listSort == sort then return state.list end
  state.list, state.listSort = Ops.dexList(S), sort
  state.byRow = {}
  for _, id in ipairs(state.list) do state.byRow[tostring(id)] = id end
  return state.list
end

local function selectedSpecies(S, state)
  local list = speciesList(S, state)
  local id = state.byRow[tostring(state.selected)]
  if id == nil then id = list[1] end
  return id
end

function Page.model(S, state)
  local dex = Ops.dex(S)
  local ownedKey = Gen.dexOwnedKey(S.save)
  local seenCount, ownedCount, total = Ops.dexCounts(S)
  local rows = {}
  for i, id in ipairs(speciesList(S, state)) do
    local def = S.data.pokemon[id]
    local seen, owned = stateOf(S, dex, ownedKey, id)
    rows[i] = {
      id = tostring(id),
      text = ("%03d %s, %s"):format(def and def.dex or 0, displayName(def, id),
        owned and "seen, owned" or (seen and "seen" or "not seen")),
    }
  end
  local selected = selectedSpecies(S, state)
  local fields = {}
  if selected ~= nil then
    local seen, owned = stateOf(S, dex, ownedKey, selected)
    local name = displayName(S.data.pokemon[selected], selected)
    fields[#fields + 1] = { id = "seen", label = "Seen", kind = "check", value = seen,
      help = name .. ". Clearing seen also clears owned." }
    fields[#fields + 1] = { id = "owned", label = "Owned", kind = "check", value = owned,
      help = name .. ". Owning also marks it seen." }
  end
  if Gen.ofState(S) == 3 then
    fields[#fields + 1] = { id = "national", label = "National Pokédex", kind = "check",
      value = dex.national == true }
  end
  return {
    pickers = { {
      id = "sort", label = "Sort", value = S.dexSort == "name" and "name" or "dex",
      options = { { value = "dex", label = "By Pokédex number" }, { value = "name", label = "By name" } },
    } },
    summary = ("%d of %d seen, %d of %d owned."):format(seenCount, total, ownedCount, total),
    list = { label = "Species", rows = rows, selected = selected ~= nil and tostring(selected) or nil, filter = true },
    fields = fields,
    actions = {
      { id = "stamp", label = "Own party and boxes" },
      { id = "see", label = "See all" },
      { id = "own", label = "Own all" },
      { id = "wipe", label = "Clear Pokédex", confirm = "Wipe the whole Pokédex, every seen and owned mark?" },
    },
  }
end

function Page.select(S, state, request)
  speciesList(S, state)
  state.selected = request.row
end

function Page.pick(S, _, request)
  if request.picker == "sort" then Ops.dexSort(S, request.value) end
end

function Page.set(S, state, request)
  if request.field == "national" then
    if Gen.ofState(S) ~= 3 then return end
    local dex = Ops.dex(S)
    if (dex.national == true) ~= (request.value == true) then Ops.toggleNationalDex(S) end
    return
  end
  local id = selectedSpecies(S, state)
  if id == nil then return end
  if request.field == "seen" then
    Ops.dexSeen(S, id, request.value == true)
  elseif request.field == "owned" then
    Ops.dexOwned(S, id, request.value == true)
  end
end

function Page.action(S, _, request)
  if request.action == "stamp" then
    Ops.dexStamp(S)
  elseif request.action == "see" then
    Ops.dexSeeAll(S)
  elseif request.action == "own" then
    Ops.dexOwnAll(S)
  elseif request.action == "wipe" then
    -- the client has already asked yes or no, so upstream's first click is taken as made
    S.armed, S.armedAt = "dex-clear", nil
    Ops.dexClear(S)
    S.armed, S.armedAt = nil, nil
  end
end

return Page
