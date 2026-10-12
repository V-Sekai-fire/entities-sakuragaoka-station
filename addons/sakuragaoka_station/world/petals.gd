# petals.js: every sakura petal in the town.
#
#  Airborne (GPU, pure functions of uTime/uWind/uGust, no shadows, no outline):
#    - fall  : one InstancedMesh of slightly cupped, notched petals (4 tris) with every "kind":
#              0 canopy emitters (spawn inside each crown, flutter/tumble/spiral down, drift downwind,
#                land, rest a moment, fade), 1 near field around the camera (large, clearly shaped),
#              2 mid field (the most; thinned by a density map that peaks around the canopies, the
#                street and the rail corridor), 4 petals resting on ballast / platform edges that
#                only the train gust lifts, 6 train swirl.
#    - soft  : a few very close, defocused petals (soft alpha, blended).
#    - glint : far field of tiny pink glints (screen-size floor instead of vanishing).
#    Train gust: services.rail.trains -> uniforms; moving cars lift petals, drag them along the body
#    and roll them in a vortex behind; stopped trains with open doors make small eddies at the doors.
#  Lying (one InstancedMesh, toon): see petals/plan.gd: clumps, streaks, drifts, piles, benches,
#    vending tops, café tables/window, ballast. Carpet patches: one quad = dozens of petals (atlas).
#  Floating: petal rafts drifting east on the river + single petals on open gutter water.
# Shaders: petals/shaders.gd (fall / soft / float / rafts .gdshader). Reads ctx.services sakura,
# street, station, plaza, shopsA, houses and (per frame) rail. Publishes ctx.services.petals.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Shaders = preload("res://addons/sakuragaoka_station/world/petals/shaders.gd")
const Textures = preload("res://addons/sakuragaoka_station/world/petals/textures.gd")
const Trains = preload("res://addons/sakuragaoka_station/world/petals/trains.gd")
const Ground = preload("res://addons/sakuragaoka_station/world/petals/ground.gd")
const Surface = preload("res://addons/sakuragaoka_station/world/petals/surface.gd")
const Plan = preload("res://addons/sakuragaoka_station/world/petals/plan.gd")

const COL := {
	"airA": "#f3dde5", "airB": "#eeb4c6", "airBase": "#dd8aa5", "glow": "#ffd3de",
	"pale": "#f5e2e9", "pink": "#f0bfcf", "deep": "#e49db4", "old": "#c9a79d",
	"raftA": "#f9eef2", "raftB": "#f4d2dc",
}

# density / landing / roof map rect
const DR := {"x0": -150.0, "x1": 150.0, "z0": -130.0, "z1": 146.0, "step": 0.5}

var ctx
var L
var r
var SI
var Q: float
var NX: int
var NZ: int
var dR := PackedFloat32Array()
var noise_perm := PackedInt32Array()
var noise_val := PackedFloat32Array()
var patches: Array = []


func _r() -> float:
	return r.f()


func H(x: float, z: float) -> float:
	return L.height_at(x, z)


static func _fin(v) -> bool:
	return v != null and (v is float or v is int) and is_finite(float(v))


# ------------------------------------------------------------------ value noise (makeNoise)
func make_noise(rn) -> void:
	var N := 256
	noise_perm.resize(N * 2)
	noise_val.resize(N)
	for i in N:
		noise_perm[i] = i
		noise_val[i] = rn.f()
	for i in range(N - 1, 0, -1):
		var j := floori(rn.f() * (i + 1))
		var t := noise_perm[i]
		noise_perm[i] = noise_perm[j]
		noise_perm[j] = t
	for i in N:
		noise_perm[N + i] = noise_perm[i]


func _nh(x: int, z: int) -> float:
	return noise_val[noise_perm[(noise_perm[x & 255] + z) & 511]]


func noise(x: float, z: float) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var fx := x - ix
	var fz := z - iz
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var a := _nh(ix, iz)
	var b := _nh(ix + 1, iz)
	var c := _nh(ix, iz + 1)
	var d := _nh(ix + 1, iz + 1)
	return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fz


func gauss() -> float:
	return (_r() + _r() + _r() + _r() - 2.0) / 0.8165


static func fallback_trees(Lr) -> Array:
	var TT: Array = []
	var add := func(x: float, z: float, rr: float, h: float, cx: float = 0.0, cz: float = 0.0, id: String = ""):
		var g: float = Lr.height_at(x, z)
		TT.append({"id": id, "x": x + cx, "z": z + cz, "y": g + h * 0.62, "r": rr, "h": h, "trunk": {"x": x, "z": z, "r": 0.3}, "ground": g})
	add.call(Lr.PLAZA.tree.x, Lr.PLAZA.tree.z, 6.6, 10.3, 0.0, 0.0, "plaza")
	add.call(Lr.SPOTS.w3Sakura.x, Lr.SPOTS.w3Sakura.z, 5.0, 9.1, 1.6, 0.0, "w3")
	add.call(Lr.SPOTS.shrineSakura.x, Lr.SPOTS.shrineSakura.z, 3.6, 7.0, 0.0, 0.0, "shrine")
	add.call(-7.6, -7.8, 2.8, 6.1, 0.0, 0.0, "plazaSW")
	add.call(19.5, -22.0, 3.9, 7.8, 0.0, 0.0, "forecourtE")
	for x in [2, 14, 26]:
		add.call(float(x), -51.3, 3.8, 8.4, 0.0, 0.6, "platN" + str(x))
	for x in [20, 32]:
		add.call(float(x), -34.6, 3.6, 8.0, 0.0, -0.6, "platS" + str(x))
	var x := -23.5
	while x > -61.0:
		add.call(x, -32.8, 3.5, 7.2, 0.0, -1.2)
		x -= 8.6
	x = 51.5
	while x < 62.5:
		add.call(x, -32.8, 3.5, 7.2, 0.0, -1.2)
		x += 8.8
	x = -24.5
	while x > -91.0:
		add.call(x, -52.9, 3.9, 7.7, 0.0, -1.4)
		x -= 8.3
	x = 52.5
	while x < 91.0:
		add.call(x, -52.9, 3.9, 7.7, 0.0, -1.4)
		x += 8.3
	for zs in [[-90.8, -124.0], [-95.3, -119.5]]:
		x = zs[1]
		while x <= 125.0:
			if not (absf(x + 12.0) < 5.0 or absf(x - 40.0) < 5.0):
				add.call(x, zs[0], 4.1, 7.6)
			x += 9.4
	add.call(-36.2, 1.85, 2.4, 5.4)
	add.call(33.8, 1.85, 2.4, 5.4)
	return TT


