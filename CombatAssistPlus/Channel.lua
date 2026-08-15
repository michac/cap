-- Channel.lua — declarative, one-way displays for facts Lua is not allowed to read.
-- AuraContainer owns acquisition and writes the secret application count directly into
-- our leaf FontString. CAP never receives, compares, type-checks, or reads the value back.
local ADDON, ns = ...

local issecretvalue = issecretvalue

ns.Channel = ns.Channel or {}
local Channel = ns.Channel

--- Pure dependency binding. The returned plan is deliberately display vocabulary, not a
--- Signal term; tests use this same path as the live armer.
function Channel.Plan(marker, abilities)
  local display = marker and marker.display
  local ability = display and abilities and abilities[display.ability]
  if not (display and display.kind == "player-aura-stacks" and display.min == 2
      and ability and type(ability.spell) == "number") then
    return nil
  end
  return {
    kind = display.kind, spell = ability.spell, min = display.min,
    unit = "player", sink = "SetApplicationCount",
  }
end

-- ---------------------------------------------------------------------------
-- Sealed power percent — render-shelf V9, the graded curve
-- ---------------------------------------------------------------------------

--- Where the curve breaks, as a fraction of max power: at or above it, one more generator
--- would push the resource past the cap. The catalog authors the GENERATION (no API reports
--- it, so it is a static approximation) and the client owns the max — cap performs the
--- division and nothing else. Pure; nil means "no honest break", which is the inert path.
function Channel.PowerBreak(generation, max)
  if issecretvalue and (issecretvalue(generation) or issecretvalue(max)) then return nil end
  if type(generation) ~= "number" or type(max) ~= "number" then return nil end
  if max <= 0 or generation <= 0 or generation >= max then return nil end
  return (max - generation) / max
end

--- Pure dependency binding for the graded cue, the sibling of `Channel.Plan`. A sealed power
--- display draws its cue and nothing else, so a plan without one is not a plan.
function Channel.PowerPlan(marker)
  local display = marker and marker.display
  if not (display and display.kind == "sealed-power-percent" and marker.cue
      and type(display.power) == "string" and type(display.generation) == "number") then
    return nil
  end
  return { kind = display.kind, power = display.power,
    generation = display.generation, cue = marker.cue }
end

--- The curve's points, in the order `AddPoint` wants them. Authored entirely by cap out of
--- one number the client gave us; the secret it will be evaluated against never appears here.
---
--- ⚠ THE SCALE OF `UnitPowerPercent` IS UNMEASURED — its documentation says "a floating point
--- percentage value", which is 0..1 on one reading and 0..100 on the other, and cap cannot
--- read the result back to find out. So the curve encodes BOTH: it rises at the break, falls
--- again just past 1, and rises a second time at the hundredfold break. `Step` holds the
--- previous point's value, so under a 0..1 scale only the first rise is ever reached, and
--- under 0..100 the sliver between them needs a Fury of 1.5 — unreachable on an integer bar.
--- Neither reading draws a wrong badge. Collapse this to two points once the flight settles it.
function Channel.PowerPoints(brk)
  if not brk then return nil end
  return { { 0, 0 }, { brk, 1 }, { 1.001, 0 }, { brk * 100, 1 } }
end

--- Arm the graded cue: one curve, built once, evaluated by the client against a secret it
--- never hands back. Feature-gated whole — a client missing any piece takes the inert path,
--- which draws no badge rather than a wrong one.
function Channel.ArmPower(plan)
  if not plan then return nil, "refused" end
  local powerType = Enum and Enum.PowerType and Enum.PowerType[plan.power]
  if type(powerType) ~= "number" then return nil, "refused" end
  if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum.LuaCurveType
      and Enum.LuaCurveType.Step and UnitPowerPercent and UnitPowerMax) then
    return nil, "refused"
  end

  local okMax, max = pcall(UnitPowerMax, "player", powerType)
  local points = Channel.PowerPoints(okMax and Channel.PowerBreak(plan.generation, max) or nil)
  if not points then return nil, "refused" end

  local curve
  local ok = pcall(function()
    curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    for _, point in ipairs(points) do curve:AddPoint(point[1], point[2]) end
  end)
  if not (ok and curve) then return nil, "refused" end
  return { kind = plan.kind, curve = curve, powerType = powerType, cue = plan.cue }, "armed"
end

--- Evaluate the armed curve. The client reads the secret power, applies cap's points, and
--- returns the mapped result — which is itself secret. Returned as `ok, value` so no caller
--- ever has to compare the value, not even against nil: it goes straight into a setter.
function Channel.PowerAlpha(armed)
  if not (armed and armed.curve and UnitPowerPercent) then return false end
  local ok, value = pcall(UnitPowerPercent, "player", armed.powerType, false, armed.curve)
  if not ok then return false end
  return true, value
end

-- ---------------------------------------------------------------------------
-- Sealed cooldown range — render-shelf V10, the same curve over a duration object
-- ---------------------------------------------------------------------------

