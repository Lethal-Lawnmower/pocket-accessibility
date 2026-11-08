# PC Clock

A mod for Gold, Silver and Crystal: the game always uses your device's clock.

- Oak's "What time is it?" and Mom's "What day is it?" are answered for you with your device's time and
  day, and your screen reader says what was set.
- The game's time and weekday follow the device from then on, daylight saving included, even on a save
  where the clock was set wrong before.
- Mom still asks whether it is daylight saving time. In this port that answer is stored but never moves the
  clock, so either answer is fine.
- Switching the mod off brings back whatever clock the save had: the mod never changes it in the save.

It needs the "patches engine code" permission, because it changes how the game reads its clock.

## Install

Copy this folder into the `mods` folder of your save folder, as `pocket_pc_clock`, or install it with the
launcher's Mods window. On Windows the save folder is `%APPDATA%\LOVE\pokemon-love2d`.
