# trains/car.js: one 18 m EMU car in its own frame: cab (if any) toward local +X, gangway end toward
# -X, left side = -Z. Everything goes into Buckets (vertex-coloured, merged later).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const Builder = preload("res://addons/sakuragaoka_station/world/trains/builder.gd")
const People = preload("res://addons/sakuragaoka_station/world/trains/people.gd")

const HW := 1.40
const YB := 1.02
const YS := 3.40
const YR := 3.80
const FLOOR := 1.30
const WALL_T := 0.08
const XE := -8.80
const XS := 8.35
const RH := YR - YS
const PR := 3.2
const Y_BAND0 := 1.78
const Y_BAND1 := 2.02
const Y_MINT0 := 2.05
const Y_MINT1 := 2.09
const DOOR_HW := 0.65
const DOOR_TOP := 3.15
const LEAF_W := 0.68
const DOORS := [-6.0, 0.0, 6.0]
const WIN_Y0 := 2.15
const WIN_Y1 := 3.02
const WINDOWS := [
	{"x0": -8.55, "x1": -7.45, "pri": true},
	{"x0": -4.60, "x1": -3.10}, {"x0": -2.90, "x1": -1.40},
	{"x0": 1.40, "x1": 2.90}, {"x0": 3.10, "x1": 4.60},
]
const CREW := {"x0": 7.36, "x1": 7.92}
const CREW_WIN := {"x0": 7.46, "x1": 7.82, "y0": 2.3, "y1": 2.98}
const CAB_WIN := {"x0": 7.99, "x1": 8.29, "y0": 2.2, "y1": 3.0}
const CAB_BACK := 7.02
const BOGIE_X := 6.1
const WHEEL_R := 0.43
const WHEELBASE := 2.1

const COL := {
	"cream": "#f2ece0", "pink": "#ee9dbb", "mint": "#86cdbb", "roof": "#b7bcc3", "roofDark": "#9ca2aa", "reveal": "#ddd6ca", "mask": "#3b3a4c",
	"metal": "#c6ccd3", "metalDark": "#7e858e", "under": "#595e67", "bogie": "#50545c", "rubber": "#3e3c47", "spring": "#6e747d",
	"wallIn": "#ece7dd", "floor": "#a9a196", "floorDoor": "#c3b8a2", "ceiling": "#f0eee8", "seat": "#c46a86", "seatPri": "#5f80b2", "seatBase": "#8f959c",
	"partition": "#dfe2e4", "yellow": "#f2c230", "cabIn": "#5d6674", "console": "#4b5463", "leafIn": "#d8d6d0", "ring": "#f1eee6", "ringPri": "#f0a441",
}


static func clampv(v: float, a: float, b: float) -> float:
	return maxf(a, minf(b, v))


static func se(q: float, n: float) -> float:
	return pow(maxf(0.0, 1.0 - pow(minf(1.0, absf(q)), n)), 1.0 / n)


static func roof_y(z: float) -> float:
	return YS + RH * se(z / HW, PR)


static func roof_normal(z: float) -> Array:
	var q := minf(1.0, absf(z) / HW)
	var t := maxf(0.0, (roof_y(z) - YS) / RH)
	var gz := (PR / HW) * pow(q, PR - 1.0) * T.sign(z)
	var gy := (PR / RH) * pow(t, PR - 1.0)
	var l := sqrt(gz * gz + gy * gy)
	if l == 0.0:
		l = 1.0
	return [gz / l, gy / l]


static func roof_profile(th0: float, th1: float, n: int) -> Dictionary:
	var pts := []
	var nrm := []
	for i in n + 1:
		var th := th0 + (th1 - th0) * i / n
		var c := cos(th)
		var s := sin(th)
		var z := HW * T.sign(c) * pow(absf(c), 2.0 / PR)
		var y := YS + RH * pow(absf(s), 2.0 / PR)
		pts.append([z, y])
		nrm.append(roof_normal(1e-6 if z == 0.0 else z))
	return {"pts": pts, "nrm": nrm}


# ------------------------------------------------------------------ nose surface (cab at +X)
const D0 := 0.45
const BOW := 0.06
const RV := 0.38
const NPLAN := 4.2
const RAKE := 0.30


static func nose_depth(u: float, y: float) -> float:
	var q := minf(1.0, absf(u))
	var plan := se(q, NPLAN)
	var ry := roof_y(u * HW)
	var t := clampv((ry - y) / RV, 0.0, 1.0)
	var sv := pow(maxf(0.0, 1.0 - pow(1.0 - t, 2.2)), 1.0 / 2.2)
	var k := clampv((y - 2.1) / (YR - 2.1), 0.0, 1.0)
	var rake := RAKE * pow(k, 1.3)
	var kb := clampv((1.3 - y) / 0.28, 0.0, 1.0)
	var tuck := 0.06 * kb * kb
	return (D0 - rake - tuck + BOW * (1.0 - q * q)) * plan * sv


static func nose(u: float, y: float) -> Dictionary:
	var p := Vector3(XS + nose_depth(u, y), y, u * HW)
	var e := 1e-3
	var ua := maxf(-1.0, u - e)
	var ub := minf(1.0, u + e)
	var Xz := (nose_depth(ub, y) - nose_depth(ua, y)) / ((ub - ua) * HW)
	var Xy := (nose_depth(u, y + e) - nose_depth(u, y - e)) / (2.0 * e)
	var n := Vector3(1, -Xy, -Xz)
	if not is_finite(n.length_squared()) or n.length_squared() < 1e-12:
		var sg := T.sign(u)
		n = Vector3(0, 0, sg if sg != 0.0 else 1.0)
	n = n.normalized()
	return {"p": p, "n": n}


static var _U = null


static func U() -> Array:
	if _U == null:
		_U = []
		for i in 33:
			var a := -1.0 + 2.0 * i / 32.0
			_U.append(sin(a * PI / 2.0))
	return _U


static func row_at(y: float, uA: float, uB: float, extra: Array = []) -> Array:
	var us := [uA, uB]
	for u in U() + extra:
		if u > uA + 0.005 and u < uB - 0.005:
			us.append(u)
	us.sort()
	var out := []
	for u in us:
		if out.is_empty() or u - out[out.size() - 1][0] > 1e-5:
			out.append([u, y])
	return out


static func rr_half(y: float, hz: float, y0: float, y1: float, r: float) -> float:
	var dy := maxf(0.0, maxf(y0 + r - y, y - (y1 - r)))
	return hz - r + sqrt(maxf(0.0, r * r - dy * dy))


const MASK := {"hz": 1.31, "y0": 2.12, "y1": 3.40, "r": 0.26}
const GLS := {"hz": 1.20, "y0": 2.24, "y1": 3.28, "r": 0.16}


static func mU(y: float) -> float:
	return rr_half(y, MASK.hz, MASK.y0, MASK.y1, MASK.r) / HW


static func gU(y: float) -> float:
	return rr_half(y, GLS.hz, GLS.y0, GLS.y1, GLS.r) / HW


static func mid_levels() -> Array:
	var s := [MASK.y0, MASK.y1, GLS.y0, GLS.y1]
	for i in 8:
		var c := 1.0 - cos((i / 7.0) * PI / 2.0)
		s.append(MASK.y0 + MASK.r * c)
		s.append(MASK.y1 - MASK.r * c)
		s.append(GLS.y0 + GLS.r * c)
		s.append(GLS.y1 - GLS.r * c)
	var y: float = MASK.y0
	while y < MASK.y1:
		s.append(y)
		y += 0.12
	var a := []
	for v in s:
		if v >= MASK.y0 - 1e-6 and v <= MASK.y1 + 1e-6 and not a.has(v):
			a.append(v)
	a.sort()
	var out := []
	for v in a:
		if out.is_empty() or v - out[out.size() - 1] > 0.004:
			out.append(v)
		elif v == MASK.y1 or v == GLS.y0 or v == GLS.y1:
			out[out.size() - 1] = v
	return out


static func _nose_fn() -> Callable:
	return func(u: float, y: float) -> Dictionary: return nose(u, y)


