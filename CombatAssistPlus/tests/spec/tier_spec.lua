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

  --- One entry, evaluated alone, so a probe band can name a term the catalog does not.
  local function probe(bands, over)
    local e = { id = "P", spell = 686, family = "spells", bands = bands }
    local one = { entries = { { entry = e, row = bound.byEntry.E10 } } }
    return ns.Tier.Evaluate(one, H.world(over)).byEntry.P
  end

  describe("the floor", function()
    it("is LOW whatever else is true", function()
      local out = evaluate()
      assert.equal("LOW", out.byEntry.E10.tier)
      assert.equal(3, out.byEntry.E10.band)
    end)

    it("stays LOW even when every gate refuses — its last band asks nothing", function()
      local out = ns.Tier.Evaluate(bound, H.blindWorld())
      assert.equal("LOW", out.byEntry.E10.tier)
    end)

    it("goes HIGH on an armed Infernal Bolt at low shards", function()
      local out = evaluate{ identity = H.map("transformed"), resource = 2 }
      assert.equal("HIGH", out.byEntry.E10.tier)
    end)

    it("falls back to LOW on the same transform at shards it would waste", function()
      -- Infernal Bolt grants 3 against a 5-shard cap: 2 + 3 fits, 3 + 3 does not.
      local out = evaluate{ identity = H.map("transformed"), resource = 3 }
      assert.equal("LOW", out.byEntry.E10.tier)
      assert.equal(2, out.byEntry.E10.band)
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
      assert.equal(2, out.byEntry.E5.band)
    end)

    it("keys `auraUp` by the aura's SPELL ID, never by the entry that named it", function()
      -- E5 band 1 is `auraUp(1276166)`. A world answering only the ENTRY key must leave it
      -- unlit: an aura argument is a spell id, and resolving it through `Catalog.Subject`
      -- would look up `E5` in a table `Track` keys by spell id and read unknown forever.
      local byEntry = evaluate{
        affordable = H.map(true), auraUp = H.map(false, { E5 = true }), resource = 0,
      }
      assert.equal("MEDIUM", byEntry.byEntry.E5.tier)

      local bySpell = evaluate{
        affordable = H.map(true), auraUp = H.map(false, { [1276166] = true }), resource = 0,
      }
      assert.equal("HIGH", bySpell.byEntry.E5.tier)
      assert.equal(1, bySpell.byEntry.E5.band)
    end)
  end)

  --------------------------------------------------------------------------------
  -- A band names an ability, and may negate it
  --------------------------------------------------------------------------------
  describe("a band may name another entry's ability", function()
    it("lights Tyrant HIGH once the Dreadstalkers are on cooldown", function()
      -- `not ready(E2)` is "you cast the dogs and their cooldown is still running",
      -- which is the readable half of "the board is staged".
      local out = evaluate{ ready = H.map(true, { E2 = false }) }
      assert.equal("HIGH", out.byEntry.E1.tier)
      assert.equal(1, out.byEntry.E1.band)
    end)

    it("holds Tyrant at MEDIUM while the Dreadstalkers are still up to press", function()
      local out = evaluate{ ready = H.map(true) }
      assert.equal("MEDIUM", out.byEntry.E1.tier)
    end)

    it("stages the Grimoire into a ready Tyrant, from Tyrant's readiness and not its own", function()
      local staged = evaluate{ ready = H.map(true) }
      assert.equal("HIGH", staged.byEntry.E3.tier)
      local not_staged = evaluate{ ready = H.map(true, { E1 = false }) }
      assert.equal("MEDIUM", not_staged.byEntry.E3.tier)
    end)

    it("resolves `this` to the entry's own ability, never to the named one", function()
      local out = evaluate{ ready = H.map(false, { E1 = true }) }
      assert.equal("HIGH", out.byEntry.E1.tier, "E1's own `ready(this)` is E1's")
      assert.is_nil(out.byEntry.E3.tier, "E3 itself is not ready, whatever E1 is doing")
    end)

    it("keeps negation from rescuing a refused read", function()
      -- `not <unknown>` is unknown, never true. Getting this wrong is the one way a
      -- blind cap reads confident.
      assert.equal("unknown", ns.Tier.Term({ "ready", "E2", negate = true }, nil, H.blindWorld()))
      local out = evaluate{ ready = H.map(true, { E2 = "unknown" }) }
      assert.equal("MEDIUM", out.byEntry.E1.tier)
    end)

    it("refuses `elapsed` on a subject other than `this`, as the check does", function()
      local v = probe({ { tier = "HIGH", when = { { "elapsed", "E2", "<=", 12 } } } })
      assert.is_nil(v.tier)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Cues — offers, of two polarities
  --------------------------------------------------------------------------------
  describe("a cue is an offer, not a decision", function()
    it("hands the client a positive cue's channel and never the count", function()
      local out = evaluate{ ready = H.map(true) }
      local cue = out.byEntry.E8.cues[1]
      assert.equal("positive", cue.polarity)
      assert.equal("HIGH", cue.tier)
      assert.same({ "stacks", 296553, ">=", 6 }, cue.channel)
    end)

    it("withholds it when the gate precondition does not hold", function()
      local out = evaluate{ ready = H.map(false) }
      assert.same({}, out.byEntry.E8.cues)
    end)

    it("withholds it when the precondition refuses, exactly as a band fails", function()
      local out = evaluate{ ready = H.map("unknown") }
      assert.same({}, out.byEntry.E8.cues)
    end)

    it("offers Dreadstalkers' hold only once Tyrant is on cooldown", function()
      -- A ready Tyrant has a zero-remaining cooldown, which clears any `<= t` and would
      -- pin the marker on; `not ready(E1)` in the precondition is what stops that.
      local ready = evaluate{ ready = H.map(true), affordable = H.map(true) }
      assert.same({}, ready.byEntry.E2.cues)
      local coming = evaluate{ ready = H.map(true, { E1 = false }), affordable = H.map(true) }
      local cue = coming.byEntry.E2.cues[1]
      assert.equal("negative", cue.polarity)
      assert.is_nil(cue.tier)
      assert.same({ "cooldownRemaining", "E1", "<=", 20 }, cue.channel)
    end)

    it("keeps a hold out of the press count", function()
      -- Folding negatives into `cuesOffered` would report a press count containing holds.
      local out = evaluate{ ready = H.map(true, { E2 = false }), affordable = H.map(true) }
      assert.equal("negative", out.byEntry.E1.cues[1].polarity)
      assert.equal(1, out.holdsOffered)
      assert.equal(1, out.cuesOffered, "Implosion's is the only positive one lit")
    end)

    it("counts positives apart from HIGH bands, because nothing here saw the count", function()
      local out = evaluate{ ready = H.map(true) }
      assert.equal(1, out.cuesOffered)
      assert.equal(0, out.holdsOffered)
    end)
  end)

  describe("more than one thing can be HIGH at once", function()
    it("lights three at a staged Tyrant setup", function()
      -- Everything ready, shards banked: Dreadstalkers, the Grimoire and Hand of Gul'dan.
      local out = evaluate{ ready = H.map(true), affordable = H.map(true), resource = 5 }
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
      -- E5 band 1 needs the apex buff; a refusal must not promote it past the shard band.
      local out = evaluate{ affordable = H.map(true), auraUp = H.map("unknown"), resource = 0 }
      assert.equal("MEDIUM", out.byEntry.E5.tier)
    end)

    refusalCase("identity", function()
      local out = evaluate{ identity = H.map("unknown") }
      assert.is_nil(out.byEntry.E6.tier)
    end)

    refusalCase("resource", function()
      local out = evaluate{ affordable = H.map(true), resource = "unknown" }
      -- Band 2 needs shards >= 5 and must not fire blind; band 3 still holds.
      assert.equal("MEDIUM", out.byEntry.E5.tier)
    end)

    refusalCase("talent", function()
      local v = probe({ { tier = "HIGH", when = { { "talent", 999999 } } } }, { talent = H.map("unknown") })
      assert.is_nil(v.tier)
    end)

    refusalCase("combat", function()
      -- Out of combat `combat` answers false; unknown is the /reload case, and it fails.
      local when = { { tier = "HIGH", when = { { "combat" } } } }
      assert.equal("HIGH", probe(when, { combat = true }).tier)
      assert.is_nil(probe(when, { combat = false }).tier)
      assert.is_nil(probe(when, { combat = "unknown" }).tier)
    end)

    refusalCase("elapsed", function()
      local when = { { tier = "HIGH", when = { { "elapsed", "this", "<=", 12 } } } }
      assert.equal("HIGH", probe(when, { elapsed = H.map(4) }).tier)
      assert.is_nil(probe(when, { elapsed = H.map("unknown") }).tier)
    end)

    refusalCase("mode", function()
      -- `mode` is cap's own state rather than a game read, so it cannot be sealed — but
      -- it is still three-valued, and an unset mode must FAIL a band rather than
      -- defaulting to single-target and asserting an opinion nobody chose.
      local when = { { tier = "HIGH", when = { { "mode", "aoe" } } } }
      assert.is_nil(probe(when, { mode = "unknown" }).tier)
      assert.is_nil(probe(when, { mode = "single" }).tier)
      assert.equal("HIGH", probe(when, { mode = "aoe" }).tier)
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
