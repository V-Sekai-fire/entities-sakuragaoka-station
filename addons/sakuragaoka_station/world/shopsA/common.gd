# shopsA/common.js: shared helpers. Tiling hand-painted textures (stand-ins here), texture atlases
# (one material per page), lot-local spaces (group + kit + ground + physics in lot coordinates),
# generic shop-front and back-yard props, and an instanced "scatter" for flower heads and leaves.
# The port draws no canvases: atlas regions are packed exactly as the original packs them (same
# sizes, same pages, same UVs) but left blank; their draw callbacks are not ported.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Fol = preload("res://addons/sakuragaoka_station/world/lib/foliage.gd")
const GM = preload("res://addons/sakuragaoka_station/world/shopsA/geom.gd")

const DEG := PI / 180.0

## Tiling textures: [name, w, h, key, repeat or null]
const TILES := [
	["wash", 512, 512, "shopsA.wash", [1, 1]],
	["wood", 256, 256, "shopsA.wood", [1, 1]],
	["planks", 512, 512, "shopsA.planks", [1, 1]],
	["tiles", 256, 256, "shopsA.tiles", [1, 1]],
	["roofTile", 256, 256, "shopsA.roofTile", [1, 1]],
	["seam", 256, 64, "shopsA.seam", [1, 1]],
	["brick", 256, 256, "shopsA.brick", [1, 1]],
	["concrete", 512, 512, "shopsA.concrete", [1, 1]],
	["crate", 128, 128, "shopsA.crate", null],
	["carton", 128, 128, "shopsA.carton", null],
]

var ctx
var L
var F
var T_: Dictionary = {}
var M
var A: Dictionary = {}
var P
var scatter
var G = null


func _init(c) -> void:
	ctx = c
	L = c.L
	F = c.tex.FONTS
	for t in TILES:
		var o := {"key": t[3]}
		if t[4] != null:
			o["repeat"] = t[4]
		T_[t[0]] = c.tex.draw(t[1], t[2], null, o)
	M = Mats.new(c, T_)
	A = {"lit": Atlas.new(c, "lit"), "glow": Atlas.new(c, "glow"), "cut": Atlas.new(c, "cut"), "inner": Atlas.new(c, "inner")}
	scatter = Scatter.new(c)
	P = Props.new(self)


static func col(c) -> Color:
	return T.color(c)


static func hex(c) -> String:
	return "#" + T.hex_string(T.color(c))


# ------------------------------------------------------------------ geometry (forwarders)

func uv_box(w: float, h: float, d: float, s: float = 1.0) -> T.Geometry:
	return GM.uv_box(w, h, d, s)


func uv_plane(w: float, h: float, s: float = 1.0) -> T.Geometry:
	return GM.uv_plane(w, h, s)


func profile_x(pts: Array, w: float) -> T.Geometry:
	return GM.profile_x(pts, w)


func scallop_geo(w: float, sw: float = 0.16, lip: float = 0.03) -> T.Geometry:
	return GM.scallop_geo(w, sw, lip)


func region_geo(reg: Dictionary, w: float, h: float, sub = null) -> T.Geometry:
	return GM.region_geo(reg, w, h, sub)


## Drops null-valued options (the original's `undefined`), so material option defaults apply.
static func opts(o: Dictionary) -> Dictionary:
	var out := {}
	for k in o:
		if o[k] != null:
			out[k] = o[k]
	return out


# ------------------------------------------------------------------ materials
## The core static batcher merges by material signature, so interior self-light is quantised to a
## few warm levels (by albedo luminance) instead of c * WARM.
class Mats extends RefCounted:
	const INNER_LV := [0.05, 0.14, 0.3, 0.52, 0.78]
	var ctx
	var mat
	var TX: Dictionary
	var _stripes := {}

	func _init(c, tx: Dictionary) -> void:
		ctx = c
		mat = c.mat
		TX = tx

	func _with(o: Dictionary, extra: Dictionary) -> Dictionary:
		var r := extra.duplicate()
		for k in o:
			r[k] = o[k]
		var out := {}
		for k in r:
			if r[k] != null:
				out[k] = r[k]
		return out

	func inner_em(c, amt: float) -> Dictionary:
		var cc := T.color(c)
		var lum := 0.2126 * cc.r + 0.7152 * cc.g + 0.0722 * cc.b
		var lv: float = INNER_LV[0]
		for i in range(1, INNER_LV.size()):
			var b: float = INNER_LV[i]
			if absf(b - lum) < absf(lv - lum):
				lv = b
		var w := T.color("#ffdcae")
		return {"emissive": "#" + T.hex_string(Color(w.r * lv, w.g * lv, w.b * lv)),
			"emissiveIntensity": 0.2 if amt < 0.24 else (0.3 if amt < 0.38 else 0.42)}

	func quant_glass(o: Dictionary = {}) -> Dictionary:
		if o.get("frost"):
			return {"tint": "#9fb6c8", "opacity": 0.26, "frost": true}
		var op: float = o.opacity if o.get("opacity") != null else 0.2
		return {"tint": "#6b4a37" if o.get("tint") == "#6b4a37" else "#9fb6c8", "opacity": 0.18 if op < 0.24 else (0.3 if op < 0.38 else 0.45)}

	func t(c, o: Dictionary = {}):
		return mat.toon(c, _with(o, {}))

	func wall(c, o: Dictionary = {}):
		return mat.toon(c, _with(o, {"map": TX.wash}))

	func wood(c, o: Dictionary = {}):
		return mat.toon(c, _with(o, {"map": TX.wood}))

	func planks(c, o: Dictionary = {}):
		return mat.toon(c, _with(o, {"map": TX.planks}))

	func tiles(c, o: Dictionary = {}):
		return mat.toon(c, _with(o, {"map": TX.tiles}))

	func brick(o: Dictionary = {}):
		return mat.toon("#ffffff", _with(o, {"map": TX.brick}))

	func concrete(c = "#cfcdc6", o: Dictionary = {}):
		return mat.toon(c, _with(o, {"map": TX.concrete}))

	func roof_tile(c, o: Dictionary = {}):
		return mat.toon(c, _with(o, {"map": TX.roofTile}))

	func seam(c, o: Dictionary = {}):
		return mat.toon(c, _with(o, {"map": TX.seam}))

	func crate(c):
		return mat.toon(c, {"map": TX.crate, "paint": 0.03})

	func carton(c = "#c9a57a"):
		return mat.toon(c, {"map": TX.carton, "paint": 0.04})

	func stripe_tex(a: String, b: String, n: int = 4):
		var key := "shopsA.stripe|%s|%s|%d" % [a, b, n]
		if _stripes.has(key):
			return _stripes[key]
		var tx = ctx.tex.draw(256, 16, null, {"key": key, "repeat": [1, 1]})
		_stripes[key] = tx
		return tx

	func stripe(a: String, b: String, n = null):
		return mat.toon("#ffffff", {"map": stripe_tex(a, b, 4 if n == null else n), "paint": 0.05})

	## interior surface: toon + (quantised) warm self-light so shop interiors glow softly behind the glass
	func inner(c, amt: float = 0.3, o: Dictionary = {}):
		return mat.toon(c, _with(o, inner_em(c, amt)))

	func inner_map(c, map, amt: float = 0.3, o: Dictionary = {}):
		var e := inner_em(c, amt)
		e["map"] = map
		return mat.toon(c, _with(o, e))

	func glow(c, i: float = 1.0, o: Dictionary = {}):
		return mat.emissive(c, i, o)

	func glass(o: Dictionary = {}):
		return mat.glass(quant_glass(o))

	func decal(c, o: Dictionary = {}):
		return mat.decal(c, o)


