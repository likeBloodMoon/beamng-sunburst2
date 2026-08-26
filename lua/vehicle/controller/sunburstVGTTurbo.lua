-- Sunburst2 VGT Turbo controller
-- The actual boost/spool behaviour for each stage is handled natively by
-- BeamNG's own turbocharger model (inertia, frictionCoef, pressurePSI and
-- engineDef curves set per-stage in the jbeam turbocharger block) -- that
-- model already simulates spool lag correctly via turbine inertia, so this
-- controller doesn't reimplement it. What it adds on top: a best-effort
-- blow-off-valve sound cue on a hard lift-off under boost, published via
-- electrics either way so a soundConfig can hook in directly.

local M = {}
M.type = "auxiliary"

local engine = nil
local prevThrottle = 0

local function tryPlayBov()
  electrics.values.sunburstVgtBovPulse = 1
  pcall(function()
    if sounds and sounds.playSoundOnceFollowing then
      local nodeID = (engine and engine.engineNodeID) or 0
      sounds.playSoundOnceFollowing("event:>Vehicle>Forced_Induction>Turbo_01>turbo_bov", nodeID, 1)
    end
  end)
end

local function updateGFX(dt)
  if not engine then
    engine = powertrain.getDevice("mainEngine")
  end

  local throttle = (electrics.values and electrics.values.throttle) or 0
  local boost = (electrics.values and electrics.values.boost) or 0
  local throttleDelta = throttle - prevThrottle

  electrics.values.sunburstVgtBovPulse = 0
  if throttleDelta < -0.35 and boost > 3 then
    tryPlayBov()
  end

  prevThrottle = throttle
end

local function init(jbeamData)
  engine = powertrain.getDevice("mainEngine")
  prevThrottle = 0
end

local function reset(jbeamData)
  init(jbeamData)
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX

return M
