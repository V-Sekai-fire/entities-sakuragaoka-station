# street/furniture.js: standalone sign posts, sign plates, convex traffic mirrors, guardrails, cones and
# bollards. Solid-colour parts share one vertex-coloured toon material (and a double-sided twin).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const SM = preload("res://addons/sakuragaoka_station/world/street/mesh.gd")
const ST = preload("res://addons/sakuragaoka_station/world/street/textures.gd")

const COL := {"steel": "#a8aeb3", "steelDark": "#7b8289", "orange": "#e5873c", "white": "#e8e6df", "coneRed": "#e8604a", "coneWhite": "#eeece6",
	"dark": "#4a4852", "yellow": "#efc43a", "delin": "#e8943f", "red": "#d9564a"}

var ctx
var root
var opts: Dictionary
var VC
var VC2
var signMat
var mirrorMat
var plates := []
var _tint_cache := {}
var _cyl_geo_cache := {}
var _geo_cache := {}
var _face_geo: T.Geometry
var _rim_geo: T.Geometry
var _back_geo: T.Geometry
var _hood_geo: T.Geometry
var _rail_profile := []
var _cone_geo: T.Geometry
var _band_geo1: T.Geometry
var _band_geo2: T.Geometry


## Extruded convex plate from a 2D outline (plate faces +Z); front_uv(x, y) and back_uv(x, y) give [u, v].
static func plate_geometry(outline: Array, front_uv: Callable, back_uv: Callable, th: float = 0.014) -> T.Geometry:
	var b := SM.MeshBuilder.new()
	var n := outline.size()
	var cx := 0.0
	var cy := 0.0
	for p in outline:
		cx += p[0]
		cy += p[1]
	cx /= n
	cy /= n
	var z1 := th / 2.0
	var z0 := -th / 2.0
	var F := [0.0, 0.0, 1.0]
	var B := [0.0, 0.0, -1.0]
	var fuv: Array = front_uv.call(cx, cy)
	var fc := b.vert(cx, cy, z1, fuv[0], fuv[1], F)
	var fi := []
	for p in outline:
		var uv: Array = front_uv.call(p[0], p[1])
		fi.append(b.vert(p[0], p[1], z1, uv[0], uv[1], F))
	for i in n:
		b.tri(fc, fi[i], fi[(i + 1) % n], F)
	var buv: Array = back_uv.call(cx, cy)
	var bc := b.vert(cx, cy, z0, buv[0], buv[1], B)
	var bi := []
	for p in outline:
		var uv: Array = back_uv.call(p[0], p[1])
		bi.append(b.vert(p[0], p[1], z0, uv[0], uv[1], B))
	for i in n:
		b.tri(bc, bi[i], bi[(i + 1) % n], B)
	var g := ST.uv_of(ST.SIGN.back, 0.5, 0.5)
	for i in n:
		var x0: float = outline[i][0]
		var y0: float = outline[i][1]
		var x1: float = outline[(i + 1) % n][0]
		var y1: float = outline[(i + 1) % n][1]
		var nx := y1 - y0
		var ny := -(x1 - x0)
		var l := Vector2(nx, ny).length()
		if l == 0.0:
			l = 1.0
		nx /= l
		ny /= l
		if nx * ((x0 + x1) / 2.0 - cx) + ny * ((y0 + y1) / 2.0 - cy) < 0:
			nx = -nx
			ny = -ny
		var N := [nx, ny, 0.0]
		var a := b.vert(x0, y0, z1, g[0], g[1], N)
		var c := b.vert(x1, y1, z1, g[0], g[1], N)
		var d := b.vert(x1, y1, z0, g[0], g[1], N)
		var e := b.vert(x0, y0, z0, g[0], g[1], N)
		b.quad(a, c, d, e, N)
	return b.geometry()


static func _bbox_uv(cell: Dictionary, outline: Array) -> Callable:
	var x0 := 1e9
	var x1 := -1e9
	var y0 := 1e9
	var y1 := -1e9
	for p in outline:
		x0 = minf(x0, p[0]); x1 = maxf(x1, p[0]); y0 = minf(y0, p[1]); y1 = maxf(y1, p[1])
	return func(x: float, y: float) -> Array: return ST.uv_of(cell, (x - x0) / (x1 - x0), (y - y0) / (y1 - y0))


