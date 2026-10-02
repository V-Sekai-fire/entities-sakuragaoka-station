# houses/laundry.js: laundry, wind-chime strips and koinobori as alpha-cut cloth cards merged into one
# dynamic mesh. aSway (direction * amplitude, weight) and aPhase drive the original's wind sway.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")

const TINTS := {
	"tee": ["#f4f4f4", "#f2c9d3", "#bcd3ea", "#f3e3a8", "#cfe3c4", "#f4f4f4", "#d9d0ec"],
	"towel": ["#f4f4f4", "#a9c8e8", "#f5c6c6", "#f3e1a6", "#c6e1c9", "#e9d6f0", "#f4f4f4"],
}
const MIXES := {
	"balcony": ["shirt", "tee", "towel", "tee", "pinch", "towel", "shirt"],
	"student": ["sailor", "skirt", "tee", "towel", "gym", "pinch", "sailor"],
	"family": ["shirt", "shirt", "tee", "gym", "towel", "towel", "pinch", "tee"],
	"sheets": ["sheet", "towel", "towel", "pinch"],
	"yard": ["sheet", "shirt", "tee", "towel", "towel", "pinch"],
	"apartment": ["shirt", "towel", "pinch", "tee"],
}
const SIZE := {"shirt": [0.52, 0.72], "sailor": [0.5, 0.64], "tee": [0.5, 0.52], "gym": [0.48, 0.5], "towel": [0.36, 0.62], "sheet": [1.25, 1.2], "pinch": [0.6, 0.5], "skirt": [0.42, 0.56]}

var H
var ctx
var P := PackedFloat32Array()
var N := PackedFloat32Array()
var U := PackedFloat32Array()
var C := PackedFloat32Array()
var S := PackedFloat32Array()
var PH := PackedFloat32Array()
var I := PackedInt32Array()
var count := 0


func _init(h) -> void:
	H = h
	ctx = h.ctx


## corner: top-left world point; ax: world vector across; ay: world vector down.
func _quad(corner: Vector3, ax: Vector3, ay: Vector3, nrm: Vector3, rect: Array, tint, amp: float, phase: float, nx: int = 3, ny: int = 4, hang_fn = null) -> void:
	var base := P.size() / 3
	var c := T.color(tint)
	for j in ny + 1:
		for i in nx + 1:
			var u := float(i) / nx
			var v := float(j) / ny
			var p := corner + ax * u + ay * v
			P.append_array([p.x, p.y, p.z])
			N.append_array([nrm.x, nrm.y, nrm.z])
			U.append_array([rect[0] + (rect[2] - rect[0]) * u, rect[3] - (rect[3] - rect[1]) * v])
			C.append_array([c.r, c.g, c.b])
			var w: float = hang_fn.call(u, v) if hang_fn != null else pow(v, 1.3)
			S.append_array([nrm.x * amp, nrm.y * amp, nrm.z * amp, w])
			PH.append(phase)
	for j in ny:
		for i in nx:
			var a := base + j * (nx + 1) + i
			var b := a + 1
			var d := a + nx + 1
			var e := d + 1
			I.append_array([a, d, b, b, d, e])
	count += 1


## Hangs garments along a pole in frame FF from local x0 to x1 at (y, z); the cards face +z.
func line(FF, x0: float, x1: float, y: float, z: float, r, mix: String = "balcony") -> void:
	var rects: Dictionary = H.tex.laundry.rects
	var list: Array = MIXES.get(mix, MIXES.balcony)
	var x := x0
	var nW: Vector3 = (FF.w(0, 0, 1) - FF.w(0, 0, 0)).normalized()
	var aX: Vector3 = (FF.w(1, 0, 0) - FF.w(0, 0, 0)).normalized()
	var k := int(floor(r.f() * list.size()))
	var guard := 0
	while x < x1 - 0.3:
		guard += 1
		if guard > 16:
			break
		var name: String = list[k % list.size()]
		k += 1
		var w: float = SIZE[name][0]
		var h: float = SIZE[name][1]
		if x + w > x1 + 0.05:
			if name == "sheet":
				continue
			break
		var tint = "#ffffff"
		if name == "tee":
			tint = TINTS.tee[int(floor(r.f() * TINTS.tee.size()))]
		elif name == "towel":
			tint = TINTS.towel[int(floor(r.f() * TINTS.towel.size()))]
		var dz := (r.f() - 0.5) * 0.06
		var hook := 0.0 if name == "towel" or name == "sheet" else 0.02
		var corner: Vector3 = FF.w(x, y + 0.02 + hook, z + dz)
		var amp := 0.16 if name == "sheet" else (0.1 if name == "pinch" else 0.12)
		_quad(corner, aX * w, Vector3(0, -h, 0), nW, rects[name], tint, amp, r.f() * 6.28, 4 if name == "sheet" else 3, 4)
		x += w + 0.05 + r.f() * 0.1


## A wind chime: a small static glass bell and a swaying paper strip under an eave.
func chime(FF, x: float, y: float, z: float) -> void:
	var M: Dictionary = H.M
	FF.box(M.plain, "#9aa1a8", 0.01, 0.12, 0.01, x, y + 0.06, z)
	FF.raw(M.glass, null, H.blob_raw(0, 1), x, y - 0.03, z, {"sx": 0.1, "sy": 0.09, "sz": 0.1, "shadow": false})
	FF.box(M.plain, "#d96c86", 0.03, 0.02, 0.03, x, y - 0.03, z)
	var rects: Dictionary = H.tex.laundry.rects
	var corner: Vector3 = FF.w(x - 0.03, y - 0.06, z)
	var ax: Vector3 = (FF.w(1, 0, 0) - FF.w(0, 0, 0)).normalized() * 0.06
	var nW: Vector3 = (FF.w(0, 0, 1) - FF.w(0, 0, 0)).normalized()
	_quad(corner, ax, Vector3(0, -0.24, 0), nW, rects.tanzaku, "#ffffff", 0.09, x * 3.1, 1, 3, func(_u, v): return v)


