# Labelled contact sheets (the repo's contact-sheet.png convention, tools/prop_shots.gd) composed
# in a SubViewport with TextureRects and Labels and captured, since Image cannot draw text.
#   var img: Image = await Sheet.render(tree, "title", ["col a", "col b"], rows, Vector2i(480, 270))
#   rows: [{"label": "row text", "cells": [{"image": Image or null, "label": "cell text", "mark": Color or null}, ...]}]
#   Sheet.publish(img, "<dir>/x-contact-sheet.png", "topic")   # saves, and copies to the desktop
# publish() also copies every sheet to <Desktop>/lookdev-contact-sheets/<topic>-<NN>.png when that
# folder exists, never overwriting (NN counts up), for review alongside other agents' sheets.
extends RefCounted

const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const PAD := 6
const TITLE_H := 34
const HEAD_H := 24
const ROW_LABEL_H := 22
const LINE_H := 18


static func render(tree: SceneTree, title: String, columns: Array, rows: Array, cell: Vector2i) -> Image:
	var cols := columns.size()
	var w := PAD + cols * (cell.x + PAD)
	var lines := 1
	for r in rows:
		for e in r.get("cells", []):
			lines = maxi(lines, str(e.get("label", "")).count("\n") + 1)
	var row_h := ROW_LABEL_H + cell.y + lines * LINE_H + 4 + PAD
	var h := TITLE_H + HEAD_H + rows.size() * row_h + PAD
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.14)
	bg.size = Vector2(w, h)
	vp.add_child(bg)
	_label(vp, title, Vector2(PAD, 4), 20, Color(1, 1, 1))
	for c in cols:
		_label(vp, str(columns[c]), Vector2(PAD + c * (cell.x + PAD), TITLE_H), 15, Color(0.85, 0.9, 1))
	for r in rows.size():
		var y := TITLE_H + HEAD_H + r * row_h
		_label(vp, str(rows[r].get("label", "")), Vector2(PAD, y), 15, rows[r].get("color", Color(1, 0.95, 0.7)))
		var cells: Array = rows[r].get("cells", [])
		for c in cells.size():
			var x := PAD + c * (cell.x + PAD)
			var e: Dictionary = cells[c]
			var mark = e.get("mark")
			if mark != null:
				var frame := ColorRect.new()
				frame.color = mark
				frame.position = Vector2(x - 3, y + ROW_LABEL_H - 3)
				frame.size = Vector2(cell.x + 6, cell.y + 6)
				vp.add_child(frame)
			var img = e.get("image")
			if img != null:
				var im: Image = img.duplicate()
				if im.get_format() != Image.FORMAT_RGBA8:
					im.convert(Image.FORMAT_RGBA8)
				im.resize(cell.x, cell.y, Image.INTERPOLATE_BILINEAR)
				var tr := TextureRect.new()
				tr.texture = ImageTexture.create_from_image(im)
				tr.position = Vector2(x, y + ROW_LABEL_H)
				tr.size = Vector2(cell)
				vp.add_child(tr)
			_label(vp, str(e.get("label", "")), Vector2(x, y + ROW_LABEL_H + cell.y + 1), 13, Color(0.9, 0.9, 0.9))
	for i in 3:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var out := vp.get_texture().get_image()
	vp.queue_free()
	return out


static func _label(parent: Node, text: String, at: Vector2, size: int, colour: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 3)
	parent.add_child(l)


## |a - b| averaged over RGB per pixel, as a black-red-yellow-white heat map (255 = white).
static func heat(a: Image, b: Image) -> Image:
	if not _guest("heat"):
		return null
	var x: Image = a.duplicate()
	var y: Image = b.duplicate()
	x.convert(Image.FORMAT_RGB8)
	y.convert(Image.FORMAT_RGB8)
	if y.get_size() != x.get_size():
		y.resize(x.get_width(), x.get_height())
	var out := Kernels.heat_rgb(x.get_data(), y.get_data())
	return Image.create_from_data(x.get_width(), x.get_height(), false, Image.FORMAT_RGB8, out)


## The parity measure: mean |a - b| over EVERY pixel and every RGB channel at full resolution, on
## the 0..255 scale (no resize, no subsample, no mask). -1 when the sizes differ.
static func mad(a: Image, b: Image) -> float:
	if a == null or b == null or a.get_size() != b.get_size() or not _guest("mad"):
		return -1.0
	var x: Image = a.duplicate()
	var y: Image = b.duplicate()
	x.convert(Image.FORMAT_RGB8)
	y.convert(Image.FORMAT_RGB8)
	var da := x.get_data()
	return float(Kernels.diff_stats(da, y.get_data())[0]) / float(da.size())


## The LEGACY measure, for older reports only: both images halved (bilinear), every 7th RGB byte.
static func mad_legacy(port: Image, orig: Image) -> float:
	if not _guest("mad_legacy"):
		return -1.0
	var w := port.get_width() / 2
	var h := port.get_height() / 2
	var a: Image = port.duplicate()
	var b: Image = orig.duplicate()
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	a.resize(w, h)
	b.resize(w, h)
	var da := a.get_data()
	return float(Kernels.stride_abs_sum(da, b.get_data(), 7)) / float(ceili(da.size() / 7.0))


static func _guest(what: String) -> bool:
	if Kernels.sandbox() != null:
		return true
	printerr("Sheet.%s: FAIL no kernels Sandbox (%s)" % [what, Kernels.reason])
	return false


## Saves img at path, and copies it to <Desktop>/lookdev-contact-sheets/<topic>-<NN>.png (first free
## NN) when that folder exists. Returns the paths written.
static func publish(img: Image, path: String, topic: String) -> PackedStringArray:
	var out := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if img.save_png(path) == OK:
		out.append(ProjectSettings.globalize_path(path))
	var desk := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP).path_join("lookdev-contact-sheets")
	if DirAccess.dir_exists_absolute(desk):
		var n := 1
		while FileAccess.file_exists(desk.path_join("%s-%02d.png" % [topic, n])):
			n += 1
		var d := desk.path_join("%s-%02d.png" % [topic, n])
		if img.save_png(d) == OK:
			out.append(d)
	return out
