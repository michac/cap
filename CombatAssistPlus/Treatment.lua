-- Treatment.lua — which shelf lane a verdict draws in. Pure; every number is ns.Style's.
local ADDON, ns = ...

local Treatment = {}
ns.Treatment = Treatment

Treatment.ORDER = { "ASAP", "SOON", "FALLBACK" }

-- The engine still speaks tiers and the shelf speaks lanes. This mapping is the whole seam:
-- it is total over ORDER, which is what keeps a catalog drawing while its spec is re-authored.
Treatment.LANE = {
  ASAP = "COOLDOWN",
  SOON = "ROTATION",
  FALLBACK = "FALLBACK",
}

Treatment.BAR = {
  track = { r = 0.06, g = 0.06, b = 0.08, a = 0.72 },
  fill = { r = 0.72, g = 0.58, b = 0.18, a = 0.82 },
}

function Treatment.For(verdict)
  local tier = verdict and verdict.tier
  local lane = tier and Treatment.LANE[tier]
  local spec = lane and ns.Style and ns.Style.lanes[lane]
  if not spec then return { emphasized = false } end
  return { emphasized = true, tier = tier, lane = lane, thickness = spec.thickness_px }
end
