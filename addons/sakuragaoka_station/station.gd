# Sakuragaoka Station as a node: builds the ported world modules at a seed into the port's scene
# graph, then realizes them under itself, in metres with Y up at the original's coordinates.
# Modules not yet ported are left out, and stats.modules names the ones built.
extends Node3D

signal built(stats: Dictionary)

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const Realize = preload("res://addons/sakuragaoka_station/core/realize.gd")

@export var world_seed := 1
@export var modules := PackedStringArray(["environment", "station", "plaza", "sakura"])

var stats := {}
var sun_dir := Vector3.UP


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var ctx = Ctx.new(world_seed)
	sun_dir = ctx.sun_dir
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
