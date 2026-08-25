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
    { id = "immolation_aura", spell = 258920, charged = true },
    { id = "chaos_strike", spell = 344862 },
    { id = "felblade", spell = 232893 },
    { id = "demons_bite", spell = 344859 },
    { id = "fel_rush", spell = 344865, charged = true },
    { id = "throw_glaive", spell = 185123, charged = true },
  },

  -- Node + entry from `knowledge/classes/demon-hunter/havoc/ability-inventory.tsv`. This is
  -- what `talent.a_fire_inside` in the APL means, read as itself rather than through a proxy
  -- (Talents.lua explains why `IsSpellKnown` and max-charge count are both refused).
  talents = {
    { id = "a_fire_inside", node = 95143, entry = 117741, spell = 427775 },
    { id = "burning_wound", node = 90917, entry = 112826, spell = 391189 },
    { id = "eternal_hunt", node = 110427, entry = 137049, spell = 1270898 },
  },

  -- Entry order IS the authored priority. `Catalog.OrderCheck` compares it against Blizzard's
  -- `layoutIndex`, which stopped being the drawn order when Anchor shipped -- so read its verdict
  -- as "the saved layout disagrees", never as "the row on screen disagrees".
  entries = {
    -- Vengeful Retreat is OFF THE GCD, so its rung-5 position in the APL carries no ordering
    -- information: it fires alongside the global-cooldown press, not instead of it. Position 1
    -- is how it is read — glance at the weave, then scan for the press.
    --
    -- Its line is alignment-gated, not press-on-cooldown: the Eye Beam weave or the Meta path.
    -- Authored literally that is a negative badge lit across the whole steady state, so these
    -- two marker ranges are the ACTIONABLE SLICE of it. Same cue twice = one badge = the OR.
    { id = "vengeful_retreat", ability = "vengeful_retreat",
      markers = {
        { id = "vr_awaits_eye_beam", cue = "blocked",
          display = { kind = "sealed-cooldown-range", ability = "eye_beam", within = 8 } },
        { id = "vr_awaits_meta", cue = "blocked",
          display = { kind = "sealed-cooldown-range", ability = "metamorphosis", within = 4 } },
      } },
    -- Meta's payoff is its RESET of Eye Beam and Death Sweep. The APL's whole condition is
    -- `!cooldown.blade_dance.up & cooldown.eye_beam.remains>8`, which straddles the readable
    -- /sealed line: readiness is readable, remaining time is not. Three markers rather than one
    -- because the band grammar is AND-only: naming the same cue three times unions into a single
    -- badge, and that union IS the OR. A satisfied dependency draws nothing.
    { id = "metamorphosis", ability = "metamorphosis",
      markers = {
        -- Eye Beam READY. This is NOT redundant with the band below, which deliberately reads
        -- nothing at zero remaining: Meta sits LEFT of Eye Beam in the row, so a quiet Meta is
        -- pressed before the eye ever reaches Eye Beam. Essence Break, sitting to its RIGHT,
        -- needs only the band — elimination covers its zero case and cannot cover this one.
        { id = "meta_wastes_eye_beam", cue = "blocked",
          when = { { "ready", "eye_beam" } } },
        -- Eye Beam IMMINENT — the rest of `remains>8`. The clock is secret, so cap authors the
        -- band and the client paints the badge while the remaining time sits inside it.
        { id = "meta_awaits_eye_beam", cue = "blocked",
          display = { kind = "sealed-cooldown-range", ability = "eye_beam", within = 8 } },
        -- Base id only: Bind unions base/override, so this reads Death Sweep in demon form.
        { id = "meta_wastes_death_sweep", cue = "blocked",
          when = { { "ready", "blade_dance" } } },
      } },
    -- The Hunt's empower rides the NEXT Eye Beam, so rung 4 casts it only when that Eye Beam is
    -- close (`cooldown.eye_beam.remains<10 & cooldown.metamorphosis.remains>15`) or when
    -- Metamorphosis is ready and about to reset Eye Beam to zero
    -- (`!cooldown.eye_beam.up & cooldown.metamorphosis.up`). Negate that and there are TWO holds,
    -- unioned onto one badge:
    --   · Eye Beam is FAR (≥10s) and Metamorphosis is not ready — the common one, and the one
    --     that costs the most: casting here burns the empower up to ~20s before its Eye Beam.
    --   · Metamorphosis is NEAR (≤15s) but not yet here — save the empower for the Eye Beam the
    --     reset is about to hand you.
    -- Both are gated on ETERNAL HUNT, because without it rung 4 is unconditional and there is no
    -- hold at all. That gate is the `talent` predicate's first use outside Immolation Aura, and
    -- it works because a graded cue may curve on ONE secret while being gated on as many
    -- READABLE facts as it likes.
    { id = "the_hunt", ability = "the_hunt",
      markers = {
        { id = "hunt_awaits_eye_beam", cue = "blocked",
          when = {
            { "talent", "eternal_hunt" },
            -- Meta ready is the OTHER cast case, so this hold must stand down for it.
            { "ready", "metamorphosis", negate = true },
          },
          display = { kind = "sealed-cooldown-range", ability = "eye_beam", beyond = 10 } },
        { id = "hunt_awaits_meta", cue = "blocked",
          when = { { "talent", "eternal_hunt" } },
          display = { kind = "sealed-cooldown-range", ability = "metamorphosis", within = 15 } },
      } },
    { id = "eye_beam", ability = "eye_beam",
       },
    -- Essence Break's window wants Eye Beam inside it, so spending it with Eye Beam a moment
    -- away throws the window away. The clock is secret, so cap never reads it: it authors the
    -- band and the client paints the badge while the remaining time sits inside it
    -- (catalog.md:158, cue C2).
    { id = "essence_break", ability = "essence_break",
      markers = {
        { id = "essence_break_awaits_eye_beam", cue = "blocked",
          display = { kind = "sealed-cooldown-range", ability = "eye_beam", within = 4 } },
      } },
    -- The two Fury spenders. `ready` cannot carry affordability here: a row with no real cooldown
    -- never raises an Available/OnCooldown edge, so its border stays lit whatever the Fury. The
    -- generators cost nothing, so `insufficientPower` is never true for them — they stay clean
    -- while the spenders wear the badge, which is the whole point of the cue.
    { id = "blade_dance", ability = "blade_dance",
      markers = {
        { id = "blade_dance_starved", cue = "starved",
          when = { { "affordable", "blade_dance", negate = true } } },
      } },
    -- Immolation Aura sits ABOVE Chaos Strike, and its rung is set by CHARGES, not by target
    -- count. Three rungs, in the order the APL evaluates them:
    --   10 `a_fire_inside & burning_wound & (charges=2|full_recharge_time<gcd.max*2)` — NO
    --      target term. A banked charge outranks the spenders, and Eye Beam, at any target
    --      count. Row position cannot carry this (it would have to sit above Eye Beam in every
    --      state); the gold `capped` badge does, through pass 1 of the reading model.
    --   20 `active_enemies>1 & (a_fire_inside|burning_wound)` — above Chaos Strike at 2+.
    --      This is what position 7 encodes.
    --   25 the unconditional floor — BELOW Chaos Strike. Position 7 is wrong here, and
    --      `immolation_single_target` is the badge that corrects it.
    { id = "immolation_aura", ability = "immolation_aura",
      markers = {
        -- `isActive` is NeverSecret and answers in both directions, but only ONE direction is
        -- drawn: at max it is the gold `capped` badge (a charge is being lost right now). Below
        -- max draws nothing — the old `immolation_recharging` badge was `capped` negated and so
        -- fired across the whole steady state, against rungs 20 and 25.
        --
        -- Rung 10 is `talent.a_fire_inside & talent.burning_wound & (charges=2|...)`, so BOTH
        -- talents gate the badge. Without them the rung does not exist and the badge is
        -- asserting a rank this build does not have.
        --
        -- ⚠ And rung 10 sits BELOW rungs 3 and 4: with a charge banked and Metamorphosis or The
        -- Hunt ready, the APL presses those. Those two readable terms are what keep a positive
        -- cue — which overrides the elimination scan by design — from pointing past a cooldown
        -- that outranks it. ONE SECRET, MANY READABLE GATES.
        { id = "immolation_capped", cue = "capped",
          when = {
            { "talent", "a_fire_inside" },
            { "talent", "burning_wound" },
            { "ready", "metamorphosis", negate = true },
            { "ready", "the_hunt", negate = true },
            { "capped", "immolation_aura" },
          } },
        -- Rung 25: at ONE target, with no charge banked, Immolation Aura is below Chaos Strike.
        -- The AoE re-weight is deliverable after all, in negative polarity: rather than shouting
        -- that Immolation Aura matters MORE in AoE (a positive cue this vocabulary does not
        -- have), mark it skippable when AoE mode is off. Three terms, ANDed:
        --   `!aoe`      — cap's own toggle. No secret, nothing to measure.
        --   `affordable(chaos_strike)` — the button you would press instead. Starved, you want
        --                the generator, so the skip must clear or the walk over-runs the row.
        --   `ready`     — a badge on a greyed-out recharging icon says nothing: the player was
        --                never going to press it. `Treatment.For` passes cues through for rows
        --                the CDM has already swiped, so this term is what keeps the badge off
        --                one.
        --   no rung-10 charge — see the union below.
        --
        -- ⚠ THREE markers, because that last condition is really `!(capped & a_fire_inside &
        -- burning_wound)` — the exact negation of the gold badge's own rung-10 test — and a
        -- marker's grammar has no OR inside it. Union IS the OR: `!(P & Q & R)` is three
        -- markers, `P & Q & R` is one. That is what makes gold and red provably exclusive on
        -- every build.
        --
        -- ⚠ And a bare `!capped` would not do, for a reason that is easy to get backwards.
        -- `Sense.readCapped` returns nil when `maxCharges <= 1`, so on a build without A Fire
        -- Inside `capped` is **UNKNOWN** — not true — and an unknown withholds. A single
        -- `!capped` marker would therefore be permanently BLIND on a one-charge build and the
        -- skip would never draw. The talent halves are what answer in that state.
        { id = "immolation_single_target", cue = "blocked",
          when = {
            { "aoe", negate = true },
            { "ready", "immolation_aura" },
            { "affordable", "chaos_strike" },
            { "capped", "immolation_aura", negate = true },
          } },
        { id = "immolation_single_target_no_fire", cue = "blocked",
          when = {
            { "aoe", negate = true },
            { "ready", "immolation_aura" },
            { "affordable", "chaos_strike" },
            { "talent", "a_fire_inside", negate = true },
          } },
        { id = "immolation_single_target_no_wound", cue = "blocked",
          when = {
            { "aoe", negate = true },
            { "ready", "immolation_aura" },
            { "affordable", "chaos_strike" },
            { "talent", "burning_wound", negate = true },
          } },
      } },
    { id = "chaos_strike", ability = "chaos_strike",
      markers = {
        { id = "chaos_strike_starved", cue = "starved",
          when = { { "affordable", "chaos_strike", negate = true } } },
      } },
    -- The two generators, which cost nothing and therefore never wear the affordability cue —
    -- their failure mode is the opposite one. cap performs no part of the decision: the client
    -- evaluates an authored curve against the secret Fury and paints the result. The max is the
    -- client's, and is emphatically not hardcoded.
    --
    -- The two break at different points, from different KINDS of number. Felblade's comes
    -- straight off APL rung 22, `felblade,if=hero_tree.felscarred&fury<=100` — an absolute Fury
    -- level, so it is authored as a `threshold` (break at 100/maxFury) and NOT as a generation.
    -- Rung 22 is not an overcap rule at all; it promotes Felblade above Chaos Strike while Fury
    -- is low, and the badge says the negation: above 100, spend before you generate.
    { id = "felblade", ability = "felblade",
      markers = {
        { id = "felblade_overcap", cue = "overcap",
          display = { kind = "sealed-power-percent", power = "Fury", threshold = 100 } },
      } },
    -- Demon's Bite is ABSENT from the 12.1 APL, and that is not evidence against it: the sim's
    -- build takes Demon Blades, which replaces the button with a passive. On a build without it
    -- this is a real button. The entry binds only if the row exists, so it costs nothing.
    { id = "demons_bite", ability = "demons_bite",
      markers = {
        -- Demon's Bite rolls 20–30; the midpoint is the honest authoring of a range cap
        -- cannot read, and the cue is a "close to overflowing" readout, not a guarantee.
        { id = "demons_bite_overcap", cue = "overcap",
          display = { kind = "sealed-power-percent", power = "Fury", generation = 25 } },
      } },
    { id = "fel_rush", ability = "fel_rush",
       },
    { id = "throw_glaive", ability = "throw_glaive",
       },
  },
}
