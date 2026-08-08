-- treatment_spec.lua — the visual vocabulary, authored from spec.md §3.1's treatment
-- table rather than from the module.
--
-- The band-disjointness block is the load-bearing one: "a grade never changes the tier"
-- is a promise about arithmetic, and an overlapping band breaks it silently — every
-- individual treatment still looks correct, and only the ladder is wrong.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("Treatment", function()
  local ns, T

  before_each(function()
    ns = H.fresh()
    T = ns.Treatment
  end)

  local function verdict(over)
    local v = { entry = "P", tier = nil, cues = {} }
    for k, val in pairs(over or {}) do v[k] = val end
    return v
  end

  describe("the ladder", function()
    it("is monotone in brightness, HIGH to MEDIUM to LOW to none", function()
      local names = { "HIGH", "MEDIUM", "LOW", "none" }
      local last
      for _, name in ipairs(names) do
        local b = T.Brightness(T.Tier(name))
        if last then assert.is_true(b < last, name .. " is not dimmer than the tier above") end
        last = b
      end
    end)

    it("is monotone in ring thickness too, so the ladder survives in greyscale", function()
      assert.is_true(T.Tier("HIGH").ring.thickness > T.Tier("MEDIUM").ring.thickness)
    end)

    it("draws no ring below MEDIUM — LOW and none are veils", function()
      assert.is_nil(T.Tier("LOW").ring)
      assert.is_nil(T.Tier("none").ring)
    end)

    it("keeps LOW visible: its veil is lighter than none's", function()
      assert.is_true(T.Tier("LOW").veil > 0)
      assert.is_true(T.Tier("LOW").veil < T.Tier("none").veil)
    end)
  end)

  describe("grade — emphasis within a tier, never across one", function()
    it("moves a tier's brightness between its dim and bright ends", function()
      assert.is_true(T.Brightness(T.Tier("HIGH", 1)) > T.Brightness(T.Tier("HIGH", 0)))
      assert.is_true(T.Brightness(T.Tier("LOW", 1)) > T.Brightness(T.Tier("LOW", 0)))
    end)

    it("puts an ungraded tier between its own two ends", function()
      for _, name in ipairs(T.ORDER) do
        local mid = T.Brightness(T.Tier(name))
        assert.is_true(mid > T.Brightness(T.Tier(name, 0)), name .. " ungraded is not above its floor")
        assert.is_true(mid < T.Brightness(T.Tier(name, 1)), name .. " ungraded is not below its ceiling")
      end
    end)

    it("keeps a fully-graded MEDIUM below the DIMMEST HIGH, graded or not", function()
      assert.is_true(T.Brightness(T.Tier("MEDIUM", 1)) < T.Brightness(T.Tier("HIGH", 0)))
    end)

    it("gives every tier a band disjoint from the next one down", function()
      local names = { "HIGH", "MEDIUM", "LOW" }
      for i = 1, #names - 1 do
        local floor = T.Brightness(T.Tier(names[i], 0))
        local ceiling = T.Brightness(T.Tier(names[i + 1], 1))
        assert.is_true(ceiling < floor, names[i + 1] .. " can reach into " .. names[i])
      end
      assert.is_true(T.Brightness(T.Tier("none")) < T.Brightness(T.Tier("LOW", 0)))
    end)

    it("clamps a grade outside 0..1 rather than escaping the band", function()
      assert.equal(T.Brightness(T.Tier("HIGH", 1)), T.Brightness(T.Tier("HIGH", 4)))
      assert.equal(T.Brightness(T.Tier("HIGH", 0)), T.Brightness(T.Tier("HIGH", -4)))
    end)
  end)

  describe("For — one verdict to one descriptor", function()
    it("draws a verdict with no tier as the none veil, never as nothing", function()
      local d = T.For(verdict())
      assert.is_nil(d.ring)
      assert.equal(T.Tier("none").veil, d.veil)
    end)

    it("survives a nil verdict the same way", function()
      assert.equal(T.Tier("none").veil, T.For(nil).veil)
    end)

    it("applies a RESOLVED grade to the ring and reports the number", function()
      local d = T.For(verdict{ tier = "MEDIUM", grade = { channel = "resource", value = 1 } })
      assert.equal(1, d.grade)
      assert.equal(T.Tier("MEDIUM", 1).ring.a, d.ring.a)
    end)

    it("passes a CHANNEL grade through untouched and draws the tier ungraded", function()
      local g = { channel = "cooldownRemaining", of = "this" }
      local d = T.For(verdict{ tier = "HIGH", grade = g })
      assert.equal(g, d.grade)
      assert.equal(T.Tier("HIGH").ring.a, d.ring.a)
    end)

    it("carries no grade field when the entry declared none", function()
      assert.is_nil(T.For(verdict{ tier = "HIGH" }).grade)
    end)
  end)

  describe("hold — the one shape in the vocabulary", function()
    it("is set by a negative cue", function()
      assert.is_true(T.For(verdict{ tier = "HIGH", cues = { { polarity = "negative" } } }).hold)
    end)

    it("is set by nothing else — not a positive cue, not a tier, not a grade", function()
      assert.is_false(T.For(verdict{ tier = "HIGH" }).hold)
      assert.is_false(T.For(verdict{ cues = { { polarity = "positive", tier = "HIGH" } } }).hold)
      assert.is_false(T.For(verdict{ tier = "LOW", grade = { channel = "resource", value = 0 } }).hold)
    end)

    it("never changes the tier treatment it sits on", function()
      local plain = T.For(verdict{ tier = "MEDIUM" })
      local held = T.For(verdict{ tier = "MEDIUM", cues = { { polarity = "negative" } } })
      assert.equal(plain.ring.a, held.ring.a)
      assert.equal(plain.veil, held.veil)
    end)
  end)

  describe("Mark — what a cue's marker is drawn in", function()
    it("draws a positive HIGH cue in the HIGH treatment, not a second language", function()
      local m = T.Mark{ polarity = "positive", tier = "HIGH" }
      assert.same(T.Tier("HIGH"), m)
    end)

    it("draws a positive MEDIUM cue in the MEDIUM treatment", function()
      assert.same(T.Tier("MEDIUM"), T.Mark{ polarity = "positive", tier = "MEDIUM" })
    end)

    it("draws a negative cue in the hold treatment, which is no tier", function()
      local m = T.Mark{ polarity = "negative" }
      assert.is_true(m.hold)
      assert.is_nil(m.tier)
      assert.is_nil(m.ring)
    end)

    it("inks a positive cue in its tier's own hue and emphasis", function()
      local r, g, b, a = T.Ink(T.Mark{ polarity = "positive", tier = "HIGH" })
      local ring = T.Tier("HIGH").ring
      assert.same({ ring.r, ring.g, ring.b, ring.a }, { r, g, b, a })
    end)

    it("inks a negative cue in the hold slate", function()
      local r, g, b, a = T.Ink(T.Mark{ polarity = "negative" })
      assert.same({ T.HOLD.hue.r, T.HOLD.hue.g, T.HOLD.hue.b, T.HOLD.alpha }, { r, g, b, a })
    end)

    it("gives a veil-only tier no ink at all — a marker there has no colour to take", function()
      assert.is_nil(T.Ink(T.Mark{ polarity = "positive", tier = "LOW" }))
      assert.is_nil(T.Ink(nil))
    end)

    it("keeps the hold hue clear of every tier's hue", function()
      for _, name in ipairs(T.ORDER) do
        local ring = T.Tier(name).ring
        if ring then
          assert.is_false(ring.r == T.HOLD.hue.r and ring.g == T.HOLD.hue.g and ring.b == T.HOLD.hue.b)
        end
      end
    end)
  end)

  describe("the Demonology catalog, drawn", function()
    local cat, bound

    before_each(function()
      cat = H.catalog(ns)
      local _, resolved = ns.Catalog.CheckBound(cat, H.rows())
      bound = resolved
    end)

    it("gives every bound entry a descriptor, blind or not", function()
      local out = ns.Tier.Evaluate(bound, H.blindWorld())
      for _, item in ipairs(bound.entries) do
        local d = T.For(out.byEntry[item.entry.id])
        assert.is_true(d.ring ~= nil or d.veil > 0, item.entry.id .. " drew nothing at all")
      end
    end)

    it("recedes the whole roster when every gate refuses, except the floor", function()
      local out = ns.Tier.Evaluate(bound, H.blindWorld())
      assert.is_nil(T.For(out.byEntry.E7).ring)
      assert.equal(T.Tier("LOW").veil, T.For(out.byEntry.E10).veil)
    end)

    it("lights Dreadstalkers brighter than a demoted Demonbolt", function()
      local out = ns.Tier.Evaluate(bound, H.world{ proc = H.map(true), resource = 5 })
      assert.is_true(T.Brightness(T.For(out.byEntry.E2)) > T.Brightness(T.For(out.byEntry.E7)))
    end)

    it("holds Dreadstalkers when its negative cue is offered, without dimming it", function()
      local out = ns.Tier.Evaluate(bound, H.world{ ready = H.map(true, { E1 = false }) })
      local d = T.For(out.byEntry.E2)
      assert.is_true(d.hold)
      assert.equal("HIGH", d.tier)
    end)
  end)
end)
