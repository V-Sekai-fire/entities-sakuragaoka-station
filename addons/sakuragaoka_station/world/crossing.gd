# crossing.js: the level crossing on road R2 over both tracks. Owns everything inside L.CROSSING.zone
# except the road asphalt (street) and the rails (railway): deck, equipment aprons, road markings, four
# warning posts, two barrier machines with animated arms, control cabinet, relay box, reaction lamps,
# side fences and signs. Animation follows ctx.services.rail.crossingActive / crossingApproach, or a
# timetable-derived demo cycle without it. Publishes ctx.services.crossing.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const CrossingTex = preload("res://addons/sakuragaoka_station/world/crossing/tex.gd")
const Glow = preload("res://addons/sakuragaoka_station/world/crossing/glow.gd")


static func clamp01(v: float) -> float:
	return minf(1.0, maxf(0.0, v))


static func _ease(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


func build(ctx):
	var L = ctx.L
	var mat = ctx.mat
	var physics = ctx.physics
	var P: Dictionary = ctx.palette
	var CR: Dictionary = L.CROSSING
	var CX: float = CR.x
	var RW: float = CR.roadHalfW
	var XRW := CX - RW
	var XRE := CX + RW
	var XLW := XRW + 0.75
	var XLE := XRE - 0.75
	var XDW := -15.5
	var XDE := -8.5
	var BEAM := 0.2
	var XWW := XDW + BEAM
	var XWE := XDE - BEAM
	var ZDS: float = CR.deckZ1
	var ZDN: float = CR.deckZ0
	var ZSS: float = CR.stopLineSouthZ
	var ZSN: float = CR.stopLineNorthZ
	var ZONE: Dictionary = CR.zone
	var RTOP: float = L.RAIL.railTopY + 0.004
	var XAW := -16.9
	var XAE := -7.1
	var ZFS := -39.1
	var ZFN := -46.9
	var prof := func(z: float) -> float:
		return L.height_at(CX, z)
	var APR := 0.004

	var TX := CrossingTex.new(ctx)
	var root := T.Group.new()
	root.name = "crossing"
	ctx.add_static(root)
	var k = ctx.kit(root)
	var rng = ctx.rng("crossing")

	var POST_R := 0.075
	var POST_H := 4.0
	var M := {
		"ink": mat.toon(CrossingTex.INK, {"paint": 0.03}),
		"inkD": mat.toon(CrossingTex.INK, {"side": "double", "paint": 0.03}),
		"housing": mat.toon("#47444f", {"paint": 0.03}),
		"rim": mat.toon("#5d5a66"),
		"steel": mat.toon(P.steel),
		"steelDark": mat.toon(P.steelDark),
		"concrete": mat.toon(P.concrete),
		"beam": mat.toon("#c7c5bc", {"paint": 0.06, "polygonOffset": -1}),
		"asphalt": mat.toon("#ffffff", {"map": TX.asphalt, "paint": 0.04, "polygonOffset": -1}),
		"rubber": [mat.toon("#686a71", {"map": TX.rubber, "paint": 0.04, "polygonOffset": -1}), mat.toon("#71727a", {"map": TX.rubber, "paint": 0.04, "polygonOffset": -1})],
		"rubberG": mat.toon("#8fb095", {"map": TX.rubber, "paint": 0.04, "polygonOffset": -1}),
		"apron": mat.toon("#ffffff", {"map": TX.concrete, "paint": 0.05, "polygonOffset": -1}),
		"post": mat.toon("#ffffff", {"map": TX.postStripe(POST_H / (2.0 * PI * POST_R)), "paint": 0.03}),
		"mach": mat.toon("#ffffff", {"map": TX.machStripe, "paint": 0.03}),
		"sign": mat.toon("#ffffff", {"map": TX.signAtlas, "paint": 0.015}),
		"speaker": mat.toon("#a9aeb3"),
		"emBox": mat.toon("#ece5d6"),
		"btnRed": mat.toon("#e8503f"),
		"cab": mat.toon("#bcc1c4"),
		"red": mat.toon("#d9463b"),
		"yellow": mat.toon(CrossingTex.HAZ_YELLOW, {"paint": 0.03}),
		"fence": mat.toon("#6f9a7c", {"paint": 0.04}),
		"fenceMesh": mat.foliage("#7aa386", TX.mesh, {"paint": 0.02}),
		"grass": mat.foliage("#ffffff", TX.grass, {"paint": 0.05}),
		"lensOff": mat.toon("#9b4448", {"paint": 0.02}),
		"lensOn": mat.emissive("#ff563f", 2.4),
		"arrowOff": mat.toon("#5b5864", {"paint": 0.02}),
		"arrowOn": mat.emissive("#ffd98c", 2.1),
		"reactOff": mat.toon("#d6d2ca", {"paint": 0.02}),
		"reactOn": mat.emissive("#fff3da", 2.2),
		"white": mat.decal("#eeece6", {"map": TX.worn}),
		"green": mat.decal("#7fb08b", {"map": TX.worn}),
		"sym": mat.decal("#ffffff", {"map": TX.roadAtlas}),
		"guide": mat.decal("#ffffff", {"map": TX.guide}),
	}
	M["slot"] = M.housing; M["machCap"] = M.rim; M["grille"] = M.rim; M["weight"] = M.rim; M["plateBack"] = M.speaker
	M["cabRoof"] = M.steel; M["emTop"] = M.red; M["tipRed"] = M.red
	var atlas_geo_cache := {}
	var atlas_geo := func(kind: String, name: String) -> T.Geometry:
		var key := kind + "|" + name
		if atlas_geo_cache.has(key):
			return atlas_geo_cache[key]
		var g: T.Geometry = (Geo.g_box(ctx.cache) if kind == "box" else Geo.g_plane(ctx.cache)).clone()
		var r: Array = TX.rect[name]
		var uv: T.Attr = g.attributes.uv
		for i in uv.count():
			uv.set_xy(i, r[0] + (r[2] - r[0]) * uv.get_x(i), r[1] + (r[3] - r[1]) * uv.get_y(i))
		atlas_geo_cache[key] = g
		return g
	var sign_plane := func(kk, name: String, w: float, h: float, pos: Array, rot = null):
		var me = kk.mesh(atlas_geo.call("plane", name), M.sign, pos, rot, [w, h, 1])
		me.cast_shadow = false
		return me
	var sign_box := func(kk, name: String, w: float, h: float, d: float, pos: Array, rot = null):
		return kk.mesh(atlas_geo.call("box", name), M.sign, pos, rot, [w, h, d])

	# Box-like slab: top from top_fn(x, z) on an nx by nz grid, skirts down to y_bot; sides s/e/n/w (south = +z).
	var slab_geo := func(x0: float, x1: float, z0: float, z1: float, top_fn: Callable, y_bot: float, o: Dictionary = {}) -> T.Geometry:
		var nx: int = o.get("nx", 1)
		var nz: int = o.get("nz", 1)
		var tile: float = o.get("tile", 1.0)
		var sides: Dictionary = o.get("sides", {"s": 1, "e": 1, "n": 1, "w": 1})
		var pos := []
		var uv := []
		var idx := []
		var W := nx + 1
		for j in nz + 1:
			for i in nx + 1:
				var x := x0 + (x1 - x0) * i / nx
				var z := z0 + (z1 - z0) * j / nz
				pos.append_array([x, top_fn.call(x, z), z])
				uv.append_array([x / tile, -z / tile])
		for j in nz:
			for i in nx:
				var a := j * W + i
				var b := a + 1
				var c := a + W
				var d := c + 1
				idx.append_array([a, c, b, b, c, d])
		var wall := func(pts: Array) -> void:
			var base := pos.size() / 3
			var dist := 0.0
			for i in pts.size():
				var x: float = pts[i][0]
				var z: float = pts[i][1]
				if i:
					dist += Vector2(x - pts[i - 1][0], z - pts[i - 1][1]).length()
				var yt: float = top_fn.call(x, z)
				pos.append_array([x, yt, z, x, y_bot, z])
				uv.append_array([dist / tile, yt / tile, dist / tile, y_bot / tile])
			for i in pts.size() - 1:
				var t0 := base + i * 2
				idx.append_array([t0, t0 + 1, t0 + 3, t0, t0 + 3, t0 + 2])
		var lin := func(a: float, b: float, n: int) -> Array:
			var o2 := []
			for i in n + 1:
				o2.append(a + (b - a) * i / n)
			return o2
		if sides.get("s", 0):
			wall.call(lin.call(x0, x1, nx).map(func(x): return [x, z1]))
		if sides.get("e", 0):
			wall.call(lin.call(z1, z0, nz).map(func(z): return [x1, z]))
		if sides.get("n", 0):
			wall.call(lin.call(x1, x0, nx).map(func(x): return [x, z0]))
		if sides.get("w", 0):
			wall.call(lin.call(z0, z1, nz).map(func(z): return [x0, z]))
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(PackedFloat32Array(pos), 3))
		g.set_attribute("uv", T.Attr.new(PackedFloat32Array(uv), 2))
		g.set_index(PackedInt32Array(idx))
		g.compute_vertex_normals()
		return g
	var add_mesh := func(g: T.Geometry, m, shadow: bool = true, parent = null):
		var me := T.MeshObj.new(g, m)
		me.cast_shadow = shadow
		me.receive_shadow = true
		(parent if parent != null else root).add(me)
		return me
	# Flat decal on the ground or deck at y = y_fn(x, z). mode "N" reads facing north, "S" facing south,
	# "W" world-tiled. render_order layers coplanar paint: green (1) < white (2) < symbols (3).
	var ORDER := {}
	var decal := func(x0: float, x1: float, z0: float, z1: float, y_fn: Callable, m, o: Dictionary = {}):
		var mode: String = o.get("mode", "W")
		var tile: float = o.get("tile", 1.5)
		var nz: int = o.get("nz", 1)
		var nx: int = o.get("nx", 1)
		if x0 > x1:
			var t := x0; x0 = x1; x1 = t
		if z0 > z1:
			var t := z0; z0 = z1; z1 = t
		var pos := PackedFloat32Array()
		var uv := PackedFloat32Array()
		var idx := PackedInt32Array()
		var W := nx + 1
		var r: Array = TX.rect[o.rect] if o.get("rect") else [0, 0, 1, 1]
		for j in nz + 1:
			for i in nx + 1:
				var x := x0 + (x1 - x0) * i / nx
				var z := z0 + (z1 - z0) * j / nz
				pos.append_array([x, y_fn.call(x, z), z])
				var fu := (x - x0) / (x1 - x0)
				var fv := (z1 - z) / (z1 - z0)
				if mode == "N":
					uv.append_array([r[0] + (r[2] - r[0]) * fu, r[1] + (r[3] - r[1]) * fv])
				elif mode == "S":
					uv.append_array([r[0] + (r[2] - r[0]) * (1 - fu), r[1] + (r[3] - r[1]) * (1 - fv)])
				else:
					uv.append_array([x / tile, -z / tile])
		for j in nz:
			for i in nx:
				var a := j * W + i
				var b := a + 1
				var c := a + W
				var d := c + 1
				idx.append_array([a, c, b, b, c, d])
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(pos, 3))
		g.set_attribute("uv", T.Attr.new(uv, 2))
		g.set_index(idx)
		g.compute_vertex_normals()
		var me := T.MeshObj.new(g, m)
		me.cast_shadow = false
		me.receive_shadow = true
		me.render_order = ORDER.get(m, 3)
		ctx.no_outline(me)
		root.add(me)
		return me
	var pipe := func(a: Vector3, b: Vector3, r: float, m, parent = null, seg: int = 8):
		var d := b - a
		var length := d.length()
		var me := T.MeshObj.new(Geo.g_cyl(ctx.cache, seg), m)
		me.scale = Vector3(r * 2, length, r * 2)
		me.position = a + d * 0.5
		me.set_quaternion(T.quat_from_unit_vectors(Vector3.UP, d.normalized()))
		me.cast_shadow = true
		me.receive_shadow = true
		(parent if parent != null else root).add(me)
		return me

	# deck
	var HG: float = L.RAIL.gauge / 2.0
	var OUTER := 0.08
	var INNER := 0.07
	var OUTW := 0.70
	var zA: float = L.RAIL.zA
	var zB: float = L.RAIL.zB
	var strips := []
	for tz in [zA, zB]:
		var rs: float = tz + HG
		var rn: float = tz - HG
		strips.append({"z0": rs + OUTER, "z1": rs + OUTER + OUTW, "kind": "rubber"})
		strips.append({"z0": rn + INNER, "z1": rs - INNER, "kind": "rubber"})
		strips.append({"z0": rn - OUTER - OUTW, "z1": rn - OUTER, "kind": "rubber"})
	strips.append({"z0": zA + HG + OUTER + OUTW, "z1": ZDS, "kind": "asphalt"})
	strips.append({"z0": zB + HG + OUTER + OUTW, "z1": zA - HG - OUTER - OUTW, "kind": "asphalt"})
	strips.append({"z0": ZDN, "z1": zB - HG - OUTER - OUTW, "kind": "asphalt"})

	add_mesh.call(slab_geo.call(XDW + 0.01, XDE - 0.01, ZDN + 0.01, ZDS - 0.01, func(_x, _z): return 0.03, -0.45), M.slot, false)
	var flat := func(y: float) -> Callable:
		return func(_x, _z): return y
	var asphalt_strips := []
	for s in strips:
		add_mesh.call(slab_geo.call(XDW, XWW, s.z0, s.z1, flat.call(RTOP), -0.45, {"tile": 1.0}), M.beam)
		add_mesh.call(slab_geo.call(XWE, XDE, s.z0, s.z1, flat.call(RTOP), -0.45, {"tile": 1.0}), M.beam)
		if s.kind == "asphalt":
			add_mesh.call(slab_geo.call(XWW, XWE, s.z0, s.z1, flat.call(RTOP), -0.45, {"tile": 4.0, "sides": {"s": 1, "e": 0, "n": 1, "w": 0}}), M.asphalt)
			asphalt_strips.append(s)
		else:
			var segs := []
			var split := func(a: float, b: float, n: int, green: bool) -> void:
				for i in n:
					segs.append({"a": a + (b - a) * i / n, "b": a + (b - a) * (i + 1) / n, "green": green})
			split.call(XWW, XLW, 2, true)
			split.call(XLW, XLE, 4, false)
			split.call(XLE, XWE, 2, true)
			for sg in segs:
				var m = M.rubberG if sg.green else M.rubber[rng.rint(0, 1)]
				k.boxb(sg.b - sg.a, RTOP - 0.03, s.z1 - s.z0, m, [(sg.a + sg.b) / 2.0, 0.03, (s.z0 + s.z1) / 2.0])
	physics.addWalkBox((XDW + XDE) / 2.0, (ZDS + ZDN) / 2.0, XDE - XDW, ZDS - ZDN, 0, RTOP)
	physics.addBox(XDW - 0.05, (ZFS + ZFN) / 2.0, 0.1, ZFS - ZFN, 0, -1, 2.6)
	physics.addBox(XDE + 0.05, (ZFS + ZFN) / 2.0, 0.1, ZFS - ZFN, 0, -1, 2.6)

	# equipment aprons (concrete, road level)
	var aprons := [
		[XAW, XRW, ZDS, -33.0], [XAW, XDW, ZFS, ZDS],
		[XRE, XAE, ZDS, ZONE.z1], [XDE, XAE, ZFS, ZDS],
		[XAW, XRW, -53.0, ZDN], [XAW, XDW, ZDN, ZFN],
		[XRE, XAE, -53.0, ZDN], [XDE, XAE, ZDN, ZFN],
	]
	for ap in aprons:
		var x0: float = ap[0]
		var x1: float = ap[1]
		var z0: float = ap[2]
		var z1: float = ap[3]
		var nz := maxi(1, int(T.js_round((z1 - z0) / 0.25)))
		var road_side_e := absf(x1 - XRW) < 1e-6 or absf(x1 - XDW) < 1e-6
		var road_side_w := absf(x0 - XRE) < 1e-6 or absf(x0 - XDE) < 1e-6
		add_mesh.call(slab_geo.call(x0, x1, z0, z1, func(_x, z): return prof.call(z) + APR, -0.45,
			{"nz": nz, "tile": 2.0, "sides": {"s": 1, "n": 1, "e": 0 if road_side_e else 1, "w": 0 if road_side_w else 1}}), M.apron)
		var cx := (x0 + x1) / 2.0
		var w := x1 - x0
		var parts := []
		var cuts := []
		for v in [z0, z1, -38.4, -37.4, -36.4, -35.4, -50.6, -49.6, -48.6, -47.6]:
			if v >= z0 and v <= z1:
				cuts.append(v)
		cuts.sort()
		for i in cuts.size() - 1:
			var a: float = cuts[i]
			var b: float = cuts[i + 1]
			if b - a > 1e-3:
				parts.append([a, b])
		for ab in parts:
			var a: float = ab[0]
			var b: float = ab[1]
			var ya: float = prof.call(a)
			var yb: float = prof.call(b)
			if absf(ya - yb) < 0.004:
				physics.addWalkBox(cx, (a + b) / 2.0, w, b - a, 0, maxf(ya, yb) + APR)
			else:
				physics.addWalkRamp(cx, (a + b) / 2.0, w, b - a, 0, ya + APR, yb + APR)

	# road markings (inside the zone)
	ORDER[M.green] = 1
	ORDER[M.white] = 2
	var LIFT := 0.02
	var y_road := func(lift: float) -> Callable:
		return func(_x, z): return prof.call(z) + lift
	var y_deck := func(lift: float) -> Callable:
		return func(_x, _z): return RTOP + lift
	var ZT := -34.7
	var XSL := -14.47
	var XSR := -9.53
	var apS := [ZDS, ZT]
	var apN := [ZONE.z0, ZDN]
	var stripe := func(a: Array, b: Array, w: float, y_fn: Callable, m, n: int = 4):
		var dx: float = b[0] - a[0]
		var dz: float = b[1] - a[1]
		var length := Vector2(dx, dz).length()
		var nx := -dz / length * w / 2.0
		var nzz := dx / length * w / 2.0
		var pos := PackedFloat32Array()
		var uv := PackedFloat32Array()
		var idx := PackedInt32Array()
		for i in n + 1:
			var t := float(i) / n
			var x: float = a[0] + dx * t
			var z: float = a[1] + dz * t
			pos.append_array([x - nx, y_fn.call(x - nx, z - nzz), z - nzz, x + nx, y_fn.call(x + nx, z + nzz), z + nzz])
			uv.append_array([length * t / 1.7, 0, length * t / 1.7, w / 1.7])
			if i < n:
				idx.append_array([i * 2, i * 2 + 1, i * 2 + 2, i * 2 + 1, i * 2 + 3, i * 2 + 2])
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(pos, 3))
		g.set_attribute("uv", T.Attr.new(uv, 2))
		g.set_index(idx)
		g.compute_vertex_normals()
		if g.attributes.normal.get_y(0) < 0:
			var ia := g.index
			for i in range(0, ia.size(), 3):
				var t2 := ia[i + 1]
				ia[i + 1] = ia[i + 2]
				ia[i + 2] = t2
			g.index = ia
			g.compute_vertex_normals()
		var me := T.MeshObj.new(g, m)
		me.cast_shadow = false
		me.receive_shadow = true
		me.render_order = ORDER.get(m, 3)
		ctx.no_outline(me)
		root.add(me)
		return me
	var nz_of := func(a: float, b: float) -> int:
		return maxi(1, int(T.js_round(absf(b - a) / 0.25)))
	var bandW := [XWW, XLW - 0.075]
	var bandE := [XLE + 0.075, XWE]
	for ab in [apS, apN]:
		var a: float = ab[0]
		var b: float = ab[1]
		decal.call(bandW[0], bandW[1], a, b, y_road.call(LIFT), M.green, {"nz": nz_of.call(a, b), "tile": 1.2})
		decal.call(bandE[0], bandE[1], a, b, y_road.call(LIFT), M.green, {"nz": nz_of.call(a, b), "tile": 1.2})
		decal.call(XLW - 0.075, XLW + 0.075, a, b, y_road.call(LIFT + 0.002), M.white, {"nz": nz_of.call(a, b), "tile": 1.7})
		decal.call(XLE - 0.075, XLE + 0.075, a, b, y_road.call(LIFT + 0.002), M.white, {"nz": nz_of.call(a, b), "tile": 1.7})
	stripe.call([XSL, ZONE.z1 + 0.1], [XLW, ZT - 0.02], 0.15, y_road.call(LIFT + 0.002), M.white)
	stripe.call([XSR, ZONE.z1 + 0.1], [XLE, ZT - 0.02], 0.15, y_road.call(LIFT + 0.002), M.white)
	for s in asphalt_strips:
		decal.call(bandW[0], bandW[1], s.z0, s.z1, y_deck.call(0.004), M.green, {"tile": 1.2})
		decal.call(bandE[0], bandE[1], s.z0, s.z1, y_deck.call(0.004), M.green, {"tile": 1.2})
		decal.call(XLW - 0.075, XLW + 0.075, s.z0, s.z1, y_deck.call(0.006), M.white, {"tile": 1.7})
		decal.call(XLE - 0.075, XLE + 0.075, s.z0, s.z1, y_deck.call(0.006), M.white, {"tile": 1.7})
	for gx in [(bandW[0] + bandW[1]) / 2.0, (bandE[0] + bandE[1]) / 2.0]:
		for s in strips:
			decal.call(gx - 0.15, gx + 0.15, s.z0 + 0.01, s.z1 - 0.01, y_deck.call(0.009), M.guide, {"tile": 0.3})
	for zs in [ZSS, ZSN]:
		decal.call(XLW - 0.075, XLE + 0.075, zs - 0.225, zs + 0.225, y_road.call(LIFT + 0.004), M.white, {"nz": 2, "tile": 1.7})
	decal.call(CX - 1.35, CX + 1.35, ZSS + 0.4, ZSS + 2.0, y_road.call(LIFT + 0.003), M.sym, {"rect": "tomare", "mode": "N", "nz": 4, "nx": 2})
	decal.call(CX - 1.35, CX + 1.35, ZSN - 2.0, ZSN - 0.4, y_road.call(LIFT + 0.003), M.sym, {"rect": "tomare", "mode": "S", "nz": 4, "nx": 2})
	var z_wait_s := -36.9
	var z_wait_n := -49.0
	for bb in [bandW, bandE]:
		var b0: float = bb[0]
		var b1: float = bb[1]
		var bc := (b0 + b1) / 2.0
		decal.call(b0, b1, z_wait_s - 0.1, z_wait_s + 0.1, y_road.call(LIFT + 0.004), M.white, {"nz": 1, "tile": 1.7})
		decal.call(bc - 0.45, bc + 0.45, z_wait_s + 0.1, z_wait_s + 0.7, y_road.call(LIFT + 0.004), M.sym, {"rect": "tactile", "mode": "N", "nz": 3})
		decal.call(bc - 0.24, bc + 0.24, -35.95, -35.47, y_road.call(LIFT + 0.005), M.sym, {"rect": "feet", "mode": "N", "nz": 2})
		decal.call(bc - 0.45, bc + 0.45, -35.25, -34.78, y_road.call(LIFT + 0.005), M.sym, {"rect": "tomareSmall", "mode": "N", "nz": 2})
		decal.call(b0, b1, z_wait_n - 0.1, z_wait_n + 0.1, y_road.call(LIFT + 0.004), M.white, {"nz": 1, "tile": 1.7})
		decal.call(bc - 0.45, bc + 0.45, z_wait_n - 0.7, z_wait_n - 0.1, y_road.call(LIFT + 0.004), M.sym, {"rect": "tactile", "mode": "N", "nz": 3})
		decal.call(bc - 0.24, bc + 0.24, -50.53, -50.05, y_road.call(LIFT + 0.005), M.sym, {"rect": "feet", "mode": "S", "nz": 2})
		decal.call(bc - 0.45, bc + 0.45, -51.4, -50.88, y_road.call(LIFT + 0.005), M.sym, {"rect": "tomareSmall", "mode": "S", "nz": 2})
	var on_deck := func(z: float) -> bool:
		return z <= ZDS and z >= ZDN
	var chev := func(xc: float, zc: float, dir: String) -> void:
		var yf: Callable = y_deck.call(0.008) if on_deck.call(zc) else y_road.call(LIFT + 0.006)
		decal.call(xc - 0.27, xc + 0.27, zc - 0.3, zc + 0.3, yf, M.sym, {"rect": "chevron", "mode": dir, "nz": 2})
	var xNB := XLW + 0.3
	var xSB := XLE - 0.3
	for z in [-34.45, -36.25, -37.65, -39.05, -43.0, -46.95]:
		chev.call(xNB, z, "N")
	for z in [-51.6, -49.95, -48.6, -46.95, -43.0, -39.05, -38.05, -34.45]:
		chev.call(xSB, z, "S")
	decal.call(xNB - 0.27, xNB + 0.27, -49.75, -48.65, y_road.call(LIFT + 0.006), M.sym, {"rect": "navi", "mode": "N", "nz": 3})
	decal.call(xSB - 0.27, xSB + 0.27, -37.4, -36.3, y_road.call(LIFT + 0.006), M.sym, {"rect": "navi", "mode": "S", "nz": 3})

	# dynamic part collection
	var dyn := {"lens": [[], []], "arrowE": [], "arrowW": [], "react": [], "_arrows": []}
	var halos := [[], []]
	var react_halos := []
	var lens_geo := Geo.g_sphere(ctx.cache, 16)
	var arrow_geo := Geo.extrude([[-0.1, -0.03], [0.015, -0.03], [0.015, -0.072], [0.108, 0], [0.015, 0.072], [0.015, 0.03], [-0.1, 0.03]], 0.014)
	var hood_geo := Geo.cylinder(0.185, 0.152, 0.17, 16, 1, true, PI / 2.0 + 0.3, PI - 0.6)

	# warning posts
	var lamp_faces := []
	var warning_post := func(o: Dictionary):
		var x: float = o.x
		var z: float = o.z
		var road_side: float = o.roadSide
		var gy: float = prof.call(z)
		var g := T.Group.new()
		g.position = Vector3(x, gy, z)
		g.rotation.y = o.rotY
		root.add(g)
		var kk = ctx.kit(g)
		kk.rbox(0.46, 0.4, 0.46, 0.035, M.concrete, [0, -0.13, 0])
		kk.box(0.26, 0.03, 0.26, M.steelDark, [0, 0.085, 0])
		for bxz in [[-0.09, -0.09], [0.09, -0.09], [-0.09, 0.09], [0.09, 0.09]]:
			kk.cyl(0.014, 0.014, 0.04, M.steel, [bxz[0], 0.11, bxz[1]], null, 6)
		kk.cyl(POST_R, POST_R, POST_H, M.post, [0, POST_H / 2.0 + 0.07, 0], null, 16)
		kk.cyl(POST_R + 0.012, POST_R + 0.012, 0.05, M.ink, [0, POST_H + 0.07, 0], null, 16)
		kk.box(0.07, 0.1, 0.07, M.steelDark, [0, POST_H + 0.14, 0])
		kk.rbox(0.27, 0.25, 0.22, 0.04, M.speaker, [0, POST_H + 0.3, 0])
		for s in [1, -1]:
			kk.box(0.21, 0.17, 0.012, M.grille, [0, POST_H + 0.3, s * 0.112])
			sign_plane.call(kk, "grille", 0.19, 0.15, [0, POST_H + 0.3, s * 0.1185], [0, 0.0 if s > 0 else PI, 0])
		kk.rbox(0.31, 0.035, 0.27, 0.015, M.machCap, [0, POST_H + 0.44, 0])
		var yB := 3.55
		kk.box(0.09, 0.34, 0.07, M.steelDark, [0, yB, 0.085])
		sign_box.call(kk, "buckA", 1.2, 0.18, 0.028, [0, yB, 0.132], [0, 0, 0.6])
		sign_box.call(kk, "buckB", 1.2, 0.18, 0.028, [0, yB, 0.162], [0, 0, -0.6])
		kk.cyl(0.035, 0.035, 0.02, M.steel, [0, yB, 0.182], [PI / 2.0, 0, 0], 10)
		var yI := 2.95
		kk.rbox(0.64, 0.23, 0.2, 0.025, M.housing, [0, yI, 0])
		for s in [1, -1]:
			kk.box(0.66, 0.02, 0.09, M.ink, [0, yI + 0.125, s * 0.125])
			var fg := T.Group.new()
			fg.position = Vector3(0, yI, s * 0.107)
			fg.rotation.y = 0.0 if s > 0 else PI
			g.add(fg)
			for side in [1, -1]:
				var a := T.MeshObj.new(arrow_geo, M.arrowOff)
				a.position = Vector3(side * 0.165, 0, 0)
				a.rotation.z = 0.0 if side > 0 else PI
				fg.add(a)
				dyn._arrows.append(a)
		var yL := 2.45
		kk.cyl(0.028, 0.028, 1.02, M.ink, [0, yL, 0], [0, 0, PI / 2.0], 10)
		kk.box(0.11, 0.17, 0.11, M.ink, [0, yL, 0])
		for pl in [[0, -0.4], [1, 0.4]]:
			var phase: int = pl[0]
			var lx: float = pl[1]
			kk.cyl(0.085, 0.085, 0.13, M.housing, [lx, yL, 0], [PI / 2.0, 0, 0], 14)
			for s in [1, -1]:
				var fg := T.Group.new()
				fg.position = Vector3(lx, yL, s * 0.065)
				fg.rotation.y = 0.0 if s > 0 else PI
				g.add(fg)
				var fk = ctx.kit(fg)
				fk.cyl(0.23, 0.23, 0.02, M.ink, [0, 0, 0.01], [PI / 2.0, 0, 0], 22)
				fk.cyl(0.14, 0.14, 0.03, M.rim, [0, 0, 0.033], [PI / 2.0, 0, 0], 18)
				fk.mesh(hood_geo, M.inkD, [0, 0, 0.105], [PI / 2.0, 0, 0])
				var lens := T.MeshObj.new(lens_geo, M.lensOff)
				lens.scale = Vector3(0.25, 0.25, 0.07)
				lens.position = Vector3(0, 0, 0.05)
				fg.add(lens)
				dyn.lens[phase].append(lens)
				lamp_faces.append({"obj": fg, "phase": phase})
		var yP := 1.92
		if o.main:
			kk.box(0.48, 0.38, 0.016, M.plateBack, [0, yP, POST_R + 0.01])
			sign_plane.call(kk, "namePlate", 0.46, 0.36, [0, yP, POST_R + 0.024])
		else:
			kk.box(0.29, 0.38, 0.016, M.plateBack, [0, yP, POST_R + 0.01])
			sign_plane.call(kk, "tomareMiyo", 0.27, 0.36, [0, yP, POST_R + 0.024])
		for dy in [-0.13, 0.13]:
			kk.box(0.2, 0.025, 0.17, M.steelDark, [0, yP + dy, 0.0])
		var eb := T.Group.new()
		eb.position = Vector3(road_side * (POST_R + 0.068), 1.22, 0)
		eb.rotation.y = road_side * PI / 2.0
		g.add(eb)
		var ek = ctx.kit(eb)
		ek.rbox(0.24, 0.32, 0.12, 0.015, M.emBox, [0, 0, 0])
		sign_plane.call(ek, "emergency", 0.22, 0.3, [0, 0, 0.066])
		ek.cyl(0.045, 0.05, 0.035, M.btnRed, [0, 0.017, 0.075], [PI / 2.0, 0, 0], 16)
		ek.box(0.27, 0.022, 0.16, M.emTop, [0, 0.172, 0.012])
		physics.addCylinder(x, z, 0.14, gy - 0.5, gy + 4.6)
		return g

	# Merges every mesh below group (except skip) into one mesh per material, layer, shadow flags and
	# renderOrder, in the group's local space; plain-colour toon materials bake into vertex colours.
	var VC = mat.toon("#ffffff", {"vertexColors": true})
	var VCD = mat.toon("#ffffff", {"vertexColors": true, "side": "double"})
	var plain_colour := func(m) -> bool:
		return m != null and m.type == "toon" and m.map == null and m.alpha_map == null and not m.transparent and not m.vertex_colors \
			and not m.polygonOffset and not m.alpha_test and m.emissive == Color(0, 0, 0)
	var merge_group := func(group, skip: Array = []) -> Array:
		group.update_matrix_world(true)
		var inv: Transform3D = group.matrix_world.affine_inverse()
		var buckets := {}
		var victims := []
		group.traverse(func(o):
			if not o.is_mesh or o == group or skip.has(o) or o.material is Array:
				return
			var p = o.parent()
			while p and p != group:
				if skip.has(p):
					return
				p = p.parent()
			var src = o.material
			var pc: bool = plain_colour.call(src)
			var target = (VCD if src.side == "double" else VC) if pc else src
			var key := "%d|%d|%d%d|%d" % [target.get_instance_id(), o.layer, 1 if o.cast_shadow else 0, 1 if o.receive_shadow else 0, o.render_order]
			if not buckets.has(key):
				buckets[key] = {"target": target, "geos": [], "proto": o}
			var tmp: Transform3D = inv * o.matrix_world
			var g: T.Geometry = o.geometry.clone()
			if not g.has_attribute("normal"):
				g.compute_vertex_normals()
			for a in g.attributes.keys():
				if a != "position" and a != "normal" and a != "uv":
					g.delete_attribute(a)
			var n: int = g.attributes.position.count()
			if not g.has_attribute("uv"):
				var uv := PackedFloat32Array()
				uv.resize(n * 2)
				g.set_attribute("uv", T.Attr.new(uv, 2))
			if not g.indexed:
				var ix := PackedInt32Array()
				ix.resize(n)
				for i in n:
					ix[i] = i
				g.set_index(ix)
			g.clear_groups()
			g.apply_matrix4(tmp)
			if tmp.basis.determinant() < 0:
				var ia := g.index
				for i in range(0, ia.size(), 3):
					var t := ia[i + 1]
					ia[i + 1] = ia[i + 2]
					ia[i + 2] = t
				g.index = ia
			if target == VC or target == VCD:
				var col := PackedFloat32Array()
				col.resize(n * 3)
				var c: Color = src.color
				for i in n:
					col[i * 3] = c.r
					col[i * 3 + 1] = c.g
					col[i * 3 + 2] = c.b
				g.set_attribute("color", T.Attr.new(col, 3))
			buckets[key].geos.append(g)
			victims.append(o))
		for o in victims:
			o.parent().remove(o)
		var out := []
		for b in buckets.values():
			var me := T.MeshObj.new(Geo.merge_geometries(b.geos, false) if b.geos.size() > 1 else b.geos[0], b.target)
			me.cast_shadow = b.proto.cast_shadow
			me.receive_shadow = b.proto.receive_shadow
			me.layer = b.proto.layer
			me.render_order = b.proto.render_order
			group.add(me)
			out.append(me)
		return out

	# barrier machines and arms
	var arms := []
	var barrier := func(o: Dictionary) -> void:
		var mx: float = o.mx
		var mz: float = o.mz
		var face_z: float = o.faceZ
		var dir_x: float = o.dirX
		var length: float = o.len
		var gy: float = prof.call(mz)
		var g = k.group([mx, gy, mz])
		var kk = ctx.kit(g)
		kk.rbox(0.6, 0.36, 0.54, 0.035, M.concrete, [0, -0.11, 0])
		kk.boxb(0.44, 1.0, 0.4, M.mach, [0, 0.06, 0])
		kk.rbox(0.48, 0.07, 0.44, 0.02, M.machCap, [0, 1.09, 0])
		kk.cyl(0.115, 0.115, 0.1, M.housing, [0, 0.92, face_z * 0.245], [PI / 2.0, 0, 0], 16)
		kk.box(0.3, 0.2, 0.012, M.steelDark, [0, 0.55, -face_z * 0.207])
		physics.addBox(mx, mz, 0.62, 0.58, 0, gy - 0.5, gy + 1.15)
		var pivot := T.Group.new()
		pivot.position = Vector3(mx, gy + 0.92, mz + face_z * 0.33)
		pivot.rotation.y = 0.0 if dir_x > 0 else PI
		var rot := T.Group.new()
		pivot.add(rot)
		var ak = ctx.kit(rot)
		ak.box(0.56, 0.13, 0.07, M.housing, [0.1, 0, 0])
		ak.cyl(0.058, 0.058, 0.36, M.steelDark, [0.32, 0, 0], [0, 0, PI / 2.0], 12)
		var tube_len := length - 0.4
		var n_band := int(T.js_round(tube_len / 0.45))
		var rA := 0.047
		var rB := 0.033
		for i in n_band:
			var f0 := float(i) / n_band
			var f1 := float(i + 1) / n_band
			var l := tube_len / n_band
			var seg := Geo.cylinder(rA + (rB - rA) * f1, rA + (rB - rA) * f0, l, 12, 1, true)
			ak.mesh(seg, M.ink if i % 2 else M.yellow, [0.4 + tube_len * (f0 + f1) / 2.0, 0, 0], [0, 0, -PI / 2.0])
		ak.cyl(rA, rA, 0.01, M.ink, [0.405, 0, 0], [0, 0, PI / 2.0], 12)
		ak.sphere(0.04, M.tipRed, [length, 0, 0], 10)
		var arm_lens := []
		var arm_halo := []
		for f in [0.3, 0.58, 0.86]:
			var ax: float = 0.4 + tube_len * f
			ak.rbox(0.085, 0.085, 0.1, 0.02, M.housing, [ax, 0.0, 0])
			for sz in [1, -1]:
				var l := T.MeshObj.new(lens_geo, M.lensOff)
				l.scale = Vector3(0.06, 0.06, 0.02)
				l.position = Vector3(ax, 0, sz * 0.051)
				l.update_matrix()
				arm_lens.append(l)
				arm_halo.append({"c": Vector3(ax, 0, sz * 0.06), "n": Vector3(0, 0, sz), "size": 0.26})
		var lgs := []
		for l in arm_lens:
			lgs.append(l.geometry.clone().apply_matrix4(l.matrix))
		var lens_mesh := T.MeshObj.new(Geo.merge_geometries(lgs, false), M.lensOff)
		lens_mesh.cast_shadow = false
		rot.add(lens_mesh)
		var halo_mesh = Glow.make_halo_mesh(ctx, arm_halo, "#ff4a34", {"intensity": 1.4, "streak": 0.5})
		rot.add(halo_mesh)
		ak.box(0.44, 0.075, 0.05, M.housing, [-0.26, 0, 0])
		ak.rbox(0.3, 0.26, 0.17, 0.035, M.weight, [-0.55, 0, 0])
		merge_group.call(rot, [lens_mesh, halo_mesh])
		ctx.add(pivot)
		var cz := mz + face_z * 0.33
		arms.append({"rot": rot, "lensMesh": lens_mesh, "haloMesh": halo_mesh, "box": {"cx": mx + dir_x * (length / 2.0 + 0.1), "cz": cz, "w": length, "d": 0.32, "rotY": 0, "y0": gy - 0.5, "y1": gy + 1.45}})

	warning_post.call({"x": -15.85, "z": -36.6, "rotY": 0.0, "main": true, "roadSide": 1.0})
	warning_post.call({"x": -8.15, "z": -36.7, "rotY": 0.0, "main": false, "roadSide": -1.0})
	warning_post.call({"x": -8.15, "z": -49.3, "rotY": PI, "main": true, "roadSide": 1.0})
	warning_post.call({"x": -15.85, "z": -49.2, "rotY": PI, "main": false, "roadSide": -1.0})
	barrier.call({"mx": -15.85, "mz": -37.35, "faceZ": -1.0, "dirX": 1.0, "len": 6.9})
	barrier.call({"mx": -8.15, "mz": -48.55, "faceZ": 1.0, "dirX": -1.0, "len": 6.9})

	# control cabinet, relay box, reaction lamps
	var cabinet := func(o: Dictionary) -> void:
		var x: float = o.x
		var z: float = o.z
		var rot_y: float = o.rotY
		var w: float = o.w
		var h: float = o.h
		var d: float = o.d
		var gy: float = prof.call(z)
		var g = k.group([x, gy, z], rot_y)
		var kk = ctx.kit(g)
		kk.rbox(w + 0.12, 0.3, d + 0.12, 0.025, M.concrete, [0, -0.07, 0])
		kk.rbox(w, h, d, 0.03, M.cab, [0, 0.08 + h / 2.0, 0])
		sign_plane.call(kk, o.face, w - 0.06, h - 0.12, [0, 0.08 + h / 2.0 - 0.01, d / 2.0 + 0.006])
		kk.rbox(w + 0.1, 0.06, d + 0.1, 0.02, M.cabRoof, [0, 0.08 + h + 0.03, 0])
		kk.box(0.03, 0.14, 0.035, M.steelDark, [0.06, 0.08 + h * 0.55, d / 2.0 + 0.018])
		kk.cyl(0.035, 0.035, 0.3, M.steelDark, [-w * 0.3, -0.02, -d / 2.0 - 0.05], null, 8)
		var along := absf(cos(rot_y)) > 0.5
		physics.addBox(x, z, w + 0.1 if along else d + 0.1, d + 0.1 if along else w + 0.1, 0, gy - 0.5, gy + h + 0.2)
	cabinet.call({"x": -16.42, "z": -50.55, "rotY": PI / 2.0, "w": 0.82, "h": 1.3, "d": 0.5, "face": "cabinet"})
	cabinet.call({"x": -7.58, "z": -38.12, "rotY": -PI / 2.0, "w": 0.55, "h": 0.82, "d": 0.38, "face": "relay"})

	var reaction_lamp := func(o: Dictionary) -> void:
		var x: float = o.x
		var z: float = o.z
		var gy: float = prof.call(z)
		var g = k.group([x, gy, z], o.rotY)
		var kk = ctx.kit(g)
		kk.rbox(0.3, 0.3, 0.3, 0.03, M.concrete, [0, -0.08, 0])
		kk.cyl(0.04, 0.04, 2.1, M.steel, [0, 1.12, 0], null, 10)
		kk.rbox(0.3, 0.3, 0.12, 0.03, M.ink, [0, 2.2, 0.02])
		kk.cyl(0.095, 0.095, 0.03, M.rim, [0, 2.2, 0.085], [PI / 2.0, 0, 0], 16)
		kk.mesh(hood_geo, M.inkD, [0, 2.2, 0.16], [PI / 2.0, 0, 0], [0.75, 0.8, 0.75])
		var fg := T.Group.new()
		fg.position = Vector3(0, 2.2, 0.1)
		g.add(fg)
		var lens := T.MeshObj.new(lens_geo, M.reactOff)
		lens.scale = Vector3(0.16, 0.16, 0.05)
		fg.add(lens)
		dyn.react.append(lens)
		react_halos.append(fg)
		physics.addCylinder(x, z, 0.1, gy - 0.5, gy + 2.4)
	reaction_lamp.call({"x": -7.42, "z": -38.8, "rotY": PI / 2.0})
	reaction_lamp.call({"x": -16.55, "z": -47.22, "rotY": -PI / 2.0})

	# fences and signs
	var FH := 1.2
	var on_apron := func(x: float, z: float) -> bool:
		return x >= XAW - 1e-3 and x <= XAE + 1e-3 and z <= -33.0 and z >= -53.0
	var fence_ground := func(x: float, z: float) -> float:
		return prof.call(z) + APR if on_apron.call(x, z) else L.height_at(x, z)
	var fence := func(pts: Array) -> void:
		for s in pts.size() - 1:
			var ax: float = pts[s][0]
			var az: float = pts[s][1]
			var bx: float = pts[s + 1][0]
			var bz: float = pts[s + 1][1]
			var length := Vector2(bx - ax, bz - az).length()
			var n := maxi(1, int(ceilf(length / 2.0 - 0.01)))
			var P0 := []
			for i in n + 1:
				var t := float(i) / n
				var x := ax + (bx - ax) * t
				var z := az + (bz - az) * t
				P0.append(Vector3(x, fence_ground.call(x, z), z))
			for i in n + 1:
				if s > 0 and i == 0:
					continue
				var p: Vector3 = P0[i]
				k.cyl(0.034, 0.034, FH + 0.2, M.fence, [p.x, p.y + (FH + 0.2) / 2.0 - 0.12, p.z], null, 8)
				k.sphere(0.042, M.fence, [p.x, p.y + FH + 0.1, p.z], 8)
			for i in n:
				var a: Vector3 = P0[i]
				var b: Vector3 = P0[i + 1]
				pipe.call(Vector3(a.x, a.y + FH, a.z), Vector3(b.x, b.y + FH, b.z), 0.024, M.fence)
				pipe.call(Vector3(a.x, a.y + 0.1, a.z), Vector3(b.x, b.y + 0.1, b.z), 0.02, M.fence)
				var dab := a.distance_to(b)
				var dl := dab - 0.08
				var ux := (b.x - a.x) / dab
				var uz := (b.z - a.z) / dab
				var a2 := Vector3(a.x + ux * 0.04, a.y, a.z + uz * 0.04)
				var b2 := Vector3(b.x - ux * 0.04, b.y, b.z - uz * 0.04)
				var y0 := 0.12
				var y1 := FH - 0.02
				var tile := 0.14
				var gq := T.Geometry.new()
				gq.set_attribute("position", T.Attr.new(PackedFloat32Array([a2.x, a2.y + y0, a2.z, b2.x, b2.y + y0, b2.z, b2.x, b2.y + y1, b2.z, a2.x, a2.y + y1, a2.z]), 3))
				gq.set_attribute("uv", T.Attr.new(PackedFloat32Array([0, 0, dl / tile, 0, dl / tile, (y1 - y0) / tile, 0, (y1 - y0) / tile]), 2))
				gq.set_index([0, 1, 2, 0, 2, 3])
				gq.compute_vertex_normals()
				var mq = add_mesh.call(gq, M.fenceMesh, true)
				ctx.no_outline(mq)
			var mx := (ax + bx) / 2.0
			var mz := (az + bz) / 2.0
			physics.addBox(mx, mz, 0.12, length + 0.08, atan2(bx - ax, bz - az), -1, maxf(fence_ground.call(ax, az), fence_ground.call(bx, bz)) + FH + 0.15)
	var RWF = ctx.services.get("railway", {}).get("fences")
	var zRS: float = RWF.southZ if RWF is Dictionary and (RWF.get("southZ") is float) else -33.8
	var zRN: float = RWF.northZ if RWF is Dictionary and (RWF.get("northZ") is float) else -52.2
	var xRW: float = -17.5
	if RWF is Dictionary and RWF.get("ranges") is Array and RWF.ranges.size() > 0 and RWF.ranges[0] is Array and RWF.ranges[0].size() > 1:
		xRW = RWF.ranges[0][1]
	var stub_x := maxf(xRW + 0.05, ZONE.x0 - 0.6)
	fence.call([[stub_x, zRS - 0.05], [XAW + 0.05, zRS - 0.05], [XAW + 0.05, ZFS], [XDW - 0.05, ZFS]])
	fence.call([[XAE - 0.05, ZONE.z1 - 0.05], [XAE - 0.05, ZFS], [XDE + 0.05, ZFS]])
	fence.call([[stub_x, zRN + 0.05], [XAW + 0.05, zRN + 0.05], [XAW + 0.05, ZFN], [XDW - 0.05, ZFN]])
	fence.call([[XAE - 0.05, ZONE.z0 + 0.05], [XAE - 0.05, ZFN], [XDE + 0.05, ZFN]])
	var plate := func(x: float, z: float, rot_y: float, w: float, h: float, m: String, y_off: float) -> void:
		var gy: float = prof.call(z)
		var g = k.group([x, gy, z], rot_y)
		var kk = ctx.kit(g)
		kk.box(w + 0.02, h + 0.02, 0.012, M.plateBack, [0, y_off, 0])
		sign_plane.call(kk, m, w, h, [0, y_off, 0.012])
	plate.call(XAW + 0.1, -34.95, PI / 2.0, 0.5, 0.31, "chui", 0.78)
	plate.call(XAE - 0.1, -34.95, -PI / 2.0, 0.5, 0.31, "chui", 0.78)
	plate.call(XAW + 0.1, -51.05, PI / 2.0, 0.5, 0.31, "chui", 0.78)
	plate.call(XAE - 0.1, -51.05, -PI / 2.0, 0.5, 0.31, "chui", 0.78)
	plate.call(-16.2, ZFS + 0.05, 0.0, 0.45, 0.28, "kinshi", 0.72)
	plate.call(-7.8, ZFS + 0.05, 0.0, 0.45, 0.28, "kinshi", 0.72)
	plate.call(-16.2, ZFN - 0.05, PI, 0.45, 0.28, "kinshi", 0.72)
	plate.call(-7.8, ZFN - 0.05, PI, 0.45, 0.28, "kinshi", 0.72)

	# weeds at the fence feet and apron cracks
	var grass_geo := Geo.g_plane(ctx.cache)
	var tuft := func(x: float, z: float, y: float, s: float) -> void:
		for i in 2:
			var me := T.MeshObj.new(grass_geo, M.grass)
			me.scale = Vector3(s, s * 0.8, 1)
			me.position = Vector3(x, y + s * 0.4 - 0.02, z)
			me.rotation.y = rng.f() * PI + i * PI / 2.0
			me.cast_shadow = false
			me.receive_shadow = true
			ctx.no_outline(me)
			root.add(me)
	for i in 26:
		var corner := i % 4
		var west := corner == 0 or corner == 2
		var south := corner < 2
		var x: float = XAW + 0.12 + rng.f() * 0.25 if west else XAE - 0.12 - rng.f() * 0.25
		var z: float = ZFS + 0.2 + rng.f() * (ZONE.z1 - ZFS - 0.4) if south else ZFN - 0.2 - rng.f() * (ZFN - ZONE.z0 - 0.4)
		tuft.call(x, z, prof.call(z), 0.22 + rng.f() * 0.2)
	for xz in [[-15.62, -36.3], [-15.55, -38.1], [-8.4, -36.95], [-8.45, -48.9], [-15.62, -49.6], [-16.1, -39.0], [-7.9, -47.0], [-16.7, -51.4], [-7.35, -38.55]]:
		tuft.call(xz[0], xz[1], prof.call(xz[1]), 0.2 + rng.f() * 0.12)

	# finalize dynamic parts
	root.update_matrix_world(true)
	var bake := func(list: Array):
		var geos := []
		for m in list:
			var g: T.Geometry = m.geometry.clone()
			g.apply_matrix4(m.matrix_world)
			for a in g.attributes.keys():
				if a != "position" and a != "normal" and a != "uv":
					g.delete_attribute(a)
			if not g.indexed:
				var n: int = g.attributes.position.count()
				var ix := PackedInt32Array()
				ix.resize(n)
				for i in n:
					ix[i] = i
				g.set_index(ix)
			geos.append(g)
		for m in list:
			if m.parent():
				m.parent().remove(m)
		return Geo.merge_geometries(geos, false) if geos.size() else null
	for a in dyn._arrows:
		var d: Vector3 = (a.matrix_world.basis * Vector3(1, 0, 0)).normalized()
		(dyn.arrowE if d.x > 0 else dyn.arrowW).append(a)
	for f in lamp_faces:
		var c: Vector3 = f.obj.matrix_world * Vector3(0, 0, 0.07)
		var n: Vector3 = (f.obj.matrix_world.basis * Vector3(0, 0, 1)).normalized()
		halos[f.phase].append({"c": c, "n": n, "size": 0.55})
	var react_items := []
	for fg in react_halos:
		react_items.append({"c": fg.matrix_world * Vector3(0, 0, 0.05), "n": (fg.matrix_world.basis * Vector3(0, 0, 1)).normalized(), "size": 0.32})
	var dyn_mesh := func(geo, m):
		var me := T.MeshObj.new(geo, m)
		me.cast_shadow = false
		me.receive_shadow = false
		ctx.add(me)
		return me
	var lens_meshes := [dyn_mesh.call(bake.call(dyn.lens[0]), M.lensOff), dyn_mesh.call(bake.call(dyn.lens[1]), M.lensOff)]
	var arrow_e = dyn_mesh.call(bake.call(dyn.arrowE), M.arrowOff)
	var arrow_w = dyn_mesh.call(bake.call(dyn.arrowW), M.arrowOff)
	var react_mesh = dyn_mesh.call(bake.call(dyn.react), M.reactOff)
	var halo_meshes := []
	for h in halos:
		halo_meshes.append(ctx.add(Glow.make_halo_mesh(ctx, h, "#ff4a34", {"intensity": 1.7, "streak": 1.0})))
	var cone_meshes := []
	for h in halos:
		var items := []
		for it in h:
			items.append({"c": it.c + it.n * 0.02, "n": it.n})
		cone_meshes.append(ctx.add(Glow.make_cone_mesh(ctx, items, "#ff5a40", {"length": 1.1, "r0": 0.12, "r1": 0.3, "intensity": 1.0})))
	var react_halo = ctx.add(Glow.make_halo_mesh(ctx, react_items, "#fff0d0", {"intensity": 1.2, "streak": 0.6}))

	merge_group.call(root)

	# state: rail service or the timetable-derived demo cycle
	var PER: float = L.TRAIN.get("period", 120.0)
	var WIN := [{"t0": 5.5, "t1": 27.5, "west": true}, {"t0": 37.5, "t1": 59.5, "west": false}]
	var LOWER_DELAY := 3.0
	var LOWER_T := 5.0
	var RAISE_T := 4.0
	var demo_at := func(t: float) -> Dictionary:
		var tm := fmod(fmod(t, PER) + PER, PER)
		var base := t - tm
		for w in WIN:
			if tm >= w.t0 and tm < w.t1:
				return {"active": true, "fromWest": w.west, "fromEast": not w.west, "down": _ease(clamp01((tm - w.t0 - LOWER_DELAY) / LOWER_T))}
		var best := -1e9
		var bw: Dictionary = WIN[0]
		for w in WIN:
			var te: float = base + w.t1
			if te > t:
				te -= PER
			if te > best:
				best = te
				bw = w
		var d0 := _ease(clamp01((bw.t1 - bw.t0 - LOWER_DELAY) / LOWER_T))
		return {"active": false, "fromWest": false, "fromEast": false, "down": d0 * (1.0 - _ease(clamp01((t - best) / RAISE_T)))}
	var S := {"active": false, "tOn": -1e9, "tOff": -1e9, "dOn": 0.0, "d0": 0.0, "lastT": null}
	var svc_down := func(t: float) -> float:
		if S.active:
			return S.dOn + (1.0 - S.dOn) * _ease(clamp01((t - S.tOn - LOWER_DELAY) / LOWER_T))
		return S.d0 * (1.0 - _ease(clamp01((t - S.tOff) / RAISE_T)))
	var svc_at := func(rail: Dictionary, t: float) -> Dictionary:
		var act: bool = bool(rail.crossingActive.call(CX))
		var ap = rail.crossingApproach.call(CX) if rail.get("crossingApproach") is Callable else null
		if S.lastT != null and t < S.lastT - 0.5:
			S.active = false
			S.tOff = -1e9
			S.d0 = 0.0
		if act and not S.active:
			S.dOn = svc_down.call(t)
			S.active = true
			S.tOn = t
		elif not act and S.active:
			S.d0 = svc_down.call(t)
			S.active = false
			S.tOff = t
		S.lastT = t
		return {"active": act, "fromWest": ap is Dictionary and bool(ap.get("fromWest")), "fromEast": ap is Dictionary and bool(ap.get("fromEast")), "down": svc_down.call(t)}

	var UP := 1.53
	var state := {"x": CX, "zone": ZONE, "active": false, "barrierDown": 0.0, "fromWest": false, "fromEast": false}
	ctx.services["crossing"] = state

	physics.addDynamic(func(): return arms.map(func(a): return a.box) if state.barrierDown > 0.55 else [])

	ctx.on_update(func(_dt, t):
		var rail = ctx.services.get("rail")
		var st: Dictionary = svc_at.call(rail, t) if rail is Dictionary and rail.get("crossingActive") is Callable else demo_at.call(t)
		state.active = st.active
		state.fromWest = st.fromWest
		state.fromEast = st.fromEast
		var dn := clamp01(st.down)
		state.barrierDown = dn
		var ph := posmod(int(floorf(t / 0.6)), 2)
		for i in 2:
			var on: bool = st.active and ph == i
			lens_meshes[i].material = M.lensOn if on else M.lensOff
			halo_meshes[i].material.uniforms.uOn.value = 1.0 if on else 0.0
			cone_meshes[i].material.uniforms.uOn.value = 1.0 if on else 0.0
		arrow_e.material = M.arrowOn if st.active and st.fromWest else M.arrowOff
		arrow_w.material = M.arrowOn if st.active and st.fromEast else M.arrowOff
		react_mesh.material = M.reactOn if st.active else M.reactOff
		react_halo.material.uniforms.uOn.value = 1.0 if st.active else 0.0
		var ang := (1.0 - dn) * UP - dn * 0.012
		var arm_on: bool = st.active and dn > 0.02 and ph == 0
		for a in arms:
			a.rot.rotation.z = ang
			a.lensMesh.material = M.lensOn if arm_on else M.lensOff
			a.haloMesh.material.uniforms.uOn.value = 1.0 if arm_on else 0.0)
