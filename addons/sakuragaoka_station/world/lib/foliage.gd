# lib/foliage.js: smooth cel-shaded foliage (shrubs, hedges, topiary, cloud-pruned trees). Welded,
# smoothly displaced "cloud" surfaces built from round leaf puffs, colours baked into vertices so every
# shrub shares one material. Geometries are cached by their options, as in the original.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")

const SHRUB_COLORS := {
	"boxwood": {"top": "#b3d27f", "mid": "#78a85c", "base": "#4d7c5b"},
	"azalea": {"top": "#a7c878", "mid": "#6b9b58", "base": "#46735a"},
	"camellia": {"top": "#8fbd6e", "mid": "#5b8f55", "base": "#3d6a57"},
	"pine": {"top": "#8db36c", "mid": "#5f8a58", "base": "#41665a"},
	"young": {"top": "#c6dc8c", "mid": "#8ab866", "base": "#5a8a5c"},
	"privet": {"top": "#a9cc78", "mid": "#6f9f5a", "base": "#4a7859"},
	"maple": {"top": "#c2da8a", "mid": "#94bd6c", "base": "#62905e"},
	"olive": {"top": "#b9c79e", "mid": "#95a882", "base": "#6c7f6c"},
	"dark": {"top": "#83ad69", "mid": "#557f55", "base": "#3a6353"},
	"veg": {"top": "#bcd98a", "mid": "#88b766", "base": "#5f8d5a"},
}
const FLOWER_COLORS := {
	"azalea": ["#ee8fb6", "#e8739f", "#f4a9c6", "#dd6a98"],
	"azaleaWhite": ["#f6f1f2", "#fbe6ee", "#f3eef0"],
	"azaleaMix": ["#ee8fb6", "#e8739f", "#f6f1f2", "#f4a9c6"],
	"hydrangea": ["#a9b8e6", "#b9b0e0", "#9fc3e3", "#c7b7e4"],
	"camellia": ["#d9485a", "#e0606f", "#ef8fa6"],
	"spirea": ["#f7f5f0", "#eef0ea"],
	"yellow": ["#f2cf4a", "#f5dc6e"],
	"mixed": ["#f2c230", "#e8697a", "#f4f0e6", "#b48ad6", "#f29a5c", "#ef9fbe"],
}

static var _ico := {}
static var _cache := {}
static var _fmat := {}


static func hash3(x: int, y: int, z: int, s: int) -> float:
	var h: int = Rng.imul(Rng.to_i32(x) ^ Rng.imul(s, 0x27d4eb2d), 0x85ebca6b) ^ Rng.imul(Rng.to_i32(y), 0xc2b2ae35) ^ Rng.imul(Rng.to_i32(z), 0x165667b1)
	h = Rng.to_i32(h)
	h = Rng.to_i32(h ^ ((h & 0xFFFFFFFF) >> 15))
	h = Rng.imul(h, 0x2c1b3c6d)
	h = Rng.to_i32(h ^ ((h & 0xFFFFFFFF) >> 12))
	return float(h & 0xFFFFFFFF) / 4294967296.0


static func vnoise(x: float, y: float, z: float, s: int) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var zi := floori(z)
	var fx := x - xi
	var fy := y - yi
	var fz := z - zi
	var u := fx * fx * (3.0 - 2.0 * fx)
	var v := fy * fy * (3.0 - 2.0 * fy)
	var w := fz * fz * (3.0 - 2.0 * fz)
	var c000 := hash3(xi, yi, zi, s)
	var c100 := hash3(xi + 1, yi, zi, s)
	var c010 := hash3(xi, yi + 1, zi, s)
	var c110 := hash3(xi + 1, yi + 1, zi, s)
	var c001 := hash3(xi, yi, zi + 1, s)
	var c101 := hash3(xi + 1, yi, zi + 1, s)
	var c011 := hash3(xi, yi + 1, zi + 1, s)
	var c111 := hash3(xi + 1, yi + 1, zi + 1, s)
	var a := lerpf(lerpf(c000, c100, u), lerpf(c010, c110, u), v)
	var b := lerpf(lerpf(c001, c101, u), lerpf(c011, c111, u), v)
	return lerpf(a, b, w)


## billowy cloud bumps in [0, 1]
static func billow(x: float, y: float, z: float, s: int) -> float:
	var a := 0.0
	var amp := 0.62
	var f := 1.0
	for o in 3:
		a += amp * (1.0 - absf(vnoise(x * f, y * f, z * f, s + o * 17) * 2.0 - 1.0))
		amp *= 0.45
		f *= 2.03
	return a / 1.05


static func smooth(a: float, b: float, x: float) -> float:
	var t := minf(1.0, maxf(0.0, (x - a) / (b - a)))
	return t * t * (3.0 - 2.0 * t)


