-- Channel.lua — declarative, one-way displays for facts Lua is not allowed to read.
-- AuraContainer owns acquisition and writes the secret application count directly into
-- our leaf FontString. CAP never receives, compares, type-checks, or reads the value back.
local ADDON, ns = ...

local issecretvalue = issecretvalue

ns.Channel = ns.Channel or {}
local Channel = ns.Channel

--- Pure dependency binding for the BANDED COUNT (render-shelf.md V16/V17). The returned plan is
--- deliberately display vocabulary, not a Signal term; tests use this same path as the live armer.
---
--- ⚠ It validates the SHAPE and never the value. In the client the count is secret: cap hands
--- over a rule and the client alone decides which band fired.
function Channel.Plan(marker, abilities)
  local display = marker and marker.display
  local ability = display and abilities and abilities[display.ability]
  if not (display and display.kind == "sealed-count-bands"
      and ability and type(ability.spell) == "number") then
    return nil
  end
  -- `BandStyle` is the shelf's own table unless `/cap band` is nudging it mid-flight.
  local rules = Channel.CountRules(display.bands, Channel.BandStyle())
  if not rules then return nil end
  return {
    kind = display.kind, spell = ability.spell, rules = rules, bands = display.bands,
    unit = ability.unit or "player", sink = "SetApplicationCount",
  }
end

--- One inline texture escape, in the long form the client places rather than flows. `dx`/`dy`
--- are optional; without them the mark sits where the text would.
local function escape(root, name, size, dx, dy)
  local where = (dx and dy) and (":" .. dx .. ":" .. dy) or ""
  return ("|T%s%s:%d:%d%s|t"):format(root, name, size, size, where)
end

--- `|cAARRGGBB…|r` from a shelf triple. Used for TEXT ONLY.
---
--- ⚠ **It does not reach art** `[client 2026-08-22]`. A colour escape tints the band's text and
--- leaves an inline `|T…|t` at full white — measured as an A/B against `SetVertexColor` on the
--- same stripe sheet, which came out correctly red two icons away. So every mark below names a
--- **pre-tinted** file and only the numeral is wrapped.
local function tint(rgb, body)
  if body == "" or not rgb then return body end
  return ("|cff%02x%02x%02x%s|r"):format(
    math.floor(rgb[1] * 255 + 0.5), math.floor(rgb[2] * 255 + 0.5),
    math.floor(rgb[3] * 255 + 0.5), body)
end

--- The pre-tinted crop for one art and one polarity. The hue is IN THE FILE because there is no
--- draw-time channel that reaches it: the sink owns a FontString and the art inside it is named
--- by a path, so there is no texture object to `SetVertexColor` and no escape that recolours one.
--- `capart export count` generates the pair.
local function hued(name, polarity)
  return name .. (polarity == "negative" and "_neg" or "_pos")
end


