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
  the final leg keeps only those inside the target floor (the shared
  planner does the same now).
- **Journey legs that are not a walk** (only when walking and the party's
  field moves get nowhere, so a walkable journey never stops at a menu or
  drops through a floor):
  - *Elevators.* A floor panel's script names its floors (`setdynamicwarp`
    map group, number, landing), so a car is a set of edges from the panel
    to each floor. Auto-walk
    stops at the panel: "Arrived at the floor panel. Face up and take the
    elevator to B4F" (the floor menu stays the player's, as in Gen 1 and
    Gen 2, where a panel is only an object to walk to). Pressing auto-walk
    again after choosing goes out of the car and on. A panel that first
    checks a flag is gated by it, and the item is the one whose giving script
    sets that flag: "Needs Lift Key".
  - *Falling through thin ice* (Icefall Cave 1F). A floor whose resume script
    sets step callback 4 and whose frame script has `warphole` drops the
    player at the same x and y on that map; every thin ice cell with floor
    below is an edge. Auto-walk walks onto the ice, steps off and back on
    ("Stepping off the thin ice and back on, to fall through to ..."), and
    carries on from the floor below; guided navigation says how. Cracked ice
    is simply walked onto.
  - *Seagallop ferry:* not a leg, and none is needed. Journeys stay inside
    one area and each island is its own area, so no journey ever crosses the
    water. A ferry leg would only matter for a cross-area target, which the
    object list does not offer.
- **Planned floors read their load scripts** (`Scripts.loadState`,
  `World.loadedView`). The transition and load scripts are read, not run:
  flags, trainer flags and variables come from the save, with the script's own
  `setflag`, `setvar` and `addvar` on the side; `setmetatile` and
  `setmaplayoutindex` are collected and read on top of the layout's base
  cells (Silph Co. doors, Pokémon Mansion gates, Rocket Hideout's doors,
  Seafoam's calmed currents, through upstream's baked alternate layout). A
  script that reaches anything else (a special, `getplayerxy`) is unreadable:
  the floor stays as planned before and the journey re-plans on arrival.
