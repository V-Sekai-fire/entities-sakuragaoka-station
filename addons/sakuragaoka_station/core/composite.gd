# src/core/renderer.js's composite pass, run in place on the colour buffer after transparents:
# colour-aware outlines from depth and normals, bloom and glow, then exposure, soft clip, grading,
# light leak and vignette.
@tool
extends CompositorEffect

const Fog := preload("res://addons/sakuragaoka_station/core/fog.gd")

const GLSL := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform ND_SAMPLER depth_tex;
layout(set = 0, binding = 2) uniform ND_SAMPLER normal_tex;
layout(set = 0, binding = 3) uniform sampler2D bloom_tex;
layout(set = 0, binding = 4) uniform sampler2D glow_tex;
layout(push_constant, std430) uniform Params {
	vec2 raster;
	float depth_a;
	float depth_b;
	vec4 sun;
	float outline;
	float grade;
	float exposure;
	float vignette;
	float bloom;
	float glow;
	float pad0;
	float pad1;
} p;

const vec3 LINE = vec3(0.0272, 0.0203, 0.0513);

#ifdef ND_MS
int nd_sample(ivec2 c) {
	int n = min(textureSamples(depth_tex), 8);
	float d[8];
	for (int i = 0; i < n; i++) {
		d[i] = texelFetch(depth_tex, c, i).r;
	}
	int best = 0;
	int votes = 0;
	for (int i = 0; i < n; i++) {
		int v = 0;
		for (int j = 0; j < n; j++) {
			v += abs(d[i] - d[j]) <= 0.01 * max(d[i], d[j]) ? 1 : 0;
		}
		if (v > votes || (v == votes && d[i] > d[best])) {
			votes = v;
			best = i;
		}
	}
	return best;
}
#else
int nd_sample(ivec2 c) {
	return 0;
}
#endif

