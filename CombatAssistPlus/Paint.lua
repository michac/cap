-- Paint.lua — the render shelf's primitives, built once. Every number comes from ns.Style.
--
-- Both the live overlay and the /cap style gallery draw through these builders, so the two
-- cannot show different pixels — that divergence is what render-shelf.md exists to end.
local ADDON, ns = ...

local issecretvalue = issecretvalue

local Paint = {}
ns.Paint = Paint

-- ONE ticker in the addon walks every visible frame-stepper — the badge sprites, and nothing
-- else now the scan edge is still (cdm-rider-patterns.md §14). Period: ns.Style.motion.tick_s.
local stepping, ticker = {}, nil

-- A stepper registers itself, but only its PARENT knows when the row went away: Overlay hides the
-- pooled frame, which leaves it shown-but-invisible and stepping forever. The visibility test is
-- the deregistration, so the ticker can actually reach zero and cancel.
local function tick()
  local now = GetTime()
  local any = false
  for entry in pairs(stepping) do
    if entry.frame:IsVisible() then
      any = true
      entry:Step(now)
    else
      stepping[entry] = nil
    end
  end
  if not any and ticker then
    ticker:Cancel()
    ticker = nil
  end
end

local function stepEvery(entry, on)
  if on then
    stepping[entry] = true
    if not ticker then ticker = C_Timer.NewTicker(ns.Style.motion.tick_s, tick) end
  else
    stepping[entry] = nil
  end
end

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

--- Offsets from the host's TOPRIGHT for the Nth badge's own TOPRIGHT, `index` 0-based.
---
--- The stack FLOWS down the right edge (render-shelf.md Part 1, V5): index 0 hangs off the
--- corner and each further badge steps one diameter+padding below it. There are no fixed slots,
--- so a badge's position depends on how many lower-ranked cues are showing beside it — which is
--- why this is called on every update rather than once at creation.
function Paint.StackOffset(index)
  local g = Paint.Geometry()
  return g.overhang, g.overhang - g.step * (index or 0)
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

--- How far a frame drawn at `scale` reaches past its own edge, per side.
function Paint.Overhang(size_px, scale)
  return size_px * (scale - 1) / 2
end

--- Whether that overhang crosses the gap to the next row — the pitch, less one frame.
function Paint.CrossesNeighbour(size_px, scale, pitch_px)
  return Paint.Overhang(size_px, scale) > pitch_px - size_px
end

--- Whole pixels, and at least one fatter than the resting ring it is flashed over.
function Paint.FatRing(thickness_px, mult)
  return math.max(math.floor(thickness_px * (mult or 1) + 0.5), thickness_px + 1)
end

--- Tiles a `tile_px` sheet across `w`x`h` at its authored size rather than stretching one copy,
--- offset along u by `phase_pct` of a stripe period. Returns SetTexCoord's left, right, bottom, top.
function Paint.StripeTexCoord(w, h, tile_px, pitch_px, phase_pct)
  if not tile_px or tile_px <= 0 then return 0, 1, 0, 1 end
  local u = (phase_pct or 0) / 100 * (pitch_px or tile_px) / tile_px
  return u, u + w / tile_px, 0, h / tile_px
end

--- A hand-replayed one-shot is rate limited to its own duration, as ShouldSnap limits the live
--- path: Stop() does not restore scale, so a second click mid-play can park a frame part-scaled.
function Paint.ShouldReplay(lastAt, now, duration)
  return not lastAt or (now - lastAt) >= duration
end

-- ---------------------------------------------------------------------------
-- V2 · the scan edge
-- ---------------------------------------------------------------------------

--- Fire-and-forget, so it must land on its final values: animations restore alpha only under
--- SetToFinalAlpha, and never restore vertex color at all. Nothing in the live overlay animates —
--- the scan edge is still — but Part 7's arrival variants are ABOUT a Scale animation, and `a`
--- lets each supply its own numbers.
function Paint.Arrival(edge, a)
  a = a or ns.Style.arrival
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

--- A host's drawn size, falling back to the nominal icon: a CDM item's width can read secret.
local function extent(host)
  local w, h = host:GetWidth(), host:GetHeight()
  if type(w) ~= "number" or type(h) ~= "number" or issecretvalue(w) or issecretvalue(h)
    or w <= 0 or h <= 0 then
    return ns.Style.surfaces.icon_px, ns.Style.surfaces.icon_px
  end
  return w, h
