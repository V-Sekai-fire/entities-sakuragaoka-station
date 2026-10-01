# plaza/furniture.js: boards, the bus stop and shelter, taxi sign, postbox, phone booth, bicycle racks
# and roof, bollards, chain fences, sorted bins, lamps (off), the clock pillar, the 90th-anniversary
# monument, a drinking fountain, round planters, a park bench, a low station-name board and small
# lived-in details.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const U = preload("res://addons/sakuragaoka_station/world/plaza/util.gd")


## Returns {benches: [...]} for ctx.services.plaza.
static func build_furniture(ctx, root, TX: Dictionary, S: Dictionary, P: Dictionary) -> Dictionary:
	var mat = ctx.mat
	var out := {"benches": []}
	var M := {
		"slate": mat.toon("#4a5667", {"paint": 0.04}),
		"frame": mat.toon("#56615e", {"paint": 0.04}),
		"steel": mat.toon("#b3bac1", {"paint": 0.03}),
		"steelD": mat.toon("#7d858d", {"paint": 0.03}),
		"concrete": mat.toon("#ffffff", {"map": TX.concrete, "paint": 0.06}),
		"wood": mat.toon("#8a6446", {"paint": 0.06}),
		"woodL": mat.toon("#ffffff", {"map": TX.wood, "paint": 0.05}),
		"woodPanel": mat.toon("#b58c64", {"map": TX.wood, "paint": 0.05}),
		"roofGreen": mat.toon("#4d6457", {"paint": 0.05}),
		"roofBlue": mat.toon("#56677a", {"paint": 0.05}),
		"cream": mat.toon("#e6e1d4", {"paint": 0.04}),
		"dark": mat.toon("#3a3346"),
		"white": mat.toon("#ebe8e0", {"paint": 0.03}),
	}
	_map_board(ctx, root, M, S, P)
	_tour_board(ctx, root, M, S, P)
	_notice_board(ctx, root, M, S, P)
	_bus_stop(ctx, root, M, S)
	_bus_shelter(ctx, root, M, S, P, out)
	_taxi_sign(ctx, root, M, S)
	_postbox(ctx, root, M, S, P)
	_phone_booth(ctx, root, M, S, P)
	_bike_parking(ctx, root, M, S, P)
	_bollards(ctx, root, M, P)
	_chains(ctx, root, M, P)
	_bins(ctx, root, M, S, P)
	_lamps(ctx, root, P)
	_clock(ctx, root, TX, S, P)
	_monument(ctx, root, TX, S, P)
	_fountain(ctx, root, M, TX, P)
	_planters(ctx, root, M, TX, P)
	_park_bench(ctx, root, M, P, out)
	_name_sign(ctx, root, P)
	_details(ctx, root, M, P)
	return out


static func _face_mat(ctx, tex):
	return ctx.mat.toon("#ffffff", {"map": tex, "paint": 0.012, "polygonOffset": -1})


## A textured face plane (w x h) in a parent, facing +Z before rot_y.
static func _face(ctx, parent, w: float, h: float, tex, pos: Array, rot_y: float = 0.0, material = null):
	var m := T.MeshObj.new(Geo.g_plane(ctx.cache), material if material != null else _face_mat(ctx, tex))
	m.scale = Vector3(w, h, 1)
	m.position = Vector3(pos[0], pos[1], pos[2])
	m.rotation.y = rot_y
	m.receive_shadow = true
	m.cast_shadow = false
	parent.add(m)
	return m


static func _group(root, x: float, z: float, rot_y: float = 0.0, y: float = 0.0):
	var g := T.Group.new()
	g.position = Vector3(x, y, z)
	g.rotation.y = rot_y
	root.add(g)
	return g


## The station-area map board (double sided).
static func _map_board(ctx, root, M: Dictionary, S: Dictionary, P: Dictionary) -> void:
	var o: Dictionary = P.mapBoard
	var g = _group(root, o.x, o.z, o.rotY)
	var k = ctx.kit(g)
	for s in [-1.0, 1.0]:
		k.boxb(0.08, 2.18, 0.08, M.slate, [s * 0.87, 0, 0])
		k.boxb(0.18, 0.06, 0.18, M.concrete, [s * 0.87, 0, 0])
		k.sphere(0.05, M.slate, [s * 0.87, 2.2, 0], 10)
	k.rbox(1.76, 1.36, 0.08, 0.025, M.slate, [0, 1.35, 0])
	_face(ctx, g, 1.6, 1.2, S.map, [0, 1.35, 0.045])
	_face(ctx, g, 1.6, 1.2, S.plazaGuide, [0, 1.35, -0.045], PI)
	k.rbox(1.9, 0.07, 0.16, 0.025, M.slate, [0, 2.07, 0])
	k.box(1.62, 0.05, 0.02, ctx.mat.toon("#ef9fbe"), [0, 2.0, 0.05])
	ctx.physics.addBox(o.x, o.z, 1.95, 0.24, o.rotY, 0, 2.3)


## The wooden tourist board with a small roof.
static func _tour_board(ctx, root, M: Dictionary, S: Dictionary, P: Dictionary) -> void:
	var o: Dictionary = P.tourBoard
	var g = _group(root, o.x, o.z, o.rotY)
	var k = ctx.kit(g)
	for s in [-1.0, 1.0]:
		k.boxb(0.1, 2.3, 0.1, M.wood, [s * 0.88, 0, 0])
		k.boxb(0.2, 0.08, 0.2, M.concrete, [s * 0.88, 0, 0])
	k.box(1.78, 1.38, 0.07, M.wood, [0, 1.36, 0])
	_face(ctx, g, 1.6, 1.2, S.tourist, [0, 1.36, 0.04])
	# back: plank panel
	U.put(g, U.box_uv(1.66, 1.26, 0.01, 1), M.woodPanel, [0, 1.36, -0.04])
	for i in 5:
		k.box(1.66, 0.008, 0.012, ctx.mat.toon("#6e5038"), [0, 0.8 + i * 0.25, -0.046])
	# roof (two slopes and a ridge)
	for s in [-1.0, 1.0]:
		k.box(1.08, 0.04, 0.44, M.roofGreen, [s * 0.5, 2.37, 0], [0, 0, -s * 0.36])
	k.box(0.12, 0.06, 0.46, M.roofGreen, [0, 2.56, 0])
	k.box(1.9, 0.08, 0.1, M.wood, [0, 2.2, 0])
	k.box(0.9, 0.18, 0.02, ctx.mat.toon("#f1e6cf"), [0, 2.08, 0.05])
	var welcome = ctx.tex.sign({"w": 512, "h": 96, "bg": "#f1e6cf", "fg": "#4a3438", "text": "さくらの町へ ようこそ", "font": ctx.tex.FONTS.brush, "weight": 400, "key": "plaza-welcome"})
	_face(ctx, g, 0.88, 0.16, welcome, [0, 2.08, 0.062])
	ctx.physics.addBox(o.x, o.z, 1.95, 0.3, o.rotY, 0, 2.6)


