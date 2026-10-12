# shopsA/goods.js: instanced goods. Every small repeated object inside the shops (products, bottles,
# cans, books, magazines, cups, floor tiles, flower heads, stems...) is a real little 3D shape drawn
# as an instance of ONE InstancedMesh per kind and per shop. Per instance: matrix + colour + label
# "variant" (a cell of the kind's label sheet). Per vertex: aTint (1 = takes the instance colour,
# 0 = keeps the printed label colours). The label sheets are canvas paintings in the original; here
# they are sized stand-ins under the original's keys, with the original's cell tables. The goods
# shader patch (label cell offset, tint mask, warm self-light) is the renderer's job: the cell
# offsets are kept in geometry.user_data.aUV.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")
const GM = preload("res://addons/sakuragaoka_station/world/shopsA/geom.gd")
const Common = preload("res://addons/sakuragaoka_station/world/shopsA/common.gd")

# swatch band: every label cell keeps its bottom 9 % for four solid colour swatches
# (s0 side, s1 top, s2 back, s3 extra) that the non-printed faces sample.
const SW := [[0.125, 0.045], [0.375, 0.045], [0.625, 0.045], [0.875, 0.045]]
const FRONT := [0.02, 0.11, 0.98, 0.99]

## Label sheets: name -> [cols, rows, cell w, cell h] (the paint callbacks are canvas work).
const SHEETS := {
	"box": [8, 2, 128, 160], "bag": [8, 2, 128, 160], "pet": [16, 1, 64, 256], "can": [16, 1, 64, 128],
	"cupmen": [8, 1, 128, 128], "carton": [8, 1, 96, 160], "bento": [8, 1, 160, 160], "onigiri": [8, 1, 96, 112],
	"sando": [4, 1, 96, 96], "mag": [8, 4, 128, 176], "spine": [16, 2, 64, 512], "cover": [8, 4, 128, 176],
	"album": [8, 2, 128, 144], "bmark": [8, 1, 48, 160], "blister": [8, 2, 96, 144],
}

## kind -> [sheet or null, side or null, outline]
const KINDS := {
	"tile": [null, null, false], "slab": [null, null, true], "pbox": ["box", null, true], "bag": ["bag", null, true],
	"pet": ["pet", null, true], "can": ["can", null, true], "petLo": ["pet", null, true], "canLo": ["can", null, true],
	"cupLo": ["cupmen", null, true], "cupmen": ["cupmen", null, true], "carton": ["carton", null, true],
	"bento": ["bento", null, true], "onigiri": ["onigiri", null, true], "sando": ["sando", null, true],
	"mag": ["mag", null, true], "book": ["spine", null, true], "cover": ["cover", null, true], "album": ["album", null, true],
	"bmark": ["bmark", null, true], "blister": ["blister", null, true],
	"blob": [null, null, true], "bud": [null, null, false], "cyl": [null, null, true], "cyl6": [null, null, true],
	"stem": [null, null, false], "leaf": [null, "double", false], "mcup": [null, null, true], "ccup": [null, null, true],
	"saucer": [null, null, true], "plate": [null, null, true], "rose": [null, null, false], "tulip": [null, "double", false],
	"daisy": [null, "double", false], "star5": [null, "double", false], "cone": [null, "double", true], "ring": [null, null, true],
}

var ctx
var C
var _sheet_tex := {}
var _mat_cache := {}
var lists := {}
var shop := "x"
var inner := 0.42
var _last_base = null


func _init(c, common) -> void:
	ctx = c
	C = common


# ---------------------------------------------------------------- geometry helpers

static func ensure(g: T.Geometry, tint: float = 1.0) -> T.Geometry:
	if not g.indexed:
		var n0 := g.vertex_count()
		var a := PackedInt32Array()
		a.resize(n0)
		for i in n0:
			a[i] = i
		g.set_index(a)
	var n := g.vertex_count()
	if not g.has_attribute("normal"):
		g.compute_vertex_normals()
	if not g.has_attribute("uv"):
		var uv := PackedFloat32Array()
		uv.resize(n * 2)
		g.set_attribute("uv", T.Attr.new(uv, 2))
	if not g.has_attribute("aTint"):
		var at := PackedFloat32Array()
		at.resize(n)
		at.fill(tint)
		g.set_attribute("aTint", T.Attr.new(at, 1))
	for k in g.attributes.keys():
		if not ["position", "normal", "uv", "aTint"].has(k):
			g.delete_attribute(k)
	g.clear_groups()
	return g


