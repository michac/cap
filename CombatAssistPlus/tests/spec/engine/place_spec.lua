-- Place.lua's store: the keyed saved position, and the one-time read of the single-panel
-- era's key. Drag, chrome and the frames themselves are client behaviour (house rule 6);
-- what is testable here is which table a position lands in and which one it came from.
local H = dofile("CombatAssistPlus/tests/mock_ns.lua")

local function loadPlace()
  local wasCreate, wasSlash = _G.CreateFrame, _G.SlashCmdList
  _G.CreateFrame = function()
    return setmetatable({}, { __index = function() return function() end end })
  end
  _G.SlashCmdList = {}
  local ns = { RegisterCommand = function() end }
  -- Core.lua first: Place binds `ns.readable` as a file-local at load.
  H.load(ns, "Core.lua")
  H.load(ns, "Place.lua")
  _G.CreateFrame, _G.SlashCmdList = wasCreate, wasSlash
  return ns
end

describe("engine / place", function()
  local ns
  before_each(function()
    ns = loadPlace()
    ns.db = {}
  end)

  it("creates a keyed table on first ask and fills only absent defaults", function()
    local s = ns.Place.Store("row", { x = 1, y = 2 })
    assert.are.equal(1, s.x)
    assert.are.equal(2, s.y)
    assert.is_false(s.placed)
    assert.are.equal(s, ns.db.places.row)
  end)

  it("never clobbers a saved value with a default", function()
    ns.Place.Store("row", { x = 1, y = 2 }).x = 99
    assert.are.equal(99, ns.Place.Store("row", { x = 1, y = 2 }).x)
  end)

  it("adopts the single-panel era's db.frame for the `frame` key", function()
    ns.db.frame = { x = 40, y = -160, placed = true }
    local s = ns.Place.Store("frame", { x = 0, y = 0 })
    assert.are.equal(40, s.x)
    assert.are.equal(-160, s.y)
    assert.is_true(s.placed)
  end)

  -- The old key is deliberately LEFT in place: it costs a few bytes, and a player who rolls
  -- back to the previous build finds their panel where they left it rather than at the origin.
  it("leaves the legacy key alone rather than moving it", function()
    ns.db.frame = { x = 40, y = -160, placed = true }
    ns.Place.Store("frame", { x = 0, y = 0 })
    assert.are.equal(40, ns.db.frame.x)
  end)

  -- The migration is scoped to one key. Reading it for the row would hand cap's CDM panel the
  -- cooldown panel's position, which is a visible jump rather than a silent one.
  it("does not read the legacy key for any other frame", function()
    ns.db.frame = { x = 40, y = -160, placed = true }
    local s = ns.Place.Store("row", { x = 0, y = -200 })
    assert.are.equal(0, s.x)
    assert.are.equal(-200, s.y)
    assert.is_false(s.placed)
  end)

  it("takes the migration once, so a later edit is not overwritten by it", function()
    ns.db.frame = { x = 40, y = -160, placed = true }
    ns.Place.Store("frame", { x = 0, y = 0 }).x = 7
    assert.are.equal(7, ns.Place.Store("frame", { x = 0, y = 0 }).x)
  end)

  it("keeps the shape before ns.db exists, so a load-time write is not orphaned", function()
    ns.db = nil
    local s = ns.Place.Store("row", { x = 3, y = 4 })
    assert.are.equal(3, s.x)
    assert.are.equal(s, ns.Place.Store("row", { x = 3, y = 4 }))
  end)
end)
