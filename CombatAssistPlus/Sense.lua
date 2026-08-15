-- Sense.lua — the impure half of the readable signal: hooks, clock and client reads.
--
-- Everything that decides anything lives in Track and Signal, which are pure and tested at
-- a desk. This file installs one alert hook per item frame, seeds the out-of-combat
-- baseline, asks the client for the gates Track cannot observe, and writes what came back
-- to the capture log. It draws nothing.
--
-- Which client read answers which gate, and why that one rather than the obvious one:
-- knowledge/addon-dev/cooldown-manager.md §5.1 and §7, and
-- security-taint-and-restricted-data.md §4.8.4 and §4.12.
local ADDON, ns = ...

local issecretvalue, issecrettable = issecretvalue, issecrettable

local TICK = 0.1
-- The GCD is reported as a cooldown, so a duration at or below it is not one. Reading a
-- baseline inside the 1.5 s after any cast would otherwise record the whole roster as
-- on cooldown (cooldown-manager.md §5.1).
local GCD_FLOOR = 1.5
-- Only for the identical-row-set case, where the generation never moves and the
-- event-driven arm can never fire. Long on purpose: in the first seconds after a hero
-- swap the generation is quiet BECAUSE the rebuild has not started, which is the state
-- the settle exists to survive.
local QUIET_SETTLE = 8

ns.Sense = ns.Sense or {}
local Sense = ns.Sense

local tierStream = ns.Capture.Open("tier", { sessions = 8, cap = 2000, dedup = false })
local edgeStream = ns.Capture.Open("edge", { sessions = 8, cap = 4000, dedup = false })

local state = {
  catalog = nil,
  bound = nil,
  reads = nil,
  track = nil,
  label = nil,
  settled = false,
  settledBy = nil,
  unsettledAt = nil,
  unsettledGen = nil,
  dark = false,
  combat = false,
  power = nil,
  hooks = 0,
  edges = 0,
  refused = 0,
  duplicates = 0,
}

-- ---------------------------------------------------------------------------
-- Reading values that may be secret
-- ---------------------------------------------------------------------------

local function plain(v)
  if v == nil then return false end
  return not issecretvalue(v)
end

--- A struct read that refuses rather than guessing. `nil` means "no answer", which is
--- what every caller here turns into an unknown gate.
local function field(t, key)
  if type(t) ~= "table" or issecrettable(t) then return nil end
  local ok, v = pcall(function() return t[key] end)
  if not ok or not plain(v) then return nil end
  return v
end

local function readProc(spellID)
  if not (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) then return nil end
  local ok, v = pcall(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
  if not ok or not plain(v) then return nil end
  return v and true or false
end

--- The live cooldown-info struct for a row, fetched once per cid per tick. Both the identity
--- gate and the live spell id derive from it, and they must come from the SAME read.
local function readInfo(cid)
  if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return nil end
  local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cid)
  if not ok then return nil end
  return { base = field(info, "spellID"), override = field(info, "overrideSpellID") }
end

-- The honest test is `overrideSpellID ~= spellID`, never `~= nil`: the field is always
-- populated and mirrors the base when nothing is overriding. Both sides come from the
-- SAME live struct — comparing against the id bound out of combat would call a permanent
-- spec override a transform.
local function readIdentity(info)
  if info == nil or info.base == nil or info.override == nil then return nil end
  if info.override ~= info.base then return "transformed" end
  return "base"
end

--- At max charges — readable in BOTH polarities, unlike the count itself.
---
--- `C_Spell.GetSpellCharges` seals per member: `currentCharges` goes secret below full, but
--- `isActive` is NeverSecret and means "a recharge is running", which is exactly "not at max".
--- `nil` for a spell with no charges, and `nil` — never `false` — when the struct refuses.
local function readCapped(spellID)
  if not (C_Spell and C_Spell.GetSpellCharges) then return nil end
  local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
  if not ok then return nil end
  local maximum = field(info, "maxCharges")
  if type(maximum) ~= "number" or maximum <= 1 then return nil end
  local active = field(info, "isActive")
  if active == nil then return nil end
  return not active
end

