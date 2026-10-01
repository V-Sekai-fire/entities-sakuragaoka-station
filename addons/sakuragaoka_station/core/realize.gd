# The port's three-shaped scene graph as Godot nodes, batched as src/core/batch2.js batches it
# (48 m cells near the play area, 200 m beyond 150 m) and shaded with MToon, toon ones through core/ramp/. MToon
# reads its colour from a texture, so each face's colour is an index into a palette texture carried
# in UV; CSG keeps UV through a union where it would drop vertex colour, and every closed solid of
# a cell goes through CSG. A cell keeps the union only when it comes out no larger than its solids.
# Open surfaces are appended as they are, instanced meshes become MultiMeshes at their material's
# colour. A keyed canvas texture is drawn by its pack-script mode (core/slug/baked.gd): "mesh" lays
# its baked triangles over the surface through the palette (replacing an alpha-cut card, or as a
# decal over a regular face), "slug" keeps the geometry's own UVs and draws it with the Slug MToon
# variant (core/slug/), "mean" (or a key nowhere in the pack) takes the texture's mean colour.
# Alpha-cut cards with no Slug or mesh form wait.
#   realize(ctx, root); await one process frame (CSG computes then); finish()
extends RefCounted

const T = preload("res://addons/sakuragaoka_station/core/three.gd")
const Svg = preload("res://addons/sakuragaoka_station/core/svg.gd")
const SakuraTree = preload("res://addons/sakuragaoka_station/world/sakura/tree.gd")
const Shaders = preload("res://addons/sakuragaoka_station/world/environment/shaders.gd")
const SlugAtlas = preload("res://addons/sakuragaoka_station/core/slug/atlas.gd")
const Baked = preload("res://addons/sakuragaoka_station/core/slug/baked.gd")
const Kernels = preload("res://addons/sakuragaoka_station/core/slug/kernels.gd")
const SLUG := "res://addons/sakuragaoka_station/core/slug/"
const RAMP := "res://addons/sakuragaoka_station/core/ramp/"
const RampSakura = preload("res://addons/sakuragaoka_station/core/ramp/sakura.gd")

const MTOON := "res://addons/Godot-MToon-Shader/"
## Each keyed canvas texture's mean linear colour, read from the original's canvases by its
## tools/texture_means.mjs: a textured surface takes it until Slug draws the texture itself.
const MEANS := "res://addons/sakuragaoka_station/core/texture_means.json"
const NEAR_CELL := 48.0
const FAR_CELL := 200.0
const FAR_R := 150.0
const WELD := 10000.0
const PALETTE := 512
## Baked canvas triangles one object may add, its instances counted (a MultiMesh of cards adds its
## card's triangles times its instance count); past it the object's texture is drawn by Slug
## instead, which shows the same vector content on the original geometry's own triangles.
const BAKE_TRI_BUDGET := 4096
const SHADE := Color(0.72, 0.68, 0.82)

var stats := {"meshes": 0, "solids": 0, "surfaces": 0, "single": 0, "instanced": 0, "skipped": 0,
		"held": 0, "blob": 0, "batches": 0, "csg_in": 0, "csg_out": 0, "csg_failed": 0, "csg_raw": 0,
		"manifold": 0, "open": 0, "colours": 0, "instance_tints_dropped": 0,
		"slugged": 0, "fallback": 0, "mode_mesh": 0, "mode_slug": 0, "mode_mean": 0, "baked_cards": 0,
		"baked_decals": 0, "baked_tris": 0, "decal_capped": 0, "ramps": 0, "bake_replaced": 0}
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
var _slug = null
var _baked = null
var _ramps := {}
var _twins := {}
## Triangles drawn, by where they come from (instanced ones times their instance count), and per
## object for the Slug and baked categories; in stats as "tris" and "tri_objects" after finish()
## (tools/tri_budget.gd prints them).
var tris := {}
var tri_objects := {}
## Instanced bakes: [object, texture key, triangles an instance, instances].
var tri_instanced := []
var _mult := 1


func realize(ctx, root: Node3D) -> void:
	_root = root
	_palette_img = Image.create(PALETTE, PALETTE, false, Image.FORMAT_RGBA8)
	_palette_img.fill(Color(1, 0, 1))
	_palette_tex = ImageTexture.create_from_image(_palette_img)
	_slug = SlugAtlas.shared()
	_baked = Baked.shared()
	ctx.scene.update_matrix_world(true)
	_walk(ctx.static_root, false)
	_walk(ctx.dynamic_root, true)


