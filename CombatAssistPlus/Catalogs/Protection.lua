-- Protection.lua — the Lightsmith roster. Templar is a separate catalog authored later, not a
-- second overlay bolted on here, and it correctly gets nothing now. Gameplay choices are
-- provisional characterizations to fly.
--
-- The definition this transcribes is `specs/protection/catalog.md`; the walk that proves it is
-- `scenarios.md` beside it, and the readable/sealed safety case is `fact-classification.md`.
-- Nothing here restates a rung, a source or a pixel.
--
-- ⚠ `hero` is deliberately unset. The Paladin hero sub-tree ids have not been read from a live
-- client, and inventing one would silently bind nothing. Unset means "any hero tree" through
-- `Catalog.ForBuild`'s loose path — and unlike Retribution, whose roster was spec-wide, THIS
-- roster is Lightsmith-specific: a Templar Protection Paladin gets a catalog built around an
-- armament row their build does not have (rung 4's identity, cues D and E's neighbours). That
-- is real exposure, not a formality. Reading the Lightsmith sub-tree id is an OPEN fact and the
-- one line to tighten once it is known.
--
-- ⚠ NO `power` field, and that is measured rather than omitted. The 12.1 Protection priority
-- list carries no `holy_power` term of any kind, so there is no `resource` condition to author
-- and nothing for `overcap` to read. Holy Power is never-secret and goes unread here anyway —
-- the spender is placed by POSITION. "Paladin ⇒ declare HolyPower" is exactly the inference the
-- second Paladin catalog invites and it is wrong.
--
-- ⚠ NO row declares `charged`, and four of them would want to. `charged` is a static
-- declaration with no talent-conditional form, and this repo carries no Tier-1 charge count for
-- Holy Armaments, Shield of the Righteous or Crusader Strike; Judgment's second charge is
-- talent-conditional. Declaring one would invent the number the flag needs. The consequence is
-- that `capped` has no subject anywhere in this catalog.
--
-- Base spell ids only: Bind unions base/override/tooltip/live into the row, so neither the
-- Sacred Weapon nor the Hammer of Wrath transform needs a hardcoded override id.
local ADDON, ns = ...

