# Yellow

What differs from Red for accessibility. Everything not listed here works
as described in `menus-and-text.md` and `battle.md` (Yellow intro, title,
Oak's speech, naming and start menu verified in a scripted run, 2026-10-31).

## Talking to Pikachu (done)

The game answers with a picture of Pikachu and a cry, no text. The
overworld presenter (`src/access/screens/Overworld.lua`) speaks the
reaction, for example "Pikachu is happy" or "Pikachu is asleep". The
reaction is traced from the shown picture back to its emotion number in the
game's own data, and worded from pokeyellow's `PikachuEmotionTable` names
(read in `pret/pokeyellow`, `engine/pikachu/pikachu_emotions.asm`, for
meaning only). All 32 reactions checked against the real Yellow data.
Not yet triggered by talking to Pikachu in a game run.

## Surfing Pikachu minigame (proposed design, not built)

Status: proposal awaiting the owner's decision. Source studied:
`src/ui/SurfingMinigame.lua` at v0.3.98.

### How the game actually plays

From upstream's source, not from memory:

- Pikachu speeds up **automatically**. There is no paddle button.
- The **jump is automatic**: when Pikachu reaches a wave crest fast enough,
  it launches (`updateRiding`, crest tile 0x14). The game already plays a
  jump sound.
- In the air, **Left and Right spin** the board (backflip and frontflip)
  through 14 angles (`frameSet`). Tricks score more for more spins.
- The landing is graded by the board angle against the water under Pikachu
  at that moment (`evaluateLanding`): clean, rough (slower), hard (much
  slower) or wipeout (crash for 96 frames, speed reset). Clean needs a
  different angle on a rising slope, falling slope, crest or flat water.
- A 60-second timer runs; the course has 24 sections, with the big wave
  ("Big Kahuna") near the end.

The old project only announced the phase, and its instructions ("press A
to paddle, Up to jump") do not match this source. Pokémon Access has no
support for this minigame.

### Proposed cues

The key insight: `evaluateLanding` is a read-only check of the current angle
and the water under Pikachu, so the layer can ask every frame, "if Pikachu
landed right now, how would it go?" and play that as sound. The player spins
until the sound says "safe", then stops.

1. **On entry:** a short spoken briefing: "Surfing Pikachu. Pikachu jumps on
   its own at each crest. In the air, Left and Right spin. Stop spinning on the
   high tone to land cleanly."
2. **In the air, a landing tone** that repeats while airborne and updates as
   the board turns. It gets faster when Pikachu starts falling
   (`jumpDescending`):
   - clean: high, clear tone
   - rough: middle tone
   - hard: low tone
   - wipeout: no tone (silence means "keep spinning or straighten up")
3. **Landing:** the game's own landing or crash sound, plus the trick popup
   text spoken as the game shows it (points), and "rough", "hard" or
   "wipeout" when not clean.
4. **Timer and progress:** spoken at 30 and 10 seconds left, and when the big
   wave section starts.
5. **Results:** the tally lines (time bonus, radness, total) and "new high
   score", read as they appear.

Speed needs no cue: the game already speeds its music up with Pikachu.

### Implementation notes

- Tones are our own generated sounds (a few short sine blips made with
  `love.sound.newSoundData` at start-up), so nothing third-party is shipped.
  They would become part of the earcon set planned for navigation.
- Reads only: `pikaState`, `frameSet`, `jumpDescending`, `routine`, `hp`,
  `distanceSection`, `trickPopups`, `outroLines`, `newRecord`; calls the
  read-only `evaluateLanding` and `getWaveTileUnderPika` through `pcall`.
- Open question for the owner: tone pitches and volume, and whether the
  landing tone should be continuous or repeating blips.
- Needs the owner's playtest: the grade can change between the last tone
  and touchdown, because the water under Pikachu keeps moving.
