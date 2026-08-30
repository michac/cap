-- Channel.lua — declarative, one-way displays for facts Lua is not allowed to read.
-- AuraContainer owns acquisition and writes the secret application count directly into
-- our leaf FontString. CAP never receives, compares, type-checks, or reads the value back.
local ADDON, ns = ...

local issecretvalue = issecretvalue

ns.Channel = ns.Channel or {}
local Channel = ns.Channel

-- `SetTimerDuration(d, interpolation, direction)`. ⚠ `Enum.StatusBarInterpolation.None` is NOT
-- in the generated enum — only `Immediate` and `ExponentialEaseOut` — so nothing here reaches
-- for it; the literals are the values cooldown-manager.md §7's recipe names.
local IMMEDIATE = (Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate)
  or 0
local REMAINING = 1   -- TimerDirection.RemainingTime

-- Cap's own mark where it has no number. NEVER a stand-in for zero: that answer is the client's.
local NO_NUMBER = "--"

-- ---------------------------------------------------------------------------
-- The duration seam — one object, two client sinks, no readback
-- ---------------------------------------------------------------------------

-- Named apart from the `formatter` locals the band sinks build: those are per-slot
-- NumericRuleFormatters, this is the one shared seconds formatter.
local secondsFmt

--- Built once and kept. `false` records that the route is unavailable, so a caller can say so
--- rather than re-asking on every pass.
function Channel.SecondsFormatter()
  if secondsFmt ~= nil then return secondsFmt or nil end
  if not (C_StringUtil and C_StringUtil.CreateSecondsFormatter) then
    secondsFmt = false
    return nil
  end
  local ok, f = pcall(C_StringUtil.CreateSecondsFormatter)
  secondsFmt = (ok and f ~= nil) and f or false
  return secondsFmt or nil
end

