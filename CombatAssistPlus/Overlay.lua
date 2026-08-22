-- Overlay.lua — addon-owned scan edges, cue badges and cooldown hatches on CDM rows, drawn
-- through ns.Paint. No stock-proc suppression: the first flight tests coexistence.
local ADDON, ns = ...

local issecretvalue = issecretvalue

ns.Overlay = ns.Overlay or {}
local Overlay = ns.Overlay
local stream = ns.Capture.Open("draw", { sessions = 8, cap = 2000, dedup = false })
local pool = {}
local state = { bound = nil, order = {}, rowOf = {}, itemOf = {}, dark = false }

--- One pooled frame per row, carrying every primitive the shelf declares — a badge per cue
--- key, built once. Acquisition happens out of combat (Bind.resolve refuses to run in it), so
--- the in-combat path is only Show/Hide/SetVertexColor/SetAlpha.
local function acquire(cid)
  local f = pool[cid]
  if f then return f end
  f = CreateFrame("Frame", nil, UIParent)
  f:Hide()
  f.border = ns.Paint.Border(f)
  -- The overlay frame is the item's own rect: the scan edge sits ON the icon (tokens.ready) and
  -- the hatch is a statement about the icon face, so neither needs room outside it. Only the
  -- badges reach past the corner, and a texture is free to overhang its frame.
  f.hatch = ns.Paint.Hatch(f)
  -- V11's second cause, its own layer: cap's "ruled out" in cap's colour and phase. Two layers
  -- rather than one re-tinted, so a row that is somehow both draws both and neither has to know
  -- about the other.
  f.skip = ns.Paint.Hatch(f, nil, (ns.Style.hatch or {}).skip)
  f.promo = ns.Paint.PromotionRing(f)
  -- V15 · chrome. On CAP'S OWN row frame, which is anchored corner-to-corner onto the CDM item
  -- rect below, so a top-left anchor lands on the icon. ⚠ Never parented into Blizzard's pooled
  -- item frames: those are recycled and re-bound on `OnCooldownIDSet`, and since 12.1 they
  -- participate in secure aura plumbing.
  f.hotkey = ns.Paint.Hotkey(f)
  f.badges = {}
  for key in pairs(ns.Style.cues) do f.badges[key] = ns.Paint.Badge(f, key) end
  f.channels, f.channelStatus, f.channelOf = {}, {}, {}
  f.gradedPlans, f.graded, f.gradedStatus = {}, {}, {}
  -- A graded cue gets its OWN badge instance, keyed by marker rather than by cue. Two markers
  -- may name one cue — that union is how the band grammar expresses an OR — and a shared frame
  -- cannot carry an OR of two SEALED bands: each writes the badge's alpha from its own curve,
  -- the values are secret and so cannot be compared or maxed, and whichever wrote last would
  -- win. Stacked instances at the same slot do the OR in the compositor instead: either alpha
  -- being opaque makes the badge visible, and both being opaque draws the same glyph twice.
  f.gradedBadges = {}
  pool[cid] = f
  return f
end

--- Every cue frame down. Called on each path that stops drawing a row, so a hidden row cannot
--- leave a badge lit or stepping.
local function quiet(f)
  if f.border then f.border:Hide() end
  if f.hatch then f.hatch:Hide() end
  if f.skip then f.skip:Hide() end
  if f.promo then f.promo:Hide() end
  -- ⚠ Chrome goes quiet with everything else. Every path that stops drawing a row comes through
  -- here, and a widget missing from this list stays lit on a hidden row forever.
  if f.hotkey then f.hotkey:Hide() end
  for _, badge in pairs(f.badges or {}) do badge:Hide() end
  for _, badge in pairs(f.gradedBadges or {}) do badge:Hide() end
  -- ⚠ The sealed displays go down with everything else. Their CONTENT is the client's, but the
  -- container is cap's own frame parented to this row, so a hidden row that left one showing
  -- would leave a count or an arc floating over nothing. Added 2026-08-22 with V16–V19; before
  -- them there was one such display in one catalog and the omission never showed.
  for _, container in pairs(f.channels or {}) do container:Hide() end
end

--- Arm every graded cue this row declares and has not armed yet. Separate from the aura
--- channels because a curve needs no frame: it can be built in combat, and a client that
--- cannot build one at all must not drag the frame-acquiring path into a retry every draw.
local function armGraded(f, declared)
  for id, plan in pairs(f.gradedPlans) do
    if not f.graded[id] then
      local armed, status = ns.Channel.ArmGraded(plan, declared)
      if armed then f.graded[id] = armed end
      f.gradedStatus[id] = status or "refused"
    end
  end
end

