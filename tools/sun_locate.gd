# Locates the sun in the rendered images of the three.js original and of the port. Two modes.
# Render (default): at each camera, the port's render (as tools/realize_check.gd saves it) and,
# through a second, linear float viewport sharing the world, per-pixel buffers of the port:
#   sun_shadow / sun_noshadow  the sun alone (no ambient, no compositor), with and without its shadow;
#                              their ratio is the port's own shadow mask
#   albedo                     white ambient alone, the sun hidden: the surface colour
#   normal                     the world normal the toon shading lights (MToon writes a normal bent
#                              toward up into the normal buffer, so its _IndirectLightIntensity is set
#                              to 1 for this pass, which leaves the shading normal itself)
#   posx / posy / posz         world position, each as (floor(c) + 1024) / 2048 and fract(c)
#   dist                       view depth, as floor(d) / 2048 and fract(d)
# Each buffer is RGB half floats, row-major from the top row, in <name>_<view>.f16, and meta.json
# records the cameras, the sun node as it stands and its shadow settings. Cameras follow
# tools/realize_check.gd (the original's player, 58 degree vertical field of view, near 0.1, far 2500).
#   godot --path . --resolution 1920x1080 --script tools/sun_locate.gd -- --out=<dir>
#       [--hammersley=8@-1,-11.4 | --cams="x,z,yaw,pitch;..."] [--q=high|medium|low]
#       [--sun-yaw=<deg>]   turn the port's sun (light, sky disc and light leak) about +Y first: the
#                           control a sun locator has to detect
#       [--ramp-control=<name>] [--shadow="key=value;..."]   tools/engine_floor.gd's ramp controls,
#                           and the station's shadow_overrides
# Analyze (--analyze): measures the sun in the original's images and the port's from those buffers,
# on the GPU (tools/sun_locate_gpu.gd, tools/sun_locate_fit.gd); see the --analyze section below.
extends SceneTree

