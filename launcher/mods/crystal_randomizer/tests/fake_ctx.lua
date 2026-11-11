-- A stand-in for the core's ctx, for module tests run with luajit from the
-- repository root:
--   local ctx = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua").new({
--     seed = "test", options = { wild = true } })
--   ctx.setActive(false)   -- runs every onSave callback with false
-- The generator version is opts.version, else CRYSTAL_RANDOMIZER_RNG_VERSION,
-- else 1 (rng.lua), so every module test can be run on both generators.
local Rng = dofile("launcher/mods/crystal_randomizer/rng.lua")

local Fake = {}

function Fake.new(opts)
  opts = opts or {}
  local version = tonumber(opts.version or os.getenv("CRYSTAL_RANDOMIZER_RNG_VERSION")) or 1
  local state = { seed = opts.seed, options = opts.options or {}, active = opts.seed ~= nil }
  local listeners = {}
  local ctx = { shared = {}, lib = {}, lines = {} }
  function ctx.active() return state.active end
  function ctx.seed() return state.active and state.seed or nil end
  function ctx.option(key) if state.active then return state.options[key] end end
  function ctx.version() return version end
  function ctx.rng(stream, ...) return Rng.streamFor(version, state.seed, stream, ...) end
  function ctx.onSave(fn) listeners[#listeners + 1] = fn end
  function ctx.log(fmt, ...) ctx.lines[#ctx.lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
  -- test controls
  function ctx.setActive(active, seed, options)
    state.active = active
    if seed then state.seed = seed end
    if options then state.options = options end
    for _, fn in ipairs(listeners) do fn(active) end
  end
  return ctx
end

return Fake
