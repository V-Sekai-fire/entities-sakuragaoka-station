# characters/human.js: anime-proportion people (≈6.5–7 heads). One skinned mesh per person (vertex
# colours + a 512² atlas with the painted face and hair ramp), a small skeleton (spine, arms, legs,
# 8 skirt bones, hair chains) so skirts flare and hair sways with GPU skinning.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Sk = preload("res://addons/sakuragaoka_station/world/characters/skin.gd")
const Atlas = preload("res://addons/sakuragaoka_station/world/characters/atlas.gd")

const DEG := PI / 180.0

# ------------------------------------------------------------------ proportions
const BASE := {
	"f": {
		"H": 1.58, "hip": 0.80, "hipJx": 0.079, "hipJy": 0.785, "thigh": 0.372, "shin": 0.352, "ankle": 0.061,
		"waist": 0.935, "chest": 1.08, "neck": 1.262, "headB": 1.326, "shX": 0.148, "shY": 1.232, "clavX": 0.03,
		"uarm": 0.238, "farm": 0.212, "hand": 0.86,
		"torso": [[0.80, 0.128, 0.099], [0.85, 0.126, 0.096], [0.90, 0.119, 0.089], [0.95, 0.110, 0.080], [1.00, 0.106, 0.075], [1.05, 0.112, 0.081],
			[1.10, 0.124, 0.089], [1.15, 0.135, 0.093], [1.19, 0.143, 0.089], [1.222, 0.142, 0.082], [1.246, 0.12, 0.07], [1.262, 0.074, 0.05], [1.28, 0.034, 0.03]],
		"bust": 0.02, "bustY": 1.13, "neckR": 0.031,
		"head": {"rx": 0.098, "ry": 0.109, "rz": 0.104, "cy": 0.135, "cz": 0.014, "jaw": 0.44, "chin": 0.28, "chinZ": 0.5, "flat": 0.93},
		"thighR": [0.072, 0.046], "calfR": 0.05, "ankleR": 0.027, "uarmR": [0.034, 0.028], "farmR": [0.027, 0.021],
		"pelvis": [[0.955, 0.112, 0.083], [0.90, 0.13, 0.097], [0.84, 0.136, 0.10], [0.785, 0.118, 0.088], [0.745, 0.06, 0.05], [0.735, 0.0, 0.0]],
	},
	"m": {
		"H": 1.72, "hip": 0.90, "hipJx": 0.09, "hipJy": 0.875, "thigh": 0.41, "shin": 0.395, "ankle": 0.07,
		"waist": 1.03, "chest": 1.19, "neck": 1.405, "headB": 1.472, "shX": 0.186, "shY": 1.37, "clavX": 0.035,
		"uarm": 0.275, "farm": 0.245, "hand": 0.98,
		"torso": [[0.86, 0.150, 0.108], [0.93, 0.148, 0.104], [1.00, 0.144, 0.100], [1.07, 0.146, 0.101], [1.14, 0.155, 0.104], [1.21, 0.166, 0.107],
			[1.28, 0.176, 0.105], [1.33, 0.181, 0.099], [1.36, 0.176, 0.090], [1.383, 0.152, 0.080], [1.40, 0.102, 0.060], [1.418, 0.046, 0.042]],
		"bust": 0.0, "bustY": 1.25, "neckR": 0.041,
		"head": {"rx": 0.095, "ry": 0.107, "rz": 0.103, "cy": 0.131, "cz": 0.012, "jaw": 0.32, "chin": 0.22, "chinZ": 0.42, "flat": 0.95},
		"thighR": [0.082, 0.053], "calfR": 0.057, "ankleR": 0.031, "uarmR": [0.044, 0.036], "farmR": [0.036, 0.027],
		"pelvis": [[1.05, 0.146, 0.101], [0.99, 0.152, 0.106], [0.93, 0.154, 0.106], [0.875, 0.134, 0.094], [0.83, 0.07, 0.055], [0.815, 0.0, 0.0]],
	},
}


## a ?? d
static func nn(v, d):
	return d if v == null else v


## a || d
static func orr(v, d):
	return v if truthy(v) else d


