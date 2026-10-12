# petals/ground.js: static petals lying on surfaces: wind-blown streaks, small piles against curbs /
# walls / gutters, clusters under every sakura, road corners, platform corners & fence bases,
# benches, vending machine tops, café tables and a few stuck to the café window. One InstancedMesh
# (toon material).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")

var env: Dictionary
var r
var cap: int
var P := PackedFloat32Array()
var Q := PackedFloat32Array()
var S := PackedFloat32Array()
var TN := PackedFloat32Array()
var n := 0
var WIND := atan2(0.35, 0.9)  # wind heading (angle in XZ, +X = 0)
var wdx := cos(WIND)
var wdz := sin(WIND)
var count: int:
	get:
		return n


static func create(_ctx, e: Dictionary):
	var g = load("res://addons/sakuragaoka_station/world/petals/ground.gd").new()
	g.env = e
	g.r = e.r
	g.cap = e.capacity
	g.P.resize(g.cap * 3)
	g.Q.resize(g.cap * 4)
	g.S.resize(g.cap)
	g.TN.resize(g.cap)
	return g


func _r() -> float:
	return r.f()


func tone() -> float:
	var u := _r()
	if u < 0.05:
		return 1.3 + _r() * 0.2  # aged, slightly browned
	if u < 0.12:
		return 1.0 + _r() * 0.2  # deeper pink
	return pow(_r(), 1.3)


static func _opt(o: Dictionary, k: String, d):
	var v = o.get(k)
	return d if v == null else v


## One petal lying on a surface at height y (surface), optional tilt (rad sigma), stack lift.
func put(x: float, y: float, z: float, o: Dictionary = {}) -> bool:
	if n >= cap:
		return false
	var size: float = float(_opt(o, "size", 0.031)) * (0.8 + _r() * 0.45)
	var tilt: float = absf((_r() + _r() + _r() - 1.5) / 1.5) * float(_opt(o, "tilt", 0.28))
	var yaw: float = float(o.yaw) if o.get("yaw") != null else _r() * PI * 2.0
	var ta := _r() * PI * 2.0
	var ax := Vector3(cos(ta), 0.0, sin(ta))
	var qa := Quaternion(Vector3.UP, yaw)
	var qb := Quaternion(ax, tilt)
	qb = qb * qa
	var nrm = o.get("normal")
	if nrm != null:  # stuck onto a vertical surface: rotate +Y onto the normal
		var q0 := T.quat_from_unit_vectors(Vector3.UP, nrm)
		qb = q0 * qb
	var lift: float = float(_opt(o, "lift", 0.016)) + sin(tilt) * size * 0.5 + float(_opt(o, "stack", 0.0))
	var i3 := n * 3
	var i4 := n * 4
	if nrm != null:
		P[i3] = x + nrm.x * lift
		P[i3 + 1] = y + nrm.y * lift
		P[i3 + 2] = z + nrm.z * lift
	else:
		P[i3] = x
		P[i3 + 1] = y + lift
		P[i3 + 2] = z
	Q[i4] = qb.x
	Q[i4 + 1] = qb.y
	Q[i4 + 2] = qb.z
	Q[i4 + 3] = qb.w
	S[n] = size
	TN[n] = float(o.tone) if o.get("tone") != null else tone()
	n += 1
	return true


func gauss() -> float:
	return (_r() + _r() + _r() + _r() - 2.0) / 0.8165  # ~N(0,1)


## Place on the generic ground surface (env.surf -> y or null).
func on_ground(x: float, z: float, o: Dictionary = {}) -> bool:
	var y = env.surf.call(x, z, o.get("mode"))
	if y == null:
		return false
	return put(x, y, z, o)


