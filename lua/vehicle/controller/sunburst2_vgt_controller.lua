local M = {}

local engine
local baseTorqueCurve
local config = {
  enabled = true,
  lowBoost = 1.25,
  highBoost = 1.0,
  transitionRPM = 3000,
  spoolTime = 0.25,
  exposeToGauges = true,
  soundEvent = "",
  visualNode = ""
}

local state = {
  currentBoost = 1.0,
  vanePos = 0.0
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
      newCurve[i] = v
    end
  end
  return newCurve
end

local function applyVGTMultiplier(mult)
  if not engine or not baseTorqueCurve or not mult then return end

  local newCurve = {}
  for i, point in ipairs(baseTorqueCurve) do
    if type(point) == "table" and #point >= 2 then
      newCurve[i] = { point[1], point[2] * mult }
    else
      newCurve[i] = (tonumber(point) or 0) * mult
    end
  end

  engine.torqueCurve = newCurve
end

local function init(jbeamData)
  engine = powertrain.getDevice("mainEngine") or powertrain.getDevice("engine")
  if not engine then
    log("E", "sunburst2_vgt_controller", "No engine device found")
    return
  end

  -- copy base torque definition
  if type(engine.torque) == "table" then
    baseTorqueCurve = copyCurve(engine.torque)
  elseif type(engine.torqueCurve) == "table" then
    baseTorqueCurve = copyCurve(engine.torqueCurve)
  end

  if not baseTorqueCurve then
    log("E", "sunburst2_vgt_controller", "No usable torque curve on engine; VGT will be disabled")
    config.enabled = false
    return
  end

  if jbeamData then
    config.enabled = jbeamData.enabled == nil and config.enabled or jbeamData.enabled
    config.lowBoost = tonumber(jbeamData.lowBoost) or config.lowBoost
    config.highBoost = tonumber(jbeamData.highBoost) or config.highBoost
    config.transitionRPM = tonumber(jbeamData.transitionRPM) or config.transitionRPM
    config.spoolTime = tonumber(jbeamData.spoolTime) or config.spoolTime
    config.exposeToGauges = jbeamData.exposeToGauges == nil and config.exposeToGauges or jbeamData.exposeToGauges
    config.soundEvent = jbeamData.soundEvent or config.soundEvent
    config.visualNode = jbeamData.visualNode or config.visualNode
  end

  -- initialize state
  state.currentBoost = 1.0
  state.vanePos = 0.0
  applyVGTMultiplier(state.currentBoost)
end

local function reset(jbeamData)
  if jbeamData then
    config.enabled = jbeamData.enabled == nil and config.enabled or jbeamData.enabled
    config.lowBoost = tonumber(jbeamData.lowBoost) or config.lowBoost
    config.highBoost = tonumber(jbeamData.highBoost) or config.highBoost
    config.transitionRPM = tonumber(jbeamData.transitionRPM) or config.transitionRPM
    config.spoolTime = tonumber(jbeamData.spoolTime) or config.spoolTime
    config.exposeToGauges = jbeamData.exposeToGauges == nil and config.exposeToGauges or jbeamData.exposeToGauges
    config.soundEvent = jbeamData.soundEvent or config.soundEvent
    config.visualNode = jbeamData.visualNode or config.visualNode
  end

  if not engine then
    engine = powertrain.getDevice("mainEngine") or powertrain.getDevice("engine")
  end

  if engine and not baseTorqueCurve then
    if type(engine.torque) == "table" then
      baseTorqueCurve = copyCurve(engine.torque)
    elseif type(engine.torqueCurve) == "table" then
      baseTorqueCurve = copyCurve(engine.torqueCurve)
    end
  end
  -- re-init state
  state.currentBoost = 1.0
  state.vanePos = 0.0
  applyVGTMultiplier(state.currentBoost)
end

local function safeGetEngineRPM()
  local ok, val = pcall(function()
    if type(engine.getRPM) == "function" then return engine.getRPM() end
    return engine.rpm or engine.RPM or 0
  end)
  return ok and (val or 0) or 0
end

local function safeGetThrottle()
  local ok, val = pcall(function()
    if type(engine.getThrottle) == "function" then return engine.getThrottle() end
    if type(engine.getThrottleInput) == "function" then return engine.getThrottleInput() end
    return engine.throttle or engine.Throttle or 1.0
  end)
  return ok and (val or 1.0) or 1.0
end

local function updateGFX(dt)
  if not engine or not baseTorqueCurve or not config.enabled then return end

  local rpm = safeGetEngineRPM()
  local thr = clamp(safeGetThrottle(), 0, 1)

  local low = tonumber(config.lowBoost) or 1.0
  local high = tonumber(config.highBoost) or 1.0
  local trans = tonumber(config.transitionRPM) or 3000
  local tau = tonumber(config.spoolTime) or 0.25
  local peak = tonumber(config.peakBoost) or 1.0
  local peakRPM = tonumber(config.peakRPM) or 2000
  local peakWidth = tonumber(config.peakWidth) or 800

  -- rpm-based interpolation around transition (use +/- 600rpm smoothing)
  local spread = math.max(200, trans * 0.2)
  local t = clamp((rpm - (trans - spread)) / (2 * spread), 0, 1)

  -- base target multiplier between low and high
  local targetBase = low * (1 - t) + high * t

  -- modulate by throttle: less effective boost when throttle is low
  local target = 1 + (targetBase - 1) * thr

  -- transient bell/peak around peakRPM (Gaussian), applied multiplicatively
  if peak and peak > 1.0 then
    local d = rpm - peakRPM
    local bell = math.exp(- (d * d) / (2 * (peakWidth * peakWidth)))
    local bellMult = 1 + (peak - 1) * bell * thr
    target = target * bellMult
  end

  -- first-order lag towards target
  local alpha = dt / (tau + dt)
  state.currentBoost = state.currentBoost + (target - state.currentBoost) * alpha

  -- vane position (0..1) relative to low->high
  if low ~= high then
    state.vanePos = clamp((state.currentBoost - high) / (low - high), 0, 1)
  else
    state.vanePos = 0
  end

  -- apply multiplier to engine torque curve
  applyVGTMultiplier(state.currentBoost)

  -- expose readouts for visuals/sound/gauges
  engine.vgt_currentBoost = state.currentBoost
  engine.vgt_vanePos = state.vanePos
  engine.vgt_targetBoost = target

  -- normalized sound level (0..1)
  local soundNorm = 0
  if low > 1 then soundNorm = clamp((state.currentBoost - 1) / (low - 1), 0, 1) end
  engine.vgt_soundLevel = soundNorm

  -- models/sound systems can read these fields (`vgt_currentBoost`, `vgt_vanePos`, `vgt_soundLevel`)
  -- if `exposeToGauges` is enabled, keep value handy for gauge systems to read
  engine.vgt_exposedToGauges = config.exposeToGauges and state.currentBoost or nil
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX

return M
