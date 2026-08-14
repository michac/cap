-- Signal.lua — unknown-safe evaluation of the catalog's readable conditions. Pure.
local ADDON, ns = ...

local Signal = { UNKNOWN = "unknown" }
ns.Signal = Signal
local UNKNOWN = Signal.UNKNOWN

local function subject(term, world)
  local name, id = term[1], term[2]
  if name == "ready" then return (world.ready or {})[id] end
  if name == "proc" then return (world.proc or {})[id] end
  if name == "capped" then return (world.capped or {})[id] end
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

--- The selected tier, plus WHICH tier went blind rather than merely that one did — a reader
--- diagnosing a dark row needs to know which band refused, not just that a band did.
local function tier(entry, world)
  local uncertain
  for _, band in ipairs(entry.bands or {}) do
    if uncertain and band.tier ~= uncertain then return nil, uncertain end
    local on, blind = all(band.when, world)
    if on then return band.tier, nil end
    if blind then uncertain = band.tier end
  end
  return nil, uncertain
end

--- Cue keys in shelf-slot order, deduped. Two markers may name one cue — that is how an OR is
--- authored without an OR in the band grammar — and the order is the shelf's rather than the
--- catalog's so a capture body stays deterministic across a marker reshuffle.
local function orderCues(keys)
  local shelf = (ns.Style or {}).cues or {}
  local out = {}
  for key in pairs(keys) do out[#out + 1] = key end
  table.sort(out, function(a, b)
    local sa = (shelf[a] or {}).slot or math.huge
    local sb = (shelf[b] or {}).slot or math.huge
    if sa ~= sb then return sa < sb end
    return a < b
  end)
  return out
end

function Signal.Evaluate(resolved, world)
  local out = { byEntry = {}, emphasized = 0, markers = 0, unknowns = 0 }
  for _, bound in ipairs((resolved or {}).entries or {}) do
    local entry = bound.entry
    local selected, blindTier = tier(entry, world)
    local verdict = {
      entry = entry.id, row = bound.row, tier = selected, charged = bound.charged,
      emphasized = selected ~= nil, blindTier = blindTier, markers = {}, cues = {},
    }
    if selected then
      out.emphasized = out.emphasized + 1
    end
    if blindTier then out.unknowns = out.unknowns + 1 end
    local cues = {}
    for _, marker in ipairs(entry.markers or {}) do
      -- Sealed displays are acquired by Channel and never become Lua predicates.
      if marker.when then
        local shown, markerBlind = all(marker.when, world)
        if shown then
          verdict.markers[#verdict.markers + 1] = marker.id
          if marker.cue then cues[marker.cue] = true end
          out.markers = out.markers + 1
        end
        if markerBlind then out.unknowns = out.unknowns + 1 end
      end
    end
    verdict.cues = orderCues(cues)
    out.byEntry[entry.id] = verdict
  end
  return out
end