end

--- ⚠ INVARIANT no test can hold: the border frame carries its own size and is anchored by its
--- CENTRE, never SetAllPoints(host) — a pinned frame is not free to scale.
local function fit(edge, host)
  local w, h = extent(host)
  if w ~= edge.fitW or h ~= edge.fitH then
    edge:SetSize(w, h)
    edge.fitW, edge.fitH = w, h
  end
end

--- Four colour strips forming a ring on the host's own rect. Also the subject of Part 7's arrival
--- variants, which ask how the client scales this construction — so it is built once, here.
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

--- ONE border per host, and one treatment: the row is IN THE SCAN or it is not. Switching is
--- Show/Hide on a frame built out of combat, which is all cap is allowed to write in combat.
--- Nothing scales and nothing steps, so the edge cannot draw outside its own rect and cannot
--- reach a neighbouring row at any row gap.
---
--- ⚠ ADD blend, cap's first use: an additive edge reads as a hot line lit over the icon rather
--- than as a painted frame, which is what lets full brightness sit on so restrained an area
--- (`tokens.ready`). SetBlendMode's five values are Tier-1 — frames-textures-animation.md §5.2.
function Paint.Border(host)
  local edge = CreateFrame("Frame", nil, host)
  edge:SetPoint("CENTER", host, "CENTER", 0, 0)
  fit(edge, host)
  edge:Hide()

  local ready = ns.Style.ready
  local parts = buildRing(edge, ready.line_px)
  for _, t in ipairs(parts) do
    t:SetColorTexture(ready.rgb[1], ready.rgb[2], ready.rgb[3], ready.alpha)
    t:SetBlendMode("ADD")
    t:Show()
  end

  local border = { frame = edge, parts = parts }

  function border:SetShown(on)
    if not on then return self:Hide() end
    fit(edge, host)
    edge:Show()
  end

  function border:Hide() edge:Hide() end

  return border
end

-- ---------------------------------------------------------------------------
-- V11 · the cooldown hatch
-- ---------------------------------------------------------------------------

--- Diagonal stripes across the icon face, drawn while the Cooldown Manager says the ability is
--- down. One tiling white-alpha sheet tinted by SetVertexColor.
---
--- ⚠ The wrap mode is set ONCE, here, and can never be changed afterwards:
--- `[T2 bug: WoWUIBugs #250, created 2022-08-13, closed]` reports that re-calling SetTexture with
--- the same path and different wrap modes is ignored, because the setter short-circuits on the
--- asset rather than the whole argument list. The texcoords are set once for the same reason
--- there is no Step method — nothing about the hatch animates, so the in-combat path is Show/Hide
--- and nothing else.
---
--- `inset` is the overlay frame's own padding: the host is anchored PAD outside the item frame so
--- the border has room, and the hatch is a statement about the icon, which is inside that.
--@unverified whether the pitch authored for a 128px sheet reads as stripes rather than as a
--@unverified flat wash once tiled across a 56px icon, and whether black at this alpha reads as
--@unverified "ruled out" rather than as "dimmed" — render-shelf.md Part 5.
--- V11's hatch. `look` overrides colour and phase without touching the GEOMETRY, which is
--- shared: one sheet, one pitch, two verdicts. Blizzard's "on cooldown" uses the defaults;
--- cap's own "ruled out" passes `ns.Style.hatch.skip`.
function Paint.Hatch(host, inset, look)
  local h = ns.Style.hatch
  if not h then return nil end
  look = look or h
  inset = inset or 0

  -- A NEGATIVE inset is an overhang. cap's half of V11 is drawn `overhang_px` OUTSIDE the icon
  -- rect so its red covers V13's yellow scan edge: a ruled-out row should not also be wearing
  -- the "in the scan" line, and the yellow reads louder than the stripes because it is a hard
  -- line against a wash.
  inset = inset - (look.overhang_px or 0)

  local t = host:CreateTexture(nil, "ARTWORK")
  t:SetTexture(ns.Style.hatch.texture_root .. h.texture .. ".tga", "REPEAT", "REPEAT",
    "TRILINEAR")
  t:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -inset)
  t:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -inset, inset)
  t:SetVertexColor(look.rgb[1], look.rgb[2], look.rgb[3])
  t:SetAlpha(look.alpha)
  t:Hide()

  -- Its own border, at V13's weight, on a frame sized to the overhung rect. Only cap's half
  -- carries one: Blizzard's cause already has the swipe underneath it saying the same thing.
  local edgeFrame, edgeParts
  local edge = look.border
  if edge then
    edgeFrame = CreateFrame("Frame", nil, host)
    edgeFrame:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -inset)
    edgeFrame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -inset, inset)
    edgeParts = buildRing(edgeFrame, edge.line_px)
    for _, part in ipairs(edgeParts) do
      part:SetColorTexture(edge.rgb[1], edge.rgb[2], edge.rgb[3], edge.alpha)
      part:Show()
    end
    edgeFrame:Hide()
  end

  local hatch = { texture = t, edge = edgeFrame }

  --- Sized from the drawn extent so the stripe pitch is the same on any icon size the client
  --- hands us, rather than stretching with the button.
  function hatch:SetShown(on)
    if edgeFrame then edgeFrame:SetShown(on and true or false) end
    if not on then return t:Hide() end
    local w, hgt = extent(host)
    w, hgt = w - 2 * inset, hgt - 2 * inset
    if w ~= self.w or hgt ~= self.h then
      t:SetTexCoord(Paint.StripeTexCoord(w, hgt, h.tile_px, h.pitch_px, look.phase_pct))
      self.w, self.h = w, hgt
    end
    t:Show()
  end

  function hatch:Hide()
    t:Hide()
    if edgeFrame then edgeFrame:Hide() end
  end

  return hatch
