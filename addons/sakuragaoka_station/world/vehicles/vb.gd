# vehicles/vb.js: the vertex-colour geometry builder. Every opaque part of a bicycle or car is
# appended (transformed and coloured per vertex) into one geometry, so a vehicle is one mesh with
# one shared material.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")

static var _gc := {}
static var _ccache := {}


## A cached primitive geometry (never mutated: VB clones before transforming).
static func cg(key: String, make: Callable) -> T.Geometry:
	if not _gc.has(key):
		_gc[key] = make.call()
	return _gc[key]


## An sRGB hex as a linear colour (cached).
static func C(hex) -> Color:
	if hex is Color:
		return hex
	if not _ccache.has(hex):
		_ccache[hex] = T.color(hex)
	return _ccache[hex]


## The matrix from pos [x, y, z], rot [rx, ry, rz] (XYZ) and scale [sx, sy, sz].
static func mtx(pos = null, rot = null, scl = null) -> Transform3D:
	var p := Vector3(pos[0], pos[1], pos[2]) if pos != null else Vector3.ZERO
	var r := Vector3.ZERO
	if rot != null:
		r = Vector3(_n(rot, 0), _n(rot, 1), _n(rot, 2))
	var s := Vector3(scl[0], scl[1], scl[2]) if scl != null else Vector3.ONE
	return Transform3D(T.euler_basis(r) * Basis.from_scale(s), p)


static func _n(a, i: int) -> float:
	return float(a[i]) if i < a.size() and a[i] != null else 0.0


static func _with_index(g: T.Geometry) -> T.Geometry:
	if g.indexed:
		return g
	var n := g.vertex_count()
	var idx := PackedInt32Array()
	idx.resize(n)
	for i in n:
		idx[i] = i
	g.set_index(idx)
	return g


