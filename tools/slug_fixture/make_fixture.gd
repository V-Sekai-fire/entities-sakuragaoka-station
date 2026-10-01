# The Slug test fixtures. encoder() packs the fixture atlas with encoder.gd (slughorn's packing);
# bakes() is the fixture's slug_cost / slug_mesh table in slug.elf's wire format (core/slug/baked.gd).
# fixture_guest.gd serves both through the slug.elf API. Run as a script it also writes
# fixture.slug, the atlas in slughorn/serial.hpp's .slug JSON, so slughorn's own serial::read and
# render.hpp can be pointed at the same data.
# Every key is a 64 x 64 px canvas at 1/64 em per px, canvas y down:
#   fx-circle  a red circle of 8 quadratic arcs, centre (32, 32) px, radius 20.125 px
#   fx-hole    a blue square 8..56 px with a hole x 24..40, y 16..32 px (the canvas' upper half)
#   fx-grad    the whole canvas, a linear gradient red (x = 0) to blue (x = 64)
#   fx-layers  a green canvas under the red circle at alpha 0.5 (source-over); no recorded frame
# fx-stamps (served by fixture_guest.gd beside the encoder's keys; slughorn's .slug has no stamps):
#   a grey canvas under stamp layer 1 (stamp layer 0 is an empty 1 x 1 grid no key uses, so the
#   stamp index collides with fx-grad's gradient id 1 as a guest's would), an 8 x 8 grid over the
#   key: hand-placed instances in the upper-left (S1 a red rect, S2 a blue ellipse over it, S3 a
#   sheared green rect for the AA edge, S4 an orange ellipse across the x = 24 px / y = 16 px cell
#   lines, S5 fx-hole's shape as a curve prototype at 1/5 scale), the top-right cell left empty, and
#   a few hundred random ellipses and rects (anisotropic, sheared, translucent) elsewhere.
# Bakes: fx-card (mode mesh: a yellow square 0.25..0.75 x 0.5..0.75, a red-to-blue strip
# 0..1 x 0..0.25 with t = u, a translucent white overlay triangle), fx-circle (mode slug),
# fx-mean (mode mean), fx-radial (mode mesh with a radial paint: not drawable as a mesh), fx-cells
# (mode mesh: a 2 x 2 atlas, one coloured square per cell, as the sakura and flora card atlases).
#   godot --headless --path . --script tools/slug_fixture/make_fixture.gd
extends SceneTree

const Encoder = preload("res://tools/slug_fixture/encoder.gd")
const DIR := "res://tools/slug_fixture/"
const PX := 1.0 / 64.0
const FRAME := {"width": 64, "height": 64, "scale": PX, "y_down": true}
const STAMP_GRID := 8
const STAMP_RANDOM := 300
const STAMP_PAD := PX  # the AA padding of an instance's bbox, in em
const STAMP_BASE := Color(0.2, 0.2, 0.2)


func _initialize() -> void:
	var f := FileAccess.open(DIR.path_join("fixture.slug"), FileAccess.WRITE)
	f.store_string(JSON.stringify(encoder().to_json(), "  "))
	f.close()
	print("slug fixture: wrote %s" % DIR.path_join("fixture.slug"))
	quit()


static func px(x: float, y: float) -> Vector2:
	return Vector2(x, y) * PX


static func encoder():
	var e = Encoder.new()
	var circle := Encoder.circle(px(32, 32), 20.125 * PX)
	e.composite("fx-circle", [e.layer("fx-circle/0", circle, Color(1, 0, 0))], FRAME)
	var outer := Encoder.polygon([px(8, 8), px(56, 8), px(56, 56), px(8, 56)])
	var hole := Encoder.polygon([px(24, 16), px(24, 32), px(40, 32), px(40, 16)])
	e.composite("fx-hole", [e.layer("fx-hole/0", outer + hole, Color(0, 0, 1))], FRAME)
	var full := Encoder.polygon([px(0, 0), px(64, 0), px(64, 64), px(0, 64)])
	var gl: Dictionary = e.layer("fx-grad/0", full, Color(1, 1, 1, 1))
	gl.gradient_id = e.linear_gradient(px(0, 32), px(64, 32), gl._origin, [
			{"t": 0.0, "color": [1.0, 0.0, 0.0, 1.0]}, {"t": 1.0, "color": [0.0, 0.0, 1.0, 1.0]}])
	e.composite("fx-grad", [gl], FRAME)
	e.composite("fx-layers", [e.layer("fx-layers/0", full, Color(0, 1, 0)), e.layer("fx-layers/1", circle, Color(1, 0, 0, 0.5))])
	return e


