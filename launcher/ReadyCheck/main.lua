-- Asks the game's own cache check (src/import/CacheContract.lua, the one
-- the game runs before it boots) whether each game is imported, and writes
-- one line per game to the file named by POCKET_READY_OUT:
--   red=ready | red=missing | red=error <message>
-- POCKET_GAME_DIR names the game folder whose code is used.  A cache from an
-- older build (format changed, files added) reads "missing", so the
-- launcher offers an import instead of starting a game that would fall back
-- to upstream's launcher.

local GAMES = { "red", "blue", "yellow", "gold", "silver", "crystal",
  "firered", "leafgreen", "ruby", "sapphire", "emerald" }

function love.load()
  local out = os.getenv("POCKET_READY_OUT")
  local gameDir = os.getenv("POCKET_GAME_DIR")
  local lines = {}
  if not (out and gameDir) then
    lines[1] = "error POCKET_READY_OUT and POCKET_GAME_DIR must be set"
  else
    local dir = gameDir:gsub("\\", "/")
    package.path = dir .. "/?.lua;" .. dir .. "/?/init.lua;" .. package.path
    local ok, CacheContract = pcall(require, "src.import.CacheContract")
    local okFs, CacheFs = pcall(require, "src.import.CacheFs")
    for _, id in ipairs(GAMES) do
      if not (ok and okFs) then
        lines[#lines + 1] = id .. "=error " .. tostring(ok and CacheFs or CacheContract):gsub("\n", " ")
      else
        local checked, ready = pcall(CacheContract.isReady, id, CacheFs)
        if not checked then
          lines[#lines + 1] = id .. "=error " .. tostring(ready):gsub("\n", " ")
        else
          lines[#lines + 1] = id .. "=" .. (ready and "ready" or "missing")
        end
      end
    end
  end
  if out then
    local file = io.open(out, "w")
    if file then
      file:write(table.concat(lines, "\n"), "\n")
      file:close()
    end
  end
  love.event.quit()
end