# ------------------------------------------------------------------ atlases
class Atlas extends RefCounted:
	var ctx
	var kind: String
	var size: int
	var pages: Array = []

	func _init(c, k: String, s: int = 1024) -> void:
		ctx = c
		kind = k
		size = s
		_new()

	func _new() -> void:
		var cv: Dictionary = ctx.tex.canvas(size, size)
		var t = ctx.tex.finish(cv, {"anisotropy": 8})
		var i := pages.size()
		var m
		if kind == "glow":
			m = ctx.mat.emissive("#ffffff", 1.0, {"map": t})
		elif kind == "inner":
			m = ctx.mat.emissive("#fff0dc", 0.92, {"map": t})
		elif kind == "cut":
			m = ctx.mat.toon("#ffffff", {"map": t, "alphaTest": 0.5, "side": "double", "paint": 0.02, "name": "shopsA-cut-%d" % i})
		else:
			m = ctx.mat.toon("#ffffff", {"map": t, "paint": 0.0, "name": "shopsA-atlas-%d" % i})
		pages.append({"canvas": cv.canvas, "t": t, "m": m, "x": 0, "y": 0, "rowH": 0})

	## Reserves a w x h cell (+ 4 px padding). The draw callback is the original's canvas painting.
	func region(w: float, h: float, _fn = null, _o: Dictionary = {}) -> Dictionary:
		var pad := 4
		var S := size
		var wi := int(T.js_round(w))
		var hi := int(T.js_round(h))
		var pg: Dictionary = pages[pages.size() - 1]
		if pg.x + wi + pad * 2 > S:
			pg.x = 0
			pg.y += pg.rowH
			pg.rowH = 0
		if pg.y + hi + pad * 2 > S:
			_new()
			pg = pages[pages.size() - 1]
		var x: int = pg.x + pad
		var y: int = pg.y + pad
		pg.x += wi + pad * 2
		pg.rowH = maxi(pg.rowH, hi + pad * 2)
		return {"m": pg.m, "u0": float(x) / S, "u1": float(x + wi) / S, "v0": 1.0 - float(y + hi) / S, "v1": 1.0 - float(y) / S, "w": wi, "h": hi}

	func finalize() -> void:
		pass


# ------------------------------------------------------------------ lot spaces
class Space extends RefCounted:
	var ctx
	var id: String
	var lot
	var f: Dictionary
	var g
	var k
	var c: float
	var s: float
	var ph

	func to_w(lx: float, lz: float) -> Dictionary:
		return {"x": f.x + lx * c + lz * s, "z": f.z - lx * s + lz * c}

	func to_l(x: float, z: float) -> Dictionary:
		var dx: float = x - f.x
		var dz: float = z - f.z
		return {"x": dx * c - dz * s, "z": dx * s + dz * c}

	func gy(lx: float, lz: float) -> float:
		var p := to_w(lx, lz)
		return ctx.L.height_at(p.x, p.z) - f.y

	func box(lx: float, lz: float, w: float, d: float, y0: float, y1: float, rot: float = 0.0):
		var p := to_w(lx, lz)
		return ph.addBox(p.x, p.z, w, d, f.rotY + rot, f.y + y0, f.y + y1)

	func walk(lx: float, lz: float, w: float, d: float, top: float, rot: float = 0.0):
		var p := to_w(lx, lz)
		return ph.addWalkBox(p.x, p.z, w, d, f.rotY + rot, f.y + top)

	func ramp(lx: float, lz: float, w: float, d: float, yA: float, yB: float, rot: float = 0.0):
		var p := to_w(lx, lz)
		return ph.addWalkRamp(p.x, p.z, w, d, f.rotY + rot, f.y + yA, f.y + yB)

	func cyl(lx: float, lz: float, r: float, y0: float, y1: float):
		var p := to_w(lx, lz)
		return ph.addCylinder(p.x, p.z, r, f.y + y0, f.y + y1)

	func world(lx: float, ly: float, lz: float) -> Vector3:
		var p := to_w(lx, lz)
		return Vector3(p.x, f.y + ly, p.z)

	func dyn():
		var d := T.Group.new()
		d.position = g.position
		d.rotation.y = f.rotY
		ctx.add(d)
		return d

	func ubox(w: float, h: float, d: float, m, pos: Array, rot = null, sc: float = 1.0):
		return k.mesh(GM.uv_box(w, h, d, sc), m, pos, rot)

	func uboxB(w: float, h: float, d: float, m, pos: Array, rot = null, sc: float = 1.0):
		return k.mesh(GM.uv_box(w, h, d, sc), m, [pos[0], pos[1] + h / 2.0, pos[2]], rot)

	func card(reg: Dictionary, w: float, h: float, pos: Array, rot = null, sub = null, kk = null):
		var kit = kk if kk != null else k
		var m = kit.mesh(GM.region_geo(reg, w, h, sub), reg.m, pos, rot)
		m.cast_shadow = false
		return m


