# tools/sun_locate.gd --analyze: locates the sun in the rendered images of both engines, on the GPU
# (tools/sun_locate_gpu.gd); this file only arranges the runs and writes the numbers.
# Method A, exact geometry, (1) post shadows: the port's buffers (tools/sun_locate.gd) give each
# pixel's world position at the original's cameras, which tools/oracle/sun_cams.mjs confirms to float
# precision; posts modelled from src/world/plaza/furniture.js cast strips on the paving. From an
# image alone each paving pixel gets a shadow fraction; each post's strip gives a direction (the
# shadow azimuth atan2(-Lz, -Lx)) and, with its top, a tip; the posts' modelled shadows are fitted to
# every window pixel for the sun (2 DOF) and an edge model per engine (dilation d, normal-bias shift b,
# blur s, all in the light plane), jointly, per view and per post, with a bootstrap over posts.
# Engines: the oracle's PNGs; the port's renders; the port with its sun turned (the control); the
# original rendered again (its floor against itself); and, to score the segmentation, both engines'
# own shadow masks (the port's sun alone with and without its shadow, the original's render with
# its shadow intensity at 0) measured the same way.
extends RefCounted

const Gpu = preload("res://tools/sun_locate_gpu.gd")

const SUN_CODE := [-0.776, 0.517, 0.362]

## furniture.js at 4112f57: kit.cyl(rTop, rBot, h, mat, [x, yCentre, z]) as [vcyl, r_top, r_bot, y0, y1],
## spheres as [ell, r, centre, y scale, upper half only], boxes as [box, size, centre, turn about Y],
## the clock face and the round bus-stop sign as [disc, r, thickness, centre, axis].
const KINDS := {
	"bollard": {"r_shaft": 0.0565, "top": 0.825, "prims": [
		["vcyl", 0.075, 0.075, 0.01, 0.05], ["vcyl", 0.055, 0.058, 0.03, 0.77], ["vcyl", 0.058, 0.058, 0.63, 0.69],
		["ell", 0.055, [0.0, 0.77, 0.0], 1.0, true]]},
	"lamp": {"r_shaft": 0.056, "top": 4.505, "prims": [
		["vcyl", 0.10, 0.14, 0.0, 0.42], ["vcyl", 0.05, 0.062, 0.42, 3.92], ["vcyl", 0.075, 0.075, 3.91, 3.99],
		["vcyl", 0.14, 0.12, 3.99, 4.33], ["vcyl", 0.03, 0.23, 4.325, 4.455], ["ell", 0.035, [0.0, 4.47, 0.0], 1.0, false]]},
	"clock": {"r_shaft": 0.0775, "top": 4.06, "prims": [
		["box", [0.44, 0.3, 0.44], [0.0, 0.15, 0.0], 0.0], ["vcyl", 0.075, 0.08, 0.3, 3.4],
		["disc", 0.345, 0.16, [0.0, 3.62, 0.0], [0.0, 0.0, 1.0]], ["ell", 0.06, [0.0, 4.0, 0.0], 1.0, false],
		["vcyl", 0.02, 0.02, 3.94, 4.0]]},
	"postbox": {"r_shaft": 0.2, "top": 1.37, "prims": [
		["box", [0.44, 0.06, 0.44], [0.0, 0.03, 0.0], 0.0], ["vcyl", 0.13, 0.15, 0.06, 0.34], ["vcyl", 0.2, 0.2, 0.34, 1.18],
		["vcyl", 0.215, 0.215, 0.34, 0.38], ["vcyl", 0.228, 0.228, 1.1725, 1.2075],
		["ell", 0.222, [0.0, 1.205, 0.0], 0.62, true], ["ell", 0.03, [0.0, 1.34, 0.0], 1.0, false],
		["box", [0.2, 0.02, 0.06], [0.0, 1.07, 0.195], 0.0], ["box", [0.2, 0.36, 0.02], [0.0, 0.7, -0.195], 0.0]]},
	"bus_stop": {"r_shaft": 0.032, "top": 2.375, "prims": [
		["vcyl", 0.25, 0.27, 0.0, 0.1], ["vcyl", 0.12, 0.2, 0.1, 0.14], ["vcyl", 0.032, 0.032, 0.1, 1.88],
		["box", [0.05, 0.1, 0.05], [0.0, 1.88, 0.0], 0.0], ["disc", 0.255, 0.024, [0.0, 2.12, 0.0], [1.0, 0.0, 0.0]],
		["box", [0.36, 0.6, 0.1], [0.0, 1.28, 0.0], PI / 2.0], ["box", [0.38, 0.03, 0.12], [0.0, 1.59, 0.0], PI / 2.0]]},
	"taxi": {"r_shaft": 0.03, "top": 2.375, "prims": [
		["box", [0.3, 0.08, 0.3], [0.0, 0.04, 0.0], 0.0], ["vcyl", 0.03, 0.03, 0.025, 2.375],
		["box", [0.46, 0.57, 0.03], [0.0, 1.98, 0.05], 0.0], ["box", [0.08, 0.03, 0.05], [0.0, 1.8, 0.025], 0.0],
		["box", [0.08, 0.03, 0.05], [0.0, 2.16, 0.025], 0.0], ["box", [0.4, 0.13, 0.02], [0.0, 1.45, 0.045], 0.0],
		["vcyl", 0.035, 0.035, 2.345, 2.375]]},
}
## plaza.js P.bollards, P.lamps, P.clock, P.postbox; layout.js PLAZA.busStop, PLAZA.taxiStand
const POSTS := [
	["bollard0", "bollard", -2.35, -5.62], ["bollard1", "bollard", -1.2, -5.65], ["bollard2", "bollard", 1.2, -5.65],
	["bollard3", "bollard", 2.35, -5.62], ["bollard4", "bollard", -8.6, -5.75], ["bollard5", "bollard", 16.8, -5.62],
	["bollard6", "bollard", 18.8, -5.62], ["bollard7", "bollard", -8.6, -21.95], ["bollard8", "bollard", -8.6, -19.65],
	["lamp0", "lamp", 5.8, -9.2], ["lamp1", "lamp", 12.6, -12.8], ["lamp2", "lamp", 15.4, -6.5], ["lamp3", "lamp", 17.2, -21.0],
	["clock", "clock", 6.4, -14.6], ["postbox", "postbox", -2.9, -6.35], ["bus_stop", "bus_stop", 8.0, -5.9], ["taxi", "taxi", -6.0, -5.9],
]

