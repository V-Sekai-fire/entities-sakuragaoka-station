# plaza.js: the station-front plaza. Paving, curbs and tactile paths; the tree pit and ring bench
# around the big sakura (the tree itself is the sakura module's); boards, the bus stop and shelter,
# taxi stand, postbox, phone booth, bicycle racks, flower beds, hedge, bollards, chains, bins, lamps,
# the clock pillar and the monument. Publishes ctx.services.plaza = {benches}.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Textures = preload("res://addons/sakuragaoka_station/world/plaza/textures.gd")
const Signs = preload("res://addons/sakuragaoka_station/world/plaza/signs.gd")
const Ground = preload("res://addons/sakuragaoka_station/world/plaza/ground.gd")
const PlazaTree = preload("res://addons/sakuragaoka_station/world/plaza/tree.gd")
const Furniture = preload("res://addons/sakuragaoka_station/world/plaza/furniture.gd")
const Plants = preload("res://addons/sakuragaoka_station/world/plaza/plants.gd")


## Returns null, or the error that stopped the build (as the original throws).
func build(ctx):
	var L = ctx.L
	var PL: Dictionary = L.PLAZA
	# layout in world coordinates, y = 0 is the plaza. The west part (x < -3) stays low: the hero view
	# looks through it to the level crossing.
	var P := {
		"x0": PL.x0, "x1": PL.x1, "z0": PL.z0, "z1": PL.z1,
		"yPave": 0.02, "curbW": 0.2,
		"tree": {"x": PL.tree.x, "z": PL.tree.z}, "circleR": 3.55,
		"bikeArea": {"x0": 15.9, "x1": 25.35, "z0": -16.4, "z1": -8.3},
		"curbCutsR3": [[-2.0, 2.0], [17.0, 18.6]],
		"curbCutsR2": [[-21.8, -19.8]],
		# tactile blocks [x0, z0, x1, z1, kind]: dots = warning, v / u = guide bars along z / x
		"tactile": [
			[-0.9, -5.8, 0.9, -5.2, "dots"],
			[-0.15, -7.6, 0.15, -5.8, "v"],
			[-0.15, -7.9, 0.15, -7.6, "dots"],
			[0.15, -7.9, 3.75, -7.6, "u"],
			[3.75, -7.9, 4.05, -7.6, "dots"],
			[4.05, -7.9, 7.35, -7.6, "u"],
			[7.35, -8.05, 7.95, -7.45, "dots"],
			[3.75, -19.9, 4.05, -7.9, "v"],
			[3.3, -20.5, 4.5, -19.9, "dots"],
		],
		"mapBoard": {"x": 1.6, "z": -19.2, "rotY": 0.0},
		"tourBoard": {"x": 11.2, "z": -18.9, "rotY": -0.35},
		"noticeBoard": {"x": 24.95, "z": -19.6, "rotY": -PI / 2.0},
		"shelter": {"x": 10.5, "z": -7.2, "w": 3.2},
		"postbox": {"x": -2.9, "z": -6.35, "rotY": 0.0},
		"phone": {"x": 14.3, "z": -17.6, "rotY": -PI / 2.0},
		"bikeSign": {"x": 15.6, "z": -8.05, "rotY": -0.64},
		"clock": {"x": 6.4, "z": -14.6, "rotY": 0.0},
		"monument": {"x": -6.7, "z": -21.4, "rotY": 0.3},
		"fountain": {"x": -0.6, "z": -19.1, "rotY": 0.2},
		"taxiMark": {"x": -7.25, "z": -6.0},
		"planters": [[15.25, -9.2], [15.25, -15.4]],
		"parkBench": {"x": 15.2, "z": -12.3, "rotY": -PI / 2.0, "len": 1.7},
		"nameSign": {"x": 4.8, "z": -6.8, "rotY": 0.0},
		"inlay": {"x": 6.4, "z": -14.6, "d": 3.4},
		"bollards": [[-2.35, -5.62], [-1.2, -5.65], [1.2, -5.65], [2.35, -5.62], [-8.6, -5.75], [16.8, -5.62], [18.8, -5.62], [-8.6, -21.95], [-8.6, -19.65]],
		"chains": [[2.9, 7.2, -5.62], [12.45, 16.5, -5.62], [19.1, 25.2, -5.62]],
		"bins": [{"x": 12.95, "z": -8.2, "rotY": -PI / 2.0}, {"x": -4.9, "z": -19.3, "rotY": 0.35}],
		"lamps": [[5.8, -9.2], [12.6, -12.8], [15.4, -6.5], [17.2, -21.0]],
		"beds": [
			{"x0": -8.6, "z0": -24.8, "x1": -4.8, "z1": -22.5, "edge": "brick", "kind": "tulips", "h": 0.32, "shrubEnds": true},
			{"x0": 2.6, "z0": -7.0, "x1": 7.0, "z1": -5.95, "edge": "concrete", "kind": "tulips", "h": 0.34},
			{"x0": -8.7, "z0": -19.2, "x1": -7.5, "z1": -8.85, "edge": "concrete", "kind": "border", "h": 0.3},
			{"x0": 21.0, "z0": -24.85, "x1": 25.3, "z1": -23.45, "edge": "brick", "kind": "tulips", "h": 0.32},
		],
		"hedge": {"x0": 25.45, "x1": 26.0, "z0": -24.8, "z1": -5.75},
		"grates": [[-4.9, -5.72], [14.45, -5.75], [22.9, -5.75]],
		"manhole": {"x": 11.2, "z": -14.0},
		"patches": [[10.5, -14.5, 2, 3, 0], [-5.5, -9.5, 2, 1, 0], [21.0, -18.5, 3, 2, 1], [6.0, -9.5, 1, 2, 1], [-1.5, -23.0, 1, 1, 0]],
		"stains": [[-3.2, -11.3, 2.2, 1], [-0.6, -14.6, 1.6, 0], [10.4, -6.3, 2.6, 1], [12.9, -8.2, 1.3, 0], [4.0, -19.0, 3.0, 1], [0.2, -6.3, 2.4, 1],
			[20.5, -12.3, 3.2, 1], [-4.9, -19.3, 1.1, 0], [7.8, -6.3, 1.1, 0], [-5.4, -6.4, 1.8, 1], [14.3, -17.6, 1.4, 0], [8.5, -17.5, 2.6, 1]],
		# the sakura module's own tree pits inside the plaza (young south-west tree, forecourt-east tree)
		"otherPits": [{"x": -7.6, "z": -7.8, "h": 0.7}, {"x": 19.5, "z": -22.0, "h": 0.82}],
		"dandelions": [[-8.62, -7.6], [-8.6, -20.3], [25.3, -9.4], [7.3, -5.66], [-4.45, -24.6], [14.72, -22.4], [25.35, -18.3], [-0.4, -5.62], [21.9, -5.66], [-7.2, -5.64], [2.2, -19.95]],
	}
	var fc: Dictionary = L.STATION.forecourt
	P["isBusy"] = func(x: float, z: float) -> bool:
		if x > fc.x0 - 0.1 and x < fc.x1 + 0.1 and z < fc.z1 + 0.1:
			return true
		if sqrt((x - P.tree.x) ** 2 + (z - P.tree.z) ** 2) < P.circleR + 0.3:
			return true
		var b: Dictionary = P.bikeArea
		if x > b.x0 - 0.3 and x < b.x1 + 0.3 and z > b.z0 - 0.3 and z < b.z1 + 0.3:
			return true
		for t in P.tactile:
			if x > t[0] - 0.35 and x < t[2] + 0.35 and z > t[1] - 0.35 and z < t[3] + 0.35:
				return true
		for d in P.beds:
			if x > d.x0 - 0.25 and x < d.x1 + 0.25 and z > d.z0 - 0.25 and z < d.z1 + 0.25:
				return true
		if x > 8.6 and x < 12.4 and z > -7.5 and z < -5.2:
			return true
		for v in L.VENDING:
			if absf(x - v.x) < 0.8 and absf(z - v.z) < 0.8:
				return true
		for t in P.otherPits:
			if absf(x - t.x) < t.h + 0.2 and absf(z - t.z) < t.h + 0.2:
				return true
		return false

	var root := T.Group.new()
	root.name = "plaza"
	ctx.add_static(root)
	var pctx := PlazaCtx.new(ctx)
	var TX: Dictionary = Textures.make_textures(pctx)
	var S: Dictionary = Signs.make_signs(pctx, TX)
	if S.has("error"):
		return S.error
	Ground.build_ground(pctx, root, TX, S, P)
	var ring: Array = PlazaTree.build_tree(pctx, root, TX, P)
	var furn: Dictionary = Furniture.build_furniture(pctx, root, TX, S, P)
	Plants.build_plants(pctx, root, TX, P)
	ctx.services["plaza"] = {"benches": ring + furn.benches}
	return null


