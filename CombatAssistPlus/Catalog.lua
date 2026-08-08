-- Catalog.lua — the closed vocabulary, the registry, and the five checks.
--
-- Pure: nothing here reads the game. `Check` runs over the authored table at load;
-- `CheckBound` needs the live rows and runs from a bind. They are separate because
-- coverage is a question about the rows the player is actually running — which entries
-- survived the bind, and which live rows nothing accounts for — and the authored table
-- cannot answer it.
--
-- Format and rationale: ../../specs/spec.md §3.5 and ../../specs/demonology/catalog.md,
-- which is normative — if this disagrees with the document, this is wrong.
local ADDON, ns = ...

local Catalog = {}
ns.Catalog = Catalog

Catalog.TIERS = { HIGH = 3, MEDIUM = 2, LOW = 1 }

-- Gates: cap may branch on these, so they may appear in a band condition and in a cue's
-- gate precondition, negated or not.
--
-- `subject` is the FORM the term's first argument takes, and it is what check 3 polices.
-- Membership alone is not enough: the two forms are answered by different machinery and a
-- subject of the wrong form can never be answered at all.
--   * `"entry"` — `this`, or the id of an entry this catalog declares. These are read off
--     a bound CDM row, and only entries resolve to rows.
--   * `"aura"` — an aura SPELL ID (a number) an entry or a silence declares. The aura
--     latch is keyed by spell id, so an entry id here is dead the same way round.
-- A term with no `subject` takes none: `resource` and `combat` describe the pull, `mode`'s
-- argument is a literal, and `talent`'s is a talent §3.5 exempts on purpose.
--
-- `thisOnly` is `elapsed` alone, cap's own arithmetic, which may estimate about the
-- entry's own ability and nothing else.
Catalog.GATES = {
  ready = { arity = 1, subject = "entry" },
  affordable = { arity = 1, subject = "entry" },
  proc = { arity = 1, subject = "entry" },
  identity = { arity = 2, subject = "entry" },
  auraUp = { arity = 1, subject = "aura" },
  -- ⚠ NOT ANSWERED BY `Sense.buildReads` TODAY, and not in its `GATE_ORDER` either — so a
  -- band using `talent(x)` reads unknown for the life of the build and nothing tallies the
  -- refusal. Nothing uses it; wire it or delete it from spec.md §3.5 before something does
  -- (`../../specs/backlog.md` → Next → Cross-cutting).
  talent = { arity = 1 },
  mode = { arity = 1 },
  resource = { arity = 2 },
  combat = { arity = 0 },
  elapsed = { arity = 3, subject = "entry", thisOnly = true },
}

-- Channels: cap never sees the value, it hands it to the client to draw. Two literal
-- forms, `{name, subject}` and `{name, subject, cmp, t}`; `threshold` names the one
-- comparator §3.5's table gives each. The bare form is §3.4's countdown and the
-- thresholded form is a cue's edge, so a channel missing one is missing it on purpose.
--
-- `subject` reads exactly as it does in GATES, and for the same reason: cap hands the
-- client a ROW for `cooldownRemaining` and `active`, and a spell id for the aura pair.
Catalog.CHANNELS = {
  cooldownRemaining = { subject = "entry", bare = true, threshold = "<=" },
  auraRemaining = { subject = "aura", bare = true, threshold = "<=" },
  stacks = { subject = "aura", threshold = ">=" },
  active = { subject = "entry", bare = true },
}

Catalog.POLARITIES = { positive = true, negative = true }

-- `casts == n` is legal in a sequence trigger and nowhere else: a band testing a position
-- in an order writes an opener, which duplicates spec.md §3.3 and breaches §4. It is named
-- here so a band carrying it fails with the reason rather than as an unknown word.
Catalog.SEQUENCE_ONLY = { casts = { arity = 2 } }

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

--- The ENTRY a term names; `this` is the entry the term belongs to. One resolver, so a
--- band and a cue cannot disagree.
---
--- ⚠ For `subject = "entry"` terms only. An aura argument is a spell id, is never `this`,
--- and does not come through here — resolving one would put an entry id in the aura set.
function Catalog.Subject(term, e)
  local id = term[2]
  if id == "this" then return e and e.id end
  return id
