# Builds and realizes the station and reports what a renderer draws: batches, solids through CSG
# and the triangles they came out as, single and instanced meshes, total triangles, and times.
# Cameras follow the three.js original's player (tools/oracle/shot.mjs): "x,z,yaw,pitch" is an eye 1.52 m
# above the ground, "x,y,z,yaw,pitch" a free camera, yaw 0 north (-Z), Euler YXZ, 58 degree vertical
# field of view. --hammersley n@x,z puts n eyes at (x,z) at the sphere Hammersley sequence's angles,
# as shot.mjs does. --original=<prefix> sets each render beside <prefix>_<i>.png and prints the mean
# absolute difference of the two.
#   godot --path . --resolution 1920x1080 --script tools/realize_check.gd -- --shots=<dir>
#       [--hammersley=8@-1,-11.4 | --cams="x,z,yaw,pitch;..."] [--original=<prefix>] [--modules=...]
#       [--q=high|medium|low]   the original's ?q= level (core/quality.gd), default high
extends SceneTree

const Layout = preload("res://addons/sakuragaoka_station/world/layout.gd")
const SlugAtlas = preload("res://addons/sakuragaoka_station/core/slug/atlas.gd")
const Baked = preload("res://addons/sakuragaoka_station/core/slug/baked.gd")
const Pack = preload("res://addons/sakuragaoka_station/core/slug/pack.gd")
const Realize = preload("res://addons/sakuragaoka_station/core/realize.gd")
const SandboxUtil = preload("res://addons/sakuragaoka_station/core/slug/sandbox_util.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const EYE := 1.52

var _out := ""
var _original := ""
var _cams := []
var _st: Node3D
var _cam: Camera3D
var _frames := -1
var _view := 0
var _last := PackedByteArray()
var _t0 := Time.get_ticks_msec()
var _layout = Layout.new("")
var _quality := "high"


func _initialize() -> void:
	var mods := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_out = a.substr(8)
		elif a.begins_with("--original="):
			_original = a.substr(11)
		elif a.begins_with("--modules="):
			mods = a.substr(10)
		elif a.begins_with("--q="):
			_quality = a.substr(4)
		elif a.begins_with("--hammersley="):
			_cams = _hammersley(a.substr(13))
		elif a.begins_with("--cams="):
			for c in a.substr(7).split(";", false):
				_cams.append(PackedFloat64Array(Array(c.split(",")).map(func(x): return float(x))))
	_st = load("res://addons/sakuragaoka_station/station.tscn").instantiate()
	if mods != "":
		_st.modules = PackedStringArray(mods.split(","))
	_st.quality = _quality
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
	print("realize: geometries %d manifold, %d open; CSG %d triangles in, %d out; %d cells kept raw, %d combiners failed" % [
			s.manifold, s.open, s.csg_in, s.csg_out, s.csg_raw, s.csg_failed])
	print("realize: %d palette colours; %d blossom masses; %d alpha-cut cards held (no Slug or mesh form); %d instance tints dropped" % [
			s.colours, s.blob, s.held, s.instance_tints_dropped])
	var atlas = SlugAtlas.shared()
	print("realize: canvas textures: %d surfaces drawn by Slug, %d on the mean-colour fallback; modes mesh %d, slug %d, mean %d" % [
			s.slugged, s.fallback, s.mode_mesh, s.mode_slug, s.mode_mean])
	print("realize: baked %d cards, %d decals, %d triangles, %d palette ramps; %d bakes over budget (%d a decal, %d an object with its instances) went to Slug or the mean; atlas %s; pack %s" % [
			s.baked_cards, s.baked_decals, s.baked_tris, s.ramps, s.decal_capped, Baked.DECAL_TRI_CAP, Realize.BAKE_TRI_BUDGET,
			"%d keys, %d layers" % [atlas.keys.size(), atlas.layer_count] if atlas != null else "none",
			"%s in %d ms %s, binary translation %s" % [Pack.info.get("source", "?"), Pack.info.get("ms", 0), str(Pack.info.get("build", "")),
			"on" if SandboxUtil.translated else "off (no res://bintr/ library)"] if Pack.shared() != null else "none (%s)" % Pack.reason])
	print("realize: %d batches; %d draws, %d triangles; build %d ms, realize %d ms" % [
			s.batches, draws, tris, s.build_ms, s.realize_ms])
	print("realize: quality %s (MSAA %s)" % [_quality, ["off", "2x", "4x", "8x"][get_root().msaa_3d]])
	if _out == "" or _cams.is_empty():
		_teardown()
		quit()
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_cam = Camera3D.new()
	_cam.fov = 58.0
	_cam.near = 0.1
	_cam.far = 2500.0
	get_root().add_child(_cam)
	_cam.make_current()
	_frames = 0


func _process(_dt: float) -> bool:
	if Time.get_ticks_msec() - _t0 > 600000:
		print("realize: FAIL (no result in 600 s)")
		_teardown()
		quit(1)
	if _frames < 0:
		return false
	_frames += 1
	if _frames == 1:
		if _view >= _cams.size():
			_teardown()
			quit()
			return false
		_place(_cams[_view])
	elif _frames == 12:
		var img := get_root().get_texture().get_image()
		var data := img.get_data()
		if data == _last:
			print("realize: FAIL (view %d came out identical to the one before)" % _view)
		_last = data
		var file := _out.path_join("port-view_%d.png" % _view)
		img.save_png(file)
		var line := "realize: view %d %s saved %s" % [_view, str(_cams[_view]), file]
		if _original != "":
			line += _compare(img, "%s_%d.png" % [_original, _view])
		print(line)
		_view += 1
		_frames = 0
	return false


## The station frees its Sandboxes as it leaves the tree; the run frees them first, so nothing is left
## loaded at exit.
func _teardown() -> void:
	Kernels.shutdown()
	Guest.shutdown()


## The original's walking eye or free camera, as player.js sets it.
func _place(c: PackedFloat64Array) -> void:
	var p: Vector3
	var yaw: float
	var pitch: float
	if c.size() == 4:
		p = Vector3(c[0], _layout.height_at(c[0], c[1]) + EYE, c[1])
		yaw = c[2]
		pitch = c[3]
	else:
		p = Vector3(c[0], c[1], c[2])
		yaw = c[3]
		pitch = c[4]
	_cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0), EULER_ORDER_YXZ), p)


