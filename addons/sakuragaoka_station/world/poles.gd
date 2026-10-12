# poles.js: utility poles of the town (桜川電力), everything mounted on them, and every street wire:
# 6.6 kV conductors on crossarms, overhead ground wire, low-voltage racks, telecom cables with
# closures, cross-street zigzag spans, service drops (引込線) to the facades, guy wires with guards.
# Publishes ctx.services.poles = {poles: [{x, z, y, top, id}], spans: [{points, kind}], drops} (service-drop
# spans are appended when the shared wire mesh is built, after every module: see section 8).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Acc = preload("res://addons/sakuragaoka_station/world/poles/acc.gd")
const Facade = preload("res://addons/sakuragaoka_station/world/poles/facade.gd")
const Atlas = preload("res://addons/sakuragaoka_station/world/poles/atlas.gd")

const UP := Vector3(0, 1, 0)
const HALF := PI / 2.0

static func angd(a: float, b: float) -> float:
	var d := fmod(a - b, TAU)
	if d > PI:
		d -= TAU
	if d < -PI:
		d += TAU
	return absf(d)


static func clamp_(v: float, a: float, b: float) -> float:
	return minf(b, maxf(a, v))


static func _v3(a) -> Vector3:
	return a if a is Vector3 else Vector3(a[0], a[1], a[2])


# ---------------------------------------------------------------- shared unit geometries
const LP := {  # lathe profiles (radius, y) bottom -> top
	"pin": [[0.0, 0], [0.03, 0], [0.03, 0.018], [0.074, 0.046], [0.036, 0.063], [0.06, 0.095], [0.031, 0.11], [0.034, 0.14], [0.0, 0.157]],
	"spool": [[0, 0], [0.037, 0], [0.043, 0.008], [0.03, 0.022], [0.028, 0.04], [0.03, 0.054], [0.043, 0.068], [0.037, 0.076], [0, 0.076]],
	"bush": [[0, 0], [0.03, 0], [0.032, 0.02], [0.05, 0.03], [0.028, 0.045], [0.043, 0.06], [0.024, 0.075], [0.03, 0.09], [0.012, 0.1], [0, 0.1]],
}


class G extends RefCounted:
	var _gc := {}

	func cache(k: String, f: Callable) -> T.Geometry:
		if not _gc.has(k):
			_gc[k] = f.call()
		return _gc[k]

	func box() -> T.Geometry:
		return cache("box", func(): return Geo.box(1, 1, 1))

	func cyl(s: int) -> T.Geometry:
		return cache("c%d" % s, func(): return Geo.cylinder(0.5, 0.5, 1, s, 1, false))

	func cylO(s: int) -> T.Geometry:
		return cache("co%d" % s, func(): return Geo.cylinder(0.5, 0.5, 1, s, 1, true))

	func sph(s: int) -> T.Geometry:
		return cache("s%d" % s, func(): return Geo.sphere(0.5, s, maxi(4, int(T.js_round(s * 0.6)))))

	func plane() -> T.Geometry:
		return cache("pl", func(): return Geo.plane(1, 1))

	func rbox() -> T.Geometry:
		return cache("rb", func(): return Geo.rounded_box(1, 1, 1, 2, 0.18))

	func torus() -> T.Geometry:
		return cache("tor", func(): return Geo.torus(0.3, 0.016, 5, 22))

	func lathe(n: String, s: int = 10) -> T.Geometry:
		return cache("l%s%d" % [n, s], func():
			var pts := []
			for p in LP[n]:
				pts.append(Vector2(p[0], p[1]))
			return Geo.lathe(pts, s))

	func diamond() -> T.Geometry:
		return cache("dia", func():
			var g := T.Geometry.new()
			g.set_attribute("position", T.Attr.new(PackedFloat32Array([0, 0.5, 0, 0.5, 0, 0, 0, -0.5, 0, -0.5, 0, 0]), 3))
			g.set_attribute("normal", T.Attr.new(PackedFloat32Array([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]), 3))
			g.set_attribute("uv", T.Attr.new(PackedFloat32Array([0.5, 1, 1, 0.5, 0.5, 0, 0, 0.5]), 2))
			g.set_index([0, 3, 2, 0, 2, 1])
			return g)


# sticker / sign physical sizes (m)
const STK := {
	"mascot0": [0.13, 0.13], "mascot1": [0.13, 0.13], "mascot2": [0.13, 0.13], "camera": [0.16, 0.12], "suido": [0.16, 0.08],
	"harigami": [0.07, 0.175], "poisute": [0.1, 0.133], "hittakuri": [0.1, 0.133], "tako": [0.1, 0.15], "scrap": [0.07, 0.07],
	"scrap2": [0.07, 0.07], "dog": [0.1, 0.1], "kodomo": [0.1, 0.133],
}
const SIGN := {"diamond": [0.5, 0.5], "aux": [0.42, 0.14], "station": [0.5, 0.19], "hydrant": [0.26, 0.43]}
const COMPASS := {"S": 0.0, "SE": PI / 4, "E": HALF, "NE": 3 * PI / 4, "N": PI, "NW": -3 * PI / 4, "W": -HALF, "SW": -PI / 4}

# per-pole features (see docs/SPEC). ad: [adIndex, face], st: [[sticker, face, y]], sign: [[type, face, y]]
const FEAT := {
	"W0": {"tr": 1, "cam": "N", "ad": [0, "S"], "st": [["mascot0", "SE", 1.5], ["poisute", "NW", 1.3], ["scrap", "N", 1.72]]},
	"W1": {"sw": 1, "ad": [1, "S"], "st": [["harigami", "NE", 1.35], ["mascot1", "SW", 1.55], ["dog", "N", 1.1]]},
	"W2": {"tr": 2, "ad": [2, "S"], "st": [["suido", "SE", 1.62], ["scrap2", "W", 1.4], ["hittakuri", "N", 1.45]]},
	"W3": {"ad": [3, "S"], "sign": [["hydrant", "road", 2.74]], "st": [["kodomo", "SW", 1.45], ["scrap", "E", 1.2]]},
	"W4": {"tr": 1, "ad": [4, "S"], "st": [["mascot2", "SE", 1.5], ["dog", "NW", 1.15]]},
	"E0": {"sign": [["diamond", "S", 3.03], ["aux", "S", 2.58]], "ad": [5, "N"], "st": [["mascot0", "SW", 1.52], ["scrap2", "NW", 1.35], ["poisute", "SE", 1.22]]},
	"E1": {"tr": 1, "ad": [6, "S"], "sign": [["hydrant", "road", 2.74]], "st": [["poisute", "SE", 1.35], ["harigami", "N", 1.4]]},
	"E2": {"ad": [7, "S"], "st": [["mascot1", "SW", 1.5], ["suido", "NE", 1.58]]},
	"E3": {"tr": 2, "ad": [8, "S"], "st": [["hittakuri", "SE", 1.45], ["dog", "W", 1.12], ["scrap", "N", 1.6]]},
	"S-26": {"ad": [9, "E"], "st": [["mascot2", "SE", 1.5], ["poisute", "NE", 1.3]]},
	"S-52": {"tr": 1, "ad": [10, "E"], "st": [["suido", "S", 1.58], ["scrap", "W", 1.3]]},
	"S-78": {"sw": 1, "st": [["harigami", "E", 1.4], ["dog", "S", 1.12]]},
	"S22": {"tr": 1, "ad": [11, "W"], "st": [["mascot0", "SW", 1.52], ["hittakuri", "S", 1.35], ["scrap2", "E", 1.62]]},
	"S46": {"ad": [0, "W"], "st": [["poisute", "SW", 1.3], ["kodomo", "S", 1.5]]},
	"S72": {"tr": 1, "st": [["dog", "W", 1.15], ["suido", "S", 1.58]]},
	"K0": {"cam": "N", "telHigh": 1, "sign": [["station", "S", 2.64]], "ad": [2, "N"], "st": [["camera", "S", 1.62], ["mascot1", "E", 1.45]]},
	"K1": {"telHigh": 1, "ad": [4, "S"], "st": [["tako", "E", 1.45], ["harigami", "N", 1.35]]},
	"K2": {"tr": 1, "st": [["tako", "S", 1.45], ["mascot2", "E", 1.5]]},
	"N0": {"st": [["scrap", "N", 1.4]]},
	"N1": {"st": [["poisute", "N", 1.3], ["kodomo", "W", 1.5]]},
	"N2": {"ad": [5, "E"], "st": [["mascot0", "NE", 1.5], ["hittakuri", "N", 1.35]]},
	"N3": {"st": [["dog", "N", 1.12], ["scrap2", "E", 1.5]]},
	"N4": {"st": [["suido", "N", 1.58]]},
	"N5": {"st": [["harigami", "N", 1.4]]},
	"A0": {"tr": 1, "st": [["tako", "N", 1.45]]},
	"A1": {"st": [["mascot1", "N", 1.5], ["dog", "E", 1.12]]},
	"A2": {"tr": 1, "ad": [9, "W"], "st": [["tako", "NE", 1.45], ["scrap", "S", 1.4]]},
	"A3": {"ad": [7, "E"], "st": [["kodomo", "N", 1.5]]},
	"A4": {"st": [["tako", "N", 1.45], ["poisute", "W", 1.3]]},
}

const EULER := {"XYZ": EULER_ORDER_XYZ, "XZY": EULER_ORDER_XZY, "YXZ": EULER_ORDER_YXZ, "YZX": EULER_ORDER_YZX, "ZXY": EULER_ORDER_ZXY, "ZYX": EULER_ORDER_ZYX}


