-- Paint.lua — the render shelf's primitives, built once. Every number comes from ns.Style.
--
-- Both the live overlay and the /cap style gallery draw through these builders, so the two
-- cannot show different pixels — that divergence is what render-shelf.md exists to end.
local ADDON, ns = ...

local issecretvalue = issecretvalue

local Paint = {}
ns.Paint = Paint

-- ONE ticker in the addon walks every visible frame-stepper — badge sprites and the lane border's
-- arrival alike (cdm-rider-patterns.md §14). Its period is ns.Style.motion.tick_s.
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

--- The band a ring flipbook actually draws at. The sheet is minified onto the row, and the band
--- with it — there is no nine-slice, because slice margins apply to a whole texture and the frames
--- are picked with SetTexCoord.
function Paint.RingBand(thickness_px, tile_px, drawn_px)
  if not tile_px or tile_px <= 0 then return thickness_px end
  return thickness_px * drawn_px / tile_px
end

--- Which arrival frame is showing, 1-based, CLAMPED: the walk is one shot and rests on the last
--- frame. `nil` once it has rested, so a stepper knows when to deregister.
function Paint.ArrivalFrame(count, elapsed, stepSeconds)
  if count < 2 or stepSeconds <= 0 then return count end
  local i = math.floor(elapsed / stepSeconds) + 1
  if i >= count then return count end
  return i
end

--- A frame's cell in a grid sheet, as SetTexCoord's left, right, bottom, top. Frames fill the grid
--- row-major, which is the order capart.ring_flipbook pastes them in.
function Paint.FrameCoords(index, grid)
  local i = math.max(index - 1, 0)
  local col, row = i % grid, math.floor(i / grid)
  local s = 1 / grid
  return col * s, (col + 1) * s, row * s, (row + 1) * s
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
-- V2 · lane border, with the one-shot arrival snap
-- ---------------------------------------------------------------------------

--- The one ring sheet every lane draws. Lanes differ by hue; the band is the shelf's, once.
function Paint.RingTexture()
  local r = ns.Style.ring
  return r.texture_root .. r.texture .. ".tga"
end

--- Fire-and-forget, so it must land on its final values: animations restore alpha only under
--- SetToFinalAlpha, and never restore vertex color at all. The declared border does not use this —
--- its arrival is a frame walk — but Part 7's arrival variants are ABOUT a Scale animation, and `a`
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

--- Arrival is a CHANGE of drawn lane — absent → present, or one lane → another. The live path
--- repaints at 10 Hz, so repainting the same lane is emphatically NOT arrival; nor is the first
--- draw after cap resumed drawing, which `silent` marks (roster churn is not arrival). Rate
--- limited per row to the snap's own duration, so a lane that flickers cannot stack snaps.
--- Pure, so the rule is desk-testable while the frame work around it is not.
function Paint.ShouldSnap(border, name, now)
  if border.silent or not name then return false end
  if border.lane == name then return false end
  local last = border.snappedAt
  if last and now - last < ns.Style.arrival.duration_s then return false end
  return true
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

