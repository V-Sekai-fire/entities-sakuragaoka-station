# sakura/tree.js: the seeded procedural cherry tree (Somei-Yoshino style, and the weeping cherry).
# Canopy: flower clusters (pads) sampled on a lobed umbrella envelope, grouped into one lobe per
# branch and fused into one blossom-mass surface per crown (canopy.gd), dressed with blossom cards.
# Skeleton: trunk, limbs forking at staggered heights, secondary limbs, branches spread along their
# parent, one twig per cluster, grown toward the clusters so branches carry the flowers.
# Everything is emitted in world space into three builders: bark, blob, cards.
extends RefCounted

const U = preload("res://addons/sakuragaoka_station/world/sakura/util.gd")
const CP = preload("res://addons/sakuragaoka_station/world/sakura/canopy.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")
const T = preload("res://addons/sakuragaoka_station/core/three.gd")

## The four tone bands (deep pink -> sakura -> pale -> near-white) and the peach accent.
const BANDS := {
	"normal": ["#e597b2", "#f3bccd", "#f9d8e2", "#fce9ef"],
	"weeping": ["#dc81a1", "#e99db7", "#f2c0d0", "#f8dde6"],
	"peach": "#f6c7b8",
}

## LOD quality. padK: cluster size factor; h: surface-nets grid step (m); amp / freq: billow
## displacement; cov / covIn: card coverage outside / in the cavity; hang: hanging-spray share.
const LODQ := [
	{"padK": 0.66, "innerX": 0.22, "h": 0.23, "amp": 0.34, "freq": 1.6, "cov": 4.5, "covIn": 1.3, "hang": 0.3, "trunkSeg": 12, "limbSeg": 8, "subSeg": 6, "twigSeg": 4,
		"cardK": 1.0, "cardS": 0.72, "sprig": 0.22, "stubs": 2, "twigs": true, "roots": 5},
	{"padK": 0.8, "innerX": 0.15, "fill": true, "smooth": 3, "cover": 0.62, "h": 0.4, "amp": 0.34, "freq": 1.05, "cov": 2.1, "covIn": 0.8, "hang": 0.25, "trunkSeg": 7,
		"limbSeg": 5, "subSeg": 4, "twigSeg": 3, "cardK": 1.0, "cardS": 0.9, "twigP": 0.45, "sprig": 0.1, "stubs": 0, "twigs": true, "roots": 3},
	{"padK": 1.05, "fill": true, "smooth": 3, "h": 0.6, "amp": 0.32, "freq": 0.7, "cov": 0.8, "covIn": 0.0, "hang": 0.15, "trunkSeg": 7, "limbSeg": 5, "subSeg": 4,
		"twigSeg": 3, "cardK": 1.0, "cardS": 1.15, "sprig": 0.0, "stubs": 0, "twigs": false, "roots": 0},
]

## atlas cells (u0, v0) of the 2x2 blossom atlas
const CELL := {"dense": [0.0, 0.5], "spray": [0.5, 0.5], "loose": [0.0, 0.0], "leaf": [0.5, 0.0]}

static var _pal := {}


## Linear-rgb palettes.
static func pal() -> Dictionary:
	if _pal.is_empty():
		var normal := []
		for h in BANDS.normal:
			normal.append(U.hex(h))
		var weeping := []
		for h in BANDS.weeping:
			weeping.append(U.hex(h))
		_pal = {"normal": normal, "weeping": weeping, "peach": U.hex(BANDS.peach), "leaf": U.hex("#f1efe3")}
	return _pal


static func rand_unit(r: Rng, out: U.V = null) -> U.V:
	if out == null:
		out = U.V.new()
	var z := r.f() * 2.0 - 1.0
	var a := r.f() * PI * 2.0
	var s := sqrt(1.0 - z * z)
	return out.set3(cos(a) * s, z, sin(a) * s)


## Pushes p (half extents rx, ry) out of keep-out boxes and above the floor (+floor_off).
## Returns the displacement.
static func constrain(p: U.V, rx: float, ry: float, spec: Dictionary, skip_floor: bool = false, floor_off: float = 0.0) -> float:
	var moved := 0.0
	for b in spec.get("keepOut", []):
		if p.x + rx > b.x0 and p.x - rx < b.x1 and p.z + rx > b.z0 and p.z - rx < b.z1 and p.y + ry > b.y0 and p.y - ry < b.y1:
			var d := 0.0
			match b.push:
				"x+":
					d = b.x1 + rx - p.x
					p.x += d
				"x-":
					d = p.x - (b.x0 - rx)
					p.x -= d
				"z+":
					d = b.z1 + rx - p.z
					p.z += d
				"z-":
					d = p.z - (b.z0 - rx)
					p.z -= d
				"y+":
					d = b.y1 + ry - p.y
					p.y += d
			moved += absf(d)
	if not skip_floor and spec.get("floorAt") != null:
		var f: float = spec.floorAt.call(p.x, p.z) + floor_off
		if p.y - ry < f:
			moved += f - (p.y - ry)
			p.y = f + ry
	if spec.has("ceilY") and p.y + ry > spec.ceilY:
		moved += p.y + ry - spec.ceilY
		p.y = spec.ceilY - ry
	return moved


static func _d2(a: U.V, b: U.V, wy: float) -> float:
	var dx := a.x - b.x
	var dy := (a.y - b.y) * wy
	var dz := a.z - b.z
	return dx * dx + dy * dy + dz * dz


## k-means on points (y weighted); returns arrays of indices.
static func kmeans(points: Array, k: int, r: Rng, wy: float = 1.0) -> Array:
	if points.size() <= k:
		var single := []
		for i in points.size():
			single.append([i])
		return single
	var cent := [points[floori(r.f() * points.size())].clone()]
	while cent.size() < k:
		var best := -1.0
		var bi := 0
		for i in points.size():
			var m := INF
			for c in cent:
				m = minf(m, _d2(points[i], c, wy))
			if m > best:
				best = m
				bi = i
		cent.append(points[bi].clone())
	var groups := []
	for it in 8:
		groups = []
		for c in cent:
			groups.append([])
		for i in points.size():
			var m := INF
			var gi := 0
			for c in cent.size():
				var d := _d2(points[i], cent[c], wy)
				if d < m:
					m = d
					gi = c
			groups[gi].append(i)
		for c in cent.size():
			if groups[c].is_empty():
				continue
			cent[c].set3(0, 0, 0)
			for i in groups[c]:
				cent[c].add(points[i])
			cent[c].div(groups[c].size())
	var out := []
	for g in groups:
		if not g.is_empty():
			out.append(g)
	return out


