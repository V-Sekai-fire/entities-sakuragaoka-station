# station/props3d.js: modelled interior props (real geometry for every object; textures only for
# flat graphics). Each factory builds a Group at world (x, y, z) facing local +Z under A.root.
# Colliders are added for floor-standing furniture ({"col": false} skips them).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Foliage = preload("res://addons/sakuragaoka_station/world/lib/foliage.gd")
const Building = preload("res://addons/sakuragaoka_station/world/station/building.gd")
const Rng = preload("res://addons/sakuragaoka_station/core/rng.gd")

var A
var ctx
var M: Dictionary
var U
var P
var C: Dictionary
var PIN: Array
var FY: float
var CEIL: float
var _g := {}
var tact_parts := []
var book_cols := []


func _init(a) -> void:
	A = a
	ctx = a.ctx
	M = a.M
	U = a.U
	P = a.P
	FY = Building.B.FY
	CEIL = Building.B.CEIL
	var ic: Callable = M.ic
	C = {
		"white": ic.call("#ebe8e0"), "offWhite": ic.call("#ddd8cb"), "cream": ic.call("#efe5cf"), "paper": ic.call("#f1eee6", 0.01),
		"steel": ic.call("#bfc5ca", 0.02), "steelDk": ic.call("#7b828a", 0.02), "dark": ic.call("#4c4d57", 0.02), "ink": ic.call("#3a3346", 0.0), "black": ic.call("#403e49", 0.02),
		"red": ic.call("#cc4a42"), "redDk": ic.call("#a83a36"), "orange": ic.call("#e8914a"), "yellow": ic.call("#e8c24a"), "green": ic.call("#4f8f5f"), "greenDk": ic.call("#3e6b52"),
		"blue": ic.call("#3f6fb0"), "navy": ic.call("#2f4068"), "sky": ic.call("#9cc4ea"), "pink": ic.call("#ef9fbe"), "pinkDk": ic.call("#d9718f"),
		"wood": ic.call("#a67a52"), "woodDk": ic.call("#6e5140"), "woodLt": ic.call("#c9a57a"), "rubber": ic.call("#57555c", 0.03), "gold": ic.call("#d6b04a", 0.02),
		"grey": ic.call("#9aa0a6"), "greyLt": ic.call("#c9ccd0"), "beige": ic.call("#d9cdb4"), "tea": ic.call("#8a6a3a", 0.0), "soil": ic.call("#6e5a48", 0.06),
	}
	PIN = [C.red, C.blue, C.yellow, C.green, C.white, C.pink]
	for h in ["#c9504a", "#3f6fb0", "#e8c24a", "#4f8f5f", "#ef9fbe", "#8a6446", "#ebe8e0", "#6d747c", "#9cc4ea", "#d9718f", "#b48a62", "#2f4068"]:
		book_cols.append(ic.call(h))


func geo(key: String, make: Callable) -> T.Geometry:
	if not _g.has(key):
		_g[key] = make.call()
	return _g[key]


func grp(x: float, y: float, z: float, rot_y: float = 0.0, parent = null):
	var g := T.Group.new()
	g.position = Vector3(x, y, z)
	g.rotation.y = rot_y
	(parent if parent != null else A.root).add(g)
	return g


func K(g) -> PKit:
	return PKit.new(g, ctx.cache, self)


func lab(g, atlas: String, id, w: float, h: float, pos: Array, rot = null, lit = 0.85):
	var a = A.atlases[atlas]
	var m := T.MeshObj.new(U.rect_plane(w, h, a.r(id)), A.sign_mat(atlas, lit))
	m.position = Vector3(pos[0], pos[1], pos[2])
	if rot != null:
		m.rotation = Vector3(rot[0] if rot[0] != null else 0.0, rot[1] if rot.size() > 1 and rot[1] != null else 0.0, rot[2] if rot.size() > 2 and rot[2] != null else 0.0)
	m.receive_shadow = true
	m.cast_shadow = false
	g.add(m)
	return m


## a paper sheet whose lower edge / corner curls off the board
func sheet_geo(w: float, h: float, r: Dictionary, curl: float = 0.012, corner: float = 0.0) -> T.Geometry:
	var g := Geo.plane(w, h, 3, 6)
	var p := g.position()
	var uv: T.Attr = g.attributes.uv
	for i in p.count():
		var u := uv.get_x(i)
		var v := uv.get_y(i)
		var t := maxf(0.0, 0.42 - v) / 0.42
		var c := maxf(0.0, u - 0.55) / 0.45
		p.set_z(i, curl * t * t + corner * c * c * t)
		uv.set_xy(i, r.u0 + u * (r.u1 - r.u0), r.v0 + v * (r.v1 - r.v0))
	g.compute_vertex_normals()
	return g


func sheet(g, atlas: String, id, w: float, h: float, pos: Array, rot_z: float = 0.0, o: Dictionary = {}):
	var a = A.atlases[atlas]
	var m := T.MeshObj.new(sheet_geo(w, h, a.r(id), o.get("curl", 0.012), o.get("corner", 0.0)), A.sign_mat(atlas, o.get("lit", 0.82)))
	m.position = Vector3(pos[0], pos[1], pos[2])
	m.rotation = Vector3(o.get("rx", 0.0), o.get("ry", 0.0), rot_z)
	m.receive_shadow = true
	m.cast_shadow = false
	g.add(m)
	return m


func col(x: float, z: float, w: float, d: float, rot_y: float = 0.0, h: float = 2.2) -> void:
	P.addBox(x, z, w, d, rot_y, -1, FY + h)


## merges many small (geometry, transform) pieces into one static mesh
func merged(parts: Array, mat):
	if parts.is_empty():
		return null
	var gs := []
	for pr in parts:
		var c: T.Geometry = (pr[0] as T.Geometry).clone()
		c.apply_matrix4(pr[1])
		if c.indexed:
			c = c.to_non_indexed()
		for k in c.attributes.keys():
			if k != "position" and k != "normal" and k != "uv":
				c.delete_attribute(k)
		gs.append(c)
	var mesh := T.MeshObj.new(Geo.merge_geometries(gs, false), mat)
	mesh.cast_shadow = false
	mesh.receive_shadow = true
	return mesh


static func mtx(pos: Array, rot: Array = [0, 0, 0], scl: Array = [1, 1, 1]) -> Transform3D:
	return T.compose(Vector3(pos[0], pos[1], pos[2]), T.quat_from_euler(Vector3(rot[0], rot[1], rot[2])), Vector3(scl[0], scl[1], scl[2]))


# ================================================================ ceiling fittings

func fix_geo(len: float) -> T.Geometry:
	return geo("fix" + str(len), func():
		var g: T.Geometry = ctx.geo.extrude([[-0.11, 0.0], [0.11, 0.0], [0.045, -0.07], [-0.045, -0.07]], len)
		g.rotate_y(PI / 2.0)
		return g)


## surface fluorescent fixture (length along local x)
func fixture(x: float, z: float, o: Dictionary = {}):
	var len: float = o.get("len", 1.25)
	var y: float = o.get("y", CEIL)
	var g = grp(x, y, z, o.get("rot", 0.0))
	var kk := K(g)
	kk.mesh(fix_geo(len), M.fixtureBody, [0, 0, 0])
	for s in [-1, 1]:
		kk.box(0.03, 0.075, 0.09, M.fixtureBody, [s * (len / 2.0 - 0.02), -0.105, 0])
	var n: int = o.get("tubes", 1)
	for i in n:
		var t = kk.cx(0.0145, len - 0.1, o.get("tube", M.tubeLit), [0, -0.108, 0.0 if n == 1 else (i - 0.5) * 0.075], 10)
		t.cast_shadow = false
	return g


## soft pool of light on the floor
func pool(x: float, z: float, rx: float, rz: float, o: Dictionary = {}):
	var m := T.MeshObj.new(Geo.g_plane(ctx.cache), o.get("mat", M.pool))
	m.position = Vector3(x, o.get("y", FY + 0.019), z)
	m.rotation = Vector3(-PI / 2.0, 0, o.get("rot", 0.0))
	m.scale = Vector3(rx * 2.0, rz * 2.0, 1)
	m.render_order = 3
	A.root.add(m)
	ctx.no_outline(m)
	return m


