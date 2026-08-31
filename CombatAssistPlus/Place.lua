-- Place.lua — one implementation of "a frame the player drags, and the game remembers".
--
-- This was Frame.lua's, and single-panel throughout: `store()` hardcoded one key and ten
-- functions closed over one file-local `panel`. cap now has TWO placeable frames — the
-- cooldown panel and `CombatAssistPlusRow`, the CDM row — so the machinery is parameterised
-- rather than copied. A copy is two places to fix a scale bug, and the scale maths here is
-- the part that is easy to get wrong.
--
-- ⚠ WHY THIS IS NOT Window.lua's. `Window.lua:71-73` may skip scale normalisation because a
-- window is never scaled; the row panel is scaled on every apply, to match the item frames it
-- carries. Window's keying is the right shape and its arithmetic is not, so this file takes
-- the first and keeps Frame.lua's second.
--
-- Free-floating by design: everything here anchors to UIParent. Plain non-secure frames —
-- protection is one-way and contagious to parents and anchor targets, so taking it on would
-- cost the ability to lay anything out mid-pull and buy nothing.
local ADDON, ns = ...


ns.Place = ns.Place or {}
local Place = ns.Place

local readable = ns.readable

-- Registration order is the order the player is told about them, so it is a list and not
-- just the key map.
local registry, byKey = {}, {}
local unlocked, ready = false, false

-- ---------------------------------------------------------------------------
-- The store
-- ---------------------------------------------------------------------------

-- File scope runs before ADDON_LOADED, so the scratch carries the shape until ns.db exists —
-- Frame.lua's reason and Window.lua's. The root is resolved on every call: a subtable cached
-- while ns.db was nil is an orphan that never reaches SavedVariables.
local scratch = {}

-- The single-panel era wrote `db.frame`. Read once into the keyed store, or an upgrading
-- player's panel jumps back to the default the first time they log in. The old key is left
-- in place rather than deleted: it costs a few bytes, and a player who downgrades to the
-- previous build finds their panel where they left it instead of at the origin.
local LEGACY = { frame = "frame" }

local function all()
  local root = ns.db or scratch
  local t = root.places
  if type(t) ~= "table" then
    t = {}
    root.places = t
  end
  return t, root
end

--- The saved place for one key, created on first ask. `defaults` fills only absent fields,
--- so a build that adds one does not clobber what the player set.
function Place.Store(key, defaults)
  local t, root = all()
  local s = t[key]
  if type(s) ~= "table" then
    local legacy = LEGACY[key]
    local old = legacy and root[legacy]
    if type(old) == "table" then
      s = { x = old.x, y = old.y, placed = old.placed }
    else
      s = {}
    end
    t[key] = s
  end
  if defaults then
    if type(s.x) ~= "number" then s.x = defaults.x end
    if type(s.y) ~= "number" then s.y = defaults.y end
    if type(s.placed) ~= "boolean" then s.placed = false end
  end
  return s
end

-- ---------------------------------------------------------------------------
-- One placeable frame
-- ---------------------------------------------------------------------------

local Handle = {}
Handle.__index = Handle

function Handle:Store()
  return Place.Store(self.key, { x = self.defaultX, y = self.defaultY })
end

-- The frame's scale expressed against UIParent's, so the maths never assumes who the parent
-- is or that either one is at 1.0.
function Handle:Ratio()
  local mine, theirs = self.frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
  if not readable(mine, theirs) or theirs == 0 then return nil end
  return mine / theirs
end

-- Persisted form is the offset of the frame's centre from UIParent's, in UIParent units at
-- scale 1.0 — the normalisation Blizzard's Edit Mode stores, and the shape EllesmereUI's
-- mover hands back. Restore divides by the frame's current scale.
function Handle:Capture()
  local f = self.frame
  if not (f:IsRectValid() and UIParent:IsRectValid()) then return nil end
  local ratio = self:Ratio()
  if not ratio then return nil end
  local cx, cy = f:GetCenter()
  local ux, uy = UIParent:GetCenter()
  if not readable(cx, cy, ux, uy) then return nil end
  return cx * ratio - ux, cy * ratio - uy
end

--- Puts the frame where the store says. A no-op mid-drag: the player's hand outranks an
--- event, and re-applying under one snaps the frame out from under the cursor.
function Handle:Apply()
  if self.dragging then return false end
  local s, f = self:Store(), self.frame
  local ratio = self:Ratio() or 1
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", s.x / ratio, s.y / ratio)
  return true
end

function Handle:Save()
  local x, y = self:Capture()
  if not x then
    ns.Emit(self.noun .. " position is unreadable — keeping the last saved place.")
    return false
  end
  local s = self:Store()
  s.x, s.y, s.placed = x, y, true
  return true
end

--- Adopts wherever the frame currently sits as its saved place, ONCE. This is how a frame
--- whose position used to be derived from somebody else's geometry becomes one the player
--- owns without appearing to jump on the login that changes it.
function Handle:Seed()
  if self:Store().placed then return false end
  return self:Save()
end

function Handle:Reset()
  local s = self:Store()
  s.x, s.y, s.placed = self.defaultX, self.defaultY, false
  self:Apply()
  return s
end

function Handle:Describe()
  local s = self:Store()
  return ("%d, %d"):format(math.floor(s.x + 0.5), math.floor(s.y + 0.5))
end

