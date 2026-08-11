-- Signal.lua — unknown-safe evaluation of the catalog's readable conditions. Pure.
local ADDON, ns = ...

local Signal = { UNKNOWN = "unknown" }
ns.Signal = Signal
local UNKNOWN = Signal.UNKNOWN

local function subject(term, world)
  local name, id = term[1], term[2]
  if name == "ready" then return (world.ready or {})[id] end
  if name == "proc" then return (world.proc or {})[id] end
  if name == "identity" then
    local value = (world.identity or {})[id]
    if value == nil or value == UNKNOWN then return UNKNOWN end
    return value == term[3]
  end
  if name == "resource" then
    local value = world.resource
    if type(value) ~= "number" then return UNKNOWN end
    if term[2] == "<=" then return value <= term[3] end
    if term[2] == ">=" then return value >= term[3] end
  end
  return UNKNOWN
end

function Signal.Term(term, world)
  local value = subject(term, world or {})
  if value == nil or value == UNKNOWN then return UNKNOWN end
  value = value and true or false
  if term.negate then return not value end
  return value
end

local function all(terms, world)
  local blind = false
  for _, term in ipairs(terms or {}) do
    local value = Signal.Term(term, world)
    if value == false then return false, blind end
    if value == UNKNOWN then blind = true end
  end
  if blind then return false, true end
  return true, false
end

local function strength(entry, world)
  local spec = entry.strength
  if not spec or spec.source ~= "resource" then return nil end
  local value, max = world.resource, world.resourceMax
  if type(value) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
  local n = math.max(0, math.min(1, value / max))
  if spec.direction == "falling" then n = 1 - n end
  return n
end

function Signal.Evaluate(resolved, world)
  local out = { byEntry = {}, emphasized = 0, markers = 0, unknowns = 0 }
  for _, bound in ipairs((resolved or {}).entries or {}) do
    local entry = bound.entry
    local on, blind = all(entry.when, world)
    local verdict = { entry = entry.id, row = bound.row, emphasized = on, markers = {} }
    if on then
      out.emphasized = out.emphasized + 1
      verdict.strength = strength(entry, world)
    end
    if blind then out.unknowns = out.unknowns + 1 end
    for _, marker in ipairs(entry.markers or {}) do
      local shown, markerBlind = all(marker.when, world)
      if shown then
        verdict.markers[#verdict.markers + 1] = marker.id
        out.markers = out.markers + 1
      end
      if markerBlind then out.unknowns = out.unknowns + 1 end
    end
    out.byEntry[entry.id] = verdict
  end
  return out
end

