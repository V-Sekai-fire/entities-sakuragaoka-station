# station/building.js: the building shell (plinth, two-skin walls with openings, windows, entrance
# storefront, canopy and name board, gable roof with seams, gutters and downpipes, the entrance
# cross-gable with its clock, exterior details) and the forecourt (terrace, stairs, switch-back ramp).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")

const B := {
	"FY": 1.25, "CEIL": 4.25, "WT": 4.55, "X0": -4.0, "X1": 12.0, "Z0": -35.5, "Z1": -25.0,
	"RIDGE_Z": -30.25, "PITCH": 0.36397023426620234, "ROOF_T": 0.18, "ROOF_BASE": 4.75,
	"GX0": 1.0, "GX1": 7.0, "GPITCH": 0.5773502691896257,
}


## top surface height of the main roof at z
static func roof_top(z: float) -> float:
	return B.ROOF_BASE + (5.25 - absf(z - B.RIDGE_Z)) * B.PITCH


static func build_building(A) -> void:
	var ctx = A.ctx
	var k = A.k
	var U = A.U
	var M: Dictionary = A.M
	var P = A.P
	var root = A.root
	var FY: float = B.FY
	var WT: float = B.WT
	var X0: float = B.X0
	var X1: float = B.X1
	var Z0: float = B.Z0
	var Z1: float = B.Z1
	var r: Rng = ctx.rng("station-building")
	# ------------------------------------------------------------ plinth & floor
	var plinth = k.box(X1 - X0, FY - 0.01 + 0.4, Z1 - Z0, M.plinth, [(X0 + X1) / 2.0, (FY - 0.01 - 0.4) / 2.0, (Z0 + Z1) / 2.0])
	plinth.name = "plinth"
	k.box(X1 - X0 + 0.1, 0.1, 0.06, M.band, [(X0 + X1) / 2.0, FY - 0.02, Z1 + 0.03])
	k.box(0.06, 0.1, Z1 - Z0 + 0.06, M.band, [X1 + 0.03, FY - 0.02, (Z0 + Z1) / 2.0 + 0.03])
	k.box(0.06, 0.1, Z1 - Z0 + 0.06, M.band, [X0 - 0.03, FY - 0.02, (Z0 + Z1) / 2.0 + 0.03])
	k.box(X1 - X0 - 0.3, 0.012, Z1 - Z0 - 0.3, M.floor, [(X0 + X1) / 2.0, FY - 0.006, (Z0 + Z1) / 2.0])
	P.addWalkBox((X0 + X1) / 2.0, (Z0 + Z1) / 2.0, X1 - X0, Z1 - Z0, 0, FY)
	# ------------------------------------------------------------ walls
	var tO := 0.12
	var tI := 0.08
	var y0 := FY - 0.01
	var S := [
		{"a0": -3.3, "a1": -1.9, "y0": 2.2, "y1": 3.55}, {"a0": -1.2, "a1": 0.2, "y0": 2.2, "y1": 3.55},
		{"a0": 1.4, "a1": 6.6, "y0": FY - 0.02, "y1": 3.65},
		{"a0": 7.8, "a1": 9.4, "y0": 2.2, "y1": 3.55}, {"a0": 10.0, "a1": 11.6, "y0": 2.2, "y1": 3.55},
	]
	var N := [
		{"a0": -2.9, "a1": -0.9, "y0": 2.2, "y1": 3.5}, {"a0": 1.3, "a1": 3.3, "y0": 2.2, "y1": 3.5},
		{"a0": 3.9, "a1": 4.8, "y0": FY - 0.02, "y1": 3.25}, {"a0": 5.6, "a1": 11.6, "y0": FY - 0.02, "y1": 3.65},
	]
	var E := [{"a0": -34.2, "a1": -32.6, "y0": 2.2, "y1": 3.55}, {"a0": -27.6, "a1": -26.0, "y0": 2.2, "y1": 3.55}]
	var W := [{"a0": -33.6, "a1": -32.2, "y0": 2.2, "y1": 3.55}, {"a0": -28.3, "a1": -26.9, "y0": 2.2, "y1": 3.55}]
	var pt := 3.0
	U.wall(k, M.plasterExt, "x", Z1 - tO, Z1, X0, X1, y0, WT, S, pt)
	U.wall(k, M.plasterInt, "x", Z1 - tO - tI, Z1 - tO, X0 + tO, X1 - tO, y0, WT - 0.2, S, pt)
	U.wall(k, M.plasterExt, "x", Z0, Z0 + tO, X0, X1, y0, WT, N, pt)
	U.wall(k, M.plasterInt, "x", Z0 + tO, Z0 + tO + tI, X0 + tO, X1 - tO, y0, WT - 0.2, N, pt)
	U.wall(k, M.plasterExt, "z", X1 - tO, X1, Z0, Z1, y0, WT, E, pt)
	U.wall(k, M.plasterInt, "z", X1 - tO - tI, X1 - tO, Z0 + tO, Z1 - tO, y0, WT - 0.2, E, pt)
	U.wall(k, M.plasterExt, "z", X0, X0 + tO, Z0, Z1, y0, WT, W, pt)
	U.wall(k, M.plasterInt, "z", X0 + tO, X0 + tO + tI, Z0 + tO, Z1 - tO, y0, WT - 0.2, W, pt)
	for c in [[X0, Z1 - 0.2, 1.4, Z1], [6.6, Z1 - 0.2, X1, Z1], [X0, Z0, 5.6, Z0 + 0.2], [11.6, Z0, X1, Z0 + 0.2],
			[X1 - 0.2, Z0, X1, Z1], [X0, Z0, X0 + 0.2, Z1], [1.4, Z1 - 0.2, 2.78, Z1], [5.22, Z1 - 0.2, 6.6, Z1]]:
		P.addAABB(c[0], c[1], c[2], c[3], -1, 6)
	for c in [[X0, Z1], [X1, Z1], [X0, Z0], [X1, Z0]]:
		k.box(0.3, WT - y0, 0.3, M.band, [c[0] + (0.13 if c[0] < 4.0 else -0.13), (WT + y0) / 2.0, c[1] + (-0.13 if c[1] > -30.0 else 0.13)])
	k.box(6.2, 0.14, 0.18, M.band, [8.6, 3.72, Z0 - 0.02])
	k.box(0.22, 3.65 - y0, 0.3, M.band, [5.5, (3.65 + y0) / 2.0, Z0 + 0.1])
	k.box(0.22, 3.65 - y0, 0.3, M.band, [11.7, (3.65 + y0) / 2.0, Z0 + 0.1])
	# ------------------------------------------------------------ windows
	var window_unit := func(axis: String, c_out: float, n_out: float, a0: float, a1: float, wy0: float, wy1: float, o: Dictionary) -> void:
		var depth := tO + tI
		var c_mid := c_out - n_out * depth * 0.45
		var Lw := a1 - a0
		var H := wy1 - wy0
		var am := (a0 + a1) / 2.0
		var ym := (wy0 + wy1) / 2.0
		var put := func(along: float, y: float, across: float, w: float, h: float, d: float, m):
			return k.box(w, h, d, m, [along, y, across]) if axis == "x" else k.box(d, h, w, m, [across, y, along])
		var fw := 0.06
		var fd := 0.09
		put.call(am, wy1 - fw / 2.0, c_mid, Lw, fw, fd, M.trim)
		put.call(am, wy0 + fw / 2.0, c_mid, Lw, fw, fd, M.trim)
		put.call(a0 + fw / 2.0, ym, c_mid, fw, H, fd, M.trim)
		put.call(a1 - fw / 2.0, ym, c_mid, fw, H, fd, M.trim)
		var n_mull: int = o.get("mullions", 1)
		for i in range(1, n_mull + 1):
			put.call(a0 + Lw * i / (n_mull + 1), ym, c_mid + n_out * (0.02 if i % 2 else -0.02), 0.045, H - fw, fd * 0.8, M.trim)
		if o.get("transom"):
			put.call(am, wy0 + H * o.transom, c_mid, Lw - fw, 0.04, fd * 0.8, M.trim)
		var gl = M.frost if o.get("frost") else M.glass
		var gm = k.plane(Lw - fw * 2.0, H - fw * 2.0, gl, [am, ym, c_mid], [0, 0, 0]) if axis == "x" else k.plane(Lw - fw * 2.0, H - fw * 2.0, gl, [c_mid, ym, am], [0, PI / 2.0, 0])
		gm.cast_shadow = false
		put.call(am, wy0 - 0.035, c_out + n_out * 0.05, Lw + 0.16, 0.07, 0.12, M.sill)
		if not o.get("noHood"):
			put.call(am, wy1 + 0.07, c_out + n_out * 0.05, Lw + 0.2, 0.06, 0.1, M.sill)
		put.call(am, wy0 - 0.02, c_out - n_out * (depth + 0.04), Lw + 0.06, 0.04, 0.1, M.trimInt)
		var ci := c_out - n_out * (depth + 0.009)
		put.call(am, wy0 - 0.085, ci, Lw + 0.02, 0.09, 0.018, M.trimInt)
		put.call(a0 - 0.035, ym + 0.02, ci, 0.07, H + 0.1, 0.018, M.trimInt)
		put.call(a1 + 0.035, ym + 0.02, ci, 0.07, H + 0.1, 0.018, M.trimInt)
		put.call(am, wy1 + 0.04, ci, Lw + 0.14, 0.08, 0.018, M.trimInt)
		if not o.get("noStreak") and r.f() < 0.8:
			var h := 0.35 + r.f() * 0.5
			var w := Lw * (0.5 + r.f() * 0.4)
			var sp
			if axis == "x":
				var sx := am + (r.f() - 0.5) * 0.2
				sp = k.plane(w, h, M.streak, [sx, wy0 - 0.07 - h / 2.0, c_out + n_out * 0.006], [0, 0.0 if n_out > 0 else PI, 0])
			else:
				sp = k.plane(w, h, M.streak, [c_out + n_out * 0.006, wy0 - 0.07 - h / 2.0, am], [0, PI / 2.0 if n_out > 0 else -PI / 2.0, 0])
			sp.receive_shadow = true
	for o in S:
		if o.y0 > 2.0:
			window_unit.call("x", Z1, 1.0, o.a0, o.a1, o.y0, o.y1, {"transom": 0.72})
	window_unit.call("x", Z0, -1.0, -2.9, -0.9, 2.2, 3.5, {"transom": 0.72})
	window_unit.call("x", Z0, -1.0, 1.3, 3.3, 2.2, 3.5, {"transom": 0.72})
	for o in E:
		window_unit.call("z", X1, 1.0, o.a0, o.a1, o.y0, o.y1, {"transom": 0.72})
	for o in W:
		window_unit.call("z", X0, -1.0, o.a0, o.a1, o.y0, o.y1, {"transom": 0.72})
	k.box(0.9, 2.0, 0.05, M.aluDark, [4.35, FY + 1.0, Z0 + 0.06])
	k.box(0.98, 0.05, 0.1, M.trim, [4.35, FY + 2.02, Z0 + 0.03])
	k.box(0.04, 0.12, 0.05, M.stainless, [4.72, FY + 1.0, Z0 + 0.02])
	k.box(0.3, 0.3, 0.02, M.frost, [4.35, FY + 1.62, Z0 + 0.03])
	A.plane("misc", "staffOnly", 0.42, 0.16, [4.35, FY + 1.25, Z0 + 0.03], PI)
	# ------------------------------------------------------------ entrance storefront
	var zs := Z1 - 0.07
	var alu := func(x: float, y: float, w: float, h: float, d: float = 0.08, z: float = zs): return k.box(w, h, d, M.alu, [x, y, z])
	alu.call(1.43, (FY + 3.65) / 2.0, 0.06, 3.65 - FY)
	alu.call(6.57, (FY + 3.65) / 2.0, 0.06, 3.65 - FY)
	alu.call(4.0, 3.62, 5.2, 0.06)
	alu.call(4.0, 3.4, 5.2, 0.06)
	alu.call(2.75, (FY + 3.4) / 2.0, 0.06, 3.4 - FY)
	alu.call(5.25, (FY + 3.4) / 2.0, 0.06, 3.4 - FY)
	alu.call(2.09, FY + 0.06, 1.3, 0.12)
	alu.call(5.91, FY + 0.06, 1.3, 0.12)
	var gp := func(x: float, y: float, w: float, h: float, z: float = zs):
		var m = k.plane(w, h, M.glass, [x, y, z])
		m.cast_shadow = false
		return m
	gp.call(2.09, (FY + 0.12 + 3.37) / 2.0, 1.28, 3.37 - FY - 0.12)
	gp.call(5.91, (FY + 0.12 + 3.37) / 2.0, 1.28, 3.37 - FY - 0.12)
	gp.call(4.0, 3.51, 5.1, 0.16)
	for x in [2.12, 5.88]:
		var zl := zs - 0.09
		k.box(1.26, 0.05, 0.05, M.alu, [x, 3.33, zl])
		k.box(1.26, 0.1, 0.05, M.alu, [x, FY + 0.05, zl])
		k.box(0.05, 2.1, 0.05, M.alu, [x - 0.6, FY + 1.05, zl])
		k.box(0.05, 2.1, 0.05, M.alu, [x + 0.6, FY + 1.05, zl])
		gp.call(x, FY + 1.1, 1.16, 1.98, zl)
		A.plane("face", "autoDoor", 0.3, 0.09, [x + (0.3 if x < 4.0 else -0.3), FY + 1.25, zs + 0.006], 0.0)
	k.box(0.46, 0.1, 0.12, M.darkPanel, [4.0, 3.3, zs - 0.12])
	A.board("P", "sakuraFest", 0.48, 0.68, [0.8, FY + 1.45, Z1 + 0.035], 0.0, {"frame": M.trim, "border": 0.03, "depth": 0.03})
	A.board("P", "festival", 0.48, 0.68, [7.2, FY + 1.45, Z1 + 0.035], 0.0, {"frame": M.trim, "border": 0.03, "depth": 0.03})
	# ------------------------------------------------------------ canopy + station name board
	var cz0 := Z1
	var cz1 := -23.25
	k.box(6.2, 0.13, cz1 - cz0, M.band, [4.0, 3.815, (cz0 + cz1) / 2.0])
	k.box(6.24, 0.2, 0.08, M.fascia, [4.0, 3.8, cz1 + 0.02])
	k.box(6.24, 0.03, 0.09, M.pinkBand, [4.0, 3.72, cz1 + 0.025])
	for x in [2.0, 4.0, 6.0]:
		k.cyl(0.09, 0.09, 0.02, M.lampWarm, [x, 3.742, -24.15], null, 16)
	for x in [1.3, 6.7]:
		U.beam(k, [x, 3.9, cz1 - 0.12], [x, 4.45, Z1 + 0.02], 0.025, 0.025, M.steelDark, true)
	var nb_w := 5.7
	var nb_h := 0.9
	var nb_y := 3.88 + 0.03 + nb_h / 2.0
	k.box(nb_w + 0.1, nb_h + 0.1, 0.1, M.fascia, [4.0, nb_y, cz1 + 0.06])
	A.plane("face", "nameBoard", nb_w, nb_h, [4.0, nb_y, cz1 + 0.113], 0.0)
	for x in [1.6, 6.4]:
		k.box(0.06, 0.12, 0.06, M.fascia, [x, 3.9, cz1 + 0.06])
	for x in [0.6, 7.35]:
		k.box(0.06, 0.06, 0.28, M.fascia, [x, 3.28, Z1 + 0.14])
		k.box(0.2, 0.05, 0.2, M.fascia, [x, 3.42, Z1 + 0.3])
		k.box(0.16, 0.24, 0.16, M.lampGlow, [x, 3.28, Z1 + 0.3])
		k.box(0.2, 0.03, 0.2, M.fascia, [x, 3.15, Z1 + 0.3])
	# ------------------------------------------------------------ main roof
	var RIDGE_Z: float = B.RIDGE_Z
	var ROOF_T: float = B.ROOF_T
	var ROOF_BASE: float = B.ROOF_BASE
	var th := atan(float(B.PITCH))
	var cth := cos(th)
	var roof_x0 := X0 - 0.45
	var roof_x1 := X1 + 0.45
	var zS := Z1 + 0.7
	var zN := Z0 - 1.1
	var roof_slab := func(xa: float, xb: float, za: float, zb: float) -> void:
		var south := zb > za
		var zm := (za + zb) / 2.0
		var ytop := roof_top(zm)
		var len := absf(zb - za) / cth
		var g := T.Group.new()
		g.position = Vector3((xa + xb) / 2.0, ytop, zm)
		g.rotation.x = th if south else -th
		root.add(g)
		var kk = ctx.kit(g)
		kk.box(xb - xa, ROOF_T, len, M.roof, [0, -ROOF_T / 2.0, 0])
		var n := floori((xb - xa) / 0.46)
		for i in range(1, n):
			kk.box(0.035, 0.045, len - 0.04, M.roofSeam, [-(xb - xa) / 2.0 + i * (xb - xa) / n, 0.02, 0])
	roof_slab.call(roof_x0, B.GX0, RIDGE_Z, zS)
	roof_slab.call(B.GX0, B.GX1, RIDGE_Z, Z1 - 0.12)
	roof_slab.call(B.GX1, roof_x1, RIDGE_Z, zS)
	roof_slab.call(roof_x0, roof_x1, RIDGE_Z, zN)
	k.box(roof_x1 - roof_x0 + 0.04, 0.12, 0.34, M.fascia, [(roof_x0 + roof_x1) / 2.0, roof_top(RIDGE_Z) + 0.02, RIDGE_Z])
	var soff := func(xa: float, xb: float, za: float, zb: float):
		return k.box(xb - xa, 0.03, absf(zb - za), M.soffit, [(xa + xb) / 2.0, minf(roof_top(za), roof_top(zb)) - ROOF_T - 0.03, (za + zb) / 2.0])
	soff.call(roof_x0, B.GX0 - 0.3, Z1, zS - 0.05)
	soff.call(B.GX1 + 0.3, roof_x1, Z1, zS - 0.05)
	soff.call(roof_x0, roof_x1, zN + 0.05, Z0)
	var eave := func(xa: float, xb: float, z: float, dir: float) -> void:
		var yt := roof_top(z)
		k.box(xb - xa, 0.26, 0.05, M.fascia, [(xa + xb) / 2.0, yt - 0.1, z + dir * 0.025])
		k.box(xb - xa, 0.1, 0.13, M.gutter, [(xa + xb) / 2.0, yt - 0.2, z + dir * 0.11])
		k.box(xb - xa, 0.02, 0.15, M.gutter, [(xa + xb) / 2.0, yt - 0.14, z + dir * 0.11])
	eave.call(roof_x0, B.GX0 - 0.3, zS, 1.0)
	eave.call(B.GX1 + 0.3, roof_x1, zS, 1.0)
	eave.call(roof_x0, roof_x1, zN, -1.0)
	for x in [roof_x0 - 0.02, roof_x1 + 0.02]:
		for zz in [[RIDGE_Z, zS], [RIDGE_Z, zN]]:
			var south: bool = zz[1] > zz[0]
			var zm: float = (zz[0] + zz[1]) / 2.0
			var len: float = absf(zz[1] - zz[0]) / cth
			var g := T.Group.new()
			g.position = Vector3(x, roof_top(zm), zm)
			g.rotation.x = th if south else -th
			root.add(g)
			ctx.kit(g).box(0.06, 0.3, len + 0.05, M.fascia, [0, -0.1, 0])
	var tri_h := roof_top(RIDGE_Z) - ROOF_T - WT
	for e in [[X1 - 0.06, -PI / 2.0], [X0 + 0.06, -PI / 2.0]]:
		var x: float = e[0]
		var pts := [[Z0 + 0.02, 0.0], [Z1 - 0.02, 0.0], [RIDGE_Z, tri_h + 0.02]]
		k.mesh(ctx.geo.extrude(pts, 0.12), M.plasterExt, [x, WT, 0], [0, e[1], 0])
		var vx := x + (0.07 if x > 4.0 else -0.07)
		k.box(0.04, 0.5, 0.7, M.trim, [vx, WT + 0.75, RIDGE_Z])
		for i in 5:
			k.box(0.05, 0.03, 0.62, M.sill, [vx + (0.01 if x > 4.0 else -0.01), WT + 0.56 + i * 0.09, RIDGE_Z])
	# ------------------------------------------------------------ entrance cross gable + clock
	var GX0: float = B.GX0
	var GX1: float = B.GX1
	var gph := atan(float(B.GPITCH))
	var cgp := cos(gph)
	var g_half := (GX1 - GX0) / 2.0 + 0.3
	var g_ridge_y: float = ROOF_BASE + (GX1 - GX0) / 2.0 * B.GPITCH
	var gz0 := Z1 + 0.55
	var gz1 := -29.9
	for side in [-1, 1]:
		var xm: float = 4.0 + side * g_half / 2.0
		var ym: float = g_ridge_y - g_half / 2.0 * B.GPITCH
		var g := T.Group.new()
		g.position = Vector3(xm, ym, (gz0 + gz1) / 2.0)
		g.rotation.z = gph if side < 0 else -gph
		root.add(g)
		var kk = ctx.kit(g)
		var len := g_half / cgp
		kk.box(len, ROOF_T, gz0 - gz1, M.roof, [0, -ROOF_T / 2.0, 0])
		var n := floori((gz0 - gz1) / 0.46)
		for i in range(1, n):
			kk.box(len - 0.04, 0.045, 0.035, M.roofSeam, [0, 0.02, -(gz0 - gz1) / 2.0 + i * (gz0 - gz1) / n])
		kk.box(len + 0.04, 0.3, 0.06, M.fascia, [0, -0.1, (gz0 - gz1) / 2.0 + 0.02])
	k.box(0.3, 0.12, gz0 - gz1, M.fascia, [4.0, g_ridge_y + 0.02, (gz0 + gz1) / 2.0])
	var gpts := [[GX0 + 0.02, 0.0], [GX1 - 0.02, 0.0], [4.0, g_ridge_y - ROOF_T - 0.04 - WT]]
	k.mesh(ctx.geo.extrude(gpts, 0.14), M.plasterExt, [0, WT, Z1 - 0.07], [0, 0, 0])
	k.box(0.36, 0.26, 0.06, M.fascia, [4.0, g_ridge_y - 0.34, Z1 + 0.55 - 0.02])
	k.box(0.22, 0.14, 0.07, M.pinkDeep, [4.0, g_ridge_y - 0.36, Z1 + 0.55 - 0.01])
	A.clock([4.0, 5.3, Z1 + 0.03], 0.0, 0.36, {"frame": M.fascia})
	for side in [-1, 1]:
		U.beam(k, [4.0 + side * 3.0, ROOF_BASE + 0.05, Z1 - 0.1], [4.0 + side * 0.05, g_ridge_y + 0.02, gz1], 0.12, 0.05, M.fascia)
	# ------------------------------------------------------------ downpipes
	var downpipe := func(xg: float, zg: float, y_top: float, xw: float, zw: float, y_bot: float) -> void:
		var y_bend := y_top - 0.45
		U.beam(k, [xg, y_top, zg], [xg, y_bend + 0.1, zg], 0.08, 0.08, M.gutter, true)
		U.beam(k, [xg, y_bend + 0.1, zg], [xw, y_bend - 0.25, zw], 0.08, 0.08, M.gutter, true)
		U.beam(k, [xw, y_bend - 0.25, zw], [xw, y_bot + 0.12, zw], 0.08, 0.08, M.gutter, true)
		k.cyl(0.05, 0.07, 0.14, M.gutter, [xw, y_bot + 0.07, zw], null, 10)
		var y := y_bot + 0.8
		while y < y_bend - 0.4:
			k.box(0.12, 0.03, 0.1, M.steelDark, [xw, y, zw])
			y += 1.2
	var L = ctx.L
	downpipe.call(roof_x0 + 0.12, zS + 0.11, roof_top(zS) - 0.2, X0 - 0.07, Z1 - 0.2, L.height_at(X0 - 0.07, Z1 - 0.2))
	downpipe.call(roof_x1 - 0.12, zS + 0.11, roof_top(zS) - 0.2, X1 + 0.07, Z1 - 0.2, L.height_at(X1 + 0.07, Z1 - 0.2))
	downpipe.call(roof_x0 + 0.12, zN - 0.11, roof_top(zN) - 0.2, X0 - 0.07, Z0 + 0.25, L.height_at(X0 - 0.07, Z0 + 0.25))
	downpipe.call(roof_x1 - 0.12, zN - 0.11, roof_top(zN) - 0.2, X1 + 0.07, Z0 + 0.25, L.height_at(X1 + 0.07, Z0 + 0.25))
	# ------------------------------------------------------------ AC units, meters, grime, streaks
	var ac_unit := func(x: float, y: float, z: float, rot_y: float) -> void:
		var g = k.group([x, y, z], rot_y)
		var kk = ctx.kit(g)
		kk.rbox(0.8, 0.6, 0.3, 0.03, M.sill, [0, 0.3, 0])
		kk.cyl(0.22, 0.22, 0.02, M.fascia, [-0.12, 0.3, 0.155], [PI / 2.0, 0, 0], 16)
		for i in range(-3, 4):
			kk.box(0.44, 0.012, 0.012, M.steel, [-0.12, 0.3 + i * 0.055, 0.168])
		kk.box(0.06, 0.08, 0.34, M.steelDark, [-0.3, -0.04, 0])
		kk.box(0.06, 0.08, 0.34, M.steelDark, [0.3, -0.04, 0])
	ac_unit.call(X1 + 0.2, 0.08, -30.6, PI / 2.0)
	P.addBox(X1 + 0.2, -30.6, 0.4, 0.9, 0, 0, 1)
	U.beam(k, [X1 + 0.05, 0.5, -30.95], [X1 + 0.05, 2.6, -30.95], 0.06, 0.06, M.sill, true)
	ac_unit.call(X0 - 0.2, 0.08, -30.4, -PI / 2.0)
	P.addBox(X0 - 0.2, -30.4, 0.4, 0.9, 0, 0, 1)
	U.beam(k, [X0 - 0.05, 0.5, -30.05], [X0 - 0.05, 2.7, -30.05], 0.06, 0.06, M.sill, true)
	k.box(0.08, 0.5, 0.36, M.sill, [X0 - 0.04, 2.0, -29.2])
	k.box(0.02, 0.16, 0.2, M.glassIn, [X0 - 0.085, 2.05, -29.2])
	k.box(0.08, 0.36, 0.28, M.steel, [X0 - 0.04, 1.2, -28.6])
	var grime_strip := func(x: float, z: float, w: float, rot_y: float, y: float = 0.0) -> void:
		var m = k.plane(w, 0.45, M.grime, [x, y + 0.24, z], [0, rot_y, 0])
		m.receive_shadow = true
	var gz := -34.5
	while gz < -25.5:
		grime_strip.call(X1 + 0.012, gz + 1.1, 2.2, PI / 2.0, L.height_at(X1 + 0.1, gz + 1.1))
		gz += 2.2
	gz = -33.5
	while gz < -25.5:
		grime_strip.call(X0 - 0.012, gz + 1.1, 2.2, -PI / 2.0, L.height_at(X0 - 0.1, gz + 1.1))
		gz += 2.2
	for e in [[-2.2, Z1 + 0.008, 0.0], [9.6, Z1 + 0.008, 0.0], [X1 + 0.008, -29.6, PI / 2.0], [X0 - 0.008, -31.0, -PI / 2.0], [0.4, Z0 - 0.008, PI], [-3.2, Z0 - 0.008, PI]]:
		var w := 1.6 + r.f() * 1.2
		var h := 0.5 + r.f() * 0.4
		var m = k.plane(w, h, M.streak, [e[0], WT - 0.35, e[1]], [0, e[2], 0])
		m.receive_shadow = true
	build_forecourt(A)


