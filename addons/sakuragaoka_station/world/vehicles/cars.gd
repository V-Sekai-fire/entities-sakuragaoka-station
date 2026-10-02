# vehicles/cars.js: parked cars (the white kei van, the pastel two-tone kei, the retro taxi) and a
# small compact waiting at the crossing (driver and lit brake lamps). Car-local frame: forward +Z,
# origin on the ground midway between the axles, +X is the car's left (right-hand drive, so the
# driver sits at -X). Each car is one vertex-colour mesh, one atlas mesh, one glass mesh and maybe
# a small lit mesh.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const VBS = preload("res://addons/sakuragaoka_station/world/vehicles/vb.gd")
const Atlas = preload("res://addons/sakuragaoka_station/world/vehicles/atlas.gd")

const TYRE := "#4a4552"
const DARK := "#3f3d47"
const TRIM := "#56545e"
const CHROME := "#d2d6da"
const REDL := "#d9534f"
const AMBER := "#efb04a"
const LAMP := "#eef0e5"


static func _plane() -> T.Geometry:
	return VBS.cg("plane", func(): return Geo.plane(1, 1))


## Sutherland-Hodgman clip of a (z, y) polygon to y in [y0, y1].
static func clip_y(pts: Array, y0: float, y1: float) -> Array:
	var clip := func(P: Array, inside: Callable, inter: Callable) -> Array:
		var out := []
		for i in P.size():
			var a = P[i]
			var b = P[(i + 1) % P.size()]
			var ia: bool = inside.call(a)
			var ib: bool = inside.call(b)
			if ia:
				out.append(a)
			if ia != ib:
				out.append(inter.call(a, b))
		return out
	var at := func(a, b, y: float) -> Array:
		var t: float = (y - a[1]) / (b[1] - a[1])
		return [a[0] + (b[0] - a[0]) * t, y]
	var P: Array = clip.call(pts, func(p): return p[1] >= y0 - 1e-6, func(a, b): return at.call(a, b, y0))
	P = clip.call(P, func(p): return p[1] <= y1 + 1e-6, func(a, b): return at.call(a, b, y1))
	return P


## The full side profile: `top` from front-bottom over the car to rear-bottom, then the bottom with
## the wheel arches.
static func profile(top: Array, s: Dictionary) -> Array:
	var pts := top.duplicate()
	var Ra: float = s.Ra + (0.0 if s.get("inset", false) else s.bev * 0.8)
	var arch := func(zA: float) -> Array:
		var al := asin(maxf(-1.0, minf(1.0, (s.yb - s.R) / Ra)))
		var out := []
		var n := 12
		for i in n + 1:
			var t := (PI - al) + (2.0 * al - PI) * i / n
			out.append([zA + Ra * cos(t), s.R + Ra * sin(t)])
		return out
	pts.append_array(arch.call(-s.wb / 2.0))
	pts.append_array(arch.call(s.wb / 2.0))
	return pts


static func extrude_side(pts: Array, W: float, bev: float, taper, inset: bool = false) -> T.Geometry:
	var depth := W - 2.0 * bev
	var g := Geo.extrude_shape(Geo.shape(pts), {"depth": depth, "bevelEnabled": true, "bevelThickness": bev,
		"bevelSize": bev * 0.8, "bevelOffset": -bev * 0.8 if inset else 0.0, "bevelSegments": 3 if inset else 2,
		"curveSegments": 4})
	g.apply_matrix4(Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3.ZERO))
	g.translate(depth / 2.0, 0, 0)
	if taper != null:
		var p: T.Attr = g.get_attribute("position")
		for i in p.count():
			var z := p.get_z(i)
			var tf := maxf(0.0, (z - taper.zF0) / (taper.zF1 - taper.zF0))
			var tr := maxf(0.0, (taper.zR0 - z) / (taper.zR0 - taper.zR1))
			var k: float = 1.0 - taper.kF * tf * tf - taper.kR * tr * tr
			if taper.get("kS", 0.0):
				var ts := maxf(0.0, minf(1.0, (p.get_y(i) - taper.yS) / (taper.yT - taper.yS)))
				k *= 1.0 - taper.kS * ts * ts
			p.set_x(i, p.get_x(i) * k)
		g.compute_vertex_normals()
	return g


## The body tint: dark wheel-arch tunnels and underside, dusty sills.
static func body_tint(s: Dictionary, dirt: String = "#a39a90", amt: float = 0.32) -> Callable:
	var dk := VBS.C("#46434d")
	var dc := VBS.C(dirt)
	return func(p: Vector3, c: Color, n: Vector3) -> Color:
		if n.y < -0.7:
			return dk
		for za in [-s.wb / 2.0, s.wb / 2.0]:
			var d := Vector2(p.z - za, p.y - s.R).length()
			if absf(n.x) < 0.8 and d < s.Ra + s.bev + 0.02 and p.y > s.yb - 0.01:
				return dk
		if p.y < s.sill:
			return c.lerp(dc, amt * minf(1.0, (s.sill - p.y) / maxf(0.05, s.sill - s.yb)))
		return c


