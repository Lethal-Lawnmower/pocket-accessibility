-- Runs another driver with the game window minimised and real keyboard,
-- mouse and controller input ignored.  POKEPORT_BACKGROUND only mutes the
-- game on Windows; its window can still take keyboard focus from the
-- owner's screen reader, and any real key stops auto-walk, which makes a
-- scripted walk fail at random.  The harness drives game.input directly,
-- so nothing it needs goes through these callbacks.
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/yellow_follower.lua
return function(game)
  -- a log redirected to a file keeps its lines when the run is closed at a time limit
  pcall(function() io.stdout:setvbuf("line") end)
  pcall(function() love.window.minimize() end)
  for _, callback in ipairs({ "keypressed", "keyreleased", "textinput", "gamepadpressed",
      "gamepadreleased", "gamepadaxis", "joystickpressed", "joystickreleased",
      "joystickaxis", "joystickhat", "mousepressed", "mousereleased" }) do
    love[callback] = function() end
  end
  -- driver runs skip PlatformHooks.update, where the layer normally sees
  -- the game (src/access/CurrentGame.lua)
  local CurrentGame = package.loaded["src.access.CurrentGame"]
  if CurrentGame then CurrentGame.set(game) end
  local path = os.getenv("ISOLATED_DRIVER")
  if not path then print("[driver] FAIL ISOLATED_DRIVER is not set") return end
  return dofile(path)(game)
end
