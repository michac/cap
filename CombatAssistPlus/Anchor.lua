-- Anchor.lua — draws the Essential viewer's rows in the catalog's authored order, so that
-- "scan left to right, press the first thing not ruled out" means something.
--
-- It re-anchors, and only re-anchors: `layoutIndex` is both the grid sort key and the
-- cooldownID data index, so rewriting it moves icon and contents together and the row
-- looks unchanged. Nothing here writes the player's saved layout or adds a row.
--
-- Two invariants an editor would silently break: position is read with GetLeft/GetTop,
-- never through Bind or Catalog.OrderCheck, which sort by layoutIndex and cannot see a
-- SetPoint; and cap stops ordering only by asking (Anchor.Judge, ask), never by latching.
local ADDON, ns = ...


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
-- Judged over several rounds: one unattributable move is ordinary, and stopping on it
-- leaves the row in someone else's order.
local CONTENTION_STRIKES = 3
local CONTENTION_WINDOW = 10
-- "Keep trying" is honoured for this long before the dialog may open again.
local ASK_COOLDOWN = 60
-- A destructive teardown re-pools every frame; the rebuild lets the viewer settle first.
local REARM_DELAY = 0.3
local ASK_KEY = "CAP_ANCHOR_CONTENTION"

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

local num = ns.num

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
    "stale:" .. num(snap.staleSeen), "strike:" .. num(snap.strikes),
  }
  -- STALE outranks a position mismatch: the order the other terms report is about the
  -- wrong frames.
  local verdict = "MISMATCH"
  if (snap.stale or 0) > 0 then verdict = "STALE:" .. num(snap.stale)
  elseif snap.match then verdict = "ok" end
  return "A{" .. table.concat(a, " ") .. "}"
    .. " P{" .. list(snap.planned) .. "}"
    .. " D{" .. list(snap.drawn) .. "}"
    .. " X{" .. verdict .. "}"
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
-- Pure: what a displacement means, and what to do about it
-- ---------------------------------------------------------------------------

--- Judges one displacement, with the clock and counters supplied so it is decidable
--- without a client. `attributed` is a move just after one of our own hooks fired —
--- Blizzard's layout engine, which cap re-asserts against. Anything else is contention,
--- counted rather than obeyed: only a run of strikes may stop the row, and stopping it
--- means asking.
function Anchor.Judge(s)
  s = s or {}
  local now = s.now or 0
  local strikes, strikeAt = s.strikes or 0, s.strikeAt
  local action, attributed

  if s.lastCauseAt ~= nil and (now - s.lastCauseAt) <= ATTRIBUTION_WINDOW then
    attributed, action = true, "reassert"
  else
    attributed = false
    if strikeAt ~= nil and (now - strikeAt) > CONTENTION_WINDOW then strikes, strikeAt = 0, nil end
    if strikes == 0 then strikeAt = now end
    strikes = strikes + 1
    if strikes < CONTENTION_STRIKES then
      action = "reassert"
    elseif s.askedAt ~= nil and (now - s.askedAt) <= ASK_COOLDOWN then
      action, strikes, strikeAt = "reassert", 0, nil
    else
      action, strikes, strikeAt = "ask", 0, nil
    end
  end

  -- cap cannot write geometry in a pull, so a re-assert waits; a question is held, and
  -- the caller opens it leaving combat.
  if s.combat and action == "reassert" then action = "hold" end

  return { action = action, attributed = attributed, strikes = strikes, strikeAt = strikeAt }
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
  staleSeen = 0,
  strikes = 0,
  strikeAt = nil,
  askedAt = nil,
  asking = false,
  askPending = false,
  staleLatched = false,
  generation = nil,
  dirty = false,
  pending = false,
  rearmPending = false,
  anchor = nil,
  ticker = nil,
  hooked = false,
  told = nil,
}

local function bit(v) return v and "1" or "0" end

local plain = ns.plain

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

