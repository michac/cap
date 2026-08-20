-- .luacheckrc — static analysis for Combat Assist Plus.
--
-- The rung above the release flow's luaparser SYNTAX gate: luacheck catches
-- undefined globals, dead locals, shadowing and typos that parse fine but are
-- bugs.  `wowkb.addon release cap` runs it because this file exists — its absence
-- is what silently switches the gate off — and it aborts the cut on a hit.  By
-- hand, from this repo root:
--
--     luacheck CombatAssistPlus/
--
-- (needs `luarocks install --local luacheck` + ~/.luarocks/bin on PATH.)
--
-- DOCTRINE: curate this config, never inline-suppress.  A real catch — undefined
-- global, dead local, shadow — gets FIXED; a WoW API name the addon legitimately
-- calls goes in the `read_globals` std below.  The signal is worth exactly what
-- this list's honesty is worth: a name nothing calls silences the undefined-global
-- warning that would have caught the day someone typo'd a real one.  So the list
-- is grouped by the file that calls each name, which is a claim a reader can check
-- with one grep.

std = "lua51+wow"

-- The client runs Lua 5.1, so start there and layer the Blizzard API on top as a
-- named std rather than a bare read_globals — a std composes, so a later per-path
-- override can add to it without restating the whole surface.
stds.wow = {
  read_globals = {
    -- Frames and combat state — Core.lua, Frame.lua, Bind.lua.
    "CreateFrame", "UIParent", "InCombatLockdown",
    -- Secret Values: the predicates every game read is fenced on — Frame.lua,
    -- Bind.lua, Capture.lua.
    "issecretvalue", "issecrettable",
    -- Clocks.  `date` is os.date hoisted to a global by the client, so the lua51
    -- std does not carry it; Capture.lua stamps every session header with it.
    "GetTime", "date",
    -- The addon's own metadata — Core.lua reads Version into ns.version, which is
    -- what lets a capture on disk name the build that wrote it.
    "C_AddOns",
    -- The Cooldown Manager and the CVar that gates it — Bind.lua.
    "C_CooldownViewer", "C_CVar",
    -- The keybind hint — Binds.lua.  `C_ActionBar` answers spell → action slots and the
    -- bonus-bar page; `GetBindingKey` / `GetBindingText` are LEGACY GLOBALS that appear in no
    -- generated API doc (only `C_KeyBindings.*` is documented), which is why they are declared
    -- by hand here.  Chain: knowledge/addon-dev/cdm-rider-patterns.md §11.
    "C_ActionBar", "GetBindingKey", "GetBindingText",
    -- Deferred work — Bind.lua coalesces its re-resolve onto a timer.
    "C_Timer",
    -- Enum.CooldownViewerCategory — Bind.lua's viewer table; and
    -- Enum.FontStringScaleAnimationMode — Overlay.lua's count marker.
    "Enum",
    -- Player identity: the spec and hero tree a capture line is labelled with —
    -- Log.lua, which reaches for the C_SpecializationInfo pair first and falls back
    -- to the bare globals, so both spellings are live.
    "C_SpecializationInfo", "GetSpecialization", "GetSpecializationInfo",
    "C_ClassTalents", "C_Traits",
    -- The gate reads — Sense.lua.  `C_Spell` answers affordability and the
    -- out-of-combat cooldown baseline, `C_SpellActivationOverlay` the proc, and
    -- `UnitPower` the secondary resource; which of them is readable when is
    -- knowledge/addon-dev/security-taint-and-restricted-data.md §4.8, §4.12.
    "C_Spell", "C_SpellActivationOverlay", "UnitPower", "UnitPowerMax",
    -- The out-of-combat AURA seed — Sense.lua.  Aura secrecy is COMBAT-GATED, so the exact
    -- read is legal exactly while it is not needed; `UnitExists` guards the unit before
    -- `C_UnitAuras` (declared below) is asked about it.
    "UnitExists",
    -- The alert choke point cap latches readiness off — Sense.lua.  It cannot be
    -- removed once installed, which is why the hook table is weak-keyed.
    "hooksecurefunc",
    -- The two sealed comparisons — Channel.lua.  `C_UnitAuras` is the stack quantiser
    -- and `C_CurveUtil` builds the Step curve a duration object evaluates; the enum
    -- members they need (`Enum.LuaCurveType`, `Enum.DurationTimeModifier`) ride the
    -- `Enum` global already declared above.  Mechanisms:
    -- knowledge/addon-dev/security-taint-and-restricted-data.md §4.8.
    "C_UnitAuras", "C_CurveUtil",
    -- The graded cue — Channel.lua.  `UnitPowerPercent` is the one call that evaluates an
    -- authored curve against a secret resource in C and hands back only the mapped result;
    -- `UnitPowerMax` (declared above) supplies the max the break point is derived from.
    "UnitPowerPercent",
    -- The §3.4 bars — Bars.lua.  `C_StringUtil.CreateSecondsFormatter` is the formatter a
    -- duration object formats its own remaining time through; the duration itself comes
    -- from `C_Spell` above and the enum members ride the `Enum` global.  Mechanism:
    -- knowledge/addon-dev/security-taint-and-restricted-data.md §4.8.1 finding 2.
    "C_StringUtil",
    -- Blizzard's tab helpers — Window.lua.  `PanelTabButtonTemplate` carries
    -- `parentArray="Tabs"`, so these read the window's own `Tabs` array; the legacy
    -- `$parentTabN` path they fall back to resolves in Blizzard's environment table and
    -- never in ours.  Confirmed present in the 12.1 client source at
    -- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua:359, :460.
    "PanelTemplates_SetTab", "PanelTemplates_SetNumTabs",
    -- The colour object `SetGradient` takes since it stopped accepting bare tables — the
    -- `/cap style` gallery's Part 7 title-bar candidates (StylePanel.lua).
    "CreateColor",
    -- Anchor.lua.  The callback registry the Cooldown Manager's settings pane raises its
    -- data change on; the viewer itself is reached through `_G`, so no viewer name is
    -- declared here.
    "EventRegistry",
    -- Anchor.lua's contention dialog.  The generic-confirmation helpers take the whole
    -- prompt as data, so no StaticPopupDialogs entry is registered under our own key.
    -- Present in the 12.1 client source at Blizzard_StaticPopup/StaticPopup.lua:232, :236.
    "StaticPopup_ShowCustomGenericConfirmation", "StaticPopup_IsCustomGenericConfirmationShown",
  },
  -- The addon's true global writes.  Every module binds its namespace as a local
  -- (`local ADDON, ns = ...`), so there is no shared-namespace global to declare —
  -- the slash registration and the SavedVariable are the whole list.
  globals = {
    "SLASH_COMBATASSISTPLUS1",
    "SlashCmdList",
    "CombatAssistPlusDB",       -- SavedVariable
    "SLASH_CAPANCHOR1",         -- probes/AnchorOrder.lua's own slash command
  },
}

-- unused_args — the client's handler idiom is `function(self, event, ...)`, and a
-- handler that wants only the third argument still has to name the first two.
-- Warning on those trains the reader to skip the whole warning class.
unused_args = false

-- max_line_length — the viewer and command-schema tables read as one declaration
-- per line; wrapping them into a column costs more than the width does.
max_line_length = false

-- Every module opens `local ADDON, ns = ...`, WoW's `(addonName, addonTable)`
-- vararg.  Most use only `ns`, so `ADDON` reads as a dead local — but naming the
-- first vararg is what makes the second one legible, and Core.lua does use it.
-- Ignored BY NAME, so a dead local under any other name still warns.
ignore = { "211/ADDON" }

-- The suite runs under busted, whose describe/it/assert are globals no addon file
-- has.  Declared here rather than left to luacheck's `*_spec.lua` filename heuristic:
-- this config gates a release, and a gate should not rest on a tool's default it
-- never asked for.
files["CombatAssistPlus/tests/"] = { std = "+busted" }
