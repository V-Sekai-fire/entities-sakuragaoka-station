# The town gate: modules built in the original's town order (src/main.js MODULES) against the oracle's
# town build (tools/reference.json builds.town), so modules ported after the dev four are checked the
# same way gate_station.gd checks those.
#
#   godot --headless --path . --script tools/gate_town.gd -- [--control=seed_2] module ...
#
# Every module before the last named one in town order is built first, so services a module reads
# exist; only the named modules are gated. A module line passes with triangles within 2% of the
# oracle's and every bounding-box coordinate within 0.1 m; meshes and vertices are printed beside it.
extends SceneTree

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const Stats = preload("res://addons/sakuragaoka_station/core/stats.gd")

const TOWN := ["environment", "street", "poles", "railway", "station", "plaza", "shopsA", "shopsB", "houses",
	"sakura", "trains", "crossing", "props", "vehicles", "characters", "petals"]


func _initialize() -> void:
	var control := ""
	var names := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--control="):
			control = a.substr(10)
		elif not a.begins_with("--"):
			names.append(a)
	if control not in ["", "seed_2"] or names.is_empty():
		print("RESULT FAIL  usage: gate_town.gd -- [--control=seed_2] module ...")
		quit(2)
		return
	var ref = JSON.parse_string(FileAccess.get_file_as_string("res://tools/reference.json"))
	var ctx = Ctx.new(2 if control == "seed_2" else 1, "")
	var last := 0
	for n in names:
		last = maxi(last, TOWN.find(n))
	var fails := []
	for i in last + 1:
		var n: String = TOWN[i]
		if not ResourceLoader.exists("res://addons/sakuragaoka_station/world/%s.gd" % n):
			if n in names:
				fails.append("%s (not ported)" % n)
				print("%-11s FAIL  not ported" % n)
			continue
		var before := Stats.snapshot(ctx.scene)
		var t0 := Time.get_ticks_msec()
		var err = load("res://addons/sakuragaoka_station/world/%s.gd" % n).new().build(ctx)
		if not (err is String):
			err = null
		if not (n in names):
			continue
		ctx.scene.update_matrix_world(true)
		var s := Stats.of(Stats.added(ctx.scene, before))
		var r: Dictionary = ref.builds.town.stats[n]
		var cmp := Stats.compare(s, r)
		var ok: bool = cmp[0] and err == null
		print("%-11s %s  %s%s  triangles %d/%d  meshes %d/%d  vertices %d/%d  %.1f s" % [n, "PASS" if ok else "FAIL",
			"build error: %s; " % err if err != null else "", cmp[1], s.triangles, r.triangles, s.meshes, r.meshes,
			s.vertices, r.vertices, (Time.get_ticks_msec() - t0) / 1000.0])
		if not ok:
			fails.append(n)
	print("RESULT %s" % ("PASS  %d modules within 2%% triangles and 0.1 m bounds" % names.size() if fails.is_empty() else "FAIL  " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)
