# Builds and realizes the station and reports what a renderer draws: batches, solids through CSG
# and the triangles they came out as, single and instanced meshes, total triangles, and times.
# --png=<file> renders the view from the pen's origin on the plaza, (-1, 1.65, -10.3) looking
# north, the way RFD 2293 places the pen.
#   godot --path . --script tools/realize_check.gd -- [--png=out.png] [--modules=environment,plaza]
extends SceneTree

var _png := ""
var _st: Node3D
var _frames := -1
var _t0 := Time.get_ticks_msec()


func _initialize() -> void:
	var mods := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--png="):
			_png = a.substr(6)
		elif a.begins_with("--modules="):
			mods = a.substr(10)
	_st = load("res://addons/sakuragaoka_station/station.tscn").instantiate()
	if mods != "":
		_st.modules = PackedStringArray(mods.split(","))
	_st.built.connect(_on_built)
	get_root().add_child(_st)


func _on_built(s: Dictionary) -> void:
	var draws := 0
	var tris := 0
	for n in _st.find_children("*", "MeshInstance3D", true, false):
		draws += n.mesh.get_surface_count()
		tris += _mesh_tris(n.mesh)
	for n in _st.find_children("*", "MultiMeshInstance3D", true, false):
		draws += 1
		tris += _mesh_tris(n.multimesh.mesh) * n.multimesh.instance_count
	print("realize: modules %s; meshes %d (solids %d through CSG, %d open surfaces, %d single, %d instanced, %d skipped)" % [
			",".join(s.modules), s.meshes, s.solids, s.surfaces, s.single, s.instanced, s.skipped])
	print("realize: geometries %d manifold, %d open; CSG %d triangles in, %d out, %d combiners failed" % [
			s.manifold, s.open, s.csg_in, s.csg_out, s.csg_failed])
	print("realize: %d batches; %d draws, %d triangles; build %d ms, realize %d ms" % [
			s.batches, draws, tris, s.build_ms, s.realize_ms])
	if _png == "":
		quit()
		return
	var cam := Camera3D.new()
	cam.fov = 75.0
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3(-1, 1.65, -10.3), Vector3(-1, 1.2, -20.3), Vector3.UP)
	cam.make_current()
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	get_root().add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -_st.sun_dir, Vector3.UP)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.78, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	get_root().add_child(we)
	_frames = 0


func _process(_dt: float) -> bool:
	if Time.get_ticks_msec() - _t0 > 300000:
		print("realize: FAIL (no result in 300 s)")
		quit(1)
	if _frames < 0:
		return false
	_frames += 1
	if _frames == 4:
		get_root().get_texture().get_image().save_png(_png)
		print("realize: saved %s" % _png)
		quit()
	return false


static func _mesh_tris(m: Mesh) -> int:
	var t := 0
	for i in m.get_surface_count():
		var a := m.surface_get_arrays(i)
		t += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
	return t
