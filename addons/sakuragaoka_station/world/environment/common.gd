# environment/common.js: deterministic noise, world zones and the extended terrain height.
# Pure functions of coordinates; the zone tests read the layout this build was given.
extends RefCounted

const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")
const T = preload("res://addons/sakuragaoka_station/core/three.gd")

const PARK := {"x0": 63.5, "x1": 92.5, "z0": -32.8, "z1": -6.6, "mound": {"x": 78.5, "z": -20.5, "rx": 11.5, "rz": 8.6, "h": 2.35}}
const VACANT_W := {"x0": -93.0, "x1": -63.0, "z0": -33.0, "z1": -6.2}
const ALLOT_W := {"x0": -91.0, "x1": -64.0, "z0": 34.0, "z1": 70.0}
const NANO_E := {"x0": 65.0, "x1": 91.0, "z0": 12.0, "z1": 40.0}
const PATHS := [
	{"pts": [[-63, -9.5], [-70, -15], [-76, -22], [-84, -26.5], [-93, -29]], "w": 0.55, "kind": "dirt"},
	{"pts": [[70.5, -6.4], [70.2, -10], [68.6, -14.5], [67.6, -19.5], [69.4, -25], [74.5, -28.6], [80.5, -28.2], [85.2, -25.4], [87.6, -21], [86.4, -16.8], [83.4, -14.6], [80.6, -16.6], [79.2, -19.6]], "w": 0.7, "kind": "park"},
	{"pts": [[86.5, -6.4], [87.4, -11], [87.6, -16.5]], "w": 0.6, "kind": "park"},
	{"pts": [[-64, 72], [-72, 90], [-70, 108], [-78, 128]], "w": 0.5, "kind": "dirt"},
	{"pts": [[63, 44], [72, 62], [70, 84], [80, 104], [76, 128]], "w": 0.5, "kind": "dirt"},
	{"pts": [[-88, -57.6], [-90, -66], [-88.5, -76], [-90.5, -83.4]], "w": 0.5, "kind": "dirt"},
	{"pts": [[88, -57.6], [89.5, -68], [88, -83.4]], "w": 0.5, "kind": "dirt"},
]
const LEV := {"toe": -84.0, "shoulderT": -91.5, "shoulderR": -94.5, "riverTop": -99.0, "waterNear": -99.95, "waterFar": -117.33, "farTop": -119.0}
const FLAT := [
	{"x0": -117.0, "x1": 117.0, "z0": -122.0, "z1": 153.0, "r": 70.0},
	{"x0": -275.0, "x1": 275.0, "z0": -101.0, "z1": 215.0, "r": 70.0},
	{"x0": -110.0, "x1": 110.0, "z0": 116.0, "z1": 255.0, "r": 70.0},
	{"x0": -445.0, "x1": 445.0, "z0": -62.0, "z1": -24.0, "r": 55.0},
	{"x0": -5000.0, "x1": 5000.0, "z0": -282.0, "z1": -82.0, "r": 70.0},
]
const BRIDGE := {"x": -160.0, "halfW": 4.2, "zLevee": -93.0, "zAbut": -119.8, "deckY": 3.45}

var L
var _lotf := []


func _init(layout) -> void:
	L = layout
	for l in L.LOTS:
		var f: Dictionary = L.lot_frame(l)
		var e := f.duplicate()
		e["c"] = cos(f.rotY)
		e["s"] = sin(f.rotY)
		e["id"] = l.id
		_lotf.append(e)


## JavaScript's smoothstep from layout.js: also defined for a > b.
static func sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ------------------------------------------------------------------ noise

static func hash2(ix: int, iz: int, seed: int = 0) -> float:
	var h := Rng.to_i32(Rng.imul(Rng.to_i32(ix), 374761393) + Rng.imul(Rng.to_i32(iz), 668265263) + Rng.imul(Rng.to_i32(seed), 1442695041))
	h = Rng.imul(h ^ ((h & 0xFFFFFFFF) >> 13), 1274126177)
	h = Rng.to_i32(h ^ ((h & 0xFFFFFFFF) >> 16))
	return float(h & 0xFFFFFFFF) / 4294967296.0


