-- The pure half of Talents.lua, plus the two predicates it and Mode feed into Signal.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("engine / talents", function()
  local ns
  before_each(function()
    ns = H.fresh()
  end)

  --- The shape `C_Traits.GetNodeInfo` is expected to return, built by hand so no test ever
  --- depends on the client answering. The shape itself is `[gap]` — unmeasured — which is why
  --- every unrecognised variant below must degrade to nil rather than to false.
  local function node(ranks, entryID)
    return { ranksPurchased = ranks, activeEntry = entryID and { entryID = entryID } or nil }
  end

  it("reads a purchased node whose active entry is the declared one as TAKEN", function()
    assert.is_true(ns.Talents.Selected(node(1, 117741), 117741))
  end)

  it("reads an unpurchased node as NOT taken", function()
    assert.is_false(ns.Talents.Selected(node(0, nil), 117741))
  end)

  it("reads a choice node resolved the other way as NOT taken", function()
    -- A purchased choice node has ranks either way; only the active entry says which half.
    assert.is_false(ns.Talents.Selected(node(1, 999999), 117741))
  end)

  it("refuses rather than guessing on every shape it does not recognise", function()
    -- The single most important property here: an unmeasured read must never become "not
    -- taken". Not-taken is an assertion; nil is the absence of one.
    for _, info in ipairs({
      { what = "nil", value = nil },
      { what = "not a table", value = 7 },
      { what = "no ranks", value = { activeEntry = { entryID = 117741 } } },
      { what = "ranks not numeric", value = node("1", 117741) },
      { what = "purchased with no active entry", value = node(1, nil) },
      { what = "active entry with no id", value = { ranksPurchased = 1, activeEntry = {} } },
    }) do
      assert.is_nil(ns.Talents.Selected(info.value, 117741), info.what)
    end
    assert.is_nil(ns.Talents.Selected(node(1, 117741), nil), "no declared entry id")
  end)

  it("folds the catalog's declared talents through one reader", function()
    local declared = {
      { id = "taken", node = 10, entry = 100 },
      { id = "not_taken", node = 20, entry = 200 },
      { id = "silent", node = 30, entry = 300 },
    }
    local infos = { [10] = node(1, 100), [20] = node(0, nil) }
    local out = ns.Talents.Reduce(declared, function(id) return infos[id] end)
    assert.is_true(out.taken)
    assert.is_false(out.not_taken)
    assert.is_nil(out.silent, "an absent node is unknown, not absent-therefore-untalented")
  end)

  it("survives a reader that errors, and reports nothing rather than false", function()
    local out = ns.Talents.Reduce({ { id = "x", node = 1, entry = 2 } }, function()
      error("restricted")
    end)
    assert.is_nil(out.x)
  end)

  it("returns an empty fold when the client will not supply a reader at all", function()
    assert.same({}, ns.Talents.Reduce({ { id = "x", node = 1, entry = 2 } }, nil))
  end)
end)

