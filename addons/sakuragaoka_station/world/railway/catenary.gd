# railway/catenary.js: dark steel poles (centre poles with double cantilevers near the station, portal
# truss beams elsewhere), insulators, messenger and contact wire with zig-zag stagger, droppers, feeders
# and an overhead ground wire. All wires go through ctx.wires.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")

const CONTACT_Y := 5.15
const MESSENGER_Y := 6.1
const FEEDER_Y := 8.2
const DIST_Y := 10.42
const GROUND_WIRE_Y := 11.05
const DIST_Z := [-42.5, -43.0, -43.5]


static func build_catenary(ctx, root, TX, E: Dictionary) -> Dictionary:
	var mat = ctx.mat
	var geo = ctx.geo
	var L = ctx.L
	var k = ctx.kit(root)
	var M := {
		"pole": mat.toon("#5d616a", {"paint": 0.08}),
		"arm": mat.toon("#8d939b", {"paint": 0.05}),
		"dark": mat.toon("#4b4e57", {"paint": 0.05}),
		"ins": mat.toon("#8f5d4a", {"paint": 0.05}),
		"insW": mat.toon("#d9d6cd", {"paint": 0.05}),
		"conc": mat.toon("#b9b7af", {"paint": 0.08}),
		"plateW": mat.toon("#eeebe3"),
	}

	var ins_pts := []
	for q in [[0.001, 0], [0.026, 0.0], [0.026, 0.035], [0.074, 0.07], [0.028, 0.105], [0.074, 0.15], [0.028, 0.19], [0.074, 0.235], [0.026, 0.27], [0.026, 0.3], [0.001, 0.3]]:
		ins_pts.append(Vector2(q[0], q[1]))
	var ins_geo := Geo.lathe(ins_pts, 7)
	ins_geo.compute_vertex_normals()
	var orient := func(mesh, a: Array, b: Array) -> void:
		var d := Vector3(b[0] - a[0], b[1] - a[1], b[2] - a[2])
		mesh.set_quaternion(T.quat_from_unit_vectors(Vector3.UP, d.normalized()))
	var pipe := func(a: Array, b: Array, r: float, m, seg: int = 8):
		var length := Vector3(b[0] - a[0], b[1] - a[1], b[2] - a[2]).length()
		if length < 1e-4:
			return null
		var mesh = k.mesh(Geo.g_cyl(ctx.cache, seg), m, [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0, (a[2] + b[2]) / 2.0], null, [r * 2, length, r * 2])
		orient.call(mesh, a, b)
		return mesh
	var bar := func(a: Array, b: Array, w: float, m):
		var length := Vector3(b[0] - a[0], b[1] - a[1], b[2] - a[2]).length()
		var mesh = k.mesh(Geo.g_box(ctx.cache), m, [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0, (a[2] + b[2]) / 2.0], null, [w, length, w])
		orient.call(mesh, a, b)
		return mesh
	var insulator := func(a: Array, b: Array, m = null):
		if m == null:
			m = M.ins
		var length := Vector3(b[0] - a[0], b[1] - a[1], b[2] - a[2]).length()
		var mesh = k.mesh(ins_geo, m, [a[0], a[1], a[2]], null, [1, length / 0.3, 1])
		orient.call(mesh, a, b)
		return mesh
	var tex_plate := func(reg: Dictionary, w: float, h: float, pos: Array, rot_y: float, back = null):
		if back == null:
			back = M.plateW
		var g = k.group(pos, rot_y)
		var kk = ctx.kit(g)
		kk.box(w + 0.02, h + 0.02, 0.012, back, [0, 0, 0])
		TX.sign_mesh(kk, reg, w, h, [0, 0, 0.0075])
		return g

	var top_crossarm := func(x: float, zc: float) -> void:
		k.box(0.09, 0.09, 1.5, M.dark, [x, DIST_Y - 0.2, zc])
		for s in [-1, 1]:
			bar.call([x, DIST_Y - 0.62, zc], [x, DIST_Y - 0.22, zc + s * 0.6], 0.03, M.dark)
		for zd in DIST_Z:
			pipe.call([x, DIST_Y - 0.16, zd], [x, DIST_Y - 0.12, zd], 0.02, M.dark, 6)
			insulator.call([x, DIST_Y - 0.14, zd], [x, DIST_Y - 0.005, zd], M.insW)
		k.box(0.07, 0.12, 0.07, M.dark, [x, GROUND_WIRE_Y - 0.03, zc])

	var PLAN := [
		[-420, "C"], [-385, "P"], [-340, "P"], [-295, "C"], [-250, "C"], [-205, "P"], [-160, "P"], [-115, "C"], [-70, "C"], [-25, "C"],
		[20, "C"], [62, "P"], [84, "P"], [106, "P"], [150, "C"], [195, "C"], [240, "P"], [285, "P"], [330, "C"], [375, "C"], [420, "P"],
	]
	var poles := []
	for i in PLAN.size():
		poles.append({"x": float(PLAN[i][0]), "type": PLAN[i][1], "i": i, "sA": -0.2 if i % 2 else 0.2, "sB": 0.2 if i % 2 else -0.2, "no": 61 + i})
	var plate_no := func(P: Dictionary) -> int:
		return P.no if absf(P.x) <= 200 else 50 + (P.i % 3)
	var pole_plate := func(P: Dictionary) -> Dictionary:
		var no: int = plate_no.call(P)
		return TX.plate([{"t": "桜川線", "s": 26, "wt": 700}, {"t": "No.%d" % no, "s": 44}], "pole%d" % no, 256, 128)
	var zA: float = E.zA
	var zB: float = E.zB
	var z_south_pole := -37.6
	var z_north_pole := -48.4
	var colliders := []

	var arm_set := func(x: float, z_base: float, zT: float, s: float, side: float, hang_from_y = null) -> void:
		var zw := zT + s
		var z_end_up := zw + side * 0.2
		var zV := zw - side * 0.32
		pipe.call([x, 6.32, z_base], [x, 6.32, z_base + side * 0.1], 0.032, M.arm)
		insulator.call([x, 6.32, z_base + side * 0.1], [x, 6.32, z_base + side * 0.4])
		pipe.call([x, 6.32, z_base + side * 0.4], [x, 6.32, z_end_up], 0.03, M.arm)
		pipe.call([x, 5.5, z_base], [x, 5.5, z_base + side * 0.1], 0.03, M.arm)
		insulator.call([x, 5.5, z_base + side * 0.1], [x, 5.5, z_base + side * 0.4])
		if (zV - (z_base + side * 0.4)) * side > 0.04:
			pipe.call([x, 5.5, z_base + side * 0.4], [x, 5.5, zV], 0.028, M.arm)
		pipe.call([x, 5.5, zV], [x, 6.32, zV], 0.022, M.arm)
		if hang_from_y != null:
			pipe.call([x, hang_from_y, z_base], [x, 6.34, z_end_up - side * 0.12], 0.016, M.dark, 6)
		k.box(0.05, 0.16, 0.05, M.dark, [x, 6.22, zw])
		pipe.call([x, 5.5, zV], [x + 0.35, CONTACT_Y + 0.03, zw], 0.012, M.dark, 6)
		k.box(0.08, 0.035, 0.035, M.dark, [x + 0.37, CONTACT_Y + 0.02, zw])

	for P in poles:
		var x: float = P.x
		if P.type == "C":
			var zc := -43.0
			k.boxb(0.52, 0.46, 0.46, M.conc, [x, -0.31, zc])
			k.box(0.3, 0.03, 0.3, M.dark, [x, 0.165, zc])
			k.cyl(0.098, 0.13, 10.95, M.pole, [x, 0.15 + 5.475, zc], null, 12)
			k.cyl(0.07, 0.1, 0.08, M.dark, [x, 11.14, zc], null, 10)
			top_crossarm.call(x, zc)
			for a in [[zA, P.sA, 1.0], [zB, P.sB, -1.0]]:
				arm_set.call(x, zc + a[2] * 0.11, a[0], a[1], a[2], 7.35)
			for y in [7.35, 6.32, 5.5]:
				k.box(0.26, 0.08, 0.26, M.dark, [x, y, zc])
			k.box(0.08, 0.08, 1.36, M.dark, [x, 7.98, zc])
			for zf in [-42.65, -43.35]:
				pipe.call([x, 8.02, zf], [x, 8.06, zf], 0.02, M.dark, 6)
				insulator.call([x, 8.04, zf], [x, FEEDER_Y - 0.01, zf], M.insW)
			colliders.append({"x": x, "z": zc, "r": 0.27})
			tex_plate.call(pole_plate.call(P), 0.24, 0.12, [x, 1.9, zc + 0.125], 0.0)
			if absf(x) < 130.0:
				tex_plate.call(TX.sign.hv, 0.24, 0.18, [x, 2.65, zc + 0.125], 0.0, mat.toon("#35303c"))
			if x == -25.0 or x == 20.0:
				tex_plate.call(TX.num("1", "#f4f2ec", "#35303c", "番線"), 0.26, 0.26, [x, 3.3, zc + 0.125], 0.0)
				tex_plate.call(TX.num("2", "#f4f2ec", "#35303c", "番線"), 0.26, 0.26, [x, 3.3, zc - 0.125], PI)
				tex_plate.call(pole_plate.call(P), 0.24, 0.12, [x, 1.9, zc - 0.125], PI)
		else:
			for zp in [z_south_pole, z_north_pole]:
				var gy: float = L.height_at(x, zp)
				k.boxb(0.64, 0.5, 0.64, M.conc, [x, gy - 0.35, zp])
				k.box(0.34, 0.03, 0.34, M.dark, [x, gy + 0.165, zp])
				k.cyl(0.13, 0.155, 7.9 - gy - 0.15, M.pole, [x, (7.9 + gy + 0.15) / 2.0, zp], null, 12)
				k.cyl(0.09, 0.135, 0.08, M.dark, [x, 7.94, zp], null, 10)
				colliders.append({"x": x, "z": zp, "r": 0.34})
			var z0 := z_south_pole + 0.3
			var z1 := z_north_pole - 0.3
			var yb := 7.3
			var yt := 7.72
			var hx := 0.16
			for dx in [-hx, hx]:
				for y in [yb, yt]:
					k.box(0.055, 0.055, z0 - z1, M.pole, [x + dx, y, (z0 + z1) / 2.0])
			var n_panel := 12
			for i in n_panel:
				var za := z0 - (z0 - z1) * i / n_panel
				var zb2 := z0 - (z0 - z1) * (i + 1) / n_panel
				for dx in [-hx, hx]:
					bar.call([x + dx, yt if i % 2 else yb, za], [x + dx, yb if i % 2 else yt, zb2], 0.032, M.pole)
				if i % 3 == 0:
					bar.call([x - hx, yb, za], [x + hx, yb, za], 0.03, M.pole)
			for zp in [z_south_pole, z_north_pole]:
				k.box(0.42, 0.62, 0.36, M.dark, [x, (yb + yt) / 2.0, zp])
			for a in [[zA, P.sA, -1.0], [zB, P.sB, 1.0]]:
				var z_drop: float = a[0] + a[1] - a[2] * 0.95
				pipe.call([x, yb, z_drop], [x, 5.46, z_drop], 0.034, M.arm)
				k.box(0.1, 0.12, 0.1, M.dark, [x, yb - 0.04, z_drop])
				arm_set.call(x, z_drop, a[0], a[1], a[2], 7.05)
			if x == 62.0 or x == 84.0 or x == 106.0:
				var zx: float = -41.65 if x == 62.0 else (E.xo.zc.call(84.0) if x == 84.0 else -44.6)
				var z_drop: float = zx + (0.95 if x == 106.0 else -0.95)
				var xo := x + 0.4
				bar.call([x - hx, yb, z_drop], [xo, yb - 0.02, z_drop], 0.05, M.pole)
				pipe.call([xo, yb, z_drop], [xo, 5.46, z_drop], 0.03, M.arm)
				arm_set.call(xo, z_drop, zx, 0.0, -1.0 if x == 106.0 else 1.0, 7.05)
			for zf in [-42.65, -43.35]:
				pipe.call([x, yt, zf], [x, yt + 0.16, zf], 0.022, M.dark, 6)
				insulator.call([x, yt + 0.16, zf], [x, FEEDER_Y - 0.01, zf], M.insW)
			pipe.call([x, yt, -43], [x, GROUND_WIRE_Y + 0.05, -43], 0.075, M.pole, 10)
			for s in [-1, 1]:
				bar.call([x, yt, -43 + s * 1.1], [x, yt + 1.1, -43 + s * 0.06], 0.045, M.pole)
			top_crossarm.call(x, -43.0)
			tex_plate.call(pole_plate.call(P), 0.24, 0.12, [x, 1.9, z_south_pole + 0.155], 0.0)
			if absf(x) < 130.0:
				tex_plate.call(TX.sign.hv, 0.24, 0.18, [x, 2.65, z_south_pole + 0.155], 0.0, mat.toon("#35303c"))

	var W = ctx.wires
	var C := {"contact": "#5a4943", "messenger": "#4b4752", "dropper": "#6b6570", "feeder": "#3e3a46", "ground": "#56525e"}
	for tk in [[zA, "sA"], [zB, "sB"]]:
		var zT: float = tk[0]
		for i in poles.size() - 1:
			var a: Dictionary = poles[i]
			var b: Dictionary = poles[i + 1]
			var span: float = b.x - a.x
			var za: float = zT + a[tk[1]]
			var zb: float = zT + b[tk[1]]
			var sag := 0.47 * pow(span / 45.0, 2)
			var pre := 0.03
			W.add(geo.catenary([a.x, MESSENGER_Y, za], [b.x, MESSENGER_Y, zb], sag, 18), {"width": 0.022, "color": C.messenger})
			W.add(geo.catenary([a.x, CONTACT_Y, za], [b.x, CONTACT_Y, zb], pre, 8), {"width": 0.024, "color": C.contact})
			var n := maxi(1, int(T.js_round(span / 5.0)) - 1)
			for j in range(1, n + 1):
				var t := float(j) / (n + 1)
				var x: float = a.x + span * t
				var z := za + (zb - za) * t
				var ym := MESSENGER_Y - sag * 4 * t * (1 - t)
				var yc := CONTACT_Y - pre * 4 * t * (1 - t)
				W.add([[x, yc + 0.012, z], [x, ym - 0.01, z]], {"width": 0.008, "color": C.dropper})
	var pts := [[62.0, -41.65, 0.16], [84.0, E.xo.zc.call(84.0), 0.0], [106.0, -44.6, 0.1]]
	for i in 2:
		var xa: float = pts[i][0]
		var za: float = pts[i][1]
		var ra: float = pts[i][2]
		var xb: float = pts[i + 1][0]
		var zb: float = pts[i + 1][1]
		var rb: float = pts[i + 1][2]
		var span := xb - xa
		var sag := 0.47 * pow(span / 45.0, 2)
		W.add(geo.catenary([xa, MESSENGER_Y + ra, za], [xb, MESSENGER_Y + rb, zb], sag, 12), {"width": 0.022, "color": C.messenger})
		W.add([[xa, CONTACT_Y + ra, za], [xb, CONTACT_Y + rb, zb]], {"width": 0.024, "color": C.contact})
		var n := int(T.js_round(span / 5.0)) - 1
		for j in range(1, n + 1):
			var t := float(j) / (n + 1)
			var x := xa + span * t
			var z := za + (zb - za) * t
			W.add([[x, CONTACT_Y + ra + (rb - ra) * t + 0.012, z], [x, MESSENGER_Y + ra + (rb - ra) * t - sag * 4 * t * (1 - t) - 0.01, z]], {"width": 0.008, "color": C.dropper})
	for i in poles.size() - 1:
		var a: Dictionary = poles[i]
		var b: Dictionary = poles[i + 1]
		var span: float = b.x - a.x
		for zf in [-42.65, -43.35]:
			W.add(geo.catenary([a.x, FEEDER_Y, zf], [b.x, FEEDER_Y, zf], 0.75 * pow(span / 45.0, 2), 18), {"width": 0.03, "color": C.feeder})
		W.add(geo.catenary([a.x, GROUND_WIRE_Y, -43], [b.x, GROUND_WIRE_Y, -43], 0.55 * pow(span / 45.0, 2), 16), {"width": 0.016, "color": C.ground})
		for zd in DIST_Z:
			W.add(geo.catenary([a.x, DIST_Y, zd], [b.x, DIST_Y, zd], 0.9 * pow(span / 45.0, 2), 18), {"width": 0.022, "color": C.feeder})
	return {"poles": poles, "colliders": colliders, "zSouthPole": z_south_pole, "zNorthPole": z_north_pole}
