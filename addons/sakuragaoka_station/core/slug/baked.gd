# Canvas textures baked to planar triangles by slug.elf (core/slug/guest.gd), the pack's
# recommended draw mode per key, and the mapping of the triangles onto a surface through the guest's
# slug_decal, which clips them to each face's UV footprint: a card (an alpha-cut quad) is replaced
# by them (no lift, cutout bake), a regular textured face gets them as a lifted decal. Guest calls:
#
#   slug_cost(key) -> Dictionary; "mode": "mesh" | "slug" | "mean" (other fields unused here)
#   slug_mesh(key) -> Dictionary, empty when the key has no bake:
#     vertices   PackedFloat32Array 3N  mesh_wire.h layout: x = u, y = v (texture UV 0..1, three.js
#                                       convention, v = 1 the canvas top), z = 0
#     triangles  PackedInt32Array 3F    counter-clockwise in UV; the planar, non-overlapping opaque
#                                       base first, then the translucent overlay
#     paint      PackedInt32Array N     paint id per vertex
#     param      PackedFloat32Array 2N  linear gradient: t in [0] (exact under interpolation);
#                                       radial: gradient-space position
#     paints     PackedFloat32Array     [n, per paint: type (0 solid, 1 linear, 2 radial), k,
#                                       k * (t, r, g, b, a)]; solid: k = 1; colours linear
#     overlay    PackedInt32Array       [first index, index count] of the overlay in triangles
#   slug_decal(key, vertices 3N, normals 3N or empty, uvs 2N, triangles 3F (mesh_wire, CCW
#              outward), uv_xform [repeat.x, repeat.y, offset.x, offset.y, wrap 0/1],
#              lift_cap [base lift, overlay lift (the input's units), cap (max output triangles),
#              alpha_test (0: normal bake; > 0: cutout bake for a card, no overlay)])
#              -> Dictionary (the sandbox passes at most 7 arguments, so the cap rides in lift_cap):
#     capped     bool                   past cap (nothing else; the host draws the face by Slug)
#     vertices   PackedFloat32Array 9T  unindexed triangles, counter-clockwise outward, lifted
#     normals    PackedFloat32Array 9T
#     paint      PackedInt32Array T     paint id per triangle
#     param      PackedFloat32Array 6T  per vertex, as slug_mesh's
#     overlay_from int                  first overlay triangle
#
#   var b = Baked.shared()      # null without slug.elf
#   b.mode("st-floor")          # "" when the pack says nothing
#   b.get_mesh("st-floor")      # {positions, indices, paint, param, paints, colours, overlay, radial} or null
extends RefCounted

const Pack = preload("res://addons/sakuragaoka_station/core/slug/pack.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")

## Cap on decal triangles per object; past it the surface is drawn with Slug instead.
const DECAL_TRI_CAP := 6000
## Decal lift off the surface (m) for the opaque base and the translucent overlay.
const DECAL_LIFT := 0.002
const OVERLAY_LIFT := 0.004

static var _shared = null
static var _tried := false

var guest
var _meshes := {}
var _modes := {}


static func shared():
	if not _tried:
		_tried = true
		var g = Pack.shared()
		if g != null:
			_shared = new()
			_shared.guest = g
	return _shared


static func reset() -> void:
	_tried = false
	_shared = null


func mode(key: String) -> String:
	if not _modes.has(key):
		var r = guest.call_fn("slug_cost", [key])
		_modes[key] = str(r.get("mode", "")) if r is Dictionary else ""
	return _modes[key]


func get_mesh(key: String):
	if not _meshes.has(key):
		var r = guest.call_fn("slug_mesh", [key])
		_meshes[key] = _parse(r) if r is Dictionary and not r.is_empty() else null
	return _meshes[key]


static func _parse(r: Dictionary):
	var v: PackedFloat32Array = r.get("vertices", PackedFloat32Array())
	var idx: PackedInt32Array = r.get("triangles", PackedInt32Array())
	if v.size() / 3 == 0 or idx.size() % 3 != 0:
		return null
	var pf: PackedFloat32Array = r.get("paints", PackedFloat32Array([0]))
	var k := Kernels.parse_mesh(v, r.get("paint", PackedInt32Array()), r.get("param", PackedFloat32Array()), pf)
	var paints := decode_paints(pf)
	if paints.is_empty():
		paints = [{"type": "solid", "stops": [{"t": 0.0, "color": Color(1, 1, 1)}]}]
	var ov: PackedInt32Array = r.get("overlay", PackedInt32Array([idx.size(), 0]))
	return {"positions": k.positions, "indices": idx, "colours": k.colours, "paint": k.paint, "param": k.param, "paints": paints,
			"overlay": Vector2i(ov[0], ov[1]) if ov.size() >= 2 else Vector2i(idx.size(), 0), "radial": k.radial}


