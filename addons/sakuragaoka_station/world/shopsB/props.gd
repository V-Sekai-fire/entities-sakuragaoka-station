# shopsB/props.js: shared modelled interior props (all real geometry; canvas textures only for flat
# graphics such as dial faces, labels and calendars). Every function builds a Group at (x, y, z)
# rotated by rotY in parent space; local +Z is the object's front. Interior variants use K.im.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")


static func grp(p, x: float, y: float, z: float, rot_y: float = 0.0):
	var g := T.Group.new()
	g.position = Vector3(x, y, z)
	g.rotation.y = rot_y
	p.add(g)
	return g


static func _o(o: Dictionary, k: String, d):
	return o[k] if o.get(k) != null else d


## Cylinder between two points (parent space).
static func tube(p, a: Array, b: Array, r: float, m, seg: int = 8):
	var A := Vector3(a[0], a[1], a[2])
	var B := Vector3(b[0], b[1], b[2])
	var d := B - A
	var length := d.length()
	var mesh := T.MeshObj.new(Geo.cylinder(r, r, length, seg), m)
	mesh.position = A + d * 0.5
	mesh.set_quaternion(T.quat_from_unit_vectors(Vector3(0, 1, 0), d.normalized()))
	mesh.cast_shadow = true
	mesh.receive_shadow = true
	p.add(mesh)
	return mesh


# ------------------------------------------------------------------------------------------- figures

## Maneki-neko (招き猫): calico, right paw raised, gold koban. s = height (m).
static func maneki_neko(p, K, x: float, y: float, z: float, s: float = 0.3, rot_y: float = 0.0, interior := false):
	var g = grp(p, x, y, z, rot_y)
	g.scale = Vector3.ONE * (s / 0.3)
	var f := func(c): return K.im(c, 0.3) if interior else K.m(c)
	var white = f.call("#f3efe6")
	var red = f.call("#c9463e")
	var gold = f.call("#e3bd52")
	var ink = f.call("#3a3346")
	var orange = f.call("#e2a04e")
	var pink_m = f.call("#f0a6b6")
	K.sph(g, 0.1, white, [0, 0.09, 0], 14, [1, 0.95, 0.85])
	K.sph(g, 0.085, white, [0, 0.23, 0.01], 14, [1.1, 0.95, 0.95])
	for sx in [-1, 1]:
		var e = K.cyl(g, 0.0, 0.05, white, [sx * 0.055, 0.31, 0.0], 6, [0, 0, sx * -0.3], 0.03)
		e.scale = Vector3(1, 0.06, 1)
	for sx in [-1, 1]:
		K.sph(g, 0.012, pink_m, [sx * 0.056, 0.305, 0.018], 6)
	K.sph(g, 0.03, orange, [0.045, 0.285, 0.03], 8, [1.2, 0.6, 1])
	K.sph(g, 0.03, ink, [-0.07, 0.12, 0.04], 8, [0.9, 1, 0.6])
	for sx in [-1, 1]:
		K.box(g, 0.026, 0.008, 0.01, ink, [sx * 0.033, 0.235, 0.088], [0, 0, sx * 0.25])
	K.sph(g, 0.008, pink_m, [0, 0.215, 0.093], 6)
	for sx in [-1, 1]:
		for k in 2:
			K.box(g, 0.035, 0.003, 0.003, ink, [sx * 0.07, 0.205 - k * 0.012, 0.085], [0, 0, sx * (0.12 - k * 0.2)])
	K.cyl(g, 0.078, 0.018, red, [0, 0.16, 0.012], 14)
	K.sph(g, 0.018, gold, [0, 0.145, 0.08], 8)
	K.sph(g, 0.03, white, [0.085, 0.3, 0.035], 8, [0.9, 1.4, 0.9])
	K.sph(g, 0.012, pink_m, [0.085, 0.32, 0.06], 6)
	K.box(g, 0.08, 0.1, 0.012, gold, [-0.04, 0.09, 0.09], [0, 0, 0.1])
	K.box(g, 0.05, 0.004, 0.004, f.call("#8a6a2a"), [-0.04, 0.1, 0.097], [0, 0, 0.1])
	K.sph(g, 0.028, white, [-0.06, 0.1, 0.075], 8)
	return g


