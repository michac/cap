-- Provisional product characterization: the Lightsmith roster's shape, not its gameplay value.
-- The definition is `specs/protection/catalog.md`; nothing here restates a rung or a source.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("product characterization / Protection", function()
  local ns, cat
  before_each(function()
    ns = H.fresh()
    cat = H.catalogBySpec(ns, 66)
  end)

  local function entry(id)
    for _, e in ipairs(cat.entries) do if e.id == id then return e end end
  end

  local function marker(id)
    for _, e in ipairs(cat.entries) do
      for _, m in ipairs(e.markers or {}) do if m.id == id then return m, e end end
    end
  end

  local function ability(id)
    for _, a in ipairs(cat.abilities) do if a.id == id then return a end end
  end

  --- Every ability keyed by id, which is the shape `Channel` binds a sealed display against.
  local function declared()
    local out = {}
    for _, a in ipairs(cat.abilities) do out[a.id] = a end
    return out
  end

  --- Terms of a marker as a comparable set, so a test names the fact rather than its position.
  local function terms(m)
    local out = {}
    for _, t in ipairs((m or {}).when or {}) do
      out[t[1] .. ":" .. tostring(t[2]) .. (t[3] and (":" .. tostring(t[3])) or "")
        .. (t.negate and ":!" or "")] = true
    end
    return out
  end

  --- The whole roster evaluated at once. There is no recorded Protection row set to bind
  --- against yet, so `resolved` is built by hand — cap's own structure, faking no client API.
  local function evaluate(world)
    local entries = {}
    for _, e in ipairs(cat.entries) do entries[#entries + 1] = { entry = e, row = {} } end
    return ns.Signal.Evaluate({ entries = entries }, world).byEntry
  end

  --- Does the composed row read as SKIP? The elimination walk passes over a row wearing a
  --- negative badge, so this is the drawn meaning of every hold below.
  local function skips(verdict)
    for _, key in ipairs(ns.Treatment.For(verdict).cues or {}) do
      if (ns.Style.cues[key] or {}).polarity ~= "positive" then return true end
    end
    return false
  end

  -- Every REGISTERED catalog is validated in `engine/catalog_spec.lua`, which is the loop that
  -- would have caught a malformed transcription without anyone running `Check` by hand.
  it("validates", function()
    assert.same({}, ns.Catalog.Check(cat))
    assert.equal(66, cat.spec)
  end)

  it("keeps the authored priority as the entry order", function()
    local order = {}
    for _, e in ipairs(cat.entries) do order[#order + 1] = e.id end
    assert.same({
      "avenging_wrath", "divine_toll", "shield_of_the_righteous", "holy_armaments",
      "avengers_shield", "consecration", "judgment", "crusader_strike", "word_of_glory",
    }, order)
  end)

  -- The load-bearing absence. Holy Power is never-secret, so declaring it would be legal — the
  -- priority simply contains no term that reads it, and a `resource` condition invented to match
  -- "Paladin ⇒ Holy Power" would be a rule the list does not have.
  it("declares no power type, so no row anywhere branches on a resource", function()
    assert.is_nil(cat.power)
    for _, e in ipairs(cat.entries) do
      for _, band in ipairs(e.bands or {}) do
        for _, t in ipairs(band.when or {}) do
          assert.not_equal("resource", t[1], e.id .. " branches on a resource")
        end
      end
      for _, m in ipairs(e.markers or {}) do
        for _, t in ipairs(m.when or {}) do
          assert.not_equal("resource", t[1], m.id .. " branches on a resource")
        end
      end
    end
  end)

  -- The Paladin hero sub-tree ids are unread, so `hero` is unset and `ForBuild`'s loose path
  -- claims any build on the spec. That is a named exposure rather than an oversight, and a
  -- Lightsmith id appearing here later should be a deliberate edit, not an accident.
  it("is unset on hero, and is therefore reached by any build on the spec", function()
    assert.is_nil(cat.hero)
    assert.equal(cat, ns.Catalog.ForBuild(66, nil))
    assert.equal(cat, ns.Catalog.ForBuild(66, 1))
  end)

  it("declares no bar and no charge row, so `capped` has no subject at all", function()
    assert.is_nil(cat.bar)
    for _, a in ipairs(cat.abilities) do
      assert.is_nil(a.charged, a.id .. " declares charges")
    end
    for _, e in ipairs(cat.entries) do
      for _, m in ipairs(e.markers or {}) do
        assert.not_equal("capped", m.cue, m.id .. " spends a cue with no subject")
      end
    end
  end)

  it("binds the armament row on its base id and gates the hold on the Bulwark identity",
    function()
      assert.equal(432459, ability("holy_armaments").spell)
      local m = marker("ha_banks_bulwark")
      assert.is_true(terms(m)["identity:holy_armaments:base"])
      -- Sacred Weapon reaches the row as an override, so its id must appear nowhere.
      for _, a in ipairs(cat.abilities) do
        assert.not_equal(432472, a.spell, a.id .. " hardcodes Sacred Weapon")
        for _, alt in ipairs(a.alt or {}) do
          assert.not_equal(432472, alt, a.id .. " hardcodes Sacred Weapon in alt")
        end
      end
    end)

  -- New to this catalog: one aura's count, read in OPPOSITE directions, from two different rows.
  -- Both tables are SEALED — cap hands the client a rule and never learns which band fired — so
  -- what is asserted is the authored table and the binding, and nothing about a value.
  it("runs one aura's count in both directions, from two different rows", function()
    local capped, cappedEntry = marker("as_guidance_capped")
    local awaits, awaitsEntry = marker("cons_awaits_hammer")
    assert.equal("avengers_shield", cappedEntry.id)
    assert.equal("consecration", awaitsEntry.id)

    -- Silent below five, ruled out at five: the ordinary sense.
    assert.equal("sealed-count-bands", capped.display.kind)
    assert.equal("none", capped.display.bands[1].draw)
    assert.equal(5, capped.display.bands[2].threshold)
    assert.equal("negative", capped.display.bands[2].polarity)
    assert.is_true(capped.display.bands[2].hatch)

    -- The complement, on the neighbouring row: ruled out BELOW five and clear at five.
    assert.equal("sealed-count-bands", awaits.display.kind)
    assert.equal("mark", awaits.display.bands[1].draw)
    assert.equal("negative", awaits.display.bands[1].polarity)
    assert.is_true(awaits.display.bands[1].hatch)
    assert.equal(5, awaits.display.bands[2].threshold)
    assert.equal("none", awaits.display.bands[2].draw)

    -- Two entries, ONE subject — and the plan resolves it through the same path the live armer
    -- takes, so a display naming a row it does not sit on is proven to bind.
    assert.equal("divine_guidance", capped.display.ability)
    assert.equal("divine_guidance", awaits.display.ability)
    for _, m in ipairs({ capped, awaits }) do
      local plan = ns.Channel.Plan(m, declared())
      assert.equal(433106, plan.spell)
      assert.equal("SetApplicationCount", plan.sink)
    end
  end)

  -- The `when`-beside-`display` shape: a readable gate licenses the paint and adds no badge.
  it("licenses both count tables with a readable gate that contributes no cue", function()
    for _, id in ipairs({ "as_guidance_capped", "cons_awaits_hammer" }) do
      local m = marker(id)
      assert.is_not_nil(m.when, id .. " has no gate")
      assert.is_not_nil(m.display, id .. " is not a sealed display")
      assert.is_nil(m.cue, id .. " adds a badge to a sealed table")
    end

    -- Hammer of Wrath armed, Glory of the Vanguard down, Divine Guidance talented: the one
    -- state both gates are open in.
    local out = evaluate(H.world{
      ready = H.map(true), aura = H.map(false),
      identity = H.map("base", { judgment = "transformed" }),
    })
    assert.is_true(out.avengers_shield.gates.as_guidance_capped)
    assert.is_true(out.consecration.gates.cons_awaits_hammer)
    -- …and the gate lands in `gates`, never in `markers`, and paints no badge.
    for _, id in ipairs(out.consecration.markers) do
      assert.not_equal("cons_awaits_hammer", id)
    end
    assert.same({}, out.consecration.cues)

    -- Glory of the Vanguard up closes the Avenger's Shield gate: rung 13 puts that row first, and
    -- the hatch would rule out the one state it is the press.
    local vanguard = evaluate(H.world{
      ready = H.map(true), aura = H.map(true),
      identity = H.map("base", { judgment = "transformed" }),
    })
    assert.is_false(vanguard.avengers_shield.gates.as_guidance_capped)
  end)

  -- The easiest thing in the catalog to invert, and inverting it draws a hold in exactly the
  -- states the priority presses.
  it("keeps each sealed range's sense the complement of the rung that fires", function()
    local seen = {}
    for _, id in ipairs({ "aw_awaits_toll", "dt_awaits_wrath", "ha_banks_bulwark" }) do
      local plan = ns.Channel.HoldPlan(marker(id))
      assert.equal("sealed-cooldown-range", plan.kind)
      assert.equal("blocked", plan.cue)
      seen[id] = plan.ability .. (plan.beyond and (" beyond " .. plan.beyond)
        or (" within " .. plan.within))
    end
    assert.same({
      aw_awaits_toll = "divine_toll beyond 10",
      dt_awaits_wrath = "avenging_wrath within 30",
      ha_banks_bulwark = "avenging_wrath beyond 5",
    }, seen)
  end)

  -- The catalog's one non-`blocked` cue, and the only thing said about the spender at all: its
  -- placement is pure position, so affordability is all that is left to draw.
  it("draws the spender starved only when it cannot be paid for", function()
    local broke = evaluate(H.world{
      ready = H.map(true), affordable = H.map(true, { shield_of_the_righteous = false }),
    }).shield_of_the_righteous
    assert.same({ "starved" }, broke.cues)
    assert.is_true(skips(broke))

    local rich = evaluate(H.world{ ready = H.map(true) }).shield_of_the_righteous
    assert.same({}, rich.cues)
    assert.is_false(skips(rich))

    -- A refused read must not tell the player they are broke on no evidence.
    local blind = evaluate(H.world{
      ready = H.map(true), affordable = H.map("unknown"),
    }).shield_of_the_righteous
    assert.same({}, blind.cues)
  end)

  it("draws the last row as a skip without its proc, and clean with it", function()
    local held = evaluate(H.world{ ready = H.map(true), aura = H.map(false) }).word_of_glory
    assert.same({ "wog_awaits_shining_light" }, held.markers)
    assert.same({ "blocked" }, held.cues)
    assert.is_true(skips(held))

    local free = evaluate(H.world{ ready = H.map(true), aura = H.map(true) }).word_of_glory
    assert.same({}, free.markers)
    assert.is_false(skips(free))
    assert.is_true(ns.Treatment.For(free).scan)
  end)

  it("keeps the yield off the base Judgment when the buff is up, and on it in its hammer life",
    function()
      local base = evaluate(H.world{ ready = H.map(true), aura = H.map(true) }).judgment
      assert.same({ "judgment_awaits_assurance" }, base.markers)
      assert.is_true(skips(base))

      -- Transformed, the row outranks both neighbours and must not stand itself down.
      local hammer = evaluate(H.world{
        ready = H.map(true), aura = H.map(true),
        identity = H.map("base", { judgment = "transformed" }),
      }).judgment
      assert.same({}, hammer.markers)
      assert.is_false(skips(hammer))
    end)

  -- `not unknown` is not `true`. Each of the three negations is a route by which a refused read
  -- could become a badge the player has no evidence for.
  it("withholds every negation on a refused read rather than badging", function()
    local blind = evaluate(H.blindWorld())
    for _, e in ipairs(cat.entries) do
      assert.same({}, blind[e.id].markers, e.id .. " invented a marker from a refused read")
      assert.same({}, blind[e.id].cues)
      assert.is_false(skips(blind[e.id]))
    end
    -- …and the two gated sealed tables refuse too: a blind gate licenses no paint.
    assert.is_false(blind.avengers_shield.gates.as_guidance_capped)
    assert.is_false(blind.consecration.gates.cons_awaits_hammer)

    -- One negation at a time, with everything else readable, so the withholding is the term's.
    local vanguard = evaluate(H.world{
      ready = H.map(true), aura = H.map("unknown"),
      identity = H.map("base", { judgment = "transformed" }),
    })
    assert.same({}, vanguard.avengers_shield.markers)

    local protector = evaluate(H.world{ ready = H.map(true), talent = H.map("unknown") })
    assert.same({}, protector.divine_toll.markers)

    local light = evaluate(H.world{ ready = H.map(true), aura = H.map("unknown") })
    assert.same({}, light.word_of_glory.markers)
  end)

  it("reaches both hammers through `alt`, because the choice node is not a transform", function()
    local cs = ability("crusader_strike")
    assert.equal(35395, cs.spell)
    assert.same({ 53595, 204019 }, cs.alt)
    -- Exactly one exists on a build and it is permanently on the row, so there is no identity
    -- band to draw and nothing to say about the filler.
    for _, band in ipairs(entry("crusader_strike").bands) do
      for _, t in ipairs(band.when or {}) do
        assert.not_equal("identity", t[1], "the filler bands on a distinction that never varies")
      end
    end
    assert.is_nil(entry("crusader_strike").markers)
  end)
end)
