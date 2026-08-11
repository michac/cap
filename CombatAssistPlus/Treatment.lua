-- Treatment.lua — provisional static pixels for the first simplification flight. Pure.
local ADDON, ns = ...

local Treatment = {}
ns.Treatment = Treatment

Treatment.EMPHASIS = { r = 1.00, g = 0.82, b = 0.22, a = 0.95, thickness = 3 }
Treatment.MARKERS = {
  dreadstalkers = { r = 0.30, g = 0.78, b = 1.00, a = 1.00, slot = "left" },
  grimoire = { r = 0.78, g = 0.38, b = 1.00, a = 1.00, slot = "right" },
}
Treatment.BAR = {
  track = { r = 0.06, g = 0.06, b = 0.08, a = 0.72 },
  fill = { r = 0.72, g = 0.58, b = 0.18, a = 0.82 },
}

function Treatment.For(verdict)
  if not (verdict and verdict.emphasized) then return { emphasized = false } end
  local d = { emphasized = true, ring = {} }
  for k, v in pairs(Treatment.EMPHASIS) do d.ring[k] = v end
  if type(verdict.strength) == "number" then
    d.ring.a = 0.55 + 0.40 * math.max(0, math.min(1, verdict.strength))
  end
  return d
end

function Treatment.Marker(id)
  return Treatment.MARKERS[id]
end
