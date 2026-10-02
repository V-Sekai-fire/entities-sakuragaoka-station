# One module against the oracle's build of the same module list (tools/reference.mjs --build=...):
# triangles within 2% and every bounding-box coordinate within 0.1 m.
#   godot --headless --path . --script tools/module_check.gd -- <reference.json> <build> [module ...]
# Builds every module of the build in its order and checks the named ones (all, if none named).
extends SceneTree

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const Stats = preload("res://addons/sakuragaoka_station/core/stats.gd")

const TRI_TOL := 0.02
const BOX_TOL := 0.1


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var ref = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var b: Dictionary = ref.builds[a[1]]
	var want := a.slice(2)
	var ctx = Ctx.new(1, "")
	var fails := 0
	for n in b.modules:
		var before := Stats.snapshot(ctx.scene)
		var t0 := Time.get_ticks_msec()
		var err = load("res://addons/sakuragaoka_station/world/%s.gd" % n).new().build(ctx)
		if not (err is String):
			err = null
		ctx.scene.update_matrix_world(true)
		if not want.is_empty() and not want.has(n):
			continue
		var s := Stats.of(Stats.added(ctx.scene, before))
		var r: Dictionary = b.stats[n]
		var rt := float(r.triangles)
		var dt: float = (s.triangles - rt) / maxf(rt, 1.0)
		var ok := absf(dt) <= TRI_TOL and err == null
		var worst := 0.0
		var where := ""
		if s.bounds != null and r.bounds != null:
			for side in ["min", "max"]:
				for i in 3:
					var d := absf(float(s.bounds[side][i]) - float(r.bounds[side][i]))
					if d > worst:
						worst = d
						where = "%s.%s" % [side, "xyz"[i]]
		else:
			ok = false
		ok = ok and worst <= BOX_TOL
		fails += 0 if ok else 1
		print("%-11s %s  triangles %d / %d (%+.2f%%)  meshes %d / %d  bounds worst %.4f m %s  %s  %.1f s" % [n, "PASS" if ok else "FAIL",
			s.triangles, rt, dt * 100.0, s.meshes, r.meshes, worst, where, ("error: %s" % err) if err != null else "", (Time.get_ticks_msec() - t0) / 1000.0])
	print("RESULT %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
