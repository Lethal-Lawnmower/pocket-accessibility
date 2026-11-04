# Battle

Speech for battles. Gen 1 presenter: `src/access/screens/Battle.lua`; Gen 2
presenter: `src/access/screens/gen2/Battle.lua` (section "Gen 2" below).

## How it works

Battle text never goes through `TextBox`. `BattleState`
(`src/battle/BattleState.lua`) keeps its own message queue and draws its own
menus in `drawTextArea`. The presenter reads the same fields that drawing
uses, through the general screen reader (`menus-and-text.md`). No battle
file is edited.

| Phase | What is spoken |
|---|---|
| `messages` | Each new message (`self.current`) once, whole. Battle messages **queue** rather than interrupt, so quick auto-advancing lines are not cut off. |
| `menu` | On opening: your Pokémon and exact HP, the enemy's name, level and HP **percentage** (Gen 1 shows the enemy only as a bar), each side's status condition (PSN, PAR...) when it has one, then the selected command. Then each command as the cursor moves. Safari: BALL with count, BAIT, THROW ROCK, RUN. |
| `moveSelect` | Move name, type, PP, and position on opening. "Disabled" for a disabled slot. |
| `mimicSelect` | "Mimic which move?" and the move. |
| Level-up stats box | After "grew to level N!": name, new level and the four stats. The box is a file-local class in `BattleState.lua` (`StatBox`), recognised by its draw function's source file. Wording follows the old project's announcement (name and level first). |

Party and bag inside battle are `PartyMenu` and `ListMenu` screens pushed on
top, so the general presenters read them. The old man's catching demo menu
is skipped (`state.demo`).

## Gen 2 (Gold, Silver, Crystal; decision 27)

Matched by the metatable of `src/ui/gen2/BattleState.lua`, so link battles
(pushed without a screen id) are covered too. The engine resolves the whole
turn before the messages play, so HP, status and the active Pokémon come from
the copies the HUD draws (`activeMon`, `hudHp`, `hudStatus`, `statusTag`).
Only fields and side-effect-free methods are read: `Battle:moveDisabled`,
`Battle:partyMoves` and `BugContest.state` create tables, so their fields
are read directly instead.

| Phase | What is spoken |
|---|---|
| Message box (any phase) | Each new line once, queued; the same line shown again is spoken again. Pages follow the game's own paging; the row a scroll page repeats is dropped when it is the row just spoken. With DIALOGUE SPEECH set to ALL AT ONCE, the whole box at once. |
| `menu` | Both sides in the Gen 1 wording plus status tags, then the command; shiny and gender the first time each Pokémon is summarised in a battle. The summary queues (Gen 1 interrupts) so the enemy's last self-advancing line is not cut off; cursor moves interrupt. Bug-Catching Contest: "PARK BALL, N left". The catching tutorial's menu stays quiet. Returning from the party or pack repeats both sides. |
| `moves` | Move, type, "PP n of m", position on opening; "disabled"; a missing PP is left out, never "0"; the "???" type is "question marks"; SELECT reorder: "marked for swap", "swapped, ...", "swap cancelled". |
| YES/NO phases | The question (as a message), then YES/NO once drawn, queued; cursor moves interrupt. Nickname, switch offer, "Use next POKéMON?", forget a move, stop learning. |
| `choose-forget` | "Which move should be forgotten?", the move with PP and position, then each move. |
| `stats-box` | Name, level and the five stats, recomputed as the stats box draws them. |

