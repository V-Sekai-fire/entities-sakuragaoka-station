# A stand-in for slug.elf answering its API (slug_atlas, slug_cost, slug_mesh, slug_decal) from the
# hand-made fixture (make_fixture.gd), in exactly the wire formats core/slug/atlas.gd and
# core/slug/baked.gd document. Tests set core/slug/guest.gd's Guest.override to one of these.
# slug_decal is a reference implementation of the guest's decal clip (Sutherland-Hodgman of each
# baked triangle, tiled by repeat, against each face's UV footprint), kept here, not in the port.
# slug_atlas also carries the stamp layers (make_fixture.gd stamps(), core/slug/stamps.gd's wire
# format) and the fx-stamps key; stamp_means is the box filter of reference.gd's raster of each
# stamp layer at STAMP_SIZE px over the key.
extends RefCounted

const Fixture = preload("res://tools/slug_fixture/make_fixture.gd")
const Baked = preload("res://addons/sakuragaoka_station/core/slug/baked.gd")
const Encoder = preload("res://tools/slug_fixture/encoder.gd")
const Ref = preload("res://tools/slug_fixture/reference.gd")
const STAMP_SIZE := 256

var name := "fixture_guest"
var enc
var bakes := {}
var calls := {}
var stamps := {}          # make_fixture.gd stamps()
var stamp_raster := {}    # stamp layer -> PackedColorArray (Ref.raster, STAMP_SIZE^2, premultiplied)
var stamp_means := PackedByteArray()
## Negative controls: cell lists to serve instead of the binned ones ({stamp layer: Array of
## G * G lists}); ignore_paint serves every instance's paint id as 0.
var stamp_lists := {}
var ignore_paint := false
var layer_index := {}     # "key/i" -> global layer index


## Other content (tools/slug_stamp_bench.gd): an encoder and a stamps() Dictionary whose "keys"
## are extra composites ({"stamp": i} layers allowed); means: false serves zero means, skipping the
## reference raster.
func _init(e = null, st = null, means := true) -> void:
	enc = e if e != null else Fixture.encoder()
	bakes = Fixture.bakes()
	stamps = st if st != null else Fixture.stamps(enc)
	for si in stamps.layers.size():
		var sl: Dictionary = stamps.layers[si]
		if not means:
			stamp_means.resize(stamp_means.size() + sl.g * sl.g * 4)
			continue
		var img := Ref.raster(sl.instances, STAMP_SIZE)
		stamp_raster[si] = img
		var g: int = sl.g
		var cpx := STAMP_SIZE / g
		for j in g:
			for i in g:
				var sum := Color(0, 0, 0, 0)
				# cell (i, j) is uv [i, i + 1) / g x [j, j + 1) / g; screen rows run down from v = 1
				for y in range(STAMP_SIZE - (j + 1) * cpx, STAMP_SIZE - j * cpx):
					for x in range(i * cpx, (i + 1) * cpx):
						sum += img[y * STAMP_SIZE + x]
				sum /= float(cpx * cpx)
				for c in [sum.r, sum.g, sum.b, sum.a]:
					stamp_means.append(clampi(roundi(c * 255.0), 0, 255))


## The mean colour of stamp layer si's cell (premultiplied), as served.
func stamp_mean(si: int, cell: int) -> Color:
	var at := 0
	for k in si:
		at += stamps.layers[k].g * stamps.layers[k].g
	var o := (at + cell) * 4
	return Color(stamp_means[o] / 255.0, stamp_means[o + 1] / 255.0, stamp_means[o + 2] / 255.0, stamp_means[o + 3] / 255.0)


func stamp_wire() -> Dictionary:
	var protos := []
	for p in stamps.protos:
		protos.append([p[0], layer_index.get("%s/%d" % [p[1], p[2]], -1)])
	var ls := []
	for si in stamps.layers.size():
		var l: Dictionary = stamps.layers[si].duplicate()
		if ignore_paint:
			var ins := []
			for it in l.instances:
				var c: Dictionary = it.duplicate()
				c.paint = 0
				ins.append(c)
			l.instances = ins
		if stamp_lists.has(si):
			l["lists"] = stamp_lists[si]
		ls.append(l)
	return Encoder.stamp_wire(ls, protos, stamp_means)