local function configure(f, item, declared)
  for _, container in pairs(f.channels) do container:Hide() end
  f.channelStatus, f.channelOf = {}, {}
  f.gradedPlans, f.graded, f.gradedStatus = {}, {}, {}
  -- Frames are kept and reused, but a badge belonging to a marker this catalog no longer
  -- declares would never be reached by `graded()` again and would sit lit forever.
  for _, badge in pairs(f.gradedBadges) do badge:Hide() end
  for _, marker in ipairs(item.entry.markers or {}) do
    -- A readable marker is still evaluated and still reported; the shelf's cue vocabulary has
    -- no drawn form for the two ad-hoc Warlock ones, so nothing is drawn for it.
    local gradedPlan = ns.Channel.GradedPlan(marker)
    local containerPlan = not gradedPlan and ns.Channel.ContainerPlan(marker, declared)
    if gradedPlan then
      f.gradedPlans[marker.id] = gradedPlan
      -- One instance per MARKER, so a two-band union stacks rather than overwrites. Built here
      -- because the marker set is not known at acquire time; `configure` runs on the bind path,
      -- which `Bind.resolve` refuses to run in combat.
      f.gradedBadges[marker.id] = f.gradedBadges[marker.id] or ns.Paint.Badge(f, marker.cue)
    -- ⚠ A CONTAINER DISPLAY MAY CARRY A READABLE GATE, and until 2026-08-22 one silently armed
    -- nothing: this branch tested `not marker.when`, so a marker with both a `when` and a
    -- `display` fell through to neither path. `Signal` has always computed `verdict.gates` for
    -- exactly that shape (one secret, many readable gates) and only the graded branch consumed
    -- it. Now both do — the gate never contributes a cue, it only decides whether the client is
    -- allowed to paint the sealed one at all.
    elseif containerPlan or not marker.when then
      local plan = containerPlan
      local key = plan and (marker.id .. "/" .. plan.spell) or marker.id
      local container = f.channels[key]
      local status
      if container then
        container:Show()
        status = "armed"
      elseif not InCombatLockdown() then
        container, status = ns.Channel.Arm(f, marker, declared)
        if container then f.channels[key] = container end
      else
        status = "refused"
      end
      f.channelStatus[marker.id] = status or "refused"
      f.channelOf[marker.id] = f.channels[key]
    end
  end
  armGraded(f, declared)
end

local function layer(f)
  if f.layered or InCombatLockdown() then return end
  f:SetFrameStrata("HIGH")
  f:SetFrameLevel(4)
  f.layered = true
end

local function anchor(f, cid)
  local item, confirmed = ns.Bind.ItemFrame(cid)
  if not item then f.anchoredTo = nil; return nil, false end
  if f.anchoredTo ~= item then
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 0, 0)
    f.anchoredTo = item
  end
  return item, confirmed
end

local function itemShown(item)
  local ok, shown = pcall(item.IsVisible, item)
  if not ok or shown == nil or issecretvalue(shown) then return true end
  return shown and true or false
end

--- ONE CURVE, ONE SINK (render-shelf V9). A graded cue's badge is shown whenever the row draws
--- and its visibility is the client's to decide: cap writes the evaluated result into the badge
--- frame's alpha and nowhere else. The value is written and forgotten; it is never compared, not
--- even against nil, which is why the evaluator answers `ok, value`.
local function graded(f, verdict)
  local gates = (verdict or {}).gates or {}
  -- The same gate, applied to the CONTAINER sinks. A container has no alpha cap may write — the
  -- client owns what it draws — so the gate lands on the container's own `Shown`, which is
  -- cap's. `gated` is its own status rather than a refusal: nothing failed, the row simply is
  -- not in the state that licenses the display.
  -- ⚠ SetShown on EVERY draw, not just on a change: `quiet()` takes the containers down with the
  -- rest of the row, so a row that comes back has to put them up again. A one-way gate would
  -- leave the display dark for the rest of the session after the first hidden frame.
  for id, container in pairs(f.channelOf or {}) do
    local allowed = gates[id] ~= false
    container:SetShown(allowed)
    f.channelStatus[id] = allowed and "armed" or "gated"
  end
  -- Where a graded badge sits in the flowing stack. It shares its cue's place with the shared
  -- badge of the same key -- two instances of one cue draw stacked on top of each other, which
  -- is what the old fixed slots did too. A graded cue nobody else is wearing goes on the end.
  local order, depth = f.cueOrder or {}, 0
  for _ in pairs(order) do depth = depth + 1 end
  for id, armed in pairs(f.graded) do
    local badge = f.gradedBadges[id]
    if badge then
      local plan = f.gradedPlans[id]
      local at = plan and order[plan.cue] or depth
      badge:SetPoint("TOPRIGHT", f, "TOPRIGHT", ns.Paint.StackOffset(at))
      -- ONE SECRET, MANY READABLE GATES. The curve reads the secret; readable terms beside it
      -- decide whether the client may paint the result at all. `false` is a deliberate
      -- withholding, reported as its own status rather than as a refusal — nothing failed.
      if gates[id] == false then
        badge:Hide()
        f.gradedStatus[id] = "gated"
      else
        local ok, value = ns.Channel.GradedAlpha(armed)
        if ok then
          badge:Show()
          badge.frame:SetAlpha(value)
          f.gradedStatus[id] = "armed"
        else
          -- An evaluation that threw is a refusal, not an empty badge left lit at its last alpha.
          badge:Hide()
          f.gradedStatus[id] = "refused"
        end
      end
    end
  end
