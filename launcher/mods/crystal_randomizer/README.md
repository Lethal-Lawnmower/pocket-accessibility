# Crystal Randomizer

A randomizer for Pokémon Crystal that you set up when you start a New Game. No ROM patching: it is a mod,
so it decides everything while you play, from one seed per save.

## Setting it up

Start a New Game. After you name yourself, Oak asks "Do you want your journey shuffled?" Answer NO and the
game plays as normal. Answer YES and he asks how:

- **RECOMMENDED:** a good first run. Wild Pokémon, trainers, starters, gifts and items are shuffled, gyms
  keep their types, trade evolutions work without trading, TMs are shuffled and reusable, and experience
  is 1.5 times. Types, level-up moves, stats, evolutions and shops stay as they are.
- **EVERYTHING:** turns on everything except the HM shuffle.
- **CHOOSE EACH:** asks every question one at a time.

Then he tells you your seed, a six-digit number. The answers and the seed are kept in that save, so the
randomized world stays the same all game. Other saves are not affected.

Version 0.2.0 shuffles more evenly. In earlier versions, choices for neighbouring spots (one route's grass
slots, one trainer's team) were related to each other, and with a type triangle a few starters, such as
Geodude, Larvitar and Chikorita, came up far more often than the rest. A New Game from 0.2.0 on uses the new
shuffling. A save started earlier keeps its world exactly as it was, so a run in progress never changes; the
same seed number gives a different world in a new save than it did in an old one.

## The questions (CHOOSE EACH)

| Area | Questions |
|---|---|
| Wild POKéMON | Shuffle them? One swap per route, per whole game, or any slot? Keep them about as strong? Keep each route's type theme? Put every POKéMON in the wild? Wild level percent? |
| Trainers | Shuffle their POKéMON? Keep them about as strong? Gyms and the Elite Four keep one type? Fully evolved from what level? Trainer level percent? |
| Starters and gifts | Shuffle the starters? Three stages? A type triangle? Shuffle gift and static POKéMON? Legendaries stay legendary? |
| Evolutions | Trade evolutions without trading? Shuffle what POKéMON evolve to? Keep a type in common? |
| Items | Shuffle items on the ground? Hidden items too? Shuffle where HMs are found? |
| Doors | Shuffle where doors lead? Off, houses, caves, or everything |
| TMs | Shuffle what TMs teach? Who can learn each? Use TMs more than once? |
| Shops | Shuffle what marts sell? Better marts? |
| POKéMON | Shuffle types? Moves learned by level? Base stats (reorder or reroll)? Attacks' power, accuracy and type? |
| Comfort | How much EXP.? Make rare POKéMON easier to catch? Battle trainers only if you talk to them? |

## What each does

- **Wild:** never replaces a species with itself or with one already on that route. Unown stays, so the
  Ruins of Alph work, and legendaries are never wild replacements. "Every POKéMON in the wild" places all
  239 eligible species somewhere (145 in the one-swap-per-game mode, which is limited to the species the
  game's tables hold).
- **Trainers:** party size and held items are kept; levels follow the level percent. Each POKéMON knows
  the moves it would at its level. Your rival's starter is the one strong against yours, and his team
  follows it. Gym leaders' themes: Falkner flying, Bugsy bug, Whitney normal, Morty ghost, Chuck fighting,
  Jasmine steel, Pryce ice, Clair and Lance dragon, the Elite Four theirs, and Kanto's leaders theirs;
  Blue gets one random type per save.
- **Starters:** three different first-stage species; Elm names the new one and its type.
- **Gifts and statics:** Eevee, Dratini, Tyrogue, the Togepi egg, Lapras, Sudowoodo, Snorlax, the red
  Gyarados, the Team Rocket traps, and the legendaries, which become other legendaries.
- **Trade evolutions:** Kadabra, Machoke, Graveler and Haunter evolve at level 37. Onix and Scyther evolve
  when you use a METAL COAT on them, Poliwhirl and Slowpoke a KING'S ROCK, Seadra a DRAGON SCALE, and
  Porygon an UP-GRADE.
- **Items:** item balls swap contents with item balls, hidden items with hidden items; key items and HMs
  never move with them.
- **HMs (CHOOSE EACH only):** the seven HMs swap places among their own seven spots, only in orders that
  keep the game beatable, and the person who gives one names the one you get.
- **Doors (CHOOSE EACH only):** houses swap with houses; caves also swap with caves; everything swaps any
  door with any other. Story places never move (Elm's lab, gyms, the Radio Tower, the towers, Ilex Forest,
  Victory Road, the League and more), and only arrangements that keep the game beatable through the
  League are used. Leaving a building returns you to the door you came in by, and Escape Rope, Dig,
  blacking out and Teleport follow the shuffled doors. Navigation names each door by where it leads now.
  Kanto after the League is not checked.
- **TMs:** each TM teaches a new move (HMs never change); HEADBUTT and ROCK SMASH stay on some TM so trees
  and rocks still work. Navigation names a TM by its number and the move it teaches now.
- **Shops:** every general mart sells POKé BALLs and POTIONs, even Cherrygrove's from the start.
- **Comfort:** the catch floor makes everything at least as easy to catch as Pidgeotto. Blind trainers
  still battle when you talk to them, and story battles still happen.

## Not changed

The roaming Raikou and Entei, Shuckie and the Odd Egg, fruit trees, items people hand you (other than HMs),
Game Corner prizes, the Bargain Shop and the Battle Tower. A static POKéMON keeps its original look on
the map, and navigation may name it by that look. A TM's description and Falkner's "a TM can be used only
once" are the original words. A link battle or trade with a randomized save uses that save's own data.

## Install

Pocket Accessibility's releases bring this mod, turned off, from the release after 0.0.2 (decision 61): turn it on
for Crystal in the launcher's Mods list before a New Game. By hand: copy this folder, without its `tests` folder, into the `mods` folder of your save folder as
`crystal_randomizer`. On Windows that is `%APPDATA%\LOVE\pokemon-love2d\mods`. It needs the "patches
engine code" permission. A save started with version 1 keeps its version 1 world.

`CONTRACT.md` explains how the pieces fit, for anyone extending it.
