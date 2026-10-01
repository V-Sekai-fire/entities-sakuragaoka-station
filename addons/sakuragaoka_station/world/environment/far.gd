# environment/far.js: everything beyond the river and the town: spring fields, farm roads,
# farmhouses with windbreak trees, greenhouses, a shrine forest, a hillside town with a school,
# lattice pylons with sagging lines, tree clumps on the hills and three layered distant ridge rings.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Common = preload("res://addons/sakuragaoka_station/world/environment/common.gd")
const Shaders = preload("res://addons/sakuragaoka_station/world/environment/shaders.gd")
const Foliage = preload("res://addons/sakuragaoka_station/world/lib/foliage.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")


static func build_far(ctx, C, tx) -> Dictionary:
	return Far.new(ctx, C, tx).build()


class Far extends RefCounted:
	## unit gable prism: width 1 (x), depth 1 (z), ridge along x at y = 1, eaves at y = 0
	static func gable_roof_geo() -> T.Geometry:
		var p := [-0.5, 0, 0.5, 0.5, 0, 0.5, 0.5, 1, 0, -0.5, 1, 0, -0.5, 0, -0.5, 0.5, 0, -0.5]
		var idx := [0, 1, 2, 0, 2, 3, 5, 4, 3, 5, 3, 2, 0, 3, 4, 1, 5, 2, 0, 4, 5, 0, 5, 1]
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(PackedFloat32Array(p), 3))
		g.set_index(idx)
		var ng := g.to_non_indexed()
		ng.compute_vertex_normals()
		return ng


	static func hip_roof_geo(w: float, d: float, h: float) -> T.Geometry:
		var r := maxf(0.0, (w - d) / 2.0)
		var p := [-w / 2, 0, d / 2, w / 2, 0, d / 2, w / 2, 0, -d / 2, -w / 2, 0, -d / 2, -r, h, 0, r, h, 0]
		var idx := [0, 1, 5, 0, 5, 4, 2, 3, 4, 2, 4, 5, 1, 2, 5, 3, 0, 4, 0, 3, 2, 0, 2, 1]
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(PackedFloat32Array(p), 3))
		g.set_index(idx)
		var ng := g.to_non_indexed()
		ng.compute_vertex_normals()
		return ng


	var ctx
	var C
	var tx
	var L
	var root
	var k
	var r: Rng
	var out := {"plots": [], "nanoEdges": [], "fieldZones": []}
	var road_mat
	var tops := {}
	var top_order := []
	var sides := Sides.new()
	var excl := []
	var roof_g: T.Geometry
	var tree_mat
	var tree_mat_d
	var tree_mat_l
	var blob_g: T.Geometry
	var blob_hi := []
	var blob_n := 0
	var cone_g: T.Geometry
	var trunk_mat
	var cside: Array
	var cside_g: Array
	var cside_g2: Array
	var csoil: Array
	const WALL_COLS := ["#ece5d6", "#e4d9c4", "#d9d3c6", "#efe9dc", "#cdb89a"]
	const ROOF_COLS := ["#4a4f58", "#56677a", "#4d6457", "#5a5553", "#6a5448"]
	const TYPE_W := [["flood", 0.34], ["dry", 0.12], ["renge", 0.16], ["wheat", 0.1], ["veg", 0.1], ["nano", 0.1], ["grass", 0.08]]

	func _init(c, common, textures) -> void:
		ctx = c
		C = common
		tx = textures
		L = c.L

	func th(x: float, z: float) -> float:
		return C.terrain_h(x, z)

	func drape(x0: float, z0: float, x1: float, z1: float, w: float, mat, seg: float = 4.0):
		var length := sqrt((x1 - x0) ** 2 + (z1 - z0) ** 2)
		var n := maxi(1, ceili(length / seg))
		var dx := (x1 - x0) / length
		var dz := (z1 - z0) / length
		var px := -dz * w / 2.0
		var pz := dx * w / 2.0
		var pos := PackedFloat32Array()
		var idx := PackedInt32Array()
		for i in n + 1:
			var x := x0 + (x1 - x0) * i / n
			var z := z0 + (z1 - z0) * i / n
			for s in [-1, 1]:
				var xx: float = x + px * s
				var zz: float = z + pz * s
				pos.append(xx); pos.append(th(xx, zz) + 0.045); pos.append(zz)
			if i:
				var a := (i - 1) * 2
				idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(pos, 3))
		g.set_index(idx)
		g.compute_vertex_normals()
		if (g.attributes.normal as T.Attr).get_y(0) < 0.0:
			var ia := g.index
			var i := 0
			while i < ia.size():
				var t := ia[i + 1]
				ia[i + 1] = ia[i + 2]
				ia[i + 2] = t
				i += 3
			g.set_index(ia)
			g.compute_vertex_normals()
		var uv := PackedFloat32Array()
		uv.resize(pos.size() / 3 * 2)
		for i in pos.size() / 3:
			uv[i * 2] = pos[i * 3] / 5.0
			uv[i * 2 + 1] = -pos[i * 3 + 2] / 5.0
		g.set_attribute("uv", T.Attr.new(uv, 2))
		var m := T.MeshObj.new(g, mat)
		m.receive_shadow = true
		root.add(m)
		return m

	func excluded(x0: float, x1: float, z0: float, z1: float) -> bool:
		for e in excl:
			if x0 < e.x1 and x1 > e.x0 and z0 < e.z1 and z1 > e.z0:
				return true
		return false

	func pick_type(x: float, z: float) -> String:
		var n: float = Common.fbm(x / 90.0, z / 70.0, 2, 201) * 0.65 + r.f() * 0.35
		var acc := 0.0
		for tw in TYPE_W:
			acc += tw[1]
			if n * 1.02 < acc:
				return tw[0]
		return "grass"

	func add_top(t: String) -> Top:
		if not tops.has(t):
			tops[t] = Top.new()
			top_order.append(t)
		return tops[t]

	func quad(p0: Array, p1: Array, p2: Array, p3: Array, c0: Array, c1: Array) -> void:
		sides.quad(p0, p1, p2, p3, c0, c1)

	func add_plot(x0: float, x1: float, z0: float, z1: float, type: String) -> void:
		var lv := maxf(maxf(th(x0, z0), th(x1, z0)), maxf(th(x0, z1), th(x1, z1))) + 0.05
		var T2 := add_top(type)
		var b := T2.pos.size() / 3
		var rot_rows: bool = (type == "veg" or type == "wheat") and r.f() < 0.5
		for c in [[x0, z1], [x1, z1], [x1, z0], [x0, z0]]:
			var x: float = c[0]
			var z: float = c[1]
			if type == "flood":
				T2.vertex(x, lv, z, x - x0, z1 - z, [x1 - x0, z1 - z0])
			elif rot_rows:
				T2.vertex(x, lv, z, -z / 4.0, x / 4.0, null)
			else:
				T2.vertex(x, lv, z, x / 4.0, -z / 4.0, null)
		T2.tri6([b, b + 1, b + 2, b, b + 2, b + 3])
		var corners := [[x0, z1], [x1, z1], [x1, z0], [x0, z0], [x0, z1]]
		var cxm := (x0 + x1) / 2.0
		var czm := (z0 + z1) / 2.0
		var rh := lv + 0.13
		var RW := 0.36
		var gT: Array = cside_g if r.f() < 0.5 else cside_g2
		for i in 4:
			var ax: float = corners[i][0]
			var az: float = corners[i][1]
			var bx: float = corners[i + 1][0]
			var bz: float = corners[i + 1][1]
			var ox := (ax + bx) / 2.0 - cxm
			var oz := (az + bz) / 2.0 - czm
			var ol := sqrt(ox * ox + oz * oz)
			ox /= ol
			oz /= ol
			var ex := ax + ox * RW
			var ez := az + oz * RW
			var fx := bx + ox * RW
			var fz := bz + oz * RW
			var el := sqrt((bx - ax) ** 2 + (bz - az) ** 2)
			var ux := (bx - ax) / el
			var uz := (bz - az) / el
			var e2x := ex - ux * RW
			var e2z := ez - uz * RW
			var f2x := fx + ux * RW
			var f2z := fz + uz * RW
			quad([ax, lv - 0.05, az], [bx, lv - 0.05, bz], [bx, rh, bz], [ax, rh, az], csoil, csoil)
			quad([ax, rh, az], [bx, rh, bz], [f2x, rh, f2z], [e2x, rh, e2z], gT, gT)
			quad([e2x, th(e2x, e2z) - 0.2, e2z], [f2x, th(f2x, f2z) - 0.2, f2z], [f2x, rh, f2z], [e2x, rh, e2z], cside, gT)
		out.plots.append({"x0": x0, "x1": x1, "z0": z0, "z1": z1, "type": type, "y": lv})
		if type == "nano":
			out.nanoEdges.append({"x0": x0, "x1": x1, "z": z1, "y": lv})

	func tree(x: float, z: float, h: float, kind: String, grp, hi: bool = false) -> void:
		var y := th(x, z)
		if kind == "cedar":
			var m := T.MeshObj.new(cone_g, tree_mat_d)
			m.scale = Vector3(h * 0.2, h * 0.86, h * 0.2)
			m.position = Vector3(x, y + h * 0.14 + h * 0.43, z)
			m.cast_shadow = true
			m.receive_shadow = true
			grp.add(m)
			k.cyl(h * 0.025, h * 0.03, h * 0.2, trunk_mat, [x, y + h * 0.1, z], null, 6)
		else:
			var bg: T.Geometry = blob_hi[blob_n % 3] if hi else blob_g
			if hi:
				blob_n += 1
			var m := T.MeshObj.new(bg, tree_mat_l if kind == "light" else tree_mat)
			m.scale = Vector3(h * 0.34, h * 0.3, h * 0.34)
			m.position = Vector3(x, y + h * 0.66, z)
			m.cast_shadow = true
			m.receive_shadow = true
			grp.add(m)
			var bg2: T.Geometry = blob_hi[blob_n % 3] if hi else blob_g
			if hi:
				blob_n += 1
			var m2 := T.MeshObj.new(bg2, tree_mat_l if kind == "light" else tree_mat)
			m2.scale = Vector3(h * 0.22, h * 0.2, h * 0.22)
			m2.position = Vector3(x + h * 0.17, y + h * 0.5, z + h * 0.08)
			m2.cast_shadow = true
			grp.add(m2)
			k.cyl(h * 0.03, h * 0.04, h * 0.45, trunk_mat, [x, y + h * 0.22, z], null, 6)

	func build() -> Dictionary:
		root = T.Group.new()
		root.name = "env-far"
		ctx.add_static(root)
		k = ctx.kit(root)
		r = ctx.rng("env-far")
		var BR: Dictionary = Common.BRIDGE
		# ============================================================ farm roads (draped strips)
		road_mat = ctx.mat.toon("#c5bfb1", {"map": tx.ground, "paint": 0.05, "name": "env-farmroad"})
		var asphalt_mat = ctx.mat.toon("#85878b", {"map": tx.path, "paint": 0.04, "name": "env-farmasphalt"})
		drape(-700, -122, BR.x - 9, -122, 2.8, road_mat, 8)
		drape(BR.x + 9, -122, 700, -122, 2.8, road_mat, 8)
		drape(-700, -206.5, 700, -206.5, 3.0, road_mat, 8)
		for x in [-410, 55, 250, 460]:
			drape(x, -123.5, x, -292, 3.0, road_mat, 8)
		drape(BR.x, -178, BR.x, -300, 6.0, asphalt_mat, 6)
		drape(BR.x, -121, BR.x, -178, 6.0, asphalt_mat, 3)
		# ============================================================ fields
		var shrine := {"x": -78.0, "z": -168.0, "r": 19.0}
		excl.append({"x0": shrine.x - 22, "x1": shrine.x + 22, "z0": shrine.z - 22, "z1": shrine.z + 24})
		excl.append({"x0": shrine.x - 2.2, "x1": shrine.x + 2.2, "z0": shrine.z, "z1": -121.0})
		excl.append({"x0": -262.0 - 17, "x1": -262.0 + 17, "z0": -300.0, "z1": -255.0})
		var farms := [{"x": -300.0, "z": -150.0, "rot": 0.05}, {"x": 128.0, "z": -165.0, "rot": -0.04}, {"x": 340.0, "z": -245.0, "rot": 0.1},
			{"x": -525.0, "z": -240.0, "rot": -0.08}, {"x": -18.0, "z": -255.0, "rot": 0.02}, {"x": 560.0, "z": -150.0, "rot": 0.06}]
		for f in farms:
			excl.append({"x0": f.x - 18, "x1": f.x + 18, "z0": f.z - 16, "z1": f.z + 14})
		var greenhouses := [{"x": 205.0, "z": -140.0, "n": 5}, {"x": -250.0, "z": -252.0, "n": 4}, {"x": 420.0, "z": -175.0, "n": 3}]
		for gh in greenhouses:
			excl.append({"x0": gh.x - 3.5, "x1": gh.x + gh.n * 7 + 1, "z0": gh.z - 17, "z1": gh.z + 17})
		excl.append({"x0": BR.x - 16, "x1": BR.x + 16, "z0": -182.0, "z1": -118.0})
		cside = Common.lin("#9d9573")
		cside_g = Common.lin("#93b56c")
		cside_g2 = Common.lin("#a3bf75")
		csoil = Common.lin("#9a8766")
		var cols_x := [-700.0, -410.0, BR.x, 55.0, 250.0, 460.0, 700.0]
		var rows_z := [-123.6, -206.5, -292.0]
		for ci in cols_x.size() - 1:
			for ri in rows_z.size() - 1:
				var bx0: float = cols_x[ci] + (3.4 if cols_x[ci] == BR.x else 1.8)
				var bx1: float = cols_x[ci + 1] - (3.4 if cols_x[ci + 1] == BR.x else 1.8)
				var bz0: float = rows_z[ri + 1] + 1.8
				var bz1: float = rows_z[ri] - 1.8
				var x := bx0
				while x < bx1 - 6.0:
					var w := minf(bx1 - x, 20.0 + r.f() * 16.0)
					var z := bz1
					while z > bz0 + 5.0:
						var d := minf(z - bz0, 14.0 + r.f() * 9.0)
						var px0 := x + 0.35
						var px1 := x + w - 0.35
						var pz0 := z - d + 0.35
						var pz1 := z - 0.35
						if not excluded(px0, px1, pz0, pz1) and absf((px0 + px1) / 2.0) < 690.0:
							var t := pick_type((px0 + px1) / 2.0, (pz0 + pz1) / 2.0)
							add_plot(px0, px1, pz0, pz1, t)
						z -= d
					x += w
		var FT = tx.sub("fields")
		var top_mats := {
			"dry": ctx.mat.toon("#ffffff", {"map": FT.dry, "paint": 0.05, "name": "env-f-dry"}),
			"renge": ctx.mat.toon("#ffffff", {"map": FT.renge, "paint": 0.04, "name": "env-f-renge"}),
			"wheat": ctx.mat.toon("#ffffff", {"map": FT.wheat, "paint": 0.04, "name": "env-f-wheat"}),
			"veg": ctx.mat.toon("#ffffff", {"map": FT.veg, "paint": 0.05, "name": "env-f-veg"}),
			"nano": ctx.mat.toon("#ffffff", {"map": FT.nano, "paint": 0.04, "name": "env-f-nano"}),
			"grass": ctx.mat.toon("#ffffff", {"map": FT.grass, "paint": 0.05, "name": "env-f-grass"}),
			"flood": Shaders.water_material(ctx, {"mode": 1, "mud": "#a9ab91", "bank": "#88a06f"}),
		}
		for t in top_order:
			var tp: Top = tops[t]
			var g := T.Geometry.new()
			g.set_attribute("position", T.Attr.new(tp.pos, 3))
			var nrm := PackedFloat32Array()
			nrm.resize(tp.pos.size())
			for i in tp.pos.size():
				nrm[i] = 1.0 if i % 3 == 1 else 0.0
			g.set_attribute("normal", T.Attr.new(nrm, 3))
			g.set_attribute("uv", T.Attr.new(tp.uv, 2))
			if t == "flood":
				g.set_attribute("aSize", T.Attr.new(tp.size, 2))
			g.set_index(tp.idx)
			var m := T.MeshObj.new(g, top_mats[t])
			m.receive_shadow = t != "flood"
			m.name = "env-fields-" + t
			if t == "flood":
				ctx.no_batch(m)
			root.add(m)
		var sg := T.Geometry.new()
		sg.set_attribute("position", T.Attr.new(sides.pos, 3))
		sg.set_attribute("color", T.Attr.new(sides.col, 3))
		sg.set_index(sides.idx)
		sg.compute_vertex_normals()
		var sm := T.MeshObj.new(sg, ctx.mat.toon("#ffffff", {"vertexColors": true, "side": "double", "paint": 0.04, "name": "env-aze"}))
		sm.receive_shadow = true
		root.add(sm)
		# ============================================================ farmhouses, barns, windbreaks, greenhouses
		roof_g = gable_roof_geo()
		tree_mat = ctx.mat.toon("#628f5b", {"paint": 0.08, "name": "env-tree"})
		tree_mat_d = ctx.mat.toon("#4f7650", {"paint": 0.07, "name": "env-treeD"})
		tree_mat_l = ctx.mat.toon("#8fb56f", {"paint": 0.07, "name": "env-treeL"})
		blob_g = Common.smooth_blob(1)
		for v in 3:
			blob_hi.append(Foliage.shrub_geometry({"rx": 1, "ry": 1, "rz": 1, "detail": 2, "flatBottom": false, "cutBottom": false, "lumps": 0.24, "freq": 1.4,
				"puff": 0, "seed": 150 + v * 9, "colors": {"top": "#ffffff", "mid": "#f2f2f2", "base": "#d0d0d0"}, "normalBlend": 0.85}).clone().translate(0, -0.55, 0))
		cone_g = Geo.cone(1, 1, 8, 1)
		trunk_mat = ctx.mat.toon("#6f5a4c", {"paint": 0.05})
		for f in farms:
			var g = k.group([f.x, 0, f.z], f.rot)
			var kg = ctx.kit(g)
			var base := minf(minf(th(f.x - 10, f.z - 8), th(f.x + 10, f.z + 8)), th(f.x, f.z)) - 0.1
			g.position.y = base
			var wc = ctx.mat.toon(r.pick(WALL_COLS), {"paint": 0.08})
			var rc = ctx.mat.toon(r.pick(ROOF_COLS), {"paint": 0.06})
			kg.boxb(13, 5.6, 9, wc, [0, 0, 0])
			var hr := T.MeshObj.new(hip_roof_geo(14.8, 10.8, 3.0), rc)
			hr.position = Vector3(0, 5.6, 0)
			hr.cast_shadow = true
			hr.receive_shadow = true
			g.add(hr)
			kg.boxb(13.1, 0.14, 9.1, ctx.mat.toon("#8b8378"), [0, 2.75, 0])
			kg.box(9, 1.0, 0.05, ctx.mat.toon("#7d8f9c", {"paint": 0.02}), [0.6, 3.9, 4.52])
			kg.box(2.2, 2.0, 0.05, ctx.mat.toon("#5d5048", {"paint": 0.02}), [-3.5, 1.0, 4.52])
			kg.box(8, 1.1, 0.05, ctx.mat.toon("#8fa2ae", {"paint": 0.02}), [1.5, 1.3, 4.52])
			var bc = ctx.mat.toon(r.pick(["#b9ad98", "#a39684", "#c9c2b2"]), {"paint": 0.08})
			kg.boxb(8, 4.2, 6, bc, [-12.5, 0, -3])
			var br := T.MeshObj.new(roof_g, ctx.mat.toon(r.pick(["#7b8691", "#8a5a44", "#56677a"]), {"paint": 0.05}))
			br.scale = Vector3(8.8, 1.8, 6.8)
			br.position = Vector3(-12.5, 4.2, -3)
			br.cast_shadow = true
			g.add(br)
			kg.boxb(26, 1.2, 0.9, tree_mat, [-3, 0, 9.5])
			for i in 6:
				var lx: float = -14.0 + i * 5.6 + (r.f() - 0.5) * 2.0
				var lz: float = -10.0 - r.f() * 3.0
				var c := cos(f.rot)
				var s := sin(f.rot)
				var h: float = 10.0 + r.f() * 7.0
				var kind := "cedar" if r.f() < 0.55 else "broad"
				tree(f.x + lx * c + lz * s, f.z - lx * s + lz * c, h, kind, root, sqrt(f.x * f.x + f.z * f.z) < 260.0)
		var gh_mat = ctx.mat.toon("#e7edef", {"paint": 0.03, "name": "env-greenhouse"})
		var gh_end = ctx.mat.toon("#d5dde0", {"paint": 0.03})
		var gh_g := Geo.cylinder(1, 1, 1, 10, 1, true, 0, PI)
		gh_g.rotate_z(PI / 2.0)
		for gh in greenhouses:
			for i in gh.n:
				var x: float = gh.x + i * 7
				var y := th(x, gh.z) - 0.05
				var m := T.MeshObj.new(gh_g, gh_mat)
				m.scale = Vector3(30, 2.8, 2.7)
				m.rotation.y = PI / 2.0
				m.position = Vector3(x, y, gh.z)
				m.cast_shadow = true
				m.receive_shadow = true
				root.add(m)
				for s in [-1, 1]:
					var e := T.MeshObj.new(Geo.circle(1, 10, 0, PI), gh_end)
					e.scale = Vector3(2.7, 2.8, 1)
					e.position = Vector3(x, y, gh.z + s * 15)
					e.rotation.y = 0.0 if s > 0 else PI
					root.add(e)
		# ============================================================ shrine forest with a torii
		var cx: float = shrine.x
		var cz: float = shrine.z
		for i in 26:
			var a: float = r.f() * PI * 2.0
			var d: float = sqrt(r.f()) * shrine.r
			var x := cx + cos(a) * d
			var z := cz + sin(a) * d * 0.85
			if z > cz + 12.0 and absf(x - cx) < 4.0:
				continue
			var h: float = (17.0 if i < 12 else 13.0) + r.f() * 7.0
			var kind: String
			if i < 12:
				kind = "cedar"
			else:
				kind = "light" if r.f() < 0.3 else "broad"
			tree(x, z, h, kind, root, true)
		var ver = ctx.mat.toon("#d8603f", {"paint": 0.05, "name": "env-torii"})
		var blk = ctx.mat.toon("#3f3a40", {"paint": 0.03})
		var tz := cz + 19.0
		var ty := th(cx, tz)
		for s in [-1, 1]:
			k.cyl(0.22, 0.25, 4.6, ver, [cx + s * 1.9, ty + 2.3, tz], null, 10)
			k.cyl(0.3, 0.3, 0.35, blk, [cx + s * 1.9, ty + 0.17, tz], null, 10)
		k.box(5.4, 0.28, 0.42, blk, [cx, ty + 4.78, tz])
		k.box(5.0, 0.26, 0.36, ver, [cx, ty + 4.5, tz])
		k.box(4.4, 0.2, 0.26, ver, [cx, ty + 3.7, tz])
		k.box(0.22, 0.6, 0.2, ver, [cx, ty + 4.1, tz])
		k.boxb(2.4, 1.8, 2.2, ctx.mat.toon("#b89a78", {"paint": 0.07}), [cx, th(cx, cz + 6), cz + 6])
		var hr2 := T.MeshObj.new(roof_g, ctx.mat.toon("#4f5560", {"paint": 0.05}))
		hr2.scale = Vector3(3.2, 1.1, 3.0)
		hr2.rotation.y = PI / 2.0
		hr2.position = Vector3(cx, th(cx, cz + 6) + 1.8, cz + 6)
		hr2.cast_shadow = true
		root.add(hr2)
		drape(cx, tz + 0.5, cx, -123.3, 2.2, road_mat, 4)
		for s in [-1, 1]:
			var lx: float = cx + s * 2.3
			var lz: float = tz + 3.0
			var ly := th(lx, lz)
			k.boxb(0.5, 0.9, 0.5, ctx.mat.toon("#c9c4b8"), [lx, ly, lz])
			k.boxb(0.75, 0.3, 0.75, ctx.mat.toon("#b7b2a6"), [lx, ly + 0.9, lz])
		# ============================================================ hillside town + school
		var body_g := Geo.box(1, 1, 1)
		body_g.translate(0, 0.5, 0)
		var houses := []
		for cl in [[215.0, -318.0, 34, 95.0, 22.0], [-392.0, -314.0, 22, 62.0, 17.0], [520.0, -345.0, 14, 60.0, 18.0]]:
			for i in cl[2]:
				var x: float = cl[0] + (r.f() - 0.5) * 2.0 * cl[3]
				var z: float = cl[1] + (r.f() - 0.5) * 2.0 * cl[4]
				var clash := false
				for hh in houses:
					if absf(hh.x - x) < 11.0 and absf(hh.z - z) < 10.0:
						clash = true
						break
				if clash:
					continue
				var w := 8.0 + r.f() * 4.0
				var d := 7.0 + r.f() * 3.0
				var h := 5.8 if r.f() < 0.75 else 3.2
				var y := minf(minf(th(x - w / 2, z - d / 2), th(x + w / 2, z - d / 2)), minf(th(x - w / 2, z + d / 2), th(x + w / 2, z + d / 2))) - 0.3
				var y_top := maxf(maxf(th(x - w / 2, z - d / 2), th(x + w / 2, z - d / 2)), th(x, z)) + 0.2
				var rot := (r.f() - 0.5) * 0.3
				var wall = r.pick(WALL_COLS)
				var roof = r.pick(ROOF_COLS)
				houses.append({"x": x, "z": z, "w": w, "d": d, "h": h, "y": y, "yTop": y_top, "rot": rot, "wall": wall, "roof": roof})
		var bm := T.InstancedMesh.new(body_g, ctx.mat.toon("#ffffff", {"map": tx.facade, "paint": 0.05, "name": "env-farhouse"}), houses.size())
		var base_m := T.InstancedMesh.new(body_g, ctx.mat.toon("#ffffff", {"paint": 0.06, "name": "env-farbase"}), houses.size())
		var rm := T.InstancedMesh.new(roof_g, ctx.mat.toon("#ffffff", {"paint": 0.05, "name": "env-farroof"}), houses.size())
		for i in houses.size():
			var hh: Dictionary = houses[i]
			var q := T.quat_from_euler(Vector3(0, hh.rot, 0))
			base_m.set_matrix_at(i, T.compose(Vector3(hh.x, hh.y, hh.z), q, Vector3(hh.w + 1.6, hh.yTop - hh.y, hh.d + 1.6)))
			base_m.set_color_at(i, T.color("#c3c0b6"))
			bm.set_matrix_at(i, T.compose(Vector3(hh.x, hh.yTop - 0.05, hh.z), q, Vector3(hh.w, hh.h, hh.d)))
			bm.set_color_at(i, T.color(hh.wall))
			rm.set_matrix_at(i, T.compose(Vector3(hh.x, hh.yTop - 0.05 + hh.h, hh.z), q, Vector3(hh.w + 1.3, 2.6, hh.d + 1.3)))
			rm.set_color_at(i, T.color(hh.roof))
		for im in [bm, rm, base_m]:
			im.cast_shadow = false
			im.receive_shadow = true
			root.add(im)
		var sx := -262.0
		var sz := -305.0
		var sy := minf(th(sx - 26, sz - 7), th(sx + 26, sz + 7)) - 0.4
		var sgp = k.group([sx, sy, sz], 0.04)
		var ks = ctx.kit(sgp)
		var sch = ctx.mat.toon("#f0eee7", {"paint": 0.05})
		ks.boxb(52, 12.4, 12, sch, [0, 0, 0])
		ks.plane(51.6, 11.2, ctx.mat.toon("#ffffff", {"map": tx.school, "paint": 0.02}), [0, 6.3, 6.02])
		ks.boxb(52.6, 0.5, 12.6, ctx.mat.toon("#cfcac0"), [0, 12.4, 0])
		ks.boxb(8, 3, 8, sch, [0, 12.9, 0])
		ks.cyl(1.2, 1.2, 0.2, ctx.mat.toon("#fbfaf6"), [0, 14.4, 4.05], [PI / 2.0, 0, 0], 16)
		drape(sx, -298, sx, -258, 30, ctx.mat.toon("#d3c09c", {"map": tx.ground, "paint": 0.06, "name": "env-schoolground"}), 5)
		# ============================================================ trees on the hills
		var hill_tree_mat = Shaders.distant_material(ctx, {"mistY0": 0.0, "mistY1": 26.0, "mistAmt": 0.25, "fogMul": 0.5, "hazeK": 0.0008, "hazeMax": 0.5, "haze": "#c3d3e6"})
		var blob0 := Geo.icosahedron(1, 0)
		var pa: T.Attr = blob0.attributes.position
		var na: T.Attr = blob0.attributes.normal
		for i in pa.count():
			var l := sqrt(pa.get_x(i) ** 2 + pa.get_y(i) ** 2 + pa.get_z(i) ** 2)
			na.set_xyz(i, pa.get_x(i) / l, pa.get_y(i) / l, pa.get_z(i) / l)
		blob0.scale(1, 0.8, 1)
		var cone0 := Geo.cone(1, 1, 7, 1)
		cone0.translate(0, 0.5, 0)
		var blobs := []
		var cones := []
		var i2 := 0
		while i2 < 2600 and blobs.size() + cones.size() < 640:
			i2 += 1
			var x := (r.f() - 0.5) * 1400.0
			var z := -300.0 - r.f() * 520.0
			var m := Common.hill_mask(x, z)
			if m < 0.5:
				continue
			var h := th(x, z)
			var n := Common.fbm(x / 60.0, z / 60.0, 2, 301)
			if n < 0.42:
				continue
			var crest := th(x, z) - (th(x, z - 25) + th(x, z + 25)) / 2.0
			if crest < -1.5 and r.f() < 0.6:
				continue
			var cedar := Common.fbm(x / 140.0, z / 140.0, 2, 302) > 0.55
			if not cedar and crest < 0.6:
				continue
			var s := 5.0 + r.f() * 5.0 if cedar else 4.0 + r.f() * 3.0
			var cc = r.pick(["#5b7d5e", "#557a5c", "#62836a"]) if cedar else r.pick(["#739b64", "#6a9160", "#7ea56a", "#779f66"])
			(cones if cedar else blobs).append({"x": x, "z": z, "y": h, "s": s, "c": cc})
		for spec in [[blob0, blobs, false], [cone0, cones, true]]:
			var list: Array = spec[1]
			var im := T.InstancedMesh.new(spec[0], hill_tree_mat, list.size())
			for j in list.size():
				var t: Dictionary = list[j]
				var q := Quaternion(Vector3(0, 1, 0), r.f() * 6.28)
				if spec[2]:
					im.set_matrix_at(j, T.compose(Vector3(t.x, t.y - 0.5, t.z), q, Vector3(t.s * 0.45, t.s * 2.2, t.s * 0.45)))
				else:
					im.set_matrix_at(j, T.compose(Vector3(t.x, t.y + t.s * 0.35, t.z), q, Vector3(t.s, t.s, t.s)))
				im.set_color_at(j, T.color(t.c))
			im.cast_shadow = false
			im.receive_shadow = false
			root.add(im)
		# ============================================================ power pylons (wires) + lines
		var pylons := [[-650, -300], [-470, -286], [-290, -278], [-108, -274], [74, -276], [262, -281], [446, -290], [640, -312]]
		var branch := [[74, -276], [112, -410], [150, -545], [190, -690]]
		var pb := Pylons.new(ctx, C)
		pb.run(pylons)
		pb.run(branch)
		out["pylons"] = pylons
		# ============================================================ distant ridge rings
		rings()
		out["shrine"] = shrine
		out["farms"] = farms
		return out

	func rings() -> void:
		var W: Dictionary = L.WORLD.visual
		var specs := [
			{"ax": 745.0, "azN": 705.0, "azS": 760.0, "H0": 48.0, "H1": 150.0, "W": 75.0, "col": "#6f9483", "col2": "#7c9d88", "haze": "#b4c6dc", "hazeMin": 0.06, "crown": 15.0, "crownAmt": 0.75, "pink": 0.0, "young": 0.35, "dark": 0.45, "seed": 401, "mist": 0.22, "fogMul": 0.36},
			{"ax": 900.0, "azN": 880.0, "azS": 905.0, "H0": 70.0, "H1": 230.0, "W": 95.0, "col": "#7d97b2", "col2": "#86a0b9", "haze": "#aabfd8", "hazeMin": 0.12, "crown": 24.0, "crownAmt": 0.35, "pink": 0.0, "young": 0.15, "dark": 0.25, "seed": 402, "mist": 0.18, "fogMul": 0.3},
			{"ax": 1120.0, "azN": 1140.0, "azS": 1130.0, "H0": 95.0, "H1": 330.0, "W": 130.0, "col": "#94a8c8", "col2": "#9aadcc", "haze": "#adbfdb", "hazeMin": 0.2, "crown": 30.0, "crownAmt": 0.0, "pink": 0.0, "young": 0.0, "dark": 0.0, "seed": 403, "mist": 0.15, "fogMul": 0.26},
		]
		var rows_f := [-1.0, -0.62, -0.3, -0.08, 0.1, 0.45, 1.0]
		var shape := [-0.18, 0.3, 0.72, 0.97, 1.0, 0.7, 0.15]
		for R in specs:
			var K := T.js_round(PI * 2.0 * R.ax / R.crown)
			var mat = Shaders.distant_material(ctx, {"arc": true, "wrap": float(K), "vertexColors": true, "crown": R.crown, "crownAmt": R.crownAmt, "pinkAmt": R.pink, "youngAmt": R.young, "darkAmt": R.dark, "patch": 160.0, "haze": R.haze, "hazeMin": R.hazeMin, "hazeMax": 0.72, "hazeK": 0.0009, "mist": "#dfe8f2", "mistY0": 0.0, "mistY1": 60.0 + R.H0, "mistAmt": R.mist, "fogMul": R.fogMul, "rim": 1.0})
			var N := 420
			var pos := PackedFloat32Array()
			var col := PackedFloat32Array()
			var idx := []
			var uv := PackedFloat32Array()
			var tan := PackedFloat32Array()
			var cA := Common.lin(R.col)
			var cB := Common.lin(R.col2)
			var seed: int = R.seed
			for i in N + 1:
				var thv := float(i) / N * PI * 2.0
				var dx := sin(thv)
				var dz := -cos(thv)
				var az: float = R.azN if dz < 0.0 else R.azS
				var Rr := 1.0 / pow(pow(absf(dx) / R.ax, 4.0) + pow(absf(dz) / az, 4.0), 0.25)
				var nb := Common.sstep(0.0, 0.85, (1.0 + cos(thv)) / 2.0)
				var ux := dx * Rr
				var uz := dz * Rr
				var peaks := 0.42 + 0.58 * (0.55 * Common.fbm(ux / 300.0, uz / 300.0, 3, seed + 3) + 0.45 * Common.ridged(ux / 340.0, uz / 340.0, 3, seed))
				var Hc: float = lerpf(R.H0, R.H1, nb) * peaks * (0.8 + 0.4 * Common.fbm(ux / 700.0, uz / 700.0, 2, seed + 1))
				for j in rows_f.size():
					var f: float = rows_f[j]
					var spur := (Common.fbm(ux / 55.0 + j * 37, uz / 55.0, 3, seed + 5) - 0.5) if (j >= 1 and j <= 3) else 0.0
					var off: float = R.W * f + spur * R.W * 0.5
					var x := dx * (Rr + off)
					var z := dz * (Rr + off)
					var bx := clampf(x, W.x0, W.x1)
					var bz := clampf(z, W.z0, W.z1)
					var base := th(bx, bz) - 6.0
					var y: float = base + Hc * shape[j] * (1.0 + spur * 0.5) + (-8.0 if j == 0 else 0.0)
					pos.append(x); pos.append(y); pos.append(z)
					uv.append(thv / (PI * 2.0) * K * R.crown); uv.append(y)
					tan.append(cos(thv)); tan.append(0.0); tan.append(sin(thv))
					var cc := Common.mix3(cA, cB, Common.fbm(ux / 180.0, uz / 180.0 + j, 2, seed + 9))
					col.append(cc[0]); col.append(cc[1]); col.append(cc[2])
				if i:
					var nr := rows_f.size()
					var a := (i - 1) * nr
					var b := i * nr
					for j in nr - 1:
						idx.append_array([a + j, b + j, a + j + 1, a + j + 1, b + j, b + j + 1])
			var g := T.Geometry.new()
			g.set_attribute("position", T.Attr.new(pos, 3))
			g.set_attribute("color", T.Attr.new(col, 3))
			g.set_attribute("uv", T.Attr.new(uv, 2))
			g.set_attribute("aTan", T.Attr.new(tan, 3))
			g.set_index(idx)
			g.compute_vertex_normals()
			if (g.attributes.normal as T.Attr).get_z(1) < 0.0:
				var i := 0
				while i < idx.size():
					var t = idx[i + 1]
					idx[i + 1] = idx[i + 2]
					idx[i + 2] = t
					i += 3
				g.set_index(idx)
				g.compute_vertex_normals()
			var m := T.MeshObj.new(g, mat)
			m.name = "env-ring"
			m.frustum_culled = false
			mat.side = "double"
			ctx.no_batch(m)
			root.add(m)


