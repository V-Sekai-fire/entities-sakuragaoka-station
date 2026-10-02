# railway/track.js: ballast bed, rails (head/web/foot profile), sleepers (PC near the station, wooden
# further out), fasteners and tie plates, fishplate joints with bolts, the crossover (two turnouts:
# switch rails, frogs, check rails, point machines and rods), ATS transponders and ballast stones.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")

## JIS 50N simplified rail profile.
const PROF := [
	[-0.0635, 0.000], [-0.0635, 0.012], [-0.012, 0.030], [-0.009, 0.042], [-0.009, 0.100], [-0.014, 0.109], [-0.0325, 0.117],
	[-0.0325, 0.139], [-0.027, 0.148], [-0.0135, 0.150], [0.0135, 0.150], [0.027, 0.148], [0.0325, 0.139], [0.0325, 0.117],
	[0.014, 0.109], [0.009, 0.100], [0.009, 0.042], [0.012, 0.030], [0.0635, 0.012], [0.0635, 0.000]]
const TOP_EDGES := [9]
const HEAD_EDGES := [5, 6, 7, 8, 10, 11, 12, 13]

static var _cap_tris = null


static func cap_tris() -> Array:
	if _cap_tris == null:
		var c := []
		for p in PROF:
			c.append([p[0], p[1]])
		_cap_tris = Geo.triangulate_shape(c, [])
	return _cap_tris


static func _push_tri(t: Dictionary, a: Array, b: Array, c: Array, N: Array) -> void:
	var ux: float = b[0] - a[0]
	var uy: float = b[1] - a[1]
	var uz: float = b[2] - a[2]
	var vx: float = c[0] - a[0]
	var vy: float = c[1] - a[1]
	var vz: float = c[2] - a[2]
	var cx := uy * vz - uz * vy
	var cy := uz * vx - ux * vz
	var cz := ux * vy - uy * vx
	var tri := [a, c, b] if cx * N[0] + cy * N[1] + cz * N[2] < 0 else [a, b, c]
	for v in tri:
		t.p.append(v[0]); t.p.append(v[1]); t.p.append(v[2])
		t.n.append(N[0]); t.n.append(N[1]); t.n.append(N[2])


static func _to_geo(t: Dictionary) -> T.Geometry:
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(t.p, 3))
	g.set_attribute("normal", T.Attr.new(t.n, 3))
	var uv := PackedFloat32Array()
	uv.resize(t.p.size() / 3 * 2)
	g.set_attribute("uv", T.Attr.new(uv, 2))
	return g


## Extrudes the rail profile along an XZ path; hs(x) scales the head width (switch-rail taper).
## Returns {side, top, head} geometries.
static func rail_geo(path: Array, hs = null, caps: Array = [false, false], lift: float = 0.0) -> Dictionary:
	var n := path.size()
	var lat := []
	for i in n:
		var a: Array = path[maxi(0, i - 1)]
		var b: Array = path[mini(n - 1, i + 1)]
		var tx: float = b[0] - a[0]
		var tz: float = b[1] - a[1]
		var l := sqrt(tx * tx + tz * tz)
		if l == 0.0:
			l = 1.0
		tx /= l
		tz /= l
		lat.append([-tz, tx])
	var side := {"p": PackedFloat32Array(), "n": PackedFloat32Array()}
	var top := {"p": PackedFloat32Array(), "n": PackedFloat32Array()}
	var head := {"p": PackedFloat32Array(), "n": PackedFloat32Array()}
	var P := func(i: int, e: int) -> Array:
		var x: float = path[i][0]
		var z: float = path[i][1]
		var u: float = PROF[e][0]
		var y: float = PROF[e][1]
		if hs != null and e >= 6 and e <= 13:
			u *= hs.call(x)
		return [x + lat[i][0] * u, y + lift, z + lat[i][1] * u]
	for i in n - 1:
		var lx: float = lat[i][0] + lat[i + 1][0]
		var lz: float = lat[i][1] + lat[i + 1][1]
		var ll := sqrt(lx * lx + lz * lz)
		if ll == 0.0:
			ll = 1.0
		lx /= ll
		lz /= ll
		for e in PROF.size() - 1:
			var a: Array = PROF[e]
			var b: Array = PROF[e + 1]
			var nu: float = -(b[1] - a[1])
			var ny: float = b[0] - a[0]
			var nl := sqrt(nu * nu + ny * ny)
			nu /= nl
			ny /= nl
			var N := [lx * nu, ny, lz * nu]
			var A0: Array = P.call(i, e)
			var B0: Array = P.call(i, e + 1)
			var A1: Array = P.call(i + 1, e)
			var B1: Array = P.call(i + 1, e + 1)
			var t: Dictionary = top if e in TOP_EDGES else (head if e in HEAD_EDGES else side)
			_push_tri(t, A0, B0, B1, N)
			_push_tri(t, A0, B1, A1, N)
	for kc in [[0, caps[0]], [n - 1, caps[1]]]:
		if not kc[1]:
			continue
		var k: int = kc[0]
		var j := 1 if k == 0 else n - 2
		var tx: float = path[k][0] - path[j][0]
		var tz: float = path[k][1] - path[j][1]
		var l := sqrt(tx * tx + tz * tz)
		if l == 0.0:
			l = 1.0
		var N := [tx / l, 0.0, tz / l]
		for tri in cap_tris():
			_push_tri(side, P.call(k, tri[0]), P.call(k, tri[1]), P.call(k, tri[2]), N)
	return {"side": _to_geo(side), "top": _to_geo(top), "head": _to_geo(head)}


