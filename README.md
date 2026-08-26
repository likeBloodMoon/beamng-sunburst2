# beamng-sunburst2

A tuning-focused addon for the Sunburst's 2.5L F4 that turns it into a proper
experimental monster. This pack adds a fully tunable Lua-powered ECU, a
variable-geometry turbo in three stages, three transmission options built to
handle stupid amounts of torque, and an optional "big block" torque-curve
remap for a V8-style pull.

## Install

Drop the `lua/` and `vehicles/` folders into a `.zip` and place it in your
BeamNG `mods` folder (or unzip straight into `Documents/BeamNG.drive/<version>/mods/`).
In the vehicle Parts Configurator for the Sunburst you should see three new
slots to equip:

- **Engine Management** → Deluxe Lua ECU
- **Turbocharger** → VGT Turbo Stage 1/2/3
- **Transmission** → 15-Speed Manual / 6-Speed Sequential / 8-Speed Auto

If your game version has renamed the engine-management or turbocharger slot
on the Sunburst, open the part in a text editor and change the single
`"slotType"` line at the top to match — everything else (the controller
wiring, the Lua) is independent of that and doesn't need to change.

## 🧠 Deluxe Lua ECU

- Adjustable rev limiter RPM & ignition-cut time
- Custom idle RPM
- Power Multiplier (0.2×–5×) that scales the whole torque curve, applied at
  runtime so it works no matter which engine is equipped
- Toggleable **indestructible engine** mode
- A soft-damage model tracking four independent wear channels — cylinder
  wall load, head-gasket boost stress, piston-ring RPM wear, and rod stress
  from load spikes — each with its own tunable threshold. Wear reduces
  power and can trigger misfires; repairing the vehicle resets it (damage
  is cleared in the controller's `reset`, same hook the game calls on
  repair)
- Optional **big-block remap**: reshapes the active engine's torque curve
  toward a broad, low-revving OHV V8 character (~420 hp @ 5600 rpm / 460
  lb-ft @ 4100 rpm before your power multiplier is applied on top) — see
  "About the V8" below for why this is implemented as a remap rather than a
  new physical engine part.

Tune it by editing the values in `vehicles/sunburst/sunburst2_ecu_deluxe_lua.jbeam`.

## 🌀 Variable Geometry Turbo (Stages 1–3)

Each stage is a full VGT simulation, not just a static boost bump:

- Low/high boost multipliers that blend smoothly around a transition RPM
- Spool-time lag (first-order response) so boost builds progressively
  instead of snapping on
- Transient overboost peak on hard throttle tip-in that decays back to the
  steady-state target
- Simulated vane angle published to `electrics.values.sunburstVgtVaneAngle`
  for gauge/HUD hookups, alongside `sunburstTurboBoostMult` and
  `sunburstTurboSpool`

Stage 1 is mild and quick-spooling, Stage 2 balances midrange and top-end,
Stage 3 is a big, laggy, aggressive hit.

## ⚙️ Transmissions

- **15-Speed Manual & Transaxle** — tight, close-ratio lower gears for
  acceleration, long overdrives for cruise/top speed, 1400 Nm capacity
- **6-Speed Sequential** — quick-shifting sport box with taller cruise
  gearing, fast shift time, 1200 Nm capacity
- **8-Speed Automatic** — wide-spread ratios with a raised shift-up point
  and sport shift logic flag to keep boosted torque on boil, 1500 Nm
  capacity

Ratios live in each `sunburst2_transmission_*.jbeam` file if you want to
adjust the spread.

## About the V8

The README always said "yes I know I could have made this all in jbeam" —
that's true of the transmissions and turbo stages, which are plain jbeam
data. The 6.2L V8 is intentionally **not** a new physical engine part: doing
that properly needs the Sunburst's actual chassis node/beam names and a new
engine mesh, neither of which ship with this repo. Building a fake engine
block with guessed node names would either silently fail to load or wreck
the car's mass distribution, so instead the V8 character is delivered as the
ECU's big-block remap — same drivetrain feel and target numbers, applied to
whichever real engine you have equipped, no risk of a broken vehicle. If
someone wants to contribute a real mesh + node set for a physical swap, the
remap curve in `sunburstDeluxeECU.lua` is the exact torque target to match.

## Changelog

**2.0**
- Replaced the empty `lua`/`vehicles` placeholders with an actual working
  mod: two vehicle Lua controllers and seven jbeam parts
- Rewrote the ECU as a real runtime power multiplier + rev limiter + idle
  control + four-channel soft-damage model with an indestructible toggle
- Added the VGT turbo controller with spool lag and transient overboost
  shaping for all three stages
- Added the three transmissions as standard gearbox jbeam parts
- Replaced the literal "V8 swap" with an ECU big-block remap (see above)
  to avoid shipping a physically-broken engine part

PS. yes I know I could have made the transmissions and turbo in plain
jbeam — I did. The ECU and VGT behaviour genuinely need Lua though, shush.