func has_fn(fn: String) -> bool:
	return fn in ["slug_atlas", "slug_cost", "slug_mesh", "slug_decal"]


func call_fn(fn: String, args: Array = []):
	calls[fn] = calls.get(fn, 0) + 1
	match fn:
		"slug_atlas":
			return _atlas()
		"slug_cost":
			var b = bakes.get(args[0])
			return {"mode": b.mode} if b != null else {}
		"slug_mesh":
			var b = bakes.get(args[0])
			return b if b != null and b.has("vertices") else {}
		"slug_decal":
			return callv("_decal", args)
	return null


func _atlas() -> Dictionary:
	var k: Dictionary = enc.pack()
	var shapes := {}
	for s in k.shapes:
		shapes[s.key.value] = s
	var keys := PackedStringArray()
	var kl := PackedInt32Array()
	var kf := PackedFloat32Array()
	var layers := PackedFloat32Array()
	var n := 0
	var comps: Array = enc.composites.duplicate()
	if stamps.has("keys"):
		comps.append_array(stamps.keys)
	else:
		# fx-stamps: a grey canvas (fx-grad's square, no gradient) under stamp layer 1
		var grey: Dictionary = enc.composites.filter(func(c): return c.key.value == "fx-grad")[0].layers[0].duplicate()
		grey.gradient_id = 0
		grey.color = [Fixture.STAMP_BASE.r, Fixture.STAMP_BASE.g, Fixture.STAMP_BASE.b, 1.0]
		comps.append({"key": {"type": "name", "value": "fx-stamps"}, "layers": [grey, {"stamp": 1}], "frame": Fixture.FRAME})
	for c in comps:
		keys.append(c.key.value)
		kl.append(n)
		var count := 0
		for li in c.layers.size():
			var l: Dictionary = c.layers[li]
			layer_index["%s/%d" % [c.key.value, li]] = n + count
			if l.has("stamp"):
				# a stamp layer: blend mode 100, slot 14 its stamp_layers index, no shape
				var srec := PackedFloat32Array()
				srec.resize(24)
				srec[14] = l.stamp
				srec[15] = 100
				layers.append_array(srec)
				count += 1
				continue
			if int(l.draw_mode) != 0 or not shapes.has(l.key.value):
				continue
			var s: Dictionary = shapes[l.key.value]
			var rec := [s.band_tex_x, s.band_tex_y, s.band_max_x, s.band_max_y,
					s.band_scale_x, s.band_scale_y, s.band_offset_x, s.band_offset_y,
					s.bearing_x, s.bearing_y, s.width, s.height,
					l.transform[0] - s.origin_x, l.transform[1] - s.origin_y, l.gradient_id, l.blend_mode,
					l.color[0], l.color[1], l.color[2], l.color[3], 0, 0, 0, 0]
			layers.append_array(PackedFloat32Array(rec))
			count += 1
		kl.append(count)
		n += count
		var f = c.get("frame")
		kf.append_array(PackedFloat32Array([f.width, f.height, f.scale, 1.0 if f.y_down else 0.0]) if f != null else PackedFloat32Array([0, 0, 0, 0]))
	var sg: Array = stamps.get("gradients", [])
	var g := PackedFloat32Array([enc.gradients.size() + sg.size()])
	for gr in enc.gradients + sg:
		g.append(float({"linear": 0, "radial": 1, "sweep": 2, "affine_radial": 3}[gr.type]))
		g.append_array(PackedFloat32Array(gr.transform))
		g.append_array(PackedFloat32Array([gr.inner_radius, gr.start_angle, gr.end_angle, gr.stops.size()]))
		for st in gr.stops:
			g.append_array(PackedFloat32Array([st.t] + st.color))
	var r := {"tex_width": enc.tex_width, "curve_format": "RGBA32F", "curve_height": k.curve_height, "curves": k.curves,
			"band_height": k.band_height, "bands": k.bands, "keys": keys, "key_layers": kl, "key_frames": kf,
			"layers": layers, "gradients": g}
	r.merge(stamp_wire())
	return r


