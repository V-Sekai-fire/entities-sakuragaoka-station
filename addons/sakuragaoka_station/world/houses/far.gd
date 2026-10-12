# houses/far.js: the far town (L.FAR_TOWN). Dense low-detail houses (instanced bodies and roofs with
# eaves) and a few small apartment blocks and garden trees, so the horizon reads as one town.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Lot = preload("res://addons/sakuragaoka_station/world/houses/lot.gd")


## A triangular prism along x with the eaves overhang baked in: the base spans z in [-0.5, 0.5] at
## y = 0, the ridge is at y = 1.
static func unit_gable() -> T.Geometry:
	var o := 0.09  # relative eave overhang
	var g := T.Geometry.new()
	var P := []
	var N := []
	var I := []
	var quad := func(a: Array, b: Array, c: Array, d: Array, n: Array) -> void:
		var k: int = P.size() / 3
		for q in [a, b, c, d]:
			P.append_array(q)
		for i in 4:
			N.append_array(n)
		I.append_array([k, k + 1, k + 2, k, k + 2, k + 3])
	var tri := func(a: Array, b: Array, c: Array, n: Array) -> void:
		var k: int = P.size() / 3
		for q in [a, b, c]:
			P.append_array(q)
		for i in 3:
			N.append_array(n)
		I.append_array([k, k + 1, k + 2])
	var e := -0.5 - o
	var E := 0.5 + o
	var yE := -o * 1.0
	var t := 0.06
	var n1 := Vector3(0, 0.5 + o, 1).normalized()
	var n2 := Vector3(0, 0.5 + o, -1).normalized()
	quad.call([E, yE, E], [E, 1, 0], [e, 1, 0], [e, yE, E], [n1.x, n1.y, n1.z])
	quad.call([e, yE, e], [e, 1, 0], [E, 1, 0], [E, yE, e], [n2.x, n2.y, n2.z])
	# eave edge thickness (fascia)
	quad.call([e, yE, E], [e, yE - t, E], [E, yE - t, E], [E, yE, E], [0, 0, 1])
	quad.call([E, yE, e], [E, yE - t, e], [e, yE - t, e], [e, yE, e], [0, 0, -1])
	# gable triangles (wall-coloured by the same instance colour; fine at distance)
	tri.call([0.5, 0, 0.5], [0.5, 0, -0.5], [0.5, 1 - o * 1.2, 0], [1, 0, 0])
	tri.call([-0.5, 0, -0.5], [-0.5, 0, 0.5], [-0.5, 1 - o * 1.2, 0], [-1, 0, 0])
	# underside
	quad.call([e, yE - t, E], [e, yE - t, e], [E, yE - t, e], [E, yE - t, E], [0, -1, 0])
	# fix winding to match normals
	var vp := func(i: int) -> Vector3: return Vector3(P[i * 3], P[i * 3 + 1], P[i * 3 + 2])
	for i in range(0, I.size(), 3):
		var va: Vector3 = vp.call(I[i])
		var nn: Vector3 = (vp.call(I[i + 1]) - va).cross(vp.call(I[i + 2]) - va)
		var j: int = I[i]
		var n0 := Vector3(N[j * 3], N[j * 3 + 1], N[j * 3 + 2])
		if nn.dot(n0) < 0.0:
			var t2: int = I[i + 1]
			I[i + 1] = I[i + 2]
			I[i + 2] = t2
	g.set_attribute("position", T.Attr.new(PackedFloat32Array(P), 3))
	g.set_attribute("normal", T.Attr.new(PackedFloat32Array(N), 3))
	g.set_index(PackedInt32Array(I))
	var uv := PackedFloat32Array()
	uv.resize(P.size() / 3 * 2)
	g.set_attribute("uv", T.Attr.new(uv, 2))
	return g