static func flower_spec(f):
	if f == null or (f is bool and not f) or (f is String and f == ""):
		return null
	if f is bool:
		return {"colors": FLOWER_COLORS.azalea, "density": 1.0, "size": 1.0}
	if f is String:
		return {"colors": FLOWER_COLORS.get(f, FLOWER_COLORS.azalea), "density": 1.0, "size": 1.0}
	var cols = f.get("colors")
	if cols == null:
		cols = FLOWER_COLORS.get(f.get("kind", ""), FLOWER_COLORS.azalea)
	return {"colors": cols, "density": f.get("density", 1.0), "size": f.get("size", 1.0), "top": f.get("top", 0.3), "xRange": f.get("xRange")}


static func ico_base(detail: int) -> T.Geometry:
	if not _ico.has(detail):
		var g := Geo.icosahedron(1, detail)
		g.delete_attribute("uv")
		g.delete_attribute("normal")
		_ico[detail] = Geo.merge_vertices(g, 1e-5)
	return (_ico[detail] as T.Geometry).clone()


## Dart-thrown puff centres on the surface vertices; ok(i) filters candidates. Returns [x, y, z, R].
static func sample_puffs(P: PackedFloat32Array, n: int, cell: float, seed: int, ok: Callable) -> Array:
	var order := []
	for i in n:
		order.append([hash3(i, 7, 3, seed), i])
	T.stable_sort(order, func(a, b): return a[0] - b[0])
	var out := []
	for e in order:
		var i: int = e[1]
		if ok.is_valid() and not ok.call(i):
			continue
		var x := P[i * 3]
		var y := P[i * 3 + 1]
		var z := P[i * 3 + 2]
		var md := cell * (0.8 + 0.3 * hash3(i, 1, 9, seed))
		var md2 := md * md
		var good := true
		for q in out:
			var dx: float = q[0] - x
			var dy: float = q[1] - y
			var dz: float = q[2] - z
			if dx * dx + dy * dy + dz * dz < md2:
				good = false
				break
		if good:
			out.append([x, y, z, cell * (0.66 + 0.26 * hash3(i, 5, 2, seed))])
	return out


## Smooth union of dome profiles at (x, y, z): [h (0 valley .. 1 puff centre), best - second].
static func puff_field(list: Array, x: float, y: float, z: float, shape: float = 0.55) -> Array:
	var s := 0.0
	var h1 := 0.0
	var h2 := 0.0
	for q in list:
		var dx: float = q[0] - x
		var dy: float = q[1] - y
		var dz: float = q[2] - z
		var d2: float = (dx * dx + dy * dy + dz * dz) / (q[3] * q[3])
		if d2 >= 1.0:
			continue
		var h := pow(1.0 - d2, shape)
		s += exp(10.0 * h)
		if h > h1:
			h2 = h1
			h1 = h
		elif h > h2:
			h2 = h
	var hs := maxf(0.0, minf(1.0, log(s) / 10.0)) if s > 0.0 else 0.0
	return [hs, h1 - h2]


## Spatial hash for puff lookups (big hedges): returns a Callable (x, y, z) -> nearby puffs.
static func puff_grid(puffs: Array, cell: float) -> Callable:
	var m := {}
	var c := cell * 1.1
	var key := func(i: int, j: int, k: int) -> int:
		return Rng.to_i32(Rng.to_i32(i * 73856093) ^ Rng.to_i32(j * 19349663) ^ Rng.to_i32(k * 83492791))
	for q in puffs:
		var i := floori(q[0] / c)
		var j := floori(q[1] / c)
		var k := floori(q[2] / c)
		for a in [-1, 0, 1]:
			for b in [-1, 0, 1]:
				for d in [-1, 0, 1]:
					var kk: int = key.call(i + a, j + b, k + d)
					if not m.has(kk):
						m[kk] = []
					m[kk].append(q)
	var empty := []
	return func(x: float, y: float, z: float) -> Array:
		return m.get(key.call(floori(x / c), floori(y / c), floori(z / c)), empty)


static func _clerp(a: Color, b: Color, t: float) -> Color:
	return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)