# ------------------------------------------------------------------------------ slug_decal

func _decal(key: String, v: PackedFloat32Array, nv: PackedFloat32Array, uvs: PackedFloat32Array, f: PackedInt32Array,
		xform: PackedFloat32Array, lift: PackedFloat32Array) -> Dictionary:
	var cap: int = int(lift[2]) if lift.size() >= 3 else 1 << 62
	# alpha_test > 0: a card's cutout bake. Overlay triangles whose paint alpha reaches it become
	# opaque base, the rest are dropped; nothing is an overlay.
	var alpha_test: float = lift[3] if lift.size() >= 4 else 0.0
	var b = bakes.get(key)
	if b == null or not b.has("vertices"):
		return {"vertices": PackedFloat32Array(), "normals": PackedFloat32Array(), "paint": PackedInt32Array(),
				"param": PackedFloat32Array(), "overlay_from": 0}
	var bv: PackedFloat32Array = b.vertices
	var bi: PackedInt32Array = b.triangles
	var bp := PackedVector2Array()
	for i in bv.size() / 3:
		bp.append(Vector2(bv[i * 3], bv[i * 3 + 1]))
	var nb := bi.size() / 3
	var paints := Baked.decode_paints(b.paints)
	var ov_first: int = b.overlay[0] if b.overlay[1] > 0 else bi.size()
	var boxes := []
	for t in nb:
		boxes.append(Rect2(bp[bi[t * 3]], Vector2.ZERO).expand(bp[bi[t * 3 + 1]]).expand(bp[bi[t * 3 + 2]]))
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	for i in v.size() / 3:
		pos.append(Vector3(v[i * 3], v[i * 3 + 1], v[i * 3 + 2]))
		if nv.size() == v.size():
			nor.append(Vector3(nv[i * 3], nv[i * 3 + 1], nv[i * 3 + 2]))
	var rep := Vector2(xform[0], xform[1])
	var off := Vector2(xform[2], xform[3])
	var wrap := xform[4] > 0.5
	# base then overlay: vertices, normals, params, paints (kept apart, joined at the end)
	var bv3 := PackedFloat32Array()
	var bn3 := PackedFloat32Array()
	var bp2 := PackedFloat32Array()
	var bpaint := PackedInt32Array()
	var ov3 := PackedFloat32Array()
	var on3 := PackedFloat32Array()
	var op2 := PackedFloat32Array()
	var opaint := PackedInt32Array()
	var tris := 0
	for s in range(0, f.size() - 2, 3):
		var ia := f[s]
		var ib := f[s + 1]
		var ic := f[s + 2]
		var ta := Vector2(uvs[ia * 2], uvs[ia * 2 + 1]) * rep + off
		var tb := Vector2(uvs[ib * 2], uvs[ib * 2 + 1]) * rep + off
		var tc := Vector2(uvs[ic * 2], uvs[ic * 2 + 1]) * rep + off
		var area := (tb - ta).cross(tc - ta)
		if absf(area) < 1e-14:
			continue
		var pa := pos[ia]
		var pb := pos[ib]
		var pc := pos[ic]
		var fn := (pb - pa).cross(pc - pa).normalized()  # counter-clockwise outward
		var foot := Rect2(ta, Vector2.ZERO).expand(tb).expand(tc)
		var i0 := floori(foot.position.x) if wrap else 0
		var i1 := floori(foot.end.x) if wrap else 0
		var j0 := floori(foot.position.y) if wrap else 0
		var j1 := floori(foot.end.y) if wrap else 0
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				var sh := Vector2(i, j)
				for t in nb:
					var box: Rect2 = boxes[t]
					box.position += sh
					if not box.intersects(foot, true):
						continue
					var q := [bp[bi[t * 3]] + sh, bp[bi[t * 3 + 1]] + sh, bp[bi[t * 3 + 2]] + sh]
					var poly := _clip(q, [ta, tb, tc], area > 0.0)
					if poly.size() < 3:
						continue
					var ovl: bool = t * 3 >= ov_first
					if alpha_test > 0.0 and ovl:
						if paints[clampi(b.paint[bi[t * 3]], 0, paints.size() - 1)].stops[0].color.a < alpha_test:
							continue
						ovl = false
					var lf: float = lift[1] if ovl else lift[0]
					var pts := []
					var nrs := []
					var prs := []
					for p in poly:
						var w: Vector3 = _bary(p, ta, tb, tc)
						var wb = _bary(p, q[0], q[1], q[2])
						var n := (nor[ia] * w.x + nor[ib] * w.y + nor[ic] * w.z).normalized() if nor.size() == pos.size() else fn
						pts.append(pa * w.x + pb * w.y + pc * w.z + n * lf)
						nrs.append(n)
						var p0 := Vector2(b.param[bi[t * 3] * 2], b.param[bi[t * 3] * 2 + 1])
						var p1 := Vector2(b.param[bi[t * 3 + 1] * 2], b.param[bi[t * 3 + 1] * 2 + 1])
						var p2 := Vector2(b.param[bi[t * 3 + 2] * 2], b.param[bi[t * 3 + 2] * 2 + 1])
						prs.append(p0 * wb.x + p1 * wb.y + p2 * wb.z if wb != null else p0)
					for k in range(1, poly.size() - 1):
						var vv := [0, k, k + 1]
						if (pts[k] - pts[0]).cross(pts[k + 1] - pts[0]).dot(fn) < 0.0:
							vv = [0, k + 1, k]
						for m in vv:
							if ovl:
								ov3.append_array(PackedFloat32Array([pts[m].x, pts[m].y, pts[m].z]))
								on3.append_array(PackedFloat32Array([nrs[m].x, nrs[m].y, nrs[m].z]))
								op2.append_array(PackedFloat32Array([prs[m].x, prs[m].y]))
							else:
								bv3.append_array(PackedFloat32Array([pts[m].x, pts[m].y, pts[m].z]))
								bn3.append_array(PackedFloat32Array([nrs[m].x, nrs[m].y, nrs[m].z]))
								bp2.append_array(PackedFloat32Array([prs[m].x, prs[m].y]))
						if ovl:
							opaint.append(b.paint[bi[t * 3]])
						else:
							bpaint.append(b.paint[bi[t * 3]])
						tris += 1
					if tris > cap:
						return {"capped": true}
	var from := bpaint.size()
	bv3.append_array(ov3)
	bn3.append_array(on3)
	bp2.append_array(op2)
	bpaint.append_array(opaint)
	return {"capped": false, "vertices": bv3, "normals": bn3, "param": bp2, "paint": bpaint, "overlay_from": from}


