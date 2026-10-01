# Scores the renders tools/oracle/canvas_svg.mjs writes, in the guest kernels (core/slug/kernels.gd ->
# slug_kernels.sgd score_rgba, diff_rgba). Per key: A = <renders>/<name>.real.png (the real canvas),
# B = <name>.direct.png (the direct SVG), C = <name>.svg.png (the optimized SVG); residual d(A,C), floor d(A,B)
# and emitter error d(B,C) go to --out as JSON (score_rgba's six values each), and |A-B| x4 and |B-C| x4 to
# <name>.dab.png and <name>.dbc.png for the contact sheets. An unscored key or no kernels Sandbox is a FAIL.
#   godot --headless --path . --script res://tools/oracle/score_renders.gd -- --renders=<dir> --files=<keys.json> --out=<scores.json>
#   --files: {"<key>": "<name>.svg", ...}, as canvas_svg.mjs names each key's file
extends SceneTree

const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const SandboxUtil = preload("res://addons/sakuragaoka_station/core/slug/sandbox_util.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var renders := ""
	var files_path := ""
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--renders="):
			renders = arg.substr(10)
		elif arg.begins_with("--files="):
			files_path = arg.substr(8)
		elif arg.begins_with("--out="):
			out_path = arg.substr(6)
	if renders == "" or files_path == "" or out_path == "":
		printerr("usage: score_renders.gd -- --renders=<dir> --files=<keys.json> --out=<scores.json>")
		quit(2)
		return
	if Kernels.sandbox() == null:
		printerr("score_renders: FAIL (no kernels Sandbox: %s)" % Kernels.reason)
		quit(1)
		return
	var files = JSON.parse_string(FileAccess.get_file_as_string(files_path))
	if not files is Dictionary:
		printerr("score_renders: FAIL (%s is not a JSON object)" % files_path)
		quit(1)
		return
	var result := {}
	var fails := 0
	var t0 := Time.get_ticks_msec()
	for key in files:
		var base: String = renders.path_join(String(files[key]).get_basename())
		var px := []
		var size := Vector2i(-1, -1)
		for tag in ["real", "direct", "svg"]:
			var img := Image.load_from_file(base + "." + tag + ".png")
			if img == null or (size.x >= 0 and img.get_size() != size):
				break
			img.convert(Image.FORMAT_RGBA8)
			size = img.get_size()
			px.append(img.get_data())
		if px.size() != 3:
			result[key] = {"error": "renders missing or of different sizes"}
			fails += 1
			continue
		var residual := Kernels.score_rgba(px[0], px[2], size.x, size.y)
		var flr := Kernels.score_rgba(px[0], px[1], size.x, size.y)
		var emitter := Kernels.score_rgba(px[1], px[2], size.x, size.y)
		if residual.size() != 6 or flr.size() != 6 or emitter.size() != 6:
			result[key] = {"error": "score_rgba returned no answer"}
			fails += 1
			continue
		result[key] = {"residual": residual, "floor": flr, "emitter": emitter}
		for d in [["dab", px[0], px[1]], ["dbc", px[1], px[2]]]:
			var bytes := Kernels.diff_rgba(d[1], d[2])
			Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes).save_png(base + "." + d[0] + ".png")
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "", true, true))
	f.close()
	print("score_renders: %d keys, %d failed, in %d ms; kernels %s" % [files.size(), fails, Time.get_ticks_msec() - t0,
			"binary-translated" if SandboxUtil.translated else "interpreted (no res://bintr/ library)"])
	Kernels.shutdown()
	quit(1 if fails > 0 else 0)
