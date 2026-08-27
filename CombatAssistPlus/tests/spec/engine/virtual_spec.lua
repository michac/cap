-- Engine guarantee: V12's virtual row — an entry cap draws on its OWN frame because the
-- Cooldown Manager carries none for it.
--
-- ⚠ The unknown polarity is INVERTED against every other row in the model, and that is what
-- most of this file is about. On a CDM row an unknown readiness draws bare, because the icon is
-- there regardless and absence of a hatch asserts nothing. A virtual row exists only to say
-- "press this now", so bare IS the instruction and an unknown must draw HATCHED.
local H = require("CombatAssistPlus.tests.mock_ns")

--- The engine fixture plus two virtual entries, one of each kind.
---
--- ⚠ Their spell ids are deliberately absent from `demonology-rows.lua`. Having no CDM row is
--- the whole definition of a virtual entry, so a fixture whose virtual ability happened to bind
--- would test nothing. `gated` reads a condition about ANOTHER ability, which is the shape a
--- real one takes: the thing that grants access is rarely the button itself.
local function withVirtual(ns)
  local cat = H.copy(H.catalog(ns))
  cat.abilities[#cat.abilities + 1] = { id = "star", spell = 9000001 }
  cat.abilities[#cat.abilities + 1] = { id = "consume", spell = 9000002 }
  cat.entries[#cat.entries + 1] = {
    id = "star", ability = "star", virtual = "gated",
    scan_when = { { { "proc", "demonbolt" } } },
  }
  cat.entries[#cat.entries + 1] = { id = "consume", ability = "consume", virtual = "standing" }
  return cat
end

local function entry(cat, id)
  for _, e in ipairs(cat.entries) do if e.id == id then return e end end
end

describe("engine / virtual row", function()
  local ns, cat
  before_each(function() ns = H.fresh(); cat = withVirtual(ns) end)

  -- ---------------------------------------------------------------- the declaration

  it("accepts exactly the two declared kinds", function()
    assert.same({}, ns.Catalog.Check(cat))

    for _, bad in ipairs({ "sometimes", true, 1, "Gated" }) do
      local broken = withVirtual(ns)
      entry(broken, "star").virtual = bad
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).shape, tostring(bad))
    end
  end)

  it("refuses a scan_when on a standing row and demands one on a gated row", function()
    -- A standing row is the terminus of the elimination walk; a condition beside it would
    -- silently decide whether the terminus is there at all.
    local broken = withVirtual(ns)
    entry(broken, "consume").scan_when = { { { "ready", "tyrant" } } }
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).shape)

    -- ⚠ And the gated one may NOT fall through to the default alternative. That default is
    -- ready(self), a virtual ability has no CDM row, so the read would be UNKNOWN for life —
    -- and with the polarity inverted, the row would be hatched forever. Safe, and useless.
    broken = withVirtual(ns)
    entry(broken, "star").scan_when = nil
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).shape)
  end)

  it("refuses any subject predicate that asks about a virtual ability", function()
    -- ⚠ The same trap as the rule above, through the explicit door. EVERY subject read is
    -- sourced from a CDM row -- `Sense.buildReads` walks `state.bound.abilities`, `Track:Bind`
    -- binds `ready`/`aura` off the same list, and `Catalog.Resolve` puts an ability there only
    -- when it found a row. So a term about an ability whose whole declaration is "there is no
    -- row" reads UNKNOWN for life, and on a virtual row that is hatched forever with nothing
    -- saying why. The fixture's gated row reads about ANOTHER ability precisely to avoid this.
    for _, term in ipairs({
      { "proc", "star" }, { "ready", "consume" }, { "capped", "star" },
      { "affordable", "star" }, { "aura", "consume" }, { "identity", "star", "base" },
    }) do
      local broken = withVirtual(ns)
      entry(broken, "star").scan_when = { { term } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject, term[1] .. "/" .. term[2])
    end

    -- A marker's `when` is walked by the same pass, so it is refused on the same grounds --
    -- and from an ORDINARY entry, not just from the virtual one that declared the ability.
    local broken = withVirtual(ns)
    entry(broken, "star").markers = { { id = "m", cue = "blocked", when = { { "proc", "consume" } } } }
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
  end)

  it("allows readable markers on a virtual row and refuses sealed ones", function()
    local ok = withVirtual(ns)
    entry(ok, "star").markers = {
      { id = "held", cue = "blocked", when = { { "ready", "tyrant", negate = true } } },
    }
    assert.same({}, ns.Catalog.Check(ok))

    -- A sealed display is an AuraContainer the client builds over a Cooldown Manager item.
    -- There is no item under a virtual row, and nothing has ever built one on a cap-owned frame.
    local broken = withVirtual(ns)
    entry(broken, "star").markers = {
      { id = "count", cue = "blocked",
        display = { kind = "sealed-count-bar", ability = "demonbolt", max = 4 } },
    }
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).display)
  end)

  it("validates an ability's unit against the two the client is ever given", function()
    -- `Channel` derives the aura filter from `unit` and hands the string straight to SetUnit,
    -- so an unrecognised token arms a container watching nothing and never draws.
    local protection = H.copy(H.catalogBySpec(ns, 66))
    assert.same({}, ns.Catalog.Check(protection))

    for _, bad in ipairs({ "focus", "targettarget", "PLAYER" }) do
      local broken = H.copy(H.catalogBySpec(ns, 66))
      for _, ability in ipairs(broken.abilities) do
        if ability.unit then ability.unit = bad; break end
      end
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).shape, bad)
    end
  end)

  -- ---------------------------------------------------------------- resolution

  it("resolves a virtual entry into its own list and never demands a row for it", function()
    local found, resolved = ns.Catalog.CheckBound(cat, H.rows())
    -- Having no CDM row is what `virtual` DECLARES, so it is not a binding failure.
    assert.same({}, found)
    assert.same({}, resolved.dropped)

    assert.equal(2, #resolved.entries)
    assert.is_nil(resolved.byEntry.star)
    assert.is_nil(resolved.byEntry.consume)

    assert.equal(2, #resolved.virtual)
    assert.same({ "star", "consume" },
      { resolved.virtual[1].entry.id, resolved.virtual[2].entry.id })
    assert.is_nil(resolved.virtual[1].row)
  end)

  it("still needs the row when a CONDITION names the virtual ability", function()
    -- The exemption is for the entry's OWN binding, not for reads. A term about `star` is a read
    -- off the Cooldown Manager, so the missing row is a real hole and must be reported.
    local naming = withVirtual(ns)
    entry(naming, "tyrant").markers[1].when = { { "ready", "star" } }
    local resolved = ns.Catalog.Resolve(naming, H.rows())
    assert.equal("star", resolved.dropped[1] and resolved.dropped[1].id)
  end)

  it("leaves the layout order check untouched, having no position to check", function()
    local resolved = ns.Catalog.Resolve(cat, H.rows())
    assert.is_nil(ns.Catalog.OrderCheck(cat, resolved, H.rows()))
  end)

  -- ---------------------------------------------------------------- the verdict

  it("makes a standing row a member unconditionally, even blind", function()
    local resolved = ns.Catalog.Resolve(cat, H.rows())
    for _, world in ipairs({ H.world(), H.blindWorld() }) do
      local out = ns.Signal.Evaluate(resolved, world)
      local v = out.byEntry.consume
      assert.equal("standing", v.virtual)
      assert.is_nil(v.row)
      assert.is_true(v.member)
      assert.is_false(v.blind)
    end
  end)

  it("follows scan_when on a gated row, and withholds it when blind", function()
    local resolved = ns.Catalog.Resolve(cat, H.rows())

    local on = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true) })
    assert.is_true(on.byEntry.star.member)

    local off = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(false) })
    assert.is_false(off.byEntry.star.member)

    -- ⚠ THE INVERTED UNKNOWN, at its source. `member` is false when the read refused, and
    -- `Treatment` turns that into the hatch — so cap says "not yet" rather than "press this".
    local blind = ns.Signal.Evaluate(resolved, H.blindWorld())
    assert.is_false(blind.byEntry.star.member)
    assert.is_true(blind.byEntry.star.blind)
  end)

  it("evaluates a virtual row's readable markers exactly as a CDM row's", function()
    local marked = withVirtual(ns)
    entry(marked, "star").markers = {
      { id = "held", cue = "blocked", when = { { "ready", "tyrant", negate = true } } },
    }
    local resolved = ns.Catalog.Resolve(marked, H.rows())
    local out = ns.Signal.Evaluate(resolved, H.world{
      proc = H.map(true), ready = H.map(true, { tyrant = false }),
    })
    assert.same({ "held" }, out.byEntry.star.markers)
    assert.same({ "blocked" }, out.byEntry.star.cues)
  end)

  -- ---------------------------------------------------------------- the treatment

  it("hatches a virtual row as the complement of the scan", function()
    local scanning = ns.Treatment.For{ virtual = "gated", member = true, cues = {} }
    assert.is_true(scanning.scan)
    assert.is_false(scanning.hatch)

    local withheld = ns.Treatment.For{ virtual = "gated", member = false, cues = {} }
    assert.is_false(withheld.scan)
    assert.is_true(withheld.hatch)

    -- Unknown is neither true nor false, and it draws hatched — the whole of V12's inversion.
    assert.is_true(ns.Treatment.For{ virtual = "gated" }.hatch)

    -- A standing row is a member always, so it never hatches.
    assert.is_false(ns.Treatment.For{ virtual = "standing", member = true, cues = {} }.hatch)
  end)

  it("leaves a CDM row's hatch on the readiness latch, where an unknown draws bare", function()
    assert.is_true(ns.Treatment.For{ member = true, oncd = true, cues = {} }.hatch)
    assert.is_false(ns.Treatment.For{ member = true, cues = {} }.hatch)
  end)

  it("still skips a virtual row wearing a negative cue", function()
    local negative = ns.Treatment.For{ virtual = "gated", member = true, cues = { "blocked" } }
    assert.is_true(negative.skip)
    local positive = ns.Treatment.For{ virtual = "gated", member = true, cues = { "priority" } }
    assert.is_false(positive.skip)
  end)

  -- ---------------------------------------------------------------- the panel

  describe("plan", function()
    local Panel
    before_each(function() Panel = H.withPanel(ns) end)

    it("describes every virtual entry in authored order, and only those", function()
      local resolved = ns.Catalog.Resolve(cat, H.rows())
      local out = ns.Signal.Evaluate(resolved, H.world{ proc = H.map(true) })
      local plan = Panel.Plan(resolved, out)

      assert.equal(2, #plan)
      assert.same({ "star", "consume" }, { plan[1].id, plan[2].id })
      assert.same({ "gated", "standing" }, { plan[1].kind, plan[2].kind })
      -- The spell comes off the DECLARED ability: there is no bound row to read it from.
      assert.same({ 9000001, 9000002 }, { plan[1].spellID, plan[2].spellID })
      assert.is_true(plan[1].draw.scan)
      assert.is_true(plan[2].draw.scan)
    end)

    it("draws hatched when the verdict is missing entirely", function()
      -- The surface must never read an absent verdict as permission. This is the same rule as
      -- the blind one, on the path where Signal never produced a verdict at all.
      local resolved = ns.Catalog.Resolve(cat, H.rows())
      local plan = Panel.Plan(resolved, { byEntry = {} })
      assert.is_false(plan[1].draw.scan)
      assert.is_true(plan[1].draw.hatch)
      -- Even the standing row: with no verdict there is nothing asserting it is available.
      assert.is_true(plan[2].draw.hatch)
    end)

    it("plans nothing for a catalog with no virtual entries", function()
      local plain = ns.Catalog.Resolve(H.catalog(ns), H.rows())
      assert.same({}, Panel.Plan(plain, ns.Signal.Evaluate(plain, H.world())))
    end)

    -- ---------------------------------------------------------------- the live face

    -- ⚠ THE ONE PLACE V12 READS THE CLIENT, and it is here rather than in the catalog because
    -- the catalog is FORBIDDEN to say it: `Catalog.Check` refuses a subject predicate naming a
    -- virtual ability, so a standing row cannot declare `identity` about itself. Devourer's
    -- Consume becomes Devour inside Void Metamorphosis; without this the row draws Consume's
    -- icon through a window in which the button is Devour.
    describe("face", function()
      local saved
      before_each(function() saved = _G.C_Spell end)
      after_each(function() _G.C_Spell = saved end)

      it("draws the override face when the client reports one", function()
        _G.C_Spell = { GetOverrideSpell = function() return 1217610 end }
        assert.equal(1217610, Panel.Face(473662))
      end)

      it("keeps the base id for every shape of 'no override'", function()
        -- nil is the ordinary answer for an untransformed spell...
        _G.C_Spell = { GetOverrideSpell = function() return nil end }
        assert.equal(473662, Panel.Face(473662))
        -- ...and 0 is the other one. 0 is TRUTHY in Lua, so it has to be tested explicitly or
        -- the row would try to draw the art of spell zero.
        _G.C_Spell = { GetOverrideSpell = function() return 0 end }
        assert.equal(473662, Panel.Face(473662))
        -- An override equal to its input is not a transform.
        _G.C_Spell = { GetOverrideSpell = function(id) return id end }
        assert.equal(473662, Panel.Face(473662))
      end)

      it("falls back to the base id when the call is absent, raises, or answers oddly", function()
        _G.C_Spell = nil
        assert.equal(473662, Panel.Face(473662))
        _G.C_Spell = { GetOverrideSpell = function() error("taint") end }
        assert.equal(473662, Panel.Face(473662))
        _G.C_Spell = { GetOverrideSpell = function() return "1217610" end }
        assert.equal(473662, Panel.Face(473662))
        -- A plan with no spell id at all (an undeclared ability) passes straight through.
        _G.C_Spell = { GetOverrideSpell = function() return 1217610 end }
        assert.is_nil(Panel.Face(nil))
      end)
    end)

    it("writes a capture cell per entry in the overlay's own grammar", function()
      local resolved = ns.Catalog.Resolve(cat, H.rows())
      local out = ns.Signal.Evaluate(resolved, H.blindWorld())
      local plan = Panel.Plan(resolved, out)
      -- `off~` is the resting state of a withheld virtual row: no scan, and the hatch that says
      -- "not yet". Reading a bare `off` as "nothing drawn" would be wrong here.
      assert.equal("star:off~", Panel.Cell(plan[1]))
      assert.equal("consume:scan", Panel.Cell(plan[2]))
    end)
  end)
end)
