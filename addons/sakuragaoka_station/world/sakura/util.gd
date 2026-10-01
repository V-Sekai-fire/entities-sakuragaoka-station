# sakura/util.js: a flat-array geometry builder, seeded 3D value noise, tapered tubes with
# parallel-transport frames and quadratic beziers. The tree generators do their vector math in
# float64 like three.js (V and Q here), since Godot's Vector3 and Quaternion are float32.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")


## V8's Math.hypot: scaled by the largest magnitude, Kahan-summed squares.
static func hypot2(a: float, b: float) -> float:
	a = absf(a)
	b = absf(b)
	var m := maxf(a, b)
	if m == 0.0:
		return 0.0
	var n := a / m
	var sum := n * n
	n = b / m
	var summand := n * n
	var pre := sum + summand
	return sqrt(pre) * m


static func hypot3(a: float, b: float, c: float) -> float:
	a = absf(a)
	b = absf(b)
	c = absf(c)
	var m := maxf(a, maxf(b, c))
	if m == 0.0:
		return 0.0
	var sum := 0.0
	var comp := 0.0
	var n := a / m
	var summand := n * n - comp
	var pre := sum + summand
	comp = (pre - sum) - summand
	sum = pre
	n = b / m
	summand = n * n - comp
	pre = sum + summand
	comp = (pre - sum) - summand
	sum = pre
	n = c / m
	summand = n * n - comp
	pre = sum + summand
	comp = (pre - sum) - summand
	sum = pre
	return sqrt(sum) * m


static func clamp01(v: float) -> float:
	return 0.0 if v < 0.0 else (1.0 if v > 1.0 else v)


static func mix3(a: Array, b: Array, t: float) -> Array:
	return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]


static func _srgb_to_linear(c: float) -> float:
	return c * 0.0773993808 if c < 0.04045 else pow(c * 0.9478672986 + 0.0521327014, 2.4)


## A hex colour as linear rgb (THREE.Color(h) under colour management).
static func hex(h: String) -> Array:
	var v := h.substr(1).hex_to_int()
	return [_srgb_to_linear(((v >> 16) & 255) / 255.0), _srgb_to_linear(((v >> 8) & 255) / 255.0), _srgb_to_linear((v & 255) / 255.0)]


## three.js Vector3 in float64.
class V extends RefCounted:
	var x := 0.0
	var y := 0.0
	var z := 0.0

	func _init(a: float = 0.0, b: float = 0.0, c: float = 0.0) -> void:
		x = a
		y = b
		z = c

	func set3(a: float, b: float, c: float) -> V:
		x = a
		y = b
		z = c
		return self

	func copy(o: V) -> V:
		x = o.x
		y = o.y
		z = o.z
		return self

	func clone() -> V:
		return V.new(x, y, z)

	func add(o: V) -> V:
		x += o.x
		y += o.y
		z += o.z
		return self

	func sub(o: V) -> V:
		x -= o.x
		y -= o.y
		z -= o.z
		return self

	func sub_vectors(a: V, b: V) -> V:
		x = a.x - b.x
		y = a.y - b.y
		z = a.z - b.z
		return self

	func add_scaled(o: V, s: float) -> V:
		x += o.x * s
		y += o.y * s
		z += o.z * s
		return self

	func mul(s: float) -> V:
		x *= s
		y *= s
		z *= s
		return self

	## divideScalar: a multiply by the reciprocal, as three.js does
	func div(s: float) -> V:
		return mul(1.0 / s)

	func length() -> float:
		return sqrt(x * x + y * y + z * z)

	func length_sq() -> float:
		return x * x + y * y + z * z

	func normalize() -> V:
		var l := length()
		return div(l if l != 0.0 else 1.0)

	func dot(o: V) -> float:
		return x * o.x + y * o.y + z * o.z

	func distance_to_squared(o: V) -> float:
		var dx := x - o.x
		var dy := y - o.y
		var dz := z - o.z
		return dx * dx + dy * dy + dz * dz

	func distance_to(o: V) -> float:
		return sqrt(distance_to_squared(o))

	func lerp(o: V, a: float) -> V:
		x += (o.x - x) * a
		y += (o.y - y) * a
		z += (o.z - z) * a
		return self

	func lerp_vectors(a: V, b: V, t: float) -> V:
		x = a.x + (b.x - a.x) * t
		y = a.y + (b.y - a.y) * t
		z = a.z + (b.z - a.z) * t
		return self

	func cross_vectors(a: V, b: V) -> V:
		var ax := a.x
		var ay := a.y
		var az := a.z
		var bx := b.x
		var by := b.y
		var bz := b.z
		x = ay * bz - az * by
		y = az * bx - ax * bz
		z = ax * by - ay * bx
		return self

	func set_y(v: float) -> V:
		y = v
		return self


