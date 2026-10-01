# GPU time of the alpha-cut foliage cards (Slug cutout variants): each view is timed by the engine's
# own GPU timer with the cards hidden, shown without casting, and shown casting, in interleaved blocks
# whose spread is the noise floor; their screen share is Kernels.frame_diff of the shown and hidden frames.
#   godot --path . --resolution 1920x1080 --script tools/card_cost.gd -- [--json=<file>] [--frames=40] [--rounds=3]
extends SceneTree

const TriView = preload("res://tools/tri_view.gd")
const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const PLAY := Vector2(-1.0, -11.4)
const EYE := 1.52
const STATES := ["hidden", "shown, no shadow", "shown"]

var _a := {}
var _st: Node3D
var _cam: Camera3D
var _cards := []
var _rid: RID


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_a[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_st = load("res://addons/sakuragaoka_station/station.tscn").instantiate()
	get_root().add_child(_st)
	await _st.built
	_rid = get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	_cam = Camera3D.new()
	_cam.fov = 58.0
	_cam.near = 0.1
	_cam.far = 2500.0
	get_root().add_child(_cam)
	_cam.make_current()
	var mixed := _find_cards()
	var tris := 0
	for n in _cards:
		tris += _tris(n)
	print("card_cost: %d card nodes, %d triangles; %d of them also draw other surfaces" % [_cards.size(), tris, mixed])
	if _cards.is_empty():
		print("card_cost: FAIL no Slug cutout nodes")
		_finish(1)
		return
	var layout = load("res://addons/sakuragaoka_station/world/layout.gd").new("")
	var views := []
	for v in TriView._views():
		views.append([v[0], Vector3(v[1], layout.height_at(v[1], v[2]) + EYE, v[2]), v[3], v[4]])
	views.append_array(_close_ups(layout))
	var frames := int(_a.get("frames", "40"))
	var rounds := int(_a.get("rounds", "3"))
	var res := {"note": "GPU ms per frame (median over blocks of frames) with the cards hidden, shown without casting, and shown; floor = spread of the repeated blocks of one state",
			"card_nodes": _cards.size(), "card_triangles": tris, "frames": frames, "rounds": rounds, "views": []}
	await _control(views[0])
	for v in views:
		var r := await _view(v, frames, rounds)
		res.views.append(r)
		print("card_cost: %-26s cover %5.1f%%  GPU hidden %6.2f  no-shadow %6.2f  shown %6.2f ms  cards %+6.2f (colour %+6.2f, shadow %+6.2f)  floor %.2f" % [
				r.name, r.cover * 100.0, r.gpu[0], r.gpu[1], r.gpu[2], r.gpu[2] - r.gpu[0], r.gpu[1] - r.gpu[0], r.gpu[2] - r.gpu[1], r.floor])
	if _a.has("json"):
		var f := FileAccess.open(_a.json, FileAccess.WRITE)
		f.store_string(JSON.stringify(res, " "))
		f.close()
	_finish(0)


func _finish(code: int) -> void:
	Kernels.shutdown()
	Guest.shutdown()
	quit(code)


func _find_cards() -> int:
	var mixed := 0
	for n in _st.find_children("*", "GeometryInstance3D", true, false):
		var mesh: Mesh = n.mesh if n is MeshInstance3D else (n.multimesh.mesh if n is MultiMeshInstance3D and n.multimesh != null else null)
		if mesh == null:
			continue
		var hit := 0
		for s in mesh.get_surface_count():
			var mat = n.material_override if n.material_override != null else mesh.surface_get_material(s)
			var path: String = mat.shader.resource_path if mat is ShaderMaterial and mat.shader != null else ""
			if "/core/slug/" in path and "_cutout" in path:
				hit += 1
		if hit > 0:
			_cards.append(n)
			mixed += 1 if hit < mesh.get_surface_count() else 0
	return mixed


static func _tris(n: GeometryInstance3D) -> int:
	var mesh: Mesh = n.mesh if n is MeshInstance3D else n.multimesh.mesh
	var k: int = n.multimesh.instance_count if n is MultiMeshInstance3D else 1
	var t := 0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		t += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
	return t * k


## Beside and under the crowns nearest the play area: the eye r + 1.5 m out from the crown's centre
## toward the play area, and under its edge looking up at 55 degrees.
func _close_ups(layout) -> Array:
	var ctx = Ctx.new(1)
	for n in TriView.MODULES:
		load("res://addons/sakuragaoka_station/world/%s.gd" % n).new().build(ctx)
	var trees: Array = ctx.services.get("sakura", {}).get("trees", []).duplicate()
	trees.sort_custom(func(p, q): return Vector2(p.x, p.z).distance_to(PLAY) < Vector2(q.x, q.z).distance_to(PLAY))
	var out := []
	for t in trees.slice(0, 4):
		var c := Vector3(t.x, t.y, t.z)
		var d := (PLAY - Vector2(t.x, t.z)).normalized()
		var side := c + Vector3(d.x, 0.0, d.y) * (float(t.r) + 1.5)
		var yaw := rad_to_deg(atan2(d.x, d.y))
		out.append(["beside %s" % t.id, side, yaw, 0.0])
		var under := c + Vector3(d.x, 0.0, d.y) * float(t.r) * 0.5
		under.y = layout.height_at(under.x, under.z) + EYE
		out.append(["under %s" % t.id, under, yaw, 55.0])
	return out


func _place(v: Array) -> void:
	_cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(v[3]), deg_to_rad(v[2]), 0.0), EULER_ORDER_YXZ), v[1])


func _set_state(s: int) -> void:
	for n in _cards:
		n.visible = s > 0
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if s == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _frame() -> PackedByteArray:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img.get_data()


func _block(n: int) -> float:
	for i in 4:
		await process_frame
	var ms := PackedFloat64Array()
	for i in n:
		await process_frame
		ms.append(RenderingServer.viewport_get_measured_render_time_gpu(_rid))
	ms.sort()
	return ms[ms.size() / 2]


func _view(v: Array, frames: int, rounds: int) -> Dictionary:
	_place(v)
	_set_state(2)
	for i in 20:
		await process_frame
	var shown := await _frame()
	_set_state(0)
	for i in 3:
		await process_frame
	var hidden := await _frame()
	var d := Kernels.frame_diff(shown, hidden, PackedByteArray(), 0)
	var med := [PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array()]
	for r in rounds:
		for s in STATES.size():
			_set_state(s)
			med[s].append(await _block(frames))
	_set_state(2)
	var gpu := []
	var spread := 0.0
	for s in STATES.size():
		var m: PackedFloat64Array = med[s].duplicate()
		m.sort()
		gpu.append(m[m.size() / 2])
		spread = maxf(spread, m[m.size() - 1] - m[0])
	return {"name": v[0], "eye": [v[1].x, v[1].y, v[1].z], "yaw": v[2], "pitch": v[3], "cover": float(d[4]) / float(shown.size() / 3),
			"gpu": gpu, "blocks": med.map(func(x): return Array(x)), "floor": spread}


## The toggle is what moves the frame: the cards hidden twice give identical frames, shown and hidden differ.
func _control(v: Array) -> void:
	_place(v)
	_set_state(0)
	for i in 20:
		await process_frame
	var a := await _frame()
	for i in 3:
		await process_frame
	var b := await _frame()
	var same := Kernels.frame_diff(a, b, PackedByteArray(), 0)
	print("card_cost: control %s hidden twice: %d pixels differ (want 0)" % [v[0], same[4]])
	_set_state(2)