## The community notice board.
static func _notice_board(ctx, root, M: Dictionary, S: Dictionary, P: Dictionary) -> void:
	var o: Dictionary = P.noticeBoard
	var g = _group(root, o.x, o.z, o.rotY)
	var k = ctx.kit(g)
	var post = ctx.mat.toon("#5f6f6a", {"paint": 0.04})
	for s in [-1.0, 1.0]:
		k.boxb(0.07, 2.25, 0.07, post, [s * 0.98, 0, 0])
		k.boxb(0.16, 0.06, 0.16, M.concrete, [s * 0.98, 0, 0])
	k.box(1.96, 1.26, 0.05, M.wood, [0, 1.25, 0])
	_face(ctx, g, 1.8, 1.125, S.notice, [0, 1.25, 0.029])
	k.box(1.96, 0.05, 0.08, M.wood, [0, 1.86, 0.01])
	k.box(1.96, 0.05, 0.08, M.wood, [0, 0.64, 0.01])
	k.box(1.04, 0.2, 0.03, M.wood, [0, 2.0, 0])
	_face(ctx, g, 1.0, 0.156, S.noticeHeader, [0, 2.0, 0.018])
	k.box(2.2, 0.035, 0.46, M.roofBlue, [0, 2.2, 0.06], [0.2, 0, 0])
	for s in [-1.0, 1.0]:
		k.box(0.04, 0.04, 0.34, post, [s * 0.98, 2.16, 0.08], [0.2, 0, 0])
	ctx.physics.addBox(o.x, o.z, 2.1, 0.3, o.rotY, 0, 2.4)


## The bus stop pole: round sign on top, timetable box.
static func _bus_stop(ctx, root, M: Dictionary, S: Dictionary) -> void:
	var o: Dictionary = ctx.L.PLAZA.busStop
	var g = _group(root, o.x, o.z, 0.0)
	var k = ctx.kit(g)
	k.cyl(0.25, 0.27, 0.1, M.concrete, [0, 0.05, 0], null, 20)
	k.cyl(0.12, 0.2, 0.04, ctx.mat.toon("#8e959d"), [0, 0.12, 0], null, 16)
	k.cyl(0.032, 0.032, 1.78, M.steel, [0, 0.99, 0], null, 10)
	# round sign on top of the pole (faces east and west, along the road)
	var disc := Geo.circle(0.25, 28)
	var sg := T.Group.new()
	sg.position = Vector3(0, 2.12, 0)
	sg.rotation.y = PI / 2.0
	g.add(sg)
	k.box(0.05, 0.1, 0.05, M.steel, [0, 1.88, 0])
	ctx.kit(sg).cyl(0.255, 0.255, 0.024, ctx.mat.toon("#e78fae"), [0, 0, 0], [PI / 2.0, 0, 0], 28)
	for s in [1.0, -1.0]:
		var m := T.MeshObj.new(disc, _face_mat(ctx, S.busRound))
		m.position.z = s * 0.0135
		m.rotation.y = 0.0 if s > 0 else PI
		sg.add(m)
	# timetable box
	var tg := T.Group.new()
	tg.position = Vector3(0, 1.28, 0)
	tg.rotation.y = PI / 2.0
	g.add(tg)
	ctx.kit(tg).box(0.36, 0.6, 0.1, M.white, [0, 0, 0])
	_face(ctx, tg, 0.32, 0.56, S.busTable, [0, 0, 0.052])
	_face(ctx, tg, 0.32, 0.56, S.busTable, [0, 0, -0.052], PI)
	ctx.kit(tg).box(0.38, 0.03, 0.12, ctx.mat.toon("#e78fae"), [0, 0.31, 0])
	ctx.physics.addCylinder(o.x, o.z, 0.28, 0, 2.4)