end


--- V14 · the promotion ring. A glowing ring around the badge of a row wearing a positive cue.
---
--- A measured replica of Blizzard's proc glow (render-shelf.md V14). Three of its properties are
--- load-bearing and none of them was guessed:
---   · it does NOT pulse -- there is deliberately no alpha animation here. The life is hot spots
---     travelling the rim, and that lives in the SHEET. A promotion that blinks makes its own
---     information come and go, which is what the text flicker limits exist to forbid.
---   · it never covers the icon -- the art's interior measures a flat zero.
---   · it is NEUTRAL art, so `SetVertexColor` reaches the authored hue. Blizzard's is baked gold,
---     and this is the one way the replica beats the original.
---
--- ⚠ `1 / cols` is correct HERE and only here: `procring` is exactly cols x rows cells with no
--- power-of-two padding (8x64 = 512, 4x64 = 256). The lab's flipbooks are padded and must use
--- the precomputed `cell / sheet` step instead -- see StylePanel's `drawFlipbook`.
function Paint.PromotionRing(host)
  local p = ns.Style.promotion
  if not p then return nil end

  local layer = CreateFrame("Frame", nil, host)
  local d = Paint.Geometry().diameter * p.spread
  layer:SetSize(d, d)
  layer:SetPoint("CENTER", host, "CENTER", 0, 0)
  layer:SetFrameLevel(math.max(host:GetFrameLevel() - 1, 0))

  local t = layer:CreateTexture(nil, "BACKGROUND")
  t:SetTexture(p.texture_root .. p.texture .. ".tga", nil, nil, "TRILINEAR")
  t:SetAllPoints(layer)
  t:SetBlendMode("ADD")
  t:SetVertexColor(p.rgb[1], p.rgb[2], p.rgb[3])
  t:SetAlpha(p.alpha)

  local i, acc = 0, 0
  local function frame(k)
    local c, r = k % p.cols, math.floor(k / p.cols)
    t:SetTexCoord(c / p.cols, (c + 1) / p.cols, r / p.rows, (r + 1) / p.rows)
  end
  frame(0)
  layer:Hide()

  local ring = { frame = layer, texture = t }
  function ring:SetShown(on)
    if not on then
      layer:SetScript("OnUpdate", nil)
      return layer:Hide()
    end
    if layer:IsShown() then return end
    layer:SetScript("OnUpdate", function(_, elapsed)
      acc = acc + elapsed
      while acc >= 1 / p.fps do
        acc = acc - 1 / p.fps
        i = (i + 1) % p.frames
        frame(i)
      end
    end)
    layer:Show()
  end
  function ring:Hide() self:SetShown(false) end
  return ring
end

