-- Treatment.lua — what a verdict draws. Pure; every number is ns.Style's.
local ADDON, ns = ...

local Treatment = {}
ns.Treatment = Treatment

Treatment.BAR = {
  track = { r = 0.06, g = 0.06, b = 0.08, a = 0.72 },
  fill = { r = 0.72, g = 0.58, b = 0.18, a = 0.82 },
}

--- ONE binary treatment: a row is IN THE SCAN or it is not (render-shelf.md V2). Priority is
--- row order plus the overlays, never a hue — so the role tier the catalog authored decides
--- only WHETHER the row is in the scan, and the tier itself stays in the model.
--- The cooldown hatch (V11) is independent of the scan: a row draws it whenever the CDM says the
--- ability is down, including a row with no tier selected, because "this button is unavailable" is
--- true regardless of whether cap had an opinion about it this instant.
function Treatment.For(verdict)
  local cues = (verdict or {}).cues or {}
  local hatch = (verdict or {}).oncd == true
  return {
    scan = (verdict and verdict.tier) ~= nil,
    cues = cues,
    hatch = hatch,
  }
end
