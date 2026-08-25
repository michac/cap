-- Provisional product characterization: the Fel-Scarred roster's shape, not its gameplay value.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("product characterization / Havoc pilot", function()
  local ns, cat
  before_each(function()
    ns = H.fresh()
    cat = H.catalogBySpec(ns, 577)
  end)

  --- Does the composed row read as SKIP? The elimination walk passes over a row wearing a
  --- negative badge, so this is the drawn meaning of every hold, starve and block below.
  local function skips(verdict)
    for _, key in ipairs(ns.Treatment.For(verdict).cues or {}) do
      if (ns.Style.cues[key] or {}).polarity ~= "positive" then return true end
    end
    return false
  end

  it("is Fel-Scarred specifically, and validates", function()
    assert.same({}, ns.Catalog.Check(cat))
    assert.equal(34, cat.hero)
    -- Aldrachi Reaver is a separate catalog; a loose spec-only match would wrongly claim it.
    assert.is_nil(ns.Catalog.ForBuild(577, 35))
    assert.equal(cat, ns.Catalog.ForBuild(577, 34))
  end)

  it("declares no power type, because Fury is a secret primary", function()
    assert.is_nil(cat.power)
    for _, entry in ipairs(cat.entries) do
      for _, alt in ipairs(ns.Catalog.Alternatives(entry)) do
        for _, term in ipairs(alt) do
          assert.not_equal("resource", term[1], entry.id .. " branches on Fury")
        end
      end
    end
  end)

  it("binds on base spell ids only, leaving the demon-form flip to the row union", function()
    for _, ability in ipairs(cat.abilities) do
      assert.is_nil(ability.alt, ability.id .. " hardcodes an override id")
    end
  end)

  it("marks exactly the charge abilities the catalog doc calls purple", function()
    local charged = {}
    for _, ability in ipairs(cat.abilities) do
      if ability.charged then charged[#charged + 1] = ability.id end
    end
    table.sort(charged)
    assert.same({ "fel_rush", "immolation_aura", "throw_glaive" }, charged)
  end)

  --- Immolation Aura alone, evaluated directly. `resolved` is cap's own structure, so building
  --- one by hand fakes no client API — there is no recorded Havoc row set to bind against yet.
  --- `over` may set `aoe`, `talent` and `affordable` to walk the three rungs.
  local function immolation(capped, over)
    local entry
    for _, e in ipairs(H.catalogBySpec(ns, 577).entries) do
      if e.id == "immolation_aura" then entry = e end
    end
    local resolved = { entries = { { entry = entry, row = {}, charged = true } } }
    -- Rung 10 sits BELOW rungs 3 and 4, so the gold badge stands down while Metamorphosis or
    -- The Hunt is ready. The default here is "both spent", which is the state rung 10 is about;
    -- a test that wants the higher cooldown up overrides `ready`.
    local world = H.world{
      capped = H.map(false, { immolation_aura = capped }),
      ready = H.map(true, { metamorphosis = false, the_hunt = false }),
    }
    for k, v in pairs(over or {}) do world[k] = v end
    return ns.Signal.Evaluate(resolved, world).byEntry.immolation_aura
  end

  it("draws capped at max charges — rung 10, which has no target term", function()
    for _, aoe in ipairs{ false, true } do
      local full = immolation(true, { aoe = aoe })
      assert.same({ "capped" }, full.cues, "a banked charge is worth spending at any count")
      assert.is_false(skips(full), "capped is the one positive cue and must not read as skip")
      assert.is_true(ns.Treatment.For(full).scan)
    end
  end)

  it("gates the capped badge on BOTH of rung 10's talents", function()
    -- Rung 10 is `talent.a_fire_inside & talent.burning_wound & (charges=2|...)`. Missing either
    -- one and the rung does not exist, so the badge would be asserting a rank this build has
    -- not got. `capped` is left TRUE below to prove the talent term is what decides it.
    for _, missing in ipairs{ "a_fire_inside", "burning_wound" } do
      local v = immolation(true, { talent = H.map(true, { [missing] = false }) })
      assert.same({ "blocked" }, v.cues, "no gold badge without " .. missing)
      assert.is_true(skips(v), "and the red skip is what replaces it at one target")
    end

    -- In AoE mode the same button draws nothing: rung 20 survives on either talent alone, so
    -- position 7 is right and there is nothing to say.
    local aoe = immolation(true, {
      aoe = true, talent = H.map(true, { a_fire_inside = false }),
    })
    assert.same({}, aoe.cues)
  end)

  it("stands the capped badge down while a higher rung is ready", function()
    -- Rung 10 is below rungs 3 (Metamorphosis) and 4 (The Hunt). A positive cue OVERRIDES the
    -- elimination scan by design, so an ungated one here would point past a cooldown that
    -- outranks it — the exact failure a positive cue is dangerous for.
    for _, up in ipairs{ "metamorphosis", "the_hunt" } do
      local v = immolation(true, { ready = H.map(false, { immolation_aura = true, [up] = true }) })
      assert.same({}, v.cues, up .. " outranks a banked charge")
      assert.is_false(skips(v))
    end
  end)

  it("keeps the skip off a button the CDM has already swiped", function()
    -- `Treatment.For` passes cues through for rows the client has greyed out, so without a
    -- readiness term the red badge stands on a recharging icon the player could not press.
    local v = immolation(false, { ready = H.map(false) })
    assert.same({}, v.cues)
    assert.is_false(skips(v))
  end)

  it("keeps both badges unknown-safe when the talent read refuses", function()
    -- `knowledge/addon-dev/` records nothing about the trait-config call, so a refusal is a
    -- real expected state. It must cost the badges, never invent one — including through the
    -- negated talent terms in the skip's union, where `not unknown` is still unknown.
    local v = immolation(true, { talent = H.map("unknown") })
    assert.same({}, v.cues)
    assert.is_false(skips(v))
  end)

  it("marks Immolation Aura skippable at ONE target — the AoE re-weight, in negative polarity",
    function()
      -- Rung 25: at one target with no charge banked it sits BELOW Chaos Strike, and row
      -- position cannot say so. Marking it skippable when AoE mode is off says the same thing
      -- in the polarity this vocabulary actually has.
      local single = immolation(false, { aoe = false })
      assert.same({ "blocked" }, single.cues)
      assert.is_true(skips(single))

      -- Rung 20: at 2+ targets it outranks Chaos Strike, which is exactly its row position, so
      -- nothing is drawn and the scan reaches it.
      local aoe = immolation(false, { aoe = true })
      assert.same({}, aoe.cues)
      assert.is_false(skips(aoe))
    end)

  it("clears the single-target skip when Chaos Strike cannot be paid for", function()
    -- The skip says "press the spender instead". Starved, there is no spender to press and the
    -- generator/Immolation half of the list is what is left, so the badge must clear or the
    -- walk over-runs the row.
    local v = immolation(false, { aoe = false, affordable = H.map(true, { chaos_strike = false }) })
    assert.same({}, v.cues)
    assert.is_false(skips(v))
  end)

  it("never draws the gold and the red badge on the same button, on ANY build", function()
    -- The skip's union is `!(capped & a_fire_inside & burning_wound)` and the gold badge tests
    -- that same conjunction, so they partition the space however the two talents fall. A row
    -- wearing both would be telling the player to press it and skip it at once; the exhaustive
    -- sweep is cheap and is the proof.
    local vals = { true, false, "unknown" }
    for _, capped in ipairs(vals) do
      for _, aoe in ipairs{ true, false } do
        for _, afi in ipairs(vals) do
          for _, bw in ipairs(vals) do
            local v = immolation(capped, {
              aoe = aoe, talent = H.map(true, { a_fire_inside = afi, burning_wound = bw }),
            })
            assert.is_true(#v.cues <= 1, ("capped=%s aoe=%s afi=%s bw=%s drew %d badges")
              :format(tostring(capped), tostring(aoe), tostring(afi), tostring(bw), #v.cues))
          end
        end
      end
    end
  end)

  it("draws nothing at all when the charge read refuses", function()
    -- Both markers name `capped`, in opposite directions, so an unknown withholds BOTH.
    local v = immolation("unknown")
    assert.same({}, v.cues)
    assert.is_false(skips(v))
  end)

  --- One Fury spender, evaluated directly, with its affordability forced.
  local function spender(id, affordable)
    local entry
    for _, e in ipairs(H.catalogBySpec(ns, 577).entries) do
      if e.id == id then entry = e end
    end
    local resolved = { entries = { { entry = entry, row = {} } } }
    return ns.Signal.Evaluate(resolved, H.world{
      affordable = H.map(true, { [id] = affordable }),
    }).byEntry[id]
  end

  it("draws starved on a spender that cannot be paid for, and nothing when it can", function()
    for _, id in ipairs{ "chaos_strike", "blade_dance" } do
      local broke = spender(id, false)
      assert.same({ "starved" }, broke.cues, id .. " must wear the cue when Fury is short")
      assert.is_true(skips(broke))

      local rich = spender(id, true)
      assert.same({}, rich.cues, id .. " must be clean when it is affordable")
      assert.is_false(skips(rich))
    end
  end)

  it("keeps a negated affordability read unknown-safe rather than assuming starved", function()
    -- The trap the negation invites: `not unknown` is not `true`. A refused read must draw
    -- nothing, never a cue that tells the player they are broke on no evidence.
    for _, id in ipairs{ "chaos_strike", "blade_dance" } do
      local v = spender(id, "unknown")
      assert.same({}, v.cues, id .. " invented a cue from a refused read")
      assert.is_false(skips(v))
    end
  end)

  it("wears overcap on the Fury generators, and affordability on neither", function()
    for _, id in ipairs{ "felblade", "demons_bite" } do
      local entry
      for _, e in ipairs(cat.entries) do if e.id == id then entry = e end end
      for _, marker in ipairs(entry.markers) do
        for _, term in ipairs(marker.when or {}) do
          assert.not_equal("affordable", term[1],
            id .. " costs nothing and must never read as unaffordable")
        end
      end
      -- The generator's failure mode is the opposite one, and it is sealed: the client
      -- evaluates the curve, so nothing here is a readable condition at all.
      local sealed = ns.Channel.PowerPlan(entry.markers[1])
      assert.equal("overcap", sealed.cue, id .. " carries no overcap readout")
      assert.equal("Fury", sealed.power)
    end
  end)

  it("breaks the two generators at the numbers their sources actually give", function()
    local function marker(id)
      for _, e in ipairs(cat.entries) do
        if e.id == id then return ns.Channel.PowerPlan(e.markers[1]) end
      end
    end
    -- Felblade's rung is `fury<=100` — an ABSOLUTE level, so it is a threshold and the break is
    -- 100/max. Authoring it as a generation would only work by assuming max is 170.
    local felblade = marker("felblade")
    assert.equal(100, felblade.threshold)
    assert.is_nil(felblade.generation)
    assert.equal(100 / 170, ns.Channel.ThresholdBreak(felblade.threshold, 170))

    -- Demon's Bite has no APL rung; its break is true overcap off the authored generation table.
    local bite = marker("demons_bite")
    assert.equal(25, bite.generation)
    assert.is_nil(bite.threshold)
    assert.equal((170 - 25) / 170, ns.Channel.PowerBreak(bite.generation, 170))
  end)

  --- One placed-cooldown entry evaluated against a forced readiness map.
  local function hold(id, ready)
    local entry
    for _, e in ipairs(H.catalogBySpec(ns, 577).entries) do
      if e.id == id then entry = e end
    end
    local resolved = { entries = { { entry = entry, row = {} } } }
    return ns.Signal.Evaluate(resolved, H.world{ ready = H.map(false, ready) }).byEntry[id]
  end

  it("holds Metamorphosis while EITHER reset target is up, and unions to one badge", function()
    -- Two markers naming one cue is how the AND-only band grammar expresses an OR. The badge
    -- must not double up, and either disjunct alone must be enough to raise it.
    local both = hold("metamorphosis", { metamorphosis = true, eye_beam = true, blade_dance = true })
    assert.same({ "blocked" }, both.cues, "two satisfied markers must union into one badge")
    assert.same({ "meta_wastes_eye_beam", "meta_wastes_death_sweep" }, both.markers)

    for _, dep in ipairs{ "eye_beam", "blade_dance" } do
      local v = hold("metamorphosis", { metamorphosis = true, [dep] = true })
      assert.same({ "blocked" }, v.cues, dep .. " alone must hold Meta")
      assert.is_true(skips(v))
    end
  end)

  it("draws nothing on Metamorphosis once both resets are spent", function()
    -- "A satisfied dependency draws nothing" — the press is the quiet row, not a decorated one.
    local v = hold("metamorphosis", { metamorphosis = true })
    assert.same({}, v.cues)
    assert.is_false(skips(v))
    assert.is_true(ns.Treatment.For(v).scan)
  end)

  it("holds The Hunt on TWO sealed bands — one per axis — and never on readiness alone", function()
    -- The polarity is the inverse of an earlier draft's: the APL casts The Hunt when
    -- `cooldown.metamorphosis.up`, and holds it while Meta is close but not here. Readiness is
    -- therefore the wrong fact entirely — both holds ride a REMAINING time, which is secret, so
    -- neither may ever surface as a readable cue.
    for _, ready in ipairs{ { the_hunt = true, metamorphosis = true }, { the_hunt = true } } do
      local v = hold("the_hunt", ready)
      assert.same({}, v.cues, "The Hunt's hold must not be a readable condition")
      assert.is_false(skips(v))
    end

    local entry
    for _, e in ipairs(cat.entries) do if e.id == "the_hunt" then entry = e end end
    local seen = {}
    for _, marker in ipairs(entry.markers) do
      local plan = ns.Channel.HoldPlan(marker)
      assert.equal("sealed-cooldown-range", plan.kind)
      assert.equal("blocked", plan.cue, "both bands name ONE cue — that union is the OR")
      seen[plan.ability] = plan.beyond and ("beyond " .. plan.beyond) or ("within " .. plan.within)
    end
    -- Two senses, two axes: Eye Beam FAR, or Metamorphosis NEAR.
    assert.same({ eye_beam = "beyond 10", metamorphosis = "within 15" }, seen)
  end)

  it("gates both of The Hunt's bands on Eternal Hunt — the talent predicate beyond one spec's "
    .. "pet case", function()
    local entry
    for _, e in ipairs(cat.entries) do if e.id == "the_hunt" then entry = e end end
    local resolved = { entries = { { entry = entry, row = {} } } }
    local function gates(talented, metaReady)
      return ns.Signal.Evaluate(resolved, H.world{
        ready = H.map(false, { the_hunt = true, metamorphosis = metaReady }),
        talent = H.map(true, { eternal_hunt = talented }),
      }).byEntry.the_hunt.gates
    end

    -- Without Eternal Hunt rung 4 is unconditional: there is no hold, so neither band may paint.
    local off = gates(false, false)
    assert.is_false(off.hunt_awaits_eye_beam)
    assert.is_false(off.hunt_awaits_meta)

    -- With it, and Metamorphosis down, both bands are allowed to speak — what they then SAY is
    -- the client's, off the curve, and cap never reads it back.
    local on = gates(true, false)
    assert.is_true(on.hunt_awaits_eye_beam)
    assert.is_true(on.hunt_awaits_meta)

    -- Metamorphosis READY is the other cast case, so the Eye-Beam-far hold stands down for it.
    local metaUp = gates(true, true)
    assert.is_false(metaUp.hunt_awaits_eye_beam)
    assert.is_true(metaUp.hunt_awaits_meta)

    -- An unknown talent read withholds, exactly as `off` does — never licenses.
    local blind = ns.Signal.Evaluate(resolved, H.world{
      ready = H.map(false, { the_hunt = true }), talent = H.map("unknown"),
    }).byEntry.the_hunt.gates
    assert.is_false(blind.hunt_awaits_eye_beam)

    -- And a gated band still contributes NO readable cue: the badge is the client's to paint.
    assert.same({}, ns.Signal.Evaluate(resolved, H.world{
      ready = H.map(false, { the_hunt = true }), talent = H.map(true),
    }).byEntry.the_hunt.cues)
  end)

  it("unions Vengeful Retreat's two sealed sync bands onto one badge", function()
    local entry
    for _, e in ipairs(cat.entries) do if e.id == "vengeful_retreat" then entry = e end end
    local seen = {}
    for _, marker in ipairs(entry.markers) do
      local plan = ns.Channel.HoldPlan(marker)
      assert.is_truthy(plan, marker.id .. " is not a sealed range hold")
      assert.equal("blocked", plan.cue, "both bands must name ONE cue — that union is the OR")
      seen[plan.ability] = plan.within
    end
    assert.same({ eye_beam = 8, metamorphosis = 4 }, seen)
  end)

  it("keeps every hold unknown-safe when the dependency read refuses", function()
    for _, id in ipairs{ "metamorphosis", "the_hunt" } do
      local v = ns.Signal.Evaluate(
        { entries = { { entry = (function()
          for _, e in ipairs(cat.entries) do if e.id == id then return e end end
        end)(), row = {} } } },
        H.blindWorld()).byEntry[id]
      assert.same({}, v.cues, id .. " invented a hold from a refused read")
    end
  end)

  it("declares no scan_when anywhere — every Havoc row is a default ready-self member", function()
    -- The FALLBACK-charges audit that stood here was about the tier having no subject on this
    -- spec; without tiers that is vacuous, and what remains assertable is that the collapse
    -- left no conditional membership behind.
    for _, entry in ipairs(cat.entries) do
      assert.is_nil(entry.scan_when, entry.id .. " declares conditional membership")
    end
  end)
end)
