-- Demonology.lua — the transcription of ../../../specs/demonology/catalog.md.
--
-- Which side wins depends on what they disagree ABOUT:
--   * what the client HAS — ids, rows, what is tracked: the running game wins over both
--     this table and the document, and the capture is how you ask it;
--   * what cap should DO — tiers, bands, windows, what we chose to be silent about:
--     the document wins, or the catalog drifts into a rotation engine one edit at a time.
-- Rationale and open questions live there; entry ids below are its own headings.
local ADDON, ns = ...

local C = ns.Catalog

local SHADOW_BOLT = 686
local WILD_IMP = 296553
local DOMINION_OF_ARGUS = 1276166
local DREADSTALKERS = 104316
local DEMONIC_CORE = 264173

C.Register{
  spec = 266,
  hero = 59,
  name = "Demonology / Diabolist",
  floor = SHADOW_BOLT,
  -- `Enum.PowerType` member name, resolved by Sense. Soul Shards are a SECONDARY
  -- resource, which is the whole reason this spec can use the graded register at all —
  -- a primary one is secret in a city and mid-pull alike.
  power = "SoulShards",

  -- The six of ../../../specs/demonology/catalog.md §2, and the cap is reached.
  -- Negation is legal here and in no band; `remaining` is cap's own arithmetic over the
  -- entry's declared `cd`, so tyrant_far degrades to holding Dreadstalkers a beat too
  -- long rather than to a false release.
  windows = {
    tyrant_setup = { { "ready", "E1" } },
    tyrant_far = { { "ready", "E1", negate = true }, { "remaining", "E1", ">", 20 } },
    tyrant_active = { { "elapsed", "E1", "<=", 15 } },
    dogs_out = { { "elapsed", "E2", "<=", 12 } },
    cores_dry = { { "proc", "E7", negate = true } },
    opener = { { "combat" }, { "casts", "==", 0 } },
  },

  entries = {
    {
      id = "E1", spell = 265187, family = "spells", bar = true, cd = 60,
      bands = {
        { tier = "HIGH", when = { { "ready", "this" }, { "window", "dogs_out" } } },
        { tier = "MEDIUM", when = { { "ready", "this" } } },
      },
      grade = { channel = "cooldownRemaining", of = "this" },
    },
    {
      id = "E2", spell = DREADSTALKERS, family = "spells", bar = true, cd = 20,
      bands = {
        { tier = "HIGH", when = { { "ready", "this" }, { "affordable", "this" }, { "window", "tyrant_setup" } } },
        { tier = "HIGH", when = { { "ready", "this" }, { "affordable", "this" }, { "window", "tyrant_far" } } },
        { tier = "MEDIUM", when = { { "ready", "this" }, { "affordable", "this" } } },
      },
      grade = { channel = "cooldownRemaining", of = "this" },
    },
    {
      id = "E3", spell = 1276452, family = "spells", bar = true, cd = 120,
      alt = { 1276467 },
      bands = {
        { tier = "HIGH", when = { { "ready", "this" }, { "window", "tyrant_setup" } } },
        { tier = "MEDIUM", when = { { "ready", "this" } } },
      },
    },
    {
      id = "E4", spell = 1276672, family = "spells", bar = true, cd = 120,
      bands = {
        { tier = "HIGH", when = { { "ready", "this" }, { "window", "tyrant_setup" } } },
        { tier = "MEDIUM", when = { { "ready", "this" } } },
      },
    },
    {
      id = "E5", spell = 105174, family = "spells",
      bands = {
        { tier = "HIGH", when = { { "auraUp", DOMINION_OF_ARGUS }, { "affordable", "this" } } },
        { tier = "HIGH", when = { { "window", "tyrant_active" }, { "affordable", "this" } } },
        { tier = "HIGH", when = { { "resource", ">=", 5 }, { "affordable", "this" } } },
        { tier = "MEDIUM", when = { { "affordable", "this" } } },
      },
      grade = { channel = "resource", direction = "rising" },
    },
    {
      id = "E6", spell = 105174, family = "spells",
      bands = {
        { tier = "HIGH", when = { { "identity", "this", "transformed" } } },
      },
    },
    {
      id = "E7", spell = 264178, family = "spells",
      bands = {
        { tier = "MEDIUM", when = { { "proc", "this" }, { "resource", "<=", 3 } } },
        { tier = "LOW", when = { { "proc", "this" } } },
      },
      grade = { channel = "resource", direction = "falling" },
      cue = {
        tier = "HIGH",
        gate = { { "proc", "this" } },
        threshold = { channel = "stacks", of = DEMONIC_CORE, min = 4 },
      },
    },
    {
      id = "E8", spell = 196277, family = "spells", cd = 15,
      bands = {
        { tier = "MEDIUM", when = { { "ready", "this" } } },
      },
      cue = {
        tier = "HIGH",
        gate = { { "ready", "this" } },
        threshold = { channel = "stacks", of = WILD_IMP, min = 6 },
      },
    },
    {
      id = "E9", spell = 264130, family = "spells", cd = 30,
      bands = {
        { tier = "MEDIUM", when = { { "ready", "this" }, { "window", "cores_dry" } } },
        { tier = "LOW", when = { { "ready", "this" } } },
      },
    },
    {
      id = "E10", spell = SHADOW_BOLT, family = "spells",
      bands = {
        { tier = "LOW", when = {} },
      },
    },
  },

  silences = {
    { spell = DEMONIC_CORE, why = "a proc, not a press — feeds E7's band, E7's cue and cores_dry" },
    { spell = WILD_IMP, why = "a count, not a press — feeds E8's cue" },
    { spell = DREADSTALKERS, family = "auras", why = "the pets' own bar; a summon binds no aura, so nothing reads it" },
    { spell = 428514, why = "a progress container; its payoff is Ruination, which E6 grades" },
    { spell = DOMINION_OF_ARGUS, why = "feeds E5 as a buff" },
    { spell = 104773, why = "defensive — cap has no read on incoming damage" },
    { spell = 108416, why = "defensive — cap has no read on incoming damage" },
    { spell = 30283, why = "situational CC; the trigger is the fight, not the rotation" },
    { spell = 6789, why = "situational CC; the trigger is the fight, not the rotation" },
    { spell = 1271802, why = "situational; the trigger is the fight, not the rotation" },
    { spell = 119898, why = "situational; the trigger is the fight, not the rotation" },
    { spell = 48020, why = "movement" },
    { spell = 30146, why = "pre-pull" },
    { spell = 460551, why = "passive — applied by Demonbolt, not pressed" },
  },

  bars = { "E1", "E2", "E3", "E4" },
}
