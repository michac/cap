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

  it("measures a swatch row and an arrival stage the way the gallery draws them", function()
    assert.equal(16, ns.StylePanel.RowWidth(0, 56, 18, 8))
    assert.equal(72, ns.StylePanel.RowWidth(1, 56, 18, 8))
    assert.equal(294, ns.StylePanel.RowWidth(4, 56, 18, 8))
    -- pad*2 + subject + isolation + the stage, which is symmetric about its own centre.
    assert.equal(496, ns.StylePanel.StageWidth(56, 120, 2, 62, 8))
    assert.equal(248, ns.StylePanel.StageWidth(56, 120, 0, 62, 8))
  end)

  it("files every Part 7 entry onto one lab tab AND gives the gallery a way to draw it", function()
    local seen = 0
    for key, entry in pairs(ns.LabStyle) do
      if key:sub(1, 1) ~= "_" then
        seen = seen + 1
        local tab = ns.StylePanel.LabTab(entry.draws)
        assert.is_true(tab == "stripes" or tab == "arrival" or tab == "ready",
                       key .. " has no lab tab to draw on")
        -- An entry nothing can draw is invisible in the client, which is the only place a
        -- treatment can be judged at all — so it is worse than absent, not merely unfinished.
        assert.is_true(ns.StylePanel.CanDraw(entry.draws),
                       key .. " draws `" .. tostring(entry.draws) .. "`, which nothing implements")
      end
    end
    -- ⚠ PENDING, not a failure — see lab_spec.lua. An empty lab is Part 7's resting state, and a
    -- contract with no subject must go quiet rather than red.
    if seen == 0 then pending("the lab is empty — no entry to file onto a tab, by design") end
  end)

  it("routes each experiment family to its own tab, and anything else to stripes", function()
    assert.equal("arrival", ns.StylePanel.LabTab("arrival-sweep"))
    assert.equal("arrival", ns.StylePanel.LabTab("arrival-ghost"))
    assert.equal("ready", ns.StylePanel.LabTab("ready-glow"))
    assert.equal("ready", ns.StylePanel.LabTab("ready-line"))
    assert.equal("stripes", ns.StylePanel.LabTab("stripes"))
    assert.equal("stripes", ns.StylePanel.LabTab(nil))
  end)
end)
