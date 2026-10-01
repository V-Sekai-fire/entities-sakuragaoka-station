# A small slughorn atlas writer for test fixtures: the packing of slughorn's Atlas::build()
# (slughorn.cpp buildShapeBands + packTextures: auto metrics, up to 16 uniform bands per axis
# snapped to the 32-slot indirection grid, curves sorted by descending max coordinate, endpoint-
# shared curve texels, per-shape band blocks that never straddle a row) serialized as
# slughorn/serial.hpp's .slug JSON (base64 bufferViews). Shapes are authored in canvas em-space
# and moved to their own origin as slughorn's Canvas does, the layer transform keeping the offset.
#   var e = Encoder.new()
#   var l = e.layer("circle", curves, Color.RED)       # curves: [[x1,y1,x2,y2,x3,y3], ...]
#   e.composite("fx-circle", [l], {"width": 64, "height": 64, "scale": 1.0 / 64, "y_down": true})
#   FileAccess.open(p, FileAccess.WRITE).store_string(JSON.stringify(e.to_json(), " "))
extends RefCounted

const IS := 32

var tex_width := 512
var shapes := []      # [{key, curves, metrics...}]
var composites := []
var gradients := []
var _shape_keys := {}


## A shape registered under key (canvas em curves, localized) and the layer that places it.
func layer(key: String, curves: Array, colour: Color, gradient_id: int = 0) -> Dictionary:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for c in curves:
		for i in 3:
			lo = lo.min(Vector2(c[i * 2], c[i * 2 + 1]))
			hi = hi.max(Vector2(c[i * 2], c[i * 2 + 1]))
	var local := []
	for c in curves:
		local.append([c[0] - lo.x, c[1] - lo.y, c[2] - lo.x, c[3] - lo.y, c[4] - lo.x, c[5] - lo.y])
	if not _shape_keys.has(key):
		_shape_keys[key] = true
		shapes.append({"key": key, "curves": local})
	return {"key": {"type": "name", "value": key}, "color": [colour.r, colour.g, colour.b, colour.a],
			"transform": [lo.x, lo.y, 0.0], "effect_id": 0, "effect_param": 0.0, "gradient_id": gradient_id,
			"draw_mode": 0, "blend_mode": 0, "_origin": lo}


## A linear gradient from canvas em point a to b; returns its 1-based id. The matrix is in the
## layer's local em-space, so it needs the layer's origin (layer()._origin).
func linear_gradient(a: Vector2, b: Vector2, origin: Vector2, stops: Array) -> int:
	var d := b - a
	var l2 := d.length_squared()
	var a0 := a - origin
	gradients.append({"type": "linear", "transform": [d.x / l2, 0.0, d.y / l2, 1.0, -(a0.x * d.x + a0.y * d.y) / l2, 0.0],
			"inner_radius": 0.0, "start_angle": 0.0, "end_angle": 1.0, "stops": stops})
	return gradients.size()


func composite(key: String, layers: Array, frame = null) -> void:
	var ls := []
	for l in layers:
		var c: Dictionary = l.duplicate()
		c.erase("_origin")
		ls.append(c)
	var c := {"key": {"type": "name", "value": key}, "advance": 0.0, "layers": ls}
	if frame != null:
		c["frame"] = frame
	composites.append(c)


# --------------------------------------------------------------------------------------- packing

static func _bands(curves: Array, axis: int, lo: float, rng: float) -> Dictionary:
	var n := curves.size()
	var nb := mini(16, maxi(1, n / 2))
	var bounds := []
	bounds.resize(nb + 1)
	bounds[0] = lo
	bounds[nb] = lo + rng
	for i in range(1, nb):
		bounds[i] = lo + roundf(float(i) / nb * IS) / IS * rng
	var lists := []
	for b in nb:
		var l := []
		for ci in n:
			var c: Array = curves[ci]
			var mn := minf(c[axis], minf(c[axis + 2], c[axis + 4]))
			var mx := maxf(c[axis], maxf(c[axis + 2], c[axis + 4]))
			if mx >= bounds[b] and mn <= bounds[b + 1]:
				l.append(ci)
		# sort by the OTHER axis' max, descending (hbands: max x; vbands: max y)
		var o := 1 - axis
		l.sort_custom(func(p, q):
			var cp: Array = curves[p]
			var cq: Array = curves[q]
			var xp := maxf(cp[o], maxf(cp[o + 2], cp[o + 4]))
			var xq := maxf(cq[o], maxf(cq[o + 2], cq[o + 4]))
			return xp > xq if xp != xq else p < q)
		lists.append(l)
	var indir := []
	for q in IS:
		var v: float = lo + (q + 0.5) / IS * rng
		var band := nb - 1
		for b in nb - 1:
			if v < bounds[b + 1]:
				band = b
				break
		indir.append(band)
	return {"lists": lists, "indir": indir}