## wall glow (vertical pool) facing local +z
func wall_glow(x: float, y: float, z: float, rot_y: float, rx: float, ry: float):
	var m := T.MeshObj.new(Geo.g_plane(ctx.cache), M.poolWall)
	m.position = Vector3(x, y, z)
	m.rotation.y = rot_y
	m.scale = Vector3(rx * 2.0, ry * 2.0, 1)
	m.render_order = 3
	A.root.add(m)
	ctx.no_outline(m)
	return m


## 4-way ceiling cassette air conditioner
func cassette(x: float, z: float, rot: float = 0.0):
	var g = grp(x, CEIL, z, rot)
	var kk := K(g)
	kk.rb(0.9, 0.035, 0.9, 0.012, C.white, [0, -0.0175, 0])
	for i in 4:
		var a := i * PI / 2.0
		var sg := T.Group.new()
		sg.position = Vector3(sin(a) * 0.345, 0, cos(a) * 0.345)
		sg.rotation.y = a
		g.add(sg)
		var sk := K(sg)
		sk.box(0.6, 0.006, 0.075, C.dark, [0, -0.037, 0])
		sk.box(0.58, 0.006, 0.062, C.offWhite, [0, -0.044, 0.004], [0.35, 0, 0])
	kk.box(0.52, 0.006, 0.52, C.offWhite, [0, -0.038, 0])
	for i in range(-3, 4):
		kk.box(0.5, 0.004, 0.008, C.greyLt, [0, -0.042, i * 0.07])
	kk.box(0.1, 0.008, 0.04, M.ledGreen, [0.3, -0.037, 0.3]).cast_shadow = false
	return g


func smoke_detector(x: float, z: float):
	var g = grp(x, CEIL, z)
	var kk := K(g)
	kk.cy(0.06, 0.028, C.white, [0, -0.014, 0], 14)
	kk.cy(0.038, 0.016, C.offWhite, [0, -0.034, 0], 12)
	kk.box(0.012, 0.006, 0.012, M.ledRed, [0.03, -0.029, 0])
	return g


func ceil_speaker(x: float, z: float):
	var g = grp(x, CEIL, z)
	var kk := K(g)
	kk.cy(0.13, 0.02, C.white, [0, -0.01, 0], 18)
	kk.cy(0.105, 0.006, C.grey, [0, -0.022, 0], 18)
	for r in [0.08, 0.055, 0.03]:
		kk.cy(r, 0.004, C.steelDk, [0, -0.026, 0], 16)
	return g


func cctv_dome(x: float, z: float):
	var g = grp(x, CEIL, z)
	var kk := K(g)
	kk.cy(0.09, 0.035, C.white, [0, -0.0175, 0], 16)
	kk.mesh(geo("dome", func(): return Geo.sphere(0.07, 14, 7, 0, TAU, PI / 2.0, PI / 2.0)), M.smoked, [0, -0.035, 0])
	kk.cy(0.074, 0.012, C.offWhite, [0, -0.038, 0], 16)
	return g


## lit green exit sign on a wall face (local +z out of the wall)
func exit_sign(x: float, y: float, z: float, rot_y: float):
	var g = grp(x, y, z, rot_y)
	var kk := K(g)
	kk.rb(0.42, 0.17, 0.07, 0.01, C.white, [0, 0, 0.035])
	kk.lab("N", "exitGreen", 0.37, 0.14, [0, 0, 0.0715], null, 1.05)
	return g


# ================================================================ floor: doormat, tactile paving

func doormat(x: float, z: float, w: float, d: float, rot_y: float = 0.0):
	var g = grp(x, FY, z, rot_y)
	var kk := K(g)
	kk.rb(w, 0.014, d, 0.006, C.rubber, [0, 0.007, 0])
	var n := floori((d - 0.08) / 0.045)
	for i in n:
		kk.box(w - 0.1, 0.006, 0.022, C.greenDk if i % 4 == 1 else C.dark, [0, 0.016, -d / 2.0 + 0.06 + i * 0.045])
	return g


func bar_geo() -> T.Geometry:
	return geo("tbar", func(): return Geo.rounded_box(1, 1, 1, 1, 0.3))


func dot_geo() -> T.Geometry:
	return geo("tdot", func(): return Geo.cylinder(0.0095, 0.0125, 0.0055, 8, 1))


## raised tactile blocks: "line" (4 bars along the run) or "dot" (5 x 5 domes); a, b = [x, z] run ends
func tactile(kind: String, a: Array, b: Array, y: float = -1.0) -> void:
	if y < 0.0:
		y = FY
	var dx: float = b[0] - a[0]
	var dz: float = b[1] - a[1]
	var len := sqrt(dx * dx + dz * dz)
	var along_x := absf(dx) > absf(dz)
	var n := maxi(1, T.js_round(len / 0.3))
	var base := T.MeshObj.new(Geo.g_box(ctx.cache), M.tactBase)
	base.position = Vector3((a[0] + b[0]) / 2.0, y + 0.003, (a[1] + b[1]) / 2.0)
	base.scale = Vector3(n * 0.3 if along_x else 0.3, 0.006, 0.3 if along_x else n * 0.3)
	base.receive_shadow = true
	A.root.add(base)
	var bg := bar_geo()
	var dg := dot_geo()
	for i in n:
		var t := (i + 0.5) / n
		var cx: float = a[0] + dx * t
		var cz: float = a[1] + dz * t
		tact_parts.append([Geo.g_box(ctx.cache), mtx([cx - 0.15 if along_x else cx, y + 0.0062, cz if along_x else cz - 0.15], [0, 0, 0], [0.006, 0.0006, 0.3] if along_x else [0.3, 0.0006, 0.006]), "joint"])
		if kind == "line":
			for o in [-0.1125, -0.0375, 0.0375, 0.1125]:
				tact_parts.append([bg, mtx([cx if along_x else cx + o, y + 0.0085, cz + o if along_x else cz], [0, 0, 0], [0.26, 0.005, 0.026] if along_x else [0.026, 0.005, 0.26]), "bump"])
		else:
			for u in range(-2, 3):
				for v in range(-2, 3):
					tact_parts.append([dg, mtx([cx + u * 0.058, y + 0.0088, cz + v * 0.058]), "bump"])


func flush_tactile() -> void:
	var bumps := []
	var joints := []
	for p in tact_parts:
		(bumps if p[2] == "bump" else joints).append([p[0], p[1]])
	var mb = merged(bumps, M.tactBump)
	var mj = merged(joints, M.tactJoint)
	for m in [mb, mj]:
		if m != null:
			A.root.add(m)
			ctx.no_outline(m)
	tact_parts.clear()


# ================================================================ ticket machine (touch-screen)

const TVM_PROF := [[0.29, 0.08], [0.29, 1.02], [0.07, 1.40], [0.07, 1.92], [-0.29, 1.92], [-0.29, 0.08]]


