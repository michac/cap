-- Provisional product characterization: play decides whether these authored cues help.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("product characterization / Destruction pilot", function()
  local ns, cat, resolved
  before_each(function()
    ns = H.fresh()
    cat = H.catalogBySpec(ns, 267)
    resolved = ns.Catalog.Resolve(cat, H.destructionRows())
  end)

  local function verdict(charges, shards)
    local ready = charges == nil and "unknown" or charges > 0
    return ns.Signal.Evaluate(resolved, H.world{
      ready = H.map(true, { conflagrate = ready }), resource = shards,
    }).byEntry.conflagrate
  end

  it("places available Conflagrate in ROTATION through four shards", function()
    assert.equal("ROTATION", verdict(1, 4).tier)
  end)

  it("places available Conflagrate in FALLBACK above four shards", function()
    assert.equal("FALLBACK", verdict(1, 5).tier)
  end)

  it("withholds a tier at zero or unknown charges", function()
    assert.is_nil(verdict(0, 2).tier)
    assert.is_nil(verdict(nil, 2).tier)
  end)

  it("authors Backdraft as an independent sealed display", function()
    local marker = cat.entries[1].markers[1]
    assert.equal("player-aura-stacks", marker.display.kind)
    assert.equal(2, marker.display.min)
    assert.is_nil(marker.when)
    assert.same({}, verdict(0, 5).markers)
  end)
end)
