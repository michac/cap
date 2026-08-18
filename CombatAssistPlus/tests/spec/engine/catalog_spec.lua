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
    for _, name in ipairs({ "elapsed", "casts", "cooldownRemaining", "stacks" }) do
      local broken = H.copy(cat)
      broken.entries[1].bands[1].when = { { name, "tyrant" } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).predicate, name)
    end
  end)

  it("keeps talent and ability subjects in separate namespaces", function()
    -- `talent` became a real predicate on 2026-08-17. Its argument is a TALENT id, so naming an
    -- ability there must still fail — a talent has no CDM row and resolving it as one would
    -- silently demand a row that can never bind.
    local broken = H.copy(cat)
    broken.entries[1].bands[1].when = { { "talent", "tyrant" } }
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)

    -- …and the reverse: an ability predicate may not name a talent.
    local havoc = H.copy(H.catalogBySpec(ns, 577))
    havoc.entries[1].bands[1].when = { { "ready", "a_fire_inside" } }
    assert.is_truthy(H.checks(ns.Catalog.Check(havoc)).subject)
  end)

  it("takes no subject for aoe, and reports arity when one is given", function()
    local broken = H.copy(cat)
    broken.entries[1].bands[1].when = { { "aoe" } }
    assert.same({}, ns.Catalog.Check(broken))

    broken = H.copy(cat)
    broken.entries[1].bands[1].when = { { "aoe", "tyrant" } }
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).predicate)
  end)

  it("requires a declared talent to carry numeric node and entry ids", function()
    local havoc = H.copy(H.catalogBySpec(ns, 577))
    havoc.talents[1].node = nil
    assert.is_truthy(H.checks(ns.Catalog.Check(havoc)).shape)

    havoc = H.copy(H.catalogBySpec(ns, 577))
    havoc.talents[1].entry = "117741"
    assert.is_truthy(H.checks(ns.Catalog.Check(havoc)).shape)
  end)

  it("routes talent and aoe terms to their own read buckets, not to byAbility", function()
    local reads = ns.Catalog.Reads(H.catalogBySpec(ns, 577))
    assert.is_true(reads.aoe)
    assert.is_true(reads.talent.a_fire_inside)
    assert.is_nil(reads.byAbility.a_fire_inside)
    -- Demonology names neither, so it must ask for neither.
    local quiet = ns.Catalog.Reads(cat)
    assert.is_false(quiet.aoe)
    assert.same({}, quiet.talent)
  end)

  it("accepts only discrete bands in descending priority order", function()
    local broken = H.copy(cat)
    broken.entries[1].bands[1].tier = "MEDIUM"
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).tier)

    broken = H.copy(cat)
    broken.entries[2].bands = {
      { tier = "FALLBACK", when = { { "proc", "demonbolt" } } },
      { tier = "ROTATION", when = { { "proc", "demonbolt" } } },
    }
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).tier)
  end)

  it("allows several alternative bands in the same tier", function()
    local expanded = H.copy(cat)
    expanded.entries[1].bands[#expanded.entries[1].bands + 1] = {
      tier = "ROTATION", when = { { "ready", "tyrant" } },
    }
    assert.same({}, ns.Catalog.Check(expanded))
  end)

  it("rejects undeclared subjects and malformed resource comparisons", function()
    local broken = H.copy(cat)
    broken.entries[1].bands[1].when = { { "ready", "missing" } }
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
    broken = H.copy(cat)
    broken.entries[1].bands[1].when = { { "resource", "==", 3 } }
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

  it("reports when the client lays the roster out against the authored priority", function()
    local rows = H.rows()
    local resolved = ns.Catalog.Resolve(cat, rows)
    assert.is_nil(ns.Catalog.OrderCheck(cat, resolved, rows))

    -- Same rows, reversed: the layout now disagrees with the catalog's own order.
    local flipped = {}
    for i = #rows, 1, -1 do flipped[#flipped + 1] = rows[i] end
    local out = ns.Catalog.OrderCheck(cat, ns.Catalog.Resolve(cat, flipped), flipped)
    assert.equal("tyrant", out.before)
    assert.equal("demonbolt", out.after)
  end)

  it("admits a readable marker, a sealed one, or a sealed one carrying readable gates", function()
    local destruction = H.catalogBySpec(ns, 267)
    assert.same({}, ns.Catalog.Check(destruction))

    -- A `when` BESIDE a `display` is the gate form: one secret, many readable gates. It was a
    -- shape error until 2026-08-17, which is what made a talent-gated band inexpressible.
    local gated = H.copy(destruction)
    gated.entries[1].markers[1].when = { { "ready", "conflagrate" } }
    assert.same({}, ns.Catalog.Check(gated))

    local neither = H.copy(destruction)
    neither.entries[1].markers[1].display = nil
    assert.is_truthy(H.checks(ns.Catalog.Check(neither)).shape)

    -- A gate still has to be a real condition; an empty one is a typo, not a permanent yes.
    local empty = H.copy(destruction)
    empty.entries[1].markers[1].when = {}
    assert.is_truthy(H.checks(ns.Catalog.Check(empty)).shape)
  end)

  it("takes exactly one of within or beyond on a sealed cooldown range", function()
    local havoc = H.catalogBySpec(ns, 577)
    local function band(target, id)
      for _, e in ipairs(target.entries) do
        if e.id == "the_hunt" then
          for _, m in ipairs(e.markers) do if m.id == id then return m end end
        end
      end
    end
    -- The shipped pair is one of each sense, which is the point of the pair.
    assert.equal(10, band(havoc, "hunt_awaits_eye_beam").display.beyond)
    assert.equal(15, band(havoc, "hunt_awaits_meta").display.within)

    local broken = H.copy(havoc)
    band(broken, "hunt_awaits_meta").display.beyond = 10
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    broken = H.copy(havoc)
    band(broken, "hunt_awaits_meta").display.within = nil
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    broken = H.copy(havoc)
    band(broken, "hunt_awaits_eye_beam").display.beyond = 0
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)
  end)

  it("rejects unsupported displays and undeclared sealed dependencies", function()
    local broken = H.copy(H.catalogBySpec(ns, 267))
    broken.entries[1].markers[1].display.kind = "target-aura-stacks"
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    broken = H.copy(H.catalogBySpec(ns, 267))
    broken.entries[1].markers[1].display.ability = "missing"
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
  end)

  it("rejects a malformed sealed power display", function()
    local havoc = H.catalogBySpec(ns, 577)
    local function generator(target)
      for _, entry in ipairs(target.entries) do
        if entry.id == "felblade" then return entry.markers[1] end
      end
    end

    -- Exactly one of generation / threshold authors the break. Neither is not a break point,
    -- and both is two of them.
    local broken = H.copy(havoc)
    generator(broken).display.threshold = nil
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    broken = H.copy(havoc)
    generator(broken).display.generation = 15
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    broken = H.copy(havoc)
    generator(broken).display.threshold = 0
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    broken = H.copy(havoc)
    generator(broken).display.power = nil
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    -- A sealed power display IS its cue; without one it would arm and draw nothing.
    broken = H.copy(havoc)
    generator(broken).cue = nil
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).cue)
  end)

  it("binds a sealed dependency to the direct AuraContainer sink only", function()
    local destruction = H.catalogBySpec(ns, 267)
    local resolved = ns.Catalog.Resolve(destruction, H.destructionRows())
    local marker = destruction.entries[1].markers[1]
    local plan = ns.Channel.Plan(marker, resolved.declared)
    assert.equal(117828, plan.spell)
    assert.equal("player", plan.unit)
    assert.equal("SetApplicationCount", plan.sink)
    assert.is_nil(resolved.byAbility.backdraft)
    assert.is_not_nil(resolved.declared.backdraft)
    assert.same({}, resolved.dropped)
  end)
end)
