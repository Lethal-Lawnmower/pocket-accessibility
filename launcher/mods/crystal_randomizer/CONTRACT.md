# Crystal randomizer: how the pieces fit

A mod (`launcher/mods/crystal_randomizer`, id `crystal_randomizer`, api 2, permission `engine_internals`).
No ROM patching: everything is decided at runtime from one seed per save.

## The core (`main.lua`, `rng.lua`)

- At New Game, Oak asks the questions every module declares (through the `intro.oak_speech.build`
  hook), and a seed is made. Answers and seed are stored in `mod.save`, so they travel with that save.
- A save without a seed is a vanilla save: every module must leave the game exactly as it was.
- Loading another save in the same process must not keep the previous save's randomization.

## A module (`modules/<name>.lua`)

```lua
return {
  id = "wild",
  -- Oak asks these in order at New Game.  kind "yesno" answers true/false;
  -- kind "choice" answers one of `options` (each { label = "...", value = ... }).
  -- onlyIf names an earlier key that must be true for this one to be asked.
  questions = {
    { key = "wild", kind = "yesno", text = "Shuffle wild\nPOKéMON?" },
    { key = "wild_similar", kind = "yesno", onlyIf = "wild", text = "Keep them about\nas strong?" },
  },
  -- Called once when the mod loads.  Prefer runtime hooks that ask ctx each time
  -- over changing data at load: the seed is not known until a save is.
  install = function(mod, ctx) end,
}
```

`ctx`, the same table for every module:

| Field | Meaning |
|---|---|
| `ctx.active()` | true when the loaded save is randomized |
| `ctx.option(key)` | that save's answer for `key`, or nil (also nil when not active) |
| `ctx.seed()` | that save's seed (a string), or nil |
| `ctx.rng(stream, ...)` | a deterministic generator for this seed, `stream` and the keys after it: `:next()` in [0,1), `:int(lo, hi)`, `:pick(list)`, `:shuffled(list)`. Same seed and keys, same answers. Which generator depends on the save (`ctx.version()`) |
| `ctx.version()` | the generator the save was made with: 1 for saves from before 2026-11-10 (no `rng` in the save), 2 for every new seed. See "Generator 2" below |
| `ctx.onSave(fn)` | `fn(active)` runs whenever the loaded save's randomizer state becomes known or changes (New Game after Oak, Continue, returning to the title). A module that has to change tables changes them here and restores vanilla when `active` is false |
| `ctx.shared` | a table modules use to share results, for example `ctx.shared.starters` (see below) |
| `ctx.log(fmt, ...)` | the mod's log |

Shared values:

- `ctx.shared.starters`: set by the starters module, `{ CHIKORITA = "X", CYNDAQUIL = "Y", TOTODILE = "Z" }`
  (vanilla starter id to the species given instead), read by the trainers module for the rival.

## Version 2 additions (2026-11-08)

**Setups.** After "Do you want your adventure shuffled?", Oak asks for a setup: RECOMMENDED, EVERYTHING or
CHOOSE EACH. Only CHOOSE EACH asks the questions one by one. The other two take each question's own value,
so every question must carry both:

```lua
{ key = "wild", kind = "yesno", text = "Shuffle wild\nPOKéMON?", recommended = true, everything = true },
{ key = "wild_mode", kind = "choice", onlyIf = "wild", text = "One swap per\nroute or game?",
  options = { { label = "PER ROUTE", value = "route" }, { label = "WHOLE GAME", value = "game" },
              { label = "ANY SLOT", value = "slot" } },
  recommended = "route", everything = "game" },
```

A choice label is at most 12 characters, uppercase like the game's menus. A missing value counts as false.
Oak's text boxes hold two lines of at most 18 characters each, with `\n` between lines, `\v` to scroll a
line and `\f` for a new box.

**Modules, in install and save-switch order:** `pokemon`, `stats`, `evolutions`, `starters`, `items`, `tms`,
`shops`, `wild`, `trainers`, `qol`, `keyitems`. A module that changes tables changes only its own fields and
restores exactly those. A module later in the order reads earlier modules' results from the current data at
`ctx.onSave` time (for example, starters read evolutions after the evolutions module has changed them), and
reads them again on every switch.

**Shared values** (in `ctx.shared`, rebuilt on every switch):
- `starters`: as above.
- `starterRivalPairs` (starters module), keyed by the ball the player takes:
  `{ CHIKORITA = { player = <species>, rivalBall = "CYNDAQUIL", rival = <species>, strong = true|false }, ... }`.
  The trainers module reads `rival`.
- `wild` (wild module): `[scope][original] = replacement`, and `wild.report` with coverage figures.
- `keyitems` (keyitems module): where each HM was placed.

## Rules

- Species, moves, items and types use the game's own ids, from the game's data (`Data`), never a list
  typed in by hand, so a mod that adds species is respected where it is reasonable.
- Keep the game winnable: nothing a story event needs (an HM user, a key item, a scripted battle's
  survival) may become impossible.
- Every result depends only on the seed and fixed keys, never on the order things are asked.
- Each module has a test in `tests/<id>_test.lua`, runnable with `luajit` from the repository root, with a
  fake `ctx` from `tests/fake_ctx.lua`.

## Generator 2 (2026-11-10)

Generator 1 (`Rng.stream`) hashes the seed and keys with FNV-1a and steps a linear generator. Both are close
to linear in the last bytes of a key, so streams whose keys differ only at the end (slot 1, slot 2 of a
route) gave related answers: of 100 choices, neighbouring slots matched 0.1% of the time instead of 1%, and
one difference between them came up about twenty times as often as it should. Generator 2
(`Rng.mixedStream`) runs the same hash through MurmurHash3's 32-bit finalizer (`Rng.mix`, plain arithmetic,
no bit library) before the first step; neighbouring slots then match 1.0% of the time.

A save keeps the generator it was made with, because every module works its answers out again from the seed
at each load: changing a save's generator would change its wild Pokémon, trainers, items and the rest in the
middle of a run. The core writes `rng = 2` with every new seed (the save's `version` stays 1; it is not the
feature round called "version 2" above). `Rng.stream` must never change; `tests/rng_test.lua` pins a value.

The starters module's type triangle also changed for generator 2 (`fairTriangle`): generator 1's search takes
the first triangle in a shuffled order, which on the cart's data put GEODUDE, LARVITAR or CHIKORITA in about
a third of all seeds each (a fair share is 11%). Generator 2 lists every triangle, weights them so each species
is in the chosen one about equally often as far as the types allow, then draws one and turns it so any of its
species may be in any ball. Module tests run on either generator with `CRYSTAL_RANDOMIZER_RNG_VERSION=1|2`.