## The bus shelter (opening faces south, +Z) and its bench.
static func _bus_shelter(ctx, root, M: Dictionary, S: Dictionary, P: Dictionary, out: Dictionary) -> void:
	var PH = ctx.physics
	var o: Dictionary = P.shelter
	var x: float = o.x
	var z: float = o.z
	var w: float = o.w
	var g = _group(root, x, z, 0.0)
	var k = ctx.kit(g)
	var post = ctx.mat.toon("#5d6c70", {"paint": 0.04})
	var depth := 1.75
	var H := 2.42
	for s in [-1.0, 1.0]:
		k.boxb(0.1, H, 0.1, post, [s * (w / 2.0 - 0.1), 0, 0])
		k.boxb(0.22, 0.05, 0.22, M.concrete, [s * (w / 2.0 - 0.1), 0, 0])
		k.box(0.08, 0.12, depth - 0.1, post, [s * (w / 2.0 - 0.1), H - 0.02, depth / 2.0 - 0.08])
	# curved roof (arched profile extruded along x)
	var pts := []
	var th := 0.05
	var n := 10
	for i in n + 1:
		var u := float(i) / n
		pts.append([-depth / 2.0 - 0.08 + u * (depth + 0.16), 0.1 * sin(PI * u)])
	for i in range(n, -1, -1):
		var u := float(i) / n
		pts.append([-depth / 2.0 - 0.08 + u * (depth + 0.16), 0.1 * sin(PI * u) - th])
	U.put(g, Geo.extrude(pts, w + 0.2), ctx.mat.toon("#e3e0d8", {"paint": 0.04}), [0, H + 0.06, depth / 2.0 - 0.08], [0, PI / 2.0, 0])
	# fascia with the stop name
	k.box(w + 0.2, 0.26, 0.04, ctx.mat.toon("#f1ede4"), [0, H - 0.04, depth - 0.02])
	_face(ctx, g, w + 0.1, (w + 0.1) * 96.0 / 1024.0, S.shelterFascia, [0, H - 0.04, depth + 0.003])
	# back glass wall and rails
	var gw := w - 0.3
	var glass := T.MeshObj.new(Geo.g_plane(ctx.cache), ctx.mat.glass({"tint": "#a9c1cf", "opacity": 0.2}))
	glass.scale = Vector3(gw, 1.75, 1)
	glass.position = Vector3(0, 1.2, 0)
	g.add(glass)
	k.box(gw, 0.05, 0.05, post, [0, 0.3, 0])
	k.box(gw, 0.05, 0.05, post, [0, 2.08, 0])
	k.box(0.04, 1.75, 0.04, post, [-0.35, 1.2, 0])
	# route map on the back wall (inside, facing south)
	k.box(0.86, 0.4, 0.03, M.white, [0.75, 1.55, 0.04])
	_face(ctx, g, 0.8, 0.35, S.routeMap, [0.75, 1.55, 0.057])
	# east side: lit advertising panel (both sides)
	var ag := T.Group.new()
	ag.position = Vector3(w / 2.0 - 0.1, 0, 0.52)
	g.add(ag)
	ctx.kit(ag).box(0.12, 1.86, 0.92, post, [0, 1.13, 0])
	var ad_m = ctx.mat.emissive("#ffffff", 0.92, {"map": S.shelterAd})
	for s in [-1.0, 1.0]:
		_face(ctx, ag, 0.8, 1.6, S.shelterAd, [s * 0.062, 1.15, 0], s * PI / 2.0, ad_m)
	# bench (slats on two legs) facing south
	var bz := 0.33
	var bl := w - 0.7
	for s in [-1.0, 1.0]:
		k.boxb(0.05, 0.4, 0.34, post, [s * (bl / 2.0 - 0.2), 0, bz])
	for i in 3:
		k.box(bl, 0.035, 0.1, M.woodL, [0, 0.4225, bz - 0.12 + i * 0.12])
	k.box(bl, 0.08, 0.03, M.woodL, [0, 0.72, 0.1])
	for s in [-1.0, 1.0]:
		k.box(0.04, 0.34, 0.04, post, [s * (bl / 2.0 - 0.2), 0.6, 0.1])
	out.benches.append({"x": x, "z": z + bz, "y": 0.44, "rotY": 0.0, "len": snappedf(bl, 0.01)})
	# forgotten folding umbrella and a folded newspaper on the bench
	var um := T.Group.new()
	um.position = Vector3(0.55, 0.44 + 0.03, bz + 0.02)
	um.rotation = Vector3(0, 0.25, PI / 2.0)
	g.add(um)
	var uk = ctx.kit(um)
	uk.cyl(0.028, 0.02, 0.26, ctx.mat.toon("#5a6a92"), [0, 0, 0], null, 8)
	uk.cyl(0.012, 0.012, 0.06, M.steelD, [0, 0.16, 0], null, 6)
	uk.cyl(0.016, 0.016, 0.07, ctx.mat.toon("#3f3a44"), [0, -0.165, 0], null, 8)
	var np := T.Group.new()
	np.position = Vector3(-0.62, 0.44, bz - 0.02)
	np.rotation.y = 0.15
	g.add(np)
	ctx.kit(np).box(0.3, 0.012, 0.21, ctx.mat.toon("#e4e0d6"), [0, 0.006, 0])
	var news = ctx.tex.draw(256, 176, null, {"key": "plaza-newspaper"})
	_face(ctx, np, 0.28, 0.19, news, [0, 0.0125, 0], 0.0).rotation = Vector3(-PI / 2.0, 0, 0)
	# colliders
	PH.addBox(x, z, w, 0.14, 0, 0, 2.3)
	PH.addBox(x + w / 2.0 - 0.1, z + 0.52, 0.14, 0.95, 0, 0, 2.3)
	PH.addBox(x, z + bz, bl, 0.38, 0, 0, 0.62)
	for s in [-1.0, 1.0]:
		PH.addCylinder(x + s * (w / 2.0 - 0.1), z, 0.09, 0, 2.5)


## The taxi stand sign.
static func _taxi_sign(ctx, root, M: Dictionary, S: Dictionary) -> void:
	var o: Dictionary = ctx.L.PLAZA.taxiStand
	var g = _group(root, o.x, o.z, 0.0)
	var k = ctx.kit(g)
	k.boxb(0.3, 0.08, 0.3, M.concrete, [0, 0, 0])
	k.cyl(0.03, 0.03, 2.35, M.steel, [0, 1.2, 0], null, 10)
	var sz := 0.05
	k.box(0.46, 0.57, 0.03, ctx.mat.toon("#2f4a78"), [0, 1.98, sz])
	_face(ctx, g, 0.44, 0.55, S.taxi, [0, 1.98, sz + 0.017])
	_face(ctx, g, 0.44, 0.55, S.taxi, [0, 1.98, sz - 0.017], PI)
	for yy in [1.8, 2.16]:
		k.box(0.08, 0.03, 0.05, M.steelD, [0, yy, 0.025])
	k.box(0.4, 0.13, 0.02, M.white, [0, 1.45, sz - 0.005])
	var tq = ctx.tex.sign({"w": 384, "h": 128, "bg": "#efece4", "fg": "#2f3a58", "text": "順番にお並びください", "sub": "Please wait in line", "size": 44, "key": "plaza-taxi-queue"})
	_face(ctx, g, 0.38, 0.125, tq, [0, 1.45, sz + 0.007])
	_face(ctx, g, 0.38, 0.125, tq, [0, 1.45, sz - 0.017], PI)
	k.cyl(0.035, 0.035, 0.03, M.steel, [0, 2.36, 0], null, 10)
	ctx.physics.addCylinder(o.x, o.z, 0.16, 0, 2.4)