static func wheels(V, D, s: Dictionary) -> void:
	for z in [-s.wb / 2.0, s.wb / 2.0]:
		for side in [-1.0, 1.0]:
			var x: float = side * s.track / 2.0
			V.cyl(s.R, s.R, s.tw, TYRE, [x, s.R, z], [0, 0, PI / 2.0], 20)
			V.cyl(s.R * 0.8, s.R * 0.8, s.tw + 0.004, "#3f3c46", [x, s.R, z], [0, 0, PI / 2.0], 14)
			D.add(VBS.cg("circ18", func(): return Geo.circle(1, 18)), "#ffffff",
				VBS.mtx([x + side * (s.tw / 2.0 + 0.006), s.R, z], [0, side * PI / 2.0, 0], [s.R * s.capK, s.R * s.capK, 1]),
				null, Atlas.uv_into(Atlas.R[s.cap]))


## A number plate (frame and atlas plane) on a face whose outward direction is rot_y (0 is +Z).
static func plate(V, D, reg: Array, x: float, y: float, z: float, rot_y: float) -> void:
	var nx := sin(rot_y)
	var nz := cos(rot_y)
	V.box(0.35, 0.185, 0.012, TRIM, [x, y, z], [0, rot_y, 0])
	D.add(_plane(), "#ffffff", VBS.mtx([x + nx * 0.0075, y, z + nz * 0.0075], [0, rot_y, 0], [0.33, 0.165, 1]), null, Atlas.uv_into(reg))


## A decal plane on the side (+1 is the +X side).
static func side_decal(D, reg: Array, side: float, x: float, y: float, z: float, w: float, h: float) -> void:
	D.add(_plane(), "#ffffff", VBS.mtx([side * x, y, z], [0, side * PI / 2.0, 0], [w, h, 1]), null, Atlas.uv_into(reg))


static func door_mirror(V, x: float, y: float, z: float, side: float, col: String) -> void:
	V.rod([side * x, y, z], [side * (x + 0.09), y + 0.03, z - 0.02], 0.012, DARK, 5)
	V.rbox(0.07, 0.10, 0.15, 0.025, col, [side * (x + 0.13), y + 0.05, z - 0.03], [0, side * 0.2, 0], 1)
	V.box(0.05, 0.075, 0.004, "#a9b8c6", [side * (x + 0.13), y + 0.05, z - 0.107], [0, side * 0.2, 0])


static func seat(V, x: float, z: float, w: float, col: String, yb: float, back: float = 0.58) -> void:
	V.rbox(w, 0.13, 0.46, 0.045, col, [x, yb + 0.065, z], null, 1)
	V.rbox(w, back, 0.12, 0.045, col, [x, yb + 0.1 + back / 2.0, z - 0.26], [-0.18, 0, 0], 1)
	V.rbox(w * 0.55, 0.15, 0.1, 0.035, col, [x, yb + 0.12 + back + 0.07, z - 0.30 - back * 0.18], [-0.18, 0, 0], 1)


static func door_line(V, W: float, z: float, y0: float, y1: float) -> void:
	for s in [-1.0, 1.0]:
		V.box(0.004, y1 - y0, 0.008, "#57545e", [s * (W / 2.0 + 0.002), (y0 + y1) / 2.0, z])


static func wipers(V, pts: Array) -> void:
	for ab in pts:
		V.bar(ab[0], ab[1], 0.018, 0.012, "#403e48")


static func finish(ctx, V, D, G, E, name: String, M: Dictionary):
	var g := T.Group.new()
	g.name = name
	var inner := T.Group.new()
	g.add(inner)
	g.user_data["inner"] = inner
	var add := func(vb, mat, opts: Dictionary = {}):
		var geo = vb.build() if vb != null else null
		if geo == null:
			return null
		var m := T.MeshObj.new(geo, mat)
		m.cast_shadow = opts.get("cast", true)
		m.receive_shadow = opts.get("recv", true)
		if opts.get("noOutline", false):
			ctx.no_outline(m)
		if opts.get("order", 0):
			m.render_order = opts.order
		inner.add(m)
		return m
	add.call(V, M.vcol)
	add.call(D, M.atlas, {"noOutline": true})
	add.call(G, M.glass, {"noOutline": true, "cast": false, "recv": false, "order": 1})
	if E != null:
		for e in E:
			add.call(e[0], e[1], {"noOutline": true, "cast": false})
	return g


