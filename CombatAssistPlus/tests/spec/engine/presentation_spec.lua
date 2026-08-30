-- Mechanical presentation seams only; pixels remain an in-game judgment.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("engine / presentation", function()
  local ns
  before_each(function() ns = H.fresh() end)

  it("draws a member row as the ONE scan treatment, with nothing finer to draw", function()
    local d = ns.Treatment.For{ member = true }
    assert.is_true(d.scan)
    -- Membership reaches the paint as one bit. Anything here that could grade one member row
    -- against another is a hue ladder growing back (render-shelf V2).
    assert.is_nil(d.lane, "a member row still carries a drawn lane")
    assert.is_nil(d.thickness, "a member row still carries a band width the border cannot use")
    assert.is_false(ns.Treatment.For{ member = false }.scan)
    assert.is_false(ns.Treatment.For{}.scan)
    assert.is_nil(ns.Treatment.ORDER, "the lane validation set should be gone with the lanes")
    assert.is_nil(ns.Treatment.Pulse)
  end)

  it("draws a charged row exactly as it draws any other in-scan row", function()
    -- CHARGES was a fourth hue that REPLACED the role lane. With one treatment there is nothing
    -- for it to replace: the catalog still authors `charged`, and the paint no longer reads it.
    assert.same(ns.Treatment.For{ member = true },
                ns.Treatment.For{ member = true, charged = true })
    -- A non-member row is out of the scan, charged or not.
    assert.is_false(ns.Treatment.For{ charged = true }.scan)
  end)

  it("carries the authored charged flag from the catalog through to the verdict", function()
    local cat = H.catalogBySpec(ns, 267)
    local resolved = ns.Catalog.Resolve(cat, H.destructionRows())
    assert.is_true(resolved.entries[1].charged)
    local v = ns.Signal.Evaluate(resolved, H.world()).byEntry.conflagrate
    assert.is_true(v.charged)
  end)

  it("has no ad-hoc marker vocabulary beside the shelf's cues", function()
    assert.is_nil(ns.Treatment.MARKERS)
    assert.is_nil(ns.Treatment.Marker)
  end)

  it("plans only the independent declared bar and carries no icon treatment", function()
    local Bars = H.withBars(ns)
    local cat = H.catalog(ns)
    local resolved = ns.Catalog.Resolve(cat, H.rows())
    local out = ns.Signal.Evaluate(resolved, H.world())
    local plan = Bars.Plan(cat.bar, out)
    assert.equal(1, #plan)
    assert.equal("tyrant", plan[1].id)
    assert.is_nil(plan[1].treatment)
  end)
  -- V11 · the cooldown hatch. Its whole safety property is the direction of the default: cap
  -- draws it when it has been TOLD the button is down, and never infers the opposite.
  describe("the cooldown hatch", function()
    it("draws only on a readiness the CDM actually reported as false", function()
      assert.is_true(ns.Treatment.For{ member = true, oncd = true }.hatch)
      assert.is_false(ns.Treatment.For{ member = true, oncd = false }.hatch)
    end)

    it("draws nothing for an unknown or absent readiness", function()
      assert.is_false(ns.Treatment.For{ member = true }.hatch)
      assert.is_false(ns.Treatment.For{ member = true, oncd = ns.Signal.UNKNOWN }.hatch)
      assert.is_false(ns.Treatment.For{ member = true, oncd = nil }.hatch)
    end)

    -- It is a fact about the button, not about cap's opinion of it, so a row outside the
    -- scan still wears it. `Overlay.cell` renders that as `id:off~`, which is why a bare `off`
    -- can no longer be read as "nothing drawn".
    it("is independent of whether the row is in the scan", function()
      local d = ns.Treatment.For{ oncd = true }
      assert.is_false(d.scan)
      assert.is_true(d.hatch)
    end)
  end)

  -- The badge Z-STACK. The corner is one pixel deep and only the top of the order draws, so
  -- everything here is about which badge that is and — the half a look at the client cannot
  -- check — that every other one is explicitly put away.
  describe("the badge z-stack", function()
    it("puts a NEGATIVE over a positive, whatever the ranks say", function()
      -- `priority` outranks `blocked` (1 against 3) and still loses. Hiding a negative behind a
      -- positive makes a held row look pressable, which is the one mistake that costs a press.
      local d = ns.Treatment.For{ member = true, cues = { "priority", "blocked" } }
      assert.equal("blocked", d.winner)
      assert.is_true(d.badges.blocked)
      assert.is_false(d.badges.priority)
      -- Both are still REPORTED: the loser exists, it is simply not the one drawn.
      assert.same({ "priority", "blocked" }, d.cues)
    end)

    it("lets rank decide inside one polarity, in both directions", function()
      assert.equal("blocked", ns.Treatment.For{ cues = { "noproc", "blocked" } }.winner)
      assert.equal("priority", ns.Treatment.For{ cues = { "capped", "priority" } }.winner)
    end)

    it("reads a cue with no declared polarity as negative", function()
      -- Same reading the hatch gives it: the one that can only be stricter.
      local d = ns.Treatment.For{ cues = { "priority", "nonesuch" } }
      assert.equal("nonesuch", d.winner)
      assert.is_false(d.badges.priority)
    end)

    it("names no winner and lights nothing on a row wearing no cue", function()
      local d = ns.Treatment.For{ member = true, cues = {} }
      assert.is_nil(d.winner)
      for key, on in pairs(d.badges) do
        assert.is_false(on, key .. " is lit on a row that wears no cue")
      end
    end)

    -- ⚠ THE ONE THAT CANNOT BE SEEN BY LOOKING. A badge is a pooled frame that outlives the
    -- verdict which raised it. Under the old flowing stack a loser nobody hid sat visibly one
    -- step down the edge; under a z-stack it sits UNDER the winner, invisible, until the winner
    -- stops drawing — and then it shows the state before last. So the answer must be a decision
    -- for every key in the vocabulary, not a list of the ones to light.
    it("answers for EVERY cue in the vocabulary, so a loser is hidden and not merely covered",
      function()
        local both = ns.Treatment.For{ member = true, cues = { "priority", "blocked" } }
        local one = ns.Treatment.For{ member = true, cues = { "priority" } }
        -- The repaint drops `blocked`. It must come back as an explicit false, not as absent.
        assert.is_false(one.badges.blocked,
          "the badge that stopped winning is not taken down — it would draw its last state the "
          .. "moment the row stops wearing what is over it")
        assert.is_true(one.badges.priority)
        for key in pairs(ns.Style.cues) do
          assert.is_not_nil(both.badges[key], key .. " has no answer in the badge map")
          assert.is_not_nil(one.badges[key], key .. " has no answer in the badge map")
        end
      end)

    it("orders the stack's levels so no positive can ever sit over a negative", function()
      local P, Z, top = ns.Paint, ns.Paint.Z, 0
      for key, cue in pairs(ns.Style.cues) do
        local level = P.CueLevel(cue.polarity, cue.rank)
        if cue.polarity == "positive" then
          assert.is_true(level < Z.negative, key .. " is positive and sits in the negative band")
        else
          assert.is_true(level >= Z.negative, key .. " is negative and sits below one")
        end
        top = math.max(top, level)
      end
      -- Corner sealed displays are the floor: they lose to everything and win against nothing,
      -- and the LAST one declared sits on the level the eliminating hatch has always needed.
      assert.is_true(P.CornerLevel(0, 4) < Z.positive)
      assert.equal(Z.corner, P.CornerLevel(3, 4))
      assert.is_true(top > Z.positive)
    end)

    it("puts every eliminating mark OVER the scan edge, by declaration", function()
      -- render-shelf.md Part 2.5. A scan edge says `this row is in the read` and an eliminating
      -- mark says `this row is out`; a row wearing a negative cue wears both, so the later word
      -- has to win by declaration rather than by the order two frames happened to be built in.
      -- ⚠ THE DEFECT THIS PINS: cap's own hatch was the one eliminating layer with no declared
      -- level, and the client and the preview resolved it opposite ways on the same row.
      local Z = ns.Paint.Z
      assert.is_true(Z.skip > Z.edge, "cap's hatch must beat the scan edge")
      assert.is_true(Z.corner > Z.skip,
        "a sealed corner display says WHY the row is out and must stay legible over the hatch")
      assert.is_true(Z.positive > Z.corner and Z.negative > Z.positive)
    end)
  end)

  describe("the live cooldown dial", function()
    it("is ONE widget with one builder, and the old name is gone", function()
      -- The rename is the guarantee: `sealed-base-cooldown` and `sealed-cooldown-range` build the
      -- same dial, and a caller reaching for the base-only name would be reaching for a widget
      -- that no longer exists rather than silently getting a second implementation.
      assert.is_function(ns.Channel.ArmCooldownDial)
      assert.is_nil(ns.Channel.ArmBaseCooldown)
    end)

    it("names all three suppliers and nothing that is not a declared display", function()
      local dials = ns.Catalog.DIAL_DISPLAYS
      assert.is_true(dials["sealed-base-cooldown"])
      assert.is_true(dials["sealed-cooldown-range"])
      -- The third resolves no cooldown at all: it is an AuraContainer slot draining an AURA's
      -- own duration. What puts it in this table is the one thing the table decides — the cue's
      -- badge IS the dial, so the still glyph is not drawn over it.
      assert.is_true(dials["sealed-aura-remaining"])
      local n = 0
      for kind in pairs(dials) do
        n = n + 1
        assert.is_true(ns.Catalog.DISPLAYS[kind], kind .. " is not a declared display kind")
      end
      assert.equal(3, n)
    end)

    it("plans the aura form off the MARKER's ability, and refuses one with no cue", function()
      -- render-shelf V21's third supplier. The subject is the ability the marker names, which is
      -- what lets the badge reach across rows — Demonbolt's hold drawing the armed Art's clock.
      -- The cue is mandatory: the dial stands in for that cue's badge, and one without a cue
      -- would be an ornament sitting on the badge's own corner.
      local abilities = { art = { spell = 432794, family = "auras" } }
      local m = { id = "m", cue = "blocked",
                  display = { kind = "sealed-aura-remaining", ability = "art" } }
      local plan = ns.Channel.AuraRemainingPlan(m, abilities)
      assert.equal(432794, plan.spell)
      assert.equal("player", plan.unit)
      assert.equal("blocked", plan.cue)
      -- ...and it reaches the container seam, which is what actually arms it.
      assert.equal("sealed-aura-remaining", ns.Channel.ContainerPlan(m, abilities).kind)
      assert.is_nil(ns.Channel.AuraRemainingPlan(
        { id = "m", display = { kind = "sealed-aura-remaining", ability = "art" } }, abilities))
      assert.is_nil(ns.Channel.AuraRemainingPlan(m, {}))
      -- It is not a cooldown and not a curve, so neither of the other two seams claims it.
      assert.is_nil(ns.Channel.GradedPlan(m))
      assert.is_nil(ns.Channel.BaseCooldownPlan(m, { base = 99 }))
    end)

    it("keeps the two plans apart, because they resolve different spells", function()
      -- render-shelf V21: the base form reads the BOUND ROW's base id and the band form reads a
      -- named ability, so a plan built from the wrong one draws the wrong clock. `BaseCooldownPlan`
      -- takes a row and refuses a band; `GradedPlan` takes the marker and refuses a base.
      local base = { id = "m", display = { kind = "sealed-base-cooldown", ability = "x" } }
      local band = { id = "m", cue = "blocked",
                     display = { kind = "sealed-cooldown-range", ability = "x", within = 10 } }
      assert.equal(99, ns.Channel.BaseCooldownPlan(base, { base = 99 }).spell)
      assert.is_nil(ns.Channel.BaseCooldownPlan(base, {}))
      assert.is_nil(ns.Channel.BaseCooldownPlan(band, { base = 99 }))
      assert.is_nil(ns.Channel.GradedPlan(base))
      assert.equal("sealed-cooldown-range", ns.Channel.GradedPlan(band).kind)
    end)
  end)
end)
