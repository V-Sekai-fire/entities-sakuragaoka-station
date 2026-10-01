# environment/park.js: a small green slope park east of the NE block (mound, winding gravel path, log
# steps, a bench on top, azalea shrubs, young maples, an entrance sign); allotments and a gravel lot in
# the west strip.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Common = preload("res://addons/sakuragaoka_station/world/environment/common.gd")
const Foliage = preload("res://addons/sakuragaoka_station/world/lib/foliage.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")


static func build_park(ctx, C, tx) -> Dictionary:
	var L = ctx.L
	var grp := T.Group.new()
	grp.name = "env-park"
	ctx.add_static(grp)
	var k = ctx.kit(grp)
	var r: Rng = ctx.rng("env-park")
	var M: Dictionary = Common.PARK.mound
	var PARK: Dictionary = Common.PARK
	var wood = ctx.mat.toon("#b48a62", {"paint": 0.09, "name": "env-benchwood"})
	var wood_d = ctx.mat.toon("#8a6446", {"paint": 0.08})
	var conc = ctx.mat.toon("#d4d0c5", {"paint": 0.08, "name": "env-stair"})
	var log_mat = ctx.mat.toon("#9a7b5c", {"paint": 0.1})
	# ------------------------------------------------------------ walkable mound (physics boxes)
	var cs := 0.7
	var x: float = M.x - M.rx
	while x < M.x + M.rx:
		var z: float = M.z - M.rz
		while z < M.z + M.rz:
			var cx := x + cs / 2.0
			var cz := z + cs / 2.0
			var h := Common.park_mound(cx, cz)
			if h >= 0.04:
				ctx.physics.addWalkBox(cx, cz, cs, cs, 0, L.height_at(cx, cz) + h)
			z += cs
		x += cs
	var is_park_mound := func(px: float, pz: float) -> bool: return Common.park_mound(px, pz) > 0.02
	# ------------------------------------------------------------ log steps where the path climbs
	var pts: Array = []
	for p in Common.PATHS:
		if p.kind == "park":
			pts = p.pts
			break
	for i in pts.size() - 1:
		var ax := float(pts[i][0])
		var az := float(pts[i][1])
		var bx := float(pts[i + 1][0])
		var bz := float(pts[i + 1][1])
		var len := sqrt((bx - ax) ** 2 + (bz - az) ** 2)
		var t := 0.6
		while t < len:
			var px := ax + (bx - ax) * t / len
			var pz := az + (bz - az) * t / len
			var slope: float = absf(C.terrain_h(px + (bx - ax) / len * 0.5, pz + (bz - az) / len * 0.5) - C.terrain_h(px - (bx - ax) / len * 0.5, pz - (bz - az) / len * 0.5))
			if slope >= 0.18:
				var rot := atan2(bx - ax, bz - az)
				var y: float = C.terrain_h(px, pz)
				k.cyl(0.075, 0.075, 1.5, log_mat, [px, y + 0.03, pz], null, 8).set_rotation(0, rot, PI / 2.0, "YXZ")
				for s in [-1, 1]:
					k.cyl(0.035, 0.035, 0.3, wood_d, [px + cos(rot) * 0.8 * s, y + 0.05, pz - sin(rot) * 0.8 * s], null, 6)
			t += 1.1
	# ------------------------------------------------------------ bench on the top, looking north
	var top := {"x": M.x, "z": M.z + 0.1}
	var by: float = C.terrain_h(top.x, top.z - 0.6) - 0.05
	var bgp = k.group([top.x, by, top.z - 0.6], PI)
	var kb = ctx.kit(bgp)
	for sx in [-0.72, 0.72]:
		kb.box(0.09, 0.44, 0.46, conc, [sx, 0.2, 0])
	for s in 4:
		kb.box(1.78, 0.04, 0.095, wood, [0, 0.44, -0.16 + s * 0.108])
	for s in 3:
		kb.box(1.78, 0.085, 0.035, wood_d if s == 1 else wood, [0, 0.6 + s * 0.13, -0.235 - s * 0.018], [-0.12, 0, 0])
	for sx in [-0.72, 0.72]:
		kb.box(0.08, 0.5, 0.07, conc, [sx, 0.68, -0.21], [-0.12, 0, 0])
	ctx.physics.addBox(top.x, top.z - 0.6, 1.9, 0.62, PI, by, by + 0.95)
	# ------------------------------------------------------------ azalea shrubs + young maples
	var fmat = Foliage.foliage_material(ctx)
	var fl_mat = ctx.mat.toon("#ffffff", {"vertexColors": true, "paint": 0.02})
	var tsutsuji := ["#ee8fb6", "#e8739f", "#f4a9c6", "#dd6a98", "#f6eef2"]
	var shrubs := []
	var i2 := 0
	while i2 < 70 and shrubs.size() < 24:
		i2 += 1
		var a := r.f() * PI * 2.0
		var d := 0.95 + r.f() * 0.25
		var sx: float = M.x + cos(a) * M.rx * d
		var sz: float = M.z + sin(a) * M.rz * d
		if Common.path_dist(sx, sz).d < 2.2:
			continue
		if sx < PARK.x0 + 1 or sx > PARK.x1 - 1 or sz < PARK.z0 + 1 or sz > PARK.z1 - 1:
			continue
		var clash := false
		for e in shrubs:
			if sqrt((e.x - sx) ** 2 + (e.z - sz) ** 2) < 2.0:
				clash = true
				break
		if clash:
			continue
		var s := 0.55 + r.f() * 0.35
		shrubs.append({"x": sx, "z": sz, "s": s})
		var sb := T.js_round(s * 10.0) / 10.0
		var v := shrubs.size() % 3
		var geo := Foliage.shrub_geometry({"rx": sb * 1.3, "ry": sb * 0.755, "rz": sb * 1.1, "seed": 40 + v * 7, "detail": 3, "lumps": 0.18, "puff": maxf(0.3, sb * 0.45), "colors": Foliage.SHRUB_COLORS.azalea})
		var m := T.MeshObj.new(geo, fmat)
		m.scale = Vector3.ONE * (s / sb)
		m.position = Vector3(sx, C.terrain_h(sx, sz) - 0.03, sz)
		m.rotation.y = r.f() * 3.0
		m.cast_shadow = true
		m.receive_shadow = true
		grp.add(m)
		var fl := T.MeshObj.new(Foliage.flower_geometry(geo, {"density": 8, "size": 0.04, "petals": 0, "colors": tsutsuji, "seed": v * 5 + 3, "minY": 0.32}), fl_mat)
		fl.cast_shadow = false
		fl.receive_shadow = true
		ctx.no_outline(fl)
		m.add(fl)
		ctx.physics.addCylinder(sx, sz, s * 1.1, C.terrain_h(sx, sz), C.terrain_h(sx, sz) + s)
	var trunk = ctx.mat.toon("#7a6452", {"paint": 0.05})
	var maple := [{"top": "#c9e09a", "mid": "#9cc27a", "base": "#6d9760"}, {"top": "#dcebaa", "mid": "#b9d38a", "base": "#88a972"}, {"top": "#b7d58e", "mid": "#86b06a", "base": "#5b8858"}]
	var lobe := []
	for v in 3:
		lobe.append(Foliage.shrub_geometry({"rx": 1, "ry": 1, "rz": 1, "detail": 2, "flatBottom": false, "cutBottom": false, "lumps": 0.3, "freq": 1.6, "puff": 0,
			"seed": 71 + v, "colors": maple[v], "normalBlend": 0.45}).clone().translate(0, -0.55, 0))
	for e in [[66.2, -9.5, 5.4], [90.2, -29.8, 6.0], [66.8, -30.6, 4.8], [91.0, -9.2, 4.4]]:
		var tx0: float = e[0]
		var tz0: float = e[1]
		var h: float = e[2]
		var y: float = C.terrain_h(tx0, tz0)
		k.cyl(0.09, 0.15, h * 0.5, trunk, [tx0, y + h * 0.25, tz0], null, 7)
		for f in [[0.5, 0.2], [-0.45, 0.35], [0.05, -0.55]]:
			k.cyl(0.04, 0.07, h * 0.3, trunk, [tx0 + f[0] * h * 0.06, y + h * 0.56, tz0 + f[1] * h * 0.06], [f[1] * 0.5, 0, -f[0] * 0.5], 6)
		var cy := y + h * 0.68
		var R := h * 0.34
		var clumps := [[0.0, 0.35, 0.0, 0.62]]
		for i in 6:
			var a: float = i / 6.0 * PI * 2.0 + r.f() * 0.5
			var c1 := cos(a) * 0.62
			var c2 := (r.f() - 0.35) * 0.4
			var c3 := sin(a) * 0.62
			var c4 := 0.44 + r.f() * 0.12
			clumps.append([c1, c2, c3, c4])
		for i in 2:
			var a := r.f() * PI * 2.0
			var c1 := cos(a) * 0.3
			var c2 := 0.7 + r.f() * 0.15
			clumps.append([c1, c2, sin(a) * 0.3, 0.38])
		for i in clumps.size():
			var cl: Array = clumps[i]
			var m := T.MeshObj.new(lobe[i % 3], fmat)
			var sc: float = R * cl[3] * 1.25
			m.scale = Vector3(sc, sc * 0.82, sc)
			m.position = Vector3(tx0 + cl[0] * R, cy + cl[1] * R, tz0 + cl[2] * R)
			m.cast_shadow = true
			m.receive_shadow = true
			grp.add(m)
		ctx.physics.addCylinder(tx0, tz0, 0.2, y, y + 3)
	# ------------------------------------------------------------ entrance sign + low log fence along R3
	var sign_tex = ctx.tex.draw(512, 256, null, {"key": "env-park-sign"})
	var ex := 68.6
	var ez := -7.3
	var ey: float = C.terrain_h(ex, ez)
	var sg = k.group([ex, ey, ez], 0.2)
	var ks = ctx.kit(sg)
	for px in [-0.55, 0.55]:
		ks.box(0.1, 1.3, 0.1, wood_d, [px, 0.65, 0])
	ks.box(1.24, 0.64, 0.06, wood, [0, 1.0, 0])
	ks.plane(1.16, 0.58, ctx.mat.toon("#ffffff", {"map": sign_tex, "paint": 0.03}), [0, 1.0, 0.031])
	ctx.physics.addBox(ex, ez, 1.3, 0.2, 0.2, ey, ey + 1.4)
	var fx: float = PARK.x0 + 0.5
	while fx < PARK.x1 - 0.3:
		if not (absf(fx - 70.5) < 1.4 or absf(fx - 86.5) < 1.4 or absf(fx - 68.6) < 1.0):
			var fz: float = PARK.z1 - 0.35
			var fy: float = C.terrain_h(fx, fz)
			k.cyl(0.06, 0.06, 0.55, log_mat, [fx, fy + 0.27, fz], null, 7)
			if fx + 1.6 < PARK.x1 - 0.3 and not (absf(fx + 0.8 - 70.5) < 1.6) and not (absf(fx + 0.8 - 86.5) < 1.6):
				ctx.wires.add(ctx.geo.catenary([fx, fy + 0.45, fz], [fx + 1.6, fy + 0.45, fz], 0.08, 6), {"width": 0.018, "color": "#c8b48c"})
		fx += 1.6
	# ------------------------------------------------------------ allotments (west strip)
	var A: Dictionary = Common.ALLOT_W
	var soil = ctx.mat.toon("#ffffff", {"map": tx.sub("fields").veg, "paint": 0.05, "name": "env-allot"})
	var soil_d = ctx.mat.toon("#a58b6c", {"paint": 0.06})
	var bamboo = ctx.mat.toon("#c9b98a", {"paint": 0.04})
	var net = ctx.mat.toon("#7fae8c", {"paint": 0.02, "transparent": true, "opacity": 0.55, "side": "double", "depthWrite": false})
	var cab_g := Common.smooth_blob(0)
	var cabs := []
	var pw := 3.6
	var pd := 6.0
	var gap := 0.9
	var ax0: float = A.x0 + 0.6
	while ax0 + pw < A.x1:
		var az0: float = A.z0 + 0.6
		while az0 + pd < A.z1:
			if r.f() < 0.12:
				az0 += pd + gap
				continue
			var cx := ax0 + pw / 2.0
			var cz := az0 + pd / 2.0
			var y: float = maxf(L.height_at(ax0, az0), L.height_at(ax0 + pw, az0 + pd)) + 0.02
			k.box(pw, 0.5, pd, soil_d, [cx, y - 0.13, cz])
			k.plane(pw - 0.04, pd - 0.04, soil, [cx, y + 0.122, cz], [-PI / 2.0, 0, 0]).receive_shadow = true
			var kind := r.f()
			if kind < 0.55:
				var rx := ax0 + 0.45
				while rx < ax0 + pw - 0.3:
					var rz := az0 + 0.45
					while rz < az0 + pd - 0.3:
						if r.f() < 0.68:
							cabs.append([rx, y + 0.14, rz, 0.17 + r.f() * 0.1])
						rz += 0.55
					rx += 0.6
			elif kind < 0.85:
				var rz := az0 + 0.6
				while rz < az0 + pd - 0.4:
					k.box(0.03, 1.5, 0.03, bamboo, [ax0 + 0.8, y + 0.85, rz])
					k.box(0.03, 1.5, 0.03, bamboo, [ax0 + pw - 0.8, y + 0.85, rz])
					rz += 1.2
				k.box(0.02, 1.2, pd - 1.2, net, [ax0 + 0.8, y + 0.9, cz]).cast_shadow = false
				k.box(0.02, 1.2, pd - 1.2, net, [ax0 + pw - 0.8, y + 0.9, cz]).cast_shadow = false
				ctx.physics.addBox(cx, cz, pw - 1.4, pd - 1.0, 0, y, y + 1.6)
			k.box(0.06, 0.5, 0.06, ctx.mat.toon("#f0ede4"), [ax0 + 0.15, y + 0.25, az0 + pd - 0.1])
			az0 += pd + gap
		ax0 += pw + gap
	var im := T.InstancedMesh.new(cab_g, ctx.mat.toon("#ffffff", {"paint": 0.06, "name": "env-cabbage"}), cabs.size())
	for i in cabs.size():
		var cb: Array = cabs[i]
		var q := Quaternion(Vector3(0, 1, 0), r.f() * 3.0)
		im.set_matrix_at(i, T.compose(Vector3(cb[0], cb[1], cb[2]), q, Vector3(cb[3], cb[3] * 0.8, cb[3])))
		im.set_color_at(i, T.color(r.pick(["#8fbf6a", "#a6cf7b", "#7aae5e", "#b8d98a"])))
	im.cast_shadow = true
	im.receive_shadow = true
	grp.add(im)
	var shx: float = A.x0 + 2.4
	var shz: float = A.z1 + 1.8
	var shy: float = L.height_at(shx, shz)
	k.boxb(2.4, 2.1, 1.8, ctx.mat.toon("#b9b5a8", {"paint": 0.08}), [shx, shy, shz])
	k.boxb(2.7, 0.08, 2.1, ctx.mat.toon("#7b8691", {"paint": 0.04}), [shx, shy + 2.1, shz], [0.08, 0, 0])
	k.box(0.9, 1.8, 0.03, ctx.mat.toon("#8f98a0"), [shx + 0.4, shy + 0.95, shz + 0.91])
	ctx.physics.addBox(shx, shz, 2.5, 1.9, 0, shy, shy + 2.3)
	var at = ctx.tex.sign({"w": 512, "h": 160, "key": "env-allot-sign"})
	var asx: float = A.x1 - 0.5
	var asz: float = A.z0 - 1.2
	var asy: float = L.height_at(asx, asz)
	k.box(0.07, 1.4, 0.07, ctx.mat.toon("#e9e7e0"), [asx, asy + 0.7, asz - 0.7])
	k.box(0.07, 1.4, 0.07, ctx.mat.toon("#e9e7e0"), [asx, asy + 0.7, asz + 0.7])
	k.plane(1.6, 0.5, ctx.mat.toon("#ffffff", {"map": at, "paint": 0.02}), [asx + 0.045, asy + 1.2, asz], [0, PI / 2.0, 0])
	ctx.physics.addBox(asx, asz, 0.2, 1.6, 0, asy, asy + 1.5)
	# ------------------------------------------------------------ gravel lot: wheel stops + signs
	var stop = ctx.mat.toon("#d9d5ca", {"paint": 0.06})
	var line_y = ctx.mat.decal("#f0ece0")
	for i in 4:
		var wx := -90.2 + i * 3.4
		var wz := -11.9
		k.boxb(1.6, 0.12, 0.16, stop, [wx, L.height_at(wx, wz), wz])
		k.box(0.08, 0.01, 4.6, line_y, [wx + 1.7, L.height_at(wx, wz) + 0.006, -9.4])
	var pk = ctx.tex.sign({"w": 512, "h": 256, "key": "env-parking-sign"})
	var ppx := -77.4
	var ppz := -6.9
	var ppy: float = L.height_at(ppx, ppz)
	k.cyl(0.04, 0.04, 1.9, ctx.mat.toon("#9aa1a8"), [ppx, ppy + 0.95, ppz], null, 8)
	k.plane(0.9, 0.45, ctx.mat.toon("#ffffff", {"map": pk, "paint": 0.02}), [ppx, ppy + 1.6, ppz + 0.05])
	k.box(0.92, 0.47, 0.02, ctx.mat.toon("#e9ecee"), [ppx, ppy + 1.6, ppz + 0.035])
	ctx.physics.addCylinder(ppx, ppz, 0.08, ppy, ppy + 2)
	var sale = ctx.tex.sign({"w": 512, "h": 256, "key": "env-sale-sign"})
	var vx := -68.5
	var vz := -7.0
	var vy: float = L.height_at(vx, vz)
	k.box(0.07, 1.5, 0.07, ctx.mat.toon("#e9e7e0"), [vx - 0.55, vy + 0.75, vz])
	k.box(0.07, 1.5, 0.07, ctx.mat.toon("#e9e7e0"), [vx + 0.55, vy + 0.75, vz])
	k.box(1.3, 0.66, 0.03, ctx.mat.toon("#fbfaf6"), [vx, vy + 1.2, vz])
	k.plane(1.26, 0.62, ctx.mat.toon("#ffffff", {"map": sale, "paint": 0.02}), [vx, vy + 1.2, vz + 0.02])
	ctx.physics.addBox(vx, vz, 1.3, 0.2, 0, vy, vy + 1.6)
	var rfx := -75.5
	while rfx < -63.2:
		var rfz := -6.5
		var rfy: float = L.height_at(rfx, rfz)
		k.box(0.07, 0.6, 0.07, ctx.mat.toon("#dedad0"), [rfx, rfy + 0.3, rfz])
		if rfx + 1.8 < -63.2:
			ctx.wires.add(ctx.geo.catenary([rfx, rfy + 0.52, rfz], [rfx + 1.8, rfy + 0.52, rfz], 0.1, 6), {"width": 0.014, "color": "#e6c34a"})
		rfx += 1.8
	# ------------------------------------------------------------ flora hook: flowers on the mound
	var park_flora := func(F) -> void:
		for i in 1500:
			var a: float = F.r.f() * PI * 2.0
			var d: float = sqrt(F.r.f()) * 1.05
			var px: float = M.x + cos(a) * M.rx * d
			var pz: float = M.z + sin(a) * M.rz * d
			if Common.path_dist(px, pz).d < 1.2 or sqrt((px - top.x) ** 2 + (pz - top.z) ** 2) < 2.2:
				continue
			var near := false
			for e in shrubs:
				if sqrt((e.x - px) ** 2 + (e.z - pz) ** 2) < e.s * 1.2:
					near = true
					break
			if near:
				continue
			var y: float = C.terrain_h(px, pz)
			var u: float = F.r.f()
			if u < 0.3:
				F.add_tuft(px, pz, 0.8, F.TUFT.short, y)
			elif u < 0.82:
				var cells := [F.FLW.dandelion, F.FLW.clover, F.FLW.violet, F.FLW.henbit, F.FLW.fleabane, F.FLW.speedwell]
				F.add_flower(px, pz, cells[floori(F.r.f() * 6.0)], 1.0, y)
			else:
				F.add_mat(px, pz, F.MAT.clover if F.r.f() < 0.6 else F.MAT.speedwell, 1.0, y)
	return {"isParkMound": is_park_mound, "parkFlora": park_flora, "top": top}
