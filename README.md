# entities-sakuragaoka-station

A port of a procedurally generated, cel-shaded station town into the engine, rebuilt from its generation code rather than imported.

## What it is for

The `sakuragaoka_station` addon reimplements the original's world modules, builds them at a seed, and realizes them as engine nodes, with vector signage drawn by a godot-sandbox guest. The gates under `tools/` compare the port against the original's own output, and each carries a control that must fail. RFD 2267 covers the port.

The original is vendored in this repository as a git subtree at `original/`: `V-Sekai-archive/sakuragaoka-station` at `f7cf5ac`, which is Kenton-GMI's MIT three.js scene at `4112f57` plus the reference oracle the gates name as their generator. The oracle scripts under `tools/oracle/` read that subtree by default, so a gate needs no checkout beside this one. Refresh it with `git subtree pull --prefix=original https://github.com/V-Sekai-archive/sakuragaoka-station main --squash`.

## Build and run

Open `project.godot` in an engine that loads the godot_sandbox addon, which this repository does not carry, and run the main scene; without the addon the vector signage is not drawn. `guest/slug/build.sh` rebuilds the vector-shape guest inside a goal-manifest checkout, where the riscv64 sysroot and slughorn sit beside it.

The oracle scripts under `tools/oracle/` need the vendored original's dependencies: run `npm ci` in `original/` once, which installs three and puppeteer-core there.

## Licence

MIT; see `LICENSE`. The vendored toon shader under `addons/` carries its own licence.
