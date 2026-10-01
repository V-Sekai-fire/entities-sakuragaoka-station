# plaza/ground.js: paving (0.5 m tiles, world UVs), granite border bands, the bike-area paving and
# lines, curbs along R2 and R3 with lowered cuts, tactile paving, drain grates, a decorative manhole,
# the inlay around the clock pillar, the taxi marking, replaced tiles and dust stains.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")
const U = preload("res://addons/sakuragaoka_station/world/plaza/util.gd")


static func build_ground(ctx, root, TX: Dictionary, S: Dictionary, P: Dictionary) -> void:
	var mat = ctx.mat
	var physics = ctx.physics
	var g := T.Group.new()
	g.name = "plaza-ground"
	root.add(g)
	var Y: float = P.yPave
	var r: Rng = ctx.rng("plaza-ground")
	var flat := func(geo, m): return U.put(g, geo, m, [0, 0, 0], null, {"cast": false})

	# ---------------------------------------------------------------- main tile field
	var tiles = mat.toon("#ffffff", {"map": TX.tiles, "paint": 0.08})
	var outer := [[-8.75, -5.5], [26.0, -5.5], [26.0, -25.0], [14.6, -25.0], [14.6, -19.9], [-4.6, -19.9], [-4.6, -25.0], [-8.75, -25.0]]
	var b: Dictionary = P.bikeArea
	var holes := [U.circle_pts(P.tree.x, P.tree.z, P.circleR + 0.02, 72), U.rect(b.x0, b.z0, b.x1, b.z1)]
	flat.call(U.flat_shape(outer, holes, Y, func(x, z): return [x, -z]), tiles)

	# bike-area paving (same tiles, darker tint) and white lines
	flat.call(U.flat_shape(U.rect(b.x0, b.z0, b.x1, b.z1), [], Y, func(x, z): return [x + 0.25, -z]), mat.toon("#d3d4cf", {"map": TX.tiles, "paint": 0.07}))
	var line_m = mat.decal("#ecebe4", {"paint": 0.02, "depthWrite": true})
	var line := func(x0: float, z0: float, x1: float, z1: float):
		var m = U.put(g, Geo.g_plane(ctx.cache), line_m, [(x0 + x1) / 2.0, Y + 0.004, (z0 + z1) / 2.0], [-PI / 2.0, 0, 0], {"cast": false})
		m.scale = Vector3(x1 - x0, z1 - z0, 1)
		return m
	line.call(b.x0 + 0.1, b.z1 - 0.18, b.x1 - 0.1, b.z1 - 0.1)
	line.call(b.x0 + 0.1, b.z0 + 0.1, b.x1 - 0.1, b.z0 + 0.18)
	line.call(b.x0 + 0.1, b.z0 + 0.1, b.x0 + 0.18, b.z1 - 0.1)
	for row in ctx.L.PLAZA.bikeRows:
		var x: float = row.x0 - 0.375
		while x <= row.x1 + 0.376:
			line.call(x - 0.03, row.z - 0.2, x + 0.03, row.z + 0.85)
			x += row.step

	# ---------------------------------------------------------------- granite bands
	var gran = mat.toon("#ffffff", {"map": TX.granite, "paint": 0.05})
	flat.call(U.flat_shape(U.rect(-9.05, -5.5, 26, -5.2), [], Y, func(x, z): return [x, -5.2 - z]), gran)
	flat.call(U.flat_shape(U.rect(-9.05, -25, -8.75, -5.5), [], Y, func(x, z): return [z, x + 9.05]), gran)
	flat.call(U.flat_shape(U.rect(-4.6, -20.5, 14.6, -19.9), [], Y, func(x, z): return [x, -19.9 - z]), gran)
	flat.call(U.flat_shape(U.rect(-4.6, -25, -4.0, -20.5), [], Y, func(x, z): return [z, x + 4.6]), gran)
	flat.call(U.flat_shape(U.rect(14.0, -25, 14.6, -20.5), [], Y, func(x, z): return [z, 14.6 - x]), gran)

	# ---------------------------------------------------------------- curbs (0.6 m stones, lowered at cuts)
	var curb_mats := []
	for c in ["#ffffff", "#f3f1ec", "#e8e7e1"]:
		curb_mats.append(mat.toon(c, {"map": TX.curb, "paint": 0.05}))
	var TOP := 0.1
	var LOW := 0.04
	var CW: float = P.curbW
	var run_x := func(x0: float, x1: float, zc: float, top: float) -> void:
		var n := maxi(1, int(T.js_round((x1 - x0) / 0.6)))
		var sl := (x1 - x0) / n
		for i in n:
			var h := top + 0.03
			U.put(g, U.box_uv(sl - 0.006, h, CW, 1), curb_mats[r.rint(0, 2)], [x0 + sl * (i + 0.5), h / 2.0 - 0.03, zc])
		physics.addWalkBox((x0 + x1) / 2.0, zc, x1 - x0, CW, 0, top)
	var run_z := func(z0: float, z1: float, xc: float, top: float) -> void:
		var n := maxi(1, int(T.js_round((z1 - z0) / 0.6)))
		var sl := (z1 - z0) / n
		for i in n:
			var h := top + 0.03
			U.put(g, U.box_uv(CW, h, sl - 0.006, 1), curb_mats[r.rint(0, 2)], [xc, h / 2.0 - 0.03, z0 + sl * (i + 0.5)])
		physics.addWalkBox(xc, (z0 + z1) / 2.0, CW, z1 - z0, 0, top)
	var zc3 := -5.0 - CW / 2.0
	var xc2 := -9.25 + CW / 2.0
	var cut_x := -9.25
	for cc in P.curbCutsR3:
		run_x.call(cut_x, cc[0], zc3, TOP)
		run_x.call(cc[0], cc[1], zc3, LOW)
		cut_x = cc[1]
	run_x.call(cut_x, 26.0, zc3, TOP)
	var cut_z := -25.0
	for cc in P.curbCutsR2:
		run_z.call(cut_z, cc[0], xc2, TOP)
		run_z.call(cc[0], cc[1], xc2, LOW)
		cut_z = cc[1]
	run_z.call(cut_z, -5.2, xc2, TOP)

	# ---------------------------------------------------------------- tactile paving (raised 12 mm yellow blocks)
	var tac_m := {"dots": mat.toon("#ffffff", {"map": TX.tacDots, "paint": 0.03}), "v": mat.toon("#ffffff", {"map": TX.tacBarsV, "paint": 0.03}),
		"u": mat.toon("#ffffff", {"map": TX.tacBarsU, "paint": 0.03})}
	for t in P.tactile:
		var w: float = t[2] - t[0]
		var d: float = t[3] - t[1]
		U.put(g, U.box_uv(w, 0.012, d, 1), tac_m[t[4]], [(t[0] + t[2]) / 2.0, Y + 0.006 - 0.001, (t[1] + t[3]) / 2.0], null, {"cast": false})

	# ---------------------------------------------------------------- drain grates and a decorative manhole
	var grate_m = mat.toon("#ffffff", {"map": S.grate, "paint": 0.03})
	for gr in P.grates:
		U.put(g, U.box_uv(0.44, 0.006, 0.3, 1), grate_m, [gr[0], Y + 0.002, gr[1]], null, {"cast": false})
	var mh := T.MeshObj.new(Geo.cylinder(0.33, 0.33, 0.012, 32), [mat.toon("#7a797d"), mat.toon("#ffffff", {"map": S.manhole, "paint": 0.03}), mat.toon("#7a797d")])
	mh.position = Vector3(P.manhole.x, Y + 0.005, P.manhole.z)
	mh.rotation.y = 0.4
	mh.receive_shadow = true
	g.add(mh)
	ctx.no_batch(mh)

	# ---------------------------------------------------------------- sakura-flower inlay around the clock pillar
	var inlay = U.put(g, Geo.g_plane(ctx.cache), mat.decal("#ffffff", {"map": TX.inlay, "alphaTest": 0.5, "transparent": false, "depthWrite": true, "paint": 0.04}),
		[P.inlay.x, Y + 0.003, P.inlay.z], [-PI / 2.0, 0, 0.12], {"cast": false})
	inlay.scale = Vector3(P.inlay.d, P.inlay.d, 1)

	# ---------------------------------------------------------------- taxi boarding position marking
	var tx = ctx.tex.draw(256, 128, null, {"key": "plaza-taxi-mark"})
	var taxi = U.put(g, Geo.g_plane(ctx.cache), mat.decal("#ffffff", {"map": tx, "opacity": 0.85}), [P.taxiMark.x, Y + 0.004, P.taxiMark.z], [-PI / 2.0, 0, PI], {"cast": false})
	taxi.scale = Vector3(1.1, 0.55, 1)

	# ---------------------------------------------------------------- replaced tiles (slightly different batch colour)
	var patch_m := [mat.decal("#b9bab4", {"transparent": true, "opacity": 0.45}), mat.decal("#d8d2c2", {"transparent": true, "opacity": 0.4})]
	for pt in P.patches:
		var px: float = pt[0]
		var pz: float = pt[1]
		for i in int(pt[2]):
			for j in int(pt[3]):
				if r.chance(0.18):
					continue
				var cx := floorf(px * 2.0) / 2.0 + 0.25 + i * 0.5
				var cz := floorf(pz * 2.0) / 2.0 + 0.25 + j * 0.5
				var m = U.put(g, Geo.g_plane(ctx.cache), patch_m[pt[4]], [cx, Y + 0.002, cz], [-PI / 2.0, 0, 0], {"cast": false})
				m.scale = Vector3(0.47, 0.47, 1)

	# ---------------------------------------------------------------- soft dust / wear stains (decals)
	var dust_m = mat.decal("#8a8477", {"alphaMap": TX.dust, "opacity": 0.32})
	var wear_m = mat.decal("#9b968a", {"alphaMap": TX.dust, "opacity": 0.22})
	for st in P.stains:
		var y := Y + 0.003 + r.range(0, 0.002)
		var rz := r.f() * 6.0
		var m = U.put(g, Geo.g_plane(ctx.cache), wear_m if st[3] else dust_m, [st[0], y, st[1]], [-PI / 2.0, 0, rz], {"cast": false})
		var s: float = st[2]
		m.scale = Vector3(s, s * r.range(0.6, 1.0), 1)
		m.render_order = 1