## Box-ish solid with a narrower top (PC sleeper), length along Z, top at y = 0, no bottom face.
static func _tapered_box(length: float, w_top: float, w_bot: float, h: float) -> T.Geometry:
	var t := {"p": PackedFloat32Array(), "n": PackedFloat32Array(), "uv": PackedFloat32Array()}
	var L2 := length / 2.0
	var a := w_top / 2.0
	var b := w_bot / 2.0
	var quad := func(v0: Array, v1: Array, v2: Array, v3: Array, N: Array, uv: Array) -> void:
		var V := [v0, v1, v2, v3]
		for tr in [[0, 1, 2], [0, 2, 3]]:
			var A: Array = V[tr[0]]
			var B: Array = V[tr[1]]
			var C: Array = V[tr[2]]
			var ux: float = B[0] - A[0]
			var uy: float = B[1] - A[1]
			var uz: float = B[2] - A[2]
			var vx: float = C[0] - A[0]
			var vy: float = C[1] - A[1]
			var vz: float = C[2] - A[2]
			var cx := uy * vz - uz * vy
			var cy := uz * vx - ux * vz
			var cz := ux * vy - uy * vx
			var ordr: Array = [tr[0], tr[2], tr[1]] if cx * N[0] + cy * N[1] + cz * N[2] < 0 else tr
			for k in ordr:
				t.p.append(V[k][0]); t.p.append(V[k][1]); t.p.append(V[k][2])
				t.n.append(N[0]); t.n.append(N[1]); t.n.append(N[2])
				t.uv.append(uv[k][0]); t.uv.append(uv[k][1])
	var sl := (b - a) / h
	var nl := sqrt(1.0 + sl * sl)
	quad.call([-a, 0, -L2], [a, 0, -L2], [a, 0, L2], [-a, 0, L2], [0, 1, 0], [[0, 0.1], [0, 0.9], [1, 0.9], [1, 0.1]])
	quad.call([a, 0, -L2], [b, -h, -L2], [b, -h, L2], [a, 0, L2], [1 / nl, sl / nl, 0], [[0, 0.9], [0, 1], [1, 1], [1, 0.9]])
	quad.call([-a, 0, -L2], [-b, -h, -L2], [-b, -h, L2], [-a, 0, L2], [-1 / nl, sl / nl, 0], [[0, 0.1], [0, 0], [1, 0], [1, 0.1]])
	quad.call([-a, 0, L2], [a, 0, L2], [b, -h, L2], [-b, -h, L2], [0, 0, 1], [[1, 0.1], [1, 0.9], [1, 1], [1, 0]])
	quad.call([-a, 0, -L2], [a, 0, -L2], [b, -h, -L2], [-b, -h, -L2], [0, 0, -1], [[0, 0.1], [0, 0.9], [0, 1], [0, 0]])
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(t.p, 3))
	g.set_attribute("normal", T.Attr.new(t.n, 3))
	g.set_attribute("uv", T.Attr.new(t.uv, 2))
	return g


static func box_geo(w: float, h: float, d: float, x: float = 0.0, y: float = 0.0, z: float = 0.0, no_bottom: bool = false) -> T.Geometry:
	var g := Geo.box(w, h, d)
	g.translate(x, y, z)
	if no_bottom:
		var keep := PackedInt32Array()
		for i in g.index.size():
			if i < 18 or i >= 24:
				keep.append(g.index[i])
		g.set_index(keep)
		g.clear_groups()
	return g


static func _smooth01(t: float) -> float:
	t = maxf(0.0, minf(1.0, t))
	return t * t * (3.0 - 2.0 * t)


static func _smoother(t: float) -> float:
	t = maxf(0.0, minf(1.0, t))
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


static func _n(it: Dictionary, k: String, d: float) -> float:
	var v = it.get(k)
	return d if v == null else float(v)


