# FireRed and LeafGreen

Differences from the Gen 1 and Gen 2 layer for the third generation's Kanto
games (decisions 29 and 30). FireRed first; LeafGreen is deferred until the
owner supplies a clean dump. Gen 1 behaviour is in `menus-and-text.md`,
`battle.md` and `navigation.md`.

## How Gen 3 sits on upstream

Upstream v0.3.98 runs Gen 3 through `src/core/Game3.lua`, with screens in
`src/ui/game3/` and the engine in `src/core/game3/`. It keeps **no
StateStack**: boot, quest log, battle and the field each own their screens.

- **Menus** are layers on `src/ui/game3/stack.lua`, `{ id, mod, hideBelow,
  ... }`, whose `mod` is a module singleton: state lives on the module.
- **Dialogue** is the module `src/ui/game3/message.lua` (`_pages`, a new
  table per message; at most two lines per page; each page waits for A).
  **Yes/no** and multiple choice are `src/ui/game3/choice.lua`.
- **Battle** is the module `src/core/game3/battle`; its text also goes
  through the message module (frame "battle").

How the layer reads it:

- `src/access/CurrentGame.lua` holds the running game for every
  generation, through a runtime wrapper on `PlatformHooks.update` (main.lua
  looks it up every frame). Driver runs step the game without it, so
  `tests/access/drivers/isolated.lua` hands the game over; Gen 3's runtime
  record is the fallback.
- `src/access/screens/gen3/Top.lua` resolves what is on screen in the
  game's own order (help, quest log, boot sub-screen, top menu layer,
  battle, yes/no, dialogue) and returns **one proxy per opening**
  (`{ gen3 = <kind>, key, layer, mod, game }`), keyed by an object that
  exists for exactly one opening: the layer record, the message's page
  table, the choice's callback, the boot sub-state. Per-screen memory and
  the "entering" flag therefore work as in Gen 1 and 2 although the modules
  are singletons; presenters keep their memory in the memo, never on the
  module. A question under a yes/no box is reported as covered and said
  first. Passive overlays (no input) register through `Top.addAmbient` and
  are polled every frame, queued.
- Presenters live in `src/access/screens/gen3/` (`Dialogue`, `Menus`,
  `Items`, `Special`, `Battle`), match on the proxy's kind and check the
  layer still holds the builtin module, so a mod that replaces a screen
  stays quiet rather than being misread. `gen3/Common.lua` cleans Gen 3
  text: font and colour tags and `0xFC` control bytes are dropped, glyph and
  button tags are said in words.

## Screens

