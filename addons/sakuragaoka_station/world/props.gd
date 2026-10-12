# props.js: all vending machines (+ recycle bins, crates, flag, sticker), the E6 neighbourhood shrine
# (torii, hokora, foxes, jizo, ema, chōzubachi, lanterns, notice board), the V5 bench, gashapon,
# 防災倉庫, fire-extinguisher boxes, traffic cones + repair notice on R4, and a garbage station.
extends RefCounted

const Common = preload("res://addons/sakuragaoka_station/world/props/common.gd")
const Vending = preload("res://addons/sakuragaoka_station/world/props/vending.gd")
const Shrine = preload("res://addons/sakuragaoka_station/world/props/shrine.gd")
const Scatter = preload("res://addons/sakuragaoka_station/world/props/scatter.gd")
const Optimize = preload("res://addons/sakuragaoka_station/world/props/optimize.gd")


## Returns null, or the error that stopped the build (as the original throws).
func build(ctx):
	var H = Common.make_helpers(ctx)
	var before := {}
	for c in ctx.static_root.children:
		before[c] = true
	var parts := [["vending", Vending.build_vending], ["shrine", Shrine.build_shrine], ["scatter", Scatter.build_scatter]]
	var errors := []
	for p in parts:
		var err = p[1].call(ctx, H)
		if err is String:
			errors.append(p[0])
			push_error("[props/%s] %s" % [p[0], err])
	# collapse materials (texture atlas pages + vertex-coloured solids) so the batcher can merge per cell
	var mine := []
	for c in ctx.static_root.children:
		if not before.has(c):
			mine.append(c)
	Optimize.optimize_props(ctx, mine)
	if not errors.is_empty():
		return "props: failed parts " + ", ".join(errors)
	return null