static func _bary(p: Vector2, a: Vector2, b: Vector2, c: Vector2):
	var v0 := b - a
	var v1 := c - a
	var d := v0.x * v1.y - v1.x * v0.y
	if absf(d) < 1e-14:
		return null
	var v2 := p - a
	var l1 := (v2.x * v1.y - v1.x * v2.y) / d
	var l2 := (v0.x * v2.y - v2.x * v0.y) / d
	return Vector3(1.0 - l1 - l2, l1, l2)


## Sutherland-Hodgman: polygon clipped to a triangle's inside.
static func _clip(poly: Array, tri: Array, ccw: bool) -> Array:
	var out := poly
	for e in 3:
		var a: Vector2 = tri[e]
		var b: Vector2 = tri[(e + 1) % 3]
		var inp := out
		out = []
		for i in inp.size():
			var p: Vector2 = inp[i]
			var q: Vector2 = inp[(i + 1) % inp.size()]
			var sp := (b - a).cross(p - a) * (1.0 if ccw else -1.0)
			var sq := (b - a).cross(q - a) * (1.0 if ccw else -1.0)
			if sp >= 0.0:
				out.append(p)
			if (sp >= 0.0) != (sq >= 0.0):
				out.append(p + (q - p) * (sp / (sp - sq)))
		if out.is_empty():
			return out
	var clean := []
	for p in out:
		if clean.is_empty() or (p - clean[clean.size() - 1]).length_squared() > 1e-16:
			clean.append(p)
	if clean.size() > 1 and (clean[0] - clean[clean.size() - 1]).length_squared() <= 1e-16:
		clean.pop_back()
	return clean
