# Per-view full-resolution MAD split into sky pixels (tools/sky_mask.gd's mask) and the rest, through
# Kernels.frame_diff, for each comparison given as label=a,b,mask with %d standing for the view.
#   godot --headless --path . --script tools/sky_split.gd -- --views=8 --cmp="<label>=<a_%d.png>,<b_%d.png>,<mask_%d.png>" ... [--json=<file>]
extends SceneTree

const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const MAGENTA := 0xff00ff

var _cmps := []
var _a := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cmp="):
			var s := a.substr(6)
			var eq := s.find("=")
			_cmps.append({"label": s.substr(0, eq), "paths": s.substr(eq + 1).split(",")})
		elif a.begins_with("--") and "=" in a:
			_a[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	_run.call_deferred()


static func _rgb(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var im := Image.load_from_file(path)
	im.convert(Image.FORMAT_RGB8)
	return im.get_data()


func _run() -> void:
	var views := int(_a.get("views", "8"))
	var res := {"note": "MAD 0..255 over the RGB channels of sky pixels (the port's mask) and of the rest, full resolution", "comparisons": []}
	print("sky_split: comparison | view | sky fraction | sky MAD | non-sky MAD | full MAD | pixels that differ (max)")
	var failed := 0
	for c in _cmps:
		var e := {"label": c.label, "views": []}
		for v in views:
			var a := _rgb(c.paths[0] % v)
			var b := _rgb(c.paths[1] % v)
			var m := _rgb(c.paths[2] % v)
			if a.is_empty() or b.is_empty() or m.size() != a.size() or a.size() != b.size():
				print("sky_split: FAIL %s view %d: a frame or the mask is missing or a different size" % [c.label, v])
				failed += 1
				continue
			var r := Kernels.frame_diff(a, b, m, MAGENTA)
			var sky := float(r[0]) / maxf(r[1], 1.0)
			var rest := float(r[2]) / maxf(r[3], 1.0)
			var full := float(r[0] + r[2]) / float(r[1] + r[3])
			var frac := float(r[1]) / float(r[1] + r[3])
			e.views.append({"view": v, "sky_fraction": frac, "sky_mad": sky, "non_sky_mad": rest, "full_mad": full, "pixels_differ": r[4], "max": r[5]})
			print("sky_split: %-36s | %d | %.3f | %6.2f | %6.2f | %6.2f | %d (%d)" % [c.label, v, frac, sky, rest, full, r[4], r[5]])
		res.comparisons.append(e)
	Kernels.shutdown()
	if _a.has("json"):
		var f := FileAccess.open(_a.json, FileAccess.WRITE)
		f.store_string(JSON.stringify(res, " "))
		f.close()
		print("sky_split: saved ", _a.json)
	quit(1 if failed > 0 else 0)
