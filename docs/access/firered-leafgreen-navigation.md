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
  cells the game lets the player cross. A step onto ice that cannot slide
  is a plain step.
- **Item balls** block like any object (as in Gen 1 and Gen 2) and are gone
  once taken. Walking (policy 1) goes round one; only when there is no way
  round does policy 2 go through it: "Pick up Potion facing right, then
  move right"; auto-walk faces it and presses A, the pickup message pauses
  the walk and it resumes past the ball (a full bag stops it). A gift Poké
  Ball (no item-ball script) is never walked through.
- **Card key doors:** on the map the player is on, a door is closed while
  its cells are not floor. A planned floor's layout draws every door open
  (the floor's load script closes those whose own flag is unset), so there
  the door's own flag (the first its script checks) decides.
- **Journeys** (decision 25) use FireRed's own planner
  (`journeySearch`): one search over the cells of every map of the area
  (maps sharing the area key, plus the player's map), the same movement
  graph as a walked route, warps and connections as edges between maps.
  The shared planner ran a route search per transition and ran out of time
  on FireRed's many-warp floors. Walking first, then what the party can
  (policy 2, as auto-walk); when only a missing field move or the Card Key
  would open the way, the answer says so ("Needs Card Key"), as Gen 1 does
  on one map. Area target cells are worked out on the starting floor, so
  the final leg keeps only those inside the target floor. Elevators (a
  floor menu) and the Seagallop ferry (a sailor's menu) are not journey
  legs, as in Gen 1 and Gen 2; an Area target never needs the ferry, since
  each island is its own area.
- **Map names on entry** are left to the game's own popup (spoken by screen
  speech) wherever it shows; navigation announces the others; M works
  everywhere. Q says "FireRed has no clock". H and Shift+H read the battle
  (`battle.md`).
- **Strength puzzles** (`gen3/PuzzleAssistance.lua`): boulders, switches
  (behaviour 0x20) and holes (0x66) from the map; a whole-floor plan
  (weighted search over pushes, estimated by push distances). The whole
  plan is kept and followed push by push while the boulders stand where it
  has them. A search longer than one request (0.3 seconds) carries on in
  slices of each frame (6 ms) on that floor; meanwhile switches say "still
  working out a boulder plan; ask again in a few seconds" and no push is
  offered. The Tanoby Key room (seven boulders, seven switches) is planned
  in about a second of search (30 to 32 pushes); it took six with the old
  estimate and a fresh search after every push.
- **Renaming** (Shift+K, Shift+M) opens FireRed's own naming screen (box
  keyboard, titled "Object name?" or "Map name?", up to 10 characters,
  starting from the current name); names are kept in FireRed's options and
  an empty name restores the game's.
- **Fixes shared with Gen 1 and 2:** auto-walk counts the battle marker as
  a battle; navigation rebinds by the adapter's identity; command gating
  and the camera option read each generation's own state.

Pokémon Access behaviour adopted (no code or text copied): the elevation
rule, water entry and exit steps, Strength switches as objects, the cue
beside a jumpable ledge, warps listed only when the game fires them.

## Verification (2026-11-01)

| Area | Level reached |
|---|---|
| Unit tests | `gen3_nav_test.lua` 112/112 (adds item balls, planned card key doors, journeys, the Tanoby room's plan across slices and followed to the end, renaming); every access suite passes; old navigation suites unchanged (known gaps 12/13 and 71/92); Gen 2 cartridge test 35/35 on the Crystal cache. |
| Gaps run (`drivers/gen3_nav_gaps.lua`) | Journeys walked: Silph Co. 1F to the Card Key on 5F (planned in 0.04 s), 4F to 5F's Protein through a card key door (without the key: "Needs Card Key"), Rocket Hideout B2F to TM 49 on B4F; B4F's elevator-side Calcium: "No route". Mt. Moon 1F's Potion ball in the only way picked up and walked past. Shift+K and Shift+M through the naming screen, names kept and cleared. Icefall Cave B1F slide of 9 cells, 1F over thin ice; Seafoam B3F and B4F carried by currents (hide flags set by the harness); Pokémon Mansion 1F secret switch reached, pressed, gates changed, routes replanned. Two Island's Cape Brink waterfall climbed by auto-walk (Surf, then Waterfall). |
| Strength in the game (`drivers/gen3_nav_puzzle.lua`) | Tanoby Key room solved by walking and pushing as the hints said: "still working out" twice, then 32 pushes, all seven switches. Victory Road 1F and Seafoam 1F as before. |
| FireRed runs (identity `pocket-access-nav-firered`) | Bedroom to Pallet Town by auto-walk; guided navigation to Route 1 and Viridian with wild battles pausing and resuming the walk; Route 1 at 200X over four ledges (speed handed back after); Nugget Bridge, five trainers, "Resuming walk" after each; Surf from Pallet Town to Route 21 through the game's prompt; Rocket Hideout B2F by spinner chains; Silph Co. 5F card key door (the harness set the key's flag); Victory Road 1F switch from the hints alone, 19 pushes. |
| Label sweep (rerun after these changes) | 418 maps, 3787 labels, none bad; 1015 active warps; 18 dynamic warps (elevators, link rooms) read "Exit". Following only the hints, with plans searched in slices and kept: Victory Road 1F (19 pushes), 2F (25), 3F (33), the Tanoby Key room (32, all seven switches), Seafoam 1F (8, both boulders dropped), B1F to B3F. |
| Gen 1 and Gen 2 after the merge (lead) | Red auto-walk battle and elevators, Yellow follower (identical to baseline), Crystal `gen2_nav.lua`: all clean. |
| Gen 1 and Gen 2 after these changes | Rerun isolated: Red auto-walk battle (walk, wild battle, "Resuming walk"; the driver now uses the navigation module's controller handlers, since isolation makes the love callbacks no-ops and the walk never started), Red elevators (Celadon, Silph, Rocket Hideout), Yellow follower (Pallet and Viridian walks arrive, Pikachu listed and talked to; Cerulean's walk says "No route to Signpost 1", not compared with an earlier log; no Gen 1 routing code changed), Crystal `gen2_nav.lua`: clean. Shared code changed: one line exporting `requirementPhrase`. |
| FireRed drivers after these changes | `gen3_nav` 15/15, `gen3_nav_more` 13/13 (door walk now starts from 5F's stairs, since the Card Key journey really arrives in the pad-only section), `gen3_nav_puzzle` 4/4 (level 100 party: a level-up prompt had stranded the harness in a battle), `gen3_nav_gaps` 23/23 plus the waterfall check 2/2, `gen3_nav_sweep` 7/7. |
| Heard by the owner | Not yet. |

## Known gaps

- Real gates, said as they are: Rocket Hideout B4F's Calcium is on the
  elevator side (Lift Key and the elevator's floor menu): "No route";
  Silph Co. 5F's Protein without the Card Key: "Needs Card Key".
- Icefall Cave 1F from the entrance reaches nothing beyond its own side:
  the way on is falling through thin ice the player has cracked, behind a
  row of one-way ledges. Routes do not plan making a hole; nothing hints
  at it yet.
- Planned floors read the layout; only card key doors are corrected for
  the floor's load script. Other load-time changes (Seafoam's calmed
  currents, Pokémon Mansion gates on a floor not yet visited) are seen once
  the player is on the floor; the journey then re-plans from there.
- Guided navigation to a warp whose own floor has no way to it may start
  a journey through other floors, while auto-walk to the same warp says
  "No route" (shared behaviour, Gen 1 and Gen 2 alike; Seafoam B3F).
- In the drivers' new game (started by upstream's boot action) Seafoam
  B3F and B4F load with calm currents, because the boulders' hide flags
  (70 to 77) are unset; the driver sets them to test the strong currents.
  Not checked whether a new game from the title menu sets them (game data,
  not this layer).
- Owner question: about 187 windows plus lights and cups are listed as
  objects; too noisy?
