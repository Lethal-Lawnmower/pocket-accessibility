-- Hoenn menu presenters (Ruby, Sapphire, Emerald).
local Common = require("src.access.screens.gen3.Common")
local H = require("src.access.screens.gen3.HoennCommon")

local Hoenn = {}

local say, rom, sentences, position = H.say, H.rom, H.sentences, Common.position

-- ------------------------------------------------------------- OPTION
-- src/ui/game3/rse/option_menu.lua (Emerald: `_st.pages`, cart rows
-- { cart = { label, key, choices, frame } }) and rs/option_menu.lua (Ruby,
-- Sapphire: `_pages`, rows { native = i }, `_data.rows[i]`, `_pending`).
-- Both keep the engine's rows and our ACCESSIBILITY page as { label, value },
-- and CANCEL as the row after the last.

local function emeraldRow(OptionMenu, page, index)
  local row = page.rows[index]
  if not row then return say(rom("gText_OptionMenuCancel")), nil end
  local cart = row.cart
  if not cart then
    local value = row.value and H.try(row.value, OptionMenu._st.ctx)
    return say(row.label), value and say(tostring(value)) or nil
  end
  local Options = H.loaded("src.core.game3.options")
  local block = Options and H.try(Options.block, OptionMenu._st.ctx.options)
  local current = block and tonumber(block[cart.key]) or nil
  local value
  if current then
    if cart.frame then
      value = H.join({ say(rom("gText_FrameType")), tostring(current + 1) }, " ")
    else
      value = say(rom(cart.choices[current + 1]))
    end
  end
  return say(rom(cart.label)), value
end

local RUBY_KEYS = { "textSpeed", "battleScene", "battleStyle", "sound", "buttonMode", "frameType" }

local function rubyRow(Menu, page, index)
  local row = page.rows[index]
  local data = Menu._data
  if not (type(data) == "table" and type(data.rows) == "table") then return nil end
  if not row then
    local cancel = data.rows[#RUBY_KEYS + 1]
    return cancel and say(cancel.text), nil
  end
  if not row.native then
    local ctx = { session = Menu._session, game = Menu._game, options = Menu._engine }
    local value = row.value and H.try(row.value, ctx)
    return say(row.label), value and say(tostring(value)) or nil
  end
  local native = data.rows[row.native]
  if type(native) ~= "table" then return nil end
  local key = RUBY_KEYS[row.native]
  local current = type(Menu._pending) == "table" and tonumber(Menu._pending[key]) or nil
  local value
  if current then
    if key == "frameType" then
      value = H.join({ say(data.frameLabel), tostring(current + 1) }, " ")
    else
      local choice = (native.choices or {})[current + 1]
      value = choice and say(choice.text)
    end
  end
  return say(native.text), value
end

local function optionPoll(state, memo, entering, readRow, pagesOf, title)
  local ShaderFX = H.loaded("src.ui.game3.shaderfx_menu")
  if ShaderFX and H.try(ShaderFX.isOpen) then return nil end
  local Menu = state.mod
  local pages = pagesOf(Menu)
  local page = type(pages) == "table" and pages[#pages] or nil
  if type(page) ~= "table" then return nil end
  local index = page.index or 1
  local label, value = readRow(Menu, page, index)
  local newPage = page ~= memo.page
  if not entering and not newPage and memo.index == index and memo.value == value then return nil end
  if not label then return nil end
  local moved = memo.index ~= index
  memo.page, memo.index, memo.value = page, index, value
  local text
  if entering or newPage or moved then
    text = H.join({ label, value })
    if entering or newPage then
      text = sentences({ say(title(Menu, page)), H.join({ text, position(index, #page.rows + 1) }) })
    end
  else
    text = value
  end
  if not text then return nil end
  return text, true
end

Hoenn.optionEmerald = {
  matches = Common.matcher("option", "src.ui.game3.rse.option_menu"),
  poll = function(state, memo, entering)
    return optionPoll(state, memo, entering, emeraldRow,
      function(Menu) return Menu._st and Menu._st.pages end,
      function(_, page) return page.title end)
  end,
}

Hoenn.optionRuby = {
  matches = Common.matcher("option", "src.ui.game3.rs.option_menu"),
  poll = function(state, memo, entering)
    return optionPoll(state, memo, entering, rubyRow,
      function(Menu) return Menu._pages end,
      function(Menu, page) return page.top and Menu._data and Menu._data.title or page.title end)
  end,
}

Hoenn.ordered = { Hoenn.optionEmerald, Hoenn.optionRuby }

return Hoenn
