# The station build's compute, run as the compiled core/build/station_build.sgd in a Sandbox (made by
# core/slug/sandbox_util.gd, so it runs natively once a res://bintr/ translation exists) or, with no
# Sandbox or STATION_BUILD=gd, as the GDScript it ports. tools/build_check.gd compares the two.
extends RefCounted

const SandboxUtil = preload("res://addons/sakuragaoka_station/core/slug/sandbox_util.gd")
static var ELF := SandboxUtil.for_precision("res://addons/sakuragaoka_station/core/build/station_build.elf")

static var mode := "gd" if OS.get_environment("STATION_BUILD") == "gd" else "sgd"
static var reason := ""
static var _sb = null
static var _tried := false


static func sandbox():
	if not _tried:
		_tried = true
		var r := SandboxUtil.make_sandbox(null, ELF, 256, 4096, 1 << 24, {}, PackedStringArray(["terrain_grid"]))
		_sb = r.sandbox
		reason = r.reason
	return _sb


static func shutdown() -> void:
	SandboxUtil.release(_sb)
	_sb = null
	_tried = false


static func compiled() -> bool:
	return mode == "sgd" and sandbox() != null


## [H, NR] over the grid, row j along z, as float32; null when not compiled.
static func terrain_grid(xs: Array, zs: Array):
	if not compiled():
		return null
	return _sb.vmcall("terrain_grid", PackedFloat64Array(xs), PackedFloat64Array(zs))

