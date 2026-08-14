-- Provisional product characterization: these examples detect pilot drift; play decides value.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("product characterization / Demonology pilot", function()
  local ns, resolved
  before_each(function()
    ns = H.fresh()
    resolved = ns.Catalog.Resolve(H.catalog(ns), H.rows())
  end)

  it("puts a ready Tyrant in SOON and exposes setup facts separately", function()
    local world = H.world{
      ready = H.map(true, { dreadstalkers = false }),
      identity = H.map("base", { grimoire = "transformed" }),
    }
    local v = ns.Signal.Evaluate(resolved, world).byEntry.tyrant
    assert.equal("SOON", v.tier)
    assert.same({ "dreadstalkers", "grimoire" }, v.markers)
  end)

  it("demotes a proc'd Demonbolt discretely at higher shards", function()
    local low = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true), resource = 1 })
    local high = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true), resource = 5 })
    assert.equal("SOON", low.byEntry.demonbolt.tier)
    assert.equal("FALLBACK", high.byEntry.demonbolt.tier)
  end)
end)
