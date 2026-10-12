# characters/animals.js: cats (white on the W3 wall, calico curled on the ring bench, black by the V5
# bench) and sparrows (little groups on the street wires + a few hopping on the plaza). Skinned like
# the people: one mesh per animal, bones for head / ears / tail / wings, poses as functions of t.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Sk = preload("res://addons/sakuragaoka_station/world/characters/skin.gd")
const Atlas = preload("res://addons/sakuragaoka_station/world/characters/atlas.gd")
const Anim = preload("res://addons/sakuragaoka_station/world/characters/anim.gd")
const Self = preload("res://addons/sakuragaoka_station/world/characters/animals.gd")

const DEG := PI / 180.0
const S2 := 512


static func nn(v, d):
	return d if v == null else v


static func ground_height(ctx, x: float, z: float, feet_y: float) -> float:
	var Cast = load("res://addons/sakuragaoka_station/world/characters/cast.gd")
	return Cast.ground_height(ctx, x, z, feet_y)


# ------------------------------------------------------------------ cat atlas (face Q0, fur patches Q2)
## The port draws no canvases: a sized stand-in under the original's key.
static func cat_atlas(ctx, key: String, o: Dictionary):
	return ctx.tex.draw(S2, S2, null, {"key": "cat|" + key + ("|c" if o.get("closed") else "")})


static func fur_uv(u: float, v: float, ox: float = 0.0, oy: float = 0.0, sc: float = 1.0) -> Array:
	var uu := fmod(fmod(u * sc + ox, 1.0) + 1.0, 1.0)
	var vv := fmod(fmod(v * sc + oy, 1.0) + 1.0, 1.0)
	return [0.004 + uu * 0.492, 0.004 + vv * 0.492]


# ------------------------------------------------------------------ cat builder
class Cat extends RefCounted:
	var group
	var mesh
	var bn := {}
	var tail: Array = []
	var mOpen
	var mClosed
	var rest := {}
	var B
	var tris := 0.0

	func set_eyes(open: bool) -> void:
		mesh.material = mOpen if open else mClosed

	func reset() -> void:
		for b in rest:
			b.position = rest[b]
			b.quat = Quaternion.IDENTITY
			b.scale = Vector3.ONE


