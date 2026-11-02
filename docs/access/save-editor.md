# Save editor

A native Windows window (decision 39), opened with Edit save in the launcher:
standard tabs, lists, text boxes and buttons, read by the screen reader like any
Windows program. The first attempt, speech and keys laid over upstream's mouse
editor, was removed at the owner's request: it meant learning a vocabulary.

## How it fits together

| Part | Holds |
|---|---|
| `launcher/PocketLauncher/SaveEditorForm.cs` | Window, tabs, Save, Undo, Redo, Reload, Close, status line |
| `launcher/PocketLauncher/PagePanel.cs` | One page, drawn from the backend's description; no knowledge of any page |
| `launcher/PocketLauncher/SaveBackendClient.cs` | Starts the backend, sends one request at a time |
| `launcher/SaveBackend/main.lua` | Windowless LÖVE program (`lovec.exe`): upstream's `App.load`, `App.save`, `History`, `Ops`, and the protocol |
| `launcher/SaveBackend/pages/<id>.lua` | What each page shows and which `Ops` calls its controls make |

Save logic stays in upstream's `tools/save-editor/`, unedited: ranges, undo, backups
(`save.lua.bak-...` before each write) and `.sav` export all remain upstream's. The
form cannot run with a game on the same save because it is modal over the launcher.

## Protocol

One JSON object per line on stdin; one per line on stdout, prefixed `@@PA `. Other
output is upstream's logging. `print` goes to stderr.

Requests: `open {version, path?}`, `model {page}`, `select {page, row}`,
`pick {page, picker, value}`, `set {page, field, value}`,
`toggle {page, row, checked}`, `action {page, action}`, `save`, `undo`, `redo`,
`reload`. The page commands answer with a fresh `model`.

Every answer has `ok`, `error` (when not ok), `status`, `dirty`, `canUndo`,
`canRedo`, `canSave`, and `message` and `messageKind` when there is something new to
say. `messageKind` of `error` shows a message box; otherwise the status line, a live
region, reads it. Opening answers `title`, `path`, `pages`, `missingCache`, `corrupt`.

## A page

`pages/<id>.lua` returns a table. Only `model` is required.

```lua
function Page.model(S, state) return model end  -- S: upstream's state; state: this page's, kept between calls
function Page.select(S, state, request) end     -- default: state.selected = request.row
function Page.pick(S, state, request) end       -- default: state[request.picker] = request.value
function Page.set(S, state, request) end        -- request.field, request.value
function Page.toggle(S, state, request) end     -- request.row, request.checked
function Page.action(S, state, request) end     -- request.action
```

Edits call upstream's `Ops`, which reports through `S.status`; an error raised in a
page becomes a message box. `state` survives Undo but resets on Reload, so a page must
cope with a selection that no longer exists.

The model, all parts optional, in tab order:

```lua
{
  pickers = { { id, label, value, options = { { value, label } }, below = false } },
  summary = "read-only lines",
  list = { label, rows = { { id, text, checked } }, selected = id,
           checks = false,   -- rows are checkboxes; Space sends toggle
           filter = false }, -- show a filter box (the client filters)
  fields = { { id, label, kind, value, lo, hi, options, help, issue, enabled } },
  actions = { { id, label, enabled, confirm = "question" } },
}
```

`below = true` puts a picker after the list. `kind` is `number`, `text`, `choice`,
`check` or `info` (read-only). `lo` and `hi` are spoken with the name; `help` and
`issue` become the control's description. `options` may be long: a dropdown of 400
species is fine and replaces upstream's picker popups. `confirm` asks yes or no first,
replacing upstream's click-twice arming. An action with id `delete` also runs on the
Delete key from the list. Row ids and option values may be strings or numbers; list
row ids reach the backend as strings.

Wording: name first, then value; plain words over internal ids where upstream has a
display name; short rows, since they are listened to.

## Pages

| Page | Holds |
|---|---|
| Party | Pokémon list; Section dropdown (Main, Stats, Moves, Origin, Extras, Checks); add, remove, order, tools |
| Boxes | Box dropdown, slots, the same sections; withdraw, deposit, release, add, sort |
| Items | View dropdown: Bag, PC, Wallet, Badges, and Pokéblocks on Ruby, Sapphire, Emerald |
| Trainer | Name, IDs, money, coins, per-game currencies, gender |
| Map | Map list, X and Y, what the cell is, warps; put player, heal or spawn, outdoor (Gen 1) |
| Pokédex | Species list, Seen and Owned, bulk actions, National Pokédex (Gen 3) |
| Events | Category dropdown and flags as checkboxes; variables |
| Checks | Read-only report; Fix all errors |

Differences from upstream's interface, by design:

- Dropdowns replace picker popups, so upstream's search by number, type or power is
  typing the name instead. Inspect is gone: fields are always on the page.
- One confirmation (yes or no) replaces click-twice; pages pre-arm `Ops.arm`.
- Nickname: a bad character refuses the whole name rather than being stripped.
- Map: a warp cell can be selected, and Follow warp is separate. Follow does not write
  `save.lastOutdoor`, so looking around leaves the save alone. Elevator and link-room
  warps (19 FireRed maps, Red's Silph elevator) say so and do not follow.
- Gen 3 cell text reads real collision through `src/access/nav/gen3/World.plannedView`.
  Only terrain: people and boulders are not in map data.
- Checks shows issues in place rather than jumping to the Pokémon.

Upstream behaviour kept: Party Add makes the first catalog species, then you change it;
Gen 3 level cannot go below met level; choosing a box updates the save's current box
without marking it changed. Gen 3 bag sort does not survive saving (export drops
`bagOrder`). Only the active save slot opens.

Recommended moveset asks upstream's sync server, sending the species name, as upstream's
editor does. Its confirmation says it goes online. Other controls wait until it answers: about 2
seconds offline in testing, and possibly up to about 20 on a slow connection.

## Verified

Backend scripts `tests/access/save_backend_{party,boxes,items,world}.json`, plus scratch
read-back runs: every section and action, Undo, Redo, save, Reload and a fresh process, in
Red, Crystal and FireRed. The same four scripts passed in Blue, Yellow, Gold and Silver
without read-back checks. In the real game (`drivers/edited_save.lua`, disposable
profiles): saves edited through the backend continued in all three, at the map and cell
set, with the party level set. Window (UI Automation and real key presses on a disposable
Red save): all eight tabs read, Tab order, dropdown change, badge toggle with focus kept,
Ctrl+Z, typed level, refusal box, Ctrl+S, Escape back to the launcher's list.

Owner's first use, 2026-11-02, on FireRed: "save editor works nicely, and was able to get
to the second gym in fire red." Used on Party: changed a Pokémon's level and made it
shiny. The owner did not notice either way whether the status line speaks.

Not established: that the live status line speaks; other games by ear;
Gen 2 mail after a party change; `.sav` export; Pokéblocks on a real save; LeafGreen, Ruby,
Sapphire and Emerald, which no test profile has imported. No owner test.

## Testing

`python tests/access/save_backend.py <game> <identity> <script.json> [scratch-save]`
drives the backend with no window. Use disposable identities and scratch saves.
