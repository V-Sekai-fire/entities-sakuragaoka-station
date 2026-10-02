# houses/props.js: domestic small objects and garden plants. Every function takes a Frame (local +Z
# outward) and appends to the module's GB; the RNG draws match the original one for one.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const GBM = preload("res://addons/sakuragaoka_station/world/houses/gb.gd")
const Fol = preload("res://addons/sakuragaoka_station/world/lib/foliage.gd")

const PLANT := {
	"green": ["#6f9a5a", "#5f8c5c", "#7aa564", "#86ad6a", "#668f55"],
	"dark": ["#4f7a52", "#557f57", "#4a7050"],
	"pine": ["#4c7153", "#557a58", "#45684d"],
	"young": ["#a9c77c", "#b8d18a", "#9dc073"],
	"azalea": ["#e27aa6", "#ec94b8", "#d9679a", "#f2b0c8"],
	"hydrangea": ["#a7b8e3", "#b9b1df", "#9fc0e0", "#c6b7e2"],
	"flowers": ["#f2c230", "#e8697a", "#f4f0e6", "#b48ad6", "#f29a5c", "#ef9fbe"],
	"tulip": ["#e8505b", "#f2c230", "#f49ac1", "#f4f0e6"],
}
const TINT := ["#ffffff", "#f3f9ec", "#fbfdf0", "#eef5ea", "#fff9f0", "#f4f4f4"]
const BUSH_KIND := {"green": ["boxwood", "azalea", "privet"], "dark": ["camellia", "dark"], "young": ["young"], "pine": ["pine"]}
const TREE_KIND := {"maple": "maple", "olive": "olive", "osmanthus": "dark", "camellia": "camellia", "round": "boxwood"}
const NEUTRAL := {"top": "#ffffff", "mid": "#e4e4e4", "base": "#b4b4b4"}

static var _fol := {}
static var _hedge_n := 0


static func _rnd(i: float, variant: int) -> float:
	var x := sin((i + 1.0) * 12.9898 + variant * 78.233) * 43758.5453
	return x - floor(x)


## A jittered icosahedron blob (cached per variant).
static func blob_raw(variant: int, detail: int = 1) -> Dictionary:
	return GBM.raw_of("blob|%d|%d" % [variant, detail], func():
		var g := Geo.icosahedron(0.5, detail)
		var p: T.Attr = g.get_attribute("position")
		for i in p.count():
			var x := p.get_x(i)
			var y := p.get_y(i)
			var z := p.get_z(i)
			var h := T.js_round(x * 97) * 31 + T.js_round(y * 97) * 17 + T.js_round(z * 97) * 7 + variant * 101
			var k := 1.0 + (_rnd(h, variant) - 0.5) * 0.28
			p.set_xyz(i, x * k, y * k * 0.92, z * k)
		g.compute_vertex_normals()
		var n: T.Attr = g.get_attribute("normal")
		var groups := {}
		for i in p.count():
			var key := "%.3f,%.3f,%.3f" % [p.get_x(i), p.get_y(i), p.get_z(i)]
			if not groups.has(key):
				groups[key] = [0.0, 0.0, 0.0, []]
			var a: Array = groups[key]
			a[0] += n.get_x(i)
			a[1] += n.get_y(i)
			a[2] += n.get_z(i)
			a[3].append(i)
		for a in groups.values():
			var l := Vector3(a[0], a[1], a[2]).length()
			if l == 0.0:
				l = 1.0
			for i in a[3]:
				n.set_xyz(i, a[0] / l, a[1] / l, a[2] / l)
		return g)


## A tiny octahedron dot with radial normals.
static func dot_raw() -> Dictionary:
	return GBM.raw_of("dot2", func():
		var g := Geo.polyhedron([1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1],
			[0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2, 1, 2, 5, 1, 5, 3, 1, 3, 4, 1, 4, 2], 0.5, 0)
		var p: T.Attr = g.get_attribute("position")
		var n: T.Attr = g.get_attribute("normal")
		for i in p.count():
			var v := Vector3(p.get_x(i), p.get_y(i), p.get_z(i))
			var l := v.length()
			if l == 0.0:
				l = 1.0
			n.set_xyz(i, v.x / l, v.y / l, v.z / l)
		return g)


static func _fol_geo(key: String, make: Callable) -> T.Geometry:
	if not _fol.has(key):
		_fol[key] = make.call()
	return _fol[key]


static func _fol_raw(key: String, make: Callable) -> Dictionary:
	return GBM.raw_of("fol|" + key, func(): return _fol_geo(key, make).clone())


static func _shrub_opts(kind: String, rb: float, flat: float, variant: int, detail: int) -> Dictionary:
	return {"rx": rb * 1.28, "ry": rb * 1.02 * flat, "rz": rb * 1.16, "seed": 1 + variant * 17, "colors": Fol.SHRUB_COLORS.get(kind, Fol.SHRUB_COLORS.boxwood),
		"detail": detail, "lumps": 0.2, "puff": maxf(0.14, rb * 0.62)}


static func _shrub_key(kind: String, rb: float, flat: float, variant: int, spacing: int) -> String:
	return "sh|%s|%s|%s|%d|%d" % [kind, rb, flat, variant, spacing]


static func shrub_raw(kind: String, rb: float, flat: float, variant: int, spacing: int) -> Dictionary:
	var o := _shrub_opts(kind, rb, flat, variant, spacing)
	return _fol_raw(_shrub_key(kind, rb, flat, variant, spacing), func(): return Fol.shrub_geometry(o))


