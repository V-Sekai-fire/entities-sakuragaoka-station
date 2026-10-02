# Contact sheets for the Slug fixture checks (tools/slug_check.gd), for vision-model review and QA:
#   card-bake-contact-sheet.png  per test card: the fixture atlas with the card's UV footprint
#       outlined | the old extrapolating map_card | the new clip (slug_decal, cutout) | expected
#       (the bake clipped to the footprint by an independent rectangle clip), all but the first in
#       the card's own (u, v) frame with the card quad outlined.
#   gpu-pixels-contact-sheet.png  per checked pixel: the GPU render around it (boxed) | GPU colour
#       beside the CPU reference (render.hpp coverage) | the whole render with the pixel marked.
#   godot --path . --script tools/slug_sheets.gd -- [--out=<dir>]      (needs a renderer)
extends SceneTree

const Sheet = preload("res://tools/sheet.gd")
const Guest = preload("res://addons/sakuragaoka_station/core/slug/guest.gd")
const Pack = preload("res://addons/sakuragaoka_station/core/slug/pack.gd")
const SlugAtlas = preload("res://addons/sakuragaoka_station/core/slug/atlas.gd")
const Baked = preload("res://addons/sakuragaoka_station/core/slug/baked.gd")
const FixtureGuest = preload("res://tools/slug_fixture/fixture_guest.gd")
const LegacyMapCard = preload("res://tools/slug_fixture/legacy_map_card.gd")
const Ref = preload("res://tools/slug_fixture/reference.gd")
const CARD_O := Vector3(1, 2, 3)
const CARD_A := Vector3(2, 0, 0.5)
const CARD_B := Vector3(0, 1.5, 0)
const IMG := 320
const SIZE := 256

var _out := "user://slug_sheets"
var _guest


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_guest = FixtureGuest.new()
	Guest.override = _guest
	Pack.reset()
	SlugAtlas.reset()
	Baked.reset()
	_make.call_deferred()


func _make() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var a: Image = await _card_sheet()
	var b: Image = await _pixel_sheet()
	for p in Sheet.publish(a, _out.path_join("card-bake-contact-sheet.png"), "card-bake") + 			Sheet.publish(b, _out.path_join("gpu-pixels-contact-sheet.png"), "slug-check-gpu"):
		print("slug_sheets: saved ", p)
	Guest.shutdown()
	quit()


# ------------------------------------------------------------------------------- drawing

## polys: [[PackedVector2Array in view (0..1, y up), Color], ...]; lines: [[PackedVector2Array, Color], ...].
func _draw(polys: Array, lines: Array) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(IMG, IMG)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.3, 0.3, 0.32)
	bg.size = Vector2(IMG, IMG)
	vp.add_child(bg)
	var px := func(p: Vector2) -> Vector2: return Vector2(p.x * IMG, (1.0 - p.y) * IMG)
	for e in polys:
		var pg := Polygon2D.new()
		var pts := PackedVector2Array()
		for p in e[0]:
			pts.append(px.call(p))
		pg.polygon = pts
		pg.color = e[1]
		vp.add_child(pg)
	for e in lines:
		var l := Line2D.new()
		var pts := PackedVector2Array()
		for p in e[0]:
			pts.append(px.call(p))
		l.points = pts
		l.default_color = e[1]
		l.width = 2.0
		vp.add_child(l)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


static func _rect_line(lo: Vector2, hi: Vector2) -> PackedVector2Array:
	return PackedVector2Array([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y), lo])


# ---------------------------------------------------------------------------- card sheet

## Card (u, v) of a 3D point on the card plane.
static func _card_uv(p: Vector3) -> Vector2:
	var d := p - CARD_O
	return Vector2(d.dot(CARD_A) / CARD_A.length_squared(), d.dot(CARD_B) / CARD_B.length_squared())


static func _card_src(uv0: Vector2, uv1: Vector2) -> Dictionary:
	var uv := PackedVector2Array([uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)])
	var pos := PackedVector3Array()
	for k in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		pos.append(CARD_O + CARD_A * k.x + CARD_B * k.y)
	return {"pos": pos, "nor": PackedVector3Array(), "uv": uv, "idx": PackedInt32Array([0, 2, 1, 0, 3, 2])}


