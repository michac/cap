-- Mechanical presentation seams only; pixels remain an in-game judgment.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("engine / presentation", function()
  local ns
  before_each(function() ns = H.fresh() end)

  it("draws a member row as the ONE scan treatment, with nothing finer to draw", function()
    local d = ns.Treatment.For{ member = true }
    assert.is_true(d.scan)
    -- Membership reaches the paint as one bit. Anything here that could grade one member row
    -- against another is a hue ladder growing back (render-shelf V2).
    assert.is_nil(d.lane, "a member row still carries a drawn lane")
    assert.is_nil(d.thickness, "a member row still carries a band width the border cannot use")
    assert.is_false(ns.Treatment.For{ member = false }.scan)
    assert.is_false(ns.Treatment.For{}.scan)
    assert.is_nil(ns.Treatment.ORDER, "the lane validation set should be gone with the lanes")
    assert.is_nil(ns.Treatment.Pulse)
  end)

  it("draws a charged row exactly as it draws any other in-scan row", function()
    -- CHARGES was a fourth hue that REPLACED the role lane. With one treatment there is nothing
    -- for it to replace: the catalog still authors `charged`, and the paint no longer reads it.
    assert.same(ns.Treatment.For{ member = true },
                ns.Treatment.For{ member = true, charged = true })
    -- A non-member row is out of the scan, charged or not.
    assert.is_false(ns.Treatment.For{ charged = true }.scan)
  end)

  it("carries the authored charged flag from the catalog through to the verdict", function()
    local cat = H.catalogBySpec(ns, 267)
    local resolved = ns.Catalog.Resolve(cat, H.destructionRows())
    assert.is_true(resolved.entries[1].charged)
    local v = ns.Signal.Evaluate(resolved, H.world()).byEntry.conflagrate
    assert.is_true(v.charged)
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
  -- V11 · the cooldown hatch. Its whole safety property is the direction of the default: cap
  -- draws it when it has been TOLD the button is down, and never infers the opposite.
  describe("the cooldown hatch", function()
    it("draws only on a readiness the CDM actually reported as false", function()
      assert.is_true(ns.Treatment.For{ member = true, oncd = true }.hatch)
      assert.is_false(ns.Treatment.For{ member = true, oncd = false }.hatch)
    end)

    it("draws nothing for an unknown or absent readiness", function()
      assert.is_false(ns.Treatment.For{ member = true }.hatch)
      assert.is_false(ns.Treatment.For{ member = true, oncd = ns.Signal.UNKNOWN }.hatch)
      assert.is_false(ns.Treatment.For{ member = true, oncd = nil }.hatch)
    end)

    -- It is a fact about the button, not about cap's opinion of it, so a row outside the
    -- scan still wears it. `Overlay.cell` renders that as `id:off~`, which is why a bare `off`
    -- can no longer be read as "nothing drawn".
    it("is independent of whether the row is in the scan", function()
      local d = ns.Treatment.For{ oncd = true }
      assert.is_false(d.scan)
      assert.is_true(d.hatch)
    end)
  end)
end)
