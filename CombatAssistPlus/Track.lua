-- Track.lua — readiness, aura presence, elapsed and window truth, from edges alone.
--
-- Pure: (timestamp, event) tuples in, plain data out. Installing the hooks and reading
-- the clock is Sense's half, because the readiness latch and the window arithmetic are
-- the parts most likely to be wrong and must be testable at a desk.
--
-- Readiness is THREE-STATE. `unknown` is not `false`: a /reload mid-combat seeds no
-- baseline and both defaults are wrong — default-ready lights the roster for a whole
-- pull, default-not-ready blanks it. Unknown fails every band and is counted, so a
-- flight can tell a quiet catalog from a blind one.
local ADDON, ns = ...

local Track = {}
ns.Track = Track

local Tier = ns.Tier
local UNKNOWN = Tier.UNKNOWN

local Instance = {}
Instance.__index = Instance

--- `catalog` supplies the window rules. Everything else arrives through Bind.
function Track.New(catalog)
  local self = setmetatable({ catalog = catalog }, Instance)
  self:Bind(nil)
  return self
end

--------------------------------------------------------------------------------
-- Binding
--------------------------------------------------------------------------------

--- `Catalog.Resolve`'s output plus the live row list, reduced to what Track needs.
--- Pure, and it lives here rather than in Sense so the shape has one author.
---
--- Only the aura families carry `auraIDs`: `auraUp(x)` means a tracked row holds a live
--- bound aura, and a spell row's ids are things you press.
--- `reads` is `Catalog.Reads(cat)`. Absent, every gate is tallied for every entry,
--- which is the right default for a hand-built binding and the wrong one in play.
function Track.Binding(resolved, rows, reads)
  local entries, auraIDs = {}, {}
  local byEntry = (reads or {}).byEntry
  local wanted = (reads or {}).auras

  for _, bound in ipairs((resolved or {}).entries or {}) do
    entries[bound.entry.id] = {
      cid = bound.row.cooldownID,
      cd = bound.entry.cd,
      needs = byEntry and (byEntry[bound.entry.id] or {}) or nil,
    }
  end

  for i = 1, #(rows or {}) do
    local row = rows[i]
    if row.family == "auras" and row.spellIDs then
      local ids = {}
      for id in pairs(row.spellIDs) do
        if wanted == nil or wanted[id] then ids[#ids + 1] = id end
      end
      -- An aura row no band names is left out entirely, so it neither latches nor
      -- lands in the health tally as a gate that refused.
      if #ids > 0 then
        table.sort(ids)
        auraIDs[row.cooldownID] = ids
      end
    end
  end

  return { entries = entries, auraIDs = auraIDs }
end

--- `binding.entries` is `entryId -> {cid, cd, needs}`; `binding.auraIDs` is
--- `cid -> {auraSpellID, …}`. Every latch resets: item frames are pooled, so a rebind
--- means the edges we watched were watched on frames that may now show something else.
function Instance:Bind(binding)
  binding = binding or {}
  self.entries = binding.entries or {}
  self.auraIDs = binding.auraIDs or {}

  self.byCid = {}
  for id, e in pairs(self.entries) do
    local list = self.byCid[e.cid]
    if not list then list = {}; self.byCid[e.cid] = list end
    list[#list + 1] = id
  end

  self.ready = {}
  self.auraCid = {}
  self.castAt = {}
  self.combatSince = nil
  self.casts = 0
end

--------------------------------------------------------------------------------
-- Edges
--------------------------------------------------------------------------------

-- Rule 13's structural guard: "one charge came back" is not "the ability is ready",
-- and the two differ for as long as a spare charge is banked.
function Instance:setReady(cid, value)
  for _, id in ipairs(self.byCid[cid] or {}) do
    local e = self.entries[id]
    if not (e.maxCharges and e.maxCharges > 1) then
      self.ready[id] = value
    end
  end
end

function Instance:stampCast(now, cid)
  for _, id in ipairs(self.byCid[cid] or {}) do
    self.castAt[id] = now
  end
end

-- OnCooldown stamps `castAt` but does NOT count toward `casts`: the client is telling us
-- the cooldown started, which is the same instant as the press for every ability that
-- has one — while `casts` means "presses we observed", and the floor has no cooldown at
-- all. Two sources for one number would double-count exactly the abilities that have both.
local EDGES = {
  Available = function(self, now, cid)
    self:setReady(cid, true)
  end,
  OnCooldown = function(self, now, cid)
    self:setReady(cid, false)
    self:stampCast(now, cid)
  end,
  OnAuraApplied = function(self, now, cid)
    self.auraCid[cid] = true
  end,
  OnAuraRemoved = function(self, now, cid)
    self.auraCid[cid] = false
  end,
}

--- An alert edge. `event` is a NAME, not an `Enum` value — Sense translates, so nothing
--- here needs the client. Returns whether it landed: every item frame in every viewer
--- raises these, so "not ours" is the common case and must not read as "recorded".
function Instance:Edge(now, cid, event)
  local fn = EDGES[event]
  if not fn then return false end
  if self.byCid[cid] == nil and self.auraIDs[cid] == nil then return false end
  fn(self, now, cid)
  return true
end

--- The out-of-combat baseline, which seeds only the /reload-mid-combat case: pass nil to
--- leave a row unknown rather than asserting a readiness nobody read.
function Instance:SeedReady(cid, value)
  if value == nil then return end
  self:setReady(cid, value and true or false)
end

function Instance:SeedAura(cid, up)
  if up == nil then return end
  self.auraCid[cid] = up and true or false
end

--- The base cooldown `remaining` counts down from. The catalog declares it; the client
--- corrects it when it will say, which is out of combat only.
function Instance:SeedCooldown(entryID, seconds)
  local e = self.entries[entryID]
  if e and type(seconds) == "number" and seconds > 0 then e.cd = seconds end
end

--- Read out of combat. Above one charge the latch refuses to move at all: an Available
--- edge means "a charge came back", not "the ability is ready", and the two differ for
--- the whole time a spare charge is banked.
function Instance:SeedCharges(entryID, maxCharges)
  local e = self.entries[entryID]
  if e and type(maxCharges) == "number" then e.maxCharges = maxCharges end
end

--- One observed press of a tracked ability.
function Instance:Cast(now, cid)
  if self.byCid[cid] == nil then return false end
  self:stampCast(now, cid)
  if self.combatSince then self.casts = self.casts + 1 end
  return true
end

function Instance:Combat(now, inCombat)
  if inCombat then
    self.combatSince = now
    self.casts = 0
  else
    self.combatSince = nil
  end
end

--------------------------------------------------------------------------------
-- Window terms — the three that exist only here
--------------------------------------------------------------------------------

local windowTerms = {}

windowTerms.remaining = function(self, term, w)
  local rem = w.remaining[term[2]]
  if type(rem) ~= "number" then return UNKNOWN end
  local cmp = Tier.Comparators[term[3]]
  if not cmp then return UNKNOWN end
  return cmp(rem, term[4])
end

windowTerms.combat = function(self)
  return self.combatSince ~= nil
end

-- Unknown out of combat, because "how many casts into the pull" has no answer when there
-- is no pull — and a window that reads true at a target dummy you have not pulled yet is
-- the opener firing at the wrong moment.
windowTerms.casts = function(self, term)
  if not self.combatSince then return UNKNOWN end
  local cmp = Tier.Comparators[term[2]]
  if not cmp then return UNKNOWN end
  return cmp(self.casts, term[3])
end

local NO_ENTRY = {}

function Instance:evalWindowTerm(term, w)
  local fn = windowTerms[term[1]]
  local v
  if fn then
    v = fn(self, term, w)
    if term.negate and v ~= UNKNOWN then return not v end
    return v
  end
  return Tier.Term(term, NO_ENTRY, w)
end

--- Three-valued like a band: every term must hold, and a single unknown makes the whole
--- window unknown rather than false. A band naming an unknown window then fails it, so a
--- blind window demotes instead of quietly asserting the situation is absent.
function Instance:windowHolds(rule, w)
  local sawUnknown = false
  for _, term in ipairs(rule) do
    local v = self:evalWindowTerm(term, w)
    if v == UNKNOWN then
      sawUnknown = true
    elseif v == false then
      return false
    end
  end
  if sawUnknown then return UNKNOWN end
  return true
end

--------------------------------------------------------------------------------
-- The world
--------------------------------------------------------------------------------

local function tally(t, key, value)
  local slot = t[key]
  if not slot then slot = { known = 0, unknown = 0 }; t[key] = slot end
  if value == nil or value == UNKNOWN then
    slot.unknown = slot.unknown + 1
  else
    slot.known = slot.known + 1
  end
end

--- The plain snapshot `Tier.Evaluate` consumes, plus a gate-health tally beside it.
--- `reads` carries what Track cannot observe — anything absent reads unknown.
---
--- Health counts readable against refused per gate. Without it "the catalog is quiet"
--- and "the latch never seeded" draw identical pixels.
function Instance:World(now, reads)
  reads = reads or {}
  local w = {
    ready = {},
    elapsed = {},
    remaining = {},
    auraUp = {},
    window = {},
    affordable = reads.affordable or {},
    proc = reads.proc or {},
    identity = reads.identity or {},
    talent = reads.talent or {},
    resource = reads.resource,
    resourceMax = reads.resourceMax,
    mode = reads.mode,
  }

  local health = { gates = {}, entries = 0, windows = { known = 0, unknown = 0 } }

  for id, e in pairs(self.entries) do
    health.entries = health.entries + 1

    -- A statement, not `(r == nil) and UNKNOWN or r`: the `and/or` idiom collapses a
    -- correct `false` into UNKNOWN, which is the one distinction this module exists for.
    local r = self.ready[id]
    if r == nil then r = UNKNOWN end
    w.ready[id] = r

    local at = self.castAt[id]
    if at then
      local since = now - at
      w.elapsed[id] = since
      if e.cd then
        local rem = e.cd - since
        w.remaining[id] = (rem > 0) and rem or 0
      end
    end

    -- Only the gates this entry's bands and the windows naming it actually ask for.
    -- Tallying the rest would report a working catalog as blind.
    local needs = e.needs
    if needs == nil or needs.ready then tally(health.gates, "ready", self.ready[id]) end
    if needs == nil or needs.elapsed then tally(health.gates, "elapsed", at) end
    if needs == nil or needs.affordable then tally(health.gates, "affordable", w.affordable[id]) end
    if needs == nil or needs.proc then tally(health.gates, "proc", w.proc[id]) end
    if needs == nil or needs.identity then tally(health.gates, "identity", w.identity[id]) end
  end

  for cid, up in pairs(self.auraCid) do
    for _, spellID in ipairs(self.auraIDs[cid] or {}) do
      w.auraUp[spellID] = up
    end
  end
  for cid in pairs(self.auraIDs) do
    tally(health.gates, "auraUp", self.auraCid[cid])
  end

  tally(health.gates, "resource", type(w.resource) == "number" and w.resource or nil)
  tally(health.gates, "mode", w.mode)

  for name, rule in pairs((self.catalog or {}).windows or {}) do
    local v = self:windowHolds(rule, w)
    w.window[name] = v
    if v == UNKNOWN then
      health.windows.unknown = health.windows.unknown + 1
    else
      health.windows.known = health.windows.known + 1
    end
  end

  return w, health
end

Track.Instance = Instance
