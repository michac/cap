-- Frame.lua — the free-floating movable panel: the substrate every drawn row sits on.
--
-- ⚠ It no longer owns being movable. Drag, chrome, the saved position and `/cap move` all
-- live in `Place.lua`, because cap has a second placeable frame now (the CDM row) and this
-- file's machinery was single-panel throughout. What is left here is the one thing that was
-- ever specific to this panel: stacking child rows and sizing to them.
--
-- Free-floating by design: it anchors to UIParent, never to the Cooldown Manager.
-- Plain non-secure frame — cap only ever shows things, and protection is one-way
-- and contagious to parents and anchor targets, so taking it on would buy nothing
-- and cost the ability to lay bars out mid-pull.
local ADDON, ns = ...


local FRAME_NAME = "CombatAssistPlusPanel"

local LAYOUT = {
  width = 220,
  rowHeight = 18,
  spacing = 2,
  padding = 4,
  minHeight = 26,
}

local DEFAULT_X, DEFAULT_Y = 0, -160

local rows = {}

ns.Frame = ns.Frame or {}

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------

local panel = CreateFrame("Frame", FRAME_NAME, UIParent)
panel:SetFrameStrata("MEDIUM")
panel:SetSize(LAYOUT.width, LAYOUT.minHeight)
panel:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_X, DEFAULT_Y)
panel:Show()

ns.Place.Register{
  key = "frame", frame = panel, noun = "panel",
  label = "cap — drag to place", x = DEFAULT_X, y = DEFAULT_Y,
}

-- ---------------------------------------------------------------------------
-- Child rows — the M4 seam
-- ---------------------------------------------------------------------------

local function relayout()
  local y = -LAYOUT.padding
  for _, row in ipairs(rows) do
    row.region:ClearAllPoints()
    row.region:SetPoint("TOPLEFT", panel, "TOPLEFT", LAYOUT.padding, y)
    row.region:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LAYOUT.padding, y)
    row.region:SetHeight(row.height)
    y = y - row.height - LAYOUT.spacing
  end
  local content = (#rows > 0) and (-y - LAYOUT.spacing + LAYOUT.padding) or 0
  panel:SetWidth(LAYOUT.width)
  panel:SetHeight(math.max(LAYOUT.minHeight, content))
end

local function indexOf(region)
  for i, row in ipairs(rows) do
    if row.region == region then return i end
  end
end

-- A module hands over a region and the height it wants; the panel stacks rows
-- top-down and resizes to them. The height is a caller-supplied plain number so
-- no child's geometry can make the panel's own size — and hence its anchoring —
-- secret.
function ns.Frame.Attach(region, height)
  assert(type(region) == "table" and region.SetPoint, "Frame.Attach: a region is required")
  assert(height == nil or type(height) == "number", "Frame.Attach: height must be a number")
  if indexOf(region) then return region end
  if region.GetParent and region:GetParent() ~= panel then region:SetParent(panel) end
  rows[#rows + 1] = { region = region, height = height or LAYOUT.rowHeight }
  relayout()
  return region
end

function ns.Frame.Detach(region)
  local i = indexOf(region)
  if not i then return false end
  table.remove(rows, i)
  region:ClearAllPoints()
  region:Hide()
  relayout()
  return true
end

function ns.Frame.Get() return panel end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

-- Position is Place.lua's; the only thing left for this file to do at login is lay its
-- children out once, since Attach may have run before the panel had a valid rect.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
  relayout()
end)
