-- The Party page: the party as a list, the chosen member's fields by section
-- (mon_fields.lua), and upstream's roster toolbar from panels/Party.lua.  The
-- selection is a slot number looked up in the save on every call, because Undo
-- and Reload replace the save and leave any held reference pointing at nothing.
local Ops = require("Ops")
local PartyMod = require("src.pokemon.Party")
local MonFields = require("pages.mon_fields")

local Page = {}

-- Finds the selected member and tells upstream's state, which Ops reads.
local function selectedMon(S, state)
  local party = S.save.party or {}
  if #party == 0 then
    state.selected = nil
    S.selectedParty, S.editingMon = 1, nil
    return nil
  end
  local slot = Ops.clamp(tonumber(state.selected) or 1, 1, #party)
  state.selected = slot
  S.selectedParty, S.editingMon = slot, party[slot]
  return party[slot], slot
end

local function rowText(S, mon)
  local parts = { MonFields.describe(S, mon) }
  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp)
  parts[#parts + 1] = "HP " .. tostring(mon.hp or 0) .. " of " .. tostring(maxHp or "unknown")
  local status = MonFields.statusName(mon)
  if status ~= "Healthy" then parts[#parts + 1] = status end
  if MonFields.isShiny(S, mon) then parts[#parts + 1] = "Shiny" end
  return table.concat(parts, ", ")
end

function Page.model(S, state)
  local mon, slot = selectedMon(S, state)
  local party = S.save.party or {}
  local rows = {}
  for i, member in ipairs(party) do
    rows[i] = { id = tostring(i), text = rowText(S, member) }
  end

  -- Move up and down stay enabled at the ends: disabling a focused button would
  -- push focus to its neighbour, and the next Enter would undo the move.
  local actions = MonFields.actions(S, state, mon)
  actions[#actions + 1] = { id = "add", label = "Add to party" }
  actions[#actions + 1] = { id = "delete", label = "Remove from party", enabled = mon ~= nil,
    confirm = mon and ("Remove " .. MonFields.describe(S, mon) .. " from the party?") or nil }
  actions[#actions + 1] = { id = "up", label = "Move up", enabled = mon ~= nil }
  actions[#actions + 1] = { id = "down", label = "Move down", enabled = mon ~= nil }

  return {
    list = { label = ("Party, %d of %d"):format(#party, PartyMod.MAX), rows = rows,
      selected = slot and tostring(slot) or nil },
    pickers = { MonFields.sectionPicker(S, state, mon) },
    fields = MonFields.fields(S, state, mon),
    actions = actions,
  }
end

function Page.select(_, state, request)
  state.selected = tonumber(request.row)
end

function Page.pick(_, state, request)
  if request.picker == "section" then MonFields.pickSection(state, request.value) end
end

function Page.set(S, state, request)
  MonFields.set(S, (selectedMon(S, state)), request.field, request.value)
end

function Page.action(S, state, request)
  local mon = selectedMon(S, state)
  local id = request.action
  if id == "add" then
    Ops.partyAdd(S)
  elseif id == "delete" then
    if mon then
      -- The window has already asked yes or no, which replaces upstream's second press.
      S.armed, S.armedAt = "party-remove", nil
      Ops.partyRemove(S)
    end
  elseif id == "up" then
    if mon then Ops.partyMove(S, -1) end
  elseif id == "down" then
    if mon then Ops.partyMove(S, 1) end
  elseif not MonFields.action(S, mon, id) then
    error("party does not handle " .. tostring(id), 0)
  end
  -- Ops moved the selection to follow the Pokémon; Clone also points it at the copy,
  -- which the next lookup undoes because this page edits the party member.
  if id == "add" or id == "delete" or id == "up" or id == "down" then
    state.selected = S.selectedParty
  end
end

return Page