func to_json() -> Dictionary:
	var k := pack()
	return {
		"asset": {"version": "1.0", "generator": "slughorn"},
		"tex_width": tex_width,
		"packing_stats": {"curve_format": "RGBA32F", "band_format": "RG16UI", "curve_texels_used": k.curve_texels,
				"curve_texels_padding": 0, "curve_texels_total": tex_width * k.curve_height, "band_texels_used": k.band_texels,
				"band_texels_padding": 0, "band_texels_total": tex_width * k.band_height},
		"bufferViews": [
			{"byteOffset": 0, "byteLength": k.curves.size(), "format": "RGBA32F", "width": tex_width, "height": k.curve_height, "data": Marshalls.raw_to_base64(k.curves)},
			{"byteOffset": 0, "byteLength": k.bands.size(), "format": "RG16UI", "width": tex_width, "height": k.band_height, "data": Marshalls.raw_to_base64(k.bands)},
		],
		"curve_texture": 0,
		"band_texture": 1,
		"gradients": gradients,
		"shapes": k.shapes,
		"composites": composites,
	}


## The packed textures and shape records: {curves, curve_height, curve_texels, bands, band_height,
## band_texels, shapes (serial.hpp shape objects)}.
func pack() -> Dictionary:
	# curve texels
	var total := 0
	for s in shapes:
		for i in s.curves.size():
			var c: Array = s.curves[i]
			total += 1 if i > 0 and c[0] == s.curves[i - 1][4] and c[1] == s.curves[i - 1][5] else 2
	var ch := maxi(1, ceili(float(total) / tex_width))
	var cpx := PackedFloat32Array()
	cpx.resize(tex_width * ch * 4)
	var cur := 0
	var built := []
	for s in shapes:
		var cv: Array = s.curves
		var locs := []
		var prev_tail := 0
		for i in cv.size():
			var c: Array = cv[i]
			if i > 0 and c[0] == cv[i - 1][4] and c[1] == cv[i - 1][5]:
				locs.append(prev_tail)
				cpx[prev_tail * 4 + 2] = c[2]
				cpx[prev_tail * 4 + 3] = c[3]
				cpx[cur * 4] = c[4]
				cpx[cur * 4 + 1] = c[5]
				prev_tail = cur
				cur += 1
			else:
				locs.append(cur)
				for k in 4:
					cpx[cur * 4 + k] = c[k]
				cpx[(cur + 1) * 4] = c[4]
				cpx[(cur + 1) * 4 + 1] = c[5]
				prev_tail = cur + 1
				cur += 2
		var lo := Vector2(INF, INF)
		var hi := -lo
		for c in cv:
			for i in 3:
				lo = lo.min(Vector2(c[i * 2], c[i * 2 + 1]))
				hi = hi.max(Vector2(c[i * 2], c[i * 2 + 1]))
		var rng := (hi - lo).max(Vector2(1e-6, 1e-6))
		built.append({"s": s, "locs": locs, "lo": lo, "rng": rng, "h": _bands(cv, 1, lo.y, rng.y), "v": _bands(cv, 0, lo.x, rng.x)})
	# band texels
	var bt := []  # [index, r, g]
	var cursor := 0
	var json_shapes := []
	for b in built:
		var nh: int = b.h.lists.size()
		var nv: int = b.v.lists.size()
		var block := 2 * IS + nh + nv
		if cursor % tex_width + block > tex_width:
			cursor += tex_width - cursor % tex_width
		var start := cursor
		for q in IS:
			bt.append([start + q, b.h.indir[q], 0])
			bt.append([start + IS + q, b.v.indir[q], 0])
		var at := start + block
		var hdr := 0
		for lists in [b.h.lists, b.v.lists]:
			for l in lists:
				bt.append([start + 2 * IS + hdr, l.size(), at - start])
				hdr += 1
				for ci in l:
					var loc: int = b.locs[ci]
					bt.append([at, loc % tex_width, loc / tex_width])
					at += 1
		cursor = at
		var sc: Vector2 = Vector2(IS, IS) / b.rng
		json_shapes.append({"key": {"type": "name", "value": b.s.key}, "band_tex_x": start % tex_width, "band_tex_y": start / tex_width,
				"band_max_x": nv - 1, "band_max_y": nh - 1, "band_scale_x": sc.x, "band_scale_y": sc.y,
				"band_offset_x": -b.lo.x * sc.x, "band_offset_y": -b.lo.y * sc.y,
				"bearing_x": b.lo.x, "bearing_y": b.lo.y + b.rng.y, "width": b.rng.x, "height": b.rng.y, "advance": b.rng.x,
				"origin_x": 0.0, "origin_y": 0.0, "origin": {"type": "Default", "x": 0.0, "y": 0.0}})
	var bh := maxi(1, ceili(float(cursor) / tex_width))
	var bb := PackedByteArray()
	bb.resize(tex_width * bh * 4)
	for t in bt:
		bb.encode_u16(t[0] * 4, t[1])
		bb.encode_u16(t[0] * 4 + 2, t[2])
	return {"curves": cpx.to_byte_array(), "curve_height": ch, "curve_texels": cur, "bands": bb, "band_height": bh,
			"band_texels": bt.size(), "shapes": json_shapes}


