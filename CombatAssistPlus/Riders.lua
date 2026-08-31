-- Riders.lua — the vocabulary of standing down beside another addon that arranges the
-- Cooldown Manager's item frames.
--
-- Two addons that each hook a frame's SetPoint and force it back to their own anchor
-- recurse without bound inside one call stack, so cap orders nothing while one of them is
-- managing the row. Anchor.lua owns the frames and the dialog; everything here is plain
-- data and text, which is what makes the decision testable.
local ADDON, ns = ...

ns.Riders = ns.Riders or {}
local Riders = ns.Riders

--- Addon folder to the label a player would recognise on their addon list. Being on this
--- list only decides WHO to name; whether that addon is actually placing the row is a
--- separate, positional question.
Riders.Known = {
  { addon = "EllesmereUICooldownManager", label = "EllesmereUI Cooldown Manager" },
  { addon = "BetterCooldownManager",      label = "Better Cooldown Manager" },
  { addon = "CooldownManagerCentered",    label = "Cooldown Manager Centered" },
  { addon = "SkironCooldownManager",      label = "Skiron Cooldown Manager" },
  { addon = "ArcUI",                      label = "ArcUI" },
  { addon = "Ayije_CDM",                  label = "Ayije CDM" },
}

--- The known riders loaded right now, as labels in table order. `isLoaded` is passed in
--- rather than read from the environment so the decision runs outside the client.
function Riders.Loaded(isLoaded)
  local out = {}
  if type(isLoaded) ~= "function" then return out end
  for _, rider in ipairs(Riders.Known) do
    local ok, loaded = pcall(isLoaded, rider.addon)
    if ok and loaded then out[#out + 1] = rider.label end
  end
  return out
end

--- Is somebody else placing the row? `frames` is one array of owner tags per item frame —
--- "viewer" for Blizzard's own layout, "cap" for cap's anchor, "other" for anyone else.
--- One stranger settles it: Blizzard writes a single point per item frame, so a point
--- naming anything outside the viewer's subtree is an addition somebody made.
function Riders.Managing(frames)
  for _, tags in ipairs(frames or {}) do
    for _, tag in ipairs(tags or {}) do
      if tag == "other" then return true end
    end
  end
  return false
end

--- The labels as one noun phrase, or nil for none.
function Riders.Phrase(labels)
  labels = labels or {}
  local n = #labels
  if n == 0 then return nil end
  if n == 1 then return labels[1] end
  return table.concat(labels, ", ", 1, n - 1) .. " and " .. labels[n]
end

--- What the player is told, or nil when there is nothing to say. An empty label list still
--- produces text — the crash backstop knows something is fighting it without knowing who.
function Riders.Message(labels, managing)
  if not managing then return nil end
  labels = labels or {}
  local who, verb = Riders.Phrase(labels), (#labels == 1 and "is" or "are")
  if not who then who, verb = "Another addon", "is" end
  return who .. " " .. verb .. " also arranging the Cooldown Manager's icons. Two addons "
    .. "cannot order the same icons, so cap has stood down.\n\n"
    .. "Combat Assist Plus is drawing nothing. Its whole reading is left-to-right, so an "
    .. "overlay on a row it did not order would be pointing at the wrong icon — better "
    .. "nothing than a scan that lies.\n\n"
    .. "Disable one of them and reload to get cap back."
end
