-- check_catalog.lua — run `Catalog.Check` over one generated catalog, outside the client.
--
-- The parity gate behind `wowkb.capart check`: a catalog is GENERATED from its catalog.json,
-- and the only thing that knows whether the result is shaped right is the validator that ships
-- beside it. Without this, schema drift between the generator and Catalog.lua stays invisible
-- until the addon loads in game.
--
-- Usage: lua CombatAssistPlus/tests/check_catalog.lua <CatalogName>
-- Exits 0 when the catalog validates, 1 with the findings when it does not.
local name = ...
if not name or name == "" then
  io.stderr:write("usage: check_catalog.lua <CatalogName>\n")
  os.exit(2)
end

local ROOT = "CombatAssistPlus/"
local ns = {}
local function load(rel)
  local chunk, err = loadfile(ROOT .. rel)
  if not chunk then
    io.stderr:write("cannot load " .. rel .. ": " .. tostring(err) .. "\n")
    os.exit(2)
  end
  return chunk("CombatAssistPlus", ns)
end

-- `Style.lua` first: `Catalog.Check` resolves every cue name against `ns.Style.cues`, so
-- without it the cue vocabulary is empty and every marker fails for the wrong reason.
load("Catalog.lua")
load("Style.lua")
load("Catalogs/" .. name .. ".lua")

local cat = ns.Catalog.All()[1]
if not cat then
  io.stderr:write("Catalogs/" .. name .. ".lua registered no catalog\n")
  os.exit(2)
end

local found = ns.Catalog.Check(cat)
if #found == 0 then os.exit(0) end

for _, f in ipairs(found) do
  io.stdout:write(("%s · %s: %s\n"):format(f.check, tostring(f.entry), f.detail))
end
os.exit(1)
