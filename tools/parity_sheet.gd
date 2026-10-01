# The Hammersley parity contact sheet with its floors (residual ladder rung 0): one row per view,
# worst (highest after-residual) first, columns original (tools/oracle/shot.mjs) | port before |
# port after | |after - original| heat map. Each row's label carries the residual MAD before and
# after (realize_check's measure: half size, RGB8, every 7th byte) and the two floors:
#   floor orig  the original against a second shot.mjs render with identical arguments
#   floor port  the port against a second render of the same commit and settings
# and the table printed (and drawn as the sheet's title block) is
#   view | floor orig | floor port (before, after) | residual HEAD | residual feat/slug
# plus, for the floors, how many pixels differ at all and the largest channel difference at full
# size, so "zero" means byte-identical rather than below the measure's subsampling.
#   godot --path . --script tools/parity_sheet.gd -- --original=<prefix> --original2=<prefix>
#       --before=<dir> --before2=<dir> --after=<dir> --after2=<dir> [--out=<png>]
# <prefix>_<i>.png are the originals; <dir>/port-view_<i>.png the port renders (realize_check
# --shots). The *2 arguments are optional; without them the floors read "n/a". --out defaults to
# <after>/parity-contact-sheet.png; the sheet is also copied to the desktop (Sheet.publish) as
# <topic>-NN.png (--topic, default parity-hammersley). For other comparisons (one port render
# against another) --names=a,b,c renames the three image columns (default original, HEAD,
# feat/slug) and --title the sheet.
extends SceneTree

const Sheet = preload("res://tools/sheet.gd")
const CELL := Vector2i(480, 270)

var _a := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			_a[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	_make.call_deferred()


static func _img(path: String):
	return Image.load_from_file(path) if path != "" and FileAccess.file_exists(path) else null


## Full-size exactness: [differing pixels, largest channel difference 0..255].
static func _exact(a: Image, b: Image) -> Vector2i:
	var x: Image = a.duplicate()
	var y: Image = b.duplicate()
	x.convert(Image.FORMAT_RGB8)
	y.convert(Image.FORMAT_RGB8)
	var da := x.get_data()
	var db := y.get_data()
	if da == db:
		return Vector2i(0, 0)
	var px := 0
	var mx := 0
	for i in range(0, mini(da.size(), db.size()), 3):
		var d := maxi(absi(da[i] - db[i]), maxi(absi(da[i + 1] - db[i + 1]), absi(da[i + 2] - db[i + 2])))
		if d > 0:
			px += 1
			mx = maxi(mx, d)
	return Vector2i(px, mx)


func _floor(a, b) -> Dictionary:
	if a == null or b == null:
		return {"mad": -1.0, "text": "n/a"}
	var m := Sheet.mad(a, b)
	var e := _exact(a, b)
	return {"mad": m, "px": e.x, "max": e.y,
			"text": "%.2f (byte-identical)" % m if e.x == 0 else "%.2f (%d px differ, max %d)" % [m, e.x, e.y]}


func _make() -> void:
	var orig: String = _a.get("original", "")
	var before: String = _a.get("before", "")
	var after: String = _a.get("after", "")
	var out: String = _a.get("out", after.path_join("parity-contact-sheet.png"))
	var names: PackedStringArray = str(_a.get("names", "original,HEAD,feat/slug")).split(",")
	var rows := []
	var table := []
	var i := 0
	while FileAccess.file_exists("%s_%d.png" % [orig, i]):
		var o = _img("%s_%d.png" % [orig, i])
		var o2 = _img("%s_%d.png" % [_a.get("original2", ""), i]) if _a.has("original2") else null
		var b = _img(before.path_join("port-view_%d.png" % i)) if before != "" else null
		var b2 = _img(str(_a.get("before2", "")).path_join("port-view_%d.png" % i)) if _a.has("before2") else null
		var f = _img(after.path_join("port-view_%d.png" % i))
		var f2 = _img(str(_a.get("after2", "")).path_join("port-view_%d.png" % i)) if _a.has("after2") else null
		var mb: float = Sheet.mad(b, o) if b != null else -1.0
		var ma := Sheet.mad(f, o)
		var fo := _floor(o, o2)
		var fb := _floor(b, b2)
		var fa := _floor(f, f2)
		table.append([i, fo, fb, fa, mb, ma])
		rows.append({"view": i, "mb": mb, "ma": ma, "cells": [
			{"image": o, "label": "view %d %s\nfloor %s" % [i, names[0], fo.text]},
			{"image": b, "label": "%s: residual %.1f\nfloor %s" % [names[1], mb, fb.text] if b != null else "(no before)"},
			{"image": f, "label": "%s: residual %.1f (delta %+.1f)\nfloor %s" % [names[2], ma, ma - mb, fa.text]},
			{"image": Sheet.heat(f, o), "label": "|%s - %s|\nblack 0, red 85, yellow 170, white 255" % [names[2], names[0]]}]})
		i += 1
	rows.sort_custom(func(x, y): return x.ma > y.ma)
	for r in rows.size():
		var row: Dictionary = rows[r]
		var t: Array = table[row.view]
		row["label"] = "#%d worst: view %d   residual %s %.1f -> %s %.1f (delta %+.1f)   floors: %s %s, %s %s" % [
				r + 1, row.view, names[1], row.mb, names[2], row.ma, row.ma - row.mb, names[0], t[1].text.split(" ")[0],
				names[2], t[3].text.split(" ")[0]]
		row["color"] = Color(1, 0.55, 0.45) if r < 3 else Color(1, 0.95, 0.7)
	print("parity_sheet: view | floor %s | floor %s | floor %s | residual %s | residual %s" % [names[0], names[1], names[2], names[1], names[2]])
	for t in table:
		print("parity_sheet: %d | %s | %s | %s | %.1f | %.1f" % [t[0], t[1].text, t[2].text, t[3].text, t[4], t[5]])
	var title: String = _a.get("title", "Hammersley parity 8@-1,-11.4, 1920x1080 (MAD 0..255; floors = same side rendered twice): %s | %s | %s | heat map, worst first" % [names[0], names[1], names[2]])
	var img: Image = await Sheet.render(self, title, [names[0], names[1], names[2], "|%s - %s|" % [names[2], names[0]]], rows, CELL)
	for p in Sheet.publish(img, out, _a.get("topic", "parity-hammersley")):
		print("parity_sheet: %d views, saved %s" % [rows.size(), p])
	quit()