## The white kei van.
static func make_kei_van(ctx):
	var M: Dictionary = Atlas.get_mats(ctx)
	var s := {"W": 1.475, "wb": 2.43, "R": 0.285, "tw": 0.15, "track": 1.23, "yb": 0.24, "Ra": 0.34, "sill": 0.46, "bev": 0.035, "cap": "capSteel", "capK": 0.68}
	var BODY := "#e8e8e3"
	var RES := "#8e9199"
	var V = VBS.VB.new()
	var D = VBS.VB.new()
	var G = VBS.VB.new()
	var top := [[1.70, 0.24], [1.735, 0.30], [1.735, 0.56], [1.705, 0.63], [1.665, 0.93], [1.55, 1.0], [1.36, 1.035], [1.30, 1.04], [-1.63, 1.04], [-1.665, 1.0], [-1.665, 0.30], [-1.63, 0.24]]
	V.add(extrude_side(profile(top, s), s.W, s.bev, {"zF0": 1.35, "zF1": 1.76, "kF": 0.05, "zR0": -1.45, "zR1": -1.69, "kR": 0.03}), BODY, null, body_tint(s))
	wheels(V, D, s)
	var gx := 0.716
	for sd in [-1.0, 1.0]:
		V.bar([sd * gx, 1.04, 1.30], [sd * gx, 1.84, 0.915], 0.055, 0.055, BODY)
		V.box(0.05, 0.80, 0.07, DARK, [sd * 0.717, 1.44, 0.32])
		V.box(0.05, 0.80, 0.09, BODY, [sd * 0.717, 1.44, -0.66])
		V.box(0.06, 0.80, 0.10, BODY, [sd * 0.712, 1.44, -1.615])
		G.add(VBS.poly([[1.30, 1.045], [0.915, 1.83], [-1.615, 1.83], [-1.615, 1.045]]), "#fff", VBS.mtx([sd * (gx + 0.001), 0, 0], [0, -PI / 2.0, 0]))
	V.rbox(1.45, 0.075, 2.64, 0.03, BODY, [0, 1.855, -0.345], null, 1)
	G.add(VBS.quad([-0.69, 1.045, 1.30], [0.69, 1.045, 1.30], [0.69, 1.83, 0.915], [-0.69, 1.83, 0.915]), "#fff")
	G.add(VBS.quad([0.69, 1.07, -1.668], [-0.69, 1.07, -1.668], [-0.69, 1.80, -1.668], [0.69, 1.80, -1.668]), "#fff")
	V.box(1.42, 0.05, 0.06, BODY, [0, 1.055, -1.64])
	wipers(V, [[[-0.62, 1.06, 1.297], [-0.06, 1.10, 1.285]], [[0.08, 1.06, 1.297], [0.62, 1.10, 1.285]]])
	for z in [0.55, -1.30]:
		V.rbox(1.38, 0.035, 0.04, 0.012, DARK, [0, 1.93, z], null, 1)
		for sd in [-1.0, 1.0]:
			V.box(0.04, 0.05, 0.05, DARK, [sd * 0.66, 1.905, z])
	for x in [-0.2, 0.2]:
		V.box(0.045, 0.03, 2.3, "#c9ced3", [x, 1.965, -0.37])
	var z := -1.42
	while z <= 0.72:
		V.box(0.40, 0.022, 0.03, "#c9ced3", [0, 1.962, z])
		z += 0.285
	for sd in [-1.0, 1.0]:
		V.rbox(0.26, 0.14, 0.05, 0.02, LAMP, [sd * 0.49, 0.77, 1.712], [-0.14, 0, 0], 1)
		V.rbox(0.10, 0.06, 0.04, 0.015, AMBER, [sd * 0.58, 0.655, 1.738], null, 1)
		door_mirror(V, 0.74, 1.08, 1.20, sd, DARK)
	D.add(_plane(), "#ffffff", VBS.mtx([0, 0.79, 1.718], [-0.14, 0, 0], [0.56, 0.13, 1]), null, Atlas.uv_into(Atlas.R.vanGrille))
	V.rbox(1.50, 0.22, 0.16, 0.06, RES, [0, 0.43, 1.73], null, 1)
	plate(V, D, Atlas.R.plVan, 0, 0.45, 1.816, 0)
	V.rbox(1.50, 0.2, 0.14, 0.05, RES, [0, 0.40, -1.67], null, 1)
	for sd in [-1.0, 1.0]:
		V.rbox(0.10, 0.24, 0.05, 0.02, REDL, [sd * 0.64, 0.86, -1.69], null, 1)
		V.rbox(0.10, 0.10, 0.05, 0.02, AMBER, [sd * 0.64, 0.67, -1.69], null, 1)
	plate(V, D, Atlas.R.plVan, 0, 0.66, -1.699, PI)
	D.add(_plane(), "#ffffff", VBS.mtx([0, 0.92, -1.702], [0, PI, 0], [0.60, 0.15, 1]), null, Atlas.uv_into(Atlas.R.vanRear))
	V.box(0.12, 0.03, 0.02, TRIM, [0, 0.80, -1.70])
	door_line(V, s.W, 0.32, 0.30, 1.04)
	door_line(V, s.W, 1.28, 0.66, 1.04)
	door_line(V, s.W, -0.64, 0.30, 1.04)
	for sd in [-1.0, 1.0]:
		V.box(0.004, 0.012, 0.94, "#57545e", [sd * (s.W / 2.0 + 0.002), 1.0, -1.11])
		V.box(0.014, 0.035, 0.11, TRIM, [sd * (s.W / 2.0 + 0.006), 0.92, 0.42])
		V.box(0.014, 0.035, 0.11, TRIM, [sd * (s.W / 2.0 + 0.006), 0.90, 0.18])
		V.box(0.004, 0.13, 0.13, "#d9d9d3", [sd * (s.W / 2.0 + 0.002), 0.86, -1.35])
		side_decal(D, Atlas.R.vanSide, sd, s.W / 2.0 + 0.005, 0.83, -0.50, 1.30, 0.325)
	for sd in [-1.0, 1.0]:
		seat(V, sd * 0.32, 0.64, 0.46, "#6f6c78", 0.66, 0.6)
	V.rbox(1.38, 0.16, 0.34, 0.04, "#5a5763", [0, 1.0, 1.16], null, 1)
	V.torus(0.17, 0.017, DARK, [-0.34, 1.15, 0.94], [-0.95, 0, 0], 5, 18)
	V.rbox(0.45, 0.34, 0.40, 0.02, "#c9a77a", [0.30, 0.80, -1.12], null, 1)
	V.rbox(0.40, 0.30, 0.36, 0.02, "#d4b588", [0.28, 1.12, -1.10], [0, 0.12, 0], 1)
	V.rbox(0.36, 0.28, 0.34, 0.02, "#c9a77a", [0.30, 0.78, -0.62], null, 1)
	for i in 3:
		V.cyl(0.03, 0.03, 1.9, "#b9bfc4", [-0.28 + i * 0.065, 1.13 + (i % 2) * 0.02, -0.62], [PI / 2.0, 0, 0], 8)
	var g = finish(ctx, V, D, G, null, "keiVan", M)
	g.user_data["dims"] = {"W": s.W, "zF": 1.81, "zR": -1.72, "H": 2.0, "wb": s.wb}
	return g


