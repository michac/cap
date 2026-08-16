--@probe
-- question:  can cap re-anchor the Essential viewer's item frames into the authored
--            order out of combat, and do those positions persist through combat?
-- opened:    2026-08-16
-- expires:   2026-08-30
-- lands-in:  knowledge/addon-dev/cooldown-manager.md
--@endprobe
--
-- Reads drawn position with GetLeft/GetTop rather than through Bind or Catalog.OrderCheck,
-- which both sort by layoutIndex and therefore cannot see a SetPoint re-anchor at all.
local ADDON, ns = ...

local issecretvalue = issecretvalue

ns.AnchorOrder = ns.AnchorOrder or {}
local AnchorOrder = ns.AnchorOrder

local VIEWER = "EssentialCooldownViewer"
local SAMPLE = 0.5
local TOLERANCE = 0.5
-- A displacement this soon after one of our own hooks fired is Blizzard's layout engine;
-- anything later had no observed cause and is reported as contention instead.
local ATTRIBUTION_WINDOW = 1.0
local DEFAULT_GAP = 4

local stream = ns.Capture.Open("anchor", { sessions = 8, cap = 2000, dedup = false })

-- ---------------------------------------------------------------------------
-- Pure: the plan
-- ---------------------------------------------------------------------------

--- The authored order mapped onto live rows. `entries` is an ordered array of
--- `{ id, cooldownID }`; a nil or unmatched cooldownID is skipped and reported rather
--- than shifting the rest. Rows the catalog does not name keep their relative order and
--- follow the named ones.
function AnchorOrder.Plan(rows, entries)
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
function AnchorOrder.Render(snap)
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
}

local function bit(v) return v and "1" or "0" end

local function plain(v)
  return v ~= nil and not issecretvalue(v)
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
  local drawn, match = AnchorOrder.Drawn()
  write(AnchorOrder.Render(snapshot(drawn, match)), edge)
end

local function stampMeta()
  stream:Meta("version", ns.version)
  stream:Meta("viewer", VIEWER)
  stream:Meta("catalog", (ns.Sense and ns.Sense.CatalogName()) or "-")
  stream:Meta("rows", P.plan and #P.plan.order or 0)
  stream:Meta("authored", list(P.planned))
  stream:Meta("contended", P.contended)
end

-- ---------------------------------------------------------------------------
-- Reading the drawn order — the measurement the existing instruments cannot make
-- ---------------------------------------------------------------------------

--- Tracked cooldownIDs sorted by drawn left edge, plus whether that agrees with the plan.
function AnchorOrder.Drawn()
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

  local anchor = ensureAnchor()
  local mine, theirs = frames[1]:GetEffectiveScale(), UIParent:GetEffectiveScale()
  if plain(mine) and plain(theirs) and theirs ~= 0 then anchor:SetScale(mine / theirs) end
  anchor:ClearAllPoints()
  anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

  P.expected = {}
  for i, t in ipairs(P.tracked) do
    local x = (i - 1) * (w + gap)
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
    if not P.warned then
      P.warned = true
      ns.Emit("these frames moved with no hooked layout call behind it — either another addon "
        .. "is contending for position, or a layout path this probe does not hook. Either way "
        .. "the flight is not measuring persistence alone.")
    end
  end
  -- Re-assert only out of combat: the whole question is whether the positions hold in a
  -- pull, and repositioning mid-pull would answer it for us.
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
    end, AnchorOrder)
  end
end

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
  if P.armed then schedule(event) end
end)

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

local function arm()
  local rows = viewerRows()
  if #rows == 0 then
    ns.Emit("no Essential viewer rows are bound — nothing to re-anchor.")
    return false
  end
  local entries = authored(rows)
  P.plan = AnchorOrder.Plan(rows, entries)
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
    ns.Emit("could not read the viewer's geometry — not armed.")
    return false
  end
  P.ticker = C_Timer.NewTicker(SAMPLE, sample)
  return true
end

-- ---------------------------------------------------------------------------
-- The probe's own command — never a `/cap` verb (house rule 2)
-- ---------------------------------------------------------------------------

local verbs = {}

verbs.on = function()
  if P.armed then ns.Emit("already armed."); return end
  if InCombatLockdown() then
    ns.Emit("arming is out of combat only.")
    return
  end
  if arm() then
    ns.Emit(("armed on %d rows (%d authored, %d unnamed, %d missing)."):format(
      #P.plan.order, P.plan.named, P.plan.extra, #P.plan.missing))
  end
end

verbs.off = function()
  if not P.armed then ns.Emit("not armed."); return end
  if InCombatLockdown() then
    ns.Emit("restoring is out of combat only.")
    return
  end
  local orphans = disarm()
  ns.Emit("restored" .. (orphans > 0 and (" — " .. orphans .. " frames left unanchored") or "") .. ".")
end

verbs.status = function()
  if not P.armed then
    ns.Emit("disarmed. stomps " .. P.stomps .. " (" .. P.stompsCombat .. " in combat), "
      .. "displaced " .. P.displaced .. ", contended " .. P.contended .. ".")
    return
  end
  local drawn, match = AnchorOrder.Drawn()
  ns.Emit(("armed on %s — %d rows, drawn order %s."):format(VIEWER, #drawn, match and "matches" or "DIFFERS"))
  ns.Emit(("stomps %d (%d in combat), displaced %d, contended %d%s."):format(
    P.stomps, P.stompsCombat, P.displaced, P.contended,
    P.contended > 0 and " — another addon is moving these frames" or ""))
end

verbs.rows = function()
  local rows = viewerRows()
  local entries, cat = authored(rows)
  if not cat then ns.Emit("no catalog for this build."); return end
  local plan = AnchorOrder.Plan(rows, entries)
  ns.Emit(("catalog %s: %d of %d entries resolved to a live row."):format(
    cat.name or "?", plan.named, #entries))
  for _, id in ipairs(plan.missing) do ns.Emit("  no row: " .. id) end
  for _, def in ipairs({
    { global = VIEWER, want = #entries },
    { global = "UtilityCooldownViewer" },
    { global = "BuffIconCooldownViewer" },
    { global = "BuffBarCooldownViewer" },
  }) do
    local v = _G[def.global]
    local active = "?"
    if v then
      local ok, frames = pcall(v.GetItemFrames, v)
      if ok and type(frames) == "table" then active = tostring(#frames) end
    end
    ns.Emit(("  %s: %s pooled frames%s"):format(def.global, active,
      def.want and (", catalog wanted " .. def.want) or ""))
  end
end

-- Exact match only, max depth `verb [arg]` — the shape of ns.Dispatch, kept probe-local
-- because a probe may not add a verb to a shipped command.
SLASH_CAPANCHOR1 = "/capanchor"
SlashCmdList.CAPANCHOR = function(msg)
  local verb = ((msg or ""):match("^%s*(%S*)") or ""):lower()
  local fn = verbs[verb]
  if fn then fn(); return end
  ns.Emit("usage: /capanchor on | off | status | rows")
end