static func build_nose(B, o: Dictionary) -> void:
	var nf := _nose_fn()
	var YM := mid_levels()
	var between := func(a: float, b: float) -> Array:
		var r := []
		for y in YM:
			if y >= a - 1e-6 and y <= b + 1e-6:
				r.append(y)
		return r
	var patches := []  # {rows, col, key}
	var exB := [-mU(MASK.y0), mU(MASK.y0)]
	var bands := [
		{"y": [YB, 1.05, 1.1, 1.17, 1.25, 1.35, 1.47, 1.6, 1.7, Y_BAND0], "col": COL.cream},
		{"y": [Y_BAND0, 1.86, 1.94, Y_BAND1], "col": COL.pink},
		{"y": [Y_BAND1, Y_MINT0], "col": COL.cream},
		{"y": [Y_MINT0, Y_MINT1], "col": COL.mint},
		{"y": [Y_MINT1, MASK.y0], "col": COL.cream},
	]
	for b in bands:
		var rows := []
		for y in b.y:
			rows.append(row_at(y, -1, 1, exB))
		patches.append({"rows": rows, "col": b.col, "noLining": true})
	var rows_l := []
	var rows_r := []
	for y in YM:
		rows_l.append(row_at(y, -1, -mU(y)))
		rows_r.append(row_at(y, mU(y), 1))
	patches.append({"rows": rows_l, "col": COL.cream})
	patches.append({"rows": rows_r, "col": COL.cream})
	var exG0 := [-gU(GLS.y0), gU(GLS.y0)]
	var exG1 := [-gU(GLS.y1), gU(GLS.y1)]
	var r0 := []
	for y in between.call(MASK.y0, GLS.y0):
		r0.append(row_at(y, -mU(y), mU(y), exG0))
	patches.append({"rows": r0, "col": COL.mask})
	var r1 := []
	for y in between.call(GLS.y1, MASK.y1):
		r1.append(row_at(y, -mU(y), mU(y), exG1))
	patches.append({"rows": r1, "col": COL.mask})
	var r2 := []
	var r3 := []
	for y in between.call(GLS.y0, GLS.y1):
		r2.append(row_at(y, -mU(y), -gU(y)))
		r3.append(row_at(y, gU(y), mU(y)))
	patches.append({"rows": r2, "col": COL.mask})
	patches.append({"rows": r3, "col": COL.mask})
	# cap (top of the nose, curving into the roof)
	var S := [0, 0.1, 0.22, 0.36, 0.5, 0.64, 0.77, 0.88, 0.95, 1]
	var exC := [-mU(MASK.y1), mU(MASK.y1)]
	var cap_rows := []
	for s in S:
		var row := []
		for uy in row_at(0, -1, 1, exC):
			var u: float = uy[0]
			row.append([u, MASK.y1 + s * (roof_y(u * HW) - MASK.y1) - (1e-4 if s == 1 else 0.0)])
		cap_rows.append(row)
	patches.append({"rows": cap_rows, "col": COL.cream})
	for p in patches:
		B.add("paint", Builder.rows_surface(p.rows, nf, 0), null, p.col)
		if not p.get("noLining"):
			B.add("interior", Builder.rows_surface(p.rows, nf, -0.02, true), null, COL.cabIn)
	# glass
	var gr := []
	for y in between.call(GLS.y0, GLS.y1):
		gr.append(row_at(y, -gU(y), gU(y)))
	B.add("glass", Builder.rows_surface(gr, nf, -0.012), null, "#ffffff")

	B.tag = "noseparts"
	var on_face := func(u: float, y: float, off: float) -> Transform3D:
		var s := nose(u, y)
		return Builder.basis((s.p as Vector3) + (s.n as Vector3) * off, s.n)
	# light cases, headlights, taillights
	for sg in [-1, 1]:
		# one rounded light case per side; lenses coplanar with its front face (local +x = toward -Z)
		B.push(on_face.call(sg * 0.682, 1.6, -0.014))
		B.rbox("matte", 0.54, 0.2, 0.07, 0.09, [0, 0, 0], "#4a4759")
		var hx: float = sg * 0.14
		var tx: float = -sg * 0.165
		B.add("head" if o.lit == "head" else "metal", Builder.geo_circle(24), Builder.M([hx, 0, 0.037], null, [0.152, 0.152, 1]), "#ffffff" if o.lit == "head" else "#c9d3dc")
		B.add("metal", Builder.geo_torus(0.079, 0.009, 4, 24), Builder.M([hx, 0, 0.036]), COL.metal)
		B.add("tail" if o.lit == "tail" else "metal", Builder.geo_circle(20), Builder.M([tx, 0, 0.037], null, [0.104, 0.104, 1]), "#ffffff" if o.lit == "tail" else "#c4505c")
		B.add("metal", Builder.geo_torus(0.054, 0.007, 4, 20), Builder.M([tx, 0, 0.036]), COL.metal)
		B.pop()
	# emblem on the band, car number below
	B.push(on_face.call(0, 1.905, 0.006)); B.decal("decal", 0.22, 0.22, o.uv.dec.call("emblem")); B.pop()
	B.push(on_face.call(0, 1.6, 0.006)); B.decal("decal", 0.3, 0.075, o.uv.dec.call(o.numFront)); B.pop()
	# destination + run number displays behind the glass (flat, facing +X)
	var glass_x := func(u0: float, u1: float, y: float) -> float:
		return minf(minf(nose(u0, y).p.x, nose(u1, y).p.x), nose((u0 + u1) / 2.0, y).p.x) - 0.012
	if true:
		var zc := 0.2
		var w := 1.28
		var h := 0.32
		var y := 3.1
		var x: float = minf(glass_x.call((zc - w / 2) / HW, (zc + w / 2) / HW, y + h / 2), glass_x.call((zc - w / 2) / HW, (zc + w / 2) / HW, y - h / 2)) - 0.03
		B.box("matte", 0.04, h + 0.06, w + 0.06, [x - 0.025, y, zc], "#2b2a33")
		B.push(Builder.M([x, y, zc], [0, PI / 2, 0])); B.decal("led", w, h, o.uv.led.call(o.destKey)); B.pop()
		var z2 := -0.86
		var w2 := 0.34
		var h2 := 0.17
		var x2: float = glass_x.call((z2 - w2 / 2) / HW, (z2 + w2 / 2) / HW, y) - 0.03
		B.box("matte", 0.04, h2 + 0.05, w2 + 0.05, [x2 - 0.025, y, z2], "#2b2a33")
		B.push(Builder.M([x2, y, z2], [0, PI / 2, 0])); B.decal("led", w2, h2, o.uv.led.call(o.runKey)); B.pop()
	# wipers (parked along the bottom of the windscreen)
	for ul in [[-0.44, 0.47], [0.2, 0.47]]:
		var u0: float = ul[0]
		var length: float = ul[1]
		var a := nose(u0, 2.31)
		var b := nose(u0 + length, 2.36)
		var pa: Vector3 = a.p + a.n * 0.024
		var pb: Vector3 = b.p + b.n * 0.024
		B.rod("matte", pa, pb, 0.011, "#3c3f48", 6)
		var qa: Vector3 = a.p + a.n * 0.012 + Vector3(0, 0.012, 0)
		var qb: Vector3 = b.p + b.n * 0.012 + Vector3(0, 0.012, 0)
		B.rod("matte", qa, qb, 0.007, "#2f3038", 4)
		B.push(Builder.basis(a.p + a.n * 0.012, a.n)); B.cyl("metal", 0.028, 0.028, 0.03, [0, 0, 0], "#5c616a", [PI / 2, 0, 0], 10); B.pop()
	B.tag = "skirt"
	# front skirt (排障器): curved plate under the nose with a coupler gap
	var skirt_p := func(u: float, y: float) -> Dictionary:
		var f := func(uu: float, yy: float) -> Vector3: return Vector3(XS - 0.30 + 0.70 * se(uu, 2.6) + 0.06 * (1.0 - (yy - 0.36) / 0.64), yy, uu * 1.3)
		var p: Vector3 = f.call(u, y)
		var e := 1e-3
		var pu: Vector3 = (f.call(minf(1.0, u + e), y) as Vector3) - (f.call(maxf(-1.0, u - e), y) as Vector3)
		var pv: Vector3 = (f.call(u, y + e) as Vector3) - (f.call(u, y - e) as Vector3)
		var n := pv.cross(pu).normalized()
		if n.x < 0.0:
			n = -n
		return {"p": p, "n": n}
	var SY := [0.36, 0.46, 0.58, 0.7, 0.82, 0.92, 1.0]
	var halves := [[-1.0, -0.2], [0.2, 1.0]]
	for ab in halves:
		var rows := []
		for y in SY:
			rows.append(row_at(y, ab[0], ab[1]))
		B.add("metal", Builder.rows_surface(rows, skirt_p, 0), null, "#9ca2aa")
		B.add("matte", Builder.rows_surface(rows, skirt_p, -0.025, true), null, "#5a5f68")
	if true:
		var rows := []
		for y in [0.36, 0.46, 0.56]:
			rows.append(row_at(y, -0.2, 0.2))
		B.add("metal", Builder.rows_surface(rows, skirt_p, 0), null, "#9ca2aa")
		B.add("matte", Builder.rows_surface(rows, skirt_p, -0.025, true), null, "#5a5f68")
	# skirt stiffener ribs
	for u in [-0.62, 0.62]:
		var s: Dictionary = skirt_p.call(u, 0.68)
		B.push(Builder.basis((s.p as Vector3) + (s.n as Vector3) * -0.06, s.n)); B.box("matte", 0.05, 0.56, 0.1, [0, 0, 0], "#4a4e57"); B.pop()
	# coupler (密着連結器) + electric coupler + hoses
	B.box("metal", 0.62, 0.12, 0.14, [XS + 0.33, 0.86, 0], "#50555e")
	B.rbox("metal", 0.24, 0.26, 0.3, 0.03, [XS + 0.72, 0.86, 0], "#5a5f68")
	B.box("matte", 0.02, 0.18, 0.2, [XS + 0.845, 0.86, 0], "#3a3346")
	B.rbox("matte", 0.2, 0.14, 0.34, 0.03, [XS + 0.66, 0.66, 0], "#454952")
	for zc in [[-0.3, "#d9463b"], [0.3, "#f2c230"]]:
		var z: float = zc[0]
		B.tube("matte", [[XS + 0.3, 0.8, z], [XS + 0.46, 0.66, z * 1.1], [XS + 0.52, 0.5, z * 1.15]], 0.025, "#2f3038", 10, 6)
		B.box("matte", 0.06, 0.03, 0.08, [XS + 0.28, 0.83, z], zc[1])
	B.tag = "cab"
	# cab interior: raised floor, console, instrument panel, seat, partition, driver / conductor
	B.box("interior", XS + 0.25 - CAB_BACK, 0.2, 2.6, [(XS + 0.25 + CAB_BACK) / 2, FLOOR + 0.1, 0], "#555c69")
	B.box("interior", 0.5, 0.72, 2.46, [XS + 0.06, FLOOR + 0.2 + 0.36, 0], COL.console)
	B.push(Builder.M([XS + 0.02, 2.24, 0], [0, 0, 0.35]))
	B.box("interior", 0.36, 0.05, 2.3, [0, 0, 0], "#434b58")
	B.pop()
	if true:
		var s := Builder.basis(Vector3(XS - 0.02, 2.29, -0.45), Vector3(-0.35, 1, 0).normalized())
		B.push(s); B.decal("led", 0.34, 0.17, o.uv.led.call("cab")); B.pop()
		var s2 := Builder.basis(Vector3(XS - 0.02, 2.29, 0.05), Vector3(-0.35, 1, 0).normalized())
		B.push(s2); B.decal("led", 0.3, 0.15, o.uv.led.call("cab2")); B.pop()
	B.box("metal", 0.08, 0.14, 0.05, [XS - 0.16, 2.34, -0.78], "#2f3038")
	B.cyl("metal", 0.018, 0.018, 0.22, [XS - 0.16, 2.44, -0.78], "#9aa1a8", [PI / 2, 0, 0], 8)
	# driver's seat
	B.rbox("interior", 0.45, 0.1, 0.45, 0.04, [XS - 0.62, 1.95, -0.52], "#3f4758")
	B.rbox("interior", 0.08, 0.55, 0.45, 0.04, [XS - 0.88, 2.28, -0.52], "#3f4758", [0, 0, 0.12])
	B.cyl("interior", 0.04, 0.04, 0.45, [XS - 0.62, 1.72, -0.52], "#2f3038", null, 8)
	if o.crew == "driver":
		People.person(B, "interior", [XS - 0.6, 2.0, -0.52], PI / 2, {"pose": "sit", "outfit": "staff", "h": 1.7, "hands": true, "glove": "#f4f4f4", "hair": "#3a3240"})
	elif o.crew == "conductor":
		People.person(B, "interior", [XS - 0.45, FLOOR + 0.2, 0.62], PI / 2 + 0.4, {"pose": "stand", "outfit": "staff", "h": 1.66, "hair": "#4a3a36"})
	# partition wall between cab and saloon (3 windows)
	if true:
		var pb := Builder.color_by_normal(Builder.geo_box().clone().scale(0.05, YS + 0.18 - FLOOR, 2.62), func(nx, _ny, _nz, _x, _y, _z): return COL.cabIn if nx > 0.5 else (COL.partition if nx < -0.5 else COL.partition))
		B.add("interior", pb, Builder.M([CAB_BACK, FLOOR + (YS + 0.18 - FLOOR) / 2, 0]), null)
		for wy in [[-0.8, 0.8, 2.3, 3.05], [0, 0.55, 1.5, 3.05], [0.8, 0.8, 2.3, 3.05]]:
			var zc: float = wy[0]
			var w: float = wy[1]
			var y0: float = wy[2]
			var y1: float = wy[3]
			for sx in [-1, 1]:
				B.box("interior", 0.006, y1 - y0, w, [CAB_BACK + sx * 0.028, (y0 + y1) / 2, zc], "#4e5a68")
		B.push(Builder.M([CAB_BACK - 0.03, 3.2, 0], [0, -PI / 2, 0])); B.decal("decal", 0.42, 0.105, o.uv.dec.call("crewSign")); B.pop()
	# cab ceiling
	var cp := [[-1.32, 3.38], [-0.95, 3.6], [0.95, 3.6], [1.32, 3.38]]
	var cn := [[0.51, -0.86], [0, -1], [0, -1], [-0.51, -0.86]]
	B.add("interior", Builder.sweep_x(cp, cn, CAB_BACK, XS + 0.02), null, "#6a7280")


