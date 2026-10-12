# shopsA geometry helpers shared by common.js and goods.js: three.js Path/Shape point sampling
# (lines, quadratic and cubic beziers, arcs) so curved outlines keep the original's vertex counts,
# metre-UV boxes and planes, the (z, y) profile prism, awning scallops, atlas-region planes and the
# welded smooth icosahedron.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")

const JS_EPS := 2.220446049250313e-16


## A three.js Path / Shape built from moveTo / lineTo / quadraticCurveTo / bezierCurveTo / absarc.
## Points are [x, y] float64 pairs, as JS numbers.
class ShapePath extends RefCounted:
	var curves: Array = []
	var cur: Array = [0.0, 0.0]

	static func from_points(pts: Array) -> ShapePath:
		var s := ShapePath.new()
		s.move_to(pts[0][0], pts[0][1])
		for i in range(1, pts.size()):
			s.line_to(pts[i][0], pts[i][1])
		return s

	func move_to(x: float, y: float) -> ShapePath:
		cur = [x, y]
		return self

	func line_to(x: float, y: float) -> ShapePath:
		curves.append(["L", cur.duplicate(), [x, y]])
		cur = [x, y]
		return self

	func quad_to(cx: float, cy: float, x: float, y: float) -> ShapePath:
		curves.append(["Q", cur.duplicate(), [cx, cy], [x, y]])
		cur = [x, y]
		return self

	func bezier_to(c1x: float, c1y: float, c2x: float, c2y: float, x: float, y: float) -> ShapePath:
		curves.append(["C", cur.duplicate(), [c1x, c1y], [c2x, c2y], [x, y]])
		cur = [x, y]
		return self

	func absarc(x: float, y: float, r: float, a0: float, a1: float, cw: bool = false) -> ShapePath:
		var c := ["E", x, y, r, r, a0, a1, cw]
		if not curves.is_empty():
			var fp := point(c, 0.0)
			if not (fp[0] == cur[0] and fp[1] == cur[1]):
				line_to(fp[0], fp[1])
		curves.append(c)
		cur = point(c, 1.0)
		return self

	func close_path() -> ShapePath:
		var s := point(curves[0], 0.0)
		var e := point(curves[curves.size() - 1], 1.0)
		if not (s[0] == e[0] and s[1] == e[1]):
			curves.append(["L", e, s])
		return self

	static func point(c: Array, t: float) -> Array:
		match c[0]:
			"L":
				if t == 1.0:
					return [c[2][0], c[2][1]]
				return [(c[2][0] - c[1][0]) * t + c[1][0], (c[2][1] - c[1][1]) * t + c[1][1]]
			"Q":
				var k := 1.0 - t
				var out := []
				for i in 2:
					out.append(k * k * c[1][i] + 2.0 * (1.0 - t) * t * c[2][i] + t * t * c[3][i])
				return out
			"C":
				var k := 1.0 - t
				var out := []
				for i in 2:
					out.append(k * k * k * c[1][i] + 3.0 * k * k * t * c[2][i] + 3.0 * (1.0 - t) * t * t * c[3][i] + t * t * t * c[4][i])
				return out
			_:
				var two_pi := PI * 2.0
				var da: float = c[6] - c[5]
				var same := absf(da) < JS_EPS
				while da < 0.0:
					da += two_pi
				while da > two_pi:
					da -= two_pi
				if da < JS_EPS:
					da = 0.0 if same else two_pi
				if c[7] == true and not same:
					da = -two_pi if da == two_pi else da - two_pi
				var ang: float = c[5] + t * da
				return [c[1] + c[3] * cos(ang), c[2] + c[4] * sin(ang)]

	## CurvePath.getPoints(divisions): ellipses take 2x divisions, lines 1; consecutive duplicates dropped.
	func get_points(divisions: int = 12) -> Array:
		var pts := []
		var last = null
		for c in curves:
			var res: int = divisions * 2 if c[0] == "E" else (1 if c[0] == "L" else divisions)
			for d in res + 1:
				var p := point(c, float(d) / res)
				if last != null and last[0] == p[0] and last[1] == p[1]:
					continue
				pts.append(p)
				last = p
		return pts


## ExtrudeGeometry(shape, {depth, bevelEnabled: false, curveSegments}).
static func extrude_path(sp: ShapePath, depth: float, curve_segments: int = 12) -> T.Geometry:
	return Geo.extrude_shape(Geo.shape(sp.get_points(curve_segments), []), {"depth": depth, "bevelEnabled": false})