## Realizes the given objects alone, whose world matrices are already current.
func realize_part(objs: Array, root: Node3D) -> void:
	_root = root
	_palette_img = Image.create(PALETTE, PALETTE, false, Image.FORMAT_RGBA8)
	_palette_img.fill(Color(1, 0, 1))
	_palette_tex = ImageTexture.create_from_image(_palette_img)
	_slug = SlugAtlas.shared()
	_baked = Baked.shared()
	for o in objs:
		_walk(o, false)


func _tally(cat: String, n: int, o = null) -> void:
	tris[cat] = tris.get(cat, 0) + n
	if o != null:
		var k := "%s|%s" % [cat, _path(o)]
		tri_objects[k] = tri_objects.get(k, 0) + n


## An object's name with up to two ancestors', for the triangle report.
static func _path(o) -> String:
	var parts := PackedStringArray()
	var n = o
	while n != null and parts.size() < 3:
		parts.insert(0, n.name if n.name != "" else "?")
		n = n.parent()
	return "/".join(parts)


func finish() -> void:
	_palette_tex.update(_palette_img)
	if _baked != null:
		_baked.guest.flush()
	stats.colours = _palette.size()
	stats.ramps = _ramps.size()
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
			_tally("palette CSG cells kept raw", e[2])
			for s in comb.get_children():
				_append(e[1], s.mesh.surface_get_arrays(0), s.transform)
		else:
			stats.csg_out += out
			_tally("palette CSG unions", out)
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
		if b.has("tint"):
			a[Mesh.ARRAY_COLOR] = b.tint
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		am.surface_set_material(0, b.mat)
		var mi := MeshInstance3D.new()
		mi.name = ("batch %s" % key).validate_node_name()
		mi.mesh = am
		if not b.get("cast", true):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(mi)
		stats.batches += 1
	_batches.clear()
	stats["tris"] = tris
	stats["tri_objects"] = tri_objects
	stats["tri_instanced"] = tri_instanced


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
	if m != null and m.alpha_test > 0.0 and m.map != null and (alone or mats.size() > 1) and _mode(m) == "mean":
		stats.mode_mean += 1
		stats.held += 1
		return
	if m != null and m.alpha_test > 0.0 and m.map != null and not alone and mats.size() == 1:
		# an alpha-cut card's shape is its drawn texture: baked triangles, Slug, or it waits
		var md := _mode(m)
		stats["mode_" + md] += 1
		if md == "mean":
			stats.held += 1
			return
		var gd0 := _geo_data(g)
		if md == "mesh" and _bake(o, gd0, gd0.idx, m, true, null):
			return
		if (md == "slug" or md == "mesh") and _slug_ok(m, gd0):
			_slug_batch(o, gd0, m)
			return
		stats.held += 1
		return
	if alone or mats.size() > 1 or m == null or not (m.type == "toon" or m.type == "basic") \
			or m.map != null or m.alpha_map != null or RampSakura.band(m):
		_single(o, alone)
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
		_tally("palette open surfaces", _tri_count(r.a))
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
	var md := _mode(m)
	if md != "":
		stats["mode_" + md] += 1
	var card: bool = m.alpha_test > 0.0 and m.map != null
	if card and md == "mean":
		stats.held += 1
		return
	var gd := _geo_data(o.geometry)
	var mesh: ArrayMesh = null
	var base_tris := 0
	if md == "mesh":
		var am := ArrayMesh.new()
		if not card and not m.transparent:
			var ba: Array = _coloured(gd, gd.idx, _mean_colour(m), gd.cols if m.vertex_colors else null, "g%d" % gd.id).a
			base_tris = _tri_count(ba)
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ba)
			am.surface_set_material(0, _mtoon(m))
		_mult = o.count
		if _bake(o, gd, gd.idx, m, card, am):
			mesh = am
			_tally("palette instanced (under decals)", base_tris * o.count, o if base_tris > 0 else null)
		_mult = 1
	if mesh == null and (md == "slug" or md == "mesh") and _slug_ok(m, gd):
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _slug_arrays(gd, gd.idx, m))
		mesh.surface_set_material(0, _slug_mtoon(m))
		stats.slugged += 1
		_tally("Slug instanced" + (" cards" if card else ""), gd.idx.size() / 3 * o.count, o)
	if mesh == null and card:
		stats.held += 1
		return
	stats.instanced += 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	if mesh != null:
		mm.mesh = mesh
	else:
		if md != "":
			stats.fallback += 1
		mm.mesh = _array_mesh(_coloured(gd, gd.idx, _mean_colour(m), gd.cols if m.vertex_colors else null, "g%d" % gd.id))
		_tally("palette instanced", gd.idx.size() / 3 * o.count)
	mm.instance_count = o.count
	for i in o.count:
		mm.set_instance_transform(i, o.instance_matrix[i])
	if o.instance_color != null:
		stats.instance_tints_dropped += o.count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = o.name if o.name != "" else "instanced"
	mmi.multimesh = mm
	mmi.transform = o.matrix_world
	if mesh == null:
		mmi.material_override = _mtoon(m)
	_root.add_child(mmi)


