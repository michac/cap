-- Provisional product characterization: the Templar roster's shape, not its gameplay value.
-- The reasoning for every claim here is specs/retribution/catalog.md.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("product characterization / Retribution", function()
  local ns, cat
  before_each(function()
    ns = H.fresh()
    cat = H.catalogBySpec(ns, 70)
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
      out[t[1] .. ":" .. tostring(t[2]) .. (t.negate and ":!" or "")] = true
    end
    return out
  end

  it("validates, and declares Holy Power because it is never-secret", function()
    assert.same({}, ns.Catalog.Check(cat))
    assert.equal("HolyPower", cat.power)
  end)

  -- The authored entry order IS the priority, and the whole reading model depends on it.
  it("keeps the authored row order", function()
    local order = {}
    for i, e in ipairs(cat.entries) do order[i] = e.id end
    assert.same({
      "execution_sentence", "avenging_wrath", "wake_of_ashes", "divine_toll",
      "templars_verdict", "divine_storm", "blade_of_justice", "judgment", "crusader_strike",
    }, order)
  end)

  -- Cue G. The opener defect this catalog was rewritten to fix: on a Holy Flames build the
  -- APL FORBIDS Avenging Wrath until Expurgation is on the target, so the row must hold.
  it("holds Avenging Wrath on the Expurgation latch, gated on the talent", function()
    local m = marker("avenging_wrath", "aw_awaits_expurgation")
    assert.is_not_nil(m)
    assert.equal("blocked", m.cue)
    local t = terms(m)
    assert.is_true(t["aura:expurgation:!"])
    -- Without Holy Flames the APL term is vacuously true and this marker must not fire.
    assert.is_true(t["talent:holy_flames"])
  end)

  -- 383344 is the passive talent node; 383346 is the debuff that lands. Confirmed by icon
  -- in client 2026-08-19. Binding the wrong one produces a marker that never lights.
  it("reads the Expurgation DoT, not the talent, off a tracked-buff row", function()
    local expurgation
    for _, a in ipairs(cat.abilities) do if a.id == "expurgation" then expurgation = a end end
    assert.is_not_nil(expurgation)
    assert.equal(383346, expurgation.spell)
    assert.equal("auras", expurgation.family)
    assert.equal("target", expurgation.unit)
  end)

  -- Only row 1 carries a readable companion to a sealed hold, because only row 1 sits LEFT of
  -- everything it waits on. Rows to the right are covered by elimination's zero case.
  it("gives Execution Sentence a readable companion, and only it", function()
    local m = marker("execution_sentence", "es_awaits_wrath_ready")
    assert.is_not_nil(m)
    assert.is_true(terms(m)["ready:avenging_wrath"])
    assert.is_nil(m.display, "this is the READABLE half and must not be a sealed band")
    -- These two existed only to steer the scan past their own rows at the opener. Promoting the
    -- opener (cue H) retired both; re-adding one means the promotion has stopped doing its job.
    assert.is_nil(marker("wake_of_ashes", "woa_awaits_wrath_ready"))
    assert.is_nil(marker("divine_toll", "dt_awaits_wrath_ready"))
  end)

  -- Cue H. The catalog's ONE promotion, and it is justified by density, not importance: said by
  -- elimination the opener needs four holds, which is over render-shelf.md Part 0.5's budget.
  it("promotes Blade of Justice at the opener, and only there", function()
    local m = marker("blade_of_justice", "boj_opener")
    assert.is_not_nil(m)
    assert.equal("priority", m.cue)
    local t = terms(m)
    -- The APL rung, minus `time<5` -- the latch subsumes it.
    assert.is_true(t["ready:blade_of_justice"])
    assert.is_true(t["talent:holy_flames"])
    assert.is_true(t["aura:expurgation:!"])
    -- One marker only. A second cue here would make it a general "press this" pointer.
    assert.equal(1, #entry("blade_of_justice").markers)
  end)

  -- The promotion must be the ONLY positive cue anywhere in the catalog: pass 1 says "press the
  -- positive cue" and says nothing about how two of them rank on one row.
  it("spends exactly one positive cue", function()
    local positives = {}
    for _, e in ipairs(cat.entries) do
      for _, m in ipairs(e.markers or {}) do
        if m.cue == "priority" or m.cue == "capped" then
          positives[#positives + 1] = e.id .. ":" .. m.id
        end
      end
    end
    assert.same({ "blade_of_justice:boj_opener" }, positives)
  end)
end)