--- The authored bands as the list `NumericRuleFormatter:SetBreakpoints` wants: one
--- `{ threshold, format }` per breakpoint, in rising order. Pure — it turns what a catalog MEANT
--- into arguments for a client object and reads nothing back, which is the same shape
--- `PowerPoints` and `HoldPoints` have and for the same reason.
---
--- ⚠ THIS IS WHERE THE PIXELS ENTER, and it is the only place they do. A catalog names `draw`,
--- `polarity` and `hatch`; the format string — which texture, at what size, at what offset, in
--- what hue — is built here out of `ns.Style.count`, which is generated from render-shelf.md
--- Part 6. `style` is an argument rather than a global read so the builder stays pure and a test
--- can hand it a table.
---
--- ⚠ `threshold` is the MINIMUM input a rule applies to, so a value ON a threshold takes the
--- UPPER band. Rising order is required rather than sorted here: a table that does not rise is a
--- table whose author believed something false about what draws, and silently repairing it would
--- hide that.
---
--- ⚠ Several escapes in ONE band is the whole trick, not an optimisation. There is exactly one
--- count FontString per button, so a hatch across the face, a plate, a mark on the corner and a
--- numeral all have to come out of one string — and the band above the threshold clears every
--- one of them together.
function Channel.CountRules(bands, style, size)
  style = style or (ns.Style or {}).count
  if not style or type(bands) ~= "table" or #bands == 0 then return nil end
  local root = style.texture_root or ""
  local out, floor = {}, nil
  for _, band in ipairs(bands) do
    if type(band) ~= "table" or type(band.threshold) ~= "number"
      or type(band.draw) ~= "string" then
      return nil
    end
    if floor and band.threshold <= floor then return nil end
    floor = band.threshold

    local wantsMark = band.draw == "mark" or band.draw == "count+mark"
    local wantsCount = band.draw == "count" or band.draw == "count+mark"
    -- Hue carries POLARITY and only polarity (render-shelf.md V5.1), so one band spends one
    -- colour on everything it says — except the plate, whose job is contrast and which is
    -- therefore the badge stack's own dark disc in both polarities.
    local rgb = (band.polarity == "negative") and style.low_rgb or style.rgb
    local plate = ns.Style and ns.Style.badges and ns.Style.badges.plate

    local body = ""
    if band.hatch then
      -- ⚠ A DIFFERENT ROOT. The hatch is V11's own sheet under `Media/`, where the plate and the
      -- mark are badge art under `Media/badges/`. Both names are injected by `capart export lua`
      -- rather than written in the shelf, so a rename cannot leave a band pointing at nothing.
      --
      -- ⚠ AND AN OFFSET, because an inline texture sits on the TEXT BASELINE rather than in the
      -- middle of the string's box `[client 2026-08-22]`. A mark as tall as the icon therefore
      -- rises far above the line it is nominally centred on. `hatch_offset_px` pulls it back down
      -- onto the button; it is one number and `/cap band` tunes it live.
      local ox, oy = 0, 0
      if style.hatch_offset_px then
        ox, oy = style.hatch_offset_px[1], style.hatch_offset_px[2]
      end
      body = body .. escape(style.hatch_root or root,
        hued(style.hatch, band.polarity), size or style.hatch_px, ox, oy)
    end
    if wantsMark then
      -- The plate goes down first and the glyph over it, both named by THIS band — which is what
      -- makes the whole badge ride the band. A plate cap drew as an ordinary texture would stay
      -- on the row at every value the band blanks (render-shelf.md V16).
      --
      -- ⚠ The plate carries NO polarity and is one file rather than a pair: its job is contrast,
      -- and hue carries polarity and only polarity (V5.1).
      if plate then
        body = body .. escape(root, style.plate, style.plate_px,
          style.plate_offset_px[1], style.plate_offset_px[2])
      end
      body = body .. escape(root, hued(style.mark, band.polarity), style.mark_px,
        style.mark_offset_px[1], style.mark_offset_px[2])
    end
    -- The numeral is the ONE thing a colour escape still reaches, because it is text.
    if wantsCount then body = body .. tint(rgb, "%d") end

    out[#out + 1] = { threshold = band.threshold, format = body }
  end
  if out[1].threshold ~= 0 then return nil end
  return out
end

--- Pure dependency binding for the SEALED RADIAL (render-shelf.md V18). `max` reaches the client
--- as `maxApplications`, which is what makes the clamp turn "or more" into "full".
function Channel.BarPlan(marker, abilities)
  local display = marker and marker.display
  local ability = display and abilities and abilities[display.ability]
  if not (display and display.kind == "sealed-count-bar"
      and type(display.max) == "number" and display.max > 0
      and ability and type(ability.spell) == "number") then
    return nil
  end
  return {
    kind = display.kind, spell = ability.spell, max = display.max,
    full = display.full and true or false,
    unit = ability.unit or "player", sink = "SetApplicationBar",
  }
end

--- Pure dependency binding for the REFRESH WINDOW (render-shelf.md V19). There is no threshold
--- to bind: the client computes `GetRefreshExtendedDuration - GetAuraBaseDuration` itself, per
--- spell, and calls SetShown on whatever Region cap registered.
function Channel.WindowPlan(marker, abilities)
  local display = marker and marker.display
  local ability = display and abilities and abilities[display.ability]
  if not (display and display.kind == "sealed-refresh-window"
      and ability and type(ability.spell) == "number") then
    return nil
  end
  return {
    kind = display.kind, spell = ability.spell,
    unit = ability.unit or "player", sink = "AddPandemicRegion",
  }
end

--- The CONTAINER seam, the sibling of `GradedPlan`: three sinks that all need an AuraContainer
--- slot, against the two graded ones that need only a curve. A marker is at most one of them.
function Channel.ContainerPlan(marker, abilities)
  return Channel.Plan(marker, abilities)
    or Channel.BarPlan(marker, abilities)
    or Channel.WindowPlan(marker, abilities)
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

--- The same curve authored the other way round. Some priority terms are an ABSOLUTE resource
--- level ("press this while Fury is at or under 100") rather than "one more press overflows",
--- and a generation amount cannot express one without smuggling a hardcoded max into the
--- catalog. The break is then the threshold as a fraction of the client's max — cap still
--- authors exactly one number and performs exactly one division, and still never learns which
--- side the secret fell on. Pure; nil is the inert path.
function Channel.ThresholdBreak(threshold, max)
  if issecretvalue and (issecretvalue(threshold) or issecretvalue(max)) then return nil end
  if type(threshold) ~= "number" or type(max) ~= "number" then return nil end
  if max <= 0 or threshold <= 0 or threshold >= max then return nil end
  return threshold / max
end

--- Pure dependency binding for the graded cue, the sibling of `Channel.Plan`. A sealed power
--- display draws its cue and nothing else, so a plan without one is not a plan. Exactly one of
--- `generation` and `threshold` authors the break; both or neither is not a plan either.
function Channel.PowerPlan(marker)
  local display = marker and marker.display
  if not (display and display.kind == "sealed-power-percent" and marker.cue
      and type(display.power) == "string") then
    return nil
  end
  local generation = type(display.generation) == "number" and display.generation or nil
  local threshold = type(display.threshold) == "number" and display.threshold or nil
  if (generation == nil) == (threshold == nil) then return nil end
  return { kind = display.kind, power = display.power,
    generation = generation, threshold = threshold, cue = marker.cue }
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
  local brk
  if okMax then
    brk = plan.threshold and Channel.ThresholdBreak(plan.threshold, max)
      or Channel.PowerBreak(plan.generation, max)
  end
  local points = Channel.PowerPoints(brk)
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

--- Pure dependency binding for the range hold. Two senses, exactly one per marker:
---   `within` — the cue lights while the dependency's cooldown is running and ends INSIDE the
---              window. "It is about to be up, so wait for it."
---   `beyond` — the cue lights while the cooldown is running and has AT LEAST that long left.
---              "It is nowhere near, so this is not its moment."
--- Both are the same Step curve read at a different x; neither is ever read back.
function Channel.HoldPlan(marker)
  local display = marker and marker.display
  if not (display and display.kind == "sealed-cooldown-range" and marker.cue
      and type(display.ability) == "string") then
    return nil
  end
  local within = type(display.within) == "number" and display.within > LIVE and display.within
  local beyond = type(display.beyond) == "number" and display.beyond > LIVE and display.beyond
  if (within and beyond) or not (within or beyond) then return nil end
  return { kind = display.kind, ability = display.ability,
    within = within or nil, beyond = beyond or nil, cue = marker.cue }
end

--- Three points, which is the window: nothing at zero remaining (the dependency is up, not
--- imminent), the cue while the clock runs inside the window, nothing again beyond it. Step
--- holds the previous point's value, so each x is where the value CHANGES.
function Channel.HoldPoints(within)
  if type(within) ~= "number" or within <= LIVE then return nil end
  return { { 0, 0 }, { LIVE, 1 }, { within, 0 } }
end

--- TWO points, which is the whole of the inverted sense — and the answer to whether this curve
--- can say "far away" as well as "nearly here". It can, and it needs no new machinery: Step
--- holds the LAST point's value out to infinity, so a rise at the threshold with nothing after
--- it lights for every remaining time at or past it.
---
--- Zero still reads nothing, and that is not incidental: a dependency that is READY is not far
--- away, and the one shape this must never take is a badge that lights on a cooldown which has
--- come back.
function Channel.BeyondPoints(beyond)
  if type(beyond) ~= "number" or beyond <= LIVE then return nil end
  return { { 0, 0 }, { beyond, 1 } }
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

  local points = plan.beyond and Channel.BeyondPoints(plan.beyond)
    or Channel.HoldPoints(plan.within)
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

--- The banded count's FontString (render-shelf.md V16/V17). ⚠ EVERY number is `ns.Style.count`'s
--- — the font, the size, the outline — because `surfaces.count_tile` declares all three and a
--- hardcoded `"Fonts\\FRIZQT__.TTF", 14, "OUTLINE"` here was the style saying one thing and the
--- client drawing another.
local function countSink(button, plan, style)
  local count = button:CreateFontString(nil, "OVERLAY")
  if not count:SetFont("Fonts\\" .. style.font, style.size, style.outline) then
    count:SetFontObject("NumberFontNormal")
  end
  count:SetPoint("CENTER", button, "CENTER", 0, 0)
  -- The static floor, and it needs no markup: the sink adds `Text` and `Shown` and never
  -- `VertexColor`, so this survives even if a later build starts sanitising escapes.
  count:SetTextColor(style.rgb[1], style.rgb[2], style.rgb[3])

  local formatter = C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
    and C_StringUtil.CreateNumericRuleFormatter()
  if not formatter then return false end
  -- ⚠ THE ESCAPE IS SIZED FROM THE REAL BUTTON, not from the shelf's nominal icon. An inline
  -- texture carries a literal size in the format string, so a full-icon mark authored at 56 draws
  -- at 56 on a Cooldown Manager the player has configured to 42 — which is exactly the overhang
  -- the first flight photographed. The token is the FALLBACK for a width that reads secret.
  local w = ns.Paint.Extent(button)
  -- A live `/cap band` size wins over the measurement: the whole point of the instrument is to
  -- try a number the measurement would not have produced.
  local nudge = Channel.BandOverride()
  formatter:SetBreakpoints(
    Channel.CountRules(plan.bands, Channel.BandStyle(), (nudge and nudge.size) or w)
    or plan.rules)
  button:SetApplicationCount(count, { formatter = formatter })

  -- ⚠ MOTION FOR FREE, GATED ON NOTHING. The sink owns `Text` and `Shown`; the animation channel
  -- is still cap's, so a loop created here and never stopped is INVISIBLE while the band draws
  -- nothing and the mark arrives already breathing. One motion per region (render-shelf V16).
  if style.pulse then
    local group = ns.Paint.Breathe(count, style.pulse)
    if group then group:Play() end
  end
  return true
end

--- The sealed radial (render-shelf.md V18). Only `BarValue` is sealed — the aspect goes on the
--- value, not the widget — so the texture, the size, the render mode and the colour below are
--- ordinary setup calls the client never touches.
local function barSink(button, plan, style, badges)
  local bar = CreateFrame("StatusBar", nil, button)
  local d = (badges.diameter_pct / 100) * ns.Style.surfaces.icon_px - 2 * style.inset_px
  bar:SetSize(d, d)
  bar:SetPoint("TOPRIGHT", button, "TOPRIGHT", ns.Paint.StackOffset(0))

  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints(bar)
  track:SetColorTexture(style.track_rgb[1], style.track_rgb[2], style.track_rgb[3],
    style.track_alpha)
  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetColorTexture(style.rgb[1], style.rgb[2], style.rgb[3], style.alpha)
  bar:SetStatusBarTexture(fill)
  -- A client without the render mode gets the linear fill rather than nothing at all: the value
  -- is the fact, and the circle is how it is drawn.
  if bar.SetRenderMode and Enum and Enum.StatusBarRenderMode then
    pcall(bar.SetRenderMode, bar, Enum.StatusBarRenderMode.Radial)
  end
  button:SetApplicationBar(bar, { maxApplications = plan.max })
  return true
end

--- The refresh window (render-shelf.md V19). A FRAME, not a texture, because the client seals its
--- `Shown` and nothing else — so plate and glyph parented under it appear and vanish together on
--- Blizzard's own window, with cap authoring no threshold at all.
local function windowSink(button, style, badges)
  local region = CreateFrame("Frame", nil, button)
  local d = (badges.diameter_pct / 100) * ns.Style.surfaces.icon_px
  region:SetSize(d, d)
  region:SetPoint("TOPRIGHT", button, "TOPRIGHT", ns.Paint.StackOffset(0))

  local plate = region:CreateTexture(nil, "OVERLAY", nil, 6)
  plate:SetTexture(badges.texture_root .. badges.plate.texture .. ".tga", nil, nil, "TRILINEAR")
  plate:SetVertexColor(badges.plate.rgb[1], badges.plate.rgb[2], badges.plate.rgb[3])
  plate:SetAlpha(badges.plate.alpha)
  plate:SetSize(d * badges.plate.scale, d * badges.plate.scale)
  plate:SetPoint("CENTER")

  local sprite = region:CreateTexture(nil, "OVERLAY", nil, 7)
  sprite:SetTexture(style.texture_root .. style.frame .. ".tga", nil, nil, "TRILINEAR")
  sprite:SetVertexColor(style.rgb[1], style.rgb[2], style.rgb[3])
  sprite:SetSize(style.size_px, style.size_px)
  sprite:SetPoint("CENTER")

  -- Gated for free, the same way V16's is: the client hides the region, so a loop running
  -- forever on it is invisible until the window opens.
  if style.pulse then
    local group = ns.Paint.Breathe(region, style.pulse)
    if group then group:Play() end
  end
  button:AddPandemicRegion(region)
  return true
end

--- Acquire one sealed display while unrestricted. The only public states are the audit
--- states: offered, armed, refused. None claims whether a secret-driven glyph appeared.
---
--- ⚠ THE SINK IS CHOSEN BY `plan.kind` AND BY NOTHING ELSE. Three kinds, three client objects,
--- one acquisition path — because what varies between them is which widget the client is handed,
--- not how the slot is built.
function Channel.Arm(host, marker, abilities)
  local plan = Channel.ContainerPlan(marker, abilities)
  if not plan or not host or InCombatLockdown() then return nil, "refused" end
  if not (C_AddOns and C_AddOns.LoadAddOn) then return nil, "refused" end

  local okLoad = pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
  if not okLoad then return nil, "refused" end

  local container, built
  local ok = pcall(function()
    container = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
    container:SetAllPoints(host)
    container:AddAuraSlot(marker.id, plan.unit == "player" and "HELPFUL" or "HARMFUL", {
      candidateFilters = {
        includeSpellIDs = { [plan.spell] = true },
        isFromPlayerOrPlayerPet = true,
      },
      initializeFrame = function(button)
        button:SetAllPoints(container)
        if plan.kind == "sealed-count-bands" then
          built = countSink(button, plan, ns.Style.count)
        elseif plan.kind == "sealed-count-bar" then
          built = barSink(button, plan, ns.Style.arc, ns.Style.badges)
        elseif plan.kind == "sealed-refresh-window" then
          built = windowSink(button, ns.Style.pandemic, ns.Style.badges)
        end
      end,
    })
    container:SetUnit(plan.unit)
    container:UpdateAllAuras()
  end)
  if not ok then
    if container then container:Hide() end
    return nil, "refused"
  end
  -- ⚠ `built` is false only when a client object cap needs was absent — a missing formatter
  -- factory, say. It is NOT a claim about whether anything DREW: cap never learns that.
  if built == false then
    container:Hide()
    return nil, "refused"
  end
  return container, "armed"
end

-- ---------------------------------------------------------------------------
-- The band nudge — a FLIGHT INSTRUMENT, not a setting
-- ---------------------------------------------------------------------------

--- `/cap band [x y [size]]` — move and resize the band's hatch while looking at it.
---
--- ⚠ THIS IS NOT A PLAYER SETTING AND MUST NOT BECOME ONE. `render-shelf.md` owns every number
--- cap draws with, and the shelf is regenerated into `Style.lua` — an override that survived a
--- session would be the style saying one thing and the client drawing another, which is the
--- exact failure the generation pipeline exists to prevent. So it lives in memory only, it
--- prints the value to paste back into Part 6, and a `/reload` forgets it.
---
--- It exists because the alternative is a release per guess. An inline escape sits on the text
--- baseline and cannot tile, so its placement is arithmetic nobody has done before — three
--- numbers, judged by eye, in a client. One flight with a nudge beats five flights without.
local override

function Channel.BandOverride()
  return override
end

--- The style the band builder should use right now: the shelf's, or the shelf's with the
--- nudge applied on top. Pure, so the override never leaks into the generated table.
function Channel.BandStyle()
  local base = (ns.Style or {}).count
  if not (base and override) then return base end
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  out.hatch_offset_px = { override.x, override.y }
  out.hatch_px = override.size or base.hatch_px
  return out
end

if ns.RegisterCommand then
  ns.RegisterCommand{
    name = "band", order = 46, args = "[x y [size]] | off",
    desc = "Nudge the sealed band's hatch while looking at it (flight instrument, not saved)",
    handler = function(rest)
      local arg = (rest or ""):lower()
      local base = (ns.Style or {}).count
      if not base then return ns.Emit("no count style loaded.") end
      if arg == "off" then
        override = nil
        ns.Emit("band nudge cleared — back to the shelf's own numbers. /reload to re-arm.")
        return
      end
      if arg == "" then
        local o = override or { x = base.hatch_offset_px[1], y = base.hatch_offset_px[2],
                                size = base.hatch_px }
        ns.Emit(("band hatch: x=%d y=%d size=%d%s"):format(
          o.x, o.y, o.size or base.hatch_px, override and "  (nudged)" or "  (the shelf's)"))
        ns.Emit("usage: /cap band <x> <y> [size]   ·   /cap band off")
        return
      end
      local x, y, size = arg:match("^(-?%d+)%s+(-?%d+)%s*(%d*)$")
      if not x then
        return ns.Emit("usage: /cap band <x> <y> [size]   ·   /cap band off")
      end
      if InCombatLockdown() then
        return ns.Emit("the band re-arms out of combat only.")
      end
      override = { x = tonumber(x), y = tonumber(y), size = tonumber(size) }
      ns.Emit(("band hatch → x=%d y=%d size=%d. Paste into render-shelf.md Part 6 as "
        .. "count.hatch_offset_px = [%d, %d] and count.hatch_px = %d once it looks right.")
        :format(override.x, override.y, override.size or base.hatch_px,
                override.x, override.y, override.size or base.hatch_px))
      if ns.Overlay and ns.Overlay.Rearm then ns.Overlay.Rearm() end
    end,
  }
end
