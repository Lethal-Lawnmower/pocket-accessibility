# Pocket Accessibility documentation

Pocket Accessibility (working name) adds screen-reader accessibility to the
Pokémon Gen 1 Recompilation Project, a native PC port. It is built as a thin
layer on our own fork; see `architecture.md`.

## Start here

Every session reads these two files first:

1. `status.md`: what is happening now and what comes next, by workstream.
2. `decisions.md`: the owner's decisions. Do not act against them.

Then read only the topic file for the area you are working on.

## Files

| File | Holds | Limit |
|---|---|---|
| `README.md` | This index and the rules below | 1 page |
| `status.md` | Current focus, one section per workstream | about 150 lines |
| `decisions.md` | Append-only owner decisions | short entries |
| `architecture.md` | How the layer sits on upstream, the hook list, launcher interface | about 300 lines |
| `old-project-inventory.md` | What the old project contained and how it is used | temporary; delete once migration-by-reference is finished |

Topic files are created when work on that area starts, not before:
`speech.md`, `navigation.md`, `menus-and-text.md`, `battle.md`, `launcher.md`,
`save-editor.md`, and one file per game holding differences only (for example
`yellow.md`; Gold, Silver and Crystal share an engine: screens in
`gold-silver-crystal.md`, navigation and the edition audit in
`gold-silver-crystal-navigation.md`; FireRed and LeafGreen in
`firered-leafgreen.md`). About 300 lines each.

## Rules

- **Update in place.** Correct the existing section; do not add dated,
  per-finding or per-session files.
- **Git is the history.** Commit messages say what changed and why. Docs say
  what is true now.
- **Split by subject, never by date.** A file over its limit splits along the
  system it covers (for example navigation into pathfinding and camera).
- **Status:** edit only your workstream's section, plus the one-line current focus.
  Re-read the file right before editing.
- **Decisions:** append only. Mark replaced entries; never rewrite them.
- **Parallel sessions:** each works on its own git branch.
- **Evidence:** say what level was reached (source read, test passed, run in
  game, heard, owner accepted). A passing test is not proof of usable speech.
- **No** evidence catalogs, receipts, intake folders, archive copies or empty
  placeholder files.
- **No individual people's names.** Name projects, not their developers.
  Upstream's required credit is the exception. The README's Goal section also credits the
  Pokémon Access authors (nuive; Tyler Spivey for Pokécrystal Access) at the
  owner's request (2026-10-31).
