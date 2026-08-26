# beamng-sunburst2

A tuning-focused addon for the Hirochi Sunburst's 2.5L F4 that turns it into
a proper experimental monster. This pack adds a fully tunable Lua-powered
ECU, a variable-geometry turbo in three stages, three transmission options
built to handle stupid amounts of torque, and an optional "big block"
torque-curve remap for a V8-style pull.

Every part in this repo is built against the Sunburst's real stock jbeam
files (`sunburst2.jbeam`, the `sunburst2_engine_*` and `sunburst2_transaxle*`
families) — verified slot types, real node/beam geometry cloned from the
actual stock turbo and gearbox parts, and the engine's real native damage
and rev-limiter fields, not guesses.

## Install

Drop the `lua/`, `vehicles/`, and `ui/` folders into a `.zip` and place it in
your BeamNG `mods` folder (or unzip straight into
`Documents/BeamNG.drive/<version>/mods/`). In the Sunburst's Parts
Configurator, under the 2.5L F4 engine, you'll find new options in:

- **Engine Management** → Deluxe Lua ECU (also fits the 1.6L and 2.0L)
- **Intake** → VGT Turbo Stage 1/2/3 (2.5L only)
- **Transaxle** → 15-Speed Manual / 6-Speed Sequential / 8-Speed Auto

## 🧠 Deluxe Lua ECU

- Adjustable rev limiter RPM & cut time, and idle RPM — these are the
  engine's real native fields (`revLimiterRPM`, `revLimiterType`,
  `revLimiterCutTime`, `idleRPM`), exposed as live in-game sliders via jbeam
  `variables`, exactly like the stock "Adjustable Race ECU" does it
- Power Multiplier (0.2×–5×) that scales the whole torque curve at runtime,
  applied in Lua so it works no matter which engine is equipped — this is
  the one thing that genuinely needs Lua rather than static jbeam, since it
  has to apply uniformly regardless of the base curve
- Toggleable **indestructible engine** mode: live-overrides the engine's
  real native damage thresholds (`cylinderWallTemperatureDamageThreshold`,
  `headGasketDamageThreshold`, `pistonRingDamageThreshold`,
  `connectingRodDamageThreshold`, `maxTorqueRating`, `maxOverTorqueDamage`)
  to effectively-infinite values, and restores your configured baseline
  when switched off
- Configurable damage thresholds baked into the part as reasonable "deluxe"
  defaults — edit them directly in `sunburst2_ecu_deluxe_lua.jbeam` since
  they're the same native fields the stock long-block parts use
- Optional **big-block remap**: reshapes the active engine's torque curve
  toward a broad, low-revving OHV V8 character (~420 hp @ 5600 rpm / 460
  lb-ft @ 4100 rpm before your power multiplier is applied on top) — see
  "About the V8" below for why this is a remap rather than a new physical
  engine part

## 🌀 Variable Geometry Turbo (Stages 1–3)

BeamNG's own turbocharger model already simulates spool lag correctly via
turbine inertia and the `pressurePSI`/`engineDef` curves, so these stages
tune that real model rather than faking a second one in Lua. Geometry
(intake, intercooler, exhaust manifold, all the node/beam attachment points)
is cloned directly from the Sunburst's real stock turbo parts, so it mounts
correctly. What makes them "VGT": each stage's `engineDef` efficiency curve
is shaped for noticeably better low-RPM exhaust energy capture than the
stock turbo — the real advantage of variable vane geometry — layered as a
tuning choice on top of the real physics, not a separate simulation.

- **Stage 1 (Mild)** — small turbo, quick-spooling, mild low-boost curve
- **Stage 2 (Balanced)** — bigger turbo, stronger midrange, race exhaust
- **Stage 3 (Aggressive)** — largest turbo, highest boost, optional
  anti-lag slot (reuses BeamNG's own stock `powertrainControl/antiLag`
  controller), flutter valve instead of a BOV

The Lua controller (`sunburstVGTTurbo.lua`) adds one genuinely new thing on
top: a best-effort blow-off-valve sound cue on a hard lift-off under boost,
`pcall`-guarded and backed by an `electrics.values.sunburstVgtBovPulse`
pulse either way so a `soundConfig` can hook in directly if the built-in
event name doesn't match your game version.

## ⚙️ Transmissions

