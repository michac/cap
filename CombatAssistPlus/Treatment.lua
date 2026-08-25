-- Treatment.lua — what a verdict draws. Pure.
--
-- ⚠ ONE exception to "every number is ns.Style's", and it is deliberate: `Treatment.BAR` is the
-- independent Tyrant bar's two colours, written here rather than in the shelf. The bar is not a
-- render-shelf primitive — it is not drawn on a Cooldown Manager row, it takes no cue and no
-- verdict, and `render-shelf.md` declares nothing about it. Giving it a token group would put a
-- style for a surface the shelf does not govern into the file that governs the overlay. It moves
-- to the shelf the day a catalog declares `bar` and the bar has to agree with the rows beside it.
local ADDON, ns = ...

local Treatment = {}
ns.Treatment = Treatment

Treatment.BAR = {
  track = { r = 0.06, g = 0.06, b = 0.08, a = 0.72 },
  fill = { r = 0.72, g = 0.58, b = 0.18, a = 0.82 },
}

--- ⚠ This does NOT read `ns.Style.verdicts`, and the reason is structural rather than an
--- oversight: that table is keyed by the docs' row-state NAMES (`cd`, `open`, `press`,
--- `ruled-sealed`, `weave`), and the engine's verdict — `Signal`'s struct of `member` / `oncd` /
--- `cues` — never carries one. There is no key to look up. The shelf's table is how a human
--- states a row's state in a catalog or a scenario; this is how cap computes one. The addon's
--- one reader of that table is the `/cap style` gallery, for `swipe`.
---
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
