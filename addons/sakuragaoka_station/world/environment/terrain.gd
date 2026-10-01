# environment/terrain.js: the base terrain of the whole visual world. A fine 1 m core (play area
# + 25 m) and graded outer bands; each patch is split by surface class into separate meshes
# (ground / levee grass / masonry bank / distant forest) sharing vertices along their borders.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Common = preload("res://addons/sakuragaoka_station/world/environment/common.gd")

const CORE := {"x0": -117.0, "x1": 117.0, "z0": -122.0, "z1": 153.0}


static func graded(a: float, b: float, s0: float, grow: float, smax: Callable) -> Array:
	var pts := [a]
	var x := a
	var s := s0
	while x < b - 1e-6:
		s = minf(s * grow, smax.call(x))
		var nx := x + s
		if b - nx < s * 0.45:
			nx = b
		x = nx
		pts.append(x)
	return pts


static func uniform_line(a: float, b: float, n: int) -> Array:
	var out := []
	for i in n + 1:
		out.append(a + (b - a) * i / n)
	return out


## [[a, b, step], ...] to sorted unique lines, each rounded like JS's +(v).toFixed(4).
static func segs(list: Array) -> Array:
	var seen := {}
	var out := []
	for e in list:
		var a := float(e[0])
		var b := float(e[1])
		var n := maxi(1, roundi((b - a) / float(e[2])))
		for i in n + 1:
			var v := ("%.4f" % (a + (b - a) * i / n)).to_float()
			if not seen.has(v):
				seen[v] = true
				out.append(v)
	out.sort()
	return out


static func build_terrain(ctx, C, tx, distant_mat) -> Dictionary:
	var lin := func(h): return Common.lin(h)
	var P := {
		"grassA": lin.call("#a4c77f"), "grassB": lin.call("#8fb96f"), "grassC": lin.call("#bdd28c"), "grassD": lin.call("#7fa866"),
		"dirt": lin.call("#cfbb95"), "dirtL": lin.call("#dccdab"), "gravel": lin.call("#c6c0b2"), "gravelD": lin.call("#aea797"),
		"town": lin.call("#cbc3b2"), "townB": lin.call("#c0b7a5"),
		"corr": lin.call("#a9a295"), "corrB": lin.call("#b8ae9b"),
		"lev": lin.call("#98c273"), "levB": lin.call("#aacd7d"), "levR": lin.call("#8fbb6e"), "levTop": lin.call("#cfc8b8"),
		"bank": lin.call("#d2cec2"), "bankWet": lin.call("#8f8e82"), "coping": lin.call("#e0ddd4"), "moss": lin.call("#9fae80"),
		"farGrass": lin.call("#a3c47d"), "aze": lin.call("#a8b27e"),
		"fartown": lin.call("#c8bfad"),
		"forA": lin.call("#7ea46a"), "forB": lin.call("#6b9163"), "forC": lin.call("#93b676"), "forBlue": lin.call("#7f9d86"),
		"soilVeg": lin.call("#b9a07e"), "nanoG": lin.call("#9fb85a"), "nanoY": lin.call("#d8cf52"),
	}
	var b := Builder.new(ctx, C, P)
	var core_x := uniform_line(CORE.x0, CORE.x1, int(CORE.x1 - CORE.x0))
	var core_z := uniform_line(CORE.z0, CORE.z1, int(CORE.z1 - CORE.z0))
	var smax_x := func(x: float) -> float: return 12.0 if x < 420.0 else 24.0
	var out_pos := graded(117, 700, 1.8, 1.26, smax_x)
	var out_x := []
	var rev := out_pos.duplicate()
	rev.reverse()
	for v in rev:
		out_x.append(-v)
	var mid := uniform_line(-117, 117, 60)
	out_x.append_array(mid.slice(1, mid.size() - 1))
	out_x.append_array(out_pos)
	var side_x := out_pos
	var mid_z := segs([
		[-122, -119, 1], [-119, -116, 0.75], [-116, -101.3, 3.7], [-101.3, -99, 0.46], [-99, -94.5, 0.75], [-94.5, -91.5, 1.5],
		[-91.5, -84, 0.75], [-84, -60, 3], [-60, -53.5, 1.625], [-53.5, -51.5, 0.5], [-51.5, -34.5, 2.125], [-34.5, -32.5, 0.5],
		[-32.5, 0, 3.25], [0, 10, 1.25], [10, 153, 7.5],
	])
	var n_z := []
	var ng := graded(122, 900, 2, 1.17, func(z: float) -> float: return 12.0 if z < 620.0 else 26.0)
	ng.reverse()
	for v in ng:
		n_z.append(-v)
	var s_z := graded(153, 700, 3.5, 1.15, func(_z: float) -> float: return 22.0)

	b.build_patch(core_x, core_z, {"w": true, "e": true})
	b.build_patch(side_x, mid_z, {"w": true, "e": false})
	var side_w := []
	var sr := side_x.duplicate()
	sr.reverse()
	for v in sr:
		side_w.append(-v)
	b.build_patch(side_w, mid_z, {"w": false, "e": true})
	b.build_patch(out_x, n_z, {})
	b.build_patch(out_x, s_z, {})

	var mats := [
		ctx.mat.toon("#ffffff", {"vertexColors": true, "map": tx.ground, "paint": 0.035, "name": "env-ground"}),
		ctx.mat.toon("#ffffff", {"vertexColors": true, "map": tx.levee, "paint": 0.03, "name": "env-levee"}),
		ctx.mat.toon("#ffffff", {"vertexColors": true, "map": tx.masonry, "paint": 0.03, "name": "env-bank"}),
		distant_mat,
	]
	var group := T.Group.new()
	group.name = "env-terrain"
	for cls in 4:
		var bk: Bucket = b.buckets[cls]
		if bk.idx.is_empty():
			continue
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(bk.pos, 3))
		g.set_attribute("normal", T.Attr.new(bk.nrm, 3))
		g.set_attribute("color", T.Attr.new(bk.col, 3))
		g.set_attribute("uv", T.Attr.new(bk.uv, 2))
		g.set_index(bk.idx)
		g.compute_bounding_box()
		var mesh := T.MeshObj.new(g, mats[cls])
		mesh.name = "env-terrain-" + ["ground", "levee", "bank", "forest"][cls]
		mesh.receive_shadow = cls != 3
		mesh.cast_shadow = cls == 1
		if cls == 3:
			ctx.no_batch(mesh)
		group.add(mesh)
	ctx.add_static(group)
	return {"group": group, "triangles": b.triangles}