## The crown envelope: smooth normals, blended shading normals and the tone of a point.
class Canopy extends RefCounted:
	var C: U.V
	var cx := 0.0
	var cy := 0.0
	var cz := 0.0
	var Rx := 1.0
	var Ry := 1.0
	var Rz := 1.0
	var pal: Array
	var pal_id := 0
	var weeping := false
	var noise: U.ValueNoise
	var sun: Array
	var wc := 0.36
	var wl := 0.52
	var wp := 0.14
	var wup := 0.08
	var nc := U.V.new()
	var nl := U.V.new()
	var np := U.V.new()

	func _init(c: U.V, rx: float, ry: float, rz: float, pal_: Array, noise_: U.ValueNoise, weeping_: bool, sun_: Array) -> void:
		C = c
		cx = c.x
		cy = c.y
		cz = c.z
		Rx = rx
		Ry = ry
		Rz = rz
		pal = pal_
		noise = noise_
		weeping = weeping_
		pal_id = 1 if weeping_ else 0
		sun = sun_
		if weeping_:
			wc = 0.6
			wl = 0.0
			wp = 0.4
			wup = 0.1

	func normal_at(p: U.V, out: U.V = null) -> U.V:
		if out == null:
			out = U.V.new()
		if weeping:
			out.set3((p.x - cx) / Rx, ((p.y - cy) / Ry) * 0.45 + 0.28, (p.z - cz) / Rz)
		else:
			out.set3((p.x - cx) / Rx, (p.y - cy) / Ry + 0.16, (p.z - cz) / Rz)
		return out.normalize()

	## blended canopy / lobe / pad normal (pad_n optional: an analytic pad normal)
	func field(p: U.V, pad, pad_n, out: U.V) -> U.V:
		normal_at(p, nc)
		var L = pad.lobe
		if L != null:
			nl.set3((p.x - L.c.x) / L.rx, (p.y - L.c.y) / L.ry + 0.12, (p.z - L.c.z) / L.rz).normalize()
		else:
			nl.copy(nc)
		if pad_n != null:
			np.copy(pad_n)
		else:
			np.set3((p.x - pad.c.x) / pad.rx, (p.y - pad.c.y) / pad.ry, (p.z - pad.c.z) / pad.rz).normalize()
		return out.set3(nc.x * wc + nl.x * wl + np.x * wp, nc.y * wc + nl.y * wl + np.y * wp + wup, nc.z * wc + nl.z * wl + np.z * wp).normalize()

	## scalar tone in [0, 1]: higher, more outward and lit = paler; inner and underside = deeper
	func tone_t(x: float, y: float, z: float, jit: float = 0.0) -> float:
		var h := U.clamp01((y - (cy - Ry * 0.8)) / (Ry * 1.8))
		var o := minf(1.25, U.hypot3((x - cx) / Rx, (y - cy) / Ry, (z - cz) / Rz))
		var ex := (x - cx) / Rx
		var ey := ((y - cy) / Ry) * 0.45 + 0.28 if weeping else (y - cy) / Ry + 0.16
		var ez := (z - cz) / Rz
		var el := sqrt(ex * ex + ey * ey + ez * ez)
		var inv := 1.0 / (el if el != 0.0 else 1.0)
		var s: float = ex * inv * sun[0] + ey * inv * sun[1] + ez * inv * sun[2]
		return U.clamp01(0.22 + 0.5 * h + 0.28 * (o - 0.55) + 0.12 * s + jit + noise.n3(x * 0.55, y * 0.55, z * 0.55) * 0.16)

	func tone(p: U.V, jit: float, extra: float = 0.0) -> Array:
		return U.band_color(pal, tone_t(p.x, p.y, p.z, jit + extra))


static func taper(n: int, r0: float, r1: float, pw: float = 0.9) -> Array:
	var a := []
	for i in n + 1:
		a.append(r0 + (r1 - r0) * pow(float(i) / n, pw))
	return a


static func point_at(pts: Array, t: float) -> U.V:
	var f := t * (pts.size() - 1)
	var i := mini(pts.size() - 2, floori(f))
	return U.V.new().lerp_vectors(pts[i], pts[i + 1], f - i)


static func dir_at(pts: Array, t: float) -> U.V:
	var f := t * (pts.size() - 1)
	var i := mini(pts.size() - 2, floori(f))
	return U.V.new().sub_vectors(pts[i + 1], pts[i]).normalize()


static func closest_t(pts: Array, p: U.V, t_min: float = 0.0) -> float:
	var best := INF
	var bt := 1.0
	for i in pts.size():
		var t := float(i) / (pts.size() - 1)
		if t < t_min:
			continue
		var d: float = pts[i].distance_to_squared(p)
		if d < best:
			best = d
			bt = t
	return bt


static func centroid(list: Array) -> U.V:
	var c := U.V.new()
	for p in list:
		c.add(p.c)
	return c.div(list.size())


static func estimate_pads(Rx: float, Ry: float, Rz: float, pr: float) -> float:
	var p := 1.6
	var a := Rx
	var b := Rz
	var c := Ry
	var A := 4.0 * PI * pow((pow(a * b, p) + pow(a * c, p) + pow(b * c, p)) / 3.0, 1.0 / p)
	return (A * 0.7) / (PI * pr * pr) * 1.3


static func summarize(pads: Array, gy: float, spec: Dictionary) -> Dictionary:
	var sx := 0.0
	var sy := 0.0
	var sz := 0.0
	var sw := 0.0
	var top := -INF
	var bot := INF
	for p in pads:
		var w: float = p.rx * p.rz
		sx += p.c.x * w
		sy += p.c.y * w
		sz += p.c.z * w
		sw += w
		top = maxf(top, p.c.y + p.ry)
		bot = minf(bot, p.c.y - p.ry)
	if sw == 0.0:
		return {"x": spec.x, "z": spec.z, "y": gy + spec.height * 0.6, "r": 2.0, "h": spec.height, "bottom": gy + 2.0}
	var cx := sx / sw
	var cy := sy / sw
	var cz := sz / sw
	var rad := 0.0
	for p in pads:
		rad = maxf(rad, U.hypot2(p.c.x - cx, p.c.z - cz) + maxf(p.rx, p.rz) * 0.9)
	return {"x": cx, "z": cz, "y": cy, "r": rad, "h": top - gy, "bottom": bot}


