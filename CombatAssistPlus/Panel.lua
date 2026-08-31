-- Panel.lua — V12's virtual rows: cap-owned icons for presses the Cooldown Manager has no frame
-- for. `Panel.Plan` is the pure seam, the way `Bars.Plan` is.
--
-- ⚠ THIS IS NOT `Frame.lua`'s `CombatAssistPlusPanel`. That is a draggable 220px box stacking
-- `Bars`' rows vertically; V12 declares a horizontal icon strip with its own anchor, size and
-- growth direction in `ns.Style.panel`. Two surfaces, two frames.
--
-- ⚠ ADDITIVE, ALWAYS. cap owns every frame here; the Cooldown Manager is neither written to nor
-- rearranged, which is why a virtual row engages none of `spec.md` §4's re-anchoring rules.
local ADDON, ns = ...

local issecretvalue = issecretvalue

ns.Panel = ns.Panel or {}
local Panel = ns.Panel

local stream = ns.Capture.Open("panel", { sessions = 8, cap = 500, dedup = false })

-- ---------------------------------------------------------------------------
-- The plan — pure
-- ---------------------------------------------------------------------------

--- One descriptor per virtual entry, in AUTHORED order, because the panel's left-to-right order
--- is the priority it declares — a standing terminus earns its silence by sitting at the end
--- (render-shelf.md V12), and sorting here would throw that away.
---
--- ⚠ A MISSING VERDICT DRAWS HATCHED, and it goes through `Treatment.For` rather than through a
--- literal, so the inverted-unknown rule has exactly one implementation. A verdict with no
--- `member` is not a member, and on a virtual row that is the hatch.
---
--- ⚠ `spellID` is the DECLARED BASE id and stays that way, because this function is pure. The
--- live face is a client read and is resolved on the draw, in `Panel.Face` — see the note there
--- for why a virtual row cannot say `identity` in its catalog at all.
function Panel.Plan(resolved, out)
  local plan = {}
  local byEntry = (out or {}).byEntry or {}
  local declared = (resolved or {}).declared or {}
  for _, item in ipairs((resolved or {}).virtual or {}) do
    local entry = item.entry
    local ability = declared[entry.ability]
    plan[#plan + 1] = {
      id = entry.id,
      kind = entry.virtual,
      ability = entry.ability,
      spellID = ability and ability.spell or nil,
      draw = ns.Treatment.For(byEntry[entry.id] or { virtual = entry.virtual }),
    }
  end
  return plan
end

--- `id:scan[+cue,cue]` or `id:off`, with a trailing `~` for the hatch — deliberately the same
--- grammar `Overlay` writes, so one reader parses both surfaces. On this surface the hatch is
--- the complement of the scan, so `off~` is the resting state rather than a second fact.
function Panel.Cell(desc)
  local d = desc.draw or {}
  local hatch = d.hatch and "~" or ""
  if not d.scan then return desc.id .. ":off" .. hatch end
  local s = desc.id .. ":scan"
  if #(d.cues or {}) > 0 then s = s .. "+" .. table.concat(d.cues, ",") end
  return s .. hatch
end

--- The spell whose ART this row should draw: the live override face where the client reports
--- one, else the declared base id.
---
--- ⚠ THIS IS THE ONE CLIENT READ ON THIS SURFACE AND IT IS DELIBERATELY NOT IN `Panel.Plan`.
--- `Plan` is the pure seam `Bars.Plan` is, so the read lives here, beside `artOf`, on the
--- impure side that is tested in the client. It is a TEXTURE and never a condition: nothing
--- branches on the answer, so a refusal costs the base art and nothing else.
---
--- ⚠ It exists because a virtual row may not declare its transform. `Catalog.Check` refuses any
--- subject predicate naming a virtual ability — the ability has no CDM row, so `identity` would
--- read UNKNOWN for life and, V12 inverting the unknown, hatch the row forever. Devourer's
--- Consume becomes Devour inside Void Metamorphosis and the catalog is silent about it by
--- construction; without this the standing row would draw Consume's icon through a whole window
--- in which the button is Devour.
---
--- Three guards, each a measured trap (`knowledge/addon-dev/cdm-rider-patterns.md` §3 and §5):
---   * a refused or SECRET return is "cap has no override", never an id;
---   * `~= 0` explicitly, because 0 is TRUTHY in Lua and 0 is how the client says "none";
---   * `~= spellID`, because an override equal to its input is not a transform.
function Panel.Face(spellID)
  if type(spellID) ~= "number" then return spellID end
  if not (C_Spell and C_Spell.GetOverrideSpell) then return spellID end
  local ok, override = pcall(C_Spell.GetOverrideSpell, spellID)
  if not ok or not ns.plain(override) then return spellID end
  if type(override) ~= "number" or override == 0 or override == spellID then return spellID end
  return override
end

