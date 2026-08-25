-- The generated style and the arithmetic Paint does with it. No test here asserts a colour,
-- a rate or a size: those are the shelf's, and pinning one would make taste a platform rule.
local H = require("CombatAssistPlus.tests.mock_ns")

local MEDIA = "CombatAssistPlus/Media/badges/"
local RING_MEDIA = "CombatAssistPlus/Media/"

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
    assert.is_string(S.badges.texture_root)
    assert.is_string(S.badges.plate.texture)
    assert.is_string(S.badges.halo_texture)
    assert.equal(3, #S.ready.rgb)
    assert.is_number(S.ready.line_px)
    assert.is_number(S.ready.alpha)
    for key, cue in pairs(S.cues) do
      assert.is_number(cue.rank, key .. " has no rank")
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

  it("declares ONE scan treatment and no hue ladder behind it", function()
    assert.is_nil(ns.Style.lanes, "the four-hue lane table should be gone, not emptied")
    assert.is_nil(ns.Treatment.LANE, "the tier→lane map should be gone, not mapped to itself")
    -- Membership puts the row in the scan; nothing else does. That is the whole contract.
    assert.is_true(ns.Treatment.For{ member = true }.scan)
    assert.is_false(ns.Treatment.For{ member = false }.scan)
    assert.is_false(ns.Treatment.For{}.scan)
  end)

  it("derives badge geometry from the icon, and the stack steps clear of itself", function()
    local S, g = ns.Style, ns.Paint.Geometry()
    assert.equal(S.badges.diameter_pct / 100 * S.surfaces.icon_px, g.diameter)
    assert.equal(g.diameter + S.badges.padding_px, g.step)
    assert.is_true(g.sprite < g.diameter)
    assert.is_true(g.plate > g.diameter)

    -- The stack FLOWS down the right edge: index 0 hangs off the corner, and each further
    -- badge keeps the same x and steps one `step` lower. No fixed slots, so no ceiling.
    local x0, y0 = ns.Paint.StackOffset(0)
    local x1, y1 = ns.Paint.StackOffset(1)
    local x4, y4 = ns.Paint.StackOffset(4)
    assert.equal(x0, x1)
    assert.equal(x0, x4)
    assert.equal(y0 - g.step, y1)
    assert.equal(y0 - g.step * 4, y4)
  end)

  it("overhangs less than the row gap, so a badge cannot land on the next icon", function()
    assert.is_true(ns.Style.badges.overhang_px < ns.Style.surfaces.row_gap_px)
  end)

  it("steps no frames from Lua — every sheet walk is the client's FlipBook", function()
    -- The frame walk left with the ticker: motion baked into AnimationGroups is the one kind
    -- that keeps rendering on a handed-over region (security-taint §3.5.3), so Paint holds no
    -- per-tick stepper and no clock arithmetic to test.
    assert.is_nil(ns.Paint.FrameIndex, "Paint.FrameIndex outlived the ticker it stepped for")
    local f = assert(io.open("CombatAssistPlus/Paint.lua", "rb"))
    local src = f:read("*a"); f:close()
    assert.is_nil(src:find("C_Timer.NewTicker", 1, true),
      "Paint.lua re-acquired a ticker — motion belongs to AnimationGroups")
  end)

  it("keeps no arrival machinery anywhere — the scan edge is still", function()
    -- The frame walk, its sheet coordinates and its rate limiter went with the lane border in
    -- V1's retirement. The ANIMATION went with the lab's arrival experiments, which were judged
    -- and deleted: `Paint.Arrival`, `tokens.ring`, `tokens.motion`, `tokens.arrival` and
    -- Media/ring.tga are all gone, so there is no arrival left in either half of the addon.
    for _, gone in ipairs({ "ShouldSnap", "ShouldReplay", "Arrival", "ArrivalFrame", "FrameCoords",
                            "RingBand", "RingTexture", "Ring", "Flash", "Ghost", "Halo" }) do
      assert.is_nil(ns.Paint[gone], "Paint." .. gone .. " outlived the treatment that used it")
    end
    for _, gone in ipairs({ "ring", "motion", "arrival" }) do
      assert.is_nil(ns.Style[gone], "ns.Style." .. gone .. " outlived its last reader")
    end
    assert.is_false(exists(RING_MEDIA .. "ring.tga"), "Media/ring.tga outlived its subject")
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
