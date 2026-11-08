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
