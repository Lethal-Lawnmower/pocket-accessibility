# Ruby, Sapphire and Emerald: navigation

Differences from FireRed's navigation (`firered-leafgreen-navigation.md`), which this shares. Screens are
in `ruby-sapphire-emerald.md`. No upstream file is changed by this work; nothing here is in the hook list.

## How it works

The same coordinator (`nav/gen3/`) runs on all five Gen 3 cartridges. `gen3/GameData.lua` says which one is
running and hands out what upstream already holds: the profile (`map.enginePrefix`, family, `badges`,
`optionsBlock`) and `Constants.of(id)` (object graphics, specials, flags, variables, map groups, metatile labels).

- **Metatile behaviours are not per game.** The importer translates every cartridge's raw byte into upstream's
  canonical ids (`src/core/game3/mb.lua`, `src/import/gba/mb_*.lua`): FireRed's numbers, and 0x100 + raw for names
  only Hoenn has. So the existing numeric tables stay right, and Hoenn's names are read through `GameData.mb`. Keying a table on
  `Constants.of(id).metatile_behaviors` would have been wrong: those are the raw bytes, which never reach the map views.
- **Object graphics are per game** (a boulder is 97 in FireRed, 87 here): `Terrain.GFX` looks them up each read.
- **Names:** `EM_`, `RU_`, `SA_` come off. Possessives and small words are spelled ("Littleroot Town Brendan's House 1F",
  "Cave of Origin 1F"). People by sheet; the rival's sheets say the character's own name ("May", "Brendan").
  A person whose sheet a variable picks is "Person" on a map the player is not on.
