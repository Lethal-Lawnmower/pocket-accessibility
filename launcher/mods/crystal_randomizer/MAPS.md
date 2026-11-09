# Map randomizer: design shared by its modules

Shuffles where doors lead, per save, never letting a seed strand the player. Built from five modules that
the core loads in this order: `mapgraph`, `maprules`, `mapplacer`, `maps`, `mapmoves`. They talk through
`ctx.lib` (functions offered at install time, never cleared) and `ctx.shared` (per-save results, cleared on
every switch). Read `CONTRACT.md` first.

## What a door is

Gen 2 keeps warps in `data.gen2Maps[mapId].warps`: `{ x, y, destMap, destWarp }`, `destWarp == 0xff`
meaning "back to the map and warp you came from" (`World:resolveWarp`, `World:recordWarpBackup`).
Each map has `environment` (`ROUTE`, `TOWN`, `INDOOR`, `CAVE`, `DUNGEON`, `GATE`).

- A **complex** is a set of non-outdoor maps joined by their own warps (a house with its upstairs, a cave's
  floors, a gym). Its **entrances** are its warps that lead to an outdoor map, and the outdoor warps that
  lead into it.
- A **door** is one outdoor-side warp leading into a complex, paired with the complex warp(s) that lead back
  to it.
- A complex with exactly one door is a **dead end** (most houses, shops, centers).

## Levels (question `maps`, a choice; RECOMMENDED and EVERYTHING both `"off"`)

| value | shuffles |
|---|---|
| `off` | nothing |
| `houses` | doors of dead-end INDOOR complexes among themselves, except story ones |
| `caves` | `houses`, plus doors of CAVE and DUNGEON complexes among themselves |
| `full` | every door that is not story-fixed, any kind to any kind |

## The pieces and their interfaces

**`mapgraph`** sets `ctx.lib.mapGraph = { build = function(data) return graph end }`:

```lua
graph = {
  doors = { [doorId] = { id = "ROUTE_29:3", map = "ROUTE_29", warp = 3, complex = complexId,
                         inside = { { map = "...", warp = n }, ... } } },
  complexes = { [complexId] = { id = complexId, maps = { mapId, ... }, environment = "INDOOR",
                                doors = { doorId, ... }, deadEnd = true, story = false, kind = "house" } },
  outdoor = { [mapId] = true },
}
```
`kind` is one of `house`, `center`, `mart`, `gym`, `gate`, `cave`, `dungeon`, `building`. `story` marks
complexes that must not move (see `maprules`, which owns that list; `mapgraph` leaves it false).

**`maprules`** sets `ctx.lib.mapRules = { model = function(data, graph) return rules end }`:

```lua
rules = {
  fixed = { [complexId] = "reason" },            -- never shuffled (Elm's lab, gyms, story buildings ...)
  regions = { [regionId] = { maps = { ... } } }, -- outdoor areas walkable without anything more
  needs = { [edgeKey] = { "SURF", "BADGE_FOG", "EVENT_..." } }, -- what crossing between regions needs
  doorRegion = { [doorId] = regionId },          -- which region an outdoor door stands in
  complexNeeds = { [complexId] = { exits = { [doorId] = { need, ... } } } }, -- moving through a complex
  canWin = function(placement, hmPlacement) return ok, why end,  -- the whole game is beatable
}
```
HMs come from `ctx.shared.keyitems` when the HM shuffle is on, else vanilla.

