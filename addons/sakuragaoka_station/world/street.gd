# street.js: every road surface (R1 main street, R2, R3, R4, R6 and junction fillets), R1 curbed
# sidewalks with corner ramps and tactile paving, L-gutters, U-ditches with lids, gratings and open
# water, road markings and road text, manholes, lids, repair patches, stains, spray marks, standalone
# sign posts, convex mirrors, guardrails and cones at a repair site. Publishes ctx.services.street.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const SM = preload("res://addons/sakuragaoka_station/world/street/mesh.gd")
const ST = preload("res://addons/sakuragaoka_station/world/street/textures.gd")
const Furniture = preload("res://addons/sakuragaoka_station/world/street/furniture.gd")
const Ditch = preload("res://addons/sakuragaoka_station/world/street/ditch.gd")

const LIFT := 0.02
const ATILE := 4.0
const CURB_H := 0.13
const UP := [0.0, 1.0, 0.0]


static func smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func range_of(a: float, b: float, step: float) -> Array:
	var n := maxi(1, int(T.js_round(absf(b - a) / step)))
	var o := []
	for i in n + 1:
		o.append(a + (b - a) * i / n)
	return o


static func cat(rs: Array) -> Array:
	var out := []
	for r in rs:
		for v in r:
			if out.is_empty() or absf(v - out[out.size() - 1]) > 1e-6:
				out.append(v)
	return out


static func mirror_list(half: Array) -> Array:
	var o := []
	for i in range(half.size() - 1, 0, -1):
		o.append(-half[i])
	return o + half


static func col_of(hex: String) -> Array:
	var c := T.color(hex)
	return [c.r, c.g, c.b]


static func fx(v: float, d: int) -> float:
	return float(("%." + str(d) + "f") % v)


static func hr(a: float, b: float) -> float:
	var x := sin(a * 127.1 + b * 311.7) * 43758.5453
	return x - floorf(x)


static func section(seed: float, s: float, length: float = 30.0) -> float:
	var q := s / length
	var k := floorf(q)
	var f := q - k
	var va := 0.955 + 0.09 * hr(seed, k)
	var vb := 0.955 + 0.09 * hr(seed, k + 1)
	return lerpf(va, vb, smooth(0.93, 1.0, f))


static func bump(a: float, c: float, w: float) -> float:
	return maxf(0.0, 1.0 - absf(a - c) / w)


static func prof2(o: float) -> float:
	var a := absf(o)
	return 1 + 0.085 * bump(a, 0.58, 0.3) + 0.085 * bump(a, 2.08, 0.3) - 0.04 * bump(a, 1.33, 0.25) - 0.02 * bump(a, 0, 0.3)


static func prof1(o: float) -> float:
	var a := absf(o)
	return 1 + 0.06 * bump(a, 0.8, 0.3) - 0.03 * bump(a, 0, 0.3)


static func grime(a: float, hw: float, on: bool) -> float:
	return 1 - 0.075 * smooth(hw - 0.35, hw, a) if on else 1.0


static func tone3(m: float) -> Array:
	return [m, m * 0.998, m * 1.008]


static func in_r(v: float, a: float, b: float) -> bool:
	return v >= a and v <= b