## sphere_hammersley_sequence(i, n, remap=True) as [azimuth, elevation] in degrees, pitch clamped to
## the original player's +-85.
static func _hammersley(spec: String) -> Array:
	var parts := spec.split("@")
	var n := int(parts[0])
	var at := parts[1].split(",")
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
		var el := rad_to_deg(acos(1.0 - 2.0 * u) - PI / 2.0)
		out.append(PackedFloat64Array([float(at[0]), float(at[1]), v * 360.0, clampf(el, -85.0, 85.0)]))
	return out


## The two renders side by side at half size, and their mean absolute difference over RGB in [0, 255].
func _compare(port: Image, original_path: String) -> String:
	var orig := Image.load_from_file(original_path)
	if orig == null:
		return "; FAIL (no original at %s)" % original_path
	var w := port.get_width() / 2
	var h := port.get_height() / 2
	var a: Image = port.duplicate()
	var b: Image = orig.duplicate()
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	a.resize(w, h)
	b.resize(w, h)
	var da: PackedByteArray = a.get_data()
	var db: PackedByteArray = b.get_data()
	var sum := 0
	for i in range(0, da.size(), 7):
		sum += absi(da[i] - db[i])
	var mad := float(sum) / float(ceili(da.size() / 7.0))
	var pair := Image.create(w * 2, h, false, Image.FORMAT_RGB8)
	pair.blit_rect(b, Rect2i(0, 0, w, h), Vector2i(0, 0))
	pair.blit_rect(a, Rect2i(0, 0, w, h), Vector2i(w, 0))
	pair.save_png(_out.path_join("compare_%d.png" % _view))
	return "; original | port in compare_%d.png, mean abs diff %.1f" % [_view, mad]


static func _mesh_tris(m: Mesh) -> int:
	var t := 0
	for i in m.get_surface_count():
		var a := m.surface_get_arrays(i)
		t += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
	return t
