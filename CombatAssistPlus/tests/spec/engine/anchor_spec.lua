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
    parks = 0, parkedNow = 0, staleSeen = 0, strikes = 0,
  }

  it("is deterministic for a given snapshot", function()
    assert.equal(Anchor.Render(snap), Anchor.Render(snap))
    assert.equal("A{n:3 named:2 extra:1 miss:1 parked:0} P{30,10,20} D{30,10,20} X{ok}"
      .. " S{stomp:4 icombat:1 disp:2 cont:0 reassert:7 park:0 stale:0 strike:0}",
      Anchor.Render(snap))
  end)

  it("renders an absent count as ? and an empty order as -, never as 0", function()
    local body = Anchor.Render{ named = 0, planned = {}, drawn = {} }
    assert.equal("A{n:? named:0 extra:? miss:? parked:?} P{-} D{-} X{MISMATCH}"
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

  it("falls back to a whole 6x2 grid when the tokens are missing", function()
    ANS.Style = nil
    local cols, rows_, cell, gap = Anchor.Grid()
    assert.are.equal(6, cols)
    assert.are.equal(2, rows_)
    assert.are.equal(50, cell)
    assert.are.equal(1, gap)
  end)
end)
