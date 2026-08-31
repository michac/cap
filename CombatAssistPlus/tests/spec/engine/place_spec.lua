-- Place.lua's store: the keyed saved position, WHICH SAVED TABLE it lives in, and the
-- one-time read of the two account-wide shapes that came before it. Drag, chrome and the
-- frames themselves are client behaviour (house rule 6).
--
-- ⚠ The rule these mostly protect: placement is PER-CHARACTER (`ns.cdb`), and a SEEDED
-- position does not carry its `placed` flag across characters. An account-wide seed is taken
-- once, by whichever character logs in first, and is then silently wrong on every other one.
local H = dofile("CombatAssistPlus/tests/mock_ns.lua")

local function loadPlace()
  local wasCreate, wasSlash = _G.CreateFrame, _G.SlashCmdList
  _G.CreateFrame = function()
    return setmetatable({}, { __index = function() return function() end end })
  end
  _G.SlashCmdList = {}
  local ns = { RegisterCommand = function() end }
  -- Core.lua first: Place binds `ns.readable` as a file-local at load.
  H.load(ns, "Core.lua")
  H.load(ns, "Place.lua")
  _G.CreateFrame, _G.SlashCmdList = wasCreate, wasSlash
  return ns
end

describe("engine / place", function()
  local ns
  before_each(function()
    ns = loadPlace()
    ns.db, ns.cdb = {}, {}
  end)

  it("creates a keyed table on first ask and fills only absent defaults", function()
    local s = ns.Place.Store("row", { x = 1, y = 2 })
    assert.are.equal(1, s.x)
    assert.are.equal(2, s.y)
    assert.is_false(s.placed)
    assert.are.equal(s, ns.cdb.places.row)
    assert.is_nil(ns.db.places)
  end)

  it("never clobbers a saved value with a default", function()
    ns.Place.Store("row", { x = 1, y = 2 }).x = 99
    assert.are.equal(99, ns.Place.Store("row", { x = 1, y = 2 }).x)
  end)

  it("adopts the single-panel era's db.frame for the `frame` key", function()
    ns.db.frame = { x = 40, y = -160, placed = true }
    local s = ns.Place.Store("frame", { x = 0, y = 0 })
    assert.are.equal(40, s.x)
    assert.are.equal(-160, s.y)
    assert.is_true(s.placed)
  end)

  -- The old key is deliberately LEFT in place: it costs a few bytes, and a player who rolls
  -- back to the previous build finds their panel where they left it rather than at the origin.
  it("leaves the legacy key alone rather than moving it", function()
    ns.db.frame = { x = 40, y = -160, placed = true }
    ns.Place.Store("frame", { x = 0, y = 0 })
    assert.are.equal(40, ns.db.frame.x)
  end)

  -- The migration is scoped to one key. Reading it for the row would hand cap's CDM panel the
  -- cooldown panel's position, which is a visible jump rather than a silent one.
  it("does not read the legacy key for any other frame", function()
    ns.db.frame = { x = 40, y = -160, placed = true }
    local s = ns.Place.Store("row", { x = 0, y = -200 })
    assert.are.equal(0, s.x)
    assert.are.equal(-200, s.y)
    assert.is_false(s.placed)
  end)

  it("takes the migration once, so a later edit is not overwritten by it", function()
    ns.db.frame = { x = 40, y = -160, placed = true }
    ns.Place.Store("frame", { x = 0, y = 0 }).x = 7
    assert.are.equal(7, ns.Place.Store("frame", { x = 0, y = 0 }).x)
  end)

  it("keeps the shape before the saved table exists, so a load-time write is not orphaned", function()
    ns.cdb = nil
    local s = ns.Place.Store("row", { x = 3, y = 4 })
    assert.are.equal(3, s.x)
    assert.are.equal(s, ns.Place.Store("row", { x = 3, y = 4 }))
  end)

  -- ⚠ THE BUG THE SPLIT EXISTS TO CLOSE. `placed` is what stops a re-seed, so an account-wide
  -- seed taken by the first character to log in would leave every other character's row
  -- sitting where THAT character's Cooldown Manager was. The position still carries over as a
  -- starting point; only the flag is dropped, so this character measures its own.
  it("does not carry a SEEDED position's placed flag to another character", function()
    ns.db.places = { row = { x = 5, y = -300, placed = true, by = "seed" } }
    local s = ns.Place.Store("row", { x = 0, y = -200 })
    assert.are.equal(5, s.x)
    assert.is_false(s.placed)
    assert.is_nil(s.by)
  end)

  -- A drag is the player's opinion and it travels: they placed cap's panel once and want it
  -- there on every character, which is the whole reason position carries at all.
  it("does carry a MOVED position, flag and all", function()
    ns.db.places = { frame = { x = 5, y = -300, placed = true, by = "move" } }
    local s = ns.Place.Store("frame", { x = 0, y = 0 })
    assert.are.equal(5, s.x)
    assert.is_true(s.placed)
  end)

  -- The single-panel era had no `by` field and no seeding — the row did not exist yet — so
  -- everything in it was hand-placed and must travel.
  it("treats the pre-keyed db.frame as hand-placed", function()
    ns.db.frame = { x = 9, y = -9, placed = true }
    assert.is_true(ns.Place.Store("frame", { x = 0, y = 0 }).placed)
  end)

  -- Two characters, one account table: the second must not see the first's per-character work.
  it("keeps two characters' positions apart", function()
    ns.Place.Store("row", { x = 0, y = 0 }).x = 111
    ns.cdb = {}
    assert.are.equal(0, ns.Place.Store("row", { x = 0, y = 0 }).x)
  end)

  it("never writes placement into the account table", function()
    ns.Place.Store("row", { x = 1, y = 2 })
    ns.Place.Store("frame", { x = 1, y = 2 })
    assert.is_nil(ns.db.places)
  end)
end)