end

--- Every band-legal condition, as (entry, term, where) triples — a cue's gate
--- precondition is band-legal by definition, so it walks through here too.
local function eachBandTerm(cat, fn)
  for _, e in ipairs(cat.entries or {}) do
    for bi, band in ipairs(e.bands or {}) do
      for _, term in ipairs(band.when or {}) do
        fn(e, term, bi)
      end
    end
    for ci, cue in ipairs(e.cues or {}) do
      for _, term in ipairs(cue.gate or {}) do
        fn(e, term, "cue" .. ci)
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Reads — which gate does this catalog actually ask for, and about which entry
--------------------------------------------------------------------------------

--- `{ byEntry = { [entryID] = { ready = true, … } }, auras = { [spellID] = true } }`.
---
--- Keyed by the SUBJECT, not by the entry that named it: `not ready(E2)` in E1's band is
--- a read of E2, and tallying it against E1 would report a working catalog as blind.
function Catalog.Reads(cat)
  local byEntry, auras = {}, {}

  eachBandTerm(cat, function(e, term)
    local name = termName(term)
    local gate = name and Catalog.GATES[name]
    if not (gate and gate.subject) then return end
    -- An aura argument is taken RAW. It is a spell id, `this` is meaningless in it
    -- (check 3 refuses one), and resolving it would file an entry id in the aura set —
    -- where `Track.Binding` filters it straight back out and the band goes silently dead.
    if gate.subject == "aura" then
      if type(term[2]) == "number" then auras[term[2]] = true end
      return
    end
    local subj = Catalog.Subject(term, e)
    if type(subj) == "string" then
      local t = byEntry[subj]
      if not t then t = {}; byEntry[subj] = t end
      t[name] = true
    end
  end)

  return { byEntry = byEntry, auras = auras }
end

--------------------------------------------------------------------------------
-- Check — pure, over the AUTHORED table. spec.md §3.5's checks 2, 3, 4 and 5, plus the
-- shape and vocabulary failures a closed vocabulary implies. Check 1 (coverage) needs the
-- live rows and lives in CheckBound.
--------------------------------------------------------------------------------

--- What the catalog declares, split by the FORM a subject may name it in: `entries` are
--- the entry ids a row-backed term may name, `auras` the base spell ids an aura term may.
--- An entry contributes to both — its id as an entry, its spell (and its alts) as an aura
--- its own row could carry.
local function declaredSubjects(cat)
  local entries, auras = {}, {}
  for _, e in ipairs(cat.entries or {}) do
    if type(e.id) == "string" then entries[e.id] = true end
    if type(e.spell) == "number" then auras[e.spell] = true end
    for _, a in ipairs(e.alt or {}) do auras[a] = true end
  end
  for _, s in ipairs(cat.silences or {}) do
    if type(s.spell) == "number" then auras[s.spell] = true end
  end
  return { entries = entries, auras = auras }
end

--- Check 3, for one argument, and the WHOLE of check 3: a term does not merely name
--- something the catalog declares, it names something of the form that term can be
--- answered in. The two are not interchangeable and the difference is invisible at
--- runtime — `{"proc", 264173}` naming a declared silence type-checks, passes every other
--- check, evaluates UNKNOWN for the life of the build, and gate health still reads
--- `proc:1/1` because nothing refused: the read was never asked for.
---
--- `nil` when the argument is admissible; the reason it is not otherwise.
local function subjectFault(kind, arg, e, declared)
  if kind == nil then return nil end

  if kind == "entry" then
    if arg == "this" then return nil end
    if type(arg) ~= "string" then
      return ("names spell %s, but this term is read off a bound row — its subject must be `this` or an entry id"):format(tostring(arg))
    end
    if not declared.entries[arg] then
      return ("names %s, which this catalog does not declare as an entry"):format(arg)
    end
    return nil
  end

  -- "aura"
  if type(arg) ~= "number" then
    return ("names %s, but an aura is named by its spell id and never by an entry"):format(tostring(arg))
  end
  if not declared.auras[arg] then
    return ("names aura %s, which no entry or silence declares"):format(tostring(arg))
  end
  return nil