--- A spell's duration object, or nil plus the reason. Nil with NO reason is a spell with
--- nothing remaining: `MayReturnNothing` is an answer here, not a failure — and it is the
--- client's answer, so nothing compares it to a number.
---
--- ⚠ `ignoreGCD` is TRUE, and it is load-bearing: with false every bar fills for 1.5 s after
--- every cast. (The API takes the flag either way; this is the addon's use of it.)
function Channel.Duration(spellID)
  if not (C_Spell and C_Spell.GetSpellCooldownDuration) then return nil, "refused" end
  if type(spellID) ~= "number" then return nil, "refused" end
  local ok, d = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
  if not ok then return nil, "refused" end
  return d
end

--- The countdown string. It is SECRET, so cap can neither read it back nor dedup on it: this is
--- written on every pass a display is armed. Nil means cap could not build one — never that the
--- remaining time is zero, an answer that belongs to the client and does not come back.
function Channel.RemainingText(d)
  local fmt = Channel.SecondsFormatter()
  if not fmt then return nil end
  -- `modifier` is `Nilable = false` WITH a `Default`, so it goes in explicitly (§4.6).
  local mod = Enum and Enum.DurationTimeModifier and Enum.DurationTimeModifier.RealTime
  if mod == nil then return nil end
  local ok, s = pcall(function() return d:FormatRemainingDuration(fmt, mod) end)
  if not ok or s == nil then return nil end
  return s
end

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
  -- ⚠ NO RULES ARE BUILT HERE ANY MORE. A banded count takes one slot per element and each
  -- element's breakpoints are built at arm time, when the button's real width is measurable. What
  -- the plan does instead is PROVE the table can produce every element it claims — a shape error
  -- has to refuse the plan, not survive to the point where one slot silently draws nothing.
  local elements = Channel.CountElements(display.bands)
  if #elements == 0 then return nil end
  for _, element in ipairs(elements) do
    if not Channel.CountRules(display.bands, Channel.BandStyle(), nil, element) then return nil end
  end
  return {
    kind = display.kind, spell = ability.spell, bands = display.bands, elements = elements,
    unit = ability.unit or "player", sink = "SetApplicationCount",
  }
end

--- One inline texture escape, in the long form the client places rather than flows. `dx`/`dy`
--- are optional; without them the mark sits where the text would.
local function escape(root, name, size, dx, dy)
  local where = (dx and dy) and (":" .. dx .. ":" .. dy) or ""
  -- Rounded, not truncated: every size here is a ratio of a measured width, so it arrives
  -- as a float and `%d` would drop a pixel off each one at every icon size.
  local px = math.floor(size + 0.5)
  return ("|T%s%s:%d:%d%s|t"):format(root, name, px, px, where)
end

--- The three escape sizes for an icon width. An escape's size is a LITERAL baked into the band
--- string when the sink is armed, so it is arithmetic on the width the row actually draws at —
--- a frozen number is right at one icon size and wrong at every other. Falls back to the shelf's
--- nominal, which is what `Paint.Extent` hands back for a width that reads secret.
function Channel.CountGeometry(width)
  local nominal = ((ns.Style or {}).surfaces or {}).icon_px
  local w = (type(width) == "number" and width > 0) and width or nominal
  if not (w and ns.Paint and ns.Paint.Ratios) then return nil end
  local r = ns.Paint.Ratios(w)
  return { hatch = w, plate = r.plate, mark = r.sprite }
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
function Channel.CountRules(bands, style, geom, element)
  style = style or (ns.Style or {}).count
  if not style or type(bands) ~= "table" or #bands == 0 then return nil end
  geom = geom or Channel.CountGeometry()
  if not geom then return nil end
  local root = style.texture_root or ""
  local out, floor = {}, nil
  for _, band in ipairs(bands) do
    if type(band) ~= "table" or type(band.threshold) ~= "number"
      or type(band.draw) ~= "string" then
      return nil
    end
    if floor and band.threshold <= floor then return nil end
    floor = band.threshold

    local wantsMark = band.draw == "mark"
    local wantsCount = band.draw == "count"
    -- Hue carries POLARITY and only polarity (render-shelf.md V5.1).
    local rgb = (band.polarity == "negative") and style.low_rgb or style.rgb
    local plate = ns.Style and ns.Style.badges and ns.Style.badges.plate

    -- A hatch means RULED OUT, so it is legal on a NEGATIVE band only (render-shelf.md V16):
    -- a positive band hatching the face is a contradiction wearing pixels, refused rather
    -- than drawn.
    if band.hatch and band.polarity ~= "negative" then return nil end

    local body = ""
    if element == "hatch" then
      if band.hatch then
        -- ⚠ A DIFFERENT ROOT: V11's sheet lives under `Media/`, the badge art under
        -- `Media/badges/`. Both names are injected by `capart export lua`.
        body = escape(style.hatch_root or root, hued(style.hatch, band.polarity), geom.hatch)
      end
    elseif element == "mark" then
      if wantsMark then
        -- The plate carries no polarity — its job is contrast, not polarity — so it is one
        -- pre-tinted file rather than a pair.
        if plate then body = body .. escape(root, style.plate, geom.plate) end
        body = body .. escape(root, hued(style.mark, band.polarity), geom.mark)
      end
    elseif element == "plate" then
      -- The numeral's plate, as its OWN element with the numeral's thresholds: a plate escape
      -- cannot sit under text within one string (the first escape flows, a later one paints
      -- over), so it rides its own slot, built before the numeral's (render-shelf.md V16).
      if wantsCount and plate then body = escape(root, style.plate, geom.plate) end
    elseif element == "count" then
      -- The numeral is the ONE thing a colour escape still reaches, because it is text.
      if wantsCount then body = tint(rgb, "%d") end
    else
      return nil
    end

    out[#out + 1] = { threshold = band.threshold, format = body }
  end
  if out[1].threshold ~= 0 then return nil end
  return out
end

--- V18's whole-bar flip as a band table: blank below max, the full-width pre-tinted red crop
--- at and above it. Pure, like `CountRules`, and for the same reason — a test hands it a table.
--- ⚠ The escape's two size literals are HEIGHT then WIDTH; every other escape in this file is
--- square so the order never showed. `w` is the host extent, `style.height_px` the bar's.
function Channel.BarFlipRules(max, style, w)
  if type(max) ~= "number" or max <= 0 then return nil end
  style = style or (ns.Style or {}).bar
  if not (style and style.full_texture and type(w) == "number" and w > 0) then return nil end
  local crop = ("|T%s%s:%d:%d|t"):format(style.texture_root or "", style.full_texture,
    style.height_px, w)
  return { { threshold = 0, format = "" }, { threshold = max, format = crop } }
end

--- Which elements a band table actually draws, in back-to-front order. One SLOT each.
---
--- ⚠ THIS IS THE FIX FOR THE WIDTH PROBLEM, and it is a platform property rather than a trick.
--- `AuraContainerAuraSlotManagerMixin:UpdateAura` offers **every aura to every slot** — it loops
--- the whole slot list with no consume, and `hasMatchedFilterString` is never flipped inside the
--- loop — while `ShouldIncludeAuraInSlot` evaluates each slot's OWN `filterString` and
--- `candidateFilters` `[T1 src @12.1.0: Blizzard_AuraContainer/Blizzard_AuraContainerSlots.lua —
--- UpdateAura, ShouldIncludeAuraInSlot]`. So several slots filtered to the same spell each take
--- it independently, each gets its own button, and each button takes its own count sink.
---
--- That means a mark no longer has to share a FontString with the marks beside it: one string
--- per element, each anchored where that element belongs, each with its own band table. The
--- ~96px run, the advance-width stacking and the offset arithmetic all go away — they were
--- consequences of forcing four statements through one string, not of the sink.
function Channel.CountElements(bands)
  local wants = {}
  for _, band in ipairs(bands or {}) do
    if band.hatch then wants.hatch = true end
    if band.draw == "mark" then wants.mark = true end
    if band.draw == "count" then wants.count, wants.plate = true, true end
  end
  local out = {}
  -- Back to front: the hatch is a statement about the whole icon, the numeral's plate sits
  -- over it, and the marks sit over both — the digit lands ON its plate (render-shelf.md V16).
  for _, name in ipairs({ "hatch", "plate", "mark", "count" }) do
    if wants[name] then out[#out + 1] = name end
  end
  return out
end

--- Pure dependency binding for the SEALED BAR (render-shelf.md V18). `max` reaches the client
--- as `maxApplications`, which is what makes the clamp turn "or more" into "full". The whole-bar
--- red flip at that value is unconditional and lives in `Channel.Arm`'s own slot: it follows from
--- the KIND, never from a catalog key.
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
    unit = ability.unit or "player", sink = "SetApplicationBar",
  }
end

--- Pure dependency binding for the REFRESH WINDOW (render-shelf.md V19). There is no threshold
--- to bind: the client computes `GetRefreshExtendedDuration - GetAuraBaseDuration` itself, per
--- spell, and calls SetShown on whatever Region cap registered.
function Channel.WindowPlan(marker, abilities)
  local display = marker and marker.display
  local ability = display and abilities and abilities[display.ability]
  if not (display and display.kind == "sealed-pandemic"
      and ability and type(ability.spell) == "number") then
    return nil
  end
  -- `outside_s` is the OPTIONAL other half of the pair (render-shelf.md V19): remaining
  -- seconds at or above it wear the gold do-not-refresh hatch. It is the catalog's own number
  -- — the window itself stays the client's — and a malformed one refuses the plan rather than
  -- arming half a display.
  if display.outside_s ~= nil
    and (type(display.outside_s) ~= "number" or display.outside_s <= 0) then
    return nil
  end
  return {
    kind = display.kind, spell = ability.spell, outside_s = display.outside_s,
    unit = ability.unit or "player", sink = "AddPandemicRegion",
  }
end

--- V20's plan: the proc bar. The slot filters to the proc aura; while it is up the client
--- shows the button and drains the bar off the aura's own duration (SetDurationBar,
--- RemainingTime). cap authors no threshold and reads nothing.
function Channel.ProcBarPlan(marker, abilities)
  local display = marker and marker.display
  local ability = display and abilities and abilities[display.ability]
  if not (display and display.kind == "sealed-proc-bar"
      and ability and type(ability.spell) == "number") then
    return nil
  end
  return { kind = display.kind, spell = ability.spell, unit = ability.unit or "player" }
end

--- The AURA-REMAINING plan (render-shelf.md V21, third supplier): how long an aura has left, as
--- the badge a readable cue would otherwise wear a still clock for. The subject is the ability
--- the MARKER names, not the bound row's — a container's aura always is (`Channel.Plan` and
--- every sibling resolve `abilities[display.ability]`), so this reaches ACROSS ROWS with no new
--- mechanism: Demonbolt's hold on an armed Infernal Bolt draws the Art's own clock.
---
--- ⚠ IT NEEDS A CUE, and that is what separates it from V20's proc bar over the same aura. The
--- bar is a quantity on the bottom edge; this IS the verdict, in the badge's own place, so it
--- takes the cue's hue and level and the sprite for it is not drawn. Without a cue there would be
--- nothing for it to stand in for.
function Channel.AuraRemainingPlan(marker, abilities)
  local display = marker and marker.display
  local ability = display and abilities and abilities[display.ability]
  if not (display and display.kind == "sealed-aura-remaining" and marker.cue
      and ability and type(ability.spell) == "number") then
    return nil
  end
  return { kind = display.kind, spell = ability.spell, unit = ability.unit or "player",
    cue = marker.cue }
end

--- V21's plan: the row's BASE spell cooldown, on a row whose button is something else. While a
--- Grimoire is talented its row spends the whole 120 s wearing the dispel it becomes, and the
--- swipe on it is that dispel's 15 s — `GetSpellCooldownInfo` resolves the display identity
--- first (`cooldown-manager.md` §3.1.1), so the cooldown the reader wants is drawn nowhere.
---
--- ⚠ THE SPELL IS THE BOUND ROW'S `base`, NOT THE DECLARATION'S `spell`, which is why this takes
--- a row where every other plan takes the declared abilities. An entry covering both halves of a
--- choice node binds through `alt` (Imp Lord / Fel Ravager), and the declaration's id is then the
--- wrong half. The declared `ability` still names the SUBJECT, for the reader and for the
--- provenance gate; it is not what gets read.
function Channel.BaseCooldownPlan(marker, row)
  local display = marker and marker.display
  if not (display and display.kind == "sealed-base-cooldown") then return nil end
  local base = row and row.base
  if type(base) ~= "number" then return nil end
  return { kind = display.kind, spell = base }
end

--- The CONTAINER seam, the sibling of `GradedPlan`: five sinks that all need an AuraContainer
--- slot, against the two graded ones that need only a curve. A marker is at most one of them.
--- ⚠ V21 is in NEITHER: it has no aura to filter on and no curve to evaluate, so it is armed
--- straight off its own plan by `Overlay`.
function Channel.ContainerPlan(marker, abilities)
  return Channel.Plan(marker, abilities)
    or Channel.BarPlan(marker, abilities)
    or Channel.WindowPlan(marker, abilities)
    or Channel.ProcBarPlan(marker, abilities)
    or Channel.AuraRemainingPlan(marker, abilities)
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
  if not (within or beyond) then return nil end
  -- BOTH set is the TWO-SIDED band (catalog.md Defeats item 1, closed 2026-08-24): hold while
  -- remaining is inside (beyond, within). The reversed pair is an empty band that would arm
  -- and never draw, so it is refused here exactly as Catalog.Check refuses it.
  if within and beyond and beyond >= within then return nil end
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

--- The TWO-SIDED band: nothing while the dependency is up or nearly up (below `beyond`), the
--- cue while the clock runs inside (beyond, within), nothing again past it. Three points on the
--- same Step curve the one-sided senses use — this is `catalog.md` Defeats item 1's named
--- recipe, built the day a spec needed it (Dreadstalkers rung 6, 2026-08-24). Step holds the
--- previous point's value, so each x is where the value CHANGES.
function Channel.BandPoints(beyond, within)
  if type(beyond) ~= "number" or type(within) ~= "number" then return nil end
  if beyond <= LIVE or within <= beyond then return nil end
  return { { 0, 0 }, { beyond, 1 }, { within, 0 } }
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

  local points = (plan.beyond and plan.within)
      and Channel.BandPoints(plan.beyond, plan.within)
    or plan.beyond and Channel.BeyondPoints(plan.beyond)
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

--- ONE element of a banded count: the FontString the sink is handed, placed by cap.
---
--- ⚠ EVERY number is `ns.Style.count`'s — font, size, outline — because `surfaces.count_tile`
--- declares all three and a hardcoded face here was the style saying one thing and the client
--- drawing another.
---
--- ⚠ THE STRING IS ANCHORED TO THE HOST, NOT THE BUTTON. The sink seals `Text` and `Shown` and
--- nothing else, so placement stays cap's — and anchoring to cap's own row frame means the mark
--- lands correctly however the container chose to lay its button out. `host` is the row, so a
--- full-icon mark is sized from it and a corner mark hangs off its corner.
local function countSink(button, host, plan, style, element)
  local count = button:CreateFontString(nil, "OVERLAY")
  if not count:SetFont("Fonts\\" .. style.font, style.size, style.outline) then
    count:SetFontObject("NumberFontNormal")
  end
  -- The static floor, and it needs no markup: the sink adds `Text` and `Shown` and never
  -- `VertexColor`, so this survives even if a later build starts sanitising escapes.
  count:SetTextColor(style.rgb[1], style.rgb[2], style.rgb[3])

  -- ⚠ Sized in the FONTSTRING'S coordinate space, which is the host's — not screen pixels, and
  -- not the shelf's nominal icon. Every escape size below is a ratio of this one measurement.
  local w = ns.Paint.Extent(host)
  local geom = Channel.CountGeometry(w)
  if not geom then return false end

  -- ⚠ GEOMETRY IS RECORDED, NOT ASSUMED. Two flights were spent nudging an offset that no log
  -- could describe, because nothing wrote down what any of these numbers actually were at the
  -- moment the sink was built. The escape size literal is read in the FONTSTRING'S coordinate
  -- space, so `host` and `button` disagreeing about size or scale silently rescales every mark —
  -- and that disagreement is invisible in a screenshot and invisible in every other stream.
  -- One line per armed element, at arm time. Nothing reads it.
  -- ⚠ IN ITS OWN pcall, AND THAT IS NOT BELT-AND-BRACES. This runs inside `initializeFrame`,
  -- which the caller wraps in ONE pcall around the whole container build — so an error raised
  -- here does not fail the readout, it fails the ARM, and every banded display on the roster
  -- silently refuses. A recorder that can break the thing it observes is worse than no recorder.
  pcall(function()
  if ns.Log and ns.Log.Mark then
    local function n(v)
      if v == nil or issecretvalue(v) or type(v) ~= "number" then return "?" end
      return ("%.1f"):format(v)
    end
    local okH, hostW = pcall(host.GetWidth, host)
    local okHh, hostH = pcall(host.GetHeight, host)
    local okHs, hostS = pcall(host.GetEffectiveScale, host)
    local okBw, btnW = pcall(button.GetWidth, button)
    local okBh, btnH = pcall(button.GetHeight, button)
    local okBs, btnS = pcall(button.GetEffectiveScale, button)
    ns.Log.Mark(("geom %s/%s host:%sx%s hs:%s btn:%sx%s bs:%s size:%s"):format(
      tostring(plan.spell), tostring(element),
      n(okH and hostW), n(okHh and hostH), n(okHs and hostS),
      n(okBw and btnW), n(okBh and btnH), n(okBs and btnS), n(geom.hatch)))
  end
  end)

  if element == "hatch" then
    local ox, oy = 0, 0
    if style.hatch_offset_px then ox, oy = style.hatch_offset_px[1], style.hatch_offset_px[2] end
    count:SetPoint("CENTER", host, "CENTER", ox, oy)
  else
    -- The corner every badge shares (render-shelf.md Part 2.5): the stack is one pixel deep
    -- and the container's frame level is what puts this under the cue badges. `count` sits over
    -- `mark` because the plate is the mark's and the numeral belongs on it.
    count:SetPoint("CENTER", host, "TOPRIGHT", ns.Paint.BadgeCentre(host, 0))
  end

  local formatter = C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
    and C_StringUtil.CreateNumericRuleFormatter()
  if not formatter then return false end
  local rules = Channel.CountRules(plan.bands, style, geom, element)
  if not rules then return false end
  formatter:SetBreakpoints(rules)
  button:SetApplicationCount(count, { formatter = formatter })

  -- ⚠ MOTION FOR FREE, GATED ON NOTHING. The sink owns `Text` and `Shown`; the animation channel
  -- is still cap's, so a loop created here and never stopped is INVISIBLE while the band draws
  -- nothing and the mark arrives already breathing. One motion per region — so only the mark
  -- breathes, never the hatch and never the numeral.
  if style.pulse and element == "mark" then
    local group = ns.Paint.Breathe(count, style.pulse)
    if group then group:Play() end
  end
  return true
end

--- The segmented bar (render-shelf.md V18). Only `BarValue` is sealed — the aspect goes on the
--- value, not the widget — so the size, the colours and the segment ticks below are ordinary
--- setup calls the client never touches. It sits on the HOST's bottom edge, the one surface
--- nothing else on a cap row claims; the whole-bar red flip at full is `flipSink`'s, on a slot
--- of its own.
local function barSink(button, host, plan, style)
  local bar = CreateFrame("StatusBar", nil, button)
  bar:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
  bar:SetHeight(style.height_px)

  ns.Paint.BarFill(bar, style, "barSink")
  -- The segment grid: one tick per application boundary, cap's own track art over the fill,
  -- so a half bar reads as 2 of 4 rather than as "some".
  local w = ns.Paint.Extent(host)
  for i = 1, plan.max - 1 do
    local seg = bar:CreateTexture(nil, "OVERLAY")
    seg:SetColorTexture(style.track_rgb[1], style.track_rgb[2], style.track_rgb[3],
      style.track_alpha)
    seg:SetSize(style.seg_px or 1, style.height_px)
    seg:SetPoint("LEFT", bar, "LEFT", w * i / plan.max, 0)
  end
  button:SetApplicationBar(bar, { maxApplications = plan.max })
  return true
end

--- The whole-bar flip: at full stacks the bar turns the negative red as a warning that procs
--- are about to be wasted. Not the fill recolouring — the value is sealed — but a count band
--- (V16's machinery) drawing the full-width pre-tinted crop at threshold = max, on a slot of
--- its own, anchored over the bar.
local function flipSink(button, host, plan, style)
  local fs = button:CreateFontString(nil, "OVERLAY")
  local face = ns.Style.count
  if not fs:SetFont("Fonts\\" .. face.font, face.size, face.outline) then
    fs:SetFontObject("NumberFontNormal")
  end
  fs:SetPoint("BOTTOM", host, "BOTTOM", 0, 0)

  local formatter = C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
    and C_StringUtil.CreateNumericRuleFormatter()
  if not formatter then return false end
  local rules = Channel.BarFlipRules(plan.max, style, ns.Paint.Extent(host))
  if not rules then return false end
  formatter:SetBreakpoints(rules)
  button:SetApplicationCount(fs, { formatter = formatter })
  return true
end

--- The pandemic pair's OTHER state (render-shelf.md V19): a gold hatch across the face while
--- the DoT is OUTSIDE its refresh window — "do not refresh yet". The pandemic sink cannot be
--- inverted (`ApplyPandemicRegions` calls `SetShown(inWindow)` with no flip), so this rides
--- `SetDurationText` band tables on the aura's remaining SECONDS instead.
--- ⚠ The threshold is therefore the CATALOG's number, not Blizzard's window: the client
--- computes the badge's edge and cap authors this one, and the two can disagree near the
--- boundary. The shelf carries that caveat; this just draws it.
local function outsideSink(button, host, plan)
  local style = ns.Style.count
  local fs = button:CreateFontString(nil, "OVERLAY")
  if not fs:SetFont("Fonts\\" .. style.font, style.size, style.outline) then
    fs:SetFontObject("NumberFontNormal")
  end
  local w = ns.Paint.Extent(host)
  local ox, oy = 0, 0
  if style.hatch_offset_px then ox, oy = style.hatch_offset_px[1], style.hatch_offset_px[2] end
  fs:SetPoint("CENTER", host, "CENTER", ox, oy)

  local formatter = C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
    and C_StringUtil.CreateNumericRuleFormatter()
  if not formatter then return false end
  -- Remaining seconds AT or ABOVE the threshold wear the hatch; below it the band clears and
  -- the window badge's own slot takes over. The gold crop is the count vocabulary's positive
  -- hatch, pre-tinted because an escape cannot be recoloured.
  formatter:SetBreakpoints({
    { threshold = 0, format = "" },
    { threshold = plan.outside_s,
      format = escape(style.hatch_root or style.texture_root or "",
        hued(style.hatch, "positive"), w) },
  })
  button:SetDurationText(fs, { textFormatter = formatter })
  return true
end

--- The pandemic window (render-shelf.md V19). A FRAME, not a texture, because the client seals its
--- `Shown` and nothing else — so plate and glyph parented under it appear and vanish together on
--- Blizzard's own window, with cap authoring no threshold at all.
--- One dial, wherever a dial draws (render-shelf.md V19/V20): a radial StatusBar the CLIENT
--- drains. ⚠ `SetMinMaxValues(0, 1)` FIRST — `ApplyDurationBar` never calls it (§4.8.1
--- finding 3) and without a range the bar draws 0 % forever, with nothing downstream to say so.
local function buildDial(parent, dial, who)
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetSize(dial.size_px, dial.size_px)
  bar:SetPoint("CENTER")
  bar:SetMinMaxValues(0, 1)
  ns.Paint.BarFill(bar, dial, who)
  -- Radial is measured on a SetTimerDuration-driven bar [client 2026-08-21]; a client that
  -- refuses it here gets a linear drain rather than no dial.
  pcall(bar.SetRenderMode, bar,
    Enum.StatusBarRenderMode and Enum.StatusBarRenderMode.Radial or 1)
  return bar
end

--- The badge plate every corner display sits on: one pre-tinted disc, contrast rather than
--- polarity, sized off the host the way every other escape on the row is.
local function badgePlate(region, d)
  local badges = ns.Style.badges
  local plate = region:CreateTexture(nil, "OVERLAY", nil, 6)
  plate:SetTexture(badges.texture_root .. badges.plate.texture .. ".tga", nil, nil, "TRILINEAR")
  plate:SetVertexColor(badges.plate.rgb[1], badges.plate.rgb[2], badges.plate.rgb[3])
  plate:SetAlpha(badges.plate.alpha)
  plate:SetSize(d * badges.plate.scale, d * badges.plate.scale)
  plate:SetPoint("CENTER")
  return plate
end

--- V21 · a cooldown, as a client-drained dial with a legible numeral in it. ONE WIDGET, TWO
--- SUPPLIERS: `sealed-base-cooldown` hands it this row's own base spell (hidden under a
--- transform) and `sealed-cooldown-range` hands it another ability's, named by catalog key. The
--- two resolve their spell differently and deliberately stay separate — see `BaseCooldownPlan`'s
--- warning — and share only what is built here.
---
--- ⚠ NOT AN AURACONTAINER, AND IT CLAIMS NO SLOT OF ITS OWN. Every other sealed display rides an
--- aura and appears and vanishes with it; there is no aura behind "the Grimoire's 120 s is
--- running" — so the widget is cap's, and cap shows and hides it off a readable gate
--- (`baseoncd`) or writes the client's own curve into its alpha (the band). What stays sealed is
--- the NUMBER: every getter on the duration object is secret (§4.8.4), so the object goes
--- straight into `SetTimerDuration` and `FormatRemainingDuration` and cap never learns a second
--- of it.
---
--- ⚠ `level` is the FRAME-LEVEL OFFSET above the host, and the caller owns it: a dial whose
--- marker declares a cue takes THAT CUE'S level (`Paint.CueLevel`) because it IS the badge for
--- it; a dial with no cue takes a corner level below the badge stack.
---
--- ⚠ The FontString is a LEAF (§4.8.1 finding 10): `SetText` with a secret marks the string AND
--- its dependent anchoring, so it is anchored TO the region and nothing is ever anchored to it.
function Channel.ArmCooldownDial(host, level)
  local style = ns.Style.basecd
  if not (host and style) or InCombatLockdown() then return nil end
  -- An unpinned host has no rect, and the diameter below is a ratio of one. `Overlay` retries.
  local okRect, valid = pcall(host.IsRectValid, host)
  if not okRect or valid ~= true then return nil end

  local built
  local region, bar, text
  local ok = pcall(function()
    local d = ns.Paint.Geometry(host).diameter
    region = CreateFrame("Frame", nil, host)
    region:SetSize(d, d)
    region:SetPoint("TOPRIGHT", host, "TOPRIGHT", ns.Paint.StackOffset(host, 0))
    ns.Paint.LevelAbove(region, host, level or ns.Paint.Z.corner)
    badgePlate(region, d)

    -- ⚠ THE RANGE GOES IN HERE, and `buildDial` is where it happens: it calls
    -- `SetMinMaxValues(0, 1)` at build time, which is strictly before any `SetTimerDuration`
    -- in `Update` below. ORDER IS THE WHOLE THING (§4.8.1 finding 3) — a correct duration on a
    -- bar with no range draws at 0 % width, with no error and nothing downstream to say so.
    -- There is exactly one such call on this bar and it is that one.
    bar = buildDial(region, style.dial, "baseCooldownSink")

    text = region:CreateFontString(nil, "OVERLAY")
    if not text:SetFont("Fonts\\" .. style.font, style.size, style.outline) then
      text:SetFontObject("NumberFontNormal")
    end
    text:SetTextColor(style.rgb[1], style.rgb[2], style.rgb[3])
    text:SetPoint("CENTER", region, "CENTER", 0, 0)
    built = true
  end)
  if not (ok and built) then
    if region then region:Hide() end
    return nil
  end
  region:Hide()

  local dial = { frame = region, bar = bar, text = text }

  --- One draw pass. ⚠ Every branch cap takes is on its OWN readable terms — the gate, and
  --- whether the call handed back an object at all. The remaining time is never one of them.
  --- `SetToTargetValue` is FIRST SHOW ONLY (§4.8.1 finding 5): on every pass it would snap out
  --- an interpolation the client is midway through.
  ---
  --- ⚠ `alpha` is the BAND's channel and it is SECRET: a `sealed-cooldown-range` marker evaluates
  --- the client's own curve and the result is written here and forgotten, never compared, exactly
  --- as a graded badge's is. `nil` means "cap decides, and it has decided yes" — the readable-gate
  --- form. Whether the region is SHOWN stays readable either way; only how opaque it is may be
  --- the client's.
  function dial:Update(allowed, plan, alpha)
    if not allowed then
      self.snapped = false
      return region:Hide()
    end
    local d = Channel.Duration(plan.spell)
    if d == nil then
      self.snapped = false
      return region:Hide()
    end
    local armed, err = pcall(bar.SetTimerDuration, bar, d, IMMEDIATE, REMAINING)
    if not armed then
      self.snapped = false
      region:Hide()
      if ns.Log and ns.Log.Mark then
        ns.Log.Mark("baseCooldownSink: SetTimerDuration refused — " .. tostring(err))
      end
      return
    end
    if not self.snapped then
      pcall(bar.SetToTargetValue, bar)
      self.snapped = true
    end
    text:SetText(Channel.RemainingText(d) or NO_NUMBER)
    region:SetAlpha(alpha == nil and 1 or alpha)
    region:Show()
  end

  return dial
end

--- V20 · the proc bar: the proc's remaining lifetime as a thin client-drained bar directly
--- above V18's charge bar (`lift` px up from the bottom edge — computed by Overlay from the
--- row's DECLARATIONS, because whether either bar is currently drawn is sealed). Linear
--- render mode; edge grammar, not badge grammar — gold here is quantity, never polarity.
--- Nothing is handed over: the client shows and hides the whole button with the aura
--- (§3.5.1), which is what scopes the bar to the proc.
local function procBarSink(button, host, style, lift)
  local bar = CreateFrame("StatusBar", nil, button)
  bar:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, lift or 0)
  bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, lift or 0)
  bar:SetHeight(style.height_px)
  -- ⚠ FIRST: `ApplyDurationBar` never calls `SetMinMaxValues` (§4.8.1 finding 3) — without a
  -- range the bar draws 0 % forever, and nothing downstream would ever say so.
  bar:SetMinMaxValues(0, 1)
  ns.Paint.BarFill(bar, style, "procBarSink")
  --@unverified a 3 px full-width SetDurationBar has never been watched, nor two client-drained
  --@unverified bars stacked on one bottom edge; render-shelf.md V20, in the flight acceptance
  --@unverified set.
  local okSink, sinkErr = pcall(button.SetDurationBar, button, bar, {
    direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1,
  })
  if not okSink and ns.Log and ns.Log.Mark then
    ns.Log.Mark("procBarSink: SetDurationBar refused — " .. tostring(sinkErr))
  end
  return okSink == true
