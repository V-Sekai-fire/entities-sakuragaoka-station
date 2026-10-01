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


## src/core/physics.js as far as building uses it: colliders are counted, not simulated.
class Physics extends RefCounted:
	var count := 0

	func addBox(_cx = 0, _cz = 0, _w = 0, _d = 0, _r = 0, _y0 = 0, _y1 = 0): count += 1
	func addAABB(_a = 0, _b = 0, _c = 0, _d = 0, _y0 = 0, _y1 = 0): count += 1
	func addCylinder(_cx = 0, _cz = 0, _r = 0, _y0 = 0, _y1 = 0): count += 1
	func addWalkBox(_cx = 0, _cz = 0, _w = 0, _d = 0, _r = 0, _t = 0, _b = 0): count += 1
	func addWalkRamp(_cx = 0, _cz = 0, _w = 0, _d = 0, _r = 0, _a = 0, _b = 0): count += 1
	func addStairs(_cx = 0, _cz = 0, _w = 0, _d = 0, _r = 0, _a = 0, _b = 0, _n = 0): count += 1
	func addFromObject(_o = null, _p = 0): count += 1
	func addDynamic(_f = null): pass


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
		return t

	func canvas(w: int, h: int) -> Dictionary:
		return {"canvas": {"width": w, "height": h}, "g": null}

	func finish(c, _opts = {}) -> T.Tex:
		return _stub(int(c.canvas.width), int(c.canvas.height))

	func sign(_a = null, _b = null, _c = null, _d = null) -> T.Tex:
		return _stub(256, 64)

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
