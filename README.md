# entities-sakuragaoka-station

A port of a procedurally generated, cel-shaded station town into the engine, rebuilt from its generation code rather than imported.

## What it is for

The `sakuragaoka_station` addon reimplements the original's world modules, builds them at a seed, and realizes them as engine nodes, with vector signage drawn by a godot-sandbox guest. The gates under `tools/` compare the port against the original's own output, and each carries a control that must fail. RFD 2267 covers the port.

## Build and run

Open `project.godot` in an engine that loads the godot_sandbox addon, which this repository does not carry, and run the main scene; without the addon the vector signage is not drawn. `guest/slug/build.sh` rebuilds the vector-shape guest inside a goal-manifest checkout, where the riscv64 sysroot and slughorn sit beside it.

## Licence

MIT; see `LICENSE`. The vendored toon shader under `addons/` carries its own licence.