## Vertex colours: vertical gradient, puff light / valley dark, leaf-clump patches.
static func bake_colors(g: T.Geometry, o: Dictionary) -> void:
	var pos := g.position()
	var nor: T.Attr = g.attributes.normal
	var n := pos.count()
	var C: Dictionary = o.colors if o.get("colors") != null else {}
	var top := T.color(C.get("top", "#a9cf7c"))
	var mid := T.color(C.get("mid", "#6fa35c"))
	var low := T.color(C.get("base", "#4a7a5a"))
	var col := PackedFloat32Array()
	col.resize(n * 3)
	var H: float = o.H
	var seed: int = o.seed
	var ph = o.get("puffH")
	var vl = o.get("valley")
	var dark: float = o.dark if o.get("dark") != null else 0.2
	for i in n:
		var x := pos.get_x(i)
		var y := pos.get_y(i)
		var z := pos.get_z(i)
		var t := y / H
		var c: Color
		if t > 0.55:
			c = _clerp(mid, top, smooth(0.55, 1.0, t))
		else:
			c = _clerp(low, mid, smooth(0.0, 0.55, t))
		var v := vnoise(x * 1.7 + 3.0, y * 1.7, z * 1.7 - 2.0, seed + 91) - 0.5
		c = T.offset_hsl(c, v * 0.02, v * 0.05, v * 0.05)
		if ph != null:
			var h: float = ph[i]
			var ny := nor.get_y(i)
			if h > 0.55 and ny > 0.1 and t > 0.3:
				c = _clerp(c, top, 0.28 * smooth(0.55, 0.95, h) * smooth(0.1, 0.6, ny))
			var k := 1.0 - dark + dark * smooth(0.05, 0.5, h)
			c = Color(c.r * k, c.g * k, c.b * k)
			if vl != null and vl[i] < 0.12 and h < 0.45:
				c = Color(c.r * 0.93, c.g * 0.93, c.b * 0.93)
		else:
			var cl := billow(x * 3.0 + 1.3, y * 3.0 - 2.2, z * 3.0 + 0.7, seed + 53)
			if cl > 0.66 and t > 0.35:
				c = _clerp(c, top, 0.35)
			elif cl < 0.3 and t < 0.7:
				c = Color(c.r * 0.86, c.g * 0.86, c.b * 0.86)
		if o.get("tint") != null:
			c = _clerp(c, o.tint, o.get("tintAmt", 0.1))
		col[i * 3] = c.r
		col[i * 3 + 1] = c.g
		col[i * 3 + 2] = c.b
	g.set_attribute("color", T.Attr.new(col, 3))


## Drops triangles that lie entirely below y0 (hidden under the ground).
static func cut_below(g: T.Geometry, y0: float) -> void:
	var idx := g.index
	var pos := g.position()
	var keep := PackedInt32Array()
	var t := 0
	while t < idx.size():
		var a := idx[t]
		var b := idx[t + 1]
		var c := idx[t + 2]
		if maxf(pos.get_y(a), maxf(pos.get_y(b), pos.get_y(c))) >= y0:
			keep.append(a)
			keep.append(b)
			keep.append(c)
		t += 3
	g.set_index(keep)


static func blend_normals(g: T.Geometry, base: PackedFloat32Array, blend: float) -> void:
	var nor: T.Attr = g.attributes.normal
	for i in nor.count():
		var nx := nor.get_x(i)
		var ny := nor.get_y(i)
		var nz := nor.get_z(i)
		nx += (base[i * 3] - nx) * blend
		ny += (base[i * 3 + 1] - ny) * blend
		nz += (base[i * 3 + 2] - nz) * blend
		var l := sqrt(nx * nx + ny * ny + nz * nz)
		if l > 0.0:
			nx /= l
			ny /= l
			nz /= l
		nor.set_xyz(i, nx, ny, nz)


static func _k(v) -> String:
	return "null" if v == null else str(v)