--- The instant a cooldown must have started for the hold to mean anything. Below it the
--- dependency is READY, not imminent, and a hold would be telling the player to wait for
--- something already waiting for them.
local LIVE = 0.001

--- Pure dependency binding for the range hold: draw the cue while another ability's cooldown
--- is running AND ends within `within` seconds.
function Channel.HoldPlan(marker)
  local display = marker and marker.display
  if not (display and display.kind == "sealed-cooldown-range" and marker.cue
      and type(display.ability) == "string" and type(display.within) == "number"
      and display.within > LIVE) then
    return nil
  end
  return { kind = display.kind, ability = display.ability,
    within = display.within, cue = marker.cue }
end

--- Three points, which is the band: nothing at zero remaining (the dependency is up, not
--- imminent), the cue while the clock runs inside the window, nothing again beyond it. Step
--- holds the previous point's value, so each x is where the value CHANGES.
function Channel.HoldPoints(within)
  if type(within) ~= "number" or within <= LIVE then return nil end
  return { { 0, 0 }, { LIVE, 1 }, { within, 0 } }
end

--- Arm the range hold. The duration object is fetched per evaluation rather than kept: it
--- describes one cooldown instance, and the next press starts another.
function Channel.ArmHold(plan, abilities)
  if not plan then return nil, "refused" end
  local ability = abilities and abilities[plan.ability]
  if not (ability and type(ability.spell) == "number") then return nil, "refused" end
  if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType
      and Enum.LuaCurveType.Step and Enum.DurationTimeModifier
      and Enum.DurationTimeModifier.RealTime
      and C_Spell and C_Spell.GetSpellCooldownDuration) then
    return nil, "refused"
  end

  local points = Channel.HoldPoints(plan.within)
  if not points then return nil, "refused" end

  local curve
  local ok = pcall(function()
    curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    for _, point in ipairs(points) do curve:AddPoint(point[1], point[2]) end
  end)
  if not (ok and curve) then return nil, "refused" end
  return { kind = plan.kind, curve = curve, spell = ability.spell, cue = plan.cue }, "armed"
end

--- Evaluate the hold. `ignoreGCD` is true and load-bearing: without it every global cooldown
--- would read as a dependency about to come up, and the cue would light on every press.
function Channel.HoldAlpha(armed)
  if not (armed and armed.curve and C_Spell and C_Spell.GetSpellCooldownDuration) then
    return false
  end
  local okDur, duration = pcall(C_Spell.GetSpellCooldownDuration, armed.spell, true)
  if not (okDur and duration and duration.EvaluateRemainingDuration) then return false end
  local ok, value = pcall(duration.EvaluateRemainingDuration, duration, armed.curve,
    Enum.DurationTimeModifier.RealTime)
  if not ok then return false end
  return true, value
end

-- ---------------------------------------------------------------------------
-- The graded seam — two sources, one sink
-- ---------------------------------------------------------------------------

--- A graded cue is one whose visibility the CLIENT decides: cap authors a curve, the client
--- evaluates it against a secret, and the result is written into an alpha. Two sources so far
--- — a resource percentage and a cooldown remaining — sharing only the curve and the sink,
--- which is the whole of what they have in common.
function Channel.GradedPlan(marker)
  return Channel.PowerPlan(marker) or Channel.HoldPlan(marker)
end

function Channel.ArmGraded(plan, abilities)
  if not plan then return nil, "refused" end
  if plan.kind == "sealed-cooldown-range" then return Channel.ArmHold(plan, abilities) end
  return Channel.ArmPower(plan)
end

function Channel.GradedAlpha(armed)
  if armed and armed.kind == "sealed-cooldown-range" then return Channel.HoldAlpha(armed) end
  return Channel.PowerAlpha(armed)
end

--- Acquire one sealed display while unrestricted. The only public states are the audit
--- states: offered, armed, refused. None claims whether a secret-driven glyph appeared.
function Channel.Arm(host, marker, abilities)
  local plan = Channel.Plan(marker, abilities)
  if not plan or not host or InCombatLockdown() then return nil, "refused" end
  if not (C_AddOns and C_AddOns.LoadAddOn) then return nil, "refused" end

  local okLoad = pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
  if not okLoad then return nil, "refused" end

  local container
  local ok = pcall(function()
    container = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
    container:SetAllPoints(host)
    container:AddAuraSlot(marker.id, "HELPFUL", {
      candidateFilters = {
        includeSpellIDs = { [plan.spell] = true },
        isFromPlayerOrPlayerPet = true,
      },
      initializeFrame = function(button)
        button:SetAllPoints(container)
        local count = button:CreateFontString(nil, "OVERLAY")
        count:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        count:SetPoint("TOP", button, "TOP", 0, 1)
        button:SetApplicationCount(count)
      end,
    })
    container:SetUnit("player")
    container:UpdateAllAuras()
  end)
  if not ok then
    if container then container:Hide() end
    return nil, "refused"
  end
  return container, "armed"
end
