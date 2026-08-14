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
  for id, ability in pairs(self.abilities) do
    self.byCid[ability.cid] = self.byCid[ability.cid] or {}
    self.byCid[ability.cid][#self.byCid[ability.cid] + 1] = id
    for spellID in pairs(ability.spells or {}) do
      self.bySpell[spellID] = self.bySpell[spellID] or {}
      self.bySpell[spellID][#self.bySpell[spellID] + 1] = id
    end
  end
end

function Instance:setReady(cid, value)
  for _, id in ipairs(self.byCid[cid] or {}) do
    local ability = self.abilities[id]
    if not ability.charged then self.ready[id] = value end
  end
end

local function clamp(value, maximum)
  return math.max(0, math.min(maximum, value))
end

function Instance:Edge(now, cid, event)
  if not self.byCid[cid] then return false end
  if event == "Available" then self:setReady(cid, true); return true end
  if event == "OnCooldown" then self:setReady(cid, false); return true end
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

function Instance:World(_, reads)
  reads = reads or {}
  local world = {
    ready = {}, proc = reads.proc or {}, identity = reads.identity or {},
    resource = reads.resource, resourceMax = reads.resourceMax, chargeProvenance = {},
  }
  local health = { predicates = {}, abilities = 0 }
  for id, ability in pairs(self.abilities) do
    health.abilities = health.abilities + 1
    local charge = self.charges[id]
    local ready
    if ability.charged then
      if charge then ready = charge.current > 0 end
    else
      ready = self.ready[id]
    end
    world.ready[id] = ready == nil and UNKNOWN or ready
    if ability.charged and charge then world.chargeProvenance[id] = charge.provenance end
    local needs = ability.needs
    if needs == nil or needs.ready then tally(health.predicates, "ready", ready) end
    if needs == nil or needs.proc then tally(health.predicates, "proc", world.proc[id]) end
    if needs == nil or needs.identity then tally(health.predicates, "identity", world.identity[id]) end
  end
  if (reads.needsResource ~= false) then tally(health.predicates, "resource", world.resource) end
  return world, health
end

Track.Instance = Instance