## One object as its own MeshInstance3D, a surface per material group. Baked canvas triangles of
## its textured groups (cards, decals) join their cell's batch unless the object stays alone.
func _single(o, alone: bool = false) -> void:
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
	var back_cast := false
	for gr in groups:
		var start: int = gr.start
		var count: int = mini(gr.count, gd.idx.size() - start)
		if count <= 0:
			continue
		var m = mats[mini(int(gr.material_index), mats.size() - 1)]
		if m == null:
			m = T.Mat.new()
		var gidx: PackedInt32Array = gd.idx.slice(start, start + count)
		var md := _mode(m)
		if md != "":
			stats["mode_" + md] += 1
		var card: bool = m.alpha_test > 0.0 and m.map != null
		if md == "mesh" and card and _bake(o, gd, gidx, m, true, am if alone else null):
			continue
		if md == "mesh" and not card and _bake(o, gd, gidx, m, false, am if alone else null):
			if m.transparent:
				# a transparent decal surface: its texture's alpha is its shape, which the baked
				# triangles already are, so nothing is drawn under them
				stats.bake_replaced += 1
				continue
			md = "under"
		if (md == "slug" or md == "mesh") and _slug_ok(m, gd):
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _slug_arrays(gd, gidx, m))
			am.surface_set_material(am.get_surface_count() - 1, _slug_mtoon(m))
			stats.slugged += 1
			_tally("Slug single surfaces" + (" (cards)" if card else ""), gidx.size() / 3, o)
			continue
		if card and md != "":
			stats.held += 1
			continue
		if md == "slug" or md == "mesh" or md == "mean":
			stats.fallback += 1
		var colour: Color = _mean_colour(m)
		var blob: bool = m.user_data.has("sakura") and m.user_data["sakura"].get("band", false)
		stats.blob += 1 if blob else 0
		if blob and RampSakura.band_ok(m, g, gd):
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, RampSakura.arrays(g, gd, gidx, _uv_of(colour)), [], {}, RampSakura.FORMAT)
			am.surface_set_material(am.get_surface_count() - 1, _mtoon(m))
			_mtoon(m).set_shader_parameter("ramp_dapple", RampSakura.dapple(o))
			back_cast = back_cast or RampSakura.dapple(o)
			_tally("palette single surfaces", gidx.size() / 3)
			continue
		var cols = _blob_cols(g, gd) if blob else (gd.cols if m.vertex_colors else null)
		var r := _coloured(gd, gidx, colour, cols, "g%d:%d" % [gd.id, start])
		_tally("palette single surfaces" + (" (under decals)" if md == "under" else ""), _tri_count(r.a), o if md == "under" else null)
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r.a)
		am.surface_set_material(am.get_surface_count() - 1, _mtoon(m))
	if am.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = o.name if o.name != "" else "mesh"
	mi.mesh = am
	mi.transform = o.matrix_world
	if back_cast:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
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
	var split := Kernels.split_coloured(pos, nor, idx, cols, colour)
	var p2: PackedVector3Array = split[0]
	var fc: PackedColorArray = split[2]
	var n := p2.size()
	var uv := PackedVector2Array()
	uv.resize(n)
	for f in fc.size():
		var u := _uv_of(fc[f])
		uv[f * 3] = u
		uv[f * 3 + 1] = u
		uv[f * 3 + 2] = u
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = p2
	if nor != null:
		a[Mesh.ARRAY_NORMAL] = split[1]
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
func _uv_of(c: Color, alpha: float = 1.0) -> Vector2:
	var s := c.linear_to_srgb()
	var a8 := clampi(roundi(alpha * 255.0), 0, 255)
	var k := (clampi(roundi(s.r * 255.0), 0, 255) << 16) | (clampi(roundi(s.g * 255.0), 0, 255) << 8) \
			| clampi(roundi(s.b * 255.0), 0, 255) | ((255 - a8) << 24)
	var i = _palette.get(k)
	if i == null:
		i = mini(_palette.size(), PALETTE * PALETTE - 1)
		_palette[k] = i
		_palette_img.set_pixel(i % PALETTE, i / PALETTE, Color8((k >> 16) & 255, (k >> 8) & 255, k & 255, a8))
	return Vector2((i % PALETTE + 0.5) / PALETTE, (i / PALETTE + 0.5) / PALETTE)