static func fallback_edges(Lr) -> Array:
	var E: Array = []
	var seg := func(pts: Array, kind: String):
		for i in range(1, pts.size()):
			E.append({"a": pts[i - 1], "b": pts[i], "kind": kind})
	for s in [-1.0, 1.0]:
		var c: Array = []
		var f: Array = []
		var z := 3.2
		while z <= 128.0:
			var x: float = Lr.street_center_x(z)
			c.append([x + s * 3.0, z])
			f.append([x + s * Lr.STREET.lotOffset, z])
			z += 3.0
		seg.call(c, "curb")
		seg.call(f, "wall")
	for z in [-5.0, 1.0]:
		seg.call([[-95.0, z], [-15.0, z]], "edge")
		seg.call([[-9.0, z], [95.0, z]], "edge")
	for x in [-14.75, -9.25]:
		seg.call([[x, -33.5], [x, -6.0]], "edge")
		seg.call([[x, -84.0], [x, -53.0]], "edge")
	for z in [-57.5, -53.5]:
		seg.call([[-95.0, z], [-15.0, z]], "edge")
		seg.call([[-9.0, z], [95.0, z]], "edge")
	for z in [-72.5, -69.5]:
		seg.call([[-85.0, z], [-15.0, z]], "edge")
		seg.call([[-9.0, z], [85.0, z]], "edge")
	return E


func in_river(z: float) -> bool:
	return z < L.RIVER.z0 + 0.2 and z > L.RIVER.z1 - 0.2


func dens(x: float, z: float) -> float:
	var i := floori((x - DR.x0) / DR.step)
	var j := floori((z - DR.z0) / DR.step)
	if i < 0 or j < 0 or i >= NX or j >= NZ:
		return 0.08
	return dR[j * NX + i]


# ------------------------------------------------------------------ surfaces for lying petals
func road_lift(x: float, z: float) -> float:
	if z > 1.0 and absf(x - L.street_center_x(z)) < 3.0:
		return 0.02
	var a := absf(x - L.street_center_x(z))
	if z > 3.2 and z < 58.8 and a >= 3.0 and a <= 4.6:
		return 0.15
	if absf(z + 2.0) < 3.0 or absf(z + 55.5) < 2.0 or absf(z + 71.0) < 1.5 or (absf(x + 12.0) < 2.75 and z < -5.0):
		return 0.02
	return 0.0


## Exact rendered surface near the terrain (NAN if none), no roof test.
func surf_raw(x: float, z: float, above: float = 0.55) -> float:
	var h0 := H(x, z)
	if SI.empty:
		return h0 + road_lift(x, z)
	return SI.top(x, z, h0 - 0.9, h0 + above)


## Is something above (x, z, y) acceptable? open: nothing below 3.4 m (no eaves, benches, cars,
## interiors); edge: fence rails / railings / wall copings (< 2 m) are fine, ceilings & awnings
## (2-3.6 m) are not; plat: like edge, and the platform shelter roof lets 60 % through.
func cover_ok(x: float, z: float, y: float, mode) -> bool:
	if SI.empty:
		return true
	var d: float = SI.cover(x, z, y + 0.04, y + 9.0) - y
	if not is_finite(d):
		return true
	if d < 0.3:
		return false
	if mode == "edge" or mode == "plat":
		if d < 2.0:
			return true
		if d < (2.2 if mode == "plat" else 3.6):
			return false
		return _r() < (0.6 if mode == "plat" else 0.3)
	if d < 3.4:
		return false
	return _r() < 0.3


## Ground surface for a lying petal, or null (no surface / indoors / under a low cover).
func surf(x: float, z: float, mode = null):
	var y := surf_raw(x, z)
	if not is_finite(y):
		return null
	if in_river(z):
		return null
	return y if cover_ok(x, z, y, mode) else null


func surf_p(x: float, z: float):
	var PY: float = L.PLATFORM.y
	if SI.empty:
		return PY
	var y: float = SI.top(x, z, PY - 0.25, PY + 0.25)
	if not is_finite(y):
		return null
	return y if cover_ok(x, z, y, "plat") else null


func tint_of() -> Color:
	return T.color(COL.pale).lerp(T.color(COL.pink), pow(_r(), 1.4) * 0.8)


