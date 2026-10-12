# characters/gear.js: accessories and hand-held props, merged into each character's skinned mesh
# (bone-local geometry).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Sk = preload("res://addons/sakuragaoka_station/world/characters/skin.gd")
const Hm = preload("res://addons/sakuragaoka_station/world/characters/human.gd")

const DEG := PI / 180.0


static func TR(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


static func ROT(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(x, y, z), EULER_ORDER_XYZ), Vector3.ZERO)


## Matrix4.setPosition
static func at(m: Transform3D, x: float, y: float, z: float) -> Transform3D:
	m.origin = Vector3(x, y, z)
	return m


static func nn(v, d):
	return d if v == null else v


static func orr(v, d):
	return v if Hm.truthy(v) else d


## Japanese railway staff cap (制帽): flat flared crown, dark band, glossy visor, gold badge + cord.
static func staff_cap(h, o: Dictionary = {}) -> void:
	var hd: Dictionary = h.P.head
	var k: float = h.P.k * h.P.hk
	var bone = h.b.head
	var y0: float = hd.cy + hd.ry * 0.3
	var z0: float = hd.cz - 0.006 * k
	var a: float = hd.rx * 1.1
	var b: float = hd.rz * 1.13
	var m := at(ROT(-0.12, 0, 0), 0, y0, z0)
	var cap := Sk.rings([{"y": -0.004, "a": a * 0.97, "b": b * 0.97}, {"y": 0.0, "a": a, "b": b}, {"y": 0.034 * k, "a": a * 1.01, "b": b * 1.01}, {"y": 0.062 * k, "a": a * 1.16, "b": b * 1.14, "z": 0.006 * k},
		{"y": 0.078 * k, "a": a * 1.17, "b": b * 1.15, "z": 0.008 * k}, {"y": 0.084 * k, "a": a * 1.08, "b": b * 1.06, "z": 0.008 * k}, {"y": 0.086 * k, "a": 0.0, "b": 0.0, "z": 0.008 * k}], 22)
	h.add(cap, {"bone": bone, "color": orr(o.get("color"), "#3d4866"), "matrix": m})
	var band := Sk.rings([{"y": 0.001, "a": a * 1.006, "b": b * 1.006}, {"y": 0.03 * k, "a": a * 1.016, "b": b * 1.016}], 22)
	h.add(band, {"bone": bone, "color": orr(o.get("band"), "#343c56"), "matrix": m})
	# visor: half disc tilted down
	var vis := Sk.surface(12, 3, func(u: float, v: float) -> Array:
		var ph := Sk.lerp_(-80, 80, u) * DEG
		var r := Sk.lerp_(0.0, 1, v)
		var x := sin(ph) * a * 1.02
		var z := cos(ph) * b * 1.02
		var x2 := sin(ph) * a * 1.05
		var z2 := cos(ph) * (b + 0.055 * k)
		return [Sk.lerp_(x, x2, r), -0.004 * k - r * r * 0.018 * k, Sk.lerp_(z, z2, r)])
	h.add(vis, {"bone": bone, "color": orr(o.get("visor"), "#2f3446"), "matrix": m})
	# badge + cord
	var mb := m * TR(0, 0.045 * k, b * 1.14)
	h.add(Sk.ellipsoid(0.013 * k, 0.012 * k, 0.004 * k, [0.0, 0.0, 0.0], 8, 6), {"bone": bone, "color": orr(o.get("badge"), "#d9b45a"), "matrix": mb})
	h.add(Sk.ellipsoid(0.018 * k, 0.005 * k, 0.003 * k, [0.0, 0.0, 0.0], 8, 4), {"bone": bone, "color": orr(o.get("badge"), "#d9b45a"), "matrix": mb * TR(0, -0.012 * k, 0.001)})
	var cord: Array = []
	for i in 9:
		var ph := Sk.lerp_(-62, 62, i / 8.0) * DEG
		cord.append(Vector3(sin(ph) * a * 1.03, 0.012 * k, cos(ph) * b * 1.03))
	h.add(Sk.sweep(cord, func(_s): return 0.004 * k, func(_s): return 0.004 * k, func(p): return Vector3(p.x, 0, p.z).normalized(), 4), {"bone": bone, "color": orr(o.get("badge"), "#d9b45a"), "matrix": m})