## A polygon clipped to an axis-aligned rectangle (four half-planes), independent of the guest's clip.
static func _clip_rect(poly: Array, lo: Vector2, hi: Vector2) -> Array:
	var out := poly
	for e in 4:
		var inp := out
		out = []
		var inside := func(p: Vector2) -> float:
			match e:
				0: return p.x - lo.x
				1: return hi.x - p.x
				2: return p.y - lo.y
				_: return hi.y - p.y
		for i in inp.size():
			var p: Vector2 = inp[i]
			var q: Vector2 = inp[(i + 1) % inp.size()]
			var sp: float = inside.call(p)
			var sq: float = inside.call(q)
			if sp >= 0.0:
				out.append(p)
			if (sp >= 0.0) != (sq >= 0.0):
				out.append(p + (q - p) * (sp / (sp - sq)))
		if out.is_empty():
			break
	return out


## View transform for the card frame: card [0, 1]^2 sits in the middle of [-0.75, 1.75]^2.
static func _view(p: Vector2) -> Vector2:
	return (p + Vector2(0.75, 0.75)) / 2.5


func _result_polys(r: Dictionary, bm: Dictionary) -> Array:
	var polys := []
	for t in r.tri_paint.size():
		var pts := PackedVector2Array()
		for k in 3:
			pts.append(_view(_card_uv(r.pos[t * 3 + k])))
		var p: Dictionary = bm.paints[clampi(r.tri_paint[t], 0, bm.paints.size() - 1)]
		var c := Baked.paint_colour(p, r.param[t * 3].x)
		polys.append([pts, Color(c.r, c.g, c.b, 1.0).linear_to_srgb()])
	return polys


