# The compiled build kernels (core/build/station_build.sgd) against the GDScript they port: each module
# is built once per mode at a seed, every mesh's attributes, index and instance transforms are hashed in
# traversal order, and the two hashes must agree. Controls: the seed perturbed (the hash must move) and
# one terrain grid z nudged by 1 mm (the kernel's answer must move).
#   godot --headless --path . --script tools/build_check.gd -- [--seed N] [--modules environment]
extends SceneTree

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const BuildKernels = preload("res://addons/sakuragaoka_station/core/build/build_kernels.gd")
const SandboxUtil = preload("res://addons/sakuragaoka_station/core/slug/sandbox_util.gd")

var _fails := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := 1
	var modules := PackedStringArray(["environment"])
	for i in args.size():
		if args[i] == "--seed":
			seed = int(args[i + 1])
		elif args[i] == "--modules":
			modules = args[i + 1].split(",")
	BuildKernels.mode = "sgd"
	if BuildKernels.sandbox() == null:
		print("FAIL no compiled kernels: ", BuildKernels.reason)
		quit(1)
		return
	print("guest %s, native translation %s" % [BuildKernels.ELF.get_file(), SandboxUtil.translated])
	print("%-12s %10s %10s %6s  %s" % ["module", "gd ms", "sgd ms", "same", "hash"])
	var hashes := {}
	for n in modules:
		var a := _build(n, seed, "gd")
		var b := _build(n, seed, "sgd")
		var same: bool = a.hash == b.hash
		if not same:
			_fails += 1
		hashes[n] = a.hash
		print("%-12s %10d %10d %6s  %s" % [n, a.ms, b.ms, same, a.hash if same else "%s != %s" % [a.hash, b.hash]])
	for n in modules:
		var c := _build(n, seed + 1, "sgd")
		var moved: bool = c.hash != hashes[n]
		print("control seed %d %-12s hash moved: %s" % [seed + 1, n, moved])
		if not moved and n != "environment":
			_fails += 1
	var xs := [0.0, 10.0, 200.0, 400.0]
	var zs := [-150.0, -100.0, 0.0, 300.0]
	var g0 = BuildKernels.terrain_grid(xs, zs)
	zs[1] += 0.001
	var g1 = BuildKernels.terrain_grid(xs, zs)
	var nudged := var_to_bytes(g0) != var_to_bytes(g1)
	print("control terrain z +1 mm, kernel answer moved: %s" % nudged)
	if not nudged:
		_fails += 1
	print("PASS" if _fails == 0 else "FAIL %d" % _fails)
	BuildKernels.shutdown()
	quit(1 if _fails else 0)


func _build(n: String, seed: int, mode: String) -> Dictionary:
	BuildKernels.mode = mode
	var ctx = Ctx.new(seed)
	var t0 := Time.get_ticks_msec()
	load("res://addons/sakuragaoka_station/world/%s.gd" % n).new().build(ctx)
	var ms := Time.get_ticks_msec() - t0
	var buf := PackedByteArray()
	ctx.scene.traverse(func(o):
		buf.append_array(o.name.to_utf8_buffer())
		if o.get("geometry") != null:
			var g = o.geometry
			for k in g.attributes:
				buf.append_array(k.to_utf8_buffer())
				buf.append_array(g.attributes[k].array.to_byte_array())
			buf.append_array(g.index.to_byte_array())
		if o.get("instance_matrix") != null:
			buf.append_array(var_to_bytes(o.instance_matrix)))
	buf.append_array(ctx.physics.prims.to_byte_array())
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(buf)
	return {"ms": ms, "hash": hc.finish().hex_encode().left(16), "bytes": buf.size()}
