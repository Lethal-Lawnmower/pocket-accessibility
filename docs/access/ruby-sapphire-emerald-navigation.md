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
  A person whose sheet a variable picks is "Person" on a map the player is not on; on the map itself the game has
  picked it, and it is named (checked on May's house, the Contest Hall, a Battle Tent and Lilycove's Pokémon Center,
  2026-11-09). The sweep counts these, and exits that lead back where the player came in, as "variable", not
  generic. The link receptionist's sheet (`LINK_RECEPTIONIST`) was called "Trainer" as a link partner's; fixed.
- **Polish sweep (2026-11-19, owner's request "a heavy third generation polish sweep").** Found by listing every label of
  Emerald, Ruby and FireRed (`RSE_SWEEP_LIST=1`) and reading the speech in the walk logs:
  - Signs: the first page, lines joined, cut at a word at 64 (was the first line at 48 bytes). An arrow starting a line is a
    direction ("ROUTE 104, east: PETALBURG CITY"), inside a sentence a word ("A short walk up way!"); a filled-in word goes
    with its quotes and "'S" (Dewford Hall was "Sign: “'S"); "1O4" on Route 104's sign is read as 104; the treasure
    hunters' list says "Wanted item, Trade item RED SHARD for FIRE STONE". `Scripts.signLine`, tested in `gen3_nav_test`.
  - Littleroot: the house that matches the player's gender is "<name>'s House 1F" (was "Littleroot Town Brendan's House 1F"
    for a boy's own house); the other keeps the rival's name. Gender from the session (`Snapshot.playerGender`).
  - Rooms: Meteor Falls' and Magma Hideout's "1F 1r" are "1F Room 1".
  - Guided navigation said "Cannot reach yet" where auto-walk named the reason: past Granite Cave B1F's cracked floor
    ("Needs Mach Bike") and at Aqua Hideout's grunt ("Blocked by Team Aqua Grunt"). When every route policy fails, the
    shared `advancePendingRoute` now asks `Navigation:unreachableReason`; Gen 3 answers with `routeNeeds`, then its
    journey planner. `dark_maps` checks the Granite Cave case in Hoenn.
  - A guided-navigation sweep (`tests/access/drivers/gen3_guided_sweep.lua`: every warp and connection of every map,
    from its first warp, with the harness party, badges and Flash; its logs are not kept) first left 55 "Cannot reach
    yet" in Emerald. What became of them is in "Second pass" below.
  - Not changed: object names come from the sprite sheet ("Fat Man", "Expert"), as in FireRed; Emerald's unused Cave of
    Origin maps are "Cave of Origin Unused Ruby Sapphire Map 1", reached only from each other.
- **Area** (decision 25): `UNDERWATER_` comes off the key, so a route and its seabed are one area; a bare route is its own area
  (FireRed's routes have none); Secret Base rooms and Battle Pyramid squares have no Area list.

## Second pass (2026-11-19, the owner: "another giant polish pass in all of third generation")

The owner named the old scripts' sore points: several dive points with nothing to tell them apart, and Victory Road.
All of this is run in game by driver, silent; nobody has heard it.

- **Dive spots** (`Navigation:diveSpots`, in the object list). Each patch of deep water over one seabed is one entry
  that says where it leads: the seabed's own doors, named by where they come up ("Dive Spot to Sootopolis City",
  "to Seafloor Cavern Entrance"), then the other waters that seabed surfaces in ("to a pool with Red Shard and the
  open water", "to water at the east edge of Route 124"), else "Dive Spot, seabed only". Below, each stretch that can
  surface is "Way Up to Route 126", "Way Up to an enclosed pool", "Way Up to Sootopolis City". Guided navigation and
  auto-walk go to the nearest cell of one and say the game's button ("Press A and answer yes to dive", B to
  surface); without the move the entry says "Needs Dive". Two patches of deep water in the same stretch over the same seabed are one entry (the
  nearer cell is the target); entries that still share a label are numbered as a map's doors are ("Dive Spot, seabed
  only, 3 of 6"). Emerald: 88 entries on 25 maps (Route 124 has 16 over ten seabeds, six of them "seabed only");
  Ruby and Sapphire: 76 on 20. "The open water" is the map's largest stretch; a smaller one that reaches the map's
  edge is "water at the north edge of ...". Hidden items on a seabed are not listed, as elsewhere. Driver
  `rse_dive_spots`: Emerald, Ruby and Sapphire, with a dive under Route 126 and back by the list alone
  (results under "Third pass"). Agent's wording, open to the owner.
- **The list broke routes from water (all five Gen 3 games).** `WorldSnapshot.mapProxy` ran the view's methods on
  the proxy, whose relabelled `def` has no layout, with the view's own cache: the cell the player stood on was cached
  "not water" the first time the list was opened there, and the next route from that cell began "Use Surf facing
  right" (auto-walk: "Could not use Surf"). The proxy now calls the view's methods on the view. Found because
  `rse_dive_spots` passed only when a route had been planned before the list was read; the driver now checks the
  cell after the list.
- **Ways round** (`Navigation:regionalNextLeg`, `wayRoundMaps`). A target on the player's own map with no way in its
  area, with or without what the player lacks, is searched for once more through the places this map's doors lead
  to and their other floors, never through a connection: Route 104 through Petalburg Woods, Route 116 through
  Rusturf Tunnel, Ever Grande City through Victory Road. Boulders on the way are set aside for the plan and pushed
  when the walk gets there. With people set aside it answers "The way is through <place>, blocked by someone
  further on". Any map at all was tried first and is wrong: see FireRed's Route 4 in `firered-leafgreen-navigation.md`.
- **A journey keeps its target** (`rememberJourneyTarget`, `keptJourneyTarget`). Victory Road from its south door to
  the League's is a target on 1F reached through B1F and B2F; the list on B1F does not have it, so when B1F's
  boulders had to take over, or a trainer had been fought, the walk stopped: "Cannot reach Ever Grande City,
  entrance 2 of 2, auto walk stopped". The target now stands in as the selection, shaped like an Area target, until
  the player arrives or chooses something else; pressing auto-walk again with nothing chosen carries the journey on
  (after Flash on a dark floor). `rse_story` W, Emerald: Victory Road door to door, Ever Grande City's League side
  back down to the Center, Route 104's two halves, Route 116's: 4 of 4, one auto-walk each.
- **Guided navigation's refusals.** Any sentence the journey planner gives is passed on ("Blocked by ...", a story
  door, "Needs ..."); a way that counts on boulders says "Boulders in the way: use auto walk"; a floor with floor
  switches (Mossdeep Gym, Trick House 7) "Floor switches change this floor: use auto walk". Lavaridge Gym's buried
  trainers stand in four of its holes, unseen and in no list: "Blocked by a hidden trainer", not "Blocked by Man"
  (agent's wording, open to the owner: it tells the player a trainer is there before the trainer jumps out).
- **Of the 55 bare refusals, 9 are left** after the third pass below: the Abandoned Ship's locked rooms asked from
  inside another room (3; a player comes from the corridor, where the game's own "locked" text answers); Magma
  Hideout 2F Room 3 from 1F (not looked into); Route 112's south-west pocket with Jagged Pass and Lavaridge's edge
  (2; reached by the cable car and down Jagged Pass: the ride is the player's); Route 123's north-east from its west
  end (one-way ledges); Route 125's north-west water from Shoal Cave (it joins Route 124 only: a row of rocks
  closes it from the rest of Route 125, seen in the planner's grid); Safari Zone South to North asked from the
  entrance door's own cell, which the attendant closes (from anywhere a player stands it says "Needs Acro Bike").

## Third pass (2026-11-19, the same request: "try and fix any of the navigation/pathfinder gaps along the way")

Run in game by driver, silent; nobody has heard it.

- **The currents west of Pacifidlog** (`Navigation:farDiveSpots`, in the Area list). Routes 132 and 133 carry the
  player west in whichever lane they entered, and only some lanes reach the water over the Sealed Chamber on Route
  134. Going connection by connection ("West connection to Route 133", then 134) ended on Route 134 with "No route
  to Dive Spot to Underwater Sealed Chamber from here" (probed: Pacifidlog, three connections, then the dive spot).
  A dive spot that leads to a place of its own (a seabed door, or a seabed that is its own place: Sootopolis City,
  Seafloor Cavern, the Sealed Chamber) is now in the Area list of every surface map within three connections, as
  "Dive Spot to Underwater Sealed Chamber, Route 134"; its journey is planned over those maps only, and the planner,
  which knows the currents, takes the lane that gets there. `rse_story` W, Emerald: Pacifidlog to that water in one
  auto-walk, through two trainer battles. Three more things had to be right for it:
  - a connection is crossed mid-step, and auto-walk planned the next leg while the player's cell still read 80,24
    on a map 80 wide: "Cannot reach ..., auto walk stopped". It waits until the cell is on the map
    (`AutoWalk.update`, for a coordinator that sets `journeyWaitsForLanding`: Gen 3 only, Gen 1 and 2 as before);
  - a current can set the player down on the very edge cell a leg ends at; with no step left the walk said "Could
    not go through". Gen 3's legs now say which way to step off (`edgeDirection`, as Gen 2's do);
  - the journey's maps may come with its target (`goals.journeyAllowed`), where they were only ever its area's.
- **Who is in the way, by name** (`journeyBlocker`, `essentialBlocker`). "Blocked by someone further on" named no
  one. The way with everyone set aside walks through whoever is nearest, so each person on it is stood back up in
  turn and the journey searched again; the first whose return leaves no way is named, with the place when it is
  not this map. FireRed's Route 16 to Route 17: "Blocked by Snorlax"; Route 4 east: "The way is through Mt. Moon 1F,
  blocked by Fossil in Mt. Moon B2F" (true: the two fossils close the corridor until one is taken; the first
  version named a Youngster who can be walked round).
- **Places the story or the tide keeps shut** (`closedForNow`, the last thing asked): Lilycove's water while the
  Wailmer are drawn, "Blocked by a group of Wailmer" (they close the cove and the only way east to Route 124, seen
  in the planner's grid; the earlier note that the harness's badges should clear them was wrong: the story does);
  the three sealed chambers, "Sealed: the braille on the far wall says how to open it"; Shoal Cave, "Not at low
  tide: this part is reached at high tide" and the reverse, by the game's own tide flag (the rooms keep their "low
  tide" map at either tide. Found because `rse_story`'s walk to the Ice Room said "No route" in a run after 9 in
  the morning: once a real map edge has been crossed the cave's own script sets the tide from the clock, and the
  flag was set. The driver now leaves that walk out at high tide, with a NOTE); the Mystery Events House's stairs, "The stairs are
  closed off" (walled in the map itself). Agent's wording, open to the owner.
- **Switches.** A floor with Secret Switches or Ruby and Sapphire's Hidden Switches says "Switches change this
  floor: use auto walk", as floor switches did.
- **An edge crossed only by water** had no crossing at all for a player without Surf, so guided navigation said "No
  path"; it now says the move ("Needs Surf", with the badge when that is missing too). `Navigation:connectionGoals`.
- **Trainers drawn with a plain sheet** ("Man", "Woman", "Boy", "Girl", "Fat Man", "Old Man", "Old Woman", "Little
  Boy", "Little Girl", "Balding Man") are named by the trainer class the battle shows, read from the object's own
  `trainerbattle` command: "Bird Keeper", "Ruin Maniac", "Tamer". A title (PKMN TRAINER, LEADER, ELITE FOUR,
  CHAMPION, RIVAL) is no better than the sheet and is not used. Emerald's label sweep: "Man" 166 to 100, "Woman"
  158 to 109. Agent's choice, open to the owner.
- **Guided sweep, Emerald**: 925 targets, 9 bare refusals (55 before the second pass, 18 after it).
- **Regression after this pass** (drivers, silent; the unit suites pass, 189 checks in `gen3_nav_test`).
  Emerald: `rse_nav_sweep`, `rse_dive_spots`, `dark_maps`, `npc_category` with no failure; `rse_story` 40 walks
  arrived, with the four story blocks it has always reported as failures (the grunts at Aqua Hideout and Seafloor
  Cavern, New Mauville's key, Sky Pillar on foot) and Shoal Cave's Ice Room left out because the run was at high
  tide; part W 5 of 5 on the last code. Ruby: `rse_dive_spots`, and `rse_story` 40 arrived with its four blocks,
  W 5 of 5. Sapphire: `rse_dive_spots` (its `rse_story` was last run before this pass: the same four blocks).
  FireRed and LeafGreen: `firered-leafgreen-navigation.md`.

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

- **Story doors and guards (decision 65, 2026-11-09).** When no route exists, the route is planned again with people set aside; the first one on it is named: "Blocked by Team Aqua Grunt" (Emerald's Aqua Hideout and Seafloor Cavern entrance; Ruby's Aqua Hideout says Team Magma Grunt, the sheet the game draws there), or "Blocked by someone further on" when the person is on a later map (`Navigation:routeNeeds`, and in `regionalNextLeg` for Area targets). New Mauville's door says "New Mauville's door is locked: needs the Basement Key", or with the key "walk up to it and the Basement Key opens it" (`STORY_DOORS`, read from `VAR_NEW_MAUVILLE_STATE` and the bag; its script opens the door when the player steps in front of it with the key). Run in game by `rse_story` H on Emerald and Ruby, silent. Ruby's Magma Hideout 1F says "Blocked by Trainer": its grunts' sheet comes from a variable the harness's teleport never set (the player's sheet, number 0), so in play it should name the grunt; not checked. Sootopolis Gym's door still says "No route". Reach counts all of them as terrain.
- **Reach gaps left, by map (Emerald; the reasons are read from the maps, not proved by walking):** Battle Pyramid squares 48 (generated in the challenge), Trick House 19, New Mauville 18 (behind the Basement Key door), Abandoned Ship hidden rooms 13 (their key), Seafloor 11 and Fiery Path 7, Victory Road B1F 4 (boulders the flood holds fixed; Seafloor was walked through), Petalburg Gym's locked signs 10, Shoal Cave 10 (tide), Safari Zone 4 (bikes). Ruby and Sapphire much the same without the Pyramid; their Trick House 35, Seafloor 14.
- **Trick House 7 in Ruby and Sapphire (solved 2026-11-09, decision 65).** Five levers, each turning its own flag and redrawing arrows. Trying them one by one stranded the player where only the last lever could be reached ("No switch opens a way"). `Navigation:leverPlan` reads what each lever draws both ways (`Scripts.pressCells`), draws a floor for any set of levers (`World.viewWithCells`) and searches which levers to press, and where the player ends up, before walking; SwitchWalk presses the one it names. Ruby: two presses, then the walk to the scroll, arrived (`rse_story` H, silent). Sapphire not run (same scripts). A floor whose drawing depends on the order of presses would be planned wrong; SwitchWalk plans again after every press. Trick House 5 is the Mechadolls' quiz, a held script, not a walk.
- **Rooms by script:** Battle Frontier, tents, contests, the cable car, the ferry, Regi chambers, Mirage Island: lists work where the map is free; nothing walks their rides or challenges. No Frontier facility was walked.
- **Acro Bike:** Jagged Pass upward, Safari Zone's rails: "Needs Acro Bike", no walk.
- **Mach Bike:** the player must already be riding; only Sky Pillar 2F was ridden. Granite Cave B2F's cracks, Mirage Tower's and the muddy slopes are the same search, not run.
- **Secret bases:** a spot is listed and walked to. Secret Power, and a base's own decorations, are not run.
- **Unexplained:** in Ruby and Sapphire, Seafloor Cavern's entrance with the grunt in the way, the walk's first move brought up the game's Dive question (the harness answered yes). Not looked into. A real player can answer no.
- **Petalburg Gym:** Norman's object stands by the door in a new game's state, so "door to leader" there is a few steps and proves nothing about the rooms. The rooms' doors are warps the planner reads; none was walked to Norman in a later state.
- **A dive spot's label is worked out once a map** in a session: "a pool with Red Shard" still says so after the shard
  is taken, until the game is started again.
- **Far dive spots** are listed within three connections and only when they lead to a place of their own; an island or
  item in the currents (Route 132's, 133's, 134's) is still chosen on its own map, where the lane may already be wrong.
  The arrival says "Arrived at Dive Spot ...", not which button dives: the list on that map has the spot, with the button.
- **The blocker's name** is the first person without whom no way exists; where two people each close a different way the
  first found is named. An object drawn by a script is no person and is not named, except Lilycove's Wailmer.
- **Ways round stop at doors.** A way round never crosses a connection, so two halves of a route that join only through
  the next town (or by a ride) stay "Cannot reach yet". A journey whose way passes through the map a door target leads to
  ends there (Route 104 south to "Petalburg Woods, entrance 3 of 3" would end inside the woods' south door). Not seen in a run.
- **A kept journey target** lasts until the player arrives, goes through its door or chooses something from the list. A
  player who leaves a journey half way and later presses auto-walk with nothing chosen is walked on to it.
- **A move through a bridge** says each cell in guided navigation, but the crossing has only been walked by auto-walk (Victory Road 1F).

