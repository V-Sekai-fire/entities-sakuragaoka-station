# plaza/plants.js: flower beds (tulips, pansies, daisies, smooth low shrubs; brick or light-concrete
# edging), the east hedge, and small weeds and dandelions in joints and along the curbs. Repeated
# plants are instanced.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")
const U = preload("res://addons/sakuragaoka_station/world/plaza/util.gd")
const PlazaTree = preload("res://addons/sakuragaoka_station/world/plaza/tree.gd")
const Foliage = preload("res://addons/sakuragaoka_station/world/lib/foliage.gd")

const TULIP := ["#e0514a", "#f09bb4", "#f2cd4a", "#f7c7d4", "#e0514a", "#f09bb4", "#f5ede2"]
const PANSY := ["#8a70c8", "#f1d04b", "#f4f1f6", "#f2a347", "#6e87d6", "#b0487a", "#d9c4f0"]


static func build_plants(ctx, root, TX: Dictionary, P: Dictionary) -> void:
	var mat = ctx.mat
	var physics = ctx.physics
	var r: Rng = ctx.rng("plaza-plants")
	var g := T.Group.new()
	g.name = "plaza-plants"
	root.add(g)
	var Y: float = P.yPave
	var I := {"bloom": [], "bloomC": [], "green": [], "pansy": [], "pansyC": [], "daisy": [], "daisyC": [], "rosette": [],
		"tuft": [], "tuftC": [], "dand": [], "clump": [], "clumpC": []}

	# ---------------------------------------------------------------- plant emitters
	var tulip_clump := func(x: float, z: float, y: float, color: String, n: int) -> void:
		for i in n:
			var a := r.f() * TAU
			var d := sqrt(r.f()) * 0.14
			var h := r.range(0.2, 0.3)
			var lean := r.range(-0.12, 0.12)
			var rot := r.f() * TAU
			var sm := U.mtx(x + cos(a) * d, y, z + sin(a) * d, lean, rot, lean * 0.5, [1.0, h / 0.32, 1.0])
			I.green.append(sm)
			# the bloom sits on top of the (leaned) stem
			var top := sm * Vector3(0, 0.318, 0)
			I.bloom.append(U.mtx(top.x, top.y - 0.006, top.z, lean, rot, lean * 0.5, r.range(1.35, 1.6)))
			var dh := r.range(-0.01, 0.01)
			I.bloomC.append(T.offset_hsl(T.color(color), dh, 0.0, r.range(-0.04, 0.03)))
	var pansy := func(x: float, z: float, y: float) -> void:
		var s := r.range(0.8, 1.15)
		var ry := r.f() * TAU
		I.clump.append(U.mtx(x, y - 0.005, z, 0, ry, 0, [0.2 * s, 0.1 * s, 0.2 * s]))
		I.clumpC.append(T.offset_hsl(T.color("#ffffff"), 0.0, 0.0, r.range(-0.12, 0.0)))
		var c: String = r.pick(PANSY)
		var n := r.rint(3, 5)
		for i in n:
			var a := (float(i) / n) * TAU + r.range(-0.4, 0.4)
			var d := r.range(0.02, 0.06) * s
			var py := y + r.range(0.045, 0.075) * s
			var rx := -r.range(0.5, 1.0)
			var sc := r.range(0.05, 0.065) * s
			I.pansy.append(U.mtx(x + cos(a) * d, py, z + sin(a) * d, rx, -a + PI / 2.0, 0, sc))
			I.pansyC.append(T.offset_hsl(T.color(c), 0.0, 0.0, r.range(-0.03, 0.03)))
	var daisy := func(x: float, z: float, y: float, n: int) -> void:
		var ry0 := r.f() * TAU
		I.rosette.append(U.mtx(x, y + 0.006, z, 0, ry0, 0, [0.16, 1.0, 0.16]))
		for i in n:
			var a := r.f() * TAU
			var d := r.range(0.0, 0.07)
			var py := y + r.range(0.05, 0.12)
			var rx := r.range(-0.35, 0.35)
			var ry := r.f() * TAU
			var rz := r.range(-0.35, 0.35)
			var sc := r.range(0.035, 0.05)
			I.daisy.append(U.mtx(x + cos(a) * d, py, z + sin(a) * d, rx, ry, rz, sc))
			I.daisyC.append(T.color("#f7dbe5" if r.chance(0.2) else "#ffffff"))
	var cover := func(x: float, z: float, y: float, s: float) -> void:
		var ry := r.f() * TAU
		I.clump.append(U.mtx(x, y - 0.005, z, 0, ry, 0, [0.36 * s, 0.12 * s, 0.36 * s]))
		I.clumpC.append(T.offset_hsl(T.color("#e8f0dc"), 0.0, 0.0, r.range(-0.15, 0.0)))
	# soft boxwood / azalea mounds: one smooth puff-scalloped shrub each (lib/foliage). The draws of
	# the original's earlier multi-blob version are kept so every other plant stays where it was.
	var shrub_n := [0]
	var shrub := func(x: float, z: float, y: float, s: float, hue: float, bloom: bool) -> void:
		var n := r.rint(2, 3)
		var v0 := 0.0
		var v1 := 0.0
		for i in n:
			var a := r.range(-0.12, 0.12)
			var b := r.range(-0.12, 0.12)
			r.range(0.19, 0.26)
			var rot := r.f() * 3.0
			r.f()
			r.f()
			if bloom and i < 2:
				r.range(-0.06, 0.0)
			else:
				r.range(-0.015, 0.015)
				r.range(-0.04, 0.04)
				r.range(-0.07, 0.03)
			if i == 0:
				v0 = a
				v1 = rot
			else:
				v0 += b * 0.3
		var seed: int = (shrub_n[0] % 4) + (11 if bloom else 1)
		shrub_n[0] += 1
		var kind := "azalea" if bloom else ("young" if hue > 0.01 else "boxwood")
		var flowers = {"colors": Foliage.FLOWER_COLORS.azaleaMix, "density": 1.4} if bloom else null
		var m = Foliage.make_shrub(ctx, {"r": 0.33 * s, "h": 0.4 * s, "sx": 1.05 + v0, "sz": 0.98, "seed": seed, "kind": kind, "spacing": 0.07, "flowers": flowers})
		m.position = Vector3(x, y - 0.02, z)
		m.rotation.y = v1 * 2.1
		g.add(m)
	var tuft := func(x: float, z: float, y: float, s: float) -> void:
		var h := r.range(0.06, 0.13) * s
		var rx := r.range(-0.2, 0.2)
		var ry := r.f() * TAU
		var sx := h * r.range(1.0, 1.6)
		I.tuft.append(U.mtx(x, y - 0.005, z, rx, ry, 0, [sx, h, h]))
		var hue := 0.23 + r.range(-0.03, 0.04)
		I.tuftC.append(T.from_hsl(hue, 0.38, 0.5 + r.range(-0.08, 0.08)))
	var dandelion := func(x: float, z: float, y: float) -> void:
		var ry0 := r.f() * TAU
		I.rosette.append(U.mtx(x, y + 0.004, z, 0, ry0, 0, [0.13, 1.0, 0.13]))
		var n := r.rint(1, 2)
		for i in n:
			var dx := r.range(-0.03, 0.03)
			var py := y + r.range(0.05, 0.1)
			var dz := r.range(-0.03, 0.03)
			var rx := r.range(-0.4, 0.4)
			var ry := r.f() * TAU
			var rz := r.range(-0.4, 0.4)
			var sc := r.range(0.04, 0.055)
			I.dand.append(U.mtx(x + dx, py, z + dz, rx, ry, rz, sc))

	# ---------------------------------------------------------------- beds
	var brick = mat.toon("#ffffff", {"map": TX.brick, "paint": 0.05})
	var conc = mat.toon("#ffffff", {"map": TX.concrete, "paint": 0.05})
	var cap_brick = mat.toon("#c7c2b6", {"map": TX.concrete, "paint": 0.04})
	var soil = mat.toon("#ffffff", {"map": TX.soil, "paint": 0.06})
	for b in P.beds:
		var x0: float = b.x0
		var z0: float = b.z0
		var x1: float = b.x1
		var z1: float = b.z1
		var h: float = b.get("h", 0.3)
		var t := 0.12
		var w := x1 - x0
		var d := z1 - z0
		var cx := (x0 + x1) / 2.0
		var cz := (z0 + z1) / 2.0
		var em = brick if b.edge == "brick" else conc
		U.put(g, U.box_uv(w, h, t, 1), em, [cx, h / 2.0, z0 + t / 2.0])
		U.put(g, U.box_uv(w, h, t, 1), em, [cx, h / 2.0, z1 - t / 2.0])
		U.put(g, U.box_uv(t, h, d - 2.0 * t, 1), em, [x0 + t / 2.0, h / 2.0, cz])
		U.put(g, U.box_uv(t, h, d - 2.0 * t, 1), em, [x1 - t / 2.0, h / 2.0, cz])
		if b.edge == "brick":
			# light coping stones on the brick walls
			U.put(g, U.box_uv(w + 0.02, 0.035, t + 0.02, 1), cap_brick, [cx, h + 0.0175, z0 + t / 2.0])
			U.put(g, U.box_uv(w + 0.02, 0.035, t + 0.02, 1), cap_brick, [cx, h + 0.0175, z1 - t / 2.0])
			U.put(g, U.box_uv(t + 0.02, 0.035, d - 2.0 * t - 0.02, 1), cap_brick, [x0 + t / 2.0, h + 0.0175, cz])
			U.put(g, U.box_uv(t + 0.02, 0.035, d - 2.0 * t - 0.02, 1), cap_brick, [x1 - t / 2.0, h + 0.0175, cz])
		var sy := h - 0.05
		var sg := Geo.plane(w - 2.0 * t, d - 2.0 * t).rotate_x(-PI / 2.0)
		var suv: T.Attr = sg.attributes.uv
		for i in suv.count():
			suv.set_xy(i, suv.get_x(i) * (w - 2.0 * t), suv.get_y(i) * (d - 2.0 * t))
		U.put(g, sg, soil, [cx, sy, cz], null, {"cast": false})
		physics.addBox(cx, cz, w, d, 0, 0, 1.0)
		# planting
		var ix0 := x0 + t + 0.08
		var ix1 := x1 - t - 0.08
		var iz0 := z0 + t + 0.08
		var iz1 := z1 - t - 0.08
		var iw := ix1 - ix0
		var id := iz1 - iz0
		if b.kind == "tulips":
			# an edge ring of pansies and daisies, clumps of tulips inside
			var per := 2.0 * (iw + id)
			var n_edge := int(T.js_round(per / 0.2))
			for i in n_edge:
				var u := (i + r.range(-0.2, 0.2)) / n_edge * per
				var x := 0.0
				var z := 0.0
				if u < iw:
					x = ix0 + u
					z = iz1
				else:
					u -= iw
					if u < id:
						x = ix1
						z = iz1 - u
					else:
						u -= id
						if u < iw:
							x = ix1 - u
							z = iz0
						else:
							u -= iw
							x = ix0
							z = iz0 + u
				if r.chance(0.72):
					pansy.call(x, z, sy)
				else:
					daisy.call(x, z, sy, 4)
			var nx := maxi(1, int(T.js_round((iw - 0.3) / 0.3)))
			var nz := maxi(1, int(T.js_round((id - 0.3) / 0.3)))
			var ci := r.rint(0, 6)
			for i in nx:
				for k in nz:
					var x := ix0 + 0.15 + ((iw - 0.3) * i / (nx - 1) if nx > 1 else (iw - 0.3) / 2.0) + r.range(-0.05, 0.05)
					var z := iz0 + 0.15 + ((id - 0.3) * k / (nz - 1) if nz > 1 else (id - 0.3) / 2.0) + r.range(-0.05, 0.05)
					if b.get("shrubEnds", false) and (i == 0 or i == nx - 1) and k == nz - 1 and nz > 1:
						shrub.call(x, z, sy, 1.1, 0.0, true)
						continue
					var color: String = TULIP[ci % TULIP.size()]
					ci += 1
					tulip_clump.call(x, z, sy, color, r.rint(7, 10))
			for i in int(T.js_round(iw * id / 0.07)):
				var cx2 := ix0 + r.f() * iw
				var cz2 := iz0 + r.f() * id
				cover.call(cx2, cz2, sy, r.range(0.8, 1.2))
		elif b.kind == "border":
			# a long narrow bed: shrubs every ~1.3 m with pansies, daisies and tulips between
			var long := d > w
			var l0 := iz0 if long else ix0
			var l1 := iz1 if long else ix1
			var mid := (ix0 + ix1) / 2.0 if long else (iz0 + iz1) / 2.0
			var blen := l1 - l0
			var ns := maxi(2, int(T.js_round(blen / 1.3)))
			for i in ns + 1:
				var u := l0 + blen * i / ns
				shrub.call(mid if long else u, u if long else mid, sy, 0.95, 0.0, i % 2 == 1)
			for i in ns:
				var u := l0 + blen * (i + 0.5) / ns
				var p := func(du: float, dv: float) -> Array: return [mid + dv, u + du] if long else [u + du, mid + dv]
				var q: Array = p.call(0.0, 0.0)
				if i % 2 == 0:
					tulip_clump.call(q[0], q[1], sy, TULIP[(i / 2) % TULIP.size()], 6)
				else:
					daisy.call(q[0], q[1], sy, 6)
				for dd in [[-0.35, -0.2], [0.35, 0.2], [-0.35, 0.2], [0.35, -0.2]]:
					var e: Array = p.call(dd[0], dd[1])
					pansy.call(e[0], e[1], sy)
			for i in int(T.js_round(iw * id / 0.06)):
				var cx2 := ix0 + r.f() * iw
				var cz2 := iz0 + r.f() * id
				cover.call(cx2, cz2, sy, r.range(0.8, 1.2))
		# weeds at the bed foot
		var perim := 2.0 * (w + d)
		for i in int(T.js_round(perim / 1.4)):
			var u := r.f() * perim
			var x := 0.0
			var z := 0.0
			if u < w:
				x = x0 + u
				z = z1 + 0.03
			elif u < w + d:
				x = x1 + 0.03
				z = z0 + (u - w)
			elif u < 2.0 * w + d:
				x = x0 + (u - w - d)
				z = z0 - 0.03
			else:
				x = x0 - 0.03
				z = z0 + (u - 2.0 * w - d)
			tuft.call(x, z, Y, 0.9)

	# ---------------------------------------------------------------- round planters: a small shrub ringed with pansies
	for pp in P.planters:
		var px: float = pp[0]
		var pz: float = pp[1]
		shrub.call(px, pz, 0.46, 1.0, 0.02, false)
		for i in 7:
			var a := float(i) / 7 * TAU + r.range(-0.2, 0.2)
			pansy.call(px + cos(a) * 0.3, pz + sin(a) * 0.3, 0.46)

	# ---------------------------------------------------------------- east hedge (boxwood) with a cloud-like top
	var hd: Dictionary = P.hedge
	var hlen: float = hd.z1 - hd.z0
	var hcx: float = (hd.x0 + hd.x1) / 2.0
	var hcz: float = (hd.z0 + hd.z1) / 2.0
	var hw: float = hd.x1 - hd.x0
	# one continuous clipped hedge along z; the draws of the original's puff version are kept
	var hn := int(T.js_round(hlen / 0.5))
	for i in hn + 1:
		r.range(0.28, 0.36)
		r.range(-0.05, 0.05)
		r.range(-0.03, 0.05)
		r.f()
		r.f()
		r.f()
		r.range(-0.015, 0.015)
		r.range(-0.05, 0.03)
	# white spirea blossoms along the south end (local x = -z)
	var hm = Foliage.make_hedge(ctx, {"length": hlen, "h": 0.78, "d": hw + 0.12, "seed": 7, "kind": "boxwood", "spacing": 0.1,
		"flowers": {"colors": Foliage.FLOWER_COLORS.spirea, "density": 2.2, "size": 0.8, "top": 0.25, "xRange": [hlen / 2.0 - 3.2, hlen / 2.0 - 0.4]}})
	hm.position = Vector3(hcx, Y - 0.03, hcz)
	hm.rotation.y = PI / 2.0
	g.add(hm)
	physics.addBox(hcx, hcz, hw + 0.1, hlen, 0, 0, 1.0)
	for i in 22:
		tuft.call(hd.x0 - 0.04, hd.z0 + r.f() * hlen, Y, 1.1)

	# ---------------------------------------------------------------- weeds and dandelions in joints and along the curbs
	for i in 46:
		var x := r.range(P.x0 + 0.3, P.x1 - 0.8)
		if absf(x) < 2.2 or (x > 16.8 and x < 18.8):
			continue
		tuft.call(x, -5.24 - r.range(0, 0.05), Y, 1.0)
	for i in 26:
		var x := -9.02 - r.range(0, 0.02)
		tuft.call(x, r.range(-24.8, -5.6), Y, 1.0)
	for i in 12:
		var x := r.range(-4.4, 14.4)
		tuft.call(x, -19.92 + r.range(-0.02, 0.02), Y, 0.8)
	for bp in P.bollards:
		if r.chance(0.6):
			var x: float = bp[0] + r.range(-0.1, 0.1)
			tuft.call(x, bp[1] + r.range(-0.1, 0.1), Y, 1.0)
	for lp in P.lamps:
		tuft.call(lp[0] + 0.14, lp[1] + 0.05, Y, 1.0)
		tuft.call(lp[0] - 0.1, lp[1] - 0.12, Y, 0.8)
	for dp in P.dandelions:
		dandelion.call(dp[0], dp[1], Y)
	# random joint weeds on the 0.5 m grid (sparse), away from paths
	for i in 40:
		var x := T.js_round(r.range(-8.5, 25) * 2.0) / 2.0
		var z := T.js_round(r.range(-24.5, -5.8) * 2.0) / 2.0
		if P.isBusy.call(x, z):
			continue
		tuft.call(x + r.range(-0.03, 0.03), z, Y, 0.55)

	# ---------------------------------------------------------------- instanced meshes
	var add := func(geo, m, mats: Array, cols, outline: bool, cast: bool):
		if mats.is_empty():
			return null
		var im = U.instanced(geo, m, mats, cols, {"cast": cast})
		if not outline:
			ctx.no_outline(im)
		g.add(im)
		return im
	# tulip bloom (a six-petal lathe cup), stem and leaves
	var bloom_geo := Geo.lathe([Vector2(0, 0), Vector2(0.021, 0.006), Vector2(0.029, 0.025), Vector2(0.027, 0.047), Vector2(0.013, 0.064)], 6)
	add.call(bloom_geo, mat.toon("#ffffff", {"paint": 0.03}), I.bloom, I.bloomC, true, true)
	add.call(tulip_green_geo(), mat.toon("#6f9e56", {"side": "double", "paint": 0.04}), I.green, null, false, true)
	add.call(clump_geo(), U.add_sway(ctx, mat.foliage("#ffffff", TX.leafClump, {"name": "plaza-sway-clump"}), 0.02, "up"), I.clump, I.clumpC, false, false)
	var flat := Geo.plane(1, 1).rotate_x(-PI / 2.0)
	var upright := Geo.plane(1, 1)
	add.call(upright, U.add_sway(ctx, mat.foliage("#ffffff", TX.pansy, {"name": "plaza-sway-pansy"}), 0.006, "flat"), I.pansy, I.pansyC, false, false)
	add.call(flat, U.add_sway(ctx, mat.foliage("#ffffff", TX.daisy, {"name": "plaza-sway-daisy"}), 0.008, "flat"), I.daisy, I.daisyC, false, false)
	add.call(flat, mat.foliage("#ffffff", TX.rosette), I.rosette, null, false, false)
	add.call(PlazaTree.cross_quads(1, 1, 3), U.add_sway(ctx, mat.foliage("#ffffff", TX.grass, {"name": "plaza-sway-grass"}), 0.018, "up"), I.tuft, I.tuftC, false, false)
	add.call(flat, U.add_sway(ctx, mat.foliage("#ffffff", TX.dandelion, {"name": "plaza-sway-dand"}), 0.008, "flat"), I.dand, null, false, false)


