# Combat Assist Plus — addon repo (michac/cap)

A **standalone GitHub repo** for the Combat Assist Plus WoW addon, checked out
**inside** the wow workspace at `projects/combat-assist/addon/` but with its
**own git root** (`michac/cap`). The parent workspace **gitignores this folder**
(`/projects/combat-assist/addon/`) so the workspace never sees it as an embedded
repo — exactly how `planner-state/` (michac/wow-planner-state),
`projects/keybinder/addon/` (michac/BucketBinds) and
`projects/cooldown-hud/addon/` (michac/CDMProbe) are handled.

Don't confuse this checkout with the **installed** copy under
`…/_retail_/Interface/AddOns/CombatAssistPlus/`. This is the **source of truth**;
the installed copy is what `ghaddons` deploys.

## What it is

A `.toc`, a namespace, SavedVariables and the schema-driven slash router
(`/cap`), plus the M2 foundation: `Bind.lua` binds Blizzard's Cooldown Manager
into a row list and holds a **health verdict** on that binding; `Frame.lua` is
the movable panel the rows attach to; `Capture.lua` (vendored) and `Log.lua`
report what the binding did to a capture log. It registers real events —
specialization change, Cooldown-Manager churn, UI scale — not just
`ADDON_LOADED`.

On top of it, the tier signal: `Catalog.lua` + `Catalogs/Demonology.lua` (the
closed vocabulary and the spec's five checks), `Tier.lua` and `Track.lua` (pure),
`Treatment.lua` (tier → look — **the only place the visual numbers exist**),
`Sense.lua` (hooks, clock, client reads), `Channel.lua` (**the only place the two
sealed comparisons live** — cap offers, the client decides) and `Overlay.lua`
(cap's own frames, anchored to the CDM icons, painted from `Sense.OnVerdicts`). On the same
verdicts, `Bars.lua` draws §3.4's cooldown bars into `Frame.lua`'s panel — the client is handed
a duration object and cap is never told what it drew.

⚠ **What has run in the client stops at `Sense.lua`.** The binding and the tier
verdicts were flown; **`Treatment.lua`, `Channel.lua`, `Overlay.lua`, `Glow.lua` and
`Bars.lua` have never executed there** — no pixel this addon draws has been observed. The pure modules are
covered by `busted`; the overlay is not testable at a desk and is verified by a
flight and an eyeball, with `wowkb.capture cap draw` as the only instrument.

⚠ **And no channel here has a readback.** `SetText`/`SetAlpha` accept a secret and hand
nothing back, and every duration sink is aspect-less — so `draw`'s `C{}` and `B{}` report only
whether cap **armed** a cue or a bar, never whether either appeared. Anything stronger than
that has to come from an eyeball.

**What it's supposed to do lives outside this repo**, on the workspace side at
`projects/combat-assist/specs/` — `spec.md` (the product definition),
`backlog.md` (work items), `notes.md` (session log + decisions). That project
root's `CLAUDE.md` describes how the three fit together. Read `spec.md` before
building anything here — especially §1's three principles, which everything else in
the spec is downstream of.

## House rules

This addon follows the workspace's addon house rules — read
`.claude/skills/wow-developer/references/house-rules.md` before writing code.
The two that bite first in a young addon:

- **Commands come from the `ns.Commands` schema table** (`Core.lua`), never a
  hand-rolled parser. Max depth `/cap <verb> [<arg>]`. **No substring dispatch.**
- **One capture path, and it is live.** `Log.lua` writes
  `CombatAssistPlusDB.captures.bind` via `ns.Capture.Open(...)`; it is read with
  `uv run python -m wowkb.capture cap bind` and by nothing else. A second stream
  goes in the same `captures` table or it doesn't exist. The contract is
  `.claude/skills/wow-developer/references/capture-and-dump-standard.md` —
  `Capture.lua` here is vendored from it, so adapt the Lua freely but keep the
  wire format byte-exact, because the shared Python reader is the only check on
  it. ⚠ SavedVariables only flush on `/reload` or logout.

## Release workflow

The **mechanical recipe lives in `wowkb.addon`**, not here. From the workspace:

```bash
cd ~/code/fun/wow/tools
uv run python -m wowkb.addon release cap [--patch|--minor|--major]
```

That bumps the `.toc` version, luaparser-checks the Lua, commits, pushes, cuts a
GitHub release (tag = `.toc` version) and `ghaddons`-deploys into the game
install. It **refuses a dirty tree** — commit your feature work first.

⚠️ **A push does not reach the game.** `ghaddons` installs from the latest GitHub
*release*, so nothing deploys until a release is cut. In-game confirm: `/reload`,
then bare `/cap` — help printing proves the router loaded.

Check the live version with `uv run python -m wowkb.addon list` — never hardcode
it in prose.