static func build_forecourt(A) -> void:
	var ctx = A.ctx
	var k = A.k
	var U = A.U
	var M: Dictionary = A.M
	var P = A.P
	var FY: float = B.FY
	var TZ0: float = B.Z1
	var TZ1 := -22.92
	var TX0: float = B.X0
	var TX1 := 7.4
	var STEP := FY / 7.0
	var TREAD := 0.32
	k.box(TX1 - TX0, FY - 0.01, TZ1 - TZ0, M.stone, [(TX0 + TX1) / 2.0, (FY - 0.01) / 2.0, (TZ0 + TZ1) / 2.0])
	k.box(TX1 - TX0, 0.02, TZ1 - TZ0, M.paving, [(TX0 + TX1) / 2.0, FY - 0.01, (TZ0 + TZ1) / 2.0])
	k.box(TX1 - TX0 + 0.04, 0.06, 0.1, M.band, [(TX0 + TX1) / 2.0, FY - 0.03, TZ1 - 0.03])
	P.addWalkBox((TX0 + TX1) / 2.0, (TZ0 + TZ1) / 2.0, TX1 - TX0, TZ1 - TZ0, 0, FY)
	var SX0 := 0.6
	var SX1 := 6.2
	for i in range(1, 7):
		var top := i * STEP
		var zf := -21.0 - (i - 1) * TREAD
		var zb := TZ1
		k.box(SX1 - SX0, top, zf - zb, M.stone, [(SX0 + SX1) / 2.0, top / 2.0, (zf + zb) / 2.0])
		k.box(SX1 - SX0, 0.015, TREAD, M.paving, [(SX0 + SX1) / 2.0, top - 0.005, zf - TREAD / 2.0])
		k.box(SX1 - SX0, 0.03, 0.05, M.aluDark, [(SX0 + SX1) / 2.0, top - 0.008, zf - 0.03])
		P.addWalkBox((SX0 + SX1) / 2.0, zf - TREAD / 2.0, SX1 - SX0, TREAD, 0, top)
	for x in [SX0 - 0.08, SX1 + 0.08]:
		var g: T.Geometry = ctx.geo.extrude([[-20.72, 0.0], [TZ1, 0.0], [TZ1, FY + 0.12], [-21.0 - 5 * TREAD, 6 * STEP + 0.12], [-21.0, STEP + 0.12], [-20.72, 0.22]], 0.16)
		k.mesh(g, M.band, [x, 0, 0], [0, -PI / 2.0, 0])
		U.railing(k, [[x, -20.9], [x, -21.0 - 5 * TREAD], [x, TZ1 - 0.05]], func(_xx, z):
			return FY + 0.12 if z < -21.0 - 5 * TREAD else (0.22 if z > -21.0 else STEP + 0.12 + (-21.0 - z) / (5 * TREAD) * 5 * STEP),
			{"h": 0.85, "post": 0.9, "rails": [1.0], "mat": M.stainless, "round": true, "postW": 0.045})
		P.addBox(x, -21.95, 0.18, 2.2, 0, -1, 2.3)
	var zt := func(i: int) -> float: return -21.0 - (i - 1) * TREAD - TREAD / 2.0
	for i in [1, 3, 6]:
		U.beam(k, [3.4, i * STEP, zt.call(i)], [3.4, i * STEP + 0.86, zt.call(i)], 0.045, 0.045, M.stainless, true)
	for h in [0.85, 0.6]:
		U.beam(k, [3.4, STEP + h, zt.call(1) + 0.15], [3.4, 6 * STEP + h, zt.call(6) - 0.1], 0.04, 0.04, M.stainless, true)
	P.addBox(3.4, (zt.call(1) + zt.call(6)) / 2.0, 0.08, zt.call(1) - zt.call(6), 0, 0, 1.3)
	U.railing(k, [[TX0 + 0.06, TZ1 + 0.06], [SX0 - 0.1, TZ1 + 0.06]], FY, {"h": 1.05, "post": 1.4, "rails": [1.0, 0.5], "bar": 0.14, "mat": M.stainless, "round": true})
	U.railing(k, [[TX0 + 0.06, TZ0 + 0.1], [TX0 + 0.06, TZ1 + 0.06]], FY, {"h": 1.05, "post": 1.1, "rails": [1.0, 0.5], "bar": 0.14, "mat": M.stainless, "round": true})
	U.railing(k, [[SX1 + 0.1, TZ1 + 0.06], [TX1 - 0.06, TZ1 + 0.06]], FY, {"h": 1.05, "post": 1.2, "rails": [1.0, 0.5], "bar": 0.14, "mat": M.stainless, "round": true})
	P.addBox((TX0 + SX0) / 2.0, TZ1 + 0.06, SX0 - TX0, 0.12, 0, FY - 0.2, FY + 1.1)
	P.addBox(TX0 + 0.06, (TZ0 + TZ1) / 2.0, 0.12, TZ1 - TZ0, 0, FY - 0.2, FY + 1.1)
	P.addBox((SX1 + TX1) / 2.0, TZ1 + 0.06, TX1 - SX1, 0.12, 0, FY - 0.2, FY + 1.1)
	planter(A, -3.85, 0.35, TZ1 + 0.05, -22.3, 0.5, "st-planter-w")
	var F1 := {"x0": 7.4, "x1": 12.5, "z0": -24.95, "z1": -23.55, "yW": FY, "yE": 0.625}
	var LD := {"x0": 12.5, "x1": 13.95, "z0": -24.95, "z1": -21.95, "y": 0.625}
	var F2 := {"x0": 7.4, "x1": 12.5, "z0": -23.35, "z1": -21.95, "yW": 0.0, "yE": 0.625}
	var wedge := func(f: Dictionary) -> void:
		var g: T.Geometry = ctx.geo.extrude([[f.x0, 0.0], [f.x1, 0.0], [f.x1, f.yE], [f.x0, f.yW]], f.z1 - f.z0)
		k.mesh(g, M.stone, [0, 0, (f.z0 + f.z1) / 2.0])
		var Lr := sqrt((f.x1 - f.x0) ** 2 + (f.yE - f.yW) ** 2)
		var ang := atan2(f.yE - f.yW, f.x1 - f.x0)
		k.box(Lr, 0.02, f.z1 - f.z0, M.paving, [(f.x0 + f.x1) / 2.0, (f.yW + f.yE) / 2.0 - 0.004, (f.z0 + f.z1) / 2.0], [0, 0, ang])
	if F1.yW > 0.01:
		wedge.call(F1)
	wedge.call(F2)
	k.box(LD.x1 - LD.x0, LD.y, LD.z1 - LD.z0, M.stone, [(LD.x0 + LD.x1) / 2.0, LD.y / 2.0, (LD.z0 + LD.z1) / 2.0])
	k.box(LD.x1 - LD.x0, 0.02, LD.z1 - LD.z0, M.paving, [(LD.x0 + LD.x1) / 2.0, LD.y - 0.006, (LD.z0 + LD.z1) / 2.0])
	P.addWalkRamp((F1.x0 + F1.x1) / 2.0, (F1.z0 + F1.z1) / 2.0, F1.z1 - F1.z0, F1.x1 - F1.x0, -PI / 2.0, F1.yE, F1.yW)
	P.addWalkRamp((F2.x0 + F2.x1) / 2.0, (F2.z0 + F2.z1) / 2.0, F2.z1 - F2.z0, F2.x1 - F2.x0, PI / 2.0, F2.yW, F2.yE)
	P.addWalkBox((LD.x0 + LD.x1) / 2.0, (LD.z0 + LD.z1) / 2.0, LD.x1 - LD.x0, LD.z1 - LD.z0, 0, LD.y)
	var dg: T.Geometry = ctx.geo.extrude([[F1.x0, 0.0], [F1.x1, 0.0], [F1.x1, F1.yE + 0.9], [F1.x0, F1.yW + 0.9]], 0.2)
	k.mesh(dg, M.plasterExt, [0, 0, -23.45])
	U.beam(k, [F1.x0, F1.yW + 0.92, -23.45], [F1.x1, F1.yE + 0.92, -23.45], 0.22, 0.05, M.band)
	P.addBox((F1.x0 + F1.x1) / 2.0, -23.45, F1.x1 - F1.x0, 0.2, 0, -1, F1.yW + 0.95)
	var parapet := func(pts: Array, y_fn: Callable, hgt: float = 0.9) -> void:
		for i in pts.size() - 1:
			var ax: float = pts[i][0]
			var az: float = pts[i][1]
			var bx: float = pts[i + 1][0]
			var bz: float = pts[i + 1][1]
			if absf(bx - ax) > absf(bz - az):
				var x0 := minf(ax, bx)
				var x1 := maxf(ax, bx)
				var z := az
				var g: T.Geometry = ctx.geo.extrude([[x0, 0.0], [x1, 0.0], [x1, y_fn.call(x1, z) + hgt], [x0, y_fn.call(x0, z) + hgt]], 0.16)
				k.mesh(g, M.plasterExt, [0, 0, z])
				U.beam(k, [x0 - 0.02, y_fn.call(x0, z) + hgt + 0.02, z], [x1 + 0.02, y_fn.call(x1, z) + hgt + 0.02, z], 0.2, 0.05, M.band)
				P.addBox((x0 + x1) / 2.0, z, x1 - x0, 0.18, 0, -1, maxf(y_fn.call(x0, z), y_fn.call(x1, z)) + hgt)
			else:
				var z0 := minf(az, bz)
				var z1 := maxf(az, bz)
				var x := ax
				var y: float = y_fn.call(x, z0)
				k.box(0.16, y + hgt, z1 - z0, M.plasterExt, [x, (y + hgt) / 2.0, (z0 + z1) / 2.0])
				k.box(0.2, 0.05, z1 - z0 + 0.04, M.band, [x, y + hgt + 0.02, (z0 + z1) / 2.0])
				P.addBox(x, (z0 + z1) / 2.0, 0.18, z1 - z0, 0, -1, y + hgt)
	var f2y := func(x: float) -> float: return F2.yW + (x - F2.x0) / (F2.x1 - F2.x0) * (F2.yE - F2.yW)
	parapet.call([[F2.x0 + 0.1, -21.87], [LD.x1, -21.87]], func(x, _z): return LD.y if x > LD.x0 else f2y.call(x))
	parapet.call([[LD.x1 - 0.08, -21.95], [LD.x1 - 0.08, -24.95]], func(_x, _z): return LD.y)
	parapet.call([[12.0, -24.87], [LD.x1, -24.87]], func(x, _z): return LD.y if x > LD.x0 else F1.yE + (F1.x1 - x) / (F1.x1 - F1.x0) * (F1.yW - F1.yE))
	var f1y := func(x: float) -> float: return F1.yE + (F1.x1 - x) / (F1.x1 - F1.x0) * (F1.yW - F1.yE)
	var hr := func(xa: float, xb: float, z: float, yf: Callable, zw: float) -> void:
		for h in [0.85, 0.65]:
			U.beam(k, [xa, yf.call(xa) + h, z], [xb, yf.call(xb) + h, z], 0.04, 0.04, M.stainless, true)
		var n := maxi(1, T.js_round((xb - xa) / 1.2))
		for i in n + 1:
			var x := xa + (xb - xa) * i / n
			for h in [0.85, 0.65]:
				U.beam(k, [x, yf.call(x) + h - 0.04, z], [x, yf.call(x) + h - 0.04, zw], 0.025, 0.025, M.stainless, true)
	hr.call(F1.x0 + 0.05, F1.x1, -24.8, f1y, -24.99)
	hr.call(F1.x0 + 0.05, F1.x1, -23.62, f1y, -23.55)
	hr.call(F2.x0 + 0.15, F2.x1, -23.28, f2y, -23.35)
	hr.call(F2.x0 + 0.15, F2.x1, -22.03, f2y, -21.95)
	var pave := func(x0: float, x1: float, z0: float, z1: float): return k.box(x1 - x0, 0.03, z1 - z0, M.paving, [(x0 + x1) / 2.0, 0.012, (z0 + z1) / 2.0])
	pave.call(-4.0, 14.0, -21.0, -20.5)
	pave.call(-4.0, 0.52, -22.92, -21.0)
	pave.call(6.28, 7.4, -23.35, -21.0)
	pave.call(7.4, 14.0, -21.95, -21.0)
	planter(A, 7.9, 13.6, -21.87 + 0.08, -21.3, 0.45, "st-planter-e")
	var t_dot := func(x: float, z: float, w: float, d: float, y: float): return k.box(w, 0.01, d, M.tactDot, [x, y + 0.005, z])
	var t_line := func(x: float, z: float, w: float, d: float, y: float): return k.box(w, 0.01, d, M.tactLine, [x, y + 0.005, z])
	t_dot.call(4.0, TZ1 - 0.3, 1.2, 0.6, FY)
	t_dot.call(4.0, -20.8, 1.2, 0.3, 0.02)
	t_line.call(4.0, (TZ0 + TZ1 - 0.6) / 2.0 + 0.05, 0.3, (TZ1 - 0.6 - TZ0) - 0.3, FY)
	t_dot.call(6.85, -21.2, 0.9, 0.3, 0.02)


