-- The Boxes page: a box picker, every slot of that box as a list, the selected
-- Pokémon's fields by section (mon_fields.lua), and upstream's storage actions
-- from panels/Boxes.lua.  Upstream's party dock and species popup become two
-- dropdowns just above the buttons that use them.  Box and slot are numbers looked
-- up in the save on every call, because Undo and Reload replace the save.
local Ops = require("Ops")
local BoxSort = require("BoxSort")
local MonFields = require("pages.mon_fields")

local Page = {}

-- Finds the selected Pokémon and tells upstream's state, which Ops reads.
local function selectedMon(S, state)
  local count, capacity = Ops.boxCount(S), Ops.boxCapacity(S)
  state.box = Ops.clamp(tonumber(state.box) or S.selectedBox or 1, 1, count)
  local box = Ops.boxes(S)[state.box]
  if not state.slot then
    state.slot = 1
    for slot = 1, capacity do
      if box[slot] then state.slot = slot; break end
    end
  end
  state.slot = Ops.clamp(tonumber(state.slot) or 1, 1, capacity)
  S.selectedBox, S.selectedBoxSlot, S.editingMon = state.box, state.slot, box[state.slot]
  return box[state.slot]
end

-- After a Pokémon leaves a slot, stay close: the same slot if something filled it,
-- else the next occupied slot, else the one before.  A list that lands on Empty
-- would disable Release and Withdraw under the player's focus.
local function settleSlot(S, state)
  local box, capacity = Ops.boxes(S)[state.box], Ops.boxCapacity(S)
  local slot = Ops.clamp(tonumber(state.slot) or 1, 1, capacity)
  if box[slot] then return end
  for later = slot + 1, capacity do
    if box[later] then state.slot = later; return end
  end
  for earlier = slot - 1, 1, -1 do
    if box[earlier] then state.slot = earlier; return end
  end
end

local function boxOptions(S)
  local boxes, capacity = Ops.boxes(S), Ops.boxCapacity(S)
  local storage = S.save.storage and S.save.storage.boxes
  local options = {}
  for b = 1, Ops.boxCount(S) do
    local name = storage and storage[b] and storage[b].name
    local label = "Box " .. b
    if type(name) == "string" and name ~= "" and name:upper() ~= ("BOX " .. b) then
      label = label .. " " .. name
    end
    options[b] = { value = b, label = ("%s, %d of %d"):format(label, Ops.boxSize(S, boxes[b]), capacity) }
  end
  return options
end

local function slotRows(S, box)
  local rows = {}
  for slot = 1, Ops.boxCapacity(S) do
    local mon = box[slot]
    rows[slot] = { id = tostring(slot),
      text = (mon and MonFields.describe(S, mon) or "Empty") .. ", slot " .. slot }
  end
  return rows
end

local function addSpeciesValue(S, state)
  local options = MonFields.speciesOptions(S)
  for _, option in ipairs(options) do
    if option.value == state.addSpecies then return option.value end
  end
  return options[1] and options[1].value or ""
end

local function depositOptions(S)
  local options = {}
  for i, mon in ipairs(S.save.party or {}) do
    options[i] = { value = i, label = i .. ", " .. MonFields.describe(S, mon) }
  end
  return options
end

local function depositSlot(S, state)
  local party = S.save.party or {}
  if #party == 0 then return nil end
  return Ops.clamp(tonumber(state.depositSlot) or 1, 1, #party)
end

function Page.model(S, state)
  local mon = selectedMon(S, state)
  local box = Ops.boxes(S)[state.box]
  local partySize = #(S.save.party or {})

  local fields = MonFields.fields(S, state, mon)
  fields[#fields + 1] = { id = "addSpecies", label = "Species to add", kind = "choice",
    value = addSpeciesValue(S, state), options = MonFields.speciesOptions(S),
    help = "Used by Add to box. A new Pokémon starts at level 5." }
  fields[#fields + 1] = { id = "depositSlot", label = "Party member to deposit", kind = "choice",
    value = depositSlot(S, state), options = depositOptions(S), enabled = partySize > 0,
    help = "Used by Deposit. It goes into the box on show, or the next box with room." }

  local actions = MonFields.actions(S, state, mon)
  actions[#actions + 1] = { id = "withdraw", label = "Withdraw to party", enabled = mon ~= nil }
  actions[#actions + 1] = { id = "deposit", label = "Deposit", enabled = partySize > 0 }
  actions[#actions + 1] = { id = "delete", label = "Release", enabled = mon ~= nil,
    confirm = mon and ("Release " .. MonFields.describe(S, mon) .. " permanently?") or nil }
  actions[#actions + 1] = { id = "add", label = "Add to box" }
  for _, mode in ipairs(BoxSort.MODES) do
    actions[#actions + 1] = { id = "sort-" .. mode.id, label = "Sort all boxes: " .. mode.label }
  end

  return {
    pickers = {
      { id = "box", label = "Box", value = state.box, options = boxOptions(S) },
      MonFields.sectionPicker(S, state, mon),
    },
    list = { label = "Slots", rows = slotRows(S, box), selected = tostring(state.slot) },
    fields = fields,
    actions = actions,
  }
end

function Page.select(_, state, request)
  state.slot = tonumber(request.row)
end

function Page.pick(S, state, request)
  if request.picker == "section" then
    MonFields.pickSection(state, request.value)
  elseif request.picker == "box" then
    -- Upstream's box arrows also make this the save's current box.
    Ops.selectBox(S, tonumber(request.value) or 1)
    state.box, state.slot = S.selectedBox, nil
  end
end

function Page.set(S, state, request)
  if request.field == "addSpecies" then
    state.addSpecies = request.value
  elseif request.field == "depositSlot" then
    state.depositSlot = tonumber(request.value)
  else
    MonFields.set(S, (selectedMon(S, state)), request.field, request.value)
  end
end

-- Follows a Pokémon that Ops placed somewhere, as upstream's panel does.
local function followPlacement(S, state)
  state.box, state.slot = S.selectedBox, S.selectedBoxSlot
end

function Page.action(S, state, request)
  local mon = selectedMon(S, state)
  local id = request.action
  if id == "withdraw" then
    Ops.withdraw(S)
    settleSlot(S, state)
  elseif id == "delete" then
    if mon then
      -- The window has already asked yes or no, which replaces upstream's second press.
      S.armed, S.armedAt = "box-release", nil
      Ops.release(S)
      settleSlot(S, state)
    end
  elseif id == "deposit" then
    local revision = S.revision
    S.selectedParty = depositSlot(S, state) or 1
    Ops.deposit(S)
    if S.revision ~= revision then
      state.box = S.selectedBox
      -- Old generations keep a box packed and append; Gen 3 reports the slot it chose.
      local box = Ops.boxes(S)[state.box]
      state.slot = box[S.selectedBoxSlot] and require("Gen").ofState(S) == 3 and S.selectedBoxSlot
        or Ops.boxSize(S, box)
    end
  elseif id == "add" then
    local revision = S.revision
    Ops.boxAddSpecies(S, addSpeciesValue(S, state))
    if S.revision ~= revision then followPlacement(S, state) end
  elseif id:match("^sort%-") then
    local revision = S.revision
    Ops.setBoxOrder(S, id:sub(6))
    if S.revision ~= revision then
      state.slot = S.selectedBoxSlot
      settleSlot(S, state)
    end
  elseif id == "clone" then
    local revision = S.revision
    MonFields.action(S, mon, id)
    if S.revision ~= revision then followPlacement(S, state) end
  elseif not MonFields.action(S, mon, id) then
    error("boxes does not handle " .. tostring(id), 0)
  end
end

return Page
