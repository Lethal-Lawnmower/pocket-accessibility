# Battle

Speech for Gen 1 battles. Presenter: `src/access/screens/Battle.lua`.

## How it works

Battle text never goes through `TextBox`. `BattleState`
(`src/battle/BattleState.lua`) keeps its own message queue and draws its own
menus in `drawTextArea`. The presenter reads the same fields that drawing
uses, through the general screen reader (`menus-and-text.md`). No battle
file is edited.

| Phase | What is spoken |
|---|---|
| `messages` | Each new message (`self.current`) once, whole. Battle messages **queue** rather than interrupt, so quick auto-advancing lines are not cut off. |
| `menu` | On opening: your Pokémon and exact HP, the enemy's name, level and HP **percentage** (Gen 1 shows the enemy only as a bar), then the selected command. Then each command as the cursor moves. Safari: BALL with count, BAIT, THROW ROCK, RUN. |
| `moveSelect` | Move name, type, PP, and position on opening. "Disabled" for a disabled slot. |
| `mimicSelect` | "Mimic which move?" and the move. |

Party and bag inside battle are `PartyMenu` and `ListMenu` screens pushed on
top, so the general presenters read them. The old man's catching demo menu
is skipped (`state.demo`).

## Not covered yet

- Shift and switch prompts and link battles: not yet checked in a game run.
- On-demand status keys (for example "read enemy HP" from Pokémon Access) belong
  to the commands workstream.

## Verification (2026-10-31)

| Level | Result |
|---|---|
| Unit tests | `luajit tests/access/battle_speech_test.lua`: 14/14 (messages queue, menu with both sides, labels, move list, disabled slot, Safari, Mimic). |
| Scripted game run | `tests/access/drivers/battle.lua`, disposable identity, real Prism (NVDA): wild PIDGEY on Route 1. The trace shows "Wild PIDGEY appeared!", "Go! SQUIRTLE!", the menu with HP for both sides each turn, every command, the move list with type and PP, misses, the enemy's moves, "Enemy PIDGEY fainted!" and the experience line. |
| Scripted trainer battle | `tests/access/drivers/trainer_battle.lua`: Youngster with RATTATA and EKANS. Trace: "YOUNGSTER wants to fight!", each send-out, HP for both sides each turn, a critical hit, stat drop, both faints, experience, "defeated YOUNGSTER!" and the prize money. |
| Heard by the owner | Not yet. |
