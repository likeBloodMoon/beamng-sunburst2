-- Sunburst2 Variable-Geometry Turbo controller
-- Simulates VGT vane behaviour on top of whatever base turbo the equipped
-- engine part defines: a low/high boost multiplier blended around a
-- transition RPM, first-order spool lag, and a transient overboost peak on
-- throttle tip-in. Publishes everything to electrics for gauges/UI, and
-- makes a best-effort (pcall-guarded) attempt to also push the value into
-- the engine device's own turbocharger sub-table where present.

local M = {}
M.type = "auxiliary"

local engine = nil
local params = {}

local spoolState = 0       -- 0..1, current spool progress
local boostSmoothed = 0
local prevThrottle = 0
local transientTimer = 0

-- Best-effort blow-off valve hiss on lift-off under boost. Stock sample/event
-- names aren't verifiable without a running BeamNG install, so this is
-- pcall-guarded; sunburstVgtBovPulse is published either way for a
-- soundConfig to drive its own sample off of.
local function tryPlayBov()
  electrics.values.sunburstVgtBovPulse = 1
  pcall(function()
    if sounds and sounds.playSoundOnceFollowing then
      local nodeID = (engine and engine.engineNodeID) or 0
      sounds.playSoundOnceFollowing("event:>Vehicle>Turbo>blowoff_high", nodeID, 1)
    end
  end)
end

local function smoothstep(edge0, edge1, x)
  if edge1 == edge0 then return x < edge0 and 0 or 1 end
  local t = math.max(0, math.min(1, (x - edge0) / (edge1 - edge0)))
  return t * t * (3 - 2 * t)
end

local function targetBoostMultiplier(rpm)
  local transition = params.transitionRPM or 3500
  local band = math.max(transition * 0.3, 300)
  local t = smoothstep(transition - band, transition + band, rpm)
  local low = params.lowBoostMultiplier or 1.0
  local high = params.highBoostMultiplier or 1.4
  return low + (high - low) * t
end

local function updateGFX(dt)
  if not engine then
    engine = powertrain.getDevice("mainEngine")
  end

  local rpm = (electrics.values and electrics.values.rpm) or 0
  local throttle = (electrics.values and electrics.values.throttle) or 0

  local target = targetBoostMultiplier(rpm)

  -- spool dynamics: first-order lag toward target, gated by throttle
  local spoolTime = math.max(params.spoolTimeSec or 0.4, 0.05)
  local spoolTarget = throttle > 0.05 and 1 or 0
  local spoolRate = dt / spoolTime
  if spoolTarget > spoolState then
    spoolState = math.min(1, spoolState + spoolRate)
  else
    spoolState = math.max(0, spoolState - spoolRate * 1.5)
  end

  -- transient overboost peak on tip-in
  local throttleDelta = throttle - prevThrottle
  if throttleDelta > 0.25 and rpm > (params.transitionRPM or 3500) * 0.5 then
    transientTimer = params.transientDecaySec or 0.6
  end

  -- blow-off valve hiss on a hard lift while meaningfully spooled/boosted
  electrics.values.sunburstVgtBovPulse = 0
  if throttleDelta < -0.35 and boostSmoothed > 0.3 then
    tryPlayBov()
  end

  prevThrottle = throttle

  local transientMult = 1
  if transientTimer > 0 then
    transientTimer = math.max(0, transientTimer - dt)
    local decay = params.transientDecaySec or 0.6
    local frac = transientTimer / math.max(decay, 0.01)
    transientMult = 1 + ((params.transientPeakMultiplier or 1.1) - 1) * frac
  end

  local boostMult = target * spoolState * transientMult
  boostSmoothed = boostSmoothed + (boostMult - boostSmoothed) * math.min(1, dt * 6)

  local vaneMin = params.vaneMinAngle or 15
  local vaneMax = params.vaneMaxAngle or 55
  local vanePos = vaneMin + (vaneMax - vaneMin) * spoolState

  if electrics.values then
    electrics.values.sunburstTurboBoostMult = boostSmoothed
    electrics.values.sunburstTurboSpool = spoolState
    electrics.values.sunburstVgtVaneAngle = vanePos
  end

  if engine and engine.turbocharger then
    pcall(function()
      if engine.turbocharger.boost ~= nil and engine.turbocharger.baseBoost ~= nil then
        engine.turbocharger.boost = engine.turbocharger.baseBoost * boostSmoothed
      end
    end)
  end
end

local function init(jbeamData)
  params = jbeamData or {}
  params.lowBoostMultiplier = params.lowBoostMultiplier or 1.0
  params.highBoostMultiplier = params.highBoostMultiplier or 1.4
  params.transitionRPM = params.transitionRPM or 3500
  params.spoolTimeSec = params.spoolTimeSec or 0.4
  params.transientPeakMultiplier = params.transientPeakMultiplier or 1.1
  params.transientDecaySec = params.transientDecaySec or 0.6
  params.vaneMinAngle = params.vaneMinAngle or 15
  params.vaneMaxAngle = params.vaneMaxAngle or 55

  engine = powertrain.getDevice("mainEngine")
  if engine and engine.turbocharger and engine.turbocharger.boost ~= nil and engine.turbocharger.baseBoost == nil then
    pcall(function() engine.turbocharger.baseBoost = engine.turbocharger.boost end)
  end

  spoolState = 0
  boostSmoothed = 0
  prevThrottle = 0
  transientTimer = 0
end

local function reset(jbeamData)
  init(jbeamData)
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX

return M