## ShapeGeometry(shape, curveSegments).
static func shape_path_geometry(sp: ShapePath, curve_segments: int = 12) -> T.Geometry:
	return Geo.shape_geometry(Geo.shape(sp.get_points(curve_segments), []), curve_segments)


## BoxGeometry whose UVs are in metres / s (tiling textures keep their scale on any box).
static func uv_box(w: float, h: float, d: float, s: float = 1.0) -> T.Geometry:
	var g := Geo.box(w, h, d)
	var uv: T.Attr = g.attributes.uv
	var dims := [[d, h], [d, h], [w, d], [w, d], [w, h], [w, h]]
	for f in 6:
		for i in 4:
			var j := f * 4 + i
			uv.set_xy(j, uv.get_x(j) * dims[f][0] / s, uv.get_y(j) * dims[f][1] / s)
	return g


static func uv_plane(w: float, h: float, s: float = 1.0) -> T.Geometry:
	var g := Geo.plane(w, h)
	var uv: T.Attr = g.attributes.uv
	for i in uv.count():
		uv.set_xy(i, uv.get_x(i) * w / s, uv.get_y(i) * h / s)
	return g


## Prism from a 2D profile in the (z, y) plane, extruded along x by w (centred).
static func profile_x(pts: Array, w: float) -> T.Geometry:
	var g := Geo.extrude(pts, w)
	g.rotate_y(-PI / 2.0)
	return g


## Row of downward half-discs (awning scallops) along x from 0..w, top edge at y = 0 (+ lip).
static func scallop_geo(w: float, sw: float = 0.16, lip: float = 0.03) -> T.Geometry:
	var n := maxi(1, int(T.js_round(w / sw)))
	var s := w / n
	var r := s / 2.0
	var sh := ShapePath.new()
	sh.move_to(0, lip)
	sh.line_to(0, 0)
	for i in n:
		sh.absarc(i * s + r, 0, r, PI, 2.0 * PI, false)
	sh.line_to(w, lip)
	sh.line_to(0, lip)
	var g := extrude_path(sh, 0.012, 4)
	g.translate(-w / 2.0, 0, -0.006)
	return g


## PlaneGeometry (w x h, facing +Z) showing an atlas region, optionally a sub-rectangle of it (fractions).
static func region_geo(reg: Dictionary, w: float, h: float, sub = null) -> T.Geometry:
	var g := Geo.plane(w, h)
	var uv: T.Attr = g.attributes.uv
	var u0: float = reg.u0
	var u1: float = reg.u1
	var v0: float = reg.v0
	var v1: float = reg.v1
	if sub != null:
		var du := u1 - u0
		var dv := v1 - v0
		u0 = reg.u0 + sub[0] * du
		u1 = reg.u0 + sub[2] * du
		v1 = reg.v1 - sub[1] * dv
		v0 = reg.v1 - sub[3] * dv
	for i in uv.count():
		uv.set_xy(i, u0 + uv.get_x(i) * (u1 - u0), v0 + uv.get_y(i) * (v1 - v0))
	return g


## Icosahedron welded + smooth normals: tiny round things without facet banding.
static func smooth_ico(detail: int = 0) -> T.Geometry:
	var g := Geo.icosahedron(1, detail)
	g.delete_attribute("normal")
	g.delete_attribute("uv")
	g = Geo.merge_vertices(g, 1e-4)
	g.compute_vertex_normals()
	var uv := PackedFloat32Array()
	uv.resize(g.vertex_count() * 2)
	g.set_attribute("uv", T.Attr.new(uv, 2))
	return g


## A JS number as String(x) for the integral and short decimal values used in rng keys.
static func js_str(x) -> String:
	if x is int:
		return str(x)
	var f := float(x)
	if f == floorf(f) and absf(f) < 1e15:
		return str(int(f))
	return str(f)


## Number.prototype.toFixed(2).
static func to_fixed2(x: float) -> String:
	var s := "%.2f" % x
	return "0.00" if s == "-0.00" else s


## A three.js-style object's world matrix after updateWorldMatrix(true, false): parents first.
static func update_world(o) -> Transform3D:
	var chain := []
	var c = o
	while c != null:
		chain.push_front(c)
		c = c.parent()
	var m := Transform3D()
	for n in chain:
		if n.matrix_auto_update:
			n.update_matrix()
		m = m * n.matrix
		n.matrix_world = m
	return o.matrix_world
