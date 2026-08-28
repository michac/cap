-- Bind.lua — which Cooldown Manager icon is which ability, kept correct across
-- spec, talent and hero-tree changes.
--
-- Identity resolves in combat as well as out: the reads are all getters. A value that
-- reads secret or throws is "no answer", never "no ability": the pass is reported partial
-- and the row is absent from it. See knowledge/addon-dev/cooldown-manager.md rules 2, 9, 15.
--
-- State and a read API only — it registers no commands and never edits Core.lua.
local ADDON, ns = ...

local CAT = Enum and Enum.CooldownViewerCategory

-- Family, not category, is the stable classifier (cooldown-manager.md §1.1).
local VIEWERS = {
  { global = "EssentialCooldownViewer", short = "E",  family = "spells", category = CAT and CAT.Essential or 0 },
  { global = "UtilityCooldownViewer",   short = "U",  family = "spells", category = CAT and CAT.Utility or 1 },
  { global = "BuffIconCooldownViewer",  short = "BI", family = "auras",  category = CAT and CAT.TrackedBuff or 2 },
  { global = "BuffBarCooldownViewer",   short = "BB", family = "auras",  category = CAT and CAT.TrackedBar or 3 },
}

local RESOLVE_DELAY = 0.2
local LOGIN_GRACE = 5

local state = {
  rows = {},      -- cooldownID -> row
  order = {},     -- rows in viewer order
  generation = 0,
  signature = "",
  frames = 0,
  viewers = 0,
  viewersShown = 0,
  unreadable = 0,
  unreadableAt = "",
  complete = false,
  observed = false,
  pending = false,
  pendingReason = nil,
  -- The only thing separating "quiet because nothing needed rebinding" from
  -- "quiet because 40 requests coalesced into one".
  deferred = 0,
  deferredLast = 0,
  lastAt = nil,
  lastReason = nil,
  health = { kind = "unknown" },
}

local listeners = {}
local watchers = {}
local resolveTimerArmed = false
local graceStarted = false

-- ---------------------------------------------------------------------------
-- Reading values that may be secret
-- ---------------------------------------------------------------------------

local plain = ns.plain

-- Three answers, not two. "empty" is a genuinely unoccupied slot; "secret" and
-- "unreadable" are slots we must draw no conclusion about.
local function readField(obj, method)
  if type(obj) ~= "table" then return nil, "unreadable" end
  local fn = obj[method]
  if type(fn) ~= "function" then return nil, "unreadable" end
  local ok, v = pcall(fn, obj)
  if not ok then return nil, "unreadable" end
  if v == nil then return nil, "empty" end
  if issecretvalue(v) then return nil, "secret" end
  return v, "plain"
end

-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------

local function buildRow(viewerDef, frame, cooldownID, index)
  if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return nil end
  local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
  if not ok or type(info) ~= "table" or issecrettable(info) then return nil end

  local base = plain(info.spellID) and info.spellID or nil
  local override = plain(info.overrideSpellID) and info.overrideSpellID or nil
  local tooltip = plain(info.overrideTooltipSpellID) and info.overrideTooltipSpellID or nil

  -- The static override, not the live id: a transform makes the live id flicker
  -- exactly when the ability is most active (rule 15, §2.8).
  local primary = override or base
  if not primary then return nil end

  local liveValue, liveClass = readField(frame, "GetSpellID")
  local live = (liveClass == "plain") and liveValue or nil

  local ids = {}
  ids[primary] = true
  if base then ids[base] = true end
  if tooltip then ids[tooltip] = true end
  if live then ids[live] = true end

  local pool = {}
  if type(info.linkedSpellIDs) == "table" and not issecrettable(info.linkedSpellIDs) then
    for _, id in ipairs(info.linkedSpellIDs) do
      if plain(id) then pool[#pool + 1] = id end
    end
  end

  local isKnown
  if plain(info.isKnown) then isKnown = info.isKnown end

  return {
    cooldownID = cooldownID,
    viewer = viewerDef.global,
    short = viewerDef.short,
    family = viewerDef.family,
    category = viewerDef.category,
    index = index,
    frame = frame,
    primary = primary,
    base = base,
    override = override,
    tooltip = tooltip,
    live = live,
    pool = pool,
    spellIDs = ids,
    isKnown = isKnown,
  }
end

local function signatureOf(order)
  local parts = {}
  for i = 1, #order do
    local row = order[i]
    parts[i] = row.cooldownID .. ":" .. row.primary
  end
  return table.concat(parts, ",")
end

local function notify()
  for i = 1, #listeners do
    local ok, err = pcall(listeners[i], state.order, state.generation)
    if not ok then ns.Emit("bind listener errored: " .. tostring(err)) end
  end
end

local function categorySetTotal()
  if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then return 0, false end
  local total, answered = 0, false
  for _, v in ipairs(VIEWERS) do
    local ok, set = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, v.category, false)
    if ok and type(set) == "table" and not issecrettable(set) then
      answered = true
      total = total + #set
    end
  end
  return total, answered