# ---------------------------------------------------------------- 5. kit
class Kit extends RefCounted:
	var acc
	var g: G

	func _init(a, gc: G) -> void:
		acc = a
		g = gc

	static func _v3(v) -> Vector3:
		return v if v is Vector3 else Vector3(v[0], v[1], v[2])

	static func M(pos, rot = null, scl = null) -> Transform3D:
		var b := Basis()
		if rot != null:
			var order: String = rot[3] if rot.size() > 3 and rot[3] else "XYZ"
			b = Basis.from_euler(Vector3(rot[0], rot[1], rot[2]), EULER[order])
		var s := Vector3(scl[0], scl[1], scl[2]) if scl != null else Vector3.ONE
		return Transform3D(b * Basis.from_scale(s), _v3(pos))

	static func rodM(p0, p1, sx: float, sz: float) -> Transform3D:
		var a := _v3(p0)
		var b := _v3(p1)
		var d := b - a
		var l := d.length()
		if l == 0.0:
			l = 1e-4
		var q := T.quat_from_unit_vectors(UP, d * (1.0 / l))
		return T.compose((a + b) / 2.0, q, Vector3(sx, l, sz))

	func geo(gg: T.Geometry, m = null, col = null, uv = null):
		return acc.add(gg, m if m != null else Transform3D(), col, uv)

	func box(w: float, h: float, dd: float, pos, col, rot = null):
		return acc.add(g.box(), M(pos, rot, [w, h, dd]), col)

	func cyl(r: float, h: float, pos, col, seg: int = 8, rot = null):
		return acc.add(g.cyl(seg), M(pos, rot, [r * 2, h, r * 2]), col)

	func cylO(r: float, h: float, pos, col, seg: int = 8, rot = null):
		return acc.add(g.cylO(seg), M(pos, rot, [r * 2, h, r * 2]), col)

	func sph(r: float, pos, col, seg: int = 8, scl = [1, 1, 1], rot = null):
		return acc.add(g.sph(seg), M(pos, rot, [r * 2 * scl[0], r * 2 * scl[1], r * 2 * scl[2]]), col)

	func lathe(n: String, pos, col, sc: float = 1.0, rot = null, seg: int = 10):
		return acc.add(g.lathe(n, seg), M(pos, rot, [sc, sc, sc]), col)

	func rodC(p0, p1, r: float, col, seg: int = 6):
		return acc.add(g.cyl(seg), rodM(p0, p1, r * 2, r * 2), col)

	func rodB(p0, p1, w: float, t: float, col):
		return acc.add(g.box(), rodM(p0, p1, w, t), col)


## TubeGeometry(new QuadraticBezierCurve3(v0, v1, v2), tubular, radius, radial, closed): Curve's
## arc-length getPointAt and finite-difference tangents, as Geo.tube_catmull does for its curve.
static func tube_quadratic(v0: Vector3, v1: Vector3, v2: Vector3, tubular: int, radius: float, radial: int, closed: bool) -> T.Geometry:
	var get_point := func(t: float) -> Vector3:
		var k := 1.0 - t
		return v0 * (k * k) + v1 * (2.0 * k * t) + v2 * (t * t)
	var lengths := PackedFloat64Array([0.0])
	var last: Vector3 = get_point.call(0.0)
	var sum := 0.0
	for p in range(1, 201):
		var cur: Vector3 = get_point.call(float(p) / 200)
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
		var sg := lengths[i + 1] - lengths[i]
		return (i + (target - lengths[i]) / sg) / (il - 1)
	var tangent_at := func(u: float) -> Vector3:
		var t: float = u_to_t.call(u)
		var t1 := maxf(t - 0.0001, 0.0)
		var t2 := minf(t + 0.0001, 1.0)
		return ((get_point.call(t2) as Vector3) - (get_point.call(t1) as Vector3)).normalized()
	var tangents := []
	for i in tubular + 1:
		tangents.append(tangent_at.call(float(i) / tubular))
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
	if closed:
		var theta := acos(clampf((normals[0] as Vector3).dot(normals[tubular]), -1.0, 1.0)) / tubular
		if (tangents[0] as Vector3).dot((normals[0] as Vector3).cross(normals[tubular])) > 0.0:
			theta = -theta
		for i in range(1, tubular + 1):
			normals[i] = Basis(tangents[i], theta * i) * (normals[i] as Vector3)
			binormals[i] = (tangents[i] as Vector3).cross(normals[i])
	var pos := PackedFloat32Array()
	var nor := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var idx := PackedInt32Array()
	var segs := range(tubular)
	segs.append(tubular if not closed else 0)
	for i in segs:
		var P: Vector3 = get_point.call(u_to_t.call(float(i) / tubular))
		var N: Vector3 = normals[i]
		var B: Vector3 = binormals[i]
		for j in radial + 1:
			var v := float(j) / radial * TAU
			var s := sin(v)
			var c := -cos(v)
			var n := (c * N + s * B).normalized()
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
	return Geo._make(idx, pos, nor, uv)


# ---------------------------------------------------------------- build state
var ctx
var L
var R
var GC := G.new()
var COL := {}
var UV := {}
var WHITE_UV: Array
var poles: Array = []
var by_id := {}
var SP: Array = []
var spans: Array = []
var tel_spans: Array = []
var drop_reqs: Array = []
var mA
var mB
var mL
var WS := {}

var _cc := {}


func C(h: String) -> Color:
	if not _cc.has(h):
		_cc[h] = T.color(h)
	return _cc[h]


func height_at(x: float, z: float) -> float:
	return L.height_at(x, z)