static func unit_hip() -> T.Geometry:
	var g := T.Geometry.new()
	var o := 0.09
	var E := 0.5 + o
	var yE := -o
	var rl := 0.18
	var P := []
	var I := []
	var add := func(pts: Array) -> void:
		var k: int = P.size() / 3
		for p in pts:
			P.append_array(p)
		if pts.size() == 4:
			I.append_array([k, k + 1, k + 2, k, k + 2, k + 3])
		else:
			I.append_array([k, k + 1, k + 2])
	add.call([[-E, yE, E], [E, yE, E], [rl, 1, 0], [-rl, 1, 0]])
	add.call([[E, yE, -E], [-E, yE, -E], [-rl, 1, 0], [rl, 1, 0]])
	add.call([[E, yE, E], [E, yE, -E], [rl, 1, 0]])
	add.call([[-E, yE, -E], [-E, yE, E], [-rl, 1, 0]])
	add.call([[-E, yE - 0.05, E], [-E, yE - 0.05, -E], [E, yE - 0.05, -E], [E, yE - 0.05, E]])
	g.set_attribute("position", T.Attr.new(PackedFloat32Array(P), 3))
	g.set_index(PackedInt32Array(I))
	var ng := g.to_non_indexed()
	ng.compute_vertex_normals()
	# make sure faces point outward (flip if the normal points toward the centre)
	var pos: T.Attr = ng.get_attribute("position")
	for i in range(0, pos.count(), 3):
		var a := pos.v3(i)
		var b := pos.v3(i + 1)
		var c := pos.v3(i + 2)
		var n := (b - a).cross(c - a)
		var m := (a + b + c) * (1.0 / 3.0)
		m.y -= 0.3
		if n.dot(m) < 0.0:
			pos.set_xyz(i + 1, c.x, c.y, c.z)
			pos.set_xyz(i + 2, b.x, b.y, b.z)
	ng.compute_vertex_normals()
	var uv := PackedFloat32Array()
	uv.resize(pos.count() * 2)
	ng.set_attribute("uv", T.Attr.new(uv, 2))
	return ng


