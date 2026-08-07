-- tier_spec.lua — band evaluation, authored from the Demonology catalog document.
--
-- The refused-read block at the bottom is the load-bearing one. A harness that can
-- hand the code a resource value cannot reproduce the state the client actually
-- produces under restriction, so every gate in the vocabulary must have a case where
-- it refuses, and a meta-test fails if one is missing.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("Tier", function()
  local ns, cat, bound

  before_each(function()
    ns = H.fresh()
    cat = H.catalog(ns)
    local _, resolved = ns.Catalog.CheckBound(cat, H.rows())
    bound = resolved
  end)

  local function evaluate(over)
    return ns.Tier.Evaluate(bound, H.world(over))
  end

  describe("the floor", function()
    it("is LOW whatever else is true", function()
      local out = evaluate()
      assert.equal("LOW", out.byEntry.E10.tier)
    end)

    it("stays LOW even when every gate refuses — it asks nothing of the world", function()
      local out = ns.Tier.Evaluate(bound, H.blindWorld())
      assert.equal("LOW", out.byEntry.E10.tier)
    end)
  end)

  describe("Demonbolt — the demotion the whole feature exists for", function()
    it("is MEDIUM on a proc at low shards", function()
      local out = evaluate{ proc = H.map(true), resource = 2 }
      assert.equal("MEDIUM", out.byEntry.E7.tier)
    end)

    it("falls to LOW on the same proc at high shards", function()
      local out = evaluate{ proc = H.map(true), resource = 5 }
      assert.equal("LOW", out.byEntry.E7.tier)
    end)

    it("has no tier at all without a proc", function()
      local out = evaluate{ proc = H.map(false), resource = 2 }
      assert.is_nil(out.byEntry.E7.tier)
    end)

    it("grades inverted — 5 shards reads dimmer than 4", function()
      local at5 = evaluate{ proc = H.map(true), resource = 5 }.byEntry.E7.grade
      local at4 = evaluate{ proc = H.map(true), resource = 4 }.byEntry.E7.grade
      assert.is_true(at5.value < at4.value)
    end)
  end)

  describe("Hand of Gul'dan and Ruination share a row and are still independent", function()
    it("gives E5 a tier and E6 none while the row shows its base", function()
      local out = evaluate{ affordable = H.map(true) }
      assert.equal("MEDIUM", out.byEntry.E5.tier)
      assert.is_nil(out.byEntry.E6.tier)
    end)

    it("lights E6 when the row transforms, without touching E5", function()
      local out = evaluate{
        affordable = H.map(true),
        identity = H.map("transformed"),
      }
      assert.equal("HIGH", out.byEntry.E6.tier)
      assert.equal("MEDIUM", out.byEntry.E5.tier)
    end)
  end)

  describe("first-match within an entry", function()
    it("takes the apex band over the ordinary one", function()
      local out = evaluate{ affordable = H.map(true), auraUp = H.map(true) }
      assert.equal("HIGH", out.byEntry.E5.tier)
      assert.equal(1, out.byEntry.E5.band)
    end)

    it("takes the shard band when the apex buff is absent", function()
      local out = evaluate{ affordable = H.map(true), resource = 5 }
      assert.equal("HIGH", out.byEntry.E5.tier)
      assert.equal(3, out.byEntry.E5.band)
    end)
  end)

  describe("the cue is an offer, not a decision", function()
    it("is offered when its gate holds and carries the HIGH treatment", function()
      local out = evaluate{ ready = H.map(true) }
      assert.equal("HIGH", out.byEntry.E8.cue.tier)
      assert.equal(296553, out.byEntry.E8.cue.threshold.of)
      assert.equal(6, out.byEntry.E8.cue.threshold.min)
    end)

    it("is withheld when the gate does not hold", function()
      local out = evaluate{ ready = H.map(false) }
      assert.is_nil(out.byEntry.E8.cue)
    end)

    it("is counted apart from HIGH bands, because nothing here saw the count", function()
      local out = evaluate{ ready = H.map(true) }
      assert.equal(1, out.cuesOffered)
    end)
  end)

  describe("more than one thing can be HIGH at once", function()
    it("lights three at a staged Tyrant setup", function()
      -- Dreadstalkers out, Tyrant ready, the window open, 5 shards banked.
      local out = evaluate{
        ready = H.map(true), affordable = H.map(true), resource = 5,
        auraUp = H.map(true), window = H.map(false, { tyrant_setup = true }),
      }
      assert.is_true(out.highs >= 3)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Refused reads — one case per gate, and a meta-test that they are all present
  --------------------------------------------------------------------------------
  local refused = {}

  local function refusalCase(gate, fn)
    refused[gate] = true
    it(gate .. " refusing fails its band rather than passing it", fn)
  end

  describe("a refused read is not a false", function()
    refusalCase("ready", function()
      local out = evaluate{ ready = H.map("unknown") }
      assert.is_nil(out.byEntry.E1.tier)
      assert.is_true(out.unknowns > 0)
    end)

    refusalCase("affordable", function()
      local out = evaluate{ affordable = H.map("unknown") }
      assert.is_nil(out.byEntry.E5.tier)
    end)

    refusalCase("proc", function()
      local out = evaluate{ proc = H.map("unknown"), resource = 2 }
      assert.is_nil(out.byEntry.E7.tier)
    end)

    refusalCase("auraUp", function()
      local out = evaluate{ ready = H.map(true), auraUp = H.map("unknown") }
      -- E1 band 1 needs the Dreadstalkers aura; a refusal must not promote it.
      assert.equal("MEDIUM", out.byEntry.E1.tier)
    end)

    refusalCase("window", function()
      local out = evaluate{ ready = H.map(true), affordable = H.map(true), window = H.map("unknown") }
      assert.equal("MEDIUM", out.byEntry.E2.tier)
    end)

    refusalCase("identity", function()
      local out = evaluate{ identity = H.map("unknown") }
      assert.is_nil(out.byEntry.E6.tier)
    end)

    refusalCase("resource", function()
      local out = evaluate{ affordable = H.map(true), resource = "unknown" }
      -- Bands 3 needs shards >= 5 and must not fire blind; band 4 still holds.
      assert.equal("MEDIUM", out.byEntry.E5.tier)
    end)

    refusalCase("talent", function()
      local out = ns.Tier.Evaluate(bound, H.world{ talent = H.map("unknown") })
      assert.is_table(out.byEntry)
    end)

    refusalCase("elapsed", function()
      local out = evaluate{ elapsed = H.map("unknown") }
      assert.is_table(out.byEntry)
    end)

    refusalCase("mode", function()
      -- `mode` is cap's own state rather than a game read, so it cannot be sealed — but
      -- it is still three-valued, and an unset mode must FAIL a band rather than
      -- defaulting to single-target and asserting an opinion nobody chose.
      local probe = { id = "P", spell = 686, family = "spells",
                      bands = { { tier = "HIGH", when = { { "mode", "aoe" } } } } }
      local one = { entries = { { entry = probe, row = bound.byEntry.E10 } } }
      assert.is_nil(ns.Tier.Evaluate(one, H.world{ mode = "unknown" }).byEntry.P.tier)
      assert.is_nil(ns.Tier.Evaluate(one, H.world{ mode = "single" }).byEntry.P.tier)
      assert.equal("HIGH", ns.Tier.Evaluate(one, H.world{ mode = "aoe" }).byEntry.P.tier)
    end)

    it("counts NOTHING blind when every gate answers", function()
      -- The counter is the only thing that separates "the catalog is quiet" from "the
      -- reads refused", and those draw identical pixels. A world that answers every
      -- gate — including answering `false` — must report zero unknowns.
      local out = evaluate{ ready = H.map(false), affordable = H.map(false) }
      assert.equal(0, out.unknowns)
    end)

    it("counts exactly the bands that met a refusal", function()
      local answered = evaluate{ proc = H.map(false), resource = 2 }
      local blind = evaluate{ proc = H.map("unknown"), resource = 2 }
      assert.equal(0, answered.unknowns)
      assert.is_true(blind.unknowns > 0)
    end)

    it("every gate in the vocabulary has a refusal case", function()
      local missing = {}
      for gate in pairs(ns.Catalog.GATES) do
        if not refused[gate] then missing[#missing + 1] = gate end
      end
      table.sort(missing)
      assert.same({}, missing)
    end)

    it("a wholly blind world produces no tier that asks anything of it", function()
      local out = ns.Tier.Evaluate(bound, H.blindWorld())
      for id, v in pairs(out.byEntry) do
        if id ~= "E10" then
          assert.is_nil(v.tier, id .. " took a tier from a world that answered nothing")
        end
      end
    end)
  end)
end)