static func truthy(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String:
		return v != ""
	return true


## (+x.toFixed(n))
static func fixed(x: float, n: int) -> float:
	return String.num(x, n).to_float()


static func V(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)


static func TR(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


static func proportions(spec: Dictionary) -> Dictionary:
	var b: Dictionary = BASE[orr(spec.get("sex"), "f")]
	var k: float = orr(spec.get("height"), b.H) / b.H
	var w: float = nn(spec.get("width"), 1.0)            # girth factor
	var hk: float = nn(spec.get("headK"), 1.0)            # head scale (children / elderly slightly larger)
	var P := {"k": k, "w": w, "hk": hk, "sex": orr(spec.get("sex"), "f")}
	for key in ["hip", "hipJy", "thigh", "shin", "ankle", "waist", "chest", "neck", "headB", "shY", "uarm", "farm", "bustY"]:
		P[key] = b[key] * k
	P.hipJx = b.hipJx * k * w
	P.shX = (b.shX - 0.006) * k * nn(spec.get("shoulder"), w)
	P.clavX = b.clavX * k
	P["shY"] -= 0.01 * k
	P.torso = b.torso.map(func(r): return [r[0] * k, r[1] * k * w, r[2] * k * w])
	if truthy(spec.get("belly")):
		var belly: float = spec.belly
		P.torso = P.torso.map(func(r):
			var f := 1.0 + belly * exp(-pow(((r[0] / k) - (b.waist + 0.02)) / 0.12, 2.0))
			return [r[0], r[1] * f, r[2] * f * 1.04])
	P.pelvis = b.pelvis.map(func(r): return [r[0] * k, r[1] * k * w, r[2] * k * w])
	P.bust = b.bust * k * nn(spec.get("bust"), 1.0)
	P.neckR = b.neckR * k * sqrt(w)
	P.hand = b.hand * k
	P.head = b.head.duplicate()
	for key in ["rx", "ry", "rz", "cy", "cz"]:
		P.head[key] = b.head[key] * k * hk
	if spec.get("headShape") != null:
		P.head.merge(spec.headShape, true)
	# keep the chin on the head bone when the head is scaled
	P.headB = P.headB - (P.head.cy - b.head.cy * k) * 0.0
	P.thighR = b.thighR.map(func(r): return r * k * w)
	P.calfR = b.calfR * k * w
	P.ankleR = b.ankleR * k * sqrt(w)
	P.uarmR = b.uarmR.map(func(r): return r * k * w)
	P.farmR = b.farmR.map(func(r): return r * k * w)
	# outer garment profile = torso, widened below the waist so untucked tops always cover trousers / belts / skirt bands
	var pel: Array = T.stable_sort(P.pelvis.filter(func(r): return r[1] > 0.0), func(a, c): return a[0] - c[0])
	var p_at := func(y: float) -> Array:
		if y <= pel[0][0]:
			return [pel[0][1], pel[0][2]]
		for i in range(1, pel.size()):
			if y <= pel[i][0]:
				var t: float = (y - pel[i - 1][0]) / (pel[i][0] - pel[i - 1][0])
				return [Sk.lerp_(pel[i - 1][1], pel[i][1], t), Sk.lerp_(pel[i - 1][2], pel[i][2], t)]
		var l: Array = pel[pel.size() - 1]
		return [l[1], l[2]]
	var ys: Array = []
	for r in P.torso + pel:
		var y := fixed(r[0], 4)
		if not ys.has(y):
			ys.append(y)
	ys.sort()
	P.outer = ys.map(func(y):
		var ab := prof(P.torso, y)
		if y > P.waist + 0.03 * k:
			return [y, ab[0], ab[1]]
		var pp: Array = p_at.call(y)
		return [y, maxf(ab[0], pp[0] * 1.085), maxf(ab[1], pp[1] * 1.09)])
	return P


## interpolate [y, a, b] profile at y
static func prof(tab: Array, y: float) -> Array:
	if y <= tab[0][0]:
		return [tab[0][1], tab[0][2]]
	for i in range(1, tab.size()):
		if y <= tab[i][0]:
			var t: float = (y - tab[i - 1][0]) / (tab[i][0] - tab[i - 1][0])
			return [Sk.lerp_(tab[i - 1][1], tab[i][1], t), Sk.lerp_(tab[i - 1][2], tab[i][2], t)]
	var l: Array = tab[tab.size() - 1]
	return [l[1], l[2]]


## merge coincident vertices of a non-indexed geometry (keeps first uv)
static func merge_by_pos(g: T.Geometry) -> T.Geometry:
	var p: T.Attr = g.position()
	var uv: T.Attr = g.get_attribute("uv")
	var map := {}
	var pos := PackedFloat32Array()
	var uvs := PackedFloat32Array()
	var idx := PackedInt32Array()
	for i in p.count():
		var key := "%.5f,%.5f,%.5f" % [p.get_x(i), p.get_y(i), p.get_z(i)]
		var j = map.get(key)
		if j == null:
			j = pos.size() / 3
			map[key] = j
			pos.append_array([p.get_x(i), p.get_y(i), p.get_z(i)])
			uvs.append_array([uv.get_x(i), uv.get_y(i)])
		idx.append(j)
	var o := T.Geometry.new()
	o.set_attribute("position", T.Attr.new(pos, 3))
	o.set_attribute("uv", T.Attr.new(uvs, 2))
	o.set_index(idx)
	return o


# ------------------------------------------------------------------ the person
class Human extends RefCounted:
	const H = preload("res://addons/sakuragaoka_station/world/characters/human.gd")
	var ctx
	var spec: Dictionary
	var P: Dictionary
	var B
	var group
	var b := {}
	var skirtBones: Array = []
	var hairChains: Array = []
	var extraBones := {}
	var seed := 1.0
	var mats := {}
	var mesh
	var face := ""
	var triangles := 0.0
	var rest := {}
	var skirtInfo = null
	var _book = null

	func _init(c, sp: Dictionary) -> void:
		ctx = c
		spec = sp
		P = H.proportions(sp)
		B = Sk.SkinBuilder.new("chr_" + sp.key)
		group = T.Group.new()
		group.name = "chr_" + sp.key
		seed = H.nn(sp.get("seed"), 1.0)
		_skeleton()
		_head()
		_body()
		_hair()
		_outfit()
		if sp.get("props"):
			for p in sp.props:
				p.call(self)
		# atlas & materials
		var variants: Array = H.orr(sp.get("variants"), ["open", "blink"])
		var aspec := {"key": sp.key, "face": sp.get("face"), "hair": sp.get("hairTex"), "stripes": sp.get("stripes"), "plaid": sp.get("plaid"), "misc": sp.get("misc"), "misc2": sp.get("misc2")}
		for v in variants:
			mats[v] = ctx.mat.toon("#ffffff", {"map": Atlas.make_atlas(ctx, aspec, v), "vertexColors": true, "side": "double", "paint": 0.025})
		mesh = B.build(group, mats[variants[0]])
		face = variants[0]
		triangles = B.triangles()
		# rest pose cache
		for bone in B.bones:
			rest[bone] = {"p": bone.position}

	func set_face(v: String) -> void:
		if v != face and mats.has(v):
			mesh.material = mats[v]
			face = v

	# -------------------------------------------------------------- skeleton
	func _skeleton() -> void:
		b.root = B.bone("root", null, 0, 0, 0)
		group.add(b.root)
		b.hips = B.bone("hips", b.root, 0, P.hip, 0)
		b.spine = B.bone("spine", b.hips, 0, P.waist - P.hip, 0)
		b.chest = B.bone("chest", b.spine, 0, P.chest - P.waist, 0)
		b.neck = B.bone("neck", b.chest, 0, P.neck - P.chest, -0.004 * P.k)
		b.head = B.bone("head", b.neck, 0, P.headB - P.neck, -0.006 * P.k)
		for s in [1.0, -1.0]:
			var n := "L" if s > 0 else "R"
			b["clav" + n] = B.bone("clav" + n, b.chest, s * P.clavX, P.shY - P.chest, 0)
			b["uarm" + n] = B.bone("uarm" + n, b["clav" + n], s * (P.shX - P.clavX), 0, 0)
			b["farm" + n] = B.bone("farm" + n, b["uarm" + n], 0, -P.uarm, 0)
			b["hand" + n] = B.bone("hand" + n, b["farm" + n], 0, -P.farm, 0)
			b["thigh" + n] = B.bone("thigh" + n, b.hips, s * P.hipJx, P.hipJy - P.hip, 0)
			b["shin" + n] = B.bone("shin" + n, b["thigh" + n], 0, -P.thigh, 0)
			b["foot" + n] = B.bone("foot" + n, b["shin" + n], 0, -P.shin, 0)

	func bind_pos(bone) -> Array:
		return B.bind_pos(bone)

	## convert root-space point to bone-local (bind has identity rotations)
	func local(bone, p: Array) -> Array:
		var q: Array = B.bind_pos(bone)
		return [p[0] - q[0], p[1] - q[1], p[2] - q[2]]

	func add(geo: T.Geometry, o: Dictionary) -> void:
		B.add(geo, o)

	# -------------------------------------------------------------- head + face
	func head_pt(ph: float, th: float, R: float = 1.0) -> Array:
		var h: Dictionary = P.head
		var cs := cos(th)
		var x := sin(ph) * cs
		var y := sin(th)
		var z := cos(ph) * cs
		x *= h.rx * R
		z *= h.rz * R
		if y >= 0.0:
			y *= h.ry * R
		else:
			var t := -y
			x *= 1.0 - h.jaw * t * t
			y = -h.ry * R * t * (1.0 + h.chin * t)
			if z < 0.0:
				z *= 1.0 - 0.32 * t
			z += h.chinZ * h.rz * R * t * t * (0.75 + 0.25 * cos(ph) * cs)
		if z > 0.0:
			z *= h.flat
		return [x, y + h.cy, z + h.cz]

	func _head() -> void:
		var sp := spec
		var skin = H.orr(sp.get("skin"), "#f6dccb")
		# neck
		var nr: float = P.neckR
		add(Sk.rings([{"y": -0.045 * P.k, "a": nr * 1.25, "b": nr * 1.1}, {"y": 0.0, "a": nr, "b": nr}, {"y": (P.headB - P.neck) * 0.6, "a": nr * 0.96, "b": nr * 0.96}, {"y": (P.headB - P.neck) + 0.03 * P.k, "a": nr * 0.94, "b": nr * 0.94}], 10), {"bone": b.neck, "color": skin})
		# head: grid over angles, uv into the painted face window
		var cols := 26
		var rows := 18
		var g := Sk.surface(cols, rows, func(u: float, v: float) -> Array:
			var ph := (u - 0.5) * TAU
			var th := (0.5 - v) * PI
			return head_pt(ph, th, 1.0))
		# bend face normals toward the face direction so the cel terminator never slices across the face
		var n: T.Attr = g.get_attribute("normal")
		var p: T.Attr = g.position()
		var F := Vector3(0, 0.08, 1).normalized()
		var c0 := Vector3(0, P.head.cy, P.head.cz - P.head.rz * 0.6)
		for i in n.count():
			var q := (Vector3(p.get_x(i), p.get_y(i), p.get_z(i)) - c0).normalized()     # softer sphere-like normal
			q = q.lerp(Vector3(n.get_x(i), n.get_y(i), n.get_z(i)), 0.35).normalized()
			q = q.lerp(F, Sk.smooth(-0.15, 0.55, q.z) * 0.72).normalized()             # front of the face -> one tone
			n.set_xyz(i, q.x, q.y, q.z)
		var uv: T.Attr = g.get_attribute("uv")
		for i in uv.count():
			var ph := (uv.get_x(i) - 0.5) * 360.0
			var th := (0.5 - uv.get_y(i)) * 180.0
			var f := Atlas.face_uv(ph, th)
			uv.set_xy(i, f[0], f[1])
		add(g, {"bone": b.head, "color": "#ffffff", "rect": [0.0, 0.0, 1.0, 1.0]})
		# ears (visible on short hair)
		if H.truthy(sp.get("ears")):
			for s in [1.0, -1.0]:
				var e := head_pt(s * 88.0 * DEG, -10.0 * DEG, 0.99)
				add(Sk.ellipsoid(0.012 * P.k, 0.026 * P.k * P.hk, 0.018 * P.k, e, 8, 6), {"bone": b.head, "color": skin})

	# -------------------------------------------------------------- body (skin parts + limbs)
	func _body() -> void:
		var sp := spec
		var o: Dictionary = H.orr(sp.get("outfit"), {})
		var skin = H.orr(sp.get("skin"), "#f6dccb")
		for s in [1.0, -1.0]:
			var n := "L" if s > 0 else "R"
			# hands (mitten style with thumb); gloves recolour them
			var style = "relax"
			if sp.get("hands") and H.truthy(sp.hands.get(n)):
				style = sp.hands[n]
			_hand(b["hand" + n], s, H.orr(o.get("gloves"), skin), style)
			# legs
			var leg_c = H.orr(o.get("legs"), skin)                   # skin / tights / trousers colour
			var trousers: bool = o.get("bottom") == "trousers" or o.get("bottom") == "shorts"
			var tr := 1.28 if trousers else 1.0
			if not trousers:
				add(Sk.limb(P.thigh, P.thighR[0], P.thighR[1], {"mid": [[0.5, (P.thighR[0] + P.thighR[1]) * 0.52]], "cols": 10}), {"bone": b["thigh" + n], "color": H.orr(o.get("thighs"), leg_c)})
				# shin: knee..calf..ankle (+ socks)
				var kk: float = P.k
				add(Sk.limb(P.shin, P.thighR[1] * 0.98, P.ankleR, {"mid": [[0.28, P.calfR], [0.62, P.calfR * 0.78]], "midZ": func(t): return -0.006 * kk * sin(t * PI), "cols": 10}), {"bone": b["shin" + n], "color": H.orr(o.get("shins"), leg_c)})
				if H.truthy(o.get("socks")):
					var top: float = H.nn(o.socks.get("top"), 0.35)   # fraction of shin from the ankle
					var L: Array = []
					var ys := [1.0 - top, 1.0 - top + 0.04, 0.62, 0.8, 0.96, 1.0]
					for t in ys:
						var r: float
						if t < 0.28:
							r = Sk.lerp_(P.thighR[1], P.calfR, t / 0.28)
						elif t < 0.62:
							r = Sk.lerp_(P.calfR, P.calfR * 0.78, (t - 0.28) / 0.34)
						else:
							r = Sk.lerp_(P.calfR * 0.78, P.ankleR, (t - 0.62) / 0.38)
						L.append({"y": -P.shin * t, "a": r + 0.0035 * P.k, "b": r + 0.0035 * P.k})
					L[0]["a"] -= 0.001
					L[0]["b"] -= 0.001
					add(Sk.rings(L, 10), {"bone": b["shin" + n], "color": o.socks.color})
			else:
				var short: bool = o.get("bottom") == "shorts"
				add(Sk.limb(P.thigh, P.thighR[0] * tr, P.thighR[1] * tr * 1.05, {"mid": [[0.5, (P.thighR[0] + P.thighR[1]) * 0.55 * tr]], "cols": 10, "capBottom": 0.0 if short else 0.75}), {"bone": b["thigh" + n], "color": o.get("bottomColor")})
				if short:
					add(Sk.limb(P.shin, P.thighR[1] * 0.98, P.ankleR, {"mid": [[0.28, P.calfR], [0.62, P.calfR * 0.78]], "cols": 10}), {"bone": b["shin" + n], "color": skin})
					if H.truthy(o.get("socks")):
						add(Sk.rings([{"y": -P.shin * 0.8, "a": P.calfR * 0.84, "b": P.calfR * 0.84}, {"y": -P.shin * 0.9, "a": P.ankleR * 1.25, "b": P.ankleR * 1.25}, {"y": -P.shin * 1.02, "a": P.ankleR * 1.2, "b": P.ankleR * 1.2}], 10), {"bone": b["shin" + n], "color": o.socks.color})
				else:
					add(Sk.limb(P.shin, P.thighR[1] * tr * 1.02, P.ankleR * 1.75, {"mid": [[0.3, P.calfR * 1.22]], "cols": 10, "capBottom": 0.2}), {"bone": b["shin" + n], "color": o.get("bottomColor")})
			_shoe(b["foot" + n], s, H.orr(o.get("shoes"), {"color": "#5b4336", "sole": "#4a3a36", "type": "loafer"}))
		# pelvis for trousers (covers hip joints)
		if o.get("bottom") == "trousers" or o.get("bottom") == "shorts":
			var L: Array = P.pelvis.map(func(r): return {"y": r[0] - P.hip, "a": r[1] * 1.06, "b": r[2] * 1.06})
			add(Sk.rings(L, 14), {"bone": b.hips, "color": o.get("bottomColor")})
			if H.truthy(o.get("belt")):
				add(Sk.rings([{"y": P.waist - P.hip + 0.012, "a": P.pelvis[0][1] * 1.075, "b": P.pelvis[0][2] * 1.08}, {"y": P.waist - P.hip - 0.018, "a": P.pelvis[1][1] * 1.04, "b": P.pelvis[1][2] * 1.05}], 14), {"bone": b.hips, "color": o.belt})

	func _hand(bone, s: float, color, style: String) -> void:
		var k: float = P.hand
		var addg := func(g): add(g, {"bone": bone, "color": color})
		var inward := -s # palm faces the body
		if style == "fist" or style == "grip" or style == "point" or style == "hold":
			addg.call(Sk.ellipsoid(0.021 * k, 0.036 * k, 0.037 * k, [0.0, -0.034 * k, 0.004 * k], 8, 6))
			# curled fingers: a rounded knuckle roll in front
			addg.call(Sk.ellipsoid(0.02 * k, 0.024 * k, 0.03 * k, [inward * 0.006 * k, -0.062 * k, 0.018 * k], 8, 5))
			addg.call(Sk.ellipsoid(0.01 * k, 0.022 * k, 0.011 * k, [inward * 0.012 * k, -0.04 * k, 0.03 * k], 6, 4)) # thumb
			if style == "point":
				add(Sk.limb(0.05 * k, 0.0085 * k, 0.007 * k, {"cols": 6}), {"bone": bone, "color": color, "matrix": H.TR(inward * 0.004 * k, -0.07 * k, 0.03 * k)})
		else:
			addg.call(Sk.ellipsoid(0.02 * k, 0.046 * k, 0.037 * k, [inward * 0.002 * k, -0.046 * k, 0.003 * k], 8, 6))
			addg.call(Sk.ellipsoid(0.017 * k, 0.03 * k, 0.034 * k, [inward * 0.005 * k, -0.085 * k, 0.006 * k], 8, 5))
			addg.call(Sk.ellipsoid(0.01 * k, 0.024 * k, 0.011 * k, [inward * 0.01 * k, -0.034 * k, 0.03 * k], 6, 4))

	func _shoe(bone, _s: float, sh: Dictionary) -> void:
		var k: float = P.k
		var a: float = P.ankle # ankle height above the sole
		var len: float = (0.26 if P.sex == "m" else 0.225) * k
		var wid: float = (0.095 if P.sex == "m" else 0.08) * k
		var hh: float = 0.07 * k if sh.get("type") == "sneaker" else 0.06 * k
		# upper
		var g := Sk.surface(12, 6, func(u: float, v: float) -> Array:
			var ph := (u - 0.5) * TAU
			var th := (0.5 - v) * PI
			var cz := cos(ph)
			var sx := sin(ph)
			var e := func(x: float) -> float: return T.sign(x) * pow(absf(x), 0.55)
			var x: float = e.call(sx) * e.call(cos(th)) * wid / 2.0
			var y: float = e.call(sin(th)) * hh / 2.0
			var z: float = e.call(cz) * e.call(cos(th)) * len / 2.0
			# toe narrower & lower, heel rounder
			var f := z / (len / 2.0)
			if f > 0.0:
				x *= 1.0 - 0.18 * f * f
				y -= maxf(0.0, y) * 0.35 * f * f
			if y < -hh * 0.3:
				y = -hh * 0.3 + (y + hh * 0.3) * 0.25 # flatten the sole
			return [x, y, z])
		var cy := -a + hh * 0.34
		var cz := len * 0.3
		add(g, {"bone": bone, "color": sh.color, "matrix": H.TR(0, cy, cz)})
		# sole
		add(Sk.rbox(wid * 1.04, 0.016 * k, len * 1.02, 0, [0.0, -a + 0.008 * k, cz]), {"bone": bone, "color": H.orr(sh.get("sole"), "#4a3f3c")})
		if H.truthy(sh.get("accent")):
			add(Sk.rbox(wid * 1.05, 0.012 * k, len * 0.5, 0, [0.0, -a + 0.026 * k, cz - len * 0.08]), {"bone": bone, "color": sh.accent})

	# -------------------------------------------------------------- torso helpers
	func torso_pt(tab: Array, ph: float, y: float, off: float = 0.0, bust = null) -> Array:
		if bust == null:
			bust = P.bust
		var ab := H.prof(tab, y)
		var bump: float = bust * exp(-pow((y - P.bustY) / (0.05 * P.k), 2.0)) * pow(maxf(0.0, cos(ph)), 2.0) if bust > 0 else 0.0
		return [sin(ph) * (ab[0] + off), y, cos(ph) * (ab[1] + off) + bump]

	func torso_weights() -> Callable:
		var sp_y: float = B.bind_pos(b.spine)[1]
		return func(_lx, ly, _lz, _s = 0.0, _i = 0) -> Array:
			var y: float = ly + sp_y
			var wc := Sk.smooth(P.chest - 0.07 * P.k, P.chest + 0.05 * P.k, y)
			var ws := 1.0 - wc
			var wh := 0.0
			if y < P.waist:
				wh = ws * Sk.smooth(P.waist, P.waist - 0.08 * P.k, y)
				ws -= wh
			return [[b.chest, wc], [b.spine, ws], [b.hips, wh]]

	## Garment on the torso. o: {y0 (hem), y1 (top), color, off, vOpen: {yV, ang}, cols, colorFn}
	func torso_garment(o: Dictionary) -> T.Geometry:
		var tab: Array = H.orr(o.get("tab"), P.torso)
		var rows_y: Array = []
		var y0: float = o.y0
		var y1: float = H.nn(o.get("y1"), tab[tab.size() - 1][0])
		for r in tab:
			if r[0] > y0 + 0.004 and r[0] < y1 - 0.004:
				rows_y.append(r[0])
		rows_y.push_front(y0)
		rows_y.append(y1)
		# extra rows for smooth V opening
		var v_open = o.get("vOpen")
		if v_open:
			var t := 0.2
			while t < 1.0:
				rows_y.append(Sk.lerp_(v_open.yV, y1, t))
				t += 0.2
			rows_y.append(v_open.yV)
			rows_y = T.stable_sort(rows_y, func(a, c): return a - c)
		var ys: Array = []
		for y in rows_y:
			var fy := H.fixed(y, 5)
			if not ys.has(fy):
				ys.append(fy)
		var rows := ys.size() - 1
		var cols: int = H.orr(o.get("cols"), 20)
		var sp_y: float = B.bind_pos(b.spine)[1]
		var hem_flare: float = H.orr(o.get("hemFlare"), 0.0)
		var off0: float = H.orr(o.get("off"), 0.0)
		var g := Sk.surface(cols, rows, func(u: float, v: float) -> Array:
			var y: float = ys[int(T.js_round(v * rows))]
			var ph: float
			if v_open:
				var tt := Sk.smooth(v_open.yV, y1, y)
				var op: float = v_open.ang * pow(tt, 0.8) * DEG
				ph = op + u * (TAU - 2.0 * op)
			else:
				ph = (u - 0.5) * TAU
			var off: float = off0 + (hem_flare * Sk.smooth(y0 + 0.08 * P.k, y0, y) if hem_flare else 0.0)
			var p := torso_pt(tab, ph, y, off)
			return [p[0], p[1] - sp_y, p[2]])
		add(g, {"bone": b.spine, "color": o.get("color"), "weights": torso_weights(), "colorFn": o.get("colorFn")})
		return g

	## Patch lying on the torso surface: boundary curves inner(u) -> [ph, y], outer(u) -> [ph, y] (deg, m)
	func torso_patch(inner: Callable, outer: Callable, o: Dictionary) -> T.Geometry:
		var tab: Array = H.orr(o.get("tab"), P.outer)
		var sp_y: float = B.bind_pos(b.spine)[1]
		var cols: int = H.orr(o.get("cols"), 16)
		var rows: int = H.orr(o.get("rows"), 4)
		var off0: float = H.orr(o.get("off"), 0.004)
		var lift = o.get("lift")
		var g := Sk.surface(cols, rows, func(u: float, v: float) -> Array:
			var A: Array = inner.call(u)
			var C: Array = outer.call(u)
			var ph: float = Sk.lerp_(A[0], C[0], v) * DEG
			var y: float = Sk.lerp_(A[1], C[1], v)
			var p := torso_pt(tab, ph, y, off0 + (lift.call(u, v) if lift != null else 0.0))
			return [p[0], p[1] - sp_y, p[2]])
		var uv_fn = o.get("uvFn")
		if uv_fn != null:
			var uv: T.Attr = g.get_attribute("uv")
			for i in uv.count():
				var r: Array = uv_fn.call(uv.get_x(i), uv.get_y(i))
				uv.set_xy(i, r[0], r[1])
		add(g, {"bone": b.spine, "color": o.get("color"), "weights": torso_weights(), "rect": [0.0, 0.0, 1.0, 1.0] if uv_fn != null else null})
		return g

	# -------------------------------------------------------------- arms / sleeves
	func sleeves(o: Dictionary) -> void:
		for s in [1.0, -1.0]:
			var n := "L" if s > 0 else "R"
			var ua: Array = P.uarmR
			var fa: Array = P.farmR
			var f: float = H.nn(o.get("loose"), 1.1)
			add(Sk.limb(P.uarm, ua[0] * f * 0.96, ua[1] * f, {"mid": [[0.45, (ua[0] + ua[1]) * 0.5 * f * 1.02]], "cols": 10, "capTop": 0.3}), {"bone": b["uarm" + n], "color": o.get("color")})
			if H.truthy(o.get("short")):
				add(Sk.limb(P.uarm * (1.0 - o.short), ua[1] * 0.95, ua[1] * 0.92, {"cols": 10, "capTop": 0.0}), {"bone": b["uarm" + n], "color": o.get("skin"), "matrix": H.TR(0, -P.uarm * o.short, 0)})
				add(Sk.limb(P.farm, fa[0], fa[1], {"cols": 10}), {"bone": b["farm" + n], "color": o.get("skin")})
				continue
			var rolled := H.truthy(o.get("rolled"))
			var len: float = P.farm * 0.35 if rolled else P.farm
			add(Sk.limb(len, fa[0] * f * 1.02, (fa[0] if rolled else fa[1]) * f * H.nn(o.get("bell"), 1.06), {"cols": 10, "capBottom": 0.3}), {"bone": b["farm" + n], "color": o.get("color")})
			if rolled:
				add(Sk.rings([{"y": -len + 0.012, "a": fa[0] * f * 1.12, "b": fa[0] * f * 1.12}, {"y": -len - 0.018, "a": fa[0] * f * 1.18, "b": fa[0] * f * 1.15}, {"y": -len - 0.03, "a": fa[0] * 1.02, "b": fa[0] * 1.02}], 10), {"bone": b["farm" + n], "color": o.get("color")})
				add(Sk.limb(P.farm, fa[0], fa[1], {"cols": 10, "capTop": 0.0}), {"bone": b["farm" + n], "color": o.get("skin")})
			if H.truthy(o.get("cuff")):
				var c: Dictionary = o.cuff
				var r: float = fa[1] * f * 1.12
				var h: float = c.h * P.k
				var L := [{"y": -P.farm + h, "a": r * 0.98, "b": r * 0.98}, {"y": -P.farm + h - 0.002, "a": r, "b": r}, {"y": -P.farm - 0.004, "a": r * 1.02, "b": r * 1.02}, {"y": -P.farm - 0.006, "a": r * 0.8, "b": r * 0.8}]
				var g := Sk.rings(L, 10)
				if H.truthy(c.get("stripes")):
					var uv: T.Attr = g.get_attribute("uv")
					for i in uv.count():
						var vv := uv.get_y(i)
						var r2 := Atlas.cell_uv(0, 0.5, 1.0 - (0.62 + vv * 0.38))
						uv.set_xy(i, r2[0], r2[1])
					add(g, {"bone": b["farm" + n], "color": "#ffffff", "rect": [0.0, 0.0, 1.0, 1.0]})
				else:
					add(g, {"bone": b["farm" + n], "color": c.get("color")})

	# -------------------------------------------------------------- skirts
	func skirt(o: Dictionary) -> void:
		var K := 8
		var y_top: float = H.nn(o.get("yTop"), P.waist + 0.02 * P.k)
		var y_hem: float = o.yHem
		var abT := H.prof(P.torso, y_top)
		var aw: float = abT[0] * 1.02
		var bw: float = abT[1] * 1.04
		if skirtBones.is_empty():
			for k in K:
				var ph := float(k) / K * TAU
				var sb = B.bone("skirt%d" % k, b.hips, sin(ph) * aw, y_top - P.hip, cos(ph) * bw)
				sb.user_data["ph"] = ph
				skirtBones.append(sb)
		# radius profile: waist -> hip -> hem
		var hip_y: float = P.hipJy - 0.01 * P.k
		var abH := H.prof(P.pelvis, hip_y)
		var aH: float = abH[0]
		var bH: float = abH[1]
		var rows: int = H.orr(o.get("rows"), 7)
		var N: int = H.orr(o.get("pleats"), 0)
		var segs: int = N * 2 if N else H.orr(o.get("cols"), 22)
		var flare: float = H.nn(o.get("flare"), 0.07)
		var R := func(t: float) -> Array: # t 0 top .. 1 hem
			var y := Sk.lerp_(y_top, y_hem, t)
			var hipT := Sk.clamp_((y_top - hip_y) / (y_top - y_hem), 0.05, 0.6)
			var a: float
			var bb: float
			if t < hipT:
				var s2 := sin(t / hipT * PI / 2.0)
				a = Sk.lerp_(aw, aH * 1.18, s2)
				bb = Sk.lerp_(bw, bH * 1.2, s2)
			else:
				var s2 := (t - hipT) / (1.0 - hipT)
				a = aH * 1.18 + flare * P.k * s2
				bb = bH * 1.2 + flare * P.k * s2 * 0.95
			return [a, bb, y]
		var pos := PackedFloat32Array()
		var uvs := PackedFloat32Array()
		var pleat: float = H.nn(o.get("pleatDepth"), 0.07)
		var pt := func(i: int, j: int) -> Array:
			var t := float(j) / rows
			var r: Array = R.call(t)
			var ph := float(i) / segs * TAU
			var f := 1.0
			if N:
				f = 1.0 - pleat * (0.3 + t) * 0.5 if i % 2 == 0 else 1.0 + pleat * (0.3 + t) * 0.5
			return [sin(ph) * r[0] * f, r[2] - P.hip, cos(ph) * r[1] * f, ph, t]
		var tri: Array = []
		for j in rows:
			for i in segs:
				var A: Array = pt.call(i, j)
				var Bp: Array = pt.call(i + 1, j)
				var C: Array = pt.call(i, j + 1)
				var D: Array = pt.call(i + 1, j + 1)
				var uA := (i % 2) * 0.5
				var uB := uA + 0.5
				var v0 := float(j) / rows
				var v1 := float(j + 1) / rows
				tri.append_array([[A, uA, v0], [C, uA, v1], [Bp, uB, v0], [Bp, uB, v0], [C, uA, v1], [D, uB, v1]])
		for e in tri:
			var p: Array = e[0]
			pos.append_array([p[0], p[1], p[2]])
			uvs.append_array([e[1], e[2]])
		var g := T.Geometry.new()
		g.set_attribute("position", T.Attr.new(pos, 3))
		g.set_attribute("uv", T.Attr.new(uvs, 2))
		if N:
			g.compute_vertex_normals()
		else:
			g = H.merge_by_pos(g)
			g.compute_vertex_normals()
			Sk.weld_normals(g)
		var weights := func(lx, ly, lz, _s = 0.0, _i = 0) -> Array:
			var ph := atan2(lx, lz)
			if ph < 0.0:
				ph += TAU
			var t := Sk.clamp_((y_top - P.hip - ly) / (y_top - y_hem), 0.0, 1.0)
			var kf := ph / TAU * K
			var k0 := posmod(int(floorf(kf)), K)
			var k1 := (k0 + 1) % K
			var f := kf - floorf(kf)
			var gw := pow(t, 1.25)
			return [[b.hips, 1.0 - gw], [skirtBones[k0], gw * (1.0 - f)], [skirtBones[k1], gw * f]]
		var plaid := H.truthy(o.get("plaid"))
		var uv_fn = null
		if plaid:
			uv_fn = func(_lx, _ly, _lz, u, v, _i = 0): return Atlas.cell_uv(1, u, 1.0 - v)
		add(g, {"bone": b.hips, "color": "#ffffff" if plaid else o.get("color"), "weights": weights, "uvFn": uv_fn})
		# waistband
		add(Sk.rings([{"y": y_top - P.hip + 0.012 * P.k, "a": aw * 1.01, "b": bw * 1.01}, {"y": y_top - P.hip + 0.014 * P.k, "a": aw * 1.03, "b": bw * 1.03}, {"y": y_top - P.hip - 0.02 * P.k, "a": aw * 1.07, "b": bw * 1.08}], 16), {"bone": b.hips, "color": H.orr(o.get("band"), o.get("color"))})
		skirtInfo = {"yTop": y_top, "yHem": y_hem, "aw": aw, "bw": bw}

	# -------------------------------------------------------------- hair
	static func A(ph_deg: float, th_deg: float, R: float) -> Dictionary:
		return {"isAng": true, "v": [ph_deg * DEG, th_deg * DEG, R]}

	func _hair() -> void:
		var hs = spec.get("hair")
		if not hs:
			return
		var h: Dictionary = P.head
		var c := [0.0, h.cy, h.cz]
		var hk: float = P.k * P.hk
		var uv_fn := func(lx, ly, lz, _u = 0.0, _v = 0.0, _i = 0) -> Array:
			var dx: float = lx - c[0]
			var dy: float = ly - c[1]
			var dz: float = lz - c[2]
			var r := Sk.hypot(dx, dy, dz)
			if r == 0.0:
				r = 1.0
			var row := (1.0 - asin(Sk.clamp_(dy / r, -1.0, 1.0)) / (PI / 2.0)) * 0.5
			if dy < -h.ry:
				row = 0.5 + 0.5 * Sk.clamp_(0.6 + (-dy - h.ry) / 0.5, 0.0, 1.0) # hanging strands: darker tips
			var ph := atan2(dx, dz)
			return Atlas.hair_uv(row, 0.5 + 0.44 * sin(ph * 4.0))
		var add_hair := func(g: T.Geometry, weights = null) -> void:
			add(g, {"bone": b.head, "color": "#ffffff", "uvFn": uv_fn, "weights": weights})
		# ---- cap
		var hl_front: float = H.nn(hs.get("hairlineFront"), 15.0)
		var hl_side: float = H.nn(hs.get("hairlineSide"), -22.0)
		var hl_back: float = H.nn(hs.get("hairlineBack"), -58.0)
		var hairline := func(ph: float) -> float:
			var a := absf(ph) / DEG
			return Sk.lerp_(Sk.lerp_(hl_front, hl_side, Sk.smooth(25, 95, a)), hl_back, Sk.smooth(100, 175, a))
		var r_top: float = H.nn(hs.get("volume"), 1.09)
		var hflare = hs.get("flare")
		var r_bot := func(ph: float) -> float:
			return Sk.lerp_(1.06, 1.06 + hflare, Sk.smooth(40, 110, absf(ph) / DEG)) if H.truthy(hflare) else 1.065
		var cap_w = hs.get("capWeights")
		add_hair.call(Sk.surface(30, 11, func(u: float, v: float) -> Array:
			var phn := (u - 0.5) * TAU
			var vv := minf(1.0, v / 0.91)
			var th := Sk.lerp_(90.0, hairline.call(phn), pow(vv, 0.9)) * DEG
			var R := 0.975 if v > 0.95 else Sk.lerp_(r_top, r_bot.call(phn), vv)
			return head_pt(phn, th, R)), cap_w)
		var out := func(p: Vector3) -> Vector3:
			return Vector3(p.x - c[0], (p.y - c[1]) * 0.8, p.z - c[2]).normalized()
		var lock := func(ctrl: Array, w0: float, t0: float, opts: Dictionary = {}) -> T.Geometry:
			var cpts: Array = ctrl.map(func(q): return head_pt(q.v[0], q.v[1], q.v[2]) if q is Dictionary else q)
			var pts := Sk.curve(cpts, H.orr(opts.get("n"), 7))
			var wf = opts.get("wf")
			var g := Sk.sweep(pts,
				func(s): return w0 * hk * (wf.call(s) if wf != null else pow(1.0 - s, 0.7) * (0.75 + s * 2.0 if s < 0.12 else 1.0)),
				func(s): return t0 * hk * (1.0 - 0.65 * s),
				H.orr(opts.get("out"), out), 5)
			add_hair.call(g, opts.get("weights"))
			return g
		# ---- fringe
		var fr: Dictionary = H.orr(hs.get("fringe"), {"n": 7, "span": 62, "tip": 4, "len": 1})
		var frn: int = fr.n
		for i in frn:
			var t := 0.5 if frn == 1 else float(i) / (frn - 1)
			var ph := Sk.lerp_(-fr.span, fr.span, t)
			var skew: float = H.nn(fr.get("skew"), 6.0) * (t - 0.5) * 2.0 + (fr.part * (-1.0 if ph < fr.partAt else 1.0) if H.truthy(fr.get("part")) else 0.0)
			var edge := absf(t - 0.5) * 2.0 # 0 centre .. 1 edge
			var tip_th: float = H.nn(fr.get("tip"), 4.0) - edge * edge * H.nn(fr.get("edgeDrop"), 18.0) + (((i * 7919) % 5) - 2) * 1.6
			lock.call([A(ph * 0.6, 62, 1.02), A(ph * 0.85 + skew * 0.2, 40, r_top * 1.01), A(ph + skew * 0.6, 20, 1.08), A(ph + skew, tip_th, 1.035 + edge * 0.02)],
				H.nn(fr.get("w"), 0.05) * (1.0 - edge * 0.2) * 1.15, H.nn(fr.get("t"), 0.024), {"n": 7})
		# ---- side locks (in front of the ears)
		if H.truthy(hs.get("side")):
			for s in [1.0, -1.0]:
				var sd: Dictionary = hs.side
				var base := [A(s * 64, 42, 1.04), A(s * 76, 12, 1.09), A(s * 80, -30, 1.1)]
				var p2 := head_pt(s * 78 * DEG, -70 * DEG, 1.12)
				var ctrl: Array = base + [[p2[0], p2[1], p2[2] + 0.004]]
				var long = sd.get("long")
				if H.truthy(long):
					ctrl.append([p2[0] * 1.08, p2[1] - long * hk, p2[2] + 0.012 * hk])
				var wfn = _chain_weights("sideL" if s > 0 else "sideR", p2[1], p2[0], p2[2], long * hk + 0.04) if H.truthy(long) else null
				if H.truthy(long):
					var ch: Dictionary = hairChains[hairChains.size() - 1]
					ch.amp = 0.55
					ch.maxFwd = 0.5
				lock.call(ctrl, H.nn(sd.get("w"), 0.034) * 1.2, 0.022, {"n": 8, "weights": wfn})
		# ---- back hair
		if H.truthy(hs.get("back")):
			_back_hair(hs.back, lock, hk)
		if H.truthy(hs.get("ponytail")):
			_ponytail(hs.ponytail, add_hair, hk)
		if H.truthy(hs.get("bun")):
			var p := head_pt(PI, H.nn(hs.bun.get("th"), 18.0) * DEG, 1.1)
			var r: float = hs.bun.r * hk
			add_hair.call(Sk.ellipsoid(r * 1.05, r * 0.9, r * 0.85, [p[0], p[1], p[2] - r * 0.55], 12, 8))
			var m := Transform3D(Basis(Vector3(0, 0, 1), 1.1), Vector3(p[0] - 0.03 * hk, p[1] + 0.035 * hk, p[2] - r * 0.4))
			add(Sk.rings([{"y": 0.0, "a": 0.003, "b": 0.003}, {"y": -0.001, "a": 0.004 * hk, "b": 0.004 * hk}, {"y": -0.075 * hk, "a": 0.003 * hk, "b": 0.003 * hk}], 5), {"bone": b.head, "color": H.orr(hs.bun.get("pin"), "#9a6b5a"), "matrix": m})
		if H.truthy(hs.get("crown")):
			for cr in hs.crown:
				lock.call([A(cr[0], 80, 1.0), A(cr[0] + cr[2] * 0.5, cr[1] * 0.5 + 40, r_top + 0.02), A(cr[0] + cr[2], cr[1], r_top + 0.03)], H.nn(cr[3] if cr.size() > 3 else null, 0.05), 0.02, {"n": 6})
		if H.truthy(hs.get("ahoge")):
			lock.call([A(10, 86, 1.05), A(18, 95, 1.22), [0.02 * hk, h.cy + h.ry * 1.42, h.cz + 0.03 * hk]], 0.018, 0.008, {"n": 6, "out": func(_p): return Vector3(1, 0, 0)})
		if hs.get("accessory") != null:
			hs.accessory.call(self)

	## Hair chain (2 bones hanging from the head) + smooth weights. Returns the weight fn.
	func _chain_weights(cname: String, y0: float, x0 = null, z0 = null, len: float = 0.3, _lateral = null) -> Callable:
		var ch = null
		for c in hairChains:
			if c.name == cname:
				ch = c
				break
		if ch == null:
			var b1 = B.bone("hair_" + cname + "1", b.head, H.nn(x0, 0.0), y0, H.nn(z0, 0.0))
			var b2 = B.bone("hair_" + cname + "2", b1, 0, -len * 0.5, 0)
			ch = {"name": cname, "b1": b1, "b2": b2, "y0": y0, "len": len, "amp": 1.0, "x0": H.nn(x0, 0.0)}
			hairChains.append(ch)
		var head = b.head
		return func(_lx, ly, _lz, _s = 0.0, _i = 0) -> Array:
			var s := Sk.clamp_((y0 - ly) / len, 0.0, 1.2)
			var w1 := Sk.smooth(0.0, 0.35, s)
			var w2 := Sk.smooth(0.35, 0.95, s)
			return [[head, 1.0 - w1], [ch.b1, w1 - w2], [ch.b2, w2]]

	func _back_hair(bk: Dictionary, lock: Callable, hk: float) -> void:
		var h: Dictionary = P.head
		var nape_y: float = h.cy - h.ry * 0.95
		var L: float = bk.len * hk       # length below the nape
		var n: int = H.nn(bk.get("n"), 7)
		# three chains across the back so the curtain moves as a mass
		var chains: Array = [-1, 0, 1].map(func(i): return {"i": i, "name": "back%d" % i, "x": i * 0.07 * hk})
		for ch in chains:
			_chain_weights(ch.name, nape_y, ch.x, h.cz - h.rz * 1.1, L)
		var weight_for := func(lx, ly, _lz, _s = 0.0, _i = 0) -> Array:
			var s := Sk.clamp_((nape_y - ly) / L, 0.0, 1.2)
			var w1 := Sk.smooth(-0.05, 0.35, s)
			var w2 := Sk.smooth(0.35, 0.95, s)
			var ws: Array = chains.map(func(ch): return exp(-pow((lx - ch.x) / (0.07 * hk), 2.0)))
			var out := [[b.head, 1.0 - w1]]
			# pick the two strongest chains
			var idx: Array = T.stable_sort([0, 1, 2], func(a, c2): return ws[c2] - ws[a]).slice(0, 2)
			var t2: float = ws[idx[0]] + ws[idx[1]]
			for k in idx:
				var chn = null
				for cc in hairChains:
					if cc.name == chains[k].name:
						chn = cc
						break
				out.append([chn.b1, (w1 - w2) * ws[k] / t2])
				out.append([chn.b2, w2 * ws[k] / t2])
			return out
		var span: float = minf(H.nn(bk.get("span"), 110.0), 115.0)
		var spread: float = H.nn(bk.get("spread"), 0.25)
		for i in n:
			var t := 0.5 if n == 1 else float(i) / (n - 1)
			var ph := Sk.lerp_(-span, span, t)        # around the back (deg from the back centre)
			var phw := 180.0 + ph
			var e := absf(t - 0.5) * 2.0
			var p1 := head_pt(phw * DEG, -35 * DEG, 1.1)
			var x: float = p1[0] * (1.05 + e * 0.1)
			var z_back: float = h.cz - h.rz * (1.12 - e * 0.35) - H.nn(bk.get("clear"), 0.02) * hk
			var len: float = L * (1.0 - e * H.nn(bk.get("taper"), 0.25)) * (1.0 + (((i * 37) % 7) - 3) * 0.03)
			var ctrl := [A(phw, 40, 1.03), A(phw, 5, 1.1), p1, [x * 1.02, nape_y - L * 0.12, z_back], [x * (1.0 + spread), nape_y - len * 0.6, z_back - 0.01 * hk], [x * (1.0 + spread * 1.2), nape_y - len, z_back + 0.006 * hk]]
			lock.call(ctrl, H.nn(bk.get("w"), 0.07) * (1.0 - e * 0.2), 0.03, {"n": 10, "weights": weight_for,
				"wf": func(s): return (0.8 + s * 2.0 if s < 0.1 else 1.0) * pow(1.0 - maxf(0.0, s - 0.55) / 0.45, 0.9)})

	func _ponytail(pt: Dictionary, add_hair: Callable, hk: float) -> void:
		var tie := head_pt(PI, H.nn(pt.get("th"), 22.0) * DEG, 1.07)
		var L: float = pt.len * hk
		var b1 = B.bone("hair_pony1", b.head, tie[0], tie[1], tie[2] - 0.02 * hk)
		var b2 = B.bone("hair_pony2", b1, 0, -L * 0.45, -0.04 * hk)
		hairChains.append({"name": "pony", "b1": b1, "b2": b2, "y0": tie[1], "len": L, "amp": 1.6})
		var pts := Sk.curve([[tie[0], tie[1], tie[2] + 0.01], [0.0, tie[1] + 0.01 * hk, tie[2] - 0.045 * hk], [0.0, tie[1] - L * 0.25, tie[2] - 0.075 * hk], [0.0, tie[1] - L * 0.6, tie[2] - 0.06 * hk], [0.004, tie[1] - L, tie[2] - 0.03 * hk]], 11)
		var head = b.head
		var wts := func(_lx, ly, _lz, _s = 0.0, _i = 0) -> Array:
			var s := Sk.clamp_((tie[1] - ly) / L, 0.0, 1.1)
			var w1 := Sk.smooth(-0.05, 0.3, s)
			var w2 := Sk.smooth(0.3, 0.9, s)
			return [[head, 1.0 - w1], [b1, w1 - w2], [b2, w2]]
		var pw: float = H.nn(pt.get("w"), 0.065)
		var g := Sk.sweep(pts,
			func(s): return pw * hk * (0.55 + s * 5.0 if s < 0.08 else pow(1.0 - s, 0.75) * (1.0 + 0.35 * sin(minf(1.0, s * 1.6) * PI))),
			func(s): return pw * 0.75 * hk * (0.6 + s * 5.0 if s < 0.08 else pow(1.0 - s, 0.8)),
			func(_p): return Vector3(1, 0, 0), 7)
		add_hair.call(g, wts)
		# tie band
		var m := Transform3D(Basis(Vector3(1, 0, 0), PI / 2.0 - 0.3), Vector3(tie[0], tie[1] + 0.004, tie[2] - 0.024 * hk))
		add(Sk.rings([{"y": 0.012, "a": 0.0, "b": 0.0}, {"y": 0.01, "a": 0.016 * hk, "b": 0.013 * hk}, {"y": -0.01, "a": 0.017 * hk, "b": 0.014 * hk}, {"y": -0.012, "a": 0.0, "b": 0.0}], 8), {"bone": b.head, "color": H.orr(pt.get("tie"), "#c86a78"), "matrix": m})

	# -------------------------------------------------------------- outfits
	func _outfit() -> void:
		var o = spec.get("outfit")
		if not o:
			return
		var k: float = P.k
		var top = o.get("top")
		if top == "sailor":
			_sailor(o)
		elif top == "blazer" or top == "jacket" or top == "staff" or top == "cardigan":
			_jacket(o)
		elif top == "sweater" or top == "hoodie" or top == "blouse" or top == "shirt":
			_simple_top(o)
		if o.get("bottom") == "pleats":
			skirt({"yHem": o.hem * k, "color": o.get("bottomColor"), "pleats": H.nn(o.get("pleats"), 18), "flare": H.nn(o.get("flare"), 0.075), "plaid": o.get("plaid")})
		elif o.get("bottom") == "skirt":
			skirt({"yHem": o.hem * k, "color": o.get("bottomColor"), "flare": H.nn(o.get("flare"), 0.1), "rows": 8, "cols": 24})
		if H.truthy(o.get("apron")):
			_apron(o.apron)

	func _sailor(o: Dictionary) -> void:
		var k: float = P.k
		var y1: float = P.torso[P.torso.size() - 1][0]
		torso_garment({"y0": P.waist - 0.075 * k, "y1": y1, "color": o.get("topColor"), "off": 0.006 * k, "hemFlare": 0.012 * k, "tab": P.outer})
		sleeves({"color": o.get("topColor"), "cuff": {"h": 0.045, "stripes": true}, "bell": 1.12})
		# big sailor collar: back square flap + shoulders + front V
		var yN: float = P.neck + 0.004 * k
		var yV: float = P.chest - 0.03 * k
		var ySh: float = P.shY - 0.03 * k
		var yFlap: float = P.shY - 0.17 * k
		var inner := func(u: float) -> Array:
			if u < 0.3:
				var t := u / 0.3
				return [Sk.lerp_(0, 34, t), Sk.lerp_(yV + 0.005, yN - 0.005, pow(t, 0.9))]
			var t := (u - 0.3) / 0.7
			return [Sk.lerp_(34, 180, t), yN + 0.006 * sin(t * PI)]
		var outer := func(u: float) -> Array:
			if u < 0.3:
				var t := u / 0.3
				return [Sk.lerp_(0, 66, t), Sk.lerp_(yV, ySh, pow(t, 0.75))]
			if u < 0.55:
				var t := (u - 0.3) / 0.25
				return [Sk.lerp_(66, 118, t), ySh - 0.006 * k * t]
			if u < 0.7:
				var t := (u - 0.55) / 0.15
				return [118.0, Sk.lerp_(ySh - 0.006 * k, yFlap, t)]
			var t := (u - 0.7) / 0.3
			return [Sk.lerp_(118, 180, t), yFlap]
		for s in [1.0, -1.0]:
			var fi := func(u):
				var p: Array = inner.call(u)
				return [s * p[0], p[1]]
			var fo := func(u):
				var p: Array = outer.call(u)
				return [s * p[0], p[1]]
			var fuv := func(_u, v): return Atlas.cell_uv(0, 0.5, 1.0 - v)
			torso_patch(fi, fo, {"off": 0.011 * k, "cols": 22, "rows": 5, "color": "#ffffff", "uvFn": fuv})
		# scarf knot + tails at the V
		var sp_y: float = B.bind_pos(b.spine)[1]
		var vp := torso_pt(P.outer, 0.0, yV + 0.012 * k, 0.022 * k)
		var sc = H.orr(o.get("scarf"), "#c86a78")
		var kc := [vp[0], vp[1] - sp_y, vp[2]]
		add(Sk.ellipsoid(0.02 * k, 0.016 * k, 0.012 * k, kc, 10, 6), {"bone": b.spine, "color": sc, "weights": torso_weights()})
		for s in [1.0, -1.0]:
			# bow loops
			add(Sk.ellipsoid(0.03 * k, 0.014 * k, 0.008 * k, [kc[0] + s * 0.026 * k, kc[1] + 0.004 * k, kc[2] - 0.003 * k], 10, 6, func(x, y, z, _u, _v): return [x, y + absf(x) * 0.25 * s * 0.0, z - x * x * 6.0]), {"bone": b.spine, "color": sc, "weights": torso_weights()})
			# tails
			var pts := Sk.curve([[kc[0] + s * 0.004, kc[1] - 0.004, kc[2]], [kc[0] + s * 0.014 * k, kc[1] - 0.05 * k, kc[2] + 0.004], [kc[0] + s * 0.02 * k, kc[1] - 0.09 * k, kc[2] - 0.004 * k]], 5)
			var g := Sk.sweep(pts, func(t): return 0.026 * k * (0.7 + t * 0.5), func(_t): return 0.004 * k, func(_p): return Vector3(0, 0, 1), 4)
			add(g, {"bone": b.spine, "color": sc, "weights": torso_weights()})

	func _jacket(o: Dictionary) -> void:
		var k: float = P.k
		var y1: float = P.torso[P.torso.size() - 1][0]
		var kind: String = o.top
		var yV: float = H.nn(o.get("vY"), 0.93 if kind == "staff" else 0.9) * (P.chest - P.waist) + P.waist
		var v_ang: float = H.nn(o.get("vAng"), 34.0)
		# inner shirt (visible in the V) + tie / ribbon
		torso_garment({"y0": P.waist - 0.02 * k, "y1": y1, "color": H.orr(o.get("shirt"), "#eeebe6"), "off": 0.003 * k})
		var jHem: float = o.jHemY * k if H.truthy(o.get("jHemY")) else P.hipJy - (-0.03 if kind == "cardigan" else 0.04) * k
		torso_garment({"y0": jHem, "y1": y1 - 0.004 * k, "color": o.get("topColor"), "off": 0.011 * k, "vOpen": {"yV": yV, "ang": v_ang}, "hemFlare": 0.014 * k, "cols": 22, "tab": P.outer})
		sleeves({"color": o.get("topColor"), "loose": 1.2, "cuff": {"h": 0.03, "color": o.cuffColor} if H.truthy(o.get("cuffColor")) else null, "bell": 1.05})
		# lapels / collar strips along the V
		var yN := y1 - 0.004 * k
		if kind != "cardigan":
			for s in [1.0, -1.0]:
				var edge := func(t: float) -> Array:
					var y := Sk.lerp_(yV, yN, t)
					var tt := Sk.smooth(yV, yN, y)
					return [s * v_ang * pow(tt, 0.8), y]
				var fo := func(u):
					var e: Array = edge.call(u)
					var w := Sk.lerp_(6, 30, sin(minf(1.0, u * 1.25) * PI / 2.0)) * (Sk.lerp_(1, 0.6, (u - 0.8) / 0.2) if u > 0.8 else 1.0)
					return [e[0] + s * w, e[1] - 0.004 * k * u]
				torso_patch(edge, fo, {"off": 0.016 * k, "cols": 10, "rows": 2, "color": H.orr(o.get("lapel"), o.get("topColor"))})
			# back collar band
			torso_patch(func(u): return [Sk.lerp_(30, 330, u), yN + 0.034 * k], func(u): return [Sk.lerp_(30, 330, u), yN - 0.02 * k], {"off": 0.017 * k, "cols": 18, "rows": 2, "color": H.orr(o.get("lapel"), o.get("topColor"))})
		else:
			# cardigan: ribbed front bands
			for s in [1.0, -1.0]:
				var fi := func(u):
					var y := Sk.lerp_(jHem, yN, u)
					var tt := Sk.smooth(yV, yN, y)
					return [s * (v_ang * pow(tt, 0.8) + 0.5), y]
				var fo := func(u):
					var y := Sk.lerp_(jHem, yN, u)
					var tt := Sk.smooth(yV, yN, y)
					return [s * (v_ang * pow(tt, 0.8) + 9.0), y]
				torso_patch(fi, fo, {"off": 0.014 * k, "cols": 14, "rows": 1, "color": H.orr(o.get("band"), o.get("topColor"))})
		# shirt collar points
		for s in [1.0, -1.0]:
			torso_patch(func(u): return [s * Sk.lerp_(4, 40, u), yN + 0.012 * k - u * 0.006 * k], func(u): return [s * Sk.lerp_(10, 30, u), yN - 0.035 * k + u * 0.02 * k], {"off": 0.012 * k, "cols": 4, "rows": 2, "color": H.orr(o.get("shirt"), "#eeebe6")})
		# tie or ribbon
		var sp_y: float = B.bind_pos(b.spine)[1]
		if H.truthy(o.get("tie")):
			var pts: Array = []
			for i in 7:
				var y := Sk.lerp_(yN - 0.018 * k, yV - 0.05 * k, i / 6.0)
				var p := torso_pt(P.outer, 0.0, y, 0.008 * k)
				pts.append(Vector3(p[0], p[1] - sp_y, p[2]))
			add(Sk.sweep(pts, func(t): return (0.022 + 0.022 * t) * k * (0.6 if t > 0.93 else 1.0), func(_t): return 0.005 * k, func(_p): return Vector3(0, 0, 1), 4), {"bone": b.spine, "color": o.tie, "weights": torso_weights()})
			var kp := torso_pt(P.outer, 0.0, yN - 0.012 * k, 0.012 * k)
			add(Sk.ellipsoid(0.013 * k, 0.012 * k, 0.008 * k, [kp[0], kp[1] - sp_y, kp[2]], 8, 6), {"bone": b.spine, "color": o.tie, "weights": torso_weights()})
		if H.truthy(o.get("ribbon")):
			var kp := torso_pt(P.outer, 0.0, yN - 0.03 * k, 0.014 * k)
			var kc := [kp[0], kp[1] - sp_y, kp[2]]
			add(Sk.ellipsoid(0.011 * k, 0.011 * k, 0.008 * k, kc, 8, 6), {"bone": b.spine, "color": o.ribbon, "weights": torso_weights()})
			for s in [1.0, -1.0]:
				add(Sk.ellipsoid(0.024 * k, 0.012 * k, 0.007 * k, [kc[0] + s * 0.021 * k, kc[1] + 0.002, kc[2] - 0.002], 8, 6), {"bone": b.spine, "color": o.ribbon, "weights": torso_weights()})
				var pts := Sk.curve([[kc[0] + s * 0.003, kc[1] - 0.004, kc[2]], [kc[0] + s * 0.012 * k, kc[1] - 0.035 * k, kc[2] + 0.002], [kc[0] + s * 0.016 * k, kc[1] - 0.055 * k, kc[2] - 0.002]], 4)
				add(Sk.sweep(pts, func(_t): return 0.016 * k, func(_t): return 0.004 * k, func(_p): return Vector3(0, 0, 1), 4), {"bone": b.spine, "color": o.ribbon, "weights": torso_weights()})
		# buttons
		var btn = H.orr(o.get("buttons"), o.get("band") if kind == "cardigan" else null)
		if H.truthy(btn):
			var nb := 4 if kind == "staff" else (4 if kind == "cardigan" else 2)
			for i in nb:
				var y := Sk.lerp_(yV - 0.02 * k, jHem + 0.06 * k, 0.0 if nb == 1 else float(i) / (nb - 1) * (0.45 if kind == "blazer" else 0.9))
				var s := -1.0 if kind == "cardigan" else 1.0
				var p := torso_pt(P.outer, s * (4.5 if kind == "cardigan" else 6.0) * DEG, y, 0.017 * k)
				add(Sk.ellipsoid(0.0065 * k, 0.0065 * k, 0.0035 * k, [p[0], p[1] - sp_y, p[2]], 6, 4), {"bone": b.spine, "color": H.orr(o.get("buttonColor"), btn), "weights": torso_weights()})
				if kind == "staff":
					var p2 := torso_pt(P.outer, -6 * DEG * s, y, 0.017 * k)
					add(Sk.ellipsoid(0.0065 * k, 0.0065 * k, 0.0035 * k, [p2[0], p2[1] - sp_y, p2[2]], 6, 4), {"bone": b.spine, "color": H.orr(o.get("buttonColor"), btn), "weights": torso_weights()})
		# breast pocket / emblem / name tag
		if H.truthy(o.get("emblem")):
			var p := torso_pt(P.outer, 26 * DEG, P.chest + 0.04 * k, 0.014 * k)
			add(Sk.rbox(0.04 * k, 0.04 * k, 0.004 * k, 0, [p[0], p[1] - sp_y, p[2]]), {"bone": b.spine, "color": o.emblem, "weights": torso_weights(), "matrix": null})
		if H.truthy(o.get("nameTag")):
			var p := torso_pt(P.outer, -26 * DEG, P.chest + 0.05 * k, 0.015 * k)
			add(Sk.rbox(0.055 * k, 0.018 * k, 0.004 * k, 0, [p[0], p[1] - sp_y, p[2]]), {"bone": b.spine, "color": o.nameTag, "weights": torso_weights()})
		if H.truthy(o.get("pockets")):
			for s in [1.0, -1.0]:
				var p := torso_pt(P.outer, s * 42 * DEG, jHem + 0.07 * k, 0.014 * k)
				add(Sk.rbox(0.07 * k, 0.012 * k, 0.005 * k, 0, [p[0], p[1] - sp_y, p[2]]), {"bone": b.spine, "color": H.orr(o.get("lapel"), o.get("topColor")), "weights": torso_weights(), "matrix": Transform3D(Basis(Vector3(0, 1, 0), s * 0.55), Vector3.ZERO)})

	func _simple_top(o: Dictionary) -> void:
		var k: float = P.k
		var y1: float = P.torso[P.torso.size() - 1][0]
		var tucked := H.truthy(o.get("tucked"))
		var top: String = o.top
		var knit: bool = top == "sweater" or top == "hoodie"
		var y0: float = P.waist - 0.02 * k if tucked else P.waist - (0.13 if top == "hoodie" else 0.09) * k
		torso_garment({"y0": y0, "y1": y1, "color": o.get("topColor"), "off": (0.01 if knit else 0.005) * k, "hemFlare": 0.0 if tucked else 0.008 * k, "tab": P.torso if tucked else P.outer})
		if knit:
			torso_patch(func(u): return [Sk.lerp_(-180, 180, u), y0 + 0.028 * k], func(u): return [Sk.lerp_(-180, 180, u), y0 - 0.002], {"off": 0.016 * k, "cols": 20, "rows": 1, "color": H.orr(o.get("band"), o.get("topColor"))})
		sleeves({"color": o.get("topColor"), "loose": 1.3 if top == "hoodie" else 1.18, "short": o.get("shortSleeve"), "skin": spec.get("skin"), "rolled": o.get("rolled"), "cuff": {"h": 0.03, "color": H.orr(o.get("band"), o.get("topColor"))} if knit else null})
		var sp_y: float = B.bind_pos(b.spine)[1]
		var yN := y1 - 0.004 * k
		if H.truthy(o.get("collar")):
			for s in [1.0, -1.0]:
				torso_patch(func(u): return [s * Sk.lerp_(4, 70, u), yN + 0.014 * k], func(u): return [s * Sk.lerp_(14, 40, u), yN - 0.03 * k + u * 0.022 * k], {"off": 0.014 * k, "cols": 5, "rows": 2, "color": o.collar})
		if top == "hoodie":
			# hood bunched behind the neck + drawstrings
			var p := torso_pt(P.outer, PI, yN - 0.03 * k, 0.03 * k)
			add(Sk.ellipsoid(0.13 * k, 0.07 * k, 0.07 * k, [p[0], p[1] - sp_y + 0.02 * k, p[2] + 0.01 * k], 14, 8, func(x, y, z, _u, _v): return [x, y, z + x * x * 2.2]), {"bone": b.spine, "color": o.get("topColor"), "weights": torso_weights()})
			for s in [1.0, -1.0]:
				var q := torso_pt(P.outer, s * 12 * DEG, yN - 0.02 * k, 0.012 * k)
				var pts := Sk.curve([[q[0], q[1] - sp_y, q[2]], [q[0] + s * 0.004, q[1] - sp_y - 0.06 * k, q[2] + 0.012 * k], [q[0] + s * 0.006, q[1] - sp_y - 0.12 * k, q[2] + 0.018 * k]], 4)
				add(Sk.sweep(pts, func(_t): return 0.006 * k, func(_t): return 0.006 * k, func(_p): return Vector3(0, 0, 1), 4), {"bone": b.spine, "color": H.orr(o.get("band"), "#e6e3dd"), "weights": torso_weights()})
			var pp := torso_pt(P.outer, 0.0, P.waist - 0.05 * k, 0.017 * k)
			add(Sk.rbox(0.16 * k, 0.07 * k, 0.012 * k, 0, [pp[0], pp[1] - sp_y, pp[2] - 0.004]), {"bone": b.spine, "color": o.get("topColor"), "weights": torso_weights()})
		if top == "sweater" and H.truthy(o.get("shirtCollar")):
			for s in [1.0, -1.0]:
				torso_patch(func(u): return [s * Sk.lerp_(2, 50, u), yN + 0.01 * k], func(u): return [s * Sk.lerp_(14, 30, u), yN - 0.035 * k + u * 0.022 * k], {"off": 0.016 * k, "cols": 4, "rows": 2, "color": o.shirtCollar})

	func _apron(a: Dictionary) -> void:
		var k: float = P.k
		var y1: float = P.chest + 0.07 * k
		var yW: float = P.waist + 0.01 * k
		var yH: float = a.hem * k
		# bib (chest -> waist) on the torso
		torso_patch(func(u): return [Sk.lerp_(-38, 38, u), y1], func(u): return [Sk.lerp_(-44, 44, u), yW], {"off": 0.02 * k, "cols": 8, "rows": 3, "color": a.color})
		# skirt panel (waist -> hem) as its own surface, attached to hips + thighs
		var g := Sk.surface(12, 6, func(u: float, v: float) -> Array:
			var y := Sk.lerp_(yW, yH, v)
			var ph := Sk.lerp_(-62, 62, u) * DEG * Sk.lerp_(1, 0.9, v)
			var pab := H.prof(P.torso, y) if y > P.hipJy else H.prof(P.pelvis, P.hipJy)
			var r := (1.0 if y > P.hipJy else 1.25) + 0.12 * v
			return [sin(ph) * (pab[0] * r + 0.02 * k), y - P.hip, cos(ph) * (pab[1] * r + 0.03 * k) + v * 0.02 * k])
		var wts := func(lx, ly, _lz, _s = 0.0, _i = 0) -> Array:
			var v := Sk.clamp_((yW - P.hip - ly) / (yW - yH), 0.0, 1.0)
			var w := Sk.smooth(0.2, 1.0, v)
			var side = b.thighL if lx > 0 else b.thighR
			return [[b.hips, 1.0 - w * 0.6], [side, w * 0.3], [b.thighR if lx > 0 else b.thighL, w * 0.3]]
		add(g, {"bone": b.hips, "color": a.color, "weights": wts})
		# neck strap + waist ties
		for s in [1.0, -1.0]:
			var pts: Array = []
			for i in 6:
				var t := i / 5.0
				var ph := Sk.lerp_(s * 36, s * 150, t) * DEG
				var y := Sk.lerp_(y1, P.neck - 0.005 * k, sin(t * PI / 2.0))
				var p := torso_pt(P.outer, ph, y, 0.016 * k)
				pts.append(Vector3(p[0], p[1] - B.bind_pos(b.spine)[1], p[2]))
			add(Sk.sweep(pts, func(_t): return 0.012 * k, func(_t): return 0.003 * k, func(p): return Vector3(p.x, 0, p.z).normalized(), 4), {"bone": b.spine, "color": H.orr(a.get("strap"), a.color), "weights": torso_weights()})
		var bk := torso_pt(P.outer, PI, yW, 0.02 * k)
		var sp: float = B.bind_pos(b.spine)[1]
		for s in [1.0, -1.0]:
			add(Sk.ellipsoid(0.03 * k, 0.012 * k, 0.008 * k, [bk[0] + s * 0.025 * k, bk[1] - sp, bk[2] - 0.004], 8, 5), {"bone": b.spine, "color": H.orr(a.get("strap"), a.color), "weights": torso_weights()})
		# waist band around the body
		torso_patch(func(u): return [Sk.lerp_(-180, 180, u), yW + 0.012 * k], func(u): return [Sk.lerp_(-180, 180, u), yW - 0.012 * k], {"off": 0.021 * k, "cols": 22, "rows": 1, "color": H.orr(a.get("strap"), a.color)})
		if H.truthy(a.get("pocket")):
			var p := torso_pt(P.outer, 0.0, yW + 0.05 * k, 0.023 * k)
			add(Sk.rbox(0.1 * k, 0.05 * k, 0.004 * k, 0, [p[0], p[1] - sp, p[2]]), {"bone": b.spine, "color": a.pocket, "weights": torso_weights()})

	# -------------------------------------------------------------- attachments (props)
	## Extra bone for a prop (e.g. book page).
	func prop_bone(bname: String, parent, x: float, y: float, z: float):
		var bn = B.bone(bname, parent, x, y, z)
		extraBones[bname] = bn
		return bn
