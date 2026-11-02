-- What the save editor put on screen this frame, as a reading order.
--
-- The editor is an immediate-mode mouse program: a control exists only as a
-- call to Kit during the draw.  Kit already reports every clickable control to
-- Kit.audit (its layout tests use it), and modal shields keep covered controls
-- out, so that list is the seam.  The wrappers below add what the audit lacks:
-- drawn text in sequence with the controls, control state, and the regions that
-- scroll.  Nothing here changes what Kit draws or returns.
local Capture = {}

local function bounds(x, y, w, h, clip)
  if not clip then return x, y, w, h end
  local x2, y2 = math.min(x + w, clip.x + clip.w), math.min(y + h, clip.y + clip.h)
  local left, top = math.max(x, clip.x), math.max(y, clip.y)
  return left, top, x2 - left, y2 - top
end

local function inside(rect, x, y)
  return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

-- Wraps Kit once.  The audit table and frame.scrollers fill while a frame runs;
-- outside one the wrappers only call through.
function Capture.install(Kit, Touch)
  local frame = { scrollers = {}, full = {} }
  local active = false

  local function count() return Kit.audit and #Kit.audit or 0 end
  -- The entry a widget's own audit call just added (none under a modal shield).
  local function added(before)
    local entry = active and Kit.audit and Kit.audit[before + 1]
    return entry and entry.class ~= "text" and entry or nil
  end

  local ellipsize = Kit.ellipsize
  Kit.ellipsize = function(name, str, maxW)
    local shown = ellipsize(name, str, maxW)
    -- a shortened label is read in full
    if active and shown ~= str then frame.full[shown] = tostring(str) end
    return shown
  end

  local text = Kit.text
  Kit.text = function(name, str, x, y, c, a)
    if active and not Kit.blockClicks and str ~= nil then
      local clip = Kit._clipRect
      if not clip or inside(clip, x + 1, y + 1) then
        local line = tostring(str)
        line = frame.full[line] or line
        local entries = Kit.audit
        local previous = entries[#entries]
        -- bold text is printed twice, a pixel apart
        if not (previous and previous.class == "text" and previous.str == line
            and math.abs(previous.x - x) < 3 and math.abs(previous.y - y) < 3) then
          entries[#entries + 1] = { class = "text", str = line, x = x, y = y, h = Kit.textHeight(name) }
        end
      end
    end
    return text(name, str, x, y, c, a)
  end

  -- Centred text prints directly; record it once, whichever way it draws.
  for _, name in ipairs({ "textCenter", "textCenterBold" }) do
    local center = Kit[name]
    Kit[name] = function(font, str, x, y, w, c, a)
      local wasActive = active
      if wasActive and not Kit.blockClicks and str ~= nil then
        local clip = Kit._clipRect
        local width = Kit.textWidth(font, str)
        local left = x + (w - width) / 2
        if not clip or inside(clip, left + 1, y + 1) then
          local entries = Kit.audit
          entries[#entries + 1] = { class = "text", str = tostring(str), x = left, y = y, h = Kit.textHeight(font) }
        end
      end
      active = false
      local result = center(font, str, x, y, w, c, a)
      active = wasActive
      return result
    end
  end

  local button = Kit.button
  Kit.button = function(x, y, w, h, label, opts)
    local before = count()
    local pressed = button(x, y, w, h, label, opts)
    local entry = added(before)
    if entry then
      opts = opts or {}
      entry.role = "button"
      entry.enabled = opts.enabled ~= false
      entry.selected = opts.active or nil
      entry.invalid = opts.invalid or nil
      entry.trailing = opts.trailingIcon
    end
    return pressed
  end

  local row = Kit.row
  Kit.row = function(x, y, w, h, selected, accent, r)
    local before = count()
    local pressed = row(x, y, w, h, selected, accent, r)
    local entry = added(before)
    if entry then entry.role, entry.selected, entry.label = "row", selected or nil, "" end
    return pressed
  end

  local checkbox = Kit.checkbox
  Kit.checkbox = function(x, y, w, h, checked, label, labelColor)
    local before = count()
    local value, changed = checkbox(x, y, w, h, checked, label, labelColor)
    local entry = added(before)
    if entry then
      entry.role, entry.label, entry.checked = "checkbox", tostring(label), value and true or false
    end
    return value, changed
  end

  local textfield = Kit.textfield
  Kit.textfield = function(id, x, y, w, h, value, placeholder, opts)
    local before = count()
    local result = textfield(id, x, y, w, h, value, placeholder, opts)
    local entry = added(before)
    if entry then
      entry.role, entry.id, entry.label, entry.value = "field", id, placeholder or "", result
      entry.invalid = opts and opts.invalid or nil
    end
    return result
  end

  -- The help mark beside a value is a bare press region; it belongs to that
  -- value rather than being one more stop.
  local help = Touch.help
  Touch.help = function(S, kit, title, message, x, y)
    frame.helpTitle = title
    local result = help(S, kit, title, message, x, y)
    frame.helpTitle = nil
    return result
  end

  -- Controls drawn without a Kit widget call Kit.press directly.
  local press = Kit.press
  Kit.press = function(x, y, w, h)
    if active and not Kit.blockClicks then
      local entries = Kit.audit
      local known = false
      for i = #entries, math.max(1, #entries - 2), -1 do
        local entry = entries[i]
        if entry.class ~= "text" and entry.x == x and entry.y == y and entry.w == w and entry.h == h then
          known = true
          break
        end
      end
      local width, height = love.graphics.getDimensions()
      -- a scrim covering the window only means "tap outside to close"
      if not known and not (w >= width * 0.9 and h >= height * 0.9) then
        entries[#entries + 1] = { class = frame.helpTitle and "help" or "press", role = "button",
          x = x, y = y, w = w, h = h, label = "", clip = Kit._clipRect, enabled = true }
      end
    end
    return press(x, y, w, h)
  end

  local scrollPixels = Kit.scrollPixels
  Kit.scrollPixels = function(x, y, w, h, offset, contentH)
    local result = scrollPixels(x, y, w, h, offset, contentH)
    if active and not Kit.blockClicks then
      local scrollers = frame.scrollers
      scrollers[#scrollers + 1] = { x = x, y = y, w = w, h = h, offset = result,
        max = math.max(0, (contentH or 0) - math.max(0, h)) }
    end
    return result
  end

  local capture = {}

  function capture.begin()
    active = true
    frame.scrollers, frame.full = {}, {}
    Kit.audit = {}
  end

  -- Ends the frame; returns the items in reading order.
  -- `skip` is a rectangle whose text is not worth reading (a number wheel).
  function capture.finish(skip)
    active = false
    local entries = Kit.audit or {}
    Kit.audit = nil
    if skip then
      local kept = {}
      for _, entry in ipairs(entries) do
        if not (entry.class == "text" and inside(skip, entry.x + 1, entry.y + 1)) then kept[#kept + 1] = entry end
      end
      entries = kept
    end
    return Capture.build(entries, frame.scrollers)
  end

  return capture
end

local function scrollerOf(scrollers, x, y)
  local best
  for _, scroller in ipairs(scrollers) do
    if scroller.max > 0 and inside(scroller, x, y) and (not best or scroller.w * scroller.h < best.w * best.h) then
      best = scroller
    end
  end
  return best
end

local function contains(haystack, needle)
  return haystack:lower():find(needle:lower(), 1, true) ~= nil
end

local function trim(str)
  return (str:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- Pure: audit entries (controls and text, in draw order) to reading items.
--   { text = "...", x, y }                         something to read
--   { control = true, label, role, x, y, id, ... } something to activate; x, y
--                                                  is a point that hits it
function Capture.build(entries, scrollers)
  local controls = {}
  for _, entry in ipairs(entries) do
    if entry.class ~= "text" then
      local x, y, w, h = bounds(entry.x, entry.y, entry.w, entry.h, entry.clip)
      if w > 0 and h > 0 then
        entry.hit = { x = x, y = y, w = w, h = h }
        controls[#controls + 1] = entry
      end
    end
  end

  -- Text inside a control belongs to it, whichever was drawn first.
  -- A row cut by its list's edge still owns the text past the cut.
  local function owner(text)
    local px, py = text.x + 1, text.y + (text.h or 0) / 2
    local found
    for _, control in ipairs(controls) do
      if inside(control, px, py) then found = control end
    end
    return found
  end

  local items = {}
  local lastText
  for _, entry in ipairs(entries) do
    if entry.class == "text" then
      local str = trim(entry.str)
      -- mouse advice, wrong under this keyboard scheme
      if str:find("^Ctrl%+S save") or str == "Roll the numbers to fine-tune" then str = "" end
      local control = str ~= "" and owner(entry)
      if control then
        control.inner = control.inner or {}
        control.inner[#control.inner + 1] = str
      elseif str ~= "" then
        local sameLine = lastText and math.abs(lastText.y - entry.y) < 3
        local nextLine = lastText and math.abs(lastText.x - entry.x) < 2
          and entry.y > lastText.y and entry.y - lastText.y <= (entry.h or 0) * 1.6
        if sameLine then
          lastText.text = lastText.text .. ", " .. str
        elseif nextLine then
          lastText.text, lastText.y = lastText.text .. " " .. str, entry.y
        else
          lastText = { text = str, x = entry.x, y = entry.y }
          items[#items + 1] = lastText
        end
      end
    elseif entry.hit then
      lastText = nil
      if entry.class == "help" then
        local previous = items[#items]
        if previous and previous.entry then previous.help = entry.hit end
      else
        items[#items + 1] = { entry = entry }
      end
    end
  end

  -- Now that all text is assigned, name the controls.
  local out = {}
  for _, item in ipairs(items) do
    local entry = item.entry
    if not entry then
      out[#out + 1] = item
    else
      local label = tostring(entry.label or "")
      -- a field's text is its value, spoken as such
      for _, inner in ipairs(entry.role ~= "field" and entry.inner or {}) do
        if label == "" then label = inner
        elseif not contains(label, inner) then label = label .. ", " .. inner end
      end
      local id = entry.id and tostring(entry.id)
      -- A slider's click sets a value from where it lands, and the box beside
      -- it edits the same number; a bare region with no words is decoration.
      if label ~= "scrollbar" and not (id and id:find("^slider%-")) and (label ~= "" or entry.role == "field") then
        -- a value box or dropdown shows only its value; its name is the line above
        local previous = out[#out]
        if previous and not previous.control and id
            and (id:find("^value%-") or id:find("^choice%-")) and not label:find(":", 1, true) then
          label = label ~= "" and (previous.text .. ": " .. label) or previous.text
          out[#out] = nil
        end
        -- each Pokédex card repeats these two toggles; name the species
        if label == "Seen" or label == "Owned" then
          for back = #out, math.max(1, #out - 3), -1 do
            if not out[back].control then
              label = out[back].text .. " " .. label
              break
            end
          end
        end
        local hit = entry.hit
        local x, y = hit.x + hit.w / 2, hit.y + hit.h / 2
        out[#out + 1] = {
          control = true, label = label, role = entry.role or "button", id = id,
          enabled = entry.enabled ~= false, selected = entry.selected, invalid = entry.invalid,
          checked = entry.checked, value = entry.value, trailing = entry.trailing, help = item.help,
          x = x, y = y, scroller = scrollerOf(scrollers, x, y),
        }
      end
    end
  end

  local seen = {}
  for _, item in ipairs(out) do
    local base = item.control and (item.id or item.label) or item.text
    seen[base] = (seen[base] or 0) + 1
    item.key = base .. "#" .. seen[base]
    if not item.control then item.scroller = scrollerOf(scrollers, item.x + 1, item.y + 1) end
  end
  return out
end

-- What one item sounds like.
function Capture.describe(item)
  if not item.control then return item.text end
  local parts = {}
  if item.role == "field" then
    parts[1] = item.label ~= "" and item.label or "Text"
    parts[2] = "edit"
    parts[3] = item.value ~= nil and tostring(item.value) ~= "" and tostring(item.value) or "blank"
  elseif item.role == "checkbox" then
    parts[1] = item.label
    parts[2] = item.checked and "checked" or "not checked"
  elseif item.role == "row" then
    parts[1] = item.label
  else
    parts[1] = item.label
    parts[2] = (item.trailing == "chevron-down" or item.trailing == "chevron-up") and "dropdown"
      or item.trailing == "pencil" and "edit" or "button"
  end
  if item.selected then parts[#parts + 1] = "selected" end
  if item.enabled == false then parts[#parts + 1] = "unavailable" end
  if item.invalid then parts[#parts + 1] = "invalid" end
  return table.concat(parts, ", ")
end

return Capture
