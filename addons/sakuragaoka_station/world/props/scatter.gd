# props/scatter.js: scattered street props: V5 bench, gashapon row, 防災倉庫, 消火器 boxes, traffic
# cones + repair notice by a manhole on R4, and a ゴミ集積所 on the R4 rail-side strip.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")

## The canvas textures as sized stand-ins: [name, width, height, key, repeat or null].
const TEXTURES := [
	["fire", 128, 208, "props.fire", null],
	["bench", 512, 64, "props.bench.ad", null],
	["wood", 256, 64, "props.bench.wood", null],
	["neko", 256, 160, "props.gacha.neko", null],
	["train", 256, 160, "props.gacha.train", null],
	["wagashi", 256, 160, "props.gacha.wagashi", null],
	["gachaHead", 512, 64, "props.gacha.head", null],
	["price", 128, 48, "props.gacha.price", null],
	["ribs", 128, 128, "props.cab.ribs", null],
	["cabLabel", 512, 128, "props.cab.label", null],
	["cabList", 192, 160, "props.cab.list", null],
	["evac", 192, 256, "props.evac", null],
	["works", 256, 384, "props.works", null],
	["manhole", 256, 256, "props.manhole", null],
	["bar", 128, 16, "props.conebar", [4, 1]],
	["mesh", 128, 128, "props.garbage.mesh", [1, 1]],
	["gomi", 256, 192, "props.garbage.sign", null],
]


static func textures(ctx) -> Dictionary:
	var t := {}
	for e in TEXTURES:
		var opts := {"key": e[3]}
		if e[4] != null:
			opts["repeat"] = e[4]
		t[e[0]] = ctx.tex.draw(e[1], e[2], null, opts)
	t["cards"] = [t.neko, t.train, t.wagashi]
	return t


## Red 消火器 box on a short post. p = {x,z,rotY} (box faces local +Z).
static func fire_box(ctx, H, p: Dictionary, y_fixed = null) -> void:
	var mat = ctx.mat
	var physics = ctx.physics
	var t := textures(ctx)
	var y0: float = y_fixed if y_fixed != null else H.footprint(p.x, p.z, 0.3, 0.24, p.rotY).max
	var g = H.place(p.x, y0, p.z, p.rotY)
	var k = ctx.kit(g)
	var steel = mat.toon("#9aa1a8", {"paint": 0.03})
	var red = mat.toon("#d9463b", {"paint": 0.04})
	k.box(0.18, 0.02, 0.18, steel, [0, 0.0, 0])
	k.cyl(0.028, 0.028, 0.5, steel, [0, 0.25, 0], null, 10)
	k.rbox(0.32, 0.52, 0.2, 0.02, red, [0, 0.76, 0])
	k.box(0.35, 0.03, 0.23, red, [0, 1.035, 0.0], [0.08, 0, 0])
	k.plane(0.26, 0.42, mat.toon("#ffffff", {"map": t.fire, "paint": 0.02}), [0, 0.77, 0.1015])
	k.box(0.1, 0.025, 0.03, steel, [0, 0.53, 0.11])
	physics.addCylinder(p.x, p.z, 0.2, y0 - 0.1, y0 + 1.05)


## matrixWorld of a scene-graph object from its local matrices (Object3D.updateWorldMatrix(true)).
static func world_of(o) -> Transform3D:
	var m := Transform3D()
	var n = o
	while n != null:
		n.update_matrix()
		m = n.matrix * m
		n = n.parent()
	return m


