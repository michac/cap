-- Bars.lua — spec.md §3.4's cooldown bars: one per catalog roster entry, stacked in the
-- movable panel Frame.lua owns, carrying §3.1's tier signal on the fill. Impure. `Bars.Plan`
-- is the pure seam: which entries get a bar, in what order, and what each is drawn in.
--
-- The remaining time never enters Lua — the client is handed a duration object and draws
-- from it (security-taint-and-restricted-data.md §4.8.1 findings 2, 3, 5). Those sinks are
-- aspect-less and hand nothing back, so `armed` is the strongest word available here.
local ADDON, ns = ...

local ROW_HEIGHT = 18
local PAD = 3
local TIME_ZONE = 42
local FONT_SIZE = 11

-- `SetTimerDuration(d, interpolation, direction)`. ⚠ `Enum.StatusBarInterpolation.None` is
-- NOT in the generated enum — only `Immediate` and `ExponentialEaseOut` — so nothing here
-- reaches for it; the literals are the values cooldown-manager.md §7's recipe names.
local IMMEDIATE = (Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate) or 0
local REMAINING = 1   -- TimerDirection.RemainingTime

-- Cap's own mark where it has no number. NEVER a stand-in for zero: that answer is the client's.
local NO_NUMBER = "--"

ns.Bars = ns.Bars or {}
local Bars = ns.Bars

local pool = {}
local attachedKey
local cells = {}
local probe

-- ---------------------------------------------------------------------------
-- The plan — pure
-- ---------------------------------------------------------------------------

--- One descriptor per id in the roster, in that order, because a panel stacks and the order
--- is part of the declaration. An id whose entry did not bind carries no spell, and the
--- surface draws it as `nobind` rather than as an empty bar.
---
--- The spell asked about is the BOUND ROW's, not the authored one: an entry covering both
--- halves of a choice node binds through `alt`, and the authored id is then the wrong half.
function Bars.Plan(roster, out)
  local plan = {}
  local byEntry = (out or {}).byEntry or {}
  for _, id in ipairs(roster or {}) do
    local v = byEntry[id]
    local row = v and v.row
    plan[#plan + 1] = {
      id = id,
      spellID = row and row.primary or nil,
      tier = v and v.tier or nil,
      treatment = ns.Treatment.For(v),
    }
  end
  return plan
end

-- ---------------------------------------------------------------------------
-- The frames
-- ---------------------------------------------------------------------------

local formatter

--- Built once and kept. `false` records that the route is unavailable, so the probe below
--- can say so rather than re-asking on every pass.
local function secondsFormatter()
  if formatter ~= nil then return formatter or nil end
  if not (C_StringUtil and C_StringUtil.CreateSecondsFormatter) then
    formatter = false
    return nil
  end
  local ok, f = pcall(C_StringUtil.CreateSecondsFormatter)
  formatter = (ok and f ~= nil) and f or false
  return formatter or nil
end

-- The returned bool is `SetFont`'s only failure signal and is discarded almost everywhere;
-- a refusal leaves the string on the template's font, silently and unreadably small.
local function dressFont(fs, justify)
  fs:SetJustifyH(justify)
  fs:SetJustifyV("MIDDLE")
  local path = fs:GetFont()
  return (path and fs:SetFont(path, FONT_SIZE, "OUTLINE")) and true or false
end