static func planter(A, x0: float, x1: float, z0: float, z1: float, h: float, seed: String) -> void:
	var ctx = A.ctx
	var k = A.k
	var U = A.U
	var M: Dictionary = A.M
	var r: Rng = ctx.rng(seed)
	var cx := (x0 + x1) / 2.0
	var cz := (z0 + z1) / 2.0
	var w := x1 - x0
	var d := absf(z1 - z0)
	k.box(w, h, d, M.stone, [cx, h / 2.0, cz])
	k.box(w + 0.06, 0.05, d + 0.06, M.band, [cx, h + 0.02, cz])
	k.box(w - 0.12, 0.02, d - 0.12, M.soil, [cx, h - 0.03, cz])
	var C = U.cards()
	var F = A.atlases.FOL
	var kinds := ["pansy", "pansy", "tulip", "daisy"]
	var n := floori(w * d * 16.0) + floori(w / 0.3)
	for i in n:
		var x := x0 + 0.12 + r.f() * (w - 0.24)
		var z := cz + (r.f() - 0.5) * (d - 0.22)
		var kind: String = kinds[floori(r.f() * kinds.size())]
		var s := 0.42 if kind == "tulip" else 0.3
		C.cross(x, h - 0.03, z, s, s * (1.1 if kind == "tulip" else 0.9), r.f() * 3.0, F.r(kind))
	var mesh = C.build(M.foliage)
	if mesh != null:
		ctx.no_outline(mesh)
		A.root.add(mesh)
	A.P.addBox(cx, cz, w, d, 0, -1, h)
