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
    --
    -- ⚠ `family = "auras"` added 2026-08-25, and it is a BINDING FIX rather than a label.
    -- `Catalog.findRow` defaults a missing family to `"spells"` and matches only rows in that
    -- family, but Backdraft is a TrackedBuff row (`BuffIconCooldownViewer`, family `auras`) —
    -- so without this key the ability could never resolve, and the sealed count band that
    -- names it as its subject had no subject. `Sense`'s seeding branches on the same key and
    -- would have called `readCooldown` on an aura. Every other aura subject in every other
    -- catalog already declares it; this was the one that did not.
    { id = "backdraft", spell = 117828, family = "auras" },
  },

  entries = {
    {
      -- Default membership (ready-self). The old two bands — ROTATION at <=4 shards, FALLBACK
      -- otherwise — both yielded membership, so the shard term carried no membership
      -- information; under blindness this row now stays lit, which is what a filler should do.
      id = "conflagrate", ability = "conflagrate",
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
