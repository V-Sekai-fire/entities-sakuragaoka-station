# The port's three-shaped scene graph as Godot nodes, batched as src/core/batch2.js batches it
# (48 m cells near the play area, 200 m beyond 150 m) and shaded with godot-vrm's MToon. MToon
# reads its colour from a texture, so each face's colour is an index into a palette texture carried
# in UV; CSG keeps UV through a union where it would drop vertex colour, and every closed solid of
# a cell goes through CSG. A cell keeps the union only when it comes out no larger than its solids.
# Open surfaces are appended as they are, instanced meshes become MultiMeshes at their material's
# colour, and alpha-cut cards wait for Slug to draw them.
#   realize(ctx, root); await one process frame (CSG computes then); finish()
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Svg = preload("res://addons/sakuragaoka_station/core/svg.gd")
const SakuraTree = preload("res://addons/sakuragaoka_station/world/sakura/tree.gd")

const MTOON := "res://addons/Godot-MToon-Shader/"
## Each keyed canvas texture's mean linear colour, read from the original's canvases by its
## tools/texture_means.mjs: a textured surface takes it until Slug draws the texture itself.
const MEANS := "res://addons/sakuragaoka_station/core/texture_means.json"
const NEAR_CELL := 48.0
const FAR_CELL := 200.0
const FAR_R := 150.0
const WELD := 10000.0
const PALETTE := 512
const SHADE := Color(0.72, 0.68, 0.82)

var stats := {"meshes": 0, "solids": 0, "surfaces": 0, "single": 0, "instanced": 0, "skipped": 0,
		"held": 0, "blob": 0, "batches": 0, "csg_in": 0, "csg_out": 0, "csg_failed": 0, "csg_raw": 0,
		"manifold": 0, "open": 0, "colours": 0, "instance_tints_dropped": 0}
var _root: Node3D
var _palette := {}
var _palette_img: Image
var _palette_tex: ImageTexture
var _geo := {}
var _coloured_cache := {}
var _meshes := {}
var _materials := {}
var _batches := {}
var _combiners := []
var _comb_by_key := {}
var _means: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MEANS))


func realize(ctx, root: Node3D) -> void:
	_root = root
	_palette_img = Image.create(PALETTE, PALETTE, false, Image.FORMAT_RGBA8)
	_palette_img.fill(Color(1, 0, 1))
	_palette_tex = ImageTexture.create_from_image(_palette_img)
	ctx.scene.update_matrix_world(true)
	_walk(ctx.static_root, false)
	_walk(ctx.dynamic_root, true)


## Realizes the given objects alone, whose world matrices are already current.
func realize_part(objs: Array, root: Node3D) -> void:
	_root = root
	_palette_img = Image.create(PALETTE, PALETTE, false, Image.FORMAT_RGBA8)
	_palette_img.fill(Color(1, 0, 1))
	_palette_tex = ImageTexture.create_from_image(_palette_img)
	for o in objs:
		_walk(o, false)


func finish() -> void:
	_palette_tex.update(_palette_img)
	stats.colours = _palette.size()
	for e in _combiners:
		var comb: CSGCombiner3D = e[0]
		var baked: ArrayMesh = comb.bake_static_mesh()
		var surfaces := []
		var out := 0
		if baked != null:
			for i in baked.get_surface_count():
				var a := baked.surface_get_arrays(i)
				surfaces.append(a)
				out += _tri_count(a)
		if surfaces.is_empty() or out > e[2]:
			stats.csg_failed += 1 if surfaces.is_empty() else 0
			stats.csg_raw += 0 if surfaces.is_empty() else 1
			stats.csg_out += e[2]
			for s in comb.get_children():
				_append(e[1], s.mesh.surface_get_arrays(0), s.transform)
		else:
			stats.csg_out += out
			for a in surfaces:
				_append(e[1], a, Transform3D.IDENTITY)
		comb.queue_free()
	_combiners.clear()
	_comb_by_key.clear()
	for key in _batches:
		var b: Dictionary = _batches[key]
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = b.pos
		a[Mesh.ARRAY_NORMAL] = b.nor
		a[Mesh.ARRAY_TEX_UV] = b.uv
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
	var det: float = o.matrix_world.basis.determinant()
	if g.position() == null or g.vertex_count() == 0 or absf(det) < 1e-12:
		stats.skipped += 1
		return
	var mats: Array = o.materials()
	var m = mats[0]
	if m != null and m.alpha_test > 0.0 and m.map != null:
		# an alpha-cut card's shape is its drawn texture; it waits for Slug to draw it
		stats.held += 1
		return
	if alone or mats.size() > 1 or m == null or not (m.type == "toon" or m.type == "basic") \
			or m.map != null or m.alpha_map != null:
		_single(o)
		return
	var gd := _geo_data(g)
	var blob: bool = m.user_data.has("sakura") and m.user_data["sakura"].get("band", false)
	var cols = _blob_cols(g, gd) if blob else (gd.cols if m.vertex_colors else null)
	stats.blob += 1 if blob else 0
	var key := _cell(o, gd) + "|" + _mat_key(m)
	var r := _coloured(gd, gd.idx, m.color, cols, "g%d" % gd.id)
	_batch(key, m)
	if gd.closed and det > 0.0:
		_solid(o, r, key)
	else:
		_append(key, r.a, o.matrix_world)
		stats.surfaces += 1