## three.js Quaternion in float64 (only what the kernels need).
class Q extends RefCounted:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var w := 1.0

	func clone() -> Q:
		var q := Q.new()
		q.x = x
		q.y = y
		q.z = z
		q.w = w
		return q

	func normalize() -> Q:
		var l := sqrt(x * x + y * y + z * z + w * w)
		if l == 0.0:
			x = 0.0
			y = 0.0
			z = 0.0
			w = 1.0
		else:
			l = 1.0 / l
			x = x * l
			y = y * l
			z = z * l
			w = w * l
		return self

	func set_from_unit_vectors(a: V, b: V) -> Q:
		var r := a.dot(b) + 1.0
		if r < 2.220446049250313e-16:
			r = 0.0
			if absf(a.x) > absf(a.z):
				x = -a.y
				y = a.x
				z = 0.0
				w = r
			else:
				x = 0.0
				y = -a.z
				z = a.y
				w = r
		else:
			x = a.y * b.z - a.z * b.y
			y = a.z * b.x - a.x * b.z
			z = a.x * b.y - a.y * b.x
			w = r
		return normalize()

	func set_from_axis_angle(axis: V, angle: float) -> Q:
		var half := angle / 2.0
		var s := sin(half)
		x = axis.x * s
		y = axis.y * s
		z = axis.z * s
		w = cos(half)
		return self

	## this = this * b
	func multiply(b: Q) -> Q:
		var qax := x
		var qay := y
		var qaz := z
		var qaw := w
		x = qax * b.w + qaw * b.x + qay * b.z - qaz * b.y
		y = qay * b.w + qaw * b.y + qaz * b.x - qax * b.z
		z = qaz * b.w + qaw * b.z + qax * b.y - qay * b.x
		w = qaw * b.w - qax * b.x - qay * b.y - qaz * b.z
		return self

	## Matrix4.makeRotationFromQuaternion(q.invert()).elements[0..10] (column major)
	func inverse_rotation_elements() -> PackedFloat64Array:
		var qx := -x
		var qy := -y
		var qz := -z
		var qw := w
		var x2 := qx + qx
		var y2 := qy + qy
		var z2 := qz + qz
		var xx := qx * x2
		var xy := qx * y2
		var xz := qx * z2
		var yy := qy * y2
		var yz := qy * z2
		var zz := qz * z2
		var wx := qw * x2
		var wy := qw * y2
		var wz := qw * z2
		var e := PackedFloat64Array()
		e.resize(11)
		e[0] = 1.0 - (yy + zz)
		e[1] = xy + wz
		e[2] = xz - wy
		e[4] = xy - wz
		e[5] = 1.0 - (xx + zz)
		e[6] = yz + wx
		e[8] = xz + wy
		e[9] = yz - wx
		e[10] = 1.0 - (xx + yy)
		return e


