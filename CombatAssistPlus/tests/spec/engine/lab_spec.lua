-- Part 7's generated data, and the arithmetic the gallery draws it with. Nothing here asserts a
-- colour, a phase or a rate: the lab decides nothing, and pinning its taste would be worse than
-- pinning the style's. What is pinned is the contract the gallery needs to draw an entry at all.
local H = require("CombatAssistPlus.tests.mock_ns")

local LAB_MEDIA = "CombatAssistPlus/Media/lab/"
-- The stripe sheet is the STYLE's since V11 was promoted (2026-08-16); the gallery borrows it
-- from Media/ rather than keeping a second copy that could drift.
local MEDIA = "CombatAssistPlus/Media/"

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
    -- ⚠ PENDING, not a failure. Part 7 says an empty lab is the correct resting state, so this
    -- contract having no subject is a fact about the lab and never a defect in it. It went red
    -- the day the lab was emptied (2026-08-19), which is exactly when it should have gone quiet.
    if not any then pending("the lab is empty — nothing here to protect, by design") end
  end)

  it("borrows the style's stripe sheet rather than shipping a second copy", function()
    local sheet = ns.LabStyle._sheet
    if not sheet then return end
    assert.is_true(exists(MEDIA .. sheet.texture .. ".tga"),
      "_sheet names " .. sheet.texture .. " with no texture in Media/")
    assert.is_false(exists(LAB_MEDIA .. sheet.texture .. ".tga"),
      "a second copy under Media/lab/ can drift from the one V11 ships")
    -- A pitch that does not divide the tile seams where the sheet wraps.
    assert.equal(0, sheet.tile_px % sheet.pitch_px)
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

  it("keeps no scaled-border geometry — nothing is drawn at a scale any more", function()
    -- `Overhang`, `CrossesNeighbour` and `FatRing` measured a border drawn LARGER than its own
    -- rect, which only the arrival and readiness experiments ever did. Nothing scales a frame
    -- now, so the arithmetic has no subject and a helper with no subject is a claim about a
    -- treatment that does not exist.
    for _, gone in ipairs({ "Overhang", "CrossesNeighbour", "FatRing" }) do
      assert.is_nil(ns.Paint[gone], "Paint." .. gone .. " outlived the treatment that scaled")
    end
  end)

  -- Part 7 · the sealed displays. The gallery draws them by hand from a cell's stated value,
  -- and the arithmetic it uses to pick a band is the client's own — so it is pinned here even
  -- though the taste around it is not. A band picked wrongly makes every cell an argument about
  -- this file rather than about the client.
  it("picks the band a value falls in the way ApplyApplicationCount does", function()
    local bands = { { threshold = 0, format = "" }, { threshold = 4, format = "%d" } }
    assert.equal(0, ns.Paint.BandFor(bands, 0).threshold)
    assert.equal(0, ns.Paint.BandFor(bands, 3).threshold)
    -- `threshold` is the MINIMUM input the rule applies to, so the value ON it takes the UPPER
    -- band. This is the off-by-one that is invisible until it is wrong in a pull.
    assert.equal(4, ns.Paint.BandFor(bands, 4).threshold)
    assert.equal(4, ns.Paint.BandFor(bands, 99).threshold)
    -- Authored order is not sorted order, and a table with no reachable band is not a crash.
    local loose = { { threshold = 6, format = "x" }, { threshold = 0, format = "y" } }
    assert.equal(6, ns.Paint.BandFor(loose, 7).threshold)
    assert.is_nil(ns.Paint.BandFor({ { threshold = 2 } }, 1))
    assert.is_nil(ns.Paint.BandFor(nil, 5))
  end)

  it("resolves the specifier and leaves a texture escape alone", function()
    local bands = { { threshold = 0, format = "" }, { threshold = 4, format = "%d" } }
    assert.equal("", ns.Paint.BandText(bands, 2))
    assert.equal("7", ns.Paint.BandText(bands, 7))
    -- ⚠ Untouched. `|T…|t` and `|A:…|a` inside a band RENDER as art in the client, so anything
    -- stripped here would be the gallery showing something the client does not.
    local art = { { threshold = 0, format = "%d|A:pawns:15:15|a" } }
    assert.equal("3|A:pawns:15:15|a", ns.Paint.BandText(art, 3))
    assert.equal("", ns.Paint.BandText({ { threshold = 0, format = "" } }, 9))
  end)

  it("tells a whole-icon escape from a corner one, which is where the string is anchored",
    function()
      local icon = ns.Style.surfaces.icon_px
      assert.is_true(ns.Paint.BandIsFullIcon(
        "|TInterface/AddOns/CombatAssistPlus/Media/stripes:56:56|t", icon))
      assert.is_false(ns.Paint.BandIsFullIcon("|A:pawn:15:15:20:-18|a", icon))
      -- Both in one band is the case that matters: there is exactly ONE count FontString per
      -- button, so a hatch and a corner badge come from one string and it must centre.
      assert.is_true(ns.Paint.BandIsFullIcon(
        "|TInterface/AddOns/CombatAssistPlus/Media/stripes:56:56|t|A:pawn:15:15:20:-18|a", icon))
      assert.is_false(ns.Paint.BandIsFullIcon("4", icon))
      assert.is_false(ns.Paint.BandIsFullIcon(nil, icon))
    end)

  it("has nothing left to rate limit — the lab replays nothing on click", function()
    -- `ShouldReplay` limited the gallery's click-to-replay, which only the arrival rows offered.
    -- Every surviving lab cell is a still, so there is no second play to guard against.
    assert.is_nil(ns.Paint.ShouldReplay)
  end)
end)