func _card_sheet() -> Image:
	var b = Baked.shared()
	var cases := [
		["fx-cells", Vector2(0.5, 0.5), Vector2(1, 1), "fx-cells card over cell (0.5, 0.5): white only"],
		["fx-cells", Vector2(0, 0), Vector2(0.5, 0.5), "fx-cells card over cell (0, 0): red only"],
		["fx-card", Vector2(0, 0), Vector2(1, 1), "fx-card, whole texture, alpha_test 0.5 (overlay turns opaque)"],
	]
	var rows := []
	var card_line := [[_rect_line(_view(Vector2(0, 0)), _view(Vector2(1, 1))), Color(0.2, 1, 0.3)]]
	for c in cases:
		var bm: Dictionary = b.get_mesh(c[0])
		var src := _card_src(c[1], c[2])
		# 1: the atlas in UV space with the footprint
		var atlas_polys := []
		var bi: PackedInt32Array = bm.indices
		for t in range(0, bi.size(), 3):
			var pts := PackedVector2Array([bm.positions[bi[t]], bm.positions[bi[t + 1]], bm.positions[bi[t + 2]]])
			var p: Dictionary = bm.paints[clampi(bm.paint[bi[t]], 0, bm.paints.size() - 1)]
			var col := Baked.paint_colour(p, bm.param[bi[t]].x)
			atlas_polys.append([pts, Color(col.r, col.g, col.b, maxf(col.a, 0.35)).linear_to_srgb()])
		var i_atlas: Image = await _draw(atlas_polys, [[_rect_line(c[1], c[2]), Color(0.2, 1, 0.3)]])
		# 2: old map_card
		var old: Dictionary = LegacyMapCard.map_card(src, bm, Vector4(1, 1, 0, 0))
		var i_old: Image = await _draw(_result_polys(old, bm), card_line)
		# 3: new clip
		var new: Dictionary = b.map_decal(c[0], src, Vector4(1, 1, 0, 0), false, 0.0, 0.5)
		var i_new: Image = await _draw(_result_polys(new, bm), card_line)
		# 4: expected: the bake's triangles clipped to the footprint, mapped linearly onto the card
		var exp_polys := []
		var size: Vector2 = c[2] - c[1]
		for t in range(0, bi.size(), 3):
			var p: Dictionary = bm.paints[clampi(bm.paint[bi[t]], 0, bm.paints.size() - 1)]
			var col := Baked.paint_colour(p, bm.param[bi[t]].x)
			if col.a < 0.5:
				continue
			var poly := _clip_rect([bm.positions[bi[t]], bm.positions[bi[t + 1]], bm.positions[bi[t + 2]]], c[1], c[2])
			if poly.size() < 3:
				continue
			var pts := PackedVector2Array()
			for q in poly:
				pts.append(_view((q - c[1]) / size))
			exp_polys.append([pts, Color(col.r, col.g, col.b, 1.0).linear_to_srgb()])
		var i_exp: Image = await _draw(exp_polys, card_line)
		var off := 0
		for q in old.pos:
			var uv := _card_uv(q)
			off += 1 if (uv.x < -1e-5 or uv.x > 1.0 + 1e-5 or uv.y < -1e-5 or uv.y > 1.0 + 1e-5) else 0
		var off_new := 0
		for q in new.pos:
			var uv := _card_uv(q)
			off_new += 1 if (uv.x < -1e-5 or uv.x > 1.0 + 1e-5 or uv.y < -1e-5 or uv.y > 1.0 + 1e-5) else 0
		rows.append({"label": c[3], "cells": [
			{"image": i_atlas, "label": "bake in UV, card footprint in green"},
			{"image": i_old, "label": "old: %d tris, %d vertices off the card" % [old.tri_paint.size(), off], "mark": Color(0.9, 0.2, 0.2) if off > 0 else null},
			{"image": i_new, "label": "new clip: %d tris, %d vertices off the card" % [new.tri_paint.size(), off_new]},
			{"image": i_exp, "label": "expected: %d clipped polygons" % exp_polys.size()}]})
	return await Sheet.render(self, "Card bake: fixture atlas | old map_card | new clip (slug_decal, cutout) | expected  (card frame, card quad green; each triangle flat in its first vertex's paint colour)",
			["fixture atlas + footprint", "old map_card (extrapolates)", "new clip", "expected"], rows, Vector2i(IMG, IMG))


# --------------------------------------------------------------------------- pixel sheet

