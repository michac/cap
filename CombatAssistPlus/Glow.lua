-- Glow.lua — dim Blizzard's proc glow on the CDM item frames, so cap's own emphasis is not
-- competing with a large gold overlay that looks like one (spec.md §3.2, §3.1). The glow is
-- the shared spell-activation overlay, redrawn per item by `RefreshOverlayGlow`
-- (cooldown-manager.md §6); why the alert FRAME, why per-instance, why a dim not a hide is
-- read off CDMProbe's `HudProcGlow.lua` and unmeasured — `backlog.md` owns the drain.
local ADDON, ns = ...

local DIM = 0.5   -- a dial for an eyeball to settle, not a measured value

ns.Glow = ns.Glow or {}
local Glow = ns.Glow

-- Hook-once-per-frame-object-ever, for the reason `Sense.lua`'s own `hooked` table states.
local hooked = setmetatable({}, { __mode = "k" })
local live = false
local count = 0

local function apply(frame, value)
  local a = frame.SpellActivationAlert
  if type(a) == "table" and type(a.SetAlpha) == "function" then pcall(a.SetAlpha, a, value) end
end

--- The immediate pass is for a glow already lit, in case nothing calls `RefreshOverlayGlow` on that frame again soon.
function Glow.Arm(frame)
  if not frame or hooked[frame] or type(frame.RefreshOverlayGlow) ~= "function" then return end
  hooked[frame] = true
  count = count + 1
  hooksecurefunc(frame, "RefreshOverlayGlow", function(self)
    if live then apply(self, DIM) end
  end)
  if live then apply(frame, DIM) end
end

--- Full alpha back on every frame ever hooked — cap must not degrade Blizzard's UI while
--- putting nothing in its place. The early-out keeps it inert: this rides a 10 Hz tick.
function Glow.Restore()
  if not live then return end
  live = false
  for frame in pairs(hooked) do apply(frame, 1) end
end

local function light()
  if live then return end
  live = true
  for frame in pairs(hooked) do apply(frame, DIM) end
end

--- `n/live` or `n/off` — frames hooked EVER, and whether the dim is armed. `SetAlpha` hands nothing back, so never that a pixel changed.
function Glow.Status()
  return count .. (live and "/live" or "/off")
end

-- Listens before Overlay does, which is what the `.toc` order buys: the `draw` line Overlay
-- writes on this pass then reports the liveness of the same pass.
ns.Sense.OnVerdicts(function(out, bound)
  if out and bound then light() else Glow.Restore() end
end)
