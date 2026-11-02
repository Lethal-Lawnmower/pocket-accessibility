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

## Testing

`python tests/access/save_backend.py <game> <identity> <script.json> [scratch-save]`
drives the backend with no window. Use disposable identities and scratch saves.