-- ---------------------------------------------------------------------------
-- V5 · corner badge, and V5.1's cue frames
-- ---------------------------------------------------------------------------

local function texturePath(name)
  return ns.Style.badges.texture_root .. name .. ".tga"
end

-- Badge art is drawn far smaller than it is authored; TRILINEAR is what keeps the minified
-- glyph clean instead of crunchy.
local function setArt(texture, name)
  texture:SetTexture(texturePath(name), nil, nil, "TRILINEAR")
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
  -- Anchored at the corner to start; Overlay re-anchors on every update, because the position
  -- is a function of the whole shown set rather than of this cue alone.
  slot:SetPoint("TOPRIGHT", host, "TOPRIGHT", Paint.StackOffset(0))
  slot:Hide()

  local halo
  if cue.glow then
    halo = Paint.Glow(slot, key)
  end

  local plate = slot:CreateTexture(nil, "OVERLAY", nil, 6)
  setArt(plate, b.plate.texture)
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
  ---
  --- ⚠ IDEMPOTENT. The live path repaints at 10 Hz, so restarting `started` on every call
  --- would reset the frame clock faster than one frame lasts and freeze the glyph on frame 1.
  function badge:Show()
    sprite:SetVertexColor(tint[1], tint[2], tint[3])
    sprite:SetAlpha(1)
    if not slot:IsShown() or not self.started then self.started = GetTime() end
    self:Step(GetTime())
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
      setArt(sprite, cue.frames[i])
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
  setArt(t, ns.Style.badges.halo_texture)
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

-- ---------------------------------------------------------------------------
-- Part 7 · the lab's primitives. Drawn by the /cap style gallery and by nothing else; every
-- number arrives as an argument, so a winner is promoted by aiming the builder at ns.Style.
-- ---------------------------------------------------------------------------

