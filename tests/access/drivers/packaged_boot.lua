-- A game booted from a packaged folder: reports that the package's rules hold, runs
-- some frames of the real game, and quits.  Used through isolated.lua.
--   POKEPORT_DRIVER=<repo>/tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=<repo>/tests/access/drivers/packaged_boot.lua
return function(game)
  local PackagedBuild = require("src.access.PackagedBuild")
  print("[driver] packaged " .. tostring(PackagedBuild.active))
  print("[driver] source " .. tostring(love.filesystem.getSource()))
  print("[driver] saves " .. tostring(love.filesystem.getSaveDirectory()))
  print("[driver] fused " .. tostring(love.filesystem.isFused()))
  print("[driver] updater " .. tostring(require("src.update.Boot").canUpdateInPlace()))
  print("[driver] speech " .. tostring(require("src.access.Speech").status()))
  for _, name in ipairs({ "src.import.LauncherView", "src.import.LauncherSettings", "src.import.OnlinePanel",
      "src.import.CartLabelArt", "src.import.CartShape" }) do
    print("[driver] " .. name .. " loaded " .. tostring(package.loaded[name] ~= nil)
      .. " file " .. tostring(love.filesystem.getInfo(name:gsub("%.", "/") .. ".lua") ~= nil))
  end
  print("[driver] game version " .. tostring(require("src.core.GameVersion").get())
    .. " generation " .. tostring(require("src.core.GameVersion").generation()))
  for _ = 1, 600 do coroutine.yield() end
  print("[driver] phase " .. tostring(game.phase) .. " top " .. tostring(game.stack and game.stack.states and #game.stack.states))
  print("[driver] OK 600 frames")
end
