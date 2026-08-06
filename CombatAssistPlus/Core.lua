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

local function cmdStatus()
  local _, class = UnitClass("player")
  local specIndex = GetSpecialization and GetSpecialization()
  local specName = specIndex and select(2, GetSpecializationInfo(specIndex)) or "?"
  emit(("v%s loaded — %s %s, assist %s."):format(
    C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?",
    specName, class or "?",
    CombatAssistPlusDB.enabled and "on" or "off"))
  emit("Nothing is wired up yet. " .. KEY .. "/cap help" .. R .. " lists the commands.")
end

local function cmdToggle()
  CombatAssistPlusDB.enabled = not CombatAssistPlusDB.enabled
  emit("assist " .. (CombatAssistPlusDB.enabled and "on" or "off") .. ".")
end

-- ---------------------------------------------------------------------------
-- The command schema — the single source of truth for dispatch and help.
-- ---------------------------------------------------------------------------

ns.Commands = {
  { name = "status", desc = "Show version, spec and enabled state", handler = cmdStatus },
  { name = "toggle", desc = "Turn the assist on or off", handler = cmdToggle },
  { name = "help", desc = "Show this help", handler = function() cmdHelp() end },
}

local byName = {}
for _, c in ipairs(ns.Commands) do byName[c.name] = c end
ns.CommandByName = byName

function cmdHelp()
  emit("commands:")
  for _, c in ipairs(ns.Commands) do
    local line = "  " .. KEY .. "/cap " .. c.name .. R
    if c.args and c.args ~= "" then line = line .. " " .. c.args end
    emit(line .. " — " .. c.desc)
  end
end

-- Exact match only, then a prefix suggestion. Never substring-match a command.
function ns.Dispatch(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "" then cmdStatus(); return end
  local c = byName[cmd]
  if c then c.handler(rest); return end
  for _, cand in ipairs(ns.Commands) do
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