# ------------------------------------------------------------------ side wall pieces
static func wall_pieces(cab: bool) -> Array:
	var out := []
	var doors_desc := DOORS.duplicate()
	doors_desc.sort()
	doors_desc.reverse()
	var doors_asc := DOORS.duplicate()
	doors_asc.sort()
	var x1 := XS if cab else -XE
	# lower (YB..Y_BAND0) with door notches from the top
	if true:
		var pts := [[XE, YB], [x1, YB], [x1, Y_BAND0]]
		for d in doors_desc:
			pts.append_array([[d + DOOR_HW, Y_BAND0], [d + DOOR_HW, FLOOR], [d - DOOR_HW, FLOOR], [d - DOOR_HW, Y_BAND0]])
		pts.append([XE, Y_BAND0])
		out.append({"shape": Builder.shape_from(pts), "col": COL.cream, "rev": COL.reveal})
	# band / gap / mint strips between doors
	var spans := []
	var prev := XE
	for d in doors_asc:
		spans.append([prev, d - DOOR_HW])
		prev = d + DOOR_HW
	spans.append([prev, x1])
	for yyc in [[Y_BAND0, Y_BAND1, COL.pink], [Y_BAND1, Y_MINT0, COL.cream], [Y_MINT0, Y_MINT1, COL.mint]]:
		var y0: float = yyc[0]
		var y1: float = yyc[1]
		for ab in spans:
			var a: float = ab[0]
			var b: float = ab[1]
			out.append({"shape": Builder.shape_from([[a, y0], [b, y0], [b, y1], [a, y1]]), "col": yyc[2], "rev": yyc[2]})
	# upper with door notches from below + window holes
	if true:
		var pts := [[XE, Y_MINT1]]
		for d in doors_asc:
			pts.append_array([[d - DOOR_HW, Y_MINT1], [d - DOOR_HW, DOOR_TOP - 0.04], [d - DOOR_HW + 0.04, DOOR_TOP], [d + DOOR_HW - 0.04, DOOR_TOP], [d + DOOR_HW, DOOR_TOP - 0.04], [d + DOOR_HW, Y_MINT1]])
		pts.append_array([[x1, Y_MINT1], [x1, YS], [XE, YS]])
		var holes := []
		for w in window_rects(cab):
			holes.append(Builder.rrect_pts((w.x0 + w.x1) / 2, (w.y0 + w.y1) / 2, w.x1 - w.x0, w.y1 - w.y0, w.r, 4))
		out.append({"shape": Builder.shape_from(pts, holes), "col": COL.cream, "rev": COL.reveal})
	return out