## The red round-top postbox.
static func _postbox(ctx, root, M: Dictionary, S: Dictionary, P: Dictionary) -> void:
	var mat = ctx.mat
	var o: Dictionary = P.postbox
	var g = _group(root, o.x, o.z, o.rotY)
	var k = ctx.kit(g)
	var red = mat.toon("#cc463c", {"paint": 0.04})
	var red_d = mat.toon("#a93a34", {"paint": 0.03})
	k.boxb(0.44, 0.06, 0.44, M.concrete, [0, 0, 0])
	k.cyl(0.13, 0.15, 0.28, red_d, [0, 0.2, 0], null, 18)
	k.cyl(0.2, 0.2, 0.84, red, [0, 0.76, 0], null, 24)
	k.cyl(0.215, 0.215, 0.04, red_d, [0, 0.36, 0], null, 24)
	k.cyl(0.228, 0.228, 0.035, red_d, [0, 1.19, 0], null, 24)
	var dome := T.MeshObj.new(Geo.sphere(0.222, 24, 10, 0, TAU, 0, PI / 2.0), red)
	dome.scale = Vector3(1, 0.62, 1)
	dome.position = Vector3(0, 1.205, 0)
	dome.cast_shadow = true
	dome.receive_shadow = true
	g.add(dome)
	k.sphere(0.03, red_d, [0, 1.34, 0], 10)
	# slot with a little hood
	k.box(0.16, 0.035, 0.03, M.dark, [0, 1.04, 0.192])
	k.box(0.2, 0.02, 0.06, red_d, [0, 1.07, 0.195])
	# curved front label and collection times on the side
	var lab := T.MeshObj.new(Geo.cylinder(0.202, 0.202, 0.32, 10, 1, true, -0.42, 0.84), mat.toon("#ffffff", {"map": S.postFront, "paint": 0.01, "polygonOffset": -1}))
	lab.position = Vector3(0, 0.8, 0)
	g.add(lab)
	var tim := T.MeshObj.new(Geo.cylinder(0.202, 0.202, 0.13, 8, 1, true, PI / 2.0 - 0.34, 0.68), mat.toon("#ffffff", {"map": S.postTimes, "paint": 0.01, "polygonOffset": -1}))
	tim.position = Vector3(0, 0.62, 0)
	g.add(tim)
	# collection door (back)
	k.box(0.2, 0.36, 0.02, red_d, [0, 0.7, -0.195])
	k.box(0.03, 0.03, 0.02, M.steel, [0.06, 0.72, -0.21])
	ctx.physics.addCylinder(o.x, o.z, 0.24, 0, 1.4)


## The public phone booth.
static func _phone_booth(ctx, root, M: Dictionary, S: Dictionary, P: Dictionary) -> void:
	var mat = ctx.mat
	var o: Dictionary = P.phone
	var g = _group(root, o.x, o.z, o.rotY)
	var k = ctx.kit(g)
	var fr = mat.toon("#cdd1d2", {"paint": 0.03})
	var green = mat.toon("#4f9a6e", {"paint": 0.04})
	var W := 0.92
	var H := 2.08
	k.boxb(W + 0.06, 0.1, W + 0.06, mat.toon("#9aa1a8"), [0, 0, 0])
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.boxb(0.06, H, 0.06, fr, [sx * (W / 2.0 - 0.03), 0.1, sz * (W / 2.0 - 0.03)])
	# kick panels and rails
	var sides := [[0.0, W / 2.0 - 0.03, 0.0], [0.0, -(W / 2.0 - 0.03), PI], [W / 2.0 - 0.03, 0.0, PI / 2.0], [-(W / 2.0 - 0.03), 0.0, -PI / 2.0]]
	var gl = mat.glass({"tint": "#a6bfcc", "opacity": 0.18})
	for sd in sides:
		var sg := T.Group.new()
		sg.position = Vector3(sd[0], 0, sd[1])
		sg.rotation.y = sd[2]
		g.add(sg)
		var sk = ctx.kit(sg)
		sk.box(W - 0.1, 0.3, 0.03, fr, [0, 0.27, 0])
		sk.box(W - 0.1, 0.04, 0.04, fr, [0, 1.02, 0])
		var p := T.MeshObj.new(Geo.g_plane(ctx.cache), gl)
		p.scale = Vector3(W - 0.1, H - 0.34, 1)
		p.position = Vector3(0, 0.42 + (H - 0.34) / 2.0, 0)
		sg.add(p)
	# door handle and folding split on the front
	k.box(0.02, 1.5, 0.03, fr, [0.0, 1.2, W / 2.0 - 0.02])
	k.box(0.02, 0.3, 0.03, M.steelD, [0.08, 1.15, W / 2.0 + 0.01])
	# header band with signs on four sides, roof
	k.box(W + 0.02, 0.2, W + 0.02, green, [0, H + 0.2, 0])
	for sd in sides:
		var sg := T.Group.new()
		sg.position = Vector3(sd[0] * (W / 2.0 + 0.012) / (W / 2.0 - 0.03), H + 0.2, sd[1] * (W / 2.0 + 0.012) / (W / 2.0 - 0.03))
		sg.rotation.y = sd[2]
		g.add(sg)
		_face(ctx, sg, 0.72, 0.18, S.phoneSign, [0, 0, 0])
	k.rbox(W + 0.14, 0.1, W + 0.14, 0.04, mat.toon("#e2e5e3", {"paint": 0.03}), [0, H + 0.35, 0])
	# interior: back mounting panel, phone, shelf, directory, notice
	k.box(0.62, 1.05, 0.025, mat.toon("#b9c3bf", {"paint": 0.03}), [0, 1.47, -W / 2.0 + 0.03])
	var phone = mat.toon("#8fae9c", {"paint": 0.03})
	k.rbox(0.26, 0.38, 0.14, 0.03, phone, [0, 1.38, -W / 2.0 + 0.11])
	k.box(0.16, 0.08, 0.01, mat.toon("#3f4a4a"), [0, 1.48, -W / 2.0 + 0.185])
	k.box(0.14, 0.12, 0.01, mat.toon("#dfe3df"), [0, 1.33, -W / 2.0 + 0.185])
	k.rbox(0.055, 0.22, 0.06, 0.02, mat.toon("#6f8e7d"), [-0.17, 1.38, -W / 2.0 + 0.13])
	k.box(0.5, 0.03, 0.28, fr, [0, 1.0, -W / 2.0 + 0.16])
	var book := T.Group.new()
	book.position = Vector3(0.08, 1.015, -W / 2.0 + 0.17)
	book.rotation.y = 0.12
	g.add(book)
	ctx.kit(book).box(0.22, 0.05, 0.16, mat.toon("#e8c547"), [0, 0.025, 0])
	_face(ctx, book, 0.2, 0.15, S.phoneBook, [0, 0.051, 0]).rotation = Vector3(-PI / 2.0, 0, 0)
	_face(ctx, g, 0.17, 0.17, S.phoneNotice, [0.215, 1.8, -W / 2.0 + 0.044])
	ctx.physics.addBox(o.x, o.z, W + 0.1, W + 0.1, o.rotY, 0, 2.6)


