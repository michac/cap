-- Anchor.lua — draws the Essential viewer's rows in the catalog's authored order.
--
-- The reading model asks you to scan left to right and press the first item that is not
-- ruled out, which only means anything if left-to-right IS the priority order. Blizzard
-- orders the row by the player's saved Cooldown Manager layout, so without this the scan
-- direction carries no information.
--
-- It re-anchors, and only re-anchors. `layoutIndex` is both the grid sort key and the
-- cooldownID data index, so rewriting it swaps the icons AND their contents and the row
-- looks unchanged; the positional move is ClearAllPoints() + SetPoint() with the index
-- left alone. Nothing here writes the player's saved layout, and a row the player has not
-- configured stays absent — this reorders what is already shown and adds nothing to it.
--
-- Reads drawn position with GetLeft/GetTop rather than through Bind or Catalog.OrderCheck,
-- which both sort by layoutIndex and therefore cannot see a SetPoint re-anchor at all.
local ADDON, ns = ...

local issecretvalue = issecretvalue

ns.Anchor = ns.Anchor or {}
local Anchor = ns.Anchor

local VIEWER = "EssentialCooldownViewer"
local SAMPLE = 0.5
local TOLERANCE = 0.5
-- A displacement this soon after one of our own hooks fired is Blizzard's layout engine;
-- anything later had no observed cause and is reported as contention instead.
local ATTRIBUTION_WINDOW = 1.0
local DEFAULT_GAP = 4
-- The viewer builds its frames on its own schedule, so the first arm waits rather than
-- racing it. A failed arm retries on the next event anyway; this only avoids the noise.
local SETTLE = 1.0

local stream = ns.Capture.Open("anchor", { sessions = 8, cap = 2000, dedup = false })

-- ---------------------------------------------------------------------------
-- Pure: the plan
-- ---------------------------------------------------------------------------

