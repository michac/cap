-- Bind.lua — which Cooldown Manager icon is which ability, kept correct across
-- spec, talent and hero-tree changes.
--
-- Identity resolves out of combat only. A value that reads secret or throws is
-- "no answer", never "no ability": the previous binding is kept and the pass is
-- reported partial. See knowledge/addon-dev/cooldown-manager.md rules 2, 9, 15.
--
-- Registers its own commands and `/cap status` line — never edits Core.lua.
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
local WARN_CAP = 3

local MESSAGES = {
  ["no-addon"] = "Blizzard's Cooldown Manager UI is not loaded, so there is nothing to bind to. cap will stay dark.",
  ["unavailable"] = "the Cooldown Manager reports itself unavailable. cap needs it and will stay dark.",
  ["disabled"] = "the Cooldown Manager is turned off. Turn it on in Options and cap will bind on its own.",
  ["empty"] = "the Cooldown Manager is on but tracks nothing on this spec. Add cooldowns to it; cap has nothing to bind to until you do.",
  ["hidden"] = "the Cooldown Manager has cooldowns configured but is drawing no rows. Check its Edit Mode placement and visibility; cap binds to what is drawn.",
}

local state = {
  rows = {},      -- cooldownID -> row
  order = {},     -- rows in viewer order, retained-stale rows last
  bySpell = {},   -- spellID -> rows, from the rule-15 union
  byPool = {},    -- spellID -> rows, from linkedSpellIDs
  generation = 0,
  signature = "",
  frames = 0,
  viewers = 0,
  unreadable = 0,
  complete = false,
  pending = false,
  pendingReason = nil,
  lastAt = nil,
  lastReason = nil,
  armed = false,
  health = { kind = "unknown" },
}

local listeners = {}
local combatFlag = false
local warnedKind, warnCount = nil, 0
local resolveTimerArmed = false
local graceStarted = false

-- ---------------------------------------------------------------------------
-- Reading values that may be secret
-- ---------------------------------------------------------------------------

local function plain(v)
  if v == nil then return false end
  return not issecretvalue(v)
end

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

local function inCombat()
  return combatFlag or InCombatLockdown()
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
    stale = false,
  }
end