static func bakes() -> Dictionary:
	var card := {
		"mode": "mesh",
		"vertices": PackedFloat32Array([0.25, 0.5, 0, 0.75, 0.5, 0, 0.75, 0.75, 0, 0.25, 0.75, 0,
				0.0, 0.0, 0, 1.0, 0.0, 0, 1.0, 0.25, 0, 0.0, 0.25, 0,
				0.1, 0.9, 0, 0.3, 0.9, 0, 0.1, 0.7, 0]),
		"triangles": PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7, 8, 10, 9]),
		"paint": PackedInt32Array([0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2]),
		"param": PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0.0, 0, 1.0, 0, 1.0, 0, 0.0, 0, 0, 0, 0, 0, 0, 0]),
		"paints": PackedFloat32Array([3,
				0, 1, 0, 1, 1, 0, 1,
				1, 2, 0, 1, 0, 0, 1, 1, 0, 0, 1, 1,
				0, 1, 0, 1, 1, 1, 0.5]),
		"overlay": PackedInt32Array([12, 3]),
	}
	var radial := {"mode": "mesh", "vertices": PackedFloat32Array([0, 0, 0, 1, 0, 0, 0, 1, 0]), "triangles": PackedInt32Array([0, 1, 2]),
		"paint": PackedInt32Array([0, 0, 0]), "param": PackedFloat32Array([0, 0, 1, 0, 0, 1]),
		"paints": PackedFloat32Array([1, 2, 2, 0, 1, 1, 1, 1, 1, 0, 0, 0, 1]), "overlay": PackedInt32Array([3, 0])}
	# a 2 x 2 atlas: cell (cx, cy) holds the square [cx + 0.1, cx + 0.4] x [cy + 0.1, cy + 0.4] in its
	# own colour (paint = cell index: (0,0) red, (0.5,0) green, (0,0.5) blue, (0.5,0.5) white)
	var cv := PackedFloat32Array()
	var ct := PackedInt32Array()
	var cp := PackedInt32Array()
	var i := 0
	for cell in [Vector2(0, 0), Vector2(0.5, 0), Vector2(0, 0.5), Vector2(0.5, 0.5)]:
		for q in [Vector2(0.1, 0.1), Vector2(0.4, 0.1), Vector2(0.4, 0.4), Vector2(0.1, 0.4)]:
			cv.append_array(PackedFloat32Array([cell.x + q.x, cell.y + q.y, 0.0]))
			cp.append(i)
		var o := i * 4
		ct.append_array(PackedInt32Array([o, o + 1, o + 2, o, o + 2, o + 3]))
		i += 1
	var prm := PackedFloat32Array()
	prm.resize(32)
	var cells := {"mode": "mesh", "vertices": cv, "triangles": ct, "paint": cp, "param": prm,
		"paints": PackedFloat32Array([4, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1]),
		"overlay": PackedInt32Array([24, 0])}
	return {"fx-card": card, "fx-circle": {"mode": "slug"}, "fx-mean": {"mode": "mean"}, "fx-radial": radial, "fx-cells": cells}


# ------------------------------------------------------------------------------------ stamps