end

--- `"bare"` or `"threshold"`, or nil plus the reason.
local function channelForm(term)
  local name = termName(term)
  local spec = name and Catalog.CHANNELS[name]
  if not spec then
    return nil, ("%s is not a channel"):format(tostring(name))
  end
  if #term == 2 then
    if not spec.bare then return nil, ("%s has no bare form"):format(name) end
    return "bare"
  end
  if #term == 4 then
    if not spec.threshold then return nil, ("%s has no thresholded form"):format(name) end
    if term[3] ~= spec.threshold then
      return nil, ("%s thresholds with %s, not %s"):format(name, spec.threshold, tostring(term[3]))
    end
    if type(term[4]) ~= "number" then return nil, ("%s needs a numeric threshold"):format(name) end
    return "threshold"
  end
  return nil, ("%s takes 1 or 3 arguments, got %d"):format(name, #term - 1)
end

--- Returns findings, then check-5 disclosures. A finding is `{check, entry, detail}`,
--- never a boolean — "which check and where" is the only part a reader can act on.
--- Disclosures are the same shape and separate because check 5 CANNOT fail.
function Catalog.Check(cat)
  local found, disclosed = {}, {}
  local function fail(check, entry, detail)
    found[#found + 1] = { check = check, entry = entry, detail = detail }
  end

  if type(cat.entries) ~= "table" or #cat.entries == 0 then
    fail("shape", nil, "catalog declares no entries")
    return found, disclosed
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
        fail("shape", e.id, ("band declares tier %s, which is not a tier"):format(tostring(band.tier)))
      end
    end
  end

  local declared = declaredSubjects(cat)

  -- Check 2 (register legality) and check 3 (declared subjects), over every band-legal
  -- condition. A channel reaching a band is check 2 — the one place principle (a) stops
  -- being an intention — and an unknown name is what makes "another entry's verdict"
  -- inexpressible rather than merely discouraged. Check 3 is `subjectFault`, which asks
  -- about the FORM of the subject and not only its membership: a subject of the wrong form
  -- is unanswerable rather than merely undeclared, and its band would read UNKNOWN forever
  -- while gate health reported the gate as fully known.
  local usesResource = false
  eachBandTerm(cat, function(e, term, where)
    local name = termName(term)
    if name == nil then
      fail("register", e.id, ("condition %s carries a term that is not a table"):format(tostring(where)))
      return
    end
    if Catalog.CHANNELS[name] then
      fail("register", e.id, ("%s is a channel and may not appear in a band condition"):format(name))
      return
    end
    if Catalog.SEQUENCE_ONLY[name] then
      fail("register", e.id, ("%s is sequence-trigger vocabulary and may not appear in a band"):format(name))
      return
    end
    local gate = Catalog.GATES[name]
    if not gate then
      fail("vocabulary", e.id, ("%s is not in the gate vocabulary"):format(name))
      return
    end
    if #term ~= gate.arity + 1 then
      fail("vocabulary", e.id, ("%s takes %d argument(s), got %d"):format(name, gate.arity, #term - 1))
      return
    end
    if name == "resource" then usesResource = true end
    if gate.thisOnly and term[2] ~= "this" then
      fail("vocabulary", e.id, ("%s is restricted to this and names %s"):format(name, tostring(term[2])))
      return
    end
    local fault = subjectFault(gate.subject, term[2], e, declared)
    if fault then
      fail("subject", e.id, ("%s %s"):format(name, fault))
    end
  end)

  for _, e in ipairs(cat.entries) do
    -- A grade names a readable gate quantity or a channel; either way its subject is
    -- check 3's, in that term's own form, and `resource` carries no subject at all.
    local g = e.grade
    if g then
      local spec = Catalog.CHANNELS[g.channel] or Catalog.GATES[g.channel]
      if not spec then
        fail("register", e.id, ("grade names %s, which is neither a channel nor a gate"):format(tostring(g.channel)))
      elseif g.of ~= nil then
        if spec.subject == nil then
          fail("subject", e.id, ("grade names %s of %s, and %s takes no subject"):format(
            tostring(g.channel), tostring(g.of), tostring(g.channel)))
        else
          local fault = subjectFault(spec.subject, g.of, e, declared)
          if fault then fail("subject", e.id, ("grade %s"):format(fault)) end
        end
      end
    end

    -- Check 4, cue schema: the fields the renderer needs to draw anything at all. The
    -- thresholded-channel rule on a negative cue is the one with teeth — a bare countdown
    -- draws `hold` at 45 s out as readily as at 5.
    for ci, cue in ipairs(e.cues or {}) do
      local at = ("cue %d"):format(ci)
      if not Catalog.POLARITIES[cue.polarity] then
        fail("cue", e.id, ("%s declares polarity %s, which is neither positive nor negative"):format(at, tostring(cue.polarity)))
      elseif cue.polarity == "positive" and Catalog.TIERS[cue.tier] == nil then
        fail("cue", e.id, ("%s is positive and declares no tier — a positive cue is drawn in the tier it stands for"):format(at))
      elseif cue.polarity == "negative" and cue.tier ~= nil then
        fail("cue", e.id, ("%s is negative and declares a tier — the hold treatment belongs to no tier"):format(at))
      end
      if type(cue.gate) ~= "table" or #cue.gate == 0 then
        fail("cue", e.id, ("%s carries no gate precondition, so it is permanently offered"):format(at))
      end
      local form, why = channelForm(cue.channel)
      if not form then
        fail("register", e.id, ("%s channel: %s"):format(at, why))
      else
        local fault = subjectFault(Catalog.CHANNELS[termName(cue.channel)].subject, cue.channel[2], e, declared)
        if fault then
          fail("subject", e.id, ("%s channel %s"):format(at, fault))
        end
        if cue.polarity == "negative" and form ~= "threshold" then
          fail("cue", e.id, ("%s is negative and its channel is un-thresholded"):format(at))
        end
      end
    end
  end

  -- Check 5, estimate disclosure. It reports, never fails, and names the channel that
  -- would replace the estimate — principle (a)'s own to-do list.
  local REPLACEMENT = { elapsed = "auraRemaining(x) or cooldownRemaining(x)" }
  eachBandTerm(cat, function(e, term, where)
    local name = termName(term)
    if name and Catalog.GATES[name] and Catalog.GATES[name].thisOnly then
      disclosed[#disclosed + 1] = {
        check = "estimate", entry = e.id,
        detail = ("%s estimates with %s; %s would be exact"):format(tostring(where), name, REPLACEMENT[name] or "a channel"),
      }
    end
  end)

  -- A `resource` term with no declared power type can never be answered, so every band
  -- carrying one silently fails for the life of the build. That is an authoring defect
  -- and not a refused read, and only a load-time check can tell the two apart.
  if usesResource and type(cat.power) ~= "string" then
    fail("shape", nil, "catalog branches on `resource` but declares no `power` type to read it from")
  end

  return found, disclosed
end

--------------------------------------------------------------------------------
-- CheckBound — needs the live rows. Coverage (spec.md §3.5 check 1) and nothing else.
--------------------------------------------------------------------------------

--- Which entries survive this build, and which rows nothing accounts for.
---
--- `rows` is `ns.Bind.Rows()`. An entry binds to the row whose spellIDs contain its
--- spell AND whose family matches; an ability on two rows (one press, one aura) is the
--- reason family is part of the key rather than a tiebreak. `alt` is tried after `spell`,
--- which is what lets one entry cover both halves of a choice node.
function Catalog.Resolve(cat, rows)
  local out = { entries = {}, dropped = {}, claimed = {}, byEntry = {} }

  local function find(spell, family)
    for i = 1, #rows do
      local row = rows[i]
      if row.family == family and row.spellIDs and row.spellIDs[spell] then return row end
    end
    return nil
  end

  local function match(e)
    local family = e.family or "spells"
    local row = find(e.spell, family)
    if row then return row end
    for _, alt in ipairs(e.alt or {}) do
      row = find(alt, family)
      if row then return row end
    end
    return nil
  end

  for _, e in ipairs(cat.entries or {}) do
    local row = match(e)
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

--- The one finding a bind can produce that a load cannot: coverage, measured against the
--- rows the player is actually running.
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

  return found, resolved
end
