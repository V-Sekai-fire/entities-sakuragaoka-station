# plaza/tree.js: the tree pit around the plaza sakura (brick ring, stone cap, soil, grass, moss, small
# flowers) and the circular wooden ring bench, with a school bag, a shopping bag with leeks and a
# half-finished drink on it. The tree itself is the sakura module's.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")
const U = preload("res://addons/sakuragaoka_station/world/plaza/util.gd")

const PIT_IN := 1.40
const PIT_OUT := 1.62
const PIT_H := 0.26


## Returns the ring bench's seats for ctx.services.plaza.benches (used sections last).
static func build_tree(ctx, root, TX: Dictionary, P: Dictionary) -> Array:
	var mat = ctx.mat
	var physics = ctx.physics
	var L = ctx.L
	var cx: float = P.tree.x
	var cz: float = P.tree.z
	var g := T.Group.new()
	g.name = "plaza-tree"
	g.position = Vector3(cx, 0, cz)
	root.add(g)
	var r: Rng = ctx.rng("plaza-tree")

	# ---------------------------------------------------------------- circle pavers around the pit, granite rim
	var circle = U.put(g, U.annulus(1.62, P.circleR, P.yPave, 120, 5, 6), mat.toon("#ffffff", {"map": TX.circle, "paint": 0.05}), [0, 0, 0], null, {"cast": false})
	circle.name = "tree-circle"
	U.put(g, U.annulus(P.circleR, P.circleR + 0.02, P.yPave, 120, 1, 6), mat.toon("#9d9a92"), [0, 0, 0], null, {"cast": false})

	# ---------------------------------------------------------------- pit: brick wall, stone cap stones, soil
	U.put(g, U.ring_sector(PIT_IN, PIT_OUT, 0.0, PIT_H, 0.0, TAU, 64, {"noBottom": true}), mat.toon("#ffffff", {"map": TX.brick, "paint": 0.05}), [0, 0, 0])
	var cap_mats := []
	for c in ["#d9d6cc", "#d2cfc5", "#dedbd2"]:
		cap_mats.append(mat.toon(c, {"map": TX.concrete, "paint": 0.05}))
	var n_cap := 14
	for i in n_cap:
		var a0 := (float(i) / n_cap) * TAU + 0.004
		var a1 := (float(i + 1) / n_cap) * TAU - 0.004
		U.put(g, U.ring_sector(1.35, 1.69, PIT_H, PIT_H + 0.055, a0, a1, 5), cap_mats[i % 3], [0, 0, 0])
	# soil disc with a gentle mound
	var B := U.GeoBuilder.new()
	var rings := 6
	var seg := 40
	var rows := []
	for j in rings + 1:
		var rr := PIT_IN * j / rings
		var row := []
		for i in seg + 1:
			var a := TAU * i / seg
			var x := rr * cos(a)
			var z := rr * sin(a)
			row.append(B.v(x, 0.205 + 0.05 * (1.0 - (rr / PIT_IN) ** 2), z, 0, 1, 0, x, -z))
			if j == 0:
				break
		rows.append(row)
	for j in rings:
		for i in seg:
			if j == 0:
				B.tri(rows[0][0], rows[1][i], rows[1][i + 1])
			else:
				B.quad(rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i])
	var soil_geo := B.build()
	soil_geo.compute_vertex_normals()
	U.put(g, soil_geo, mat.toon("#ffffff", {"map": TX.soil, "paint": 0.06}), [0, 0, 0], null, {"cast": false})
	# moss patches on the soil and on the cap (decals)
	var moss_mat = mat.decal("#6f8d55", {"alphaMap": TX.moss, "opacity": 0.85})
	for i in 9:
		var a := r.f() * TAU
		var rr := r.range(0.7, 1.3)
		var s := r.range(0.25, 0.5)
		var y := 0.205 + 0.05 * (1.0 - (rr / PIT_IN) ** 2) + 0.006
		var rz := r.f() * 3.0
		var m = U.put(g, Geo.g_plane(ctx.cache), moss_mat, [rr * cos(a), y, rr * sin(a)], [-PI / 2.0, 0, rz], {"cast": false})
		m.scale = Vector3(s, s * r.range(0.6, 1.0), 1)
	for i in 5:
		var a := r.f() * TAU
		var rz := r.f() * 3.0
		var m = U.put(g, Geo.g_plane(ctx.cache), mat.decal("#7d9460", {"alphaMap": TX.moss, "opacity": 0.7}), [1.52 * cos(a), PIT_H + 0.059, 1.52 * sin(a)], [-PI / 2.0, 0, rz], {"cast": false})
		m.scale = Vector3(0.3, 0.14, 1)

	# ---------------------------------------------------------------- pit plants (instanced cut-outs)
	var soil_y := func(rr: float) -> float: return 0.205 + 0.05 * (1.0 - (rr / PIT_IN) ** 2)
	var tuft_geo := cross_quads(1, 1, 3)
	var grass_mats := []
	var grass_cols := []
	for i in 90:
		var a := r.f() * TAU
		var rr := sqrt(r.range(0.30, 1)) * 1.32
		if rr < 0.62:
			continue
		var s := r.range(0.07, 0.15)
		var ry := r.f() * TAU
		var sx := s * r.range(0.9, 1.4)
		grass_mats.append(U.mtx(rr * cos(a), soil_y.call(rr) - 0.01, rr * sin(a), 0, ry, 0, [sx, s, s]))
		var hue := 0.24 + r.range(-0.03, 0.03)
		grass_cols.append(T.from_hsl(hue, 0.4, 0.5 + r.range(-0.08, 0.06)))
	var grass = U.instanced(tuft_geo, U.add_sway(ctx, mat.foliage("#ffffff", TX.grass, {"name": "plaza-sway-grass"}), 0.018, "up"), grass_mats, grass_cols)
	ctx.no_outline(grass)
	g.add(grass)
	# small flowers: white star flowers, violets, a few dandelions
	var flat_geo := Geo.plane(1, 1).rotate_x(-PI / 2.0)
	var fl := []
	var flc := []
	for i in 46:
		var a := r.f() * TAU
		var rr := r.range(0.7, 1.33)
		var s := r.range(0.1, 0.17)
		var y: float = soil_y.call(rr) + r.range(0.03, 0.08)
		var rx := r.range(-0.3, 0.3)
		var ry := r.f() * TAU
		var rz := r.range(-0.3, 0.3)
		fl.append(U.mtx(rr * cos(a), y, rr * sin(a), rx, ry, rz, s))
		flc.append(T.color(r.pick(["#ffffff", "#ffffff", "#e8e4ff", "#d9ccf2", "#f7e0ec"])))
	var flowers = U.instanced(flat_geo, U.add_sway(ctx, mat.foliage("#ffffff", TX.tinyFlower, {"name": "plaza-sway-tiny"}), 0.008, "flat"), fl, flc)
	ctx.no_outline(flowers)
	g.add(flowers)
	var dd := []
	for i in 6:
		var a := r.f() * TAU
		var rr := r.range(0.8, 1.3)
		var rx := r.range(-0.4, 0.4)
		var ry := r.f() * TAU
		dd.append(U.mtx(rr * cos(a), soil_y.call(rr) + 0.07, rr * sin(a), rx, ry, 0, 0.07))
	var dand = U.instanced(flat_geo, U.add_sway(ctx, mat.foliage("#ffffff", TX.dandelion, {"name": "plaza-sway-dand"}), 0.008, "flat"), dd)
	ctx.no_outline(dand)
	g.add(dand)

	# ---------------------------------------------------------------- ring bench
	var br0 := 2.08
	var br1 := 2.52
	var seat_y: float = L.SPOTS.plazaBenchSeatY
	var bn := 8
	var cat: Dictionary = L.SPOTS.calicoCat
	var th0 := atan2(cat.z - cz, cat.x - cx)
	var sec_a := TAU / bn
	var gap_a := 0.012
	var wood = mat.toon("#ffffff", {"map": TX.wood, "paint": 0.05})
	var wood_b = mat.toon("#f1e8dc", {"map": TX.wood, "paint": 0.05})
	var frame = mat.toon("#56615e", {"paint": 0.03})
	var n_sl := 5
	var sl_gap := 0.014
	var sl_w := (br1 - br0 - (n_sl - 1) * sl_gap) / n_sl
	var sl_t := 0.034
	var legs := []
	var sections := []
	for k in bn:
		var th := th0 + k * sec_a
		var a0 := th - sec_a / 2.0 + gap_a / 2.0
		var a1 := th + sec_a / 2.0 - gap_a / 2.0
		for i in n_sl:
			var ra := br0 + i * (sl_w + sl_gap)
			U.put(g, U.ring_sector(ra, ra + sl_w, seat_y - sl_t, seat_y, a0, a1, 7, {"uvScale": 1}), wood_b if i % 2 else wood, [0, 0, 0])
		# seat rails under the slats
		U.put(g, U.ring_sector(2.12, 2.14, seat_y - sl_t - 0.05, seat_y - sl_t, a0 + 0.01, a1 - 0.01, 6), frame, [0, 0, 0])
		U.put(g, U.ring_sector(2.46, 2.48, seat_y - sl_t - 0.05, seat_y - sl_t, a0 + 0.01, a1 - 0.01, 6), frame, [0, 0, 0])
		# backrest (two curved slats, facing outward)
		U.put(g, U.ring_sector(2.025, 2.058, 0.57, 0.655, a0, a1, 7), wood, [0, 0, 0])
		U.put(g, U.ring_sector(2.025, 2.058, 0.715, 0.80, a0, a1, 7), wood_b, [0, 0, 0])
		sections.append({"th": th, "a0": a0, "a1": a1})
		legs.append(th + sec_a / 2.0)
	# leg frames at the section boundaries
	var kit = ctx.kit(g)
	for a in legs:
		var ca := cos(a)
		var sa := sin(a)
		var at := func(rr: float, y: float) -> Array: return [rr * ca, y, rr * sa]
		var ry: float = -a
		kit.box(0.045, 0.84, 0.045, frame, at.call(2.075, 0.42), [0, ry, 0])
		kit.box(0.045, seat_y - sl_t, 0.045, frame, at.call(2.46, (seat_y - sl_t) / 2.0), [0, ry, 0])
		kit.box(0.46, 0.035, 0.05, frame, at.call(2.28, seat_y - sl_t - 0.03), [0, ry, 0])
		kit.box(0.5, 0.03, 0.07, frame, at.call(2.28, 0.015), [0, ry, 0])
		kit.box(0.06, 0.02, 0.06, frame, at.call(2.075, 0.85), [0, ry, 0])

	# ---------------------------------------------------------------- items on the bench
	## the section whose centre is closest to a compass angle (atan2(z, x) in degrees)
	var sec_idx := func(deg: float) -> int:
		var best := 0
		var bd := 1e9
		for i in sections.size():
			var th: float = sections[i].th
			var d := absf(atan2(sin(th - deg * PI / 180.0), cos(th - deg * PI / 180.0)))
			if d < bd:
				bd = d
				best = i
		return best
	var s_south: int = sec_idx.call(90.0)
	var s_sw: int = sec_idx.call(138.0)
	var place_on_seat := func(theta: float, rad: float):
		var grp := T.Group.new()
		grp.position = Vector3(rad * cos(theta), seat_y, rad * sin(theta))
		grp.rotation.y = atan2(cos(theta), sin(theta))
		g.add(grp)
		return grp
	school_bag(ctx, place_on_seat.call(sections[s_south].th - 0.2, 2.2), TX)
	drink_cup(ctx, place_on_seat.call(sections[s_south].th + 0.24, 2.37))
	shopping_bag(ctx, place_on_seat.call(sections[s_sw].th + 0.08, 2.25), TX)
	# small brass donor plate on one backrest
	var plate = ctx.tex.draw(256, 64, null, {"key": "plaza-bench-plate"})
	var pth: float = sections[sec_idx.call(50.0)].th
	var pm := T.MeshObj.new(Geo.g_plane(ctx.cache), mat.toon("#ffffff", {"map": plate, "paint": 0.01, "polygonOffset": -1}))
	pm.scale = Vector3(0.2, 0.05, 1)
	pm.position = Vector3(2.063 * cos(pth), 0.757, 2.063 * sin(pth))
	pm.rotation.y = atan2(cos(pth), sin(pth))
	g.add(pm)

	# ---------------------------------------------------------------- physics and services
	physics.addCylinder(cx, cz, 1.72, 0, 1.4)
	var benches := []
	var used := [s_south, s_sw, 0]
	for i in sections.size():
		var th: float = sections[i].th
		var x := cx + 2.3 * cos(th)
		var z := cz + 2.3 * sin(th)
		var rot_y := atan2(cos(th), sin(th))
		var chord := 2.0 * 2.55 * sin(sec_a / 2.0)
		physics.addBox(x, z, chord, 0.6, rot_y, 0, 0.9)
		benches.append({"x": x, "z": z, "y": seat_y, "rotY": rot_y, "len": snappedf(2.0 * 2.3 * sin(sec_a / 2.0) - 0.1, 0.01), "_used": used.has(i)})
	benches = T.stable_sort(benches, func(p, q): return (1 if p._used else 0) - (1 if q._used else 0))
	var out := []
	for b in benches:
		out.append({"x": b.x, "z": b.z, "y": b.y, "rotY": b.rotY, "len": b.len})
	return out


