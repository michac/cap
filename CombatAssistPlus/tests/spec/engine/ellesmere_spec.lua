-- Ellesmere.lua — the element table cap offers a foreign mover, and the one place cap's saved
-- position crosses an addon boundary.
--
-- ⚠ Two claims here have no other guard. The mover measures in UIParent units and cap's panel
-- is the only thing cap draws that is not at UIParent scale, so an unscaled `getSize` sizes
-- every geometry the host derives wrongly at every icon size but one. And the row is offered
-- AS AN ANCHOR TARGET: declaring `noAnchorTarget` or `noAnchorTo` would leave every gate here
-- green while removing the only reason the registration exists.
local H = dofile("CombatAssistPlus/tests/mock_ns.lua")

-- `Place:Apply` runs on every stored drop, and it reads UIParent's scale. Permissive rather
-- than measured: what this file tests is the store, and Place's own spec owns the arithmetic.
local function stub()
  return setmetatable({}, { __index = function() return function() end end })
end

local function loadBridge()
  local wasCreate, wasSlash, wasHost, wasUI =
    _G.CreateFrame, _G.SlashCmdList, _G.EllesmereUI, _G.UIParent
  _G.UIParent = stub()
  _G.CreateFrame = nil
  _G.SlashCmdList = {}
  local ns = { RegisterCommand = function() end }
  H.load(ns, "Core.lua")
  _G.CreateFrame = stub
  H.load(ns, "Place.lua")
  _G.CreateFrame = nil
  ns.db, ns.cdb = {}, {}
  H.load(ns, "Ellesmere.lua")
  _G.CreateFrame, _G.SlashCmdList, _G.EllesmereUI = wasCreate, wasSlash, wasHost
  ns._restoreUI = function() _G.UIParent = wasUI end
  return ns
end

--- An `Anchor` with the three readings the bridge takes off it, and a real `Place` handle so
--- the store round-trip is the shipped one rather than a fake.
local function fakeAnchor(ns, over)
  over = over or {}
  local frame = stub()
  local place = ns.Place.Register{ key = "row", frame = frame, noun = "CDM row", x = 0, y = -200 }
  return {
    Row = function() return frame, place end,
    GridSize = function() return over.w or 305, over.h or 101 end,
    Scale = function() return over.scale or 0.8 end,
    Ordering = function() if over.ordering == nil then return true end return over.ordering end,
  }, frame, place
end