## Daruma doll.
static func daruma(p, K, x: float, y: float, z: float, s: float = 0.14, rot_y: float = 0.0):
	var g = grp(p, x, y, z, rot_y)
	g.scale = Vector3.ONE * (s / 0.14)
	K.sph(g, 0.07, K.im("#c9463e", 0.3), [0, 0.068, 0], 12, [1, 1.02, 0.95])
	K.sph(g, 0.036, K.im("#f3ead8", 0.3), [0, 0.085, 0.045], 10, [1.05, 1, 0.5])
	for sx in [-1, 1]:
		K.sph(g, 0.009, K.im("#3a3346" if sx < 0 else "#f3ead8", 0.3), [sx * 0.014, 0.09, 0.062], 6)
	K.box(g, 0.05, 0.02, 0.01, K.im("#e3bd52", 0.3), [0, 0.035, 0.065])
	return g


# ------------------------------------------------------------------------------------------- counter tools

## Soroban (abacus) lying flat; long axis along local x.
static func abacus(p, K, x: float, y: float, z: float, rot_y: float = 0.0):
	var g = grp(p, x, y, z, rot_y)
	var wood = K.im("#5a3a2a", 0.28)
	var _rod = K.im("#c9b48a", 0.3)
	var L := 0.34
	var D := 0.1
	for sz in [-1, 1]:
		K.box(g, L, 0.022, 0.012, wood, [0, 0.011, sz * (D / 2.0 - 0.006)])
	for sx in [-1, 1]:
		K.box(g, 0.012, 0.022, D, wood, [sx * (L / 2.0 - 0.006), 0.011, 0])
	K.box(g, L - 0.02, 0.018, 0.008, wood, [0, 0.012, -0.018])  # beam
	var n := 13
	for i in n:
		var rx := -L / 2.0 + 0.02 + (L - 0.04) * (i + 0.5) / n
		K.I.add("cylc", g, [rx, 0.012, 0], [0.003, D - 0.02, 0.003], "#c9b48a", [PI / 2.0, 0, 0])
		var cnt := (i * 7) % 5  # a few beads pushed to the beam
		K.I.add("ball", g, [rx, 0.012, -0.034 + (0.008 if (i % 3) == 0 else 0.0)], [0.02, 0.013, 0.013], "#6a4432")
		for b in 4:
			K.I.add("ball", g, [rx, 0.012, (-0.006 if b < cnt else 0.004) + b * 0.0115], [0.02, 0.013, 0.012], "#6a4432")
	return g


## Desk calculator (flat, tilted keypad).
static func calculator(p, K, x: float, y: float, z: float, rot_y: float = 0.0):
	var g = grp(p, x, y, z, rot_y)
	var body = K.im("#e7e3da", 0.3)
	K.rbox(g, 0.12, 0.018, 0.16, 0.2, body, [0, 0.012, 0], [0.06, 0, 0])
	K.box(g, 0.1, 0.004, 0.035, K.lamp(0.85, "#b9c6b3"), [0, 0.024, -0.05], [0.06, 0, 0])
	K.box(g, 0.1, 0.004, 0.016, K.im("#3a3346", 0.1), [0, 0.024, -0.075], [0.06, 0, 0])
	for i in 4:
		for j in 5:
			K.I.add("rbox", g, [-0.036 + i * 0.024, 0.018 + j * 0.0015, -0.02 + j * 0.021], [0.018, 0.008, 0.016], "#d9463b" if j == 0 and i == 3 else ("#9aa6b3" if i == 3 else "#f4f1ea"), [0.06, 0, 0])
	return g