func space(id: String) -> Space:
	var lot = L.lot_by_id(id)
	var f: Dictionary = L.lot_frame(lot)
	var g := T.Group.new()
	g.name = "shopsA:" + id
	g.position = Vector3(f.x, f.y, f.z)
	g.rotation.y = f.rotY
	ctx.add_static(g)
	g.update_matrix_world(true)
	var S := Space.new()
	S.ctx = ctx
	S.id = id
	S.lot = lot
	S.f = f
	S.g = g
	S.k = ctx.kit(g)
	S.c = cos(f.rotY)
	S.s = sin(f.rotY)
	S.ph = ctx.physics
	return S


## Ground-following paving (lot-local rectangle), lifted a little above the terrain.
func pave(S: Space, x0: float, x1: float, z0: float, z1: float, m, o: Dictionary = {}):
	var step: float = o.step if o.get("step") != null else 0.8
	var lift: float = o.lift if o.get("lift") != null else 0.02
	var s: float = o.uv if o.get("uv") != null else 1.0
	var nx := maxi(1, int(ceil((x1 - x0) / step)))
	var nz := maxi(1, int(ceil((z1 - z0) / step)))
	var geo := Geo.plane(x1 - x0, z1 - z0, nx, nz)
	geo.rotate_x(-PI / 2.0)
	geo.translate((x0 + x1) / 2.0, 0, (z0 + z1) / 2.0)
	var p: T.Attr = geo.attributes.position
	var t: T.Attr = geo.attributes.uv
	for i in p.count():
		var x := p.get_x(i)
		var z := p.get_z(i)
		var yv: float = o.yFn.call(x, z) if o.get("yFn") != null else S.gy(x, z)
		p.set_y(i, yv + lift)
		t.set_xy(i, x / s, -z / s)
	geo.compute_vertex_normals()
	var mesh := T.MeshObj.new(geo, m)
	mesh.receive_shadow = true
	mesh.cast_shadow = false
	S.g.add(mesh)
	return mesh


## Foundation/plinth block: top at y = top, bottom buried below the lowest ground in the footprint.
func plinth(S: Space, x0: float, x1: float, z0: float, z1: float, top: float, m, sc: float = 1.0):
	var lo := INF
	for q in [[x0, z0], [x1, z0], [x0, z1], [x1, z1], [(x0 + x1) / 2.0, (z0 + z1) / 2.0]]:
		lo = minf(lo, S.gy(q[0], q[1]))
	var y0 := lo - 0.25
	return S.ubox(x1 - x0, top - y0, z1 - z0, m, [(x0 + x1) / 2.0, (top + y0) / 2.0, (z0 + z1) / 2.0], null, sc)


# ------------------------------------------------------------------ instanced scatter (flowers, leaves, blossoms)
class Scatter extends RefCounted:
	var ctx
	var lists := {}
	var _last_base = null

	func _init(c) -> void:
		ctx = c

	static func tulip_geo() -> T.Geometry:
		var pts := []
		for p in [[0.0, 0], [0.55, 0.12], [0.85, 0.45], [0.9, 0.8], [0.72, 1.0]]:
			pts.append(Vector2(p[0], p[1]))
		return Geo.lathe(pts, 8)

	static func type_geo(type: String) -> T.Geometry:
		match type:
			"ball":
				return GM.smooth_ico(0)
			"bush":
				return GM.smooth_ico(1)
			"cup":
				return tulip_geo()
			"disc":
				return Geo.cylinder(1, 1, 1, 8)
			"stem":
				return Geo.cylinder(1, 1, 1, 4, 1, true)
			_:
				var g := Geo.plane(1, 1)
				g.translate(0, 0.5, 0)
				return g

	## base: a space S or any Object3D; pos / scl / rot in base-local coordinates.
	func add(type: String, base, pos: Array, scl: Array, color, rot = null) -> void:
		var o = base.g if base is Space else base
		if o != _last_base:
			GM.update_world(o)
			_last_base = o
		var e := Vector3(float(rot[0]) if rot != null and rot[0] else 0.0, float(rot[1]) if rot != null and rot[1] else 0.0, float(rot[2]) if rot != null and rot[2] else 0.0)
		var q := Basis.from_euler(e, EULER_ORDER_XYZ).get_rotation_quaternion()
		var m: Transform3D = o.matrix_world * T.compose(Vector3(pos[0], pos[1], pos[2]), q, Vector3(scl[0], scl[1], scl[2]))
		if not lists.has(type):
			lists[type] = []
		lists[type].append({"m": m, "c": T.color(color)})

	func build() -> Array:
		var out := []
		for type in lists:
			var arr: Array = lists[type]
			if arr.is_empty():
				continue
			var side = "double" if type == "cup" or type == "blade" else null
			var o := {"paint": 0.03}
			if side != null:
				o["side"] = side
			var m = ctx.mat.toon("#ffffff", o)
			var im := T.InstancedMesh.new(type_geo(type), m, arr.size())
			for i in arr.size():
				im.set_matrix_at(i, arr[i].m)
				im.set_color_at(i, arr[i].c)
			im.cast_shadow = type == "bush"
			im.receive_shadow = true
			im.name = "shopsA-scatter-" + type
			if type != "bush":
				ctx.no_outline(im)
			ctx.add_static(im)
			out.append(im)
		return out


# ------------------------------------------------------------------ foliage
func shrub_mat():
	return ctx.mat.toon("#ffffff", {"vertexColors": true, "paint": 0.03})


func green_set(c) -> Dictionary:
	var b := col(c)
	var top := b.lerp(col("#e4f0b0"), 0.38)
	var bm := Color(b.r * 0.72, b.g * 0.72, b.b * 0.72)
	var base := bm.lerp(col("#3d5a66"), 0.25)
	return {"top": "#" + T.hex_string(top), "mid": "#" + T.hex_string(b), "base": "#" + T.hex_string(base)}


