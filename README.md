# Combat Assist Plus (`cap`)

A World of Warcraft (Retail / Midnight 12.1) combat-assistance overlay that extends
Blizzard's Cooldown Manager.

cap makes the Cooldown Manager tell you **more** without telling you what to press. It
skins the rows the client already draws: a scan edge on the rows still in the running,
negative badges on the rows ruled out, hatching over the ones eliminated, and sealed
displays the *client* evaluates for facts cap is not allowed to read.

A spec without a catalog gets nothing, by design. The catalogs that ship today are
Demonology, Destruction, Havoc, Protection and Retribution.

## Install

Via [`ghaddons`](https://github.com/michac) (the GitHub-driven addon manager),
or manually: drop the `CombatAssistPlus/` folder into
`World of Warcraft/_retail_/Interface/AddOns/` and `/reload`.

## Usage

| Command | What it does |
| --- | --- |
| `/cap` · `/cap status` | Is the assist working, and if not, why |
| `/cap toggle` | Turn the assist on or off |
| `/cap aoe [on\|off]` | Switch the target mode cap grades against |
| `/cap anchor [on\|off\|retry\|rows]` | Draw the Cooldown Manager rows in the catalog's priority order |
| `/cap move [reset]` | Unlock the cooldown panel to drag it, or reset its position |
| `/cap style` | Open the render-shelf gallery in its own window |
| `/cap band [x y [size]] \| off` | Nudge the sealed band's hatch while looking at it (flight instrument, not saved) |
| `/cap help` | List the commands |

Commands come from the `ns.Commands` schema table — register a row with
`ns.RegisterCommand` and help and dispatch both pick it up. No substring matching in the
router.

## Layout

Load order is the `.toc`; each file is one seam.

```
CombatAssistPlus/
  Core.lua          namespace, SavedVariables, command schema + router
  Capture.lua       the shared capture contract (SavedVariables streams)
  Bind.lua          CDM rows ⇄ catalog entries
  Talents.lua       trait-config reads
  Binds.lua         keybind text for the rows
  Catalog.lua       the catalog schema and its validator
  Catalogs/*.lua    the per-spec rosters (data only)
  Log.lua           the decision log
  Signal.lua        unknown-safe predicate evaluation
  Track.lua         per-row state tracking
  Style.lua         GENERATED from specs/render-shelf.md — every number cap draws with
  Lab.lua           GENERATED — the /cap style gallery's lab entries only
  Treatment.lua     verdict → treatment
  Paint.lua         the drawing primitives
  Channel.lua       sealed displays: the client evaluates, cap never learns
  Sense.lua         the roster read
  Glow.lua          Blizzard's proc glow, dimmed
  Bars.lua          the optional per-row bar (no catalog declares one yet)
  Overlay.lua       the per-frame paint loop
  Anchor.lua        re-anchoring the CDM rows into priority order
  Frame.lua         the cooldown panel frame
  Window.lua        the gallery window chrome
  StylePanel.lua    the /cap style gallery
  Mode.lua          the AoE mode toggle
  Status.lua        /cap status
```

The definition of what cap shows and why lives outside this repo, in the parent
workspace: `specs/spec.md` (approved behavior), `specs/render-shelf.md` (every visual
opinion), `specs/<spec>/catalog.md` (the per-spec roster). `Style.lua` and `Lab.lua` are
**generated** from the shelf — do not hand-edit them.

## License

MIT — see `LICENSE`.
