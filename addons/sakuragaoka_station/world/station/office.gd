# station/office.js: the station office and the gate-booth fittings, every object modelled: desks
# with terminal, PC, CCTV and PA mic, swivel chairs, binder shelving, lockers, key cabinet, coat hooks
# with the uniform cap and jacket, tea corner, desk fan, radio, clipboards, whiteboard, safe, copier,
# filing cabinet, wall AC, signal flags and hand lamp, bin, broom.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Building = preload("res://addons/sakuragaoka_station/world/station/building.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")


static func build_office(A, X) -> void:
	Office.new(A, X).build()


class Office extends RefCounted:
	var A
	var X
	var ctx
	var M: Dictionary
	var P
	var C: Dictionary
	var r: Rng
	var FY: float
	var laminate
	var desk_grey
	var fabric
	var plastic

	func _init(a, x) -> void:
		A = a
		X = x
		ctx = a.ctx
		M = a.M
		P = a.P
		C = x.C
		FY = Building.B.FY
		r = ctx.rng("station-office")
		laminate = M.ic.call("#d7d2c4")
		desk_grey = M.ic.call("#9ea3aa")
		fabric = M.ic.call("#34466e")
		plastic = M.ic.call("#4a4b55", 0.02)

	func K(g):
		return X.K(g)

	func desk(x: float, z: float, rot_y: float, w: float, d: float, o: Dictionary = {}) -> Dictionary:
		var g = X.grp(x, FY, z, rot_y)
		var kk = K(g)
		kk.rb(w, 0.03, d, 0.008, laminate, [0, 0.725, 0])
		kk.box(w - 0.02, 0.04, d - 0.04, desk_grey, [0, 0.69, 0])
		kk.box(0.03, 0.67, d - 0.06, desk_grey, [-w / 2.0 + 0.03, 0.335, 0])
		kk.box(w - 0.1, 0.35, 0.02, desk_grey, [0, 0.45, -d / 2.0 + 0.04])
		var px := w / 2.0 - 0.22
		kk.box(0.42, 0.66, d - 0.06, desk_grey, [px, 0.34, 0])
		for i in 3:
			var y := 0.13 + i * 0.2
			kk.box(0.38, 0.17, 0.012, M.ic.call("#b3b7bd"), [px, y, d / 2.0 - 0.024])
			kk.box(0.12, 0.018, 0.018, C.steelDk, [px, y + 0.05, d / 2.0 - 0.012])
		kk.box(0.4, 0.02, d - 0.08, C.rubber, [px, 0.01, 0])
		if o.get("col", true) != false:
			P.addBox(x, z, w, d, rot_y, -1, FY + 0.8)
		return {"g": g, "kk": kk, "top": 0.74}

	func chair(x: float, z: float, rot_y: float, o: Dictionary = {}):
		var g = X.grp(x, FY, z, rot_y)
		var kk = K(g)
		for i in 5:
			var a := i * PI * 2.0 / 5.0 + 0.3
			var lg := T.Group.new()
			lg.rotation.y = a
			lg.position.y = 0.07
			g.add(lg)
			var lk = K(lg)
			lk.box(0.035, 0.03, 0.3, plastic, [0, 0, 0.15], [0.12, 0, 0])
			lk.sphere(0.026, C.ink, [0, -0.04, 0.29], 8)
		kk.cy(0.035, 0.12, plastic, [0, 0.12, 0], 10)
		kk.cy(0.022, 0.2, C.steel, [0, 0.27, 0], 8)
		kk.box(0.2, 0.04, 0.22, plastic, [0, 0.39, 0])
		kk.rb(0.48, 0.07, 0.46, 0.03, fabric, [0, 0.445, 0.02], null, 2)
		kk.box(0.06, 0.28, 0.025, plastic, [0, 0.55, -0.2], [-0.08, 0, 0])
		kk.rb(0.44, 0.44, 0.06, 0.03, fabric, [0, 0.85, -0.23], [-0.1, 0, 0], 2)
		if o.get("arms", true) != false:
			for s in [-1, 1]:
				kk.box(0.03, 0.2, 0.03, plastic, [s * 0.23, 0.56, -0.02])
				kk.rb(0.06, 0.03, 0.26, 0.012, plastic, [s * 0.23, 0.66, 0.01])
		P.addCylinder(x, z, 0.3, -1, FY + 1.0)
		return g

	func monitor(g, x: float, y: float, z: float, rot_y: float, scr: String, o: Dictionary = {}):
		var mg := T.Group.new()
		mg.position = Vector3(x, y, z)
		mg.rotation.y = rot_y
		g.add(mg)
		var mk = K(mg)
		var w: float = o.get("w", 0.5)
		var h: float = o.get("h", 0.31)
		mk.rb(0.2, 0.014, 0.16, 0.006, plastic, [0, 0.007, 0])
		mk.box(0.045, 0.2, 0.03, plastic, [0, 0.11, -0.03])
		var pg := T.Group.new()
		pg.position = Vector3(0, 0.2 + h / 2.0, -0.005)
		pg.rotation.x = -0.08
		mg.add(pg)
		var pk = K(pg)
		pk.rb(w, h, 0.03, 0.008, plastic, [0, 0, 0])
		pk.box(w * 0.6, h * 0.6, 0.02, plastic, [0, 0, -0.025])
		pk.lab("N", scr, w - 0.03, h - 0.03, [0, 0.004, 0.0155], null, 1.0)
		pk.box(0.012, 0.006, 0.004, M.ledBlue, [w / 2.0 - 0.03, -h / 2.0 + 0.008, 0.016])
		return mg

	func keyboard(kk, x: float, y: float, z: float, rot_y: float = 0.0) -> void:
		kk.rb(0.42, 0.018, 0.14, 0.006, C.offWhite, [x, y + 0.009, z], [0.04, rot_y, 0])
		var cs := cos(rot_y)
		var sn := sin(rot_y)
		for row in 4:
			for c in 13:
				if row == 3 and c > 3 and c < 9:
					continue
				var lx := -0.186 + c * 0.031
				var lz := -0.045 + row * 0.03
				kk.box(0.026, 0.008, 0.025, C.white, [x + lx * cs + lz * sn, y + 0.02 + row * 0.001, z - lx * sn + lz * cs], [0.04, rot_y, 0])
		kk.box(0.15, 0.008, 0.025, C.white, [x + 0.0 * cs + 0.045 * sn, y + 0.023, z + 0.045 * cs], [0.04, rot_y, 0])

	func desk_phone(kk, x: float, y: float, z: float, rot_y: float = 0.0):
		var pg := T.Group.new()
		pg.position = Vector3(x, y, z)
		pg.rotation.y = rot_y
		kk.parent.add(pg)
		var pk = K(pg)
		pk.rb(0.2, 0.05, 0.2, 0.015, C.offWhite, [0, 0.025, 0])
		pk.rb(0.2, 0.03, 0.12, 0.01, C.offWhite, [0, 0.06, 0.03], [-0.25, 0, 0])
		for i in 12:
			pk.box(0.022, 0.008, 0.018, C.grey, [0.04 + (i % 3) * 0.028, 0.078 - floori(i / 3.0) * 0.006, 0.075 - floori(i / 3.0) * 0.022], [-0.25, 0, 0])
		pk.box(0.06, 0.004, 0.03, M.screenDim, [-0.05, 0.078, 0.06], [-0.25, 0, 0])
		pk.rb(0.07, 0.04, 0.2, 0.018, C.offWhite, [-0.055, 0.075, -0.035])
		pk.rb(0.08, 0.045, 0.05, 0.02, C.offWhite, [-0.055, 0.08, -0.12])
		pk.rb(0.08, 0.045, 0.05, 0.02, C.offWhite, [-0.055, 0.08, 0.05])
		pg.update_matrix_world()
		var wm: Transform3D = pg.matrix_world
		ctx.wires.add(ctx.geo.catenary(wm * Vector3(-0.09, 0.07, 0.07), wm * Vector3(-0.1, 0.03, 0.1), 0.03, 6), {"width": 0.008, "color": "#d8d4ca"})
		return pg

	func pen_cup(kk, x: float, y: float, z: float) -> void:
		kk.cy(0.035, 0.1, C.navy, [x, y + 0.05, z], 12)
		kk.cy(0.03, 0.004, C.ink, [x, y + 0.1, z], 10)
		var pens := [C.blue, C.red, C.ink, C.yellow]
		for i in pens.size():
			var p = kk.cy(0.005, 0.14, pens[i], [x + cos(i * 1.7) * 0.015, y + 0.12, z + sin(i * 1.7) * 0.015], 6)
			p.rotation = Vector3(sin(i * 1.7) * 0.2, 0, -cos(i * 1.7) * 0.2)

	func papers(kk, x: float, y: float, z: float, n: int = 5, rot: float = 0.0) -> void:
		for i in n:
			var px := x + (r.f() - 0.5) * 0.01
			var pz := z + (r.f() - 0.5) * 0.01
			var ry := rot + (r.f() - 0.5) * 0.08
			kk.box(0.21, 0.003, 0.297, C.paper, [px, y + 0.0015 + i * 0.003, pz], [0, ry, 0])

	func mug(kk, x: float, y: float, z: float, m) -> void:
		kk.cy(0.036, 0.085, m, [x, y + 0.0425, z], 12)
		kk.cy(0.03, 0.004, C.tea, [x, y + 0.083, z], 10)
		kk.torus(0.024, 0.006, m, [x + 0.04, y + 0.045, z], [0, 0, PI / 2.0], PI, 8)

	func desk_fan(kk, x: float, y: float, z: float, rot_y: float):
		var fg := T.Group.new()
		fg.position = Vector3(x, y, z)
		fg.rotation.y = rot_y
		kk.parent.add(fg)
		var fk = K(fg)
		fk.cy(0.1, 0.03, C.white, [0, 0.015, 0], 16)
		fk.box(0.03, 0.012, 0.02, C.sky, [0.05, 0.034, 0.04])
		fk.cy(0.016, 0.24, C.white, [0, 0.15, 0], 8)
		var hg := T.Group.new()
		hg.position = Vector3(0, 0.3, 0)
		hg.rotation.x = 0.12
		fg.add(hg)
		var hk = K(hg)
		hk.cz(0.055, 0.1, C.white, [0, 0, -0.04], 14)
		hk.torus(0.145, 0.005, C.greyLt, [0, 0, 0.06], null, PI * 2.0, 28)
		hk.torus(0.145, 0.005, C.greyLt, [0, 0, 0.0], null, PI * 2.0, 28)
		for i in 8:
			var a := i * PI / 4.0
			hk.box(0.004, 0.14, 0.004, C.greyLt, [cos(a) * 0.072, sin(a) * 0.072, 0.06], [0, 0, a + PI / 2.0])
		for i in 3:
			var a := i * PI * 2.0 / 3.0 + 0.3
			hk.box(0.05, 0.12, 0.004, C.sky, [cos(a) * 0.06, sin(a) * 0.06, 0.03], [0.25, 0, a - PI / 2.0])
		hk.cz(0.025, 0.02, C.sky, [0, 0, 0.065], 12)
		return fg

	func radio(kk, x: float, y: float, z: float, rot_y: float):
		var rg := T.Group.new()
		rg.position = Vector3(x, y, z)
		rg.rotation.y = rot_y
		kk.parent.add(rg)
		var rk = K(rg)
		rk.rb(0.28, 0.15, 0.09, 0.015, M.ic.call("#c95a4a"), [0, 0.075, 0])
		rk.box(0.12, 0.1, 0.004, C.dark, [-0.06, 0.075, 0.046])
		for i in 6:
			rk.box(0.11, 0.006, 0.004, C.greyLt, [-0.06, 0.035 + i * 0.016, 0.049])
		rk.lab("N", "radioFace", 0.1, 0.033, [0.07, 0.1, 0.0455], null, 0.9)
		rk.cz(0.014, 0.018, C.cream, [0.045, 0.045, 0.052], 10)
		rk.cz(0.014, 0.018, C.cream, [0.1, 0.045, 0.052], 10)
		for s in [-1, 1]:
			rk.box(0.014, 0.04, 0.02, C.steel, [s * 0.11, 0.17, 0])
		rk.box(0.24, 0.014, 0.02, C.steel, [0, 0.19, 0])
		var ant = rk.cy(0.003, 0.36, C.steel, [0.12, 0.3, -0.03], 6)
		ant.rotation.z = -0.5
		return rg

	func thermos_pot(kk, x: float, y: float, z: float) -> void:
		kk.cy(0.1, 0.02, C.dark, [x, y + 0.01, z], 16)
		kk.mesh(X.geo("pot", func(): return Geo.cylinder(0.095, 0.1, 0.27, 18)), C.white, [x, y + 0.155, z])
		kk.cy(0.1, 0.06, M.ic.call("#d9718f"), [x, y + 0.32, z], 18)
		kk.cy(0.04, 0.02, C.white, [x, y + 0.355, z], 12)
		kk.box(0.04, 0.03, 0.06, M.ic.call("#d9718f"), [x, y + 0.29, z + 0.1])
		kk.box(0.05, 0.03, 0.01, M.screenDim, [x, y + 0.22, z + 0.098])
		kk.torus(0.07, 0.01, C.dark, [x, y + 0.36, z], [0, PI / 2.0, 0], PI, 12)

	func jug_kettle(kk, x: float, y: float, z: float, rot_y: float = 0.0) -> void:
		kk.cy(0.09, 0.02, C.dark, [x, y + 0.01, z], 16)
		kk.mesh(X.geo("jug", func(): return Geo.cylinder(0.075, 0.088, 0.2, 16)), C.steel, [x, y + 0.12, z])
		kk.cy(0.07, 0.02, C.dark, [x, y + 0.23, z], 14)
		var hx := x - cos(rot_y) * 0.1
		var hz := z + sin(rot_y) * 0.1
		kk.box(0.025, 0.17, 0.035, C.dark, [hx, y + 0.13, hz], [0, rot_y, 0])
		kk.box(0.045, 0.025, 0.035, C.steel, [x + cos(rot_y) * 0.085, y + 0.2, z - sin(rot_y) * 0.085], [0, rot_y, -0.4])

	func lockers(x: float, z: float, rot_y: float, n: int = 3, names: Array = []):
		var g = X.grp(x, FY, z, rot_y)
		var kk = K(g)
		var w := 0.4
		var H := 1.8
		var D := 0.5
		var body = M.ic.call("#b9bec3")
		kk.box(n * w, 0.08, D - 0.04, C.dark, [0, 0.04, 0])
		for i in n:
			var lx := (i - (n - 1) / 2.0) * w
			kk.box(w - 0.004, H - 0.08, D, body, [lx, 0.08 + (H - 0.08) / 2.0, 0])
			kk.box(w - 0.04, H - 0.14, 0.012, M.ic.call("#c9cdd1"), [lx, 0.08 + (H - 0.08) / 2.0, D / 2.0 + 0.004])
			for y0 in [1.55, 0.25]:
				for kq in 5:
					kk.box(0.22, 0.01, 0.006, C.steelDk, [lx, y0 + kq * 0.03, D / 2.0 + 0.012])
			kk.box(0.02, 0.12, 0.03, C.steelDk, [lx + w / 2.0 - 0.06, 1.0, D / 2.0 + 0.02])
			kk.box(0.1, 0.035, 0.004, C.paper, [lx, 1.42, D / 2.0 + 0.012])
			if i < names.size() and names[i]:
				X.lab(g, "N", names[i], 0.09, 0.03, [lx, 1.42, D / 2.0 + 0.0145], null, 0.9)
		kk.box(n * w + 0.01, 0.02, D + 0.01, body, [0, H + 0.01, 0])
		kk.box(0.4, 0.22, 0.3, M.ic.call("#c9a57a"), [-0.3, H + 0.13, 0])
		kk.box(0.4, 0.004, 0.02, M.ic.call("#b88a5a"), [-0.3, H + 0.241, 0])
		kk.mesh(X.geo("helmet", func(): return Geo.sphere(0.13, 14, 7, 0, TAU, 0, PI / 2.0)), C.white, [0.3, H + 0.02, 0])
		kk.box(0.2, 0.012, 0.1, C.white, [0.3, H + 0.026, 0.12])
		P.addBox(x, z, n * w, D, rot_y, -1, 3)
		return g

	func binder_shelf(x: float, z: float, rot_y: float, w: float = 0.9, o: Dictionary = {}):
		var g = X.grp(x, FY, z, rot_y)
		var kk = K(g)
		var H := 1.8
		var D := 0.35
		var frame = M.ic.call("#a9aeb4")
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				kk.box(0.03, H, 0.03, frame, [sx * (w / 2.0 - 0.015), H / 2.0, sz * (D / 2.0 - 0.015)])
		var levels := [0.08, 0.5, 0.92, 1.34, 1.76]
		for y in levels:
			kk.box(w, 0.018, D, frame, [0, y, 0])
		for sx in [-1, 1]:
			kk.box(0.006, 0.4, D - 0.04, frame, [sx * (w / 2.0 - 0.02), 0.3, 0])
		var spines: Dictionary = A.atlases.N.r("spines")
		var cols := []
		for h in ["#3f6fb0", "#c9504a", "#3f8a5c", "#e2c05a", "#8e949b", "#ef9fbe", "#2f4068", "#ebe8e0"]:
			cols.append(M.ic.call(h))
		var kinds: Array = o.get("kinds", ["binder", "binder", "box", "binder"])
		for s in 4:
			var y: float = levels[s] + 0.009
			var bx := -w / 2.0 + 0.04
			var kind: String = kinds[s]
			while bx < w / 2.0 - 0.1:
				if kind == "box":
					if r.f() < 0.3:
						for i in 4:
							kk.box(0.21, 0.02, 0.28, C.paper, [bx + 0.12, y + 0.01 + i * 0.02, 0.01], [0, (r.f() - 0.5) * 0.1, 0])
						bx += 0.26
						continue
					var t := 0.09
					kk.box(t, 0.32, 0.3, cols[floori(r.f() * 4.0) + 4], [bx + t / 2.0, y + 0.16, 0.0])
					kk.box(t * 0.7, 0.08, 0.004, C.paper, [bx + t / 2.0, y + 0.24, 0.151])
					kk.cz(0.012, 0.006, C.ink, [bx + t / 2.0, y + 0.1, 0.151], 8)
					bx += t + 0.004
					continue
				if r.f() < 0.06:
					bx += 0.05 + r.f() * 0.06
					continue
				var t := 0.05 + r.f() * 0.03
				var m = cols[floori(r.f() * cols.size())]
				var lean := -0.14 if r.f() < 0.08 else 0.0
				var bgp := T.Group.new()
				bgp.position = Vector3(bx + t / 2.0 + (0.03 if lean else 0.0), y, 0.005)
				bgp.rotation.z = lean
				g.add(bgp)
				var bk = K(bgp)
				bk.box(t, 0.31, 0.28, m, [0, 0.155, 0])
				var cell := floori(r.f() * 8.0)
				var u0: float = spines.u0 + (spines.u1 - spines.u0) * cell / 8.0
				var u1: float = spines.u0 + (spines.u1 - spines.u0) * (cell + 1) / 8.0
				var lp := T.MeshObj.new(A.U.rect_plane(t * 0.7, 0.2, {"u0": u0, "u1": u1, "v0": spines.v0, "v1": spines.v1}), A.sign_mat("N", 0.8))
				lp.position = Vector3(0, 0.19, 0.1415)
				bgp.add(lp)
				bk.cz(0.011, 0.004, C.ink, [0, 0.055, 0.141], 10)
				bx += t + 0.003 + (0.06 if lean else 0.0)
		kk.box(0.34, 0.25, 0.28, M.ic.call("#c9a57a"), [-w / 2.0 + 0.22, 1.77 + 0.125, 0])
		for i in 3:
			kk.cx(0.035, 0.5, C.paper, [0.12, 1.805 + i * 0.001, -0.08 + i * 0.07], 10)
		P.addBox(x, z, w, D, rot_y, -1, 3)
		return g

	func safe(x: float, z: float, rot_y: float) -> Dictionary:
		var g = X.grp(x, FY, z, rot_y)
		var kk = K(g)
		kk.rb(0.42, 0.5, 0.42, 0.02, M.ic.call("#5a5e68"), [0, 0.25, 0])
		kk.box(0.34, 0.4, 0.012, M.ic.call("#666a74"), [0, 0.26, 0.211])
		kk.cz(0.045, 0.02, C.steel, [-0.06, 0.32, 0.222], 16)
		kk.box(0.008, 0.03, 0.012, C.ink, [-0.06, 0.35, 0.233])
		kk.box(0.02, 0.1, 0.03, C.steel, [0.09, 0.28, 0.225])
		kk.box(0.1, 0.03, 0.004, C.gold, [0, 0.12, 0.218])
		P.addBox(x, z, 0.44, 0.44, rot_y, -1, FY + 0.5)
		return {"g": g, "kk": kk}

	func copier(x: float, z: float, rot_y: float):
		var g = X.grp(x, FY, z, rot_y)
		var kk = K(g)
		kk.box(0.6, 0.06, 0.55, C.dark, [0, 0.03, 0])
		kk.rb(0.62, 0.62, 0.58, 0.02, C.offWhite, [0, 0.37, 0])
		for i in 3:
			kk.box(0.56, 0.14, 0.012, C.white, [0, 0.15 + i * 0.16, 0.292])
			kk.box(0.18, 0.02, 0.02, C.grey, [0, 0.19 + i * 0.16, 0.302])
		kk.rb(0.64, 0.14, 0.58, 0.02, C.white, [0, 0.75, 0])
		kk.box(0.52, 0.02, 0.2, C.greyLt, [0, 0.83, 0.1])
		kk.box(0.52, 0.03, 0.38, C.white, [0, 0.845, -0.08])
		kk.rb(0.24, 0.05, 0.1, 0.01, C.dark, [0.16, 0.86, 0.27], [-0.3, 0, 0])
		kk.box(0.1, 0.004, 0.06, M.screenDim, [0.12, 0.886, 0.285], [-0.3, 0, 0])
		kk.box(0.4, 0.012, 0.2, C.paper, [0, 0.7, 0.18])
		P.addBox(x, z, 0.64, 0.6, rot_y, -1, 3)
		return g

	func filing_cabinet(x: float, z: float, rot_y: float, h: float = 1.32) -> Dictionary:
		var g = X.grp(x, FY, z, rot_y)
		var kk = K(g)
		var body = M.ic.call("#b0b5bb")
		kk.box(0.46, h, 0.62, body, [0, h / 2.0, 0])
		var n := 4
		for i in n:
			var y := 0.05 + (i + 0.5) * (h - 0.08) / n
			kk.box(0.42, (h - 0.08) / n - 0.02, 0.012, M.ic.call("#c3c7cc"), [0, y, 0.316])
			kk.box(0.16, 0.025, 0.022, C.steelDk, [0, y + 0.06, 0.33])
			kk.box(0.07, 0.03, 0.004, C.paper, [0, y + 0.1, 0.323])
		P.addBox(x, z, 0.48, 0.64, rot_y, -1, 3)
		return {"g": g, "kk": kk, "top": h}

	func build() -> void:
		var OX0 := 0.6
		var OX1 := 5.2
		var OZ0 := -35.3
		# ======================================================== 1. window counter desk + staff chair
		var d1 := desk(3.82, -29.74, PI, 1.85, 0.62)
		var g = d1.g
		var kk = d1.kk
		var y := 0.74
		monitor(g, 0.35, y, 0.05, 0.0, "termScr", {"w": 0.42, "h": 0.27})
		kk.rb(0.3, 0.12, 0.28, 0.02, C.offWhite, [-0.2, y + 0.06, -0.05])
		kk.box(0.22, 0.012, 0.04, C.ink, [-0.2, y + 0.12, 0.07])
		kk.box(0.18, 0.004, 0.12, C.paper, [-0.2, y + 0.125, 0.14], [-0.4, 0, 0])
		var cg := T.Group.new()
		cg.position = Vector3(-0.55, y, -0.18)
		cg.rotation.y = PI
		g.add(cg)
		var ck = K(cg)
		ck.box(0.05, 0.14, 0.04, plastic, [0, 0.07, 0])
		ck.rb(0.2, 0.12, 0.03, 0.008, plastic, [0, 0.19, 0], [-0.15, 0, 0])
		ck.lab("N", "custScr", 0.17, 0.085, [0, 0.19, 0.0165], [-0.15, 0, 0], 1.0)
		keyboard(kk, 0.35, y, 0.2)
		kk.rb(0.06, 0.03, 0.1, 0.012, C.offWhite, [0.65, y + 0.015, 0.2])
		pen_cup(kk, 0.75, y, -0.05)
		papers(kk, -0.62, y, 0.12, 4, 0.2)
		kk.box(0.2, 0.02, 0.08, C.woodDk, [-0.35, y + 0.01, 0.2])
		for i in 4:
			kk.cy(0.012, 0.07, C.red if i % 2 else C.dark, [-0.42 + i * 0.045, y + 0.055, 0.2], 8)
		kk.rb(0.1, 0.02, 0.07, 0.006, C.ink, [-0.12, y + 0.01, 0.23])
		kk.rb(0.1, 0.015, 0.16, 0.006, C.dark, [0.0, y + 0.0075, 0.24], [0.08, 0.3, 0])
		kk.box(0.07, 0.004, 0.03, M.screenDim, [-0.005, y + 0.018, 0.195], [0.08, 0.3, 0])
		mug(kk, 0.85, y, 0.2, M.ic.call("#8fd1c1"))
		chair(3.95, -30.45, 0.05)
		kk.box(0.1, 0.02, 0.08, C.dark, [0.0, y + 0.01, -0.2])
		var mic := T.Group.new()
		mic.position = Vector3(0.0, y + 0.02, -0.2)
		g.add(mic)
		var mk = K(mic)
		for i in 5:
			var a := i * 0.25
			mk.cy(0.007, 0.06, C.dark, [0, 0.03 + i * 0.055, -sin(a) * 0.04 * i], 6).rotation.x = -a
		mk.cy(0.014, 0.05, C.dark, [0, 0.3, -0.2], 8).rotation.x = -1.2
		# ======================================================== 2. platform-window desk
		var d2 := desk(2.3, -34.95, 0.0, 1.8, 0.68)
		g = d2.g
		kk = d2.kk
		monitor(g, -0.35, y, -0.12, 0.2, "pcScr")
		monitor(g, 0.32, y, -0.14, -0.25, "cctvScr", {"w": 0.44, "h": 0.28})
		keyboard(kk, -0.3, y, 0.12, 0.2)
		kk.rb(0.06, 0.03, 0.1, 0.012, C.offWhite, [0.0, y + 0.015, 0.16])
		desk_phone(kk, 0.66, y, 0.08, -0.3)
		radio(kk, -0.7, y, -0.18, 0.15)
		pen_cup(kk, 0.1, y, -0.22)
		papers(kk, 0.35, y, 0.14, 6, -0.25)
		kk.rb(0.16, 0.04, 0.12, 0.01, C.dark, [-0.72, y + 0.02, 0.12])
		kk.box(0.03, 0.01, 0.02, M.ledRed, [-0.68, y + 0.042, 0.15])
		var pm = kk.cy(0.006, 0.22, C.dark, [-0.74, y + 0.15, 0.1], 6)
		pm.rotation.x = -0.35
		kk.cy(0.018, 0.06, C.dark, [-0.74, y + 0.26, 0.06], 10).rotation.x = -0.9
		mug(kk, 0.55, y, -0.2, M.ic.call("#ef9fbe"))
		chair(2.25, -34.2, PI + 0.15)
		var fg = X.grp(3.55, FY, -34.55, -0.7)
		var fk = K(fg)
		fk.cy(0.14, 0.03, C.white, [0, 0.015, 0], 16)
		desk_fan(fk, 0, 0.0, 0, 0).scale = Vector3(1.35, 1.9, 1.35)
		var bg = X.grp(1.22, FY, -34.35, 0)
		var bk = K(bg)
		bk.mesh(X.geo("wbin", func(): return Geo.cylinder(0.13, 0.11, 0.32, 16)), M.ic.call("#9aa0a6"), [0, 0.16, 0])
		bk.cy(0.118, 0.004, C.ink, [0, 0.321, 0], 14)
		bk.torus(0.13, 0.008, C.greyLt, [0, 0.32, 0], [PI / 2.0, 0, 0], PI * 2.0, 16)
		for i in 3:
			var sx := (r.f() - 0.5) * 0.1
			var sz := (r.f() - 0.5) * 0.1
			bk.sphere(0.04, C.paper, [sx, 0.2 + i * 0.03, sz], 6)
		P.addCylinder(1.22, -34.35, 0.16, -1, FY + 0.4)
		# ======================================================== 3. west wall
		binder_shelf(OX0 + 0.18, -33.45, PI / 2.0, 0.9)
		binder_shelf(OX0 + 0.18, -32.53, PI / 2.0, 0.9, {"kinds": ["box", "binder", "binder", "binder"]})
		var sf := safe(OX0 + 0.22, -31.55, PI / 2.0)
		sf.kk.box(0.3, 0.08, 0.22, M.ic.call("#c9a57a"), [0, 0.54, 0])
		var wg = X.grp(OX0, FY, -30.6, PI / 2.0)
		var wk = K(wg)
		wk.box(0.9, 0.05, 0.02, C.woodDk, [0, 1.9, 0.01])
		X.clipboard(wg, -0.3, 1.66, 0.018, "clipPaper", 0.03)
		X.clipboard(wg, 0.02, 1.66, 0.018, "clipPaper2", -0.02)
		X.clipboard(wg, 0.32, 1.64, 0.018, "clipPaper", 0.05)
		for xx in [-0.3, 0.02, 0.32]:
			wk.cz(0.006, 0.03, C.steel, [xx, 1.85, 0.02], 6)
		X.sheet(wg, "B", "calendar", 0.3, 0.4, [0.0, 2.3, 0.012], 0.01, {"curl": 0.008})
		wk.cz(0.005, 0.02, C.steel, [0.0, 2.49, 0.015], 6)
		var acg = X.grp(OX0, FY + 2.55, -33.0, PI / 2.0)
		var ack = K(acg)
		ack.rb(0.82, 0.28, 0.22, 0.04, C.white, [0, 0, 0.11], null, 2)
		ack.box(0.72, 0.05, 0.02, C.dark, [0, -0.11, 0.19], [0.5, 0, 0])
		ack.box(0.7, 0.012, 0.03, C.offWhite, [0, -0.12, 0.2], [0.9, 0, 0])
		ack.box(0.03, 0.012, 0.004, M.ledGreen, [0.3, -0.06, 0.221])
		copier(1.05, -29.72, PI)
		var fc := filing_cabinet(1.85, -29.74, PI)
		papers(fc.kk, 0, fc.top, 0, 3, 0.1)
		fc.kk.box(0.3, 0.12, 0.22, M.ic.call("#c9a57a"), [0.02, fc.top + 0.06 + 0.009, 0.05])
		# ======================================================== 4. east wall
		lockers(OX1 - 0.25, -34.2, -PI / 2.0, 3, ["lockerA", "lockerB", "lockerC"])
		var tg = X.grp(OX1 - 0.225, FY, -32.9, -PI / 2.0)
		var tk = K(tg)
		tk.box(0.9, 0.8, 0.45, M.ic.call("#d8d2c2"), [0, 0.4, 0])
		tk.rb(0.94, 0.03, 0.48, 0.008, laminate, [0, 0.815, 0.01])
		for s in [-1, 1]:
			tk.box(0.43, 0.7, 0.012, M.ic.call("#e4dfd2"), [s * 0.222, 0.42, 0.228])
			tk.box(0.015, 0.1, 0.02, C.steelDk, [s * 0.03, 0.5, 0.24])
		tk.box(0.88, 0.05, 0.43, C.dark, [0, 0.025, -0.005])
		var ty := 0.83
		thermos_pot(tk, -0.28, ty, -0.02)
		jug_kettle(tk, 0.02, ty, -0.06, 0.4)
		tk.rb(0.32, 0.014, 0.22, 0.006, C.woodLt, [0.27, ty + 0.007, 0.06])
		var cups := [M.ic.call("#8fd1c1"), C.white, M.ic.call("#e8914a"), C.navy]
		for i in cups.size():
			var cx := 0.19 + (i % 2) * 0.1
			var cz := 0.02 + floori(i / 2.0) * 0.09
			tk.cy(0.032, 0.07, cups[i], [cx, ty + 0.014 + 0.035, cz], 12)
			tk.cy(0.027, 0.004, C.tea if i < 2 else C.ink, [cx, ty + 0.084, cz], 10)
		tk.cy(0.04, 0.12, C.greenDk, [0.33, ty + 0.06, -0.12], 12)
		tk.cy(0.042, 0.03, C.greenDk, [0.33, ty + 0.135, -0.12], 12)
		tk.cy(0.035, 0.09, M.ic.call("#6e5140"), [0.42, ty + 0.045, 0.1], 10)
		tk.cy(0.036, 0.02, C.red, [0.42, ty + 0.1, 0.1], 10)
		P.addBox(OX1 - 0.225, -32.9, 0.94, 0.48, -PI / 2.0, -1, 2)
		var wb = X.grp(OX1, FY + 1.68, -32.9, -PI / 2.0)
		var wbk = K(wb)
		wbk.box(1.1, 0.72, 0.015, C.paper, [0, 0, 0.0075])
		wbk.lab("B", "officeBoard", 1.04, 0.68, [0, 0, 0.0155], null, 0.85)
		for e in [[1.14, 0.025, 0, 0.3725], [1.14, 0.025, 0, -0.3725], [0.025, 0.72, -0.5575, 0], [0.025, 0.72, 0.5575, 0]]:
			wbk.box(e[0], e[1], 0.025, C.steel, [e[2], e[3], 0.0125])
		wbk.box(0.6, 0.02, 0.05, C.steel, [0.1, -0.385, 0.03])
		var markers := [C.blue, C.red, C.ink]
		for i in markers.size():
			wbk.cx(0.008, 0.12, markers[i], [-0.05 + i * 0.13, -0.368, 0.035], 8)
		wbk.rb(0.1, 0.03, 0.04, 0.008, C.navy, [0.3, -0.36, 0.035])
		X.sheet(wb, "N", "nDaiya", 0.18, 0.25, [0.4, 0.12, 0.017], -0.04, {"curl": 0.006})
		wbk.cz(0.012, 0.01, C.red, [0.4, 0.23, 0.024], 10)
		wbk.cz(0.012, 0.01, C.blue, [-0.33, 0.2, 0.02], 10)
		wbk.cz(0.012, 0.01, C.yellow, [-0.2, -0.18, 0.02], 10)
		# key cabinet (door open, keys + tags on hooks)
		var kg = X.grp(OX1, FY + 1.75, -32.05, -PI / 2.0)
		var kkk = K(kg)
		var w := 0.36
		var h := 0.46
		var d := 0.08
		var kbody = M.ic.call("#b9bec3")
		kkk.box(w, h, 0.01, kbody, [0, 0, 0.005])
		kkk.box(w, 0.012, d, kbody, [0, h / 2.0 - 0.006, d / 2.0])
		kkk.box(w, 0.012, d, kbody, [0, -h / 2.0 + 0.006, d / 2.0])
		kkk.box(0.012, h, d, kbody, [-w / 2.0 + 0.006, 0, d / 2.0])
		kkk.box(0.012, h, d, kbody, [w / 2.0 - 0.006, 0, d / 2.0])
		var tags := [C.red, C.blue, C.yellow, C.green, C.white]
		for row in 4:
			for c in 5:
				var hx := -0.13 + c * 0.065
				var hy := 0.17 - row * 0.105
				kkk.cz(0.004, 0.03, C.steel, [hx, hy, 0.025], 6)
				if r.f() < 0.8:
					kkk.box(0.012, 0.035, 0.004, C.gold, [hx, hy - 0.025, 0.036])
					kkk.rb(0.028, 0.045, 0.005, 0.006, tags[(row + c) % 5], [hx, hy - 0.065, 0.034])
		var dg := T.Group.new()
		dg.position = Vector3(-w / 2.0, 0, d)
		dg.rotation.y = -1.25
		kg.add(dg)
		var dk = K(dg)
		dk.box(w, h, 0.012, M.ic.call("#c3c8cc"), [w / 2.0, 0, 0.006])
		dk.box(0.02, 0.05, 0.02, C.steelDk, [w - 0.04, 0, 0.02])
		dk.lab("N", "keyLabel", 0.12, 0.03, [w / 2.0, 0.16, 0.0125], null, 0.9)
		# coat hook rail: uniform jacket on a hanger + cap
		var hgp = X.grp(OX1, FY + 1.9, -31.35, -PI / 2.0)
		var hk = K(hgp)
		hk.rb(0.72, 0.08, 0.02, 0.006, C.wood, [0, 0, 0.01])
		for xx in [-0.25, 0.0, 0.25]:
			hk.cz(0.008, 0.07, C.steel, [xx, 0, 0.055], 6)
			hk.cy(0.008, 0.04, C.steel, [xx, 0.02, 0.09], 6)
		var jk := T.Group.new()
		jk.position = Vector3(0.0, 0.04, 0.1)
		hgp.add(jk)
		var jj = K(jk)
		jj.torus(0.02, 0.004, C.steel, [0, 0.0, 0], [PI / 2.0, 0, 0], PI * 2.0, 10)
		jj.box(0.42, 0.018, 0.02, C.woodLt, [0, -0.05, 0], [0, 0, 0])
		jj.rb(0.46, 0.2, 0.12, 0.05, C.navy, [0, -0.15, 0], null, 2)
		jj.rb(0.42, 0.52, 0.1, 0.04, C.navy, [0, -0.46, 0.005], null, 2)
		for s in [-1, 1]:
			jj.rb(0.1, 0.56, 0.1, 0.04, C.navy, [s * 0.25, -0.38, 0], [0, 0, s * 0.06], 2)
		jj.box(0.012, 0.5, 0.004, C.ink, [0, -0.45, 0.056])
		for i in 4:
			jj.sphere(0.009, C.gold, [0.035, -0.28 - i * 0.1, 0.057], 6)
		jj.box(0.14, 0.05, 0.02, C.navy, [0, -0.06, 0.05], [0.4, 0, 0])
		jj.box(0.06, 0.02, 0.004, C.gold, [-0.12, -0.2, 0.056])
		var cp := T.Group.new()
		cp.position = Vector3(-0.25, -0.04, 0.12)
		cp.rotation = Vector3(0.35, 0.2, 0.1)
		hgp.add(cp)
		var cpk = K(cp)
		cpk.mesh(X.geo("capCrown", func(): return Geo.cylinder(0.125, 0.105, 0.075, 20)), C.navy, [0, 0.07, 0])
		cpk.cy(0.126, 0.012, C.navy, [0, 0.11, 0], 20)
		cpk.cy(0.107, 0.035, C.ink, [0, 0.02, 0], 20)
		cpk.cy(0.108, 0.006, C.gold, [0, 0.04, 0], 20)
		cpk.mesh(X.geo("visor", func(): return Geo.cylinder(0.105, 0.105, 0.008, 16, 1, false, -PI / 2.0, PI)), C.ink, [0, 0.0, 0.03], [0.3, 0, 0])
		cpk.cz(0.018, 0.006, C.gold, [0, 0.055, 0.108], 12)
		hk.box(0.16, 0.3, 0.012, C.white, [0.25, -0.16, 0.1])
		# broom + dustpan
		var brg = X.grp(OX1 - 0.12, FY, -31.05, 0)
		var brk = K(brg)
		var stick = brk.cy(0.012, 1.2, C.woodLt, [0, 0.62, 0], 6)
		stick.rotation.x = 0.12
		brk.box(0.26, 0.12, 0.06, M.ic.call("#c9a07a"), [0, 0.06, -0.07])
		brk.box(0.24, 0.02, 0.2, M.ic.call("#4f8f5f"), [-0.28, 0.01, 0.05])
		brk.box(0.24, 0.1, 0.012, M.ic.call("#4f8f5f"), [-0.28, 0.05, -0.05])
		brk.cy(0.01, 0.8, M.ic.call("#4f8f5f"), [-0.28, 0.45, -0.05], 6)
		# ======================================================== 5. north wall: flags + hand lamp, clock, door inside
		var nfg = X.grp(3.55, FY, OZ0, 0)
		var nfk = K(nfg)
		nfk.box(0.16, 0.06, 0.08, C.dark, [0, 1.3, 0.04])
		for e in [[-0.035, C.red], [0.035, C.green]]:
			nfk.cy(0.008, 0.62, C.woodLt, [e[0], 1.5, 0.05], 6)
			nfk.cy(0.02, 0.3, e[1], [e[0], 1.62, 0.05], 8)
		nfk.lab("N", "flagLabel", 0.1, 0.027, [0, 1.3, 0.0805], null, 0.9)
		nfk.box(0.24, 0.02, 0.16, C.dark, [0, 0.95, 0.08])
		nfk.box(0.2, 0.06, 0.12, C.dark, [0, 0.99, 0.08])
		nfk.box(0.04, 0.012, 0.004, M.ledGreen, [0.06, 1.0, 0.141])
		nfk.cy(0.035, 0.18, C.dark, [-0.02, 1.11, 0.08], 12)
		nfk.cz(0.036, 0.02, M.ic.call("#e8e2c8"), [-0.02, 1.17, 0.115], 12)
		nfk.box(0.02, 0.08, 0.03, C.dark, [-0.02, 1.22, 0.06])
		A.clock([2.3, FY + 2.7, OZ0 + 0.03], 0.0, 0.15, {"frame": C.dark})
		var drg = X.grp(4.35, FY, OZ0, 0)
		var drk = K(drg)
		drk.box(0.88, 1.99, 0.07, M.ic.call("#9fa6ae"), [0, 1.0, -0.08])
		for s in [-1, 1]:
			drk.box(0.06, 2.06, 0.05, C.steelDk, [s * 0.47, 1.03, 0.01])
		drk.box(1.0, 0.06, 0.05, C.steelDk, [0, 2.03, 0.01])
		drk.box(0.12, 0.03, 0.03, C.steel, [0.3, 1.0, 0.0])
		drk.box(0.04, 0.1, 0.02, C.steel, [0.35, 1.0, -0.01])
		drk.box(0.3, 0.05, 0.05, C.steelDk, [-0.25, 1.94, 0.02])
		drk.box(0.25, 0.02, 0.02, C.steel, [-0.1, 1.94, 0.055], [0, 0.4, 0])
		X.sheet(drg, "N", "clipPaper", 0.2, 0.27, [0, 1.5, -0.043], 0.0, {"curl": 0.006})
		drk.cz(0.008, 0.01, C.red, [0, 1.62, -0.038], 8)
		X.potted_plant(1.6, -35.255, {"y": FY + 0.95, "potR": 0.05, "potH": 0.09, "r": 0.11, "h": 0.18, "seed": 21, "shrubKind": "young", "col": false, "saucer": false})
		# ======================================================== gate booth counter props
		var top := FY + 1.09
		var bpg = X.grp(6.0, top, -30.0, 0)
		var bpk = K(bpg)
		bpk.rb(0.2, 0.14, 0.14, 0.01, C.woodDk, [0.45, 0.07, 0.4])
		bpk.box(0.1, 0.006, 0.012, C.ink, [0.45, 0.143, 0.4])
		bpk.lab("N", "lbTicket", 0.18, 0.028, [0.45, 0.07, 0.4705], null, 0.9)
		bpk.rb(0.08, 0.05, 0.06, 0.01, C.dark, [0.5, 0.025, 0.15])
		bpk.cy(0.012, 0.06, C.dark, [0.5, 0.08, 0.15], 8)
		bpk.sphere(0.02, C.red, [0.5, 0.12, 0.15], 8)
		pen_cup(bpk, 0.2, 0.0, -0.78)
		monitor(bpg, 0.46, 0.0, -0.18, -PI / 2.0, "custScr", {"w": 0.24, "h": 0.14})
		desk_phone(bpk, -0.35, 0.0, -0.83, 0.1)
		papers(bpk, -0.1, 0.0, 0.84, 3, PI / 2.0)
		mug(bpk, 0.5, 0.0, -0.1, M.ic.call("#9cc4ea"))