--- Can the player pay for this right now. The SECOND return of `C_Spell.IsSpellUsable` is
--- `insufficientPower`, which is the only one that means affordability — `isUsable` is false for
--- a spell merely on cooldown, which the lane border already says. `AllowedWhenTainted`, so this
--- answers in combat. `nil` — never `false` — when the call refuses, so a refused read is unknown.
local function readAffordable(spellID)
  if not (C_Spell and C_Spell.IsSpellUsable) then return nil end
  local ok, _, insufficientPower = pcall(C_Spell.IsSpellUsable, spellID)
  if not ok then return nil end
  if type(insufficientPower) ~= "boolean" then return nil end
  return not insufficientPower
end

--- Current and max for the catalog's declared power type. A primary resource is always
--- secret, so the class check is the guard rather than a list of type names.
local function readResource()
  local t = state.power
  if t == nil or not UnitPower then return nil, nil end
  local okV, v = pcall(UnitPower, "player", t)
  local okM, m = pcall(UnitPowerMax, "player", t)
  local have = (okV and plain(v) and type(v) == "number") and v or nil
  local max = (okM and plain(m) and type(m) == "number") and m or nil
  return have, max
end

--- Readiness out of combat only — `C_Spell.GetSpellCooldown` is secret in combat.
local function readCooldown(spellID)
  if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
  local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
  if not ok then return nil end
  local start = field(info, "startTime")
  local duration = field(info, "duration")
  if type(start) ~= "number" or type(duration) ~= "number" then return nil end
  if duration <= GCD_FLOOR then return true end
  return (start + duration - GetTime()) <= 0
end

local function readCharges(spellID)
  if not (C_Spell and C_Spell.GetSpellCharges) then return nil end
  local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
  if not ok then return nil end
  local current = field(info, "currentCharges")
  local maximum = field(info, "maxCharges")
  local recharge = field(info, "cooldownDuration")
  if type(current) ~= "number" or type(maximum) ~= "number" then return nil end
  -- Duration is best-effort: a full-charge seed is still exact even when this is zero,
  -- and Track retains the last positive measurement for duplicate filtering.
  if type(recharge) ~= "number" or recharge <= 0 then recharge = nil end
  return current, maximum, recharge
end

-- ---------------------------------------------------------------------------
-- The alert hook
-- ---------------------------------------------------------------------------

-- Weak-keyed and never cleared per rebind: `hooksecurefunc` cannot be removed, and item
-- frames are pooled, so re-hooking on every bind stacks N hooks on one frame and grows
-- with every spec swap. Once per frame object ever, for the life of the session.
local hooked = setmetatable({}, { __mode = "k" })

local EDGE_NAMES = {}
do
  local E = Enum and Enum.CooldownViewerAlertEventType
  if E then
    EDGE_NAMES[E.Available] = "Available"
    EDGE_NAMES[E.OnCooldown] = "OnCooldown"
    EDGE_NAMES[E.ChargeGained] = "ChargeGained"
    EDGE_NAMES[E.OnAuraApplied] = "OnAuraApplied"
    EDGE_NAMES[E.OnAuraRemoved] = "OnAuraRemoved"
  end
end

local evaluate

-- A refused cid is logged ONCE and counted thereafter. The count alone cannot tell
-- "correctly ignoring a silenced row" from "resolving the wrong cid", and those are the
-- pass and the fail of the same criterion; the identity can, and every viewer raises
-- these on every row, so logging each occurrence would drown the stream.
local refusedSeen = {}

local function onAlert(frame, event)
  local name = EDGE_NAMES[event]
  if not name or not state.track then return end

  -- Resolved INSIDE the callback, never closed over: the frame this hook was installed
  -- on may since have been recycled onto a different row.
  local ok, cid = pcall(frame.GetCooldownID, frame)
  if not ok or type(cid) ~= "number" or issecretvalue(cid) then return end

  local now = GetTime()
  local landed, refusedWhy = state.track:Edge(now, cid, name)
  if landed then
    state.edges = state.edges + 1
    edgeStream:Line(("t%.1f %s cid:%d"):format(now, name, cid))
    evaluate(now, "edge")
  elseif refusedWhy == "duplicate" then
    state.duplicates = state.duplicates + 1
    edgeStream:Line(("t%.1f duplicate %s cid:%d"):format(now, name, cid))
  else
    state.refused = state.refused + 1
    if not refusedSeen[cid] then
      refusedSeen[cid] = true
      edgeStream:Line(("t%.1f refused cid:%d first:%s"):format(now, cid, name))
    end
  end
