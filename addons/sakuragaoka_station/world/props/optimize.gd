# props/optimize.js: post-build draw-call optimiser for the props module (runs on props' own objects
# only).
#  1) Atlas pass: every sign / label / decal / lit-panel texture (non-tiling canvas, UVs in 0..1) is
#     copied into shared 1024² atlas pages (down-scaled to <= CAP texels per metre where it was
#     oversampled), meshes get remapped UVs, and all of them share a handful of page materials.
#  2) Colour pass: plain solid-colour toon materials are collapsed into a few vertex-coloured toon
#     materials (colour baked per vertex, linear) so the static batcher merges them per cell.
# The port draws no canvases, so each page's drawImage calls are kept as data on the page texture
# (user_data.atlas: source key and rectangle, in draw order).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")

const PAGE := 1024
const PAD := 4
const CAP := 900.0
const MAXDIM := 768.0


## The material's cache key split as optimize.js's parseKey: {kind, hex, opts[, intensity]}.
## A toon material keeps its opts; an emissive one's are read back from its key.
static func parse_key(m):
	if m == null or not (m.key is String):
		return null
	var key: String = m.key
	if key.begins_with("toon|"):
		var i := key.find("|", 5)
		return {"kind": "toon", "hex": key.substr(5, i - 5), "opts": (m.opts as Dictionary).duplicate() if m.opts is Dictionary else {}}
	if key.begins_with("emi|"):
		var i := key.find("|", 4)
		var j := key.find("|", i + 1)
		return {"kind": "emi", "hex": key.substr(4, i - 4), "intensity": float(key.substr(i + 1, j - i - 1)), "opts": _parse_opts(key.substr(j + 1))}
	return null


static func _parse_opts(s: String) -> Dictionary:
	var o := {}
	if s == "":
		return o
	for part in s.split(","):
		var kv := part.split("=", true, 1)
		if kv.size() < 2:
			continue
		var v: String = kv[1]
		if v.begins_with("tex:"):
			o[kv[0]] = v
		elif v == "true" or v == "false":
			o[kv[0]] = v == "true"
		elif v.is_valid_float():
			o[kv[0]] = float(v)
		else:
			o[kv[0]] = v
	return o


static func paint_bucket(p: float) -> float:
	return 0.02 if p <= 0.025 else (0.04 if p <= 0.045 else (0.06 if p <= 0.065 else 0.08))


static func optimize_props(ctx, roots: Array) -> Dictionary:
	var meshes := []
	for r in roots:
		r.update_matrix_world(true)
		r.traverse(func(o):
			if o.is_mesh and not o.is_instanced and not o.user_data.get("noBatch") and not o.user_data.get("dynamic") and not (o.material is Array):
				meshes.append(o))
	var a := atlas_pass(ctx, meshes)
	var c := color_pass(ctx, meshes)
	a.merge(c)
	return a


# ------------------------------------------------------------------ atlas
static func uv_in_range(geo: T.Geometry) -> bool:
	var uv: T.Attr = geo.get_attribute("uv")
	if not uv:
		return false
	for i in uv.count():
		var u := uv.get_x(i)
		var v := uv.get_y(i)
		if u < -0.002 or u > 1.002 or v < -0.002 or v > 1.002:
			return false
	return true


## texels-per-metre of a texture (W x H) on a mesh (area weighted).
static func density(o, W: float, H: float) -> float:
	var g: T.Geometry = o.geometry
	var p: T.Attr = g.position()
	var uv: T.Attr = g.get_attribute("uv")
	var n: int = g.index.size() if g.indexed else p.count()
	var wa := 0.0
	var ta := 0.0
	var t := 0
	while t < n:
		var i0: int = g.index[t] if g.indexed else t
		var i1: int = g.index[t + 1] if g.indexed else t + 1
		var i2: int = g.index[t + 2] if g.indexed else t + 2
		var A: Vector3 = o.matrix_world * p.v3(i0)
		var B: Vector3 = o.matrix_world * p.v3(i1)
		var C: Vector3 = o.matrix_world * p.v3(i2)
		wa += (B - A).cross(C - A).length() / 2.0
		var u0 := uv.get_x(i0) * W
		var v0 := uv.get_y(i0) * H
		var u1 := uv.get_x(i1) * W
		var v1 := uv.get_y(i1) * H
		var u2 := uv.get_x(i2) * W
		var v2 := uv.get_y(i2) * H
		ta += absf((u1 - u0) * (v2 - v0) - (u2 - u0) * (v1 - v0)) / 2.0
		t += 3
	return sqrt(ta / wa) if wa > 1e-8 else 0.0