## A blossom mass's colour attribute is (tone, peach + 2 * palette, shading normal y); its colour is
## the tone's band in that palette, mixed toward peach. The world-space noise on the band edges and
## the shading normal are not carried.
func _blob_cols(g, gd: Dictionary) -> PackedColorArray:
	if gd.has("blob"):
		return gd.blob
	var ca = g.get_attribute("color")
	var bands: Dictionary = SakuraTree.BANDS
	var bn := PackedColorArray(bands.normal.map(func(h): return Color.html(h).srgb_to_linear()))
	var bw := PackedColorArray(bands.weeping.map(func(h): return Color.html(h).srgb_to_linear()))
	var pe := Color.html(bands.peach).srgb_to_linear()
	var out := Kernels.blob_cols(ca.array, ca.item_size, bn, bw, pe)
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
	if m.user_data.has("distant"):
		return m.key
	var s: Dictionary = m.user_data.get("sakura", {})
	return "%s|%s|%s|%.3f|%.3f|%s|%.2f|%s%s%s" % [m.type, m.side, m.transparent, m.opacity, m.alpha_test,
			m.emissive.to_html(false), m.emissive_intensity, s.get("rim", 0), "|ov" if m.user_data.get("overlay", false) else "",
			_ramp_key(m)]


## materials.js toon()'s paint (0.05 unless given); other toon materials have no paint patch, so 0.
static func _ramp_paint(m) -> float:
	return float(m.user_data.get("toon", {}).get("paint", 0.0))


static func _ramp_flip(m) -> bool:
	return not bool(m.user_data.get("sakura", {}).get("noFlip", false))


static func _ramp_key(m) -> String:
	if m.type != "toon":
		return ""
	return "|p%.4f%s" % [_ramp_paint(m), "" if _ramp_flip(m) else "|nf"]


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
	if b.has("tint"):
		b.tint.append_array(a[Mesh.ARRAY_COLOR])
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
	if m.type == "shader":
		var custom := Shaders.material(m, _palette_tex)
		if custom != null:
			_materials[k] = custom
			return custom
	var sm := ShaderMaterial.new()
	if m.type == "toon":
		sm.shader = load(RAMP + _variant(m, "mtoon_ramp_sakura" if RampSakura.wants(m) else "mtoon_ramp") + ".gdshader")
	else:
		sm.shader = load(MTOON + _variant(m, "mtoon") + ".gdshader")
	sm.set_shader_parameter("_MainTex", _palette_tex)
	sm.set_shader_parameter("_ShadeTexture", _palette_tex)
	_toon_params(sm, m)
	if RampSakura.wants(m):
		RampSakura.params(sm, m, _slug)
	if m.type == "basic":
		sm.set_shader_parameter("_EmissionMap", _palette_tex)
	_materials[k] = sm
	return sm