static func make_cat(ctx, key: String, o: Dictionary) -> Cat:
	var B = Sk.SkinBuilder.new("cat_" + key)
	var group := T.Group.new()
	group.name = "cat_" + key
	var k: float = nn(o.get("scale"), 1.0)
	var bn := {}
	bn.root = B.bone("root", null, 0, 0, 0)
	group.add(bn.root)
	var pose: String = o.pose # 'sit' | 'loaf' | 'curl'
	var tex := func(ox: float, oy: float, sc: float = 1.0) -> Callable:
		return func(_lx, _ly, _lz, u, v, _i = 0): return Self.fur_uv(u, v, ox, oy, sc)
	var add_fur := func(g: T.Geometry, bone, ox: float = 0.0, oy: float = 0.0, sc: float = 1.0, weights = null) -> void:
		B.add(g, {"bone": bone, "color": "#ffffff", "uvFn": tex.call(ox, oy, sc), "weights": weights})
	var head_pos: Array
	var tail_pts: Array
	if pose == "sit":
		bn.body = B.bone("body", bn.root, 0, 0.1 * k, 0)
		bn.chest = B.bone("chest", bn.body, 0, 0.09 * k, 0.05 * k)
		head_pos = [0.0, 0.285 * k, 0.07 * k]
		bn.neck = B.bone("neck", bn.chest, 0, head_pos[1] - 0.19 * k - 0.02 * k, head_pos[2] - 0.05 * k)
		add_fur.call(Sk.ellipsoid(0.085 * k, 0.085 * k, 0.1 * k, [0.0, -0.015 * k, -0.045 * k], 14, 9), bn.body, 0, 0, 1)            # haunches
		add_fur.call(Sk.ellipsoid(0.066 * k, 0.11 * k, 0.07 * k, [0.0, 0.045 * k, 0.0], 14, 9, func(x, y, z, _u, _v): return [x, y, z + y * 0.35]), bn.body, 0.3, 0.2)  # upright torso
		add_fur.call(Sk.ellipsoid(0.056 * k, 0.07 * k, 0.052 * k, [0.0, 0.0, 0.03 * k], 12, 8), bn.chest, 0.55, 0.5)   # chest
		for s in [1.0, -1.0]:
			add_fur.call(Sk.ellipsoid(0.038 * k, 0.062 * k, 0.07 * k, [s * 0.058 * k, -0.035 * k, -0.02 * k], 10, 7), bn.body, 0.2 + s * 0.1, 0.7)   # hind thighs
			add_fur.call(Sk.ellipsoid(0.02 * k, 0.012 * k, 0.045 * k, [s * 0.052 * k, -0.092 * k, 0.045 * k], 8, 6), bn.body, 0.1, 0.1)              # hind paws
			var fl := Sk.limb(0.17 * k, 0.019 * k, 0.015 * k, {"cols": 8})
			B.add(fl, {"bone": bn.chest, "color": "#ffffff", "uvFn": tex.call(0.6, 0.3), "matrix": Transform3D(Basis(Vector3(1, 0, 0), -0.06), Vector3(s * 0.03 * k, -0.005 * k, 0.05 * k))})
			add_fur.call(Sk.ellipsoid(0.019 * k, 0.012 * k, 0.026 * k, [s * 0.031 * k, -0.18 * k, 0.07 * k], 8, 6), bn.chest, 0.6, 0.3)
		tail_pts = nn(o.get("tail"), [[0.0, -0.09 * k, -0.13 * k], [0.06 * k, -0.095 * k, -0.12 * k], [0.1 * k, -0.095 * k, -0.04 * k], [0.09 * k, -0.095 * k, 0.05 * k], [0.05 * k, -0.09 * k, 0.1 * k]])
	elif pose == "loaf":
		bn.body = B.bone("body", bn.root, 0, 0.075 * k, 0)
		bn.chest = B.bone("chest", bn.body, 0, 0.01 * k, 0.07 * k)
		head_pos = [0.0, 0.16 * k, 0.12 * k]
		bn.neck = B.bone("neck", bn.chest, 0, head_pos[1] - 0.085 * k - 0.03 * k, head_pos[2] - 0.07 * k - 0.02 * k)
		add_fur.call(Sk.ellipsoid(0.075 * k, 0.07 * k, 0.16 * k, [0.0, 0.0, -0.02 * k], 14, 9, func(x, y, z, _u, _v): return [x, -0.04 * k + (y + 0.04 * k) * 0.3 if y < -0.04 * k else y, z]), bn.body, 0, 0, 1)
		add_fur.call(Sk.ellipsoid(0.065 * k, 0.06 * k, 0.06 * k, [0.0, 0.0, 0.03 * k], 12, 8), bn.chest, 0.5, 0.5)
		for s in [1.0, -1.0]:
			add_fur.call(Sk.ellipsoid(0.02 * k, 0.012 * k, 0.03 * k, [s * 0.03 * k, -0.065 * k, 0.075 * k], 8, 6), bn.chest, 0.6, 0.2) # tucked paws peeking
		tail_pts = nn(o.get("tail"), [[0.0, -0.02 * k, -0.17 * k], [-0.06 * k, -0.05 * k, -0.16 * k], [-0.085 * k, -0.07 * k, -0.06 * k], [-0.08 * k, -0.072 * k, 0.04 * k], [-0.055 * k, -0.072 * k, 0.1 * k]])
	else: # curl: a round "bean" seen from above, head tucked on the paws at the open side, tail wrapped round
		bn.body = B.bone("body", bn.root, 0, 0.062 * k, 0)
		bn.chest = B.bone("chest", bn.body, 0.02 * k, 0, 0.08 * k)
		head_pos = [0.075 * k, 0.07 * k, 0.15 * k]
		bn.neck = B.bone("neck", bn.chest, 0.02 * k, 0.0, 0.03 * k)
		var bean := func(x, y, z, _u, _v): return [x + 1.5 * z * z / k, -0.035 * k + (y + 0.035 * k) * 0.35 if y < -0.035 * k else y, z]
		add_fur.call(Sk.ellipsoid(0.118 * k, 0.074 * k, 0.165 * k, [-0.02 * k, 0.0, -0.01 * k], 16, 10, bean), bn.body, 0, 0, 1)            # curled back
		add_fur.call(Sk.ellipsoid(0.082 * k, 0.07 * k, 0.085 * k, [-0.045 * k, 0.008 * k, -0.095 * k], 12, 8), bn.body, 0.35, 0.6)          # haunch
		add_fur.call(Sk.ellipsoid(0.07 * k, 0.058 * k, 0.07 * k, [0.0, -0.004 * k, 0.1 * k], 12, 8), bn.body, 0.6, 0.3)                     # shoulders
		for s2 in [1.0, -1.0]:
			add_fur.call(Sk.ellipsoid(0.02 * k, 0.014 * k, 0.036 * k, [0.06 * k + s2 * 0.026 * k, -0.052 * k, 0.17 * k], 8, 6), bn.body, 0.6, 0.2) # front paws
		add_fur.call(Sk.ellipsoid(0.026 * k, 0.018 * k, 0.04 * k, [0.1 * k, -0.05 * k, -0.12 * k], 8, 6), bn.body, 0.2, 0.8)                # hind paw peeking out
		tail_pts = nn(o.get("tail"), [[-0.09 * k, -0.035 * k, -0.15 * k], [0.0, -0.03 * k, -0.2 * k], [0.12 * k, -0.03 * k, -0.155 * k], [0.185 * k, -0.03 * k, -0.02 * k], [0.17 * k, -0.03 * k, 0.1 * k], [0.12 * k, -0.028 * k, 0.19 * k]])
	# ---- head (painted face) + ears
	var nb_pos: Array = B.bind_pos(bn.neck)
	bn.head = B.bone("head", bn.neck, head_pos[0] - nb_pos[0], head_pos[1] - nb_pos[1], head_pos[2] - nb_pos[2])
	var hk2 := 1.1
	var hr := [0.058 * k * hk2, 0.05 * k * hk2, 0.052 * k * hk2]
	var hg := Sk.surface(24, 16, func(u: float, v: float) -> Array:
		var ph := (u - 0.5) * TAU
		var th := (0.5 - v) * PI
		var x: float = sin(ph) * cos(th) * hr[0]
		var y: float = sin(th) * hr[1]
		var z: float = cos(ph) * cos(th) * hr[2]
		var m := exp(-pow(ph / (28.0 * DEG), 2.0) - pow((th + 24.0 * DEG) / (20.0 * DEG), 2.0))
		z += m * 0.016 * k
		y -= m * 0.004 * k
		if y < 0.0:
			x *= 1.0 + 0.12 * cos(ph) * (1.0 + y / hr[1]) # cheek fluff
		return [x, y, z])
	var huv: T.Attr = hg.get_attribute("uv")
	for i in huv.count():
		var f := Atlas.face_uv((huv.get_x(i) - 0.5) * 360.0, (0.5 - huv.get_y(i)) * 180.0)
		huv.set_xy(i, f[0], f[1])
	B.add(hg, {"bone": bn.head, "color": "#ffffff", "rect": [0.0, 0.0, 1.0, 1.0]})
	for s in [1.0, -1.0]:
		var en := "ear" + ("L" if s > 0 else "R")
		var eb = B.bone(en, bn.head, s * 0.033 * k, 0.042 * k, -0.004 * k)
		bn[en] = eb
		var cone := func(r: float, h: float, z_off: float, col: String) -> void:
			var gg := Geo.cone(r, h, 8, 1, true)
			gg.translate(0, h / 2.0, 0)
			gg.scale(1, 1, 0.45)
			var m4 := Transform3D(Basis.from_euler(Vector3(-0.12, 0, -s * 0.32), EULER_ORDER_XYZ), Vector3(0, 0, z_off))
			B.add(gg, {"bone": eb, "color": col, "matrix": m4, "uvFn": (func(_lx, _ly, _lz, u, v, _i = 0): return Self.fur_uv(u * 0.2 + 0.4, v * 0.2 + 0.1)) if col == "#ffffff" else null})
		cone.call(0.026 * k, 0.05 * k, 0.0, "#ffffff")
		cone.call(0.017 * k, 0.036 * k, 0.006 * k, nn(o.get("earIn"), "#e9b3b8"))
	# ---- tail: sweep + a bone chain along it
	var body_bind: Array = B.bind_pos(bn.body)
	var tp := Sk.curve(tail_pts.map(func(p): return [p[0], p[1] + body_bind[1], p[2]]), 12)
	var tb: Array = []
	var nb := 5
	var parent = bn.body
	var prev: Array = body_bind
	for i in nb:
		var p: Vector3 = tp[int(T.js_round(float(i) / nb * (tp.size() - 1)))]
		var b = B.bone("tail%d" % i, parent, p.x - prev[0], p.y - prev[1], p.z - prev[2])
		tb.append(b)
		parent = b
		prev = [p.x, p.y, p.z]
	var bodyv := Vector3(body_bind[0], body_bind[1], body_bind[2])
	var tail_w: float = nn(o.get("tailW"), 0.034)
	var tg := Sk.sweep(tp.map(func(p): return p - bodyv), func(s): return tail_w * k * (1.0 - 0.45 * s) * (0.7 if s > 0.92 else 1.0), func(s): return tail_w * k * (1.0 - 0.45 * s), func(_p): return Vector3(0, 1, 0), 6)
	var tail_tip = o.get("tailTip")
	var body_bone = bn.body
	B.add(tg, {"bone": bn.body, "color": "#ffffff", "uvFn": func(_lx, _ly, _lz, u, v, _i = 0): return Self.fur_uv(v * 0.5 + 0.3, u * 0.3, 0, 0),
		"colorFn": (func(_x, _y, _z, s, _i = 0): return tail_tip if s > 0.8 else "#ffffff") if tail_tip else null,
		"weights": func(_lx, _ly, _lz, s, _i = 0) -> Array:
			var f: float = s * nb - 0.3
			var i0 := clampi(floori(f), 0, nb - 1)
			var fr := Sk.clamp_(f - i0, 0.0, 1.0)
			if f < 0.0:
				return [[body_bone, 1.0 + f], [tb[0], -f]]
			return [[tb[nb - 1], 1.0]] if i0 >= nb - 1 else [[tb[i0], 1.0 - fr], [tb[i0 + 1], fr]]})
	# ---- material
	var m_open = ctx.mat.toon("#ffffff", {"map": cat_atlas(ctx, key, o), "vertexColors": true, "side": "double", "paint": 0.03})
	var oc := o.duplicate()
	oc["closed"] = true
	var m_closed = ctx.mat.toon("#ffffff", {"map": cat_atlas(ctx, key, oc), "vertexColors": true, "side": "double", "paint": 0.03})
	var mesh = B.build(group, m_closed if o.get("startClosed") else m_open)
	var c := Cat.new()
	for b in B.bones:
		c.rest[b] = b.position
	c.group = group
	c.mesh = mesh
	c.bn = bn
	c.tail = tb
	c.mOpen = m_open
	c.mClosed = m_closed
	c.B = B
	c.tris = B.triangles()
	return c