## value noise 0..1
static func vnoise(x: float, z: float, seed: int = 0) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var fx := x - ix
	var fz := z - iz
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uz := fz * fz * (3.0 - 2.0 * fz)
	var a := hash2(ix, iz, seed)
	var b := hash2(ix + 1, iz, seed)
	var c := hash2(ix, iz + 1, seed)
	var d := hash2(ix + 1, iz + 1, seed)
	return a + (b - a) * ux + (c - a) * uz + (a - b - c + d) * ux * uz


## fractal noise 0..1
static func fbm(x: float, z: float, oct: int = 4, seed: int = 0) -> float:
	var s := 0.0
	var a := 0.5
	var n := 0.0
	var f := 1.0
	for i in oct:
		s += a * vnoise(x * f + i * 17.3, z * f - i * 9.1, seed + i * 7)
		n += a
		a *= 0.5
		f *= 2.03
	return s / n


## ridged noise 0..1 (sharp crests)
static func ridged(x: float, z: float, oct: int = 4, seed: int = 0) -> float:
	var s := 0.0
	var a := 0.5
	var n := 0.0
	var f := 1.0
	for i in oct:
		var v := 1.0 - absf(vnoise(x * f + i * 5.7, z * f + i * 3.1, seed + i * 11) * 2.0 - 1.0)
		s += a * v * v
		n += a
		a *= 0.5
		f *= 2.1
	return s / n


# ------------------------------------------------------------------ zones

func in_lot(x: float, z: float, pad: float = 0.0):
	for f in _lotf:
		var dx: float = x - f.x
		var dz: float = z - f.z
		var lx: float = dx * f.c - dz * f.s
		var lz: float = dx * f.s + dz * f.c
		if absf(lx) <= f.w / 2.0 + pad and lz <= pad and lz >= -f.depth - pad:
			return f
	return null


static func in_rect(x: float, z: float, r: Dictionary, pad: float = 0.0) -> bool:
	return x >= r.x0 - pad and x <= r.x1 + pad and z >= r.z0 - pad and z <= r.z1 + pad


## Signed-ish distance (m) from (x, z) to the nearest road surface edge (<= 0 on a road).
func road_dist(x: float, z: float) -> float:
	var d := 1e9
	if z > 0.5 and z < 131.0:
		d = minf(d, absf(x - L.street_center_x(z)) - 4.6)
	var R2: Dictionary = L.ROADS.R2
	var dx2: float = absf(x - R2.x) - R2.halfW
	var dz2: float = maxf(maxf(R2.z0 - z, z - R2.z1), 0.0)
	d = minf(d, sqrt(maxf(dx2, 0.0) ** 2 + dz2 * dz2) if maxf(dx2, 0.0) + dz2 > 0.0 else dx2)
	for k in ["R3", "R4", "R6"]:
		var R: Dictionary = L.ROADS[k]
		var dz: float = absf(z - R.z) - R.halfW
		var dx: float = maxf(maxf(R.x0 - x, x - R.x1), 0.0)
		d = minf(d, sqrt(dx * dx + maxf(dz, 0.0) ** 2) if dx > 0.0 else dz)
	return d


static func path_dist(x: float, z: float) -> Dictionary:
	var best := 1e9
	var kind = null
	var w := 1.0
	for p in PATHS:
		var pts: Array = p.pts
		for i in pts.size() - 1:
			var ax := float(pts[i][0])
			var az := float(pts[i][1])
			var vx := float(pts[i + 1][0]) - ax
			var vz := float(pts[i + 1][1]) - az
			var l2 := vx * vx + vz * vz
			var t := clampf(((x - ax) * vx + (z - az) * vz) / l2, 0.0, 1.0)
			var ex := x - ax - vx * t
			var ez := z - az - vz * t
			var d := sqrt(ex * ex + ez * ez) / float(p.w)
			if d < best:
				best = d
				kind = p.kind
				w = p.w
	return {"d": best, "kind": kind, "w": w}


