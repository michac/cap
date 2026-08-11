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

  it("does not call one returned charge fully ready", function()
    track:SeedCharges("tyrant", 2)
    track:Edge(1, H.cid(resolved, "tyrant"), "Available")
    assert.equal("unknown", world().ready.tyrant)
  end)

  it("tallies only predicates the catalog asks for", function()
    local _, health = world{ proc = { demonbolt = false }, identity = { grimoire = "base" }, resource = 2 }
    assert.equal(1, health.predicates.proc.known)
    assert.equal(1, health.predicates.identity.known)
    assert.equal(1, health.predicates.resource.known)
  end)
end)
