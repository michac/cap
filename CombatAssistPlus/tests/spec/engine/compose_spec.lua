-- The composition seam: catalog cue -> verdict cue set -> scan membership + badges.
-- No assertion here fixes a colour, a slot or a rate — those are the shelf's.
local H = require("CombatAssistPlus.tests.mock_ns")

--- A one-entry catalog whose markers are whatever the test needs, resolved against a real
--- recorded row set so nothing here fakes an API.
local function withMarkers(ns, markers)
  local cat = H.copy(H.catalogBySpec(ns, 267))
  cat.entries[1].markers = markers
  return cat, ns.Catalog.Resolve(cat, H.destructionRows())
end

describe("engine / composition", function()
  local ns
  before_each(function() ns = H.fresh() end)

  it("unions two markers naming one cue into a single badge", function()
    local cat, resolved = withMarkers(ns, {
      { id = "a", cue = "blocked", when = { { "ready", "conflagrate" } } },
      { id = "b", cue = "blocked", when = { { "ready", "conflagrate" } } },
    })
    assert.same({}, ns.Catalog.Check(cat))
    local v = ns.Signal.Evaluate(resolved, H.world()).byEntry.conflagrate
    assert.same({ "a", "b" }, v.markers)
    assert.same({ "blocked" }, v.cues)
  end)

  it("orders a cue set by shelf slot, not by marker order", function()
    local _, resolved = withMarkers(ns, {
      { id = "second", cue = "starved", when = { { "ready", "conflagrate" } } },
      { id = "first", cue = "blocked", when = { { "ready", "conflagrate" } } },
    })
    local cues = ns.Signal.Evaluate(resolved, H.world()).byEntry.conflagrate.cues
    local slots = {}
    for i, key in ipairs(cues) do slots[i] = ns.Style.cues[key].slot end
    assert.is_true(slots[1] < slots[2], "cue set is not in slot order")
  end)

  describe("the graded cue", function()
    local plan = {
      id = "overflow", cue = "overcap",
      display = { kind = "sealed-power-percent", power = "Fury", generation = 15 },
    }

    it("binds only a well-formed sealed power display", function()
      local bound = ns.Channel.PowerPlan(plan)
      assert.equal("Fury", bound.power)
      assert.equal("overcap", bound.cue)
      assert.equal(15, bound.generation)
      -- A readable marker, another sealed kind, and a cueless one are all not this.
      assert.is_nil(ns.Channel.PowerPlan{ id = "x", cue = "overcap", when = { { "ready", "x" } } })
      assert.is_nil(ns.Channel.PowerPlan{ id = "x", cue = "overcap",
        display = { kind = "player-aura-stacks", ability = "x", min = 2 } })
      local cueless = H.copy(plan)
      cueless.cue = nil
      assert.is_nil(ns.Channel.PowerPlan(cueless))
    end)

    it("breaks the curve where one more cast would overflow", function()
      -- The catalog authors generation; the client owns the max. Nothing here is a percentage.
      assert.equal((170 - 15) / 170, ns.Channel.PowerBreak(15, 170))
      -- No honest break: a refused max, a generator that fills the bar, a missing number.
      assert.is_nil(ns.Channel.PowerBreak(15, nil))
      assert.is_nil(ns.Channel.PowerBreak(15, 0))
      assert.is_nil(ns.Channel.PowerBreak(200, 170))
      assert.is_nil(ns.Channel.PowerBreak(nil, 170))
    end)

    it("authors points that read the same under either percentage scale", function()
      local brk = ns.Channel.PowerBreak(15, 170)
      local points = ns.Channel.PowerPoints(brk)
      -- Step holds the PREVIOUS point's value, so each pair is (break, on) then (fall, off).
      local previous
      for _, point in ipairs(points) do
        if previous then assert.is_true(point[1] > previous, "points must ascend in x") end
        previous = point[1]
      end
      assert.equal(0, points[1][2])
      assert.equal(brk, points[2][1])
      assert.equal(brk * 100, points[#points][1])
      assert.equal(1, points[#points][2])
      assert.is_nil(ns.Channel.PowerPoints(nil))
    end)

    it("is inert, not broken, on a client with no curve support", function()
      -- The busted harness has no C_CurveUtil, no Enum and no UnitPowerPercent — which is
      -- exactly the missing-piece client the feature gate exists for.
      local armed, status = ns.Channel.ArmPower(ns.Channel.PowerPlan(plan))
      assert.is_nil(armed)
      assert.equal("refused", status)
      assert.is_false(ns.Channel.PowerAlpha(nil))
      assert.is_false(ns.Channel.PowerAlpha{ curve = {} })
    end)
  end)

  describe("the graded hold", function()
    local plan = {
      id = "awaits", cue = "blocked",
      display = { kind = "sealed-cooldown-range", ability = "eye_beam", within = 4 },
    }

    it("binds only a well-formed sealed cooldown range", function()
      local bound = ns.Channel.HoldPlan(plan)
      assert.equal("eye_beam", bound.ability)
      assert.equal(4, bound.within)
      assert.equal("blocked", bound.cue)
      local zero = H.copy(plan)
      zero.display.within = 0
      assert.is_nil(ns.Channel.HoldPlan(zero))
      assert.is_nil(ns.Channel.HoldPlan{ id = "x", cue = "blocked", when = { { "ready", "x" } } })
    end)

    it("bands the window between running and beyond it", function()
      local points = ns.Channel.HoldPoints(4)
      -- Nothing at zero remaining — a dependency that is UP is not one that is imminent.
      assert.equal(0, points[1][1])
      assert.equal(0, points[1][2])
      assert.equal(1, points[2][2])
      assert.is_true(points[2][1] > 0 and points[2][1] < points[3][1])
      assert.equal(4, points[3][1])
      assert.equal(0, points[3][2])
      assert.is_nil(ns.Channel.HoldPoints(0))
      assert.is_nil(ns.Channel.HoldPoints(nil))
    end)

    it("is inert, not broken, without curves or a bound dependency", function()
      local abilities = { eye_beam = { id = "eye_beam", spell = 198013 } }
      local armed, status = ns.Channel.ArmHold(ns.Channel.HoldPlan(plan), abilities)
      assert.is_nil(armed)
      assert.equal("refused", status)
      -- An undeclared dependency refuses before the client is asked anything at all.
      assert.is_nil((ns.Channel.ArmHold(ns.Channel.HoldPlan(plan), {})))
      assert.is_false(ns.Channel.HoldAlpha(nil))
    end)

    it("routes both graded sources through one plan, arm and evaluate", function()
      assert.equal("sealed-cooldown-range", ns.Channel.GradedPlan(plan).kind)
      assert.equal("sealed-power-percent", ns.Channel.GradedPlan{
        id = "overflow", cue = "overcap",
        display = { kind = "sealed-power-percent", power = "Fury", generation = 15 },
      }.kind)
      -- A readable marker is not a graded one, and neither is the aura channel's display.
      assert.is_nil(ns.Channel.GradedPlan{ id = "x", cue = "blocked", when = { { "ready", "x" } } })
      assert.equal("refused", select(2, ns.Channel.ArmGraded(ns.Channel.GradedPlan(plan), {})))
      assert.is_false(ns.Channel.GradedAlpha(nil))
    end)
  end)

  it("refuses two cues that would want the same badge slot", function()
    local cat = withMarkers(ns, {
      { id = "a", cue = "starved", when = { { "ready", "conflagrate" } } },
      { id = "b", cue = "overcap", when = { { "ready", "conflagrate" } } },
    })
    assert.equal(ns.Style.cues.starved.slot, ns.Style.cues.overcap.slot)
    assert.is_truthy(H.checks(ns.Catalog.Check(cat)).cue)
  end)

  it("refuses a cue the generated shelf does not declare", function()
    local cat = withMarkers(ns, {
      { id = "a", cue = "encouraging", when = { { "ready", "conflagrate" } } },
    })
    assert.is_truthy(H.checks(ns.Catalog.Check(cat)).cue)
  end)

  it("keeps `cue` optional, so a marker may inform without drawing", function()
    local cat, resolved = withMarkers(ns, {
      { id = "quiet", when = { { "ready", "conflagrate" } } },
    })
    assert.same({}, ns.Catalog.Check(cat))
    local v = ns.Signal.Evaluate(resolved, H.world()).byEntry.conflagrate
    assert.same({ "quiet" }, v.markers)
    assert.same({}, v.cues)
    assert.same({}, ns.Treatment.For(v).cues)
  end)

  -- The elimination walk reads off the badge alone: the press is the leftmost row that is
  -- neither swiped nor wearing a NEGATIVE badge. That only decides anything while every cue
  -- declares a polarity and the positive one is unique.
  it("keeps the cue vocabulary polarised, with exactly one positive cue", function()
    local positive = {}
    for key, cue in pairs(ns.Style.cues) do
      assert.is_string(cue.polarity, key .. " declares no polarity")
      if cue.polarity == "positive" then positive[#positive + 1] = key end
    end
    assert.equal(1, #positive, "the reading model allows exactly one positive cue")
  end)

  it("carries a mixed cue set through whole, so the negative badge is still there to read",
    function()
      local d = ns.Treatment.For{ tier = "ROTATION", cues = { "capped", "blocked" } }
      assert.same({ "capped", "blocked" }, d.cues)
      assert.is_true(d.scan)
    end)

  it("offers no cue at all when the reads refuse", function()
    local _, resolved = withMarkers(ns, {
      { id = "a", cue = "blocked", when = { { "ready", "conflagrate" } } },
    })
    local v = ns.Signal.Evaluate(resolved, H.blindWorld()).byEntry.conflagrate
    assert.same({}, v.cues)
    assert.same({}, ns.Treatment.For(v).cues)
  end)

  it("names which tier went blind rather than only that one did", function()
    local cat = H.catalogBySpec(ns, 267)
    local resolved = ns.Catalog.Resolve(cat, H.destructionRows())
    local v = ns.Signal.Evaluate(resolved, H.blindWorld()).byEntry.conflagrate
    assert.is_nil(v.tier)
    assert.equal(cat.entries[1].bands[1].tier, v.blindTier)
  end)
end)
