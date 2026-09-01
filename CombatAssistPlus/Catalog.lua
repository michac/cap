-- Catalog.lua — the small authored contract between a spec and cap's renderer.
-- Pure: this validates plain data and resolves it against Bind rows; it reads no game API.
local ADDON, ns = ...

local Catalog = {}
ns.Catalog = Catalog

local registry = {}
-- `subject = true` means "argument 1 is an ability id, declared in `abilities`". `talent = true`
-- means "argument 1 is a talent id, declared in `talents`" — a separate subject class because a
-- talent has no CDM row and must never be resolved as if it did. `aoe` takes no subject at all:
-- it is cap's OWN state (the /cap aoe toggle), the one gate that is not a game read.
local PREDICATES = {
  ready = { arity = 1, subject = true },
  proc = { arity = 1, subject = true },
  identity = { arity = 2, subject = true },
  capped = { arity = 1, subject = true },
  affordable = { arity = 1, subject = true },
  resource = { arity = 2 },
  talent = { arity = 1, talent = true },
  -- Is this AURA on its unit right now? The subject is an ability in the `auras` family, so it
  -- binds to a Cooldown Manager tracked-buff/bar row and the latch rides that row's alert edges.
  -- Unbound row (the player never enabled it) => no cid => UNKNOWN, never false. See Track.
  aura = { arity = 1, subject = true },
  -- Is the subject's OWN cooldown running while its row is displaying a different spell? The
  -- Cooldown Manager's dial resolves the display identity first, so a transformed row's swipe
  -- belongs to the replacement and the base's cooldown is drawn nowhere. UNKNOWN whenever the
  -- row is not transformed — the question only exists there. See Sense's `readBaseCooldown`.
  baseoncd = { arity = 1, subject = true },
  aoe = { arity = 0 },
}
Catalog.PREDICATES = PREDICATES
-- ⚠ A KIND LISTED HERE WITH NO MATCHING BRANCH IN `Catalog.Check` IS ACCEPTED WITH ZERO FIELD
-- CHECKS. The list decides whether a display is *known*; the branch is the only thing that
-- decides whether it is *shaped right*. Add both or neither.
local DISPLAYS = {
  ["sealed-count-bands"] = true,
  ["sealed-count-bar"] = true,
  ["sealed-pandemic"] = true,
  ["sealed-proc-bar"] = true,
  ["sealed-power-percent"] = true,
  ["sealed-cooldown-range"] = true,
  ["sealed-base-cooldown"] = true,
  ["sealed-aura-remaining"] = true,
}
Catalog.DISPLAYS = DISPLAYS