end

local function evaluate(why)
  local health = {
    rows = #state.order,
    frames = state.frames,
    viewers = state.viewers,
    viewersShown = state.viewersShown,
  }
  health.configured, health.configuredOk = categorySetTotal()

  if not (C_CooldownViewer and _G.EssentialCooldownViewer) then
    health.kind = "no-addon"
  else
    local ok, isAvailable, reason = pcall(C_CooldownViewer.IsCooldownViewerAvailable)
    if ok and plain(isAvailable) and isAvailable == false then
      health.kind = "unavailable"
      if plain(reason) and type(reason) == "string" and reason ~= "" then health.detail = reason end
    elseif C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("cooldownViewerEnabled") == false then
      health.kind = "disabled"
    elseif health.configuredOk and health.configured == 0 then
      health.kind = "empty"
    -- The item frame's IsShown is constant-true when hide-when-inactive is off, so
    -- only the viewer's own IsShown can tell a hidden viewer from a drawn one.
    elseif state.lastAt and state.viewers > 0 and state.viewersShown == 0 then
      health.kind = "hidden"
    elseif state.lastAt and #state.order == 0 then
      health.kind = "empty"
    else
      -- "unknown" (never evaluated), "ok" (evaluated, healthy) and an absent value
      -- have to stay three different things to a reader.
      health.kind = "ok"
    end
  end

  state.health = health
  for i = 1, #watchers do
    local ok, err = pcall(watchers[i], health, why)
    if not ok then ns.Emit("bind watcher errored: " .. tostring(err)) end
  end
  return health
end