end

local function installHooks()
  if not ns.Bind then return 0 end
  local added = 0
  for _, row in ipairs(ns.Bind.Rows()) do
    local frame = row.frame
    if frame and not hooked[frame] and type(frame.TriggerAlertEvent) == "function" then
      hooked[frame] = true
      hooksecurefunc(frame, "TriggerAlertEvent", onAlert)
      added = added + 1
    end
  end
  state.hooks = state.hooks + added
  return added
end

-- ---------------------------------------------------------------------------
-- Rendering — pure, and IS the dedup key
-- ---------------------------------------------------------------------------

local function num(v)
  if v == nil or issecretvalue(v) or type(v) ~= "number" then return "?" end
  return tostring(math.floor(v))
end

-- `Capture.Safe` is necessary and not sufficient for a space-delimited line: it leaves
-- internal whitespace ("Demonology / Diabolist") and braces, which split a field or
-- forge a group boundary.
local function token(v)
  local s = ns.Capture.Safe(v):gsub("%s+", "_"):gsub("[{}|]", "")
  if s == "" then return "?" end
  return s
end

local function pair(t)
  if not t then return "-" end
  return num(t.known) .. "/" .. num(t.known + t.unknown)
end

local PREDICATE_ORDER = { "ready", "proc", "identity", "capped", "affordable", "resource" }

