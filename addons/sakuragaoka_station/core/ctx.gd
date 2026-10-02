# src/core/ctx.js: the context handed to every world module's build(ctx). Static scenery goes under
# static_root (merged later by core/batch.gd), animated or interactive objects under dynamic_root.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")
const Materials = preload("res://addons/sakuragaoka_station/core/materials.gd")
const Layout = preload("res://addons/sakuragaoka_station/world/layout.gd")

var L
var layout
var mat
var tex
var geo = Geo
var wires
var physics
var palette := Materials.PALETTE
var shared := {}
var sun_dir: Vector3
var services := {}
var static_root := T.Group.new()
var dynamic_root := T.Group.new()
var scene := T.Group.new()
var time := 0.0
var player := {"position": Vector3.ZERO}
var quality := {"name": "high", "pixelRatio": 1, "msaa": 4, "shadowMap": 4096, "shadowSize": 75, "petals": 1}
var seed := 1
var cache := Geo.Cache.new()
var _updates: Array = []
var LAYER_NO_OUTLINE := Materials.LAYER_NO_OUTLINE


func _init(world_seed: int = 1, drop_lot: String = "") -> void:
	seed = world_seed
	L = Layout.new(drop_lot)
	layout = L
	static_root.name = "static"
	dynamic_root.name = "dynamic"
	scene.add(static_root, dynamic_root)
	sun_dir = Vector3(L.SUN_DIR[0], L.SUN_DIR[1], L.SUN_DIR[2]).normalized()
	shared = {"uTime": 0.0, "uWind": Vector2(0.9, 0.35), "uSunDir": sun_dir, "uGust": 0.5}
	mat = Materials.new(shared)
	tex = Textures.new()
	wires = Geo.Wires.new()
	physics = Physics.new()


## Static scenery, merged by material after every module is built.
func add_static(obj):
	static_root.add(obj)
	return obj


## Animated or interactive objects, never merged.
func add(obj):
	obj.traverse(func(o): o.user_data["dynamic"] = true)
	dynamic_root.add(obj)
	return obj


func on_update(fn: Callable) -> void:
	_updates.append(fn)


func no_outline(obj):
	obj.traverse(func(o): o.layer = LAYER_NO_OUTLINE)
	return obj


func no_batch(obj):
	obj.traverse(func(o): o.user_data["noBatch"] = true)
	return obj


func rng(key) -> RefCounted:
	return Rng.make(key, seed)


func kit(parent) -> Geo.Kit:
	return Geo.Kit.new(parent, cache)


