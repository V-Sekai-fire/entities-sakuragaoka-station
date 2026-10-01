# How much shadow parity tapered capsules cost: every caster the port builds (cast_shadow, as the original
# flags it) fitted with inscribed tapered capsules from its distance transform's medial seeds, the fits
# spent at whole-world budgets, and each budget's analytic sun visibility compared per pixel with the
# original's own (tools/oracle/sun_mask.mjs, WARP), beside the port's rasterized map and a replica of
# the original's map, per view and per caster class. All pixel and fitting work is GLSL compute
# (tools/capsule_shadow_gpu.gd).
#   godot --path . --resolution 1920x1080 --script tools/capsule_shadow.gd -- --port=<sun_locate render dir>
#       --truth=<sun_mask dir> [--rerender=<dir>] [--shift=<dir>] [--d3d11=<dir>] [--vulkan=<dir>]
#       [--budgets=500,2000,8000,32000,128000] [--views=0,...,7] [--fit=<cache dir>] [--json=<file>]
#       [--sheets=<dir>] [--desktop=<dir>] [--sheet-budgets=8000,128000]
#   ... -- --time --out=<json>   the port's own map at the same views: GPU ms with the sun's shadow on and off
extends SceneTree

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const Layout = preload("res://addons/sakuragaoka_station/world/layout.gd")
const Gpu = preload("res://tools/capsule_shadow_gpu.gd")
const MODULES := ["environment", "station", "plaza", "sakura"]
const CLASSES := ["building", "roof", "post", "railing", "trunk", "canopy", "terrain", "other", "open"]
const S := 75.0
const MAP := 4096
const NORMAL_BIAS := 0.035
const DEPTH_BIAS := 0.00035 * 519.0
const PCF_SIGMA_TEXELS := 0.957
const VOX_OBJ := 16 << 20
const VOX_BATCH := 24 << 20
const CELL := 0.5
const ANCHORS := [["credit card", 0.00076], ["penny", 0.00152], ["pencil", 0.007], ["AAA battery", 0.0105], ["AA battery", 0.0145],
		["nickel", 0.0212], ["golf ball", 0.0427], ["adult wrist", 0.057], ["soda can", 0.066]]

