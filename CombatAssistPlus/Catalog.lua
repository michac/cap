-- Catalog.lua — the closed vocabulary, the registry, and the checks.
--
-- Pure: nothing here reads the game. `Check` runs over the authored table at load;
-- `CheckBound` needs the live rows and runs from a bind. They are separate because
-- entries DROP at bind, so breadth over the authored table measures a catalog the
-- player is not running.
--
-- Format and rationale: ../../specs/spec.md §3.5 and ../../specs/demonology/catalog.md,
-- which is normative — if this disagrees with the document, this is wrong.
local ADDON, ns = ...

local Catalog = {}
ns.Catalog = Catalog

Catalog.TIERS = { HIGH = 3, MEDIUM = 2, LOW = 1 }

-- Gates: cap may branch on these, so they may appear in a band condition.
-- `arity` is how many arguments follow the term name; `subject` marks the terms whose
-- first argument names an entry — "this" in a band, an explicit id in a window.
Catalog.GATES = {
  ready = { arity = 1, subject = true },
  affordable = { arity = 1, subject = true },
  proc = { arity = 1, subject = true },
  identity = { arity = 2, subject = true },
  auraUp = { arity = 1 },
  talent = { arity = 1 },
  window = { arity = 1 },
  mode = { arity = 1 },
  resource = { arity = 2 },
  elapsed = { arity = 3, subject = true },
}

-- Window-only terms. A window is the one place negation is legal, and these three exist
-- only there: `remaining` needs a declared base cooldown, which is an assumption about
-- the build rather than an observation, and the other two describe the pull rather than
-- an ability. None may appear in a band condition.
Catalog.WINDOW_TERMS = {
  remaining = { arity = 3, subject = true },
  combat = { arity = 0 },
  casts = { arity = 2 },
}

-- Channels: cap never sees the value, it hands it to the client to draw. Legal in a
-- grade or a cue, never in a band condition.
Catalog.CHANNELS = {
  cooldownRemaining = { register = "graded" },
  auraRemaining = { register = "graded" },
  stacks = { register = "threshold" },
}

Catalog.MIN_HIGH_CAPABLE = 3
Catalog.MAX_WINDOWS = 6

local registry = {}