## Gaussian ellipse cluster (sx along ang, sz across). pile: dome height (m) for stacking.
func cluster(cx: float, cz: float, sx: float, sz: float, ang: float, cnt: int, o: Dictionary = {}) -> int:
	var c := cos(ang)
	var s := sin(ang)
	var placed := 0
	var reject = o.get("reject")
	var pile = o.get("pile")
	for i in cnt:
		var u := gauss() * sx
		var v := gauss() * sz
		var x := cx + u * c - v * s
		var z := cz + u * s + v * c
		if reject != null and reject.call(x, z):
			continue
		var d2 := (u * u) / (sx * sx) + (v * v) / (sz * sz)
		var stack: float = pile * maxf(0.0, 1.0 - d2 / 2.2) * _r() if pile else 0.0
		var oo := o.duplicate()
		oo["stack"] = stack
		oo["tilt"] = 0.55 if pile else o.get("tilt")
		if on_ground(x, z, oo):
			placed += 1
	return placed


## Wind-blown streak: tapered, denser at the downwind head (ang = direction the wind pushes).
func streak(cx: float, cz: float, ang: float, length: float, width: float, cnt: int, o: Dictionary = {}) -> void:
	var c := cos(ang)
	var s := sin(ang)
	var reject = o.get("reject")
	for i in cnt:
		var u := pow(_r(), 0.7)  # 0 = tail, 1 = head (denser)
		var along := (u - 0.5) * length
		var w := width * (0.35 + 0.65 * sin(PI * minf(1.0, u * 1.1))) * 0.5
		var v := gauss() * w * 0.6 + sin(along * 1.7) * width * 0.12
		var x := cx + along * c - v * s
		var z := cz + along * s + v * c
		if reject != null and reject.call(x, z):
			continue
		on_ground(x, z, o)


## Strip along a segment with clumpy density; offsets drawn from band [o0, o1] on side(s).
func strip(ax_: float, az_: float, bx_: float, bz_: float, per_m: float, o: Dictionary = {}) -> void:
	var dx := bx_ - ax_
	var dz := bz_ - az_
	var length := sqrt(dx * dx + dz * dz)
	if length < 0.2:
		return
	var tx := dx / length
	var tz := dz / length
	var nx := -tz
	var nz := tx
	var ph1 := _r() * 10.0
	var ph2 := _r() * 10.0
	var ph3 := _r() * 10.0
	var cnt := int(T.js_round(length * per_m))
	var band: Array = o.get("band") if o.get("band") else [0.02, 0.3]
	var sides: Array = o.get("sides") if o.get("sides") else [-1, 1]
	var hug: float = float(_opt(o, "hug", 2.2))
	var reject = o.get("reject")
	for i in cnt:
		var s_al := _r() * length
		# clumps and gaps: product of slow sines, sharpened
		var d := maxf(0.0, 0.5 + 0.5 * sin(s_al * 0.83 + ph1) * sin(s_al * 0.29 + ph2) + 0.25 * sin(s_al * 2.1 + ph3))
		if _r() > pow(d, 1.6) * 1.25:
			continue
		var side: float = sides[floori(_r() * sides.size())]
		var off: float = band[0] + pow(_r(), hug) * (band[1] - band[0])
		var x := ax_ + tx * s_al + nx * off * side
		var z := az_ + tz * s_al + nz * off * side
		if reject != null and reject.call(x, z):
			continue
		on_ground(x, z, o)
	# small piles every few metres (against the edge)
	if o.get("piles"):
		var np := floori(length / float(o.piles))
		for k in np:
			if _r() > 0.6:
				continue
			var s_al := _r() * length
			var side: float = sides[floori(_r() * sides.size())]
			var off: float = band[0] + 0.06
			var x := ax_ + tx * s_al + nx * off * side
			var z := az_ + tz * s_al + nz * off * side
			var sx := 0.16 + _r() * 0.18
			var sz := 0.06 + _r() * 0.05
			var cn := 18 + floori(_r() * 26)
			var oo := o.duplicate()
			oo["pile"] = 0.012 + _r() * 0.014
			cluster(x, z, sx, sz, atan2(tz, tx), cn, oo)


## Uniform scatter in an axis-aligned rect.
func scatter(x0: float, z0: float, x1: float, z1: float, cnt: int, o: Dictionary = {}) -> void:
	var reject = o.get("reject")
	for i in cnt:
		var x := x0 + _r() * (x1 - x0)
		var z := z0 + _r() * (z1 - z0)
		if reject != null and reject.call(x, z):
			continue
		on_ground(x, z, o)


