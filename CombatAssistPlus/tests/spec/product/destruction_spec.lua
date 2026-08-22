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
    assert.equal("sealed-count-bands", marker.display.kind)
    -- The shape is UNCHANGED by the 2026-08-22 migration off `player-aura-stacks`: silent below
    -- two, the number at two and above. What changed is whose rule it is — `min = 2` was
    -- Blizzard's no-formatter default, and this is cap's own breakpoint table saying the same
    -- thing, which is why the assertion moved from one number to two bands.
    assert.same({ threshold = 0, draw = "none" }, marker.display.bands[1])
    assert.same({ threshold = 2, draw = "count" }, marker.display.bands[2])
    assert.is_nil(marker.when)
    assert.same({}, verdict(0, 5).markers)
  end)
end)