## Showa cash register: body, sloped key bank, flag display, drawer, crank.
static func register(p, K, x: float, y: float, z: float, rot_y: float = 0.0, o: Dictionary = {}):
	var g = grp(p, x, y, z, rot_y)
	var I = K.I
	var body = K.im(o.color if o.get("color") else "#8f9a8c", 0.24)
	var dark = K.im("#4f5358", 0.18)
	var chrome = K.im("#d3d7da", 0.36)
	var brass = K.im("#c9a45a", 0.32)
	K.box(g, 0.4, 0.11, 0.38, body, [0, 0.055, 0])  # cash drawer
	K.box(g, 0.42, 0.012, 0.4, chrome, [0, 0.114, 0])
	K.box(g, 0.3, 0.018, 0.006, dark, [0, 0.06, 0.192])
	K.cyl(g, 0.012, 0.03, brass, [0, 0.06, 0.2], 8, [PI / 2.0, 0, 0])
	K.box(g, 0.36, 0.14, 0.24, body, [0, 0.19, -0.06])  # key housing
	K.box(g, 0.34, 0.02, 0.19, dark, [0, 0.2, 0.08], [-0.55, 0, 0])  # sloped key bed
	for i in 6:
		for j in 4:
			I.add("cyl", g, [-0.14 + i * 0.056, 0.195 + 0.035 - j * 0.023, 0.14 - j * 0.037], [0.03, 0.022, 0.03], ("#d9463b" if i == 5 else "#e8c547") if j == 3 else "#f2eee4", [-0.55, 0, 0])
	K.box(g, 0.3, 0.1, 0.12, body, [0, 0.31, -0.11])  # flag display
	K.box(g, 0.31, 0.012, 0.13, chrome, [0, 0.366, -0.11])
	for s in [1, -1]:
		K.box(g, 0.25, 0.05, 0.004, K.lamp(1.0, "#f5ecd2"), [0, 0.315, -0.11 + s * 0.061])
	K.box(g, 0.14, 0.03, 0.004, brass, [0, 0.13, 0.121])  # maker plate
	K.cyl(g, 0.016, 0.08, chrome, [0.22, 0.19, -0.05], 8, [0, 0, PI / 2.0])  # crank
	K.box(g, 0.012, 0.09, 0.012, chrome, [0.265, 0.15, -0.05])
	K.sph(g, 0.018, dark, [0.265, 0.1, -0.05], 8)
	return g


## Kitchen / shop dial scale (はかり) with a round face.
static func scale(p, K, x: float, y: float, z: float, rot_y: float = 0.0):
	var g = grp(p, x, y, z, rot_y)
	var body = K.im("#e3ded2", 0.3)
	var red = K.im("#c9463e", 0.3)
	K.rbox_r(g, 0.26, 0.08, 0.24, 0.03, body, [0, 0.04, 0])
	K.cyl(g, 0.11, 0.2, body, [0, 0.18, 0.02], 20, [PI / 2.0, 0, 0])
	K.cyl(g, 0.115, 0.02, red, [0, 0.18, 0.12], 20, [PI / 2.0, 0, 0])
	var face = K.tex.draw(128, 128, null, {"key": "sb-scale-face"})
	K.plane(g, 0.19, 0.19, K.im("#ffffff", 0.35, {"map": face}), [0, 0.18, 0.132])
	K.cyl(g, 0.02, 0.06, body, [0, 0.31, 0.02], 8)
	K.cyl(g, 0.14, 0.015, K.im("#c9ccd0", 0.32), [0, 0.345, 0.02], 20)  # pan
	K.cyl(g, 0.13, 0.03, K.im("#c9ccd0", 0.32), [0, 0.36, 0.02], 20, null, 0.14)
	return g


## Retro transistor radio.
static func radio(p, K, x: float, y: float, z: float, rot_y: float = 0.0, color = "#b8423c"):
	var g = grp(p, x, y, z, rot_y)
	var body = K.im(color, 0.3)
	var cream = K.im("#efe7d4", 0.3)
	var chrome = K.im("#c9ccd0", 0.32)
	K.rbox_r(g, 0.3, 0.17, 0.09, 0.03, body, [0, 0.085, 0])
	K.rbox_r(g, 0.13, 0.12, 0.012, 0.01, cream, [-0.06, 0.085, 0.046])
	for i in 6:
		K.box(g, 0.11, 0.006, 0.006, K.im("#8e877c", 0.2), [-0.06, 0.04 + i * 0.018, 0.053])  # grille slats
	K.box(g, 0.1, 0.035, 0.006, K.im("#f5ecd2", 0.45), [0.08, 0.12, 0.046])  # tuning dial window
	K.box(g, 0.002, 0.03, 0.008, K.im("#d9463b", 0.3), [0.07, 0.12, 0.05])
	for kx in [0.055, 0.105]:
		K.cyl(g, 0.017, 0.02, chrome, [kx, 0.055, 0.05], 12, [PI / 2.0, 0, 0])
	for sx in [-0.12, 0.12]:
		K.box(g, 0.012, 0.06, 0.012, chrome, [sx, 0.2, 0])
	K.box(g, 0.25, 0.012, 0.012, chrome, [0, 0.23, 0])  # handle
	tube(g, [0.13, 0.17, -0.03], [0.02, 0.5, -0.06], 0.003, chrome, 5)  # antenna
	return g


