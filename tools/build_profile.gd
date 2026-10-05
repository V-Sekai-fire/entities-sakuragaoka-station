# Times each environment step and the other world modules at seed 1 (STATION_BUILD=gd for the GDScript path).
#   godot --headless --path . --script res://tools/build_profile.gd
extends SceneTree

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const P := "res://addons/sakuragaoka_station/world/environment/"
const Common = preload(P + "common.gd")
const Textures = preload(P + "textures.gd")
const Shaders = preload(P + "shaders.gd")
const Terrain = preload(P + "terrain.gd")
const Far = preload(P + "far.gd")
const Levee = preload(P + "levee.gd")
const Water = preload(P + "water.gd")
const Park = preload(P + "park.gd")
const Flora = preload(P + "flora.gd")

var t := 0


func lap(label: String) -> void:
	var now := Time.get_ticks_usec()
	print("%-12s %8.1f ms" % [label, (now - t) / 1000.0])
	t = Time.get_ticks_usec()


func _initialize() -> void:
	t = Time.get_ticks_usec()
	var ctx = Ctx.new(1)
	lap("ctx")
	var C = Common.new(ctx.L)
	var tx = Textures.create_env_textures(ctx)
	var env := {"groundAt": Callable(C, "terrain_h"), "common": C}
	ctx.services["environment"] = env
	var forest_mat = Shaders.distant_material(ctx, {"vertexColors": true})
	lap("env-setup")
	Terrain.build_terrain(ctx, C, tx, forest_mat)
	lap("terrain")
	var far: Dictionary = Far.build_far(ctx, C, tx)
	lap("far")
	var levee: Dictionary = Levee.build_levee(ctx, C, tx)
	lap("levee")
	var river: Dictionary = Water.build_river(ctx, C, tx)
	lap("river")
	var park: Dictionary = Park.build_park(ctx, C, tx)
	lap("park")
	env.merge({"nanoEdges": far.get("nanoEdges", []), "isParkMound": park.get("isParkMound"), "parkFlora": park.get("parkFlora"),
		"levee": {"benches": levee.get("benches", []), "lamps": levee.get("lamps", []), "stairs": levee.get("stairs", [])},
		"river": {"waterY": -0.45, "bars": river.get("bars", [])}}, true)
	Flora.build_flora(ctx, C, tx, env)
	lap("flora")
	for g in ctx.static_root.children:
		if g.name.begins_with("env-") and g.name != "env-terrain":
			Common.bake_colors(ctx, g)
	lap("bake_colors")
	for n in ["station", "plaza", "sakura"]:
		load("res://addons/sakuragaoka_station/world/%s.gd" % n).new().build(ctx)
		lap(n)
	quit()
