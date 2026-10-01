# The port's three-shaped scene graph as Godot nodes, batched as src/core/batch2.js batches it:
# 48 m cells near the play area, 200 m beyond 150 m, colours baked into linear vertex colours,
# one draw per cell and material signature. Closed toon solids are united per cell by CSG first,
# which drops the faces hidden where solids meet; CSG takes only geometry that passes the manifold
# check, and everything else is appended as it is. Instanced meshes become MultiMeshes.
#   realize(ctx, root); await one process frame (CSG computes then); finish()
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Svg = preload("res://addons/sakuragaoka_station/core/svg.gd")
const TOON := preload("res://addons/sakuragaoka_station/core/toon.gdshader")

const NEAR_CELL := 48.0
const FAR_CELL := 200.0
const FAR_R := 150.0
const WELD := 10000.0

var stats := {"meshes": 0, "solids": 0, "surfaces": 0, "single": 0, "instanced": 0, "skipped": 0,
		"batches": 0, "csg_in": 0, "csg_out": 0, "csg_failed": 0, "manifold": 0, "open": 0}
var _root: Node3D
var _geo := {}
var _plain := {}
var _shaders := {}
var _materials := {}
var _solid_mat := {}
var _colour_of := {}
var _batches := {}
var _combiners := []
var _comb_by_key := {}


func realize(ctx, root: Node3D) -> void:
	_root = root
	ctx.scene.update_matrix_world(true)
	_walk(ctx.static_root, false)
	_walk(ctx.dynamic_root, true)


func finish() -> void:
	for e in _combiners:
		var comb: CSGCombiner3D = e[0]
		var baked: ArrayMesh = comb.bake_static_mesh()
		if baked == null or baked.get_surface_count() == 0:
			stats.csg_failed += 1
			for s in comb.get_children():
				_append(e[1], s.mesh.surface_get_arrays(0), _colour_of[s.material], s.transform)
		else:
			for i in baked.get_surface_count():
				var a := baked.surface_get_arrays(i)
				stats.csg_out += _tri_count(a)
				_append(e[1], a, _colour_of.get(baked.surface_get_material(i), Color(1, 0, 1)), Transform3D.IDENTITY)
		comb.queue_free()
	_combiners.clear()
	_comb_by_key.clear()
	for key in _batches:
		var b: Dictionary = _batches[key]
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = b.pos
		a[Mesh.ARRAY_NORMAL] = b.nor
		a[Mesh.ARRAY_COLOR] = b.col
		a[Mesh.ARRAY_INDEX] = b.idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		am.surface_set_material(0, b.mat)
		var mi := MeshInstance3D.new()
		mi.name = ("batch %s" % key).validate_node_name()
		mi.mesh = am
		_root.add_child(mi)
		stats.batches += 1
	_batches.clear()


func _walk(o, alone: bool) -> void:
	if not o.visible:
		return
	var nb: bool = alone or o.user_data.get("noBatch", false)
	if o.is_instanced:
		_instanced(o)
	elif o.is_mesh:
		_mesh(o, nb)
	for c in o.children:
		_walk(c, nb)


func _mesh(o, alone: bool) -> void:
	stats.meshes += 1
	var g = o.geometry
	if g.position() == null or g.vertex_count() == 0:
		stats.skipped += 1
		return
	var mats: Array = o.materials()
	var m = mats[0]
	if alone or mats.size() > 1 or m == null or not (m.type == "toon" or m.type == "basic") \
			or m.map != null or m.alpha_map != null:
		_single(o)
		return
	var key := _cell(o) + "|" + _sig(m)
	var gd := _geo_data(g)
	if m.type == "toon" and gd.closed:
		_solid(o, gd, m.color, key, m)
	else:
		_batch(key, m)
		_append(key, gd.arrays, m.color, o.matrix_world)
		stats.surfaces += 1


func _solid(o, gd: Dictionary, colour: Color, key: String, m) -> void:
	var comb: CSGCombiner3D = _comb_by_key.get(key)
	if comb == null:
		comb = CSGCombiner3D.new()
		comb.name = ("csg %s" % key).validate_node_name()
		comb.visible = false
		_root.add_child(comb)
		_combiners.append([comb, key])
		_comb_by_key[key] = comb
		_batch(key, m)
	var s := CSGMesh3D.new()
	s.mesh = _plain_mesh(gd)
	s.material = _solid_material(colour)
	s.transform = o.matrix_world
	comb.add_child(s)
	stats.solids += 1
	stats.csg_in += _tri_count(gd.arrays)