## An instanced mesh from items {x, y, z, rx, ry, rz (Euler YXZ), sx, sy, sz, c}.
static func make_instanced(geo: T.Geometry, mat, items: Array, opts: Dictionary = {}):
	if items.is_empty():
		return null
	var shadow: bool = opts.get("shadow", true)
	var colors: bool = opts.get("colors", false)
	var m := T.InstancedMesh.new(geo, mat, items.size())
	for i in items.size():
		var it: Dictionary = items[i]
		var q := Basis.from_euler(Vector3(_n(it, "rx", 0), _n(it, "ry", 0), _n(it, "rz", 0)), EULER_ORDER_YXZ).get_rotation_quaternion()
		m.set_matrix_at(i, T.compose(Vector3(it.x, it.y, it.z), q, Vector3(_n(it, "sx", 1), _n(it, "sy", 1), _n(it, "sz", 1))))
		if colors:
			m.set_color_at(i, T.color(it.get("c", "#ffffff") if it.get("c") else "#ffffff"))
	m.cast_shadow = shadow
	m.receive_shadow = true
	return m


static func _octahedron() -> T.Geometry:
	return Geo.polyhedron([1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1],
		[0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2, 1, 2, 5, 1, 5, 3, 1, 3, 4, 1, 4, 2], 1, 0)


