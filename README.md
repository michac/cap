# Combat Assist Plus (`cap`)

A World of Warcraft (Retail / Midnight 12.0) combat-assistance addon.

> ⚠️ **Scaffold only.** This is the initial skeleton — a `.toc`, a namespace,
> SavedVariables and the slash-command router. It does nothing in combat yet.

## Install

Via [`ghaddons`](https://github.com/michac) (the GitHub-driven addon manager),
or manually: drop the `CombatAssistPlus/` folder into
`World of Warcraft/_retail_/Interface/AddOns/` and `/reload`.

## Usage

| Command | What it does |
| --- | --- |
| `/cap` · `/cap status` | Version, class + spec, enabled state |
| `/cap toggle` | Turn the assist on or off |
| `/cap help` | List the commands |

## Layout

```
CombatAssistPlus/
  CombatAssistPlus.toc
  Core.lua              namespace, SavedVariables, command schema + router
```

Commands come from the `ns.Commands` schema table — add a row there and help
and dispatch both pick it up. No substring matching in the router.

## License

MIT — see `LICENSE`.
