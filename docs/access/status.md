# Status

**Current focus (2026-10-31):** Gen 1 speech foundation done and heard by
the owner ("really good"); dialogue paced chunk by chunk at their request.
Published as a public GitHub fork (decision 19). Next workstream not chosen.

Each workstream section is edited only by the session working on it. Keep each
one short: state, next steps, blockers. Remove a section when its work is done
and recorded in the topic file.

## Repository

- `main` starts at upstream tag `v0.3.98` (commit `4312fb64`). Remotes:
  `upstream` (bryanthaboi/pokemon-gen1-recomp-project) and `origin` (the
  public fork `pocket-accessibility` under the owner's GitHub account).
- Commits use the owner's GitHub username and noreply address (decision 13).
- `core.autocrlf false` keeps upstream's line endings.
- The fork, like every fork, contains upstream's proprietary launcher files
  in its tree and history; the GitHub Fork route was chosen for that reason
  (decision 19). Our builds must not include them.

## Speech foundation

- **State:** done. Prism through LuaJIT FFI, one hook in `main.lua`. Heard by
  the owner through NVDA on 2026-10-31. Details: `speech.md`.
- **Later:** move to Prism 0.18.3 and re-check the declarations before packaging.

## Menus and text

- **State:** every Gen 1 screen class has a presenter except Yellow's
  surfing minigame, with no edits to screen files. Mod screens can opt in
  with `accessibilityText`. Dialogue follows the game's A presses. Unit
  suites 28, 37, 13, 14 and 32 checks, all passing. Scripted game runs in
  disposable identities cover Red and Yellow. Details: `menus-and-text.md`,
  `battle.md`, `yellow.md`.
- **Next:** surfing minigame (design in `yellow.md`, awaiting the owner);
  game runs for minor screens, `MoveSelectMenu`, evolution and trade; the
  owner's judgement on wording and verbosity from playing.

## Before any packaged release

- Our own launcher (decision 4). Upstream's self-updater off, upstream's
  launcher files excluded (`architecture.md`).
- Upstream License Term 1 also requires the credit in the app's credits,
  about or title screen and in our launcher.
- Decide on upstream's Discord rich presence.

## Open questions for the owner

- Should saves from the old Purple build load in the new one?
- Next workstream: navigation (Pokémon Access features), the launcher, or the
  surfing minigame?

## Not started

Navigation, launcher, save editor accessibility.
