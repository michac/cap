-- Paint.lua — the render shelf's primitives, built once. Every number comes from ns.Style.
--
-- Both the live overlay and the /cap style gallery draw through these builders, so the two
-- cannot show different pixels — that divergence is what render-shelf.md exists to end.
local ADDON, ns = ...

local issecretvalue = issecretvalue

local Paint = {}
ns.Paint = Paint

-- There is deliberately NO ticker here. Every motion — badge strips, the promotion ring, the
-- pandemic flame, every pulse — is an AnimationGroup the client steps, so no Lua runs per tick
-- and a group armed before a handover keeps rendering where a ticker's writes are sealed
-- (security-taint-and-restricted-data.md §3.5.3).

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

--- The drawn extent of a host, guarded against a secret or unset width. See `extent` below.
function Paint.Extent(host)
  local w, h = host:GetWidth(), host:GetHeight()
  if type(w) ~= "number" or type(h) ~= "number" or issecretvalue(w) or issecretvalue(h)
    or w <= 0 or h <= 0 then
    return ns.Style.surfaces.icon_px, ns.Style.surfaces.icon_px
  end
  return w, h
end

--- The offset from a host's TOPRIGHT to the CENTRE of the first badge in the stack. `StackOffset`
--- gives a badge frame's own TOPRIGHT; a FontString centres on a point, so it needs the middle.
function Paint.BadgeCentre(index)
  local x, y = Paint.StackOffset(index or 0)
  local d = Paint.Geometry().diameter
  return x - d / 2, y - d / 2
end

--- Tiles a `tile_px` sheet across `w`x`h` at its authored size rather than stretching one copy,
--- offset along u by `phase_pct` of a stripe period. Returns SetTexCoord's left, right, bottom, top.
function Paint.StripeTexCoord(w, h, tile_px, pitch_px, phase_pct)
  if not tile_px or tile_px <= 0 then return 0, 1, 0, 1 end
  local u = (phase_pct or 0) / 100 * (pitch_px or tile_px) / tile_px
  return u, u + w / tile_px, 0, h / tile_px
end

-- ---------------------------------------------------------------------------
-- V2 · the scan edge
-- ---------------------------------------------------------------------------

--- A host's drawn size, falling back to the nominal icon: a CDM item's width can read secret.
---
--- ⚠ PUBLIC as `Paint.Extent` since 2026-08-22, because the sealed band needs it too: an inline
--- texture escape is sized in the string by a literal, so a band's hatch has to be told the
--- button's REAL width or it draws at the shelf's nominal 56 on whatever the player configured.
--- Measured in flight: a 56px escape on a 42px icon is where the overhang came from.
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
--- ⚠ The blend mode is a TOKEN (`tokens.ready.blend`), not a constant, and it reads `BLEND`.
--- It was `ADD` until 2026-08-23, when the edge was observed drawing WHITE on Demonology's
--- purple roster: additive is destination + source, so this hue saturates red on every pixel and
--- green and blue on any icon that is not near-black. The declared colour could not reach a pixel
--- under it. SetBlendMode's five values are Tier-1 — frames-textures-animation.md §5.2.
function Paint.Border(host)
  local edge = CreateFrame("Frame", nil, host)
  edge:SetPoint("CENTER", host, "CENTER", 0, 0)
  fit(edge, host)
  edge:Hide()

  local ready = ns.Style.ready
  local parts = buildRing(edge, ready.line_px)
  for _, t in ipairs(parts) do
    t:SetColorTexture(ready.rgb[1], ready.rgb[2], ready.rgb[3], ready.alpha)
    t:SetBlendMode(ready.blend or "BLEND")
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


