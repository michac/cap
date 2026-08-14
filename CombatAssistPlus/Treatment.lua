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

function Treatment.For(verdict)
  local lane = verdict and verdict.tier
  local spec = lane and ns.Style and ns.Style.lanes[lane]
  if not spec then return { emphasized = false } end
  return { emphasized = true, lane = lane, thickness = spec.thickness_px }
end
