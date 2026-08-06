local ADDON, ns = ...

local COLOR = "|cff40ff90"
local KEY = "|cffffd100"
local ERR = "|cffff4040"
local R = "|r"
local TAG = COLOR .. "CAP" .. R

local DEFAULTS = {
  enabled = true,
}

local function emit(msg)
  print(TAG .. ": " .. msg)
end
ns.Emit = emit

-- Fills in any key the running build added without clobbering saved values.
local function applyDefaults(db)
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then db[k] = v end
  end
  return db
end

-- ---------------------------------------------------------------------------
-- Command handlers
-- ---------------------------------------------------------------------------

local cmdHelp

-- `/cap status` is the debugging surface for every feature, so each module
-- contributes its own line rather than Core knowing what they are. A reporter
-- returns a string (or nil to say nothing); it must never throw and never
-- format a secret value.
local reporters = {}
function ns.RegisterStatus(order, fn)
  assert(type(order) == "number", "RegisterStatus: order required")
  assert(type(fn) == "function", "RegisterStatus: fn required")
  reporters[#reporters + 1] = { order = order, fn = fn }
  table.sort(reporters, function(a, b) return a.order < b.order end)
end

local function cmdStatus()
  local _, class = UnitClass("player")
  local specIndex = GetSpecialization and GetSpecialization()
  local specName = specIndex and select(2, GetSpecializationInfo(specIndex)) or "?"
  emit(("v%s loaded — %s %s, assist %s."):format(
    C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?",
    specName, class or "?",
    CombatAssistPlusDB.enabled and "on" or "off"))

  local said = false
  for _, r in ipairs(reporters) do
    local ok, line = pcall(r.fn)
    if not ok then
      emit(ERR .. "  status reporter errored" .. R .. ": " .. tostring(line))
      said = true
    elseif line and line ~= "" then
      emit("  " .. line)
      said = true
    end
  end
  if not said then
    emit("Nothing is wired up yet. " .. KEY .. "/cap help" .. R .. " lists the commands.")
  end
end

local function cmdToggle()
  CombatAssistPlusDB.enabled = not CombatAssistPlusDB.enabled
  emit("assist " .. (CombatAssistPlusDB.enabled and "on" or "off") .. ".")
end

-- ---------------------------------------------------------------------------
-- The command schema — the single source of truth for dispatch and help.
-- ---------------------------------------------------------------------------

ns.Commands = {}

local byName = {}
ns.CommandByName = byName

-- Modules register their own commands from their own file, so adding one never
-- edits Core.lua. `order` sorts the help listing (default 50); registration
-- order breaks ties, so a module's commands stay grouped.
local seq = 0
function ns.RegisterCommand(cmd)
  assert(type(cmd) == "table", "RegisterCommand: expected a table")
  assert(type(cmd.name) == "string" and cmd.name ~= "", "RegisterCommand: name required")
  assert(type(cmd.handler) == "function", "RegisterCommand: handler required for " .. cmd.name)
  -- A duplicate is a programming error, but erroring here would abort the rest of
  -- the *calling file* — losing a whole module to a name clash. Complain loudly,
  -- keep the first registration, let the module finish loading.
  if byName[cmd.name] then
    emit(ERR .. "duplicate command" .. R .. " '" .. cmd.name .. "' ignored — the first registration stands.")
    return byName[cmd.name]
  end
  seq = seq + 1
  cmd.order = cmd.order or 50
  cmd.seq = seq
  cmd.desc = cmd.desc or ""
  ns.Commands[#ns.Commands + 1] = cmd
  byName[cmd.name] = cmd
  return cmd
end

-- Sorted view, rebuilt only when the set changes.
local sorted, sortedFor = {}, -1
local function commandsInOrder()
  if sortedFor ~= seq then
    sorted = {}
    for i, c in ipairs(ns.Commands) do sorted[i] = c end
    table.sort(sorted, function(a, b)
      if a.order ~= b.order then return a.order < b.order end
      return a.seq < b.seq
    end)
    sortedFor = seq
  end
  return sorted
end
ns.CommandsInOrder = commandsInOrder

function cmdHelp()
  emit("commands:")
  for _, c in ipairs(commandsInOrder()) do
    local line = "  " .. KEY .. "/cap " .. c.name .. R
    if c.args and c.args ~= "" then line = line .. " " .. c.args end
    emit(line .. " — " .. c.desc)
  end
end

ns.RegisterCommand{ name = "status", order = 10,
  desc = "Show version, spec and enabled state", handler = cmdStatus }
ns.RegisterCommand{ name = "toggle", order = 20,
  desc = "Turn the assist on or off", handler = cmdToggle }
ns.RegisterCommand{ name = "help", order = 99,
  desc = "Show this help", handler = function() cmdHelp() end }

-- Exact match only, then a prefix suggestion. Never substring-match a command.
function ns.Dispatch(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "" then cmdStatus(); return end
  local c = byName[cmd]
  if c then c.handler(rest); return end
  for _, cand in ipairs(commandsInOrder()) do
    if cand.name:sub(1, #cmd) == cmd then
      emit(ERR .. "unknown command" .. R .. " '" .. cmd .. "'. Did you mean " ..
        KEY .. "/cap " .. cand.name .. R .. "?")
      return
    end
  end
  emit(ERR .. "unknown command" .. R .. " '" .. cmd .. "'. Try " .. KEY .. "/cap help" .. R .. ".")
end

SLASH_COMBATASSISTPLUS1 = "/cap"
SlashCmdList.COMBATASSISTPLUS = ns.Dispatch

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name ~= ADDON then return end
  CombatAssistPlusDB = applyDefaults(CombatAssistPlusDB or {})
  self:UnregisterEvent("ADDON_LOADED")
end)
