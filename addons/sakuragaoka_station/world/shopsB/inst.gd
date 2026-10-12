# shopsB/inst.js: repeated small goods (cans, bottles, snack bags, sweets, bowls, beads, keys,
# chopsticks, tyres...) are collected in each shop's local space and emitted at the end as ONE
# InstancedMesh per (shape, glow) for the whole module, in world space, coloured per instance.
# Interior instances get the same warm self-light as K.im() (emissive = warm * instanceColor * glow).
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")

const SHAPE_NAMES := ["box", "boxc", "rbox", "pillow", "cyl", "cyl16", "cylc", "stick", "cup", "cone", "bottle", "gbottle",
	"sph", "ball", "bowl", "dish", "tumbler", "disc", "tyre", "ring"]

var ctx
var K
var groups := {}
var _order: Array = []
var geos := {}
var col_cache := {}


func _init(c, k) -> void:
	ctx = c
	K = k


static func _lathe(pts: Array, seg: int) -> T.Geometry:
	var v := []
	for p in pts:
		v.append(Vector2(p[0], p[1]))
	return Geo.lathe(v, seg)


## Soft pillow-shaped snack bag (unit: 1 wide (x), 1 tall (y), 1 thick (z) at the belly; bottom at y=0).
static func pillow_geo() -> T.Geometry:
	var g := Geo.box(1, 1, 1, 3, 4, 1)
	g.delete_attribute("normal")
	g.delete_attribute("uv")
	g = Geo.merge_vertices(g, 1e-4)
	var p: T.Attr = g.attributes["position"]
	for i in p.count():
		var x := p.get_x(i)
		var y := p.get_y(i)
		var z := p.get_z(i)
		var ex := 1.0 - pow(absf(x) * 2.0, 2.2)
		var ey := 1.0 - pow(absf(y) * 2.0, 3.0)
		var crimp := maxf(0.0, absf(y) * 2.0 - 0.84) / 0.16  # flat sealed seams top & bottom
		var bz := T.sign(z) * (0.12 + 0.38 * maxf(0.0, ex) * maxf(0.0, ey)) * (1.0 - crimp)
		p.set_xyz(i, x * (1.0 - 0.04 * crimp), y + 0.5, 0.0 if absf(z) < 1e-6 else bz + T.sign(z) * 0.03 * (1.0 - crimp))
	g.compute_vertex_normals()
	var uv := PackedFloat32Array()
	uv.resize(p.count() * 2)
	g.set_attribute("uv", T.Attr.new(uv, 2))
	return g


static func make_shape(shape: String) -> T.Geometry:
	match shape:
		"box": return Geo.box(1, 1, 1).translate(0, 0.5, 0)
		"boxc": return Geo.box(1, 1, 1)
		"rbox": return Geo.rounded_box(1, 1, 1, 1, 0.16).translate(0, 0.5, 0)
		"pillow": return pillow_geo()
		"cyl": return Geo.cylinder(0.5, 0.5, 1, 8).translate(0, 0.5, 0)
		"cyl16": return Geo.cylinder(0.5, 0.5, 1, 16).translate(0, 0.5, 0)
		"cylc": return Geo.cylinder(0.5, 0.5, 1, 6)  # centred (rods, handles)
		"stick": return Geo.cylinder(0.5, 0.5, 1, 5).translate(0, 0.5, 0)
		"cup": return Geo.cylinder(0.5, 0.37, 1, 10).translate(0, 0.5, 0)
		"cone": return Geo.cylinder(0.04, 0.5, 1, 10).translate(0, 0.5, 0)
		# PET bottle, unit height, radius 0.5
		"bottle": return _lathe([[0, 0], [0.46, 0], [0.5, 0.06], [0.5, 0.58], [0.3, 0.76], [0.17, 0.86], [0.17, 0.9], [0, 0.9]], 7)
		# 1 L glass bottle (soy sauce / sake), long neck
		"gbottle": return _lathe([[0, 0], [0.47, 0], [0.5, 0.05], [0.5, 0.56], [0.2, 0.74], [0.16, 0.96], [0.19, 1.0], [0, 1.0]], 8)
		"sph": return Geo.sphere(0.5, 9, 6)
		"ball": return Geo.sphere(0.5, 6, 4)
		# ramen / rice bowl: top radius 0.5, height 0.6, foot ring
		"bowl": return _lathe([[0, 0.04], [0.21, 0.04], [0.23, 0], [0.26, 0.05], [0.42, 0.34], [0.5, 0.6], [0.46, 0.6], [0.3, 0.2], [0, 0.1]], 12)
		# plate: radius 0.5, height 0.12
		"dish": return _lathe([[0, 0], [0.3, 0], [0.5, 0.1], [0.5, 0.12], [0.3, 0.05], [0, 0.05]], 12)
		# yunomi / tumbler: radius 0.5 top, height 1
		"tumbler": return _lathe([[0, 0], [0.42, 0], [0.5, 1], [0.45, 1], [0.37, 0.1], [0, 0.1]], 10)
		"disc": return Geo.cylinder(0.5, 0.5, 1, 10).translate(0, 0.5, 0)
		"tyre": return Geo.torus(0.5, 0.045, 5, 18)  # in XY plane, axis Z
		"ring": return Geo.torus(0.5, 0.03, 4, 16)
	return null