## MToon for a material whose canvas texture Slug draws: the texture at the geometry's own UVs,
## tinted per vertex (COLOR); an unlit material shows it as emission.
func _slug_mtoon(m) -> ShaderMaterial:
	var k := _mat_key(m) + "|" + _slug_mat_key(m)
	if _materials.has(k):
		return _materials[k]
	var sm := ShaderMaterial.new()
	var sakura := RampSakura.wants(m, true)
	sm.shader = load(SLUG + _variant(m, "mtoon_slug_sakura" if sakura else "mtoon_slug") + ".gdshader")
	_toon_params(sm, m)
	if sakura:
		RampSakura.params(sm, m, _slug)
	if m.type == "basic":
		sm.set_shader_parameter("slug_emission", true)
	if _in_atlas(m.map):
		_bind(sm, m.map, "")
	else:
		sm.set_shader_parameter("slug_has_map", false)
		_bind(sm, m.alpha_map, "")
	if _in_atlas(m.alpha_map):
		_bind(sm, m.alpha_map, "alpha_")
	_materials[k] = sm
	return sm


static func _variant(m, base: String) -> String:
	var v := base
	if m.transparent:
		v += "_trans"
	elif m.alpha_test > 0.0:
		v += "_cutout"
	if m.side != "front":
		v += "_cull_off"
	return v


func _toon_params(sm: ShaderMaterial, m) -> void:
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
		sm.set_shader_parameter("_EmissionColor", Color(1, 1, 1))
	elif m.emissive != Color(0, 0, 0):
		sm.set_shader_parameter("_EmissionColor", (m.emissive * m.emissive_intensity).linear_to_srgb())
	if m.type == "toon":
		sm.set_shader_parameter("ramp_paint", _ramp_paint(m))
		sm.set_shader_parameter("ramp_flip", _ramp_flip(m))
	if m.user_data.get("overlay", false):
		sm.render_priority = 1


# ------------------------------------------------------------------------------ canvas textures

static func _tex_key(t) -> String:
	return str(t.user_data.get("key", "")) if t != null else ""


static func _wraps(t) -> bool:
	return t != null and t.get("wrap_s") == "repeat"


## How a material's canvas texture is drawn: "" untextured, else "mesh", "slug" or "mean". An
## alpha-cut foliage card in the atlas is always cut out by Slug at runtime; otherwise the bake's
## recommendation wins, "mesh" needing a bake without radial paints and a material without an alpha
## map or an opacity under 1 (else Slug, else mean); with none, or "stamp", Slug draws an atlas key.
func _mode(m) -> String:
	if m == null or (m.map == null and m.alpha_map == null):
		return ""
	if m.user_data.has("draw_mode"):
		# calibration only (tools/engine_floor.gd): draw this material's texture one way
		return str(m.user_data["draw_mode"])
	var key := _tex_key(m.map if m.map != null else m.alpha_map)
	var in_atlas := _in_atlas(m.map) or _in_atlas(m.alpha_map)
	if in_atlas and _foliage(m):
		return "slug"
	var want: String = _baked.mode(key) if _baked != null and key != "" else ""
	# a bake carries one key's colours and shape: an alpha map (another texture's green) or a
	# material opacity under 1 cannot be laid on it, so those surfaces are drawn by Slug
	var bakeable: bool = m.alpha_map == null and not (m.transparent and m.opacity < 0.999)
	if want == "mesh" and bakeable:
		var bm = _baked.get_mesh(key)
		if bm != null and not bm.radial:
			return "mesh"
	elif want == "mean":
		return "mean"
	return "slug" if in_atlas else "mean"


static func _foliage(m) -> bool:
	return m.alpha_test > 0.0 and m.side == "double" and m.user_data.has("sakura")


func _in_atlas(t) -> bool:
	return t != null and _slug != null and _slug.has(_tex_key(t))


func _slug_ok(m, gd: Dictionary) -> bool:
	return gd.uv.size() > 0 and (_in_atlas(m.map) or _in_atlas(m.alpha_map))


## The colour a textured surface takes when its texture is not drawn: a sign's background, else
## the texture's mean, times the material's colour.
func _mean_colour(m) -> Color:
	var colour: Color = m.color
	var bg = Svg.sign_colour(m.map)
	if bg != null:
		colour *= bg
	elif m.map != null and _means.has(_tex_key(m.map)):
		var mc: Array = _means[_tex_key(m.map)]
		colour *= Color(mc[0], mc[1], mc[2])
	return colour


func _slug_mat_key(m) -> String:
	var parts := []
	for t in [m.map, m.alpha_map]:
		parts.append("" if t == null else "%s:%s:%s:%s" % [_tex_key(t), t.repeat, t.offset, _wraps(t)])
	return "slug|" + "|".join(parts)