var gpu
var opt := {}
var objs := []
var geo_f := PackedFloat32Array()
var gix := PackedInt32Array()
var _geos := {}
var skipped := {"no_position": 0, "item_size": 0, "degenerate": 0}
var L := Vector3.ZERO
var lx := Vector3.ZERO
var ly := Vector3.ZERO
var ntri := 0
var boxes := []
var log_lines := []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var k := a.substr(2)
			opt[k.get_slice("=", 0)] = k.get_slice("=", 1) if "=" in k else "1"
	if opt.has("time"):
		_time_map()
		return
	gpu = Gpu.new()
	if not gpu.ok:
		quit(1)
		return
	var lay = Layout.new("")
	L = Vector3(lay.SUN_DIR[0], lay.SUN_DIR[1], lay.SUN_DIR[2]).normalized()
	lx = L.cross(Vector3.UP).normalized()
	ly = lx.cross(L).normalized()
	var t0 := Time.get_ticks_msec()
	_extract()
	_log("casters: %d objects, %d triangles, %d floats of positions, skipped %s, in %d ms" % [objs.size(), ntri, geo_f.size(), str(skipped), Time.get_ticks_msec() - t0])
	_upload()
	_classify()
	var out := {}
	var fit_dir: String = opt.get("fit", "")
	if opt.has("dry"):
		pass
	elif fit_dir != "" and FileAccess.file_exists(fit_dir.path_join("capsules.bin")) and not opt.has("refit"):
		_load_fit(fit_dir)
	else:
		_fit()
		if fit_dir != "":
			_save_fit(fit_dir)
	out["casters"] = _caster_summary()
	out["fit"] = _fit_summary()
	if opt.has("dry"):
		print(JSON.stringify(out.casters, "  "))
		if opt.has("dump"):
			var rows := []
			for e in objs:
				rows.append([e.path, e.mat, CLASSES[e.cls], e.ext, e.ntri, e.roi, e.flags, [e.wlo.x, e.wlo.y, e.wlo.z], [e.whi.x, e.whi.y, e.whi.z], e.area, e.volume])
			var f := FileAccess.open(opt.dump, FileAccess.WRITE)
			f.store_string(JSON.stringify(rows))
			f.close()
	if opt.has("port"):
		out["views"] = _shade_views()
	out["log"] = log_lines
	if opt.has("json"):
		var f := FileAccess.open(opt.json, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  ", false))
		f.close()
		print("capsule_shadow: numbers in %s" % opt.json)
	gpu.release()
	if _sheets.is_empty():
		quit()
	else:
		_start_captions()


func _log(s: String) -> void:
	print("capsule_shadow: " + s)
	log_lines.append(s)


static func household(m: float) -> String:
	var a: float = absf(m)
	var best = ANCHORS[0]
	for x in ANCHORS:
		if absf(log(a / x[1])) < absf(log(a / best[1])):
			best = x
	return "%.1f mm, about %.1f x a %s" % [a * 1000.0, a / best[1], best[0]] if a > 0.0 else "0 mm"


# ------------------------------------------------------------------------------ casters

func _extract() -> void:
	var ctx = Ctx.new(1)
	for n in MODULES:
		load("res://addons/sakuragaoka_station/world/%s.gd" % n).new().build(ctx)
	ctx.scene.update_matrix_world(true)
	_walk(ctx.static_root, "")
	_walk(ctx.dynamic_root, "")


func _walk(o, path: String) -> void:
	if not o.visible:
		return
	var p: String = path + "/" + (o.name if o.name != "" else "?")
	if o.is_mesh and o.cast_shadow:
		_add(o, p)
	for c in o.children:
		_walk(c, p)


func _add(o, path: String) -> void:
	var g = o.geometry
	var pos = g.get_attribute("position")
	if pos == null or pos.count() == 0:
		skipped.no_position += 1
		return
	if pos.item_size != 3:
		skipped.item_size += 1
		return
	var m = o.materials()[0]
	var gid: int = g.get_instance_id()
	if not _geos.has(gid):
		var e := {"voff": geo_f.size() / 3, "ioff": -1, "ntri": pos.count() / 3}
		geo_f.append_array(pos.array)
		if g.index.size() > 0:
			var idx: PackedInt32Array = g.index
			if g.draw_count >= 0:
				idx = idx.slice(g.draw_start, g.draw_start + g.draw_count)
			e.ioff = gix.size()
			e.ntri = idx.size() / 3
			gix.append_array(idx)
		_geos[gid] = e
	var ge: Dictionary = _geos[gid]
	var mname: String = m.name if m != null else ""
	var card: bool = m != null and m.alpha_test > 0.0 and m.map != null
	var flags := (1 if m != null and m.side == "double" else 0) | (2 if o.user_data.has("customDepthMaterial") else 0) | (32 if card else 0)
	var xs: Array = o.instance_matrix.slice(0, o.count) if o.is_instanced else [Transform3D()]
	for t in xs:
		var w: Transform3D = o.matrix_world * t
		if absf(w.basis.determinant()) < 1e-12:
			skipped.degenerate += 1
			continue
		objs.append({"path": path, "mat": mname, "geo": ge, "w": w, "flags": flags | (4 if w.basis.determinant() < 0.0 else 0),
				"toff": ntri, "ntri": ge.ntri})
		ntri += ge.ntri


static func _frame(b: Basis) -> Basis:
	var u0 := b.x.normalized()
	var u1 := (b.y - b.y.dot(u0) * u0).normalized()
	if u1.length() < 0.5:
		u1 = u0.cross(Vector3.UP if absf(u0.y) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(u0, u1, u0.cross(u1))


func _upload() -> void:
	var n := objs.size()
	var oi := PackedInt32Array()
	oi.resize(n * Gpu.OI)
	var of := PackedFloat32Array()
	of.resize(n * Gpu.OF)
	for o in n:
		var e: Dictionary = objs[o]
		var b := o * Gpu.OI
		oi[b] = e.geo.voff
		oi[b + 1] = e.geo.ioff
		oi[b + 2] = e.ntri
		oi[b + 3] = e.toff
		oi[b + 4] = e.flags
		oi[b + 23] = o
		var w: Transform3D = e.w
		var r := _frame(w.basis)
		e["r"] = r
		var vals := [w.basis.x, w.basis.y, w.basis.z, w.origin, r.x, r.y, r.z]
		for k in vals.size():
			of[o * Gpu.OF + 3 * k] = vals[k].x
			of[o * Gpu.OF + 3 * k + 1] = vals[k].y
			of[o * Gpu.OF + 3 * k + 2] = vals[k].z
	gpu.alloc("geo", geo_f.size() * 4)
	gpu.put("geo", 0, geo_f.to_byte_array())
	gpu.alloc("gix", maxi(1, gix.size()) * 4)
	gpu.put("gix", 0, gix.to_byte_array())
	gpu.alloc("obi", oi.size() * 4)
	gpu.put("obi", 0, oi.to_byte_array())
	gpu.alloc("obf", of.size() * 4)
	gpu.put("obf", 0, of.to_byte_array())
	gpu.alloc("tri", ntri * 48)
	var ab := PackedInt32Array()
	ab.resize(n * 12)
	for o in n:
		for k in 12:
			ab[o * 12 + k] = 0x7FFFFFFF if (k % 6) < 3 else -0x7FFFFFFF - 1
	gpu.alloc("aab", ab.size() * 4)
	gpu.put("aab", 0, ab.to_byte_array())
	gpu.alloc("scr", maxi(n * 12, 1 << 20) * 4)
	gpu.run("tri", (ntri + 255) / 256, [n, ntri])
	gpu.run("area", n, [0, n])
	var bb: PackedFloat32Array = gpu.floats("scr", 0, n * 12)
	var ar: PackedFloat32Array = gpu.floats("obf", 0, n * Gpu.OF)
	for o in n:
		var e: Dictionary = objs[o]
		e["wlo"] = Vector3(bb[o * 12], bb[o * 12 + 1], bb[o * 12 + 2])
		e["whi"] = Vector3(bb[o * 12 + 3], bb[o * 12 + 4], bb[o * 12 + 5])
		e["llo"] = Vector3(bb[o * 12 + 6], bb[o * 12 + 7], bb[o * 12 + 8])
		e["lhi"] = Vector3(bb[o * 12 + 9], bb[o * 12 + 10], bb[o * 12 + 11])
		e["area"] = ar[o * Gpu.OF + 26]
		e["volume"] = absf(ar[o * Gpu.OF + 27])


## Class by material, name, then shape in the object's own frame (low wide objects are ground relief); in
## the ROI when its light-plane footprint meets any view's shadow box.
func _classify() -> void:
	var centres := _box_centres()
	for e in objs:
		var ext: Vector3 = e.lhi - e.llo
		var r: Basis = e.r
		var ax := [[ext.x, r.x], [ext.y, r.y], [ext.z, r.z]]
		ax.sort_custom(func(p, q): return p[0] > q[0])
		var a: float = ax[0][0]
		var b: float = ax[1][0]
		var c: float = ax[2][0]
		var up_long: float = absf(ax[0][1].y)
		var up_thin: float = absf(ax[2][1].y)
		var cls := "other"
		var p: String = e.path
		if e.mat == "sakura:blob" or e.mat == "foliage-clumps":
			cls = "canopy"
		elif e.mat.begins_with("sakura:bark"):
			cls = "trunk"
		elif "env-terrain" in p or "env-levee" in p or "env-riprap" in p or e.mat in ["env-levee", "env-riprap"]:
			cls = "terrain"
		elif a >= 4.0 * b and b <= 0.6 and up_long >= 0.85:
			cls = "post"
		elif a >= 4.0 * b and b <= 0.35 and up_long < 0.5:
			cls = "railing"
		elif c <= 0.35 and b >= 1.0 and up_thin >= 0.5 and e.wlo.y >= 2.0:
			cls = "roof"
		elif b >= 1.0 and e.whi.y - e.wlo.y <= 1.6 and e.whi.y <= 2.0:
			cls = "terrain"
		elif b >= 1.5 and e.whi.y - e.wlo.y >= 1.5:
			cls = "building"
		e["cls"] = CLASSES.find(cls)
		e["ext"] = [a, b, c]
		e["radius"] = 0.5 * (e.whi - e.wlo).length()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for k in 8:
			var q := Vector3(e.whi.x if k & 1 else e.wlo.x, e.whi.y if k & 2 else e.wlo.y, e.whi.z if k & 4 else e.wlo.z)
			var uv := Vector2(q.dot(lx), q.dot(ly))
			lo = lo.min(uv)
			hi = hi.max(uv)
		var roi := false
		for cc in centres:
			if hi.x >= cc.x - S and lo.x <= cc.x + S and hi.y >= cc.y - S and lo.y <= cc.y + S:
				roi = true
		e["roi"] = roi
		if roi:
			e.flags |= 64
	var oi := PackedInt32Array()
	oi.resize(objs.size() * 2)
	for o in objs.size():
		gpu.put("obi", o * Gpu.OI + 4, PackedInt32Array([objs[o].flags, objs[o].cls]).to_byte_array())
		gpu.put("obf", o * Gpu.OF + 28, PackedFloat32Array([objs[o].radius]).to_byte_array())


## Each view's snapped shadow-box centre in the light plane, from the truth's meta (the original's own).
func _box_centres() -> Array:
	var out := []
	var m = _meta(opt.get("truth", ""))
	if m == null:
		return [Vector2(Vector3(-1, 1.52, -11.4).dot(lx), Vector3(-1, 1.52, -11.4).dot(ly))]
	for v in m.views:
		var c := Vector3(v.sunTarget[0], v.sunTarget[1], v.sunTarget[2])
		out.append(Vector2(c.dot(lx), c.dot(ly)))
	return out


static func _meta(dir: String):
	if dir == "" or not FileAccess.file_exists(dir.path_join("meta.json")):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("meta.json")))


