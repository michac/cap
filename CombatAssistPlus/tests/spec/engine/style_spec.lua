-- The generated style and the arithmetic Paint does with it. No test here asserts a colour,
-- a rate or a size: those are the shelf's, and pinning one would make taste a platform rule.
local H = require("CombatAssistPlus.tests.mock_ns")

local MEDIA = "CombatAssistPlus/Media/badges/"

local function exists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

describe("engine / style", function()
  local ns
  before_each(function() ns = H.fresh() end)

  it("carries every key Paint reads", function()
    local S = ns.Style
    assert.is_number(S.surfaces.icon_px)
    assert.is_number(S.surfaces.row_gap_px)
    assert.is_number(S.veil.alpha)
    assert.is_table(S.veil.rgb)
    assert.is_number(S.arrival.from_scale)
    assert.is_number(S.arrival.duration_s)
    assert.is_string(S.arrival.smoothing)
    assert.is_string(S.badges.texture_root)
    assert.is_string(S.badges.plate.texture)
    assert.is_string(S.badges.halo_texture)
    for lane, spec in pairs(S.lanes) do
      assert.is_number(spec.thickness_px, lane .. " has no thickness")
      assert.equal(3, #spec.rgb, lane .. " needs an rgb triple")
    end
    for key, cue in pairs(S.cues) do
      assert.is_number(cue.slot, key .. " has no slot")
      assert.is_number(cue.duration_s, key .. " has no duration")
      assert.is_true(#cue.frames > 0, key .. " names no frames")
      if cue.glow then
        assert.is_number(cue.glow.hz)
        assert.is_number(cue.glow.alpha_min)
        assert.is_number(cue.glow.alpha_max)
        assert.is_number(cue.glow.scale)
      end
    end
  end)

  it("names every engine tier after a lane the style declares", function()
    assert.is_nil(ns.Treatment.LANE, "the tier→lane map should be gone, not mapped to itself")
    for _, lane in ipairs(ns.Treatment.ORDER) do
      assert.is_table(ns.Style.lanes[lane], lane .. " is not a declared lane")
      assert.equal(lane, ns.Treatment.For{ tier = lane }.lane)
    end
    assert.is_false(ns.Treatment.For{}.emphasized)
    assert.is_false(ns.Treatment.For{ tier = "NOSUCHTIER" }.emphasized)
  end)

  it("derives badge geometry from the icon, and the slots step clear of each other", function()
    local S, g = ns.Style, ns.Paint.Geometry()
    assert.equal(S.badges.diameter_pct / 100 * S.surfaces.icon_px, g.diameter)
    assert.equal(g.diameter + S.badges.padding_px, g.step)
    assert.is_true(g.sprite < g.diameter)
    assert.is_true(g.plate > g.diameter)

    -- Slot 1 hangs off the corner; 2 steps left along the top, 3 down the right.
    local x1, y1 = ns.Paint.SlotOffset(1)
    local x2, y2 = ns.Paint.SlotOffset(2)
    local x3, y3 = ns.Paint.SlotOffset(3)
    assert.equal(y1, y2)
    assert.equal(x1, x3)
    assert.equal(x1 - g.step, x2)
    assert.equal(y1 - g.step, y3)
  end)

  it("overhangs less than the row gap, so a badge cannot land on the next icon", function()
    assert.is_true(ns.Style.badges.overhang_px < ns.Style.surfaces.row_gap_px)
  end)

  it("walks a cue's frames the way the artifact does", function()
    local step = 0.5
    -- REPEAT wraps; BOUNCE turns around at each end.
    assert.equal(1, ns.Paint.FrameIndex(3, "REPEAT", 0.0, step))
    assert.equal(3, ns.Paint.FrameIndex(3, "REPEAT", 1.0, step))
    assert.equal(1, ns.Paint.FrameIndex(3, "REPEAT", 1.5, step))
    assert.equal(2, ns.Paint.FrameIndex(3, "BOUNCE", 1.5, step))
    assert.equal(1, ns.Paint.FrameIndex(3, "BOUNCE", 2.0, step))
    -- A single-frame cue is a still image, and a zero-length step never divides.
    assert.equal(1, ns.Paint.FrameIndex(1, "REPEAT", 99, step))
    assert.equal(1, ns.Paint.FrameIndex(4, "REPEAT", 99, 0))
  end)

  it("snaps on arrival, and on nothing else", function()
    local d = ns.Style.arrival.duration_s
    -- Absent → present, and one lane → another, are both arrivals.
    assert.is_true(ns.Paint.ShouldSnap({}, "ROTATION", 100))
    assert.is_true(ns.Paint.ShouldSnap({ lane = "ROTATION" }, "COOLDOWN", 100))
    -- Repainting the same lane at 10 Hz is not.
    assert.is_false(ns.Paint.ShouldSnap({ lane = "ROTATION" }, "ROTATION", 100))
    -- Neither is the first draw after a rebuild or a resume, nor a lane-less paint.
    assert.is_false(ns.Paint.ShouldSnap({ silent = true }, "ROTATION", 100))
    assert.is_false(ns.Paint.ShouldSnap({}, nil, 100))
    -- Rate limited per row to the snap's own duration, so a flickering lane cannot stack.
    assert.is_false(ns.Paint.ShouldSnap({ snappedAt = 100 }, "ROTATION", 100 + d / 2))
    assert.is_true(ns.Paint.ShouldSnap({ snappedAt = 100 }, "ROTATION", 100 + d * 2))
  end)

  it("ships a texture for every frame the cue vocabulary names", function()
    for key, cue in pairs(ns.Style.cues) do
      for _, frame in ipairs(cue.frames) do
        assert.is_true(exists(MEDIA .. frame .. ".tga"),
          key .. " names frame " .. frame .. " with no texture in Media/badges")
      end
    end
    -- The two shapes CSS gets for free: a missing one fails silently in client.
    assert.is_true(exists(MEDIA .. ns.Style.badges.plate.texture .. ".tga"))
    assert.is_true(exists(MEDIA .. ns.Style.badges.halo_texture .. ".tga"))
  end)
end)