end

--- Compose one row: the cooldown hatch, the scan edge, then a badge per cue — the order
--- render-shelf.md Part 2.5 fixes, bottom to top.
local function paint(f, verdict, item)
  local d = ns.Treatment.For(verdict)
  f.border:SetShown(d.scan)
  if f.hatch then f.hatch:SetShown(d.hatch) end
  if f.skip then f.skip:SetShown(d.skip) end

  -- V15 · which key casts this icon. Above the badges because it is CHROME (`spec.md` §3.8): it
  -- takes no part in the read they carry, so it neither joins their stack nor waits on it. The
  -- row's `primary` (`override or base`) is the id fed to the lookup — not the live id, which
  -- flickers under a transform, and not the authored one, which a choice node can bind past.
  if f.hotkey then
    local row = (item or {}).row
    ns.Paint.Label(f.hotkey, ns.Binds and ns.Binds.For(row and row.primary))
  end

  -- The shared badges are the READABLE cues' and only theirs; graded cues own their own frames
  -- now, so this no longer has to leave a key alone on their behalf. A cue carried by both (a
  -- readable marker and a band naming one `blocked`) simply draws two stacked instances.
  -- `d.cues` arrives in shelf-RANK order (Signal), so its index IS the badge's place in the
  -- stack. Re-anchored every update: the same cue sits on the corner when it is alone and one
  -- step down when a higher-ranked one is showing beside it.
  local wanted = {}
  for i, key in ipairs(d.cues or {}) do wanted[key] = i - 1 end
  for key, badge in pairs(f.badges) do
    local at = wanted[key]
    if at then
      badge:SetPoint("TOPRIGHT", f, "TOPRIGHT", ns.Paint.StackOffset(at))
      badge.frame:SetAlpha(1)
      badge:Show()
    else
      badge:Hide()
    end
  end
  f.cueOrder = wanted

  -- V14 rides the POSITIVE cue: shown exactly while one is worn, and centred on the BADGE that
  -- carries it rather than on the row's corner, so it follows the badge down the stack when a
  -- higher-ranked cue is showing beside it.
  if f.promo then
    local host
    for key, badge in pairs(f.badges or {}) do
      if wanted[key] and (ns.Style.cues[key] or {}).polarity == "positive" then host = badge end
    end
    if host then
      f.promo.frame:ClearAllPoints()
      f.promo.frame:SetPoint("CENTER", host, "CENTER", 0, 0)
    end
    f.promo:SetShown(host ~= nil)
  end
  graded(f, verdict)
  return d
end

--- `id:scan[+cue,cue]`, or `id:off` where the row draws nothing at all. A trailing `~` is V11's
--- cooldown hatch, which is independent of the scan — so `id:off~` is a real state, and reading a
--- bare `off` as "nothing drawn" would be wrong. The ROLE TIER is deliberately not here: it is a
--- model fact, recoverable from Sense.lua's tier stream, and the paint no longer branches on it.
local function cell(id, d)
  local hatch = (d and d.hatch) and "~" or ""
  if not (d and d.scan) then return id .. ":off" .. hatch end
  local s = id .. ":scan"
  if #(d.cues or {}) > 0 then s = s .. "+" .. table.concat(d.cues, ",") end
  return s .. hatch
end

local function num(v)
  if v == nil or issecretvalue(v) or type(v) ~= "number" then return "?" end
  return tostring(math.floor(v))
end

