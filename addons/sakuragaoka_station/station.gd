# Sakuragaoka Station as a node: builds the ported world modules at a seed into the port's scene
# graph, then realizes them under itself, in metres with Y up at the original's coordinates.
# Modules not yet ported are left out, and stats.modules names the ones built.
extends Node3D

signal built(stats: Dictionary)

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const Realize = preload("res://addons/sakuragaoka_station/core/realize.gd")
const SKY := preload("res://addons/sakuragaoka_station/core/sky.gdshader")
const Composite := preload("res://addons/sakuragaoka_station/core/composite.gd")

@export var world_seed := 1
@export var modules := PackedStringArray(["environment", "station", "plaza", "sakura"])
## src/core/sky.js's light: the dome, the sun, the hemisphere light's mean as ambient, and fog.
@export var with_environment := true

var stats := {}
var sun_dir := Vector3.UP


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var ctx = Ctx.new(world_seed)
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
