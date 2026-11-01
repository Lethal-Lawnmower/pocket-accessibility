# Old project inventory: carry over, rewrite, drop

Written 2026-10-31. Nothing has been copied or moved.

> **Owner decision, 2026-10-31: fresh code.** All accessibility code is written
> new. Old code is *reference only*: read it for behaviour and hard-won edge cases
> (ledges, Cut and other HMs, warps, doors, puzzle rooms), but do not copy it in.
> The owner's reason: full control, and knowing exactly what works and what
> breaks. Wherever this document says "carry over" for code (sections 1 to 3
> below), read "use as reference". Non-code items still carry over: key bindings
> (reviewed), research notes (re-checked), Prism, and active owner decisions.
> Exception path: if an old module proves solid on review, reusing it needs a
> specific owner decision.

## Source of truth used

The old project's own status page names the active code as
`purple-gen1-gen2-preview` (branch `purple/gen1-gen2-preview-v0.3.32`, HEAD
`71cdd419e`). Its upstream base is the v0.3.32 merge commit `63aaaa178`.
Measured with `git diff --numstat 63aaaa178 HEAD` (git dir
`pokemon-gen1-recomp-project/.git/worktrees/purple-gen1-gen2-preview`):

| Area | Files | Lines added |
|---|---:|---:|
| Purple launcher, mods, import, cache, sync, platform storage (`src/`) | 149 | 34,528 |
| Their tests | 399 | 73,127 |
| Accessibility core (`src/accessibility/`) | 21 changed, 13 Lua modules now | 10,256 (7,396 lines today) |
| Accessibility tests | 52 | 12,316 |
| Speech edits inside upstream screens (Gen 1 and Gen 2) | about 130 | about 7,500 |
| Save editor accessibility (`tools/save-editor/`) | 18 | 2,183 |
| Docs inside the repository (`docs/`) | 161 | 22,829 |
| **Total** | **1,008** | **168,262** |

Roughly one line in ten was accessibility. The rest was the launcher and its
mod, import and cache machinery, which the restart replaces with a small native
Windows app. Test categories were assigned by filename pattern, so the split is
approximate.

## Owner rule: no old game fixes (2026-10-31)

The owner approved this inventory and added a rule: none of the old project's
own map, code or game fixes carry over. They were patches for an early, unstable
upstream, which is now mostly stable. Only accessibility moves.

How this is applied:
- Drop every gameplay, map, battle, save-format or engine correction the old
  fork carried, including the "defended" rows in the old
  `docs/upstream-divergence-ledger.md` (PARITY guards, refusal and atomicity
  guards) and fix-style edits such as `src/world/CutTrees.lua`,
  `src/world/ChaosCut.lua`, and the non-speech parts of `BattleState`,
  `SaveData`, `Data` and the gen 2 world files.
- When a carried accessibility file assumed an old fix, rewrite it against
  upstream's current behaviour instead of bringing the fix along.
- Accessibility-only behaviour, such as routing to the reachable side of a Cut
  tree (`A11Y-001`), is accessibility and may carry over.
- If an upstream bug blocks accessibility, record it and ask the owner. No
  silent local fix, and no contact with upstream without permission.

## Carry over (review, then copy)

1. **Accessibility core**, `src/accessibility/` (13 modules, 7,396 lines):
   `Speech`, `ApplicationSpeech`, `BackendLoader` (Prism over FFI), `SpeechTrace`,
   `Pathfinder`, `RegionalPathfinder`, `TerrainSemantics`, `TraversalSemantics`,
   `WorldSnapshot`, `PuzzleAssistance`, `Earcons`, `CommandRouter`.
   `Accessibility.lua` alone is 3,300 lines and should be split by
   responsibility on the way in (see Rewrite).
2. **Accessibility tests** that cover the modules above (subset of the 52 files),
   adapted to the new layout.
3. **Save editor accessibility** (`tools/save-editor/` `App`, `Kit`,
   `EditorNavigation`, panels). Re-apply onto the current upstream editor
   rather than copying old files over newer upstream ones.