## Crossed vertical quads (width 1, height 1, base at y = 0) with up-facing normals.
static func cross_quads(w: float = 1.0, h: float = 1.0, n: int = 2) -> T.Geometry:
	var pos := PackedFloat32Array()
	var nor := PackedFloat32Array()
	var uv := PackedFloat32Array()
	var idx := PackedInt32Array()
	var o := 0
	for i in n:
		var q := Geo.plane(w, h)
		q.translate(0, h / 2.0, 0)
		q.rotate_y((float(i) / n) * PI)
		pos.append_array(q.position().array)
		for k in q.attributes.normal.count():
			nor.append_array([0.0, 1.0, 0.0])
		uv.append_array(q.attributes.uv.array)
		for k in q.index:
			idx.append(k + o)
		o += q.position().count()
	var out := T.Geometry.new()
	out.set_attribute("position", T.Attr.new(pos, 3))
	out.set_attribute("normal", T.Attr.new(nor, 3))
	out.set_attribute("uv", T.Attr.new(uv, 2))
	out.set_index(idx)
	return out


# ---------------------------------------------------------------- bench items (local +Z outward, y = 0 is the seat top)

static func school_bag(ctx, grp, _tx: Dictionary) -> void:
	var mat = ctx.mat
	var navy = mat.toon("#3f4768", {"paint": 0.04})
	var navy_d = mat.toon("#353c5a", {"paint": 0.03})
	var tilt := T.Group.new()
	tilt.position = Vector3(0, 0, -0.055)
	tilt.rotation.x = -0.24
	grp.add(tilt)
	var t = ctx.kit(tilt)
	t.rbox(0.40, 0.29, 0.11, 0.03, navy, [0, 0.145, 0.055])
	t.rbox(0.38, 0.15, 0.02, 0.01, navy_d, [0, 0.215, 0.115])
	t.box(0.05, 0.035, 0.012, mat.toon("#c9ccd1"), [0, 0.15, 0.124])
	t.box(0.30, 0.012, 0.004, mat.toon("#e3d6b8"), [0, 0.268, 0.126])
	var emb = t.plane(0.06, 0.06, mat.decal("#ffffff", {"map": ctx.tex.draw(64, 64, null, {"key": "plaza-emblem"})}), [0.12, 0.225, 0.1265])
	emb.render_order = 1
	var h := T.MeshObj.new(Geo.torus(0.065, 0.011, 6, 14, PI), navy_d)
	h.position = Vector3(0, 0.29, 0.055)
	tilt.add(h)
	# keychain charm
	t.box(0.006, 0.05, 0.006, mat.toon("#e9e3d6"), [-0.05, 0.27, 0.12])
	t.sphere(0.022, mat.toon("#f2b5c8"), [-0.05, 0.235, 0.125], 10)


