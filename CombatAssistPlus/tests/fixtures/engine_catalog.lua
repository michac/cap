-- engine_catalog.lua — the ENGINE's fixture catalog, and not a product one.
--
-- `backlog.md`: engine guarantees and provisional per-spec examples are separate groups. Until
-- 2026-08-22 the engine specs rode the Demonology *pilot*, so building the real Demonology
-- catalog broke four engine tests that were not about Demonology at all — and the pressure that
-- created was to keep the shipped catalog shaped like a fixture, which is exactly backwards.
--
-- So this is the pilot, preserved as what it always was: the smallest catalog that exercises
-- readable readiness, a readable marker pair, a declared `scan_when` alternative and a
-- resource comparison. It binds against `demonology-rows.lua` because that is the row capture
-- the harness has; nothing about it is a claim about how Demonology should be played.
local ADDON, ns = ...

ns.Catalog.Register{
  spec = 0,
  hero = 0,
  name = "engine fixture",
  power = "SoulShards",

  abilities = {
    { id = "tyrant", spell = 265187 },
    { id = "dreadstalkers", spell = 104316 },
    { id = "grimoire", spell = 1276452, alt = { 1276467 } },
    { id = "demonbolt", spell = 264178 },
  },

  entries = {
    {
      -- Default membership: no `scan_when`, so the engine reads ready(self) and nothing else.
      id = "tyrant", ability = "tyrant",
      markers = {
        { id = "dreadstalkers", when = { { "ready", "dreadstalkers", negate = true } } },
        { id = "grimoire", when = { { "identity", "grimoire", "transformed" } } },
      },
    },
    {
      -- Declared membership: one conditional alternative, blind-able through the resource
      -- read. Tests add a second alternative in situ to pin the OR semantics.
      id = "demonbolt", ability = "demonbolt",
      scan_when = { { { "proc", "demonbolt" }, { "resource", "<=", 3 } } },
    },
  },

  bar = "tyrant",
}
