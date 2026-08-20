-- StylePanel.lua — `/cap style`: every render-shelf primitive drawn once, side by side,
-- in its own scrolling window with a tab per section.
--
-- The Lua twin of the artifact's swatch section. Nothing here touches a Cooldown Manager
-- frame; every texture is cap's own, so the gallery has no platform exposure at all.
local ADDON, ns = ...

ns.StylePanel = ns.StylePanel or {}
local SP = ns.StylePanel

local PAD, LABEL_H, CAPTION_H, SPREAD = 8, 13, 11, 18

-- Sample art: Havoc roster abilities the artifact also draws, so the gallery and
-- havoc-stepper.html show the same icons under the same treatments.
local SAMPLE = {
  { spell = 191427, name = "Metamorphosis" },
  { spell = 188499, name = "Blade Dance" },
  { spell = 344865, name = "Fel Rush" },
  { spell = 258920, name = "Immolation Aura" },
}

-- The pane being filled and its top-down cursor: a pane is built by pointing these at it.
local container, y

local function icon()
  return ns.Style.surfaces.icon_px
end

local function text(parent, font, x, top, value, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -top)
  fs:SetWidth(width or 200)
  fs:SetJustifyH("LEFT")
  fs:SetText(value)
  return fs
end

local function section(title)
  text(container, "GameFontNormalSmall", PAD, y, title, 320)
  y = y + LABEL_H
end

local function note(body)
  local fs = text(container, "GameFontDisableSmall", PAD, y, body, 320)
  fs:SetJustifyV("TOP")
  y = y + math.max(CAPTION_H, fs:GetStringHeight() + 2)
end

--- One swatch: cap's own frame at the shelf's nominal icon size, wearing sample art.
local function swatch(x, top, spell, caption)
  local host = CreateFrame("Frame", nil, container)
  host:SetSize(icon(), icon())
  host:SetPoint("TOPLEFT", container, "TOPLEFT", x, -top)

  local art = host:CreateTexture(nil, "ARTWORK")
  art:SetAllPoints(host)
  local file = spell and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell)
  if file then
    art:SetTexture(file)
  else
    art:SetColorTexture(0.16, 0.16, 0.18, 1)
  end

  if caption then
    local fs = host:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOP", host, "BOTTOM", 0, -2)
    fs:SetText(caption)
  end
  return host
end

local function swipe(host)
  local ok, cd = pcall(CreateFrame, "Cooldown", nil, host, "CooldownFrameTemplate")
  if not ok or not cd then return end
  cd:SetAllPoints(host)
  if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
  cd:SetCooldown(GetTime() - 1200, 3600)
end

--- ⚠ Rate limited to the animation's own duration, as Paint.ShouldSnap limits the live path:
--- Stop() does not restore scale, so an unlimited click can park a frame part-scaled.
local function replayOnClick(hosts, plays, duration)
  local last
  local function fire()
    local now = GetTime()
    if not ns.Paint.ShouldReplay(last, now, duration) then return end
    last = now
    for _, play in ipairs(plays) do play() end
  end
  for _, host in ipairs(hosts) do
    host:EnableMouse(true)
    host:SetScript("OnMouseUp", fire)
  end
end

-- ---------------------------------------------------------------------------
-- The gallery
-- ---------------------------------------------------------------------------

local function buildScan()
  section("V2 · the scan edge  ·  V7 · swipe")
  local x = PAD

  local inScan = swatch(x, y, SAMPLE[1].spell, "in the scan")
  ns.Paint.Border(inScan):SetShown(true)
  x = x + icon() + SPREAD

  swatch(x, y, SAMPLE[2].spell, "not in the scan")
  x = x + icon() + SPREAD

  swipe(swatch(x, y, SAMPLE[3].spell, "swipe"))

  y = y + icon() + CAPTION_H + 6
  local r = ns.Style.ready
  note(("One binary treatment: a %dpx additive edge ON the icon rect, or nothing. There is no " ..
        "hue ladder and no motion — priority is row order plus the overlays."):format(r.line_px))
end

