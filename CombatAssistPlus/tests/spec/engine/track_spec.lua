-- Engine guarantee: readiness begins unknown and only accepted CDM edges change it.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("engine / track", function()
  local ns, track, resolved
  before_each(function()
    ns = H.fresh()
    local cat
    track, cat, resolved = H.track(ns)
    assert.is_not_nil(cat)
  end)

  local function world(reads) return track:World(100, reads) end

  it("starts unknown and latches both readiness states", function()
    assert.equal("unknown", world().ready.tyrant)
    track:Edge(1, H.cid(resolved, "tyrant"), "Available")
    assert.is_true(world().ready.tyrant)
    track:Edge(2, H.cid(resolved, "tyrant"), "OnCooldown")
    assert.is_false(world().ready.tyrant)
  end)

  it("ignores unbound rows and unrelated alert types", function()
    assert.is_false(track:Edge(1, 999999, "Available"))
    assert.is_false(track:Edge(1, H.cid(resolved, "tyrant"), "OnAuraApplied"))
    assert.equal("unknown", world().ready.tyrant)
  end)

  it("tallies only predicates the catalog asks for", function()
    local _, health = world{ proc = { demonbolt = false }, identity = { grimoire = "base" }, resource = 2 }
    assert.equal(1, health.predicates.proc.known)
    assert.equal(1, health.predicates.identity.known)
    assert.equal(1, health.predicates.resource.known)
  end)
end)

describe("engine / charged readiness", function()
  local ns, track, resolved, cid
  before_each(function()
    ns = H.fresh()
    local cat = H.catalogBySpec(ns, 267)
    resolved = ns.Catalog.Resolve(cat, H.destructionRows())
    track = ns.Track.New()
    track:Bind(ns.Track.Binding(resolved, ns.Catalog.Reads(cat)))
    cid = H.cid(resolved, "conflagrate")
  end)

  local function chargeWorld() return track:World(100, { needsResource = false }) end

  it("stays unknown without an exact seed and reports zero as unavailable", function()
    assert.equal("unknown", chargeWorld().ready.conflagrate)
    assert.is_true(track:SeedCharges("conflagrate", 0, 2, 9.3))
    assert.is_false(chargeWorld().ready.conflagrate)
    assert.equal("live", chargeWorld().chargeProvenance.conflagrate)
  end)

  it("seeds, spends, clamps, and gains a charge", function()
    track:SeedCharges("conflagrate", 2, 2, 9.3)
    assert.is_true(track:CastSpell(1, 17962))
    assert.is_true(chargeWorld().ready.conflagrate)
    assert.equal("napkin", chargeWorld().chargeProvenance.conflagrate)
    track:CastSpell(2, 91591)
    track:CastSpell(3, 17962)
    assert.is_false(chargeWorld().ready.conflagrate)
    assert.is_true(track:Edge(10, cid, "ChargeGained"))
    assert.is_true(chargeWorld().ready.conflagrate)
  end)

  it("filters duplicate gains inside half a recharge or one second", function()
    track:SeedCharges("conflagrate", 0, 2, 10)
    assert.is_true(track:Edge(10, cid, "ChargeGained"))
    local landed, why = track:Edge(14.9, cid, "ChargeGained")
    assert.is_false(landed)
    assert.equal("duplicate", why)
    assert.is_true(track:Edge(15, cid, "ChargeGained"))
    local again = track:Edge(20, cid, "ChargeGained")
    assert.is_true(again)
    assert.is_true(chargeWorld().ready.conflagrate)
  end)

  it("re-seeds from live state and retains the last positive recharge", function()
    track:SeedCharges("conflagrate", 0, 2, 8)
    track:Edge(10, cid, "ChargeGained")
    track:SeedCharges("conflagrate", 2, 2, nil)
    assert.equal("live", chargeWorld().chargeProvenance.conflagrate)
    track:CastSpell(11, 17962)
    assert.is_true(track:Edge(12, cid, "ChargeGained"))
    local landed, why = track:Edge(15.9, cid, "ChargeGained")
    assert.is_false(landed)
    assert.equal("duplicate", why)
  end)
end)