function Catalog.Register(cat)
  assert(type(cat) == "table", "Catalog.Register needs a table")
  assert(type(cat.spec) == "number", "catalog needs a numeric spec id")
  registry[#registry + 1] = cat
  return cat
end

function Catalog.All()
  return registry
end

--- The catalog claiming this build, or nil. A catalog with a `hero` matches only that
--- hero tree; one without matches any. A more specific claim wins.
function Catalog.ForBuild(specID, subTreeID)
  local loose
  for i = 1, #registry do
    local cat = registry[i]
    if cat.spec == specID then
      if cat.hero == nil then
        loose = loose or cat
      elseif cat.hero == subTreeID then
        return cat
      end
    end
  end
  return loose
end

--------------------------------------------------------------------------------
-- Term walking
--------------------------------------------------------------------------------

local function termName(term)
  return type(term) == "table" and term[1] or nil
end

--- Every band condition of every entry, plus every cue gate, as (entry, term) pairs.
local function eachBandTerm(cat, fn)
  for _, e in ipairs(cat.entries or {}) do
    for bi, band in ipairs(e.bands or {}) do
      for _, term in ipairs(band.when or {}) do
        fn(e, term, bi)
      end
    end
    if e.cue and e.cue.gate then
      for _, term in ipairs(e.cue.gate) do
        fn(e, term, "cue-gate")
      end
    end
  end
end

local function highCapable(e)
  for _, band in ipairs(e.bands or {}) do
    if band.tier == "HIGH" then return true end
  end
  return e.cue ~= nil and e.cue.tier == "HIGH"
end

--------------------------------------------------------------------------------
-- Reads — which gate does this catalog actually ask for, and of which entry
--------------------------------------------------------------------------------

-- `remaining` is not a read: Track derives it from the entry's own elapsed and its
-- declared base cooldown, so a window asking for one is asking for the other.
local IMPLIES = { remaining = "elapsed" }

--- `{ byEntry = { [entryID] = { ready = true, … } }, auras = { [spellID] = true } }`.
---
--- Two jobs, and both matter for honesty rather than for speed. It tells Sense which
--- reads to make — and it tells the health tally which gates an entry was ever meant to
--- answer, so a gate nobody asks for does not inflate the refused count and make a
--- working catalog read blind.
function Catalog.Reads(cat)
  local byEntry, auras = {}, {}

  local function want(entryID, gate)
    if type(entryID) ~= "string" then return end
    gate = IMPLIES[gate] or gate
    local t = byEntry[entryID]
    if not t then t = {}; byEntry[entryID] = t end
    t[gate] = true
  end

  -- In a band the subject is always the entry the band belongs to; `auraUp` names an
  -- aura outright and belongs to no entry.
  eachBandTerm(cat, function(e, term)
    local name = termName(term)
    if name == "auraUp" then auras[term[2]] = true; return end
    local spec = name and Catalog.GATES[name]
    if spec and spec.subject then want(e.id, name) end
  end)

  for _, rule in pairs(cat.windows or {}) do
    for _, term in ipairs(rule) do
      local name = termName(term)
      if name == "auraUp" then
        auras[term[2]] = true
      else
        local spec = name and (Catalog.GATES[name] or Catalog.WINDOW_TERMS[name])
        if spec and spec.subject then want(term[2], name) end
      end
    end
  end

  return { byEntry = byEntry, auras = auras }
end

--------------------------------------------------------------------------------
-- Check — pure, over the AUTHORED table. spec.md §3.5 checks 2-6.
--------------------------------------------------------------------------------

--- Returns a list of findings; empty means the catalog loads. A finding is
--- `{check, entry, detail}` — never a boolean, because "which check and where" is the
--- only part a reader can act on.
function Catalog.Check(cat)
  local found = {}
  local function fail(check, entry, detail)
    found[#found + 1] = { check = check, entry = entry, detail = detail }
  end

  if type(cat.entries) ~= "table" or #cat.entries == 0 then
    fail("shape", nil, "catalog declares no entries")
    return found
  end

  local windows = cat.windows or {}
  local nWindows = 0
  for _ in pairs(windows) do nWindows = nWindows + 1 end
  if nWindows > Catalog.MAX_WINDOWS then
    fail("shape", nil, ("%d windows declared, the cap is %d"):format(nWindows, Catalog.MAX_WINDOWS))
  end

  local seenIDs = {}
  for _, e in ipairs(cat.entries) do
    if type(e.id) ~= "string" or e.id == "" then
      fail("shape", nil, "entry with no id")
    elseif seenIDs[e.id] then
      fail("shape", e.id, "duplicate entry id")
    else
      seenIDs[e.id] = true
    end
    if type(e.spell) ~= "number" then
      fail("shape", e.id, "entry has no numeric spell id")
    end
    for _, band in ipairs(e.bands or {}) do
      if Catalog.TIERS[band.tier] == nil then
        fail("shape", e.id, ("band declares tier %q, which is not a tier"):format(tostring(band.tier)))
      end
    end
  end

  -- Windows: a rule list, evaluated by Track. Negation is legal here and nowhere else,
  -- and a window may not name another window — a cycle would have no first-match to stop
  -- it, and the six-window cap is what keeps a priority ladder from being re-encoded here.
  for name, rule in pairs(windows) do
    if type(rule) ~= "table" or #rule == 0 then
      fail("shape", nil, ("window %q declares no rule"):format(tostring(name)))
    else
      for _, term in ipairs(rule) do
        local tName = termName(term)
        local spec = tName and (Catalog.WINDOW_TERMS[tName] or Catalog.GATES[tName])
        if tName == nil then
          fail("register", nil, ("window %q carries a term that is not a table"):format(tostring(name)))
        elseif tName == "window" then
          fail("vocabulary", nil, ("window %q names another window"):format(tostring(name)))
        elseif Catalog.CHANNELS[tName] then
          fail("register", nil, ("%q is a channel and may not appear in window %q"):format(tName, tostring(name)))
        elseif not spec then
          fail("vocabulary", nil, ("%q is not in the window vocabulary (window %q)"):format(tName, tostring(name)))
        else
          if #term ~= spec.arity + 1 then
            fail("vocabulary", nil,
              ("%s takes %d argument(s), got %d (window %q)"):format(tName, spec.arity, #term - 1, tostring(name)))
          end
          if spec.subject and term[2] ~= nil and seenIDs[term[2]] == nil then
            fail("vocabulary", nil,
              ("window %q names entry %q, which this catalog does not declare"):format(tostring(name), tostring(term[2])))
          end
        end
      end
    end
  end

  -- Check 2: breadth.
  local nHigh = 0
  for _, e in ipairs(cat.entries) do
    if highCapable(e) then nHigh = nHigh + 1 end
  end
  if nHigh < Catalog.MIN_HIGH_CAPABLE then
    fail("breadth", nil,
      ("%d HIGH-capable entries, the floor is %d — one ability owning HIGH is a ranked list")
        :format(nHigh, Catalog.MIN_HIGH_CAPABLE))
  end

  -- Checks 3 and 4: every band term is a GATE, named, of the right arity, and
  -- positive. A channel term reaching a band is the register-legality failure; an
  -- unknown name is check 3, since the vocabulary is what makes "another entry's
  -- tier" inexpressible.
  eachBandTerm(cat, function(e, term, where)
    local name = termName(term)
    if name == nil then
      fail("register", e.id, ("band %s carries a term that is not a table"):format(tostring(where)))
      return
    end
    if Catalog.CHANNELS[name] then
      fail("register", e.id, ("%q is a channel and may not appear in a band condition"):format(name))
      return
    end
    local gate = Catalog.GATES[name]
    if not gate then
      fail("vocabulary", e.id, ("%q is not in the gate vocabulary"):format(name))
      return
    end
    if #term ~= gate.arity + 1 then
      fail("vocabulary", e.id, ("%s takes %d argument(s), got %d"):format(name, gate.arity, #term - 1))
    end
    if term.negate then
      fail("positive", e.id, ("%s is negated; band conditions are positive"):format(name))
    end
    if name == "window" and windows[term[2]] == nil then
      fail("vocabulary", e.id, ("window %q is not declared"):format(tostring(term[2])))
    end
  end)

  -- Check 4 again, on the other side: a grade or a threshold must name a real channel.
  for _, e in ipairs(cat.entries) do
    local g = e.grade
    if g then
      if not (Catalog.CHANNELS[g.channel] or Catalog.GATES[g.channel]) then
        fail("register", e.id, ("grade names %q, which is neither a channel nor a gate"):format(tostring(g.channel)))
      end
    end
    local cue = e.cue
    if cue then
      -- Check 5: cue honesty.
      if Catalog.TIERS[cue.tier] == nil then
        fail("cue-honesty", e.id, "cue declares no tier — a cue is drawn in the tier it stands for")
      end
      if cue.tier == "HIGH" and (type(cue.gate) ~= "table" or #cue.gate == 0) then
        fail("cue-honesty", e.id,
          "a HIGH cue with no gate precondition is permanently lit, which fails §3.1 like a bare HIGH band")
      end
      local th = cue.threshold
      if type(th) ~= "table" or th.channel ~= "stacks" then
        fail("register", e.id, "a cue's threshold must be a stack count — nothing else may drive one")
      elseif type(th.of) ~= "number" or type(th.min) ~= "number" then
        fail("register", e.id, "a stacks threshold needs a numeric aura id and a numeric minimum")
      end
    end
  end

  -- Check 6: a named floor.
  if type(cat.floor) ~= "number" then
    fail("floor", nil, "catalog names no floor — the ability to press when nothing is lit")
  end

  -- A `resource` term with no declared power type can never be answered, so every band
  -- carrying one silently fails for the life of the build. That is an authoring defect
  -- and not a refused read, and only a load-time check can tell the two apart.
  local usesResource = false
  eachBandTerm(cat, function(_, term)
    if termName(term) == "resource" then usesResource = true end
  end)
  if usesResource and type(cat.power) ~= "string" then
    fail("shape", nil, "catalog branches on `resource` but declares no `power` type to read it from")
  end

  return found
end

--------------------------------------------------------------------------------
-- CheckBound — needs the live rows. Coverage, and breadth RE-RUN after drops.
--------------------------------------------------------------------------------

--- Which entries survive this build, and which rows nothing accounts for.
---
--- `rows` is `ns.Bind.Rows()`. An entry binds to the row whose spellIDs contain its
--- spell AND whose family matches; an ability on two rows (one press, one aura) is the
--- reason family is part of the key rather than a tiebreak.
function Catalog.Resolve(cat, rows)
  local out = { entries = {}, dropped = {}, claimed = {}, byEntry = {} }

  local function match(spell, family)
    for i = 1, #rows do
      local row = rows[i]
      if row.family == family and row.spellIDs and row.spellIDs[spell] then return row end
    end
    return nil
  end

  for _, e in ipairs(cat.entries or {}) do
    local row = match(e.spell, e.family or "spells")
    if row then
      out.entries[#out.entries + 1] = { entry = e, row = row }
      out.byEntry[e.id] = row
      out.claimed[row.cooldownID] = e.id
    else
      out.dropped[#out.dropped + 1] = { id = e.id, spell = e.spell, why = "no CDM row on this build" }
    end
  end

  -- A silence names an ability and covers every row carrying that base spellID, unless
  -- an entry claimed a specific row first. That is what lets one line cover an ability
  -- tracked on two viewers.
  for _, s in ipairs(cat.silences or {}) do
    for i = 1, #rows do
      local row = rows[i]
      local familyOK = (s.family == nil) or (row.family == s.family)
      if familyOK and row.spellIDs and row.spellIDs[s.spell] and not out.claimed[row.cooldownID] then
        out.claimed[row.cooldownID] = "silence"
      end
    end
  end

  return out
end

--- Findings a bind can produce that a load cannot: coverage, and breadth measured on
--- the entries that actually survived.
function Catalog.CheckBound(cat, rows)
  local resolved = Catalog.Resolve(cat, rows)
  local found = {}
  local function fail(check, entry, detail)
    found[#found + 1] = { check = check, entry = entry, detail = detail }
  end

  -- Check 1: coverage.
  for i = 1, #rows do
    local row = rows[i]
    if not resolved.claimed[row.cooldownID] then
      fail("coverage", nil,
        ("row %d (%s/%s, spell %s) is neither an entry nor a declared silence")
          :format(row.cooldownID, tostring(row.short), tostring(row.family), tostring(row.primary)))
    end
  end

  -- Check 2, re-run: breadth over what survived.
  local nHigh = 0
  for _, bound in ipairs(resolved.entries) do
    if highCapable(bound.entry) then nHigh = nHigh + 1 end
  end
  if nHigh < Catalog.MIN_HIGH_CAPABLE then
    fail("breadth", nil,
      ("%d HIGH-capable entries survived the bind (of %d authored), the floor is %d")
        :format(nHigh, #(cat.entries or {}), Catalog.MIN_HIGH_CAPABLE))
  end

  return found, resolved
end

Catalog.HighCapable = highCapable
