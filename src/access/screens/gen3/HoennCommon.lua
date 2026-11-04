-- Reading helpers shared by the Hoenn presenters (Ruby, Sapphire, Emerald).
-- A read that fails stays silent: every helper returns nil rather than a
-- guess, and every value comes from the screen's own fields or from the same
-- cart text keys its draw code uses.

local Menus = require("src.access.screens.gen3.Menus")

local H = {}

function H.loaded(path) return package.loaded[path] end

function H.try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c
end

local function nonEmpty(text)
  if text == nil or text == "" then return nil end
  return text
end
H.nonEmpty = nonEmpty

function H.say(text)
  if text == nil then return nil end
  return nonEmpty(Menus.speakable(text))
end

function H.sentences(parts)
  return nonEmpty(Menus.sentences(parts))
end

function H.join(parts, sep)
  local out = {}
  for i = 1, table.maxn(parts) do
    local part = parts[i]
    if part ~= nil and part ~= "" then out[#out + 1] = tostring(part) end
  end
  return nonEmpty(table.concat(out, sep or ", "))
end

function H.rom(key, ctx)
  local RomText = package.loaded["src.core.game3.rom_text"]
  if not (RomText and key) then return nil end
  local ok, text = pcall(RomText.plain, key, ctx)
  if ok and type(text) == "string" then return text end
  return nil
end

function H.romAt(name, index, ctx)
  local RomText = package.loaded["src.core.game3.rom_text"]
  if not (RomText and name) then return nil end
  local ok, text = pcall(RomText.at, name, index, nil, ctx)
  if ok and type(text) == "string" then return text end
  return nil
end

function H.romHas(key)
  local RomText = package.loaded["src.core.game3.rom_text"]
  return RomText ~= nil and H.try(RomText.has, key) == true
end

-- Speakable cart text, from the first key this game has.
function H.first(keys, ctx)
  for _, key in ipairs(keys) do
    if H.romHas(key) then
      local text = H.say(H.rom(key, ctx))
      if text then return text end
    end
  end
  return nil
end

-- YES or NO by the game's own text; 1 YES, 2 NO.
function H.yesNo(cursor)
  if cursor == 1 then return H.first({ "gText_Yes", "OtherText_Yes" }) or "YES" end
  if cursor == 2 then return H.first({ "gText_No", "OtherText_No" }) or "NO" end
  return nil
end

-- A text printer of rse/scene_kit.lua as pages: "para", "scroll" and "wait"
-- each wait for a button.  Returns the page strings and the first token of
-- each page, from the tokens the printer will type.
local function printerPages(printer)
  local pages, starts, line = {}, { 1 }, {}
  local function close(pos)
    pages[#pages + 1] = table.concat(line)
    line = {}
    starts[#starts + 1] = pos
  end
  for i, tok in ipairs(printer.toks or {}) do
    if tok.t == "c" then line[#line + 1] = tok.s
    elseif tok.t == "nl" then line[#line + 1] = "\n"
    elseif tok.t == "para" or tok.t == "scroll" or tok.t == "wait" then close(i + 1) end
  end
  pages[#pages + 1] = table.concat(line)
  local kept, keptStarts = {}, {}
  for i, page in ipairs(pages) do
    if page:find("%S") then
      kept[#kept + 1] = page
      keptStarts[#keptStarts + 1] = starts[i]
    end
  end
  return kept, keptStarts
end

-- The page of a printer that has started, spoken once, or every page at once
-- when DIALOGUE SPEECH is ALL AT ONCE.  `memo` may be any table: the state
-- for each printer object is kept in it.
function H.printerSay(printer, memo, game)
  if type(printer) ~= "table" or type(printer.toks) ~= "table" then return nil end
  local own = memo.printerState
  if not own or own.printer ~= printer then
    local pages, starts = printerPages(printer)
    own = { printer = printer, pages = pages, starts = starts, speech = {} }
    memo.printerState = own
  end
  local page = 1
  for i, start in ipairs(own.starts) do
    if (printer.pos or 1) >= start then page = i end
  end
  return Menus.printerSpeech(own.pages, page, own.speech, game)
end

return H
