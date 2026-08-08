-- track_spec.lua — the readiness latch and the elapsed stamp, authored from the
-- Demonology catalog document rather than from Track.lua.
--
-- The three-state blocks are the ones that carry their weight. A latch that reads
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

  describe("elapsed", function()
    it("has none for an ability never observed", function()
      assert.is_nil(world().elapsed.E1)
    end)

    it("counts from the OnCooldown edge", function()
      track:Edge(100, cid("E1"), "OnCooldown")
      assert.equal(12, world(112).elapsed.E1)
    end)

    it("counts no cooldown down — the client owns every remaining time", function()
      -- The declared base cooldown, and the arithmetic over it, are gone: a channel is
      -- exact where cap's own count drifts under anything that shortens a cooldown.
      track:Edge(100, cid("E1"), "OnCooldown")
      assert.is_nil(world(110).remaining)
    end)
  end)

  describe("combat", function()
    it("rides the world as a gate, answered rather than refused", function()
      assert.is_false(world().combat)
      track:Combat(100, true)
      assert.is_true(world(101).combat)
      track:Combat(200, false)
      assert.is_false(world(201).combat)
    end)
  end)

  describe("casts", function()
    -- Nothing reads this yet: it is the counter behind `casts == n`, which is legal in a
    -- sequence trigger and refused in a band, so M5 is its first consumer.
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
  -- The world feeds Tier, and gate health is what a flight reads
  --------------------------------------------------------------------------------
  describe("the world Tier consumes", function()
    it("promotes Tyrant to HIGH once the Dreadstalkers are on cooldown and it is ready", function()
      track:Edge(100, cid("E2"), "OnCooldown")
      track:Edge(101, cid("E1"), "Available")
      local out = ns.Tier.Evaluate(resolved, world(105))
      assert.equal("HIGH", out.byEntry.E1.tier)
    end)

    it("leaves Tyrant at MEDIUM once the Dreadstalkers are back up", function()
      track:Edge(100, cid("E2"), "OnCooldown")
      track:Edge(101, cid("E1"), "Available")
      track:Edge(120, cid("E2"), "Available")
      local out = ns.Tier.Evaluate(resolved, world(125))
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

    it("tallies a gate against the SUBJECT entry, not the one that named it", function()
      -- Bound WITH the reads map. Nothing asks E1's affordability and nothing asks E5's
      -- readiness, so a tally that counted every gate for every entry would report a
      -- working catalog as blind — the failure this measurement exists to detect.
      local t = ns.Track.New()
      t:Bind(ns.Track.Binding(resolved, H.rows(), ns.Catalog.Reads(cat)))
      local _, health = t:World(100)
      assert.equal(2, health.gates.identity.known + health.gates.identity.unknown)
      assert.equal(2, health.gates.affordable.known + health.gates.affordable.unknown)
      assert.is_true(health.gates.ready.known + health.gates.ready.unknown < health.entries)
    end)

    it("counts E2's readiness, which only E1's band asks for", function()
      local t = ns.Track.New()
      t:Bind(ns.Track.Binding(resolved, H.rows(), ns.Catalog.Reads(cat)))
      assert.is_true(t.entries.E2.needs.ready, "E1 names `not ready(E2)`")
      assert.is_nil(t.entries.E1.needs.affordable, "nothing asks E1's affordability")
    end)

    it("separates a false read from a refused one", function()
      local _, answered = world(100, { proc = H.map(false) })
      local _, blind = world(100, { proc = H.map("unknown") })
      assert.equal(0, answered.gates.proc.unknown)
      assert.equal(0, blind.gates.proc.known)
    end)
  end)
end)