## Smooth lumpy shrub geometry of round leaf puffs (see lib/foliage.js shrubGeometry).
static func shrub_geometry(o: Dictionary = {}) -> T.Geometry:
	var rx: float = o.get("rx", 0.6)
	var ry: float = o.get("ry", 0.5)
	var rz: float = o.get("rz", 0.6)
	var lumps: float = o.get("lumps", 0.22) if o.get("lumps") != null else 0.22
	var freq: float = o.get("freq", 2.2) if o.get("freq") != null else 2.2
	var square: float = o.get("square", 1.0) if o.get("square") != null else 1.0
	var seed := int(o.get("seed", 1) if o.get("seed") != null else 1)
	var size := maxf(rx, maxf(ry, rz))
	var reff := (rx + ry + rz) / 3.0
	var detail = o.get("detail")
	if detail == null:
		var sp: float
		if o.get("spacing") != null:
			sp = o.spacing
		elif o.get("seg") != null:
			sp = (PI * 2.0 * reff) / float(o.seg)
		else:
			sp = 0.075
		detail = T.js_round((reff * 1.1) / sp) - 1
	var di: int = maxi(1, mini(int(o.get("maxDetail", 11)), int(detail)))
	detail = di
	var spacing := (reff * 1.1) / (di + 1)
	var puff: float = o.puff if o.get("puff") != null else maxf(spacing * 3.6, minf(0.55, 0.16 + size * 0.3))
	var puff_amp: float = o.puffAmp if o.get("puffAmp") != null else 0.42
	var puff_shape: float = o.puffShape if o.get("puffShape") != null else 0.5
	var flat: bool = o.flatBottom if o.get("flatBottom") != null else true
	var cut: bool = o.cutBottom if o.get("cutBottom") != null else true
	var key := "s2|%s|%s|%s|%s|%s|%s|%d|%d|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [rx, ry, rz, lumps, freq, square, seed, detail, flat,
		_k(o.get("colors")), puff, puff_amp, _k(o.get("normalBlend")), cut, _k(o.get("scallop")), puff_shape, _k(o.get("dark"))]
	if _cache.has(key):
		return _cache[key]
	var g := ico_base(di)
	var pos := g.position()
	var n := pos.count()
	var base := PackedFloat32Array()
	base.resize(n * 3)
	for i in n:
		var px := pos.get_x(i)
		var py := pos.get_y(i)
		var pz := pos.get_z(i)
		if square > 1.0:
			var e := 2.0 / square
			px = signf(px) * pow(absf(px), e)
			py = signf(py) * pow(absf(py), e)
			pz = signf(pz) * pow(absf(pz), e)
		var l := sqrt(px * px + py * py + pz * pz)
		var dx := px / l
		var dy := py / l
		var dz := pz / l
		var bump := billow(dx * freq * size + 11.3, dy * freq * size + 3.7, dz * freq * size - 5.1, seed)
		var r := 1.0 + lumps * (bump - 0.55)
		if o.get("scallop"):
			var sf := 3.2 * size
			r += float(o.scallop) * (billow(dx * sf + 2.1, dy * sf - 7.3, dz * sf + 4.4, seed + 37) - 0.5)
		px *= r
		py *= r
		pz *= r
		px *= rx
		py *= ry
		pz *= rz
		if flat and py < -ry * 0.55:
			py = -ry * 0.55 + (py + ry * 0.55) * 0.25
		pos.set_xyz(i, px, py + ry * 0.55, pz)
		var nn := Vector3(px / (rx * rx), py / (ry * ry), pz / (rz * rz)).normalized()
		if square > 1.0:
			nn = Vector3(signf(px) * pow(absf(px / rx), square - 1.0) / rx, signf(py) * pow(absf(py / ry), square - 1.0) / ry,
				signf(pz) * pow(absf(pz / rz), square - 1.0) / rz).normalized()
		base[i * 3] = nn.x
		base[i * 3 + 1] = nn.y
		base[i * 3 + 2] = nn.z
	var H := ry * 2.0 * 0.86
	var ph = null
	var vl = null
	if puff > 0.0 and puff_amp > 0.0:
		var P := pos.array
		var puffs := sample_puffs(P, n, puff, seed + 3, func(i): return P[i * 3 + 1] > H * 0.08)
		ph = PackedFloat32Array()
		ph.resize(n)
		vl = PackedFloat32Array()
		vl.resize(n)
		var amp := puff_amp * puff
		for i in n:
			var x := P[i * 3]
			var y := P[i * 3 + 1]
			var z := P[i * 3 + 2]
			var f := puff_field(puffs, x, y, z, puff_shape)
			ph[i] = f[0]
			vl[i] = f[1]
			var fade := smooth(0.0, H * 0.22, y)
			var dd: float = amp * (f[0] - 0.5) * fade
			pos.set_xyz(i, x + base[i * 3] * dd, y + base[i * 3 + 1] * dd * 0.9, z + base[i * 3 + 2] * dd)
	g.compute_vertex_normals()
	blend_normals(g, base, o.normalBlend if o.get("normalBlend") != null else (0.6 if ph != null else 0.55))
	bake_colors(g, {"colors": o.get("colors"), "H": H, "seed": seed, "puffH": ph, "valley": vl, "dark": o.get("dark")})
	if cut:
		cut_below(g, -0.004)
	var uv := PackedFloat32Array()
	uv.resize(pos.count() * 2)
	g.set_attribute("uv", T.Attr.new(uv, 2))
	g.compute_bounding_box()
	g.user_data["foliage"] = {"H": H, "spacing": spacing, "puff": puff}
	_cache[key] = g
	return g