end

local function windowSink(button, style, badges)
  local region = CreateFrame("Frame", nil, button)
  local d = ns.Paint.Geometry(button).diameter
  region:SetSize(d, d)
  -- The corner, like every other badge: the stack is one pixel deep and the container's own
  -- frame level is what puts this under the cue badges (`Paint.Z`).
  region:SetPoint("TOPRIGHT", button, "TOPRIGHT", ns.Paint.StackOffset(button, 0))

  -- The FULL positive-cue treatment: V14's promotion ring around the badge, and the halo
  -- under the plate. This badge is a client-decided promotion and must read as bright as one.
  -- Both motions are AnimationGroups armed BEFORE the handover — the one kind that survives on
  -- a handed-over region: in combat the armed subtree is a forbidden object and the seal
  -- covers writes (§3.5.3).
  local ring = ns.Paint.PromotionRing(region)
  if ring then ring:SetShown(true) end
  local glow = style.glow
  if glow then
    local halo = region:CreateTexture(nil, "OVERLAY", nil, 5)
    halo:SetTexture(badges.texture_root .. badges.halo_texture .. ".tga", nil, nil, "TRILINEAR")
    halo:SetVertexColor(style.rgb[1], style.rgb[2], style.rgb[3])
    halo:SetSize(d * glow.scale, d * glow.scale)
    halo:SetPoint("CENTER")
    halo:SetAlpha(glow.alpha_min)
    local breathe = halo:CreateAnimationGroup()
    breathe:SetLooping("BOUNCE")
    local a = breathe:CreateAnimation("Alpha")
    a:SetFromAlpha(glow.alpha_min)
    a:SetToAlpha(glow.alpha_max)
    a:SetDuration(1 / glow.hz)
    a:SetSmoothing("IN_OUT")
    breathe:Play()
  end

  badgePlate(region, d)

  -- The dial: a radial StatusBar the CLIENT drains off the aura's own duration.
  -- `SetDurationBar` seals only `BarValue` and its whole apply path is
  -- `SetTimerDuration(auraDuration, interpolation, options.direction)` (§3.5.2, T1) — cap
  -- hands the widget over and reads nothing, ever.
  --@unverified the AddPandemicRegion + SetDurationBar ONE-BUTTON pair: each half is measured
  --@unverified alone (§3.5.1's sink fill, §3.5.2's region), never together — render-shelf.md
  --@unverified Part 5 #11. The dial must live INSIDE the wrapper: that is what makes it
  --@unverified appear only in the refresh window.
  local bar = buildDial(region, style.dial, "windowSink")
  local okSink, sinkErr = pcall(button.SetDurationBar, button, bar, {
    direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1,
  })
  if not okSink and ns.Log and ns.Log.Mark then
    ns.Log.Mark("windowSink: SetDurationBar refused — " .. tostring(sinkErr))
  end

  -- No numeral and no region pulse: the badge holds cue-badge brightness exactly — plate at
  -- badges alpha, the dial's arc the client's — and the halo's breath is its only cap-authored
  -- motion (render-shelf.md V19).
  button:AddPandemicRegion(region)
  return true
