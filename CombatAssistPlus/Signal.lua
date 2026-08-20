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
  if name == "affordable" then return (world.affordable or {})[id] end
  -- Aura up/down, from Track's latch. UNKNOWN until something says otherwise, which is what
  -- keeps a marker dark on a setup where the tracked-buff row was never enabled.
  if name == "aura" then return (world.aura or {})[id] end
  -- Is this talent taken? Read from the trait config, not from a proxy — see Talents.lua.
  -- nil/UNKNOWN when the read refused, which never becomes "not taken".
  if name == "talent" then return (world.talent or {})[id] end
  -- The one gate that is not a game read at all: cap's own /cap aoe toggle. It has no
  -- subject, so `id` is nil here by design.
  if name == "aoe" then return world.aoe end
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

-- A capture label for one term: the predicate and its subject, so a log reader sees which
-- fact gated a marker without re-deriving it from the catalog. `!` marks a negated term.
local function termLabel(term)
  local prefix = term.negate and "!" or ""
  local name = term[1]
  if name == "aoe" then return prefix .. "aoe" end
  if name == "resource" then return prefix .. "resource" .. tostring(term[2]) .. tostring(term[3]) end
  if name == "identity" then return prefix .. "identity:" .. tostring(term[2]) .. ":" .. tostring(term[3]) end
  return prefix .. tostring(name) .. ":" .. tostring(term[2])
end

local GLYPH = { [true] = "T", [false] = "F", [UNKNOWN] = "?" }

--- Evaluate EVERY term (no short-circuit) and report both the verdict and the reasoning:
--- `state` is "on" (all true), "off" (a false present), or "blind" (an unknown but no false),
--- and `parts` is one `label=T|F|?` per term. `off` wins over `blind` — a false answer rules
--- the marker out even when another term is unknown, matching the eliminating spirit.
function Signal.Explain(terms, world)
  local parts, sawFalse, sawBlind = {}, false, false
  for _, term in ipairs(terms or {}) do
    local value = Signal.Term(term, world)
    parts[#parts + 1] = termLabel(term) .. "=" .. (GLYPH[value] or "?")
    if value == false then sawFalse = true elseif value == UNKNOWN then sawBlind = true end
  end
  local state = sawFalse and "off" or (sawBlind and "blind" or "on")
  return state, parts
end

-- The truth-only view the tier/marker gates need. Delegated to Explain so the two can never
-- disagree: `shown` iff every term is true, `blind` iff an unknown (and no false) withheld it.
local function all(terms, world)
  local state = Signal.Explain(terms, world)
  return state == "on", state == "blind"
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

--- Cue keys in shelf-RANK order, deduped. Two markers may name one cue — that is how an OR is
--- authored without an OR in the band grammar — and the order is the shelf's rather than the
--- catalog's so a capture body stays deterministic across a marker reshuffle.
local function orderCues(keys)
  local shelf = (ns.Style or {}).cues or {}
  local out = {}
  for key in pairs(keys) do out[#out + 1] = key end
  table.sort(out, function(a, b)
    local sa = (shelf[a] or {}).rank or math.huge
    local sb = (shelf[b] or {}).rank or math.huge
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
    -- V11's hatch: the CDM's own readiness latch, and ONLY the false case. `nil` and UNKNOWN both
    -- draw bare, because absence of a hatch must never assert that a button is up — cap says a
    -- thing is on cooldown when it has been told so and at no other time.
    local ready = (world.ready or {})[entry.id]
    local verdict = {
      entry = entry.id, row = bound.row, tier = selected, charged = bound.charged,
      oncd = ready == false,
      emphasized = selected ~= nil, blindTier = blindTier, markers = {}, cues = {},
      reasons = {}, gates = {},
    }
    if selected then
      out.emphasized = out.emphasized + 1
    end
    if blindTier then out.unknowns = out.unknowns + 1 end
    local cues = {}
    for _, marker in ipairs(entry.markers or {}) do
      -- Sealed displays are acquired by Channel and never become Lua predicates.
      if marker.when then
        local state, parts = Signal.Explain(marker.when, world)
        if marker.display then
          -- A READABLE GATE on a sealed cue. It never contributes a cue — the client paints
          -- that from the curve — it only says whether the paint is allowed at all. `blind` is
          -- `false` here for the same reason `off` is: an unknown must not license a badge.
          verdict.gates[marker.id] = state == "on"
          if state == "blind" then out.unknowns = out.unknowns + 1 end
        elseif state == "on" then
          verdict.markers[#verdict.markers + 1] = marker.id
          if marker.cue then cues[marker.cue] = true end
          out.markers = out.markers + 1
        elseif state == "blind" then
          out.unknowns = out.unknowns + 1
        end
        -- The reason a marker drew OR was withheld — captured for every readable marker so a
        -- flight can answer "why", not just "what". `off` is the most telling: a cleanly
        -- ruled-out gate names the fact that ruled it out.
        verdict.reasons[#verdict.reasons + 1] = { id = marker.id, state = state, terms = parts }
      end
    end
    verdict.cues = orderCues(cues)
    out.byEntry[entry.id] = verdict
  end
  return out
end
