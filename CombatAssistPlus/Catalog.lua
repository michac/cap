-- Catalog.lua — the small authored contract between a spec and cap's renderer.
-- Pure: this validates plain data and resolves it against Bind rows; it reads no game API.
local ADDON, ns = ...

local Catalog = {}
ns.Catalog = Catalog

local registry = {}
-- `subject = true` means "argument 1 is an ability id, declared in `abilities`". `talent = true`
-- means "argument 1 is a talent id, declared in `talents`" — a separate subject class because a
-- talent has no CDM row and must never be resolved as if it did. `aoe` takes no subject at all:
-- it is cap's OWN state (the /cap aoe toggle), the one gate that is not a game read.
local PREDICATES = {
  ready = { arity = 1, subject = true },
  proc = { arity = 1, subject = true },
  identity = { arity = 2, subject = true },
  capped = { arity = 1, subject = true },
  affordable = { arity = 1, subject = true },
  resource = { arity = 2 },
  talent = { arity = 1, talent = true },
  -- Is this AURA on its unit right now? The subject is an ability in the `auras` family, so it
  -- binds to a Cooldown Manager tracked-buff/bar row and the latch rides that row's alert edges.
  -- Unbound row (the player never enabled it) => no cid => UNKNOWN, never false. See Track.
  aura = { arity = 1, subject = true },
  aoe = { arity = 0 },
}
Catalog.PREDICATES = PREDICATES
-- ⚠ A KIND LISTED HERE WITH NO MATCHING BRANCH IN `Catalog.Check` IS ACCEPTED WITH ZERO FIELD
-- CHECKS. The list decides whether a display is *known*; the branch is the only thing that
-- decides whether it is *shaped right*. Add both or neither.
local DISPLAYS = {
  ["sealed-count-bands"] = true,
  ["sealed-count-bar"] = true,
  ["sealed-pandemic"] = true,
  ["sealed-proc-bar"] = true,
  ["sealed-power-percent"] = true,
  ["sealed-cooldown-range"] = true,
}
Catalog.DISPLAYS = DISPLAYS

