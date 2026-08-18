-- Catalog.lua — the small authored contract between a spec and cap's renderer.
-- Pure: this validates plain data and resolves it against Bind rows; it reads no game API.
local ADDON, ns = ...

local Catalog = {}
ns.Catalog = Catalog

local registry = {}
local TIERS = { COOLDOWN = 3, ROTATION = 2, FALLBACK = 1 }
Catalog.TIERS = TIERS
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
  aoe = { arity = 0 },
}
Catalog.PREDICATES = PREDICATES
local DISPLAYS = {
  ["player-aura-stacks"] = true,
  ["sealed-power-percent"] = true,
  ["sealed-cooldown-range"] = true,
}
Catalog.DISPLAYS = DISPLAYS

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

local function eachCondition(cat, fn)
  for _, entry in ipairs(cat.entries or {}) do
    for _, band in ipairs(entry.bands or {}) do
      for _, term in ipairs(band.when or {}) do fn(entry, term, "tier " .. tostring(band.tier)) end
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
    if type(entry.bands) ~= "table" or #entry.bands == 0 then
      fail("shape", entry.id, "entry has no readable tier bands")
    end
    local previous
    for _, band in ipairs(entry.bands or {}) do
      local rank = TIERS[band.tier]
      if not rank then
        fail("tier", entry.id, "band names unsupported tier " .. tostring(band.tier))
      elseif previous and rank > previous then
        fail("tier", entry.id, "bands must not rise in priority")
      end
      previous = rank or previous
      if type(band.when) ~= "table" or #band.when == 0 then
        fail("shape", entry.id, "tier " .. tostring(band.tier) .. " has no readable condition")
      end
    end
    local markerIDs, bySlot = {}, {}
    for _, marker in ipairs(entry.markers or {}) do
      if type(marker.id) ~= "string" or marker.id == "" then
        fail("shape", entry.id, "marker has no id")
      elseif markerIDs[marker.id] then
        fail("shape", entry.id, "duplicate marker id " .. marker.id)
      else
        markerIDs[marker.id] = true
      end
      -- `cue` stays OPTIONAL: a marker with none is evaluated and reported but draws nothing,
      -- which is what the two Warlock context markers still are.
      if marker.cue ~= nil then
        local cue = cues()[marker.cue]
        if not cue then
          fail("cue", entry.id, "marker " .. tostring(marker.id) .. " names undeclared cue "
            .. tostring(marker.cue))
        elseif bySlot[cue.slot] and bySlot[cue.slot] ~= marker.cue then
          -- One badge per slot. Two cues sharing one would draw a stack the player never sees.
          fail("cue", entry.id, ("cues %s and %s both want badge slot %s")
            :format(bySlot[cue.slot], marker.cue, tostring(cue.slot)))
        else
          bySlot[cue.slot] = marker.cue
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
        elseif display.kind == "player-aura-stacks" then
          if not abilities[display.ability] then
            fail("subject", entry.id, "marker " .. tostring(marker.id) .. " names undeclared ability "
              .. tostring(display.ability))
          end
          if display.min ~= 2 then
            fail("display", entry.id, "player-aura-stacks currently supports min = 2")
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
          -- left". Exactly one, because two would be two curves on one badge.
          local within = type(display.within) == "number" and display.within or nil
          local beyond = type(display.beyond) == "number" and display.beyond or nil
          if (within == nil) == (beyond == nil) then
            fail("display", entry.id,
              "sealed-cooldown-range needs exactly one of within or beyond")
          elseif (within or beyond) <= 0 then
            fail("display", entry.id,
              "sealed-cooldown-range needs a positive window in seconds")
          end
          if marker.cue == nil then
            fail("cue", entry.id, "marker " .. tostring(marker.id) .. " is a graded display with no cue")
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