static func atlas_pass(ctx, meshes: Array) -> Dictionary:
	var mat = ctx.mat
	var entries := {}  # texKey -> entry
	var users := []
	var blocked := {}  # textures also used by meshes we cannot remap
	for o in meshes:
		var m = o.material
		var tex = m.map if m else null
		if not tex:
			continue
		var pk = parse_key(m)
		var ok: bool = pk != null and not m.alpha_map and pk.hex == "ffffff" and tex.width > 1 \
				and tex.get("wrap_s") != "repeat" and tex.get("wrap_t") != "repeat" \
				and tex.repeat == Vector2.ONE and tex.offset == Vector2.ZERO \
				and o.geometry.has_attribute("uv") and uv_in_range(o.geometry)
		if not ok:
			blocked[tex] = true
			continue
		var opts: Dictionary = pk.opts.duplicate()
		opts.erase("map")
		var sig: String
		var bake := 1.0
		var transparent := bool(opts.get("transparent", false))
		if pk.kind == "toon":
			var p0: float = opts.paint if opts.get("paint") != null else 0.05
			opts["paint"] = 0.02 if p0 <= 0.03 else 0.045
			sig = "T|" + JSON.stringify(opts)
		else:
			var I: float = pk.intensity
			if I <= 1.0 and not transparent:
				bake = I
				sig = "E|1|" + JSON.stringify(opts)
			else:
				sig = "E|" + str(I) + "|" + JSON.stringify(opts)
		var key: String = tex.uuid + "|" + str(bake) + "|" + ("1" if transparent else "0")
		var e = entries.get(key)
		if e == null:
			e = {"key": key, "tex": tex, "W": tex.width, "H": tex.height, "bake": bake, "transparent": transparent, "sig": sig, "dens": 0.0, "n": 0}
			entries[key] = e
		e.dens = maxf(e.dens, density(o, e.W, e.H))
		e.n += 1
		users.append({"o": o, "e": e, "sig": sig, "kind": pk.kind, "opts": opts,
			"intensity": ((1.0 if bake != 1.0 else pk.intensity) if pk.kind == "emi" else 0.0)})
	if entries.is_empty():
		return {"atlasPages": 0, "atlased": 0}
	# sizes (down-scale oversampled textures)
	for e in entries.values():
		var s: float = CAP / e.dens if e.dens > CAP else 1.0
		s = minf(s, MAXDIM / maxf(e.W, e.H))
		e["w"] = maxi(8, mini(PAGE - 2 * PAD, int(T.js_round(e.W * s))))
		e["h"] = maxi(8, mini(PAGE - 2 * PAD, int(T.js_round(e.H * s))))
	# guillotine packing (sorted by signature, then size) so a page mostly serves one material
	var list: Array = T.stable_sort(entries.values(), func(a, b):
		if a.sig < b.sig:
			return -1
		if a.sig > b.sig:
			return 1
		var d: int = maxi(b.w, b.h) - maxi(a.w, a.h)
		return d if d != 0 else b.w * b.h - a.w * a.h)
	var pages := []
	var new_page := func():
		var c: Dictionary = ctx.tex.canvas(PAGE, PAGE)
		var p := {"canvas": c, "free": [[0, 0, PAGE, PAGE]], "tex": null, "draws": []}
		pages.append(p)
		return p
	var fit := func(p: Dictionary, w: int, h: int) -> int:
		var best := -1
		var bs := INF
		for i in p.free.size():
			var r: Array = p.free[i]
			if w <= r[2] and h <= r[3]:
				var s2: float = mini(r[2] - w, r[3] - h)
				if s2 < bs:
					bs = s2
					best = i
		return best
	for e in list:
		var w: int = e.w + 2 * PAD
		var h: int = e.h + 2 * PAD
		var page = null
		var ri := -1
		for p in pages:
			ri = fit.call(p, w, h)
			if ri >= 0:
				page = p
				break
		if page == null:
			page = new_page.call()
			ri = fit.call(page, w, h)
		var r: Array = page.free[ri]
		page.free.remove_at(ri)
		# split the leftover along the longer remaining side
		var rw: int = r[2] - w
		var rh: int = r[3] - h
		if rw > rh:
			if rw > 0:
				page.free.append([r[0] + w, r[1], rw, r[3]])
			if rh > 0:
				page.free.append([r[0], r[1] + h, w, rh])
		else:
			if rh > 0:
				page.free.append([r[0], r[1] + h, r[2], rh])
			if rw > 0:
				page.free.append([r[0] + w, r[1], rw, h])
		e["page"] = page
		e["x"] = r[0] + PAD
		e["y"] = r[1] + PAD
		# copy (edge-extended for opaque art so mip levels don't bleed); kept as the draw list
		page.draws.append({"key": e.tex.user_data.get("key", e.tex.uuid), "x": e.x, "y": e.y, "w": e.w, "h": e.h,
			"extend": not e.transparent, "bake": e.bake})
	for i in pages.size():
		var p: Dictionary = pages[i]
		p.tex = ctx.tex.finish(p.canvas, {"anisotropy": 8})
		p.tex.name = "props.atlas%d" % i
		p.tex.user_data["atlas"] = p.draws
	# materials per (page, signature) + remapped geometries
	var mats := {}
	var geos := {}
	for u in users:
		var e: Dictionary = u.e
		var p: Dictionary = e.page
		var mk: String = p.tex.uuid + "|" + u.sig
		var m = mats.get(mk)
		if m == null:
			var o: Dictionary = u.opts.duplicate()
			o["map"] = p.tex
			m = mat.toon("#ffffff", o) if u.kind == "toon" else mat.emissive("#ffffff", u.intensity, o)
			mats[mk] = m
		var gk := "%d|%s" % [u.o.geometry.get_instance_id(), e.key]
		var g = geos.get(gk)
		if g == null:
			g = u.o.geometry.clone()
			var uv: T.Attr = g.get_attribute("uv")
			for i in uv.count():
				var uu := clampf(uv.get_x(i), 0.0, 1.0)
				var vv := clampf(uv.get_y(i), 0.0, 1.0)
				uv.set_xy(i, (e.x + uu * e.w) / float(PAGE), 1.0 - (e.y + (1.0 - vv) * e.h) / float(PAGE))
			geos[gk] = g
		u.o.geometry = g
		u.o.material = m
	# free source canvases that are no longer referenced
	for e in entries.values():
		if blocked.has(e.tex):
			continue
		e.tex.width = 1
		e.tex.height = 1
	var area := 0
	var texels_in := 0
	for e in entries.values():
		area += (e.w + 2 * PAD) * (e.h + 2 * PAD)
		texels_in += e.W * e.H
	return {"atlasFill": snappedf(float(area) / (pages.size() * PAGE * PAGE), 0.01), "texelsIn": texels_in, "texelsOut": area,
		"atlasPages": pages.size(), "atlasMaterials": mats.size(), "atlased": users.size(), "atlasTextures": entries.size()}


