# trains/builder.js: geometry accumulation for the trains. Every part is transformed into train
# space and collected into per-material "buckets" (vertex-coloured), then merged -> a handful of
# meshes per train.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")

static var _cache := {}


static func cached(k: String, f: Callable) -> T.Geometry:
	var g = _cache.get(k)
	if g == null:
		g = f.call()
		_cache[k] = g
	return g


static func r4(v: float) -> float:
	return T.js_round(v * 1e4) / 1e4


static func _s(v: float) -> String:
	return str(r4(v))


# ---------------------------------------------------------------- GEO
static func geo_box() -> T.Geometry:
	return cached("box", func(): return Geo.box(1, 1, 1))


static func geo_rbox(w: float, h: float, d: float, r: float, s: int = 2) -> T.Geometry:
	return cached("rb%s|%s|%s|%s|%d" % [_s(w), _s(h), _s(d), _s(r), s], func(): return Geo.rounded_box(w, h, d, s, maxf(0.001, minf(minf(r, w / 2.0 - 1e-3), minf(h / 2.0 - 1e-3, d / 2.0 - 1e-3)))))


static func geo_cyl(rt: float, rb: float, h: float, seg: int = 12, open: bool = false) -> T.Geometry:
	return cached("cy%s|%s|%s|%d|%s" % [_s(rt), _s(rb), _s(h), seg, str(open)], func(): return Geo.cylinder(rt, rb, h, seg, 1, open))


static func geo_sphere(seg: int = 10) -> T.Geometry:
	return cached("sp%d" % seg, func(): return Geo.sphere(0.5, seg, maxi(5, int(seg * 0.6))))


static func geo_hemi(seg: int = 10) -> T.Geometry:
	return cached("hs%d" % seg, func(): return Geo.sphere(0.5, seg, maxi(4, int(seg * 0.35)), 0.0, PI * 2.0, 0.0, PI / 2.0))


static func geo_torus(R: float, r: float, rs: int = 4, ts: int = 10) -> T.Geometry:
	return cached("to%s|%s|%d|%d" % [_s(R), _s(r), rs, ts], func(): return Geo.torus(R, r, rs, ts))


static func geo_plane() -> T.Geometry:
	return cached("pl", func(): return Geo.plane(1, 1))


static func geo_circle(seg: int = 16) -> T.Geometry:
	return cached("ci%d" % seg, func(): return Geo.circle(0.5, seg))


static func _v3(a) -> Vector3:
	return a if a is Vector3 else Vector3(a[0], a[1], a[2])


static func _n(a, i: int) -> float:
	return float(a[i]) if i < a.size() and a[i] != null else 0.0


## Matrix from position, euler rotation [rx,ry,rz] (order YXZ) and scale.
static func M(pos = [0, 0, 0], rot = null, scale = null) -> Transform3D:
	var e := Vector3(_n(rot, 0), _n(rot, 1), _n(rot, 2)) if rot != null else Vector3.ZERO
	var s := Vector3(scale[0], scale[1], scale[2]) if scale != null else Vector3.ONE
	return Transform3D(Basis.from_euler(e, EULER_ORDER_YXZ) * Basis.from_scale(s), _v3(pos))


## Matrix that maps local +Z to direction n (unit), local +Y as close as possible to up, at position p.
static func basis(p: Vector3, n: Vector3, up: Vector3 = Vector3(0, 1, 0)) -> Transform3D:
	var z := n.normalized()
	var x := up.cross(z)
	if x.length_squared() < 1e-8:
		x = Vector3(1, 0, 0)
	x = x.normalized()
	var y := z.cross(x).normalized()
	return Transform3D(Basis(x, y, z), p)


