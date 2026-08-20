-- Binds.lua — which key casts this row.
--
-- WHY THIS EXISTS. A Cooldown Manager row shows you *what* to press and never *which key*:
-- `grep HotKey` over the whole `Blizzard_CooldownViewer` folder returns zero, so the CDM has no
-- keybind region at all. The player reads an icon and then remembers a binding. This is the
-- lookup that closes that gap; `Overlay` draws the result and `render-shelf.md` V15 owns how it
-- looks. It is CHROME (`spec.md` §3.8) — it names a row and asserts nothing about the press, so
-- nothing here feeds a cue, a verdict or the elimination walk.
--
-- THE LOOKUP IS TWO STAGES, and both come from `knowledge/addon-dev/cdm-rider-patterns.md` §11
-- (Tier-1 against shipped 12.1 source). Spell → action slots, then slot → binding command.
--
-- ⚠ STAGE 1 TAKES A BASE SPELL, and that is the API's stated contract rather than a fallback:
-- `C_ActionBar.FindSpellActionButtons` is documented "expects a base spell". The CDM routinely
-- hands us an override while the player's bar holds the base, so both are probed and merged. It
-- returns **nil, not an empty table**, when the spell is unslotted, which is why every list is
-- guarded rather than iterated.
--
-- ⚠ STAGE 2 SCANS THE REAL BUTTON FRAMES and reads `frame.action` off each. There is no page
-- arithmetic here on purpose: a hardcoded `floor((slot-1)/12)+1` plus a page→binding table gets
-- paged, bonus and override bars wrong, and the frames already know the answer.
--
-- KNOWN LIMIT, RULED RATHER THAN OUTSTANDING: the lookup is spell-keyed, so a slot holding a
-- MACRO that casts the ability is invisible to it and that row shows blank. Blank, never a
-- placeholder — an invented key is worse than an absent one. A slot-scan fallback is possible
-- and is not v1.
--
-- ⚠ THE CLIENT'S OWN ABBREVIATION IS NOT ENOUGH, and that is a measured fact rather than a
-- preference. `GetBindingText(key, 1)` shortens the MODIFIERS only — `SHIFT_KEY_TEXT_ABBR = "s"`,
-- `CTRL_KEY_TEXT_ABBR = "c"`, `ALT_KEY_TEXT_ABBR = "a"` — and leaves every key NAME at full
-- length, because no `KEY_ABBR_*` string exists for keyboard or mouse keys at all (the
-- `KEY_ABBR_*` family is gamepad-only, and it expands to a texture escape rather than to text).
-- So a mouse binding comes back as the literal `"Mouse Button 4"`, which cannot go in the corner
-- of a 56 px icon. Blizzard's own action button does not shorten it either — it fixes the
-- FontString's width and lets the widget clip. `Shorten` is cap's answer: a name, not a crop.
--
-- ⚠ NO COMBAT FENCE, deliberately. §11 measured the read chain callable in combat: Blizzard runs
-- `GetBindingKey` → `GetBindingText` → `HotKey:SetText` mid-combat with no lockdown check, and a
-- FontString is not protected even inside a protected button. A "rescan out of combat only" rule
-- would be a COST rule wearing safety's clothes, and one that blanks or stales the hint for the
-- rest of a pull. So: debounce, never defer.
local ADDON, ns = ...

ns.Binds = ns.Binds or {}
local Binds = ns.Binds

-- How long a burst of bar events is allowed to run before the cache drops. A spec swap arrives
-- as a burst of `ACTIONBAR_SLOT_CHANGED` rather than one event, so this is what stops the map
-- being rebuilt once per slot.
local REBUILD_DELAY = 0.2