## Petals on a flat top (bench seat, table, vending top): local rect w x d rotated by rotY, at y.
func on_top(cx: float, y: float, cz: float, rot_y: float, w: float, d: float, cnt: int, o: Dictionary = {}) -> void:
	var c := cos(rot_y)
	var s := sin(rot_y)
	# gather a bit toward one end / the back edge (where the wind drops them)
	var bias_x := (_r() - 0.5) * 0.6
	var bias_z := -0.3 + _r() * 0.2
	for i in cnt:
		var lx := (_r() - 0.5) * w
		var lz := (_r() - 0.5) * d
		if _r() < 0.45:
			lx = (bias_x + gauss() * 0.18) * w * 0.5
			lz = (bias_z + gauss() * 0.25) * d * 0.5
		lx = maxf(-w / 2.0, minf(w / 2.0, lx))
		lz = maxf(-d / 2.0, minf(d / 2.0, lz))
		var x := cx + lx * c + lz * s
		var z := cz - lx * s + lz * c
		put(x, y, z, {"lift": 0.006, "tilt": 0.18, "size": _opt(o, "size", 0.031)})


## Round table top.
func on_disc(cx: float, y: float, cz: float, rad: float, cnt: int) -> void:
	for i in cnt:
		var a := _r() * PI * 2.0
		var d := sqrt(_r()) * rad
		put(cx + cos(a) * d, y, cz + sin(a) * d, {"lift": 0.005, "tilt": 0.15, "size": 0.027})


## Petals stuck to a vertical glass pane (window frame: centre x, y, z; rotY faces outward +Z local).
func on_pane(win: Dictionary, cnt: int) -> void:
	var c := cos(win.rotY)
	var s := sin(win.rotY)
	var nrm := Vector3(s, 0.0, c)
	for i in cnt:
		var lx: float
		var ly: float
		var u := _r()
		if u < 0.35:  # lower corners
			lx = (-1.0 if _r() < 0.5 else 1.0) * (win.w / 2.0 - absf(gauss()) * 0.25)
			ly = -win.h / 2.0 + absf(gauss()) * 0.3
		elif u < 0.55:  # along the sill
			lx = (_r() - 0.5) * win.w * 0.95
			ly = -win.h / 2.0 + _r() * 0.12
		else:
			lx = (_r() - 0.5) * win.w * 0.9
			ly = (_r() - 0.35) * win.h * 0.8
		lx = maxf(-win.w / 2.0 + 0.03, minf(win.w / 2.0 - 0.03, lx))
		ly = maxf(-win.h / 2.0 + 0.03, minf(win.h / 2.0 - 0.03, ly))
		var x: float = win.x + lx * c
		var z: float = win.z - lx * s
		var y: float = win.y + ly
		put(x, y, z, {"normal": nrm, "lift": 0.012, "tilt": 0.12, "size": 0.032})


func build(material):
	var geo: T.Geometry = Geo.plane(0.72, 1.0, 1, 1).rotate_x(-PI / 2.0)  # lying in XZ, normal +Y, length along Z
	var mesh := T.InstancedMesh.new(geo, material, maxi(1, n))
	var c_pale := T.color(env.colors.pale)
	var c_pink := T.color(env.colors.pink)
	var c_deep := T.color(env.colors.deep)
	var c_old := T.color(env.colors.old)
	for i in n:
		var p := Vector3(P[i * 3], P[i * 3 + 1], P[i * 3 + 2])
		var q := Quaternion(Q[i * 4], Q[i * 4 + 1], Q[i * 4 + 2], Q[i * 4 + 3])
		mesh.set_matrix_at(i, T.compose(p, q, Vector3.ONE * S[i]))
		var t: float = TN[i]
		var col: Color
		if t <= 1.0:
			col = c_pale.lerp(c_pink, t)
		elif t < 1.25:
			col = c_pink.lerp(c_deep, (t - 1.0) * 4.0)
		else:
			col = c_pink.lerp(c_old, 0.55 + (t - 1.3) * 1.5)
		mesh.set_color_at(i, col)
	mesh.count = n
	mesh.cast_shadow = false
	mesh.receive_shadow = true
	mesh.name = "petals-ground"
	return mesh
