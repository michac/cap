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
      broken.entries[1].scan_when = { { { name, "tyrant" } } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).predicate, name)
    end
  end)

  it("keeps talent and ability subjects in separate namespaces", function()
    -- `talent` became a real predicate on 2026-08-17. Its argument is a TALENT id, so naming an
    -- ability there must still fail — a talent has no CDM row and resolving it as one would
    -- silently demand a row that can never bind.
    local broken = H.copy(cat)
    broken.entries[1].scan_when = { { { "talent", "tyrant" } } }
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)

    -- …and the reverse: an ability predicate may not name a talent.
    local havoc = H.copy(H.catalogBySpec(ns, 577))
    havoc.entries[1].scan_when = { { { "ready", "a_fire_inside" } } }
    assert.is_truthy(H.checks(ns.Catalog.Check(havoc)).subject)
  end)

  it("takes no subject for aoe, and reports arity when one is given", function()
    local broken = H.copy(cat)
    broken.entries[1].scan_when = { { { "aoe" } } }
    assert.same({}, ns.Catalog.Check(broken))

    broken = H.copy(cat)
    broken.entries[1].scan_when = { { { "aoe", "tyrant" } } }
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

  it("rejects the retired tier bands by name", function()
    -- A stale catalog must fail loudly rather than silently fall back to default membership.
    local broken = H.copy(cat)
    broken.entries[1].bands = { { tier = "ROTATION", when = { { "ready", "tyrant" } } } }
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).shape)
  end)

  it("accepts a well-shaped scan_when and rejects malformed ones", function()
    local expanded = H.copy(cat)
    expanded.entries[1].scan_when = {
      { { "ready", "tyrant" } },
      { { "identity", "grimoire", "transformed" } },
    }
    assert.same({}, ns.Catalog.Check(expanded))

    local broken = H.copy(cat)
    broken.entries[1].scan_when = {}
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).shape)

    broken = H.copy(cat)
    broken.entries[1].scan_when = { {} }
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).shape)

    broken = H.copy(cat)
    broken.entries[1].scan_when = "ready"
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).shape)
  end)

  it("rejects undeclared subjects and malformed resource comparisons", function()
    local broken = H.copy(cat)
    broken.entries[1].scan_when = { { { "ready", "missing" } } }
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
    broken = H.copy(cat)
    broken.entries[1].scan_when = { { { "resource", "==", 3 } } }
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

  it("takes within, beyond, or the ordered pair on a sealed cooldown range", function()
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

    -- BOTH is the two-sided band (Demonology's dogs, 2026-08-24) — legal when beyond < within.
    local paired = H.copy(havoc)
    band(paired, "hunt_awaits_meta").display.beyond = 10
    assert.is_falsy(H.checks(ns.Catalog.Check(paired)).display)

    -- The reversed pair is an empty band that would arm and never draw — refused.
    local broken = H.copy(havoc)
    band(broken, "hunt_awaits_meta").display.beyond = 20
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    broken = H.copy(havoc)
    band(broken, "hunt_awaits_meta").display.within = nil
    band(broken, "hunt_awaits_meta").display.beyond = nil
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

  -- render-shelf.md V16/V17. The `min = 2` guard this replaced was never a platform limit --
  -- `applications > 1` is what the client does when NO formatter is passed -- so what is checked
  -- now is the authored band table, and nothing about it is ever read back.
  it("validates a banded count as a rising table of meanings", function()
    local destruction = H.catalogBySpec(ns, 267)
    assert.same({}, ns.Catalog.Check(destruction))

    local function bands(target)
      return target.entries[1].markers[1].display.bands
    end

    -- ⚠ The bands must RISE. The client picks the highest threshold a value reaches, so a
    -- repeated or out-of-order breakpoint makes one band unreachable and the authored table
    -- stops describing what draws.
    local broken = H.copy(destruction)
    bands(broken)[2].threshold = 0
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    broken = H.copy(destruction)
    bands(broken)[1].threshold = 4
    bands(broken)[2].threshold = 2
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    -- The lowest band is the RESTING state and must start at zero; without one the client has
    -- no rule for a low count and falls back to the default this kind exists to replace.
    broken = H.copy(destruction)
    bands(broken)[1].threshold = 1
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    -- A band names WHAT IT MEANS, never a format string: the format is a pixel decision and
    -- pixels are the shelf's, built by `Channel.CountRules` from `ns.Style.count`.
    broken = H.copy(destruction)
    bands(broken)[2].draw = "|A:pawn:15:15|a"
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    broken = H.copy(destruction)
    bands(broken)[2].polarity = "gold"
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    broken = H.copy(destruction)
    bands(broken)[2].threshold = 2.5
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    broken = H.copy(destruction)
    broken.entries[1].markers[1].display.bands = {}
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)
  end)

  it("validates the sealed radial and the pandemic window against their one field each", function()
    local demo = H.catalogBySpec(ns, 266)
    assert.same({}, ns.Catalog.Check(demo))

    local function marker(target, id)
      for _, e in ipairs(target.entries) do
        for _, m in ipairs(e.markers or {}) do if m.id == id then return m end end
      end
    end
    assert.equal(4, marker(demo, "db_core_charge").display.max)
    assert.equal("doom", marker(demo, "db_doom_window").display.ability)

    -- `max` is the number past which nothing more can be said -- for Demonic Core that IS the
    -- aura's real cap ("Maximum 4 stacks") -- and the clamp is what turns "or more" into "full",
    -- so a non-positive one has no fired state at all.
    local broken = H.copy(demo)
    marker(broken, "db_core_charge").display.max = 0
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    broken = H.copy(demo)
    marker(broken, "db_core_charge").display.max = nil
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)

    -- The pandemic window has NO threshold to get wrong -- the client computes the window
    -- itself, per spell -- so its subject is the whole of what there is to check.
    broken = H.copy(demo)
    marker(broken, "db_doom_window").display.ability = "missing"
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
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

  -- ⚠ Until 2026-08-23 NOTHING iterated the registry: a malformed catalog could be registered,
  -- ship, and never fail a test, because every existing check ran against a fixture or against
  -- one hand-named roster. `Check` is the schema, so running it over what is actually registered
  -- is the gate — and it covers the next catalog the day it is added, not the day someone
  -- remembers to write it a product spec.
  -- render-shelf.md V22 · a badge whose face is a NUMBER cap authored. The whole licence is that
  -- the marker's own `when` fixes the value, so the checks below are about keeping a numeral
  -- attached to something that draws and to something that established it.
  it("accepts a numeral badge only on a readable marker that declares a cue", function()
    local function withBadge(badge, mutate)
      local broken = H.copy(cat)
      local m = broken.entries[1].markers[1]
      m.badge = badge
      if mutate then mutate(m) end
      return H.checks(ns.Catalog.Check(broken))
    end
    -- The shipped shape passes: a readable marker, a cue, a non-negative whole value.
    local ok = H.copy(cat)
    ok.entries[1].markers[1].badge = { kind = "numeral", value = 0 }
    ok.entries[1].markers[1].cue = ok.entries[1].markers[1].cue or "blocked"
    assert.same({}, ns.Catalog.Check(ok))

    -- Closed vocabulary, one kind.
    assert.is_truthy(withBadge({ kind = "glyph", value = 0 }).badge)
    assert.is_truthy(withBadge("numeral").badge)
    -- A value that is not a non-negative whole number is not a count of anything.
    assert.is_truthy(withBadge({ kind = "numeral", value = -1 }).badge)
    assert.is_truthy(withBadge({ kind = "numeral", value = 1.5 }).badge)
    assert.is_truthy(withBadge({ kind = "numeral" }).badge)
    -- No cue: `Overlay.paint` looks a numeral up BY CUE KEY, so one without a cue builds and
    -- never draws.
    assert.is_truthy(withBadge({ kind = "numeral", value = 0 },
      function(m) m.cue = nil end).badge)
    -- ⚠ AND THE SILENT ONE. `Signal.markersOf` routes a marker carrying a `display` to
    -- `verdict.gates` and it never contributes a cue — so a numeral on a display marker would
    -- pass every other gate, arm nothing, and be invisible for the life of the session.
    assert.is_truthy(withBadge({ kind = "numeral", value = 0 }, function(m)
      m.display = { kind = "sealed-count-bar", ability = "demonic_core", max = 4 }
    end).badge)
  end)

  it("validates every catalog the addon actually registers", function()
    local all = ns.Catalog.All()
    assert.is_true(#all > 1, "the registry did not load")
    for _, registered in ipairs(all) do
      assert.same({}, ns.Catalog.Check(registered),
        ("catalog spec %s is malformed"):format(tostring(registered.spec)))
    end
  end)
end)