# ------------------------------------------------------------------ sparrow
static func bird_mat(ctx):
	return ctx.mat.toon("#ffffff", {"vertexColors": true, "side": "double", "paint": 0.02})


## Adds one sparrow (bones + geometry) to the shared flock builder B; its root bone sits at p (world).
static func add_sparrow(ctx, B, flock, seed: int, p: Array) -> Dictionary:
	var r = ctx.rng(seed)
	var k: float = 0.95 + r.f() * 0.12
	var root = B.bone("bird%d" % seed, null, p[0], p[1], p[2])
	flock.add(root)
	var body = B.bone("body", root, 0, 0.035 * k, 0)
	var head = B.bone("head", body, 0, 0.028 * k, 0.03 * k)
	var tail = B.bone("tail", body, 0, 0.004 * k, -0.04 * k)
	var wL = B.bone("wingL", body, 0.024 * k, 0.012 * k, 0.012 * k)
	var wR = B.bone("wingR", body, -0.024 * k, 0.012 * k, 0.012 * k)
	var brown := "#8f6a50"
	var cream := "#e7dccb"
	var chest := "#cfc2b0"
	var cap := "#86573f"
	var dark := "#4a3f45"
	var white := "#eeebe6"
	B.add(Sk.ellipsoid(0.03 * k, 0.029 * k, 0.047 * k, [0.0, 0.0, 0.0], 10, 7, func(x, y, z, _u, _v): return [x, y, z + y * 0.35]),
		{"bone": body, "colorFn": func(_x, y, _z, _s = 0.0, _i = 0): return (cream if y < -0.016 * k else chest) if y < -0.004 * k else brown})
	B.add(Sk.ellipsoid(0.023 * k, 0.022 * k, 0.024 * k, [0.0, 0.004 * k, 0.004 * k], 10, 7), {"bone": head, "colorFn": func(x, y, z, _s = 0.0, _i = 0):
		if y > 0.012 * k:
			return cap
		if absf(x) > 0.016 * k and y > -0.006 * k and y < 0.008 * k:
			return dark if z > 0.004 * k and z < 0.016 * k else white # cheek + spot
		if z > 0.014 * k and y < -0.002 * k and absf(x) < 0.012 * k:
			return dark # bib
		if absf(x) > 0.014 * k and y >= 0.004 * k:
			return cap
		return white if y > -0.01 * k else chest})
	# eye beads
	for s in [1.0, -1.0]:
		B.add(Sk.ellipsoid(0.0042 * k, 0.0046 * k, 0.003 * k, [s * 0.019 * k, 0.009 * k, 0.012 * k], 6, 4), {"bone": head, "color": "#3a3346"})
	var beak := Geo.cone(0.0065 * k, 0.014 * k, 6)
	beak.rotate_x(PI / 2.0)
	B.add(beak, {"bone": head, "color": "#4f4448", "matrix": Transform3D(Basis(), Vector3(0, 0.002 * k, 0.028 * k))})
	B.add(Sk.ellipsoid(0.013 * k, 0.004 * k, 0.03 * k, [0.0, 0.0, -0.022 * k], 8, 5, func(x, y, z, _u, _v): return [x * (1.0 + maxf(0.0, -z) * 18.0), y, z]), {"bone": tail, "color": "#6e5646"})
	for sw in [[1.0, wL], [-1.0, wR]]:
		var s: float = sw[0]
		B.add(Sk.ellipsoid(0.008 * k, 0.019 * k, 0.04 * k, [s * 0.002 * k, 0.0, -0.014 * k], 8, 6, func(x, y, z, _u, _v): return [x, y, z]),
			{"bone": sw[1], "colorFn": func(_x, y, z, _s = 0.0, _i = 0): return "#5f4a40" if z < -0.03 * k else ("#e2d6c6" if absf(y) < 0.004 * k else "#7e5d48")})
	for s in [1.0, -1.0]:
		B.add(Sk.limb(0.028 * k, 0.0022 * k, 0.002 * k, {"cols": 4}), {"bone": root, "color": "#b58d7c", "matrix": Transform3D(Basis(), Vector3(s * 0.008 * k, 0.028 * k, 0.002 * k))})
	return {"group": root, "root": root, "body": body, "head": head, "tail": tail, "wL": wL, "wR": wR}