## Bicycle parking: front-wheel racks, the roof over the north row, notices and the corner sign.
static func _bike_parking(ctx, root, M: Dictionary, S: Dictionary, P: Dictionary) -> void:
	var mat = ctx.mat
	var PH = ctx.physics
	var rows: Array = ctx.L.PLAZA.bikeRows
	var rack_m = mat.toon("#9aa3aa", {"paint": 0.03})
	var rack_d = mat.toon("#6d747c", {"paint": 0.03})
	# a low steel base frame and a pair of bent-pipe wheel hoops per slot
	var hoop_geo := Geo.torus(0.2, 0.011, 5, 12, PI)
	for row in rows:
		var slots := []
		var sx: float = row.x0
		while sx <= row.x1 + 1e-6:
			slots.append(sx)
			sx += row.step
		var x0: float = slots[0] - 0.35
		var x1: float = slots[slots.size() - 1] + 0.35
		var len := x1 - x0
		var xc := (x0 + x1) / 2.0
		var zf: float = row.z - 0.92
		var zb: float = row.z - 0.32
		var zh: float = row.z - 0.6
		var g = _group(root, 0.0, 0.0, 0.0)
		var k = ctx.kit(g)
		k.box(len, 0.04, 0.05, rack_d, [xc, 0.04, zf])
		k.box(len, 0.04, 0.05, rack_d, [xc, 0.04, zb])
		for s in [x0, x1]:
			k.box(0.05, 0.04, zb - zf + 0.05, rack_d, [s, 0.04, (zf + zb) / 2.0])
			k.boxb(0.05, 0.36, 0.05, rack_m, [s, 0, zf])
		k.cyl(0.018, 0.018, len, rack_m, [xc, 0.36, zf], [0, 0, PI / 2.0], 8)
		for slot_x in slots:
			for d in [-0.046, 0.046]:
				var h := T.MeshObj.new(hoop_geo, rack_m)
				h.position = Vector3(slot_x + d, 0.06, zh)
				h.rotation.y = PI / 2.0
				h.cast_shadow = true
				h.receive_shadow = true
				g.add(h)
			for d in [-0.046, 0.046]:
				k.box(0.022, 0.03, zb - zf, rack_d, [slot_x + d, 0.045, (zf + zb) / 2.0])
		# slot numbers on the back rail
		var nums := T.MeshObj.new(Geo.g_plane(ctx.cache), _face_mat(ctx, S.slotNums))
		nums.scale = Vector3(0.75 * 12, 0.055, 1)
		nums.position = Vector3(row.x0 - 0.375 + 0.75 * 6, 0.072, zb + 0.031)
		g.add(nums)
		PH.addBox(xc, (zf + zb) / 2.0, len, zb - zf + 0.12, 0, 0, 0.5)
	# roof over the north row
	var nrow: Dictionary = rows[1]
	var rg = _group(root, 0.0, 0.0, 0.0)
	var rk = ctx.kit(rg)
	var post = mat.toon("#6f8a80", {"paint": 0.04})
	var zP: float = nrow.z - 1.3
	var zF: float = nrow.z + 1.25
	var xa: float = nrow.x0 - 0.55
	var xb: float = nrow.x1 + 0.35
	var hB := 2.35
	var hF := 2.2
	var pxs := [xa + 0.1, (xa + xb) / 2.0, xb - 0.1]
	for px in pxs:
		rk.boxb(0.1, hB, 0.1, post, [px, 0, zP])
		rk.boxb(0.22, 0.05, 0.22, M.concrete, [px, 0, zP])
		var beam_len := sqrt((zF - zP + 0.1) ** 2 + (hB - hF) ** 2)
		rk.box(0.08, 0.1, beam_len, post, [px, (hB + hF) / 2.0 - 0.02, (zP + zF) / 2.0], [atan2(hB - hF, zF - zP), 0, 0])
		PH.addCylinder(px, zP, 0.09, 0, 2.5)
	var slope := atan2(hB - hF, zF - zP)
	var panel := T.MeshObj.new(Geo.g_plane(ctx.cache), mat.glass({"tint": "#9fc4b8", "opacity": 0.42}))
	panel.scale = Vector3(xb - xa + 0.2, zF - zP + 0.3, 1)
	panel.position = Vector3((xa + xb) / 2.0, (hB + hF) / 2.0 + 0.06, (zP + zF) / 2.0)
	panel.rotation.x = -PI / 2.0 + slope
	panel.cast_shadow = true
	rg.add(panel)
	for i in range(1, 9):
		rk.box(0.03, 0.02, zF - zP + 0.3, post, [xa - 0.1 + (xb - xa + 0.2) * i / 9, (hB + hF) / 2.0 + 0.075, (zP + zF) / 2.0], [slope, 0, 0])
	rk.box(xb - xa + 0.24, 0.12, 0.06, post, [(xa + xb) / 2.0, hF - 0.02, zF + 0.14])
	rk.box(xb - xa + 0.24, 0.1, 0.06, post, [(xa + xb) / 2.0, hB + 0.02, zP - 0.16])
	# no-abandoned-bicycles notice on the west post
	var ng = _group(root, pxs[0] - 0.056, zP, -PI / 2.0)
	_face(ctx, ng, 0.34, 0.425, S.bikeNotice, [0, 1.35, 0])
	ctx.kit(ng).box(0.36, 0.445, 0.01, M.white, [0, 1.35, -0.006])
	# parking sign on its own post at the south-west corner of the bike area
	var o: Dictionary = P.bikeSign
	var g = _group(root, o.x, o.z, o.rotY)
	var k = ctx.kit(g)
	k.boxb(0.24, 0.06, 0.24, M.concrete, [0, 0, 0])
	k.cyl(0.035, 0.035, 2.25, M.steel, [0, 1.15, 0], null, 10)
	k.box(0.92, 0.28, 0.035, mat.toon("#2f64b5"), [0, 2.05, 0.03])
	_face(ctx, g, 0.9, 0.253, S.bikeSign, [0, 2.05, 0.05])
	k.box(0.34, 0.425, 0.012, M.white, [0, 1.3, 0.042])
	_face(ctx, g, 0.32, 0.4, S.bikeNotice, [0, 1.3, 0.05])
	PH.addCylinder(o.x, o.z, 0.14, 0, 2.3)


