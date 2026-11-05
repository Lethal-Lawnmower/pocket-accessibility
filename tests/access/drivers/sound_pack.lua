-- The Pokémon Access sounds the launcher imported: each game's cues find the pack in the save
-- folder, and every mapped cue with a file there loads.  Plays nothing.  Needs a pack copied to
-- pocket-access-sounds in the identity.  Silent; read the RESULT and FAIL lines.
return function(game)
  local version = os.getenv("POKEPORT_VERSION") or "red"
  local isGen3 = version == "firered" or version == "leafgreen" or version == "ruby"
    or version == "sapphire" or version == "emerald"
  local isGen1 = version == "red" or version == "blue" or version == "yellow"
  local L = dofile(isGen3 and "tests/access/drivers/gen3_nav_lib.lua"
    or "tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local started
  if isGen3 then started = L.boot()
  elseif isGen1 then started = U.newGame(game)
  else started = L.settle(2000, true) end
  if not started then U.log("FAIL", "never reached the free world") return end
  U.wait(30)
  local Earcons = require("src.access.nav.Earcons")
  local nav = require("src.access.nav").coordinator()
  local path = nav and nav.earcons and nav.earcons.soundPackPath
  U.log(path and tostring(path):find("pocket%-access%-sounds") and "RESULT" or "FAIL", "the game's cues use the pack:", tostring(path))
  local loaded, missing = 0, {}
  for id, relative in pairs(Earcons.SOUND_FILES) do
    local file = io.open(tostring(path) .. "/" .. relative, "rb")
    if file then
      local bytes = file:read("*a")
      file:close()
      local ok = pcall(love.audio.newSource, love.filesystem.newFileData(bytes, relative), "static")
      if ok then loaded = loaded + 1 else U.log("FAIL", "would not load", relative) end
    else
      missing[#missing + 1] = id
    end
  end
  table.sort(missing)
  U.log("RESULT", "cues with a loadable pack file:", loaded, "falling back to built-in:", table.concat(missing, " "))
  U.log("DONE")
end
