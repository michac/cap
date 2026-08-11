-- Provisional product characterization: these examples detect pilot drift; play decides value.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("product characterization / Demonology pilot", function()
  local ns, resolved
  before_each(function()
    ns = H.fresh()
    resolved = ns.Catalog.Resolve(H.catalog(ns), H.rows())
  end)

  it("emphasizes a ready Tyrant and exposes setup facts separately", function()
    local world = H.world{
      ready = H.map(true, { dreadstalkers = false }),
      identity = H.map("base", { grimoire = "transformed" }),
    }
    local v = ns.Signal.Evaluate(resolved, world).byEntry.tyrant
    assert.is_true(v.emphasized)
    assert.same({ "dreadstalkers", "grimoire" }, v.markers)
  end)

  it("emphasizes a proc'd Demonbolt more strongly at fewer shards", function()
    local low = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true), resource = 1 })
    local high = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true), resource = 5 })
    assert.is_true(low.byEntry.demonbolt.emphasized)
    assert.is_true(low.byEntry.demonbolt.strength > high.byEntry.demonbolt.strength)
  end)
end)
