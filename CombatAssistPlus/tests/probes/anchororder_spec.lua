-- The probe's three pure functions. Everything else in AnchorOrder.lua is frames, hooks and
-- a clock, which is tested in the client and nowhere else (house rule 6).
local H = dofile("CombatAssistPlus/tests/mock_ns.lua")

-- The chunk registers a slash command and an event frame at file scope. These stubs exist
-- only so it LOADS; no assertion below reads one, and none models client behaviour.
local function loadProbe()
  local wasSecret, wasCreate, wasSlash = _G.issecretvalue, _G.CreateFrame, _G.SlashCmdList
  _G.issecretvalue = function() return false end
  _G.CreateFrame = function()
    return setmetatable({}, { __index = function() return function() end end })
  end
  _G.SlashCmdList = {}

  local ns = { Capture = { Open = function()
    return setmetatable({}, { __index = function() return function() end end })
  end } }
  H.load(ns, "probes/AnchorOrder.lua")

  -- The module captured the stub as a file-local at load, so the pure functions keep
  -- working once the globals go back to being absent.
  _G.issecretvalue, _G.CreateFrame, _G.SlashCmdList = wasSecret, wasCreate, wasSlash
  return ns.AnchorOrder
end

local AnchorOrder = loadProbe()

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

describe("AnchorOrder.Plan", function()
  it("lays the named rows out in the authored order, not the client's", function()
    local plan = AnchorOrder.Plan(rows(10, 20, 30), entries({ "a", 30 }, { "b", 10 }, { "c", 20 }))
    assert.same({ 30, 10, 20 }, ids(plan))
    assert.equal(3, plan.named)
    assert.equal(0, plan.extra)
  end)

  it("keeps rows the catalog does not name, in client order, after the named ones", function()
    local plan = AnchorOrder.Plan(rows(10, 20, 30, 40), entries({ "a", 30 }, { "b", 10 }))
    assert.same({ 30, 10, 20, 40 }, ids(plan))
    assert.equal(2, plan.named)
    assert.equal(2, plan.extra)
  end)

  it("skips an entry with no live row without shifting the rest", function()
    local plan = AnchorOrder.Plan(rows(10, 30), entries({ "a", 30 }, { "b", 99 }, { "c", 10 }))
    assert.same({ 30, 10 }, ids(plan))
    assert.same({ "b" }, plan.missing)
  end)

  it("never places one row twice when two entries name it", function()
    local plan = AnchorOrder.Plan(rows(10, 20), entries({ "a", 10 }, { "b", 10 }))
    assert.same({ 10, 20 }, ids(plan))
    assert.same({ "b" }, plan.missing)
  end)
end)

describe("AnchorOrder.Intended", function()
  local plan = AnchorOrder.Plan(rows(10, 20, 30), entries({ "a", 30 }, { "b", 10 }, { "c", 20 }))

  local function order(mode)
    local out = {}
    for i, item in ipairs(AnchorOrder.Intended(plan, mode)) do out[i] = item.cooldownID end
    return out
  end

  it("draws the plan as authored for any mode but demo", function()
    assert.same({ 30, 10, 20 }, order("authored"))
    assert.same({ 30, 10, 20 }, order(nil))
  end)

  it("reverses the authored order for demo, over the same rows", function()
    assert.same({ 20, 10, 30 }, order("demo"))
    local count = {}
    for _, id in ipairs(order("demo")) do count[id] = (count[id] or 0) + 1 end
    for _, id in ipairs(order("authored")) do assert.equal(1, count[id]) end
    assert.equal(#order("authored"), #order("demo"))
  end)
end)

describe("AnchorOrder.Render", function()
  local snap = {
    n = 3, named = 2, extra = 1, missing = 1,
    planned = { 30, 10, 20 }, drawn = { 30, 10, 20 }, match = true,
    stomps = 4, stompsCombat = 1, displaced = 2, contended = 0,
  }

  it("is deterministic for a given snapshot", function()
    assert.equal(AnchorOrder.Render(snap), AnchorOrder.Render(snap))
    assert.equal("A{n:3 named:2 extra:1 miss:1} P{30,10,20} D{30,10,20} X{ok}"
      .. " S{stomp:4 icombat:1 disp:2 cont:0}", AnchorOrder.Render(snap))
  end)

  it("renders an absent count as ? and an empty order as -, never as 0", function()
    local body = AnchorOrder.Render{ named = 0, planned = {}, drawn = {} }
    assert.equal("A{n:? named:0 extra:? miss:?} P{-} D{-} X{MISMATCH}"
      .. " S{stomp:? icombat:? disp:? cont:?}", body)
  end)
end)