## Clipped hedge: a lofted rounded box with gentle leaf puffs; length along local X, open bottom.
static func hedge_geometry(o: Dictionary = {}) -> T.Geometry:
	var Lh: float = o.get("length", 3.0) if o.get("length") != null else 3.0
	var h: float = o.get("h", 1.0) if o.get("h") != null else 1.0
	var d: float = o.get("d", 0.7) if o.get("d") != null else 0.7
	var seed := int(o.get("seed", 3) if o.get("seed") != null else 3)
	var sp: float = o.spacing if o.get("spacing") != null else 0.13
	var ground = o.get("ground")
	var key = null
	if ground == null:
		key = "h2|%s|%s|%s|%d|%s|%s|%s|%s|%s|%s|%s|%s" % [Lh, h, d, seed, sp, _k(o.get("colors")), _k(o.get("puff")), _k(o.get("puffAmp")),
			_k(o.get("lumps")), _k(o.get("round")), _k(o.get("normalBlend")), _k(o.get("dark"))]
		if _cache.has(key):
			return _cache[key]
	var a := d / 2.0
	var r_top := minf(h * 0.45, maxf(0.14, a * (o.round if o.get("round") != null else 0.85)))
	var yc := h - r_top
	var y0 := -0.06
	var cap_r := minf(a * 1.05, Lh * 0.45)
	var xs := []
	var n_cap := maxi(4, ceili((cap_r * PI / 2.0) / sp) + 1)
	for k in n_cap:
		var t := cos((float(k) / n_cap) * PI / 2.0)
		xs.append([-Lh / 2.0 + cap_r * (1.0 - t), t])
	var mid0 := -Lh / 2.0 + cap_r
	var mid1 := Lh / 2.0 - cap_r
	var nm := maxi(1, roundi((mid1 - mid0) / sp))
	for k in nm + 1:
		xs.append([mid0 + (mid1 - mid0) * k / nm, 0.0])
	for k in range(n_cap - 1, -1, -1):
		var t := cos((float(k) / n_cap) * PI / 2.0)
		xs.append([Lh / 2.0 - cap_r * (1.0 - t), t])
	var n_side := maxi(2, roundi((yc - y0) / (sp * 1.05)))
	var n_arc: int = o.arcSeg if o.get("arcSeg") != null else maxi(8, roundi((PI * (a + r_top) / 2.0) / (sp * 0.72)))
	var prof := []
	for k in n_side:
		prof.append([1.0, y0 + (yc - y0) * k / n_side, -1.0])
	var ne := 2.0 / 3.2
	var sg := func(v: float) -> float: return signf(v) * pow(absf(v), ne)
	for k in n_arc + 1:
		var th := (float(k) / n_arc) * PI
		prof.append([sg.call(cos(th)), yc + r_top * sg.call(sin(th)), th])
	for k in range(n_side - 1, -1, -1):
		prof.append([-1.0, y0 + (yc - y0) * k / n_side, -2.0])
	var nr := xs.size()
	var np := prof.size()
	var P := PackedFloat32Array()
	P.resize(nr * np * 3)
	for i in nr:
		var x: float = xs[i][0]
		var t: float = xs[i][1]
		var e := sqrt(maxf(0.0, 1.0 - t * t)) if t > 0.0 else 1.0
		var ey := pow(maxf(0.0, 1.0 - pow(t, 2.4)), 1.0 / 2.4) if t > 0.0 else 1.0
		for j in np:
			var zu: float = prof[j][0]
			var y: float = prof[j][1]
			var th: float = prof[j][2]
			var yy := y
			if th >= 0.0:
				yy = yc + (y - yc) * (0.55 + 0.45 * ey)
			else:
				yy = minf(y, yc)
			var k3 := (i * np + j) * 3
			P[k3] = x
			P[k3 + 1] = yy
			P[k3 + 2] = zu * a * e
	var idx := PackedInt32Array()
	for i in nr - 1:
		for j in np - 1:
			var A := i * np + j
			var B := A + 1
			var Cc := A + np
			var D := Cc + 1
			idx.append(A); idx.append(Cc); idx.append(B); idx.append(B); idx.append(Cc); idx.append(D)
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(P.duplicate(), 3))
	g.set_index(idx)
	g.compute_vertex_normals()
	var jm := n_side + roundi(n_arc / 2.0)
	var im := floori(nr / 2.0)
	if (g.attributes.normal as T.Attr).get_y(im * np + jm) < 0.0:
		var ia := g.index
		var t := 0
		while t < ia.size():
			var tmp := ia[t + 1]
			ia[t + 1] = ia[t + 2]
			ia[t + 2] = tmp
			t += 3
		g.set_index(ia)
		g.compute_vertex_normals()
	var pos := g.position()
	var n := pos.count()
	var base: PackedFloat32Array = (g.attributes.normal as T.Attr).array.duplicate()
	var puff: float = o.puff if o.get("puff") != null else maxf(sp * 3.2, minf(0.5, 0.26 + h * 0.12))
	var amp: float = (o.puffAmp if o.get("puffAmp") != null else 0.2) * puff
	var lumps: float = o.lumps if o.get("lumps") != null else 0.07
	var puffs := sample_puffs(P, n, puff, seed + 3, func(i): return P[i * 3 + 1] > h * 0.12)
	var grid := puff_grid(puffs, puff)
	var ph := PackedFloat32Array()
	ph.resize(n)
	var vl := PackedFloat32Array()
	vl.resize(n)
	for i in n:
		var x := P[i * 3]
		var y := P[i * 3 + 1]
		var z := P[i * 3 + 2]
		var f := puff_field(grid.call(x, y, z), x, y, z, 0.6)
		ph[i] = f[0]
		vl[i] = f[1]
		var big := (billow(x * 0.9 + 3.1, y * 0.9, z * 0.9 - 1.7, seed) - 0.55) * lumps * minf(h, 1.2)
		var fade := smooth(0.0, 0.28, y)
		var dd: float = (amp * (f[0] - 0.5) + big) * fade
		pos.set_xyz(i, x + base[i * 3] * dd, y + base[i * 3 + 1] * dd, z + base[i * 3 + 2] * dd)
	g.compute_vertex_normals()
	blend_normals(g, base, o.normalBlend if o.get("normalBlend") != null else 0.5)
	bake_colors(g, {"colors": o.get("colors"), "H": h, "seed": seed, "puffH": ph, "valley": vl, "dark": o.dark if o.get("dark") != null else 0.13})
	if ground != null:
		for i in n:
			pos.set_y(i, pos.get_y(i) + float(ground.call(pos.get_x(i))))
	var uv := PackedFloat32Array()
	uv.resize(n * 2)
	g.set_attribute("uv", T.Attr.new(uv, 2))
	g.compute_bounding_box()
	g.user_data["foliage"] = {"H": h, "spacing": sp, "puff": puff}
	if key != null:
		_cache[key] = g
	return g