static func shrub_blossoms(kind: String, rb: float, flat: float, variant: int, spacing: int, fo: Dictionary) -> Dictionary:
	var k := _shrub_key(kind, rb, flat, variant, spacing)
	var o := _shrub_opts(kind, rb, flat, variant, spacing)
	return _fol_raw(k + "|fl|" + JSON.stringify(fo), func(): return Fol.flower_geometry(_fol_geo(k, func(): return Fol.shrub_geometry(o)), fo))


## A smooth leaf clump (radius 0.5, centred), neutral colours tinted by the emit colour.
static func leaf_raw(variant: int, detail: int = 1) -> Dictionary:
	return _fol_raw("leaf|%d|%d" % [variant, detail], func():
		var g: T.Geometry = Fol.shrub_geometry({"rx": 0.5, "ry": 0.46, "rz": 0.5, "seed": 31 + variant * 7, "detail": detail, "flatBottom": false, "cutBottom": false,
			"lumps": 0.3, "freq": 3.2, "puff": 0.2 if detail >= 3 else 0.0, "colors": NEUTRAL, "normalBlend": 0.35}).clone()
		g.translate(0, -0.46 * 0.55, 0)
		return g)


## A cloud pad or canopy lobe (radius 0.5, centred); flat pads for pines.
static func lobe_raw(kind: String, variant: int, flat_pad: bool, detail: int) -> Dictionary:
	return _fol_raw("lobe|%s|%d|%d|%d" % [kind, variant, 1 if flat_pad else 0, detail], func():
		var ry := 0.2 if flat_pad else 0.5
		var g: T.Geometry = Fol.shrub_geometry({"rx": 0.52, "ry": ry, "rz": 0.5, "seed": 57 + variant * 11, "detail": detail, "flatBottom": flat_pad, "cutBottom": false,
			"lumps": 0.12 if flat_pad else 0.2, "freq": 3, "puff": 0.2 if flat_pad else 0.24, "puffAmp": 0.38 if flat_pad else 0.42,
			"colors": Fol.SHRUB_COLORS.get(kind, Fol.SHRUB_COLORS.boxwood)}).clone()
		g.translate(0, -ry * 0.55, 0)
		return g)


## The RNG draws the old multi-blob bush made, consumed so every later lot feature stays in place.
static func burn_bush(r, rad: float, o: Dictionary, hi: bool) -> Array:
	var out := []
	var n: int = o.n if o.get("n") else (3 if rad > 0.5 and hi else 2)
	for i in n:
		out.append(r.f())
		if i:
			out.append(r.f())
		out.append(r.f())
		out.append(r.f())
		out.append(r.f())
	if o.get("flowers"):
		var fn0: float = o.fn if o.get("fn") else T.js_round(5 + rad * 12)
		var k := int(T.js_round(fn0 * (1.0 if hi else 0.5)))
		for i in k:
			out.append(r.f())
			out.append(r.f())
			if not o.get("fsize"):
				out.append(r.f())
			out.append(r.f())
	return out


var H
var M: Dictionary
var A: Dictionary


func _init(h) -> void:
	H = h
	M = h.M
	A = h.A


func _hi() -> bool:
	return (H.lod if H.lod != null else 2) >= 2


func at(name: String) -> Dictionary:
	return {"uv": {"rect": A.rects[name], "white": A.white}}


static func pick(r, a: Array):
	return a[floori(r.f() * a.size())]


## A rounded shrub: one smooth puff-scalloped mass and optional blossoms.
func bush(F, x: float, y: float, z: float, rad: float, r, o: Dictionary = {}) -> void:
	var hi := _hi()
	var R := burn_bush(r, rad, o, hi)
	var kinds: Array = BUSH_KIND.get(o.get("pal", "green") if o.get("pal") else "green", BUSH_KIND.green)
	var kind: String = kinds[int(floor(R[0] * kinds.size())) % kinds.size()]
	var variant := int(floor(R[1] * 4)) % 4
	var rb := maxf(0.1, T.js_round(rad * 20) / 20.0)
	var flat := float("%.2f" % (o.flat / 0.85)) if o.get("flat") else 1.0
	var sp: int
	if o.get("detail") != null:
		sp = o.detail
	elif hi:
		sp = 2 if rb <= 0.2 else (3 if rb <= 0.5 else 4)
	else:
		sp = 1 if rb <= 0.35 else 2
	var k := rad / rb
	var sx: float = 0.9 + R[2] * 0.2
	var rot: float = R[3] * 6.283
	var m := {"sx": k * sx, "sy": k, "sz": k * (2 - sx), "ry": rot}
	F.raw(H.M.foliage, TINT[int(floor(R[4] * TINT.size())) % TINT.size()], shrub_raw(kind, rb, flat, variant, sp), x, y - 0.015, z, m)
	if not o.get("flowers"):
		return
	var fn0: float = o.fn if o.get("fn") else T.js_round(5 + rad * 12)
	var nf := int(T.js_round(fn0 * (1.35 if hi else 0.8)))
	if o.flowers == "hydrangea":
		var fs: float = o.fsize if o.get("fsize") else 0.16
		for i in maxi(2, int(T.js_round(nf / 2.2))):
			var a: float = R[(5 + i * 2) % R.size()] * 6.283 + i * 2.1
			var el: float = 0.2 + R[(6 + i * 2) % R.size()] * 0.75
			var rr := rad * 1.18
			var px := cos(a) * cos(el) * rr
			var pz := sin(a) * cos(el) * rr
			F.raw(M.plain, PLANT.hydrangea[i % PLANT.hydrangea.size()], leaf_raw(7 + (i % 3), 2), x + px, y + rad * 0.95 + sin(el) * rad * 0.7, z + pz, {"sx": fs, "sy": fs * 0.82, "sz": fs, "ry": a})
		return
	var fo := {"count": nf, "size": 0.03, "colors": PLANT.get(o.flowers, PLANT.azalea), "seed": variant * 3 + 5, "petals": 5 if hi and o.get("detail") == null else 0, "minY": 0.35}
	var mm := m.duplicate()
	mm["noOutline"] = true
	mm["shadow"] = false
	F.raw(M.plain, null, shrub_blossoms(kind, rb, flat, variant, sp, fo), x, y - 0.015, z, mm)