func ticket_machine(x: float, z: float, rot_y: float = 0.0, o: Dictionary = {}):
	var g = grp(x, FY, z, rot_y)
	var kk := K(g)
	var W := 0.8
	kk.mesh(geo("tvmBody", func():
		var gg: T.Geometry = ctx.geo.extrude(TVM_PROF, W - 0.024, {"bevel": 0.012})
		gg.rotate_y(-PI / 2.0)
		return gg), M.tvmBody, [0, 0, 0])
	kk.box(W - 0.05, 0.08, 0.54, M.tvmDark, [0, 0.04, 0])
	kk.rb(W + 0.012, 0.028, 0.39, 0.008, M.tvmDark, [0, 1.935, -0.11])
	for s in [-1, 1]:
		kk.box(0.004, 1.6, 0.012, M.tvmDark, [s * (W / 2.0 + 0.011), 0.95, -0.2])
		for i in 5:
			kk.box(0.004, 0.012, 0.16, M.tvmDark, [s * (W / 2.0 + 0.011), 0.25 + i * 0.03, 0.05])
	kk.box(W - 0.06, 0.15, 0.008, M.tvmDark, [0, 1.77, 0.086])
	kk.lab("N", "tvmHead", 0.62, 0.124, [0, 1.775, 0.0905], null, 1.0)
	kk.box(W, 0.018, 0.012, M.pinkBand, [0, 1.675, 0.088])
	kk.lab("N", "tvmLamp", 0.12, 0.032, [0.26, 1.555, 0.0835], null, 1.1)
	kk.lab("N", "lbIC", 0.07, 0.033, [-0.27, 1.555, 0.0835], null, 1.0)
	var th := atan2(0.22, 0.38)
	var sg := T.Group.new()
	sg.position = Vector3(0, 1.21 + 0.012 * sin(th) + 0.0, 0.18 + 0.012 * cos(th))
	sg.rotation.x = -th
	g.add(sg)
	var sk := K(sg)
	var sw := 0.44
	var sh := 0.27
	var sx := -0.1
	var sy := 0.012
	sk.box(sw + 0.06, 0.03, 0.016, M.tvmDark, [sx, sy + sh / 2.0 + 0.015, 0.008])
	sk.box(sw + 0.06, 0.03, 0.016, M.tvmDark, [sx, sy - sh / 2.0 - 0.015, 0.008])
	sk.box(0.03, sh, 0.016, M.tvmDark, [sx - sw / 2.0 - 0.015, sy, 0.008])
	sk.box(0.03, sh, 0.016, M.tvmDark, [sx + sw / 2.0 + 0.015, sy, 0.008])
	var scr := T.MeshObj.new(U.rect_plane(sw, sh, A.atlases.TVM.r("screen")), A.sign_mat("TVM", 1.0))
	scr.position = Vector3(sx, sy, 0.002)
	sg.add(scr)
	sk.rb(0.13, 0.095, 0.014, 0.004, M.stainless, [0.285, 0.1, 0.007])
	sk.box(0.075, 0.012, 0.006, C.ink, [0.285, 0.098, 0.0145])
	sk.box(0.085, 0.01, 0.018, M.stainless, [0.285, 0.083, 0.014], [0.6, 0, 0])
	sk.lab("N", "lbCoin", 0.1, 0.031, [0.285, 0.172, 0.0015])
	sk.box(0.12, 0.12, 0.01, C.dark, [0.285, -0.075, 0.005])
	sk.lab("face", "icPad", 0.1, 0.1, [0.285, -0.075, 0.0105], null, 1.1)
	var fz := 0.302
	kk.rb(0.24, 0.085, 0.055, 0.01, M.tvmDark, [0.19, 0.9, fz + 0.026])
	kk.box(0.17, 0.012, 0.01, C.ink, [0.19, 0.9, fz + 0.053])
	kk.box(0.17, 0.006, 0.004, M.ledGreen, [0.19, 0.924, fz + 0.051]).cast_shadow = false
	kk.lab("N", "lbBill", 0.1, 0.031, [0.19, 0.975, fz + 0.001])
	kk.box(0.075, 0.075, 0.012, C.dark, [-0.29, 0.9, fz + 0.006])
	kk.cz(0.024, 0.02, C.yellow, [-0.29, 0.9, fz + 0.02], 14)
	kk.lab("N", "lbCall", 0.08, 0.029, [-0.29, 0.965, fz + 0.001])
	kk.box(0.5, 0.025, 0.06, M.tvmDark, [0, 0.79, fz + 0.03])
	kk.box(0.5, 0.03, 0.075, M.tvmDark, [0, 0.655, fz + 0.037])
	for s in [-1, 1]:
		kk.box(0.025, 0.11, 0.06, M.tvmDark, [s * 0.2375, 0.722, fz + 0.03])
	kk.box(0.45, 0.11, 0.004, C.ink, [0, 0.722, fz + 0.002])
	kk.box(0.45, 0.085, 0.006, M.smoked, [0, 0.735, fz + 0.04], [-0.3, 0, 0])
	kk.lab("N", "lbTicket", 0.2, 0.031, [0, 0.822, fz + 0.001])
	kk.box(0.5, 0.02, 0.11, M.tvmDark, [0, 0.49, fz + 0.055])
	kk.box(0.46, 0.015, 0.1, M.stainless, [0, 0.33, fz + 0.05])
	for s in [-1, 1]:
		kk.box(0.02, 0.17, 0.11, M.tvmDark, [s * 0.24, 0.41, fz + 0.055])
	kk.box(0.5, 0.05, 0.02, M.tvmDark, [0, 0.35, fz + 0.1])
	kk.box(0.46, 0.15, 0.004, C.ink, [0, 0.41, fz + 0.002])
	kk.lab("N", "lbChange", 0.2, 0.031, [0, 0.527, fz + 0.001])
	kk.rb(0.13, 0.17, 0.012, 0.004, M.stainless, [0.33, 0.6, fz + 0.006])
	for rr in 4:
		for c in 3:
			var m = (C.green if c else C.red) if rr == 3 and c != 1 else C.white
			kk.box(0.024, 0.024, 0.012, m, [0.33 + (c - 1) * 0.034, 0.653 - rr * 0.035, fz + 0.016])
	for i in 4:
		kk.box(0.09, 0.008, 0.004, C.ink, [-0.32, 0.56 + i * 0.022, fz + 0.002])
	kk.box(W - 0.06, 0.06, 0.01, M.tvmDark, [0, 0.13, fz + 0.004])
	if o.get("col", true) != false:
		P.addBox(x, z, W + 0.04, 0.62, rot_y, -1, 3)
	return g


# ================================================================ automatic IC gate cabinet

func head_geo(L: float, H: float, s: float) -> T.Geometry:
	return geo("ghead|%s|%s" % [L, s], func():
		var pts := []
		for e in [[L / 2.0 - 0.01, H + 0.02], [L / 2.0 - 0.4, H + 0.02], [L / 2.0 - 0.4, H + 0.13], [L / 2.0 - 0.05, H + 0.075]]:
			pts.append([e[0] * s, e[1]])
		var gg: T.Geometry = ctx.geo.extrude(pts, 0.3 - 0.016, {"bevel": 0.008})
		gg.rotate_y(-PI / 2.0)
		return gg)


