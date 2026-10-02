# railway/trackside.js: corridor ground strips, cable troughs, maintenance walkway, drainage channels,
# corridor fences with colliders, warning and emergency signs, signals with red and green lamps, km
# posts, speed limit signs, equipment cabinets, reflectors, spare rails and stacked spare sleepers.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Track = preload("res://addons/sakuragaoka_station/world/railway/track.gd")


static func _rail_merged(path: Array, caps: Array, lift: float = 0.0) -> T.Geometry:
	var rg := Track.rail_geo(path, null, caps, lift)
	return Geo.merge_geometries([rg.side, rg.top, rg.head])


static func build_trackside(ctx, root, TX, E: Dictionary, track: Dictionary, cat: Dictionary) -> Dictionary:
	var mat = ctx.mat
	var L = ctx.L
	var physics = ctx.physics
	var k = ctx.kit(root)
	var r = ctx.rng("rw-side")
	var M := {
		"strip": mat.toon("#ffffff", {"map": TX.strip, "paint": 0.05, "polygonOffset": -1}),
		"trough": mat.toon("#ffffff", {"map": TX.trough, "paint": 0.05}),
		"troughSide": mat.toon("#aaa79f", {"paint": 0.05}),
		"slab": mat.toon("#ffffff", {"map": TX.slab, "paint": 0.05}),
		"conc": mat.toon("#bdbab2", {"paint": 0.08}),
		"concDark": mat.toon("#8e8b84", {"paint": 0.08}),
		"wet": mat.toon("#77766f", {"paint": 0.08}),
		"whiteFence": mat.toon("#e7e3d9", {"paint": 0.08}),
		"fencePost": mat.toon("#4e7a5c", {"paint": 0.05}),
		"fenceMesh": mat.foliage("#ffffff", TX.mesh, {"name": "rw-fence-mesh", "alphaTest": 0.42, "paint": 0.05}),
		"steel": mat.toon("#9aa1a8", {"paint": 0.05}),
		"steelDark": mat.toon("#6d747c", {"paint": 0.05}),
		"sigBoard": mat.toon("#36333b", {"paint": 0.05}),
		"sigHood": mat.toon("#2f2c34", {"side": "double", "paint": 0.05}),
		"lensG": mat.toon("#2e5a4d"), "lensY": mat.toon("#6a5b30"), "lensR": mat.toon("#6c3636"),
		"litG": mat.emissive("#5ff0b8", 2.3), "litR": mat.emissive("#ff5646", 2.3),
		"box": mat.toon("#b3b8bb", {"paint": 0.05}),
		"pipeDark": mat.toon("#4b4850", {"paint": 0.05}),
		"white": mat.toon("#eeebe3"),
		"reflR": mat.toon("#e0503f", {"emissive": "#6a3418", "emissiveIntensity": 0.55}),
		"reflY": mat.toon("#f0b43a", {"emissive": "#6a3418", "emissiveIntensity": 0.55}),
		"wood": mat.toon("#7d6552", {"paint": 0.08}),
		"pc": track.M.pc,
		"railSide": track.M.railSide, "railTop": track.M.railTop,
		"signBack": mat.toon("#9ea4aa", {"paint": 0.05}),
	}
	M.fenceMesh.alphaToCoverage = true

	var gy := func(x: float, z: float) -> float:
		return L.height_at(x, z)
	var S := {"strip": [-39.2, -34.0], "trough": -38.55, "walk": -36.75, "equip": -35.75, "drain": -34.95, "fence": -33.8}
	var zs := func(v: float, side: float) -> float:
		return v if side > 0 else -86.0 - v
	var STRIP_X := [[-420.0, -17.5], [50.5, 420.0]]
	var DETAIL_X := [[-165.0, -17.5], [50.5, 172.0]]
	var in_ranges := func(x: float, R: Array) -> bool:
		for ab in R:
			if x >= ab[0] and x <= ab[1]:
				return true
		return false
	var tex_box := func(w: float, h: float, d: float, m, pos: Array, u_rep: float = 1.0, v_rep: float = 1.0):
		var g := Geo.box(w, h, d)
		var uv: T.Attr = g.attributes.uv
		for i in uv.count():
			uv.set_xy(i, uv.get_x(i) * u_rep, uv.get_y(i) * v_rep)
		return k.mesh(g, m, pos)
	var tex_plane := func(reg: Dictionary, w: float, h: float, pos: Array, rot_y: float, back = null, depth: float = 0.014):
		if back == null:
			back = M.white
		var g = k.group(pos, rot_y)
		var kk = ctx.kit(g)
		kk.box(w + 0.02, h + 0.02, depth, back, [0, 0, 0])
		TX.sign_mesh(kk, reg, w, h, [0, 0, depth / 2.0 + 0.003])
		return g

	# ground strips
	for side in [1.0, -1.0]:
		var z_toe: float = S.strip[0] if side > 0 else zs.call(S.strip[0], -1)
		var z_fence: float = S.strip[1] if side > 0 else zs.call(S.strip[1], -1)
		for ab in STRIP_X:
			var x0: float = ab[0]
			while x0 < ab[1] - 1e-6:
				var x1 := minf(ab[1], x0 + 40.0)
				var pos := PackedFloat32Array()
				var uv := PackedFloat32Array()
				for x in [x0, x1]:
					for z in [z_toe, z_fence]:
						pos.append(x); pos.append(gy.call(x, z) + 0.012); pos.append(z)
						uv.append(x / 8.0); uv.append((z - z_toe) / (z_fence - z_toe))
				var g := T.Geometry.new()
				g.set_attribute("position", T.Attr.new(pos, 3))
				g.set_attribute("uv", T.Attr.new(uv, 2))
				g.set_index([0, 1, 3, 0, 3, 2])
				g.set_attribute("normal", T.Attr.new(PackedFloat32Array([0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0]), 3))
				var ax := pos[3] - pos[0]
				var az := pos[5] - pos[2]
				var bx := pos[9] - pos[0]
				var bz := pos[11] - pos[2]
				if az * bx - ax * bz < 0:
					g.set_index([0, 3, 1, 0, 2, 3])
				var m := T.MeshObj.new(g, M.strip)
				m.receive_shadow = true
				root.add(m)
				x0 += 40.0

	# troughs, walkway slabs, drainage channels
	for side in [1.0, -1.0]:
		for ab in DETAIL_X:
			var a: float = ab[0]
			var b: float = ab[1]
			var x0 := a
			while x0 < b - 1e-6:
				var x1 := minf(b, x0 + 20.0)
				var length := x1 - x0
				var xc := (x0 + x1) / 2.0
				var zt: float = zs.call(S.trough, side)
				var g0: float = gy.call(xc, zt)
				tex_box.call(length, 0.17, 0.36, M.trough, [xc, g0 - 0.015, zt], length, 1)
				var zw: float = zs.call(S.walk, side)
				tex_box.call(length - 0.04, 0.05, 0.6, M.slab, [xc, gy.call(xc, zw) + 0.015, zw], length / 1.2, 1)
				var zd: float = zs.call(S.drain, side)
				var gd: float = gy.call(xc, zd)
				k.box(length, 0.15, 0.07, M.conc, [xc, gd + 0.045, zd - 0.2])
				k.box(length, 0.15, 0.07, M.conc, [xc, gd + 0.045, zd + 0.2])
				k.box(length, 0.03, 0.34, M.wet, [xc, gd + 0.02, zd])
				var x: float = x0 + 4.0 + r.f() * 6.0
				while x < x1 - 1.0:
					tex_box.call(0.95, 0.06, 0.52, M.trough, [x, gd + 0.15, zd], 1, 1)
					x += 9.0 + r.f() * 6.0
				x0 += 20.0
			for x in [a + 0.5, b - 0.5]:
				var zt: float = zs.call(S.trough, side)
				k.boxb(0.8, 0.12, 0.7, M.conc, [x, gy.call(x, zt) - 0.02, zt])
				k.box(0.66, 0.012, 0.56, M.concDark, [x, gy.call(x, zt) + 0.1, zt])

	# fences
	var colliders := []
	var add_fence_collider := func(x0: float, x1: float, z: float) -> void:
		var a := x0
		while a < x1 - 1e-6:
			var b := minf(x1, a + 8.0)
			var g: float = gy.call((a + b) / 2.0, z)
			physics.addBox((a + b) / 2.0, z, b - a, 0.26, 0, g - 1, g + 2.3)
			colliders.append([a, b, z])
			a += 8.0
	var post_geo := _rail_merged([[0, 0], [1.42, 0]], [false, true])
	post_geo.rotate_z(PI / 2.0)
	post_geo.rotate_y(-PI / 2.0)
	var post_items := []
	var mesh_post_items := []
	var build_old_rail_fence := func(x0: float, x1: float, z: float, face_north: bool) -> void:
		var n := maxi(1, int(T.js_round((x1 - x0) / 2.4)))
		for i in n + 1:
			var x := x0 + (x1 - x0) * i / n
			post_items.append({"x": x, "y": gy.call(x, z) - 0.26, "z": z, "ry": 0.0 if face_north else PI})
		var a := x0
		while a < x1 - 1e-6:
			var b := minf(x1, a + 20.0)
			for h in [0.42, 0.9]:
				var g := _rail_merged([[a, z], [b, z]], [false, false], gy.call((a + b) / 2.0, z) + h)
				var m := T.MeshObj.new(g, M.whiteFence)
				m.cast_shadow = true
				m.receive_shadow = true
				root.add(m)
			var x := a + 1.2
			while x < b:
				var g: float = gy.call(x, z)
				k.cyl(0.045, 0.045, 0.012, M.reflR, [x, g + 0.72, z + (0.05 if face_north else -0.05)], [PI / 2.0, 0, 0], 12)
				x += 9.6
			a += 20.0
		add_fence_collider.call(x0, x1, z)
	var build_mesh_fence := func(x0: float, x1: float, z: float, outward: float) -> void:
		var n := maxi(1, int(T.js_round((x1 - x0) / 2.0)))
		for i in n + 1:
			var x := x0 + (x1 - x0) * i / n
			mesh_post_items.append({"x": x, "y": gy.call(x, z) - 0.1, "z": z})
		var a := x0
		while a < x1 - 1e-6:
			var b := minf(x1, a + 20.0)
			var length := b - a
			var xc := (a + b) / 2.0
			var g: float = gy.call(xc, z)
			k.box(length, 0.2, 0.16, M.conc, [xc, g + 0.02, z])
			k.cyl(0.022, 0.022, length, M.fencePost, [xc, g + 1.55, z], [0, 0, PI / 2.0], 6)
			k.cyl(0.012, 0.012, length, M.fencePost, [xc, g + 0.14, z], [0, 0, PI / 2.0], 5)
			var pg := Geo.plane(length, 1.42)
			var uv: T.Attr = pg.attributes.uv
			for i in uv.count():
				uv.set_xy(i, uv.get_x(i) * length / 0.3, uv.get_y(i) * 1.42 / 0.3)
			var pm := T.MeshObj.new(pg, M.fenceMesh)
			pm.position = Vector3(xc, g + 0.84, z + outward * 0.035)
			pm.receive_shadow = true
			pm.cast_shadow = false
			ctx.no_outline(pm)
			root.add(pm)
			if absf(xc) < 200.0:
				var x := a + 1.0
				while x < b:
					k.cyl(0.04, 0.04, 0.012, M.reflY, [x, g + 1.2, z + outward * 0.05], [PI / 2.0, 0, 0], 10)
					x += 10.0
			a += 20.0
		add_fence_collider.call(x0, x1, z)
	for ab in STRIP_X:
		var a: float = ab[0]
		var b: float = ab[1]
		var oa := maxf(a, -110.0)
		var ob := minf(b, 110.0)
		if ob > oa:
			build_old_rail_fence.call(oa, ob, S.fence, true)
		if a < -110.0:
			build_mesh_fence.call(a, minf(b, -110.0), S.fence, 1.0)
		if b > 110.0:
			build_mesh_fence.call(maxf(a, 110.0), b, S.fence, 1.0)
		build_mesh_fence.call(a, b, zs.call(S.fence, -1), -1.0)
	var im = Track.make_instanced(post_geo, M.whiteFence, post_items)
	if im:
		im.name = "rw-oldrail-posts"
		root.add(im)
	var npg := Geo.cylinder(0.032, 0.032, 1.72, 6, 1, true)
	npg.translate(0, 0.86, 0)
	var im2 = Track.make_instanced(npg, M.fencePost, mesh_post_items)
	if im2:
		im2.name = "rw-net-posts"
		root.add(im2)
	physics.addAABB(-17.5, -52.35, -17.2, -33.65, -2, 3)
	physics.addAABB(50.2, -52.35, 50.5, -33.65, -2, 3)
	physics.addAABB(-7.2, -46.5, -6.95, -39.5, -2, 3)
	physics.addWalkBox((-17.2 + 50.2) / 2.0, -43, 50.2 + 17.2, 6.7, 0, -0.02)

	# fence signs
	var fence_sign := func(x: float, south: bool, reg: Dictionary, w: float, h: float, y: float = 0.86) -> void:
		var z: float = S.fence + 0.085 if south else zs.call(S.fence, -1) - 0.07
		tex_plane.call(reg, w, h, [x, gy.call(x, z) + y, z], 0.0 if south else PI, M.white, 0.012)
	var xs1 := [-88, -62, -38, 62, 86]
	for i in xs1.size():
		fence_sign.call(float(xs1[i]), true, TX.sign.kiken if i % 2 else TX.sign.tachiiri, 0.6, 0.45)
	var xs2 := [-84, -56, -30, 58, 82]
	for i in xs2.size():
		fence_sign.call(float(xs2[i]), false, TX.sign.tachiiri if i % 2 else TX.sign.kiken, 0.6, 0.45, 1.05)
	fence_sign.call(-19.4, true, TX.sign.emergency, 0.5, 0.625, 0.9)
	fence_sign.call(-19.4, false, TX.sign.emergency, 0.5, 0.625, 1.05)

	# signals
	var signals := []
	var build_signal := func(o: Dictionary) -> void:
		var x: float = o.x
		var z: float = o.z
		var face: float = o.face
		var label: String = o.label
		var gyb: float = -0.05 if o.get("between", false) else gy.call(x, z)
		var head_y: float = o.headY
		var mast_top := head_y + 0.72
		k.boxb(0.42, 0.34, 0.42, M.conc, [x, gyb - 0.2, z])
		k.cyl(0.07, 0.078, mast_top - gyb - 0.14, M.steel, [x, (mast_top + gyb + 0.14) / 2.0, z], null, 10)
		k.cyl(0.055, 0.08, 0.06, M.steelDark, [x, mast_top + 0.03, z], null, 10)
		k.rbox(0.2, 0.3, 0.16, 0.03, M.box, [x - face * 0.14, gyb + 0.9, z])
		if not o.get("between", false):
			for s in [-1, 1]:
				k.box(0.025, head_y - 0.6 - gyb, 0.025, M.steelDark, [x - face * 0.16, (head_y - 0.6 + gyb) / 2.0 + 0.3, z + s * 0.17])
			var y := gyb + 0.5
			while y < head_y - 0.5:
				k.box(0.02, 0.02, 0.34, M.steelDark, [x - face * 0.16, y, z])
				y += 0.3
			k.box(0.5, 0.04, 0.6, M.steelDark, [x - face * 0.05, head_y - 0.62, z])
		var rot_y := PI / 2.0 if face > 0 else -PI / 2.0
		var hx := x + face * 0.13
		var hz: float = z + o.get("headDz", 0.0)
		var head = k.group([hx, head_y, hz], rot_y)
		var kh = ctx.kit(head)
		kh.rbox(0.28, 1.0, 0.2, 0.04, M.steelDark, [0, 0, -0.12])
		kh.rbox(0.4, 1.12, 0.05, 0.04, M.sigBoard, [0, 0, 0])
		var hood_geo := Geo.cylinder(0.1, 0.1, 0.16, 14, 1, true)
		for lens in [[0.34, M.lensG], [0.0, M.lensY], [-0.34, M.lensR]]:
			kh.cyl(0.082, 0.082, 0.02, lens[1], [0, lens[0], 0.035], [PI / 2.0, 0, 0], 16)
			var hood = kh.mesh(hood_geo, M.sigHood, [0, lens[0], 0.105], [PI / 2.0, 0, 0])
			hood.cast_shadow = true
		tex_plane.call(TX.plate([{"t": label, "s": 50}], "sig-" + label, 256, 96), 0.3, 0.11, [hx + face * 0.02, head_y - 0.7, hz], rot_y, M.white, 0.012)
		var dyn := T.Group.new()
		dyn.position = Vector3(hx, head_y, hz)
		dyn.rotation.y = rot_y
		var disc := Geo.cylinder(0.078, 0.078, 0.012, 16)
		var lit_g := T.MeshObj.new(disc, M.litG)
		lit_g.position = Vector3(0, 0.34, 0.05)
		lit_g.rotation.x = PI / 2.0
		var lit_r := T.MeshObj.new(disc, M.litR)
		lit_r.position = Vector3(0, -0.34, 0.05)
		lit_r.rotation.x = PI / 2.0
		var glow_tex = TX.glow
		var gG := T.MeshObj.new(Geo.plane(0.5, 0.5), mat.emissive("#5ff0b8", 1.4, {"map": glow_tex, "transparent": true, "depthWrite": false}))
		var gR := T.MeshObj.new(Geo.plane(0.5, 0.5), mat.emissive("#ff5646", 1.4, {"map": glow_tex, "transparent": true, "depthWrite": false}))
		lit_g.add(gG)
		gG.rotation.x = -PI / 2.0
		gG.position = Vector3(0, 0.02, 0)
		lit_r.add(gR)
		gR.rotation.x = -PI / 2.0
		gR.position = Vector3(0, 0.02, 0)
		dyn.add(lit_g)
		dyn.add(lit_r)
		ctx.no_outline(gG)
		ctx.no_outline(gR)
		ctx.add(dyn)
		lit_g.visible = false
		lit_r.visible = true
		physics.addCylinder(x, z, 0.24, gyb - 1, mast_top)
		var s := o.duplicate()
		s["litG"] = lit_g
		s["litR"] = lit_r
		s["state"] = false
		signals.append(s)
	TX.glow = ctx.tex.draw(64, 64, null, {"key": "rw-glow"})
	build_signal.call({"id": "A-start", "track": "A", "x": -4.5, "z": -43.0, "face": 1.0, "headY": 3.35, "label": "上り出発", "between": true, "kind": "start", "dir": -1})
	build_signal.call({"id": "B-start", "track": "B", "x": 44.5, "z": -43.0, "face": -1.0, "headY": 3.35, "label": "下り出発", "between": true, "kind": "start", "dir": 1})
	build_signal.call({"id": "A-home", "track": "A", "x": 140.0, "z": -39.0, "face": 1.0, "headY": 3.9, "label": "上り場内", "kind": "home", "dir": -1, "headDz": -0.1})
	build_signal.call({"id": "B-home", "track": "B", "x": -163.0, "z": -47.0, "face": -1.0, "headY": 3.9, "label": "下り場内", "kind": "home", "dir": 1, "headDz": 0.1})

	# km posts every 100 m
	var km_post := func(x: float, south: bool) -> void:
		var z := -38.92 if south else -47.08
		var g: float = gy.call(x, z)
		var kmv := 8.5 + (x + 60.0) / 1000.0
		var km := int(floorf(kmv + 1e-6))
		var hm := int(T.js_round((kmv - km) * 10.0)) % 10
		k.boxb(0.17, 0.78, 0.17, M.white, [x, g - 0.2, z])
		k.box(0.2, 0.05, 0.2, M.concDark, [x, g - 0.02, z])
		var reg: Dictionary = TX.km(km, hm)
		for f in [[0.087, 0.0, PI / 2.0], [-0.087, 0.0, -PI / 2.0], [0.0, 0.087 if south else -0.087, 0.0 if south else PI]]:
			TX.sign_mesh(k, reg, 0.15, 0.225, [x + f[0], g + 0.42, z + f[1]], [0, f[2], 0])
	for x in [-360.0, -260.0, -160.0, -60.0, 240.0, 340.0]:
		km_post.call(x, true)
	km_post.call(140.0, false)

	# speed limit signs
	var speed_sign := func(x: float, south: bool, v: int) -> void:
		var z := -38.92 if south else -47.08
		var g: float = gy.call(x, z)
		var face := 1.0 if south else -1.0
		k.boxb(0.26, 0.2, 0.26, M.conc, [x, g - 0.1, z])
		k.cyl(0.035, 0.035, 1.75, M.steel, [x, g + 0.9, z], null, 8)
		tex_plane.call(TX.speed(v), 0.4, 0.4, [x + face * 0.05, g + 1.62, z], PI / 2.0 if face > 0 else -PI / 2.0, M.signBack, 0.02)
	speed_sign.call(128.0, true, 45)
	speed_sign.call(-40.0, true, 60)
	speed_sign.call(56.0, false, 45)
	speed_sign.call(-110.0, false, 60)

	# equipment cabinets with conduits to the trough
	var cabinet := func(x: float, side: float, big: bool = true) -> void:
		var z: float = zs.call(S.equip, side)
		var g: float = gy.call(x, z)
		var w := 0.86 if big else 0.56
		var h := 1.32 if big else 0.86
		var d := 0.5 if big else 0.36
		k.boxb(w + 0.2, 0.14, d + 0.16, M.conc, [x, g - 0.02, z])
		k.rbox(w, h, d, 0.035, M.box, [x, g + 0.12 + h / 2.0, z])
		k.rbox(w + 0.08, 0.05, d + 0.1, 0.02, M.steelDark, [x, g + 0.12 + h + 0.02, z])
		var face_z := z + side * (d / 2.0 + 0.004)
		TX.sign_mesh(k, TX.sign.box, w * 0.92, h * 0.94, [x, g + 0.12 + h / 2.0, face_z], [0, 0.0 if side > 0 else PI, 0])
		var zt: float = zs.call(S.trough, side)
		var zc0 := z - side * (d / 2.0 + 0.05)
		k.cyl(0.035, 0.035, 0.5, M.pipeDark, [x + w * 0.3, g + 0.2, zc0], null, 8)
		k.box(0.07, 0.06, absf(zt - zc0), M.pipeDark, [x + w * 0.3, g + 0.02, (zt + zc0) / 2.0])
		physics.addBox(x, z, w + 0.2, d + 0.16, 0, g - 1, g + h + 0.2)
	cabinet.call(-32.0, 1.0); cabinet.call(-30.8, 1.0, false); cabinet.call(-76.0, 1.0); cabinet.call(58.0, 1.0); cabinet.call(59.2, 1.0, false); cabinet.call(132.0, 1.0)
	cabinet.call(-38.0, -1.0); cabinet.call(72.0, -1.0); cabinet.call(120.0, -1.0); cabinet.call(121.1, -1.0, false); cabinet.call(-166.0, -1.0)

	# white delineator posts with red reflectors at the corridor ends
	for xs in [[-20.2, 1.0], [-23.4, 1.0], [-20.2, -1.0], [-23.4, -1.0], [53.0, 1.0], [56.2, 1.0], [53.0, -1.0], [56.2, -1.0]]:
		var x: float = xs[0]
		var z: float = zs.call(-38.95, xs[1])
		var g: float = gy.call(x, z)
		k.boxb(0.07, 0.72, 0.07, M.white, [x, g - 0.12, z])
		for s in [-1, 1]:
			k.cyl(0.03, 0.03, 0.01, M.reflR, [x + s * 0.04, g + 0.48, z], [0, 0, PI / 2.0], 10)

	# spare rails on wooden blocks, stacked spare sleepers
	var spare_rails := func(x0: float, x1: float, side: float, dzs: Array) -> void:
		var z0: float = zs.call(S.equip, side)
		var x := x0 + 0.6
		while x < x1:
			k.boxb(0.14, 0.09, 0.62, M.wood, [x, gy.call(x, z0) - 0.01, z0])
			x += 4.1
		for dz in dzs:
			var rg := Track.rail_geo([[x0, z0 + dz], [x1, z0 + dz]], null, [true, true], gy.call(x0, z0) + 0.08)
			for g in [rg.side, rg.top, rg.head]:
				var m := T.MeshObj.new(g, M.railSide)
				m.cast_shadow = true
				m.receive_shadow = true
				root.add(m)
	spare_rails.call(78.0, 103.0, -1.0, [-0.12, 0.12])
	spare_rails.call(-72.0, -47.0, 1.0, [-0.14, 0.1])
	var sx0 := -86.5
	var sz0: float = zs.call(S.equip, 1) - 0.05
	var sg: float = gy.call(sx0, sz0)
	for layer in 3:
		var y := sg + 0.06 + layer * 0.22
		for dx in [-0.8, 0.8]:
			k.boxb(0.1, 0.05, 0.62, M.wood, [sx0 + dx, y - 0.05, sz0])
		for dz in [-0.14, 0.14]:
			var m = k.box(2.0, 0.17, 0.22, M.pc, [sx0 + (r.f() - 0.5) * 0.06, y + 0.085, sz0 + dz])
			m.rotation.y = (r.f() - 0.5) * 0.03
	physics.addBox(sx0, sz0, 2.2, 0.8, 0, sg - 1, sg + 1)

	for c in cat.colliders:
		physics.addCylinder(c.x, c.z, c.r, -2, 9)

	return {"signals": signals, "fenceColliders": colliders, "S": S, "zs": zs, "STRIP_X": STRIP_X, "DETAIL_X": DETAIL_X, "inRanges": in_ranges}