static func _back_grey() -> Callable:
	var g := ST.uv_of(ST.SIGN.back, 0.5, 0.5)
	return func(_x: float, _y: float) -> Array: return g


static func outline_circle(r: float, seg: int = 28) -> Array:
	var o := []
	for i in seg:
		o.append([cos(float(i) / seg * TAU) * r, sin(float(i) / seg * TAU) * r])
	return o


static func outline_rect(w: float, h: float) -> Array:
	return [[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]]


static func outline_diamond(a: float) -> Array:
	return [[0.0, -a], [a, 0.0], [0.0, a], [-a, 0.0]]


static func outline_tri_down(s: float) -> Array:
	var H := s * sqrt(3.0) / 2.0
	return [[-s / 2, H / 3], [0.0, -2 * H / 3], [s / 2, H / 3]]


func _init(c, r, tex: Dictionary, o: Dictionary) -> void:
	ctx = c
	root = r
	opts = o
	var mat = ctx.mat
	VC = mat.toon("#ffffff", {"vertexColors": true, "paint": 0.03})
	VC2 = mat.toon("#ffffff", {"vertexColors": true, "paint": 0.03, "side": "double"})
	signMat = mat.toon("#ffffff", {"map": tex.signs, "paint": 0.0})
	mirrorMat = mat.shader("street-mirror", "#9a9ba2", {})
	_face_geo = Geo.circle(0.3, 28)
	_rim_geo = Geo.torus(0.303, 0.024, 6, 28)
	_back_geo = Geo.sphere(0.315, 20, 5, 0, TAU, 0, PI / 2).rotate_x(-PI / 2).scale(1, 1, 0.28)
	_hood_geo = Geo.cylinder(0.335, 0.335, 0.13, 16, 1, true, PI / 2, PI).rotate_x(PI / 2).translate(0, 0, 0.06)
	var N := 12
	var pts := []
	for i in N + 1:
		var v := -0.175 + 0.35 * i / N
		var bb := 0.034 * pow(sin(PI * (v + 0.175) / 0.175), 2)
		pts.append([bb, v])
	var back := []
	for i in range(pts.size() - 1, -1, -1):
		back.append([pts[i][0] - 0.014, pts[i][1]])
	_rail_profile = pts + back
	_cone_geo = Geo.cylinder(0.028, 0.13, 0.62, 14)
	_band_geo1 = Geo.cylinder(0.066, 0.086, 0.09, 14, 1, true)
	_band_geo2 = Geo.cylinder(0.098, 0.113, 0.07, 14, 1, true)


func tint(geo: T.Geometry, hex: String) -> T.Geometry:
	var key := "%d%s" % [geo.get_instance_id(), hex]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var g := geo.clone()
	var c := T.color(hex)
	var n := g.attributes.position.count()
	var a := PackedFloat32Array()
	a.resize(n * 3)
	for i in n:
		a[i * 3] = c.r
		a[i * 3 + 1] = c.g
		a[i * 3 + 2] = c.b
	g.set_attribute("color", T.Attr.new(a, 3))
	_tint_cache[key] = g
	return g


## Solid-colour part: geo, colour hex, pos, rot [rx, ry, rz], scale [sx, sy, sz], parent.
func part(geo: T.Geometry, hex: String, pos = null, rot = null, scl = null, parent = null, m = null) -> T.MeshObj:
	var mesh := T.MeshObj.new(tint(geo, hex), m if m != null else VC)
	if pos != null:
		mesh.position = Vector3(pos[0], pos[1], pos[2])
	if rot != null:
		mesh.rotation = Vector3(rot[0] if rot[0] else 0.0, rot[1] if rot[1] else 0.0, rot[2] if rot[2] else 0.0)
	if scl != null:
		mesh.scale = Vector3(scl[0], scl[1], scl[2])
	mesh.cast_shadow = true
	mesh.receive_shadow = true
	(parent if parent != null else root).add(mesh)
	return mesh


