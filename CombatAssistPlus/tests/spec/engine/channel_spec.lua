-- Engine guarantee: the band builder turns AUTHORED MEANING into client arguments, and nothing
-- in it ever reads a value back. Every number it emits is the shelf's; every decision it makes
-- is the catalog's; the secret it will be evaluated against never appears here at all.
local H = require("CombatAssistPlus.tests.mock_ns")

-- A stand-in for `ns.Style.count`, passed as an argument so the builder stays pure and the
-- assertions below are about the BUILDER rather than about today's palette.
local STYLE = {
  texture_root = "BADGES\\",
  hatch_root = "MEDIA\\",
  hatch = "stripes", hatch_px = 56,
  plate = "plate", plate_px = 25, plate_offset_px = { 20, -18 },
  mark = "glyph", mark_px = 15, mark_offset_px = { 20, -18 },
  rgb = { 1, 0.5, 0 },
  low_rgb = { 1, 0, 0 },
}

describe("engine / channel bands", function()
  local ns
  before_each(function() ns = H.fresh() end)

  local function rules(bands)
    return ns.Channel.CountRules(bands, STYLE)
  end

  it("emits one breakpoint per band, in the order they were authored", function()
    local out = rules{
      { threshold = 0, draw = "none" },
      { threshold = 2, draw = "count" },
    }
    assert.equal(2, #out)
    assert.equal(0, out[1].threshold)
    assert.equal("", out[1].format)
    assert.equal(2, out[2].threshold)
    -- The specifier survives verbatim: the client resolves it against the secret.
    assert.is_truthy(out[2].format:find("%%d"))
  end)

  it("refuses a table that does not rise, or one with no resting band", function()
    assert.is_nil(rules{ { threshold = 2, draw = "count" } })
    assert.is_nil(rules{
      { threshold = 0, draw = "none" }, { threshold = 0, draw = "count" } })
    assert.is_nil(rules{
      { threshold = 0, draw = "none" }, { threshold = 4, draw = "count" },
      { threshold = 2, draw = "mark" } })
    assert.is_nil(rules{})
    assert.is_nil(rules(nil))
  end)

  -- ⚠ THE POINT OF THE WHOLE PRIMITIVE. There is exactly one count FontString per button, so a
  -- hatch across the face, a plate, a mark on the corner and a numeral all have to come out of
  -- ONE format string -- and the band above the threshold clears every one of them together.
  it("puts several placed escapes in one band, and the plate inside it", function()
    local out = rules{
      { threshold = 0, draw = "count+mark", polarity = "negative", hatch = true },
      { threshold = 6, draw = "none" },
    }
    local fired = out[1].format
    assert.is_truthy(fired:find("MEDIA\\stripes:56:56", 1, true), fired)
    -- Placed by `:xoff:yoff` rather than flowed, which is what lets one string say two things.
    assert.is_truthy(fired:find("BADGES\\plate:25:25:20:-18", 1, true), fired)
    assert.is_truthy(fired:find("BADGES\\glyph:15:15:20:-18", 1, true), fired)
    assert.is_truthy(fired:find("%%d"))
    -- And the band above clears ALL of it. A plate cap drew as an ordinary texture could not do
    -- this: only the FontString carries a sink, so the plate has to be named BY the band.
    assert.equal("", out[2].format)
  end)

  it("spends hue on polarity and gives the plate its own, because contrast is not polarity",
    function()
      local negative = rules{ { threshold = 0, draw = "mark", polarity = "negative" } }[1].format
      local positive = rules{ { threshold = 0, draw = "mark" } }[1].format
      assert.is_truthy(negative:find("|cffff0000", 1, true), negative)
      assert.is_truthy(positive:find("|cffff8000", 1, true), positive)
      -- The plate is the badge stack's own dark disc in BOTH, at the shelf's own alpha.
      local plate = ("|c%02x000000"):format(
        math.floor(ns.Style.badges.plate.alpha * 255 + 0.5))
      assert.is_truthy(negative:find(plate, 1, true), negative)
      assert.is_truthy(positive:find(plate, 1, true), positive)
    end)

  it("treats the hatch as orthogonal to the mark, so a band can rule a row out silently",
    function()
      -- `hatch` says the row is RULED OUT and `draw` says what else the count has to add. They
      -- are separate because a row can be ruled out with nothing to say about the number --
      -- which is the shape Power Siphon wants at two Cores and Implosion does not.
      local out = rules{ { threshold = 0, draw = "none", polarity = "negative", hatch = true } }
      assert.is_truthy(out[1].format:find("stripes", 1, true))
      assert.is_falsy(out[1].format:find("%%d"))
      assert.is_falsy(out[1].format:find("glyph", 1, true))
      -- And an empty format string is the ONLY way this object can say "draw nothing here",
      -- which is what a band with neither says.
      assert.equal("", rules{ { threshold = 0, draw = "none" } }[1].format)
    end)

  it("plans the three container sinks apart, and each names its own client object", function()
    local demo = H.catalogBySpec(ns, 266)
    local declared = ns.Catalog.Resolve(demo, {}).declared
    local function marker(id)
      for _, e in ipairs(demo.entries) do
        for _, m in ipairs(e.markers or {}) do if m.id == id then return m end end
      end
    end

    local count = ns.Channel.ContainerPlan(marker("implosion_imps_short"), declared)
    assert.equal("SetApplicationCount", count.sink)
    assert.equal(296553, count.spell)
    assert.equal("player", count.unit)
    assert.equal(2, #count.rules)

    local bar = ns.Channel.ContainerPlan(marker("db_core_charge"), declared)
    assert.equal("SetApplicationBar", bar.sink)
    assert.equal(4, bar.max)

    -- The refresh window is the one sink whose PREDICATE is the client's, so its plan carries no
    -- threshold of any kind -- and the unit comes from the ability, because Doom is a debuff.
    local window = ns.Channel.ContainerPlan(marker("db_doom_window"), declared)
    assert.equal("AddPandemicRegion", window.sink)
    assert.equal("target", window.unit)
    assert.is_nil(window.max)
    assert.is_nil(window.rules)

    -- A graded marker is not a container one, and vice versa: a marker is at most one of them.
    assert.is_nil(ns.Channel.ContainerPlan(marker("hog_awaits_tyrant"), declared))
    assert.is_nil(ns.Channel.GradedPlan(marker("db_core_charge")))
  end)
end)
