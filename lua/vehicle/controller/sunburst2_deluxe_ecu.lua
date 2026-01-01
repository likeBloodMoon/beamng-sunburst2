local M = {}

local engine
local baseTorqueCurve
local config = {
  powerCoef = 1,
  indestructible = false,
  engineBrakeTorque = 60,
  cylinderWallDamageThreshold = 1000000000,
  headGasketDamageThreshold = 1000000000,
  pistonRingDamageThreshold = 1000000000,
  connectingRodDamageThreshold = 1000000000,
  maxTorqueRating = 1000000000,
  maxOverTorqueDamage = 1000000000,
  revLimiterRPM = 7000,
  revLimiterCutTime = 0.12,
  idleRPM = 950,
  highShiftUp = 6800,
  highShiftDown = 4200
}

local function clamp(x, minV, maxV)
  if minV and x < minV then return minV end
  if maxV and x > maxV then return maxV end
  return x
end

local function copyCurve(curve)
  if type(curve) ~= "table" then return nil end

  local newCurve = {}
  for i, v in ipairs(curve) do
    if type(v) == "table" then
      newCurve[i] = { v[1], v[2] }
    else
      newCurve[i] = v -- v is just a number (torque at that RPM index)
    end
  end
  return newCurve
end

local function applyPowerCoef()
  if not engine or not baseTorqueCurve then return end

  local scale = tonumber(config.powerCoef) or 1
  scale = clamp(scale, 0.1, 10)

  local newCurve = {}
  for i, v in ipairs(baseTorqueCurve) do
    if type(v) == "table" and #v >= 2 then
      newCurve[i] = { v[1], v[2] * scale }
    else
      newCurve[i] = (tonumber(v) or 0) * scale
    end
  end

  engine.torqueCurve = newCurve
end

local function applyEngineConfig()
  if not engine then return end

  -- Apply engine brake torque
  engine.engineBrakeTorque = tonumber(config.engineBrakeTorque) or 60

  -- Apply damage thresholds (indestructible mode sets them very high)
  local damageThreshold = config.indestructible and 1000000000 or tonumber(config.cylinderWallDamageThreshold) or 1000000000
  engine.cylinderWallTemperatureDamageThreshold = damageThreshold

  damageThreshold = config.indestructible and 1000000000 or tonumber(config.headGasketDamageThreshold) or 1000000000
  engine.headGasketDamageThreshold = damageThreshold

  damageThreshold = config.indestructible and 1000000000 or tonumber(config.pistonRingDamageThreshold) or 1000000000
  engine.pistonRingDamageThreshold = damageThreshold

  damageThreshold = config.indestructible and 1000000000 or tonumber(config.connectingRodDamageThreshold) or 1000000000
  engine.connectingRodDamageThreshold = damageThreshold

  damageThreshold = config.indestructible and 1000000000 or tonumber(config.maxTorqueRating) or 1000000000
  engine.maxTorqueRating = damageThreshold

  damageThreshold = config.indestructible and 1000000000 or tonumber(config.maxOverTorqueDamage) or 1000000000
  engine.maxOverTorqueDamage = damageThreshold

  -- Rev limiter and idle settings
  engine.hasRevLimiter = true
  engine.revLimiterRPM = tonumber(config.revLimiterRPM) or engine.revLimiterRPM
  engine.revLimiterCutTime = tonumber(config.revLimiterCutTime) or engine.revLimiterCutTime
  engine.idleRPM = tonumber(config.idleRPM) or engine.idleRPM

  -- Automatic shift hints (used by some gearboxes)
  engine.highShiftUp = tonumber(config.highShiftUp) or engine.highShiftUp
  engine.highShiftDown = tonumber(config.highShiftDown) or engine.highShiftDown
end

local function init(jbeamData)
  engine = powertrain.getDevice("mainEngine") or powertrain.getDevice("engine")
  if not engine then
    log("E", "sunburst2_deluxe_ecu", "No engine device found")
    return
  end

  if type(engine.torqueCurve) ~= "table" then
    log("E", "sunburst2_deluxe_ecu", "engine.torqueCurve is not a table (" .. tostring(type(engine.torqueCurve)) .. ")")
    return
  end

  baseTorqueCurve = copyCurve(engine.torqueCurve)

  -- Load configuration from jbeamData
  reset(jbeamData)

end

local function reset(jbeamData)
  if jbeamData then
    config.powerCoef = tonumber(jbeamData.powerCoef) or config.powerCoef or 1
    config.indestructible = jbeamData.indestructible or config.indestructible
    config.engineBrakeTorque = tonumber(jbeamData.engineBrakeTorque) or config.engineBrakeTorque
    config.revLimiterRPM = tonumber(jbeamData.maxRPM or jbeamData.revLimiterRPM) or config.revLimiterRPM
    config.revLimiterCutTime = tonumber(jbeamData.revLimiterCutTime or jbeamData.cutTime) or config.revLimiterCutTime
    config.idleRPM = tonumber(jbeamData.idleRPM) or config.idleRPM
    config.highShiftUp = tonumber(jbeamData.highShiftUp) or config.highShiftUp
    config.highShiftDown = tonumber(jbeamData.highShiftDown) or config.highShiftDown
    config.headGasketDamageThreshold = tonumber(jbeamData.headGasketDamageThreshold) or config.headGasketDamageThreshold
    config.pistonRingDamageThreshold = tonumber(jbeamData.pistonRingDamageThreshold) or config.pistonRingDamageThreshold
    config.connectingRodDamageThreshold = tonumber(jbeamData.connectingRodDamageThreshold) or config.connectingRodDamageThreshold
    config.maxTorqueRating = tonumber(jbeamData.maxTorqueRating) or config.maxTorqueRating
    config.maxOverTorqueDamage = tonumber(jbeamData.maxOverTorqueDamage) or config.maxOverTorqueDamage
  end

  if not engine then
    engine = powertrain.getDevice("mainEngine") or powertrain.getDevice("engine")
  end

  if engine and not baseTorqueCurve and type(engine.torqueCurve) == "table" then
    baseTorqueCurve = copyCurve(engine.torqueCurve)
  end

  applyPowerCoef()
  applyEngineConfig()
end

local function updateGFX(dt)
  -- nothing needed each frame; we only change curve on init/reset
end

M.init      = init
M.reset     = reset
M.updateGFX = updateGFX

return M
