-- Provisional product characterization: the Diabolist roster's shape, not its gameplay value.
-- The definition is `specs/demonology/catalog.md`; nothing here restates a rung or a source.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("product characterization / Demonology", function()
  local ns, cat, resolved
  before_each(function()
    ns = H.fresh()
    cat = H.catalogBySpec(ns, 266)
    resolved = ns.Catalog.Resolve(cat, H.rows())
  end)

  local function marker(id)
    for _, e in ipairs(cat.entries) do
      for _, m in ipairs(e.markers or {}) do if m.id == id then return m end end
    end
  end

  --- Does the composed row read as SKIP? The elimination walk passes over a row wearing a
  --- negative badge, so this is the drawn meaning of every hold below.
  local function skips(verdict)
    for _, key in ipairs(ns.Treatment.For(verdict).cues or {}) do
      if (ns.Style.cues[key] or {}).polarity ~= "positive" then return true end
    end
    return false
  end

  it("is Diabolist specifically, and validates", function()
    assert.same({}, ns.Catalog.Check(cat))
    assert.equal(59, cat.hero)
    -- Soul Harvester is a separate catalog; a loose spec-only match would wrongly claim it.
    assert.is_nil(ns.Catalog.ForBuild(266, 60))
    assert.equal(cat, ns.Catalog.ForBuild(266, 59))
  end)

  it("keeps the authored priority as the entry order", function()
    local order = {}
    for _, e in ipairs(cat.entries) do order[#order + 1] = e.id end
    assert.same({
      "power_siphon", "grimoire", "summon_doomguard", "call_dreadstalkers",
      "summon_demonic_tyrant", "implosion", "hand_of_guldan", "demonbolt", "shadow_bolt",
    }, order)
  end)

  -- Soul Shards are one of the seven NEVER-SECRET power types, which is why the largest
  -- decision in the spec is an exact comparison rather than a curve. `resource` takes only
  -- `<=` and `>=`, so the APL's `soul_shard=5` is authored as "at or below four".
  it("holds Tyrant on readable shards, and only while it is actually up", function()
    local ready = H.world{ ready = H.map(true), resource = 3 }
    local out = ns.Signal.Evaluate(resolved, ready).byEntry.summon_demonic_tyrant
    assert.is_true(skips(out))
    assert.same({ "tyrant_awaits_shards" }, out.markers)

    local capped = ns.Signal.Evaluate(resolved,
      H.world{ ready = H.map(true), resource = 5 }).byEntry.summon_demonic_tyrant
    assert.is_false(skips(capped))

    -- A hold badge on a greyed icon says nothing, hence the readiness gate.
    local down = ns.Signal.Evaluate(resolved,
      H.world{ ready = H.map(true, { summon_demonic_tyrant = false }), resource = 3 })
    assert.same({}, down.byEntry.summon_demonic_tyrant.markers)
  end)

  -- The pilot said three and three was wrong: the APL's term is `soul_shard<4`, so a Core spent
  -- at three leaves exactly five, which is full and not waste.
  it("lights Demonbolt's overcap at four shards and not at three", function()
    local function db(shards)
      return ns.Signal.Evaluate(resolved,
        H.world{ ready = H.map(true), proc = H.map(true), resource = shards,
                 identity = H.map("base") }).byEntry.demonbolt
    end
    assert.same({ "db_overcap" }, db(4).markers)
    assert.same({}, db(3).markers)
  end)

  -- Demonbolt appears in the list ONLY gated on a Demonic Core, so with no Core there is no
  -- rung at all. This is also render-shelf V11's hatch at zero Cores: the one state a sealed
  -- display can never decorate, because with no aura there is no button — and it needs no new
  -- vocabulary, because a negative cue already hatches the row.
  it("stands Demonbolt down with no Core, through the readable proc and not through a count",
    function()
      local out = ns.Signal.Evaluate(resolved,
        H.world{ ready = H.map(true), proc = H.map(false), resource = 1,
                 identity = H.map("base") }).byEntry.demonbolt
      assert.same({ "db_awaits_core" }, out.markers)
      assert.is_true(skips(out))
      -- ⚠ And an unknown must not become confidence through the negation: a refused `proc`
      -- leaves the row unbadged rather than held.
      local blind = ns.Signal.Evaluate(resolved, H.blindWorld()).byEntry.demonbolt
      assert.same({}, blind.markers)
    end)

  it("reads ANOTHER row's identity to yield to an armed Infernal Bolt", function()
    local function db(shards, form)
      return ns.Signal.Evaluate(resolved,
        H.world{ ready = H.map(true), proc = H.map(true), resource = shards,
                 identity = H.map("base", { shadow_bolt = form }) }).byEntry.demonbolt
    end
    assert.is_truthy(db(2, "transformed").markers[1])
    assert.same({}, db(2, "base").markers)
    -- Rung 12 puts Infernal Bolt above Demonbolt only BELOW three shards.
    assert.same({}, db(3, "transformed").markers)
  end)

  it("keeps row 9 in the scan under either identity — the KIND is the icon's to say", function()
    -- Accepted behavior change (2026-08-25): the old identity/ready band pair both yielded
    -- membership, so shadow_bolt dropped to default ready-self. A filler is always a scan
    -- candidate, and an unknown identity no longer darkens it.
    local function sb(form)
      return ns.Signal.Evaluate(resolved,
        H.world{ ready = H.map(true), identity = H.map("base", { shadow_bolt = form }) })
        .byEntry.shadow_bolt
    end
    assert.is_true(sb("transformed").member)
    assert.is_true(sb("base").member)
    assert.is_nil((function()
      for _, e in ipairs(cat.entries) do
        if e.id == "shadow_bolt" then return e.scan_when end
      end
    end)(), "shadow_bolt declares a scan_when it does not need")
  end)

  -- render-shelf V16/V17. Both counts are SEALED: cap hands the client a rule and never learns
  -- which band fired, so what is asserted here is the authored table and nothing else.
  it("puts both stack counts on the client, and both polarities on Implosion's numeral", function()
    local imps = marker("implosion_imps_short").display
    assert.equal("sealed-count-bands", imps.kind)
    assert.equal("wild_imp", imps.ability)
    -- ⚠ TWO POLARITIES, one numeral: below six the count is red with the hatch (Implosion is
    -- literally a damage loss — the first sealed fact in any catalog to enter elimination),
    -- and at six it RECOLORS gold instead of clearing (2026-08-25): banked, the press is
    -- loaded. A positive band may not hatch, and hue alone carries the verdict.
    assert.is_true(imps.bands[1].hatch)
    assert.equal("negative", imps.bands[1].polarity)
    assert.equal(6, imps.bands[2].threshold)
    assert.equal("count", imps.bands[2].draw)
    assert.equal("positive", imps.bands[2].polarity)
    assert.is_nil(imps.bands[2].hatch)

    -- Power Siphon runs the ordinary direction: silent while the row is a candidate, ruled out
    -- at two Cores, which is `buff.demonic_core.stack<=1` read as a hold.
    local cores = marker("ps_cores_banked").display
    assert.equal("none", cores.bands[1].draw)
    assert.equal(2, cores.bands[2].threshold)
    assert.is_true(cores.bands[2].hatch)
  end)

  it("gates the pandemic window on the talent that makes its fact exist", function()
    local doom = marker("db_doom_window")
    assert.equal("sealed-pandemic", doom.display.kind)
    assert.same({ { "talent", "doom" } }, doom.when)
    -- A gate never contributes a cue: it only decides whether the client may paint the sealed
    -- display at all, which is why it lands in `gates` and not in `markers`.
    local on = ns.Signal.Evaluate(resolved,
      H.world{ ready = H.map(true), talent = H.map(true) }).byEntry.demonbolt
    assert.is_true(on.gates.db_doom_window)
    local off = ns.Signal.Evaluate(resolved,
      H.world{ ready = H.map(true), talent = H.map(false) }).byEntry.demonbolt
    assert.is_false(off.gates.db_doom_window)
    for _, id in ipairs(on.markers) do
      assert.not_equal("db_doom_window", id)
    end
  end)

  it("declares no bar and no charge spell, because nothing in the set has either", function()
    assert.is_nil(cat.bar)
    for _, ability in ipairs(cat.abilities) do
      assert.is_nil(ability.charged, ability.id .. " declares charges")
    end
    -- …so this catalog spends no `capped` cue: there is nothing to cap.
    for _, e in ipairs(cat.entries) do
      for _, m in ipairs(e.markers or {}) do
        assert.not_equal("capped", m.cue)
      end
    end
  end)

  it("binds on base spell ids only, leaving both transforms to the row union", function()
    for _, ability in ipairs(cat.abilities) do
      assert.not_equal(433885, ability.spell, "Ruination is hardcoded")
      assert.not_equal(433891, ability.spell, "Infernal Bolt is hardcoded")
    end
  end)
end)