func gate_cabinet(cx: float, cz: float, o: Dictionary = {}):
	var L: float = o.get("L", 1.7)
	var w := 0.3
	var H := 1.0
	var g = grp(cx, FY, cz, 0)
	var kk := K(g)
	kk.box(w - 0.06, 0.1, L - 0.14, M.gateBase, [0, 0.05, 0])
	kk.rb(w, H - 0.1, L, 0.05, M.gateBody, [0, 0.1 + (H - 0.1) / 2.0, 0], null, 2)
	kk.rb(w + 0.014, 0.03, L + 0.014, 0.012, M.gateTop, [0, H + 0.01, 0])
	for s in [-1, 1]:
		kk.box(0.004, 0.012, L - 0.2, M.gateTop, [s * (w / 2.0 + 0.001), 0.28, 0])
		kk.box(0.004, 0.012, L - 0.2, M.gateTop, [s * (w / 2.0 + 0.001), H - 0.06, 0])
	var th := atan2(0.055, 0.35)
	for e in [[1, o.get("readS")], [-1, o.get("readN")]]:
		var end: int = e[0]
		var z_end := end * L / 2.0
		if e[1]:
			kk.mesh(head_geo(L, H, end), M.gateTop, [0, 0, 0])
			var hg := T.Group.new()
			hg.position = Vector3(0, H + 0.1145, end * (L / 2.0 - 0.23))
			hg.set_rotation(-PI / 2.0 + th, 0.0 if end > 0 else PI, 0, "YXZ")
			g.add(hg)
			var hk := K(hg)
			hk.box(0.2, 0.2, 0.006, M.ledBlue, [0, 0, 0.001]).cast_shadow = false
			hk.lab("face", "icPad", 0.17, 0.17, [0, 0, 0.0045], null, 1.15)
			hk.lab("N", "gateScr" if end > 0 else "gateScr2", 0.12, 0.045, [0, 0.145, 0.0045], null, 1.0)
		else:
			kk.rb(w, 0.04, 0.34, 0.012, M.gateTop, [0, H + 0.035, end * (L / 2.0 - 0.17)])
		var ef := T.Group.new()
		ef.position = Vector3(0, 0, z_end + end * 0.004)
		ef.rotation.y = 0.0 if end > 0 else PI
		g.add(ef)
		var ek := K(ef)
		ek.rb(0.15, 0.15, 0.014, 0.01, C.ink, [0, H - 0.14, 0.002])
		var go = o.get("goS") if end > 0 else o.get("goN")
		ek.lab("face", "gateGo" if go else "gateNo", 0.1, 0.1, [0, H - 0.14, 0.0095], null, 1.25)
		var lab_id = o.get("labelS") if end > 0 else o.get("labelN")
		if lab_id:
			ek.lab("face", lab_id, 0.2, 0.06, [0, H - 0.29, 0.001], null, 1.0)
		ek.rb(0.2, 0.012, 0.012, 0.004, M.gateTop, [0, 0.2, 0.004])
		if o.get("ticket") and end > 0:
			ek.rb(0.15, 0.05, 0.045, 0.01, M.gateTop, [0, H - 0.04, 0.02])
			ek.box(0.1, 0.008, 0.006, C.ink, [0, H - 0.04, 0.043])
	if o.get("ticket"):
		kk.rb(0.16, 0.035, 0.1, 0.01, M.gateTop, [0, H + 0.04, -(L / 2.0 - 0.55)])
		kk.box(0.1, 0.004, 0.012, C.ink, [0, H + 0.058, -(L / 2.0 - 0.55)])
	for e in [[1, o.get("flapE")], [-1, o.get("flapW")]]:
		if not e[1]:
			continue
		var s: int = e[0]
		kk.box(0.006, 0.44, 0.06, C.ink, [s * (w / 2.0 + 0.001), 0.64, 0])
		kk.rb(0.1, 0.36, 0.026, 0.012, M.flap, [s * (w / 2.0 + 0.04), 0.64, 0])
		kk.rb(0.02, 0.34, 0.03, 0.008, C.rubber, [s * (w / 2.0 + 0.087), 0.64, 0])
		for zz in [-0.66, -0.46, -0.26, 0.26, 0.46, 0.66]:
			for yy in [0.5, 0.86]:
				kk.rb(0.006, 0.028, 0.04, 0.003, M.smoked, [s * (w / 2.0 + 0.0015), yy, zz])
	return g


# ================================================================ sorted bin unit

func rim_geo() -> T.Geometry:
	return geo("binRim", func(): return Geo.torus(0.07, 0.009, 6, 20).rotate_x(PI / 2.0))


func bin_unit(x: float, z: float, rot_y: float, o: Dictionary = {}):
	var g = grp(x, o.get("y", FY), z, rot_y)
	var kk := K(g)
	var cold: bool = o.get("warm", true) == false
	var kinds: Array = o.get("kinds", [["binCan", M.binBlue if cold else M.binBlueI, "round"], ["binPet", M.binGreen if cold else M.binGreenI, "round"], ["binBurn", M.binRed if cold else M.binRedI, "slot"]])
	var n := kinds.size()
	var pitch := 0.43
	var bw := 0.4
	var bd := 0.38
	var bh := 0.86
	kk.rb(n * pitch + 0.04, 0.05, bd + 0.06, 0.01, C.steelDk, [0, 0.025, 0])
	for i in n:
		var kd: Array = kinds[i]
		var bx := (i - (n - 1) / 2.0) * pitch
		kk.rb(bw, bh, bd, 0.035, kd[1], [bx, 0.05 + bh / 2.0, 0], null, 1)
		kk.box(bw - 0.07, 0.006, 0.004, C.ink, [bx, 0.14, bd / 2.0 + 0.001])
		kk.box(0.004, bh - 0.22, 0.004, C.ink, [bx - bw / 2.0 + 0.035, 0.05 + bh / 2.0 - 0.03, bd / 2.0 + 0.001])
		kk.box(0.004, bh - 0.22, 0.004, C.ink, [bx + bw / 2.0 - 0.035, 0.05 + bh / 2.0 - 0.03, bd / 2.0 + 0.001])
		kk.cz(0.01, 0.006, M.stainless, [bx + 0.13, 0.72, bd / 2.0 + 0.003], 8)
		lab(g, "B", kd[0], 0.28, 0.14, [bx, 0.56, bd / 2.0 + 0.002], null, false if cold else 0.85)
		var ly := 0.05 + bh
		kk.rb(bw + 0.02, 0.05, bd + 0.02, 0.012, M.binGrey, [bx, ly + 0.025, 0])
		if kd[2] == "round":
			kk.cy(0.068, 0.004, C.ink, [bx, ly + 0.051, 0], 18)
			kk.mesh(rim_geo(), C.greyLt, [bx, ly + 0.052, 0])
		else:
			kk.box(0.27, 0.004, 0.09, C.ink, [bx, ly + 0.051, 0.02])
			for s in [-1, 1]:
				kk.box(0.3, 0.014, 0.014, C.greyLt, [bx, ly + 0.056, 0.02 + s * 0.052])
				kk.box(0.014, 0.014, 0.09, C.greyLt, [bx + s * 0.142, ly + 0.056, 0.02])
			kk.box(0.26, 0.008, 0.07, M.binGrey, [bx, ly + 0.046, 0.01], [0.35, 0, 0])
	if o.get("col", true) != false:
		P.addBox(x, z, n * pitch + 0.06, bd + 0.08, rot_y, -1, 3)
	return g


# ================================================================ umbrella rack with folded umbrellas

func umb_geo() -> T.Geometry:
	return geo("umbCanopy", func():
		var g := Geo.cylinder(0.046, 0.01, 0.6, 8, 3)
		var p := g.position()
		for i in p.count():
			var x := p.get_x(i)
			var z := p.get_z(i)
			var a := atan2(z, x)
			var k := 1.0 if int(T.js_round(a / (PI / 4.0))) % 2 == 0 else 0.7
			p.set_x(i, x * k)
			p.set_z(i, z * k)
		g.compute_vertex_normals()
		return g)


func umbrella(g, x: float, y: float, z: float, m, o: Dictionary = {}):
	var ug := T.Group.new()
	ug.position = Vector3(x, y, z)
	ug.rotation = Vector3(o.get("rx", 0.0), o.get("ry", 0.0), o.get("rz", 0.0))
	g.add(ug)
	var uk := K(ug)
	uk.cy(0.005, 0.07, C.ink, [0, 0.035, 0], 6)
	uk.mesh(umb_geo(), m, [0, 0.37, 0])
	uk.cy(0.043, 0.03, C.white if m == M.vinyl else m, [0, 0.52, 0], 8)
	uk.cy(0.007, 0.16, C.steel, [0, 0.74, 0], 6)
	var handle = o.get("handle") if o.get("handle") != null else C.woodDk
	if o.get("straight"):
		uk.cy(0.016, 0.1, handle, [0, 0.86, 0], 8)
	else:
		uk.cy(0.012, 0.05, handle, [0, 0.84, 0], 8)
		uk.torus(0.035, 0.011, handle, [0.035, 0.865, 0], [0, 0, 0], PI, 10)
	return ug


