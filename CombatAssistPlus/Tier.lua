-- Tier.lua — first-match bands over a plain-data world. Pure: no game reads, no clock.
--
-- Two properties the format depends on and this enforces:
--   * entries never see each other — an entry is evaluated from its own terms alone;
--   * a gate is THREE-STATE. `unknown` is not `false`: it fails every band (conditions
--     are positive, so that composes) and is counted, so a quiet field and a blind one
--     are distinguishable in the log.
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

-- "this" is the entry the band belongs to. A window has no `this` and names its subject
-- outright, which is what lets one evaluator serve both surfaces.
local function subject(term, e)
  local id = term[2]
  if id == "this" then return e and e.id end
  return id
end

evaluators.ready = function(term, e, w)
  return three(w.ready and w.ready[subject(term, e)])
end

evaluators.affordable = function(term, e, w)
  return three(w.affordable and w.affordable[subject(term, e)])
end

evaluators.proc = function(term, e, w)
  return three(w.proc and w.proc[subject(term, e)])
end

evaluators.auraUp = function(term, e, w)
  return three(w.auraUp and w.auraUp[term[2]])
end

evaluators.talent = function(term, e, w)
  return three(w.talent and w.talent[term[2]])
end

evaluators.window = function(term, e, w)
  return three(w.window and w.window[term[2]])
end

-- The one gate that is not a game read: the target mode the player set. It cannot be
-- refused the way a sealed value can, but it is still three-valued — before cap has a
-- mode it is unknown, and an unknown mode must fail its band like anything else rather
-- than defaulting to single and quietly asserting an opinion nobody chose.
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

evaluators.elapsed = function(term, e, w)
  local t = w.elapsed and w.elapsed[subject(term, e)]
  if type(t) ~= "number" then return UNKNOWN end
  local cmp = comparators[term[3]]
  if not cmp then return UNKNOWN end
  return cmp(t, term[4])
end

Tier.Comparators = comparators

--- One term, three-valued, honouring `negate`. Bands may not negate (Catalog.Check
--- refuses it); windows are the one place that flag is legal, and Track evaluates them
--- through here so the two surfaces cannot drift apart on what a term means.
---
--- Assigned in a statement, never `fn and fn(...) or UNKNOWN`: a term that correctly
--- evaluates to `false` comes back UNKNOWN through that idiom, which is exactly the
--- distinction this file exists to keep.
function Tier.Term(term, e, w)
  local fn = evaluators[term[1]]
  local v = UNKNOWN
  if fn then v = fn(term, e, w) end
  if term.negate and v ~= UNKNOWN then return not v end
  return v
end

--- A band holds when EVERY term is true. An empty condition list is unconditional,
--- which is how a floor declares "always, at this tier".
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

--- A cue is offered only when its gate holds. The threshold is the client's to test,
--- so what leaves here is an offer, never a decision about the count.
local function cueOf(e, w)
  local cue = e.cue
  if not cue then return nil end
  local gate = { when = cue.gate }
  local holds = bandHolds(gate, e, w)
  if not holds then return nil end
  return { tier = cue.tier, threshold = cue.threshold }
end

--------------------------------------------------------------------------------
-- Evaluate
--------------------------------------------------------------------------------

--- `bound` is Catalog.Resolve's output; `world` is Sense's plain snapshot.
---
--- `highs` counts HIGH BANDS only, and `cuesOffered` counts HIGH cues handed to the
--- client, separately and on purpose: whether a cue is actually on screen depends on a
--- count cap never learns, so folding the two would report a number nothing observed.
--- The honest reading of §3.5's HIGH-at-once distribution is the interval between them.
function Tier.Evaluate(bound, world)
  local out = { byEntry = {}, highs = 0, cuesOffered = 0, unknowns = 0 }
  local w = world or {}

  for _, item in ipairs(bound.entries or {}) do
    local e, row = item.entry, item.row
    local verdict = { entry = e.id, row = row, tier = nil, band = nil }

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
    verdict.cue = cueOf(e, w)
    if verdict.cue and verdict.cue.tier == "HIGH" then out.cuesOffered = out.cuesOffered + 1 end

    out.byEntry[e.id] = verdict
  end

  return out
end

Tier.BandHolds = bandHolds