## CRT television (ブラウン管テレビ) on a wall bracket or standing. screen faces +Z.
static func crt_tv(p, K, x: float, y: float, z: float, rot_y: float = 0.0, o: Dictionary = {}):
	var g = grp(p, x, y, z, rot_y)
	var body = K.im(o.color if o.get("color") else "#8a8f96", 0.22)
	var dark = K.im("#4f5358", 0.18)
	var glow: float = _o(o, "glow", 1.0)
	K.rbox_r(g, 0.52, 0.42, 0.34, 0.05, body, [0, 0.21, 0.02])
	K.rbox_r(g, 0.36, 0.3, 0.2, 0.06, dark, [0, 0.22, -0.2])  # tube back
	K.rbox_r(g, 0.4, 0.31, 0.02, 0.03, K.lamp(glow, o.screen if o.get("screen") else "#aac8dc"), [-0.04, 0.23, 0.19])
	K.plane(g, 0.3, 0.2, K.memo("emi", "#ffffff", {"map": tv_screen_tex(K)}, glow), [-0.04, 0.23, 0.2005])
	K.box(g, 0.07, 0.3, 0.01, dark, [0.21, 0.22, 0.19])
	for i in 3:
		K.cyl(g, 0.012, 0.02, K.im("#c9ccd0", 0.3), [0.21, 0.32 - i * 0.07, 0.2], 8, [PI / 2.0, 0, 0])
	if o.get("antenna"):
		tube(g, [0.05, 0.42, -0.05], [-0.18, 0.72, -0.1], 0.004, K.im("#c9ccd0", 0.3), 5)
		tube(g, [0.07, 0.42, -0.05], [0.28, 0.7, -0.08], 0.004, K.im("#c9ccd0", 0.3), 5)
	return g


static func tv_screen_tex(K):
	return K.tex.draw(192, 128, null, {"key": "sb-tv-screen"})


## Oscillating electric fan (扇風機). stand: floor stand, else wall mount (back at z=0).
static func fan(p, K, x: float, y: float, z: float, rot_y: float = 0.0, o: Dictionary = {}):
	var g = grp(p, x, y, z, rot_y)
	var body = K.im(o.color if o.get("color") else "#e9e5dc", 0.3)
	var blue = K.im(o.blade if o.get("blade") else "#8fc0d8", 0.35)
	var chrome = K.im("#c9ccd0", 0.32)
	var hy := 0.0
	if o.get("stand"):
		K.cyl(g, 0.17, 0.05, body, [0, 0.025, 0], 16, null, 0.19)
		K.cyl(g, 0.018, 0.8, chrome, [0, 0.45, 0], 8)
		hy = 0.9
	else:
		K.rbox_r(g, 0.12, 0.16, 0.03, 0.01, body, [0, 0, 0.015])
		K.box(g, 0.03, 0.03, 0.14, body, [0, 0, 0.09])
		hy = 0.0
	var head = grp(g, 0, hy, 0.0 if o.get("stand") else 0.16, 0)
	head.rotation.x = -0.08 if o.get("stand") else 0.25
	K.sph(head, 0.07, body, [0, 0, -0.05], 12, [1, 1, 1.3])
	K.cyl(head, 0.03, 0.05, chrome, [0, 0, 0.05], 10, [PI / 2.0, 0, 0])
	for zz in [0.03, 0.11]:
		var r := T.MeshObj.new(Geo.torus(0.19, 0.006, 4, 28), chrome)
		r.position = Vector3(0, 0, zz)
		head.add(r)
	for i in 8:
		var a := float(i) / 8 * PI
		K.box(head, 0.004, 0.37, 0.004, chrome, [0, 0, 0.115]).rotation.z = a
	K.cyl(head, 0.035, 0.012, K.im("#8fc0d8", 0.35), [0, 0, 0.118], 12, [PI / 2.0, 0, 0])
	for i in 3:
		var a := float(i) / 3 * PI * 2.0 + 0.3
		var b = K.sph(head, 0.075, blue, [cos(a) * 0.085, sin(a) * 0.085, 0.07], 10, [1, 0.62, 0.08])
		b.rotation.z = a
	return g