var gpu
var log_lines := PackedStringArray()


static func post_defs() -> Array:
	var out := []
	for p in POSTS:
		var k: Dictionary = KINDS[p[1]]
		out.append({"name": p[0], "kind": p[1], "x": p[2], "z": p[3], "top": k.top, "r_shaft": k.r_shaft,
			"r_max": _r_max(k.prims), "prims": k.prims})
	return out


## Largest horizontal reach of a post's parts from its axis.
static func _r_max(prims: Array) -> float:
	var r := 0.0
	for q in prims:
		match q[0]:
			"vcyl":
				r = maxf(r, maxf(q[1], q[2]))
			"ell":
				r = maxf(r, Vector2(q[2][0], q[2][2]).length() + q[1])
			"box":
				var hx: float = q[1][0] / 2.0
				var hz: float = q[1][2] / 2.0
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var v := Vector2(sx * hx, sz * hz).rotated(-q[3]) + Vector2(q[2][0], q[2][2])
						r = maxf(r, v.length())
			"disc":
				r = maxf(r, Vector2(q[3][0], q[3][2]).length() + Vector2(q[1], q[2] / 2.0).length())
	return r


## A length in metres with its household equivalent (CLAUDE.md's anchors), e.g. "5.8 cm (about
## 1.4 golf balls)".
static func household(m: float) -> String:
	var anchors := [["credit card", 0.76], ["penny", 1.52], ["pencil", 7.0], ["AAA battery", 10.5], ["AA battery", 14.5],
		["nickel", 21.2], ["golf ball", 42.7], ["adult wrist", 57.0], ["soda can", 66.0]]
	var mm := absf(m) * 1000.0
	var pick: Array = anchors[0]
	for a in anchors:
		if mm >= a[1]:
			pick = a
	var n: float = mm / pick[1]
	var count := ("%.1f" % n) if n < 3.0 else str(int(round(n)))
	var plural := "" if count == "1.0" else "s"
	var size := ("%.1f mm" % mm) if mm < 10.0 else (("%.1f cm" % (mm / 10.0)) if mm < 1000.0 else ("%.2f m" % (mm / 1000.0)))
	return "%s (about %s %s%s)" % [size, count, pick[0], plural]


static func dir_of(az: float, el: float) -> Vector3:
	var a := deg_to_rad(az)
	var e := deg_to_rad(el)
	return Vector3(-cos(e) * cos(a), sin(e), -cos(e) * sin(a))


