# Development runner: builds the given modules in order on the port's scene graph and prints each
# module's numbers beside the oracle's dev build.
#   godot --headless --path . --script tools/dev_stats.gd -- environment plaza
extends SceneTree

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const Stats = preload("res://addons/sakuragaoka_station/core/stats.gd")


func _initialize() -> void:
	var names := []
	var seed := 1
	var drop := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed = int(a.substr(7))
		elif a.begins_with("--drop-lot="):
			drop = a.substr(11)
		else:
			names.append(a)
	var ref = JSON.parse_string(FileAccess.get_file_as_string("res://tools/reference.json"))
	var ctx = Ctx.new(seed, drop)
	for n in names:
		var before := Stats.snapshot(ctx.scene)
		var t0 := Time.get_ticks_msec()
		var mod = load("res://addons/sakuragaoka_station/world/%s.gd" % n).new()
		mod.build(ctx)
		ctx.scene.update_matrix_world(true)
		var s := Stats.of(Stats.added(ctx.scene, before))
		var r = ref.builds.dev.stats[n]
		var cmp := Stats.compare(s, r)
		print("%-11s %s  %s  meshes %d/%d  verts %d/%d  %d ms" % [n, "ok  " if cmp[0] else "MISS", cmp[1], s.meshes, r.meshes, s.vertices, r.vertices, Time.get_ticks_msec() - t0])
		print("            bounds %s\n            oracle %s" % [str(s.bounds), str(r.bounds)])
		print("            centroid %s oracle %s" % [str(s.centroid), str(r.centroid)])
	quit()
