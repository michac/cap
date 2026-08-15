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
    -- Meta's payoff is its RESET of Eye Beam and Death Sweep, so spending it while either is
    -- already up throws that half away. Two markers rather than one because the band grammar is
    -- AND-only: naming the same cue twice unions into a single badge, and that union IS the OR.
    -- A satisfied dependency draws nothing (catalog.md:133).
    { id = "metamorphosis", ability = "metamorphosis",
      bands = { { tier = "COOLDOWN", when = { { "ready", "metamorphosis" } } } },
      markers = {
        { id = "meta_wastes_eye_beam", cue = "blocked",
          when = { { "ready", "eye_beam" } } },
        -- Base id only: Bind unions base/override, so this reads Death Sweep in demon form.
        { id = "meta_wastes_death_sweep", cue = "blocked",
          when = { { "ready", "blade_dance" } } },
      } },
    -- Hold The Hunt for the Meta window rather than spending it bare (catalog.md:145).
    { id = "the_hunt", ability = "the_hunt",
      bands = { { tier = "COOLDOWN", when = { { "ready", "the_hunt" } } } },
      markers = {
        { id = "hunt_awaits_meta", cue = "blocked",
          when = { { "ready", "metamorphosis" } } },
      } },
    { id = "eye_beam", ability = "eye_beam",
      bands = { { tier = "COOLDOWN", when = { { "ready", "eye_beam" } } } } },
    -- Essence Break's window wants Eye Beam inside it, so spending it with Eye Beam a moment
    -- away throws the window away. The clock is secret, so cap never reads it: it authors the
    -- band and the client paints the badge while the remaining time sits inside it
    -- (catalog.md:158, cue C2).
    { id = "essence_break", ability = "essence_break",
      bands = { { tier = "COOLDOWN", when = { { "ready", "essence_break" } } } },
      markers = {
        { id = "essence_break_awaits_eye_beam", cue = "blocked",
          display = { kind = "sealed-cooldown-range", ability = "eye_beam", within = 4 } },
      } },
    -- The two Fury spenders. `ready` cannot carry affordability here: a row with no real cooldown
    -- never raises an Available/OnCooldown edge, so its border stays lit whatever the Fury. The
    -- generators cost nothing, so `insufficientPower` is never true for them — they stay clean
    -- while the spenders wear the badge, which is the whole point of the cue.
    { id = "blade_dance", ability = "blade_dance",
      bands = { { tier = "ROTATION", when = { { "ready", "blade_dance" } } } },
      markers = {
        { id = "blade_dance_starved", cue = "starved",
          when = { { "affordable", "blade_dance", negate = true } } },
      } },
    { id = "chaos_strike", ability = "chaos_strike",
      bands = { { tier = "ROTATION", when = { { "ready", "chaos_strike" } } } },
      markers = {
        { id = "chaos_strike_starved", cue = "starved",
          when = { { "affordable", "chaos_strike", negate = true } } },
      } },
    -- Two readable states off `isActive`, which is NeverSecret and therefore answers in both
    -- directions: at max it is the gold `capped` badge (a charge is being lost right now); below
    -- max it is the red `blocked` badge (hold the one you have, let the other come back).
    { id = "immolation_aura", ability = "immolation_aura",
      bands = { { tier = "ROTATION", when = { { "ready", "immolation_aura" } } } },
      markers = {
        { id = "immolation_capped", cue = "capped",
          when = { { "capped", "immolation_aura" } } },
        { id = "immolation_recharging", cue = "blocked",
          when = { { "capped", "immolation_aura", negate = true } } },
      } },
    -- The two generators, which cost nothing and therefore never wear the affordability cue —
    -- their failure mode is the opposite one: generating Fury that overflows the cap. That
    -- decision is `secret Fury-% ≥ (maxFury − generation)/maxFury`, and cap performs no part of
    -- it: the client evaluates an authored curve against the secret and paints the result.
    -- `generation` is an authored static approximation because no API reports it (catalog.md
    -- R4); the max is the client's, and is emphatically not hardcoded.
    { id = "felblade", ability = "felblade",
      bands = { { tier = "ROTATION", when = { { "ready", "felblade" } } } },
      markers = {
        { id = "felblade_overcap", cue = "overcap",
          display = { kind = "sealed-power-percent", power = "Fury", generation = 15 } },
      } },
    { id = "demons_bite", ability = "demons_bite",
      bands = { { tier = "ROTATION", when = { { "ready", "demons_bite" } } } },
      markers = {
        -- Demon's Bite rolls 20–30; the midpoint is the honest authoring of a range cap
        -- cannot read, and the cue is a "close to overflowing" readout, not a guarantee.
        { id = "demons_bite_overcap", cue = "overcap",
          display = { kind = "sealed-power-percent", power = "Fury", generation = 25 } },
      } },
    { id = "fel_rush", ability = "fel_rush",
      bands = { { tier = "FALLBACK", when = { { "ready", "fel_rush" } } } } },
    { id = "throw_glaive", ability = "throw_glaive",
      bands = { { tier = "FALLBACK", when = { { "ready", "throw_glaive" } } } } },
  },
}
