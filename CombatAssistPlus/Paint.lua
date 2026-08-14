-- Paint.lua — the render shelf's primitives, built once. Every number comes from ns.Style.
--
-- Both the live overlay and the /cap style gallery draw through these builders, so the two
-- cannot show different pixels — that divergence is what render-shelf.md exists to end.
local ADDON, ns = ...

local Paint = {}
ns.Paint = Paint

-- One ticker walks every visible badge's frame list (cdm-rider-patterns.md §14).
local STEP_TICK = 0.05
local stepping, ticker = {}, nil

-- ---------------------------------------------------------------------------
-- Pure geometry — the same arithmetic the artifact's generated CSS does
-- ---------------------------------------------------------------------------

--- Badge sizes measured against the shelf's nominal icon, never against the host: a CDM item's
--- own width is a game read that can come back secret, and a badge that silently sized to nil
--- would draw nothing.
function Paint.Geometry()
  local b = ns.Style.badges
  local d = b.diameter_pct / 100 * ns.Style.surfaces.icon_px
  return {
    diameter = d,
    step = d + b.padding_px,
    overhang = b.overhang_px,
    plate = d * b.plate.scale,
    sprite = d * (1 - 2 * b.sprite_inset_pct / 100),
  }
end

--- Offsets from the host's TOPRIGHT for a slot's own TOPRIGHT. Slot 1 hangs off the corner;
--- 2 steps left along the top edge, 3 steps down the right edge.
function Paint.SlotOffset(slot)
  local g = Paint.Geometry()
  if slot == 2 then return g.overhang - g.step, g.overhang end
  if slot == 3 then return g.overhang, g.overhang - g.step end
  return g.overhang, g.overhang
end

--- Which frame of a cue's list is showing, 1-based. REPEAT wraps; BOUNCE plays forward then
--- back, which is what the animation system's own loop type does.
function Paint.FrameIndex(count, loop, elapsed, stepSeconds)
  if count < 2 or stepSeconds <= 0 then return 1 end
  local k = math.floor(elapsed / stepSeconds)
  if loop == "BOUNCE" then
    local period = 2 * (count - 1)
    local p = k % period
    return (p < count and p or period - p) + 1
  end
  return k % count + 1
end

-- ---------------------------------------------------------------------------
-- V2 · lane border, with the one-shot arrival snap
-- ---------------------------------------------------------------------------

