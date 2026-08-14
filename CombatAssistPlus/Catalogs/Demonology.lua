-- Demonology.lua — the deliberately small Demonology / Diabolist pilot.
-- Gameplay choices here are provisional characterizations to fly, not engine policy.
local ADDON, ns = ...

ns.Catalog.Register{
  spec = 266,
  hero = 59,
  name = "Demonology / Diabolist pilot",
  power = "SoulShards",

  -- Dependencies may be read without becoming enhanced entries. There is no exhaustive
  -- accounting of the rest of the Cooldown Manager.
  abilities = {
    { id = "tyrant", spell = 265187 },
    { id = "dreadstalkers", spell = 104316 },
    { id = "grimoire", spell = 1276452, alt = { 1276467 } },
    { id = "demonbolt", spell = 264178 },
  },

  entries = {
    {
      id = "tyrant", ability = "tyrant",
      -- Canonical readiness-tier example. Its marker forms are the canonical readable
      -- fact-to-context examples; their gameplay meaning remains provisional here.
      bands = {
        { tier = "ROTATION", when = { { "ready", "tyrant" } } },
      },
      markers = {
        -- These mean exactly what the readable rows establish: dogs were committed and
        -- their cooldown is running; the Grimoire row is transformed. Neither claims the
        -- summoned pet is still active.
        { id = "dreadstalkers", when = { { "ready", "dreadstalkers", negate = true } } },
        { id = "grimoire", when = { { "identity", "grimoire", "transformed" } } },
      },
    },
    {
      id = "demonbolt", ability = "demonbolt",
      -- Canonical proc-plus-secondary-resource tier example.
      bands = {
        { tier = "ROTATION", when = { { "proc", "demonbolt" }, { "resource", "<=", 3 } } },
        { tier = "FALLBACK", when = { { "proc", "demonbolt" } } },
      },
    },
  },

  bar = "tyrant",
}