func _instanced(o) -> void:
	stats.instanced += 1
	var gd := _geo_data(o.geometry)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = o.instance_color != null
	mm.mesh = _plain_mesh(gd)
	mm.instance_count = o.count
	for i in o.count:
		mm.set_instance_transform(i, o.instance_matrix[i])
		if mm.use_colors:
			mm.set_instance_color(i, o.instance_color[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = o.name if o.name != "" else "instanced"
	mmi.multimesh = mm
	mmi.transform = o.matrix_world
	mmi.material_override = _material(o.materials()[0], false)
	_root.add_child(mmi)


func _single(o) -> void:
	stats.single += 1
	var g = o.geometry
	var gd := _geo_data(g)
	var mats: Array = o.materials()
	var am := ArrayMesh.new()
	var groups: Array = g.groups if mats.size() > 1 and not g.groups.is_empty() else [{"start": 0, "count": gd.idx.size(), "material_index": 0}]
	for gr in groups:
		var a: Array = gd.arrays.duplicate()
		var start: int = gr.start
		var count: int = mini(gr.count, gd.idx.size() - start)
		if count <= 0:
			continue
		a[Mesh.ARRAY_INDEX] = gd.idx.slice(start, start + count)
		var m = mats[mini(int(gr.material_index), mats.size() - 1)]
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		am.surface_set_material(am.get_surface_count() - 1, _material(m, false))
	if am.get_surface_count() == 0:
		stats.skipped += 1
		return
	var mi := MeshInstance3D.new()
	mi.name = o.name if o.name != "" else "mesh"
	mi.mesh = am
	mi.transform = o.matrix_world
	_root.add_child(mi)


func _cell(o) -> String:
	var box: AABB = o.matrix_world * _geo_data(o.geometry).aabb
	var c := box.get_center()
	var far := maxf(absf(c.x), absf(c.z - 10.0)) > FAR_R
	var cell := FAR_CELL if far else NEAR_CELL
	if box.size.x > cell * 1.5 or box.size.z > cell * 1.5:
		return "L"
	return "%s%d,%d" % ["f" if far else "n", floori(c.x / cell), floori(c.z / cell)]


func _sig(m) -> String:
	var t: Dictionary = m.user_data.get("toon", {})
	return "%s|%s|%s|%.3f|%.3f|%s|%s|%.2f|%s" % [m.type, m.side, m.transparent, m.opacity, m.alpha_test,
			m.depth_write, m.emissive.to_html(false), m.emissive_intensity, t.get("polygonOffset", 0)]


func _batch(key: String, m) -> Dictionary:
	if not _batches.has(key):
		_batches[key] = {"pos": PackedVector3Array(), "nor": PackedVector3Array(), "col": PackedColorArray(),
				"idx": PackedInt32Array(), "mat": _material(m, true)}
	return _batches[key]


func _append(key: String, a: Array, colour: Color, xform: Transform3D) -> void:
	var b: Dictionary = _batches[key]
	var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var base: int = b.pos.size()
	b.pos.append_array(xform * pos)
	var nor = a[Mesh.ARRAY_NORMAL]
	if nor != null and nor.size() == pos.size():
		b.nor.append_array(Transform3D(xform.basis.inverse().transposed(), Vector3.ZERO) * nor)
	else:
		var up := PackedVector3Array()
		up.resize(pos.size())
		up.fill(Vector3.UP)
		b.nor.append_array(up)
	var col := PackedColorArray()
	col.resize(pos.size())
	col.fill(colour)
	b.col.append_array(col)
	var ix = a[Mesh.ARRAY_INDEX]
	if ix == null:
		ix = _range(pos.size())
	var out := PackedInt32Array()
	out.resize(ix.size())
	for i in ix.size():
		out[i] = ix[i] + base
	b.idx.append_array(out)


func _geo_data(g) -> Dictionary:
	if _geo.has(g):
		return _geo[g]
	var pos: PackedVector3Array = g.position().vec3_array()
	var na = g.get_attribute("normal")
	var nor: PackedVector3Array = na.vec3_array() if na != null and na.count() == pos.size() else PackedVector3Array()
	var idx: PackedInt32Array = g.index if g.indexed else _range(pos.size())
	if g.draw_count >= 0:
		idx = idx.slice(g.draw_start, g.draw_start + g.draw_count)
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = pos
	if nor.size() == pos.size():
		a[Mesh.ARRAY_NORMAL] = nor
	a[Mesh.ARRAY_INDEX] = idx
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in pos:
		lo = lo.min(p)
		hi = hi.max(p)
	var closed := _manifold(pos, idx)
	stats.manifold += 1 if closed else 0
	stats.open += 0 if closed else 1
	var d := {"arrays": a, "idx": idx, "aabb": AABB(lo, hi - lo), "closed": closed}
	_geo[g] = d
	return d


## Closed and consistently wound once vertices are welded by position: every directed edge
## appears once and its reverse once. Degenerate triangles are ignored.
func _manifold(pos: PackedVector3Array, idx: PackedInt32Array) -> bool:
	if idx.size() < 12:
		return false
	var weld := {}
	var id := PackedInt32Array()
	id.resize(pos.size())
	for i in pos.size():
		var p := pos[i]
		var k := Vector3i(roundi(p.x * WELD), roundi(p.y * WELD), roundi(p.z * WELD))
		var w = weld.get(k)
		if w == null:
			w = weld.size()
			weld[k] = w
		id[i] = w
	var n := weld.size()
	var fwd := PackedInt64Array()
	var rev := PackedInt64Array()
	for t in range(0, idx.size() - 2, 3):
		var a := id[idx[t]]
		var b := id[idx[t + 1]]
		var c := id[idx[t + 2]]
		if a == b or b == c or c == a:
			continue
		fwd.push_back(a * n + b)
		fwd.push_back(b * n + c)
		fwd.push_back(c * n + a)
		rev.push_back(b * n + a)
		rev.push_back(c * n + b)
		rev.push_back(a * n + c)
	if fwd.size() < 12:
		return false
	fwd.sort()
	rev.sort()
	if fwd != rev:
		return false
	for i in range(1, fwd.size()):
		if fwd[i] == fwd[i - 1]:
			return false
	return true


func _plain_mesh(gd: Dictionary) -> ArrayMesh:
	if _plain.has(gd):
		return _plain[gd]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, gd.arrays)
	_plain[gd] = am
	return am


func _solid_material(colour: Color) -> Material:
	var k := colour.to_html()
	if not _solid_mat.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		_solid_mat[k] = m
		_colour_of[m] = colour
	return _solid_mat[k]


func _material(m, batched: bool) -> Material:
	if m == null:
		m = T.Mat.new()
	var k := "%s|%s" % [m.get_instance_id(), batched]
	if _materials.has(k):
		return _materials[k]
	var sm := ShaderMaterial.new()
	sm.shader = _shader(m)
	var c: Color = Color(1, 1, 1) if batched else m.color
	c.a = m.opacity if m.transparent else 1.0
	sm.set_shader_parameter("albedo", c)
	sm.set_shader_parameter("emission", Vector3(m.emissive.r, m.emissive.g, m.emissive.b) * m.emissive_intensity)
	sm.set_shader_parameter("alpha_scissor", m.alpha_test)
	var bg = Svg.sign_colour(m.map)
	if bg != null:
		sm.set_shader_parameter("albedo", Color(c.r * bg.r, c.g * bg.g, c.b * bg.b, c.a))
	_materials[k] = sm
	return sm


func _shader(m) -> Shader:
	var cull: String = {"double": "cull_disabled", "back": "cull_front"}.get(m.side, "cull_back")
	var alpha: bool = m.transparent
	var lit: bool = m.type != "basic"
	var decal: bool = m.user_data.get("toon", {}).get("polygonOffset", 0) != 0
	var k := "%s|%s|%s|%s" % [cull, alpha, lit, decal]
	if not _shaders.has(k):
		var code := TOON.code.replace("cull_back", cull)
		if not lit:
			code = code.replace("specular_disabled", "unshaded")
		if not m.depth_write:
			code = code.replace("specular_disabled", "specular_disabled, depth_draw_never")
		if alpha:
			code = code.replace("// ALPHA", "ALPHA = c.a;")
		if decal:
			code = code.replace("// DECAL", "VERTEX += NORMAL * 0.003;")
		var s := Shader.new()
		s.code = code
		_shaders[k] = s
	return _shaders[k]


static func _range(n: int) -> PackedInt32Array:
	var r := PackedInt32Array()
	r.resize(n)
	for i in n:
		r[i] = i
	return r


static func _tri_count(a: Array) -> int:
	var ix = a[Mesh.ARRAY_INDEX]
	return (ix.size() if ix != null else a[Mesh.ARRAY_VERTEX].size()) / 3
