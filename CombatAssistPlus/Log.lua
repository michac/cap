-- Log.lua — the binding state, written to the workspace-standard capture log.
--
-- cap's one output path: `CombatAssistPlusDB.captures.bind`, read with `wowkb.capture
-- cap bind`. One line per change of answer, a marked line on each combat edge.
-- `Log.Render` is pure and IS the dedup key; the wrapper below owns the clock and ring.
local ADDON, ns = ...

local issecretvalue = issecretvalue

ns.Log = ns.Log or {}
local Log = ns.Log

-- dedup = false is deliberate. `Stream:Mark` neither reads nor writes the stream's own
-- `last`, so Line(x) -> Mark(edge) -> Line(x) would drop the state after an edge, which
-- is what this log exists to record; cap dedups below, where a Mark can move the baseline.
-- sessions = 8 prices one verification pass's reloads — deploy, sanity check, fly, extract
-- — plus headroom; CDMProbe went to 6 after its earliest pull rolled off.
local stream = ns.Capture.Open("bind", { sessions = 8, cap = 2000, dedup = false })

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local function plain(v)
  return v ~= nil and not issecretvalue(v)
end

-- `Capture.Safe` leaves whitespace ("Beast Mastery") and braces, which in a space-delimited line split a field or forge a group boundary.
local function token(v)
  local s = ns.Capture.Safe(v):gsub("%s+", "_"):gsub("[{}|]", "")
  if s == "" then return "?" end
  return s
end

-- A digit here has to mean a measurement, so anything else renders "?". The predicate
-- runs before type(): security-taint-and-restricted-data.md §7.
local function num(v)
  if v == nil or issecretvalue(v) or type(v) ~= "number" then return "?" end
  return tostring(math.floor(v))
end

--- The body a Line or a Mark carries — no frames, db, clock or game reads; `spec` and
--- `hero` are resolved by the caller and ride the snapshot. ⚠ No `pairs()`: the key is
--- a string and pairs() order is unstable, which is why `byViewer` is an array.
function Log.Render(snap)
  snap = snap or {}

  local b = { "n:" .. num(snap.rows) }
  for _, v in ipairs(snap.byViewer or {}) do
    b[#b + 1] = token(v.short) .. ":" .. num(v.count)
  end
  b[#b + 1] = "f:" .. num(snap.frames)
  b[#b + 1] = "v:" .. num(snap.viewers)
  b[#b + 1] = "g:" .. num(snap.generation)
  b[#b + 1] = snap.complete and "OK" or "PARTIAL"
  b[#b + 1] = "u:" .. num(snap.unreadable)

  -- `set:?`, never `set:0`. A coerced zero reads as "nothing is configured" when the
  -- truth is "no viewer answered" — two findings a reader would act on differently.
  local h = {
    token(snap.kind),
    "shown:" .. num(snap.viewersShown) .. "/" .. num(snap.viewers),
    "set:" .. (snap.configuredOk and num(snap.configured) or "?"),
  }
  if snap.detail ~= nil then h[#h + 1] = token(snap.detail) end

  return "B{" .. table.concat(b, " ") .. "}"
    .. " H{" .. table.concat(h, " ") .. "}"
    .. " C{" .. token(snap.spec) .. " hero:" .. token(snap.hero) .. "}"
end

-- ---------------------------------------------------------------------------
-- The stateful wrapper
-- ---------------------------------------------------------------------------

-- The hero tree answers four ways and a reader must tell them apart: a name · `#<id>`
-- (an id we could not name) · `-` (none chosen) · `?` (the read refused). Game reads, so
-- they resolve here rather than inside Render.
local function specAndHero()
  local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
  local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
  local spec = "?"
  if getSpec and getInfo then
    local okIndex, index = pcall(getSpec)
    if okIndex and plain(index) then
      local okInfo, _, specName = pcall(getInfo, index)
      if okInfo and type(specName) == "string" and specName ~= "" then spec = specName end
    end
  end

  local hero = "?"
  local talents = C_ClassTalents
  if talents and talents.GetActiveHeroTalentSpec then
    local ok, subTreeID = pcall(talents.GetActiveHeroTalentSpec)
    if ok and subTreeID == nil then
      hero = "-"
    elseif ok and plain(subTreeID) then
      hero = "#" .. token(subTreeID)
      local okConfig, configID = pcall(talents.GetActiveConfigID)
      if okConfig and plain(configID) and C_Traits and C_Traits.GetSubTreeInfo then
        local okTree, info = pcall(C_Traits.GetSubTreeInfo, configID, subTreeID)
        if okTree and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
          hero = info.name
        end
      end
    end
  end
  return token(spec), token(hero)
