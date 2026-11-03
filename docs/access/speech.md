# Speech

How the accessibility layer speaks. Prism is the only speech path
(decisions 3 and 9).

## Pieces

| File | Role |
|---|---|
| `src/access/init.lua` | Layer entry. `Access.install()` starts speech, announces "Pocket Accessibility ready.", and closes speech when the game really quits. |
| `src/access/Speech.lua` | The one speaking API: `Speech.say(text, { interrupt = true })`, `Speech.stop()`, `Speech.available()`, `Speech.status()`. |
| `src/access/speech/PrismBackend.lua` | Finds and loads Prism through LuaJIT FFI, acquires Prism's best backend, sends text. |

## Rules for callers

- **Focus changes interrupt** (`interrupt = true`), so moving through a menu
  never builds a backlog of stale names. Follow-up information queues.
- Blank text is refused and logged; it means a caller bug.
- `POKEPORT_ACCESS_TRACE=1` logs every utterance as `[access] say: ...`
  (`say!:` when it interrupts), for scripted runs and bug reports.
- `POKEPORT_ACCESS_SILENT=1` keeps that trace but never sends speech to the
  screen reader, for scripted runs while someone is at the computer.
- `POKEPORT_ACCESS=0` skips the whole layer (plain upstream), to tell our
  bugs from upstream's.
- If Prism cannot load, `Speech.say` returns false and the game runs silent.
  The reason is logged and kept in `Speech.status()`. There is no fallback to
  another speech library.

## Output

`PrismBackend` uses Prism's *output* call (speech plus braille) when the
backend supports it, otherwise plain *speak*. Prism chooses the backend: the
running screen reader first, then system voices.

## Finding prism.dll

Search order (`PrismBackend.candidates`):

1. `POKEPORT_PRISM_DLL`, an explicit path.
2. The folder holding the game folder, then the game folder.
3. `local-deps/prism/` under each of those. The packaged folder and a source checkout both use `game\local-deps\prism`.

The launcher's "speech library was not found" warning checks the same places (`GamePaths.HasPrism`).

`local-deps/` is git-ignored, so binaries are never committed. For a source
checkout, copy `prism.dll` from the Prism release's `dynamic/release/bin/`
into `local-deps/prism/`.

Prism releases also ship `tolk.dll`, a compatibility layer. Never load or
ship it; only `prism.dll` is used.

## Version

Developing against Prism 0.17.3 (MPL-2.0, Windows x64), from the old
project's local copy. The packaged folder ships this build: its DLL is byte-identical to the Prism
0.17.3 Windows x64 release, whose `NOTICE` and `LICENSES` are shipped with it. Prism 0.18.3 exists (GitHub, checked
2026-10-31). Moving to it, and re-verifying the C declarations, is left for after the first package.
The declarations in `PrismBackend.lua` are copied from 0.17.3's `prism.h`.

## Verification (2026-10-31)

| Level | Result |
|---|---|
| Unit tests | `luajit tests/access/speech_test.lua`: 32/32 passed (fake backend; routing, interrupt, blank text, failures, install and quit wiring, library search order, missing-library message). |
| Real Prism, outside the game | LuaJIT loaded `local-deps/prism/prism.dll`; Prism chose **NVDA** (features 181: output and speak supported); output of a test phrase returned success. |
| Real game start | `lovec.exe .` from the repository root logged `[access] speech ready: NVDA`, then reached upstream's launcher. Output was captured by temporarily unbuffering stdout; that line was removed afterwards. |
| Heard by the owner | **Yes, 2026-10-31.** First listening session (Red from source, `POKEPORT_GAME=red`): speech is audible through NVDA. Owner: "This is really good." Field report: a dialogue page is spoken whole, ahead of the lines the game reveals after each A press. |