function Overlay.Render(snap)
  snap = snap or {}
  local d = {
    "n:" .. num(snap.entries), "rows:" .. num(snap.rows),
    "anch:" .. num(snap.anchored), "conf:" .. num(snap.confirmed),
    "off:" .. num(snap.hidden), "nf:" .. num(snap.noframe),
    "bar:" .. (snap.bar or "-"),
    "stock:" .. ((ns.Glow and ns.Glow.Status()) or "absent"),
  }
  return "D{" .. table.concat(d, " ") .. "}"
    .. " P{" .. (#(snap.cells or {}) > 0 and table.concat(snap.cells, " ") or "-") .. "}"
    .. " M{" .. (#(snap.marks or {}) > 0 and table.concat(snap.marks, " ") or "-") .. "}"
    .. " B{" .. (#(snap.bars or {}) > 0 and table.concat(snap.bars, " ") or "-") .. "}"
    .. " C{" .. (#(snap.channels or {}) > 0 and table.concat(snap.channels, " ") or "-") .. "}"
end

local lastBody, lines
lines = 0
local function write(body, edge)
  if not edge and body == lastBody then return end
  local text = ("t%.1f "):format(GetTime()) .. (edge and ("# " .. edge .. " ") or "") .. body
  if edge then stream:Mark(text) else stream:Line(text) end
  if not ns.db then return end
  lastBody, lines = body, lines + 1
  stream:Meta("catalog", ns.Sense.CatalogName() or "-")
  stream:Meta("version", ns.version)
  stream:Meta("lines", lines)
end

local function barReport()
  if not ns.Bars then return nil, nil end
  return ns.Bars.Report()
end

--- Cap has stopped drawing — unsettled, dark, or catalog-less. Every row goes quiet; the scan
--- edge is a still treatment, so resuming needs no first-draw special case.
local function hideAll(edge)
  for _, f in pairs(pool) do quiet(f); f:Hide() end
  local bars, bar = barReport()
  write(Overlay.Render{ entries = 0, rows = 0, anchored = 0, confirmed = 0,
    hidden = 0, noframe = 0, bars = bars, bar = bar }, edge)
end

local function rebuild(bound)
  state.bound, state.order, state.rowOf, state.itemOf = bound, {}, {}, {}
  local live = {}
  for _, item in ipairs(bound.entries or {}) do
    state.order[#state.order + 1] = item.entry.id
    state.rowOf[item.entry.id] = item.row.cooldownID
    state.itemOf[item.entry.id] = item
    live[item.row.cooldownID] = true
  end
  table.sort(state.order)
  for cid, f in pairs(pool) do if not live[cid] then quiet(f); f:Hide() end end
  for _, id in ipairs(state.order) do
    local item = state.itemOf[id]
    configure(acquire(item.row.cooldownID), item, bound.declared)
  end
end

local function draw(out, bound, edge)
  if not (out and bound) then state.bound = nil; hideAll(edge); return end
  if bound ~= state.bound then rebuild(bound) end

  local rows, anchored, confirmed, hidden, noframe = 0, 0, 0, 0, 0
  local cells, marks, channels = {}, {}, {}
  for _, id in ipairs(state.order) do
    local verdict = out.byEntry[id]
    local cid = state.rowOf[id]
    local f = acquire(cid)
    -- A combat-time acquisition refusal gets one honest retry after restriction lifts.
    for _, status in pairs(f.channelStatus) do
      if status == "refused" and not InCombatLockdown() then
        configure(f, state.itemOf[id], bound.declared)
        break
      end
    end
    for marker, status in pairs(f.channelStatus) do
      channels[#channels + 1] = id .. ":" .. marker .. ":" .. status
    end
    -- A graded cue can be armed under restriction, so it retries on every draw until it is.
    armGraded(f, bound.declared)
    for marker, status in pairs(f.gradedStatus) do
      channels[#channels + 1] = id .. ":" .. marker .. ":" .. status
    end
    layer(f)
    local item, ok = anchor(f, cid)
    rows = rows + 1
    if not item then
      noframe = noframe + 1
      quiet(f)
      f:Hide()
      cells[#cells + 1] = id .. ":noframe"
    elseif not itemShown(item) then
      anchored = anchored + 1
      if ok then confirmed = confirmed + 1 end
      hidden = hidden + 1
      quiet(f)
      f:Hide()
      cells[#cells + 1] = id .. ":hidden"
    else
      anchored = anchored + 1
      if ok then confirmed = confirmed + 1 end
      cells[#cells + 1] = cell(id, paint(f, verdict, state.itemOf[id]))
      f:Show()
      for _, marker in ipairs(verdict.markers or {}) do marks[#marks + 1] = id .. ":" .. marker end
    end
  end
  table.sort(channels)
  local bars, bar = barReport()
  write(Overlay.Render{ entries = #state.order, rows = rows, anchored = anchored,
    confirmed = confirmed, hidden = hidden, noframe = noframe,
    cells = cells, marks = marks, channels = channels, bars = bars, bar = bar }, edge)
end

ns.Sense.OnVerdicts(draw)