class Bucket extends RefCounted:
	var pos := PackedFloat32Array()
	var nrm := PackedFloat32Array()
	var col := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var idx := PackedInt32Array()
	var n := 0

	func vertex(x: float, y: float, z: float, nx: float, ny: float, nz: float, c: Array, u: float, v: float) -> int:
		pos.append(x); pos.append(y); pos.append(z)
		nrm.append(nx); nrm.append(ny); nrm.append(nz)
		col.append(c[0]); col.append(c[1]); col.append(c[2])
		uv.append(u); uv.append(v)
		n += 1
		return n - 1

	func copy_down(v: int, drop: float) -> void:
		vertex(pos[v * 3], pos[v * 3 + 1] - drop, pos[v * 3 + 2], nrm[v * 3], nrm[v * 3 + 1], nrm[v * 3 + 2],
			[col[v * 3], col[v * 3 + 1], col[v * 3 + 2]], uv[v * 2], uv[v * 2 + 1] + 0.2)

	func tri6(a: int, b: int, c: int, d: int, e: int, f: int) -> void:
		idx.append(a); idx.append(b); idx.append(c); idx.append(d); idx.append(e); idx.append(f)


class Builder extends RefCounted:
	var ctx
	var C
	var P: Dictionary
	var L
	var buckets := []
	var triangles := 0

	func _init(c, common, palette: Dictionary) -> void:
		ctx = c
		C = common
		P = palette
		L = c.L
		for i in 4:
			buckets.append(Bucket.new())

	static func m3(a: Array, b: Array, t: float) -> Array:
		return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]

	static func ss(a: float, b: float, x: float) -> float:
		var t := clampf((x - a) / (b - a), 0.0, 1.0)
		return t * t * (3.0 - 2.0 * t)

	func open_ground(x: float, z: float) -> Array:
		var n1 := Common.fbm(x / 7.5, z / 7.5, 3, 31)
		var n2 := Common.fbm(x / 26.0, z / 26.0, 3, 32)
		var n3 := Common.vnoise(x / 2.2, z / 2.2, 33)
		var c := m3(P.grassB, P.grassA, ss(0.3, 0.7, n1))
		c = m3(c, P.grassC, ss(0.55, 0.8, n2) * 0.6)
		c = m3(c, P.grassD, ss(0.62, 0.85, n3) * 0.35)
		var rd: float = C.road_dist(x, z)
		if rd > -0.1 and rd < 1.4:
			c = m3(c, m3(P.dirt, P.gravel, n3), (1.0 - ss(0.1, 1.4, rd)) * (0.55 + 0.3 * n1))
		var V: Dictionary = Common.VACANT_W
		if x > V.x0 and x < V.x1 and z > V.z0 and z < V.z1:
			if x < -76.0 and z > -13.5:
				c = m3(c, m3(P.gravel, P.gravelD, n3 * 0.6), ss(-76.0, -77.5, x) * ss(-13.5, -12.0, z) * 0.95)
		var A: Dictionary = Common.ALLOT_W
		if x > A.x0 - 2.0 and x < A.x1 + 2.0 and z > A.z0 - 2.0 and z < A.z1 + 2.0:
			c = m3(c, P.dirt, 0.55 + 0.2 * n3)
		var N: Dictionary = Common.NANO_E
		if x > N.x0 - 1.5 and x < N.x1 + 1.5 and z > N.z0 - 1.5 and z < N.z1 + 1.5:
			var in_f: bool = x > N.x0 + 0.3 and x < N.x1 - 0.3 and z > N.z0 + 0.3 and z < N.z1 - 0.3 and absf(z - (N.z0 + N.z1) / 2.0) > 0.6
			c = m3(P.nanoG, P.nanoY, ss(0.35, 0.7, n1) * 0.7) if in_f else m3(c, P.dirt, 0.45)
		var pd := Common.path_dist(x, z)
		if pd.d < 2.0:
			var wob := (Common.vnoise(x * 0.7, z * 0.7, 41) - 0.5) * 0.3
			var k := 1.0 - ss(0.55, 1.25, pd.d + wob)
			c = m3(c, P.dirtL if pd.kind == "park" else P.dirt, k * (0.92 if pd.kind == "park" else 0.8))
		return c

	func town_ground(x: float, z: float) -> Array:
		var n := Common.fbm(x / 6.0, z / 6.0, 3, 51)
		var n2 := Common.vnoise(x / 1.7, z / 1.7, 52)
		var c := m3(P.townB, P.town, n)
		return m3(c, P.gravel, ss(0.6, 0.9, n2) * 0.3)

	func ground_color(x: float, z: float, _h: float) -> Array:
		if z < -119.0:
			var n := Common.fbm(x / 9.0, z / 9.0, 3, 61)
			var c := m3(P.farGrass, P.grassC, ss(0.35, 0.75, n) * 0.6)
			if z < -123.5 and z > -286.0 and absf(x) < 660.0:
				c = m3(c, P.aze, 0.55)
			var m := Common.hill_mask(x, z)
			if m > 0.0:
				c = m3(c, P.forC, ss(0.0, 0.3, m))
			return c
		if C.in_corridor(x, z):
			var n := Common.fbm(x / 4.0, z / 4.0, 3, 71)
			var n2 := Common.vnoise(x / 1.3, z / 1.3, 72)
			var c := m3(P.corr, P.corrB, ss(0.3, 0.75, n))
			c = m3(c, P.gravelD, ss(0.65, 0.9, n2) * 0.4)
			var de: float = minf(z - L.RAIL.corridorZ0, L.RAIL.corridorZ1 - z) + (Common.vnoise(x * 0.5, z * 0.5, 73) - 0.5) * 1.2
			return m3(c, m3(P.grassB, P.grassA, n), 1.0 - ss(0.6, 1.7, de))
		var own = C.owned_by_others(x, z)
		if own == "block" and z < -31.0 and z > -34.0:
			return m3(open_ground(x, z), town_ground(x, z), 0.25)
		if own == "fartown":
			var n := Common.fbm(x / 11.0, z / 11.0, 3, 81)
			return m3(P.fartown, P.townB, n)
		if own != null:
			return town_ground(x, z)
		var m := Common.hill_mask(x, z)
		var c := open_ground(x, z)
		if m > 0.0:
			c = m3(c, P.forC, ss(0.0, 0.3, m))
		return c

	func levee_color(x: float, z: float, _h: float) -> Array:
		var n := Common.fbm(x / 6.0, z / 6.0, 3, 91)
		var n2 := Common.vnoise(x / 2.5, z / 2.5, 92)
		if z > L.ROADS.R5.z + 1.5:
			var c := m3(P.lev, P.levB, ss(0.3, 0.75, n))
			c = m3(c, P.grassC, ss(0.7, 0.9, n2) * 0.3)
			var toe := ss(-84.9, -84.0, z)
			if toe > 0.0:
				c = m3(c, ground_color(x, -83.9, 0.0), toe)
			return c
		if z >= -94.5:
			var c := m3(P.levTop, P.gravel, n)
			if absf(x) > 128.0:
				var g := 1.0 - ss(0.25, 0.55, absf(absf(z + 93.0) - 0.0))
				var edge := ss(1.05, 1.45, absf(z + 93.0))
				c = m3(c, m3(P.lev, P.levB, n), maxf(g * 0.8, edge * 0.9))
			return c
		var c := m3(P.levR, P.lev, ss(0.3, 0.75, n))
		c = m3(c, P.grassC, ss(0.72, 0.92, n2) * 0.25)
		return m3(c, P.moss, ss(-98.2, -99.0, z) * 0.5)

	func bank_color(x: float, z: float, h: float) -> Array:
		var n := Common.vnoise(x / 3.0, z / 3.0 + h, 101)
		var c := m3(P.bank, Common.mul3(P.bank, 0.92), n)
		c = m3(c, P.moss, ss(-0.05, -0.38, h) * 0.45)
		c = m3(c, P.bankWet, ss(-0.35, -0.55, h))
		if h > 0.1:
			c = m3(c, P.coping, ss(0.1, 0.19, h))
		return c

	func forest_color(x: float, z: float, _h: float) -> Array:
		var n := Common.fbm(x / 70.0, z / 70.0, 3, 111)
		var n2 := Common.fbm(x / 24.0, z / 24.0, 2, 112)
		var c := m3(P.forB, P.forA, ss(0.3, 0.7, n))
		return m3(c, P.forC, ss(0.55, 0.85, n2) * 0.55)

	func class_color(cls: int, x: float, z: float, h: float) -> Array:
		match cls:
			0: return ground_color(x, z, h)
			1: return levee_color(x, z, h)
			2: return bank_color(x, z, h)
		return forest_color(x, z, h)

	static func class_uv(cls: int, x: float, y: float, z: float) -> Array:
		match cls:
			0: return [x / 5.0, -z / 5.0]
			1: return [x / 5.6, -z / 5.6]
			2: return [x / 2.2, y / 2.2 - z * 0.08]
		return [x / 40.0, -z / 40.0]

	static func classify(cx: float, cz: float, hs: Array) -> int:
		if maxf(maxf(hs[0], hs[1]), maxf(hs[2], hs[3])) < -0.82 and cz < -100.0 and cz > -117.6:
			return -1
		if cz > -99.0 and cz < -84.0:
			return 1
		if (cz >= -101.3 and cz <= -99.0) or (cz >= -119.0 and cz <= -115.6):
			return 2
		if Common.hill_mask(cx, cz) > 0.22:
			return 3
		return 0

	static func eps_at(x: float, z: float) -> float:
		return 0.5 if absf(x) <= 300.0 and z > -300.0 and z < 300.0 else 2.5

	func build_patch(xs: Array, zs: Array, skirts: Dictionary) -> void:
		var nx := xs.size()
		var nz := zs.size()
		var H := PackedFloat32Array()
		H.resize(nx * nz)
		var NR := PackedFloat32Array()
		NR.resize(nx * nz * 3)
		for j in nz:
			for i in nx:
				var k := j * nx + i
				var x: float = xs[i]
				var z: float = zs[j]
				var h: float = C.terrain_h(x, z)
				var e := eps_at(x, z)
				var hx: float = C.terrain_h(x + e, z) - C.terrain_h(x - e, z)
				var hz: float = C.terrain_h(x, z + e) - C.terrain_h(x, z - e)
				var nl := sqrt(hx * hx + 4.0 * e * e + hz * hz)
				H[k] = h
				NR[k * 3] = -hx / nl
				NR[k * 3 + 1] = 2.0 * e / nl
				NR[k * 3 + 2] = -hz / nl
		var maps := [{}, {}, {}, {}]
		var cell_class := PackedInt32Array()
		cell_class.resize((nx - 1) * (nz - 1))
		var vid := func(cls: int, i: int, j: int) -> int:
			var key := j * nx + i
			var m: Dictionary = maps[cls]
			if m.has(key):
				return m[key]
			var bk: Bucket = buckets[cls]
			var x: float = xs[i]
			var z: float = zs[j]
			var h := H[key]
			var uv := class_uv(cls, x, h, z)
			var v := bk.vertex(x, h, z, NR[key * 3], NR[key * 3 + 1], NR[key * 3 + 2], class_color(cls, x, z, h), uv[0], uv[1])
			m[key] = v
			return v
		for j in nz - 1:
			for i in nx - 1:
				var k00 := j * nx + i
				var k10 := k00 + 1
				var k01 := k00 + nx
				var k11 := k01 + 1
				var cx: float = (xs[i] + xs[i + 1]) / 2.0
				var cz: float = (zs[j] + zs[j + 1]) / 2.0
				var cls := classify(cx, cz, [H[k00], H[k10], H[k01], H[k11]])
				cell_class[j * (nx - 1) + i] = cls
				if cls < 0:
					continue
				var a: int = vid.call(cls, i, j)
				var b: int = vid.call(cls, i + 1, j)
				var c: int = vid.call(cls, i, j + 1)
				var d: int = vid.call(cls, i + 1, j + 1)
				if absf(H[k00] - H[k11]) < absf(H[k10] - H[k01]):
					buckets[cls].tri6(a, c, d, a, d, b)
				else:
					buckets[cls].tri6(a, c, b, b, c, d)
				triangles += 2
		if skirts.is_empty():
			return
		var drop := 1.3
		var add_skirt := func(i0: int, j0: int, i1: int, j1: int, ci: int, cj: int, out: Array) -> void:
			var cls := cell_class[cj * (nx - 1) + ci]
			if cls < 0:
				return
			var pa: int = vid.call(cls, i0, j0)
			var pb: int = vid.call(cls, i1, j1)
			var bk: Bucket = buckets[cls]
			var base: int = bk.n
			bk.copy_down(pa, drop)
			bk.copy_down(pb, drop)
			var qa := base
			var qb := base + 1
			var ax: float = bk.pos[pa * 3]
			var az: float = bk.pos[pa * 3 + 2]
			var bx: float = bk.pos[pb * 3]
			var bz: float = bk.pos[pb * 3 + 2]
			var fx := bz - az
			var fz := -(bx - ax)
			if fx * out[0] + fz * out[1] > 0.0:
				bk.tri6(pa, pb, qa, pb, qb, qa)
			else:
				bk.tri6(pa, qa, pb, pb, qa, qb)
			triangles += 2
		for i in nx - 1:
			add_skirt.call(i, 0, i + 1, 0, i, 0, [0, -1])
			add_skirt.call(i, nz - 1, i + 1, nz - 1, i, nz - 2, [0, 1])
		for j in nz - 1:
			if skirts.get("w", false):
				add_skirt.call(0, j, 0, j + 1, 0, j, [-1, 0])
			if skirts.get("e", false):
				add_skirt.call(nx - 1, j, nx - 1, j + 1, nx - 2, j, [1, 0])