-- ---------------------------------------------------------------------------
-- Setup chrome — only ever visible while unlocked
-- ---------------------------------------------------------------------------

function Handle:BuildChrome()
  if self.chrome then return end
  local f = self.frame
  local parts = {}
  self.chrome = parts

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(f)
  bg:SetColorTexture(0, 0, 0, 0.55)
  parts[#parts + 1] = bg

  local function edge(a, b, horizontal)
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(0.25, 1.0, 0.56, 0.9)
    t:SetPoint(a)
    t:SetPoint(b)
    if horizontal then t:SetHeight(1) else t:SetWidth(1) end
    parts[#parts + 1] = t
  end
  edge("TOPLEFT", "TOPRIGHT", true)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  edge("TOPLEFT", "BOTTOMLEFT", false)
  edge("TOPRIGHT", "BOTTOMRIGHT", false)

  local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("CENTER", f, "CENTER", 0, 0)
  label:SetText(self.label)
  parts[#parts + 1] = label
end

function Handle:ShowChrome(show)
  if not self.chrome then return end
  for _, part in ipairs(self.chrome) do
    if show then part:Show() else part:Hide() end
  end
end

-- ---------------------------------------------------------------------------
-- Drag
-- ---------------------------------------------------------------------------

function Handle:EndDrag()
  if not self.dragging then return end
  self.dragging = false
  self.frame:StopMovingOrSizing()
  self:Save()
  self:Apply()
  if self.onPlaced then self.onPlaced(self) end
end

function Handle:Lock()
  self:EndDrag()
  self.frame:EnableMouse(false)
  self.frame:SetMovable(false)
  self:ShowChrome(false)
end

function Handle:Unlock()
  self:BuildChrome()
  self.frame:EnableMouse(true)
  self.frame:SetMovable(true)
  self:ShowChrome(true)
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

--- `spec` is { key, frame, noun, label, x, y, onPlaced }. `noun` is what the player is
--- called it in chat — cap has more than one of these now, so every line needs a subject.
--- Returns the handle; registering the same key twice returns the first.
function Place.Register(spec)
  assert(type(spec) == "table" and type(spec.key) == "string", "Place.Register: key is required")
  assert(spec.frame and spec.frame.SetPoint, "Place.Register: a frame is required")
  if byKey[spec.key] then return byKey[spec.key] end

  local h = setmetatable({
    key = spec.key,
    frame = spec.frame,
    noun = spec.noun or "frame",
    label = spec.label or "cap — drag to place",
    defaultX = spec.x or 0,
    defaultY = spec.y or 0,
    onPlaced = spec.onPlaced,
    dragging = false,
  }, Handle)
  byKey[h.key] = h
  registry[#registry + 1] = h

  local f = h.frame
  f:SetClampedToScreen(true)
  f:EnableMouse(false)
  f:SetMovable(false)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    if not unlocked or InCombatLockdown() then return end
    h.dragging = true
    self:StartMoving()
  end)
  f:SetScript("OnDragStop", function() h:EndDrag() end)

  -- A frame registered after login has missed the login apply, so it takes one now.
  if ready then h:Apply() end
  if unlocked then h:Unlock() end
  return h
end

function Place.Get(key) return byKey[key] end
function Place.Unlocked() return unlocked end

function Place.Lock()
  unlocked = false
  for _, h in ipairs(registry) do h:Lock() end
end

function Place.Unlock()
  unlocked = true
  for _, h in ipairs(registry) do h:Unlock() end
end

function Place.ApplyAll()
  for _, h in ipairs(registry) do h:Apply() end
end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------

--- ONE unlock gesture for every frame cap can place. `/cap <verb> [<arg>]` is the whole
--- command budget — `reset` already occupies the argument slot — so a per-frame verb would
--- need a depth the parser does not have. Unlocking both at once also reads better: the
--- question a player has is "where do I want cap's furniture", not "which one first".
local moveActions = {
  [""] = function()
    if unlocked then
      Place.Lock()
      for _, h in ipairs(registry) do
        ns.Emit(h.noun .. " locked at " .. h:Describe() .. ".")
      end
      return
    end
    if InCombatLockdown() then
      ns.Emit("placement is out of combat only.")
      return
    end
    if #registry == 0 then
      ns.Emit("nothing to place yet.")
      return
    end
    Place.Unlock()
    local nouns = {}
    for _, h in ipairs(registry) do nouns[#nouns + 1] = h.noun end
    ns.Emit("unlocked " .. table.concat(nouns, " and ")
      .. " — drag to place, then /cap move again to lock.")
  end,

  reset = function()
    if InCombatLockdown() then
      ns.Emit("placement is out of combat only.")
      return
    end
    for _, h in ipairs(registry) do
      h:Reset()
      if h.onPlaced then h.onPlaced(h) end
      ns.Emit(h.noun .. " reset to " .. h:Describe() .. ".")
    end
  end,
}

ns.RegisterCommand{
  name = "move", order = 40, args = "[reset]",
  desc = "Unlock cap's panel and CDM row to drag them, or reset their positions",
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
    Place.ApplyAll()
  elseif event == "PLAYER_REGEN_DISABLED" then
    if unlocked then
      Place.Lock()
      ns.Emit("combat — cap's frames locked.")
    end
  elseif ready then
    -- The saved offset is normalised to UIParent at scale 1.0, so a scale or resolution
    -- change makes the current anchor wrong until it is re-applied.
    Place.ApplyAll()
  end
end)