## Owned by another module (roads, lots, blocks, plaza, station, crossing, far town)?
func owned_by_others(x: float, z: float, pad: float = 0.0):
	if road_dist(x, z) <= pad: return "road"
	if in_rect(x, z, L.PLAZA, pad): return "plaza"
	if in_rect(x, z, L.STATION, pad) or in_rect(x, z, L.STATION.forecourt, pad) or in_rect(x, z, L.STATION.sideYard, pad) or in_rect(x, z, L.STATION.westYard, pad): return "station"
	if in_rect(x, z, L.CROSSING.zone, pad): return "crossing"
	if in_lot(x, z, pad) != null: return "lot"
	for b in L.BLOCKS:
		if in_rect(x, z, b, pad): return "block"
	for b in L.FAR_TOWN:
		if in_rect(x, z, b, pad): return "fartown"
	return null


func in_corridor(x: float, z: float, pad: float = 0.0) -> bool:
	return z >= L.RAIL.corridorZ0 - pad and z <= L.RAIL.corridorZ1 + pad and absf(x) <= 440.0


# ------------------------------------------------------------------ extended terrain height

static func _rect_influence(x: float, z: float, r: Dictionary) -> float:
	var dx: float = maxf(maxf(r.x0 - x, 0.0), x - r.x1)
	var dz: float = maxf(maxf(r.z0 - z, 0.0), z - r.z1)
	return 1.0 - sstep(0.0, r.r, sqrt(dx * dx + dz * dz))


## 0 inside flat zones, 1 in the free hills.
static func hill_mask(x: float, z: float) -> float:
	var m := 1.0
	for r in FLAT:
		m *= 1.0 - _rect_influence(x, z, r)
		if m <= 0.0:
			return 0.0
	return m


static func _bump(v: float, c: float, w: float) -> float:
	var t := 1.0 - clampf(absf(v - c) / w, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Raw hill relief (before masking): north foothills and a second range; rolling hills elsewhere.
static func hill_relief(x: float, z: float) -> float:
	if z < -181.0:
		var zz := z + (fbm(x / 260.0, 3.3, 3, 11) - 0.5) * 90.0
		var r1 := _bump(zz, -372.0, 88.0) * (17.0 + 26.0 * fbm(x / 120.0, 1.7, 3, 12))
		var r2 := _bump(zz, -575.0, 150.0) * (38.0 + 36.0 * ridged(x / 210.0, 4.1, 3, 13))
		var plain := sstep(-282.0, -430.0, zz) * 7.0 + sstep(-470.0, -700.0, zz) * 16.0
		var small := (fbm(x / 45.0, z / 45.0, 3, 14) - 0.5) * 7.0 * sstep(-282.0, -330.0, z)
		return maxf(r1, r2 * 0.25) + r2 * 0.8 + plain + small
	var re := sqrt(x * x + ((z - 30.0) / 1.08) ** 2)
	var g := sstep(250.0, 560.0, re)
	var n := fbm(x / 170.0, z / 170.0, 4, 21)
	var n2 := fbm(x / 60.0, z / 60.0, 3, 22)
	return g * (14.0 + 42.0 * n * n + 9.0 * n2) + sstep(520.0, 720.0, re) * 22.0 * fbm(x / 300.0, z / 300.0, 2, 23)


func _bridge_embankment(x: float, z: float) -> float:
	if z > -118.6 or z < -182.0:
		return 0.0
	var top: float = lerpf(BRIDGE.deckY, L.height_at(BRIDGE.x, -175.0), sstep(-120.0, -175.0, z))
	var side := maxf(0.0, absf(x - BRIDGE.x) - 4.5)
	var h_top := top - side * 0.55
	var base: float = L.height_at(x, z)
	return maxf(0.0, h_top - base) * sstep(-118.6, -120.2, z)


static func park_mound(x: float, z: float) -> float:
	var M: Dictionary = PARK.mound
	var dx: float = (x - M.x) / M.rx
	var dz: float = (z - M.z) / M.rz
	var d := sqrt(dx * dx + dz * dz)
	if d >= 1.0:
		return 0.0
	var f := 0.5 * (1.0 + cos(PI * d))
	var lx: float = (x - M.x - 5.0) / 5.0
	var lz: float = (z - M.z - 3.0) / 4.0
	var lobe := 0.18 * maxf(0.0, 1.0 - sqrt(lx * lx + lz * lz))
	return M.h * f * (1.0 + lobe)


## Terrain height of the environment mesh; equals L.height_at wherever other modules build.
func terrain_h(x: float, z: float) -> float:
	var h: float = L.height_at(x, z)
	var m := hill_mask(x, z)
	if m > 0.0:
		h += m * hill_relief(x, z)
	if x > -200.0 and x < -120.0:
		h += _bridge_embankment(x, z)
	if x > 66.0 and x < 91.0 and z > -30.0 and z < -11.0:
		h += park_mound(x, z)
	return h


func terrain_normal(x: float, z: float, e: float = 0.5) -> Array:
	var hx := terrain_h(x + e, z) - terrain_h(x - e, z)
	var hz := terrain_h(x, z + e) - terrain_h(x, z - e)
	var nx := -hx
	var ny := 2.0 * e
	var nz := -hz
	var l := sqrt(nx * nx + ny * ny + nz * nz)
	return [nx / l, ny / l, nz / l]


# ------------------------------------------------------------------ helpers

## A Geometry from flat arrays: position, optional normal / uv / color, optional index.
static func make_geo(pos, idx, opts: Dictionary = {}) -> T.Geometry:
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(PackedFloat32Array(pos), 3))
	if opts.get("nrm") != null:
		g.set_attribute("normal", T.Attr.new(PackedFloat32Array(opts.nrm), 3))
	if opts.get("uv") != null:
		g.set_attribute("uv", T.Attr.new(PackedFloat32Array(opts.uv), 2))
	if opts.get("col") != null:
		g.set_attribute("color", T.Attr.new(PackedFloat32Array(opts.col), 3))
	if idx != null:
		g.set_index(PackedInt32Array(idx))
	if opts.get("nrm") == null:
		g.compute_vertex_normals()
	g.compute_bounding_box()
	return g