## A clipped hedge along local x from x0 to x1 at z: one continuous mass following the ground.
func hedge(F, x0: float, x1: float, z: float, h: float, d: float, r, pal: String = "green", gy = null) -> void:
	var ln := x1 - x0
	var n := maxi(1, int(T.js_round(ln / 1.1)))
	var R := []
	for i in n:
		R.append(r.f())
		R.append(r.f())
	var hi := _hi()
	var cx := (x0 + x1) / 2.0
	var g0: float = gy.call(cx, z) if gy != null else 0.0
	var kind := "camellia" if pal == "dark" else ("privet" if R[0] < 0.55 else "boxwood")
	var ground = null
	if gy != null:
		ground = func(lx): return gy.call(cx + lx, z) - g0
	var geo: T.Geometry = Fol.hedge_geometry({"length": ln + 0.08, "h": h * 1.05, "d": d * 1.1, "seed": 1 + int(floor(R[1] * 997)), "colors": Fol.SHRUB_COLORS[kind],
		"spacing": 0.165 if hi else 0.28, "ground": ground})
	_hedge_n += 1
	var raw := GBM.raw_of("hedge|%d" % _hedge_n, func(): return geo)
	F.raw(M.foliage, TINT[int(floor(R[R.size() - 1] * TINT.size())) % TINT.size()], raw, cx, g0 - 0.02, z)


## A dwarf, cloud-pruned pine: trunk and flat-bottomed pads.
func pine(F, x: float, y: float, z: float, s: float, r) -> void:
	var lean := (r.f() - 0.5) * 0.5
	var hi := _hi()
	F.cyl(M.plain, "#6b5244", 0.07 * s, 0.9 * s, x, y + 0.45 * s, z, {"rz": lean, "seg": 6, "rTop": 0.05 * s})
	var tx := x - sin(lean) * 0.9 * s
	var pads := [[0, 1.0, 0, 0.9], [0.35, 0.72, 0.1, 0.62], [-0.38, 0.6, -0.08, 0.55], [0.1, 1.28, -0.05, 0.55]]
	var pi := 0
	for pd in pads:
		var dx: float = pd[0]
		var dy: float = pd[1]
		var dz: float = pd[2]
		var ps: float = pd[3]
		pick(r, PLANT.pine)
		var v := int(floor(r.f() * 6))
		F.raw(M.foliage, "#f4fbee" if pi == 3 else "#ffffff", lobe_raw("pine", v % 3, true, 3 if hi else 2), tx + dx * s, y + dy * s, z + dz * s,
			{"sx": ps * s * 1.08, "sy": ps * s * 1.1, "sz": ps * s * 0.92, "ry": r.f() * 6})
		F.cyl(M.plain, "#6b5244", 0.025 * s, Vector2(dx, dy - 0.8).length() * s, (tx + tx + dx * s) / 2.0, y + (0.85 + dy) / 2.0 * s, z + dz * s / 2.0,
			{"rz": -atan2(dx, dy - 0.8) * 0.8, "seg": 5})
		pi += 1


## Nandina: slender stems, reddish leaf tufts, red berries.
func nandina(F, x: float, y: float, z: float, s: float, r) -> void:
	for i in 5:
		var a := r.f() * 6.28
		var d := r.f() * 0.12 * s
		var hh := (0.7 + r.f() * 0.6) * s
		var px := x + cos(a) * d
		var pz := z + sin(a) * d
		F.cyl(M.plain, "#7a6a4a", 0.012 * s, hh, px, y + hh / 2.0, pz, {"seg": 4})
		var lc := "#b8584a" if r.f() < 0.35 else ("#8a9c5a" if r.f() < 0.5 else "#6f9458")
		F.raw(M.foliage, lc, leaf_raw(i % 4, 1) if _hi() else blob_raw(i, 0), px, y + hh, pz, {"sx": 0.34 * s, "sy": 0.2 * s, "sz": 0.3 * s, "ry": r.f() * 6})
		if i < 2:
			for k in 4:
				F.raw(M.plain, "#cf3f3a", dot_raw(), px + (r.f() - 0.5) * 0.1, y + hh - 0.08 - r.f() * 0.06, pz + (r.f() - 0.5) * 0.1, {"sx": 0.035, "sy": 0.035, "sz": 0.035})


