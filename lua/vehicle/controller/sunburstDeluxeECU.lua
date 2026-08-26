-- Sunburst2 Deluxe Lua ECU
-- Auxiliary vehicle controller: power multiplier, custom idle/rev-limiter,
-- soft-damage simulation with toggleable "indestructible" mode, and an
-- optional big-block torque-curve remap.
--
-- All reads from the engine device are defensive (existence-checked / pcall
-- guarded) because private field names on the combustion engine device can
-- change between game versions -- if a hook isn't present on the running
-- version, that one integration is skipped instead of erroring the whole
-- controller.

local M = {}
M.type = "auxiliary"
M.relevantDevice = nil

local engine = nil
local baseTorqueCurve = nil
local params = {}

local damage = {
  cylinderWall = 0,
  headGasket = 0,
  pistonRings = 0,
  rods = 0,
}

local revLimiterCutTimer = 0
local damagePenalty = 1

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

local function snapshotTorqueCurve()
  baseTorqueCurve = nil
  if engine and type(engine.torqueCurve) == "table" then
    baseTorqueCurve = {}
    for k, v in pairs(engine.torqueCurve) do
      if type(v) == "number" then
        baseTorqueCurve[k] = v
      end
    end
  end
end

local function rebuildTorqueCurve()
  if not (engine and baseTorqueCurve and type(engine.torqueCurve) == "table") then return end

  local mult = (params.powerMultiplier or 1) * damagePenalty
  local limitNm = params.torqueLimitNm

  for k, base in pairs(baseTorqueCurve) do
    local value = base * mult

    if params.bigBlockRemap and type(k) == "number" then
      -- blend toward the big-block target shape, scaled by the same tuning multiplier
      value = interpolateBigBlock(k) * mult
    end

    if limitNm and limitNm > 0 and value > limitNm then
      value = limitNm
    end

    engine.torqueCurve[k] = value
  end
end

local function applyIdleRPM()
  if not engine then return end
  local idle = params.idleRPM
  if not idle or idle <= 0 then return end
  if engine.idleRPM ~= nil then
    engine.idleRPM = idle
  end
  if engine.idleAV ~= nil and engine.rpmToAV ~= nil then
    engine.idleAV = idle * engine.rpmToAV
  end
end

local function applyRevLimiter(dt, rpm)
  if not (engine and params.revLimiterRPM) then return end

  if revLimiterCutTimer > 0 then
    revLimiterCutTimer = revLimiterCutTimer - dt
    if engine.ignitionCoef ~= nil then
      engine.ignitionCoef = 0
    end
    return
  end

  if engine.ignitionCoef ~= nil then
    engine.ignitionCoef = 1
  end

  if rpm >= params.revLimiterRPM then
    revLimiterCutTimer = (params.revLimiterCutTimeMs or 60) / 1000
  end
end

local function updateDamage(dt, rpm, load, boost)
  if params.indestructible then
    damage.cylinderWall = 0
    damage.headGasket = 0
    damage.pistonRings = 0
    damage.rods = 0
    damagePenalty = 1
    electrics.values.sunburstEcuDamage = 0
    return
  end

  local th = params.damageThresholds or {}

  -- Cylinder wall stress: sustained high load
  local cylTh = th.cylinderWallLoad or 1.0
  if load > cylTh then
    damage.cylinderWall = damage.cylinderWall + (load - cylTh) * dt * 4
  end

  -- Head gasket stress: boost pressure above threshold
  local hgTh = th.headGasketBoost or 1.0
  if boost and boost > hgTh then
    damage.headGasket = damage.headGasket + (boost - hgTh) * dt * 3
  end

  -- Piston ring wear: sustained high RPM
  local ringTh = th.pistonRingRPM or 1.0
  local maxRPM = (engine and engine.maxRPM) or 7000
  if rpm > maxRPM * ringTh * 0.92 then
    damage.pistonRings = damage.pistonRings + dt * 2
  end

  -- Rod stress: rapid load spikes at high RPM (approximated via load*rpm ratio)
  local rodTh = th.rodTorqueSpike or 1.0
  local rodStress = (load * (rpm / math.max(maxRPM, 1))) / rodTh
  if rodStress > 1 then
    damage.rods = damage.rods + (rodStress - 1) * dt * 5
  end

  damage.cylinderWall = math.min(damage.cylinderWall, 100)
  damage.headGasket = math.min(damage.headGasket, 100)
  damage.pistonRings = math.min(damage.pistonRings, 100)
  damage.rods = math.min(damage.rods, 100)

  local total = math.max(damage.cylinderWall, damage.headGasket, damage.pistonRings, damage.rods)
  damagePenalty = 1 - (total / 100) * 0.6
  if damagePenalty < 0.25 then damagePenalty = 0.25 end

  electrics.values.sunburstEcuDamage = total
  electrics.values.sunburstEcuDamageCylinderWall = damage.cylinderWall
  electrics.values.sunburstEcuDamageHeadGasket = damage.headGasket
  electrics.values.sunburstEcuDamagePistonRings = damage.pistonRings
  electrics.values.sunburstEcuDamageRods = damage.rods

  -- rough misfire feedback once things get bad
  if total > 85 and engine and engine.ignitionCoef ~= nil and revLimiterCutTimer <= 0 then
    if math.random() < (total - 85) / 100 then
      engine.ignitionCoef = 0.4
    end
  end
end

local function updateGFX(dt)
  if not engine then
    engine = powertrain.getDevice("mainEngine")
    if engine then
      snapshotTorqueCurve()
    else
      return
    end
  end

  local rpm = (electrics.values and electrics.values.rpm) or 0
  local load = (electrics.values and electrics.values.engineLoad) or 0
  local boost = (electrics.values and electrics.values.boost) or 0

  applyIdleRPM()
  applyRevLimiter(dt, rpm)
  updateDamage(dt, rpm, load, boost)
  rebuildTorqueCurve()
end

local function setPowerMultiplier(mult)
  params.powerMultiplier = math.max(0.2, math.min(5, mult or 1))
  rebuildTorqueCurve()
end

local function setIndestructible(state)
  params.indestructible = state and true or false
end

local function setBigBlockRemap(state)
  params.bigBlockRemap = state and true or false
  rebuildTorqueCurve()
end

local function init(jbeamData)
  params = jbeamData or {}
  params.powerMultiplier = params.powerMultiplier or 1
  params.revLimiterRPM = params.revLimiterRPM or 7200
  params.revLimiterCutTimeMs = params.revLimiterCutTimeMs or 60
  params.idleRPM = params.idleRPM or 900
  params.indestructible = params.indestructible or false
  params.bigBlockRemap = params.bigBlockRemap or false
  params.torqueLimitNm = params.torqueLimitNm or 0
  params.damageThresholds = params.damageThresholds or {}

  engine = powertrain.getDevice("mainEngine")
  snapshotTorqueCurve()

  damage.cylinderWall = 0
  damage.headGasket = 0
  damage.pistonRings = 0
  damage.rods = 0
  damagePenalty = 1
  revLimiterCutTimer = 0

  rebuildTorqueCurve()
  applyIdleRPM()
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
