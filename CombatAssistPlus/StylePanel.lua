-- StylePanel.lua — `/cap style`: every render-shelf primitive drawn once, side by side,
-- in its own scrolling window. Two tabs: the STYLE, which is Parts 1-6 and decides things,
-- and the LAB, which is Part 7 and decides nothing.
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

-- ⚠ The ONE client reader of the preview's authoring nominal, and deliberately so. Every
-- painter uses `surfaces.host_nominal_px` (50) because it is standing in for a real frame; the
-- gallery is not decorating anything, it is showing the shelf AS AUTHORED, so the number that
-- belongs here is the one the shelf was drawn against. Not a site the 2026-08-31 split missed.
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

-- Part 7's lab: no authority, never a CDM row.
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

-- ---------------------------------------------------------------------------
-- Part 7 · the sealed displays
--
-- The treatments in which a SECRET value — an aura's application count, or a DoT's remaining
-- duration — reaches a pixel without cap ever learning it. In the client the platform owns the
-- widget: `SetApplicationCount` seals a FontString's `Text` and `Shown`, `SetApplicationBar`
-- seals a StatusBar's value, `AddPandemicRegion` seals a Region's `Shown`.
--
-- ⚠ THE GALLERY DRIVES THEM BY HAND, from the value the CELL states, and that is the one thing
-- to keep straight while reading a cell. A caption saying "at 4 stacks" is a reader's
-- convenience; cap can never know that, and no live row will ever be drawn this way. What the
-- gallery is for is the half a browser cannot show: how the client renders a band's inline
-- texture escape, what `SetVertexColor` does over Blizzard's own icon art, whether a radial
-- render mode reads as a count or as a timer.

--- The band input: a count sink bands on the aura's applications, `SetDurationText` bands on a
--- DurationTextBindingProperty. One renderer, because it is one formatter object — what changes
--- is which sealed number the client feeds it.
local function bandValue(cell)
  if cell.remaining_pct ~= nil then return cell.remaining_pct end
  return cell.stacks or 0
end

--- A lab cell captioned with the value it STATES rather than with its ability name, because the
--- value is what the cell is an argument about.
local function labSwatch(cell, x, caption)
  local host = swatch(x, y, spellOf(cell.ability), caption)
  if cell.verdict and (ns.Style.verdicts[cell.verdict] or {}).swipe then swipe(host) end
  return host
end

local function valueCaption(cell)
  if cell.remaining_pct ~= nil then return cell.remaining_pct .. "%" end
  if cell.stacks ~= nil then return cell.stacks .. (cell.max and ("/" .. cell.max) or "") end
  return cell.state or cell.ability
end

--- One banded FontString, driven to the cell's value. Shared by `count`, `count-glyph` and
--- `duration`, which are three questions about ONE mechanism and differ only in what the band's
--- `format` carries: a numeral, a texture escape, or both.
---
--- ⚠ The format string is passed to `SetText` UNTOUCHED. `|T…|t` and `|A:…|a` inside a band
--- render as art `[client 2026-08-21]`, so anything this function stripped would be the gallery
--- showing something the client does not.
local function bandedString(host, key, entry, cell, rgb)
  local drawn = ns.Paint.BandText(cell.bands, bandValue(cell))
  -- A band carrying a full-icon escape is about the WHOLE icon, so its string is centred; the
  -- corner marks in the same band get there through the escape's own `:xoff:yoff`.
  local place = cell.place
  if ns.Paint.BandIsFullIcon(drawn, icon()) then place = nil end

  local band = ns.Paint.CountString(host, {
    font = entry.font, size = cell.size_px or entry.size_px or entry.size,
    outline = entry.outline, rgb = rgb, place = place, y_px = entry.y,
  })
  band:SetBand(drawn)
  band.text = drawn
  return band
end

--- L5/L6 · the same formatter with a TEXTURE ESCAPE in the band.
---
--- The difference from `drawCount` is one line and it is the whole entry: a `composited` cell's
--- plate is baked INTO the art the escape names, so it rides the band. The gallery has no
--- pre-composited crop on disk, so it draws cap's own plate and gates it on the band being
--- non-empty — which is exactly the visibility the baked plate would have, and it makes the
--- empty corner at rest visible for what it is.
local function drawCountGlyph(key, entry)
  local x = PAD
  for _, cell in ipairs(entry.cells or {}) do
    local host = labSwatch(cell, x, valueCaption(cell))
    local rgb = cell.alt_hue and entry.alt_rgb or entry.rgb
    local band = bandedString(host, key, entry, cell, rgb)
    if cell.composited and band.text ~= "" and cell.place == "badge"
      and not ns.Paint.BandIsFullIcon(band.text, icon()) then
      local plate = ns.Paint.CountPlate(host, 0)
      plate:SetFrameLevel(band.frame:GetFrameLevel() - 1)
    end
    -- One motion per region, on the frame the band gates, so everything it draws breathes
    -- together. While the band is blank there is nothing to animate, which is why the mark
    -- arrives already breathing and cap branched on nothing to get it.
    if cell.motion == "pulse" and entry.pulse then
      ns.Paint.Breathe(band.frame, entry.pulse):Play()
    end
    x = x + icon() + SPREAD
  end
  y = y + icon() + CAPTION_H + 6