## Accumulates vertices (position, normal, uv, colour) and indices; builds one geometry. Values are
## stored as float32 straight away (the original converts once, at build).
class GeoBuilder extends RefCounted:
	var p := PackedFloat32Array()
	var n := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var c := PackedFloat32Array()
	var i := PackedInt32Array()
	var count := 0

	func v(x: float, y: float, z: float, nx: float, ny: float, nz: float, u: float, w: float, r: float = 1.0, g: float = 1.0, b: float = 1.0) -> int:
		p.append(x)
		p.append(y)
		p.append(z)
		n.append(nx)
		n.append(ny)
		n.append(nz)
		uv.append(u)
		uv.append(w)
		c.append(r)
		c.append(g)
		c.append(b)
		count += 1
		return count - 1

	func t(a: int, b: int, cc: int) -> void:
		i.append(a)
		i.append(b)
		i.append(cc)

	func tris() -> int:
		return i.size() / 3

	func build(with_color: bool = true) -> T.Geometry:
		if count == 0:
			return null
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(p, 3))
		g.set_attribute("normal", T.Attr.new(n, 3))
		g.set_attribute("uv", T.Attr.new(uv, 2))
		if with_color:
			g.set_attribute("color", T.Attr.new(c, 3))
		g.set_index(i)
		g.compute_bounding_box()
		return g


## Seeded 3D value noise in [-1, 1] (smooth, cheap).
class ValueNoise extends RefCounted:
	var perm := PackedInt32Array()
	var val := PackedFloat32Array()

	func _init(rng) -> void:
		var p := []
		for k in 256:
			p.append(k)
		for k in range(255, 0, -1):
			var j := floori(rng.f() * (k + 1))
			var t = p[k]
			p[k] = p[j]
			p[j] = t
		perm.resize(512)
		for k in 512:
			perm[k] = p[k & 255]
		val.resize(256)
		for k in 256:
			val[k] = rng.f() * 2.0 - 1.0

	func n3(x: float, y: float, z: float) -> float:
		var ix := floori(x)
		var iy := floori(y)
		var iz := floori(z)
		var tx := x - ix
		var ty := y - iy
		var tz := z - iz
		var fx := tx * tx * (3.0 - 2.0 * tx)
		var fy := ty * ty * (3.0 - 2.0 * ty)
		var fz := tz * tz * (3.0 - 2.0 * tz)
		var px0 := perm[ix & 255]
		var px1 := perm[(ix + 1) & 255]
		var y0 := iy & 255
		var y1 := (iy + 1) & 255
		var z0 := iz & 255
		var z1 := (iz + 1) & 255
		var p00 := perm[px0 + y0]
		var p10 := perm[px1 + y0]
		var p01 := perm[px0 + y1]
		var p11 := perm[px1 + y1]
		var a: float = val[perm[p00 + z0]]
		var b: float = val[perm[p10 + z0]]
		var c: float = val[perm[p01 + z0]]
		var d: float = val[perm[p11 + z0]]
		var e: float = val[perm[p00 + z1]]
		var g: float = val[perm[p10 + z1]]
		var h: float = val[perm[p01 + z1]]
		var k: float = val[perm[p11 + z1]]
		var x1 := a + (b - a) * fx
		var x2 := c + (d - c) * fx
		var x3 := e + (g - e) * fx
		var x4 := h + (k - h) * fx
		var yy1 := x1 + (x2 - x1) * fy
		var yy2 := x3 + (x4 - x3) * fy
		return yy1 + (yy2 - yy1) * fz

	func fbm(x: float, y: float, z: float) -> float:
		return n3(x, y, z) * 0.62 + n3(x * 2.13 + 5.1, y * 2.13 + 1.7, z * 2.13 + 9.3) * 0.38


## Quadratic bezier sampled into n + 1 points.
static func bezier(a: V, c: V, b: V, n: int) -> Array:
	var out := []
	for i in n + 1:
		var t := float(i) / n
		var u := 1.0 - t
		out.append(V.new(u * u * a.x + 2.0 * u * t * c.x + t * t * b.x, u * u * a.y + 2.0 * u * t * c.y + t * t * b.y, u * u * a.z + 2.0 * u * t * c.z + t * t * b.z))
	return out


