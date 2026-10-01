# station/yards.js: the side yard (station garden with brick beds and shrubs, a retired-wheelset
# monument, the public toilet block, a drinking fountain, a tool shed and the staff bicycle shed),
# the low west yard, and the weeds and low shrubs growing outside both platform fences.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")


static func build_yards(A) -> void:
	var ctx = A.ctx
	var k = A.k
	var U = A.U
	var M: Dictionary = A.M
	var P = A.P
	var L = A.L
	var r: Rng = ctx.rng("station-yards")
	var F = A.atlases.FOL
	var C = U.cards()
	var azalea = ctx.mat.toon("#f0aac8", {"paint": 0.08})
	var azalea_deep = ctx.mat.toon("#e493b6", {"paint": 0.08})
	var wheel_red = ctx.mat.toon("#94504a", {"paint": 0.05})
	var hose_green = ctx.mat.toon("#4f8a5c", {"paint": 0.03})
	var bucket_blue = ctx.mat.toon("#4f86c0", {"paint": 0.03})
	var tile_low = ctx.mat.toon("#a9c6b4", {"paint": 0.05})
	var tile_in = ctx.mat.toon("#7f958b", {"paint": 0.04})
	var floor_dark = ctx.mat.toon("#8f9690", {"paint": 0.04})

	## cloud-like bush: a big core lobe and 3-5 smaller lobes on a dome; bloom colours the upper lobes
	var bush := func(x: float, z: float, s: float, m, bloom) -> void:
		var yb: float = L.height_at(x, z)
		var core = k.sphere(s * 0.78, m, [x, yb + s * 0.5, z], 8)
		core.scale.y *= 0.8
		var n := 3 + floori(r.f() * 3.0)
		var a0 := r.f() * PI * 2.0
		for i in n:
			var a := a0 + i * PI * 2.0 / n + (r.f() - 0.5) * 0.5
			var d := s * (0.5 + r.f() * 0.15)
			var rr := s * (0.42 + r.f() * 0.16)
			var fl: bool = bloom != null and i % 2 == 0
			var up := 0.3 if fl else 0.12 + r.f() * 0.2
			var f := 1.05 if fl else 1.0
			var b = k.sphere(rr * 0.72 if fl else rr, bloom if fl else m, [x + cos(a) * d * f, yb + s * (0.38 + up), z + sin(a) * d * f], 8)
			b.scale.y *= 0.82
		if bloom != null and r.f() < 0.6:
			var tx := x + (r.f() - 0.5) * s * 0.3
			var tz := z + (r.f() - 0.5) * s * 0.3
			var t = k.sphere(s * 0.34, bloom, [tx, yb + s * 0.95, tz], 8)
			t.scale.y *= 0.75

	## weed / flower strip along x at centre z (half width hw); ground from height_at or o.y
	var weeds := func(x0: float, x1: float, zc: float, hw: float, o: Dictionary) -> void:
		var dens: float = o.get("dens", 5)
		var flowers: float = o.get("flowers", 0.3)
		var n := int(T.js_round((x1 - x0) * dens))
		for i in n:
			var x := x0 + (x1 - x0) * (i + r.f()) / n
			var z := zc + (r.f() * 2.0 - 1.0) * hw
			var y: float = (o.y if o.has("y") else L.height_at(x, z)) - 0.01
			var q := r.f()
			var id := ""
			var s := 0.0
			var h := 0.0
			if q < flowers * 0.35:
				id = "dandelion"
				s = 0.26
				h = 0.24
			elif q < flowers * 0.7:
				id = "daisy"
				s = 0.24
				h = 0.2
			elif q < flowers:
				var nano: bool = o.get("nanohana", false)
				id = "nanohana" if nano else "tsukushi"
				s = 0.42 if nano else 0.26
				h = 0.55 if nano else 0.22
			else:
				id = "grass" if r.f() < 0.5 else "grass2"
				s = 0.3 + r.f() * 0.22
				h = s * (0.8 + r.f() * 0.5) * float(o.get("tall", 1.0))
			var ang := r.f() * PI
			C.cross(x, y, z, s, h, ang, F.r(id), (r.f() - 0.5) * 0.08)

	# ==================================================================== side yard (x 12..27, z -35.5..-25)
	var SY: Dictionary = L.STATION.sideYard
	A.root.add(U.ground_patch(SY.x0 + 0.02, SY.x1, -33.0, SY.z1 - 0.04, M.gravel, 0.012, 1.0))
	A.root.add(U.ground_patch(SY.x0 + 0.02, SY.x1, SY.z0 + 0.02, -33.0, M.grass, 0.014, 0.5))
	var pave := func(x0: float, x1: float, z0: float, z1: float) -> void:
		k.box(x1 - x0, 0.03, z1 - z0, M.paving, [(x0 + x1) / 2.0, 0.015, (z0 + z1) / 2.0])
	pave.call(16.2, 22.2, -26.4, -25.03)
	pave.call(15.9, 17.0, -27.9, -26.4)

	# ---- public toilet block x 17.2..21.8, z -30.6..-26.4, facing the plaza
	var X0 := 17.2
	var X1 := 21.8
	var Z0 := -30.6
	var Z1 := -26.4
	var B0 := 0.15
	var WT := 2.85
	var OT := 2.05
	var TH := 0.15
	k.box(X1 - X0 + 0.1, B0, Z1 - Z0 + 0.1, M.plinth, [(X0 + X1) / 2.0, B0 / 2.0, (Z0 + Z1) / 2.0])
	var open_s := [{"a0": 17.6, "a1": 18.5, "y0": 0.0, "y1": OT}, {"a0": 19.05, "a1": 19.95, "y0": 0.0, "y1": OT}, {"a0": 20.5, "a1": 21.4, "y0": 0.0, "y1": OT}]
	var skin := func(m, y0: float, y1: float, tile) -> void:
		U.wall(k, m, "x", Z1 - TH, Z1, X0, X1, y0, y1, open_s, tile)
		U.wall(k, m, "x", Z0, Z0 + TH, X0, X1, y0, y1, [], tile)
		U.wall(k, m, "z", X0, X0 + TH, Z0 + TH, Z1 - TH, y0, y1, [], tile)
		U.wall(k, m, "z", X1 - TH, X1, Z0 + TH, Z1 - TH, y0, y1, [], tile)
	skin.call(tile_low, B0, 1.15, null)
	skin.call(M.plasterExt, 1.15, WT, 3.0)
	k.box(X1 - X0 + 0.03, 0.06, 0.03, M.band, [(X0 + X1) / 2.0, 1.15, Z1 + 0.012])
	k.box(X1 - X0 + 0.03, 0.06, 0.03, M.band, [(X0 + X1) / 2.0, 1.15, Z0 - 0.012])
	k.box(0.03, 0.06, Z1 - Z0 + 0.03, M.band, [X0 - 0.012, 1.15, (Z0 + Z1) / 2.0])
	k.box(0.03, 0.06, Z1 - Z0 + 0.03, M.band, [X1 + 0.012, 1.15, (Z0 + Z1) / 2.0])
	# vestibules behind the two open doorways
	for ab in [[17.6, 18.5], [20.5, 21.4]]:
		var a0: float = ab[0]
		var a1: float = ab[1]
		var zb := Z1 - 1.0
		var cx := (a0 + a1) / 2.0
		k.box(a1 - a0 + 0.3, OT - B0, 0.08, tile_in, [cx, (B0 + OT) / 2.0, zb])
		k.box(0.06, OT - B0, Z1 - TH - zb, tile_in, [a0 + 0.03, (B0 + OT) / 2.0, (Z1 - TH + zb) / 2.0])
		k.box(0.06, OT - B0, Z1 - TH - zb, tile_in, [a1 - 0.03, (B0 + OT) / 2.0, (Z1 - TH + zb) / 2.0])
		k.box(a1 - a0, 0.05, Z1 - zb, M.sill, [cx, OT + 0.025, (Z1 + zb) / 2.0])
		k.box(a1 - a0, 0.02, Z1 - zb, floor_dark, [cx, B0 + 0.01, (Z1 + zb) / 2.0])
		k.box(a1 - a0 + 0.08, 0.06, 0.1, M.trim, [cx, OT + 0.03, Z1 + 0.03])
		for x in [a0, a1]:
			k.box(0.05, OT - B0, 0.1, M.trim, [x, (B0 + OT) / 2.0, Z1 + 0.02])
	# multipurpose toilet: closed sliding door
	var ma0 := 19.05
	var ma1 := 19.95
	var mcx := (ma0 + ma1) / 2.0
	k.box(ma1 - ma0, OT - B0, 0.05, M.sill, [mcx, (B0 + OT) / 2.0, Z1 - 0.08])
	k.box(ma1 - ma0 + 0.08, 0.06, 0.1, M.alu, [mcx, OT + 0.03, Z1 + 0.03])
	for x in [ma0, ma1]:
		k.box(0.05, OT - B0, 0.1, M.alu, [x, (B0 + OT) / 2.0, Z1 + 0.02])
	k.box(0.04, 0.5, 0.05, M.stainless, [ma1 - 0.14, 1.05, Z1 - 0.03])
	A.plane("misc", "wcMulti", 0.26, 0.26, [mcx, 1.5, Z1 - 0.05], 0.0)
	k.box(0.32, 0.12, 0.02, M.signRed, [mcx, 1.2, Z1 - 0.05])
	A.plane("misc", "wcMen", 0.24, 0.24, [18.05, 2.2, Z1 + 0.008], 0.0)
	A.plane("misc", "wcWomen", 0.24, 0.24, [20.95, 2.2, Z1 + 0.008], 0.0)
	A.board("misc", "toilet", 1.7, 0.374, [19.5, 2.6, Z1 + 0.035], 0.0, {"frame": M.trim, "border": 0.03})
	# frosted high windows on the side walls
	for xr in [[X0 - 0.012, -PI / 2.0], [X1 + 0.012, PI / 2.0]]:
		var x: float = xr[0]
		var rot: float = xr[1]
		for z in [-29.6, -27.6]:
			k.plane(1.0, 0.34, M.frost, [x, 2.35, z], [0, rot, 0])
			k.box(0.04, 0.05, 1.08, M.trim, [x, 2.55, z])
			k.box(0.04, 0.05, 1.08, M.trim, [x, 2.15, z])
			k.box(0.06, 0.04, 1.14, M.sill, [x + (0.02 if x > 19.0 else -0.02), 2.12, z])
	# flat roof with overhang, dark fascia, vent stack, gutter and downpipe
	var rx0 := X0 - 0.35
	var rx1 := X1 + 0.35
	var rz0 := Z0 - 0.3
	var rz1 := Z1 + 0.55
	k.box(rx1 - rx0, 0.14, rz1 - rz0, M.roof, [(rx0 + rx1) / 2.0, WT + 0.07, (rz0 + rz1) / 2.0])
	k.box(rx1 - rx0 + 0.04, 0.24, 0.05, M.fascia, [(rx0 + rx1) / 2.0, WT + 0.06, rz1])
	k.box(rx1 - rx0 + 0.04, 0.24, 0.05, M.fascia, [(rx0 + rx1) / 2.0, WT + 0.06, rz0])
	k.box(0.05, 0.24, rz1 - rz0, M.fascia, [rx0, WT + 0.06, (rz0 + rz1) / 2.0])
	k.box(0.05, 0.24, rz1 - rz0, M.fascia, [rx1, WT + 0.06, (rz0 + rz1) / 2.0])
	k.box(rx1 - rx0 - 0.1, 0.02, rz1 - Z1 - 0.05, M.soffit, [(rx0 + rx1) / 2.0, WT - 0.01, (Z1 + rz1) / 2.0])
	k.cyl(0.07, 0.07, 0.6, M.gutter, [21.0, WT + 0.44, -29.8], null, 10)
	k.cyl(0.1, 0.1, 0.06, M.gutter, [21.0, WT + 0.76, -29.8], null, 10)
	U.beam(k, [rx1 - 0.1, WT + 0.02, rz0 + 0.1], [X1 + 0.07, WT - 0.3, Z0 + 0.12], 0.08, 0.08, M.gutter, true)
	U.beam(k, [X1 + 0.07, WT - 0.3, Z0 + 0.12], [X1 + 0.07, 0.1, Z0 + 0.12], 0.08, 0.08, M.gutter, true)
	# ceiling lamp under the front eave
	k.box(0.5, 0.06, 0.12, M.shelterFascia, [19.5, WT - 0.05, Z1 + 0.3])
	k.box(0.44, 0.02, 0.07, M.tubeWarm, [19.5, WT - 0.085, Z1 + 0.3]).cast_shadow = false
	# grime at the plinth
	for e in [[19.5, Z1 + 0.01, 0.0, 4.4], [19.5, Z0 - 0.01, PI, 4.4], [X1 + 0.01, -28.5, PI / 2.0, 4.0]]:
		k.plane(e[3], 0.4, M.grime, [e[0], 0.36, e[1]], [0, e[2], 0]).receive_shadow = true
	P.addBox((X0 + X1) / 2.0, (Z0 + Z1) / 2.0, X1 - X0 + 0.1, Z1 - Z0 + 0.1, 0, -1, 4)
	bush.call(16.7, -29.9, 0.42, M.shrub, null)
	bush.call(22.35, -27.0, 0.38, M.shrubLight, M.yukiyanagi)

	# ---- drinking fountain / hand-wash next to the path
	var fx := 16.45
	var fz := -27.25
	k.rbox(0.32, 0.78, 0.32, 0.04, M.stoneGrey, [fx, 0.03 + 0.39, fz])
	k.box(0.52, 0.1, 0.4, M.stainless, [fx, 0.85, fz])
	k.box(0.44, 0.02, 0.32, M.steelDark, [fx, 0.9, fz])
	k.cyl(0.018, 0.018, 0.16, M.stainless, [fx, 0.98, fz - 0.12], null, 8)
	U.beam(k, [fx, 1.05, fz - 0.12], [fx, 1.05, fz - 0.02], 0.03, 0.03, M.stainless, true)
	k.box(0.06, 0.03, 0.03, M.get("signBlue", M.navy), [fx, 1.07, fz - 0.14])
	A.plane("misc", "tapSign", 0.24, 0.12, [fx, 0.6, fz + 0.165], 0.0)
	P.addCylinder(fx, fz, 0.3, -1, 1.1)
	# hose reel and blue bucket beside it
	var hk = ctx.kit(k.group([16.2, 0.03, -28.55], 0.3))
	hk.cyl(0.16, 0.16, 0.1, hose_green, [0, 0.24, 0], [PI / 2.0, 0, 0], 14)
	hk.box(0.03, 0.4, 0.12, M.steelDark, [-0.1, 0.2, 0])
	hk.box(0.03, 0.4, 0.12, M.steelDark, [0.1, 0.2, 0])
	hk.box(0.36, 0.03, 0.2, M.steelDark, [0, 0.015, 0])
	k.cyl(0.14, 0.11, 0.26, bucket_blue, [16.95, 0.16, -27.95], null, 14)
	k.cyl(0.12, 0.12, 0.01, M.steelDark, [16.95, 0.28, -27.95], null, 14)
	P.addCylinder(16.2, -28.55, 0.28, -1, 1)

	# ---- tool shed
	var sx0 := 23.0
	var sx1 := 25.4
	var sz0 := -30.1
	var sz1 := -28.7
	var H := 2.0
	var scx := (sx0 + sx1) / 2.0
	var scz := (sz0 + sz1) / 2.0
	k.box(sx1 - sx0 + 0.1, 0.08, sz1 - sz0 + 0.1, M.plinth, [scx, 0.04, scz])
	k.rbox(sx1 - sx0, H - 0.08, sz1 - sz0, 0.02, M.pastelGreen, [scx, 0.08 + (H - 0.08) / 2.0, scz])
	# sliding doors with ribs, handle, label
	for dd in [[-0.55, 0.012], [0.5, 0.03]]:
		var dx: float = dd[0]
		var dz: float = dd[1]
		k.box(1.12, H - 0.35, 0.02, M.sill, [scx + dx, 0.2 + (H - 0.35) / 2.0, sz1 + dz])
		for i in range(-2, 3):
			k.box(0.025, H - 0.4, 0.015, M.band, [scx + dx + i * 0.2, 0.2 + (H - 0.35) / 2.0, sz1 + dz + 0.012])
	k.box(0.1, 0.04, 0.04, M.steelDark, [scx - 0.08, 1.0, sz1 + 0.05])
	A.plane("misc", "shedLabel", 0.4, 0.12, [scx + 0.5, 1.62, sz1 + 0.058], 0.0)
	k.box(sx1 - sx0, 0.03, 0.04, M.aluDark, [scx, 0.19, sz1 + 0.03])
	# pent roof
	var shed_roof = k.group([scx, H + 0.06, scz], 0.0)
	shed_roof.rotation.x = 0.08
	ctx.kit(shed_roof).box(sx1 - sx0 + 0.24, 0.07, sz1 - sz0 + 0.3, M.roofSeam, [0, 0, 0])
	for i in 7:
		ctx.kit(shed_roof).box(0.03, 0.03, sz1 - sz0 + 0.3, M.roof, [-1.2 + i * 0.4, 0.045, 0])
	P.addBox(scx, scz, sx1 - sx0 + 0.1, sz1 - sz0 + 0.1, 0, -1, 3)
	# watering can and broom leaning on the shed
	var wk = ctx.kit(k.group([22.75, 0.02, -28.9], -0.4))
	wk.cyl(0.1, 0.12, 0.26, hose_green, [0, 0.13, 0], null, 12)
	U.beam(wk, [0.1, 0.12, 0], [0.3, 0.3, 0], 0.03, 0.03, hose_green, true)
	U.beam(wk, [-0.08, 0.3, 0], [0.06, 0.3, 0], 0.02, 0.02, hose_green, true)
	U.beam(k, [25.6, 0.05, -28.72], [25.52, 1.35, -28.93], 0.03, 0.03, M.woodLight, true)
	k.box(0.26, 0.2, 0.06, M.woodDark, [25.605, 0.12, -28.7], [0, 0, 0.05])

	# ---- staff bicycle shed
	var bx0 := 22.3
	var bx1 := 26.7
	var zB := -32.85
	var zF := -30.95
	var yB := 2.05
	var yF := 2.3
	var posts := [[bx0 + 0.1, zB], [bx1 - 0.1, zB], [bx0 + 0.1, zF], [bx1 - 0.1, zF], [(bx0 + bx1) / 2.0, zB], [(bx0 + bx1) / 2.0, zF]]
	for pz in posts:
		var x: float = pz[0]
		var z: float = pz[1]
		var top := yB if z == zB else yF
		k.box(0.08, top, 0.08, M.steelDark, [x, top / 2.0, z])
		k.box(0.2, 0.04, 0.2, M.stoneGrey, [x, 0.02, z])
		P.addBox(x, z, 0.12, 0.12, 0, -1, 3)
	var roof_ang := atan2(yF - yB, zF - zB)
	var rlen := sqrt((yF - yB) ** 2 + (zF - zB) ** 2) + 0.5
	var rg = k.group([(bx0 + bx1) / 2.0, (yB + yF) / 2.0 + 0.06, (zB + zF) / 2.0], 0.0)
	rg.rotation.x = -roof_ang
	var rk = ctx.kit(rg)
	rk.box(bx1 - bx0 + 0.3, 0.05, rlen, M.shelterRoof, [0, 0, 0])
	for i in 12:
		rk.box(0.03, 0.03, rlen, M.shelterFascia, [-(bx1 - bx0) / 2.0 + i * 0.4, 0.035, 0])
	k.box(bx1 - bx0 + 0.3, 0.12, 0.06, M.steelDark, [(bx0 + bx1) / 2.0, yF - 0.02, zF])
	k.box(bx1 - bx0 + 0.3, 0.12, 0.06, M.steelDark, [(bx0 + bx1) / 2.0, yB - 0.02, zB])
	# wheel rack (front-wheel slots)
	k.box(bx1 - bx0 - 0.3, 0.05, 0.05, M.steel, [(bx0 + bx1) / 2.0, 0.32, zB + 0.45])
	k.box(bx1 - bx0 - 0.3, 0.04, 0.04, M.steel, [(bx0 + bx1) / 2.0, 0.06, zB + 0.25])
	var rack_x := bx0 + 0.45
	while rack_x < bx1 - 0.3:
		k.box(0.03, 0.3, 0.36, M.steel, [rack_x - 0.07, 0.2, zB + 0.35])
		k.box(0.03, 0.3, 0.36, M.steel, [rack_x + 0.07, 0.2, zB + 0.35])
		rack_x += 0.62
	P.addBox((bx0 + bx1) / 2.0, zB + 0.35, bx1 - bx0 - 0.3, 0.4, 0, -1, 0.9)
	A.board("misc", "staffBike", 0.9, 0.253, [(bx0 + bx1) / 2.0, yF - 0.28, zF + 0.04], 0.0, {"frame": M.steelDark, "border": 0.02})

	# ---- station garden: brick beds, welcome board, wheelset monument, shrubs
	var bed := func(x0: float, x1: float, z0: float, z1: float, kinds: Array, dens: float) -> void:
		var h := 0.22
		var cx := (x0 + x1) / 2.0
		var cz := (z0 + z1) / 2.0
		var w := x1 - x0
		var d := z1 - z0
		var t := 0.11
		k.box(w, h, t, M.brick, [cx, h / 2.0, z0 + t / 2.0])
		k.box(w, h, t, M.brick, [cx, h / 2.0, z1 - t / 2.0])
		k.box(t, h, d - 2.0 * t, M.brick, [x0 + t / 2.0, h / 2.0, cz])
		k.box(t, h, d - 2.0 * t, M.brick, [x1 - t / 2.0, h / 2.0, cz])
		k.box(w + 0.02, 0.03, t + 0.02, M.brickLight, [cx, h + 0.012, z0 + t / 2.0])
		k.box(w + 0.02, 0.03, t + 0.02, M.brickLight, [cx, h + 0.012, z1 - t / 2.0])
		k.box(w - 2.0 * t, 0.02, d - 2.0 * t, M.soil, [cx, h - 0.04, cz])
		var n := int(T.js_round(w * d * dens))
		for i in n:
			var x := x0 + t + 0.08 + r.f() * (w - 2.0 * t - 0.16)
			var z := z0 + t + 0.08 + r.f() * (d - 2.0 * t - 0.16)
			var id: String = kinds[floori(r.f() * kinds.size())]
			var s := 0.36 if id == "tulip" else (0.42 if id == "nanohana" else 0.3)
			var hh := 0.42 if id == "tulip" else (0.55 if id == "nanohana" else 0.26)
			var ch := hh * (0.85 + r.f() * 0.3)
			C.cross(x, h - 0.04, z, s, ch, r.f() * PI, F.r(id))
		P.addBox(cx, cz, w, d, 0, -1, 0.5)
	bed.call(12.35, 15.9, -26.45, -25.2, ["tulip", "tulip", "pansy", "pansy"], 22.0)
	bed.call(22.6, 26.8, -26.3, -25.2, ["pansy", "tulip", "daisy", "pansy"], 20.0)
	bed.call(12.9, 15.7, -30.1, -28.2, ["nanohana", "pansy", "daisy", "tulip"], 16.0)
	# welcome board standing in the centre bed, garden care sign on a stake in the front bed
	for x in [13.75, 14.85]:
		k.box(0.06, 0.95, 0.06, M.woodDark, [x, 0.475, -29.2])
	A.board("misc", "welcome", 1.1, 0.55, [14.3, 0.92, -29.16], 0.0, {"frame": M.woodDark, "border": 0.03, "depth": 0.04})
	k.box(0.04, 0.55, 0.04, M.woodDark, [12.8, 0.275, -25.7])
	A.board("misc", "gardenSign", 0.44, 0.19, [12.8, 0.6, -25.67], 0.0, {"frame": M.woodDark, "border": 0.015, "depth": 0.02})
	# retired wheelset monument
	var mx := 14.3
	var mz := -31.9
	k.box(1.8, 0.35, 0.9, M.stone, [mx, 0.175, mz])
	k.box(1.86, 0.04, 0.96, M.band, [mx, 0.37, mz])
	var mtop := 0.39
	for s in [-1.0, 1.0]:
		k.box(0.07, 0.12, 0.88, M.steelDark, [mx + s * 0.56, mtop + 0.06, mz])
		var wy := mtop + 0.12 + 0.43
		k.cyl(0.43, 0.43, 0.12, wheel_red, [mx + s * 0.56, wy, mz], [0, 0, PI / 2.0], 22)
		k.cyl(0.44, 0.44, 0.06, M.steel, [mx + s * 0.53, wy, mz], [0, 0, PI / 2.0], 22)
		k.cyl(0.47, 0.47, 0.025, M.steel, [mx + s * 0.49, wy, mz], [0, 0, PI / 2.0], 22)
		k.cyl(0.14, 0.14, 0.2, M.steelDark, [mx + s * 0.58, wy, mz], [0, 0, PI / 2.0], 12)
	k.cyl(0.075, 0.075, 1.45, M.steelDark, [mx, mtop + 0.55, mz], [0, 0, PI / 2.0], 12)
	# plaque on a slanted stand
	k.box(0.06, 0.62, 0.06, M.woodDark, [mx, 0.31, mz + 0.75])
	var pg = k.group([mx, 0.72, mz + 0.78], 0.0)
	pg.rotation.x = -0.5
	ctx.kit(pg).box(0.6, 0.28, 0.04, M.woodDark, [0, 0, -0.02])
	var pl := T.MeshObj.new(U.rect_plane(0.55, 0.24, A.atlases.misc.r("wheelPlaque")), A.sign_mat("misc", false))
	pl.position.z = 0.002
	pg.add(pl)
	P.addBox(mx, mz, 1.9, 1.0, 0, -1, 1.5)
	bush.call(12.75, -31.9, 0.44, M.shrub, azalea)
	bush.call(15.85, -31.75, 0.4, M.shrubDark, azalea_deep)
	# shrubs against the building east wall and along the platform wall
	bush.call(12.5, -27.5, 0.38, M.shrubLight, M.yukiyanagi)
	bush.call(12.5, -33.2, 0.42, M.shrubDark, null)
	bush.call(16.4, -30.7, 0.36, M.shrub, azalea)
	var wall_x := 12.6
	while wall_x < 27.0:
		var q := r.f()
		var m = M.shrub if q < 0.5 else (M.shrubLight if q < 0.8 else M.shrubDark)
		var bz := -34.85 + (r.f() - 0.5) * 0.2
		var bs := 0.42 + r.f() * 0.2
		var bloom = null
		if r.f() < 0.3:
			bloom = M.yukiyanagi if r.f() < 0.5 else azalea
		bush.call(wall_x, bz, bs, m, bloom)
		wall_x += 1.15 + r.f() * 0.5
	# clover and tsukushi in the gravel, weeds at the wall foot
	for i in 70:
		var x := 12.3 + r.f() * 14.5
		var z := -33.0 + r.f() * 7.8
		if x > 16.9 and x < 22.3 and z > -31.0 and z < -25.9:
			continue
		if x > 22.2 and x < 26.8 and z > -33.0 and z < -28.5:
			continue
		if x > 12.8 and x < 16.0 and z > -32.5 and z < -25.0:
			continue
		var ang := r.f() * PI
		var id := "tsukushi" if r.f() < 0.15 else ("daisy" if r.f() < 0.3 else "grass2")
		C.cross(x, 0.0, z, 0.24, 0.18, ang, F.r(id))
	weeds.call(17.2, 21.8, -30.75, 0.08, {"dens": 4, "flowers": 0.25, "y": 0.0, "tall": 0.8})

	# ==================================================================== west yard (x -9.25..-4), kept low
	var WYD: Dictionary = L.STATION.westYard
	A.root.add(U.ground_patch(WYD.x0 + 0.02, WYD.x1 - 0.02, WYD.z0, WYD.z1 - 0.04, M.gravel, 0.012, 0.7))
	# trimmed hedge along the road side, 0.75 m
	var hz0 := -33.7
	var hz1 := -25.4
	var hx := -8.95
	k.rbox(0.5, 0.72, hz1 - hz0, 0.18, M.shrub, [hx, 0.36, (hz0 + hz1) / 2.0])
	var hz := hz0 + 0.4
	while hz < hz1 - 0.3:
		var px := hx + (r.f() - 0.5) * 0.1
		var pz := hz + r.f() * 0.3
		var b = k.sphere(0.28, M.shrubLight, [px, 0.66, pz], 8)
		b.scale.y *= 0.55
		hz += 0.9
	P.addBox(hx, (hz0 + hz1) / 2.0, 0.5, hz1 - hz0, 0, -1, 1.0)
	# low planters along the building wall
	var planter_low := func(x0: float, x1: float, z0: float, z1: float, kinds: Array) -> void:
		var cx := (x0 + x1) / 2.0
		var cz := (z0 + z1) / 2.0
		var w := x1 - x0
		var d := z1 - z0
		var h := 0.42
		k.rbox(w, h, d, 0.03, M.stone, [cx, h / 2.0, cz])
		k.box(w - 0.1, 0.02, d - 0.1, M.soil, [cx, h - 0.03, cz])
		var n := int(T.js_round(w * d * 14.0))
		for i in n:
			var x := x0 + 0.1 + r.f() * (w - 0.2)
			var z := z0 + 0.1 + r.f() * (d - 0.2)
			var ang := r.f() * PI
			C.cross(x, h - 0.03, z, 0.28, 0.26, ang, F.r(kinds[floori(r.f() * kinds.size())]))
		P.addBox(cx, cz, w, d, 0, -1, h + 0.1)
	planter_low.call(-5.0, -4.35, -33.6, -31.4, ["pansy", "pansy", "daisy"])
	planter_low.call(-5.0, -4.35, -28.2, -26.3, ["pansy", "tulip", "pansy"])
	# flower pots by the south corner
	for e in [[-4.6, -25.65, 0.16], [-4.95, -25.55, 0.13], [-4.62, -26.0, 0.12]]:
		var s: float = e[2]
		k.cyl(s, s * 0.75, s * 1.6, M.plantPot, [e[0], s * 0.8, e[1]], null, 12)
		C.cross(e[0], s * 1.5, e[1], s * 2.2, s * 2.0, r.f() * PI, F.r("pansy"))
	# low "no bicycle parking" notice
	var nx := -7.5
	var nz := -25.55
	for dx in [-0.2, 0.2]:
		k.box(0.05, 0.9, 0.05, M.steelDark, [nx + dx, 0.45, nz])
	A.board("misc", "bikeNotice", 0.5, 0.35, [nx, 0.85, nz + 0.03], 0.0, {"frame": M.fenceWhite, "border": 0.02})
	P.addBox(nx, nz, 0.5, 0.1, 0, -1, 1.1)
	bush.call(-7.4, -31.8, 0.32, M.shrubLight, null)
	bush.call(-6.3, -28.6, 0.3, M.shrub, azalea)
	for i in 40:
		var x := -8.5 + r.f() * 3.4
		var z := -33.6 + r.f() * 8.0
		var ang := r.f() * PI
		var id := "daisy" if r.f() < 0.3 else ("tsukushi" if r.f() < 0.4 else "grass2")
		C.cross(x, L.height_at(x, z), z, 0.24, 0.18, ang, F.r(id))

	# ==================================================================== weeds outside the platform fences
	var S: Dictionary = L.PLATFORM.south
	var N: Dictionary = L.PLATFORM.north
	weeds.call(-6.9, -4.3, S.z1 + 0.35, 0.28, {"dens": 6, "flowers": 0.35})
	weeds.call(12.2, 46.5, S.z1 + 0.3, 0.25, {"dens": 5, "flowers": 0.3})
	weeds.call(27.0, 46.5, S.z1 + 0.85, 0.4, {"dens": 4, "flowers": 0.4, "nanohana": true})
	weeds.call(9.3, 48.3, N.z0 - 0.35, 0.3, {"dens": 6, "flowers": 0.35, "nanohana": true})
	weeds.call(9.3, 48.3, N.z0 - 1.05, 0.35, {"dens": 3, "flowers": 0.3, "tall": 1.2})
	weeds.call(-6.9, -6.45, N.z0 - 0.7, 0.6, {"dens": 10, "flowers": 0.3})
	# low shrubs here and there outside the fences
	var lx := 28.5
	while lx < 46.0:
		var bz: float = S.z1 + 0.9 + r.f() * 0.4
		var bs := 0.34 + r.f() * 0.2
		var m = M.shrubLight if r.f() < 0.3 else M.shrub
		var bloom = M.yukiyanagi if r.f() < 0.2 else null
		bush.call(lx, bz, bs, m, bloom)
		lx += 3.2 + r.f() * 2.4
	lx = 9.8
	while lx < 47.0:
		var bz: float = N.z0 - 0.95 - r.f() * 0.3
		var bs := 0.32 + r.f() * 0.22
		var m = M.shrubDark if r.f() < 0.3 else M.shrub
		bush.call(lx, bz, bs, m, null)
		lx += 3.0 + r.f() * 2.6

	var fol = C.build(M.foliage)
	if fol != null:
		ctx.no_outline(fol)
		A.root.add(fol)
