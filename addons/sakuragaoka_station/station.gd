# Sakuragaoka Station as a node: builds the ported world modules at a seed into the port's scene
# graph, then realizes them under itself, in metres with Y up at the original's coordinates.
# Modules not yet ported are left out, and stats.modules names the ones built.
extends Node3D

signal built(stats: Dictionary)

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const Realize = preload("res://addons/sakuragaoka_station/core/realize.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const Quality = preload("res://addons/sakuragaoka_station/core/quality.gd")
const SKY := preload("res://addons/sakuragaoka_station/core/sky.gdshader")
const Composite := preload("res://addons/sakuragaoka_station/core/composite.gd")

@export var world_seed := 1
@export var modules := PackedStringArray(["environment", "station", "plaza", "sakura"])
## src/core/sky.js's light: the dome, the sun, the hemisphere light's mean as ambient, and fog.
@export var with_environment := true
## The original's ?q= level (core/quality.gd): high is its desktop default, MSAA 4x.
@export_enum("high", "medium", "low") var quality := "high"
## DirectionalLight3D properties set after the shadow map is fitted; a max distance or blur given here
## is fitted around, and shadow_normal_bias_scale scales the fitted normal bias.
@export var shadow_overrides := {}

## sky.js's shadow: normalBias along the normal, and bias over its shadow camera's far - near, metres.
const SHADOW_NORMAL_BIAS := 0.035
const SHADOW_DEPTH_BIAS := 0.00035 * (520.0 - 1.0)
const SHADOW_BLUR := 0.866

var stats := {}
var sun_dir := Vector3.UP
var shadow_setup := {}
## The build context, kept so a walker can read ctx.physics's colliders after `built`.
var ctx
var _sun: DirectionalLight3D
var _fed := []
var _fit := []


## The canvas-texture Sandboxes (slug.elf, slug_kernels.elf) go with the station.
func _exit_tree() -> void:
	Kernels.shutdown()
	Guest.shutdown()


func _ready() -> void:
	Quality.apply(get_viewport(), quality)
	var t0 := Time.get_ticks_msec()
	ctx = Ctx.new(world_seed)
	sun_dir = ctx.sun_dir
	if with_environment:
		_environment()
	var done := PackedStringArray()
	for n in modules:
		var path := "res://addons/sakuragaoka_station/world/%s.gd" % n
		if ResourceLoader.exists(path):
			load(path).new().build(ctx)
			done.append(n)
	var t1 := Time.get_ticks_msec()
	var r = Realize.new()
	r.realize(ctx, self)
	await get_tree().process_frame
	await get_tree().process_frame
	r.finish()
	stats = r.stats.merged({"modules": done, "build_ms": t1 - t0, "realize_ms": Time.get_ticks_msec() - t1})
	print("station: %s built in %d ms, realized in %d ms" % [",".join(done), stats.build_ms, stats.realize_ms])
	built.emit(stats)


## The light's direction and LIGHT_COLOR (linear, in float64 as three.js forms it) as the shader globals
## core/ramp/mtoon_ramp_sakura.gdshaderinc lights from.
func _feed_sun() -> void:
	var z := _sun.global_transform.basis.z.normalized()
	var lc := _sun.light_color
	var c := Vector3(_lin(lc.r), _lin(lc.g), _lin(lc.b)) * (_sun.light_energy * PI)
	var now := [z, c]
	if now == _fed:
		return
	_fed = now
	RenderingServer.global_shader_parameter_set("ramp_sun_dir", z)
	RenderingServer.global_shader_parameter_set("ramp_sun_color", c)


static func _lin(x: float) -> float:
	return x / 12.92 if x <= 0.04045 else pow((x + 0.055) / 1.055, 2.4)


func _process(_delta: float) -> void:
	if _sun != null:
		_feed_sun()
		_fit_shadow()


## The original's one +-S box as Godot's one orthogonal map: the max distance whose bounding radius
## of the camera frustum is S gives its texel, 2S / map, and both biases keep its world lengths.
func _fit_shadow() -> void:
	var cam := get_viewport().get_camera_3d()
	var fov := cam.fov if cam != null else 58.0
	var near := cam.near if cam != null else 0.1
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var now := [fov, near, aspect, shadow_overrides.duplicate()]
	if now == _fit:
		return
	_fit = now
	var q: Dictionary = Quality.level(quality)
	var map: int = q.shadow_map
	var d: float = shadow_overrides.get("directional_shadow_max_distance", shadow_distance(q.shadow_size, fov, aspect, near, map))
	var r := shadow_radius(d, fov, aspect, near, map)
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = d
	_sun.directional_shadow_fade_start = 0.999
	_sun.shadow_blur = shadow_overrides.get("shadow_blur", SHADOW_BLUR)
	_sun.shadow_normal_bias = SHADOW_NORMAL_BIAS / (2.0 * r / map) * shadow_overrides.get("shadow_normal_bias_scale", 1.0)
	_sun.shadow_bias = SHADOW_DEPTH_BIAS / (0.01 * (2.0 * r + _sun.directional_shadow_pancake_size) * _sun.shadow_blur * Quality.FILTER_RADIUS)
	for k in shadow_overrides:
		if not k in ["directional_shadow_max_distance", "shadow_blur", "shadow_normal_bias_scale"]:
			_sun.set(k, shadow_overrides[k])
	shadow_setup = {"max_distance": d, "radius": r, "texel": 2.0 * r / map, "map": map, "blur": _sun.shadow_blur,
		"normal_bias": _sun.shadow_normal_bias, "bias": _sun.shadow_bias, "filter": Quality.FILTER, "camera": [fov, aspect, near]}


## Godot's bounding radius of the camera frustum from near to d, a texel added each side
## (renderer_scene_cull.cpp, _light_instance_setup_directional_shadow).
static func shadow_radius(d: float, fov: float, aspect: float, near: float, map: int) -> float:
	var ty := tan(deg_to_rad(fov) * 0.5)
	var tx := ty * aspect
	return sqrt(d * d * (tx * tx + ty * ty) + 0.25 * (d - near) * (d - near)) * map / (map - 2.0)


## The max distance whose bounding radius is s.
static func shadow_distance(s: float, fov: float, aspect: float, near: float, map: int) -> float:
	var ty := tan(deg_to_rad(fov) * 0.5)
	var tx := ty * aspect
	var a := tx * tx + ty * ty + 0.25
	var t := s * (map - 2.0) / map
	return (0.5 * near + sqrt(0.25 * near * near - 4.0 * a * (0.25 * near * near - t * t))) / (2.0 * a)


## three.js divides a light's irradiance by pi where Godot folds pi into the light, so the original's
## intensities 2.75 (sun) and 1.62 (hemisphere) become 2.75 / pi and 1.62 / pi here. Its FogExp2 is
## core/fog.gd in the compositor, since Godot's own fog has no squared exponential.
func _environment() -> void:
	var sm := ShaderMaterial.new()
	sm.shader = SKY
	sm.set_shader_parameter("sun_dir", sun_dir)
	var sky := Sky.new()
	sky.sky_material = sm
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a9b3ee").lerp(Color("#d9c6c8"), 0.5)
	env.ambient_light_energy = 1.62 / PI
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.name = "SkyAndFog"
	we.environment = env
	we.compositor = Composite.compositor(sun_dir)
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("#fff0dc")
	sun.light_energy = 2.75 / PI
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP)
	_sun = sun
	_feed_sun()
	_fit_shadow()
