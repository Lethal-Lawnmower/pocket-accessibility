# Status

**Current focus (2026-10-31):** speech foundation built and verified up to a
real game start; waiting on the owner to hear it. Next: pick the following
workstream (menus and text, launcher, or navigation).

Each workstream section is edited only by the session working on it. Keep each
one short: state, next steps, blockers. Remove a section when its work is done
and recorded in the topic file.

## Repository

- `main` starts at upstream tag `v0.3.98` (commit `4312fb64`). Remote
  `upstream` only; no `origin`, nothing pushed.
- Commits so far use the old project pseudonym. Re-author to the owner's GitHub
  username before the first push (decision 13).
- `core.autocrlf false` keeps upstream's line endings.

## Speech foundation

- **State:** `src/access/` (init, Speech, speech/PrismBackend) and one hook in
  `main.lua`. Unit tests pass (32/32). Real Prism selected NVDA. A real game
  start logged `speech ready: NVDA`. Details: `speech.md`.
- **Needs the owner:** start the game from source (`love .` in this folder,
  with `prism.dll` in `local-deps/prism/`) and confirm "Pocket Accessibility
  ready." is heard.
- **Later:** move to Prism 0.18.3 and re-check the declarations before packaging.

## Before the first push (not authorized yet)

1. Owner go-ahead on the GitHub setup (decision 15).
2. Re-author local commits.
3. Review docs for wording and names.
4. Add the project section and upstream credit to the top of `README.md`.
5. **Owner decision needed: upstream's proprietary launcher files in our
   repository.** The tree and its history contain them unchanged, as every
   fork does. License Term 2 forbids copying or redistributing them in a fork.
   A GitHub-button fork stays inside GitHub's own forking terms. A separately
   created repository would itself redistribute them. Options: use the GitHub
   fork route, or delete those files from our tree (history still holds them).
   Not legal advice; decide before pushing.

## Open questions for the owner

- Should saves from the old Purple build load in the new one?
- Next workstream: menus and text, launcher, or navigation?

## Not started

Menus and text, navigation, battle, launcher, save editor accessibility.
