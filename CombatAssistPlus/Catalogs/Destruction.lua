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
        { id = "backdraft", display = {
          kind = "player-aura-stacks", ability = "backdraft", min = 2,
        } },
      },
    },
  },
}