static func decode_paints(f: PackedFloat32Array) -> Array:
	return Kernels.decode_paints(f)


## A paint's linear colour; t is the linear gradient parameter.
static func paint_colour(p: Dictionary, t: float) -> Color:
	return Kernels.paint_colour(p, t)


static func ramp(stops: Array, t: float) -> Color:
	return Kernels.ramp(stops, t)


# ------------------------------------------------------------------------------------- mapping

## Barycentric coordinates of p in triangle (a, b, c), or null for a degenerate triangle.
static func bary(p: Vector2, a: Vector2, b: Vector2, c: Vector2):
	var v0 := b - a
	var v1 := c - a
	var d := v0.x * v1.y - v1.x * v0.y
	if absf(d) < 1e-14:
		return null
	var v2 := p - a
	var l1 := (v2.x * v1.y - v1.x * v2.y) / d
	var l2 := (v0.x * v2.y - v2.x * v0.y) / d
	return Vector3(1.0 - l1 - l2, l1, l2)


## Godot-wound (clockwise front) triangle's outward normal.
static func face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var n := (c - a).cross(b - a)
	return n.normalized() if n.length_squared() > 1e-24 else Vector3.UP


## The key's baked triangles over a surface's faces, by the guest's slug_decal: tiled by repeat,
## clipped to each face's UV footprint (so a face that samples one cell of an atlas gets only that
## cell), placed by the face's barycentric coordinates. src: {pos: PackedVector3Array, nor (may be
## empty), uv: PackedVector2Array (geometry UV), idx: PackedInt32Array (Godot winding)}; xf: the
## texture's repeat.xy, offset.zw.
##   decal: lift_scale > 0 lifts the base by lift_scale x DECAL_LIFT, the overlay by OVERLAY_LIFT.
##   card:  lift_scale 0 and alpha_test > 0: the card is replaced, so nothing is lifted, and the
##          guest bakes a cutout (composite alpha >= alpha_test opaque, the rest dropped, no overlay),
##          as three.js alphaTest draws it.
## Returns unindexed triangles in Godot winding: {pos, nor, param (per vertex), tri_paint (per
## triangle), overlay_from (first overlay triangle)}, or {"capped": true} past DECAL_TRI_CAP.
func map_decal(key: String, src: Dictionary, xf: Vector4, wrap: bool, lift_scale: float = 1.0, alpha_test: float = 0.0) -> Dictionary:
	var pos: PackedVector3Array = src.pos
	var v := PackedFloat32Array()
	v.resize(pos.size() * 3)
	for i in pos.size():
		v[i * 3] = pos[i].x
		v[i * 3 + 1] = pos[i].y
		v[i * 3 + 2] = pos[i].z
	var nv := PackedFloat32Array()
	if src.nor.size() == pos.size():
		nv.resize(pos.size() * 3)
		for i in pos.size():
			nv[i * 3] = src.nor[i].x
			nv[i * 3 + 1] = src.nor[i].y
			nv[i * 3 + 2] = src.nor[i].z
	var uv := PackedFloat32Array()
	uv.resize(src.uv.size() * 2)
	for i in src.uv.size():
		uv[i * 2] = src.uv[i].x
		uv[i * 2 + 1] = src.uv[i].y
	var idx: PackedInt32Array = src.idx
	var f := PackedInt32Array()
	f.resize(idx.size() - idx.size() % 3)
	for t in range(0, f.size(), 3):  # Godot clockwise -> mesh_wire counter-clockwise
		f[t] = idx[t]
		f[t + 1] = idx[t + 2]
		f[t + 2] = idx[t + 1]
	var r = guest.call_fn("slug_decal", [key, v, nv, uv, f, PackedFloat32Array([xf.x, xf.y, xf.z, xf.w, 1.0 if wrap else 0.0]),
			PackedFloat32Array([DECAL_LIFT * lift_scale, OVERLAY_LIFT * lift_scale, DECAL_TRI_CAP, alpha_test])])
	if not (r is Dictionary):
		return {}
	if r.get("capped", false):
		return {"capped": true}
	var ov: PackedFloat32Array = r.get("vertices", PackedFloat32Array())
	var on: PackedFloat32Array = r.get("normals", PackedFloat32Array())
	var op: PackedFloat32Array = r.get("param", PackedFloat32Array())
	var m := ov.size() / 3
	var u := Kernels.unpack_tris(ov, on, op)
	var out_pos: PackedVector3Array = u[0]
	var out_nor: PackedVector3Array = u[1]
	var out_prm: PackedVector2Array = u[2]
	var paint: PackedInt32Array = r.get("paint", PackedInt32Array())
	paint.resize(m / 3)
	return {"pos": out_pos, "nor": out_nor, "param": out_prm, "tri_paint": paint, "overlay_from": int(r.get("overlay_from", m / 3))}