# ------------------------------------------------------------------ assembly
static func make_animals(ctx) -> Array:
	var L = ctx.L
	var S: Dictionary = L.SPOTS
	var actors: Array = []
	var player = ctx.player.get("position") if ctx.player is Dictionary else null
	var add_c := func(c: Cat) -> Cat:
		ctx.add(c.group)
		return c

	# ---- white cat: loafing along the W3 wall top, head turned to the street
	if true:
		var sp: Dictionary = S.catWhite
		var y: float = L.height_at(sp.x, sp.z) + S.w3Wall.h
		var c: Cat = add_c.call(make_cat(ctx, "white", {"pose": "loaf", "scale": 1.0, "fur": "#eeebe6", "eye": "#9cc3e4", "eyeDark": "#5f86b3", "ink": "#4a4250", "nose": "#e7a3ab", "earIn": "#ecb8bd", "muzzle": "#f4f1ed",
			"tail": [[0.0, -0.02, -0.17], [-0.06, -0.035, -0.2], [-0.115, -0.1, -0.2], [-0.13, -0.22, -0.18], [-0.13, -0.31, -0.13], [-0.12, -0.34, -0.08]]}))
		var rot_y := PI # body along the wall (north), street is to its right (+X world)
		ctx.physics.addCylinder(sp.x, sp.z, 0.12, y, y + 0.3)
		actors.append({"h": c, "update": func(t: float, _dt: float) -> void:
			c.reset()
			c.group.position = Vector3(sp.x, y, sp.z)
			c.group.set_rotation(0, rot_y, 0)
			var cyc := fmod(t, 17.0)
			# slow head turn: street -> station -> street, eyes half-closed now and then
			var look := Sk.lerp_(-1.25, -0.2, Sk.smooth(6, 8.5, cyc) * (1.0 - Sk.smooth(12, 14.5, cyc)))
			var yaw := look + 0.08 * sin(t * 0.5)
			if player != null and Vector3(player.x - sp.x, 0, player.z - sp.z).length() < 4.0:
				var a: float = atan2(player.x - sp.x, player.z - sp.z) - rot_y
				yaw = Sk.clamp_(atan2(sin(a), cos(a)), -1.4, 1.4)
			Anim.rot(c.bn.neck, 0.05, yaw * 0.4, 0)
			Anim.rot(c.bn.head, -0.06 + 0.04 * sin(t * 0.3), yaw * 0.6, 0.08 * sin(t * 0.21))
			c.bn.body.scale = Vector3(1.0 + 0.018 * sin(t * 2.4), 1.0 + 0.025 * sin(t * 2.4), 1.0)
			Self.ear_flick(c, t, 1.3)
			# tail tip swish hanging down the wall face
			for i in c.tail.size():
				Anim.rot(c.tail[i], 0.14 * sin(t * 1.3 - i * 0.6) * (float(i) / c.tail.size()), 0, 0)
			c.set_eyes(fmod(t + 1.1, 5.3) > 0.14 and not (cyc > 9 and cyc < 10.2))})

	# ---- calico: curled up asleep on the ring bench
	if true:
		var sp: Dictionary = S.calicoCat
		var y: float = nn(sp.get("y"), S.plazaBenchSeatY)
		var c: Cat = add_c.call(make_cat(ctx, "calico", {"pose": "curl", "scale": 1.0, "fur": "#efe9e1", "eye": "#d9b55e", "eyeDark": "#a07d3c", "ink": "#4a4250", "nose": "#e7a3ab", "earIn": "#ecb8bd",
			"patches": [["#d98d4f", 5, 34], ["#4e4652", 4, 26]], "facePatch": "#d98d4f", "facePatch2": "#4e4652", "startClosed": true}))
		ctx.physics.addCylinder(sp.x, sp.z, 0.16, y, y + 0.5)
		actors.append({"h": c, "update": func(t: float, _dt: float) -> void:
			c.reset()
			c.group.position = Vector3(sp.x, y + 0.004, sp.z)
			c.group.set_rotation(0, sp.rotY, 0)
			var cyc := fmod(t, 26.0)
			var up := Sk.smooth(15, 16.5, cyc) * (1.0 - Sk.smooth(21, 22.5, cyc))      # lifts her head, looks around
			c.bn.body.scale = Vector3(1.0 + 0.03 * sin(t * 1.9), 1.0 + 0.04 * sin(t * 1.9), 1.0)
			Anim.rot(c.bn.neck, -0.3 * up, 0.35 * (1.0 - up) + 0.2 * up, 0.15 * (1.0 - up))
			Anim.rot(c.bn.head, 0.32 * (1.0 - up) - 0.2 * up, 0.25 * (1.0 - up) + (0.6 * sin((cyc - 16.0) * 0.7)) * up, 0.35 * (1.0 - up))
			Self.ear_flick(c, t, 2.1)
			for i in c.tail.size():
				Anim.rot(c.tail[i], 0, 0.05 * sin(t * 0.8 - i * 0.7) * (float(i) / c.tail.size()) + (0.15 * maxf(0.0, sin(t * 0.37)) if i == c.tail.size() - 1 else 0.0), 0)
			c.set_eyes(up > 0.6 and fmod(t, 3.7) > 0.15)})

	# ---- black cat: sitting on the ground by the V5 bench, tail wrapped, tip twitching
	if true:
		var sp: Dictionary = S.blackCat
		var y: float = ground_height(ctx, sp.x, sp.z, L.height_at(sp.x, sp.z) + 0.2)
		var c: Cat = add_c.call(make_cat(ctx, "black", {"pose": "sit", "scale": 1.02, "fur": "#4b4757", "eye": "#d8cf6a", "eyeDark": "#8d9a3c", "ink": "#3a3346", "nose": "#8f6f7c", "earIn": "#8d7584", "muzzle": "#56515f", "pupil": 2.6}))
		ctx.physics.addCylinder(sp.x, sp.z, 0.14, y, y + 0.5)
		actors.append({"h": c, "update": func(t: float, _dt: float) -> void:
			c.reset()
			c.group.position = Vector3(sp.x, y, sp.z)
			c.group.set_rotation(0, sp.rotY, 0)
			var cyc := fmod(t, 19.0)
			var yaw := 0.7 * sin(t * 0.17) * Sk.smooth(3, 6, cyc) + 0.9 * (Sk.smooth(11, 12, cyc) * (1.0 - Sk.smooth(15, 16.5, cyc)))
			if player != null and Vector3(player.x - sp.x, 0, player.z - sp.z).length() < 4.5:
				var a: float = atan2(player.x - sp.x, player.z - sp.z) - sp.rotY
				yaw = Sk.clamp_(atan2(sin(a), cos(a)), -1.4, 1.4)
			Anim.rot(c.bn.neck, 0, yaw * 0.35, 0)
			Anim.rot(c.bn.head, -0.1 + 0.05 * sin(t * 0.4), yaw * 0.65, 0.1 * sin(t * 0.23))
			Anim.rot(c.bn.chest, 0.02 * sin(t * 2.3), 0, 0)
			Self.ear_flick(c, t, 0.7)
			for i in c.tail.size():
				Anim.rot(c.tail[i], 0, (0.1 + 0.18 * (float(i) / c.tail.size())) * sin(t * 1.7 - i * 0.8) * (1.0 if i > 1 else 0.3), 0)
			c.set_eyes(fmod(t + 2.3, 4.1) > 0.14)})

	# ---- sparrows: the whole flock is ONE skinned mesh (one draw call), one little bone rig per bird
	var spans := pick_spans(ctx)
	var birds: Array = []
	var FB = Sk.SkinBuilder.new("sparrows")
	var flock := T.Group.new()
	flock.name = "sparrows"
	var seed := 400
	for grp in spans:
		for p in grp.perches:
			var b := add_sparrow(ctx, FB, flock, seed, [p.x, p.y, p.z])
			seed += 1
			var it := {"b": b, "kind": "wire"}
			it.merge(p, true)
			it["seed"] = seed
			birds.append(it)
	# ground birds on the plaza (pecking between the tree bench and the bike racks)
	var home := [[1.6, -8.6], [2.2, -9.3], [1.1, -9.6]]
	for hxz in home:
		var hx: float = hxz[0]
		var hz: float = hxz[1]
		var gy: float = ground_height(ctx, hx, hz, L.height_at(hx, hz) + 0.2)
		var b := add_sparrow(ctx, FB, flock, seed, [hx, gy, hz])
		seed += 1
		birds.append({"b": b, "kind": "ground", "x": hx, "z": hz, "y": gy, "seed": seed})
	if birds.size():
		var fm = FB.build(flock, bird_mat(ctx))
		fm.cast_shadow = false
		ctx.add(flock)
		for it in birds:
			it.b.body.user_data["restY"] = it.b.body.position.y
		actors.append({"h": null, "update": func(t: float, _dt: float) -> void:
			for it in birds:
				Self.bird_update(ctx, it, t)})
	return actors


