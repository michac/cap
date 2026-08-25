-- Retribution.lua — the Templar roster. Authored from `specs/retribution/catalog.md`; the
-- reasoning lives there and is deliberately not repeated here, only the parts a reader of this
-- file would otherwise have to take on faith.
--
-- `power = "HolyPower"`: Holy Power is NEVER-SECRET, so unlike Havoc's Fury the `resource`
-- predicate is usable and this is the first catalog where a resource does ordering work.
--
-- ⚠ `hero` is deliberately unset. The Templar sub-tree id has not been read from a live client,
-- and inventing one would silently bind nothing. Unset means "any hero tree", which on Herald of
-- the Sun offers a Templar-authored priority — acceptable while this addon has one Templar user,
-- and the one line to tighten once the id is known.
local ADDON, ns = ...

ns.Catalog.Register{
  spec = 70,
  name = "Retribution / Templar",
  power = "HolyPower",

  abilities = {
    { id = "execution_sentence", spell = 343527 },
    { id = "avenging_wrath", spell = 31884 },
    -- Base id only: Bind unions base/override/tooltip/live, so the Light's Guidance flip to
    -- Hammer of Light (427453) is reached through `identity`, not through a hardcoded id.
    { id = "wake_of_ashes", spell = 255937, alt = { 427453 } },
    { id = "divine_toll", spell = 375576 },
    { id = "templars_verdict", spell = 85256, alt = { 383328 } },
    { id = "divine_storm", spell = 53385 },
    { id = "blade_of_justice", spell = 184575 },
    { id = "judgment", spell = 20271, alt = { 24275 } },
    { id = "crusader_strike", spell = 35395, alt = { 406646 } },

    -- The Expurgation DoT, as a TRACKED-BUFF row rather than a spell row.
    --
    -- ⚠ `383346` is the debuff that LANDS. `383344` is the passive talent node and is the wrong
    -- id — confirmed in client 2026-08-19 by icon (383346 shares Blade of Justice's icon).
    --
    -- ⚠ This binds only if the player has added Expurgation to Tracked Buffs. If they have not,
    -- `Catalog.Resolve` drops it with "no CDM row on this build", `world.aura` never gets a key,
    -- and `aura:expurgation` reads UNKNOWN — so the marker below stays DARK rather than reading
    -- as "the DoT is down". That degradation is the whole reason no enablement check is needed.
    { id = "expurgation", spell = 383346, family = "auras", unit = "target" },
  },

  -- Node + entry from `knowledge/classes/paladin/retribution/ability-inventory.tsv`.
  talents = {
    { id = "holy_flames", node = 109371, entry = 115438, spell = 406545 },
    { id = "radiant_glory", node = 81549, entry = 102525, spell = 458359 },
  },

  -- Entry order IS the authored priority; `Catalog.OrderCheck` reports when the player's
  -- Cooldown Manager disagrees with it.
  entries = {
    -- 1. A PLACED cooldown, not a press-on-cooldown one. Three markers, one cue key, so the
    -- AND-only band grammar unions them into a single badge — and that union IS the OR.
    { id = "execution_sentence", ability = "execution_sentence",
      markers = {
        -- Avenging Wrath READY. Not redundant with the band below, which reads nothing at zero
        -- remaining: this row sits LEFT of Avenging Wrath, so a quiet row 1 is pressed before
        -- the eye ever arrives there.
        { id = "es_awaits_wrath_ready", cue = "blocked",
          when = { { "ready", "execution_sentence" }, { "talent", "radiant_glory", negate = true },
                   { "ready", "avenging_wrath" } } },
        { id = "es_awaits_wrath", cue = "blocked",
          when = { { "ready", "execution_sentence" }, { "talent", "radiant_glory", negate = true } },
          display = { kind = "sealed-cooldown-range", ability = "avenging_wrath", within = 15 } },
        -- The `beyond` sense: "it is nowhere near, so this is not its moment." Authored at the
        -- UNHASTED 1.5 because `UnitSpellHaste` is sealed in instanced combat.
        { id = "es_awaits_wake", cue = "blocked",
          when = { { "ready", "execution_sentence" } },
          display = { kind = "sealed-cooldown-range", ability = "wake_of_ashes", beyond = 1.5 } },
      } },

    -- 2. The window everything aligns into — and on a Holy Flames build it is FORBIDDEN, not
    -- merely outranked, until Expurgation is on the target. Its line's only non-simulation term
    -- is `(!talent.holy_flames|dot.expurgation.ticking)`.
    --
    -- The `talent` gate is what makes this safe in the other direction: without Holy Flames the
    -- APL term is vacuously true, and this marker must not exist at all.
    { id = "avenging_wrath", ability = "avenging_wrath",
      markers = {
        { id = "aw_awaits_expurgation", cue = "blocked",
          when = { { "ready", "avenging_wrath" }, { "talent", "holy_flames" },
                   { "aura", "expurgation", negate = true } } },
      } },

    -- 3. One row, two lives, selected by identity: a cooldown while it is Wake of Ashes, a
    -- spender while Light's Guidance has made it Hammer of Light. Membership is the OR of the
    -- scan_when alternatives, so either life keeps the row in the scan.
    { id = "wake_of_ashes", ability = "wake_of_ashes",
      -- Real conditional membership, the rare case: as base Wake of Ashes the row is in the
      -- scan only when ready; as Hammer of Light (transformed) it is in the scan by identity —
      -- the granted press has no cooldown of its own to read.
      scan_when = {
        { { "identity", "wake_of_ashes", "base" }, { "ready", "wake_of_ashes" } },
        { { "identity", "wake_of_ashes", "transformed" } },
      },
      markers = {
        -- Affordability of the LIVE id: Hammer of Light's 5 Holy Power on the transformed row,
        -- Wake of Ashes's nothing on the base one. One marker covers both lives correctly.
        { id = "woa_starved", cue = "starved",
          when = { { "affordable", "wake_of_ashes", negate = true } } },
        { id = "woa_awaits_wrath", cue = "blocked",
          when = { { "identity", "wake_of_ashes", "base" }, { "ready", "wake_of_ashes" },
                   { "talent", "radiant_glory", negate = true } },
          display = { kind = "sealed-cooldown-range", ability = "avenging_wrath", within = 6 } },
        { id = "woa_awaits_sentence", cue = "blocked",
          when = { { "identity", "wake_of_ashes", "base" }, { "ready", "wake_of_ashes" } },
          display = { kind = "sealed-cooldown-range", ability = "execution_sentence", within = 4 } },
      } },

    -- 4. The one builder that genuinely must not be pressed at cap.
    { id = "divine_toll", ability = "divine_toll",
      markers = {
        { id = "dt_awaits_wrath", cue = "blocked",
          when = { { "ready", "divine_toll" }, { "talent", "radiant_glory", negate = true } },
          display = { kind = "sealed-cooldown-range", ability = "avenging_wrath", within = 15 } },
        -- Readable, not a curve on a secret: Holy Power is never-secret, and this is the whole
        -- difference from Havoc's authored Fury break point.
        { id = "dt_overcap", cue = "overcap",
          when = { { "ready", "divine_toll" }, { "resource", ">=", 5 } } },
      } },

    -- 5. The default spender, and the wrong one in three states that look identical on the icon.
    { id = "templars_verdict", ability = "templars_verdict",
      scan_when = { { { "affordable", "templars_verdict" } } },
      markers = {
        { id = "tv_starved", cue = "starved",
          when = { { "affordable", "templars_verdict", negate = true } } },
        -- Cue D. Generators 5 outranks the unconditional `finishers` call, so a free Blade of
        -- Justice is pressed first — EXCEPT at 5 Holy Power, which is what `resource <= 4` is
        -- for. The `affordable` term keeps this off a row already wearing `starved`.
        { id = "tv_awaits_blade", cue = "blocked",
          when = { { "proc", "blade_of_justice" }, { "ready", "blade_of_justice" },
                   { "resource", "<=", 4 }, { "affordable", "templars_verdict" } } },
        -- Cue E, twice, unioned onto one badge — the APL's `ds_castable` read as a skip. cap has
        -- no enemy count and will not compute one, so the target-count clause is the player's
        -- `/cap aoe` toggle. `!proc(templars_verdict)` is `!buff.empyrean_legacy.up`.
        --
        -- ⚠ The two markers carry DIFFERENT keys, and until 2026-08-19 they shared `blocked`.
        -- They are not the same statement:
        --   · the AoE one is a MODE fact -- nothing is held, nothing is wasted, it is simply the
        --     other spender's turn. `st_only`.
        --   · the Empyrean Power one fires in SINGLE TARGET, where the mode is right and the
        --     reason is a free Divine Storm waiting. That is exactly `blocked`'s declared meaning,
        --     "a readable dependency says the press would be wasted", and calling it `st_only`
        --     would tell the player their mode was wrong when it was not.
        { id = "tv_divine_storm_aoe", cue = "st_only",
          when = { { "aoe" }, { "proc", "templars_verdict", negate = true },
                   { "affordable", "templars_verdict" } } },
        { id = "tv_empyrean_power", cue = "blocked",
          when = { { "proc", "divine_storm" }, { "proc", "templars_verdict", negate = true },
                   { "affordable", "templars_verdict" } } },
      } },

    -- 6. Needs no mirror of cue E: it sits RIGHT of Templar's Verdict, so in single target
    -- elimination reaches that row first and never has to be told to.
    { id = "divine_storm", ability = "divine_storm",
      scan_when = { { { "affordable", "divine_storm" } } },
      markers = {
        { id = "ds_starved", cue = "starved",
          when = { { "affordable", "divine_storm", negate = true } } },
        -- The MIRROR of cue E, and it is not there to steer the scan: this row sits RIGHT of
        -- Templar's Verdict, so in single target elimination reaches that one first and stops.
        -- It is there so a reader can tell the two spenders APART -- without it, "why is this one
        -- not the answer?" is answerable only from row position, which is the knowledge a player
        -- new to a spec has least of.
        --
        -- Gated OFF by an Empyrean Power proc: that proc makes Divine Storm free and it beats the
        -- single-target spender at ANY target count (RET-9), so it is emphatically not "AoE only"
        -- in that state. Gated on `affordable` so it never lands on a row already wearing
        -- `starved`, which would be two badges saying nothing extra.
        { id = "ds_aoe_only", cue = "aoe_only",
          when = { { "aoe", negate = true }, { "proc", "divine_storm", negate = true },
                   { "affordable", "divine_storm" } } },
        -- Not optional: badging only Templar's Verdict would hand the walk to this row.
        { id = "ds_awaits_blade", cue = "blocked",
          when = { { "proc", "blade_of_justice" }, { "ready", "blade_of_justice" },
                   { "resource", "<=", 4 }, { "affordable", "divine_storm" } } },
      } },

    -- 7. ONE cue, and it is the vocabulary's second positive.
    --
    -- In the steady state this row is reached by ELIMINATION and wears nothing — its ordering
    -- story is told by the markers it causes on the rows above it, and Blizzard already glows it
    -- on an Art of War / Righteous Cause proc. The opener is the exception, and the reason is
    -- DENSITY rather than rank: `generators` 2 puts Blade of Justice first on a Holy Flames
    -- build, and saying that by elimination would mean holding FOUR rows above it
    -- (render-shelf.md Part 0.5, the density rule). Two of those holds existed for no other
    -- reason and were deleted when this marker was authored.
    --
    -- The condition IS the APL rung, minus `time<5`: the aura latch subsumes it, because the only
    -- moment Expurgation is absent on a Holy Flames build is before the first Blade of Justice.
    { id = "blade_of_justice", ability = "blade_of_justice",
      markers = {
        { id = "boj_opener", cue = "priority",
          when = { { "ready", "blade_of_justice" }, { "talent", "holy_flames" },
                   { "aura", "expurgation", negate = true } } },
      } },

    -- 8. Hammer of Wrath's execute condition needs no vocabulary: the row IS Hammer of Wrath
    -- exactly when Hammer of Wrath is castable.
    { id = "judgment", ability = "judgment",
       },

    -- 9. Binds only if the row exists. On a Crusading Strikes build the talent replaces the
    -- button with an auto-attack, so the priority genuinely ends at Judgment and this costs
    -- nothing.
    { id = "crusader_strike", ability = "crusader_strike",
       },
  },
}