ns.Catalog.Register{
  spec = 66,
  name = "Protection / Lightsmith",

  abilities = {
    { id = "avenging_wrath", spell = 31884 },
    { id = "divine_toll", spell = 375576 },
    { id = "shield_of_the_righteous", spell = 53600 },
    -- Holy Bulwark's row. Sacred Weapon `432472` has ZERO CooldownSetSpell rows anywhere in the
    -- game data, so the only route by which the Cooldown Manager can show it is an override on
    -- this row — which is what the APL's `next_armament` is, read for free through `identity`.
    { id = "holy_armaments", spell = 432459 },
    { id = "avengers_shield", spell = 31935 },
    -- `26573`, not the inventory's `81297`, which has no CooldownSetSpell row anywhere.
    { id = "consecration", spell = 26573 },
    -- `275779`, not `20271` — that id is Retribution's set 901. Hammer of Wrath `24275` rides
    -- this row as a transform and is reached through `identity`.
    { id = "judgment", spell = 275779 },
    -- A CHOICE NODE, not a transform: Hammer of the Righteous and Blessed Hammer are the spec
    -- node at 3,19, exactly one exists on a build, and both reach the Cooldown Manager on
    -- Crusader Strike's row. So the second and third ids go in `alt` rather than through R7.
    { id = "crusader_strike", spell = 35395, alt = { 53595, 204019 } },
    { id = "word_of_glory", spell = 85673 },

    -- Aura dependencies only: these are not enhanced CDM entries and never enter Signal. They
    -- exist so a marker can name a boolean or a sealed display can name a subject. Each is a
    -- Category-2 (TrackedBuff) row in set 637, which is the `aura` latch's home ground.
    { id = "vanguard", spell = 1267203, family = "auras" },
    { id = "blessed_assurance", spell = 433015, family = "auras" },
    { id = "divine_guidance", spell = 433106, family = "auras" },
    { id = "shining_light", spell = 321136, family = "auras" },
  },

  -- Node + entry from `knowledge/classes/paladin/protection/ability-inventory.tsv` @ 12.1.
  --
  -- ⚠ `divine_guidance` and `blessed_assurance` SHARE node 95235, and that is the fact rather
  -- than a typo: they are the Lightsmith choice node at 8,11, so exactly one of them exists on
  -- any build and the other is dead. Two markers below are gated on it in opposite directions.
  --
  -- ⚠ The key `divine_guidance` appears in BOTH families and that is legal — `Catalog.Check`
  -- keys `abilities` and `talents` in separate tables and the `talent` predicate resolves only
  -- the second. The aura is the stacking buff; the talent is whether the buff can exist at all.
  talents = {
    { id = "righteous_protector", node = 81477, entry = 102440, spell = 204074 },
    { id = "divine_guidance", node = 95235, entry = 117884, spell = 433106 },
    { id = "blessed_assurance", node = 95235, entry = 117883, spell = 433015 },
  },

  -- Entry order IS the authored priority, and it is the flattened `actions.default` — one list,
  -- no sub-lists and no hero fork, with four rows whose rungs straddle another row's.
  -- `Catalog.OrderCheck` reports when the player's Cooldown Manager disagrees with it.
  entries = {
    -- 1 · Avenging Wrath (rung 5). A PLACED cooldown: its value is set by what lands inside it,
    -- and Divine Toll's clock is the whole of that. Sealed, so the hold is a band.
    --
    -- ⚠ The sense is `beyond` and getting it backwards would invert the button. Rung 5 FIRES at
    -- `cooldown.divine_toll.remains<=10`, so the HOLD is the complement: Divine Toll has at
    -- least ten seconds left, i.e. "it is nowhere near, so this is not its moment." The band
    -- also reads nothing at zero remaining, which is correct here — a READY Divine Toll
    -- satisfies `remains<=10` and must not hold anything.
    { id = "avenging_wrath", ability = "avenging_wrath",
      bands = { { tier = "COOLDOWN", when = { { "ready", "avenging_wrath" } } } },
      markers = {
        { id = "aw_awaits_toll", cue = "blocked",
          when = { { "ready", "avenging_wrath" } },
          display = { kind = "sealed-cooldown-range", ability = "divine_toll", beyond = 10 } },
      } },

    -- 2 · Divine Toll (rung 7). The spec's largest Holy Power injection, and it belongs inside
    -- Wings.
    --
    -- ⚠ The rung has two disjuncts and only the second is authorable. The first is
    -- `buff.avenging_wrath.up`, and Avenging Wrath's buff lives on a Category-3 (TrackedBar) row
    -- in set 637 — whether a TrackedBar row raises the `aura` latch's alert edges is UNMEASURED,
    -- and a latch on an unmeasured edge is a hold that may never release. Not authored.
    --
    -- ⚠ So the whole of this cue is `!talent.righteous_protector.enabled &
    -- cooldown.avenging_wrath.remains>30`, and the talent gate is what keeps it honest.
    -- `within = 30` is the complement of `remains>30` and is correct across the entire 120 s
    -- cooldown WITHOUT Righteous Protector. Righteous Protector halves that cooldown, which both
    -- deletes the disjunct from the priority and would leave a 30 s band covering half a 60 s
    -- cycle — a rule the priority does not contain. It is near-mandatory, so this cue is
    -- withheld on the build almost everyone plays and Divine Toll wears nothing there. Stated as
    -- a hole rather than papered over with an approximation.
    { id = "divine_toll", ability = "divine_toll",
      bands = { { tier = "COOLDOWN", when = { { "ready", "divine_toll" } } } },
      markers = {
        { id = "dt_awaits_wrath", cue = "blocked",
          when = { { "ready", "divine_toll" },
                   { "talent", "righteous_protector", negate = true } },
          display = { kind = "sealed-cooldown-range", ability = "avenging_wrath", within = 30 } },
      } },

    -- 3 · Shield of the Righteous (rung 9). The spender and the active mitigation, shown
    -- castable when you cannot pay for it, and off the global — so it is the button pressed out
    -- of habit at the wrong Holy Power.
    --
    -- ⚠ Rung 9 is UNCONDITIONAL on Lightsmith, by derivation rather than by reading: every term
    -- in its condition is Templar's (Hammer of Light, Undisputed Ruling), so with no Hammer of
    -- Light on the build the first disjunct is trivially true. The row needs no press gate at
    -- all, which is why the spender's placement is pure position.
    --
    -- ⚠ R1's warning applies exactly: a spender whose cost is the only thing between it and a
    -- press raises no readiness edge for that cost, so Blizzard's border cannot say this.
    { id = "shield_of_the_righteous", ability = "shield_of_the_righteous",
      bands = { { tier = "ROTATION",
                  when = { { "affordable", "shield_of_the_righteous" } } } },
      markers = {
        { id = "sotr_starved", cue = "starved",
          when = { { "affordable", "shield_of_the_righteous", negate = true } } },
      } },

    -- 4 · Holy Bulwark / Sacred Weapon (rungs 10 / 14, 23). One button, two jobs, and which job
    -- it has right now is written only on the icon's own artwork. As Sacred Weapon it wants
    -- pressing the moment its buff lapses; as Holy Bulwark it wants SAVING until Wings.
    --
    -- ⚠ The identity gate is load-bearing in BOTH directions. Without it the hold would sit on
    -- the Sacred Weapon life, where the correct press is now; with it, the Sacred Weapon life
    -- carries no cue at all, which is a separate and named exposure — rung 10's
    -- `buff.sacred_weapon.remains<6` is an aura-remaining band nobody has written.
    --
    -- ⚠ And the hold is wrong at two charges, which is rung 23. No `charged` is declarable here
    -- (see the header), so the hold keeps drawing where the priority would dump the charge. The
    -- failure direction is a held press and a possibly-wasted charge, which is why it is a named
    -- defeat rather than a footnote.
    { id = "holy_armaments", ability = "holy_armaments",
      bands = { { tier = "COOLDOWN", when = { { "ready", "holy_armaments" } } } },
      markers = {
        { id = "ha_banks_bulwark", cue = "blocked",
          when = { { "identity", "holy_armaments", "base" },
                   { "ready", "holy_armaments" } },
          display = { kind = "sealed-cooldown-range", ability = "avenging_wrath", beyond = 5 } },
      } },

    -- 5 · Avenger's Shield (rungs 13 and 18). It FEELS like the top of the rotation and rung 18
    -- is the low unconditional one, with three rungs between it and rung 13. Only Glory of the
    -- Vanguard genuinely puts it first.
    --
    -- ⚠ The second marker is the first sealed display in any catalog that rules out a row the
    -- aura does not belong to. Demonology's two count tables both sat on the row whose own press
    -- the count gated; here the count is Divine Guidance's, the entry is Avenger's Shield, and
    -- the statement is "the row to your right outranks this one right now". The mechanism needs
    -- nothing new — `Channel.Plan` binds `display.ability` independently of `entry.ability` —
    -- but the STATEMENT is a relationship rather than a self-test, and that is new.
    --
    -- ⚠ The direction is V16 and not V17, and the choice is the whole of whether it is honest.
    -- Drawn the other way it would say "Avenger's Shield is ruled out until Divine Guidance is
    -- capped", which is false: rung 18 is the ordinary press for the rest of the fight.
    --
    -- ⚠ The Vanguard term is a READABLE GATE on a sealed display — the `when`-beside-`display`
    -- shape. Without it the hatch would rule out the row in the one state rung 13 puts it first.
    { id = "avengers_shield", ability = "avengers_shield",
      bands = { { tier = "ROTATION", when = { { "ready", "avengers_shield" } } } },
      markers = {
        { id = "as_awaits_hammer", cue = "blocked",
          when = { { "identity", "judgment", "transformed" }, { "ready", "judgment" },
                   { "aura", "vanguard", negate = true }, { "ready", "avengers_shield" } } },
        { id = "as_guidance_capped",
          when = { { "aura", "vanguard", negate = true }, { "talent", "divine_guidance" },
                   { "ready", "avengers_shield" } },
          display = {
            kind = "sealed-count-bands", ability = "divine_guidance",
            bands = {
              { threshold = 0, draw = "none" },
              { threshold = 5, draw = "mark", polarity = "negative", hatch = true },
            },
          } },
      } },

    -- 6 · Consecration (rungs 15, 19, 24 and 29). The most-pressed button in the rotation and
    -- the one with the least visible reason — three different ranks behind one identical icon.
    --
    -- ⚠ The complement's readable gate is what makes it TRUE, and this is the answer to
    -- Demonology's warning rather than an exception to it. Below five stacks Consecration is not
    -- eliminated in general: rung 19 presses it whenever the ground effect is down. The gate
    -- narrows the display to the one state where the low band IS an elimination — while Hammer
    -- of Wrath is armed and off cooldown, where rung 16 outranks rung 19 and only rung 15 could
    -- put Consecration back on top. Under that gate both bands are exactly right. Outside it the
    -- client is never asked to paint anything.
    --
    -- ⚠ With no Divine Guidance aura at all the table has no subject and NOTHING covers that
    -- state. A readable marker (`cons_no_guidance`) was authored to fill it and the walk deleted
    -- it for DENSITY, not for being wrong: it was the common term of two overflowing three-hold
    -- trios, and on a Divine Guidance build the identical elimination already arrives free from
    -- the low band. The price is one rung of throughput on a Blessed Assurance build, never a
    -- forbidden press. Reversible — a readable substitute for the count makes it free again.
    --
    -- ⚠ Rungs 19 and 24 are not modelled: `!consecration.up` reads a Category-3 (TrackedBar)
    -- row, the same unmeasured alert-edge question as Avenging Wrath's buff above.
    { id = "consecration", ability = "consecration",
      bands = { { tier = "ROTATION", when = { { "ready", "consecration" } } } },
      markers = {
        { id = "cons_awaits_hammer",
          when = { { "identity", "judgment", "transformed" }, { "ready", "judgment" },
                   { "talent", "divine_guidance" }, { "ready", "consecration" } },
          display = {
            kind = "sealed-count-bands", ability = "divine_guidance",
            bands = {
              { threshold = 0, draw = "mark", polarity = "negative", hatch = true },
              { threshold = 5, draw = "none" },
            },
          } },
      } },

    -- 7 · Judgment / Hammer of Wrath (rungs 17, 22 / 16). In its base life one problem only:
    -- Blessed Assurance makes the hammer to its right worth more for exactly one cast. In its
    -- Hammer of Wrath life it needs nothing — it outranks the two rows to its left, and both of
    -- those wear cue E to say so.
    --
    -- ⚠ The identity term is not decoration: rung 16 puts Hammer of Wrath above both hammer
    -- rungs, so the yield must VANISH while the row is transformed — otherwise the row that just
    -- earned cue E on two neighbours would stand itself down.
    --
    -- ⚠ The talent gate is belt-and-braces in the safe direction. On a Divine Guidance build the
    -- Blessed Assurance aura never exists, so the latch would withhold anyway; the gate makes
    -- the reason legible and matches how the two sealed tables are gated on the other half of
    -- the same node.
    --
    -- ⚠ Rung 17 is not authored — the second-charge dump, and `charged` is undeclarable.
    { id = "judgment", ability = "judgment",
      bands = { { tier = "ROTATION", when = { { "ready", "judgment" } } } },
      markers = {
        { id = "judgment_awaits_assurance", cue = "blocked",
          when = { { "aura", "blessed_assurance" }, { "talent", "blessed_assurance" },
                   { "identity", "judgment", "base" }, { "ready", "judgment" } } },
      } },

    -- 8 · Crusader Strike / Hammer of the Righteous / Blessed Hammer (rungs 20, 21 / 25, 26).
    -- The filler, reached by subtraction. No cue solves anything here.
    --
    -- ⚠ The row declares NO band on `identity` even though it is a choice node. Both hammers
    -- have zero CooldownSetSpell rows, so exactly one exists on any build and reaches the
    -- Cooldown Manager permanently on `35395` — the transform is always on and a band would
    -- encode a distinction that never varies. Retribution's Final Verdict is the same shape.
    --
    -- ⚠ Its Blessed Assurance promotion is expressed on Judgment (cue F), not here: this row
    -- does not change KIND under the buff, and a rank change within one kind is what the
    -- left-to-right scan already carries.
    { id = "crusader_strike", ability = "crusader_strike",
      bands = { { tier = "FALLBACK", when = { { "ready", "crusader_strike" } } } } },

    -- 9 · Word of Glory (rung 28). A Holy Power heal competing with the active mitigation for
    -- the same three Holy Power, and the priority presses it in exactly one state: free. Without
    -- the proc the button has no place in the damage priority at all, so this hold is
    -- load-bearing the way Demonology's `db_awaits_core` is.
    --
    -- ⚠ No `starved` marker here, deliberately. Cue G already holds the row in EVERY state where
    -- affordability could matter, and a second badge on the last entry would say the same thing
    -- twice.
    { id = "word_of_glory", ability = "word_of_glory",
      bands = { { tier = "FALLBACK", when = { { "ready", "word_of_glory" } } } },
      markers = {
        { id = "wog_awaits_shining_light", cue = "blocked",
          when = { { "aura", "shining_light", negate = true } } },
      } },
  },
}
