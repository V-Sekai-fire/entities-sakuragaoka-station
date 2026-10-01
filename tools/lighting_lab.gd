# A synthetic lighting lab: CSG solids under the original's toon lighting (lighting_lab/truth.gdshader)
# rendered at sphere-Hammersley orbit views, then once per planted defect. Each defect's residual against
# the truth is summed on the GPU; the truth rendered twice is the floor, and a defect counts as seen when
# it moves more pixels than the floor does. --aov also writes each view's reference passes, the inputs
# the toon model reads (aov_albedo_<i>.png, aov_light_<i>.png).
#   godot --path . --resolution 512x512 --script tools/lighting_lab.gd -- --out=<dir> [--views=8] [--aov]
extends SceneTree

const TRUTH := preload("res://tools/lighting_lab/truth.gdshader")
const AOV := preload("res://tools/lighting_lab/aov.gdshader")
const SUN := Vector3(0.5, 0.45, 0.35)
const MAD_GLSL := """
#version 450
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, std430) readonly buffer A { uint a[]; };
layout(set = 0, binding = 1, std430) readonly buffer B { uint b[]; };
layout(set = 0, binding = 2, std430) buffer S { uint sum[4]; };
layout(push_constant, std430) uniform P { uint n; uint pad0; uint pad1; uint pad2; } p;
void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= p.n) {
		return;
	}
	uint moved = 0u;
	for (int c = 0; c < 3; c++) {
		int va = int((a[i] >> (8 * c)) & 0xFFu);
		int vb = int((b[i] >> (8 * c)) & 0xFFu);
		atomicAdd(sum[c], uint(abs(va - vb)));
		moved |= uint(va != vb);
	}
	atomicAdd(sum[3], moved);
}
"""

var _out := "user://lighting_lab"
var _views := 8
var _aov := false
var _mat := ShaderMaterial.new()
var _env := Environment.new()
var _sun := DirectionalLight3D.new()
var _cam := Camera3D.new()
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--views="):
			_views = int(a.substr(8))
		elif a == "--aov":
			_aov = true
	_mat.shader = TRUTH
	_scene()
	_gpu()
	_run.call_deferred()


func _scene() -> void:
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.82, 0.86, 0.92)
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = _env
	root.add_child(we)
	_sun.light_energy = 2.75 / PI
	_sun.shadow_enabled = true
	root.add_child(_sun)
	_sun.look_at_from_position(Vector3.ZERO, -SUN.normalized(), Vector3.UP)
	var csg := CSGCombiner3D.new()
	root.add_child(csg)
	_solid(csg, CSGBox3D.new(), Vector3(0, -0.1, 0), {"size": Vector3(14, 0.2, 14)})
	_solid(csg, CSGSphere3D.new(), Vector3(0, 1, 0), {"radius": 1.0, "radial_segments": 48, "rings": 24})
	_solid(csg, CSGBox3D.new(), Vector3(2.6, 0.75, 0.4), {"size": Vector3(1.5, 1.5, 1.5)})
	_solid(csg, CSGCylinder3D.new(), Vector3(-2.6, 1, 0.3), {"radius": 0.6, "height": 2.0, "sides": 40})
	_solid(csg, CSGTorus3D.new(), Vector3(0.2, 0.35, 2.6), {"inner_radius": 0.5, "outer_radius": 1.1, "sides": 40, "ring_sides": 20})
	var carved := CSGBox3D.new()
	_solid(csg, carved, Vector3(-0.4, 0.9, -2.6), {"size": Vector3(1.8, 1.8, 1.8)})
	var hole := CSGSphere3D.new()
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	_solid(carved, hole, Vector3(0.5, 0.5, 0.5), {"radius": 0.9, "radial_segments": 40, "rings": 20})
	_cam.fov = 50.0
	root.add_child(_cam)


func _solid(parent: Node, shape: CSGShape3D, at: Vector3, props: Dictionary) -> void:
	for k in props:
		shape.set(k, props[k])
	shape.set("material", _mat)
	shape.position = at
	parent.add_child(shape)


## Orbit views at the sphere Hammersley sequence's angles, elevation remapped to 10-70 degrees.
func _orbit() -> Array:
	var out := []
	for i in _views:
		var u := float(i) / _views
		var v := 0.0
		var f := 0.5
		var k := i
		while k > 0:
			v += (k & 1) * f
			k >>= 1
			f *= 0.5
		u = 2.0 * u if u < 0.25 else 2.0 / 3.0 * u + 1.0 / 3.0
		var el := clampf(rad_to_deg(acos(1.0 - 2.0 * u) - PI / 2.0), -85.0, 85.0)
		out.append(Vector2(v * 360.0, 10.0 + (el + 85.0) / 170.0 * 60.0))
	return out


## One image per view, drawn synchronously after the camera moves so no stale frame is read.
func _render(views: Array) -> Array:
	var shots := []
	for a in views:
		_cam.global_transform = _orbit_transform(a)
		await process_frame
		RenderingServer.force_draw(true)
		RenderingServer.force_draw(true)
		shots.append(root.get_texture().get_image())
	return shots


## The reference passes through the same viewport as the renders, as 8-bit sRGB PNGs: albedo, then
## 0.5 dotNL + 0.5 / shadow / 0.5 normal y + 0.5 in red, green and blue, black where there is sky.
func _passes(views: Array) -> void:
	_mat.shader = AOV
	var bg: Color = _env.background_color
	_env.background_color = Color(0, 0, 0)
	for mode in 2:
		_mat.set_shader_parameter("mode", mode)
		var shots: Array = await _render(views)
		for i in shots.size():
			shots[i].save_png(_out.path_join("aov_%s_%d.png" % [["albedo", "light"][mode], i]))
	_env.background_color = bg
	_mat.shader = TRUTH


