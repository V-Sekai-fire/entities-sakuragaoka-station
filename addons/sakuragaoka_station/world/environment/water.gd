# environment/water.js: the river: toon water surface, rip-rap stones at the waterline, a low weir,
# stepping stones, a small gravel bar and the road bridge far west (x ~ -160).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Common = preload("res://addons/sakuragaoka_station/world/environment/common.gd")
const Shaders = preload("res://addons/sakuragaoka_station/world/environment/shaders.gd")

const WEIR_X := 76.0
const STONES_X := -45.0


static func water_y(L) -> float:
	return L.RIVER.waterY


static func build_river(ctx, C, tx) -> Dictionary:
	var L = ctx.L
	var WATER_Y := water_y(L)
	var kit = ctx.kit(T.Group.new())
	ctx.add_static(kit.parent)
	kit.parent.name = "env-river"
	var BR: Dictionary = Common.BRIDGE
	# ------------------------------------------------------------ water surface
	var water = Shaders.water_material(ctx, {"mode": 0, "weirX": WEIR_X + 0.9, "stonesX": STONES_X})
	var xs := []
	var zs := [-99.55, -101.5, -104.5, -108.5, -112.5, -115.5, -118.0]
	var xv := -700
	while xv <= 700:
		xs.append(float(xv))
		xv += 10
	var pos := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var idx := PackedInt32Array()
	for j in zs.size():
		for i in xs.size():
			pos.append_array([xs[i], WATER_Y, zs[j]])
			uv.append_array([xs[i], zs[j]])
	var nx := xs.size()
	for j in zs.size() - 1:
		for i in nx - 1:
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var d := c + 1
			idx.append_array([a, b, d, a, d, c])
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(pos, 3))
	var nrm := PackedFloat32Array()
	nrm.resize(pos.size())
	for i in pos.size():
		nrm[i] = 1.0 if i % 3 == 1 else 0.0
	g.set_attribute("normal", T.Attr.new(nrm, 3))
	g.set_attribute("uv", T.Attr.new(uv, 2))
	g.set_index(idx)
	var wm := T.MeshObj.new(g, water)
	wm.name = "env-river-water"
	ctx.no_batch(wm)
	ctx.add_static(wm)
	# ------------------------------------------------------------ rip-rap stones (instanced, faceted)
	var geo := Geo.icosahedron(0.5, 0).to_non_indexed()
	geo.compute_vertex_normals()
	var mat = ctx.mat.toon("#ffffff", {"paint": 0.06, "name": "env-riprap"})
	var r = ctx.rng("env-riprap")
	var list := []
	for b in [{"z": -99.95, "dir": 1.0, "x0": -135.0, "x1": 135.0, "step": 1.0}, {"z": -117.33, "dir": -1.0, "x0": -135.0, "x1": 135.0, "step": 1.35}]:
		var x: float = b.x0
		while x < b.x1:
			if not (absf(x - STONES_X) < 1.2 or absf(x - WEIR_X) < 2.2 or absf(x - BR.x) < 5.0):
				var s: float = 0.28 + r.f() * 0.42
				s += 0.35 if r.f() < 0.08 else 0.0
				var z: float = b.z - b.dir * (r.f() * 0.9 - 0.25)
				list.append({"x": x, "z": z, "y": WATER_Y - s * 0.18 + r.f() * 0.08, "s": s})
				if r.f() < 0.35:
					var x2: float = x + (r.f() - 0.5) * 0.6
					var z2: float = z - b.dir * (0.4 + r.f() * 0.5)
					list.append({"x": x2, "z": z2, "y": WATER_Y - 0.12, "s": s * 0.6})
			x += b.step * (0.6 + r.f() * 0.8)
	var im := T.InstancedMesh.new(geo, mat, list.size())
	var tones := ["#cfc9bc", "#bdb7aa", "#d8d3c7", "#aea99f", "#c7bfae"]
	for i in list.size():
		var st: Dictionary = list[i]
		var ex: float = r.f() * 3.0
		var ey: float = r.f() * 3.0
		var ez: float = r.f() * 3.0
		var q := T.quat_from_euler(Vector3(ex, ey, ez))
		var sx: float = st.s * (1.0 + r.f() * 0.5)
		var sy: float = st.s * (0.55 + r.f() * 0.3)
		var sz: float = st.s * (0.9 + r.f() * 0.4)
		im.set_matrix_at(i, T.compose(Vector3(st.x, st.y, st.z), q, Vector3(sx, sy, sz)))
		im.set_color_at(i, T.color(tones[i % tones.size()]))
	im.cast_shadow = true
	im.receive_shadow = true
	im.name = "env-riprap"
	ctx.add_static(im)
	# ------------------------------------------------------------ weir at x ~ 76
	var conc = ctx.mat.toon("#cfcbc0", {"paint": 0.07})
	var conc_d = ctx.mat.toon("#a9a699", {"paint": 0.06})
	var zc := (-99.3 + -117.9) / 2.0
	var wl := 18.6
	kit.box(1.3, 0.9, wl, conc, [WEIR_X, WATER_Y + 0.06 - 0.45, zc])
	kit.box(3.2, 0.3, wl, conc_d, [WEIR_X + 2.1, WATER_Y - 0.28, zc], [0, 0, -0.08])
	for dz in [-3.4, -2.2]:
		kit.box(1.5, 0.35, 0.35, conc_d, [WEIR_X, WATER_Y + 0.08, -104.0 + dz])
	# ------------------------------------------------------------ stepping stones at x ~ -45
	var stone = ctx.mat.toon("#d3cec2", {"paint": 0.08})
	var stone_g := Geo.icosahedron(0.5, 1)
	var pa: T.Attr = stone_g.attributes.position
	var na: T.Attr = stone_g.attributes.normal
	for i in pa.count():
		var x := pa.get_x(i)
		var y := pa.get_y(i)
		var z := pa.get_z(i)
		var l := sqrt(x * x + y * y + z * z)
		na.set_xyz(i, x / l, y / l, z / l)
		pa.set_y(i, y * 0.75 + 0.05 if y > 0.0 else y)
	var rs = ctx.rng("env-steps")
	var zst := -100.7
	while zst > -117.0:
		var w: float = 0.95 + rs.f() * 0.2
		var d: float = 0.72 + rs.f() * 0.12
		var px: float = STONES_X + (rs.f() - 0.5) * 0.25
		var py: float = WATER_Y + 0.02 + rs.f() * 0.04
		var ry: float = rs.f() * 3.0
		var m = kit.mesh(stone_g, stone, [px, py, zst], [0, ry, 0], [w * 1.05, 0.42, d * 1.1])
		m.cast_shadow = true
		zst -= 1.28
	# ------------------------------------------------------------ small gravel bar with reeds (reeds: flora)
	var bar := T.MeshObj.new(Geo.sphere(1, 20, 8, 0, TAU, 0, PI / 2.0), ctx.mat.toon("#c9c1ad", {"paint": 0.08, "map": tx.ground}))
	bar.scale = Vector3(9.5, 0.5, 2.1)
	bar.position = Vector3(26, WATER_Y - 0.28, -112.4)
	bar.rotation.y = 0.06
	bar.receive_shadow = true
	kit.parent.add(bar)
	var grass := T.MeshObj.new(Geo.sphere(1, 16, 6, 0, TAU, 0, PI / 2.0), ctx.mat.toon("#9dbf78", {"paint": 0.06, "map": tx.levee}))
	grass.scale = Vector3(6.2, 0.32, 1.25)
	grass.position = Vector3(25.2, WATER_Y - 0.05, -112.5)
	grass.receive_shadow = true
	kit.parent.add(grass)
	build_bridge(ctx, C, tx)
	var xb := -130
	while xb < 130:
		ctx.physics.addBox(xb + 10, -99.5, 20, 0.6, 0, -5, 20)
		xb += 20
	return {"bars": [{"x": 26.0, "z": -112.4, "rx": 9.0, "rz": 1.8}]}