## plaza.js's pctx: the module context, with a toon() that quantises `paint` so the core batcher can
## merge more props (untextured ones, and ones on tiled textures).
class PlazaCtx extends RefCounted:
	var base
	var mat

	func _init(c) -> void:
		base = c
		mat = PlazaMat.new(c.mat)

	func _get(p: StringName):
		return base.get(p)

	func rng(key):
		return base.rng(key)

	func kit(parent):
		return base.kit(parent)

	func add(obj):
		return base.add(obj)

	func add_static(obj):
		return base.add_static(obj)

	func no_outline(obj):
		return base.no_outline(obj)

	func no_batch(obj):
		return base.no_batch(obj)

	func on_update(fn: Callable) -> void:
		base.on_update(fn)


class PlazaMat extends RefCounted:
	var base

	func _init(m) -> void:
		base = m

	func toon(c = "#ffffff", o: Dictionary = {}):
		var p: float = o.paint if o.get("paint") != null else 0.05
		if not o.get("map") and not o.get("alphaMap") and not o.get("transparent") and p < 0.08:
			o = o.duplicate()
			o["paint"] = 0.04
		elif o.get("map") and o.map.get("wrap_s") == "repeat" and not o.get("transparent") and p >= 0.03 and p <= 0.07:
			o = o.duplicate()
			o["paint"] = 0.05
		return base.toon(c, o)

	func decal(c = "#ffffff", o: Dictionary = {}):
		return base.decal(c, o)

	func emissive(c = "#ffffff", intensity: float = 1.6, o: Dictionary = {}):
		return base.emissive(c, intensity, o)

	func glass(o: Dictionary = {}):
		return base.glass(o)

	func foliage(c = "#ffffff", map = null, o: Dictionary = {}):
		return base.foliage(c, map, o)

	func shader(kind: String, c = "#ffffff", o: Dictionary = {}):
		return base.shader(kind, c, o)

	func color(c) -> Color:
		return base.color(c)
