# characters/atlas.js: the per-character 512² canvas atlas (one material per character):
#   Q0 (canvas 0..256, 0..256)    painted face in "angle space" (see FACE)
#   Q1 (256..512, 0..256)         plain white — vertex-coloured parts sample its centre
#   Q2 (0..256, 256..512)         hair: vertical tone ramp + "angel ring" highlight strokes
#   Q3 (256..512, 256..512)       4 × 128² cells: stripes (sailor collar / cuffs), plaid, misc A, misc B
# The port draws no canvases: makeAtlas returns a sized stand-in under the original's key. The uv
# helpers that map geometry into the quadrants are ported as they are.
extends RefCounted

const FACE := {"p0": -80.0, "p1": 80.0, "t0": -90.0, "t1": 42.0}   # degrees (azimuth φ, elevation θ)
const S := 512.0
const Q := 256.0
const INSET := 2.0 / S


## atlas uv of a face-window angle (deg). Outside the window -> plain skin sample.
static func face_uv(ph_deg: float, th_deg: float) -> Array:
	if ph_deg < FACE.p0 or ph_deg > FACE.p1 or th_deg < FACE.t0 or th_deg > FACE.t1:
		return [6.0 / S, 1.0 - 250.0 / S]
	var x: float = (ph_deg - FACE.p0) / (FACE.p1 - FACE.p0)
	var y: float = (FACE.t1 - th_deg) / (FACE.t1 - FACE.t0)
	return [INSET + x * (0.5 - 2.0 * INSET), 1.0 - (INSET + y * (0.5 - 2.0 * INSET))]


## hair ramp uv: row 0 = crown .. 1 = tips; col 0..1 across the stroke band
static func hair_uv(row: float, col: float = 0.5) -> Array:
	var r := minf(1.0, maxf(0.0, row))
	var c := minf(1.0, maxf(0.0, col))
	return [INSET + c * (0.5 - 2.0 * INSET), 0.5 - INSET - r * (0.5 - 2.0 * INSET)]


## Q3 cells: 0 stripes, 1 plaid, 2 miscA, 3 miscB. (gu, gv) in 0..1, gv = 1 = top of the cell
static func cell_uv(cell: int, gu: float, gv: float) -> Array:
	var cx := 256.0 + (cell % 2) * 128.0
	var cy := 256.0 + floorf(cell / 2.0) * 128.0
	var x := cx + 2.0 + gu * 124.0
	var y := cy + 2.0 + (1.0 - gv) * 124.0
	return [x / S, 1.0 - y / S]


static func cell_rect(cell: int) -> Array:
	var a := cell_uv(cell, 0.0, 0.0)
	var b := cell_uv(cell, 1.0, 1.0)
	return [a[0], a[1], b[0], b[1]]


## The atlas texture for one character + variant. spec: {key, face, hair, stripes?, plaid?, misc?}
static func make_atlas(ctx, spec: Dictionary, variant: String = "open"):
	var key := "chr|%s|%s" % [spec.key, variant]
	return ctx.tex.draw(int(S), int(S), null, {"key": key, "anisotropy": 4})