func taper(rt: float, rb: float, h: float, seg: int) -> T.Geometry:
	var k := "%s|%s|%s|%d" % [rt, rb, h, seg]
	if not _cyl_geo_cache.has(k):
		_cyl_geo_cache[k] = Geo.cylinder(rt, rb, h, seg)
	return _cyl_geo_cache[k]


func cyl(r: float, h: float, hex: String, pos: Array, seg: int = 10, parent = null) -> T.MeshObj:
	return part(Geo.g_cyl(ctx.cache, seg), hex, pos, null, [r * 2, h, r * 2], parent)


func cyl_t(rt: float, rb: float, h: float, hex: String, pos: Array, seg: int = 10, parent = null) -> T.MeshObj:
	return part(taper(rt, rb, h, seg), hex, pos, null, null, parent)


func box(w: float, h: float, d: float, hex: String, pos: Array, rot = null, parent = null) -> T.MeshObj:
	return part(Geo.g_box(ctx.cache), hex, pos, rot, [w, h, d], parent)


func add_plate(geo: T.Geometry, x: float, y: float, z: float, rot_y: float, tilt: float = 0.0) -> T.MeshObj:
	var m := T.MeshObj.new(geo, signMat)
	m.position = Vector3(x, y, z)
	m.set_rotation(tilt, rot_y, 0, "YXZ")
	m.cast_shadow = true
	m.receive_shadow = true
	root.add(m)
	plates.append(m)
	return m


func plate_geo(kind: String, cell: Dictionary, size: Array, double: bool = false) -> T.Geometry:
	var key := "%s|%s,%s|%s|%s" % [kind, cell.x, cell.y, ",".join(size.map(func(v): return str(v))), double]
	if _geo_cache.has(key):
		return _geo_cache[key]
	var out: Array
	var front: Callable
	if kind == "circle":
		out = outline_circle(size[0])
		front = _bbox_uv(cell, out)
	elif kind == "rect":
		out = outline_rect(size[0], size[1])
		front = _bbox_uv(cell, out)
	elif kind == "diamond":
		out = outline_diamond(size[0])
		front = _bbox_uv(cell, out)
	elif kind == "tri":
		var s: float = size[0]
		var Hh := s * sqrt(3.0) / 2.0
		out = outline_tri_down(s)
		front = func(x: float, y: float) -> Array: return ST.uv_of(cell, (128 + x * (244 / s)) / 256.0, 1.0 - (14 + (Hh / 3 - y) * (228 / Hh)) / 256.0)
	var back: Callable = (func(x: float, y: float) -> Array: return front.call(-x, y)) if double else _back_grey()
	var g := plate_geometry(out, front, back)
	_geo_cache[key] = g
	return g


## Galvanised post; returns the top y. Items: [{kind, cell, size, y (above base), double, dx}].
func sign_post(x: float, z: float, base_y: float, height: float, rot_y: float, items: Array, o: Dictionary = {}) -> float:
	var r: float = o.get("r", 0.03)
	cyl(r, height + 0.05, o.get("col", COL.steel), [x, base_y + height / 2.0 - 0.025, z])
	cyl(r + 0.006, 0.03, COL.steelDark, [x, base_y + height + 0.01, z])
	cyl_t(r + 0.018, r + 0.024, 0.06, COL.steelDark, [x, base_y + 0.025, z])
	var fx := sin(rot_y)
	var fz := cos(rot_y)
	for it in items:
		var off: float = r + 0.012 + it.get("gap", 0.0)
		var lat: float = it.get("dx", 0.0)
		var rx := cos(rot_y)
		var rz := -sin(rot_y)
		var px := x + fx * off + rx * lat
		var pz := z + fz * off + rz * lat
		var py: float = base_y + it.y
		add_plate(plate_geo(it.kind, it.cell, it.size, it.get("double", false)), px, py, pz, rot_y, it.get("tilt", 0.0))
		if not it.get("noClamp", false):
			for dy in it.get("clamps", [0.0]):
				box(0.09, 0.028, 0.03, COL.steelDark, [x + fx * (r * 0.3), py + dy, z + fz * (r * 0.3)], [0, rot_y, 0])
	ctx.physics.addCylinder(x, z, r + 0.06, base_y - 0.2, base_y + height)
	return base_y + height


