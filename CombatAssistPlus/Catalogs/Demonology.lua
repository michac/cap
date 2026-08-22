-- Demonology.lua — the Diabolist roster. Soul Harvester (hero 60) is a separate catalog and
-- correctly gets nothing. Gameplay choices are provisional characterizations to fly.
--
-- The definition this transcribes is `specs/demonology/catalog.md`; the walk that proves it is
-- `scenarios.md` beside it, and the readable/sealed safety case is `fact-classification.md`.
-- Nothing here restates a rung, a source or a pixel.
--
-- `power = "SoulShards"` because Soul Shards are one of the seven NEVER-SECRET power types, so
-- the largest decision in the spec — do I have five shards for Tyrant — is an exact Lua
-- comparison rather than a curve. Base spell ids only: Bind unions base/override/tooltip/live
-- into the row, so neither transform needs a hardcoded override id.
local ADDON, ns = ...

ns.Catalog.Register{
  spec = 266,
  hero = 59,
  name = "Demonology / Diabolist",
  power = "SoulShards",

  abilities = {
    { id = "power_siphon", spell = 264130 },
    { id = "grimoire", spell = 1276452, alt = { 1276467 } },
    { id = "summon_doomguard", spell = 1276672 },
    { id = "call_dreadstalkers", spell = 104316 },
    { id = "summon_demonic_tyrant", spell = 265187 },
    { id = "implosion", spell = 196277 },
    { id = "hand_of_guldan", spell = 105174 },
    { id = "demonbolt", spell = 264178 },
    { id = "shadow_bolt", spell = 686 },
    -- Aura dependencies only: these are not enhanced CDM entries and never enter Signal. They
    -- exist so a sealed display can name a subject — the count or the clock the CLIENT reads.
    -- cap never learns any of their values.
    { id = "demonic_core", spell = 264173, family = "auras" },
    { id = "wild_imp", spell = 296553, family = "auras" },
    -- Doom is a DEBUFF cap puts on the target, which is why it carries a unit. Its refresh
    -- window is the client's own arithmetic, per spell (V19).
    { id = "doom", spell = 460553, family = "auras", unit = "target" },
  },

  -- Node + entry from `knowledge/classes/warlock/demonology/talents.json` @ 12.1. This is what
  -- `talent.to_hell_and_back` and `talent.doom` in the APL mean, read as themselves rather than
  -- through a proxy (Talents.lua explains why `IsSpellKnown` and charge counts are both refused).
  talents = {
    { id = "to_hell_and_back", node = 110199, entry = 136728, spell = 1281511 },
    { id = "doom", node = 110200, entry = 136729, spell = 460551 },
  },

  -- Entry order IS the authored priority, and it is the flattened `actions.diabolist` with one
  -- swap. `Catalog.OrderCheck` compares it against Blizzard's `layoutIndex`, which stopped being
  -- the drawn order when Anchor shipped — so read its verdict as "the saved layout disagrees",
  -- never as "the row on screen disagrees".
  entries = {
    -- 1 · Power Siphon. Its rung gate is `buff.demonic_core.stack<=1`, which is a SEALED count —
    -- so the row carries no readable cue at all and the display does the whole of the work.
    -- Below two Cores the band draws nothing and the row is an ordinary candidate; at two it
    -- hatches and marks itself, which is the row RULED OUT by a fact cap never read.
    --
    -- ⚠ This is what closes `catalog.md`'s second defeat. It was written as a row elimination
    -- could not rule out, because cap's only count form painted a number and could not badge or
    -- invert. V16/V17 are both.
    { id = "power_siphon", ability = "power_siphon",
      bands = { { tier = "COOLDOWN", when = { { "ready", "power_siphon" } } } },
      markers = {
        { id = "ps_cores_banked", display = {
          kind = "sealed-count-bands", ability = "demonic_core",
          bands = {
            { threshold = 0, draw = "none" },
            { threshold = 2, draw = "mark", polarity = "negative", hatch = true },
          },
        } },
      } },
    -- 2 · Grimoire. A CHOICE NODE, not a transform: both ids have their own Essential row and
    -- exactly one exists on a build, so the second goes in `alt` rather than through R7.
    { id = "grimoire", ability = "grimoire",
      bands = { { tier = "COOLDOWN", when = { { "ready", "grimoire" } } } } },
    -- 3 · Summon Doomguard. Midnight-new, which is a reason to DRAW it and not to badge it.
    { id = "summon_doomguard", ability = "summon_doomguard",
      bands = { { tier = "COOLDOWN", when = { { "ready", "summon_doomguard" } } } } },
    -- 4 · Call Dreadstalkers. No cue: the Reign-of-Tyranny window is a TWO-SIDED sealed band and
    -- `sealed-cooldown-range` takes exactly one of `within` and `beyond`. Either half alone is a
    -- WRONG hold, so nothing is drawn. `catalog.md` defeat 1 owns the reopening condition.
    { id = "call_dreadstalkers", ability = "call_dreadstalkers",
      bands = { { tier = "COOLDOWN", when = { { "ready", "call_dreadstalkers" } } } } },
    -- 5 · Summon Demonic Tyrant. The single biggest decision in the spec, and it is READABLE:
    -- rung 8 is `soul_shard=5`, read as a hold. Gated on readiness because a hold badge on a
    -- greyed icon says nothing.
    { id = "summon_demonic_tyrant", ability = "summon_demonic_tyrant",
      bands = { { tier = "COOLDOWN", when = { { "ready", "summon_demonic_tyrant" } } } },
      markers = {
        { id = "tyrant_awaits_shards", cue = "blocked",
          when = { { "ready", "summon_demonic_tyrant" }, { "resource", "<=", 4 } } },
      } },
    -- 6 · Implosion. Two halves of one rung, and they split exactly on the readable/sealed line:
    -- `active_enemies>2|talent.to_hell_and_back` is readable and is the cue; `wild_imps.stack>=6`
    -- is sealed and is the display.
    --
    -- ⚠ The display is V17's COMPLEMENT — it draws BELOW the threshold and clears at it — and it
    -- is the first time a sealed fact enters elimination rather than merely being displayed. It
    -- is truthful here and would not be on a rising count generally: below six imps Implosion is
    -- literally a damage loss, which is `implosion,if=buff.wild_imps.stack>=6`.
    { id = "implosion", ability = "implosion",
      bands = { { tier = "ROTATION", when = { { "ready", "implosion" } } } },
      markers = {
        { id = "implosion_st_only", cue = "aoe_only",
          when = { { "aoe", negate = true }, { "talent", "to_hell_and_back", negate = true } } },
        -- ⚠ THE ONE STATE THE BAND BELOW CANNOT REACH, and it needs cap's own readable latch.
        -- With no Wild Imp at all there is no aura, so the client hides the whole button and
        -- every sink on it draws nothing — which would leave a ready Implosion un-ruled-out at
        -- zero imps, the worst possible place for the walk to stop. The `aura` predicate is
        -- readable (a Category-2 row's alert edges), and an unbound row reads UNKNOWN rather
        -- than false, so this stays dark rather than asserting the imps are gone.
        { id = "implosion_no_imps", cue = "blocked",
          when = { { "aura", "wild_imp", negate = true } } },
        { id = "implosion_imps_short", display = {
          kind = "sealed-count-bands", ability = "wild_imp",
          -- ⚠ FLIGHT CONFIGURATION 2026-08-22, deliberately narrowed to ONE variable. The
          -- declared style (render-shelf.md V16/V17) is `count+mark` here; this draws the HATCH
          -- ALONE so its geometry can be judged without a badge and a numeral moving beside it.
          -- Four separate constraints were measured on the multi-escape route in one flight —
          -- no draw-time tint, advance width, no tiling, baseline anchoring — and tuning three
          -- marks at once converges on nothing. Part 7's `band_budget` holds the candidate
          -- resolutions; NONE is adopted, and this is not one of them.
          bands = {
            { threshold = 0, draw = "none", polarity = "negative", hatch = true },
            { threshold = 6, draw = "none" },
          },
        } },
      } },
    -- 7 · Hand of Gul'dan / Ruination. Two lives, one lane: both are shard spenders. The
    -- identity carries the transform with no cue, because Ruination outranks the ordinary press
    -- by one rung and both are pressed from this position.
    { id = "hand_of_guldan", ability = "hand_of_guldan",
      bands = { { tier = "ROTATION", when = { { "ready", "hand_of_guldan" } } } },
      markers = {
        -- `Sense.buildReads` asks affordability of the LIVE id, so this is Ruination's cost —
        -- which is none — on the transformed row and three shards on the base one. One marker,
        -- both lives, correct in each.
        { id = "hog_starved", cue = "starved",
          when = { { "affordable", "hand_of_guldan", negate = true } } },
        -- The catalog's only sealed band, and the mirror of the Tyrant hold: Tyrant holds ITSELF
        -- below five shards (readable); Hand of Gul'dan holds itself while Tyrant is nearly here
        -- (sealed). Gated on `resource <= 4` because rung 11's `|soul_shard=5` makes the spend
        -- unconditional at cap, and on affordability so it never lands on a starved row.
        { id = "hog_awaits_tyrant", cue = "blocked",
          when = { { "resource", "<=", 4 }, { "affordable", "hand_of_guldan" } },
          display = { kind = "sealed-cooldown-range",
                      ability = "summon_demonic_tyrant", within = 5 } },
      } },
    -- 8 · Demonbolt. The pilot's row, and the pilot had the number wrong: the APL says
    -- `soul_shard<4`, so the overcap badge lights at FOUR and not at three.
    { id = "demonbolt", ability = "demonbolt",
      bands = { { tier = "ROTATION", when = { { "ready", "demonbolt" } } } },
      markers = {
        -- Demonbolt appears in `actions.diabolist` ONLY gated on `buff.demonic_core.react`, so
        -- with no Core there is no rung at all. This is also V11's hatch at zero Cores — the one
        -- state a sealed display can never decorate, because with no aura there is no button,
        -- and it needs no new vocabulary: a negative cue already hatches the row.
        { id = "db_awaits_core", cue = "blocked",
          when = { { "proc", "demonbolt", negate = true } } },
        { id = "db_overcap", cue = "overcap",
          when = { { "proc", "demonbolt" }, { "resource", ">=", 4 } } },
        -- The first marker in any catalog that reads ANOTHER ROW'S identity. Rung 12 puts an
        -- armed Infernal Bolt above Demonbolt, and only below three shards.
        { id = "db_yields_to_infernal_bolt", cue = "blocked",
          when = { { "identity", "shadow_bolt", "transformed" }, { "resource", "<=", 2 } } },
        -- V18 · how many Cores, as a shape. `max = 4` is the number that MATTERS rather than the
        -- aura's real cap: SetValue clamps, so four and above reads FULL and the fired state is
        -- always the complete arc.
        { id = "db_core_charge", display = {
          kind = "sealed-count-bar", ability = "demonic_core", max = 4, full = true,
        } },
        -- V19 · Doom's refresh window, on the button that applies it. cap authors NO threshold:
        -- the client computes `GetRefreshExtendedDuration - GetAuraBaseDuration` per spell.
        --
        -- ⚠ GATED on the talent, and this is the readable-gate seam: without Doom talented the
        -- fact does not exist, and a display armed for it would sit dark forever with no way to
        -- tell that from a client refusal.
        { id = "db_doom_window", when = { { "talent", "doom" } },
          display = { kind = "sealed-refresh-window", ability = "doom" } },
      } },
    -- 9 · Shadow Bolt / Infernal Bolt. TWO BANDS, identity first, because the first band whose
    -- condition holds wins: while row 9 is displaying Infernal Bolt it is the best builder in
    -- the rotation, not the filler.
    --
    -- ⚠ Band 1 is not load-bearing for visibility — Shadow Bolt has no cooldown, so `ready`
    -- never goes false and the row draws under either band. It exists to say the row has changed
    -- KIND. The ordering correction lives on Demonbolt, which is the row that has to move.
    { id = "shadow_bolt", ability = "shadow_bolt",
      bands = {
        { tier = "ROTATION", when = { { "identity", "shadow_bolt", "transformed" } } },
        { tier = "FALLBACK", when = { { "ready", "shadow_bolt" } } },
      } },
  },
}