## Smooth foliage clump from lib/foliage.js (shared vertex-colour toon material). parent: space S or
## Object3D; pos = ground contact centre. o: r, h, sx, sz, seed, colors | kind | green, seg
func shrub(parent, x: float, y: float, z: float, o: Dictionary = {}):
	var p = parent.g if parent is Space else parent
	var r: float = o.r if o.get("r") != null else 0.3
	var h: float = o.h if o.get("h") != null else r * 1.4
	var colors
	if o.get("colors") != null:
		colors = o.colors
	elif o.get("green") != null:
		colors = green_set(o.green)
	else:
		colors = Fol.SHRUB_COLORS[o.kind if o.get("kind") != null else "boxwood"]
	var seg = o.seg if o.get("seg") != null else (12 if r < 0.1 else (16 if r < 0.2 else null))
	var fo := {"rx": r * (o.sx if o.get("sx") != null else 1.0), "ry": h / 2.0, "rz": r * (o.sz if o.get("sz") != null else 1.0),
		"lumps": o.lumps if o.get("lumps") != null else 0.22, "freq": o.freq if o.get("freq") != null else (5 if r < 0.15 else 2.6),
		"seed": o.seed if o.get("seed") != null else 1, "colors": colors, "seg": seg,
		"flatBottom": o.flatBottom if o.get("flatBottom") != null else true}
	var g := Fol.shrub_geometry(fo)
	var m := T.MeshObj.new(g, shrub_mat())
	m.position = Vector3(x, y, z)
	if o.get("rot") != null:
		m.rotation = Vector3(o.rot[0], o.rot[1], o.rot[2])
	m.cast_shadow = o.shadow if o.get("shadow") != null else true
	m.receive_shadow = true
	p.add(m)
	return m


