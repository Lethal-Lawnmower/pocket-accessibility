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
- **Area floors:** each other floor of the area is a target ("Pokémon Tower 7F"); arriving on it by any way in
  is the arrival.
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

## Audit, 2026-11-03 (by script; not heard)

Whole-map audit (`gen3_nav_sweep`, 418 maps, 0 bad labels) plus new runs:

| Check | Result |
|---|---|
| Plain signs | 307 "Signpost N" down to 42, named "Sign: " and their first line. Left: Game Corner machines, Cinnabar Gym, Ruby Path B4F, Dotted Hole and a few others, whose scripts load no text first |
| Merged exits | 49 pairs of warps to one map that are not side by side are now separate ("entrance 1 of 2"), as Tohjo Falls needed: Rock Tunnel, Power Plant, Mansion, Seafoam. 3 remain merged |
| Boulder floors (`gen3_boulders`) | Finished: Seafoam 1F (8 pushes), B1F (1), B2F (3), Victory Road 1F (19). Stopped by the harness in a battle menu, not by the walk: Seafoam B3F, Victory Road 2F. Not started: Victory Road 3F, no boulder within reach of the start cell. Tanoby Key: no boulder listed |
| Secret Switches (`gen3_switches`) | Mansion 3F Iron (1 flip), B1F TM 22 (2), TM 14 (1), Secret Key (3). 1F, from beside the door: "No switch opens a way", 3 flips, which can leave a switch flipped |
| Owner's save (Cerulean) | Routes and refusals read as expected on a copy |

Not run: anything by ear. The boulder and switch rows above are superseded by the next section.

## Story pass against Crystal, 2026-11-03 (by script, run in game; not heard)

The owner asked that nothing Crystal got be missing in FireRed. Teleports, party, flags, a Repel and the
Silph Scope come from the harness; every walk is one auto-walk from the list. Drivers: `gen3_story`
(parts A to E, N, M), `gen3_reach_sweep`, `gen3_dump`, plus the reruns named below.

| Crystal feature | FireRed | Evidence |
|---|---|---|
| Boulder auto-push | Passed | `gen3_boulders`: Seafoam 1F 8, B1F 1, B2F 3, B3F 1; Victory Road 1F 19, 2F 25, 3F 34; Tanoby Key 32 (all seven, the rumble line in the trace). Harness fix only: both earlier stops were its battle handling and its start cell |
| Hole filling | Passed | Seafoam floors above: boulders dropped, "all in place" |
| Secret switches | Fixed | Mansion 1F no longer ends at "No switch": goes to 3F's switch, flips it, drops, reaches B1F. Floor put back when nothing opens. `gen3_switches`: Carbos 5 flips, Protein 1, B1F warp 4, east exit 4, Iron 1, TM 22 2, TM 14 1, Secret Key 3 |
| Target blocked only by boulders (`planOpening`) | Fixed | Ported. Warden's House Rare Candy, Ruby Path B2F to B3F, Mt. Ember to Summit Path 1F, Ruin Valley Sun Stone, Full Restore, HP Up, Sevault Canyon King's Rock |
| Warps kept separate | Passed | Audit above; lists read again here (Silph 3F "entrance 1 of 2"). 3 pairs stay merged, not revisited |
| Signs named | Fixed | Plain "Signpost N": 42 to 0. Slot Machine, Braille, Vending Machine, Hidden Switch (Game Corner poster), Quiz Machine |
| Door and panel names in hideouts | Passed, one fixed | Card Key Door and Floor Panel listed; the Game Corner's poster was "Sign: Hey!"; Celadon's panel was listed twice, once on a wall no one can stand below |
| Routes across floors, Area floor entries | Fixed | Area had items only. Now 271 floor entries in 65 areas; being on the floor is the arrival. 241 of 278 planned from each area's first floor; the 37 refused are the Mt. Ember and League rooms behind story doors, buildings closed by people in a new game, unconnected tunnels, harness failures on Tanoby's water |
| Journeys through puzzle floors | Fixed | Victory Road 2F to 3F by Area from the west side: floor solved, then walked on. Seafoam 1F to B4F, calm and with strong currents. Victory Road 2F to its Route 23 exit; Indigo Plateau not walked. A journey stopped by boulders opens them and plans again |
| Text boxes read | Passed in trace | `gen3_walkthrough` speech, plus trainers' lines and Pokémon Tower's text in `gen3_story`. Silent runs cannot show refused speech |