## A garden tree: kind is maple, olive, osmanthus, camellia or round.
func tree(F, x: float, y: float, z: float, s: float, r, kind: String = "round") -> void:
	var hi := _hi()
	var tc := "#8f887a" if kind == "olive" else ("#7a6252" if kind == "maple" else "#6e5646")
	var SP := {
		"maple": [1.6, 1.0, 0.74, 6, ["#9fbf72", "#aac87c", "#94b56a", "#b4cd86"]],
		"olive": [1.2, 0.7, 0.85, 5, ["#9fae8a", "#aab996", "#8fa27f"]],
		"osmanthus": [0.7, 0.62, 1.35, 5, ["#4f7a52", "#557f57", "#5f8c5c"]],
		"camellia": [0.55, 0.6, 1.15, 5, PLANT.dark],
		"round": [1.25, 0.8, 0.8, 5, PLANT.green],
	}
	var sp: Array = SP.get(kind, [1.25, 0.8, 0.8, 5, PLANT.green])
	var th: float = sp[0]
	var cr: float = sp[1]
	var sq: float = sp[2]
	var nb: int = sp[3]
	var pal: Array = sp[4]
	var h := th * s
	var R := cr * s
	var lean := (r.f() - 0.5) * 0.16
	var lx := sin(lean) * h
	var tx := x - lx
	F.cyl(M.plain, tc, 0.085 * s, h + 0.2 * s, x - lx / 2.0, y + h / 2.0, z, {"seg": 6, "rTop": 0.055 * s, "rz": lean})
	if hi and kind != "osmanthus" and kind != "camellia":
		for sd in [-1, 1]:
			var a := r.f() * 6.28
			F.beam(M.plain, tc, [tx, y + h * 0.9, z], [tx + cos(a) * R * 0.55, y + h + R * 0.25 * sd + 0.2 * s, z + sin(a) * R * 0.55], 0.05 * s, 0.05 * s)
	var n := nb - (0 if hi else 2)
	var cy := y + h + R * sq * 0.55
	for i in n:
		var top := i == 0
		var a := i * 2.39996 + r.f() * 0.6
		var d := 0.0 if top else R * (0.36 + r.f() * 0.18)
		var tier: float = ((-0.2 if i % 2 else 0.08) * R) if kind == "maple" else (r.f() - 0.55) * R * sq * 0.6
		var bs := (1.25 if top else 0.8 + r.f() * 0.3) * R
		pick(r, pal)
		var v := int(floor(r.f() * 6))
		var det := (3 if top else 2) if hi else (2 if top else 1)
		F.raw(M.foliage, "#ffffff" if top else TINT[(i + v) % TINT.size()], lobe_raw(TREE_KIND.get(kind, "boxwood"), v % 4, false, det),
			tx + cos(a) * d, cy + (R * sq * 0.18 if top else tier), z + sin(a) * d, {"sx": bs, "sy": bs * sq, "sz": bs, "ry": r.f() * 6})
	if kind == "camellia":
		for k in 12:
			var a := r.f() * 6.28
			var e := r.f()
			F.raw(M.plain, "#d9485a" if r.f() < 0.5 else "#ef8fa6", leaf_raw(k % 3, 1), tx + cos(a) * R * 1.02, cy + (e - 0.5) * R * sq * 1.4, z + sin(a) * R * 1.02, {"sx": 0.1, "sy": 0.08, "sz": 0.1})


## A flower pot or planter: kind terra, glaze or plastic.
func pot(F, x: float, y: float, z: float, r, scale: float = 1.0, kind = null) -> void:
	var k: String = kind if kind else pick(r, ["terra", "terra", "glaze", "plastic", "glaze"])
	var c: String
	if k == "terra":
		c = pick(r, ["#c07a55", "#b86f4e", "#c98a62"])
	elif k == "glaze":
		c = pick(r, ["#4f6f94", "#5f7c6a", "#3e5a78", "#7b5f86", "#e5dfcf"])
	else:
		c = pick(r, ["#6b6e73", "#e2ded2", "#5b7a5b"])
	var pr := (0.13 + r.f() * 0.08) * scale
	var ph := pr * (1.1 + r.f() * 0.4)
	var hi := _hi()
	F.cyl(M.plain, c, pr * 0.82, ph, x, y + ph / 2.0, z, {"rTop": pr, "seg": 7})
	if hi:
		F.cyl(M.plain, c, pr * 1.08, 0.04, x, y + ph - 0.02, z, {"seg": 7, "open": true})
	F.cyl(M.soil, "#8a7058", pr * 0.95, 0.02, x, y + ph - 0.01, z, {"seg": 6})
	var t := r.f()
	var det := 2 if hi and pr > 0.17 else 1
	if t < 0.35:
		bush(F, x, y + ph * 0.8, z, pr * 1.2, r, {"pal": "green", "n": 2, "flowers": "flowers" if r.f() < 0.6 else null, "fn": 4, "detail": det})
	elif t < 0.55:
		for i in 4:
			var a := i * 1.6 + r.f()
			var d := pr * 0.5
			var hh := 0.22 * scale + r.f() * 0.08
			F.cyl(M.plain, "#6f9a5a", 0.008, hh, x + cos(a) * d, y + ph + hh / 2.0, z + sin(a) * d, {"seg": 3})
			F.raw(M.plain, pick(r, PLANT.tulip), dot_raw(), x + cos(a) * d, y + ph + hh, z + sin(a) * d, {"sx": 0.05 * scale, "sy": 0.07 * scale, "sz": 0.05 * scale})
		F.raw(M.plain, "#7aa564", leaf_raw(3, 1), x, y + ph + 0.04, z, {"sx": pr * 1.6, "sy": 0.08, "sz": pr * 1.6})
	elif t < 0.7:
		bush(F, x, y + ph * 0.85, z, pr * 1.0, r, {"pal": "green", "n": 1, "flat": 1.4, "detail": det})
	elif t < 0.85:
		nandina(F, x, y + ph * 0.9, z, 0.55 * scale, r)
	else:
		bush(F, x, y + ph * 0.8, z, pr * 1.3, r, {"pal": "green", "n": 2, "flowers": "azalea", "fn": 4, "detail": det})


