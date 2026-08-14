-- Overlay.lua — addon-owned lane borders on CDM rows, drawn through ns.Paint.
-- No stock-proc suppression: the first flight tests coexistence.
local ADDON, ns = ...

local issecretvalue = issecretvalue
local PAD = 2

ns.Overlay = ns.Overlay or {}
local Overlay = ns.Overlay
local stream = ns.Capture.Open("draw", { sessions = 8, cap = 2000, dedup = false })
local pool = {}
local state = { bound = nil, order = {}, rowOf = {}, itemOf = {}, dark = false }

local function acquire(cid)
  local f = pool[cid]
  if f then return f end
  f = CreateFrame("Frame", nil, UIParent)
  f:Hide()
  f.border = ns.Paint.Border(f)
  f.channels, f.channelStatus = {}, {}
  pool[cid] = f
  return f
end

local function configure(f, item, declared)
  for _, container in pairs(f.channels) do container:Hide() end
  f.channelStatus = {}
  for _, marker in ipairs(item.entry.markers or {}) do
    -- A readable marker is still evaluated and still reported; the shelf's cue vocabulary has
    -- no drawn form for the two ad-hoc Warlock ones, so nothing is drawn for it.
    if not marker.when then
      local plan = ns.Channel.Plan(marker, declared)
      local key = plan and (marker.id .. "/" .. plan.spell) or marker.id
      local container = f.channels[key]
      local status
      if container then
        container:Show()
        status = "armed"
      elseif not InCombatLockdown() then
        container, status = ns.Channel.Arm(f, marker, declared)
        if container then f.channels[key] = container end
      else
        status = "refused"
      end
      f.channelStatus[marker.id] = status or "refused"
    end
  end
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
  if d.lane then f.border:SetLane(d.lane) else f.border:Hide() end
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
    .. " C{" .. (#(snap.channels or {}) > 0 and table.concat(snap.channels, " ") or "-") .. "}"
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
  state.bound, state.order, state.rowOf, state.itemOf = bound, {}, {}, {}
  local live = {}
  for _, item in ipairs(bound.entries or {}) do
    state.order[#state.order + 1] = item.entry.id
    state.rowOf[item.entry.id] = item.row.cooldownID
    state.itemOf[item.entry.id] = item
    live[item.row.cooldownID] = true
  end
  table.sort(state.order)
  for cid, f in pairs(pool) do if not live[cid] then f:Hide() end end
  for _, id in ipairs(state.order) do
    local item = state.itemOf[id]
    configure(acquire(item.row.cooldownID), item, bound.declared)
  end
end

local function draw(out, bound, edge)
  if not (out and bound) then state.bound = nil; hideAll(edge); return end
  if bound ~= state.bound then rebuild(bound) end

  local rows, anchored, confirmed, hidden, noframe = 0, 0, 0, 0, 0
  local cells, marks, channels = {}, {}, {}
  for _, id in ipairs(state.order) do
    local verdict = out.byEntry[id]
    local cid = state.rowOf[id]
    local f = acquire(cid)
    -- A combat-time acquisition refusal gets one honest retry after restriction lifts.
    for _, status in pairs(f.channelStatus) do
      if status == "refused" and not InCombatLockdown() then
        configure(f, state.itemOf[id], bound.declared)
        break
      end
    end
    for marker, status in pairs(f.channelStatus) do
      channels[#channels + 1] = id .. ":" .. marker .. ":" .. status
    end
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
      cells[#cells + 1] = id .. ":" .. (verdict.tier or "off")
      for _, marker in ipairs(verdict.markers or {}) do marks[#marks + 1] = id .. ":" .. marker end
    end
  end
  table.sort(channels)
  local bars, bar = barReport()
  write(Overlay.Render{ entries = #state.order, rows = rows, anchored = anchored,
    confirmed = confirmed, hidden = hidden, noframe = noframe,
    cells = cells, marks = marks, channels = channels, bars = bars, bar = bar }, edge)
end

ns.Sense.OnVerdicts(draw)