end

--- The AURA-REMAINING badge (render-shelf.md V21): a red radial on an aura's own remaining, in
--- the badge's place, drawn by the client. `windowSink` minus its promotion ring and its halo,
--- and in `basecd`'s red rather than `pandemic`'s gold — under V5.1 hue carries polarity and only
--- polarity, and gold here would be cap promoting a row it is holding.
---
--- ⚠ NO NUMERAL, AND THAT IS A LIMIT RATHER THAN A CHOICE. V21's number comes from
--- `FormatRemainingDuration` on a COOLDOWN duration object, which cap holds; the aura's duration
--- object is the client's and never reaches cap. `SetDurationText` is the only aura-side text
--- sink and its breakpoints emit fixed strings — `""` or a texture escape, never a `%d` over the
--- remaining seconds (`outsideSink` is its one use). So this ships as the arc alone, which is
--- still strictly more than a clock face frozen at 50 %. Give it a numeral the day a
--- `SetDurationText` breakpoint is measured to interpolate a value.
---
--- ⚠ THE CONTAINER'S VISIBILITY IS THE GATE. The slot filters to the aura, so the badge exists
--- exactly while the aura does; the marker's readable terms ride `verdict.gates` and reach the
--- container's own `Shown`, the way every other container-with-a-`when` already does.
local function auraRemainingSink(button, host, style)
  local region = CreateFrame("Frame", nil, button)
  local d = ns.Paint.Geometry(host).diameter
  region:SetSize(d, d)
  region:SetPoint("TOPRIGHT", host, "TOPRIGHT", ns.Paint.StackOffset(host, 0))
  badgePlate(region, d)

  local bar = buildDial(region, style.dial, "auraRemainingSink")
  --@unverified a badge-corner SetDurationBar over an AURA duration has never been watched: the
  --@unverified measured pairs are V19's window region and V20's edge bar, both on other geometry.
  local okSink, sinkErr = pcall(button.SetDurationBar, button, bar, {
    direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1,
  })
  if not okSink and ns.Log and ns.Log.Mark then
    ns.Log.Mark("auraRemainingSink: SetDurationBar refused — " .. tostring(sinkErr))
  end
  return okSink == true