static func build_scatter(ctx, H) -> void:
	var L = ctx.L
	var mat = ctx.mat
	var physics = ctx.physics
	var t := textures(ctx)
	var rnd = ctx.rng("props.scatter")
	var M := {
		"iron": mat.toon("#4d6457", {"paint": 0.04}),
		"bench": mat.toon("#ffffff", {"map": t.wood, "paint": 0.05}),
		"benchAd": mat.toon("#ffffff", {"map": t.bench, "paint": 0.04}),
		"steel": mat.toon("#9aa1a8", {"paint": 0.03}),
		"steelDark": mat.toon("#6d747c", {"paint": 0.03}),
		"concrete": mat.toon("#c4c2ba", {"paint": 0.08}),
		"ink": mat.toon("#3a3346", {"paint": 0}),
		"white": mat.toon("#eeeeea", {"paint": 0.02}),
		"glass": mat.glass({"tint": "#dde8ef", "opacity": 0.08, "streaks": true}),
	}

	# ---------------------------------------------------------------- V5 bench (seat y 0.44 above its floor)
	if true:
		var s: Dictionary = L.SPOTS.v5Bench
		var ln: float = s["len"] if s.get("len") else 1.5
		var fp: Dictionary = H.footprint(s.x, s.z, ln, 0.6, s.rotY)
		var g = H.place(s.x, fp.max, s.z, s.rotY)
		var k = ctx.kit(g)
		var seat_y: float = s.seatY if s.get("seatY") != null else 0.44
		var dfp: float = fp.max - fp.min
		for sx in [-1, 1]:
			var x: float = sx * (ln / 2.0 - 0.1)
			k.box(0.05, seat_y - 0.035 + dfp + 0.02, 0.05, M.iron, [x, (seat_y - 0.035 - dfp - 0.02) / 2.0, 0.2])
			k.box(0.05, 0.86 + dfp + 0.02, 0.05, M.iron, [x, (0.86 - dfp - 0.02) / 2.0, -0.21], [-0.1, 0, 0])
			k.box(0.05, 0.05, 0.5, M.iron, [x, seat_y - 0.06, -0.01])
			k.box(0.05, 0.035, 0.44, M.iron, [x, 0.64, 0.02])
			k.box(0.04, 0.2, 0.04, M.iron, [x, 0.53, 0.22])
			k.box(0.05, 0.03, 0.4, M.iron, [x, 0.08, 0.0])
		for i in 4:
			k.box(ln, 0.035, 0.095, M.bench, [0, seat_y - 0.0175, -0.165 + i * 0.11])
		k.box(ln, 0.1, 0.03, M.bench, [0, 0.58, -0.245], [-0.1, 0, 0])
		k.box(ln, 0.16, 0.03, M.bench, [0, 0.76, -0.265], [-0.1, 0, 0])
		k.plane(ln * 0.98, 0.15, M.benchAd, [0, 0.76, -0.2485], [-0.1, 0, 0])
		physics.addBox(s.x, s.z, ln + 0.05, 0.62, s.rotY, fp.min - 0.1, fp.max + 0.86)

	# ---------------------------------------------------------------- gashapon (capsule-toy machines) at the general store front
	if true:
		var s: Dictionary = L.SPOTS.gashapon
		var n: int = s.count if s.get("count") else 3
		var step := 0.47
		var total := n * step
		var fp: Dictionary = H.footprint(s.x, s.z, total + 0.1, 0.5, s.rotY)
		var g = H.place(s.x, fp.max, s.z, s.rotY)
		var k = ctx.kit(g)
		var drop: float = fp.max - fp.min + 0.03
		k.box(total + 0.04, 0.05, 0.46, M.steelDark, [0, 0.275, 0])
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				k.box(0.04, 0.3 + drop, 0.04, M.steelDark, [sx * (total / 2.0 - 0.02), (0.3 - drop) / 2.0, sz * 0.2])
		k.box(total, 0.03, 0.03, M.steelDark, [0, 0.06, 0.2])
		var frames := ["#ec7f72", "#72a9de", "#f0cd5c", "#9ad7a8"]
		var cap_cols := ["#f28b9b", "#7fc4e8", "#f6d55c", "#9ad7a8", "#c9a7e8", "#f7a86b", "#f5f0e6"]
		var cap_m := []
		for j in n:
			var x := -total / 2.0 + step * (j + 0.5)
			var mg := T.Group.new()
			mg.position = Vector3(x, 0.3, 0)
			g.add(mg)
			var m = ctx.kit(mg)
			var fm = mat.toon(frames[j % frames.size()], {"paint": 0.04})
			m.rbox(0.44, 0.46, 0.42, 0.025, fm, [0, 0.23, 0])
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					m.box(0.03, 0.42, 0.03, fm, [sx * 0.205, 0.67, sz * 0.195])
			m.rbox(0.44, 0.05, 0.42, 0.02, fm, [0, 0.885, 0])
			m.box(0.38, 0.012, 0.38, M.white, [0, 0.466, 0])
			var gl = m.plane(0.38, 0.4, M.glass, [0, 0.66, 0.2])
			ctx.no_outline(gl)
			gl.cast_shadow = false
			for sx in [-1, 1]:
				var gs = m.plane(0.36, 0.4, M.glass, [sx * 0.21, 0.66, 0], [0, sx * PI / 2.0, 0])
				ctx.no_outline(gs)
				gs.cast_shadow = false
			m.box(0.38, 0.4, 0.01, M.white, [0, 0.66, -0.19])
			m.plane(0.34, 0.2125, mat.emissive("#ffffff", 0.92, {"map": t.cards[j % t.cards.size()]}), [0, 0.76, 0.17])
			m.rbox(0.25, 0.2, 0.02, 0.01, M.steel, [0, 0.3, 0.215])
			m.plane(0.2, 0.075, mat.toon("#ffffff", {"map": t.price, "paint": 0.01}), [0, 0.365, 0.2265])
			m.cyl(0.058, 0.058, 0.035, M.white, [0, 0.27, 0.24], [PI / 2.0, 0, 0], 20)
			m.box(0.11, 0.022, 0.02, M.steelDark, [0, 0.27, 0.265], [0, 0, 0.35 + j * 0.6])
			m.box(0.018, 0.04, 0.012, M.ink, [0.09, 0.265, 0.232])
			m.box(0.13, 0.09, 0.02, M.ink, [0, 0.09, 0.212])
			m.box(0.12, 0.08, 0.01, mat.toon("#8e98a8", {"paint": 0.01}), [0, 0.09, 0.224], [-0.12, 0, 0])
			# capsule pile (merged below)
			for ly in 3:
				for ix in 5:
					for iz in 4:
						if ly == 2 and rnd.f() < 0.45:
							continue
						var px: float = -0.16 + ix * 0.08 + (rnd.f() - 0.5) * 0.02
						var pz: float = -0.15 + iz * 0.1 + (rnd.f() - 0.5) * 0.03
						var py: float = 0.472 + 0.03 + ly * 0.05 + (rnd.f() - 0.5) * 0.012
						var r0: float = rnd.f() * 6.0
						var r1: float = rnd.f() * 6.0
						var r2: float = rnd.f() * 6.0
						cap_m.append({"g": mg, "pos": Vector3(px, py, pz), "rot": Vector3(r0, r1, r2), "col": cap_cols[int(rnd.f() * cap_cols.size())]})
		# lit header
		k.box(total, 0.16, 0.1, M.white, [0, 0.3 + 0.91 + 0.08, 0])
		k.plane(total - 0.04, 0.13, mat.emissive("#ffffff", 1.05, {"map": t.gachaHead}), [0, 0.3 + 0.91 + 0.08, 0.0505])
		# all capsules -> ONE vertex-coloured mesh (coloured bottom half, clear-white top half)
		var bot: T.Geometry = Geo.sphere(0.029, 9, 3, 0, PI * 2.0, PI / 2.0, PI / 2.0).to_non_indexed()
		var top: T.Geometry = Geo.sphere(0.029, 9, 3, 0, PI * 2.0, 0, PI / 2.0).to_non_indexed()
		var P := PackedFloat32Array()
		var N := PackedFloat32Array()
		var C := PackedFloat32Array()
		var cw := T.color("#f3f5f7")
		var inv: Transform3D = world_of(g).affine_inverse()
		for e in cap_m:
			var m4: Transform3D = inv * world_of(e.g) * T.compose(e.pos, T.quat_from_euler(e.rot), Vector3.ONE)
			var nm: Basis = m4.basis.inverse().transposed()
			var c := T.color(e.col)
			for pair in [[bot, c], [top, cw]]:
				var geo: T.Geometry = pair[0]
				var col: Color = pair[1]
				var p: T.Attr = geo.attributes.position
				var nn: T.Attr = geo.attributes.normal
				for jj in p.count():
					var v: Vector3 = m4 * p.v3(jj)
					P.append_array([v.x, v.y, v.z])
					v = (nm * nn.v3(jj)).normalized()
					N.append_array([v.x, v.y, v.z])
					C.append_array([col.r, col.g, col.b])
		var cg := T.Geometry.new()
		cg.set_attribute("position", T.Attr.new(P, 3))
		cg.set_attribute("normal", T.Attr.new(N, 3))
		cg.set_attribute("color", T.Attr.new(C, 3))
		var uvz := PackedFloat32Array()
		uvz.resize(P.size() / 3 * 2)
		cg.set_attribute("uv", T.Attr.new(uvz, 2))
		var caps = k.mesh(cg, mat.toon("#ffffff", {"vertexColors": true, "paint": 0.02}), [0, 0, 0])
		caps.cast_shadow = false
		physics.addBox(s.x, s.z, total + 0.06, 0.48, s.rotY, fp.min - 0.1, fp.max + 1.4)

	# ---------------------------------------------------------------- 防災倉庫 (disaster-supply storehouse) + evac sign + extinguisher
	if true:
		var s: Dictionary = L.SPOTS.disasterCabinet
		var fp: Dictionary = H.footprint(s.x, s.z, 1.96, 1.06, s.rotY)
		var y0: float = fp.max + 0.1
		var g = H.place(s.x, y0, s.z, s.rotY)
		var k = ctx.kit(g)
		k.boxb(1.98, y0 - fp.min + 0.06, 1.08, M.concrete, [0, fp.min - y0 - 0.06, 0])
		var body = mat.toon("#ffffff", {"map": t.ribs, "paint": 0.05})
		k.box(1.8, 1.72, 0.9, body, [0, 0.86, 0])
		k.box(1.92, 0.07, 1.02, mat.toon("#98a1a8", {"paint": 0.05}), [0, 1.755, 0.0], [-0.05, 0, 0])
		var door = mat.toon("#d3d8da", {"paint": 0.05})
		for sx in [-1, 1]:
			k.rbox(0.86, 1.52, 0.03, 0.01, door, [sx * 0.44, 0.84, 0.46])
			for i in 5:
				k.box(0.5, 0.018, 0.02, M.steelDark, [sx * 0.44, 0.22 + i * 0.045, 0.482], [0.5, 0, 0])
			k.box(0.03, 0.22, 0.035, M.steelDark, [sx * 0.06, 0.92, 0.49])
		k.cyl(0.018, 0.018, 0.03, M.steel, [0.12, 1.08, 0.485], [PI / 2.0, 0, 0], 10)
		k.plane(1.2, 0.3, mat.toon("#ffffff", {"map": t.cabLabel, "paint": 0.01}), [0, 1.42, 0.4775])
		k.plane(0.36, 0.3, mat.toon("#ffffff", {"map": t.cabList, "paint": 0.01}), [0.44, 1.0, 0.4775])
		k.box(1.84, 0.06, 0.94, M.steelDark, [0, 0.03, 0])
		physics.addBox(s.x, s.z, 1.98, 1.08, s.rotY, fp.min - 0.1, y0 + 1.8)
		var pe: Dictionary = H.to_world(s.x, s.z, s.rotY, 1.28, 0.25)
		fire_box(ctx, H, {"x": pe.x, "z": pe.z, "rotY": s.rotY - 0.15})
		var ps: Dictionary = H.to_world(s.x, s.z, s.rotY, -1.35, 0.35)
		var ys: float = H.footprint(ps.x, ps.z, 0.1, 0.1, 0).max
		var sg = H.place(ps.x, ys, ps.z, s.rotY + 0.1)
		var kk = ctx.kit(sg)
		kk.cyl(0.03, 0.03, 2.3, M.steel, [0, 1.15, 0], null, 10)
		kk.box(0.47, 0.62, 0.02, M.steel, [0, 1.95, 0.04])
		kk.plane(0.45, 0.6, mat.toon("#ffffff", {"map": t.evac, "paint": 0.01}), [0, 1.95, 0.0505])
		physics.addCylinder(ps.x, ps.z, 0.08, ys - 0.1, ys + 2.3)

	# ---------------------------------------------------------------- 消火器 boxes at a few corners
	var fb := func(x: float, z: float, rot_y: float) -> void: fire_box(ctx, H, {"x": x, "z": z, "rotY": rot_y})
	fb.call(-8.86, -60.7, -PI / 2.0)  # quiet corner by V4 (R2/R4)
	fb.call(-15.28, -18.4, PI / 2.0)  # R2 west side, by pole R2W
	if true:
		var f: Dictionary = L.street_frame(84.6, 1, 4.38)
		fb.call(f.x, f.z, f.rotY)  # main street, east sidewalk

	# ---------------------------------------------------------------- R4: manhole inspection with cones + notice
	if true:
		var cx := 6.2
		var cz := -55.05
		var y: float = L.height_at(cx, cz) + 0.012
		var mh = mat.toon("#ffffff", {"map": t.manhole, "paint": 0.03})
		var g = H.place(cx, y, cz, 0.3)
		var k = ctx.kit(g)
		var mhm = k.cyl(0.33, 0.33, 0.03, mh, [0, 0.0, 0], null, 28)
		mhm.cast_shadow = false
		var orange = mat.toon("#ec6f45", {"paint": 0.03})
		var white = mat.toon("#f4f2ee", {"paint": 0.01})
		var rubber = mat.toon("#4a4552", {"paint": 0.02})
		var cone_pts := [[-0.85, -0.6], [0.85, -0.6], [0.85, 0.62], [-0.85, 0.62]]
		var cone_at := func(lx: float, lz: float) -> Dictionary:
			var p: Dictionary = H.to_world(cx, cz, 0.3, lx, lz)
			var cy: float = L.height_at(p.x, p.z) + 0.012
			var cg = H.place(p.x, cy, p.z, rnd.f() * 3.0)
			var c = ctx.kit(cg)
			c.box(0.36, 0.035, 0.36, rubber, [0, 0.0175, 0])
			c.mesh(Geo.cylinder(0.028, 0.13, 0.64, 18), orange, [0, 0.035 + 0.32, 0])
			c.mesh(Geo.cylinder(0.075, 0.094, 0.1, 18), white, [0, 0.035 + 0.38, 0])
			c.mesh(Geo.cylinder(0.052, 0.066, 0.07, 18), white, [0, 0.035 + 0.52, 0])
			physics.addCylinder(p.x, p.z, 0.17, cy - 0.1, cy + 0.7)
			return {"x": p.x, "y": cy, "z": p.z}
		var cones := []
		for ab in cone_pts:
			cones.append(cone_at.call(ab[0], ab[1]))
		var bar_m = mat.toon("#ffffff", {"map": t.bar, "paint": 0.01})
		for ij in [[0, 1], [1, 2]]:
			var a := Vector3(cones[ij[0]].x, cones[ij[0]].y + 0.56, cones[ij[0]].z)
			var b := Vector3(cones[ij[1]].x, cones[ij[1]].y + 0.56, cones[ij[1]].z)
			var mid := (a + b) * 0.5
			var d := b - a
			var bar := T.MeshObj.new(Geo.cylinder(0.022, 0.022, d.length(), 10), bar_m)
			bar.position = mid
			bar.set_quaternion(T.quat_from_unit_vectors(Vector3(0, 1, 0), d.normalized()))
			bar.cast_shadow = true
			bar.receive_shadow = true
			ctx.add_static(bar)
		# A-frame notice facing westbound traffic (from the east), printed on both faces
		var sx := cx + 1.75
		var sz := cz + 0.25
		var ys: float = L.height_at(sx, sz) + 0.012
		var sg = H.place(sx, ys, sz, PI / 2.0 - 0.2)
		var frame = mat.toon("#e9e7e2", {"paint": 0.02})
		var works_mat = mat.toon("#ffffff", {"map": t.works, "paint": 0.01})
		for side in [1, -1]:
			# the two panels hinge together at the top, feet spread ~0.44 m apart
			var fg := T.Group.new()
			fg.rotation.x = -side * 0.2
			fg.position = Vector3(0, 0, side * 0.222)
			sg.add(fg)
			var f = ctx.kit(fg)
			f.box(0.6, 0.9, 0.02, frame, [0, 0.62, 0])
			f.plane(0.56, 0.84, works_mat, [0, 0.62, side * 0.0105], [0, 0.0 if side > 0 else PI, 0])
			for lx in [-0.29, 0.29]:
				f.box(0.03, 1.12, 0.03, M.steel, [lx, 0.54, -side * 0.025])
		physics.addBox(sx, sz, 0.66, 0.5, PI / 2.0 - 0.2, ys - 0.1, ys + 1.1)

	# ---------------------------------------------------------------- ゴミ集積所 on the R4 rail-side strip (faces the lane, north)
	if true:
		var gx := -27.5
		var gz := -53.0
		var rot := PI
		var fp: Dictionary = H.footprint(gx, gz, 1.9, 1.0, rot)
		var y0: float = fp.max + 0.06
		var g = H.place(gx, y0, gz, rot)
		var k = ctx.kit(g)
		k.boxb(1.9, y0 - fp.min + 0.08, 1.0, M.concrete, [0, fp.min - y0 - 0.08, 0])
		var green = mat.toon("#5d8f6c", {"paint": 0.04})
		var W2 := 0.8
		var D2 := 0.42
		var Hh := 0.86
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				k.box(0.035, Hh, 0.035, green, [sx * W2, Hh / 2.0, sz * D2])
		for y in [0.02, Hh]:
			for sz in [-1, 1]:
				k.box(W2 * 2.0, 0.03, 0.03, green, [0, y, sz * D2])
			for sx in [-1, 1]:
				k.box(0.03, 0.03, D2 * 2.0, green, [sx * W2, y, 0])
		var mesh_mat = mat.toon("#ffffff", {"map": t.mesh, "alphaTest": 0.5, "side": "double", "paint": 0.01})
		var panel := func(w: float, h: float, pos: Array, rot2: Array, rep: Array):
			var pg := Geo.plane(w, h)
			var uv: T.Attr = pg.attributes.uv
			for i in uv.count():
				uv.set_xy(i, uv.get_x(i) * rep[0], uv.get_y(i) * rep[1])
			var m = k.mesh(pg, mesh_mat, pos, rot2)
			ctx.no_outline(m)
			m.cast_shadow = false
			return m
		panel.call(W2 * 2.0, Hh, [0, Hh / 2.0, D2], [0, 0, 0], [W2 * 2.0 / 0.25, Hh / 0.25])
		panel.call(W2 * 2.0, Hh, [0, Hh / 2.0, -D2], [0, 0, 0], [W2 * 2.0 / 0.25, Hh / 0.25])
		for sx in [-1, 1]:
			panel.call(D2 * 2.0, Hh, [sx * W2, Hh / 2.0, 0], [0, PI / 2.0, 0], [D2 * 2.0 / 0.25, Hh / 0.25])
		# lid (closed, slightly domed frame)
		var lid := T.Group.new()
		lid.position = Vector3(0, Hh + 0.02, -D2)
		lid.rotation.x = -0.02
		g.add(lid)
		var kl = ctx.kit(lid)
		for sx in [-1, 1]:
			kl.box(0.03, 0.03, D2 * 2.0 + 0.04, green, [sx * (W2 + 0.02), 0, D2])
		kl.box(W2 * 2.0 + 0.07, 0.03, 0.03, green, [0, 0, D2 * 2.0 + 0.02])
		var lp := Geo.plane(W2 * 2.0, D2 * 2.0)
		var luv: T.Attr = lp.attributes.uv
		for i in luv.count():
			luv.set_xy(i, luv.get_x(i) * W2 * 2.0 / 0.25, luv.get_y(i) * D2 * 2.0 / 0.25)
		var lm = kl.mesh(lp, mesh_mat, [0, 0.005, D2], [-PI / 2.0, 0, 0])
		ctx.no_outline(lm)
		lm.cast_shadow = false
		# folded crow net on the lid + sign on the front
		var net_m = mat.toon("#4f86c8", {"paint": 0.08})
		k.rbox(1.25, 0.055, 0.26, 0.025, net_m, [0.08, Hh + 0.06, -0.22], [0, 0.04, 0.02])
		k.rbox(0.9, 0.05, 0.2, 0.022, net_m, [0.02, Hh + 0.105, -0.2], [0.05, -0.06, -0.03])
		k.rbox(0.28, 0.35, 0.03, 0.012, net_m, [0.66, Hh - 0.12, -D2 - 0.03], [0.05, 0, 0.1])
		k.box(0.52, 0.38, 0.015, M.white, [0, Hh - 0.24, D2 + 0.03])
		k.plane(0.5, 0.375, mat.toon("#ffffff", {"map": t.gomi, "paint": 0.01}), [0, Hh - 0.24, D2 + 0.0385])
		physics.addBox(gx, gz, 1.9, 1.0, rot, fp.min - 0.1, y0 + 1.0)
