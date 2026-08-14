-- Frame.lua — the free-floating movable panel (spec.md §3.4): drag to place,
-- position saved, placement out of combat only. M4's substrate.
--
-- Free-floating by design: it anchors to UIParent, never to the Cooldown Manager.
-- Plain non-secure frame — cap only ever shows things, and protection is one-way
-- and contagious to parents and anchor targets, so taking it on would buy nothing
-- and cost the ability to lay bars out mid-pull.
local ADDON, ns = ...

local issecretvalue = issecretvalue

local FRAME_NAME = "CombatAssistPlusPanel"

local LAYOUT = {
  width = 220,
  rowHeight = 18,
  spacing = 2,
  padding = 4,
  minHeight = 26,
}

local DEFAULT_X, DEFAULT_Y = 0, -160

local unlocked, dragging, ready = false, false, false
local chrome
local rows = {}

ns.Frame = ns.Frame or {}

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------

local panel = CreateFrame("Frame", FRAME_NAME, UIParent)
panel:SetFrameStrata("MEDIUM")
panel:SetSize(LAYOUT.width, LAYOUT.minHeight)
panel:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_X, DEFAULT_Y)
panel:SetClampedToScreen(true)
panel:EnableMouse(false)
panel:SetMovable(false)
panel:RegisterForDrag("LeftButton")
panel:Show()

-- ---------------------------------------------------------------------------
-- Saved position
-- ---------------------------------------------------------------------------

-- The panel's keys are created here rather than in Core's DEFAULTS so this file
-- stays the only one that knows their shape — but the root table is Core's alone.
-- Two identities for one root is how a write lands in an orphan that never
-- reaches SavedVariables. This file runs at file scope, before ADDON_LOADED, so
-- the scratch carries the shape until ns.db exists.
local scratch = {}
local function store()
  local root = ns.db or scratch
  local s = root.frame
  if type(s) ~= "table" then
    s = {}
    root.frame = s
  end
  if type(s.x) ~= "number" then s.x = DEFAULT_X end
  if type(s.y) ~= "number" then s.y = DEFAULT_Y end
  if type(s.placed) ~= "boolean" then s.placed = false end
  return s
end

local function readable(...)
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v == nil or issecretvalue(v) then return false end
  end
  return true
end

-- The panel's scale expressed against UIParent's, so the maths below never
-- assumes who the parent is.
local function scaleRatio()
  local mine, theirs = panel:GetEffectiveScale(), UIParent:GetEffectiveScale()
  if not readable(mine, theirs) or theirs == 0 then return nil end
  return mine / theirs
end

-- Persisted form is the offset of the panel's centre from UIParent's, in
-- UIParent units at scale 1.0 — the normalisation Blizzard's Edit Mode stores.
-- Restore divides by the panel's current scale.
local function capturePosition()
  if not (panel:IsRectValid() and UIParent:IsRectValid()) then return nil end
  local ratio = scaleRatio()
  if not ratio then return nil end
  local cx, cy = panel:GetCenter()
  local ux, uy = UIParent:GetCenter()
  if not readable(cx, cy, ux, uy) then return nil end
  return cx * ratio - ux, cy * ratio - uy
end

local function applyPosition()
  local s = store()
  local ratio = scaleRatio() or 1
  panel:ClearAllPoints()
  panel:SetPoint("CENTER", UIParent, "CENTER", s.x / ratio, s.y / ratio)
end

local function savePosition()
  local x, y = capturePosition()
  if not x then
    ns.Emit("frame position is unreadable — keeping the last saved place.")
    return false
  end
  local s = store()
  s.x, s.y, s.placed = x, y, true
  return true
end

-- ---------------------------------------------------------------------------
-- Setup chrome — only ever visible while unlocked
-- ---------------------------------------------------------------------------

