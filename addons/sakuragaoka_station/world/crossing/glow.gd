# crossing/glow.js: soft lamp halos (camera-facing billboards, one merged mesh per flash phase) and faint
# light cones for the crossing's flashing lights. Each mesh owns its material, whose uniforms.uOn the
# crossing's update switches; off, the material is fully transparent.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")

static var _serial := 0


static func _glow_mat(ctx, kind: String, color: String, intensity: float, extra: Dictionary):
	_serial += 1
	var m = ctx.mat.shader("%s#%d" % [kind, _serial], color, {"transparent": true, "depthWrite": false})
	m.opacity = 0.0
	m.uniforms = {"uColor": {"value": T.color(color) * intensity}, "uOn": {"value": 0.0}}
	m.uniforms.merge(extra)
	return m


## items: [{c: Vector3 (world centre), n: Vector3 (world facing), size}]
static func make_halo_mesh(ctx, items: Array, color: String, opts: Dictionary = {}):
	var intensity: float = opts.get("intensity", 1.6)
	var streak: float = opts.get("streak", 1.0)
	var n := items.size()
	var pos := PackedFloat32Array()
	var cen := PackedFloat32Array()
	var dir := PackedFloat32Array()
	var cor := PackedFloat32Array()
	var siz := PackedFloat32Array()
	var idx := PackedInt32Array()
	var C := [[-1, -1], [1, -1], [1, 1], [-1, 1]]
	for i in n:
		var it: Dictionary = items[i]
		for j in 4:
			pos.append_array([it.c.x, it.c.y, it.c.z])
			cen.append_array([it.c.x, it.c.y, it.c.z])
			dir.append_array([it.n.x, it.n.y, it.n.z])
			cor.append_array(C[j])
			siz.append(it.get("size", 0.5))
		idx.append_array([i * 4, i * 4 + 1, i * 4 + 2, i * 4, i * 4 + 2, i * 4 + 3])
	var g := T.Geometry.new()
	g.set_attribute("position", T.Attr.new(pos, 3))
	g.set_attribute("aCenter", T.Attr.new(cen, 3))
	g.set_attribute("aDir", T.Attr.new(dir, 3))
	g.set_attribute("aCorner", T.Attr.new(cor, 2))
	g.set_attribute("aSize", T.Attr.new(siz, 1))
	g.set_index(idx)
	var mesh := T.MeshObj.new(g, _glow_mat(ctx, "crossing-halo", color, intensity, {"uStreak": {"value": streak}}))
	mesh.render_order = 5
	mesh.cast_shadow = false
	mesh.receive_shadow = false
	mesh.name = "crossing-halo"
	ctx.no_outline(mesh)
	return mesh


## items: [{c, n}] -> merged open cones (apex at the lens, opening along n).
static func make_cone_mesh(ctx, items: Array, color: String, opts: Dictionary = {}):
	var length: float = opts.get("length", 1.3)
	var r0: float = opts.get("r0", 0.13)
	var r1: float = opts.get("r1", 0.5)
	var intensity: float = opts.get("intensity", 1.2)
	var geos := []
	for it in items:
		var cg := Geo.cylinder(r1, r0, length, 14, 1, true)
		var p: T.Attr = cg.attributes.position
		var al := PackedFloat32Array()
		al.resize(p.count())
		for i in p.count():
			al[i] = p.get_y(i) / length + 0.5
		cg.set_attribute("aAlong", T.Attr.new(al, 1))
		cg.translate(0, length / 2.0, 0)
		var q := T.quat_from_unit_vectors(Vector3.UP, (it.n as Vector3).normalized())
		cg.apply_matrix4(T.compose(it.c, q, Vector3.ONE))
		cg.delete_attribute("uv")
		geos.append(cg)
	var g = Geo.merge_geometries(geos, false)
	var m = _glow_mat(ctx, "crossing-cone", color, intensity, {})
	m.side = "double"
	var mesh := T.MeshObj.new(g, m)
	mesh.render_order = 4
	mesh.cast_shadow = false
	mesh.receive_shadow = false
	mesh.name = "crossing-cone"
	ctx.no_outline(mesh)
	return mesh