## Round thin glasses.
static func glasses(h, o: Dictionary = {}) -> void:
	var k: float = h.P.k * h.P.hk
	var bone = h.b.head
	var f: Dictionary = h.spec.face
	var col = orr(o.get("color"), "#6b5a57")
	for s in [1.0, -1.0]:
		var p: Array = h.head_pt(s * f.eyeP * DEG, (f.eyeT + 1) * DEG, 1.07)
		var ring: Array = []
		for i in 15:
			var a := i / 14.0 * TAU
			ring.append(Vector3(p[0] + cos(a) * 0.019 * k, p[1] + sin(a) * 0.016 * k, p[2] + 0.004 * k - absf(cos(a)) * 0.004 * k * s * 0.0))
		h.add(Sk.sweep(ring, func(_s): return 0.0028 * k, func(_s): return 0.0028 * k, func(_p): return Vector3(0, 0, 1), 4), {"bone": bone, "color": col})
		# temple arm to the ear
		var e: Array = h.head_pt(s * 92 * DEG, (f.eyeT + 4) * DEG, 1.03)
		h.add(Sk.sweep([Vector3(p[0] + s * 0.019 * k, p[1] + 0.004 * k, p[2]), Vector3(e[0], e[1], e[2])], func(_s): return 0.0025 * k, func(_s): return 0.0025 * k, func(_p): return Vector3(0, 1, 0), 4), {"bone": bone, "color": col})
	var pl: Array = h.head_pt(-(f.eyeP - 11) * DEG, (f.eyeT + 3) * DEG, 1.08)
	var pr: Array = h.head_pt((f.eyeP - 11) * DEG, (f.eyeT + 3) * DEG, 1.08)
	h.add(Sk.sweep(Sk.curve([pl, [0.0, (pl[1] + pr[1]) / 2.0 + 0.004 * k, pl[2] + 0.004 * k], pr], 5), func(_s): return 0.0025 * k, func(_s): return 0.0025 * k, func(_p): return Vector3(0, 1, 0), 4), {"bone": bone, "color": col})


## Hair clip / ribbon accessory at head angles.
static func hair_clip(h, ph_deg: float, th_deg: float, color) -> void:
	var k: float = h.P.k * h.P.hk
	var p: Array = h.head_pt(ph_deg * DEG, th_deg * DEG, 1.1)
	h.add(Sk.rbox(0.012 * k, 0.03 * k, 0.008 * k, 0, [0.0, 0.0, 0.0]), {"bone": h.b.head, "color": color, "matrix": at(ROT(0, ph_deg * DEG, 0.6), p[0], p[1], p[2])})


## School shoulder bag: strap from the right shoulder across the chest, bag at the left hip.
static func shoulder_bag(h, o: Dictionary = {}) -> void:
	var P: Dictionary = h.P
	var k: float = P.k
	var b: Dictionary = h.b
	var sp_y: float = h.bind_pos(b.spine)[1]
	var tp := func(ph: float, y: float, off: float) -> Vector3:
		var p: Array = h.torso_pt(P.outer, ph * DEG, y, off)
		return Vector3(p[0], p[1] - sp_y, p[2])
	var col = orr(o.get("color"), "#434b66")
	var pts := [tp.call(-50, P.shY + 0.02 * k, 0.02 * k), tp.call(-28, P.chest + 0.06 * k, 0.024 * k), tp.call(0, P.chest - 0.03 * k, 0.026 * k), tp.call(40, P.waist, 0.026 * k), tp.call(80, P.waist - 0.08 * k, 0.03 * k)]
	var back := [tp.call(-50, P.shY + 0.02 * k, 0.02 * k), tp.call(-130, P.chest + 0.04 * k, 0.022 * k), tp.call(-180, P.chest - 0.05 * k, 0.024 * k), tp.call(-230, P.waist, 0.026 * k), tp.call(-280, P.waist - 0.08 * k, 0.03 * k)]
	for line in [pts, back]:
		h.add(Sk.sweep(Sk.curve(line, 12), func(_s): return 0.03 * k, func(_s): return 0.004 * k, func(p): return Vector3(p.x, 0, p.z).normalized(), 4), {"bone": b.spine, "color": orr(o.get("strap"), col), "weights": h.torso_weights()})
	# bag at the left hip (hips bone)
	var hy: float = P.waist - 0.13 * k - P.hip
	var x: float = (P.pelvis[1][1] + 0.05) * 1.05
	var m := at(ROT(0.04, 1.35, 0.06), x, hy, -0.01 * k)
	h.add(Sk.rbox(0.32 * k, 0.24 * k, 0.085 * k, 0, [0.0, 0.0, 0.0]), {"bone": b.hips, "color": col, "matrix": m})
	h.add(Sk.rbox(0.3 * k, 0.1 * k, 0.09 * k, 0, [0.0, 0.075 * k, 0.004 * k]), {"bone": b.hips, "color": orr(o.get("flap"), "#3c4460"), "matrix": m})
	if Hm.truthy(o.get("charm")):
		h.add(Sk.ellipsoid(0.016 * k, 0.018 * k, 0.012 * k, [0.1 * k, -0.02 * k, 0.05 * k], 8, 6), {"bone": b.hips, "color": o.charm, "matrix": m})