## The fx-stamps content: {"protos": [[kind, layer key, layer index in that key or -1]],
## "gradients": slug_atlas()-style gradients appended after the encoder's (ids from
## enc.gradients.size() + 1), "layers": [{"g", "instances"}], "special": {name: instance index in
## stamp layer 1}, "deep": [first, count] (the 32-deep cell's instances), "deep_cell": its index}.
## Instances: {"fwd": prototype frame -> canvas em, "inv", "proto", "kind", "paint", "grad"
## (reference.gd's view of the paint), "color", "bbox" (em), "uv_box" (padded, key UV), "curves" +
## "offset" (curve prototypes)}. enc: encoder() (fx-hole's shape is the curve prototype).
static func stamps(enc) -> Dictionary:
	var hole_curves: Array
	for sh in enc.shapes:
		if sh.key == "fx-hole/0":
			hole_curves = sh.curves
	var hole_off := Vector2.ZERO
	for c in enc.composites:
		if c.key.value == "fx-hole":
			hole_off = Vector2(c.layers[0].transform[0], c.layers[0].transform[1])
	var protos := [[1, "", -1], [2, "", -1], [0, "fx-hole", 0]]
	# a linear gradient along the prototype's x: red, green at 0.5, blue
	var grad := {"type": "linear", "transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], "inner_radius": 0.0, "start_angle": 0.0,
			"end_angle": 1.0, "stops": [{"t": 0.0, "color": [1.0, 0.0, 0.0, 1.0]}, {"t": 0.5, "color": [0.0, 1.0, 0.0, 1.0]},
			{"t": 1.0, "color": [0.0, 0.0, 1.0, 1.0]}]}
	var grad_id: int = enc.gradients.size() + 1
	var insts := []
	var special := {}
	var mk := func(name: String, proto: int, fwd: Transform2D, col: Color, paint: int = 0) -> void:
		special[name] = insts.size()
		var it := _stamp(proto, protos[proto][0], fwd, col, hole_curves, hole_off)
		if paint > 0:
			it.paint = paint
			it.grad = grad
		insts.append(it)
	# S1: rect 8 x 6 px rotated 20 degrees, centred (10, 11) px
	mk.call("S1", 1, _at(px(10, 11), deg_to_rad(20), px(8, 6)) * Transform2D(0, Vector2(-0.5, -0.5)), Color(1, 0, 0))
	# S2: ellipse radii 3.5 x 2.5 px at (14, 12.5) px, over S1
	mk.call("S2", 0, _at(px(14, 12.5), deg_to_rad(-30), px(3.5, 2.5)), Color(0, 0, 1))
	# S3: a sheared rect, edges at odd angles
	mk.call("S3", 1, Transform2D(Vector2(9, 0.5) * PX, Vector2(3, 3) * PX, px(19, 2)), Color(0, 1, 0))
	# S4: ellipse across the x = 24 px and y = 16 px cell lines
	mk.call("S4", 0, _at(px(24, 18), deg_to_rad(35), px(3.5, 2)), Color(1, 0.5, 0))
	# a mixed run: S5 fx-hole's shape (a 48 px square with a hole) at 1/5, rotated 15 degrees,
	# centred (10, 34) px; S6 a translucent ellipse over it; S7 a translucent rect over both
	mk.call("S5", 2, _at(px(10, 34), deg_to_rad(15), Vector2(0.2, 0.2)) * Transform2D(0, -px(32, 32)), Color(0.6, 0, 0.8))
	mk.call("S6", 0, _at(px(13, 36), deg_to_rad(10), px(4, 2.5)), Color(0, 0.9, 0.9, 0.6))
	mk.call("S7", 1, _at(px(11, 37), deg_to_rad(-25), px(5, 6)) * Transform2D(0, Vector2(-0.5, -0.5)), Color(1, 1, 0, 0.5))
	# S8: the gradient along a rect rotated 30 degrees, 14 x 5 px, centred (44, 7) px
	mk.call("S8", 1, _at(px(44, 7), deg_to_rad(30), px(14, 5)) * Transform2D(0, Vector2(-0.5, -0.5)), Color(1, 1, 1), grad_id)
	# the 32-deep cell x 40..48, y 32..40 px: rect k spans screen columns 160 + k .. 192 (256 px
	# view) and rows 136..152, so column 160 + k is covered by rects 0..k, k on top
	var deep_first := insts.size()
	for k in 32:
		var x0 := (160.0 + k) / 256.0
		var c := Color.from_hsv(float(k) / 32.0, 0.9, 1.0, 0.8)
		mk.call("D%d" % k, 1, Transform2D(Vector2(192.0 / 256.0 - x0, 0), Vector2(0, 16.0 / 256.0), Vector2(x0, 136.0 / 256.0)), c)
	var reserved := [Rect2(0, 0, 32 * PX, 24 * PX), Rect2(0, 24 * PX, 24 * PX, 20 * PX), Rect2(56 * PX, 0, 8 * PX, 8 * PX),
			Rect2(34 * PX, 0, 20 * PX, 14 * PX), Rect2(39 * PX, 32 * PX, 17 * PX, 8 * PX)]
	var counts := []
	var lists := Encoder.bin_cells(STAMP_GRID, insts)
	for c in lists.size():
		counts.append(lists[c].size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261001
	var tries := 0
	var placed := 0
	while placed < STAMP_RANDOM and tries < 20000:
		tries += 1
		var proto := rng.randi_range(0, 1)
		var sc := Vector2(rng.randf_range(0.8, 4.0), rng.randf_range(0.6, 3.0)) * PX
		var fwd := _at(Vector2(rng.randf(), rng.randf()), rng.randf() * TAU, sc) * Transform2D(Vector2(1, 0), Vector2(rng.randf_range(-0.6, 0.6), 1), Vector2.ZERO)
		if proto == 1:
			fwd = fwd * Transform2D(0, Vector2(-0.5, -0.5))
		var col := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf_range(0.5, 1.0))
		var it := _stamp(proto, protos[proto][0], fwd, col, hole_curves, hole_off)
		var pb: Rect2 = it.bbox.grow(STAMP_PAD)
		if pb.position.x < 0 or pb.position.y < 0 or pb.end.x > 1 or pb.end.y > 1:
			continue
		var clash := false
		for r in reserved:
			clash = clash or r.intersects(pb)
		if clash:
			continue
		var cl: Array = Encoder.bin_cells(STAMP_GRID, [it])
		var full := false
		for c in cl.size():
			full = full or (cl[c].size() > 0 and counts[c] >= 16)
		if full:
			continue
		for c in cl.size():
			counts[c] += cl[c].size()
		insts.append(it)
		placed += 1
	# cell (i, j) = floor(uv * G): x 40..48 px is i = 5, y 32..40 px is v 0.375..0.5, j = 3
	return {"protos": protos, "gradients": [grad], "layers": [{"g": 1, "instances": []}, {"g": STAMP_GRID, "instances": insts}],
			"special": special, "deep": [deep_first, 32], "deep_cell": 3 * STAMP_GRID + 5, "random": placed}


