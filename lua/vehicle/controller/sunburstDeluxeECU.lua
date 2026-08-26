-- Sunburst2 Deluxe Lua ECU
-- Auxiliary vehicle controller: runtime power multiplier and an
-- indestructible-mode toggle that overrides the engine's native damage
-- thresholds. Idle RPM and the rev limiter are handled natively by the
-- combustion engine device via jbeam (idleRPM/revLimiterRPM/revLimiterType/
-- revLimiterCutTime on sunburst2_ecu_deluxe_lua.jbeam) -- BeamNG's stock
-- engine model already does that correctly, so this controller only adds
-- what genuinely needs Lua: a multiplier that has to apply uniformly no
-- matter which engine is equipped, and a live damage-threshold override.

local M = {}
M.type = "auxiliary"
M.relevantDevice = nil

local engine = nil
local baseTorqueCurve = nil
local baseDamageFields = nil
local params = {}

-- native combustion engine damage fields; see documentation.beamng.com
-- "JBeam file sections" -> mainEngine for the authoritative list
local damageFieldNames = {
  "cylinderWallTemperatureDamageThreshold",
  "engineBlockTemperatureDamageThreshold",
  "headGasketDamageThreshold",
  "pistonRingDamageThreshold",
  "connectingRodDamageThreshold",
  "maxTorqueRating",
  "maxOverTorqueDamage",
}

local bigBlockCurvePoints = {
  {rpm = 800, torque = 350},
  {rpm = 1500, torque = 480},
  {rpm = 2500, torque = 590},
  {rpm = 3000, torque = 610},
  {rpm = 4100, torque = 624},
  {rpm = 4800, torque = 600},
  {rpm = 5600, torque = 534},
  {rpm = 6200, torque = 460},
  {rpm = 6500, torque = 380},
}

local function interpolateBigBlock(rpm)
  local pts = bigBlockCurvePoints
  if rpm <= pts[1].rpm then return pts[1].torque end
  if rpm >= pts[#pts].rpm then return pts[#pts].torque end
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    if rpm >= a.rpm and rpm <= b.rpm then
      local t = (rpm - a.rpm) / (b.rpm - a.rpm)
      return a.torque + (b.torque - a.torque) * t
    end
  end
  return pts[#pts].torque
end

local function snapshotEngineState()
  baseTorqueCurve = nil
  if engine and type(engine.torqueCurve) == "table" then
    baseTorqueCurve = {}
    for k, v in pairs(engine.torqueCurve) do
      if type(v) == "number" then
        baseTorqueCurve[k] = v
      end
    end
  end

  baseDamageFields = {}
  if engine then
    for _, name in ipairs(damageFieldNames) do
      if type(engine[name]) == "number" then
        baseDamageFields[name] = engine[name]
      end
    end
  end
end

local function rebuildTorqueCurve()
  if not (engine and baseTorqueCurve and type(engine.torqueCurve) == "table") then return end

  local mult = params.powerMultiplier or 1

  for k, base in pairs(baseTorqueCurve) do
    local value = base * mult

    if params.bigBlockRemap and type(k) == "number" then
      -- blend toward the big-block target shape, scaled by the same tuning multiplier
      value = interpolateBigBlock(k) * mult
    end

    engine.torqueCurve[k] = value
  end
end

local function applyIndestructible()
  if not engine then return end

  if params.indestructible then
    pcall(function()
      engine.cylinderWallTemperatureDamageThreshold = 99999
      engine.engineBlockTemperatureDamageThreshold = 99999
      engine.headGasketDamageThreshold = 99999999
      engine.pistonRingDamageThreshold = 99999999
      engine.connectingRodDamageThreshold = 99999999
      engine.maxTorqueRating = 999999
      engine.maxOverTorqueDamage = 999999
    end)
  elseif baseDamageFields then
    pcall(function()
      for name, value in pairs(baseDamageFields) do
        engine[name] = value
      end
    end)
  end
end

-- best-effort backfire pop near the rev limiter; the actual ignition cut is
-- handled natively by the engine device (revLimiterRPM/Type/CutTime), this
-- is purely a sound cue layered on top
local wasNearLimiter = false
local function updateBackfireCue()
  local limiterRPM = engine and engine.revLimiterRPM
  if not (electrics.values and limiterRPM) then return end
  local rpm = electrics.values.rpm or 0
  local nearLimiter = rpm >= limiterRPM - 60

  electrics.values.sunburstBackfirePulse = 0
  if nearLimiter and not wasNearLimiter then
    electrics.values.sunburstBackfirePulse = 1
    pcall(function()
      if sounds and sounds.playSoundOnceFollowing then
        local nodeID = engine.engineNodeID or 0
        sounds.playSoundOnceFollowing("event:>Vehicle>Backfire>machine_gun_backfire", nodeID, 0.8)
      end
    end)
  end
  wasNearLimiter = nearLimiter
end

local function updateGFX(dt)
  if not engine then
    engine = powertrain.getDevice("mainEngine")
    if engine then
      snapshotEngineState()
      rebuildTorqueCurve()
      applyIndestructible()
    else
      return
    end
  end

  updateBackfireCue()

  if electrics.values then
    electrics.values.sunburstEcuIndestructible = params.indestructible and 1 or 0
  end
end

local function setPowerMultiplier(mult)
  params.powerMultiplier = math.max(0.2, math.min(5, mult or 1))
  rebuildTorqueCurve()
end

local function setIndestructible(state)
  params.indestructible = state and true or false
  applyIndestructible()
end

local function setBigBlockRemap(state)
  params.bigBlockRemap = state and true or false
  rebuildTorqueCurve()
end

local function init(jbeamData)
  params = jbeamData or {}
  params.powerMultiplier = params.powerMultiplier or 1
  params.indestructible = params.indestructible or false
  params.bigBlockRemap = params.bigBlockRemap or false

  engine = powertrain.getDevice("mainEngine")
  snapshotEngineState()

  wasNearLimiter = false

  rebuildTorqueCurve()
  applyIndestructible()
end

local function reset(jbeamData)
  init(jbeamData)
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX

M.setPowerMultiplier = setPowerMultiplier
M.setIndestructible = setIndestructible
M.setBigBlockRemap = setBigBlockRemap

return M