func mirror_head(parent, pos: Array, rot_y: float, tilt: float = 0.07) -> T.Group:
	var g := T.Group.new()
	g.position = Vector3(pos[0], pos[1], pos[2])
	g.set_rotation(tilt, rot_y, 0, "YXZ")
	parent.add(g)
	var face := T.MeshObj.new(_face_geo, mirrorMat)
	face.position.z = 0.014
	face.receive_shadow = false
	g.add(face)
	part(_rim_geo, COL.orange, [0, 0, 0.012], null, null, g)
	part(_back_geo, COL.orange, null, null, null, g)
	part(_hood_geo, COL.orange, null, null, null, g, VC2)
	part(Geo.g_box(ctx.cache), COL.orange, [0, 0, -0.16], null, [0.06, 0.06, 0.2], g)
	return g


## Curve mirror post. heads: [{yaw (relative), dx (lateral on a T-arm)}]
func curve_mirror(x: float, z: float, rot_y: float, heads = null, extra: Array = [], base_y = null) -> void:
	if heads == null:
		heads = [{"yaw": 0.0, "dx": 0.0}]
	var base: float = base_y if base_y != null else ctx.L.height_at(x, z) + (opts.baseLift.call(x, z) if opts.get("baseLift") else 0.0)
	var h_top := 3.05
	cyl(0.038, h_top, COL.orange, [x, base + h_top / 2.0 - 0.02, z], 12)
	cyl(0.045, 0.035, COL.orange, [x, base + h_top, z], 12)
	cyl_t(0.07, 0.08, 0.06, COL.steelDark, [x, base + 0.02, z], 12)
	var g := T.Group.new()
	g.position = Vector3(x, base, z)
	g.rotation.y = rot_y
	root.add(g)
	var y_head := 2.72
	if heads.size() > 1:
		part(Geo.g_box(ctx.cache), COL.orange, [0, y_head + 0.05, 0.05], null, [1.0, 0.055, 0.055], g)
	for h in heads:
		mirror_head(g, [h.get("dx", 0.0), y_head, 0.26], h.get("yaw", 0.0))
	var pl := T.MeshObj.new(plate_geo("rect", ST.SIGN.pTown, [0.34, 0.085]), signMat)
	pl.position = Vector3(0, 1.85, 0.047)
	pl.cast_shadow = true
	g.add(pl)
	plates.append(pl)
	for it in extra:
		var m := T.MeshObj.new(plate_geo(it.kind, it.cell, it.size, it.get("double", false)), signMat)
		var ry: float = it.get("rotY", 0.0)
		m.position = Vector3(sin(ry) * 0.056, it.y, cos(ry) * 0.056)
		m.rotation.y = ry
		m.cast_shadow = true
		g.add(m)
		plates.append(m)
	ctx.physics.addCylinder(x, z, 0.12, base - 0.2, base + h_top)