func umbrella_rack(x: float, z: float, rot_y: float, o: Dictionary = {}):
	var g = grp(x, FY, z, rot_y)
	var kk := K(g)
	var n: int = o.get("n", 6)
	var cw := 0.12
	var W := n * cw
	var D := 0.2
	kk.box(W + 0.06, 0.02, D + 0.06, M.stainless, [0, 0.03, 0])
	for s in [-1, 1]:
		kk.box(W + 0.06, 0.04, 0.012, M.stainless, [0, 0.05, s * (D / 2.0 + 0.03)])
		kk.box(0.012, 0.04, D + 0.06, M.stainless, [s * (W / 2.0 + 0.03), 0.05, 0])
	kk.box(W + 0.03, 0.002, D + 0.03, C.steelDk, [0, 0.041, 0])
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			kk.box(0.02, 0.62, 0.02, M.stainless, [sx * W / 2.0, 0.35, sz * D / 2.0])
	for sz in [-1, 1]:
		kk.box(W + 0.02, 0.025, 0.012, M.stainless, [0, 0.66, sz * D / 2.0])
		kk.box(W + 0.02, 0.012, 0.012, M.stainless, [0, 0.3, sz * D / 2.0])
	for i in n + 1:
		kk.box(0.01, 0.025, D, M.stainless, [-W / 2.0 + i * cw, 0.66, 0])
	var r: Rng = ctx.rng(o.get("seed", "umb"))
	var cols := [M.umbrellaCols[0], M.vinyl, M.umbrellaCols[1], M.umbrellaCols[3], M.vinyl, M.umbrellaCols[4], M.umbrellaCols[5], M.umbrellaCols[2]]
	for i in o.get("filled", [0, 1, 2, 4, 5]):
		var ux: float = -W / 2.0 + cw * (i + 0.5)
		var uz := (r.f() - 0.5) * 0.04
		var rx := (r.f() - 0.5) * 0.12
		var rz := (r.f() - 0.5) * 0.12
		var ry := r.f() * PI * 2.0
		var straight := r.f() < 0.3
		var handle = C.black if r.f() < 0.4 else C.woodDk
		umbrella(g, ux, 0.04, uz, cols[i % cols.size()], {"rx": rx, "rz": rz, "ry": ry, "straight": straight, "handle": handle})
	if o.get("col", true) != false:
		P.addBox(x, z, W + 0.1, D + 0.1, rot_y, -1, 3)
	return g


# ================================================================ waiting-room bench

func bench_in(x: float, z: float, rot_y: float, len: float = 2.2, o: Dictionary = {}):
	var g = grp(x, FY, z, rot_y)
	var kk := K(g)
	var slat = o.get("slat", C.wood)
	var frame = o.get("frame", C.dark)
	for i in 4:
		kk.rb(len, 0.032, 0.088, 0.01, slat, [0, 0.43, -0.16 + i * 0.104])
	for i in 3:
		kk.rb(len, 0.085, 0.028, 0.01, slat, [0, 0.58 + i * 0.12, -0.235 - i * 0.017], [-0.14, 0, 0])
	var n_leg := maxi(2, T.js_round(len / 1.1) + 1)
	for j in n_leg:
		var lx := -len / 2.0 + 0.12 + (len - 0.24) * j / (n_leg - 1)
		kk.box(0.045, 0.41, 0.045, frame, [lx, 0.205, 0.17])
		kk.box(0.045, 0.86, 0.045, frame, [lx, 0.43, -0.24], [-0.1, 0, 0])
		kk.box(0.045, 0.04, 0.46, frame, [lx, 0.395, -0.03])
		kk.box(0.045, 0.03, 0.4, frame, [lx, 0.05, -0.03])
		kk.box(0.05, 0.012, 0.06, C.rubber, [lx, 0.006, 0.17])
		kk.box(0.05, 0.012, 0.06, C.rubber, [lx, 0.006, -0.2])
		if j == 0 or j == n_leg - 1:
			kk.rb(0.06, 0.035, 0.44, 0.012, slat, [lx, 0.66, -0.01])
			kk.box(0.04, 0.22, 0.04, frame, [lx, 0.55, 0.16])
	if o.get("col", true) != false:
		P.addBox(x, z, len + 0.06, 0.55, rot_y, -1, FY + 0.55)
	return g


# ================================================================ kerosene stove with guard and kettle

func stove(x: float, z: float):
	var g = grp(x, FY, z, 0.4)
	var kk := K(g)
	kk.rb(1.0, 0.012, 1.0, 0.005, C.steelDk, [0, 0.006, 0])
	kk.cy(0.27, 0.05, C.dark, [0, 0.045, 0], 20)
	for i in 3:
		var a := i * PI * 2.0 / 3.0
		kk.box(0.05, 0.02, 0.05, C.ink, [cos(a) * 0.23, 0.01, sin(a) * 0.23])
	kk.cy(0.235, 0.5, C.greyLt, [0, 0.32, 0], 22)
	kk.cy(0.24, 0.03, C.dark, [0, 0.085, 0], 22)
	kk.cy(0.24, 0.02, C.dark, [0, 0.575, 0], 22)
	kk.cy(0.25, 0.04, C.steel, [0, 0.605, 0], 22)
	kk.cy(0.215, 0.006, C.ink, [0, 0.626, 0], 20)
	for i in range(-3, 4):
		kk.box(0.4 * cos(asin(absf(i) / 3.6)), 0.01, 0.014, C.steel, [0, 0.63, i * 0.055])
	var wg := T.Group.new()
	wg.position = Vector3(0, 0.3, 0)
	g.add(wg)
	var wk := K(wg)
	wk.rb(0.2, 0.14, 0.03, 0.01, C.ink, [0, 0, 0.225])
	wk.rb(0.16, 0.1, 0.02, 0.008, M.smoked, [0, 0, 0.235])
	kk.cz(0.03, 0.03, C.ink, [0.12, 0.14, 0.24], 12)
	kk.box(0.012, 0.05, 0.012, C.red, [0.12, 0.14, 0.258])
	kk.cz(0.022, 0.012, C.white, [-0.12, 0.14, 0.235], 12)
	for s in [-1, 1]:
		kk.box(0.02, 0.06, 0.02, C.steel, [s * 0.2, 0.66, -0.06])
		kk.box(0.02, 0.06, 0.02, C.steel, [s * 0.2, 0.66, 0.06])
		kk.box(0.02, 0.018, 0.14, C.steel, [s * 0.2, 0.69, 0])
	var kt := T.Group.new()
	kt.position = Vector3(0.02, 0.63, 0)
	kt.rotation.y = -0.9
	g.add(kt)
	var tk := K(kt)
	tk.mesh(geo("kettle", func(): return Geo.cylinder(0.1, 0.12, 0.13, 18)), C.steel, [0, 0.065, 0])
	tk.mesh(geo("kettleTop", func(): return Geo.sphere(0.1, 18, 6, 0, TAU, 0, PI / 2.0)), C.steel, [0, 0.13, 0])
	tk.cy(0.04, 0.02, C.steelDk, [0, 0.225, 0], 12)
	tk.sphere(0.015, C.black, [0, 0.24, 0], 8)
	var sp = tk.cy(0.014, 0.12, C.steel, [0.13, 0.12, 0], 8)
	sp.rotation.z = -0.9
	tk.torus(0.085, 0.009, C.black, [0, 0.2, 0], [0, 0, 0], PI, 12)
	var R := 0.5
	for y in [0.06, 0.45, 0.78]:
		kk.torus(R, 0.01, C.steel, [0, y, 0], [PI / 2.0, 0, 0], PI * 2.0, 32)
	for i in 14:
		var a := i * PI * 2.0 / 14.0
		kk.cy(0.007, 0.74, C.steel, [cos(a) * R, 0.42, sin(a) * R], 6)
	P.addCylinder(x, z, R + 0.04, -1, FY + 1.0)
	return g


# ================================================================ bookshelf with individual books

func fill_books(kk, r: Rng, x0: float, x1: float, y: float, depth: float, hmax: float, z: float = 0.0) -> void:
	var bx := x0 + 0.01
	while bx < x1 - 0.03:
		var q := r.f()
		if q < 0.08 and x1 - bx > 0.25:
			var n := 2 + floori(r.f() * 3.0)
			var yy := y
			for i in n:
				var t := 0.02 + r.f() * 0.02
				var bw := 0.17 + r.f() * 0.05
				var m = book_cols[floori(r.f() * book_cols.size())]
				var ry := (r.f() - 0.5) * 0.15
				kk.box(bw, t, depth * 0.8, m, [bx + 0.11, yy + t / 2.0, z], [0, ry, 0])
				yy += t
			bx += 0.24
			continue
		if q < 0.14:
			bx += 0.03 + r.f() * 0.05
			continue
		var t := 0.018 + r.f() * 0.035
		var h := hmax * (0.62 + r.f() * 0.36)
		var d := depth * (0.75 + r.f() * 0.2)
		var lean := -0.22 if (q > 0.9 and bx > x0 + 0.1) else 0.0
		var m = book_cols[floori(r.f() * book_cols.size())]
		kk.box(t, h, d, m, [bx + t / 2.0 + (h * 0.1 if lean else 0.0), y + h / 2.0 - (0.005 if lean else 0.0), z], [0, 0, lean])
		if r.f() < 0.55:
			kk.box(t + 0.002, 0.018, 0.004, C.paper, [bx + t / 2.0 + (h * 0.1 if lean else 0.0), y + h * 0.72, z + d / 2.0], [0, 0, lean])
		bx += t + 0.002 + (h * 0.22 if lean else 0.0)


