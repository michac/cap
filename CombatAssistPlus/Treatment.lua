-- Treatment.lua — what a verdict looks like. Pure: no frames, no game reads, no clock.
--
-- Three properties the table below exists to hold, all from spec.md §3.1:
--   * the ladder HIGH -> MEDIUM -> LOW -> none is monotone in BRIGHTNESS, so it survives
--     a colour-blind read and a small icon — hue is the accent, never the signal;
--   * each tier owns a DISJOINT brightness band and a grade moves an entry only inside
--     its own, which is "a grade never changes the tier" as arithmetic rather than as an
--     intention;
--   * polarity is carried by SHAPE. The hold glyph is the only shape in the vocabulary,
--     which is what makes "press" and "hold" impossible to confuse.
local ADDON, ns = ...

local Treatment = {}
ns.Treatment = Treatment

local ORDER = { "HIGH", "MEDIUM", "LOW" }
Treatment.ORDER = ORDER

-- Grade 0 reads `dim`, grade 1 reads `bright`, and an ungraded entry reads the midpoint:
-- no grade means the ability is neither the most nor the least urgent thing its tier can
-- be, so it sits in the middle of the band rather than at either end.
local TIERS = {
  HIGH = {
    tier = "HIGH",
    hue = { r = 1.00, g = 0.92, b = 0.55 },
    thickness = 3,
    alpha = { dim = 0.82, bright = 1.00 },
  },
  MEDIUM = {
    tier = "MEDIUM",
    hue = { r = 0.45, g = 0.70, b = 0.95 },
    thickness = 2,
    alpha = { dim = 0.56, bright = 0.86 },
  },
  LOW = {
    tier = "LOW",
    veil = { dim = 0.42, bright = 0.20 },
  },
}

-- No tier held. Not an absent state: cap has an opinion about this ability and right now
-- the opinion is "not now", so the icon recedes rather than disappearing.
local NONE = { veil = { dim = 0.62, bright = 0.62 } }

-- A neutral slate in no tier's hue family, on a dark plate so it reads over a bright
-- icon. Two vertical bars, bottom-centre — the shape is what carries polarity.
local HOLD = {
  hold = true,
  hue = { r = 0.80, g = 0.82, b = 0.88 },
  alpha = 0.95,
  plate = { r = 0.04, g = 0.04, b = 0.06, a = 0.72 },
  bar = { width = 3, height = 9, gap = 3 },
  inset = 3,
}
Treatment.HOLD = HOLD

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

--- The look of one tier at a given grade; `nil` grade takes the band's midpoint and an
--- unknown name takes the *none* treatment. Reusable on a marker as well as on an icon,
--- which is what lets a positive cue be drawn in the tier it stands for (§3.1).
function Treatment.Tier(name, grade)
  local t = TIERS[name] or NONE
  local g = (type(grade) == "number") and clamp01(grade) or 0.5
  local d = { tier = t.tier }
  if t.hue then
    d.ring = {
      r = t.hue.r, g = t.hue.g, b = t.hue.b,
      a = lerp(t.alpha, g),
      thickness = t.thickness,
    }
    d.veil = 0
  else
    d.veil = lerp(t.veil, g)
  end
  return d
end

--- The one scalar the ladder is ordered by: the light a ring puts on screen, or the
--- light a veil takes away.
function Treatment.Brightness(d)
  if d and d.ring then return d.ring.a * luma(d.ring) end
  return -((d and d.veil) or 0)
end

--- The treatment a cue's marker is drawn in. A positive cue borrows the tier it stands
--- for; a negative one takes the hold treatment, which belongs to no tier.
function Treatment.Mark(cue)
  if cue and cue.polarity == "negative" then return HOLD end
  return Treatment.Tier(cue and cue.tier)
end

--- The ink a marker is drawn in: a tier's own ring, or the hold slate. Nil for a veil-only tier.
function Treatment.Ink(m)
  if m and m.ring then return m.ring.r, m.ring.g, m.ring.b, m.ring.a end
  if m and m.hue then return m.hue.r, m.hue.g, m.hue.b, m.alpha end
  return nil
end

--- The distinct ring thicknesses the table uses, ascending. A surface builds one ring per
--- thickness up front so its paint path never has to resize anything.
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