## Translate * rotate * scale.
static func _at(origin: Vector2, angle: float, scale: Vector2) -> Transform2D:
	return Transform2D(angle, scale, 0.0, origin)


static func _stamp(proto: int, kind: int, fwd: Transform2D, col: Color, curves: Array, off: Vector2) -> Dictionary:
	var pts := []
	if kind == 1:
		var h := Vector2(Vector2(fwd.x.x, fwd.y.x).length(), Vector2(fwd.x.y, fwd.y.y).length())
		pts = [fwd.origin - h, fwd.origin + h]
	elif kind == 2:
		pts = [fwd * Vector2(0, 0), fwd * Vector2(1, 0), fwd * Vector2(0, 1), fwd * Vector2(1, 1)]
	else:
		for c in curves:
			for i in 3:
				pts.append(fwd * (Vector2(c[i * 2], c[i * 2 + 1]) + off))
	var b := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		b = b.expand(p)
	var pb := b.grow(STAMP_PAD)
	# key UV of the padded bbox (FRAME: em = (u, 1 - v))
	var uv := Rect2(pb.position.x, 1.0 - pb.end.y, pb.size.x, pb.size.y)
	return {"fwd": fwd, "inv": fwd.affine_inverse(), "proto": proto, "kind": kind, "paint": 0, "grad": null, "color": col,
			"bbox": b, "uv_box": uv, "curves": curves if kind == 0 else [], "offset": off}