## Tapered tube through pts with radii (m) and seg radial segments, appended to the builder.
## u_tile / v_tile: metres per texture repeat around / along. opts: capEnd, v0, color.
static func tube(B: GeoBuilder, pts: Array, radii: Array, seg: int, u_tile: float = 0.8, v_tile: float = 1.6, opts: Dictionary = {}) -> void:
	var n := pts.size()
	if n < 2:
		return
	var avg_r := 0.0
	for r in radii:
		avg_r += r
	avg_r /= radii.size()
	var u_rep: float = maxf(1.0, T.js_round((2.0 * PI * avg_r) / u_tile))
	var T0 := V.new().sub_vectors(pts[1], pts[0]).normalize()
	var N := V.new(0, 1, 0) if absf(T0.y) < 0.9 else V.new(1, 0, 0)
	N.sub(V.new().copy(T0).mul(N.dot(T0))).normalize()
	var v_acc: float = opts.get("v0", 0.0) if opts.get("v0") else 0.0
	var col: Array = opts.get("color", [1.0, 1.0, 1.0]) if opts.get("color") != null else [1.0, 1.0, 1.0]
	var base := B.count
	var tt := V.new()
	var bb := V.new()
	var tmp := V.new()
	for i in n:
		var pi: V = pts[i]
		if i == 0:
			tt.copy(T0)
		elif i == n - 1:
			tt.sub_vectors(pi, pts[i - 1]).normalize()
		else:
			tt.sub_vectors(pts[i + 1], pts[i - 1]).normalize()
		# parallel transport
		N.sub(tmp.copy(tt).mul(N.dot(tt))).normalize()
		bb.cross_vectors(tt, N).normalize()
		if i > 0:
			v_acc += pi.distance_to(pts[i - 1]) / v_tile
		var r: float = radii[i]
		# the taper's slope tilts the normal a little along the axis
		var dr: float = (radii[i] - radii[i + 1]) / maxf(1e-3, pi.distance_to(pts[i + 1])) if i < n - 1 else 0.0
		for j in seg + 1:
			var a := (float(j) / seg) * PI * 2.0
			var ca := cos(a)
			var sa := sin(a)
			var nx0 := N.x * ca + bb.x * sa
			var ny0 := N.y * ca + bb.y * sa
			var nz0 := N.z * ca + bb.z * sa
			var nx := nx0 + tt.x * dr * 0.6
			var ny := ny0 + tt.y * dr * 0.6
			var nz := nz0 + tt.z * dr * 0.6
			var nl := hypot3(nx, ny, nz)
			if nl == 0.0:
				nl = 1.0
			B.v(pi.x + nx0 * r, pi.y + ny0 * r, pi.z + nz0 * r, nx / nl, ny / nl, nz / nl, (float(j) / seg) * u_rep, v_acc, col[0], col[1], col[2])
	var row := seg + 1
	for i in n - 1:
		for j in seg:
			var a := base + i * row + j
			var b := a + 1
			var c := a + row
			var d := c + 1
			B.t(a, b, c)
			B.t(b, d, c)
	# close the tip with a small cone point
	var rl: float = radii[n - 1]
	if opts.get("capEnd", false) and rl > 0.004:
		var pl: V = pts[n - 1]
		var tip := B.v(pl.x + tt.x * rl * 0.8, pl.y + tt.y * rl * 0.8, pl.z + tt.z * rl * 0.8, tt.x, tt.y, tt.z, 0.5, v_acc + 0.05)
		var last := base + (n - 1) * row
		for j in seg:
			B.t(last + j, last + j + 1, tip)


## Soft-quantised 4-band colour for tone t in [0, 1] (matches the blossom shader's bands).
static func band_color(bands: Array, t: float) -> Array:
	t = clamp01(t)
	var w := 0.035
	var c: Array = bands[0]
	for k in range(1, 4):
		var e := k / 4.0
		var a := clamp01((t - (e - w)) / (2.0 * w))
		var s := a * a * (3.0 - 2.0 * a)
		if s > 0.0:
			c = mix3(c, bands[k], s)
	return c.duplicate()
