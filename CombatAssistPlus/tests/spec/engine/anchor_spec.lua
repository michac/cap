-- Anchor.lua's pure functions. Everything else in it is frames, hooks and a clock, which
-- is tested in the client and nowhere else (house rule 6).
local H = dofile("CombatAssistPlus/tests/mock_ns.lua")

-- The chunk registers a slash command and an event frame at file scope. These stubs exist
-- only so it LOADS; no assertion below reads one, and none models client behaviour.
local function loadAnchor()
  local wasSecret, wasCreate, wasSlash = _G.issecretvalue, _G.CreateFrame, _G.SlashCmdList
  _G.issecretvalue = function() return false end
  _G.CreateFrame = function()
    return setmetatable({}, { __index = function() return function() end end })
  end
  _G.SlashCmdList = {}

  local ns = {
    Capture = { Open = function()
      return setmetatable({}, { __index = function() return function() end end })
    end },
    RegisterCommand = function() end,
  }
  -- Core.lua FIRST: Anchor binds its fenced reads (`ns.num`, `ns.plain`, `ns.SpecAndHero`) as
  -- file-locals at load, so they have to be on the namespace before the chunk runs. Place.lua
  -- next, because Anchor builds its row panel at file scope and registers it as placeable —
  -- eagerly and not on an event, so that `/cap move` can offer the panel before the Cooldown
  -- Manager has drawn anything.
  H.load(ns, "Core.lua")
  H.load(ns, "Place.lua")
  -- Catalog.lua before Anchor.lua, in the `.toc`'s own order: Anchor aliases
  -- `Catalog.GridLimits` at file scope, so the one list of bounds is on the namespace first.
  H.load(ns, "Catalog.lua")
  H.load(ns, "Anchor.lua")

  -- The module captured the stub as a file-local at load, so the pure functions keep
  -- working once the globals go back to being absent.
  _G.issecretvalue, _G.CreateFrame, _G.SlashCmdList = wasSecret, wasCreate, wasSlash
  return ns.Anchor, ns
end

local Anchor, ANS = loadAnchor()