static func _bollards(ctx, root, M: Dictionary, P: Dictionary) -> void:
	var mat = ctx.mat
	var body = mat.toon("#b9c0c6", {"paint": 0.03})
	var band = mat.toon("#e8c547")
	var cap = mat.toon("#9ca4ab")
	for bp in P.bollards:
		var g = _group(root, bp[0], bp[1], 0.0)
		var k = ctx.kit(g)
		k.cyl(0.075, 0.075, 0.04, M.concrete, [0, 0.03, 0], null, 12)
		k.cyl(0.055, 0.058, 0.74, body, [0, 0.4, 0], null, 12)
		k.cyl(0.058, 0.058, 0.06, band, [0, 0.66, 0], null, 12)
		var d := T.MeshObj.new(Geo.sphere(0.055, 12, 5, 0, TAU, 0, PI / 2.0), cap)
		d.position.y = 0.77
		d.cast_shadow = true
		g.add(d)
		ctx.physics.addCylinder(bp[0], bp[1], 0.08, 0, 0.9)


static func _chains(ctx, root, M: Dictionary, P: Dictionary) -> void:
	var chain_post = ctx.mat.toon("#56615e", {"paint": 0.03})
	for run in P.chains:
		var xa: float = run[0]
		var xb: float = run[1]
		var zc: float = run[2]
		var n := maxi(1, int(T.js_round((xb - xa) / 1.45)))
		var posts := []
		for i in n + 1:
			posts.append(xa + (xb - xa) * i / n)
		for px in posts:
			var g = _group(root, px, zc, 0.0)
			var k = ctx.kit(g)
			k.cyl(0.06, 0.07, 0.04, M.concrete, [0, 0.03, 0], null, 10)
			k.cyl(0.035, 0.035, 0.6, chain_post, [0, 0.33, 0], null, 10)
			k.sphere(0.045, chain_post, [0, 0.65, 0], 10)
			ctx.physics.addCylinder(px, zc, 0.06, 0, 0.8)
		for i in posts.size() - 1:
			var pts := Geo.catenary([posts[i] + 0.03, 0.56, zc], [posts[i + 1] - 0.03, 0.56, zc], 0.13, 14)
			ctx.wires.add(pts, {"width": 0.018, "color": "#4f4a55"})
		ctx.physics.addBox((xa + xb) / 2.0, zc, xb - xa, 0.12, 0, 0, 0.75)


static func _bins(ctx, root, M: Dictionary, S: Dictionary, P: Dictionary) -> void:
	for b in P.bins:
		var g = _group(root, b.x, b.z, b.rotY)
		var k = ctx.kit(g)
		var body = ctx.mat.toon("#cbd2cc", {"paint": 0.04})
		var labs := [S.binBurn, S.binCan, S.binPet]
		var holes := ["slot", "round", "round"]
		for i in 3:
			var bx := (i - 1) * 0.36
			k.rbox(0.34, 0.86, 0.4, 0.03, body, [bx, 0.46, 0])
			_face(ctx, g, 0.25, 0.25, labs[i], [bx, 0.56, 0.203])
			if holes[i] == "slot":
				k.box(0.2, 0.05, 0.02, M.dark, [bx, 0.8, 0.198])
			else:
				var h := T.MeshObj.new(Geo.circle(0.055, 14), M.dark)
				h.position = Vector3(bx, 0.79, 0.2015)
				g.add(h)
		k.box(1.1, 0.04, 0.44, M.concrete, [0, 0.02, 0])
		k.rbox(1.14, 0.06, 0.46, 0.02, ctx.mat.toon("#5f7f7a", {"paint": 0.04}), [0, 0.92, 0])
		ctx.physics.addBox(b.x, b.z, 1.14, 0.46, b.rotY, 0, 1.0)


## Plaza lamps (off in daylight).
static func _lamps(ctx, root, P: Dictionary) -> void:
	var lamp_post = ctx.mat.toon("#55605d", {"paint": 0.04})
	var globe = ctx.mat.toon("#eeebe3", {"paint": 0.02})
	for lp in P.lamps:
		var g = _group(root, lp[0], lp[1], 0.0)
		var k = ctx.kit(g)
		k.cyl(0.1, 0.14, 0.42, lamp_post, [0, 0.21, 0], null, 12)
		k.cyl(0.05, 0.062, 3.5, lamp_post, [0, 2.17, 0], null, 10)
		k.cyl(0.075, 0.075, 0.08, lamp_post, [0, 3.95, 0], null, 12)
		k.cyl(0.14, 0.12, 0.34, globe, [0, 4.16, 0], null, 16)
		k.cyl(0.03, 0.23, 0.13, lamp_post, [0, 4.39, 0], null, 16)
		k.sphere(0.035, lamp_post, [0, 4.47, 0], 8)
		ctx.physics.addCylinder(lp[0], lp[1], 0.14, 0, 4.5)