local function snapshot(drawn, match, stale)
  return {
    n = P.plan and #P.plan.order or 0,
    named = P.plan and P.plan.named or 0,
    extra = P.plan and P.plan.extra or 0,
    missing = P.plan and #P.plan.missing or 0,
    planned = P.planned,
    drawn = drawn,
    match = match,
    stale = stale,
    staleSeen = P.staleSeen,
    strikes = P.strikes,
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
  local drawn, match, stale = Anchor.Drawn()
  write(Anchor.Render(snapshot(drawn, match, stale)), edge)
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

--- The cooldownID the frame is CURRENTLY serving, or nil if it will not answer. The pool
--- re-issues frames, so the id cap recorded on taking one is a claim about the past.
local function liveID(frame)
  local ok, id = pcall(frame.GetCooldownID, frame)
  if not ok or not plain(id) then return nil end
  return id
end

--- Tracked cooldownIDs by drawn left edge, whether that agrees with the plan, and how
--- many tracked frames now serve a different row.
function Anchor.Drawn()
  local seen, stale = {}, 0
  for _, t in ipairs(P.tracked) do
    local live = liveID(t.frame)
    if live ~= nil and live ~= t.cooldownID then stale = stale + 1 end
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
  return drawn, match, stale
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

-- Defined with arming; the stomp hook and the sampler both reach it from above.
local rearm

local function scheduleRearm(why)
  if not P.armed or P.rearmPending then return end
  P.rearmPending = true
  C_Timer.After(REARM_DELAY, function()
    P.rearmPending = false
    if P.armed then rearm(why) end
  end)
end

-- ---------------------------------------------------------------------------
-- The sampler
-- ---------------------------------------------------------------------------

local ask

local function sample()
  if not P.armed or P.asking then return end

  -- Identity before position: re-placing frames the plan no longer owns scrambles the
  -- row rather than ordering it.
  local _, _, stale = Anchor.Drawn()
  if stale > 0 then
    -- One episode per latch; `adopt` clears it, so a rebuild that worked lets the next
    -- tick look again and one that did not is a fresh strike rather than a 2 Hz loop.
    if P.staleLatched then return end
    P.staleLatched = true
    P.staleSeen, P.dirty = P.staleSeen + 1, false
    mark(("# stale n=%d combat=%s"):format(stale, bit(P.combat)))
    -- `lastCauseAt` is deliberately withheld: a re-pool is a re-pool whoever caused it,
    -- and attributing it would re-arm against the same frames forever.
    local verdict = Anchor.Judge{
      now = GetTime(), combat = InCombatLockdown(),
      strikes = P.strikes, strikeAt = P.strikeAt, askedAt = P.askedAt,
    }
    P.strikes, P.strikeAt = verdict.strikes, verdict.strikeAt
    if verdict.action == "reassert" then scheduleRearm("stale")
    elseif verdict.action == "ask" then ask() end
    return
  end
  P.staleLatched = false

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

  local verdict = Anchor.Judge{
    now = GetTime(), lastCauseAt = P.lastCauseAt, combat = InCombatLockdown(),
    strikes = P.strikes, strikeAt = P.strikeAt, askedAt = P.askedAt,
  }
  P.strikes, P.strikeAt = verdict.strikes, verdict.strikeAt

  if verdict.attributed then
    P.displaced = P.displaced + 1
    mark(("# displaced n=%d combat=%s"):format(moved, bit(P.combat)))
  else
    P.contended = P.contended + 1
    mark(("# contended n=%d strike=%d combat=%s"):format(moved, P.strikes, bit(P.combat)))
  end

  if verdict.action == "reassert" then schedule("displaced")
  elseif verdict.action == "ask" then ask() end
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
  if destructive then
    P.expected = {}
    scheduleRearm(source)
  else
    schedule(source)
  end
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

local specAndHero = ns.SpecAndHero

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
--- ⚠ ONE PHRASE, FOR THE LINE CAP SAYS OUT LOUD. The player asked the reasonable question — did
--- it order the bars — and until 2026-08-23 the only answer lived in a capture file. Deliberately
--- coarse: `/cap anchor rows` is the detailed readout and this is not a second copy of it.
function Anchor.Status()
  if not Anchor.Enabled() then return "off" end
  if not P.armed then return "on, not applied" end
  return ("applied to %d row(s)"):format(#P.planned)
end

function Anchor.Census()
  local v = viewer()
  if not v then return { exists = false, rows = 0 } end
  return { exists = true, rows = #viewerRows() }
end

--- Takes the plan's frames as the ones cap owns, stamping the generation with them so a
--- later row change is distinguishable from a frame re-issue.
local function adopt(rows, entries)
  P.plan = Anchor.Plan(rows, entries)
  P.tracked, P.planned = {}, {}
  for i, item in ipairs(P.plan.order) do
    P.tracked[i] = { cooldownID = item.cooldownID, frame = item.row.frame }
    P.planned[i] = item.cooldownID
  end
  P.generation = ns.Bind.Generation and ns.Bind.Generation() or nil
  P.staleLatched = false
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
  P.strikes, P.strikeAt, P.dirty, P.generation = 0, nil, false, nil
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

  adopt(rows, entries)
  P.armed = true
  installHooks()
  mark("# armed")
  stampMeta()
  -- The first placement is itself a cause: without it the next displacement has no
  -- preceding event and reads as another addon by construction.
  P.lastCauseAt = GetTime()
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

--- Rebuilds the plan against the frames the viewer holds NOW. Re-binding first is the
--- point: Bind's rows carry frames taken before the teardown.
function rearm(why)
  if not P.armed or InCombatLockdown() then return false end
  if ns.Bind.Resolve then ns.Bind.Resolve("anchor-" .. why) end
  local rows = viewerRows()
  local entries, cat = authored(rows)
  if not cat then
    disarm()
    tell("no-catalog", "no catalog for this spec and hero tree, so cap has no order to "
      .. "impose — the row keeps Blizzard's.")
    return false
  end
  adopt(rows, entries)
  P.dirty = false
  mark("# rearmed why=" .. why)
  stampMeta()
  P.lastCauseAt = GetTime()
  return apply("rearmed")
end

--- Turns ordering off and persists it; only the player turns it on again.
function Anchor.Disable()
  store().anchor = false
  if P.armed then disarm() end
  ns.Emit("ordering off — the row keeps Blizzard's order. /cap anchor on to turn it back on.")
end

--- Drops the strike run and rebuilds from scratch — the one recovery path.
function Anchor.Retry()
  P.strikes, P.strikeAt, P.dirty, P.told = 0, nil, false, nil
  if InCombatLockdown() then return false, "combat" end
  if P.armed then disarm() end
  return arm()
end

local function asking()
  return StaticPopup_IsCustomGenericConfirmationShown
    and StaticPopup_IsCustomGenericConfirmationShown(ASK_KEY) or false
end

-- cap stops only by being told to, never by latching. Held out of combat: a dialog
-- mid-pull is its own problem.
function ask()
  if P.asking then return end
  if InCombatLockdown() then P.askPending = true; return end
  if not StaticPopup_ShowCustomGenericConfirmation then
    P.askedAt, P.askPending = GetTime(), false
    ns.Emit("something else is moving the Cooldown Manager's icons, so the row's order is "
      .. "not cap's. /cap anchor off to stop trying, /cap anchor retry to rebuild.")
    return
  end
  P.asking, P.askPending = true, false
  P.askedAt = GetTime()
  mark("# asking")
  StaticPopup_ShowCustomGenericConfirmation{
    referenceKey = ASK_KEY,
    showAlert = true,
    text = "Combat Assist Plus\n\nSomething else is moving the Cooldown Manager's icons, so "
      .. "cap cannot order them. The row's left-to-right order is not cap's and should not be "
      .. "read as a priority.\n\nTurn cap's ordering off?",
    acceptText = "Turn it off",
    cancelText = "Keep trying",
    callback = function()
      P.asking = false
      Anchor.Disable()
    end,
    cancelCallback = function()
      P.asking = false
      Anchor.Retry()
    end,
  }
end

--- Arms if enabled and not armed; otherwise rebuilds or re-applies. Callers are events.
local function refresh()
  if not Anchor.Enabled() then return end
  if P.asking and not asking() then P.asking = false end
  if P.asking or InCombatLockdown() then return end
  if not P.armed then arm(); return end
  if P.generation ~= (ns.Bind.Generation and ns.Bind.Generation() or nil) then
    scheduleRearm("generation")
  else
    schedule("event")
  end
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
    if P.askPending then ask(); return end
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
  local drawn, match, stale = Anchor.Drawn()
  ns.Emit(("ordering %d rows on %s — drawn order %s the authored one."):format(
    #drawn, VIEWER, match and "matches" or "DIFFERS from"))
  ns.Emit(("layout rebuilds %d (%d in combat), displaced %d, contended %d, re-pooled %d."):format(
    P.stomps, P.stompsCombat, P.displaced, P.contended, P.staleSeen))
  if stale > 0 then
    ns.Emit(("  %d frames are serving other rows right now — rebuilding."):format(stale))
  end
  if P.contended > 0 then
    ns.Emit(("  something else is moving these frames (%d of %d strikes). /cap anchor retry "
      .. "to rebuild now."):format(P.strikes, CONTENTION_STRIKES))
  end
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

local function enable()
  store().anchor = true
  P.told, P.askedAt = nil, nil
  if not P.armed then arm() end
  ns.Emit("ordering on.")
end

local function retryLine()
  local ok, why = Anchor.Retry()
  if why == "combat" then ns.Emit("out of combat only."); return end
  ns.Emit(ok and "rebuilt from the Cooldown Manager's current frames."
    or "could not rebuild — see /cap anchor status.")
end

local actions = {
  [""] = statusLine,
  status = statusLine,
  rows = rowsLine,
  retry = retryLine,
  on = enable,
  off = Anchor.Disable,
}

ns.RegisterCommand{
  name = "anchor", order = 35, args = "[on|off|retry|rows]",
  desc = "Draw the Cooldown Manager row in the catalog's priority order",
  handler = function(rest)
    local verb = (rest or ""):lower()
    local action = actions[verb]
    if not action then
      ns.Emit("usage: /cap anchor  or  /cap anchor on|off|retry|rows")
      return
    end
    if (verb == "on" or verb == "off" or verb == "retry") and InCombatLockdown() then
      ns.Emit("out of combat only.")
      return
    end
    action()
  end,
}
