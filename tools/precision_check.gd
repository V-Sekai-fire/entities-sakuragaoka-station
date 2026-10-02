# The guests' precision gate: each guest's build the station picks (SandboxUtil.for_precision) loads
# here and the other real_t's is refused (the Sandbox logs why); --control=swap picks the other and FAILs.
#   godot --headless --path . --script tools/precision_check.gd -- [--control=swap]
extends SceneTree

const SandboxUtil = preload("res://addons/sakuragaoka_station/core/slug/sandbox_util.gd")
const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")

var _fails := 0


func _try(elf: String, required: Array, expect_loads: bool) -> void:
	var r := SandboxUtil.make_sandbox(null, elf, Guest.MEM_MB, Guest.REFS, Guest.TIMEOUT_UNITS, {}, PackedStringArray(required))
	var loads: bool = r.sandbox != null
	SandboxUtil.release(r.sandbox)
	if loads != expect_loads:
		_fails += 1
	print("precision_check: %-26s %-7s expected %-7s %s%s" % [elf.get_file(), "loads" if loads else "refused",
			"loads" if expect_loads else "refused", "ok" if loads == expect_loads else "FAIL",
			"" if loads else "  (%s)" % r.reason])


func _initialize() -> void:
	var swap := "--control=swap" in OS.get_cmdline_user_args()
	var double := OS.has_feature("double")
	print("precision_check: %s-precision engine%s" % ["double" if double else "single", ", control: swap" if swap else ""])
	for g in [[Guest.ELF, Guest.SINGLE_ELF, Guest.REQUIRED], [Kernels.ELF, Kernels.SINGLE_ELF, []]]:
		var picked: String = g[0]
		var other := SandboxUtil.for_precision(g[1], not double)
		if picked == other:
			_fails += 1
			print("precision_check: FAIL %s is the other real_t's build" % picked.get_file())
		if swap:
			var t := picked
			picked = other
			other = t
		_try(picked, g[2], true)
		_try(other, g[2], false)
	print("precision_check: RESULT %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
