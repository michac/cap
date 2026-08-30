-- Track.lua — the readable readiness latch. Pure: timestamped alert edges in, data out.
local ADDON, ns = ...

local Track = {}
ns.Track = Track
local UNKNOWN = ns.Signal.UNKNOWN
local Instance = {}
Instance.__index = Instance

function Track.New()
  local self = setmetatable({}, Instance)
  self:Bind(nil)
  return self
end

function Track.Binding(resolved, reads)
  local abilities = {}
  local needed = (reads or {}).byAbility
  for _, bound in ipairs((resolved or {}).abilities or {}) do
    abilities[bound.ability.id] = {
      cid = bound.row.cooldownID,
      needs = needed and (needed[bound.ability.id] or {}) or nil,
      charged = bound.ability.charged and true or false,
      spells = {},
    }
    local ability = abilities[bound.ability.id]
    ability.spells[bound.ability.spell] = true
    for _, spellID in ipairs(bound.ability.alt or {}) do ability.spells[spellID] = true end
    for spellID in pairs(bound.row.spellIDs or {}) do ability.spells[spellID] = true end
  end
  return { abilities = abilities }
end

function Instance:Bind(binding)
  self.abilities = (binding or {}).abilities or {}
  self.byCid, self.bySpell, self.ready, self.charges = {}, {}, {}, {}
  self.aura = {}
  for id, ability in pairs(self.abilities) do
    self.byCid[ability.cid] = self.byCid[ability.cid] or {}
    self.byCid[ability.cid][#self.byCid[ability.cid] + 1] = id
    for spellID in pairs(ability.spells or {}) do
      self.bySpell[spellID] = self.bySpell[spellID] or {}
      self.bySpell[spellID][#self.bySpell[spellID] + 1] = id
    end
  end
end

-- ---------------------------------------------------------------------------
-- The cooldown state — cap's own, held, not fetched
-- ---------------------------------------------------------------------------
--
-- `self.ready[id]` is a HELD representation of whether each ability is on cooldown, fed by
-- several sources that each know one half of the story. Nothing here is a read on demand,
-- because no single read answers in every state: the Cooldown Manager's dial is shared by
-- four sources, and while an AURA owns it (demon form, a buff row) the dial says nothing at
-- all about the cooldown running underneath it.
--
-- Sources, and which direction each can push:
--
--   OnCooldown alert   -> ON.   Fires for every row unconditionally (the data-refresh path).
--   OnCooldownDone     -> OFF.  The engine's widget script, outside the alert system, so it
--                               arrives for rows with no configured alert (§5.1).
--   Available alert    -> OFF.  Real when it comes; only comes for configured rows.
--   the live dial read -> EITHER, and CRUCIALLY only when it is decisive. `nil` means the
--                               dial is showing something else and the state is LEFT ALONE.
--   out-of-combat seed -> EITHER. The exact read, while it is legal.
--
-- ⚠ The old design used the alert edges ALONE, and `Available` only fires for rows the player
-- configured an alert on — so it went on and never came off. The fix is not a different single
-- source; it is that OFF now has three independent suppliers and the ambiguous case abstains.
function Instance:setReady(cid, value)
  for _, id in ipairs(self.byCid[cid] or {}) do
    self.ready[id] = value
  end
end

--- Fold in the live dial read. `nil` for a row is NOT "ready" — it is "the dial is busy saying
--- something else", and the held state is the only thing that knows better, so it stands.
function Instance:Observe(live)
  for id, onCooldown in pairs(live or {}) do
    if onCooldown ~= nil and self.abilities[id] then
      self.ready[id] = not onCooldown
    end
  end
end

local function clamp(value, maximum)
  return math.max(0, math.min(maximum, value))
end

--- The AURA latch, and why it is a latch rather than a read.
---
--- Aura secrecy is COMBAT-GATED: out of combat `C_UnitAuras` answers a tainted caller
--- normally, and in combat the spell-keyed getters return a silent `nil` that is
--- indistinguishable from "no such aura" (`security-taint-and-restricted-data.md` §4.7.1). So
--- the exact read is legal exactly when it is not needed. Sources, in the same shape as
--- `ready` above:
---
---   out-of-combat seed -> EITHER. The exact read, while it is legal. `SeedAura`.
---   OnAuraApplied      -> ON.
---   OnAuraRemoved      -> OFF.
---
--- ⚠ There is no third supplier and no timeout. A row the player never enabled has no cid, so
--- nothing here is ever written for it and `World` reports UNKNOWN — a marker on it stays dark
--- instead of reading as "the aura is down", which is the one failure that must not happen.
--- ⚠ A REFRESH of a live aura raises no edge (`cooldown-manager.md` §5.4). Harmless for up/down
--- and fatal for anything wanting duration, so this holds a boolean and nothing else.
function Instance:setAura(cid, value)
  for _, id in ipairs(self.byCid[cid] or {}) do
    self.aura[id] = value
  end
end

--- Seed one ability's aura state from an exact read. `nil` leaves the held state alone.
function Instance:SeedAura(id, value)
  if value ~= nil and self.abilities[id] then self.aura[id] = value and true or false end
end

function Instance:Edge(now, cid, event)
  if not self.byCid[cid] then return false end
  if event == "Available" then self:setReady(cid, true); return true end
  if event == "OnCooldown" then self:setReady(cid, false); return true end
  if event == "OnAuraApplied" then self:setAura(cid, true); return true end
  if event == "OnAuraRemoved" then self:setAura(cid, false); return true end
  if event == "ChargeGained" then
    local landed, charged = false, false
    for _, id in ipairs(self.byCid[cid]) do
      local ability, charge = self.abilities[id], self.charges[id]
      if ability.charged and charge then
        charged = true
        local window = math.max(1, 0.5 * (charge.recharge or 0))
        if not charge.lastGain or (now - charge.lastGain) >= window then
          charge.current = clamp(charge.current + 1, charge.max)
          charge.lastGain = now
          charge.provenance = "napkin"
          landed = true
        end
      end
    end
    if not landed and charged then return false, "duplicate" end
    return landed
  end
  return false
end

function Instance:SeedReady(cid, value)
  if value ~= nil then self:setReady(cid, value and true or false) end
end

--- Charged abilities no longer take their readiness from the charge ledger. The ledger's
--- recovery edge is `ChargeGained`, which is one of the three the viewer only raises for rows
--- with a configured alert — measured ZERO times across a whole session — so a ledger-driven
--- readiness decremented on cast and never came back. The dial answers it correctly instead:
--- the Cooldown Manager SKIPS its spell-cooldown source entirely while a charge is banked
--- `[T1 src @12.1.0: CooldownViewer.lua:979]`, so `wasSetFromCooldown` is true for a charged
--- ability exactly when it has none left. The ledger still owns the COUNT and `capped`.

function Instance:SeedCharges(id, currentCharges, maxCharges, recharge)
  local ability = self.abilities[id]
  if not (ability and ability.charged) then return false end
  if type(currentCharges) ~= "number" or type(maxCharges) ~= "number" or maxCharges <= 0 then
    return false
  end
  local previous = self.charges[id]
  local measured = type(recharge) == "number" and recharge > 0 and recharge
    or (previous and previous.recharge)
  self.charges[id] = {
    current = clamp(currentCharges, maxCharges), max = maxCharges,
    recharge = measured, provenance = "live", lastGain = nil,
  }
  return true
end

function Instance:CastSpell(_, spellID)
  local landed = false
  for _, id in ipairs(self.bySpell[spellID] or {}) do
    local ability, charge = self.abilities[id], self.charges[id]
    if ability.charged and charge then
      charge.current = clamp(charge.current - 1, charge.max)
      charge.provenance = "napkin"
      landed = true
    end
  end
  return landed
end

local function tally(health, name, value)
  local slot = health[name] or { known = 0, unknown = 0 }
  health[name] = slot
  if value == nil or value == UNKNOWN then slot.unknown = slot.unknown + 1 else slot.known = slot.known + 1 end
end

-- Per-ability gates Track copies straight through from the live reads. `ready` is absent
-- because it is the one Track MAINTAINS — the latch and the charge ledger are its whole job.
--
-- ⚠ `capped` deliberately bypasses the charge ledger and is read live every tick. A napkin
-- count cannot survive Immolation Aura's demon-form flip (the override id is not in the frozen
-- spellIDs union, so a Consuming Fire cast would never debit) and `isActive` needs no ledger.
--
-- ⚠ `baseoncd` IS COPIED AND MUST NEVER BE OBSERVED. `onCooldown` is folded into `self.ready`
-- as `not onCooldown` (`Observe` above), and this is a fact about a DIFFERENT spell than the one
-- the row is drawing — inverting it into `ready` would corrupt every readiness answer on the row
-- for the whole time the transform is up, which is exactly when the row matters.
local COPIED = { "proc", "identity", "capped", "affordable", "baseoncd" }
Track.COPIED = COPIED

function Instance:World(_, reads)
  reads = reads or {}
  self:Observe(reads.onCooldown)
  local world = {
    ready = {}, aura = {}, resource = reads.resource, resourceMax = reads.resourceMax,
    chargeProvenance = {},
  }
  for _, name in ipairs(COPIED) do world[name] = reads[name] or {} end
  -- Neither of these is per-ability, so neither goes through COPIED or the charge ledger.
  -- `talent` is keyed by the catalog's talent ids; `aoe` is a single boolean, cap's own.
  world.talent = reads.talent or {}
  world.aoe = reads.aoe

  local health = { predicates = {}, abilities = 0 }
  for id, ability in pairs(self.abilities) do
    health.abilities = health.abilities + 1
    local charge = self.charges[id]
    local ready = self.ready[id]
    world.ready[id] = ready == nil and UNKNOWN or ready
    local aura = self.aura[id]
    world.aura[id] = aura == nil and UNKNOWN or aura
    if ability.charged and charge then world.chargeProvenance[id] = charge.provenance end
    local needs = ability.needs
    if needs == nil or needs.ready then tally(health.predicates, "ready", ready) end
    if needs and needs.aura then tally(health.predicates, "aura", aura) end
    for _, name in ipairs(COPIED) do
      if needs == nil or needs[name] then tally(health.predicates, name, world[name][id]) end
    end
  end
  if (reads.needsResource ~= false) then tally(health.predicates, "resource", world.resource) end
  -- Tallied only when the catalog asks for them, so a spec that names neither reports neither
  -- rather than a permanent unknown. `needsTalent` is the ordered id list, so the count is
  -- deterministic — a `pairs()` walk here would be a health number that moves for no reason.
  for _, id in ipairs(reads.needsTalent or {}) do
    tally(health.predicates, "talent", world.talent[id])
  end
  if reads.needsAoE then tally(health.predicates, "aoe", world.aoe) end
  return world, health
end

Track.Instance = Instance