## unit box, origin at the bottom centre, without its bottom face (never seen: things stand on shelves)
static func box_nb(bottom: bool = false, back: bool = true) -> T.Geometry:
	var g := Geo.box(1, 1, 1)
	g.translate(0, 0.5, 0)
	if not bottom or not back:
		var src := g.index
		var keep := PackedInt32Array()
		for f in 6:
			if (bottom or f != 3) and (back or f != 5):
				for t in 6:
					keep.append(src[f * 6 + t])
		g.set_index(keep)
	return g


## classify each vertex by its normal and assign label UVs (front/back planar projection, points elsewhere)
static func proj_uv(g: T.Geometry, spec: Dictionary) -> T.Geometry:
	g.compute_bounding_box()
	var bb: AABB = g.bounding_box
	var lo := bb.position
	var hi := bb.end
	var p: T.Attr = g.attributes.position
	var n: T.Attr = g.attributes.normal
	var uv: T.Attr = g.attributes.uv
	var tn = g.attributes.get("aTint")
	var W := hi.x - lo.x
	if W == 0.0:
		W = 1.0
	var H := hi.y - lo.y
	if H == 0.0:
		H = 1.0
	var D := hi.z - lo.z
	if D == 0.0:
		D = 1.0
	for i in p.count():
		var x := p.get_x(i)
		var y := p.get_y(i)
		var z := p.get_z(i)
		var ny := n.get_y(i)
		var nz := n.get_z(i)
		var face: String
		if spec.get("half"):
			face = "front" if nz >= 0.0 else "back"
		else:
			face = "front" if nz > 0.62 else ("back" if nz < -0.62 else ("top" if ny > 0.7 else ("bottom" if ny < -0.7 else "side")))
		var s = spec[face] if spec.get(face) != null else spec.side
		if face == "back" and s is String and s == "front":
			s = spec.front
		if s.size() == 4:
			var fx: float = (hi.x - x) / W if face == "back" else (x - lo.x) / W
			var fy: float = (hi.z - z) / D if face == "top" or face == "bottom" else (y - lo.y) / H
			uv.set_xy(i, s[0] + fx * (s[2] - s[0]), s[1] + fy * (s[3] - s[1]))
		else:
			uv.set_xy(i, s[0], s[1])
		if spec.get("tint") != null and tn != null:
			var tv = spec.tint.get(face)
			if tv != null:
				tn.set_x(i, tv)
	return g


## lathe around Y with u = 0.5 facing +z and v given per profile point: prof = [[r, y, v], ...]
static func lathe(prof: Array, seg: int, warp: String = "") -> T.Geometry:
	var pts := []
	for p in prof:
		pts.append(Vector2(maxf(1e-4, p[0]), p[1]))
	var g := Geo.lathe(pts, seg, PI, PI * 2.0)
	var uv: T.Attr = g.attributes.uv
	var np := prof.size()
	var pos: T.Attr = g.attributes.position
	for i in seg + 1:
		for j in np:
			var k := i * np + j
			var v: float = prof[j][2] if prof[j].size() > 2 and prof[j][2] != null else float(j) / (np - 1)
			uv.set_xy(k, float(i) / seg, v)
			if warp != "":
				var phi := PI + (float(i) / seg) * PI * 2.0
				var w: Array = _rose_warp(phi, j) if warp == "rose" else _tulip_warp(phi, j)
				var x := pos.get_x(k)
				var z := pos.get_z(k)
				pos.set_xyz(k, x * (1.0 + w[0]), pos.get_y(k) + w[1], z * (1.0 + w[0]))
	if warp != "":
		g.compute_vertex_normals()
	return g


static func extrude_y(shape_pts: Array, depth: float = 1.0, curve: int = 3) -> T.Geometry:
	var g := GM.extrude_path(GM.ShapePath.from_points(shape_pts), depth, curve)
	g.translate(0, 0, -depth / 2.0)
	return g


