# Architecture

Status: speech foundation exists (see `speech.md`); everything else is
planned. Update this file as each part is built, and mark what is planned
and what exists.

## Layers

1. **Upstream game** (everything not listed below). Kept as close to upstream
   as possible. Changes are limited to hooks in the hook list.
2. **Accessibility layer**, planned under `src/access/`. All speech, sound
   cues, navigation, commands and settings. Speech goes through Prism, loaded
   in-process with LuaJIT FFI. No other speech system, no fallback, no bridge.
3. **Launcher**, planned under `launcher/`. A separate native Windows app (C#
   Windows Forms on .NET 10, agent recommendation) with standard controls.
   It starts the game program with command-line arguments.

## Observation principles

From the old project's seam research, to be re-checked against v0.3.98
before relying on it:

- Read settled game state once per update, after the state stack updates.
  Do not scrape what is drawn, and do not speak from the render loop.
- Prefer read-only observation of game data (map, collision, warps, NPCs,
  party, battle state) over hooks. Most navigation needs no hooks.
- Upstream's mod *events* can be observed without changing behaviour. Its
  mod *hooks* are middleware and can change behaviour, so do not use them
  merely to observe.
- Battles need their own adapter, because battle text does not go through
  the normal text box.

## Hook list

Every change to an upstream file must be listed here, and so must every
runtime wrapper or read of upstream internals. When updating upstream,
check exactly these places.

| File | Function or place | What it reports | Added |
|---|---|---|---|
| `main.lua` | `love.load`, right after `Boot.run(args)` | Calls `require("src.access").install()`, starting the layer before any game, editor or importer path | 2026-10-31 |
| `main.lua` (runtime wrapper, no edit) | `love.update`, `love.quit` | `Access.install` wraps both; ours runs after upstream's and passes its return value through | 2026-10-31 |
| `src/core/StateStack.lua` (read only) | `StateStack.states` | Top screen each frame; relies on Gen 1 `Game` using the module as its stack | 2026-10-31 |
| `TextBox`, `Menu`, `ListMenu`, `ChoiceBox` (read only) | Fields `pages`, `pageIndex`, `items`, `index`, `title`, `labels`; row fields `label`, `level`, `sub`, `price`, `count`, `right` | Speech for dialogue and menus (`menus-and-text.md`) | 2026-10-31 |
| Gen 1 screens (read only): `QuantityBox`, `NamingScreen`, `PartyMenu`, `SummaryMenu`, `MoveLearnMenu`, `MoveSelectMenu`, `TrainerCard`, `PokedexMenu`, `DexEntryMenu`, `OptionsMenu`, `TownMap` | Their cursor and page fields; read-only methods `NamingScreen:grid`, `PartyMenu:bottomMessage`, `TownMap:bannerText`, options row `value`; `PartyMenu:draw`'s TM and stone checks and `DexEntryMenu`'s page split are mirrored | Screen speech (`menus-and-text.md`) | 2026-10-31 |
| Minor screens (read only): `TitleState`, `IntroMovie`, `YellowIntro`, `LeaguePC`, `PrizeCounter`, `SlotMachine`, `HallOfFame`, `Diploma`, `Credits` | Their index, stage, message and screen fields; `game.data.text` Diploma strings | Screen speech (`menus-and-text.md`) | 2026-10-31 |
| Extra screens (read only): `ManagerState`, `QuarantineReport`, `LinkState`, `Gen1BattlePrep`, `Gen1TradePrep`, `PicBox`, `SurfHiScore` | Mod manager `screen`, `tab`, `cursor`, `overlay`, `notice`, `optionRows`, read-only `rowsForScreen`, `isStaged`, `runsHere`; link `stage`, `index`, `side`, `trade`, `willText`, `listLabel`; union page models' `page`, `label`, `formatLines` | Screen speech (`menus-and-text.md`) | 2026-10-31 |
| `src/world/OverworldController.lua` (read only) | The module is Gen 1's overworld (`Game.overworld = OverworldState`); field `emote.pikaPic`, traced through `field.pikachu.emotions` and `.pics` | Pikachu reactions (`yellow.md`) | 2026-10-31 |
| `main.lua` (runtime wrappers, no edit) | `love.keypressed` (ours first, may consume), `love.keyreleased` | Navigation command keys (`navigation.md`) | 2026-10-31 |
| `main.lua` (runtime wrappers, no edit) | `love.gamepadaxis`, `gamepadpressed`, `gamepadreleased` (ours first, may consume) | Controller navigation (`navigation.md`) | 2026-10-31 |
| `src/core/Input.lua` (input injection) | Auto-walk holds directions in `sources`, `pressQueue`, `state` under its own source; `padEventSeen` marks D-pad presses used for navigation | Auto-walk, controller navigation | 2026-10-31 |
| `src/mods/Runtime.lua` events (subscribe only) | `map.entered`, `world.stepped` through `Runtime.events:on` | Navigation world events | 2026-10-31 |
| `BattleState.lua` local `StatBox` (read only) | Recognised by `debug.getinfo(mt.draw).source`; fields `mon.stats`, `mon.level`, `mon.species` | Level-up stats speech (`battle.md`) | 2026-10-31 |
| `src/battle/BattleState.lua` (read only) | `phase`, `current.text`, `menuIndex`, `moveIndex`, `mimicIndex`, `mimicMoves`, `safari.balls`, `demo`, `player.mon`, `player.curMoves`, `player.disabledSlot`, `enemy.mon`, `data` | Battle speech (`battle.md`) | 2026-10-31 |

## Launcher to game interface

Upstream's `main.lua` (v0.3.98, `love.load`) already supports everything the
launcher needs, so no game-side change is planned. Read from source; not yet
exercised by our launcher.

| Purpose | How | Status |
|---|---|---|
| Start a specific game, skipping upstream's launcher | `POKEPORT_GAME=red`, `blue` or `yellow`; optional `--slot <id>` | exists upstream; verified 2026-10-31 |
| Import a ROM without any launcher | `POKEPORT_IMPORT_ROM=<path>` with `POKEPORT_IMPORT_ONLY=1`; quits when done | exists upstream |
| Open the save editor | `--editor`, optional `--save <path>`, game from `POKEPORT_VERSION` | exists upstream |

**Do not pass `--game` on the command line from source** (`love . --game red`): on 2026-10-31 that failed before `main.lua` ran (no output at all, with the layer on or off), and the owner saw LÖVE's blue error screen. `POKEPORT_GAME=red` works. Re-check this for packaged builds.

Without a game choice, upstream's own proprietary launcher opens. Our packaged
build must never reach that path (see packaging notes below).

## Packaging notes (for the launcher workstream)

- **Upstream's self-updater must be off in our builds.** `src/update/Boot.lua`
  and `Check.lua` download upstream's `gen1recomp-X.Y.Z.love` from upstream's
  GitHub releases and mount it above the bundled code. In our build that would
  silently replace our accessibility layer with plain upstream. Source
  checkouts never self-update; packaged builds would.
- Upstream's proprietary launcher files (License Term 2) must not be in our
  distributed build.
- Upstream connects to Discord rich presence at start-up when Discord is
  running (log: "discord: rich presence connected"). Decide whether our build
  keeps that; it shares what the player is doing with Discord.

## Licensing boundaries

- Upstream code: GPLv3 with Section 7 terms. Credit required in the README and
  in the app (Term 1).
- Upstream launcher files (Term 2 list in `LICENSE.MD`): never copied or used.
- Prism: MPL-2.0, compatible with GPLv3. Binaries are not committed.
- Pokémon Access: no license. Use its features as ideas only. Its sounds are
  bring-your-own and never shipped.