--- The authored order mapped onto live rows. `entries` is an ordered array of
--- `{ id, cooldownID }`; a nil or unmatched cooldownID is skipped and reported rather
--- than shifting the rest. Rows the catalog does not name keep their relative order and
--- follow the named ones.
function Anchor.Plan(rows, entries)
  local byID, seen = {}, {}
  for _, row in ipairs(rows or {}) do
    if row.cooldownID ~= nil and byID[row.cooldownID] == nil then byID[row.cooldownID] = row end
  end

  local order, missing = {}, {}
  for _, entry in ipairs(entries or {}) do
    local row = entry.cooldownID ~= nil and byID[entry.cooldownID] or nil
    if row and not seen[row] then
      seen[row] = true
      order[#order + 1] = { cooldownID = entry.cooldownID, row = row, entry = entry.id }
    else
      missing[#missing + 1] = entry.id
    end
  end

  local named = #order
  for _, row in ipairs(rows or {}) do
    if not seen[row] and row.cooldownID ~= nil then
      seen[row] = true
      order[#order + 1] = { cooldownID = row.cooldownID, row = row }
    end
  end

  return { order = order, named = named, extra = #order - named, missing = missing }
end

-- ---------------------------------------------------------------------------
-- Pure: the line body, and the dedup key
-- ---------------------------------------------------------------------------

local function num(v)
  if v == nil or issecretvalue(v) or type(v) ~= "number" then return "?" end
  return tostring(math.floor(v))
end

local function list(ids)
  if not ids or #ids == 0 then return "-" end
  local out = {}
  for i = 1, #ids do out[i] = num(ids[i]) end
  return table.concat(out, ",")
end

--- No frames, no clock, no game reads: every field rides the snapshot the caller built.
function Anchor.Render(snap)
  snap = snap or {}
  local a = {
    "n:" .. num(snap.n), "named:" .. num(snap.named),
    "extra:" .. num(snap.extra), "miss:" .. num(snap.missing),
  }
  local s = {
    "stomp:" .. num(snap.stomps), "icombat:" .. num(snap.stompsCombat),
    "disp:" .. num(snap.displaced), "cont:" .. num(snap.contended),
  }
  return "A{" .. table.concat(a, " ") .. "}"
    .. " P{" .. list(snap.planned) .. "}"
    .. " D{" .. list(snap.drawn) .. "}"
    .. " X{" .. (snap.match and "ok" or "MISMATCH") .. "}"
    .. " S{" .. table.concat(s, " ") .. "}"
end

-- ---------------------------------------------------------------------------
-- Pure: what a viewer census means
-- ---------------------------------------------------------------------------

--- Classifies an arm attempt. The two failures are different problems and only one is
--- cap's business: a viewer that is absent or empty is something to tell the player
--- about, while a catalog entry with no row is NORMAL — the Cooldown Manager only makes
--- rows for abilities it tracks, so an entry for an ability with no cooldown never binds
--- and would otherwise complain on every login.
function Anchor.Diagnose(census)
  census = census or {}
  if not census.exists then
    return "no-viewer", VIEWER .. " does not exist — cap cannot order a row it cannot find."
  end
  if (census.rows or 0) == 0 then
    return "no-rows", "the " .. VIEWER .. " is empty — nothing to order. Add abilities to it "
      .. "in the Cooldown Manager, or check that it is enabled."
  end
  return "ok", nil
end

-- ---------------------------------------------------------------------------
-- Session state
-- ---------------------------------------------------------------------------

local P = {
  armed = false,
  combat = false,
  plan = nil,
  tracked = {},
  expected = {},
  planned = {},
  stomps = 0,
  stompsCombat = 0,
  displaced = 0,
  contended = 0,
  lastCauseAt = nil,
  dirty = false,
  warned = false,
  pending = false,
  anchor = nil,
  ticker = nil,
  hooked = false,
  told = nil,
}

local function bit(v) return v and "1" or "0" end

local function plain(v)
  return v ~= nil and not issecretvalue(v)
end

-- File scope runs before ADDON_LOADED, so the scratch carries the shape until ns.db
-- exists — the same reason, and the same shape, as Mode.lua's.
local scratch = {}
local function store()
  local root = ns.db or scratch
  if root.anchor == nil then root.anchor = true end
  return root
end

function Anchor.Enabled()
  return store().anchor and true or false
end

local function viewer()
  return _G[VIEWER]
end

local function geometry(frame)
  local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
  if not ok or not (plain(left) and plain(top)) then return nil end
  return left, top
end

-- ---------------------------------------------------------------------------
-- Writing
-- ---------------------------------------------------------------------------

local function snapshot(drawn, match)
  return {
    n = P.plan and #P.plan.order or 0,
    named = P.plan and P.plan.named or 0,
    extra = P.plan and P.plan.extra or 0,
    missing = P.plan and #P.plan.missing or 0,
    planned = P.planned,
    drawn = drawn,
    match = match,
    stomps = P.stomps,
    stompsCombat = P.stompsCombat,
    displaced = P.displaced,
    contended = P.contended,
  }
end

-- A write before `ns.db` exists is dropped silently, so it must not move the dedup
-- baseline — the first line that could land would be swallowed as a duplicate.
local lastBody

local function write(body, edge)
  if not ns.db then return end
  local text = ("t%.1f "):format(GetTime()) .. (edge and (edge .. " ") or "") .. body
  if edge then stream:Mark(text) else
    if body == lastBody then return end
    stream:Line(text)
  end
  lastBody = body
end

local function mark(edge)
  local drawn, match = Anchor.Drawn()
  write(Anchor.Render(snapshot(drawn, match)), edge)
end

local function stampMeta()
  stream:Meta("version", ns.version)
  stream:Meta("viewer", VIEWER)
  stream:Meta("catalog", (ns.Sense and ns.Sense.CatalogName()) or "-")
  stream:Meta("rows", P.plan and #P.plan.order or 0)
  stream:Meta("intended", list(P.planned))
  stream:Meta("contended", P.contended)
end

-- Said once per reason per session: a condition that holds forever would otherwise
-- reprint on every event that retries the arm.
local function tell(reason, message)
  if P.told == reason then return end
  P.told = reason
  ns.Emit(message)
end

-- ---------------------------------------------------------------------------
-- Reading the drawn order — the measurement the existing instruments cannot make
-- ---------------------------------------------------------------------------

--- Tracked cooldownIDs sorted by drawn left edge, plus whether that agrees with the plan.
function Anchor.Drawn()
  local seen = {}
  for _, t in ipairs(P.tracked) do
    local left = geometry(t.frame)
    if left then seen[#seen + 1] = { cooldownID = t.cooldownID, left = left } end
  end
  table.sort(seen, function(a, b)
    if a.left ~= b.left then return a.left < b.left end
    return a.cooldownID < b.cooldownID
  end)
  local drawn, match = {}, #seen == #P.planned
  for i = 1, #seen do
    drawn[i] = seen[i].cooldownID
    if drawn[i] ~= P.planned[i] then match = false end
  end
  return drawn, match
end

-- ---------------------------------------------------------------------------
-- Applying
-- ---------------------------------------------------------------------------

local function ensureAnchor()
  if P.anchor then return P.anchor end
  P.anchor = CreateFrame("Frame", nil, UIParent)
  P.anchor:SetSize(1, 1)
  return P.anchor
end

-- Read off the frames before any of them move, so the re-anchored row keeps the CDM's own
-- metrics: origin is the drawn row's top-left corner and the gap is its narrowest column
-- spacing. Scale is matched to the item frames so a SetPoint offset means the same distance
-- in both coordinate spaces.
local function metrics(frames)
  local w = frames[1]:GetWidth()
  if not plain(w) then return nil end
  local lefts, left, top = {}, nil, nil
  for _, frame in ipairs(frames) do
    local l, t = geometry(frame)
    if l then
      lefts[#lefts + 1] = l
      if left == nil or l < left then left = l end
      if top == nil or t > top then top = t end
    end
  end
  if left == nil then return nil end
  table.sort(lefts)
  local gap = DEFAULT_GAP
  for i = 2, #lefts do
    local delta = lefts[i] - lefts[i - 1] - w
    if delta > 0 and delta < gap then gap = delta end
  end
  return w, gap, left, top
end

local function apply(why)
  if InCombatLockdown() or not P.armed or not P.plan then return false end
  local frames = {}
  for _, t in ipairs(P.tracked) do frames[#frames + 1] = t.frame end
  if #frames == 0 then return false end

  local w, gap, left, top = metrics(frames)
  if not w then return false end

  local pitch = w + gap
  local anchor = ensureAnchor()
  local mine, theirs = frames[1]:GetEffectiveScale(), UIParent:GetEffectiveScale()
  if plain(mine) and plain(theirs) and theirs ~= 0 then anchor:SetScale(mine / theirs) end
  anchor:ClearAllPoints()
  anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

  P.expected = {}
  for i, t in ipairs(P.tracked) do
    local x = (i - 1) * pitch
    t.frame:ClearAllPoints()
    t.frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, 0)
    P.expected[t.cooldownID] = { left = left + x, top = top }
  end
  P.dirty = false
  mark("# reapply why=" .. why)
  stampMeta()
  return true
end

-- One pass per burst: a spec swap raises several of these events back to back, and each
-- one would otherwise re-measure a layout that is still in flight.
local function schedule(why)
  if not P.armed or P.pending then return end
  P.pending = true
  C_Timer.After(0, function()
    P.pending = false
    apply(why)
  end)
end

-- ---------------------------------------------------------------------------
-- The sampler
-- ---------------------------------------------------------------------------

local function sample()
  if not P.armed then return end
  local moved = 0
  for _, t in ipairs(P.tracked) do
    local want = P.expected[t.cooldownID]
    local left, top = geometry(t.frame)
    if want and left then
      if math.abs(left - want.left) > TOLERANCE or math.abs(top - want.top) > TOLERANCE then
        moved = moved + 1
      end
    end
  end
  -- One mark per displacement, not one per tick: in combat cap cannot re-place the frames,
  -- so an unlatched sampler would repeat the same finding twice a second for the whole pull.
  if moved == 0 then P.dirty = false; return end
  if P.dirty then return end
  P.dirty = true

  local attributed = P.lastCauseAt and (GetTime() - P.lastCauseAt) <= ATTRIBUTION_WINDOW
  if attributed then
    P.displaced = P.displaced + 1
    mark(("# displaced n=%d combat=%s"):format(moved, bit(P.combat)))
  else
    P.contended = P.contended + 1
    mark(("# contended n=%d combat=%s"):format(moved, bit(P.combat)))
    -- Backing off rather than re-asserting: another addon that re-anchors these frames
    -- wins every round anyway, and a fight between two riders at 2 Hz is worse for the
    -- player than one of them losing quietly. Say it once, then leave the row alone.
    if not P.warned then
      P.warned = true
      ns.Emit("another addon is moving the Cooldown Manager's icons, so cap cannot order "
        .. "them — the row's left-to-right order is not cap's and should not be read as a "
        .. "priority. Disable that addon's Cooldown Manager module, or /cap anchor off.")
    end
    return
  end
  -- Re-assert only out of combat: the layout teardown reaches combat, where a re-anchor
  -- is not available to us, and the row recovers on the next out-of-combat pass.
  if not InCombatLockdown() then schedule("displaced") end
end

-- ---------------------------------------------------------------------------
-- Hooks — installed once ever, so every callback is gated on `armed`
-- ---------------------------------------------------------------------------

local function onStomp(source, destructive)
  if not P.armed then return end
  P.stomps = P.stomps + 1
  P.lastCauseAt = GetTime()
  if P.combat then P.stompsCombat = P.stompsCombat + 1 end
  mark(("# stomp %s destructive=%s combat=%s"):format(source, bit(destructive), bit(P.combat)))
  if destructive then P.expected = {} end
  schedule(source)
end

local function installHooks()
  if P.hooked then return end
  local v = viewer()
  if not v then return end
  P.hooked = true
  hooksecurefunc(v, "RefreshLayout", function() onStomp("RefreshLayout", true) end)
  hooksecurefunc(v, "Layout", function() onStomp("Layout", false) end)
  if EventRegistry then
    EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
      if P.armed then schedule("settings") end
    end, Anchor)
  end
end

-- ---------------------------------------------------------------------------
-- Arming
-- ---------------------------------------------------------------------------

local function specAndHero()
  local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
  local specID
  if getSpec then
    local okIndex, index = pcall(getSpec)
    if okIndex and plain(index) then
      local getID = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo)
        or GetSpecializationInfo
      if getID then
        local okInfo, id = pcall(getID, index)
        if okInfo and plain(id) then specID = id end
      end
    end
  end
  local hero
  local talents = C_ClassTalents
  if talents and talents.GetActiveHeroTalentSpec then
    local ok, subTreeID = pcall(talents.GetActiveHeroTalentSpec)
    if ok and plain(subTreeID) then hero = subTreeID end
  end
  return specID, hero
end

local function viewerRows()
  local out = {}
  for _, row in ipairs(ns.Bind.Rows()) do
    if row.viewer == VIEWER and row.frame then out[#out + 1] = row end
  end
  return out
end

--- The authored entry order as `{ id, cooldownID }`, which is all `Plan` needs.
local function authored(rows)
  local cat = ns.Catalog.ForBuild(specAndHero())
  if not cat then return {}, nil end
  local resolved = ns.Catalog.Resolve(cat, rows)
  local entries = {}
  for _, entry in ipairs(cat.entries or {}) do
    local row = resolved.byEntry[entry.id]
    entries[#entries + 1] = { id = entry.id, cooldownID = row and row.cooldownID or nil }
  end
  return entries, cat
end

--- What the four viewers currently hold, as plain numbers `Diagnose` can judge.
function Anchor.Census()
  local v = viewer()
  if not v then return { exists = false, rows = 0 } end
  return { exists = true, rows = #viewerRows() }
end

local function disarm()
  P.armed = false
  if P.ticker then P.ticker:Cancel(); P.ticker = nil end
  local orphans = 0
  for _, t in ipairs(P.tracked) do t.frame:ClearAllPoints() end
  local v = viewer()
  if v and type(v.Layout) == "function" then pcall(v.Layout, v) end
  for _, t in ipairs(P.tracked) do
    local ok, points = pcall(t.frame.GetNumPoints, t.frame)
    if not ok or not plain(points) or points == 0 then orphans = orphans + 1 end
  end
  mark("# restored orphans=" .. orphans)
  P.tracked, P.expected, P.planned, P.plan = {}, {}, {}, nil
  return orphans
end

--- Returns ok, reason. `reason` is nil on success and on a silent retry-later.
local function arm()
  local status, message = Anchor.Diagnose(Anchor.Census())
  if status ~= "ok" then
    tell(status, message)
    return false, status
  end

  local rows = viewerRows()
  local entries, cat = authored(rows)
  if not cat then
    tell("no-catalog", "no catalog for this spec and hero tree, so cap has no order to "
      .. "impose — the row keeps Blizzard's.")
    return false, "no-catalog"
  end

  P.plan = Anchor.Plan(rows, entries)
  P.tracked, P.planned = {}, {}
  for i, item in ipairs(P.plan.order) do
    P.tracked[i] = { cooldownID = item.cooldownID, frame = item.row.frame }
    P.planned[i] = item.cooldownID
  end
  P.armed = true
  P.warned = false
  installHooks()
  mark("# armed")
  stampMeta()
  if not apply("armed") then
    P.armed = false
    tell("no-geometry", "could not read the Cooldown Manager's geometry — the row keeps "
      .. "Blizzard's order.")
    return false, "no-geometry"
  end
  P.told = nil
  if not P.ticker then P.ticker = C_Timer.NewTicker(SAMPLE, sample) end
  return true, nil
end

--- Arms if enabled and not already armed; re-applies if it is. Every caller is an event.
local function refresh()
  if not Anchor.Enabled() then return end
  if InCombatLockdown() then return end
  if P.armed then schedule("event") else arm() end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
  "PLAYER_ENTERING_WORLD",
  "SPELLS_CHANGED",
  "TRAIT_CONFIG_UPDATED",
  "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
  "ACTIVE_COMBAT_CONFIG_CHANGED",
  "ACTIVE_TALENT_GROUP_CHANGED",
  "PLAYER_EQUIPMENT_CHANGED",
  "COOLDOWN_VIEWER_TABLE_HOTFIXED",
}) do
  events:RegisterEvent(event)
end

-- ⚠ Combat comes from the event edge, never InCombatLockdown() inside a handler, so a
-- recorded combat flag never depends on when the lockdown flag clears.
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    P.combat = true
    if P.armed then mark("# combat start") end
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    P.combat = false
    if P.armed then mark("# combat end") end
  end
  if event == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(SETTLE, refresh)
    return
  end
  refresh()
end)

-- ---------------------------------------------------------------------------
-- The command
-- ---------------------------------------------------------------------------

local function statusLine()
  if not P.armed then
    ns.Emit("ordering is " .. (Anchor.Enabled() and "on but not applied" or "off") .. ".")
    local _, message = Anchor.Diagnose(Anchor.Census())
    if message then ns.Emit("  " .. message) end
    return
  end
  local drawn, match = Anchor.Drawn()
  ns.Emit(("ordering %d rows on %s — drawn order %s the authored one."):format(
    #drawn, VIEWER, match and "matches" or "DIFFERS from"))
  ns.Emit(("layout rebuilds %d (%d in combat), displaced %d, contended %d%s."):format(
    P.stomps, P.stompsCombat, P.displaced, P.contended,
    P.contended > 0 and " — another addon is moving these frames" or ""))
end

local function rowsLine()
  local rows = viewerRows()
  local entries, cat = authored(rows)
  if not cat then ns.Emit("no catalog for this spec and hero tree."); return end
  ns.Emit(("catalog %s: %d of %d entries have a Cooldown Manager row."):format(
    cat.name or "?", Anchor.Plan(rows, entries).named, #entries))
  -- Listed, not warned about: the Cooldown Manager only makes rows for what it tracks, so
  -- an ability with no cooldown never gets one and that is not a fault to report.
  for _, id in ipairs(Anchor.Plan(rows, entries).missing) do ns.Emit("  no row: " .. id) end
  for _, name in ipairs({
    VIEWER, "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer",
  }) do
    local v = _G[name]
    local active = "absent"
    if v then
      local ok, frames = pcall(v.GetItemFrames, v)
      if ok and type(frames) == "table" then active = #frames .. " frames" end
    end
    ns.Emit(("  %s: %s"):format(name, active))
  end
end

local function set(on)
  store().anchor = on and true or false
  if on then
    P.told = nil
    if not P.armed then arm() end
    ns.Emit("ordering on.")
  else
    if P.armed then disarm() end
    ns.Emit("ordering off — the row keeps Blizzard's order.")
  end
end

local actions = {
  [""] = statusLine,
  status = statusLine,
  rows = rowsLine,
  on = function() set(true) end,
  off = function() set(false) end,
}

ns.RegisterCommand{
  name = "anchor", order = 35, args = "[on|off|rows]",
  desc = "Draw the Cooldown Manager row in the catalog's priority order",
  handler = function(rest)
    local verb = (rest or ""):lower()
    local action = actions[verb]
    if not action then
      ns.Emit("usage: /cap anchor  or  /cap anchor on|off|rows")
      return
    end
    if (verb == "on" or verb == "off") and InCombatLockdown() then
      ns.Emit("out of combat only.")
      return
    end
    action()
  end,
}