func _solid(o, r: Dictionary, key: String) -> void:
	var e = _comb_by_key.get(key)
	if e == null:
		var c := CSGCombiner3D.new()
		c.name = ("csg %s" % key).validate_node_name()
		c.visible = false
		_root.add_child(c)
		e = [c, key, 0]
		_combiners.append(e)
		_comb_by_key[key] = e
	var s := CSGMesh3D.new()
	s.mesh = _array_mesh(r)
	s.material = _batches[key].mat
	s.transform = o.matrix_world
	e[0].add_child(s)
	e[2] += _tri_count(r.a)
	stats.solids += 1
	stats.csg_in += _tri_count(r.a)


func _instanced(o) -> void:
	var m = o.materials()[0]
	if m == null:
		m = T.Mat.new()
	if absf(o.matrix_world.basis.determinant()) < 1e-12:
		stats.skipped += 1
		return
	if m.alpha_test > 0.0 and m.map != null:
		stats.held += 1
		return
	stats.instanced += 1
	var gd := _geo_data(o.geometry)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _array_mesh(_coloured(gd, gd.idx, m.color, gd.cols if m.vertex_colors else null, "g%d" % gd.id))
	mm.instance_count = o.count
	for i in o.count:
		mm.set_instance_transform(i, o.instance_matrix[i])
	if o.instance_color != null:
		stats.instance_tints_dropped += o.count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = o.name if o.name != "" else "instanced"
	mmi.multimesh = mm
	mmi.transform = o.matrix_world
	mmi.material_override = _mtoon(m)
	_root.add_child(mmi)


func _single(o) -> void:
	var g = o.geometry
	var det: float = o.matrix_world.basis.determinant()
	if g.position() == null or g.vertex_count() == 0 or absf(det) < 1e-12:
		stats.skipped += 1
		return
	stats.single += 1
	var gd := _geo_data(g)
	var mats: Array = o.materials()
	var groups: Array = g.groups if mats.size() > 1 and not g.groups.is_empty() else [{"start": 0, "count": gd.idx.size(), "material_index": 0}]
	var am := ArrayMesh.new()
	for gr in groups:
		var start: int = gr.start
		var count: int = mini(gr.count, gd.idx.size() - start)
		if count <= 0:
			continue
		var m = mats[mini(int(gr.material_index), mats.size() - 1)]
		if m == null:
			m = T.Mat.new()
		var colour: Color = m.color
		var bg = Svg.sign_colour(m.map)
		if bg != null:
			colour *= bg
		elif m.map != null and _means.has(str(m.map.user_data.get("key", ""))):
			var mc: Array = _means[m.map.user_data["key"]]
			colour *= Color(mc[0], mc[1], mc[2])
		var blob: bool = m.user_data.has("sakura") and m.user_data["sakura"].get("band", false)
		stats.blob += 1 if blob else 0
		var cols = _blob_cols(g, gd) if blob else (gd.cols if m.vertex_colors else null)
		var r := _coloured(gd, gd.idx.slice(start, start + count), colour, cols, "g%d:%d" % [gd.id, start])
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r.a)
		am.surface_set_material(am.get_surface_count() - 1, _mtoon(m))
	if am.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = o.name if o.name != "" else "mesh"
	mi.mesh = am
	mi.transform = o.matrix_world
	_root.add_child(mi)