## parent.updateWorldMatrix(true, false): the world matrix through every ancestor.
static func world_of(o) -> Transform3D:
	var t := Transform3D()
	var cur = o
	while cur != null:
		cur.update_matrix()
		t = cur.matrix * t
		cur = cur.parent()
	return t


func col(c) -> Color:
	if c is Color:
		return c
	if not col_cache.has(c):
		col_cache[c] = T.color(c)
	return col_cache[c]


func material(glow: float):
	var m = ctx.mat.toon("#ffffff", {"name": "shopsB-inst", "emissive": "#ffc58a", "emissiveIntensity": glow, "paint": 0.04} if glow else {"name": "shopsB-inst-out", "paint": 0.04})
	if glow and not m.user_data.get("sbPatched", false):
		# the original patches the shader so the emissive is tinted by the instance colour
		m.user_data["sbPatched"] = true
	return m


## Add one instance. parent: Object3D (already positioned); pos/rot/scale in parent space.
## o: {glow (default 0.3; 0 = exterior), shadow (cast, default false)}
func add(shape: String, parent, pos: Array, scale, color, rot = null, o: Dictionary = {}) -> void:
	if not SHAPE_NAMES.has(shape):
		push_error("inst: unknown shape " + shape)
		return
	var glow: float = o.glow if o.get("glow") != null else 0.3
	var sh := bool(o.get("shadow", false))
	var key := "%s|%s|%s" % [shape, str(glow), str(sh)]
	var gr = groups.get(key)
	if gr == null:
		gr = {"shape": shape, "glow": glow, "sh": sh, "mats": [], "cols": []}
		groups[key] = gr
		_order.append(key)
	var pw := world_of(parent)
	var p := Vector3(pos[0], pos[1], pos[2])
	var q := Quaternion.IDENTITY
	if rot != null:
		q = T.quat_from_euler(Vector3(_n(rot, 0), _n(rot, 1), _n(rot, 2)))
	var s: Vector3
	if scale is float or scale is int:
		s = Vector3(scale, scale, scale)
	else:
		s = Vector3(scale[0], scale[1], scale[2])
	gr.mats.append(pw * T.compose(p, q, s))
	gr.cols.append(col(color))


static func _n(a, i: int) -> float:
	return float(a[i]) if i < a.size() and a[i] != null else 0.0


func count() -> int:
	var n := 0
	for k in _order:
		n += groups[k].mats.size()
	return n


func finish() -> Array:
	var out := []
	for k in _order:
		var gr = groups[k]
		var geo = geos.get(gr.shape)
		if geo == null:
			geo = make_shape(gr.shape)
			geos[gr.shape] = geo
		var mesh := T.InstancedMesh.new(geo, material(gr.glow), gr.mats.size())
		for i in gr.mats.size():
			mesh.set_matrix_at(i, gr.mats[i])
			mesh.set_color_at(i, gr.cols[i])
		mesh.cast_shadow = gr.sh
		mesh.receive_shadow = true
		mesh.name = "shopsB-inst-" + gr.shape
		ctx.add_static(mesh)
		out.append(mesh)
	groups.clear()
	_order.clear()
	return out