--- ⚠ Both FontStrings are LEAVES. The countdown is fed a secret string and `SetText` marks
--- the string AND its dependent anchoring-secret (§4.8.1 finding 10), so each is anchored TO
--- the row — the label's right edge to the row, never to the countdown beside it.
local function buildRow()
  local f = CreateFrame("Frame", nil, UIParent)

  local T = ns.Treatment.BAR.track
  local track = f:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints(f)
  -- Fed literals and never a game value: `SetColorTexture` POISONS the anchor chain on a
  -- secret (§4.8.1 finding 12), which the colour and alpha channels below do not.
  track:SetColorTexture(T.r, T.g, T.b, T.a)

  local sb = CreateFrame("StatusBar", nil, f)
  sb:SetAllPoints(f)
  -- ⚠ The bool almost everyone discards. Reported, not acted on: a texture is the whole of
  -- what a bar fills, so a refusal is worth naming — but standing down on one leaves the
  -- player nothing, where carrying on still leaves them a track and a number.
  local textured = sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8") and true or false
  sb:Hide()

  -- Ready is its own widget. A timer bar released and re-armed is a sequence nothing has
  -- measured, and a ready cooldown has no duration object to arm one with.
  local full = f:CreateTexture(nil, "ARTWORK")
  full:SetAllPoints(f)
  full:SetColorTexture(1, 1, 1, 1)
  full:Hide()

  local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  name:SetPoint("LEFT", f, "LEFT", PAD, 0)
  name:SetPoint("RIGHT", f, "RIGHT", -(TIME_ZONE + PAD), 0)
  name:SetWordWrap(false)
  local sized = dressFont(name, "LEFT")

  local time = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  time:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
  time:SetWidth(TIME_ZONE)
  sized = dressFont(time, "RIGHT") and sized

  if probe == nil then
    probe = (textured and "tex" or "notex")
      .. "/" .. (secondsFormatter() and "fmt" or "nofmt")
      .. "/" .. (sized and "font" or "nofont")
  end

  f:Hide()
  return { frame = f, sb = sb, full = full, name = name, time = time }
end

-- The fallback IS the signal: a bar labelled `E2` rather than an ability name is the name
-- lookup having refused, which needs no token of its own to see.
local function label(desc)
  local fn = C_Spell and C_Spell.GetSpellName
  if type(fn) == "function" and type(desc.spellID) == "number" then
    local ok, s = pcall(fn, desc.spellID)
    if ok and type(s) == "string" and s ~= "" then return s end
  end
  return desc.id
end

-- ---------------------------------------------------------------------------
-- The client's half — cap hands over a duration and is never told what was drawn
-- ---------------------------------------------------------------------------

-- Two ways a bar ends up empty: one set of pixels, two cells, because a flight that cannot
-- tell the faults apart learns nothing from either.
local REFUSED = "refused"   -- the read refused: the call was absent, or it threw
local UNARMED = "unarmed"   -- the sinks refused it: SetMinMaxValues / SetTimerDuration raised

--- The duration object, or nil plus the reason. Nil with no reason is a spell with nothing
--- remaining: `MayReturnNothing` is an answer here, not a failure. ignoreGCD, or every bar
--- fills for 1.5 s after every cast.
local function durationOf(spellID)
  if not (C_Spell and C_Spell.GetSpellCooldownDuration) then return nil, REFUSED end
  local ok, d = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
  if not ok then return nil, REFUSED end
  return d
end

--- ⚠ ORDER IS THE WHOLE FUNCTION (§4.8.1 finding 3): the range goes in BEFORE the timer, or
--- a correct duration draws at 0 % width. `SetToTargetValue` is finding 5 and is FIRST SHOW
--- ONLY — on every pass it would snap out an interpolation the client is midway through.
local function armTimer(r, d)
  local sb = r.sb
  local ok = pcall(function()
    sb:SetMinMaxValues(0, 1)
    sb:SetTimerDuration(d, IMMEDIATE, REMAINING)
  end)
  if not ok then return false end
  if not r.snapped then
    pcall(sb.SetToTargetValue, sb)
    r.snapped = true
  end
  return true
end

--- The countdown string, written EVERY pass a bar is armed: it is secret, so cap can neither
--- read it back nor dedup on it. Nil means cap could not build one — never that the
--- remaining time is zero, an answer that belongs to the client and does not come back.
local function timeText(d)
  local fmt = secondsFormatter()
  if not fmt then return nil end
  -- `modifier` is `Nilable = false` WITH a `Default`, so it goes in explicitly (§4.6).
  local mod = Enum and Enum.DurationTimeModifier and Enum.DurationTimeModifier.RealTime
  if mod == nil then return nil end
  local ok, s = pcall(function() return d:FormatRemainingDuration(fmt, mod) end)
  if not ok or s == nil then return nil end
  return s