static func window_rects(cab: bool) -> Array:
	var list := []
	for w in WINDOWS:
		var d: Dictionary = w.duplicate()
		d.merge({"y0": WIN_Y0, "y1": WIN_Y1, "r": 0.07}, true)
		list.append(d)
	if cab:
		var cw: Dictionary = CREW_WIN.duplicate()
		cw.merge({"r": 0.05, "crew": true}, true)
		var bw: Dictionary = CAB_WIN.duplicate()
		bw.merge({"r": 0.05, "cab": true}, true)
		list.append(cw)
		list.append(bw)
	else:
		list.append({"x0": 7.45, "x1": 8.55, "y0": WIN_Y0, "y1": WIN_Y1, "r": 0.07, "pri": true})  # (unused: all cars have a cab)
	return list


# ------------------------------------------------------------------ door leaf
static func leaf(B, xd: float, k: int, side: int, sticker_uv) -> void:
	var x0 := xd - LEAF_W if k == 0 else xd
	var x1 := xd if k == 0 else xd + LEAF_W
	var wx0 := xd - 0.56 if k == 0 else xd + 0.1
	var wx1 := xd - 0.1 if k == 0 else xd + 0.56
	var wy0 := 2.18
	var wy1 := 3.0
	var zT := -(HW - 0.015) if side < 0 else HW - 0.055  # leaf occupies zT..zT+0.04
	var pieces := [
		[1.29, Y_BAND0, COL.cream], [Y_BAND0, Y_BAND1, COL.pink], [Y_BAND1, Y_MINT0, COL.cream], [Y_MINT0, Y_MINT1, COL.mint],
	]
	for pc in pieces:
		var y0: float = pc[0]
		var y1: float = pc[1]
		var col: String = pc[2]
		var g := Builder.color_by_normal(Builder.extrude_shape(Builder.shape_from([[x0, y0], [x1, y0], [x1, y1], [x0, y1]]), 0.04), func(_nx, _ny, nz, _x, _y, _z): return col if nz * side > 0.5 else (COL.leafIn if nz * side < -0.5 else col))
		B.add("paint", g, Builder.M([0, 0, zT]), null)
	var win := Builder.rrect_pts((wx0 + wx1) / 2, (wy0 + wy1) / 2, wx1 - wx0, wy1 - wy0, 0.06, 4)
	var up := Builder.color_by_normal(Builder.extrude_shape(Builder.shape_from([[x0, Y_MINT1], [x1, Y_MINT1], [x1, DOOR_TOP + 0.02], [x0, DOOR_TOP + 0.02]], [win]), 0.04, 4), func(_nx, _ny, nz, _x, _y, _z): return COL.cream if nz * side > 0.5 else (COL.leafIn if nz * side < -0.5 else "#d3cdc2"))
	B.add("paint", up, Builder.M([0, 0, zT]), null)
	B.add("glass", Builder.shape_geo(Builder.shape_from(win)), Builder.M([0, 0, side * (HW - 0.035)]), "#ffffff")
	# leading edge rubber + inner yellow line
	B.box("paint", 0.024, DOOR_TOP + 0.02 - 1.29, 0.046, [xd + (-0.012 if k == 0 else 0.012), (DOOR_TOP + 0.02 + 1.29) / 2, side * (HW - 0.035)], COL.rubber)
	B.box("paint", 0.022, 1.7, 0.004, [xd + (-0.042 if k == 0 else 0.042), 2.25, side * (HW - 0.057)], COL.yellow)
	# sticker on the window (outside)
	if sticker_uv:
		B.push(Builder.M([(wx0 + wx1) / 2 + (0.1 if k == 0 else -0.1), 2.32, side * (HW - 0.031)], [0, PI if side < 0 else 0.0, 0])); B.decal("decal", 0.12, 0.12, sticker_uv); B.pop()