--- The same four strips with thickness as an ANCHOR OFFSET: three anchors each and no
--- SetWidth/SetHeight. Pixel-identical to buildRing at rest, corner insets included.
local function buildRingRelative(host, t)
  local parts = {}
  local function strip(points)
    local x = host:CreateTexture(nil, "OVERLAY")
    x:SetColorTexture(1, 1, 1, 1)
    for _, p in ipairs(points) do x:SetPoint(p[1], host, p[2], p[3], p[4]) end
    x:Hide()
    parts[#parts + 1] = x
  end
  strip{ { "TOPLEFT", "TOPLEFT", 0, 0 }, { "TOPRIGHT", "TOPRIGHT", 0, 0 },
         { "BOTTOMLEFT", "TOPLEFT", 0, -t } }
  strip{ { "BOTTOMLEFT", "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 },
         { "TOPLEFT", "BOTTOMLEFT", 0, t } }
  strip{ { "TOPLEFT", "TOPLEFT", 0, -t }, { "BOTTOMLEFT", "BOTTOMLEFT", 0, t },
         { "TOPRIGHT", "TOPLEFT", t, -t } }
  strip{ { "TOPRIGHT", "TOPRIGHT", 0, -t }, { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, t },
         { "TOPLEFT", "TOPRIGHT", -t, -t } }
  return parts
end

--- One ring in one colour on its own frame, left alone: no switching, no arrival.
--- `o` is { rgb, thickness_px, relative, alpha }.
function Paint.Ring(host, o)
  local edge = CreateFrame("Frame", nil, host)
  edge:SetPoint("CENTER", host, "CENTER", 0, 0)
  fit(edge, host)
  local build = o.relative and buildRingRelative or buildRing
  local parts = build(edge, o.thickness_px)
  for _, t in ipairs(parts) do
    t:SetVertexColor(o.rgb[1], o.rgb[2], o.rgb[3])
    -- `add` makes the lab's ring the same additive line the declared scan edge is, so a
    -- hairline experiment is comparing area against the real treatment and not against a wash.
    if o.add then t:SetBlendMode("ADD") end
    t:Show()
  end
  edge:SetAlpha(o.alpha or 1)
  return { frame = edge, parts = parts }
end

--- Alpha up and straight back down, with no geometry moving at all.
--- ⚠ The frame RESTS at 0 and both exit paths land there — rest it visible and every row wears a
--- permanent second border.
function Paint.Flash(frame, duration)
  frame:SetAlpha(0)
  local group = frame:CreateAnimationGroup()
  local up = group:CreateAnimation("Alpha")
  up:SetFromAlpha(0)
  up:SetToAlpha(1)
  up:SetDuration(duration / 2)
  up:SetSmoothing("OUT")
  local down = group:CreateAnimation("Alpha")
  down:SetFromAlpha(1)
  down:SetToAlpha(0)
  down:SetStartDelay(duration / 2)
  down:SetDuration(duration / 2)
  down:SetSmoothing("IN")
  group:SetToFinalAlpha(true)
  return group
end

--- The outward ping: its own frame, its own ring, and the only thing that scales.
--- ⚠ It must land INVISIBLE — scale restoration on Stop() is unmeasured, so it hides itself.
function Paint.Ghost(host, o)
  local ghost = Paint.Ring(host, o)
  local f = ghost.frame
  f:SetAlpha(0)
  f:Hide()

  local group = f:CreateAnimationGroup()
  local grow = group:CreateAnimation("Scale")
  grow:SetScaleFrom(o.from_scale, o.from_scale)
  grow:SetScaleTo(o.to_scale, o.to_scale)
  grow:SetOrigin("CENTER", 0, 0)
  grow:SetDuration(o.duration_s)
  grow:SetSmoothing(o.smoothing)
  local fade = group:CreateAnimation("Alpha")
  fade:SetFromAlpha(o.from_alpha)
  fade:SetToAlpha(o.to_alpha)
  fade:SetDuration(o.duration_s)
  fade:SetSmoothing(o.smoothing)
  group:SetToFinalAlpha(true)
  group:SetScript("OnFinished", function() f:Hide() end)

  function ghost:Play()
    group:Stop()
    f:Hide()
    f:SetAlpha(o.from_alpha)
    f:Show()
    group:Play()
  end

  function ghost:Stop()
    group:Stop()
    f:Hide()
  end

  return ghost
end

--- A soft additive halo reaching `glow_px` OUTSIDE the host's rect. `o` is
--- { rgb, glow_px, rest_alpha, flare_alpha, flare_mult, decay_s, period_s }, and which of those an
--- entry declares picks the behaviour: static, a continuous breathe between a floor and a peak, or
--- a one-shot flare that decays back to the floor. The floor is the point — a treatment that is
--- never absent, only varying, is what separates these from a blink.
function Paint.Halo(host, o)
  local w, h = extent(host)
  local reach = o.glow_px or 0

  local layer = CreateFrame("Frame", nil, host)
  layer:SetPoint("CENTER", host, "CENTER", 0, 0)
  layer:SetSize(w + 2 * reach, h + 2 * reach)
  layer:SetFrameLevel(math.max(host:GetFrameLevel() - 1, 0))

  local t = layer:CreateTexture(nil, "BACKGROUND")
  setArt(t, ns.Style.badges.halo_texture)
  t:SetAllPoints(layer)
  t:SetBlendMode("ADD")
  t:SetVertexColor(o.rgb[1], o.rgb[2], o.rgb[3])

  local rest = o.rest_alpha or 1
  layer:SetAlpha(rest)

  local halo = { frame = layer, texture = t }
  local group

  if o.period_s then
    group = layer:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local breathe = group:CreateAnimation("Alpha")
    breathe:SetFromAlpha(rest)
    breathe:SetToAlpha(o.flare_alpha or 1)
    breathe:SetDuration(o.period_s / 2)
    breathe:SetSmoothing("IN_OUT")
  elseif o.decay_s then
    group = layer:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(o.flare_alpha or 1)
    fade:SetToAlpha(rest)
    fade:SetDuration(o.decay_s)
    fade:SetSmoothing("OUT")
    if o.flare_mult then
      local shrink = group:CreateAnimation("Scale")
      shrink:SetScaleFrom(o.flare_mult, o.flare_mult)
      shrink:SetScaleTo(1, 1)
      shrink:SetOrigin("CENTER", 0, 0)
      shrink:SetDuration(o.decay_s)
      shrink:SetSmoothing("OUT")
    end
    -- ⚠ Fire-and-forget onto the FLOOR, never onto nothing: alpha is restored only under
    -- SetToFinalAlpha, and this treatment's whole claim is that the resting row stays lit.
    group:SetToFinalAlpha(true)
  end

  function halo:Play()
    if not group then return end
    group:Stop()
    layer:SetAlpha(rest)
    group:Play()
  end

  function halo:Stop()
    if group then group:Stop() end
    layer:SetAlpha(rest)
  end

  return halo
end

--- The sheet tiled across an icon-sized host: white art, so colour is the vertex colour. Its own
--- frame two levels up, so it lies over the icon and the border and under the corner badges.
--- `spec` is { texture, rgb, alpha, phase_pct, tile_px, pitch_px }.
--@unverified tiling here is REPEAT wrap plus tex-coords past 1. The KB has the wrap-mode
--@unverified vocabulary and no measurement of the pair (frames-textures-animation.md §5.2).
function Paint.Stripes(host, spec)
  local layer = CreateFrame("Frame", nil, host)
  layer:SetAllPoints(host)
  layer:SetFrameLevel(host:GetFrameLevel() + 2)

  local t = layer:CreateTexture(nil, "OVERLAY")
  t:SetTexture(spec.texture, "REPEAT", "REPEAT", "LINEAR")
  t:SetAllPoints(layer)
  t:SetVertexColor(spec.rgb[1], spec.rgb[2], spec.rgb[3])
  t:SetAlpha(spec.alpha or 1)

  local w, h = extent(host)
  t:SetTexCoord(Paint.StripeTexCoord(w, h, spec.tile_px, spec.pitch_px, spec.phase_pct))
  return { frame = layer, texture = t }
end

--- V15 · the row's name. An outlined FontString in the corner the cue vocabulary does not use.
---
--- CHROME, not a cue (`spec.md` §3.8): it says which key casts this icon and nothing about
--- whether to press it, so it is built here beside the primitives but joins no stack and takes
--- no part in the read. It never moves, blinks or tints — `ns.Style.text`'s flicker limits bind
--- text that changes, and this does not.
function Paint.Hotkey(host)
  local T = ns.Style.hotkey
  -- ⚠ ITS OWN FRAME, ABOVE EVERYTHING cap draws. A FontString created on `host` sits at the
  -- host's own frame level, and every other primitive here is a CHILD frame — the badges at the
  -- host's level, the hatch at +2 — so a bare FontString would be drawn UNDER a badge that
  -- overlapped it. Draw order across frames is decided by frame level, not by draw layer, so
  -- "OVERLAY" alone buys nothing. The label must win every one of those: it is the row's name,
  -- and a name half-covered by a disc is worse than no name.
  local layer = CreateFrame("Frame", nil, host)
  layer:SetAllPoints(host)
  layer:SetFrameLevel(host:GetFrameLevel() + 5)
  local fs = layer:CreateFontString(nil, "OVERLAY")
  -- ⚠ `SetFont`'s returned bool is its only failure signal, and a refusal leaves the string on
  -- no font at all rather than on a smaller one — a bare FontString has none to fall back to.
  -- So the shelf's path is tried first and the template's own second, and the caller gets a
  -- string that is either dressed or plainly invisible, never silently mis-sized.
  --
  -- `T.font` is a FULL path, not a filename: V15's face is cap's own shipped file under
  -- `Media/fonts/`, not one of the client's. That is also the failure this guard now covers —
  -- a missing `Media/` file, rather than a typo'd `Fonts\` name.
  if not fs:SetFont(T.font, T.size, T.outline) then
    local path = fs:GetFont()
    if path then fs:SetFont(path, T.size, T.outline) end
  end
  fs:SetTextColor(T.rgb[1], T.rgb[2], T.rgb[3])
  fs:SetAlpha(T.alpha)
  fs:SetJustifyH("LEFT")
  fs:SetPoint(T.anchor, layer, T.anchor, T.offset.x, T.offset.y)
  fs:Hide()
  return fs
end

--- Write a chrome label, or take it away.
---
--- BLANK IS A STATE IT DRAWS, not a failure to draw one: an ability you have not bound has no
--- key, and a placeholder would be a keybind cap invented. `SetText` on cap's own FontString is
--- a legal in-combat write (render-shelf.md Part 3), which is what lets a bar-page flip mid-pull
--- reach the row instead of waiting for the pull to end.
function Paint.Label(fs, text)
  if type(text) == "string" and text ~= "" then
    fs:SetText(text)
    fs:Show()
  else
    fs:SetText("")
    fs:Hide()
  end
end