- **Auto-walk and guided navigation agree.** A target on this map with no
  route here is walked as a journey through other maps, the order guided
  navigation uses (walk, field moves, other maps), and "Needs Surf" is said
  when only that would help. FireRed only (`Navigation.autoWalkJourneys`).
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
| Unit tests | `gen3_nav_test.lua` 142/142 (adds item balls, planned card key doors, journeys, the Tanoby room's plan across slices and followed to the end, renaming, load scripts, elevators, thin ice); `auto_walk_test.lua` 63/63 (stop legs, the thin ice steps, journeys to a target on this map); every access suite passes; old navigation suites unchanged (known gaps 12/13 and 71/92); Gen 2 cartridge test 35/35 on the Crystal cache. |
| Gaps run (`drivers/gen3_nav_gaps.lua`) | Journeys walked: Silph Co. 1F to the Card Key on 5F (planned in 0.04 s), 4F to 5F's Protein through a card key door (without the key: "Needs Card Key"), Rocket Hideout B2F to TM 49 on B4F; B4F's elevator-side Calcium: "No route". Mt. Moon 1F's Potion ball in the only way picked up and walked past. Shift+K and Shift+M through the naming screen, names kept and cleared. Icefall Cave B1F slide of 9 cells, 1F over thin ice; Seafoam B3F and B4F carried by currents (hide flags set by the harness); Pokémon Mansion 1F secret switch reached, pressed, gates changed, routes replanned. Two Island's Cape Brink waterfall climbed by auto-walk (Surf, then Waterfall). |
| Strength in the game (`drivers/gen3_nav_puzzle.lua`) | Tanoby Key room solved by walking and pushing as the hints said: "still working out" twice, then 32 pushes, all seven switches. Victory Road 1F and Seafoam 1F as before. |
| FireRed runs (identity `pocket-access-nav-firered`) | Bedroom to Pallet Town by auto-walk; guided navigation to Route 1 and Viridian with wild battles pausing and resuming the walk; Route 1 at 200X over four ledges (speed handed back after); Nugget Bridge, five trainers, "Resuming walk" after each; Surf from Pallet Town to Route 21 through the game's prompt; Rocket Hideout B2F by spinner chains; Silph Co. 5F card key door (the harness set the key's flag); Victory Road 1F switch from the hints alone, 19 pushes. |
| Label sweep (rerun after these changes) | 418 maps, 3787 labels, none bad; 1015 active warps; 18 dynamic warps (elevators, link rooms) read "Exit". Following only the hints, with plans searched in slices and kept: Victory Road 1F (19 pushes), 2F (25), 3F (33), the Tanoby Key room (32, all seven switches), Seafoam 1F (8, both boulders dropped), B1F to B3F. |
| Gen 1 and Gen 2 after the merge (lead) | Red auto-walk battle and elevators, Yellow follower (identical to baseline), Crystal `gen2_nav.lua`: all clean. |
| Gen 1 and Gen 2 after these changes | Rerun isolated: Red auto-walk battle (walk, wild battle, "Resuming walk"; the driver now uses the navigation module's controller handlers, since isolation makes the love callbacks no-ops and the walk never started), Red elevators (Celadon, Silph, Rocket Hideout), Yellow follower (Pallet and Viridian walks arrive, Pikachu listed and talked to; Cerulean's walk says "No route to Signpost 1", not compared with an earlier log; no Gen 1 routing code changed), Crystal `gen2_nav.lua`: clean. Shared code changed: one line exporting `requirementPhrase`. |
| FireRed drivers after these changes | `gen3_nav` 15/15 (rerun on merged main), `gen3_nav_more` 13/13 (door walk now starts from 5F's stairs, since the Card Key journey really arrives in the pad-only section), `gen3_nav_puzzle` 5/5 (level 100 party: a level-up prompt had stranded the harness in a battle; Victory Road 2F added, 25 pushes through its barrier), `gen3_nav_gaps` 38/38, `gen3_nav_sweep` 7/7 (on the floors as drawn, gates open, since it runs no switch scripts). |
| Quirks run in FireRed (`gen3_nav_gaps` H to K) | Rocket Hideout B2F to Calcium: "Needs Lift Key" without it; with the flag, a walk to the car's panel, "Face up and take the elevator to B4F", the menu by the harness, auto-walk again out of the car and to the item. Icefall Cave 1F from the entrance to a ladder reached only from below: onto the thin ice, off and back on, fell, carried on through B1F, arrived. Planned floors against loaded ones, cell by cell, 0 differing: Seafoam B3F and B4F (calm), Mansion 1F and 2F (switch on), 1F (off), Silph 5F (doors shut). Load scripts on the cartridge: 117 readable (19 change the floor in this state), 35 not: 2 `getplayerxy`, the rest specials (18 `ValidateSavedWonderCard`, 8 Trainer Tower, E-Reader, Vermilion's trash cans, Icefall's remembered cracks, others). Seafoam B3F: guided navigation and auto-walk agree on all 7 warps. |
| Heard by the owner | Not yet. |

Rock Tunnel 1F before Flash (`drivers/dark_maps.lua`, decision 37): 1 of 16
items listed, guided navigation and auto-walk refuse, the camera stops after
one cell. With the flash level set to 0 by the harness: all 16, routes work.
Not heard.

Flavor furniture is under Misc, not Objects or All (decision 36; Viridian's
Pokémon Center and Mart listed it, a Bookshelf and a Poster walked to, 0 in
All). Before that (decision 34), the sweep after hiding it
lists 3033 labels on 418 maps (754 fewer than the first sweep), none bad. The
PC, Town Map, Battle Records and Questionnaire stay, as do signs the map
places (16 Trash Cans, 6 Bookshelves, 2 Computers, 1 Painting, 1 TV). A still
reads this furniture. Not heard.

Auto-walk falling through thin ice when no other way exists is the
owner's choice (decision 33).

## Known gaps

- Load scripts not read: see the verification table for the count. The
  specials among them cannot be read without running them (Vermilion's trash
  cans, Trainer Tower, Icefall's remembered cracks); those floors are right
  once the player is on them, and the journey re-plans there.
- Objects on planned floors are at their template positions: a script that
  moves one on load (`setobjectxyperm`) is not followed.
- Cross-area targets are not journeys, so no ferry leg (above).
- Yellow's follower run says "No route to Signpost 1" in Cerulean: the same
  output at the commit before FireRed navigation (541f2cfd), so not new; not
  looked into further.
- In the drivers' new game (started by upstream's boot action) Seafoam
  B3F and B4F load with calm currents, because the boulders' hide flags
  (70 to 77) are unset; the driver sets them to test the strong currents.
  Not checked whether a new game from the title menu sets them (game data,
  not this layer).
