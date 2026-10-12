# props/shrine.js: E6, 桜ヶ丘稲荷神社, a tiny neighbourhood Inari shrine on a raised gravel terrace.
# Lot frame: origin at the frontage centre, +Z faces the main street, lot = x in [-4.25,4.25],
# z in [-14,0]. Local +x of this lot points south (world +z). SPOTS.shrineSakura (lot -2.5,-6.5) is
# left clear.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const C = preload("res://addons/sakuragaoka_station/world/props/common.gd")
const ST = preload("res://addons/sakuragaoka_station/world/props/shrinetex.gd")
const Scatter = preload("res://addons/sakuragaoka_station/world/props/scatter.gd")
const Fol = preload("res://addons/sakuragaoka_station/world/lib/foliage.gd")


static func build_shrine(ctx, H) -> void:
	var L = ctx.L
	var mat = ctx.mat
	var physics = ctx.physics
	var lot = L.lot_by_id("E6")
	if not lot:
		return
	var f: Dictionary = L.lot_frame(lot)
	var tx: Dictionary = ST.make_shrine_textures(ctx)
	var root = H.place(f.x, 0, f.z, f.rotY)
	var K = ctx.kit(root)
	var W := func(lx: float, lz: float) -> Dictionary: return L.lot_to_world(lot, lx, lz)
	var gy := func(lx: float, lz: float) -> float:
		var p: Dictionary = W.call(lx, lz)
		return L.height_at(p.x, p.z)
	var c_box := func(lx: float, lz: float, w: float, d: float, lrot: float, y0: float, y1: float) -> void:
		var p: Dictionary = W.call(lx, lz)
		physics.addBox(p.x, p.z, w, d, f.rotY + lrot, y0, y1)
	var c_cyl := func(lx: float, lz: float, r: float, y0: float, y1: float) -> void:
		var p: Dictionary = W.call(lx, lz)
		physics.addCylinder(p.x, p.z, r, y0, y1)
	var c_walk := func(lx: float, lz: float, w: float, d: float, lrot: float, top: float) -> void:
		var p: Dictionary = W.call(lx, lz)
		physics.addWalkBox(p.x, p.z, w, d, f.rotY + lrot, top)
	var sub := func(lx: float, y: float, lz: float, rot: float):
		var g := T.Group.new()
		g.position = Vector3(lx, y, lz)
		g.rotation.y = rot
		root.add(g)
		return g
	var rnd = ctx.rng("props.shrine")

	# ---------------------------------------------------------------- materials
	var M := {
		"wall": mat.toon("#ffffff", {"map": tx.stoneWall, "paint": 0.05}),
		"stone": mat.toon("#ffffff", {"map": tx.stone, "paint": 0.06}),
		"coping": mat.toon("#dedad2", {"map": tx.stone, "paint": 0.05}),
		"slabA": mat.toon("#ece9e2", {"map": tx.stone, "paint": 0.05}),
		"slabB": mat.toon("#dcd8cf", {"map": tx.stone, "paint": 0.05}),
		"slabC": mat.toon("#d2cdc3", {"map": tx.stone, "paint": 0.05}),
		"statue": mat.toon("#ecebe5", {"map": tx.stone, "paint": 0.05}),
		"gravel": mat.toon("#ffffff", {"map": tx.gravel, "paint": 0.04}),
		"verm": mat.toon("#e2623f", {"paint": 0.035}),
		"black": mat.toon("#453d4b", {"paint": 0.02}),
		"wood": mat.toon("#ffffff", {"map": tx.wood, "paint": 0.04}),
		"woodDark": mat.toon("#7e5f45", {"paint": 0.05}),
		"woodMid": mat.toon("#9c7a58", {"paint": 0.05}),
		"copper": mat.toon("#8bb6a4", {"paint": 0.05}),
		"copperDark": mat.toon("#6f9a8a", {"paint": 0.04}),
		"slate": mat.toon("#667083", {"paint": 0.05}),
		"red": mat.toon("#d9503f", {"side": "double", "paint": 0.03}),
		"redKnit": mat.toon("#c9463d", {"paint": 0.06}),
		"shide": mat.toon("#f6f3ec", {"side": "double", "paint": 0.01}),
		"gold": mat.toon("#dcbb66", {"paint": 0.02}),
		"rope": mat.toon("#ffffff", {"map": tx.rope, "paint": 0.02}),
		"bellRope": mat.toon("#e0a090", {"map": tx.rope, "paint": 0.02}),
		"ink": mat.toon("#3a3346", {"paint": 0}),
		"porcelain": mat.toon("#f1efe9", {"paint": 0.01}),
		"bamboo": mat.toon("#c9bb86", {"paint": 0.04}),
		"bambooDark": mat.toon("#a8996a", {"paint": 0.04}),
		"water": mat.toon("#ffffff", {"map": tx.water, "paint": 0.01}),
		"stream": mat.emissive("#e3f3f8", 0.95),
		"leafDark": mat.toon("#4c7a52", {"paint": 0.08}),
		"leafMid": mat.toon("#5f8e5b", {"paint": 0.08}),
		"leafLight": mat.toon("#80aa68", {"paint": 0.08}),
		"camellia": mat.toon("#d9434f", {"paint": 0.03}),
		"trunk": mat.toon("#6b5546", {"paint": 0.07}),
		"ema": mat.toon("#ffffff", {"map": tx.ema, "paint": 0.02}),
		"cord": mat.toon("#c9453d", {"paint": 0}),
		"notice": mat.toon("#ffffff", {"map": tx.notice, "paint": 0.02}),
		"noticeHead": mat.toon("#ffffff", {"map": tx.noticeHead, "paint": 0.02}),
		"roofTin": mat.toon("#5f6670", {"paint": 0.04}),
		"moss": mat.decal("#ffffff", {"map": moss_tex(ctx), "transparent": true}),
	}

	# ---------------------------------------------------------------- terrace, steps, gravel
	var TY: float = f.y + 0.30
	var g_min := INF
	for lx in [-4.25, 4.25]:
		for lz in [0.0, -14.0]:
			g_min = minf(g_min, gy.call(lx, lz))
	var tb := g_min - 0.15
	var tt := TY - 0.03
	K.mesh(_tiled_box(8.4, tt - tb, 13.35, 2.0, 1.0), M.wall, [0, (tt + tb) / 2.0, -7.275])
	# coping stones (笠石) on the retaining wall
	var cop := func(cx: float, cz: float, w: float, d: float): return K.mesh(_tiled_box(w, 0.1, d, 0.8), M.coping, [cx, TY - 0.015, cz])
	cop.call((-4.2 - 0.75) / 2.0, -0.76, 4.2 - 0.75, 0.32)
	cop.call((1.55 + 4.2) / 2.0, -0.76, 4.2 - 1.55, 0.32)
	cop.call(-4.04, -7.275, 0.32, 12.71)
	cop.call(4.04, -7.275, 0.32, 12.71)
	cop.call(0, -13.79, 8.4, 0.32)
	# gravel
	if true:
		var pg := Geo.plane(7.76, 12.71)
		var uv: T.Attr = pg.attributes.uv
		for i in uv.count():
			uv.set_xy(i, uv.get_x(i) * 7.76 / 1.6, uv.get_y(i) * 12.71 / 1.6)
		var m = K.mesh(pg, M.gravel, [0, TY, -7.275], [-PI / 2.0, 0, 0])
		m.cast_shadow = false
	# front steps (2 steps + terrace), cheek stones
	var yS: float = gy.call(0.4, -0.05)
	var rise := (TY + 0.03 - yS) / 3.0
	K.mesh(_tiled_box(2.3, rise + 0.14, 0.58, 0.8), M.coping, [0.4, yS - 0.14 + (rise + 0.14) / 2.0, -0.31])
	K.mesh(_tiled_box(2.3, rise + 0.02, 0.29, 0.8), M.coping, [0.4, yS + rise - 0.02 + (rise + 0.02) / 2.0, -0.455])
	for s in [-1, 1]:
		var x: float = 0.4 + s * 1.23
		var h: float = TY + 0.08 - (yS - 0.12)
		K.mesh(_tiled_box(0.16, h, 0.62, 0.8), M.coping, [x, yS - 0.12 + h / 2.0, -0.3])
	c_walk.call(0.4, -0.175, 2.3, 0.29, 0, yS + rise)
	c_walk.call(0.4, -0.455, 2.3, 0.29, 0, yS + 2 * rise)
	c_walk.call(0, -7.275, 8.4, 13.35, 0, TY + 0.03)
	for s in [-1, 1]:
		c_box.call(0.4 + s * 1.23, -0.3, 0.16, 0.62, 0, tb, TY + 0.08)

	# ---------------------------------------------------------------- stone path (参道) + apron + stepping stones
	var slab_mats := [M.slabA, M.slabB, M.slabC]
	var slab := func(cx: float, cz: float, w: float, d: float) -> void:
		var mi: int = int(rnd.f() * 3)
		var py: float = TY + 0.005 + rnd.f() * 0.006
		var r0: float = (rnd.f() - 0.5) * 0.008
		var r1: float = (rnd.f() - 0.5) * 0.02
		var r2: float = (rnd.f() - 0.5) * 0.008
		var m = K.mesh(_tiled_box(w, 0.05, d, 0.9), slab_mats[mi], [cx, py, cz], [r0, r1, r2])
		m.cast_shadow = false
	slab.call(0.4, -0.86, 2.28, 0.5)
	var z := -1.14
	while z > -11.0:
		var d: float = 0.46 + rnd.f() * 0.08
		if rnd.f() < 0.35:
			slab.call(0.4 - 0.28, z - d / 2.0, 0.54, d)
			slab.call(0.4 + 0.28, z - d / 2.0, 0.54, d)
		else:
			slab.call(0.4 + (rnd.f() - 0.5) * 0.04, z - d / 2.0, 1.1, d)
		z -= d + 0.035
	for i in 3:
		slab.call(-0.08 + i * 0.64, -11.45, 0.6, 0.62)
	var step := func(lx: float, lz: float, r: float) -> void:
		var mi: int = int(rnd.f() * 3)
		var ry: float = rnd.f() * 3.0
		var m = K.cyl(r, r * 1.06, 0.034, slab_mats[mi], [lx, TY + 0.006, lz], [0, ry, 0], 10)
		m.scale.z *= 0.8
		m.cast_shadow = false
	for e in [[-0.5, -9.25, 0.2], [-1.1, -9.45, 0.18], [-1.7, -9.35, 0.19], [-2.3, -9.55, 0.17]]:
		step.call(e[0], e[1], e[2])
	for e in [[1.3, -7.9, 0.19], [1.86, -8.08, 0.17], [2.42, -7.95, 0.18]]:
		step.call(e[0], e[1], e[2])

	# ---------------------------------------------------------------- 玉垣 fence (stone posts + rails)
	var post_g := C.merge_all([C.xf(Geo.box(0.11, 0.6, 0.11), [0, 0.3, 0]), C.xf(Geo.cylinder(0.004, 0.078, 0.07, 4), [0, 0.635, 0], [0, PI / 4.0, 0])])
	var FB := TY + 0.035  # fence base (coping top)
	var fence := func(a: Array, b: Array, n: int, skip_a: bool, skip_b: bool) -> void:
		var dx: float = b[0] - a[0]
		var dz: float = b[1] - a[1]
		var ln := sqrt(dx * dx + dz * dz)
		var ang := atan2(dx, dz)
		for i in n + 1:
			if (i == 0 and skip_a) or (i == n and skip_b):
				continue
			var t := float(i) / n
			K.mesh(post_g, M.stone, [a[0] + dx * t, FB, a[1] + dz * t])
		for h in [0.17, 0.47]:
			K.mesh(_tiled_box(0.055, 0.06, ln, 0.8), M.stone, [(a[0] + b[0]) / 2.0, FB + h, (a[1] + b[1]) / 2.0], [0, ang, 0])
		var p: Dictionary = W.call((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)
		physics.addBox(p.x, p.z, 0.16, ln, f.rotY + ang, tb, FB + 0.68)
	fence.call([-4.04, -0.76], [-1.13, -0.76], 3, false, true)
	fence.call([1.9, -0.76], [4.04, -0.76], 2, true, false)
	fence.call([-4.04, -0.76], [-4.04, -13.79], 13, true, false)
	fence.call([4.04, -0.76], [4.04, -13.79], 13, true, false)
	fence.call([-4.04, -13.79], [4.04, -13.79], 8, true, true)
	# donor names on a few front posts (奉納 ...)
	for e in [[-4.04, 0], [-3.07, 1], [2.97, 2], [4.04, 3]]:
		K.plane(0.075, 0.3, mat.decal("#ffffff", {"map": tx.kennoTex[e[1]], "transparent": true}), [e[0], FB + 0.3, -0.76 + 0.057])
	# 社号標 (shrine-name pillar) and the south gate pillar
	K.mesh(_tiled_box(0.44, 0.12, 0.44, 0.8), M.coping, [-1.0, FB + 0.06, -0.76])
	K.mesh(_tiled_box(0.27, 1.34, 0.27, 0.8), M.stone, [-1.0, FB + 0.12 + 0.67, -0.76])
	K.mesh(Geo.cylinder(0.01, 0.19, 0.08, 4).rotate_y(PI / 4.0), M.stone, [-1.0, FB + 0.12 + 1.34 + 0.04, -0.76])
	K.plane(0.19, 1.14, mat.decal("#ffffff", {"map": tx.shagou, "transparent": true}), [-1.0, FB + 0.12 + 0.69, -0.76 + 0.1375])
	c_box.call(-1.0, -0.76, 0.44, 0.44, 0, tb, FB + 1.55)
	K.mesh(_tiled_box(0.3, 0.1, 0.3, 0.8), M.coping, [1.8, FB + 0.05, -0.76])
	K.mesh(_tiled_box(0.2, 0.86, 0.2, 0.8), M.stone, [1.8, FB + 0.1 + 0.43, -0.76])
	K.mesh(Geo.cylinder(0.008, 0.14, 0.07, 4).rotate_y(PI / 4.0), M.stone, [1.8, FB + 0.1 + 0.86 + 0.035, -0.76])
	c_box.call(1.8, -0.76, 0.3, 0.3, 0, tb, FB + 1.0)

	# ---------------------------------------------------------------- torii (稲荷鳥居: vermilion, black kasagi, daiwa rings)
	if true:
		var g = sub.call(0.4, TY, -1.3, 0.0)
		var k = ctx.kit(g)
		var lean := 1.4 * C.DEG
		for s in [-1, 1]:
			var x: float = s * 1.05
			k.mesh(Geo.cylinder(0.094, 0.108, 2.64, 18), M.verm, [x - s * sin(lean) * 1.32, 1.32, 0], [0, 0, s * lean])
			k.cyl(0.124, 0.13, 0.32, M.black, [x, 0.14, 0], null, 18)
			k.cyl(0.134, 0.134, 0.07, M.black, [x - s * sin(lean) * 2.64, 2.64, 0], null, 18)
			c_cyl.call(0.4 + x, -1.3, 0.14, TY - 0.2, TY + 3.0)
		k.box(2.72, 0.12, 0.09, M.verm, [0, 2.2, 0])
		for s in [-1, 1]:
			k.box(0.035, 0.15, 0.12, M.black, [s * 1.2, 2.2, 0])
		k.mesh(C.bent_box(3.08, 0.12, 0.22, 20, func(t: float) -> float: return 0.05 * pow(absf(t), 2.6)), M.verm, [0, 2.735, 0])
		k.mesh(C.bent_box(3.56, 0.13, 0.3, 24, func(t: float) -> float: return 0.12 * pow(absf(t), 2.6)), M.black, [0, 2.86, 0])
		k.box(0.12, 0.42, 0.085, M.verm, [0, 2.47, 0])
		k.box(0.27, 0.38, 0.035, M.black, [0, 2.47, 0.058])
		k.plane(0.235, 0.35, mat.toon("#ffffff", {"map": tx.gaku, "paint": 0.01}), [0, 2.47, 0.0765])
		# shimenawa + shide on the torii
		rope_with_shide(ctx, k, M, [-0.96, 2.05, 0.075], [0.96, 2.05, 0.075], 0.13, 0.03, [-0.5, 0, 0.5])

	# ---------------------------------------------------------------- stone lanterns (石灯籠)
	for lx in [-0.82, 1.62]:
		var g = sub.call(lx, TY, -2.95, 0.0)
		var k = ctx.kit(g)
		k.cyl(0.3, 0.32, 0.13, M.stone, [0, 0.065, 0], null, 6)
		k.cyl(0.22, 0.26, 0.1, M.stone, [0, 0.18, 0], null, 6)
		k.cyl(0.085, 0.095, 0.62, M.stone, [0, 0.54, 0], null, 12)
		k.cyl(0.105, 0.105, 0.04, M.stone, [0, 0.55, 0], null, 12)
		k.cyl(0.26, 0.15, 0.14, M.stone, [0, 0.92, 0], null, 6)
		k.cyl(0.17, 0.17, 0.28, M.ink, [0, 1.13, 0], null, 6)
		for i in 6:
			var a := i * PI / 3.0 + PI / 6.0
			k.box(0.055, 0.28, 0.055, M.stone, [sin(a) * 0.19, 1.13, cos(a) * 0.19], [0, a, 0])
		k.cyl(0.22, 0.22, 0.035, M.stone, [0, 0.9975 + 0.0, 0], null, 6)
		k.cyl(0.22, 0.22, 0.035, M.stone, [0, 1.2875, 0], null, 6)
		k.cyl(0.07, 0.4, 0.2, M.stone, [0, 1.4, 0], null, 6)
		k.cyl(0.4, 0.4, 0.04, M.stone, [0, 1.3, 0], null, 6)
		for i in 6:
			var a := i * PI / 3.0
			k.sphere(0.035, M.stone, [sin(a) * 0.39, 1.34, cos(a) * 0.39], 6)
		k.cyl(0.075, 0.075, 0.045, M.stone, [0, 1.52, 0], null, 10)
		k.sphere(0.07, M.stone, [0, 1.6, 0], 10)
		k.mesh(Geo.cylinder(0.0, 0.05, 0.07, 10), M.stone, [0, 1.68, 0])
		k.mesh(Geo.g_sphere(ctx.cache, 10), M.leafLight, [0.12, 1.43, 0.05], [0, 0, 0.3], [0.18, 0.05, 0.14])  # moss on the roof
		c_cyl.call(lx, -2.95, 0.3, TY - 0.2, TY + 1.7)

	# ---------------------------------------------------------------- nobori (正一位稲荷大明神)
	for e in [[1.72, -4.35, -0.45, 0], [1.72, -6.95, -0.45, 1], [-0.95, -4.35, 0.45, 2], [-0.95, -8.15, 0.45, 3]]:
		var lx: float = e[0]
		var lz: float = e[1]
		var i: int = e[3]
		var g = sub.call(lx, TY, lz, e[2])
		var k = ctx.kit(g)
		k.box(0.15, 0.12, 0.15, M.stone, [0, 0.06, 0])
		k.cyl(0.014, 0.014, 2.32, M.bamboo, [0, 1.16, 0], null, 8)
		k.cyl(0.007, 0.007, 0.34, M.bamboo, [0.165, 2.2, 0], [0, 0, PI / 2.0], 6)
		var sheet := C.wave_sheet(0.3, 1.22, 0.02, 0.9, i * 0.37)
		var fm = mat.toon("#ffffff", {"map": tx.noboriTex[i], "paint": 0.02})
		k.mesh(sheet, fm, [0.168, 2.19 - 0.62, 0])
		k.mesh(C.back_side(sheet), fm, [0.168, 2.19 - 0.62, 0])
		c_cyl.call(lx, lz, 0.09, TY - 0.2, TY + 2.3)

	# ---------------------------------------------------------------- 手水鉢 (hand-washing basin)
	if true:
		var g = sub.call(2.95, TY, -2.35, -PI / 2.0)
		var k = ctx.kit(g)
		k.mesh(_tiled_box(1.0, 0.2, 0.62, 0.8), M.coping, [0, 0.1, 0])
		var bw = mat.toon("#ffffff", {"map": tx.stone, "paint": 0.05})
		for s in [-1, 1]:
			k.mesh(_tiled_box(0.9, 0.42, 0.07, 0.8), bw, [0, 0.41, s * 0.225])
		for s in [-1, 1]:
			k.mesh(_tiled_box(0.07, 0.42, 0.38, 0.8), bw, [s * 0.415, 0.41, 0])
		k.box(0.76, 0.12, 0.38, bw, [0, 0.26, 0])
		var wm = k.plane(0.76, 0.38, M.water, [0, 0.57, 0], [-PI / 2.0, 0, 0])
		wm.cast_shadow = false
		k.plane(0.5, 0.25, mat.decal("#ffffff", {"map": tx.chozu, "transparent": true}), [0, 0.42, 0.2615])
		for zz in [-0.1, 0.12]:
			k.cyl(0.011, 0.011, 0.9, M.bambooDark, [0, 0.631, zz], [0, 0, PI / 2.0], 8)
		var xs := [-0.22, 0.0, 0.22]
		for i in xs.size():
			var x: float = xs[i]
			var a := (i - 1) * 0.06
			k.cyl(0.034, 0.031, 0.055, M.bamboo, [x, 0.667, -0.1], null, 12)
			k.cyl(0.03, 0.03, 0.004, M.bambooDark, [x, 0.696, -0.1], null, 12)
			k.cyl(0.0075, 0.0075, 0.4, M.bamboo, [x + sin(a) * 0.2, 0.65, 0.1], [PI / 2.0 - 0.05, a, 0], 6)
		k.cyl(0.03, 0.034, 0.96, M.bamboo, [0.3, 0.48, -0.34], null, 10)
		var a3 := Vector3(0.3, 0.86, -0.34)
		var b3 := Vector3(0.08, 0.78, -0.06)
		var mid := (a3 + b3) * 0.5
		var dir := b3 - a3
		var pipe = k.mesh(Geo.cylinder(0.021, 0.021, dir.length(), 10), M.bamboo, [mid.x, mid.y, mid.z])
		pipe.set_quaternion(T.quat_from_unit_vectors(Vector3(0, 1, 0), dir.normalized()))
		var st = k.cyl(0.005, 0.005, 0.2, M.stream, [0.07, 0.675, -0.055], null, 6)
		st.cast_shadow = false
		c_box.call(2.95, -2.35, 0.64, 1.02, 0, TY - 0.2, TY + 0.75)

	# ---------------------------------------------------------------- hokora on a stone base + offering box + bell
	if true:
		K.mesh(_tiled_box(1.9, 0.28, 1.5, 0.8), M.coping, [0.4, TY + 0.14, -12.55])
		K.mesh(_tiled_box(1.5, 0.34, 1.16, 0.8), M.stone, [0.4, TY + 0.28 + 0.17, -12.7])
		c_box.call(0.4, -12.55, 1.9, 1.5, 0, TY - 0.2, TY + 1.8)
		var g = sub.call(0.4, TY + 0.62, -12.74, 0.0)
		g.scale = Vector3.ONE * 1.18
		var k = ctx.kit(g)
		k.box(1.0, 0.06, 0.9, M.woodDark, [0, 0.03, 0])
		k.box(0.7, 0.6, 0.5, M.wood, [0, 0.36, -0.08])
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				k.box(0.05, 0.62, 0.05, M.woodDark, [sx * 0.36, 0.37, -0.08 + sz * 0.26])
		k.plane(0.56, 0.5, mat.toon("#ffffff", {"map": tx.doors, "paint": 0.02}), [0, 0.35, 0.1735])
		k.box(0.78, 0.04, 0.58, M.woodDark, [0, 0.68, -0.08])
		for sx in [-1, 1]:
			k.box(0.025, 0.12, 0.025, M.woodDark, [sx * 0.46, 0.12, 0.4])
			k.box(0.02, 0.02, 0.4, M.woodMid, [sx * 0.46, 0.17, 0.22])
		k.box(0.3, 0.02, 0.02, M.woodMid, [-0.31, 0.17, 0.4])
		k.box(0.3, 0.02, 0.02, M.woodMid, [0.31, 0.17, 0.4])
		# gable infill + nagare roof (long front slope)
		var gable := Geo.extrude([[0.2, 0.66], [-0.36, 0.66], [-0.36, 0.8], [-0.12, 0.985], [0.2, 0.84]], 0.68).rotate_y(-PI / 2.0)
		k.mesh(gable, M.wood, [0, 0, 0])
		var slab_f := {"len": sqrt(0.66 * 0.66 + 0.31 * 0.31), "ang": atan2(0.31, 0.66)}
		var slab_b := {"len": sqrt(0.4 * 0.4 + 0.29 * 0.29), "ang": atan2(0.29, 0.4)}
		k.box(1.14, 0.055, slab_f["len"], M.copper, [0, 0.855 + 0.02, (0.54 - 0.12) / 2.0], [slab_f.ang, 0, 0])
		k.box(1.14, 0.055, slab_b["len"], M.copper, [0, 0.855 + 0.02, (-0.12 - 0.52) / 2.0], [-slab_b.ang, 0, 0])
		k.box(1.18, 0.05, 0.08, M.copperDark, [0, 1.03, -0.12])
		for x in [-0.3, 0, 0.3]:
			k.cyl(0.024, 0.024, 0.14, M.copperDark, [x, 1.075, -0.12], [PI / 2.0, 0, 0], 10)
			k.cyl(0.026, 0.026, 0.012, M.gold, [x, 1.075, -0.05], [PI / 2.0, 0, 0], 10)
			k.cyl(0.026, 0.026, 0.012, M.gold, [x, 1.075, -0.19], [PI / 2.0, 0, 0], 10)
		rope_with_shide(ctx, k, M, [-0.37, 0.64, 0.24], [0.37, 0.64, 0.24], 0.05, 0.024, [-0.2, 0.2])
		# bell + bell rope
		k.cyl(0.004, 0.004, 0.06, M.ink, [0, 0.75, 0.47], null, 4)
		k.sphere(0.045, M.gold, [0, 0.69, 0.47], 12)
		k.cyl(0.011, 0.013, 0.62, M.bellRope, [0, 0.35, 0.47], null, 8)
		for dx in [-0.02, 0.02]:
			k.cyl(0.006, 0.006, 0.12, M.red, [dx, 0.0, 0.47], null, 5)
		# offerings on the base
		for sx in [-1, 1]:
			k.cyl(0.028, 0.034, 0.12, M.porcelain, [sx * 0.42, 0.06, 0.3], null, 12)
			for i in 4:
				k.mesh(Geo.g_sphere(ctx.cache, 8), M.leafDark, [sx * 0.42 + (i - 1.5) * 0.02, 0.17 + (i % 2) * 0.03, 0.3 + ((i * 7) % 3 - 1) * 0.015], [0.3, i, 0.4], [0.05, 0.1, 0.03])
			k.cyl(0.02, 0.028, 0.08, M.porcelain, [sx * 0.2, 0.04, 0.36], null, 10)
			k.cyl(0.009, 0.012, 0.035, M.porcelain, [sx * 0.2, 0.097, 0.36], null, 8)
		k.cyl(0.06, 0.05, 0.02, M.porcelain, [0, 0.01, 0.36], null, 14)
		var dish = k.sphere(0.035, M.porcelain, [0, 0.025, 0.36], 10)
		dish.scale.y = 0.5
		# 賽銭箱
		var sb = sub.call(0.4, TY + 0.03, -11.43, 0.0)
		var s = ctx.kit(sb)
		s.box(0.62, 0.34, 0.38, M.woodDark, [0, 0.2, 0])
		s.box(0.66, 0.035, 0.42, M.woodMid, [0, 0.385, 0])
		for i in 6:
			s.box(0.56, 0.035, 0.035, M.woodMid, [0, 0.41, -0.15 + i * 0.06], [PI / 4.0, 0, 0])
		for x in [-0.29, 0.29]:
			s.box(0.06, 0.03, 0.4, M.gold, [x, 0.405, 0])
		s.box(0.64, 0.04, 0.4, M.woodDark, [0, 0.02, 0])
		s.plane(0.58, 0.3, mat.toon("#ffffff", {"map": tx.saisen, "paint": 0.02}), [0, 0.2, 0.1915])
		c_box.call(0.4, -11.43, 0.68, 0.44, 0, TY - 0.2, TY + 0.45)

	# ---------------------------------------------------------------- inari fox pair (key / jewel) on pedestals
	for e in [[-0.85, 0.32, "jewel"], [1.65, -0.32, "key"]]:
		var lx: float = e[0]
		var g = sub.call(lx, TY + 0.02, -10.35, 0.0)
		var k = ctx.kit(g)
		k.mesh(_tiled_box(0.52, 0.12, 0.52, 0.8), M.coping, [0, 0.06, 0])
		k.mesh(_tiled_box(0.38, 0.58, 0.38, 0.8), M.stone, [0, 0.12 + 0.29, 0])
		k.mesh(_tiled_box(0.46, 0.08, 0.46, 0.8), M.coping, [0, 0.74, 0])
		var fg := T.Group.new()
		fg.position = Vector3(0, 0.78, 0)
		fg.rotation.y = e[1]
		fg.scale = Vector3.ONE * 1.12
		g.add(fg)
		fox(ctx, ctx.kit(fg), M, e[2])
		c_box.call(lx, -10.35, 0.52, 0.52, 0, TY - 0.2, TY + 1.5)

	# ---------------------------------------------------------------- jizo shelter (地蔵堂) with three jizo, pinwheels
	if true:
		var JX := 3.3
		var JZ := -8.0
		var JR := -PI / 2.0
		var g = sub.call(JX, TY, JZ, JR)
		var k = ctx.kit(g)
		k.mesh(_tiled_box(1.7, 0.2, 0.86, 0.8), M.coping, [0, 0.1, 0])
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				k.box(0.07, 1.45, 0.07, M.woodDark, [sx * 0.76, 0.2 + 0.725, sz * 0.36])
		k.box(1.52, 1.34, 0.03, M.wood, [0, 0.2 + 0.67, -0.365])
		for sx in [-1, 1]:
			k.box(0.03, 0.8, 0.7, M.wood, [sx * 0.765, 0.2 + 0.4, 0])
		k.box(1.64, 0.09, 0.08, M.woodDark, [0, 1.62, 0.36])
		k.box(1.64, 0.09, 0.08, M.woodDark, [0, 1.62, -0.36])
		for sx in [-1, 1]:
			k.box(0.06, 0.06, 0.8, M.woodDark, [sx * 0.76, 1.62, 0])
		var gab := Geo.extrude([[-0.4, 1.66], [0.4, 1.66], [0, 1.99]], 0.05).rotate_y(-PI / 2.0)
		for sx in [-1, 1]:
			k.mesh(gab, M.wood, [sx * 0.76, 0, 0])
		var ra := atan2(0.36, 0.64)
		var rl := sqrt(0.64 * 0.64 + 0.36 * 0.36)
		k.box(1.98, 0.05, rl, M.slate, [0, 1.84, 0.315], [ra, 0, 0])
		k.box(1.98, 0.05, rl, M.slate, [0, 1.84, -0.315], [-ra, 0, 0])
		k.box(2.0, 0.06, 0.09, M.roofTin, [0, 2.03, 0])
		k.box(0.14, 0.36, 0.02, M.woodDark, [0, 1.38, 0.395])
		k.plane(0.113, 0.34, mat.toon("#ffffff", {"map": tx.jizoPlaque, "paint": 0.02}), [0, 1.38, 0.4065])
		# jizo statues
		var jz := [[-0.5, 0.86, false], [0.0, 1.0, true], [0.5, 0.78, false]]
		for i in jz.size():
			var jg := T.Group.new()
			jg.position = Vector3(jz[i][0], 0.2, -0.04)
			jg.rotation.y = (i - 1) * -0.08
			g.add(jg)
			jizo(ctx, ctx.kit(jg), M, jz[i][1], jz[i][2])
		# offerings: flower vases, a cup, a small incense stand
		for e in [[-0.25, ["#f2b5c8", "#f7e3a0", "#ffffff"]], [0.27, ["#e9a1c0", "#b9d6f0", "#f7e3a0"]]]:
			var x: float = e[0]
			var cols: Array = e[1]
			k.cyl(0.03, 0.036, 0.1, M.bambooDark, [x, 0.25, 0.28], null, 10)
			for j in cols.size():
				k.sphere(0.028, mat.toon(cols[j], {"paint": 0.02}), [x + (j - 1) * 0.03, 0.34 + (j % 2) * 0.03, 0.28 + (j - 1) * 0.01], 8)
			for j in 3:
				k.mesh(Geo.g_sphere(ctx.cache, 6), M.leafMid, [x + (j - 1) * 0.035, 0.31, 0.29], [0, j, 0.5], [0.03, 0.06, 0.02])
		k.cyl(0.025, 0.02, 0.05, M.porcelain, [-0.66, 0.225, 0.28], null, 10)
		k.box(0.14, 0.05, 0.08, M.stone, [0.0, 0.225, 0.3])
		# pinwheels (spinning, dynamic)
		for e in [[-0.7, 0.3, 0], [0.7, 0.3, 1]]:
			var x: float = e[0]
			var zz: float = e[1]
			k.cyl(0.02, 0.02, 0.16, M.bamboo, [x, 0.28, zz], null, 8)
			k.cyl(0.004, 0.004, 0.46, M.bambooDark, [x, 0.43, zz], null, 5)
			pinwheel(ctx, g, [x, 0.66, zz + 0.012], e[2])
		var p: Dictionary = W.call(JX, JZ)
		physics.addBox(p.x, p.z, 1.8, 0.95, f.rotY + JR, TY - 0.2, TY + 2.1)

	# ---------------------------------------------------------------- ema rack (絵馬掛所)
	if true:
		var EX := -3.25
		var EZ := -9.7
		var ER := PI / 2.0
		var g = sub.call(EX, TY, EZ, ER)
		var k = ctx.kit(g)
		for sx in [-1, 1]:
			k.mesh(_tiled_box(0.2, 0.1, 0.2, 0.8), M.coping, [sx * 0.74, 0.05, 0])
			k.box(0.08, 1.82, 0.08, M.woodDark, [sx * 0.74, 0.1 + 0.91, 0])
		var ra := atan2(0.15, 0.32)
		var rl := sqrt(0.32 * 0.32 + 0.15 * 0.15)
		k.box(1.84, 0.04, rl, M.woodDark, [0, 1.99, 0.16], [ra, 0, 0])
		k.box(1.84, 0.04, rl, M.woodDark, [0, 1.99, -0.16], [-ra, 0, 0])
		k.box(1.86, 0.05, 0.07, M.woodMid, [0, 2.07, 0])
		k.box(1.56, 0.08, 0.06, M.woodDark, [0, 1.9, 0])
		k.box(0.54, 0.14, 0.02, M.woodMid, [0, 1.76, 0.03])
		k.plane(0.5, 0.125, mat.toon("#ffffff", {"map": tx.emaSign, "paint": 0.02}), [0, 1.76, 0.0405])
		var bars := [0.95, 1.24, 1.53]
		for y in bars:
			k.box(1.44, 0.035, 0.035, M.woodMid, [0, y, 0])
		var cell := 0
		var ema_geos := {}
		var EMA: Dictionary = ST.EMA
		for bi in bars.size():
			var by: float = bars[bi]
			for side in [1, -1]:
				var n := 12 if side > 0 else 11
				for i in n:
					if rnd.f() < (0.15 if side < 0 else 0.06):
						continue
					var x: float = -0.64 + (i + (0.5 if side < 0 else 0.0)) * (1.28 / (n - 0.5)) + (rnd.f() - 0.5) * 0.03
					var c: int = (cell * 7 + bi * 3) % int(tx.wishes)
					cell += 1
					if not ema_geos.has(c):
						var ex: float = (c % int(EMA.cols)) * EMA.cw
						var ey: float = floori(c / float(EMA.cols)) * EMA.ch
						ema_geos[c] = C.ema_geo(0.17, 0.114, 0.008, [ex, ey, EMA.cw, EMA.ch], tx.emaBack, EMA.W, EMA.H)
					var r0: float = side * 0.06 + (rnd.f() - 0.5) * 0.06
					var r1: float = PI + (rnd.f() - 0.5) * 0.2 if side < 0 else (rnd.f() - 0.5) * 0.2
					var r2: float = (rnd.f() - 0.5) * 0.22
					var em = k.mesh(ema_geos[c], M.ema, [x, by - 0.108 - (i % 3) * 0.006, side * (0.024 + (i % 2) * 0.009)], [r0, r1, r2])
					em.cast_shadow = false
					var cord = k.cyl(0.0025, 0.0025, 0.06, M.cord, [x, by - 0.025, side * 0.022], [side * 0.3, 0, 0], 4)
					cord.cast_shadow = false
		var p: Dictionary = W.call(EX, EZ)
		physics.addBox(p.x, p.z, 1.7, 0.42, f.rotY + ER, TY - 0.2, TY + 2.1)

	# ---------------------------------------------------------------- community notice board (last year's 夏まつり poster)
	if true:
		var g = sub.call(-3.0, TY, -1.38, 0.06)
		var k = ctx.kit(g)
		for sx in [-1, 1]:
			k.box(0.07, 1.95, 0.07, M.woodDark, [sx * 0.7, 0.975, -0.02])
		k.box(1.34, 0.86, 0.035, M.woodMid, [0, 1.25, 0])
		k.plane(1.26, 0.78, M.notice, [0, 1.25, 0.0185])
		k.box(1.4, 0.05, 0.06, M.woodDark, [0, 1.7, 0.01])
		k.box(1.4, 0.05, 0.06, M.woodDark, [0, 0.8, 0.01])
		for sx in [-1, 1]:
			k.box(0.05, 0.95, 0.06, M.woodDark, [sx * 0.675, 1.25, 0.01])
		k.box(0.96, 0.13, 0.03, M.woodDark, [0, 1.8, 0])
		k.plane(0.9, 0.1125, M.noticeHead, [0, 1.8, 0.0155])
		k.box(1.6, 0.035, 0.36, M.roofTin, [0, 1.92, 0.03], [0.16, 0, 0])
		var p: Dictionary = W.call(-3.0, -1.38)
		physics.addBox(p.x, p.z, 1.5, 0.16, f.rotY + 0.06, TY - 0.2, TY + 1.95)

	# ---------------------------------------------------------------- fire-extinguisher box (south front corner)
	if true:
		var p: Dictionary = W.call(3.72, -1.3)
		Scatter.fire_box(ctx, H, {"x": p.x, "z": p.z, "rotY": f.rotY}, TY + 0.03)

	# ---------------------------------------------------------------- evergreen trees (鎮守の森) + shrubs, moss
	tree(ctx, K, M, [-3.2, TY, -12.95], 2.5, 1.0, rnd, 0)
	tree(ctx, K, M, [3.2, TY, -12.85], 2.9, 1.15, rnd, 1)
	c_cyl.call(-3.2, -12.95, 0.2, TY - 0.2, TY + 2.5)
	c_cyl.call(3.2, -12.85, 0.22, TY - 0.2, TY + 2.9)
	for e in [[3.45, -4.3, 0.55, true], [-3.55, -3.9, 0.5, true], [3.55, -10.9, 0.6, true], [-0.95, -13.2, 0.42, false], [1.85, -13.2, 0.42, false], [-3.55, -11.5, 0.45, false], [2.55, -13.25, 0.38, true]]:
		bush(ctx, K, M, [e[0], TY, e[1]], e[2], rnd, e[3])
		c_cyl.call(e[0], e[1], e[2] * 0.7, TY - 0.2, TY + e[2] * 1.6)
	for e in [[-3.6, -12.1, 1.2], [3.6, -6.1, 0.9], [-1.25, -3.35, 0.7], [2.15, -3.25, 0.6], [0.4, -11.95, 1.6], [-3.5, -1.2, 0.8], [3.65, -9.4, 1.0], [-2.1, -13.4, 1.1]]:
		var s: float = e[2]
		var mm = K.plane(s, s * 0.7, M.moss, [e[0], TY + 0.004, e[1]], [-PI / 2.0, 0, rnd.f() * 3.0])
		mm.cast_shadow = false


## tiledBox: a box whose UVs repeat every tu x tv metres on each face.
static func _tiled_box(w: float, h: float, d: float, tu: float, tv: float = -1.0) -> T.Geometry:
	if tv < 0.0:
		tv = tu
	var g := Geo.box(w, h, d)
	var n: T.Attr = g.attributes.normal
	var uv: T.Attr = g.attributes.uv
	for i in uv.count():
		var ax := absf(n.get_x(i))
		var ay := absf(n.get_y(i))
		var su := d if ax > 0.5 else w
		var sv := d if ay > 0.5 else h
		uv.set_xy(i, uv.get_x(i) * su / tu, uv.get_y(i) * sv / tv)
	return g


## ell: a scaled shared sphere.
static func _ell(ctx, k, m, pos, size, rot = null):
	return k.mesh(Geo.g_sphere(ctx.cache, 14), m, pos, rot, size)


# ------------------------------------------------------------------ pieces

## The moss splat canvas (seeded Lehmer draws, local to the canvas): a sized stand-in.
static func moss_tex(ctx):
	return ctx.tex.draw(128, 128, null, {"key": "props.shrine.moss"})


## Straw rope along a sagging curve with zig-zag paper streamers (shide). Coordinates in the kit's frame.
static func rope_with_shide(ctx, k, M: Dictionary, a: Array, b: Array, sag: float, r: float, shide_x: Array) -> void:
	var pts := Geo.catenary(a, b, sag, 16)
	k.mesh(Geo.tube_catmull(pts, false, 20, r, 8, false), M.rope, [0, 0, 0])
	for s in [a, b]:
		k.sphere(r * 1.15, M.rope, s, 8)
	for x in shide_x:
		var t: float = (x - a[0]) / (b[0] - a[0])
		var y: float = a[1] + (b[1] - a[1]) * t - sag * 4.0 * t * (1.0 - t) - r
		var zz: float = a[2] + r * 0.6
		for i in 4:
			var pl = k.plane(0.034, 0.05, M.shide, [x + (0.014 if i % 2 else -0.006), y - 0.03 - i * 0.047, zz + i * 0.002], [0, 0.15, (-0.06 if i % 2 else 0.06)])
			pl.cast_shadow = false


static func fox(ctx, k, M: Dictionary, holds: String) -> void:
	var m = M.statue
	var limb := func(a: Array, b: Array, r0: float, r1: float):
		var A := Vector3(a[0], a[1], a[2])
		var B := Vector3(b[0], b[1], b[2])
		var d := B - A
		var mid := (A + B) * 0.5
		var c = k.mesh(Geo.cylinder(r1, r0, d.length(), 10), m, [mid.x, mid.y, mid.z])
		c.set_quaternion(T.quat_from_unit_vectors(Vector3(0, 1, 0), d.normalized()))
		return c
	k.box(0.28, 0.05, 0.36, m, [0, 0.025, 0])
	_ell(ctx, k, m, [0, 0.12, -0.05], [0.23, 0.19, 0.29])  # haunches
	for s in [-1, 1]:
		_ell(ctx, k, m, [s * 0.1, 0.05, 0.03], [0.07, 0.06, 0.15])  # hind feet
	limb.call([0, 0.14, -0.04], [0, 0.44, 0.02], 0.1, 0.055)  # slender torso
	_ell(ctx, k, m, [0, 0.31, 0.06], [0.12, 0.22, 0.1])  # chest
	for s in [-1, 1]:
		limb.call([s * 0.038, 0.03, 0.115], [s * 0.035, 0.3, 0.07], 0.026, 0.03)  # front legs
		_ell(ctx, k, m, [s * 0.038, 0.03, 0.13], [0.05, 0.035, 0.07])
		k.mesh(Geo.cylinder(0.004, 0.03, 0.115, 8), m, [s * 0.042, 0.62, 0.05], [-0.12, 0, -s * 0.24])
		k.mesh(Geo.g_sphere(ctx.cache, 8), M.ink, [s * 0.034, 0.555, 0.112], [0, 0, s * 0.42], [0.028, 0.008, 0.01])
	limb.call([0, 0.42, 0.02], [0, 0.52, 0.05], 0.05, 0.045)  # neck
	_ell(ctx, k, m, [0, 0.545, 0.06], [0.11, 0.1, 0.12])  # head
	k.mesh(Geo.cylinder(0.011, 0.04, 0.13, 10), m, [0, 0.52, 0.165], [PI / 2.0 + 0.2, 0, 0])
	k.sphere(0.01, M.ink, [0, 0.508, 0.232], 6)
	for e in [[0, 0.1, -0.2, 0.065], [0.02, 0.22, -0.23, 0.08], [0.035, 0.35, -0.22, 0.078], [0.045, 0.47, -0.18, 0.06], [0.045, 0.56, -0.13, 0.038], [0.04, 0.61, -0.09, 0.02]]:
		var r: float = e[3]
		_ell(ctx, k, m, [e[0], e[1], e[2]], [r * 2.0, r * 2.3, r * 2.0])
	k.mesh(Geo.cylinder(0.05, 0.1, 0.11, 16, 1, true, -PI * 0.56, PI * 1.12), M.red, [0, 0.42, 0.035])
	if holds == "key":
		k.cyl(0.008, 0.008, 0.1, M.gold, [0, 0.495, 0.2], [0, 0, PI / 2.0], 8)
		k.mesh(Geo.torus(0.015, 0.005, 6, 12), M.gold, [0.062, 0.495, 0.2])
	else:
		k.sphere(0.022, M.gold, [0, 0.49, 0.222], 10)


static func jizo(ctx, k, M: Dictionary, s: float, cap: bool) -> void:
	var m = M.statue
	k.cyl(0.15 * s, 0.13 * s, 0.07 * s, M.stone, [0, 0.035 * s, 0], null, 12)
	k.mesh(Geo.cylinder(0.1 * s, 0.135 * s, 0.34 * s, 14), m, [0, 0.07 * s + 0.17 * s, 0])
	_ell(ctx, k, m, [0, 0.41 * s, 0], [0.2 * s, 0.13 * s, 0.19 * s])
	k.sphere(0.086 * s, m, [0, 0.53 * s, 0.005], 14)
	k.mesh(Geo.cylinder(0.1 * s, 0.152 * s, 0.16 * s, 16, 1, true, -PI * 0.56, PI * 1.12), M.red, [0, 0.37 * s, 0.004])
	k.mesh(Geo.torus(0.083 * s, 0.014 * s, 6, 16), M.red, [0, 0.452 * s, 0.0], [PI / 2.0, 0, 0])
	for sx in [-1, 1]:
		k.box(0.024 * s, 0.005 * s, 0.006, M.ink, [sx * 0.03 * s, 0.535 * s, 0.083 * s])
	if cap:
		k.mesh(Geo.sphere(0.093 * s, 14, 7, 0, PI * 2.0, 0, PI * 0.52), M.redKnit, [0, 0.54 * s, 0.0])


static func pinwheel(ctx, parent, pos: Array, i: int) -> void:
	# static proxy in the jizo frame -> world transform for the dynamic head
	var proxy := T.Obj3D.new()
	proxy.position = Vector3(pos[0], pos[1], pos[2])
	parent.add(proxy)
	var wm: Transform3D = Scatter.world_of(proxy)
	var outer := T.Group.new()
	outer.position = wm.origin
	outer.set_quaternion(wm.basis.get_rotation_quaternion())
	outer.scale = wm.basis.get_scale()
	var spin := T.Group.new()
	outer.add(spin)
	var hex: Array = ["#f3a6c0", "#9fd0f0", "#f7df86", "#a7dcb5"] if i else ["#f7df86", "#f3a6c0", "#a7dcb5", "#9fd0f0"]
	var cols: Array = hex.map(func(h): return T.color(h))
	# 4 blades + a pin head merged into ONE vertex-coloured mesh (one draw call per pinwheel)
	var P := PackedFloat32Array()
	var Cc := PackedFloat32Array()
	for b in 4:
		var a := b * PI / 2.0
		var ca := cos(a)
		var sa := sin(a)
		var tri := [[0.0, 0.0, 0.0], [0.075, 0.0, 0.012], [0.075, 0.075, 0.0]]
		for q in tri:
			P.append_array([q[0] * ca - q[1] * sa, q[0] * sa + q[1] * ca, q[2]])
			Cc.append_array([cols[b].r, cols[b].g, cols[b].b])
	var oct_v := [1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1]
	var oct_i := [0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2, 1, 2, 5, 1, 5, 3, 1, 3, 4, 1, 4, 2]
	var pin_g := Geo.polyhedron(oct_v, oct_i, 0.011, 0)
	var pp: T.Attr = pin_g.attributes.position
	var cw := T.color("#f6f3ec")
	for j in pp.count():
		P.append_array([pp.get_x(j), pp.get_y(j), pp.get_z(j) + 0.006])
		Cc.append_array([cw.r, cw.g, cw.b])
	var geo := T.Geometry.new()
	geo.set_attribute("position", T.Attr.new(P, 3))
	geo.set_attribute("color", T.Attr.new(Cc, 3))
	var uvz := PackedFloat32Array()
	uvz.resize(P.size() / 3 * 2)
	geo.set_attribute("uv", T.Attr.new(uvz, 2))
	geo.compute_vertex_normals()
	var head := T.MeshObj.new(geo, ctx.mat.toon("#ffffff", {"vertexColors": true, "side": "double", "paint": 0.02}))
	head.cast_shadow = true
	spin.add(head)
	ctx.add(outer)
	var w0 := 3.2 + i * 0.9
	ctx.on_update(func(_dt, t): spin.rotation.z = -(t * w0 + sin(t * 0.63 + i) * 1.6))


# Evergreen foliage (鎮守の森 camphor / oak, camellia bushes): smooth puff-scalloped clouds from
# lib/foliage (welded surfaces, blended normals, baked colour + procedural leaf clumps) instead of
# faceted icospheres.
const EVERGREEN := {
	"light": {"top": "#b3d38a", "mid": "#80aa68", "base": "#57835a"},
	"mid": {"top": "#94bd72", "mid": "#5f8e5b", "base": "#416b51"},
	"dark": {"top": "#7fa865", "mid": "#4c7a52", "base": "#34594a"},
}
static var _lobes := {}


## unit-radius canopy lobe (centred), cached per tone/variant
static func lobe_geo(tone: String, v: int) -> T.Geometry:
	var k := tone + str(v)
	if not _lobes.has(k):
		_lobes[k] = Fol.shrub_geometry({"rx": 1, "ry": 1, "rz": 1, "detail": 3, "flatBottom": false, "cutBottom": false, "lumps": 0.26, "freq": 1.7,
			"puff": 0.42, "puffAmp": 0.36, "seed": 90 + v * 13 + tone.length(), "colors": EVERGREEN[tone], "normalBlend": 0.55}).clone().translate(0, -0.55, 0)
	return _lobes[k]


static func tree(ctx, K, M: Dictionary, pos: Array, trunk_h: float, s: float, rnd, seed: int) -> void:
	var x: float = pos[0]
	var y: float = pos[1]
	var z: float = pos[2]
	var fm = Fol.foliage_material(ctx)
	K.mesh(Geo.cylinder(0.09 * s, 0.16 * s, trunk_h, 10), M.trunk, [x, y + trunk_h / 2.0, z])
	for i in 2:
		var a := i * 2.6 + seed
		K.mesh(Geo.cylinder(0.03 * s, 0.06 * s, 1.0 * s, 7), M.trunk, [x + sin(a) * 0.3, y + trunk_h * 0.75, z + cos(a) * 0.3], [cos(a) * 0.7, 0, -sin(a) * 0.7])
	var n := 12
	for i in n:
		var a := i * 2.399 + seed
		var rr := (0.3 + 0.7 * ((i * 37) % 11) / 11.0) * 1.1 * s
		var hy := trunk_h + 0.3 + ((i * 53) % 13) / 13.0 * 2.2 * s
		var r: float = (0.62 + rnd.f() * 0.35) * s * (1.1 - 0.25 * (hy - trunk_h) / (2.4 * s))
		var cx := x + sin(a) * rr
		var cz := z + cos(a) * rr * 0.8
		var lit := sin(a) < -0.2 or hy > trunk_h + 1.6 * s  # west / top side catches the sun
		var rot := [rnd.f(), rnd.f(), rnd.f()]
		K.mesh(lobe_geo("light" if lit else ("mid" if i % 3 else "dark"), i % 3), fm, [cx, y + hy, cz], [0, rot[1] * 6.28, 0], [r, r * 0.86, r])
	K.mesh(lobe_geo("mid", 1), fm, [x, y + trunk_h + 2.3 * s, z], [0, 0.5, 0], [0.6 * s, 0.7 * s, 0.6 * s])


static func bush(ctx, K, M: Dictionary, pos: Array, s: float, rnd, flowers: bool) -> void:
	var x: float = pos[0]
	var y: float = pos[1]
	var z: float = pos[2]
	for i in 4:  # same RNG draws as the old 4-lobe bush
		rnd.f()
		rnd.f()
		rnd.f()
	var v: int = int(floor(s * 100)) % 3
	# camellia / evergreen mound matching the old 4-lobe footprint (~1.1 s wide, ~1.2 s tall)
	var geo: T.Geometry = Fol.shrub_geometry({"rx": 0.72, "ry": 0.7, "rz": 0.66, "seed": 120 + v * 5, "detail": 5, "lumps": 0.2, "puff": 0.26, "colors": EVERGREEN.mid})
	var m = K.mesh(geo, Fol.foliage_material(ctx), [x, y - 0.02, z], [0, v * 2.1, 0], [s, s, s])
	if flowers:  # red / white camellia blossoms
		for i in 9:
			rnd.f()
			rnd.f()
			rnd.f()
		var fl := T.MeshObj.new(Fol.flower_geometry(geo, {"density": 9, "size": 0.045, "petals": 5, "colors": ["#d9434f", "#e0606f", "#d9434f", "#f1efe9"], "seed": 7 + v, "minY": 0.25}),
			ctx.mat.toon("#ffffff", {"vertexColors": true, "paint": 0.02}))
		fl.cast_shadow = false
		ctx.no_outline(fl)
		m.add(fl)
