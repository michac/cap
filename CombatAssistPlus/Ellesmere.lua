-- Ellesmere.lua — offers cap's CDM row to EllesmereUI's mover, so other UI can anchor to it.
--
-- Optional and one-way: absent the host nothing here runs. The saved position stays cap's —
-- the host gets a VIEW of `Place`'s store, never a second copy, so `/cap move` and a mover
-- drag write the same number.
--
-- The surface it speaks to: knowledge/addon-dev/cdm-rider-patterns.md §4.8.
local ADDON, ns = ...


ns.Ellesmere = ns.Ellesmere or {}
local Bridge = ns.Ellesmere

-- ⚠ Element keys share ONE flat namespace across every addon that registers, so the prefix is
-- the whole defence against two of them clobbering each other.
local KEY = "CAP_ROW"

-- Past the host's own login apply, whichever of its two branches ran (§4.8).
local SETTLE = 1.0

-- Resolved once, at registration: `getFrame` must be side-effect-free.
local frame, place
local registered = false

local function host()
  local E = _G.EllesmereUI
  if type(E) == "table" and type(E.RegisterUnlockElements) == "function" then return E end
  return nil
end

-- ---------------------------------------------------------------------------
-- The element
-- ---------------------------------------------------------------------------

local element = {
  key = KEY,
  label = "cap — CDM row",
  group = "Combat Assist Plus",
  order = 1,
  -- ⚠ Declining resize keeps the grid cap's. Declining nothing ELSE is what leaves the row
  -- usable as an anchor target, which is the entire point of registering it.
  noResize = true,

  getFrame = function() return frame end,

  --- ⚠ THE SCALE FACTOR IS NOT OPTIONAL. `GridSize` is panel units; the host reads UIParent's.
  --- Pinned by `ellesmere_spec`.
  getSize = function()
    local Anchor = ns.Anchor
    if not (Anchor and Anchor.GridSize and Anchor.Scale) then return nil end
    local w, h = Anchor.GridSize()
    local scale = Anchor.Scale()
    if not (ns.plain(w) and ns.plain(h) and ns.plain(scale)) then return nil end
    return w * scale, h * scale
  end,

  --- Exactly when cap draws nothing. Called with no arguments.
  isHidden = function()
    local Anchor = ns.Anchor
    return not (Anchor and Anchor.Ordering and Anchor.Ordering())
  end,

  --- The row hangs off UIParent and nothing else. Asked both with a key and without one.
  isAnchored = function() return false end,

  --- ⚠ SEVEN ARGUMENTS, already normalised to the shape `Place` stores (§4.8). Args 6 and 7
  --- are the pre-conversion point, which cap has no use for.
  savePos = function(_, point, relPoint, x, y)
    if not place then return end
    if point ~= "CENTER" or relPoint ~= "CENTER" then
      -- Refused, not converted: guessing at a shape we were promised never arrives is how a
      -- drag lands somewhere the player did not put it.
      ns.Emit(("a mover offered the CDM row a %s/%s position, which cap cannot store."):format(
        tostring(point), tostring(relPoint)))
      return
    end
    place:Place(x, y)
  end,

  --- nil until placed, so an unplaced panel takes the host's default rather than asserting
  --- cap's un-seeded origin as a position somebody chose.
  loadPos = function()
    if not place then return nil end
    local s = place:Store()
    if not s.placed then return nil end
    return { point = "CENTER", relPoint = "CENTER", x = s.x, y = s.y }
  end,

  clearPos = function() if place then place:Reset() end end,
  applyPos = function() if place then place:Apply() end end,
}

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

--- The panel's footprint changed with no `SetSize` for the host to have hooked (§4.8).
function Bridge.Resized()
  if not registered then return end
  local E = host()
  if E and E.NotifyElementResized then E.NotifyElementResized(KEY) end
end

function Bridge.Register()
  if registered then return false end
  local E = host()
  if not E then return false end
  local Anchor = ns.Anchor
  if not (Anchor and Anchor.Row) then return false end
  frame, place = Anchor.Row()
  if not (frame and place) then return false end

  local elem = E.MakeUnlockElement and E.MakeUnlockElement(element) or element
  E:RegisterUnlockElements({ elem }, "cap")
  registered = true

  -- A child whose target the host could not resolve yet was skipped, and nothing re-drives it.
  if C_Timer then
    C_Timer.After(SETTLE, function()
      if E.ReapplyOwnAnchor then E.ReapplyOwnAnchor(KEY) end
      if E.ReapplyAllUnlockAnchors then E.ReapplyAllUnlockAnchors() end
    end)
  end
  return true
end

function Bridge.Registered() return registered end

-- Guarded because the half above is unit-tested outside the client, where `CreateFrame` is not.
if CreateFrame then
  local events = CreateFrame("Frame")
  events:RegisterEvent("PLAYER_LOGIN")
  events:SetScript("OnEvent", function() Bridge.Register() end)
end