local function buildRing(host, thickness)
  local parts = {}
  local function part(a, b, horizontal)
    local t = host:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 1, 1, 1)
    if horizontal then
      t:SetPoint(a); t:SetPoint(b); t:SetHeight(thickness)
    else
      t:SetPoint(a, host, a, 0, -thickness)
      t:SetPoint(b, host, b, 0, thickness)
      t:SetWidth(thickness)
    end
    t:Hide()
    parts[#parts + 1] = t
  end
  part("TOPLEFT", "TOPRIGHT", true)
  part("BOTTOMLEFT", "BOTTOMRIGHT", true)
  part("TOPLEFT", "BOTTOMLEFT", false)
  part("TOPRIGHT", "BOTTOMRIGHT", false)
  return parts
end

--- Fire-and-forget, so it must land on its final values: animations restore alpha only under
--- SetToFinalAlpha, and never restore vertex color at all.
function Paint.Arrival(edge)
  local a = ns.Style.arrival
  local snap = edge:CreateAnimationGroup()
  local grow = snap:CreateAnimation("Scale")
  grow:SetScaleFrom(a.from_scale, a.from_scale)
  grow:SetScaleTo(1, 1)
  grow:SetOrigin("CENTER", 0, 0)
  grow:SetDuration(a.duration_s)
  grow:SetSmoothing(a.smoothing)
  local fade = snap:CreateAnimation("Alpha")
  fade:SetFromAlpha(a.from_alpha)
  fade:SetToAlpha(1)
  fade:SetDuration(a.duration_s)
  fade:SetSmoothing(a.smoothing)
  snap:SetToFinalAlpha(true)
  return snap
end

--- One border per host, carrying a pre-built ring for every lane. Switching lane is Show/Hide
--- plus SetVertexColor, which is all cap is allowed to write in combat.
function Paint.Border(host, lane)
  local edge = CreateFrame("Frame", nil, host)
  edge:SetAllPoints(host)
  edge:Hide()

  local rings = {}
  for name, spec in pairs(ns.Style.lanes) do
    rings[name] = buildRing(edge, spec.thickness_px)
  end
  local snap = Paint.Arrival(edge)

  local border = { frame = edge, rings = rings }

  function border:SetLane(name)
    local spec = ns.Style.lanes[name]
    if not spec then return self:Hide() end
    for ring, parts in pairs(rings) do
      for _, t in ipairs(parts) do
        if ring == name then
          t:SetVertexColor(spec.rgb[1], spec.rgb[2], spec.rgb[3])
          t:SetAlpha(1)
          t:Show()
        else
          t:Hide()
        end
      end
    end
    self.lane = name
    edge:Show()
  end

  function border:Hide()
    self.lane = nil
    edge:Hide()
  end

  --- The arrival snap: played on the event that something became available, then it rests.
  function border:Snap()
    if not edge:IsShown() then return end
    snap:Stop()
    snap:Play()
  end

  if lane then border:SetLane(lane) end
  return border
end

-- ---------------------------------------------------------------------------
-- V4 · veil
-- ---------------------------------------------------------------------------

function Paint.Veil(host)
  local v = ns.Style.veil
  local t = host:CreateTexture(nil, "OVERLAY", nil, 1)
  t:SetColorTexture(v.rgb[1], v.rgb[2], v.rgb[3], v.alpha)
  t:SetAllPoints(host)
  t:Hide()
  return t
end

-- ---------------------------------------------------------------------------
-- V5 · corner badge, and V5.1's cue frames
-- ---------------------------------------------------------------------------

local function texturePath(name)
  return ns.Style.badges.texture_root .. name .. ".tga"
end

local function tick()
  local now = GetTime()
  local any = false
  for badge in pairs(stepping) do
    any = true
    badge:Step(now)
  end
  if not any and ticker then
    ticker:Cancel()
    ticker = nil
  end
end

local function stepEvery(badge, on)
  if on then
    stepping[badge] = true
    if not ticker then ticker = C_Timer.NewTicker(STEP_TICK, tick) end
  else
    stepping[badge] = nil
  end
end

--- A badge is a plate, a glyph, and — for the one positive cue — a halo behind both. The
--- glyph holds full alpha always; only the halo breathes.
function Paint.Badge(host, key)
  local cue = ns.Style.cues[key]
  if not cue then return nil end
  local b, g = ns.Style.badges, Paint.Geometry()
  local tint = cue.rgb or b.rgb

  local slot = CreateFrame("Frame", nil, host)
  slot:SetSize(g.diameter, g.diameter)
  slot:SetPoint("TOPRIGHT", host, "TOPRIGHT", Paint.SlotOffset(cue.slot))
  slot:Hide()

  local halo
  if cue.glow then
    halo = Paint.Glow(slot, key)
  end

  local plate = slot:CreateTexture(nil, "OVERLAY", nil, 6)
  plate:SetTexture(texturePath(b.plate.texture))
  plate:SetVertexColor(b.plate.rgb[1], b.plate.rgb[2], b.plate.rgb[3])
  plate:SetAlpha(b.plate.alpha)
  plate:SetSize(g.plate, g.plate)
  plate:SetPoint("CENTER")

  local sprite = slot:CreateTexture(nil, "OVERLAY", nil, 7)
  sprite:SetSize(g.sprite, g.sprite)
  sprite:SetPoint("CENTER")

  local count = #cue.frames
  local badge = {
    frame = slot, cue = key, sprite = sprite, plate = plate, halo = halo,
    seconds = count > 0 and cue.duration_s / count or 0,
  }

  --- Pooled frames outlive their colour: an animation that stopped restores alpha and never
  --- vertex colour, so both are written again on every show.
  function badge:Show()
    sprite:SetVertexColor(tint[1], tint[2], tint[3])
    sprite:SetAlpha(1)
    self.started = GetTime()
    self:Step(self.started)
    slot:Show()
    if halo then halo:Play() end
    stepEvery(self, count > 1)
  end

  function badge:Hide()
    slot:Hide()
    if halo then halo:Stop() end
    stepEvery(self, false)
  end

  function badge:Step(now)
    local i = Paint.FrameIndex(count, cue.loop, now - (self.started or now), self.seconds)
    if i ~= self.shown then
      sprite:SetTexture(texturePath(cue.frames[i]))
      sprite:SetVertexColor(tint[1], tint[2], tint[3])
      self.shown = i
    end
  end

  return badge
end

--- The halo, drawn under the plate so it reads as light escaping from behind the badge. It is
--- the only looping motion in the style, and it carries no information — the glyph does.
function Paint.Glow(slot, key)
  local cue = ns.Style.cues[key]
  local glow = cue and cue.glow
  if not glow then return nil end
  local tint = cue.rgb or ns.Style.badges.rgb
  local g = Paint.Geometry()

  local t = slot:CreateTexture(nil, "OVERLAY", nil, 5)
  t:SetTexture(texturePath(ns.Style.badges.halo_texture))
  t:SetVertexColor(tint[1], tint[2], tint[3])
  t:SetSize(g.diameter * glow.scale, g.diameter * glow.scale)
  t:SetPoint("CENTER")
  t:SetAlpha(glow.alpha_min)

  local group = t:CreateAnimationGroup()
  group:SetLooping("BOUNCE")
  local breathe = group:CreateAnimation("Alpha")
  breathe:SetFromAlpha(glow.alpha_min)
  breathe:SetToAlpha(glow.alpha_max)
  breathe:SetDuration(1 / glow.hz)
  breathe:SetSmoothing("IN_OUT")

  return {
    texture = t,
    Play = function() if not group:IsPlaying() then group:Play() end end,
    Stop = function()
      group:Stop()
      t:SetAlpha(glow.alpha_min)
    end,
  }
end