**`mapplacer`** sets `ctx.lib.mapPlacer = { place = function(graph, rules, level, rng, hmPlacement)
return placement, report end }`: `placement[doorId] = doorId'` (door A now leads where door A' led). Only
doors the level allows move, kinds only within the level's pools, story complexes fixed, and only a
placement that `rules.canWin` accepts. Deterministic for the rng given.

**`maps`** owns the question and applies: in `ctx.onSave`, builds the graph once from vanilla data, places,
then rewrites outdoor warps' `destMap`/`destWarp` and, where a complex's way out is an explicit warp rather
than `0xff`, that warp too, so leaving a complex returns to the door used. It keeps the vanilla warp
values and restores them exactly, and publishes `ctx.shared.maps = { placement = ..., report = ... }`.

**`mapmoves`** makes the other ways of moving agree with shuffled doors: Escape Rope and Dig, Fly and
Teleport, blacking out, elevators, the shared Pokémon Center upstairs, and anything else that remembers
a door. Through hooks or wrappers, only while `ctx.shared.maps` is set.

**Our accessibility layer** (`src/access/nav`) must name a door by where it leads now and plan routes over
the shuffled doors.

## Rules

- Never strand: if no placement passes `canWin` within a bounded search, place nothing for that save and log
  it; the save plays with vanilla doors.
- Everything per save, deterministic, restored exactly; nothing written to the save but the seed and answers.

## As built (2026-11-08)

- **Entrances.** A doorway can be two tiles; `mapgraph` groups adjacent outdoor tiles into one entrance
  (`graph.entrances`, `door.entrance`), and `complex.deadEnd` counts entrances. The placer moves whole
  entrances and returns `placement.entrances[E] = E'`, plus `placement[doorId]` = the target entrance's first
  door for every tile. `maps` rewrites every tile of E to the target, and the target complex's explicit
  exits to E's first tile; `0xff` exits already return to the tile used.
- **The Center upstairs** (`POKECENTER_2F` and its link rooms) is an annex shared by every center, not a
  complex. The Goldenrod Dept Store complex includes the Underground; the Indigo center includes the Elite
  Four rooms.
- **Crystal's counts:** 290 door tiles in 247 entrances into 188 complexes; 145 dead ends.
- **Fixed** (`maprules`, 49 complexes): New Bark's lab and house, all gyms, the Radio Tower and Dept Store
  with the Underground, the flower shop, the Magnet Train, the Mahogany mart and hideout, Ilex Forest and its
  gates, the Slowpoke Well, Kurt's house, the Ruins, Tin and Burned Towers, the National Park gates, the
  lighthouse, the Cianwood pharmacy, the S.S. Aqua and ports, Mr. Pokémon's house, the Dragon's Den, Victory
  Road and its gate, the Indigo center, the Battle Tower, Kanto's story places and the closed Safari Zone
  gate (its Fuchsia door is a wall; found by the end-to-end test).
- **canWin** walks the Johto story from the starter to the League through the placed doors, in the keyitems
  module's strict style, and agrees with it on all 5040 HM orders with vanilla doors. Kanto is closed to it,
  so post-game Kanto is not guaranteed. One-way ledges, Rock Smash and darkness are not modelled; Dark Cave is
  never a route.
- **mapmoves** wraps `World:escapeRopeTarget` (the door used wins), `World:healPoint` (blackout and Teleport
  land at the moved door of the center last used) and observes `recordWarpBackup`, only while a placement is
  active. Fly, elevators and the Center upstairs needed nothing.
- **Navigation** already read warps live; `src/access/nav/gen2/Navigation.lua` now rebuilds a planned map
  whose warps changed, and applies a `0xff` return warp only on the map the player stands on.

## Verification

Each module's luajit test passes, also on the real Crystal data. `tests/maps_e2e.py` runs the whole mod in
silent Crystal runs: 12 of 12 passed (houses, caves and full, seeds 424242, 190731, 777001, 555123), 83 to
89 checks each. Every shuffled door walked arrived where the placement said and led back out to the door
used; navigation named every shuffled town door by its new destination; the Escape Rope landed at the door
used; `canWin` held; the save switch took about 0.1 s at most. Doors were walked from a teleport, not by
auto-walk, and nothing was heard. Installed in the owner's save folder for testing at their request (2026-11-08, "update it so I can test"); not yet played.
