-- Engine guarantee: the band builder turns AUTHORED MEANING into client arguments, and nothing
-- in it ever reads a value back. Every number it emits is the shelf's; every decision it makes
-- is the catalog's; the secret it will be evaluated against never appears here at all.
local H = require("CombatAssistPlus.tests.mock_ns")

-- A stand-in for `ns.Style.count`, passed as an argument so the builder stays pure and the
-- assertions below are about the BUILDER rather than about today's palette.
local STYLE = {
  texture_root = "BADGES\\",
  hatch_root = "MEDIA\\",
  hatch = "stripes",
  plate = "plate", plate_offset_px = { 20, -18 },
  mark = "glyph", mark_offset_px = { 20, -18 },
  rgb = { 1, 0.5, 0 },
  low_rgb = { 1, 0, 0 },
}

describe("engine / channel bands", function()
  local ns
  before_each(function() ns = H.fresh() end)

  --- One element's breakpoints. Since 2026-08-22 a banded count takes ONE SLOT PER ELEMENT —
  --- every slot is offered every aura and filters independently — so each mark has its own
  --- FontString, its own placement and its own band table. `element` is which one.
  local function rules(bands, element)
    return ns.Channel.CountRules(bands, STYLE, nil, element or "mark")
  end

  it("emits one breakpoint per band, in the order they were authored", function()
    local out = rules({
      { threshold = 0, draw = "none" },
      { threshold = 2, draw = "count" },
    }, "count")
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

  -- ⚠ THE POINT OF THE WHOLE PRIMITIVE, and it CHANGED on 2026-08-22.
  --
  -- It used to be "there is one count FontString per button, so everything the count says has to
  -- come out of one string" — which is true of a BUTTON and false of a SLOT. Every slot is
  -- offered every aura and filters independently, so a banded count takes one slot per element:
  -- the hatch, the badge and the numeral each get their own button, their own string and their
  -- own band table. The ~96px run that overhung the neighbouring icon, and the offset arithmetic
  -- under it, were consequences of the old reading rather than of the sink.
  it("splits the marks across one element each, and each carries only its own", function()
    local bands = {
      { threshold = 0, draw = "count", polarity = "negative", hatch = true },
      { threshold = 6, draw = "none" },
    }
    -- The numeral rides ON a plate, which is its own slot with the numeral's thresholds
    -- (render-shelf.md V16): a plate escape cannot sit under text within one string.
    assert.same({ "hatch", "plate", "count" }, ns.Channel.CountElements(bands))

    -- `count` and `mark` are EXCLUSIVE, so a band asking for one never yields the other's slot.
    assert.same({ "hatch", "mark" }, ns.Channel.CountElements({
      { threshold = 0, draw = "mark", polarity = "negative", hatch = true },
      { threshold = 6, draw = "none" },
    }))

    local hatch = rules(bands, "hatch")[1].format
    assert.is_truthy(hatch:find("MEDIA\\stripes_neg:", 1, true), hatch)
    assert.is_falsy(hatch:find("glyph", 1, true), "the hatch element carries the mark")
    assert.is_falsy(hatch:find("%%d"), "the hatch element carries the numeral")

    -- `bands` asks for the numeral, so the MARK element emits nothing at all: the two are
    -- exclusive and this is the shape of that. The mark's own art is covered by the polarity
    -- case below, which asks for a mark band.
    assert.equal("", rules(bands, "mark")[1].format)

    local markBands = { { threshold = 0, draw = "mark", polarity = "negative", hatch = true },
                        { threshold = 6, draw = "none" } }
    local mark = rules(markBands, "mark")[1].format
    assert.is_truthy(mark:find("BADGES\\plate:", 1, true), mark)
    assert.is_truthy(mark:find("BADGES\\glyph_neg:", 1, true), mark)
    assert.is_falsy(mark:find("stripes", 1, true), "the mark element carries the hatch")
    assert.equal("", rules(markBands, "count")[1].format,
      "a mark band emits a numeral as well")

    local count = rules(bands, "count")[1].format
    assert.is_truthy(count:find("%%d"))
    assert.is_falsy(count:find("|T", 1, true), "the numeral element carries art")

    -- ⚠ AND THE UPPER BAND CLEARS EVERY ELEMENT. They are separate strings now, so "they all go
    -- together" stops being automatic and becomes something to hold: each element's own table
    -- has to emit nothing above the threshold, or one mark outlives the decision.
    for _, element in ipairs({ "hatch", "count" }) do
      assert.equal("", rules(bands, element)[2].format, element .. " survives its threshold")
    end
  end)

  it("asks for a slot only for the elements a table actually draws", function()
    assert.same({ "hatch" },
      ns.Channel.CountElements{ { threshold = 0, draw = "none", hatch = true } })
    assert.same({ "plate", "count" },
      ns.Channel.CountElements{ { threshold = 0, draw = "count" } })
    assert.same({ "plate", "mark", "count" }, ns.Channel.CountElements{
      { threshold = 0, draw = "count" }, { threshold = 4, draw = "mark" } })
    -- A table that draws nothing anywhere needs no slot at all, and `Plan` refuses it: a display
    -- that arms and renders nothing is `spec.md` §3.2's defect.
    assert.same({}, ns.Channel.CountElements{ { threshold = 0, draw = "none" } })
  end)

  -- ⚠ THE HUE IS IN THE FILE, and this is a client fact rather than a preference. Measured
  -- 2026-08-22: a `|cAARRGGBB…|r` escape tints a band's TEXT and leaves an inline `|T…|t` at full
  -- white. There is no `SetVertexColor` either — the sink owns a FontString and the art inside it
  -- is named by a path, so there is no texture object to recolour. `capart export count` bakes
  -- the pair.
  it("names a pre-tinted crop per polarity, and wraps only the numeral in a colour escape",
    function()
      -- The MARK is the element that names a crop, so both polarities are asked for as marks.
      local negative = rules({ { threshold = 0, draw = "mark", polarity = "negative" } },
        "mark")[1].format
      local positive = rules({ { threshold = 0, draw = "mark" } }, "mark")[1].format

      assert.is_truthy(negative:find("glyph_neg", 1, true), negative)
      assert.is_truthy(positive:find("glyph_pos", 1, true), positive)

      -- The numeral is the one thing a colour escape still reaches, because it is text — and it
      -- lives on its OWN element now, so it is asked for by name rather than expected here.
      local band = { { threshold = 0, draw = "count", polarity = "negative" } }
      assert.is_truthy(rules(band, "count")[1].format:find("|cffff0000%d", 1, true))
      assert.is_truthy(rules({ { threshold = 0, draw = "count" } }, "count")[1].format
        :find("|cffff8000%d", 1, true))

      -- ⚠ NO colour escape may wrap an escape. One that did would draw white in the client while
      -- every preview and every test said otherwise, which is exactly the failure this replaced.
      for run in negative:gmatch("|c%x%x%x%x%x%x%x%x(.-)|r") do
        assert.is_falsy(run:find("|T", 1, true), "a colour escape wraps art: " .. run)
      end

      -- The plate carries no polarity — its job is contrast, and hue carries polarity and only
      -- polarity (V5.1) — so it is ONE file in both bands rather than a pair.
      assert.is_truthy(negative:find("BADGES\\plate:", 1, true), negative)
      assert.is_truthy(positive:find("BADGES\\plate:", 1, true), positive)
      assert.is_falsy(negative:find("plate_neg", 1, true))
    end)

  it("treats the hatch as orthogonal to the mark, so a band can rule a row out silently",
    function()
      -- `hatch` says the row is RULED OUT and `draw` says what else the count has to add. They
      -- are separate because a row can be ruled out with nothing to say about the number --
      -- which is the shape Power Siphon wants at two Cores and Implosion does not.
      local out = rules({ { threshold = 0, draw = "none", polarity = "negative", hatch = true } },
        "hatch")
      assert.is_truthy(out[1].format:find("stripes", 1, true))
      assert.is_falsy(out[1].format:find("%%d"))
      assert.is_falsy(out[1].format:find("glyph", 1, true))
      -- And an empty format string is the ONLY way this object can say "draw nothing here",
      -- which is what a band with neither says.
      assert.equal("", rules({ { threshold = 0, draw = "none" } }, "hatch")[1].format)
    end)

  it("plans the three container sinks apart, and each names its own client object", function()
    local demo = H.catalogBySpec(ns, 266)
    local declared = ns.Catalog.Resolve(demo, {}).declared
    local function marker(id)
      for _, e in ipairs(demo.entries) do
        for _, m in ipairs(e.markers or {}) do if m.id == id then return m end end
      end
    end

    local count = ns.Channel.ContainerPlan(marker("implosion_imps_aoe"), declared)
    assert.equal("SetApplicationCount", count.sink)
    assert.equal(296553, count.spell)
    assert.equal("player", count.unit)
    assert.same({ "hatch", "plate", "count" }, count.elements)

    local bar = ns.Channel.ContainerPlan(marker("db_core_charge"), declared)
    assert.equal("SetApplicationBar", bar.sink)
    assert.equal(4, bar.max)
    -- ⚠ THE PLAN CARRIES NO `full`. V18's whole-bar red flip follows from the KIND -- `Arm`
    -- adds its slot on `plan.kind == "sealed-count-bar"` alone -- so the catalog key that used to
    -- ride here controlled nothing while being cited in prose as though it fired the flip. A
    -- field that reads as a switch and switches nothing is worse than no field.
    assert.is_nil(bar.full)
    assert.is_nil(ns.Channel.BarPlan(
      { id = "m", display = { kind = "sealed-count-bar", ability = "core", max = 0 } },
      { core = { spell = 1, unit = "player" } }), "max must be positive")

    -- The pandemic window is the one sink whose PREDICATE is the client's, so its plan carries no
    -- threshold of any kind -- and the unit comes from the ability, because Doom is a debuff.
    local window = ns.Channel.ContainerPlan(marker("db_doom_window"), declared)
    assert.equal("AddPandemicRegion", window.sink)
    assert.equal("target", window.unit)
    assert.is_nil(window.max)
    assert.is_nil(window.rules)

    -- The pair's OTHER state (render-shelf.md V19): `outside_s` is the catalog's own number and
    -- optional; a malformed one refuses the plan rather than arming half a display.
    assert.is_nil(window.outside_s, "Doom declares no outside_s yet")
    local dotAbil = { dot = { spell = 603, unit = "target" } }
    local withOutside = ns.Channel.WindowPlan(
      { id = "m", display = { kind = "sealed-pandemic", ability = "dot", outside_s = 18 } },
      dotAbil)
    assert.equal(18, withOutside.outside_s)
    assert.is_nil(ns.Channel.WindowPlan(
      { id = "m", display = { kind = "sealed-pandemic", ability = "dot", outside_s = -1 } },
      dotAbil))
    assert.is_nil(ns.Channel.WindowPlan(
      { id = "m", display = { kind = "sealed-pandemic", ability = "dot", outside_s = "18" } },
      dotAbil))

    -- V20 · the proc bar: a plan with no threshold and no numbers of its own — the slot
    -- filters to the proc aura and the client drains the bar off its duration.
    local pbar = ns.Channel.ContainerPlan(marker("db_core_clock"), declared)
    assert.equal("sealed-proc-bar", pbar.kind)
    assert.equal("player", pbar.unit)
    assert.is_nil(pbar.max)
    assert.is_nil(ns.Channel.ProcBarPlan(
      { id = "m", display = { kind = "sealed-proc-bar", ability = "missing" } }, declared))

    -- A graded marker is not a container one, and vice versa: a marker is at most one of them.
    assert.is_nil(ns.Channel.ContainerPlan(marker("hog_awaits_tyrant"), declared))
    assert.is_nil(ns.Channel.GradedPlan(marker("db_core_charge")))
  end)

  it("authors the two-sided band as three step points, ordered or refused", function()
    -- catalog.md Defeats item 1's named recipe, built 2026-08-24: hold while the dependency's
    -- remaining time is inside (beyond, within). Step holds the previous value, so 5s reads 0
    -- (the APL fires the dogs), 16s reads 1 (the dead zone), 30s reads 0 again.
    assert.same({ { 0, 0 }, { 10.5, 1 }, { 21.5, 0 } }, ns.Channel.BandPoints(10.5, 21.5))
    -- The reversed or degenerate pair is an empty band that would arm and never draw.
    assert.is_nil(ns.Channel.BandPoints(21.5, 10.5))
    assert.is_nil(ns.Channel.BandPoints(10.5, 10.5))
    assert.is_nil(ns.Channel.BandPoints(0, 21.5))

    -- HoldPlan carries the pair through, and refuses the reversed one at the plan seam too.
    local paired = ns.Channel.HoldPlan({ id = "m", cue = "blocked",
      display = { kind = "sealed-cooldown-range", ability = "dep",
                  beyond = 10.5, within = 21.5 } })
    assert.equal(10.5, paired.beyond)
    assert.equal(21.5, paired.within)
    assert.is_nil(ns.Channel.HoldPlan({ id = "m", cue = "blocked",
      display = { kind = "sealed-cooldown-range", ability = "dep",
                  beyond = 21.5, within = 10.5 } }))
  end)
end)
