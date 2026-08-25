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
    -- ⚠ The armed Art that transforms row 9 into Infernal Bolt. The id is TIER-3-SOURCED
    -- (maxroll's capture: Demonic Art: Mother of Chaos 432794) and a wrong aura id dies
    -- SILENT — the slot matches nothing forever, indistinguishable from a refusal (the
    -- cast-id/aura-id trap, KB §3.5.2). Flight question; @verify-ingame on the id.
    { id = "art_mother_of_chaos", spell = 432794, family = "auras" },
  },

  -- Node + entry from `knowledge/classes/warlock/demonology/talents.json` @ 12.1. This is what
  -- `talent.to_hell_and_back` and `talent.doom` in the APL mean, read as themselves rather than
  -- through a proxy (Talents.lua explains why `IsSpellKnown` and charge counts are both refused).
  talents = {
    { id = "to_hell_and_back", node = 110199, entry = 136728, spell = 1281511 },
    { id = "doom", node = 110200, entry = 136729, spell = 460551 },
    { id = "reign_of_tyranny", node = 110201, entry = 136730, spell = 1276748 },
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
    --
    -- ⚠ Cue I is authored PAST the APL — rungs 3/4 are unconditional. The pilot's ramp reading
    -- (catalog.md changelog 2026-08-24): the whole summon block holds while Tyrant is READY and
    -- the board is below five shards. Playtest-gated.
    { id = "grimoire", ability = "grimoire",
      markers = {
        { id = "grimoire_awaits_shards", cue = "building",
          when = { { "ready", "summon_demonic_tyrant" }, { "resource", "<=", 4 } } },
      } },
    -- 3 · Summon Doomguard. Midnight-new. Cue I is uniformity with the block, not played
    -- experience — the least-tested marker here (catalog.md, 2026-08-24).
    { id = "summon_doomguard", ability = "summon_doomguard",
      markers = {
        { id = "doomguard_awaits_shards", cue = "building",
          when = { { "ready", "summon_demonic_tyrant" }, { "resource", "<=", 4 } } },
      } },
    -- 4 · Call Dreadstalkers. Cue I is the block's shared readable hold; cue J is the
    -- TWO-SIDED sealed band that used to be defeat 1 — hold while Tyrant's remaining is inside
    -- (10.5, 21.5), rung 6's own dead zone at S4's unhasted 1.5 s floor, Reign-gated. Closed
    -- 2026-08-24 by `Channel.BandPoints`; unflown.
    { id = "call_dreadstalkers", ability = "call_dreadstalkers",
      markers = {
        { id = "dreadstalkers_awaits_shards", cue = "building",
          when = { { "ready", "summon_demonic_tyrant" }, { "resource", "<=", 4 } } },
        { id = "dreadstalkers_awaits_tyrant", cue = "blocked",
          when = { { "talent", "reign_of_tyranny" } },
          display = { kind = "sealed-cooldown-range",
                      ability = "summon_demonic_tyrant",
                      beyond = 10.5, within = 21.5 } },
      } },
    -- 5 · Summon Demonic Tyrant. The single biggest decision in the spec, and it is READABLE:
    -- rung 8 is `soul_shard=5`, read as a hold. Gated on readiness because a hold badge on a
    -- greyed icon says nothing.
    { id = "summon_demonic_tyrant", ability = "summon_demonic_tyrant",
      markers = {
        -- Re-badged `blocked` → `building` 2026-08-24: the block's holds and Tyrant's own are
        -- one statement — build shards — and now wear one glyph.
        { id = "tyrant_awaits_shards", cue = "building",
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
          bands = {
            -- The NUMERAL, not the mark: `how many more` is exactly the live question below
            -- six, and the hatch beside it already carries `ruled out`. A mark here would say
            -- the hatch's thing twice and the count's thing not at all.
            { threshold = 0, draw = "count", polarity = "negative", hatch = true },
            -- At six the count RECOLORS instead of clearing (2026-08-25, stepper feedback):
            -- the red half says "this many more needed", the gold half says "banked — the
            -- Implosion is loaded". Same numeral, opposite polarity, no hatch — hue carries
            -- polarity and only polarity (V5.1), and a positive band may not hatch.
            { threshold = 6, draw = "count", polarity = "positive" },
          },
        } },
      } },
    -- 7 · Hand of Gul'dan / Ruination. Two lives, one lane: both are shard spenders. The
    -- identity carries the transform with no cue, because Ruination outranks the ordinary press
    -- by one rung and both are pressed from this position.
    { id = "hand_of_guldan", ability = "hand_of_guldan",
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
        -- The READABLE half of the same window rule (cue I): Tyrant READY at sub-five shards
        -- holds the spend — rung 11's `remains>5` is false at zero remaining. Cue F covers
        -- "nearly here"; this covers "here, board not built".
        { id = "hog_awaits_shards", cue = "building",
          when = { { "ready", "summon_demonic_tyrant" }, { "resource", "<=", 4 },
                   { "affordable", "hand_of_guldan" } } },
      } },
    -- 8 · Demonbolt. The pilot's row, and the pilot had the number wrong: the APL says
    -- `soul_shard<4`, so the overcap badge lights at FOUR and not at three.
    { id = "demonbolt", ability = "demonbolt",
      markers = {
        -- Demonbolt appears in `actions.diabolist` ONLY gated on `buff.demonic_core.react`, so
        -- with no Core there is no rung at all. This is also V11's hatch at zero Cores — the one
        -- state a sealed display can never decorate, because with no aura there is no button,
        -- and it needs no new vocabulary: a negative cue already hatches the row.
        -- Re-badged `blocked` → `noproc` 2026-08-24: "no Core" is not "wait for a clock" —
        -- the empty card says the press belongs elsewhere until the proc returns.
        { id = "db_awaits_core", cue = "noproc",
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
        -- V19 · Doom's pandemic window, on the button that applies it. cap authors NO threshold:
        -- the client computes `GetRefreshExtendedDuration - GetAuraBaseDuration` per spell.
        --
        -- ⚠ GATED on the talent, and this is the readable-gate seam: without Doom talented the
        -- fact does not exist, and a display armed for it would sit dark forever with no way to
        -- tell that from a client refusal.
        { id = "db_doom_window", when = { { "talent", "doom" } },
          display = { kind = "sealed-pandemic", ability = "doom" } },
        -- V20 · the Core's remaining lifetime as a thin bar directly above the charge bar
        -- (2026-08-25, re-formed off the one-day corner dial: gold in the badge column read as
        -- a verdict beside the red holds; the edge carries quantity, not polarity). "This many
        -- banked, this long to use one." No threshold anywhere.
        { id = "db_core_clock", display = {
          kind = "sealed-proc-bar", ability = "demonic_core",
        } },
      } },
    -- 9 · Shadow Bolt / Infernal Bolt. Default membership (ready-self): a filler is always a
    -- scan candidate, and the old two-band tier flip both yielded membership, so the tier
    -- carried no membership information. "The row changed KIND" is said by cue D and the icon
    -- itself; the ordering correction lives on Demonbolt, which is the row that has to move.
    { id = "shadow_bolt", ability = "shadow_bolt",
      markers = {
        -- V20 · how long the armed Art (and so the Infernal Bolt on this row) has left,
        -- drained by the client. The slot filters to the ART aura, so the bar exists exactly
        -- while the transform does — no identity gate needed, the visibility IS the gate.
        -- ⚠ The aura id is Tier-3-sourced and unflown; see the abilities table.
        { id = "ib_art_clock", display = {
          kind = "sealed-proc-bar", ability = "art_mother_of_chaos",
        } },
      } },
  },
}