func bookshelf(x: float, z: float, rot_y: float, o: Dictionary = {}) -> Dictionary:
	var W: float = o.get("w", 1.6)
	var H: float = o.get("h", 0.86)
	var D: float = o.get("d", 0.3)
	var t := 0.02
	var g = grp(x, FY, z, rot_y)
	var kk := K(g)
	var wood = C.woodLt
	var dk = C.wood
	kk.box(t, H, D, wood, [-W / 2.0 + t / 2.0, H / 2.0, 0])
	kk.box(t, H, D, wood, [W / 2.0 - t / 2.0, H / 2.0, 0])
	kk.rb(W + 0.02, 0.025, D + 0.02, 0.008, wood, [0, H + 0.0125, 0])
	kk.box(W - 2.0 * t, 0.06, D - 0.01, dk, [0, 0.03, 0.005])
	kk.box(W - 2.0 * t, 0.01, D - 0.01, dk, [0, 0.065, 0])
	kk.box(W, H - 0.02, 0.01, dk, [0, H / 2.0, -D / 2.0 + 0.005])
	var shelves: int = o.get("shelves", 2)
	var span := (H - 0.08) / shelves
	var r: Rng = ctx.rng(o.get("seed", "books"))
	for s in shelves:
		var y := 0.07 + s * span
		if s > 0:
			kk.box(W - 2.0 * t, 0.018, D - 0.02, wood, [0, y - 0.009, 0])
		if s == 0 and W > 1.2:
			kk.box(t, span - 0.01, D - 0.02, wood, [0, y + span / 2.0, 0])
			fill_books(kk, r, -W / 2.0 + t, -t / 2.0, y, D - 0.06, span - 0.04)
			fill_books(kk, r, t / 2.0, W / 2.0 - t, y, D - 0.06, span - 0.04)
		else:
			fill_books(kk, r, -W / 2.0 + t, W / 2.0 - t, y, D - 0.06, span - 0.04)
	if o.get("col", true) != false:
		P.addBox(x, z, W, D + 0.04, rot_y, -1, 3)
	return {"g": g, "kk": kk, "top": H + 0.025}


## folded newspaper stack
func newspapers(kk, x: float, y: float, z: float, n: int = 4, rot: float = 0.0) -> void:
	for i in n:
		kk.box(0.3, 0.008, 0.21, C.paper, [x + (i % 2) * 0.004, y + 0.004 + i * 0.008, z + (i % 3) * 0.003], [0, rot + (0.03 if i % 2 else -0.02), 0])
	kk.lab("N", "news", 0.29, 0.2, [x, y + n * 0.008 + 0.0015, z], [-PI / 2.0, 0, rot], 0.85)


## pamphlet stand with slanted pockets
func pamphlet_rack(x: float, z: float, rot_y: float):
	var g = grp(x, FY, z, rot_y)
	var kk := K(g)
	var W := 0.46
	var H := 1.3
	kk.box(W, H, 0.02, C.woodDk, [0, H / 2.0, -0.1])
	for s in [-1, 1]:
		kk.box(0.02, H, 0.2, C.woodDk, [s * (W / 2.0 - 0.01), H / 2.0, 0])
	kk.box(W, 0.05, 0.22, C.woodDk, [0, 0.025, 0])
	var ids := [["pamA", "pamB", "pamC"], ["freePaper", "pamC", "pamA"], ["pamB", "pamA", "freePaper"], ["pamC", "freePaper", "pamB"]]
	for s in 4:
		var y := 0.3 + s * 0.27
		kk.box(W - 0.04, 0.012, 0.16, C.woodDk, [0, y, -0.01], [0.35, 0, 0])
		kk.box(W - 0.04, 0.06, 0.006, M.glassIn, [0, y + 0.03, 0.07]).cast_shadow = false
		for i in 3:
			var id: String = ids[s][i]
			var pg := T.Group.new()
			pg.position = Vector3((i - 1) * 0.135, y + 0.09, 0.0)
			pg.rotation.x = -0.35
			g.add(pg)
			var pk := K(pg)
			pk.box(0.1, 0.14, 0.012, C.paper, [0, 0, 0])
			pk.lab("B" if id == "freePaper" else "N", id, 0.098, 0.136, [0, 0, 0.0065], null, 0.85)
	kk.lab("N", "paperSign", 0.4, 0.107, [0, H - 0.08, -0.089], null, 0.9)
	P.addBox(x, z, W, 0.24, rot_y, -1, 3)
	return g


# ================================================================ drinks vending machine

func can_geo() -> T.Geometry:
	return geo("can", func(): return Geo.cylinder(0.032, 0.032, 0.12, 12))


func bot_geo() -> T.Geometry:
	return geo("bottle", func():
		var pts := []
		for e in [[0, 0], [0.033, 0], [0.034, 0.1], [0.022, 0.13], [0.014, 0.15], [0.014, 0.165], [0, 0.165]]:
			pts.append(Vector2(e[0], e[1]))
		return Geo.lathe(pts, 10))


func vending_machine(x: float, z: float, rot_y: float, o: Dictionary = {}):
	var g = grp(x, FY, z, rot_y)
	var kk := K(g)
	var body = o.get("body") if o.get("body") != null else M.ic.call("#f1ecef")
	var trim = o.get("trim") if o.get("trim") != null else C.pink
	kk.box(0.96, 0.08, 0.68, C.dark, [0, 0.04, -0.02])
	kk.rb(1.0, 1.77, 0.52, 0.025, body, [0, 0.08 + 0.885, -0.1])
	kk.box(1.0, 0.85, 0.2, body, [0, 0.08 + 0.425, 0.26])
	kk.box(1.0, 0.3, 0.2, body, [0, 1.55 + 0.15, 0.26])
	kk.box(0.06, 0.62, 0.2, body, [-0.47, 1.24, 0.26])
	kk.box(0.3, 0.62, 0.2, body, [0.35, 1.24, 0.26])
	kk.lab("N", "vmHead", 0.9, 0.253, [0, 1.7, 0.3615], null, 1.05)
	kk.box(1.0, 0.02, 0.012, trim, [0, 1.56, 0.36])
	kk.box(1.0, 0.02, 0.012, trim, [0, 0.93, 0.36])
	kk.box(0.64, 0.62, 0.01, M.lampGlow, [-0.12, 1.24, 0.165]).cast_shadow = false
	var r: Rng = ctx.rng(o.get("seed", "vm"))
	var drink_cols := []
	for h in ["#8a5a3a", "#4f8f5f", "#ef9fbe", "#e8914a", "#e8e4dc", "#3f6fb0", "#c9504a", "#e8c24a", "#8fd1c1", "#6e5140"]:
		drink_cols.append(M.ic.call(h))
	for row in 3:
		var yb := 0.975 + row * 0.2
		kk.box(0.64, 0.012, 0.18, C.steel, [-0.12, yb - 0.006, 0.26])
		for i in 6:
			var dx := -0.39 + i * 0.108
			var m = drink_cols[floori(r.f() * drink_cols.size())]
			if row == 2 or (row == 1 and i % 2 == 0):
				kk.mesh(bot_geo(), m, [dx, yb, 0.27])
				kk.cy(0.035, 0.03, C.white, [dx, yb + 0.07, 0.27], 10)
			else:
				kk.mesh(can_geo(), m, [dx, yb + 0.06, 0.27])
				kk.cy(0.0325, 0.03, C.white if i % 3 else C.steel, [dx, yb + 0.07, 0.27], 10)
				kk.cy(0.026, 0.006, C.steel, [dx, yb + 0.123, 0.27], 10)
			kk.box(0.05, 0.016, 0.01, M.ledRed if row == 0 and i < 2 else M.ledBlue, [dx, yb - 0.022, 0.357]).cast_shadow = false
		kk.lab("N", "vmTags", 0.64, 0.024, [-0.12, yb + 0.0, 0.352], null, 0.95)
	var gl = kk.plane(0.64, 0.62, M.glass, [-0.12, 1.24, 0.358])
	gl.cast_shadow = false
	for yy in [1.555, 0.925]:
		kk.box(0.66, 0.03, 0.03, C.greyLt, [-0.12, yy, 0.35])
	kk.rb(0.2, 0.26, 0.014, 0.006, C.greyLt, [0.35, 1.3, 0.367])
	kk.box(0.02, 0.07, 0.008, C.ink, [0.3, 1.36, 0.376])
	kk.lab("N", "vmCoin", 0.07, 0.021, [0.3, 1.42, 0.3745], null, 0.9)
	kk.rb(0.1, 0.05, 0.03, 0.006, C.dark, [0.39, 1.36, 0.38])
	kk.box(0.08, 0.008, 0.006, C.ink, [0.39, 1.36, 0.396])
	kk.box(0.1, 0.035, 0.006, M.ledAmber, [0.35, 1.24, 0.376]).cast_shadow = false
	kk.box(0.09, 0.09, 0.008, C.dark, [0.35, 1.13, 0.37])
	lab(g, "face", "icPad", 0.075, 0.075, [0.35, 1.13, 0.3745], null, 1.1)
	kk.box(0.03, 0.06, 0.03, C.greyLt, [0.44, 1.22, 0.38])
	kk.rb(0.1, 0.08, 0.05, 0.01, C.greyLt, [0.39, 0.62, 0.385])
	kk.box(0.07, 0.04, 0.02, C.ink, [0.39, 0.62, 0.405])
	kk.box(0.62, 0.05, 0.05, C.greyLt, [-0.12, 0.44, 0.385])
	kk.box(0.62, 0.04, 0.06, C.greyLt, [-0.12, 0.18, 0.39])
	for s in [-1, 1]:
		kk.box(0.03, 0.26, 0.05, C.greyLt, [-0.12 + s * 0.31, 0.31, 0.385])
	kk.box(0.58, 0.22, 0.004, C.ink, [-0.12, 0.31, 0.362])
	kk.box(0.58, 0.2, 0.01, M.smoked, [-0.12, 0.32, 0.395], [-0.12, 0, 0])
	kk.lab("N", "vmTake", 0.2, 0.029, [-0.12, 0.5, 0.3615], null, 0.9)
	kk.box(0.04, 0.3, 0.004, trim, [-0.47, 0.5, 0.362])
	if o.get("col", true) != false:
		P.addBox(x, z, 1.02, 0.78, rot_y, -1, 3)
	return g