func _bind(sm: ShaderMaterial, t, prefix: String) -> void:
	_slug.bind(sm, _slug.key_info(_tex_key(t), t.width, t.height), t.repeat, t.offset, _wraps(t), prefix)


## The geometry's own arrays and UVs over idx, its tint (material colour times vertex colour) as
## sRGB-encoded vertex colour: 8 bits a channel like the palette, decoded by mtoon_slug.gdshaderinc.
func _slug_arrays(gd: Dictionary, idx: PackedInt32Array, m) -> Array:
	var a: Array = gd.arrays.duplicate()
	a[Mesh.ARRAY_TEX_UV] = gd.uv
	a[Mesh.ARRAY_INDEX] = idx
	var tint: Color = m.color
	if m.map != null and not _in_atlas(m.map):
		tint = _mean_colour(m)
	var cols = gd.cols if m.vertex_colors else null
	var n: int = gd.uv.size()
	var c := PackedColorArray()
	c.resize(n)
	var ts := Color(tint.r, tint.g, tint.b).clamp().linear_to_srgb()
	for i in n:
		c[i] = ts if cols == null else Color(tint.r * cols[i].r, tint.g * cols[i].g, tint.b * cols[i].b).clamp().linear_to_srgb()
	a[Mesh.ARRAY_COLOR] = c
	return a


## A Slug-drawn surface into its cell's batch for its material and texture.
func _slug_batch(o, gd: Dictionary, m) -> void:
	var cast: bool = o.cast_shadow or not _foliage(m)
	var key := _cell(o, gd) + "|" + _mat_key(m) + "|" + _slug_mat_key(m) + ("" if cast else "|nc")
	if not _batches.has(key):
		_batches[key] = {"pos": PackedVector3Array(), "nor": PackedVector3Array(), "uv": PackedVector2Array(),
				"idx": PackedInt32Array(), "tint": PackedColorArray(), "mat": _slug_mtoon(m), "cast": cast}
	_append(key, _slug_arrays(gd, gd.idx, m), o.matrix_world)
	_tally("Slug cards (batched)", gd.idx.size() / 3, o)
	stats.slugged += 1
	stats.surfaces += 1


## The baked triangles of m's texture over the faces idx of a geometry, clipped by the guest to
## each face's UV footprint: in place of a card (unlifted, cutout bake), or as a decal over a
## regular surface. They go through the palette (paint colour times material colour;
## a linear gradient as a palette ramp row) into the cell's batch, or into am when given; a
## translucent overlay goes to a transparent twin drawn after. False when there is nothing to lay
## or a decal passes its caps.
func _bake(o, gd: Dictionary, idx: PackedInt32Array, m, card: bool, am) -> bool:
	var t = m.map if m.map != null else m.alpha_map
	var bm = _baked.get_mesh(_tex_key(t)) if _baked != null else null
	if bm == null or gd.uv.is_empty():
		return false
	var src := {"pos": gd.arrays[Mesh.ARRAY_VERTEX], "nor": gd.nor, "uv": gd.uv, "idx": idx}
	var xf := Vector4(t.repeat.x, t.repeat.y, t.offset.x, t.offset.y)
	# the guest stops at the cap: the per-decal cap, or this object's share of the budget per instance
	var cap := mini(Baked.DECAL_TRI_CAP, BAKE_TRI_BUDGET / maxi(_mult, 1))
	if cap < 1:
		stats.decal_capped += 1
		return false
	var r: Dictionary
	if card:
		# replaced, not overlaid: no lift, and a cutout bake at the card's alpha_test
		r = _baked.map_decal(_tex_key(t), src, xf, _wraps(t), 0.0, m.alpha_test, cap)
	else:
		var det := absf(o.matrix_world.basis.determinant())
		r = _baked.map_decal(_tex_key(t), src, xf, _wraps(t), 1.0 / pow(det, 1.0 / 3.0) if det > 1e-12 else 1.0, 0.0, cap)
	if r.get("capped", false):
		stats.decal_capped += 1
		return false
	if r.is_empty():
		return false
	var parts := [[_baked_arrays(r, 0, r.overlay_from, bm, m.color, false), _twin(m, false)],
			[_baked_arrays(r, r.overlay_from, r.tri_paint.size(), bm, m.color, true), _twin(m, true)]]
	for p in parts:
		if p[0] == null:
			continue
		if am != null:
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, p[0])
			am.surface_set_material(am.get_surface_count() - 1, _mtoon(p[1]))
		else:
			var key := _cell(o, gd) + "|" + _mat_key(p[1])
			_batch(key, p[1])
			_append(key, p[0], o.matrix_world)
	if card:
		stats.baked_cards += 1
	else:
		stats.baked_decals += 1
	stats.baked_tris += r.tri_paint.size()
	_tally(("baked cards" if card else "baked decals") + (" (instanced)" if _mult > 1 else ""), r.tri_paint.size() * _mult, o)
	if _mult > 1:
		tri_instanced.append([_path(o), _tex_key(t), r.tri_paint.size(), _mult])
	return true


