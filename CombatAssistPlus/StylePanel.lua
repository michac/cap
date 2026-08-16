-- StylePanel.lua — `/cap style`: every render-shelf primitive drawn once, side by side.
--
-- The Lua twin of the artifact's swatch section. Nothing here touches a Cooldown Manager
-- frame; every texture is cap's own, so the gallery has no platform exposure at all.
local ADDON, ns = ...

local PAD, LABEL_H, CAPTION_H, SPREAD = 8, 13, 11, 18

-- Sample art: the Havoc roster ability the artifact draws for each lane, so the gallery and
-- havoc-stepper.html show the same icon under the same border.
local SAMPLE = {
  { lane = "COOLDOWN", spell = 191427, name = "Metamorphosis" },
  { lane = "ROTATION", spell = 188499, name = "Blade Dance" },
  { lane = "FALLBACK", spell = 344865, name = "Fel Rush" },
  { lane = "CHARGES", spell = 258920, name = "Immolation Aura" },
}

local container, built, y

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

--- Today's builder at each declared from_scale — the control that can falsify the diagnosis.
local function drawSweep(key, entry)
  local a, lane = ns.Style.arrival, subjectLane()
  for _, scale in ipairs(entry.from_scale_sweep or {}) do
    local crosses = ns.Paint.CrossesNeighbour(icon(), scale, pitch())
    local caption = ("%.2fx · %s"):format(scale, crosses and "reaches the neighbour" or "clear")
    local hosts, plays = arrivalRow(caption, function(host)
      local ring = ns.Paint.Ring(host, { rgb = lane.rgb, thickness_px = lane.thickness_px })
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
      rgb = lane.rgb, thickness_px = lane.thickness_px, relative = true,
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
    ns.Paint.Ring(host, { rgb = lane.rgb, thickness_px = lane.thickness_px })
    local fat = ns.Paint.Ring(host, {
      rgb = lane.rgb, thickness_px = ns.Paint.FatRing(lane.thickness_px, entry.fat_mult),
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
      rgb = lane.rgb, thickness_px = lane.thickness_px,
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

local function buildLab()
  local keys = labKeys()
  section("LAB · render-shelf.md Part 7 — no authority, decides nothing")
  if #keys == 0 then
    note("The lab is empty. That is its correct resting state, not a defect.")
    return {}
  end
  note("Experiments, drawn so they can be judged in the client. None of this is the style and " ..
       "none of it reaches a Cooldown Manager row. Read arrival-control-sweep first: it is the " ..
       "falsifier. An arrival row replays on click, rate limited to its own duration.")

  local badges = {}
  for _, key in ipairs(keys) do
    local entry = lab()[key]
    section("lab." .. key .. "  ·  " .. (entry.title or key))
    note(entry.asks or "no `asks` — Part 7 says an entry that cannot say what it is asking is " ..
                       "decoration")
    local draw = DRAWS[entry.draws]
    if draw then
      for _, badge in ipairs(draw(key, entry) or {}) do badges[#badges + 1] = badge end
    else
      note("nothing here knows how to draw `" .. tostring(entry.draws) .. "`.")
    end
  end
  return badges
end

local function build()
  if built then return built end
  container = CreateFrame("Frame", nil, ns.Frame.Get())
  container.badges = {}
  y = PAD

  text(container, "GameFontNormal", PAD, y, "render shelf v" .. tostring(ns.Style.version), 320)
  y = y + LABEL_H + 4

  buildLanes()
  buildMotion()
  for _, badge in ipairs(buildCues()) do container.badges[#container.badges + 1] = badge end
  for _, badge in ipairs(buildSlots()) do container.badges[#container.badges + 1] = badge end
  note("Every texture here is cap's own. Numbers come from Style.lua, generated from " ..
       "render-shelf.md Part 6.")

  for _, badge in ipairs(buildLab()) do container.badges[#container.badges + 1] = badge end

  container.height = y + PAD
  built = container
  return container
end

-- ---------------------------------------------------------------------------
-- Command
-- ---------------------------------------------------------------------------

local shown = false

local function hide()
  shown = false
  for _, badge in ipairs(container.badges) do badge:Hide() end
  ns.Frame.Detach(container)
  ns.Emit("style gallery closed.")
end

local function show()
  local c = build()
  -- The lab's arrival rows are the widest thing drawn: a subject, ISOLATION of clear space, then
  -- the neighbour stage.
  local n = (lab()._arrival_stage or {}).neighbours or 0
  ns.Frame.RequestWidth(math.max(icon() * 4 + SPREAD * 3,
                                 icon() * 2 + ISOLATION + 2 * n * pitch()) + PAD * 2)
  ns.Frame.Attach(c, c.height)
  c:Show()
  for _, badge in ipairs(c.badges) do badge:Show() end
  shown = true
  ns.Emit("style gallery open — /cap style again to close, /cap move to place it.")
end

ns.RegisterCommand{
  name = "style", order = 45, args = "",
  desc = "Show every render-shelf primitive on cap's own frame",
  handler = function()
    if shown then hide() else show() end
  end,
}
