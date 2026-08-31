-- Status.lua — `/cap status`: is it working, and if not, why.
--
-- ⚠ THIS EXISTS BECAUSE A DARK OVERLAY AND A WORKING ONE LOOK IDENTICAL. cap draws nothing on a
-- row it has no opinion about, which is correct and is also indistinguishable from cap being
-- broken. On 2026-08-23 one unreadable Cooldown Manager row held the settle open and cap sat dark
-- through a whole session; the answer was in the capture file the entire time, and a capture file
-- is not a thing anyone should have to read to find out whether their addon is on.
--
-- It reads accessors and formats them. It computes no state, caches nothing, and is safe to run
-- in combat. Every number here already exists somewhere — this is the one place they are put
-- beside each other, because the diagnosis is always in the JOIN and never in one of them.
local ADDON, ns = ...

local KEY, OK, ERR, WARN, R = "|cff8ab4f8", "|cff8bd17c", "|cffe06c75", "|cffe5c07b", "|r"

local num = ns.num

local function row(label, value)
  ns.Emit(("  %-11s%s"):format(label, value))
end

--- The first line, and the only one most readings need. Ordered by what a player would fix
--- first, so the FIRST failing term is named and the rest are not — a list of six complaints
--- when one of them is the cause is how a diagnosis becomes noise.
--- `notOrdering` is `Anchor.NotOrdering()`'s answer — "off", "rider", or nil — passed IN
--- rather than read off the namespace, so this stays a pure classifier over its arguments.
local function verdict(enabled, bind, health, notOrdering)
  if not enabled then return ERR .. "OFF" .. R, "you turned it off — /cap toggle" end
  -- Second, and above everything below it: without the order there is nothing true to draw
  -- (`spec.md` §1), so every finer diagnosis underneath is moot while this holds.
  if notOrdering == "off" then
    return ERR .. "DARK — NOT ORDERING" .. R,
      "row ordering is off, and the scan is a claim about position — cap draws nothing "
      .. "without it (/cap anchor on)"
  elseif notOrdering then
    return ERR .. "DARK — NOT ORDERING" .. R,
      "another addon is arranging the Cooldown Manager's icons, so cap cannot order the row "
      .. "and draws nothing (/cap anchor for the details)"
  end
  if not health.catalog then
    return WARN .. "NO CATALOG" .. R, "this spec and hero pair has none, which is by design"
  end
  if not bind.observed then
    return ERR .. "NOT DRAWING" .. R,
      ("the Cooldown Manager sweep has not finished — %s viewer(s) answered, %s frame(s) seen")
        :format(num(bind.viewers), num(bind.frames))
  end
  if health.bound == 0 then
    return ERR .. "NOT DRAWING" .. R, "no catalog entry bound to a Cooldown Manager row"
  end
  if not health.settled then
    return WARN .. "WAITING" .. R, "bound, not yet settled — this clears on its own in a few seconds"
  end
  if health.dark then
    return WARN .. "DARK FOR THIS FIGHT" .. R,
      "combat began before the roster settled; cap will not change what it emphasises mid-pull"
  end
  return OK .. "WORKING" .. R, nil
end

local function cmdStatus()
  local enabled = ns.db and ns.db.enabled and true or false
  local bind = (ns.Bind and ns.Bind.Snapshot and ns.Bind.Snapshot()) or {}
  local health = (ns.Sense and ns.Sense.Health and ns.Sense.Health()) or {}

  local state, why = verdict(enabled, bind, health,
    ns.Anchor and ns.Anchor.NotOrdering and ns.Anchor.NotOrdering())
  ns.Emit(("Combat Assist Plus %s — %s"):format(ns.version or "?", state))
  if why then ns.Emit("  " .. why) end

  row("catalog", health.catalog
    and ("%s — %s of %s entries bound"):format(health.catalog, num(health.bound), num(health.entries))
    or "none for this spec and hero")
  row("sweep", ("%s · %s viewer(s) · %s frame(s) · %s row(s)"):format(
    bind.observed and "finished" or (ERR .. "unfinished" .. R),
    num(bind.viewers), num(bind.frames), num(bind.rows)))

  -- ⚠ Printed even at ZERO, and that is deliberate. A row cap cannot read is NOT a fault and no
  -- longer blocks anything, but it used to, and a line that appears only on failure teaches the
  -- reader nothing about what normal looks like.
  local at = bind.unreadableAt
  row("unreadable", (bind.unreadable or 0) == 0 and "none"
    or ("%s (%s) — ignored, not a fault"):format(num(bind.unreadable), (at ~= "" and at) or "?"))

  row("settle", health.settled
    and ("settled by %s"):format(health.settledBy or "?")
    or "not settled")
  row("order", (ns.Anchor and ns.Anchor.Status and ns.Anchor.Status()) or "unavailable")
  row("combat", health.combat and "in combat" or "out of combat")
  row("edges", ("%s accepted · %s refused · %s hook(s)"):format(
    num(health.edges), num(health.refused), num(health.hooks)))

  ns.Emit("  " .. KEY .. "/cap help" .. R .. " for commands")
end

-- Guarded exactly as `Channel.lua`'s command is: the pure half of this file is under test, and
-- the harness loads a module without Core's command registry.
if ns.RegisterCommand then
  ns.RegisterCommand{
    name = "status", order = 10,
    desc = "Is the assist working, and if not, why",
    handler = cmdStatus,
  }
end

ns.Status = { Verdict = verdict, Show = cmdStatus }