func sill_pot(F, x: float, y: float, z: float) -> void:
	F.boxB(M.plain, "#c07a55", 0.18, 0.1, 0.1, x, y, z)
	F.raw(M.plain, "#e8697a", leaf_raw(8, 1), x - 0.04, y + 0.15, z, {"sx": 0.1, "sy": 0.08, "sz": 0.1})
	F.raw(M.plain, "#6f9a5a", leaf_raw(4, 1), x + 0.03, y + 0.13, z, {"sx": 0.14, "sy": 0.08, "sz": 0.1})


func planter(F, x: float, y: float, z: float, ln: float, r) -> void:
	F.boxB(M.plain, pick(r, ["#8a6446", "#d9d2c2", "#6b6e73", "#b48a62"]), ln, 0.26, 0.28, x, y, z)
	F.boxB(M.soil, "#8a7058", ln - 0.06, 0.02, 0.22, x, y + 0.24, z, {"uv": {"world": 0.5}})
	var n := int(T.js_round(ln / 0.14))
	for i in n:
		var px := x - ln / 2.0 + 0.08 + i * (ln - 0.16) / maxf(1, n - 1)
		F.raw(M.plain, "#6f9a5a", leaf_raw(i % 4, 1) if _hi() else blob_raw(i % 6, 0), px, y + 0.3, z + (r.f() - 0.5) * 0.1, {"sx": 0.15, "sy": 0.1, "sz": 0.15})
		F.raw(M.plain, pick(r, PLANT.flowers), dot_raw(), px + 0.02, y + 0.35, z + (r.f() - 0.5) * 0.1, {"sx": 0.07, "sy": 0.05, "sz": 0.07})


func bonsai_shelf(F, x: float, y: float, z: float, r) -> void:
	var wc := "#8a6446"
	for s in [-1, 1]:
		F.boxB(M.plain, wc, 0.06, 0.8, 0.4, x + s * 0.55, y, z)
	for hh in [0.4, 0.78]:
		F.boxB(M.wood, "#b48a62", 1.2, 0.04, 0.42, x, y + hh, z, {"uv": {"world": 1.2}})
	for i in 4:
		var px := x - 0.42 + i * 0.28
		var py := y + (0.82 if i % 2 else 0.44)
		F.boxB(M.plain, pick(r, ["#5a4c44", "#4f6f94", "#7a5a4a"]), 0.2, 0.06, 0.14, px, py, z)
		F.cyl(M.plain, "#6b5244", 0.015, 0.14, px, py + 0.12, z, {"rz": (r.f() - 0.5), "seg": 4})
		F.raw(M.plain, pick(r, PLANT.pine), leaf_raw(i % 4, 1), px + (r.f() - 0.5) * 0.06, py + 0.2, z, {"sx": 0.2, "sy": 0.08, "sz": 0.14})


func lantern(F, x: float, y: float, z: float) -> void:
	var c := "#a9a79f"
	F.boxB(M.concrete, c, 0.4, 0.12, 0.4, x, y, z, {"uv": {"world": 2}})
	F.cyl(M.concrete, c, 0.08, 0.5, x, y + 0.37, z, {"seg": 6})
	F.boxB(M.concrete, c, 0.34, 0.08, 0.34, x, y + 0.62, z, {"uv": {"world": 2}})
	F.boxB(M.concrete, "#9d9b94", 0.26, 0.24, 0.26, x, y + 0.7, z, {"uv": {"world": 2}})
	F.box(M.plain, "#3e3a44", 0.12, 0.1, 0.27, x, y + 0.82, z)
	F.cyl(M.concrete, c, 0.04, 0.18, x, y + 0.99, z, {"rTop": 0.28, "seg": 6})
	F.raw(M.concrete, c, blob_raw(1, 0), x, y + 1.12, z, {"sx": 0.12, "sy": 0.12, "sz": 0.12})


func stepping_stones(F, x0: float, z0: float, x1: float, z1: float, gy: Callable, r) -> void:
	var ln := Vector2(x1 - x0, z1 - z0).length()
	var n := maxi(2, int(T.js_round(ln / 0.55)))
	for i in n:
		var t := (i + 0.5) / n
		var x := x0 + (x1 - x0) * t + (r.f() - 0.5) * 0.12
		var z := z0 + (z1 - z0) * t + (r.f() - 0.5) * 0.08
		var c = pick(r, ["#a8a59c", "#9b988f", "#b3b0a6"])
		var rad := 0.2 + r.f() * 0.06
		F.cyl(M.concrete, c, rad, 0.06, x, gy.call(x, z) + 0.02, z, {"seg": 7, "ry": r.f() * 3, "uv": {"world": 2}})


## An AC outdoor unit on a base, front facing +z, with an optional pipe cover up the wall to to_y.
func ac_unit(F, u: float, y: float, z: float, to_y: float) -> void:
	var c := "#e7e5de"
	var w := 0.8
	var h := 0.56
	var d := 0.28
	F.boxB(M.plain, "#5a5c62", w * 0.9, 0.1, d + 0.02, u, y, z)
	F.boxB(M.atlas, c, w, h, d, u, y + 0.1, z, at("ac_front"))
	F.box(M.plain, "#d9d7cf", w + 0.02, 0.03, d + 0.02, u, y + 0.1 + h, z)
	if to_y:
		var px := u + w / 2.0 - 0.08
		F.box(M.plain, "#dcd8cc", 0.1, 0.08, z - d / 2.0 + 0.02, px, y + 0.45, (z - d / 2.0) / 2.0 + 0.01)
		F.boxB(M.plain, "#dcd8cc", 0.1, to_y - (y + 0.4), 0.08, px, y + 0.4, 0.04)
		F.box(M.plain, "#cfcabd", 0.14, 0.14, 0.1, px, to_y + 0.05, 0.05)