local num = ns.num

function Panel.Render(snap)
  snap = snap or {}
  return "D{" .. table.concat({
    "n:" .. num(snap.entries), "icons:" .. num(snap.icons), "noart:" .. num(snap.noart),
  }, " ") .. "}"
    .. " P{" .. (#(snap.cells or {}) > 0 and table.concat(snap.cells, " ") or "-") .. "}"
end

-- ---------------------------------------------------------------------------
-- The frames
-- ---------------------------------------------------------------------------

local host
local pool = {}
local placedKey

--- cap's own strip, parented to `UIParent` at MEDIUM. MEDIUM is where UIParent, the action bars
--- and every opened panel live; a surface at HIGH covers the talent window at every frame level,
--- which `Overlay` learned the hard way. Nothing here anchors to a Cooldown Manager frame, so
--- there is no item level to lift off — the strip sits where the shelf puts it.
--- The virtual row's icon size, and it is the CDM ROW's — not a token of its own.
---
--- ⚠ WHY IT IS DERIVED. A virtual row takes part in the SAME left-to-right scan as the
--- Cooldown Manager's rows (`render-shelf.md` V12), and a scan is a row of peers: one peer at a
--- different size is a signal nothing in the cue vocabulary authorised. `panel.icon_px` used to
--- be authored beside `row.icon_px` and the two happened to agree at 50, so the mismatch was
--- invisible — until `row.icon_px` became the one knob a player turns, at which point Devourer's
--- Consume would have been the only entry in its scan drawn at the old size. Decided 2026-08-31.
local function panelIconPx()
  local row = ns.Style and ns.Style.row
  local px = type(row) == "table" and row.icon_px or nil
  -- Same guard as `Anchor.rowScale`: a hand-edited token can be a string, and `plain` answers
  -- secrecy rather than type. 50 is Blizzard's item template, the size a peer row draws at.
  if type(px) ~= "number" or px <= 0 then px = 50 end
  return px
end

local function container()
  if host then return host end
  local p, iconPx = ns.Style.panel, panelIconPx()
  host = CreateFrame("Frame", nil, UIParent)
  host:SetFrameStrata("MEDIUM")
  host:SetPoint(p.anchor, UIParent, p.anchor, p.x, p.y)
  host:SetSize(iconPx, iconPx)
  host:Hide()
  return host
end

--- Where the Nth icon sits: the strip EDGE the growth starts from, plus one step per index.
---
--- ⚠ The edge is derived from `grow`, never from `anchor`. `anchor` places the whole strip
--- against UIParent — the shelf's `BOTTOM` centres it — and hanging the icons off that same
--- point would grow the strip out of its own centre instead of filling it. A `grow` the shelf
--- does not declare runs RIGHT rather than stacking every icon on one spot.
local function slot(index)
  local p, iconPx = ns.Style.panel, panelIconPx()
  local step = (iconPx + p.gap_px) * index
  local grow = p.grow
  if grow == "LEFT" then return "RIGHT", -step, 0 end
  if grow == "UP" then return "BOTTOM", 0, step end
  if grow == "DOWN" then return "TOP", 0, -step end
  return "LEFT", step, 0
end

--- One icon: the spell art, V11's hatch (both causes), V13's scan edge, and a badge per cue.
--- Built out of combat or not at all — every widget here is cap's own, so nothing is restricted,
--- but the badge set is built once for the same reason `Overlay` builds it once.
local function build()
  local iconPx = panelIconPx()
  local f = CreateFrame("Frame", nil, container())
  f:SetSize(iconPx, iconPx)
  f:Hide()

  -- ⚠ NO SetTexCoord. Cropping the baked ring off a spell icon is the convention on an action
  -- button, and it is also a number — and the shelf declares none for this surface. An undeclared
  -- crop in Lua is exactly the divergence `render-shelf.md` exists to end, so the art is drawn
  -- whole until the shelf says otherwise.
  local art = f:CreateTexture(nil, "BACKGROUND")
  art:SetAllPoints(f)

  local icon = {
    frame = f, art = art,
    border = ns.Paint.Border(f),
    hatch = ns.Paint.Hatch(f),
    skip = ns.Paint.Hatch(f, nil, (ns.Style.hatch or {}).skip),
    badges = {},
  }
  for key in pairs(ns.Style.cues) do icon.badges[key] = ns.Paint.Badge(f, key) end
  return icon
end

--- The spell's own art, or nil. `GetSpellTexture` answers a FileDataID or a path and either is
--- fine for `SetTexture`; a refusal, a secret and an absent call are three different worlds and
--- all three end here as "cap has no art", which is drawn as a bare frame rather than guessed at.
local function artOf(spellID)
  if type(spellID) ~= "number" then return nil end
  if not (C_Spell and C_Spell.GetSpellTexture) then return nil end
  local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
  if not ok or texture == nil or issecretvalue(texture) then return nil end
  return texture
end

--- Every cue frame down. Called on each path that stops drawing an icon, so a hidden one cannot
--- leave a badge lit or stepping.
local function quiet(icon)
  icon.border:Hide()
  if icon.hatch then icon.hatch:Hide() end
  if icon.skip then icon.skip:Hide() end
  for _, badge in pairs(icon.badges) do badge:Hide() end
end

--- Re-place the strip only when the roster changes. The icons are cap's own frames, so this is
--- free — but the SIZE is what centres the strip under its anchor, and recomputing it every pass
--- would fight a player dragging nothing and cost a layout pass at 10 Hz.
local function relayout(plan)
  local ids = {}
  for _, desc in ipairs(plan) do ids[#ids + 1] = desc.id end
  local key = table.concat(ids, ",")
  if key == placedKey then return end
  placedKey = key

  local p, iconPx = ns.Style.panel, panelIconPx()
  local f = container()
  local n = #ids
  local span = n > 0 and (n * iconPx + (n - 1) * p.gap_px) or iconPx
  local vertical = p.grow == "UP" or p.grow == "DOWN"
  f:SetSize(vertical and iconPx or span, vertical and span or iconPx)

  -- Every pooled icon goes down first: an id the new roster does not carry keeps its frame
  -- (frames cannot be destroyed) and would otherwise stay lit at its old place forever.
  for _, icon in pairs(pool) do
    quiet(icon)
    icon.frame:Hide()
  end
  for i, id in ipairs(ids) do
    local icon = pool[id]
    if not icon then
      icon = build()
      pool[id] = icon
    end
    -- ⚠ `ClearAllPoints` first. `SetPoint` ADDS an anchor rather than replacing one, so a frame
    -- re-anchored without clearing keeps both and is stretched between them.
    icon.frame:ClearAllPoints()
    local point, x, y = slot(i - 1)
    icon.frame:SetPoint(point, f, point, x, y)
  end
end

--- Compose one icon: the art, the hatch, the scan edge, then the badge — the same order
--- `Overlay` composes a CDM row in, bottom to top, and the same Z-STACK: the corner is one
--- badge deep and `d.badges` says which one that is. A virtual row draws in cap's own panel
--- rather than on a Cooldown Manager item, and it must not read differently for it.
local function paint(icon, desc)
  local d = desc.draw or {}
  local texture = artOf(Panel.Face(desc.spellID))
  if texture ~= nil and icon.artSet ~= texture then
    icon.art:SetTexture(texture)
    icon.artSet = texture
  end
  icon.border:SetShown(d.scan == true)
  if icon.hatch then icon.hatch:SetShown(d.hatch == true) end
  if icon.skip then icon.skip:SetShown(d.skip == true) end

  local badges = d.badges or {}
  for key, badge in pairs(icon.badges) do
    if badges[key] then
      local cue = ns.Style.cues[key] or {}
      ns.Paint.LevelAbove(badge.frame, icon.frame, ns.Paint.CueLevel(cue.polarity, cue.rank))
      badge:SetPoint("TOPRIGHT", icon.frame, "TOPRIGHT", ns.Paint.StackOffset(icon.frame, 0))
      badge.frame:SetAlpha(1)
      badge:Show()
    else
      badge:Hide()
    end
  end
  return texture ~= nil
end

local lastBody
local function write(body, edge)
  if not edge and body == lastBody then return end
  local text = ("t%.1f "):format(GetTime()) .. (edge and ("# " .. edge .. " ") or "") .. body
  if edge then stream:Mark(text) else stream:Line(text) end
  if not ns.db then return end
  lastBody = body
  stream:Meta("version", ns.version)
end

--- cap has stopped drawing, or this build declares no virtual rows. The strip goes down whole:
--- an empty panel must not leave one icon from the last roster lit over nothing.
local function dark(edge)
  for _, icon in pairs(pool) do
    quiet(icon)
    icon.frame:Hide()
  end
  if host then host:Hide() end
  placedKey = nil
  write(Panel.Render{ entries = 0, icons = 0, noart = 0 }, edge)
end

local function draw(out, bound, edge)
  if not (out and bound) then return dark(edge) end
  local plan = Panel.Plan(bound, out)
  if #plan == 0 then return dark(edge) end
  relayout(plan)

  local cells, icons, noart = {}, 0, 0
  for _, desc in ipairs(plan) do
    local icon = pool[desc.id]
    if icon then
      if paint(icon, desc) then icons = icons + 1 else noart = noart + 1 end
      icon.frame:Show()
    end
    cells[#cells + 1] = Panel.Cell(desc)
  end
  container():Show()
  write(Panel.Render{ entries = #plan, icons = icons, noart = noart, cells = cells }, edge)
end

ns.Sense.OnVerdicts(draw)
