-- The pure half of Binds.lua: slot → binding command, and the base-spell merge.
--
-- ⚠ WHAT IS DELIBERATELY NOT HERE. There is no fake `C_ActionBar.FindSpellActionButtons` that
-- returns a slot list of this file's invention, and no assertion resting on one. Blizzard's
-- lookup is a client API this workspace has never called; a test that asserts what it returns
-- asserts what its author imagined. What IS testable is everything downstream of it — the
-- arithmetic and the table walk are ours, and they are what a hardcoded page formula got wrong.
--
-- So `find` and `frameOf` arrive as functions: the harness hands them tables, the client hands
-- them the real API and `_G`, and the code under test is the same either way.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("engine / binds", function()
  local ns
  before_each(function()
    ns = H.fresh()
  end)

  --- A `_G` stand-in: the button frames a scan would find, keyed by their global name.
  local function frames(map)
    return function(name) return map[name] end
  end

  --- A `FindSpellActionButtons` stand-in over a spell → slots table. It answers **nil** for an
  --- unslotted spell, which is the documented shape and the one that breaks a naive `ipairs`.
  local function finder(map)
    return function(id) return map[id] end
  end

  describe("slot map", function()
    it("reads the slot off each real button frame rather than computing a page", function()
      local map = ns.Binds.SlotMap(ns.Binds.BARS, frames({
        ActionButton3 = { action = 3 },
        -- The paged case a `floor((slot-1)/12)+1` formula gets wrong: the frame is bar 1's
        -- button 5 while the player is on page 4, so its slot is 41 and its binding is still
        -- ACTIONBUTTON5. No arithmetic recovers that; the frame just knows.
        ActionButton5 = { action = 41 },
        MultiBarBottomLeftButton1 = { action = 13 },
        MultiBarLeftButton7 = { action = 43 },
      }))
      assert.same({ binding = "ACTIONBUTTON3", frame = "ActionButton3" }, map[3])
      assert.same({ binding = "ACTIONBUTTON5", frame = "ActionButton5" }, map[41])
      assert.same({ binding = "MULTIACTIONBAR1BUTTON1", frame = "MultiBarBottomLeftButton1" },
                  map[13])
      assert.same({ binding = "MULTIACTIONBAR4BUTTON7", frame = "MultiBarLeftButton7" }, map[43])
    end)

    it("maps the bar NAMES onto the binding NUMBERS, which do not line up", function()
      -- MultiBarBottomLeft is binding bar 1 and MultiBarLeft is binding bar 4. Getting this
      -- pair backwards shows the player a key that casts something else.
      local map = ns.Binds.SlotMap(ns.Binds.BARS, frames({
        MultiBarBottomLeftButton1 = { action = 1 },
        MultiBarBottomRightButton1 = { action = 2 },
        MultiBarRightButton1 = { action = 3 },
        MultiBarLeftButton1 = { action = 4 },
      }))
      assert.equal("MULTIACTIONBAR1BUTTON1", map[1].binding)
      assert.equal("MULTIACTIONBAR2BUTTON1", map[2].binding)
      assert.equal("MULTIACTIONBAR3BUTTON1", map[3].binding)
      assert.equal("MULTIACTIONBAR4BUTTON1", map[4].binding)
    end)

    it("gives a contested slot to the earlier bar and does not average two answers", function()
      local map = ns.Binds.SlotMap(ns.Binds.BARS, frames({
        ActionButton1 = { action = 7 },
        MultiBarRightButton1 = { action = 7 },
      }))
      assert.equal("ACTIONBUTTON1", map[7].binding)
    end)

    it("survives a frame that is absent, or present with no slot on it", function()
      local map = ns.Binds.SlotMap(ns.Binds.BARS, frames({
        ActionButton1 = { action = 1 },
        ActionButton2 = {},
      }))
      assert.equal("ACTIONBUTTON1", map[1].binding)
      assert.same({ [1] = map[1] }, map)
    end)

    it("answers an empty map rather than throwing when there is no lookup at all", function()
      assert.same({}, ns.Binds.SlotMap(ns.Binds.BARS, nil))
    end)
  end)

  describe("bonus bar", function()
    -- The one place §11 sanctions a modulo: a bonus-bar slot maps onto ActionButton{i} only
    -- while that bonus bar is the active one, which no frame's `action` field records.
    -- Slot 125 is button 5 of a bonus page: ((125 - 1) % 12) + 1 = 5.
    it("resolves a bonus slot onto the primary bar's button while that bar is active", function()
      assert.same({ binding = "ACTIONBUTTON5", frame = "ActionButton5" },
                  ns.Binds.BonusEntry(125, 2, 2))
    end)

    it("answers nothing while a DIFFERENT bonus bar is active", function()
      assert.is_nil(ns.Binds.BonusEntry(125, 2, 3))
    end)

    it("answers nothing when the client will not say which bar is active", function()
      assert.is_nil(ns.Binds.BonusEntry(125, 2, nil))
    end)
  end)

  describe("the base-spell merge", function()
    it("probes the override AND the base, because the CDM hands over the override", function()
      -- 442294 is slotted nowhere; its base 198013 is on the bar. The API's documented input is
      -- the BASE, so a lookup that only asked about the row's own id would find nothing.
      local slots = ns.Binds.Slots(442294, 198013, finder({ [198013] = { 4 } }))
      assert.same({ 4 }, slots)
    end)

    it("puts the row's own id first, and lets the base only fill in what it missed", function()
      local slots = ns.Binds.Slots(442294, 198013, finder({ [442294] = { 9 }, [198013] = { 4 } }))
      assert.same({ 9, 4 }, slots)
    end)

    it("does not repeat a slot both ids report", function()
      local slots = ns.Binds.Slots(442294, 198013, finder({ [442294] = { 4 }, [198013] = { 4 } }))
      assert.same({ 4 }, slots)
    end)

    it("treats an unslotted spell's NIL as empty, not as a table", function()
      -- The documented return is `MayReturnNothing`: nil, never `{}`. An unguarded ipairs over
      -- it is the crash this asserts against.
      assert.same({}, ns.Binds.Slots(198013, nil, finder({})))
    end)

    it("asks once when the base and the row's id are the same spell", function()
      local asked = 0
      local slots = ns.Binds.Slots(198013, 198013, function(id) asked = asked + 1; return { id } end)
      assert.equal(1, asked)
      assert.same({ 198013 }, slots)
    end)
  end)

  describe("shortening the key text", function()
    -- The client abbreviates MODIFIERS ONLY (`SHIFT_KEY_TEXT_ABBR = "s"` and friends) and has no
    -- abbreviation at all for key names — `KEY_ABBR_*` exists only for gamepad. So the client's
    -- own best effort still hands back "Mouse Button 4", and this is what makes it fit a corner.
    it("names a mouse button instead of spelling it out", function()
      assert.equal("M4", ns.Binds.Shorten("Mouse Button 4"))
      assert.equal("M5", ns.Binds.Shorten("Mouse Button 5"))
      assert.equal("M3", ns.Binds.Shorten("Middle Mouse"))
      assert.equal("M1", ns.Binds.Shorten("Left Mouse Button"))
      assert.equal("M2", ns.Binds.Shorten("Right Mouse Button"))
      assert.equal("MU", ns.Binds.Shorten("Mouse Wheel Up"))
      assert.equal("MD", ns.Binds.Shorten("Mouse Wheel Down"))
    end)

    it("names a numpad key instead of spelling it out", function()
      assert.equal("N5", ns.Binds.Shorten("Num Pad 5"))
      -- `Num Pad .` is a literal, and matching it as a Lua pattern would eat the wrong character.
      assert.equal("N.", ns.Binds.Shorten("Num Pad ."))
    end)

    it("closes up the modifier run, so `s-F` reads as a modifier rather than a range", function()
      assert.equal("sF", ns.Binds.Shorten("s-F"))
      assert.equal("c3", ns.Binds.Shorten("c-3"))
      assert.equal("aQ", ns.Binds.Shorten("a-Q"))
      assert.equal("csF1", ns.Binds.Shorten("c-s-F1"))
    end)

    it("lands on the same answer whichever joiner the client turns out to use", function()
      -- ⚠ The joiner is UNMEASURED — `GetBindingText` is C-side and in no local source. This is
      -- the assertion that makes the unknown harmless rather than load-bearing.
      assert.equal("sF", ns.Binds.Shorten("s-F"))
      assert.equal("sF", ns.Binds.Shorten("s F"))
      assert.equal("sF", ns.Binds.Shorten("sF"))
    end)

    it("shortens a modified mouse binding on both halves at once", function()
      assert.equal("sM4", ns.Binds.Shorten("s-Mouse Button 4"))
    end)

    it("leaves a key it has no shorter name for exactly as it came", function()
      assert.equal("F1", ns.Binds.Shorten("F1"))
      assert.equal("3", ns.Binds.Shorten("3"))
      assert.equal("`", ns.Binds.Shorten("`"))
    end)

    it("treats the client's empty string as no key at all", function()
      -- Blizzard's own UpdateHotkeys tests `text == ""` and hides the string on it.
      assert.is_nil(ns.Binds.Shorten(""))
      assert.is_nil(ns.Binds.Shorten(nil))
    end)
  end)

  describe("resolution", function()
    local map = { [4] = { binding = "ACTIONBUTTON4", frame = "ActionButton4" },
                  [13] = { binding = "MULTIACTIONBAR1BUTTON1", frame = "MultiBarBottomLeftButton1" } }

    it("takes the FIRST slot that answers — one spell on four bars, one keyboard", function()
      local key = ns.Binds.Resolve({ 4, 13 }, map, function(binding)
        return ({ ACTIONBUTTON4 = "4", MULTIACTIONBAR1BUTTON1 = "S-1" })[binding]
      end)
      assert.equal("4", key)
    end)

    it("walks past a slot that is bound to nothing", function()
      local key = ns.Binds.Resolve({ 4, 13 }, map, function(binding)
        return binding == "MULTIACTIONBAR1BUTTON1" and "S-1" or nil
      end)
      assert.equal("S-1", key)
    end)

    it("treats an empty string as unbound, not as a key", function()
      local key = ns.Binds.Resolve({ 4, 13 }, map, function(binding)
        return binding == "ACTIONBUTTON4" and "" or "S-1"
      end)
      assert.equal("S-1", key)
    end)

    it("falls back to the bonus resolution for a slot no scanned frame claimed", function()
      local key = ns.Binds.Resolve({ 61 }, map, function(binding)
        return binding == "ACTIONBUTTON1" and "1" or nil
      end, function(slot)
        return ns.Binds.BonusEntry(slot, 1, 1)
      end)
      assert.equal("1", key)
    end)

    it("answers nil — never a placeholder — when nothing is bound", function()
      assert.is_nil(ns.Binds.Resolve({ 4, 13 }, map, function() return nil end))
      assert.is_nil(ns.Binds.Resolve({}, map, function() return "4" end))
      assert.is_nil(ns.Binds.Resolve({ 99 }, map, function() return "4" end))
    end)

    it("does not throw when a key lookup does", function()
      assert.is_nil(ns.Binds.Resolve({ 4 }, map, function() error("restricted") end))
    end)
  end)
end)