## Pendulum wall clock (柱時計). back at z=0, faces +Z.
static func pendulum_clock(p, K, x: float, y: float, z: float, rot_y: float = 0.0):
	var g = grp(p, x, y, z, rot_y)
	var wood = K.im("#6a4432", 0.28)
	var brass = K.im("#d1ad5c", 0.35)
	K.rbox_r(g, 0.3, 0.62, 0.1, 0.02, wood, [0, 0, 0.05])
	K.box(g, 0.34, 0.04, 0.12, wood, [0, 0.32, 0.05])
	K.box(g, 0.34, 0.04, 0.12, wood, [0, -0.32, 0.05])
	K.cyl(g, 0.115, 0.012, brass, [0, 0.14, 0.1], 20, [PI / 2.0, 0, 0])
	var face = K.tex.draw(128, 128, null, {"key": "sb-pclock-face"})
	K.plane(g, 0.2, 0.2, K.im("#ffffff", 0.35, {"map": face}), [0, 0.14, 0.108])
	var win = K.box(g, 0.17, 0.26, 0.004, K.glass({"opacity": 0.18, "streaks": false}), [0, -0.15, 0.101])
	win.cast_shadow = false
	K.ctx.no_outline(win)
	K.box(g, 0.006, 0.2, 0.006, brass, [0, -0.12, 0.08])
	K.cyl(g, 0.035, 0.008, brass, [0, -0.23, 0.08], 14, [PI / 2.0, 0, 0])
	return g


## Wall calendar: board-backed sheet on a nail (faces +Z, back at z = 0).
static func calendar(p, K, x: float, y: float, z: float, rot_y: float, texture, w: float = 0.36, h: float = 0.52):
	var g = grp(p, x, y, z, rot_y)
	K.box(g, w, h, 0.004, K.im("#e4ddcd", 0.3), [0, 0, 0.002])
	K.plane(g, w - 0.01, h - 0.01, K.im("#ffffff", 0.32, {"map": texture}), [0, 0, 0.0055])
	K.box(g, w + 0.01, 0.018, 0.01, K.im("#b8423c", 0.3), [0, h / 2.0 - 0.009, 0.006])
	K.cyl(g, 0.004, 0.02, K.im("#8d949b", 0.3), [0, h / 2.0 + 0.02, 0.01], 5, [PI / 2.0, 0, 0])
	return g


## Showa milk-glass pendant lamp (+ cord via wires). Returns bulb height.
static func pendant(S, K, x: float, y_ceil: float, y_lamp: float, z: float, o: Dictionary = {}) -> float:
	var ctx = K.ctx
	var g = S.g
	var p = S.w2(x, z)
	ctx.wires.add([[p.x, S.f.y + y_ceil, p.z], [p.x, S.f.y + y_lamp + 0.2, p.z]], {"width": 0.007, "color": "#3a3346"})
	K.cyl(g, 0.025, 0.05, K.im("#6a4432", 0.25), [x, y_lamp + 0.2, z], 10)
	if o.get("kind") == "shade":
		K.lathe(g, [[0.02, 0.2], [0.09, 0.16], [0.2, 0.02], [0.21, 0]], K.im(o.color if o.get("color") else "#e8d9b8", 0.5, {"side": "double"}), [x, y_lamp, z], 16)
	else:
		# frosted milk-glass bell with a scalloped rim
		K.lathe(g, [[0.03, 0.2], [0.07, 0.19], [0.13, 0.12], [0.17, 0.03], [0.185, 0.0], [0.17, -0.005]], K.lamp(_o(o, "glow", 1.05), o.color if o.get("color") else "#fff0d6"), [x, y_lamp, z], 18)
	K.sph(g, 0.055, K.lamp(1.6, "#fff1d4"), [x, y_lamp + 0.05, z], 10)
	if o.get("pullCord"):
		var q = S.w2(x + 0.1, z)
		ctx.wires.add([[q.x, S.f.y + y_lamp + 0.02, q.z], [q.x, S.f.y + y_lamp - 0.35, q.z]], {"width": 0.004, "color": "#e9e2d0"})
		K.sph(g, 0.012, K.im("#e9e2d0", 0.3), [x + 0.1, y_lamp - 0.36, z], 6)
	return y_lamp


# ------------------------------------------------------------------------------------------- furniture