func _caster_summary() -> Dictionary:
	var by := {}
	for c in CLASSES:
		by[c] = {"objects": 0, "triangles": 0, "in_roi": 0, "roi_triangles": 0}
	var cards := {"objects": 0, "triangles": 0, "in_roi": 0}
	var boxes12 := 0
	for e in objs:
		var d: Dictionary = by[CLASSES[e.cls]]
		if e.flags & 32:
			cards.objects += 1
			cards.triangles += e.ntri
			cards.in_roi += 1 if e.roi else 0
			continue
		d.objects += 1
		d.triangles += e.ntri
		if e.roi:
			d.in_roi += 1
			d.roi_triangles += e.ntri
			boxes12 += 1 if e.ntri == 12 else 0
	return {"by_class": by, "alpha_cut_cards_not_capsules": cards, "twelve_triangle_boxes_in_roi": boxes12, "skipped": skipped}


# ------------------------------------------------------------------------------ fitting

func _fit() -> void:
	var t0 := Time.get_ticks_msec()
	var order := []
	var limit := int(opt.get("limit", "0"))
	var only := {}
	for x in str(opt.get("only", "")).split(",", false):
		only[int(x)] = true
	for o in objs.size():
		var e: Dictionary = objs[o]
		if not e.roi or (e.flags & 32) or (limit > 0 and order.size() >= limit) or (not only.is_empty() and not only.has(o)):
			e["nvox"] = 0
			continue
		var ext: Vector3 = e.lhi - e.llo
		var mn: float = minf(ext.x, minf(ext.y, ext.z))
		var h := maxf(0.002, mn / 8.0)
		if CLASSES[e.cls] == "trunk":
			h = 0.025
		elif e.mat == "sakura:blob":
			h = 0.08
		var dims := Vector3i.ZERO
		while true:
			dims = Vector3i(int(ceil(ext.x / h)) + 4, int(ceil(ext.y / h)) + 4, int(ceil(ext.z / h)) + 4)
			if dims.x * dims.y * dims.z <= VOX_OBJ:
				break
			h *= 1.1
		e["h"] = h
		e["dims"] = dims
		e["nvox"] = dims.x * dims.y * dims.z
		e["kcap"] = clampi(e.nvox / 2000, 32, 4096)
		order.append(o)
	var capoff := 0
	for o in order:
		objs[o]["capoff"] = capoff
		capoff += objs[o].kcap
	gpu.alloc("cap", capoff * 32)
	gpu.alloc("hst", capoff * 4)
	gpu.alloc("capw", capoff * 48)
	gpu.zero("hst")
	var batches := []
	var cur := []
	var nv := 0
	for o in order:
		if cur.size() > 0 and nv + objs[o].nvox > VOX_BATCH:
			batches.append(cur)
			cur = []
			nv = 0
		cur.append(o)
		nv += objs[o].nvox
	if cur.size() > 0:
		batches.append(cur)
	_log("fitting %d objects in %d batches, %d capsule slots" % [order.size(), batches.size(), capoff])
	var iters := 0
	for bi in batches.size():
		iters += _fit_batch(batches[bi])
		if bi % 10 == 0:
			_log("batch %d / %d done (%d s)" % [bi + 1, batches.size(), (Time.get_ticks_msec() - t0) / 1000])
	gpu.run("capw", (objs.size() + 63) / 64, [0, objs.size()])
	var k: PackedInt32Array = gpu.ints("obi", 0, objs.size() * Gpu.OI)
	var total := 0
	for o in objs.size():
		objs[o]["k"] = k[o * Gpu.OI + 16]
		objs[o]["oflags"] = k[o * Gpu.OI + 4]
		objs[o]["odd"] = k[o * Gpu.OI + 24]
		total += objs[o].k
	_log("fit: %d capsules in %d greedy rounds, %d s" % [total, iters, (Time.get_ticks_msec() - t0) / 1000])
	for o in only:
		var e: Dictionary = objs[o]
		var cw: PackedFloat32Array = gpu.floats("capw", e.capoff * 12, mini(e.k, 12) * 12)
		var hh: PackedFloat32Array = gpu.floats("hst", e.capoff, mini(e.k, 12))
		_log("object %d %s %s ext %s h %.4f dims %s k %d" % [o, e.path, CLASSES[e.cls], str(e.ext), e.h, str(e.dims), e.k])
		for j in mini(e.k, 12):
			_log("  cap %d (%.3f %.3f %.3f) r %.4f -> (%.3f %.3f %.3f) r %.4f  H %.4f" % [j, cw[12 * j], cw[12 * j + 1], cw[12 * j + 2], cw[12 * j + 3],
				cw[12 * j + 4], cw[12 * j + 5], cw[12 * j + 6], cw[12 * j + 7], hh[j]])


