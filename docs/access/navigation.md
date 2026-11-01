# Navigation

Getting around the overworld: object list, pathfinding, camera ("sonar"),
terrain and footstep cues, puzzle help. Reused from the old project under
decision 20, adapted to v0.3.98. Status: wired into the game and working
for the core Pokémon Access commands; walking cues and wall bumps not yet
checked in a game run.

## Reused modules (`src/access/nav/`)

Each file starts with an origin header naming the old file and commit
(`purple-gen1-gen2-preview`, `71cdd419`).

| Module | Role | Old tests ported |
|---|---|---|
| `Pathfinder` | Routes on one map | 60/60 |
| `RegionalPathfinder` | Routes across maps | 82/82 |
| `TerrainSemantics` | What a cell is (grass, water, ledge, door, bush...) | 131/131 |
| `TraversalSemantics` | Special movement (spinners, currents, holes) | (covered by snapshot) |
| `WorldSnapshot` | Map, player, warps, connections, signs, objects; the object list | 70/91, see below |
| `PuzzleAssistance` | Detours through puzzle rooms | 50/50 |
| `Navigation` | The old coordinator (`Accessibility.lua`), navigation half: commands, object list, routes, sonar, world events, renaming | commands 247/247, world events 37/37, journey 27/27, interactive objects 12/13 |
| `init.lua` | Creates the coordinator for a loaded Gen 1 game, speech adapter, key routing | (game run) |
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
- Interactive objects 12/13: the bedroom SNES does not appear in the object
  list (the PC does). Not yet investigated.
- Camera ("sonar") is off by default (decision 22): its keys pass through
  to the game and F8 help omits them unless `accessibilityCamera` is set in
  the save options. `CommandRouter.isCameraAction` decides which actions
  count; `tests/access/camera_option_test.lua` 8/8. No menu sets the
  option yet, and the camera path was not re-checked in a game run.
- Walking: step and terrain cues, ledges and continuous route guidance
  while moving have not been exercised in a game run yet.

## How it is wired (`src/access/nav/init.lua`)

- `Access.install` wraps `love.keypressed` *before* upstream: the old
  `CommandRouter` sees every key first and consumes recognised commands.
  F7 toggles the command layer (WASD is then reserved, arrows still move),
  F8 reads help, F6 repeats.
- The coordinator is created once a Gen 1 game is loaded (Game module with
  `save` and `data`) and re-created when the save or the mod event bus
  (`Runtime.events`) changes. It subscribes to upstream's `map.entered` and
  `world.stepped` events.
- Speech goes through an adapter over `src/access/Speech` (Prism). The old
  start-up line ("Screen reader ready. Press F6 to repeat. Press F7 for
  accessibility command mode. Press F8 for help.") plays once per game load.
- `updateNavigation()` (added) runs routes, events and cues each frame; the
  old `describe()` screen speech is not driven (new presenters do that).

## Other adaptations in the coordinator

- Speech stack replaced by the adapter (BackendLoader, Speech, SpeechTrace).
- T (read screen text) repeats the last screen speech from the new
  presenters (`Speech.lastScreenText`).
- Renaming (Shift+K, Shift+M) prefills upstream's NamingScreen glyph list
  with the current name; the old fork had added an initial-text option to
  that upstream file instead.

## Game run (2026-10-31)

`tests/access/drivers/navigation.lua` (keys sent through `love.keypressed`),
disposable identity `pocket-access-run`: F8 help, F7 on and off, map name,
position, object list with directions ("PC, 5 up 3 left"), filter change,
surrounding tiles, pathfinding start ("1 right"), and Pallet Town's warps
("Oaks Lab: 4 down 3 right"). Not yet heard by the owner.