--- Cue keys in slot order, so the gallery is laid out the same way on every login.
-- V11 · the cooldown hatch, drawn beside a bare swipe and a swiped-and-hatched row, because the
-- question it exists to answer is comparative: is cap restating Blizzard's swipe or adding to it?
local function buildHatch()
  section("V11 · cooldown hatch")
  local h = ns.Style.hatch
  local x = PAD
  for _, cell in ipairs({
    { caption = "swipe only", swipe = true, hatch = false },
    { caption = "hatch only", swipe = false, hatch = true },
    { caption = "as it ships", swipe = true, hatch = true },
    { caption = "untreated", swipe = false, hatch = false },
  }) do
    local host = swatch(x, y, SAMPLE[1].spell, cell.caption)
    if cell.swipe then swipe(host) end
    if cell.hatch then
      local hatch = ns.Paint.Hatch(host, 0)
      if hatch then hatch:SetShown(true) end
    end
    x = x + icon() + SPREAD
  end
  y = y + icon() + CAPTION_H + 6
  note(("A %dpx sheet at %dpx pitch, tiled across a %dpx icon — roughly %.1f stripes per edge. "
        .. "Black at %.2f alpha, offset half a pitch so a second stripe condition could "
        .. "interleave with it."):format(
       h.tile_px, h.pitch_px, icon(), icon() / h.pitch_px, h.alpha))
end

local function cueKeys()
  local keys = {}
  for key in pairs(ns.Style.cues) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    local ca, cb = ns.Style.cues[a], ns.Style.cues[b]
    if ca.slot ~= cb.slot then return ca.slot < cb.slot end
    return a < b
  end)
  return keys
end