func build(ctx):
	var L = ctx.L
	var mat = ctx.mat
	var physics = ctx.physics
	var H: Callable = L.height_at
	var cX: Callable = L.street_center_x
	var sX: Callable = L.street_slope_x
	var root := T.Group.new()
	root.name = "street"
	ctx.add_static(root)
	var TX := ST.make_street_textures(ctx)

	# frames and heights
	var r2_stair = null
	for st in ctx.services.get("environment", {}).get("levee", {}).get("stairs", []):
		if absf(st.x - L.ROADS.R2.x) < 3:
			r2_stair = st
			break
	var R2N: float = maxf(-84.2, r2_stair.z1 - 0.3) if r2_stair else -83.8
	var lift_at := func(_x: float, z: float) -> float:
		return LIFT + 0.04 * smooth(-83.3, -85.3, z)
	var road_y := func(x: float, z: float) -> float:
		return H.call(x, z) + lift_at.call(x, z)
	var r1 := func(zc: float, o: float) -> Array:
		var sx: float = sX.call(zc)
		var length := sqrt(sx * sx + 1)
		return [cX.call(zc) + o / length, zc - o * sx / length]
	var r1T := func(zc: float) -> Array:
		var sx: float = sX.call(zc)
		var length := sqrt(sx * sx + 1)
		return [-sx / length, -1 / length]
	var r1N := func(zc: float) -> Array:
		var sx: float = sX.call(zc)
		var length := sqrt(sx * sx + 1)
		return [1 / length, -sx / length]
	var road_y2 := func(p: Array) -> float:
		return road_y.call(p[0], p[1])

	var M := {
		"asphalt": mat.toon("#ffffff", {"map": TX.asphalt, "vertexColors": true, "paint": 0.03}),
		"pavers": mat.toon("#ffffff", {"map": TX.pavers, "paint": 0.035}),
		"curb": mat.toon("#ffffff", {"map": TX.curb, "paint": 0.03}),
		"lgutter": mat.toon("#ffffff", {"map": TX.lgutter, "paint": 0.03, "polygonOffset": -1}),
		"lid": mat.toon("#ffffff", {"map": TX.lid, "paint": 0.04}),
		"grate": mat.toon("#ffffff", {"map": TX.grate, "alphaTest": 0.5, "side": "double", "paint": 0}),
		"dots": mat.toon("#ffffff", {"map": TX.dots, "paint": 0.02, "polygonOffset": -1}),
		"bars": mat.toon("#ffffff", {"map": TX.bars, "paint": 0.02, "polygonOffset": -1}),
		"line": mat.decal("#ffffff", {"map": TX.line, "vertexColors": true}),
		"paint": mat.decal("#ffffff", {"map": TX.paint, "vertexColors": true}),
		"glyph": mat.decal("#ffffff", {"map": TX.glyphs, "vertexColors": true}),
		"util": mat.decal("#ffffff", {"map": TX.util}),
	}

	var F := Furniture.new(ctx, root, TX, {"baseLift": func(_x, _z): return 0.0})
	var VC = F.VC
	var solid := func(B, hex: String):
		var c := T.color(hex)
		for i in B.n:
			B.col[i * 3] = c.r
			B.col[i * 3 + 1] = c.g
			B.col[i * 3 + 2] = c.b
		return B
	var add := func(b, material, o: Dictionary = {}):
		if b.is_empty():
			return null
		var m = b.mesh(material, o)
		root.add(m)
		if o.get("noOutline", false):
			ctx.no_outline(m)
		return m

	var r3_tone := func(x: float, o: float) -> float:
		var mouth := (o > 0 and absf(x) < 5.25) or (o < 0 and in_r(x, -17.3, -9.2))
		return prof2(o) * grime(absf(o), 3.0, not mouth) * section(23, x, 36) * 1.02
	var r1_tone := func(zc: float, o: float) -> float:
		var a := absf(o)
		var m: float = prof2(o) if a <= 2.6 else (0.955 if a <= 3.0 else 0.985 - 0.07 * smooth(4.2, 4.6, a))
		m *= section(11, zc, 34)
		if o < 0 and o > -2.6:
			m *= 1 - 0.045 * smooth(13, 4, zc) * bump(a, 1.33, 0.7)
		return m
	var r2_mouth := func(z: float) -> bool:
		return z > -7.6 or in_r(z, -59.6, -52.2) or in_r(z, -74.1, -67.9)
	var r2_tone := func(z: float, o: float) -> float:
		return prof1(o) * grime(absf(o), 2.75, not r2_mouth.call(z)) * section(37, z, 30) * 1.03
	var r2_edge := func(z: float) -> float:
		return section(37, z, 30) * 1.03
	var lane_tone := func(seed: float, base: float, hw: float) -> Callable:
		return func(x: float, o: float) -> float:
			return prof1(o) * grime(absf(o), hw, true) * section(seed, x, 40) * base

	# road surfaces
	var roadB := SM.MeshBuilder.new(true)
	var surf := func(rows: Array, lats: Array, pos: Callable, tone: Callable) -> void:
		SM.grid(roadB, rows.size(), lats.size(), func(i, j):
			var s: float = rows[i]
			var o: float = lats[j]
			var xz: Array = pos.call(s, o)
			var m: float = tone.call(xz[0], xz[1], s, o)
			return {"x": xz[0], "y": road_y.call(xz[0], xz[1]), "z": xz[1], "u": xz[0] / ATILE, "v": -xz[1] / ATILE, "c": tone3(m)})
	var R1_HALF := [0, 0.3, 0.58, 0.86, 1.33, 1.8, 2.08, 2.36, 2.6, 2.72, 3.0, 3.8, 4.6]
	var R1_LAT := mirror_list(R1_HALF)
	var R1A_LAT := R1_LAT.filter(func(o): return absf(o) <= 3.0 + 1e-6)
	var R3_LAT := mirror_list([0, 0.3, 0.58, 0.86, 1.33, 1.8, 2.08, 2.36, 2.72, 3.0])
	var R2_LAT := mirror_list([0, 0.5, 0.8, 1.1, 1.8, 2.4, 2.75])
	var R4_LAT := mirror_list([0, 0.5, 0.8, 1.1, 1.65, 2.0])
	var R6_LAT := mirror_list([0, 0.5, 0.8, 1.1, 1.5])
	var r1p := func(zc, o): return r1.call(zc, o)
	surf.call(range_of(1.0, 3.2, 0.44), R1A_LAT, r1p, func(x, _z, zc, o): return lerpf(r3_tone.call(x, 3.0), r1_tone.call(zc, o), smooth(1.0, 3.2, zc)))
	surf.call(cat([range_of(3.2, 12, 0.4), range_of(12, 130, 1.0)]), R1_LAT, r1p, func(_x, _z, zc, o): return r1_tone.call(zc, o))
	surf.call(cat([range_of(-95, -30, 2), range_of(-30, 30, 1), range_of(30, 95, 2)]), R3_LAT, func(x, o): return [x, -2 + o], func(x, _z, _s, o): return r3_tone.call(x, o))
	var r2T := func(x, z, _s, o): return lerpf(r2_tone.call(z, o), r3_tone.call(x, -3.0), smooth(-7.2, -5.0, z))
	surf.call(cat([range_of(R2N, -83, 0.4), range_of(-83, -53, 1), range_of(-53, -47.6, 0.3)]), R2_LAT, func(z, o): return [-12 + o, z], r2T)
	surf.call(cat([range_of(-38.4, -33, 0.3), range_of(-33, -5, 1)]), R2_LAT, func(z, o): return [-12 + o, z], r2T)
	var r4_base: Callable = lane_tone.call(41, 1.1, 2.0)
	var r6_base: Callable = lane_tone.call(43, 1.13, 1.5)
	var side_blend := func(base: Callable) -> Callable:
		return func(x, z, _s, o):
			var m: float = base.call(x, o)
			var w := smooth(-16.8, -14.75, x) if x < -12 else smooth(-7.2, -9.25, x)
			return lerpf(m, r2_edge.call(z), w)
	surf.call(cat([range_of(-95, -30, 2), range_of(-30, -14.75, 1)]), R4_LAT, func(x, o): return [x, -55.5 + o], side_blend.call(r4_base))
	surf.call(cat([range_of(-9.25, 30, 1), range_of(30, 95, 2)]), R4_LAT, func(x, o): return [x, -55.5 + o], side_blend.call(r4_base))
	surf.call(cat([range_of(-85, -30, 2), range_of(-30, -14.75, 1)]), R6_LAT, func(x, o): return [x, -71 + o], side_blend.call(r6_base))
	surf.call(cat([range_of(-9.25, 30, 1), range_of(30, 85, 2)]), R6_LAT, func(x, o): return [x, -71 + o], side_blend.call(r6_base))
	var FILLETS := [
		{"K": [-14.75, -5], "e1": [0, -1], "e2": [-1, 0], "r": 2.5},
		{"K": [-14.75, -57.5], "e1": [0, -1], "e2": [-1, 0], "r": 2.0}, {"K": [-9.25, -57.5], "e1": [0, -1], "e2": [1, 0], "r": 2.0},
		{"K": [-14.75, -53.5], "e1": [0, 1], "e2": [-1, 0], "r": 1.2}, {"K": [-9.25, -53.5], "e1": [0, 1], "e2": [1, 0], "r": 1.2},
		{"K": [-14.75, -72.5], "e1": [0, -1], "e2": [-1, 0], "r": 1.5}, {"K": [-9.25, -72.5], "e1": [0, -1], "e2": [1, 0], "r": 1.5},
		{"K": [-14.75, -69.5], "e1": [0, 1], "e2": [-1, 0], "r": 1.5}, {"K": [-9.25, -69.5], "e1": [0, 1], "e2": [1, 0], "r": 1.5},
		{"K": [-3, 1], "e1": [0, 1], "e2": [-1, 0], "r": 2.2, "r1": true}, {"K": [3, 1], "e1": [0, 1], "e2": [1, 0], "r": 2.2, "r1": true},
	]
	var fillet_arc := func(f: Dictionary, n: int = 12) -> Dictionary:
		var C := [f.K[0] + f.r * (f.e1[0] + f.e2[0]), f.K[1] + f.r * (f.e1[1] + f.e2[1])]
		var a1 := atan2(-f.e2[1], -f.e2[0])
		var a2 := atan2(-f.e1[1], -f.e1[0])
		var d := a2 - a1
		while d > PI:
			d -= TAU
		while d < -PI:
			d += TAU
		var pts := []
		for i in n + 1:
			var a := a1 + d * i / n
			pts.append([C[0] + f.r * cos(a), C[1] + f.r * sin(a)])
		return {"C": C, "pts": pts}
	for f in FILLETS:
		var pts: Array = fillet_arc.call(f).pts
		var kx: float = f.K[0]
		var kz: float = f.K[1]
		var k_idx := roadB.vert(kx, road_y.call(kx, kz), kz, kx / ATILE, -kz / ATILE, UP, tone3(1.0))
		var ring := func(fr: float, m: float) -> Array:
			var o := []
			for p in pts:
				var X: float = kx + (p[0] - kx) * fr
				var Z: float = kz + (p[1] - kz) * fr
				o.append(roadB.vert(X, road_y.call(X, Z), Z, X / ATILE, -Z / ATILE, UP, tone3(m)))
			return o
		var mid: Array = ring.call(0.5, 0.985)
		var out: Array = ring.call(1.0, 0.94)
		for i in pts.size() - 1:
			roadB.tri(k_idx, mid[i], mid[i + 1])
			roadB.quad(mid[i], out[i], out[i + 1], mid[i + 1])
	add.call(roadB, M.asphalt, {"computeNormals": true, "name": "street-asphalt"})

	# decal builders
	var lineB := SM.MeshBuilder.new(true)
	var paintB := SM.MeshBuilder.new(true)
	var glyphB := SM.MeshBuilder.new(true)
	var utilB := SM.MeshBuilder.new(false)
	var utilTopB := SM.MeshBuilder.new(false)
	var C_WHITE := col_of("#e7e5de")
	var C_ORANGE := col_of("#e59b3c")
	var C_YELLOW := col_of("#e4c14a")
	var C_GREEN := col_of("#86b494")
	var LINE_LIFT := 0.006
	var GLYPH_LIFT := 0.007
	var UTIL_LIFT := 0.004
	var strip := func(B, pts: Array, w: float, col, lift: float = LINE_LIFT, h_fn = null, tile: float = 0.8) -> void:
		var hf: Callable = h_fn if h_fn != null else road_y
		var rs := SM.resample(pts, 0.8)
		var prev = null
		for p in rs:
			var nx: float = -p.tz
			var nz: float = p.tx
			var ax: float = p.x + nx * w / 2
			var az: float = p.z + nz * w / 2
			var bx: float = p.x - nx * w / 2
			var bz: float = p.z - nz * w / 2
			var a: int = B.vert(ax, hf.call(ax, az) + lift, az, p.s / tile, w / tile, UP, col)
			var b: int = B.vert(bx, hf.call(bx, bz) + lift, bz, p.s / tile, 0, UP, col)
			if prev:
				B.quad(prev[0], prev[1], b, a)
			prev = [a, b]
	var quad := func(B, cell: Dictionary, cx: float, cz: float, w: float, l: float, dir: Array, lift: float, col = null, h_fn = null) -> void:
		var hf: Callable = h_fn if h_fn != null else road_y
		var dl := Vector2(dir[0], dir[1]).length()
		var dx: float = dir[0] / dl
		var dz: float = dir[1] / dl
		var rx := -dz
		var rz := dx
		var n := maxi(1, int(ceilf(l / 1.0)))
		var m := maxi(1, int(ceilf(w / 1.5)))
		var rows := []
		for i in n + 1:
			var lv := -l / 2 + l * i / n
			var row := []
			for j in m + 1:
				var lu := -w / 2 + w * j / m
				var x := cx + rx * lu + dx * lv
				var z := cz + rz * lu + dz * lv
				var uv := ST.uv_of(cell, lu / w + 0.5, lv / l + 0.5)
				row.append(B.vert(x, hf.call(x, z) + lift, z, uv[0], uv[1], UP, col))
			rows.append(row)
		for i in n:
			for j in m:
				B.quad(rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j])
	var r1_path := func(o: float, z0: float, z1: float, step: float = 1.0) -> Array:
		return range_of(z0, z1, step).map(func(zc): return r1.call(zc, o))
	var dashes := func(fn_pts: Callable, a: float, b: float, dash: float, gap: float, w: float, col) -> void:
		var s := a
		while s < b - 0.2:
			strip.call(lineB, fn_pts.call(s, minf(b, s + dash)), w, col)
			s += dash + gap
	var north_dir := func(zc: float) -> Array:
		return r1T.call(zc)
	var south_dir := func(zc: float) -> Array:
		var t: Array = r1T.call(zc)
		return [-t[0], -t[1]]
	var r1_glyph := func(cell: Dictionary, zc: float, o: float, w: float, l: float, dir_sign: float, col = null) -> void:
		var xz: Array = r1.call(zc, o)
		quad.call(glyphB, cell, xz[0], xz[1], w, l, north_dir.call(zc) if dir_sign < 0 else south_dir.call(zc), GLYPH_LIFT, col if col != null else C_WHITE)
	var r1_util := func(cell: Dictionary, zc: float, o: float, w: float, l: float, dir_sign: float = -1, lift: float = UTIL_LIFT, B = null) -> void:
		var xz: Array = r1.call(zc, o)
		quad.call(B if B != null else utilB, cell, xz[0], xz[1], w, l, north_dir.call(zc) if dir_sign < 0 else south_dir.call(zc), lift)

	# sidewalks (R1, both sides, z 1..60)
	var edges := []
	var gutters := []
	var push_edge_poly := func(pts: Array, kind: String, step: float = 3) -> void:
		var rs := SM.resample(pts, step)
		for i in range(1, rs.size()):
			edges.append({"a": [fx(rs[i - 1].x, 3), fx(rs[i - 1].z, 3)], "b": [fx(rs[i].x, 3), fx(rs[i].z, 3)], "kind": kind})
	var curbB := SM.MeshBuilder.new()
	var paverB := SM.MeshBuilder.new()
	var lgB := SM.MeshBuilder.new()
	var faceB := SM.MeshBuilder.new(true)
	var dotsB := SM.MeshBuilder.new()
	var barsB := SM.MeshBuilder.new()
	var SW_END := 60.0
	var ARC_R := 2.2
	var sidewalk_info := {}
	for s in [-1.0, 1.0]:
		var P := []
		for zc in cat([range_of(SW_END, 57.6, 0.3), range_of(57.6, 6, 1.0), range_of(6, 3.2, 0.4)]):
			var c: Array = r1.call(zc, s * 3.0)
			var ob: Array = r1.call(zc, s * 4.6)
			var nn: Array = r1N.call(zc)
			P.append({"cx": c[0], "cz": c[1], "ox": ob[0], "oz": ob[1], "nx": s * nn[0], "nz": s * nn[1], "part": 1, "zc": zc})
		var A := [s * 5.2, 3.2]
		var th0 := 0.0 if s < 0 else PI
		var dth := -PI / 2 if s < 0 else PI / 2
		for i in 13:
			var th := th0 + dth * i / 12
			var cx: float = A[0] + ARC_R * cos(th)
			var cz: float = A[1] + ARC_R * sin(th)
			var l := Vector2(A[0] - cx, A[1] - cz).length()
			P.append({"cx": cx, "cz": cz, "ox": s * 4.6, "oz": 2.45, "nx": (A[0] - cx) / l, "nz": (A[1] - cz) / l, "part": 2})
		for ax in range_of(5.2, 8.5, 0.4):
			P.append({"cx": s * ax, "cz": 1.0, "ox": s * ax, "oz": 2.45, "nx": 0.0, "nz": 1.0, "part": 3})
		var t := 0.0
		P[0]["t"] = 0.0
		for i in range(1, P.size()):
			t += Vector2(P[i].cx - P[i - 1].cx, P[i].cz - P[i - 1].cz).length()
			P[i]["t"] = t
		var t_end := t
		var arc := P.filter(func(p): return p.part == 2)
		var tA0: float = arc[0].t
		var tA1: float = arc[arc.size() - 1].t
		var E := func(tt: float) -> float:
			return smooth(0, 1.2, tt) * smooth(t_end, t_end - 1.0, tt)
		var dip := func(tt: float) -> float:
			return smooth(tA0 + 0.3, tA0 + 0.9, tt) * (1 - smooth(tA1 - 0.9, tA1 - 0.3, tt))
		var curb_h := func(tt: float, d: float) -> float:
			return maxf(0.012, CURB_H * E.call(tt) * (1 - 0.9 * dip.call(tt) * (1 - smooth(0.05, 1.05, d))))
		sidewalk_info[s] = {"P": P, "curbH": curb_h, "tA0": tA0, "tA1": tA1, "tEnd": t_end}
		var FR := [0, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0]
		var rows_curb := []
		var rows_pav := []
		var rows_lg := []
		for p in P:
			var ry: float = road_y.call(p.cx, p.cz)
			var h0: float = curb_h.call(p.t, 0)
			var h3: float = curb_h.call(p.t, 0.03)
			var h18: float = curb_h.call(p.t, 0.18)
			var face_top := ry + maxf(0.004, h0 - 0.02)
			var nF := [-p.nx, 0.0, -p.nz]
			var nC := [-p.nx / sqrt(2.0), 1 / sqrt(2.0), -p.nz / sqrt(2.0)]
			var u: float = p.t / 1.2
			var c3x: float = p.cx + p.nx * 0.03
			var c3z: float = p.cz + p.nz * 0.03
			var bx: float = p.cx + p.nx * 0.18
			var bz: float = p.cz + p.nz * 0.18
			rows_curb.append([
				curbB.vert(p.cx, ry - 0.015, p.cz, u, 0.0, nF), curbB.vert(p.cx, face_top, p.cz, u, 0.45, nF),
				curbB.vert(p.cx, face_top, p.cz, u, 0.45, nC), curbB.vert(c3x, road_y.call(c3x, c3z) + h3, c3z, u, 0.55, nC),
				curbB.vert(c3x, road_y.call(c3x, c3z) + h3, c3z, u, 0.55, UP), curbB.vert(bx, road_y.call(bx, bz) + h18, bz, u, 1.0, UP),
			])
			var pav := []
			var length := Vector2(p.ox - bx, p.oz - bz).length()
			for f in FR:
				var x: float = bx + (p.ox - bx) * f
				var z: float = bz + (p.oz - bz) * f
				var d: float = 0.18 + length * f
				pav.append(paverB.vert(x, road_y.call(x, z) + curb_h.call(p.t, d), z, x / 1.6, -z / 1.6, UP))
			rows_pav.append(pav)
			var gx: float = p.cx - p.nx * 0.28
			var gz: float = p.cz - p.nz * 0.28
			rows_lg.append([lgB.vert(p.cx, ry + 0.006, p.cz, p.t / 2, 1, UP), lgB.vert(gx, road_y.call(gx, gz) + 0.006, gz, p.t / 2, 0, UP)])
		for i in P.size() - 1:
			var a: Array = rows_curb[i]
			var b: Array = rows_curb[i + 1]
			var nF := [-P[i].nx, 0.0, -P[i].nz]
			curbB.quad(a[0], b[0], b[1], a[1], nF)
			curbB.quad(a[2], b[2], b[3], a[3], [-P[i].nx, 1.0, -P[i].nz])
			curbB.quad(a[4], b[4], b[5], a[5])
			for j in FR.size() - 1:
				paverB.quad(rows_pav[i][j], rows_pav[i + 1][j], rows_pav[i + 1][j + 1], rows_pav[i][j + 1])
			lgB.quad(rows_lg[i][0], rows_lg[i + 1][0], rows_lg[i + 1][1], rows_lg[i][1])
		var p3 := P.filter(func(p): return p.part == 3)
		for i in p3.size() - 1:
			var a: Dictionary = p3[i]
			var b: Dictionary = p3[i + 1]
			var ya: float = road_y.call(a.ox, a.oz) + curb_h.call(a.t, 2)
			var yb: float = road_y.call(b.ox, b.oz) + curb_h.call(b.t, 2)
			var NZ := [0.0, 0.0, 1.0]
			var v0 := faceB.vert(a.ox, H.call(a.ox, a.oz) - 0.03, a.oz, 0, 0, NZ)
			var v1 := faceB.vert(b.ox, H.call(b.ox, b.oz) - 0.03, b.oz, 0, 0, NZ)
			var v2 := faceB.vert(b.ox, yb, b.oz, 0, 0, NZ)
			var v3 := faceB.vert(a.ox, ya, a.oz, 0, 0, NZ)
			faceB.quad(v0, v1, v2, v3, NZ)
		var cbx0 := s * 4.6
		var cbx1 := s * 4.95
		var top: float = road_y.call(s * 4.8, 2.85) + CURB_H
		var cbx := (cbx0 + cbx1) / 2
		F.box(0.35, top - H.call(cbx, 2.85) + 0.05, 0.8, "#b2b0a8", [cbx, (top + H.call(cbx, 2.85) - 0.05) / 2, 2.85])
		quad.call(utilTopB, ST.UTIL.drain, cbx, 2.85, 0.3, 0.7, [0, -1], 0.003, null, func(_x, _z): return top)
		physics.addWalkBox(cbx, 2.85, 0.4, 0.85, 0, top)
		var band := []
		var tb0 := tA0 + 0.35
		var tb1 := tA1 - 0.35
		for p in P:
			if p.t >= tb0 - 0.2 and p.t <= tb1 + 0.2:
				band.append(p)
		var prev = null
		for p in band:
			var ax: float = p.cx + p.nx * 0.36
			var az: float = p.cz + p.nz * 0.36
			var bx: float = p.cx + p.nx * 0.66
			var bz: float = p.cz + p.nz * 0.66
			var a := dotsB.vert(ax, road_y.call(ax, az) + curb_h.call(p.t, 0.36) + 0.008, az, p.t / 0.3, 0, UP)
			var b := dotsB.vert(bx, road_y.call(bx, bz) + curb_h.call(p.t, 0.66) + 0.008, bz, p.t / 0.3, 1, UP)
			if prev:
				dotsB.quad(prev[0], prev[1], b, a)
			prev = [a, b]
		var guide := func(z0: float, z1: float) -> void:
			var prev_g = null
			for zc in range_of(z0, z1, 1.0):
				var A2: Array = r1.call(zc, s * 3.8)
				var B2: Array = r1.call(zc, s * 4.1)
				var y: float = road_y.call(A2[0], A2[1]) + CURB_H + 0.005
				var a := barsB.vert(A2[0], y, A2[1], 1.0 if s < 0 else 0.0, zc / 0.3, UP)
				var b := barsB.vert(B2[0], y, B2[1], 0.0 if s < 0 else 1.0, zc / 0.3, UP)
				if prev_g:
					barsB.quad(prev_g[0], prev_g[1], b, a)
				prev_g = [a, b]
		guide.call(4.5, 57.6)
		for zc in [4.2, 57.9]:
			var xz: Array = r1.call(zc, s * 3.95)
			quad.call(dotsB, {"x": 0, "y": 0, "w": 1024, "h": 1024}, xz[0], xz[1], 0.3, 0.3, north_dir.call(zc), CURB_H + 0.005, null, road_y)
		var za := 3.2
		while za < 58.8 - 0.01:
			var zb := minf(58.8, za + 3.0)
			var zm := (za + zb) / 2
			var xz: Array = r1.call(zm, s * 3.95)
			var dd: Array = south_dir.call(zm)
			var ya: float = road_y2.call(r1.call(za, s * 3.95)) + CURB_H
			var yb: float = road_y2.call(r1.call(zb, s * 3.95)) + CURB_H
			physics.addWalkRamp(xz[0], xz[1], 1.95, (zb - za) + 0.06, atan2(dd[0], dd[1]), ya, yb)
			za += 3.0
		var xz2: Array = r1.call(59.4, s * 3.95)
		var dd2: Array = south_dir.call(59.4)
		physics.addWalkRamp(xz2[0], xz2[1], 1.95, 1.2, atan2(dd2[0], dd2[1]), road_y2.call(r1.call(58.8, s * 3.95)) + CURB_H, road_y2.call(r1.call(60, s * 3.95)) + 0.01)
		physics.addWalkBox(s * 6.35, 1.72, 2.3, 1.45, 0, CURB_H + 0.02)
		physics.addWalkRamp(s * 8.0, 1.72, 1.45, 1.0, s * PI / 2, CURB_H + 0.02, 0.03)
		physics.addWalkBox(s * 4.1, 2.85, 0.9, 0.8, 0, CURB_H + 0.02)
		push_edge_poly.call(P.map(func(p): return [p.cx, p.cz]), "curb", 2.5)
	add.call(curbB, M.curb, {"cast": true, "name": "street-curbs"})
	add.call(paverB, M.pavers, {"name": "street-sidewalk"})
	add.call(lgB, M.lgutter, {"name": "street-lgutter"})
	add.call(dotsB, M.dots, {"name": "street-tactile-dots"})
	add.call(barsB, M.bars, {"name": "street-tactile-bars"})

	# gutters (U-ditches)
	var lidB := SM.MeshBuilder.new()
	var gFaceB := faceB
	var ditchB := Ditch.DitchBuilder.new()
	var grateB := SM.MeshBuilder.new()
	var top_r1 := func(sgn: float) -> Callable:
		return func(x: float, z: float) -> float:
			var zc: float = z + sgn * 4.75 * sX.call(z)
			return H.call(x, z) + LIFT + maxf(0.012, CURB_H * (1 - smooth(58.8, 60, zc)))
	var top_flat := func(x: float, z: float) -> float:
		return road_y.call(x, z) + 0.012
	var RUNS := []
	var never := func(_x = 0.0, _z = 0.0): return false
	var run := func(id: String, pts: Array, o: Dictionary = {}) -> void:
		RUNS.append({"id": id, "pts": pts, "w": o.get("w", 0.3), "top": o.get("top", top_flat), "open": o.get("open", never), "noGrate": o.get("noGrate", never), "every": o.get("every", [8, 14])})
	run.call("R1W", range_of(3.25, 130, 2).map(func(zc): return r1.call(zc, -4.75)), {"top": top_r1.call(-1), "open": func(_x, z): return in_r(z, 92.5, 95.5)})
	run.call("R1E", range_of(3.25, 130, 2).map(func(zc): return r1.call(zc, 4.75)), {"top": top_r1.call(1), "open": func(_x, z): return in_r(z, 104.5, 107.5)})
	run.call("R3S-W", [[-95, 1.13], [-8.6, 1.13]], {"open": func(x, _z = 0.0): return in_r(x, -61, -57.5), "noGrate": func(x, _z = 0.0): return absf(x + 78) < 0.6 or absf(x + 52) < 0.6 or absf(x + 26) < 0.6})
	run.call("R3S-E", [[8.6, 1.13], [95, 1.13]], {"open": func(x, _z = 0.0): return in_r(x, 39, 43), "noGrate": func(x, _z = 0.0): return absf(x - 22) < 0.6 or absf(x - 46) < 0.6 or absf(x - 72) < 0.6})
	run.call("R3N-W", [[-95, -5.15], [-17.35, -5.15]], {"open": func(x, _z = 0.0): return in_r(x, -45, -41)})
	run.call("R3N-E", [[26.2, -5.15], [95, -5.15]])
	run.call("R2W-S", [[-14.9, -7.6], [-14.9, -33.8]])
	run.call("R2W-N1", [[-14.9, -59.6], [-14.9, -67.9]], {"open": func(_x, z): return in_r(z, -66.2, -63.8)})
	run.call("R2W-N2", [[-14.9, -74.1], [-14.9, R2N + 0.25]])
	run.call("R2E-N1", [[-9.1, -59.6], [-9.1, -67.9]])
	run.call("R2E-N2", [[-9.1, -74.1], [-9.1, R2N + 0.25]])
	run.call("R4N-W", [[-95, -57.65], [-16.85, -57.65]], {"open": func(x, _z = 0.0): return in_r(x, -61, -57)})
	run.call("R4N-E", [[-7.15, -57.65], [95, -57.65]], {"open": func(x, _z = 0.0): return in_r(x, 23.5, 27.5)})
	run.call("R6N-W", [[-85, -72.65], [-16.35, -72.65]], {"open": func(x, _z = 0.0): return in_r(x, -52, -46)})
	run.call("R6N-E", [[-7.65, -72.65], [85, -72.65]], {"open": func(x, _z = 0.0): return in_r(x, 30, 42)})
	run.call("R6S-W", [[-85, -69.375], [-16.35, -69.375]], {"w": 0.25, "open": func(x, _z = 0.0): return in_r(x, -41, -38)})
	run.call("R6S-E", [[-7.65, -69.375], [85, -69.375]], {"w": 0.25})
	var RIM := 0.035
	var LIDLEN := 0.5
	var grate_spots := []
	for g in RUNS:
		var rs := SM.resample(g.pts, 1.0)
		var total: float = rs[rs.size() - 1].s
		var w: float = g.w
		var hw := w / 2
		var n_lid := maxi(1, int(floorf(total / LIDLEN)))
		var kind := []
		for k in n_lid:
			var p := SM.point_at(rs, (k + 0.5) * LIDLEN)
			kind.append("open" if g.open.call(p.x, p.z) else "lid")
		var rr = ctx.rng("gutter-" + g.id)
		var nxt: float = rr.range(2, 7)
		while nxt < total - 1:
			var k := int(floorf(nxt / LIDLEN))
			var p := SM.point_at(rs, (k + 0.5) * LIDLEN)
			if k > 0 and k < n_lid - 1 and kind[k] == "lid" and kind[k - 1] == "lid" and kind[k + 1] == "lid" and not g.noGrate.call(p.x, p.z):
				kind[k] = "grate"
			nxt += rr.range(g.every[0], g.every[1])
		var spans := []
		var k0 := 0
		for k in range(1, n_lid + 1):
			if k == n_lid or kind[k] != kind[k0]:
				spans.append({"kind": kind[k0], "s0": k0 * LIDLEN, "s1": k * LIDLEN})
				k0 = k
		var last: Dictionary = spans[spans.size() - 1]
		if last.kind == "lid":
			last.s1 = total
		else:
			spans.append({"kind": "lid", "s0": last.s1, "s1": total})
		var samples := func(s0: float, s1: float) -> Array:
			var o := [s0]
			for p in rs:
				if p.s > s0 + 0.05 and p.s < s1 - 0.05:
					o.append(p.s)
			o.append(s1)
			return o.map(func(s): return SM.point_at(rs, s))
		for sp in spans:
			if sp.s1 - sp.s0 < 0.02:
				continue
			var pts: Array = samples.call(sp.s0, sp.s1)
			var Ef := func(p: Dictionary, off: float) -> Array:
				var x: float = p.x - p.tz * off
				var z: float = p.z + p.tx * off
				return [x, z, g.top.call(x, z)]
			for side in [1.0, -1.0]:
				var prev = null
				for p in pts:
					var e: Array = Ef.call(p, side * hw)
					var N := [-p.tz * side, 0.0, p.tx * side]
					var a := gFaceB.vert(e[0], H.call(e[0], e[1]) - 0.035, e[1], 0, 0, N)
					var b := gFaceB.vert(e[0], e[2], e[1], 0, 0, N)
					if prev:
						gFaceB.quad(prev[0], a, b, prev[1], N)
					prev = [a, b]
			if sp.kind == "lid":
				var prev = null
				for p in pts:
					var ea: Array = Ef.call(p, hw)
					var eb: Array = Ef.call(p, -hw)
					var a := lidB.vert(ea[0], ea[2], ea[1], p.s / 1.0, 1, UP)
					var b := lidB.vert(eb[0], eb[2], eb[1], p.s / 1.0, 0, UP)
					if prev:
						lidB.quad(prev[0], prev[1], b, a)
					prev = [a, b]
				for i in range(0, pts.size() - 1, 3):
					var p: Dictionary = pts[i]
					var q: Dictionary = pts[mini(pts.size() - 1, i + 3)]
					gutters.append({"a": [fx(p.x, 2), fx(p.z, 2)], "b": [fx(q.x, 2), fx(q.z, 2)], "w": w, "water": false, "y": fx(g.top.call(p.x, p.z), 3)})
				continue
			var wi := hw - RIM
			for oo in [[hw, wi], [-wi, -hw]]:
				var prev = null
				for p in pts:
					var ea: Array = Ef.call(p, oo[0])
					var eb: Array = Ef.call(p, oo[1])
					var a := gFaceB.vert(ea[0], ea[2], ea[1], 0, 0, UP)
					var b := gFaceB.vert(eb[0], eb[2], eb[1], 0, 0, UP)
					if prev:
						gFaceB.quad(prev[0], prev[1], b, a)
					prev = [a, b]
			var wl := 0.19 if sp.kind == "open" else 0.21
			var dp := 0.002 if sp.kind == "open" else 0.012
			var span := [sp.s0, sp.s1, wi, wl]
			var prevd = null
			for p in pts:
				var n2 := [-p.tz, p.tx]
				var ea: Array = Ef.call(p, wi)
				var eb: Array = Ef.call(p, -wi)
				var a := ditchB.vert(ea[0], ea[2] - dp, ea[1], wi, p.s, dp, n2, span)
				var b := ditchB.vert(eb[0], eb[2] - dp, eb[1], -wi, p.s, dp, n2, span)
				if prevd:
					ditchB.quad(prevd[0], prevd[1], b, a)
				prevd = [a, b]
			if sp.kind == "grate":
				var prev = null
				for p in pts:
					var ea: Array = Ef.call(p, hw - 0.012)
					var eb: Array = Ef.call(p, -hw + 0.012)
					var u: float = (p.s - sp.s0) / LIDLEN
					var a := grateB.vert(ea[0], ea[2] - 0.004, ea[1], u, 1, UP)
					var b := grateB.vert(eb[0], eb[2] - 0.004, eb[1], u, 0, UP)
					if prev:
						grateB.quad(prev[0], prev[1], b, a)
					prev = [a, b]
			var pa: Dictionary = pts[0]
			var pb: Dictionary = pts[pts.size() - 1]
			var top_y: float = g.top.call(pa.x, pa.z)
			var wl_y := 0.19 if sp.kind == "open" else 0.21
			gutters.append({"a": [fx(pa.x, 2), fx(pa.z, 2)], "b": [fx(pb.x, 2), fx(pb.z, 2)], "w": w, "water": true, "open": sp.kind == "open", "grate": sp.kind == "grate", "y": fx(top_y, 3), "waterY": fx(top_y - wl_y, 3)})
			if sp.kind == "grate":
				var pm := SM.point_at(rs, (sp.s0 + sp.s1) / 2)
				grate_spots.append({"x": pm.x, "z": pm.z, "tx": pm.tx, "tz": pm.tz, "top": g.top, "id": g.id})
		push_edge_poly.call(g.pts, "gutter", 4)
	add.call(lidB, M.lid, {"name": "street-gutter-lids"})
	add.call(solid.call(gFaceB, "#b2b0a8"), VC, {"name": "street-gutter-faces"})
	if not ditchB.is_empty():
		root.add(ditchB.mesh(Ditch.ditch_material(ctx)))
	add.call(grateB, M.grate, {"name": "street-gratings", "noOutline": true})

	# line markings
	var W := C_WHITE
	strip.call(lineB, r1_path.call(-2.6, 3.65, 130), 0.15, W)
	strip.call(lineB, r1_path.call(2.6, 3.2, 130), 0.15, W)
	strip.call(lineB, r1_path.call(0, 3.2, 9), 0.15, W)
	dashes.call(func(a, b): return r1_path.call(0, a, b, 0.75), 12, 30, 3, 3, 0.15, W)
	strip.call(lineB, r1_path.call(0, 30, 90), 0.15, C_ORANGE)
	dashes.call(func(a, b): return r1_path.call(0, a, b, 0.75), 93, 130, 3, 3, 0.15, W)
	strip.call(lineB, [r1.call(3.45, -2.6), r1.call(3.45, -0.08)], 0.4, W)
	strip.call(paintB, r1_path.call(-3.615, 63, 101), 1.85, C_GREEN, 0.005, road_y, 2.0)
	strip.call(paintB, r1_path.call(3.615, 65, 85.2), 1.85, C_GREEN, 0.005, road_y, 2.0)
	strip.call(paintB, r1_path.call(3.615, 87.4, 99), 1.85, C_GREEN, 0.005, road_y, 2.0)
	strip.call(lineB, [[-95, -4.72], [-17.4, -4.72]], 0.15, W); strip.call(lineB, [[-9.15, -4.72], [-2.45, -4.72]], 0.15, W); strip.call(lineB, [[2.45, -4.72], [95, -4.72]], 0.15, W)
	strip.call(lineB, [[-95, 0.72], [-8.75, 0.72]], 0.15, W); strip.call(lineB, [[8.75, 0.72], [95, 0.72]], 0.15, W)
	dashes.call(func(a, b): return [[a, -2], [b, -2]], 6, 95, 3, 3, 0.15, W)
	dashes.call(func(a, b): return [[-a, -2], [-b, -2]], 18, 95, 3, 3, 0.15, W)
	for i in 7:
		strip.call(lineB, [[-2.0, -4.7 + i * 0.9], [2.0, -4.7 + i * 0.9]], 0.45, W)
	for zz in [[-33.9, -7.6], [-67.9, -59.6], [R2N + 0.3, -74.1]]:
		strip.call(lineB, [[-14.47, zz[0]], [-14.47, zz[1]]], 0.15, W)
	for zz in [[-33.9, -5.35], [-67.9, -59.6], [R2N + 0.3, -74.1]]:
		strip.call(lineB, [[-9.53, zz[0]], [-9.53, zz[1]]], 0.15, W)
	strip.call(lineB, [[-12.0, -6.3], [-9.6, -6.3]], 0.4, W)
	strip.call(lineB, [[-95, -57.22], [-16.85, -57.22]], 0.15, W); strip.call(lineB, [[-7.15, -57.22], [95, -57.22]], 0.15, W)
	strip.call(lineB, [[-95, -53.78], [-16.0, -53.78]], 0.15, W); strip.call(lineB, [[-8.0, -53.78], [95, -53.78]], 0.15, W)
	strip.call(lineB, [[-6.95, -55.45], [-6.95, -53.86]], 0.4, W); strip.call(lineB, [[-17.05, -57.14], [-17.05, -55.55]], 0.4, W)
	strip.call(lineB, [[-85, -72.25], [-16.35, -72.25]], 0.13, W); strip.call(lineB, [[-7.65, -72.25], [85, -72.25]], 0.13, W)
	strip.call(lineB, [[-85, -69.75], [-16.35, -69.75]], 0.13, W); strip.call(lineB, [[-7.65, -69.75], [85, -69.75]], 0.13, W)
	strip.call(lineB, [[-7.4, -72.2], [-7.4, -69.8]], 0.35, W); strip.call(lineB, [[-16.6, -72.2], [-16.6, -69.8]], 0.35, W)
	add.call(paintB, M.paint, {"name": "street-paint", "renderOrder": -3, "noOutline": true})
	add.call(lineB, M.line, {"name": "street-lines", "renderOrder": -2, "noOutline": true})

	# road text and symbols
	var G: Dictionary = ST.GLYPH
	r1_glyph.call(G.tomare, 7.55, -1.3, 1.35, 7.2, -1)
	r1_glyph.call(G.diamond, 22, -1.3, 1.25, 3.0, -1); r1_glyph.call(G.diamond, 40, -1.3, 1.25, 3.0, -1)
	r1_glyph.call(G.jokou, 15.5, 1.3, 1.3, 4.6, 1)
	r1_glyph.call(G.n30, 55.5, -1.3, 1.2, 2.9, -1); r1_glyph.call(G.n30, 70.5, 1.3, 1.2, 2.9, 1)
	r1_glyph.call(G.school, 86, -1.3, 2.2, 3.6, -1); r1_glyph.call(G.school, 77.5, 1.3, 2.2, 3.6, 1)
	r1_glyph.call(G.hokou, 74.5, -1.3, 2.2, 3.6, -1); r1_glyph.call(G.hokou, 89, 1.3, 2.2, 3.6, 1)
	for zc in [18.5, 47, 104, 117]:
		r1_glyph.call(G.navi, zc, -2.2, 0.62, 1.6, -1)
	for zc in [26, 52, 97, 121]:
		r1_glyph.call(G.navi, zc, 2.2, 0.62, 1.6, 1)
	for zc in [67, 85]:
		r1_glyph.call(G.tsugaku, zc, -3.62, 1.05, 3.2, -1)
	for zc in [73, 91]:
		r1_glyph.call(G.kids, zc, -3.62, 1.2, 1.5, -1)
	for zc in [70, 94]:
		r1_glyph.call(G.tsugaku, zc, 3.62, 1.05, 3.2, 1)
	for zc in [76, 81]:
		r1_glyph.call(G.kids, zc, 3.62, 1.2, 1.5, 1)
	quad.call(glyphB, G.jokou, 16.5, -0.7, 1.3, 4.6, [-1, 0], GLYPH_LIFT, W)
	quad.call(glyphB, G.jokou, -24.5, -3.3, 1.3, 4.6, [1, 0], GLYPH_LIFT, W)
	for x in [32, 52]:
		quad.call(glyphB, G.diamond, x, -0.7, 1.25, 3.0, [-1, 0], GLYPH_LIFT, W)
	for x in [-32, -52]:
		quad.call(glyphB, G.diamond, x, -3.3, 1.25, 3.0, [1, 0], GLYPH_LIFT, W)
	for x in [28, 64]:
		quad.call(glyphB, G.navi, x, 0.25, 0.62, 1.6, [-1, 0], GLYPH_LIFT, W)
	for x in [-40, -70]:
		quad.call(glyphB, G.navi, x, -4.25, 0.62, 1.6, [1, 0], GLYPH_LIFT, W)
	quad.call(glyphB, G.bus, 9.8, -3.9, 0.9, 2.4, [1, 0], GLYPH_LIFT, C_YELLOW)
	quad.call(glyphB, G.tomare, -10.75, -9.9, 1.2, 6.0, [0, 1], GLYPH_LIFT, W)
	quad.call(glyphB, G.tomare, -3.7, -54.62, 1.1, 5.6, [-1, 0], GLYPH_LIFT, W)
	quad.call(glyphB, G.tomare, -20.3, -56.38, 1.1, 5.6, [1, 0], GLYPH_LIFT, W)
	quad.call(glyphB, G.tomare, -4.2, -71, 1.3, 5.4, [-1, 0], GLYPH_LIFT, W)
	quad.call(glyphB, G.tomare, -19.8, -71, 1.3, 5.4, [1, 0], GLYPH_LIFT, W)
	quad.call(glyphB, G.bike, -35, 0.2, 0.95, 0.95, [-1, 0], GLYPH_LIFT, W)
	quad.call(glyphB, G.bike, 58, -4.2, 0.95, 0.95, [1, 0], GLYPH_LIFT, W)
	var rl = ctx.rng("street-litter")
	var ONE := [1.0, 1.0, 1.0]
	for gs in grate_spots:
		if not rl.chance(0.55):
			continue
		var k: float = rl.range(-0.12, 0.12)
		var gtop: float = gs.top.call(gs.x, gs.z) + 0.006
		var flat_top := func(_x, _z): return gtop
		quad.call(glyphB, G.litter, gs.x + gs.tx * k, gs.z + gs.tz * k, 0.42, 0.46, [gs.tx * (1.0 if rl.chance(0.5) else -1.0), gs.tz], 0, ONE, flat_top)
		if rl.chance(0.6):
			var d: float = rl.pick([-0.55, 0.55])
			quad.call(glyphB, G.litter, gs.x + gs.tx * d, gs.z + gs.tz * d, 0.36, 0.4, [-gs.tz, gs.tx], 0, ONE, flat_top)
	add.call(glyphB, M.glyph, {"name": "street-glyphs", "renderOrder": -1, "noOutline": true})

	# utility decals (manholes, lids, patches, stains, sprays)
	var U: Dictionary = ST.UTIL
	r1_util.call(U.patchA, 17.5, -1.2, 1.8, 2.6); r1_util.call(U.patchB, 45, 1.6, 1.2, 1.6); r1_util.call(U.patchC, 36.5, -1.0, 1.4, 1.4)
	r1_util.call(U.patchC, 112, 0.9, 2.2, 2.2); r1_util.call(U.trench, 96.5, -1.8, 0.55, 8.0)
	var t58: Array = r1.call(58, 0)
	quad.call(utilB, U.trench, t58[0], t58[1], 0.6, 5.8, r1N.call(58), UTIL_LIFT)
	quad.call(utilB, U.patchA, -30, -3.1, 2.0, 3.0, [1, 0], UTIL_LIFT); quad.call(utilB, U.trench, 48, -2, 0.6, 5.8, [0, 1], UTIL_LIFT); quad.call(utilB, U.patchB, 12, -0.6, 1.4, 1.8, [1, 0], UTIL_LIFT)
	quad.call(utilB, U.fresh, 35, 0.1, 1.3, 2.6, [1, 0], UTIL_LIFT)
	quad.call(utilB, U.patchA, -11.2, -16, 1.6, 2.2, [0, 1], UTIL_LIFT); quad.call(utilB, U.trench, -12, -22, 0.6, 5.3, [1, 0], UTIL_LIFT); quad.call(utilB, U.patchC, -12.6, -63, 1.5, 1.5, [0, 1], UTIL_LIFT)
	quad.call(utilB, U.patchB, -30, -55.9, 1.5, 2.2, [1, 0], UTIL_LIFT); quad.call(utilB, U.patchA, 40, -55.0, 2.0, 2.5, [1, 0], UTIL_LIFT); quad.call(utilB, U.trench, 12, -55.5, 0.6, 3.8, [0, 1], UTIL_LIFT)
	quad.call(utilB, U.patchA, 22, -71.2, 1.4, 2.0, [1, 0], UTIL_LIFT); quad.call(utilB, U.patchC, -40, -70.6, 1.2, 1.2, [1, 0], UTIL_LIFT)
	r1_util.call(U.seal, 64, -0.4, 0.8, 4.0); r1_util.call(U.seal, 20.5, 1.2, 0.7, 3.2)
	quad.call(utilB, U.seal, -60, -2.8, 0.8, 4.0, [1, 0.2], UTIL_LIFT); quad.call(utilB, U.seal, 58, -0.9, 0.8, 4.0, [1, -0.1], UTIL_LIFT)
	quad.call(utilB, U.seal, -70, -55.2, 0.7, 3.6, [1, 0.1], UTIL_LIFT); quad.call(utilB, U.seal, 48, -71, 0.6, 3.0, [1, 0], UTIL_LIFT)
	r1_util.call(U.oilA, 12.4, -1.3, 0.9, 0.9); r1_util.call(U.oilB, 14.3, -1.4, 0.7, 0.7); r1_util.call(U.oilB, 72.5, -3.9, 1.0, 1.2); r1_util.call(U.oilA, 33, 1.4, 0.6, 0.6)
	quad.call(utilB, U.oilA, -6.0, -3.5, 1.0, 1.0, [1, 0], UTIL_LIFT); quad.call(utilB, U.oilB, 22.3, -0.25, 0.9, 0.9, [1, 0], UTIL_LIFT); quad.call(utilB, U.oilA, -10.6, -54.2, 0.8, 0.8, [0, 1], UTIL_LIFT)
	for zo in [[9, -2.75], [24, 2.75], [41, -2.75], [53, 2.75], [80, -2.9], [110, 2.9]]:
		r1_util.call(U.stain, zo[0], zo[1], 0.8, 2.2, -1)
	for xz in [[-50, 0.6], [30, -4.6], [70, 0.6], [-80, -4.6]]:
		quad.call(utilB, U.stain, xz[0], xz[1], 0.8, 2.4, [1, 0], UTIL_LIFT)
	r1_util.call(U.skid, 16.5, -1.3, 0.9, 2.8); quad.call(utilB, U.skid, -20, -3.3, 0.9, 2.8, [1, 0], UTIL_LIFT)
	for f in FILLETS:
		if f.get("r1", false):
			continue
		var C: Array = fillet_arc.call(f).C
		var dx: float = f.K[0] - C[0]
		var dz: float = f.K[1] - C[1]
		var l := Vector2(dx, dz).length()
		var px: float = C[0] + dx / l * (f.r + 0.25)
		var pz: float = C[1] + dz / l * (f.r + 0.25)
		quad.call(utilB, U.wet, px + dx / l * 0.2, pz + dz / l * 0.2, 1.3, 0.7, [-dz, dx], UTIL_LIFT)
		quad.call(utilB, U.drain, px, pz, 0.42, 0.42, f.e1, UTIL_LIFT + 0.001)
	r1_util.call(U.sprayA, 108.8, 2.2, 0.9, 0.9, 1); r1_util.call(U.sprayC, 107.2, 3.3, 1.0, 1.0, 1); r1_util.call(U.sprayB, 50.5, -2.0, 0.8, 0.8)
	quad.call(utilB, U.sprayA, 32.9, 0.3, 0.9, 0.9, [-1, 0], UTIL_LIFT); quad.call(utilB, U.sprayB, 37.6, -0.6, 0.9, 0.9, [-1, 0], UTIL_LIFT); quad.call(utilB, U.sprayC, 35, -1.35, 0.8, 0.8, [-1, 0], UTIL_LIFT)
	quad.call(utilB, U.sprayB, -44, -54.2, 0.8, 0.8, [1, 0], UTIL_LIFT); quad.call(utilB, U.sprayA, -58, -70.4, 0.8, 0.8, [1, 0], UTIL_LIFT)
	r1_util.call(U.fresh, 108, 3.4, 1.0, 1.9, 1)
	var MH := 0.66
	r1_util.call(U.manholeA, 28.6, -0.6, MH, MH)
	for zo in [[15.5, 0.6], [47, 0.6], [79, -0.6], [109.5, 0.6]]:
		r1_util.call(U.manholeB, zo[0], zo[1], MH, MH)
	r1_util.call(U.manholeC, 36, -1.9, 0.6, 0.6); r1_util.call(U.manholeC, 62, 2.0, 0.6, 0.6)
	quad.call(utilB, U.manholeA, 10.5, -1.4, MH, MH, [1, 0], UTIL_LIFT)
	for xz in [[-43.5, -1.4], [40, -2.6], [70, -1.4]]:
		quad.call(utilB, U.manholeB, xz[0], xz[1], MH, MH, [1, 0], UTIL_LIFT)
	for xz in [[-70, -2.6], [-24, -1.3]]:
		quad.call(utilB, U.manholeC, xz[0], xz[1], 0.6, 0.6, [1, 0], UTIL_LIFT)
	quad.call(utilB, U.manholeB, -12.6, -20, MH, MH, [0, -1], UTIL_LIFT); quad.call(utilB, U.manholeC, -11.4, -64, 0.6, 0.6, [0, -1], UTIL_LIFT); quad.call(utilB, U.manholeA, -12.5, -78, MH, MH, [0, -1], UTIL_LIFT)
	quad.call(utilB, U.manholeB, -40, -55.1, MH, MH, [1, 0], UTIL_LIFT); quad.call(utilB, U.manholeA, 30, -55.8, MH, MH, [1, 0], UTIL_LIFT); quad.call(utilB, U.manholeC, 60, -55.2, 0.6, 0.6, [1, 0], UTIL_LIFT)
	quad.call(utilB, U.manholeA, 20, -71, MH, MH, [1, 0], UTIL_LIFT); quad.call(utilB, U.manholeB, -45, -71, MH, MH, [1, 0], UTIL_LIFT); quad.call(utilB, U.manholeC, 55, -71, 0.6, 0.6, [1, 0], UTIL_LIFT)
	for zo in [[19, 2.2], [52, -2.0], [88, 1.9]]:
		r1_util.call(U.valveR, zo[0], zo[1], 0.3, 0.3)
	for zo in [[33.5, -2.2], [100, 2.3]]:
		r1_util.call(U.valveS, zo[0], zo[1], 0.32, 0.32)
	for zo in [[24.5, -2.35], [57, 2.2]]:
		r1_util.call(U.gas, zo[0], zo[1], 0.24, 0.24)
	quad.call(utilB, U.valveR, -24, 0.2, 0.3, 0.3, [1, 0], UTIL_LIFT); quad.call(utilB, U.valveR, 28, -4.2, 0.3, 0.3, [1, 0], UTIL_LIFT); quad.call(utilB, U.valveR, -10.3, -26, 0.3, 0.3, [0, 1], UTIL_LIFT); quad.call(utilB, U.valveR, -30, -71.8, 0.3, 0.3, [1, 0], UTIL_LIFT)
	quad.call(utilB, U.valveS, 18.4, 0.1, 0.32, 0.32, [1, 0], UTIL_LIFT); quad.call(utilB, U.valveS, 0, -56.9, 0.32, 0.32, [1, 0], UTIL_LIFT); quad.call(utilB, U.valveS, 60, -70.3, 0.32, 0.32, [1, 0], UTIL_LIFT)
	quad.call(utilB, U.gas, -52, 0.3, 0.24, 0.24, [1, 0], UTIL_LIFT); quad.call(utilB, U.gas, -13.8, -70.2, 0.24, 0.24, [1, 0], UTIL_LIFT); quad.call(utilB, U.gas, -62, -70.1, 0.24, 0.24, [1, 0], UTIL_LIFT)
	r1_util.call(U.hydrant, 86.3, 3.55, 1.05, 1.6, 1)
	quad.call(utilB, U.hydrant, 44.0, -4.0, 0.95, 1.45, [0, 1], UTIL_LIFT)
	quad.call(utilB, U.hydrant, -13.75, -29.5, 0.9, 1.35, [0, 1], UTIL_LIFT)
	add.call(utilB, M.util, {"name": "street-util-decals", "renderOrder": -3, "noOutline": true})
	for zs in [[6.5, -1], [6.5, 1], [21, -1], [29, 1], [36, -1], [44, 1], [50, -1], [50.5, 1]]:
		r1_util.call(U.drain, zs[0], zs[1] * 2.86, 0.25, 0.5, -1, 0.009, utilTopB)
	add.call(utilTopB, M.util, {"name": "street-util-top", "renderOrder": -1, "noOutline": true})

	# sign posts, mirrors, guardrails, cones
	var S: Dictionary = ST.SIGN
	var sw_top := func(x: float, z: float) -> float:
		return road_y.call(x, z) + CURB_H
	var sh_top := func(x: float, z: float) -> float:
		return road_y.call(x, z) - 0.01
	var face_s := func(zc: float) -> float:
		var d: Array = south_dir.call(zc)
		return atan2(d[0], d[1])
	var face_n := func(zc: float) -> float:
		var d: Array = north_dir.call(zc)
		return atan2(d[0], d[1])
	var disc := func(cell: Dictionary, y: float, r: float = 0.3, extra: Dictionary = {}) -> Dictionary:
		var o := {"kind": "circle", "cell": cell, "size": [r], "y": y}
		o.merge(extra, true)
		return o
	var rect := func(cell: Dictionary, y: float, w: float, h: float, extra: Dictionary = {}) -> Dictionary:
		var o := {"kind": "rect", "cell": cell, "size": [w, h], "y": y}
		o.merge(extra, true)
		return o
	F.sign_post(-3.38, 4.3, sw_top.call(-3.38, 4.3), 2.55, 0, [{"kind": "tri", "cell": S.stop, "size": [0.8], "y": 2.2, "clamps": [0.08, -0.12]}, rect.call(S.pPriority, 1.72, 0.52, 0.18)])
	F.sign_post(-6.7, 1.45, sw_top.call(-6.7, 1.45), 2.75, -PI / 2, [rect.call(S.cross, 2.42, 0.6, 0.6, {"double": true, "clamps": [0.14, -0.14]})])
	F.sign_post(6.7, 1.45, sw_top.call(6.7, 1.45), 2.75, PI / 2, [rect.call(S.cross, 2.42, 0.6, 0.6, {"double": true, "clamps": [0.14, -0.14]})])
	F.curve_mirror(-4.85, 1.42, -0.36, null, [], sw_top.call(-4.85, 1.42))
	F.curve_mirror(4.85, 1.42, 0.25, null, [], sw_top.call(4.85, 1.42))
	var gx := -3.32
	var gz := 19.2
	var gbase: float = sw_top.call(gx, gz)
	var gtop_h := 3.55
	F.sign_post(gx, gz, gbase, gtop_h, 0, [])
	var pw := 1.2
	var ph := 0.9
	var pcx := gx - 0.02 - pw / 2
	var pcy := gbase + 2.98
	F.add_plate(F.plate_geo("rect", S.guide, [pw, ph]), pcx, pcy, gz + 0.055, 0)
	var bx1 := pcx - pw / 2 + 0.12
	for dy in [-0.28, 0.28]:
		F.box(gx - bx1, 0.04, 0.03, Furniture.COL.steel, [(gx + bx1) / 2, pcy + dy, gz + 0.03])
	var post_at := func(zc: float, o: float) -> Array:
		return r1.call(zc, o)
	var p1: Array = post_at.call(28.8, -3.35)
	F.sign_post(p1[0], p1[1], sw_top.call(p1[0], p1[1]), 2.6, face_s.call(28.8), [disc.call(S.noPark, 2.25), rect.call(S.p820, 1.8, 0.5, 0.19)])
	p1 = post_at.call(44.5, 3.35)
	F.sign_post(p1[0], p1[1], sw_top.call(p1[0], p1[1]), 2.6, face_n.call(44.5), [disc.call(S.noPark, 2.25)])
	p1 = post_at.call(60.8, -4.3)
	F.sign_post(p1[0], p1[1], sh_top.call(p1[0], p1[1]), 2.75, face_s.call(60.8), [disc.call(S.n30, 2.4)])
	p1 = post_at.call(64.2, 4.3)
	F.sign_post(p1[0], p1[1], sh_top.call(p1[0], p1[1]), 2.75, face_n.call(64.2), [disc.call(S.n30, 2.4)])
	p1 = post_at.call(66.5, -4.3)
	F.sign_post(p1[0], p1[1], sh_top.call(p1[0], p1[1]), 2.9, face_s.call(66.5), [{"kind": "diamond", "cell": S.school, "size": [0.4], "y": 2.45, "clamps": [0.12, -0.12]}, rect.call(S.pTsugaku, 1.85, 0.5, 0.19)])
	p1 = post_at.call(91, 4.3)
	F.sign_post(p1[0], p1[1], sh_top.call(p1[0], p1[1]), 2.9, face_n.call(91), [{"kind": "diamond", "cell": S.school, "size": [0.4], "y": 2.45, "clamps": [0.12, -0.12]}, rect.call(S.pSchool, 1.85, 0.56, 0.21)])
	p1 = post_at.call(101, 4.3)
	F.sign_post(p1[0], p1[1], sh_top.call(p1[0], p1[1]), 2.6, face_n.call(101), [disc.call(S.noPark, 2.25), rect.call(S.p820, 1.8, 0.5, 0.19)])
	p1 = post_at.call(87.3, 4.42)
	F.sign_post(p1[0], p1[1], sh_top.call(p1[0], p1[1]), 2.3, face_n.call(87.3) + 0.5, [rect.call(S.hydrant, 1.95, 0.3, 0.6, {"clamps": [0.2, -0.2]})], {"r": 0.025})
	F.sign_post(44.8, -5.5, H.call(44.8, -5.5), 2.3, 0, [rect.call(S.hydrant, 1.95, 0.3, 0.6, {"clamps": [0.2, -0.2]})], {"r": 0.025})
	F.curve_mirror(-12.0, 1.62, PI, [{"yaw": 0.5, "dx": -0.42}, {"yaw": -0.5, "dx": 0.42}])
	F.curve_mirror(-15.4, -58.15, PI / 4, [{"yaw": 0.0}], [{"kind": "rect", "cell": S.pStop, "size": [0.5, 0.25], "y": 1.35, "rotY": -PI * 3 / 4}])
	F.curve_mirror(-8.6, -52.95, -PI * 3 / 4, [{"yaw": 0.0}], [{"kind": "rect", "cell": S.pStop, "size": [0.5, 0.25], "y": 1.35, "rotY": PI * 5 / 4}])
	F.curve_mirror(-8.62, -73.12, -PI / 4)
	F.curve_mirror(-15.38, -68.88, PI * 3 / 4)
	F.sign_post(-8.6, -68.85, H.call(-8.6, -68.85), 2.5, PI / 2, [{"kind": "tri", "cell": S.stop, "size": [0.75], "y": 2.15, "clamps": [0.08, -0.12]}])
	F.sign_post(-15.4, -73.15, H.call(-15.4, -73.15), 2.5, -PI / 2, [{"kind": "tri", "cell": S.stop, "size": [0.75], "y": 2.15, "clamps": [0.08, -0.12]}])
	F.guardrail([-57, -53.3], [-35, -53.3], -1)
	F.guardrail([54, -53.3], [76, -53.3], -1)
	var sx0: float = r2_stair.x - r2_stair.w / 2 if r2_stair else -13.7
	var sx1: float = r2_stair.x + r2_stair.w / 2 if r2_stair else -10.3
	var zg := R2N - 0.15
	F.guardrail([-16.6, zg], [sx0 - 0.26, zg], 1)
	F.guardrail([sx1 + 0.26, zg], [-7.4, zg], 1)
	F.cone(33.4, 0.45, road_y.call(33.4, 0.45)); F.cone(36.6, 0.45, road_y.call(36.6, 0.45)); F.cone_bar([33.4, 0.45], [36.6, 0.45], road_y.call(35, 0.45) + 0.55)
	p1 = post_at.call(106.3, 3.45)
	F.cone(p1[0], p1[1], sh_top.call(p1[0], p1[1]) + 0.01)

	# services
	for s in [-1, 1]:
		for lot in L.LOTS.filter(func(l): return l.side == s):
			push_edge_poly.call(range_of(lot.z0, lot.z1, 2).map(func(zc): return r1.call(zc, s * L.STREET.lotOffset)), "wall", 2.5)
	var edge_line := func(pts: Array) -> void:
		push_edge_poly.call(pts, "edge", 4)
	edge_line.call([[-95, 1], [-5.2, 1]]); edge_line.call([[5.2, 1], [95, 1]]); edge_line.call([[-95, -5], [-17.25, -5]]); edge_line.call([[26, -5], [95, -5]])
	edge_line.call([[-14.75, -7.5], [-14.75, -34]]); edge_line.call([[-9.25, -5], [-9.25, -34]])
	for x in [-14.75, -9.25]:
		edge_line.call([[x, -59.5], [x, -68]])
		edge_line.call([[x, -74], [x, R2N]])
	for z in [-57.5, -53.5]:
		edge_line.call([[-95, z], [-16.75, z]])
		edge_line.call([[-7.25, z], [95, z]])
	for z in [-72.5, -69.5]:
		edge_line.call([[-85, z], [-16.25, z]])
		edge_line.call([[-7.75, z], [85, z]])
	edge_line.call(r1_path.call(-4.6, 60, 130, 2))
	edge_line.call(r1_path.call(4.6, 60, 130, 2))
	for f in FILLETS:
		push_edge_poly.call(fillet_arc.call(f, 6).pts, "curb" if f.get("r1", false) else "edge", 1.5)
	ctx.services["street"] = {"edges": edges, "gutters": gutters}