--- A sprite-sheet flipbook as a FlipBook AnimationGroup: the client steps the frames, no Lua
--- runs per tick, and — decisive for V19 — a group playing before a handover keeps rendering
--- where a ticker's writes are sealed (security-taint-and-restricted-data.md §3.5.3). `spec`
--- carries cols/rows/frames and either `fps` or `duration_s`. Looping defaults to REPEAT.
---
--- --@unverified: the setter names are the generated docs'; that rows × cols grid the whole
--- texture and `frames` caps the walk is a source read of the XSD, never watched in the client
--- (frames-textures-animation.md §7.1). Every consumer is in the next flight's acceptance set.
---
--- ⚠ Fits only an unpadded sheet — every cell a frame, no power-of-two slack. The lab's padded
--- sheets must keep StylePanel's `drawFlipbook`.
function Paint.FlipBook(texture, spec, looping)
  local group = texture:CreateAnimationGroup()
  group:SetLooping(looping or "REPEAT")
  local book = group:CreateAnimation("FlipBook")
  book:SetFlipBookColumns(spec.cols)
  book:SetFlipBookRows(spec.rows)
  book:SetFlipBookFrames(spec.frames)
  book:SetDuration(spec.duration_s or (spec.frames / spec.fps))
  return group
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
--- ⚠ `procring` is exactly cols x rows cells with no power-of-two padding (8x64 = 512,
--- 4x64 = 256), which is what lets `Paint.FlipBook` drive it and the `1 / cols` first-frame
--- texcoord below address it.
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

  -- Frame 0 by hand, so the instant between Show() and the group's first step never flashes
  -- the whole sheet. While the group plays, the FlipBook owns the texcoords.
  t:SetTexCoord(0, 1 / p.cols, 0, 1 / p.rows)
  local anim = Paint.FlipBook(t, p)
  layer:Hide()

  local ring = { frame = layer, texture = t }
  function ring:SetShown(on)
    if not on then
      anim:Stop()
      return layer:Hide()
    end
    if layer:IsShown() then return end
    anim:Play()
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

  -- A multi-frame cue draws its baked strip (capart bakes `strip_<cue>` beside the single
  -- frames) and the client's FlipBook walks it; a single frame is a still and needs neither.
  local count = #cue.frames
  local anim
  if count > 1 then
    sprite:SetTexture(texturePath("strip_" .. key), nil, nil, "TRILINEAR")
    sprite:SetTexCoord(0, 1 / count, 0, 1)
    anim = Paint.FlipBook(sprite, { cols = count, rows = 1, frames = count,
                                    duration_s = cue.duration_s },
                          cue.loop == "BOUNCE" and "BOUNCE" or "REPEAT")
  else
    setArt(sprite, cue.frames[1])
  end

  local badge = { frame = slot, cue = key, sprite = sprite, plate = plate, halo = halo }

  --- Pooled frames outlive their colour: an animation that stopped restores alpha and never
  --- vertex colour, so both are written again on every show.
  ---
  --- ⚠ IDEMPOTENT. The live path repaints at 10 Hz, so an unguarded Play() here would restart
  --- the strip faster than one frame lasts and freeze the glyph on frame 1.
  function badge:Show()
    sprite:SetVertexColor(tint[1], tint[2], tint[3])
    sprite:SetAlpha(1)
    slot:Show()
    if halo then halo:Play() end
    if anim and not anim:IsPlaying() then anim:Play() end
  end

  --- Move the badge to its place in the flowing stack. There are no fixed slots — a cue's
  --- position is a function of how many lower-ranked cues are showing beside it — so Overlay
  --- calls this on every update rather than once at creation.
  ---
  --- ⚠ IT MUST EXIST. `Paint.Badge` returns a plain TABLE, not a frame, so a method Overlay
  --- calls and Paint does not define is a nil call that takes the whole `paint()` down — every
  --- badge, edge, hatch and hotkey on every row, not just this one. That is exactly what shipped
  --- in v0.12.0: the call arrived 2026-08-19 with the flowing stack and stayed invisible because
  --- the only catalog anyone ran declared no cues, so the loop never reached this branch.
  ---
  --- ⚠ `ClearAllPoints` first. `SetPoint` ADDS an anchor rather than replacing one, so a frame
  --- re-anchored without clearing keeps both and is stretched between them.
  function badge:SetPoint(point, relativeTo, relativePoint, x, y)
    slot:ClearAllPoints()
    slot:SetPoint(point, relativeTo, relativePoint, x, y)
  end

  function badge:Hide()
    slot:Hide()
    if halo then halo:Stop() end
    if anim then anim:Stop() end
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
-- V15 · the row's chrome. Built here beside the primitives, and LIVE: Overlay.lua builds a
-- hotkey label on every bound row and writes it through Paint.Label.
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- Part 7 · the sealed-display primitives. A secret aura APPLICATION COUNT, or a DoT's remaining
-- duration, reaching a pixel. Every number is an argument, so a winner is promoted by aiming the
-- builder at ns.Style.
--
-- ⚠ NOTHING HERE READS A SEALED VALUE, and nothing here is a sink. In the client cap hands the
-- platform a FontString (SetApplicationCount), a StatusBar (SetApplicationBar) or a Region
-- (AddPandemicRegion) and the client alone drives it. These builders make the WIDGET; the
-- gallery drives it by hand from a cell's stated value so a treatment can be looked at.
-- ---------------------------------------------------------------------------

