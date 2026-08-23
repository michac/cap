local ADDON, ns = ...

local COLOR = "|cff40ff90"
local KEY = "|cffffd100"
local ERR = "|cffff4040"
local R = "|r"
local TAG = COLOR .. "CAP" .. R

ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "?"

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

ns.RegisterCommand{ name = "toggle", order = 20,
  desc = "Turn the assist on or off", handler = cmdToggle }
ns.RegisterCommand{ name = "help", order = 99,
  desc = "Show this help", handler = function() cmdHelp() end }

-- Exact match only, then a prefix suggestion. Never substring-match a command.
function ns.Dispatch(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  -- ⚠ BARE `/cap` ANSWERS THE QUESTION, it does not list commands. The thing a player types by
  -- reflex when something looks wrong should say whether it is wrong; a command list is what you
  -- want when you already know it works. `help` is one word away and named on the status block.
  if cmd == "" then
    local status = byName["status"]
    if status then status.handler("") else cmdHelp() end
    return
  end
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
  -- ns.db is assigned before anything that can throw. A capture stream drops every
  -- write while ns.db is unset, silently, so a load-time error here would make a
  -- whole session read back as "(no captures)" — the log has to survive it.
  CombatAssistPlusDB = CombatAssistPlusDB or {}
  ns.db = CombatAssistPlusDB
  applyDefaults(CombatAssistPlusDB)
  self:UnregisterEvent("ADDON_LOADED")
end)
