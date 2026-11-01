# Agent instructions

This repository is **Pocket Accessibility** (working name): screen-reader
accessibility for the Pokémon Gen 1 Recompilation Project, built as a thin layer
on our own fork. Everything outside our folders is upstream code.

## Start every session here

1. Read `docs/access/README.md` (the index and documentation rules).
2. Read `docs/access/status.md` (current focus and workstreams).
3. Read `docs/access/decisions.md` (owner decisions; do not act against them).
4. Read only the topic file for your area.

## Hard rules

- **Our code lives in** `src/access/` (game side) and `launcher/` (Windows app).
  Any change to an upstream file must be a small hook and must be added to the
  hook list in `docs/access/architecture.md`.
- **No game fixes.** Do not patch upstream gameplay, maps, battles or saves. If an
  upstream bug blocks accessibility, record it in `status.md` and ask the owner.
- **Fresh code.** Do not copy code from the old project in the parent folder; it
  is reference only.
- **Speech goes through Prism only.** No other speech system, fallback or bridge.
- **Never commit** ROMs, saves, sound packs, Prism binaries, caches or private
  files. Never use or copy upstream's proprietary launcher files (see `LICENSE.MD`).
- **Never push, publish or contact anyone** without the owner's explicit approval
  for that specific action.
- **Documentation is part of every change.** Update status, the topic file and,
  for owner decisions, `decisions.md`, following the size and update rules in
  `docs/access/README.md`. Do not create new kinds of documents.
- **Report honestly.** Name the level reached: source read, test passed, run in
  game, speech heard, owner accepted. A test pass is not proof of usable speech.
- **Parallel work** happens on separate git branches.

## Owner

The owner is blind and uses a screen reader. Describe visual state in text. Do not
rely on them reading screenshots or finding visual controls. They playtest and
accept; agents audit, implement, test and document.