end

--- Acquire one sealed display while unrestricted. The only public states are the audit
--- states: offered, armed, refused. None claims whether a secret-driven glyph appeared.
---
--- ⚠ THE SINK IS CHOSEN BY `plan.kind` AND BY NOTHING ELSE. Four kinds, four client objects,
--- one acquisition path — because what varies between them is which widget the client is handed,
--- not how the slot is built.
function Channel.Arm(host, marker, abilities, cornerLevel, lift)
  local plan = Channel.ContainerPlan(marker, abilities)
  if not plan or not host or InCombatLockdown() then return nil, "refused" end
  -- ⚠ AN UNPINNED HOST HAS NO RECT, AND EVERY SIZE BELOW IS A RATIO OF ONE. An escape's size is
  -- a literal baked into the band string at arm time and never revisited, so arming against a
  -- 0x0 host bakes the shelf's nominal icon into every element for the life of the frame.
  -- "deferred" is not a failure: the caller retries on the next draw, by which time it is pinned.
  local okRect, valid = pcall(host.IsRectValid, host)
  if not okRect or valid ~= true then return nil, "deferred" end
  if not (C_AddOns and C_AddOns.LoadAddOn) then return nil, "refused" end

  local okLoad = pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
  if not okLoad then return nil, "refused" end

  local container, built
  local filter = plan.unit == "player" and "HELPFUL" or "HARMFUL"
  local candidates = {
    includeSpellIDs = { [plan.spell] = true },
    isFromPlayerOrPlayerPet = true,
  }
  local ok = pcall(function()
    container = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
    container:SetAllPoints(host)

    -- ⚠ AN ELIMINATING MARK DRAWS OVER AN INCLUDING ONE (`render-shelf.md` Part 1). The scan
    -- edge and this container are siblings on cap's frame and neither declared a level, so the
    -- client resolved it by creation order and put the edge on top — the row then read as
    -- in-scan with a hatch scribbled through it, which is the two signals arguing. The hatch is
    -- the later word, so it takes the higher level. `Paint.Z.corner` is that floor; a corner
    -- claimer is handed its own level above it, which is what orders two of them.
    ns.Paint.LevelAbove(container, host, cornerLevel or ns.Paint.Z.corner)

    -- ⚠ A BANDED COUNT TAKES ONE SLOT PER ELEMENT, and that is the whole reason it can draw more
    -- than one mark correctly. Every slot is offered every aura and filters independently
    -- `[T1 src @12.1.0: Blizzard_AuraContainerSlots.lua — UpdateAura, ShouldIncludeAuraInSlot]`,
    -- so the hatch, the badge and the numeral each get their own button, their own FontString and
    -- their own band table — placed where each belongs instead of flowing out of one string.
    if plan.kind == "sealed-count-bands" then
      built = true
      for _, element in ipairs(Channel.CountElements(plan.bands)) do
        container:AddAuraSlot(marker.id .. ":" .. element, filter, {
          candidateFilters = candidates,
          initializeFrame = function(button)
            -- ⚠ THE BUTTON MUST BE THE HOST RECT, and this line was missing until 2026-08-23
            -- while the single-slot branch below had it. A FontString's escape size literal is
            -- read in ITS OWN frame's coordinate space, and the size handed to the band table
            -- is measured off `host` — so a button left at the template's default size read
            -- that number in a different space and drew the hatch at the wrong scale, which is
            -- exactly the residual misalignment two flights could not tune away.
            button:SetAllPoints(container)
            if not countSink(button, host, plan, Channel.BandStyle(), element) then
              built = false
            end
          end,
        })
      end
    else
    container:AddAuraSlot(marker.id, filter, {
      candidateFilters = candidates,
      initializeFrame = function(button)
        button:SetAllPoints(container)
        if plan.kind == "sealed-count-bar" then
          built = barSink(button, host, plan, ns.Style.bar)
        elseif plan.kind == "sealed-pandemic" then
          built = windowSink(button, ns.Style.pandemic, ns.Style.badges)
        elseif plan.kind == "sealed-proc-bar" then
          built = procBarSink(button, host, ns.Style.procbar, lift)
        elseif plan.kind == "sealed-aura-remaining" then
          built = auraRemainingSink(button, host, ns.Style.basecd)
        end
      end,
    })
    -- V18's red flip rides its OWN slot, exactly as a banded count's elements do.
    if plan.kind == "sealed-count-bar" then
      container:AddAuraSlot(marker.id .. ":flip", filter, {
        candidateFilters = candidates,
        initializeFrame = function(button)
          button:SetAllPoints(container)
          if not flipSink(button, host, plan, ns.Style.bar) then built = false end
        end,
      })
    end
    -- The pair's other state rides its OWN slot, exactly as a banded count's elements do: the
    -- badge lives in a handed-over region only the window shows, so the outside hatch cannot
    -- share its widget — it needs a button of its own to hang a duration sink on.
    if plan.kind == "sealed-pandemic" and plan.outside_s then
      container:AddAuraSlot(marker.id .. ":outside", filter, {
        candidateFilters = candidates,
        initializeFrame = function(button)
          button:SetAllPoints(container)
          if not outsideSink(button, host, plan) then built = false end
        end,
      })
    end
    end
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

--- `/cap band [x y]` — move the band's hatch while looking at it.
---
--- ⚠ THIS IS NOT A PLAYER SETTING AND MUST NOT BECOME ONE. `render-shelf.md` owns every number
--- cap draws with, and the shelf is regenerated into `Style.lua` — an override that survived a
--- session would be the style saying one thing and the client drawing another, which is the
--- exact failure the generation pipeline exists to prevent. So it lives in memory only, it
--- prints the value to paste back into Part 6, and a `/reload` forgets it.
---
--- ⚠ IT NUDGES THE OFFSET AND NOTHING ELSE. Size is not an opinion: every escape is a ratio of
--- the row's measured width, and a by-eye number pasted into a shelf shared by every icon size
--- is how the whole primitive came to be frozen at one. The no-argument readout is the
--- instrument that replaces it — drawn diameter against the shelf's ratio, measured, not typed.
---
--- The offset stays nudgeable because an inline escape sits on the text baseline and its
--- placement is arithmetic nobody has done before: two numbers, judged by eye, in a client.
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
  return out
end

if ns.RegisterCommand then
  ns.RegisterCommand{
    name = "band", order = 46, args = "[x y] | off",
    desc = "Nudge the sealed band's hatch offset while looking at it (flight instrument, not saved)",
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
        local o = override or { x = base.hatch_offset_px[1], y = base.hatch_offset_px[2] }
        ns.Emit(("band hatch offset: x=%d y=%d%s"):format(
          o.x, o.y, override and "  (nudged)" or "  (the shelf's)"))
        -- ⚠ MEASURED, NOT REASONED ABOUT — and this readout is now the ASSERTION rather than an
        -- input. An escape's size literal lives in the FontString's own coordinate space and the
        -- shelf's `icon_px` is a screen-pixel intent, so the two differ by the effective scale.
        -- The sizes are derived from the local width, so the drawn diameter must equal
        -- `diameter_pct` of it; if it does not, the row was measured before it was pinned.
        local row = ns.Overlay and ns.Overlay.AnyHost and ns.Overlay.AnyHost()
        if row then
          local w = ns.Paint.Extent(row)
          local scale = row.GetEffectiveScale and row:GetEffectiveScale() or 1
          ns.Emit(("row: local %.1f × effective scale %.3f = %.1f screen px  (shelf nominal %d)")
            :format(w, scale, w * scale, ns.Style.surfaces.icon_px))
          local g = Channel.CountGeometry(w)
          if g then
            ns.Emit(("escapes: hatch %.1f  plate %.1f  mark %.1f  (badge diameter %.1f = %d%% of "
              .. "%.1f)"):format(g.hatch, g.plate, g.mark,
              ns.Paint.Ratios(w).diameter, ns.Style.badges.diameter_pct, w))
          end
        else
          ns.Emit("no row anchored yet — the measurement needs a drawn Cooldown Manager row.")
        end
        ns.Emit("usage: /cap band <x> <y>   ·   /cap band off")
        return
      end
      local x, y = arg:match("^(-?%d+)%s+(-?%d+)$")
      if not x then
        return ns.Emit("usage: /cap band <x> <y>   ·   /cap band off")
      end
      if InCombatLockdown() then
        return ns.Emit("the band re-arms out of combat only.")
      end
      override = { x = tonumber(x), y = tonumber(y) }
      ns.Emit(("band hatch offset → x=%d y=%d. Paste into render-tokens.json as "
        .. "count.hatch_offset_px = [%d, %d] once it looks right.")
        :format(override.x, override.y, override.x, override.y))
      if ns.Overlay and ns.Overlay.Rearm then ns.Overlay.Rearm() end
    end,
  }
end
