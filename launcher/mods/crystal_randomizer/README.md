# Crystal Randomizer

A randomizer for Pokémon Crystal that you set up when you start a New Game. No ROM patching: it is a mod,
so it decides everything while you play, from one seed per save.

## How it works

Start a New Game. After you name yourself, Oak asks "Do you want your adventure shuffled?" Answer NO and
the game plays as normal. Answer YES and he asks, one at a time:

1. Shuffle wild POKéMON? Then: keep them about as strong?
2. Shuffle trainers' POKéMON? Then: keep them about as strong?
3. Shuffle the starter POKéMON? And: shuffle gift and static POKéMON?
4. Shuffle the items on the ground? Then: shuffle hidden items too?
5. Shuffle POKéMON types? And: shuffle moves learned by level?

Then he tells you your seed, a six-digit number. The answers and the seed are kept in that save, so the
randomized world stays the same all game. Another save, or a save made without the randomizer, is not
affected.

## What it changes

- **Wild POKéMON:** grass at every time of day, surfing, all three rods, headbutt trees, Rock Smash, swarms
  and the Bug-Catching Contest. On each route, each original species becomes one new species for the whole
  save. Levels are kept. Unown stays, so the Ruins of Alph work, and legendaries never appear as wild ones.
- **Trainers:** every trainer, including gym leaders, the Elite Four, Lance, Red and your rival. Party
  size, levels and held items are kept; each POKéMON knows the moves it would at that level. Your rival's
  team follows the starter he took and evolves with it.
- **Starters:** Elm's three balls hold three different first-stage species, and Elm names the new one and
  its type.
- **Gifts and static POKéMON:** Eevee, Dratini, Tyrogue, the Togepi egg, Lapras, Sudowoodo, Snorlax, the red
  Gyarados, Ho-Oh, Lugia, Suicune, Celebi and the Team Rocket traps. Levels are kept.
- **Items:** the contents of item balls are shuffled among item balls, and hidden items among hidden items.
  Key items and HMs never move.
- **Types and moves:** each evolution family gets new types, and level-up moves are shuffled while every
  POKéMON keeps a usable attack. TM and HM moves are not changed, so the story's field moves still work.

## Not changed yet

The roaming Raikou and Entei, Shuckie and the Odd Egg, items people hand you, fruit trees, Game Corner
prizes, and the Battle Tower. On overworld sprites, a static POKéMON keeps its original look, and
navigation may name it by that look. A link battle or trade with a randomized save uses that save's own
types and moves, which the other player does not have.

## Install

Copy this folder, without its `tests` folder, into the `mods` folder of your save folder as
`crystal_randomizer`. On Windows that is `%APPDATA%\LOVE\pokemon-love2d\mods`. It needs the "patches
engine code" permission.

`CONTRACT.md` explains how the pieces fit, for anyone extending it.
