# Sakuragaoka Station as a node: builds the ported world modules at a seed into the port's scene
# graph, then realizes them under itself, in metres with Y up at the original's coordinates.
# Modules not yet ported are left out, and stats.modules names the ones built.
extends Node3D

signal built(stats: Dictionary)

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Realize = preload("res://addons/sakuragaoka_station/core/realize.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const Quality = preload("res://addons/sakuragaoka_station/core/quality.gd")
const SKY := preload("res://addons/sakuragaoka_station/core/sky.gdshader")
const Composite := preload("res://addons/sakuragaoka_station/core/composite.gd")
const PetalShaders = preload("res://addons/sakuragaoka_station/world/petals/shaders.gd")

@export var world_seed := 1
@export var modules := PackedStringArray(["environment", "station", "plaza", "sakura"])
## src/core/sky.js's light: the dome, the sun, the hemisphere light's mean as ambient, and fog.
@export var with_environment := true
## The original's ?q= level (core/quality.gd): high is its desktop default, MSAA 4x.
@export_enum("high", "medium", "low") var quality := "high"
## main.js's clock in seconds for the shaders that move by it; below 0 it runs in real time. A fixed
## value matches the original's shot.mjs --t.
@export var clock := -1.0

var stats := {}
var sun_dir := Vector3.UP
## The build context, kept so a walker can read ctx.physics's colliders after `built`.
var ctx
var _sun: DirectionalLight3D
var _fed := []
var _live: Array = []
var _time := 0.0


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
		ctx.sky = {"sun": {"color": T.color("#fff0dc"), "intensity": 2.75},
			"hemi": {"color": T.color("#a9b3ee"), "groundColor": T.color("#d9c6c8"), "intensity": 1.62}}
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
	_live = r.live_shaders
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


func _process(delta: float) -> void:
	if _sun != null:
		_feed_sun()
	if not _live.is_empty():
		_animate(delta)


## main.js's clock for the shaders that move by it (the petals): uTime, the core's gust, the petals'
## per-frame update (train slots, drawing-buffer height), then their uniforms.
func _animate(delta: float) -> void:
	_time += delta
	var t := _time if clock < 0.0 else clock
	ctx.time = t
	ctx.shared["uTime"] = t
	ctx.shared["uGust"] = 0.5 + 0.28 * sin(t * 0.37) + 0.14 * sin(t * 1.13 + 1.7) + 0.08 * sin(t * 2.9 + 0.4)
	var p = ctx.services.get("petals")
	if p != null and p.get("update") != null:
		p.update.call(delta, t)
	var res_y := maxf(240.0, get_viewport().get_visible_rect().size.y)
	for pair in _live:
		PetalShaders.update(pair[0], pair[1])
		pair[0].set_shader_parameter("uResY", res_y)


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
