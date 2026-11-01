# Navigation

Getting around the overworld: object list, pathfinding, camera ("sonar"),
terrain and footstep cues, puzzle help. Reused from the old project under
decision 20, adapted to v0.3.98. Status: modules ported, not yet wired into
the game.

## Reused modules (`src/access/nav/`)

Each file starts with an origin header naming the old file and commit
(`purple-gen1-gen2-preview`, `71cdd419`).

| Module | Role | Old tests ported |
|---|---|---|
| `Pathfinder` | Routes on one map | 60/60 |
| `RegionalPathfinder` | Routes across maps | needs the coordinator |
| `TerrainSemantics` | What a cell is (grass, water, ledge, door, bush...) | 131/131 |
| `TraversalSemantics` | Special movement (spinners, currents, holes) | (covered by snapshot) |
| `WorldSnapshot` | Map, player, warps, connections, signs, objects; the object list | 70/91, see below |
| `PuzzleAssistance` | Detours through puzzle rooms | needs the coordinator |
| `Earcons` | Sound cues, optional bring-your-own Pokémon Access pack | 21/21 |
| `CommandRouter` | Pokémon Access keys behind a command layer (F7) | 193/193 |
| `CutTrees` | Read-only lookup of cuttable trees | via terrain tests |
| `ChaosCut` | Labels for the optional Chaos Cut mod (decision 21) | via snapshot tests |

Old tests live in `tests/access/nav/`. The ones that need generated game
data are run from inside a test identity's Red cache, with the repository on
`LUA_PATH`, so no ROM data is copied into the repository:

```
cd "$APPDATA/LOVE/pocket-access-run/red"
LUA_PATH="<repo>/?.lua;<repo>/?/init.lua;;" luajit "<repo>/tests/access/nav/world_snapshot_tests.lua"
```

## Adaptations so far

- `CutTrees`: upstream generates no `cutTiles` data. The lookup now falls
  back to upstream's own rule from `OverworldState:tryCut` (OVERWORLD tile
  0x3d, GYM tile 0x50). Fixed the one terrain failure.
- Dropped dependency: none of these modules patch game behaviour. The old
  fork's in-game Cut fix (`src/world/CutTrees.lua` used by the overworld) is
  not carried over (decision 10); only the read-only lookup is.

## Known gaps

- `world_snapshot_tests`: 21 failures cascade from one synthetic fixture
  warp (destination LAST_MAP) that v0.3.98's `Map:warpAtCell` /
  `isWarpTileCell` no longer report as active, so it drops out of the browse
  list and every later index shifts. To check against real maps once the
  object list runs in game; adapt the filter or the fixture then.
- `world.bumped` (wall bumps) is not an upstream event; the old fork added
  it. Needs another source.
- Coordinator (the old `Accessibility.lua` navigation half: commands, object
  list browsing, routes, sonar, world events) is the next step.
