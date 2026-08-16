-- Part 7's generated data, and the arithmetic the gallery draws it with. Nothing here asserts a
-- colour, a phase or a rate: the lab decides nothing, and pinning its taste would be worse than
-- pinning the style's. What is pinned is the contract the gallery needs to draw an entry at all.
local H = require("CombatAssistPlus.tests.mock_ns")

local LAB_MEDIA = "CombatAssistPlus/Media/lab/"

local function exists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

local function entries(ns)
  local out = {}
  for key, entry in pairs(ns.LabStyle) do
    if key:sub(1, 1) ~= "_" then out[key] = entry end
  end
  return out
end

describe("engine / lab", function()
  local ns
  before_each(function()
    ns = H.fresh()
    H.load(ns, "Lab.lua")
  end)

  it("gives every entry an `asks` and a treatment the gallery can dispatch on", function()
    local any = false
    for key, entry in pairs(entries(ns)) do
      any = true
      assert.is_string(entry.asks, key .. " asks nothing, so it is decoration (Part 7)")
      assert.is_string(entry.draws, key .. " names no `draws`, so the gallery draws nothing")
      assert.is_string(entry.title, key .. " has no title")
    end
    assert.is_true(any, "an empty lab is legal, but then this file has nothing to protect")
  end)

  it("ships the sheet every striped entry draws with", function()
    local sheet = ns.LabStyle._sheet
    if not sheet then return end
    assert.is_true(exists(LAB_MEDIA .. sheet.texture .. ".tga"),
      "lab._sheet names " .. sheet.texture .. " with no texture in Media/lab")
    -- A pitch that does not divide the tile seams where the sheet wraps.
    assert.equal(0, sheet.tile_px % sheet.pitch_px)
  end)

  it("ships the ring texture the border-as-a-texture entry draws with", function()
    local ring = ns.LabStyle._ring
    if not ring then return end
    assert.is_true(exists(LAB_MEDIA .. ring.texture .. ".tga"),
      "lab._ring names " .. ring.texture .. " with no texture in Media/lab")
    -- Power of two, or the client will not read it.
    local t = ring.tile_px
    while t > 1 do
      assert.equal(0, t % 2, "tile_px " .. ring.tile_px .. " is not a power of two")
      t = t / 2
    end
    -- Only the nine-slice corner square is drawn 1:1, so the margin has to contain the whole
    -- curved corner AND the band, and two margins have to fit across the tile.
    if (ring.slice_margin_px or 0) > 0 then
      assert.is_true(ring.slice_margin_px >= ring.thickness_px)
      assert.is_true(ring.slice_margin_px >= (ring.corner_px or 0))
      assert.is_true(2 * ring.slice_margin_px <= ring.tile_px)
    end
    -- A band that does not leave a transparent centre is a filled rect, not a ring.
    assert.is_true(2 * ring.thickness_px < ring.tile_px)
  end)

  it("draws a nine-sliced band at its authored width and an unsliced one at the drawn scale",
    function()
      -- Sliced: the corner squares and the band are pinned to their authored pixels.
      assert.equal(3, ns.Paint.RingBand(3, 64, 56, true))
      assert.equal(3, ns.Paint.RingBand(3, 64, 120, true))
      -- Unsliced: the band is minified with the rest of the sheet.
      assert.equal(3 * 56 / 64, ns.Paint.RingBand(3, 64, 56, false))
      assert.equal(6, ns.Paint.RingBand(3, 64, 128, false))
      -- A sheet with no size is a missing asset, not a divide by zero.
      assert.equal(3, ns.Paint.RingBand(3, 0, 56, false))
    end)

  it("stages the arrival variants against real neighbours", function()
    local stage = ns.LabStyle._arrival_stage
    if not stage then return end
    assert.is_true(stage.neighbours >= 1, "a stage with no neighbours cannot show the crossing")
    -- The row pitch is the STYLE's and is never restated in the lab.
    assert.is_nil(stage.pitch_px)
    assert.is_nil(stage.row_gap_px)
  end)

  it("tiles the sheet at its authored size rather than stretching one copy over the host",
    function()
      -- A host twice the sheet's width shows the sheet twice, not one stretched copy.
      local l, r, b, t = ns.Paint.StripeTexCoord(256, 128, 128, 16, 0)
      assert.equal(0, l)
      assert.equal(2, r)
      assert.equal(0, b)
      assert.equal(1, t)
      -- A host smaller than the sheet crops it; the drawn pitch is the authored one either way.
      local _, r2 = ns.Paint.StripeTexCoord(56, 56, 128, 16, 0)
      assert.equal(56 / 128, r2)
      -- A sheet with no size is a missing asset, not a divide by zero.
      local l3, r3 = ns.Paint.StripeTexCoord(56, 56, 0, 16, 50)
      assert.equal(0, l3)
      assert.equal(1, r3)
    end)

  it("offsets the complementary phase by half a stripe period", function()
    local zero = ns.Paint.StripeTexCoord(56, 56, 128, 16, 0)
    local half = ns.Paint.StripeTexCoord(56, 56, 128, 16, 50)
    local full = ns.Paint.StripeTexCoord(56, 56, 128, 16, 100)
    assert.equal(8 / 128, half - zero)
    assert.equal(16 / 128, full - zero)
    -- The whole rect moves, so the repeat factor is untouched by the phase.
    local _, rz = ns.Paint.StripeTexCoord(56, 56, 128, 16, 0)
    local _, rh = ns.Paint.StripeTexCoord(56, 56, 128, 16, 50)
    assert.equal(8 / 128, rh - rz)
  end)

  it("measures how far a scaled border reaches past its own edge, and whose row it lands in",
    function()
      assert.equal(0, ns.Paint.Overhang(60, 1.00))
      assert.equal(30, ns.Paint.Overhang(60, 2.00))
      assert.equal(7.5, ns.Paint.Overhang(60, 1.25))
      -- The live border frame is the icon plus two pixels of padding on each side, against a
      -- row pitch of icon + row_gap: two pixels of clear space, which 2.00x crosses by 28.
      local S = ns.Style.surfaces
      local frame, gap = S.icon_px + 4, S.icon_px + S.row_gap_px
      assert.is_true(ns.Paint.CrossesNeighbour(frame, 2.00, gap))
      assert.is_false(ns.Paint.CrossesNeighbour(frame, 1.00, gap))
    end)

  it("draws a fat ring at least one whole pixel fatter than the resting one", function()
    assert.equal(9, ns.Paint.FatRing(3, 3.0))
    assert.equal(6, ns.Paint.FatRing(2, 3.0))
    -- A multiplier that rounds back onto the resting thickness would draw it twice.
    assert.equal(2, ns.Paint.FatRing(1, 1.0))
    assert.equal(3, ns.Paint.FatRing(2, 1.2))
    -- Whole pixels: a half-pixel strip is a blur rather than a thicker line.
    assert.equal(4, ns.Paint.FatRing(3, 1.4))
  end)

  it("rate limits a hand-replayed one-shot to its own duration", function()
    -- An exactly representable duration, so the boundary case is the rule and not a rounding.
    local d = 0.5
    assert.is_true(ns.Paint.ShouldReplay(nil, 100, d))
    assert.is_false(ns.Paint.ShouldReplay(100, 100 + d / 2, d))
    assert.is_true(ns.Paint.ShouldReplay(100, 100 + d, d))
    assert.is_true(ns.Paint.ShouldReplay(100, 100 + d * 2, d))
  end)
end)