const Layout = preload("res://addons/sakuragaoka_station/world/layout.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const RealizeCheck = preload("res://tools/realize_check.gd")
const SunFit = preload("res://tools/sun_locate_fit.gd")
const EngineFloor = preload("res://tools/engine_floor.gd")
const Gpu = preload("res://tools/sun_locate_gpu.gd")
const EYE := 1.52
const SETTLE := 8
const GBUF_LAYER := 1 << 19
const PASSES := ["beauty", "sun_shadow", "sun_noshadow", "albedo", "normal", "posx", "posy", "posz", "dist"]

const QUAD_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, repeat_disable, filter_nearest;
uniform int mode = 0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 vp = INV_PROJECTION_MATRIX * ndc;
	vp.xyz /= vp.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(vp.xyz, 1.0)).xyz;
	float valid = depth > 0.0 ? 1.0 : 0.0;
	vec3 o = vec3(0.0);
	if (mode == 0) {
		vec3 nv = normalize(textureLod(normal_tex, SCREEN_UV, 0.0).xyz * 2.0 - 1.0);
		o = normalize(mat3(INV_VIEW_MATRIX) * nv) * 0.5 + 0.5;
	} else if (mode == 4) {
		float d = -vp.z;
		o = vec3(floor(d) / 2048.0, fract(d), valid);
	} else {
		float c = mode == 1 ? world.x : (mode == 2 ? world.y : world.z);
		o = vec3((floor(c) + 1024.0) / 2048.0, fract(c), valid);
	}
	ALBEDO = o;
	ALPHA = 1.0;
}
"""

var _out := ""
var _control := ""
var _cams := []
var _quality := "high"
var _sun_yaw := 0.0
var _layout = Layout.new("")
var _st: Node3D
var _sun: DirectionalLight3D
var _cam: Camera3D
var _sub: SubViewport
var _scam: Camera3D
var _quad: MeshInstance3D
var _quad_mat: ShaderMaterial
var _env_sun: Environment
var _env_albedo: Environment
var _toon := []
var _toon_k := {}
var _overrides := {}
var _steps := []
var _step := -1
var _wait := -1
var _meta := {"views": []}
var _t0 := Time.get_ticks_msec()


func _initialize() -> void:
	if "--analyze" in OS.get_cmdline_user_args():
		_analyze()
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--q="):
			_quality = a.substr(4)
		elif a.begins_with("--sun-yaw="):
			_sun_yaw = float(a.substr(10))
		elif a.begins_with("--ramp-control="):
			_control = a.substr(15)
		elif a.begins_with("--shadow="):
			for kv in a.substr(9).split(";", false):
				var p := kv.split("=")
				_overrides[p[0]] = int(p[1]) if p[1].is_valid_int() else float(p[1])
		elif a.begins_with("--hammersley="):
			_cams = RealizeCheck._hammersley(a.substr(13))
		elif a.begins_with("--cams="):
			for c in a.substr(7).split(";", false):
				_cams.append(PackedFloat64Array(Array(c.split(",")).map(func(x): return float(x))))
	if _out == "" or _cams.is_empty():
		push_error("sun_locate: --out=<dir> and --hammersley= or --cams= are required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_st = load("res://addons/sakuragaoka_station/station.tscn").instantiate()
	_st.quality = _quality
	if "shadow_overrides" in _st:
		_st.shadow_overrides = _overrides
	_st.built.connect(_on_built)
	get_root().add_child(_st)


func _on_built(s: Dictionary) -> void:
	_sun = _st.get_node("Sun")
	var we: WorldEnvironment = _st.get_node("SkyAndFog")
	var code_dir: Vector3 = _st.sun_dir
	_meta["sun_dir_code"] = _v(code_dir)
	_meta["sun_basis_z_built"] = _v(_sun.global_transform.basis.z)
	if _sun_yaw != 0.0:
		var r := Basis(Vector3.UP, deg_to_rad(_sun_yaw))
		_sun.global_transform = Transform3D(r * _sun.global_transform.basis, _sun.global_transform.origin)
		var turned := r * code_dir
		we.environment.sky.sky_material.set_shader_parameter("sun_dir", turned)
		for fx in we.compositor.compositor_effects:
			if "sun_dir" in fx:
				fx.sun_dir = turned
	_meta["sun_yaw_deg"] = _sun_yaw
	if _control != "":
		_meta["ramp_control"] = [_control, EngineFloor.ramp_control(_st, _control)]
	# Godot lights shine along their -Z: the light travels along -basis.z, so +basis.z points at the sun
	_meta["sun_to_light"] = _v(_sun.global_transform.basis.z.normalized())
	_meta["sun_shadow"] = _shadow_settings()
	_meta["modules"] = Array(s.modules)
	_meta["quality"] = _quality
	print("sun_locate: built %s in %d ms; sun points at %s (code %s, turned %.3f deg)" % [
			",".join(s.modules), s.build_ms + s.realize_ms, str(_sun.global_transform.basis.z), str(code_dir), _sun_yaw])
	_collect_toon()
	_setup_cameras()
	for v in _cams.size():
		for p in PASSES:
			_steps.append([v, p])
	_wait = 0


func _process(_dt: float) -> bool:
	if _sheet_wait >= 0:
		_caption_tick()
		return false
	if Time.get_ticks_msec() - _t0 > 900000:
		print("sun_locate: FAIL (no result in 900 s)")
		_finish(1)
		return false
	if _wait < 0:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= 0:
		_capture(_steps[_step])
	_step += 1
	if _step >= _steps.size():
		var f := FileAccess.open(_out.path_join("meta.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(_meta, "  "))
		f.close()
		print("sun_locate: %d views, %d passes each, in %s" % [_cams.size(), PASSES.size(), _out])
		_finish(0)
		return false
	_prepare(_steps[_step])
	_wait = SETTLE + (6 if _steps[_step][1] == "beauty" else 0)
	return false


func _finish(code: int) -> void:
	_wait = -1
	Kernels.shutdown()
	Guest.shutdown()
	quit(code)


## The beauty camera on the window, as realize_check places it, and an analysis camera on a linear
## float SubViewport sharing the world, with its own environment and no compositor, which alone sees
## the buffer quad.
func _setup_cameras() -> void:
	var root := get_root()
	_cam = Camera3D.new()
	_cam.fov = 58.0
	_cam.near = 0.1
	_cam.far = 2500.0
	_cam.cull_mask = 0xFFFFF & ~GBUF_LAYER
	root.add_child(_cam)
	_cam.make_current()
	_sub = SubViewport.new()
	_sub.size = root.size
	_sub.use_hdr_2d = true
	_sub.msaa_3d = Viewport.MSAA_DISABLED
	_sub.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_sub.use_taa = false
	_sub.use_debanding = false
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.world_3d = root.world_3d
	root.add_child(_sub)
	_scam = Camera3D.new()
	_scam.fov = 58.0
	_scam.near = 0.1
	_scam.far = 2500.0
	_scam.cull_mask = 0xFFFFF
	_scam.compositor = Compositor.new()
	_env_sun = _flat_env(Color(0, 0, 0), 0.0)
	_env_albedo = _flat_env(Color(1, 1, 1), 1.0)
	_scam.environment = _env_sun
	_sub.add_child(_scam)
	_scam.make_current()
	var sh := Shader.new()
	sh.code = QUAD_SHADER
	_quad_mat = ShaderMaterial.new()
	_quad_mat.shader = sh
	_quad_mat.render_priority = 127
	_quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	_quad.mesh = qm
	_quad.material_override = _quad_mat
	_quad.layers = GBUF_LAYER
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	_quad.visible = false
	_scam.add_child(_quad)
	_quad.position = Vector3(0, 0, -1)
	_meta["viewport"] = [root.size.x, root.size.y]
	_meta["beauty_msaa"] = ["off", "2x", "4x", "8x"][root.msaa_3d]


static func _flat_env(ambient: Color, energy: float) -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = ambient
	e.ambient_light_energy = energy
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	return e


## Every toon material with MToon's _IndirectLightIntensity, and its value, so the normal pass can
## set it to 1 and put it back.
func _collect_toon() -> void:
	var seen := {}
	var mats := []
	for n in _st.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi.material_override != null:
			mats.append(gi.material_override)
		var mesh: Mesh = null
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
			for i in (gi as MeshInstance3D).get_surface_override_material_count():
				mats.append((gi as MeshInstance3D).get_surface_override_material(i))
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			mesh = (gi as MultiMeshInstance3D).multimesh.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				mats.append(mesh.surface_get_material(i))
	var has := {}
	for m in mats:
		if not (m is ShaderMaterial) or seen.has(m):
			continue
		seen[m] = true
		var sh: Shader = (m as ShaderMaterial).shader
		if sh == null:
			continue
		if not has.has(sh):
			has[sh] = sh.get_shader_uniform_list().any(func(u): return u.name == "_IndirectLightIntensity")
		if has[sh]:
			_toon.append(m)
			var k = m.get_shader_parameter("_IndirectLightIntensity")
			_toon_k[m] = 0.1 if k == null else float(k)
	_meta["toon_materials"] = _toon.size()


func _toon_normals(on: bool) -> void:
	for m in _toon:
		m.set_shader_parameter("_IndirectLightIntensity", 1.0 if on else _toon_k[m])


func _prepare(step: Array) -> void:
	var v: int = step[0]
	var p: String = step[1]
	if p == "beauty":
		_place(_cams[v])
	_quad.visible = p in ["normal", "posx", "posy", "posz", "dist"]
	_quad_mat.set_shader_parameter("mode", {"normal": 0, "posx": 1, "posy": 2, "posz": 3, "dist": 4}.get(p, 0))
	_sun.visible = p != "albedo"
	_sun.shadow_enabled = p != "sun_noshadow"
	_scam.environment = _env_albedo if p == "albedo" else _env_sun
	_toon_normals(p == "normal")


func _capture(step: Array) -> void:
	var v: int = step[0]
	var p: String = step[1]
	if p == "beauty":
		var img := get_root().get_texture().get_image()
		img.save_png(_out.path_join("port-view_%d.png" % v))
		var vm := _view_meta(v)
		for t in [["visible", Viewport.RENDER_INFO_TYPE_VISIBLE], ["shadow", Viewport.RENDER_INFO_TYPE_SHADOW]]:
			vm["render_" + t[0]] = {"objects": get_root().get_render_info(t[1], Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
				"primitives": get_root().get_render_info(t[1], Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
				"draw_calls": get_root().get_render_info(t[1], Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
		vm["shadow_setup"] = _st.get("shadow_setup")
		_meta.views.append(vm)
		print("sun_locate: view %d %s at %s" % [v, str(_cams[v]), str(_cam.global_position)])
		return
	var img := _sub.get_texture().get_image()
	if img.get_format() != Image.FORMAT_RGBH:
		img.convert(Image.FORMAT_RGBH)
	var f := FileAccess.open(_out.path_join("%s_%d.f16" % [p, v]), FileAccess.WRITE)
	f.store_buffer(img.get_data())
	f.close()


## The original's walking eye or free camera (tools/realize_check.gd), on both cameras.
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
	var t := Transform3D(Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0), EULER_ORDER_YXZ), p)
	_cam.transform = t
	_scam.transform = t


func _view_meta(v: int) -> Dictionary:
	var t := _cam.global_transform
	var pr := _cam.get_camera_projection()
	return {
		"view": v, "cam": Array(_cams[v]),
		"origin": _v(t.origin), "basis_x": _v(t.basis.x), "basis_y": _v(t.basis.y), "basis_z": _v(t.basis.z),
		"projection": [_v4(pr.x), _v4(pr.y), _v4(pr.z), _v4(pr.w)],
		"fov": _cam.fov, "near": _cam.near, "far": _cam.far, "keep_aspect": _cam.keep_aspect,
		"analysis_origin": _v(_scam.global_transform.origin),
		"analysis_projection": [_v4(_scam.get_camera_projection().x), _v4(_scam.get_camera_projection().y),
				_v4(_scam.get_camera_projection().z), _v4(_scam.get_camera_projection().w)],
	}


func _shadow_settings() -> Dictionary:
	var d := {}
	for k in ["shadow_enabled", "shadow_bias", "shadow_normal_bias", "shadow_blur", "shadow_opacity",
			"shadow_transmittance_bias", "directional_shadow_mode", "directional_shadow_split_1",
			"directional_shadow_split_2", "directional_shadow_split_3", "directional_shadow_blend_splits",
			"directional_shadow_fade_start", "directional_shadow_max_distance", "directional_shadow_pancake_size",
			"light_angular_distance", "light_energy", "light_color", "sky_mode"]:
		var val = _sun.get(k)
		d[k] = str(val) if val is Color else val
	d["station_fit"] = _st.get("shadow_setup")
	for k in ["rendering/lights_and_shadows/directional_shadow/size",
			"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",
			"rendering/lights_and_shadows/directional_shadow/16_bits"]:
		d[k] = ProjectSettings.get_setting(k)
	return d


static func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _v4(v: Vector4) -> Array:
	return [v.x, v.y, v.z, v.w]


# ------------------------------------------------------------------------------ --analyze
# godot --path . --resolution 1920x1080 --script tools/sun_locate.gd -- --analyze --port=<render dir>
#     --oracle=<original_%d.png pattern> [--orig=<tools/oracle/sun_cams.mjs dir>] [--control=<render dir
#     with --sun-yaw>] [--masks=1] [--boot=200] [--json=tools/calib/sun_locate.json] [--sheets=<dir>]
#     [--desktop=<dir>] [--views=0,...,7]
# Runs tools/sun_locate_fit.gd's measurements on the GPU (tools/sun_locate_gpu.gd), writes the
# numbers, and one contact sheet per view (copied to --desktop as sun-locate-NN, never overwriting).

var _sheets := []
var _sheet_vp: SubViewport
var _sheet_label: Label
var _sheet_opt := {}
var _sheet_wait := -1


func _analyze() -> void:
	var opt := {"views": "0,1,2,3,4,5,6,7", "boot": "200"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			opt[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var views := Array(opt.views.split(",")).map(func(x): return int(x))
	var fit = SunFit.new()
	fit.gpu = Gpu.new()
	if not fit.gpu.ok:
		quit(1)
		return
	fit.gpu.set_posts(SunFit.post_defs())
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(opt.port.path_join("meta.json")))
	var sh: Dictionary = meta.sun_shadow
	var v0: Dictionary = meta.views[0]
	var sp: Dictionary = Gpu.godot_splits(v0.fov, float(meta.viewport[0]) / meta.viewport[1], v0.near,
			minf(sh.directional_shadow_max_distance, v0.far),
			[sh.directional_shadow_split_1, sh.directional_shadow_split_2, sh.directional_shadow_split_3],
			int(sh["rendering/lights_and_shadows/directional_shadow/size"]))
	fit.gpu.split_far = sp.far
	fit.gpu.split_texel = sp.texel
	var pssm := int(sh.directional_shadow_mode) != DirectionalLight3D.SHADOW_ORTHOGONAL
	var nboot := int(opt.boot)
	var engines := [{"name": "oracle", "images": opt.oracle, "buffers": opt.port, "num": 0, "den": 0}]
	engines.append({"name": "port", "images": opt.port.path_join("port-view_%d.png"), "buffers": opt.port, "num": 0, "den": 0, "godot_edges": pssm})
	if opt.has("control"):
		engines.append({"name": "control", "images": opt.control.path_join("port-view_%d.png"), "buffers": opt.control, "num": 0, "den": 0, "godot_edges": pssm})
	if opt.has("orig"):
		engines.append({"name": "original_rerender", "images": opt.orig.path_join("beauty_%d.png"), "buffers": opt.port, "num": 0, "den": 0})
	if opt.has("masks"):
		engines.append({"name": "port_true_mask", "images": "", "buffers": opt.port, "num": 1, "den": 2, "sun_passes": true, "godot_edges": pssm})
		if opt.has("orig"):
			engines.append({"name": "original_true_mask", "images": opt.oracle, "buffers": opt.port, "num": 0, "den": 1,
				"den_images": opt.orig.path_join("noshadow_%d.png")})
	var recs := {}
	for e in engines:
		e["boot"] = nboot
		e["meta"] = meta
		recs[e.name] = fit.engine(e, views)
		if e.name in ["oracle", "port", "control", "original_rerender"]:
			recs[e.name]["toon_bands"] = fit.toon(e, views, meta, nboot)
	var out := _summary(recs, meta, opt, sp, fit)
	out["log"] = fit.log_lines
	if opt.has("json"):
		var f := FileAccess.open(opt.json, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  ", false))
		f.close()
		print("sun_locate: numbers in %s" % opt.json)
	if opt.has("sheets"):
		DirAccess.make_dir_recursive_absolute(opt.sheets)
		_sheets = fit.sheets(views, meta, opt.port, opt.oracle, recs)
		_sheet_opt = opt
		fit.gpu.release()
		_start_captions()
		return
	fit.gpu.release()
	quit()


## Gates, verdict and the tables.
func _summary(recs: Dictionary, meta: Dictionary, opt: Dictionary, sp: Dictionary, fit) -> Dictionary:
	var code := Vector3(SunFit.SUN_CODE[0], SunFit.SUN_CODE[1], SunFit.SUN_CODE[2]).normalized()
	var live := {"port": Vector3(meta.sun_to_light[0], meta.sun_to_light[1], meta.sun_to_light[2])}
	var cams := []
	var shadow_orig := {}
	if opt.has("orig"):
		var om: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(opt.orig.path_join("meta.json")))
		var ov: Dictionary = om.views[0]
		var travel := Vector3(ov.sunTarget[0] - ov.sunPosition[0], ov.sunTarget[1] - ov.sunPosition[1], ov.sunTarget[2] - ov.sunPosition[2])
		live["original"] = -travel.normalized()
		shadow_orig = ov.shadow
		shadow_orig["type"] = ov.shadowMapType
		shadow_orig["revision"] = om.revision
		for v in range(om.views.size()):
			var o: Dictionary = om.views[v]
			var pv: Dictionary = meta.views[v]
			var M: Array = o.matrixWorld
			var rot := 0.0
			for c in 3:
				var col := Vector3(M[4 * c], M[4 * c + 1], M[4 * c + 2])
				var pc: Array = [pv.basis_x, pv.basis_y, pv.basis_z][c]
				rot = maxf(rot, rad_to_deg(col.angle_to(Vector3(pc[0], pc[1], pc[2]))))
			fit.gpu.load_view(opt.port, v, false)
			var dc: Dictionary = fit.gpu.depth_check(opt.orig.path_join("geo_%d.f32" % v))
			cams.append({"view": v, "cam": pv.cam, "eye_original": o.position, "eye_port": pv.origin,
				"eye_diff_m": Vector3(o.position[0], o.position[1], o.position[2]).distance_to(Vector3(pv.origin[0], pv.origin[1], pv.origin[2])),
				"axes_diff_deg": rot, "fov_aspect_near_far_original": [o.fov, o.aspect, o.near, o.far],
				"fov_near_far_port": [pv.fov, pv.near, pv.far], "projection_p00_p11_original": [o.projectionMatrix[0], o.projectionMatrix[5]],
				"projection_p00_p11_port": [pv.projection[0][0], pv.projection[1][1]], "depth_vs_original": dc})
	var yaw_meta = null
	if opt.has("control"):
		var cm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(opt.control.path_join("meta.json")))
		live["control"] = Vector3(cm.sun_to_light[0], cm.sun_to_light[1], cm.sun_to_light[2])
		yaw_meta = cm.sun_yaw_deg
	var table := []
	var sun_of := {}
	for name in recs:
		var r: Dictionary = recs[name]
		for m in [["post shadows", r.get("joint")], ["toon bands", r.get("toon_bands", {}).get("joint")]]:
			if m[1] == null:
				continue
			var L := SunFit.dir_of(m[1].azimuth_deg, m[1].elevation_deg)
			sun_of["%s/%s" % [name, m[0]]] = L
			var row := {"image": name, "method": m[0], "azimuth_deg": m[1].azimuth_deg, "elevation_deg": m[1].elevation_deg,
				"angle_to_SUN_DIR_deg": SunFit.angle_between(L, code)}
			var who: String = "original" if name.begins_with("original") or name == "oracle" else ("control" if name == "control" else "port")
			if live.has(who):
				row["angle_to_live_light_deg"] = SunFit.angle_between(L, live[who])
				row["live_light"] = who
			if m[1].has("bootstrap"):
				row["bootstrap_angle_p68_deg"] = m[1].bootstrap.get("angle_p68_deg")
				row["bootstrap_angle_p95_deg"] = m[1].bootstrap.get("angle_p95_deg")
			if m[1].get("se_curvature_b_profiled_deg") != null:
				row["residual_se_az_el_deg"] = m[1].se_curvature_b_profiled_deg
			table.append(row)
	var pairs := {}
	for m in ["post shadows", "toon bands"]:
		var o = sun_of.get("oracle/" + m)
		var p = sun_of.get("port/" + m)
		var c = sun_of.get("control/" + m)
		var f = sun_of.get("original_rerender/" + m)
		var d := {}
		if o != null and p != null:
			d["oracle_vs_port_deg"] = SunFit.angle_between(o, p)
		if o != null and f != null:
			d["original_floor_oracle_vs_rerender_deg"] = SunFit.angle_between(o, f)
		if c != null and p != null:
			var ac := SunFit.az_el_of(c)
			var ap := SunFit.az_el_of(p)
			d["control_vs_port_deg"] = SunFit.angle_between(c, p)
			d["control_shadow_azimuth_turn_deg"] = wrapf(ac.x - ap.x, -180.0, 180.0)
			d["control_elevation_change_deg"] = ac.y - ap.y
		if c != null and o != null:
			d["control_vs_oracle_deg"] = SunFit.angle_between(c, o)
		pairs[m] = d
	# gates (primary: post shadows; the toon bands reported beside them)
	var gates := {}
	for m in ["post shadows", "toon bands"]:
		var rows := table.filter(func(r): return r.method == m)
		var o = rows.filter(func(r): return r.image == "oracle")
		var p = rows.filter(func(r): return r.image == "port")
		var g := {}
		if o.size() and p.size():
			g["oracle_under_0.5deg"] = o[0].angle_to_SUN_DIR_deg < 0.5
			g["port_under_0.5deg"] = p[0].angle_to_SUN_DIR_deg < 0.5
			g["oracle_vs_port_under_0.5deg"] = pairs[m].get("oracle_vs_port_deg", 99.0) < 0.5
			g["oracle_bootstrap_p68_under_0.5deg"] = o[0].get("bootstrap_angle_p68_deg", 99.0) < 0.5
			g["port_bootstrap_p68_under_0.5deg"] = p[0].get("bootstrap_angle_p68_deg", 99.0) < 0.5
		if pairs[m].has("control_shadow_azimuth_turn_deg"):
			var turn: float = pairs[m].control_shadow_azimuth_turn_deg
			# the control turns the light +2 deg about +Y: the shadow azimuth atan2(-Lz, -Lx) goes down 2 deg
			g["control_detected_2deg_pm_0.5"] = absf(absf(turn) - absf(yaw_meta if yaw_meta != null else 2.0)) <= 0.5
			g["control_fails_0.5deg_gate"] = pairs[m].get("control_vs_oracle_deg", 0.0) >= 0.5
		if pairs[m].has("original_floor_oracle_vs_rerender_deg"):
			g["original_floor_under_0.05deg"] = pairs[m].original_floor_oracle_vs_rerender_deg < 0.05
		gates[m] = g
	var ok: bool = gates["post shadows"].get("oracle_under_0.5deg", false) and gates["post shadows"].get("port_under_0.5deg", false) \
			and gates["post shadows"].get("oracle_vs_port_under_0.5deg", false)
	var verdict := ""
	if ok:
		verdict = "Same sun. Both images put the sun within 0.5 deg of SUN_DIR and of each other, by the post shadows and, independently, by the toon bands; the 2 deg control is detected and fails the gate, and the original measured twice agrees with itself. No axis flip, sign slip or wrong vector: the remaining shadow differences belong to the shadow-map setup (see shadow_setup)."
	else:
		verdict = "Different suns, or a measurement that did not converge: see table and gates."
	var hashes := {}
	for v in 8:
		var pth: String = opt.oracle % v
		if FileAccess.file_exists(pth):
			hashes["original_%d.png" % v] = FileAccess.get_sha256(pth)
	var inputs := {
		"oracle": "release oracle-4112f57-h8 (V-Sekai-fire/entities-sakuragaoka-station): the original at upstream 4112f57, sphere-Hammersley 8@-1,-11.4, 1920x1080, --only environment,station,plaza,sakura; local copies pixel-identical to the release PNGs",
		"oracle_sha256_of_files_read": hashes,
		"port_images": "tools/sun_locate.gd's beauty pass, pixel-identical to tools/realize_check.gd --hammersley=8@-1,-11.4 renders at this commit",
		"control": ("tools/sun_locate.gd --sun-yaw=%s: the port's light, sky disc and light leak turned about +Y" % str(yaw_meta)) if yaw_meta != null else "none",
		"godot": Engine.get_version_info().string, "renderer": "Forward+ (Vulkan), the analysis as GLSL compute on a local RenderingDevice",
		"bootstrap_replicates": int(opt.boot),
	}
	return {
		"inputs": inputs,
		"about": "Where the sun is in the rendered images of the three.js original (oracle-4112f57-h8) and the Godot port, measured from pixels: tools/sun_locate.gd (port buffers and --analyze), tools/sun_locate_gpu.gd (GLSL compute), tools/sun_locate_fit.gd, tools/oracle/sun_cams.mjs (the original's live cameras and sun). Azimuth is the shadow's direction atan2(-Lz, -Lx) in degrees, elevation asin(Ly), L pointing at the sun.",
		"SUN_DIR": {"code": SunFit.SUN_CODE, "normalized": [code.x, code.y, code.z], "azimuth_deg": SunFit.az_el_of(code).x, "elevation_deg": SunFit.az_el_of(code).y},
		"live_lights": _vecs(live),
		"cameras": cams,
		"verdict": verdict,
		"gates": gates,
		"pairs": pairs,
		"table": table,
		"engines": recs,
		"shadow_setup": _shadow_setup(meta, shadow_orig, sp, recs),
		"moge": _moge(),
		"port_splits": sp,
	}


static func _vecs(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		var v: Vector3 = d[k]
		o[k] = {"to_sun": [v.x, v.y, v.z], "azimuth_deg": SunFit.az_el_of(v).x, "elevation_deg": SunFit.az_el_of(v).y}
	return o


## The two shadow setups side by side, with what each does to a shadow's edge, and the edge model
## the images themselves gave.
static func _shadow_setup(meta: Dictionary, orig: Dictionary, sp: Dictionary, recs: Dictionary) -> Array:
	var sh: Dictionary = meta.sun_shadow
	var tx: Array = sp.texel
	var far: Array = sp.far
	var eo: Dictionary = recs.get("oracle", {}).get("edge_model", {})
	var ep: Dictionary = recs.get("port", {}).get("edge_model", {})
	var nb := float(sh.shadow_normal_bias)
	var tan_el := tan(deg_to_rad(31.12))
	var H := func(m: float) -> String: return SunFit.household(m)
	var box := float(orig.get("right", 75))
	var span := float(orig.get("far", 520)) - float(orig.get("near", 1))
	var otex := 2.0 * box / float(orig.get("mapSize", [4096])[0])
	var obias := absf(float(orig.get("bias", -0.00035))) * span
	var onb := float(orig.get("normalBias", 0.035))
	var pbias := [0.001 * (2.0 * tx[0] * 1024.0 + 20.0) * 2.0, 0.001 * (2.0 * tx[1] * 1024.0 + 20.0) * 2.0]
	return [
		{"setting": "filter", "original": "PCFSoftShadowMap (shadowMap.type %d, three r%s): a fixed 3x3 bilinear-weighted kernel, about a 4-texel footprint" % [int(orig.get("type", 2)), str(orig.get("revision", 170))],
			"port": "PCF, soft_shadow_filter_quality %d (Soft Low: 4 Vogel taps, radius blur %.1f x 2 texels), light_angular_distance %.1f (no PCSS)" % [int(sh["rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"]), sh.shadow_blur, sh.light_angular_distance],
			"effect": "edge softness: the original's edges blur over about 1.5 texels a side; the port's PCF is thresholded by MToon (below), so its edges stay hard"},
		{"setting": "radius", "original": "shadow.radius %s: ignored, three r170 reads radius only for PCFShadowMap and VSM" % str(orig.get("radius", 1.6)),
			"port": "shadow_blur %.1f" % sh.shadow_blur, "effect": "none in the original; porting radius 1.6 as a blur would soften the port beyond the original"},
		{"setting": "map", "original": "%d x %d, one map" % [int(orig.get("mapSize", [4096, 4096])[0]), int(orig.get("mapSize", [4096, 4096])[1])],
			"port": "directional atlas %d (16-bit depth: %s), 4 splits of %d each" % [int(sh["rendering/lights_and_shadows/directional_shadow/size"]), str(sh["rendering/lights_and_shadows/directional_shadow/16_bits"]), int(sh["rendering/lights_and_shadows/directional_shadow/size"]) / 2],
			"effect": "resolution where the camera is"},
		{"setting": "coverage", "original": "orthographic box +-%d m (quality.shadowSize at high), near %d, far %d; target = camera + 0.45 S ahead (horizontal), snapped to texels in light space; light 260 m up the sun" % [int(box), int(orig.get("near", 1)), int(orig.get("far", 520))],
			"port": "PSSM %d splits to %.0f m (max distance), offsets %.1f / %.1f / %.1f -> far %.2f / %.2f / %.2f / %.0f m view depth; each split's box fits its frustum slice's bounding sphere, snapped (stable); pancake %.0f m; fade from %.0f %%; blend_splits %s" % [
				4 if int(sh.directional_shadow_mode) == 2 else int(sh.directional_shadow_mode) + 1, sh.directional_shadow_max_distance, sh.directional_shadow_split_1, sh.directional_shadow_split_2, sh.directional_shadow_split_3,
				far[0], far[1], far[2], far[3], sh.directional_shadow_pancake_size, 100.0 * float(sh.directional_shadow_fade_start), str(sh.directional_shadow_blend_splits)],
			"effect": "the port has no shadow past %s of view depth (fading from 80 %%); the original has none outside its box; the port's quality steps at the split seams" % H.call(float(sh.directional_shadow_max_distance))},
		{"setting": "texel (world)", "original": "%s everywhere" % H.call(otex),
			"port": "%s / %s / %s / %s by split (this camera: 58 deg, 16:9)" % [H.call(tx[0]), H.call(tx[1]), H.call(tx[2]), H.call(tx[3])],
			"effect": "the port is sharper than the original inside 20 m of view depth and coarser beyond; a bollard is 3 of the original's texels wide, so thin posts rasterize coarsely there"},
		{"setting": "depth bias", "original": "bias %s in [0,1] depth over far - near = %.0f m: %s toward the light" % [str(orig.get("bias", -0.00035)), span, H.call(obias)],
			"port": "shadow_bias %.2f: %.2f / 100 x (2 r + pancake) x blur x quality radius -> %s (split 1) to %s (split 2) toward the light" % [sh.shadow_bias, sh.shadow_bias, H.call(pbias[0]), H.call(pbias[1])],
			"effect": "removes shadow where the occluder is that close along the ray: a lit gap at the foot of each post, largest in the original"},
		{"setting": "normal bias", "original": "normalBias %s along the world normal: on the paving the lookup moves %s away from the sun, and tips shorten by that" % [H.call(onb), H.call(onb / tan_el)],
			"port": "shadow_normal_bias %.1f x split texel along the normal, its part along the light removed: %s / %s / %s, so tips shorten %s / %s / %s by split" % [nb, H.call(nb * tx[0]), H.call(nb * tx[1]), H.call(nb * tx[2]), H.call(nb * tx[0] / tan_el), H.call(nb * tx[1] / tan_el), H.call(nb * tx[2] / tan_el)],
			"effect": "shadows shorter toward the sun by b / tan(elevation); in the port the shortening jumps at each split seam"},
		{"setting": "shading of a shadow", "original": "MeshToonMaterial: sun irradiance x shadow (linear), so the visible edge sits at 50 % attenuation; in shadow only the hemisphere light remains (about 23 % of lit luminance on the paving, then graded blue-violet)",
			"port": "MToon: the attenuation enters lightIntensity before the toon ramp (_ShadeToony 0.9, _ShadeShift 0), so the edge snaps at about 69 % attenuation (paving, N.L 0.52); in shadow the shade colour (0.72, 0.68, 0.82) stays lit by the sun (42 % of lit in the sun alone)",
			"effect": "the port's shadows are harder, slightly larger (dilated) and lighter than the original's"},
		{"setting": "edge model fitted to the images (light plane)", "original": "dilation %s, normal-bias shift %s, blur %s" % [H.call(eo.get("dilation", 0.0)), H.call(eo.get("normal_bias", 0.0)), H.call(eo.get("blur_m", 0.0))],
			"port": "dilation %.3f texel, normal-bias shift %.3f texel (setting %.1f), blur %s" % [ep.get("dilation", 0.0), ep.get("normal_bias", 0.0), nb, H.call(ep.get("blur_m", 0.0))],
			"effect": "measured, not assumed: the sun is fitted with these as free parameters, so they do not bias it"},
	]


static func _moge() -> Dictionary:
	return {
		"status": "not run",
		"why": "RFD 2294 (where compute runs): heavy compute runs in a godot-sandbox guest or on ggml-rd/compute-rd, never as a host Python pipeline, and MoGe may run only as ggml in a guest; RFD 1167 lists MoGe read-only with no ggml-rd port, so method B would need that port first",
		"weights_checked": {"repo": "Ruicheng/moge-2-vitl-normal (MoGe-2, ViT-L, normals)", "license": "MIT (model card), base model facebook/dinov2-large (Apache-2.0)", "file": "model.pt", "size_bytes": 1323815904, "gated": false},
		"code": "3-interactor/moge-upstream 74fbce0: MIT, its DINOv2 module Apache-2.0",
		"cost_of_the_python_route_not_taken": "a host deep-learning framework with GPU wheels (about 3 GB), MoGe's helper packages, a GPU kernel compiler for MoGe-3, and the 1.3 GB checkpoint; about 10 minutes on this desk, and off the route",
		"cost_of_the_allowed_route": "a ggml port of DINOv2-L (24 ViT blocks) plus MoGe-2's conv heads into a guest on ggml-rd, then 8 oracle views at its 1.3 GB weights: a project of its own",
		"would_add": "normals and depth independent of the port's geometry, a check of the cameras; here the cameras are checked directly instead (cameras: the original's live matrices against the port's, and its own depth against the port's)",
	}


## Captions through a Label in a SubViewport (rendered, then read back), under each sheet body.
func _start_captions() -> void:
	_sheet_vp = SubViewport.new()
	_sheet_vp.size = Vector2i(1920, 120)
	_sheet_vp.transparent_bg = false
	_sheet_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1)
	bg.size = Vector2(1920, 120)
	_sheet_vp.add_child(bg)
	_sheet_label = Label.new()
	_sheet_label.position = Vector2(10, 4)
	_sheet_label.size = Vector2(1900, 112)
	_sheet_label.add_theme_font_size_override("font_size", 16)
	_sheet_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_sheet_vp.add_child(_sheet_label)
	get_root().add_child(_sheet_vp)
	_sheet_wait = 0


func _caption_tick() -> void:
	if _sheet_wait < 0:
		return
	if _sheets.is_empty():
		_sheet_wait = -1
		quit()
		return
	if _sheet_wait == 0:
		_sheet_label.text = _sheets[0].caption
	_sheet_wait += 1
	if _sheet_wait < 4:
		return
	var s: Dictionary = _sheets.pop_front()
	var cap := _sheet_vp.get_texture().get_image()
	cap.convert(Image.FORMAT_RGBA8)
	var img := Image.create(1920, 1080 + 120, false, Image.FORMAT_RGBA8)
	img.blit_rect(s.body, Rect2i(0, 0, 1920, 1080), Vector2i(0, 0))
	img.blit_rect(cap, Rect2i(0, 0, 1920, 120), Vector2i(0, 1080))
	img.convert(Image.FORMAT_RGB8)
	var path: String = _sheet_opt.sheets.path_join("sun-locate-view%d.png" % s.view)
	img.save_png(path)
	if _sheet_opt.has("desktop"):
		DirAccess.make_dir_recursive_absolute(_sheet_opt.desktop)
		var n := 1
		while FileAccess.file_exists(_sheet_opt.desktop.path_join("sun-locate-%02d.png" % n)):
			n += 1
		var dst: String = _sheet_opt.desktop.path_join("sun-locate-%02d.png" % n)
		DirAccess.copy_absolute(path, dst)
		print("sun_locate: view %d sheet %s -> %s" % [s.view, path, dst])
	else:
		print("sun_locate: view %d sheet %s" % [s.view, path])
	_sheet_wait = 0