## The retro two-tone kei car.
static func make_kei_car(ctx, o: Dictionary = {}):
	var M: Dictionary = Atlas.get_mats(ctx)
	var s := {"W": 1.475, "wb": 2.46, "R": 0.28, "tw": 0.155, "track": 1.24, "yb": 0.20, "Ra": 0.33, "sill": 0.40, "bev": 0.065, "inset": true, "cap": "capCover", "capK": 0.7}
	var BODY: String = o.color if o.get("color") != null else "#9fd4c2"
	var ROOF := "#efe9dd"
	var V = VBS.VB.new()
	var D = VBS.VB.new()
	var G = VBS.VB.new()
	var top := [[1.70, 0.22], [1.73, 0.30], [1.73, 0.52], [1.715, 0.62], [1.67, 0.70], [1.58, 0.76], [1.40, 0.82], [1.15, 0.875], [1.08, 0.895], [-1.52, 0.925], [-1.60, 0.915], [-1.645, 0.86], [-1.665, 0.75], [-1.665, 0.32], [-1.64, 0.22]]
	V.add(extrude_side(profile(top, s), s.W, s.bev, {"zF0": 1.25, "zF1": 1.76, "kF": 0.09, "zR0": -1.35, "zR1": -1.69, "kR": 0.05, "yS": 0.76, "yT": 0.95, "kS": 0.035}, true), BODY, null, body_tint(s, "#a7a092", 0.25))
	wheels(V, D, s)
	var gx := 0.685
	for sd in [-1.0, 1.0]:
		V.bar([sd * gx, 0.90, 1.08], [sd * gx, 1.44, 0.45], 0.05, 0.05, ROOF)
		V.box(0.045, 0.53, 0.07, DARK, [sd * 0.687, 1.165, -0.12])
		V.box(0.05, 0.53, 0.30, ROOF, [sd * 0.688, 1.17, -1.43])
		V.box(0.004, 0.012, 2.5, CHROME, [sd * (s.W / 2.0 * 0.981 + 0.003), 0.90, -0.22])
		G.add(VBS.poly([[1.08, 0.905], [0.46, 1.43], [-1.285, 1.43], [-1.285, 0.915]]), "#fff", VBS.mtx([sd * (gx + 0.001), 0, 0], [0, -PI / 2.0, 0]))
	V.rbox(1.40, 0.09, 2.08, 0.045, ROOF, [0, 1.475, -0.54], null, 2)
	G.add(VBS.quad([-0.64, 0.905, 1.08], [0.64, 0.905, 1.08], [0.64, 1.43, 0.46], [-0.64, 1.43, 0.46]), "#fff")
	G.add(VBS.quad([0.62, 0.94, -1.628], [-0.62, 0.94, -1.628], [-0.62, 1.43, -1.55], [0.62, 1.43, -1.55]), "#fff")
	wipers(V, [[[-0.58, 0.915, 1.075], [-0.05, 0.955, 1.03]], [[0.06, 0.915, 1.075], [0.56, 0.955, 1.03]]])
	for sd in [-1.0, 1.0]:
		V.cyl(0.088, 0.088, 0.05, LAMP, [sd * 0.50, 0.66, 1.72], [PI / 2.0 - 0.35, 0, 0], 16)
		V.torus(0.09, 0.012, CHROME, [sd * 0.50, 0.6686, 1.7435], [-0.35, 0, 0], 4, 16)
		V.rbox(0.07, 0.04, 0.03, 0.01, AMBER, [sd * 0.62, 0.52, 1.76], null, 1)
		door_mirror(V, 0.72, 0.95, 0.98, sd, ROOF)
	V.rbox(0.36, 0.08, 0.03, 0.02, CHROME, [0, 0.60, 1.735], null, 1)
	D.add(_plane(), "#ffffff", VBS.mtx([0, 0.60, 1.753], null, [0.065, 0.065, 1]), null, Atlas.uv_into(Atlas.R.sakuraMark))
	V.rbox(1.50, 0.18, 0.14, 0.05, ROOF, [0, 0.40, 1.735], null, 1)
	plate(V, D, Atlas.R.plKei, 0, 0.42, 1.812, 0)
	V.rbox(1.50, 0.18, 0.13, 0.05, ROOF, [0, 0.40, -1.67], null, 1)
	for sd in [-1.0, 1.0]:
		V.rbox(0.12, 0.17, 0.05, 0.03, REDL, [sd * 0.60, 0.82, -1.69], null, 1)
		V.rbox(0.12, 0.055, 0.05, 0.02, AMBER, [sd * 0.60, 0.70, -1.69], null, 1)
	plate(V, D, Atlas.R.plKei, 0, 0.62, -1.672, PI)
	D.add(_plane(), "#ffffff", VBS.mtx([-0.42, 0.64, -1.672], [0, PI, 0], [0.15, 0.15, 1]), null, Atlas.uv_into(Atlas.R.beginner))
	V.box(0.14, 0.03, 0.02, CHROME, [0, 0.78, -1.673])
	door_line(V, s.W, 1.05, 0.62, 0.85)
	door_line(V, s.W, -0.12, 0.24, 0.85)
	door_line(V, s.W, -1.05, 0.62, 0.85)
	for sd in [-1.0, 1.0]:
		for z in [-0.02, -0.95]:
			V.box(0.014, 0.03, 0.10, CHROME, [sd * (s.W / 2.0 + 0.006), 0.83, z])
	for sd in [-1.0, 1.0]:
		seat(V, sd * 0.32, 0.25, 0.46, "#dccfb6", 0.50, 0.55)
	V.rbox(1.2, 0.12, 0.46, 0.04, "#dccfb6", [0, 0.56, -0.78], null, 1)
	V.rbox(1.2, 0.50, 0.12, 0.04, "#dccfb6", [0, 0.86, -1.03], [-0.15, 0, 0], 1)
	V.rbox(1.36, 0.14, 0.34, 0.04, "#e6dfcf", [0, 0.87, 0.90], null, 1)
	V.torus(0.17, 0.017, "#6d6977", [-0.34, 1.0, 0.64], [-0.5, 0, 0], 5, 18)
	V.box(1.28, 0.02, 0.28, "#5a5763", [0, 0.93, -1.40])
	V.sph(0.075, "#f2b9c9", [0.36, 1.02, -1.40], 8)
	V.sph(0.058, "#f2b9c9", [0.36, 1.12, -1.40], 8)
	for sd in [-1.0, 1.0]:
		V.sph(0.022, "#f2b9c9", [0.36 + sd * 0.04, 1.17, -1.40], 6)
	V.rbox(0.24, 0.08, 0.12, 0.02, "#f3c8d5", [-0.30, 0.98, -1.40], null, 1)
	var g = finish(ctx, V, D, G, null, "keiCar", M)
	g.user_data["dims"] = {"W": s.W, "zF": 1.81, "zR": -1.74, "H": 1.56, "wb": s.wb}
	return g