# ------------------------------------------------------------------ the car
## o: { lit:'head'|'tail', animSide:-1|1, carSign:±1, doorsNeg, doorsPos, uv, numFront, numSide,
## destKey, runKey, lcdKey, sideKey, panto:bool, motor:bool, rng, crew:'driver'|'conductor',
## jakurei:bool, lamps: [] (out, car frame), wheelsets: [] (out, car frame) }
static func build_car(B, o: Dictionary) -> void:
	var r = o.rng
	var cab := true
	B.tag = "walls"
	# ---------------- side walls
	for side in [-1, 1]:
		for pc in wall_pieces(cab):
			var g := Builder.color_by_normal(Builder.extrude_shape(pc.shape, WALL_T, 4), func(_nx, _ny, nz, _x, _y, _z): return pc.col if nz * side > 0.5 else (COL.wallIn if nz * side < -0.5 else pc.rev))
			B.add("paint", g, Builder.M([0, 0, -HW if side < 0 else HW - WALL_T]), null)
		# window frames + glass
		for w in window_rects(cab):
			var cx: float = (w.x0 + w.x1) / 2
			var cy: float = (w.y0 + w.y1) / 2
			var ww: float = w.x1 - w.x0
			var hh: float = w.y1 - w.y0
			var inner := Builder.rrect_pts(cx, cy, ww, hh, w.r, 4)
			var fr := Builder.extrude_shape(Builder.shape_from(Builder.rrect_pts(cx, cy, ww + 0.07, hh + 0.07, w.r + 0.035, 4), [inner]), 0.012, 4)
			B.add("metal", fr, Builder.M([0, 0, -HW - 0.012 if side < 0 else HW]), "#4a4a56" if w.get("crew") or w.get("cab") else COL.metal)
			B.add("glass", Builder.shape_geo(Builder.shape_from(inner)), Builder.M([0, 0, side * (HW - 0.035)]), "#ffffff")
			var face_rot := [0, PI if side < 0 else 0.0, 0]
			if w.get("pri"):
				B.push(Builder.M([cx, 2.27, side * (HW - 0.031)], face_rot)); B.decal("decal", 0.56, 0.14, o.uv.dec.call("priority")); B.pop()
		# doors: leaves (platform side animated), threshold, visor
		for xd in DOORS:
			for k in [0, 1]:
				var anim: bool = side == o.animSide
				var target = B
				if anim:
					var dir_train: float = o.carSign * (-1 if k == 0 else 1)
					target = o.doorsNeg if dir_train < 0 else o.doorsPos
				var st = o.uv.dec.call("doorCaution") if k == 0 else (o.uv.dec.call("mascot") if xd == 0 else o.uv.dec.call("kids"))
				leaf(target, xd, k, side, st)
			B.box("metal", 2 * DOOR_HW, 0.025, WALL_T + 0.02, [xd, FLOOR - 0.0095, side * (HW - WALL_T / 2)], "#b5bbc2")
			B.box("paint", 2 * DOOR_HW - 0.04, 0.022, 0.012, [xd, FLOOR - 0.011, side * (HW + 0.012)], COL.yellow)  # sill edge (足元注意)
			B.box("interior", 2 * DOOR_HW - 0.1, 0.006, 0.06, [xd, FLOOR + 0.003, side * (HW - WALL_T - 0.05)], COL.yellow)
			B.box("interior", 2 * DOOR_HW + 0.3, 0.004, 0.5, [xd, FLOOR + 0.002, side * (HW - WALL_T - 0.33)], COL.floorDoor)
			B.rbox("metal", 2 * DOOR_HW + 0.14, 0.025, 0.05, 0.01, [xd, DOOR_TOP + 0.08, side * (HW + 0.018)], COL.metal)
			# above-door (inside) LCD + route map
			B.box("interior", 1.2, 0.2, 0.04, [xd, DOOR_TOP + 0.14, side * (HW - WALL_T - 0.02)], "#dcdad4")
			var in_rot := [0, 0.0 if side < 0 else PI, 0]
			B.push(Builder.M([xd - 0.3, DOOR_TOP + 0.14, side * (HW - WALL_T - 0.043)], in_rot)); B.decal("led", 0.46, 0.115, o.uv.led.call(o.lcdKey)); B.pop()
			B.push(Builder.M([xd + 0.3, DOOR_TOP + 0.14, side * (HW - WALL_T - 0.043)], in_rot)); B.decal("decal", 0.5, 0.166, o.uv.dec.call("routeMap")); B.pop()
		var face_rot := [0, PI if side < 0 else 0.0, 0]
		var zo: float = side * (HW + 0.005)
		# car number, wordmark, maker plate, emergency sticker
		B.push(Builder.M([XE + 0.75, 1.5, zo], face_rot)); B.decal("decal", 0.52, 0.13, o.uv.dec.call(o.numSide)); B.pop()
		for x in [-3.0, 3.0]:
			B.push(Builder.M([x, 1.46, zo], face_rot)); B.decal("decal", 0.96, 0.24, o.uv.dec.call("wordmark")); B.pop()
		B.push(Builder.M([XE + 1.6, 1.2, zo], face_rot)); B.decal("decal", 0.16, 0.08, o.uv.dec.call("plate")); B.pop()
		B.push(Builder.M([-6.95, 1.55, zo], face_rot)); B.decal("decal", 0.14, 0.07, o.uv.dec.call("emergency")); B.pop()
		# wheelchair / stroller stickers next to the cab-end door
		B.push(Builder.M([7.02, 2.66, zo], face_rot)); B.decal("decal", 0.2, 0.2, o.uv.dec.call("wheelchair")); B.pop()
		B.push(Builder.M([7.02, 2.4, zo], face_rot)); B.decal("decal", 0.2, 0.2, o.uv.dec.call("stroller")); B.pop()
		if o.jakurei:
			B.push(Builder.M([3.85, 2.3, side * (HW - 0.031)], face_rot)); B.decal("decal", 0.3, 0.15, o.uv.dec.call("jakurei")); B.pop()
		# side destination LED (above the window at x≈-2.15)
		B.box("matte", 0.84, 0.19, 0.016, [-2.15, 3.2, side * (HW + 0.004)], "#2b2a33")
		B.push(Builder.M([-2.15, 3.2, side * (HW + 0.0135)], face_rot)); B.decal("led", 0.76, 0.127, o.uv.led.call(o.sideKey)); B.pop()
		# car side lamps (車側灯): red, lit while the doors on this side are open
		for x in [XE + 0.32, CREW.x0 - 0.25]:
			B.rbox("matte", 0.1, 0.1, 0.03, 0.012, [x, 3.27, side * (HW + 0.01)], "#6a3a44")
			if side == o.animSide:
				o.lamps.append([x, 3.27, side * (HW + 0.026)])
		# crew door: outline, grab handles, step
		if true:
			var zz: float = side * (HW + 0.003)
			for whxy in [[0.012, 1.92, CREW.x0, 2.21], [0.012, 1.92, CREW.x1, 2.21], [CREW.x1 - CREW.x0, 0.012, (CREW.x0 + CREW.x1) / 2, 3.17]]:
				B.box("matte", whxy[0], whxy[1], 0.006, [whxy[2], whxy[3], zz], "#8d8a92")
			for x in [CREW.x0 - 0.07, CREW.x1 + 0.05]:
				B.rod("metal", [x, 1.55, side * (HW + 0.05)], [x, 2.75, side * (HW + 0.05)], 0.014, COL.metal, 8)
				for y in [1.6, 2.7]:
					B.rod("metal", [x, y, side * HW], [x, y, side * (HW + 0.05)], 0.01, COL.metal, 6)
			B.box("metal", 0.42, 0.035, 0.09, [(CREW.x0 + CREW.x1) / 2, 0.93, side * (HW + 0.02)], "#7e858e")
			B.rod("metal", [(CREW.x0 + CREW.x1) / 2 - 0.18, 0.95, side * (HW + 0.02)], [(CREW.x0 + CREW.x1) / 2 - 0.18, 1.02, side * (HW - 0.02)], 0.012, "#7e858e", 6)
		# gutter (rain channel) along the roof edge
		B.rbox("metal", XS - XE + 0.02, 0.035, 0.03, 0.01, [(XS + XE) / 2, YS - 0.005, side * (HW + 0.012)], "#d4d8dc")

	B.tag = "roof"
	# ---------------- roof shell (cream shoulders, grey top)
	if true:
		var th1 := PI - acos(pow(1.16 / HW, PR / 2))
		var th2 := acos(pow(1.16 / HW, PR / 2))
		var Lp := roof_profile(PI, th1, 5)
		var Tp := roof_profile(th1, th2, 26)
		var Rp := roof_profile(th2, 0, 5)
		B.add("paint", Builder.sweep_x(Lp.pts, Lp.nrm, XE, XS), null, COL.cream)
		B.add("paint", Builder.sweep_x(Tp.pts, Tp.nrm, XE, XS), null, COL.roof)
		B.add("paint", Builder.sweep_x(Rp.pts, Rp.nrm, XE, XS), null, COL.cream)
		# anti-slip walkway strips
		B.box("matte", XS - XE - 1.2, 0.012, 0.5, [(XS + XE) / 2, YR + 0.002, 0.0], COL.roofDark)
	B.tag = "endwall"
	# ---------------- gangway end wall
	if true:
		var prof: Array = roof_profile(0, PI, 24).pts  # from +HW over the roof to -HW
		var pts := [[-HW, YB], [HW, YB]]
		for zy in prof:
			pts.append([zy[0], zy[1]])
		var g := Builder.color_by_normal(Builder.extrude_shape(Builder.shape_from(pts), 0.06, 4), func(_nx, _ny, nz, _x, _y, _z): return COL.wallIn if nz < -0.5 else COL.cream)
		# shape (sx=z, sy=y, d) -> rotate -90° about Y: x=-d, z=sx  => then shift to x = XE + 0.06
		B.add("paint", g, Builder.M([XE + 0.06, 0, 0], [0, -PI / 2, 0]), null)
		# gangway door panel inside
		B.push(Builder.M([XE + 0.065, 2.25, 0], [0, PI / 2, 0])); B.decal("decal", 0.8, 1.9, o.uv.dec.call("gangway")); B.pop()
		# receptacles / jumper sockets on the outer face
		for z in [-0.95, -0.72, 0.8]:
			B.rbox("matte", 0.08, 0.14, 0.14, 0.02, [XE - 0.03, 1.12, z * o.carSign], "#3f434c")
		B.box("matte", 0.3, 0.14, 0.16, [XE - 0.12, 0.9, 0], "#4a4e57")
		B.push(Builder.M([XE - 0.004, 1.36, -0.84 * o.carSign], [0, -PI / 2, 0])); B.decal("decal", 0.2, 0.1, o.uv.dec.call("jumperWarn")); B.pop()

	B.tag = "under"
	# ---------------- underframe & floor
	B.add("interior", Builder.color_by_normal(Builder.geo_box().clone().scale(XS - XE - 0.06, 0.28, 2 * (HW - WALL_T)), func(_nx, ny, _nz, _x, _y, _z): return COL.floor if ny > 0.5 else COL.under), Builder.M([(XS + XE + 0.06) / 2, YB + 0.14, 0]), null)
	B.box("matte", XS - XE, 0.09, 2 * HW - 0.08, [(XS + XE) / 2, 0.975, 0], COL.under)
	# underfloor equipment boxes
	if true:
		var specs: Array
		if o.motor:
			specs = [[-4.45, -2.85, 0.5, 1.2, 0.2], [-2.6, -1.85, 0.32, 1.1, 0.35], [-1.55, 0.35, 0.52, 1.2, 0.18], [0.6, 1.5, 0.36, 1.05, 0.4], [1.8, 3.35, 0.46, 1.18, 0.22], [3.6, 4.4, 0.3, 1.0, 0.45]]
		else:
			specs = [[-4.4, -3.3, 0.42, 1.15, 0.25], [-3.0, -1.4, 0.3, 1.0, 0.5], [-1.1, 0.2, 0.48, 1.2, 0.2], [0.5, 1.9, 0.34, 1.1, 0.35], [2.2, 3.1, 0.44, 1.15, 0.3], [3.4, 4.4, 0.28, 0.95, 0.5]]
		for side in [-1, 1]:
			for sp in specs:
				var x0: float = sp[0]
				var x1: float = sp[1]
				var h: float = sp[2]
				var z_out: float = sp[3]
				var z_in: float = sp[4]
				var w := x1 - x0
				var zc: float = side * (z_out + z_in) / 2
				var d := z_out - z_in
				var col = r.pick(["#5b5f68", "#63676f", "#555960", "#6d7178"])
				B.rbox("matte", w, h, d, 0.03, [(x0 + x1) / 2, 0.93 - h / 2, zc], col, null, 1)
				# ribs / vents on the outer face
				var nr := maxi(2, floori(w / 0.22))
				if r.chance(0.6):
					for i in nr:
						B.box("matte", 0.03, h * 0.6, 0.012, [x0 + 0.1 + (w - 0.2) * i / maxi(1, nr - 1), 0.93 - h / 2, side * (z_out + 0.004)], "#4a4e56")
				else:
					B.box("matte", w * 0.7, h * 0.5, 0.01, [(x0 + x1) / 2, 0.93 - h / 2, side * (z_out + 0.004)], "#727781")
		# air reservoirs
		for z in [-0.12, 0.3]:
			B.cyl("matte", 0.15, 0.15, 2.2, [2.4 if o.motor else -2.1, 0.7, z], "#6a6e76", [0, 0, PI / 2], 14)
		# pipes
		for zy in [[-0.3, 0.84], [0.25, 0.86], [0.1, 0.8]]:
			B.cyl("matte", 0.025, 0.025, XS - XE - 1.2, [(XS + XE) / 2, zy[1], zy[0]], "#4a4e56", [0, 0, PI / 2], 6)
	B.tag = "bogies"
	# ---------------- bogies
	for bx in [-BOGIE_X, BOGIE_X]:
		var prof := [[-1.38, 0.8], [-1.38, 0.92], [-0.72, 0.92], [-0.5, 0.76], [0.5, 0.76], [0.72, 0.92], [1.38, 0.92], [1.38, 0.8], [0.8, 0.8], [0.56, 0.6], [-0.56, 0.6], [-0.8, 0.8]]
		for side in [-1, 1]:
			B.add("matte", Builder.extrude_shape(Builder.shape_from(prof), 0.14), Builder.M([bx, 0, side * 0.86 - 0.07]), COL.bogie)
			for ax in [-WHEELBASE / 2, WHEELBASE / 2]:
				B.rbox("metal", 0.32, 0.2, 0.2, 0.04, [bx + ax, WHEEL_R + 0.15, side * 0.86], "#5f646c", null, 1)
				B.cyl("metal", 0.07, 0.07, 0.05, [bx + ax, WHEEL_R + 0.15, side * 0.975], "#8a9098", [PI / 2, 0, 0], 12)
				# coil spring
				var pts := []
				var turns := 4.5
				var n := 36
				for i in n + 1:
					var a := (float(i) / n) * turns * PI * 2
					pts.append(Vector3(bx + ax + cos(a) * 0.075, 0.68 + 0.12 * i / n, side * 0.86 + sin(a) * 0.075))
				B.add("metal", Geo.tube_catmull(pts, false, 27, 0.017, 3, false), null, COL.spring)
				# brake unit facing the tread (inboard of each wheel)
				var bxx: float = bx + ax - T.sign(ax) * 0.52
				B.rbox("matte", 0.16, 0.18, 0.14, 0.03, [bxx, 0.6, side * 0.56], "#474b53")
				B.cyl("matte", 0.06, 0.06, 0.16, [bxx - T.sign(ax) * 0.12, 0.62, side * 0.56], "#666b73", [0, 0, PI / 2], 10)
			# air spring (bellows)
			var lp := []
			for p in [[0.16, 0], [0.23, 0.03], [0.25, 0.08], [0.23, 0.13], [0.17, 0.16]]:
				lp.append(Vector2(p[0], p[1]))
			B.add("matte", Geo.lathe(lp, 16), Builder.M([bx, 0.765, side * 0.98]), "#3f4148")
			B.cyl("matte", 0.2, 0.2, 0.02, [bx, 0.935, side * 0.98], "#5b5f68", null, 16)
			# lateral damper
			B.rod("matte", [bx + 0.35, 0.7, side * 0.35], [bx + 0.35, 0.9, side * 0.75], 0.03, "#2f3038", 8)
		for ax in [-WHEELBASE / 2, WHEELBASE / 2]:
			o.wheelsets.append([bx + ax, WHEEL_R + 0.15, 0])
		B.box("matte", 0.34, 0.2, 1.62, [bx, 0.7, 0], COL.bogie)
		B.box("matte", 1.9, 0.08, 0.12, [bx, 0.66, 0], "#45494f")
		if o.motor:
			for ax in [-0.55, 0.55]:
				B.cyl("matte", 0.2, 0.2, 0.5, [bx + ax, 0.58, -0.12 * T.sign(ax)], "#5a5e66", [PI / 2, 0, 0], 16)
				B.rbox("matte", 0.3, 0.34, 0.16, 0.04, [bx + ax * 1.55, 0.55, 0.36 * T.sign(ax)], "#4a4e56")

	B.tag = "roofgear"
	# ---------------- roof gear
	var acX := 1.0 if o.panto else 0.0
	if true:
		B.rbox("paint", 3.3, 0.05, 1.92, 0.02, [acX, 3.76, 0], "#8f959d")
		B.rbox("paint", 3.2, 0.34, 1.86, 0.1, [acX, 3.91, 0], "#d3d7da", null, 3)
		for fx in [-0.78, 0.78]:
			B.cyl("metal", 0.36, 0.36, 0.02, [acX + fx, 4.08, 0], "#707780", null, 24)
			B.cyl("metal", 0.3, 0.3, 0.012, [acX + fx, 4.089, 0], "#5d636c", null, 24)
			B.box("metal", 0.64, 0.012, 0.035, [acX + fx, 4.094, 0], "#8b929a", [0, 0.6, 0])
			B.box("metal", 0.64, 0.012, 0.035, [acX + fx, 4.094, 0], "#8b929a", [0, -0.6, 0])
			B.cyl("metal", 0.07, 0.07, 0.03, [acX + fx, 4.1, 0], "#9aa1a8", null, 12)
		for side in [-1, 1]:
			for y in [3.84, 3.9, 3.96]:
				B.box("matte", 2.7, 0.014, 0.012, [acX, y, side * 0.931], "#a2a8af")
			B.box("matte", 2.9, 0.2, 0.004, [acX, 3.9, side * 0.927], "#bfc4c9")
		var vents := [3.9, 5.6, -2.3] if o.panto else [-3.5, 3.5, -5.8, 5.6]
		for vx in vents:
			B.rbox("paint", 0.62, 0.13, 0.42, 0.05, [vx, 3.83, 0], "#c9cdd1")
			B.box("matte", 0.5, 0.012, 0.3, [vx, 3.9, 0], "#8a9098")
		# antenna near the cab
		B.box("matte", 0.3, 0.03, 0.14, [XS - 1.5, YR + 0.01, -0.5], "#5b5f68")
		B.box("matte", 0.03, 0.22, 0.16, [XS - 1.5, YR + 0.12, -0.5], "#3f434c")
		# roof bus cable (runs the whole car on small insulators)
		var cz: float = 0.62 * o.carSign
		var x := XE + 0.5
		while x < XS - 0.8:
			var y := roof_y(cz)
			B.cyl("metal", 0.03, 0.035, 0.08, [x, y + 0.03, cz], "#e3e0d8", null, 8)
			x += 1.6
		B.cyl("matte", 0.024, 0.024, XS - XE - 1.0, [(XS + XE) / 2 - 0.2, roof_y(cz) + 0.085, cz], "#3a3a44", [0, 0, PI / 2], 8)
	if o.panto:
		build_pantograph(B, -BOGIE_X, 0.62 * o.carSign)

	B.tag = "saloon"
	# ---------------- interior (saloon)
	build_saloon(B, o)
	B.tag = "nose"
	# ---------------- nose
	build_nose(B, o)
	B.tag = "petals"
	# ---------------- petals resting on the roof / windscreen edge
	roof_petals(B, o, acX)