class VB extends RefCounted:
	var geos: Array = []
	var M := Transform3D()
	var stack: Array = []
	var tris := 0

	## Multiplies the current transform by m until pop().
	func push(m: Transform3D) -> VB:
		stack.append(M)
		M = M * m
		return self

	func pop() -> VB:
		M = stack.pop_back()
		return self

	## Appends geo coloured `color` under local matrix `local`. tint(p, c, n) returns a modified colour.
	func add(geo: T.Geometry, color, local = null, tint = null, uv_map = null) -> T.Geometry:
		var VBS = load("res://addons/sakuragaoka_station/world/vehicles/vb.gd")
		var g: T.Geometry = VBS._with_index(geo.clone())
		var m: Transform3D = M * local if local != null else M
		for k in g.attributes.keys():
			if k != "position" and k != "normal" and k != "uv":
				g.delete_attribute(k)
		g.clear_groups()
		if not g.has_attribute("normal"):
			g.compute_vertex_normals()
		if not g.has_attribute("uv"):
			var z := PackedFloat32Array()
			z.resize(g.vertex_count() * 2)
			g.set_attribute("uv", T.Attr.new(z, 2))
		g.apply_matrix4(m)
		if m.basis.determinant() < 0.0:
			var ia := g.index
			var i := 0
			while i < ia.size():
				var t := ia[i + 1]
				ia[i + 1] = ia[i + 2]
				ia[i + 2] = t
				i += 3
			g.set_index(ia)
		if uv_map != null:
			uv_map.call(g.get_attribute("uv"))
		var n := g.vertex_count()
		var ca := PackedFloat32Array()
		ca.resize(n * 3)
		var base: Color = VBS.C(color)
		var pa: T.Attr = g.get_attribute("position")
		var na: T.Attr = g.get_attribute("normal")
		for i in n:
			var cc := base
			if tint != null:
				cc = tint.call(pa.v3(i), cc, na.v3(i))
			ca[i * 3] = cc.r
			ca[i * 3 + 1] = cc.g
			ca[i * 3 + 2] = cc.b
		g.set_attribute("color", T.Attr.new(ca, 3))
		geos.append(g)
		tris += g.index.size() / 3
		return g

	func box(w: float, h: float, d: float, color, pos, rot = null, tint = null) -> T.Geometry:
		var VBS = load("res://addons/sakuragaoka_station/world/vehicles/vb.gd")
		return add(VBS.cg("box", func(): return Geo.box(1, 1, 1)), color, VBS.mtx(pos, rot, [w, h, d]), tint)

	## A rounded box (seg 1 is chamfer-like and cheap; seg 2 is smoother).
	func rbox(w: float, h: float, d: float, r: float, color, pos, rot = null, seg: int = 1, tint = null) -> T.Geometry:
		var VBS = load("res://addons/sakuragaoka_station/world/vehicles/vb.gd")
		var R := minf(minf(r, w / 2.0 - 1e-4), minf(h / 2.0 - 1e-4, d / 2.0 - 1e-4))
		var key := "rb|%.3f|%.3f|%.3f|%.3f|%d" % [w, h, d, R, seg]
		return add(VBS.cg(key, func(): return Geo.rounded_box(w, h, d, seg, R)), color, VBS.mtx(pos, rot), tint)

	func cyl(rt: float, rb: float, h: float, color, pos, rot = null, seg: int = 10, tint = null) -> T.Geometry:
		var VBS = load("res://addons/sakuragaoka_station/world/vehicles/vb.gd")
		var key := "cy|%.4f|%.4f|%.4f|%d" % [rt, rb, h, seg]
		return add(VBS.cg(key, func(): return Geo.cylinder(rt, rb, h, seg)), color, VBS.mtx(pos, rot), tint)

	func sph(r: float, color, pos, seg: int = 8, scl = null, rot = null) -> T.Geometry:
		var VBS = load("res://addons/sakuragaoka_station/world/vehicles/vb.gd")
		var s = [r * scl[0], r * scl[1], r * scl[2]] if scl != null else [r, r, r]
		return add(VBS.cg("sp|%d" % seg, func(): return Geo.sphere(1, seg, maxi(4, int(seg * 0.66)))), color, VBS.mtx(pos, rot, s))

	func torus(R: float, r: float, color, pos, rot = null, rad_seg: int = 6, tub_seg: int = 24, arc: float = TAU) -> T.Geometry:
		var VBS = load("res://addons/sakuragaoka_station/world/vehicles/vb.gd")
		var key := "to|%.4f|%.4f|%d|%d|%.3f" % [R, r, rad_seg, tub_seg, arc]
		return add(VBS.cg(key, func(): return Geo.torus(R, r, rad_seg, tub_seg, arc)), color, VBS.mtx(pos, rot))

	## A straight rod from a to b ([x, y, z]).
	func rod(a: Array, b: Array, r: float, color, seg: int = 6):
		var VBS = load("res://addons/sakuragaoka_station/world/vehicles/vb.gd")
		var A := Vector3(a[0], a[1], a[2])
		var B := Vector3(b[0], b[1], b[2])
		var d := B - A
		var ln := d.length()
		if ln < 1e-5:
			return null
		var q := T.quat_from_unit_vectors(Vector3.UP, d.normalized())
		var m := T.compose((A + B) * 0.5, q, Vector3(r, ln, r))
		return add(VBS.cg("rod|%d" % seg, func(): return Geo.cylinder(1, 1, 1, seg)), color, m)

	## A flat bar (box) from a to b: w across (local x), t thick (local z).
	func bar(a: Array, b: Array, w: float, t: float, color, twist: float = 0.0):
		var VBS = load("res://addons/sakuragaoka_station/world/vehicles/vb.gd")
		var A := Vector3(a[0], a[1], a[2])
		var B := Vector3(b[0], b[1], b[2])
		var d := B - A
		var ln := d.length()
		if ln < 1e-5:
			return null
		var q := T.quat_from_unit_vectors(Vector3.UP, d.normalized())
		if twist != 0.0:
			q = q * Quaternion(Vector3.UP, twist)
		var m := T.compose((A + B) * 0.5, q, Vector3(w, ln, t))
		return add(VBS.cg("box", func(): return Geo.box(1, 1, 1)), color, m)

	## A smooth tube through points (CatmullRomCurve3, type catmullrom).
	func tube(points: Array, r: float, color, tub_seg: int = 12, rad_seg: int = 6, tension: float = 0.5) -> T.Geometry:
		var VBS = load("res://addons/sakuragaoka_station/world/vehicles/vb.gd")
		var pts := []
		for p in points:
			pts.append(Vector3(p[0], p[1], p[2]))
		return add(VBS.tube_geometry(pts, tension, tub_seg, r, rad_seg), color)

	func geo(g: T.Geometry, color, pos = null, rot = null, scl = null, tint = null) -> T.Geometry:
		var VBS = load("res://addons/sakuragaoka_station/world/vehicles/vb.gd")
		return add(g, color, VBS.mtx(pos, rot, scl), tint)

	func build():
		if geos.is_empty():
			return null
		var g: T.Geometry = Geo.merge_geometries(geos, false)
		geos = []
		g.compute_bounding_box()
		return g