## Objects of one batch are contiguous ids? No: they are given by list; their voxel and line offsets are
## batch-relative and the kernels search them by id range, so a batch is a contiguous id range here.
func _fit_batch(ids: Array) -> int:
	var o0: int = ids[0]
	var o1: int = ids[ids.size() - 1] + 1
	var vox := 0
	var lines := [0, 0, 0]
	var scr := [0, 0, 0]
	var oi := PackedInt32Array()
	oi.resize((o1 - o0) * Gpu.OI)
	var of := PackedFloat32Array()
	of.resize((o1 - o0) * 4)
	var cur: PackedInt32Array = gpu.ints("obi", o0 * Gpu.OI, (o1 - o0) * Gpu.OI)
	for o in range(o0, o1):
		var e: Dictionary = objs[o]
		var b := (o - o0) * Gpu.OI
		for k in Gpu.OI:
			oi[b + k] = cur[b + k]
		var d: Vector3i = e.get("dims", Vector3i(1, 1, 1))
		if e.nvox == 0:
			d = Vector3i.ZERO
		oi[b + 6] = d.x
		oi[b + 7] = d.y
		oi[b + 8] = d.z
		oi[b + 9] = vox
		oi[b + 10] = lines[0]
		oi[b + 11] = lines[1]
		oi[b + 12] = lines[2]
		oi[b + 13] = scr[0]
		oi[b + 14] = scr[1]
		oi[b + 15] = scr[2]
		oi[b + 16] = 0
		oi[b + 17] = 1 if e.nvox == 0 else 0
		oi[b + 24] = 0
		oi[b + 25] = e.get("kcap", 0)
		oi[b + 26] = e.get("capoff", 0)
		vox += d.x * d.y * d.z
		var ln := [d.y * d.z, d.x * d.z, d.x * d.y]
		var n := [d.x, d.y, d.z]
		for a in 3:
			lines[a] += ln[a]
			scr[a] += ln[a] * (3 * n[a] + 2)
		if e.nvox > 0:
			var g0: Vector3 = e.llo - Vector3.ONE * 2.0 * e.h
			gpu.put("obf", o * Gpu.OF + 21, PackedFloat32Array([g0.x, g0.y, g0.z, e.h]).to_byte_array())
	gpu.put("obi", o0 * Gpu.OI, oi.to_byte_array())
	if vox == 0:
		return 0
	gpu.alloc("vox", vox * 4)
	gpu.alloc("vfl", vox * 4)
	gpu.alloc("scr", maxi(maxi(scr[0], scr[1]), maxi(scr[2], 1 << 20)) * 4)
	var t0: int = objs[o0].toff
	var t1: int = objs[o1 - 1].toff + objs[o1 - 1].ntri
	if opt.has("dbg-cand"):
		var d0: Vector3i = objs[o0].dims
		var col := func(tag: String) -> void:
			var parts := PackedStringArray()
			for y in d0.y:
				parts.append("%x" % gpu.ints("vfl", (30 * d0.y + y) * d0.x + 4600, 1)[0])
			_log("%s vfl along y at x 4600 z 30: %s" % [tag, " ".join(parts)])
		gpu.runs([["vclear", (vox + 255) / 256, [o0, o1, vox]]])
		for a in 3:
			gpu.runs([["vrow", (lines[a] + 63) / 64, [o0, o1, lines[a], a]]])
			col.call("after axis %d" % a)
		gpu.runs([["vdecide", (vox + 255) / 256, [o0, o1, vox]]])
		col.call("decided")
		gpu.runs([["vshell", (t1 - t0 + 63) / 64, [o0, o1, t0, t1]]])
		col.call("shell")
		_log("llo %s lhi %s h %f g0 %s" % [str(objs[o0].llo), str(objs[o0].lhi), objs[o0].h, str(gpu.floats("obf", o0 * Gpu.OF + 21, 4))])
	gpu.runs([["vclear", (vox + 255) / 256, [o0, o1, vox]],
			["vrow", (lines[0] + 63) / 64, [o0, o1, lines[0], 0]],
			["vrow", (lines[1] + 63) / 64, [o0, o1, lines[1], 1]],
			["vrow", (lines[2] + 63) / 64, [o0, o1, lines[2], 2]],
			["vdecide", (vox + 255) / 256, [o0, o1, vox]],
			["vshell", (t1 - t0 + 63) / 64, [o0, o1, t0, t1]]])
	if opt.has("dbg-cand"):
		var d1: Vector3i = objs[o0].dims
		for a in 3:
			gpu.runs([["edt", (lines[a] + 63) / 64, [o0, o1, lines[a], a]]])
			for x in [1000, 4600]:
				var parts := PackedStringArray()
				for y in d1.y:
					parts.append("%.1f" % gpu.floats("vox", (30 * d1.y + y) * d1.x + x, 1)[0])
				_log("edt pass %d, D^2 along y at x %d z 30: %s" % [a, x, " ".join(parts)])
	else:
		gpu.runs([["edt", (lines[0] + 63) / 64, [o0, o1, lines[0], 0]],
				["edt", (lines[1] + 63) / 64, [o0, o1, lines[1], 1]],
				["edt", (lines[2] + 63) / 64, [o0, o1, lines[2], 2]]])
	gpu.zero("cnt", 0, 16)
	gpu.run("medial", (vox + 255) / 256, [o0, o1, vox])
	var c: PackedInt32Array = gpu.ints("cnt", 0, 2)
	if c[0] > Gpu.MEDCAP or c[1] > Gpu.MEDCAP:
		_log("batch %d..%d: %d medial, %d boundary voxels over the cap" % [o0, o1, c[0], c[1]])
	if opt.has("dbg-cand"):
		var d: Vector3i = objs[o0].dims
		for yz in [[4, 4], [4, 30], [5, 30], [3, 30]]:
			var row := PackedStringArray()
			var base: int = (yz[1] * d.y + yz[0]) * d.x
			var vv: PackedFloat32Array = gpu.floats("vox", base, d.x)
			var ff: PackedInt32Array = gpu.ints("vfl", base, d.x)
			for x in [0, 1, 2, 3, 4, 5, 100, 1000, 4600, 9100, 9120, 9130, 9135, 9136, 9137, 9140, 9150, 9200, 9207, 9208, 9209, 9210, 9211]:
				row.append("%d:%.2f/%d" % [x, sqrt(vv[x]), ff[x]])
			_log("y %d z %d: %s" % [yz[0], yz[1], " ".join(row)])
		for x in [4600]:
			var col := PackedStringArray()
			for y in d.y:
				col.append("%.2f" % sqrt(gpu.floats("vox", (30 * d.y + y) * d.x + x, 1)[0]))
			_log("x %d z 30 along y: %s" % [x, " ".join(col)])
	var nm := mini(c[0], Gpu.MEDCAP)
	var nb := mini(c[1], Gpu.MEDCAP)
	var nob := o1 - o0
	gpu.alloc("cnd", nob * Gpu.NDIR * 48)
	var it := 0
	var kmax := 0
	for o in range(o0, o1):
		kmax = maxi(kmax, objs[o].get("kcap", 0))
	while it < kmax + 8:
		for r in 4:
			gpu.runs([["greset", (nob + 63) / 64, [o0, o1]],
					["seed", (nm + 255) / 256, [o0, o1, nm, 0]],
					["seed", (nm + 255) / 256, [o0, o1, nm, 1]],
					["cand", (nob * Gpu.NDIR + 63) / 64, [o0, o1]],
					["gain", nob * Gpu.NDIR, [o0, o1]],
					["pick", (nob + 63) / 64, [o0, o1], [], [1.0]],
					["cover", nob, [o0, o1]],
					["mcover", (nm + 255) / 256, [o0, o1, nm, 0]],
					["mcover", (nb + 255) / 256, [o0, o1, nb, 1]],
					["hrec", (nob + 63) / 64, [o0, o1], [], [0.0, 0.002]]])
			it += 1
			if opt.has("dbg-cand") and it == 1:
				var cd: PackedFloat32Array = gpu.floats("cnd", 0, mini(nob, 3) * Gpu.NDIR * 12)
				var md: PackedFloat32Array = gpu.floats("med", 0, 8)
				_log("medial %d boundary %d; first medial %s" % [nm, nb, str(md)])
				for g in cd.size() / 12:
					_log("  cand %d P (%.2f %.2f %.2f) r %.3f Q (%.2f %.2f %.2f) r %.3f gain %.1f %.1f" % [g, cd[12 * g], cd[12 * g + 1], cd[12 * g + 2], cd[12 * g + 3],
						cd[12 * g + 4], cd[12 * g + 5], cd[12 * g + 6], cd[12 * g + 7], cd[12 * g + 8], cd[12 * g + 9]])
		var st: PackedInt32Array = gpu.ints("obi", o0 * Gpu.OI, nob * Gpu.OI)
		var live := 0
		for k in nob:
			live += 1 if st[k * Gpu.OI + 17] == 0 else 0
		if live == 0:
			break
	return it


func _save_fit(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("capsules.bin"), FileAccess.WRITE)
	var n: int = gpu.sizes.capw / 48
	f.store_32(n)
	f.store_buffer(gpu.rd.buffer_get_data(gpu.bufs.capw, 0, n * 48))
	f.store_buffer(gpu.rd.buffer_get_data(gpu.bufs.hst, 0, n * 4))
	f.close()
	var rows := []
	for e in objs:
		rows.append([e.get("k", 0), e.get("capoff", 0), e.get("kcap", 0), e.get("h", 0.0), e.get("nvox", 0), e.get("oflags", e.flags), e.get("odd", 0)])
	var g := FileAccess.open(dir.path_join("objects.json"), FileAccess.WRITE)
	g.store_string(JSON.stringify(rows))
	g.close()


