-- The windowless save backend the launcher's native save editor talks to
-- (docs/access/save-editor.md).  Same save folder (identity) as the game, so it
-- edits the same saves and reads the same ROM caches; no window, so it never
-- takes focus from the player's screen reader.
function love.conf(t)
  t.identity = os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d"
  t.version = "11.5"
  t.console = false
  t.window = false
  t.modules.window = false
  t.modules.graphics = false
  t.modules.audio = false
  t.modules.sound = false
  t.modules.joystick = false
  t.modules.keyboard = false
  t.modules.mouse = false
  t.modules.touch = false
  t.modules.physics = false
  t.modules.video = false
  t.modules.font = false
  t.modules.image = false
end