## spec: {id, kind ('old' | 'medium' | 'young' | 'weeping'), seed, x, z, height, spread, spreadZ?, trunkR,
## forkH, lean, offset, limbs, lod, padR, vr, lobes, gaps, archDirs, thetaMax, floorAt, keepOut, ceilY,
## bark, rootReach, ...}; env: {rng: Callable(key) -> Rng, noise, heightAt: Callable, sun}.
## Returns {bark, blob, cards (GeoBuilders), info, colliders, groundY}.
static func make_tree(spec: Dictionary, env: Dictionary) -> Dictionary:
	if spec.kind == "weeping":
		return make_weeping(spec, env)
	var r: Rng = env.rng.call(spec.get("seed", spec.id))
	var noise: U.ValueNoise = env.noise
	var Q: Dictionary = LODQ[spec.get("lod", 0)]
	var bark := U.GeoBuilder.new()
	var blob := U.GeoBuilder.new()
	var cards := U.GeoBuilder.new()
	var H: Callable = env.heightAt
	var sx: float = spec.x
	var sz: float = spec.z
	var trunk_r: float = spec.trunkR
	var fork_h: float = spec.forkH
	var gy: float = H.call(sx, sz)
	var g_min := gy
	for k in 10:
		var a := (k / 10.0) * PI * 2.0
		g_min = minf(g_min, H.call(sx + cos(a) * trunk_r * 2.4, sz + sin(a) * trunk_r * 2.4))
	var lean: Array = spec.get("lean", [0.0, 0.0])
	var off: Array = spec.get("offset", [0.0, 0.0])
	var Fk := U.V.new(sx + lean[0], gy + fork_h, sz + lean[1])
	var Rx: float = spec.spread
	var Rz: float = spec.get("spreadZ", spec.spread)
	var Ry: float = spec.spread * spec.get("vr", 0.56)
	var top: float = gy + spec.height
	var C := U.V.new(Fk.x + off[0], top - Ry, Fk.z + off[1])
	var P := pal()
	var canopy := Canopy.new(C, Rx, Ry, Rz, P.normal, noise, false, env.sun)
	var pad_r: float = spec.get("padR", 1.25) * Q.padK
	var UP := U.V.new(0, 1, 0)

	# ------------------------------------------------ 1. pad targets on a lobed umbrella envelope
	var theta_max: float = spec.get("thetaMax", 1.95)
	var arch: Array = spec.get("archDirs", [])
	var n_outer := int(T.js_round(spec.padCount if spec.has("padCount") else estimate_pads(Rx, Ry, Rz, pad_r) * Q.get("cover", 1.0)))
	var gap_dirs := []
	var n_gaps: int = spec.get("gaps", 1 if spec.get("lod", 0) else 3)
	for g in n_gaps:
		var th := 0.95 + r.f() * 0.8
		var ph := r.f() * PI * 2.0
		gap_dirs.append(U.V.new(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)))
	var cand := []
	var n_cand := n_outer * 9
	var ga := PI * (3.0 - sqrt(5.0))
	var phase := r.f() * PI * 2.0
	var lobes: float = spec.get("lobes", 0.18)
	for i in n_cand:
		var y := 1.0 - (i + 0.5) / n_cand * 2.0
		var th := acos(y)
		var ph := phase + i * ga
		var tmax := theta_max
		for a in arch:
			var d := absf(atan2(sin(ph - a), cos(ph - a)))
			tmax = maxf(tmax, theta_max + 0.42 * maxf(0.0, 1.0 - d / 0.75))
		if th > tmax:
			continue
		var dx := sin(th) * cos(ph)
		var dz := sin(th) * sin(ph)
		var dy := cos(th)
		var in_gap := false
		for gd in gap_dirs:
			if gd.x * dx + gd.y * dy + gd.z * dz > 0.955:
				in_gap = true
		if in_gap:
			continue
		var lobe := 1.0 + lobes * noise.n3(dx * 1.3 + 3.3, dy * 1.3, dz * 1.3 - 1.1) + 0.07 * noise.n3(dx * 3.4 + 7.0, dy * 3.4, dz * 3.4)
		var droop := 1.0 + 0.12 * (th - PI / 2.0) if th > PI / 2.0 else 1.0
		cand.append({"d": U.V.new(dx, dy, dz), "s": lobe * droop, "th": th})
	for i in range(cand.size() - 1, 0, -1):
		var j := floori(r.f() * (i + 1))
		var t = cand[i]
		cand[i] = cand[j]
		cand[j] = t
	var pads := []
	var try_pad := func(p: U.V, pr: float, layer: int) -> bool:
		var pad := CP.Pad.new()
		pad.c = p
		pad.rx = pr * (0.9 + r.f() * 0.32)
		pad.rz = pr * (0.84 + r.f() * 0.32)
		pad.ry = pr * (0.44 + r.f() * 0.12)
		pad.layer = layer
		var moved := constrain(pad.c, maxf(pad.rx, pad.rz) * 0.85, pad.ry, spec)
		if moved > pr * 1.8:
			return false
		for o in pads:
			if o.c.distance_to(pad.c) < (pr + (o.rx + o.rz) * 0.5) * (0.5 if layer else 0.55):
				return false
		pads.append(pad)
		return true
	for cd in cand:
		if pads.size() >= n_outer:
			break
		var pr: float = pad_r * (0.78 + r.f() * 0.45) * (1.1 if cd.th < 0.6 else 1.0)
		var k: float = cd.s
		var p := U.V.new(C.x + cd.d.x * Rx * k, C.y + cd.d.y * Ry * k, C.z + cd.d.z * Rz * k)
		p.add(canopy.normal_at(p, U.V.new()).mul(-pr * 0.5))
		try_pad.call(p, pr, 0)
	var n_inner := int(T.js_round(pads.size() * spec.get("inner", 0.2)))
	var ii := 0
	var tries := 0
	while ii < n_inner and tries < n_inner * 8:
		tries += 1
		var cd: Dictionary = cand[floori(r.f() * cand.size())]
		if cd.th > 1.5:
			continue
		var k: float = cd.s * (0.62 + r.f() * 0.16)
		var pr := pad_r * (0.7 + r.f() * 0.3)
		var p := U.V.new(C.x + cd.d.x * Rx * k, C.y + cd.d.y * Ry * k, C.z + cd.d.z * Rz * k)
		if try_pad.call(p, pr, 1):
			ii += 1
	for pad in pads:
		pad.seed = r.f() * 50.0
		pad.jit = (r.f() - 0.5) * 0.14 - pad.layer * 0.14
		pad.peach = 0.3 + r.f() * 0.35 if r.f() < 0.14 else 0.0
		r.f()
		r.f()
		var n := canopy.normal_at(pad.c, U.V.new())
		var upv := U.V.new().copy(UP).lerp(n, 0.18 + r.f() * 0.16).normalize()
		pad.q = U.Q.new().set_from_unit_vectors(UP, upv).multiply(U.Q.new().set_from_axis_angle(UP, r.f() * PI * 2.0))
	# low clusters of near trees (seen from 1-5 m below): smaller kernels and denser cards
	if spec.get("lod", 0) == 0:
		for pad in pads:
			var hb: float = pad.c.y - pad.ry - gy
			if hb < 6.0:
				var kk := U.clamp01((hb - 2.6) / 3.4)
				pad.core = 0.72 + 0.28 * kk

	# ------------------------------------------------ 2. skeleton
	var branches := []
	var B0 := U.V.new(sx, g_min - 0.3, sz)
	var lean_early: float = spec.get("leanEarly", 0.18)
	var tc := U.V.new(sx + lean[0] * lean_early, gy + fork_h * 0.55, sz + lean[1] * lean_early)
	var n_tr := maxi(6, int(T.js_round(fork_h / 0.3)) + 2)
	var tpts := U.bezier(B0, tc, Fk, n_tr)
	var trad := []
	var tph := r.f() * 100.0
	for i in tpts.size():
		var t := float(i) / (tpts.size() - 1)
		var tp: U.V = tpts[i]
		var h_above := tp.y - gy
		if i > 0 and i < tpts.size() - 1:
			var w := sin(t * PI) * trunk_r * 0.5
			tp.x += noise.n3(tph + tp.y * 0.55, 1.3, 2.1) * w
			tp.z += noise.n3(tph + tp.y * 0.55, 7.7, 4.9) * w
		var flare := 1.0 + 0.55 * pow(1.0 - U.clamp01(h_above / 0.9), 2.2) if h_above < 0.9 else 1.0
		var bulge := 1.0 + 0.07 * noise.n3(tp.y * 1.6 + tph, 0.3, 0.5) + (0.1 if t > 0.86 else 0.0)
		trad.append(trunk_r * flare * bulge * (1.0 - 0.14 * t))
	branches.append({"pts": tpts, "radii": trad, "seg": Q.trunkSeg, "depth": 0})

	var n_limbs := mini(spec.get("limbs", 4), pads.size())
	var dirs := []
	for p in pads:
		dirs.append(U.V.new().sub_vectors(p.c, Fk).set_y((p.c.y - Fk.y) * 0.45).normalize())
	var limb_groups := kmeans(dirs, n_limbs, r, 1.0)
	var total_pads := pads.size()
	var colliders := []
	var gn: float = spec.get("gnarl", 0.1)
	# a smooth, low-frequency wobble along a bezier (no zig-zag)
	var shaped := func(S: U.V, E: U.V, ctrl_up: float, gnarl: float, n: int, rad: float, parent_dir) -> Array:
		var len := S.distance_to(E)
		var ctrl := U.V.new().lerp_vectors(S, E, 0.5)
		if parent_dir != null:
			ctrl.add_scaled(parent_dir, len * 0.24)
		ctrl.y += len * ctrl_up
		var pts := U.bezier(S, ctrl, E, n)
		var ph := r.f() * 100.0
		for i in range(1, pts.size() - 1):
			var t := float(i) / (pts.size() - 1)
			var w := sin(t * PI) * len * gnarl
			var s := ph + t * len * 0.42
			var pt: U.V = pts[i]
			pt.x += noise.n3(s, 0.3, 1.7) * w
			pt.y += noise.n3(s, 5.1, 2.3) * w * 0.5
			pt.z += noise.n3(s, 9.7, 4.1) * w
			var horiz := U.hypot2(pt.x - sx, pt.z - sz)
			constrain(pt, rad, rad, spec, horiz < 1.3, -0.6)
		return pts

	# Limbs fork off the upper trunk at staggered heights (low, sideways-reaching groups leave first),
	# split into 1-3 secondary limbs, which carry branches spread along their length, which carry one
	# twig per flower cluster.
	var limb_data := []
	for grp in limb_groups:
		var gp := []
		for i in grp:
			gp.append(pads[i])
		var cen := centroid(gp)
		var d := U.V.new().sub_vectors(cen, Fk)
		var dl := d.length()
		limb_data.append({"gp": gp, "cen": cen, "elev": d.y / (dl if dl != 0.0 else 1.0)})
	limb_data = T.stable_sort(limb_data, func(a, b): return a.elev - b.elev)
	var f_low: float = spec.get("forkSpread", 0.7 if fork_h > 1.6 else 0.9)
	for li in limb_data.size():
		var LD: Dictionary = limb_data[li]
		var gp: Array = LD.gp
		var cen: U.V = LD.cen
		var limb_r := trunk_r * 0.93 * sqrt(float(gp.size()) / total_pads)
		var f := f_low + (1.0 - f_low) * (float(li) / (limb_data.size() - 1)) if limb_data.size() > 1 else 1.0
		var h_dir := U.V.new().sub_vectors(cen, Fk).set_y(0).normalize()
		var S := point_at(tpts, f).add_scaled(h_dir, trunk_r * 0.25)
		if f > 0.97:
			S.y -= trunk_r * 0.4
		var reach: float = spec.get("limbReach", 0.62)
		var E := U.V.new().lerp_vectors(S, cen, reach + r.f() * 0.1)
		constrain(E, limb_r, limb_r, spec, false, -0.6)
		var len_l := S.distance_to(E)
		var n_l := maxi(5, int(T.js_round(len_l / 0.42)))
		var lpts: Array = shaped.call(S, E, spec.get("limbArch", 0.22), gn, n_l, limb_r, null)
		branches.append({"pts": lpts, "radii": taper(n_l, limb_r, limb_r * 0.5), "seg": Q.limbSeg, "depth": 1})

		var n_sec := 3 if gp.size() >= 24 else (2 if gp.size() >= 9 else 1)
		var sec_idx := []
		if n_sec > 1:
			var cs := []
			for p in gp:
				cs.append(p.c)
			sec_idx = kmeans(cs, n_sec, r, 1.2)
		else:
			var all := []
			for i in gp.size():
				all.append(i)
			sec_idx = [all]
		var secs := []
		for sg in sec_idx:
			var sp := []
			for i in sg:
				sp.append(gp[i])
			var c := centroid(sp)
			secs.append({"sp": sp, "c": c, "t": closest_t(lpts, c, 0.25)})
		secs = T.stable_sort(secs, func(a, b): return a.t - b.t)
		for si in secs.size():
			var sec: Dictionary = secs[si]
			var spts: Array = lpts
			var s_r := limb_r * 0.72
			var s_depth := 1
			if secs.size() > 1:
				var tS := minf(0.9, maxf(0.28, 0.5 * (0.28 + 0.55 * (si + 0.5) / secs.size()) + 0.5 * sec.t))
				var SA := point_at(lpts, tS)
				var s_rad := maxf(0.04, limb_r * 0.86 * sqrt(float(sec.sp.size()) / gp.size()))
				var EA := U.V.new().lerp_vectors(SA, sec.c, 0.56 + r.f() * 0.1)
				constrain(EA, s_rad, s_rad, spec, false, -0.6)
				var len_s := SA.distance_to(EA)
				if len_s > 0.4:
					var n_s := maxi(4, int(T.js_round(len_s / 0.42)))
					spts = shaped.call(SA, EA, 0.16, gn * 1.05, n_s, s_rad, dir_at(lpts, tS))
					branches.append({"pts": spts, "radii": taper(n_s, s_rad, s_rad * 0.55), "seg": maxi(Q.subSeg, Q.limbSeg - 2), "depth": 2})
					s_r = s_rad * 0.8
					s_depth = 2
			var n_sub := maxi(1, int(T.js_round(sec.sp.size() / float(spec.get("padsPerBranch", 3)))))
			var scs := []
			for p in sec.sp:
				scs.append(p.c)
			var subs := []
			for sg in kmeans(scs, n_sub, r, 1.4):
				var sp := []
				for i in sg:
					sp.append(sec.sp[i])
				var sc := centroid(sp)
				subs.append({"sp": sp, "sc": sc, "t": closest_t(spts, sc, 0.3)})
			subs = T.stable_sort(subs, func(a, b): return a.t - b.t)
			for ui in subs.size():
				var sub: Dictionary = subs[ui]
				var sp: Array = sub.sp
				var sc: U.V = sub.sc
				# lobe (clump) volume for normal transfer
				var lrx := 0.0
				var lry := 0.0
				var lrz := 0.0
				for p in sp:
					lrx = maxf(lrx, absf(p.c.x - sc.x) + p.rx)
					lrz = maxf(lrz, absf(p.c.z - sc.z) + p.rz)
					lry = maxf(lry, absf(p.c.y - sc.y) + p.ry)
				var lobe := CP.Lobe.new()
				lobe.c = sc.clone()
				lobe.rx = maxf(lrx, 0.8)
				lobe.rz = maxf(lrz, 0.8)
				lobe.ry = maxf(lry, maxf(lrx, lrz) * 0.55)
				lobe.jit = (r.f() - 0.5) * 0.18
				for p in sp:
					p.lobe = lobe
					p.jit += lobe.jit
				var sub_r := maxf(0.03, s_r * 0.9 * sqrt(float(sp.size()) / sec.sp.size()))
				var t_rank := (0.3 if s_depth > 1 else 0.4) + 0.62 * (ui + 0.5) / subs.size()
				var tA := minf(0.97, maxf(0.3, 0.55 * t_rank + 0.45 * sub.t + (r.f() - 0.5) * 0.06))
				var SA := point_at(spts, tA)
				var EA := U.V.new().lerp_vectors(SA, sc, 0.72 + r.f() * 0.1)
				EA.y -= 0.15
				constrain(EA, sub_r, sub_r, spec, false, -0.6)
				var len_s := SA.distance_to(EA)
				var bpts = null
				if len_s > 0.25:
					var n_s := maxi(3, int(T.js_round(len_s / 0.42)))
					bpts = shaped.call(SA, EA, 0.12, gn * 1.1, n_s, sub_r, dir_at(spts, tA))
					branches.append({"pts": bpts, "radii": taper(n_s, sub_r, sub_r * 0.5), "seg": Q.subSeg, "depth": 2})
				var tw_r := maxf(0.014, sub_r * 0.55 / sqrt(sp.size()))
				for pad in sp:
					var src: Array = bpts if bpts != null else spts
					var tt := maxf(0.5, closest_t(bpts, pad.c, 0.5)) if bpts != null else maxf(0.6, closest_t(spts, pad.c, 0.6))
					var TS := point_at(src, tt)
					var TE := U.V.new().copy(pad.c)
					TE.y -= pad.ry * 0.3
					var len_t := TS.distance_to(TE)
					if Q.twigs and len_t > 0.2 and r.f() < Q.get("twigP", 1.0):
						var n_t := maxi(2, int(T.js_round(len_t / 0.55)))
						var tp: Array = shaped.call(TS, TE, 0.1, 0.1, n_t, tw_r, dir_at(src, tt))
						branches.append({"pts": tp, "radii": taper(n_t, tw_r, tw_r * 0.55), "seg": Q.twigSeg, "depth": 3})
					pad.twig_dir = U.V.new().sub_vectors(TE, TS).normalize()
		for s in Q.stubs:
			var t := 0.3 + r.f() * 0.4
			var SA := point_at(lpts, t)
			var d := dir_at(lpts, t)
			var side := rand_unit(r).add_scaled(d, 0.6)
			side.y = absf(side.y) * 0.8 + 0.2
			side.normalize()
			var L := 0.5 + r.f() * 0.9
			var EA := SA.clone().add_scaled(side, L)
			if constrain(EA, 0.03, 0.03, spec, false, -0.6) > 0.3:
				continue
			var rr := maxf(0.02, limb_r * 0.28)
			var spts2: Array = shaped.call(SA, EA, 0.08, 0.08, 3, rr, d)
			branches.append({"pts": spts2, "radii": taper(3, rr, rr * 0.35), "seg": Q.twigSeg, "depth": 3, "cap": true})

	# roots (buttresses sinking into the ground)
	var reach_r: float = spec.get("rootReach", trunk_r * 2.5)
	for k in Q.roots:
		var a: float = (float(k) / Q.roots) * PI * 2.0 + r.f() * 0.8
		var L := reach_r * (0.7 + r.f() * 0.3)
		var S := U.V.new(sx + cos(a) * trunk_r * 0.3, gy + trunk_r * (0.55 + r.f() * 0.35), sz + sin(a) * trunk_r * 0.3)
		var ex := sx + cos(a) * L
		var ez := sz + sin(a) * L
		var E := U.V.new(ex, H.call(ex, ez) - 0.12, ez)
		var mx := sx + cos(a) * L * 0.45
		var mz := sz + sin(a) * L * 0.45
		var rp := U.bezier(S, U.V.new(mx, H.call(mx, mz) + trunk_r * 0.25, mz), E, 5)
		branches.append({"pts": rp, "radii": taper(5, trunk_r * 0.46, trunk_r * 0.1, 0.7), "seg": maxi(5, Q.limbSeg - 1), "depth": 1})

	# ------------------------------------------------ 3. emit bark
	var young: bool = spec.get("bark", "old") == "young"
	var v_tile := 1.0 if young else 1.6
	var u_tile := 0.5 if young else 0.8
	for b in branches:
		U.tube(bark, b.pts, b.radii, b.seg, u_tile, v_tile, {"capEnd": b.depth >= 2 or b.get("cap", false)})

	# ------------------------------------------------ 4. blossom mass surface and cards
	# extra clusters fused under the shell (their own rng: the published pads and skeleton stay
	# unchanged) so the underside seen from below bulges into clumps
	var extra := []
	var r2: Rng = env.rng.call(str(spec.get("seed", spec.id)) + "-inner")
	var n_x := int(T.js_round(pads.size() * Q.get("innerX", 0.0)))
	ii = 0
	tries = 0
	while ii < n_x and tries < n_x * 10:
		tries += 1
		var src: CP.Pad = pads[floori(r2.f() * pads.size())]
		if src.layer or src.c.y < C.y - Ry * 0.35:
			continue
		var pr := pad_r * (0.6 + r2.f() * 0.3)
		var d := U.V.new().sub_vectors(src.c, C)
		d.y *= 0.6
		var p := src.c.clone().add_scaled(d.normalize(), -pr * (0.55 + r2.f() * 0.4))
		p.y -= pr * (0.15 + r2.f() * 0.35)
		var e := CP.Pad.new()
		e.c = p
		e.rx = pr * (0.9 + r2.f() * 0.3)
		e.rz = pr * (0.85 + r2.f() * 0.3)
		e.ry = pr * (0.5 + r2.f() * 0.15)
		e.layer = 1
		e.lobe = src.lobe
		e.jit = src.jit - 0.08
		e.peach = src.peach
		e.q = src.q
		if constrain(e.c, maxf(e.rx, e.rz) * 0.85, e.ry, spec) > pr:
			continue
		extra.append(e)
		ii += 1
	# mid / far trees: a core cluster fills the crown
	if Q.get("fill", false):
		var e := CP.Pad.new()
		e.c = U.V.new(C.x, C.y - Ry * 0.12, C.z)
		e.rx = Rx * 0.66
		e.ry = Ry * 0.5
		e.rz = Rz * 0.66
		e.layer = 1
		e.jit = -0.1
		e.q = U.Q.new()
		e.weight = 0.9
		extra.append(e)
	# plug the upper branch gaps (seen from above they read as craters); side and low gaps stay open
	for gd in gap_dirs:
		if gd.y < cos(1.22):
			continue
		var pr := pad_r * (1.0 + r2.f() * 0.2)
		var p := U.V.new(C.x + gd.x * Rx, C.y + gd.y * Ry, C.z + gd.z * Rz)
		p.add(canopy.normal_at(p, U.V.new()).mul(-pr * 0.5))
		var e := CP.Pad.new()
		e.c = p
		e.rx = pr * 1.1
		e.rz = pr * 1.05
		e.ry = pr * 0.55
		e.layer = 0
		e.q = U.Q.new().set_from_unit_vectors(UP, canopy.normal_at(p, U.V.new()).lerp(UP, 0.7).normalize())
		if constrain(e.c, pr * 0.9, e.ry, spec) > pr:
			continue
		extra.append(e)
	var surf := CP.blossom_surface(pads + extra, {"h": spec.get("meshH", Q.h), "smooth": Q.get("smooth"), "canopy": canopy, "noise": noise, "spec": spec,
		"amp": Q.amp, "freq": Q.freq, "groundY": gy})
	if surf != null:
		surf.emit(blob)
	var card_base: float = Q.cardS * spec.get("cardScale", 1.0)
	var density: float = spec.get("cardDensity", 1.0) * Q.cardK
	var near: bool = spec.get("lod", 0) == 0
	if surf != null:
		var nb = (func(hb: float) -> float: return 1.0 + 0.8 * (1.0 - U.clamp01((hb - 2.6) / 3.4))) if near else null
		CP.dress_surface(cards, surf, {"r": r, "CELL": CELL, "cardBase": card_base, "pal": P.normal, "peachCol": P.peach, "leafCol": P.leaf,
			"cov": Q.cov * density, "covIn": Q.covIn * density, "hangP": Q.hang, "nearBoost": nb})
	# sprigs: thin twigs poking out of pads, carrying a few sprays
	var tmpv := U.V.new()
	var nf := U.V.new()
	for pad in pads:
		if r.f() > Q.sprig:
			continue
		var n0 := canopy.normal_at(pad.c, U.V.new())
		var d: U.V = (pad.twig_dir if pad.twig_dir != null else n0).clone().lerp(n0, 0.6).add(rand_unit(r, tmpv).mul(0.3)).normalize()
		var L := maxf(pad.rx, pad.rz) * (0.95 + r.f() * 0.3)
		var S: U.V = pad.c.clone()
		var E: U.V = pad.c.clone().add_scaled(d, L)
		if constrain(E, 0.02, 0.02, spec) > 0.2:
			continue
		var pts := U.bezier(S, U.V.new().lerp_vectors(S, E, 0.5).add(U.V.new(0, L * 0.08, 0)), E, 3)
		U.tube(bark, pts, taper(3, 0.02, 0.008), 3, u_tile, v_tile, {"capEnd": true})
		var norm_fn := func(p: U.V) -> U.V: return canopy.field(p, pad, null, nf)
		var n := 3 + floori(r.f() * 3.0)
		for k in n:
			var t := 0.5 + (float(k) / n) * 0.5
			var cc := U.V.new().lerp_vectors(S, E, t).add(rand_unit(r, tmpv).mul(0.07))
			var pnv := U.V.new().copy(rand_unit(r, tmpv)).normalize()
			var cj: float = pad.jit + 0.06 + (r.f() - 0.5) * 0.2
			var size := card_base * (0.7 + r.f() * 0.3)
			var rot := r.f() * 6.28
			var cell: Array = CELL.spray if r.f() < 0.6 else CELL.loose
			CP.emit_card(cards, cc.x, cc.y, cc.z, pnv.x, pnv.y, pnv.z, size, rot, cell, func(p: U.V) -> Array: return canopy.tone(p, cj), norm_fn)

	# ------------------------------------------------ 5. info and colliders
	var info := summarize(pads, gy, spec)
	var p1 := point_at(tpts, U.clamp01((gy + 0.6 - B0.y) / maxf(0.01, Fk.y - B0.y)))
	var p2 := point_at(tpts, U.clamp01((gy + 1.7 - B0.y) / maxf(0.01, Fk.y - B0.y)))
	colliders.append({"x": p1.x, "z": p1.z, "r": trunk_r * 1.05 + 0.04, "y0": gy - 1.0, "y1": gy + 1.15})
	colliders.append({"x": p2.x, "z": p2.z, "r": trunk_r * 0.95 + 0.03, "y0": gy + 1.15, "y1": gy + minf(fork_h, 2.6)})
	return {"bark": bark, "blob": blob, "cards": cards, "info": info, "colliders": colliders, "groundY": gy}


