# PC Clock

A mod for Gold, Silver, Crystal, Ruby, Sapphire and Emerald: the game always uses your device's clock.

## Gold, Silver and Crystal

- Oak's "What time is it?" and Mom's "What day is it?" are answered for you with your device's time and
  day, and your screen reader says what was set.
- The game's time and weekday follow the device from then on, daylight saving included, even on a save
  where the clock was set wrong before.
- Mom's "Is it Daylight Saving Time now?" is answered from your device too, and her "is that OK?" after it,
  and your screen reader says which answer was given.
- Switching the mod off brings back whatever clock the save had: the mod never changes it in the save.

## Ruby, Sapphire and Emerald (version 1.1.0)

- The wall clock you set at the start of the game opens on your device's time and is confirmed for you, and
  your screen reader says what was set.
- The game's time of day follows the device from then on, daylight saving included, even on a save where
  the clock was set wrong, or one moved from a cartridge whose clock was off. Time-of-day events, such as
  Shoal Cave's tide, evolutions by day or night and Match Call times, use it.
- The game's own day count (berries, the lottery and other daily events) keeps counting from where your
  save had it. On a save whose clock was set wrong, the first start with the mod can bring one day's events
  a little early, or make berries wait a few hours; no day is lost or repeated.
- The title screen's clock reset is left as it is; with the mod on, it has no effect on the time of day.
- Switching the mod off brings back whatever clock the save had.

It needs the "patches engine code" permission, because it changes how the game reads its clock.

## Install

Pocket Accessibility's releases bring this mod, on, from the release after 0.0.2 (decision 61); it is in the
launchers' Mods list, where it can be turned off or removed. By hand: copy this folder into the `mods` folder of your save folder, as `pocket_pc_clock`, or install it with the
launcher's Mods window. On Windows the save folder is `%APPDATA%\LOVE\pokemon-love2d`.
