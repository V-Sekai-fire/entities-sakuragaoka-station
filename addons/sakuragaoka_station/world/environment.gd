# environment.js: base terrain of the whole world, ground colouring, the levee, the river, far
# fields / hills / mountains, wildflowers and weeds, and a small green park.
extends RefCounted

const Common = preload("res://addons/sakuragaoka_station/world/environment/common.gd")
const Textures = preload("res://addons/sakuragaoka_station/world/environment/textures.gd")
const Shaders = preload("res://addons/sakuragaoka_station/world/environment/shaders.gd")
const Terrain = preload("res://addons/sakuragaoka_station/world/environment/terrain.gd")

## Parts still being ported are skipped by name; the gate reports the module against the oracle.
const PARTS := ["terrain", "far", "levee", "river", "park", "flora"]


func build(ctx) -> Dictionary:
	var C = Common.new(ctx.L)
	var tx = Textures.create_env_textures(ctx)
	var env := {"groundAt": Callable(C, "terrain_h"), "common": C}
	ctx.services["environment"] = env
	var forest_mat = Shaders.distant_material(ctx, {"vertexColors": true})
	var terrain := Terrain.build_terrain(ctx, C, tx, forest_mat)
	var far := {}
	var levee := {}
	var river := {}
	var park := {}
	for part in PARTS:
		match part:
			"far": far = load("res://addons/sakuragaoka_station/world/environment/far.gd").build_far(ctx, C, tx)
			"levee": levee = load("res://addons/sakuragaoka_station/world/environment/levee.gd").build_levee(ctx, C, tx)
			"river": river = load("res://addons/sakuragaoka_station/world/environment/water.gd").build_river(ctx, C, tx)
			"park": park = load("res://addons/sakuragaoka_station/world/environment/park.gd").build_park(ctx, C, tx)
	env.merge({
		"nanoEdges": far.get("nanoEdges", []), "isParkMound": park.get("isParkMound"), "parkFlora": park.get("parkFlora"),
		"levee": {"benches": levee.get("benches", []), "lamps": levee.get("lamps", []), "stairs": levee.get("stairs", [])},
		"river": {"waterY": -0.45, "bars": river.get("bars", [])},
	}, true)
	if PARTS.has("flora"):
		load("res://addons/sakuragaoka_station/world/environment/flora.gd").build_flora(ctx, C, tx, env)
	for g in ctx.static_root.children:
		if g.name.begins_with("env-") and g.name != "env-terrain":
			Common.bake_colors(ctx, g)
	return {"terrain": terrain}