static func rounded_tri(r: float = 0.16) -> T.Geometry:
	var sh := GM.ShapePath.new()
	var P := [[-0.5, 0.0], [0.5, 0.0], [0.0, 0.92]]
	var lerp2 := func(a: Array, b: Array, t: float) -> Array: return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
	for i in 3:
		var a: Array = P[(i + 2) % 3]
		var b: Array = P[i]
		var c: Array = P[(i + 1) % 3]
		var p0: Array = lerp2.call(b, a, r)
		var p1: Array = lerp2.call(b, c, r)
		if i == 0:
			sh.move_to(p0[0], p0[1])
		else:
			sh.line_to(p0[0], p0[1])
		sh.quad_to(b[0], b[1], p1[0], p1[1])
	sh.close_path()
	var g := GM.extrude_path(sh, 1, 3)
	g.translate(0, 0, -0.5)
	# flatten the bottom: shift so min y = 0
	g.compute_bounding_box()
	g.translate(0, -(g.bounding_box as AABB).position.y, 0)
	return g


static func bag_geo() -> T.Geometry:
	var g := Geo.box(1, 1, 1, 1, 3, 1)
	var p: T.Attr = g.attributes.position
	for i in p.count():
		var x := p.get_x(i)
		var y := p.get_y(i)
		var z := p.get_z(i)
		var t := pow(maxf(0.0, cos(PI * y * 0.98)), 0.55)
		var bx := 1.0 - 0.08 * (1.0 - cos(PI * x)) * t
		p.set_xyz(i, x * (0.96 + 0.04 * t) * (1.0 if absf(x) > 0.49 else bx), y, z * maxf(0.1, t) * (1.0 - 0.25 * absf(x)))
	g.translate(0, 0.5, 0)
	g.compute_vertex_normals()
	return g