func _load_fit(dir: String) -> void:
	var f := FileAccess.open(dir.path_join("capsules.bin"), FileAccess.READ)
	var n := f.get_32()
	gpu.alloc("capw", n * 48)
	gpu.put("capw", 0, f.get_buffer(n * 48))
	gpu.alloc("hst", n * 4)
	gpu.put("hst", 0, f.get_buffer(n * 4))
	f.close()
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("objects.json")))
	for o in objs.size():
		var r: Array = rows[o]
		objs[o]["k"] = int(r[0])
		objs[o]["capoff"] = int(r[1])
		objs[o]["kcap"] = int(r[2])
		objs[o]["h"] = r[3]
		objs[o]["nvox"] = int(r[4])
		objs[o]["oflags"] = int(r[5])
		objs[o]["odd"] = int(r[6])
		gpu.put("obi", o * Gpu.OI + 16, PackedInt32Array([objs[o].k]).to_byte_array())
		gpu.put("obi", o * Gpu.OI + 26, PackedInt32Array([objs[o].capoff]).to_byte_array())
	_log("fit loaded from %s: %d capsule slots" % [dir, n])


func _fit_summary() -> Dictionary:
	var by := {}
	for c in CLASSES:
		by[c] = {"objects": 0, "capsules_full": 0, "saturated": 0, "odd_line_objects": 0, "overflow_objects": 0}
	for e in objs:
		if not e.roi or (e.flags & 32):
			continue
		var d: Dictionary = by[CLASSES[e.cls]]
		d.objects += 1
		d.capsules_full += e.get("k", 0)
		d.saturated += 1 if e.get("k", 0) >= e.get("kcap", 1) else 0
		d.odd_line_objects += 1 if e.get("odd", 0) > 0 else 0
		d.overflow_objects += 1 if (e.get("oflags", 0) & 16) else 0
	return {"by_class": by}


# ------------------------------------------------------------------------------ budgets

## The tolerance whose capsule count is nearest the budget: per object, the first capsules until its
## surface-to-capsule distance is within it (none for an object within it altogether).
func _alloc_table(deltas: PackedFloat32Array, pick := -1) -> PackedInt32Array:
	gpu.put("scr", 0, deltas.to_byte_array())
	gpu.zero("cnt", 16, deltas.size())
	gpu.alloc("sel", maxi(objs.size(), 1) * 4 + (gpu.sizes.capw / 48) * 4 + 1024)
	if pick >= 0:
		gpu.zero("sel", 0, objs.size())
	gpu.run("alloc", (objs.size() + 63) / 64, [objs.size(), 0, 0, deltas.size()], [pick])
	return gpu.ints("cnt", 16, deltas.size())


func _delta_for(budget: int) -> float:
	var lo := 0.0005
	var hi := 8.0
	for round_ in 3:
		var ds := PackedFloat32Array()
		for i in 64:
			ds.append(hi * pow(lo / hi, float(i) / 63.0))
		var n := _alloc_table(ds)
		var j := 0
		while j < 63 and n[j + 1] <= budget:
			j += 1
		hi = ds[j]
		lo = ds[mini(j + 1, 63)]
		if j == 63:
			return ds[63]
	return hi


# ------------------------------------------------------------------------------ views

const PL := {"truth": 0, "rerender": 1, "shift": 2, "d3d11": 3, "vulkan": 4, "map": 5, "replica": 6, "occ": 7, "cls": 8,
		"cone": 9, "filter": 10, "sd": 11, "arg": 12, "valid": 13, "sheet1": 14, "sheet2": 15}
const FLOORS := ["rerender", "shift", "d3d11", "vulkan"]
const EDGE_R := 24
const BAND := 0.3
const FOOT := 4096
const SURV := 1 << 20

var _sheets := []
var _sheet_vp: SubViewport
var _sheet_label: Label
var _sheet_wait := -1
var _foot_n := 0


func _shade_views() -> Dictionary:
	var views := Array(str(opt.get("views", "0,1,2,3,4,5,6,7")).split(",")).map(func(x): return int(x))
	var budgets := Array(str(opt.get("budgets", "500,2000,8000,32000,128000")).split(",")).map(func(x): return int(x))
	var sheet_b := Array(str(opt.get("sheet-budgets", "8000,128000")).split(",")).map(func(x): return int(x))
	var tm = _meta(opt.truth)
	var res := {"truth": {"dir": opt.truth, "angle": tm.get("angle"), "renderer": tm.get("renderer")}, "budgets": [], "per_view": [], "settings": {}}
	for name in FLOORS:
		var m = _meta(opt.get(name, ""))
		res.truth[name] = {"dir": opt.get(name, ""), "angle": m.get("angle") if m != null else null,
			"renderer": m.get("renderer") if m != null else null, "shift_texels": m.get("shift_texels") if m != null else null}
	var deltas := {}
	for b in budgets + sheet_b:
		if not deltas.has(b):
			deltas[b] = _delta_for(b)
	for b in budgets:
		var n := _alloc_table(PackedFloat32Array([deltas[b]]))
		res.budgets.append({"target": b, "tolerance_m": deltas[b], "tolerance": household(deltas[b]), "capsules": n[0]})
	_log("budgets: %s" % str(res.budgets))
	_footprints()
	var tex := 2.0 * S / MAP
	var sig := PCF_SIGMA_TEXELS * tex
	var occ := PackedInt32Array()
	occ.resize(64)
	for v in views:
		_replica(v, tm.views[v])
		gpu.alloc("acc", 4096 * 4)
		gpu.zero("acc", 0, 64)
		gpu.run("thist", Gpu.NPIX / 256)
		var h: PackedInt32Array = gpu.ints("acc", 0, 64)
		for k in 64:
			occ[k] += h[k]
	var tot := 0
	for k in 64:
		tot += occ[k]
	var cum := 0
	var t_med := 1.0
	for k in 64:
		cum += occ[k]
		if cum * 2 >= tot:
			t_med = 0.01 * pow(10.0, (k + 0.5) / 16.0)
			break
	var tan_cone := sig / t_med
	res.settings = {"pcf_sigma_m": sig, "pcf_sigma": household(sig), "occluder_distance_median_m": t_med, "occluder_distance_samples": tot,
		"cone_tan": tan_cone, "cone_half_angle_deg": rad_to_deg(atan(tan_cone)), "normal_bias_m": NORMAL_BIAS, "depth_bias_m": DEPTH_BIAS,
		"texel_m": tex, "texel": household(tex), "cell_m": CELL, "edge_search_px": EDGE_R, "contact_band_m": BAND, "footprints": _foot_n}
	for v in views:
		res.per_view.append(_shade_view(v, tm.views[v], budgets, sheet_b, deltas, tan_cone, sig))
		_log("view %d done" % v)
	res["summary"] = _summarize(res, budgets)
	return res


## Building footprints for the contact metric: upright twelve-triangle building-class boxes in the ROI.
func _footprints() -> void:
	var f := PackedFloat32Array()
	for e in objs:
		if not e.roi or CLASSES[e.cls] != "building" or e.ntri != 12:
			continue
		var r: Basis = e.r
		var axes := [r.x, r.y, r.z]
		var up := -1
		for a in 3:
			if absf(axes[a].y) > 0.95:
				up = a
		if up < 0:
			continue
		var hz := [0, 1, 2]
		hz.erase(up)
		var ext: Vector3 = e.lhi - e.llo
		var exts := [ext.x, ext.y, ext.z]
		var lc: Vector3 = 0.5 * (e.llo + e.lhi)
		var wc: Vector3 = e.w.origin + r.x * lc.x + r.y * lc.y + r.z * lc.z
		var cs := Vector2(axes[hz[0]].x, axes[hz[0]].z).normalized()
		f.append_array(PackedFloat32Array([wc.x, wc.z, 0.5 * exts[hz[0]], 0.5 * exts[hz[1]], cs.x, cs.y, e.wlo.y, e.whi.y]))
	_foot_n = f.size() / 8
	gpu.put("scr", FOOT, f.to_byte_array())


