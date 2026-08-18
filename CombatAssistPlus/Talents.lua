-- Talents.lua — which of the catalog's declared talents are actually taken.
--
-- WHY THIS EXISTS AND WHY IT READS WHAT IT READS. A priority list branches on talents
-- (`talent.a_fire_inside`), and a catalog that cannot see them either badges a build it was not
-- written for or drops a rule the build needs. The measured case: on a loadout without A Fire
-- Inside, Immolation Aura is a ONE-charge button, so "at max charges" is true whenever the
-- button is ready and the gold `capped` badge would ride the row permanently.
--
-- ⚠ It reads the TRAIT CONFIG, not a proxy. Two proxies are available and both are rejected on
-- purpose: `C_SpellBook.IsSpellKnown` answers about a spell, and max-charge count answers about
-- a button, and each stands in for the talent rather than being it. A proxy can diverge from the
-- thing it stands for — a spell known from another source, a charge granted by something else —
-- and when it does the failure is silent. The principle: key off what the APL keys off, whenever
-- that is readable.
--
-- ⚠ `[gap]` THE EXACT CALL IS UNMEASURED. `knowledge/addon-dev/` records nothing about
-- `C_Traits.GetNodeInfo` — not its shape, not whether `ranksPurchased` / `activeEntry` survive
-- combat restriction. Nothing here asserts that they do: every read is `pcall`ed and every
-- non-answer becomes `nil`, which `Signal` turns into UNKNOWN and which therefore draws NOTHING.
-- An unmeasured read that refuses costs a badge; it can never invent one. Resolve the marker by
-- measuring, not by trusting this comment.
--
-- Talents cannot change in combat, so the read is cached and this is not a combat-path concern.
local ADDON, ns = ...

local issecretvalue = issecretvalue

ns.Talents = ns.Talents or {}
local Talents = ns.Talents

-- ---------------------------------------------------------------------------
-- Pure
-- ---------------------------------------------------------------------------

--- Is one declared talent selected, given the client's node info?
---
--- `true` = the node is purchased AND the selected entry is the declared one. `false` = it is
--- genuinely not taken. `nil` = the read refused or answered in a shape we do not recognise —
--- which is NOT "not taken", and is the whole reason this returns three values rather than two.
---
--- The entry check is what makes a choice node answer correctly: a purchased choice node has
--- ranks either way, and only `activeEntry` says which half of the choice the player picked.
function Talents.Selected(info, entryID)
  if type(info) ~= "table" or type(entryID) ~= "number" then return nil end
  local ranks = info.ranksPurchased
  if issecretvalue and issecretvalue(ranks) then return nil end
  if type(ranks) ~= "number" then return nil end
  if ranks <= 0 then return false end
  local active = info.activeEntry
  if type(active) ~= "table" then return nil end
  local id = active.entryID
  if issecretvalue and issecretvalue(id) then return nil end
  if type(id) ~= "number" then return nil end
  return id == entryID
end

--- Fold every declared talent into `{ [id] = true|false|nil }`. `nodeInfo` is a function so the
--- pure fold and the live read are the same code path — the harness passes a table lookup, the
--- client passes `C_Traits.GetNodeInfo` bound to the active config.
function Talents.Reduce(declared, nodeInfo)
  local out = {}
  if type(nodeInfo) ~= "function" then return out end
  for _, talent in ipairs(declared or {}) do
    if type(talent.id) == "string" then
      local ok, info = pcall(nodeInfo, talent.node)
      -- Written out, not `ok and Selected(...) or nil`: that idiom collapses a legitimate
      -- `false` to nil, which would turn "genuinely not taken" into "we could not tell" and
      -- silently withhold every rule the absent talent is supposed to switch off.
      if ok then out[talent.id] = Talents.Selected(info, talent.entry) end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- The live read
-- ---------------------------------------------------------------------------

--- A `nodeInfo(nodeID)` closure over the player's active trait config, or nil when the client
--- will not say. Feature-gated whole: a missing piece takes the inert path, which reports
--- nothing rather than reporting "not taken".
function Talents.Reader()
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID
      and C_Traits and C_Traits.GetNodeInfo) then
    return nil
  end
  local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
  if not (ok and type(configID) == "number") then return nil end
  return function(nodeID)
    return C_Traits.GetNodeInfo(configID, nodeID)
  end
end

local cache

--- Every event on this list is a HINT, never a fact. `cooldown-manager.md` §4 measured
-- `TRAIT_CONFIG_UPDATED` landing ~4.7 s BEFORE the dependent state settled, so no single event
-- may be trusted to mean "the answer is now correct". Dropping the cache on all of them, and
-- re-reading on the next evaluation, is the mitigation that file prescribes.
function Talents.Invalidate()
  cache = nil
end

--- The cached fold. Cheap on a hit, one config read on a miss, and re-derived rather than
--- patched — there is no partial invalidation because there is no partial change.
function Talents.Get(declared)
  if cache then return cache end
  cache = Talents.Reduce(declared, Talents.Reader())
  return cache
end

-- Guarded because the pure half above is unit-tested outside the client, where `CreateFrame`
-- does not exist. Nothing below this line runs in the harness, and nothing above it needs to.
if CreateFrame then
  local events = CreateFrame("Frame")
  for _, event in ipairs({
    "PLAYER_ENTERING_WORLD",
    "SPELLS_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "TRAIT_CONFIG_UPDATED",
    "ACTIVE_COMBAT_CONFIG_CHANGED",
  }) do
    events:RegisterEvent(event)
  end
  events:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
  events:SetScript("OnEvent", function()
    Talents.Invalidate()
  end)
end
