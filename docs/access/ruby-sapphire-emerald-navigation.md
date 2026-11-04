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

VERIFICATION_TABLE

## Known gaps

KNOWN_GAPS