# ================================================================ boards

## cork board on a wall; sheets: [[atlas, id, lx, ly, w, h, rotZ, curl, corner, pins]]
func cork_board(x: float, y: float, z: float, rot_y: float, w: float, h: float, sheets: Array = [], o: Dictionary = {}):
	var g = grp(x, y, z, rot_y)
	var kk := K(g)
	var fr = o.get("frame", C.woodDk)
	var ft := 0.045
	kk.box(w, h, 0.012, C.woodDk, [0, 0, 0.006])
	kk.box(w, h, 0.012, M.cork, [0, 0, 0.018])
	kk.rb(w + ft * 2.0, ft, 0.035, 0.008, fr, [0, h / 2.0 + ft / 2.0, 0.0175])
	kk.rb(w + ft * 2.0, ft, 0.035, 0.008, fr, [0, -h / 2.0 - ft / 2.0, 0.0175])
	kk.rb(ft, h, 0.035, 0.008, fr, [-w / 2.0 - ft / 2.0, 0, 0.0175])
	kk.rb(ft, h, 0.035, 0.008, fr, [w / 2.0 + ft / 2.0, 0, 0.0175])
	if o.get("title") != null:
		var tt: Array = o.title
		kk.rb(tt[1], 0.09, 0.015, 0.005, C.cream, [0, h / 2.0 + 0.1, 0.02])
		kk.lab(tt[0], tt[2], tt[1] - 0.02, 0.07, [0, h / 2.0 + 0.1, 0.0285], null, 0.9)
	var pi := [0]
	for s in sheets:
		var atlas: String = s[0]
		var id = s[1]
		var lx: float = s[2]
		var ly: float = s[3]
		var sw: float = s[4]
		var sh: float = s[5]
		var rz: float = s[6] if s.size() > 6 else 0.0
		var curl: float = s[7] if s.size() > 7 else 0.012
		var corner: float = s[8] if s.size() > 8 else 0.0
		var pins: int = s[9] if s.size() > 9 else 1
		sheet(g, atlas, id, sw, sh, [lx, ly, 0.0255], rz, {"curl": curl, "corner": corner})
		var cs := cos(rz)
		var sn := sin(rz)
		var pin_at := func(px: float, py: float) -> void:
			var wx := lx + px * cs - py * sn
			var wy := ly + px * sn + py * cs
			kk.cz(0.0075, 0.012, PIN[pi[0] % PIN.size()], [wx, wy, 0.034], 8)
			pi[0] += 1
			kk.cz(0.004, 0.01, C.steel, [wx, wy, 0.028], 6)
		if pins >= 1:
			pin_at.call(0.0, sh / 2.0 - 0.014)
		if pins >= 2:
			pin_at.call(-sw / 2.0 + 0.014, sh / 2.0 - 0.014)
			pin_at.call(sw / 2.0 - 0.014, sh / 2.0 - 0.014)
		if pins >= 4:
			pin_at.call(-sw / 2.0 + 0.014, -sh / 2.0 + 0.014)
			pin_at.call(sw / 2.0 - 0.014, -sh / 2.0 + 0.014)
	return g


func chalk_board(x: float, y: float, z: float, rot_y: float, w: float = 1.2, h: float = 0.68):
	var g = grp(x, y, z, rot_y)
	var kk := K(g)
	kk.box(w, h, 0.015, C.greenDk, [0, 0, 0.0075])
	kk.lab("N", "dengon", w, h, [0, 0, 0.0155], null, 0.72)
	var ft := 0.04
	kk.rb(w + ft * 2.0, ft, 0.03, 0.008, C.woodDk, [0, h / 2.0 + ft / 2.0, 0.015])
	kk.rb(ft, h, 0.03, 0.008, C.woodDk, [-w / 2.0 - ft / 2.0, 0, 0.015])
	kk.rb(ft, h, 0.03, 0.008, C.woodDk, [w / 2.0 + ft / 2.0, 0, 0.015])
	kk.rb(w + ft * 2.0, 0.03, 0.09, 0.008, C.woodDk, [0, -h / 2.0 - 0.015, 0.045])
	kk.box(w + ft * 2.0, 0.025, 0.012, C.woodDk, [0, -h / 2.0 + 0.005, 0.085])
	var chalk := [C.white, C.pink, C.yellow, C.white]
	for i in chalk.size():
		kk.cx(0.0055, 0.07, chalk[i], [-0.35 + i * 0.09, -h / 2.0 + 0.006, 0.05 + (i % 2) * 0.012], 8)
	kk.rb(0.13, 0.03, 0.05, 0.008, C.navy, [0.32, -h / 2.0 + 0.015, 0.05])
	kk.box(0.13, 0.01, 0.05, C.beige, [0.32, -h / 2.0 - 0.0, 0.05])
	return g


# ================================================================ wall safety devices

func wall_speaker(x: float, y: float, z: float, rot_y: float):
	var g = grp(x, y, z, rot_y)
	var kk := K(g)
	kk.box(0.06, 0.08, 0.06, C.white, [0, 0.07, 0.03])
	var sp := T.Group.new()
	sp.position = Vector3(0, 0, 0.1)
	sp.rotation.x = 0.25
	g.add(sp)
	var sk := K(sp)
	sk.rb(0.26, 0.17, 0.1, 0.02, C.white, [0, 0, 0])
	sk.box(0.2, 0.12, 0.004, C.grey, [0, 0, 0.051])
	for i in 6:
		sk.box(0.18, 0.008, 0.004, C.dark, [0, -0.05 + i * 0.02, 0.0535])
	return g


