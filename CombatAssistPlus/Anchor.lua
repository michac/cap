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
-- The row panel's own name, because a mover can only address a frame that has one.
local ROW_NAME = "CombatAssistPlusRow"
-- Blizzard's item template is 50x50 (CooldownViewer.xml, CooldownViewerEssentialItemTemplate),
-- so a cell narrower than this would overlap icons whatever the tokens say.
local CELL_FLOOR = 50
-- Where the panel sits before it has ever been placed. Nearly unreachable: the first apply
-- SEEDS the saved position from wherever the Cooldown Manager drew the row, and `/cap move
-- reset` clears the seed so the next apply takes it again. This is the fallback for a reset
-- performed while the viewer has drawn nothing to measure.
local ROW_DEFAULT_X, ROW_DEFAULT_Y = 0, -200
-- Where a parked frame goes: far enough off the anchor that no UI scale brings it back, and
-- expressed as an offset so it travels with the anchor instead of pinning to a screen corner.
local PARK_X, PARK_Y = -10000, 10000
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
local RIDER_KEY = "CAP_ANCHOR_RIDER"
-- Two addons that each force a frame back to their own anchor recurse without bound inside
-- one SetPoint call. The positional test at arm time is the detector; this is the floor
-- under it, for the rider that claims the row after cap has already armed.
local REENTRY_LIMIT = 8

local stream = ns.Capture.Open("anchor", { sessions = 8, cap = 2000, dedup = false })

-- One button, because there is nothing for the player to decide here: cap has already
-- stopped, and the only fix is a toggle on the addon list.
if StaticPopupDialogs then
  StaticPopupDialogs[RIDER_KEY] = {
    text = "Combat Assist Plus\n\n%s",
    button1 = OKAY or "Okay",
    showAlert = 1,
    hideOnEscape = 1,
    whileDead = 1,
    timeout = 0,
    wide = 1,
  }