# ------------------------------------------------------------------------------- path helpers

## A polygon's edges as straight quadratics (control at the midpoint), closed.
static func polygon(pts: Array) -> Array:
	var out := []
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var m := (a + b) * 0.5
		out.append([a.x, a.y, m.x, m.y, b.x, b.y])
	return out


## A circle as n quadratic arcs, counter-clockwise in its own axes.
static func circle(c: Vector2, r: float, n: int = 8) -> Array:
	var out := []
	var h := PI / n
	for k in n:
		var a0 := 2.0 * h * k
		var a1 := 2.0 * h * (k + 1)
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a0 + h), sin(a0 + h)) * (r / cos(h))
		var p2 := c + Vector2(cos(a1), sin(a1)) * r
		if k == n - 1:
			p2 = c + Vector2(r, 0.0)
		out.append([p0.x, p0.y, p1.x, p1.y, p2.x, p2.y])
	return out


# --------------------------------------------------------------------------------- stamp layers
# Stamp layers in slug_atlas()'s wire format (core/slug/stamps.gd documents it). A stamp layer here:
# {"g": G, "instances": [{"inv": Transform2D (canvas em -> prototype frame), "proto": id,
# "paint": 0 or a 1-based gradient id, "color": Color, "uv_box": Rect2 (the AA-padded bbox in key
# UV)}], "lists": optional, G * G
# arrays of instance indices (bin_cells() when absent; tests pass corrupted ones)}.

## Per cell (index j * G + i, cell (i, j) = floor(uv * G)), the instances whose padded bbox touches
## it, in paint order.
static func bin_cells(g: int, instances: Array) -> Array:
	var lists := []
	for c in g * g:
		lists.append([])
	for k in instances.size():
		var b: Rect2 = instances[k].uv_box
		var i0 := clampi(floori(b.position.x * g), 0, g - 1)
		var i1 := clampi(floori(b.end.x * g), 0, g - 1)
		var j0 := clampi(floori(b.position.y * g), 0, g - 1)
		var j1 := clampi(floori(b.end.y * g), 0, g - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				lists[j * g + i].append(k)
	return lists


## The stamp_* arrays. protos: [[kind, layer index or -1], ...]; means: 4 bytes per cell, stamp
## layers in order.
static func stamp_wire(stamp_layers: Array, protos: Array, means: PackedByteArray) -> Dictionary:
	var pr := PackedFloat32Array()
	for p in protos:
		pr.append_array(PackedFloat32Array([p[0], p[1]]))
	var inst := PackedFloat32Array()
	var sl := PackedInt32Array()
	var u16 := PackedInt32Array()  # the cell stream, two u16 per texel
	for s in stamp_layers:
		var g: int = s.g
		var lists: Array = s.lists if s.has("lists") else bin_cells(g, s.instances)
		var first := inst.size() / 12
		for it in s.instances:
			var m: Transform2D = it.inv
			var c: Color = it.color
			inst.append_array(PackedFloat32Array([m.x.x, m.x.y, m.y.x, m.y.y, m.origin.x, m.origin.y, it.proto, it.get("paint", 0),
					c.r, c.g, c.b, c.a]))
		var base := u16.size() / 2
		var maxc := 0
		var at := 2 * g * g
		var body := PackedInt32Array()
		for l in lists:
			u16.append_array(PackedInt32Array([at, l.size()]))
			maxc = maxi(maxc, l.size())
			for k in l:
				body.append(k)
			at += l.size()
		if body.size() % 2:
			body.append(0)
		u16.append_array(body)
		sl.append_array(PackedInt32Array([g, base, first, s.instances.size(), maxc]))
	var cb := PackedByteArray()
	cb.resize(u16.size() * 2)
	for i in u16.size():
		cb.encode_u16(i * 2, u16[i])
	return {"stamp_protos": pr, "stamp_instances": inst, "stamp_layers": sl, "stamp_cells": cb, "stamp_means": means}
