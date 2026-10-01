# The original's shadow probes counted for tools/oracle/calib_probe.mjs in the guest kernel probe_read: each pass's
# frame (<file>.zst, RGBA as read back, bottom row first) and screen quads (<file>.f64) to [pixels, hidden, lowest
# red, highest red] per quad, written to --out as {"<file>": [...]}. No kernels Sandbox is a FAIL.
#   godot --headless --path . --script res://tools/oracle/probe_read.gd -- --passes=<passes.json> --out=<reads.json>
extends SceneTree

const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		if s.begins_with("--") and "=" in s:
			a[s.substr(2, s.find("=") - 2)] = s.substr(s.find("=") + 1)
	if not a.has("passes") or not a.has("out"):
		printerr("usage: probe_read.gd -- --passes=<passes.json> --out=<reads.json>")
		quit(2)
		return
	if Kernels.sandbox() == null:
		printerr("probe_read: FAIL no kernels Sandbox (%s)" % Kernels.reason)
		quit(1)
		return
	var passes = JSON.parse_string(FileAccess.get_file_as_string(a.passes))
	var dir: String = str(a.passes).get_base_dir()
	var out := {}
	var fails := 0
	for p in passes:
		var w := int(p.w)
		var h := int(p.h)
		var px := FileAccess.get_file_as_bytes(dir.path_join(p.file + ".zst")).decompress(w * h * 4, FileAccess.COMPRESSION_ZSTD)
		var quads := FileAccess.get_file_as_bytes(dir.path_join(p.file + ".f64")).to_float64_array()
		if px.size() != w * h * 4 or quads.size() % 18 != 0:
			printerr("probe_read: FAIL %s: the frame or its quads are cut short" % p.file)
			fails += 1
			continue
		out[p.file] = Array(Kernels.probe_read(px, w, h, quads))
	var f := FileAccess.open(a.out, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("probe_read: %d passes, %d failed" % [passes.size(), fails])
	Kernels.shutdown()
	quit(1 if fails > 0 else 0)