-- The corner CLAIMERS (render-shelf.md Part 2.5's cession rule): kinds whose widgets sit on the
-- badge stack's corner slots. Claimed BY DECLARATION, in marker order, whether or not the
-- client is currently showing anything — that fact is sealed and the stack cannot re-flow on
-- it. Overlay assigns the slots; the row's cue badges start below them.
local CORNER_DISPLAYS = {
  ["sealed-count-bands"] = true,
  ["sealed-pandemic"] = true,
}
Catalog.CORNER_DISPLAYS = CORNER_DISPLAYS

-- What ONE band of a `sealed-count-bands` display draws, as meaning rather than as pixels. The
-- shelf (render-shelf.md V16/V17) owns the art each of these resolves to; a catalog picks from
-- this list and never writes a format string.
--   none        — the resting state. The client draws nothing at all for values in this band.
--   count       — the number, while `how many more` is still the live question.
--   mark        — one badge, plate and glyph, once `how many more` has stopped being one.
-- `count` and `mark` are EXCLUSIVE. The client accepts both from one band and draws the numeral
-- on top of the glyph, in the same hue, on the same corner — a digit over a symbol, which reads
-- as a fault rather than as a statement. There is no offset that separates them without spending
-- a second corner the badge stack already wants.
-- `polarity` says which hue the band spends (V5.1: hue carries polarity and only polarity) and
-- `hatch` adds V11's stripe sheet across the face, which is the row RULED OUT rather than
-- decorated — the only thing on this list that changes the elimination walk.
local COUNT_DRAWS = {
  ["none"] = true, ["count"] = true, ["mark"] = true,
}
Catalog.COUNT_DRAWS = COUNT_DRAWS

-- The cue vocabulary is the GENERATED shelf's, read at call time rather than copied here:
-- a second list would let the addon invent a fifth cue that renders nowhere.
local function cues()
  return (ns.Style or {}).cues or {}
end

function Catalog.Register(cat)
  assert(type(cat) == "table", "Catalog.Register needs a table")
  assert(type(cat.spec) == "number", "catalog needs a numeric spec id")
  registry[#registry + 1] = cat
  return cat
end

function Catalog.All()
  return registry
end

function Catalog.ForBuild(specID, subTreeID)
  local loose
  for _, cat in ipairs(registry) do
    if cat.spec == specID then
      if cat.hero == subTreeID then return cat end
      if cat.hero == nil then loose = loose or cat end
    end
  end
  return loose
end

-- Scan membership is an OR of ANDs: `scan_when` lists alternatives, each a list of readable
-- terms. An entry with no `scan_when` gets the default alternative — ready(self) — which is
-- also why the default's read is registered here: Reads/Resolve walk this too, and a row whose
-- only condition is implicit must still subscribe its readiness.
function Catalog.Alternatives(entry)
  return entry.scan_when or { { { "ready", entry.ability } } }
end

local function eachCondition(cat, fn)
  for _, entry in ipairs(cat.entries or {}) do
    local alts = Catalog.Alternatives(entry)
    for i, alt in ipairs(type(alts) == "table" and alts or {}) do
      if type(alt) == "table" then
        for _, term in ipairs(alt) do fn(entry, term, "scan_when alternative " .. i) end
      end
    end
    for _, marker in ipairs(entry.markers or {}) do
      for _, term in ipairs(marker.when or {}) do fn(entry, term, "marker " .. tostring(marker.id)) end
    end
  end
end

function Catalog.Check(cat)
  local found = {}
  local function fail(check, entry, detail)
    found[#found + 1] = { check = check, entry = entry, detail = detail }
  end

  local abilities = {}
  for _, ability in ipairs(cat.abilities or {}) do
    if type(ability.id) ~= "string" or ability.id == "" then
      fail("shape", nil, "ability has no id")
    elseif abilities[ability.id] then
      fail("shape", ability.id, "duplicate ability id")
    else
      abilities[ability.id] = ability
    end
    if type(ability.spell) ~= "number" then fail("shape", ability.id, "ability has no numeric spell id") end
    if ability.charged ~= nil and type(ability.charged) ~= "boolean" then
      fail("shape", ability.id, "charged must be boolean")
    end
  end

  -- Talents are declared the way abilities are, and for the same reason: a term names a
  -- readable id, never a raw number. `node` + `entry` are what the trait config is keyed on —
  -- the thing the APL's `talent.<x>` actually means — so they are read directly rather than
  -- inferred from a spell being known or from how many charges a button has.
  local talents = {}
  for _, talent in ipairs(cat.talents or {}) do
    if type(talent.id) ~= "string" or talent.id == "" then
      fail("shape", nil, "talent has no id")
    elseif talents[talent.id] then
      fail("shape", talent.id, "duplicate talent id")
    else
      talents[talent.id] = talent
    end
    if type(talent.node) ~= "number" then fail("shape", talent.id, "talent has no numeric node id") end
    if type(talent.entry) ~= "number" then fail("shape", talent.id, "talent has no numeric entry id") end
  end

  local entries = {}
  for _, entry in ipairs(cat.entries or {}) do
    if type(entry.id) ~= "string" or entry.id == "" then
      fail("shape", nil, "entry has no id")
    elseif entries[entry.id] then
      fail("shape", entry.id, "duplicate entry id")
    else
      entries[entry.id] = true
    end
    if not abilities[entry.ability] then
      fail("subject", entry.id, "entry names an undeclared ability")
    end
    -- The role-tier `bands` left the model 2026-08-25. Reject them by name so a stale catalog
    -- fails loudly instead of silently losing its membership conditions to the default.
    if entry.bands ~= nil then
      fail("shape", entry.id, "entry declares retired `bands`; membership is `scan_when`")
    end
    if entry.scan_when ~= nil then
      if type(entry.scan_when) ~= "table" or #entry.scan_when == 0 then
        fail("shape", entry.id, "scan_when must be a non-empty list of alternatives")
      else
        for i, alt in ipairs(entry.scan_when) do
          if type(alt) ~= "table" or #alt == 0 then
            fail("shape", entry.id, "scan_when alternative " .. i .. " has no readable condition")
          end
        end
      end
    end
    local markerIDs, positive = {}, nil
    for _, marker in ipairs(entry.markers or {}) do
      if type(marker.id) ~= "string" or marker.id == "" then
        fail("shape", entry.id, "marker has no id")
      elseif markerIDs[marker.id] then
        fail("shape", entry.id, "duplicate marker id " .. marker.id)
      else
        markerIDs[marker.id] = true
      end
      -- `cue` stays OPTIONAL: a marker with none is evaluated and reported but draws nothing.
      -- A marker carrying only a `display` is the shipped case; one carrying neither is legal
      -- and silent.
      if marker.cue ~= nil then
        local cue = cues()[marker.cue]
        if not cue then
          fail("cue", entry.id, "marker " .. tostring(marker.id) .. " names undeclared cue "
            .. tostring(marker.cue))
        elseif cue.polarity == "positive" and positive and positive ~= marker.cue then
          -- Badges STACK now (render-shelf.md Part 1: they flow down the right edge in `rank`
          -- order), so two cues on one entry is ordinary and no longer a collision. The one
          -- thing that stays undefined is two POSITIVE cues on a single button: pass 1 says
          -- "press the positive cue" and says nothing about which of two wins.
          fail("cue", entry.id, ("cues %s and %s are both positive on one entry; pass 1 has no "
            .. "tie-break"):format(positive, marker.cue))
        elseif cue.polarity == "positive" then
          positive = marker.cue
        end
      end
      -- A marker is a readable cue, a sealed cue, or a sealed cue WITH readable gates. The last
      -- shape exists because a graded cue may curve on exactly one secret but may be gated on as
      -- many readable facts as you like — so `when` beside a `display` never contributes a cue of
      -- its own, it only decides whether the client is allowed to paint the sealed one.
      local readable = marker.when ~= nil
      local sealed = marker.display ~= nil
      if not (readable or sealed) then
        fail("shape", entry.id, "marker " .. tostring(marker.id) .. " needs a when or a display")
      end
      if readable and (type(marker.when) ~= "table" or #marker.when == 0) then
        fail("shape", entry.id, "marker " .. tostring(marker.id) .. " has no readable condition")
      end
      if sealed then
        local display = marker.display
        if type(display) ~= "table" or not DISPLAYS[display.kind] then
          fail("display", entry.id, "marker " .. tostring(marker.id) .. " names unsupported display "
            .. tostring(type(display) == "table" and display.kind or nil))
        elseif display.kind == "sealed-count-bands" then
          -- render-shelf.md V16/V17. cap authors a piecewise function over the SEALED aura
          -- application count and hands it to the client, which evaluates it and calls SetText.
          -- Nothing here is ever read back, so every check is about the AUTHORED table.
          --
          -- ⚠ This replaced `player-aura-stacks` and its `min = 2` guard on 2026-08-22. That
          -- guard was never a platform limit: `applications > 1` is Blizzard's behaviour when no
          -- formatter is passed, and passing one replaces it outright `[client 2026-08-21]`.
          if not abilities[display.ability] then
            fail("subject", entry.id, "marker " .. tostring(marker.id) .. " names undeclared ability "
              .. tostring(display.ability))
          end
          local bands = display.bands
          if type(bands) ~= "table" or #bands == 0 then
            fail("display", entry.id, "sealed-count-bands needs a bands list")
          else
            local floor
            for i, band in ipairs(bands) do
              if type(band) ~= "table" then
                fail("display", entry.id, "band " .. i .. " is not a table")
              else
                if type(band.threshold) ~= "number" or band.threshold < 0
                  or band.threshold % 1 ~= 0 then
                  fail("display", entry.id, "band " .. i .. " needs a non-negative whole threshold")
                elseif floor and band.threshold <= floor then
                  -- Monotone, because the client picks the HIGHEST threshold a value reaches: an
                  -- out-of-order or repeated breakpoint makes one band unreachable and the
                  -- authored table stops describing what draws.
                  fail("display", entry.id, "bands must rise: threshold " .. band.threshold
                    .. " does not exceed " .. floor)
                else
                  floor = band.threshold
                end
                -- ⚠ A BAND NAMES WHAT IT MEANS, NEVER A FORMAT STRING. The client's breakpoint
                -- takes a `format`, but a format carrying a texture escape is a pixel decision,
                -- and pixels are render-shelf.md's. `Channel.CountRules` builds the string from
                -- `ns.Style.count`; a catalog that wrote one directly would put the style in the
                -- gameplay file where nothing regenerates it.
                if not COUNT_DRAWS[band.draw] then
                  fail("display", entry.id, "band " .. i .. " names unsupported draw "
                    .. tostring(band.draw))
                end
                if band.polarity ~= nil and band.polarity ~= "positive"
                  and band.polarity ~= "negative" then
                  fail("display", entry.id, "band " .. i .. " polarity must be positive or negative")
                end
                if band.hatch ~= nil and type(band.hatch) ~= "boolean" then
                  fail("display", entry.id, "band " .. i .. " hatch must be boolean")
                end
              end
            end
            -- The lowest band is the RESTING state and every value below the next threshold
            -- lands in it. Without one starting at zero the client has no rule for a low count
            -- and falls back to its own default, which is the behaviour this kind replaced.
            if type(bands[1]) == "table" and bands[1].threshold ~= 0 then
              fail("display", entry.id, "the first band must start at threshold 0")
            end
          end
        elseif display.kind == "sealed-count-bar" then
          -- render-shelf.md V18. The same sealed count as a FILL. `max` reaches the client as
          -- `maxApplications` and SetValue clamps into [0, max], so it is authored as the number
          -- past which nothing more can be said -- usually the aura's real cap, and on an aura
          -- with a higher one, the number that matters. The whole-bar red flip at that value is
          -- V18's own, unconditional: a catalog names no pixels and carries no switch for it.
          --
          -- (A `full = true` key lived here until 2026-08-26. It was inert -- `BarPlan` copied it
          -- to `plan.full` and nothing ever read it, while `Channel.Arm` armed the flip slot on
          -- the KIND alone -- and it had been cited in prose as though it fired the flip. A field
          -- that reads as a switch and switches nothing is worse than no field, so it is gone
          -- rather than wired: the shelf owns the flip.)
          if not abilities[display.ability] then
            fail("subject", entry.id, "marker " .. tostring(marker.id) .. " names undeclared ability "
              .. tostring(display.ability))
          end
          if type(display.max) ~= "number" or display.max <= 0 or display.max % 1 ~= 0 then
            fail("display", entry.id, "sealed-count-bar needs a positive whole max")
          end
        elseif display.kind == "sealed-pandemic" then
          -- render-shelf.md V19. The WINDOW carries no authored threshold — the client computes
          -- it per spell, which is exactly the property that makes it good. The optional
          -- `outside_s` is the pair's other state (the gold do-not-refresh hatch) and that one
          -- IS the catalog's number, drawn off the aura's remaining seconds.
          if not abilities[display.ability] then
            fail("subject", entry.id, "marker " .. tostring(marker.id) .. " names undeclared ability "
              .. tostring(display.ability))
          end
          if display.outside_s ~= nil
            and (type(display.outside_s) ~= "number" or display.outside_s <= 0) then
            fail("display", entry.id, "sealed-pandemic outside_s must be a positive number of seconds")
          end
        elseif display.kind == "sealed-power-percent" then
          -- The break point is NEVER authored as a percentage: the percentage depends on the
          -- player's max power, which only the client can read. It is authored either as a
          -- GENERATION amount (break at `(max - generation)/max` — "one more press overflows")
          -- or as an absolute resource THRESHOLD lifted off a priority condition (break at
          -- `threshold/max`). Exactly one, because two would be two break points.
          if type(display.power) ~= "string" then
            fail("display", entry.id, "sealed-power-percent needs a power type name")
          end
          local generation = type(display.generation) == "number" and display.generation or nil
          local threshold = type(display.threshold) == "number" and display.threshold or nil
          if (generation == nil) == (threshold == nil) then
            fail("display", entry.id,
              "sealed-power-percent needs exactly one of generation or threshold")
          elseif (generation or threshold) <= 0 then
            fail("display", entry.id,
              "sealed-power-percent needs a positive generation or threshold")
          end
          -- Unlike a readable marker, a graded one has no verdict to report: the cue IS the
          -- whole of it, so a graded display without one would arm and draw nothing.
          if marker.cue == nil then
            fail("cue", entry.id, "marker " .. tostring(marker.id) .. " is a graded display with no cue")
          end
        elseif display.kind == "sealed-cooldown-range" then
          if not abilities[display.ability] then
            fail("subject", entry.id, "marker " .. tostring(marker.id) .. " names undeclared ability "
              .. tostring(display.ability))
          end
          -- `within` = "ends inside this many seconds"; `beyond` = "has at least this long
          -- left". One alone is a one-sided hold; BOTH is the two-sided band (hold while
          -- remaining is inside (beyond, within) — catalog.md Defeats item 1, closed
          -- 2026-08-24), which demands beyond < within because the reversed pair is an empty
          -- band that would arm and never draw.
          local within = type(display.within) == "number" and display.within or nil
          local beyond = type(display.beyond) == "number" and display.beyond or nil
          if within == nil and beyond == nil then
            fail("display", entry.id,
              "sealed-cooldown-range needs within, beyond, or both (the two-sided band)")
          elseif (within or beyond) <= 0 or (beyond or 1) <= 0 then
            fail("display", entry.id,
              "sealed-cooldown-range needs a positive window in seconds")
          elseif within and beyond and beyond >= within then
            fail("display", entry.id,
              "two-sided sealed-cooldown-range needs beyond < within — the reversed pair is "
              .. "an empty band that arms and never draws")
          end
          if marker.cue == nil then
            fail("cue", entry.id, "marker " .. tostring(marker.id) .. " is a graded display with no cue")
          end
        elseif display.kind == "sealed-proc-bar" then
          -- V20: the proc's remaining lifetime as a bar above the charge bar. The subject must
          -- be a declared ability (normally an aura-family one); it carries no cue — the fill
          -- is the whole statement — and no numbers of its own, so there is nothing else to
          -- check.
          if not abilities[display.ability] then
            fail("subject", entry.id, "marker " .. tostring(marker.id) .. " names undeclared ability "
              .. tostring(display.ability))
          end
        end
      end
    end
  end

  local usesResource = false
  eachCondition(cat, function(entry, term, where)
    local name = type(term) == "table" and term[1] or nil
    local spec = name and PREDICATES[name]
    if not spec then
      fail("predicate", entry.id, where .. " names unsupported predicate " .. tostring(name))
      return
    end
    if #term ~= spec.arity + 1 then
      fail("predicate", entry.id, ("%s %s takes %d argument(s)"):format(where, name, spec.arity))
      return
    end
    if spec.subject and not abilities[term[2]] then
      fail("subject", entry.id, where .. " names undeclared ability " .. tostring(term[2]))
    end
    if spec.talent and not talents[term[2]] then
      fail("subject", entry.id, where .. " names undeclared talent " .. tostring(term[2]))
    end
    if name == "identity" and term[3] ~= "base" and term[3] ~= "transformed" then
      fail("predicate", entry.id, "identity accepts only base or transformed")
    end
    if name == "resource" then
      usesResource = true
      if term[2] ~= "<=" and term[2] ~= ">=" then
        fail("predicate", entry.id, "resource accepts only <= or >=")
      end
      if type(term[3]) ~= "number" then fail("predicate", entry.id, "resource threshold must be numeric") end
    end
  end)

  if usesResource and type(cat.power) ~= "string" then
    fail("shape", nil, "resource condition needs a power type")
  end
  if cat.bar ~= nil and (type(cat.bar) ~= "string" or not entries[cat.bar]) then
    fail("shape", tostring(cat.bar), "bar must name one enhanced entry")
  end
  return found
end

local function findRow(ability, rows)
  local family = ability.family or "spells"
  for _, spell in ipairs({ ability.spell, unpack(ability.alt or {}) }) do
    for _, row in ipairs(rows or {}) do
      if row.family == family and row.spellIDs and row.spellIDs[spell] then return row end
    end
  end
end

function Catalog.Resolve(cat, rows)
  local out = {
    abilities = {}, entries = {}, byAbility = {}, byEntry = {}, declared = {}, dropped = {},
  }
  local needsRow = {}
  for _, entry in ipairs(cat.entries or {}) do needsRow[entry.ability] = true end
  eachCondition(cat, function(_, term)
    local spec = PREDICATES[term[1]]
    if spec and spec.subject then needsRow[term[2]] = true end
  end)
  for _, ability in ipairs(cat.abilities or {}) do
    out.declared[ability.id] = ability
    local row = findRow(ability, rows)
    if row then
      local bound = { ability = ability, row = row }
      out.abilities[#out.abilities + 1] = bound
      out.byAbility[ability.id] = row
    elseif needsRow[ability.id] then
      out.dropped[#out.dropped + 1] = { id = ability.id, spell = ability.spell, why = "no CDM row on this build" }
    end
  end
  for _, entry in ipairs(cat.entries or {}) do
    local row = out.byAbility[entry.ability]
    if row then
      -- The AUTHORED flag, never a client maxCharges read: the artifact's roster column and
      -- the live border must not be able to disagree about which rows are purple.
      local charged = (out.declared[entry.ability] or {}).charged and true or false
      out.entries[#out.entries + 1] = { entry = entry, row = row, charged = charged }
      out.byEntry[entry.id] = row
    end
  end
  return out
end

--- The authored priority against the client's own row order, or nil when they agree.
---
--- A catalog's entry order IS its priority, and the whole reading model assumes the Cooldown
--- Manager lays those rows out in that order. Nothing guarantees it — the layout is Blizzard's,
--- filtered by what the player enabled — and if it is wrong the model fails everywhere at once
--- rather than degrading per ability. This names the first pair that is out of order. It is a
--- diagnostic: it never says what to press.
function Catalog.OrderCheck(cat, resolved, rows)
  local at = {}
  for i, row in ipairs(rows or {}) do at[row] = i end
  local previous, previousID
  for _, entry in ipairs((cat or {}).entries or {}) do
    local position = at[(resolved or {}).byEntry and resolved.byEntry[entry.id]]
    if position then
      if previous and position < previous then
        return { after = entry.id, before = previousID }
      end
      previous, previousID = position, entry.id
    end
  end
end

function Catalog.CheckBound(cat, rows)
  local resolved = Catalog.Resolve(cat, rows)
  local found = {}
  for _, entry in ipairs(cat.entries or {}) do
    if not resolved.byEntry[entry.id] then
      found[#found + 1] = { check = "binding", entry = entry.id, detail = "enhanced ability has no CDM row" }
    end
  end
  return found, resolved
end

function Catalog.Reads(cat)
  local out = { byAbility = {}, resource = false, talent = {}, aoe = false }
  eachCondition(cat, function(_, term)
    local name = term[1]
    if name == "resource" then
      out.resource = true
    elseif name == "aoe" then
      out.aoe = true
    elseif name == "talent" then
      out.talent[term[2]] = true
    elseif PREDICATES[name] and PREDICATES[name].subject then
      out.byAbility[term[2]] = out.byAbility[term[2]] or {}
      out.byAbility[term[2]][name] = true
    end
  end)
  return out
end