## The arrays of one object's faces with palette UVs. One colour keeps the geometry indexed, cached
## per geometry and colour; per-vertex colours split the faces, each taking the mean of its three.
func _coloured(gd: Dictionary, idx: PackedInt32Array, colour: Color, cols, ck: String) -> Dictionary:
	var src: Array = gd.arrays
	if cols == null:
		var k := "%s|%s" % [ck, colour.to_html()]
		if _coloured_cache.has(k):
			return _coloured_cache[k]
		var a: Array = src.duplicate()
		var uv := PackedVector2Array()
		uv.resize(src[Mesh.ARRAY_VERTEX].size())
		uv.fill(_uv_of(colour))
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_INDEX] = idx
		var r := {"a": a, "k": k}
		_coloured_cache[k] = r
		return r
	var pos: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var nor = src[Mesh.ARRAY_NORMAL]
	var n := idx.size() - idx.size() % 3
	var p2 := PackedVector3Array()
	p2.resize(n)
	var n2 := PackedVector3Array()
	n2.resize(n if nor != null else 0)
	var uv := PackedVector2Array()
	uv.resize(n)
	for t in range(0, n, 3):
		var ia := idx[t]
		var ib := idx[t + 1]
		var ic := idx[t + 2]
		var u := _uv_of((cols[ia] + cols[ib] + cols[ic]) / 3.0 * colour)
		p2[t] = pos[ia]
		p2[t + 1] = pos[ib]
		p2[t + 2] = pos[ic]
		if nor != null:
			n2[t] = nor[ia]
			n2[t + 1] = nor[ib]
			n2[t + 2] = nor[ic]
		uv[t] = u
		uv[t + 1] = u
		uv[t + 2] = u
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = p2
	if nor != null:
		a[Mesh.ARRAY_NORMAL] = n2
	a[Mesh.ARRAY_TEX_UV] = uv
	return {"a": a, "k": ""}


func _array_mesh(r: Dictionary) -> ArrayMesh:
	if r.k != "" and _meshes.has(r.k):
		return _meshes[r.k]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r.a)
	if r.k != "":
		_meshes[r.k] = am
	return am


## The palette texel holding a linear colour, stored as 8-bit sRGB since MToon samples it as colour.
func _uv_of(c: Color) -> Vector2:
	var s := c.linear_to_srgb()
	var k := (clampi(roundi(s.r * 255.0), 0, 255) << 16) | (clampi(roundi(s.g * 255.0), 0, 255) << 8) \
			| clampi(roundi(s.b * 255.0), 0, 255)
	var i = _palette.get(k)
	if i == null:
		i = mini(_palette.size(), PALETTE * PALETTE - 1)
		_palette[k] = i
		_palette_img.set_pixel(i % PALETTE, i / PALETTE, Color8((k >> 16) & 255, (k >> 8) & 255, k & 255))
	return Vector2((i % PALETTE + 0.5) / PALETTE, (i / PALETTE + 0.5) / PALETTE)


## A blossom mass's colour attribute is (tone, peach + 2 * palette, shading normal y); its colour is
## the tone's band in that palette, mixed toward peach. The world-space noise on the band edges and
## the shading normal are not carried.
func _blob_cols(g, gd: Dictionary) -> PackedColorArray:
	if gd.has("blob"):
		return gd.blob
	var ca = g.get_attribute("color")
	var bands: Dictionary = SakuraTree.BANDS
	var bn: Array = bands.normal.map(func(h): return Color.html(h).srgb_to_linear())
	var bw: Array = bands.weeping.map(func(h): return Color.html(h).srgb_to_linear())
	var pe := Color.html(bands.peach).srgb_to_linear()
	var out := PackedColorArray()
	out.resize(ca.count())
	for i in out.size():
		var tn: float = ca.get_x(i)
		var gc: float = ca.get_y(i)
		var pal := 1 if gc >= 1.5 else 0
		var band: Array = bw if pal == 1 else bn
		var b: Color = band[3 if tn >= 0.75 else (2 if tn >= 0.5 else (1 if tn >= 0.25 else 0))]
		out[i] = b.lerp(pe, clampf(gc - 2.0 * pal, 0.0, 1.0))
	gd.blob = out
	return out


func _cell(o, gd: Dictionary) -> String:
	var box: AABB = o.matrix_world * gd.aabb
	var c := box.get_center()
	var far := maxf(absf(c.x), absf(c.z - 10.0)) > FAR_R
	var cell := FAR_CELL if far else NEAR_CELL
	if box.size.x > cell * 1.5 or box.size.z > cell * 1.5:
		return "L"
	return "%s%d,%d" % ["f" if far else "n", floori(c.x / cell), floori(c.z / cell)]


func _mat_key(m) -> String:
	var s: Dictionary = m.user_data.get("sakura", {})
	return "%s|%s|%s|%.3f|%.3f|%s|%.2f|%s" % [m.type, m.side, m.transparent, m.opacity, m.alpha_test,
			m.emissive.to_html(false), m.emissive_intensity, s.get("rim", 0)]


