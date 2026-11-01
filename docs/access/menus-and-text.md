# Menus, text and screens

Speech for dialogue, menus and Gen 1 information screens. Battle has its
own workstream. Gen 2 and 3 are not covered.

## How it works

`src/access/screens/ScreenReader.lua` runs once per frame, after upstream's
`love.update`. `Access.install` wraps that callback, so no screen file is
edited. It reads the top of Gen 1's shared state stack
(`src/core/StateStack.lua`, which `Game` uses directly as its stack). When
the top screen is a known upstream class, a presenter turns it into speech:

- `src/access/screens/Presenters.lua`: shared primitives (text box, menu,
  list, Yes/No, quantity), naming keyboard, party.
- `src/access/screens/InfoScreens.lua`: summary, move pickers, trainer card,
  Pokédex list and entry, options, town map.

Rules for presenters:

- Match by **metatable** (or a metatable chain for subclasses such as the
  controls list), never by guessing field names.
- `poll(state, memo, entering)` runs every frame the screen is on top. It
  compares a few fields with what it last said (kept in `memo`, one table per
  screen) and builds text only on a change.
- Read what the screen draws, and cite the draw code mirrored. Calling an
  upstream method is allowed only when it is read-only (`grid()`,
  `bottomMessage()`, `bannerText()`, row `value()`), and always through `pcall`.
- Measured cost (LuaJIT, fake backend, 2026-10-31): about 0.002 µs per
  unchanged frame, 0.11 µs when the cursor moves. Speech is sent in the
  same frame the game changes, at most one frame (about 17 ms) after input.

## What is spoken

| Screen (upstream class) | On entry or return | On change |
|---|---|---|
| Dialogue page (`TextBox`) | Whole page as one utterance, interrupting | Each new page |
| Menu (`Menu`: title, start, name choice, PC, shop root) | Title, item, position | Item |
| List (`ListMenu` and subclasses: bag, boxes, shop, controls, fly) | Title, item and detail, position | Item and detail, position |
| Yes/No (`ChoiceBox`) | Selection, queued after the question | Selection |
| Quantity (`QuantityBox`) | "Quantity", amount, running total, maximum | Amount and total |
| Naming keyboard (`NamingScreen`) | Title, name so far, cell | Cell; typed letter plus name; "deleted"; case page |
| Party (`PartyMenu`) | Prompt, Pokémon row, position | Row; sub-menu items; messages |
| Summary (`SummaryMenu`) | Page 1: name, number, level, HP, status, stats, types, ID, trainer | Page 2: experience, to next level, moves with PP |
| Move pickers (`MoveLearnMenu`, `MoveSelectMenu`) | Prompt, move and PP, position | Move and PP |
| Trainer card (`TrainerCard`) | Name, money, time, badges | (static) |
| Pokédex list (`PokedexMenu`) | Seen and owned counts, number, name, owned or seen, position | Same without counts |
| Pokédex entry (`DexEntryMenu`) | Name, kind, number, height and weight, first page | Next page |
| Options (`OptionsMenu`) | Row label, value, position (BACK is the last row) | Value only, or label and value on a new row |
| Town map and fly (`TownMap`) | "Town map" or "Fly", location, "you are here" | Location |

Party rows say name, level, HP and status, or "able" or "not able" when
teaching a TM or using an evolution stone. That check mirrors
`PartyMenu:draw`. Naming cells spell out punctuation and symbols ("dash",
"male", "PK") because screen readers often skip them. Lines of a page join
with spaces, except a word split by a line-end hyphen.

Returning to a screen repeats its context. A dialogue page is spoken once
per page, so a closing Yes/No box does not repeat the question.

## Not covered yet

- **Battle** text, menus and sub-screens (battle workstream).
- Hall of Fame, diploma, credits, League PC, prize counter, slot machine,
  Yellow's surfing minigame, intro movies, evolution animation.
- Pokédex AREA nests on the town map.
- Gen 2 and 3 screens.
- Options pages are grouped upstream (for example "SPEED, 4 OPTIONS"); the
  values inside a group were not yet checked in a game run.
- Wording and pronunciation (for example "POKéMON") need the owner's playtest.

## Verification (2026-10-31)

| Level | Result |
|---|---|
| Unit tests | `screen_reader_test.lua` 23/23; `game_screens_test.lua` 29/29 (quantity, naming, party and sub-menu, TM able, summary pages, move learn, trainer card, Pokédex list and entry, options, town map). |
| Scripted game runs | Disposable identity `pocket-access-test`, `POKEPORT_ACCESS_TRACE=1`, real Prism (NVDA). `drivers/menus_and_text.lua`: title menu, Oak's speech, name menus, start menu. `drivers/gen1_screens.lua`: naming keyboard typing and confirm, party rows and sub-menu, both summary pages, options entry, trainer card. Not yet run in game: quantity, move pickers, Pokédex, town map. |
| Heard by the owner | Not yet. |

## Testing note

Game runs must use a disposable identity (`POKEPORT_IDENTITY=...`). On
2026-10-31 an early start-up check ran with the default identity, and
upstream's launcher rewrote `options.lua` (contents unchanged, backup kept),
`launcher-window.cfg` and `mod_index_cache.lua` in the owner's real
`pokemon-love2d` save folder. No saves were touched.