# ------------------------------------------------------------------ vertex colours
static func color_pass(ctx, meshes: Array) -> Dictionary:
	var mat = ctx.mat
	var geos := {}
	var vms := {}
	var n := 0
	for o in meshes:
		var m = o.material
		if m == null or m.type != "toon":
			continue
		if m.map and m.map.get("name") and str(m.map.name).begins_with("props.atlas"):
			continue
		if m.alpha_map or m.vertex_colors or m.transparent or m.alpha_test > 0 or m.opacity != 1 or m.depth_write == false or m.get("polygonOffset"):
			continue
		if m.emissive.r or m.emissive.g or m.emissive.b:
			continue
		var pk = parse_key(m)
		if pk == null or pk.kind != "toon":
			continue
		var side: String = "double" if pk.opts.get("side") == "double" else ("back" if pk.opts.get("side") == "back" else "front")
		var paint := paint_bucket(pk.opts.paint if pk.opts.get("paint") != null else 0.05)
		var vk: String = side + "|" + str(paint) + "|" + (m.map.uuid if m.map else "")
		var vm = vms.get(vk)
		if vm == null:
			var opts := {"vertexColors": true, "paint": paint}
			if m.map:
				opts["map"] = m.map
			if side != "front":
				opts["side"] = side
			vm = mat.toon("#ffffff", opts)
			vms[vk] = vm
		var gk := "%d|%s" % [o.geometry.get_instance_id(), T.hex_string(m.color)]
		var g = geos.get(gk)
		if g == null:
			g = o.geometry.clone()
			var cnt: int = g.vertex_count()
			var arr := PackedFloat32Array()
			arr.resize(cnt * 3)
			for i in cnt:
				arr[i * 3] = m.color.r
				arr[i * 3 + 1] = m.color.g
				arr[i * 3 + 2] = m.color.b
			g.set_attribute("color", T.Attr.new(arr, 3))
			geos[gk] = g
		o.geometry = g
		o.material = vm
		n += 1
	return {"vcMeshes": n, "vcMaterials": vms.size()}