static func carton_geo() -> T.Geometry:
	var body := box_nb()
	body.scale(1, 0.8, 1)
	var roof := T.Geometry.new()
	roof.set_attribute("position", T.Attr.new(PackedFloat32Array([-0.5, 0.8, 0.5, 0.5, 0.8, 0.5, 0.5, 0.96, 0, -0.5, 0.96, 0, 0.5, 0.8, -0.5, -0.5, 0.8, -0.5, -0.5, 0.96, 0, 0.5, 0.96, 0]), 3))
	roof.set_index([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	var gab := T.Geometry.new()
	gab.set_attribute("position", T.Attr.new(PackedFloat32Array([0.5, 0.8, 0.5, 0.5, 0.8, -0.5, 0.5, 0.96, 0, -0.5, 0.8, -0.5, -0.5, 0.8, 0.5, -0.5, 0.96, 0]), 3))
	gab.set_index([0, 1, 2, 3, 4, 5])
	var fin := Geo.box(1, 0.05, 0.08)
	fin.translate(0, 0.975, 0)
	var parts := []
	for x in [body, roof, gab, fin]:
		var y: T.Geometry = x.to_non_indexed() if x.indexed else x
		y.delete_attribute("uv")
		y.delete_attribute("normal")
		y.compute_vertex_normals()
		parts.append(y)
	return Geo.merge_geometries(parts, false)


static func leaf_geo() -> T.Geometry:
	var s := GM.ShapePath.new()
	s.move_to(0, 0)
	s.quad_to(0.42, 0.35, 0, 1)
	s.quad_to(-0.42, 0.35, 0, 0)
	return GM.shape_path_geometry(s, 3)


static func star_geo(n: int = 14, r_in: float = 0.18) -> T.Geometry:
	var s := GM.ShapePath.new()
	for i in n * 2 + 1:
		var a := float(i) / (n * 2) * PI * 2.0
		var r := r_in if i % 2 else 0.5
		var x := cos(a) * r
		var y := sin(a) * r
		if i == 0:
			s.move_to(x, y)
		else:
			s.line_to(x, y)
	var g := GM.shape_path_geometry(s, 1)
	g.rotate_x(-PI / 2.0)
	return g


static func cup_handle_geo() -> T.Geometry:
	var body := lathe([[0, 0, 0], [0.36, 0, 0], [0.4, 0.06, 0], [0.5, 0.9, 0], [0.5, 1.0, 0], [0.45, 1.0, 0], [0.4, 0.2, 0], [0, 0.18, 0]], 12)
	var h := Geo.torus(0.2, 0.05, 5, 8, PI * 1.2)
	h.rotate_z(-PI * 0.6)
	h.translate(0.52, 0.52, 0)
	body.delete_attribute("uv")
	h.delete_attribute("uv")
	return Geo.merge_geometries([body.to_non_indexed(), h.to_non_indexed()], false)


static func _rose_warp(phi: float, j: int) -> Array:
	return [0.08 * cos(phi * 5.0 + j * 1.3) if j >= 2 and j <= 4 else 0.0, 0.05 * cos(phi * 5.0) if j == 3 else 0.0]


static func _tulip_warp(phi: float, j: int) -> Array:
	return [0.0, 0.14 * maxf(0.0, cos(phi * 3.0)) if j == 4 else 0.0]


static func spot(k: int) -> Array:
	return SW[k]


static func kind_geo(kind: String) -> T.Geometry:
	match kind:
		"tile":
			var g := Geo.plane(1, 1)
			g.rotate_x(-PI / 2.0)
			return g
		"slab":
			return box_nb(true)
		"pbox":
			return proj_uv(ensure(box_nb()), {"front": FRONT, "back": FRONT, "top": spot(1), "side": spot(0)})
		"bag":
			return proj_uv(ensure(bag_geo()), {"half": true, "front": FRONT, "back": FRONT})
		"pet":
			return lathe([[0.48, 0, 0.04], [0.5, 0.05, 0.06], [0.5, 0.6, 0.58], [0.4, 0.7, 0.68], [0.2, 0.8, 0.78], [0.235, 0.815, 0.83], [0.235, 0.975, 0.96], [0, 1, 1]], 7)
		"can":
			return lathe([[0.46, 0, 0.04], [0.5, 0.05, 0.07], [0.5, 0.92, 0.92], [0.42, 0.99, 0.96], [0, 0.99, 1]], 8)
		# cheaper silhouettes for the rows behind the front facing (same label sheet)
		"petLo":
			return lathe([[0.5, 0.02, 0.05], [0.5, 0.6, 0.58], [0.22, 0.84, 0.82], [0, 0.99, 1]], 6)
		"canLo":
			return lathe([[0.5, 0.02, 0.05], [0.5, 0.95, 0.93], [0, 0.99, 1]], 6)
		"cupLo":
			return lathe([[0.37, 0.02, 0.06], [0.52, 0.9, 0.86], [0, 0.95, 1]], 6)
		"cupmen":
			return lathe([[0.37, 0.01, 0.06], [0.5, 0.88, 0.84], [0.53, 0.9, 0.87], [0.53, 0.95, 0.9], [0, 0.96, 1]], 8)
		"carton":
			return proj_uv(ensure(carton_geo()), {"front": FRONT, "back": FRONT, "top": spot(1), "side": spot(0)})
		"bento":
			return proj_uv(ensure(box_nb()), {"top": [0.02, 0.43, 0.98, 0.99], "front": [0.02, 0.12, 0.98, 0.38], "back": [0.02, 0.12, 0.98, 0.38], "side": spot(0)})
		"onigiri":
			return proj_uv(ensure(rounded_tri()), {"front": FRONT, "back": FRONT, "side": spot(0), "top": spot(0)})
		"sando":
			return proj_uv(ensure(extrude_y([[-0.5, 0], [0.5, 0], [0, 0.95]], 1)), {"front": FRONT, "back": FRONT, "side": spot(0), "top": spot(0)})
		"mag":
			return proj_uv(ensure(box_nb()), {"front": FRONT, "back": spot(2), "top": spot(0), "side": spot(0)})
		"book":
			return proj_uv(ensure(box_nb(false, false)), {"front": [0.04, 0.11, 0.96, 0.995], "back": spot(1), "top": spot(1), "side": spot(0), "tint": {"front": 1, "back": 0, "top": 0, "side": 1}})
		"cover":
			return proj_uv(ensure(box_nb()), {"front": FRONT, "back": spot(2), "top": spot(1), "side": spot(0), "tint": {"front": 1, "back": 1, "top": 0, "side": 1}})
		"album", "bmark":
			return proj_uv(ensure(box_nb()), {"front": FRONT, "back": FRONT, "top": spot(0), "side": spot(0)})
		"blister":
			return proj_uv(ensure(box_nb()), {"front": FRONT, "back": spot(2), "top": spot(0), "side": spot(0)})
		# plain (instance colour only)
		"blob":
			var g := Geo.sphere(0.5, 8, 6)
			g.translate(0, 0.5, 0)
			return g
		"bud":
			var g := Geo.icosahedron(0.5, 0)
			g.delete_attribute("normal")
			g.delete_attribute("uv")
			g = Geo.merge_vertices(g, 1e-4)
			g.compute_vertex_normals()
			g.translate(0, 0.5, 0)
			return g
		"cyl":
			var g := Geo.cylinder(0.5, 0.5, 1, 10)
			g.translate(0, 0.5, 0)
			return g
		"cyl6":
			var g := Geo.cylinder(0.5, 0.5, 1, 6)
			g.translate(0, 0.5, 0)
			return g
		"stem":
			var g := Geo.cylinder(0.5, 0.5, 1, 4, 1, true)
			g.translate(0, 0.5, 0)
			return g
		"leaf":
			return leaf_geo()
		"mcup":
			return lathe([[0.34, 0, 0], [0.5, 1, 0], [0.53, 0.98, 0], [0.47, 0.93, 0], [0.33, 0.03, 0]], 8)
		"ccup":
			return cup_handle_geo()
		"saucer":
			return lathe([[0, 0, 0], [0.3, 0, 0], [0.34, 0.05, 0], [0.5, 0.18, 0], [0.5, 0.24, 0], [0.3, 0.14, 0], [0, 0.12, 0]], 14)
		"plate":
			return lathe([[0, 0, 0], [0.36, 0, 0], [0.4, 0.3, 0], [0.5, 0.8, 0], [0.5, 1, 0], [0.38, 0.55, 0], [0, 0.5, 0]], 14)
		"rose":
			return lathe([[0, 0, 0], [0.36, 0.1, 0], [0.5, 0.45, 0], [0.45, 0.8, 0], [0.26, 0.86, 0], [0, 0.78, 0]], 7, "rose")
		"tulip":
			return lathe([[0, 0, 0], [0.28, 0.08, 0], [0.46, 0.4, 0], [0.45, 0.78, 0], [0.34, 0.96, 0]], 6, "tulip")
		"daisy":
			return star_geo(14, 0.2)
		"star5":
			return star_geo(5, 0.26)
		"cone":
			var g := Geo.cone(0.5, 1, 8, 1, true)
			g.translate(0, 0.5, 0)
			return g
		"ring":
			var g := Geo.torus(0.4, 0.1, 5, 10)
			g.rotate_x(PI / 2.0)
			g.translate(0, 0.1, 0)
			return g
	push_error("shopsA goods: unknown kind " + kind)
	return null


# ---------------------------------------------------------------- label sheets

func sheet(name: String) -> Dictionary:
	if _sheet_tex.has(name):
		return _sheet_tex[name]
	var s: Array = SHEETS[name]
	var t = ctx.tex.draw(s[0] * s[2], s[1] * s[3], null, {"key": "shopsA.sheet." + name, "anisotropy": 8})
	_sheet_tex[name] = {"t": t, "cols": s[0], "rows": s[1], "n": s[0] * s[1]}
	return _sheet_tex[name]


## toon + per-instance label cell + per-vertex tint mask (the shader patch is the renderer's)
func goods_mat(kind: String, inn: float, side) -> Dictionary:
	var mk := kind + "|" + GM.js_str(inn)
	if _mat_cache.has(mk):
		return _mat_cache[mk]
	var K: Array = KINDS[kind]
	var sh = sheet(K[0]) if K[0] != null else null
	var o := {"map": sh.t if sh != null else null, "paint": 0.02, "name": "shopsA-goods-%s-%s" % [kind, GM.js_str(inn if inn else 0)]}
	if side != null:
		o["side"] = side
	var m = ctx.mat.toon("#ffffff", o)
	var res := {"m": m, "sh": sh}
	_mat_cache[mk] = res
	return res


# ---------------------------------------------------------------- registry

## subsequent add() calls belong to this shop (one InstancedMesh per kind per shop); inner_glow = warm self-light
func set_shop(id: String, inner_glow: float = 0.42) -> void:
	shop = id
	inner = inner_glow


func count(kind: String) -> int:
	return sheet(KINDS[kind][0]).n


## add an instance: base = Object3D (its current world matrix is used) or a space S; pos / rot / scl in
## base-local coordinates; unit shapes have their origin at the bottom centre and face +z.
func add(kind: String, base, pos: Array, scl: Array, color = "#ffffff", rot = null, variant: int = 0, o: Dictionary = {}) -> void:
	var b = base.g if base is Common.Space else base
	if b != _last_base:
		GM.update_world(b)
		_last_base = b
	var e := Vector3(float(rot[0]) if rot != null and rot[0] else 0.0, float(rot[1]) if rot != null and rot[1] else 0.0, float(rot[2]) if rot != null and rot[2] else 0.0)
	var order := EULER_ORDER_XYZ
	if rot != null and rot.size() > 3 and rot[3]:
		order = {"XYZ": EULER_ORDER_XYZ, "XZY": EULER_ORDER_XZY, "YXZ": EULER_ORDER_YXZ, "YZX": EULER_ORDER_YZX, "ZXY": EULER_ORDER_ZXY, "ZYX": EULER_ORDER_ZYX}[rot[3]]
	var q := Basis.from_euler(e, order).get_rotation_quaternion()
	var m: Transform3D = b.matrix_world * T.compose(Vector3(pos[0], pos[1], pos[2]), q, Vector3(scl[0], scl[1], scl[2]))
	var inn: float = o.inner if o.get("inner") != null else inner
	var key := "%s|%s|%s" % [kind, shop, GM.js_str(inn)]
	if not lists.has(key):
		lists[key] = {"kind": kind, "inner": inn, "shop": shop, "items": []}
	lists[key].items.append({"m": m, "c": T.color(color), "v": variant})


func build() -> Array:
	var out := []
	for key in lists:
		var L2: Dictionary = lists[key]
		var items: Array = L2.items
		if items.is_empty():
			continue
		var K: Array = KINDS[L2.kind]
		var geo := ensure(kind_geo(L2.kind))
		var gm := goods_mat(L2.kind, L2.inner, K[1])
		var sh = gm.sh
		var n := items.size()
		var auv := PackedFloat32Array()
		auv.resize(n * 4)
		var im := T.InstancedMesh.new(geo, gm.m, n)
		for i in n:
			var it: Dictionary = items[i]
			im.set_matrix_at(i, it.m)
			im.set_color_at(i, it.c)
			if sh != null:
				var sn: int = sh.n
				var v: int = ((int(it.v) % sn) + sn) % sn
				var cx: int = v % int(sh.cols)
				var cy: int = v / int(sh.cols)
				auv[i * 4] = float(cx) / sh.cols
				auv[i * 4 + 1] = 1.0 - float(cy + 1) / sh.rows
				auv[i * 4 + 2] = 1.0 / sh.cols
				auv[i * 4 + 3] = 1.0 / sh.rows
			else:
				auv[i * 4] = 0.0
				auv[i * 4 + 1] = 0.0
				auv[i * 4 + 2] = 1.0
				auv[i * 4 + 3] = 1.0
		geo.user_data["aUV"] = auv
		im.cast_shadow = false
		im.receive_shadow = true
		im.name = "shopsA-goods-%s-%s" % [L2.kind, L2.shop]
		if K[2] == false:
			ctx.no_outline(im)
		ctx.add_static(im)
		out.append(im)
	return out


func stats() -> Dictionary:
	var s := {}
	for k in lists:
		s[k] = lists[k].items.size()
	return s
