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
| `ctx.rng(stream, ...)` | a deterministic generator for this seed, `stream` and the keys after it: `:next()` in [0,1), `:int(lo, hi)`, `:pick(list)`, `:shuffled(list)`. Same seed and keys, same answers |
| `ctx.onSave(fn)` | `fn(active)` runs whenever the loaded save's randomizer state becomes known or changes (New Game after Oak, Continue, returning to the title). A module that has to change tables changes them here and restores vanilla when `active` is false |
| `ctx.shared` | a table modules use to share results, for example `ctx.shared.starters` (see below) |
| `ctx.log(fmt, ...)` | the mod's log |

Shared values:

- `ctx.shared.starters`: set by the starters module, `{ CHIKORITA = "X", CYNDAQUIL = "Y", TOTODILE = "Z" }`
  (vanilla starter id to the species given instead), read by the trainers module for the rival.

## Rules

- Species, moves, items and types use the game's own ids, from the game's data (`Data`), never a list
  typed in by hand, so a mod that adds species is respected where it is reasonable.
- Keep the game winnable: nothing a story event needs (an HM user, a key item, a scripted battle's
  survival) may become impossible.
- Every result depends only on the seed and fixed keys, never on the order things are asked.
- Each module has a test in `tests/<id>_test.lua`, runnable with `luajit` from the repository root, with a
  fake `ctx` from `tests/fake_ctx.lua`.
