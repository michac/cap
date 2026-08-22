-- Engine guarantee: every method the live overlay calls on a Paint-built object EXISTS on it.
--
-- ⚠ THIS TEST IS TEXTUAL, AND IT HAS TO BE. `mock_ns.lua` says the modules under test are pure
-- and that anything needing a `CreateFrame` stub does not belong there — which is right, and
-- which means no test in this suite can ever construct a badge, a border or a hatch. So the one
-- class of defect a pure suite is structurally blind to is *cap calling a method its own
-- constructor does not define*, and the only place left to catch it is the source text.
--
-- It is not hypothetical. `badge:SetPoint` arrived 2026-08-19 with the flowing badge stack and
-- shipped in v0.12.0 without ever being defined. It stayed invisible for three days because the
-- only catalog anyone ran was the Demonology PILOT, which declared no cues at all — so the
-- stack loop only ever reached its `badge:Hide()` branch. The first catalog with cues took the
-- whole of `paint()` down on its first row: no badges, no scan edges, no hatches, no keybind
-- labels, on every row at once, and the error reached nobody because `Sense.fireVerdicts`
-- pcall-protects its listeners by design.
--
-- These objects are PLAIN TABLES, not frames. A frame would inherit the widget API and a missing
-- method would be a typo; here it is a nil call.
local ROOT = "CombatAssistPlus/"

local function read(rel)
  local f = assert(io.open(ROOT .. rel, "r"))
  local text = f:read("*a")
  f:close()
  return text
end

--- Which Paint constructor builds each thing Overlay holds. Hand-written on purpose: this map
--- IS the contract, and generating it from the source would just re-derive the bug.
local OWNER = {
  ["badge"] = "badge",           -- Paint.Badge, via f.badges / f.gradedBadges
  ["f%.hatch"] = "hatch",        -- Paint.Hatch, Blizzard's cause
  ["f%.skip"] = "hatch",         -- Paint.Hatch, cap's own cause
  ["f%.border"] = "border",      -- Paint.Border
  ["f%.promo"] = "ring",         -- Paint.PromotionRing
}

--- Every `function <obj>:<Method>` Paint defines, as `{ [obj] = { [Method] = true } }`.
local function defined()
  local out = {}
  for obj, method in read("Paint.lua"):gmatch("function%s+([%a_]+):([%a_]+)%s*%(") do
    out[obj] = out[obj] or {}
    out[obj][method] = true
  end
  return out
end

describe("engine / surface", function()
  local have = defined()

  it("defines every method the overlay calls on a Paint-built table", function()
    local overlay = read("Overlay.lua")
    local checked = 0
    for pattern, obj in pairs(OWNER) do
      -- `:Method(` only — a `.frame:Method(` call goes to a real widget and is the client's API.
      for method in overlay:gmatch(pattern .. ":([%a_]+)%s*%(") do
        checked = checked + 1
        assert.is_true((have[obj] or {})[method] == true,
          ("Overlay calls %s:%s(), which Paint's `%s` table does not define. It is a plain " ..
           "table, so this is a nil call and it takes the WHOLE of paint() down — every row, " ..
           "not just this one."):format(pattern:gsub("%%", ""), method, obj))
      end
    end
    -- A map that matched nothing would pass silently while guaranteeing nothing, which is the
    -- failure mode this whole file exists to prevent.
    assert.is_true(checked >= 8, "the call map matched only " .. checked .. " call sites")
  end)

  it("keeps the badge's stack-placement method, which has no other way to be exercised",
    function()
      -- Named explicitly rather than left to the sweep above: the stack has no fixed slots, so
      -- Overlay re-anchors on EVERY update, and this is the method it re-anchors through.
      assert.is_true(have.badge.SetPoint, "Paint.Badge defines no SetPoint")
      assert.is_true(have.badge.Show and have.badge.Hide and have.badge.Step)
    end)

  it("gives the gallery the same guarantee, since it draws through the same builders", function()
    local panel = read("StylePanel.lua")
    for method in panel:gmatch("badge:([%a_]+)%s*%(") do
      assert.is_true(have.badge[method] == true,
        "StylePanel calls badge:" .. method .. "(), which Paint does not define")
    end
  end)
end)
