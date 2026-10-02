# The realized station as an OpenUSD intermediate for CPU contact sheets: every mesh and MultiMesh
# baked to world space, Y-up metres, one UsdGeom.Mesh per face colour (the palette texel each face reads).
#   godot --headless --path . --script tools/export_usda.gd -- --out=<scene.usda> [--modules=a,b]
extends SceneTree

const Ctx = preload("res://addons/sakuragaoka_station/core/ctx.gd")
const Realize = preload("res://addons/sakuragaoka_station/core/realize.gd")
const QUANT := 24.0

var _out := "scene.usda"
var _holder: Node3D
var _palette: Image


func _initialize() -> void:
	var mods := PackedStringArray(["environment", "station", "plaza", "sakura"])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--modules="):
			mods = PackedStringArray(a.substr(10).split(","))
	_build.call_deferred(mods)


func _build(mods: PackedStringArray) -> void:
	var ctx = Ctx.new(1)
	for n in mods:
		load("res://addons/sakuragaoka_station/world/%s.gd" % n).new().build(ctx)
	_holder = Node3D.new()
	root.add_child(_holder)
	var r = Realize.new()
	r.realize(ctx, _holder)
	await process_frame
	await process_frame
	r.finish()
	# The palette texture's own copy does not follow update() under the headless renderer.
	_palette = r._palette_img
	_write()


func _write() -> void:
	var groups := {}
	var count := [0, 0]
	_walk(_holder, groups, count)
	var o := FileAccess.open(_out, FileAccess.WRITE)
	if o == null:
		print("export_usda: FAIL cannot write %s" % _out)
		quit(1)
		return
	o.store_line('#usda 1.0\n(\n    defaultPrim = "Scene"\n    metersPerUnit = 1\n    upAxis = "Y"')
	o.store_line('    customLayerData = {\n        string state = "DONE"\n        string status = "%d meshes, %d triangles"\n    }\n)\n' % count)
	o.store_line('def Xform "Scene"\n{')
	var i := 0
	for key in groups:
		_mesh(o, "Part_%d" % i, groups[key])
		i += 1
	o.store_line("}")
	print("export_usda: wrote %s, %d meshes, %d triangles, %d colours" % [_out, count[0], count[1], groups.size()])
	quit(0 if count[1] > 0 else 1)


func _walk(n: Node, groups: Dictionary, count: Array) -> void:
	if n is MeshInstance3D and n.mesh and n.is_visible_in_tree():
		_add(n.mesh, [n.global_transform], groups, count)
	elif n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh and n.is_visible_in_tree():
		var mm: MultiMesh = n.multimesh
		var xs := []
		for k in mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count:
			xs.append(n.global_transform * mm.get_instance_transform(k))
		_add(mm.mesh, xs, groups, count)
	for c in n.get_children():
		_walk(c, groups, count)


func _add(mesh: Mesh, xforms: Array, groups: Dictionary, count: Array) -> void:
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if v.is_empty():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		if not idx is PackedInt32Array or idx.is_empty():
			idx = PackedInt32Array(range(v.size()))
		var face_cols := _face_colours(mesh, s, arr, idx)
		for x: Transform3D in xforms:
			var w := PackedVector3Array()
			w.resize(v.size())
			for k in v.size():
				w[k] = x * v[k]
			for t in idx.size() / 3:
				var c: Color = face_cols[t]
				var key := Vector3i(roundi(c.r * QUANT), roundi(c.g * QUANT), roundi(c.b * QUANT))
				if not groups.has(key):
					groups[key] = {"colour": c, "points": PackedVector3Array(), "faces": PackedInt32Array()}
				var g: Dictionary = groups[key]
				var base: int = g.points.size()
				g.points.append(w[idx[3 * t]])
				g.points.append(w[idx[3 * t + 1]])
				g.points.append(w[idx[3 * t + 2]])
				g.faces.append_array([base, base + 1, base + 2])
		count[0] += xforms.size()
		count[1] += xforms.size() * idx.size() / 3


## Each face's colour: the palette texel under its first vertex's UV (realize.gd's palette), times the
## material's tint; vertex colours or the albedo when there is no palette.
func _face_colours(mesh: Mesh, s: int, arr: Array, idx: PackedInt32Array) -> Array:
	var m := mesh.surface_get_material(s)
	var tint := Color(1, 1, 1)
	var img: Image = null
	if m is ShaderMaterial:
		var t = m.get_shader_parameter("_Color")
		if t is Color:
			tint = t
		var tex = m.get_shader_parameter("_MainTex")
		if tex is Texture2D:
			img = _image(tex)
	elif m is BaseMaterial3D:
		tint = m.albedo_color
		if m.albedo_texture:
			img = _image(m.albedo_texture)
	var uv = arr[Mesh.ARRAY_TEX_UV]
	var cols = arr[Mesh.ARRAY_COLOR]
	var out := []
	out.resize(idx.size() / 3)
	for t in out.size():
		var i: int = idx[3 * t]
		var c := Color(1, 1, 1)
		if img and uv is PackedVector2Array and i < uv.size():
			var p: Vector2 = uv[i]
			c = img.get_pixel(clampi(int(p.x * img.get_width()), 0, img.get_width() - 1),
					clampi(int(p.y * img.get_height()), 0, img.get_height() - 1)).srgb_to_linear()
		elif cols is PackedColorArray and i < cols.size():
			c = cols[i]
		elif not img:
			c = Color(0.7, 0.7, 0.7) if tint == Color(1, 1, 1) else Color(1, 1, 1)
		out[t] = c * tint
	return out


var _images := {}


func _image(tex: Texture2D) -> Image:
	if tex.get_width() == Realize.PALETTE and _palette:
		return _palette
	if not _images.has(tex):
		var img := tex.get_image()
		if img and img.is_compressed():
			img.decompress()
		_images[tex] = img
	return _images[tex]


func _mesh(o: FileAccess, name: String, g: Dictionary) -> void:
	var pts := PackedStringArray()
	for p: Vector3 in g.points:
		pts.append("(%.4f, %.4f, %.4f)" % [p.x, p.y, p.z])
	var f: PackedInt32Array = g.faces
	var idx := PackedStringArray()
	for i in range(0, f.size(), 3):
		idx.append("%d, %d, %d" % [f[i], f[i + 2], f[i + 1]])
	var counts := PackedStringArray()
	counts.resize(f.size() / 3)
	counts.fill("3")
	var c: Color = g.colour
	o.store_line('    def Mesh "%s"\n    {' % name)
	o.store_line("        int[] faceVertexCounts = [%s]" % ", ".join(counts))
	o.store_line("        int[] faceVertexIndices = [%s]" % ", ".join(idx))
	o.store_line("        point3f[] points = [%s]" % ", ".join(pts))
	o.store_line("        color3f[] primvars:displayColor = [(%f, %f, %f)]" % [c.r, c.g, c.b])
	o.store_line('        uniform token subdivisionScheme = "none"\n    }')