func elec_meter(F, u: float, y: float) -> void:
	F.box(M.plain, "#5f6166", 0.24, 0.36, 0.09, u, y, 0.045)
	F.box(M.atlas, "#ffffff", 0.17, 0.25, 0.11, u, y + 0.01, 0.07, at("elec_meter"))
	F.boxB(M.plain, "#8d9197", 0.05, 1.3, 0.05, u + 0.1, y + 0.2, 0.03)


func gas_meter(F, u: float, y: float, g0: float) -> void:
	F.box(M.atlas, "#ffffff", 0.28, 0.32, 0.16, u, y, 0.1, at("gas_meter"))
	var pc := "#d6c06a"
	F.boxB(M.plain, pc, 0.035, y - 0.16 - g0 + 0.05, 0.035, u - 0.08, g0 - 0.05, 0.1)
	F.box(M.plain, pc, 0.035, 0.035, 0.1, u + 0.08, y + 0.22, 0.05)
	F.boxB(M.plain, pc, 0.035, 0.24, 0.035, u + 0.08, y + 0.16, 0.1)


func propane(F, u: float, g0: float) -> void:
	for s in [-0.21, 0.21]:
		F.cyl(M.plain, "#dcdcd6", 0.17, 1.12, u + s, g0 + 0.56, 0.22, {"seg": 10})
		F.raw(M.plain, "#dcdcd6", blob_raw(0, 1), u + s, g0 + 1.12, 0.22, {"sx": 0.34, "sy": 0.2, "sz": 0.34})
		F.cyl(M.plain, "#8a8f96", 0.09, 0.12, u + s, g0 + 1.25, 0.22, {"seg": 8, "open": true})
	F.box(M.plain, "#6d747c", 0.9, 0.02, 0.02, u, g0 + 0.9, 0.4)
	F.box(M.plain, "#8a8f96", 0.2, 0.14, 0.08, u, g0 + 1.35, 0.05)
	F.boxB(M.concrete, "#b9b8b2", 0.9, 0.06, 0.48, u, g0 - 0.02, 0.24, {"uv": {"world": 2}})


func water_heater(F, u: float, y: float) -> void:
	F.box(M.plain, "#ecebe6", 0.46, 0.6, 0.22, u, y, 0.11)
	F.box(M.atlas, "#ffffff", 0.3, 0.1, 0.01, u, y + 0.14, 0.226, at("vent"))
	for k in 3:
		F.boxB(M.plain, "#c9a24a" if k == 0 else "#9aa1a8", 0.03, 0.5, 0.03, u - 0.12 + k * 0.12, y - 0.8, 0.08)


func vent_hood(F, u: float, y: float) -> void:
	F.box(M.plain, "#dedbd3", 0.18, 0.18, 0.1, u, y, 0.05)
	F.box(M.plain, "#d4d1c8", 0.2, 0.03, 0.15, u, y + 0.1, 0.075, {"rx": 0.35})


## A small BS/CS satellite dish facing local direction ry.
func dish(F, x: float, y: float, z: float, ry: float) -> void:
	var DF = F.sub(x, y, z, ry)
	DF.cyl(M.plain, "#e9e8e3", 0.23, 0.03, 0, 0.12, 0.08, {"rx": -0.9, "seg": 12})
	DF.box(M.plain, "#bfc3c8", 0.03, 0.03, 0.35, 0, 0.0, 0.2, {"rx": 0.35})
	DF.box(M.plain, "#d8d8d4", 0.06, 0.06, 0.08, 0, -0.05, 0.36)
	DF.box(M.plain, "#9aa1a8", 0.04, 0.3, 0.04, 0, -0.05, 0.0)


func plate(F, x: float, y: float, z: float, name) -> void:
	var v: bool = name != null and String(name).begins_with("plateV")
	F.box(M.atlas, "#ffffff", 0.12 if v else 0.26, 0.3 if v else 0.1, 0.025, x, y, z + 0.012, at(name if name else "plateH0"))


## A futon draped over a balcony railing.
func futon(F, x: float, y: float, z: float, r) -> void:
	var pat: String = pick(r, ["futon_a", "futon_b", "futon_c"])
	var w := 1.0
	var hh := 0.75
	F.box(M.atlas, "#ffffff", w, hh, 0.09, x, y - hh / 2.0 + 0.04, z + 0.08, {"uv": {"rect": A.rects[pat], "white": A.white, "faces": "front"}})
	F.box(M.atlas, "#ffffff", w, 0.4, 0.09, x, y - 0.18, z - 0.08, {"uv": {"rect": A.rects[pat], "white": A.white, "faces": "front"}})
	F.cyl(M.plain, "#efe7ea", 0.075, w, x, y + 0.04, z, {"rz": PI / 2.0, "seg": 8})
	for s in [-0.3, 0.3]:
		F.box(M.plain, "#6a8fc0", 0.05, 0.14, 0.24, x + s, y + 0.02, z)