## Round wooden stool (丸椅子) or steel stool with vinyl top (o.steel).
static func stool(p, K, x: float, y: float, z: float, o: Dictionary = {}):
	var g = grp(p, x, y, z, o.rotY if o.get("rotY") else 0.0)
	var h: float = _o(o, "h", 0.45)
	if o.get("steel"):
		var st = K.im("#b9bfc4", 0.28)
		K.cyl(g, 0.15, 0.02, st, [0, 0.01, 0], 14)
		K.cyl(g, 0.022, h - 0.07, st, [0, (h - 0.07) / 2.0 + 0.02, 0], 8)
		K.cyl(g, 0.12, 0.02, st, [0, 0.2, 0], 14)
		var ring := T.MeshObj.new(Geo.torus(0.12, 0.008, 4, 18), st)
		ring.rotation.x = PI / 2.0
		ring.position.y = 0.2
		g.add(ring)
		K.cyl(g, 0.165, 0.07, K.im(o.color if o.get("color") else "#c9463e", 0.3), [0, h - 0.035, 0], 16, null, 0.155)
		K.cyl(g, 0.155, 0.012, K.im("#e0dcd4", 0.3), [0, h - 0.074, 0], 16)
	else:
		var wood = K.im(o.color if o.get("color") else "#a57c58", 0.3, {"map": K.TX.grain})
		var dark = K.im("#6e5040", 0.26)
		K.cyl(g, 0.16, 0.04, wood, [0, h - 0.02, 0], 16)
		for i in 4:
			var a := float(i) / 4 * PI * 2.0 + PI / 4.0
			var lx := cos(a) * 0.11
			var lz := sin(a) * 0.11
			tube(g, [lx * 0.8, h - 0.04, lz * 0.8], [lx * 1.25, 0, lz * 1.25], 0.014, dark, 6)
		for i in 2:
			var a := i * PI / 2.0 + PI / 4.0
			K.box(g, 0.25, 0.018, 0.018, dark, [0, 0.16, 0]).rotation.y = a
	return g


## Zabuton cushion.
static func zabuton(p, K, x: float, y: float, z: float, rot_y: float = 0.0, color = "#8e3b56"):
	var g = grp(p, x, y, z, rot_y)
	K.rbox(g, 0.52, 0.07, 0.56, 0.3, K.im(color, 0.28), [0, 0.035, 0])
	K.box(g, 0.3, 0.004, 0.02, K.im("#e9cf8a", 0.3), [0, 0.071, 0])
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			K.sph(g, 0.012, K.im("#e9cf8a", 0.3), [sx * 0.24, 0.05, sz * 0.26], 6)
	return g


## Chabudai (round low folding table).
static func chabudai(p, K, x: float, y: float, z: float, r: float = 0.38, h: float = 0.33):
	var g = grp(p, x, y, z, 0)
	var wood = K.im("#8a5a3a", 0.3, {"map": K.TX.grain})
	var dark = K.im("#5a3a2a", 0.26)
	K.cyl(g, r, 0.03, wood, [0, h - 0.015, 0], 28)
	K.cyl(g, r + 0.006, 0.012, dark, [0, h - 0.035, 0], 28)
	for l in [[0.22, 0], [-0.22, 0], [0, 0.22], [0, -0.22]]:
		K.box(g, 0.035, h - 0.04, 0.035, dark, [l[0], (h - 0.04) / 2.0, l[1]])
	K.box(g, 0.44, 0.03, 0.03, dark, [0, h - 0.07, 0])
	K.box(g, 0.03, 0.03, 0.44, dark, [0, h - 0.07, 0])
	return g


## Kyusu (side-handle teapot) + optional cups.
static func kyusu(p, K, x: float, y: float, z: float, rot_y: float = 0.0, color = "#8a5a44"):
	var g = grp(p, x, y, z, rot_y)
	var c = K.im(color, 0.3)
	K.lathe(g, [[0, 0], [0.04, 0], [0.058, 0.02], [0.062, 0.045], [0.05, 0.075], [0.03, 0.08], [0, 0.08]], c, [0, 0, 0], 14)
	K.cyl(g, 0.034, 0.012, c, [0, 0.086, 0], 12)
	K.sph(g, 0.009, c, [0, 0.096, 0], 6)
	tube(g, [0.05, 0.035, 0], [0.095, 0.075, 0], 0.009, c, 6)  # spout (+x)
	tube(g, [0, 0.045, 0.055], [0, 0.05, 0.13], 0.012, c, 6)  # side handle (+z, 90° to spout)
	return g


static func yunomi(p, K, x: float, y: float, z: float, color = "#9fb3a8", h: float = 0.075, r: float = 0.03) -> void:
	K.I.add("tumbler", p, [x, y, z], [r * 2.0, h, r * 2.0], color)
	K.I.add("disc", p, [x, y + h - 0.012, z], [r * 1.7, 0.004, r * 1.7], "#9c7a3e")  # tea surface


