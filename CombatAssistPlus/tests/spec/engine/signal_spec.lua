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
    assert.equal("ROTATION", out.byEntry.tyrant.tier)
    assert.same({ "dreadstalkers", "grimoire" }, out.byEntry.tyrant.markers)
    assert.equal("ROTATION", out.byEntry.demonbolt.tier)
  end)

  it("withholds output when a readable fact refuses", function()
    local out = ns.Signal.Evaluate(resolved, H.blindWorld())
    assert.is_false(out.byEntry.tyrant.emphasized)
    assert.is_nil(out.byEntry.tyrant.tier)
    assert.same({}, out.byEntry.tyrant.markers)
    assert.is_true(out.unknowns > 0)
  end)

  it("does not turn negated unknown into true", function()
    assert.equal(ns.Signal.UNKNOWN,
      ns.Signal.Term({ "ready", "dreadstalkers", negate = true }, H.blindWorld()))
  end)

  it("selects a discrete lower tier rather than grading strength", function()
    local low = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true), resource = 1 })
    local high = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true), resource = 5 })
    assert.equal("ROTATION", low.byEntry.demonbolt.tier)
    assert.equal("FALLBACK", high.byEntry.demonbolt.tier)
    local blind = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true), resource = "unknown" })
    assert.is_nil(blind.byEntry.demonbolt.tier)
  end)

  it("allows several entries to occupy one tier", function()
    local duplicate = H.copy(resolved)
    duplicate.entries[2].entry.bands = {
      { tier = "ROTATION", when = { { "proc", "demonbolt" } } },
    }
    local out = ns.Signal.Evaluate(duplicate, H.world{ proc = H.map(true) })
    assert.equal("ROTATION", out.byEntry.tyrant.tier)
    assert.equal("ROTATION", out.byEntry.demonbolt.tier)
  end)

  it("tries same-tier alternatives but never falls below an uncertain higher tier", function()
    local bands = resolved.entries[2].entry.bands
    bands[1] = { tier = "ROTATION", when = { { "resource", "<=", 3 } } }
    table.insert(bands, 2, { tier = "ROTATION", when = { { "proc", "demonbolt" } } })
    local same = ns.Signal.Evaluate(resolved,
      H.world{ proc = H.map(true), resource = "unknown" })
    assert.equal("ROTATION", same.byEntry.demonbolt.tier)

    bands[2] = { tier = "FALLBACK", when = { { "proc", "demonbolt" } } }
    local lower = ns.Signal.Evaluate(resolved,
      H.world{ proc = H.map(true), resource = "unknown" })
    assert.is_nil(lower.byEntry.demonbolt.tier)
  end)


  it("records why each readable marker drew, was ruled out, or went blind", function()
    local out = ns.Signal.Evaluate(resolved, H.world{
      ready = H.map(true, { dreadstalkers = false }), -- dreadstalkers marker ON (negated false)
      identity = H.map("base"),                       -- grimoire marker OFF (not transformed)
    })
    local byId = {}
    for _, r in ipairs(out.byEntry.tyrant.reasons) do byId[r.id] = r end
    assert.equal("on", byId.dreadstalkers.state)
    assert.same({ "!ready:dreadstalkers=T" }, byId.dreadstalkers.terms)
    assert.equal("off", byId.grimoire.state)
    assert.same({ "identity:grimoire:transformed=F" }, byId.grimoire.terms)

    local blind = ns.Signal.Evaluate(resolved, H.blindWorld())
    assert.equal("blind", blind.byEntry.tyrant.reasons[1].state)
  end)

  it("Explain agrees with the gate: off wins over blind, all-true is on", function()
    local w = H.world{ ready = H.map(ns.Signal.UNKNOWN, { a = false }) }
    assert.equal("off", (ns.Signal.Explain({ { "ready", "a" }, { "ready", "b" } }, w)))
    assert.equal("blind", (ns.Signal.Explain({ { "ready", "b" } }, w)))
    assert.equal("on", (ns.Signal.Explain({ { "ready", "c" } }, H.world())))
  end)

  it("never evaluates or reports sealed display markers", function()
    local cat = H.catalogBySpec(ns, 267)
    local destruction = ns.Catalog.Resolve(cat, H.destructionRows())
    local out = ns.Signal.Evaluate(destruction, H.blindWorld())
    assert.same({}, out.byEntry.conflagrate.markers)
    assert.equal(0, out.markers)
  end)
end)