static func build_track(ctx, root, TX, E: Dictionary) -> Dictionary:
	var mat = ctx.mat
	var r = ctx.rng("rw-track")
	var out := {"sleeperLists": {}, "ties": [], "frogs": [], "railsAt": null}
	var zA: float = E.zA
	var zB: float = E.zB
	var HG: float = E.HG
	var X0: float = E.X0
	var X1: float = E.X1
	var SaZ: float = E.rails.SaZ
	var NaZ: float = E.rails.NaZ
	var SbZ: float = E.rails.SbZ
	var NbZ: float = E.rails.NbZ
	var xa: float = E.xo.xa
	var xb: float = E.xo.xb

	var M := {
		"railSide": mat.toon("#68564d", {"paint": 0.08}),
		"railHead": mat.toon("#8e8580", {"paint": 0.08}),
		"railTop": mat.toon("#e6eaee", {"paint": 0.05, "emissive": "#444a54", "emissiveIntensity": 1}),
		"ballast": mat.toon("#ffffff", {"map": TX.ballast, "vertexColors": true, "paint": 0.05}),
		"pc": mat.toon("#ffffff", {"map": TX.pc, "paint": 0.05}),
		"wood": mat.toon("#ffffff", {"map": TX.wood, "paint": 0.08}),
		"steel": mat.toon("#5d5a5c", {"paint": 0.05}),
		"clip": mat.toon("#4a4a52", {"paint": 0.05}),
		"plate": mat.toon("#6a5d57", {"paint": 0.08}),
		"frog": mat.toon("#5f5754", {"paint": 0.08}),
		"stone": mat.toon("#ffffff", {"paint": 0.05}),
		"pm": mat.toon("#a2a8ac", {"paint": 0.05}),
		"concrete": mat.toon(ctx.palette.concrete, {"paint": 0.08}),
		"ats": mat.toon("#e7b23e", {"paint": 0.05}),
		"atsDark": mat.toon("#4b4750"),
		"white": mat.toon("#eeebe4"),
		"black": mat.toon("#3d3a42"),
	}
	out["M"] = M

	# ballast bed: half profile by distance d from the corridor centre (z = -43), mirrored
	var HALF := [
		[0.0, -0.062, [0.9, 0.88, 0.86]], [0.45, -0.05, [0.95, 0.94, 0.92]], [0.9, -0.03, [1.0, 1.0, 0.99]], [1.1, -0.02, [0.98, 0.97, 0.96]],
		[1.434, -0.02, [0.84, 0.76, 0.7]], [1.62, -0.02, [0.95, 0.92, 0.9]], [2.0, -0.02, [0.88, 0.86, 0.85]], [2.38, -0.02, [0.95, 0.92, 0.9]],
		[2.566, -0.02, [0.84, 0.76, 0.7]], [2.75, -0.02, [0.97, 0.96, 0.95]], [3.2, -0.02, [1.05, 1.04, 1.03]], [3.33, -0.032, [1.06, 1.05, 1.04]],
		[3.6, -0.15, [1.0, 1.0, 0.99]], [3.85, -0.285, [0.9, 0.91, 0.86]], [4.02, -0.345, [0.84, 0.86, 0.8]]]
	var PZ := []
	for i in range(HALF.size() - 1, -1, -1):
		PZ.append([-43.0 - HALF[i][0], HALF[i][1], HALF[i][2]])
	for i in range(1, HALF.size()):
		PZ.append([-43.0 + HALF[i][0], HALF[i][1], HALF[i][2]])
	E["ballastY"] = func(z: float) -> float:
		var d := absf(z + 43.0)
		if d >= HALF[HALF.size() - 1][0]:
			return -0.345
		for i in range(1, HALF.size()):
			if d <= HALF[i][0]:
				var t: float = (d - HALF[i - 1][0]) / (HALF[i][0] - HALF[i - 1][0])
				return HALF[i - 1][1] + (HALF[i][1] - HALF[i - 1][1]) * t
		return -0.02
	var row_noise := func(x: float) -> float:
		return 1.0 + 0.05 * sin(x * 0.21 + 1.3) + 0.04 * sin(x * 0.57) + 0.03 * sin(x * 1.31 + 0.4)
	var cx0 := -440.0
	while cx0 < X1:
		var x0 := maxf(X0, cx0)
		var x1 := minf(X1, cx0 + 40.0)
		if x1 > x0:
			var xs := []
			var xx := x0
			while xx < x1 - 1e-6:
				xs.append(xx)
				xx += 4.0
			xs.append(x1)
			var pos := PackedFloat32Array()
			var col := PackedFloat32Array()
			var uv := PackedFloat32Array()
			var idx := PackedInt32Array()
			var nz := PZ.size()
			for x in xs:
				var rn: float = row_noise.call(x)
				for p in PZ:
					var z: float = p[0]
					pos.append(x); pos.append(p[1]); pos.append(z)
					uv.append(x / 1.7); uv.append(-z / 1.7)
					var k: float = rn * (1.0 + 0.04 * sin(x * 0.9 + z * 3.1))
					col.append(p[2][0] * k); col.append(p[2][1] * k); col.append(p[2][2] * k)
			for i in xs.size() - 1:
				for j in nz - 1:
					var a := i * nz + j
					var b := a + 1
					var c := a + nz
					var d := c + 1
					idx.append(a); idx.append(b); idx.append(d); idx.append(a); idx.append(d); idx.append(c)
			var g := T.Geometry.new()
			g.set_attribute("position", T.Attr.new(pos, 3))
			g.set_attribute("color", T.Attr.new(col, 3))
			g.set_attribute("uv", T.Attr.new(uv, 2))
			g.set_index(idx)
			g.compute_vertex_normals()
			var m := T.MeshObj.new(g, M.ballast)
			m.receive_shadow = true
			m.cast_shadow = false
			root.add(m)
		cx0 += 40.0

	# crossover centreline
	var XL := xb - xa
	var zc := func(x: float) -> float:
		return zA + (zB - zA) * _smoother((x - xa) / XL)
	var zc_slope := func(x: float) -> float:
		var t := (x - xa) / XL
		if t <= 0.0 or t >= 1.0:
			return 0.0
		return (zB - zA) / XL * 30.0 * t * t * (1.0 - t) * (1.0 - t)
	var sec := func(x: float) -> float:
		var s: float = zc_slope.call(x)
		return sqrt(1.0 + s * s)
	var XsZ := func(x: float) -> float:
		return zc.call(x) + HG * sec.call(x)
	var XnZ := func(x: float) -> float:
		return zc.call(x) - HG * sec.call(x)
	E.xo["zc"] = zc
	E.xo["XsZ"] = XsZ
	E.xo["XnZ"] = XnZ
	var hs_start := func(x: float) -> float:
		return 0.3 + 0.7 * _smooth01((x - xa) / 4.5)
	var hs_end := func(x: float) -> float:
		return 0.3 + 0.7 * _smooth01((xb - x) / 4.5)
	var off := func(hs: float) -> float:
		return 0.0325 * (1.0 + hs)

	var RAILS := [
		{"id": "Sa", "track": "A", "x0": X0, "x1": X1, "zf": func(_x: float) -> float: return SaZ},
		{"id": "Nb", "track": "B", "x0": X0, "x1": X1, "zf": func(_x: float) -> float: return NbZ},
		{"id": "NaW-Xn", "track": "A", "x0": X0, "x1": xb,
			"zf": func(x: float) -> float: return NaZ if x <= xa else maxf(XnZ.call(x), NbZ + off.call(hs_end.call(x))),
			"hs": func(x: float) -> float: return hs_end.call(x) if x > xb - 5.0 else 1.0, "curved": true, "capEnd": true},
		{"id": "NaE", "track": "A", "x0": xa, "x1": X1,
			"zf": func(x: float) -> float: return maxf(NaZ, XnZ.call(x) + off.call(hs_start.call(x))),
			"hs": func(x: float) -> float: return hs_start.call(x) if x < xa + 5.0 else 1.0, "curved": true, "capStart": true},
		{"id": "Xs-SbE", "track": "B", "x0": xa, "x1": X1,
			"zf": func(x: float) -> float: return SbZ if x >= xb else minf(XsZ.call(x), SaZ - off.call(hs_start.call(x))),
			"hs": func(x: float) -> float: return hs_start.call(x) if x < xa + 5.0 else 1.0, "curved": true, "capStart": true},
		{"id": "SbW", "track": "B", "x0": X0, "x1": xb,
			"zf": func(x: float) -> float: return SbZ if x < xa else minf(SbZ, XsZ.call(x) - off.call(hs_end.call(x))),
			"hs": func(x: float) -> float: return hs_end.call(x) if x > xb - 5.0 else 1.0, "curved": true, "capEnd": true},
	]
	out["rails"] = RAILS
	var rails_at := func(x: float) -> Array:
		var o := []
		for R in RAILS:
			if x >= R.x0 and x <= R.x1:
				o.append({"id": R.id, "z": R.zf.call(x)})
		return o
	out["railsAt"] = rails_at

	# frogs
	var solve := func(f: Callable, lo: float, hi: float) -> float:
		for i in 60:
			var mm := (lo + hi) / 2.0
			if f.call(lo) * f.call(mm) <= 0.0:
				hi = mm
			else:
				lo = mm
		return (lo + hi) / 2.0
	var xf1: float = solve.call(func(x: float) -> float: return XsZ.call(x) - NaZ, xa + 1.0, xb - 1.0)
	var xf2: float = solve.call(func(x: float) -> float: return XnZ.call(x) - SbZ, xa + 1.0, xb - 1.0)
	out["frogs"] = [{"x": xf1, "z": NaZ, "slope": zc_slope.call(xf1)}, {"x": xf2, "z": SbZ, "slope": zc_slope.call(xf2)}]

	# check rails opposite the frogs, flared ends
	var flare := func(x: float, xc: float, length: float) -> float:
		var d := absf(x - xc) - (length / 2.0 - 0.6)
		return 0.045 * pow(d / 0.6, 1.5) if d > 0.0 else 0.0
	var CO := 0.107
	var CL := 4.6
	var CHECKS := [
		{"xc": xf1, "zf": func(x: float) -> float: return SaZ - CO - flare.call(x, xf1, CL)},
		{"xc": xf1, "zf": func(x: float) -> float: return XnZ.call(x) + CO + flare.call(x, xf1, CL)},
		{"xc": xf2, "zf": func(x: float) -> float: return NbZ + CO + flare.call(x, xf2, CL)},
		{"xc": xf2, "zf": func(x: float) -> float: return XsZ.call(x) - CO - flare.call(x, xf2, CL)},
	]

	# rail meshes
	var add_rail_path := func(path: Array, hs, caps: Array) -> void:
		var rg := rail_geo(path, hs, caps)
		var ms := T.MeshObj.new(rg.side, M.railSide)
		var mt := T.MeshObj.new(rg.top, M.railTop)
		var mh := T.MeshObj.new(rg.head, M.railHead)
		ms.cast_shadow = true; ms.receive_shadow = true
		mh.cast_shadow = true; mh.receive_shadow = true
		mt.cast_shadow = false; mt.receive_shadow = true
		root.add(ms); root.add(mt); root.add(mh)
	for R in RAILS:
		var cuts := {R.x0: true, R.x1: true}
		var cx := ceilf(R.x0 / 20.0) * 20.0
		while cx < R.x1:
			cuts[cx] = true
			cx += 20.0
		if R.get("curved", false):
			cuts[xa] = true
			cuts[xb] = true
		var xs_cut := []
		for x in cuts:
			if x >= R.x0 and x <= R.x1:
				xs_cut.append(x)
		xs_cut.sort()
		for i in xs_cut.size() - 1:
			var a: float = xs_cut[i]
			var b: float = xs_cut[i + 1]
			var curved_here: bool = R.get("curved", false) and b > xa - 0.01 and a < xb + 0.01
			var xs := [a]
			if curved_here:
				var n := maxi(1, int(ceilf((b - a) / 0.6)))
				for k in range(1, n):
					xs.append(a + (b - a) * k / n)
			xs.append(b)
			var path := []
			for x in xs:
				path.append([x, R.zf.call(x)])
			add_rail_path.call(path, R.hs if R.has("hs") and curved_here else null,
				[R.get("capStart", false) and a == R.x0, R.get("capEnd", false) and b == R.x1])
	for C in CHECKS:
		var path := []
		for k in 17:
			var x: float = C.xc - CL / 2.0 + CL * k / 16.0
			path.append([x, C.zf.call(x)])
		add_rail_path.call(path, null, [true, true])
	for F in out.frogs:
		var ang := atan(F.slope) / 2.0
		var kf = ctx.kit(root)
		var bx = kf.box(3.2, 0.13, 0.34, M.frog, [F.x, 0.075, F.z + tan(ang) * 0.0], [0, -ang, 0])
		bx.cast_shadow = true
		kf.box(3.6, 0.018, 0.5, M.plate, [F.x, 0.006, F.z], [0, -ang, 0])

	# sleepers and turnout ties
	var SP := 0.625
	var TX0 := xa - 4.4
	var TX1 := xb + 4.4
	var TSP := 0.6
	var pc_prob := func(x: float) -> float:
		if x >= -45.0 and x <= 150.0:
			return 0.975
		if x < -45.0:
			return maxf(0.0, 1.0 - (-45.0 - x) / 16.0)
		return maxf(0.0, 1.0 - (x - 150.0) / 16.0)
	var pc_items := []
	var wood_items := []
	var clip_items := []
	var plate_items := []
	var plate_lite := []
	var WOOD_COLS := ["#8b7462", "#7c6655", "#957e69", "#76655a", "#8f8274", "#6f5b4d"]
	var PC_COLS := ["#cfccc3", "#c6c3bb", "#d6d3ca", "#bfbdb6", "#cbc6b8", "#c2c2ba"]
	var lists := {"A": [], "B": []}
	for tr in [["A", zA, X0 + 0.3125], ["B", zB, X0 + 0.625]]:
		var tid: String = tr[0]
		var zT: float = tr[1]
		var x: float = tr[2]
		while x < X1 - 0.1:
			if x > TX0 - 0.3 and x < TX1 + 0.3:
				x += SP
				continue
			var jx: float = x + (r.f() - 0.5) * 0.03
			var jr: float = (r.f() - 0.5) * 0.02
			var is_pc: bool = r.f() < pc_prob.call(x)
			lists[tid].append(jx)
			if is_pc:
				pc_items.append({"x": jx, "y": 0, "z": zT, "ry": jr, "c": PC_COLS[floori(r.f() * PC_COLS.size())]})
				for rz in [zT - HG, zT + HG]:
					for s in [0.0, PI]:
						clip_items.append({"x": jx, "y": 0, "z": rz, "ry": s + jr})
			else:
				wood_items.append({"x": jx, "y": 0, "z": zT, "ry": jr, "sz": 2.1 + (r.f() - 0.5) * 0.06, "c": WOOD_COLS[floori(r.f() * WOOD_COLS.size())]})
				if absf(x) < 130.0:
					for rz in [zT - HG, zT + HG]:
						plate_items.append({"x": jx, "y": 0, "z": rz, "ry": jr + (0.0 if r.f() < 0.5 else PI)})
				elif absf(x) < 260.0:
					for rz in [zT - HG, zT + HG]:
						plate_lite.append({"x": jx, "y": 0, "z": rz, "ry": jr})
			x += SP
	out.sleeperLists = {"A": {"x0": X0 + 0.3125, "list": lists.A}, "B": {"x0": X0 + 0.625, "list": lists.B}}
	var tx := TX0
	while tx <= TX1 + 1e-6:
		var zs := []
		for o in rails_at.call(tx):
			zs.append(o.z)
		for C in CHECKS:
			if absf(tx - C.xc) < CL / 2.0:
				zs.append(C.zf.call(tx))
		zs.sort()
		var groups := []
		var g0: float = zs[0]
		var g1: float = zs[0]
		for i in range(1, zs.size()):
			if zs[i] - g1 > 1.5:
				groups.append([g0, g1])
				g0 = zs[i]
			g1 = zs[i]
		groups.append([g0, g1])
		for gr in groups:
			var zlo: float = gr[0] - 0.43 - 0.0
			var zhi: float = gr[1] + 0.43
			var c: String = WOOD_COLS[floori(r.f() * WOOD_COLS.size())]
			wood_items.append({"x": tx, "y": 0, "z": (zlo + zhi) / 2.0, "ry": 0, "sz": zhi - zlo, "sx": 1.06, "c": c})
			out.ties.append({"x": tx, "z0": zlo, "z1": zhi})
		for zr in zs:
			plate_items.append({"x": tx, "y": 0, "z": zr, "ry": 0.0 if r.f() < 0.5 else PI})
		tx += TSP
	var pc_geo := _tapered_box(2.0, 0.2, 0.26, 0.17)
	var wood_geo := box_geo(0.21, 0.145, 1, 0, -0.0725, 0, true)
	var uvA: T.Attr = wood_geo.attributes.uv
	var pA: T.Attr = wood_geo.attributes.position
	var nA: T.Attr = wood_geo.attributes.normal
	for i in uvA.count():
		var z := pA.get_z(i) + 0.5
		var ny := absf(nA.get_y(i))
		var nx := absf(nA.get_x(i))
		var v: float
		if ny > 0.5:
			v = pA.get_x(i) / 0.21 + 0.5
		elif nx > 0.5:
			v = (pA.get_y(i) / 0.145 + 1.0) * 0.5
		else:
			v = 0.5 + pA.get_x(i) / 0.21 * 0.8
		uvA.set_xy(i, ((1.0 if z > 0.5 else 0.0) if absf(nA.get_z(i)) > 0.5 else z), v)
	var pcM = make_instanced(pc_geo, M.pc, pc_items, {"colors": true})
	var woodM = make_instanced(wood_geo, M.wood, wood_items, {"colors": true})
	if pcM:
		pcM.name = "rw-pc-sleepers"
		root.add(pcM)
	if woodM:
		woodM.name = "rw-wood-sleepers"
		root.add(woodM)

	# fasteners: PC double elastic clip, wooden tie plate and dog spikes
	var clip_geo := Geo.merge_geometries([box_geo(0.07, 0.022, 0.056, 0, 0.021, 0.082, true), box_geo(0.032, 0.04, 0.032, 0, 0.02, 0.114, true)])
	var plate_geo := Geo.merge_geometries([box_geo(0.17, 0.014, 0.32, 0, 0.003, 0, true), box_geo(0.022, 0.03, 0.03, 0.045, 0.02, 0.082, true), box_geo(0.022, 0.03, 0.03, -0.045, 0.02, -0.082, true)])
	var plate_lite_geo := box_geo(0.17, 0.014, 0.3, 0, 0.003, 0, true)
	for e in [[clip_geo, clip_items, M.clip, "rw-clips"], [plate_geo, plate_items, M.plate, "rw-plates"], [plate_lite_geo, plate_lite, M.plate, "rw-plates-lite"]]:
		var im = make_instanced(e[0], e[2], e[1], {"shadow": false})
		if im:
			im.name = e[3]
			root.add(im)

	# fishplate joints every 25 m and bolts
	var fish_items := []
	var bolt_items := []
	for jt in [[zA, X0], [zB, X0 + 12.8125]]:
		var zT: float = jt[0]
		var x: float = jt[1] + 25.0
		while x < X1 - 1.0:
			if not (x > TX0 - 3.0 and x < TX1 + 3.0):
				for rz in [zT - HG, zT + HG]:
					for s in [-1, 1]:
						fish_items.append({"x": x, "y": 0.072, "z": rz + s * 0.019})
						if absf(x) < 230.0:
							for bx in [-0.2, -0.07, 0.07, 0.2]:
								bolt_items.append({"x": x + bx, "y": 0.07, "z": rz + s * 0.04, "rx": PI / 2.0, "ry": 0})
			x += 25.0
	var fish_geo := box_geo(0.58, 0.062, 0.016, 0, 0, 0, true)
	var bolt_geo := Geo.cylinder(0.014, 0.014, 0.024, 6, 1)
	for e in [[fish_geo, fish_items, M.steel, "rw-fishplates"], [bolt_geo, bolt_items, M.clip, "rw-bolts"]]:
		var im = make_instanced(e[0], e[2], e[1], {"shadow": false})
		if im:
			im.name = e[3]
			root.add(im)

	# turnout equipment: point machines, rods, switch indicators
	var k = ctx.kit(root)
	var machine := func(x: float, z_machine: float, z_far: float, dir: float, rod_x: float) -> void:
		k.boxb(1.2, 0.42, 0.7, M.concrete, [x, -0.5, z_machine])
		k.rbox(0.95, 0.3, 0.46, 0.04, M.pm, [x, 0.07, z_machine])
		k.box(0.9, 0.05, 0.4, M.pm, [x, 0.245, z_machine])
		TX.sign_mesh(k, TX.sign.pm, 0.9, 0.24, [x, 0.08, z_machine - dir * 0.232], [0, PI if dir > 0 else 0.0, 0])
		var zr0 := z_machine - dir * 0.22
		var length := absf(z_far - zr0)
		for dh in [[0.0, 0.028], [0.12, 0.022]]:
			k.box(0.035, dh[1], length, M.steel, [rod_x + dh[0], 0.0, (zr0 + z_far) / 2.0])
		k.box(0.18, 0.1, 0.18, M.steel, [rod_x + 0.06, 0.03, z_machine - dir * 0.3])
	machine.call(xa + 0.55, SaZ + 1.08, NaZ + 0.05, 1.0, xa + 0.5)
	machine.call(xb - 0.55, NbZ - 1.08, SbZ - 0.05, -1.0, xb - 0.1)
	for si in [[xa - 0.9, SaZ + 1.15, PI / 2.0], [xb + 0.9, NbZ - 1.15, -PI / 2.0]]:
		var x: float = si[0]
		var z: float = si[1]
		k.boxb(0.3, 0.36, 0.3, M.concrete, [x, -0.5, z])
		k.cyl(0.028, 0.028, 0.75, M.pm, [x, 0.2, z], null, 8)
		var g = k.group([x, 0.66, z], si[2])
		var kk = ctx.kit(g)
		kk.cyl(0.1, 0.1, 0.12, M.black, [0, 0, 0], [PI / 2.0, 0, 0], 16)
		kk.cyl(0.082, 0.082, 0.01, M.white, [0, 0, 0.062], [PI / 2.0, 0, 0], 16)
		kk.box(0.13, 0.03, 0.01, M.black, [0, 0, 0.068])

	# ATS transponders between the rails
	var ka = ctx.kit(root)
	var at := func(x: float, zT: float) -> void:
		ka.box(0.5, 0.07, 0.26, M.ats, [x, 0.035, zT])
		ka.box(0.44, 0.012, 0.2, M.atsDark, [x, 0.076, zT])
		for s in [-1, 1]:
			ka.box(0.05, 0.02, 0.36, M.steel, [x + s * 0.2, 0.01, zT])
	at.call(-2.4, zA); at.call(16.0, zA); at.call(147.0, zA)
	at.call(41.8, zB); at.call(18.0, zB); at.call(-167.0, zB)

	# sleeper lookup (stones and weeds)
	var on_sleeper := func(x: float, z: float, pad: float = 0.04) -> bool:
		if x > TX0 - 0.4 and x < TX1 + 0.4:
			var kx := T.js_round((x - TX0) / TSP)
			var t0 := TX0 + kx * TSP
			if absf(x - t0) < 0.11 + pad:
				for t in out.ties:
					if absf(t.x - t0) < 0.01 and z > t.z0 - pad and z < t.z1 + pad:
						return true
			if x > TX0 and x < TX1:
				return false
		for tz in [["A", zA], ["B", zB]]:
			if absf(z - tz[1]) > 1.0 + pad:
				continue
			var L0: Dictionary = out.sleeperLists[tz[0]]
			var kx := T.js_round((x - L0.x0) / SP)
			var sx: float = L0.x0 + kx * SP
			if absf(x - sx) < 0.13 + pad:
				return true
		return false
	out["onSleeper"] = on_sleeper
	var near_rail := func(x: float, z: float, pad: float = 0.085) -> bool:
		for o in rails_at.call(x):
			if absf(z - o.z) < pad:
				return true
		return false
	out["nearRail"] = near_rail

	# instanced ballast stones
	var rs = ctx.rng("rw-stones")
	var STONE_COLS := [["#8a8781", 24], ["#7c7975", 18], ["#6d6a66", 14], ["#958f86", 10], ["#86766a", 12], ["#9c8e80", 6], ["#aea99f", 5], ["#7a7e85", 6], ["#67615b", 3]]
	var pick_c := func() -> String:
		var s := 0.0
		for c in STONE_COLS:
			s += c[1]
		var v: float = rs.f() * s
		for c in STONE_COLS:
			v -= c[1]
			if v <= 0.0:
				return c[0]
		return STONE_COLS[0][0]
	var oct_items := []
	var tet_items := []
	var density := func(x: float) -> float:
		if x > -17.2 and x < -6.8:
			return 0.0
		if x > 45.8 and x < 48.7:
			return 0.0
		if x > -62.0 and x < 102.0:
			return 1.0
		if x > -135.0 and x < 165.0:
			return 0.28
		return 0.0
	var place := func(x: float, z: float, big: bool) -> void:
		var rad: float = (0.032 if big else 0.024) + rs.f() * rs.f() * 0.03
		var y: float = E.ballastY.call(z)
		var it := {"x": x, "y": y - rad * 0.12, "z": z}
		it["rx"] = (rs.f() - 0.5) * 0.5
		it["ry"] = rs.f() * 6.28
		it["rz"] = (rs.f() - 0.5) * 0.5
		it["sx"] = rad * (0.9 + rs.f() * 0.6)
		it["sy"] = rad * (0.42 + rs.f() * 0.22)
		it["sz"] = rad * (0.9 + rs.f() * 0.6)
		it["c"] = pick_c.call()
		(oct_items if rs.f() < 0.8 else tet_items).append(it)
	var BANDS := [[0.0, 1.0, 11.0], [1.0, 3.0, 8.0], [3.0, 3.95, 15.0]]
	for xi in range(-140, 170):
		var x := float(xi)
		var dens: float = density.call(x + 0.5)
		if dens == 0.0:
			continue
		for bd in BANDS:
			var d0: float = bd[0]
			var d1: float = bd[1]
			for s in [-1, 1]:
				var n := T.js_round(bd[2] * (d1 - d0) * dens * (0.8 + rs.f() * 0.4))
				for i in n:
					var px: float = x + rs.f()
					var d: float = d0 + (d1 - d0) * rs.f()
					var pz: float = -43.0 + s * d
					if on_sleeper.call(px, pz, 0.035) or near_rail.call(px, pz):
						continue
					if px > -7.0 and px < 46.0 and d > 3.45:
						continue
					place.call(px, pz, d > 3.0)
	var soften := func(g: T.Geometry) -> T.Geometry:
		g = g.to_non_indexed()
		g.compute_vertex_normals()
		var nn: T.Attr = g.attributes.normal
		var p: T.Attr = g.attributes.position
		for i in nn.count():
			if p.get_y(i) > 0.5:
				p.set_y(i, 0.62)
			var v := Vector3(nn.get_x(i), nn.get_y(i) * 0.6 + 0.9, nn.get_z(i)).normalized()
			nn.set_xyz(i, v.x, v.y, v.z)
		return g
	var oct: T.Geometry = soften.call(_octahedron())
	var tet: T.Geometry = soften.call(_octahedron().scale(1.35, 0.8, 0.85))
	for e in [[oct, oct_items, "rw-stones-oct"], [tet, tet_items, "rw-stones-tet"]]:
		var im = make_instanced(e[0], M.stone, e[1], {"shadow": false, "colors": true})
		if im:
			im.name = e[2]
			ctx.no_outline(im)
			root.add(im)
	out["stoneCount"] = oct_items.size() + tet_items.size()
	out["TX0"] = TX0
	out["TX1"] = TX1
	return out