## The clock pillar. Its hands are a dynamic group posed at the sim clock's 16:02 (animation stays
## out of the port).
static func _clock(ctx, root, TX: Dictionary, S: Dictionary, P: Dictionary) -> void:
	var mat = ctx.mat
	var lamp_post = mat.toon("#55605d", {"paint": 0.04})
	var o: Dictionary = P.clock
	var g = _group(root, o.x, o.z, o.rotY)
	var k = ctx.kit(g)
	k.box(0.44, 0.3, 0.44, mat.toon("#ffffff", {"map": TX.granite, "paint": 0.05}), [0, 0.15, 0])
	k.cyl(0.075, 0.08, 3.1, lamp_post, [0, 1.85, 0], null, 12)
	k.cyl(0.345, 0.345, 0.16, lamp_post, [0, 3.62, 0], [PI / 2.0, 0, 0], 32)
	k.sphere(0.06, lamp_post, [0, 4.0, 0], 10)
	k.cyl(0.02, 0.02, 0.06, lamp_post, [0, 3.97, 0], null, 6)
	var dial := Geo.circle(0.31, 36)
	var hand_groups := []
	for s in [1.0, -1.0]:
		var d := T.MeshObj.new(dial, _face_mat(ctx, S.clock))
		d.position = Vector3(0, 3.62, s * 0.081)
		d.rotation.y = 0.0 if s > 0 else PI
		g.add(d)
		var hg := T.Group.new()
		hg.position = Vector3(0, 3.62, s * 0.087)
		hg.rotation.y = 0.0 if s > 0 else PI
		var hm = mat.toon("#3a3346")
		var hour := T.MeshObj.new(Geo.box(0.024, 0.16, 0.006).translate(0, 0.06, 0), hm)
		var mn := T.MeshObj.new(Geo.box(0.016, 0.25, 0.006).translate(0, 0.1, 0.004), hm)
		var cap := T.MeshObj.new(Geo.cylinder(0.018, 0.018, 0.012, 10).rotate_x(PI / 2.0), hm)
		cap.position.z = 0.008
		hg.add(hour, mn, cap)
		hg.user_data = {"hour": hour, "min": mn}
		hand_groups.append(hg)
	var dyn := T.Group.new()
	dyn.position = g.position
	dyn.rotation.y = o.rotY
	for hg in hand_groups:
		dyn.add(hg)
	ctx.add(dyn)
	var mins := 2.0
	var a := fmod(16.0 + mins / 60.0, 12.0) / 12.0 * TAU
	var b := fmod(mins, 60.0) / 60.0 * TAU
	for hg in hand_groups:
		hg.user_data.hour.rotation.z = -a
		hg.user_data.min.rotation.z = -b
	_face(ctx, g, 0.3, 0.075, S.clockPlate, [0, 1.45, 0.082])
	ctx.physics.addBox(o.x, o.z, 0.46, 0.46, o.rotY, 0, 4.0)


## The station's 90th-anniversary monument stone: a low, wide natural stone (about 1 m), since it
## stands in the hero view's sightline to the level crossing.
static func _monument(ctx, root, TX: Dictionary, S: Dictionary, P: Dictionary) -> void:
	var mat = ctx.mat
	var o: Dictionary = P.monument
	var g = _group(root, o.x, o.z, o.rotY)
	var k = ctx.kit(g)
	k.box(1.76, 0.14, 0.66, mat.toon("#ffffff", {"map": TX.granite, "paint": 0.05}), [0, 0.07, 0])
	var sil := [[-0.7, 0.0], [0.74, 0.0], [0.8, 0.2], [0.76, 0.46], [0.62, 0.68], [0.34, 0.8], [-0.06, 0.82], [-0.42, 0.76], [-0.66, 0.58], [-0.78, 0.3]]
	var stone_m = mat.toon("#a9a598", {"paint": 0.12})
	stone_m.user_data["plazaKeep"] = true
	# smooth outline (a spline through the silhouette) with a rounded 4-step bevel
	var ring := sil.duplicate()
	ring.append(sil[0])
	var sg := Geo.extrude_shape(Geo.shape(Geo.spline_points(ring, 64)), {"depth": 0.24, "bevelEnabled": true, "bevelThickness": 0.06, "bevelSize": 0.05, "bevelSegments": 4, "curveSegments": 64})
	sg.translate(0, 0, -0.12)
	U.put(g, sg, stone_m, [0, 0.14, 0])
	_face(ctx, g, 0.86, 0.296, S.monument, [0.0, 0.14 + 0.42, 0.186])
	k.box(0.9, 0.336, 0.02, mat.toon("#3f3d46"), [0, 0.14 + 0.42, 0.176])
	_face(ctx, g, 0.36, 0.126, S.monumentPlate, [0, 0.07, 0.334])
	ctx.physics.addBox(o.x, o.z, 1.8, 0.7, o.rotY, 0, 1.05)


## The drinking fountain.
static func _fountain(ctx, root, M: Dictionary, TX: Dictionary, P: Dictionary) -> void:
	var mat = ctx.mat
	var o: Dictionary = P.fountain
	var g = _group(root, o.x, o.z, o.rotY)
	var k = ctx.kit(g)
	var gr = mat.toon("#ffffff", {"map": TX.granite, "paint": 0.05})
	k.boxb(0.5, 0.05, 0.5, gr, [0, 0, 0])
	k.rbox(0.3, 0.72, 0.3, 0.03, gr, [0, 0.41, 0])
	k.cyl(0.21, 0.16, 0.1, gr, [0, 0.8, 0], null, 18)
	k.cyl(0.17, 0.17, 0.012, mat.toon("#8fa3ad"), [0, 0.846, 0], null, 18)
	k.cyl(0.018, 0.018, 0.1, M.steel, [0, 0.9, 0.06], null, 8)
	k.box(0.05, 0.03, 0.05, M.steel, [0, 0.95, 0.06])
	k.box(0.06, 0.05, 0.03, M.steelD, [0, 0.62, 0.16])
	k.boxb(0.2, 0.14, 0.03, gr, [0, 0.05, 0.3])
	ctx.physics.addBox(o.x, o.z, 0.5, 0.5, o.rotY, 0, 1.0)


## Round concrete planters (their shrubs and pansies are plants.gd's).
static func _planters(ctx, root, M: Dictionary, TX: Dictionary, P: Dictionary) -> void:
	for pp in P.planters:
		var g = _group(root, pp[0], pp[1], 0.0)
		var k = ctx.kit(g)
		k.cyl(0.46, 0.38, 0.46, M.concrete, [0, 0.23, 0], null, 22)
		k.cyl(0.48, 0.48, 0.05, ctx.mat.toon("#cfcbc0", {"map": TX.concrete}), [0, 0.47, 0], null, 22)
		k.cyl(0.42, 0.42, 0.02, ctx.mat.toon("#ffffff", {"map": TX.soil}), [0, 0.45, 0], null, 18)
		ctx.physics.addCylinder(pp[0], pp[1], 0.5, 0, 0.9)