## Doorstep life around the porch, on the entrance's face frame.
func doorstep(F, du: float, dw: float, top: float, pw: float, pd: float, S: Dictionary) -> void:
	var r = S.rng
	F.boxB(M.plain, pick(r, ["#6b5a4c", "#5b5f6a", "#7a6a50", "#4f5f58"]), 0.75, 0.015, 0.45, du, top, 0.45)
	if r.f() < 0.55:
		var sx0 := du + (r.f() - 0.5) * 0.4
		for s in [-0.07, 0.07]:
			var c = pick(r, ["#3e5a78", "#8a6446", "#c9b6a0"])
			var zz := 0.75 + (r.f() - 0.5) * 0.05
			F.boxB(M.plain, c, 0.1, 0.03, 0.26, sx0 + s, top, zz, {"ry": (r.f() - 0.5) * 0.4})
	var side := -1 if du > 0 else 1
	var sx := du + side * (pw / 2.0 - 0.25)
	if r.f() < 0.65:
		F.cyl(M.plain, pick(r, ["#8a8f96", "#6b5a4c", "#c9c2b2"]), 0.12, 0.45, sx, top + 0.225, 0.3, {"seg": 8})
		for i in 3:
			var c = pick(r, ["#3f5f8f", "#e9e4da", "#c84a57", "#4f7a52", "#e8b84a", "#3a3346"])
			var a := (i - 1) * 0.22
			F.cyl(M.plain, c, 0.035, 0.75, sx + sin(a) * 0.18, top + 0.5, 0.3 + (i - 1) * 0.04, {"rz": a, "seg": 6, "rTop": 0.012})
			F.box(M.plain, "#6b5244", 0.02, 0.1, 0.06, sx + sin(a) * 0.36, top + 0.9, 0.3 + (i - 1) * 0.04, {"rz": a})
	if r.f() < 0.22:
		var ux := du + side * (dw / 2.0 + 0.12)
		F.cyl(M.plain, pick(r, ["#3f5f8f", "#c84a57", "#6b5a8a", "#4f7a52"]), 0.028, 0.62, ux, top + 0.3, 0.07, {"rz": side * 0.14, "rx": -0.1, "seg": 6, "rTop": 0.012})
		F.box(M.plain, "#3a3346", 0.025, 0.08, 0.025, ux - side * 0.04, top + 0.64, 0.04)
	if r.f() < 0.25:
		var o := at("cardboard")
		o["ry"] = (r.f() - 0.5) * 0.3
		F.boxB(M.atlas, "#ffffff", 0.4, 0.3, 0.3, du - side * (pw / 2.0 - 0.3), top, 0.35, o)
	elif r.f() < 0.2:
		F.boxB(M.atlas, "#ffffff", 0.45, 0.55, 0.4, du - side * (pw / 2.0 - 0.3), top, 0.28, at("parcel_box"))
	if r.f() < 0.3:
		F.box(M.atlas, "#ffffff", 0.24, 0.2, 0.18, du - side * (dw / 2.0 + 0.45), top + 1.05, 0.09, at("milk"))
	var gf: float = S.groundFront if S.get("groundFront") != null else 0.0
	var np := 1 + int(floor(r.f() * 3))
	for i in np:
		var px := du + (1 if i % 2 else -1) * (pw / 2.0 + 0.25 + r.f() * 0.2)
		pot(F, px, gf, 0.35 + i * 0.35, r, 1.1)
	if r.f() < 0.35:
		watering_can(F, du + side * (pw / 2.0 + 0.5), gf, 1.0, r)
	if r.f() < 0.2:
		bucket(F, du - side * (pw / 2.0 + 0.55), gf, 0.9, r)


func watering_can(F, x: float, y: float, z: float, r) -> void:
	var c = pick(r, ["#5f9a6a", "#e3a33b", "#6f8fbf", "#c9c2b2"])
	F.cyl(M.plain, c, 0.1, 0.2, x, y + 0.1, z, {"seg": 8})
	F.beam(M.plain, c, [x + 0.08, y + 0.08, z], [x + 0.28, y + 0.24, z], 0.025, 0.025)
	F.box(M.plain, c, 0.04, 0.08, 0.02, x - 0.05, y + 0.26, z)
	F.box(M.plain, c, 0.12, 0.02, 0.02, x, y + 0.3, z)


func bucket(F, x: float, y: float, z: float, r) -> void:
	var c = pick(r, ["#4f7fc4", "#d9575a", "#e8c84a", "#e2ded2"])
	F.cyl(M.plain, c, 0.14, 0.26, x, y + 0.13, z, {"rTop": 0.14, "seg": 8, "open": true})
	F.cyl(M.plain, c, 0.1, 0.02, x, y + 0.01, z, {"seg": 8})
	F.box(M.plain, "#8a8f96", 0.26, 0.012, 0.012, x, y + 0.32, z)


func broom(F, x: float, y: float, z: float, _ry: float = 0.0) -> void:
	F.cyl(M.plain, "#c9b27a", 0.015, 1.3, x, y + 0.8, z + 0.1, {"rx": -0.18, "seg": 4})
	F.cyl(M.plain, "#a88f5a", 0.02, 0.45, x, y + 0.22, z + 0.2, {"rx": -0.18, "seg": 5, "rTop": 0.15})


func dustpan(F, x: float, y: float, z: float) -> void:
	F.box(M.plain, "#4f7fc4", 0.26, 0.04, 0.22, x, y + 0.02, z)
	F.box(M.plain, "#4f7fc4", 0.03, 0.5, 0.03, x, y + 0.3, z - 0.08, {"rx": -0.2})


## Garbage sorting bins.
func bins(F, x: float, y: float, z: float, r, n: int = 2) -> void:
	var labels := ["bin_burn", "bin_res", "bin_pla"]
	var cols := ["#6b8f6b", "#5a7fa8", "#8a8f96"]
	for i in n:
		var bx := x + (i - (n - 1) / 2.0) * 0.5
		var c: String = cols[i % 3]
		F.boxB(M.plain, c, 0.42, 0.62, 0.42, bx, y, z)
		F.boxB(M.plain, c, 0.46, 0.06, 0.46, bx, y + 0.62, z)
		F.box(M.atlas, "#ffffff", 0.3, 0.12, 0.01, bx, y + 0.45, z + 0.215, at(labels[i % 3]))