## The view's port buffers, and the original's map replicated over them (planes 6, 7).
func _replica(v: int, tv: Dictionary) -> Dictionary:
	gpu.load_port(opt.port, v, 0.01)
	var c := Vector3(tv.sunTarget[0], tv.sunTarget[1], tv.sunTarget[2])
	var u0 := c.dot(lx) - S
	var v0 := c.dot(ly) - S
	var tex := 2.0 * S / MAP
	var doff := 260.0 + c.dot(L)
	var fr := [u0, v0, tex, doff, L.x, L.y, L.z, 0.0, lx.x, lx.y, lx.z, 0.0, ly.x, ly.y, ly.z, 0.0]
	var t0 := Time.get_ticks_usec()
	gpu.runs([["mclear", MAP * MAP / 256], ["mrast", (ntri + 63) / 64, [0, ntri, 0], [], fr], ["mrast", (ntri + 63) / 64, [0, ntri, 1], [], fr]])
	var raster_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var fs := [u0, v0, tex, DEPTH_BIAS, L.x, L.y, L.z, 0.0, lx.x, lx.y, lx.z, NORMAL_BIAS, ly.x, ly.y, ly.z, doff]
	gpu.runs([["mshade", Gpu.NPIX / 256, [0, 0, 0, 1], [8], fs]])
	return {"u0": u0, "v0": v0, "raster_ms_cpu_clock": raster_ms, "fs": fs}


func _shade_view(v: int, tv: Dictionary, budgets: Array, sheet_b: Array, deltas: Dictionary, tan_cone: float, sig: float) -> Dictionary:
	var out := {"view": v, "budgets": []}
	var rep := _replica(v, tv)
	var have := {}
	for name in ["truth"] + FLOORS:
		var dir: String = opt.get(name, "")
		have[name] = dir != "" and gpu.load_truth(dir.path_join("mask_%d.f32" % v), PL[name])
	if not have.truth:
		out["error"] = "no truth mask for view %d" % v
		return out
	gpu.run("class", Gpu.NPIX / 256)
	out["map_ms"] = {"replica_raster_cpu_clock": rep.raster_ms_cpu_clock,
		"replica_pcf_lookup": gpu.time_runs([["mshade", Gpu.NPIX / 256, [0, 0, 0, 0], [8], rep.fs]], 5)}
	var pm = _meta(opt.port)
	if pm != null and v < pm.views.size():
		out["port_map_render"] = {"shadow": pm.views[v].get("render_shadow"), "visible": pm.views[v].get("render_visible"),
			"setup": pm.views[v].get("shadow_setup")}
	var nb := budgets.size()
	var base_tests := ["replica", "map"] + FLOORS
	var tp := []
	for n in base_tests:
		tp.append(PL[n] if (n == "replica" or n == "map" or have.get(n, false)) else -1)
	var mad_n := (1 + nb) * Gpu.NTEST * Gpu.NCLS * 2
	var eb := 4 * Gpu.NCLS * (Gpu.HBINS + 2)
	var edge_off := mad_n
	var con_off := edge_off + (1 + nb) * 2 * eb
	var acc_n := con_off + (1 + nb) * 48
	gpu.alloc("acc", acc_n * 4)
	gpu.zero("acc")
	gpu.runs([["acc", Gpu.NPIX / 256, tp.slice(0, 4), tp.slice(4, 6) + [-1, -1], [0.0, 0.0]],
			["edge", Gpu.NPIX / 256, tp.slice(0, 4), [edge_off, EDGE_R], [0.0]],
			["edge", Gpu.NPIX / 256, tp.slice(4, 6) + [-1, -1], [edge_off + eb, EDGE_R], [0.0]],
			["contact", Gpu.NPIX / 256, tp.slice(0, 4), [FOOT, _foot_n, con_off], [0.0, BAND]],
			["contact", Gpu.NPIX / 256, tp.slice(4, 6) + [-1, -1], [FOOT, _foot_n, con_off + 24], [0.0, BAND]]])
	var nobj := objs.size()
	gpu.alloc("sel", (SURV + nobj * 3) * 4)
	gpu.zero("sel", SURV, nobj * 3)
	gpu.run("surv", Gpu.NPIX / 256, [PL.replica, PL.map], [SURV], [0.0])
	var surv_base: PackedInt32Array = gpu.ints("sel", SURV, nobj * 3)
	out["base"] = {"tests": base_tests}
	for bi in nb:
		var b: int = budgets[bi]
		var info := _shade_budget(rep, deltas[b], tan_cone, sig, [PL.cone, PL.filter])
		var slot := 1 + bi
		gpu.zero("sel", SURV, nobj * 3)
		gpu.runs([["acc", Gpu.NPIX / 256, [PL.cone, PL.filter, -1, -1], [-1, -1, -1, -1], [0.0, float(slot)]],
				["edge", Gpu.NPIX / 256, [PL.cone, PL.filter, -1, -1], [edge_off + slot * 2 * eb, EDGE_R], [0.0]],
				["contact", Gpu.NPIX / 256, [PL.cone, PL.filter, -1, -1], [FOOT, _foot_n, con_off + slot * 48], [0.0, BAND]],
				["surv", Gpu.NPIX / 256, [PL.cone, PL.filter], [SURV], [0.0]]])
		info["survival"] = _survival(gpu.ints("sel", SURV, nobj * 3))
		info["target"] = b
		out.budgets.append(info)
	var raw: PackedInt32Array = gpu.ints("acc", 0, acc_n)
	var accf: PackedFloat32Array = raw.to_byte_array().to_float32_array()
	out.base["mad"] = _mad_block(raw, accf, 0, base_tests)
	out.base["edge"] = _edge_block(raw, accf, edge_off, base_tests.slice(0, 4))
	out.base["edge"].merge(_edge_block(raw, accf, edge_off + eb, base_tests.slice(4, 6)))
	out.base["contact"] = _contact_block(raw, accf, con_off, base_tests.slice(0, 4))
	out.base["contact"].merge(_contact_block(raw, accf, con_off + 24, base_tests.slice(4, 6)))
	out.base["survival_replica_map"] = _survival(surv_base)
	for bi in nb:
		var slot := 1 + bi
		var d: Dictionary = out.budgets[bi]
		d["mad"] = _mad_block(raw, accf, slot, ["cone", "filter"])
		d["edge"] = _edge_block(raw, accf, edge_off + slot * 2 * eb, ["cone", "filter"])
		d["contact"] = _contact_block(raw, accf, con_off + slot * 48, ["cone", "filter"])
	if opt.has("sheets"):
		for k in mini(2, sheet_b.size()):
			_shade_budget(rep, deltas[sheet_b[k]], tan_cone, sig, [PL.sheet1 + k, -1])
		gpu.run("sheet", Gpu.NPIX / 256, [PL.truth, PL.map, PL.sheet1, PL.sheet2])
		var img := Image.create_from_data(Gpu.W, Gpu.H, false, Image.FORMAT_RGBA8, gpu.rd.buffer_get_data(gpu.bufs.img, 0, Gpu.NPIX * 4))
		var m0: Dictionary = out.base.mad.get("map", {}).get("all", {})
		var b1: int = sheet_b[0]
		var b2: int = sheet_b[mini(1, sheet_b.size() - 1)]
		var caption := "view %d    top left: the original's own sun visibility (%s)    top right: the port's shadow map, MAD %.4f against it\nbottom left: tapered capsules at a %d budget, MAD %.4f    bottom right: at %d, MAD %.4f    dark blue: not compared (no receiver in both, or no sun)" % [
			v, str(_meta(opt.truth).get("angle")), m0.get("mad", -1.0), b1, _budget_mad(out, b1), b2, _budget_mad(out, b2)]
		_sheets.append({"view": v, "body": img, "caption": caption})
	return out


