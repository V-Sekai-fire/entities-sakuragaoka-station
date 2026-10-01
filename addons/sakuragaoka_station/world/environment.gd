# environment.js: base terrain of the whole world, ground colouring, the levee, the river, far
# fields / hills / mountains, wildflowers and weeds, and a small green park.
extends RefCounted

const Common = preload("res://addons/sakuragaoka_station/world/environment/common.gd")
const Textures = preload("res://addons/sakuragaoka_station/world/environment/textures.gd")
const Shaders = preload("res://addons/sakuragaoka_station/world/environment/shaders.gd")
const Terrain = preload("res://addons/sakuragaoka_station/world/environment/terrain.gd")
const Far = preload("res://addons/sakuragaoka_station/world/environment/far.gd")
const Levee = preload("res://addons/sakuragaoka_station/world/environment/levee.gd")
const Water = preload("res://addons/sakuragaoka_station/world/environment/water.gd")
const Park = preload("res://addons/sakuragaoka_station/world/environment/park.gd")
const Flora = preload("res://addons/sakuragaoka_station/world/environment/flora.gd")


## Returns {terrain}, as the original does.
func build(ctx) -> Dictionary:
	var C = Common.new(ctx.L)
	var tx = Textures.create_env_textures(ctx)
	var env := {"groundAt": Callable(C, "terrain_h"), "common": C}
	ctx.services["environment"] = env
	# near hills: painted forest crowns with valley mist
	var forest_mat = Shaders.distant_material(ctx, {"vertexColors": true})
	var terrain := Terrain.build_terrain(ctx, C, tx, forest_mat)
	var far: Dictionary = Far.build_far(ctx, C, tx)
	var levee: Dictionary = Levee.build_levee(ctx, C, tx)
	var river: Dictionary = Water.build_river(ctx, C, tx)
	var park: Dictionary = Park.build_park(ctx, C, tx)
	env.merge({
		"nanoEdges": far.get("nanoEdges", []), "isParkMound": park.get("isParkMound"), "parkFlora": park.get("parkFlora"),
		"levee": {"benches": levee.get("benches", []), "lamps": levee.get("lamps", []), "stairs": levee.get("stairs", [])},
		"river": {"waterY": -0.45, "bars": river.get("bars", [])},
	}, true)
	Flora.build_flora(ctx, C, tx, env)
	# one shared vertex-coloured material for all plain props (fewer materials, fewer draw calls)
	for g in ctx.static_root.children:
		if g.name.begins_with("env-") and g.name != "env-terrain":
			Common.bake_colors(ctx, g)
	return {"terrain": terrain}
