-- Tier.lua — first-match bands over a plain-data world. Pure: no game reads, no clock.
--
-- Two properties the format depends on and this enforces:
--   * no term names another entry's VERDICT — a band names abilities, never tiers;
--   * a gate is THREE-STATE. `unknown` is not `false`, and negation does not rescue it:
--     `not <unknown>` stays unknown, an unknown fails its band, and the refusals are
--     counted, so a quiet field and a blind one are distinguishable in the log.
--
-- Keyed by ENTRY, never by cooldownID: two entries share one row on a transforming
-- ability, and collapsing them would pick a winner in a return type.
local ADDON, ns = ...

local Tier = {}
ns.Tier = Tier

local UNKNOWN = "unknown"
Tier.UNKNOWN = UNKNOWN

local function three(v)
  if v == UNKNOWN or v == nil then return UNKNOWN end
  return v and true or false
end

--------------------------------------------------------------------------------
-- Term evaluation — one gate each, three-valued
--------------------------------------------------------------------------------

local evaluators = {}

-- Catalog owns `this` → entry-id, so a band and the check that admitted it cannot
-- disagree about which ability a term named.
local subject = ns.Catalog.Subject

evaluators.ready = function(term, e, w)
  return three(w.ready and w.ready[subject(term, e)])
end

evaluators.affordable = function(term, e, w)
  return three(w.affordable and w.affordable[subject(term, e)])
end

evaluators.proc = function(term, e, w)
  return three(w.proc and w.proc[subject(term, e)])
end

-- ⚠ `auraUp`'s argument is an AURA SPELL ID, not an entry subject, so it deliberately does
-- NOT go through `Catalog.Subject` — `this` would resolve to an entry id, and `w.auraUp` is
-- keyed by spell id off `Track`'s aura latch, which filters its ids against the numeric set
-- `Catalog.Reads` collected. An entry id there is not merely wrong, it is undetectable: the
-- row never enters `auraIDs`, nothing latches, nothing tallies, and the band is silently
-- dead. `Catalog.GATES.auraUp` says `subject = "aura"` and check 3 refuses a string here,
-- which is the other half of the same rule.
evaluators.auraUp = function(term, e, w)
  return three(w.auraUp and w.auraUp[term[2]])
end

evaluators.talent = function(term, e, w)
  return three(w.talent and w.talent[term[2]])
end

evaluators.combat = function(term, e, w)
  if w.combat == nil or w.combat == UNKNOWN then return UNKNOWN end
  return w.combat and true or false
end

-- The one gate that is not a game read, and still three-valued: before cap has a mode it
-- is unknown, and it must fail its band rather than default to single and assert an
-- opinion nobody chose.
evaluators.mode = function(term, e, w)
  if w.mode == nil or w.mode == UNKNOWN then return UNKNOWN end
  return w.mode == term[2]
end

-- `identity(this, "transformed")` is "the row is showing something other than its own
-- base". It names no spell id on purpose — the honest test for an override is that it
-- differs from the base, never that it is present.
evaluators.identity = function(term, e, w)
  local state = w.identity and w.identity[subject(term, e)]
  if state == nil or state == UNKNOWN then return UNKNOWN end
  return state == term[3]
end

local comparators = {
  [">="] = function(a, b) return a >= b end,
  ["<="] = function(a, b) return a <= b end,
  [">"] = function(a, b) return a > b end,
  ["<"] = function(a, b) return a < b end,
  ["=="] = function(a, b) return a == b end,
}

evaluators.resource = function(term, e, w)
  local have = w.resource
  if type(have) ~= "number" then return UNKNOWN end
  local cmp = comparators[term[2]]
  if not cmp then return UNKNOWN end
  return cmp(have, term[3])
end

-- Restricted to `this` here as well as at check time, so a table reaching Tier some
-- other way cannot get an estimate about an ability it may not estimate about.
evaluators.elapsed = function(term, e, w)
  if term[2] ~= "this" then return UNKNOWN end
  local t = w.elapsed and w.elapsed[subject(term, e)]
  if type(t) ~= "number" then return UNKNOWN end
  local cmp = comparators[term[3]]
  if not cmp then return UNKNOWN end
  return cmp(t, term[4])
