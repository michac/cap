-- track_spec.lua — the readiness latch, the elapsed arithmetic and the six windows,
-- authored from the Demonology catalog document §2 rather than from Track.lua.
--
-- The two blocks that carry their weight are the three-state ones. A latch that reads
-- `false` where it means "nobody told me" lights or blanks a whole roster for a pull,
-- and both failures look like a working addon from the outside.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("Track", function()
  local ns, track, cat, resolved

  before_each(function()
    ns = H.fresh()
    track, cat, resolved = H.track(ns)
  end)

  local function cid(id) return H.cid(resolved, id) end
  local function world(now, reads) return track:World(now or 100, reads) end

  describe("the binding", function()
    it("keys the entries that survived, and only those", function()
      assert.is_table(track.entries.E1)
      assert.is_nil(track.entries.E4, "Doomguard has no row on this build and must not bind")
      assert.is_nil(track.entries.E9, "Power Siphon is the untalented half of its choice node")
    end)

    it("puts the two entries sharing one row on the same cooldownID", function()
      assert.equal(track.entries.E5.cid, track.entries.E6.cid)
    end)

    it("collects aura ids from the aura families only", function()
      local b = ns.Track.Binding(resolved, H.rows())
      assert.same({ 1276166 }, b.auraIDs[169561])
      assert.is_nil(b.auraIDs[34990], "Shadow Bolt is a spell row and binds no aura")
    end)

    it("drops an aura row no band names, so it neither latches nor tallies", function()
      local b = ns.Track.Binding(resolved, H.rows(), ns.Catalog.Reads(cat))
      -- Dominion of Argus is E5's `auraUp` source and is the only aura the catalog
      -- names. Unending Resolve's bar is tracked by the CDM and silenced by us.
      assert.same({ 1276166 }, b.auraIDs[169561])
      assert.is_nil(b.auraIDs[84183], "an aura row nothing reads must not be bound at all")
      local n = 0
      for _ in pairs(b.auraIDs) do n = n + 1 end
      assert.equal(1, n)
    end)
  end)

  describe("readiness is three-state", function()
    it("starts unknown — nothing observed is not 'not ready'", function()
      assert.equal("unknown", world().ready.E1)
    end)

    it("latches ready on the Available edge", function()
      track:Edge(10, cid("E1"), "Available")
      assert.is_true(world().ready.E1)
    end)

    it("latches not-ready on the OnCooldown edge", function()
      track:Edge(10, cid("E1"), "Available")
      track:Edge(20, cid("E1"), "OnCooldown")
      assert.is_false(world().ready.E1)
    end)

    it("moves both entries that share a row", function()
      track:Edge(10, cid("E5"), "Available")
      local w = world()
      assert.is_true(w.ready.E5)
      assert.is_true(w.ready.E6)
    end)

    it("ignores an edge on a row nothing bound", function()
      assert.is_false(track:Edge(10, 999999, "Available"))
    end)

    it("ignores the alert types that say nothing about readiness", function()
      track:Edge(10, cid("E1"), "Available")
      assert.is_false(track:Edge(20, cid("E1"), "PandemicTime"))
      assert.is_true(world().ready.E1)
    end)

    it("refuses to latch an ability with more than one charge", function()
      -- Nothing on Demonology has charges, so this never fires there — but an Available
      -- edge on a charge ability means "a charge came back", not "the ability is ready".
      track:SeedCharges("E1", 2)
      track:Edge(10, cid("E1"), "Available")
      assert.equal("unknown", world().ready.E1)
    end)

    it("forgets everything on a rebind — item frames are pooled", function()
      track:Edge(10, cid("E1"), "Available")
      track:Bind(ns.Track.Binding(resolved, H.rows()))
      assert.equal("unknown", world().ready.E1)
    end)

    it("takes an out-of-combat baseline, and nil leaves it unknown", function()
      track:SeedReady(cid("E1"), true)
      track:SeedReady(cid("E2"), nil)
      local w = world()
      assert.is_true(w.ready.E1)
      assert.equal("unknown", w.ready.E2)
    end)
  end)

  describe("aura presence", function()
    it("is unknown until an edge or a seed says otherwise", function()
      assert.is_nil(world().auraUp[1276166])
    end)

    it("latches from the aura edges, keyed by the aura's own spell id", function()
      track:Edge(10, 169561, "OnAuraApplied")
      assert.is_true(world().auraUp[1276166])
      track:Edge(20, 169561, "OnAuraRemoved")
      assert.is_false(world().auraUp[1276166])
    end)
  end)

  describe("elapsed and remaining", function()
    it("has no elapsed for an ability never observed", function()
      assert.is_nil(world().elapsed.E1)
    end)

    it("counts from the OnCooldown edge", function()
      track:Edge(100, cid("E1"), "OnCooldown")
      assert.equal(12, world(112).elapsed.E1)
    end)

    it("counts the declared base cooldown down, and floors at zero", function()
      track:Edge(100, cid("E1"), "OnCooldown")
      assert.equal(50, world(110).remaining.E1)
      assert.equal(0, world(200).remaining.E1)
    end)

    it("takes a measured base cooldown over the declared one", function()
      track:SeedCooldown("E1", 45)
      track:Edge(100, cid("E1"), "OnCooldown")
      assert.equal(35, world(110).remaining.E1)
    end)

    it("has no remaining for an entry the catalog declares no cooldown for", function()
      track:Cast(100, cid("E5"))
      assert.equal(10, world(110).elapsed.E5)
      assert.is_nil(world(110).remaining.E5)
    end)
  end)

  describe("casts", function()
    it("counts only inside a pull, and resets at each combat entry", function()
      track:Cast(5, cid("E10"))
      track:Combat(10, true)
      assert.equal(0, track.casts)
      track:Cast(11, cid("E10"))
      assert.equal(1, track.casts)
      track:Combat(20, true)
      assert.equal(0, track.casts)
    end)

    it("does not count the OnCooldown edge, which would double-count every cooldown", function()
      track:Combat(10, true)
      track:Cast(11, cid("E1"))
      track:Edge(11, cid("E1"), "OnCooldown")
      assert.equal(1, track.casts)
    end)

    it("ignores a cast of something the catalog does not track", function()
      track:Combat(10, true)
      assert.is_false(track:Cast(11, 999999))
      assert.equal(0, track.casts)
    end)
  end)

  --------------------------------------------------------------------------------
  -- The six windows — catalog.md §2, one case each plus its refusal
  --------------------------------------------------------------------------------
  local covered = {}

  local function windowCase(name, desc, fn)
    covered[name] = true
    it(name .. " " .. desc, fn)
  end

  describe("windows", function()
    windowCase("tyrant_setup", "is exactly 'Tyrant is ready'", function()
      track:Edge(10, cid("E1"), "Available")
      assert.is_true(world().window.tyrant_setup)
      track:Edge(20, cid("E1"), "OnCooldown")
      assert.is_false(world().window.tyrant_setup)
    end)

    windowCase("tyrant_far", "needs not-ready AND more than 20s left", function()
      track:Edge(100, cid("E1"), "OnCooldown")
      assert.is_true(world(110).window.tyrant_far, "50s left is far")
      assert.is_false(world(145).window.tyrant_far, "15s left is the hold zone, not far")
    end)

    it("leaves the hold zone expressed by NEITHER tyrant window, so no band says 'not'", function()
      track:Edge(100, cid("E1"), "OnCooldown")
      local w = world(145)
      assert.is_false(w.window.tyrant_setup)
      assert.is_false(w.window.tyrant_far)
    end)

    windowCase("tyrant_active", "is ~15s from the observed cast", function()
      track:Edge(100, cid("E1"), "OnCooldown")
      assert.is_true(world(112).window.tyrant_active)
      assert.is_false(world(120).window.tyrant_active)
    end)

    windowCase("dogs_out", "is ~12s from the observed Dreadstalkers cast", function()
      track:Edge(100, cid("E2"), "OnCooldown")
      assert.is_true(world(108).window.dogs_out)
      assert.is_false(world(115).window.dogs_out)
    end)

    windowCase("cores_dry", "is the negation of the Demonbolt proc, legal only here", function()
      assert.is_true(world(100, { proc = H.map(false) }).window.cores_dry)
      assert.is_false(world(100, { proc = H.map(true) }).window.cores_dry)
    end)

    windowCase("opener", "is in combat before the first observed cast", function()
      -- False rather than unknown, and the order is why: `combat` answers definitively,
      -- and a term known false settles the window whatever the rest of it refuses.
      assert.is_false(world(100).window.opener)
      track:Combat(100, true)
      assert.is_true(world(101).window.opener)
      track:Cast(102, cid("E10"))
      assert.is_false(world(103).window.opener)
    end)

    it("is unknown, never false, when the read it rests on refused", function()
      -- E1's readiness never seeded: tyrant_setup must not read as "Tyrant is not ready".
      assert.equal("unknown", world().window.tyrant_setup)
      assert.equal("unknown", world().window.tyrant_far)
    end)

    it("negation of a refusal stays a refusal", function()
      assert.equal("unknown", world(100, { proc = H.map("unknown") }).window.cores_dry)
    end)

    it("has a case for every window the catalog declares", function()
      local missing = {}
      for name in pairs(cat.windows) do
        if not covered[name] then missing[#missing + 1] = name end
      end
      table.sort(missing)
      assert.same({}, missing)
    end)
  end)

  --------------------------------------------------------------------------------
  -- The world feeds Tier, and gate health is what a flight reads
  --------------------------------------------------------------------------------
  describe("the world Tier consumes", function()
    it("promotes Tyrant to HIGH once the dogs are out and it is ready", function()
      track:Edge(100, cid("E2"), "OnCooldown")
      track:Edge(101, cid("E1"), "Available")
      local out = ns.Tier.Evaluate(resolved, world(105))
      assert.equal("HIGH", out.byEntry.E1.tier)
    end)

    it("leaves Tyrant at MEDIUM once the window has closed", function()
      track:Edge(100, cid("E2"), "OnCooldown")
      track:Edge(101, cid("E1"), "Available")
      local out = ns.Tier.Evaluate(resolved, world(120))
      assert.equal("MEDIUM", out.byEntry.E1.tier)
    end)

    it("gives nothing but the floor a tier while every gate is unseeded", function()
      local out = ns.Tier.Evaluate(resolved, world())
      for id, v in pairs(out.byEntry) do
        if id ~= "E10" then assert.is_nil(v.tier, id .. " took a tier from an unseeded world") end
      end
    end)
  end)

  describe("gate health", function()
    it("reports every entry blind before anything is observed", function()
      local _, health = world()
      assert.equal(0, health.gates.ready.known)
      assert.is_true(health.gates.ready.unknown > 0)
    end)

    it("moves a gate from unknown to known as the edges land", function()
      for id in pairs(track.entries) do track:SeedReady(track.entries[id].cid, false) end
      local _, health = world()
      assert.equal(0, health.gates.ready.unknown)
    end)

    it("counts a window that could not be evaluated", function()
      local _, health = world()
      assert.is_true(health.windows.unknown > 0)
      assert.equal(6, health.windows.known + health.windows.unknown)
    end)

    it("counts only the gates the catalog asks of each entry", function()
      -- Bound WITH the reads map: one entry names `identity`, so a blind identity read
      -- is 1 refusal and not 8. Counting a gate nobody asks for reports a working
      -- catalog as blind, which is the failure this measurement exists to detect.
      local rows = H.rows()
      local t = ns.Track.New(cat)
      t:Bind(ns.Track.Binding(resolved, rows, ns.Catalog.Reads(cat)))
      local _, health = t:World(100)
      local ident = health.gates.identity
      assert.equal(1, ident.known + ident.unknown)
      assert.is_true(health.gates.ready.known + health.gates.ready.unknown < health.entries)
    end)

    it("separates a false read from a refused one", function()
      local _, answered = world(100, { proc = H.map(false) })
      local _, blind = world(100, { proc = H.map("unknown") })
      assert.equal(0, answered.gates.proc.unknown)
      assert.equal(0, blind.gates.proc.known)
    end)
  end)
end)
