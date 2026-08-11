-- Engine guarantee: catalogs admit only the readable forms the live renderer supports.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("engine / catalog", function()
  local ns, cat
  before_each(function() ns = H.fresh(); cat = H.catalog(ns) end)

  it("accepts the small pilot and declares only two enhanced entries", function()
    assert.same({}, ns.Catalog.Check(cat))
    assert.same({ "tyrant", "demonbolt" }, { cat.entries[1].id, cat.entries[2].id })
    assert.is_nil(cat.silences)
  end)

  it("rejects unused or sealed vocabulary as a Lua predicate", function()
    for _, name in ipairs({ "elapsed", "casts", "cooldownRemaining", "stacks", "talent" }) do
      local broken = H.copy(cat)
      broken.entries[1].when = { { name, "tyrant" } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).predicate, name)
    end
  end)

  it("rejects undeclared subjects and malformed resource comparisons", function()
    local broken = H.copy(cat)
    broken.entries[1].when = { { "ready", "missing" } }
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
    broken = H.copy(cat)
    broken.entries[1].when = { { "resource", "==", 3 } }
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).predicate)
  end)

  it("binds dependencies without turning them into enhanced entries", function()
    local found, resolved = ns.Catalog.CheckBound(cat, H.rows())
    assert.same({}, found)
    assert.equal(4, #resolved.abilities)
    assert.equal(2, #resolved.entries)
    assert.is_not_nil(resolved.byAbility.dreadstalkers)
    assert.is_nil(resolved.byEntry.dreadstalkers)
  end)

  it("fails an enhanced ability visibly when it has no row", function()
    local rows = H.rows()
    for _, row in ipairs(rows) do row.spellIDs[265187] = nil end
    local found, resolved = ns.Catalog.CheckBound(cat, rows)
    assert.is_truthy(H.checks(found).binding)
    assert.is_nil(resolved.byEntry.tyrant)
  end)

  it("resolves a declared transform alternative deterministically", function()
    local rows = H.rows()
    for _, row in ipairs(rows) do
      if row.spellIDs[1276452] then
        row.spellIDs = { [1276467] = true }
        row.primary = 1276467
      end
    end
    local resolved = ns.Catalog.Resolve(cat, rows)
    assert.equal(1276467, resolved.byAbility.grimoire.primary)
  end)
end)

