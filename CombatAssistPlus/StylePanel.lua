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
  section("V2 · arrival snap  ·  V4 · veil  ·  V7 · swipe")
  local x = PAD

  local host = swatch(x, y, SAMPLE[1].spell, "click to fire")
  local border = ns.Paint.Border(host, "COOLDOWN")
  host:EnableMouse(true)
  host:SetScript("OnMouseUp", function() border:Snap() end)
  border:Snap()
  x = x + icon() + SPREAD

  local veiled = swatch(x, y, SAMPLE[2].spell, "veil")
  ns.Paint.Border(veiled, "ROTATION")
  ns.Paint.Veil(veiled):Show()
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
  ns.Frame.RequestWidth(icon() * 4 + SPREAD * 3 + PAD * 2)
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
