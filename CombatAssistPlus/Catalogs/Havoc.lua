-- Havoc.lua — the Fel-Scarred roster. Aldrachi Reaver (hero 35) is a separate catalog and
-- correctly gets nothing. Gameplay choices are provisional characterizations to fly.
--
-- No `power` field: Fury is a secret primary, so the `resource` predicate can never be used
-- on this spec. Base spell ids only — Bind unions base/override/tooltip/live into the row, so
-- the demon-form flip needs no hardcoded override ids.
local ADDON, ns = ...

ns.Catalog.Register{
  spec = 577,
  hero = 34,
  name = "Havoc / Fel-Scarred",

  abilities = {
    { id = "vengeful_retreat", spell = 198793 },
    { id = "metamorphosis", spell = 191427 },
    { id = "the_hunt", spell = 370965 },
    { id = "eye_beam", spell = 198013 },
    { id = "essence_break", spell = 258860 },
    { id = "blade_dance", spell = 188499 },
    { id = "chaos_strike", spell = 344862 },
    { id = "immolation_aura", spell = 258920, charged = true },
    { id = "felblade", spell = 232893 },
    { id = "demons_bite", spell = 344859 },
    { id = "fel_rush", spell = 344865, charged = true },
    { id = "throw_glaive", spell = 185123, charged = true },
  },

  -- Entry order IS the authored priority, and `Catalog.OrderCheck` reports when the player's
  -- Cooldown Manager disagrees with it.
  entries = {
    { id = "vengeful_retreat", ability = "vengeful_retreat",
      bands = { { tier = "COOLDOWN", when = { { "ready", "vengeful_retreat" } } } } },
    { id = "metamorphosis", ability = "metamorphosis",
      bands = { { tier = "COOLDOWN", when = { { "ready", "metamorphosis" } } } } },
    { id = "the_hunt", ability = "the_hunt",
      bands = { { tier = "COOLDOWN", when = { { "ready", "the_hunt" } } } } },
    { id = "eye_beam", ability = "eye_beam",
      bands = { { tier = "COOLDOWN", when = { { "ready", "eye_beam" } } } } },
    { id = "essence_break", ability = "essence_break",
      bands = { { tier = "COOLDOWN", when = { { "ready", "essence_break" } } } } },
    { id = "blade_dance", ability = "blade_dance",
      bands = { { tier = "ROTATION", when = { { "ready", "blade_dance" } } } } },
    { id = "chaos_strike", ability = "chaos_strike",
      bands = { { tier = "ROTATION", when = { { "ready", "chaos_strike" } } } } },
    { id = "immolation_aura", ability = "immolation_aura",
      bands = { { tier = "ROTATION", when = { { "ready", "immolation_aura" } } } } },
    { id = "felblade", ability = "felblade",
      bands = { { tier = "ROTATION", when = { { "ready", "felblade" } } } } },
    { id = "demons_bite", ability = "demons_bite",
      bands = { { tier = "ROTATION", when = { { "ready", "demons_bite" } } } } },
    { id = "fel_rush", ability = "fel_rush",
      bands = { { tier = "FALLBACK", when = { { "ready", "fel_rush" } } } } },
    { id = "throw_glaive", ability = "throw_glaive",
      bands = { { tier = "FALLBACK", when = { { "ready", "throw_glaive" } } } } },
  },
}