func _budget_mad(out: Dictionary, b: int) -> float:
	for d in out.budgets:
		if d.target == b:
			return d.mad.get("cone", {}).get("all", {}).get("mad", -1.0)
	return -1.0


## One budget's capsules binned in the view's light plane, shaded into planes [cone, filter] (-1 skips).
func _shade_budget(rep: Dictionary, delta: float, tan_cone: float, sig: float, planes: Array) -> Dictionary:
	var nobj := objs.size()
	_alloc_table(PackedFloat32Array([delta]), 0)
	gpu.zero("cnt", 8, 4)
	gpu.run("select", (nobj + 63) / 64, [nobj, nobj])
	var nsel: int = gpu.ints("cnt", 9, 1)[0]
	var n := int(ceil(2.0 * S / CELL))
	var blocks := (n * n + Gpu.SCAN_BLOCK - 1) / Gpu.SCAN_BLOCK
	var tmp := 2 * n * n + 2
	var lbase := tmp + blocks + 8
	var pad := 4.0 * maxf(sig, tan_cone * 40.0)
	var fb := [rep.u0, rep.v0, CELL, pad, L.x, L.y, L.z, 0.0, lx.x, lx.y, lx.z, 0.0, ly.x, ly.y, ly.z, 0.0]
	if gpu.sizes.bin < (lbase + (16 << 20)) * 4:
		gpu.alloc("bin", (lbase + (16 << 20)) * 4)
	gpu.zero("bin", 0, n * n + 1)
	var t0 := Time.get_ticks_usec()
	gpu.run("bin", (nsel + 63) / 64, [nsel, n, 0, lbase], [nobj], fb)
	var entries: int = gpu.scan(0, n * n, tmp)
	if lbase + entries > gpu.sizes.bin / 4:
		push_error("capsule_shadow: %d bin entries over the bin buffer" % entries)
		return {}
	gpu.runs([["copy", (n * n + 255) / 256, [0, n * n + 1, n * n]], ["bin", (nsel + 63) / 64, [nsel, n, 1, lbase], [nobj], fb]])
	var bin_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var in_box: int = gpu.ints("cnt", 10, 1)[0]
	var fc := [rep.u0, rep.v0, CELL, NORMAL_BIAS, L.x, L.y, L.z, DEPTH_BIAS, lx.x, lx.y, lx.z, tan_cone, ly.x, ly.y, ly.z, sig]
	var texel_bits: int = PackedFloat32Array([2.0 * S / MAP]).to_byte_array().to_int32_array()[0]
	var info := {"tolerance_m": delta, "capsules_selected": nsel, "capsules_in_view_box": in_box, "bin_entries": entries, "bin_ms_cpu_clock": bin_ms}
	for m in 2:
		if planes[m] < 0:
			continue
		var d := ["cshade", Gpu.NPIX / 128, [n, lbase, planes[m], 1 if m == 0 else 0], [m, texel_bits], fc]
		gpu.zero("cnt", 8, 1)
		gpu.runs([d])
		if m == 0:
			info["tests_per_pixel"] = float(gpu.ints("cnt", 8, 1)[0]) / Gpu.NPIX
			info["shade_ms"] = gpu.time_runs([d], 5)
		else:
			info["shade_ms_filter"] = gpu.time_runs([d], 5)
	return info


func _mad_block(raw: PackedInt32Array, accf: PackedFloat32Array, slot: int, tests: Array) -> Dictionary:
	var out := {}
	for k in tests.size():
		var d := {}
		var s_all := 0.0
		var n_all := 0
		for c in Gpu.NCLS:
			var i := ((slot * Gpu.NTEST + k) * Gpu.NCLS + c) * 2
			var n: int = raw[i + 1]
			if n > 0:
				d[CLASSES[c]] = {"mad": accf[i] / n, "pixels": n}
				s_all += accf[i]
				n_all += n
		if n_all > 0:
			d["all"] = {"mad": s_all / n_all, "pixels": n_all}
			out[tests[k]] = d
	return out


func _edge_block(raw: PackedInt32Array, accf: PackedFloat32Array, off: int, tests: Array) -> Dictionary:
	var out := {}
	var nb := Gpu.HBINS + 2
	for k in tests.size():
		var d := {}
		var tot_h := PackedInt32Array()
		tot_h.resize(Gpu.HBINS)
		var ssum := 0.0
		var sn := 0
		for c in Gpu.NCLS:
			var b := off + (k * Gpu.NCLS + c) * nb
			var h := raw.slice(b, b + Gpu.HBINS)
			for j in Gpu.HBINS:
				tot_h[j] += h[j]
			ssum += accf[b + Gpu.HBINS]
			sn += raw[b + Gpu.HBINS + 1]
			var st := _hist_stats(h, accf[b + Gpu.HBINS], raw[b + Gpu.HBINS + 1])
			if st.edges > 0:
				d[CLASSES[c]] = st
		var all := _hist_stats(tot_h, ssum, sn)
		if all.edges > 0:
			d["all"] = all
			out[tests[k]] = d
	return out


static func _hist_stats(h: PackedInt32Array, ssum: float, sn: int) -> Dictionary:
	var found := 0
	for j in Gpu.HBINS - 1:
		found += h[j]
	var total := found + h[Gpu.HBINS - 1]
	var out := {"edges": total, "found": found, "not_found_fraction": float(h[Gpu.HBINS - 1]) / total if total > 0 else 0.0}
	if found == 0:
		return out
	for q in [["median", 0.5], ["p90", 0.9]]:
		var cum := 0
		for j in Gpu.HBINS - 1:
			cum += h[j]
			if cum >= q[1] * found:
				out[q[0] + "_m"] = (j + 0.5) * 0.005 if j < Gpu.HBINS - 2 else 0.33
				out[q[0]] = household(out[q[0] + "_m"]) if j < Gpu.HBINS - 2 else "over 32 cm"
				break
	out["mean_signed_m"] = ssum / sn if sn > 0 else 0.0
	return out


func _contact_block(raw: PackedInt32Array, accf: PackedFloat32Array, off: int, tests: Array) -> Dictionary:
	var out := {}
	for k in tests.size():
		var d := {}
		for zone in 2:
			var b := off + (k * 2 + zone) * 3
			var n: int = raw[b + 2]
			if n > 0:
				d[["base_band", "corner"][zone]] = {"mad": accf[b] / n, "mean_signed": accf[b + 1] / n, "pixels": n}
		if not d.is_empty():
			out[tests[k]] = d
	return out


