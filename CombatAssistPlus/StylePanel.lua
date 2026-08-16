-- StylePanel.lua — `/cap style`: every render-shelf primitive drawn once, side by side,
-- in its own scrolling window with a tab per section.
--
-- The Lua twin of the artifact's swatch section. Nothing here touches a Cooldown Manager
-- frame; every texture is cap's own, so the gallery has no platform exposure at all.
local ADDON, ns = ...

ns.StylePanel = ns.StylePanel or {}
local SP = ns.StylePanel

local PAD, LABEL_H, CAPTION_H, SPREAD = 8, 13, 11, 18

-- Sample art: the Havoc roster ability the artifact draws for each lane, so the gallery and
-- havoc-stepper.html show the same icon under the same border.
local SAMPLE = {
  { lane = "COOLDOWN", spell = 191427, name = "Metamorphosis" },
  { lane = "ROTATION", spell = 188499, name = "Blade Dance" },
  { lane = "FALLBACK", spell = 344865, name = "Fel Rush" },
  { lane = "CHARGES", spell = 258920, name = "Immolation Aura" },
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

local function buildLanes()
  section("V2 · lane borders")
  local x = PAD
  for _, s in ipairs(SAMPLE) do
    local host = swatch(x, y, s.spell, s.lane:lower())
    ns.Paint.Border(host, s.lane)
    x = x + icon() + SPREAD
  end
  y = y + icon() + CAPTION_H + 6
  note("CHARGES has no live subject yet — no catalog reports charges, so it draws here only.")
  local ring = ns.Style.ring
  note(("One ring flipbook for every lane, tinted per lane: a %dpx band in a %dpx cell draws at " ..
        "%.1fpx here. Click the arrival swatch below to watch its %d frames."):format(
       ring.thickness_px, ring.tile_px,
       ns.Paint.RingBand(ring.thickness_px, ring.tile_px, icon()), ring.frames))
end

local function buildMotion()
  section("V2 · arrival snap  ·  V7 · swipe")
  local x = PAD

  local host = swatch(x, y, SAMPLE[1].spell, "click to fire")
  local border = ns.Paint.Border(host, "COOLDOWN")
  replayOnClick({ host }, { function() border:Snap() end }, ns.Style.arrival.duration_s)
  border:Snap()
  x = x + icon() + SPREAD

  local swiped = swatch(x, y, SAMPLE[3].spell, "swipe")
  swipe(swiped)

  y = y + icon() + CAPTION_H + 6
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
    ns.Paint.Border(row, SAMPLE[i].lane)
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
      ns.Paint.Border(swatch(cx + step * pitch(), y, SAMPLE[2].spell), "ROTATION")
    end
  end
  place(cx, "with neighbours")

  y = y + icon() + CAPTION_H + LAB_CLEAR
  return hosts, plays
end

local function subjectLane()
  return ns.Style.lanes.COOLDOWN
end

--- The lab's four-strip rings take a band width as an argument; the style declares one.
local function subjectBand()
  return ns.Style.ring.thickness_px
end

--- Today's builder at each declared from_scale — the control that can falsify the diagnosis.
local function drawSweep(key, entry)
  local a, lane = ns.Style.arrival, subjectLane()
  for _, scale in ipairs(entry.from_scale_sweep or {}) do
    local crosses = ns.Paint.CrossesNeighbour(icon(), scale, pitch())
    local caption = ("%.2fx · %s"):format(scale, crosses and "reaches the neighbour" or "clear")
    local hosts, plays = arrivalRow(caption, function(host)
      local ring = ns.Paint.Ring(host, { rgb = lane.rgb, thickness_px = subjectBand() })
      local snap = ns.Paint.Arrival(ring.frame, {
        from_scale = scale, from_alpha = a.from_alpha,
        duration_s = a.duration_s, smoothing = a.smoothing,
      })
      return function() snap:Stop(); snap:Play() end
    end)
    replayOnClick(hosts, plays, a.duration_s)
  end
  note("⚠ The gallery's ring is the icon itself. On a real row the border frame is 2px larger " ..
       "on every side, so it starts 4px closer to its neighbour and overhangs further at the " ..
       "same scale — a value that reads clear here is not yet clear there.")
end

--- Variant B: the declared snap on a ring whose thickness is an anchor offset.
local function drawRelative(key, entry)
  local a, lane = ns.Style.arrival, subjectLane()
  local hosts, plays = arrivalRow("relative ring", function(host)
    local ring = ns.Paint.Ring(host, {
      rgb = lane.rgb, thickness_px = subjectBand(), relative = true,
    })
    local snap = ns.Paint.Arrival(ring.frame)
    return function() snap:Stop(); snap:Play() end
  end)
  replayOnClick(hosts, plays, a.duration_s)
end

--- Variant C: no Scale anywhere. Two pre-built rings; only alpha moves, so nothing overhangs.
local function drawThickness(key, entry)
  local lane = subjectLane()
  local hosts, plays = arrivalRow("fat ring, alpha only", function(host)
    ns.Paint.Ring(host, { rgb = lane.rgb, thickness_px = subjectBand() })
    local fat = ns.Paint.Ring(host, {
      rgb = lane.rgb, thickness_px = ns.Paint.FatRing(subjectBand(), entry.fat_mult),
    })
    local flash = ns.Paint.Flash(fat.frame, entry.duration_s)
    return function() flash:Stop(); flash:Play() end
  end)
  replayOnClick(hosts, plays, entry.duration_s)
end

--- Variant D: the declared border, never animated, plus a ghost that grows outward and fades.
local function drawGhost(key, entry)
  local lane = subjectLane()
  local hosts, plays = arrivalRow("ghost ping", function(host)
    ns.Paint.Border(host, "COOLDOWN")
    local ghost = ns.Paint.Ghost(host, {
      rgb = lane.rgb, thickness_px = subjectBand(),
      from_scale = entry.from_scale, to_scale = entry.to_scale,
      from_alpha = entry.from_alpha, to_alpha = entry.to_alpha,
      duration_s = entry.duration_s, smoothing = entry.smoothing,
    })
    return function() ghost:Play() end
  end)
  replayOnClick(hosts, plays, entry.duration_s)
end

local DRAWS = {
  ["stripes"] = drawStripes,
  ["arrival-sweep"] = drawSweep,
  ["arrival-relative"] = drawRelative,
  ["arrival-thickness"] = drawThickness,
  ["arrival-ghost"] = drawGhost,
}

--- `count` swatches on one line, each `size` wide, `gap` between them, `pad` on both ends.
function SP.RowWidth(count, size, gap, pad)
  if count < 1 then return pad * 2 end
  return pad * 2 + count * size + (count - 1) * gap
end

--- An arrival row: the isolated subject, the clear space, then the symmetric neighbour stage.
function SP.StageWidth(size, isolation, neighbours, pitch_px, pad)
  return pad * 2 + size * 2 + isolation + 2 * neighbours * pitch_px
end

--- Which lab tab an entry draws on: arrival experiments need the stage, everything else does not.
function SP.LabTab(draws)
  return tostring(draws):find("^arrival") and "arrival" or "stripes"
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

  buildLanes()
  buildMotion()
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
  name = "style", order = 45, args = "[style|stripes|arrival]",
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
