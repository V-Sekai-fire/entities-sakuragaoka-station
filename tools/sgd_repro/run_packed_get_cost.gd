# godot --headless --path . --script tools/sgd_repro/run_packed_get_cost.gd
# (compile first: gdscript_to_riscv -o tools/sgd_repro/packed_get_cost.elf tools/sgd_repro/packed_get_cost.sgd)
extends SceneTree
const SandboxUtil = preload("res://addons/sakuragaoka_station/core/slug/sandbox_util.gd")
const N := 200000

func g_scalar(n: int) -> int:
	var s := 0
	for i in n:
		s += (i * i) % 7
	return s

func g_sum(v: PackedFloat32Array) -> float:
	var s := 0.0
	for i in v.size():
		s += v[i]
	return s

func g_fill(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = float(i)
	return out

func g_copy_vec2(v: PackedFloat32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(v.size() / 2)
	for i in out.size():
		out[i] = Vector2(v[i * 2], v[i * 2 + 1])
	return out

func _t(label: String, f: Callable) -> int:
	var t0 := Time.get_ticks_usec()
	f.call()
	return Time.get_ticks_usec() - t0

func _initialize():
	var r := SandboxUtil.make_sandbox(null, "res://tools/sgd_repro/packed_get_cost.elf", 256, 4096, 1 << 24)
	if r.sandbox == null:
		print("packed_get_cost: ", r.reason)
		quit(1)
		return
	var sb = r.sandbox
	var v := PackedFloat32Array()
	v.resize(N)
	v.fill(1.0)
	print("packed_get_cost: N = %d elements, binary translation %s" % [N, SandboxUtil.translated])
	for c in [["scalar loop (10 N)", func(): g_scalar(N * 10), func(): sb.vmcall("scalar", N * 10)],
			["sum of a PackedFloat32Array", func(): g_sum(v), func(): sb.vmcall("sum", v)],
			["fill a PackedFloat32Array", func(): g_fill(N), func(): sb.vmcall("fill", N)],
			["floats -> PackedVector2Array", func(): g_copy_vec2(v), func(): sb.vmcall("copy_vec2", v)]]:
		var tg := _t(c[0], c[1])
		var ts := _t(c[0], c[2])
		print("packed_get_cost: %-30s .gd %8d us   .sgd %8d us   (.sgd / .gd %.2f)" % [c[0], tg, ts, float(ts) / tg])
	quit()
