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
  H.load(ns, "Anchor.lua")

  -- The module captured the stub as a file-local at load, so the pure functions keep
  -- working once the globals go back to being absent.
  _G.issecretvalue, _G.CreateFrame, _G.SlashCmdList = wasSecret, wasCreate, wasSlash
  return ns.Anchor
end

local Anchor = loadAnchor()

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
    planned = { 30, 10, 20 }, drawn = { 30, 10, 20 }, match = true,
    stomps = 4, stompsCombat = 1, displaced = 2, contended = 0,
  }

  it("is deterministic for a given snapshot", function()
    assert.equal(Anchor.Render(snap), Anchor.Render(snap))
    assert.equal("A{n:3 named:2 extra:1 miss:1} P{30,10,20} D{30,10,20} X{ok}"
      .. " S{stomp:4 icombat:1 disp:2 cont:0}", Anchor.Render(snap))
  end)

  it("renders an absent count as ? and an empty order as -, never as 0", function()
    local body = Anchor.Render{ named = 0, planned = {}, drawn = {} }
    assert.equal("A{n:? named:0 extra:? miss:?} P{-} D{-} X{MISMATCH}"
      .. " S{stomp:? icombat:? disp:? cont:?}", body)
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