## Returns null, or the error that stopped the build (as the original throws).
func build(c):
	ctx = c
	L = ctx.L
	var mat = ctx.mat
	R = ctx.rng("poles:v1")
	WHITE_UV = Atlas.white_uv()
	COL = {
		"cap": C("#b3b2ab"), "steel": C("#a1a8ae"), "steelLight": C("#b9bec2"), "steelDark": C("#7d848b"), "porcelain": C("#e9e6df"),
		"porcelainGrey": C("#cdd1d1"), "black": C("#48454f"), "closure": C("#4a4751"), "trans": C("#c5cacd"), "transDark": C("#a7adb1"),
		"lampArm": C("#c9ccc9"), "lampHousing": C("#dcdfdc"), "camera": C("#e7e5df"), "lens": C("#3a3346"), "yellow": C("#eec13a"),
		"yellowDark": C("#c99a26"), "boxGrey": C("#aab1b5"), "boxGreyDark": C("#949ba0"), "cutout": C("#dfddd6"), "conduit": C("#b4b6b2"),
		"anchor": C("#b8b5ad"), "signBack": C("#b7bcc0"), "termBox": C("#5a5761"), "termBoxDark": C("#4a4751"), "telCable": C("#3e3b45"),
		"guard": C("#efc33c"), "guardBand": C("#3e3a46"),
	}
	UV = {"shaft": Atlas.uv_of(Atlas.RA.shaft), "sleeve": Atlas.uv_of(Atlas.RA.sleeve), "cover": Atlas.uv_of(Atlas.RA.cover), "trans": Atlas.uv_of(Atlas.RA.trans)}

	# ================================================================ 1. poles
	var PR: Dictionary = L.POLE_RUNS
	var R1WH := [12, 11.5, 12, 11.5, 12]
	var R1EH := [11.5, 12, 11.5, 12]
	for i in PR.R1W.size():
		var q: Dictionary = PR.R1W[i]
		mk("W%d" % i, q.x, q.z, {"run": "R1W", "H": float(R1WH[i]) if i < R1WH.size() else 12.0, "road": [1, 0], "gw": true, "plate": {"line": "桜ヶ丘幹", "num": 12 + i}})
	for i in PR.R1E.size():
		var q: Dictionary = PR.R1E[i]
		mk("E%d" % i, q.x, q.z, {"run": "R1E", "H": float(R1EH[i]) if i < R1EH.size() else 12.0, "road": [-1, 0], "gw": true, "plate": {"line": "駅前支", "num": 1 + i}})
	var r3w: Array = T.stable_sort(PR.R3S.filter(func(q): return q.x < 0), func(a, b): return b.x - a.x)
	var r3e: Array = T.stable_sort(PR.R3S.filter(func(q): return q.x >= 0), func(a, b): return a.x - b.x)
	for i in r3w.size():
		var q: Dictionary = r3w[i]
		mk("S" + _num(q.x), q.x, q.z, {"run": "R3S", "road": [0, -1], "gw": true, "plate": {"line": "桜ヶ丘幹", "num": 11 - i}})
	for i in r3e.size():
		var q: Dictionary = r3e[i]
		mk("S" + _num(q.x), q.x, q.z, {"run": "R3S", "road": [0, -1], "gw": true, "plate": {"line": "東町支", "num": 1 + i}})
	for i in PR.R2W.size():
		var q: Dictionary = PR.R2W[i]
		mk("K%d" % i, q.x, q.z, {"run": "R2W", "road": [1, 0], "gw": i > 0, "plate": {"line": "踏切支", "num": 1 + i}})
	for i in PR.R4S.size():
		var q: Dictionary = PR.R4S[i]
		mk("N%d" % i, q.x, q.z, {"run": "R4S", "cls": "low", "H": 8.5, "road": [0, -1], "plate": {"line": "線路北", "num": 1 + i}})
	for i in PR.R6S.size():
		var q: Dictionary = PR.R6S[i]
		mk("A%d" % i, q.x, q.z, {"run": "R6S", "cls": "alley", "H": 10.5, "road": [0, -1], "plate": {"line": "北町支", "num": 1 + i}})
	# extensions beyond the play area + far-town lines (simplified)
	far("XW1", -104, 1.45, {"road": [0, -1]}); far("XE1", 98, 1.45, {"road": [0, -1]})
	var FZ := [-31.55, 1.45, 34.45, 67.45, 100.45, 133.45, 166.45]
	for i in FZ.size():
		far("FW%d" % i, -134, FZ[i], {"road": [1, 0]})
		far("FE%d" % i, 128, FZ[i], {"road": [-1, 0]})
	far("XN0", -106, -53.05, {"cls": "low", "H": 8.5, "road": [0, -1], "f": {}}); far("XN1", -134, -53.05, {"cls": "low", "H": 8.5, "road": [0, -1], "f": {}})
	far("XN2", 106, -53.05, {"cls": "low", "H": 8.5, "road": [0, -1], "f": {}}); far("XN3", 134, -53.05, {"cls": "low", "H": 8.5, "road": [0, -1], "f": {}})
	far("XA0", -91, -69.1, {"cls": "alley", "H": 10.5, "road": [0, -1]}); far("XA1", -120, -69.1, {"cls": "alley", "H": 10.5, "road": [0, -1]})
	far("XA2", 93, -69.1, {"cls": "alley", "H": 10.5, "road": [0, -1]}); far("XA3", 122, -69.1, {"cls": "alley", "H": 10.5, "road": [0, -1]})
	far("XS0", L.street_center_x(154) - 3.45, 154, {"road": [1, 0]})
	far("XS1", L.street_center_x(141) + 3.45, 141, {"road": [-1, 0]})

	# ================================================================ 2. span topology
	var MAIN := ["hv", "gw", "lv", "tel"]
	var ALLEY := ["hv", "lv", "tel"]
	var LOW := ["lv", "tel"]
	var FAR := ["hv", "lv", "tel1"]
	chain(["W0", "W1", "W2", "W3", "W4", "XS0"], MAIN)
	chain(["E0", "E1", "E2", "E3", "XS1"], MAIN)
	chain(["S-26", "S-52", "S-78", "XW1"], MAIN)
	chain(["S22", "S46", "S72", "XE1"], MAIN)
	link("XW1", "FW1", FAR); link("XE1", "FE1", FAR)
	var fw := []
	var fe := []
	for i in FZ.size():
		fw.append("FW%d" % i)
		fe.append("FE%d" % i)
	chain(fw, FAR); chain(fe, FAR)
	link("K0", "K1", ["telHigh"], true)  # the one span crossing the rail corridor: telecom only, y >= 9
	chain(["K1", "K2"], MAIN)
	chain(["XN1", "XN0", "N0", "N1", "N2", "N3", "N4", "N5", "XN2", "XN3"], LOW)  # along the tracks: wires < 7 m
	chain(["XA1", "XA0", "A0", "A1", "A2", "A3", "A4", "XA2", "XA3"], ALLEY)
	link("W0", "S-26", ["hv", "lv", "tel"])  # junction pole at the station-front crossroads
	link("W0", "S22", ["hv", "lv", "tel"])
	link("S-26", "K0", ["hv", "lv", "tel1"])
	link("K1", "N2", ["tel1"])
	link("K2", "A1", ["hv", "lv", "tel"])
	# main street zigzag: LV + telecom criss-cross over the street (the iconic view from the hero camera)
	var ZZ := ["W0", "E0", "W1", "E1", "W2", "E2", "W3", "E3", "W4"]
	for i in ZZ.size() - 1:
		link(ZZ[i], ZZ[i + 1], ["lv", "tel2"] if i < 2 else ["lv2", "tel1"])

	# ================================================================ 3. frames (local +X = run direction, +Z = road side)
	for p in poles:
		var rd = null
		for s in SP:
			if not s.run or (not is_same(s.A, p) and not is_same(s.B, p)):
				continue
			var o: Dictionary = s.B if is_same(s.A, p) else s.A
			var d := unit2(o.x - p.x, o.z - p.z)
			if rd == null:
				rd = d
			else:
				if d[0] * rd[0] + d[1] * rd[1] < 0:
					d = [-d[0], -d[1]]
				rd = [rd[0] + d[0], rd[1] + d[1]]
		if rd == null:
			var fs = null
			for s in SP:
				if is_same(s.A, p) or is_same(s.B, p):
					fs = s
					break
			var o: Dictionary = ((fs.B if is_same(fs.A, p) else fs.A) if fs != null else {"x": p.x, "z": p.z - 1})
			rd = [o.x - p.x, o.z - p.z]
		rd = unit2(rd[0], rd[1])
		var zx: float = p.road[0]
		var zz: float = p.road[1]
		var dt: float = zx * rd[0] + zz * rd[1]
		zx -= dt * rd[0]
		zz -= dt * rd[1]
		if Vector2(zx, zz).length() < 0.2:
			zx = -rd[1]
			zz = rd[0]
		var u := unit2(zx, zz)
		zx = u[0]
		zz = u[1]
		p.rotY = atan2(zx, zz)
		p.hs = heights(p)
		# HV arms
		p.arms = []
		if p.hs.arm != null:
			var hv := []
			for s in SP:
				if s.tiers.has("hv") and (is_same(s.A, p) or is_same(s.B, p)):
					var o: Dictionary = s.B if is_same(s.A, p) else s.A
					var d := to_local(p, o.x - p.x, o.z - p.z)
					hv.append({"psi": atan2(d[0], d[1]), "run": s.run})
			if not hv.is_empty():
				p.arms.append({"psi": HALF if hv.any(func(h): return h.run) else hv[0].psi})
				for h in hv:
					if p.arms.size() < 2 and not p.arms.any(func(a): return absf(cos(h.psi - a.psi)) > cos(35 * PI / 180)):
						p.arms.append({"psi": h.psi})

	# ================================================================ 4. atlases & materials
	var plates := []
	var tel_plates := []
	for p in poles:
		if p.detail == "full":
			p.plateIdx = plates.size()
			var sub := ""
			if R.f() < 0.4:
				sub = ("左" if R.f() < 0.5 else "右") + str(1 + int(R.f() * 3))
			plates.append({"line": p.plate.line, "num": p.plate.num, "sub": sub})
	for i in 15:
		tel_plates.append({"line": ["桜ヶ丘", "駅前", "北町", "東町", "川原"][i % 5], "num": str(101 + i * 7)})
	var atlas: Dictionary = Atlas.make_atlases(ctx, plates, tel_plates)
	mA = mat.toon("#ffffff", {"map": atlas.A, "vertexColors": true, "paint": 0.05})
	mB = mat.toon("#ffffff", {"map": atlas.B, "vertexColors": true, "alphaTest": 0.5, "paint": 0.02, "polygonOffset": -1})
	mL = mat.emissive("#e9ece8", 0.92)

	# ================================================================ 6. pole geometry
	for p in poles:
		build_pole(p)

	# ================================================================ 7. wires
	WS = {
		"hv": {"w": 0.02, "c": "#565b64"}, "gw": {"w": 0.012, "c": "#6d737b"}, "lv": {"w": 0.026, "c": "#403c47"},
		"tel": [{"w": 0.046, "c": "#37343e"}, {"w": 0.034, "c": "#3d3a44"}, {"w": 0.029, "c": "#34313b"}],
		"telHigh": {"w": 0.038, "c": "#37343e"}, "dropP": {"w": 0.017, "c": "#433f4a"}, "dropT": {"w": 0.012, "c": "#4f4b57"},
		"jump": {"w": 0.012, "c": "#50545c"}, "jumpLV": {"w": 0.016, "c": "#403c47"}, "guy": {"w": 0.014, "c": "#7a8088"},
	}
	for s in SP:
		var A: Dictionary = s.A
		var B: Dictionary = s.B
		var dW := Vector3(B.x - A.x, 0, B.z - A.z)
		var Ls := dW.length()
		dW = dW.normalized()
		for t in s.tiers:
			var pa: Array = []
			var pb: Array = []
			if t == "hv":
				pa = hv_at(A, dW) if not A.arms.is_empty() else []
				pb = hv_at(B, dW) if not B.arms.is_empty() else []
			elif t == "gw":
				pa = [A.gwPt] if A.get("gwPt") != null else []
				pb = [B.gwPt] if B.get("gwPt") != null else []
			elif t == "lv" or t == "lv2":
				var n := 3 if t == "lv" else 2
				pa = A.lvPts.slice(0, n)
				pb = B.lvPts.slice(0, n)
			elif t == "tel" or t == "tel2" or t == "tel1":
				var n := 4 if t == "tel" else (2 if t == "tel2" else 1)
				pa = A.telPts.slice(0, n)
				pb = B.telPts.slice(0, n)
			elif t == "telHigh":
				pa = [A.telHighPt] if A.get("telHighPt") != null else []
				pb = [B.telHighPt] if B.get("telHighPt") != null else []
			var n := mini(pa.size(), pb.size())
			for i in n:
				var jit: float = 0.9 + R.f() * 0.2
				if t == "hv":
					hang(pa[i], pb[i], (0.011 * Ls + 0.12) * jit, WS.hv, "hv")
				elif t == "gw":
					hang(pa[i], pb[i], (0.009 * Ls + 0.06) * jit, WS.gw, "gw")
				elif t[0] == "l":
					hang(pa[i], pb[i], (0.016 * Ls + 0.15) * jit * (1 + i * 0.05), WS.lv, "lv")
				elif t == "telHigh":
					hang(pa[i], pb[i], 1.0, WS.telHigh, "tel")
				else:
					var sag: float = (0.024 * Ls + 0.2) * jit * [1, 1.12, 0.94][i]
					var pts := hang(pa[i], pb[i], sag, WS.tel[i] if i < WS.tel.size() else WS.tel[0], "tel")
					if i == 0:
						tel_spans.append({"A": A, "B": B, "a": pa[i], "b": pb[i], "sag": sag, "pts": pts, "Ls": Ls})

	# jumpers on the poles (HV -> cut-outs -> transformer -> LV rack; switch bushings; lamp feed; drop spool)
	for p in poles:
		var hv = p.arms[0].pts if not p.arms.is_empty() else null
		if p.get("trInfo") != null and hv != null:
			var cans: Array = p.trInfo.cans
			var cut_top: Array = p.trInfo.cutTop
			var cut_bot: Array = p.trInfo.cutBot
			for i in cut_top.size():
				hang(hv[mini(i, hv.size() - 1)], cut_top[i], 0.06, WS.jump, "jump", 6)
			for i in cut_bot.size():
				var can: Dictionary = cans[i % cans.size()]
				hang(cut_bot[i], can.hvB[i % can.hvB.size()], 0.1, WS.jump, "jump", 6)
			for can in cans:
				for i in can.lvB.size():
					hang(can.lvB[i], p.lvPts[i % p.lvPts.size()], 0.14, WS.jumpLV, "jump", 6)
		if p.get("swInfo") != null and hv != null:
			for i in p.swInfo.bushPts.size():
				hang(p.swInfo.bushPts[i], hv[(i >> 1) % hv.size()], 0.07, WS.jump, "jump", 6)
		if p.get("lampFeed") != null:
			hang(p.lampFeed, p.lvPts[p.lvPts.size() - 1], 0.04, WS.jump, "jump", 5)
		if p.get("lvDropJ") != null:
			ctx.wires.add(Geo.catenary(p.lvDropJ[0], p.lvDropJ[1], 0.03, 4) + Geo.catenary(p.lvDropJ[1], p.lvDropJ[2], 0.03, 4).slice(1), {"width": WS.jumpLV.w, "color": WS.jumpLV.c})

	# telecom closures (クロージャー) hanging on the cables near the poles
	for ts in tel_spans:
		if ts.Ls < 10:
			continue
		var pairs := [[0.1 + R.f() * 0.07, ts.A], [0.9 - R.f() * 0.07, ts.B]]
		for pr_ in pairs:
			var t: float = pr_[0]
			var pr: Dictionary = pr_[1]
			if pr.detail == "far" or R.f() > 0.55:
				continue
			var a: Vector3 = ts.a
			var b: Vector3 = ts.b
			var P := a.lerp(b, t)
			P.y -= ts.sag * 4 * t * (1 - t)
			var Tg := b - a
			Tg.y -= ts.sag * 4 * (1 - 2 * t)
			Tg = Tg.normalized()
			closure(pr.kW, P, Tg)

	# ================================================================ 8. service drops (引込線) to facades
	# Drops are requested here and realised just before the shared wire mesh is generated, i.e. after every
	# module has been built: each one is snapped onto the real facade found by a short ray cast into the lot
	# (houses sit 1.7–6 m behind the frontage). Nothing else in the scene -> contract point (lz -1.5, y +5.3).
	var main_poles := poles.filter(func(p): return p.get("run") == "R1W" or p.get("run") == "R1E")
	var LOT_DROPS := ["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8", "W9", "W10", "W11", "W12", "W13", "E1", "E2", "E3", "E4", "E5", "E7", "E8", "E9", "E10", "E11", "E12", "E13"]
	for id in LOT_DROPS:
		var lot = L.lot_by_id(id)
		if lot == null:
			continue
		var fr: Dictionary = L.lot_frame(lot)
		var c_ := cos(fr.rotY)
		var s_ := sin(fr.rotY)
		var best = null
		for p in main_poles:
			var dx: float = p.x - fr.x
			var dz: float = p.z - fr.z
			var lx := clamp_(dx * c_ - dz * s_, -fr.w / 3.0, fr.w / 3.0)
			var wp: Dictionary = L.lot_to_world(lot, lx, -1.5)
			var same: bool = (lot.side < 0) == (p.run == "R1W")
			var d: float = Vector2(wp.x - p.x, wp.z - p.z).length() + (0.0 if same else 4.0)
			if best == null or d < best.d:
				best = {"d": d, "p": p, "lx": lx, "wp": wp}
		if best == null or best.d > 26:
			continue
		var o: Dictionary = L.lot_to_world(lot, best.lx, 0)
		var lxT := clamp_(best.lx + (-0.5 if best.lx > 0 else 0.5), -fr.w / 2.0 + 0.4, fr.w / 2.0 - 0.4)
		drop_reqs.append({
			"p": best.p, "O": Vector3(o.x, 0, o.z), "n": Vector3(s_, 0, c_), "lat": Vector3(c_, 0, -s_), "maxD": 12.0, "telShift": lxT - best.lx,
			"def": Vector3(best.wp.x, height_at(best.wp.x, best.wp.z) + 5.3, best.wp.z), "withTel": R.f() < 0.8,
		})
	# residential blocks: points 1.5 m inside the front edges, [pole, x, z, nx, nz]
	var BLK := [
		["S-52", -56, -7.3, 0, 1], ["S-52", -47, -7.3, 0, 1], ["S-26", -30, -7.3, 0, 1], ["S-26", -21.5, -7.3, 0, 1], ["S-78", -61, -7.3, 0, 1],
		["K0", -17.0, -15.5, 1, 0], ["K0", -17.0, -24, 1, 0],
		["S22", 29.5, -7.3, 0, 1], ["S46", 41, -7.3, 0, 1], ["S46", 51, -7.3, 0, 1], ["S72", 60, -7.3, 0, 1],
		["N0", -81, -59.4, 0, 1], ["N0", -73, -59.4, 0, 1], ["N1", -52, -59.4, 0, 1], ["N1", -43, -59.4, 0, 1], ["N2", -25, -59.4, 0, 1], ["K1", -17.0, -63.5, 1, 0],
		["N3", 13, -59.4, 0, 1], ["N3", 23, -59.4, 0, 1], ["N4", 43, -59.4, 0, 1], ["N4", 53, -59.4, 0, 1], ["N5", 73, -59.4, 0, 1], ["N5", 82, -59.4, 0, 1],
		["A0", -66, -74.2, 0, 1], ["A0", -57, -74.2, 0, 1], ["A1", -36, -74.2, 0, 1], ["A1", -27, -74.2, 0, 1], ["K2", -17.0, -77, 1, 0],
		["A2", -1, -74.2, 0, 1], ["A2", 9, -74.2, 0, 1], ["A3", 29, -74.2, 0, 1], ["A3", 39, -74.2, 0, 1], ["A4", 59, -74.2, 0, 1], ["A4", 69, -74.2, 0, 1],
		["S-26", -24, 4.1, 0, -1], ["S-52", -49, 4.1, 0, -1], ["S22", 24.5, 4.1, 0, -1], ["S46", 47, 4.1, 0, -1],
	]
	for e in BLK:
		var p = by_id.get(e[0])
		if p == null:
			continue
		var x: float = e[1]
		var z: float = e[2]
		var nx: float = e[3]
		var nz: float = e[4]
		drop_reqs.append({
			"p": p, "O": Vector3(x + nx * 1.5, 0, z + nz * 1.5), "n": Vector3(nx, 0, nz), "lat": Vector3(nz, 0, -nx), "maxD": 10.0, "telShift": 0.5,
			"def": Vector3(x, height_at(x, z) + 5.3, z), "withTel": R.f() < 0.55,
		})
	# The port's ctx.wires has no build(): the wire-mesh builder runs the "before_build" hooks first.
	var hooks: Array = ctx.wires.get_meta("before_build", [])
	hooks.append(func(): finalize_drops())
	ctx.wires.set_meta("before_build", hooks)

	# ================================================================ 9. guy wires (支線) with yellow guards
	var TW := {"hv": 1.0, "gw": 0.3, "lv": 0.6, "lv2": 0.45, "tel": 0.6, "tel2": 0.45, "tel1": 0.3, "telHigh": 0.4}
	for p in poles:
		var vx := 0.0
		var vz := 0.0
		for s in SP:
			if not is_same(s.A, p) and not is_same(s.B, p):
				continue
			var o: Dictionary = s.B if is_same(s.A, p) else s.A
			var u := unit2(o.x - p.x, o.z - p.z)
			var w := 0.0
			for t in s.tiers:
				w += TW.get(t, 0.0)
			vx += u[0] * w
			vz += u[1] * w
		if Vector2(vx, vz).length() < 1.15:
			continue
		var base := atan2(-vx, -vz)
		for da in [0, 0.35, -0.35, 0.7, -0.7, 1.05, -1.05, 1.4, -1.4]:
			var ang: float = base + da
			var dx := sin(ang)
			var dz := cos(ang)
			var D: float = 0.3 * p.H
			var ax: float = p.x + dx * D
			var az: float = p.z + dz * D
			if not free_ground(ax, az):
				continue
			build_guy(p, dx, dz, ax, az)
			break

	# ================================================================ 10. meshes, colliders, services
	var root := T.Group.new()
	root.name = "poles"
	for p in poles:
		put(root, p, p.acc.A, mA, true)
		put(root, p, p.acc.W, mA, true)
		put(root, p, p.acc.B, mB, false)
		put(root, p, p.acc.L, mL, false)
		physics(p.x, p.z, r_at(p, 0) + (0.04 if p.hasCover else 0.02), p.y - 1, p.y + p.H)
	ctx.add_static(root)
	var out_poles := []
	for p in poles:
		out_poles.append({"x": p.x, "z": p.z, "y": p.y, "top": p.y + p.H, "id": p.id})
	var out_spans := []
	for s in spans:
		if s.kind != "guy" and s.kind != "jump":
			out_spans.append({"points": s.points, "kind": s.kind})
	ctx.services["poles"] = {"poles": out_poles, "spans": out_spans}
	return null


