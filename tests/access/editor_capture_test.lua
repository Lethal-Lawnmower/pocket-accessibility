-- The save editor's reading order (src/access/editor/Capture.lua): which drawn
-- things become stops and what they are called.  Synthetic frames; the game half
-- is drivers/editor_tour.lua.
-- Run: luajit tests/access/editor_capture_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness")
local check, eq = T.check, T.eq

local Capture = require("src.access.editor.Capture")

local function button(label, y, extra)
  local entry = { class = "control", role = "button", label = label, x = 10, y = y, w = 100, h = 20, enabled = true }
  for k, v in pairs(extra or {}) do entry[k] = v end
  return entry
end
local function text(str, y, x)
  return { class = "text", str = str, x = x or 10, y = y, h = 10 }
end
local function spoken(entries, scrollers)
  local out = {}
  for _, item in ipairs(Capture.build(entries, scrollers or {})) do out[#out + 1] = Capture.describe(item) end
  return table.concat(out, " / ")
end

eq(spoken({ text("Trainer", 0), button("Save", 20), button("Undo", 50, { enabled = false }) }),
  "Trainer / Save, button / Undo, button, unavailable", "text and controls keep their order")

-- a row is named by the words drawn inside it, before or after it
eq(spoken({ { class = "row", role = "row", label = "", x = 0, y = 0, w = 200, h = 30, selected = true },
  text("ABRA", 5), text("Lv 5", 5, 100) }), "ABRA, Lv 5, selected", "a row reads its text")

-- a row cut by its list still owns its text past the cut
eq(spoken({ { class = "row", role = "row", label = "", x = 0, y = 90, w = 200, h = 30,
  clip = { x = 0, y = 0, w = 200, h = 100 } }, text("POTION", 102) }), "POTION", "clipped row keeps its name")

-- a value box takes its name from the line above
eq(spoken({ text("Level", 0), text("1 - 100", 0, 80), button("5", 20, { id = "value-level" }) }),
  "Level, 1 - 100: 5, button", "a value box names itself")

-- states
eq(spoken({ { class = "row", role = "checkbox", label = "EVENT_A", checked = true, x = 0, y = 0, w = 100, h = 20 } }),
  "EVENT_A, checked", "checkbox on")
eq(spoken({ { class = "control", role = "field", id = "q", label = "search", value = "", x = 0, y = 0, w = 100, h = 20 } }),
  "search, edit, blank", "empty field")
eq(spoken({ { class = "control", role = "field", id = "q", label = "search", value = "POT", x = 0, y = 0, w = 100, h = 20 },
  text("POT", 5) }), "search, edit, POT", "a field's text is its value, not its name")
eq(spoken({ button("Bag", 0, { trailing = "chevron-down" }), button("Level: 5", 30, { trailing = "pencil" }) }),
  "Bag, dropdown / Level: 5, edit", "dropdown and editable values say so")

-- not stops: a slider (a click would set a value from where it lands), a
-- scrollbar, a wordless press region, mouse advice
eq(spoken({ button("", 0, { id = "slider-level" }), button("Keep", 30),
  button("scrollbar", 60), { class = "press", role = "button", label = "", x = 0, y = 90, w = 20, h = 20 },
  text("Ctrl+S save . Ctrl+R reload", 120) }), "Keep, button", "decoration is not a stop")

-- the help mark belongs to the value beside it
do
  local items = Capture.build({ button("Level: 5", 0),
    { class = "help", role = "button", label = "", x = 120, y = 0, w = 20, h = 20 } }, {})
  eq(#items, 1, "help is not a stop")
  check(items[1].help ~= nil, "the value carries its help")
end

-- the toggles on each Pokédex card name the species
eq(spoken({ text("BULBASAUR", 0), button("Seen", 20), button("Owned", 50) }),
  "BULBASAUR / BULBASAUR Seen, button / BULBASAUR Owned, button", "dex toggles name the species")

-- keys stay apart for repeated labels; a click lands inside the visible part
do
  local items = Capture.build({ button("Max", 0), button("Max", 30),
    button("Cut", 90, { clip = { x = 0, y = 0, w = 200, h = 100 } }) }, {})
  check(items[1].key ~= items[2].key, "repeated labels get their own keys")
  eq(items[3].y, 95, "a clipped control is hit in its visible part")
end

-- which list an item scrolls with
do
  local scroller = { x = 0, y = 0, w = 200, h = 100, offset = 0, max = 50 }
  local fixed = { x = 0, y = 200, w = 200, h = 100, offset = 0, max = 0 }
  local items = Capture.build({ button("In", 10), button("Out", 150), button("Fixed", 210) }, { scroller, fixed })
  eq(items[1].scroller, scroller, "an item in a list knows it")
  eq(items[2].scroller, nil, "an item outside has none")
  eq(items[3].scroller, nil, "a region that cannot scroll does not count")
end

T.finish("editor capture")