--- Frame prefix, binding prefix, count — the bars whose slots can carry a bound key.
--- `MultiBarBottomLeft` is binding bar **1** and `MultiBarLeft` is binding bar **4**; the names
--- and the numbers do not line up, which is most of why this is a table and not a format string.
Binds.BARS = {
  { "ActionButton",              "ACTIONBUTTON",          12 },
  { "MultiBarBottomLeftButton",  "MULTIACTIONBAR1BUTTON", 12 },
  { "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON", 12 },
  { "MultiBarRightButton",       "MULTIACTIONBAR3BUTTON", 12 },
  { "MultiBarLeftButton",        "MULTIACTIONBAR4BUTTON", 12 },
  { "MultiBar5Button",           "MULTIACTIONBAR5BUTTON", 12 },
  { "MultiBar6Button",           "MULTIACTIONBAR6BUTTON", 12 },
  { "MultiBar7Button",           "MULTIACTIONBAR7BUTTON", 12 },
}

--- The long key NAMES the client hands back, and what cap draws instead. Longest match first,
--- because "Mouse Button 4" contains none of the others but "Middle Mouse" and "Mouse Wheel Up"
--- overlap on the word.
---
--- The mouse numbering follows the client's own: button 1 is left, 2 is right, 3 is middle, and
--- 4 upward are the side buttons — so `M3` names the same button `KEY_BUTTON3` does.
Binds.NAMES = {
  { "Left Mouse Button", "M1" },
  { "Right Mouse Button", "M2" },
  { "Middle Mouse", "M3" },
  { "Mouse Wheel Up", "MU" },
  { "Mouse Wheel Down", "MD" },
  { "Mouse Button ", "M" },
  { "Num Pad ", "N" },
}

-- ---------------------------------------------------------------------------
-- Pure
-- ---------------------------------------------------------------------------