static func drink_cup(ctx, grp) -> void:
	var mat = ctx.mat
	var k = ctx.kit(grp)
	var glass = mat.glass({"tint": "#e8eef2", "opacity": 0.22, "streaks": false})
	var cup := T.MeshObj.new(Geo.cylinder(0.043, 0.034, 0.125, 16, 1, true), glass)
	cup.position = Vector3(0, 0.0625, 0)
	grp.add(cup)
	k.cyl(0.037, 0.033, 0.058, mat.toon("#f2b3c4", {"paint": 0.02}), [0, 0.031, 0], null, 14)
	k.cyl(0.0385, 0.0375, 0.008, mat.toon("#f7dde2", {"paint": 0.02}), [0, 0.062, 0], null, 14)
	k.cyl(0.044, 0.041, 0.042, mat.toon("#c9a77f", {"paint": 0.03}), [0, 0.07, 0], null, 16)
	var lid := T.MeshObj.new(Geo.sphere(0.044, 16, 6, 0, TAU, 0, PI / 2.0), glass)
	lid.scale = Vector3(1, 0.55, 1)
	lid.position = Vector3(0, 0.125, 0)
	grp.add(lid)
	k.cyl(0.046, 0.046, 0.006, mat.toon("#eef1f2"), [0, 0.126, 0], null, 16)
	k.cyl(0.0048, 0.0048, 0.22, mat.toon("#ee9ab0"), [0.008, 0.13, 0.004], [0.12, 0, 0.1], 6)