local function rows(...)
  local out = {}
  for _, id in ipairs({ ... }) do out[#out + 1] = { cooldownID = id } end
  return out
end

local function entries(...)
  local out = {}
  for _, pair in ipairs({ ... }) do out[#out + 1] = { id = pair[1], cooldownID = pair[2] } end
  return out
end

local function ids(plan)
  local out = {}
  for i, item in ipairs(plan.order) do out[i] = item.cooldownID end
  return out
end

describe("Anchor.Plan", function()
  it("lays the named rows out in the authored order, not the client's", function()
    local plan = Anchor.Plan(rows(10, 20, 30), entries({ "a", 30 }, { "b", 10 }, { "c", 20 }))
    assert.same({ 30, 10, 20 }, ids(plan))
    assert.equal(3, plan.named)
    assert.equal(0, plan.extra)
  end)

  it("keeps rows the catalog does not name, in client order, after the named ones", function()
    local plan = Anchor.Plan(rows(10, 20, 30, 40), entries({ "a", 30 }, { "b", 10 }))
    assert.same({ 30, 10, 20, 40 }, ids(plan))
    assert.equal(2, plan.named)
    assert.equal(2, plan.extra)
  end)

  it("skips an entry with no live row without shifting the rest", function()
    local plan = Anchor.Plan(rows(10, 30), entries({ "a", 30 }, { "b", 99 }, { "c", 10 }))
    assert.same({ 30, 10 }, ids(plan))
    assert.same({ "b" }, plan.missing)
  end)

  it("never places one row twice when two entries name it", function()
    local plan = Anchor.Plan(rows(10, 20), entries({ "a", 10 }, { "b", 10 }))
    assert.same({ 10, 20 }, ids(plan))
    assert.same({ "b" }, plan.missing)
  end)
end)

describe("Anchor.Render", function()
  local snap = {
    n = 3, named = 2, extra = 1, missing = 1,
    planned = { 30, 10, 20 }, drawn = { 30, 10, 20 }, match = true, stale = 0,
    stomps = 4, stompsCombat = 1, displaced = 2, contended = 0, reasserts = 7,
    parks = 0, parkedNow = 0, staleSeen = 0, strikes = 0, overflowed = 0,
  }

  it("is deterministic for a given snapshot", function()
    assert.equal(Anchor.Render(snap), Anchor.Render(snap))
    assert.equal("A{n:3 named:2 extra:1 miss:1 parked:0 over:0} P{30,10,20} D{30,10,20} X{ok}"
      .. " S{stomp:4 icombat:1 disp:2 cont:0 reassert:7 park:0 stale:0 strike:0}",
      Anchor.Render(snap))
  end)

  it("renders an absent count as ? and an empty order as -, never as 0", function()
    local body = Anchor.Render{ named = 0, planned = {}, drawn = {} }
    assert.equal("A{n:? named:0 extra:? miss:? parked:? over:?} P{-} D{-} X{MISMATCH}"
      .. " S{stomp:? icombat:? disp:? cont:? reassert:? park:? stale:? strike:?}", body)
  end)

  -- The defect this term exists to catch: the position terms agree while the frames are
  -- serving other rows, so a reader with only P/D/X{ok} sees a healthy row that is wrong.
  it("says STALE rather than ok when the plan no longer owns its frames", function()
    local repooled = {}
    for k, v in pairs(snap) do repooled[k] = v end
    repooled.stale = 2
    assert.matches("X{STALE:2}", Anchor.Render(repooled), 1, true)
  end)
end)

describe("Anchor.Judge", function()
  local function judge(t) return Anchor.Judge(t) end

  it("treats drift right after one of its own re-asserts as settling, not contention", function()
    local v = judge{ now = 100, handledAt = 99.5 }
    assert.is_true(v.attributed)
    assert.equal("reassert", v.action)
    assert.equal(0, v.strikes)
  end)

  -- A first unattributable displacement is ordinary; asking on it stops the row for the
  -- rest of the session over one move.
  it("does not ask on a first unattributable displacement", function()
    local v = judge{ now = 100, handledAt = nil }
    assert.is_false(v.attributed)
    assert.equal("reassert", v.action)
    assert.equal(1, v.strikes)
  end)

  it("asks only once a run of strikes lands inside the window", function()
    local v = judge{ now = 100, strikes = 0 }
    v = judge{ now = 101, strikes = v.strikes, strikeAt = v.strikeAt }
    assert.equal("reassert", v.action)
    v = judge{ now = 102, strikes = v.strikes, strikeAt = v.strikeAt }
    assert.equal("ask", v.action)
    assert.equal(0, v.strikes)
  end)

  it("forgets a run that spread out past the window", function()
    local v = judge{ now = 100, strikes = 0 }
    v = judge{ now = 101, strikes = v.strikes, strikeAt = v.strikeAt }
    v = judge{ now = 200, strikes = v.strikes, strikeAt = v.strikeAt }
    assert.equal("reassert", v.action)
    assert.equal(1, v.strikes)
  end)

  it("honours keep-trying rather than re-opening the dialog on the next run", function()
    local v = judge{ now = 100, strikes = 2, strikeAt = 99, askedAt = 90 }
    assert.equal("reassert", v.action)
    assert.equal(0, v.strikes)
  end)

  it("asks again once the keep-trying window has passed", function()
    local v = judge{ now = 200, strikes = 2, strikeAt = 199, askedAt = 90 }
    assert.equal("ask", v.action)
  end)

  -- The item frames are unprotected, so a re-assert is legal in a pull and the verdict
  -- does not read combat at all. Deferring one leaves Blizzard's order on screen.
  it("re-asserts in combat exactly as it does out of it", function()
    assert.equal("reassert", (judge{ now = 100, handledAt = 99.5, combat = true }).action)
    assert.equal("ask", (judge{ now = 100, strikes = 2, strikeAt = 99, combat = true }).action)
  end)

  it("treats an absent state as a first strike rather than erroring", function()
    assert.equal("reassert", (Anchor.Judge()).action)
  end)
end)

describe("Anchor.Diagnose", function()
  it("reports an absent viewer, which is cap's problem to raise", function()
    local status, message = Anchor.Diagnose{ exists = false, rows = 0 }
    assert.equal("no-viewer", status)
    assert.truthy(message)
  end)

  it("reports a viewer the player has put nothing in", function()
    local status, message = Anchor.Diagnose{ exists = true, rows = 0 }
    assert.equal("no-rows", status)
    assert.truthy(message)
  end)

  -- The distinction the error exists to make: a catalog entry with no row is normal,
  -- because the Cooldown Manager only makes rows for abilities it tracks. Diagnose sees
  -- the viewer census alone and so cannot mistake one for the other.
  it("is ok whenever the viewer holds rows, whatever the catalog wanted", function()
    assert.equal("ok", (Anchor.Diagnose{ exists = true, rows = 1 }))
    assert.equal("ok", (Anchor.Diagnose{ exists = true, rows = 12 }))
  end)

  it("treats a missing census as an absent viewer rather than erroring", function()
    assert.equal("no-viewer", (Anchor.Diagnose(nil)))
  end)
end)

-- ---------------------------------------------------------------------------
-- The grid
--
-- The panel's rect is a claim about how many icons fit and how far apart they sit. It is
-- FIXED — read from the tokens, never measured — which is the whole reason the row can be
-- dragged and anchored to before the Cooldown Manager has drawn a single frame.
-- ---------------------------------------------------------------------------

describe("engine / anchor grid", function()
  local was
  before_each(function() was = ANS.Style end)
  after_each(function() ANS.Style = was end)

  it("reads the declared grid", function()
    ANS.Style = { row = { cols = 6, rows = 2, cell_px = 50, cell_floor_px = 50, gap_px = 1 } }
    local cols, rows_, cell, gap = Anchor.Grid()
    assert.are.equal(6, cols)
    assert.are.equal(2, rows_)
    assert.are.equal(50, cell)
    assert.are.equal(1, gap)
  end)

  -- Six 50-wide cells with five 1-wide gaps between them, and two such rows.
  it("sizes the panel as cells plus the gaps between them, never a trailing one", function()
    ANS.Style = { row = { cols = 6, rows = 2, cell_px = 50, cell_floor_px = 50, gap_px = 1 } }
    local w, h = Anchor.GridSize()
    assert.are.equal(6 * 50 + 5 * 1, w)
    assert.are.equal(2 * 50 + 1 * 1, h)
  end)

  -- Blizzard's item template is 50x50, so a smaller cell would draw icons over each other.
  -- The floor is a token-authoring guard, not a runtime one.
  it("floors the cell at the item template's own size", function()
    ANS.Style = { row = { cols = 2, rows = 1, cell_px = 20, cell_floor_px = 50, gap_px = 0 } }
    local _, _, cell = Anchor.Grid()
    assert.are.equal(50, cell)
    assert.are.equal(100, (Anchor.GridSize()))
  end)

  it("takes a cell LARGER than the floor as authored", function()
    ANS.Style = { row = { cols = 1, rows = 1, cell_px = 64, cell_floor_px = 50, gap_px = 0 } }
    local _, _, cell = Anchor.Grid()
    assert.are.equal(64, cell)
  end)

  -- ⚠ The icon-size setting is carried by the panel's SCALE, so it must not appear in these
  -- lengths as well. A grid that changed with iconScale would count it twice, and the panel
  -- would be the square of the setting away from the row it is supposed to hold.
  it("does not vary with the viewer's icon scale", function()
    ANS.Style = { row = { cols = 6, rows = 2, cell_px = 50, cell_floor_px = 50, gap_px = 1 } }
    local before = Anchor.GridSize()
    _G.EssentialCooldownViewer = { iconScale = 1.5 }
    local after = Anchor.GridSize()
    _G.EssentialCooldownViewer = nil
    assert.are.equal(before, after)
  end)

  -- -------------------------------------------------------------------------
  -- Who owns the icon size. Inverted 2026-08-31: cap declares it, Blizzard's Edit Mode
  -- setting does not reach it. These are the tests that would have caught the old premise.
  -- -------------------------------------------------------------------------

  it("takes the panel's scale from cap's own token", function()
    ANS.Style = { row = { icon_px = 75, cols = 6, rows = 2, cell_px = 50, cell_floor_px = 50, gap_px = 1 } }
    assert.are.equal(1.5, Anchor.Scale())
  end)

  -- The default is the template's own size, so landing this inversion changed nothing on
  -- screen for anyone who had not authored a size.
  it("draws at Blizzard's own size when nothing is authored", function()
    ANS.Style = { row = { cols = 6, rows = 2, cell_px = 50, cell_floor_px = 50, gap_px = 1 } }
    assert.are.equal(1, Anchor.Scale())
    ANS.Style = nil
    assert.are.equal(1, Anchor.Scale())
  end)

  -- ⚠ THE POINT OF THE WHOLE INVERSION. Blizzard's setting is an input cap no longer chases:
  -- it cost the v0.18.1 rescale jump and it is why a band sized at arm time goes stale.
  it("ignores the viewer's icon scale entirely", function()
    ANS.Style = { row = { icon_px = 50, cols = 6, rows = 2, cell_px = 50, cell_floor_px = 50, gap_px = 1 } }
    _G.EssentialCooldownViewer = { iconScale = 2.5 }
    local scale, size = Anchor.Scale(), Anchor.GridSize()
    _G.EssentialCooldownViewer = nil
    assert.are.equal(1, scale)
    assert.are.equal(Anchor.GridSize(), size)
  end)

  it("refuses a token that is absent, zero, negative or not a number", function()
    for _, bad in ipairs({ 0, -10, "50", false }) do
      ANS.Style = { row = { icon_px = bad, cols = 6, rows = 2, cell_px = 50, cell_floor_px = 50, gap_px = 1 } }
      assert.are.equal(1, Anchor.Scale())
    end
  end)

  -- ⚠ Anchoring is not parenting: a claimed frame stays a child of the VIEWER, so the scale
  -- put on it has to be divided by its parent's ratio for its effective scale to equal the
  -- panel's. Placement offsets are written raw and are only valid while those two are equal.
  it("scales a claimed frame to the panel's space, not its own parent's", function()
    ANS.Style = { row = { icon_px = 60, cols = 6, rows = 2, cell_px = 50, cell_floor_px = 50, gap_px = 1 } }
    _G.UIParent = { GetEffectiveScale = function() return 1 end }
    -- The panel wants 1.2. The frame reaches it through a viewer that is already doubling
    -- everything under it, so it needs 0.6 — NOT 1.2, which is the bug this test exists for.
    local frame = { GetParent = function() return { GetEffectiveScale = function() return 2 end } end }
    local got = Anchor.ItemScale(frame)
    _G.UIParent = nil
    assert.are.equal(0.6, got)
  end)

  -- A viewer at the same scale as UIParent is the ordinary case, and there the correction is
  -- the identity — which is why getting it wrong stays invisible until someone scales the UI.
  it("is the panel's own scale when the viewer sits at UIParent's scale", function()
    ANS.Style = { row = { icon_px = 60, cols = 6, rows = 2, cell_px = 50, cell_floor_px = 50, gap_px = 1 } }
    _G.UIParent = { GetEffectiveScale = function() return 0.64 end }
    local frame = { GetParent = function() return { GetEffectiveScale = function() return 0.64 end } end }
    local got = Anchor.ItemScale(frame)
    _G.UIParent = nil
    assert.are.equal(1.2, got)
  end)

  it("falls back to the panel's own scale when the parent cannot be measured", function()
    ANS.Style = { row = { icon_px = 60, cols = 6, rows = 2, cell_px = 50, cell_floor_px = 50, gap_px = 1 } }
    _G.UIParent = { GetEffectiveScale = function() return 1 end }
    assert.are.equal(1.2, Anchor.ItemScale(nil))
    assert.are.equal(1.2, Anchor.ItemScale({ GetParent = function() return nil end }))
    assert.are.equal(1.2, Anchor.ItemScale({
      GetParent = function() return { GetEffectiveScale = function() return 0 end } end,
    }))
    _G.UIParent = nil
    -- And with no UIParent at all, which is the harness's own state.
    assert.are.equal(1.2, Anchor.ItemScale({
      GetParent = function() return { GetEffectiveScale = function() return 2 end } end,
    }))
  end)

  it("falls back to a whole 6x2 grid when the tokens are missing", function()
    ANS.Style = nil
    local cols, rows_, cell, gap = Anchor.Grid()
    assert.are.equal(6, cols)
    assert.are.equal(2, rows_)
    assert.are.equal(50, cell)
    assert.are.equal(1, gap)
  end)
end)

-- ---------------------------------------------------------------------------
-- The second row (Phase 2)
-- ---------------------------------------------------------------------------

describe("Anchor.Plan break", function()
  local function e(...) return entries(...) end

  it("is nil when the catalog authors no break, and the order is untouched", function()
    local plan = Anchor.Plan(rows(10, 20, 30), e({ "a", 10 }, { "b", 20 }, { "c", 30 }))
    assert.is_nil(plan.breakAt)
    assert.same({ 10, 20, 30 }, ids(plan))
  end)

  it("points at the authored entry when every entry is present", function()
    local plan = Anchor.Plan(rows(10, 20, 30, 40),
      e({ "a", 10 }, { "b", 20 }, { "c", 30 }, { "d", 40 }), "c")
    assert.are.equal(3, plan.breakAt)
  end)

  -- The nominal talent change: the break entry is not talented this build, so the row still
  -- has to start somewhere and it starts at the next thing that is.
  it("falls through to the next present entry when the break entry is absent", function()
    local plan = Anchor.Plan(rows(10, 20, 40),
      e({ "a", 10 }, { "b", 20 }, { "c", 99 }, { "d", 40 }), "c")
    assert.same({ 10, 20, 40 }, ids(plan))
    assert.are.equal(3, plan.breakAt)
  end)

  -- The break falls off the end. One row, not an empty second one, and above all not an error:
  -- this is reachable by a talent change, which is exactly when nobody is looking.
  it("runs past the end when every entry from the break onward is absent", function()
    local plan = Anchor.Plan(rows(10, 20),
      e({ "a", 10 }, { "b", 20 }, { "c", 98 }, { "d", 99 }), "c")
    assert.are.equal(3, plan.breakAt)
    assert.are.equal(2, #plan.order)
    -- Past the end, so `Cells` puts everything on the first row.
    local layout = Anchor.Cells(#plan.order, plan.breakAt, 6, 51)
    assert.are.equal(0, layout[1].y)
    assert.are.equal(0, layout[2].y)
  end)

  it("puts one icon on the second row when the break is the last entry", function()
    local plan = Anchor.Plan(rows(10, 20, 30), e({ "a", 10 }, { "b", 20 }, { "c", 30 }), "c")
    assert.are.equal(3, plan.breakAt)
    local layout = Anchor.Cells(#plan.order, plan.breakAt, 6, 51)
    assert.are.equal(0, layout[2].y)
    assert.are.equal(-51, layout[3].y)
  end)

  -- The dedup case `Catalog.Resolve` cannot see: `byEntry` holds "b", but Plan dropped it
  -- because "a" already took row 10. Resolving the break in plan space is what gets this right.
  it("falls through when the break entry's row was already claimed by an earlier entry", function()
    local plan = Anchor.Plan(rows(10, 30), e({ "a", 10 }, { "b", 10 }, { "c", 30 }), "b")
    assert.same({ 10, 30 }, ids(plan))
    assert.same({ "b" }, plan.missing)
    assert.are.equal(2, plan.breakAt)
  end)

  it("sends rows the catalog does not name to the tail of the second row", function()
    local plan = Anchor.Plan(rows(10, 20, 70, 80), e({ "a", 10 }, { "b", 20 }), "b")
    assert.same({ 10, 20, 70, 80 }, ids(plan))
    assert.are.equal(2, plan.breakAt)
  end)

  it("ignores a break naming an entry the catalog does not author", function()
    local plan = Anchor.Plan(rows(10, 20), e({ "a", 10 }, { "b", 20 }), "nope")
    assert.is_nil(plan.breakAt)
  end)
end)

describe("Anchor.Cells", function()
  -- ⚠ THE SIGN, ASSERTED AS A SIGN. A positive y draws the second row ABOVE the first and the
  -- drift auditor reports zero drift either way, because `want.top` is wrong in the same
  -- direction. Nothing else in the addon can catch this.
  it("descends: the second row is NEGATIVE y, never positive", function()
    local layout = Anchor.Cells(4, 3, 6, 51)
    assert.are.equal(0, layout[1].y)
    assert.are.equal(0, layout[2].y)
    assert.is_true(layout[3].y < 0)
    assert.are.equal(-51, layout[3].y)
    assert.are.equal(-51, layout[4].y)
  end)

  it("left-aligns both rows, so x resets to 0 at the break", function()
    local layout = Anchor.Cells(5, 3, 6, 51)
    assert.same({ 0, 51, 0, 51, 102 },
      { layout[1].x, layout[2].x, layout[3].x, layout[4].x, layout[5].x })
  end)

  -- The one-row case has to stay exactly what shipped, because every catalog but Havoc is it.
  it("reproduces the old single-axis layout with no break and a roster that fits", function()
    local layout = Anchor.Cells(6, nil, 6, 51)
    for i = 1, 6 do
      assert.are.equal((i - 1) * 51, layout[i].x)
      assert.are.equal(0, layout[i].y)
    end
  end)

  -- The clamp. Before this, a roster longer than the panel ran off its right edge in one line.
  it("wraps at the column count even with no break authored", function()
    local layout = Anchor.Cells(12, nil, 6, 51)
    assert.are.equal(255, layout[6].x)
    assert.are.equal(0, layout[6].y)
    assert.are.equal(0, layout[7].x)
    assert.are.equal(-51, layout[7].y)
  end)

  it("treats the break as a minimum wrap point, not the only one", function()
    -- Break at 9 of 12: without the clamp the first row would run two cells past the edge.
    local layout = Anchor.Cells(12, 9, 6, 51)
    assert.is_true(layout[7].y < 0)
    assert.are.equal(-51, layout[7].y)
    -- And the authored break still forces its own wrap, onto a third row here.
    assert.are.equal(0, layout[9].x)
    assert.are.equal(-102, layout[9].y)
  end)

  it("does not skip a row when the break lands where a row already ended", function()
    -- 6 columns and a break at 7: the column clamp has just wrapped, so the break must not
    -- wrap again and leave an empty row behind it.
    local layout = Anchor.Cells(8, 7, 6, 51)
    assert.are.equal(0, layout[7].x)
    assert.are.equal(-51, layout[7].y)
  end)

  it("returns an empty layout for an empty roster", function()
    assert.same({}, Anchor.Cells(0, nil, 6, 51))
  end)
end)

describe("Anchor.ReadOrder", function()
  local function seen(...)
    local out = {}
    for _, t in ipairs({ ... }) do
      out[#out + 1] = { cooldownID = t[1], left = t[2], top = t[3] }
    end
    return out
  end

  local function idsOf(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.cooldownID end
    return out
  end

  it("matches the old left-only result on a single row", function()
    local ordered = Anchor.ReadOrder(seen({ 30, 102, 500 }, { 10, 0, 500 }, { 20, 51, 500 }))
    assert.same({ 10, 20, 30 }, idsOf(ordered))
  end)

  -- ⚠ The sign test for the SORT. A higher top is higher on screen, so it reads FIRST. An
  -- all-ascending comparator passes every same-row assertion and silently reverses the rows.
  it("reads the higher row first, which is the LARGER top", function()
    local ordered, first = Anchor.ReadOrder(seen(
      { 40, 51, 449 }, { 10, 0, 500 }, { 30, 0, 449 }, { 20, 51, 500 }))
    assert.same({ 10, 20, 30, 40 }, idsOf(ordered))
    assert.are.equal(2, first)
  end)

  it("counts the whole roster as the first row when there is only one", function()
    local _, first = Anchor.ReadOrder(seen({ 10, 0, 500 }, { 20, 51, 500 }))
    assert.are.equal(2, first)
  end)

  it("has no first row for an empty input", function()
    local ordered, first = Anchor.ReadOrder({})
    assert.same({}, ordered)
    assert.are.equal(0, first)
  end)

  it("breaks a tie on left, then on cooldownID", function()
    local ordered = Anchor.ReadOrder(seen({ 30, 0, 500 }, { 10, 0, 500 }, { 20, 51, 500 }))
    assert.same({ 10, 30, 20 }, idsOf(ordered))
  end)

  -- ⚠ THE TRANSITIVITY GUARD. A tolerance comparator (`abs(a.top - b.top) > TOL`) is not
  -- transitive and Lua's table.sort raises `invalid order function for sorting` on a large
  -- enough shuffled input — a hard error, in a capture path. Sub-unit jitter must sort, not
  -- throw.
  it("does not raise on sub-unit jitter in the measured tops", function()
    local jittered, n = {}, 24
    for i = 1, n do
      local row = (i > n / 2) and 1 or 0
      jittered[#jittered + 1] = {
        cooldownID = i,
        left = ((i - 1) % 12) * 51,
        top = 500 - row * 51 + ((i % 5) - 2) * 0.2,
      }
    end
    -- Shuffled deterministically, so a failure reproduces.
    for i = #jittered, 2, -1 do
      local j = (i * 7) % #jittered + 1
      jittered[i], jittered[j] = jittered[j], jittered[i]
    end
    local ok, ordered, first = pcall(Anchor.ReadOrder, jittered)
    assert.is_true(ok)
    assert.are.equal(24, #ordered)
    assert.are.equal(12, first)
  end)
end)

describe("Anchor.Render row break", function()
  local base = {
    n = 4, named = 4, extra = 0, missing = 0,
    planned = { 10, 20, 30, 40 }, drawn = { 10, 20, 30, 40 }, match = true, stale = 0,
    stomps = 0, stompsCombat = 0, displaced = 0, contended = 0, reasserts = 0,
    parks = 0, parkedNow = 0, staleSeen = 0, strikes = 0,
  }

  local function with(t)
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    for k, v in pairs(t) do out[k] = v end
    return out
  end

  it("marks the split in both orders", function()
    local body = Anchor.Render(with{ plannedRow0 = 2, drawnRow0 = 2 })
    assert.is_truthy(body:find("P{10,20|30,40}", 1, true))
    assert.is_truthy(body:find("D{10,20|30,40}", 1, true))
  end)

  it("omits the separator when everything is on one row", function()
    local body = Anchor.Render(with{ plannedRow0 = 4, drawnRow0 = 4 })
    assert.is_truthy(body:find("P{10,20,30,40}", 1, true))
    assert.is_falsy(body:find("|", 1, true))
  end)

  -- ⚠ THE READING THAT MATTERS. Identical id sequences, different splits: the intended two
  -- rows against a pass that collapsed them onto one. Nothing in `A{}` or the id order can
  -- show this, which is why the separator is in the orders.
  it("shows a collapsed second row as a difference between P and D", function()
    local body = Anchor.Render(with{ plannedRow0 = 2, drawnRow0 = 4, match = false })
    assert.is_truthy(body:find("P{10,20|30,40}", 1, true))
    assert.is_truthy(body:find("D{10,20,30,40}", 1, true))
    assert.is_truthy(body:find("X{MISMATCH}", 1, true))
  end)

  it("is still deterministic for a given snapshot", function()
    local snap = with{ plannedRow0 = 2, drawnRow0 = 2 }
    assert.are.equal(Anchor.Render(snap), Anchor.Render(snap))
  end)
end)

describe("Anchor.Cells capacity", function()
  -- ⚠ THE OTHER HALF OF THE CLAMP. Wrapping at `cols` alone only rotates the overflow: the row
  -- stops running off the right edge and starts running off the BOTTOM, onto a third row of a
  -- two-row panel — still outside the rect other UI anchors to, still with no diagnostic.
  it("gives no cell to an icon past the last row", function()
    local layout, from = Anchor.Cells(13, nil, 6, 51, 2)
    assert.are.equal(13, from)
    assert.is_nil(layout[13])
    assert.is_table(layout[12])
    assert.are.equal(-51, layout[12].y)
  end)

  it("never places anything below the last row, even with a late break", function()
    -- Break at 9 of 12 would otherwise wrap onto a third row.
    local layout, from = Anchor.Cells(12, 9, 6, 51, 2)
    for i = 1, 12 do
      if layout[i] then assert.is_true(layout[i].y > -102, "cell " .. i .. " fell below row 1") end
    end
    assert.are.equal(9, from)
  end)

  it("reports no overflow when the roster fits", function()
    local layout, from = Anchor.Cells(12, nil, 6, 51, 2)
    assert.is_nil(from)
    assert.are.equal(12, #layout)
  end)

  it("treats a nil row count as arithmetic without a capacity", function()
    local _, from = Anchor.Cells(13, nil, 6, 51, nil)
    assert.is_nil(from)
  end)

  it("scales its capacity with the row count, not a constant", function()
    local _, from = Anchor.Cells(13, nil, 6, 51, 3)
    assert.is_nil(from)
    local _, from2 = Anchor.Cells(7, nil, 6, 51, 1)
    assert.are.equal(7, from2)
  end)
end)

describe("Anchor grid override", function()
  local savedSpec, savedCdb

  before_each(function()
    savedSpec, savedCdb = ANS.SpecAndHero, ANS.cdb
    ANS.SpecAndHero = function() return 577, 2456 end
    ANS.cdb = {}
    ANS.Style = { row = { icon_px = 50, cols = 6, rows = 2, cell_px = 50, cell_floor_px = 50, gap_px = 1 } }
  end)

  after_each(function()
    ANS.SpecAndHero, ANS.cdb = savedSpec, savedCdb
  end)

  local function store(t)
    ANS.cdb.grid = { ["577:2456"] = t }
  end

  it("falls back to the token when the player has set nothing", function()
    local cols, rows_ = Anchor.Grid()
    assert.are.equal(6, cols)
    assert.are.equal(2, rows_)
  end)

  it("uses the player's cols and rows over the token", function()
    store{ cols = 7, rows = 3 }
    local cols, rows_ = Anchor.Grid()
    assert.are.equal(7, cols)
    assert.are.equal(3, rows_)
  end)

  it("uses the player's icon size over the token", function()
    store{ icon_px = 75 }
    assert.are.equal(1.5, Anchor.Scale())
  end)

  -- ⚠ Validated on READ, not only on write: saved variables are a file a player can edit and a
  -- build can roll back into. Nonsense must fall back to the token, not propagate into geometry.
  it("ignores a stored value that is not a usable number", function()
    for _, bad in ipairs({ "six", true, 0, -1, 999 }) do
      store{ cols = bad }
      assert.are.equal(6, Anchor.Grid(), "cols accepted " .. tostring(bad))
    end
  end)

  it("keeps one spec's grid away from another's", function()
    ANS.cdb.grid = { ["577:2456"] = { cols = 7 }, ["266:-"] = { cols = 4 } }
    assert.are.equal(7, Anchor.Grid())
    ANS.SpecAndHero = function() return 266, nil end
    assert.are.equal(4, Anchor.Grid())
  end)

  it("takes the token when the client will not say what spec this is", function()
    ANS.SpecAndHero = function() return nil, nil end
    store{ cols = 7 }
    assert.are.equal(6, Anchor.Grid())
  end)
end)

-- The catalog tier, which sits between the two above: the catalog PROPOSES a shape that fits its
-- roster, the player DISPOSES, and the token is the floor.
describe("Anchor grid tiers", function()
  local savedSpec, savedCdb

  local function register(grid)
    local cat = { spec = 577, hero = 2456, entries = {} }
    if grid then cat.grid = grid end
    ANS.Catalog.Register(cat)
    return cat
  end

  before_each(function()
    savedSpec, savedCdb = ANS.SpecAndHero, ANS.cdb
    ANS.SpecAndHero = function() return 577, 2456 end
    ANS.cdb = {}
    ANS.Style = { row = { icon_px = 50, cols = 6, rows = 2, cell_px = 50, cell_floor_px = 50, gap_px = 1 } }
  end)

  after_each(function()
    ANS.SpecAndHero, ANS.cdb = savedSpec, savedCdb
    -- The registry is one module-level table, so a catalog left in it is the next suite's
    -- catalog too. Emptied in place because `Catalog.All` hands back the table itself.
    local reg = ANS.Catalog.All()
    for i = #reg, 1, -1 do reg[i] = nil end
  end)

  it("uses the catalog's grid over the token", function()
    register{ cols = 7, rows = 3 }
    local cols, rows_ = Anchor.Grid()
    assert.are.equal(7, cols)
    assert.are.equal(3, rows_)
  end)

  it("takes the token for a dimension the catalog does not propose", function()
    register{ cols = 7 }
    local cols, rows_ = Anchor.Grid()
    assert.are.equal(7, cols)
    assert.are.equal(2, rows_)
  end)

  it("lets the player override the catalog", function()
    register{ cols = 7, rows = 3 }
    ANS.cdb.grid = { ["577:2456"] = { cols = 4 } }
    local cols, rows_ = Anchor.Grid()
    assert.are.equal(4, cols)
    assert.are.equal(3, rows_)
  end)

  -- ⚠ Icon size has NO catalog tier: it is taste, and taste is the player's. A catalog that
  -- declares one anyway is refused by `Catalog.Check`, and ignored here even if it loads.
  it("ignores an icon size the catalog declares", function()
    register{ cols = 7, icon_px = 75 }
    assert.are.equal(1, Anchor.Scale())
    assert.is_nil(Anchor.GridProposed("icon_px"))
  end)

  -- Same rule the player's store follows: `Catalog.Register` asserts only the spec id, so a
  -- shape the validator would have refused must fall back rather than reach the geometry.
  it("ignores a catalog dimension that is not a usable number", function()
    for _, bad in ipairs({ "seven", true, 0, -1, 999 }) do
      register{ cols = bad }
      assert.are.equal(6, Anchor.Grid(), "cols accepted " .. tostring(bad))
      local reg = ANS.Catalog.All()
      for i = #reg, 1, -1 do reg[i] = nil end
    end
  end)

  it("takes the token when this build has no catalog at all", function()
    assert.are.equal(6, Anchor.Grid())
    assert.is_nil(Anchor.GridProposed("cols"))
  end)
end)