local function buildCues()
  section("V5.1 · the cues, each in its own slot")
  local x, badges = PAD, {}
  for _, key in ipairs(cueKeys()) do
    local cue = ns.Style.cues[key]
    local host = swatch(x, y, SAMPLE[2].spell, key .. " · " .. cue.slot)
    local badge = ns.Paint.Badge(host, key)
    if badge then
      badge:Show()
      badges[#badges + 1] = badge
    end
    x = x + icon() + SPREAD
  end
  y = y + icon() + CAPTION_H + 6
  return badges
end

local function buildSlots()
  section("V5 · all three slots, then a real row at the row gap")
  local badges = {}
  local host = swatch(PAD, y, SAMPLE[4].spell, "1 · 2 · 3")
  local filled = {}
  for _, key in ipairs(cueKeys()) do
    local slot = ns.Style.cues[key].slot
    -- One badge per slot: slot 2 carries two mutually exclusive cues, and drawing both would
    -- show a stack the player can never see.
    if not filled[slot] then
      filled[slot] = true
      local badge = ns.Paint.Badge(host, key)
      if badge then
        badge:Show()
        badges[#badges + 1] = badge
      end
    end
  end

  local x = PAD + icon() + SPREAD * 2
  for i = 1, 3 do
    local row = swatch(x, y, SAMPLE[i].spell, i == 2 and "row gap" or nil)
    ns.Paint.Border(row):SetShown(true)
    local badge = ns.Paint.Badge(row, "blocked")
    if badge then
      badge:Show()
      badges[#badges + 1] = badge
    end
    x = x + icon() + ns.Style.surfaces.row_gap_px
  end

  y = y + icon() + CAPTION_H + 6
  return badges
end

-- Part 7's lab: no authority, never a CDM row. Clearances beat the widest overhang drawn here.
local ISOLATION, LAB_CLEAR = 120, 72

local function lab()
  return ns.LabStyle or {}
end

local function labKeys()
  local keys = {}
  for k in pairs(lab()) do
    if k:sub(1, 1) ~= "_" then keys[#keys + 1] = k end
  end
  table.sort(keys)
  return keys
end

local function pitch()
  return icon() + ns.Style.surfaces.row_gap_px
end

--- Lab cells name abilities the way catalog.md does; the catalogs key them as slugs.
local function spellOf(name)
  if not name then return nil end
  local slug = (name:lower():gsub("[^%w]+", "_"))
  for _, cat in ipairs(ns.Catalog.All()) do
    for _, ability in ipairs(cat.abilities or {}) do
      if ability.id == slug then return ability.spell end
    end
  end
end

--- A layer's numbers come from ONE entry plus the shared sheet — never a shared "striped" flag.
local function stripeSpec(key)
  local sheet, entry = lab()._sheet, lab()[key]
  return {
    texture = sheet.texture_root .. sheet.texture .. ".tga",
    tile_px = sheet.tile_px,
    pitch_px = sheet.pitch_px,
    rgb = entry.rgb,
    alpha = entry.alpha,
    phase_pct = entry.phase_pct,
  }
end

--- The cell's icon plus Blizzard's swipe if its verdict carries one. No border: it is not the subject.
local function stripeCell(cell, x, top)
  local host = swatch(x, top, spellOf(cell.ability), cell.ability or "sheet")
  if cell.verdict and (ns.Style.verdicts[cell.verdict] or {}).swipe then swipe(host) end
  return host
end

local function drawStripes(key, entry)
  local x, badges = PAD, {}
  for _, cell in ipairs(entry.cells or {}) do
    local host = stripeCell(cell, x, y)
    -- A `sheet` cell is the entry's own stripes with no icon under them.
    local layers = cell.kind == "sheet" and { "self" } or cell.stripes or {}
    for _, which in ipairs(layers) do
      ns.Paint.Stripes(host, stripeSpec(which == "self" and key or which))
    end
    for _, cue in ipairs(cell.cues or {}) do
      local badge = ns.Paint.Badge(host, cue)
      if badge then
        -- Above the stripes, which sit two levels up: the badge says *why* and must stay legible.
        badge.frame:SetFrameLevel(host:GetFrameLevel() + 3)
        badges[#badges + 1] = badge
      end
    end
    x = x + icon() + SPREAD
  end
  y = y + icon() + CAPTION_H + 6
  return badges
end

--- One row: the treatment alone, then the same treatment inside the stage's neighbours at the
--- true pitch. `make(host)` builds it and returns a replay.
local function arrivalRow(caption, make)
  local hosts, plays = {}, {}
  local function place(x, cap)
    local host = swatch(x, y, SAMPLE[1].spell, cap)
    hosts[#hosts + 1] = host
    plays[#plays + 1] = make(host)
    return host
  end

  place(PAD, caption)

  local n = (lab()._arrival_stage or {}).neighbours or 0
  local cx = PAD + icon() + ISOLATION + n * pitch()
  for i = 1, n do
    for _, step in ipairs({ -i, i }) do
      ns.Paint.Border(swatch(cx + step * pitch(), y, SAMPLE[2].spell)):SetShown(true)
    end
  end
  place(cx, "with neighbours")

  y = y + icon() + CAPTION_H + LAB_CLEAR
  return hosts, plays
end

local function subjectColor()
  return ns.Style.ready
end

--- The lab's four-strip rings take a band width as an argument; the style declares one.
local function subjectBand()
  return ns.Style.ready.line_px
end

--- Today's builder at each declared from_scale — the control that can falsify the diagnosis.
local function drawSweep(key, entry)
  local a, hue = ns.Style.arrival, subjectColor()
  for _, scale in ipairs(entry.from_scale_sweep or {}) do
    local crosses = ns.Paint.CrossesNeighbour(icon(), scale, pitch())
    local caption = ("%.2fx · %s"):format(scale, crosses and "reaches the neighbour" or "clear")
    local hosts, plays = arrivalRow(caption, function(host)
      local ring = ns.Paint.Ring(host, { rgb = hue.rgb, thickness_px = subjectBand() })
      local snap = ns.Paint.Arrival(ring.frame, {
        from_scale = scale, from_alpha = a.from_alpha,
        duration_s = a.duration_s, smoothing = a.smoothing,
      })
      return function() snap:Stop(); snap:Play() end
    end)
    replayOnClick(hosts, plays, a.duration_s)
  end
  note("⚠ The gallery's ring is the icon itself, which is now also what a live row draws on: " ..
       "the scan edge sits ON the icon rect, so a value that reads clear here reads clear there.")
end

--- Variant B: the declared snap on a ring whose thickness is an anchor offset.
local function drawRelative(key, entry)
  local a, hue = ns.Style.arrival, subjectColor()
  local hosts, plays = arrivalRow("relative ring", function(host)
    local ring = ns.Paint.Ring(host, {
      rgb = hue.rgb, thickness_px = subjectBand(), relative = true,
    })
    local snap = ns.Paint.Arrival(ring.frame)
    return function() snap:Stop(); snap:Play() end
  end)
  replayOnClick(hosts, plays, a.duration_s)
end

--- Variant C: no Scale anywhere. Two pre-built rings; only alpha moves, so nothing overhangs.
local function drawThickness(key, entry)
  local hue = subjectColor()
  local hosts, plays = arrivalRow("fat ring, alpha only", function(host)
    ns.Paint.Ring(host, { rgb = hue.rgb, thickness_px = subjectBand() })
    local fat = ns.Paint.Ring(host, {
      rgb = hue.rgb, thickness_px = ns.Paint.FatRing(subjectBand(), entry.fat_mult),
    })
    local flash = ns.Paint.Flash(fat.frame, entry.duration_s)
    return function() flash:Stop(); flash:Play() end
  end)
  replayOnClick(hosts, plays, entry.duration_s)
end

--- Variant D: the declared border, never animated, plus a ghost that grows outward and fades.
local function drawGhost(key, entry)
  local hue = subjectColor()
  local hosts, plays = arrivalRow("ghost ping", function(host)
    ns.Paint.Border(host):SetShown(true)
    local ghost = ns.Paint.Ghost(host, {
      rgb = hue.rgb, thickness_px = subjectBand(),
      from_scale = entry.from_scale, to_scale = entry.to_scale,
      from_alpha = entry.from_alpha, to_alpha = entry.to_alpha,
      duration_s = entry.duration_s, smoothing = entry.smoothing,
    })
    return function() ghost:Play() end
  end)
  replayOnClick(hosts, plays, entry.duration_s)
end

--- A readiness cell: one icon, or `kind = "row"` — four icons at the TRUE row pitch, which is what
--- the candles test needs. `make(host, cell)` applies the treatment and returns a replay.
local function readyCells(entry, make)
  local hosts, plays = {}, {}
  local x = PAD
  for _, cell in ipairs(entry.cells or {}) do
    local names = cell.kind == "row" and (cell.abilities or {}) or { cell.ability }
    for i, name in ipairs(names) do
      local host = swatch(x, y, spellOf(name), i == 1 and (cell.ability or "row") or nil)
      hosts[#hosts + 1] = host
      plays[#plays + 1] = make(host, cell)
      x = x + icon() + (cell.kind == "row" and ns.Style.surfaces.row_gap_px or 0)
    end
    x = x + SPREAD
  end
  y = y + icon() + CAPTION_H + 6
  return hosts, plays
end

--- The halo family: static, breathing, or flaring and decaying to a floor. Every one of them
--- rests LIT, so each is played once as the section is built and replays on click.
local function drawReadyGlow(key, entry)
  local hosts, plays = readyCells(entry, function(host)
    local halo = ns.Paint.Halo(host, entry)
    halo:Play()
    return function() halo:Play() end
  end)
  replayOnClick(hosts, plays, entry.decay_s or entry.period_s or 0)
end

--- The hairline family: full brightness on a restrained area, at the width the CELL asks for —
--- the ladder is the experiment, so a per-cell `line_px` overrides the entry's.
local function drawReadyLine(key, entry)
  readyCells(entry, function(host, cell)
    ns.Paint.Ring(host, {
      rgb = entry.rgb,
      thickness_px = cell.line_px or entry.line_px,
      alpha = entry.rest_alpha,
      add = true,
    })
    return function() end
  end)
end

--- Part 7 · the blaze. A promotion that SHOUTS rather than points.
---
--- The two entries differ in ONE thing: what shape the light has. `behind = "glyph"` tints a
--- scaled-up copy of the sprite itself, so the flame looks like the source of its own light;
--- `behind = "plate"` uses the round halo and lets the dark plate sit over it, so the blaze has
--- a hard circular edge and the glyph keeps its contrast.
---
--- ADD blend on both, because that is what the client does with additive art and the whole
--- reason the gallery exists is to show what the client does rather than what CSS approximates.
local function drawBlaze(key, entry)
  -- TWO roots: the SPRITE is `fire`, which the style owns since `priority` took it as a glyph,
  -- and the SHEET is VFX art the lab still owns. A lab entry citing the style is the legal
  -- direction (Part 7 rule 1); the alternative is a second copy of `fire` on disk.
  local root = (ns.LabStyle._sprites or {}).texture_root
  local sheetRoot = (ns.LabStyle._sheets or {}).texture_root
  local hosts, plays = readyCells(entry, function(host)
    local g = ns.Paint.Geometry()
    local layer = CreateFrame("Frame", nil, host)
    layer:SetSize(g.diameter, g.diameter)
    layer:SetPoint("TOPRIGHT", host, "TOPRIGHT", g.overhang, g.overhang)

    -- The bright field, BEHIND everything else in the badge.
    -- Three shapes for one field, which is the only thing separating these entries:
    --   glyph  — the lab's own sprite, so the light has the flame's silhouette
    --   corona — a real ring, keeping its own falloff (a flat colour through a mask would lose
    --            the part that reads as heat)
    --   plate  — the style's round halo, so it has a hard disc's edge
    local blaze = layer:CreateTexture(nil, "BACKGROUND")
    if entry.behind == "glyph" then
      blaze:SetTexture(root .. entry.sprite .. ".tga", nil, nil, "TRILINEAR")
    elseif entry.behind == "corona" or entry.behind == "sheet" then
      blaze:SetTexture(sheetRoot .. entry.sheet .. ".tga", nil, nil, "TRILINEAR")
    else
      blaze:SetTexture(ns.Style.badges.texture_root
        .. ns.Style.badges.halo_texture .. ".tga", nil, nil, "TRILINEAR")
    end
    local spread = entry.spread or 1
    blaze:SetPoint("CENTER", layer, "CENTER", 0, 0)
    blaze:SetSize(g.diameter * spread, g.diameter * spread)
    blaze:SetBlendMode("ADD")
    -- The corona is baked art with its own gradient; tinting it multiplies that gradient toward
    -- one colour and flattens the falloff. The other two fields are neutral shapes and want it.
    -- Baked art keeps its own gradient: tinting it multiplies that toward one colour and
    -- flattens the falloff. Neutral fields (a shape, or a sheet declaring `tint = "lane"`) are
    -- the ones that want the authored hue.
    if entry.behind ~= "corona" and (entry.behind ~= "sheet" or entry.tint == "lane") then
      blaze:SetVertexColor(entry.rgb[1], entry.rgb[2], entry.rgb[3])
    end

    -- A sheet field walks its frames, using the same precomputed `cell / sheet` step the
    -- flipbook family uses -- never `1 / cols`, which would step into the power-of-two padding.
    if entry.behind == "sheet" and (entry.frames or 1) > 1 and (entry.fps or 0) > 0 then
      local cols, du, dv = entry.cols or 1, entry.du or 1, entry.dv or 1
      local n, fps, i, acc = entry.frames, entry.fps, 0, 0
      local function frame(k)
        local c, r = k % cols, math.floor(k / cols)
        blaze:SetTexCoord(c * du, (c + 1) * du, r * dv, (r + 1) * dv)
      end
      frame(0)
      layer:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        while acc >= 1 / fps do
          acc = acc - 1 / fps
          i = (i + 1) % n
          frame(i)
        end
      end)
    end
    blaze:SetAlpha(entry.flare_alpha or entry.rest_alpha or 1)

    -- The plate. Every field EXCEPT `glyph` keeps it, because the layering is glyph on top,
    -- dark disc under it, effect behind that -- a badge that loses its disc stops reading as a
    -- badge. `glyph` is the exception on purpose: there the light wears the glyph's own
    -- silhouette, and a disc between the two would hide the whole treatment.
    if entry.behind ~= "glyph" then
      local plate = layer:CreateTexture(nil, "ARTWORK")
      plate:SetTexture(ns.Style.badges.texture_root
        .. ns.Style.badges.plate.texture .. ".tga", nil, nil, "TRILINEAR")
      plate:SetPoint("CENTER", layer, "CENTER", 0, 0)
      plate:SetSize(g.plate, g.plate)
      local pl = ns.Style.badges.plate
      plate:SetVertexColor(pl.rgb[1], pl.rgb[2], pl.rgb[3])
      plate:SetAlpha(pl.alpha)
    end

    -- The glyph. Full alpha ALWAYS -- what breathes is the light behind it, never the mark
    -- carrying the information (render-shelf.md V5).
    local sprite = layer:CreateTexture(nil, "OVERLAY")
    sprite:SetTexture(root .. entry.sprite .. ".tga", nil, nil, "TRILINEAR")
    sprite:SetPoint("CENTER", layer, "CENTER", 0, 0)
    sprite:SetSize(g.sprite, g.sprite)
    local gl = entry.glyph_rgb or { 1, 1, 1 }
    sprite:SetVertexColor(gl[1], gl[2], gl[3])

    local group
    if entry.period_s then
      group = layer:CreateAnimationGroup()
      group:SetLooping("BOUNCE")
      local breathe = group:CreateAnimation("Alpha")
      breathe:SetChildKey("blaze")
      breathe:SetFromAlpha(entry.rest_alpha or 1)
      breathe:SetToAlpha(entry.flare_alpha or 1)
      breathe:SetDuration(entry.period_s / 2)
      breathe:SetSmoothing("IN_OUT")
      group:Play()
    end
    return function() if group then group:Play() end end
  end)
  replayOnClick(hosts, plays, entry.period_s or 0)
end

--- Part 7 · the icon-scale VFX family (the proc-glow candidates).
---
--- A flipbook sheet walked with SetTexCoord, which is the thing the browser preview can only
--- approximate: the client's ADD blend over Blizzard's own icon art is the whole question these
--- entries exist to ask, and CSS `mix-blend-mode: screen` is not it.
---
--- The sheet is padded to a power of two, so a cell's texcoords come from the DECLARED grid and
--- the padding is never addressed. Frame count is carried, not inferred -- an 8x4 sheet holding
--- 30 frames has two dead cells and walking into them would show blank.
local function drawFlipbook(key, entry)
  local root = (ns.LabStyle._sheets or {}).texture_root
  local hosts, plays = readyCells(entry, function(host)
    local layer = CreateFrame("Frame", nil, host)
    local w, h = host:GetWidth(), host:GetHeight()
    local scale = entry.scale or 1
    layer:SetSize(w * scale, h * scale)
    layer:SetPoint("CENTER", host, "CENTER", 0, 0)
    layer:SetFrameLevel(math.max(host:GetFrameLevel() - 1, 0))

    local tex = layer:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(root .. entry.sheet .. ".tga", nil, nil, "TRILINEAR")
    tex:SetAllPoints(layer)
    tex:SetBlendMode(entry.blend or "ADD")
    -- Neutral art takes the authored hue; baked art is drawn as it is. Which one a sheet is
    -- gets DECLARED (`tint`) and `capart check` fails a declaration the art contradicts.
    if entry.tint == "lane" and entry.rgb then
      tex:SetVertexColor(entry.rgb[1], entry.rgb[2], entry.rgb[3])
    end

    -- ⚠ `du`/`dv` are the texcoord step, precomputed by capart as `cell / sheet`. NOT `1/cols`:
    -- the sheet is padded to a power of two, so an 8x3 grid of 64px cells sits in a 512x256
    -- texture with a quarter of the height unused, and dividing by `rows` would stretch every
    -- frame and walk into the padding.
    local cols = entry.cols or 1
    local du, dv = entry.du or 1, entry.dv or 1
    local function frame(i)
      local c, r = i % cols, math.floor(i / cols)
      tex:SetTexCoord(c * du, (c + 1) * du, r * dv, (r + 1) * dv)
    end
    frame(0)

    local n, fps = entry.frames or 1, entry.fps or 0
    if n > 1 and fps > 0 then
      local i, acc = 0, 0
      layer:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        while acc >= 1 / fps do
          acc = acc - 1 / fps
          i = (i + 1) % n
          frame(i)
        end
      end)
    elseif entry.period_s then
      -- A single-frame entry cannot shimmer, so it breathes: shape isolated from motion, which
      -- is exactly the comparison the circular entry exists to make against the square one.
      local group = layer:CreateAnimationGroup()
      group:SetLooping("BOUNCE")
      local a = group:CreateAnimation("Alpha")
      a:SetFromAlpha(0.45)
      a:SetToAlpha(1)
      a:SetDuration(entry.period_s / 2)
      a:SetSmoothing("IN_OUT")
      group:Play()
      return function() group:Play() end
    end
    return function() end
  end)
  replayOnClick(hosts, plays, entry.period_s or 0)
end

--- Part 7 · the font candidates for V15's hotkey text.
---
--- THE GALLERY IS WHERE A FONT IS DECIDED, not the preview. The browser measures the same advance
--- widths — the preview embeds the very same subset files — but the client rasterises a TTF into a
--- signed-distance-field slug (the install's own `Fonts/615960.slug` is FRIZQT's), so the PIXELS
--- at 14 px are the client's to show and nobody else's.
---
--- A candidate's file is either the CLIENT'S, which every install already has and cap only names,
--- or OURS, subset and shipped to `Media/lab/` by `capart export lab`. That difference is the
--- whole shipping question, and `entry.font.shippable` is where the entry states it.
local function drawHotkey(key, entry)
  local font = entry.font or {}
  readyCells(entry, function(host, cell)
    local fs = host:CreateFontString(nil, "OVERLAY")
    -- ⚠ `SetFont` returns false rather than raising when the file is missing, and a refusal
    -- leaves a bare FontString on NO font at all — invisible, which would read as "this candidate
    -- draws nothing" instead of "this candidate is not installed". So the refusal is reported.
    local ok = font.client_path
      and fs:SetFont(font.client_path, entry.size_px, entry.outline or "OUTLINE")
    if not ok then
      note("`" .. tostring(font.client_path) .. "` did not load — this candidate cannot be " ..
           "judged here. If it is ours, run `capart export lab`; if it is the client's, the " ..
           "path is wrong.")
      return function() end
    end
    local T = ns.Style.hotkey
    fs:SetTextColor(T.rgb[1], T.rgb[2], T.rgb[3])
    fs:SetAlpha(T.alpha)
    fs:SetJustifyH("LEFT")
    fs:SetPoint(T.anchor, host, T.anchor, T.offset.x, T.offset.y)
    fs:SetText(cell.key or "3")

    -- The title bar, where a candidate has one. Full icon width, anchored to the top edge, with
    -- the label centred in it — so the bar's size is a constant of the row and never a function
    -- of what is written in it. That is the whole difference from the plate below.
    --
    -- ⚠ `SetGradient` RESETS VERTEX COLOUR TO WHITE (render-shelf.md Part 3), so the fade is
    -- applied as two full colours rather than as a tint over a gradient. Both stops carry the
    -- same rgb and differ only in alpha, which is what makes this a scrim rather than a wash.
    local bar = entry.bar
    if bar then
      local t = host:CreateTexture(nil, "ARTWORK")
      t:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
      t:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
      t:SetHeight(bar.height_px)
      if bar.fade and CreateColor then
        t:SetColorTexture(1, 1, 1, 1)
        t:SetGradient("VERTICAL",
          CreateColor(bar.rgb[1], bar.rgb[2], bar.rgb[3], 0),
          CreateColor(bar.rgb[1], bar.rgb[2], bar.rgb[3], bar.alpha))
      else
        t:SetColorTexture(bar.rgb[1], bar.rgb[2], bar.rgb[3], bar.alpha)
      end
      if bar.rule then
        local line = host:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(bar.rule.rgb[1], bar.rule.rgb[2], bar.rule.rgb[3], bar.rule.alpha)
        line:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, 0)
        line:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", 0, 0)
        line:SetHeight(bar.rule.px)
      end
      -- Re-anchored into the bar: the corner offset the style declares is about a corner label,
      -- and this is not one.
      fs:ClearAllPoints()
      fs:SetJustifyH(bar.align == "center" and "CENTER" or "LEFT")
      fs:SetPoint("CENTER", t, "CENTER", 0, 0)
    end

    -- The plate, where a candidate has one: contrast from the ground instead of from the stroke.
    -- An unsized FontString takes the extent of its own text, so anchoring the texture to the
    -- string's two corners sizes the plate to the label with no measuring — and it re-sizes for
    -- free when the text changes, which `SetText` on a live row does.
    --
    -- ⚠ ARTWORK, not OVERLAY: the layer is shared with the text and the text has to win. And a
    -- flat `SetColorTexture` rect is the whole primitive — square corners, because rounding one
    -- means shipping art, which is a different proposal from a colour and an alpha.
    local plate = entry.plate
    if plate then
      local t = host:CreateTexture(nil, "ARTWORK")
      t:SetColorTexture(plate.rgb[1], plate.rgb[2], plate.rgb[3], plate.alpha)
      t:SetPoint("TOPLEFT", fs, "TOPLEFT", -(plate.pad_x_px or 0), plate.pad_y_px or 0)
      t:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", plate.pad_x_px or 0, -(plate.pad_y_px or 0))
    end
    return function() end
  end)
end

local DRAWS = {
  ["hotkey"] = drawHotkey,
  ["flipbook"] = drawFlipbook,
  ["blaze"] = drawBlaze,
  ["stripes"] = drawStripes,
  ["arrival-sweep"] = drawSweep,
  ["arrival-relative"] = drawRelative,
  ["arrival-thickness"] = drawThickness,
  ["arrival-ghost"] = drawGhost,
  ["ready-glow"] = drawReadyGlow,
  ["ready-line"] = drawReadyLine,
}

--- Whether the gallery can actually draw an entry. A Part 7 entry nothing can draw is invisible
--- in the client, which is the only place it could ever have been judged.
function SP.CanDraw(draws)
  return DRAWS[draws] ~= nil
end

--- `count` swatches on one line, each `size` wide, `gap` between them, `pad` on both ends.
function SP.RowWidth(count, size, gap, pad)
  if count < 1 then return pad * 2 end
  return pad * 2 + count * size + (count - 1) * gap
end

--- An arrival row: the isolated subject, the clear space, then the symmetric neighbour stage.
function SP.StageWidth(size, isolation, neighbours, pitch_px, pad)
  return pad * 2 + size * 2 + isolation + 2 * neighbours * pitch_px
end

--- Which lab tab an entry draws on, from its `draws` family: arrival experiments need the
--- isolation stage, readiness experiments need the true row pitch, everything else needs neither.
function SP.LabTab(draws)
  local family = tostring(draws):match("^%a+")
  if family == "arrival" or family == "ready" then return family end
  -- `blaze` files onto the readiness tab: it is a badge-scale treatment judged against its
  -- NEIGHBOURS, and that tab is the one drawn at the true row pitch. `hotkey` joins it for the
  -- same reason — a label is judged against the art under it and the badge beside it, never on
  -- its own line.
  if family == "blaze" or family == "flipbook" or family == "hotkey" then return "ready" end
  return "stripes"
end

local function collect(into, from)
  for _, badge in ipairs(from or {}) do into[#into + 1] = badge end
end

local function open(pane)
  container, y = pane, PAD
end

local function close(pane, badges)
  pane.badges = badges
  return y + PAD
end

local function buildStyle(pane)
  open(pane)
  local badges = {}
  text(container, "GameFontNormal", PAD, y, "render shelf v" .. tostring(ns.Style.version), 320)
  y = y + LABEL_H + 4

  buildScan()
  buildHatch()
  collect(badges, buildCues())
  collect(badges, buildSlots())
  note("Every texture here is cap's own. Numbers come from Style.lua, generated from " ..
       "render-shelf.md Part 6.")
  return close(pane, badges)
end

local LAB_BLURB = {
  stripes = "Experiments, drawn so they can be judged in the client. Nothing on this tab is " ..
            "the style, nothing on it decides anything, and none of it reaches a Cooldown " ..
            "Manager row.",
  arrival = "Experiments, drawn so they can be judged in the client. Nothing on this tab is " ..
            "the style, nothing on it decides anything, and none of it reaches a Cooldown " ..
            "Manager row. Read arrival-control-sweep first: it is the falsifier. An arrival " ..
            "row replays on click, rate limited to its own duration.",
  ready = "Candidate readiness treatments, drawn so they can be judged in the client. Nothing " ..
          "on this tab is the style and none of it reaches a Cooldown Manager row. Each entry " ..
          "draws alone and then four at once at the TRUE row pitch — the candles test.",
}

local function buildLabPane(which)
  return function(pane)
    open(pane)
    local badges, any = {}, false
    section("LAB · render-shelf.md Part 7 — no authority, decides nothing")
    note(LAB_BLURB[which])
    for _, key in ipairs(labKeys()) do
      local entry = lab()[key]
      if SP.LabTab(entry.draws) == which then
        any = true
        section("lab." .. key .. "  ·  " .. (entry.title or key))
        note(entry.asks or "no `asks` — Part 7 says an entry that cannot say what it is asking " ..
                           "is decoration")
        local draw = DRAWS[entry.draws]
        if draw then
          collect(badges, draw(key, entry))
        else
          note("nothing here knows how to draw `" .. tostring(entry.draws) .. "`.")
        end
      end
    end
    if not any then
      note("The lab holds nothing here. That is its correct resting state, not a defect.")
    end
    return close(pane, badges)
  end
end

local TABS = {
  { id = "style", label = "Style", build = buildStyle },
  { id = "stripes", label = "Lab · stripes", build = buildLabPane("stripes") },
  { id = "arrival", label = "Lab · arrival", build = buildLabPane("arrival") },
  { id = "ready", label = "Lab · ready", build = buildLabPane("ready") },
}

-- ---------------------------------------------------------------------------
-- Command
-- ---------------------------------------------------------------------------

local DEFAULT_H, DEFAULT_X, DEFAULT_Y = 560, 200, 40

--- The widest line any tab draws, measured rather than guessed: swatches sit at the real icon size.
local function contentWidth()
  local cells = math.max(4, #cueKeys())
  for _, key in ipairs(labKeys()) do
    cells = math.max(cells, #(lab()[key].cells or {}))
  end
  local n = (lab()._arrival_stage or {}).neighbours or 0
  return math.max(SP.RowWidth(cells, icon(), SPREAD, PAD),
                  SP.StageWidth(icon(), ISOLATION, n, pitch(), PAD))
end

local window

local function create()
  return ns.Window.New{
    name = "CombatAssistPlusStyleWindow", key = "style", title = "cap · render shelf",
    width = contentWidth(), height = DEFAULT_H, x = DEFAULT_X, y = DEFAULT_Y,
    tabs = TABS,
    onSelect = function(_, pane)
      for _, badge in ipairs(pane.badges or {}) do badge:Show() end
    end,
    onHide = function() ns.Emit("style gallery closed.") end,
  }
end

local function show(arg)
  if not window then
    if InCombatLockdown() then
      ns.Emit("the style window is not built yet, and building it is out of combat only.")
      return
    end
    window = create()
  end
  local tab = ns.Window.TabIndex(TABS, arg)
  if arg ~= "" and not tab then
    ns.Emit("usage: /cap style  or  /cap style style|stripes|arrival")
    return
  end
  if tab then window:Select(tab) end
  window:Show()
  ns.Emit("style gallery open — drag the title bar to place it, /cap style again to close.")
end

ns.RegisterCommand{
  name = "style", order = 45, args = "[style|stripes|arrival|ready]",
  desc = "Open the render-shelf gallery in its own window",
  handler = function(rest)
    local arg = (rest or ""):lower()
    if arg == "" and window and window:IsShown() then
      window:Hide()
      return
    end
    show(arg)
  end,
}