## JS number-to-string for the pole ids ("S" + -26 is "S-26").
static func _num(x: float) -> String:
	return str(int(x)) if x == floorf(x) else str(x)


func mk(id: String, x: float, z: float, o: Dictionary = {}) -> Dictionary:
	var p := {"id": id, "x": x, "z": z, "y": height_at(x, z), "cls": "main", "H": 12.0, "detail": "full", "road": [1, 0], "f": FEAT.get(id, {})}
	p.merge(o, true)
	p.H = float(p.H)
	poles.append(p)
	by_id[id] = p
	return p


func far(id: String, x: float, z: float, o: Dictionary = {}) -> Dictionary:
	var H := 11.5 + (0.5 if R.f() < 0.5 else 0.0)
	var f := {"tr": 1 if R.f() < 0.25 else 0}
	var b := {"detail": "far", "H": H, "f": f}
	b.merge(o, true)
	return mk(id, x, z, b)


func link(a: String, b: String, tiers: Array, run: bool = false) -> void:
	if by_id.has(a) and by_id.has(b):
		SP.append({"A": by_id[a], "B": by_id[b], "tiers": tiers, "run": run})


func chain(ids: Array, tiers: Array) -> void:
	for i in ids.size() - 1:
		link(ids[i], ids[i + 1], tiers, true)


