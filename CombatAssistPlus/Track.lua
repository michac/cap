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
    }
  end
  return { abilities = abilities }
end

function Instance:Bind(binding)
  self.abilities = (binding or {}).abilities or {}
  self.byCid, self.ready = {}, {}
  for id, ability in pairs(self.abilities) do
    self.byCid[ability.cid] = self.byCid[ability.cid] or {}
    self.byCid[ability.cid][#self.byCid[ability.cid] + 1] = id
  end
end

function Instance:setReady(cid, value)
  for _, id in ipairs(self.byCid[cid] or {}) do
    local ability = self.abilities[id]
    if not (ability.maxCharges and ability.maxCharges > 1) then self.ready[id] = value end
  end
end

function Instance:Edge(_, cid, event)
  if not self.byCid[cid] then return false end
  if event == "Available" then self:setReady(cid, true); return true end
  if event == "OnCooldown" then self:setReady(cid, false); return true end
  return false
end

function Instance:SeedReady(cid, value)
  if value ~= nil then self:setReady(cid, value and true or false) end
end

function Instance:SeedCharges(id, maxCharges)
  local ability = self.abilities[id]
  if ability and type(maxCharges) == "number" then ability.maxCharges = maxCharges end
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
    resource = reads.resource, resourceMax = reads.resourceMax,
  }
  local health = { predicates = {}, abilities = 0 }
  for id, ability in pairs(self.abilities) do
    health.abilities = health.abilities + 1
    local ready = self.ready[id]
    world.ready[id] = ready == nil and UNKNOWN or ready
    local needs = ability.needs
    if needs == nil or needs.ready then tally(health.predicates, "ready", ready) end
    if needs == nil or needs.proc then tally(health.predicates, "proc", world.proc[id]) end
    if needs == nil or needs.identity then tally(health.predicates, "identity", world.identity[id]) end
  end
  if (reads.needsResource ~= false) then tally(health.predicates, "resource", world.resource) end
  return world, health
end

Track.Instance = Instance