-- Runs in combat too, deliberately: every client call on this path is a pcall'd getter, so
-- there is nothing here a lockdown protects, and the viewer releases its whole item-frame
-- pool mid-pull. A resolve that waited for regen would leave every consumer holding frames
-- that now serve other rows. `state.deferred` counts refusals and should read 0.
local function resolve(reason)
  local rows, order = {}, {}
  local frames, viewersSeen, unreadable, complete = 0, 0, 0, true
  local viewersShown = 0
  -- ⚠ `observed` and `complete` are NOT the same claim, and conflating them disabled the whole
  -- addon on 2026-08-23. `complete` means every frame was understood; `observed` means the sweep
  -- FINISHED — every viewer answered and there was something to look at. A frame cap cannot map
  -- to a spell (a trinket, an item, a row from another addon) makes the first false forever,
  -- because it is never going to become readable. Gating the settle on `complete` therefore meant
  -- ONE unrecognised row in the player's Cooldown Manager left cap permanently dark, with no
  -- message, on a roster it had already bound and evaluated correctly.
  local observed = true
  local unreadableAt = {}

  for _, v in ipairs(VIEWERS) do
    local viewer = _G[v.global]
    local list
    if viewer then
      local shown, shownClass = readField(viewer, "IsShown")
      if shownClass == "plain" and shown then viewersShown = viewersShown + 1 end
      local ok, result = pcall(viewer.GetItemFrames, viewer)
      if ok and type(result) == "table" then list = result end
    end
    if not list then
      complete = false
      observed = false
    else
      viewersSeen = viewersSeen + 1
      for i = 1, #list do
        local frame = list[i]
        frames = frames + 1
        local cooldownID, class = readField(frame, "GetCooldownID")
        if class == "plain" then
          if not rows[cooldownID] then
            local row = buildRow(v, frame, cooldownID, i)
            if row then
              rows[cooldownID] = row
              order[#order + 1] = row
            else
              unreadable = unreadable + 1
              complete = false
              unreadableAt[#unreadableAt + 1] = v.short .. ":" .. i .. ":norow"
            end
          end
        elseif class ~= "empty" then
          unreadable = unreadable + 1
          complete = false
          unreadableAt[#unreadableAt + 1] = v.short .. ":" .. i .. ":" .. tostring(class)
        end
      end
    end
  end

  -- Nothing observed is not the same as nothing there.
  if frames == 0 then complete = false; observed = false end

  state.rows, state.order = rows, order
  state.frames, state.viewers, state.viewersShown, state.unreadable, state.complete =
    frames, viewersSeen, viewersShown, unreadable, complete
  state.observed = observed
  state.unreadableAt = table.concat(unreadableAt, ",")
  state.lastAt, state.lastReason = GetTime(), reason
  state.pending, state.pendingReason = false, nil
  state.deferredLast, state.deferred = state.deferred, 0

  local signature = signatureOf(order)
  if signature ~= state.signature then
    state.signature = signature
    state.generation = state.generation + 1
    notify()
  end
  evaluate(reason)
  return "ran"
end

local function schedule(reason)
  state.pending = true
  state.pendingReason = reason
  if resolveTimerArmed then return end
  resolveTimerArmed = true
  C_Timer.After(RESOLVE_DELAY, function()
    resolveTimerArmed = false
    if state.pending then resolve(state.pendingReason or "timer") end
  end)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
    -- Both edges resolve. A pull that changed nothing produces two identical readings,
    -- which is the point: identical is a finding, and absent is not.
    schedule(state.pendingReason or event)
    return
  end
  -- The CDM loads its data asynchronously, so the first health verdict waits. The
  -- timer is what guarantees one health sample taken after that load, whether or
  -- not any other event happens to land.
  if event == "PLAYER_ENTERING_WORLD" and not graceStarted then
    graceStarted = true
    C_Timer.After(LOGIN_GRACE, function()
      evaluate("login-grace")
    end)
  end
  schedule(event)
end)

-- COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED is the fast path only: it fires
-- redundantly and may have fired before we loaded, so every bind re-polls
-- (cooldown-manager.md rule 9).
for _, event in ipairs({
  "PLAYER_ENTERING_WORLD",
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
  "SPELLS_CHANGED",
  "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
  "TRAIT_CONFIG_UPDATED",
  "ACTIVE_COMBAT_CONFIG_CHANGED",
  "COOLDOWN_VIEWER_DATA_LOADED",
  "COOLDOWN_VIEWER_TABLE_HOTFIXED",
  "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",
}) do
  watcher:RegisterEvent(event)
end
watcher:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")

-- ---------------------------------------------------------------------------
-- The read API
-- ---------------------------------------------------------------------------

local Bind = {}
ns.Bind = Bind

-- The live array, in viewer order. Treat as read-only.
function Bind.Rows()
  return state.order
end

-- Returns the item frame and whether the binding was confirmed this call. An
-- unconfirmable frame is still returned; a frame confirmed to belong to another
-- row is not, and forces a rebind.
function Bind.ItemFrame(cooldownID)
  local row = state.rows[cooldownID]
  if not row or not row.frame then return nil, false end
  local live, class = readField(row.frame, "GetCooldownID")
  if class == "plain" then
    if live == cooldownID then return row.frame, true end
    -- Drop it, don't just decline to return it: `Bind.Rows()` hands the same table to
    -- Sense, Anchor and Overlay, and a frame confirmed to be serving another row is
    -- wrong for all of them until the rebind lands.
    row.frame = nil
    schedule("frame-repooled")
    return nil, false
  end
  return row.frame, false
end

function Bind.Generation()
  return state.generation
end

-- One plain table per bound row, in viewer order. Snapshot counts rows; this says WHICH,
-- and without it a reader can check the binding is populous but never that it is correct.
-- Every field was fenced through plain() or readField at construction, so none can be secret.
function Bind.RowDigest()
  local out = {}
  for i = 1, #state.order do
    local row = state.order[i]
    out[i] = {
      cooldownID = row.cooldownID,
      viewer = row.short,
      slot = row.index,
      primary = row.primary,
      base = row.base,
      override = row.override,
      tooltip = row.tooltip,
      live = row.live,
      isKnown = row.isKnown,
      pool = (#row.pool > 0) and table.concat(row.pool, ",") or nil,
    }
  end
  return out
end

-- A flat plain-Lua copy: no frames and no reference into state, so a consumer may
-- hold or serialise it without pinning a game object.
function Bind.Snapshot()
  local health = state.health or {}

  local counts = {}
  for _, row in ipairs(state.order) do
    counts[row.short] = (counts[row.short] or 0) + 1
  end
  -- An array in VIEWERS order, never a map: this renders into a dedup key, and
  -- pairs() order is unstable, so a map would break dedup nondeterministically.
  local byViewer = {}
  for i = 1, #VIEWERS do
    byViewer[i] = { short = VIEWERS[i].short, count = counts[VIEWERS[i].short] or 0 }
  end

  return {
    rows = #state.order,
    byViewer = byViewer,
    frames = state.frames,
    viewers = state.viewers,
    generation = state.generation,
    complete = state.complete,
    observed = state.observed,
    unreadable = state.unreadable,
    unreadableAt = state.unreadableAt,
    pending = state.pending,
    deferredLast = state.deferredLast,
    lastAt = state.lastAt,
    reason = state.lastReason,
    kind = health.kind,
    detail = health.detail,
    viewersShown = health.viewersShown,
    configured = health.configured,
    configuredOk = health.configuredOk,
  }
end

function Bind.Resolve(reason)
  return resolve(reason or "manual")
end

-- Re-runs the verdict only; the rows are left exactly as the last resolve left them.
function Bind.Evaluate(why)
  return evaluate(why or "manual")
end

function Bind.OnChanged(fn)
  listeners[#listeners + 1] = fn
  return fn
end

-- Fires on every evaluation, moved or not. Not a widened OnChanged, and must not
-- be merged into one: OnChanged promises the row signature moved, so a row
-- listener may assume the rows differ. Folding sampling in would make every such
-- listener re-do its work on samples that changed nothing.
function Bind.OnEvaluated(fn)
  watchers[#watchers + 1] = fn
  return fn
end
