-- The arithmetic and the dispatch behind the `/cap style` window. The chrome itself is a
-- client question and is not tested here: nothing in this repo has ever called CreateFrame.
local H = require("CombatAssistPlus.tests.mock_ns")

local function loaded()
  local ns = H.fresh()
  H.load(ns, "Lab.lua")
  H.load(ns, "Window.lua")
  -- Our own seam, not a client API: StylePanel registers its command at file scope.
  ns.RegisterCommand = function() end
  H.load(ns, "StylePanel.lua")
  return ns
end

local TABS = {
  { id = "style" }, { id = "stripes" }, { id = "arrival" },
}

describe("engine / style window", function()
  local ns
  before_each(function() ns = loaded() end)

  it("resolves a tab argument by its whole id and never by a substring", function()
    assert.equal(1, ns.Window.TabIndex(TABS, "style"))
    assert.equal(3, ns.Window.TabIndex(TABS, "arrival"))
    assert.equal(2, ns.Window.TabIndex(TABS, "STRIPES"))
    for _, near in ipairs({ "st", "styl", "stylex", "lab", "arr" }) do
      assert.is_nil(ns.Window.TabIndex(TABS, near), near .. " matched a tab")
    end
  end)

  it("treats a missing argument as 'leave the tab alone'", function()
    assert.is_nil(ns.Window.TabIndex(TABS, ""))
    assert.is_nil(ns.Window.TabIndex(TABS, nil))
  end)

  it("sizes to content plus chrome, capped by the screen and floored by a minimum", function()
    assert.equal(540, ns.Window.Fit(500, 40, nil, 0, 200))
    assert.equal(540, ns.Window.Fit(500, 40, 1000, 80, 200))
    -- A screen too small for the content wins over the content.
    assert.equal(320, ns.Window.Fit(500, 40, 400, 80, 200))
    -- ...but never past the floor, or the window has no room for its own tabs.
    assert.equal(200, ns.Window.Fit(500, 40, 220, 80, 200))
  end)

  it("measures a swatch row the way the gallery draws it", function()
    assert.equal(16, ns.StylePanel.RowWidth(0, 56, 18, 8))
    assert.equal(72, ns.StylePanel.RowWidth(1, 56, 18, 8))
    assert.equal(294, ns.StylePanel.RowWidth(4, 56, 18, 8))
    -- StageWidth went with the arrival experiments: the isolation stage had no other subject.
    assert.is_nil(ns.StylePanel.StageWidth)
  end)

  it("gives the gallery a way to draw every Part 7 entry", function()
    local seen = 0
    for key, entry in pairs(ns.LabStyle) do
      if key:sub(1, 1) ~= "_" then
        seen = seen + 1
        -- An entry nothing can draw is invisible in the client, which is the only place a
        -- treatment can be judged at all — so it is worse than absent, not merely unfinished.
        assert.is_true(ns.StylePanel.CanDraw(entry.draws),
                       key .. " draws `" .. tostring(entry.draws) .. "`, which nothing implements")
      end
    end
    -- ⚠ PENDING, not a failure — see lab_spec.lua. An empty lab is Part 7's resting state, and a
    -- contract with no subject must go quiet rather than red.
    if seen == 0 then pending("the lab is empty — nothing to draw, by design") end
  end)

  it("holds one lab tab, because the family split went with the families", function()
    -- Three tabs existed to give the arrival variants an isolation stage and the readiness ones
    -- the true row pitch. Both stages went with their entries, so the routing has no question
    -- left to answer and a tab that can never render advertises one the gallery cannot ask.
    assert.is_nil(ns.StylePanel.LabTab)
  end)
end)