## Tiny 5-petal blossoms scattered (area-weighted) on a foliage geometry's upper surface.
static func flower_geometry(src: T.Geometry, o: Dictionary = {}) -> T.Geometry:
	var key := "f|%d|%s|%s|%s|%s|%s|%s|%s|%s" % [src.get_instance_id(), _k(o.get("count")), _k(o.get("density")), _k(o.get("size")),
		_k(o.get("colors")), _k(o.get("seed")), _k(o.get("minY")), _k(o.get("petals")), _k(o.get("xRange"))]
	if _cache.has(key):
		return _cache[key]
	var pos := src.position()
	var nor: T.Attr = src.attributes.normal
	var idx = src.index if src.indexed else null
	var H: float
	if src.user_data.has("foliage") and src.user_data.foliage.H:
		H = src.user_data.foliage.H
	elif src.bounding_box != null:
		H = (src.bounding_box as AABB).end.y
	else:
		H = 1.0
	var seed := int(o.seed if o.get("seed") != null else 7)
	var size: float = o.size if o.get("size") != null else 0.03
	var min_y: float = o.minY if o.get("minY") != null else 0.3
	var petals: int = o.petals if o.get("petals") != null else 5
	var cols := []
	for c in (o.colors if o.get("colors") != null else FLOWER_COLORS.azalea):
		cols.append(T.color(c))
	var nt: int = idx.size() / 3 if idx != null else pos.count() / 3
	var cdf := PackedFloat32Array()
	cdf.resize(nt)
	var tot := 0.0
	var xr = o.get("xRange")
	for t in nt:
		var i0: int = idx[t * 3] if idx != null else t * 3
		var i1: int = idx[t * 3 + 1] if idx != null else t * 3 + 1
		var i2: int = idx[t * 3 + 2] if idx != null else t * 3 + 2
		var A := pos.v3(i0)
		var B := pos.v3(i1)
		var Cv := pos.v3(i2)
		var cxm := (A.x + B.x + Cv.x) / 3.0
		var ok: bool = (A.y + B.y + Cv.y) / 3.0 > H * min_y and nor.get_y(i0) + nor.get_y(i1) + nor.get_y(i2) > -0.3 and (xr == null or (cxm > xr[0] and cxm < xr[1]))
		if ok:
			tot += (B - A).cross(Cv - A).length() / 2.0
		cdf[t] = tot
	var count: int = o.count if o.get("count") != null else maxi(1, roundi(tot * (o.density if o.get("density") != null else 28.0)))
	var pick_tri := func(u: float) -> int:
		var lo := 0
		var hi := nt - 1
		var v := u * tot
		while lo < hi:
			var m := (lo + hi) >> 1
			if cdf[m] < v:
				lo = m + 1
			else:
				hi = m
		return lo
	var Pp := PackedFloat32Array()
	var Nn := PackedFloat32Array()
	var Cc := PackedFloat32Array()
	var Ii := PackedInt32Array()
	var placed := 0
	var tries := 0
	while tries < count * 12 and placed < count:
		var t: int = pick_tri.call(hash3(tries, 13, 5, seed)) if tot > 0.0 else floori(hash3(tries, 13, 5, seed) * nt)
		var i0: int = idx[t * 3] if idx != null else t * 3
		var i1: int = idx[t * 3 + 1] if idx != null else t * 3 + 1
		var i2: int = idx[t * 3 + 2] if idx != null else t * 3 + 2
		var a := pos.v3(i0)
		var b := pos.v3(i1)
		var c := pos.v3(i2)
		var u := hash3(tries, 2, 8, seed)
		var v := hash3(tries, 9, 1, seed)
		var su := sqrt(u)
		var q := a * (1.0 - su) + b * (su * (1.0 - v)) + c * (su * v)
		if q.y < H * min_y:
			tries += 1
			continue
		var na := (nor.v3(i0) + nor.v3(i1) + nor.v3(i2)).normalized()
		if na.y < -0.1:
			tries += 1
			continue
		var t1 := Vector3(0, 1, 0).cross(na)
		if t1.length_squared() < 1e-4:
			t1 = Vector3(1, 0, 0)
		t1 = t1.normalized()
		var t2 := na.cross(t1)
		var s := size * (0.8 + 0.45 * hash3(tries, 4, 4, seed))
		var rot := hash3(tries, 6, 6, seed) * 6.283
		var col: Color = cols[floori(hash3(tries, 8, 2, seed) * cols.size()) % cols.size()]
		var ci := Color(col.r * 0.8, col.g * 0.8, col.b * 0.8)
		var o0 := Pp.size() / 3
		var lift := 0.012
		Pp.append(q.x + na.x * (lift + 0.004)); Pp.append(q.y + na.y * (lift + 0.004)); Pp.append(q.z + na.z * (lift + 0.004))
		Nn.append(na.x); Nn.append(na.y); Nn.append(na.z)
		Cc.append(ci.r); Cc.append(ci.g); Cc.append(ci.b)
		var m := petals * 2 if petals else 5
		for k in m:
			var ang := rot + (float(k) / m) * PI * 2.0
			var rr := s * 0.74 if petals and k % 2 else s
			var x := cos(ang) * rr
			var y := sin(ang) * rr
			Pp.append(q.x + t1.x * x + t2.x * y + na.x * lift); Pp.append(q.y + t1.y * x + t2.y * y + na.y * lift); Pp.append(q.z + t1.z * x + t2.z * y + na.z * lift)
			Nn.append(na.x); Nn.append(na.y); Nn.append(na.z)
			Cc.append(col.r); Cc.append(col.g); Cc.append(col.b)
		for k in m:
			Ii.append(o0); Ii.append(o0 + 1 + k); Ii.append(o0 + 1 + ((k + 1) % m))
		placed += 1
		tries += 1
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(Pp, 3))
	g.set_attribute("normal", T.Attr.new(Nn, 3))
	g.set_attribute("color", T.Attr.new(Cc, 3))
	var uv := PackedFloat32Array()
	uv.resize(Pp.size() / 3 * 2)
	g.set_attribute("uv", T.Attr.new(uv, 2))
	if Ii.size():
		var a := Vector3(Pp[Ii[0] * 3], Pp[Ii[0] * 3 + 1], Pp[Ii[0] * 3 + 2])
		var b := Vector3(Pp[Ii[1] * 3], Pp[Ii[1] * 3 + 1], Pp[Ii[1] * 3 + 2])
		var c := Vector3(Pp[Ii[2] * 3], Pp[Ii[2] * 3 + 1], Pp[Ii[2] * 3 + 2])
		var na := Vector3(Nn[Ii[0] * 3], Nn[Ii[0] * 3 + 1], Nn[Ii[0] * 3 + 2])
		if (b - a).cross(c - a).dot(na) < 0.0:
			var t := 0
			while t < Ii.size():
				var tmp := Ii[t + 1]
				Ii[t + 1] = Ii[t + 2]
				Ii[t + 2] = tmp
				t += 3
	g.set_index(Ii)
	g.compute_bounding_box()
	_cache[key] = g
	return g