--- The body a line carries. No clock, no game reads, no `pairs()` over anything whose
--- order would move — a key that reorders breaks dedup nondeterministically.
function Sense.Render(snap)
  snap = snap or {}
  local out = snap.out or {}
  local health = snap.health or {}

  local t = {
    "n:" .. num(snap.entries),
    "on:" .. num(out.emphasized),
    "mark:" .. num(out.markers),
    "blind:" .. num(out.unknowns),
  }

  local entries = {}
  for _, id in ipairs(snap.order or {}) do
    local v = (out.byEntry or {})[id]
    if v then
      local marks = (#(v.markers or {}) > 0) and ("+" .. table.concat(v.markers, ",")) or ""
      entries[#entries + 1] = id .. ":" .. (v.tier or "off") .. marks
    end
  end

  local g = {}
  for _, name in ipairs(PREDICATE_ORDER) do
    g[#g + 1] = name .. ":" .. pair((health.predicates or {})[name])
  end

  local s = { snap.settled and ("settled/" .. token(snap.settledBy)) or "unsettled" }
  if snap.dark then s[#s + 1] = "DARK" end

  return "S{" .. table.concat(t, " ") .. "}"
    .. " E{" .. (#entries > 0 and table.concat(entries, " ") or "-") .. "}"
    .. " R{" .. table.concat(g, " ") .. "}"
    .. " Q{" .. (#(snap.charges or {}) > 0 and table.concat(snap.charges, " ") or "-") .. "}"
    .. " S{" .. table.concat(s, " ") .. "}"
end

-- ---------------------------------------------------------------------------
-- Evaluation
-- ---------------------------------------------------------------------------

local lastBody

local function buildReads()
  local proc, identity, capped, affordable = {}, {}, {}, {}
  local byAbility = (state.reads or {}).byAbility or {}
  local infoOf = {}

  for _, item in ipairs(state.bound.abilities) do
    local id, needs = item.ability.id, byAbility[item.ability.id] or {}
    local cid = item.row.cooldownID
    if needs.identity or needs.capped or needs.affordable then
      if infoOf[cid] == nil then infoOf[cid] = readInfo(cid) or false end
    end
    local info = infoOf[cid] or nil
    -- `row.primary` froze at bind and `Bind.resolve` refuses to run in combat, so a demon-form
    -- flip moves the live id underneath it. Charges and usability are asked about the LIVE one.
    local live = (info and info.override) or item.row.primary

    if needs.proc then proc[id] = readProc(item.row.primary) end
    if needs.identity then identity[id] = readIdentity(info) end
    if needs.capped then capped[id] = readCapped(live) end
    if needs.affordable then affordable[id] = readAffordable(live) end
  end

  local have, max = readResource()
  return {
    proc = proc, identity = identity, capped = capped, affordable = affordable,
    resource = have, resourceMax = max,
    needsResource = state.reads and state.reads.resource,
  }
end

local rowSeq = 0

local function write(snap, body, why, edge)
  local text = ("t%.1f "):format(GetTime())
    .. (edge and ("# " .. edge .. " ") or "") .. body .. " why:" .. token(why)
  if edge then tierStream:Mark(text) else tierStream:Line(text) end
  -- Spent only once the line can have landed: the stream DROPS every write while `ns.db`
  -- is unset, and burning the dedup key on a dropped line suppresses the first real one.
  if ns.db then lastBody = body end

  rowSeq = rowSeq + 1
  local health = snap.health or {}
  local row = {
    rec = "signal", t = GetTime(), seq = rowSeq, why = why,
    entries = snap.entries, emphasized = (snap.out or {}).emphasized,
    markers = (snap.out or {}).markers,
    blind = (snap.out or {}).unknowns,
    settled = snap.settled, settledBy = snap.settledBy, dark = snap.dark,
    combat = state.combat,
    chargeProvenance = table.concat(snap.charges or {}, ","),
  }
  for _, name in ipairs(PREDICATE_ORDER) do
    local slot = (health.predicates or {})[name]
    if slot then
      row["g_" .. name] = slot.known
      row["u_" .. name] = slot.unknown
    end
  end
  tierStream:Row(row)

  tierStream:Meta("catalog", state.catalog and token(state.catalog.name) or "-")
  tierStream:Meta("settled", tostring(snap.settled))
  tierStream:Meta("edges", state.edges)
  tierStream:Meta("edgesRefused", state.refused)
  tierStream:Meta("chargeDuplicates", state.duplicates)
  tierStream:Meta("hooks", state.hooks)
  tierStream:Meta("samples", rowSeq)
end

local verdictListeners = {}
local listenerFailed = {}
local listenerErrors = 0

--- Subscribe a surface to the verdicts. Fired at the end of every recompute with
--- `Sense.Verdicts()`'s answer plus the edge that caused it, so cap has ONE clock and a
--- surface never opens a second — nor a second set of combat events to learn the edge.
function Sense.OnVerdicts(fn)
  verdictListeners[#verdictListeners + 1] = fn
  return fn
end

--- Fired on the early return too: a spec swap into a catalog-less build drops `bound`, and
--- a surface that never hears about it keeps the last roster lit forever. Each listener is
--- PROTECTED — this runs inside the 10 Hz tick and inside a posthook on Blizzard's alert
--- path, where a bare error re-throws forever. Reported once per listener, counted after.
local function fireVerdicts(edge)
  local out, bound = Sense.Verdicts()
  for i = 1, #verdictListeners do
    local ok, err = pcall(verdictListeners[i], out, bound, edge)
    if not ok then
      listenerErrors = listenerErrors + 1
      tierStream:Meta("listenerErrors", listenerErrors)
      if not listenerFailed[i] then
        listenerFailed[i] = true
        ns.Emit("verdict listener " .. i .. " errored: " .. tostring(err))
        tierStream:Mark(("t%.1f # listener-error i:%d %s"):format(GetTime(), i, token(err)))
      end
    end
  end
end

--- One recompute. `edge` marks a transition the log exists to record, so it is written
--- whether or not the body moved — a bare marker against an unchanged state emits no
--- numbers, and unchanged is often the case a flight confirms.
function evaluate(now, why, edge)
  if not (state.bound and state.track and ns.db) then
    fireVerdicts(edge)
    return
  end

  local world, health = state.track:World(now, buildReads())
  local out = ns.Signal.Evaluate(state.bound, world)

  local charges = {}
  for _, id in ipairs(state.chargeOrder or {}) do
    charges[#charges + 1] = id .. ":" .. (world.chargeProvenance[id] or "unknown")
  end

  local snap = {
    entries = #state.bound.entries,
    order = state.order,
    out = out, health = health,
    settled = state.settled, settledBy = state.settledBy,
    dark = state.dark, charges = charges,
  }
  local body = Sense.Render(snap)
  if edge or body ~= lastBody then write(snap, body, why, edge) end
  state.lastOut = out
  fireVerdicts(edge)
  return out
end

--- The one independent bar entry, or nil where no catalog is in force.
function Sense.Roster()
  return state.catalog and state.catalog.bar or nil
end

function Sense.CatalogName()
  return state.catalog and state.catalog.name or nil
end

--- The signal verdicts a surface should draw, or nil when cap must draw nothing. The one
--- place the settle and the dark-for-the-fight rule are enforced, rather than re-derived
--- once per surface.
function Sense.Verdicts()
  if not (state.bound and state.settled and not state.dark) then return nil end
  return state.lastOut, state.bound
end

-- ---------------------------------------------------------------------------
-- Binding, and the settle
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

local function report(kind, findings)
  for _, f in ipairs(findings) do
    tierStream:Mark(("t%.1f # %s %s entry:%s %s"):format(
      GetTime(), kind, token(f.check), token(f.entry), token(f.detail)))
  end
end

--- Seeded out of combat only, and it exists for exactly one case: a /reload mid-combat
--- has no baseline at all, and both defaults are wrong. A row the client will not answer
--- for is left unknown rather than assumed.
local function seedBaseline()
  for _, item in ipairs(state.bound.abilities) do
    local id = item.ability.id
    local spellID = item.ability.charged and item.ability.spell or item.row.primary
    if item.ability.charged then
      local current, maximum, recharge = readCharges(spellID)
      if current then state.track:SeedCharges(id, current, maximum, recharge) end
    else
      state.track:SeedReady(item.row.cooldownID, readCooldown(spellID))
    end
  end
end

local function rebind(generation)
  local specID, hero = specAndHero()
  local cat = ns.Catalog.ForBuild(specID, hero)

  local label = tostring(specID) .. "/" .. tostring(hero)
  if label ~= state.label then
    state.label = label
    state.settled = false
    state.settledBy = nil
    state.unsettledAt = GetTime()
    state.unsettledGen = generation
    tierStream:Mark(("t%.1f # config spec:%s hero:%s catalog:%s"):format(
      GetTime(), token(specID), token(hero), cat and token(cat.name) or "-"))
  end

  if not cat then
    -- spec.md §3.5: no catalog, nothing at all — and the reason goes to the log and
    -- nowhere else. A chat line at every login for a permanent property of the build
    -- is noise, and the one state a player could act on raises none of cap's events.
    state.catalog, state.bound, state.track, state.order, state.chargeOrder = nil, nil, nil, nil, nil
    return
  end

  if cat ~= state.catalog then
    -- Check 5 disclosures ride the same reporter and cannot fail.
    local findings = ns.Catalog.Check(cat)
    report("check", findings)
    state.reads = ns.Catalog.Reads(cat)
    state.power = Enum and Enum.PowerType and cat.power and Enum.PowerType[cat.power] or nil
  end
  state.catalog = cat

  local rows = ns.Bind.Rows()
  local findings, resolved = ns.Catalog.CheckBound(cat, rows)
  report("bound", findings)
  for _, d in ipairs(resolved.dropped) do
    tierStream:Mark(("t%.1f # dropped entry:%s spell:%s %s"):format(
      GetTime(), token(d.id), token(d.spell), token(d.why)))
  end

  -- A DIAGNOSTIC, never a hint: it says this player's Cooldown Manager is ordered in a way
  -- the catalog's reading model does not hold for, and says nothing about what to press.
  local out = ns.Catalog.OrderCheck(cat, resolved, rows)
  local told = out and (out.before .. ">" .. out.after) or nil
  if told ~= state.orderTold then
    state.orderTold = told
    if told then
      ns.Log.Note(("row-order %s is laid out after %s; this catalog reads left-to-right in "
        .. "priority order"):format(out.before, out.after))
      ns.Emit("your Cooldown Manager orders " .. out.after .. " before " .. out.before
        .. ", which is not this catalog's priority order — read the row with that in mind.")
    end
  end

  state.bound = resolved
  state.order = {}
  state.chargeOrder = {}
  for _, item in ipairs(resolved.entries) do state.order[#state.order + 1] = item.entry.id end
  for _, item in ipairs(resolved.abilities) do
    if item.ability.charged then state.chargeOrder[#state.chargeOrder + 1] = item.ability.id end
  end
  table.sort(state.order)
  table.sort(state.chargeOrder)

  state.track = ns.Track.New()
  state.track:Bind(ns.Track.Binding(resolved, state.reads))
  refusedSeen = {}
  installHooks()
  if not InCombatLockdown() then seedBaseline() end
end

--- Two arms, both logged, because a flight should be able to delete one. The
--- event-driven arm is the real one; the quiet window exists only for the case where the
--- row set comes back identical and the generation therefore never moves.
local function trySettle(snapshot, why)
  if state.settled or state.combat or not state.bound then return end
  if not snapshot.complete then return end

  if why == "SPELLS_CHANGED" and state.unsettledGen and snapshot.generation > state.unsettledGen then
    state.settled, state.settledBy = true, "spells-changed"
  elseif state.unsettledAt and (GetTime() - state.unsettledAt) >= QUIET_SETTLE then
    state.settled, state.settledBy = true, "quiet"
  else
    return
  end
  tierStream:Mark(("t%.1f # settle by:%s gen:%s"):format(
    GetTime(), state.settledBy, num(snapshot.generation)))
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local lastKind

ns.Bind.OnChanged(function(_, generation)
  rebind(generation)
end)

ns.Bind.OnEvaluated(function(health, why)
  if health.kind ~= lastKind then
    lastKind = health.kind
    tierStream:Mark(("t%.1f # health %s"):format(GetTime(), token(health.kind)))
  end
  if state.bound == nil and state.catalog == nil then rebind(ns.Bind.Generation()) end
  trySettle(ns.Bind.Snapshot(), why)
  if not InCombatLockdown() and state.track and state.bound then seedBaseline() end
  evaluate(GetTime(), why or "evaluate")
end)

-- The combat edges are marks on the edge stream too, not only on `tier`: lines are
-- pre-rendered, so a slice a reader wants later cannot be recovered from a marker that
-- only exists in the other file.
local function markEdgeCombat(edge)
  edgeStream:Mark(("t%.1f # combat %s edges:%d refused:%d hooks:%d"):format(
    GetTime(), edge, state.edges, state.refused, state.hooks))
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:SetScript("OnEvent", function(_, event, unit, _, spellID)
  local now = GetTime()

  if event == "PLAYER_REGEN_DISABLED" then
    state.combat = true
    markEdgeCombat("start")
    -- Unsettled at combat entry means dark for the whole fight: committing to a roster
    -- mid-pull would change what is emphasised while the player is reading it.
    state.dark = not state.settled
    evaluate(now, event, "combat start")
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    state.combat = false
    markEdgeCombat("end")
    state.dark = false
    if state.track and state.bound then seedBaseline() end
    evaluate(now, event, "combat end")
    return
  end

  if event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" and state.track
      and plain(spellID) and type(spellID) == "number" then
    if state.track:CastSpell(now, spellID) then
      edgeStream:Line(("t%.1f cast spell:%d charge:napkin"):format(now, spellID))
      evaluate(now, event, "charge spend")
    end
    return
  end

end)

-- The four client reads raise no event of their own, so an event-only cadence would
-- hold the last verdict until something unrelated happened.
local elapsed = 0
events:SetScript("OnUpdate", function(_, delta)
  elapsed = elapsed + delta
  if elapsed < TICK then return end
  elapsed = 0
  -- The quiet arm has to be driven from here and not only from a Bind evaluation: on a
  -- quiet login nothing resolves again after the login grace, so a settle waiting on the
  -- next resolve would never come and the first pull would be dark.
  if not state.settled then trySettle(ns.Bind.Snapshot()) end
  evaluate(GetTime(), "tick")
end)