## The park bench between the planters, facing the tree.
static func _park_bench(ctx, root, M: Dictionary, P: Dictionary, out: Dictionary) -> void:
	var o: Dictionary = P.parkBench
	var x: float = o.x
	var z: float = o.z
	var rot_y: float = o.rotY
	var blen: float = o.len
	var g = _group(root, x, z, rot_y)
	var k = ctx.kit(g)
	var fr = ctx.mat.toon("#56615e", {"paint": 0.03})
	var seat_y := 0.44
	for s in [-1.0, 1.0]:
		var lx: float = s * (blen / 2.0 - 0.2)
		k.box(0.05, seat_y - 0.03, 0.05, fr, [lx, (seat_y - 0.03) / 2.0, 0.15])
		k.box(0.05, 0.84, 0.05, fr, [lx, 0.42, -0.2], [-0.12, 0, 0])
		k.box(0.05, 0.035, 0.46, fr, [lx, seat_y - 0.05, -0.02])
		k.box(0.05, 0.03, 0.42, fr, [lx, 0.62, 0.0])
		k.box(0.05, 0.2, 0.04, fr, [lx, 0.52, 0.18])
	for i in 4:
		k.box(blen, 0.03, 0.085, M.woodL, [0, seat_y - 0.015, 0.16 - i * 0.1])
	for i in 2:
		k.box(blen, 0.08, 0.025, M.woodL, [0, 0.6 + i * 0.13, -0.235 - i * 0.016], [-0.12, 0, 0])
	out.benches.append({"x": x, "z": z, "y": seat_y, "rotY": rot_y, "len": snappedf(blen - 0.5, 0.01)})
	ctx.physics.addBox(x, z, 0.5, blen, 0, 0, 0.8)


## The low station-name board in the tulip bed.
static func _name_sign(ctx, root, P: Dictionary) -> void:
	var mat = ctx.mat
	var o: Dictionary = P.nameSign
	var g = _group(root, o.x, o.z, o.rotY)
	var k = ctx.kit(g)
	var post = mat.toon("#4a5667", {"paint": 0.04})
	var tex = ctx.tex.draw(512, 160, null, {"key": "plaza-name-sign"})
	for s in [-1.0, 1.0]:
		k.boxb(0.07, 1.0, 0.07, post, [s * 0.62, 0.2, 0])
	k.rbox(1.5, 0.5, 0.07, 0.02, post, [0, 0.8, 0])
	_face(ctx, g, 1.44, 0.45, tex, [0, 0.8, 0.037])
	k.box(1.44, 0.45, 0.01, mat.toon("#e6e1d4"), [0, 0.8, -0.036])
	ctx.physics.addBox(o.x, o.z, 1.55, 0.2, o.rotY, 0, 1.1)


## Small lived-in details: a broom, dustpan and bucket at the bike-roof post, a watering can by the
## north-west bed, and mascot stickers on the phone booth and the bus-stop pole.
static func _details(ctx, root, M: Dictionary, P: Dictionary) -> void:
	var mat = ctx.mat
	var row: Dictionary = ctx.L.PLAZA.bikeRows[1]
	var px: float = row.x0 - 0.45
	var pz: float = row.z - 1.3
	var g = _group(root, px - 0.02, pz + 0.16, 0.0)
	var k = ctx.kit(g)
	var br := T.Group.new()
	br.position = Vector3(-0.08, 0, 0)
	br.rotation = Vector3(0.0, 0.3, -0.2)
	g.add(br)
	var bk = ctx.kit(br)
	bk.cyl(0.013, 0.013, 1.2, mat.toon("#c9a26e"), [0, 0.68, 0], null, 6)
	bk.box(0.26, 0.2, 0.06, mat.toon("#b9954f", {"paint": 0.08}), [0, 0.1, 0])
	bk.box(0.2, 0.04, 0.07, mat.toon("#d9463b"), [0, 0.2, 0])
	var dp := T.Group.new()
	dp.position = Vector3(0.16, 0, 0.06)
	dp.rotation = Vector3(-0.25, -0.4, 0)
	g.add(dp)
	ctx.kit(dp).box(0.24, 0.012, 0.2, mat.toon("#5f86c8"), [0, 0.12, 0.08], [1.25, 0, 0])
	ctx.kit(dp).cyl(0.011, 0.011, 0.72, mat.toon("#5f86c8"), [0, 0.46, 0.0], null, 6)
	k.cyl(0.13, 0.11, 0.26, mat.toon("#6fa7c9", {"paint": 0.03}), [0.34, 0.13, 0.12], null, 14)
	k.cyl(0.118, 0.118, 0.012, mat.toon("#4f7fa0"), [0.34, 0.255, 0.12], null, 14)
	var hd := T.MeshObj.new(Geo.torus(0.12, 0.006, 4, 12, PI), M.steelD)
	hd.position = Vector3(0.34, 0.26, 0.12)
	hd.rotation = Vector3(-0.5, 0.2, 0)
	g.add(hd)
	ctx.physics.addBox(px + 0.1, pz + 0.3, 0.7, 0.4, 0, 0, 0.6)
	# green watering can next to the north-west flower bed
	var wg = _group(root, -4.5, -22.25, 0.9)
	var wk = ctx.kit(wg)
	var gc = mat.toon("#7fb07a", {"paint": 0.04})
	wk.rbox(0.28, 0.2, 0.14, 0.05, gc, [0, 0.11, 0])
	wk.cyl(0.012, 0.022, 0.32, gc, [0.2, 0.2, 0], [0, 0, -0.95], 6)
	wk.cyl(0.03, 0.02, 0.03, gc, [0.33, 0.29, 0], [0, 0, -0.95], 8)
	var h := T.MeshObj.new(Geo.torus(0.1, 0.012, 5, 10, PI), gc)
	h.position = Vector3(-0.03, 0.21, 0)
	wg.add(h)
	# mascot stickers on the phone booth and the bus-stop pole
	var stk = ctx.tex.draw(128, 128, null, {"key": "plaza-sticker"})
	var sm = mat.decal("#ffffff", {"map": stk, "alphaTest": 0.5, "transparent": false, "depthWrite": true})
	var ph: Dictionary = P.phone
	var pg = _group(root, ph.x, ph.z, ph.rotY)
	var s1 := T.MeshObj.new(Geo.g_plane(ctx.cache), sm)
	s1.scale = Vector3(0.09, 0.09, 1)
	s1.position = Vector3(0.3, 0.62, 0.434)
	pg.add(s1)
	var bs: Dictionary = ctx.L.PLAZA.busStop
	var bg = _group(root, bs.x, bs.z, 0.0)
	var s2 := T.MeshObj.new(Geo.g_plane(ctx.cache), sm)
	s2.scale = Vector3(0.06, 0.06, 1)
	s2.position = Vector3(0, 0.95, 0.033)
	bg.add(s2)
	ctx.no_outline(s1)
	ctx.no_outline(s2)
