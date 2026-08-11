-- Treatment.lua — what a verdict looks like. Pure: no frames, no game reads, no clock.
--
-- The property the table below exists to hold (spec.md §3.1): the ladder HIGH -> MEDIUM
-- -> LOW -> none is ORDERED, three emphasis levels being levels rather than three
-- colours. `Brightness` is the one scalar that order is asserted against.
local ADDON, ns = ...

local Treatment = {}
ns.Treatment = Treatment

local ORDER = { "HIGH", "MEDIUM", "LOW" }
Treatment.ORDER = ORDER

-- Grade 0 reads `dim`, grade 1 `bright`, and an ungraded entry reads the MIDPOINT: no
-- grade means the ability is neither the most nor the least urgent thing its tier can be.
local TIERS = {
  HIGH = {
    tier = "HIGH",
    hue = { r = 1.00, g = 0.92, b = 0.55 },
    thickness = 3,
    alpha = { dim = 0.82, bright = 1.00 },
    pulse = 2.5,
  },
  MEDIUM = {
    tier = "MEDIUM",
    hue = { r = 0.45, g = 0.70, b = 0.95 },
    thickness = 2,
    alpha = { dim = 0.48, bright = 0.78 },
    pulse = 1.2,
  },
  LOW = {
    tier = "LOW",
    hue = { r = 0.80, g = 0.82, b = 0.88 },
    thickness = 1,
    -- The bright end is what a person picked on a real spell icon at CDM size.
    alpha = { dim = 0.36, bright = 0.50 },
    pulse = 0.5,
    -- ⚠ No ink, deliberately: this hue IS the hold slate, so a LOW-tier marker and a hold
    -- marker would be one colour. A positive cue therefore stands for HIGH or MEDIUM.
    ink = false,
  },
}

-- No tier held, and not an absent state: cap has an opinion and right now it is "not now",
-- so the icon recedes. The only row with no ring, which is what the LOW -> none step is.
local NONE = { veil = { dim = 0.60, bright = 0.60 } }

-- One Blizzard atlas played as a flipbook: no library, no license question. Grid, duration
-- and the 1.4x host scale are Blizzard's own (ActionButtonSpellAlerts.xml:25, .lua:20).
local RING = {
  atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook",
  rows = 6, columns = 5, frames = 30, seconds = 1.0,
  blend = "ADD",
  scale = 1.4,
}
Treatment.RING = RING

-- `trough` is a fraction of the tier's OWN alpha, so the pulse and the paint path write one
-- channel. `stride` staggers row N (see `Phase`) and the rates are deliberately unequal:
-- WCAG 2.3.1's general flash threshold is ~21,824 px² of a 10° field and a 40x40 icon is
-- 1,600 px², so ~14 icons flashing IN SYNC cross it and the same 14 offset never approach
-- it. MIL-STD-1472 says to synchronise; we take the seizure floor. Do NOT align the rates,
-- and do not make the stride a whole fraction.
local PULSE = { trough = 0.68, stride = 0.6180339887498949 }
Treatment.PULSE = PULSE

-- The count marker. Its emphasis is SIZE, not opacity: flashing text is capped at 2 Hz /
-- ~70 % on-time and measurably slows word recognition.
local COUNT = { size = 18, pulse = { from = 0.88, to = 1.15, seconds = 0.6 } }
Treatment.COUNT = COUNT

-- A neutral slate on a dark plate, so it reads over a bright icon. Two vertical bars,
-- bottom-centre — the SHAPE is what carries polarity, because LOW shares the hue.
local HOLD = {
  hold = true,
  hue = { r = 0.80, g = 0.82, b = 0.88 },
  alpha = 0.95,
  plate = { r = 0.04, g = 0.04, b = 0.06, a = 0.72 },
  bar = { width = 3, height = 9, gap = 3 },
  inset = 3,
}
Treatment.HOLD = HOLD

-- The §3.4 bars. `track` is the empty part; `rest` is the fill where no band held — the slate
-- LOW and hold share, reading UNDER LOW's dimmest because a bar has no ring to carry the
-- LOW -> none step (treatment_spec pins it). Only that ordering is derived; the values are picked.
local BAR = {
  track = { r = 0.06, g = 0.06, b = 0.08, a = 0.72 },
  rest = { r = 0.80, g = 0.82, b = 0.88, a = 0.24 },
}
Treatment.BAR = BAR

-- Rec. 709 luma. The ladder is ordered by one number a test can compare, not three.
local function luma(c)
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
end

local function lerp(band, g)
  return band.dim + (band.bright - band.dim) * g
end

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