end

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
    "parked:" .. num(snap.parkedNow),
  }
  local s = {
    "stomp:" .. num(snap.stomps), "icombat:" .. num(snap.stompsCombat),
    "disp:" .. num(snap.displaced), "cont:" .. num(snap.contended),
    "reassert:" .. num(snap.reasserts), "park:" .. num(snap.parks),
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

--- Judges one displacement the SAMPLER still sees — that is, one the per-frame re-assert
--- did not already correct. `handledAt` is the last time cap re-placed a frame itself, so
--- `attributed` means the layout engine is still settling around a move cap has answered.
--- A displacement standing with no recent answer of ours reached the frame by a route the
--- re-assert cannot see, and is contention: counted rather than obeyed, and only a run of
--- strikes may stop the row, which means asking.
function Anchor.Judge(s)
  s = s or {}
  local now = s.now or 0
  local strikes, strikeAt = s.strikes or 0, s.strikeAt
  local action, attributed

  if s.handledAt ~= nil and (now - s.handledAt) <= ATTRIBUTION_WINDOW then
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

  -- A re-assert is a SetPoint on an unprotected frame, so combat does not change the
  -- verdict. Only the question is held, and the caller opens it leaving combat.
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
  -- Frame -> where that frame belongs, for every frame cap currently holds a position for:
  -- the placed ones and the parked ones alike. The re-assert hook reads only this.
  wantOf = {},
  -- Every frame cap has MOVED, whether or not the plan still names it. `tracked` is rebuilt on
  -- every adopt; this is not, because a frame cap displaced and then stopped tracking is still
  -- cap's to answer for — restoring it is what `disarm` owes.
  claimed = {},
  -- Claimed frames the plan no longer places. They are held off the row rather than left in it.
  parked = {},
  parks = 0,
  parkPending = 0,
  planned = {},
  stomps = 0,
  stompsCombat = 0,
  displaced = 0,
  contended = 0,
  reasserts = 0,
  handledAt = nil,
  staleSeen = 0,
  strikes = 0,
  strikeAt = nil,
  askedAt = nil,
  asking = false,
  askPending = false,
  -- The message cap is standing down with, or nil when it is not. Re-decided on every arm
  -- attempt, so a rider the player disables stops holding cap off on the next event.
  stoodDown = nil,
  riderTold = false,
  riderPending = nil,
  riderGuard = false,
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

-- Defined with the apply machinery below; the row panel's drag callback reaches it from here.
local schedule

-- ---------------------------------------------------------------------------
-- The grid
--
-- ⚠ EVERY NUMBER HERE IS IN THE PANEL'S OWN COORDINATE SPACE. The panel is scaled to match
-- the item frames (see `rowScale`), so Edit Mode's icon-size setting arrives as that SCALE
-- and must not be multiplied into these lengths as well — `GetWidth` on an item frame reads
-- 50 whatever `SetScale` did to it. A cell of `50 x iconScale` would count it twice.
--
-- Fixed cell counts are the point: the panel's rect is known at login, so it never waits for
-- the Cooldown Manager to draw before it can be dragged or anchored to.
-- ---------------------------------------------------------------------------

local function grid()
  local t = ns.Style and ns.Style.row
  if type(t) ~= "table" then return 6, 2, CELL_FLOOR, 1 end
  local cell = math.max(t.cell_px or CELL_FLOOR, t.cell_floor_px or CELL_FLOOR)
  return t.cols or 6, t.rows or 2, cell, t.gap_px or 1
end

local function gridSize()
  local cols, rowCount, cell, gap = grid()
  return cols * cell + (cols - 1) * gap, rowCount * cell + (rowCount - 1) * gap
end

-- Exported because they are the arithmetic and not the frame: the panel's rect is a claim
-- about how many icons fit and how far apart they sit, and that claim is checkable without a
-- client. Read them; do not re-derive a cell size anywhere else.
Anchor.Grid = grid
Anchor.GridSize = gridSize

--- The scale the panel wears so that one unit in it is one unit on an item frame. Measured
--- off a live frame when there is one; before that, Edit Mode's icon-size setting is the
--- estimate, since the viewer itself is unscaled by default
--- *[T1 src @12.1.0: Blizzard_EditMode/Shared/EditModeSystemTemplates.lua —
--- EditModeCooldownViewerSystemMixin:UpdateSystemSettingIconSize]*.
local function rowScale(frame)
  if frame then
    local mine, theirs = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if plain(mine) and plain(theirs) and theirs ~= 0 then return mine / theirs end
  end
  local v = viewer()
  local s = v and v.iconScale
  if plain(s) and s > 0 then return s end
  return 1
end

local function geometry(frame)
  local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
  if not ok or not (plain(left) and plain(top)) then return nil end
  return left, top
end

-- ---------------------------------------------------------------------------
-- Who is placing the row
-- ---------------------------------------------------------------------------

--- Which owner one anchor point names: cap's own frame, the viewer's subtree, or a
--- stranger. A nil `relativeTo` resolves against the parent, which is how Blizzard's own
--- layout writes most of them.
local function owner(relativeTo, frame, v)
  if relativeTo == nil then
    local ok, parent = pcall(frame.GetParent, frame)
    if not ok then return "other" end
    relativeTo = parent
  end
  if P.anchor ~= nil and relativeTo == P.anchor then return "cap" end
  local node, depth = relativeTo, 0
  while node ~= nil and depth < 8 do
    if node == v then return "viewer" end
    -- One pcall for the index and the call together: a node with no GetParent and a node
    -- that refuses the read are the same answer here, which is "stop walking".
    local ok, parent = pcall(function() return node:GetParent() end)
    if not ok then break end
    node, depth = parent, depth + 1
  end
  return "other"
end

--- Owner tags for every point one item frame carries. A point cap cannot read is dropped
--- rather than guessed at, because a guess here either nags a player with no rider or
--- lets cap arm beside one.
local function ownerTags(frame, v)
  local tags = {}
  local ok, n = pcall(frame.GetNumPoints, frame)
  if not ok or not plain(n) or type(n) ~= "number" then return tags end
  for i = 1, n do
    local got, _, relativeTo = pcall(frame.GetPoint, frame, i)
    if got then tags[#tags + 1] = owner(relativeTo, frame, v) end
  end
  return tags
end

local function addonLoaded()
  return (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
end

--- The stand-down message, or nil. Both stages have to agree: a known rider is loaded, AND
--- an item frame is anchored to neither the viewer nor cap, which is the difference between
--- a rider that is installed and a rider that is managing the row.
local function riderMessage(rows)
  local labels = ns.Riders.Loaded(addonLoaded())
  if #labels == 0 then return nil end
  local v = viewer()
  local frames = {}
  for _, row in ipairs(rows) do frames[#frames + 1] = ownerTags(row.frame, v) end
  return ns.Riders.Message(labels, ns.Riders.Managing(frames))
end

-- ---------------------------------------------------------------------------
-- Writing
-- ---------------------------------------------------------------------------

local function countParked()
  local n = 0
  for _ in pairs(P.parked) do n = n + 1 end
  return n
end

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
    reasserts = P.reasserts,
    parks = P.parks,
    parkedNow = countParked(),
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

--- The row panel. Created once, eagerly: `/cap move` has to be able to offer it before the
--- Cooldown Manager has drawn anything, and a mover can only register a frame that exists.
--- ⚠ Its IDENTITY is the discriminator `owner()` uses to tell cap's own writes from a
--- stranger's, so nothing here may replace the frame once anything is anchored to it.
local function ensureAnchor()
  if P.anchor then return P.anchor end
  local f = CreateFrame("Frame", ROW_NAME, UIParent)
  f:SetSize(gridSize())
  f:SetScale(rowScale(nil))
  P.anchor = f
  P.place = ns.Place.Register{
    key = "row", frame = f, noun = "CDM row",
    label = "cap row — drag to place",
    x = ROW_DEFAULT_X, y = ROW_DEFAULT_Y,
    -- A drag ends with the panel somewhere new; the frames it carries follow it live, but
    -- the drift auditor's expectations are absolute coordinates and are now stale.
    onPlaced = function() if P.armed then schedule("moved") end end,
  }
  return f
end

--- Re-sizes the panel from the tokens and the live icon scale. Cheap and idempotent, so it
--- rides every apply and the Edit Mode settings callback rather than needing its own guard.
local function resizeAnchor(frame)
  local f = ensureAnchor()
  local w, h = gridSize()
  local scale = rowScale(frame)
  local changed = f:GetWidth() ~= w or f:GetHeight() ~= h or f:GetScale() ~= scale
  if not changed then return false end
  f:SetSize(w, h)
  f:SetScale(scale)
  return true
end

-- Puts one frame where cap wants it — in the row, or off it. EVERY write cap makes to an item
-- frame goes through here, which is what makes the anchor a reliable own-write signature, and
-- what makes `claimed` a complete list of what `disarm` owes the player back.
--
-- ⚠ ONE ANCHOR KEYWORD FOR BOTH. A same-keyword `SetPoint` replaces; a different one would
-- accumulate a second, conflicting anchor, so a parked frame would be pulled between the two
-- rather than leaving the row.
local function place(frame, want)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", P.anchor, "TOPLEFT", want.x, want.y)
  P.claimed[frame] = true
end

--- Where a frame goes when cap has claimed it but the plan no longer says where it belongs.
--- `left`/`top` follow the offsets so a later drift read describes the parked position rather
--- than reporting the park itself as a displacement.
local function parkWant(left, top)
  return { x = PARK_X, y = PARK_Y, left = (left or 0) + PARK_X, top = (top or 0) + PARK_Y }
end

local reentry = 0
local standDown

--- Corrects a frame inside the call that moved it, so a foreign placement never draws.
--- The discriminator is the anchor: everything cap writes is relative to its own frame,
--- so a point relative to anything else — including a bare offset, which resolves against
--- the parent — came from outside. This catches movers that expose no hook of their own.
local function onFramePoint(frame, _, relativeTo)
  if not P.armed or P.riderGuard or P.anchor == nil or relativeTo == P.anchor then return end
  local want = P.wantOf[frame]
  if not want then return end
  -- ⚠ A FOREIGN ORIGIN USED TO BE READ HERE, before the correction destroyed the evidence,
  -- so that Blizzard's Layout could move cap's whole row
  -- *[T1 src @12.1.0: Blizzard_SharedXML/LayoutFrame.lua — LayoutMixin:Layout, LayoutChildren]*.
  -- The row holds a saved position of its own now, so following somebody else's placement is
  -- exactly what it must not do: the reading was deleted rather than kept and ignored, since a
  -- live origin nothing consumes is an invitation to consume it.
  local now = GetTime()
  -- ⚠ THE ONE PLACE CAP CAN CRASH THE CLIENT. Another rider's own SetPoint hook answers
  -- this write with a write of its own, which lands back here: the depth counter is what
  -- turns that mutual recursion into a stand-down. The teardown is deferred because this
  -- runs inside somebody else's SetPoint.
  if reentry >= REENTRY_LIMIT then
    if not P.riderGuard then
      P.riderGuard = true
      C_Timer.After(0, function()
        standDown(ns.Riders.Message(ns.Riders.Loaded(addonLoaded()), true))
      end)
    end
    return
  end
  reentry = reentry + 1
  place(frame, want)
  reentry = reentry - 1
  P.reasserts = P.reasserts + 1
  P.handledAt = now
end

-- `hooksecurefunc` cannot be removed, so the flag is per frame and permanent; every
-- callback is gated on `armed` and on the frame still being one the plan owns. Weak keys
-- so a frame the viewer drops is not held alive by the record of having been hooked.
local hookedFrames = setmetatable({}, { __mode = "k" })

local function armFrame(frame)
  if hookedFrames[frame] or type(frame.SetPoint) ~= "function" then return end
  hookedFrames[frame] = true
  hooksecurefunc(frame, "SetPoint", onFramePoint)
end

-- The drawn row's top-left corner, read off the frames before any of them move. This is the
-- ONE thing still taken from Blizzard's geometry, and it is taken once: it seeds the panel's
-- saved position so an upgrading player's row does not jump on the login that gives it one.
-- ⚠ The COLUMN SPACING used to be derived here, as the narrowest observed gap with a
-- fallback of 4. It is not derived any more, because the grid is cap's: the panel declares
-- its own cell and gap (`tokens.row`), which is what lets its rect be known before the
-- Cooldown Manager has drawn. For the record the fallback was also wrong — Blizzard's own
-- layout padding is `iconPadding + GetAdditionalPaddingOffset()` = 5 + (-4) = 1
-- *[T1 src @12.1.0: Blizzard_CooldownViewer/CooldownViewer.lua —
-- CooldownViewerMixin:GetAdditionalPaddingOffset, and the childXPadding assignment]*.
local function origin(frames)
  local left, top = nil, nil
  for _, frame in ipairs(frames) do
    local l, t = geometry(frame)
    if l then
      if left == nil or l < left then left = l end
      if top == nil or t > top then top = t end
    end
  end
  if left == nil then return nil end
  return left, top
end

local function apply(why)
  if not P.armed or not P.plan then return false end
  local frames = {}
  for _, t in ipairs(P.tracked) do frames[#frames + 1] = t.frame end
  if #frames == 0 then return false end

  local anchor = ensureAnchor()
  resizeAnchor(frames[1])

  -- ⚠ WHOSE ORIGIN THIS IS. It used to be Blizzard's, re-measured on every pass, which is why
  -- the row had no position of its own and nothing could be anchored to it. It is the
  -- PLAYER'S now, held in `Place`, and Blizzard's geometry is consulted exactly once — to
  -- seed that store the first time, so the login that hands the row a position of its own
  -- does not appear to move it. A layout pass no longer relocates cap's row, and that is the
  -- deliberate behaviour change: an Edit Mode move of the Cooldown Manager moves Blizzard's
  -- row, and cap's row stays where the player put it (`/cap move reset` re-seeds).
  if not P.place:Store().placed then
    local left, top = origin(frames)
    if not left then return false end
    anchor:ClearAllPoints()
    anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    P.place:Seed()
  end
  P.place:Apply()

  -- The drift auditor compares absolute coordinates, so the row's expectations are derived
  -- from where the panel actually landed rather than from what was asked for. A panel whose
  -- rect will not answer is not a reason to place frames at a guessed origin: bail, and let
  -- the next event try again.
  local left, top = anchor:GetLeft(), anchor:GetTop()
  if not (plain(left) and plain(top)) then return false end

  local _, _, cell, gap = grid()
  local pitch = cell + gap

  -- Stamped before the write, not after: `onFramePoint` fires synchronously inside the
  -- SetPoint below, and a stale expectation there would undo the move being made.
  P.wantOf = {}
  for i, t in ipairs(P.tracked) do
    local x = (i - 1) * pitch
    local want = { x = x, y = 0, left = left + x, top = top }
    P.wantOf[t.frame] = want
    place(t.frame, want)
  end
  -- Parked frames are re-asserted on the same pass. They are held by the same hook as the
  -- placed ones, so an omission here would not leave them parked — it would hand them back to
  -- Blizzard's next layout pass, which is the state parking exists to prevent.
  for frame in pairs(P.parked) do
    local want = parkWant(left, top)
    P.wantOf[frame] = want
    place(frame, want)
  end
  P.handledAt = GetTime()
  P.dirty = false
  if P.parkPending > 0 then
    P.parks = P.parks + P.parkPending
    mark(("# parked n=%d combat=%s"):format(P.parkPending, bit(P.combat)))
    P.parkPending = 0
  end
  mark("# reapply why=" .. why)
  stampMeta()
  return true
end

-- One pass per burst: a spec swap raises several of these events back to back, and each
-- one would otherwise re-measure a layout that is still in flight.
function schedule(why)
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
    -- Cleared AFTER the call: while a rearm is running it is still pending, so a stomp
    -- it provokes coalesces into it rather than queuing a second one behind it.
    if P.armed then rearm(why) end
    P.rearmPending = false
  end)
end

-- ---------------------------------------------------------------------------
-- The auditor
--
-- The re-assert does not wait for this: `onFramePoint` corrects a move inside the call
-- that made it. What survives to be seen here arrived by a route SetPoint does not carry,
-- so this measures drift, feeds Judge and raises the question — and re-places as a
-- backstop for exactly those routes.
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
    -- `handledAt` is deliberately withheld: a re-pool is a re-pool whoever caused it,
    -- and attributing it would re-arm against the same frames forever.
    local verdict = Anchor.Judge{
      now = GetTime(),
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
    local want = P.wantOf[t.frame]
    local left, top = geometry(t.frame)
    if want and left then
      if math.abs(left - want.left) > TOLERANCE or math.abs(top - want.top) > TOLERANCE then
        moved = moved + 1
      end
    end
  end
  -- One mark per displacement, not one per tick: a mover that keeps winning would
  -- otherwise repeat the same finding twice a second for the whole pull.
  if moved == 0 then P.dirty = false; return end
  if P.dirty then return end
  P.dirty = true

  local verdict = Anchor.Judge{
    now = GetTime(), handledAt = P.handledAt,
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
  if P.combat then P.stompsCombat = P.stompsCombat + 1 end
  mark(("# stomp %s destructive=%s combat=%s"):format(source, bit(destructive), bit(P.combat)))
  if destructive then
    -- ⚠ THE CLAIM DIES WITH THE POOL, and a park that outlived it would be a bug with teeth.
    -- `RefreshLayout` releases every item frame and re-acquires it against a fresh row, so cap
    -- neither owes these frames a restore nor may keep holding one off the row: the same frame
    -- object comes back serving a different ability, and a stale park would make that ability
    -- silently invisible.
    P.wantOf, P.parked, P.claimed, P.parkPending = {}, {}, {}, 0
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
      -- ⚠ Unconditional, unlike the schedule below it: the icon-size setting changes the
      -- panel's own size whether or not cap is ordering, and a mover that has registered our
      -- geometry is entitled to a panel whose rect is honest at all times.
      resizeAnchor(nil)
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
  if P.stoodDown then return "off — another addon is arranging the row" end
  if not P.armed then return "on, not applied" end
  local parkedNow = countParked()
  if parkedNow > 0 then
    return ("applied to %d row(s), %d held off the row"):format(#P.planned, parkedNow)
  end
  return ("applied to %d row(s)"):format(#P.planned)
end

function Anchor.Census()
  local v = viewer()
  if not v then return { exists = false, rows = 0 } end
  return { exists = true, rows = #viewerRows() }
end

--- Takes the plan's frames as the ones cap owns, stamping the generation with them so a
--- later row change is distinguishable from a frame re-issue.
---
--- ⚠ It also decides what is PARKED, which is the half a plain rebuild used to drop. A frame
--- cap moved and the new plan does not name is not "no longer our problem": it is sitting at
--- cap's coordinates, inside a row that reads as a priority scan, in nobody's order. The
--- commonest way in is a live `GetCooldownID()` that stopped matching, which takes the row out
--- of `Bind`'s list without taking the icon off the screen.
local function adopt(rows, entries)
  P.plan = Anchor.Plan(rows, entries)
  P.tracked, P.planned = {}, {}
  local inPlan = {}
  for i, item in ipairs(P.plan.order) do
    P.tracked[i] = { cooldownID = item.cooldownID, frame = item.row.frame }
    P.planned[i] = item.cooldownID
    inPlan[item.row.frame] = true
    -- A frame returning to the plan stops being parked; `apply` places it on this pass.
    P.parked[item.row.frame] = nil
    armFrame(item.row.frame)
  end

  -- Counted here, REPORTED by `apply`, because `apply` is what actually moves them. An adopt
  -- that is followed by a failed apply has parked nothing, and a capture line saying otherwise
  -- would be the instrument describing a move it never made.
  for frame in pairs(P.claimed) do
    if not inPlan[frame] and not P.parked[frame] then
      P.parked[frame] = true
      P.parkPending = P.parkPending + 1
    end
  end

  P.generation = ns.Bind.Generation and ns.Bind.Generation() or nil
  P.staleLatched = false
end

--- Hands every frame cap moved back to Blizzard and lets its layout place them.
---
--- ⚠ It walks `claimed`, not `tracked`. A parked frame is by definition absent from the plan,
--- so restoring only the tracked ones would turn ordering off and leave the parked icons
--- offscreen — cap's last act would be to hide a row permanently.
local function disarm()
  P.armed = false
  if P.ticker then P.ticker:Cancel(); P.ticker = nil end
  local restoring, orphans = {}, 0
  for frame in pairs(P.claimed) do restoring[#restoring + 1] = frame end
  for _, frame in ipairs(restoring) do frame:ClearAllPoints() end
  local v = viewer()
  if v and type(v.Layout) == "function" then pcall(v.Layout, v) end
  for _, frame in ipairs(restoring) do
    local ok, points = pcall(frame.GetNumPoints, frame)
    if not ok or not plain(points) or points == 0 then orphans = orphans + 1 end
  end
  mark(("# restored n=%d orphans=%d"):format(#restoring, orphans))
  P.tracked, P.wantOf, P.planned, P.plan = {}, {}, {}, nil
  P.claimed, P.parked, P.parkPending = {}, {}, 0
  P.strikes, P.strikeAt, P.dirty, P.generation = 0, nil, false, nil
  return orphans
end

-- ---------------------------------------------------------------------------
-- Standing down beside another rider
-- ---------------------------------------------------------------------------

--- Said once a session, and deliberately not remembered across one: the nag is the point,
--- and the fix is one toggle on the addon list. Held out of combat, as the contention
--- question is.
local function showRider(message)
  if P.riderTold then return end
  if InCombatLockdown() then P.riderPending = message; return end
  P.riderTold, P.riderPending = true, nil
  if StaticPopupDialogs and StaticPopupDialogs[RIDER_KEY] and StaticPopup_Show then
    StaticPopup_Show(RIDER_KEY, message)
  end
end

--- Gives every frame cap holds back and orders nothing until the rider is gone. `message`
--- is what the player is told and also the flag `Anchor.Ordering` reads, so another addon's
--- conflict check sees cap step aside rather than a setting it cannot inspect.
function standDown(message)
  -- Idempotent because every event retries the arm: without this the same finding would
  -- write a capture mark and a chat line on each one.
  if not message or P.stoodDown == message then return end
  P.stoodDown = message
  if P.armed then disarm() end
  mark("# stood-down")
  tell("rider", (message:gsub("%s+", " ")))
  showRider(message)
end

--- Is cap going to order the row? Read by another addon's conflict table, which should not
--- raise its own dialog about an addon that has already stepped aside.
function Anchor.Ordering()
  return Anchor.Enabled() and P.stoodDown == nil
end
_G._CAP_IsOrderingEnabled = Anchor.Ordering

--- WHY cap is not ordering — `"off"` or `"rider"` — or nil when it is. Separate from
--- `Ordering()` because the two readers want different things: a foreign conflict table wants
--- the boolean, and `/cap status` has to name the cause, since "cap is drawing nothing" is
--- only actionable with the reason beside it.
function Anchor.NotOrdering()
  if not Anchor.Enabled() then return "off" end
  if P.stoodDown then return "rider" end
  return nil
end

--- Returns ok, reason. `reason` is nil on success and on a silent retry-later.
local function arm()
  -- The backstop latches for the session: it fired inside somebody's SetPoint, and arming
  -- again against the same frames is how that becomes a loop. /cap anchor retry releases it.
  if P.riderGuard then return false, "rider" end
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

  -- ⚠ BEFORE `adopt`, which is what hooks each frame's SetPoint. A second such hook on a
  -- frame another rider already holds recurses without bound, so the test has to precede
  -- the first one. Re-decided every attempt, so a rider the player disables stops holding
  -- cap off on the next event.
  local rider = riderMessage(rows)
  if rider then
    standDown(rider)
    return false, "rider"
  end
  P.stoodDown = nil

  adopt(rows, entries)
  P.armed = true
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

--- Rebuilds the plan against the frames the viewer holds NOW. Re-binding first is the
--- point: Bind's rows carry frames taken before the teardown.
function rearm(why)
  if not P.armed then return false end
  if ns.Bind.Resolve then ns.Bind.Resolve("anchor-" .. why) end
  local rows = viewerRows()
  local entries, cat = authored(rows)
  if not cat then
    disarm()
    tell("no-catalog", "no catalog for this spec and hero tree, so cap has no order to "
      .. "impose — the row keeps Blizzard's.")
    return false
  end
  local rider = riderMessage(rows)
  if rider then
    standDown(rider)
    return false
  end
  adopt(rows, entries)
  P.dirty = false
  mark("# rearmed why=" .. why)
  stampMeta()
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
  P.riderGuard, P.stoodDown = false, nil
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
  if P.asking then return end
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
    if P.riderPending then showRider(P.riderPending) end
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

-- The panel exists from load, not from the first successful arm. `/cap move` must be able to
-- offer it before the Cooldown Manager has drawn anything, a mover can only register a frame
-- that already exists, and its size comes from the tokens rather than from a measurement — so
-- there is nothing left to wait for.
ensureAnchor()

local function statusLine()
  if not P.armed then
    if P.stoodDown then
      ns.Emit("ordering is standing down.")
      ns.Emit("  " .. P.stoodDown:gsub("\n+", " "))
      return
    end
    ns.Emit("ordering is " .. (Anchor.Enabled() and "on but not applied" or "off") .. ".")
    local _, message = Anchor.Diagnose(Anchor.Census())
    if message then ns.Emit("  " .. message) end
    return
  end
  local drawn, match, stale = Anchor.Drawn()
  ns.Emit(("ordering %d rows on %s — drawn order %s the authored one."):format(
    #drawn, VIEWER, match and "matches" or "DIFFERS from"))
  ns.Emit(("layout rebuilds %d (%d in combat), re-asserted %d, displaced %d, contended %d, "
    .. "re-pooled %d, parked %d."):format(
    P.stomps, P.stompsCombat, P.reasserts, P.displaced, P.contended, P.staleSeen, P.parks))
  local parkedNow = countParked()
  if parkedNow > 0 then
    ns.Emit(("  %d icon(s) held off the row — cap moved them and can no longer say where they "
      .. "belong. /cap anchor off returns them."):format(parkedNow))
  end
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