## Three splayed leaf cards around a centre (1 wide, 1 tall), up-facing normals for even light.
static func clump_geo() -> T.Geometry:
	var pos := PackedFloat32Array()
	var nor := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var idx := PackedInt32Array()
	for i in 3:
		var a := float(i) / 3 * PI + 0.3
		var ca := cos(a)
		var sa := sin(a)
		for side in [1.0, -1.0]:
			# each card leans outward from the centre on one side
			var o := pos.size() / 3
			var lean: float = 0.55 * side
			var tx: float = -sa * side * lean
			var tz: float = ca * side * lean
			for c in [[-0.5, 0.0], [0.5, 0.0], [0.5, 1.0], [-0.5, 1.0]]:
				var u: float = c[0]
				var v: float = c[1]
				pos.append_array([ca * u + tx * v, v, sa * u + tz * v])
				nor.append_array([0.0, 1.0, 0.0])
				uv.append_array([u + 0.5, v])
			idx.append_array([o, o + 1, o + 2, o, o + 2, o + 3])
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(pos, 3))
	g.set_attribute("normal", T.Attr.new(nor, 3))
	g.set_attribute("uv", T.Attr.new(uv, 2))
	g.set_index(idx)
	return g


## A stem (thin box) and two arching leaves, unit height 0.32.
static func tulip_green_geo() -> T.Geometry:
	var B := U.GeoBuilder.new()
	var h := 0.32
	var w := 0.005
	var corners := [[-w, -w], [w, -w], [w, w], [-w, w]]
	for i in 4:
		var ax: float = corners[i][0]
		var az: float = corners[i][1]
		var bx: float = corners[(i + 1) % 4][0]
		var bz: float = corners[(i + 1) % 4][1]
		var nx := (ax + bx) / 2.0
		var nz := (az + bz) / 2.0
		var l := sqrt(nx * nx + nz * nz)
		var a := B.v(ax, 0, az, nx / l, 0, nz / l)
		var b := B.v(bx, 0, bz, nx / l, 0, nz / l)
		var c := B.v(bx, h, bz, nx / l, 0, nz / l)
		var d := B.v(ax, h, az, nx / l, 0, nz / l)
		B.quad(a, b, c, d)
	var leaf := func(dir: float, len: float, width: float, lift: float) -> void:
		var segs := 4
		var ca := cos(dir)
		var sa := sin(dir)
		var prev := []
		for i in segs + 1:
			var t := float(i) / segs
			var out := t * len * 0.45
			var up := lift + t * len * (1.0 - 0.55 * t)
			var hw := width * sin(PI * minf(1.0, t * 1.15 + 0.05)) * (1.0 - t * 0.6)
			var px := ca * out
			var pz := sa * out
			var tx := -sa * hw
			var tz := ca * hw
			var a := B.v(px - tx, up, pz - tz, ca * 0.6, 0.8, sa * 0.6)
			var b := B.v(px + tx, up, pz + tz, ca * 0.6, 0.8, sa * 0.6)
			if not prev.is_empty():
				B.quad(prev[0], prev[1], b, a)
			prev = [a, b]
	leaf.call(0.0, 0.2, 0.022, 0.0)
	leaf.call(PI * 0.9, 0.17, 0.02, 0.02)
	return B.build()
