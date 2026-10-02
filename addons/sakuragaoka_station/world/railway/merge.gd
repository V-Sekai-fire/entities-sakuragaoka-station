# railway/merge.js: the railway's static meshes merged per material into corridor-long meshes, so the
# thin 840 m corridor costs a few draw calls. Instanced, dynamic and noBatch meshes are left alone.
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Geo = preload("res://addons/sakuragaoka_station/core/geo.gd")


static func _normalise(o, inv: Transform3D) -> T.Geometry:
	var g: T.Geometry = o.geometry.clone()
	if not g.has_attribute("normal"):
		g.compute_vertex_normals()
	var n: int = g.attributes.position.count()
	if not g.has_attribute("uv"):
		var uv := PackedFloat32Array()
		uv.resize(n * 2)
		g.set_attribute("uv", T.Attr.new(uv, 2))
	var keep_color: bool = o.material.vertex_colors
	if keep_color and not g.has_attribute("color"):
		var c := PackedFloat32Array()
		c.resize(n * 3)
		c.fill(1.0)
		g.set_attribute("color", T.Attr.new(c, 3))
	for name in g.attributes.keys():
		if name == "position" or name == "normal" or name == "uv" or (keep_color and name == "color"):
			continue
		g.delete_attribute(name)
	if not g.indexed:
		var idx := PackedInt32Array()
		idx.resize(n)
		for i in n:
			idx[i] = i
		g.set_index(idx)
	g.clear_groups()
	var m: Transform3D = inv * o.matrix_world
	g.apply_matrix4(m)
	if m.basis.determinant() < 0:
		var ia := g.index
		for i in range(0, ia.size(), 3):
			var t := ia[i + 1]
			ia[i + 1] = ia[i + 2]
			ia[i + 2] = t
		g.index = ia
	return g


## Merges every plain static mesh under root by (material, layer, shadow flags, renderOrder, frustumCulled).
static func premerge(root) -> Dictionary:
	root.update_matrix_world(true)
	var inv: Transform3D = root.matrix_world.affine_inverse()
	var groups := {}
	root.traverse(func(o):
		if not o.is_mesh or o.is_instanced or o.user_data.get("noBatch", false) or o.user_data.get("dynamic", false):
			return
		if o.material is Array or not o.geometry.has_attribute("position"):
			return
		var key := "%d|%d|%d%d|%d|%d" % [o.material.get_instance_id(), o.layer, 1 if o.cast_shadow else 0, 1 if o.receive_shadow else 0, o.render_order, 1 if o.frustum_culled else 0]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(o))
	var meshes := 0
	var sources := 0
	var out := []
	for list in groups.values():
		if list.size() < 2:
			continue
		var geos := []
		for o in list:
			geos.append(_normalise(o, inv))
		var mg = Geo.merge_geometries(geos, false)
		if mg == null:
			continue
		mg.compute_bounding_box()
		var s = list[0]
		var mesh := T.MeshObj.new(mg, s.material)
		mesh.cast_shadow = s.cast_shadow
		mesh.receive_shadow = s.receive_shadow
		mesh.layer = s.layer
		mesh.render_order = s.render_order
		mesh.frustum_culled = s.frustum_culled
		mesh.name = "rw-merged"
		out.append(mesh)
		for o in list:
			if o.parent():
				o.parent().remove(o)
		meshes += 1
		sources += list.size()
	for m in out:
		root.add(m)
	var empties := []
	root.traverse(func(o):
		if o != root and not o.is_mesh and o.children.is_empty() and not o.user_data.get("dynamic", false):
			empties.append(o))
	for e in empties:
		if e.parent():
			e.parent().remove(e)
	return {"meshes": meshes, "sources": sources}