func _batch(key: String, m) -> Dictionary:
	if not _batches.has(key):
		_batches[key] = {"pos": PackedVector3Array(), "nor": PackedVector3Array(), "uv": PackedVector2Array(),
				"idx": PackedInt32Array(), "mat": _mtoon(m)}
	return _batches[key]


func _append(key: String, a: Array, xform: Transform3D) -> void:
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
	b.uv.append_array(a[Mesh.ARRAY_TEX_UV])
	var ix = a[Mesh.ARRAY_INDEX]
	if ix == null:
		ix = _range(pos.size())
	if xform.basis.determinant() < 0.0:
		ix = _flipped(ix)
	var out := PackedInt32Array()
	out.resize(ix.size())
	for i in ix.size():
		out[i] = ix[i] + base
	b.idx.append_array(out)


## MToon for a material: the palette is both its lit and its shade texture; an unlit ("basic")
## material shows the palette as emission with its lit and shade colours black.
func _mtoon(m) -> ShaderMaterial:
	var k := _mat_key(m)
	if _materials.has(k):
		return _materials[k]
	var v := "mtoon"
	if m.transparent:
		v = "mtoon_trans"
	elif m.alpha_test > 0.0:
		v = "mtoon_cutout"
	if m.side != "front":
		v += "_cull_off"
	var sm := ShaderMaterial.new()
	sm.shader = load(MTOON + v + ".gdshader")
	sm.set_shader_parameter("_MainTex", _palette_tex)
	sm.set_shader_parameter("_ShadeTexture", _palette_tex)
	sm.set_shader_parameter("_Color", Color(1, 1, 1, m.opacity if m.transparent else 1.0))
	sm.set_shader_parameter("_ShadeColor", SHADE)
	sm.set_shader_parameter("_ShadeToony", 0.9)
	sm.set_shader_parameter("_ShadeShift", 0.0)
	if m.alpha_test > 0.0:
		sm.set_shader_parameter("_AlphaCutoutEnable", 1.0)
		sm.set_shader_parameter("_Cutoff", m.alpha_test)
	if m.type == "basic":
		sm.set_shader_parameter("_Color", Color(0, 0, 0, m.opacity if m.transparent else 1.0))
		sm.set_shader_parameter("_ShadeColor", Color(0, 0, 0))
		sm.set_shader_parameter("_EmissionMap", _palette_tex)
		sm.set_shader_parameter("_EmissionColor", Color(1, 1, 1))
	elif m.emissive != Color(0, 0, 0):
		sm.set_shader_parameter("_EmissionColor", (m.emissive * m.emissive_intensity).linear_to_srgb())
	var rim: float = float(m.user_data.get("sakura", {}).get("rim", 0.0))
	if rim > 0.0:
		sm.set_shader_parameter("_RimColor", Color(1.0, 0.64, 0.75) * rim)
		sm.set_shader_parameter("_RimFresnelPower", 2.2)
	_materials[k] = sm
	return sm


func _geo_data(g) -> Dictionary:
	if _geo.has(g):
		return _geo[g]
	var pos: PackedVector3Array = g.position().vec3_array()
	var na = g.get_attribute("normal")
	var nor: PackedVector3Array = na.vec3_array() if na != null and na.count() == pos.size() else PackedVector3Array()
	var idx: PackedInt32Array = g.index if g.indexed else _range(pos.size())
	if g.draw_count >= 0:
		idx = idx.slice(g.draw_start, g.draw_start + g.draw_count)
	idx = _flipped(idx)
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
	var ca = g.get_attribute("color")
	var cols = null
	if ca != null and ca.count() == pos.size() and ca.item_size >= 3:
		cols = PackedColorArray()
		cols.resize(pos.size())
		for i in pos.size():
			cols[i] = Color(ca.get_x(i), ca.get_y(i), ca.get_z(i))
	var d := {"id": _geo.size(), "arrays": a, "idx": idx, "aabb": AABB(lo, hi - lo), "closed": closed, "cols": cols}
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


## three.js takes counter-clockwise triangles as front faces and Godot clockwise ones.
static func _flipped(ix: PackedInt32Array) -> PackedInt32Array:
	var out := ix.duplicate()
	for t in range(0, out.size() - 2, 3):
		out[t + 1] = ix[t + 2]
		out[t + 2] = ix[t + 1]
	return out


static func _range(n: int) -> PackedInt32Array:
	var r := PackedInt32Array()
	r.resize(n)
	for i in n:
		r[i] = i
	return r


static func _tri_count(a: Array) -> int:
	var ix = a[Mesh.ARRAY_INDEX]
	return (ix.size() if ix != null else a[Mesh.ARRAY_VERTEX].size()) / 3
