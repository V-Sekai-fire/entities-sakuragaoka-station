# The toon ramp (core/ramp/mtoon_ramp.gdshaderinc) against the original's toon material, with tests
# that can fail:
#   formula   each palette ramp variant drawn on a quad at chosen N.L, on both sides of each break of
#             the gradient map and on back faces for the double-sided variants, against the ramp
#             written out here: albedo * (G(N.L) * 2.75 * sun + hemisphere(N.y) * 1.62) / pi, 8-bit
#             sRGB, within one level; the environment's own ambient is pure red, so if any of it
#             reached the ramp the test would fail
#   chart     engine_floor.gd's chart-toon tile, three.js against the port before and after, dE00 per
#             patch in the sun and in the cast shadow (each side's mean <= 1.0, every patch <= 2.0 after);
#             the unlit chart's 8-bit codes (exact after); the tiles b-toon, b-toon-paint and c-shadow
#             (MAD, every pixel and channel, full resolution)
#   controls  engine_floor.gd --ramp-control runs, each of which must fail where it should:
#             step     MToon's step in place of G: the chart's shadow dE00 must come back over the gate
#             nohemi   no hemisphere light: every shadow patch must darken by its own hemisphere term,
#                      the patch's colour times mix(ground, sky, 0.5) * 1.62 / pi (the chart is vertical),
#                      within one 8-bit level and 2 %; the chart must fail its gate
#             nopaint  no hand paint: b-toon-paint must regress (MAD at least 1.5x after's) while
#                      b-toon, which has no paint, stays put
# The contact sheet: per patch, the original | port before | port after, in the sun and in shadow,
# with dE00 (toon-ramp-chart-NN on the desktop, Sheet.publish).
#   godot --path . --resolution 1920x1080 --script tools/toon_ramp_check.gd -- --three=<prefix>
#       --before=<engine floor dir> --after=<dir> [--step=<dir>] [--nohemi=<dir>] [--nopaint=<dir>]
#       [--out=<dir>] [--no-formula]
# <prefix>_<tile>.png are tools/oracle/calib.mjs' renders, <dir>/godot_<tile>.png engine_floor.gd's.
extends SceneTree

const Chart = preload("res://tools/chart_calib.gd")
const Sheet = preload("res://tools/sheet.gd")
const SCENE := "res://tools/oracle/calib_scene.json"
const RAMP := "res://addons/sakuragaoka_station/core/ramp/"
const VARIANTS := ["mtoon_ramp", "mtoon_ramp_cull_off", "mtoon_ramp_cutout", "mtoon_ramp_cutout_cull_off",
		"mtoon_ramp_trans", "mtoon_ramp_trans_cull_off"]
## core/sky.js: the sun, DirectionalLight('#fff0dc', 2.75), and HemisphereLight('#a9b3ee', '#d9c6c8', 1.62)
const SUN := "#fff0dc"
const SUN_I := 2.75
const SKY := "#a9b3ee"
const GROUND := "#d9c6c8"
const HEMI_I := 1.62
const MEAN_MAX := 1.0
const PATCH_MAX := 2.0
const CELL := Vector2i(150, 84)

var _a := {}
var _fails := PackedStringArray()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var eq := a.find("=")
			_a[a.substr(2, eq - 2) if eq > 0 else a.substr(2)] = a.substr(eq + 1) if eq > 0 else "1"
	_run.call_deferred()


