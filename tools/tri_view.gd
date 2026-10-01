# Triangles in view per view and per class, read from the engine's own counters (visible primitives
# after frustum culling, colour pass; shadow passes beside them). Each class is realized alone and
# measured at every view; held cutout cards are counted as if drawn, at their source geometry.
#   godot --path . --resolution 1920x1080 --script tools/tri_view.gd -- [--json=<file>]
extends SceneTree

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const RealizeBase = preload("res://addons/sakuragaoka_station/core/realize.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const MODULES := ["environment", "station", "plaza", "sakura"]
const CLASSES := ["architecture", "terrain", "foliage masses", "textured surfaces", "instanced props", "distant", "cutout cards"]
const EYE := 1.52


class Only extends RealizeBase:
	var want := ""
	var draw_held := false
	var held_tris := 0

	static func classify(o, m) -> String:
		if m == null:
			return "architecture"
		var nm := str(m.user_data.get("name", ""))
		if m.user_data.has("distant") or str(o.name).begins_with("env-far") or nm.begins_with("env-far") or str(o.name) == "env-ring":
			return "distant"
		if m.alpha_test > 0.0 and (m.map != null or m.alpha_map != null):
			return "cutout cards"
		if m.user_data.has("sakura") and m.user_data["sakura"].get("band", false):
			return "foliage masses"
		if str(o.name).begins_with("env-terrain") or str(o.name).begins_with("env-river"):
			return "terrain"
		if o.is_instanced:
			return "instanced props"
		if m.map != null or m.alpha_map != null:
			return "textured surfaces"
		return "architecture"

	func _take(o) -> bool:
		return want == "" or classify(o, o.materials()[0]) == want

	## A held card drawn at its source geometry (palette), as if its texture had a drawn form.
	func _as_drawn(o) -> bool:
		var m = o.materials()[0]
		if not draw_held or m == null or not (m.alpha_test > 0.0 and m.map != null):
			return false
		var md := _mode(m)
		return md == "mean" or md == ""

	func _instanced(o) -> void:
		if not _take(o):
			return
		if _as_drawn(o):
			var m = o.materials()[0]
			var t: float = m.alpha_test
			m.alpha_test = 0.0
			super(o)
			m.alpha_test = t
			return
		super(o)

	func _mesh(o, alone: bool) -> void:
		if not _take(o):
			return
		if _as_drawn(o):
			var m = o.materials()[0]
			var t: float = m.alpha_test
			m.alpha_test = 0.0
			super(o, alone)
			m.alpha_test = t
			return
		super(o, alone)


var _a := {}
var _cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_a[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	_run.call_deferred()


static func _hammersley(n: int, x: float, z: float) -> Array:
	var out := []
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
		out.append(["hammersley %d" % i, x, z, v * 360.0, clampf(rad_to_deg(acos(1.0 - 2.0 * u) - PI / 2.0), -85.0, 85.0)])
	return out


static func _views() -> Array:
	var v := _hammersley(8, -1.0, -11.4)
	for yaw in range(0, 360, 30):
		v.append(["eye sweep %d" % yaw, -1.0, -11.4, float(yaw), 0.0])
	v.append_array([["hero", 1.6, 34.0, 4.0, 2.0], ["plaza", 9.5, -9.0, 12.0, 6.0], ["platform", 20.0, -37.6, 95.0, 0.0],
			["crossing", -12.8, -31.5, -8.0, 3.0], ["riverbank", -20.0, -92.8, 160.0, -2.0],
			["long axis north", 0.0, 125.0, 0.0, 0.0], ["long axis south", 0.0, -95.0, 180.0, 0.0],
			["long axis west", 90.0, 0.0, 90.0, 0.0], ["long axis east", -90.0, 0.0, -90.0, 0.0]])
	return v


func _frames(n: int) -> void:
	for i in n:
		await process_frame
	await RenderingServer.frame_post_draw


## Realizes the station's objects of one class (all: "") under a fresh root; returns [root, realize].
func _realize(want: String, draw_held: bool) -> Array:
	var ctx = Ctx.new(1)
	for n in MODULES:
		load("res://addons/sakuragaoka_station/world/%s.gd" % n).new().build(ctx)
	var root := Node3D.new()
	get_root().add_child(root)
	var r := Only.new()
	r.want = want
	r.draw_held = draw_held
	r.realize(ctx, root)
	await process_frame
	await process_frame
	r.finish()
	return [root, r]


func _measure(views: Array, layout) -> Array:
	var out := []
	for v in views:
		_cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(v[4]), deg_to_rad(v[3]), 0.0), EULER_ORDER_YXZ),
				Vector3(v[1], layout.height_at(v[1], v[2]) + EYE, v[2]))
		await _frames(3)
		out.append([get_root().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
				get_root().get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)])
	return out


func _run() -> void:
	var st: Node3D = load("res://addons/sakuragaoka_station/station.tscn").instantiate()
	st.modules = PackedStringArray()
	get_root().add_child(st)
	await st.built
	_cam = Camera3D.new()
	_cam.fov = 58.0
	_cam.near = 0.1
	_cam.far = 2500.0
	get_root().add_child(_cam)
	_cam.make_current()
	var layout = load("res://addons/sakuragaoka_station/world/layout.gd").new("")
	var views := _views()
	var res := {"note": "visible primitives (triangles) per view, the engine's colour-pass and shadow-pass counters", "views": [], "classes": {}}
	for v in views:
		res.views.append({"name": v[0], "x": v[1], "z": v[2], "yaw": v[3], "pitch": v[4]})
	for want in [""] + CLASSES + ["cutout cards (held drawn)"]:
		var held_drawn: bool = want == "cutout cards (held drawn)"
		var rr: Array = await _realize("cutout cards" if held_drawn else want, held_drawn)
		var m := await _measure(views, layout)
		var label: String = "all (as drawn now)" if want == "" else want
		res.classes[label] = m
		var tot: int = 0
		for x in m:
			tot = maxi(tot, x[0])
		print("tri_view: %-28s max %7d in view; %s" % [label, tot, " ".join(PackedStringArray(m.map(func(x): return str(x[0]))))])
		rr[0].queue_free()
		await process_frame
	print("tri_view: views: ", " | ".join(PackedStringArray(views.map(func(v): return str(v[0])))))
	if _a.has("json"):
		var f := FileAccess.open(_a.json, FileAccess.WRITE)
		f.store_string(JSON.stringify(res, " "))
		f.close()
	Kernels.shutdown()
	Guest.shutdown()
	quit()