end

-- ---------------------------------------------------------------------------
-- The draw pass
-- ---------------------------------------------------------------------------

local function showBar(r, on)
  if r.barShown == on then return end
  r.barShown = on
  if on then
    r.sb:Show()
  else
    r.sb:Hide()
    r.snapped = false
  end
end

--- Four states, three sets of pixels: ready is full and unnumbered, armed is the client's
--- fill and the client's number, and both empty states carry cap's own `--`.
local function paint(r, desc, state)
  local rr, gg, bb, aa = ns.Treatment.Fill(desc.treatment)
  -- The spell is in the key because the label is: one entry covering both halves of a choice
  -- node rebinds to the other half without the roster changing.
  local k = (desc.tier or "-") .. ("/%0.2f/"):format(aa) .. state .. "/" .. tostring(desc.spellID)
  if r.painted == k then return end
  r.painted = k
  r.sb:SetStatusBarColor(rr, gg, bb, aa)
  r.full:SetVertexColor(rr, gg, bb)
  r.full:SetAlpha(aa)
  r.name:SetText(label(desc))
end

local function update(r, desc)
  local d, why = durationOf(desc.spellID)
  local state, marked = REFUSED, false

  if why == nil and d == nil then
    state = "ready"
  elseif d ~= nil then
    if armTimer(r, d) then
      state = "armed"
      local s = timeText(d)
      if s ~= nil then r.time:SetText(s) else marked = true end
    else
      state = UNARMED
    end
  end

  paint(r, desc, state)
  showBar(r, state == "armed")
  if state == "ready" then r.full:Show() else r.full:Hide() end
  if state ~= "armed" or marked then r.time:SetText(state == "ready" and "" or NO_NUMBER) end
  r.frame:Show()
  return state, marked
end

--- ⚠ Detaching clears the show flags with it, or a pooled row that comes back is `Show`n
--- with `snapped` set, skips `SetToTargetValue` (§4.8.1 finding 5) and drifts off a stale value.
local function release(r)
  showBar(r, false)
  r.painted = nil
  ns.Frame.Detach(r.frame)
end

--- The attach order IS the panel's stacking order, so a change of roster re-attaches the
--- whole list rather than appending to it. Rebuilt only on that change: a bind is settled
--- out of combat, so every row is created and placed before the pull.
local function relayout(plan)
  local ids = {}
  for _, desc in ipairs(plan) do
    if desc.spellID then ids[#ids + 1] = desc.id end
  end
  local key = table.concat(ids, ",")
  if key == attachedKey then return end
  attachedKey = key

  for _, r in pairs(pool) do release(r) end
  for _, id in ipairs(ids) do
    local r = pool[id]
    if not r then
      r = buildRow()
      pool[id] = r
    end
    ns.Frame.Attach(r.frame, ROW_HEIGHT)
  end
end

local function dark()
  cells = {}
  for _, r in pairs(pool) do
    showBar(r, false)
    r.frame:Hide()
    r.painted = nil
  end
end

--- The `B{}` cells of the last pass, and the build-time probe. ⚠ Neither says a bar
--- appeared: every duration sink is aspect-less and hands nothing back.
function Bars.Report()
  return cells, probe or "-"
end

ns.Sense.OnVerdicts(function(out, bound)
  if not (out and bound) then
    dark()
    return
  end
  local plan = Bars.Plan(ns.Sense.Roster(), out)
  relayout(plan)

  cells = {}
  for _, desc in ipairs(plan) do
    local state, marked = "nobind", false
    local r = desc.spellID and pool[desc.id]
    if r then state, marked = update(r, desc) end
    cells[#cells + 1] = desc.id .. ":" .. state .. (marked and "!" or "")
  end
end)
