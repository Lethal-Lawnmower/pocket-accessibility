# Save editor

Upstream's save editor (`tools/save-editor/`, decision 5) with keyboard focus and
speech on top (decision 38). Upstream is a mouse program; our code is in
`src/access/editor/`, and one line in `App.lua` attaches it. Every action still
goes through upstream's own click, confirmation and save paths, so backups,
modal shields and Undo behave as they do for a sighted player.

## Keys

| Key | Does |
|---|---|
| Tab, Shift+Tab | Next or previous control |
| Down, Up | Next or previous stop, including plain text (like browse mode) |
| Home, End | First or last stop on the screen |
| Enter, Space | Activate |
| Escape | Close a popup or menu, leave a text box, or clear the selection (upstream) |
| F1 | Help for the focused value, when it has any |
| F2 | Repeat the focused item |
| Shift+arrows | Map page: move the cell cursor (below) |
| Page Up, Page Down | Scroll the list under the focus (upstream) |
| Ctrl+S, Ctrl+R, Ctrl+Z, Ctrl+Y | Save, reload from disk, undo, redo (upstream) |

Results upstream reports (status line, toasts, notes) are spoken after the focus.

## How it works

`Capture.lua` wraps Kit, the editor's widget module, at runtime. Kit already
reports every clickable control to `Kit.audit` for its layout tests, and leaves
out whatever a modal covers, so popups trap focus without extra code. The
wrappers add drawn text in sequence, control state and the regions that scroll;
they do not change what Kit draws or returns. Each frame becomes a list of stops.
Nothing is a separate model of the editor, so any page upstream adds is readable
at once, if not always well named.

`init.lua` keeps the focus between frames by control id or label, and activates
with `App.mousepressed` at the control's visible centre. `PadInput.pointer`
returns the focused control, so hover and the wheel act where the focus is.

Naming rules worth knowing:

- A row is named by the text drawn inside it. A value box or dropdown that shows
  only its value takes its name from the line above.
- Not stops: `slider-` controls (a click there sets a value from where it lands;
  the box beside each edits the same number), the scrollbar, and press regions
  with no words. Help marks belong to the value beside them (F1).
- Pokédex toggles are prefixed with the species, since Tab skips the name.
- Upstream's mouse hints ("Ctrl+S save . ... arrows pan map") are dropped.

Behaviour added for keyboard use:

- Leaving a list with rows out of view scrolls them in first; entering one left
  scrolled partway starts from its near end.
- A picker with a search box opens ready to type. After a pause it says "First:"
  and the result Enter would take; Tab or the arrows walk the results.
- A number popup opens on "Type a value" and says the current value. A number box
  opens holding the old value and the first digit replaces it.

## Map page

The map is a picture with no controls in it. Choose a map with the search box and
the list, then Shift+arrows walk a cell cursor. It starts where the player stands
on that map, or else in the middle. Each step says the coordinates, a warp's
destination, and "walkable" or "blocked" where upstream's map object can answer
(Gen 1 and Gen 2; FireRed's preview has no such method, so it says neither).
Player and Heal or Spawn (and Outdoor in Gen 1) then act on that cell. Upstream
allows placing the player on a blocked cell; the speech warns but does not stop it.
Clicking a warp cell with a mouse follows it; the cursor only selects it.

## Opening

The launcher's Edit save sets `POKEPORT_EDITOR=1` and `POKEPORT_VERSION`. A
standalone start names no file, and upstream's default is a pre-slots path, so
`Editor.activeSavePath` asks `SaveData` for the file the game itself would load.
That lookup can move a flat `save_<game>.lua` into `saves/<game>/slot1.lua`,
which is upstream's own migration and also happens on the next game start (a
first session saves flat until then). Checked on a disposable profile: the game's
load and the editor's path were the same file.

## Verified

Driver `tests/access/drivers/editor_tour.lua` (silent, isolated, scratch saves),
run in game in Red, Crystal and FireRed. By keyboard only it added a Pokémon,
changed species and level, added an item through the search, set
money, chose a map and a cell and placed the player, earned a badge, saved, and
reloaded from disk with the money intact; Close with unsaved edits asked first. It
read every page. A copy of the owner's FireRed save opened and read correctly
(party, trainer), with nothing edited. Unit test `editor_capture_test.lua`.

Not established:

- **Nobody has heard it.** Scripted runs are silent.
- The real key path: drivers call `App.keypressed` directly. The standalone start
  was only shown to run for 14 seconds without crashing, window hidden. Source
  reading says the game's command router stays out of the way with no game running.
- Blue, Yellow, Gold, Silver, LeafGreen, Ruby, Sapphire and Emerald were not run.
- Not exercised: Boxes moves, Events edits, Pokédex edits, move and stat editing
  (Stats, Moves, Origin, Extras), Tools menus, Sort, Open's file dialog, F1.
- Upstream's own editor suites need generated data and were not run through the
  layer. The layer stays off when speech is unavailable, so they do not attach it.

## Known rough edges

- Box slots read as bare numbers when empty ("2"), and the first row of a long
  flag list takes many stops; the filter box is the quick way.
- The Events page lists internal flag names. Setting flags can break a story;
  that is upstream's editor, unchanged.
- Sliders have no keyboard form; the value box covers them.
- Open uses a native Windows dialog, outside this layer.