end

-- The gallery draws what the lab HOLDS, and the lab currently holds NOTHING. The sixteen handlers
-- the arrival, readiness, stripes and composite intakes needed went with those intakes: seven were
-- promoted into Parts 1-6 (V16-V20), the rest were judged and deleted, and a handler with no
-- entry to draw is a tab that can never render. `drawComposition` left the same way on 2026-08-28
-- with L9 `ring_collision`, which is the only entry it was ever written for. What remains below is
-- the count/duration pair, kept because it is the shape a banded-sink entry re-arrives in. A new
-- experiment brings its own handler here.
local DRAWS = {
  ["count-glyph"] = drawCountGlyph,
  ["duration"] = drawCountGlyph,
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

--- V16–V19 · the sealed displays, on the STYLE tab.
---
--- ⚠ These are the ONE part of the gallery that is not a faithful reproduction, and the reason is
--- the point of them: in the client the platform owns the widget and drives it from an aura count
--- cap never sees. There is no aura here and no secret, so each cell is drawn by hand at a value
--- the CAPTION states — which is a reader's convenience and never a claim cap can know that.
---
--- What the gallery is for is the half a browser cannot show: whether a band's inline texture
--- escape renders at all, what a radial render mode looks like at badge size over Blizzard's own
--- icon art, whether two sealed displays in one corner read as one statement or as a mess.
local function buildSealed()
  section("V16 · banded count  ·  V17 · the complement")
  local x, C = PAD, ns.Style.count
  local function countCell(caption, bands, value)
    local host = swatch(x, y, SAMPLE[4].spell, caption)
    local rules = ns.Channel.CountRules(bands, C)
    local band = rules and ns.Paint.BandFor(rules, value)
    local drawn = band and (band.format:gsub("%%d", tostring(value))) or ""
    local place = ns.Paint.BandIsFullIcon(drawn, icon()) and nil or "badge"
    local fs = ns.Paint.CountString(host, {
      font = C.font, size = C.size, outline = C.outline, place = place,
    })
    fs:SetBand(drawn)
    if C.pulse then ns.Paint.Breathe(fs.frame, C.pulse):Play() end
    x = x + icon() + SPREAD
    return host
  end

  -- The ORDINARY direction: silent while the row is a candidate, marked when it is not.
  local plain = {
    { threshold = 0, draw = "none" },
    { threshold = 2, draw = "mark", polarity = "negative", hatch = true },
  }
  countCell("1 · quiet", plain, 1)
  countCell("2 · ruled out", plain, 2)
  -- The COMPLEMENT: drawn below the threshold, cleared at it. The hatch says ruled out and the
  -- numeral says how far below — one element each, on their own slots.
  local complement = {
    { threshold = 0, draw = "count", polarity = "negative", hatch = true },
    { threshold = 6, draw = "none" },
  }
  countCell("3 · below", complement, 3)
  countCell("6 · clear", complement, 6)
  countCell("4 · positive", { { threshold = 0, draw = "mark" } }, 4)

  y = y + icon() + CAPTION_H + 6
  note("One SLOT per element — the hatch across the face, the mark or the numeral on the corner " ..
       "— each its own FontString with its own band table, and the band above the threshold " ..
       "clears them together. A band draws the mark or the number, never both. " ..
       "The VALUES here are the gallery's; in the client cap never learns which band fired.")

  section("V18 · sealed bar  ·  V19 · pandemic window  ·  V20 · proc bar")
  x = PAD
  local A = ns.Style.bar
  for _, at in ipairs({ 0, 2, 4 }) do
    local host = swatch(x, y, SAMPLE[4].spell, at .. " of 4")
    local bar = ns.Paint.CountBar(host, {
      rgb = A.rgb, track_rgb = A.track_rgb, track_alpha = A.track_alpha,
      w = icon(), h = A.height_px,
    })
    bar:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
    bar:SetValue(at / 4)
    -- The segment grid, and — at full — the whole-bar red flip the flip band draws in the
    -- client. Gallery-drawn statics; the live path is Channel's barSink/flipSink.
    for i = 1, 3 do
      local seg = bar:CreateTexture(nil, "OVERLAY")
      seg:SetColorTexture(A.track_rgb[1], A.track_rgb[2], A.track_rgb[3], A.track_alpha)
      seg:SetSize(A.seg_px or 1, A.height_px)
      seg:SetPoint("LEFT", bar, "LEFT", icon() * i / 4, 0)
    end
    if at == 4 then
      local flip = bar:CreateTexture(nil, "OVERLAY", nil, 7)
      flip:SetColorTexture(A.full_rgb[1], A.full_rgb[2], A.full_rgb[3], A.full_alpha or 1)
      flip:SetAllPoints(bar)
    end
    x = x + icon() + SPREAD
  end

  -- The window's own badge, drawn shown — which is the ONE state the client would ever show it in.
  local P, b = ns.Style.pandemic, ns.Style.badges
  local host = swatch(x, y, SAMPLE[4].spell, "in window")
  local slot = CreateFrame("Frame", nil, host)
  local g = ns.Paint.Geometry(host)
  slot:SetSize(g.diameter, g.diameter)
  slot:SetPoint("TOPRIGHT", host, "TOPRIGHT", ns.Paint.StackOffset(host, 0))
  local plate = slot:CreateTexture(nil, "OVERLAY", nil, 6)
  plate:SetTexture(b.texture_root .. b.plate.texture .. ".tga", nil, nil, "TRILINEAR")
  plate:SetVertexColor(b.plate.rgb[1], b.plate.rgb[2], b.plate.rgb[3])
  plate:SetAlpha(b.plate.alpha)
  plate:SetSize(g.plate, g.plate)
  plate:SetPoint("CENTER")
  -- The dial at a STATIC fraction: a swatch states the look; only the client drains the live
  -- one (Channel's windowSink, SetDurationBar → RemainingTime).
  local dial = CreateFrame("StatusBar", nil, slot)
  dial:SetSize(P.dial.size_px, P.dial.size_px)
  dial:SetPoint("CENTER")
  dial:SetMinMaxValues(0, 1)
  ns.Paint.BarFill(dial, P.dial, "gallery dial")
  pcall(dial.SetRenderMode, dial,
    Enum.StatusBarRenderMode and Enum.StatusBarRenderMode.Radial or 1)
  dial:SetValue(0.75)
  x = x + icon() + SPREAD

  -- V20 · the proc bar: the proc's remaining lifetime as a thin bar directly above the
  -- charge bar. Static fractions; the live one is Channel's procBarSink, drained by the
  -- client. Edge grammar, not badge grammar — gold here is quantity, never polarity.
  local PB = ns.Style.procbar
  local host20 = swatch(x, y, SAMPLE[4].spell, "proc bar")
  local charge20 = ns.Paint.CountBar(host20, {
    rgb = A.rgb, track_rgb = A.track_rgb, track_alpha = A.track_alpha,
    w = icon(), h = A.height_px,
  })
  charge20:SetPoint("BOTTOMLEFT", host20, "BOTTOMLEFT", 0, 0)
  charge20:SetValue(2 / 4)
  local pbar = CreateFrame("StatusBar", nil, host20)
  pbar:SetPoint("BOTTOMLEFT", host20, "BOTTOMLEFT", 0, A.height_px + (PB.gap_px or 0))
  pbar:SetPoint("BOTTOMRIGHT", host20, "BOTTOMRIGHT", 0, A.height_px + (PB.gap_px or 0))
  pbar:SetHeight(PB.height_px)
  pbar:SetMinMaxValues(0, 1)
  ns.Paint.BarFill(pbar, PB, "gallery proc bar")
  pbar:SetValue(0.6)

  y = y + icon() + CAPTION_H + 6
  note("A bar has NO BLANK STATE — the track draws at zero — and at full the WHOLE bar flips " ..
       "to the negative red: stop banking. The window badge authors no threshold at all: the " ..
       "client computes its own, per spell, and owns whether the region is shown. The proc " ..
       "bar is the proc's remaining lifetime above the charge bar — this many banked, this " ..
       "long to use one — drained by the client off the proc's own duration.")
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
  buildSealed()
  note("Every texture here is cap's own. Numbers come from Style.lua, generated from " ..
       "specs/render-tokens.json.")
  return close(pane, badges)
end

local LAB_BLURB =
  "Experiments, drawn so they can be judged in the client. Nothing on this tab is the style, " ..
  "nothing on it decides anything, and none of it reaches a Cooldown Manager row."

--- ONE lab tab, holding every Part 7 entry. There were three, split by experiment family,
--- because the arrival variants needed an isolation stage and the readiness ones the true row
--- pitch — and both stages went with their entries. A tab that can never render is worse than
--- absent: it advertises a question the gallery has no way to ask.
local function buildLabPane(pane)
  open(pane)
  local badges, any = {}, false
  section("LAB · render-shelf.md Part 7 — no authority, decides nothing")
  note(LAB_BLURB)
  for _, key in ipairs(labKeys()) do
    local entry = lab()[key]
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
  if not any then
    note("The lab holds nothing. That is its correct resting state, not a defect.")
  end
  return close(pane, badges)
end

local TABS = {
  { id = "style", label = "Style", build = buildStyle },
  { id = "lab", label = "Lab", build = buildLabPane },
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
  return SP.RowWidth(cells, icon(), SPREAD, PAD)
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
    ns.Emit("usage: /cap style  or  /cap style style|lab")
    return
  end
  if tab then window:Select(tab) end
  window:Show()
  ns.Emit("style gallery open — drag the title bar to place it, /cap style again to close.")
end

ns.RegisterCommand{
  name = "style", order = 45, args = "[style|lab]",
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
