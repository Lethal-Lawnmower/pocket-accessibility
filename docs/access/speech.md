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
2. Beside the program (packaged build).
3. The source folder, then `local-deps/prism/` (source checkout).

`local-deps/` is git-ignored, so binaries are never committed. For a source
checkout, copy `prism.dll` from the Prism release's `dynamic/release/bin/`
into `local-deps/prism/`.

Prism releases also ship `tolk.dll`, a compatibility layer. Never load or
ship it; only `prism.dll` is used.

## Version

Developing against Prism 0.17.3 (MPL-2.0, Windows x64), from the old
project's local copy. Prism 0.18.3 exists (GitHub, checked 2026-10-31).
Upgrade and re-verify the C declarations before the first packaged build.
The declarations in `PrismBackend.lua` are copied from 0.17.3's `prism.h`.

## Verification (2026-10-31)

| Level | Result |
|---|---|
| Unit tests | `luajit tests/access/speech_test.lua`: 32/32 passed (fake backend; routing, interrupt, blank text, failures, install and quit wiring, library search order, missing-library message). |
| Real Prism, outside the game | LuaJIT loaded `local-deps/prism/prism.dll`; Prism chose **NVDA** (features 181: output and speak supported); output of a test phrase returned success. |
| Real game start | `lovec.exe .` from the repository root logged `[access] speech ready: NVDA`, then reached upstream's launcher. Output was captured by temporarily unbuffering stdout; that line was removed afterwards. |
| Heard by the owner | **Not yet.** No agent can hear the output; the owner should confirm that "Pocket Accessibility ready." is spoken at start-up. |
