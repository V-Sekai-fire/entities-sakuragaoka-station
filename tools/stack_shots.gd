# Port renders under post-stack toggles, for tools/sky_seam.gd. Builds the station once
# (--modules=none is the sky alone) and renders every camera set under each configuration, as
# <out>/<config>/<set>_<i>.png, so a toggle's effect is one directory apart. Sets: the sphere Hammersley views
# (realize_check.gd's) and a turntable. The mask configuration is tools/sky_mask.gd's: magenta sky, post off.
#   godot --path . --resolution 1920x1080 --script tools/stack_shots.gd -- --out=<dir> [--modules=none]
#       [--hammersley=8@-1,-11.4] [--turntable=24@5,20,45] [--sets=hammersley,turntable] [--configs=base,...]
#       [--shader=<path>]
extends SceneTree

const RC = preload("res://tools/realize_check.gd")
const Layout = preload("res://addons/sakuragaoka_station/world/layout.gd")
const Quality = preload("res://addons/sakuragaoka_station/core/quality.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const EYE := 1.52
const CONFIGS := ["base", "composite_off", "fog_off", "post_off", "bloom_off", "outline_off", "grade_off",
		"msaa_off", "q_medium", "q_low", "sky_realtime", "sky_quality", "radiance_32", "radiance_2048", "debanding", "mask"]

var _a := {}
var _st: Node3D
var _cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_a[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	_st = load("res://addons/sakuragaoka_station/station.tscn").instantiate()
	if _a.has("modules"):
		_st.modules = PackedStringArray(_a.modules.split(","))
	_st.built.connect(func(_s): _run.call_deferred())
	get_root().add_child(_st)


func _sets() -> Dictionary:
	var spec: String = _a.get("hammersley", "8@-1,-11.4")
	var at := spec.split("@")[1].split(",")
	var x := float(at[0])
	var z := float(at[1])
	var y := Layout.new("").height_at(x, z) + EYE
	var out := {"hammersley": [], "turntable": []}
	for c in RC._hammersley(spec):
		out.hammersley.append(Vector3(c[2], c[3], y))
	var t: String = _a.get("turntable", "24@5,20,45")
	var n := int(t.split("@")[0])
	for p in t.split("@")[1].split(","):
		for i in n:
			out.turntable.append(Vector3(360.0 * i / n, float(p), y))
	return {"at": Vector3(x, y, z), "sets": out}


func _apply(cfg: String, we: WorldEnvironment, fx: Array, defaults: Dictionary) -> void:
	var env := we.environment
	var vp := get_root()
	Quality.apply(vp, _st.quality)
	env.sky.process_mode = defaults.process_mode
	env.sky.radiance_size = defaults.radiance_size
	vp.use_debanding = false
	env.background_mode = Environment.BG_SKY
	for e in fx:
		e.enabled = true
	var comp = fx[1]
	for k in ["outline", "grade", "bloom", "glow"]:
		comp.set(k, defaults[k])
	match cfg:
		"composite_off":
			comp.enabled = false
		"fog_off":
			fx[0].enabled = false
		"post_off":
			for e in fx:
				e.enabled = false
		"bloom_off":
			comp.bloom = 0.0
			comp.glow = 0.0
		"outline_off":
			comp.outline = 0.0
		"grade_off":
			comp.grade = 0.0
		"msaa_off":
			vp.msaa_3d = Viewport.MSAA_DISABLED
		"q_medium", "q_low":
			Quality.apply(vp, cfg.substr(2))
		"sky_realtime":
			env.sky.process_mode = Sky.PROCESS_MODE_REALTIME
		"sky_quality":
			env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
		"radiance_32":
			env.sky.radiance_size = Sky.RADIANCE_SIZE_32
		"radiance_2048":
			env.sky.radiance_size = Sky.RADIANCE_SIZE_2048
		"debanding":
			vp.use_debanding = true
		"mask":
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(1, 0, 1)
			for e in fx:
				e.enabled = false


func _run() -> void:
	var out: String = _a.get("out", "user://stack_shots")
	var configs: PackedStringArray = PackedStringArray(_a.get("configs", "base").split(","))
	var we: WorldEnvironment = _st.get_node("SkyAndFog")
	if _a.has("shader"):
		var sh := Shader.new()
		sh.code = FileAccess.get_file_as_string(_a.shader)
		we.environment.sky.sky_material.shader = sh
	var fx: Array = we.compositor.compositor_effects
	var comp = fx[1]
	var defaults := {"process_mode": we.environment.sky.process_mode, "radiance_size": we.environment.sky.radiance_size,
			"outline": comp.outline, "grade": comp.grade, "bloom": comp.bloom, "glow": comp.glow}
	var s := _sets()
	_cam = Camera3D.new()
	_cam.fov = 58.0
	_cam.near = 0.1
	_cam.far = 2500.0
	get_root().add_child(_cam)
	_cam.make_current()
	var manifest := {"at": [s.at.x, s.at.y, s.at.z], "modules": ",".join(_st.stats.get("modules", [])), "sets": {}}
	for k in s.sets:
		manifest.sets[k] = s.sets[k].map(func(v): return [v.x, v.y])
	DirAccess.make_dir_recursive_absolute(out)
	var f := FileAccess.open(out.path_join("cameras.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, " "))
	f.close()
	var last := PackedByteArray()
	var failed := 0
	for cfg in configs:
		if not cfg in CONFIGS:
			print("stack_shots: FAIL unknown config ", cfg)
			failed += 1
			continue
		_apply(cfg, we, fx, defaults)
		DirAccess.make_dir_recursive_absolute(out.path_join(cfg))
		for set_name in _a.get("sets", "hammersley,turntable").split(","):
			var cams: Array = s.sets[set_name]
			for i in cams.size():
				var c: Vector3 = cams[i]
				_cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(c.y), deg_to_rad(c.x), 0.0), EULER_ORDER_YXZ), s.at)
				for k in 12:
					await process_frame
				await RenderingServer.frame_post_draw
				var img := get_root().get_texture().get_image()
				if img.get_data() == last:
					print("stack_shots: FAIL %s %s %d came out identical to the frame before" % [cfg, set_name, i])
					failed += 1
				last = img.get_data()
				img.save_png(out.path_join(cfg).path_join("%s_%d.png" % [set_name, i]))
		print("stack_shots: %s done (MSAA %d, sky process mode %d, radiance %d)" % [cfg, get_root().msaa_3d,
				we.environment.sky.process_mode, we.environment.sky.radiance_size])
	Kernels.shutdown()
	Guest.shutdown()
	print("stack_shots: %s, %d configs in %s" % ["FAIL" if failed else "PASS", configs.size(), out])
	quit(1 if failed else 0)