## The retro taxi.
static func make_taxi(ctx):
	var M: Dictionary = Atlas.get_mats(ctx)
	var s := {"W": 1.695, "wb": 2.68, "R": 0.30, "tw": 0.185, "track": 1.40, "yb": 0.22, "Ra": 0.355, "sill": 0.40, "bev": 0.03, "cap": "capTaxi", "capK": 0.72}
	var ROSE := "#c47a8f"
	var CREAM := "#f0e9da"
	var V = VBS.VB.new()
	var D = VBS.VB.new()
	var G = VBS.VB.new()
	var E = VBS.VB.new()
	var top := [[2.23, 0.24], [2.25, 0.30], [2.26, 0.62], [2.24, 0.78], [2.18, 0.84], [1.60, 0.875], [1.10, 0.905], [1.00, 0.915], [-1.38, 0.935], [-1.50, 0.945], [-2.30, 0.935], [-2.40, 0.905], [-2.43, 0.80], [-2.43, 0.34], [-2.40, 0.24]]
	var full := profile(top, s)
	var SPLIT := 0.70
	var TP := {"zF0": 1.7, "zF1": 2.29, "kF": 0.06, "zR0": -1.9, "zR1": -2.46, "kR": 0.05}
	V.add(extrude_side(clip_y(full, -1, SPLIT), s.W, s.bev, TP), ROSE, null, body_tint(s, "#a3928c", 0.28))
	V.add(extrude_side(clip_y(full, SPLIT, 9), s.W, s.bev, TP), CREAM, null, body_tint(s))
	wheels(V, D, s)
	var gx := 0.735
	var hw: float = s.W / 2.0
	for sd in [-1.0, 1.0]:
		V.bar([sd * gx, 0.92, 1.00], [sd * (gx - 0.005), 1.42, 0.30], 0.05, 0.05, CREAM)
		V.box(0.045, 0.49, 0.065, CREAM, [sd * (gx + 0.002), 1.175, -0.19])
		V.bar([sd * (gx - 0.005), 1.42, -0.80], [sd * gx, 0.94, -1.40], 0.05, 0.12, CREAM)
		V.box(0.012, 0.014, 2.40, CHROME, [sd * (gx + 0.012), 0.93, -0.20])
		V.rod([sd * (gx + 0.01), 1.414, 0.30], [sd * (gx + 0.01), 1.414, -0.80], 0.007, CHROME, 4)
		V.box(0.014, 0.026, 3.6, CHROME, [sd * (hw + 0.004), SPLIT, -0.10])
		G.add(VBS.poly([[1.00, 0.93], [0.30, 1.415], [-0.80, 1.415], [-1.40, 0.945]]), "#fff", VBS.mtx([sd * (gx + 0.001), 0, 0], [0, -PI / 2.0, 0]))
		side_decal(D, Atlas.R.taxiDoor, sd, hw + 0.005, 0.815, 0.36, 0.84, 0.21)
	V.rbox(1.46, 0.06, 1.17, 0.03, CREAM, [0, 1.445, -0.24], null, 1)
	G.add(VBS.quad([-0.70, 0.925, 1.00], [0.70, 0.925, 1.00], [0.69, 1.415, 0.30], [-0.69, 1.415, 0.30]), "#fff")
	G.add(VBS.quad([0.64, 0.95, -1.40], [-0.64, 0.95, -1.40], [-0.64, 1.415, -0.79], [0.64, 1.415, -0.79]), "#fff")
	wipers(V, [[[-0.64, 0.935, 0.99], [-0.08, 0.975, 0.93]], [[0.08, 0.935, 0.99], [0.62, 0.975, 0.93]]])
	V.box(0.30, 0.03, 0.12, DARK, [0, 1.49, 0.02])
	V.rbox(0.42, 0.15, 0.14, 0.03, "#f3ecdc", [0, 1.58, 0.02], null, 1)
	D.add(_plane(), "#ffffff", VBS.mtx([0, 1.58, 0.0925], null, [0.37, 0.13, 1]), null, Atlas.uv_into(Atlas.R.andon))
	D.add(_plane(), "#ffffff", VBS.mtx([0, 1.58, -0.0525], [0, PI, 0], [0.37, 0.13, 1]), null, Atlas.uv_into(Atlas.R.andon))
	V.box(0.19, 0.095, 0.03, DARK, [0.40, 1.03, 0.772], [-0.25, 0, 0])
	E.add(_plane(), "#ffffff", VBS.mtx([0.40, 1.03, 0.789], [-0.25, 0, 0], [0.17, 0.085, 1]), null, Atlas.uv_into(Atlas.R.kusha))
	V.rbox(1.74, 0.13, 0.16, 0.04, CHROME, [0, 0.42, 2.27], null, 1)
	for sd in [-1.0, 1.0]:
		V.box(0.10, 0.10, 0.03, DARK, [sd * 0.52, 0.42, 2.355])
	D.add(_plane(), "#ffffff", VBS.mtx([0, 0.665, 2.292], null, [0.78, 0.19, 1]), null, Atlas.uv_into(Atlas.R.grille))
	for sd in [-1.0, 1.0]:
		V.rbox(0.22, 0.12, 0.04, 0.015, LAMP, [sd * 0.60, 0.685, 2.285], null, 1)
		V.box(0.235, 0.135, 0.03, CHROME, [sd * 0.60, 0.685, 2.275])
		V.rbox(0.12, 0.05, 0.03, 0.01, AMBER, [sd * 0.60, 0.57, 2.292], null, 1)
		V.rod([sd * 0.66, 0.87, 1.78], [sd * 0.68, 1.0, 1.76], 0.008, DARK, 5)
		V.rbox(0.06, 0.075, 0.10, 0.02, DARK, [sd * 0.69, 1.03, 1.75], null, 1)
	plate(V, D, Atlas.R.plTaxi, 0, 0.42, 2.357, 0)
	V.rbox(1.74, 0.13, 0.16, 0.04, CHROME, [0, 0.42, -2.44], null, 1)
	for sd in [-1.0, 1.0]:
		V.rbox(0.34, 0.13, 0.04, 0.02, REDL, [sd * 0.58, 0.80, -2.452], null, 1)
		V.rbox(0.12, 0.13, 0.04, 0.02, AMBER, [sd * 0.33, 0.80, -2.452], null, 1)
	plate(V, D, Atlas.R.plTaxi, 0, 0.62, -2.46, PI)
	D.add(_plane(), "#ffffff", VBS.mtx([0, 0.80, -2.462], [0, PI, 0], [0.40, 0.10, 1]), null, Atlas.uv_into(Atlas.R.taxiRear))
	D.add(_plane(), "#ffffff", VBS.mtx([0.42, 1.03, -1.21], [-0.8, PI, 0], [0.12, 0.06, 1]), null, Atlas.uv_into(Atlas.R.kinen))
	V.box(1.5, 0.004, 0.006, "#57545e", [0, 0.972, -1.52])
	V.rod([-0.60, 0.97, -2.15], [-0.62, 1.75, -2.25], 0.004, DARK, 4)
	door_line(V, s.W, 0.97, 0.66, 0.93)
	door_line(V, s.W, -0.17, 0.24, 0.935)
	door_line(V, s.W, -1.28, 0.66, 0.94)
	for sd in [-1.0, 1.0]:
		for z in [-0.05, -1.16]:
			V.box(0.014, 0.03, 0.12, CHROME, [sd * (hw + 0.006), 0.84, z])
	var SEAT := "#6e6a78"
	var LACE := "#f1efea"
	for sd in [-1.0, 1.0]:
		seat(V, sd * 0.36, 0.20, 0.54, SEAT, 0.50, 0.55)
		V.rbox(0.56, 0.24, 0.14, 0.03, LACE, [sd * 0.36, 1.04, -0.12], [-0.18, 0, 0], 1)
		V.rbox(0.32, 0.17, 0.12, 0.03, LACE, [sd * 0.36, 1.24, -0.17], [-0.18, 0, 0], 1)
	V.rbox(1.3, 0.12, 0.48, 0.04, SEAT, [0, 0.56, -0.95], null, 1)
	V.rbox(1.3, 0.55, 0.13, 0.04, SEAT, [0, 0.88, -1.22], [-0.2, 0, 0], 1)
	V.rbox(1.32, 0.22, 0.15, 0.03, LACE, [0, 1.06, -1.26], [-0.2, 0, 0], 1)
	V.rbox(1.50, 0.14, 0.34, 0.04, "#57545f", [0, 0.90, 0.86], null, 1)
	V.box(0.16, 0.07, 0.10, DARK, [0.06, 1.0, 0.70])
	V.torus(0.18, 0.018, DARK, [-0.38, 1.02, 0.55], [-0.55, 0, 0], 5, 18)
	var g = finish(ctx, V, D, G, [[E, M.lit]], "taxi", M)
	g.user_data["dims"] = {"W": s.W, "zF": 2.36, "zR": -2.52, "H": 1.65, "wb": s.wb}
	return g


