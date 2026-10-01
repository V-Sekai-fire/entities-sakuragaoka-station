# station/util.js: world-space UV boxes, atlas planes, beams, walls with openings, railings,
# foliage-card batches and ground patches.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")

var ctx
var _cache := {}


func _init(c) -> void:
	ctx = c


func cyl(seg: int = 10) -> T.Geometry:
	var key := "cyl%d" % seg
	if not _cache.has(key):
		_cache[key] = Geo.cylinder(0.5, 0.5, 1, seg)
	return _cache[key]


## cylinder lying along +Z (unit length, unit diameter)
func cyl_z(seg: int = 8) -> T.Geometry:
	var key := "cylZ%d" % seg
	if not _cache.has(key):
		_cache[key] = Geo.cylinder(0.5, 0.5, 1, seg).rotate_x(PI / 2.0)
	return _cache[key]


## Re-maps a mesh's UVs to world metres; UVs only, so the port leaves the geometry as it is.
func world_uv(mesh, _tile = 1, _off = [0, 0], _swap_top: bool = false):
	return mesh


## Plane geometry whose UVs map to an atlas sub-rect r = {u0, v0, u1, v1}.
func rect_plane(w: float, h: float, r: Dictionary) -> T.Geometry:
	var g := Geo.plane(w, h)
	var uv: T.Attr = g.attributes.uv
	for i in uv.count():
		uv.set_xy(i, r.u0 + uv.get_x(i) * (r.u1 - r.u0), r.v0 + uv.get_y(i) * (r.v1 - r.v0))
	return g


## three.js Matrix4.lookAt(eye, target, up) as a basis (+Z from target to eye).
static func look_at_basis(eye: Vector3, target: Vector3, up: Vector3) -> Basis:
	var z := eye - target
	if z.length_squared() == 0.0:
		z.z = 1.0
	z = z.normalized()
	var x := up.cross(z)
	if x.length_squared() == 0.0:
		if absf(up.z) == 1.0:
			z.x += 0.0001
		else:
			z.z += 0.0001
		z = z.normalized()
		x = up.cross(z)
	x = x.normalized()
	var y := z.cross(x)
	return Basis(x, y, z)


## Box from a to b (centre line), w (horizontal) x h (vertical) cross-section; round = cylinder.
func beam(k, a: Array, b: Array, w: float, h: float, m, round: bool = false, seg: int = 8):
	var A := Vector3(a[0], a[1], a[2])
	var B := Vector3(b[0], b[1], b[2])
	var len := A.distance_to(B)
	var mesh := T.MeshObj.new(cyl_z(seg) if round else Geo.g_box(ctx.cache), m)
	mesh.position = (A + B) * 0.5
	mesh.scale = Vector3(w, h, len)
	k.parent.add(mesh)
	var up := Vector3(1, 0, 0) if absf(B.y - A.y) > 0.999 * len else Vector3(0, 1, 0)
	mesh.set_quaternion(look_at_basis(B, A, up).get_rotation_quaternion())
	mesh.cast_shadow = true
	mesh.receive_shadow = true
	return mesh


## Straight wall along an axis with rectangular openings [{a0, a1, y0, y1}].
func wall(k, m, axis: String, c0: float, c1: float, a0: float, a1: float, y0: float, y1: float, openings: Array = [], tile = null) -> Array:
	var edges := {a0: true, a1: true}
	for o in openings:
		edges[maxf(a0, minf(a1, o.a0))] = true
		edges[maxf(a0, minf(a1, o.a1))] = true
	var xs := edges.keys()
	xs.sort()
	var out := []
	for i in xs.size() - 1:
		var s: float = xs[i]
		var e: float = xs[i + 1]
		if e - s < 1e-4:
			continue
		var mid := (s + e) / 2.0
		var holes := []
		for o in openings:
			if o.a0 < mid and o.a1 > mid:
				holes.append([maxf(y0, o.y0), minf(y1, o.y1)])
		T.stable_sort(holes, func(p, q): return p[0] - q[0])
		var y := y0
		var spans := []
		for hh in holes:
			if hh[0] > y + 1e-4:
				spans.append([y, hh[0]])
			y = maxf(y, hh[1])
		if y1 > y + 1e-4:
			spans.append([y, y1])
		for sp in spans:
			var Lw := e - s
			var H: float = sp[1] - sp[0]
			var Tt := c1 - c0
			var pos := [mid, (sp[0] + sp[1]) / 2.0, (c0 + c1) / 2.0] if axis == "x" else [(c0 + c1) / 2.0, (sp[0] + sp[1]) / 2.0, mid]
			var mesh = k.box(Lw, H, Tt, m, pos) if axis == "x" else k.box(Tt, H, Lw, m, pos)
			out.append(mesh)
	return out


