-- Destruction.lua — the minimal Destruction / Diabolist authoring proof.
-- Gameplay choices are provisional characterizations; mechanisms remain shared.
local ADDON, ns = ...

ns.Catalog.Register{
  spec = 267,
  hero = 59,
  name = "Destruction / Diabolist pilot",
  power = "SoulShards",

  abilities = {
    { id = "conflagrate", spell = 17962, alt = { 91591 }, charged = true },
    -- Aura dependency only: this is not an enhanced CDM entry and never enters Signal.
    { id = "backdraft", spell = 117828 },
  },

  entries = {
    {
      id = "conflagrate", ability = "conflagrate",
      bands = {
        { tier = "ROTATION", when = { { "ready", "conflagrate" }, { "resource", "<=", 4 } } },
        { tier = "FALLBACK", when = { { "ready", "conflagrate" } } },
      },
      markers = {
        -- Migrated from `player-aura-stacks` to V16's bands on 2026-08-22. The shape is
        -- UNCHANGED — silent below two, the number at two and above — but it is now cap's own
        -- rule rather than Blizzard's no-formatter default, which is the only difference and the
        -- whole point: `min = 2` was never a ceiling. Destruction's own catalog is not authored
        -- yet (`specs/backlog.md`), so this is a mechanical migration and not a design change.
        { id = "backdraft", display = {
          kind = "sealed-count-bands", ability = "backdraft",
          bands = {
            { threshold = 0, draw = "none" },
            { threshold = 2, draw = "count" },
          },
        } },
      },
    },
  },
}