end

--- One term, three-valued, honouring `negate`. Negation never rescues an unknown — a
--- refused read is not evidence the situation is absent (spec.md §3.5).
---
--- Assigned in a statement, never `fn and fn(...) or UNKNOWN`: a term that correctly
--- evaluates to `false` comes back UNKNOWN through that idiom.
function Tier.Term(term, e, w)
  local fn = evaluators[term[1]]
  local v = UNKNOWN
  if fn then v = fn(term, e, w) end
  if term.negate and v ~= UNKNOWN then return not v end
  return v
end

--- A band holds when EVERY term is true. An empty condition list is unconditional,
--- which is how a floor declares "always, at this tier". A term known false settles the
--- band whatever else refused; an unknown with nothing false fails it and reports blind.
local function bandHolds(band, e, w)
  local sawUnknown = false
  for _, term in ipairs(band.when or {}) do
    local v = Tier.Term(term, e, w)
    if v == UNKNOWN then
      sawUnknown = true
    elseif v == false then
      return false, false
    end
  end
  if sawUnknown then return false, true end
  return true, false
end

--------------------------------------------------------------------------------
-- Grade — continuous emphasis WITHIN a band; it never changes the band
--------------------------------------------------------------------------------

local function gradeOf(e, w)
  local g = e.grade
  if not g then return nil end
  -- A grade over a readable gate quantity is arithmetic cap may do itself, so it
  -- resolves to a number here. A grade over a channel is handed on as a descriptor:
  -- cap never sees that value and the client evaluates it.
  if g.channel == "resource" then
    local have, max = w.resource, w.resourceMax
    if type(have) ~= "number" or type(max) ~= "number" or max <= 0 then
      return { channel = g.channel, direction = g.direction }
    end
    local frac = have / max
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    if g.direction == "falling" then frac = 1 - frac end
    return { channel = g.channel, direction = g.direction, value = frac }
  end
  return { channel = g.channel, direction = g.direction, of = g.of }
end

--- A cue is offered only when its gate precondition holds — a band, so an unknown
--- withholds it. The channel is the client's, so what leaves here is an offer.
local function cuesOf(e, w)
  local out = {}
  for _, cue in ipairs(e.cues or {}) do
    if bandHolds({ when = cue.gate }, e, w) then
      out[#out + 1] = { polarity = cue.polarity, tier = cue.tier, channel = cue.channel }
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- Evaluate
--------------------------------------------------------------------------------

--- `bound` is Catalog.Resolve's output; `world` is Sense's plain snapshot.
---
--- Three counts, kept apart on purpose. `highs` is HIGH BANDS; `cuesOffered` is POSITIVE
--- HIGH cues handed to the client, which may or may not have drawn them; `holdsOffered`
--- is negative cues, and folding those in would report a press count that includes holds.
--- The honest reading of §3.5's HIGH-at-once distribution is highs plus the cue interval.
function Tier.Evaluate(bound, world)
  local out = { byEntry = {}, highs = 0, cuesOffered = 0, holdsOffered = 0, unknowns = 0 }
  local w = world or {}

  for _, item in ipairs(bound.entries or {}) do
    local e, row = item.entry, item.row
    local verdict = { entry = e.id, row = row, tier = nil, band = nil, cues = nil }

    for bi, band in ipairs(e.bands or {}) do
      local holds, blind = bandHolds(band, e, w)
      if blind then out.unknowns = out.unknowns + 1 end
      if holds then
        verdict.tier = band.tier
        verdict.band = bi
        break
      end
    end

    if verdict.tier then
      verdict.grade = gradeOf(e, w)
      if verdict.tier == "HIGH" then out.highs = out.highs + 1 end
    end
    verdict.cues = cuesOf(e, w)
    for _, cue in ipairs(verdict.cues) do
      if cue.polarity == "negative" then
        out.holdsOffered = out.holdsOffered + 1
      elseif cue.tier == "HIGH" then
        out.cuesOffered = out.cuesOffered + 1
      end
    end

    out.byEntry[e.id] = verdict
  end

  return out
end

Tier.BandHolds = bandHolds