## Tissue box with a tuft of tissue.
static func tissue_box(p, K, x: float, y: float, z: float, rot_y: float = 0.0, color = "#a9cfc0"):
	var g = grp(p, x, y, z, rot_y)
	K.box(g, 0.24, 0.08, 0.12, K.im("#f1ece2", 0.3), [0, 0.04, 0])
	K.box(g, 0.242, 0.03, 0.122, K.im(color, 0.3), [0, 0.025, 0])
	K.box(g, 0.1, 0.004, 0.03, K.im("#d9d4c6", 0.2), [0, 0.081, 0])
	var t = K.sph(g, 0.03, K.im("#fbf9f4", 0.4), [0, 0.1, 0], 8, [1.6, 0.9, 0.5])
	t.rotation.z = 0.25
	return g


## Stainless water pitcher.
static func pitcher(p, K, x: float, y: float, z: float, rot_y: float = 0.0):
	var g = grp(p, x, y, z, rot_y)
	var st = K.im("#c9ced3", 0.34)
	K.lathe(g, [[0, 0], [0.055, 0], [0.058, 0.01], [0.06, 0.15], [0.055, 0.2], [0.062, 0.215], [0.058, 0.215], [0, 0.2]], st, [0, 0, 0], 16)
	var h := T.MeshObj.new(Geo.torus(0.05, 0.008, 5, 12, PI), st)
	h.position = Vector3(-0.065, 0.12, 0)
	h.rotation.z = PI / 2.0
	g.add(h)
	K.box(g, 0.03, 0.01, 0.03, st, [0.065, 0.21, 0], [0, 0, -0.3])
	K.cyl(g, 0.05, 0.004, K.im("#dfeef4", 0.45), [0, 0.19, 0], 14)
	return g


## Umbrella stand with 3 umbrellas.
static func umbrella_stand(p, K, x: float, y: float, z: float):
	var g = grp(p, x, y, z, 0)
	K.cyl(g, 0.12, 0.42, K.im("#8a8f94", 0.26), [0, 0.21, 0], 14, null, 0.11)
	K.cyl(g, 0.125, 0.03, K.im("#6d747c", 0.26), [0, 0.42, 0], 14)
	var cols := ["#3f4f7e", "#c9463e", "#e9e2d0"]
	for i in cols.size():
		var c = cols[i]
		var a := i * 2.1
		var ox := cos(a) * 0.05
		var oz := sin(a) * 0.05
		var u = grp(g, ox, 0, oz, 0)
		u.rotation = Vector3(sin(a) * 0.1, 0, cos(a) * 0.1)
		K.cyl(u, 0.03, 0.55, K.im(c, 0.3), [0, 0.45, 0], 8, null, 0.012)
		K.cyl(u, 0.006, 0.2, K.im("#b8b0a0", 0.3), [0, 0.82, 0], 5)
		var hk := T.MeshObj.new(Geo.torus(0.03, 0.007, 4, 10, PI), K.im("#6a4432", 0.3))
		hk.position = Vector3(0.03, 0.92, 0)
		u.add(hk)
	return g


# ------------------------------------------------------------------------------------------- shrine shelf

