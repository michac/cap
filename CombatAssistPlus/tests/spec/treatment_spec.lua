-- treatment_spec.lua — the visual vocabulary, authored from spec.md §3.1's treatment
-- table rather than from the module.
--
-- The ladder block is the load-bearing one: §3.1 asks for an ordered ladder, and an
-- out-of-order rung breaks it silently — every individual treatment still looks correct,
-- and only the ladder is wrong.
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
    it("is ordered by brightness, HIGH to MEDIUM to LOW to none", function()
      local names = { "HIGH", "MEDIUM", "LOW", "none" }
      local last
      for _, name in ipairs(names) do
        local b = T.Brightness(T.Tier(name))
        if last then assert.is_true(b < last, name .. " is not dimmer than the tier above") end
        last = b
      end
    end)

    it("ranks the tiers with *none* lowest, so a shared row draws the higher of two", function()
      assert.is_true(T.Rank(T.Tier("HIGH")) > T.Rank(T.Tier("MEDIUM")))
      assert.is_true(T.Rank(T.Tier("MEDIUM")) > T.Rank(T.Tier("LOW")))
      assert.is_true(T.Rank(T.Tier("LOW")) > T.Rank(T.Tier("none")))
      assert.equal(T.Rank(T.Tier("none")), T.Rank(nil))
    end)

    it("gives every tier a ring and *none* the only veil — the LOW step is the ring itself", function()
      for _, name in ipairs(T.ORDER) do
        assert.is_not_nil(T.Tier(name).ring, name .. " lost its ring")
        assert.equal(0, T.Tier(name).veil)
      end
      assert.is_nil(T.Tier("none").ring)
      assert.is_true(T.Tier("none").veil > 0)
    end)
  end)

  describe("pulse — a second channel over the band, and a seizure floor", function()
    it("gives every tier a rate and *none* none at all", function()
      for _, name in ipairs(T.ORDER) do
        assert.is_not_nil(T.Pulse(T.Tier(name)), name .. " does not pulse")
      end
      assert.is_nil(T.Pulse(T.Tier("none")))
      assert.is_nil(T.Pulse(nil))
    end)

    it("keeps the three rates pairwise distinct — they must never align", function()
      local seen = {}
      for _, name in ipairs(T.ORDER) do
        local hz = T.Pulse(T.Tier(name)).hz
        assert.is_nil(seen[hz], name .. " shares a pulse rate with the tier above")
        seen[hz] = name
      end
    end)

    it("peaks at the tier's own alpha and troughs below it, one channel not two", function()
      local d = T.Tier("HIGH", 1)
      local p = T.Pulse(d)
      assert.equal(d.ring.a, p.to)
      assert.is_true(p.from < p.to)
      assert.equal(T.PULSE.trough, p.from / p.to)
    end)

    it("tracks the grade, so a graded entry peaks above an ungraded one", function()
      assert.is_true(T.Pulse(T.Tier("MEDIUM", 1)).to > T.Pulse(T.Tier("MEDIUM", 0)).to)
    end)

    it("halves a period per hertz, so a slower tier is a longer animation", function()
      assert.equal(0.5 / T.Pulse(T.Tier("LOW")).hz, T.Pulse(T.Tier("LOW")).seconds)
      assert.is_true(T.Pulse(T.Tier("LOW")).seconds > T.Pulse(T.Tier("HIGH")).seconds)
    end)

    it("gives a period the offsets are measured against, not a fixed number of seconds", function()
      for _, name in ipairs(T.ORDER) do
        local p = T.Pulse(T.Tier(name))
        assert.equal(p.seconds * 2, p.cycle, name .. "'s cycle is not the bounce round trip")
      end
    end)

    it("phases row N inside its own cycle, first row on time", function()
      assert.equal(0, T.Phase(1))
      assert.equal(T.Phase(1), T.Phase(nil))
      for n = 1, 40 do
        local frac = T.Phase(n)
        assert.is_true(frac >= 0 and frac < 1, "row " .. n .. " phased outside its cycle")
      end
    end)

    it("never lands two rows on the same phase — the seizure floor is the whole point", function()
      local seen = {}
      for n = 1, 40 do
        local key = ("%.4f"):format(T.Phase(n))
        assert.is_nil(seen[key], "row " .. n .. " starts in sync with row " .. tostring(seen[key]))
        seen[key] = n
      end
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

  describe("hold — the treatment that belongs to no tier", function()
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
    it("draws a positive HIGH cue in the HIGH treatment", function()
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

    it("refuses LOW its ink even though LOW draws a ring — that ring IS the hold slate", function()
      local ring = T.Tier("LOW").ring
      assert.same({ T.HOLD.hue.r, T.HOLD.hue.g, T.HOLD.hue.b }, { ring.r, ring.g, ring.b })
      assert.is_nil(T.Ink(T.Mark{ polarity = "positive", tier = "LOW" }))
    end)

    it("gives *none* no ink either, and survives a nil marker", function()
      assert.is_nil(T.Ink(T.Mark{ polarity = "positive", tier = "none" }))
      assert.is_nil(T.Ink(nil))
    end)

    it("keeps the hold hue clear of every tier that CAN ink a marker", function()
      for _, name in ipairs(T.ORDER) do
        local ring = T.Tier(name).ring
        if T.Ink(T.Tier(name)) then
          assert.is_false(ring.r == T.HOLD.hue.r and ring.g == T.HOLD.hue.g and ring.b == T.HOLD.hue.b)
        end
      end
    end)
  end)

  describe("Fill — what a §3.4 bar is drawn in", function()
    it("gives a tiered bar its own tier's hue and emphasis, the same as the icon", function()
      for _, name in ipairs(T.ORDER) do
        local ring = T.Tier(name).ring
        local r, g, b, a = T.Fill(T.Tier(name))
        assert.same({ ring.r, ring.g, ring.b, ring.a }, { r, g, b, a })
      end
    end)

    it("still fills a bar no band held — a cooldown counts down without an opinion", function()
      local r, g, b, a = T.Fill(T.Tier("none"))
      local rest = T.BAR.rest
      assert.same({ rest.r, rest.g, rest.b, rest.a }, { r, g, b, a })
      assert.same({ r, g, b, a }, { T.Fill(nil) })
    end)

    it("rests under every reachable LOW fill — *none* is the bottom rung of an ordered ladder", function()
      -- §3.1's surviving property: the ladder is ordered, and a bar has no ring, so the fill
      -- is the only carrier of the LOW -> none step. The resting slate IS LOW's hue, so
      -- "dimmer" is the alpha and nothing else; a resting fill inside LOW's band would draw
      -- a graded LOW and an opinion-less bar in the same pixels.
      local rr, rg, rb, ra = T.Fill(T.Tier("none"))
      local low = T.Tier("LOW").ring
      assert.same({ low.r, low.g, low.b }, { rr, rg, rb })
      for i = 0, 20 do
        local g = i / 20
        local _, _, _, a = T.Fill(T.Tier("LOW", g))
        assert.is_true(ra < a, ("the resting fill is not under LOW at grade %.2f"):format(g))
      end
    end)

    it("orders the four fills, none lowest, on the one scalar a bar has", function()
      local names = { "HIGH", "MEDIUM", "LOW", "none" }
      local last
      for _, name in ipairs(names) do
        local b = T.FillBrightness(T.Tier(name))
        if last then assert.is_true(b < last, name .. "'s fill is not dimmer than the tier above") end
        last = b
      end
    end)

    it("keeps the empty track darker than every fill on every channel", function()
      -- The bar's whole reading is filled-vs-empty, so the two halves have to differ on the
      -- colour and not only on where they stop.
      local track = T.BAR.track
      local names = { "HIGH", "MEDIUM", "LOW", "none" }
      for _, name in ipairs(names) do
        local r, g, b = T.Fill(T.Tier(name))
        assert.is_true(track.r < r and track.g < g and track.b < b,
          name .. " does not read against the empty track")
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
      assert.equal(T.Tier("none").veil, T.For(out.byEntry.E7).veil)
      assert.equal(T.Tier("LOW").ring.a, T.For(out.byEntry.E10).ring.a)
    end)

    -- Via `Rank`, never `Brightness`: comparing a graded HIGH against a graded LOW on one
    -- scalar is the band-separation claim §3.1 no longer makes.
    it("ranks Dreadstalkers above a demoted Demonbolt", function()
      local out = ns.Tier.Evaluate(bound, H.world{ proc = H.map(true), resource = 5 })
      assert.equal("HIGH", T.For(out.byEntry.E2).tier)
      assert.equal("LOW", T.For(out.byEntry.E7).tier)
      assert.is_true(T.Rank(T.For(out.byEntry.E2)) > T.Rank(T.For(out.byEntry.E7)))
    end)

    it("holds Dreadstalkers when its negative cue is offered, without dimming it", function()
      local out = ns.Tier.Evaluate(bound, H.world{ ready = H.map(true, { E1 = false }) })
      local d = T.For(out.byEntry.E2)
      assert.is_true(d.hold)
      assert.equal("HIGH", d.tier)
    end)
  end)
end)
