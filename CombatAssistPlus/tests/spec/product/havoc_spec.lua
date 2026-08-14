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