static func build_pantograph(B, px: float, cz: float) -> void:
	var y0 := YR
	# insulators + base frame
	for dx in [-0.55, 0.55]:
		for dz in [-0.42, 0.42]:
			var x: float = px + dx
			var z: float = dz
			var yb := roof_y(z)
			for i in 3:
				B.cyl("metal", 0.065, 0.065, 0.03, [x, yb + 0.03 + i * 0.05, z], "#e6e2da", null, 12)
			B.cyl("metal", 0.035, 0.035, 0.16, [x, yb + 0.08, z], "#d8d4cc", null, 8)
	var yf := y0 + 0.2
	for dz in [-0.42, 0.42]:
		B.box("metal", 1.3, 0.05, 0.07, [px, yf, dz], "#8a9098")
	for dx in [-0.55, 0.55]:
		B.box("metal", 0.07, 0.05, 0.9, [px + dx, yf, 0], "#8a9098")
	var H := [px - 0.5, yf + 0.05]
	var P := [px - 0.35, 5.06]
	var L1 := 1.25
	var L2 := 1.2
	var ddx: float = P[0] - H[0]
	var ddy: float = P[1] - H[1]
	var d := sqrt(ddx * ddx + ddy * ddy)
	var ca := (L1 * L1 + d * d - L2 * L2) / (2 * L1 * d)
	var a := atan2(ddy, ddx) - acos(clampv(ca, -1, 1))
	var K := [H[0] + L1 * cos(a), H[1] + L1 * sin(a)]
	B.cyl("metal", 0.05, 0.05, 0.5, [H[0], H[1], 0], "#9aa1a8", [PI / 2, 0, 0], 10)
	B.rod("metal", [H[0], H[1], 0], [K[0], K[1], 0], 0.045, "#c9ced4", 10)
	B.rod("metal", [H[0] + 0.1, H[1] - 0.02, 0.1], [K[0] - 0.05, K[1] - 0.06, 0.06], 0.014, "#aab0b7", 6)
	for z in [-0.26, 0.26]:
		B.rod("metal", [K[0], K[1], z * 0.25], [P[0], P[1], z], 0.024, "#c9ced4", 8)
	B.rod("metal", [K[0] - 0.3, K[1] + 0.18, -0.13], [K[0] - 0.3, K[1] + 0.18, 0.13], 0.014, "#aab0b7", 6)
	B.cyl("metal", 0.04, 0.04, 0.3, [K[0], K[1], 0], "#8a9098", [PI / 2, 0, 0], 10)
	# spring/damper at the base
	B.rod("matte", [H[0] + 0.08, H[1] - 0.02, -0.2], [H[0] + 0.55, H[1] + 0.12, -0.2], 0.035, "#4a4e57", 8)
	# pan head: two collector strips with horns (top at y 5.15)
	B.box("metal", 0.1, 0.04, 0.62, [P[0], 5.075, 0], "#9aa1a8")
	for sx in [-0.06, 0.06]:
		B.box("metal", 0.045, 0.05, 1.12, [P[0] + sx, 5.12, 0], "#6d747c")
		for s in [-1, 1]:
			B.tube("metal", [[P[0] + sx, 5.12, s * 0.55], [P[0] + sx, 5.1, s * 0.75], [P[0] + sx, 5.02, s * 0.9], [P[0] + sx, 4.95, s * 0.93]], 0.016, "#9aa1a8", 8, 5)
	for s in [-1, 1]:
		B.rod("metal", [P[0], 5.075, s * 0.3], [P[0], 5.1, s * 0.3], 0.02, "#8a9098", 6)
	# lightning arrester + cable to the bus line
	B.cyl("metal", 0.06, 0.07, 0.28, [px + 1.2, roof_y(cz) + 0.14, cz], "#e3e0d8", null, 10)
	B.tube("matte", [[px + 0.55, yf, 0.42], [px + 0.8, yf - 0.05, 0.55], [px + 1.2, roof_y(cz) + 0.28, cz]], 0.02, "#3a3a44", 10, 6)


