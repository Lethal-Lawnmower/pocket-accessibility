-- Shared reading helpers for the Gen 2 presenters (decision 27).
--
-- Gold, Silver and Crystal run on the same StateStack as Gen 1, so
-- ScreenReader already polls their screens; only the presenters differ.
-- Gen 2 screens are classes under src/ui/gen2/, matched by metatable like
-- the Gen 1 ones.  Many of them type their own message box with
-- src/ui/gen2/Typer.lua instead of pushing a TextBox; `Common.typerText`
-- reads that pattern.

local Common = {}

-- Presenters loads the Gen 2 modules at the end of its own load, so it is
-- looked up lazily rather than required here (a require would loop).
local function presenters()
  return package.loaded["src.access.screens.Presenters"] or require("src.access.screens.Presenters")
end

-- Matches instances of src/ui/gen2/<name>.lua.  Looked up in package.loaded,
-- so speech never loads a screen module before the game does.
function Common.matcher(name)
  local path = "src.ui.gen2." .. name
  return function(state)
    local mod = package.loaded[path]
    return mod ~= nil and getmetatable(state) == mod
  end
end

function Common.position(index, count)
  return string.format("%d of %d", index, count)
end

-- Gen 2 strings carry a few text commands and ligatures a screen reader
-- cannot say: '#' is the POKé command (src/render/Font.lua MACRO_TEXT),
-- <PO><KE> spells POKé in the start menu's POKéGEAR, <LV> and <ID> are the
-- level and ID marks.  Layout commands (<NEXT>, <LINE>, ...) become spaces.
-- Any other <TOKEN> left over is dropped rather than spelled out.
local TOKENS = {
  ["<PO><KE>"] = "POKé", ["<LV>"] = "level ", ["<ID>"] = "ID ",
  ["<PK><MN>"] = "PKMN", ["<PK>"] = "PK", ["<MN>"] = "MN",
}
function Common.speakable(text)
  if type(text) == "table" then text = presenters().joinLines(text) end
  text = tostring(text or "")
  for token, words in pairs(TOKENS) do
    text = text:gsub(token:gsub("%p", "%%%0"), words)
  end
  text = text:gsub("#", "POKé")
  text = text:gsub("<NEXT>", " "):gsub("<LINE>", " "):gsub("<CONT>", " "):gsub("<PARA>", " ")
  text = text:gsub("<[%u_]+>", "")
  text = text:gsub("№", "number ")
  return (presenters().speakable(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A list of lines (or one string) as one sentence, split words rejoined.
function Common.lines(lines)
  if type(lines) ~= "table" then return Common.speakable(lines) end
  return Common.speakable(presenters().joinLines(lines))
end

-- The Typer message pattern (src/ui/gen2/Typer.lua): `state.typer.page` is
-- the current page's lines after substitution, replaced by a new table on
-- each page.  Returns the page as one sentence the first time a page table
-- is seen (memo[key] holds the last one), else nil.  The page is spoken
-- whole as soon as typing starts, like a TextBox chunk.
function Common.typerText(state, memo, key)
  key = key or "typerPage"
  local typer = state and state.typer
  local page = typer and typer.page
  if type(page) ~= "table" or page == memo[key] then return nil end
  memo[key] = page
  local text = Common.lines(page)
  if text == "" then return nil end
  return text
end

-- The selected row of a src/ui/gen2/Chrome.lua List (fields `items`,
-- `index`; rows carry `label`).
function Common.listRow(list)
  local item = list and list.items and list.items[list.index]
  if type(item) ~= "table" then return nil end
  return Common.speakable(item.label)
end

return Common
