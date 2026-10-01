# The lookdev-24 chart in the engine floor (tools/engine_floor.gd renders the tiles): each patch read
# back from the central 60% of its square, by projecting the square with the tile's camera, and
# scored in CIEDE2000 (sRGB 8-bit -> linear -> XYZ D65 -> Bradford to D50 -> L*a*b* D50).
#   unlit chart, both engines:  8-bit code against srgb8 (unlit must be exact); dE00 against lab_d50
#                               (absolute; the cyan's R' = 0 is clipped, flagged); dE00 against the
#                               srgb8 colour's own L*a*b* (fidelity: what an engine can be held to)
#   lit toon chart:             three against godot, dE00 per patch in the sun and in the cast shadow
#   texture path:               the chart as the original's canvas texture -> canvas_svg.mjs -> SVG
#                               -> slug.elf -> the baked mesh (palette) and slug-runtime, on an unlit
#                               quad in the port (three.js's own textured quad alongside)
# Tests that can fail (unclipped patches): unlit fidelity dE00 <= 0.5 in both engines; texture path
# fidelity dE00 <= 1.0 in both paths; the control (the port's unlit chart with patches 3 and 4
# swapped) must FAIL the unlit test. The absolute test against lab_d50 (dE00 <= 0.5) is reported too:
# the published srgb8 values themselves miss lab_d50 by up to 1.19 under this conversion, so that test
# measures the reference, not an engine; the "srgb8" column shows by how much.
extends RefCounted

const Sheet = preload("res://tools/sheet.gd")
const BRADFORD := [[1.0478112, 0.0228866, -0.0501270], [0.0295424, 0.9904844, -0.0170491], [-0.0092345, 0.0150436, 0.7521316]]
const SRGB_XYZ := [[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]]
const WHITE_D50 := Vector3(0.96422, 1.0, 0.82521)
const UNLIT_MAX := 0.5
const TEXTURE_MAX := 1.0


static func _lin(c8: float) -> float:
	var c := c8 / 255.0
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func _mul(m: Array, v: Vector3) -> Vector3:
	return Vector3(m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z, m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
			m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z)