static func build_saloon(B, o: Dictionary) -> void:
	var r = o.rng
	# ceiling (cove + flat), light strips, diffuser
	var cp := [[-1.32, 3.38], [-0.95, 3.6], [0.95, 3.6], [1.32, 3.38]]
	var cn := [[0.51, -0.86], [0, -1], [0, -1], [-0.51, -0.86]]
	B.add("interior", Builder.sweep_x(cp, cn, XE + 0.06, CAB_BACK), null, COL.ceiling)
	for z in [-0.62, 0.62]:
		var x := XE + 0.35
		while x < CAB_BACK - 0.5:
			B.box("iLight", 1.12, 0.02, 0.15, [x + 0.56, 3.588, z], "#ffffff")
			x += 1.25
	B.box("interior", CAB_BACK - XE - 0.5, 0.03, 0.34, [(CAB_BACK + XE) / 2, 3.585, 0], "#e2e1dc")
	# benches: [x0, x1, priority]
	var benches := [[-8.68, -7.34, true], [-4.61, -1.39, false], [1.39, 4.61, false]]
	for side in [-1, 1]:
		for bn in benches:
			var x0: float = bn[0]
			var x1: float = bn[1]
			var pri: bool = bn[2]
			var length := x1 - x0
			var cx := (x0 + x1) / 2
			var col: String = COL.seatPri if pri else COL.seat
			B.rbox("interior", length, 0.11, 0.5, 0.045, [cx, 1.685, side * 1.06], col, null, 1)
			B.rbox("interior", length, 0.4, 0.09, 0.04, [cx, 1.97, side * 1.27], col, [side * 0.08, 0, 0], 1)
			B.box("interior", length - 0.02, 0.3, 0.02, [cx, 1.47, side * 1.12], COL.seatBase)
			# seat end partitions (袖仕切り) + poles
			for ed in [[x0, -1], [x1, 1]]:
				var px: float = ed[0] + ed[1] * 0.03
				if not (pri and ed[1] < 0):
					B.rbox("interior", 0.035, 1.02, 0.5, 0.03, [px, FLOOR + 0.52, side * 1.07], COL.partition, null, 1)
					B.rod("metal", [px, FLOOR, side * 0.8], [px, 3.3, side * 0.8], 0.017, COL.metal, 8)
			if not pri:
				for d in [-0.69, 0.69]:
					B.rod("metal", [cx + d, 1.74, side * 0.82], [cx + d, 3.05, side * 1.1], 0.015, COL.metal, 8)
			# luggage rack
			B.box("metal", length, 0.025, 0.3, [cx, 3.05, side * 1.17], "#cfd4d8")
			var kn := int(T.js_round(length / 1.1))
			for k in kn + 1:
				B.box("metal", 0.02, 0.08, 0.3, [x0 + 0.05 + (length - 0.1) * k / maxi(1, kn), 3.09, side * 1.17], "#aeb4ba")
			# window-top ads
			if not pri:
				for ax in [cx - 0.8, cx + 0.8]:
					B.push(Builder.M([ax, 3.24, side * (HW - WALL_T - 0.05)], [0.25, 0.0 if side < 0 else PI, 0]))
					B.decal("decal", 0.5, 0.31, o.uv.dec.call("ad" + str(r.rint(0, 5)))); B.pop()
		# grab bar + straps
		var gx0 := XE + 0.3
		var gx1 := CAB_BACK - 0.25
		B.rod("metal", [gx0, 3.3, side * 0.86], [gx1, 3.3, side * 0.86], 0.015, COL.metal, 8)
		var x := gx0 + 0.2
		while x < gx1 - 0.1:
			var pri := x < -7.2
			B.box("interior", 0.028, 0.2, 0.01, [x, 3.19, side * 0.86], "#e5e3de")
			B.add("interior", Builder.geo_torus(0.055, 0.011, 3, 7), Builder.M([x, 3.035, side * 0.86]), COL.ringPri if pri else COL.ring)
			x += 0.34
		# wheelchair space handrail near the cab
		B.rod("metal", [6.72, 2.1, side * 1.26], [6.98, 2.1, side * 1.26], 0.015, COL.metal, 6)
	# hanging posters (中吊り) — double sided
	for hx in [-3.0, 3.0, -8.0]:
		B.rod("metal", [hx - 0.3, 3.58, 0], [hx + 0.3, 3.58, 0], 0.008, COL.metal, 4)
		var id := "hang" + str(r.rint(0, 3))
		B.push(Builder.M([hx, 3.44, 0.004], [0, 0, 0])); B.decal("decal", 0.56, 0.28, o.uv.dec.call(id)); B.pop()
		B.push(Builder.M([hx, 3.44, -0.004], [0, PI, 0])); B.decal("decal", 0.56, 0.28, o.uv.dec.call("hang" + str(r.rint(0, 3)))); B.pop()
	# priority sign on the end wall area
	B.push(Builder.M([XE + 0.07, 3.2, 0], [0, PI / 2, 0])); B.decal("decal", 0.5, 0.125, o.uv.dec.call("prioritySign")); B.pop()

	B.tag = "people"
	# passengers (a few)
	var seats_x := []
	for bn in benches:
		var x0: float = bn[0]
		var x1: float = bn[1]
		var n := int(T.js_round((x1 - x0) / 0.46))
		for i in n:
			seats_x.append([x0 + (i + 0.5) * (x1 - x0) / n, bn[2]])
	var n_sit: int = r.rint(3, 5)
	var used := {}
	for i in n_sit:
		var side := -1 if r.chance(0.5) else 1
		var k: int = r.rint(0, seats_x.size() - 1)
		var key := "%d:%d" % [side, k]
		if used.has(key):
			continue
		used[key] = true
		var x: float = seats_x[k][0]
		var pri: bool = seats_x[k][1]
		var look := People.pick_look(r)
		if pri and r.chance(0.6):
			look.outfit = "cardigan"
			look.hair = "#b8b2b8"
			look.style = "bob"
		var po: Dictionary = look.duplicate()
		po.merge({"pose": "sit", "lookDown": look.acc == "phone" or look.acc == "book"}, true)
		People.person(B, "interior", [x, 1.74, side * 1.1], 0.0 if side < 0 else PI, po)
	var n_stand: int = r.rint(1, 3)
	for i in n_stand:
		var xd: float = r.pick(DOORS)
		var look := People.pick_look(r)
		var x: float = xd + r.range(-0.9, 0.9)
		var z: float = r.range(-0.55, 0.55)
		var strap: bool = r.chance(0.5)
		var pos := [x, FLOOR, T.sign(z if z != 0.0 else 1.0) * 0.86 if strap else z]
		var rot := PI / 2 if r.chance(0.5) else -PI / 2
		var po: Dictionary = look.duplicate()
		po.merge({"pose": "stand", "strap": strap, "acc": "bag" if strap else look.acc}, true)
		People.person(B, "interior", pos, rot, po)