static func ear_flick(c: Cat, t: float, seed: float) -> void:
	var cyc := fmod(t + seed * 3.3, 4.5 + seed)
	var f := sin(cyc / 0.25 * PI) if cyc < 0.25 else 0.0
	Anim.rot(c.bn.earL, -0.5 * f, 0, 0.4 * f)
	var cyc2 := fmod(t + seed * 1.7, 6.1 + seed * 0.5)
	var f2 := sin(cyc2 / 0.22 * PI) if cyc2 < 0.22 else 0.0
	Anim.rot(c.bn.earR, -0.4 * f2, 0, -0.35 * f2)


## Choose wire spans visible from the hero view and the plaza; place little groups of perches.
static func pick_spans(ctx) -> Array:
	var L = ctx.L
	var spans: Array = []
	var poles = ctx.services.get("poles")
	if poles != null and poles.get("spans") != null:
		for s in poles.spans:
			var p = s.get("points")
			if p and p.size() > 2:
				spans.append(p)
	var fallback := false
	if spans.is_empty():
		fallback = true
		for run in L.POLE_RUNS.values():
			for i in range(1, run.size()):
				var a: Dictionary = run[i - 1]
				var b: Dictionary = run[i]
				spans.append(ctx.geo.catenary([a.x, L.height_at(a.x, a.z) + 7.5, a.z], [b.x, L.height_at(b.x, b.z) + 7.5, b.z], 0.35, 16))
	# desired sites (x, z) in priority order and group sizes
	var sites := [
		{"x": -3.4, "z": 16.0, "n": 4},   # west side of the main street, above the flower shop (hero view)
		{"x": 3.4, "z": 30.0, "n": 3},    # east side near the hero camera
		{"x": -2.0, "z": 1.45, "n": 4},   # cross street R3, right at the end of the main street (hero view + plaza)
		{"x": 16.0, "z": 1.45, "n": 3},   # R3 east, seen from the plaza
	]
	var r = ctx.rng("sparrows")
	var out: Array = []
	var used := {}
	for site in sites:
		var best = null
		for si in spans.size():
			if used.has(si):
				continue
			var pts: Array = spans[si]
			for i in range(1, pts.size()):
				var a: Vector3 = pts[i - 1]
				var b: Vector3 = pts[i]
				var len := a.distance_to(b)
				if len < 0.2:
					continue
				var slope := absf(b.y - a.y) / len
				if slope > 0.12 or a.y < 4.5 or a.y > 10.5:
					continue
				var mx := (a.x + b.x) / 2.0
				var mz := (a.z + b.z) / 2.0
				var d := Sk.hypot(mx - site.x, mz - site.z) + slope * 4.0 - a.y * 0.05
				if best == null or d < best.d:
					best = {"d": d, "si": si, "i": i, "pts": pts}
		if best == null or best.d > 9:
			continue
		used[best.si] = true
		# walk along the span from the chosen segment, spacing 0.13..0.26 m
		var pts: Array = best.pts
		var perches: Array = []
		var lens: Array = [0.0]
		for i in range(1, pts.size()):
			lens.append(lens[i - 1] + (pts[i] as Vector3).distance_to(pts[i - 1]))
		var total: float = lens[lens.size() - 1]
		var s := Sk.clamp_(lens[best.i - 1] + r.f() * 0.5, 0.8, total - 2.5)
		var facing := 1 if r.f() < 0.5 else -1
		for j in site.n:
			var at := sample_at(pts, lens, s)
			var pp: Vector3 = at.p
			var tt: Vector3 = at.t
			perches.append({"x": pp.x, "y": pp.y, "z": pp.z, "tx": tt.x, "tz": tt.z, "face": facing if r.f() < 0.8 else -facing, "span": pts, "lens": lens, "s": s})
			s += 0.13 + r.f() * 0.14
		if fallback:
			ctx.wires.add(pts, {"width": 0.012, "color": "#3a3640"})
		out.append({"perches": perches})
	return out