static func unit2(x: float, z: float) -> Array:
	var l := Vector2(x, z).length()
	if l == 0.0:
		l = 1.0
	return [x / l, z / l]


static func to_local(p: Dictionary, x: float, z: float) -> Array:
	var c := cos(p.rotY)
	var s := sin(p.rotY)
	return [x * c - z * s, x * s + z * c]


static func heights(p: Dictionary) -> Dictionary:
	var H: float = p.H
	if p.cls == "low":
		return {"arm": null, "lv": [6.9, 6.6, 6.3], "light": 5.55, "tel": [5.15, 4.9]}
	if p.cls == "alley":
		return {"arm": H - 0.4, "lv": [7.2, 6.9, 6.6], "light": 5.85, "tel": [5.3, 5.02]}
	return {"arm": H - 0.4, "lv": [H - 3.4, H - 3.7, H - 4.0], "light": 6.5 if H >= 12 else 6.3, "tel": [5.95, 5.65, 5.38]}


static func r_at(p: Dictionary, h: float) -> float:
	return p.rTop + (p.H - h) / 150.0


func face_l(p: Dictionary, s) -> float:
	if s is float or s is int:
		return s
	if s == "road":
		return 0.0
	if s == "lot":
		return PI
	return COMPASS[s] - p.rotY


static func is_busy(busy: Array, y: float, phi: float) -> bool:
	for bz in busy:
		if y >= bz.y0 and y <= bz.y1 and (bz.get("face") == null or angd(phi, bz.face) < (bz.get("w", 0.7) if bz.get("w") else 0.7)):
			return true
	return false


static func at(phi: float, rad: float, y: float) -> Array:
	return [sin(phi) * rad, y, cos(phi) * rad]


func hv_at(p: Dictionary, dW: Vector3) -> Array:
	var dl := to_local(p, dW.x, dW.z)
	var psi := atan2(dl[0], dl[1])
	var best: Dictionary = p.arms[0]
	var bc := -1.0
	for arm in p.arms:
		var c := absf(cos(psi - arm.psi))
		if c > bc:
			bc = c
			best = arm
	var px: float = p.x
	var pz: float = p.z
	return T.stable_sort(best.pts.duplicate(), func(u: Vector3, v: Vector3):
		return (dW.x * (u.z - pz) - dW.z * (u.x - px)) - (dW.x * (v.z - pz) - dW.z * (v.x - px)))


func band(a: Kit, p: Dictionary, seg: int, y: float, extra: float = 0.006, h: float = 0.03, col = null) -> void:
	a.cylO(r_at(p, y) + extra, h, [0, y, 0], col if col != null else COL.steel, seg)