## Thin casters (posts, railings) casting at least 20 shadow pixels in the truth: how many of them each
## test keeps in shadow for at least half of those pixels.
func _survival(cnt: PackedInt32Array) -> Dictionary:
	var out := {}
	for cls in ["post", "railing"]:
		var seen := 0
		var kept := [0, 0]
		for o in objs.size():
			if CLASSES[objs[o].cls] != cls or cnt[3 * o] < 20:
				continue
			seen += 1
			for t in 2:
				if cnt[3 * o + 1 + t] * 2 >= cnt[3 * o]:
					kept[t] += 1
		out[cls] = {"objects": seen, "kept_first": kept[0], "kept_second": kept[1]}
	return out


func _pool(res: Dictionary, getter: Callable) -> Dictionary:
	var o := {}
	for c in CLASSES + ["all"]:
		var s := 0.0
		var n := 0
		for pv in res.per_view:
			var d = getter.call(pv)
			if d == null or not d.has(c):
				continue
			s += d[c].mad * d[c].pixels
			n += d[c].pixels
		if n > 0:
			o[c] = {"mad": s / n, "pixels": n}
	return o


func _summarize(res: Dictionary, budgets: Array) -> Dictionary:
	var out := {"map": _pool(res, func(pv): return pv.get("base", {}).get("mad", {}).get("map")),
		"replica": _pool(res, func(pv): return pv.get("base", {}).get("mad", {}).get("replica"))}
	for f in FLOORS:
		out["floor_" + f] = _pool(res, func(pv): return pv.get("base", {}).get("mad", {}).get(f))
	for bi in budgets.size():
		for m in ["cone", "filter"]:
			out["capsules_%d_%s" % [budgets[bi], m]] = _pool(res, func(pv): return pv.budgets[bi].get("mad", {}).get(m) if bi < pv.get("budgets", []).size() else null)
	return out


func _process(_dt: float) -> bool:
	if opt.has("time"):
		_time_tick()
	else:
		_caption_tick()
	return false


func _start_captions() -> void:
	_sheet_vp = SubViewport.new()
	_sheet_vp.size = Vector2i(1920, 120)
	_sheet_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1)
	bg.size = Vector2(1920, 120)
	_sheet_vp.add_child(bg)
	_sheet_label = Label.new()
	_sheet_label.position = Vector2(10, 4)
	_sheet_label.size = Vector2(1900, 112)
	_sheet_label.add_theme_font_size_override("font_size", 16)
	_sheet_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_sheet_vp.add_child(_sheet_label)
	get_root().add_child(_sheet_vp)
	_sheet_wait = 0


func _caption_tick() -> void:
	if _sheet_wait < 0:
		return
	if _sheets.is_empty():
		_sheet_wait = -1
		quit()
		return
	if _sheet_wait == 0:
		_sheet_label.text = _sheets[0].caption
	_sheet_wait += 1
	if _sheet_wait < 4:
		return
	var s: Dictionary = _sheets.pop_front()
	var cap := _sheet_vp.get_texture().get_image()
	cap.convert(Image.FORMAT_RGBA8)
	var img := Image.create(1920, 1080 + 120, false, Image.FORMAT_RGBA8)
	img.blit_rect(s.body, Rect2i(0, 0, 1920, 1080), Vector2i(0, 0))
	img.blit_rect(cap, Rect2i(0, 0, 1920, 120), Vector2i(0, 1080))
	img.convert(Image.FORMAT_RGB8)
	DirAccess.make_dir_recursive_absolute(opt.sheets)
	var path: String = opt.sheets.path_join("capsule-shadow-view%d.png" % s.view)
	img.save_png(path)
	if opt.has("desktop"):
		DirAccess.make_dir_recursive_absolute(opt.desktop)
		var n := 1
		while FileAccess.file_exists(opt.desktop.path_join("capsule-shadow-%02d.png" % n)):
			n += 1
		img.save_png(opt.desktop.path_join("capsule-shadow-%02d.png" % n))
		_log("sheet view %d -> capsule-shadow-%02d.png" % [s.view, n])
	_sheet_wait = 0


# ------------------------------------------------------------------------------ the port's map, timed

## The port's own map at the views of --port: GPU milliseconds per frame with the sun's shadow on and off,
## and the shadow pass's own draw calls and primitives.
var _tm := {}


func _time_map() -> void:
	var pm = _meta(opt.port)
	_tm = {"views": [], "cams": pm.views.map(func(v): return v.cam), "frames": int(opt.get("frames", "60")), "step": 0, "i": 0, "phase": 0, "acc": []}
	var st = load("res://addons/sakuragaoka_station/station.tscn").instantiate()
	_tm["st"] = st
	st.built.connect(func(_s): _tm["ready"] = true)
	get_root().add_child(st)
	var cam := Camera3D.new()
	cam.fov = 58.0
	cam.near = 0.1
	cam.far = 2500.0
	get_root().add_child(cam)
	cam.current = true
	_tm["cam"] = cam
	RenderingServer.viewport_set_measure_render_time(get_root().get_viewport_rid(), true)
	_sheet_wait = -1


func _time_tick() -> void:
	if not _tm.get("ready", false):
		return
	var vp := get_root().get_viewport_rid()
	if _tm.phase == 0:
		if _tm.i >= _tm.cams.size():
			var f := FileAccess.open(opt.out, FileAccess.WRITE)
			f.store_string(JSON.stringify({"views": _tm.views, "frames": _tm.frames, "viewport": get_root().size}, "  ", false))
			f.close()
			print("capsule_shadow: map timing in %s" % opt.out)
			_tm.phase = 9
			quit()
			return
		var c: Array = _tm.cams[_tm.i]
		var lay = Layout.new("")
		var p := Vector3(c[0], lay.height_at(c[0], c[1]) + 1.52, c[1])
		_tm.cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(c[3]), deg_to_rad(c[2]), 0.0), EULER_ORDER_YXZ), p)
		_tm["sun"] = _tm.st.find_children("*", "DirectionalLight3D", true, false)[0]
		_tm.sun.shadow_enabled = true
		_tm.phase = 1
		_tm.step = 0
		_tm.acc = []
		return
	if _tm.phase > 2:
		return
	_tm.step += 1
	if _tm.step <= 20:
		return
	_tm.acc.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	if _tm.acc.size() < _tm.frames:
		return
	var a: Array = _tm.acc.duplicate()
	a.sort()
	var med: float = a[a.size() / 2]
	if _tm.phase == 1:
		_tm["on"] = {"gpu_ms_median": med, "gpu_ms_min": a[0],
			"shadow_primitives": get_root().get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
			"shadow_draw_calls": get_root().get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			"visible_primitives": get_root().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)}
		_tm.sun.shadow_enabled = false
		_tm.phase = 2
	else:
		_tm.views.append({"view": _tm.i, "cam": _tm.cams[_tm.i], "shadow_on": _tm.on, "shadow_off": {"gpu_ms_median": med, "gpu_ms_min": a[0]},
			"shadow_cost_ms": _tm.on.gpu_ms_median - med, "setup": _tm.st.get("shadow_setup")})
		print("capsule_shadow: view %d map on %.3f ms, off %.3f ms" % [_tm.i, _tm.on.gpu_ms_median, med])
		_tm.i += 1
		_tm.phase = 0
	_tm.step = 0
	_tm.acc = []
