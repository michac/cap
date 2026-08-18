-- Mode.lua — the target mode you set, and the panel row that says which.
--
-- `mode(x)` is the one gate that is not a game read: the client will not tell an addon
-- how many things it is fighting, so cap asks you and branches on its own state. It is
-- persisted, because a toggle that silently resets each login is a worse surprise than
-- one that remembers; `single` is the resting state, where a wrong guess costs least.
local ADDON, ns = ...

local SINGLE, AOE = "single", "aoe"

ns.Mode = ns.Mode or {}
local Mode = ns.Mode

-- File scope runs before ADDON_LOADED, so the scratch carries the shape until ns.db
-- exists — the same reason, and the same shape, as Frame.lua's.
local scratch = {}
local function store()
  local root = ns.db or scratch
  if root.mode ~= SINGLE and root.mode ~= AOE then root.mode = SINGLE end
  return root
end

function Mode.Get()
  return store().mode
end

function Mode.IsAoE()
  return store().mode == AOE
end

-- ---------------------------------------------------------------------------
-- The panel row
-- ---------------------------------------------------------------------------

local row, label

local function paint()
  if not label then return end
  local aoe = Mode.IsAoE()
  label:SetText(aoe and "AOE" or "single target")
  if aoe then
    label:SetTextColor(1.0, 0.82, 0.0)
  else
    label:SetTextColor(0.55, 0.55, 0.55)
  end
end

local function build()
  if row then return end
  row = CreateFrame("Frame", nil, ns.Frame.Get())
  label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("LEFT", row, "LEFT", 0, 0)
  label:SetJustifyH("LEFT")
  ns.Frame.Attach(row, 14)
  paint()
end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------

local function set(value)
  store().mode = value
  paint()
  -- The toggle is a catalog gate now (the `aoe` predicate), so flipping it changes what the
  -- row draws — and nothing else would wake the verdict. `Bind.Evaluate` re-runs the verdict
  -- only; it never re-resolves rows, so it is safe to call mid-combat, which is exactly when
  -- a player reaches for this.
  if ns.Bind and ns.Bind.Evaluate then ns.Bind.Evaluate("mode") end
  ns.Emit("target mode: " .. value .. ".")
end

-- A schema table, not a substring match: `rest:find("on")` also matches "off". The two
-- explicit verbs exist because a macro needs a deterministic result and a toggle has none.
local aoeActions = {
  [""] = function() set(Mode.IsAoE() and SINGLE or AOE) end,
  on = function() set(AOE) end,
  off = function() set(SINGLE) end,
}

ns.RegisterCommand{
  name = "aoe", order = 30, args = "[on|off]",
  desc = "Switch the target mode cap grades against",
  handler = function(rest)
    local action = aoeActions[(rest or ""):lower()]
    if not action then
      ns.Emit("usage: /cap aoe  or  /cap aoe on  or  /cap aoe off")
      return
    end
    action()
  end,
}

-- PLAYER_LOGIN, not ADDON_LOADED: Frame.lua lays the panel out there.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
  build()
end)