static func sample_at(pts: Array, lens: Array, s: float) -> Dictionary:
	var i := 1
	while i < pts.size() - 1 and lens[i] < s:
		i += 1
	var f := Sk.clamp_((s - lens[i - 1]) / maxf(1e-6, lens[i] - lens[i - 1]), 0.0, 1.0)
	var p: Vector3 = (pts[i - 1] as Vector3).lerp(pts[i], f)
	var t: Vector3 = ((pts[i] as Vector3) - pts[i - 1]).normalized()
	return {"p": p, "t": t}


## Bird behaviour (pure function of t + per-bird seed).
static func bird_update(_ctx, it: Dictionary, t: float) -> void:
	var b: Dictionary = it.b
	var sd: float = it.seed * 1.618
	for n in ["root", "body", "head", "tail", "wL", "wR"]:
		b[n].quat = Quaternion.IDENTITY
	b.body.position = Vector3(0, b.body.user_data.restY, 0)
	b.body.scale = Vector3.ONE
	# head: quick jerky turns held for a moment
	var slot := floorf(t / 0.9 + sd)
	var fr := (t / 0.9 + sd) - slot
	var hr := func(n: float) -> float:
		var x := sin(n * 12.9898 + sd * 78.233) * 43758.5453
		return x - floorf(x)
	var yaw0: float = (hr.call(slot - 1) - 0.5) * 2.2
	var yaw1: float = (hr.call(slot) - 0.5) * 2.2
	var hy := Sk.lerp_(yaw0, yaw1, Sk.smooth(0, 0.12, fr))
	var pitch: float = (hr.call(slot + 100) - 0.5) * 0.5
	if it.kind == "wire":
		var cyc := fmod(t + sd * 7.0, 11.0)
		# a short hop along the wire now and then (returns later)
		var hop_a := Sk.smooth(5.0, 5.35, cyc)
		var hop_b := Sk.smooth(8.8, 9.15, cyc)
		var off := (hop_a - hop_b) * 0.07 * (1.0 if it.face > 0 else -1.0)
		var air := sin(Sk.clamp_((cyc - 5.0) / 0.35, 0.0, 1.0) * PI) + sin(Sk.clamp_((cyc - 8.8) / 0.35, 0.0, 1.0) * PI)
		var at := sample_at(it.span, it.lens, it.s + off)
		var ap: Vector3 = at.p
		var atv: Vector3 = at.t
		b.root.position = Vector3(ap.x, ap.y + air * 0.05 + 0.001, ap.z)
		var fx: float = -atv.z * it.face
		var fz: float = atv.x * it.face
		Anim.rot(b.root, 0, atan2(fx, fz), 0)
		# flutter while hopping, fluff / preen occasionally
		var flap := sin(t * 60.0) * 0.9 * air if air > 0.01 else 0.0
		Anim.rot(b.wL, 0, 0, 0.1 + flap)
		Anim.rot(b.wR, 0, 0, -0.1 - flap)
		var preen := Sk.smooth(2, 2.2, cyc) * (1.0 - Sk.smooth(3.2, 3.4, cyc))
		Anim.rot(b.head, pitch + preen * 0.9, hy * (1.0 - preen) + preen * 1.9, preen * 0.4)
		Anim.rot(b.tail, 0.25 * maxf(0.0, sin(t * 7.0 + sd)) * (1.0 if hr.call(slot + 7) > 0.7 else 0.1), 0, 0)
		var sc := 1.0 + 0.08 * Sk.smooth(6.2, 6.5, cyc) * (1.0 - Sk.smooth(7.2, 7.6, cyc))
		b.body.scale = Vector3(sc, sc, sc)
	else:
		# ground: hop to random nearby points, peck
		var TT := 1.4
		var n := floorf(t / TT + sd)
		var f := (t / TT + sd) - n
		var pt := func(m: float) -> Array: return [it.x + (hr.call(m) - 0.5) * 1.1, it.z + (hr.call(m + 50) - 0.5) * 0.9]
		var p0: Array = pt.call(n)
		var p1: Array = pt.call(n + 1)
		var hop := Sk.smooth(0.0, 0.25, f)
		var x := Sk.lerp_(p0[0], p1[0], hop)
		var z := Sk.lerp_(p0[1], p1[1], hop)
		var air := sin(Sk.clamp_(f / 0.25, 0.0, 1.0) * PI) * 0.035
		b.root.position = Vector3(x, it.y + air, z)
		var dir := atan2(p1[0] - p0[0], p1[1] - p0[1])
		Anim.rot(b.root, 0, dir + ((hr.call(n + 9) - 0.5) * 1.2 if f > 0.3 else 0.0), 0)
		var peck := maxf(0.0, sin((f - 0.45) / 0.5 * PI * 3.0)) if f > 0.45 and f < 0.95 else 0.0
		Anim.rot(b.body, 0.35 * peck, 0, 0)
		Anim.rot(b.head, 0.9 * peck + (1.0 - peck) * pitch, (1.0 - peck) * hy * 0.7, 0)
		var flap := sin(t * 50.0) * 0.5 if f < 0.25 else 0.0
		Anim.rot(b.wL, 0, 0, 0.1 + flap)
		Anim.rot(b.wR, 0, 0, -0.1 - flap)
		Anim.rot(b.tail, 0.3 * (1.0 - peck) * (1.0 if f < 0.3 else 0.2), 0, 0)
