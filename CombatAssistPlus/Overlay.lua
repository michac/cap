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

-- The overlay sits PAD outside the icon on every side, so the ring frames it rather than
-- covering its edge pixels; the veil is inset back onto the icon rect.
local PAD = 2
local STRATA = "HIGH"
local LEVEL = 4
local COUNT_SIZE = 18

-- One marker each per row, claimed in sorted entry order so a row two entries bind
-- resolves identically on every login.
local SLOTS = { "count", "hold" }

ns.Overlay = ns.Overlay or {}
local Overlay = ns.Overlay

local stream = ns.Capture.Open("draw", { sessions = 8, cap = 2000, dedup = false })

local pool = {}

local state = {
  bound = nil,
  order = {},
  rowOf = {},
  dark = false,
}

-- ---------------------------------------------------------------------------
-- The frames
-- ---------------------------------------------------------------------------

-- White, so `SetVertexColor` multiplies to exactly the treatment's hue. `SetColorTexture`
-- is fed a literal and never a game value: it POISONS the anchor chain on a secret
-- (§4.8.1 finding 12), which the colour and alpha channels below do not.
local function buildRing(f, thickness)
  local parts = {}
  local function bar(a, b, horizontal)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 1, 1, 1)
    if horizontal then
      t:SetPoint(a)
      t:SetPoint(b)
      t:SetHeight(thickness)
    else
      -- Inset by the thickness so the verticals stop short of the horizontals: an
      -- overlapping corner double-draws and reads brighter than the rest of the ring.
      t:SetPoint(a, f, a, 0, -thickness)
      t:SetPoint(b, f, b, 0, thickness)
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

-- ⚠ A LEAF, and it carries no plate. `SetText` with a secret marks anchoring secret and
-- propagates DOWN, so this is anchored TO the frame and nothing is ever anchored to it;
-- a plate would also be visible while the quantiser's string is empty, which is exactly
-- the state that must show nothing. The outline is what replaces it.
local function buildCount(f)
  local fs = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
  local path = fs:GetFont()
  if path then fs:SetFont(path, COUNT_SIZE, "OUTLINE") end
  fs:SetPoint("TOP", f, "TOP", 0, -PAD)
  fs:Hide()
  return fs
end

-- One ring per thickness the treatment table declares, built once and shown by tier. The
-- paint path then writes only Show/Hide, SetVertexColor and SetAlpha — no geometry, so
-- nothing it does mid-pull rests on a protected setter that has not been measured there.
local function acquire(cid)
  local f = pool[cid]
  if f then return f end

  f = CreateFrame("Frame", nil, UIParent)
  f:Hide()
  f.veil = buildVeil(f)
  f.rings = {}
  for _, thickness in ipairs(ns.Treatment.Thicknesses()) do
    f.rings[#f.rings + 1] = buildRing(f, thickness)
  end
  f.hold = buildHold(f)
  f.count = buildCount(f)
  pool[cid] = f
  return f
end

-- `SetFrameStrata` is protected and, unlike SetPoint/Show/Hide, has not been measured on
-- an addon frame in combat. Nothing here reaches it there: a row is only drawn once Sense
-- has settled, and a settle happens out of combat only, so every frame in the pool was
-- created and layered before the pull. The combat check is belt-and-braces on that, not
-- the thing holding the guarantee.
local function layer(f)
  if f.layered or InCombatLockdown() then return end
  f:SetFrameStrata(STRATA)
  f:SetFrameLevel(LEVEL)
  f.layered = true
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
  end
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
  local want = d.ring and d.ring.thickness
  for _, ring in ipairs(f.rings) do
    if ring.thickness == want then
      for _, t in ipairs(ring.parts) do
        t:SetVertexColor(d.ring.r, d.ring.g, d.ring.b)
        t:SetAlpha(d.ring.a)
        t:Show()
      end
    else
      for _, t in ipairs(ring.parts) do t:Hide() end
    end
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

--- The marker a cue is drawn as, or nil where the vocabulary has none: polarity is carried
--- by SHAPE, so the hold glyph may never stand for a press and a count may never stand for
--- a wait. Both live forms are thresholded, which is what check 4 guarantees for the
--- negative half and what the count's `>= n` is by construction.
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
    return (d.tier or "?") .. "/a" .. pct(d.ring.a) .. "t" .. d.ring.thickness
  end
  return (d.tier or "-") .. "/v" .. pct(d.veil)
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
--- to a brighter sibling and is on no icon.
---
--- ⚠ `C{}` reports what CAP DID — every cue offered, and whether cap armed the channel or
--- could not. There is no "appeared" and there never can be: the client owns that answer
--- and does not report it back, so a log naming one would be a fabrication.
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
  }
  local cells = snap.cells or {}
  local marks = snap.marks or {}
  return "D{" .. table.concat(d, " ") .. "}"
    .. " P{" .. ((#cells > 0) and table.concat(cells, " ") or "-") .. "}"
    .. " C{" .. ((#marks > 0) and table.concat(marks, " ") or "-") .. "}"
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

local function hideAll(edge)
  if state.dark and not edge then return end
  state.dark = true
  for _, f in pairs(pool) do
    f:Hide()
    f.painted = nil
  end
  write(Overlay.Render{
    entries = 0, rows = 0, anchored = 0, confirmed = 0, hidden = 0, noframe = 0,
    cues = 0, armed = 0,
  }, edge)
end

--- Entry ids sorted, and the row each binds. Rebuilt only when the bound set changes,
--- because the sort is what makes the log line a stable dedup key.
local function rebuild(bound)
  state.bound = bound
  state.order, state.rowOf = {}, {}
  local live = {}
  for _, item in ipairs(bound.entries or {}) do
    state.order[#state.order + 1] = item.entry.id
    state.rowOf[item.entry.id] = item.row.cooldownID
    live[item.row.cooldownID] = true
  end
  table.sort(state.order)
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
  -- icon can only be drawn one way, so the row takes the brighter of the two — which is
  -- one icon carrying the higher of two tiers, not a ranking within one (spec.md §3.1).
  -- `winner` records which entry that was, because the log prints all of them.
  local perEntry, best, winner = {}, {}, {}
  for _, id in ipairs(state.order) do
    local cid = state.rowOf[id]
    local d = ns.Treatment.For(out.byEntry[id])
    perEntry[id] = d
    if not best[cid] or ns.Treatment.Brightness(d) > ns.Treatment.Brightness(best[cid]) then
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
  local rows, anchored, confirmed, hidden, noframe = 0, 0, 0, 0, 0
  local mark = {}
  for cid, d in pairs(best) do
    rows = rows + 1
    local f = acquire(cid)
    layer(f)
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

  write(Overlay.Render{
    entries = #state.order, rows = rows,
    anchored = anchored, confirmed = confirmed, hidden = hidden, noframe = noframe,
    cells = cells, cues = #offers, armed = armed, marks = marks,
  }, edge)
end

ns.Sense.OnVerdicts(draw)
