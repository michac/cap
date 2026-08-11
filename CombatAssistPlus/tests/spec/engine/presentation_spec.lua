-- Mechanical presentation seams only; pixels remain an in-game judgment.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("engine / presentation", function()
  local ns
  before_each(function() ns = H.fresh() end)

  it("has one static emphasis and no pulse vocabulary", function()
    local d = ns.Treatment.For{ emphasized = true, strength = 0.5 }
    assert.is_not_nil(d.ring)
    assert.is_nil(ns.Treatment.Pulse)
    assert.is_nil(ns.Treatment.ORDER)
  end)

  it("gives each readable marker a distinct fixed slot", function()
    local dogs = ns.Treatment.Marker("dreadstalkers")
    local grim = ns.Treatment.Marker("grimoire")
    assert.is_not_nil(dogs)
    assert.is_not_nil(grim)
    assert.is_not_equal(dogs.slot, grim.slot)
  end)

  it("plans only the independent declared bar and carries no icon treatment", function()
    local Bars = H.withBars(ns)
    local cat = H.catalog(ns)
    local resolved = ns.Catalog.Resolve(cat, H.rows())
    local out = ns.Signal.Evaluate(resolved, H.world())
    local plan = Bars.Plan(cat.bar, out)
    assert.equal(1, #plan)
    assert.equal("tyrant", plan[1].id)
    assert.is_nil(plan[1].treatment)
  end)
end)