-- The corner CLAIMERS (render-shelf.md Part 2.5's cession rule): kinds whose widgets sit on the
-- badge stack's corner slots. Claimed BY DECLARATION, in marker order, whether or not the
-- client is currently showing anything — that fact is sealed and the stack cannot re-flow on
-- it. Overlay assigns the slots; the row's cue badges start below them.
local CORNER_DISPLAYS = {
  ["sealed-count-bands"] = true,
  ["sealed-pandemic"] = true,
  ["sealed-base-cooldown"] = true,
}
Catalog.CORNER_DISPLAYS = CORNER_DISPLAYS

-- The kinds that draw as a LIVE COOLDOWN DIAL (render-shelf.md V21) rather than as a cue sprite:
-- a red radial on a real remaining time with a white countdown in it. Both resolve a cooldown and
-- hand the client's own duration object to a StatusBar; they differ only in WHOSE cooldown, which
-- is `Channel.lua`'s business and not this table's.
--
-- ⚠ A marker declaring one of these AND a `cue` draws that cue AS the dial, at the cue's own
-- frame level, and `Overlay` does not show the sprite for it — `timer_CW_50` is a clock face
-- frozen at 50 %, and drawing it over a clock that is telling the time is one statement made
-- twice with only one of them true.
local DIAL_DISPLAYS = {
  ["sealed-base-cooldown"] = true,
  ["sealed-cooldown-range"] = true,
  -- ...and an AURA's remaining, which is the third supplier of the same picture. It differs from
  -- the two above in resolving no cooldown at all: the slot filters to the aura, the client
  -- drains the bar off that aura's own duration object, and cap holds neither. It is a CONTAINER,
  -- so it is armed through `Channel.Arm` rather than as one of `Overlay`'s own dials — the only
  -- thing this table decides for it is that it takes the cue's level and the sprite stays down.
  ["sealed-aura-remaining"] = true,
}
Catalog.DIAL_DISPLAYS = DIAL_DISPLAYS

-- What a marker's `badge` may be: a badge whose face is a NUMBER cap authored, drawn in place of
-- the cue's sprite (render-shelf.md V22). One kind, one shape.
--
-- ⚠ THE NUMBER IS CAP'S OWN LITERAL AND ITS MARKER'S `when` IS WHAT MAKES IT TRUE. Everywhere
-- else a count is the client's — a FontString in an AuraContainer slot cap never reads back —
-- and this is legal only because a readable term has already fixed the value: `!aura(wild_imp)`
-- means zero. A numeral whose marker does not establish it would be cap asserting a count it
-- does not hold.
local BADGES = {
  numeral = true,
}
Catalog.BADGES = BADGES

-- What ONE band of a `sealed-count-bands` display draws, as meaning rather than as pixels. The
-- shelf (render-shelf.md V16/V17) owns the art each of these resolves to; a catalog picks from
-- this list and never writes a format string.
--   none        — the resting state. The client draws nothing at all for values in this band.
--   count       — the number, while `how many more` is still the live question.
--   mark        — one badge, plate and glyph, once `how many more` has stopped being one.
-- `count` and `mark` are EXCLUSIVE. The client accepts both from one band and draws the numeral
-- on top of the glyph, in the same hue, on the same corner — a digit over a symbol, which reads
-- as a fault rather than as a statement. There is no offset that separates them without spending
-- a second corner the badge stack already wants.
-- `polarity` says which hue the band spends (V5.1: hue carries polarity and only polarity) and
-- `hatch` adds V11's stripe sheet across the face, which is the row RULED OUT rather than
-- decorated — the only thing on this list that changes the elimination walk.
local COUNT_DRAWS = {
  ["none"] = true, ["count"] = true, ["mark"] = true,
}
Catalog.COUNT_DRAWS = COUNT_DRAWS

-- The bounds every panel dimension is held to, and THE ONLY COPY OF THEM — `Anchor.Limits`
-- aliases this table, so the author's numbers and the player's are judged by one list. It lives
-- here because `tests/check_catalog.lua` loads this file WITHOUT `Anchor.lua`, which builds a
-- frame at file scope. The floor is 1 because a one-cell row is a legitimate thing to want; the
-- ceilings only stop a typo building a panel larger than the screen.
-- ⚠ `icon_px` is here because the PLAYER may set it. `Catalog.Check` rejects it by name.
local GRID_LIMITS = {
  cols = { min = 1, max = 16 },
  rows = { min = 1, max = 8 },
  icon_px = { min = 16, max = 256 },
}
Catalog.GridLimits = GRID_LIMITS

-- The grid fields an AUTHOR may declare. `cols` and `rows` fit the ROSTER — twelve entries need
-- twelve cells, which is the author's business. Icon size is taste, and taste is the player's:
-- a catalog shipping 40px icons imposes a preference rather than fitting anything.
local GRID_AUTHORABLE = { cols = true, rows = true }
Catalog.GridAuthorable = GRID_AUTHORABLE

-- The cue vocabulary is the GENERATED shelf's, read at call time rather than copied here:
-- a second list would let the addon invent a fifth cue that renders nowhere.
local function cues()
  return (ns.Style or {}).cues or {}
end

function Catalog.Register(cat)
  assert(type(cat) == "table", "Catalog.Register needs a table")
  assert(type(cat.spec) == "number", "catalog needs a numeric spec id")
  registry[#registry + 1] = cat
  return cat
end

function Catalog.All()
  return registry
end

function Catalog.ForBuild(specID, subTreeID)
  local loose
  for _, cat in ipairs(registry) do
    if cat.spec == specID then
      if cat.hero == subTreeID then return cat end
      if cat.hero == nil then loose = loose or cat end
    end
  end
  return loose
end

-- V12's two kinds of virtual row (render-shelf.md § "V12 · Virtual row"), fixed by the ability
-- rather than by the moment: `gated` availability varies and the row is hatched until a positive
-- readable verdict clears it; `standing` availability is constant and the row draws clear
-- forever. The value of the `virtual` key is the WHOLE declaration — there is no second field.
local VIRTUAL = { gated = true, standing = true }
Catalog.VIRTUAL = VIRTUAL

-- The two units an ability may name. Not a style choice: `Channel.Arm` derives the aura filter
-- from it (`unit == "player"` ⇒ HELPFUL, else HARMFUL) and hands the string straight to
-- `SetUnit`, so a typo would silently arm a container watching a unit token the client does not
-- know and the display would never draw. These are the only two that appear across all five
-- shipped catalogs.
local UNITS = { player = true, target = true }

-- Scan membership is an OR of ANDs: `scan_when` lists alternatives, each a list of readable
-- terms. An entry with no `scan_when` gets the default alternative — ready(self) — which is
-- also why the default's read is registered here: Reads/Resolve walk this too, and a row whose
-- only condition is implicit must still subscribe its readiness.
function Catalog.Alternatives(entry)
  if entry.scan_when then return entry.scan_when end
  -- ⚠ A `standing` virtual row asks for NO verdict at all, so it has no alternatives — not even
  -- the default one. Handing it ready(self) would be worse than useless twice over: it has no
  -- CDM row, so `world.ready` never carries it and the read would be UNKNOWN for life; and
  -- `eachCondition` walks this, so the synthesized term would put the ability back into
  -- `needsRow` and demand a row for the one ability whose definition is not having one.
  -- `Catalog.Check` forbids `scan_when` on a standing entry, so this is the only shape it takes.
  if entry.virtual == "standing" then return {} end
  return { { { "ready", entry.ability } } }
end

local function eachCondition(cat, fn)
  for _, entry in ipairs(cat.entries or {}) do
    local alts = Catalog.Alternatives(entry)
    for i, alt in ipairs(type(alts) == "table" and alts or {}) do
      if type(alt) == "table" then
        for _, term in ipairs(alt) do fn(entry, term, "scan_when alternative " .. i) end
      end
    end
    for _, marker in ipairs(entry.markers or {}) do
      for _, term in ipairs(marker.when or {}) do fn(entry, term, "marker " .. tostring(marker.id)) end
    end
  end
end

function Catalog.Check(cat)
  local found = {}
  local function fail(check, entry, detail)
    found[#found + 1] = { check = check, entry = entry, detail = detail }
  end

  local abilities = {}
  for _, ability in ipairs(cat.abilities or {}) do
    if type(ability.id) ~= "string" or ability.id == "" then
      fail("shape", nil, "ability has no id")
    elseif abilities[ability.id] then
      fail("shape", ability.id, "duplicate ability id")
    else
      abilities[ability.id] = ability
    end
    if type(ability.spell) ~= "number" then fail("shape", ability.id, "ability has no numeric spell id") end
    if ability.charged ~= nil and type(ability.charged) ~= "boolean" then
      fail("shape", ability.id, "charged must be boolean")
    end
    -- `unit` flows straight through `Channel.ContainerPlan` into `SetUnit`, and the aura filter
    -- (HELPFUL vs HARMFUL) is derived from it. An unrecognised token arms a container watching
    -- nothing and the sealed display never draws — a silence with no error behind it.
    if ability.unit ~= nil and not UNITS[ability.unit] then
      fail("shape", ability.id, "unit must be player or target, not " .. tostring(ability.unit))
    end
  end

  -- Talents are declared the way abilities are, and for the same reason: a term names a
  -- readable id, never a raw number. `node` + `entry` are what the trait config is keyed on —
  -- the thing the APL's `talent.<x>` actually means — so they are read directly rather than
  -- inferred from a spell being known or from how many charges a button has.
  local talents = {}
  for _, talent in ipairs(cat.talents or {}) do
    if type(talent.id) ~= "string" or talent.id == "" then
      fail("shape", nil, "talent has no id")
    elseif talents[talent.id] then
      fail("shape", talent.id, "duplicate talent id")
    else
      talents[talent.id] = talent
    end
    if type(talent.node) ~= "number" then fail("shape", talent.id, "talent has no numeric node id") end
    if type(talent.entry) ~= "number" then fail("shape", talent.id, "talent has no numeric entry id") end
  end

  -- Every ability a virtual entry declares. Collected because a virtual ability has no CDM row
  -- BY DEFINITION, and every `subject` predicate is sourced from one — see the refusal below.
  local virtualAbilities = {}

  local entries = {}
  for _, entry in ipairs(cat.entries or {}) do
    if type(entry.id) ~= "string" or entry.id == "" then
      fail("shape", nil, "entry has no id")
    elseif entries[entry.id] then
      fail("shape", entry.id, "duplicate entry id")
    else
      entries[entry.id] = true
    end
    if not abilities[entry.ability] then
      fail("subject", entry.id, "entry names an undeclared ability")
    end
    -- The role-tier `bands` left the model 2026-08-25. Reject them by name so a stale catalog
    -- fails loudly instead of silently losing its membership conditions to the default.
    if entry.bands ~= nil then
      fail("shape", entry.id, "entry declares retired `bands`; membership is `scan_when`")
    end
    -- V12. `virtual` is the whole declaration of a cap-owned icon, and the two kinds differ in
    -- exactly one thing: whether the row asks for a verdict at all.
    if entry.virtual ~= nil then
      virtualAbilities[entry.ability] = true
      if not VIRTUAL[entry.virtual] then
        fail("shape", entry.id, "virtual must be gated or standing, not " .. tostring(entry.virtual))
      elseif entry.virtual == "standing" and entry.scan_when ~= nil then
        -- A standing row is the terminus of the elimination walk: it draws clear, permanently.
        -- A condition beside it would silently decide whether the terminus is there at all,
        -- which is a contradiction rather than a refinement.
        fail("shape", entry.id, "a standing virtual row asks for no verdict and takes no scan_when")
      elseif entry.virtual == "gated" and entry.scan_when == nil then
        -- ⚠ THE DEFAULT ALTERNATIVE IS A TRAP HERE. `Catalog.Alternatives`' default is
        -- ready(self), and a virtual ability has no CDM row, so `world.ready` never carries it:
        -- the read would be UNKNOWN for life and — V12 inverting the unknown polarity — the row
        -- would draw hatched forever. Safe, and useless. The author says what makes it available.
        fail("shape", entry.id, "a gated virtual row needs an explicit scan_when")
      end
    end
    if entry.scan_when ~= nil then
      if type(entry.scan_when) ~= "table" or #entry.scan_when == 0 then
        fail("shape", entry.id, "scan_when must be a non-empty list of alternatives")
      else
        for i, alt in ipairs(entry.scan_when) do
          if type(alt) ~= "table" or #alt == 0 then
            fail("shape", entry.id, "scan_when alternative " .. i .. " has no readable condition")
          end
        end
      end
    end
    local markerIDs, positive = {}, nil
    for _, marker in ipairs(entry.markers or {}) do
      if type(marker.id) ~= "string" or marker.id == "" then
        fail("shape", entry.id, "marker has no id")
      elseif markerIDs[marker.id] then
        fail("shape", entry.id, "duplicate marker id " .. marker.id)
      else
        markerIDs[marker.id] = true
      end
      -- `cue` stays OPTIONAL: a marker with none is evaluated and reported but draws nothing.
      -- A marker carrying only a `display` is the shipped case; one carrying neither is legal
      -- and silent.
      if marker.cue ~= nil then
        local cue = cues()[marker.cue]
        if not cue then
          fail("cue", entry.id, "marker " .. tostring(marker.id) .. " names undeclared cue "
            .. tostring(marker.cue))
        elseif cue.polarity == "positive" and positive and positive ~= marker.cue then
          -- Badges STACK now (render-shelf.md Part 1: they flow down the right edge in `rank`
          -- order), so two cues on one entry is ordinary and no longer a collision. The one
          -- thing that stays undefined is two POSITIVE cues on a single button: pass 1 says
          -- "press the positive cue" and says nothing about which of two wins.
          fail("cue", entry.id, ("cues %s and %s are both positive on one entry; pass 1 has no "
            .. "tie-break"):format(positive, marker.cue))
        elseif cue.polarity == "positive" then
          positive = marker.cue
        end
      end
      -- A marker is a readable cue, a sealed cue, or a sealed cue WITH readable gates. The last
      -- shape exists because a graded cue may curve on exactly one secret but may be gated on as
      -- many readable facts as you like — so `when` beside a `display` never contributes a cue of
      -- its own, it only decides whether the client is allowed to paint the sealed one.
      local readable = marker.when ~= nil
      local sealed = marker.display ~= nil
      if not (readable or sealed) then
        fail("shape", entry.id, "marker " .. tostring(marker.id) .. " needs a when or a display")
      end
      -- ⚠ A SEALED DISPLAY IS AN AuraContainer THE CLIENT BUILDS AND GATES, and every one of
      -- them is parented to cap's overlay frame ON a Cooldown Manager item. A virtual row has no
      -- item underneath it, nothing has ever built one over a cap-owned frame, and the first
      -- consumer declares none — so the shape is refused rather than shipped untried. Readable
      -- markers (`when` + optional `cue`) are fine and draw as ordinary badges.
      if sealed and entry.virtual then
        fail("display", entry.id, "marker " .. tostring(marker.id)
          .. " carries a sealed display on a virtual row, which has no CDM frame to host one")
      end
      if readable and (type(marker.when) ~= "table" or #marker.when == 0) then
        fail("shape", entry.id, "marker " .. tostring(marker.id) .. " has no readable condition")
      end
      -- V22 · the numeral badge. Three checks, and the last two are the silent failures.
      if marker.badge ~= nil then
        local badge = marker.badge
        if type(badge) ~= "table" or not BADGES[badge.kind] then
          fail("badge", entry.id, "marker " .. tostring(marker.id) .. " names unsupported badge "
            .. tostring(type(badge) == "table" and badge.kind or nil))
        elseif type(badge.value) ~= "number" or badge.value < 0
            or badge.value ~= math.floor(badge.value) then
          fail("badge", entry.id, "marker " .. tostring(marker.id)
            .. " needs a non-negative whole badge value")
        end
        -- The numeral stands in for a CUE's badge; one without a cue would build and never draw,
        -- because `Overlay.paint` looks a numeral up by cue key off `d.badges`.
        if marker.cue == nil then
          fail("badge", entry.id, "marker " .. tostring(marker.id) .. " carries a badge with no cue")
        end
        -- ⚠ AND THIS IS THE ONE THAT FAILS SILENTLY WITHOUT IT. `Signal.markersOf` routes a
        -- marker carrying a `display` to `verdict.gates` and it NEVER contributes a cue — so a
        -- numeral declared on a display marker would pass every other gate, arm nothing, and be
        -- invisible for the life of the session with nothing anywhere saying why.
        if sealed then
          fail("badge", entry.id, "marker " .. tostring(marker.id) .. " carries a badge AND a "
            .. "display; a display marker contributes no cue, so the numeral would never draw")
        end
      end
      if sealed then
        local display = marker.display
        if type(display) ~= "table" or not DISPLAYS[display.kind] then
          fail("display", entry.id, "marker " .. tostring(marker.id) .. " names unsupported display "
            .. tostring(type(display) == "table" and display.kind or nil))
        elseif display.kind == "sealed-count-bands" then
          -- render-shelf.md V16/V17. cap authors a piecewise function over the SEALED aura
          -- application count and hands it to the client, which evaluates it and calls SetText.
          -- Nothing here is ever read back, so every check is about the AUTHORED table.
          --
          -- ⚠ This replaced `player-aura-stacks` and its `min = 2` guard on 2026-08-22. That
          -- guard was never a platform limit: `applications > 1` is Blizzard's behaviour when no
          -- formatter is passed, and passing one replaces it outright `[client 2026-08-21]`.
          if not abilities[display.ability] then
            fail("subject", entry.id, "marker " .. tostring(marker.id) .. " names undeclared ability "
              .. tostring(display.ability))
          end
          local bands = display.bands
          if type(bands) ~= "table" or #bands == 0 then
            fail("display", entry.id, "sealed-count-bands needs a bands list")
          else
            local floor
            for i, band in ipairs(bands) do
              if type(band) ~= "table" then
                fail("display", entry.id, "band " .. i .. " is not a table")
              else
                if type(band.threshold) ~= "number" or band.threshold < 0
                  or band.threshold % 1 ~= 0 then
                  fail("display", entry.id, "band " .. i .. " needs a non-negative whole threshold")
                elseif floor and band.threshold <= floor then
                  -- Monotone, because the client picks the HIGHEST threshold a value reaches: an
                  -- out-of-order or repeated breakpoint makes one band unreachable and the
                  -- authored table stops describing what draws.
                  fail("display", entry.id, "bands must rise: threshold " .. band.threshold
                    .. " does not exceed " .. floor)
                else
                  floor = band.threshold
                end
                -- ⚠ A BAND NAMES WHAT IT MEANS, NEVER A FORMAT STRING. The client's breakpoint
                -- takes a `format`, but a format carrying a texture escape is a pixel decision,
                -- and pixels are render-shelf.md's. `Channel.CountRules` builds the string from
                -- `ns.Style.count`; a catalog that wrote one directly would put the style in the
                -- gameplay file where nothing regenerates it.
                if not COUNT_DRAWS[band.draw] then
                  fail("display", entry.id, "band " .. i .. " names unsupported draw "
                    .. tostring(band.draw))
                end
                if band.polarity ~= nil and band.polarity ~= "positive"
                  and band.polarity ~= "negative" then
                  fail("display", entry.id, "band " .. i .. " polarity must be positive or negative")
                end
                if band.hatch ~= nil and type(band.hatch) ~= "boolean" then
                  fail("display", entry.id, "band " .. i .. " hatch must be boolean")
                end
              end
            end
            -- The lowest band is the RESTING state and every value below the next threshold
            -- lands in it. Without one starting at zero the client has no rule for a low count
            -- and falls back to its own default, which is the behaviour this kind replaced.
            if type(bands[1]) == "table" and bands[1].threshold ~= 0 then
              fail("display", entry.id, "the first band must start at threshold 0")
            end
          end
        elseif display.kind == "sealed-count-bar" then
          -- render-shelf.md V18. The same sealed count as a FILL. `max` reaches the client as
          -- `maxApplications` and SetValue clamps into [0, max], so it is authored as the number
          -- past which nothing more can be said -- usually the aura's real cap, and on an aura
          -- with a higher one, the number that matters. The whole-bar red flip at that value is
          -- V18's own, unconditional: a catalog names no pixels and carries no switch for it.
          --
          -- (A `full = true` key lived here until 2026-08-26. It was inert -- `BarPlan` copied it
          -- to `plan.full` and nothing ever read it, while `Channel.Arm` armed the flip slot on
          -- the KIND alone -- and it had been cited in prose as though it fired the flip. A field
          -- that reads as a switch and switches nothing is worse than no field, so it is gone
          -- rather than wired: the shelf owns the flip.)
          if not abilities[display.ability] then
            fail("subject", entry.id, "marker " .. tostring(marker.id) .. " names undeclared ability "
              .. tostring(display.ability))
          end
          if type(display.max) ~= "number" or display.max <= 0 or display.max % 1 ~= 0 then
            fail("display", entry.id, "sealed-count-bar needs a positive whole max")
          end
        elseif display.kind == "sealed-pandemic" then
          -- render-shelf.md V19. The WINDOW carries no authored threshold — the client computes
          -- it per spell, which is exactly the property that makes it good. The optional
          -- `outside_s` is the pair's other state (the gold do-not-refresh hatch) and that one
          -- IS the catalog's number, drawn off the aura's remaining seconds.
          if not abilities[display.ability] then
            fail("subject", entry.id, "marker " .. tostring(marker.id) .. " names undeclared ability "
              .. tostring(display.ability))
          end
          if display.outside_s ~= nil
            and (type(display.outside_s) ~= "number" or display.outside_s <= 0) then
            fail("display", entry.id, "sealed-pandemic outside_s must be a positive number of seconds")
          end
        elseif display.kind == "sealed-power-percent" then
          -- The break point is NEVER authored as a percentage: the percentage depends on the
          -- player's max power, which only the client can read. It is authored either as a
          -- GENERATION amount (break at `(max - generation)/max` — "one more press overflows")
          -- or as an absolute resource THRESHOLD lifted off a priority condition (break at
          -- `threshold/max`). Exactly one, because two would be two break points.
          if type(display.power) ~= "string" then
            fail("display", entry.id, "sealed-power-percent needs a power type name")
          end
          local generation = type(display.generation) == "number" and display.generation or nil
          local threshold = type(display.threshold) == "number" and display.threshold or nil
          if (generation == nil) == (threshold == nil) then
            fail("display", entry.id,
              "sealed-power-percent needs exactly one of generation or threshold")
          elseif (generation or threshold) <= 0 then
            fail("display", entry.id,
              "sealed-power-percent needs a positive generation or threshold")
          end
          -- Unlike a readable marker, a graded one has no verdict to report: the cue IS the
          -- whole of it, so a graded display without one would arm and draw nothing.
          if marker.cue == nil then
            fail("cue", entry.id, "marker " .. tostring(marker.id) .. " is a graded display with no cue")
          end
        elseif display.kind == "sealed-cooldown-range" then
          if not abilities[display.ability] then
            fail("subject", entry.id, "marker " .. tostring(marker.id) .. " names undeclared ability "
              .. tostring(display.ability))
          end
          -- `within` = "ends inside this many seconds"; `beyond` = "has at least this long
          -- left". One alone is a one-sided hold; BOTH is the two-sided band (hold while
          -- remaining is inside (beyond, within) — catalog.md Defeats item 1, closed
          -- 2026-08-24), which demands beyond < within because the reversed pair is an empty
          -- band that would arm and never draw.
          local within = type(display.within) == "number" and display.within or nil
          local beyond = type(display.beyond) == "number" and display.beyond or nil
          if within == nil and beyond == nil then
            fail("display", entry.id,
              "sealed-cooldown-range needs within, beyond, or both (the two-sided band)")
          elseif (within or beyond) <= 0 or (beyond or 1) <= 0 then
            fail("display", entry.id,
              "sealed-cooldown-range needs a positive window in seconds")
          elseif within and beyond and beyond >= within then
            fail("display", entry.id,
              "two-sided sealed-cooldown-range needs beyond < within — the reversed pair is "
              .. "an empty band that arms and never draws")
          end
          if marker.cue == nil then
            fail("cue", entry.id, "marker " .. tostring(marker.id) .. " is a graded display with no cue")
          end
        elseif display.kind == "sealed-base-cooldown" then
          -- V21. The subject names the row whose own cooldown this draws while the row is
          -- wearing something else, so it must be declared — but the id the dial actually reads
          -- is the BOUND ROW's `base`, not this declaration's `spell`: an entry covering both
          -- halves of a choice node binds through `alt` and the declared id is then the wrong
          -- half (`Channel.BaseCooldownPlan`). Nothing else to check: the display carries no
          -- numbers of its own — the remaining time is the client's and cap never learns it.
          if not abilities[display.ability] then
            fail("subject", entry.id, "marker " .. tostring(marker.id) .. " names undeclared ability "
              .. tostring(display.ability))
          end
        elseif display.kind == "sealed-aura-remaining" then
          -- V21's third supplier: an aura's remaining, in the badge's place. The subject must be
          -- a declared ability, and the marker MUST declare a cue — the dial stands in for that
          -- cue's badge, and one without a cue would be an ornament wearing the badge's corner.
          -- No numbers of its own: the remaining is the client's and cap never learns it.
          if not abilities[display.ability] then
            fail("subject", entry.id, "marker " .. tostring(marker.id) .. " names undeclared ability "
              .. tostring(display.ability))
          end
          if marker.cue == nil then
            fail("cue", entry.id, "marker " .. tostring(marker.id)
              .. " is a sealed-aura-remaining display with no cue; it stands in for a cue's badge")
          end
        elseif display.kind == "sealed-proc-bar" then
          -- V20: the proc's remaining lifetime as a bar above the charge bar. The subject must
          -- be a declared ability (normally an aura-family one); it carries no cue — the fill
          -- is the whole statement — and no numbers of its own, so there is nothing else to
          -- check.
          if not abilities[display.ability] then
            fail("subject", entry.id, "marker " .. tostring(marker.id) .. " names undeclared ability "
              .. tostring(display.ability))
          end
        end
      end
    end
  end

  local usesResource = false
  eachCondition(cat, function(entry, term, where)
    local name = type(term) == "table" and term[1] or nil
    local spec = name and PREDICATES[name]
    if not spec then
      fail("predicate", entry.id, where .. " names unsupported predicate " .. tostring(name))
      return
    end
    if #term ~= spec.arity + 1 then
      fail("predicate", entry.id, ("%s %s takes %d argument(s)"):format(where, name, spec.arity))
      return
    end
    if spec.subject and not abilities[term[2]] then
      fail("subject", entry.id, where .. " names undeclared ability " .. tostring(term[2]))
    end
    -- ⚠ NO SUBJECT PREDICATE CAN ASK ABOUT A VIRTUAL ABILITY, and this is the same trap the
    -- `gated`-needs-a-`scan_when` rule closes, arriving through the explicit door instead of the
    -- default one. EVERY subject read is sourced from a CDM row: `Sense.buildReads` walks
    -- `state.bound.abilities` for `proc` / `identity` / `capped` / `affordable` / `onCooldown`
    -- (Sense.lua:446), and `Track:Bind` binds `ready` / `aura` off the same list (Track.lua:35).
    -- `Catalog.Resolve` puts an ability there only when it found a row. So a term about an
    -- ability whose whole declaration is *"there is no row"* reads UNKNOWN for the life of the
    -- session — and on a virtual row, V12 inverting the unknown, that is HATCHED FOREVER with
    -- nothing anywhere saying why. Declaring `virtual` IS the author's assertion that no row
    -- exists, so this is decidable here rather than at bind time.
    -- ⚠ It bites the shapes a spec actually wants: an identity spine across a transform
    -- (Devourer's Consume → Devour) is exactly this, and it is not readable today. Refusing it
    -- at authoring time is the point — the alternative is a row that never draws and never says so.
    if spec.subject and virtualAbilities[term[2]] then
      fail("subject", entry.id, where .. " asks " .. tostring(name) .. " about "
        .. tostring(term[2]) .. ", a virtual ability — it has no CDM row, so the read is UNKNOWN "
        .. "for life and the row hatches forever")
    end
    if spec.talent and not talents[term[2]] then
      fail("subject", entry.id, where .. " names undeclared talent " .. tostring(term[2]))
    end
    if name == "identity" and term[3] ~= "base" and term[3] ~= "transformed" then
      fail("predicate", entry.id, "identity accepts only base or transformed")
    end
    if name == "resource" then
      usesResource = true
      if term[2] ~= "<=" and term[2] ~= ">=" then
        fail("predicate", entry.id, "resource accepts only <= or >=")
      end
      if type(term[3]) ~= "number" then fail("predicate", entry.id, "resource threshold must be numeric") end
    end
  end)

  if usesResource and type(cat.power) ~= "string" then
    fail("shape", nil, "resource condition needs a power type")
  end
  if cat.bar ~= nil and (type(cat.bar) ~= "string" or not entries[cat.bar]) then
    fail("shape", tostring(cat.bar), "bar must name one enhanced entry")
  end

  -- ⚠ THE GRID IS THE CATALOG'S PROPOSAL, checked here rather than in the entry loop because it
  -- describes the panel and not an entry. `cols` and `rows` only; `icon_px` is refused by name
  -- so the message can say where taste is set instead of reading as a typo.
  if cat.grid ~= nil then
    if type(cat.grid) ~= "table" then
      fail("shape", tostring(cat.grid), "grid must be a table of cols and rows")
    else
      for field, v in pairs(cat.grid) do
        local lim = GRID_LIMITS[field]
        if not GRID_AUTHORABLE[field] then
          if field == "icon_px" then
            fail("shape", "icon_px",
              "icon size is the player's, not the catalog's — it is set with /cap grid")
          else
            fail("shape", tostring(field), "grid takes only cols and rows")
          end
        elseif type(v) ~= "number" or v ~= math.floor(v) then
          fail("shape", field, ("grid %s must be a whole number"):format(field))
        elseif v < lim.min or v > lim.max then
          fail("shape", field, ("grid %s must be between %d and %d"):format(field, lim.min, lim.max))
        end
      end
    end
  end

  -- ⚠ THE ROW BREAK IS A CATALOG-LEVEL KEY, checked here rather than in the entry loop above,
  -- because it names an entry instead of describing one. There is exactly one per catalog.
  --
  -- The panel is `cols x rows` cells: the catalog's own grid where it declares one, else the
  -- token in `render-tokens.json`, which is the same order `Anchor.Grid` resolves in minus the
  -- player tier a static check cannot see. Nothing is written as a literal here — a hardcoded
  -- 12 would turn widening the row back into a code change. `Anchor.Grid` is the arithmetic but
  -- cannot be called from here: `tests/check_catalog.lua` loads this file without `Anchor.lua`.
  --
  -- ⚠ THIS IS THE AUTHORED PANEL, NOT NECESSARILY THE PLAYER'S. The grid is settable per spec
  -- and hero tree (`/cap grid`) and a static check cannot know what any given player set, so
  -- what it answers is "does this catalog fit the panel it ships with" — the authoring question,
  -- and the right one at author time. The messages say so rather than implying a guarantee.
  -- `Anchor.Cells`' capacity clamp is what holds for a real player.
  local style = (ns.Style or {}).row or {}
  local authored = type(cat.grid) == "table" and cat.grid or {}
  local function dimension(field, fallback)
    for _, v in ipairs({ authored[field], style[field] }) do
      if type(v) == "number" and v == math.floor(v) then
        local lim = GRID_LIMITS[field]
        if v >= lim.min and v <= lim.max then return v end
      end
    end
    return fallback
  end
  local cols = dimension("cols", 6)
  local rowCount = dimension("rows", 2)

  -- Only the entries that get a Cooldown Manager row. A virtual entry is cap's own icon and
  -- has no cell here by construction, so counting it would fail a catalog that fits.
  --
  -- ⚠ IT STILL OVER-COUNTS BY ONE PER UTILITY-VIEWER ENTRY, and that is a known limit rather
  -- than an oversight. `Anchor.lua` re-anchors the ESSENTIAL viewer only, so an entry whose
  -- ability binds to a Utility row is skinned and hatched but never placed — Devourer's
  -- `vengeful_retreat` is the shipped example, making that catalog 6 counted against 5 actually
  -- placed. Which viewer an entry lands in is a COMMENT in the catalog today, not a field, so
  -- nothing here can read it. The error is in the safe direction (stricter than reality, never
  -- looser) and no catalog is near capacity because of it, but a `viewer` field would make the
  -- count exact — see `specs/backlog.md`.
  local placed, at = {}, {}
  for _, entry in ipairs(cat.entries or {}) do
    if type(entry.id) == "string" and not entry.virtual then
      placed[#placed + 1] = entry.id
      at[entry.id] = #placed
    end
  end

  local breakIndex
  if cat.break_before ~= nil then
    if type(cat.break_before) ~= "string" then
      fail("shape", tostring(cat.break_before), "break_before must be an entry id")
    elseif not entries[cat.break_before] then
      fail("shape", cat.break_before, "break_before names an undeclared entry")
    elseif not at[cat.break_before] then
      -- A virtual entry never reaches `Resolve`'s `byEntry`, so a break on one would fall
      -- through on every build and the key would do nothing, forever, with no error. A
      -- permanent no-op is worse than a refusal.
      fail("shape", cat.break_before, "break_before names a virtual entry, which has no row")
    elseif at[cat.break_before] == 1 then
      fail("shape", cat.break_before, "break_before names the first entry, so nothing precedes it")
    else
      breakIndex = at[cat.break_before]
    end
  end

  -- ⚠ A TRIPWIRE FOR AUTHORING, NOT A SAFETY NET. `Anchor.Plan` appends every viewer row the
  -- catalog does not name after the named ones, so a player enabling one extra ability in the
  -- Essential viewer can overflow a catalog that passes here — from outside the catalog's
  -- control and invisibly to anything static. The column clamp in `Anchor.Cells` is what
  -- actually holds at runtime; this is what tells an author before they ship.
  local n = #placed
  if n > cols * rowCount then
    fail("shape", nil, ("catalog places %d entries; its authored panel holds %d (%dx%d) — "
      .. "declare a `grid` if the roster needs more cells")
      :format(n, cols * rowCount, cols, rowCount))
  elseif breakIndex then
    -- The break decides the SPLIT, so a total that fits is not sufficient: a break authored
    -- late runs the first row past the panel's edge even though the roster fits the panel.
    if breakIndex - 1 > cols then
      fail("shape", cat.break_before,
        ("%d entries precede the break; this catalog's row holds %d"):format(breakIndex - 1, cols))
    end
    if n - breakIndex + 1 > cols then
      fail("shape", cat.break_before,
        ("%d entries follow the break; this catalog's row holds %d"):format(n - breakIndex + 1, cols))
    end
  end

  return found
end

local function findRow(ability, rows)
  local family = ability.family or "spells"
  for _, spell in ipairs({ ability.spell, unpack(ability.alt or {}) }) do
    for _, row in ipairs(rows or {}) do
      if row.family == family and row.spellIDs and row.spellIDs[spell] then return row end
    end
  end
end

function Catalog.Resolve(cat, rows)
  local out = {
    abilities = {}, entries = {}, virtual = {}, byAbility = {}, byEntry = {},
    declared = {}, dropped = {},
  }
  local needsRow = {}
  -- ⚠ A VIRTUAL ENTRY'S OWN ABILITY IS EXCLUDED, because having no CDM row is the definition of
  -- one — demanding a row for it would drop the ability and report a binding failure for the
  -- shape V12 exists to express. A CONDITION naming that ability elsewhere still needs the row:
  -- that read comes off the CDM, and `eachCondition` below is not weakened.
  for _, entry in ipairs(cat.entries or {}) do
    if not entry.virtual then needsRow[entry.ability] = true end
  end
  eachCondition(cat, function(_, term)
    local spec = PREDICATES[term[1]]
    if spec and spec.subject then needsRow[term[2]] = true end
  end)
  for _, ability in ipairs(cat.abilities or {}) do
    out.declared[ability.id] = ability
    local row = findRow(ability, rows)
    if row then
      local bound = { ability = ability, row = row }
      out.abilities[#out.abilities + 1] = bound
      out.byAbility[ability.id] = row
    elseif needsRow[ability.id] then
      out.dropped[#out.dropped + 1] = { id = ability.id, spell = ability.spell, why = "no CDM row on this build" }
    end
  end
  for _, entry in ipairs(cat.entries or {}) do
    local row = out.byAbility[entry.ability]
    if entry.virtual then
      -- Its own list, in authored order, and never `out.entries`: everything downstream of that
      -- list assumes a row to anchor to. `byEntry` stays unset for the same reason, which is
      -- also what keeps `OrderCheck` skipping these — a virtual row has no layout position.
      out.virtual[#out.virtual + 1] = { entry = entry }
    elseif row then
      -- The AUTHORED flag, never a client maxCharges read: the artifact's roster column and
      -- the live border must not be able to disagree about which rows are purple.
      local charged = (out.declared[entry.ability] or {}).charged and true or false
      out.entries[#out.entries + 1] = { entry = entry, row = row, charged = charged }
      out.byEntry[entry.id] = row
    end
  end
  return out
end

--- The authored priority against the client's own row order, or nil when they agree.
---
--- A catalog's entry order IS its priority, and the whole reading model assumes the Cooldown
--- Manager lays those rows out in that order. Nothing guarantees it — the layout is Blizzard's,
--- filtered by what the player enabled — and if it is wrong the model fails everywhere at once
--- rather than degrading per ability. This names the first pair that is out of order. It is a
--- diagnostic: it never says what to press.
function Catalog.OrderCheck(cat, resolved, rows)
  local at = {}
  for i, row in ipairs(rows or {}) do at[row] = i end
  local previous, previousID
  for _, entry in ipairs((cat or {}).entries or {}) do
    local position = at[(resolved or {}).byEntry and resolved.byEntry[entry.id]]
    if position then
      if previous and position < previous then
        return { after = entry.id, before = previousID }
      end
      previous, previousID = position, entry.id
    end
  end
end

function Catalog.CheckBound(cat, rows)
  local resolved = Catalog.Resolve(cat, rows)
  local found = {}
  for _, entry in ipairs(cat.entries or {}) do
    -- A virtual entry is exempt, not tolerated: "no CDM row" is what `virtual` declares, so
    -- reporting it here would make the correct authoring read as a binding failure.
    if not (entry.virtual or resolved.byEntry[entry.id]) then
      found[#found + 1] = { check = "binding", entry = entry.id, detail = "enhanced ability has no CDM row" }
    end
  end
  return found, resolved
end

function Catalog.Reads(cat)
  local out = { byAbility = {}, resource = false, talent = {}, aoe = false }
  eachCondition(cat, function(_, term)
    local name = term[1]
    if name == "resource" then
      out.resource = true
    elseif name == "aoe" then
      out.aoe = true
    elseif name == "talent" then
      out.talent[term[2]] = true
    elseif PREDICATES[name] and PREDICATES[name].subject then
      out.byAbility[term[2]] = out.byAbility[term[2]] or {}
      out.byAbility[term[2]][name] = true
    end
  end)
  return out
end