## Kamidana (神棚): shelf with brackets, miniature shrine, sakaki vases, shimenawa + shide, offerings.
## Back at z = 0 (against the wall), faces +Z.
static func kamidana(p, K, x: float, y: float, z: float, rot_y: float = 0.0, w: float = 0.8):
	var g = grp(p, x, y, z, rot_y)
	var wood = K.im("#d8c19a", 0.32, {"map": K.TX.grain})
	var roof = K.im("#6d6e72", 0.2)
	var white = K.im("#f4f1ea", 0.38)
	K.box(g, w, 0.03, 0.3, wood, [0, 0, 0.15])
	for sx in [-w / 2.0 + 0.08, w / 2.0 - 0.08]:
		K.box(g, 0.03, 0.18, 0.03, wood, [sx, -0.1, 0.015])
		tube(g, [sx, -0.18, 0.02], [sx, -0.02, 0.26], 0.012, wood, 5)
	var sh = grp(g, 0, 0.015, 0.13, 0)
	K.box(sh, 0.32, 0.03, 0.18, wood, [0, 0.015, 0])  # base
	K.box(sh, 0.16, 0.16, 0.11, wood, [0, 0.11, -0.01])  # honden
	for sx in [-1, 1]:
		K.box(sh, 0.078, 0.13, 0.004, K.im("#e2cfa6", 0.34), [sx * 0.04, 0.105, 0.047])
	K.cyl(sh, 0.018, 0.004, K.im("#f0dca0", 0.5), [0, 0.12, 0.05], 12, [PI / 2.0, 0, 0])  # mirror
	for sd in [-1, 1]:
		K.box(sh, 0.22, 0.012, 0.11, roof, [0, 0.215, sd * 0.042], [sd * 0.55, 0, 0])
	K.box(sh, 0.23, 0.02, 0.02, roof, [0, 0.245, 0])
	for sx in [-0.1, 0.1]:
		K.I.add("stick", sh, [sx, 0.24, 0], [0.006, 0.05, 0.006], "#6d6e72", [0, 0, -0.5 if sx > 0 else 0.5])
	K.box(sh, 0.24, 0.02, 0.06, wood, [0, 0.035, 0.1])  # steps
	# sakaki in white vases both sides
	for sx in [-w / 2.0 + 0.13, w / 2.0 - 0.13]:
		K.I.add("tumbler", g, [sx, 0.015, 0.16], [0.045, 0.08, 0.045], "#f2efe8")
		for i in 7:
			var a := i * 0.9
			K.I.add("sph", g, [sx + cos(a) * 0.028, 0.12 + (i % 3) * 0.035, 0.16 + sin(a) * 0.022], [0.04, 0.018, 0.028], "#3f6a4a" if i % 2 else "#4f7a52", [0, a, 0.7 * cos(a)])
		K.I.add("stick", g, [sx, 0.08, 0.16], [0.006, 0.12, 0.006], "#6a5040")
	# offerings: rice, salt, water
	for e in [[-0.12, "#f4f1ea"], [0.0, "#f7f7f4"], [0.12, "#e9eef0"]]:
		K.I.add("dish", g, [e[0], 0.015, 0.265], [0.06, 0.1, 0.06], "#f2efe8")
		K.I.add("sph", g, [e[0], 0.03, 0.265], [0.03, 0.02, 0.03], e[1])
	# shimenawa rope + shide paper zig-zags
	K.cyl_x(g, 0.018, w - 0.05, K.im("#d8c38a", 0.35), [0, 0.33, 0.29], 8)
	for i in 4:
		var sx := -w * 0.3 + i * w * 0.2
		for k in 4:
			K.box(g, 0.022, 0.03, 0.003, white, [sx + (0.012 if k % 2 else -0.004), 0.3 - k * 0.028, 0.3])
	for i in 5:
		K.cyl(g, 0.006, 0.05, K.im("#d8c38a", 0.35), [-w * 0.35 + i * w * 0.175, 0.29, 0.29], 5)
	return g


# ------------------------------------------------------------------------------------------- shelving

## Open wooden shelf unit: back panel, sides, plinth, shelves at `levels` (heights of shelf tops).
## w along local x, d depth (front at +z), back at z = 0. Returns the group.
static func shelf_unit(p, K, x: float, y: float, z: float, rot_y: float, w: float, d: float, h: float, levels: Array, o: Dictionary = {}):
	var g = grp(p, x, y, z, rot_y)
	var wood = o.mat if o.get("mat") else K.im("#a57c58", 0.3, {"map": K.TX.grain})
	var dark = o.dark if o.get("dark") else K.im("#6e5040", 0.26, {"map": K.TX.grain})
	if o.get("back") != false:
		K.tbox(g, w, h, 0.02, o.backMat if o.get("backMat") else dark, [0, h / 2.0, 0.01], 1)
	for sx in [-1, 1]:
		K.tbox(g, 0.03, h, d, wood, [sx * (w / 2.0 - 0.015), h / 2.0, d / 2.0], 1)
	K.tbox(g, w, 0.08, d - 0.02, dark, [0, 0.04, d / 2.0 + 0.005], 1)
	K.tbox(g, w + 0.02, 0.03, d + 0.01, wood, [0, h - 0.015, d / 2.0], 1)
	for lv in levels:
		K.tbox(g, w - 0.06, 0.022, d - 0.02, wood, [0, lv - 0.011, d / 2.0], 1)
		if o.get("lip"):
			K.box(g, w - 0.06, 0.03, 0.01, o.lip, [0, lv + 0.004, d - 0.01])
	return g
