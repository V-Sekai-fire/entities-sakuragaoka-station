# How far the original's cutout flora still shows: two renders of the original (tools/oracle/calib_inview.mjs,
# with and without --hide env-flora) compared through Kernels.frame_diff inside each distance band's footprint
# of flora instances (their projected bounding circles), so a band's share of changed pixels is its coverage.
#   godot --path . --resolution 1920x1080 --script tools/card_fade.gd -- --with=<prefix> --without=<prefix> --cams=<x,z,yaw,pitch;...>
extends SceneTree

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const BANDS := [0.0, 4.0, 8.0, 16.0, 32.0, 64.0, 128.0, 1e9]
const MAGENTA := 0xff00ff
const EYE := 1.52

var _a := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_a[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	_run.call_deferred()


func _run() -> void:
	var ctx = Ctx.new(1)
	for n in ["environment", "station", "plaza", "sakura"]:
		load("res://addons/sakuragaoka_station/world/%s.gd" % n).new().build(ctx)
	ctx.scene.update_matrix_world(true)
	# every flora instance: world centre and bounding radius
	var pts := []
	var visit := func(o, f):
		if o.is_instanced and str(o.name).begins_with("env-flora"):
			if o.geometry.bounding_box == null:
				o.geometry.compute_bounding_box()
			var bb: AABB = o.geometry.bounding_box if o.geometry.bounding_box is AABB else AABB()
			for i in o.count:
				var xf: Transform3D = o.matrix_world * o.instance_matrix[i]
				var c := xf * bb.get_center()
				pts.append([c, (xf.basis * (bb.size * 0.5)).length()])
		for c in o.children:
			f.call(c, f)
	visit.call(ctx.static_root, visit)
	var cam := Camera3D.new()
	cam.fov = 58.0
	cam.near = 0.1
	cam.far = 2500.0
	get_root().add_child(cam)
	cam.make_current()
	await process_frame
	var layout = load("res://addons/sakuragaoka_station/world/layout.gd").new("")
	var size := Vector2(get_root().size)
	var focal: float = size.y * 0.5 / tan(deg_to_rad(29.0))
	var tot := []
	for b in BANDS.size() - 1:
		tot.append([0, 0, 0])
	var cams: PackedStringArray = str(_a.get("cams", "")).split(";", false)
	print("card_fade: %d flora instances, %d views" % [pts.size(), cams.size()])
	for vi in cams.size():
		var c := Array(cams[vi].split(",")).map(func(x): return float(x))
		cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(c[3]), deg_to_rad(c[2]), 0.0), EULER_ORDER_YXZ),
				Vector3(c[0], layout.height_at(c[0], c[1]) + EYE, c[1]))
		var masks := []
		for b in BANDS.size() - 1:
			var im := Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGB8)
			masks.append(im)
		for p in pts:
			if cam.is_position_behind(p[0]):
				continue
			var d: float = (p[0] - cam.global_position).length()
			var s := cam.unproject_position(p[0])
			var r := maxf(1.0, p[1] / maxf(d, 0.1) * focal)
			if s.x + r < 0 or s.y + r < 0 or s.x - r > size.x or s.y - r > size.y:
				continue
			var b := 0
			while d >= BANDS[b + 1]:
				b += 1
			masks[b].fill_rect(Rect2i(int(s.x - r), int(s.y - r), int(2 * r) + 1, int(2 * r) + 1), Color(1, 0, 1))
		var with_img := Image.load_from_file("%s_%d.png" % [_a.get("with", ""), vi])
		var without_img := Image.load_from_file("%s_%d.png" % [_a.get("without", ""), vi])
		with_img.convert(Image.FORMAT_RGB8)
		without_img.convert(Image.FORMAT_RGB8)
		var line := PackedStringArray()
		for b in BANDS.size() - 1:
			var r := Kernels.frame_diff(with_img.get_data(), without_img.get_data(), masks[b].get_data(), MAGENTA)
			var px: int = r[1] / 3
			tot[b][0] += px
			tot[b][1] += r[6]
			line.append("%d/%d" % [r[6], px])
		print("card_fade: view %d (%s): changed/footprint px per band %s" % [vi, cams[vi], " ".join(line)])
	print("card_fade: band | footprint px | changed px | coverage")
	for b in BANDS.size() - 1:
		print("card_fade: %.0f-%.0f m | %d | %d | %.3f" % [BANDS[b], BANDS[b + 1], tot[b][0], tot[b][1], float(tot[b][1]) / maxf(tot[b][0], 1.0)])
	Kernels.shutdown()
	quit()