const TEST_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://addons/sakuragaoka_station/core/slug/slug.gdshaderinc"
void fragment() {
	ALBEDO = slug_texture(slug_key, slug_frame, slug_uv, slug_wrap, UV).rgb;  // premultiplied over black
}
"""


func _render(key: String) -> SubViewport:
	var sh := Shader.new()
	sh.code = TEST_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	var a = SlugAtlas.shared()
	a.bind(sm, a.key_info(key, 64, 64), Vector2.ONE, Vector2.ZERO, false)
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.0
	cam.position = Vector3(0, 0, 1)
	vp.add_child(cam)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = sm
	vp.add_child(mi)
	return vp


## The fixture key's premultiplied colour at screen pixel (px, py), as slug_check computes it.
func _reference(key: String, px: int, py: int) -> Color:
	var em := Vector2((px + 0.5) / SIZE, (py + 0.5) / SIZE)
	var comp: Dictionary
	for c in _guest.enc.composites:
		if c.key.value == key:
			comp = c
	var shapes := {}
	for s in _guest.enc.shapes:
		shapes[s.key] = s.curves
	var acc := Color(0, 0, 0, 0)
	for l in comp.layers:
		var p := em - Vector2(l.transform[0], l.transform[1])
		var cov := Ref.coverage(shapes[l.key.value], p.x, p.y, Vector2(SIZE, SIZE))
		var col := Color(l.color[0], l.color[1], l.color[2], l.color[3])
		if int(l.gradient_id) > 0:
			var g: Dictionary = _guest.enc.gradients[l.gradient_id - 1]
			var m: Array = g.transform
			var t := clampf(m[0] * p.x + m[2] * p.y + m[4], 0, 1)
			var c0: Array = g.stops[0].color
			var c1: Array = g.stops[1].color
			col = Color(c0[0], c0[1], c0[2]).lerp(Color(c1[0], c1[1], c1[2]), t)
			col.a = l.color[3]
		var a := col.a * cov
		acc = Color(col.r * a + acc.r * (1 - a), col.g * a + acc.g * (1 - a), col.b * a + acc.b * (1 - a), a + acc.a * (1 - a))
	return acc


static func _box(img: Image, c: Vector2i, r: int, col: Color) -> void:
	for d in range(-r, r + 1):
		for e in [Vector2i(c.x + d, c.y - r), Vector2i(c.x + d, c.y + r), Vector2i(c.x - r, c.y + d), Vector2i(c.x + r, c.y + d)]:
			if e.x >= 0 and e.y >= 0 and e.x < img.get_width() and e.y < img.get_height():
				img.set_pixelv(e, col)


func _pixel_sheet() -> Image:
	var keys := ["fx-circle", "fx-hole", "fx-grad", "fx-layers"]
	var vps := {}
	for k in keys:
		vps[k] = _render(k)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var imgs := {}
	for k in keys:
		imgs[k] = vps[k].get_texture().get_image()
		imgs[k].convert(Image.FORMAT_RGBA8)
		vps[k].queue_free()
	var pts := [
		["fx-circle", 128, 128, "inside the circle"], ["fx-circle", 10, 10, "outside the circle"],
		["fx-circle", 208, 128, "circle edge (partial)"],
		["fx-hole", 66, 194, "square, below the hole"], ["fx-hole", 130, 98, "the hole"], ["fx-hole", 10, 10, "outside the square"],
		["fx-grad", 128, 128, "gradient midpoint"], ["fx-grad", 8, 128, "gradient red end"], ["fx-grad", 248, 60, "gradient blue end"],
		["fx-layers", 128, 128, "red 0.5 over green"], ["fx-layers", 10, 10, "green alone"],
	]
	var rows := []
	for p in pts:
		var img: Image = imgs[p[0]]
		var got: Color = img.get_pixel(p[1], p[2]).srgb_to_linear()
		var want := _reference(p[0], p[1], p[2])
		var dmax := maxf(absf(got.r - want.r), maxf(absf(got.g - want.g), absf(got.b - want.b)))
		var crop := Image.create(25, 25, false, Image.FORMAT_RGBA8)
		crop.fill(Color(0.3, 0.3, 0.32))
		crop.blit_rect(img, Rect2i(p[1] - 12, p[2] - 12, 25, 25), Vector2i(0, 0))
		crop.resize(200, 200, Image.INTERPOLATE_NEAREST)
		_box(crop, Vector2i(100, 100), 5, Color(0.2, 1, 0.3))
		var sw := Image.create(200, 200, false, Image.FORMAT_RGBA8)
		sw.fill_rect(Rect2i(0, 0, 100, 200), Color(got.r, got.g, got.b).linear_to_srgb())
		sw.fill_rect(Rect2i(100, 0, 100, 200), Color(want.r, want.g, want.b).linear_to_srgb())
		var whole: Image = img.duplicate()
		_box(whole, Vector2i(p[1], p[2]), 6, Color(0.2, 1, 0.3))
		rows.append({"label": "%s (%d, %d): %s   max |GPU - ref| %.3f %s" % [p[0], p[1], p[2], p[3], dmax, "ok" if dmax <= 0.02 else "FAIL"],
			"color": Color(1, 0.95, 0.7) if dmax <= 0.02 else Color(1, 0.4, 0.4),
			"cells": [{"image": crop, "label": "GPU, 25 px around (boxed)"},
				{"image": sw, "label": "GPU (%.3f %.3f %.3f)\nref  (%.3f %.3f %.3f)" % [got.r, got.g, got.b, want.r, want.g, want.b]},
				{"image": whole, "label": "whole 256 px render"}]})
	return await Sheet.render(self, "Slug GPU vs CPU reference (render.hpp coverage), linear RGB",
			["GPU crop", "GPU (left) | reference (right)", "render"], rows, Vector2i(200, 200))