## CatmullRomCurve3(points, false, 'catmullrom', tension).getPoint(t).
static func catmull_point(pts: Array, tension: float, t: float) -> Vector3:
	var l := pts.size()
	var p := (l - 1) * t
	var ip := int(floor(p))
	var w := p - ip
	if w == 0.0 and ip == l - 1:
		ip = l - 2
		w = 1.0
	var p0: Vector3 = pts[ip - 1] if ip > 0 else (pts[0] - pts[1]) + pts[0]
	var p1: Vector3 = pts[ip]
	var p2: Vector3 = pts[ip + 1]
	var p3: Vector3 = pts[ip + 2] if ip + 2 < l else (pts[l - 1] - pts[l - 2]) + pts[l - 1]
	return Vector3(_cr(p0.x, p1.x, p2.x, p3.x, tension, w), _cr(p0.y, p1.y, p2.y, p3.y, tension, w),
		_cr(p0.z, p1.z, p2.z, p3.z, tension, w))


static func _cr(x0: float, x1: float, x2: float, x3: float, tension: float, s: float) -> float:
	var t0 := tension * (x2 - x0)
	var t1 := tension * (x3 - x1)
	var c2 := -3.0 * x1 + 3.0 * x2 - 2.0 * t0 - t1
	var c3 := 2.0 * x1 - 2.0 * x2 + t0 + t1
	return x1 + t0 * s + c2 * s * s + c3 * s * s * s


## TubeGeometry(curve, tubular, radius, radial, false) over a catmullrom curve.
static func tube_geometry(pts: Array, tension: float, tubular: int, radius: float, radial: int) -> T.Geometry:
	var gp := func(t: float) -> Vector3: return catmull_point(pts, tension, t)
	var lengths := PackedFloat64Array([0.0])
	var last: Vector3 = gp.call(0.0)
	var sum := 0.0
	for p in range(1, 201):
		var cur: Vector3 = gp.call(float(p) / 200)
		sum += cur.distance_to(last)
		lengths.append(sum)
		last = cur
	var u_to_t := func(u: float) -> float:
		var il := lengths.size()
		var target := u * lengths[il - 1]
		var low := 0
		var high := il - 1
		var i := 0
		while low <= high:
			i = int(floor(low + (high - low) / 2.0))
			var cmp := lengths[i] - target
			if cmp < 0.0:
				low = i + 1
			elif cmp > 0.0:
				high = i - 1
			else:
				high = i
				break
		i = high
		if lengths[i] == target:
			return float(i) / (il - 1)
		var seg := lengths[i + 1] - lengths[i]
		return (i + (target - lengths[i]) / seg) / (il - 1)
	var tangents := []
	for i in tubular + 1:
		var t: float = u_to_t.call(float(i) / tubular)
		var a: Vector3 = gp.call(maxf(t - 0.0001, 0.0))
		var b: Vector3 = gp.call(minf(t + 0.0001, 1.0))
		tangents.append((b - a).normalized())
	var normals := [Vector3.ZERO]
	var binormals := [Vector3.ZERO]
	var mn := INF
	var t0: Vector3 = tangents[0]
	var nrm := Vector3.ZERO
	if absf(t0.x) <= mn:
		mn = absf(t0.x)
		nrm = Vector3(1, 0, 0)
	if absf(t0.y) <= mn:
		mn = absf(t0.y)
		nrm = Vector3(0, 1, 0)
	if absf(t0.z) <= mn:
		nrm = Vector3(0, 0, 1)
	var vec := t0.cross(nrm).normalized()
	normals[0] = t0.cross(vec)
	binormals[0] = t0.cross(normals[0])
	for i in range(1, tubular + 1):
		normals.append(normals[i - 1])
		binormals.append(binormals[i - 1])
		vec = (tangents[i - 1] as Vector3).cross(tangents[i])
		if vec.length() > T.EPS:
			vec = vec.normalized()
			var theta := acos(clampf((tangents[i - 1] as Vector3).dot(tangents[i]), -1.0, 1.0))
			normals[i] = Basis(vec, theta) * (normals[i] as Vector3)
		binormals[i] = (tangents[i] as Vector3).cross(normals[i])
	var pos := PackedFloat32Array()
	var nor := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var idx := PackedInt32Array()
	for i in tubular + 1:
		var P: Vector3 = gp.call(u_to_t.call(float(i) / tubular))
		var N: Vector3 = normals[i]
		var B: Vector3 = binormals[i]
		for j in radial + 1:
			var v := float(j) / radial * TAU
			var n := (-cos(v) * N + sin(v) * B).normalized()
			nor.append(n.x); nor.append(n.y); nor.append(n.z)
			pos.append(P.x + radius * n.x); pos.append(P.y + radius * n.y); pos.append(P.z + radius * n.z)
	for i in tubular + 1:
		for j in radial + 1:
			uv.append(float(i) / tubular); uv.append(float(j) / radial)
	for j in range(1, tubular + 1):
		for i in range(1, radial + 1):
			var a := (radial + 1) * (j - 1) + (i - 1)
			var b := (radial + 1) * j + (i - 1)
			var c := (radial + 1) * j + i
			var d := (radial + 1) * (j - 1) + i
			idx.append(a); idx.append(b); idx.append(d)
			idx.append(b); idx.append(c); idx.append(d)
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(pos, 3))
	g.set_attribute("normal", T.Attr.new(nor, 3))
	g.set_attribute("uv", T.Attr.new(uv, 2))
	g.set_index(idx)
	return g