vec4 nd(ivec2 c, out bool tagged) {
	c = clamp(c, ivec2(0), ivec2(p.raster) - 1);
	int s = nd_sample(c);
	float d = texelFetch(depth_tex, c, s).r;
	vec4 nr = texelFetch(normal_tex, c, s);
	int r = int(round(nr.a * 255.0));
	tagged = d != 0.0 && (r == 95 || r == 160);
	return vec4(d == 0.0 ? vec3(0.0, 0.0, 1.0) : normalize(nr.xyz * 2.0 - 1.0), p.depth_b / (d + p.depth_a));
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
	bool t0;
	bool tl;
	bool tr;
	bool tu;
	bool td;
	vec4 c0 = nd(c, t0);
	vec4 cl = nd(c - dx, tl);
	vec4 cr = nd(c + dx, tr);
	vec4 cu = nd(c - dy, tu);
	vec4 cd = nd(c + dy, td);
	vec4 h = vec4(0.0, 0.0, 1.0, -1.0);
	h = !t0 && c0.w > h.w ? c0 : h;
	h = !tl && cl.w > h.w ? cl : h;
	h = !tr && cr.w > h.w ? cr : h;
	h = !tu && cu.w > h.w ? cu : h;
	h = !td && cd.w > h.w ? cd : h;
	c0 = t0 ? h : c0;
	cl = tl ? h : cl;
	cr = tr ? h : cr;
	cu = tu ? h : cu;
	cd = td ? h : cd;
	float d0 = c0.w;
	float dl = cl.w;
	float dr = cr.w;
	float du = cu.w;
	float dd = cd.w;
	float i0 = 1.0 / max(d0, 0.05);
	float lap_x = abs(1.0 / max(dl, 0.05) + 1.0 / max(dr, 0.05) - 2.0 * i0) / i0;
	float lap_y = abs(1.0 / max(du, 0.05) + 1.0 / max(dd, 0.05) - 2.0 * i0) / i0;
	float d_edge = smoothstep(0.06, 0.18, max(lap_x, lap_y));
	float dmin = min(min(dl, dr), min(du, dd));
	d_edge = max(d_edge, smoothstep(0.10, 0.25, (d0 - dmin) / max(dmin, 0.05)));
	vec3 n0 = c0.xyz;
	float n_edge = max(max(1.0 - dot(n0, cl.xyz), 1.0 - dot(n0, cr.xyz)), max(1.0 - dot(n0, cu.xyz), 1.0 - dot(n0, cd.xyz)));
	n_edge = smoothstep(0.30, 0.65, n_edge);
	float fade = 1.0 - smoothstep(35.0, 190.0, min(d0, dmin));
	float edge = h.w < 0.0 ? 0.0 : max(d_edge, n_edge * 0.85) * fade * p.outline;
	col = mix(col, mix(col * vec3(0.42, 0.38, 0.5), LINE, 0.35), edge * 0.82);
	vec2 tuv = (vec2(c) + 0.5) / p.raster;
	col += texture(bloom_tex, tuv).rgb * p.bloom + texture(glow_tex, tuv).rgb * p.glow;
	if (p.grade > 0.0) {
		vec3 g = soft_clip(col * p.exposure);
		float l = lum(g);
		g = mix(g, g * vec3(0.9, 0.92, 1.1), (1.0 - smoothstep(0.08, 0.55, l)) * 0.55);
		g += vec3(0.022, 0.012, -0.012) * smoothstep(0.55, 1.0, l);
		g = mix(vec3(lum(g)), g, 1.07);
		vec2 uv = vec2(tuv.x, 1.0 - tuv.y);
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

## The original's bloom chain: a soft-knee bright pass at a quarter size, three separable 9-tap blurs,
## then a sixteenth-size glow from the blurred bloom with four more. mode 0 is the bright pass.
const BLOOM_GLSL := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D src;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D dst;
layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 dir;
	float mode;
	float pad0;
	float pad1;
	float pad2;
} p;

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	if (c.x >= int(p.size.x) || c.y >= int(p.size.y)) {
		return;
	}
	vec2 uv = (vec2(c) + 0.5) / p.size;
	vec3 o;
	if (p.mode < 0.5) {
		vec3 col = texture(src, uv).rgb;
		float l = max(col.r, max(col.g, col.b));
		float soft = clamp(l - 1.05 + 0.5, 0.0, 1.0);
		soft = soft * soft / (4.0 * 0.5 + 1e-4);
		float w = max(soft, l - 1.05) / max(l, 1e-4);
		o = min(col * w, vec3(8.0));
	} else {
		o = texture(src, uv).rgb * 0.2270270270;
		o += texture(src, uv + p.dir * 1.3846153846).rgb * 0.3162162162;
		o += texture(src, uv - p.dir * 1.3846153846).rgb * 0.3162162162;
		o += texture(src, uv + p.dir * 3.2307692308).rgb * 0.0702702703;
		o += texture(src, uv - p.dir * 3.2307692308).rgb * 0.0702702703;
	}
	imageStore(dst, c, vec4(o, 1.0));
}
"""

const CONTEXT := &"sakuragaoka_composite"

@export_range(0.0, 1.0) var outline := 1.0
@export_range(0.0, 1.0) var grade := 1.0
@export var exposure := 1.0
@export var vignette := 0.22
@export var bloom := 0.32
@export var glow := 0.14
@export var sun_dir := Vector3.UP

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _shader_ms := RID()
var _pipeline_ms := RID()
var _bloom_shader := RID()
var _bloom_pipeline := RID()
var _nearest := RID()
var _linear := RID()


static func compositor(sun: Vector3) -> Compositor:
	var fx := new()
	fx.sun_dir = sun
	var c := Compositor.new()
	c.compositor_effects = [Fog.new(), fx]
	return c


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_normal_roughness = true
	RenderingServer.call_on_render_thread(_create)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null and _shader.is_valid():
		for r in [_nearest, _linear, _bloom_shader, _shader, _shader_ms]:
			_rd.free_rid(r)


func _compile(glsl: String) -> RID:
	var src := RDShaderSource.new()
	src.source_compute = glsl
	var spirv := _rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("composite: %s" % spirv.compile_error_compute)
		return RID()
	return _rd.shader_create_from_spirv(spirv)


func _create() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	_shader = _compile(GLSL.replace("#version 450", "#version 450\n#define ND_SAMPLER sampler2D"))
	_shader_ms = _compile(GLSL.replace("#version 450", "#version 450\n#define ND_SAMPLER sampler2DMS\n#define ND_MS"))
	_bloom_shader = _compile(BLOOM_GLSL)
	if not _shader.is_valid() or not _shader_ms.is_valid() or not _bloom_shader.is_valid():
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	_pipeline_ms = _rd.compute_pipeline_create(_shader_ms)
	_bloom_pipeline = _rd.compute_pipeline_create(_bloom_shader)
	_nearest = _rd.sampler_create(RDSamplerState.new())
	var ls := RDSamplerState.new()
	ls.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ls.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	_linear = _rd.sampler_create(ls)


func _uniform(type: int, binding: int, ids: Array) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = binding
	for id in ids:
		u.add_id(id)
	return u


func _pass(src: RID, dst: RID, size: Vector2i, dir: Vector2, mode: float) -> void:
	var set := UniformSetCacheRD.get_cache(_bloom_shader, 0, [
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, [_linear, src]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [dst])])
	var bytes := PackedFloat32Array([size.x, size.y, dir.x, dir.y, mode, 0.0, 0.0, 0.0]).to_byte_array()
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _bloom_pipeline)
	_rd.compute_list_bind_uniform_set(list, set, 0)
	_rd.compute_list_set_push_constant(list, bytes, bytes.size())
	_rd.compute_list_dispatch(list, (size.x + 7) / 8, (size.y + 7) / 8, 1)
	_rd.compute_list_end()


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
	var views := buffers.get_view_count()
	var quarter := Vector2i(maxi(4, size.x >> 2), maxi(4, size.y >> 2))
	var sixteenth := Vector2i(maxi(4, size.x >> 4), maxi(4, size.y >> 4))
	var usage := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var fmt := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	for n in ["b1", "b2"]:
		buffers.create_texture(CONTEXT, n, fmt, usage, RenderingDevice.TEXTURE_SAMPLES_1, quarter, views, 1, true, false)
	for n in ["b3", "b4"]:
		buffers.create_texture(CONTEXT, n, fmt, usage, RenderingDevice.TEXTURE_SAMPLES_1, sixteenth, views, 1, true, false)
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
	var bytes := PackedFloat32Array([size.x, size.y, proj.z.z, proj.w.z,
			sun.x, sun.y, sun.z, sun.w, outline, grade, exposure, vignette, bloom, glow, 0.0, 0.0]).to_byte_array()
	var qx := Vector2(1.0 / quarter.x, 0.0)
	var qy := Vector2(0.0, 1.0 / quarter.y)
	var sxd := Vector2(1.0 / sixteenth.x, 0.0)
	var syd := Vector2(0.0, 1.0 / sixteenth.y)
	var ms := buffers.get_msaa_3d() != RenderingServer.VIEWPORT_MSAA_DISABLED
	var shader := _shader_ms if ms else _shader
	for view in views:
		var color := buffers.get_color_layer(view)
		var b := {}
		for n in ["b1", "b2", "b3", "b4"]:
			b[n] = buffers.get_texture_slice(CONTEXT, n, view, 0, 1, 1)
		_pass(color, b.b1, quarter, Vector2.ZERO, 0.0)
		_pass(b.b1, b.b2, quarter, qx, 1.0)
		_pass(b.b2, b.b1, quarter, qy, 1.0)
		_pass(b.b1, b.b2, quarter, qx * 1.5, 1.0)
		_pass(b.b2, b.b3, sixteenth, sxd, 1.0)
		_pass(b.b3, b.b4, sixteenth, syd, 1.0)
		_pass(b.b4, b.b3, sixteenth, sxd * 1.6, 1.0)
		_pass(b.b3, b.b4, sixteenth, syd * 1.6, 1.0)
		var set := UniformSetCacheRD.get_cache(shader, 0, [
				_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [color]),
				_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_nearest, buffers.get_depth_layer(view, ms)]),
				_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_nearest, buffers.get_texture_slice("forward_clustered",
						"normal_roughness_msaa" if ms else "normal_roughness", view, 0, 1, 1)]),
				_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_linear, b.b2]),
				_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, [_linear, b.b4])])
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline_ms if ms else _pipeline)
		_rd.compute_list_bind_uniform_set(list, set, 0)
		_rd.compute_list_set_push_constant(list, bytes, bytes.size())
		_rd.compute_list_dispatch(list, (size.x + 7) / 8, (size.y + 7) / 8, 1)
		_rd.compute_list_end()