describe("engine / the inverted sealed band", function()
  local ns
  before_each(function()
    ns = H.fresh()
  end)

  it("says FAR with two points, because Step holds the last value out to infinity", function()
    -- `within` is a window and needs three points to close again; `beyond` never closes, so the
    -- rise at the threshold IS the whole curve. Same mechanism, one point fewer.
    assert.same({ { 0, 0 }, { 10, 1 } }, ns.Channel.BeyondPoints(10))
    assert.same({ { 0, 0 }, { 0.001, 1 }, { 10, 0 } }, ns.Channel.HoldPoints(10))
  end)

  it("still reads nothing at zero remaining, which is the property that matters", function()
    -- A dependency that is READY is not far away. The one shape this must never take is a badge
    -- that lights on a cooldown which has come back, and the leading {0,0} is what prevents it.
    local points = ns.Channel.BeyondPoints(10)
    assert.same({ 0, 0 }, points[1])
  end)

  it("refuses a threshold that is not a positive number", function()
    for _, bad in ipairs{ 0, -1, "10" } do
      assert.is_nil(ns.Channel.BeyondPoints(bad), tostring(bad))
    end
    assert.is_nil(ns.Channel.BeyondPoints(nil))
  end)

  it("plans exactly one sense per marker", function()
    local function plan(display)
      return ns.Channel.HoldPlan({ id = "m", cue = "blocked", display = display })
    end
    local base = { kind = "sealed-cooldown-range", ability = "eye_beam" }
    assert.equal(10, plan{ kind = base.kind, ability = base.ability, beyond = 10 }.beyond)
    assert.is_nil(plan{ kind = base.kind, ability = base.ability, beyond = 10 }.within)
    assert.equal(4, plan{ kind = base.kind, ability = base.ability, within = 4 }.within)
    -- Two senses would be two curves on one badge.
    assert.is_nil(plan{ kind = base.kind, ability = base.ability, within = 4, beyond = 10 })
    assert.is_nil(plan{ kind = base.kind, ability = base.ability })
  end)
end)

describe("engine / the talent and aoe predicates", function()
  local ns
  before_each(function()
    ns = H.fresh()
  end)

  local function term(t, world)
    return ns.Signal.Term(t, world)
  end

  it("evaluates talent off the world's talent map, unknown-safely", function()
    assert.is_true(term({ "talent", "a" }, { talent = { a = true } }))
    assert.is_false(term({ "talent", "a" }, { talent = { a = false } }))
    assert.equal("unknown", term({ "talent", "a" }, { talent = {} }))
    assert.equal("unknown", term({ "talent", "a" }, {}))
    -- Negation of an unknown stays unknown; `not unknown` is not `true`.
    assert.equal("unknown", term({ "talent", "a", negate = true }, {}))
  end)

  it("evaluates aoe off cap's own toggle, with no subject", function()
    assert.is_true(term({ "aoe" }, { aoe = true }))
    assert.is_false(term({ "aoe" }, { aoe = false }))
    assert.is_true(term({ "aoe", negate = true }, { aoe = false }))
    -- cap owns this value, so it is never unknown in the client — but the engine must not
    -- assume that of a world it was handed.
    assert.equal("unknown", term({ "aoe" }, {}))
  end)

  it("labels an aoe term without a phantom subject", function()
    local _, parts = ns.Signal.Explain({ { "aoe", negate = true } }, { aoe = false })
    assert.same({ "!aoe=T" }, parts)
  end)

  it("carries talent and aoe into the world without touching the charge ledger", function()
    local track = ns.Track.New()
    track:Bind(ns.Track.Binding({ abilities = {}, entries = {} }, ns.Catalog.Reads(
      H.catalogBySpec(ns, 577))))
    local world = track:World(0, {
      talent = { a_fire_inside = true }, needsTalent = { "a_fire_inside" },
      aoe = false, needsAoE = true, needsResource = false,
    })
    assert.is_true(world.talent.a_fire_inside)
    assert.is_false(world.aoe)
    assert.is_nil(world.chargeProvenance.a_fire_inside)
  end)

  it("tallies the two predicates only when the catalog asks for them", function()
    local track = ns.Track.New()
    track:Bind(ns.Track.Binding({ abilities = {}, entries = {} }, ns.Catalog.Reads(
      H.catalogBySpec(ns, 577))))
    local _, health = track:World(0, {
      talent = { a_fire_inside = "unknown" }, needsTalent = { "a_fire_inside" },
      aoe = true, needsAoE = true, needsResource = false,
    })
    assert.same({ known = 0, unknown = 1 }, health.predicates.talent)
    assert.same({ known = 1, unknown = 0 }, health.predicates.aoe)

    local _, quiet = track:World(0, { needsResource = false })
    assert.is_nil(quiet.predicates.talent, "a spec naming no talent must not report one")
    assert.is_nil(quiet.predicates.aoe)
  end)
end)
