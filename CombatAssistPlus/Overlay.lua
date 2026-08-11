-- Overlay.lua — cap's own frames, anchored to the CDM item frames and painted from
-- Sense's verdicts. The impure half of both registers; Treatment decides the look,
-- Channel hands the sealed comparisons to the client, and this paints.
--
-- Its OWN frames because `SPELL_UPDATE_USABLE` rewrites a tab-1 icon's colour and fires
-- constantly (cooldown-manager.md §5), so a treatment written onto Blizzard's texture is
-- stomped within a frame or two. Parented to UIParent and only ever ANCHORED to the item
-- frame: an addon frame parented to UIParent reads `IsProtected() == false` and
-- re-anchoring it to a protected frame does not change that, with `SetPoint` / `Show` /
-- `Hide` measured working in combat (security-taint-and-restricted-data.md §1.1).
local ADDON, ns = ...

local issecretvalue = issecretvalue

-- The overlay sits PAD outside the icon on every side and the veil is inset back onto the
-- icon rect. The ring gets its own host frame because the pulse is an alpha animation and
-- must not reach the veil or either marker.
local PAD = 2
local STRATA = "HIGH"
local LEVEL = 4

-- One marker each per row, claimed in sorted entry order so a row two entries bind
-- resolves identically on every login.
local SLOTS = { "count", "hold" }

ns.Overlay = ns.Overlay or {}
local Overlay = ns.Overlay

local stream = ns.Capture.Open("draw", { sessions = 8, cap = 2000, dedup = false })

local pool = {}

-- What the two build-time probes below settled, reported on `ring:` and `mark:`. Neither
-- says a pixel moved; each says which route the code took when a name it needs is absent.
local ringMode
local countMode

local state = {
  bound = nil,
  order = {},
  rowOf = {},
  phaseOf = {},
  dark = false,
}

-- ---------------------------------------------------------------------------
-- The frames
-- ---------------------------------------------------------------------------