## Bag hanging from a hand (tote, eco bag, paper bag, briefcase).
static func hand_bag(h, side: String, o: Dictionary) -> void:
	var k: float = h.P.k
	var bone = h.b["hand" + side]
	var w: float = o.w * k
	var hh: float = o.h * k
	var d: float = o.d * k
	var drop: float = nn(o.get("drop"), 0.08) * k
	var c := [0.0, -0.05 * k - drop - hh / 2.0, 0.01 * k]
	var m := at(ROT(0, nn(o.get("yaw"), PI / 2.0), 0), c[0], c[1], c[2])
	h.add(Sk.rbox(w, hh, d, 0, [0.0, 0.0, 0.0]), {"bone": bone, "color": o.color, "matrix": m})
	if Hm.truthy(o.get("band")):
		h.add(Sk.rbox(w * 1.01, hh * 0.18, d * 1.02, 0, [0.0, hh * 0.28, 0.0]), {"bone": bone, "color": o.band, "matrix": m})
	# handles: two arcs up to the hand
	if o.get("handles") != false:
		for s in [1.0, -1.0]:
			var pts := Sk.curve([[s * w * 0.22, hh / 2.0 - 0.004, 0.0], [s * w * 0.12, hh / 2.0 + drop * 0.7, 0.0], [0.0, hh / 2.0 + drop + 0.035 * k, 0.0]], 6)
			var hw: float = nn(o.get("handleW"), 0.012)
			h.add(Sk.sweep(pts, func(_s): return hw * k, func(_s): return 0.005 * k, func(_p): return Vector3(0, 0, 1), 4), {"bone": bone, "color": orr(o.get("handle"), o.color), "matrix": m})
	if Hm.truthy(o.get("leek")):
		var lm := m * at(ROT(0, 0, -0.32), w * 0.18, hh * 0.3, 0)
		h.add(Sk.limb(0.28 * k, 0.014 * k, 0.013 * k, {"cols": 8, "capTop": 0.4, "capBottom": 0.6}), {"bone": bone, "color": "#eeeadb", "matrix": lm * TR(0, 0.1 * k, 0)})
		for i in 3:
			h.add(Sk.limb(0.22 * k, 0.012 * k, 0.004 * k, {"cols": 6, "capTop": 0.3}), {"bone": bone, "color": "#7fa55a" if i else "#8fb867", "matrix": lm * at(ROT(PI + (i - 1) * 0.16, 0, (i - 1) * 0.12), 0, 0.1 * k, 0)})
	if Hm.truthy(o.get("greens")):
		h.add(Sk.ellipsoid(w * 0.35, 0.05 * k, d * 0.35, [-w * 0.15, hh / 2.0 + 0.02 * k, 0.0], 8, 6), {"bone": bone, "color": o.greens, "matrix": m})
	if Hm.truthy(o.get("logo")):
		h.add(Sk.rbox(w * 0.4, hh * 0.3, d * 1.04, 0, [0.0, -hh * 0.05, 0.0]), {"bone": bone, "color": o.logo, "matrix": m})


## Smartphone in the hand.
static func phone(h, side: String, color = "#5c6a86") -> void:
	var k: float = h.P.k
	var bone = h.b["hand" + side]
	var m := at(ROT(0.2, 0, 0), 0, -0.06 * k, 0.03 * k)
	h.add(Sk.rbox(0.012 * k, 0.13 * k, 0.065 * k, 0, [0.0, 0.0, 0.0]), {"bone": bone, "color": color, "matrix": m})
	var s := -1.0 if side == "L" else 1.0
	h.add(Sk.rbox(0.002 * k, 0.11 * k, 0.055 * k, 0, [s * 0.007 * k, 0.0, 0.0]), {"bone": bone, "color": "#9fc0de", "matrix": m})