## A carp tube from the mouth along world direction dir (downwind).
func _carp(mouth: Vector3, dir: Vector3, ln: float, rad: float, rect: Array, phase: float) -> void:
	var up := Vector3.UP
	var side := dir.cross(up).normalized()
	var nL := 6
	var nR := 8
	var base := P.size() / 3
	for j in nL + 1:
		var t := float(j) / nL
		var rr := rad * (1.0 - 0.45 * t) * (1.0 - 0.15 * sin(t * PI * 2.0))
		var c := mouth + dir * (ln * t) + up * (-t * t * ln * 0.12)
		for i in nR + 1:
			var a := float(i) / nR * PI * 2.0
			var n := up * cos(a) + side * sin(a)
			var p := c + n * rr
			P.append_array([p.x, p.y, p.z])
			N.append_array([n.x, n.y, n.z])
			U.append_array([rect[0] + (rect[2] - rect[0]) * t, rect[1] + (rect[3] - rect[1]) * (0.5 + 0.5 * cos(a))])
			C.append_array([1.0, 1.0, 1.0])
			var amp := 0.35 * ln * 0.25
			S.append_array([0.0, amp, 0.0, t * t])
			PH.append(phase)
	for j in nL:
		for i in nR:
			var a := base + j * (nR + 1) + i
			var b := a + 1
			var d := a + nR + 1
			var e := d + 1
			I.append_array([a, b, d, b, e, d])
	count += 1


func _wind_dir() -> Vector3:
	var w: Vector2 = ctx.shared.uWind
	return Vector3(w.x, 0, w.y).normalized()


## A big garden koinobori on a pole at (x, groundY, z).
func koinobori(F, x: float, y: float, z: float, h: float = 7.5) -> void:
	var M: Dictionary = H.M
	F.cyl(M.plain, "#e8e4da", 0.06, h, x, y + h / 2.0, z, {"seg": 8, "rTop": 0.04})
	F.raw(M.plain, "#e8c84a", H.blob_raw(1, 0), x, y + h + 0.1, z, {"sx": 0.18, "sy": 0.18, "sz": 0.18})
	for k in 6:
		var a := k / 6.0 * PI * 2.0
		F.box(M.plain, "#d9575a" if k % 2 else "#4f7fc4", 0.03, 0.03, 0.42, x + sin(a) * 0.21, y + h - 0.12, z + cos(a) * 0.21, {"ry": a})
	var dir := _wind_dir()
	var top: Vector3 = F.w(x, y + h - 0.35, z)
	var rects: Dictionary = H.tex.laundry.rects
	_quad(top, dir * 2.4, Vector3(0, -0.5, 0), Vector3(-dir.z, 0, dir.x), rects.fukinagashi, "#ffffff", 0.3, 0.5, 6, 1, func(u, _v): return u * u)
	var sizes := [[2.6, 0.36, "carp_black"], [2.1, 0.3, "carp_red"], [1.6, 0.24, "carp_blue"]]
	for i in sizes.size():
		_carp(top + Vector3(0, -0.75 - i * 0.85, 0) + dir * 0.12, dir, sizes[i][0], sizes[i][1], rects[sizes[i][2]], i * 1.3)
	ctx.wires.add([F.w(x, y + h - 0.2, z), F.w(x, y + 1.2, z) + Vector3(0.05, 0, 0)], {"width": 0.008, "color": "#8a8f96"})


## A small balcony koinobori on a bracket pole.
func koinobori_small(FF, x: float, y: float, z: float) -> void:
	var M: Dictionary = H.M
	FF.cyl(M.plain, "#e8e4da", 0.02, 1.9, x, y + 0.95, z, {"seg": 6, "rx": 0.35})
	var top: Vector3 = FF.w(x, y + 1.75, z + 0.62)
	var dir := _wind_dir()
	var rects: Dictionary = H.tex.laundry.rects
	var sets := [[0.8, 0.12, "carp_black"], [0.65, 0.1, "carp_red"], [0.5, 0.08, "carp_blue"]]
	for i in sets.size():
		_carp(top + Vector3(0, -0.12 - i * 0.26, 0), dir, sets[i][0], sets[i][1], rects[sets[i][2]], i * 1.1 + x)


func build():
	if count == 0:
		return null
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(P, 3))
	g.set_attribute("normal", T.Attr.new(N, 3))
	g.set_attribute("uv", T.Attr.new(U, 2))
	g.set_attribute("color", T.Attr.new(C, 3))
	g.set_attribute("aSway", T.Attr.new(S, 4))
	g.set_attribute("aPhase", T.Attr.new(PH, 1))
	g.set_index(I)
	g.compute_bounding_box()
	var mat = ctx.mat.toon("#ffffff", {"map": H.tex.laundry.texture, "alphaTest": 0.5, "side": "double", "vertexColors": true, "name": "houses-laundry"})
	mat.user_data["sway"] = "houses-laundry"
	var mesh := T.MeshObj.new(g, mat)
	mesh.cast_shadow = true
	mesh.receive_shadow = true
	mesh.frustum_culled = false
	mesh.name = "houses-laundry"
	ctx.no_outline(mesh)
	ctx.add(mesh)
	return mesh
