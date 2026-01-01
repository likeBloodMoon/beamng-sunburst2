local M = {}

local engine
local electrics
local loggedElectricsFailure = false

local function safeElectricsSet(name, value)
  if not name then return end
  local ok, err = pcall(function()
    if electrics and type(electrics.set) == "function" then
      electrics.set(name, value)
    elseif electrics and electrics.values then
      electrics.values[name] = value
    else
      -- try global electrics
      if type(electrics) == "table" then electrics[name] = value end
    end
  end)
  if not ok then
    -- swallow errors to avoid spamming log
  end
end

local function init()
  engine = powertrain.getDevice("mainEngine") or powertrain.getDevice("engine")

  -- attempt to find electrics API
  if not electrics then electrics = rawget(_G or {}, "electrics") end
  -- some vehicle setups provide an `electrics` module
  if not electrics and type(require) == "function" then
    local ok, mod = pcall(require, "electrics")
    if ok and type(mod) == "table" then electrics = mod end
  end

  if not electrics and not loggedElectricsFailure then
    log("W", "sunburst2_vgt_gauge", "Could not bind to electrics; VGT gauges will not update")
    loggedElectricsFailure = true
  end
end

local function reset()
  init()
end

local function updateGFX(dt)
  if not engine then return end
  local boost = engine.vgt_currentBoost or engine.vgt_exposedToGauges or engine.vgt_targetBoost or 1.0
  local vane = engine.vgt_vanePos or 0
  local soundLevel = engine.vgt_soundLevel or 0

  -- publish to electrics so gauges / html can read them
  safeElectricsSet("vgt_boost", boost)
  safeElectricsSet("vgt_vane", vane)
  safeElectricsSet("vgt_sound", soundLevel)
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX

return M
