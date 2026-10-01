# environment/levee.js: the levee-top path (R5) with painted edge lines, concrete stairs on the
# town-side slope, benches, the wooden promenade signboard, lamp posts, river km posts and a notice.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Common = preload("res://addons/sakuragaoka_station/world/environment/common.gd")

const STAIRS := [
	{"x": -12.0, "w": 3.0, "rails": false, "bike": true},
	{"x": 40.0, "w": 2.2, "rails": true, "bike": false},
]
const BENCHES := [{"x": -58.5}, {"x": 17.5}, {"x": 63.0}, {"x": -101.0}]
const LAMPS := [-121.0, -81.0, -41.0, 1.5, 44.5, 81.0, 121.0]


static func path_y(L) -> float:
	return L.ROADS.R5.y + 0.03


## z on the town-side slope where height_at == y (inverse of the smoothstep profile).
static func z_at_height(y: float) -> float:
	var target := clampf(y / 3.2, 0.0, 1.0)
	var a := 0.0
	var b := 1.0
	for i in 40:
		var m := (a + b) / 2.0
		if Common.sstep(0.0, 1.0, m) < target:
			a = m
		else:
			b = m
	return -84.0 - 7.5 * (a + b) / 2.0


static func build_levee(ctx, _C, tx) -> Dictionary:
	var L = ctx.L
	var R5: Dictionary = L.ROADS.R5
	var PATH_Y := path_y(L)
	var grp := T.Group.new()
	grp.name = "env-levee"
	ctx.add_static(grp)
	var k = ctx.kit(grp)
	# ------------------------------------------------------------ path surface + edge skirts
	var mat = ctx.mat.toon("#d9d6cd", {"map": tx.path, "paint": 0.04, "name": "env-r5"})
	var x0: float = R5.x0
	var x1: float = R5.x1
	var zN: float = R5.z - R5.halfW
	var zS: float = R5.z + R5.halfW
	var pos := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var nrm := PackedFloat32Array()
	var idx := PackedInt32Array()
	var n := 52
	for i in n + 1:
		var x := x0 + (x1 - x0) * i / n
		for e in [[zS, PATH_Y - 0.09, 0, 1], [zS, PATH_Y, 1, 0], [zN, PATH_Y, 1, 0], [zN, PATH_Y - 0.09, 0, -1]]:
			pos.append(x); pos.append(e[1]); pos.append(e[0])
			uv.append(x / 4.2); uv.append(-float(e[0]) / 4.2 + (0.0 if e[2] else 0.1))
			nrm.append(0.0); nrm.append(e[2]); nrm.append(e[3])
		if i:
			var a := (i - 1) * 4
			var b := i * 4
			for q in 3:
				idx.append_array([a + q, b + q, a + q + 1, a + q + 1, b + q, b + q + 1])
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(pos, 3))
	g.set_attribute("normal", T.Attr.new(nrm, 3))
	g.set_attribute("uv", T.Attr.new(uv, 2))
	g.set_index(idx)
	var m := T.MeshObj.new(g, mat)
	m.receive_shadow = true
	m.cast_shadow = false
	m.name = "env-r5-path"
	grp.add(m)
	var line_mat = ctx.mat.decal("#f1efe8", {"paint": 0.03})
	var r = ctx.rng("env-r5-lines")
	for z in [zS - 0.22, zN + 0.22]:
		var x := x0 + 0.4
		while x < x1 - 0.4:
			var len := minf(x1 - 0.4 - x, 6.0 + r.f() * 14.0)
			var near := false
			for s in STAIRS:
				if absf(x + len / 2.0 - s.x) < s.w / 2.0 + len / 2.0:
					near = true
					break
			near = near and z > R5.z
			if not near:
				k.box(len, 0.01, 0.11, line_mat, [x + len / 2.0, PATH_Y + 0.006, z])
			x += len + (0.3 + r.f() * 0.5 if r.f() < 0.25 else 0.02)
	var mark = ctx.tex.draw(512, 128)
	var mm = ctx.mat.decal("#ffffff", {"map": mark, "paint": 0.02})
	for e in [[-30.0, -PI / 2.0], [72.0, PI / 2.0]]:
		var p = k.plane(2.4, 0.6, mm, [e[0], PATH_Y + 0.007, R5.z], [-PI / 2.0, 0, e[1]])
		p.receive_shadow = true
	# ------------------------------------------------------------ concrete stairs on the town-side slope
	var conc = ctx.mat.toon("#d4d0c5", {"paint": 0.08, "name": "env-stair"})
	var conc_dark = ctx.mat.toon("#bdb9ad", {"paint": 0.07})
	var steel = ctx.mat.toon("#cfd4d6", {"paint": 0.02})
	var ns := 18
	var rise := 3.2 / ns
	var stair_info := []
	for S in STAIRS:
		var nos := []
		for i in ns:
			var zA := z_at_height(i * rise) + (0.25 if i == 0 else 0.0)
			var zB := z_at_height((i + 1) * rise)
			var top := (i + 1) * rise
			var bottom := i * rise - 0.35
			k.box(S.w, top - bottom, zA - zB, conc, [S.x, (top + bottom) / 2.0, (zA + zB) / 2.0])
			k.box(S.w, 0.012, 0.05, conc_dark, [S.x, top + 0.006, zA - 0.06])
			ctx.physics.addWalkBox(S.x, (zA + zB) / 2.0, S.w, zA - zB, 0, top)
			nos.append([zA, top])
		nos.append([z_at_height(3.2) - 0.02, 3.2])
		var pts := [[83.55, 0.16]]
		for e in nos:
			pts.append([-e[0], e[1] + 0.14])
		var last: float = nos[nos.size() - 1][0]
		pts.append([-last, 3.2 + 0.14 - 0.1])
		pts.append([-last, 2.6])
		for i in range(nos.size() - 1, -1, -1):
			pts.append([-nos[i][0], nos[i][1] - rise - 0.5])
		pts.append([83.55, -0.4])
		for s in [-1, 1]:
			var gg: T.Geometry = ctx.geo.extrude(pts, 0.2)
			gg.rotate_y(PI / 2.0)
			var cw := T.MeshObj.new(gg, conc)
			cw.position = Vector3(S.x + s * (S.w / 2.0 + 0.1), 0, 0)
			cw.cast_shadow = true
			cw.receive_shadow = true
			grp.add(cw)
		if S.bike:
			var bpos := PackedFloat32Array()
			var bidx := PackedInt32Array()
			var xs0: float = S.x + S.w / 2.0 - 0.45
			var xs1: float = S.x + S.w / 2.0 - 0.05
			var line := [[-83.6, 0.04]]
			for e in nos:
				line.append([e[0], e[1] + 0.02])
			for i in line.size():
				var z: float = line[i][0]
				var y: float = line[i][1]
				bpos.append_array([xs0, y, z, xs1, y, z])
				if i:
					var a := (i - 1) * 2
					bidx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
			var bg := T.Geometry.new()
			bg.set_attribute("position", T.Attr.new(bpos, 3))
			bg.set_index(bidx)
			bg.compute_vertex_normals()
			if (bg.attributes.normal as T.Attr).get_y(0) < 0.0:
				var ia := bg.index
				var i := 0
				while i < ia.size():
					var t := ia[i + 1]
					ia[i + 1] = ia[i + 2]
					ia[i + 2] = t
					i += 3
				bg.set_index(ia)
				bg.compute_vertex_normals()
			var bm := T.MeshObj.new(bg, conc_dark)
			bm.receive_shadow = true
			grp.add(bm)
			for i in line.size() - 1:
				var za: float = line[i][0]
				var ya: float = line[i][1]
				var zb: float = line[i + 1][0]
				var yb: float = line[i + 1][1]
				var len := sqrt((za - zb) ** 2 + (ya - yb) ** 2)
				k.box(0.06, 0.06, len, conc, [xs0 - 0.03, (ya + yb) / 2.0 + 0.03, (za + zb) / 2.0], [atan2(yb - ya, za - zb), 0, 0])
		if S.rails:
			for s in [-1, 1]:
				var xr: float = S.x + s * (S.w / 2.0 - 0.12)
				var rail_pts := []
				var i := 0
				while i <= ns:
					rail_pts.append(nos[mini(i, nos.size() - 1)])
					i += 3
				rail_pts.append(nos[nos.size() - 1])
				for j in rail_pts.size():
					var z: float = rail_pts[j][0]
					var y: float = rail_pts[j][1]
					k.cyl(0.028, 0.028, 0.9, steel, [xr, y + 0.45, z - 0.12], null, 8)
					ctx.physics.addCylinder(xr, z - 0.12, 0.06, y, y + 1.0)
					if j:
						var z0: float = rail_pts[j - 1][0]
						var y0: float = rail_pts[j - 1][1]
						var len := sqrt((z - z0) ** 2 + (y - y0) ** 2)
						var ang := atan2(y - y0, z0 - z)
						k.cyl(0.03, 0.03, len, steel, [xr, (y + y0) / 2.0 + 0.88, (z + z0) / 2.0 - 0.12], [ang - PI / 2.0, 0, 0], 8)
						k.cyl(0.022, 0.022, len, steel, [xr, (y + y0) / 2.0 + 0.45, (z + z0) / 2.0 - 0.12], [ang - PI / 2.0, 0, 0], 8)
						ctx.physics.addBox(xr, (z + z0) / 2.0 - 0.12, 0.1, absf(z - z0), 0, minf(y, y0), maxf(y, y0) + 1.0)
		stair_info.append({"x": S.x, "w": S.w + 0.4, "z0": -91.6, "z1": -83.5})
	# ------------------------------------------------------------ benches facing the river
	var wood = ctx.mat.toon("#b48a62", {"paint": 0.09, "name": "env-benchwood"})
	var wood_d = ctx.mat.toon("#8a6446", {"paint": 0.08})
	var bench_info := []
	for b in BENCHES:
		var z: float = R5.z - R5.halfW + 0.42
		var y := PATH_Y
		var bgp = k.group([b.x, y, z], PI)
		var kb = ctx.kit(bgp)
		for sx in [-0.72, 0.72]:
			kb.box(0.09, 0.42, 0.46, conc, [sx, 0.21, 0.0])
			kb.box(0.08, 0.5, 0.07, conc, [sx, 0.68, -0.21], [-0.12, 0, 0])
		for s in 4:
			kb.box(1.78, 0.04, 0.095, wood, [0, 0.44, -0.16 + s * 0.108])
		for s in 3:
			kb.box(1.78, 0.085, 0.035, wood_d if s == 1 else wood, [0, 0.6 + s * 0.13, -0.235 - s * 0.018], [-0.12, 0, 0])
		ctx.physics.addBox(b.x, z, 1.9, 0.62, PI, y, y + 0.95)
		bench_info.append({"x": b.x, "z": z, "y": y + 0.44, "rotY": PI, "len": 1.78})
	# ------------------------------------------------------------ promenade signboard at the top of the R2 stairs
	var board = ctx.tex.draw(1024, 512)
	var sx := -8.9
	var sz: float = R5.z - R5.halfW + 0.35
	var sg = k.group([sx, PATH_Y, sz], 0.08)
	var ks = ctx.kit(sg)
	for px in [-0.86, 0.86]:
		ks.box(0.12, 1.85, 0.12, wood_d, [px, 0.925, 0])
		ks.box(0.16, 0.06, 0.16, wood_d, [px, 1.88, 0])
	ks.box(1.86, 0.95, 0.07, wood, [0, 1.3, 0])
	ks.plane(1.74, 0.87, ctx.mat.toon("#ffffff", {"map": board, "paint": 0.03}), [0, 1.3, 0.037])
	ks.box(2.02, 0.07, 0.2, wood_d, [0, 1.81, 0.0])
	ks.box(0.3, 0.05, 0.3, conc, [-0.86, 0.02, 0])
	ks.box(0.3, 0.05, 0.3, conc, [0.86, 0.02, 0])
	ctx.physics.addBox(sx, sz, 2.0, 0.25, 0.08, PATH_Y, PATH_Y + 2.0)
	# ------------------------------------------------------------ lamp posts
	var pole_mat = ctx.mat.toon("#5f6d6a", {"paint": 0.03, "name": "env-lamppole"})
	var glass_mat = ctx.mat.emissive("#fff4dc", 0.95)
	var lamp_info := []
	for x in LAMPS:
		var z: float = R5.z - R5.halfW + 0.2
		var y := PATH_Y
		k.cyl(0.16, 0.2, 0.3, conc_dark, [x, y + 0.15, z], null, 10)
		k.cyl(0.055, 0.075, 3.5, pole_mat, [x, y + 1.95, z], null, 10)
		k.cyl(0.09, 0.09, 0.22, pole_mat, [x, y + 0.42, z], null, 10)
		k.box(0.05, 0.05, 0.42, pole_mat, [x, y + 3.68, z + 0.2])
		var hz := z + 0.4
		k.cyl(0.19, 0.12, 0.09, pole_mat, [x, y + 3.62, hz], null, 8)
		k.cyl(0.13, 0.1, 0.34, glass_mat, [x, y + 3.4, hz], null, 8)
		k.cyl(0.07, 0.13, 0.05, pole_mat, [x, y + 3.2, hz], null, 8)
		ctx.physics.addCylinder(x, z, 0.14, y, y + 4)
		lamp_info.append({"x": x, "z": z, "y": y + 3.4})
	# ------------------------------------------------------------ river km posts + notice sign
	for e in [[-100.5, "3.4"], [99.5, "3.2"]]:
		var z: float = R5.z + R5.halfW - 0.2
		var pg = k.group([e[0], PATH_Y, z], 0)
		var kp = ctx.kit(pg)
		kp.box(0.16, 0.8, 0.16, ctx.mat.toon("#e9e7e0", {"paint": 0.05}), [0, 0.4, 0])
		kp.plane(0.14, 0.28, ctx.mat.toon("#ffffff", {"map": ctx.tex.draw(128, 256), "paint": 0.02}), [0, 0.52, 0.081])
		ctx.physics.addCylinder(e[0], z, 0.12, PATH_Y, PATH_Y + 0.8)
	var notice = ctx.tex.draw(256, 192)
	var nx := 43.2
	var nz: float = R5.z + R5.halfW - 0.18
	var ng = k.group([nx, PATH_Y, nz], -0.1)
	var kn = ctx.kit(ng)
	kn.cyl(0.03, 0.03, 1.5, steel, [0, 0.75, -0.02], null, 8)
	kn.box(0.46, 0.34, 0.02, ctx.mat.toon("#f2f2ef", {"paint": 0.02}), [0, 1.3, 0])
	kn.plane(0.44, 0.32, ctx.mat.toon("#ffffff", {"map": notice, "paint": 0.02}), [0, 1.3, 0.011])
	ctx.physics.addCylinder(nx, nz, 0.08, PATH_Y, PATH_Y + 1.5)
	return {"stairs": stair_info, "benches": bench_info, "lamps": lamp_info}