## The weeping cherry.
static func make_weeping(spec: Dictionary, env: Dictionary) -> Dictionary:
	var r: Rng = env.rng.call(spec.get("seed", spec.id))
	var noise: U.ValueNoise = env.noise
	var Q: Dictionary = LODQ[spec.get("lod", 0)]
	var H: Callable = env.heightAt
	var bark := U.GeoBuilder.new()
	var blob := U.GeoBuilder.new()
	var cards := U.GeoBuilder.new()
	var sx: float = spec.x
	var sz: float = spec.z
	var trunk_r: float = spec.trunkR
	var fork_h: float = spec.forkH
	var height: float = spec.height
	var gy: float = H.call(sx, sz)
	var g_min := gy
	for k in 10:
		var a := (k / 10.0) * PI * 2.0
		g_min = minf(g_min, H.call(sx + cos(a) * trunk_r * 2.4, sz + sin(a) * trunk_r * 2.4))
	var lean: Array = spec.get("lean", [0.0, 0.0])
	var Fk := U.V.new(sx + lean[0], gy + fork_h, sz + lean[1])
	var Rx: float = spec.spread
	var Ry := height * 0.5
	var C := U.V.new(Fk.x, gy + height * 0.55, Fk.z)
	var P := pal()
	var canopy := Canopy.new(C, Rx, Ry, Rx, P.weeping, noise, true, env.sun)
	var UP := U.V.new(0, 1, 0)
	var branches := []
	var B0 := U.V.new(sx, g_min - 0.3, sz)
	var tp := U.bezier(B0, U.V.new(sx + lean[0] * 0.1, gy + fork_h * 0.5, sz + lean[1] * 0.1), Fk, 8)
	var tph := r.f() * 100.0
	var trad := []
	for i in tp.size():
		var p: U.V = tp[i]
		var h := p.y - gy
		var t := float(i) / (tp.size() - 1)
		var q := 1.0 - U.clamp01(h / 0.8)
		trad.append(trunk_r * (1.0 + 0.5 * (q * q) if h < 0.8 else 1.0) * (1.0 - 0.15 * t) * (1.0 + 0.06 * noise.n3(p.y * 1.5 + tph, 1.0, 0.3)))
	for i in range(1, tp.size() - 1):
		var w := sin(float(i) / (tp.size() - 1) * PI) * trunk_r * 0.45
		var p: U.V = tp[i]
		p.x += noise.n3(tph + p.y * 0.5, 2.0, 0.4) * w
		p.z += noise.n3(tph + p.y * 0.5, 5.0, 7.1) * w
	branches.append({"pts": tp, "radii": trad, "seg": Q.trunkSeg, "depth": 0})
	for k in Q.roots:
		var a: float = (float(k) / Q.roots) * PI * 2.0 + r.f() * 0.8
		var L: float = spec.get("rootReach", trunk_r * 2.4) * (0.7 + r.f() * 0.3)
		var S := U.V.new(sx, gy + trunk_r * 0.7, sz)
		var ex := sx + cos(a) * L
		var ez := sz + sin(a) * L
		var mx := sx + cos(a) * L * 0.45
		var mz := sz + sin(a) * L * 0.45
		branches.append({"pts": U.bezier(S, U.V.new(mx, H.call(mx, mz) + trunk_r * 0.25, mz), U.V.new(ex, H.call(ex, ez) - 0.12, ez), 5),
			"radii": taper(5, trunk_r * 0.45, trunk_r * 0.1, 0.7), "seg": 6, "depth": 1})
	var pads := []
	var strands := []
	var n_limbs: int = spec.get("limbs", 5)
	var arcs := []
	for k in n_limbs:
		var a := (float(k) / n_limbs) * PI * 2.0 + r.f() * 0.6
		var out := U.V.new(cos(a), 0, sin(a))
		var rise := (height - fork_h) * (0.62 + r.f() * 0.28)
		var reach := Rx * (0.38 + r.f() * 0.2)
		var S := Fk.clone().add_scaled(out, trunk_r * 0.3)
		var E := U.V.new(Fk.x + out.x * reach, Fk.y + rise * 0.8, Fk.z + out.z * reach)
		constrain(E, 0.4, 0.3, spec, true)
		var Cc := U.V.new(Fk.x + out.x * reach * 0.2, Fk.y + rise * 1.12, Fk.z + out.z * reach * 0.2)
		var lr := trunk_r * 0.72 / sqrt(n_limbs) * 1.3
		var lp := U.bezier(S, Cc, E, 8)
		branches.append({"pts": lp, "radii": taper(8, lr, lr * 0.55), "seg": Q.limbSeg, "depth": 1})
		var n_sec := 2 + floori(r.f() * 2.0)
		for s in n_sec:
			var t := 0.45 + r.f() * 0.55
			var f := t * (lp.size() - 1)
			var i := mini(lp.size() - 2, floori(f))
			var SA := U.V.new().lerp_vectors(lp[i], lp[i + 1], f - i)
			var aa := a + (r.f() - 0.5) * 1.3
			var o2 := U.V.new(cos(aa), 0, sin(aa))
			var L := Rx * (0.35 + r.f() * 0.3)
			var EA := SA.clone().add_scaled(o2, L)
			EA.y -= L * (0.2 + r.f() * 0.2)
			constrain(EA, 0.5, 0.3, spec, true)
			var CA := SA.clone().add_scaled(o2, L * 0.5)
			CA.y += L * 0.35
			var sp := U.bezier(SA, CA, EA, 6)
			var sr := lr * 0.5
			branches.append({"pts": sp, "radii": taper(6, sr, sr * 0.4), "seg": Q.subSeg, "depth": 2, "cap": true})
			arcs.append(sp)
		arcs.append(lp)
		var pd := CP.Pad.new()
		pd.c = E.clone().add(U.V.new(0, 0.25, 0))
		pd.rx = 0.95 + r.f() * 0.3
		pd.rz = 0.9 + r.f() * 0.3
		pd.ry = 0.45 + r.f() * 0.15
		pd.layer = 0
		pads.append(pd)
	for k in 3:
		var a := r.f() * PI * 2.0
		var d := r.f() * Rx * 0.25
		var pd := CP.Pad.new()
		pd.c = U.V.new(Fk.x + cos(a) * d, gy + height - 0.6 - r.f() * 0.4, Fk.z + sin(a) * d)
		pd.rx = 0.95 + r.f() * 0.3
		pd.rz = 0.95
		pd.ry = 0.5
		pd.layer = 0
		pads.append(pd)
	var n_strands := int(T.js_round(spec.get("strands", 10) * n_limbs * (0.6 if spec.get("lod", 0) else 1.0)))
	for s in n_strands:
		var arc: Array = arcs[floori(r.f() * arcs.size())]
		var t := 0.25 + r.f() * 0.75
		var f := t * (arc.size() - 1)
		var i := mini(arc.size() - 2, floori(f))
		var S := U.V.new().lerp_vectors(arc[i], arc[i + 1], f - i)
		var out := U.V.new(S.x - Fk.x, 0, S.z - Fk.z)
		var dist := out.length()
		if dist == 0.0:
			dist = 1.0
		out.div(dist)
		out.x += (r.f() - 0.5) * 0.5
		out.z += (r.f() - 0.5) * 0.5
		out.normalize()
		var floor_y: float = spec.floorAt.call(S.x + out.x * 0.8, S.z + out.z * 0.8) if spec.get("floorAt") != null else gy + 1.8
		var hang := maxf(0.6, minf(S.y - floor_y, spec.get("hang", 3.2) * (0.6 + r.f() * 0.5)))
		var E := S.clone().add_scaled(out, 0.35 + r.f() * 0.5)
		E.y = S.y - hang
		constrain(E, 0.25, 0.1, spec, true)
		var Cc := S.clone().add_scaled(out, 0.5 + r.f() * 0.3)
		Cc.y += 0.25 + r.f() * 0.2
		var pts := U.bezier(S, Cc, E, 6)
		strands.append(pts)
		branches.append({"pts": pts, "radii": taper(6, 0.016, 0.006), "seg": 3, "depth": 3, "cap": true})
	for pad in pads:
		constrain(pad.c, pad.rx, pad.ry, spec)
		pad.seed = r.f() * 50.0
		pad.jit = (r.f() - 0.5) * 0.2
		pad.peach = 0.0
		r.f()
		r.f()
		pad.q = U.Q.new().set_from_axis_angle(UP, r.f() * 6.28)
	var strand_pads := []
	for st in strands:
		# a slim core only high on the strand (keeps an outline where it leaves the crown)
		var n := 1 if r.f() < 0.55 else 0
		for k in n:
			var t := 0.18 + r.f() * 0.12
			var f: float = t * (st.size() - 1)
			var i := mini(st.size() - 2, floori(f))
			var c := U.V.new().lerp_vectors(st[i], st[i + 1], f - i)
			var sp := CP.Pad.new()
			sp.c = c
			sp.rx = 0.1 + r.f() * 0.03
			sp.rz = 0.1 + r.f() * 0.03
			sp.ry = 0.24 + r.f() * 0.08
			sp.seed = r.f() * 50.0
			sp.jit = (r.f() - 0.5) * 0.2 - 0.05
			sp.peach = 0.0
			sp.q = U.Q.new().set_from_axis_angle(UP, r.f() * 6.28)
			sp.layer = 1
			strand_pads.append(sp)
	var young: bool = spec.get("bark", "old") == "young"
	var tile := [0.5, 1.0] if young else [0.8, 1.6]
	for b in branches:
		U.tube(bark, b.pts, b.radii, b.seg, tile[0], tile[1], {"capEnd": b.get("cap", false)})
	# crown clusters and slim drips where strands leave the crown -> one blossom-mass surface
	for p in strand_pads:
		p.k_scale = 1.35
		p.y_scale = 1.0
	var surf := CP.blossom_surface(pads + strand_pads, {"h": spec.get("meshH", Q.h * 0.75), "canopy": canopy, "noise": noise, "spec": spec,
		"amp": Q.amp * 0.8, "freq": Q.freq * 1.1, "groundY": gy, "weights": {"t": 0.45, "l": 0.15, "c": 0.4, "up": 0.1}})
	if surf != null:
		surf.emit(blob)
	var card_base: float = Q.cardS * 0.85
	if surf != null:
		CP.dress_surface(cards, surf, {"r": r, "CELL": CELL, "cardBase": card_base, "pal": P.weeping, "peachCol": P.peach, "leafCol": P.leaf,
			"cov": Q.cov * 1.1, "covIn": Q.covIn, "hangP": 0.45})
	var nrm := U.V.new()
	var norm_fn := func(p: U.V) -> U.V: return canopy.normal_at(p, nrm)
	var tmpv := U.V.new()
	for st in strands:
		var len := 0.0
		for i in range(1, st.size()):
			len += st[i].distance_to(st[i - 1])
		var n := maxi(3, int(T.js_round((len / 0.15) * Q.cardK)))
		for k in n:
			var t := 0.12 + (float(k) / n) * 0.88
			var f: float = t * (st.size() - 1)
			var i := mini(st.size() - 2, floori(f))
			var cc := U.V.new().lerp_vectors(st[i], st[i + 1], f - i).add(rand_unit(r, tmpv).mul(0.05 + 0.07 * t))
			var a := r.f() * 6.28
			var pn := U.V.new(cos(a), (r.f() - 0.5) * 0.5, sin(a)).normalize()
			var cj := 0.02 + (1.0 - t) * 0.1 + (r.f() - 0.5) * 0.22
			var roll := r.f()
			var size := card_base * (0.75 + r.f() * 0.45)
			var rot := PI / 2.0 + (r.f() - 0.5) * 0.8
			var cell: Array = CELL.spray if roll < 0.5 else (CELL.loose if roll < 0.85 else CELL.dense)
			CP.emit_card(cards, cc.x, cc.y, cc.z, pn.x, pn.y, pn.z, size, rot, cell, func(p: U.V) -> Array: return canopy.tone(p, cj), norm_fn, 0.75)
	var info := summarize(pads + strand_pads, gy, spec)
	var colliders := [{"x": sx + lean[0] * 0.1, "z": sz + lean[1] * 0.1, "r": trunk_r * 1.05 + 0.04, "y0": gy - 1.0, "y1": gy + minf(2.4, fork_h)}]
	return {"bark": bark, "blob": blob, "cards": cards, "info": info, "colliders": colliders, "groundY": gy}