## White W-beam guardrail from a to b ([x, z]); road_dir +1 if the road is on the left of a->b.
func guardrail(a: Array, b: Array, road_dir: float, o: Dictionary = {}) -> void:
	var H: Callable = ctx.L.height_at
	var dx: float = b[0] - a[0]
	var dz: float = b[1] - a[1]
	var length := Vector2(dx, dz).length()
	var tx := dx / length
	var tz := dz / length
	var nx := -tz * road_dir
	var nz := tx * road_dir
	var n := maxi(1, int(T.js_round(length / 2.0)))
	var lift: Callable = o.get("lift", func(_x, _z): return 0.0)
	var rings := []
	var beam_y := 0.6
	for i in range(-1, n + 2):
		var f := float(i) / n
		var back := 0.0
		if i < 0:
			f = -0.22 / length
			back = -0.2
		elif i > n:
			f = 1 + 0.22 / length
			back = -0.2
		var px: float = a[0] + dx * f + nx * back
		var pz: float = a[1] + dz * f + nz * back
		rings.append({"x": px, "z": pz, "y": H.call(px, pz) + lift.call(px, pz) + beam_y})
	var B := SM.MeshBuilder.new(true)
	var P := _rail_profile.size()
	var wc := T.color(COL.white)
	var WC := [wc.r, wc.g, wc.b]
	var idx := []
	for r in rings:
		var row := []
		for lv in _rail_profile:
			row.append(B.vert(r.x + nx * lv[0], r.y + lv[1], r.z + nz * lv[0], 0, 0, [0.0, 1.0, 0.0], WC))
		idx.append(row)
	for i in rings.size() - 1:
		for j in P:
			var j2 := (j + 1) % P
			var l0: float = _rail_profile[j][0]
			var v0: float = _rail_profile[j][1]
			var l1: float = _rail_profile[j2][0]
			var v1: float = _rail_profile[j2][1]
			var ex := v1 - v0
			var ey := -(l1 - l0)
			B.quad(idx[i][j], idx[i + 1][j], idx[i + 1][j2], idx[i][j2], [nx * ex, ey, nz * ex])
	root.add(B.mesh(VC, {"cast": true, "computeNormals": true}))
	for i in n + 1:
		var f := float(i) / n
		var px: float = a[0] + dx * f - nx * 0.085
		var pz: float = a[1] + dz * f - nz * 0.085
		var y: float = H.call(px, pz) + lift.call(px, pz)
		cyl(0.06, 0.86, COL.white, [px, y + 0.38, pz])
		cyl(0.066, 0.025, COL.white, [px, y + 0.81, pz])
		if i % 3 == 1:
			box(0.07, 0.07, 0.012, COL.delin, [px + nx * 0.07, y + 0.78, pz + nz * 0.07], [0, atan2(nx, nz), 0])
	var mx: float = (a[0] + b[0]) / 2.0
	var mz: float = (a[1] + b[1]) / 2.0
	ctx.physics.addBox(mx - nx * 0.04, mz - nz * 0.04, 0.24, length + 0.3, atan2(tx, tz), -5, maxf(H.call(a[0], a[1]), H.call(b[0], b[1])) + lift.call(mx, mz) + 0.9)


func cone(x: float, z: float, y0: float) -> void:
	box(0.36, 0.04, 0.36, COL.dark, [x, y0 + 0.02, z])
	part(_cone_geo, COL.coneRed, [x, y0 + 0.35, z])
	part(_band_geo1, COL.coneWhite, [x, y0 + 0.47, z])
	part(_band_geo2, COL.coneWhite, [x, y0 + 0.25, z])
	ctx.physics.addCylinder(x, z, 0.2, y0 - 0.1, y0 + 0.7)


func cone_bar(a: Array, b: Array, y: float) -> void:
	var n := 8
	var dx: float = (b[0] - a[0]) / n
	var dz: float = (b[1] - a[1]) / n
	var length := Vector2(b[0] - a[0], b[1] - a[1]).length()
	for i in n:
		var m := part(Geo.g_cyl(ctx.cache, 10), COL.dark if i % 2 else COL.yellow, [a[0] + dx * (i + 0.5), y, a[1] + dz * (i + 0.5)], null, [0.044, length / n, 0.044])
		m.set_rotation(PI / 2, atan2(dx, dz), 0, "YXZ")


func bollard(x: float, z: float, y0: float) -> void:
	cyl(0.05, 0.82, COL.white, [x, y0 + 0.4, z], 12)
	part(Geo.g_sphere(ctx.cache, 10), COL.white, [x, y0 + 0.81, z], null, [0.104, 0.104, 0.104])
	cyl(0.053, 0.07, COL.red, [x, y0 + 0.66, z], 12)
	cyl_t(0.08, 0.09, 0.04, COL.steelDark, [x, y0 + 0.02, z], 12)
	ctx.physics.addCylinder(x, z, 0.12, y0 - 0.1, y0 + 0.85)