## Carpet patch: one quad = dozens of petals (atlas), corners follow the real surface.
func patch(x: float, z: float, l: float, w: float, ang: float, cell: int, o: Dictionary = {}) -> bool:
	w = l / 3.0 * (0.9 + _r() * 0.2) if cell >= 2 else l * (0.86 + _r() * 0.24)  # match the atlas cell aspect
	var sf: Callable = o.surf if o.get("surf") != null else surf
	var yc = sf.call(x, z)
	if yc == null or not is_finite(yc):
		return false
	var raw: Callable = o.raw if o.get("raw") != null else surf_raw
	var c := cos(ang)
	var s := sin(ang)
	var P: Array = []
	for uv in [[-0.5, -0.5], [0.5, -0.5], [0.5, 0.5], [-0.5, 0.5]]:
		var px: float = x + uv[0] * l * c - uv[1] * w * s
		var pz: float = z + uv[0] * l * s + uv[1] * w * c
		P.append([px, raw.call(px, pz), pz])
	for p in P:
		if not _fin(p[1]):
			return false
	var avg: float = (P[0][1] + P[1][1] + P[2][1] + P[3][1]) / 4.0
	if absf(avg - yc) > 0.012:
		return false
	for k in 4:  # mid-edge samples catch steps between two corners
		var A: Array = P[k]
		var B: Array = P[(k + 1) % 4]
		var mx: float = (A[0] + B[0]) / 2.0
		var mz: float = (A[2] + B[2]) / 2.0
		var my = raw.call(mx, mz)
		if not _fin(my) or absf(my - (A[1] + B[1]) / 2.0) > 0.012:
			return false
	patches.append({"P": P, "cell": cell, "tint": o.tint if o.get("tint") != null else tint_of()})
	return true


# ------------------------------------------------------------------ instance buffers
class Buf:
	var A := PackedFloat32Array()
	var B := PackedFloat32Array()
	var C := PackedFloat32Array()
	var D := PackedFloat32Array()
	var n := 0
	var cap := 0

	func _init(c: int, four: bool = false) -> void:
		cap = c
		A.resize(c * 4)
		B.resize(c * 4)
		C.resize(c * 4)
		if four:
			D.resize(c * 4)


func push(buf: Buf, a: Array, c: Array) -> void:
	if buf.n >= buf.cap:
		return
	var o := buf.n * 4
	for i in 4:
		buf.A[o + i] = a[i]
		buf.C[o + i] = c[i]
	buf.B[o] = _r()
	buf.B[o + 1] = _r()
	buf.B[o + 2] = _r()
	buf.B[o + 3] = _r()
	buf.n += 1


func push_f(b: Buf, A: Array, B: Array, C: Array, D: Array) -> void:
	if b.n >= b.cap:
		return
	var o := b.n * 4
	for i in 4:
		b.A[o + i] = A[i]
		b.B[o + i] = B[i]
		b.C[o + i] = C[i]
		b.D[o + i] = D[i]
	b.n += 1


static func _sub(a: PackedFloat32Array, n: int) -> T.Attr:
	return T.Attr.new(a.slice(0, maxi(1, n) * 4), 4)


static func make_mesh(geo: T.Geometry, buf: Buf, mat, name: String) -> T.InstancedMesh:
	var g := geo.clone()
	g.set_attribute("aA", _sub(buf.A, buf.n))
	g.set_attribute("aB", _sub(buf.B, buf.n))
	g.set_attribute("aC", _sub(buf.C, buf.n))
	g.user_data["instanced"] = ["aA", "aB", "aC"]
	var m := T.InstancedMesh.new(g, mat, maxi(1, buf.n))
	m.count = buf.n
	m.frustum_culled = false
	m.cast_shadow = false
	m.receive_shadow = true
	m.name = name
	m.render_order = 3 if mat.transparent else 1
	return m


static func float_mesh(b: Buf, mat, name: String) -> T.InstancedMesh:
	var g: T.Geometry = Geo.plane(1.0, 1.0).rotate_x(-PI / 2.0)
	g.set_attribute("aA", _sub(b.A, b.n))
	g.set_attribute("aB", _sub(b.B, b.n))
	g.set_attribute("aC", _sub(b.C, b.n))
	g.set_attribute("aD", _sub(b.D, b.n))
	g.user_data["instanced"] = ["aA", "aB", "aC", "aD"]
	var m := T.InstancedMesh.new(g, mat, maxi(1, b.n))
	m.count = b.n
	m.frustum_culled = false
	m.cast_shadow = false
	m.receive_shadow = true
	m.name = name
	m.render_order = 1
	return m


## 3x2 grid (4 tris): folded along the midrib = cupped, normal ~ +Y.
static func petal_geo() -> T.Geometry:
	var pos := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var idx := PackedInt32Array()
	for j in 2:
		for i in 3:
			var u := i / 2.0
			var v := float(j)
			var x := (u - 0.5) * 0.72
			var z := 0.5 - v
			pos.append_array([x, 0.12 * absf(2.0 * u - 1.0) + 0.05 * v - 0.04, z])
			uv.append_array([u, v])
	for i in 2:
		var a := i
		var b := a + 1
		var c := a + 3
		var d := c + 1
		idx.append_array([a, c, b, b, c, d])
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(pos, 3))
	g.set_attribute("uv", T.Attr.new(uv, 2))
	g.set_index(idx)
	g.compute_vertex_normals()
	var n: T.Attr = g.get_attribute("normal")
	var sy := 0.0
	for i in n.count():
		sy += n.get_y(i)
	if sy < 0.0:
		for i in n.count():
			n.set_xyz(i, -n.get_x(i), -n.get_y(i), -n.get_z(i))
	return g


