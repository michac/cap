-- catalog_spec.lua — the vocabulary and the five checks.
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

    it("discloses no estimate — nothing in it uses `elapsed`", function()
      local _, disclosed = ns.Catalog.Check(cat)
      assert.same({}, disclosed)
    end)

    it("names Shadow Bolt as the floor", function()
      assert.equal(686, cat.floor)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Check 2 — register legality, and the vocabulary failures a closed set implies
  --------------------------------------------------------------------------------
  describe("check 2 — register legality", function()
    it("refuses a channel in a band condition", function()
      local broken = H.copy(cat)
      broken.entries[1].bands[1].when = { { "cooldownRemaining", "this" } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).register)
    end)

    it("refuses a channel in a cue's gate precondition, which is band-legal", function()
      local broken = H.copy(cat)
      broken.entries[1].cues[1].gate = { { "cooldownRemaining", "E2", "<=", 8 } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).register)
    end)

    it("refuses `casts`, which is sequence-trigger vocabulary and nothing else", function()
      -- A band testing a position in an order IS an opener, which duplicates §3.3.
      local broken = H.copy(cat)
      broken.entries[1].bands[1].when = { { "casts", "==", 0 } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).register)
    end)

    it("refuses a gate driving a cue's channel", function()
      local broken = H.copy(cat)
      broken.entries[1].cues[1].channel = { "ready", "E2" }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).register)
    end)

    it("refuses a term that is in neither column", function()
      local broken = H.copy(cat)
      broken.entries[1].bands[1].when = { { "tierOf", "E2" } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).vocabulary)
    end)

    it("refuses `elapsed` on any subject but `this`", function()
      -- An entry may estimate about itself and about nothing else; every other subject
      -- has a channel the client evaluates exactly.
      local broken = H.copy(cat)
      broken.entries[1].bands[1].when = { { "elapsed", "E2", "<=", 12 } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).vocabulary)
    end)

    it("permits negation in a band, on this and on another subject alike", function()
      assert.same({}, ns.Catalog.Check(cat))
      local negated = 0
      for _, e in ipairs(cat.entries) do
        for _, band in ipairs(e.bands) do
          for _, term in ipairs(band.when) do
            if term.negate then negated = negated + 1 end
          end
        end
      end
      assert.is_true(negated > 0, "the catalog under test negates nothing, so this proves nothing")
    end)
  end)

  --------------------------------------------------------------------------------
  -- Check 3 — declared subjects
  --------------------------------------------------------------------------------
  describe("check 3 — declared subjects", function()
    it("refuses a band naming an ability the catalog does not declare", function()
      local broken = H.copy(cat)
      broken.entries[1].bands[1].when = { { "ready", "E99" } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
    end)

    it("refuses a cue's channel naming an undeclared ability", function()
      local broken = H.copy(cat)
      broken.entries[1].cues[1].channel = { "cooldownRemaining", "E99", "<=", 8 }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
    end)

    it("refuses a grade naming an undeclared ability", function()
      local broken = H.copy(cat)
      broken.entries[1].grade = { channel = "cooldownRemaining", of = "E99" }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
    end)

    it("accepts a spell id a silence declares — an aura read is a declared subject", function()
      assert.is_nil(H.checks(ns.Catalog.Check(cat)).subject)
      local broken = H.copy(cat)
      for i, s in ipairs(broken.silences) do
        if s.spell == 1276166 then table.remove(broken.silences, i); break end
      end
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject, "E5's auraUp lost its silence")
    end)

    --------------------------------------------------------------------------------
    -- Check 3 polices the FORM of a subject, not merely its membership. Membership
    -- alone lets a band name a declared SPELL ID where an entry belongs: it type-checks,
    -- passes every other check, and is then permanently UNKNOWN in play while gate health
    -- reports the gate as fully known, because the read was never asked for at all.
    --------------------------------------------------------------------------------
    it("refuses an entry gate naming a declared SPELL ID — an unanswerable subject", function()
      -- `{"proc", 264173}` is Demonic Core, which the catalog declares as a silence. It is
      -- semantically what `{"proc", "E7"}` says and it can never be answered: `proc` is
      -- read off a bound CDM row and only entries resolve to rows.
      for _, gate in ipairs({ "ready", "affordable", "proc", "elapsed", "identity" }) do
        local broken = H.copy(cat)
        local term = { gate, 264173 }
        if gate == "identity" then term = { gate, 264173, "transformed" } end
        if gate == "elapsed" then term = { gate, 264173, "<=", 12 } end
        broken.entries[1].bands[1].when = { term }
        local checks = H.checks(ns.Catalog.Check(broken))
        -- `elapsed` is caught one line earlier, by its own `this`-only restriction.
        assert.is_truthy(checks.subject or checks.vocabulary, gate .. " admitted a spell id")
      end
    end)

    it("refuses an entry gate naming the catalog's own entry spell id", function()
      -- E2's own base spell, which the catalog certainly declares. Still not an entry id.
      local broken = H.copy(cat)
      broken.entries[1].bands[1].when = { { "ready", 104316 } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
    end)

    it("refuses `auraUp` naming an ENTRY id — an aura is named by spell id", function()
      -- The mirror failure, and the worse one: `Track.Binding` filters aura rows against
      -- the numeric ids Reads collected, so an entry id never enters `auraIDs` at all —
      -- no latch, no tally, and the band is silently dead for the life of the build.
      local broken = H.copy(cat)
      broken.entries[5].bands[1].when = { { "auraUp", "E2" }, { "affordable", "this" } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
    end)

    it("refuses `auraUp(this)`, which reads as an entry and resolves to nothing", function()
      local broken = H.copy(cat)
      broken.entries[5].bands[1].when = { { "auraUp", "this" } }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
    end)

    it("refuses a `stacks` channel naming an entry, and a `cooldownRemaining` naming a spell id", function()
      -- The same split runs down the channel column: cap hands the client a ROW for
      -- `cooldownRemaining`, and a spell id for `stacks`.
      local broken = H.copy(cat)
      broken.entries[8].cues[1].channel = { "stacks", "E8", ">=", 6 }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)

      broken = H.copy(cat)
      broken.entries[1].cues[1].channel = { "cooldownRemaining", 104316, "<=", 8 }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
    end)

    it("still accepts every legal form", function()
      local ok = H.copy(cat)
      ok.entries[1].bands[1].when = {
        { "ready", "this" }, { "ready", "E2", negate = true },
        { "affordable", "E5" }, { "proc", "E7" }, { "identity", "E6", "transformed" },
        { "elapsed", "this", "<=", 12 },
        { "auraUp", 1276166 },
      }
      ok.entries[1].cues[1].channel = { "cooldownRemaining", "this", "<=", 8 }
      -- `elapsed(this)` discloses under check 5, which cannot fail — findings only.
      local found = ns.Catalog.Check(ok)
      assert.same({}, found)
    end)

    it("refuses a grade naming a subject on a term that takes none", function()
      local broken = H.copy(cat)
      broken.entries[5].grade = { channel = "resource", direction = "rising", of = "E5" }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
    end)

    it("exempts the arguments that are not subjects", function()
      -- `talent`'s argument may be a passive with no CDM row, so it can be neither an
      -- entry nor a silence; `mode`'s is a literal; `resource` and `combat` take none.
      local ok = H.copy(cat)
      ok.entries[1].bands[1].when = {
        { "talent", 999999 }, { "mode", "aoe" }, { "resource", ">=", 1 }, { "combat" },
      }
      assert.same({}, ns.Catalog.Check(ok))
    end)
  end)

  --------------------------------------------------------------------------------
  -- Check 4 — cue schema
  --------------------------------------------------------------------------------
  describe("check 4 — cue schema", function()
    local function firstCue(c) return c.entries[1].cues[1] end

    it("refuses a cue with no polarity", function()
      local broken = H.copy(cat)
      firstCue(broken).polarity = nil
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).cue)
    end)

    it("refuses a positive cue that declares no tier", function()
      local broken = H.copy(cat)
      firstCue(broken).polarity, firstCue(broken).tier = "positive", nil
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).cue)
    end)

    it("refuses a negative cue that declares one — the hold treatment is no tier", function()
      local broken = H.copy(cat)
      firstCue(broken).tier = "HIGH"
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).cue)
    end)

    it("refuses a cue with no gate precondition, of either polarity", function()
      local broken = H.copy(cat)
      firstCue(broken).gate = {}
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).cue)
    end)

    it("refuses a NEGATIVE cue on a bare countdown", function()
      -- Un-thresholded, `cooldownRemaining(E2)` draws hold at 45 s out as readily as at 5,
      -- which is a permanent marker wearing a number.
      local broken = H.copy(cat)
      firstCue(broken).channel = { "cooldownRemaining", "E2" }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).cue)
    end)

    it("refuses a channel form its own row does not have", function()
      local broken = H.copy(cat)
      firstCue(broken).channel = { "stacks", 296553 }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).register)
      broken = H.copy(cat)
      firstCue(broken).channel = { "cooldownRemaining", "E2", ">=", 8 }
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).register)
    end)

    it("accepts a bare countdown on a positive cue — §3.4's bars want the number", function()
      local ok = H.copy(cat)
      firstCue(ok).polarity, firstCue(ok).tier = "positive", "MEDIUM"
      firstCue(ok).channel = { "cooldownRemaining", "E2" }
      assert.same({}, ns.Catalog.Check(ok))
    end)
  end)

  --------------------------------------------------------------------------------
  -- Check 5 — estimate disclosure, which reports and cannot fail
  --------------------------------------------------------------------------------
  describe("check 5 — estimate disclosure", function()
    it("names the band using `elapsed` without failing the catalog", function()
      local using = H.copy(cat)
      using.entries[1].bands[1].when = { { "elapsed", "this", "<=", 12 } }
      local found, disclosed = ns.Catalog.Check(using)
      assert.same({}, found)
      assert.equal(1, #disclosed)
      assert.equal("E1", disclosed[1].entry)
      assert.is_truthy(disclosed[1].detail:find("cooldownRemaining"))
    end)
  end)

  --------------------------------------------------------------------------------
  -- Shape
  --------------------------------------------------------------------------------
  describe("shape", function()
    it("refuses `resource` with no power type to read it from", function()
      local broken = H.copy(cat)
      broken.power = nil
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).shape)
    end)

    it("refuses a band declaring something that is not a tier", function()
      local broken = H.copy(cat)
      broken.entries[1].bands[1].tier = "URGENT"
      assert.is_truthy(H.checks(ns.Catalog.Check(broken)).shape)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Check 1 — coverage, against the 21 rows the client actually recorded
  --------------------------------------------------------------------------------
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

    it("binds Call Dreadstalkers' two rows to different things", function()
      local _, resolved = ns.Catalog.CheckBound(cat, rows)
      -- The Essential row is E2's press; the BuffBar row is E1's auraUp source and is
      -- silenced. A roster keyed by spellID alone would give both to whichever it met
      -- first and be wrong for one of the two gates.
      assert.equal(671, resolved.byEntry.E2.cooldownID)
      assert.equal("E2", resolved.claimed[671])
      assert.equal("silence", resolved.claimed[760])
    end)

    it("binds E3 through `alt` on the other half of its choice node", function()
      -- Fel Ravager and Imp Lord are one entry covering both; keying on `spell` alone
      -- drops E3 silently on the half the fixture does not carry, and a real HIGH with it.
      for _, row in ipairs(rows) do
        if row.spellIDs[1276452] then
          row.spellIDs = { [1276467] = true }
          row.primary, row.base = 1276467, 1276467
        end
      end
      local found, resolved = ns.Catalog.CheckBound(cat, rows)
      assert.same({}, found)
      assert.equal(135056, resolved.byEntry.E3.cooldownID)
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
  -- Reads — which gate is asked, and ABOUT WHICH entry
  --------------------------------------------------------------------------------
  describe("Reads — which gate is asked of which entry", function()
    local reads
    before_each(function() reads = ns.Catalog.Reads(cat) end)

    it("asks identity of the two entries that read a transform, and no others", function()
      assert.is_true(reads.byEntry.E6.identity)
      assert.is_true(reads.byEntry.E10.identity)
      assert.is_nil(reads.byEntry.E5.identity)
    end)

    it("keys a cross-entry read against the SUBJECT, not the entry that named it", function()
      -- E1's band 1 is `ready(this) and not ready(E2)`. Tallying that against E1 would
      -- report E2 as never-asked and E1 as blind twice over.
      assert.is_true(reads.byEntry.E2.ready)
      assert.is_nil(reads.byEntry.E1.affordable, "nothing asks E1's affordability")
      assert.is_true(reads.byEntry.E2.affordable)
    end)

    it("collects a read a cue's gate precondition asks for", function()
      -- E9's band names proc(E7); so does E7's own. E1's cue gate is the case that
      -- proves cue preconditions are walked at all.
      assert.is_true(reads.byEntry.E7.proc)
    end)

    it("asks nothing about elapsed — the catalog carries no estimate", function()
      assert.is_nil(reads.byEntry.E1.elapsed)
    end)

    it("collects only the aura ids a band actually names", function()
      assert.is_true(reads.auras[1276166], "Dominion of Argus feeds E5 band 1")
      assert.is_nil(reads.auras[264173], "Demonic Core is a proc gate, not an auraUp")
    end)

    it("files an aura read under its SPELL ID and never under an entry", function()
      -- `Tier.evaluators.auraUp` reads `w.auraUp[<spell id>]` and `Track.Binding` filters
      -- aura rows against exactly this set, so an entry id in it is a row that never
      -- latches: no aura ids survive the filter, nothing tallies, and the band is dead
      -- with no signal. Check 3 refuses the authoring mistake; this pins the other half.
      for k in pairs(reads.auras) do
        assert.equal("number", type(k), "an entry id reached the aura set")
      end
      assert.is_nil(reads.byEntry.E5 and reads.byEntry.E5.auraUp,
        "an aura read must not be tallied as a per-entry gate")
    end)
  end)
end)
