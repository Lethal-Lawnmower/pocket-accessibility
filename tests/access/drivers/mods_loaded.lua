-- What the game's own mod loader made of the mods folder: read the RESULT lines to
-- see that a mod installed by the launcher's Mods window (launcher/ModBackend,
-- ModInstaller.cs) is found, and that its on and off reach the loader.  Silent.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  U.wait(30)
  local ids = {}
  for id in pairs(game.mods.mods) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local mod = game.mods.mods[id]
    U.log("RESULT", id, "enabled", tostring(mod.enabled), "state", tostring(mod.state),
      "skip", tostring(mod.skipReason), "path", tostring(mod.path))
  end
  for _, problem in ipairs(game.mods.errors) do U.log("RESULT", "error", tostring(problem)) end
  U.log("DONE")
end