static func _half_tex(rgba: PackedFloat32Array, w: int, h: int, key: String) -> T.Tex:
	var bytes := PackedByteArray()
	bytes.resize(rgba.size() * 2)
	for i in rgba.size():
		bytes.encode_half(i * 2, rgba[i])
	var t := T.Tex.new()
	t.uuid = key
	t.width = w
	t.height = h
	t.user_data["image"] = Image.create_from_data(w, h, false, Image.FORMAT_RGBAH, bytes)
	t.user_data["key"] = key
	t.colorSpace = "none"
	t.minFilter = "linear"
	t.magFilter = "linear"
	t.wrap_s = "clamp"
	t.wrap_t = "clamp"
	return t


func build(c):
	ctx = c
	L = ctx.L
	var qp = ctx.quality.get("petals")
	Q = maxf(0.15, minf(1.5, 1.0 if qp == null else float(qp)))
	r = ctx.rng("petals")
	make_noise(ctx.rng("petals-noise"))
	var TX: Dictionary = Textures.create_petal_textures(ctx.rng("petals-tex"))
	var root := T.Group.new()
	root.name = "petals"

	# ------------------------------------------------------------------ what exists around us
	SI = Surface.create(ctx, {})
	var trees_src = ctx.services.get("sakura", {}).get("trees") if ctx.services.get("sakura") != null else null
	var src: Array = trees_src if trees_src is Array and not trees_src.is_empty() else fallback_trees(L)
	var trees: Array = []
	var boost_re := RegEx.create_from_string("^(platN|platS|forecourt|shrine|plazaSW)")
	for t in src:
		if t == null or not _fin(t.get("x")) or not _fin(t.get("z")):
			continue
		var trunk = t.get("trunk")
		var tx: float = trunk.x if trunk != null and _fin(trunk.get("x")) else t.x
		var tz: float = trunk.z if trunk != null and _fin(trunk.get("z")) else t.z
		var ground: float = t.ground if _fin(t.get("ground")) else H(tx, tz)
		var h: float = t.h if _fin(t.get("h")) else 7.0
		var y: float = t.y if _fin(t.get("y")) else ground + h * 0.62
		if y < ground + 1.6:
			y = ground + maxf(2.2, h * 0.6)
		var id := str(t.get("id")) if t.get("id") else ""
		var boost := 3.2 if id == "plaza" else (2.6 if id == "w3" else (1.6 if boost_re.search(id) != null else 1.0))
		var tr = t.get("r")
		var trunk_r = trunk.get("r") if trunk != null else null
		trees.append({"id": id, "boost": boost, "x": float(t.x), "z": float(t.z), "y": y, "r": maxf(1.2, minf(9.0, float(tr) if tr else 3.5)),
			"h": h, "tx": tx, "tz": tz, "trunkR": float(trunk_r) if trunk_r else 0.3, "ground": ground})
	var street = ctx.services.get("street")
	var edges: Array = street.edges if street != null and street.get("edges") is Array and not street.edges.is_empty() else fallback_edges(L)
	var gutters: Array = street.gutters if street != null and street.get("gutters") is Array else []

	# ------------------------------------------------------------------ density / landing / roof map (GPU + CPU)
	NX = int(T.js_round((DR.x1 - DR.x0) / DR.step))
	NZ = int(T.js_round((DR.z1 - DR.z0) / DR.step))
	dR.resize(NX * NZ)
	var dG := PackedFloat32Array()
	dG.resize(NX * NZ)
	var dB := PackedFloat32Array()
	dB.resize(NX * NZ)
	var WA := atan2(0.35, 0.9)
	var wdx := cos(WA)
	var wdz := sin(WA)
	var siB: Dictionary = SI.bounds
	var si_empty: bool = SI.empty
	for j in NZ:
		var z: float = DR.z0 + (j + 0.5) * DR.step
		var scx: float = L.street_center_x(z)
		for i in NX:
			var x: float = DR.x0 + (i + 0.5) * DR.step
			var k := j * NX + i
			var h0 := H(x, z)
			var y := h0
			var ceil_ := 0.0
			if not si_empty and x > siB.x0 and x < siB.x1 and z > siB.z0 and z < siB.z1:
				var a: float = SI.top(x - 0.12, z - 0.12, h0 - 1.6, h0 + 2.05)
				var b: float = SI.top(x + 0.12, z + 0.12, h0 - 1.6, h0 + 2.05)
				var t: float = minf(a, b) if is_finite(a) and is_finite(b) else (a if is_finite(a) else b)
				if is_finite(t):
					y = t
				var cv: float = SI.cover(x, z, y + 0.25, y + 11.0)
				if is_finite(cv):
					ceil_ = cv - y
			if in_river(z):
				y = maxf(y, L.RIVER.waterY + 0.005)
			dG[k] = y
			dB[k] = ceil_
			# baseline airborne density: the town, the main street, the rail corridor
			var d := 0.16
			if z > 1.0 and absf(x - scx) < 8.0:
				d += 0.2
			if z > -54.0 and z < -32.0 and x > -60.0 and x < 80.0:
				d += 0.16
			if z > -5.5 and z < 1.5:
				d += 0.08
			dR[k] = d
	for t in trees:
		var cx: float = t.x + wdx * 4.5
		var cz: float = t.z + wdz * 4.5
		var R: float = t.r + 9.0
		var i0 := maxi(0, floori((cx - R * 1.8 - DR.x0) / DR.step))
		var i1 := mini(NX - 1, ceili((cx + R * 1.8 - DR.x0) / DR.step))
		var j0 := maxi(0, floori((cz - R * 1.8 - DR.z0) / DR.step))
		var j1 := mini(NZ - 1, ceili((cz + R * 1.8 - DR.z0) / DR.step))
		var amp := minf(1.0, 0.35 + t.r * 0.12)
		for j in range(j0, j1 + 1):
			var z: float = DR.z0 + (j + 0.5) * DR.step
			for i in range(i0, i1 + 1):
				var x: float = DR.x0 + (i + 0.5) * DR.step
				# ellipse stretched downwind
				var dx := x - cx
				var dz := z - cz
				var u := (dx * wdx + dz * wdz) / (R * 1.35)
				var v := (-dx * wdz + dz * wdx) / R
				dR[j * NX + i] += amp * exp(-(u * u + v * v) * 1.6)
	for k in dR.size():
		dR[k] = minf(1.0, dR[k])
	var hf := PackedFloat32Array()
	hf.resize(NX * NZ * 4)
	for k in NX * NZ:
		hf[k * 4] = dR[k]
		hf[k * 4 + 1] = dG[k]
		hf[k * 4 + 2] = dB[k]
		hf[k * 4 + 3] = 1.0
	var dens_tex := _half_tex(hf, NX, NZ, "petals-dens")

	# ------------------------------------------------------------------ lying petals
	var G = Ground.create(ctx, {"r": r, "capacity": int(T.js_round(52000.0 * Q)) + 2000, "surf": surf,
		"colors": {"pale": COL.pale, "pink": COL.pink, "deep": COL.deep, "old": COL.old}})
	var grates: Array = []
	for g in gutters:
		if g == null or not g.get("water") or g.get("open"):
			continue
		var ax: float = g.a[0]
		var az: float = g.a[1]
		var bx: float = g.b[0]
		var bz: float = g.b[1]
		var length := Vector2(bx - ax, bz - az).length()
		if length > 0.2 and length < 2.5 and _r() < 0.8:
			grates.append({"x": (ax + bx) / 2.0, "z": (az + bz) / 2.0, "ang": atan2(bz - az, bx - ax)})
	var plan_stats: Dictionary = Plan.plan_ground(ctx, G, {"r": r, "Q": Q, "trees": trees, "SI": SI, "dens": dens, "noise": noise,
		"gauss": gauss, "edges": edges, "grates": grates, "surf": surf, "surfRaw": surf_raw, "surfP": surf_p, "patch": patch})
	var ground_mat = ctx.mat.toon("#ffffff", {"map": TX.colorTex, "alphaTest": 0.5, "side": "double", "paint": 0.03, "emissive": "#f0c6d3", "emissiveIntensity": 0.2})
	ground_mat.alphaToCoverage = true
	var ground = G.build(ground_mat)
	ground.frustum_culled = false  # instances span the whole town
	root.add(ground)
	if not patches.is_empty():
		var n := patches.size()
		var pos := PackedFloat32Array()
		pos.resize(n * 12)
		var nor := PackedFloat32Array()
		nor.resize(n * 12)
		var uv := PackedFloat32Array()
		uv.resize(n * 8)
		var col := PackedFloat32Array()
		col.resize(n * 12)
		var idx := PackedInt32Array()
		idx.resize(n * 6)
		var UV := [[0, 0], [1, 0], [1, 1], [0, 1]]
		for i in n:
			var p: Dictionary = patches[i]
			var ou: float = (p.cell % 2) * 0.5
			var ov: float = floori(p.cell / 2.0) * 0.5
			for k in 4:
				var o3 := (i * 4 + k) * 3
				var o2 := (i * 4 + k) * 2
				pos[o3] = p.P[k][0]
				pos[o3 + 1] = p.P[k][1] + 0.005
				pos[o3 + 2] = p.P[k][2]
				nor[o3] = 0.0
				nor[o3 + 1] = 1.0
				nor[o3 + 2] = 0.0
				uv[o2] = ou + 0.004 + UV[k][0] * 0.492
				uv[o2 + 1] = ov + 0.004 + UV[k][1] * 0.492
				col[o3] = p.tint.r
				col[o3 + 1] = p.tint.g
				col[o3 + 2] = p.tint.b
			var a := i * 4
			var p0: Array = p.P[0]
			var p1: Array = p.P[1]
			var p2: Array = p.P[2]
			var up: bool = (p1[2] - p0[2]) * (p2[0] - p0[0]) - (p1[0] - p0[0]) * (p2[2] - p0[2]) > 0.0  # winding so the face points up
			var tri := [a, a + 1, a + 2, a, a + 2, a + 3] if up else [a, a + 2, a + 1, a, a + 3, a + 2]
			for k in 6:
				idx[i * 6 + k] = tri[k]
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(pos, 3))
		g.set_attribute("normal", T.Attr.new(nor, 3))
		g.set_attribute("uv", T.Attr.new(uv, 2))
		g.set_attribute("color", T.Attr.new(col, 3))
		g.set_index(idx)
		g.compute_bounding_sphere()
		var pm = ctx.mat.toon("#ffffff", {"map": TX.patchTex, "alphaTest": 0.5, "vertexColors": true, "polygonOffset": -2, "paint": 0.02, "emissive": "#f0c6d3", "emissiveIntensity": 0.18})
		pm.alphaToCoverage = true
		var mesh := T.MeshObj.new(g, pm)
		mesh.name = "petals-carpet"
		mesh.receive_shadow = true
		mesh.cast_shadow = false
		root.add(mesh)

	# ------------------------------------------------------------------ airborne petals
	var pgeo := petal_geo()
	var flat_geo: T.Geometry = Geo.plane(0.72, 1.0).rotate_x(-PI / 2.0)

	var sky = ctx.get("sky")
	var LC := {
		"sun": sky.sun.color * sky.sun.intensity if sky != null and sky.get("sun") != null else Color(2.6, 2.4, 2.2),
		"skyC": sky.hemi.color * sky.hemi.intensity if sky != null and sky.get("hemi") != null else Color(1.2, 1.3, 1.6),
		"gnd": sky.hemi.groundColor * sky.hemi.intensity if sky != null and sky.get("hemi") != null else Color(1.3, 1.2, 1.2),
	}
	var u_light := {"uSunCol": LC.sun, "uSkyCol": LC.skyC, "uGndCol": LC.gnd}
	var live := {"uTr": [Vector4(), Vector4(), Vector4(), Vector4()], "uTr2": [Vector4(), Vector4(), Vector4(), Vector4()], "uResY": 720.0}
	var shared := {
		"uDens": dens_tex, "uDensRect": Vector4(DR.x0, DR.z0, 1.0 / (DR.x1 - DR.x0), 1.0 / (DR.z1 - DR.z0)),
		"uDensSize": Vector2(NX, NZ),
		"uTex": TX.shapeTex,
		"uColA": T.color(COL.airA), "uColB": T.color(COL.airB),
		"uColBase": T.color(COL.airBase), "uGlowCol": T.color(COL.glow),
	}
	shared.merge(u_light)

	var fall := Buf.new(int(T.js_round(28500.0 * Q)) + 800)
	# kind 0: canopy emitters (budget shared by crown size, fewer on distant trees)
	if true:
		var core := {"x": 6.0, "z": -4.0}
		var w: Array = []
		for t in trees:
			w.append(t.boost * t.r * t.r * maxf(0.22, minf(1.0, 1.0 - (Vector2(t.x - core.x, t.z - core.z).length() - 60.0) / 120.0)))
		var tot := 0.0
		for v in w:
			tot += v
		if tot == 0.0:
			tot = 1.0
		var budget := 14000.0 * Q
		for i in trees.size():
			var t: Dictionary = trees[i]
			var n := maxf(T.js_round(18.0 * Q), minf(T.js_round(3600.0 * Q), T.js_round(budget * w[i] / tot)))
			var k := 0
			while k < n:
				k += 1
				var c0 := 0.034 + _r() * 0.016
				var c1 := 0.42 + _r() * 0.42
				push(fall, [t.x, t.y, t.z, 0.0], [c0, c1, t.r, t.ground])
	# kind 2: mid field (the most), kind 1: near field
	var kk := 0
	while kk < 6400.0 * Q:
		kk += 1
		var a0 := (_r() - 0.5) * 64.0
		var a1 := _r() * 13.0
		var a2 := (_r() - 0.5) * 64.0
		var c0 := 0.032 + _r() * 0.014
		var c1 := 0.35 + _r() * 0.4
		push(fall, [a0, a1, a2, 2.0], [c0, c1, 32.0, 13.0])
	kk = 0
	while kk < 900.0 * Q:
		kk += 1
		var a0 := (_r() - 0.5) * 14.0
		var a1 := _r() * 4.2
		var a2 := (_r() - 0.5) * 14.0
		var c0 := 0.03 + _r() * 0.012
		var c1 := 0.3 + _r() * 0.35
		push(fall, [a0, a1, a2, 1.0], [c0, c1, 7.0, 4.2])
	# kind 4: resting on ballast / platform edges, lifted only by the train gust
	if true:
		var n := T.js_round(3400.0 * Q)
		var PL: Dictionary = L.PLATFORM
		var PY: float = PL.y
		var k := 0
		var tries := 0
		while k < n and tries < n * 4:
			tries += 1
			var on_plat := _r() < 0.25
			var x := -30.0 + _r() * 100.0 if _r() < 0.7 else -85.0 + _r() * 190.0
			var z: float
			var y: float
			if on_plat:
				var south := _r() < 0.5
				var p: Dictionary = PL.south if south else PL.north
				if x < p.x0 + 0.2 or x > p.x1 - 0.2:
					continue
				z = p.z0 + 0.25 + pow(_r(), 1.6) * 1.4 if south else p.z1 - 0.25 - pow(_r(), 1.6) * 1.4
				y = PY if SI.empty else SI.top(x, z, PY - 0.2, PY + 0.2)
				if not is_finite(y):
					continue
				if not cover_ok(x, z, y, "plat"):
					continue
			else:
				var zc: float = L.RAIL.zA if _r() < 0.5 else L.RAIL.zB
				z = zc + gauss() * 1.05
				if z > PL.south.z0 - 0.05 and x > PL.south.x0 and x < PL.south.x1:
					continue
				if z < PL.north.z1 + 0.05 and x > PL.north.x0 and x < PL.north.x1:
					continue
				y = L.RAIL.ballastTopY if SI.empty else surf_raw(x, z)
				if not is_finite(y):
					continue
				var on_rail := false
				for zt in [L.RAIL.zA, L.RAIL.zB]:
					for s in [-1.0, 1.0]:
						if absf(z - (zt + s * L.RAIL.gauge / 2.0)) < 0.06 and y > 0.08:
							on_rail = true
				if on_rail:
					continue
			var c0 := 0.03 + _r() * 0.01
			push(fall, [x, y + 0.012, z, 4.0], [c0, 0.5, 0.0, 0.0])
			k += 1
	# kind 6: train swirl: slot 0 = track A, slot 1 = track B (see update); aC.w 0 = wake, 1 = door eddy
	for slot in 2:
		kk = 0
		while kk < 460.0 * Q:  # trailing vortex pair
			kk += 1
			push(fall, [0.0, 0.0, 0.0, 6.0], [0.038 + _r() * 0.014, 0.0, float(slot), 0.0])
		kk = 0
		while kk < 160.0 * Q:  # along the car sides
			kk += 1
			push(fall, [0.0, 0.0, 0.0, 6.0], [0.036 + _r() * 0.012, 0.0, float(slot), 2.0])
		kk = 0
		while kk < 170.0 * Q:  # door eddies when stopped
			kk += 1
			push(fall, [0.0, 0.0, 0.0, 6.0], [0.038 + _r() * 0.012, 0.0, float(slot), 1.0])
	var soft := Buf.new(int(T.js_round(40.0 * Q)) + 4)
	for k in soft.cap:
		var a0 := (_r() - 0.5) * 4.4
		var a1 := _r() * 2.8
		var a2 := (_r() - 0.5) * 4.4
		var c0 := 0.036 + _r() * 0.014
		var c1 := 0.22 + _r() * 0.2
		push(soft, [a0, a1, a2, 5.0], [c0, c1, 2.2, 2.8])
	var far := Buf.new(int(T.js_round(4200.0 * Q)) + 10)
	for k in far.cap:
		var a0 := (_r() - 0.5) * 240.0
		var a1 := _r() * 22.0
		var a2 := (_r() - 0.5) * 240.0
		var c0 := 0.036 + _r() * 0.01
		var c1 := 0.4 + _r() * 0.4
		push(far, [a0, a1, a2, 3.0], [c0, c1, 120.0, 22.0])

	var mat_fall := Shaders.fall_material({"name": "fall", "minPx": 1.5, "far": 230.0}, shared, ctx.shared, live)
	var mat_soft := Shaders.fall_material({"name": "soft", "minPx": 1.0, "far": 12.0, "soft": true, "opacity": 0.62}, shared, ctx.shared, live)
	var mat_far := Shaders.fall_material({"name": "glint", "minPx": 2.0, "far": 260.0}, shared, ctx.shared, live)
	var m_fall := make_mesh(pgeo, fall, mat_fall, "petals-fall")
	var m_soft := make_mesh(flat_geo, soft, mat_soft, "petals-soft")
	var m_far := make_mesh(flat_geo, far, mat_far, "petals-glint")
	root.add(m_fall, m_soft, m_far)

	# ------------------------------------------------------------------ floating petals: river rafts + gutter water
	var float_uniforms := func(sheet: bool, map) -> Dictionary:
		var u := {"uSunDir": ctx.sun_dir, "uFar": 320.0 if sheet else 90.0, "uTex": map,
			"uColA": T.color(COL.raftA if sheet else COL.pale), "uColB": T.color(COL.raftB if sheet else COL.pink)}
		u.merge(u_light)
		return u
	var WY: float = L.RIVER.waterY + 0.006
	var reaches := [[-170.0, -46.5], [-43.5, 74.5], [77.5, 170.0]]  # stepping stones at x=-45, weir at x=76 (environment)
	var RZ0: float = L.RIVER.z0
	var RZ1: float = L.RIVER.z1
	var rafts := Buf.new(int(T.js_round(300.0 * Q)) + 10, true)
	for k in rafts.cap:
		var rc: Array = r.pick(reaches)
		var x0: float = rc[0]
		var x1: float = rc[1]
		var length := x1 - x0
		var bank := _r() < 0.62
		var z: float
		if bank:
			z = RZ0 - 0.7 - pow(_r(), 1.5) * 3.2 if _r() < 0.55 else RZ1 + 0.7 + pow(_r(), 1.5) * 3.2
		else:
			z = RZ1 + 2.0 + _r() * (RZ0 - RZ1 - 4.0)
		if x0 < 30.0 and x1 > 20.0 and z > -114.0 and z < -110.8:
			z = -114.6 if _r() < 0.5 else -110.2
		var ribbon := _r() < 0.75 if bank else _r() < 0.15  # long ribbons gather along the banks
		var Lr: float = 2.2 + _r() * 3.4 if ribbon else (1.0 if bank else 0.8) + _r() * _r() * 2.6
		var Wr := Lr * (0.92 + _r() * 0.16)  # isotropic: shapes live in the atlas
		var speed := 0.12 + _r() * 0.16 if bank else 0.3 + _r() * 0.28
		var cell := (2 if ribbon else 0) + (1 if _r() < 0.5 else 0)
		var a1 := WY + _r() * 0.002
		var a3 := _r()
		var c2 := (_r() - 0.5) * (0.16 if ribbon else 0.5)
		var c3 := _r() * length
		var d2 := _r() * 6.28
		var d3 := cell + _r() * 0.99
		push_f(rafts, [x0, a1, z, a3], [1.0, 0.0, 0.0, length], [Wr, Lr, c2, c3], [speed, 0.25 if bank else 0.8, d2, d3])
	var singles := Buf.new(int(T.js_round(2600.0 * Q)) + 400, true)
	kk = 0
	while kk < 2000.0 * Q:
		kk += 1
		var rc: Array = r.pick(reaches)
		var x0: float = rc[0]
		var x1: float = rc[1]
		var length := x1 - x0
		var z := RZ1 + 0.5 + _r() * (RZ0 - RZ1 - 1.0)
		if x0 < 30.0 and x1 > 20.0 and z > -114.0 and z < -110.8:
			continue
		var s := 0.026 + _r() * 0.008
		var near_bank := minf(absf(z - RZ0), absf(z - RZ1)) < 3.0
		var a3 := _r()
		var c2 := _r() * 6.28
		var c3 := _r() * length
		var d0 := 0.12 + _r() * 0.15 if near_bank else 0.3 + _r() * 0.3
		var d2 := _r() * 6.28
		var d3 := _r() * 0.99
		push_f(singles, [x0, WY, z, a3], [1.0, 0.0, 0.0, length], [s * 0.72, s, c2, c3], [d0, 0.5, d2, d3])
	# open gutter water: petals drifting slowly downhill
	var gutter_float := 0
	for g in gutters:
		if g == null or not g.get("water") or not g.get("open"):
			continue
		var ax: float = g.a[0]
		var az: float = g.a[1]
		var bx: float = g.b[0]
		var bz: float = g.b[1]
		if H(ax, az) < H(bx, bz):
			var sx := ax
			var sz := az
			ax = bx
			az = bz
			bx = sx
			bz = sz
		var length := Vector2(bx - ax, bz - az).length()
		if length < 0.4:
			continue
		var dx := (bx - ax) / length
		var dz := (bz - az) / length
		var gw: float = g.w if g.get("w") else 0.3
		var hw := maxf(0.05, gw / 2.0 - 0.05)
		var mx := (ax + bx) / 2.0
		var mz := (az + bz) / 2.0
		var h0 := H(mx, mz)
		var wy := h0 + 0.02 - 0.195
		if not SI.empty:
			var rim: float = SI.top(mx + dz * (gw / 2.0 - 0.015), mz - dx * (gw / 2.0 - 0.015), h0 - 0.1, h0 + 0.3)
			var low: float = SI.top(mx, mz, h0 - 0.45, h0 + 0.05)
			if is_finite(low):
				wy = low + 0.075 if (is_finite(rim) and rim - low > 0.23) else low
		var n := T.js_round(length * 7.0 * Q)
		var k := 0
		while k < n:
			k += 1
			var s := 0.025 + _r() * 0.007
			var off := (_r() - 0.5) * 2.0 * hw * 0.6
			var a3 := _r()
			var c2 := _r() * 6.28
			var c3 := _r() * length
			var d0 := 0.04 + _r() * 0.07
			var d2 := _r() * 6.28
			var d3 := _r() * 0.99
			push_f(singles, [ax - dz * off, wy + 0.004, az + dx * off, a3], [dx, 0.0, dz, length], [s * 0.72, s, c2, c3], [d0, hw * 0.4, d2, d3])
			gutter_float += 1
	var m_rafts := float_mesh(rafts, Shaders.float_material(true, float_uniforms.call(true, TX.raftTex), ctx.shared, live), "petals-rafts")
	var m_singles := float_mesh(singles, Shaders.float_material(false, float_uniforms.call(false, TX.colorTex), ctx.shared, live), "petals-floating")
	root.add(m_rafts, m_singles)

	ctx.no_outline(root)
	ctx.no_batch(root)
	ctx.add(root)

	# ------------------------------------------------------------------ per frame: train gust + resolution
	var trains_r = Trains.create(ctx)
	var update := func(_dt, t):
		var lst: Array = trains_r.read(t)
		# stable slots: track A -> 0, track B -> 1 (the swirl petals are bound to a slot), extras -> 2, 3
		var slots := [null, null, null, null]
		for TT in lst:
			var want := 0 if TT.side > 0 else 1
			if slots[want] == null:
				slots[want] = TT
			elif slots[2] == null:
				slots[2] = TT
			elif slots[3] == null:
				slots[3] = TT
		for i in 4:
			var TT = slots[i]
			if TT != null:
				live.uTr[i] = Vector4(TT.x, TT.z, TT.v, TT.half)
				live.uTr2[i] = Vector4(TT.doors, TT.side, 1.0, 0.0)
			else:
				live.uTr[i] = Vector4(0.0, -1000.0, 0.0, 1.0)
				live.uTr2[i] = Vector4(0.0, 0.0, 0.0, 0.0)
		var renderer = ctx.get("renderer")
		if renderer != null and renderer.has_method("get_drawing_buffer_size"):
			var sz: Vector2 = renderer.get_drawing_buffer_size()
			var pr = ctx.quality.get("pixelRatio")
			live.uResY = maxf(240.0, sz.y * (float(pr) if pr else 1.0))
	ctx.on_update(update)

	var counts := {"ground": G.count, "patches": patches.size(), "fall": fall.n, "soft": soft.n, "glint": far.n, "rafts": rafts.n,
		"floating": singles.n, "gutterFloat": gutter_float}
	counts.merge(plan_stats)
	counts.merge({"surfaceTris": SI.count, "trees": trees.size()})
	# update: the frame callback also registered with on_update, for a host that runs only the petals
	ctx.services["petals"] = {"counts": counts, "update": update}
	return null
