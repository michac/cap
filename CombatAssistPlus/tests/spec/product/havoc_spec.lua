-- Provisional product characterization: the Fel-Scarred roster's shape, not its gameplay value.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("product characterization / Havoc pilot", function()
  local ns, cat
  before_each(function()
    ns = H.fresh()
    cat = H.catalogBySpec(ns, 577)
  end)

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
      for _, band in ipairs(entry.bands) do
        for _, term in ipairs(band.when) do
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
  local function immolation(capped)
    local entry
    for _, e in ipairs(H.catalogBySpec(ns, 577).entries) do
      if e.id == "immolation_aura" then entry = e end
    end
    local resolved = { entries = { { entry = entry, row = {}, charged = true } } }
    return ns.Signal.Evaluate(resolved, H.world{
      capped = H.map(false, { immolation_aura = capped }),
    }).byEntry.immolation_aura
  end

  it("draws capped at max charges and blocked below it — never both, never neither", function()
    local full = immolation(true)
    assert.same({ "capped" }, full.cues)
    assert.is_false(ns.Treatment.For(full).veil)
    assert.equal("CHARGES", ns.Treatment.For(full).lane)

    local recharging = immolation(false)
    assert.same({ "blocked" }, recharging.cues)
    assert.is_true(ns.Treatment.For(recharging).veil)
  end)

  it("draws neither state when the charge read refuses", function()
    local v = immolation("unknown")
    assert.same({}, v.cues)
    assert.is_false(ns.Treatment.For(v).veil)
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
      assert.is_true(ns.Treatment.For(broke).veil)

      local rich = spender(id, true)
      assert.same({}, rich.cues, id .. " must be clean when it is affordable")
      assert.is_false(ns.Treatment.For(rich).veil)
    end
  end)

  it("keeps a negated affordability read unknown-safe rather than assuming starved", function()
    -- The trap the negation invites: `not unknown` is not `true`. A refused read must draw
    -- nothing, never a cue that tells the player they are broke on no evidence.
    for _, id in ipairs{ "chaos_strike", "blade_dance" } do
      local v = spender(id, "unknown")
      assert.same({}, v.cues, id .. " invented a cue from a refused read")
      assert.is_false(ns.Treatment.For(v).veil)
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

  --- One COOLDOWN entry evaluated against a forced readiness map.
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
      assert.is_true(ns.Treatment.For(v).veil)
    end
  end)

  it("draws nothing on Metamorphosis once both resets are spent", function()
    -- "A satisfied dependency draws nothing" — the press is the quiet row, not a decorated one.
    local v = hold("metamorphosis", { metamorphosis = true })
    assert.same({}, v.cues)
    assert.is_false(ns.Treatment.For(v).veil)
    assert.equal("COOLDOWN", ns.Treatment.For(v).lane)
  end)

  it("holds The Hunt while Metamorphosis is available, and releases it once Meta is spent", function()
    local waiting = hold("the_hunt", { the_hunt = true, metamorphosis = true })
    assert.same({ "blocked" }, waiting.cues)
    assert.is_true(ns.Treatment.For(waiting).veil)

    local free = hold("the_hunt", { the_hunt = true })
    assert.same({}, free.cues)
    assert.is_false(ns.Treatment.For(free).veil)
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

  it("leaves no FALLBACK row without charges — the lane has no subject on this spec", function()
    local byAbility = {}
    for _, a in ipairs(cat.abilities) do byAbility[a.id] = a end
    for _, entry in ipairs(cat.entries) do
      if entry.bands[1].tier == "FALLBACK" then
        assert.is_true(byAbility[entry.ability].charged,
          entry.id .. " would draw a FALLBACK border, which catalog.md says never happens")
      end
    end
  end)
end)