## src/core/physics.js's colliders, kept as primitives for the MuJoCo guest (station coordinates,
## y up). A row is [type, cx, cy, cz, sx, sy, sz, qw, qx, qy, qz, mocap]: boxes are half extents,
## cylinders are radius and half height about local y. Walk tops and ramps keep their walkable top.
class Physics extends RefCounted:
	const STEP_HEIGHT := 0.45
	const STRIDE := 12
	enum { BOX, CYLINDER, WALK, RAMP }
	## The guest's primitive types: walkable boxes (walk tops, ramps) are ground, in geom group 1.
	enum { GUEST_BOX, GUEST_CYLINDER, GUEST_WALK }
	const WALK_DEPTH := 0.5
	const HF_CELL := 0.25

	var prims := PackedFloat64Array()
	var items: Array = []
	var dynamic: Array = []
	var count: int:
		get:
			return prims.size() / STRIDE

	## item is physics.js's own record: [type, cx, cz, hw, hd, rotY, r, y0, y1, top, yA, yB].
	func _row(type: int, c: Vector3, half: Vector3, q: Quaternion, item: Array):
		var shape: int = GUEST_CYLINDER if type == CYLINDER else (GUEST_WALK if type == WALK or type == RAMP else GUEST_BOX)
		prims.append_array([shape, c.x, c.y, c.z, half.x, half.y, half.z, q.w, q.x, q.y, q.z, 0.0])
		items.append(item)
		return count - 1

	func addBox(cx = 0.0, cz = 0.0, w = 0.0, d = 0.0, rotY = 0.0, y0 = -50.0, y1 = 200.0):
		return _row(BOX, Vector3(cx, (y0 + y1) / 2.0, cz), Vector3(w / 2.0, (y1 - y0) / 2.0, d / 2.0),
				Quaternion(Vector3.UP, rotY), ["box", cx, cz, w / 2.0, d / 2.0, rotY, null, y0, y1, null, null, null])

	func addAABB(minx = 0.0, minz = 0.0, maxx = 0.0, maxz = 0.0, y0 = -50.0, y1 = 200.0):
		return addBox((minx + maxx) / 2.0, (minz + maxz) / 2.0, maxx - minx, maxz - minz, 0.0, y0, y1)

	func addCylinder(cx = 0.0, cz = 0.0, r = 0.0, y0 = -50.0, y1 = 200.0):
		return _row(CYLINDER, Vector3(cx, (y0 + y1) / 2.0, cz), Vector3(r, (y1 - y0) / 2.0, 0.0), Quaternion.IDENTITY,
				["cyl", cx, cz, null, null, null, r, y0, y1, null, null, null])

	## Solid from bottom to its walkable top, as in physics.js; the walker's band starts at the step
	## height, so a top within a step never blocks.
	func addWalkBox(cx = 0.0, cz = 0.0, w = 0.0, d = 0.0, rotY = 0.0, topY = 0.0, bottom = -50.0):
		var depth: float = topY - bottom
		return _row(WALK, Vector3(cx, topY - depth / 2.0, cz), Vector3(w / 2.0, depth / 2.0, d / 2.0),
				Quaternion(Vector3.UP, rotY), ["walk", cx, cz, w / 2.0, d / 2.0, rotY, null, bottom, null, topY, null, null])

	## Local z runs from yA at -d/2 to yB at +d/2: a slab pitched about its local x axis.
	func addWalkRamp(cx = 0.0, cz = 0.0, w = 0.0, d = 0.0, rotY = 0.0, yA = 0.0, yB = 0.0):
		var pitch: float = atan2(yB - yA, d)
		var length: float = sqrt(d * d + (yB - yA) * (yB - yA))
		var q := Quaternion(Vector3.UP, rotY) * Quaternion(Vector3.RIGHT, -pitch)
		var down: Vector3 = q * Vector3(0.0, -WALK_DEPTH / 2.0, 0.0)
		return _row(RAMP, Vector3(cx, (yA + yB) / 2.0, cz) + down, Vector3(w / 2.0, WALK_DEPTH / 2.0, length / 2.0), q,
				["ramp", cx, cz, w / 2.0, d / 2.0, rotY, null, minf(yA, yB) - 50.0, null, null, yA, yB])

	func addStairs(cx = 0.0, cz = 0.0, w = 0.0, d = 0.0, rotY = 0.0, y0 = 0.0, y1 = 0.0, n = 1):
		var c: float = cos(rotY)
		var s: float = sin(rotY)
		for i in n:
			var lz: float = -d / 2.0 + d * (i + 0.5) / n
			addWalkBox(cx + lz * s, cz + lz * c, w, d / n, rotY, y0 + (y1 - y0) * (i + 1) / n)

	func addFromObject(o = null, pad = 0.0):
		if o == null or not o.has_method("world_aabb"):
			return null
		var b: AABB = o.world_aabb()
		if b.size == Vector3.ZERO:
			return null
		return addAABB(b.position.x - pad, b.position.z - pad, b.end.x + pad, b.end.z + pad, b.position.y, b.end.y)

	func addDynamic(fn = null):
		if fn != null:
			dynamic.append(fn)

	## Each dynamic collider becomes a mocap box; its slot count is fixed by the first call.
	func dynamic_boxes() -> Array:
		var out: Array = []
		for fn in dynamic:
			out.append_array(fn.call())
		return out

	## The terrain as metres, rows along z and columns along x over [x0, z0, x1, z1].
	func height_field(height_at: Callable, rect: Array, cell: float) -> Dictionary:
		var ncol: int = int(ceil((rect[2] - rect[0]) / cell)) + 1
		var nrow: int = int(ceil((rect[3] - rect[1]) / cell)) + 1
		var h := PackedFloat64Array()
		h.resize(nrow * ncol)
		for r in nrow:
			for c in ncol:
				h[r * ncol + c] = height_at.call(rect[0] + c * cell, rect[1] + r * cell)
		return {"heights": h, "nrow": nrow, "ncol": ncol,
				"rect": [rect[0], rect[1], rect[0] + (ncol - 1) * cell, rect[1] + (nrow - 1) * cell]}


## src/core/textures.js stand-in: the port draws no canvases (textured signs are blank), so a map
## is a sized stub. measure() is check.mjs's stub metric, since the oracle sized text with it.
class Textures extends RefCounted:
	var FONTS := {"sans": "sans", "serif": "serif", "round": "round", "hand": "hand", "brush": "brush", "en": "en"}
	var pixels := 0
	var _n := 0
	var _keyed := {}

	func _stub(w: int, h: int) -> T.Tex:
		var t := T.Tex.new()
		_n += 1
		t.uuid = "tex%d" % _n
		t.width = w
		t.height = h
		pixels += w * h
		return t

	## opts.key returns the same texture for the same key; opts.repeat tiles it, as textures.js does.
	func draw(w: int, h: int, _fn = null, opts = {}) -> T.Tex:
		var key = opts.get("key")
		if key != null and _keyed.has(key):
			return _keyed[key]
		var t := _stub(w, h)
		if opts.get("repeat") != null:
			t.wrap_s = "repeat"
			t.wrap_t = "repeat"
			t.repeat = Vector2(opts.repeat[0], opts.repeat[1])
		if key != null:
			_keyed[key] = t
			t.user_data["key"] = key
		return t

	func canvas(w: int, h: int) -> Dictionary:
		return {"canvas": {"width": w, "height": h}, "g": null}

	func finish(c, _opts = {}) -> T.Tex:
		return _stub(int(c.canvas.width), int(c.canvas.height))

	func sign(opts = null, _b = null, _c = null, _d = null) -> T.Tex:
		var t := _stub(256, 64)
		if opts is Dictionary:
			t.user_data["sign"] = opts
		return t

	static func measure(text: String, size: float) -> float:
		return text.length() * size * 0.92

	## A bag whose every key is a texture stand-in (nested bags for groups such as tx.fields).
	func bag() -> TexBag:
		return TexBag.new(self)


class TexBag extends RefCounted:
	var _tex
	var _m := {}

	func _init(t) -> void:
		_tex = t

	func _get(p: StringName):
		if not _m.has(p):
			_m[p] = _tex._stub(256, 256)
		return _m[p]

	func sub(name: String) -> TexBag:
		if not _m.has(name):
			_m[name] = TexBag.new(_tex)
		return _m[name]