# ------------------------------------------------------------------ generic props
class Props extends RefCounted:
	var C
	var ctx
	var M
	var mMetal
	var mMetalDark
	var mInk

	func _init(c) -> void:
		C = c
		ctx = c.ctx
		M = c.M
		mMetal = M.t("#9aa1a8")
		mMetalDark = M.t("#6d747c")
		mInk = M.t("#4a4552")

	## plastic crate. pos = bottom centre.
	func crate(S, x: float, y: float, z: float, rotY: float = 0.0, c = "#4f8fc0", o: Dictionary = {}):
		var w: float = o.w if o.get("w") != null else 0.5
		var h: float = o.h if o.get("h") != null else 0.3
		var d: float = o.d if o.get("d") != null else 0.36
		var m = S.k.box(w, h, d, M.crate(c), [x, y + h / 2.0, z], [0, rotY, 0])
		if o.get("bottles"):
			var gq = S.k.group([x, y + h, z], rotY)
			var kk = ctx.kit(gq)
			for i in 4:
				for j in 3:
					kk.cyl(0.028, 0.028, 0.04, M.t(o.bottles), [-w / 2.0 + 0.07 + i * (w - 0.14) / 3.0, 0.0, -d / 2.0 + 0.07 + j * (d - 0.14) / 2.0], null, 6)
		return m

	## cardboard box
	func carton(S, x: float, y: float, z: float, w: float, h: float, d: float, rotY: float = 0.0, c = "#c9a57a"):
		return S.k.box(w, h, d, M.carton(c), [x, y + h / 2.0, z], [0, rotY, 0])

	## wall-hung / ground AC outdoor unit with duct cover up the wall. pos = bottom centre, back at -z.
	func ac_unit(S, x: float, y: float, z: float, rotY: float = 0.0, o: Dictionary = {}):
		var w: float = o.w if o.get("w") != null else 0.8
		var h: float = o.h if o.get("h") != null else 0.6
		var d: float = o.d if o.get("d") != null else 0.29
		var gq = S.k.group([x, y, z], rotY)
		var k = ctx.kit(gq)
		var body = M.t("#e4e2da")
		k.rbox(w, h, d, 0.03, body, [0, h / 2.0 + 0.06, 0])
		k.cyl(h * 0.36, h * 0.36, 0.02, M.t("#5d6068"), [-w * 0.14, h / 2.0 + 0.06, d / 2.0 + 0.005], [PI / 2.0, 0, 0], 16)
		k.cyl(h * 0.12, h * 0.12, 0.03, M.t("#d9d7cf"), [-w * 0.14, h / 2.0 + 0.06, d / 2.0 + 0.01], [PI / 2.0, 0, 0], 10)
		for i in range(-2, 3):
			k.box(h * 0.72, 0.012, 0.012, M.t("#8b8e96"), [-w * 0.14, h / 2.0 + 0.06 + i * h * 0.13, d / 2.0 + 0.02])
		k.box(w * 0.22, h * 0.7, 0.01, M.t("#cfcdc5"), [w * 0.34, h / 2.0 + 0.06, d / 2.0 + 0.003])
		k.box(0.08, 0.06, d * 0.9, M.t("#5d5a62"), [-w * 0.36, 0.03, 0])
		k.box(0.08, 0.06, d * 0.9, M.t("#5d5a62"), [w * 0.36, 0.03, 0])
		if o.get("duct") != false:
			var dh: float = o.ductH if o.get("ductH") != null else 1.4
			k.box(0.1, 0.1, 0.22, M.t("#e8e1cf"), [w / 2.0 + 0.06, h * 0.45, -d / 2.0 + 0.02])
			k.box(0.1, dh, 0.08, M.t("#e8e1cf"), [w / 2.0 + 0.06, h * 0.45 + dh / 2.0, -d / 2.0 - 0.06])
		return gq

	## electric meter on a small board. pos = centre, facing +z.
	func meter(S, x: float, y: float, z: float, rotY: float = 0.0):
		var gq = S.k.group([x, y, z], rotY)
		var k = ctx.kit(gq)
		k.box(0.26, 0.36, 0.02, M.t("#d8d5cc"), [0, 0, 0.01])
		k.rbox(0.16, 0.22, 0.12, 0.02, M.t("#b9bcc0"), [0, 0.01, 0.08])
		k.box(0.1, 0.07, 0.01, M.glow("#dfe9e6", 0.8), [0, 0.05, 0.145])
		k.cyl(0.018, 0.018, 0.9, M.t("#8e9298"), [0.1, 0.62, 0.03])
		return gq

	func gas_meter(S, x: float, y: float, z: float, rotY: float = 0.0):
		var gq = S.k.group([x, y, z], rotY)
		var k = ctx.kit(gq)
		k.rbox(0.24, 0.26, 0.14, 0.03, M.t("#c9c5b6"), [0, 0, 0.09])
		k.box(0.12, 0.05, 0.01, M.t("#5a5f66"), [0, 0.05, 0.165])
		k.cyl(0.02, 0.02, 0.5, M.t("#d6b64f"), [-0.07, -0.36, 0.06])
		k.cyl(0.02, 0.02, 0.5, M.t("#d6b64f"), [0.07, -0.36, 0.06])
		return gq

	## two LPG cylinders with a chain. pos = bottom centre between them, backs to -z
	func propane(S, x: float, y: float, z: float, rotY: float = 0.0):
		var gq = S.k.group([x, y, z], rotY)
		var k = ctx.kit(gq)
		var m = M.t("#aeb3b8")
		for s in [-1, 1]:
			k.cyl(0.16, 0.16, 1.0, m, [s * 0.19, 0.55, 0], null, 12)
			k.sphere(0.16, m, [s * 0.19, 1.05, 0], 10)
			k.cyl(0.17, 0.17, 0.06, M.t("#8d9298"), [s * 0.19, 0.03, 0], null, 12)
			k.cyl(0.06, 0.06, 0.1, M.t("#6d747c"), [s * 0.19, 1.2, 0], null, 8)
			k.box(0.2, 0.04, 0.01, M.t("#d6c35a"), [s * 0.19, 0.8, 0.162])
		ctx.wires.add([S.world(x - 0.4, y + 0.85, z), S.world(x, y + 0.8, z + 0.2), S.world(x + 0.4, y + 0.85, z)], {"width": 0.012, "color": "#6b6770"})
		k.cyl(0.015, 0.015, 0.6, M.t("#d6b64f"), [0, 1.2, -0.12], [0, 0, PI / 2.0])
		return gq

	## vertical pipe from y0 to y1 (lot-local)
	func pipe(S, x: float, z: float, y0: float, y1: float, r: float = 0.04, m = null):
		if m == null:
			m = M.t("#b9b7ae")
		return S.k.cyl(r, r, y1 - y0, m, [x, (y0 + y1) / 2.0, z], null, 8)

	## pipe along x or z at height y
	func pipe_h(S, x0: float, x1: float, y: float, z: float, r: float = 0.035, m = null, along_z: bool = false):
		if m == null:
			m = M.t("#b9b7ae")
		var L2 := absf(x1 - x0)
		if along_z:
			return S.k.cyl(r, r, L2, m, [z, y, (x0 + x1) / 2.0], [PI / 2.0, 0, 0], 8)
		return S.k.cyl(r, r, L2, m, [(x0 + x1) / 2.0, y, z], [0, 0, PI / 2.0], 8)

	## downpipe with brackets + shoe at the bottom (ends at ground). n = unit (x, z) direction to the wall.
	func downpipe(S, x: float, z: float, y_top: float, m = null, n: Array = [0, -1]) -> void:
		if m == null:
			m = M.t("#c9c3b4")
		var yb: float = S.gy(x, z)
		S.k.cyl(0.04, 0.04, y_top - yb - 0.1, m, [x, (y_top + yb + 0.1) / 2.0, z], null, 8)
		S.k.cyl(0.045, 0.045, 0.14, m, [x - n[0] * 0.05, yb + 0.08, z - n[1] * 0.05], [-n[1] * PI / 4.0, 0, n[0] * PI / 4.0], 8)
		var dims := [0.06, 0.03, 0.12] if n[0] else [0.12, 0.03, 0.06]
		var yy := yb + 0.8
		while yy < y_top - 0.3:
			S.k.box(dims[0], dims[1], dims[2], m, [x + n[0] * 0.03, yy, z + n[1] * 0.03])
			yy += 1.2

	## steel back door with frame, handle, small hood and a lamp. pos = bottom centre on wall face (+z out).
	func back_door(S, x: float, y: float, z: float, rotY: float = 0.0, c = "#8f9aa0", o: Dictionary = {}):
		var gq = S.k.group([x, y, z], rotY)
		var k = ctx.kit(gq)
		k.box(0.98, 2.1, 0.05, M.t("#6f757c"), [0, 1.05, 0.0])
		k.box(0.86, 2.0, 0.04, M.t(c), [0, 1.0, 0.03])
		k.box(0.04, 0.16, 0.05, M.t("#4f5358"), [0.33, 1.0, 0.07])
		k.box(0.5, 0.04, 0.01, M.t("#7b8388"), [0, 1.65, 0.052])
		if o.get("hood") != false:
			k.box(1.2, 0.05, 0.5, M.t("#8a9096"), [0, 2.32, 0.25])
			k.box(1.2, 0.08, 0.02, M.t("#8a9096"), [0, 2.29, 0.5])
		if o.get("lamp") != false:
			k.box(0.12, 0.16, 0.08, M.t("#e6e4dc"), [0.62, 2.0, 0.05])
			k.box(0.08, 0.1, 0.02, M.glow("#ffe8c0", 1.1), [0.62, 2.0, 0.1])
		if o.get("label"):
			S.card(o.label, 0.3, 0.1, [0, 1.5, 0.056], null, null, k)
		return gq

	## terracotta / ceramic pot with a plant. pos = bottom centre
	func pot(S, x: float, y: float, z: float, o: Dictionary = {}) -> void:
		var r: float = o.r if o.get("r") != null else 0.16
		var h: float = o.h if o.get("h") != null else r * 1.5
		var c = o.color if o.get("color") != null else "#c7805d"
		S.k.cyl(r, r * 0.74, h, M.t(c), [x, y + h / 2.0, z], null, 12)
		S.k.cyl(r * 1.06, r * 1.06, h * 0.12, M.t(c), [x, y + h * 0.94, z], null, 12)
		S.k.cyl(r * 0.92, r * 0.92, 0.01, M.t("#6a5040"), [x, y + h * 0.9, z], null, 10)
		var kind: String = o.plant if o.get("plant") != null else "bush"
		var g0 := y + h * 0.9
		var rr = ctx.rng("pot|%s|%s|%s" % [S.id, GM.to_fixed2(x), GM.to_fixed2(z)])
		var greens: Array = o.greens if o.get("greens") != null else ["#6f9a5a", "#5f8c5c", "#86ad68"]
		var pseed := floori(rr.f() * 1000)
		var sc = C.scatter
		if kind == "bush":
			C.shrub(S, x, g0 - r * 0.1, z, {"r": r * 1.05, "h": r * 1.5, "green": greens[0], "seed": pseed})
		elif kind == "flowers":
			C.shrub(S, x, g0 - r * 0.05, z, {"r": r * 0.95, "h": r * 0.9, "green": greens[0], "seed": pseed, "lumps": 0.18})
			var fc: Array = o.flowers if o.get("flowers") != null else ["#f2b5c8", "#fbe9ef", "#f1e3b0"]
			var n: int = o.n if o.get("n") != null else 9
			for i in n:
				var a: float = rr.f() * 6.28
				var d: float = sqrt(rr.f()) * r * 0.8
				var py: float = g0 + r * (0.62 + rr.f() * 0.22)
				var colr = rr.pick(fc)
				var rot := [rr.f(), rr.f(), rr.f()]
				sc.add("ball", S, [x + cos(a) * d, py, z + sin(a) * d], [r * 0.19, r * 0.14, r * 0.19], colr, rot)
		elif kind == "tall":
			var th: float = o.th if o.get("th") != null else 0.9
			S.k.cyl(0.012, 0.018, th, M.t("#6a5040"), [x, g0 + th / 2.0, z], null, 6)
			var balls := [[0, th * 0.78, 0, 1.25], [r * 0.9, th * 0.55, r * 0.3, 0.9], [-r * 0.8, th * 0.62, -r * 0.35, 0.95], [r * 0.2, th * 0.4, -r * 0.8, 0.75]]
			for i in balls.size():
				var bb: Array = balls[i]
				var s: float = bb[3]
				C.shrub(S, x + bb[0], g0 + bb[1] - r * s * 0.5, z + bb[2], {"r": r * 1.1 * s, "h": r * 1.5 * s, "green": greens[i % greens.size()], "seed": pseed + i, "lumps": 0.26})
		elif kind == "succulent":
			for i in 5:
				var px: float = x + (rr.f() - 0.5) * r
				var pz: float = z + (rr.f() - 0.5) * r
				var colr = rr.pick(["#8fb49a", "#a6c49a", "#7fa38a"])
				var rot := [rr.f(), rr.f(), rr.f()]
				sc.add("ball", S, [px, g0 + r * 0.25, pz], [r * 0.35, r * 0.3, r * 0.35], colr, rot)
		elif kind == "grass":
			for i in 9:
				var a: float = rr.f() * 6.28
				var sy: float = r * (1.6 + rr.f())
				var colr = rr.pick(greens)
				var rot := [(rr.f() - 0.5) * 0.6, a, (rr.f() - 0.5) * 0.6]
				sc.add("blade", S, [x + cos(a) * r * 0.3, g0, z + sin(a) * r * 0.3], [0.03, sy, 1], colr, rot)

	## A-frame board (two leaning boards). reg_f / reg_b: atlas regions for the two faces. pos = ground centre.
	func a_frame(S, x: float, y: float, z: float, rotY: float, reg_f, reg_b, o: Dictionary = {}):
		var w: float = o.w if o.get("w") != null else 0.6
		var h: float = o.h if o.get("h") != null else 0.92
		var lean := 0.2
		var gq = S.k.group([x, y, z], rotY)
		var k = ctx.kit(gq)
		var wood = M.wood(o.frame if o.get("frame") != null else "#8a6446")
		var ang := atan2(lean, h)
		for s in [1, -1]:
			var b := T.Group.new()
			b.position = Vector3(0, 0, s * lean)
			b.rotation.x = -s * ang
			gq.add(b)
			var kb = ctx.kit(b)
			kb.box(w, 0.045, 0.03, wood, [0, h - 0.02, 0])
			kb.box(0.045, h, 0.03, wood, [-w / 2.0 + 0.022, h / 2.0, 0])
			kb.box(0.045, h, 0.03, wood, [w / 2.0 - 0.022, h / 2.0, 0])
			kb.box(w, 0.045, 0.03, wood, [0, 0.1, 0])
			kb.box(w - 0.09, h - 0.16, 0.012, M.t("#34403b"), [0, h / 2.0 + 0.05, 0])
			var reg = reg_f if s > 0 else reg_b
			if reg:
				var cm = kb.mesh(GM.region_geo(reg, w - 0.1, h - 0.18), reg.m, [0, h / 2.0 + 0.05, s * 0.008], [0, 0.0 if s > 0 else PI, 0])
				cm.cast_shadow = false
		k.cyl(0.004, 0.004, lean * 1.6, mMetalDark, [0, h * 0.42, 0], [PI / 2.0, 0, 0], 4)
		return gq

	## folding stand sign: metal frame, poster on both sides.
	func stand_sign(S, x: float, y: float, z: float, rotY: float, reg, o: Dictionary = {}):
		var w: float = o.w if o.get("w") != null else 0.5
		var h: float = o.h if o.get("h") != null else 1.0
		var gq = S.k.group([x, y, z], rotY)
		var fr = M.t(o.frame if o.get("frame") != null else "#e8e6df")
		var ang := 0.12
		for s in [1, -1]:
			var b := T.Group.new()
			b.position = Vector3(0, 0, s * 0.06)
			b.rotation.x = -s * ang
			gq.add(b)
			var kb = ctx.kit(b)
			kb.box(w, h, 0.03, fr, [0, h / 2.0 + 0.03, 0])
			if reg:
				var cm = kb.mesh(GM.region_geo(reg, w - 0.06, h - 0.1), reg.m, [0, h / 2.0 + 0.05, s * 0.017], [0, 0.0 if s > 0 else PI, 0])
				cm.cast_shadow = false
		return gq

	## nobori flag on a pole with water-tank base. reg: atlas region (tall).
	func nobori(S, x: float, y: float, z: float, rotY: float, reg, o: Dictionary = {}):
		var w: float = o.w if o.get("w") != null else 0.45
		var h: float = o.h if o.get("h") != null else 1.6
		var pole := h + 0.55
		var gq = S.k.group([x, y, z], rotY)
		var k = ctx.kit(gq)
		k.cyl(0.14, 0.17, 0.26, M.t(o.base if o.get("base") != null else "#cfd2d4"), [0, 0.13, 0], null, 10)
		k.cyl(0.013, 0.013, pole, M.t("#e6e6e2"), [0, 0.26 + pole / 2.0, 0], null, 6)
		k.cyl(0.009, 0.009, w, M.t("#e6e6e2"), [w / 2.0, 0.26 + pole - 0.05, 0], [0, 0, PI / 2.0], 5)
		# gently waving cloth: subdivided plane with a baked wave
		var geo := GM.region_geo(reg, w, h)
		var g2 := Geo.plane(w, h, 6, 1)
		var uv0: T.Attr = geo.attributes.uv
		var uv: T.Attr = g2.attributes.uv
		var pp: T.Attr = g2.attributes.position
		var u0 := minf(uv0.get_x(0), uv0.get_x(1))
		var u1 := maxf(uv0.get_x(0), uv0.get_x(1))
		var v0 := minf(uv0.get_y(0), uv0.get_y(2))
		var v1 := maxf(uv0.get_y(0), uv0.get_y(2))
		for i in uv.count():
			uv.set_xy(i, u0 + uv.get_x(i) * (u1 - u0), v0 + uv.get_y(i) * (v1 - v0))
			var px := pp.get_x(i) + w / 2.0
			pp.set_z(i, sin(px / w * PI * 1.3) * 0.035 * (px / w))
		g2.compute_vertex_normals()
		var flag = k.mesh(g2, ctx.mat.toon("#ffffff", {"map": reg.m.map, "side": "double", "paint": 0.02}), [w / 2.0 + 0.015, 0.26 + pole - 0.08 - h / 2.0, 0])
		flag.cast_shadow = true
		return gq

	## umbrella stand with a couple of umbrellas. pos = bottom centre
	func umbrella_stand(S, x: float, y: float, z: float, rotY: float = 0.0, o: Dictionary = {}):
		var gq = S.k.group([x, y, z], rotY)
		var k = ctx.kit(gq)
		var m = M.t(o.color if o.get("color") != null else "#9aa1a8")
		k.box(0.5, 0.05, 0.22, m, [0, 0.03, 0])
		k.box(0.5, 0.03, 0.22, m, [0, 0.55, 0])
		for sx in [-0.24, 0.24]:
			k.box(0.02, 0.55, 0.2, m, [sx, 0.3, 0])
		var cols: Array = o.umbrellas if o.get("umbrellas") != null else ["#7ea6c9", "#e8e6df", "#d98f9e"]
		for i in cols.size():
			var ux := -0.15 + i * 0.15
			k.cyl(0.035, 0.02, 0.62, M.t(cols[i]), [ux, 0.36, 0.0], [0.08 * (i - 1), 0, 0.1 * (i - 1)], 8)
			k.cyl(0.008, 0.008, 0.25, M.t("#5a4032"), [ux + 0.03 * (i - 1), 0.78, 0.0], null, 4)
		return gq

	## round bistro table (top at y + 0.72). Returns world top centre.
	func bistro_table(S, x: float, y: float, z: float, o: Dictionary = {}) -> Vector3:
		var r: float = o.r if o.get("r") != null else 0.34
		var top: float = o.h if o.get("h") != null else 0.72
		var m_top = o.topMat if o.get("topMat") != null else M.t("#e8e2d6")
		var m_leg = o.legMat if o.get("legMat") != null else M.t("#4b4d52")
		S.k.cyl(r, r, 0.03, m_top, [x, y + top - 0.015, z], null, 20)
		S.k.cyl(r + 0.008, r + 0.008, 0.012, m_leg, [x, y + top - 0.036, z], null, 20)
		S.k.cyl(0.022, 0.022, top - 0.05, m_leg, [x, y + (top - 0.05) / 2.0 + 0.02, z], null, 6)
		S.k.cyl(0.2, 0.24, 0.03, m_leg, [x, y + 0.015, z], null, 12)
		return S.world(x, y + top, z)

	## metal bistro chair facing rotY (+z local forward = seat front). pos = ground
	func bistro_chair(S, x: float, y: float, z: float, rotY: float, o: Dictionary = {}):
		var gq = S.k.group([x, y, z], rotY)
		var k = ctx.kit(gq)
		var m = o.mat if o.get("mat") != null else M.t("#4b4d52")
		var seat = o.seat if o.get("seat") != null else m
		k.cyl(0.19, 0.19, 0.025, seat, [0, 0.45, 0], null, 14)
		for l in [[-0.13, -0.13], [0.13, -0.13], [-0.13, 0.13], [0.13, 0.13]]:
			k.cyl(0.011, 0.011, 0.45, m, [l[0] * 1.08, 0.225, l[1] * 1.08], [l[1] * 0.12, 0, -l[0] * 0.12], 5)
		k.cyl(0.011, 0.011, 0.44, m, [-0.15, 0.66, -0.15], [-0.1, 0, 0], 5)
		k.cyl(0.011, 0.011, 0.44, m, [0.15, 0.66, -0.15], [-0.1, 0, 0], 5)
		var arc := Geo.torus(0.17, 0.012, 4, 12, PI)
		k.mesh(arc, m, [0, 0.8, -0.16], [-0.1, 0, 0])
		k.mesh(arc, m, [0, 0.68, -0.155], [-0.1, 0, 0], [0.95, 0.95, 1])
		k.cyl(0.14, 0.14, 0.008, m, [0, 0.14, 0], null, 12)
		return gq

	## pendant lamp hanging from ceiling y = ceil down to shade bottom at yb.
	func pendant(S, x: float, ceil_y: float, yb: float, z: float, o: Dictionary = {}) -> void:
		var shade = o.shade if o.get("shade") != null else "#3f5a4a"
		ctx.wires.add([S.world(x, ceil_y, z), S.world(x, yb + 0.2, z)], {"width": 0.008, "color": "#3a3640"})
		if o.get("kind") == "globe":
			S.k.sphere(0.13, M.glow("#ffe2b0", 1.25), [x, yb + 0.13, z], 12)
			S.k.cyl(0.03, 0.03, 0.05, M.t("#b08a4a"), [x, yb + 0.27, z], null, 8)
		else:
			S.k.cyl(0.05, 0.19, 0.17, M.t(shade, {"side": "double"}), [x, yb + 0.1, z], null, 14)
			S.k.cyl(0.17, 0.17, 0.005, M.glow("#ffe2b0", 1.35), [x, yb + 0.015, z], null, 14)
			S.k.sphere(0.05, M.glow("#fff0d0", 1.6), [x, yb + 0.05, z], 8)

	## framed window: frame + glass (+ optional mullions / backing). pos = bottom centre on wall plane.
	func window(S, x: float, y: float, z: float, w: float, h: float, o: Dictionary = {}):
		var gq = S.k.group([x, y, z], o.rotY if o.get("rotY") != null else 0.0)
		var k = ctx.kit(gq)
		var ft: float = o.ft if o.get("ft") != null else 0.06
		var fd: float = o.fd if o.get("fd") != null else 0.1
		var fm = o.frameMat if o.get("frameMat") != null else M.wood(o.frame if o.get("frame") != null else "#5a4032")
		k.box(w + ft * 2.0, ft, fd, fm, [0, h + ft / 2.0, 0])
		k.box(w + ft * 2.0, ft, fd, fm, [0, -ft / 2.0, 0])
		k.box(ft, h, fd, fm, [-w / 2.0 - ft / 2.0, h / 2.0, 0])
		k.box(ft, h, fd, fm, [w / 2.0 + ft / 2.0, h / 2.0, 0])
		var cols: int = o.cols if o.get("cols") != null else 1
		var rows: int = o.rows if o.get("rows") != null else 1
		var mt: float = o.mt if o.get("mt") != null else ft * 0.6
		for i in range(1, cols):
			k.box(mt, h, fd * 0.8, fm, [-w / 2.0 + i * w / cols, h / 2.0, 0])
		for j in range(1, rows):
			k.box(w, mt, fd * 0.8, fm, [0, j * h / rows, 0])
		if o.get("transom"):
			k.box(w, mt * 1.2, fd * 0.85, fm, [0, o.transom, 0])
		var gl = k.plane(w, h, o.glass if o.get("glass") != null else M.glass(), [0, h / 2.0, 0.0])
		gl.cast_shadow = false
		gl.receive_shadow = false
		var sill_d: float = o.sillD if o.get("sillD") != null else 0.08
		if o.get("sill") != false:
			k.box(w + ft * 2.0 + 0.08, 0.045, fd + sill_d, o.sillMat if o.get("sillMat") != null else fm, [0, -ft - 0.022, sill_d / 2.0])
		var back_z: float = o.backZ if o.get("backZ") != null else 0.12
		if o.get("back"):
			var b = S.card(o.back, w, h, [0, h / 2.0, -back_z], null, null, k)
			b.receive_shadow = true
		elif o.get("dim"):
			k.plane(w, h, o.dim, [0, h / 2.0, -back_z])
		return gq

	## awning (fixed canvas) on a wall whose outer face is at z = zWall; slopes toward +z.
	func awning(S, o: Dictionary) -> Dictionary:
		var x0: float = o.x0
		var x1: float = o.x1
		var z_wall: float = o.zWall
		var y_top: float = o.yTop
		var depth: float = o.depth
		var drop: float = o.drop
		var w := x1 - x0
		var cx := (x0 + x1) / 2.0
		var lng := sqrt(depth * depth + drop * drop)
		var ang := atan2(drop, depth)
		var sm = o.stripeMat if o.get("stripeMat") != null else M.stripe(o.stripe[0], o.stripe[1], o.n if o.get("n") != null else 4)
		S.ubox(w, 0.03, lng, sm, [cx, y_top - drop / 2.0, z_wall + depth / 2.0], [ang, 0, 0], o.period if o.get("period") != null else 1.0)
		var val_h: float = o.valH if o.get("valH") != null else 0.24
		var vm = o.valMat if o.get("valMat") != null else M.t(o.valance if o.get("valance") != null else o.stripe[0])
		var zf := z_wall + depth
		var yb := y_top - drop
		S.k.box(w + 0.02, val_h, 0.02, vm, [cx, yb - val_h / 2.0 + 0.02, zf])
		if o.get("valReg"):
			S.card(o.valReg, minf(w - 0.1, o.valTextW if o.get("valTextW") != null else w - 0.1), val_h * 0.8, [cx + (o.valTextX if o.get("valTextX") != null else 0.0), yb - val_h / 2.0 + 0.02, zf + 0.012])
		if o.get("scallop") != false:
			S.k.mesh(GM.scallop_geo(w + 0.02, o.scallopW if o.get("scallopW") != null else 0.18), vm, [cx, yb - val_h + 0.02, zf])
		# side cheeks
		var cheek := GM.profile_x([[0, 0], [depth, -drop], [depth, -drop - val_h + 0.02], [0, -0.05]], 0.02)
		for sx in [x0 + 0.01, x1 - 0.01]:
			S.k.mesh(cheek, sm, [sx, y_top, z_wall])
		S.k.cyl(0.012, 0.012, w, M.t("#6d747c"), [cx, yb + 0.01, zf - 0.02], [0, 0, PI / 2.0], 6)
		return {"zf": zf, "yb": yb - val_h}