-- White, so `SetVertexColor` multiplies to exactly the treatment's hue. `SetColorTexture`
-- is fed a literal and never a game value: it POISONS the anchor chain on a secret
-- (§4.8.1 finding 12), which the colour and alpha channels below do not.
local function buildQuad(host, thickness)
  local parts = {}
  local function bar(a, b, horizontal)
    local t = host:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 1, 1, 1)
    if horizontal then
      t:SetPoint(a)
      t:SetPoint(b)
      t:SetHeight(thickness)
    else
      -- Inset by the thickness so the verticals stop short of the horizontals: an
      -- overlapping corner double-draws and reads brighter than the rest of the ring.
      t:SetPoint(a, host, a, 0, -thickness)
      t:SetPoint(b, host, b, 0, thickness)
      t:SetWidth(thickness)
    end
    t:Hide()
    parts[#parts + 1] = t
  end
  bar("TOPLEFT", "TOPRIGHT", true)
  bar("BOTTOMLEFT", "BOTTOMRIGHT", true)
  bar("TOPLEFT", "BOTTOMLEFT", false)
  bar("TOPRIGHT", "BOTTOMRIGHT", false)
  return { thickness = thickness, parts = parts }
end

--@unverified the FlipBook Lua setter NAMES. They are Tier 1 in the generated docs
-- (SimpleAnimFlipBookAPIDocumentation.lua:75-125) but an XML attribute name is not a Lua
-- setter name and guessing wrong is SILENT (frames-textures-animation.md §7.1), so each is
-- probed and a miss falls back to the quad ring and names the absent method on `ring:`.
local FLIP_SETTERS = { "SetFlipBookRows", "SetFlipBookColumns", "SetFlipBookFrames" }

local function buildFlip(host)
  local R = ns.Treatment.RING
  local t = host:CreateTexture(nil, "OVERLAY")
  t:SetAtlas(R.atlas)
  -- `GetAtlas()` says the region is atlas-backed and nothing about what was drawn; a name
  -- that did not resolve leaves it nil (frames-textures-animation.md §5.1).
  local got = t:GetAtlas()
  if type(got) ~= "string" or got:lower() ~= R.atlas:lower() then
    t:Hide()
    return nil, "atlas"
  end
  t:SetBlendMode(R.blend)
  t:SetPoint("CENTER", host, "CENTER")
  local g = t:CreateAnimationGroup()
  local ok, a = pcall(g.CreateAnimation, g, "FlipBook")
  if not ok or a == nil then
    t:Hide()
    return nil, "flipbook"
  end
  for _, name in ipairs(FLIP_SETTERS) do
    if type(a[name]) ~= "function" then
      t:Hide()
      return nil, name
    end
  end
  a:SetFlipBookRows(R.rows)
  a:SetFlipBookColumns(R.columns)
  a:SetFlipBookFrames(R.frames)
  a:SetDuration(R.seconds)
  g:SetLooping("REPEAT")
  -- Runs for the life of the frame, tier or no tier: the host's alpha and Show/Hide are
  -- what gate visibility, so a tier change has nothing here to stop.
  g:Play()
  return t
end

-- The mode is remembered across frames: the flipbook either resolves for the process or it
-- does not, so a downgrade partway through is an anomaly and `ring:` carries the last word.
local function buildRingArt(f)
  if ringMode == nil or ringMode == "flip" then
    local tex, why = buildFlip(f.ringHost)
    if tex then
      ringMode = "flip"
      f.flip = tex
      return
    end
    ringMode = "quad:" .. why
  end
  f.quads = {}
  for _, thickness in ipairs(ns.Treatment.Thicknesses()) do
    f.quads[#f.quads + 1] = buildQuad(f.ringHost, thickness)
  end
end

-- The tier's alpha is BAKED INTO the endpoints: an Alpha animation drives the same channel
-- `SetAlpha` writes (frames-textures-animation.md §7.3), so a wrapper would be two writers
-- on one channel. The consequence is that this must be re-armed whenever the tier or the
-- grade moves, which is exactly when the paint path runs.
local function buildPulse(host)
  local g = host:CreateAnimationGroup()
  g:SetLooping("BOUNCE")
  local a = g:CreateAnimation("Alpha")
  a:SetSmoothing("IN_OUT")
  return { group = g, alpha = a }
end

-- ⚠ ORDER IS THE WHOLE FUNCTION. `Stop()` restores the alpha captured at the last `Play()`,
-- so the tier's alpha goes after the stop (a write before it is reverted) and before the
-- play (that write is what the next stop restores to). The no-pulse path exits between them.
local function armPulse(f, d)
  f.pulse.group:Stop()
  local ring = d.ring
  f.ringHost:SetAlpha(ring and ring.a or 0)
  local p = ns.Treatment.Pulse(d)
  if not p then return end
  f.pulse.alpha:SetFromAlpha(p.from)
  f.pulse.alpha:SetToAlpha(p.to)
  f.pulse.alpha:SetDuration(p.seconds)
  --@unverified does `SetStartDelay` re-pay on every BOUNCE iteration, or only the first?
  -- The KB has the setter and not the answer (frames-textures-animation.md §7.3). If it
  -- re-pays, the period is `cycle + delay`, one tier's rows stop sharing a rate, and `P{}`'s
  -- `p<hz>` names a rate nothing runs at. Either way a re-arm re-pays it, so a row changing
  -- faster than its own delay never reaches a first pulse — LOW's worst case ~1.98 s.
  f.pulse.alpha:SetStartDelay((f.phase or 0) * p.cycle)
  f.pulse.group:Play()
end

local function buildVeil(f)
  local t = f:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(0, 0, 0, 1)
  t:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
  t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
  t:Hide()
  return t
end

-- Bottom-centre, on its own plate. Every part is anchored to the frame and every part
-- takes the channel's alpha, so a plate outliving its bars cannot leak the offer.
local function buildHold(f)
  local H = ns.Treatment.HOLD
  local plateW = H.bar.width * 2 + H.bar.gap + H.inset * 2
  local plateH = H.bar.height + H.inset * 2
  local cy = H.inset + plateH / 2
  local plate = f:CreateTexture(nil, "OVERLAY", nil, 1)
  plate:SetColorTexture(H.plate.r, H.plate.g, H.plate.b, H.plate.a)
  plate:SetSize(plateW, plateH)
  plate:SetPoint("CENTER", f, "BOTTOM", 0, cy)
  local parts = { plate }
  local dx = (H.bar.gap + H.bar.width) / 2
  for i = 1, 2 do
    local t = f:CreateTexture(nil, "OVERLAY", nil, 2)
    t:SetColorTexture(1, 1, 1, 1)
    t:SetVertexColor(H.hue.r, H.hue.g, H.hue.b)
    t:SetSize(H.bar.width, H.bar.height)
    t:SetPoint("CENTER", f, "BOTTOM", (i == 1) and -dx or dx, cy)
    parts[#parts + 1] = t
  end
  for _, t in ipairs(parts) do t:Hide() end
  return parts
end

-- Justification is written rather than inherited, and `CENTER`/`MIDDLE` are the XSD
-- defaults (frames-textures-animation.md §6.2) — so this is defence against a template that
-- overrode them, not a hole being filled. It goes ABOVE the early return: the unpulsed path
-- still draws the glyph. An absent name leaves it unpulsed and says so on `mark:`.
local function buildCountPulse(fs)
  fs:SetJustifyH("CENTER")
  fs:SetJustifyV("MIDDLE")
  local mode = Enum and Enum.FontStringScaleAnimationMode and Enum.FontStringScaleAnimationMode.Vertex
  if mode == nil or type(fs.SetScaleAnimationMode) ~= "function" then return nil end
  fs:SetScaleAnimationMode(mode)
  local g = fs:CreateAnimationGroup()
  local ok, a = pcall(g.CreateAnimation, g, "Scale")
  if not ok or a == nil or type(a.SetScaleFrom) ~= "function" then return nil end
  local P = ns.Treatment.COUNT.pulse
  a:SetScaleFrom(P.from, P.from)
  a:SetScaleTo(P.to, P.to)
  a:SetDuration(P.seconds)
  a:SetSmoothing("IN_OUT")
  a:SetOrigin("CENTER", 0, 0)
  g:SetLooping("BOUNCE")
  g:Play()
  return g
end

-- ⚠ A LEAF, and it carries no plate. `SetText` with a secret marks anchoring secret and
-- propagates DOWN, so this is anchored TO the frame and nothing is ever anchored to it;
-- a plate would also be visible while the quantiser's string is empty, which is exactly
-- the state that must show nothing. The outline is what replaces it.
local function buildCount(f)
  local C = ns.Treatment.COUNT
  local fs = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
  local path = fs:GetFont()
  -- The returned bool is the only failure signal `SetFont` has, and a refusal leaves the
  -- string on the template's font silently.
  local sized = path and fs:SetFont(path, C.size, "OUTLINE") or false
  fs:SetPoint("TOP", f, "TOP", 0, -PAD)
  fs:Hide()
  countMode = (sized and "font" or "nofont") .. "/" .. (buildCountPulse(fs) and "pulse" or "nopulse")
  return fs
end

-- The ring's own host, so the pulse's alpha reaches the ring and nothing else. It is meant
-- to sit one level BELOW the overlay so both markers draw over it — but `layer` is what
-- puts it there, and a default child level is parent+1. A ring and a veil never coexist.
local function buildRingHost(f)
  local host = CreateFrame("Frame", nil, f)
  host:SetAllPoints(f)
  host:Hide()
  return host
end

-- Built once per row and shown by tier. The paint path then writes only Show/Hide,
-- SetVertexColor, SetAlpha and the pulse endpoints — no geometry, so nothing it does
-- mid-pull rests on a protected setter that has not been measured there.
local function acquire(cid)
  local f = pool[cid]
  if f then return f end

  f = CreateFrame("Frame", nil, UIParent)
  f:Hide()
  f.veil = buildVeil(f)
  f.ringHost = buildRingHost(f)
  buildRingArt(f)
  f.pulse = buildPulse(f.ringHost)
  f.hold = buildHold(f)
  f.count = buildCount(f)
  pool[cid] = f
  return f
end

-- `SetFrameStrata` and `SetFrameLevel` are protected and, unlike SetPoint/Show/Hide, are
-- unmeasured on an addon frame in combat. Nothing reaches them there: a row draws only once
-- Sense has settled and a settle happens out of combat, so the pool is layered before the
-- pull — the combat check is belt-and-braces, not the guarantee. ⚠ Skipping it also skips
-- the ring host's level, the ONLY thing putting the ring under both markers.
local function layer(f)
  if f.layered or InCombatLockdown() then return end
  f:SetFrameStrata(STRATA)
  f:SetFrameLevel(LEVEL)
  f.ringHost:SetFrameLevel(LEVEL - 1)
  f.layered = true
end

-- Blizzard sizes its own proc-alert frame at 1.4x the button and centres it there
-- (ActionButtonSpellAlerts.lua:20), so the ring is sized off the ITEM frame. `GetWidth` is
-- SecretWhenAnchoringSecret (§3.2), so a refused read leaves it unsized — and unshown.
local function sizeRing(f, item)
  local ok, w = pcall(item.GetWidth, item)
  if not ok or w == nil or issecretvalue(w) or type(w) ~= "number" then return end
  if w <= 0 then return end
  local s = w * ns.Treatment.RING.scale
  if f.ringSize == s then return end
  f.flip:SetSize(s, s)
  f.ringSize = s
  -- The paint path is what shows the ring, and it runs only on a change of drawn key — so
  -- a size that arrives later than the first paint has to ask for one.
  f.painted = nil
end

-- Item frames are POOLED, so a cooldownID's frame can change under us. Re-anchor whenever
-- the object differs; an unconfirmed frame is still drawn on, because Bind reschedules a
-- resolve itself and a blank overlay would hide the symptom.
local function anchor(f, cid)
  local item, confirmed = ns.Bind.ItemFrame(cid)
  if not item then
    f.anchoredTo = nil
    return nil, false
  end
  if f.anchoredTo ~= item then
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", item, "TOPLEFT", -PAD, PAD)
    f:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", PAD, -PAD)
    f.anchoredTo = item
    f.painted = nil
  end
  -- Every pass: a UI rescale re-lays the item frame without handing cap a different one.
  if f.flip then sizeRing(f, item) end
  return item, confirmed
end

-- A viewer the player switched off leaves live item frames with no pixels, and an overlay
-- anchored to one would float over nothing. A refused read DRAWS: an overlay in the wrong
-- place is a visible bug, and a silently blank one is not.
local function itemShown(item)
  local ok, shown = pcall(item.IsVisible, item)
  if not ok or shown == nil or issecretvalue(shown) then return true end
  return shown and true or false
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------

local function paint(f, d)
  local ring = d.ring
  if not ring then
    armPulse(f, d)
    f.ringHost:Hide()
  else
    if f.flip then
      f.flip:SetVertexColor(ring.r, ring.g, ring.b)
    else
      for _, quad in ipairs(f.quads) do
        local on = quad.thickness == ring.thickness
        for _, t in ipairs(quad.parts) do
          if on then t:SetVertexColor(ring.r, ring.g, ring.b) end
          if on then t:Show() else t:Hide() end
        end
      end
    end
    -- Armed before the size is known, so an unsized ring plays on a host the next line
    -- hides. One arming path is worth more than the frames a hidden group costs.
    armPulse(f, d)
    if f.flip and not f.ringSize then f.ringHost:Hide() else f.ringHost:Show() end
  end

  if (d.veil or 0) > 0 then
    f.veil:SetAlpha(d.veil)
    f.veil:Show()
  else
    f.veil:Hide()
  end
end

local function pct(v)
  return ("%d"):format(math.floor((v or 0) * 100 + 0.5))
end

-- ---------------------------------------------------------------------------
-- Cues — cap offers, the client decides, and cap is never told
-- ---------------------------------------------------------------------------

--- The marker a cue is drawn as, keyed on the (polarity, channel) PAIR, or nil where no
--- marker exists for that pairing yet. Both live forms are thresholded, which is what
--- check 4 guarantees for the negative half and what the count's `>= n` is by construction.
local function slotFor(cue)
  local ch = cue.channel or {}
  if #ch ~= 4 then return nil end
  if cue.polarity == "positive" and ch[1] == "stacks" then return "count" end
  if cue.polarity == "negative" and ch[1] == "cooldownRemaining" then return "hold" end
  return nil
end

local function slotKey(s)
  local parts = {}
  for _, name in ipairs(SLOTS) do
    local o = s and s[name]
    parts[#parts + 1] = o and (o.id .. tostring(o.cue.tier) .. tostring(o.cue.channel[4])) or "-"
  end
  return table.concat(parts, "|")
end

--- Setup, keyed on the OFFER — a withdrawn cue puts its marker away here rather than on
--- the hot path. `inked` is the one thing that can fail: a tier drawn as a veil puts no
--- light on the icon, so its marker has no colour and cap cannot arm it.
local function dress(f, s)
  local o = s and s.count
  local r, g, b, a = ns.Treatment.Ink(o and ns.Treatment.Mark(o.cue))
  f.inked = r ~= nil
  if r then f.count:SetTextColor(r, g, b, a) else f.count:Hide() end
  if not (s and s.hold) then
    for _, t in ipairs(f.hold) do t:Hide() end
  end
end

--- The channel write, and it runs EVERY pass a cue is offered: a count and a countdown
--- both move, and cap cannot dedup on an answer it is not allowed to read. Each half hides
--- its marker when the channel refuses, so a marker never stands for something cap could
--- not establish. Nothing here tests the value the client returned — only whether one came.
local function channels(f, s, bound)
  local o = s.count
  local text
  if o and f.inked then text = ns.Channel.StackText(o.cue.channel[2], o.cue.channel[4]) end
  if text ~= nil then
    f.count:SetText(text)
    f.count:Show()
    o.state = "armed"
  elseif o then
    f.count:Hide()
  end

  o = s.hold
  local alpha
  -- Through `Catalog.Subject`: an entry-subject channel may name `this`, and `byEntry` is
  -- keyed by entry id, so a raw subject misses every time the author writes one.
  local row = o and bound.byEntry[ns.Catalog.Subject(o.cue.channel, { id = o.id })]
  if row then alpha = ns.Channel.Threshold(row.primary, o.cue.channel[4], ns.Treatment.HOLD.alpha) end
  if alpha ~= nil then
    for _, t in ipairs(f.hold) do t:SetAlpha(alpha); t:Show() end
    o.state = "armed"
  elseif o then
    for _, t in ipairs(f.hold) do t:Hide() end
  end
end

-- The drawn state of one row, and the repaint key: a verdict recomputes at 10 Hz and
-- almost never moves, so writing the widgets only when this changes is what keeps the
-- paint path off the hot loop.
local function cell(d)
  if d.ring then
    -- `t` is the FALLBACK ring's thickness: printed only when the fallback is on screen.
    return (d.tier or "?") .. "/a" .. pct(d.ring.a)
      .. ((ringMode == "flip") and "" or ("t" .. d.ring.thickness))
      .. "p" .. tostring(d.ring.pulse or 0)
  end
  return (d.tier or "-") .. "/v" .. pct(d.veil)
end

-- Which of two entries a shared row is drawn as: tier first, emphasis only to break a
-- tie inside one tier.
local function outranks(a, b)
  local ra, rb = ns.Treatment.Rank(a), ns.Treatment.Rank(b)
  if ra ~= rb then return ra > rb end
  return ns.Treatment.Brightness(a) > ns.Treatment.Brightness(b)
end

-- ---------------------------------------------------------------------------
-- Rendering — pure, and IS the dedup key
-- ---------------------------------------------------------------------------

local function num(v)
  if v == nil or issecretvalue(v) or type(v) ~= "number" then return "?" end
  return tostring(math.floor(v))
end

--- The body a line carries. No clock, no game reads, and `cells` arrives already sorted —
--- a key that reorders breaks dedup nondeterministically.
---
--- ⚠ A `P{}` cell is ONE ENTRY's own treatment, and two entries can bind one row. The
--- entry whose treatment was actually painted carries `*`; a cell without one lost its row
--- to a higher-tier sibling and is on no icon.
---
--- ⚠ `C{}` reports what CAP DID — every cue offered, and whether cap armed the channel or
--- could not. There is no "appeared" and there never can be: the client owns that answer
--- and does not report it back, so a log naming one would be a fabrication.
---
--- ⚠ `B{}` carries §3.4's bars under exactly that rule: `armed` means cap handed the client
--- a duration object, never that a bar drew.
function Overlay.Render(snap)
  snap = snap or {}
  local d = {
    "n:" .. num(snap.entries),
    "rows:" .. num(snap.rows),
    "anch:" .. num(snap.anchored),
    "conf:" .. num(snap.confirmed),
    "off:" .. num(snap.hidden),
    "nf:" .. num(snap.noframe),
    "cue:" .. num(snap.cues),
    "arm:" .. num(snap.armed),
    "glow:" .. (snap.glow or "-"),
    "nosize:" .. num(snap.nosize),
    "ring:" .. (snap.ring or "-"),
    "mark:" .. (snap.mark or "-"),
    "bar:" .. (snap.bar or "-"),
  }
  local cells = snap.cells or {}
  local marks = snap.marks or {}
  local bars = snap.bars or {}
  return "D{" .. table.concat(d, " ") .. "}"
    .. " P{" .. ((#cells > 0) and table.concat(cells, " ") or "-") .. "}"
    .. " C{" .. ((#marks > 0) and table.concat(marks, " ") or "-") .. "}"
    .. " B{" .. ((#bars > 0) and table.concat(bars, " ") or "-") .. "}"
end

local lastBody
local lines = 0

-- Combat start and end are marked HERE as well as on `tier`, carrying the full body:
-- lines are pre-rendered, so a slice a reader wants later cannot be recovered from a
-- marker in the other file, and a bare marker against an unchanged drawn set would emit
-- no numbers — which is the PASS case. The edge is the one Sense passes down from the
-- event, never `InCombatLockdown()`.
local function write(body, edge)
  local text = ("t%.1f "):format(GetTime()) .. (edge and ("# " .. edge .. " ") or "") .. body
  if edge then
    stream:Mark(text)
  elseif body ~= lastBody then
    stream:Line(text)
  else
    return
  end

  -- Remembered only once the line can actually have landed: the stream DROPS every write
  -- while `ns.db` is unset, and spending the dedup key on a dropped line would suppress
  -- the first real one.
  if not ns.db then return end
  lastBody = body
  lines = lines + 1
  stream:Meta("catalog", ns.Sense.CatalogName() or "-")
  stream:Meta("version", ns.version)
  stream:Meta("lines", lines)
end

-- ---------------------------------------------------------------------------
-- The draw pass
-- ---------------------------------------------------------------------------

-- The bars are their own surface on the same pass and report through the same line, the way
-- `glow:` does — `Bars.lua` listens first, so what this reads is this pass's answer.
local function barReport()
  if not ns.Bars then return nil, nil end
  return ns.Bars.Report()
end

local function hideAll(edge)
  if state.dark and not edge then return end
  state.dark = true
  for _, f in pairs(pool) do
    f:Hide()
    f.painted = nil
  end
  local bars, bar = barReport()
  write(Overlay.Render{
    entries = 0, rows = 0, anchored = 0, confirmed = 0, hidden = 0, noframe = 0, nosize = 0,
    cues = 0, armed = 0, glow = ns.Glow and ns.Glow.Status() or nil,
    ring = ringMode, mark = countMode, bars = bars, bar = bar,
  }, edge)
end

--- Entry ids sorted, and the row each binds. Rebuilt only when the bound set changes,
--- because the sort is what makes the log line a stable dedup key.
local function rebuild(bound)
  state.bound = bound
  state.order, state.rowOf, state.phaseOf = {}, {}, {}
  local live = {}
  for _, item in ipairs(bound.entries or {}) do
    state.order[#state.order + 1] = item.entry.id
    state.rowOf[item.entry.id] = item.row.cooldownID
    live[item.row.cooldownID] = true
  end
  table.sort(state.order)

  -- One phase per ROW, off the sorted order, so no two pulses start together and a row
  -- takes the same offset on every login. Why they must not start together: Treatment's
  -- note on `PULSE`.
  local n = 0
  for _, id in ipairs(state.order) do
    local cid = state.rowOf[id]
    if state.phaseOf[cid] == nil then
      n = n + 1
      state.phaseOf[cid] = ns.Treatment.Phase(n)
    end
  end
  -- An overlay whose row left the bound set is hidden and KEPT: the pool is keyed by
  -- cooldownID, and a spec swapped away from and back to re-uses it.
  for cid, f in pairs(pool) do
    if not live[cid] then
      f:Hide()
      f.painted = nil
    end
  end
end

local function draw(out, bound, edge)
  if not (out and bound) then
    state.bound = nil
    hideAll(edge)
    return
  end
  state.dark = false
  if bound ~= state.bound then rebuild(bound) end

  -- One descriptor per ROW. Two entries bind one row on a transforming ability and an
  -- icon can only be drawn one way, so the row is drawn in the higher of the two tiers —
  -- one icon carrying the higher of two, not a ranking within one (spec.md §3.1).
  -- `winner` records which entry that was, because the log prints all of them.
  local perEntry, best, winner = {}, {}, {}
  for _, id in ipairs(state.order) do
    local cid = state.rowOf[id]
    local d = ns.Treatment.For(out.byEntry[id])
    perEntry[id] = d
    if not best[cid] or outranks(d, best[cid]) then
      best[cid] = d
      winner[cid] = id
    end
  end

  -- Every offer, in sorted entry order, `refused` until a channel arms it. A cue whose
  -- shape has no marker reads `nodraw` — cap never asked the client — and a second cue
  -- for a slot another entry already holds reads `taken`.
  local slots, offers = {}, {}
  for _, id in ipairs(state.order) do
    local cid = state.rowOf[id]
    for _, cue in ipairs((out.byEntry[id] or {}).cues or {}) do
      local name = slotFor(cue)
      local s = slots[cid]
      if not s then s = {}; slots[cid] = s end
      local o = { id = id, cue = cue, state = "nodraw" }
      if name and s[name] then
        o.state = "taken"
      elseif name then
        s[name], o.state = o, "refused"
      end
      offers[#offers + 1] = o
    end
  end

  -- `hidden` and `noframe` are different failures and are counted apart: a hidden item
  -- frame means the overlay is correctly dark, and no item frame at all means the
  -- anchoring never happened. Conflated, a total anchoring failure reads as a pass.
  local rows, anchored, confirmed, hidden, noframe, nosize = 0, 0, 0, 0, 0, 0
  local mark = {}
  for cid, d in pairs(best) do
    rows = rows + 1
    local f = acquire(cid)
    layer(f)
    f.phase = state.phaseOf[cid] or 0
    local item, ok = anchor(f, cid)
    if not item then
      mark[cid] = "!"
      noframe = noframe + 1
      f:Hide()
      f.painted = nil
    else
      anchored = anchored + 1
      if ok then
        confirmed = confirmed + 1
      else
        mark[cid] = "?"
      end

      if itemShown(item) then
        -- ⚠ Counted apart for the reason `off:` and `nf:` are: an unsized ring draws NOTHING
        -- and a tiered row has no veil either, so unreported it reads exactly like a pass.
        if d.ring and f.flip and not f.ringSize then nosize = nosize + 1 end
        local k = cell(d)
        if f.painted ~= k then
          paint(f, d)
          f.painted = k
        end
        local ck = slotKey(slots[cid])
        if f.cueKey ~= ck then
          dress(f, slots[cid])
          f.cueKey = ck
        end
        if slots[cid] then channels(f, slots[cid], bound) end
        f:Show()
      else
        hidden = hidden + 1
        f:Hide()
        f.painted = nil
      end
    end
  end

  local cells = {}
  for _, id in ipairs(state.order) do
    local cid = state.rowOf[id]
    cells[#cells + 1] = id .. ":" .. cell(perEntry[id])
      .. ((winner[cid] == id) and "*" or "") .. (mark[cid] or "")
  end

  local marks, armed = {}, 0
  for _, o in ipairs(offers) do
    if o.state == "armed" then armed = armed + 1 end
    marks[#marks + 1] = o.id .. ":" .. ((o.cue.polarity == "negative") and "-" or "+")
      .. tostring((o.cue.channel or {})[1]) .. ":" .. o.state
  end

  local barCells, barProbe = barReport()
  write(Overlay.Render{
    entries = #state.order, rows = rows,
    anchored = anchored, confirmed = confirmed, hidden = hidden, noframe = noframe,
    nosize = nosize,
    cells = cells, cues = #offers, armed = armed, marks = marks,
    glow = ns.Glow and ns.Glow.Status() or nil,
    ring = ringMode, mark = countMode, bars = barCells, bar = barProbe,
  }, edge)
end

ns.Sense.OnVerdicts(draw)
