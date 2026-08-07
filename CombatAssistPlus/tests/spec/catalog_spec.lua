-- catalog_spec.lua — the vocabulary and the six checks.
--
-- Authored from ../../../../specs/spec.md §3.5 and the Demonology catalog document,
-- never from Catalog.lua. Every "this check fires" case breaks the catalog in the one
-- way the check exists to catch: a suite where every check passes proves only that
-- nothing is currently wrong, not that a check could ever say so.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("Catalog", function()
  local ns, cat

  before_each(function()
    ns = H.fresh()
    cat = H.catalog(ns)
  end)

  describe("the authored Demonology catalog", function()
    it("passes every load-time check", function()
      local found = ns.Catalog.Check(cat)
      assert.same({}, found)
    end)

    it("sits exactly AT the six-window cap — a seventh needs one removed", function()
      local n = 0
      for _ in pairs(cat.windows) do n = n + 1 end
      assert.equal(ns.Catalog.MAX_WINDOWS, n)
    end)

    it("names Shadow Bolt as the floor", function()
      assert.equal(686, cat.floor)
    end)
  end)

  describe("each check can fail", function()
    it("breadth — when no entry is HIGH-capable", function()
      local broken = H.copy(cat)
      for _, e in ipairs(broken.entries) do
        for _, band in ipairs(e.bands or {}) do
          if band.tier == "HIGH" then band.tier = "MEDIUM" end
        end
        if e.cue then e.cue.tier = "MEDIUM" end
      end
      assert.equal(1, H.checks(ns.Catalog.Check(broken)).breadth)
    end)

    it("vocabulary — when a band names a term that is not a gate", function()
      local broken = H.copy(cat)
      broken.entries[1].bands[1].when = { { "tierOf", "E2" } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).vocabulary)
    end)

    it("vocabulary — when a band names an undeclared window", function()
      local broken = H.copy(cat)
      broken.entries[1].bands[1].when = { { "window", "burn_phase" } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).vocabulary)
    end)

    it("register — when a channel appears in a band condition", function()
      local broken = H.copy(cat)
      broken.entries[1].bands[1].when = { { "cooldownRemaining", "this" } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).register)
    end)

    it("register — when a cue's threshold is not a stack count", function()
      local broken = H.copy(cat)
      for _, e in ipairs(broken.entries) do
        if e.cue then e.cue.threshold = { channel = "cooldownRemaining", of = 196277 } end
      end
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).register)
    end)

    it("positive — when a band term is negated", function()
      local broken = H.copy(cat)
      broken.entries[1].bands[1].when = { { "ready", "this", negate = true } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).positive)
    end)

    it("cue-honesty — when a HIGH cue carries no gate", function()
      local broken = H.copy(cat)
      for _, e in ipairs(broken.entries) do
        if e.cue then e.cue.gate = {} end
      end
      assert.is_truthy(H.checks(ns.Catalog.Check(broken))["cue-honesty"])
    end)

    it("floor — when the catalog names none", function()
      local broken = H.copy(cat)
      broken.floor = nil
      assert.equal(1, H.checks(ns.Catalog.Check(broken)).floor)
    end)
  end)

  describe("bound against the 21 rows the client actually recorded", function()
    local rows

    before_each(function() rows = H.rows() end)

    it("covers every tracked row — nothing left over", function()
      local found = ns.Catalog.CheckBound(cat, rows)
      assert.same({}, found)
    end)

    it("drops the entries this build does not have", function()
      local _, resolved = ns.Catalog.CheckBound(cat, rows)
      local dropped = {}
      for _, d in ipairs(resolved.dropped) do dropped[d.id] = true end
      -- Summon Doomguard is not talented; Power Siphon lost its choice node to Implosion.
      assert.is_true(dropped.E4)
      assert.is_true(dropped.E9)
      assert.equal(2, #resolved.dropped)
    end)

    it("still passes breadth after the drops", function()
      local found = ns.Catalog.CheckBound(cat, rows)
      assert.is_nil(H.checks(found).breadth)
    end)

    it("binds Call Dreadstalkers' two rows to different things", function()
      local _, resolved = ns.Catalog.CheckBound(cat, rows)
      -- The Essential row is E2's press; the BuffBar row is E1's auraUp source and is
      -- silenced. A roster keyed by spellID alone would give both to whichever it met
      -- first and be wrong for one of the two gates.
      assert.equal(671, resolved.byEntry.E2.cooldownID)
      assert.equal("E2", resolved.claimed[671])
      assert.equal("silence", resolved.claimed[760])
    end)

    it("coverage fires when a silence is removed", function()
      local broken = H.copy(cat)
      for i, s in ipairs(broken.silences) do
        if s.spell == 264173 then table.remove(broken.silences, i); break end
      end
      local found = ns.Catalog.CheckBound(broken, rows)
      assert.equal(1, H.checks(found).coverage)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Windows and the reads they imply
  --------------------------------------------------------------------------------
  describe("window rules", function()
    it("declares one for every window, so none is a bare assertion", function()
      for name, rule in pairs(cat.windows) do
        assert.is_table(rule, name .. " declares no rule")
        assert.is_true(#rule > 0, name .. " declares an empty rule")
      end
    end)

    it("permits negation, which a band may not", function()
      local found = ns.Catalog.Check(cat)
      assert.same({}, found)
      -- cores_dry IS a negation, and the same term inside a band must fail.
      local broken = H.copy(cat)
      broken.entries[1].bands[1].when = { { "ready", "this", negate = true } }
      assert.equal(1, H.checks(ns.Catalog.Check(broken)).positive)
    end)

    it("refuses a window naming another window", function()
      local broken = H.copy(cat)
      broken.windows.cores_dry = { { "window", "opener" } }
      assert.is_true((H.checks(ns.Catalog.Check(broken)).vocabulary or 0) > 0)
    end)

    it("refuses a window naming an entry the catalog does not declare", function()
      local broken = H.copy(cat)
      broken.windows.tyrant_setup = { { "ready", "E99" } }
      assert.is_true((H.checks(ns.Catalog.Check(broken)).vocabulary or 0) > 0)
    end)

    it("refuses a channel inside a window", function()
      local broken = H.copy(cat)
      broken.windows.tyrant_setup = { { "cooldownRemaining", "E1" } }
      assert.is_true((H.checks(ns.Catalog.Check(broken)).register or 0) > 0)
    end)

    it("refuses `resource` with no power type to read it from", function()
      local broken = H.copy(cat)
      broken.power = nil
      assert.is_true((H.checks(ns.Catalog.Check(broken)).shape or 0) > 0)
    end)
  end)

  describe("Reads — which gate is asked of which entry", function()
    local reads
    before_each(function() reads = ns.Catalog.Reads(cat) end)

    it("asks identity of Ruination alone", function()
      assert.is_true(reads.byEntry.E6.identity)
      assert.is_nil(reads.byEntry.E5.identity)
    end)

    it("asks readiness of E1 because a WINDOW names it, not only its own band", function()
      -- tyrant_setup is `ready(E1)`; without the window walk this would still be true
      -- from E1's own band, so cores_dry is the case that proves the walk runs.
      assert.is_true(reads.byEntry.E7.proc, "cores_dry names proc(E7)")
    end)

    it("turns a window's `remaining` into the elapsed read it is derived from", function()
      assert.is_true(reads.byEntry.E1.elapsed)
      assert.is_nil(reads.byEntry.E1.remaining, "remaining is arithmetic, not a read")
    end)

    it("collects only the aura ids a band actually names", function()
      assert.is_true(reads.auras[1276166], "Dominion of Argus feeds E5 band 1")
      assert.is_nil(reads.auras[264173], "Demonic Core is a proc gate, not an auraUp")
    end)
  end)
end)
