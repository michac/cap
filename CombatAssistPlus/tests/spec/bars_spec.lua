-- bars_spec.lua — the §3.4 cooldown roster's pure seam.
--
-- Authored from ../../../../specs/spec.md §3.4 and ../../../../specs/demonology/catalog.md
-- §4, never from Bars.lua. Everything below is about WHICH bars, in WHAT order and drawn in
-- WHAT — the frame work around it is not testable at a desk and is not faked here.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("Bars", function()
  local ns, Bars, cat

  before_each(function()
    ns = H.fresh()
    Bars = H.withBars(ns)
    cat = H.catalog(ns)
  end)

  --- The verdicts a plan is built from, against the 21 rows the client recorded.
  local function verdicts(world)
    local rows = H.rows()
    local _, resolved = ns.Catalog.CheckBound(cat, rows)
    return ns.Tier.Evaluate(resolved, world or H.world())
  end

  local function ids(plan)
    local out = {}
    for i, desc in ipairs(plan) do out[i] = desc.id end
    return out
  end

  describe("the roster catalog.md §4 declares", function()
    it("is Tyrant, Dreadstalkers, Grimoire, Implosion — in that order", function()
      assert.same({ "E1", "E2", "E3", "E8" }, cat.bars)
    end)

    it("gives Implosion a bar and Summon Doomguard none", function()
      -- §4: E8's press is gated by its 15 s cooldown once the imp count saturates, and E4
      -- binds no row on this build, so a Doomguard bar would draw nothing at all.
      local seen = {}
      for _, id in ipairs(cat.bars) do seen[id] = true end
      assert.is_true(seen.E8)
      assert.is_nil(seen.E4)
    end)

    it("is the catalog's only declaration of it — no entry carries a `bar` flag", function()
      for _, e in ipairs(cat.entries) do
        assert.is_nil(e.bar, e.id .. " declares `bar`; the order lives in `bars` and a flag carries none")
      end
    end)
  end)

  describe("Plan", function()
    it("returns one descriptor per declared bar, in the declared order", function()
      assert.same({ "E1", "E2", "E3", "E8" }, ids(Bars.Plan(cat.bars, verdicts())))
    end)

    it("follows the declaration's order rather than any order of its own", function()
      -- The order is part of the declaration because a panel stacks: a plan that sorted, or
      -- that walked the entries, would read correct against the roster as authored today.
      assert.same({ "E8", "E3", "E2", "E1" }, ids(Bars.Plan({ "E8", "E3", "E2", "E1" }, verdicts())))
    end)

    it("plans nothing for a build whose catalog declares no roster", function()
      assert.same({}, Bars.Plan(nil, verdicts()))
    end)

    it("carries the BOUND row's spell, not the authored one", function()
      -- E3 covers both halves of its choice node and binds through `alt` on a Fel Ravager
      -- build, so the authored id is then the wrong half — and the wrong cooldown to ask
      -- the client about.
      local rows = H.rows()
      for _, row in ipairs(rows) do
        if row.spellIDs[1276452] then
          row.spellIDs = { [1276467] = true }
          row.primary, row.base = 1276467, 1276467
        end
      end
      local _, resolved = ns.Catalog.CheckBound(cat, rows)
      local plan = Bars.Plan(cat.bars, ns.Tier.Evaluate(resolved, H.world()))
      for _, desc in ipairs(plan) do
        if desc.id == "E3" then
          assert.equal(1276467, desc.spellID)
          return
        end
      end
      error("E3 was not planned")
    end)

    it("names an entry that did not bind and gives it no spell", function()
      -- Summon Doomguard is authored and drops at bind on this build (catalog.md O3). A bar
      -- for it must be nameable as such, not silently absent — the surface draws `nobind`.
      local plan = Bars.Plan({ "E1", "E4" }, verdicts())
      assert.same({ "E1", "E4" }, ids(plan))
      assert.is_number(plan[1].spellID)
      assert.is_nil(plan[2].spellID)
    end)

    it("takes each bar's treatment from its own tier", function()
      local plan = Bars.Plan(cat.bars, verdicts())
      local byID = {}
      for _, desc in ipairs(plan) do byID[desc.id] = desc end
      -- E2 is HIGH on a ready, affordable Dreadstalkers; E8 is MEDIUM on a ready Implosion.
      assert.equal("HIGH", byID.E2.tier)
      assert.equal("MEDIUM", byID.E8.tier)
      assert.same(ns.Treatment.Tier("HIGH").ring, byID.E2.treatment.ring)
      assert.same(ns.Treatment.Tier("MEDIUM").ring, byID.E8.treatment.ring)
    end)

    it("still plans a bar for an entry no band held — a cooldown counts down regardless", function()
      -- The case that matters most in play: E1/E2/E3 all need `ready(this)`, so the whole
      -- roster is tier-less for exactly the stretch its bar has something to show.
      local plan = Bars.Plan(cat.bars, verdicts(H.blindWorld()))
      assert.equal(4, #plan)
      for _, desc in ipairs(plan) do
        assert.is_nil(desc.tier)
        assert.is_number(desc.spellID)
        assert.is_nil(desc.treatment.ring)
      end
    end)
  end)
end)