--- A host that records what it was handed. `make` opts the fixture into the optional
--- `MakeUnlockElement` factory, which renames the four position fields.
local function fakeHost(make)
  local host = { calls = {}, resized = {}, reapplied = {} }
  host.RegisterUnlockElements = function(self, elements, folder)
    host.calls[#host.calls + 1] = { elements = elements, folder = folder, self = self }
  end
  host.NotifyElementResized = function(key) host.resized[#host.resized + 1] = key end
  host.ReapplyOwnAnchor = function(key) host.reapplied[#host.reapplied + 1] = key end
  if make then
    host.MakeUnlockElement = function(opts)
      local out = {}
      for k, v in pairs(opts) do out[k] = v end
      out.savePosition, out.loadPosition = opts.savePos, opts.loadPos
      out.clearPosition, out.applyPosition = opts.clearPos, opts.applyPos
      return out
    end
  end
  return host
end

local function registered(ns, host)
  if not ns.Ellesmere.Registered() then assert.is_true(ns.Ellesmere.Register()) end
  return host.calls[1].elements[1]
end

describe("engine / ellesmere", function()
  local ns, host, place

  local function setup(over, make)
    host = fakeHost(make)
    _G.EllesmereUI = host
    ns = loadBridge()
    local a, _, p = fakeAnchor(ns, over)
    place = p
    ns.Anchor = a
    return ns
  end

  after_each(function()
    _G.EllesmereUI = nil
    if ns and ns._restoreUI then ns._restoreUI() end
  end)

  it("registers one element, as an array, under cap's own folder", function()
    setup()
    local elem = registered(ns, host)
    assert.are.equal(1, #host.calls)
    assert.are.equal(1, #host.calls[1].elements)
    assert.are.equal("cap", host.calls[1].folder)
    -- A colon call: the host reads its own state off `self`.
    assert.are.equal(host, host.calls[1].self)
    assert.are.equal("CAP_ROW", elem.key)
  end)

  it("prefixes the key, because element keys share one flat namespace", function()
    setup()
    assert.is_truthy(registered(ns, host).key:match("^CAP_"))
  end)

  it("registers once however often it is asked", function()
    setup()
    assert.is_true(ns.Ellesmere.Register())
    assert.is_false(ns.Ellesmere.Register())
    assert.are.equal(1, #host.calls)
  end)

  it("declines to register without a host", function()
    setup()
    _G.EllesmereUI = nil
    assert.is_false(ns.Ellesmere.Register())
    assert.is_false(ns.Ellesmere.Registered())
  end)

  -- ⚠ The panel's own units are not the mover's. `Anchor.Scale` is the whole difference.
  it("reports its size in the mover's coordinate space, not the panel's", function()
    setup({ w = 305, h = 101, scale = 0.8 })
    local w, h = registered(ns, host).getSize("CAP_ROW")
    assert.are.equal(305 * 0.8, w)
    assert.are.equal(101 * 0.8, h)
  end)

  it("reports no size rather than a wrong one when the panel cannot be read", function()
    setup()
    ns.Anchor.Scale = function() return nil end
    assert.is_nil(registered(ns, host).getSize("CAP_ROW"))
  end)

  it("is hidden exactly when cap is not ordering, and is asked without a key", function()
    setup({ ordering = false })
    assert.is_true(registered(ns, host).isHidden())
    ns.Anchor.Ordering = function() return true end
    assert.is_false(registered(ns, host).isHidden())
  end)

  it("answers isAnchored the same with a key and without one", function()
    setup()
    local elem = registered(ns, host)
    assert.is_false(elem.isAnchored())
    assert.is_false(elem.isAnchored("CAP_ROW"))
  end)

  -- The registration exists so other UI can anchor TO the row. Declaring either of these
  -- would keep every other assertion green and remove the point.
  it("declines resize and nothing else", function()
    setup()
    local elem = registered(ns, host)
    assert.is_true(elem.noResize)
    assert.is_nil(elem.noAnchorTarget)
    assert.is_nil(elem.noAnchorTo)
  end)

  it("stores a drop into cap's own place, as the player's hand", function()
    setup()
    local elem = registered(ns, host)
    elem.savePos("CAP_ROW", "CENTER", "CENTER", 120, -240, "TOPLEFT", "TOPLEFT")
    local s = place:Store()
    assert.are.equal(120, s.x)
    assert.are.equal(-240, s.y)
    assert.is_true(s.placed)
    assert.are.equal("move", s.by)
  end)

  it("refuses a position it was not promised rather than converting one", function()
    setup()
    local said = {}
    ns.Emit = function(line) said[#said + 1] = line end
    registered(ns, host).savePos("CAP_ROW", "TOPLEFT", "TOPLEFT", 5, 5)
    assert.is_false(place:Store().placed)
    assert.are.equal(1, #said)
  end)

  it("offers no position until the row has been placed", function()
    setup()
    local elem = registered(ns, host)
    assert.is_nil(elem.loadPos("CAP_ROW"))
    elem.savePos("CAP_ROW", "CENTER", "CENTER", 7, 9)
    local pos = elem.loadPos("CAP_ROW")
    assert.are.same({ point = "CENTER", relPoint = "CENTER", x = 7, y = 9 }, pos)
  end)

  it("round-trips a drop back through the host's own load shape", function()
    setup()
    local elem = registered(ns, host)
    elem.savePos("CAP_ROW", "CENTER", "CENTER", -33, 44)
    elem.clearPos("CAP_ROW")
    assert.is_nil(elem.loadPos("CAP_ROW"))
    assert.are.equal(0, place:Store().x)
    assert.are.equal(-200, place:Store().y)
  end)

  it("tells the host about a resize only once it has something registered", function()
    setup()
    ns.Ellesmere.Resized()
    assert.are.equal(0, #host.resized)
    registered(ns, host)
    ns.Ellesmere.Resized()
    assert.are.same({ "CAP_ROW" }, host.resized)
  end)

  -- MakeUnlockElement is optional and only renames the four position fields; the host does
  -- the same aliasing itself. Both routes must land the same element.
  it("goes through the host's factory when it has one", function()
    setup(nil, true)
    local elem = registered(ns, host)
    assert.are.equal("CAP_ROW", elem.key)
    assert.is_function(elem.savePosition)
    assert.is_function(elem.loadPosition)
    assert.is_function(elem.clearPosition)
    assert.is_function(elem.applyPosition)
  end)
end)