class Buckets extends RefCounted:
	var defs: Dictionary
	var lists := {}
	var stack: Array = [Transform3D()]
	var tris := 0
	var tag = null
	var _b = load("res://addons/sakuragaoka_station/world/trains/builder.gd")

	## defs: { key: { uv: bool } }
	func _init(d: Dictionary) -> void:
		defs = d
		for k in d:
			lists[k] = []

	func top() -> Transform3D:
		return stack[stack.size() - 1]

	func push(m: Transform3D) -> Buckets:
		stack.append(top() * m)
		return self

	func pop() -> Buckets:
		stack.pop_back()
		return self

	## Add a geometry (cloned) transformed by the current stack × m, coloured (hex) unless
	## color == null and the geometry has its own colour attribute.
	func add(key: String, geo: T.Geometry, m = null, color = "#ffffff") -> T.Geometry:
		var def = defs.get(key)
		if def == null:
			push_error("unknown bucket " + key)
			return null
		var src: Dictionary = geo.attributes
		var sp: T.Attr = src["position"]
		var n := sp.count()
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(sp.array.duplicate(), 3))
		if src.has("normal"):
			g.set_attribute("normal", T.Attr.new((src["normal"] as T.Attr).array.duplicate(), 3))
		if def.get("uv", false):
			if src.has("uv"):
				g.set_attribute("uv", T.Attr.new((src["uv"] as T.Attr).array.duplicate(), 2))
			else:
				var z := PackedFloat32Array()
				z.resize(n * 2)
				g.set_attribute("uv", T.Attr.new(z, 2))
		var ca := PackedFloat32Array()
		ca.resize(n * 3)
		if color == null and src.has("color"):
			var sc: T.Attr = src["color"]
			for i in n:
				ca[i * 3] = sc.get_x(i)
				ca[i * 3 + 1] = sc.get_y(i)
				ca[i * 3 + 2] = sc.get_z(i)
		else:
			var c := T.color(color if color != null else "#ffffff")
			for i in n:
				ca[i * 3] = c.r
				ca[i * 3 + 1] = c.g
				ca[i * 3 + 2] = c.b
		g.set_attribute("color", T.Attr.new(ca, 3))
		var idx: PackedInt32Array
		if geo.indexed:
			idx = geo.index.duplicate()
		else:
			idx = PackedInt32Array()
			idx.resize(n)
			for i in n:
				idx[i] = i
		var tm: Transform3D = top() * m if m != null else top()
		g.apply_matrix4(tm)
		if tm.basis.determinant() < 0.0:
			var i := 0
			while i < idx.size():
				var t := idx[i + 1]
				idx[i + 1] = idx[i + 2]
				idx[i + 2] = t
				i += 3
		g.set_index(idx)
		if not src.has("normal"):
			g.compute_vertex_normals()
		lists[key].append(g)
		tris += idx.size() / 3
		return g

	# ---- shorthand primitives (pos = centre)
	func box(key: String, w: float, h: float, d: float, pos, color, rot = null) -> T.Geometry:
		return add(key, _b.geo_box(), _b.M(pos, rot, [w, h, d]), color)

	func rbox(key: String, w: float, h: float, d: float, r: float, pos, color, rot = null, seg: int = 2) -> T.Geometry:
		return add(key, _b.geo_rbox(w, h, d, r, seg), _b.M(pos, rot), color)

	func cyl(key: String, rt: float, rb: float, h: float, pos, color, rot = null, seg: int = 12, open: bool = false) -> T.Geometry:
		return add(key, _b.geo_cyl(rt, rb, h, seg, open), _b.M(pos, rot), color)

	func sphere(key: String, r: float, pos, color, seg: int = 10, scale = null) -> T.Geometry:
		return add(key, _b.geo_sphere(seg), _b.M(pos, null, [r * 2 * scale[0], r * 2 * scale[1], r * 2 * scale[2]] if scale != null else [r * 2, r * 2, r * 2]), color)

	## Cylinder between two points a, b (arrays).
	func rod(key: String, a, b, r: float, color, seg: int = 8) -> T.Geometry:
		var A: Vector3 = _b._v3(a)
		var Bv: Vector3 = _b._v3(b)
		var d := Bv - A
		var length := d.length()
		var q := T.quat_from_unit_vectors(Vector3(0, 1, 0), d.normalized())
		var m := T.compose(A + d * 0.5, q, Vector3(1, 1, 1))
		return add(key, _b.geo_cyl(r, r, length, seg), m, color)

	## Tube through points.
	func tube(key: String, pts: Array, r: float, color, seg: int = 24, radial: int = 6) -> T.Geometry:
		var vs := []
		for p in pts:
			vs.append(_b._v3(p))
		return add(key, Geo.tube_catmull(vs, false, seg, r, radial, false), null, color)

	## Plane (faces +Z) with UVs mapped to atlas rect {u0,v0,u1,v1}.
	func decal(key: String, w: float, h: float, rect: Dictionary, m = null) -> T.Geometry:
		var g: T.Geometry = _b.geo_plane().clone()
		var uv: T.Attr = g.attributes["uv"]
		for i in uv.count():
			uv.set_xy(i, rect.u0 + (rect.u1 - rect.u0) * uv.get_x(i), rect.v0 + (rect.v1 - rect.v0) * uv.get_y(i))
		g.scale(w, h, 1)
		return add(key, g, m, "#ffffff")

	## Merge each bucket -> geometry.
	func merge() -> Dictionary:
		var out := {}
		for k in lists:
			var list: Array = lists[k]
			if list.is_empty():
				continue
			var g = list[0] if list.size() == 1 else Geo.merge_geometries(list, false)
			if g == null:
				push_warning("trains: merge failed " + k)
				continue
			g.compute_bounding_box()
			out[k] = g
		return out


