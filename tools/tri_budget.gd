# Where the station's triangles come from (the VR budget question): builds and realizes the station
# as realize_check does and prints
#   by node: palette batches (CSG unions and open surfaces), Slug batches, single meshes per surface
#            material (palette / Slug), MultiMeshes (mesh triangles x instances) per surface material
#   by source (realize.gd's tallies, when it keeps them): palette CSG / open / single / instanced,
#            Slug cards and surfaces, baked cards and decals, instanced variants x instance count
#   the top objects by added triangles (Slug and baked categories, and surfaces drawn under decals)
# Works on older checkouts too (by node only), so HEAD and a branch can be compared.
#   godot --headless --path . --script tools/tri_budget.gd -- [--top=10] [--modules=...]
extends SceneTree

var _st: Node3D
var _top := 10


func _initialize() -> void:
	var mods := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--top="):
			_top = int(a.substr(6))
		elif a.begins_with("--modules="):
			mods = a.substr(10)
	_st = load("res://addons/sakuragaoka_station/station.tscn").instantiate()
	_st.with_environment = false
	if mods != "":
		_st.modules = PackedStringArray(mods.split(","))
	_st.built.connect(_on_built)
	get_root().add_child(_st)


static func _tris(m: Mesh, surface: int) -> int:
	var a := m.surface_get_arrays(surface)
	return (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3


static func _kind(mat) -> String:
	if mat is ShaderMaterial and mat.shader != null:
		var f: String = mat.shader.resource_path.get_file()
		if f.begins_with("mtoon_slug"):
			return "Slug"
		if mat.render_priority > 0:
			return "palette overlay"
	return "palette"


func _on_built(s: Dictionary) -> void:
	var by_node := {}
	var total := 0
	for n in _st.find_children("*", "MeshInstance3D", true, false):
		var batch := str(n.name).begins_with("batch")
		for i in n.mesh.get_surface_count():
			var t := _tris(n.mesh, i)
			var k := "%s %s" % [_kind(n.mesh.surface_get_material(i) if n.mesh.surface_get_material(i) else n.material_override),
					"batches" if batch else "single meshes"]
			by_node[k] = by_node.get(k, 0) + t
			total += t
	for n in _st.find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = n.multimesh
		for i in mm.mesh.get_surface_count():
			var mat = n.material_override if n.material_override != null else mm.mesh.surface_get_material(i)
			var t := _tris(mm.mesh, i) * mm.instance_count
			var k := "%s MultiMeshes" % _kind(mat)
			by_node[k] = by_node.get(k, 0) + t
			total += t
	print("tri_budget: modules %s; %d triangles" % [",".join(s.modules), total])
	var keys := by_node.keys()
	keys.sort_custom(func(a, b): return by_node[a] > by_node[b])
	for k in keys:
		print("tri_budget: node  %-34s %10d" % [k, by_node[k]])
	if s.has("tris"):
		var t: Dictionary = s.tris
		var sum := 0
		var ks := t.keys()
		ks.sort_custom(func(a, b): return t[a] > t[b])
		for k in ks:
			print("tri_budget: source %-42s %10d" % [k, t[k]])
			sum += t[k]
		print("tri_budget: source total %d (by node %d)" % [sum, total])
		var o: Dictionary = s.tri_objects
		var ok := o.keys()
		ok.sort_custom(func(a, b): return o[a] > o[b])
		for i in mini(_top, ok.size()):
			var parts: PackedStringArray = ok[i].split("|")
			print("tri_budget: top %2d %10d  %-36s %s" % [i + 1, o[ok[i]], parts[0], parts[1]])
	if s.has("tri_instanced"):
		var ti: Array = s.tri_instanced
		ti.sort_custom(func(a, b): return a[2] * a[3] > b[2] * b[3])
		for e in ti:
			print("tri_budget: instanced bake %-34s %-22s %6d tris x %6d = %d" % [e[0], e[1], e[2], e[3], e[2] * e[3]])
	quit()
