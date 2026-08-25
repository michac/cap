-- Window.lua — the chrome for a cap panel that is not the overlay: a movable, closable,
-- tabbed, scrolling frame on UIParent. It carries no content and no style numbers; a
-- caller hands it tabs whose `build` fills a pane and returns that pane's height.
--
-- Plain non-secure frame, for Frame.lua's reason: protection is one-way and contagious
-- to parents and anchor targets, so taking it on would buy nothing.
local ADDON, ns = ...

local issecretvalue = issecretvalue

ns.Window = ns.Window or {}
local Window = ns.Window

-- BasicFrameTemplateWithInset draws its inset at TOPLEFT (4,-24) / BOTTOMRIGHT (-6,4).
-- The scroll frame sits inside that, with the right edge pulled in for the scroll bar,
-- which ScrollFrameTemplate anchors OUTSIDE the scroll frame's right edge.
local INSET = { left = 12, top = 30, right = 30, bottom = 10 }
local GRIP_H, TAB_X, TAB_Y = 24, 11, 2
local MIN_W, MIN_H = 240, 200

-- ---------------------------------------------------------------------------
-- Pure
-- ---------------------------------------------------------------------------

--- The tab whose id is exactly `name`, or nil. Exact match on the whole argument, never a
--- substring: `sty` is an error, not a shortcut for `style`. A blank name matches nothing.
function Window.TabIndex(tabs, name)
  if type(name) ~= "string" or name == "" then return nil end
  name = name:lower()
  for i, tab in ipairs(tabs) do
    if tab.id == name then return i end
  end
  return nil
end

--- Big enough for the content plus the chrome around it, never past the screen it has to
--- fit on, never below the floor.
function Window.Fit(content, chrome, available, margin, floor)
  local want = content + chrome
  if type(available) == "number" and available > 0 then
    want = math.min(want, available - (margin or 0))
  end
  return math.max(want, floor or 0)
end

-- ---------------------------------------------------------------------------
-- Saved place
-- ---------------------------------------------------------------------------

-- File scope runs before ADDON_LOADED, so the scratch carries the shape until ns.db
-- exists — the same reason, and the same shape, as Frame.lua's. The root is resolved on
-- every call: a subtable cached while ns.db was nil is an orphan nothing ever saves.
local scratch = {}
function Window.Store(key)
  local root = ns.db or scratch
  local all = root.windows
  if type(all) ~= "table" then
    all = {}
    root.windows = all
  end
  local s = all[key]
  if type(s) ~= "table" then
    s = {}
    all[key] = s
  end
  return s
end

local readable = ns.readable

-- ⚠ A window is never scaled, so its centre offset from UIParent's is already in UIParent
-- units and needs none of Frame.lua's scale normalisation. Call SetScale on one and this
-- becomes wrong.
local function savePlace(f, s)
  if not (f:IsRectValid() and UIParent:IsRectValid()) then return end
  local cx, cy = f:GetCenter()
  local ux, uy = UIParent:GetCenter()
  if not readable(cx, cy, ux, uy) then return end
  s.x, s.y = cx - ux, cy - uy
end

local function applyPlace(f, s)
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", s.x, s.y)
end

local function extent(getter)
  local v = getter(UIParent)
  if type(v) ~= "number" or issecretvalue(v) or v <= 0 then return nil end
  return v
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

--- `spec` is { name, title, key, width, height, tabs = {{id, label, build}}, onSelect,
--- onHide, x, y }. Every pane is built here, so no later tab click creates a frame.
function Window.New(spec)
  local f = CreateFrame("Frame", spec.name, UIParent, "BasicFrameTemplateWithInset")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:Hide()
  f.TitleText:SetText(spec.title)

  local s = Window.Store(spec.key)
  if type(s.x) ~= "number" then s.x = spec.x or 0 end
  if type(s.y) ~= "number" then s.y = spec.y or 0 end

  f:SetSize(Window.Fit(spec.width, INSET.left + INSET.right, extent(UIParent.GetWidth), 40, MIN_W),
            Window.Fit(spec.height, INSET.top + INSET.bottom, extent(UIParent.GetHeight), 80, MIN_H))
  applyPlace(f, s)

  f:SetMovable(true)
  local grip = CreateFrame("Frame", nil, f)
  grip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  grip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -GRIP_H, 0)
  grip:SetHeight(GRIP_H)
  grip:EnableMouse(true)
  grip:RegisterForDrag("LeftButton")
  grip:SetScript("OnDragStart", function() f:StartMoving() end)
  grip:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    savePlace(f, s)
    applyPlace(f, s)
  end)

  local scroll = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", INSET.left, -INSET.top)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -INSET.right, INSET.bottom)

  local w = { frame = f, scroll = scroll }
  local panes = {}

  -- Idempotent: a pane is built once and cached, so re-selecting a tab redraws nothing.
  local function pane(i)
    if panes[i] then return panes[i] end
    local p = CreateFrame("Frame", nil, scroll)
    p:SetWidth(spec.width)
    p:SetHeight(math.max(spec.tabs[i].build(p) or 1, 1))
    p:Hide()
    panes[i] = p
    return p
  end

  --- SetScrollChild does not hide the child it displaced, so the outgoing pane is hidden
  --- by hand or two tabs draw at once.
  function w:Select(i)
    local p = pane(i)
    for _, other in ipairs(panes) do other:Hide() end
    scroll:SetScrollChild(p)
    p:Show()
    scroll:SetVerticalScroll(0)
    PanelTemplates_SetTab(f, i)
    if spec.onSelect then spec.onSelect(i, p) end
  end

  function w:Show() f:Show() end
  function w:Hide() f:Hide() end
  function w:IsShown() return f:IsShown() end

  for i, tab in ipairs(spec.tabs) do
    local b = CreateFrame("Button", nil, f, "PanelTabButtonTemplate")
    b:SetID(i)
    b:SetText(tab.label)
    if i == 1 then b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", TAB_X, TAB_Y) end
    b:SetScript("OnClick", function(self) w:Select(self:GetID()) end)
    pane(i)
  end
  -- After every tab exists: this anchors 2..n off their predecessors.
  PanelTemplates_SetNumTabs(f, #spec.tabs)

  f:SetScript("OnHide", function() if spec.onHide then spec.onHide() end end)
  w:Select(1)
  return w
end