func _baked_arrays(r: Dictionary, t0: int, t1: int, bm: Dictionary, tint: Color, overlay: bool):
	if t1 <= t0:
		return null
	var n := (t1 - t0) * 3
	var pos: PackedVector3Array = r.pos.slice(t0 * 3, t1 * 3)
	var nor: PackedVector3Array = r.nor.slice(t0 * 3, t1 * 3)
	var uv := PackedVector2Array()
	uv.resize(n)
	var paints: Array = bm.paints
	for t in range(t0, t1):
		var p: Dictionary = paints[clampi(r.tri_paint[t], 0, paints.size() - 1)]
		var o := (t - t0) * 3
		if str(p.get("type", "solid")) == "linear":
			var row := _ramp_row(p, tint, overlay)
			for k in 3:
				uv[o + k] = Vector2((0.5 + clampf(r.param[t * 3 + k].x, 0.0, 1.0) * (PALETTE - 1)) / PALETTE, (row + 0.5) / PALETTE)
		else:
			var c := Baked.paint_colour(p, 0.0)
			var u := _uv_of(Color(c.r * tint.r, c.g * tint.g, c.b * tint.b), c.a if overlay else 1.0)
			for k in 3:
				uv[o + k] = u
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = pos
	a[Mesh.ARRAY_NORMAL] = nor
	a[Mesh.ARRAY_TEX_UV] = uv
	return a


## A palette row (from the bottom up) holding a linear gradient's ramp times the tint, 8-bit sRGB;
## t maps across the row's texel centres, so interpolated UVs reproduce the gradient.
func _ramp_row(p: Dictionary, tint: Color, overlay: bool) -> int:
	var k := "%s|%s|%s" % [JSON.stringify(p.get("stops", [])), tint.to_html(), overlay]
	if _ramps.has(k):
		return _ramps[k]
	var row := PALETTE - 1 - _ramps.size()
	_ramps[k] = row
	var cs := Kernels.ramp_row(p.get("stops", []), tint, overlay, PALETTE)
	for x in PALETTE:
		_palette_img.set_pixel(x, row, cs[x])
	return row


## The palette-path stand-in for a material whose texture is baked: same flags, no texture, opaque
## (or, for the overlay, transparent and drawn after the base).
func _twin(m, overlay: bool):
	var k := "%d|%s" % [m.get_instance_id(), overlay]
	if _twins.has(k):
		return _twins[k]
	var t := T.Mat.new()
	t.type = "basic" if m.type == "basic" else "toon"
	t.color = m.color
	t.side = m.side
	t.emissive = m.emissive
	t.emissive_intensity = m.emissive_intensity
	t.user_data = m.user_data.duplicate()
	if overlay:
		t.user_data["overlay"] = true
	t.transparent = overlay
	t.opacity = 1.0
	t.depth_write = not overlay
	_twins[k] = t
	return t


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
	var ua = g.get_attribute("uv")
	var uv := PackedVector2Array()
	if ua != null and ua.count() == pos.size() and ua.item_size >= 2:
		uv.resize(pos.size())
		for i in pos.size():
			uv[i] = Vector2(ua.get_x(i), ua.get_y(i))
	var d := {"id": _geo.size(), "arrays": a, "idx": idx, "aabb": AABB(lo, hi - lo), "closed": closed, "cols": cols,
			"uv": uv, "nor": nor if nor.size() == pos.size() else PackedVector3Array()}
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