## A steel storage shed, front facing +z.
func shed(F, x: float, y: float, z: float, r, w: float = 1.7) -> void:
	var c = pick(r, ["#dcd8cc", "#c9cfc6", "#d5d2c8"])
	F.boxB(M.plain, "#8a8f96", w + 0.05, 0.1, 0.95, x, y - 0.02, z)
	F.boxB(M.atlas, c, w, 1.75, 0.9, x, y + 0.08, z, at("shed_door"))
	F.box(M.metal, "#7b8691", w + 0.16, 0.05, 1.05, x, y + 1.88, z, {"rx": 0.08, "uv": {"world": 0.9}})


## An outside tap and hose reel.
func faucet(F, x: float, y: float, z: float, r) -> void:
	F.boxB(M.concrete, "#c9c7c0", 0.14, 0.8, 0.14, x, y, z, {"uv": {"world": 2}})
	F.box(M.plain, "#c9ccd1", 0.03, 0.03, 0.12, x, y + 0.7, z + 0.1)
	F.box(M.plain, "#9aa1a8", 0.3, 0.05, 0.3, x, y + 0.02, z + 0.2)
	if r.f() < 0.6:
		F.box(M.atlas, "#ffffff", 0.36, 0.36, 0.1, x + 0.35, y + 0.3, z + 0.05, at("hose"))
		F.box(M.plain, "#8a8f96", 0.05, 0.4, 0.12, x + 0.35, y + 0.2, z + 0.05)


## A yard laundry stand: two stands and poles, laundry optional.
func laundry_stand(F, x: float, z: float, gy: Callable, ln: float, r, with_laundry: bool = true) -> void:
	var c := "#c9ccd1"
	for s in [-1, 1]:
		var px := x + s * ln / 2.0
		var g: float = gy.call(px, z)
		F.boxB(M.concrete, "#b9b8b2", 0.45, 0.12, 0.45, px, g - 0.02, z, {"uv": {"world": 2}})
		F.cyl(M.plain, c, 0.025, 1.7, px, g + 0.95, z, {"seg": 6})
		F.box(M.plain, c, 0.04, 0.04, 0.7, px, g + 1.75, z)
	var g2: float = gy.call(x, z)
	for dz in [-0.28, 0.28]:
		F.cyl(M.plain, "#8fb3c9", 0.016, ln + 0.4, x, g2 + 1.78, z + dz, {"rz": PI / 2.0, "seg": 6})
	if with_laundry:
		H.laundry.line(F, x - ln / 2.0 + 0.3, x + ln / 2.0 - 0.3, g2 + 1.78, z + 0.28, r, "yard")


func toys(F, x: float, y: float, z: float, r) -> void:
	var c = pick(r, ["#d9575a", "#4f7fc4", "#e8c84a"])
	F.cyl(M.plain, "#3a3346", 0.12, 0.05, x - 0.2, y + 0.12, z, {"rz": PI / 2.0, "seg": 10})
	F.cyl(M.plain, "#3a3346", 0.08, 0.04, x + 0.2, y + 0.08, z - 0.12, {"rz": PI / 2.0, "seg": 8})
	F.cyl(M.plain, "#3a3346", 0.08, 0.04, x + 0.2, y + 0.08, z + 0.12, {"rz": PI / 2.0, "seg": 8})
	F.beam(M.plain, c, [x - 0.2, y + 0.14, z], [x + 0.2, y + 0.22, z], 0.06, 0.05)
	F.box(M.plain, c, 0.2, 0.05, 0.16, x + 0.1, y + 0.3, z)
	F.box(M.plain, "#4b4d52", 0.04, 0.25, 0.04, x - 0.18, y + 0.3, z)
	F.cyl(M.plain, "#e8697a", 0.11, 0.22, x + 0.6, y + 0.11, z + 0.2, {"seg": 10})


## A gomi station cage with a green net and a sign.
func gomi_station(F, x: float, y: float, z: float, r) -> void:
	var c := "#6b8f6b"
	F.boxB(M.concrete, "#b9b8b2", 1.9, 0.08, 1.0, x, y - 0.02, z, {"uv": {"world": 2}})
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			F.boxB(M.plain, c, 0.04, 1.1, 0.04, x + sx * 0.9, y, z + sz * 0.45)
	F.box(M.plain, c, 1.84, 0.04, 0.04, x, y + 1.08, z + 0.45)
	F.box(M.plain, c, 1.84, 0.04, 0.04, x, y + 1.08, z - 0.45)
	F.box(M.plain, c, 0.04, 0.04, 0.9, x - 0.9, y + 1.08, z)
	F.box(M.plain, c, 0.04, 0.04, 0.9, x + 0.9, y + 1.08, z)
	F.box(M.plain, "#7faa7a", 1.8, 1.0, 0.02, x, y + 0.56, z - 0.44, {"shadow": false})
	F.box(M.plain, "#7faa7a", 0.02, 1.0, 0.88, x - 0.89, y + 0.56, z, {"shadow": false})
	F.box(M.plain, "#7faa7a", 0.02, 1.0, 0.88, x + 0.89, y + 0.56, z, {"shadow": false})
	F.box(M.atlas, "#ffffff", 0.5, 0.3, 0.02, x + 0.5, y + 0.8, z + 0.47, at("gomi_sign"))
	if r.f() < 0.6:
		for i in 2:
			F.raw(M.plain, "#eeeae0", blob_raw(i + 2, 0), x - 0.4 + i * 0.35, y + 0.2, z - 0.1, {"sx": 0.4, "sy": 0.38, "sz": 0.35})