static func build_bridge(ctx, C, tx) -> void:
	var L = ctx.L
	var grp := T.Group.new()
	grp.name = "env-bridge"
	ctx.add_static(grp)
	var k = ctx.kit(grp)
	var X: float = Common.BRIDGE.x
	var top: float = Common.BRIDGE.deckY
	var conc = ctx.mat.toon("#d6d2c7", {"paint": 0.07})
	var conc_s = ctx.mat.toon("#c4c0b4", {"paint": 0.06})
	var asphalt = ctx.mat.toon("#77797e", {"paint": 0.05})
	var walk = ctx.mat.toon("#c9c5ba", {"paint": 0.05})
	var steel = ctx.mat.toon("#e3e6e6", {"paint": 0.03})
	var line = ctx.mat.decal("#ecebe5")
	var z0 := -91.6
	var z1 := -121.2
	var zl := (z0 + z1) / 2.0
	var length := z0 - z1
	k.box(9.2, 0.32, length, conc, [X, top - 0.16, zl])
	for dx in [-3.1, 0, 3.1]:
		k.box(0.7, 1.0, -94.2 - z1 + 0.3, conc_s, [X + dx, top - 0.82, (-94.2 + z1) / 2.0])
	k.box(6.0, 0.03, length, asphalt, [X, top + 0.015, zl])
	for s in [-1, 1]:
		k.box(1.45, 0.18, length, walk, [X + s * 3.72, top + 0.09, zl])
		k.box(0.12, 0.012, length, line, [X + s * 2.75, top + 0.036, zl])
	k.box(0.12, 0.012, length, ctx.mat.decal("#e9c54a"), [X, top + 0.036, zl])
	for zp in [-104.6, -112.3]:
		k.rbox(7.4, 3.35, 1.25, 0.55, conc_s, [X, (-1.2 + top - 1.3) / 2.0, zp])
	k.box(9.4, top + 1.6, 1.4, conc_s, [X, (top - 1.6 - 0.2) / 2.0 + 0.1 - 0.1, -120.6])
	var panel_mat = ctx.mat.foliage("#ffffff", tx.railing, {"alphaTest": 0.5, "name": "env-railing"})
	for s in [-1, 1]:
		var xr: float = X + s * 4.45
		k.box(0.1, 0.1, length, steel, [xr, top + 1.18, zl])
		var z := z0 - 0.2
		while z > z1:
			k.box(0.1, 1.0, 0.1, steel, [xr, top + 0.68, z])
			z -= 2.5
		var pg := Geo.plane(length, 0.95)
		pg.rotate_y(PI / 2.0)
		var uva: T.Attr = pg.attributes.uv
		for i in uva.count():
			uva.set_x(i, uva.get_x(i) * length / 2.4)
		var p := T.MeshObj.new(pg, panel_mat)
		p.position = Vector3(xr, top + 0.66, zl)
		ctx.no_outline(p)
		grp.add(p)
		for ze in [z0 - 0.3, z1 + 0.3]:
			k.rbox(0.55, 1.45, 0.55, 0.06, conc, [xr, top + 0.72, ze])
		for zlmp in [-99.5, -113.5]:
			k.cyl(0.07, 0.09, 6.2, ctx.mat.toon("#8f979c"), [xr + s * 0.1, top + 3.1, zlmp], null, 8)
			k.box(0.9, 0.1, 0.12, ctx.mat.toon("#8f979c"), [xr - s * 0.4, top + 6.1, zlmp])
			k.box(0.5, 0.12, 0.26, ctx.mat.toon("#e9ecef"), [xr - s * 0.8, top + 6.02, zlmp])
	var pm = ctx.mat.toon("#ffffff", {"map": ctx.tex.draw(256, 128), "paint": 0.02})
	for s in [-1, 1]:
		var pl = k.plane(0.44, 0.22, pm, [X + s * 4.45, top + 1.1, z0 - 0.3 + 0.281], [0, 0, 0])
		pl.rotation.y = 0.0
	var ramp := []
	for i in 25:
		var t := i / 24.0
		ramp.append([X - 1.0 - t * 42.0, -92.2 + t * 8.4])
	var pos := PackedFloat32Array()
	var idx := []
	for i in ramp.size():
		var x: float = ramp[i][0]
		var z: float = ramp[i][1]
		var nb: Array = ramp[i + 1] if i < ramp.size() - 1 else ramp[i - 1]
		var dx: float = nb[0] - x
		var dz: float = nb[1] - z
		if i == ramp.size() - 1:
			dx = -dx
			dz = -dz
		var l := sqrt(dx * dx + dz * dz)
		var px := -dz / l * 2.8
		var pz := dx / l * 2.8
		for s in [-1, 1]:
			var xx: float = x + px * s
			var zz: float = z + pz * s
			pos.append_array([xx, maxf(L.height_at(xx, zz), C.terrain_h(xx, zz)) + 0.035, zz])
		if i:
			var a := (i - 1) * 2
			idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var rg := T.Geometry.new()
	rg.set_attribute("position", T.Attr.new(pos, 3))
	rg.set_index(idx)
	rg.compute_vertex_normals()
	if (rg.attributes.normal as T.Attr).get_y(0) < 0.0:
		var i := 0
		while i < idx.size():
			var t = idx[i + 1]
			idx[i + 1] = idx[i + 2]
			idx[i + 2] = t
			i += 3
		rg.set_index(idx)
		rg.compute_vertex_normals()
	var rm := T.MeshObj.new(rg, asphalt)
	rm.receive_shadow = true
	grp.add(rm)
	k.box(7.0, 0.04, 3.4, asphalt, [X, 3.22, -93])
