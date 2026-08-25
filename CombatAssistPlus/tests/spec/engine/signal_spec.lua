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
    assert.is_true(out.byEntry.tyrant.member)
    assert.same({ "dreadstalkers", "grimoire" }, out.byEntry.tyrant.markers)
    assert.is_true(out.byEntry.demonbolt.member)
  end)

  it("withholds output when a readable fact refuses", function()
    local out = ns.Signal.Evaluate(resolved, H.blindWorld())
    assert.is_false(out.byEntry.tyrant.emphasized)
    assert.is_false(out.byEntry.tyrant.member)
    assert.is_true(out.byEntry.tyrant.blind)
    assert.same({}, out.byEntry.tyrant.markers)
    assert.is_true(out.unknowns > 0)
  end)

  it("does not turn negated unknown into true", function()
    assert.equal(ns.Signal.UNKNOWN,
      ns.Signal.Term({ "ready", "dreadstalkers", negate = true }, H.blindWorld()))
  end)

  it("membership follows the declared scan_when alternative", function()
    local low = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true), resource = 1 })
    local high = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true), resource = 5 })
    assert.is_true(low.byEntry.demonbolt.member)
    assert.is_false(high.byEntry.demonbolt.member)
    assert.is_false(high.byEntry.demonbolt.blind)
    local blind = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true), resource = "unknown" })
    assert.is_false(blind.byEntry.demonbolt.member)
    assert.is_true(blind.byEntry.demonbolt.blind)
  end)

  it("a default entry is in the scan exactly when the ability reads ready", function()
    -- The shadow_bolt-shaped pin (2026-08-25): default membership reads ready(self) and
    -- NOTHING else, so an unknown identity or resource no longer darkens a filler row.
    local out = ns.Signal.Evaluate(resolved,
      H.world{ identity = H.map("unknown"), resource = "unknown" })
    assert.is_true(out.byEntry.tyrant.member)
    assert.is_false(out.byEntry.tyrant.blind)
    local down = ns.Signal.Evaluate(resolved, H.world{ ready = H.map(false) })
    assert.is_false(down.byEntry.tyrant.member)
    assert.is_false(down.byEntry.tyrant.blind)
  end)

  it("one ON alternative carries membership even while another is blind", function()
    -- The uniform blind rule: blindness withholds only when NO alternative reads ON. Under
    -- the retired tier bands a blind higher band withheld a true lower one.
    local alts = resolved.entries[2].entry.scan_when
    alts[#alts + 1] = { { "proc", "demonbolt" } }
    local out = ns.Signal.Evaluate(resolved,
      H.world{ proc = H.map(true), resource = "unknown" })
    assert.is_true(out.byEntry.demonbolt.member)
    assert.is_false(out.byEntry.demonbolt.blind)
  end)

  it("allows several entries in the scan at once", function()
    local out = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true), resource = 1 })
    assert.is_true(out.byEntry.tyrant.member)
    assert.is_true(out.byEntry.demonbolt.member)
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
