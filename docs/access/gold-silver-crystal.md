# Gold, Silver and Crystal

Differences from the Gen 1 layer for the three Gen 2 games (decision 27).
Gen 1 behaviour is in `menus-and-text.md`, `battle.md` and `navigation.md`;
this file holds only what is different or Gen 2 only.

## How Gen 2 sits on upstream

Upstream v0.3.98 runs Gold, Silver and Crystal through `src/core/Game2.lua`
(not `Game.lua`), with screens in `src/ui/gen2/`, the overworld in
`src/world/gen2/` and the script VM in `src/script/gen2/`. Gold and Silver
share the `gs` engine; Crystal is `crystal`.

- **Same stack.** `Game2` uses the `src.core.StateStack` module table as
  its stack, so `ScreenReader` sees Gen 2 screens with no new hook. Free
  roaming leaves the stack empty: the top is nil there.
- **Same dialogue box.** Script text goes VM, then `World:showText`, then a
  pushed `src.render.TextBox`, so the Gen 1 dialogue presenter speaks it.
  Yes/No goes through the same `ChoiceBox`.
- **Own screen classes.** Gen 2 module names repeat Gen 1's (`PartyMenu`,
  `StartMenu` ...) at other paths, so no Gen 1 presenter matches a Gen 2
  screen. Presenters live in `src/access/screens/gen2/` (`Menus`, `Items`,
  `Info`, `Special`, `Battle`), collected by `gen2/init.lua`.
  `gen2/Common.lua` holds what they share: Gen 2 text commands (`#` is
  POKé, `<PO><KE>`, `<LV>`), the Typer message pattern many screens use for
  their own message box (`typer.page`), Chrome list rows, metatable matching.
- **Held screens.** Some screens draw another screen that is not on the
  stack (a mart's selling pack, MapRadio's radio, MoveTutor's party). The
  holder's presenter speaks the held screen.
- **Options.** Gen 2 has its own OPTION screen; the ACCESSIBILITY page is
  added there too and stored in Gen 2's options block (`menus-and-text.md`,
  decision 26).

## Screens

| Screen (`src/ui/gen2/` class) | On entry or return | On change |
|---|---|---|
| Party (`PartyMenu`) | The prompt as drawn, the row (nickname, species when different, level, HP, status, "holding an item" or "holding mail"), position (CANCEL counts) | Row; sub-menu label (with position when it opens); SWITCH says "Move to where?" plus the row; after a switch the Pokémon now under the cursor; "able" or "not able" from the screen's own TM check; item messages once the HP bar stops |
| Summary (`SummaryMenu`) | Nickname, species, number, level, gender, shiny; the page; "page N of 3" | Page; Pokémon switch; move screen: move, PP, type, power, position, description; reorder ("<move>. Where?", then the moved move); egg page |
| Pokédex (`PokedexMenu`) | "Pokédex", mode, seen and owned, row, position (unseen rows say "unknown") | Row; entry: name, kind, number, height and weight once caught, the action under the arrow, the description; page 2; AREA ("<NAME>'S NEST", region, nest landmarks or "none"); OPTION, SEARCH (rows, values, results), UNOWN MODE (letter and word) |
| Pokégear (`Pokegear`) | Card label and its face (clock day and time, map landmark, radio frequency and station), position on the strip | Card; map landmark ("you are here"); phone: prompt, contact with slot of 10, CALL/DELETE/CANCEL; radio: frequency and station on each knob step, then each show line, queued |
| Fly map and town map (`Pokegear` with `fly` or `townMap`) | "FLY. Where? <destination>, you are here, N of M" or "MAP. <landmark>" | Destination or landmark |
| Incoming call (`CallerBox`) | "Phone call, <name>, <class>" while it rings | (once) |
| House radio (`MapRadio`) | "Radio, <station>" | Each show line, queued |
| Trainer card (`TrainerCard`) | "Trainer card", name, ID, money, Pokédex count, time, page N of 3 | JOHTO BADGES or KANTO BADGES with the badges earned |

Rows follow what the screen draws: the party list draws no gender, and its
held item is only an icon, so speech says "holding an item" without naming
it. A missing PP count means full; only an explicit 0 is said as 0. Radio
lines queue rather than interrupt, so a show is heard in order. The clock is
read when its card is reached, not on every minute. Reading never changes
game state: the radio is read from the screen's record (never through
`ensureTuned` or `tuneRadio`), the Unown list from the save field (not
`Unown.dex`, which creates it).

## Verification

| Area | Level reached |
|---|---|
| Baseline (2026-11-01) | Game run, Crystal and Gold, new game to a wild battle (`drivers/gen2_walkthrough.lua`): only TextBox dialogue spoke before this work. |
| Info screens | `gen2_info_test.lua` 106/106. `drivers/gen2_info.lua` run in Crystal, Gold and Silver (identities `pocket-access-info-<game>`): every section reached and spoken. Not run: Softboiled target mode, the battle party list, phone DELETE, out-of-area calls, Buena's Password station, Kanto on the map and AREA screens, the dex PRNT action. |
| Heard by the owner | Not yet. |

## Open questions for the owner

- Trainer card page 3 ("KANTO BADGES"): upstream's plain draw puts Kanto
  names on the Johto badge flags (with only BOULDER earned it shows
  BOULDER and CASCADE). Speech copies the screen. Keep matching the screen,
  or read the save's Kanto badges?
- Wording: "PRNT" said as written; "holding an item" without the item's
  name; "Phone call" and "Radio" are our words.

## Known gaps

- An outgoing call's first line ("PROF.ELM: ……") is covered by the call's
  first page in the same frame and is not heard.
- The phone card's signal meter (no service) is not spoken; no key re-reads
  the clock on request.

## Upstream observations (recorded, not fixed)

- Trainer card page 3 reads the Johto badge flags (above).
- The summary ignores presses while its second swap sound plays, so a B
  straight after a reorder is lost.
- The radio card's draw tunes the radio and starts its music as soon as
  RADIO is highlighted, before A.
- From source only: `Game2:useFieldItem`'s TM branch opens the party
  without the TM check, so rows show HP instead of able.
