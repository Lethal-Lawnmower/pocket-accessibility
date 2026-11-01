# FireRed and LeafGreen: navigation

Gen 3 differences for navigation (decisions 29 and 30). Gen 1 behaviour is
in `navigation.md`; Gen 3 screens and open questions are in
`firered-leafgreen.md`. FireRed only: LeafGreen is deferred, and the
adapter enables FireRed alone until a LeafGreen dump is checked.

## How it works

The shared navigation runs through a coordinator subclass, `nav/gen3/`,
and a third `WorldAdapter` entry: the Gen 2 pattern.

- **No world object, no stack.** One facade over the field singletons
  (runtime, field, player, collision, map, objects). The game is found
  through `CurrentGame` or the Gen 3 runtime, only once a session exists.
  "Free on the map" follows the gates of the game's own player update
  (help, HUD, field locks, scripts, step events, ferry, fishing), adapted
  from the old project's field-input classifier (decision 20). A warp is a
  transition; during a battle the top is a fixed battle marker, so auto-walk
  pauses and resumes. The coordinator is bound to the session (FireRed
  replaces `game.save` on every save). Options come from the game's own
  block (`game.options.firered`), never the root Red shares.
- **Map views** (`gen3/World.lua`) read collision, metatile behaviour,
  elevation (0 and 15 match anything, as in Pokémon Access), water,
  directional walls and active warps, cached per cell until the layout
  changes. Warps get a kind: door (entered moving up), exit mat, arrow or
  stair (fire only while pressed in their direction, so they can be walked
  across), escalator, hole, pad.
- **Labels never come from ROM addresses** (`gen3/Scripts.lua` reads what
  a script does, never runs it): item balls by their item; signs by role
  (Card Key Door, Secret Switch, Quiz Machine, Trash Can, Floor Panel, PC,
  Braille, Fossil Display, Records, Teleporter); people by their graphics,
  the rival's sheet by the rival's name; invisible objects and hidden items
  are not listed. Map names are the id without `FR_` ("RED's House 2F").
  Exit mats, arrows and stairs read "Continue <direction> to ...".
- **Routing:** ledges, Surf ("enter water", "exit water"), Cut trees and
  Rock Smash rocks (objects with what they need: "Cuttable Tree; Needs Cut
  and Cascade Badge"), Waterfall, forced chains for ice, spinners (until a
  stop tile), currents and moving floors; connection goals only at edge
  cells the game lets the player cross.
- **Map names on entry** are left to the game's own popup (spoken by screen
  speech) wherever it shows; navigation announces the others; M works
  everywhere. Q says "FireRed has no clock". H and Shift+H read the battle
  (`battle.md`).
- **Strength puzzles** (`gen3/PuzzleAssistance.lua`): boulders, switches
  (behaviour 0x20) and holes (0x66) from the map; a whole-floor plan
  (weighted search over pushes); when the search runs out of time it gives
  no hint rather than a push that could block the rest.
- **Fixes shared with Gen 1 and 2:** auto-walk counts the battle marker as
  a battle; navigation rebinds by the adapter's identity; command gating
  and the camera option read each generation's own state.

Pokémon Access behaviour adopted (no code or text copied): the elevation
rule, water entry and exit steps, Strength switches as objects, the cue
beside a jumpable ledge, warps listed only when the game fires them.

## Verification (2026-11-01)

| Area | Level reached |
|---|---|
| Unit tests | `gen3_nav_test.lua` 70/70; every access suite passes; old navigation suites unchanged (known gaps 12/13 and 71/92); Gen 2 cartridge test 35/35 on the Crystal cache. |
| FireRed runs (identity `pocket-access-nav-firered`) | Bedroom to Pallet Town by auto-walk; guided navigation to Route 1 and Viridian with wild battles pausing and resuming the walk; Route 1 at 200X over four ledges (speed handed back after); Nugget Bridge, five trainers, "Resuming walk" after each; Surf from Pallet Town to Route 21 through the game's prompt; Rocket Hideout B2F by spinner chains; Silph Co. 5F card key door (the harness set the key's flag); Victory Road 1F switch from the hints alone, 19 pushes. |
| Label sweep | 418 maps, 3787 labels, none bad; 1015 active warps; 18 dynamic warps (elevators, link rooms) read "Exit". Victory Road 1F to 3F and Seafoam 1F solved from the hints in a sweep before the last warp fix (not rerun). |
| Gen 1 and Gen 2 after the merge (lead) | Red auto-walk battle and elevators, Yellow follower (identical to baseline), Crystal `gen2_nav.lua`: all clean. |
| Heard by the owner | Not yet. |

## Known gaps

- Cross-map journeys: Silph Co. 1F to the Card Key runs out of planning
  time; Rocket Hideout B2F to B4F and Silph 4F to 5F said "No route" (may
  be real gates; not checked).
- An uncollected item ball blocks routes past it.
- The Tanoby Key room needs about 6 seconds of search: no hint.
- Renaming (Shift+K, Shift+M) is not wired; Seagallop ferry legs are not
  part of journeys.
- Not run in game: Icefall Cave ice, Seafoam currents, Pokémon Mansion
  switches, waterfalls.
- Owner question: about 187 windows plus lights and cups are listed as
  objects; too noisy?