Real gearbox device types (`frictionClutch`+`manualGearbox`,
`frictionClutch`+`sequentialGearbox`, `torqueConverter`+`cvtGearbox`), the
same `tra1` node/beam attachment pattern the stock transaxles use, and the
same `sunburst2_flywheel` / `sunburst2_transfer_case` /
`sunburst2_differential_F` child slots so they compose with the rest of the
drivetrain normally.

- **15-Speed Manual & Transaxle** — close-ratio lower gears for
  acceleration, long overdrives for cruise/top speed. Every gear ratio is
  its own live-adjustable variable, same pattern as the stock race gearbox
- **6-Speed Sequential** — quick-shifting sport box with taller cruise
  gearing, built directly off the stock race sequential transaxle
- **8-Speed Automatic** — a real torque-converter automatic using the
  stock CVT unit's `cvtSportGearRatios` field to give it 8 discrete stepped
  ratios instead of a continuously-variable feel, with a raised shift point

## 🖥️ Tuning app

`ui/modules/apps/SunburstDeluxeECU/` adds an in-game UI app (drag it onto
your screen from the apps menu while driving) with live RPM and boost
readouts plus a power-multiplier slider and indestructible/big-block
toggles that apply immediately, no part re-equip needed.

This is the one piece of the mod that couldn't be checked against a running
BeamNG install, so treat it as unverified: if it doesn't appear or doesn't
render, everything else in the mod still works exactly the same via the
in-game Parts Configurator sliders or by editing the jbeam directly — the
app is a convenience layer, not a dependency.

## About the V8

The README always said "yes I know I could have made this all in jbeam" —
true of the transmissions and turbo stages, which are plain jbeam data. The
6.2L V8 is still **not** a new physical engine part. The good news: with the
real stock engine files now in hand, I can confirm the 1.6L/2.0L/2.5L
engines all share the exact same `e1r/e1l/e2r/e2l/e3r/e3l/e4r/e4l` node
layout and engine-mount positions — so a real physical V8 part *is*
buildable on top of this repo now (clone that same node/beam pattern, heavier
mass, its own torque curve and sub-slots). It just hasn't been done yet — it
needs its own set of sub-parts (intake, long block, ECU slots scoped to the
V8) that didn't fit in this pass. Until then, the V8 character is delivered
as the ECU's big-block remap, applied to whichever real engine you have
equipped.

## Changelog

**3.0**
- Rebuilt every part against the Sunburst's real stock jbeam files (thanks
  to files provided directly from a BeamNG install) instead of best-guess
  slot names — moved `vehicles/sunburst/` → `vehicles/sunburst2/` to match
  the real vehicle directory
- Fixed slot types to the real ones: `sunburst2_engine_{1_6,2_0,2_5}_ecu`
  for the ECU, `sunburst2_engine_2_5_intake` for the turbo stages,
  `sunburst2_transaxle` for the transmissions
- Rebuilt the turbo stages with real node/beam/flexbody geometry cloned
  from the stock turbo parts, so they actually mount correctly
- Rebuilt the transmissions on the real gearbox device types and the real
  `tra1` node pattern, with proper flywheel/transfer-case/differential
  child slots
- Simplified the Deluxe ECU controller: removed the guessed custom damage
  simulation and rev-limiter hack now that the engine's real native damage
  thresholds and rev limiter fields are confirmed — the ECU now tunes those
  directly and only uses Lua for the power multiplier and the indestructible
  toggle
- Simplified the VGT turbo controller: removed the fake spool-lag
  simulation now that BeamNG's native turbocharger model is confirmed to
  already do this correctly; kept only the blow-off-valve sound cue
- Added live in-game sliders (jbeam `variables`) for rev limiter, idle RPM,
  power multiplier, wastegate target, and every gear ratio

**2.1**
- Added a GitHub Actions workflow that validates every `.jbeam` file as
  JSON and every `.lua` file's syntax on push
- Added the in-game tuning UI app
- Added best-effort backfire and blow-off-valve sound hooks

**2.0**
- Replaced the empty `lua`/`vehicles` placeholders with an actual working
  mod: two vehicle Lua controllers and seven jbeam parts

PS. yes I know I could have made the transmissions and turbo in plain
jbeam — I did. The ECU's power multiplier and indestructible toggle
genuinely need Lua though, shush.
