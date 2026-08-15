-- Catalog.lua — the small authored contract between a spec and cap's renderer.
-- Pure: this validates plain data and resolves it against Bind rows; it reads no game API.
local ADDON, ns = ...

local Catalog = {}
ns.Catalog = Catalog

local registry = {}
local TIERS = { COOLDOWN = 3, ROTATION = 2, FALLBACK = 1 }
Catalog.TIERS = TIERS
local PREDICATES = {
  ready = { arity = 1, subject = true },
  proc = { arity = 1, subject = true },
  identity = { arity = 2, subject = true },
  capped = { arity = 1, subject = true },
  affordable = { arity = 1, subject = true },
  resource = { arity = 2 },
}
Catalog.PREDICATES = PREDICATES
local DISPLAYS = { ["player-aura-stacks"] = true, ["sealed-power-percent"] = true }
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
      local readable = marker.when ~= nil
      local sealed = marker.display ~= nil
      if readable == sealed then
        fail("shape", entry.id, "marker " .. tostring(marker.id) .. " needs exactly one of when or display")
      elseif readable and (type(marker.when) ~= "table" or #marker.when == 0) then
        fail("shape", entry.id, "marker " .. tostring(marker.id) .. " has no readable condition")
      elseif sealed then
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
          -- The break point is authored as a GENERATION amount, never as a percentage: the
          -- percentage depends on the player's max power, which only the client can read.
          if type(display.power) ~= "string" then
            fail("display", entry.id, "sealed-power-percent needs a power type name")
          end
          if type(display.generation) ~= "number" or display.generation <= 0 then
            fail("display", entry.id, "sealed-power-percent needs a positive generation amount")
          end
          -- Unlike a readable marker, a sealed one has no verdict to report: the cue IS the
          -- whole of it, so a sealed power display without one would arm and draw nothing.
          if marker.cue == nil then
            fail("cue", entry.id, "marker " .. tostring(marker.id) .. " is a sealed power display with no cue")
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
  local out = { byAbility = {}, resource = false }
  eachCondition(cat, function(_, term)
    local name = term[1]
    if name == "resource" then
      out.resource = true
    elseif PREDICATES[name] and PREDICATES[name].subject then
      out.byAbility[term[2]] = out.byAbility[term[2]] or {}
      out.byAbility[term[2]][name] = true
    end
  end)
  return out
end
