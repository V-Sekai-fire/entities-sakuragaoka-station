# The sakura canopy round's gates and controls over the 8 Hammersley views (MAD 0..255, full resolution):
# every view at or below its 1f87734 value; and per extend() control, the port's move against the move
# predicted from the original's own response to the same switch, both with the blossom cards hidden:
#   predicted = MAD(clamp(after + (original_nocards_off - original_nocards)), original) - MAD(after, original)
# within max(0.1, 25 %) of the measured move. Publishes toon-ramp-canopy-NN.
#   godot --path . --resolution 1920x1080 --script tools/toon_ramp_canopy.gd -- --original=<prefix>
#       --original2=<prefix> --nocards=<prefix> --before=<dir> --after=<dir> --after2=<dir>
#       --port-controls=<dir with %s> --orig-controls=<cards-hidden prefix with %s> [--controls=oct,...] [--out=<dir>]
extends SceneTree

const Sheet = preload("res://tools/sheet.gd")
const CELL := Vector2i(384, 216)

var _a := {}
var _fails := PackedStringArray()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_a[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("toon_ramp_canopy: %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


static func _img(path: String):
	if not FileAccess.file_exists(path):
		return null
	var i := Image.load_from_file(path)
	i.convert(Image.FORMAT_RGB8)
	return i


static func _mad(a: PackedByteArray, b: PackedByteArray) -> float:
	var s := 0
	for i in a.size():
		s += absi(a[i] - b[i])
	return float(s) / a.size()


## MAD(clamp(base + (to - from)), ref): base moved by another render pair's difference, against ref.
static func _moved(base: PackedByteArray, from: PackedByteArray, to: PackedByteArray, ref: PackedByteArray) -> float:
	var s := 0
	for i in base.size():
		s += absi(clampi(base[i] + to[i] - from[i], 0, 255) - ref[i])
	return float(s) / base.size()


func _run() -> void:
	var o: String = _a.get("original", "")
	var controls: PackedStringArray = str(_a.get("controls", "oct,wobble,speck,rim,shade,dapple")).split(",")
	var res := {"views": [], "controls": {}}
	var rows := []
	for c in controls:
		res.controls[c] = []
	var v := 0
	while FileAccess.file_exists("%s_%d.png" % [o, v]):
		var orig: Image = _img("%s_%d.png" % [o, v])
		var od := orig.get_data()
		var rgb := func(path: String):
			var i = _img(path)
			return i.get_data() if i != null else null
		var before = rgb.call(str(_a.get("before", "")).path_join("port-view_%d.png" % v))
		var after = rgb.call(str(_a.get("after", "")).path_join("port-view_%d.png" % v))
		var after2 = rgb.call(str(_a.get("after2", "")).path_join("port-view_%d.png" % v))
		var o2 = rgb.call("%s_%d.png" % [_a.get("original2", ""), v])
		var nc = rgb.call("%s_%d.png" % [_a.get("nocards", ""), v])
		var e := {"view": v, "before": _mad(before, od) if before != null else -1.0, "after": _mad(after, od),
				"floor_original": _mad(o2, od) if o2 != null else -1.0, "floor_after": _mad(after2, after) if after2 != null else -1.0,
				"after_vs_nocards": _mad(after, nc) if nc != null else -1.0}
		if before != null:
			_check(e.after <= e.before, "view %d at or below its 1f87734 value: %.2f -> %.2f" % [v, e.before, e.after])
		for c in controls:
			var pc = rgb.call((str(_a.get("port-controls", "")) % c).path_join("port-view_%d.png" % v))
			var oc = rgb.call("%s_%d.png" % [str(_a.get("orig-controls", "")) % c, v])
			if pc == null or oc == null or nc == null:
				_check(false, "control %s view %d: renders missing" % [c, v])
				continue
			var meas: float = _mad(pc, od) - e.after
			var pred: float = _moved(after, nc, oc, od) - e.after
			var r := {"view": v, "measured": meas, "predicted": pred, "port_response": _mad(pc, after), "original_response": _mad(oc, nc),
					"response_difference": _moved(pc, after, nc, oc)}
			res.controls[c].append(r)
		res.views.append(e)
		var heat := Sheet.heat(Image.create_from_data(orig.get_width(), orig.get_height(), false, Image.FORMAT_RGB8, after), orig)
		rows.append({"after": e.after, "label": "view %d   1f87734 %.2f -> after %.2f (gate <= %.2f)   floors: original %.2f, port %.2f   after vs original without cards %.2f" % [
				v, e.before, e.after, e.before, e.floor_original, e.floor_after, e.after_vs_nocards], "cells": [
			{"image": orig, "label": "original"},
			{"image": _img(str(_a.get("before", "")).path_join("port-view_%d.png" % v)), "label": "port at 1f87734: %.2f" % e.before},
			{"image": _img(str(_a.get("after", "")).path_join("port-view_%d.png" % v)), "label": "toon ramp + extend(): %.2f" % e.after},
			{"image": heat, "label": "|after - original|"}]})
		v += 1
	var tol := func(p: float) -> float: return maxf(0.1, 0.25 * absf(p))
	for c in controls:
		var worst := 0.0
		var lines := PackedStringArray()
		for r in res.controls[c]:
			worst = maxf(worst, absf(r.measured - r.predicted) / tol.call(r.predicted))
			lines.append("%d: %+.2f / %+.2f" % [r.view, r.measured, r.predicted])
		print("toon_ramp_canopy: control %-6s view: measured / predicted move  %s" % [c, "  ".join(lines)])
		if not res.controls[c].is_empty():
			_check(worst <= 1.0, "control %s: every view moves as predicted, within max(0.1, 25 %%) (worst %.2f of it)" % [c, worst])
	var sb := 0.0
	var sa := 0.0
	for e in res.views:
		sb += e.before
		sa += e.after
	var n := maxf(res.views.size(), 1)
	res["mean"] = {"before": sb / n, "after": sa / n}
	print("toon_ramp_canopy: mean of %d views: 1f87734 %.2f -> after %.2f" % [res.views.size(), sb / n, sa / n])
	var out: String = _a.get("out", "user://toon_ramp_canopy")
	DirAccess.make_dir_recursive_absolute(out)
	res["fails"] = _fails
	var f := FileAccess.open(out.path_join("toon_ramp_canopy.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(res, " "))
	f.close()
	rows.sort_custom(func(x, y): return x.after > y.after)
	var img: Image = await Sheet.render(self, "Toon ramp + sakura extend(): 8 views, MAD 0..255 full resolution, 1f87734 %.2f -> %.2f mean" % [sb / n, sa / n],
			["original", "port 1f87734", "port after", "|after - original|"], rows, CELL)
	for p in Sheet.publish(img, out.path_join("toon-ramp-canopy-sheet.png"), "toon-ramp-canopy"):
		print("toon_ramp_canopy: saved ", p)
	print("toon_ramp_canopy: %s (%d failed)" % ["ALL PASS" if _fails.is_empty() else "FAILED", _fails.size()])
	quit(0 if _fails.is_empty() else 1)