func fire_extinguisher(kk, x: float, y: float, z: float, s: float = 1.0) -> void:
	kk.cy(0.075 * s, 0.42 * s, C.red, [x, y + 0.21 * s, z], 14)
	var top = kk.sphere(0.075 * s, C.red, [x, y + 0.42 * s, z], 12)
	top.scale.y *= 0.5
	kk.cy(0.022 * s, 0.05 * s, C.ink, [x, y + 0.47 * s, z], 8)
	kk.box(0.1 * s, 0.018 * s, 0.03 * s, C.ink, [x + 0.03 * s, y + 0.505 * s, z])
	kk.box(0.09 * s, 0.014 * s, 0.028 * s, C.ink, [x + 0.03 * s, y + 0.48 * s, z], [0, 0, -0.35])
	kk.cz(0.02 * s, 0.01 * s, C.white, [x, y + 0.36 * s, z + 0.074 * s], 10)
	kk.box(0.08 * s, 0.12 * s, 0.004 * s, C.paper, [x, y + 0.22 * s, z + 0.075 * s])
	var hose = kk.cy(0.011 * s, 0.34 * s, C.ink, [x - 0.08 * s, y + 0.28 * s, z + 0.02 * s], 6)
	hose.rotation.z = 0.12
	kk.cy(0.016 * s, 0.05 * s, C.ink, [x - 0.1 * s, y + 0.1 * s, z + 0.02 * s], 8)


## floor-standing red extinguisher box (open front)
func fire_box(x: float, z: float, rot_y: float):
	var g = grp(x, FY, z, rot_y)
	var kk := K(g)
	kk.box(0.34, 0.02, 0.26, C.red, [0, 0.01, 0])
	kk.box(0.34, 0.6, 0.02, C.red, [0, 0.3, -0.12])
	for s in [-1, 1]:
		kk.box(0.02, 0.6, 0.26, C.red, [s * 0.16, 0.3, 0])
	kk.rb(0.36, 0.03, 0.28, 0.008, C.redDk, [0, 0.615, 0])
	kk.box(0.3, 0.14, 0.012, C.red, [0, 0.52, 0.125])
	kk.lab("N", "fireSign", 0.26, 0.082, [0, 0.52, 0.132], null, 0.95)
	fire_extinguisher(kk, 0, 0.02, 0.0, 0.9)
	P.addBox(x, z, 0.36, 0.3, rot_y, -1, 2)
	return g


func aed_box(x: float, y: float, z: float, rot_y: float):
	var g = grp(x, y, z, rot_y)
	var kk := K(g)
	kk.rb(0.44, 0.5, 0.2, 0.02, C.white, [0, 0, 0.1])
	for e in [[0.38, 0.03, 0, 0.19], [0.38, 0.03, 0, -0.19], [0.03, 0.35, -0.175, 0], [0.03, 0.35, 0.175, 0]]:
		kk.box(e[0], e[1], 0.02, C.greyLt, [e[2], e[3], 0.205])
	kk.box(0.34, 0.34, 0.004, C.offWhite, [0, 0, 0.012])
	kk.rb(0.26, 0.2, 0.09, 0.02, C.orange, [0, -0.04, 0.07])
	kk.box(0.12, 0.03, 0.03, C.dark, [0, 0.07, 0.07])
	kk.box(0.16, 0.08, 0.004, C.dark, [0, -0.04, 0.1155])
	var gl = kk.plane(0.32, 0.34, M.glassIn, [0, 0, 0.2])
	gl.cast_shadow = false
	kk.box(0.03, 0.08, 0.02, C.greyLt, [0.2, 0, 0.21])
	kk.box(0.02, 0.02, 0.01, M.ledGreen, [0.16, 0.2, 0.2]).cast_shadow = false
	kk.rb(0.46, 0.18, 0.03, 0.008, C.white, [0, 0.36, 0.015])
	kk.lab("N", "aedSign", 0.42, 0.168, [0, 0.36, 0.031], null, 1.0)
	return g


# ================================================================ plants

func potted_plant(x: float, z: float, o: Dictionary = {}):
	var y0: float = o.get("y", FY)
	var g = grp(x, y0, z, o.get("rot", 0.0))
	var kk := K(g)
	var pr: float = o.get("potR", 0.2)
	var ph: float = o.get("potH", 0.36)
	var pot = o.get("pot") if o.get("pot") != null else M.plantPot
	kk.mesh(geo("pot|%s|%s" % [pr, ph], func(): return Geo.cylinder(pr, pr * 0.78, ph, 16)), pot, [0, ph / 2.0, 0])
	kk.cy(pr * 1.04, 0.035, pot, [0, ph - 0.012, 0], 16)
	kk.cy(pr * 0.94, 0.01, C.soil, [0, ph - 0.03, 0], 14)
	if o.get("saucer", true) != false:
		kk.cy(pr * 0.95, 0.025, C.offWhite, [0, 0.0125, 0], 16)
	if o.get("kind") == "topiary":
		var t = Foliage.make_topiary(ctx, {"trunk": o.get("trunk", 0.55), "r": o.get("r", 0.24), "seed": o.get("seed", 7)})
		t.position.y = ph - 0.03
		g.add(t)
	else:
		var s = Foliage.make_shrub(ctx, {"r": o.get("r", 0.28), "h": o.get("h", 0.5), "seed": o.get("seed", 3), "kind": o.get("shrubKind", "camellia"), "lumps": 0.28})
		s.position.y = ph - 0.04
		g.add(s)
	if o.get("col", true) != false:
		P.addCylinder(x, z, pr + 0.05, -1, y0 + 1.2)
	return g


func clipboard(g, x: float, y: float, z: float, id, rz: float = 0.0):
	var cg := T.Group.new()
	cg.position = Vector3(x, y, z)
	cg.rotation.z = rz
	g.add(cg)
	var ck := K(cg)
	ck.cz(0.004, 0.02, C.steel, [0, 0.175, 0.006], 6)
	ck.rb(0.23, 0.32, 0.006, 0.01, C.woodLt, [0, 0, 0.004])
	sheet(cg, "N", id, 0.21, 0.28, [0, -0.012, 0.0075], 0.0, {"curl": 0.01})
	ck.rb(0.1, 0.03, 0.016, 0.004, C.steel, [0, 0.14, 0.012])
	ck.box(0.03, 0.012, 0.012, C.steel, [0, 0.162, 0.018])
	return cg


## The kit for a props group with the extras: rb (cached rounded box), cz / cx / cy (cylinders),
## lab (atlas label plane) and torus.
class PKit extends Geo.Kit:
	var X

	func _init(p, c, props) -> void:
		super(p, c)
		X = props

	func rb(w: float, h: float, d: float, r: float, m, pos, rot = null, seg: int = 1):
		var g: T.Geometry = X.geo("rb|%s|%s|%s|%s|%d" % [w, h, d, r, seg], func(): return Geo.rounded_box(w, h, d, seg, minf(minf(r, w / 2.0), minf(h / 2.0, d / 2.0))))
		return mesh(g, m, pos, rot)

	func cz(r: float, len: float, m, pos, seg: int = 10, rot = null):
		return mesh(X.U.cyl_z(seg), m, pos, rot, [r * 2.0, r * 2.0, len])

	func cx(r: float, len: float, m, pos, seg: int = 10):
		return mesh(X.U.cyl_z(seg), m, pos, [0, PI / 2.0, 0], [r * 2.0, r * 2.0, len])

	func cy(r: float, h: float, m, pos, seg: int = 12):
		return mesh(X.U.cyl(seg), m, pos, null, [r * 2.0, h, r * 2.0])

	func lab(atlas: String, id, w: float, h: float, pos, rot = null, lit = 0.85):
		return X.lab(parent, atlas, id, w, h, pos, rot, lit)

	func torus(R: float, r: float, m, pos, rot, arc: float = PI * 2.0, seg: int = 20):
		var g: T.Geometry = X.geo("tor|%s|%s|%s|%d" % [R, r, arc, seg], func(): return Geo.torus(R, r, 6, seg, arc))
		return mesh(g, m, pos, rot)