static func az_el_of(v: Vector3) -> Vector2:
	v = v.normalized()
	return Vector2(rad_to_deg(atan2(-v.z, -v.x)), rad_to_deg(asin(clampf(v.y, -1.0, 1.0))))


static func angle_between(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


func say(s: String) -> void:
	print(s)
	log_lines.append(s)


## One image set measured and fitted. e: {name, images (pattern with %d), buffers dir, num, den,
## den_images (pattern, for den 1), sun_passes}. Returns its record.
func engine(e: Dictionary, views: Array) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	gpu.rd.buffer_clear(gpu.bufs.lst, 8, 4)  # this engine's window entries start at 0
	gpu.edge_units = 1.0 if e.get("godot_edges", false) else 0.0
	gpu.set_bounds()
	var wins := []
	var rejected := []
	var job := 0
	# pass 1: every post's strip, gated on its own quality; pass 2: windows for the strips that also
	# agree (within 5 degrees) with the median strip direction, which drops a strip locked onto
	# another object's shadow
	var found := {}
	for v in views:
		if not _load(e, v):
			continue
		for k in gpu.posts.size():
			var m: Dictionary = gpu.measure(job % Gpu.MAX_JOBS, k, v, -1)
			job += 1
			if m.is_empty():
				continue
			var why := ""
			if m.centre_bins < 8:
				why = "centre line over %d bins" % m.centre_bins
			elif m.dir_se_rad == null or rad_to_deg(m.dir_se_rad) > 0.5:
				why = "centre line direction unsure"
			elif m.score < 0.5:
				why = "search score %.2f" % m.score
			elif m.window_px < 500:
				why = "window of %d pixels" % m.window_px
			if why != "":
				rejected.append({"post": m.post, "view": v, "why": why, "strip_dir_deg": rad_to_deg(m.dir_rad)})
				continue
			found["%d/%d" % [v, k]] = wrapf(rad_to_deg(m.dir_rad), -180.0, 180.0)
	var dirs := found.values()
	dirs.sort()
	var med: float = dirs[dirs.size() / 2] if dirs.size() else 0.0
	for v in views:
		var todo := []
		for k in gpu.posts.size():
			var key := "%d/%d" % [v, k]
			if not found.has(key):
				continue
			var off: float = absf(wrapf(found[key] - med, -180.0, 180.0))
			if off > 5.0:
				rejected.append({"post": gpu.posts[k].name, "view": v, "why": "%.1f deg off the median strip" % off, "strip_dir_deg": found[key]})
				continue
			todo.append(k)
		if todo.is_empty() or not _load(e, v):
			continue
		for k in todo:
			var m: Dictionary = gpu.measure(job % Gpu.MAX_JOBS, k, v, wins.size())
			job += 1
			if m.is_empty() or m.win[1] - m.win[0] < 500:
				continue
			wins.append(m)
	var n_entries: int = gpu.uints("lst", 2, 1)[0]
	var rec := {"engine": e.name, "windows": [], "views": {}, "rejected": rejected}
	if wins.is_empty():
		say("sun_locate: %s: no post shadow found" % e.name)
		return rec
	# start: the strips' own directions (median), then the elevation by a scan, edge model neutral
	var wdirs := []
	for m in wins:
		wdirs.append(wrapf(rad_to_deg(m.dir_rad), -180.0, 180.0))
	wdirs.sort()
	var az0: float = wdirs[wdirs.size() / 2]
	var scan: Dictionary = gpu.grid(0, n_entries, 0, wins.size(), {"az": az0, "el": 40.0, "d": 0.0, "b": 0.0, "ls": log(0.03),
		"n_az": 1, "n_el": 61, "n_d": 1, "n_b": 1, "n_s": 1, "st_az": 0.0, "st_el": 1.0, "st_d": 0.0, "st_b": 0.0, "st_ls": 0.0})
	var joint: Dictionary = gpu.fit(0, n_entries, 0, wins.size(), {"az": az0, "el": scan.el})
	var nuis := {"d": joint.d, "b": joint.b, "ls": joint.ls}
	var curv: Dictionary = gpu.curvature(0, n_entries, 0, wins.size(), joint, 0.02, 0.04)
	var L := dir_of(joint.az, joint.el)
	rec["joint"] = _sun_record(joint, curv, n_entries, 2)
	var c3: Dictionary = gpu.curvature3(0, n_entries, 0, wins.size(), joint, [0.02, 0.04, 0.05 if gpu.edge_units > 0.5 else 0.002])
	rec.joint["se_curvature_b_profiled_deg"] = _se3(c3, n_entries)
	rec["edge_model"] = {"units": "texels of each pixel's PSSM split" if gpu.edge_units > 0.5 else "m",
		"dilation": joint.d, "normal_bias": joint.b, "blur_m": exp(joint.ls)}
	rec["start"] = {"azimuth_deg": az0, "elevation_deg": scan.el}
	# bootstrap over posts (windows): the sun and b refitted, dilation and blur held
	var boot_az := PackedFloat64Array()
	var boot_el := PackedFloat64Array()
	var nboot: int = e.get("boot", 100)
	for r in nboot:
		var b: Dictionary = gpu.fit(0, n_entries, 0, wins.size(), joint, nuis, r + 1, 8, true)
		boot_az.append(b.az)
		boot_el.append(b.el)
	rec.joint["bootstrap"] = _spread(boot_az, boot_el, joint)
	# the edge model's own spread over posts: every parameter refitted per replicate
	var eb := []
	for r in int(e.get("edge_boot", 0)):
		var f: Dictionary = gpu.fit(0, n_entries, 0, wins.size(), joint, null, 1000 + r, 8)
		eb.append([f.d, f.b, exp(f.ls)])
	if eb.size() >= 2:
		var sd := []
		for k in 3:
			var m := 0.0
			for x in eb:
				m += x[k]
			m /= eb.size()
			var v := 0.0
			for x in eb:
				v += (x[k] - m) ** 2
			sd.append(sqrt(v / (eb.size() - 1)))
		rec.edge_model["bootstrap_sd"] = {"replicates": eb.size(), "dilation": sd[0], "normal_bias": sd[1], "blur_m": sd[2]}
	# per view and per post, the edge model held
	var by_view := {}
	for wi in wins.size():
		var m: Dictionary = wins[wi]
		if not by_view.has(m.view):
			by_view[m.view] = [wi, wi + 1, m.win[0], m.win[1]]
		else:
			by_view[m.view][1] = wi + 1
			by_view[m.view][3] = m.win[1]
	for v in by_view:
		var r: Array = by_view[v]
		var f: Dictionary = gpu.fit(r[2], r[3], r[0], r[1], joint, nuis)
		var c: Dictionary = gpu.curvature(r[2], r[3], r[0], r[1], f, 0.02, 0.04)
		rec.views[str(v)] = _sun_record(f, c, r[3] - r[2], 2)
		rec.views[str(v)]["posts"] = r[1] - r[0]
		if r[1] - r[0] >= 2:
			var va := PackedFloat64Array()
			var ve := PackedFloat64Array()
			for k in mini(nboot, 50):
				var bf: Dictionary = gpu.fit(r[2], r[3], r[0], r[1], f, nuis, k + 1, 6)
				va.append(bf.az)
				ve.append(bf.el)
			rec.views[str(v)]["bootstrap"] = _spread(va, ve, f)
	for wi in wins.size():
		var m: Dictionary = wins[wi]
		var f: Dictionary = gpu.fit(m.win[0], m.win[1], wi, wi + 1, joint, nuis)
		var c: Dictionary = gpu.curvature(m.win[0], m.win[1], wi, wi + 1, f, 0.02, 0.04)
		var pr := _sun_record(f, c, m.win[1] - m.win[0], 2)
		var p: Dictionary = gpu.posts[m.post_index]
		# tips along the jointly fitted sun: the model's (with the engine's edge model) and the image's
		var reach: float = m.reach
		var mv: Dictionary = e.meta.views[m.view]
		gpu.set_tip_camera(Vector3(mv.origin[0], mv.origin[1], mv.origin[2]), -Vector3(mv.basis_z[0], mv.basis_z[1], mv.basis_z[2]))
		var mt: float = gpu.tip(m.post_index, joint.az, joint.el, joint.d, joint.b, reach)
		var dir := atan2(-L.z, -L.x)
		var ot: float = gpu.obs_tip(wi, m.win[0], m.win[1], dir, m.post_index, mt, maxf(0.7 * p.r_shaft, 0.02))
		var raw_el = null
		if ot > 0.0:
			raw_el = _el_from_tip(m.post_index, rad_to_deg(m.dir_rad), ot, reach)
		pr.merge({"post": m.post, "kind": m.kind, "view": m.view, "base": [p.x, Gpu.GROUND_Y, p.z], "top": p.top,
			"strip_dir_deg": rad_to_deg(m.dir_rad), "strip_dir_se_deg": rad_to_deg(m.dir_se_rad) if m.dir_se_rad != null else null,
			"strip_centre_bins": m.centre_bins, "strip_shaft_m": m.shaft_strip_m, "levels_log": m.levels_log,
			"window_px": m.window_px, "window_entries": m.win[1] - m.win[0], "slices_dropped": [m.slices_dropped, m.slices],
			"window_end_m": m.window_end_m,
			"tip_model_m": mt, "tip_observed_m": ot if ot > 0.0 else null,
			"elevation_from_tip_raw_deg": raw_el})
		rec.windows.append(pr)
	var dt := (Time.get_ticks_msec() - t0) / 1000.0
	var edge_txt := "edge d %.3f b %.3f texels, s %s" % [joint.d, joint.b, household(exp(joint.ls))] if gpu.edge_units > 0.5 \
			else "edge d %s, b %s, s %s" % [household(joint.d), household(joint.b), household(exp(joint.ls))]
	say("sun_locate: %s: %d post windows over views %s, %d entries; joint az %.3f el %.3f (to code sun %.3f deg); %s; %.0f s" % [
		e.name, wins.size(), str(by_view.keys()), n_entries, joint.az, joint.el, angle_between(L, Vector3(SUN_CODE[0], SUN_CODE[1], SUN_CODE[2])),
		edge_txt, dt])
	return rec


## Method A (2), toon bands, on one image set: the posts' own surfaces, lit in the port's shadow
## mask, as regions of one post and one albedo; the sun whose N.L bands best explain each region's
## log luminance (the original's steps at the gradient map's texel edges N.L = 0, 0.125, 0.375; the
## port's MToon over 0..0.1), jointly and per view, with a bootstrap over regions.
func toon(e: Dictionary, views: Array, meta: Dictionary, nboot: int) -> Dictionary:
	var ramp: bool = e.get("godot_edges", false)
	var edges: Array = [0.0, 0.1, 1e9] if ramp else [0.0, 0.125, 0.375]
	gpu.tb_begin()
	var ranges := {}
	for v in views:
		gpu.load_view(e.buffers, v, true)
		if not gpu.load_png(e.images % v, "img"):
			continue
		var o: Array = meta.views[v].origin
		ranges[v] = gpu.tb_collect(Vector3(o[0], o[1], o[2]), true)
	var nr: int = gpu.tb_regions(40)
	var all := [1 << 30, 0]
	for v in ranges:
		all[0] = mini(all[0], ranges[v][0])
		all[1] = maxi(all[1], ranges[v][1])
	var rec := {"model": "MToon ramp: I = a + c clamp(N.L / 0.1, 0, 1) per region" if ramp else "MeshToonMaterial steps at N.L = 0, 0.125, 0.375 (16-texel nearest gradient map), one level per band and region",
		"regions": nr, "pixels": all[1] - all[0], "views": {}}
	if nr == 0 or all[1] <= all[0]:
		return rec
	var j: Dictionary = gpu.tb_fit(all[0], all[1], edges, 0, null, ramp)
	var code := Vector3(SUN_CODE[0], SUN_CODE[1], SUN_CODE[2]).normalized()
	rec["joint"] = {"azimuth_deg": j.az, "elevation_deg": j.el, "angle_to_code_sun_deg": angle_between(dir_of(j.az, j.el), code)}
	var ba := PackedFloat64Array()
	var be := PackedFloat64Array()
	for r in nboot:
		var b: Dictionary = gpu.tb_fit(all[0], all[1], edges, r + 1, j, ramp)
		ba.append(b.az)
		be.append(b.el)
	rec.joint["bootstrap"] = _spread(ba, be, j)
	for v in ranges:
		var rg: Array = ranges[v]
		if rg[1] - rg[0] < 3000:
			if rg[1] > rg[0]:
				rec.views[str(v)] = {"pixels": rg[1] - rg[0], "note": "too few post-surface pixels for a band fit"}
			continue
		var f: Dictionary = gpu.tb_fit(rg[0], rg[1], edges, 0, null, ramp)
		rec.views[str(v)] = {"azimuth_deg": f.az, "elevation_deg": f.el, "pixels": rg[1] - rg[0],
			"angle_to_code_sun_deg": angle_between(dir_of(f.az, f.el), code)}
		var va := PackedFloat64Array()
		var ve := PackedFloat64Array()
		for r in mini(nboot, 30):
			var bf: Dictionary = gpu.tb_fit(rg[0], rg[1], edges, r + 1, null, ramp)
			va.append(bf.az)
			ve.append(bf.el)
		rec.views[str(v)]["bootstrap"] = _spread(va, ve, f)
	say("sun_locate: %s toon bands: %d regions, %d pixels; joint az %.3f el %.3f (to code sun %.3f deg)" % [
		e.name, nr, all[1] - all[0], j.az, j.el, rec.joint.angle_to_code_sun_deg])
	return rec


func _load(e: Dictionary, v: int) -> bool:
	gpu.load_view(e.buffers, v, e.get("sun_passes", false))
	if e.num == 0 and not gpu.load_png(e.images % v, "img"):
		say("sun_locate: %s view %d: no image %s" % [e.name, v, e.images % v])
		return false
	if e.den == 1 and not gpu.load_png(e.den_images % v, "outp"):
		say("sun_locate: %s view %d: no reference %s" % [e.name, v, e.den_images % v])
		return false
	gpu.make_rel(e.num, e.den)
	return true


## Elevation at which the post's modelled tip (edge model neutral) lands on the observed tip, the
## azimuth held at the strip's own direction: bisection over the GPU tip.
func _el_from_tip(post_index: int, az: float, tip: float, reach: float):
	var units: float = gpu.edge_units
	gpu.edge_units = 0.0
	var r = _bisect_tip(post_index, az, tip, reach)
	gpu.edge_units = units
	return r


func _bisect_tip(post_index: int, az: float, tip: float, reach: float):
	var lo := 3.0
	var hi := 87.0
	if gpu.tip(post_index, az, lo, 0.0, 0.0, reach) < tip or gpu.tip(post_index, az, hi, 0.0, 0.0, reach) > tip:
		return null
	for i in 40:
		var mid := 0.5 * (lo + hi)
		if gpu.tip(post_index, az, mid, 0.0, 0.0, reach) > tip:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


func _sun_record(f: Dictionary, c: Dictionary, n: int, p: int) -> Dictionary:
	var L := dir_of(f.az, f.el)
	var code := Vector3(SUN_CODE[0], SUN_CODE[1], SUN_CODE[2]).normalized()
	var out := {"azimuth_deg": f.az, "elevation_deg": f.el, "sun_dir": [L.x, L.y, L.z],
		"angle_to_code_sun_deg": angle_between(L, code), "cost": f.cost}
	# curvature errors: cost ~ sum r^2 / (2 f^2) near the optimum, so cov = 2 C / (n - p) * inv(Hess C)
	var det: float = c.faa * c.fee - c.fae * c.fae
	if det > 0.0 and c.faa > 0.0:
		var s2: float = 2.0 * c.c0 / maxf(1.0, n - p)
		out["se_curvature_deg"] = [sqrt(s2 * c.fee / det), sqrt(s2 * c.faa / det)]
	else:
		out["se_curvature_deg"] = null
	return out


## Azimuth and elevation errors from a 3 x 3 Hessian over (az, el, b): cov = 2 C / (n - 3) inv(H).
static func _se3(c3: Dictionary, n: int):
	var H: Array = c3.H
	var a: float = H[0][0]
	var b: float = H[0][1]
	var c: float = H[0][2]
	var d: float = H[1][1]
	var e: float = H[1][2]
	var f: float = H[2][2]
	var det := a * (d * f - e * e) - b * (b * f - c * e) + c * (b * e - c * d)
	if det <= 0.0:
		return null
	var s2: float = 2.0 * c3.c0 / maxf(1.0, n - 3)
	var i00 := (d * f - e * e) / det
	var i11 := (a * f - c * c) / det
	if i00 <= 0.0 or i11 <= 0.0:
		return null
	return [sqrt(s2 * i00), sqrt(s2 * i11)]


func _spread(az: PackedFloat64Array, el: PackedFloat64Array, centre: Dictionary) -> Dictionary:
	var n := az.size()
	if n < 2:
		return {}
	var ma := 0.0
	var me := 0.0
	for i in n:
		ma += az[i]
		me += el[i]
	ma /= n
	me /= n
	var va := 0.0
	var ve := 0.0
	var ang := PackedFloat64Array()
	var c := dir_of(centre.az, centre.el)
	for i in n:
		va += (az[i] - ma) ** 2
		ve += (el[i] - me) ** 2
		ang.append(angle_between(dir_of(az[i], el[i]), c))
	ang.sort()
	var sa := az.duplicate()
	var se := el.duplicate()
	sa.sort()
	se.sort()
	var q := func(arr: PackedFloat64Array, f: float) -> float: return arr[int(round(f * (arr.size() - 1)))]
	return {"replicates": n, "azimuth_sd_deg": sqrt(va / (n - 1)), "elevation_sd_deg": sqrt(ve / (n - 1)),
		"azimuth_p2.5_p16_p50_p84_p97.5_deg": [q.call(sa, 0.025), q.call(sa, 0.16), q.call(sa, 0.5), q.call(sa, 0.84), q.call(sa, 0.975)],
		"elevation_p2.5_p16_p50_p84_p97.5_deg": [q.call(se, 0.025), q.call(se, 0.16), q.call(se, 0.5), q.call(se, 0.84), q.call(se, 0.975)],
		"angle_p68_deg": ang[int(0.68 * (n - 1))], "angle_p95_deg": ang[int(0.95 * (n - 1))]}


# ---------------------------------------------------------------------------- contact sheets

## A camera from tools/sun_locate.gd's meta: world point -> pixel (x right, y down, pixel centres
## at +0.5), or null behind the camera.
static func project(v: Dictionary, p: Vector3):
	var R := Basis(Vector3(v.basis_x[0], v.basis_x[1], v.basis_x[2]), Vector3(v.basis_y[0], v.basis_y[1], v.basis_y[2]),
			Vector3(v.basis_z[0], v.basis_z[1], v.basis_z[2]))
	var q := R.transposed() * (p - Vector3(v.origin[0], v.origin[1], v.origin[2]))
	if q.z > -0.05:
		return null
	var p00: float = v.projection[0][0]
	var p11: float = v.projection[1][1]
	return Vector2((q.x / -q.z * p00 * 0.5 + 0.5) * Gpu.W, (0.5 - q.y / -q.z * p11 * 0.5) * Gpu.H)


## One sheet body per view (oracle | port with their measurements; both shadow masks over the
## oracle, red the oracle's, cyan the port's, white both; a crop of them around the posts at full
## size) and its caption. recs: the oracle's and the port's engine records.
func sheets(views: Array, meta: Dictionary, port_dir: String, oracle_pattern: String, recs: Dictionary) -> Array:
	var out := []
	var colours := {"base": Color(1.0, 0.55, 0.0), "obs": Color(0.1, 1.0, 0.2), "tip": Color(1.0, 0.9, 0.1),
		"fit": Color(1.0, 0.9, 0.1), "strip": Color(1.0, 0.2, 0.9)}
	for v in views:
		var mv: Dictionary = meta.views[v]
		gpu.load_view(port_dir, v, false)
		gpu.load_png(port_dir.path_join("port-view_%d.png" % v), "img")
		gpu.make_rel(0, 0)
		gpu.mask_image(1, Gpu.MAX_JOBS - 1)
		gpu.load_png(oracle_pattern % v, "img")
		gpu.make_rel(0, 0)
		gpu.mask_image(0, Gpu.MAX_JOBS - 1)
		gpu.load_png(port_dir.path_join("port-view_%d.png" % v), "outp")
		var markers := []
		var box := Rect2()
		var have_box := false
		var caption := PackedStringArray()
		for k in [["oracle", 0, 2], ["port", 1, 3]]:
			var rec: Dictionary = recs.get(k[0], {})
			var post_ids := []
			var edge: Dictionary = rec.get("edge_model", {})
			var godot: bool = k[0] == "port"
			for w in rec.get("windows", []):
				if w.view != v:
					continue
				post_ids.append(_post_index(w.post))
				var base := Vector3(w.base[0], w.base[1], w.base[2])
				var sun: Dictionary = rec.views.get(str(v), rec.joint)
				var L := dir_of(sun.azimuth_deg, sun.elevation_deg)
				var u := Vector3(-L.x, 0.0, -L.z).normalized()
				var su := Vector3(cos(deg_to_rad(w.strip_dir_deg)), 0.0, sin(deg_to_rad(w.strip_dir_deg)))
				var pb = project(mv, base)
				var pt = project(mv, base + u * w.tip_model_m)
				var ps = project(mv, base + su * maxf(w.tip_model_m, 1.0))
				if pb == null:
					continue
				markers.append([1, k[1], pb.x, pb.y, 7.0, 0.0, colours.base, 2.0])
				for q in [pb, pt]:
					if q != null:
						box = Rect2(q, Vector2.ZERO) if not have_box else box.expand(q)
						have_box = true
				if pt != null:
					markers.append([0, k[1], pb.x, pb.y, pt.x, pt.y, colours.fit, 2.0])
					markers.append([2, k[1], pt.x, pt.y, 8.0, 0.0, colours.tip, 2.0])
				if ps != null:
					markers.append([0, k[1], pb.x, pb.y, ps.x, ps.y, colours.strip, 1.0])
				if w.tip_observed_m != null:
					var po = project(mv, base + u * w.tip_observed_m)
					if po != null:
						markers.append([1, k[1], po.x, po.y, 6.0, 0.0, colours.obs, 2.0])
			if not post_ids.is_empty() and not edge.is_empty():
				var sun: Dictionary = rec.views.get(str(v), rec.joint)
				var d: float = edge.dilation
				var b: float = edge.normal_bias
				gpu.mask_model(k[2], post_ids, {"az": sun.azimuth_deg, "el": sun.elevation_deg, "d": d, "b": b, "s": edge.blur_m}, godot)
			else:
				gpu.mask_model(k[2], [], {"az": 0.0, "el": 45.0, "d": 0.0, "b": 0.0, "s": 0.03}, godot)
			caption.append(_caption(k[0], rec, v))
		# crop: the posts' bases and tips with a margin, 16:9, between 480 x 270 and 960 x 540 source
		# pixels (so at full size or larger), centred on them
		var crop := Rect2(Vector2(480, 270), Vector2(960, 540))
		if have_box:
			box = box.grow(80.0)
			var wd := clampf(maxf(box.size.x, box.size.y * 16.0 / 9.0), 480.0, 960.0)
			var c := box.get_center()
			crop = Rect2(c - Vector2(wd, wd * 9.0 / 16.0) / 2.0, Vector2(wd, wd * 9.0 / 16.0))
			crop.position.x = clampf(crop.position.x, 0.0, 1920.0 - crop.size.x)
			crop.position.y = clampf(crop.position.y, 0.0, 1080.0 - crop.size.y)
		var body: Image = gpu.sheet(markers, crop, crop.size.x / 960.0)
		var cam: Array = mv.cam
		var head := "view %d, yaw %.1f pitch %.1f.  Top: original | port; orange ring base, yellow line fitted sun's shadow direction to the model tip (+), green ring observed tip, magenta line the strip's own centre line, yellow outline the model shadow." % [
			v, cam[2], cam[3]]
		var head2 := "Bottom: shadow masks from each image over the paving, red original only, cyan port only, white both; right: x%.2f at (%d, %d), model outlines orange (original's fit) and blue (port's)." % [
			960.0 / crop.size.x, int(crop.position.x), int(crop.position.y)]
		out.append({"view": v, "body": body, "caption": head + "\n" + head2 + "\n" + "\n".join(caption)})
	return out


func _post_index(name: String) -> int:
	for i in gpu.posts.size():
		if gpu.posts[i].name == name:
			return i
	return -1


func _caption(name: String, rec: Dictionary, v: int) -> String:
	if rec.is_empty() or not rec.has("joint"):
		return "%s: no post shadow measured" % name
	var parts := PackedStringArray()
	var pv = rec.views.get(str(v))
	if pv != null:
		parts.append("post shadows here (%d posts) az %.2f el %.2f, %.2f deg from SUN_DIR" % [pv.posts, pv.azimuth_deg, pv.elevation_deg, pv.angle_to_code_sun_deg])
	else:
		parts.append("no post shadow in this view")
	var tb: Dictionary = rec.get("toon_bands", {})
	var tv = tb.get("views", {}).get(str(v))
	if tv != null and tv.has("azimuth_deg"):
		var sd := ""
		if tv.has("bootstrap") and tv.bootstrap.has("angle_p68_deg"):
			sd = ", bootstrap 68 %% %.2f deg" % tv.bootstrap.angle_p68_deg
		parts.append("toon bands here az %.2f el %.2f (%.2f deg%s)" % [tv.azimuth_deg, tv.elevation_deg, tv.angle_to_code_sun_deg, sd])
	elif tv != null:
		parts.append("toon bands: %d post-surface pixels, too few" % tv.pixels)
	parts.append("joint: shadows az %.2f el %.2f (%.2f deg)" % [rec.joint.azimuth_deg, rec.joint.elevation_deg, rec.joint.angle_to_code_sun_deg])
	if tb.has("joint"):
		parts.append("toon az %.2f el %.2f (%.2f deg)" % [tb.joint.azimuth_deg, tb.joint.elevation_deg, tb.joint.angle_to_code_sun_deg])
	return "%s: %s" % [name, "; ".join(parts)]
