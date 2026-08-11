-- Overlay.lua — static addon-owned emphasis and readable context dots on CDM rows.
-- No animation and no stock-proc suppression: the first flight tests coexistence.
local ADDON, ns = ...

local issecretvalue = issecretvalue
local PAD, DOT = 2, 7

ns.Overlay = ns.Overlay or {}
local Overlay = ns.Overlay
local stream = ns.Capture.Open("draw", { sessions = 8, cap = 2000, dedup = false })
local pool = {}
local state = { bound = nil, order = {}, rowOf = {}, dark = false }

local function buildRing(host)
  local parts = {}
  local thickness = ns.Treatment.EMPHASIS.thickness
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

local function buildDot(host, id)
  local d = ns.Treatment.Marker(id)
  local t = host:CreateTexture(nil, "OVERLAY", nil, 2)
  t:SetColorTexture(d.r, d.g, d.b, d.a)
  t:SetSize(DOT, DOT)
  t:SetPoint(d.slot == "left" and "BOTTOMLEFT" or "BOTTOMRIGHT", host,
    d.slot == "left" and "BOTTOMLEFT" or "BOTTOMRIGHT", 0, 0)
  t:Hide()
  return t
end

local function acquire(cid)
  local f = pool[cid]
  if f then return f end
  f = CreateFrame("Frame", nil, UIParent)
  f:Hide()
  f.ring = buildRing(f)
  f.markers = {
    dreadstalkers = buildDot(f, "dreadstalkers"),
    grimoire = buildDot(f, "grimoire"),
  }
  pool[cid] = f
  return f
end

local function layer(f)
  if f.layered or InCombatLockdown() then return end
  f:SetFrameStrata("HIGH")
  f:SetFrameLevel(4)
  f.layered = true
end

local function anchor(f, cid)
  local item, confirmed = ns.Bind.ItemFrame(cid)
  if not item then f.anchoredTo = nil; return nil, false end
  if f.anchoredTo ~= item then
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", item, "TOPLEFT", -PAD, PAD)
    f:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", PAD, -PAD)
    f.anchoredTo = item
  end
  return item, confirmed
end

local function itemShown(item)
  local ok, shown = pcall(item.IsVisible, item)
  if not ok or shown == nil or issecretvalue(shown) then return true end
  return shown and true or false
end

local function paint(f, verdict)
  local d = ns.Treatment.For(verdict)
  local ring = d.ring
  for _, t in ipairs(f.ring) do
    if ring then
      t:SetVertexColor(ring.r, ring.g, ring.b)
      t:SetAlpha(ring.a)
      t:Show()
    else
      t:Hide()
    end
  end
  local shown = {}
  for _, id in ipairs(verdict.markers or {}) do shown[id] = true end
  for id, t in pairs(f.markers) do if shown[id] then t:Show() else t:Hide() end end
end

local function num(v)
  if v == nil or issecretvalue(v) or type(v) ~= "number" then return "?" end
  return tostring(math.floor(v))
end

function Overlay.Render(snap)
  snap = snap or {}
  local d = {
    "n:" .. num(snap.entries), "rows:" .. num(snap.rows),
    "anch:" .. num(snap.anchored), "conf:" .. num(snap.confirmed),
    "off:" .. num(snap.hidden), "nf:" .. num(snap.noframe),
    "bar:" .. (snap.bar or "-"), "stock:coexist",
  }
  return "D{" .. table.concat(d, " ") .. "}"
    .. " P{" .. (#(snap.cells or {}) > 0 and table.concat(snap.cells, " ") or "-") .. "}"
    .. " M{" .. (#(snap.marks or {}) > 0 and table.concat(snap.marks, " ") or "-") .. "}"
    .. " B{" .. (#(snap.bars or {}) > 0 and table.concat(snap.bars, " ") or "-") .. "}"
end

local lastBody, lines
lines = 0
local function write(body, edge)
  if not edge and body == lastBody then return end
  local text = ("t%.1f "):format(GetTime()) .. (edge and ("# " .. edge .. " ") or "") .. body
  if edge then stream:Mark(text) else stream:Line(text) end
  if not ns.db then return end
  lastBody, lines = body, lines + 1
  stream:Meta("catalog", ns.Sense.CatalogName() or "-")
  stream:Meta("version", ns.version)
  stream:Meta("lines", lines)
end

local function barReport()
  if not ns.Bars then return nil, nil end
  return ns.Bars.Report()
end

local function hideAll(edge)
  for _, f in pairs(pool) do f:Hide() end
  local bars, bar = barReport()
  write(Overlay.Render{ entries = 0, rows = 0, anchored = 0, confirmed = 0,
    hidden = 0, noframe = 0, bars = bars, bar = bar }, edge)
end

local function rebuild(bound)
  state.bound, state.order, state.rowOf = bound, {}, {}
  local live = {}
  for _, item in ipairs(bound.entries or {}) do
    state.order[#state.order + 1] = item.entry.id
    state.rowOf[item.entry.id] = item.row.cooldownID
    live[item.row.cooldownID] = true
  end
  table.sort(state.order)
  for cid, f in pairs(pool) do if not live[cid] then f:Hide() end end
end

local function draw(out, bound, edge)
  if not (out and bound) then state.bound = nil; hideAll(edge); return end
  if bound ~= state.bound then rebuild(bound) end

  local rows, anchored, confirmed, hidden, noframe = 0, 0, 0, 0, 0
  local cells, marks = {}, {}
  for _, id in ipairs(state.order) do
    local verdict = out.byEntry[id]
    local cid = state.rowOf[id]
    local f = acquire(cid)
    layer(f)
    local item, ok = anchor(f, cid)
    rows = rows + 1
    if not item then
      noframe = noframe + 1
      f:Hide()
      cells[#cells + 1] = id .. ":noframe"
    elseif not itemShown(item) then
      anchored = anchored + 1
      if ok then confirmed = confirmed + 1 end
      hidden = hidden + 1
      f:Hide()
      cells[#cells + 1] = id .. ":hidden"
    else
      anchored = anchored + 1
      if ok then confirmed = confirmed + 1 end
      paint(f, verdict)
      f:Show()
      cells[#cells + 1] = id .. ":" .. (verdict.emphasized and "on" or "off")
      for _, marker in ipairs(verdict.markers or {}) do marks[#marks + 1] = id .. ":" .. marker end
    end
  end
  local bars, bar = barReport()
  write(Overlay.Render{ entries = #state.order, rows = rows, anchored = anchored,
    confirmed = confirmed, hidden = hidden, noframe = noframe,
    cells = cells, marks = marks, bars = bars, bar = bar }, edge)
end

ns.Sense.OnVerdicts(draw)
