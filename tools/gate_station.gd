# The station gate: the port against the original's oracle (tools/reference.json, from
# V-Sekai-fire/sakuragaoka-station tools/reference.mjs at seed 1, t = 0).
#
#   godot --headless --path . --script tools/gate_station.gd -- [--control=drop_lot|seed_2] [module ...]
#
# Checks, one line each, then one RESULT line (exit 0 on PASS, 1 on FAIL):
#   rng         the mulberry32 vectors (seed 1, "env-far", "2:env-far"; 16 outputs each) match
#   generators  the three.js r170 geometry generator cases match (tools/gencheck_*.{json,txt})
#   <module>    environment, station, plaza, sakura built in the oracle's dev order: triangles within
#               2% of the oracle's and every bounding-box coordinate within 0.1 m
# Controls (each must FAIL): --control=drop_lot removes lot W1 from the layout (the plaza's map board
# labels it, so the plaza build fails as the original's does); --control=seed_2 builds at world seed 2
# against the seed-1 oracle.
extends SceneTree

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const Stats = preload("res://addons/sakuragaoka_station/core/stats.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")
const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const G = preload("res://addons/sakuragaoka_station/core/geo.gd")

const MODULES := ["environment", "station", "plaza", "sakura"]
const TRI_TOL := 0.02
const BOX_TOL := 0.1
const DROP_LOT := "W1"


func _initialize() -> void:
	var control := ""
	var names := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--control="):
			control = a.substr(10)
		elif not a.begins_with("--"):
			names.append(a)
	if names.is_empty():
		names = MODULES.duplicate()
	if control not in ["", "drop_lot", "seed_2"]:
		print("RESULT FAIL  unknown control %s (drop_lot | seed_2)" % control)
		quit(2)
		return
	var seed := 2 if control == "seed_2" else 1
	var drop := DROP_LOT if control == "drop_lot" else ""
	var ref = JSON.parse_string(FileAccess.get_file_as_string("res://tools/reference.json"))
	var precision := "double" if OS.has_feature("double") else "single"
	print("gate_station  Godot %s (%s precision)  oracle %s (three %s, seed %d, t %d)  control %s" % [Engine.get_version_info().string, precision,
		str(ref.source).substr(0, 7), ref.three, ref.seed, ref.t, control if control != "" else "none"])
	var fails := []

	var rng := _check_rng(ref)
	print("%-11s %s  %s" % ["rng", "PASS" if rng[0] else "FAIL", rng[1]])
	if not rng[0]:
		fails.append("rng")
	var gen := _check_generators()
	print("%-11s %s  %s" % ["generators", "PASS" if gen[0] else "FAIL", gen[1]])
	if not gen[0]:
		fails.append("generators")

	var ctx = Ctx.new(seed, drop)
	var passed := 0
	for n in names:
		var before := Stats.snapshot(ctx.scene)
		var t0 := Time.get_ticks_msec()
		# a module's build returns an error String when it fails (the original throws); anything else is its result
		var err = load("res://addons/sakuragaoka_station/world/%s.gd" % n).new().build(ctx)
		if not (err is String):
			err = null
		ctx.scene.update_matrix_world(true)
		var s := Stats.of(Stats.added(ctx.scene, before))
		var r: Dictionary = ref.builds.dev.stats[n]
		var cmp := _compare(s, r)
		var ok: bool = cmp[0] and err == null
		var why: String = ("build error: %s; " % err if err != null else "") + cmp[1]
		print("%-11s %s  %s  meshes %d/%d  %.1f s" % [n, "PASS" if ok else "FAIL", why, s.meshes, r.meshes, (Time.get_ticks_msec() - t0) / 1000.0])
		if ok:
			passed += 1
		else:
			fails.append("%s (%s)" % [n, why.split(";")[0] if err != null else cmp[2]])
	var ctl := "" if control == "" else ("  [control drop_lot: lot %s removed]" % DROP_LOT if control == "drop_lot" else "  [control seed_2: world seed 2 against the seed-1 oracle]")
	if fails.is_empty():
		print("RESULT PASS  rng, generators and %d/%d modules within %d%% triangles and %.1f m bounds (%s precision)%s" % [passed, names.size(), int(TRI_TOL * 100), BOX_TOL, precision, ctl])
	else:
		print("RESULT FAIL  %s (%s precision)%s" % [", ".join(fails), precision, ctl])
	quit(0 if fails.is_empty() else 1)


## [ok, line, short reason] for a module's numbers against the oracle's.
func _compare(got: Dictionary, ref: Dictionary) -> Array:
	var rt := float(ref.triangles)
	var dt: float = (got.triangles - rt) / maxf(rt, 1.0)
	var line := "triangles %d / oracle %d (%+.2f%%)" % [got.triangles, rt, dt * 100.0]
	var ok := absf(dt) <= TRI_TOL
	var short := "" if ok else "triangles %+.2f%%" % (dt * 100.0)
	if (got.bounds == null) != (ref.bounds == null):
		line += "  bounds %s / oracle %s" % ["present" if got.bounds != null else "none", "present" if ref.bounds != null else "none"]
		if short == "":
			short = "no bounds"
		return [false, line, short]
	if got.bounds != null:
		var worst := 0.0
		var where := ""
		for side in ["min", "max"]:
			for i in 3:
				var d := absf(float(got.bounds[side][i]) - float(ref.bounds[side][i]))
				if d > worst:
					worst = d
					where = "%s.%s" % [side, "xyz"[i]]
		if worst > BOX_TOL:
			line += "  bounds %s off by %.3f m" % [where, worst]
			ok = false
			if short == "":
				short = "bounds %s off by %.3f m" % [where, worst]
		else:
			line += "  bounds within %.4f m" % worst
	return [ok, line, short]