## Railing along a polyline of [x, z]; base is a number or a Callable (x, z) -> y.
func railing(k, pts: Array, base, opts: Dictionary = {}) -> void:
	var h: float = opts.get("h", 1.1)
	var m = opts.get("mat")
	var pm = opts.get("postMat") if opts.get("postMat") != null else m
	var yb: Callable = base if base is Callable else func(_x, _z): return base
	var rails: Array = opts.get("rails", [1.0, 0.55])
	var post_w: float = opts.get("postW", 0.05)
	var rail_w: float = opts.get("railW", 0.042)
	for i in pts.size() - 1:
		var ax: float = pts[i][0]
		var az: float = pts[i][1]
		var bx: float = pts[i + 1][0]
		var bz: float = pts[i + 1][1]
		var len := sqrt((bx - ax) ** 2 + (bz - az) ** 2)
		var n_post := maxi(1, T.js_round(len / float(opts.get("post", 2.0))))
		for j in n_post + 1:
			if j == 0 and i > 0:
				continue
			var t := float(j) / n_post
			var x := ax + (bx - ax) * t
			var z := az + (bz - az) * t
			var y: float = yb.call(x, z)
			if opts.get("round", false):
				k.cyl(post_w / 2.0, post_w / 2.0, h, pm, [x, y + h / 2.0, z], null, 8)
			else:
				k.box(post_w, h, post_w, pm, [x, y + h / 2.0, z])
		for f in rails:
			var ya: float = yb.call(ax, az) + h * f - (rail_w / 2.0 if f == 1.0 else 0.0)
			var ybb: float = yb.call(bx, bz) + h * f - (rail_w / 2.0 if f == 1.0 else 0.0)
			beam(k, [ax, ya, az], [bx, ybb, bz], rail_w, rail_w, m, bool(opts.get("round", false)))
		if opts.get("bar"):
			var nb := maxi(1, floori(len / float(opts.bar)))
			var lo: float = opts.get("barLo", 0.1)
			var hi: float = rails[0] * h - rail_w
			for j in range(1, nb):
				var t := float(j) / nb
				var x := ax + (bx - ax) * t
				var z := az + (bz - az) * t
				var y: float = yb.call(x, z)
				k.box(opts.get("barW", 0.022), hi - lo, opts.get("barW", 0.022), m, [x, y + (lo + hi) / 2.0, z])


func cards() -> Cards:
	return Cards.new()


## Ground-hugging subdivided plane over a rectangle following height_at (+lift).
func ground_patch(x0: float, x1: float, z0: float, z1: float, m, lift: float = 0.012, step: float = 0.5, hfn = null):
	var L = ctx.L
	var nx := maxi(1, T.js_round((x1 - x0) / step))
	var nz := maxi(1, T.js_round((z1 - z0) / step))
	var g := Geo.plane(x1 - x0, z1 - z0, nx, nz).rotate_x(-PI / 2.0)
	var p := g.position()
	for i in p.count():
		var x := p.get_x(i) + (x0 + x1) / 2.0
		var z := p.get_z(i) + (z0 + z1) / 2.0
		var y: float = hfn.call(x, z) if hfn != null else L.height_at(x, z)
		p.set_xyz(i, x, y + lift, z)
	g.compute_vertex_normals()
	var mesh := T.MeshObj.new(g, m)
	mesh.receive_shadow = true
	return mesh


## Accumulates alpha-tested vegetation cards into one geometry (one draw call).
class Cards extends RefCounted:
	var P := PackedFloat32Array()
	var U := PackedFloat32Array()
	var Nn := PackedFloat32Array()
	var I := PackedInt32Array()
	var vcount := 0

	func quad(x: float, y: float, z: float, w: float, h: float, ang: float, r: Dictionary, lean: float = 0.0) -> void:
		var c := cos(ang)
		var s := sin(ang)
		var dx := c * w / 2.0
		var dz := -s * w / 2.0
		var lx := sin(ang) * lean
		var lz := cos(ang) * lean
		P.append_array([x - dx, y, z - dz, x + dx, y, z + dz, x + dx + lx, y + h, z + dz + lz, x - dx + lx, y + h, z - dz + lz])
		U.append_array([r.u0, r.v0, r.u1, r.v0, r.u1, r.v1, r.u0, r.v1])
		for i in 4:
			Nn.append_array([0, 1, 0])
		I.append_array([vcount, vcount + 1, vcount + 2, vcount, vcount + 2, vcount + 3])
		vcount += 4

	## crossed pair of cards, bottom centre at (x, y, z)
	func cross(x: float, y: float, z: float, w: float, h: float, ang: float, r: Dictionary, lean: float = 0.0) -> void:
		quad(x, y, z, w, h, ang, r, lean)
		quad(x, y, z, w, h, ang + PI / 2.0, r, -lean)

	## three-way star
	func star(x: float, y: float, z: float, w: float, h: float, ang: float, r: Dictionary) -> void:
		for i in 3:
			quad(x, y, z, w, h, ang + i * PI / 3.0, r)

	func count() -> int:
		return vcount / 4

	func build(material):
		if vcount == 0:
			return null
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(P, 3))
		g.set_attribute("normal", T.Attr.new(Nn, 3))
		g.set_attribute("uv", T.Attr.new(U, 2))
		g.set_index(I)
		g.compute_bounding_box()
		var mesh := T.MeshObj.new(g, material)
		mesh.cast_shadow = false
		mesh.receive_shadow = true
		return mesh
