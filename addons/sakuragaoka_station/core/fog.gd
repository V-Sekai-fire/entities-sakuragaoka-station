# The original's scene fog, FogExp2: 1 - exp(-(density * view depth)^2) toward the fog colour, applied
# exactly to opaque surfaces after the sky is drawn, since Godot's fog modes have no squared exponential.
# A material that fogs itself writes roughness 0, and its pixels are skipped.
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
	float depth_a;
	float depth_b;
	vec4 fog;
} p;

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	if (c.x >= int(p.raster.x) || c.y >= int(p.raster.y)) {
		return;
	}
	float d = texelFetch(depth_tex, c, 0).r;
	float r = texelFetch(normal_tex, c, 0).a;
	if (d == 0.0 || r < 0.25 || r > 0.75) {
		return;
	}
	float z = p.depth_b / (d + p.depth_a);
	float f = 1.0 - exp(-p.fog.a * p.fog.a * z * z);
	vec4 src = imageLoad(color_image, c);
	imageStore(color_image, c, vec4(mix(src.rgb, p.fog.rgb, f), src.a));
}
"""

@export var colour := Color("#cfdcec")
@export var density := 0.0026

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _sampler := RID()


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_SKY
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
		push_error("fog: %s" % spirv.compile_error_compute)
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
	var lin := colour.srgb_to_linear()
	var pc := PackedFloat32Array([size.x, size.y, proj.z.z, proj.w.z, lin.r, lin.g, lin.b, density])
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
