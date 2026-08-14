-- mock_ns.lua — the busted harness.
--
-- Deliberately thin. The modules under test are PURE, so there is no client to fake:
-- what this provides is the `local ADDON, ns = ...` vararg shim and a fresh namespace
-- per spec file. Anything that would need a CreateFrame stub does not belong here —
-- it belongs on the impure side, which is tested in the client and nowhere else.
local H = {}

local ROOT = "CombatAssistPlus/"

--- Load a module into a namespace, through the addon vararg shim the game uses.
function H.load(ns, relPath)
  local chunk = assert(loadfile(ROOT .. relPath))
  return chunk("CombatAssistPlus", ns)
end

--- A namespace with the pure core loaded and the Demonology catalog registered.
function H.fresh()
  local ns = {}
  H.load(ns, "Catalog.lua")
  H.load(ns, "Signal.lua")
  H.load(ns, "Track.lua")
  H.load(ns, "Style.lua")
  H.load(ns, "Treatment.lua")
  H.load(ns, "Paint.lua")
  H.load(ns, "Channel.lua")
  H.load(ns, "Catalogs/Demonology.lua")
  H.load(ns, "Catalogs/Destruction.lua")
  -- Last, so `H.catalog(ns)` — registry entry 1 — stays Demonology for every existing spec.
  H.load(ns, "Catalogs/Havoc.lua")
  return ns
end

--- The pure core plus `Bars`, whose `Plan` is pure. Bars subscribes to the verdicts at load,
--- so the harness supplies that one seam — OUR module, never a client API.
function H.withBars(ns)
  ns.Sense = { OnVerdicts = function() end }
  H.load(ns, "Bars.lua")
  return ns.Bars
end

--- The 21-row Demonology set recorded by cap v0.2.0 in the live client.
function H.rows()
  return assert(loadfile(ROOT .. "tests/fixtures/demonology-rows.lua"))()
end

function H.catalog(ns)
  return ns.Catalog.All()[1]
end

function H.catalogBySpec(ns, spec)
  for _, cat in ipairs(ns.Catalog.All()) do if cat.spec == spec then return cat end end
end

function H.destructionRows()
  return assert(loadfile(ROOT .. "tests/fixtures/destruction-rows.lua"))()
end

--- A Track bound to the client-authored row set — the same call Sense makes.
function H.track(ns)
  local cat = H.catalog(ns)
  local rows = H.rows()
  local _, resolved = ns.Catalog.CheckBound(cat, rows)
  local t = ns.Track.New()
  t:Bind(ns.Track.Binding(resolved, ns.Catalog.Reads(cat)))
  return t, cat, resolved
end

--- The cooldownID an entry bound to, so a test can raise the edge the client would.
function H.cid(resolved, abilityID)
  return assert(resolved.byAbility[abilityID], abilityID .. " did not bind").cooldownID
end

--- A deep-ish copy, so a test that breaks a catalog to prove a check fires cannot
--- leak the damage into the next test.
function H.copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = H.copy(val) end
  return out
end

--- Findings reduced to a set of check names, which is what an assertion cares about.
function H.checks(found)
  local out = {}
  for _, f in ipairs(found) do out[f.check] = (out[f.check] or 0) + 1 end
  return out
end

--- A world in which every gate refuses. This is the harness's most important helper:
--- a fixture that hands the code a value cannot reproduce the state the client
--- actually produces under restriction, and that has already cost this workspace a
--- hundred green tests elsewhere.
function H.blindWorld()
  local U = "unknown"
  local blind = setmetatable({}, { __index = function() return U end })
  return {
    ready = blind, proc = blind, identity = blind, capped = blind, affordable = blind,
    resource = U, resourceMax = U,
  }
end

--- A world where everything reads, so a test can vary one gate at a time.
function H.world(over)
  local yes = setmetatable({}, { __index = function() return true end })
  local no = setmetatable({}, { __index = function() return false end })
  local w = {
    ready = yes, proc = no, capped = no, affordable = yes,
    identity = setmetatable({}, { __index = function() return "base" end }),
    resource = 0, resourceMax = 5,
  }
  for k, v in pairs(over or {}) do w[k] = v end
  return w
end

--- A per-key table with a default, for overriding one entry's gate.
function H.map(default, over)
  local t = setmetatable({}, { __index = function() return default end })
  for k, v in pairs(over or {}) do rawset(t, k, v) end
  return t
end

return H
