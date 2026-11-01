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

## Launcher to game interface

Upstream's `main.lua` (v0.3.98, `love.load`) already supports everything the
launcher needs, so no game-side change is planned. Read from source; not yet
exercised by our launcher.

| Purpose | How | Status |
|---|---|---|
| Start a specific game, skipping upstream's launcher | `--game red`, `blue` or `yellow` (also `POKEPORT_GAME`); optional `--slot <id>` | exists upstream |
| Import a ROM without any launcher | `POKEPORT_IMPORT_ROM=<path>` with `POKEPORT_IMPORT_ONLY=1`; quits when done | exists upstream |
| Open the save editor | `--editor`, optional `--save <path>`, game from `POKEPORT_VERSION` | exists upstream |

Without `--game`, upstream's own proprietary launcher opens. Our packaged
build must never reach that path (see packaging notes below).

## Packaging notes (for the launcher workstream)

- **Upstream's self-updater must be off in our builds.** `src/update/Boot.lua`
  and `Check.lua` download upstream's `gen1recomp-X.Y.Z.love` from upstream's
  GitHub releases and mount it above the bundled code. In our build that would
  silently replace our accessibility layer with plain upstream. Source
  checkouts never self-update; packaged builds would.
- Upstream's proprietary launcher files (License Term 2) must not be in our
  distributed build.

## Licensing boundaries

- Upstream code: GPLv3 with Section 7 terms. Credit required in the README and
  in the app (Term 1).
- Upstream launcher files (Term 2 list in `LICENSE.MD`): never copied or used.
- Prism: MPL-2.0, compatible with GPLv3. Binaries are not committed.
- Pokémon Access: no license. Use its features as ideas only. Its sounds are
  bring-your-own and never shipped.