func build_pole(p: Dictionary) -> void:
	var H: float = p.H
	var is_far: bool = p.detail == "far"
	var f: Dictionary = p.f
	var hs: Dictionary = p.hs
	var rTop := 0.12 if is_far else 0.11
	p.rTop = rTop
	var pole_m := Transform3D(Basis(UP, p.rotY), Vector3(p.x, p.y, p.z))
	p.M = pole_m
	var A := Acc.new(WHITE_UV)
	var B := Acc.new(WHITE_UV)
	var Lm := Acc.new(WHITE_UV)
	var Wd := Acc.new(WHITE_UV)
	A.T_ = pole_m
	B.T_ = pole_m
	Lm.T_ = pole_m
	p.acc = {"A": A, "B": B, "L": Lm, "W": Wd}
	var a := Kit.new(A, GC)
	var b := Kit.new(B, GC)
	var l := Kit.new(Lm, GC)
	p.kW = Kit.new(Wd, GC)
	var seg := 10 if is_far else 16
	var busy := []

	# --- shaft + cap
	a.geo(Geo.cylinder(rTop, r_at(p, -0.3), H + 0.3, seg, 1, true), Kit.M([0, (H - 0.3) / 2, 0]), null, UV.shaft)
	a.sph(rTop + 0.012, [0, H, 0], COL.cap, 10, [1, 0.5, 1])
	a.cylO(rTop + 0.014, 0.05, [0, H - 0.025, 0], COL.cap, seg)
	if p.get("gw") and not is_far:
		a.cyl(0.013, 0.17, [0, H + 0.1, 0], COL.steel, 6)
		a.sph(0.02, [0, H + 0.19, 0], COL.steel, 6)
		p.gwPt = pole_m * Vector3(0, H + 0.17, 0)

	# --- base: yellow guard + black/yellow reflective sleeve (tiger stripes)
	var kind: String
	if is_far:
		kind = "tiger" if R.f() < 0.5 else "none"
	else:
		kind = "tiger" if p.cls == "alley" else "both"
	p.hasCover = kind == "both"
	p.hasTiger = kind != "none"
	if p.hasCover:
		a.geo(Geo.cylinder(r_at(p, 0.78) + 0.02, r_at(p, -0.02) + 0.024, 0.8, seg, 1, true), Kit.M([0, 0.38, 0]), null, UV.cover)
		a.cyl(r_at(p, 0.78) + 0.026, 0.035, [0, 0.785, 0], COL.yellowDark, seg)
	if p.hasTiger:
		var y0 := 0.8 if p.hasCover else 0.25
		var y1 := 1.95
		a.geo(Geo.cylinder(r_at(p, y1) + 0.008, r_at(p, y0) + 0.008, y1 - y0, seg, 1, true), Kit.M([0, (y0 + y1) / 2, 0]), null, UV.sleeve)

	# --- number plate (road face) + telecom plate (lot face) + ad + stickers
	if not is_far:
		var hc := 2.17
		var rr := r_at(p, hc)
		a.box(0.116, 0.346, 0.008, at(0, rr + 0.004, hc), COL.steelLight)
		b.geo(GC.plane(), Kit.M(at(0, rr + 0.0088, hc), null, [0.108, 0.336, 1]), null, Atlas.uv_of(Atlas.plate_rect(p.plateIdx)))
		band(a, p, seg, hc + 0.19, 0.012, 0.022, COL.steelDark); band(a, p, seg, hc - 0.19, 0.012, 0.022, COL.steelDark)
		busy.append({"y0": 1.95, "y1": 2.42, "face": 0.0})
		var ti: int = (p.plateIdx * 7) % 15
		var tc := 2.12
		var tr_ := r_at(p, tc)
		a.box(0.076, 0.19, 0.006, at(PI, tr_ + 0.003, tc), COL.steelLight, [0, PI, 0])
		a.geo(GC.plane(), Kit.M(at(PI, tr_ + 0.0082, tc), [0, PI, 0], [0.07, 0.176, 1]), null, Atlas.uv_of(Atlas.tel_plate_rect(ti)))
		busy.append({"y0": 1.95, "y1": 2.3, "face": PI})
	if not is_far and f.get("ad"):
		var phi := face_l(p, f.ad[1])
		var y0 := 2.06
		var y1 := 3.42
		var r0 := r_at(p, y0) + 0.007
		var r1 := r_at(p, y1) + 0.007
		var tl := 0.28 / ((r0 + r1) / 2)
		a.geo(Geo.cylinder(r1, r0, y1 - y0, 8, 1, true, phi - tl / 2, tl), Kit.M([0, (y0 + y1) / 2, 0]), null, Atlas.uv_of(Atlas.ad_rect(f.ad[0])))
		for yb in [y0 - 0.018, y1 + 0.018]:
			var rb := r_at(p, yb) + 0.01
			a.geo(Geo.cylinder(rb, rb, 0.024, 10, 1, true, phi - tl / 2 - 0.3, tl + 0.6), Kit.M([0, yb, 0]), COL.steelDark)
		busy.append({"y0": y0 - 0.06, "y1": y1 + 0.06, "face": phi, "w": tl / 2 + 0.35})
	if not is_far:
		for st in f.get("st", []):
			var key: String = st[0]
			var yc: float = st[2]
			var phi: float = face_l(p, st[1]) + (R.f() - 0.5) * 0.25
			var sw: float = STK[key][0]
			var sh: float = STK[key][1]
			var off := 0.028 if p.hasCover and yc < 0.8 else (0.013 if p.hasTiger and yc > 0.25 and yc < 1.95 else 0.004)
			var rr := r_at(p, yc) + off
			var tl := sw / rr
			b.geo(Geo.cylinder(rr, rr, sh, 5, 1, true, phi - tl / 2, tl), Kit.M([0, yc, 0]), null, Atlas.uv_of(Atlas.RB[key]))

	# --- HV crossarms with pin insulators
	for ai in p.arms.size():
		var arm: Dictionary = p.arms[ai]
		var y: float = hs.arm - ai * 0.75
		var beta: float = arm.psi - HALF
		var sub := Basis(UP, beta)
		var side := 1.0 if ai else -1.0
		var xa := side * (r_at(p, y) + 0.045)
		a.box(0.085, 0.085, 1.7 if is_far else 1.8, sub * Vector3(xa, y, 0), COL.steel, [0, beta, 0])
		band(a, p, seg, y, 0.01, 0.07, COL.steelDark)
		a.rodC(sub * Vector3(side * (r_at(p, y) - 0.02), y, 0), sub * Vector3(xa + side * 0.05, y, 0), 0.016, COL.steelDark, 6)  # through bolt
		if not is_far:
			for zz in [-0.56, 0.56]:
				a.rodB(sub * Vector3(side * (r_at(p, y - 0.5) + 0.01), y - 0.5, 0), sub * Vector3(xa, y - 0.045, zz), 0.03, 0.012, COL.steel)
			band(a, p, seg, y - 0.5, 0.008, 0.04)
		arm.pts = []
		arm.y = y
		for o in [-0.78, 0.33, 0.78]:
			if is_far:
				a.cyl(0.034, 0.12, sub * Vector3(xa, y + 0.1, o), COL.porcelain, 6)
				a.cyl(0.062, 0.02, sub * Vector3(xa, y + 0.1, o), COL.porcelain, 8)
			else:
				a.cyl(0.012, 0.05, sub * Vector3(xa, y + 0.065, o), COL.steelDark, 6)
				a.lathe("pin", sub * Vector3(xa, y + 0.07, o), COL.porcelain, 1, [0, beta, 0], 8)
			arm.pts.append(pole_m * (sub * Vector3(xa, y + 0.2, o)))
		busy.append({"y0": y - 0.62, "y1": H + 0.3, "face": null})

	# --- pole transformer(s) + cut-out switches, or a sectionalizing switch
	var shift := 0.45 if p.arms.size() > 1 else 0.0
	if f.get("tr") and hs.arm != null:
		var trTop: float = hs.arm - 1.75 - shift
		var trBot := trTop - 0.75
		var cy := trTop - 0.375
		var sides := [1, -1] if f.tr == 2 else [1]
		var cans := []
		for s in sides:
			var r0 := r_at(p, cy)
			var cx: float = s * (r0 + 0.3)
			var cs := 10 if is_far else 16
			for yy in [trTop - 0.08, trBot + 0.12]:
				a.box(0.34, 0.05, 0.05, [s * (r0 + 0.15), yy, 0], COL.steelDark)
				band(a, p, seg, yy, 0.01, 0.05, COL.steelDark)
			a.box(0.03, 0.8, 0.12, [s * (r0 + 0.075), cy, 0], COL.steelDark)
			a.geo(Geo.cylinder(0.22, 0.22, 0.75, cs, 1, true, -PI, TAU), Kit.M([cx, cy, 0]), null, UV.trans)
			a.cyl(0.214, 0.03, [cx, trBot - 0.008, 0], COL.transDark, cs)
			a.cyl(0.236, 0.036, [cx, trTop + 0.012, 0], COL.trans, cs)
			a.sph(0.226, [cx, trTop + 0.028, 0], COL.trans, 8 if is_far else 12, [1, 0.22, 1])
			if not is_far:
				for yy in [cy + 0.2, cy - 0.22]:
					a.cylO(0.226, 0.022, [cx, yy, 0], COL.transDark, cs)
			var hvB := []
			var lvB := []
			for dz in [-0.09, 0.09]:
				if is_far:
					a.cyl(0.025, 0.09, [cx, trTop + 0.09, dz], COL.porcelainGrey, 6)
				else:
					a.lathe("bush", [cx, trTop + 0.04, dz], COL.porcelainGrey, 0.9, null, 8)
				hvB.append(pole_m * Vector3(cx, trTop + 0.14, dz))
			for dx in [-0.08, 0, 0.08]:
				a.rodC([cx + dx, cy + 0.2, 0.2], [cx + dx, cy + 0.2, 0.29], 0.018, COL.black, 6)
				lvB.append(pole_m * Vector3(cx + dx, cy + 0.2, 0.295))
			cans.append({"hvB": hvB, "lvB": lvB})
		var ycut: float = hs.arm - 1.1 - shift
		var r1 := r_at(p, ycut)
		var xc := r1 + 0.035
		a.box(0.065, 0.065, 1.12, [xc, ycut, 0], COL.steel)
		band(a, p, seg, ycut, 0.01, 0.05)
		var cut_top := []
		var cut_bot := []
		for cz in ([-0.35, 0.35] if is_far else [-0.42, 0.02, 0.44]):
			var yb := ycut - 0.2
			a.box(0.1, 0.27, 0.11, [xc, yb, cz], COL.cutout)
			a.box(0.11, 0.035, 0.12, [xc, yb + 0.1, cz], COL.porcelainGrey)
			if not is_far:
				a.box(0.03, 0.15, 0.028, [xc + 0.065, yb - 0.02, cz], COL.steelDark)
				a.cyl(0.012, 0.05, [xc, yb + 0.16, cz], COL.steelDark, 6)
				a.cyl(0.012, 0.05, [xc, yb - 0.16, cz], COL.steelDark, 6)
			cut_top.append(pole_m * Vector3(xc, yb + 0.185, cz))
			cut_bot.append(pole_m * Vector3(xc, yb - 0.185, cz))
		p.trInfo = {"cans": cans, "cutTop": cut_top, "cutBot": cut_bot}
		busy.append({"y0": trBot - 0.15, "y1": ycut + 0.1, "face": null})
		if not is_far:  # earth wire + grey conduit down the pole
			var phi := PI - 0.55
			a.rodC(at(phi, r_at(p, trBot) + 0.014, trBot + 0.1), at(phi, r_at(p, 2.45) + 0.03, 2.45), 0.008, COL.black, 4)
			a.box(0.05, 1.7, 0.03, at(phi, r_at(p, 1.6) + 0.036, 1.6), COL.conduit, [0, phi, 0])
	if f.get("sw") and hs.arm != null:
		var ysw: float = hs.arm - 1.35
		var s := -1.0
		var r0 := r_at(p, ysw)
		var bx := s * (r0 + 0.3)
		a.box(0.06, 0.06, 0.5, [s * (r0 + 0.03), ysw + 0.3, 0], COL.steelDark)
		band(a, p, seg, ysw + 0.3, 0.01, 0.05, COL.steelDark)
		a.box(0.03, 0.3, 0.3, [s * (r0 + 0.07), ysw + 0.1, 0], COL.steelDark)
		a.box(0.46, 0.4, 0.34, [bx, ysw, 0], COL.boxGrey)
		a.box(0.5, 0.04, 0.38, [bx, ysw + 0.215, 0], COL.boxGreyDark)
		var bush_pts := []
		for dz in [-0.11, 0, 0.11]:
			for dx in [-0.13, 0.13]:
				a.lathe("bush", [bx + dx, ysw + 0.23, dz], COL.porcelainGrey, 0.8, null, 8)
				bush_pts.append(pole_m * Vector3(bx + dx, ysw + 0.31, dz))
		a.rodC([bx + s * 0.24, ysw - 0.02, 0.1], [bx + s * 0.3, ysw - 0.35, 0.24], 0.012, COL.steelDark)
		a.box(0.1, 0.06, 0.02, [bx, ysw - 0.02, 0.175], COL.signBack)
		p.swInfo = {"bushPts": bush_pts}
		busy.append({"y0": ysw - 0.45, "y1": ysw + 0.4, "face": null})

	# --- low-voltage rack with spool insulators (road face)
	p.lvPts = []
	if true:
		var lv: Array = hs.lv
		var top: float = lv[0] + 0.1
		var bot: float = lv[lv.size() - 1] - 0.1
		var rm := r_at(p, (top + bot) / 2)
		band(a, p, seg, top, 0.008, 0.04); band(a, p, seg, bot, 0.008, 0.04)
		a.box(0.03, 0.03, 0.13, at(0, rm + 0.055, top), COL.steelDark); a.box(0.03, 0.03, 0.13, at(0, rm + 0.055, bot), COL.steelDark)
		a.box(0.05, top - bot + 0.05, 0.014, at(0, rm + 0.115, (top + bot) / 2), COL.steel)
		for y in lv:
			if not is_far:
				a.box(0.06, 0.008, 0.1, at(0, rm + 0.165, y + 0.045), COL.steel)
				a.box(0.06, 0.008, 0.1, at(0, rm + 0.165, y - 0.045), COL.steel)
				a.lathe("spool", at(0, rm + 0.18, y - 0.038), COL.porcelain, 1, null, 6)
			else:
				a.cyl(0.036, 0.07, at(0, rm + 0.18, y), COL.porcelain, 6)
			p.lvPts.append(pole_m * _v3(at(0, rm + 0.215, y)))
		busy.append({"y0": bot - 0.12, "y1": top + 0.12, "face": 0.0, "w": 1.0})
		# service-drop spool on the side (+X) so drops to either side never clip the shaft
		var yd := bot - 0.2
		var rd := r_at(p, yd)
		band(a, p, seg, yd, 0.008, 0.035)
		a.box(0.13, 0.025, 0.025, [rd + 0.06, yd, 0], COL.steelDark)
		if not is_far:
			a.lathe("spool", [rd + 0.14, yd - 0.035, 0], COL.porcelain, 0.85, null, 6)
		p.lvDrop = pole_m * Vector3(rd + 0.17, yd, 0)
		p.lvDropJ = [p.lvPts[p.lvPts.size() - 1], pole_m * Vector3(rd + 0.16, yd + 0.12, rd + 0.1), p.lvDrop]
		busy.append({"y0": yd - 0.1, "y1": yd + 0.1, "face": HALF, "w": 0.8})

	# --- LED street light on a side bracket, facing the road
	p.light = R.f() < 0.4 if is_far else true
	if p.light:
		var y: float = hs.light
		var r0 := r_at(p, y)
		band(a, p, seg, y, 0.01, 0.05); band(a, p, seg, y + 0.17, 0.01, 0.05)
		a.box(0.075, 0.26, 0.03, at(0, r0 + 0.012, y + 0.085), COL.lampArm)
		a.geo(tube_quadratic(Vector3(0, y + 0.06, r0 + 0.02), Vector3(0, y + 0.1, r0 + 0.62), Vector3(0, y + 0.33, r0 + 1.02), 5 if is_far else 10, 0.026, 6, false), null, COL.lampArm)
		var hz := r0 + 1.25
		var hy := y + 0.37
		a.cyl(0.034, 0.07, [0, y + 0.34, r0 + 1.03], COL.lampArm, 8, [HALF, 0, 0])
		a.sph(0.5, [0, hy, hz], COL.lampHousing, 8 if is_far else 12, [0.27, 0.11, 0.56], [-0.08, 0, 0])
		l.sph(0.5, [0, hy - 0.036, hz + 0.004], null, 8 if is_far else 10, [0.22, 0.07, 0.48], [-0.08, 0, 0])
		if not is_far:
			a.cyl(0.018, 0.035, [0, hy + 0.065, hz - 0.14], COL.lampHousing, 8)
		p.lampFeed = pole_m * Vector3(0, y + 0.1, r0 + 0.035)
		busy.append({"y0": y - 0.12, "y1": y + 0.45, "face": 0.0, "w": 0.9})

	# --- telecom: suspension clamps, drop terminal, slack loop; optional high crossing bracket
	p.telPts = []
	var tel: Array = hs.tel
	var telN: int = 1 if is_far else tel.size()
	for k in telN:
		var y: float = tel[k]
		var r0 := r_at(p, y)
		var off := 0.14 + 0.08 * k
		band(a, p, seg, y, 0.008, 0.035, COL.steelDark)
		a.box(0.025, 0.025, off, at(0, r0 + off / 2, y), COL.steelDark)
		a.box(0.05, 0.055, 0.065, at(0, r0 + off, y - 0.02), COL.black)
		p.telPts.append(pole_m * _v3(at(0, r0 + off, y - 0.055)))
	var tLow: float = tel[telN - 1]
	if not is_far:
		var yT := tLow - 0.45
		var r0 := r_at(p, yT)
		band(a, p, seg, yT + 0.1, 0.008, 0.03, COL.steelDark)
		a.box(0.09, 0.22, 0.13, [r0 + 0.055, yT, 0], COL.termBox)
		a.box(0.1, 0.03, 0.14, [r0 + 0.055, yT + 0.125, 0], COL.termBoxDark)
		a.box(0.004, 0.05, 0.07, [r0 + 0.101, yT + 0.03, 0], COL.porcelain)
		p.telDrop = pole_m * Vector3(r0 + 0.07, yT - 0.12, 0)
		if R.f() < 0.5:
			a.geo(GC.torus(), Kit.M([0.42 if R.f() < 0.5 else -0.42, tel[0] - 0.4, r0 + 0.17]), COL.telCable)
		busy.append({"y0": yT - 0.2, "y1": tel[0] + 0.1, "face": 0.0, "w": 1.3})
		busy.append({"y0": yT - 0.2, "y1": yT + 0.2, "face": HALF, "w": 0.8})
	else:
		p.telDrop = p.telPts[0]
	if f.get("telHigh"):
		var y := H - 1.5
		var r0 := r_at(p, y)
		band(a, p, seg, y, 0.01, 0.05, COL.steelDark)
		a.box(0.03, 0.03, 0.34, at(0, r0 + 0.17, y), COL.steelDark)
		a.rodC(at(0, r0 + 0.01, y - 0.32), at(0, r0 + 0.3, y - 0.02), 0.012, COL.steelDark)
		a.box(0.06, 0.06, 0.075, at(0, r0 + 0.34, y - 0.03), COL.black)
		p.telHighPt = pole_m * _v3(at(0, r0 + 0.34, y - 0.075))
		busy.append({"y0": y - 0.38, "y1": y + 0.1, "face": null})

	# --- small security camera (near the station)
	if f.get("cam") and not is_far:
		var phi := face_l(p, f.cam)
		var y := 3.62
		var r0 := r_at(p, y)
		var tilt := 0.22
		band(a, p, seg, y, 0.01, 0.05)
		a.box(0.07, 0.13, 0.02, at(phi, r0 + 0.01, y), COL.camera, [0, phi, 0])
		a.rodC(at(phi, r0 + 0.015, y), at(phi, r0 + 0.2, y - 0.02), 0.018, COL.camera, 8)
		var cp := _v3(at(phi, r0 + 0.3, y - 0.07))
		var rot := [tilt, phi, 0, "YXZ"]
		var eb := Basis.from_euler(Vector3(tilt, phi, 0), EULER_ORDER_YXZ)
		a.geo(GC.rbox(), Kit.M(cp, rot, [0.11, 0.11, 0.27]), COL.camera)
		a.box(0.14, 0.012, 0.31, cp + eb * Vector3(0, 0.068, 0.03), COL.camera, rot)
		a.cyl(0.04, 0.02, cp + eb * Vector3(0, 0, 0.135), COL.lens, 12, [HALF + tilt, phi, 0, "YXZ"])
		a.cyl(0.006, 0.01, cp + eb * Vector3(0.035, -0.035, 0.138), C("#d9463b"), 6, [HALF + tilt, phi, 0, "YXZ"])
		busy.append({"y0": y - 0.25, "y1": y + 0.15, "face": phi, "w": 0.8})

	# --- pole-mounted signs (通学路, 桜ヶ丘駅→, 消火栓)
	if not is_far:
		for sg in f.get("sign", []):
			var key: String = sg[0]
			var yc: float = sg[2]
			var phi := face_l(p, sg[1])
			var r0 := r_at(p, yc)
			var sw: float = SIGN[key][0]
			var sh: float = SIGN[key][1]
			var dd := r0 + 0.075
			band(a, p, seg, yc + sh * 0.28, 0.01, 0.03, COL.steelDark); band(a, p, seg, yc - sh * 0.28, 0.01, 0.03, COL.steelDark)
			a.box(0.045, sh * 0.7, 0.07, at(phi, r0 + 0.035, yc), COL.steelDark, [0, phi, 0])
			if key == "diamond":
				var back: T.Geometry = Geo.extrude([[0, 0.5], [-0.5, 0], [0, -0.5], [0.5, 0]], 0.012)
				a.geo(back, Kit.M(at(phi, dd, yc), [0, phi, 0], [sw, sh, 1]), COL.signBack)
				b.geo(GC.diamond(), Kit.M(at(phi, dd + 0.0075, yc), [0, phi, 0], [sw, sh, 1]), null, Atlas.uv_of(Atlas.RB.diamond))
			else:
				a.box(sw, sh, 0.012, at(phi, dd, yc), COL.signBack, [0, phi, 0])
				b.geo(GC.plane(), Kit.M(at(phi, dd + 0.0075, yc), [0, phi, 0], [sw, sh, 1]), null, Atlas.uv_of(Atlas.RB[key]))
			busy.append({"y0": yc - sh / 2 - 0.06, "y1": yc + sh / 2 + 0.06, "face": phi, "w": 0.9})

	# --- step bolts (足場ボルト) on the two faces free of ads, "危険 のぼるな" plate below them
	if not is_far:
		var bf: float = face_l(p, f.ad[1]) + HALF if f.get("ad") else HALF
		if true:
			var y := 2.26
			var r0 := r_at(p, y)
			var phi := bf + PI if is_busy(busy, y, bf) else bf
			a.box(0.106, 0.14, 0.006, at(phi, r0 + 0.003, y), COL.steelLight, [0, phi, 0])
			b.geo(GC.plane(), Kit.M(at(phi, r0 + 0.0072, y), [0, phi, 0], [0.098, 0.13, 1]), null, Atlas.uv_of(Atlas.RB.noboruna))
		var sgn := 0
		var y := 2.55
		while y < H - 1.2:
			var phi := bf + PI if sgn else bf
			sgn ^= 1
			if is_busy(busy, y, phi):
				y += 0.45
				continue
			var r0 := r_at(p, y)
			a.box(0.02, 0.02, 0.2, at(phi, r0 + 0.09, y), COL.steelDark, [0, phi, 0])
			a.box(0.02, 0.055, 0.02, at(phi, r0 + 0.18, y + 0.03), COL.steelDark, [0, phi, 0])
			y += 0.45