local function reindex()
  local bySpell, byPool = {}, {}
  for _, row in ipairs(state.order) do
    for id in pairs(row.spellIDs) do
      local t = bySpell[id]
      if not t then t = {}; bySpell[id] = t end
      t[#t + 1] = row
    end
    for _, id in ipairs(row.pool) do
      local t = byPool[id]
      if not t then t = {}; byPool[id] = t end
      t[#t + 1] = row
    end
  end
  state.bySpell, state.byPool = bySpell, byPool
end

local function signatureOf(order)
  local parts = {}
  for i = 1, #order do
    local row = order[i]
    parts[i] = row.cooldownID .. ":" .. row.primary .. ":" .. (row.stale and "s" or "f")
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
    if ok and type(set) == "table" then
      answered = true
      total = total + #set
    end
  end
  return total, answered
end

local function announce(health)
  if not state.armed then return end
  if not health.kind then warnedKind = nil; return end
  if health.kind == warnedKind then return end
  warnedKind = health.kind
  if warnCount >= WARN_CAP then return end
  warnCount = warnCount + 1
  local msg = MESSAGES[health.kind] or ("the Cooldown Manager is not usable (" .. tostring(health.kind) .. ").")
  if health.detail then msg = msg .. " (" .. health.detail .. ")" end
  ns.Emit(msg)
  if warnCount == WARN_CAP then
    ns.Emit("further Cooldown Manager warnings suppressed — /cap status carries the current state.")
  end
end

local function evaluate()
  local health = { rows = #state.order, frames = state.frames, viewers = state.viewers }
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
    elseif state.lastAt and state.frames == 0 then
      health.kind = "hidden"
    elseif state.lastAt and #state.order == 0 then
      health.kind = "empty"
    end
  end

  state.health = health
  announce(health)
  return health
end

local function resolve(reason)
  if inCombat() then
    state.pending = true
    state.pendingReason = reason
    return "queued"
  end

  local rows, order = {}, {}
  local frames, viewersSeen, unreadable, complete = 0, 0, 0, true

  for _, v in ipairs(VIEWERS) do
    local viewer = _G[v.global]
    local list
    if viewer then
      local ok, result = pcall(viewer.GetItemFrames, viewer)
      if ok and type(result) == "table" then list = result end
    end
    if not list then
      complete = false
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
            end
          end
        elseif class ~= "empty" then
          unreadable = unreadable + 1
          complete = false
        end
      end
    end
  end

  -- Nothing observed is not the same as nothing there.
  if frames == 0 then complete = false end

  if not complete then
    for cooldownID, row in pairs(state.rows) do
      if not rows[cooldownID] then
        row.stale = true
        rows[cooldownID] = row
        order[#order + 1] = row
      end
    end
  end

  state.rows, state.order = rows, order
  state.frames, state.viewers, state.unreadable, state.complete = frames, viewersSeen, unreadable, complete
  state.lastAt, state.lastReason = GetTime(), reason
  state.pending, state.pendingReason = false, nil
  reindex()

  local signature = signatureOf(order)
  if signature ~= state.signature then
    state.signature = signature
    state.generation = state.generation + 1
    notify()
  end
  evaluate()
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
  if event == "PLAYER_REGEN_DISABLED" then
    combatFlag = true
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    combatFlag = false
    if state.pending then schedule(state.pendingReason or event) end
    return
  end
  -- The CDM loads its data asynchronously, so the first health verdict waits.
  if event == "PLAYER_ENTERING_WORLD" and not graceStarted then
    graceStarted = true
    combatFlag = InCombatLockdown()
    C_Timer.After(LOGIN_GRACE, function()
      state.armed = true
      evaluate()
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

local function copy(list)
  local out = {}
  for i = 1, #list do out[i] = list[i] end
  return out
end

local Bind = {}
ns.Bind = Bind

-- The live array, in viewer order. Treat as read-only.
function Bind.Rows()
  return state.order
end

function Bind.Row(cooldownID)
  return state.rows[cooldownID]
end

-- Rows answering to a spellID. The default union is base + static overrides +
-- the resolved live id (rule 15); `includePool` widens it to linkedSpellIDs,
-- which matches aura ids but also matches rows that only ever cast them.
function Bind.RowsForSpell(spellID, includePool)
  local hits = state.bySpell[spellID]
  local out = hits and copy(hits) or {}
  if includePool then
    local seen = {}
    for i = 1, #out do seen[out[i]] = true end
    for _, row in ipairs(state.byPool[spellID] or {}) do
      if not seen[row] then out[#out + 1] = row end
    end
  end
  return out
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
    schedule("frame-repooled")
    return nil, false
  end
  return row.frame, false
end

function Bind.Generation()
  return state.generation
end

function Bind.Health()
  return state.health
end

function Bind.Resolve(reason)
  return resolve(reason or "manual")
end

function Bind.OnChanged(fn)
  listeners[#listeners + 1] = fn
  return fn
end

-- ---------------------------------------------------------------------------
-- Reporting
-- ---------------------------------------------------------------------------

local function specLabel()
  local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
  local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
  local name = "?"
  if getSpec and getInfo then
    local okIndex, index = pcall(getSpec)
    if okIndex and plain(index) then
      local okInfo, _, specName = pcall(getInfo, index)
      if okInfo and type(specName) == "string" then name = specName end
    end
  end

  local talents = C_ClassTalents
  if talents and talents.GetActiveHeroTalentSpec then
    local okHero, subTreeID = pcall(talents.GetActiveHeroTalentSpec)
    if okHero and plain(subTreeID) then
      local hero = tostring(subTreeID)
      local okConfig, configID = pcall(talents.GetActiveConfigID)
      if okConfig and plain(configID) and C_Traits and C_Traits.GetSubTreeInfo then
        local okTree, info = pcall(C_Traits.GetSubTreeInfo, configID, subTreeID)
        if okTree and type(info) == "table" and type(info.name) == "string" then hero = info.name end
      end
      name = name .. " (" .. hero .. ")"
    end
  end
  return name
end

local function breakdown()
  local counts, stale = {}, 0
  for _, v in ipairs(VIEWERS) do counts[v.short] = 0 end
  for _, row in ipairs(state.order) do
    counts[row.short] = (counts[row.short] or 0) + 1
    if row.stale then stale = stale + 1 end
  end
  local parts = {}
  for _, v in ipairs(VIEWERS) do parts[#parts + 1] = v.short .. " " .. counts[v.short] end
  return table.concat(parts, " "), stale
end

local function ago(when)
  if not when then return "never" end
  local delta = GetTime() - when
  if delta < 1 then return "just now" end
  return ("%ds ago"):format(math.floor(delta))
end

ns.RegisterStatus(30, function()
  local health = state.health or {}
  local counts, stale = breakdown()
  local parts = {}

  if health.kind == "unknown" then
    parts[#parts + 1] = "cdm: not resolved yet"
  elseif health.kind then
    parts[#parts + 1] = ("cdm: NOT USABLE (%s%s) — holding %d rows"):format(
      health.kind, health.detail and (": " .. health.detail) or "", #state.order)
  else
    parts[#parts + 1] = ("cdm: bound — %d rows on %d viewers (%s)"):format(
      #state.order, state.viewers, counts)
  end

  parts[#parts + 1] = specLabel()
  parts[#parts + 1] = ("resolved %s after %s, gen %d"):format(
    ago(state.lastAt), tostring(state.lastReason or "-"), state.generation)

  if state.lastAt and not state.complete then
    parts[#parts + 1] = ("PARTIAL — %d unreadable, %d rows kept from the last good pass"):format(
      state.unreadable, stale)
  end
  if state.pending then
    parts[#parts + 1] = "rebind queued" .. (inCombat() and " (in combat)" or "")
  end
  if health.configuredOk then
    parts[#parts + 1] = ("%d in the CDM set, %d frames walked"):format(health.configured, state.frames)
  end

  return table.concat(parts, " · ")
end)

-- The per-row detail this module can report is a DUMP, and a dump is a button on
-- the `/cap dump` panel writing to the capture stream — never a slash subcommand
-- printing to chat, which has no copy/paste and so cannot leave the client.
-- House rule 4. Until that panel exists, `/cap status` is the whole surface.