## Backpack on the chest bone.
static func backpack(h, o: Dictionary = {}) -> void:
	var P: Dictionary = h.P
	var k: float = P.k
	var b: Dictionary = h.b
	var sp_y: float = h.bind_pos(b.spine)[1]
	var bb: float = P.torso[6][2]
	var cy: float = P.chest + 0.02 * k - sp_y
	h.add(Sk.rbox(0.27 * k, 0.34 * k, 0.13 * k, 0, [0.0, cy, -bb - 0.075 * k]), {"bone": b.spine, "color": orr(o.get("color"), "#5f6f8c"), "weights": h.torso_weights()})
	h.add(Sk.rbox(0.23 * k, 0.12 * k, 0.05 * k, 0, [0.0, cy - 0.08 * k, -bb - 0.15 * k]), {"bone": b.spine, "color": orr(o.get("pocket"), "#53617c"), "weights": h.torso_weights()})
	for s in [1.0, -1.0]:
		var pts: Array = []
		for i in 7:
			var t := i / 6.0
			var ph := (s * Sk.lerp_(160, 25, t)) * DEG
			var y := Sk.lerp_(P.shY + 0.03 * k, P.chest - 0.1 * k, sin(t * PI / 2.0) * 0.6 + t * 0.4)
			var p: Array = h.torso_pt(P.outer, ph, y, 0.022 * k)
			pts.append(Vector3(p[0] * (1.0 if t < 0.3 else 1.0), p[1] - sp_y, p[2]))
		h.add(Sk.sweep(pts, func(_s): return 0.035 * k, func(_s): return 0.006 * k, func(p): return Vector3(p.x, 0.4, p.z).normalized(), 4), {"bone": b.spine, "color": orr(o.get("strap"), "#48546c"), "weights": h.torso_weights()})


## Open paperback with one turning page. Returns {book, page} bones.
static func book(h, o: Dictionary = {}) -> Dictionary:
	var k: float = h.P.k
	var bk = h.prop_bone("book", h.b.hips, 0, 0.2, 0.3)
	var pg = h.prop_bone("page", bk, 0, 0, 0.004 * k)
	var W := 0.105 * k
	var H := 0.16 * k
	for s in [1.0, -1.0]:
		# cover half (slightly tilted up from the spine => shallow V)
		var m := at(ROT(0, -s * 0.16, 0), 0, 0, 0)
		h.add(Sk.rbox(W, H, 0.004 * k, 0, [s * W / 2.0, 0.0, -0.004 * k]), {"bone": bk, "color": orr(o.get("cover"), "#c7836a"), "matrix": m})
		h.add(Sk.rbox(W * 0.95, H * 0.95, 0.012 * k, 0, [s * W * 0.49, 0.0, 0.003 * k]), {"bone": bk, "color": "#f1ece2", "matrix": m})
	# turning page: lies on the right half at rest (rotates about the local Y axis)
	h.add(Sk.rbox(W * 0.93, H * 0.93, 0.0015 * k, 0, [W * 0.47, 0.0, 0.004 * k]), {"bone": pg, "color": "#f4efe6", "matrix": ROT(0, -0.16, 0)})
	return {"book": bk, "page": pg, "W": W, "H": H}


## Chalk stick / small cloth in the hand.
static func chalk(h, side: String) -> void:
	var k: float = h.P.k
	h.add(Sk.limb(0.05 * k, 0.005 * k, 0.005 * k, {"cols": 6}), {"bone": h.b["hand" + side], "color": "#f0ede6", "matrix": at(ROT(1.2, 0, 0), 0, -0.06 * k, 0.03 * k)})


## Wristwatch band.
static func watch(h, side: String, color = "#6b5a57") -> void:
	var k: float = h.P.k
	var fa: float = h.P.farmR[1]
	h.add(Sk.rings([{"y": -h.P.farm + 0.03 * k, "a": fa * 1.12, "b": fa * 1.12}, {"y": -h.P.farm + 0.012 * k, "a": fa * 1.12, "b": fa * 1.12}], 10), {"bone": h.b["farm" + side], "color": color})
