-- Channel.lua — declarative, one-way displays for facts Lua is not allowed to read.
-- AuraContainer owns acquisition and writes the secret application count directly into
-- our leaf FontString. CAP never receives, compares, type-checks, or reads the value back.
local ADDON, ns = ...

ns.Channel = ns.Channel or {}
local Channel = ns.Channel

--- Pure dependency binding. The returned plan is deliberately display vocabulary, not a
--- Signal term; tests use this same path as the live armer.
function Channel.Plan(marker, abilities)
  local display = marker and marker.display
  local ability = display and abilities and abilities[display.ability]
  if not (display and display.kind == "player-aura-stacks" and display.min == 2
      and ability and type(ability.spell) == "number") then
    return nil
  end
  return {
    kind = display.kind, spell = ability.spell, min = display.min,
    unit = "player", sink = "SetApplicationCount",
  }
end

--- Acquire one sealed display while unrestricted. The only public states are the audit
--- states: offered, armed, refused. None claims whether a secret-driven glyph appeared.
function Channel.Arm(host, marker, abilities)
  local plan = Channel.Plan(marker, abilities)
  if not plan or not host or InCombatLockdown() then return nil, "refused" end
  if not (C_AddOns and C_AddOns.LoadAddOn) then return nil, "refused" end

  local okLoad = pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
  if not okLoad then return nil, "refused" end

  local container
  local ok = pcall(function()
    container = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
    container:SetAllPoints(host)
    container:AddAuraSlot(marker.id, "HELPFUL", {
      candidateFilters = {
        includeSpellIDs = { [plan.spell] = true },
        isFromPlayerOrPlayerPet = true,
      },
      initializeFrame = function(button)
        button:SetAllPoints(container)
        local count = button:CreateFontString(nil, "OVERLAY")
        count:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        count:SetPoint("TOP", button, "TOP", 0, 1)
        button:SetApplicationCount(count)
      end,
    })
    container:SetUnit("player")
    container:UpdateAllAuras()
  end)
  if not ok then
    if container then container:Hide() end
    return nil, "refused"
  end
  return container, "armed"
end
