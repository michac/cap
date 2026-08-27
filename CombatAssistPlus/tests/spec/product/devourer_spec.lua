-- Provisional product characterization: the Void-Scarred RANGED roster's shape, not its
-- gameplay value. The reasoning for every claim here is specs/devourer/catalog.md, and the
-- walk that proves it is specs/devourer/scenarios.md.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("product characterization / Devourer", function()
  local ns, cat
  before_each(function()
    ns = H.fresh()
    cat = H.catalogBySpec(ns, 1480)
  end)

  local function entry(id)
    for _, e in ipairs(cat.entries) do if e.id == id then return e end end
  end

  local function marker(entryID, markerID)
    for _, m in ipairs((entry(entryID) or {}).markers or {}) do
      if m.id == markerID then return m end
    end
  end

  local function terms(m)
    local out = {}
    for _, t in ipairs((m or {}).when or {}) do
      out[t[1] .. ":" .. tostring(t[2]) .. ":" .. tostring(t[3]) .. (t.negate and ":!" or "")] = true
    end
    return out
  end

  it("validates, and declares no power because Fury is a secret primary", function()
    assert.same({}, ns.Catalog.Check(cat))
    assert.is_nil(cat.power)
    -- Void-Scarred's TraitSubTree id. Annihilator is 124 and is a separate catalog, so a wrong
    -- number here does not mis-draw — it binds NOTHING, silently, on the wrong hero tree.
    assert.equal(126, cat.hero)
  end)

  -- The authored entry order IS the priority, and the whole reading model depends on it.
  -- Voidblade is LAST deliberately: rung 1 is its only out-of-form line and fires in one narrow
  -- state, so a leftmost Voidblade would stop the scan on every build global.
  it("keeps the authored row order, with the Utility row and the terminus after the line", function()
    local order = {}
    for i, e in ipairs(cat.entries) do order[i] = e.id end
    assert.same({
      "void_metamorphosis", "reap", "void_ray", "soul_immolation", "voidblade",
      "vengeful_retreat", "consume",
    }, order)
  end)

  -- V12. Consume is the only press in the branch with no Cooldown Manager frame in any
  -- category, and its availability is a constant (cooldown 0, no power cost, no aura gate).
  it("makes Consume a STANDING virtual row, which asks for no verdict", function()
    local e = entry("consume")
    assert.equal("standing", e.virtual)
    assert.is_nil(e.scan_when)
    assert.same({}, ns.Catalog.Alternatives(e))
    -- And it may declare no markers at all: a sealed display needs a CDM frame to host it, and
    -- no readable one is authored here.
    assert.is_nil(e.markers)
  end)

  -- ⚠ The catalog is SILENT about Consume → Devour and that silence is load-bearing:
  -- `Catalog.Check` refuses any subject predicate naming a virtual ability. The face is
  -- resolved on the draw instead (`Panel.Face`), which is a texture and never a condition.
  it("refuses to name the virtual ability in a condition, so the transform stays undeclared", function()
    local broken = H.copy(cat)
    for _, e in ipairs(broken.entries) do
      if e.id == "soul_immolation" then
        e.markers[1].when = { { "identity", "consume", "transformed" } }
      end
    end
    assert.is_truthy(H.checks(ns.Catalog.Check(broken)).subject)
  end)

  -- ONE ROW, TWO COUNTS, THREE BANDS. The bank fork is a readable selection between two
  -- authored thresholds; the identity fork is what keeps the bank and the harvest counter apart.
  it("forks the sealed count on identity and on Soul Glutton, mutually exclusively", function()
    local glutton = marker("void_metamorphosis", "meta_bank_glutton")
    local deep = marker("void_metamorphosis", "meta_bank_deep")
    local star = marker("void_metamorphosis", "star_counter")

    assert.equal("void_metamorphosis_stack", glutton.display.ability)
    assert.equal("void_metamorphosis_stack", deep.display.ability)
    assert.equal("collapsing_star_stacking", star.display.ability)

    -- The thresholds, and they are the whole reason there are two markers rather than one.
    assert.equal(35, glutton.display.bands[2].threshold)
    assert.equal(50, deep.display.bands[2].threshold)
    assert.equal(30, star.display.bands[2].threshold)

    -- V17's complement: the marks draw BELOW the threshold and the band above clears them.
    for _, m in ipairs({ glutton, deep, star }) do
      assert.equal(0, m.display.bands[1].threshold)
      assert.equal("count", m.display.bands[1].draw)
      assert.equal("negative", m.display.bands[1].polarity)
      assert.is_true(m.display.bands[1].hatch)
      assert.equal("none", m.display.bands[2].draw)
    end

    -- Mutually exclusive gates, never a plain OR: each corner display claims a stack slot BY
    -- DECLARATION, so two live at once would draw two numerals at two corners.
    assert.is_true(terms(glutton)["identity:void_metamorphosis:base"])
    assert.is_true(terms(glutton)["talent:soul_glutton:nil"])
    assert.is_true(terms(deep)["identity:void_metamorphosis:base"])
    assert.is_true(terms(deep)["talent:soul_glutton:nil:!"])
    assert.is_true(terms(star)["identity:void_metamorphosis:transformed"])
  end)

  -- Cue D. It is a SOUND SLICE of rung 2, not the rung: `proc(reap)` is the OR of Eradicate and
  -- Moment of Craving, so the badge holds strictly less often than the rung would — and missing
  -- a hold is the safe direction.
  it("holds the transform in AoE on the Eradicate latch, scoped out of the form", function()
    local m = marker("void_metamorphosis", "meta_eradicate_hold")
    assert.equal("blocked", m.cue)
    local t = terms(m)
    assert.is_true(t["aoe:nil:nil"])
    assert.is_true(t["talent:eradicate:nil"])
    assert.is_true(t["proc:reap:nil:!"])
    -- Inside the form rung 2 is structurally dead: entering expires the bank and it cannot
    -- refill, so the hold must not follow the row across the transform.
    assert.is_true(t["identity:void_metamorphosis:base"])
  end)

  -- The position-1 correction. In AoE Collapsing Star is rung 9, BELOW Void Ray's rung 8, and
  -- the face is the leftmost icon — so the hold is the only thing that can say so.
  it("yields the in-form face to Void Ray in AoE, and asks whether Void Ray can fire", function()
    local m = marker("void_metamorphosis", "star_yields_to_void_ray")
    assert.equal("blocked", m.cue)
    local t = terms(m)
    assert.is_true(t["identity:void_metamorphosis:transformed"])
    assert.is_true(t["aoe:nil:nil"])
    -- ⚠ A hold that names a row must check that row is AVAILABLE, or it eliminates the correct
    -- press in every state where the outranker is swiped.
    assert.is_true(t["ready:void_ray:nil"])
    -- In single target there is no such hold: rung 5 sits ABOVE rung 8.
    assert.is_nil(m.display)
  end)

  -- Cue B. The readable gate beside a sealed curve: `identity` decides whether the client may
  -- paint at all, and the curve is the only thing that touches the secret.
  it("grades the drain save on Fury, gated on being in the form", function()
    local m = marker("soul_immolation", "soul_immolation_drain_save")
    assert.equal("blocked", m.cue)
    assert.equal("sealed-power-percent", m.display.kind)
    assert.equal("Fury", m.display.power)
    -- An ABSOLUTE threshold, because rung 13's term is one (`fury < drain_ps`). cap divides by
    -- the client's own max and never learns which side the secret fell on.
    assert.equal(17, m.display.threshold)
    assert.is_nil(m.display.generation)
    -- Void Metamorphosis's row is the unambiguous subject for "am I in the form" — Reap's
    -- identity also flips out of the form, when the Eradicate upgrade is banked.
    assert.is_true(terms(m)["identity:void_metamorphosis:transformed"])
  end)

  -- The Utility row: bound, skinned, hatched, and deliberately cue-less.
  it("gives Vengeful Retreat no cue, because Blizzard already glows Voidstep", function()
    local e = entry("vengeful_retreat")
    assert.is_nil(e.markers)
    assert.is_nil(e.scan_when)
  end)
end)