# ------------------------------------------------------------------ shapes
## Rounded rectangle path points (counter-clockwise) centred at (cx,cy), size w×h, radius r.
static func rrect_pts(cx: float, cy: float, w: float, h: float, r: float, seg: int = 4) -> Array:
	r = minf(r, minf(w / 2.0 - 1e-4, h / 2.0 - 1e-4))
	var pts := []
	var corners := [[cx + w / 2 - r, cy - h / 2 + r, -PI / 2], [cx + w / 2 - r, cy + h / 2 - r, 0.0], [cx - w / 2 + r, cy + h / 2 - r, PI / 2], [cx - w / 2 + r, cy - h / 2 + r, PI]]
	for c in corners:
		var x: float = c[0]
		var y: float = c[1]
		var a0: float = c[2]
		if r <= 1e-4:
			pts.append([x, y])
			continue
		for i in seg + 1:
			var a := a0 + (PI / 2) * i / seg
			pts.append([x + cos(a) * r, y + sin(a) * r])
	return pts


static func shape_from(pts: Array, holes: Array = []) -> Dictionary:
	var hs := []
	for h in holes:
		var rev: Array = h.duplicate()
		rev.reverse()
		hs.append(rev)
	return Geo.shape(pts.duplicate(), hs)


## Extruded shape (in local XY, extruded 0..depth along +Z). Non-indexed.
static func extrude_shape(shape: Dictionary, depth: float, _curve_segments: int = 4) -> T.Geometry:
	var g := Geo.extrude_shape(shape, {"depth": depth, "bevelEnabled": false})
	g.clear_groups()
	return g


static func shape_geo(shape: Dictionary, curve_segments: int = 4) -> T.Geometry:
	return Geo.shape_geometry(shape, curve_segments)


## Colour a geometry per-vertex by normal: fn(nx,ny,nz,x,y,z) -> hex.
static func color_by_normal(geo: T.Geometry, fn: Callable) -> T.Geometry:
	var n: T.Attr = geo.attributes["normal"]
	var p: T.Attr = geo.attributes["position"]
	var c := PackedFloat32Array()
	c.resize(p.count() * 3)
	var memo := {}
	for i in p.count():
		var hx: String = fn.call(n.get_x(i), n.get_y(i), n.get_z(i), p.get_x(i), p.get_y(i), p.get_z(i))
		var col: Color
		if memo.has(hx):
			col = memo[hx]
		else:
			col = T.color(hx)
			memo[hx] = col
		c[i * 3] = col.r
		c[i * 3 + 1] = col.g
		c[i * 3 + 2] = col.b
	geo.set_attribute("color", T.Attr.new(c, 3))
	return geo


