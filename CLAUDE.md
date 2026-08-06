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

Scaffold. A `.toc`, a namespace, SavedVariables and the schema-driven slash
router (`/cap`), and nothing else — no combat behaviour, no frames, no events
beyond `ADDON_LOADED`.

**What it's supposed to do lives outside this repo**, on the workspace side at
`projects/combat-assist/specs/` — `spec.md` (the product definition),
`backlog.md` (work items), `notes.md` (session log + decisions). That project
root's `CLAUDE.md` describes how the three fit together. Read `spec.md` before
building anything here; as of now it is deliberately undefined.

## House rules

This addon follows the workspace's addon house rules — read
`.claude/skills/wow-developer/references/house-rules.md` before writing code.
The two that bite first in a young addon:

- **Commands come from the `ns.Commands` schema table** (`Core.lua`), never a
  hand-rolled parser. Max depth `/cap <verb> [<arg>]`. **No substring dispatch.**
- **One capture path.** If this addon ever needs to get data out to the tools, it
  writes `CombatAssistPlusDB.captures.<stream>` via `ns.Capture.Open(...)` and is
  read with `wowkb.capture cap <stream>` — nothing else. The contract is
  `.claude/skills/wow-developer/references/capture-and-dump-standard.md`.

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
then `/cap status`.

Check the live version with `uv run python -m wowkb.addon list` — never hardcode
it in prose.