Example from a Crystal run: "CYNDAQUIL, male, HP 28 of 28. enemy SENTRET,
shiny, level 5, male, HP 100 percent. FIGHT". `Gen2Battle.health()` gives
the on-demand health text ("Player RATTATA, 46 of 46 HP | Enemy health:
100.00 percent"); the H and Shift+H keys reach it once navigation runs in
Gen 2 (`navigation.md`).

**Fast game speed.** Speech polls once per rendered frame, and GAME SPEED
has no battle lock. At 200X with BATTLE SCENE off a scripted run lost 2 of
14 self-advancing lines ("Go! CYNDAQUIL!" and an enemy move line); none at
8X or 64X; lines that wait for A are never lost. Gen 1 polls the same way.
Catching every line at 200X would need a listed wrapper around the battle's
page functions; not done (AUTO-WALK SPEED never applies in battle).

## Gen 3 (FireRed, LeafGreen; decision 29)

Presenter `src/access/screens/gen3/Battle.lua`. The battle is a module
(`src/core/game3/battle`), reported by `gen3/Top.lua` as a proxy keyed on
`Battle._st` while no menu layer is open; party, bag, summary (forgetting
a move), naming, Pokédex and evolution are layers with their own
presenters. Shown values only: `Anim._present[id]` (`displayHp`,
`displayMaxHp`, `displayLevel`, `displayStatus`, `shown`) and
`Anim._stage.healthbox[id].visible`, read with rawget.

| Part | What is spoken |
|---|---|
| Message box | Every page shown (frames battle and voiceover), once, queued; a re-shown line again; ALL AT ONCE whole; "LV. 13" said "level 13" |
| Action menu | First menu of a turn, and after the party or bag: every side (yours exact HP, the enemy's level and HP percent, status tags; shiny, gender, "owned" the first time), "What will X do?", the command; queued. Reopened in the same turn (partner, B back, refused choice): prompt and command, interrupting. Safari: "BALL, N left", ROCK, BAIT. Old man and POKé DUDE: prompt only |
| Moves | Name, type, "PP n of m", position; missing PP left out; "???" is "question marks"; no disabled marker (the game shows none). SELECT: "Switch which?", the second cursor's move, "swapped" or "swap cancelled" |
| Targets (doubles) | "enemy X, HP n percent" or "X, HP n of m" |
| YES/NO | After the question: the option queued, moves interrupt |
| Level-up window | Page 1 increases (queued), page 2 totals (interrupts), six stats with max HP |

Example (FireRed): "CHARMANDER, male, HP 33 of 33. enemy PIDGEY, level 3,
male, HP 100 percent. What will CHARMANDER do? FIGHT".
`Gen3Battle.health(state, side)` answers H and Shift+H in the Gen 2 words;
doubles name both battlers; Safari Shift+H gives the balls left.

**Fast game speed.** A record-only runtime wrapper on `Message.show` and
`Message.close` (original called unchanged, results passed through) keeps
each battle page shown between two polls, so it is still said. 200X
FireRed trainer battle: 8 of 32 lines lost without it, 0 of 38 with it.

Ruby, Sapphire and Emerald use this presenter; their notes are in
`ruby-sapphire-emerald.md` (section "Battle").

## Not covered yet

- Shift and switch prompts and link battles: not yet checked in a game run.
- On-demand status keys (for example "read enemy HP" from Pokémon Access) belong
  to the commands workstream.
- Gen 2: ball shakes (the failure line says how close it was), on-demand
  EXP, held item, weather and screens; link-battle waiting phases (not run);
  the Battle Tower, the Bug-Catching Contest and the catching tutorial are
  unit-tested only.

## Verification (2026-10-31)

| Level | Result |
|---|---|
| Unit tests | `luajit tests/access/battle_speech_test.lua`: 16/16 (status in summary, level-up stats box, messages queue, menu with both sides, labels, move list, disabled slot, Safari, Mimic). |
| Scripted game run | `tests/access/drivers/battle.lua`, disposable identity, real Prism (NVDA): wild PIDGEY on Route 1. The trace shows "Wild PIDGEY appeared!", "Go! SQUIRTLE!", the menu with HP for both sides each turn, every command, the move list with type and PP, misses, the enemy's moves, "Enemy PIDGEY fainted!" and the experience line. |
| Scripted trainer battle | `tests/access/drivers/trainer_battle.lua`: Youngster with RATTATA and EKANS. Trace: "YOUNGSTER wants to fight!", each send-out, HP for both sides each turn, a critical hit, stat drop, both faints, experience, "defeated YOUNGSTER!" and the prize money. |
| Scripted level-up battle | `tests/access/drivers/level_up_battle.lua`: a poisoned SQUIRTLE one point short of level 6. Trace: PSN in every turn summary, "hurt by poison!", stat drops, "grew to level 6!" and the stats box. |
| Gen 2 (2026-11-01) | `gen2_battle_test.lua` 86/86 (hand-built screens and the real `BattleState` around a stub game). `drivers/gen2_battle.lua` in Crystal, Gold and Silver (identities `pocket-access-battle-<game>`): a shiny wild battle with a party peek, a move swap and balls thrown until caught; a wild battle run from; a trainer battle with a faint, level up and stats box, forgetting TAIL WHIP for FOCUS ENERGY, the switch offer, a voluntary switch, the win and an evolution after it; "Use next POKéMON?" and "Choose a POKéMON.". The driver logged every line the box showed at each logic step: none went unspoken at 1X in any game. ALL AT ONCE run in Crystal. |
| Gen 3 (2026-11-01) | `gen3_battle_test.lua` 92/92 (the real battle, Ui, Anim, Message, Choice and StatGrowth modules, a 200X run of the real queue). `drivers/gen3_battle.lua` in FireRed (identity `pocket-access-battle-firered`): wild catch, level up with learn-move questions, SHIFT trainer battle, run, Safari, the old man, doubles, 200X: every shown page spoken. Unit tests only: Oak's first battle, Pokémon Tower ghost, the caught marker. Not run: link battles, Trainer Tower, the POKé DUDE. |
| Heard by the owner | Gen 1: not yet in a listening session. Gen 2: Crystal battles up to the first gym, 2026-11-01, "It works perfectly in Crystal." |