local function buildChrome()
  if chrome then return end
  chrome = { parts = {} }

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(panel)
  bg:SetColorTexture(0, 0, 0, 0.55)
  chrome.parts[#chrome.parts + 1] = bg

  local function edge(a, b, horizontal)
    local t = panel:CreateTexture(nil, "BORDER")
    t:SetColorTexture(0.25, 1.0, 0.56, 0.9)
    t:SetPoint(a)
    t:SetPoint(b)
    if horizontal then t:SetHeight(1) else t:SetWidth(1) end
    chrome.parts[#chrome.parts + 1] = t
  end
  edge("TOPLEFT", "TOPRIGHT", true)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  edge("TOPLEFT", "BOTTOMLEFT", false)
  edge("TOPRIGHT", "BOTTOMRIGHT", false)

  local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("CENTER", panel, "CENTER", 0, 0)
  label:SetText("cap — drag to place")
  chrome.parts[#chrome.parts + 1] = label
end

local function showChrome(show)
  if not chrome then return end
  for _, part in ipairs(chrome.parts) do
    if show then part:Show() else part:Hide() end
  end
end

-- ---------------------------------------------------------------------------
-- Lock state
-- ---------------------------------------------------------------------------

local function endDrag()
  if not dragging then return end
  dragging = false
  panel:StopMovingOrSizing()
  savePosition()
  applyPosition()
end

local function lock()
  endDrag()
  unlocked = false
  panel:EnableMouse(false)
  panel:SetMovable(false)
  showChrome(false)
end

local function unlock()
  buildChrome()
  unlocked = true
  panel:EnableMouse(true)
  panel:SetMovable(true)
  showChrome(true)
end

panel:SetScript("OnDragStart", function(self)
  if not unlocked or InCombatLockdown() then return end
  dragging = true
  self:StartMoving()
end)

panel:SetScript("OnDragStop", function()
  endDrag()
end)

-- ---------------------------------------------------------------------------
-- Child rows — the M4 seam
-- ---------------------------------------------------------------------------

-- A child may need more room than the bar column does; the widest request wins and it never
-- shrinks below LAYOUT.width.
local requested = LAYOUT.width

local function relayout()
  local width = math.max(LAYOUT.width, requested)
  local y = -LAYOUT.padding
  for _, row in ipairs(rows) do
    row.region:ClearAllPoints()
    row.region:SetPoint("TOPLEFT", panel, "TOPLEFT", LAYOUT.padding, y)
    row.region:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LAYOUT.padding, y)
    row.region:SetHeight(row.height)
    y = y - row.height - LAYOUT.spacing
  end
  local content = (#rows > 0) and (-y - LAYOUT.spacing + LAYOUT.padding) or 0
  panel:SetWidth(width)
  panel:SetHeight(math.max(LAYOUT.minHeight, content))
end

function ns.Frame.RequestWidth(w)
  if type(w) ~= "number" or w <= requested then return end
  requested = w
  relayout()
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

function ns.Frame.Relayout() relayout() end
function ns.Frame.Get() return panel end
function ns.Frame.RowCount() return #rows end
function ns.Frame.IsUnlocked() return unlocked end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------

local function describePosition(s)
  return ("%d, %d"):format(math.floor(s.x + 0.5), math.floor(s.y + 0.5))
end

local moveActions = {
  [""] = function()
    if unlocked then
      lock()
      ns.Emit("frame locked at " .. describePosition(store()) .. ".")
      return
    end
    if InCombatLockdown() then
      ns.Emit("placement is out of combat only.")
      return
    end
    unlock()
    ns.Emit("frame unlocked — drag it, then /cap move again to lock.")
  end,

  reset = function()
    if InCombatLockdown() then
      ns.Emit("placement is out of combat only.")
      return
    end
    local s = store()
    s.x, s.y, s.placed = DEFAULT_X, DEFAULT_Y, false
    applyPosition()
    ns.Emit("frame reset to " .. describePosition(s) .. ".")
  end,
}

ns.RegisterCommand{
  name = "move", order = 40, args = "[reset]",
  desc = "Unlock the cooldown panel to drag it, or reset its position",
  handler = function(rest)
    local action = moveActions[(rest or ""):lower()]
    if not action then
      ns.Emit("usage: /cap move  or  /cap move reset")
      return
    end
    action()
  end,
}

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    ready = true
    applyPosition()
    relayout()
  elseif event == "PLAYER_REGEN_DISABLED" then
    if unlocked or dragging then
      lock()
      ns.Emit("combat — frame locked.")
    end
  elseif ready then
    -- The saved offset is normalised to UIParent at scale 1.0, so a scale or
    -- resolution change makes the current anchor wrong until it is re-applied.
    applyPosition()
  end
end)
