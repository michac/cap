# Combat Assist Plus — addon repo

This is the standalone `michac/cap` repository checked out inside the WoW workspace at
`projects/combat-assist/addon/`. It is the source of truth; the installed copy under the WoW
game directory is a deployment target.

The parent workspace gitignores this repository. A parent-repo commit or push does not include
these files.

## Product and status

Product behavior lives in the parent workspace at `projects/combat-assist/specs/spec.md`.
Implementation status and the current work list live only in
`projects/combat-assist/specs/backlog.md` → `## Status`. Do not add a second status summary
here or infer intended behavior from the current module layout.

Read the spec—especially §1—before changing behavior. During the simplification migration,
the current source is evidence of the previous design, not authority for preserving it.

## Development rules

Read the workspace `wow-developer` skill and
`.claude/skills/wow-developer/references/house-rules.md` before editing Lua, XML or the `.toc`.

- Commands come from the `ns.Commands` schema table. Maximum depth is
  `/cap <verb> [<arg>]`; do not use substring dispatch.
- Every capture uses `ns.Capture.Open(...)` and writes
  `CombatAssistPlusDB.captures.<stream>`. The only reader is
  `wowkb.capture cap <stream>`.
- Keep the shared capture wire format exact. SavedVariables flush on `/reload` or logout.
- Pure tests protect engine and platform contracts. Gameplay opinions and visual tuning are
  characterized provisionally and decided through play.
- Facts learned about the client go to `knowledge/addon-dev/`; they do not remain only in a
  comment or project document.

## Release workflow

The mechanical recipe belongs to `wowkb.addon`:

```bash
cd ~/code/fun/wow/tools
uv run python -m wowkb.addon release cap [--patch|--minor|--major]
```

It checks Lua and tests, bumps the `.toc`, commits, pushes, creates a GitHub release and
deploys that release. It refuses a dirty addon worktree.

Releasing is ask-first. A push alone does not deploy anything. Read the live version with
`wowkb.addon list`; never hardcode it here.
