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
    if value == false then return false, false end
    if value == UNKNOWN then blind = true end
  end
  if blind then return false, true end
  return true, false
end

local function tier(entry, world)
  local uncertain
  for _, band in ipairs(entry.bands or {}) do
    if uncertain and band.tier ~= uncertain then return nil, true end
    local on, blind = all(band.when, world)
    if on then return band.tier, false end
    if blind then uncertain = band.tier end
  end
  return nil, uncertain ~= nil
end

function Signal.Evaluate(resolved, world)
  local out = { byEntry = {}, emphasized = 0, markers = 0, unknowns = 0 }
  for _, bound in ipairs((resolved or {}).entries or {}) do
    local entry = bound.entry
    local selected, blind = tier(entry, world)
    local verdict = {
      entry = entry.id, row = bound.row, tier = selected,
      emphasized = selected ~= nil, markers = {},
    }
    if selected then
      out.emphasized = out.emphasized + 1
    end
    if blind then out.unknowns = out.unknowns + 1 end
    for _, marker in ipairs(entry.markers or {}) do
      -- Sealed displays are acquired by Channel and never become Lua predicates.
      if marker.when then
        local shown, markerBlind = all(marker.when, world)
        if shown then
          verdict.markers[#verdict.markers + 1] = marker.id
          out.markers = out.markers + 1
        end
        if markerBlind then out.unknowns = out.unknowns + 1 end
      end
    end
    out.byEntry[entry.id] = verdict
  end
  return out
end