## The compact hatchback at the crossing (driver, brake lamps lit).
static func make_compact(ctx, o: Dictionary = {}):
	var M: Dictionary = Atlas.get_mats(ctx)
	var s := {"W": 1.695, "wb": 2.53, "R": 0.30, "tw": 0.185, "track": 1.45, "yb": 0.21, "Ra": 0.355, "sill": 0.40, "bev": 0.085, "inset": true, "cap": "capCompact", "capK": 0.7}
	var BODY: String = o.color if o.get("color") != null else "#8fb0d2"
	var V = VBS.VB.new()
	var D = VBS.VB.new()
	var G = VBS.VB.new()
	var E = VBS.VB.new()
	var top := [[2.03, 0.23], [2.065, 0.30], [2.08, 0.40], [2.075, 0.52], [2.05, 0.61], [2.0, 0.69], [1.92, 0.755], [1.78, 0.815], [1.58, 0.865], [1.42, 0.898], [1.32, 0.915], [-1.70, 1.00], [-1.80, 0.99], [-1.89, 0.93], [-1.925, 0.80], [-1.925, 0.35], [-1.89, 0.23]]
	V.add(extrude_side(profile(top, s), s.W, s.bev, {"zF0": 1.25, "zF1": 2.11, "kF": 0.17, "zR0": -1.40, "zR1": -1.96, "kR": 0.08, "yS": 0.80, "yT": 1.02, "kS": 0.06}, true), BODY, null, body_tint(s, "#a39c94", 0.3))
	wheels(V, D, s)
	var gx := 0.73
	var hw: float = s.W / 2.0
	for sd in [-1.0, 1.0]:
		V.bar([sd * gx, 0.92, 1.32], [sd * gx, 1.455, 0.22], 0.05, 0.05, BODY)
		V.box(0.045, 0.52, 0.07, DARK, [sd * (gx + 0.003), 1.19, -0.25])
		V.bar([sd * gx, 1.44, -1.36], [sd * gx, 1.0, -1.74], 0.05, 0.16, BODY)
		G.add(VBS.poly([[1.32, 0.93], [0.22, 1.455], [-1.45, 1.44], [-1.74, 1.005]]), "#fff", VBS.mtx([sd * (gx + 0.001), 0, 0], [0, -PI / 2.0, 0]))
		door_mirror(V, 0.735, 0.97, 1.12, sd, BODY)
	V.rbox(1.46, 0.07, 1.98, 0.035, BODY, [0, 1.49, -0.75], null, 2)
	G.add(VBS.quad([-0.70, 0.925, 1.32], [0.70, 0.925, 1.32], [0.70, 1.455, 0.22], [-0.70, 1.455, 0.22]), "#fff")
	G.add(VBS.quad([0.62, 1.01, -1.862], [-0.62, 1.01, -1.862], [-0.62, 1.45, -1.70], [0.62, 1.45, -1.70]), "#fff")
	wipers(V, [[[-0.62, 0.94, 1.31], [-0.06, 0.975, 1.255]], [[0.06, 0.94, 1.31], [0.60, 0.975, 1.255]]])
	for sd in [-1.0, 1.0]:
		V.rbox(0.34, 0.10, 0.20, 0.035, LAMP, [sd * 0.52, 0.70, 1.99], [-0.62, sd * 0.42, 0], 1)
		V.rbox(0.06, 0.03, 0.03, 0.01, AMBER, [sd * 0.64, 0.64, 2.035], [0, sd * 0.5, 0], 1)
	V.rbox(0.40, 0.05, 0.02, 0.008, DARK, [0, 0.62, 2.058], [-0.35, 0, 0], 1)
	D.add(_plane(), "#ffffff", VBS.mtx([0, 0.625, 2.071], [-0.35, 0, 0], [0.05, 0.05, 1]), null, Atlas.uv_into(Atlas.R.sakuraMark))
	V.rbox(1.5, 0.15, 0.10, 0.05, BODY, [0, 0.40, 2.06], null, 1)
	V.rbox(0.8, 0.06, 0.02, 0.01, DARK, [0, 0.33, 2.11], null, 1)
	plate(V, D, Atlas.R.plCar, 0, 0.44, 2.117, 0)
	for sd in [-1.0, 1.0]:
		V.rbox(0.24, 0.14, 0.05, 0.02, "#b8474a", [sd * 0.60, 0.92, -1.925], null, 1)
		E.rbox(0.20, 0.10, 0.02, 0.008, "#ffffff", [sd * 0.60, 0.925, -1.952], null, 1)
	E.box(0.30, 0.03, 0.02, "#ffffff", [0, 1.435, -1.712])
	plate(V, D, Atlas.R.plCar, 0, 0.62, -1.932, PI)
	V.box(0.12, 0.03, 0.02, CHROME, [0, 0.79, -1.93])
	door_line(V, s.W, 1.18, 0.68, 0.88)
	door_line(V, s.W, -0.24, 0.24, 0.88)
	door_line(V, s.W, -1.30, 0.68, 0.88)
	for sd in [-1.0, 1.0]:
		for z in [-0.12, -1.18]:
			V.box(0.014, 0.03, 0.10, BODY, [sd * (hw + 0.006), 0.86, z])
	for sd in [-1.0, 1.0]:
		seat(V, sd * 0.37, 0.05, 0.50, "#5f5c69", 0.46, 0.56)
	V.rbox(1.2, 0.12, 0.46, 0.04, "#5f5c69", [0, 0.53, -0.95], null, 1)
	V.rbox(1.2, 0.5, 0.12, 0.04, "#5f5c69", [0, 0.82, -1.2], [-0.15, 0, 0], 1)
	V.rbox(1.50, 0.14, 0.40, 0.04, "#4f4c58", [0, 0.93, 0.92], null, 1)
	var JK := "#58627f"
	var SKIN := "#f1d6c3"
	var HAIR := "#4a3c48"
	V.rbox(0.36, 0.46, 0.22, 0.08, JK, [-0.37, 0.98, -0.03], [-0.12, 0, 0], 1)
	V.sph(0.105, SKIN, [-0.37, 1.30, 0.02], 10)
	V.sph(0.113, HAIR, [-0.37, 1.325, -0.008], 10, [1, 0.94, 1.02])
	for sd in [-1.0, 1.0]:
		V.rod([-0.37 + sd * 0.15, 1.14, 0.0], [-0.37 + sd * 0.13, 1.02, 0.26], 0.045, JK, 6)
		V.rod([-0.37 + sd * 0.13, 1.02, 0.26], [-0.37 + sd * 0.14, 1.08, 0.43], 0.04, JK, 6)
		V.sph(0.035, SKIN, [-0.37 + sd * 0.14, 1.09, 0.46], 6)
	V.torus(0.18, 0.018, DARK, [-0.37, 1.06, 0.46], [-0.5, 0, 0], 5, 18)
	V.box(0.22, 0.06, 0.03, DARK, [0, 1.38, 0.30])
	V.rod([0, 1.35, 0.30], [0, 1.29, 0.30], 0.002, "#e5d9b8", 3)
	V.sph(0.022, "#f2b5c8", [0, 1.27, 0.30], 6)
	var g = finish(ctx, V, D, G, [[E, M.brake]], "compact", M)
	g.user_data["dims"] = {"W": s.W, "zF": 2.12, "zR": -1.98, "H": 1.55, "wb": s.wb}
	return g