static func shopping_bag(ctx, grp, _tx: Dictionary) -> void:
	var mat = ctx.mat
	var k = ctx.kit(grp)
	var canvas = mat.toon("#c7d7b4", {"paint": 0.05})
	var inner = mat.toon("#8fa07e", {"paint": 0.03})
	var W := 0.36
	var H := 0.3
	var D := 0.15
	var t := 0.012
	k.box(W, t, D, inner, [0, t / 2.0, 0])
	k.box(W, H, t, canvas, [0, H / 2.0, D / 2.0 - t / 2.0])
	k.box(W, H, t, canvas, [0, H / 2.0, -D / 2.0 + t / 2.0])
	k.box(t, H, D - 2.0 * t, canvas, [W / 2.0 - t / 2.0, H / 2.0, 0])
	k.box(t, H, D - 2.0 * t, canvas, [-W / 2.0 + t / 2.0, H / 2.0, 0])
	k.box(W - 0.02, 0.2, D - 0.03, inner, [0, 0.1, 0])
	for zz in [D / 2.0 - t / 2.0, -D / 2.0 + t / 2.0]:
		var h := T.MeshObj.new(Geo.torus(0.075, 0.01, 5, 14, PI), mat.toon("#a9bb96"))
		h.position = Vector3(0, H, zz)
		grp.add(h)
	# printed shop-street logo on the front
	var logo = ctx.tex.draw(128, 96, null, {"key": "plaza-bag-logo"})
	k.plane(0.2, 0.15, mat.decal("#ffffff", {"map": logo}), [0, 0.15, D / 2.0 + 0.004])
	# leeks poking out, leaning outward
	var white = mat.toon("#eeeadf", {"paint": 0.03})
	var pale = mat.toon("#cfe0a6", {"paint": 0.03})
	var green = mat.toon("#6f9a4e", {"paint": 0.04})
	var leek := func(x: float, lean: float, twist: float, len: float) -> void:
		var lg := T.Group.new()
		lg.position = Vector3(x, 0.03, -0.01)
		lg.rotation = Vector3(lean, 0, twist)
		grp.add(lg)
		var lk = ctx.kit(lg)
		lk.cyl(0.017, 0.018, len * 0.45, white, [0, len * 0.225, 0], null, 8)
		lk.cyl(0.016, 0.017, len * 0.12, pale, [0, len * 0.51, 0], null, 8)
		for i in 3:
			var leaf := T.MeshObj.new(Geo.cylinder(0.004, 0.013, len * 0.42, 5), green)
			leaf.position = Vector3((i - 1) * 0.012, len * 0.78, 0)
			leaf.rotation.z = (i - 1) * 0.16
			leaf.rotation.x = -0.1 if i == 1 else 0.05
			leaf.cast_shadow = true
			lg.add(leaf)
	leek.call(-0.06, 0.34, 0.22, 0.6)
	leek.call(-0.02, 0.28, 0.12, 0.56)
	# milk carton and bread bag peeking out
	k.box(0.07, 0.2, 0.07, mat.toon("#eef0f2"), [0.1, 0.12, -0.01])
	k.box(0.072, 0.03, 0.072, mat.toon("#6a9ad0"), [0.1, 0.2, -0.01])
	k.rbox(0.13, 0.12, 0.1, 0.04, mat.toon("#e9cf9a"), [0.05, 0.25, 0.0])
