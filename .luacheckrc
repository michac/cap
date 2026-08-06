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
    -- Deferred work — Bind.lua coalesces its re-resolve onto a timer.
    "C_Timer",
    -- Enum.CooldownViewerCategory — Bind.lua's viewer table.
    "Enum",
    -- Player identity: the spec and hero tree a capture line is labelled with —
    -- Log.lua, which reaches for the C_SpecializationInfo pair first and falls back
    -- to the bare globals, so both spellings are live.
    "C_SpecializationInfo", "GetSpecialization", "GetSpecializationInfo",
    "C_ClassTalents", "C_Traits",
  },
  -- The addon's true global writes.  Every module binds its namespace as a local
  -- (`local ADDON, ns = ...`), so there is no shared-namespace global to declare —
  -- the slash registration and the SavedVariable are the whole list.
  globals = {
    "SLASH_COMBATASSISTPLUS1",
    "SlashCmdList",
    "CombatAssistPlusDB",       -- SavedVariable
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
