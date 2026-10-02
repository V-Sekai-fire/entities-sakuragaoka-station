# The collider gate: every collider the port's modules register, against the original's own
# physics.items (tools/colliders_reference.json, read from window.__ctx.physics at seed 1).
#
#   godot --headless --path . --script tools/gate_colliders.gd -- [--build=dev|town] [--control=drop_one|shift]
#
# PASS when the port registers the same colliders in the same order, every field within 1e-4, and the
# terrain height field (HF_CELL cells over WORLD.play) stays within 20 mm of layout.height_at.
# Controls (each must FAIL): --control=drop_one skips the 100th call; --control=shift moves one 5 cm.
extends SceneTree

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const TOL := 1e-4
const FIELDS := ["type", "cx", "cz", "hw", "hd", "rotY", "r", "y0", "y1", "top", "yA", "yB"]


func _initialize() -> void:
	var build := "dev"
	var control := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--build="):
			build = a.substr(8)
		elif a.begins_with("--control="):
			control = a.substr(10)
	var ref = JSON.parse_string(FileAccess.get_file_as_string("res://tools/colliders_reference.json"))
	var want: Dictionary = ref.builds[build]
	var ctx = Ctx.new(1, "")
	for n in want.modules:
		var err = load("res://addons/sakuragaoka_station/world/%s.gd" % n).new().build(ctx)
		if err is String:
			print("RESULT FAIL  %s failed to build: %s" % [n, err])
			quit(1)
			return
	var got: Array = ctx.physics.items.duplicate(true)
	if control == "drop_one":
		got.remove_at(99)
	elif control == "shift":
		got[99][1] = float(got[99][1]) + 0.05
	var bad := _first_mismatch(got, want.items)
	var line := "%d colliders / original %d, %d dynamic / original %d" % [got.size(), want.count, ctx.physics.dynamic.size(), want.dynamic]
	var hf_mm := _height_field_error(ctx)
	var ok: bool = bad == "" and got.size() == int(want.count) and ctx.physics.dynamic.size() == int(want.dynamic) and hf_mm <= 20.0
	print("gate_colliders  build %s  control %s" % [build, control if control != "" else "none"])
	print("height field  worst %.2f mm against layout.height_at over 4096 points (limit 20 mm, under a nickel at 21.2 mm)" % hf_mm)
	print("RESULT %s  %s%s" % ["PASS" if ok else "FAIL", line, "" if bad == "" else "  first mismatch: " + bad])
	quit(0 if ok else 1)


func _first_mismatch(got: Array, want: Array) -> String:
	for i in mini(got.size(), want.size()):
		for f in FIELDS.size():
			var g = got[i][f]
			var w = want[i][f]
			if (g == null) != (w == null):
				return "#%d %s %s / original %s" % [i, FIELDS[f], g, w]
			if g is String or w is String:
				if str(g) != str(w):
					return "#%d %s %s / original %s" % [i, FIELDS[f], g, w]
			elif g != null and absf(float(g) - float(w)) > TOL:
				return "#%d %s %.6f / original %.6f" % [i, FIELDS[f], float(g), float(w)]
	if got.size() != want.size():
		return "#%d missing" % mini(got.size(), want.size())
	return ""


## The worst bilinear error of the height field against the exact ground, in mm.
func _height_field_error(ctx) -> float:
	var p: Dictionary = ctx.L.WORLD.play
	var hf: Dictionary = ctx.physics.height_field(ctx.L.height_at, [p.x0, p.z0, p.x1, p.z1], ctx.physics.HF_CELL)
	var rect: Array = hf.rect
	var ncol: int = hf.ncol
	var worst := 0.0
	var r := RandomNumberGenerator.new()
	r.seed = 1
	for i in 4096:
		var x: float = r.randf_range(rect[0], rect[2])
		var z: float = r.randf_range(rect[1], rect[3])
		var fx: float = (x - rect[0]) / ctx.physics.HF_CELL
		var fz: float = (z - rect[1]) / ctx.physics.HF_CELL
		var c0: int = mini(int(fx), ncol - 2)
		var r0: int = mini(int(fz), hf.nrow - 2)
		var tx: float = fx - c0
		var tz: float = fz - r0
		var h: PackedFloat64Array = hf.heights
		var a: float = lerpf(h[r0 * ncol + c0], h[r0 * ncol + c0 + 1], tx)
		var b: float = lerpf(h[(r0 + 1) * ncol + c0], h[(r0 + 1) * ncol + c0 + 1], tx)
		worst = maxf(worst, absf(lerpf(a, b, tz) - ctx.L.height_at(x, z)) * 1000.0)
	return worst
