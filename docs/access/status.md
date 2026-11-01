# Status

**Current focus (2026-10-31):** repository set up and documentation in place.
No accessibility code yet. Next step needs the owner: choose which workstream
starts first.

Each workstream section is edited only by the session working on it. Keep each
one short: state, next steps, blockers. Remove a section when its work is done
and recorded in the topic file.

## Repository

- `main` starts at upstream tag `v0.3.98` (commit `4312fb64`). Remote
  `upstream` only; no `origin`, nothing pushed.
- Our files: `docs/access/`, root `CLAUDE.md` and `AGENTS.md`, and a marked
  block at the end of `.gitignore` (ROMs, saves, sound packs, Prism binaries,
  launcher build output; checked with `git check-ignore`).
- Commits so far use the old project pseudonym. Re-author to the owner's GitHub
  username before the first push (decision 13).
- `core.autocrlf false` keeps upstream's line endings.

## Before the first push (not authorized yet)

1. Owner go-ahead on the GitHub setup (decision 15).
2. Re-author local commits.
3. Review docs for wording and names.
4. Add the project section and upstream credit to the top of `README.md`.

## Open questions for the owner

- Should saves from the old Purple build load in the new one?
- Which workstream starts first: speech foundation, launcher, or navigation?

## Not started

Speech foundation (Prism), menus and text, navigation, battle, launcher,
save editor accessibility. Each gets a section here when work begins.
