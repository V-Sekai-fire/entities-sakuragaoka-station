# src/core/renderer.js's composite pass, run in place on the colour buffer after transparents:
# colour-aware outlines from depth and normals, then exposure, soft clip, grading, light leak and vignette.
@tool
extends CompositorEffect

const GLSL := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(set = 0, binding = 2) uniform sampler2D normal_tex;
layout(push_constant, std430) uniform Params {
	vec2 raster;
	float near;
	float far;
	vec4 sun;
	float outline;
	float grade;
	float exposure;
	float vignette;
} p;

const vec3 LINE = vec3(0.0272, 0.0203, 0.0513);

float lin_depth(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(p.raster) - 1);
	float d = texelFetch(depth_tex, c, 0).r;
	return min(p.near * p.far / (d * (p.far - p.near) + p.near), p.far);
}

vec3 nrm(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(p.raster) - 1);
	if (texelFetch(depth_tex, c, 0).r == 0.0) {
		return vec3(0.0, 0.0, 1.0);
	}
	return normalize(texelFetch(normal_tex, c, 0).xyz * 2.0 - 1.0);
}

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 soft_clip(vec3 c) {
	vec3 k = vec3(0.78);
	vec3 over = max(c - k, 0.0);
	return min(c, k) + (1.0 - k) * (1.0 - exp(-over / (1.0 - k)));
}

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	if (c.x >= int(p.raster.x) || c.y >= int(p.raster.y)) {
		return;
	}
	vec4 src = imageLoad(color_image, c);
	vec3 col = src.rgb;
	int px = int(round(max(1.0, p.raster.y / 1100.0)));
	ivec2 dx = ivec2(px, 0);
	ivec2 dy = ivec2(0, px);
	float d0 = lin_depth(c);
	float dl = lin_depth(c - dx);
	float dr = lin_depth(c + dx);
	float du = lin_depth(c - dy);
	float dd = lin_depth(c + dy);
	float i0 = 1.0 / max(d0, 0.05);
	float lap_x = abs(1.0 / max(dl, 0.05) + 1.0 / max(dr, 0.05) - 2.0 * i0) / i0;
	float lap_y = abs(1.0 / max(du, 0.05) + 1.0 / max(dd, 0.05) - 2.0 * i0) / i0;
	float d_edge = smoothstep(0.06, 0.18, max(lap_x, lap_y));
	float dmin = min(min(dl, dr), min(du, dd));
	d_edge = max(d_edge, smoothstep(0.10, 0.25, (d0 - dmin) / max(dmin, 0.05)));
	vec3 n0 = nrm(c);
	float n_edge = max(max(1.0 - dot(n0, nrm(c - dx)), 1.0 - dot(n0, nrm(c + dx))),
			max(1.0 - dot(n0, nrm(c - dy)), 1.0 - dot(n0, nrm(c + dy))));
	n_edge = smoothstep(0.30, 0.65, n_edge);
	float fade = 1.0 - smoothstep(35.0, 190.0, min(d0, dmin));
	float edge = max(d_edge, n_edge * 0.85) * fade * p.outline;
	col = mix(col, mix(col * vec3(0.42, 0.38, 0.5), LINE, 0.35), edge * 0.82);
	if (p.grade > 0.0) {
		vec3 g = soft_clip(col * p.exposure);
		float l = lum(g);
		g = mix(g, g * vec3(0.9, 0.92, 1.1), (1.0 - smoothstep(0.08, 0.55, l)) * 0.55);
		g += vec3(0.022, 0.012, -0.012) * smoothstep(0.55, 1.0, l);
		g = mix(vec3(lum(g)), g, 1.07);
		vec2 uv = (vec2(c) + 0.5) / p.raster;
		uv.y = 1.0 - uv.y;
		vec2 asp = vec2(p.raster.x / p.raster.y, 1.0);
		float ds = length((uv - p.sun.xy) * asp);
		float leak = exp(-ds * ds * 1.8) * 0.10 + exp(-ds * ds * 10.0) * 0.09 * p.sun.z;
		g += vec3(1.0, 0.86, 0.68) * leak * p.sun.w * (0.55 + 0.45 * p.sun.z);
		vec2 q = (uv - 0.5) * asp * 0.9;
		g *= 1.0 - p.vignette * smoothstep(0.35, 1.05, length(q));
		col = mix(col, g, p.grade);
	}
	imageStore(color_image, c, vec4(col, src.a));
}
"""

@export_range(0.0, 1.0) var outline := 1.0
@export_range(0.0, 1.0) var grade := 1.0
@export var exposure := 1.0
@export var vignette := 0.22
@export var sun_dir := Vector3.UP

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _sampler := RID()


static func compositor(sun: Vector3) -> Compositor:
	var fx := new()
	fx.sun_dir = sun
	var c := Compositor.new()
	c.compositor_effects = [fx]
	return c


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_normal_roughness = true
	RenderingServer.call_on_render_thread(_create)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null and _shader.is_valid():
		_rd.free_rid(_sampler)
		_rd.free_rid(_shader)


func _create() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	var src := RDShaderSource.new()
	src.source_compute = GLSL
	var spirv := _rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("composite: %s" % spirv.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	_sampler = _rd.sampler_create(RDSamplerState.new())


func _render_callback(type: int, data: RenderData) -> void:
	if type != effect_callback_type or not _pipeline.is_valid():
		return
	var buffers := data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := data.get_render_scene_data() as RenderSceneDataRD
	if buffers == null or scene == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var proj := scene.get_cam_projection()
	var cam := scene.get_cam_transform()
	var v := cam.affine_inverse() * (cam.origin + sun_dir.normalized() * 1000.0)
	var clip := proj * Vector4(v.x, v.y, v.z, 1.0)
	var front := clip.w > 0.0
	var sx := clip.x / clip.w * 0.5 + 0.5
	var sy := clip.y / clip.w * 0.5 + 0.5
	var on_screen := 0.0
	if front:
		var off := Vector2(maxf(0.0, absf(sx - 0.5) - 0.5), maxf(0.0, absf(sy - 0.5) - 0.5))
		on_screen = 1.0 - minf(1.0, off.length() * 2.5)
	var sun := Vector4(clampf(sx, -0.3, 1.3), clampf(sy, -0.2, 1.3), on_screen, 1.0)
	if not front:
		sun = Vector4(1.4 if sx < 0.5 else -0.4, 1.2, 0.0, 0.25)
	var pc := PackedFloat32Array([size.x, size.y, proj.get_z_near(), proj.get_z_far(),
			sun.x, sun.y, sun.z, sun.w, outline, grade, exposure, vignette])
	var bytes := pc.to_byte_array()
	for view in buffers.get_view_count():
		var u_color := RDUniform.new()
		u_color.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_color.binding = 0
		u_color.add_id(buffers.get_color_layer(view))
		var u_depth := RDUniform.new()
		u_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_depth.binding = 1
		u_depth.add_id(_sampler)
		u_depth.add_id(buffers.get_depth_layer(view))
		var u_normal := RDUniform.new()
		u_normal.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_normal.binding = 2
		u_normal.add_id(_sampler)
		u_normal.add_id(buffers.get_texture_slice("forward_clustered", "normal_roughness", view, 0, 1, 1))
		var set := UniformSetCacheRD.get_cache(_shader, 0, [u_color, u_depth, u_normal])
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, set, 0)
		_rd.compute_list_set_push_constant(list, bytes, bytes.size())
		_rd.compute_list_dispatch(list, (size.x + 7) / 8, (size.y + 7) / 8, 1)
		_rd.compute_list_end()
