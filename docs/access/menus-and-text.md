# Menus and text

Speech for dialogue and menus. Gen 1 only so far.

## How it works

`src/access/screens/ScreenReader.lua` runs once per frame, after upstream's
`love.update`. `Access.install` wraps that callback, so no screen file is
edited. It reads the top of Gen 1's shared state stack
(`src/core/StateStack.lua`, which `Game` uses directly as its stack). When
the top screen is one of upstream's shared UI classes, a presenter in
`src/access/screens/Presenters.lua` turns it into speech.

- Presenters match by **metatable**, never by guessing field names.
- Each presenter has a cheap change marker (cursor index, page number).
  Speech text is built only when the top screen or that marker changes.
- Measured cost (LuaJIT, fake backend, 2026-10-31): about 0.002 µs per
  unchanged frame and 0.11 µs when the cursor moves. Real speech output adds
  the Prism call, only on changes. Responsiveness: speech is queued in the
  same frame the game changes, at most one frame (about 17 ms at 60 fps)
  after the input.

## What is spoken

| Screen (upstream class) | On entry or return | On change |
|---|---|---|
| Dialogue page (`TextBox`) | The whole page as one utterance, interrupting | Each new page |
| Bordered menu (`Menu`: title menu, start menu, name choice, PC, shop root) | Title (if any), item, position | Item only |
| List (`ListMenu`: bag, boxes, shop lists, Pokédex, fly) | Title, item with its detail, position | Item with detail, position |
| Yes/No (`ChoiceBox`) | Selection, queued after the question | Selection, interrupting |

Row details follow what the list draws: level, sub-line, price, quantity, or
right-hand text. An empty list says "Empty". Lines of a page join with
spaces, except a word split by a line-end hyphen ("grand-" + "son").

Returning to a menu repeats its context (position). Returning to a dialogue
page under a closed Yes/No box does not repeat the question.

## Not covered yet

- **Naming screen keyboard** (`src/ui/NamingScreen.lua`): letters are not
  spoken. The name menu before it is.
- **Battle text and battle menus**: battle text does not use `TextBox`;
  battles need their own presenter (battle workstream).
- **Quantity box**, trainer card, Pokémon summary, party screen, Pokédex
  entry and other custom screens: silent until each gets a presenter.
- **Gen 2 and 3** screens.
- Text uses the game's own spelling (for example capitals in "POKéMON").
  Whether screen readers pronounce it well is for the owner's playtest.

## Verification (2026-10-31)

| Level | Result |
|---|---|
| Unit tests | `luajit tests/access/screen_reader_test.lua`: 23/23 (all four presenters, change detection, return behaviour, empty list, hyphen join). |
| Scripted game run | `tests/access/drivers/menus_and_text.lua` with `POKEPORT_ACCESS_TRACE=1` in the disposable identity `pocket-access-test` (Red imported there with `POKEPORT_IMPORT_ROM` and `POKEPORT_IMPORT_ONLY=1`). The trace showed the title menu, every page of Oak's speech, both name menus, the start menu with position, and context on returning from the trainer card. Real Prism (NVDA) was active. |
| Heard by the owner | Not yet. |

## Testing note

Game runs must use a disposable identity (`POKEPORT_IDENTITY=...`). On
2026-10-31 an early start-up check ran with the default identity, and
upstream's launcher rewrote `options.lua` (contents unchanged, backup kept),
`launcher-window.cfg` and `mod_index_cache.lua` in the owner's real
`pokemon-love2d` save folder. No saves were touched.
