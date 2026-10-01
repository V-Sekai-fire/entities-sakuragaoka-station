# Shadow-map setup: plan

The sun is the same in both engines (`tools/calib/sun_locate.json`), so what still differs
in the shadows is the shadow map. This rung gives the port the original's shadow map, on top of
the toon-ramp hook, and touches `station.gd` only after that merge lands on feat/slug.

## Settings

| | original (sky.js, three r170) | port today | planned |
|---|---|---|---|
| coverage | one orthographic box of half-size S: 75 at high, 60 medium, 45 low | PSSM, 4 splits to max distance 100 | `SHADOW_ORTHOGONAL`, one map |
| texel | 2S / 4096: 3.66 cm (about 1.7 nickels) | 1.22 / 2.27 / 5.72 / 11.3 cm by split (a AAA battery to 1.7 soda cans) | max distance d = S / k, so Godot's bounding radius is S and the texel is the original's 3.66 cm (about 1.7 nickels) |
| filter | soft PCF: a 3-texel box through a bilinear tent, SD 0.96 texel; its radius 1.6 is ignored | Soft Low, 4 taps, radius 2 texels | Soft Medium (8 taps), blur 0.87, so radius 1.73 texels and SD 0.96 texel; then tuned to the measured blur |
| normal bias | 3.5 cm (about 1.7 nickels) along N | 2 texels | `shadow_normal_bias` 0.957: 3.5 cm (about 1.7 nickels) in 3.66 cm texels |
| depth bias | 0.00035 of 519 m depth: 18.2 cm (about 2.8 soda cans) toward the light | 0.1: 9.0 to 13.3 cm (about 1.4 to 2 soda cans) | `shadow_bias` 0.062: 0.01 x (2r + pancake) x blur x 2 gives 18.2 cm (about 2.8 soda cans) |
| fade | the box's hard edge | from 80 % of max distance | `directional_shadow_fade_start` 0.999 |
| shading | toon irradiance x shadow, edge at 50 % | MToon's step, edge at about 69 % | the ramp hook: `ramp_gradient(N.L) * ATTENUATION`, edge at 50 % |

k is the frustum's bounding-radius factor, 1.237 for this camera (58 degrees, 16:9), so d is
60.6 at high, 48.5 at medium and 36.4 at low (`Quality.apply` sets d and both biases per level
from S, the atlas side and the active camera's k, since a headset frustum has its own k).

The cost of matching the texel is range. The port's shadows end at view depth d, where the
original's box reaches 1.45 S ahead. So two candidates are measured. A is texel-matched (d 60.6,
as above). B is d 75 with 4.53 cm texels (about 2.1 nickels): normal bias 0.773, depth bias 0.051.
A third, an 8192 atlas with d 121, matches the texel out past 1.45 S at four times the shadow
memory, and is kept for the case where A and B both make a far view worse.

## Measurements and gates

Every gate has a control that has to fail.

1. **Tip shift and edge softness.** `tools/sun_locate.gd --analyze` on the port's renders, with the
   port's edge model in metres once it has one map. The original's: dilation 8.2 mm (about 1.2
   pencils), normal-bias shift 5.7 cm (about an adult wrist), blur 2.5 cm (about 1.2 nickels).
   Its floor is the larger of two spreads. One is a bootstrap of the edge model over posts (to add:
   refit d, b and s per replicate). The other is the original's image against its own shadow-free
   render: 2.1 mm, 7.7 mm and 1.7 mm (about 3 credit cards, a pencil, 2 credit cards). Per post the
   observed tips are model-free: today the port's run 2.1, 3.9, 3.5, 5.6 and 1.0 cm longer than the
   original's (bollard0, bollard1, bollard4, postbox, taxi; about a AAA battery to an adult
   wrist), against the original's own 1.0 to 1.7 cm (about a AAA to an AA battery). Gate: the edge model and
   every tip within the floor. Control: doubling the normal bias, or the blur, fails it.
2. **MToon's snap against the ramp hook.** With the hook, the port's dilation falls from 0.33 texel
   to the original's 8.2 mm (about 1.2 pencils), within the floor. Control: `RAMP_CONTROL_STEP`
   brings the dilation back.
3. **Dapple.** `tools/toon_ramp_canopy.gd --controls=dapple`: view 0 moves by its predicted -1.57,
   within max(0.1, 25 %).
4. **No view worse.** `tools/realize_check.gd` full-resolution MAD per view against the oracle,
   before (ramp merged, PSSM) and after.
5. **Budget.** realize_check's triangles and draws, which a light setting leaves alone, and per
   frame the viewport's render info for the visible and the shadow pass (draw calls, primitives) at
   the 8 views. One orthogonal pass in place of four splits should lower the shadow pass.

## Order once the merge lands

1. Fast-forward feat/sun-locate onto feat/slug; record the baseline (gates 1 to 5) with the hook
   and PSSM.
2. Set A, render, measure; sweep the blur (0.5 to 1.0) for gate 1; repeat for B.
3. Keep the candidate that passes every gate, with its controls, and commit the numbers beside
   `sun_locate.json`.
