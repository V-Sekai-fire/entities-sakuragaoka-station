# The port's sky mask per Hammersley view: the scene with a magenta background, fog and post off, so a
# pixel of exactly (255, 0, 255) shows only sky. Preloads nothing of its own, so it runs in any checkout.
#   godot --path <checkout> --resolution 1920x1080 --script <this file> -- --out=<dir> [--hammersley=8@-1,-11.4]
extends SceneTree

const EYE := 1.52

var _a := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_a[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	var out: String = _a.get("out", "user://sky_mask")
	DirAccess.make_dir_recursive_absolute(out)
	var st: Node3D = load("res://addons/sakuragaoka_station/station.tscn").instantiate()
	if "quality" in st:
		st.quality = _a.get("q", "high")
	get_root().add_child(st)
	await st.built
	var cam := Camera3D.new()
	cam.fov = 58.0
	cam.near = 0.1
	cam.far = 2500.0
	get_root().add_child(cam)
	cam.make_current()
	var we: WorldEnvironment = st.get_node("SkyAndFog")
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(1, 0, 1)
	if we.compositor != null:
		for e in we.compositor.compositor_effects:
			if e != null:
				e.enabled = false
	var layout = load("res://addons/sakuragaoka_station/world/layout.gd").new("")
	var spec: String = _a.get("hammersley", "8@-1,-11.4")
	var at := spec.split("@")[1].split(",")
	var n := int(spec.split("@")[0])
	for i in n:
		var u := float(i) / n
		var v := 0.0
		var f := 0.5
		var k := i
		while k > 0:
			v += (k & 1) * f
			k >>= 1
			f *= 0.5
		u = 2.0 * u if u < 0.25 else 2.0 / 3.0 * u + 1.0 / 3.0
		var pitch := clampf(rad_to_deg(acos(1.0 - 2.0 * u) - PI / 2.0), -85.0, 85.0)
		var x := float(at[0])
		var z := float(at[1])
		cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(v * 360.0), 0.0), EULER_ORDER_YXZ),
				Vector3(x, layout.height_at(x, z) + EYE, z))
		await _frames(12)
		get_root().get_texture().get_image().save_png(out.path_join("mask_%d.png" % i))
	print("sky_mask: %d views, MSAA %d, saved in %s" % [n, get_root().msaa_3d, out])
	quit()
