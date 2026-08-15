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

  it("leaves the Fury generators clean, since they can never be unaffordable", function()
    for _, id in ipairs{ "felblade", "demons_bite" } do
      local entry
      for _, e in ipairs(cat.entries) do if e.id == id then entry = e end end
      assert.is_nil(entry.markers, id .. " is a generator and must carry no affordability cue")
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