## The shared foliage material (vertex colours; the leaf-clump pattern is the shader's).
static func foliage_material(ctx, o: Dictionary = {}):
	var key := str(ctx.mat.get_instance_id()) + "|" + str(o)
	if _fmat.has(key):
		return _fmat[key]
	var opts := {"vertexColors": true, "paint": 0.03, "name": "foliage-clumps" + ("-" + o.side if o.get("side") else "")}
	if o.get("side"):
		opts["side"] = o.side
	var m = ctx.mat.toon("#ffffff", opts)
	m.user_data["foliage"] = true
	_fmat[key] = m
	return m


static func add_blossoms(ctx, m, g: T.Geometry, flowers, seed: int) -> void:
	var fl = flower_spec(flowers)
	if fl == null:
		return
	var fo := {"density": 60.0 * fl.density, "size": 0.0145 * fl.size, "colors": fl.colors, "seed": seed + 17, "minY": fl.get("top", 0.3)}
	if fl.get("xRange") != null:
		fo["xRange"] = fl.xRange
	var fg := flower_geometry(g, fo)
	var fm := T.MeshObj.new(fg, ctx.mat.toon("#ffffff", {"vertexColors": true, "paint": 0.02}))
	fm.receive_shadow = true
	fm.cast_shadow = false
	ctx.no_outline(fm)
	m.add(fm)


static func _opt(o: Dictionary, k: String, d):
	return o[k] if o.get(k) != null else d


## Round shrub mesh; origin = ground contact centre.
static func make_shrub(ctx, o: Dictionary = {}):
	var r: float = _opt(o, "r", 0.6)
	var h: float = _opt(o, "h", r * 1.5)
	var cols = o.get("colors")
	if cols == null:
		cols = SHRUB_COLORS[_opt(o, "kind", "boxwood")]
	var g := shrub_geometry({"rx": r * _opt(o, "sx", 1.0), "ry": h / 2.0, "rz": r * _opt(o, "sz", 1.0), "lumps": _opt(o, "lumps", 0.16), "freq": _opt(o, "freq", 2.4),
		"seed": _opt(o, "seed", 1), "colors": cols, "puff": o.get("puff"), "puffAmp": o.get("puffAmp"), "spacing": o.get("spacing"), "detail": o.get("detail"),
		"square": o.get("square"), "normalBlend": o.get("normalBlend")})
	var m := T.MeshObj.new(g, foliage_material(ctx))
	m.cast_shadow = true
	m.receive_shadow = true
	add_blossoms(ctx, m, g, o.get("flowers") if o.get("flowers") else o.get("blossoms"), _opt(o, "seed", 1))
	return m