- **Area** (decision 25): `UNDERWATER_` comes off the key, so a route and its seabed are one area; a bare route is its own area
  (FireRed's routes have none); Secret Base rooms and Battle Pyramid squares have no Area list.

## Tiles and field moves

| Thing | Treatment | Source |
|---|---|---|
| Deep water, currents, Waterfall, ledges, ice | As in FireRed, canonical ids | `forced_movement.lua` `TABLE_RSE` |
| Trick House 8's floor | Slides like ice | `MB_TRICK_HOUSE_PUZZLE_8_FLOOR` |
| Muddy slope | Slides the player down; up only on the Mach Bike | `muddySlope` |
| Cracked floor | A drop on foot. Walking refuses it, a journey may fall through it as a last resort, the Mach Bike rides it | `step_callbacks_rse.crackedFloor` |
| Bumpy slope, rails | Refused: "Needs Acro Bike" (no bunny hop or wheelie walk is written) | `Bike.acroCollision` |
| Bridges (elevation 15) | One straight crossing is one move, refused when the far side's elevation differs. A planner that saw each cell alone walked Victory Road 1F into a wall until "Turned back" | `Player.updateElevation` |
| Water doors, Mt. Pyre's holes, Lavaridge's holes and springs, Mossdeep's pads, Aqua's pads | Warps fire on behaviour alone here, so planned views count them | `installWarps`' `RSE_WARP` |
| Underwater maps | Moved through with no Surf; surface edges and "exit water" do not apply | `Dive.isUnderwaterMap` |
| Dive | An edge from every deep water cell to the same cell below; from below, every cell not under rock. A script's `setdivewarp` (Sootopolis's crater, Route 134's chamber) lands on its one cell. Auto-walk stops: "Press A and answer yes to dive to ...", "Press B ... to surface" (the game surfaces on B) | `dive.lua` |
| Secret bases | Each closed spot is listed as "Secret Base Spot"; Secret Power stays the player's | `MB_SECRET_BASE_SPOT_*` |
| Flash | A cave's level stays 1 after Flash here, so the flag decides. Dewford Gym is not "dark" for decision 37: its map is no cave and Flash is refused there, its level falls with its trainers. Agent choice, open to the owner | `field_moves.flashFromMenu` |
| Q | The game's local time ("7:05 AM") from `Rtc.calcLocalTime` | `rtc.lua` |
| Badges | Named from upstream's table (Strength: Dynamo Badge in Hoenn) | `Flags.forVersion` |

## Auto-walk puzzles

All under AUTO-WALK PUZZLES; any key stops them. They start when a target has no route.

- **Boulders** (Seafloor Cavern, Victory Road, Fiery Path, Magma Hideout, Trick House 4, Shoal Cave): FireRed's
  `planOpening` unchanged. A journey now keeps its Area target across floors, so a floor's boulders are solved in passing.
- **Floor switches** (coord events whose script changes the floor; Mauville Gym's beams, Mossdeep Gym's colours): listed
  as "Floor Switch" and pressed by `SwitchWalk`, which steps onto them. A route never crosses one, since that would change the floor
  under it. A trainer who walked into the only way restarts the search (`puzzlesOnResume`).
- **Mossdeep Gym (Emerald):** each switch moves every object on arrows of its colour (`RotatingTilePuzzle.move`), so the presses are
  worked out ahead (`Navigation:rotatingSwitchPlan`, a search over where objects stand). When the search hits its limit, `SwitchWalk`'s trying carries on and asks again after each press.
- **Spinning gates** (Fortree Gym, Trick House 6): `Navigation:plannedRoute`, a search over cell and gate positions using `RotatingGate`'s rules. Guided navigation says "Spinning gates here: use auto walk" rather than give a route that ignores them.
- **Thin ice** (Sootopolis Gym, `IceWalk.lua`): one path over every thin cell of a room, ending beside the way on, walked cell by cell, for each room in turn. Before any way round through a fall. A partly cracked room that cannot be finished is refused with a reason.
- **Mach Bike:** when the player is riding it, `Navigation:machRoute` searches cell, heading and gear, so a run-up is part of the route. Getting on is the player's.

## Refused on purpose

- Acro Bike's jumps and rails ("Needs Acro Bike").
- Cross-area journeys (as in FireRed): the ferry, the cable car and Fly stay the player's.
- Regi chambers: the braille signs are listed, what they ask is the player's.
- Doors a story opens (New Mauville's, Sootopolis Gym's) are closed until it does; "No route" is true then.

## Verification

Numbers below are from driver logs on this branch. Nobody has heard any of it.

| Check | Emerald | Ruby | Sapphire |
|---|---|---|---|
| Label sweep (`rse_nav_sweep`), maps | 519 | 395 | 395 |
| Labels on those maps | 4405 | 3523 | 3523 |
| Bad labels (raw ids, addresses, placeholders) | 0 | 0 | 0 |
| Generic: "Person" | 495 | 536 | 536 |
| Generic: "Exit" (dynamic warps) | 33 | 30 | 30 |
| Generic: "Trainer" | 9 | 0 | 0 |
| "Signpost N" | 0 | 0 | 0 |
| Reach (`rse_nav_reach`): listed, no cell any flood entered | 2099, 150 | 1756, 117 | 1756, 117 |
| Area journeys planned, refused (`rse_story` A, a new game's flags) | 238, 68 | 209, 43 | 209, 43 |
| All 8 gym leaders, door to leader, one auto-walk each | 8 of 8 | 8 of 8 | 8 of 8 |

All levels: run in game by driver with a harness party, badges, flags and teleports, skipping every scene in between. No full playthrough
was run, and no walk started from a save. Rerunning Emerald's later parts after the last fix, one walk changed: Shoal Cave's Ice Room is "No route" at high tide,
because the game's tide follows the clock (`UpdateShoalTideFlag`); low tide arrived.

- **"Person" and "Exit" are planned-map counts.** "Person" is a sprite a variable picks: mostly Secret Bases (360), then Contest Halls and houses, resolved when the map loads.
  Live, on Brendan's and May's 2F, two Pokémon Centers, a Secret Base and Lilycove (Emerald), 0 of 41 objects said "Person". "Exit" is a warp the game fills in while running (Secret Bases, link rooms).
- **Puzzles, seen arriving:** Mauville (switches, a trainer in the only way), Fortree (gates; Ruby and Sapphire's route crosses a cell twice), Lavaridge (holes and springs), Mossdeep (Emerald: 16 presses in the traced run; Ruby and Sapphire: hidden switches), Sootopolis (all three rooms). Seafloor Cavern Room 1 to Room 9 by one walk, boulders and Rock Smash included, all three games. Trick House 1, 2, 3, 4, 6, 8 to the scroll, all three; 7 in Emerald only.
- **Field moves, seen:** Surf, Waterfall (Meteor Falls), Dive and back (Route 124, all three), Sky Pillar 2F to 3F on the Mach Bike, and "Needs Mach Bike" on foot (run with the harness's VAR_SKY_PILLAR_STATE in Emerald). Crater by water door (Emerald). Q says the time.
- **Unit tests:** every suite in `tests/access` passes; `gen2_nav_cart_test` skipped. No Hoenn unit suite was added; drivers are the evidence.
- **Other games on this code:** FireRed `gen3_nav` 15/15, `gen3_nav_more` 13/13, `gen3_nav_gaps` 38/38, `gen3_nav_puzzle` 5/5, `gen3_boulders` (Seafoam, Tanoby 32, Victory Road 19, 25, 34), `gen3_nav_sweep` 7/7, `gen3_switches`. Crystal `gen2_nav`, `gen2_switches`: finished, no FAIL lines. Red `journeys`: finished, no FAIL lines; `gen1_puzzles`: no FAIL lines, but stopped by my 500 second limit before its end, so not a full pass.
- **Heard:** nothing. Every run was silent.


## Known gaps

- **Story doors and guards.** New Mauville's door, Sootopolis Gym's door, the grunts inside Aqua and Magma Hideouts and at Seafloor Cavern's entrance: "No route" until the story clears them. Reach counts them as terrain. These were read from the floors, not walked with the story's flags set.
- **Reach gaps left, by map (Emerald; the reasons are read from the maps, not proved by walking):** Battle Pyramid squares 48 (generated in the challenge), Trick House 19, New Mauville 18 (behind the Basement Key door), Abandoned Ship hidden rooms 13 (their key), Seafloor 11 and Fiery Path 7, Victory Road B1F 4 (boulders the flood holds fixed; Seafloor was walked through), Petalburg Gym's locked signs 10, Shoal Cave 10 (tide), Safari Zone 4 (bikes). Ruby and Sapphire much the same without the Pyramid; their Trick House 35, Seafloor 14.
- **Trick House 7 in Ruby and Sapphire:** "No switch opens a way". Their constants have no arrow tile names, so `rotatingSwitchPlan` cannot read the puzzle and trying switches does not find it. Optional. Trick House 5 is the Mechadolls' quiz, a held script, not a walk.
- **Rooms by script:** Battle Frontier, tents, contests, the cable car, the ferry, Regi chambers, Mirage Island: lists work where the map is free; nothing walks their rides or challenges. No Frontier facility was walked.
- **Acro Bike:** Jagged Pass upward, Safari Zone's rails: "Needs Acro Bike", no walk.
- **Mach Bike:** the player must already be riding; only Sky Pillar 2F was ridden. Granite Cave B2F's cracks, Mirage Tower's and the muddy slopes are the same search, not run.
- **Secret bases:** a spot is listed and walked to. Secret Power, and a base's own decorations, are not run.
- **Unexplained:** in Ruby and Sapphire, Seafloor Cavern's entrance with the grunt in the way, the walk's first move brought up the game's Dive question (the harness answered yes). Not looked into. A real player can answer no.
- **Petalburg Gym:** Norman's object stands by the door in a new game's state, so "door to leader" there is a few steps and proves nothing about the rooms. The rooms' doors are warps the planner reads; none was walked to Norman in a later state.
- **A move through a bridge** says each cell in guided navigation, but the crossing has only been walked by auto-walk (Victory Road 1F).

