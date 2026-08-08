-- Track.lua — readiness, aura presence and elapsed, from alert edges alone.
--
-- Pure: (timestamp, event) tuples in, plain data out. Installing the hooks and reading
-- the clock is Sense's half, because the readiness latch is the part most likely to be
-- wrong and must be testable at a desk.
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

--- Everything arrives through Bind; an entry's terms are Tier's to evaluate, not this.
function Track.New()
  local self = setmetatable({}, Instance)
  self:Bind(nil)
  return self
end

--------------------------------------------------------------------------------
-- Binding
--------------------------------------------------------------------------------

--- `Catalog.Resolve`'s output plus the live rows, reduced to what Track needs. Only the
--- aura families carry `auraIDs`: `auraUp(x)` means a tracked row holds a live bound
--- aura, and a spell row's ids are things you press. Without `reads` every gate is
--- tallied for every entry — right for a hand-built binding, wrong in play.
function Track.Binding(resolved, rows, reads)
  local entries, auraIDs = {}, {}
  local byEntry = (reads or {}).byEntry
  local wanted = (reads or {}).auras

  for _, bound in ipairs((resolved or {}).entries or {}) do
    entries[bound.entry.id] = {
      cid = bound.row.cooldownID,
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
      -- An aura row no band names neither latches nor tallies as a gate that refused.
      if #ids > 0 then
        table.sort(ids)
        auraIDs[row.cooldownID] = ids
      end
    end
  end

  return { entries = entries, auraIDs = auraIDs }
end

--- `binding.entries` is `entryId -> {cid, needs}`; `binding.auraIDs` is
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

-- OnCooldown stamps `castAt` but does NOT count toward `casts`: it fires at the same
-- instant as the press for every ability that has a cooldown, so counting both would
-- double-count exactly those and leave the cooldown-less floor at zero.
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

--- The out-of-combat baseline: nil leaves a row unknown rather than asserting readiness.
function Instance:SeedReady(cid, value)
  if value == nil then return end
  self:setReady(cid, value and true or false)
end

function Instance:SeedAura(cid, up)
  if up == nil then return end
  self.auraCid[cid] = up and true or false
end

--- Read out of combat. Above one charge `setReady` refuses to move the latch at all.
function Instance:SeedCharges(entryID, maxCharges)
  local e = self.entries[entryID]
  if e and type(maxCharges) == "number" then e.maxCharges = maxCharges end
end

--- One observed press. `casts` has no consumer today: it is the counter behind §3.5's
--- `casts == n`, which is sequence-trigger vocabulary and is refused in a band.
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

--- The plain snapshot `Tier.Evaluate` consumes, plus a per-gate readable-against-refused
--- tally. `reads` carries what Track cannot observe; anything absent reads unknown, and
--- without the tally "the catalog is quiet" and "the latch never seeded" draw alike.
function Instance:World(now, reads)
  reads = reads or {}
  local w = {
    ready = {},
    elapsed = {},
    auraUp = {},
    affordable = reads.affordable or {},
    proc = reads.proc or {},
    identity = reads.identity or {},
    talent = reads.talent or {},
    resource = reads.resource,
    resourceMax = reads.resourceMax,
    mode = reads.mode,
    combat = self.combatSince ~= nil,
  }

  local health = { gates = {}, entries = 0 }

  for id, e in pairs(self.entries) do
    health.entries = health.entries + 1

    -- A statement, not `(r == nil) and UNKNOWN or r`: the `and/or` idiom collapses a
    -- correct `false` into UNKNOWN, which is the one distinction this module exists for.
    local r = self.ready[id]
    if r == nil then r = UNKNOWN end
    w.ready[id] = r

    local at = self.castAt[id]
    if at then w.elapsed[id] = now - at end

    -- Only the gates something in the catalog asks OF THIS ENTRY — `Catalog.Reads` keys
    -- by subject, so a band naming E2 from E1 tallies against E2. Tallying a gate nobody
    -- asks for would report a working catalog as blind.
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

  return w, health
end

Track.Instance = Instance