end

local lastBody, combat, samples = nil, nil, 0

local function snapshot()
  local snap = ns.Bind.Snapshot()
  snap.spec, snap.hero = specAndHero()
  return snap
end

-- Freshness sits OUTSIDE the dedup key: `age` moves on every evaluation, so folding it
-- into the key would make every line unique and flood the ring.
local function suffix(snap, why)
  local age = "-"
  if type(snap.lastAt) == "number" then age = num(GetTime() - snap.lastAt) end
  return " why:" .. token(why or snap.reason or "-")
    .. " d:" .. num(snap.deferredLast)
    .. " age:" .. age
end

-- The machine-readable mirror, written only where a line or a mark is — `Row` has no
-- dedup of its own, so an unconditional one would flood. Not being the key, it also
-- carries what tells a stale in-combat binding from a fresh one: the edge, and `pending`.
local function row(snap, why)
  local t = {
    rec = "state",
    t = GetTime(),
    rows = snap.rows,
    frames = snap.frames,
    viewers = snap.viewers,
    viewersShown = snap.viewersShown,
    generation = snap.generation,
    unreadable = snap.unreadable,
    complete = snap.complete,
    kind = snap.kind,
    spec = snap.spec,
    hero = snap.hero,
    why = why or snap.reason,
    deferred = snap.deferredLast,
    combat = combat,
    pending = snap.pending,
  }
  if type(snap.lastAt) == "number" then t.age = GetTime() - snap.lastAt end
  -- ⚠ nil, never a coerced 0 — the `set:?` rule, in the channel a grader reads.
  if snap.configuredOk then t.configured = snap.configured end
  -- The one game-authored string here, so it takes the same route it does on a line.
  if snap.detail ~= nil then t.detail = token(snap.detail) end
  for _, v in ipairs(snap.byViewer or {}) do t["v_" .. token(v.short)] = v.count end
  return t
end

local lastGen = nil

-- Gated on the generation, not on the write: a resolve that moved nothing would otherwise
-- repeat the whole set, and identity only changes when the signature does.
local function writeRowDigest(snap)
  if snap.generation == lastGen then return end
  lastGen = snap.generation
  for _, r in ipairs(ns.Bind.RowDigest()) do
    r.rec, r.g = "bind", snap.generation
    stream:Row(r)
  end
end

-- ⚠ `samples` against `#lines` at read time is how a reader detects the ring trimmed.
local function stampMeta(snap, body)
  stream:Meta("spec", snap.spec)
  stream:Meta("hero", snap.hero)
  stream:Meta("verdict", token(snap.kind))
  stream:Meta("samples", samples)
  stream:Meta("last", body)
  local f = ns.db and ns.db.frame
  stream:Meta("frame", type(f) == "table"
    and (num(f.x) .. "," .. num(f.y) .. "," .. tostring(f.placed == true)) or "?")
end

-- One pre-built string, no varargs: `Capture.lua` formats only when varargs are present,
-- so a `%` in a localised spec name never reaches a format slot.
local function write(snap, body, why, edge)
  local text = string.format("t%.1f ", GetTime())
    .. (edge and ("# combat " .. edge .. " ") or "") .. body .. suffix(snap, why)
  if edge then stream:Mark(text) else stream:Line(text) end
  samples = samples + 1
  stream:Row(row(snap, why))
  writeRowDigest(snap)
  stampMeta(snap, body)
  lastBody = body
end

-- A write before `ns.db` exists is dropped silently, so it must not move the dedup
-- baseline — otherwise the first line that could land is swallowed as a duplicate.
local function record(_, why)
  if not ns.db then return end
  local snap = snapshot()
  local body = Log.Render(snap)
  if body == lastBody then return end
  write(snap, body, why)
end

-- Both edges carry the FULL body: a bare marker against an unchanged state emits no
-- numbers, and unchanged is the case a flight confirms. The mark moves the dedup
-- baseline, and a session's first mark needs a state line above it to read against.
local function markCombat(edge, event)
  if not ns.db then return end
  combat = edge
  local snap = snapshot()
  local body = Log.Render(snap)
  if lastBody == nil then write(snap, body, nil) end
  write(snap, body, event, edge)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

-- ⚠ Combat comes from the event name, never `InCombatLockdown()`, so the log never
-- depends on when the lockdown flag clears. Bind registers these but does not act here.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
  markCombat(event == "PLAYER_REGEN_DISABLED" and "start" or "end", event)
end)

-- No `# config` mark: spec and hero ride inside the dedup key, so a swap always moves
-- the body and cannot be swallowed the way a combat edge can.
ns.Bind.OnEvaluated(record)