const PETAL_COLS := ["#f2a9c0", "#eb9db6", "#f5bfd0", "#e993b0", "#f7c9d7", "#f0b0c6", "#f4b6c9"]


static func roof_petals(B, o: Dictionary, acX: float) -> void:
	var r = o.rng
	var up := Vector3(0, 1, 0)
	var add := func(p: Vector3, n: Vector3, s: float) -> void:
		B.push(Builder.basis(p, n))
		var m := Builder.M([0, 0, 0], [0, 0, r.f() * PI * 2], [s, s * 1.2, 1])
		B.add("petal", Builder.geo_plane(), m, r.pick(PETAL_COLS))
		B.pop()
	var vents := [3.9, 5.6, -2.3] if o.panto else [-3.5, 3.5, -5.8, 5.6]
	var blocked := func(x: float, z: float) -> bool:
		if absf(x - acX) < 1.66 and absf(z) < 0.98:
			return true
		for v in vents:
			if absf(x - v) < 0.34 and absf(z) < 0.24:
				return true
		return bool(o.panto) and absf(x + BOGIE_X) < 0.72 and absf(z) < 0.52
	var on_roof := func(x: float, z: float, s: float) -> void:
		if x < XE + 0.05 or x > XS - 0.1 or blocked.call(x, z):
			return
		var nzy := roof_normal(z if z != 0.0 else 1e-4)
		add.call(Vector3(x, roof_y(z) + 0.005, z), Vector3(0, nzy[1], nzy[0]), s)
	var tri := func() -> float: return r.f() + r.f() - 1.0  # soft-centred offset in [-1, 1]
	# drifts: elongated along the car (air flow), dense core, soft falloff
	var drift := func(cx: float, cz: float, lx: float, lz: float, n: int, s0: float, s1: float) -> void:
		for i in n:
			var x: float = cx + tri.call() * lx
			var z: float = clampv(cz + tri.call() * lz, -1.08, 1.08)
			on_roof.call(x, z, r.range(s0, s1))
	drift.call(acX - 1.95, r.range(-0.3, 0.3), 0.42, 0.58, 50, 0.058, 0.088)          # leeward of the AC unit (both ends)
	drift.call(acX + 1.95, r.range(-0.3, 0.3), 0.34, 0.52, 36, 0.058, 0.088)
	for zc in [-0.29, 0.29]:
		for k in 3:    # caught along the edges of the anti-slip walkway
			var a0: float = r.range(XE + 1, XS - 1.2)
			var a1: float = zc + r.range(-0.04, 0.04)
			var a2: float = r.range(0.5, 1.1)
			drift.call(a0, a1, a2, 0.1, r.rint(16, 28), 0.058, 0.088)
	drift.call(XS - 0.55, r.range(-0.3, 0.3), 0.32, 0.72, 28, 0.058, 0.088)            # cab-end roof
	drift.call(XE + 0.45, r.range(-0.4, 0.4), 0.3, 0.62, 18, 0.058, 0.088)            # gangway end
	for v in vents:
		drift.call(v + 0.45, 0.0, 0.14, 0.3, 6, 0.045, 0.065)  # little heaps behind the vents
	# on top of the AC unit (avoid the fan discs)
	for i in 16:
		var x: float = acX + r.range(-1.45, 1.45)
		var z: float = r.range(-0.82, 0.82)
		var hit := false
		for fx in [-0.78, 0.78]:
			if Vector2(x - acX - fx, z).length() < 0.39:
				hit = true
				break
		if hit:
			continue
		add.call(Vector3(x, 4.084, z), up, r.range(0.045, 0.065))
	for i in 60:
		var a0: float = r.range(XE + 0.1, XS - 0.2)
		var a1: float = r.range(-1.05, 1.05)
		on_roof.call(a0, a1, r.range(0.048, 0.07))  # sparse scatter
	# windscreen: caught along the lower edge of the glass, mostly in the corners and against the parked wipers
	for i in 24:
		var corner: bool = r.chance(0.55)
		var sgn := -1.0 if r.chance(0.5) else 1.0
		var u: float = sgn * r.range(0.55, 0.8) if corner else r.range(-0.55, 0.55)
		var y: float = GLS.y0 + (r.range(-0.035, 0.07) if corner else r.range(-0.035, 0.03))
		var on_glass: bool = y > GLS.y0 and absf(u) < gU(y)
		var s := nose(u, y)
		add.call((s.p as Vector3) + (s.n as Vector3) * (-0.008 if on_glass else 0.004), s.n, r.range(0.042, 0.06))
	# nose cap (top of the cab, curving into the roof)
	for i in 12:
		var u: float = r.range(-0.8, 0.8)
		var y: float = r.range(MASK.y1 + 0.05, 3.62)
		var s := nose(u, y)
		add.call((s.p as Vector3) + (s.n as Vector3) * 0.005, s.n, r.range(0.04, 0.055))
