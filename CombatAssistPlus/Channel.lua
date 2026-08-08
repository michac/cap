-- Channel.lua — the half of the tier signal cap is not allowed to compute: the comparison
-- happens in C and Lua consumes only the visual difference. Both mechanisms, their
-- preconditions and every claim the guards below rest on are in
-- security-taint-and-restricted-data.md §4.8.2 + §4.8.1 finding 4 and cooldown-manager.md §7.
-- ⚠ Could-not-arm returns NIL and nil draws nothing — a marker that defaults to on tells
-- the player something cap could not establish.
local ADDON, ns = ...

local issecretvalue = issecretvalue

ns.Channel = ns.Channel or {}
local Channel = ns.Channel

local function field(obj, key)
  if type(obj) ~= "table" then return nil end
  local ok, v = pcall(function() return obj[key] end)
  if not ok or v == nil or issecretvalue(v) then return nil end
  return v
end

-- Lowest cooldownID among the AURA rows: only those carry a bound aura, and one aura on two viewers must not flip-flop.
local function auraRow(auraSpellID)
  local best
  for _, row in ipairs(ns.Bind.RowsForSpell(auraSpellID)) do
    if row.family == "auras" and (not best or row.cooldownID < best.cooldownID) then best = row end
  end
  return best
end

--- The quantiser's string for `stacks(aura) >= min`, or nil. Its only use is `SetText`.
function Channel.StackText(auraSpellID, min)
  if type(auraSpellID) ~= "number" or type(min) ~= "number" then return nil end
  if not (C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount) then return nil end
  local row = auraRow(auraSpellID)
  if not row then return nil end
  local item = ns.Bind.ItemFrame(row.cooldownID)
  if not item then return nil end

  -- A secret id is REFUSED by the API; a nil unit is no bound aura, not a count of zero.
  local unit, aid = field(item, "auraDataUnit"), field(item, "auraInstanceID")
  if type(unit) ~= "string" or type(aid) ~= "number" then return nil end

  -- No maxDisplayCount, so the `"*"` branch is unreachable: nothing, or the number.
  local ok, s = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, aid, min, nil)
  if not ok or s == nil then return nil end
  return s
end

-- Built once and kept, keyed by (threshold, on-value): only the duration is per-spell.
local curves = {}

--- ⚠ An empty curve evaluates to 0, so an unbuilt one is neither cached nor returned — a
--- zero result has to mean "the client said no".
local function stepCurve(t, on)
  local key = t .. "/" .. on
  if curves[key] then return curves[key] end
  if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType) then return nil end
  local okNew, curve = pcall(C_CurveUtil.CreateCurve)
  if not okNew or curve == nil then return nil end
  -- Step floors to the previous point, so `on` holds below t and 0 from t upward.
  local okBuild = pcall(function()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, on)
    curve:AddPoint(t, 0)
  end)
  if not okBuild then return nil end
  curves[key] = curve
  return curve
end

--- An armed value for `cooldownRemaining(spell) <= t` — `on` below the threshold and 0 at
--- or above it, decided inside the client. Nil if cap could not arm it.
--- ⚠ The result is SECRET and is supposed to be, so `type(r) == "number"` is the wrong
--- guard: it rejects exactly the in-combat case this exists for. `r ~= nil` is the whole
--- test, and `modifier` is `Nilable = false` WITH a `Default`, so it goes in explicitly.
function Channel.Threshold(spellID, t, on)
  if type(spellID) ~= "number" or type(t) ~= "number" or type(on) ~= "number" then return nil end
  if not (C_Spell and C_Spell.GetSpellCooldownDuration) then return nil end
  local mod = Enum and Enum.DurationTimeModifier and Enum.DurationTimeModifier.RealTime
  if mod == nil then return nil end
  -- ignoreGCD, or the marker lights for 1.5 s after every cast.
  local okDur, dur = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
  if not okDur or dur == nil then return nil end
  local curve = stepCurve(t, on)
  if not curve then return nil end
  local ok, r = pcall(function() return dur:EvaluateRemainingDuration(curve, mod) end)
  if not ok or r == nil then return nil end
  return r
end