func _check(ok: bool, what: String) -> bool:
	print("toon_ramp_check: %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)
	return ok


static func _lin(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


static func _lin8(v: float) -> float:
	var c := v / 255.0
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


## makeGradientMap() as getGradientIrradiance reads it (NEAREST, 16 texels, 8-bit).
static func gradient(dot_nl: float) -> float:
	var i := clampf(floorf((dot_nl * 0.5 + 0.5) * 16.0), 0.0, 15.0)
	return 0.0 if i < 8.0 else (107.0 / 255.0 if i < 9.0 else (204.0 / 255.0 if i < 11.0 else 1.0))


static func hemisphere(up: float) -> Vector3:
	return _lin(Color(GROUND)).lerp(_lin(Color(SKY)), 0.5 * up + 0.5) * HEMI_I / PI


## The toon ramp's linear radiance for a linear albedo, normal n (world) and sun direction s.
static func ramp(albedo: Vector3, n: Vector3, s: Vector3, shadow: float) -> Vector3:
	return albedo * (_lin(Color(SUN)) * SUN_I / PI * gradient(n.dot(s)) * shadow + hemisphere(n.y))


func _run() -> void:
	var res := {}
	if not _a.has("no-formula"):
		res["formula"] = await _formula()
	if _a.has("after"):
		res["chart"] = await _chart()
	var out: String = _a.get("out", "user://toon_ramp_check")
	DirAccess.make_dir_recursive_absolute(out)
	res["fails"] = _fails
	var f := FileAccess.open(out.path_join("toon_ramp_check.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(res, " "))
	f.close()
	print("toon_ramp_check: %s (%d failed)" % ["ALL PASS" if _fails.is_empty() else "FAILED", _fails.size()])
	quit(0 if _fails.is_empty() else 1)


# ----------------------------------------------------------------------------------- formula

func _formula() -> Dictionary:
	var sun_dir := Vector3(-0.776, 0.517, 0.362).normalized()   # world/layout.gd SUN_DIR
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 0, 0)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	get_root().add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(SUN)
	sun.light_energy = SUN_I / PI
	get_root().add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP)
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.make_current()
	var albedo := Color("#b48a62")   # materials.js PALETTE.woodLight
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(albedo)
	var tex := ImageTexture.create_from_image(img)
	var p1 := sun_dir.cross(Vector3.UP).normalized()
	var p2 := sun_dir.cross(p1).normalized()
	var worst := 0
	var n_cases := 0
	var rows := []
	for v in VARIANTS:
		var sm := ShaderMaterial.new()
		sm.shader = load(RAMP + v + ".gdshader")
		sm.set_shader_parameter("_MainTex", tex)
		sm.set_shader_parameter("_ShadeTexture", tex)
		sm.set_shader_parameter("ramp_paint", 0.0)
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(4, 4)
		mi.mesh = q
		mi.material_override = sm
		get_root().add_child(mi)
		for d in [-0.3, 0.001, 0.06, 0.124, 0.126, 0.25, 0.374, 0.376, 0.7, 0.99]:
			for k in [0.0, 0.7]:
				var n: Vector3 = (sun_dir * d + (p1 * cos(k) + p2 * sin(k)) * sqrt(1.0 - d * d)).normalized()
				for back in ([false, true] if v.ends_with("cull_off") else [false]):
					# the quad faces n and the camera looks along -n; turned round, the camera sees its back
					# face, whose flipped normal is n again
					var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT
					var b := Basis.looking_at(-n, up)
					mi.transform = Transform3D(Basis.looking_at(n, up) if back else b, Vector3.ZERO)
					cam.transform = Transform3D(b, n * 3.0)
					for i in 3:
						await process_frame
					await RenderingServer.frame_post_draw
					var px := get_root().get_texture().get_image().get_pixel(get_root().size.x / 2, get_root().size.y / 2)
					var w := ramp(_lin(albedo), n, sun_dir, 1.0)
					var want := Color(w.x, w.y, w.z).linear_to_srgb()
					var d8 := maxi(absi(px.r8 - want.r8), maxi(absi(px.g8 - want.g8), absi(px.b8 - want.b8)))
					worst = maxi(worst, d8)
					n_cases += 1
					rows.append("%s%s N.L %+.3f N.y %+.2f: %d,%d,%d want %d,%d,%d" % [v, " back" if back else "", n.dot(sun_dir), n.y,
							px.r8, px.g8, px.b8, want.r8, want.g8, want.b8])
		mi.queue_free()
	for c in [we, sun, cam]:
		c.queue_free()
	await process_frame
	_check(worst <= 1, "formula: %d renders of the six palette ramp variants (G bands either side of 0, 0.125, 0.375; back faces) within one 8-bit level of the ramp (largest %d)" % [n_cases, worst])
	return {"cases": n_cases, "largest_8bit": worst, "rows": rows}


# ------------------------------------------------------------------------------------- chart

static func _img(path: String):
	return Image.load_from_file(path) if FileAccess.file_exists(path) else null


func _chart() -> Dictionary:
	var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCENE))
	var chart: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + str(scene.get("chart", "tools/calib/chart24.json"))))
	var cam := Camera3D.new()
	cam.fov = 58.0
	cam.near = 0.1
	cam.far = 2500.0
	get_root().add_child(cam)
	cam.make_current()
	var rects := {}
	for t in scene.tiles:
		if t.id in ["chart-toon", "chart-unlit"]:
			var c: Array = t.cam
			cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(c[4]), deg_to_rad(c[3]), 0.0), EULER_ORDER_YXZ), Vector3(c[0], c[1], c[2]))
			rects[t.id] = []
			for ch in t.charts:
				rects[t.id].append(Chart.patch_rects(cam, ch, chart))
	var three: String = _a.get("three", "")
	var runs := {}
	for k in ["before", "after", "step", "nohemi", "nopaint"]:
		if _a.has(k):
			runs[k] = str(_a[k])
	var ti = _img("%s_chart-toon.png" % three)
	if ti == null:
		_check(false, "chart: no three.js render %s_chart-toon.png" % three)
		return {}
	var vals := {"three": [Chart.read(ti, rects["chart-toon"][0]), Chart.read(ti, rects["chart-toon"][1])]}
	var imgs := {"three": ti}
	for k in runs:
		var g = _img(runs[k].path_join("godot_chart-toon.png"))
		if g != null:
			imgs[k] = g
			vals[k] = [Chart.read(g, rects["chart-toon"][0]), Chart.read(g, rects["chart-toon"][1])]
	var res := {"patches": [], "mean": {}, "max": {}, "tiles": {}, "controls": {}}
	var sums := {}
	var maxs := {}
	var n: int = chart.patches.size()
	for i in n:
		var p: Dictionary = chart.patches[i]
		var e := {"no": p.no, "name": p.name}
		for side in 2:
			var sn: String = ["lit", "shadow"][side]
			var a: Vector3 = vals.three[side][i]
			e[sn] = {"three": [a.x, a.y, a.z]}
			for k in vals:
				if k == "three":
					continue
				var b: Vector3 = vals[k][side][i]
				var de := Chart.de2000(Chart.lab(a), Chart.lab(b))
				e[sn][k] = {"rgb": [b.x, b.y, b.z], "de": de}
				sums["%s %s" % [k, sn]] = sums.get("%s %s" % [k, sn], 0.0) + de
				maxs["%s %s" % [k, sn]] = maxf(maxs.get("%s %s" % [k, sn], 0.0), de)
		res.patches.append(e)
	for k in sums:
		res.mean[k] = sums[k] / n
		res.max[k] = maxs[k]
	print("toon_ramp_check: chart-toon dE00 (three.js against the port) mean / max per patch:")
	for k in sums:
		print("toon_ramp_check:   %-16s %6.2f / %6.2f" % [k, res.mean[k], res.max[k]])
	if res.mean.has("after lit"):
		_check(res.mean["after lit"] <= MEAN_MAX and res.max["after lit"] <= PATCH_MAX,
				"chart in the sun after: mean dE00 %.2f <= %.1f, every patch <= %.1f (largest %.2f); before %.2f" % [res.mean["after lit"], MEAN_MAX, PATCH_MAX, res.max["after lit"], res.mean.get("before lit", -1.0)])
		_check(res.mean["after shadow"] <= MEAN_MAX and res.max["after shadow"] <= PATCH_MAX,
				"chart in shadow after: mean dE00 %.2f <= %.1f, every patch <= %.1f (largest %.2f); before %.2f" % [res.mean["after shadow"], MEAN_MAX, PATCH_MAX, res.max["after shadow"], res.mean.get("before shadow", -1.0)])
	# the unlit chart: every patch's 8-bit code, before and after
	var tu = _img("%s_chart-unlit.png" % three)
	for k in ["before", "after"]:
		var g = _img(runs.get(k, "").path_join("godot_chart-unlit.png")) if runs.has(k) else null
		if g == null:
			continue
		var gv := Chart.read(g, rects["chart-unlit"][0])
		var code := 0.0
		var de := 0.0
		for i in n:
			var s8 := Vector3(chart.patches[i].srgb8[0], chart.patches[i].srgb8[1], chart.patches[i].srgb8[2])
			code = maxf(code, maxf(absf(gv[i].x - s8.x), maxf(absf(gv[i].y - s8.y), absf(gv[i].z - s8.z))))
			de = maxf(de, Chart.de2000(Chart.lab(s8), Chart.lab(gv[i])))
		res["unlit_" + k] = {"largest_code_diff": code, "largest_de00": de, "frame_mad": Sheet.mad(g, tu) if tu != null else -1.0}
		if k == "after":
			_check(code == 0.0, "unlit chart after: every patch's 8-bit code equals the chart's (largest difference %.2f, dE00 %.2f)" % [code, de])
	# engine floor tiles
	for t in ["b-toon", "b-toon-paint", "c-shadow", "chart-toon", "d-skyfog", "e-post-off"]:
		var th = _img("%s_%s.png" % [three, t])
		res.tiles[t] = {}
		for k in runs:
			var g = _img(runs[k].path_join("godot_%s.png" % t))
			if th != null and g != null:
				res.tiles[t][k] = Sheet.mad(g, th)
		print("toon_ramp_check: tile %-13s MAD %s" % [t, JSON.stringify(res.tiles[t])])
	for t in ["b-toon", "b-toon-paint", "c-shadow"]:
		if res.tiles[t].has("before") and res.tiles[t].has("after"):
			_check(res.tiles[t].after < res.tiles[t].before, "tile %s: MAD %.2f before -> %.2f after" % [t, res.tiles[t].before, res.tiles[t].after])
	# controls
	if res.mean.has("step shadow"):
		res.controls["step"] = {"lit": res.mean["step lit"], "shadow": res.mean["step shadow"], "b-toon": res.tiles["b-toon"].get("step", -1.0)}
		_check(res.mean["step shadow"] > MEAN_MAX, "CONTROL step (MToon's step for G): the chart's shadow dE00 comes back, mean %.2f > %.1f (lit %.2f: N.L there is 0.856, where both are 1); b-toon MAD %.2f against after's %.2f" % [
				res.mean["step shadow"], MEAN_MAX, res.mean["step lit"], res.tiles["b-toon"].get("step", -1.0), res.tiles["b-toon"].get("after", -1.0)])
	if vals.has("nohemi") and vals.has("after"):
		res.controls["nohemi"] = _darkening(chart, vals, res)
	if res.tiles["b-toon-paint"].has("nopaint") and res.tiles["b-toon-paint"].has("after"):
		var bp: Dictionary = res.tiles["b-toon-paint"]
		var bt: Dictionary = res.tiles["b-toon"]
		res.controls["nopaint"] = {"b-toon-paint": bp.nopaint, "b-toon": bt.get("nopaint", -1.0)}
		_check(bp.nopaint >= 1.5 * bp.after, "CONTROL nopaint: b-toon-paint regresses, MAD %.2f -> %.2f without the paint (>= 1.5x)" % [bp.after, bp.nopaint])
		_check(absf(bt.get("nopaint", 0.0) - bt.get("after", 0.0)) < 0.01, "CONTROL nopaint: b-toon (paint 0) stays at MAD %.2f (%.2f)" % [bt.get("after", -1.0), bt.get("nopaint", -1.0)])
	await _sheet(chart, rects["chart-toon"], imgs, vals, res)
	cam.queue_free()
	return res


