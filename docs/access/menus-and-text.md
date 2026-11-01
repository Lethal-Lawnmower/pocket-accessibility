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
- `src/access/screens/MinorScreens.lua`: title and intros, League PC, prize
  counter, slot machine, Hall of Fame, diploma, credits.
- `src/access/screens/Battle.lua`: battles (`battle.md`).

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
| Dialogue (`TextBox`) | The first chunk: the lines shown before the game waits for A | Each chunk the next A press reveals (owner request, 2026-10-31). With OPTIONS, ACCESSIBILITY, DIALOGUE SPEECH set to ALL AT ONCE (decision 26): the whole box, every page, on entry, and nothing after. A box covered by a menu in the same frame it opens (Yellow's instant elevator prompt) is spoken before the menu, which queues behind it |
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
| Pokédex AREA (`TownMap` with a nest species) | "<name>'s NEST" and every nest location, sorted naturally (ROUTE 2 before ROUTE 12), or AREA UNKNOWN | (once) |
| Title and intros (`TitleState`, `IntroMovie`, `YellowIntro`) | "Title screen. Press start." or "Intro. Press start to skip." | (once) |
| League PC (`LeaguePC`) | Hall of Fame team number, member, level | Member |
| Prize counter (`PrizeCounter`) | Coins, prize and cost (last row NO THANKS) | Prize and cost |
| Slot machine (`SlotMachine`) | Its messages (queued), bet amount, "Spinning", One more go YES/NO | Bet, YES/NO |
| Hall of Fame (`HallOfFame`) | Each member as shown | Next member |
| Diploma (`Diploma`), credits (`Credits`) | Diploma text with the player's name; each credits screen's lines | Next credits screen |
| Picture pop-up (`PicBox`) | "Picture of" the Pokémon, "Press A to continue" | (once) |
| Yellow high-score print (`SurfHiScore`) | Player and high score | (once) |
| Mod manager (`ManagerState`) | "Mod manager", tab, mod and its state (enabled, disabled, error, missing dependency, not for this game, change pending restart), position | Row; tab; detail page (name, version, state, description); options with values; confirmations with YES/NO; notices |
| Save load report (`QuarantineReport`) | Every report line | (once) |
| Cable club (`LinkState`) | Each stage: HOST/JOIN menu with port, hosting address, typed host address, connected, TRADE/BATTLE, battle level option, version notices, link battle | Stage text; in the trade centre: your or their Pokémon with position, STATS/TRADE, the trade message, TRADE/CANCEL, waiting |
| Union Room battle and trade prep (`Gen1BattlePrep`, `Gen1TradePrep`) | Page title, every body line (not just the visible window), focused option with position, "unavailable" when disabled | Option; notices |
| Yellow: talking to Pikachu (overworld `emote`) | "Pikachu is happy", "Pikachu is asleep" and so on | Each new reaction picture |

Evolution and trade speak through the text boxes they push. Yellow's
surfing minigame is a timing game and needs its own design.

Party rows say name, level, HP and status, or "able" or "not able" when
teaching a TM or using an evolution stone. That check mirrors
`PartyMenu:draw`. Naming cells spell out punctuation and symbols ("dash",
"male", "PK") because screen readers often skip them. Lines of a page join
with spaces. A word the cartridge splits across lines ("crea-" / "tures",
letter, hyphen, then a lower-case start) is joined without the hyphen, and
when the split falls on one of the game's A waits the chunk before the wait
finishes the word (2026-11-01, found in Crystal's intro; applies to every
game). Upper-case compounds and a few real compound prefixes keep the
hyphen ("SUPER-POTION", "super-effective").

Returning to a screen repeats its context. Dialogue lines are spoken once
each, so a closing Yes/No box does not repeat the question. An instant box
(shown all at once) speaks its whole page.

## Mods

Goal (decision 17): screens and text added by mods should speak without
changes to this layer.

- **Upstream's mod UI kit works automatically.** `mod.ui.Menu`,
  `ListMenu`, `ChoiceBox`, `QuantityBox` and `TextBox` are the real upstream
  classes (`src/ui/ModUI.lua`), so a mod screen built from them, rows a mod
  inserts into existing menus, and mod dialogue and translations all speak
  through the presenters above. Gen 3 mods get a different `TextBox` and are
  not covered.
- **Custom-drawn screens can describe themselves.** A screen state with an
  `accessibilityText` method is spoken by `Presenters.selfDescribing`,
  which runs before every other presenter (so it also overrides ours). A mod
  needs nothing from this layer:

  ```lua
  function MyScreen:accessibilityText()
    return "Jukebox. " .. self.tracks[self.index].name .. ", "
      .. self.index .. " of " .. #self.tracks
  end
  ```

  It is called once per frame while the screen is on top, so it must be
  cheap. Speech happens (interrupting) when the returned text changes. If it
  raises, the error is logged once and that screen stays quiet.
- **Custom screens without it are silent.** A fallback that captures the
  text a screen draws was considered and deferred: it would read layout
  fragments out of order. Revisit if real mods need it.

## Not covered yet

- Yellow's Pokédex print preview (`PrinterMonStats` is a render helper, not a screen of its own; not reached).
- Upstream visual tools: palette screen, skin studio, touch controls editor (visual or touch-only editors).
- Network flows were checked only up to the cable club menu; hosting, joining and Union Room sessions need a second player.
- Yellow's surfing minigame (needs a design for a timing game).
- Gen 2 screens: in progress, see `gold-silver-crystal.md`. Gen 3 screens: not started.
- Wording and pronunciation (for example "POKéMON") need the owner's playtest.

## Verification (2026-10-31)

| Level | Result |
|---|---|
| Unit tests | `screen_reader_test.lua` 28/28; `game_screens_test.lua` 37/37 (self-describing screens, nest areas, quantity, naming, party and sub-menu, TM able, summary pages, move learn, trainer card, Pokédex list, unseen rows and entry, options, town map); `minor_screens_test.lua` 13/13. |
| Scripted game runs | Disposable identity `pocket-access-test`, `POKEPORT_ACCESS_TRACE=1`, real Prism (NVDA). `drivers/menus_and_text.lua`: title menu, Oak's speech, name menus, start menu. `drivers/gen1_screens.lua`: naming keyboard, party and sub-menu, summary pages, options entry, trainer card. `drivers/more_screens.lua`: bag, toss quantity, Pokédex list and a two-page entry, town map, a mart's buy list, priced quantity, price prompt with YES/NO, Pokédex nest areas, an options group page with a value change. Title and intro lines appear at every scripted start. `drivers/pc_and_moves.lua`: Bill's PC and deposit list, player's PC and withdraw list, the whole forget-a-move flow including the abandon prompt. |
| Owner listening | 2026-10-31, Red: speech heard and judged "really good". Reported that a whole page is read at once, ahead of the lines revealed by each A press; pacing change offered. |
| Chunk pacing | Owner chose chunk-by-chunk speech. `screen_reader_test.lua` 28/28 (5 pacing checks); a scripted run (fresh identity `pocket-access-run`) traced Oak's speech and the move-learning prompt one A press at a time. Not yet heard by the owner. |
| More game runs (2026-10-31) | `drivers/remaining_screens.lua`: mod manager (both tabs), cable club menu, slot machine, prize counter, League PC, Hall of Fame, diploma, credits, the item move picker, evolution. `drivers/gen1_screens.lua` with `POKEPORT_VERSION=blue` in a fresh identity: Blue behaves like Red. Pikachu reactions: all 32 map from their picture in the real Yellow data (28 exact, 4 share a picture with a reaction worded the same). `extra_screens_test.lua` 24/24 (mod manager, load report, cable club, Union Room prep, Pikachu reactions); `minor_screens_test.lua` 15/15. |
| Accessibility page (decision 26) | `settings_test.lua` 22/22. `drivers/settings.lua` (silent): "Options. ACCESSIBILITY, 2 OPTIONS, 1 of 14", the page, entered as "ACCESSIBILITY. AUTO-WALK SPEED, GAME SPEED, 1 of 3" (group pages are named after the row that opened them; `game_screens_test.lua` 38/38), DIALOGUE SPEECH switched with the game's keys; Mom's whole line then came as one utterance ("MOM: Right. All boys leave home some day. It said so on TV. PROF.OAK, next door, is looking for you.") and nothing after the A presses. The setting persists in the options file across runs. Owner tried the page 2026-10-31: "It looks real good." Gen 2 (decision 27): the same page is added to Gen 2's own OPTION screen (`src/ui/gen2/OptionsMenu.lua`), values kept in Gen 2's options block, so each generation has its own choice; `settings_test.lua` 31/31. Not yet run in a Gen 2 game. |
| Yellow | Yellow imported into a fresh identity (`pocket-access-yellow`); `drivers/menus_and_text.lua` with `POKEPORT_VERSION=yellow` traced the Yellow intro, title, Oak's speech, naming and the start menu. |
| Heard by the owner | Not yet. |

## Testing note

Game runs must use a disposable identity (`POKEPORT_IDENTITY=...`). On
2026-10-31 an early start-up check ran with the default identity, and
upstream's launcher rewrote `options.lua` (contents unchanged, backup kept),
`launcher-window.cfg` and `mod_index_cache.lua` in the owner's real
`pokemon-love2d` save folder. No saves were touched.

Importing Yellow headless (`POKEPORT_IMPORT_ONLY=1`) into the
`pocket-access-test` identity, which already held Red and had one killed
import attempt, hung twice with no error (10 and 15 minutes). The same
import into fresh identities finished in about 2 seconds, both with the
layer on and with `POKEPORT_ACCESS=0`, so the layer is not the cause. Not
investigated further; use a fresh identity per game for scripted runs.
