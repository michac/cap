-- Treatment.lua — which shelf lane a verdict draws in. Pure; every number is ns.Style's.
local ADDON, ns = ...

local Treatment = {}
ns.Treatment = Treatment

-- A catalog's tier names ARE the shelf's role lanes; there is no mapping table between them.
-- ORDER stays as the validation set — every name here must be a lane ns.Style declares.
Treatment.ORDER = { "COOLDOWN", "ROTATION", "FALLBACK" }

Treatment.BAR = {
  track = { r = 0.06, g = 0.06, b = 0.08, a = 0.72 },
  fill = { r = 0.72, g = 0.58, b = 0.18, a = 0.82 },
}

--- THE VEIL IS DERIVED, NEVER AUTHORED: a row is veiled iff it wears at least one negative
--- cue. That is what makes render-shelf.md V4's "a badge with no veil does not occur"
--- mechanical rather than a promise, and it is what lets the one positive cue ride an
--- un-veiled press.
local function veiled(cues)
  local shelf = (ns.Style or {}).cues or {}
  for _, key in ipairs(cues or {}) do
    -- A cue declaring no polarity reads as negative — the reading that can only be stricter.
    if (shelf[key] or {}).polarity ~= "positive" then return true end
  end
  return false
end

--- CHARGES REPLACES the role lane rather than stacking with it: an ability wears exactly one
--- border (render-shelf.md V2). The role lane the rotation authored is unchanged and still
--- lives in the catalog; only the drawn hue moves.
function Treatment.For(verdict)
  local cues = (verdict or {}).cues or {}
  local lane = verdict and verdict.tier
  if lane and verdict.charged then lane = "CHARGES" end
  local spec = lane and ns.Style and ns.Style.lanes[lane]
  if not spec then return { emphasized = false, cues = cues, veil = veiled(cues) } end
  return {
    emphasized = true, lane = lane, thickness = spec.thickness_px,
    cues = cues, veil = veiled(cues),
  }
end
