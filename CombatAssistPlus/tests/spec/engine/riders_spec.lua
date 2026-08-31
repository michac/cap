-- Riders.lua's two-stage stand-down decision. The frames, the SetPoint hooks and the dialog
-- are Anchor.lua's and are tested in the client and nowhere else (house rule 6).
local H = dofile("CombatAssistPlus/tests/mock_ns.lua")

local ns = {}
H.load(ns, "Riders.lua")
local Riders = ns.Riders

local function loader(...)
  local set = {}
  for _, name in ipairs({ ... }) do set[name] = true end
  return function(name) return set[name] or false end
end

describe("Riders.Loaded", function()
  it("names the known riders that are loaded, in table order", function()
    assert.same({ "EllesmereUI Cooldown Manager", "ArcUI" },
      Riders.Loaded(loader("ArcUI", "EllesmereUICooldownManager")))
  end)

  it("names nothing for an addon that is not a known rider", function()
    assert.same({}, Riders.Loaded(loader("WeakAuras", "EllesmereUIActionBars")))
  end)

  it("survives an absent or throwing loader rather than standing cap down", function()
    assert.same({}, Riders.Loaded(nil))
    assert.same({}, Riders.Loaded(function() error("refused") end))
  end)
end)

describe("Riders.Managing", function()
  it("is false while every point names the viewer's subtree", function()
    assert.is_false(Riders.Managing({ { "viewer" }, { "viewer" }, { "viewer" } }))
  end)

  it("is false for cap's own placement, which is not somebody else's", function()
    assert.is_false(Riders.Managing({ { "cap" }, { "cap" } }))
  end)

  it("is true on ONE stranger, because Blizzard writes one point per item frame", function()
    assert.is_true(Riders.Managing({ { "viewer" }, { "other" }, { "viewer" } }))
  end)

  it("reads no frames as nobody managing, so an empty row never nags", function()
    assert.is_false(Riders.Managing({}))
    assert.is_false(Riders.Managing(nil))
    assert.is_false(Riders.Managing({ {}, {} }))
  end)
end)

describe("Riders.Phrase", function()
  it("joins the labels the way a sentence would", function()
    assert.is_nil(Riders.Phrase({}))
    assert.equal("ArcUI", Riders.Phrase({ "ArcUI" }))
    assert.equal("ArcUI and Ayije CDM", Riders.Phrase({ "ArcUI", "Ayije CDM" }))
    assert.equal("A, B and C", Riders.Phrase({ "A", "B", "C" }))
  end)
end)

describe("Riders.Message", function()
  it("says nothing about a rider that is loaded but not placing the row", function()
    assert.is_nil(Riders.Message({ "ArcUI" }, false))
  end)

  it("names the rider and agrees with itself about number", function()
    local one = Riders.Message({ "ArcUI" }, true)
    assert.truthy(one:find("ArcUI is also arranging", 1, true))
    local two = Riders.Message({ "ArcUI", "Ayije CDM" }, true)
    assert.truthy(two:find("ArcUI and Ayije CDM are also arranging", 1, true))
  end)

  it("still has something to say when the rider is not one it knows", function()
    local text = Riders.Message({}, true)
    assert.truthy(text:find("Another addon is also arranging", 1, true))
  end)

  it("tells the player the row's order is not cap's, which is the point of saying it", function()
    assert.truthy(Riders.Message({ "ArcUI" }, true):find("should not be read as a priority", 1, true))
  end)
end)
