-- Treatment.lua — what a verdict draws. Pure; every number is ns.Style's.
local ADDON, ns = ...

local Treatment = {}
ns.Treatment = Treatment

Treatment.BAR = {
  track = { r = 0.06, g = 0.06, b = 0.08, a = 0.72 },
  fill = { r = 0.72, g = 0.58, b = 0.18, a = 0.82 },
}

--- ONE binary treatment: a row is IN THE SCAN or it is not (render-shelf.md V13). Priority is
--- row order plus the overlays, never a hue — membership (`verdict.member`, Signal's
--- scan_when evaluation) is the whole statement, and nothing finer exists to draw.
--- The RULED-OUT hatch (V11) is independent of the scan, and has TWO causes: the CDM says the
--- ability is down, or cap itself is ruling the row out with a negative cue. Both mean "not this
--- one", so both stripe -- in different colours, because the two verdicts have different owners.
---
--- ⚠ It generalises over POLARITY, never over a list of cue keys. `blocked`, `starved` and
--- `overcap` all hatch because all three declare themselves negative, and a cue added tomorrow is
--- covered the day it declares a polarity rather than the day someone remembers this function.
--- A cue the shelf does not know is treated as negative, which can only make the hatch stricter.
---
--- ⚠ This is Part 0.5's pass 2 drawn: *skip what the swipe ran down, and what wears a red cue.*
--- Until 2026-08-19 only the first half was visible.
function Treatment.For(verdict)
  local cues = (verdict or {}).cues or {}
  local skip = false
  for _, key in ipairs(cues) do
    if (ns.Style.cues[key] or {}).polarity ~= "positive" then skip = true end
  end
  return {
    scan = (verdict and verdict.member) == true,
    cues = cues,
    hatch = (verdict or {}).oncd == true,
    skip = skip,
  }
end
