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
  resource = { arity = 2 },
}
Catalog.PREDICATES = PREDICATES
local DISPLAYS = { ["player-aura-stacks"] = true }
Catalog.DISPLAYS = DISPLAYS

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
    local markerIDs = {}
    for _, marker in ipairs(entry.markers or {}) do
      if type(marker.id) ~= "string" or marker.id == "" then
        fail("shape", entry.id, "marker has no id")
      elseif markerIDs[marker.id] then
        fail("shape", entry.id, "duplicate marker id " .. marker.id)
      else
        markerIDs[marker.id] = true
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
      out.entries[#out.entries + 1] = { entry = entry, row = row }
      out.byEntry[entry.id] = row
    end
  end
  return out
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
