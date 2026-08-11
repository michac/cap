-- Engine guarantee: readable branching is three-valued and never grows confidence blind.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("engine / signal", function()
  local ns, resolved
  before_each(function()
    ns = H.fresh()
    resolved = ns.Catalog.Resolve(H.catalog(ns), H.rows())
  end)

  it("lets readable facts drive emphasis and markers", function()
    local world = H.world{
      ready = H.map(true, { dreadstalkers = false }),
      identity = H.map("base", { grimoire = "transformed" }),
      proc = H.map(false, { demonbolt = true }), resource = 1,
    }
    local out = ns.Signal.Evaluate(resolved, world)
    assert.is_true(out.byEntry.tyrant.emphasized)
    assert.same({ "dreadstalkers", "grimoire" }, out.byEntry.tyrant.markers)
    assert.is_true(out.byEntry.demonbolt.emphasized)
  end)

  it("withholds output when a readable fact refuses", function()
    local out = ns.Signal.Evaluate(resolved, H.blindWorld())
    assert.is_false(out.byEntry.tyrant.emphasized)
    assert.same({}, out.byEntry.tyrant.markers)
    assert.is_true(out.unknowns > 0)
  end)

  it("does not turn negated unknown into true", function()
    assert.equal(ns.Signal.UNKNOWN,
      ns.Signal.Term({ "ready", "dreadstalkers", negate = true }, H.blindWorld()))
  end)

  it("grades strength only from a readable numeric resource", function()
    local low = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true), resource = 1 })
    local high = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true), resource = 5 })
    assert.is_true(low.byEntry.demonbolt.strength > high.byEntry.demonbolt.strength)
    local blind = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true), resource = "unknown" })
    assert.is_nil(blind.byEntry.demonbolt.strength)
  end)
end)