| Screen | On entry | On change |
|---|---|---|
| Dialogue (`message.lua`) | The first page as it starts; ALL AT ONCE: every page | Each page as the next A press starts it; a word split across a page break is finished on the earlier page |
| Yes/no and choices (`choice.lua`) | The selection, queued behind the question; position for multiple choice | Selection |
| Bag, TM case, berry pouch (`bag_menu`, `tm_case`, `berry_pouch`, `sell_flow`) | "<pocket> pocket", item (TM: number, move, type, power, accuracy, PP; quantity except key items and TMs; "registered" for the SELECT item), position, description | Item and description; action menu ("ANTIDOTE is selected. USE, 1 of 4"); toss and deposit quantities; YES/NO; messages; selling with money |
| Party (`party_menu`) | The prompt as drawn, the row (nickname, species when nicknamed, level, gender, HP, or the screen's ABLE / NOT ABLE, status in words, "holding an item" or "holding mail"), position | Row; sub-menus; move picker; level-up window; messages once the HP bar stops |
| Summary (`summary_menu`) | Header, page title, "page N of 3", the page (info with nature and where met; skills with ability; moves) | Page; move detail ("N of 5" when learning, the new move fifth); "moving <move>"; forget-a-move flow for TMs and battle |
| Pokédex (`pokedex`) | Contents with seen and owned counts; sections; list rows (number, name, caught or seen, types, "-----" when unseen) | Row; habitat pages; entry page 1 (category, height, weight, text) and page 2 (type, AREA places or AREA UNKNOWN) |
| PC and boxes (`pc_menu`, `box_storage_ui`, box picker, `release_seq`, `item_pc`) | Question and row with its description; box name and "N of 30"; slot with Pokémon or "empty", row and column | Slot; drawer; action and box menus; box picker ("BOX 1, 0 of 30"); release sequence; item PC rows, quantities, results |
| Shop and money (`shop_menu`, `money_box`) | Clerk line, BUY/SELL/QUIT; buy list with money, price, description | Quantity with total and "IN BAG"; confirm YES/NO; result and new money; the money box when shown or changed, queued |
| Town map and Fly (`region_map`) | "Town map" or "Fly", the place under the cursor, "you are here" | Place as the cursor moves; "can fly" on the Fly map |
| Slots (`slot_machine`) | Title, credit, controls | Bet and the lines it buys; each reel as it lands, queued; the winning lines' symbols or "No win"; credit; payout chart; quit yes/no |
| Prize corner, Day-Care list, records, PIN pad, Easy Chat, Hall of Fame PC | Row and position, or the whole page | Row; digit; word slot, group, word; confirm and yes/no |
| Link, Union Room, chat, trade, Mystery Gift, minigame lobbies | Context, row, position | Rows, arrivals, counts, messages, yes/no, countdown, results |
| Overlays: braille, pictures, ferry, Itemfinder, VS Seeker, Berry Powder, arena | Said once, queued | Value changes |
| Credits, diploma, whiteout | Each screen's text, queued | Next screen |

Item, party and storage reads never call `Bag.listPocket`, `Bag.get` or
`Storage.ensure` (they rebuild pockets, and `ensure` adds a Potion); pocket
rows come from `bag.pockets` and boxes from `session.storage`. Labels the
screens keep in file-local tables are read from their draw functions'
upvalues by name, never copied. Pokémon Access behaviour adopted (no code
or text copied): item descriptions follow the cursor, status icons are
said in words, the box picker reads name and count, the box screen reads
the hovered Pokémon.

Braille says "Braille:" and the decoded text (agent default; the original
Pokémon Access spelled dot numbers). Reading never changes game state:
`MuseumPic.isActive`, `BerryPowderBox.isVisible` and
`ElevatorWindow.isVisible` change state when called and are never used;
the Mystery Gift record is never created by reading.

## Verification

| Area | Level reached |
|---|---|
| Baseline (2026-11-01) | FireRed new game, start menu, bag, field messages: nothing spoken. |
| Core (dialogue, yes/no) | FireRed run through `isolated.lua`: "RED played with the NES." then "…Okay! It's time to go!", a page per A press. |
| Items, party, summary, Pokédex, PC, shop, map | `gen3_items_test.lua` 133/133 (traps `Bag.listPocket`, `Bag.get`, `Storage.ensure`: zero calls). `drivers/gen3_items.lua` in FireRed (identity `pocket-access-items-firered`), six runs, every section reached. Unit tests only: habitat pages, registration after a catch, wallpaper, MOVE in storage, the party level-up window, "can fly". Not reached: TM case and berry pouch from the bag's menu, TAKE, Softboiled, Teachy TV demos, double-battle party, a clerk's script opening the shop. |
| Special screens | `gen3_special_test.lua` 122/122. `drivers/gen3_special.lua` in FireRed (identity `pocket-access-special-firered`): slots, braille, records, PIN pad, Easy Chat, Day-Care, Hall of Fame PC, diploma, overlays, mod manager, whiteout, credits spoken. Unit tests only: link and Union Room flows, Mystery Gift, minigames, Berry Powder box, fossil picture, VS Seeker, arena. The prize corner list needs the `Top.lua` change below. |
| Heard by the owner | Not yet. |

## Open questions for the owner (agent defaults)

- Braille: decoded text, or spelled dot numbers?
- Slots: symbols by the game's icon names, SEVEN said "7"; a controls line
  on entry and "Win" / "No win" are our words (the screen shows only
  animation).
- Itemfinder: arrow direction only. VS Seeker: how many trainers want a
  rematch, not where.
- Town map: say the place on every cursor step (a route repeats), silence
  on empty cells, a list of Fly destinations?
- Item wording (our words): status words, "holding an item", "Party, N
  POKéMON", "row R, column C", "<pocket> pocket", "can fly", "caught" or
  "seen", "moving". The summary speaks a whole page on entry: too long?
- Real-time minigames (Pokémon Jump, Dodrio Berry Picking, Berry Crush):
  play is silent; non-speech timing cues?
- Trainer Tower: a key for the time so far? The game shows no timer.

## Known gaps

- Layers that keep what is under them visible (prize corner, Day-Care
  list, Union Room, PIN pad, the script floor list) lose to an open message
  in `Top.lua`; fix in progress on the menus branch.

## Upstream observations (recorded, not fixed)

- The party's Softboiled / Milk Drink target mode draws "Choose a
  POKéMON."; the cartridge asks "Use on which POKéMON?" (source read).
- The summary falls back to the name "RED" for a Pokémon with no OT name.

- Trainer Tower results board: the first row has no label and every row
  shows the same best time.
- The Berry Crush berry choice has no B to cancel.
- `MuseumPic.isActive`, `BerryPowderBox.isVisible`,
  `ElevatorWindow.isVisible` change state when called.
- The online arena hides the battle from the resolver (`game.phase` is
  "arena").