# ================================================================ 7. wires
func add_wire(pts: Array, st: Dictionary, kind: String) -> void:
	ctx.wires.add(pts, {"width": st.w, "color": st.c})
	spans.append({"points": pts, "kind": kind})


func hang(pa: Vector3, pb: Vector3, sag: float, st: Dictionary, kind: String, n: int = 0) -> Array:
	var length := pa.distance_to(pb)
	var pts := Geo.catenary(pa, pb, maxf(0.02, sag), n if n else maxi(6, mini(24, int(T.js_round(length / 1.3)))))
	add_wire(pts, st, kind)
	return pts


func closure(k: Kit, P: Vector3, Tg: Vector3) -> void:
	var q := T.quat_from_unit_vectors(UP, Tg)
	var length: float = 0.48 + R.f() * 0.28
	var r: float = 0.068 + R.f() * 0.022
	var c := P
	c.y -= r + 0.035
	k.geo(GC.cyl(8), T.compose(c, q, Vector3(2 * r, length, 2 * r)), COL.closure)
	for s in [-1, 1]:
		var e: Vector3 = c + Tg * (s * length / 2)
		k.geo(GC.sph(8), T.compose(e, q, Vector3(2 * r * 0.96, 2 * r * 0.55, 2 * r * 0.96)), COL.closure)
		var g: Vector3 = c + Tg * (s * (length / 2 + r * 0.25))
		k.geo(GC.cyl(6), T.compose(g, q, Vector3(0.035, 0.05, 0.035)), COL.black)
	for s in [-0.3, 0.3]:
		var e: Vector3 = c + Tg * (s * length)
		var top: Vector3 = P + Tg * (s * length)
		k.rodC([e.x, e.y + r * 0.7, e.z], [top.x, top.y, top.z], 0.01, COL.black, 5)