4. **Key bindings**: the command set in `CommandRouter` and the bindings menu
   changes, reviewed with the owner, not imported blindly.
5. **Research notes** in `research/`: `TARGET_ACCESSIBILITY_SEAMS.md` (2026-07-20
   map of where the engine can be observed; its core advice is to observe
   settled state after `StateStack:update`, use the non-mutating mod events, and
   give battles their own adapter), `POKEMON_ACCESS_RED_INVENTORY.md` and
   `MOD_ACCESSIBILITY_DESIGN.md`. These are reference material and are re-checked
   against current upstream before anything relies on them.
6. **Prism v0.17.3** (`local-deps/`: Windows x64 binaries and source).
   License MPL-2.0, which is compatible with GPLv3. Check for a newer release
   before pinning.
7. **Active owner decisions** from `Documentation/`: extract only rules that
   still apply (speech style, controls, honesty rules) into the new decision log.
   The 1.6 MB archive itself does not move.

## Rewrite (keep the behaviour, change the structure)

1. **Speech inside upstream screens.** The old fork added 50 to 275 lines of
   speech logic directly into about 40 Gen 1 screens (`BattleState`,
   `BoxMenu`, `BagMenu`, `SummaryMenu`, `PartyMenu`, `PlayerPC`,
   `MoveLearnMenu`, `ShopMenu`, `NamingScreen`, `DexEntryMenu`, `TownMap`,
   `ChoiceBox`, `ListMenu`, `Menu`, `TextBox`, `StartMenu` and others). In the
   new design that logic moves into our accessibility folder, and each screen
   keeps at most a small, listed hook. This is the largest piece of real work.
2. **`Accessibility.lua`** (3,300 lines): split into focused modules (focus
   speech, dialogue, battle, overworld, settings) while moving it.
3. **Game start-up wiring** (`main.lua` +763, `Game.lua`, `SaveData.lua`):
   almost all of the `main.lua` change is launcher wiring and is dropped. Only
   the accessibility boot hook and the command-line arguments our Windows
   launcher needs (game choice, ROM import, editor) are rewritten.
4. **Sounds**: our own default set, plus the bring-your-own Pokémon Access pack.
   `Earcons.lua` already supports an external pack with generated fallbacks.

## Parked (keep in the archive, revisit after Red, Blue and Yellow)

- Gen 2 speech edits (`src/ui/gen2/*`, `Game2.lua`, `src/world/gen2/*`) and the
  Gen 2 docs. Useful reference when Gold, Silver and Crystal come back into scope.
- Gen 3 (upstream now has it) and Android: already parked by the owner.

## Drop

- The Purple launcher and everything under it: 149 `src/` files
  (`Purple*`, `Windows*`, `Linux*` storage and probes, mod install,
  preferences, sources, covers, mascots, cries, carousel, onboarding), their
  399 test files, and the `tools/purple_*.py` release and packaging scripts.
- The 161 in-repository docs, which are mostly launcher and cache audits.
  Anything still true about accessibility gets rewritten into the new topic docs.
- The 14 version intake, integration and audit checkouts, the
  `launcher-overhaul-worktree`, `V0159_*` merge logs and suite dumps, and the two
  zip snapshots. They stay on disk as the archive; they do not migrate.
- `audit-tools/` (contains only a `python3.exe`).

## Never goes into the new repository

- ROMs: `red/` (all six cartridges) and `local-input/`.
- Saves: `save-backups/` and any player saves.
- The Pokémon Access sound pack (bring-your-own only).
- Private handoffs: `CLAUDE_HANDOFF_PRIVATE.md`, `CLAUDE_UNDERSTANDING.md` and the
  handoff zip.
- `research/pokered` (the disassembly) and `research/pokecrystal-access`:
  local reference only.

## Open questions for the owner

1. Is anything in the drop list something you actually want?
2. Should old saves from the Purple build load in the new one?
3. Any old accessibility behaviour you disliked and do not want carried over?
