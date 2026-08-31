-- The status verdict is a PURE classifier over three tables, which is the only reason it can be
-- tested at all — the formatting around it touches the client and deliberately is not here.
--
-- What these protect: the ORDER. The verdict names the FIRST failing term and stops, because a
-- diagnosis that lists six complaints when one is the cause is noise. A reordering would still
-- produce true statements and a much worse answer, and nothing else would catch it.
local H = require("CombatAssistPlus.tests.mock_ns")

describe("engine / status verdict", function()
  local verdict

  before_each(function()
    local ns = H.fresh()
    H.load(ns, "Status.lua")
    verdict = ns.Status.Verdict
  end)

  local function ok(over)
    local b = { observed = true, viewers = 4, frames = 30, rows = 28 }
    for k, v in pairs(over or {}) do b[k] = v end
    return b
  end
  local function healthy(over)
    local h = { catalog = "Demonology / Diabolist", entries = 9, bound = 7,
                settled = true, settledBy = "spells-changed", dark = false }
    for k, v in pairs(over or {}) do h[k] = v end
    return h
  end

  local function state(enabled, bind, health, notOrdering)
    local s = verdict(enabled, bind, health, notOrdering)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  end

  it("says WORKING only when every term holds", function()
    assert.equals("WORKING", state(true, ok(), healthy()))
  end)

  it("reports being switched off before anything else", function()
    assert.equals("OFF", state(false, ok{ observed = false }, healthy{ settled = false }))
  end)

  -- Written out rather than built from `healthy{ catalog = nil }`, which sets nothing: a nil
  -- value is simply absent from the override table, so the base catalog would survive and the
  -- test would pass on the wrong branch.
  it("calls a spec with no catalog by its own name, not a failure", function()
    assert.equals("NO CATALOG",
      state(true, ok(), { entries = 0, bound = 0, settled = false, dark = false }))
  end)

  -- The 2026-08-23 defect, as a test: an unfinished sweep is NOT DRAWING and must say so.
  it("names an unfinished sweep, and names it above an unsettled roster", function()
    local s, why = verdict(true, ok{ observed = false }, healthy{ settled = false })
    assert.equals("NOT DRAWING", (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    assert.truthy(why:find("sweep has not finished"))
  end)

  -- ⚠ The point of the whole change: rows cap cannot read are reported, never a verdict.
  it("stays WORKING when the Cooldown Manager holds rows cap cannot read", function()
    assert.equals("WORKING",
      state(true, ok{ unreadable = 2, unreadableAt = "E:3:norow,BI:2:norow" }, healthy()))
  end)

  it("separates not-yet-settled from dark-for-the-fight", function()
    assert.equals("WAITING", state(true, ok(), healthy{ settled = false }))
    assert.equals("DARK FOR THIS FIGHT", state(true, ok(), healthy{ dark = true }))
  end)

  it("reports a bound roster of zero rather than claiming to work", function()
    assert.equals("NOT DRAWING", state(true, ok(), healthy{ bound = 0 }))
  end)

  -- ⚠ THE LINE IN THE SAND (`spec.md` §1). Ordering and the augments are one product: the
  -- scan is a claim about POSITION, so on a row cap did not order there is nothing true to
  -- draw. These protect the PLACE of that term in the order — it sits directly under "off",
  -- above every finer diagnosis, because while it holds none of them is worth reporting.
  it("reports not ordering above every finer diagnosis", function()
    assert.equals("DARK — NOT ORDERING",
      state(true, ok(), healthy{ settled = false, dark = true }, "off"))
  end)

  it("still reports being switched off first, since that is the one the player did", function()
    assert.equals("OFF", state(false, ok(), healthy(), "off"))
  end)

  it("names a rider stand-down as the same dark state", function()
    assert.equals("DARK — NOT ORDERING", state(true, ok(), healthy(), "rider"))
  end)

  it("says nothing about ordering when cap is ordering", function()
    assert.equals("WORKING", state(true, ok(), healthy(), nil))
  end)

  -- The two causes are not interchangeable to a player: one is a setting they can flip and
  -- one is another addon they have to disable, so the ADVICE has to differ even though the
  -- state does not.
  it("gives a different reason for each cause", function()
    local _, offWhy = verdict(true, ok(), healthy(), "off")
    local _, riderWhy = verdict(true, ok(), healthy(), "rider")
    assert.truthy(offWhy:find("/cap anchor on", 1, true))
    assert.truthy(riderWhy:find("another addon", 1, true))
  end)
end)