--- The look of one tier at a given grade; `nil` grade takes the midpoint and an unknown
--- name takes *none*. Reusable on a marker, which is what draws a cue in its own tier (§3.1).
function Treatment.Tier(name, grade)
  local t = TIERS[name] or NONE
  local g = (type(grade) == "number") and clamp01(grade) or 0.5
  local d = { tier = t.tier }
  if t.hue then
    d.ring = {
      r = t.hue.r, g = t.hue.g, b = t.hue.b,
      a = lerp(t.alpha, g),
      thickness = t.thickness,
      pulse = t.pulse,
    }
    d.ink = t.ink ~= false
    d.veil = 0
  else
    d.veil = lerp(t.veil, g)
  end
  return d
end

--- The one scalar the ladder is ordered by: a ring's light, or the light a veil takes away.
function Treatment.Brightness(d)
  if d and d.ring then return d.ring.a * luma(d.ring) end
  return -((d and d.veil) or 0)
end

local RANK = {}
for i, name in ipairs(ORDER) do RANK[name] = #ORDER - i + 1 end

--- Tier order as a number, *none* lowest. This is what "the higher of two tiers" compares
--- when one row carries two entries; a tier's bands and another's may reach the same
--- brightness, so `Brightness` orders inside one tier and never across two.
function Treatment.Rank(d)
  return RANK[d and d.tier] or 0
end

--- The treatment a cue's marker is drawn in. A positive cue borrows the tier it stands
--- for; a negative one takes the hold treatment, which belongs to no tier.
function Treatment.Mark(cue)
  if cue and cue.polarity == "negative" then return HOLD end
  return Treatment.Tier(cue and cue.tier)
end

--- The ink a marker is drawn in: a tier's own ring, or the hold slate. Nil where the tier
--- refuses one — see LOW's `ink = false` above, and *none*, which puts no light on the icon.
function Treatment.Ink(m)
  if m and m.hold then return m.hue.r, m.hue.g, m.hue.b, m.alpha end
  if m and m.ring and m.ink then return m.ring.r, m.ring.g, m.ring.b, m.ring.a end
  return nil
end

--- The fill one §3.4 bar is drawn in: its tier's own hue and emphasis, or the resting slate
--- where no band held. A cooldown counts down whether or not cap has an opinion about it.
function Treatment.Fill(d)
  local ring = d and d.ring
  if ring then return ring.r, ring.g, ring.b, ring.a end
  return BAR.rest.r, BAR.rest.g, BAR.rest.b, BAR.rest.a
end

--- The one scalar a BAR's ladder is ordered by — a bar has no veil, so `Brightness` cannot.
function Treatment.FillBrightness(d)
  local r, g, b, a = Treatment.Fill(d)
  return a * luma({ r = r, g = g, b = b })
end

--- The pulse for a descriptor, or nil where the tier does not pulse. The animation drives
--- the alpha the paint path writes, so a surface must RE-ARM on every tier or grade change.
--- `seconds` is one sweep; `cycle` is the bounce round trip a `Phase` fraction spans.
function Treatment.Pulse(d)
  local ring = d and d.ring
  local hz = ring and ring.pulse
  if type(hz) ~= "number" or hz <= 0 then return nil end
  return { hz = hz, seconds = 0.5 / hz, cycle = 1 / hz, from = ring.a * PULSE.trough, to = ring.a }
end

--- Where in its own cycle the Nth drawn row starts, as a FRACTION — a surface multiplies by
--- that row's live period, because fixed seconds alias back into alignment. See `PULSE`.
function Treatment.Phase(index)
  local n = (type(index) == "number" and index > 0) and index or 1
  return ((n - 1) * PULSE.stride) % 1
end

--- The distinct ring thicknesses, ascending. The drawn ring is one flipbook shape, so this
--- is the FALLBACK geometry's ladder — built once, so its paint path never resizes anything.
function Treatment.Thicknesses()
  local seen, out = {}, {}
  for _, name in ipairs(ORDER) do
    local t = TIERS[name].thickness
    if t and not seen[t] then
      seen[t] = true
      out[#out + 1] = t
    end
  end
  table.sort(out)
  return out
end

--- The icon descriptor for one verdict. `grade` is passed through as it arrived: a
--- resolved number was cap's own arithmetic, a channel descriptor is the client's and cap
--- cannot evaluate it.
function Treatment.For(verdict)
  local v = verdict or {}
  local grade = v.grade
  local resolved = (type(grade) == "table") and grade.value or nil

  local d = Treatment.Tier(v.tier, resolved)
  if resolved ~= nil then
    d.grade = resolved
  elseif type(grade) == "table" then
    d.grade = grade
  end

  d.hold = false
  for _, cue in ipairs(v.cues or {}) do
    if cue.polarity == "negative" then d.hold = true end
  end
  return d
end