Story places, one walk each, all arrived: Game Corner Rocket, poster (Hidden Switch), stairs to the Hideout;
Hideout B1F to B4F by spinners; Silph 1F to 5F and 3F to 11F by pads with the Card Key; Pokémon Tower 1F to 7F
(Silph Scope, rival, Marowak); Mansion 1F to B1F; Saffron Gym to Sabrina (fixed), Viridian to Giovanni, Fuchsia
to Koga, Celadon to Erika, Cerulean to Misty, Pewter to Brock, Vermilion to Lt. Surge. Cinnabar: "No route to
Blaine" until the quiz gates open, which is the player's to do; walking to a Quiz Machine works. Sevii: every
listed target checked from the entrance on Mt. Ember, Icefall Cave, Rocket Warehouse, Lost Cave, Dotted Hole,
Pattern Bush, Altering Cave, Tanoby Key, Trainer Tower, Berry Forest. No full playthrough was run, and the
harness skips every scene between these places.

Bugs fixed and their causes:

- **Boulders with no switch or hole:** Gen 3's `boulderOpening` ignored its goals. `Puzzle.planOpening` searches
  pushes over the route graph with the boulders taken out, so ledges, Rock Smash and Surf count.
- **Puzzle end stopped the walk:** a target with no route ended at "all in place". It now walks on.
- **Saffron Gym:** "Cannot reach Sabrina". A pad lands on the same map, so the old leg's cell was asked for from
  the new room. The journey now plans again (`replanJourneyOffRoute`, set by FireRed only).
- **Mansion:** one flag, one switch a floor, and the way to the basement only from 3F. `remoteSwitch` supposes
  the flag flipped and plans from each switch, so a walk goes to the right floor first. Without it the Secret
  Key, which the story needs, was unreachable by one walk.
- **Quiet walks with an Area target selected** said "No route" and could leave the floor: fixed in `AutoWalk.start`.
- **Standing on the warp a walk wants** said "is here". It now presses or steps off and back (FireRed only).
- **Listed but unreachable (1936 listed, 151 with no cell any route enters, to 1876 and 78):** objects placed past
  the map's edge, connections no cell can cross, connections to a map with nothing on it, cable club doors behind
  the counter. The 78 left are behind boulders, gates or the Mansion's flag (walks above), two Dojo signs behind
  the gift balls, Saffron's empty map.
- **Island buildings:** a journey between two buildings of one island could not cross the town.

Vermilion Gym with the first lock already open (`gen3_surge`, `GEN3_SURGE_RESTART=1`): stopped after the lock
opened and asked again, 20 presses, arrived at Lt. Surge.

Regressions on the final code unless noted: `gen3_nav` 15/15, `gen3_nav_more` 13/13, `gen3_nav_gaps` 38/38,
`gen3_nav_puzzle` 5/5, `gen3_nav_sweep` 7/7, `npc_category`, `dark_maps` clean; unit suites pass (`gen3_nav_test`
167, `auto_walk_test` 63) except `gen2_menus_test` 121/122, whose fix is uncommitted on main. The last two small
fixes (target memory on another floor) came after the first of those runs; `gen3_switches` and `gen3_story` N ran on them.
The running sweep has no FireRed lane: its ROM folder holds no FireRed dump. These runs used the imported cache of
an earlier disposable profile. Gen 1 and Gen 2 drivers were not rerun here; shared code changes are listed in the branch.

## Vermilion Gym's trash cans (2026-11-03, by script; not heard)

Auto-walk to Lt. Surge, or anything else behind the door, with AUTO-WALK PUZZLES on, says "Searching for
switches to reach Lt. Surge" and presses cans until a route opens, then walks on. Any key stops it. The game
picks a first can, then a second next to it, and picks again after a wrong second can.

- **How it knows a press did something:** the tiles scripts have drawn on the floor changed
  (`Navigation:floorMarks`). The first lock and a reset change no collision, so `SwitchWalk`'s usual state won't do.
- **Order:** nearest to the last can that changed the floor, which puts the second can's neighbours first.
  Everything tried is forgotten at each change, because a reset re-rolls.
- **Facing:** the cans' script ends at once when the player faces up, so the cell below a can is never used.

`gen3_surge`, three runs on a fresh profile with a level 90 party: 26, 11 and 41 presses, about 2.4, 1.6 and 3.5
minutes of game time counting gym battles; each arrived at Lt. Surge. Every game line came through, such as "The
first electric lock opened!". Red, Blue, Yellow, Gold, Silver and Crystal do not have this.

## Known gaps

- Mt. Ember's Fire Stone: "No route" from the entrance. Its room looks to need a boulder moved through a space
  a rock fills until smashed, and the search counts rocks as fixed for boulders. Optional item; not solved.
- `remoteSwitch` looks one flip ahead, and the walk can win battles on the way before it knows the next flip.
- A journey past boulders walks on hopefully; a floor with no solution ends with "No route" there, not at the start.
- 3 merged exits from the audit were not looked at again.
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