--- One border per host, carrying a pre-built ring texture for every lane — one texture object per
--- lane, so switching lane is Show/Hide plus SetVertexColor and never SetTexture, which is all cap
--- is allowed to write in combat. Every lane draws the same sheet; only the hue differs.
--- The arrival is a one-shot walk over the sheet's frames on the shared ticker. Nothing scales, so
--- the border cannot draw outside its own rect and cannot reach a neighbouring row.
--@unverified whether the frame walk reads as motion rather than as steps at the shelf's tick, and
--@unverified whether a band authored in one cell survives minification onto a row-sized rect.
--@unverified render-shelf.md Part 5 question 8 — this flight's acceptance set.
function Paint.Border(host, lane)
  local edge = CreateFrame("Frame", nil, host)
  edge:SetPoint("CENTER", host, "CENTER", 0, 0)
  fit(edge, host)
  edge:Hide()

  local frames, grid = ns.Style.ring.frames, ns.Style.ring.grid
  local rings = {}
  for name in pairs(ns.Style.lanes) do
    local t = edge:CreateTexture(nil, "OVERLAY")
    t:SetTexture(Paint.RingTexture(), nil, nil, "TRILINEAR")
    t:SetAllPoints(edge)
    t:SetTexCoord(Paint.FrameCoords(frames, grid))
    t:Hide()
    rings[name] = t
  end

  local border = { frame = edge, rings = rings }

  --- Walked by the shared ticker until it lands on the resting frame, then deregistered.
  function border:Step(now)
    local i = Paint.ArrivalFrame(frames, now - (self.snappedAt or now), ns.Style.motion.tick_s)
    if i ~= self.shownFrame then
      local t = rings[self.lane]
      if t then t:SetTexCoord(Paint.FrameCoords(i, grid)) end
      self.shownFrame = i
    end
    if i >= frames then stepEvery(self, false) end
  end

  function border:SetLane(name)
    local spec = ns.Style.lanes[name]
    if not spec then return self:Hide() end
    local now = GetTime()
    local arrived = Paint.ShouldSnap(self, name, now)
    fit(edge, host)
    for ring, t in pairs(rings) do
      if ring == name then
        t:SetVertexColor(spec.rgb[1], spec.rgb[2], spec.rgb[3])
        t:SetAlpha(1)
        t:Show()
      else
        t:Hide()
      end
    end
    self.lane = name
    edge:Show()
    if arrived then
      self.snappedAt = now
      self:Snap()
    end
  end

  --- A hidden row's border is ABSENT, so its next lane is an arrival. That is what makes a row
  --- the CDM stopped showing — or one cap stopped drawing — snap when it comes back.
  function border:Hide()
    self.lane = nil
    edge:Hide()
    stepEvery(self, false)
  end

  --- The arrival: the frame walk starts here and stops itself on the resting frame.
  function border:Snap()
    if not edge:IsShown() then return end
    self.snappedAt = GetTime()
    self.shownFrame = nil
    self:Step(self.snappedAt)
    stepEvery(self, true)
  end

  -- The constructor's own first paint is not an arrival: nothing became available, the frame
  -- was just built.
  border.silent = true
  if lane then border:SetLane(lane) end
  border.silent = false
  return border
end

-- ---------------------------------------------------------------------------
-- V11 · the cooldown hatch
-- ---------------------------------------------------------------------------

--- Diagonal stripes across the icon face, drawn while the Cooldown Manager says the ability is
--- down. One tiling white-alpha sheet tinted by SetVertexColor, exactly as the lane border is.
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
function Paint.Hatch(host, inset)
  local h = ns.Style.hatch
  if not h then return nil end
  inset = inset or 0

  local t = host:CreateTexture(nil, "ARTWORK")
  t:SetTexture(ns.Style.hatch.texture_root .. h.texture .. ".tga", "REPEAT", "REPEAT",
    "TRILINEAR")
  t:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -inset)
  t:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -inset, inset)
  t:SetVertexColor(h.rgb[1], h.rgb[2], h.rgb[3])
  t:SetAlpha(h.alpha)
  t:Hide()

  local hatch = { texture = t }

  --- Sized from the drawn extent so the stripe pitch is the same on any icon size the client
  --- hands us, rather than stretching with the button.
  function hatch:SetShown(on)
    if not on then return t:Hide() end
    local w, hgt = extent(host)
    w, hgt = w - 2 * inset, hgt - 2 * inset
    if w ~= self.w or hgt ~= self.h then
      t:SetTexCoord(Paint.StripeTexCoord(w, hgt, h.tile_px, h.pitch_px, h.phase_pct))
      self.w, self.h = w, hgt
    end
    t:Show()
  end

  function hatch:Hide() t:Hide() end

  return hatch
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
  slot:SetPoint("TOPRIGHT", host, "TOPRIGHT", Paint.SlotOffset(cue.slot))
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

--- Four colour strips forming a ring. The declared border is one texture; this construction is
--- the subject of the arrival variants, which ask how the client scales it.
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

--- One ring in one colour on its own frame, left alone: no lane switching, no arrival.
--- `o` is { rgb, thickness_px, relative, alpha }.
function Paint.Ring(host, o)
  local edge = CreateFrame("Frame", nil, host)
  edge:SetPoint("CENTER", host, "CENTER", 0, 0)
  fit(edge, host)
  local build = o.relative and buildRingRelative or buildRing
  local parts = build(edge, o.thickness_px)
  for _, t in ipairs(parts) do
    t:SetVertexColor(o.rgb[1], o.rgb[2], o.rgb[3])
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