## The mulberry32 vectors: compared as 32-bit integers (k = v * 2^32), since parsing the JSON's
## decimals is not exact in the last bit.
func _check_rng(ref) -> Array:
	var n := 0
	var bad := []
	for key in ref.rng:
		var r = Rng.make(int(key) if key == "1" else key)
		for i in 16:
			n += 1
			if roundi(r.f() * 4294967296.0) != roundi(float(ref.rng[key][i]) * 4294967296.0):
				bad.append("%s[%d]" % [key, i])
	if bad.is_empty():
		return [true, "mulberry32 %d/%d outputs match (keys %s)" % [n, n, ", ".join(ref.rng.keys())]]
	return [false, "mulberry32 %d/%d mismatched: %s" % [bad.size(), n, ", ".join(bad)]]


## The three.js r170 generators the modules use, case by case: vertices, triangles, bounds and
## position sums (tools/gencheck_expected.txt is three.js's output for tools/gencheck_cases.json).
func _check_generators() -> Array:
	var cases = JSON.parse_string(FileAccess.get_file_as_string("res://tools/gencheck_cases.json"))
	var expected := FileAccess.get_file_as_string("res://tools/gencheck_expected.txt").strip_edges().split("\n")
	var bad := []
	for ci in cases.size():
		var c = cases[ci]
		var g := _make(c)
		g.compute_bounding_box()
		var p := g.position()
		var sx := 0.0
		var sy := 0.0
		var sz := 0.0
		for i in p.count():
			sx += p.get_x(i)
			sy += p.get_y(i)
			sz += p.get_z(i)
		var b: AABB = g.bounding_box
		var e := b.end
		var tri = g.triangle_count()
		var line := "%s | %d | %s | %.4f,%.4f,%.4f,%.4f,%.4f,%.4f | %.3f,%.3f,%.3f" % [c[0], p.count(), str(int(tri)) if tri == int(tri) else str(tri),
			b.position.x, b.position.y, b.position.z, e.x, e.y, e.z, sx, sy, sz]
		if line.replace("-0.000", "0.000") != expected[ci].replace("-0.000", "0.000"):
			bad.append("%d:%s" % [ci, c[0]])
	if bad.is_empty():
		return [true, "three.js r170 generators %d/%d cases match" % [cases.size(), cases.size()]]
	return [false, "three.js r170 generators %d/%d mismatched: %s" % [bad.size(), cases.size(), ", ".join(bad)]]


func _make(c: Array) -> T.Geometry:
	var k: String = c[0]
	var a = c[1]
	match k:
		"box":
			return G.box(a[0], a[1], a[2], a[3], a[4], a[5])
		"plane":
			return G.plane(a[0], a[1], a[2], a[3])
		"circle":
			return G.circle(a[0], a[1], a[2], a[3])
		"cylinder":
			return G.cylinder(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7])
		"sphere":
			return G.sphere(a[0], a[1], a[2], a[3], a[4], a[5], a[6])
		"torus":
			return G.torus(a[0], a[1], a[2], a[3], a[4])
		"icosahedron":
			return G.icosahedron(a[0], a[1])
		"lathe":
			var pts := []
			for p in a[0]:
				pts.append(Vector2(p[0], p[1]))
			return G.lathe(pts, a[1], a[2], a[3])
		"rounded_box":
			return G.rounded_box(a[0], a[1], a[2], a[3], a[4])
		"extrude":
			return G.extrude(a[0], a[1], a[2])
		"extrude_spline":
			var pts: Array = a[0].duplicate()
			pts.append(a[0][0])
			return G.extrude_shape(G.shape(G.spline_points(pts, a[1])), {"depth": 0.24, "bevelEnabled": true, "bevelThickness": 0.06, "bevelSize": 0.05, "bevelSegments": 4})
		"shape_geometry":
			return G.shape_geometry(G.shape(a[0], a[1]), 24)
		"tube":
			var pts := []
			for p in a[0]:
				pts.append(Vector3(p[0], p[1], p[2]))
			return G.tube_catmull(pts, true, a[1], a[2], a[3], true)
		"merge_vertices":
			var g := _make([a[0], a[1]])
			g.delete_attribute("uv")
			g.delete_attribute("normal")
			return G.merge_vertices(g, a[2])
		"merge_geometries":
			return G.merge_geometries([G.box(1, 1, 1), G.box(2, 1, 1, 2, 1, 1).translate(3, 0, 0), G.box(1, 3, 1)], false)
	return T.Geometry.new()