## An arc band swept around local X (fenders, wheel arches): radius R, profile [[x, dr], ...] as a
## closed loop; a0 < a1 where angle 0 is +Z (forward) and PI/2 is +Y (up).
static func arc_sweep(R: float, prof: Array, a0: float, a1: float, seg: int) -> T.Geometry:
	var pos := PackedFloat32Array()
	var idx := PackedInt32Array()
	for e in prof.size():
		var p0: Array = prof[e]
		var p1: Array = prof[(e + 1) % prof.size()]
		var base := pos.size() / 3
		for i in seg + 1:
			var a := a0 + (a1 - a0) * i / seg
			var s := sin(a)
			var c := cos(a)
			for p in [p0, p1]:
				var rr: float = R + p[1]
				pos.append(p[0]); pos.append(rr * s); pos.append(rr * c)
		for i in seg:
			var a := base + i * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(pos, 3))
	g.set_index(idx)
	g.compute_vertex_normals()
	return g


## A quad from 4 corners (counter-clockwise seen from the front).
static func quad(a: Array, b: Array, c: Array, d: Array) -> T.Geometry:
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(PackedFloat32Array(a + b + c + d), 3))
	g.set_attribute("uv", T.Attr.new(PackedFloat32Array([0, 0, 1, 0, 1, 1, 0, 1]), 2))
	g.set_index([0, 1, 2, 0, 2, 3])
	g.compute_vertex_normals()
	return g


## A flat polygon ([[x, y], ...]) in the XY plane facing +Z.
static func poly(points: Array) -> T.Geometry:
	return Geo.shape_geometry(Geo.shape(points))


## The 2D convex hull (monotone chain) of [[x, y], ...] as a CCW polygon.
static func hull(pts: Array) -> Array:
	var P := pts.duplicate()
	P = T.stable_sort(P, func(a, b): return a[0] - b[0] if a[0] != b[0] else a[1] - b[1])
	var cross := func(o, a, b): return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
	var lo := []
	var up := []
	for p in P:
		while lo.size() >= 2 and cross.call(lo[lo.size() - 2], lo[lo.size() - 1], p) <= 0:
			lo.pop_back()
		lo.append(p)
	for i in range(P.size() - 1, -1, -1):
		var p = P[i]
		while up.size() >= 2 and cross.call(up[up.size() - 2], up[up.size() - 1], p) <= 0:
			up.pop_back()
		up.append(p)
	up.pop_back()
	lo.pop_back()
	return lo + up