# ------------------------------------------------------------------ parametric surfaces
## Build a surface from rows of parameter points. rows: [[ [a,b], ... ], ...] each row sorted.
## surf(a,b) -> { p: Vector3, n: Vector3 }. offset along the normal. flip: inward-facing.
## Triangles between consecutive rows are "zippered" (rows may have different counts).
static func rows_surface(rows: Array, surf: Callable, offset: float = 0.0, flip: bool = false) -> T.Geometry:
	var pos := PackedFloat64Array()
	var nor := PackedFloat64Array()
	var idx := []  # an Array: the closure below appends to it (packed arrays are captured by value)
	var starts := []
	for row in rows:
		starts.append(pos.size() / 3)
		for ab in row:
			var s: Dictionary = surf.call(ab[0], ab[1])
			var sp: Vector3 = s.p
			var sn: Vector3 = s.n
			var nx := -sn.x if flip else sn.x
			var ny := -sn.y if flip else sn.y
			var nz := -sn.z if flip else sn.z
			pos.append(sp.x + sn.x * offset); pos.append(sp.y + sn.y * offset); pos.append(sp.z + sn.z * offset)
			nor.append(nx); nor.append(ny); nor.append(nz)
	var tri := func(i: int, j: int, k: int) -> void:
		var ux := pos[j * 3] - pos[i * 3]
		var uy := pos[j * 3 + 1] - pos[i * 3 + 1]
		var uz := pos[j * 3 + 2] - pos[i * 3 + 2]
		var vx := pos[k * 3] - pos[i * 3]
		var vy := pos[k * 3 + 1] - pos[i * 3 + 1]
		var vz := pos[k * 3 + 2] - pos[i * 3 + 2]
		var fx := uy * vz - uz * vy
		var fy := uz * vx - ux * vz
		var fz := ux * vy - uy * vx
		if fx * fx + fy * fy + fz * fz < 1e-14:
			return
		var nx := nor[i * 3] + nor[j * 3] + nor[k * 3]
		var ny := nor[i * 3 + 1] + nor[j * 3 + 1] + nor[k * 3 + 1]
		var nz := nor[i * 3 + 2] + nor[j * 3 + 2] + nor[k * 3 + 2]
		if fx * nx + fy * ny + fz * nz >= 0.0:
			idx.append(i); idx.append(j); idx.append(k)
		else:
			idx.append(i); idx.append(k); idx.append(j)
	for r in rows.size() - 1:
		var A: Array = rows[r]
		var B: Array = rows[r + 1]
		var a0: int = starts[r]
		var b0: int = starts[r + 1]
		var i := 0
		var j := 0
		while i < A.size() - 1 or j < B.size() - 1:
			var can_i := i < A.size() - 1
			var can_j := j < B.size() - 1
			var adv_i: bool
			if not can_j:
				adv_i = true
			elif not can_i:
				adv_i = false
			else:
				adv_i = A[i + 1][0] <= B[j + 1][0]
			if adv_i:
				tri.call(a0 + i, a0 + i + 1, b0 + j)
				i += 1
			else:
				tri.call(a0 + i, b0 + j + 1, b0 + j)
				j += 1
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(PackedFloat32Array(Array(pos)), 3))
	g.set_attribute("normal", T.Attr.new(PackedFloat32Array(Array(nor)), 3))
	g.set_index(idx)
	return g


## Sweep a 2D profile (array of [z,y] + normals [nz,ny]) straight along x from x0 to x1.
static func sweep_x(profile: Array, normals: Array, x0: float, x1: float) -> T.Geometry:
	var pos := PackedFloat32Array()
	var nor := PackedFloat32Array()
	var idx := PackedInt32Array()
	for i in profile.size():
		var z: float = profile[i][0]
		var y: float = profile[i][1]
		var nz: float = normals[i][0]
		var ny: float = normals[i][1]
		pos.append_array([x0, y, z, x1, y, z])
		nor.append_array([0, ny, nz, 0, ny, nz])
	for i in profile.size() - 1:
		var a := i * 2
		var b := i * 2 + 1
		var c := i * 2 + 2
		var d := i * 2 + 3
		idx.append_array([a, c, b, b, c, d])
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(pos, 3))
	g.set_attribute("normal", T.Attr.new(nor, 3))
	g.set_index(idx)
	fix_winding(g)
	return g


## Make every triangle's winding agree with its vertex normals.
static func fix_winding(g: T.Geometry) -> T.Geometry:
	var p: T.Attr = g.attributes["position"]
	var n: T.Attr = g.attributes["normal"]
	var ix := g.index
	var i := 0
	while i < ix.size():
		var a := p.v3(ix[i])
		var b := p.v3(ix[i + 1])
		var c := p.v3(ix[i + 2])
		var f := (b - a).cross(c - a)
		var s := n.v3(ix[i]) + n.v3(ix[i + 1]) + n.v3(ix[i + 2])
		if f.dot(s) < 0.0:
			var t := ix[i + 1]
			ix[i + 1] = ix[i + 2]
			ix[i + 2] = t
		i += 3
	g.index = ix
	return g