func _orbit_transform(a: Vector2) -> Transform3D:
	var az := deg_to_rad(a.x)
	var el := deg_to_rad(a.y)
	var eye := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)) * 9.0 + Vector3(0, 0.8, 0)
	return Transform3D.IDENTITY.translated(eye).looking_at(Vector3(0, 0.8, 0), Vector3.UP)


func _apply(defect: Dictionary) -> void:
	for k in defect.get("set", {}):
		_mat.set_shader_parameter(k, defect.set[k])
	_sun.shadow_enabled = defect.get("shadow", true)


func _run() -> void:
	var mean := Color("#a9b3ee").lerp(Color("#d9c6c8"), 0.5)
	var truth_params := {
		"sky": Color("#a9b3ee"), "ground": Color("#d9c6c8"), "thresholds": Vector3(0.0, 0.12, 0.42),
		"levels": Vector4(0.0, 0.42, 0.8, 1.0), "sun_gain": 1.0
	}
	var defects := [
		{"name": "truth again (floor)", "set": {}},
		{"name": "ramp thresholds moved", "set": {"thresholds": Vector3(0.0, 0.2, 0.5)}},
		{"name": "shade level too bright", "set": {"levels": Vector4(0.0, 0.6, 0.8, 1.0)}},
		{"name": "sun 7 percent dark", "set": {"sun_gain": 0.93}},
		{"name": "hemisphere swapped", "set": {"sky": Color("#d9c6c8"), "ground": Color("#a9b3ee")}},
		{"name": "hemisphere as its mean", "set": {"sky": mean, "ground": mean}},
		{"name": "no shadow", "set": {}, "shadow": false},
	]
	DirAccess.make_dir_recursive_absolute(_out)
	var views := _orbit()
	await process_frame
	await process_frame
	_apply({"set": truth_params})
	var truth: Array = await _render(views)
	for i in truth.size():
		truth[i].save_png(_out.path_join("truth_%d.png" % i))
	if _aov:
		await _passes(views)
	var summary := []
	var failed := 0
	var floor_moved := 0
	for d in defects:
		_apply({"set": truth_params})
		_apply(d)
		var shots: Array = await _render(views)
		var mads := []
		var moved := 0
		for i in shots.size():
			var r: Vector2 = _mad(truth[i], shots[i])
			mads.append(r.x)
			moved += int(r.y)
			shots[i].save_png(_out.path_join("%s_%d.png" % [d.name.replace(" ", "_"), i]))
		var mean_mad: float = mads.reduce(func(s, x): return s + x, 0.0) / mads.size()
		var is_floor: bool = str(d.name).begins_with("truth again")
		if is_floor:
			floor_moved = moved
		var ok: bool = (moved == 0) if is_floor else (moved > floor_moved)
		failed += 0 if ok else 1
		print("lab: %-26s MAD %.3f  pixels moved %d (%.2f%%)  views %s  %s" % [d.name, mean_mad, moved,
				100.0 * moved / (shots.size() * shots[0].get_width() * shots[0].get_height()),
				", ".join(mads.map(func(x): return "%.2f" % x)), "ok" if ok else "FAIL"])
		summary.append({"defect": d.name, "planted": var_to_str(d.get("set", {})), "shadow": d.get("shadow", true),
				"mad": mads, "mean": mean_mad, "pixels_moved": moved, "ok": ok})
	var f := FileAccess.open(_out.path_join("summary.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"views": views.map(func(v): return [v.x, v.y]), "defects": summary}, "  "))
	f.close()
	print("lab: %d defects, %d failed, renders and summary.json in %s" % [defects.size(), failed, _out])
	quit(1 if failed > 0 else 0)


func _gpu() -> void:
	_rd = RenderingServer.create_local_rendering_device()
	var src := RDShaderSource.new()
	src.source_compute = MAD_GLSL
	_shader = _rd.shader_create_from_spirv(_rd.shader_compile_spirv_from_source(src))
	_pipeline = _rd.compute_pipeline_create(_shader)


## Mean absolute difference over RGB in [0, 255], every pixel, and how many pixels differ at all.
func _mad(a: Image, b: Image) -> Vector2:
	var x: Image = a.duplicate()
	var y: Image = b.duplicate()
	x.convert(Image.FORMAT_RGBA8)
	y.convert(Image.FORMAT_RGBA8)
	var n := x.get_width() * x.get_height()
	var ba := _rd.storage_buffer_create(n * 4, x.get_data())
	var bb := _rd.storage_buffer_create(n * 4, y.get_data())
	var zero := PackedByteArray()
	zero.resize(16)
	var bs := _rd.storage_buffer_create(16, zero)
	var uniforms := []
	for i in 3:
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = i
		u.add_id([ba, bb, bs][i])
		uniforms.append(u)
	var set := _rd.uniform_set_create(uniforms, _shader, 0)
	var pc := PackedInt32Array([n, 0, 0, 0]).to_byte_array()
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, set, 0)
	_rd.compute_list_set_push_constant(list, pc, pc.size())
	_rd.compute_list_dispatch(list, (n + 63) / 64, 1, 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	var sums := _rd.buffer_get_data(bs)
	var total := sums.decode_u32(0) + sums.decode_u32(4) + sums.decode_u32(8)
	for r in [set, ba, bb, bs]:
		_rd.free_rid(r)
	return Vector2(float(total) / (3.0 * n), float(sums.decode_u32(12)))