class Top extends RefCounted:
	var pos := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var idx := PackedInt32Array()
	var size := PackedFloat32Array()

	func vertex(x: float, y: float, z: float, u: float, v: float, sz) -> void:
		pos.append(x); pos.append(y); pos.append(z)
		uv.append(u); uv.append(v)
		if sz != null:
			size.append(sz[0]); size.append(sz[1])

	func tri6(a: Array) -> void:
		idx.append_array(a)


class Sides extends RefCounted:
	var pos := PackedFloat32Array()
	var col := PackedFloat32Array()
	var idx := PackedInt32Array()

	func quad(p0: Array, p1: Array, p2: Array, p3: Array, c0: Array, c1: Array) -> void:
		var s0 := pos.size() / 3
		for p in [p0, p1, p2, p3]:
			pos.append(p[0]); pos.append(p[1]); pos.append(p[2])
		for c in [c0, c0, c1, c1]:
			col.append(c[0]); col.append(c[1]); col.append(c[2])
		idx.append_array([s0, s0 + 1, s0 + 2, s0, s0 + 2, s0 + 3])


## Lattice pylons drawn with the wire list, and the sagging lines between them.
class Pylons extends RefCounted:
	var ctx
	var C
	var built := {}
	const STEEL := "#7f8994"
	const WIRE := "#59606a"

	func _init(c, common) -> void:
		ctx = c
		C = common

	func pylon(x: float, z: float, rot: float) -> Dictionary:
		var key := "%s,%s" % [x, z]
		if built.has(key):
			return built[key]
		var y: float = C.terrain_h(x, z) - 0.2
		var H := 44.0
		var c := cos(rot)
		var s := sin(rot)
		var P := func(lx: float, ly: float, lz: float) -> Array: return [x + lx * c + lz * s, y + ly, z - lx * s + lz * c]
		var lv := [[0.0, 4.2], [13.0, 3.0], [26.0, 1.9], [33.0, 1.5], [38.5, 1.3], [H, 0.8]]
		var legs := [[1, 1], [1, -1], [-1, -1], [-1, 1]]
		for lg in legs:
			ctx.wires.add(lv.map(func(l): return P.call(lg[0] * l[1], l[0], lg[1] * l[1])), {"width": 0.34, "color": STEEL})
		for i in lv.size():
			var ly: float = lv[i][0]
			var hw: float = lv[i][1]
			ctx.wires.add((legs + [legs[0]]).map(func(lg): return P.call(lg[0] * hw, ly, lg[1] * hw)), {"width": 0.22, "color": STEEL})
			if i < lv.size() - 1:
				var ly2: float = lv[i + 1][0]
				var hw2: float = lv[i + 1][1]
				for f in 4:
					var a: Array = legs[f]
					var b: Array = legs[(f + 1) % 4]
					ctx.wires.add([P.call(a[0] * hw, ly, a[1] * hw), P.call(b[0] * hw2, ly2, b[1] * hw2)], {"width": 0.16, "color": STEEL})
					ctx.wires.add([P.call(b[0] * hw, ly, b[1] * hw), P.call(a[0] * hw2, ly2, a[1] * hw2)], {"width": 0.16, "color": STEEL})
		var tips := []
		for arm in [[26.0, 7.6], [33.0, 8.4], [38.5, 7.0]]:
			for sd in [-1, 1]:
				var ly: float = arm[0]
				var ln: float = arm[1]
				var hw := 0.0
				for l in lv:
					if l[0] == ly:
						hw = l[1]
						break
				ctx.wires.add([P.call(sd * hw, ly, 0.9), P.call(sd * ln, ly + 0.3, 0), P.call(sd * hw, ly, -0.9)], {"width": 0.2, "color": STEEL})
				ctx.wires.add([P.call(sd * hw, ly + 1.8, 0), P.call(sd * ln, ly + 0.3, 0)], {"width": 0.16, "color": STEEL})
				var tip: Array = P.call(sd * (ln - 0.3), ly + 0.2, 0)
				var ins: Array = P.call(sd * (ln - 0.3), ly - 2.4, 0)
				ctx.wires.add([tip, ins], {"width": 0.12, "color": "#c9cdd2"})
				tips.append(ins)
		ctx.wires.add([P.call(0.8, H, 0.8), P.call(0, H + 3.2, 0), P.call(-0.8, H, -0.8)], {"width": 0.18, "color": STEEL})
		var res := {"tips": tips, "peak": P.call(0, H + 3.1, 0)}
		built[key] = res
		return res

	func run(pts: Array) -> void:
		var prev = null
		for i in pts.size():
			var x := float(pts[i][0])
			var z := float(pts[i][1])
			var nx := float(pts[mini(i + 1, pts.size() - 1)][0])
			var nz := float(pts[mini(i + 1, pts.size() - 1)][1])
			var px := float(pts[maxi(i - 1, 0)][0])
			var pz := float(pts[maxi(i - 1, 0)][1])
			var rot := atan2(nx - px, nz - pz) + PI / 2.0
			var p := pylon(x, z, rot)
			if prev != null:
				for j in 6:
					var a: Array = prev.tips[j]
					var best: Array = p.tips[0]
					var bd := 1e9
					for b in p.tips:
						var d: float = (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2
						if d < bd:
							bd = d
							best = b
					ctx.wires.add(Geo.catenary(a, best, sqrt(bd) * 0.028, 18), {"width": 0.045, "color": WIRE})
				var span := sqrt((prev.peak[0] - p.peak[0]) ** 2 + (prev.peak[2] - p.peak[2]) ** 2)
				ctx.wires.add(Geo.catenary(prev.peak, p.peak, span * 0.022, 18), {"width": 0.035, "color": WIRE})
			prev = p
