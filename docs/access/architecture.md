# Architecture

Status: planned. Nothing here is implemented yet. Update this file as each
part is built, and mark what is planned and what exists.

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

Every change to an upstream file must be listed here. When updating upstream,
check exactly these places.

| File | Function or place | What it reports | Added |
|---|---|---|---|
| (none yet) | | | |

## Launcher to game interface

Planned command-line arguments; names to be confirmed against upstream's
`main.lua` and `src/core/Prelaunch.lua`. Upstream already accepts `--editor`,
`--save` and `--update`.

| Purpose | Argument | Status |
|---|---|---|
| Start a specific game | to be decided | planned |
| Import a ROM file | to be decided | planned |
| Open the save editor | `--editor` (upstream) | exists upstream |

## Licensing boundaries

- Upstream code: GPLv3 with Section 7 terms. Credit required in the README and
  in the app (Term 1).
- Upstream launcher files (Term 2 list in `LICENSE.MD`): never copied or used.
- Prism: MPL-2.0, compatible with GPLv3. Binaries are not committed.
- Pokémon Access: no license. Use its features as ideas only. Its sounds are
  bring-your-own and never shipped.