## The no-hemisphere control: in the cast shadow the ramp is the hemisphere term alone, so every
## patch darkens by colour * mix(ground, sky, 0.5) * 1.62 / pi (the chart's normal is horizontal).
func _darkening(chart: Dictionary, vals: Dictionary, res: Dictionary) -> Dictionary:
	var h := hemisphere(0.0)
	var worst := 0.0
	var rows := []
	var ok := true
	for i in chart.patches.size():
		var p: Dictionary = chart.patches[i]
		var al := Vector3(_lin8(p.srgb8[0]), _lin8(p.srgb8[1]), _lin8(p.srgb8[2]))
		var pred := al * h
		var a: Vector3 = vals.after[1][i]
		var c: Vector3 = vals.nohemi[1][i]
		var meas := Vector3(_lin8(a.x) - _lin8(c.x), _lin8(a.y) - _lin8(c.y), _lin8(a.z) - _lin8(c.z))
		for k in 3:
			# one 8-bit level at the after code, plus 2 %
			var code: float = a[k]
			var tol := (_lin8(minf(code + 1.0, 255.0)) - _lin8(code)) + 0.02 * pred[k]
			var err := absf(meas[k] - pred[k])
			worst = maxf(worst, err / maxf(tol, 1e-9))
			ok = ok and err <= tol
		rows.append({"no": p.no, "predicted": [pred.x, pred.y, pred.z], "measured": [meas.x, meas.y, meas.z], "nohemi_rgb": [c.x, c.y, c.z]})
	var m: float = res.mean.get("nohemi shadow", 0.0)
	_check(ok, "CONTROL nohemi: every shadow patch darkens by its hemisphere term colour * mix(ground, sky, 0.5) * 1.62 / pi (largest error %.2f of the tolerance, one 8-bit level + 2 %%)" % worst)
	_check(m > MEAN_MAX, "CONTROL nohemi: the chart's shadow dE00 fails the gate, mean %.2f > %.1f" % [m, MEAN_MAX])
	return {"shadow_mean_de": m, "worst_over_tolerance": worst, "patches": rows}