# ================================================================ 8. service drops
func brackets(k: Kit, w: Vector3, n: Vector3, tel: bool) -> Vector3:
	var rot := atan2(n.x, n.z)
	k.box(0.05 if tel else 0.07, 0.07 if tel else 0.12, 0.018, [w.x + n.x * 0.009, w.y, w.z + n.z * 0.009], COL.steelDark, [0, rot, 0])
	var tip := w + n * (0.07 if tel else 0.1)
	k.rodC([w.x, w.y + 0.02, w.z], [tip.x, tip.y + 0.02, tip.z], 0.007, COL.steelDark, 5)
	if not tel:
		k.lathe("spool", [tip.x, tip.y - 0.028, tip.z], COL.porcelain, 0.65, null, 6)
	else:
		k.sph(0.016, [tip.x, tip.y + 0.01, tip.z], COL.black, 6)
	return Vector3(tip.x, tip.y + (0.012 if tel else 0.004), tip.z)


static func drop_sag(a: Vector3, b: Vector3) -> float:
	return 0.02 * a.distance_to(b) + 0.08


static func clear_path(F, a: Vector3, b: Vector3, sag: float) -> bool:
	var pts := Geo.catenary(a, b, sag, 4)
	for i in pts.size() - 1:
		if F.seg(pts[i], pts[i + 1]) != null:
			return false
	return true


func find_wall(F, d: Dictionary):
	for hy in [5.3, 4.95, 4.6, 3.4, 3.0]:
		for sh in [0, 0.7, -0.7, 1.4, -1.4, 2.2, -2.2]:
			var ox: float = d.O.x + d.lat.x * sh
			var oz: float = d.O.z + d.lat.z * sh
			var y: float = height_at(ox, oz) + hy
			var h = F.seg(Vector3(ox + d.n.x * 0.5, y, oz + d.n.z * 0.5), Vector3(ox - d.n.x * d.maxD, y, oz - d.n.z * d.maxD))
			if h == null or not h.solid:
				continue
			var nh := Vector3(h.normal.x, 0, h.normal.z)
			if nh.length() < 0.85:
				continue
			nh = nh.normalized()
			if nh.dot(d.n) < 0.5:
				continue
			var tip: Vector3 = h.point + nh * 0.13
			if not clear_path(F, d.p.lvDrop, tip, drop_sag(d.p.lvDrop, tip)):
				continue
			return {"wp": h.point, "n": nh}
	return null


func realise(k: Kit, d: Dictionary, w: Dictionary, F) -> void:
	var p: Dictionary = d.p
	var wp: Vector3 = w.wp
	var n: Vector3 = w.n
	var tip := brackets(k, wp, n, false)
	hang(p.lvDrop, tip, drop_sag(p.lvDrop, tip), WS.dropP, "drop")
	var wl := wp
	wl.y -= 0.38  # service entrance lead into the wall (drip loop)
	ctx.wires.add(Geo.catenary(tip, wl + n * 0.012, 0.06, 5), {"width": 0.014, "color": WS.dropP.c})
	if not d.withTel:
		return
	var lat := Vector3(-n.z, 0, n.x)
	if lat.dot(d.lat) < 0:
		lat = -lat
	var wt: Vector3 = wp + lat * d.telShift
	wt.y -= 0.5
	var tn := n
	if F != null:  # re-find the wall at the telecom bracket (the facade may step or end there)
		var h = F.seg(wt + n * 0.6, wt + n * -2.5)
		if h == null or not h.solid:
			return
		tn = Vector3(h.normal.x, 0, h.normal.z)
		if tn.length() < 0.85:
			return
		tn = tn.normalized()
		if tn.dot(n) < 0.7:
			return
		wt = h.point
		if not clear_path(F, p.telDrop, wt + tn * 0.1, drop_sag(p.telDrop, wt) + 0.02):
			return
	var tt := brackets(k, wt, tn, true)
	hang(p.telDrop, tt, 0.025 * (p.telDrop as Vector3).distance_to(tt) + 0.08, WS.dropT, "drop")


func finalize_drops() -> void:
	var F := Facade.new(ctx, [mA, mB, mL])
	var n_mesh := F.collect()
	var acc := Acc.new(WHITE_UV)
	var k := Kit.new(acc, GC)
	var spans0 := spans.size()
	var t0 := Time.get_ticks_msec()
	var built := 0
	for d in drop_reqs:
		var w = null
		if n_mesh == 0:
			w = {"wp": d.def, "n": d.n}
		elif Time.get_ticks_msec() - t0 < 4000:
			w = find_wall(F, d)
		if w == null:
			continue
		realise(k, d, w, F if n_mesh else null)
		built += 1
	var g = acc.build()
	if g != null:
		var m := T.MeshObj.new(g, mA)
		m.cast_shadow = true
		m.receive_shadow = true
		m.name = "pole-drops"
		ctx.add_static(m)
	var sv = ctx.services.get("poles")
	if sv != null:
		for s in spans.slice(spans0):
			sv.spans.append({"points": s.points, "kind": s.kind})
		sv["drops"] = {"requested": drop_reqs.size(), "built": built, "facadeMeshes": n_mesh, "ms": int(T.js_round(Time.get_ticks_msec() - t0))}


# ================================================================ 9. guy wires
func free_ground(x: float, z: float) -> bool:
	if z > 0.5 and z < 131 and absf(x - L.street_center_x(z)) < 3.2:
		return false
	if absf(x + 12) < 3.0 and z > -89 and z < -4:
		return false
	if absf(z + 2) < 3.2 and absf(x) < 96:
		return false
	if absf(z + 55.5) < 2.2 and absf(x) < 96:
		return false
	if absf(z + 71) < 1.7 and absf(x) < 86:
		return false
	if absf(z + 93) < 1.8:
		return false
	if z < -33.5 and z > -52.5:
		return false
	if x > -9.6 and x < 26.4 and z > -25.4 and z < -4.7:
		return false
	if z > 1 and z < 129:
		var dx: float = x - L.street_center_x(z)
		var d := absf(dx)
		if d > 4.65 and d < 19.2:
			return false
		# keep shop / shrine frontages clear (entrances, boards, benches, flags)
		if d > 3.0 and d < 5.2:
			for l in L.LOTS:
				if l.side == signf(dx) and z > l.z0 - 0.8 and z < l.z1 + 0.8 and l.owner != "houses":
					return false
	for bl in L.BLOCKS:
		if x > bl.x0 - 0.3 and x < bl.x1 + 0.3 and z > bl.z0 - 0.3 and z < bl.z1 + 0.3:
			return false
	for v in L.VENDING:
		if Vector2(x - v.x, z - v.z).length() < 1.6:
			return false
	for b in L.SPOTS.konbiniBikes:
		if Vector2(x - b.x, z - b.z).length() < 1.4:
			return false
	return true


func build_guy(p: Dictionary, dx: float, dz: float, ax: float, az: float) -> void:
	var k: Kit = p.kW
	var ya: float = p.hs.lv[p.hs.lv.size() - 1] - 0.55
	var ra := r_at(p, ya)
	k.geo(GC.cylO(12), T.compose(Vector3(p.x, p.y + ya, p.z), Quaternion(), Vector3(2 * (ra + 0.01), 0.06, 2 * (ra + 0.01))), COL.steelDark)
	var top := Vector3(p.x + dx * (ra + 0.03), p.y + ya, p.z + dz * (ra + 0.03))
	var ay := height_at(ax, az)
	var anc := Vector3(ax, ay + 0.06, az)
	hang(top, anc, 0.02, WS.guy, "guy", 8)
	var u := (top - anc).normalized()
	var g0 := anc + u * 0.12
	var g1 := anc + u * 2.0
	if p.detail == "far":
		k.rodC(g0, g1, 0.04, COL.guard, 8)
	else:
		k.rodC(g0, g1, 0.04, COL.guard, 10)
		for t in [0.2, 0.5, 0.8]:
			var m0 := g0.lerp(g1, t - 0.04)
			var m1 := g0.lerp(g1, t + 0.04)
			k.rodC(m0, m1, 0.043, COL.guardBand, 10)
		k.sph(0.045, g1, COL.guard, 8)
		physics(anc.x + u.x * 0.45, anc.z + u.z * 0.45, 0.12, ay - 0.5, ay + 1.8)
	k.box(0.32, 0.12, 0.32, [ax, ay + 0.02, az], COL.anchor, [0, atan2(dx, dz), 0])
	k.rodC([ax, ay + 0.06, az], g0, 0.018, COL.steelDark, 6)


func physics(x: float, z: float, r: float, y0: float, y1: float) -> void:
	ctx.physics.addCylinder(x, z, r, y0, y1)


# ================================================================ 10. meshes
func put(root, p: Dictionary, acc, m, shadow: bool) -> void:
	var g = acc.build()
	if g == null:
		return
	var mesh := T.MeshObj.new(g, m)
	mesh.cast_shadow = shadow
	mesh.receive_shadow = true
	mesh.name = "pole-" + p.id
	root.add(mesh)
