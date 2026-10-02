# houses/gb.js: the geometry accumulator for the houses module. Small parts are appended as raw
# vertex data into per-material bins (vertex colours carry the colour), then flushed into one mesh
# per bin.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")

## [normal, u axis, v axis] per face, in BoxGeometry order (px, nx, py, ny, pz, nz).
const BOX_FACES := [
	{"n": [1, 0, 0], "u": [2, -1], "v": [1, 1]},
	{"n": [-1, 0, 0], "u": [2, 1], "v": [1, 1]},
	{"n": [0, 1, 0], "u": [0, 1], "v": [2, -1]},
	{"n": [0, -1, 0], "u": [0, 1], "v": [2, 1]},
	{"n": [0, 0, 1], "u": [0, 1], "v": [1, 1]},
	{"n": [0, 0, -1], "u": [0, -1], "v": [1, 1]},
]

static var _geo_cache := {}
static var _col_cache := {}


static func col(c) -> Color:
	if c is Color:
		return c
	if not _col_cache.has(c):
		_col_cache[c] = T.color(c)
	return _col_cache[c]


static func v3(a: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(a.size() / 3)
	for k in out.size():
		out[k] = Vector3(a[k * 3], a[k * 3 + 1], a[k * 3 + 2])
	return out


static func v2(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(a.size() / 2)
	for k in out.size():
		out[k] = Vector2(a[k * 2], a[k * 2 + 1])
	return out


static func f32(v) -> PackedFloat32Array:
	var b: PackedByteArray = v.to_byte_array()
	if v is PackedColorArray:
		return b.to_float32_array()
	var n: int = v.size() * (3 if v is PackedVector3Array else 2)
	if b.size() == n * 8:
		return PackedFloat32Array(Array(b.to_float64_array()))
	return b.to_float32_array()


## A BufferGeometry as plain arrays, made once per key: {p, n, u, i, c}.
static func raw_of(key: String, make: Callable) -> Dictionary:
	if _geo_cache.has(key):
		return _geo_cache[key]
	var g: T.Geometry = make.call()
	if not g.has_attribute("normal"):
		g.compute_vertex_normals()
	var pa: T.Attr = g.get_attribute("position")
	var nv := pa.count()
	var U := PackedVector2Array()
	U.resize(nv)
	if g.has_attribute("uv"):
		var ua: T.Attr = g.get_attribute("uv")
		for k in nv:
			U[k] = Vector2(ua.get_x(k), ua.get_y(k))
	var I := PackedInt32Array()
	if g.indexed:
		I = g.index.duplicate()
	else:
		I.resize(nv)
		for k in nv:
			I[k] = k
	var C = null
	if g.has_attribute("color"):
		var ca: T.Attr = g.get_attribute("color")
		C = PackedColorArray()
		C.resize(nv)
		for k in nv:
			C[k] = Color(ca.get_x(k), ca.get_y(k), ca.get_z(k))
	var r := {"p": pa.vec3_array(), "n": g.get_attribute("normal").vec3_array(), "u": U, "i": I, "c": C}
	_geo_cache[key] = r
	return r


class GB extends RefCounted:
	var ctx
	var bins := {}
	var tris := 0

	func _init(c) -> void:
		ctx = c

	func _bin(mat, fl) -> Dictionary:
		var shadow := 0 if fl is Dictionary and fl.get("shadow", true) == false else 1
		var no := 1 if fl is Dictionary and fl.get("noOutline", false) else 0
		var rec := 0 if fl is Dictionary and fl.get("receive", true) == false else 1
		var key := "%d|%d%d%d" % [mat.get_instance_id(), shadow, no, rec]
		if not bins.has(key):
			bins[key] = {"mat": mat, "chunks": [], "vc": 0, "shadow": shadow == 1, "noOutline": no == 1, "receive": rec == 1}
		return bins[key]

	## Appends raw arrays transformed by m. uvx: null | [su, sv, ou, ov] | Callable(u, v, k) -> Vector2.
	## C: optional per-vertex linear colours, multiplied by color.
	func raw(mat, color, P: PackedVector3Array, N: PackedVector3Array, U: PackedVector2Array, I: PackedInt32Array, m: Transform3D, uvx = null, fl = null, C = null) -> void:
		var b := _bin(mat, fl)
		var nb := m.basis.inverse().transposed()
		var c := Color(1, 1, 1)
		if color != null:
			c = GBS.col(color)
		var nv := P.size()
		var pp: PackedVector3Array = m * P
		var nn: PackedVector3Array = Transform3D(nb, Vector3.ZERO) * N
		for k in nv:
			nn[k] = nn[k].normalized()
		var uu := U
		if uvx != null:
			uu = U.duplicate()
			if uvx is Callable:
				for k in nv:
					uu[k] = uvx.call(U[k].x, U[k].y, k)
			else:
				for k in nv:
					uu[k] = Vector2(U[k].x * uvx[0] + uvx[2], U[k].y * uvx[1] + uvx[3])
		var cc := PackedColorArray()
		cc.resize(nv)
		if C != null:
			for k in nv:
				cc[k] = Color(c.r * C[k].r, c.g * C[k].g, c.b * C[k].b)
		else:
			cc.fill(c)
		b.chunks.append([pp, nn, uu, cc, I, b.vc])
		b.vc += nv
		tris += I.size() / 3

	## A w x h x d box centred at m's origin. uv: null (0..1 per face), {world, worldV, ou, ov} (metres
	## per repeat) or {rect, white, faces} for atlas mapping. fl.skip names faces to omit (r l t d f b).
	func box(mat, color, w: float, h: float, d: float, m: Transform3D, uv = null, fl = null) -> void:
		var P := PackedVector3Array()
		var N := PackedVector3Array()
		var U := PackedVector2Array()
		var I := PackedInt32Array()
		var hs := [w / 2.0, h / 2.0, d / 2.0]
		var dims := [w, h, d]
		var skip = fl.get("skip") if fl is Dictionary else null
		var uvd: Dictionary = uv if uv is Dictionary else {}
		for f in 6:
			if skip and String(skip).contains("rltdfb"[f]):
				continue
			var F: Dictionary = GBS.BOX_FACES[f]
			var ua: int = F.u[0]
			var us: int = F.u[1]
			var va: int = F.v[0]
			var vs: int = F.v[1]
			var na := 0
			while F.n[na] == 0:
				na += 1
			var ns: int = F.n[na]
			var nrm := Vector3(F.n[0], F.n[1], F.n[2])
			var base := P.size()
			for j in 4:
				var su := 1 if (j == 1 or j == 2) else -1
				var sv := 1 if j >= 2 else -1
				var q := [0.0, 0.0, 0.0]
				q[na] = ns * hs[na]
				q[ua] = su * us * hs[ua]
				q[va] = sv * vs * hs[va]
				P.append(Vector3(q[0], q[1], q[2]))
				N.append(nrm)
				var u0 := (su + 1) / 2.0
				var v0 := (sv + 1) / 2.0
				if uvd.get("world"):
					u0 = (su * dims[ua] / 2.0 + uvd.get("ou", 0.0)) / uvd.world
					v0 = (sv * dims[va] / 2.0 + uvd.get("ov", 0.0)) / (uvd.worldV if uvd.get("worldV") else uvd.world)
				elif uvd.get("rect"):
					var front: bool = f == 4 or (uvd.get("faces") == "front+back" and f == 5) or uvd.get("faces") == "all"
					if front:
						var r: Array = uvd.rect
						u0 = r[0] + (r[2] - r[0]) * u0
						v0 = r[1] + (r[3] - r[1]) * v0
					else:
						u0 = uvd.white[0]
						v0 = uvd.white[1]
				U.append(Vector2(u0, v0))
			var e1 := P[base + 1] - P[base]
			var e2 := P[base + 2] - P[base]
			if e1.cross(e2).dot(nrm) >= 0.0:
				I.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
			else:
				I.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		if uvd.get("skipBottom") and not skip:
			var J := PackedInt32Array()
			for k in I.size():
				if k < 18 or k >= 24:
					J.append(I[k])
			I = J
		raw(mat, color, P, N, U, I, m, null, fl)

	func mesh(mat, color, P: PackedVector3Array, N: PackedVector3Array, U: PackedVector2Array, I: PackedInt32Array, m: Transform3D, fl = null) -> void:
		raw(mat, color, P, N, U, I, m, null, fl)

	## Emits the accumulated bins as meshes into parent.
	func flush(parent, name: String = "houses") -> Array:
		var out := []
		for b in bins.values():
			if b.vc == 0:
				continue
			var p := PackedVector3Array()
			var n := PackedVector3Array()
			var u := PackedVector2Array()
			var c := PackedColorArray()
			var ix := PackedInt32Array()
			for ch in b.chunks:
				p.append_array(ch[0])
				n.append_array(ch[1])
				u.append_array(ch[2])
				c.append_array(ch[3])
				var off: int = ch[5]
				var I: PackedInt32Array = ch[4]
				var at := ix.size()
				ix.append_array(I)
				if off != 0:
					for k in I.size():
						ix[at + k] = I[k] + off
			var g := T.Geometry.new()
			g.set_attribute("position", T.Attr.new(GBS.f32(p), 3))
			g.set_attribute("normal", T.Attr.new(GBS.f32(n), 3))
			g.set_attribute("uv", T.Attr.new(GBS.f32(u), 2))
			if b.mat.vertex_colors:
				var cf := PackedFloat32Array()
				cf.resize(c.size() * 3)
				for k in c.size():
					cf[k * 3] = c[k].r
					cf[k * 3 + 1] = c[k].g
					cf[k * 3 + 2] = c[k].b
				g.set_attribute("color", T.Attr.new(cf, 3))
			g.set_index(ix)
			g.compute_bounding_box()
			var m := T.MeshObj.new(g, b.mat)
			m.name = name
			m.cast_shadow = b.shadow
			m.receive_shadow = b.receive
			if b.noOutline:
				ctx.no_outline(m)
			parent.add(m)
			out.append(m)
		bins.clear()
		return out


const GBS = preload("res://addons/sakuragaoka_station/world/houses/gb.gd")


## A rigid placement frame (translation + rotation about Y) bound to a GB. Local +Z is the front.
class Frame extends RefCounted:
	var gb
	var m := Transform3D()
	var ry := 0.0

	func _init(g, mm: Transform3D = Transform3D(), r: float = 0.0) -> void:
		gb = g
		m = mm
		ry = r

	static func at(g, x: float, y: float, z: float, r: float = 0.0) -> Frame:
		return Frame.new(g, Transform3D(Basis(Vector3.UP, r), Vector3(x, y, z)), r)

	func sub(x: float, y: float, z: float, r: float = 0.0) -> Frame:
		return Frame.new(gb, m * Transform3D(Basis(Vector3.UP, r), Vector3(x, y, z)), ry + r)

	## World position of a local point.
	func w(x: float, y: float, z: float) -> Vector3:
		return m * Vector3(x, y, z)

	func origin() -> Vector3:
		return m.origin

	func M(x: float, y: float, z: float, o = null) -> Transform3D:
		var od: Dictionary = o if o is Dictionary else {}
		var e := Vector3(_f(od, "rx"), _f(od, "ry"), _f(od, "rz"))
		var s := Vector3.ONE
		if _f(od, "sx") or _f(od, "sy") or _f(od, "sz"):
			s = Vector3(_f1(od, "sx"), _f1(od, "sy"), _f1(od, "sz"))
		return m * Transform3D(Basis.from_euler(e, EULER_ORDER_YXZ) * Basis.from_scale(s), Vector3(x, y, z))

	static func _f(o: Dictionary, k: String) -> float:
		var v = o.get(k)
		return float(v) if v else 0.0

	static func _f1(o: Dictionary, k: String) -> float:
		var v = o.get(k)
		return float(v) if v else 1.0

	func box(mat, c, bw: float, bh: float, bd: float, x: float, y: float, z: float, o = null) -> void:
		gb.box(mat, c, bw, bh, bd, M(x, y, z, o), o.get("uv") if o is Dictionary else null, o)

	## A box with its bottom at y.
	func boxB(mat, c, bw: float, bh: float, bd: float, x: float, y: float, z: float, o = null) -> void:
		gb.box(mat, c, bw, bh, bd, M(x, y + bh / 2.0, z, o), o.get("uv") if o is Dictionary else null, o)

	func raw(mat, c, R: Dictionary, x: float, y: float, z: float, o = null) -> void:
		gb.raw(mat, c, R.p, R.n, R.u, R.i, M(x, y, z, o), o.get("uvx") if o is Dictionary else null, o, R.c)

	## A cylinder along local Y, centred.
	func cyl(mat, c, r: float, h: float, x: float, y: float, z: float, o: Dictionary = {}) -> void:
		var seg: int = o.seg if o.get("seg") else 8
		var rt: float = o.rTop if o.get("rTop") != null else r
		var open := bool(o.get("open", false))
		var R := GBS.raw_of("cyl|%s|%s|%d|%d" % [rt, r, seg, 1 if open else 0], func(): return Geo.cylinder(rt, r, 1, seg, 1, open))
		var oo := o.duplicate()
		oo["sy"] = h
		gb.raw(mat, c, R.p, R.n, R.u, R.i, M(x, y, z, oo), o.get("uvx"), o)

	## A box spanning point a to point b (local), cross-section w (horizontal) x h.
	func beam(mat, c, a: Array, b: Array, bw: float, bh: float, o: Dictionary = {}) -> void:
		var A := Vector3(a[0], a[1], a[2])
		var B := Vector3(b[0], b[1], b[2])
		var dir := B - A
		var ln := dir.length()
		dir = dir.normalized()
		var side := Vector3.UP.cross(dir)
		if side.length_squared() < 1e-6:
			side = Vector3(1, 0, 0)
		side = side.normalized()
		var nup := dir.cross(side).normalized()
		var mid := (A + B) * 0.5
		var basis := Transform3D(Basis(side, nup, dir), Vector3(mid.x, mid.y + o.get("dy", 0.0), mid.z))
		gb.box(mat, c, bw, bh, ln + o.get("extend", 0.0), m * basis, o.get("uv"), o)


const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")


## A slab (roof plane) from a planar convex top polygon of [x, y, z], pushed down by t.
## uv_top(q) -> Vector2 maps the top face. Returns packed arrays {p, n, u, i}.
static func slab(poly_pts: Array, t: float, uv_top: Callable) -> Dictionary:
	var P := PackedVector3Array()
	var N := PackedVector3Array()
	var U := PackedVector2Array()
	var I := PackedInt32Array()
	var pts := poly_pts
	var n := pts.size()
	var a := _v(pts[0])
	var b := _v(pts[1])
	var c := _v(pts[2])
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.y < 0.0:
		pts = pts.duplicate()
		pts.reverse()
		nrm = -nrm
	var base := 0
	for q in pts:
		P.append(_v(q))
		N.append(nrm)
		U.append(uv_top.call(q))
	for k in range(1, n - 1):
		I.append_array([base, base + k, base + k + 1])
	base = P.size()
	for q in pts:
		P.append(Vector3(q[0], q[1] - t, q[2]))
		N.append(-nrm)
		U.append(Vector2(0.001, 0.001))
	for k in range(1, n - 1):
		I.append_array([base, base + k + 1, base + k])
	var cx := 0.0
	var cz := 0.0
	for q in pts:
		cx += q[0]
		cz += q[2]
	cx /= n
	cz /= n
	for k in n:
		var p0: Array = pts[k]
		var p1: Array = pts[(k + 1) % n]
		var ex: float = p1[0] - p0[0]
		var ez: float = p1[2] - p0[2]
		if Vector2(ex, ez).length() < 1e-5:
			continue
		var sx := ez
		var sz := -ex
		var sl := Vector2(sx, sz).length()
		sx /= sl
		sz /= sl
		var mx: float = (p0[0] + p1[0]) / 2.0 - cx
		var mz: float = (p0[2] + p1[2]) / 2.0 - cz
		if mx * sx + mz * sz < 0.0:
			sx = -sx
			sz = -sz
		base = P.size()
		P.append_array([_v(p0), _v(p1), Vector3(p1[0], p1[1] - t, p1[2]), Vector3(p0[0], p0[1] - t, p0[2])])
		for j in 4:
			N.append(Vector3(sx, 0, sz))
			U.append(Vector2(0.002, 0.002))
		var ay: float = p1[1] - p0[1]
		var by: float = p1[1] - t - p0[1]
		var cxx: float = ay * ez - ez * by
		var czz: float = ex * by - ay * ex
		if cxx * sx + czz * sz > 0.0:
			I.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		else:
			I.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	return {"p": P, "n": N, "u": U, "i": I}


## A flat polygon with a given outward normal, wound to face it.
static func poly(points: Array, normal: Array, uvf = null) -> Dictionary:
	var P := PackedVector3Array()
	var N := PackedVector3Array()
	var U := PackedVector2Array()
	var I := PackedInt32Array()
	var nv := Vector3(normal[0], normal[1], normal[2])
	for q in points:
		P.append(_v(q))
		N.append(nv)
		U.append(uvf.call(q) if uvf != null else Vector2.ZERO)
	var a := _v(points[0])
	var nn := (_v(points[1]) - a).cross(_v(points[2]) - a)
	var ok := nn.dot(nv) >= 0.0
	for k in range(1, points.size() - 1):
		if ok:
			I.append_array([0, k, k + 1])
		else:
			I.append_array([0, k + 1, k])
	return {"p": P, "n": N, "u": U, "i": I}


static func _v(q) -> Vector3:
	return Vector3(q[0], q[1], q[2])