## Clipped hedge; length along local X, origin = ground centre.
static func make_hedge(ctx, o: Dictionary = {}):
	var cols = o.get("colors")
	if cols == null:
		cols = SHRUB_COLORS[_opt(o, "kind", "boxwood")]
	var g := hedge_geometry({"length": _opt(o, "length", 3.0), "h": _opt(o, "h", 1.0), "d": _opt(o, "d", 0.7), "seed": _opt(o, "seed", 3), "colors": cols,
		"lumps": o.get("lumps"), "puff": o.get("puff"), "puffAmp": o.get("puffAmp"), "spacing": o.get("spacing"), "ground": o.get("ground"), "round": o.get("round")})
	var m := T.MeshObj.new(g, foliage_material(ctx))
	m.cast_shadow = true
	m.receive_shadow = true
	add_blossoms(ctx, m, g, o.get("flowers"), _opt(o, "seed", 3))
	return m


## Topiary: clipped balls on a trunk; origin = pot soil level.
static func make_topiary(ctx, o: Dictionary = {}):
	var grp := T.Group.new()
	var trunk_h: float = _opt(o, "trunk", 0.7)
	var r: float = _opt(o, "r", 0.28)
	var seed: int = _opt(o, "seed", 5)
	var trunk := T.MeshObj.new(Geo.cylinder(0.018, 0.026, trunk_h, 8), ctx.mat.toon(_opt(o, "trunkColor", "#6a5040")))
	trunk.position.y = trunk_h / 2.0
	trunk.cast_shadow = true
	grp.add(trunk)
	var balls = _opt(o, "balls", [[0, trunk_h + r * 0.8, 0, 1], [r * 0.9, trunk_h + r * 0.2, 0.05, 0.62], [-r * 0.8, trunk_h + r * 0.35, -0.04, 0.7]])
	for i in balls.size():
		var bb = balls[i]
		var s: float = bb[3]
		var b = make_shrub(ctx, {"r": r * s, "h": r * s * 1.9, "seed": seed + i, "lumps": 0.1, "freq": 3.5, "puffAmp": 0.18, "kind": o.get("kind"), "colors": o.get("colors")})
		b.position = Vector3(bb[0], bb[1] - r * s * 0.95, bb[2])
		grp.add(b)
	return grp


## Cloud-pruned tree / pine: trunk and flat-bottomed foliage pads; origin = ground.
static func make_cloud_tree(ctx, o: Dictionary = {}):
	var grp := T.Group.new()
	var h: float = _opt(o, "h", 2.2)
	var r: float = _opt(o, "r", 0.55)
	var seed: int = _opt(o, "seed", 9)
	var tm = ctx.mat.toon(_opt(o, "trunkColor", "#6b5244"), {"paint": 0.06})
	var lean: float = _opt(o, "lean", 0.12)
	var pivot := T.Group.new()
	pivot.rotation.z = lean
	grp.add(pivot)
	var trunk := T.MeshObj.new(Geo.cylinder(0.05 * h / 2.0, 0.08 * h / 2.0, h * 0.8, 8), tm)
	trunk.position.y = h * 0.4
	trunk.cast_shadow = true
	pivot.add(trunk)
	var pads = _opt(o, "pads", [[0.1, 0.92, 0, 1.0], [0.55, 0.62, 0.1, 0.72], [-0.5, 0.52, -0.1, 0.66], [0.2, 0.36, 0.3, 0.5]])
	for i in pads.size():
		var p = pads[i]
		var pr: float = r * float(p[3])
		var cols = o.get("colors")
		if cols == null:
			cols = SHRUB_COLORS[_opt(o, "kind", "pine")]
		var g := shrub_geometry({"rx": pr * 1.15, "ry": pr * 0.42, "rz": pr, "lumps": 0.1, "freq": 3, "seed": seed + i * 7, "colors": cols, "puffAmp": 0.34, "puff": maxf(0.16, pr * 0.55)})
		var m := T.MeshObj.new(g, foliage_material(ctx))
		m.position = Vector3(float(p[0]) * r * 1.2 - sin(lean) * float(p[1]) * h, float(p[1]) * h - pr * 0.3, float(p[2]) * r)
		m.rotation.y = hash3(i, seed, 1, 3) * 6.28
		m.cast_shadow = true
		m.receive_shadow = true
		grp.add(m)
	return grp