func _sheet(chart: Dictionary, rects: Array, imgs: Dictionary, vals: Dictionary, res: Dictionary) -> void:
	var cols := ["original, sun", "port before", "port after", "original, shadow", "port before", "port after"]
	var rows := []
	for i in chart.patches.size():
		var p: Dictionary = chart.patches[i]
		var e: Dictionary = res.patches[i]
		var cells := []
		for side in 2:
			var sn: String = ["lit", "shadow"][side]
			for k in ["three", "before", "after"]:
				if not imgs.has(k):
					cells.append({"image": null, "label": "(no %s)" % k})
					continue
				var v: Vector3 = vals[k][side][i]
				var label := "%d,%d,%d" % [roundi(v.x), roundi(v.y), roundi(v.z)]
				if k != "three":
					label += "\ndE00 %.2f" % e[sn][k].de
				cells.append({"image": Chart._crop(imgs[k], rects[side][i], CELL), "label": label,
						"mark": Color(0.9, 0.2, 0.2) if k == "after" and e[sn][k].de > PATCH_MAX else null})
		rows.append({"label": "patch %d %s: dE00 sun %.2f -> %.2f, shadow %.2f -> %.2f" % [p.no, p.name,
				e.lit.get("before", {}).get("de", -1.0), e.lit.get("after", {}).get("de", -1.0),
				e.shadow.get("before", {}).get("de", -1.0), e.shadow.get("after", {}).get("de", -1.0)], "cells": cells})
	var c: Dictionary = res.controls
	var tl: Dictionary = res.tiles
	var mad := func(t: String, k: String) -> String: return "%.2f" % tl[t][k] if tl.has(t) and tl[t].has(k) else "-"
	rows.append({"label": "tiles, MAD before -> after: b-toon %s -> %s, b-toon-paint %s -> %s, c-shadow %s -> %s" % [mad.call("b-toon", "before"),
			mad.call("b-toon", "after"), mad.call("b-toon-paint", "before"), mad.call("b-toon-paint", "after"), mad.call("c-shadow", "before"), mad.call("c-shadow", "after")],
			"color": Color(0.7, 0.9, 1.0), "cells": [{"image": null, "label": ("controls: MToon's step, chart dE00 sun %.2f, shadow %.2f; no hemisphere, shadow %.2f (darkening as computed: %s);" +
			"\nno paint, b-toon-paint MAD %s, b-toon %s") % [c.get("step", {}).get("lit", -1.0), c.get("step", {}).get("shadow", -1.0),
			c.get("nohemi", {}).get("shadow_mean_de", -1.0), "yes" if c.get("nohemi", {}).get("worst_over_tolerance", 9.0) <= 1.0 else "NO",
			mad.call("b-toon-paint", "nopaint"), mad.call("b-toon", "nopaint")]}]})
	var title := "Toon ramp, 24-patch chart: dE00 three.js vs port (mean), sun %.2f -> %.2f, shadow %.2f -> %.2f" % [
			res.mean.get("before lit", -1.0), res.mean.get("after lit", -1.0), res.mean.get("before shadow", -1.0), res.mean.get("after shadow", -1.0)]
	var img: Image = await Sheet.render(self, title, cols, rows, CELL)
	var out: String = _a.get("out", "user://toon_ramp_check")
	for path in Sheet.publish(img, out.path_join("toon-ramp-chart-sheet.png"), "toon-ramp-chart"):
		print("toon_ramp_check: saved ", path)
