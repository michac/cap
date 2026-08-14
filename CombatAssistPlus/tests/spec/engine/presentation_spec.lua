-- Mechanical presentation seams only; pixels remain an in-game judgment.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("engine / presentation", function()
  local ns
  before_each(function() ns = H.fresh() end)

  it("draws each discrete tier as one whole lane treatment", function()
    assert.same({ "COOLDOWN", "ROTATION", "FALLBACK" }, ns.Treatment.ORDER)
    for _, tier in ipairs(ns.Treatment.ORDER) do
      local d = ns.Treatment.For{ tier = tier }
      assert.is_true(d.emphasized, tier .. " draws nothing")
      assert.is_number(d.thickness)
    end
    assert.is_nil(ns.Treatment.Pulse)
  end)

  it("has no ad-hoc marker vocabulary beside the shelf's cues", function()
    assert.is_nil(ns.Treatment.MARKERS)
    assert.is_nil(ns.Treatment.Marker)
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