--- Which band a value falls in: the highest threshold the value reaches. Pure, and the same
--- arithmetic `ApplyApplicationCount` does, which is what makes a gallery cell an argument about
--- the client rather than about this file.
---
--- ⚠ `threshold` is the MINIMUM input the rule applies to, so a value exactly ON a threshold
--- takes the UPPER band. An off-by-one here is invisible until it is wrong in a pull.
function Paint.BandFor(bands, value)
  local hit
  for _, b in ipairs(bands or {}) do
    if value >= b.threshold and (not hit or b.threshold >= hit.threshold) then hit = b end
  end
  return hit
end

--- The string a band draws at `value`, with `%d` resolved. Texture escapes are left ALONE: the
--- client renders `|T…|t` and `|A:…|a` inline `[client 2026-08-21]`, so passing the format
--- through untouched is what makes the gallery show what the client shows.
function Paint.BandText(bands, value)
  local b = Paint.BandFor(bands, value)
  if not b then return "" end
  local fmt = b.format or ""
  if fmt == "" then return "" end
  return (fmt:gsub("%%d", tostring(value)))
end

--- A looping alpha (and optionally scale) breath. `o` is { duration_s, alpha = {a0, a1}, scale }.
---
--- ⚠ ONE motion per region. Bands choose WHAT is drawn, never HOW it moves, and two loops at
--- different rates on one row read as malfunction — so a caller attaches this to the frame the
--- band gates and never to each part inside it.
function Paint.Breathe(frame, o)
  local half = (o.duration_s or 1) / 2
  local a0, a1 = o.alpha and o.alpha[1] or 0.7, o.alpha and o.alpha[2] or 1
  local group = frame:CreateAnimationGroup()
  group:SetLooping("REPEAT")

  local up = group:CreateAnimation("Alpha")
  up:SetFromAlpha(a0); up:SetToAlpha(a1); up:SetDuration(half); up:SetOrder(1)
  local down = group:CreateAnimation("Alpha")
  down:SetFromAlpha(a1); down:SetToAlpha(a0); down:SetDuration(half); down:SetOrder(2)

  if o.scale and o.scale ~= 1 then
    local grow = group:CreateAnimation("Scale")
    grow:SetScaleFrom(1, 1); grow:SetScaleTo(o.scale, o.scale)
    grow:SetDuration(half); grow:SetOrder(1)
    local shrink = group:CreateAnimation("Scale")
    shrink:SetScaleFrom(o.scale, o.scale); shrink:SetScaleTo(1, 1)
    shrink:SetDuration(half); shrink:SetOrder(2)
  end
  return group
end

--- The badge stack's own plate, alone, on its own frame at the stack's corner. `index` is the
--- slot, 0-based.
---
--- ⚠ A plate cap draws has NO SINK ON IT. That is the whole finding L5 was built to show: the
--- count sink seals `Text` and `Shown` on the FontString and nothing else, so a plate behind a
--- banded numeral draws at every value including the ones the band blanks. The way to make a
--- plate ride the band is to bake it into the art the escape names, not to draw one here.
function Paint.CountPlate(host, index)
  local b, g = ns.Style.badges, Paint.Geometry()
  local slot = CreateFrame("Frame", nil, host)
  slot:SetSize(g.diameter, g.diameter)
  slot:SetPoint("TOPRIGHT", host, "TOPRIGHT", Paint.StackOffset(index or 0))
  slot:SetFrameLevel(host:GetFrameLevel() + 4)

  local plate = slot:CreateTexture(nil, "OVERLAY", nil, 6)
  plate:SetTexture(b.texture_root .. b.plate.texture .. ".tga", nil, nil, "TRILINEAR")
  plate:SetVertexColor(b.plate.rgb[1], b.plate.rgb[2], b.plate.rgb[3])
  plate:SetAlpha(b.plate.alpha)
  plate:SetSize(g.plate, g.plate)
  plate:SetPoint("CENTER")
  return slot