--- The key text, compacted to something that fits an icon corner.
---
--- Two jobs. It replaces the long key names above, and it drops the SEPARATORS between the
--- modifier letters and the key, so `s-F` becomes `sF` — which is the notation EllesmereUI's CDM
--- option uses and reads as a modifier rather than as a range.
---
--- ⚠ `[gap]` THE JOINER IS UNMEASURED. `GetBindingText` is implemented C-side and appears in no
--- local source, so what it puts BETWEEN the abbreviated modifier and the key is unknown —
--- `s-F`, `sF` and `s F` are all consistent with what the string table proves
--- [searched 2026-08-19: wow-ui-source 12.0.7 (68453), BlizzardInterfaceResources enUS
--- GlobalStrings]. This is written to be indifferent to it: it strips `-` and spaces from the
--- modifier run rather than matching one assumed layout, so it lands on `sF` whichever the client
--- emits. Confirm the raw form in the flight before anyone builds on the exact shape.
function Binds.Shorten(text)
  if type(text) ~= "string" or text == "" then return nil end
  for _, pair in ipairs(Binds.NAMES) do
    -- `find`/`gsub` with plain=false would read `Num Pad .` as a pattern; every needle here is
    -- literal, so both calls are made plain.
    local at = text:find(pair[1], 1, true)
    if at then
      text = text:sub(1, at - 1) .. pair[2] .. text:sub(at + #pair[1])
    end
  end
  -- The modifier run: a leading sequence of the client's own single-letter abbreviations, each
  -- optionally followed by a separator. Anything else is left exactly as it came.
  local mods, rest = "", text
  while true do
    local letter, tail = rest:match("^([sca])[%-%s]+(.+)$")
    if not letter then break end
    mods, rest = mods .. letter, tail
  end
  return mods .. rest
end

--- Every action slot the client says holds this spell, merged over the raw id and its base.
---
--- `find` is the client's `FindSpellActionButtons` in the game and a table lookup in the
--- harness, so the merge is the same code path either way. Order is preserved and duplicates
--- drop: the raw id's slots come first because the CDM's own identity is the one the player is
--- looking at, and the base only fills in what it did not cover.
function Binds.Slots(spellID, baseID, find)
  local out, seen = {}, {}
  if type(find) ~= "function" then return out end
  for _, id in ipairs({ spellID, baseID }) do
    -- String keys for ids, number keys for slots: two key spaces in one table, which cannot
    -- collide and saves carrying a second `seen`.
    if type(id) == "number" and not seen["#" .. id] then
      seen["#" .. id] = true
      local ok, slots = pcall(find, id)
      if ok and type(slots) == "table" then
        for _, slot in ipairs(slots) do
          if type(slot) == "number" and not seen[slot] then
            seen[slot] = true
            out[#out + 1] = slot
          end
        end
      end
    end
  end
  return out
end

--- `{ [slot] = { binding, frame } }`, built by asking each real button frame which slot it is
--- currently showing. `frameOf` is `_G` lookup in the game and a table in the harness.
---
--- First writer wins, so a slot claimed by two bars resolves to the earlier one in `BARS` — the
--- primary bar. Two frames on one slot is a paged-bar transient, not a state to average.
function Binds.SlotMap(bars, frameOf)
  local out = {}
  if type(frameOf) ~= "function" then return out end
  for _, bar in ipairs(bars or {}) do
    local framePrefix, bindPrefix, n = bar[1], bar[2], bar[3]
    for i = 1, n do
      local name = framePrefix .. i
      local ok, frame = pcall(frameOf, name)
      local slot = (ok and type(frame) == "table") and frame.action or nil
      if type(slot) == "number" and out[slot] == nil then
        out[slot] = { binding = bindPrefix .. i, frame = name }
      end
    end
  end
  return out
end

--- The bonus/stance-bar case, which the frame scan cannot cover: a bonus-bar slot maps onto
--- `ActionButton{i}` only while that bonus bar is the active one, so the answer depends on state
--- the frames do not carry. This is the ONE place §11 sanctions the modulo.
function Binds.BonusEntry(slot, bonusIndex, activeIndex)
  if type(slot) ~= "number" or type(bonusIndex) ~= "number" then return nil end
  if type(activeIndex) ~= "number" or bonusIndex ~= activeIndex then return nil end
  local i = ((slot - 1) % 12) + 1
  return { binding = "ACTIONBUTTON" .. i, frame = "ActionButton" .. i }
end

--- The first slot in `slots` that resolves to a key. `keyOf(binding, frame)` answers the key,
--- `bonusOf(slot)` is the optional fallback for a slot no scanned frame claimed.
---
--- A spell on four bars has four answers and the player has one keyboard; taking the first is
--- what makes this deterministic. Nothing here ranks the bars — `BARS` order does.
function Binds.Resolve(slots, map, keyOf, bonusOf)
  if type(keyOf) ~= "function" then return nil end
  for _, slot in ipairs(slots or {}) do
    local entry = (map or {})[slot]
    if not entry and type(bonusOf) == "function" then entry = bonusOf(slot) end
    if entry then
      local ok, key = pcall(keyOf, entry.binding, entry.frame)
      if ok and type(key) == "string" and key ~= "" then return key end
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- The live read
-- ---------------------------------------------------------------------------

local function frameOf(name)
  return _G[name]
end

--- Binding command → the text to draw. The CLICK form is the fallback that click-cast and
--- addon bars bind under; it is tried second because a real binding on the stock command is the
--- more common answer and the cheaper one.
---
--- ⚠ `GetBindingText(key, 1)` — the abbreviate flag is a POSITIONAL TRUTHY ARGUMENT. It is not
--- the string `"KEY_ABBR"`, which is the naming convention for the globals the function looks up
--- internally (§11). Passing the string abbreviates nothing and looks like it worked.
local function keyOf(binding, frameName)
  if type(GetBindingKey) ~= "function" then return nil end
  local ok, key = pcall(GetBindingKey, binding)
  if not (ok and type(key) == "string" and key ~= "") then key = nil end
  if not key and frameName then
    local okClick, alt = pcall(GetBindingKey, "CLICK " .. frameName .. ":LeftButton")
    if okClick and type(alt) == "string" and alt ~= "" then key = alt end
  end
  if not key then return nil end
  if type(GetBindingText) == "function" then
    local okText, text = pcall(GetBindingText, key, 1)
    -- ⚠ `""`, not nil, is the client's "nothing here" — Blizzard's own `UpdateHotkeys` tests
    -- `text == ""` and hides the FontString on it.
    if okText and type(text) == "string" and text ~= "" then return Binds.Shorten(text) end
  end
  return Binds.Shorten(key)
end

--- Feature-gated whole: a client missing any part of the bonus-bar trio answers nothing rather
--- than answering from half of it.
local function bonusOf(slot)
  local B = C_ActionBar
  if not (B and B.GetBonusBarIndexForSlot and B.HasBonusActionBar and B.GetBonusBarIndex) then
    return nil
  end
  local okHas, has = pcall(B.HasBonusActionBar)
  if not (okHas and has) then return nil end
  local okIndex, index = pcall(B.GetBonusBarIndexForSlot, slot)
  if not okIndex then return nil end
  local okActive, active = pcall(B.GetBonusBarIndex)
  if not okActive then return nil end
  return Binds.BonusEntry(slot, index, active)
end

local function baseOf(spellID)
  if not (C_Spell and C_Spell.GetBaseSpell) then return nil end
  local ok, base = pcall(C_Spell.GetBaseSpell, spellID)
  if ok and type(base) == "number" and base ~= spellID then return base end
  return nil
end

local cache

--- Drop everything. Nothing is patched: a bar event says a slot moved, never which spell moved
--- with it, so a partial invalidation would be a guess. The map and the per-spell answers are
--- cheap to rebuild and both are re-derived on the next draw.
function Binds.Invalidate()
  cache = nil
end

--- The key that casts `spellID`, or nil when nothing is bound to it.
---
--- ⚠ Feed it the row's `primary` (`override or base`), not the authored id and not the LIVE id.
--- The live id flickers under a transform exactly when the ability is most active, and a hint
--- that changes mid-pull because the icon re-skinned is a hint nobody can trust.
---
--- `false` is cached for "we looked and nothing is bound", so an unbound ability costs one scan
--- rather than one per draw.
function Binds.For(spellID)
  if type(spellID) ~= "number" then return nil end
  if not (C_ActionBar and C_ActionBar.FindSpellActionButtons) then return nil end
  cache = cache or { keys = {} }
  local hit = cache.keys[spellID]
  if hit ~= nil then return hit or nil end

  cache.map = cache.map or Binds.SlotMap(Binds.BARS, frameOf)
  local slots = Binds.Slots(spellID, baseOf(spellID), C_ActionBar.FindSpellActionButtons)
  local key = Binds.Resolve(slots, cache.map, keyOf, bonusOf)
  cache.keys[spellID] = key or false
  return key
end

-- Guarded because the pure half above is unit-tested outside the client, where `CreateFrame`
-- does not exist. Nothing below this line runs in the harness, and nothing above it needs to.
if CreateFrame then
  local pending, armed = false, false

  -- DEBOUNCE, NOT DEFER (see the header). A spec swap raises one `ACTIONBAR_SLOT_CHANGED` per
  -- slot, so dropping the cache on each would rebuild the map dozens of times in one frame;
  -- waiting for `PLAYER_REGEN_ENABLED` instead would leave the hint wrong for the pull.
  local function schedule()
    pending = true
    if armed then return end
    armed = true
    C_Timer.After(REBUILD_DELAY, function()
      armed = false
      if pending then
        pending = false
        Binds.Invalidate()
      end
    end)
  end

  local events = CreateFrame("Frame")
  for _, event in ipairs({
    "PLAYER_ENTERING_WORLD",
    "UPDATE_BINDINGS",
    "ACTIONBAR_SLOT_CHANGED",
    "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_OVERRIDE_ACTIONBAR",
    "UPDATE_VEHICLE_ACTIONBAR",
    "UPDATE_SHAPESHIFT_FORM",
    "PET_BAR_UPDATE",
    -- No action-bar file registers this one, and the bars do not need it. A cache keyed by
    -- SPELL does: a talent override changes which base id is slotted, and the burst of slot
    -- events that accompanies a spec swap says nothing about that.
    "PLAYER_SPECIALIZATION_CHANGED",
  }) do
    events:RegisterEvent(event)
  end
  events:SetScript("OnEvent", schedule)
end