## sRGB hex to linear [r, g, b].
static func lin(hex) -> Array:
	var c := T.color(hex)
	return [c.r, c.g, c.b]


static func mix3(a: Array, b: Array, t: float) -> Array:
	return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]


static func mul3(a: Array, k: float) -> Array:
	return [a[0] * k, a[1] * k, a[2] * k]


## Bakes each plain opaque toon mesh's colour into a vertex colour and gives it one shared
## vertex-coloured material, so the batcher merges them into one mesh per cell.
static func bake_colors(ctx, root) -> int:
	var shared = ctx.mat.toon("#ffffff", {"vertexColors": true, "paint": 0.06, "name": "env-vc"})
	var n := [0]
	root.traverse(func(o):
		if not o.is_mesh or o.is_instanced:
			return
		var m = o.material
		if m == null or m is Array or m.type != "toon" or m == shared:
			return
		if m.map != null or m.alpha_map != null or m.transparent or m.vertex_colors or m.polygonOffset or m.side != "front" or m.alpha_test > 0.0:
			return
		if m.emissive.r + m.emissive.g + m.emissive.b > 0.0:
			return
		var g: T.Geometry = o.geometry.clone()
		var cnt := g.vertex_count()
		var a := PackedFloat32Array()
		a.resize(cnt * 3)
		for i in cnt:
			a[i * 3] = m.color.r
			a[i * 3 + 1] = m.color.g
			a[i * 3 + 2] = m.color.b
		g.set_attribute("color", T.Attr.new(a, 3))
		o.geometry = g
		o.material = shared
		n[0] += 1)
	return n[0]


## Unit icosphere with radial normals: round cel-shaded clumps.
static func smooth_blob(detail: int = 1) -> T.Geometry:
	var Geo = load("res://addons/sakuragaoka_station/core/geo.gd")
	var g: T.Geometry = Geo.icosahedron(1, detail)
	var pa: T.Attr = g.attributes.position
	var na: T.Attr = g.attributes.normal
	for i in pa.count():
		var x := pa.get_x(i)
		var y := pa.get_y(i)
		var z := pa.get_z(i)
		var l := sqrt(x * x + y * y + z * z)
		na.set_xyz(i, x / l, y / l, z / l)
	return g