static func build_far_town(H) -> Dictionary:
	var ctx = H.ctx
	var L = H.L
	var r = ctx.rng("houses-far")
	var TX = ctx.tex
	# facade textures per storey count (canvas drawings in the original; keyed stand-ins here)
	var facade := func(floors: int): return TX.draw(256, 256, null, {"key": "houses_farfacade%d" % floors})
	var mWallF := [1, 2, 3].map(func(fl): return ctx.mat.toon("#ffffff", {"map": facade.call(fl), "paint": 0.05}))
	var apt_tex = TX.draw(128, 128, null, {"key": "houses_farapt"})
	var mApt = ctx.mat.toon("#ffffff", {"map": apt_tex, "paint": 0.05})
	var mRoof = ctx.mat.toon("#ffffff", {"paint": 0.05})
	var mTree = ctx.mat.toon("#ffffff", {"paint": 0.07})
	var box := Geo.box(1, 1, 1).translate(0, 0.5, 0)
	var gable := unit_gable()
	var hip := unit_hip()
	var tree := Geo.icosahedron(0.5, 1)
	var items := {"body1": [], "body2": [], "body3": [], "gable": [], "hip": [], "apt": [], "aptRoof": [], "tree": []}
	var wall_cols: Array = Lot.PAL.plaster + Lot.PAL.paint + Lot.PAL.siding + Lot.PAL.tile + ["#e9e1cf", "#f0ece2"]
	var roof_cols: Array = Lot.PAL.kawara + Lot.PAL.kawara + Lot.PAL.metal
	var tree_cols := ["#6f9a5a", "#5f8c5c", "#7aa564", "#4f7a52", "#86ad6a"]
	var mat4 := func(x: float, y: float, z: float, ry: float, sx: float, sy: float, sz: float) -> Transform3D:
		return T.compose(Vector3(x, y, z), T.quat_from_euler(Vector3(0, ry, 0)), Vector3(sx, sy, sz))
	var skip_road := func(x: float, z: float) -> bool:
		return (z > 128 and x > -2 and x < 16) or (z > 128 and absf(z - 170) < 4) or (absf(x) > 95 and absf(z - 40) < 4) or (absf(x) > 95 and fmod(absf(x), 90.0) < 5 and false)
	for R in L.FAR_TOWN:
		var cw := 11.5
		var cd := 11.0
		var x: float = R.x0 + cw / 2.0
		while x < R.x1 - 3:
			var z: float = R.z0 + cd / 2.0
			while z < R.z1 - 3:
				# lanes every few cells
				var ix := int(T.js_round((x - R.x0) / cw))
				var iz := int(T.js_round((z - R.z0) / cd))
				if ix % 5 == 2 or iz % 6 == 3:
					if r.f() < 0.12:
						var tx: float = x + (r.f() - 0.5) * 6
						var tz: float = z + (r.f() - 0.5) * 6
						items.tree.append([tx, tz, 2 + r.f() * 2.5])
					z += cd
					continue
				if z < -82 or skip_road.call(x, z):
					z += cd
					continue
				if r.f() < 0.07:
					items.tree.append([x, z, 3 + r.f() * 3])
					items.tree.append([x + 3, z - 2, 2.5 + r.f() * 2])
					z += cd
					continue
				var px: float = x + (r.f() - 0.5) * 2.4
				var pz: float = z + (r.f() - 0.5) * 2.2
				var ry: float = (0.0 if r.f() < 0.5 else PI / 2.0) + (r.f() - 0.5) * 0.12
				var w: float = 6.5 + r.f() * 2.8
				var d: float = 6 + r.f() * 2.2
				var gH: float = minf(minf(L.height_at(px - 3, pz - 3), L.height_at(px + 3, pz + 3)), L.height_at(px, pz))
				var apt: bool = r.f() < 0.06
				if apt:
					var afl: int = 3 + floori(r.f() * 2)
					var ahh: float = afl * 2.9
					var aw: float = 14 + r.f() * 6
					var ad: float = 8 + r.f() * 2
					items.apt.append([px, gH - 0.3, pz, ry, aw, ahh + 0.3, ad, r.pick(["#e9e1cf", "#dcd6c8", "#e4e0d6", "#d6dde0"])])
					items.aptRoof.append([px, gH + ahh, pz, ry, aw + 0.3, 0.45, ad + 0.3, "#9d9c96"])
					z += cd
					continue
				var fl: int = 1 if r.f() < 0.12 else (2 if r.f() < 0.9 else 3)
				var hh: float = fl * 2.85 + 0.45
				var wc = r.pick(wall_cols)
				var rc = r.pick(roof_cols)
				items["body%d" % fl].append([px, gH - 0.4, pz, ry, w, hh + 0.4, d, wc])
				var hipR: bool = r.f() < 0.5
				var pitch: float = 0.42 + r.f() * 0.12
				(items.hip if hipR else items.gable).append([px, gH + hh, pz, ry, w, (minf(w, d) / 2.0 + 0.4) * pitch, d, rc])
				# 1F wing
				if fl >= 2 and r.f() < 0.4:
					var ww: float = w * 0.45
					var wd: float = 2.6 + r.f() * 1.2
					var c := cos(ry)
					var s := sin(ry)
					var ox: float = (-1.0 if r.f() < 0.5 else 1.0) * (w / 2.0 - ww / 2.0)
					var oz: float = d / 2.0 + wd / 2.0 - 0.2
					var wx: float = px + ox * c + oz * s
					var wz: float = pz - ox * s + oz * c
					items.body1.append([wx, gH - 0.4, wz, ry, ww, 3.3 + 0.4, wd, wc])
					items.hip.append([wx, gH + 3.3, wz, ry, ww, 0.9, wd, rc])
				if r.f() < 0.25:
					var tx2: float = px + (r.f() - 0.5) * w * 1.6
					items.tree.append([tx2, pz + d / 2.0 + 1.8, 2.2 + r.f() * 1.8])
				z += cd
			x += cw
	var out := []
	var inst := func(geo: T.Geometry, mat, list: Array, col_idx: int, no_shadow: bool = false) -> void:
		if list.is_empty():
			return
		var m := T.InstancedMesh.new(geo, mat, list.size())
		for i in list.size():
			var q: Array = list[i]
			m.set_matrix_at(i, mat4.call(q[0], q[1], q[2], q[3], q[4], q[5], q[6]))
			m.set_color_at(i, T.color(q[col_idx]))
		m.cast_shadow = not no_shadow
		m.receive_shadow = true
		m.name = "houses-far"
		ctx.add_static(m)
		out.append(m)
	inst.call(box, mWallF[0], items.body1, 7)
	inst.call(box, mWallF[1], items.body2, 7)
	inst.call(box, mWallF[2], items.body3, 7)
	inst.call(gable, mRoof, items.gable, 7)
	inst.call(hip, mRoof, items.hip, 7)
	inst.call(box, mApt, items.apt, 7)
	inst.call(box, mRoof, items.aptRoof, 7)
	# trees
	var tl := []
	for it in items.tree:
		var g: float = L.height_at(it[0], it[1])
		var s: float = it[2]
		var rot: float = r.f() * 6
		tl.append([it[0], g + s * 0.55, it[1], rot, s * 1.1, s * 0.95, s * 1.1, r.pick(tree_cols)])
	inst.call(tree, mTree, tl, 7)
	var trunks := []
	for it in items.tree:
		trunks.append([it[0], L.height_at(it[0], it[1]) - 0.2, it[1], 0, 0.25, it[2] * 0.35, 0.25, "#6e5646"])
	inst.call(box, mRoof, trunks, 7, true)
	return {"count": items.body1.size() + items.body2.size() + items.body3.size() + items.apt.size(), "meshes": out}