end

--- The FontString the count sink would be handed, on its own frame so it wins draw order the
--- way `Paint.Hotkey`'s does. `o` is
--- { font, size, outline, rgb, place = "centre"|"badge", y_px }.
---
--- Returns { frame, fs, SetBand(text) }. `SetBand("")` leaves an EMPTY string rather than
--- hiding the frame: a band that draws nothing is a state the treatment has, and the corner it
--- leaves behind is the thing being judged.
function Paint.CountString(host, o)
  local layer = CreateFrame("Frame", nil, host)
  layer:SetFrameLevel(host:GetFrameLevel() + 5)

  local fs = layer:CreateFontString(nil, "OVERLAY")
  -- ⚠ `SetFont` signals failure only through its returned bool, and a refusal leaves the string
  -- on no font at all rather than on a smaller one. The shelf's path is tried first and the
  -- template's own second.
  local path = "Fonts\\" .. (o.font or ns.Style.surfaces.count_tile.font)
  if not fs:SetFont(path, o.size or ns.Style.surfaces.count_tile.size,
                    o.outline or ns.Style.surfaces.count_tile.outline) then
    fs:SetFontObject("NumberFontNormal")
  end
  if o.rgb then fs:SetTextColor(o.rgb[1], o.rgb[2], o.rgb[3]) end

  if o.place == "badge" then
    local g = Paint.Geometry()
    layer:SetSize(g.diameter, g.diameter)
    layer:SetPoint("TOPRIGHT", host, "TOPRIGHT", Paint.StackOffset(o.index or 0))
    fs:SetPoint("CENTER", layer, "CENTER", 0, 0)
  else
    layer:SetAllPoints(host)
    fs:SetPoint("TOP", layer, "TOP", 0, -(o.y_px or 1))
  end

  local band = { frame = layer, fs = fs }
  function band:SetBand(text) fs:SetText(text or "") end
  return band
end

--- A StatusBar the application-bar sink would be handed. `o` is
--- { rgb, track_rgb, track_alpha, mode = "bar"|"radial", w, h, inset_px }.
---
--- ⚠ A BAR HAS NO BLANK STATE. `SetValue` clamps into [0, max], so at zero the track still
--- draws — there is no band, no complement, no "nothing until N". That is the straight trade
--- against the formatter, which can be silent and cannot be a shape.
---
--- ⚠ Radial is a RENDER MODE, not a masked fill: at 12.1 `SetRenderMode` drives the managed
--- texture's radial progress percent instead of moving anchors, so the circle needs no
--- MaskTexture. A client without it falls back to the linear fill rather than drawing nothing.
function Paint.CountBar(host, o)
  local bar = CreateFrame("StatusBar", nil, host)
  bar:SetSize(o.w, o.h)
  bar:SetFrameLevel(host:GetFrameLevel() + 4)

  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints(bar)
  local tr = o.track_rgb or { 0, 0, 0 }
  track:SetColorTexture(tr[1], tr[2], tr[3], o.track_alpha or 0.55)

  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetColorTexture(o.rgb[1], o.rgb[2], o.rgb[3], 1)
  bar:SetStatusBarTexture(fill)

  if o.mode == "radial" and bar.SetRenderMode and Enum and Enum.StatusBarRenderMode then
    pcall(bar.SetRenderMode, bar, Enum.StatusBarRenderMode.Radial)
  elseif o.mode == "up" then
    bar:SetOrientation("VERTICAL")
  end
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  return bar
end

--- Whether a resolved band string carries a mark big enough to be about the WHOLE ICON rather
--- than about a corner — L6's hatch is a 56x56 escape in the same FontString as its badge.
---
--- This decides where the string is anchored, and it matters because there is exactly ONE count
--- FontString per button: a band that hatches the icon and hangs a badge on the corner does both
--- from one string, and the badge gets there through the escape's own `:xoff:yoff` rather than
--- through a second anchor. Anchoring such a string in the corner would hang its hatch off the
--- side of the button.
function Paint.BandIsFullIcon(text, icon_px)
  if type(text) ~= "string" then return false end
  local limit = (icon_px or ns.Style.surfaces.icon_px) * 0.75
  for h in text:gmatch("|[AT]:?[^|:]+:(%d+):%d+") do
    if tonumber(h) >= limit then return true end
  end
  return false
end