## L*a*b* D50 of an sRGB 8-bit colour (channels may be fractional: a patch's mean code).
static func lab(rgb8: Vector3) -> Vector3:
	var xyz := _mul(BRADFORD, _mul(SRGB_XYZ, Vector3(_lin(rgb8.x), _lin(rgb8.y), _lin(rgb8.z))))
	var f := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 216.0 / 24389.0 else (24389.0 / 27.0 * t + 16.0) / 116.0
	var fx: float = f.call(xyz.x / WHITE_D50.x)
	var fy: float = f.call(xyz.y / WHITE_D50.y)
	var fz: float = f.call(xyz.z / WHITE_D50.z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


## CIEDE2000 (Sharma, Wu and Dalal 2005), kL = kC = kH = 1.
static func de2000(l1: Vector3, l2: Vector3) -> float:
	var c1 := sqrt(l1.y * l1.y + l1.z * l1.z)
	var c2 := sqrt(l2.y * l2.y + l2.z * l2.z)
	var cb := (c1 + c2) / 2.0
	var g := 0.5 * (1.0 - sqrt(pow(cb, 7) / (pow(cb, 7) + pow(25.0, 7))))
	var a1p := (1.0 + g) * l1.y
	var a2p := (1.0 + g) * l2.y
	var c1p := sqrt(a1p * a1p + l1.z * l1.z)
	var c2p := sqrt(a2p * a2p + l2.z * l2.z)
	var h1p := fposmod(rad_to_deg(atan2(l1.z, a1p)), 360.0)
	var h2p := fposmod(rad_to_deg(atan2(l2.z, a2p)), 360.0)
	var dlp := l2.x - l1.x
	var dcp := c2p - c1p
	var dhp := 0.0
	if c1p * c2p != 0.0:
		dhp = h2p - h1p
		if dhp > 180.0:
			dhp -= 360.0
		elif dhp < -180.0:
			dhp += 360.0
	var dhhp := 2.0 * sqrt(c1p * c2p) * sin(deg_to_rad(dhp / 2.0))
	var lbp := (l1.x + l2.x) / 2.0
	var cbp := (c1p + c2p) / 2.0
	var hbp := h1p + h2p
	if c1p * c2p != 0.0:
		if absf(h1p - h2p) <= 180.0:
			hbp = (h1p + h2p) / 2.0
		elif h1p + h2p < 360.0:
			hbp = (h1p + h2p + 360.0) / 2.0
		else:
			hbp = (h1p + h2p - 360.0) / 2.0
	var t := 1.0 - 0.17 * cos(deg_to_rad(hbp - 30.0)) + 0.24 * cos(deg_to_rad(2.0 * hbp)) \
			+ 0.32 * cos(deg_to_rad(3.0 * hbp + 6.0)) - 0.20 * cos(deg_to_rad(4.0 * hbp - 63.0))
	var dth := 30.0 * exp(-pow((hbp - 275.0) / 25.0, 2))
	var rc := 2.0 * sqrt(pow(cbp, 7) / (pow(cbp, 7) + pow(25.0, 7)))
	var sl := 1.0 + 0.015 * pow(lbp - 50.0, 2) / sqrt(20.0 + pow(lbp - 50.0, 2))
	var sc := 1.0 + 0.045 * cbp
	var sh := 1.0 + 0.015 * cbp * t
	var rt := -sin(deg_to_rad(2.0 * dth)) * rc
	return sqrt(pow(dlp / sl, 2) + pow(dcp / sc, 2) + pow(dhhp / sh, 2) + rt * (dcp / sc) * (dhhp / sh))


## The central 60% of each patch square on screen, by projecting it with cam (placed at the tile).
## c: a chart placement (calib_scene.json "charts" / "textured": pos, yaw, px).
static func patch_rects(cam: Camera3D, c: Dictionary, chart: Dictionary) -> Array:
	var out := []
	var yaw := deg_to_rad(float(c.yaw))
	var px := float(c.px)
	var pos := Vector3(c.pos[0], c.pos[1], c.pos[2])
	for p in chart.patches:
		var cx: float = 20.0 + p.col * 110.0 + 50.0
		var cy: float = 20.0 + p.row * 110.0 + 50.0
		var lo := Vector2(INF, INF)
		var hi := -lo
		for k in [Vector2(-30, -30), Vector2(30, -30), Vector2(30, 30), Vector2(-30, 30)]:
			var x: float = (cx + k.x - 345.0) * px
			var y: float = (235.0 - (cy + k.y)) * px
			var w := pos + Vector3(x * cos(yaw), y, -x * sin(yaw))
			var s := cam.unproject_position(w)
			lo = lo.min(s)
			hi = hi.max(s)
		out.append(Rect2i(Vector2i(ceili(lo.x), ceili(lo.y)), Vector2i(floori(hi.x) - ceili(lo.x), floori(hi.y) - ceili(lo.y))))
	return out


## Each rect's mean 8-bit sRGB code.
static func read(img: Image, rects: Array) -> Array:
	var x: Image = img.duplicate()
	x.convert(Image.FORMAT_RGB8)
	var out := []
	for r in rects:
		var s := Vector3.ZERO
		var n := 0
		for j in range(r.position.y, r.end.y):
			for i in range(r.position.x, r.end.x):
				var c := x.get_pixel(i, j)
				s += Vector3(c.r8, c.g8, c.b8)
				n += 1
		out.append(s / maxf(n, 1))
	return out


const CELL := Vector2i(120, 90)


static func _swatch(rgb: Vector3, size: Vector2i) -> Image:
	var im := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	im.fill(Color8(roundi(rgb.x), roundi(rgb.y), roundi(rgb.z)))
	return im


## The middle of a read rect at the cell's aspect, scaled up without filtering (the pixels as read).
static func _crop(img: Image, r: Rect2i, size: Vector2i) -> Image:
	var h := mini(r.size.y, roundi(r.size.x * float(size.y) / size.x))
	var w := mini(r.size.x, roundi(h * float(size.x) / size.y))
	var c := img.get_region(Rect2i(r.position + (r.size - Vector2i(w, h)) / 2, Vector2i(maxi(w, 1), maxi(h, 1))))
	c.convert(Image.FORMAT_RGB8)
	c.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	return c


## Scores, tests, the control and the chart-calib contact sheet. reads: {source: {"img", "rects"}}
## with sources three-unlit, godot-unlit, godot-unlit-swapped, three-texture, godot-baked,
## godot-runtime, three-lit, godot-lit, three-shadow, godot-shadow (any may be missing).
static func report(tree: SceneTree, chart: Dictionary, reads: Dictionary, out: String) -> Dictionary:
	var vals := {}
	for k in reads:
		vals[k] = read(reads[k].img, reads[k].rects)
	var rows := []
	var res := {"patches": [], "tests": {}}
	var fails := {"unlit": [], "texture": [], "control": [], "absolute": []}
	var unlit := ["three-unlit", "godot-unlit"]
	var tex := ["three-texture", "godot-baked", "godot-runtime"]
	for i in chart.patches.size():
		var p: Dictionary = chart.patches[i]
		var ref8 := Vector3(p.srgb8[0], p.srgb8[1], p.srgb8[2])
		var lab_ref := Vector3(p.lab_d50[0], p.lab_d50[1], p.lab_d50[2])
		var lab_s := lab(ref8)
		var clipped: bool = p.srgb8_clipped.has(true)
		var e := {"no": p.no, "name": p.name, "clipped": clipped, "ref_de_abs": de2000(lab_ref, lab_s)}
		var worst := 0.0
		for k in unlit + tex + ["godot-unlit-swapped"]:
			if not vals.has(k):
				continue
			var v: Vector3 = vals[k][i]
			var code := maxf(absf(v.x - ref8.x), maxf(absf(v.y - ref8.y), absf(v.z - ref8.z)))
			var fid := de2000(lab_s, lab(v))
			var ab := de2000(lab_ref, lab(v))
			e[k] = {"rgb": [v.x, v.y, v.z], "code": code, "de_fid": fid, "de_abs": ab}
			if k != "godot-unlit-swapped":
				worst = maxf(worst, fid)
			if clipped:
				continue
			if k in unlit and fid > UNLIT_MAX:
				fails.unlit.append("%s patch %d %.2f" % [k, p.no, fid])
			if k in unlit and ab > UNLIT_MAX:
				fails.absolute.append("%s patch %d %.2f" % [k, p.no, ab])
			if k in tex and k != "three-texture" and fid > TEXTURE_MAX:
				fails.texture.append("%s patch %d %.2f" % [k, p.no, fid])
			if k == "godot-unlit-swapped" and fid > UNLIT_MAX:
				fails.control.append("patch %d %.2f" % [p.no, fid])
		for side in ["lit", "shadow"]:
			if vals.has("three-" + side) and vals.has("godot-" + side):
				var a: Vector3 = vals["three-" + side][i]
				var b: Vector3 = vals["godot-" + side][i]
				e[side] = {"three": [a.x, a.y, a.z], "godot": [b.x, b.y, b.z], "de": de2000(lab(a), lab(b))}
		res.patches.append(e)
		# the contact sheet row
		var cells := [{"image": _swatch(ref8, CELL), "label": "%d,%d,%d\nabs %.2f%s" % [p.srgb8[0], p.srgb8[1], p.srgb8[2], e.ref_de_abs, " CLIPPED" if clipped else ""]}]
		for k in unlit + tex:
			if reads.has(k):
				var f: Dictionary = e[k]
				cells.append({"image": _crop(reads[k].img, reads[k].rects[i], CELL), "label": "fid %.2f d%.1f\nabs %.2f" % [f.de_fid, f.code, f.de_abs],
						"mark": Color(0.9, 0.2, 0.2) if (not clipped and f.de_fid > (UNLIT_MAX if k in unlit else TEXTURE_MAX)) else null})
		for side in ["lit", "shadow"]:
			if e.has(side):
				for eng in ["three", "godot"]:
					var v: Array = e[side][eng]
					cells.append({"image": _crop(reads[eng + "-" + side].img, reads[eng + "-" + side].rects[i], CELL),
							"label": "%d,%d,%d%s" % [roundi(v[0]), roundi(v[1]), roundi(v[2]), ("\ndE00 %.2f" % e[side].de) if eng == "godot" else ""]})
		rows.append({"worst": maxf(worst, maxf(e.get("lit", {}).get("de", 0.0), e.get("shadow", {}).get("de", 0.0))),
				"label": "patch %d %s%s" % [p.no, p.name, " (clipped: cyan R' = 0)" if clipped else ""], "cells": cells})
	rows.sort_custom(func(x, y): return x.worst > y.worst)
	res.tests = {
		"unlit_fidelity_le_0.5": {"pass": fails.unlit.is_empty(), "fails": fails.unlit},
		"unlit_absolute_vs_lab_d50_le_0.5": {"pass": fails.absolute.is_empty(), "fails": fails.absolute},
		"texture_fidelity_le_1.0": {"pass": fails.texture.is_empty(), "fails": fails.texture},
		"control_swapped_must_fail": {"pass": not fails.control.is_empty(), "fails_seen": fails.control},
	}
	for t in res.tests:
		print("chart_calib: test %-34s %s %s" % [t, "PASS" if res.tests[t].pass else "FAIL", str(res.tests[t].get("fails", res.tests[t].get("fails_seen", [])))])
	print("chart_calib: patch | srgb8 vs lab_d50 | three unlit fid/abs/code | godot unlit fid/abs/code | baked fid/abs | runtime fid/abs | three tex fid | lit dE00 | shadow dE00")
	for e in res.patches:
		var f := func(k: String, what: String) -> String: return "%.2f" % e[k][what] if e.has(k) else "-"
		print("chart_calib: %2d %-14s %5.2f%s | %s/%s/%s | %s/%s/%s | %s/%s | %s/%s | %s | %s | %s" % [e.no, e.name, e.ref_de_abs, "*" if e.clipped else " ",
				f.call("three-unlit", "de_fid"), f.call("three-unlit", "de_abs"), f.call("three-unlit", "code"),
				f.call("godot-unlit", "de_fid"), f.call("godot-unlit", "de_abs"), f.call("godot-unlit", "code"),
				f.call("godot-baked", "de_fid"), f.call("godot-baked", "de_abs"), f.call("godot-runtime", "de_fid"), f.call("godot-runtime", "de_abs"),
				f.call("three-texture", "de_fid"), "%.2f" % e.lit.de if e.has("lit") else "-", "%.2f" % e.shadow.de if e.has("shadow") else "-"])
	var heads := ["srgb8"]
	for k in unlit + tex:
		if reads.has(k):
			heads.append(k)
	for side in ["lit", "shadow"]:
		if reads.has("three-" + side):
			heads.append_array(["three " + side, "godot " + side])
	var img: Image = await Sheet.render(tree, "24-patch chart, worst first. fid: dE00 vs srgb8's Lab; abs: vs lab_d50; d: max code diff; red: over the limit",
			heads, rows, CELL)
	for p in Sheet.publish(img, out.path_join("chart-calib-sheet.png"), "chart-calib"):
		print("chart_calib: saved ", p)
	var fl := FileAccess.open(out.path_join("chart_calib.json"), FileAccess.WRITE)
	fl.store_string(JSON.stringify(res, " "))
	fl.close()
	return res
